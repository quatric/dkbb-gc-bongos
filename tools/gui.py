#!/usr/bin/env python3
"""Drag-and-drop GC/Bongos patcher: drop a disc image on the window, done.

Extracts the disc, checks sys/main.dol against the exact bytes these patches
were computed against (build.verify_patches -- refuses to touch a foreign or
already-patched dump instead of guessing), writes the chosen poller variant
plus the DK controller hooks, and rebuilds via wit (Wiimms ISO Tool).

The rebuilt image replaces the original *in place*, keeping its filename and
folder -- USB loaders key off the `/wbfs/<Title> [ID6]/` layout, so a renamed
file next to it can leave the loader unable to find the title. The untouched
original is kept alongside as `<name>.bak`.

Two poller variants (see README for the tradeoff between them):
  autopoll (default) -- programs real SI hardware auto-polling.
  stash              -- doesn't touch SIPOLL; stashes an immediate-transfer
                         response in RAM instead. Try this if autopoll
                         doesn't work on your console.

Needs a dump where codeA-D and the poller are already baked into main.dol --
see build.py's module docstring. A genuinely clean retail dump has none of
that, and verify_patches() will correctly refuse it (POLLER_BODY_RAM isn't
mapped there).
"""
import os
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build
from dol import Dol

try:
    from tkinterdnd2 import DND_FILES, TkinterDnD
    HAVE_DND = True
except ImportError:                                    # fall back to click-to-browse
    HAVE_DND = False

EXPECTED_DISC_ID = 'RDKE01'


def find_wit():
    """A wit bundled with this app (PyInstaller build) wins over PATH."""
    name = 'wit.exe' if os.name == 'nt' else 'wit'
    if getattr(sys, 'frozen', False):
        for base in (getattr(sys, '_MEIPASS', None), os.path.dirname(sys.executable)):
            if base:
                bundled = os.path.join(base, name)
                if os.path.isfile(bundled):
                    return bundled
    return shutil.which('wit')


def find_file(root, name):
    for r, _, files in os.walk(root):
        if name in files:
            return os.path.join(r, name)
    return None


def read_disc_id(fst):
    boot = find_file(fst, 'boot.bin')
    if not boot:
        return None
    with open(boot, 'rb') as f:
        header = f.read(6)
    return header.decode('ascii', 'replace')


def run_patch(image_path, variant, log, done):
    try:
        wit = find_wit()
        if wit is None:
            raise RuntimeError('wit (Wiimms ISO Tool) not found: not bundled with this '
                                'build and not on PATH')

        fmt = '--iso' if image_path.lower().endswith('.iso') else '--wbfs'

        with tempfile.TemporaryDirectory(prefix='dkbb_patch_') as tmp:
            fst = os.path.join(tmp, 'fst')
            log('extracting %s...' % os.path.basename(image_path))
            r = subprocess.run([wit, 'extract', image_path, '--dest', fst,
                                 '--psel', 'data', '--overwrite', '-q'],
                                capture_output=True, text=True)
            if r.returncode:
                raise RuntimeError('extract failed:\n' + (r.stderr or r.stdout))

            disc_id = read_disc_id(fst)
            if not disc_id:
                raise RuntimeError('could not read sys/boot.bin from the extracted disc')
            if disc_id != EXPECTED_DISC_ID:
                raise RuntimeError(
                    'disc id %s is not the supported target (%s, USA)' % (disc_id, EXPECTED_DISC_ID))
            log('disc: %s' % disc_id)

            dol_path = find_file(fst, 'main.dol')
            if not dol_path or os.path.basename(os.path.dirname(dol_path)) != 'sys':
                raise RuntimeError('could not find sys/main.dol in the extracted disc')

            d = Dol(dol_path)
            build.verify_patches(d, variant)

            for va, blob in build.static_patches(variant):
                d.write(va, blob)
            d.save(dol_path)
            log('  patched main.dol (%s poller)' % variant)

            staged = os.path.join(tmp, 'patched.img')
            log('rebuilding...')
            r = subprocess.run([wit, 'copy', fst, '--dest', staged, fmt, '--overwrite', '-q'],
                                capture_output=True, text=True)
            if r.returncode:
                raise RuntimeError('rebuild failed:\n' + (r.stderr or r.stdout))

            # Only touch the user's file once the rebuild has actually succeeded.
            backup = image_path + '.bak'
            if os.path.exists(backup):
                log('  backup already exists, keeping it: %s' % os.path.basename(backup))
            else:
                shutil.copyfile(image_path, backup)
                log('  backed up original -> %s' % os.path.basename(backup))
            shutil.move(staged, image_path)
            log('done: patched in place, %s' % os.path.basename(image_path))
            done(True, image_path)
    except Exception as e:
        log('ERROR: %s' % e)
        done(False, str(e))


