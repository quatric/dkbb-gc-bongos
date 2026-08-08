#!/usr/bin/env python3
"""Finish Classic Controller support in codes/RDKE01.ini.

The working sources for codeA-D were lost (see src/README.md), so this edits
the shipped Gecko code text at the word level, asserting every pre-image
before it writes. Run once; the result is committed.

Three independent changes, each of which leaves the GameCube path untouched:

  codeA  D-pad RIGHT never worked. The test is `andis. r0,r9,0x8000`, i.e.
         r9 & 0x80000000 -- but r9 is the Classic button word loaded by
         `lwz r9,0x60(r31)`, which KPADiRead fills from a zero-extended
         u16, so bit 31 is never set. CC RIGHT is 0x8000, so the test
         should be `andi.`. One-word fix.

  codeC  Its whole Classic Controller branch reads the wrong addresses.
         In codeC, r30 is the channel base + 0x60 (proved by its own
         channel-detect constants: it compares r30 against 0x803C9220 /
         0x803C9C68 / 0x803CA18C, each exactly base+0x60), but the branch
         was written as though r30 were the bare base. So the extension-type
         probe read base+0xBC instead of base+0x5c, the stick reads hit
         base+0xCC/0xD0 instead of base+0x6c/0x70, and the float scratch
         landed at base+0x168 -- inside the KPAD sample ring buffer, which
         starts at +0x110. Rebased, with the scratch moved onto codeC's own
         stack frame (0x38/0x3c of a 0x40-byte frame that only uses 0x08-0x37).

  codeB  Had no Classic Controller branch at all -- this is the actual
         "drumming and jump" gap. Appends one that synthesises the same two
         registers the existing GC drum state machine consumes, so all the
         edge-trigger/oscillation logic downstream is reused verbatim.

Sizes: only codeB grows, and only the .ini form is affected. The DOL patcher
(build.py) touches the SI poller and nothing else, so a baked main.dol is
unaffected by any of this.
"""
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
INI = os.path.join(HERE, '..', 'codes', 'RDKE01.ini')

CODEB = 0x80246588
CODEA = 0x80248090
CODEC = 0x8024791C

# ---------------------------------------------------------------- codeA fix
# (word index, old, new) -- indices are into the code's body word list.
CODEA_PATCHES = [
    (26, 0x75208000, 0x71208000),   # andis. r0,r9,0x8000 -> andi.
]

# ---------------------------------------------------------------- codeC fix
# r30 = channel base + 0x60, so every base-relative displacement drops 0x60.
# The float<->int scratch moves to the hook's own stack frame instead of
# KPAD +0x108/+0x10c (which overruns into +0x10e/+0x10f, the ring index
# and sample count that KPADiRead consumes).
CODEC_PATCHES = [
    (32, 0x895E005C, 0x895EFFFC),   # lbz  r10,0x5c(r30)  -> lbz  r10,-4(r30)
    (36, 0x915E0108, 0x9141003C),   # stw  r10,0x108(r30) -> stw  r10,0x3c(r1)
    (37, 0xC03E0108, 0xC021003C),   # lfs  f1,0x108(r30)  -> lfs  f1,0x3c(r1)
    (38, 0xC05E006C, 0xC05E000C),   # lfs  f2,0x6c(r30)   -> lfs  f2,0xc(r30)
    (41, 0xD85E0108, 0xD8410038),   # stfd f2,0x108(r30)  -> stfd f2,0x38(r1)
    (42, 0x809E010C, 0x8081003C),   # lwz  r4,0x10c(r30)  -> lwz  r4,0x3c(r1)
    (43, 0xC07E0070, 0xC07E0010),   # lfs  f3,0x70(r30)   -> lfs  f3,0x10(r30)
    (46, 0xD87E0108, 0xD8610038),   # stfd f3,0x108(r30)  -> stfd f3,0x38(r1)
    (47, 0x80BE010C, 0x80A1003C),   # lwz  r5,0x10c(r30)  -> lwz  r5,0x3c(r1)
]

# ---------------------------------------------------------------- codeB fix
# The three `b <fan-in>` at the tail of the channel-detect ladder get
# redirected through the new Classic Controller check. Channel 3 reaches the
# fan-in by fallthrough and so stays GameCube-only -- channel 1 detection is
# already broken upstream (`ori rX,rX,0x524` where an add was meant), which
# is why 4-player is not shipped.
CODEB_ENTRY_BRANCHES = [36, 38, 40]     # currently b +0x18 / +0x10 / +0x08
CODEB_FANIN = 42                        # mulli r10,r3,0xc
CODEB_COMMON = 53                       # lis r7,0x4120 -- shared drum logic
CODEB_ORIG_IDX = 132                    # lwz r0,0x44(r1), the hooked instruction

CC_ASM = os.path.join(HERE, '..', 'src', 'codeB_cc.s')