BASE = TkinterDnD.Tk if HAVE_DND else tk.Tk


class App(BASE):
    def __init__(self):
        super().__init__()
        self.title('DKBB GC/Bongos Patcher')
        self.geometry('560x460')
        self.msgq = queue.Queue()
        self.busy = False

        self.variant = tk.StringVar(value='autopoll')
        variant_row = tk.Frame(self)
        variant_row.pack(fill='x', padx=10, pady=(10, 0))
        tk.Label(variant_row, text='Poller:').pack(side='left')
        ttk.Radiobutton(variant_row, text='auto-poll (default)', variable=self.variant,
                         value='autopoll').pack(side='left', padx=(8, 0))
        ttk.Radiobutton(variant_row, text='stash (fallback)', variable=self.variant,
                         value='stash').pack(side='left', padx=(8, 0))

        hint = ('Drop a .wbfs or .iso here\n\n(or click to choose one)'
                if HAVE_DND else 'Click to choose a .wbfs or .iso')
        self.drop = tk.Label(self, text=hint, relief='ridge', bd=2,
                             padx=10, pady=30, cursor='hand2')
        self.drop.pack(fill='x', padx=10, pady=10)
        self.drop.bind('<Button-1>', lambda e: self.pick())

        if HAVE_DND:
            self.drop.drop_target_register(DND_FILES)
            self.drop.dnd_bind('<<Drop>>', self.on_drop)

        tk.Label(self, text='The original is kept alongside as <name>.bak',
                 fg='#666').pack()

        self.log = tk.Text(self, height=14, state='disabled', wrap='word')
        self.log.pack(fill='both', expand=True, padx=10, pady=10)

        self.after(100, self.poll_queue)

    def on_drop(self, event):
        paths = self.tk.splitlist(event.data)      # handles {braced paths with spaces}
        if paths:
            self.start(paths[0])

    def pick(self):
        if self.busy:
            return
        p = filedialog.askopenfilename(
            title='Select disc image',
            filetypes=[('Wii disc image', '*.wbfs *.iso'), ('All files', '*')])
        if p:
            self.start(p)

    def append_log(self, text):
        self.log.configure(state='normal')
        self.log.insert('end', text + '\n')
        self.log.see('end')
        self.log.configure(state='disabled')

    def poll_queue(self):
        try:
            while True:
                kind, payload = self.msgq.get_nowait()
                if kind == 'log':
                    self.append_log(payload)
                elif kind == 'done':
                    ok, msg = payload
                    self.busy = False
                    self.drop.configure(state='normal')
                    if ok:
                        messagebox.showinfo('Done', 'Patched in place:\n%s' % msg)
                    else:
                        messagebox.showerror('Patch failed', msg)
        except queue.Empty:
            pass
        self.after(100, self.poll_queue)

    def start(self, image_path):
        if self.busy:
            return
        if not os.path.isfile(image_path):
            messagebox.showerror('Not a file', '%s is not a file.' % image_path)
            return

        self.busy = True
        self.drop.configure(state='disabled')
        self.log.configure(state='normal')
        self.log.delete('1.0', 'end')
        self.log.configure(state='disabled')

        threading.Thread(
            target=run_patch,
            args=(image_path, self.variant.get(),
                  lambda t: self.msgq.put(('log', t)),
                  lambda ok, m: self.msgq.put(('done', (ok, m)))),
            daemon=True,
        ).start()


if __name__ == '__main__':
    App().mainloop()