def parse_ini(path):
    lines = [l.rstrip('\n') for l in open(path)]
    head, codes, i = [], [], 0
    while i < len(lines) and not lines[i].startswith('C2'):
        head.append(lines[i]); i += 1
    while i < len(lines):
        if not lines[i].strip():
            i += 1; continue
        hdr = lines[i].split()
        addr = int(hdr[0][2:], 16) | 0x80000000
        nn = int(hdr[1], 16)
        words = []
        for j in range(nn):
            i += 1
            a, b = lines[i].split()
            words += [int(a, 16), int(b, 16)]
        codes.append([addr, words])
        i += 1
    return head, codes


def emit_ini(path, head, codes):
    out = list(head)
    for addr, words in codes:
        assert len(words) % 2 == 0, f'{addr:#x}: odd word count {len(words)}'
        out.append(f'C2{addr & 0x01FFFFFF:06X} {len(words)//2:08X}')
        for k in range(0, len(words), 2):
            out.append(f'{words[k]:08X} {words[k+1]:08X}')
    open(path, 'w').write('\n'.join(out) + '\n')


def apply(words, patches, label):
    for idx, old, new in patches:
        got = words[idx]
        if got != old:
            raise AssertionError(
                f'{label} word {idx}: expected {old:#010X}, found {got:#010X} '
                f'-- this is not the code these offsets were computed against')
        words[idx] = new
        print(f'  {label} [{idx:3d}] {old:08X} -> {new:08X}')


def branch(from_idx, to_idx):
    off = (to_idx - from_idx) * 4
    assert -0x2000000 <= off < 0x2000000
    return 0x48000000 | (off & 0x03FFFFFC)


def assemble(path):
    with tempfile.TemporaryDirectory() as tmp:
        o = os.path.join(tmp, 'a.o')
        b = os.path.join(tmp, 'a.bin')
        dk = '/opt/devkitpro/devkitPPC/bin'
        subprocess.run([f'{dk}/powerpc-eabi-as', '-mbig', '-mgekko', '-o', o, path], check=True)
        subprocess.run([f'{dk}/powerpc-eabi-objcopy', '-O', 'binary', o, b], check=True)
        data = open(b, 'rb').read()
    return list(struct.unpack('>%dI' % (len(data) // 4), data))


def main():
    head, codes = parse_ini(INI)
    by_addr = {a: w for a, w in codes}
    print(f'parsed {len(codes)} codes from {os.path.relpath(INI, HERE)}')

    print('\ncodeA -- Classic Controller D-pad RIGHT:')
    apply(by_addr[CODEA], CODEA_PATCHES, 'codeA')

    print('\ncodeC -- rebase Classic Controller branch (r30 = base+0x60):')
    apply(by_addr[CODEC], CODEC_PATCHES, 'codeC')

    print('\ncodeB -- append Classic Controller drum branch:')
    b = by_addr[CODEB]
    assert len(b) == 134, f'codeB is {len(b)} words, expected 134'
    assert b[CODEB_ORIG_IDX] == 0x80010044, f'codeB[{CODEB_ORIG_IDX}] is not the hooked instruction'
    assert b[CODEB_FANIN] == 0x1D43000C, 'codeB fan-in is not `mulli r10,r3,0xc`'
    assert b[CODEB_COMMON] == 0x3CE04120, 'codeB common is not `lis r7,0x4120`'

    cc = assemble(CC_ASM)
    print(f'  assembled {CC_ASM.split("/")[-1]}: {len(cc)} words')
    assert len(cc) == 30, f'CC block is {len(cc)} words, expected 30'

    # new layout: [0..131] [b over_cc] [cc x30] [orig] [nop pad] [spare]
    jump_idx = 132
    cc_idx = 133
    orig_idx = cc_idx + len(cc)          # 163
    body = b[:132]
    body.append(branch(jump_idx, orig_idx))
    body += cc
    body.append(b[CODEB_ORIG_IDX])       # hooked instruction
    body.append(0x60000000)              # pad to an even word count
    body.append(0x60000000)              # spare: handler overwrites with `b back`

    # patch the CC block's two exits
    body[cc_idx + 28] = branch(cc_idx + 28, CODEB_COMMON)
    body[cc_idx + 29] = branch(cc_idx + 29, CODEB_FANIN)
    print(f'  [{cc_idx+28:3d}] b common  -> {body[cc_idx+28]:08X}')
    print(f'  [{cc_idx+29:3d}] b gc_si   -> {body[cc_idx+29]:08X}')

    # redirect the channel-detect fan-in through the CC check
    for idx in CODEB_ENTRY_BRANCHES:
        old = body[idx]
        assert (old >> 26) == 18, f'codeB[{idx}] is not a branch: {old:#010X}'
        body[idx] = branch(idx, cc_idx)
        print(f'  [{idx:3d}] {old:08X} -> {body[idx]:08X}  (b cc_check)')

    assert len(body) % 2 == 0
    print(f'  codeB: 134 -> {len(body)} words, NN {len(b)//2:#04x} -> {len(body)//2:#04x}')
    by_addr[CODEB][:] = body

    emit_ini(INI, head, codes)
    print(f'\nwrote {INI}')


if __name__ == '__main__':
    main()
