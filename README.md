# Donkey Kong Barrel Blast — Classic Controller, GameCube Controller & DK Bongos support

Gecko codes that let you play the Wii release of **Donkey Kong Barrel Blast**
(`RDKE01`, USA) with a **Classic Controller**, a **GameCube controller**, or a set
of **DK Bongos** plugged into the console's GameCube ports.

The Wii version of Barrel Blast is a motion-controlled game: everything is driven
by Wii Remote / Nunchuk shake detection, and the game has no GameCube input path
at all. These codes hook the KPAD library, poll the Serial Interface directly, and
synthesise the motion the game is looking for from GameCube button and stick state.

> **⚠️ Work in progress — console behavior not yet hardware-confirmed.**
> The four button/motion/stick hooks are known to work in Dolphin. An SI
> auto-polling hook is now included (see "Reading the GameCube controller"
> below) that's designed to make the same codes work on real hardware — its
> hook-installation has been verified in a debugger against a running Dolphin
> instance, but it has not yet been confirmed on real hardware or observed
> actually firing mid-gameplay. Use `tools/gui.py` (see "Patcher tool" below)
> to build a test image. Jump (the "pull up on both bongos" gesture) is still
> driven by a placeholder acceleration vector rather than captured
> real-controller values. Classic Controller support is **buttons only** so
> far — see below. Treat this as a work in progress, not a finished hack.

## Classic Controller

This is also groundwork toward playing the game on a **Classic Controller**, and
that part is the least finished.

What works today is the button layer: hook 1 checks the KPAD extension type
(`cmpwi r4, 2` — Classic Controller) and, when it matches, folds the Classic
Controller's button word into the Wii Remote button bits (`r7`) the game actually
reads, before the composing instruction runs:

| Classic Controller | Reported as Wii Remote |
| --- | --- |
| A | A |
| B | B |
| D-pad Up / Down / Left / Right | D-pad Up / Down / Left / Right |
| + | + |
| − | − |
| HOME | HOME |

That is enough to drive menus and every button-driven part of the game from a
Classic Controller. What is **not** done is the motion half: a Classic Controller
has no accelerometer, so there is nothing to derive a drum hit or a jump from, and
the accelerometer / stick / IR hooks below are currently gated to the GameCube
path only. Drumming and jumping still need a Wii Remote, a GameCube pad, or
Bongos. Extending the synthesised-motion logic to trigger off Classic Controller
buttons is the obvious next step and is not implemented yet.

## What is mapped

GameCube controller / DK Bongos:

| Physical input | In-game action |
| --- | --- |
| A / X (right bongo) | Right drum hit |
| B / Y (left bongo) | Left drum hit |
| R / Z (clap) | Both drums — jump / boost |
| L, R analog triggers | Left / right drum (hair-trigger, threshold ≈ 48) |
| Control stick | Nunchuk stick (character movement), with a ±16 deadzone |
| C-stick | IR pointer position |
| Start, D-pad, face buttons | Wii Remote / Nunchuk button equivalents |

Player 1 should still have a real Wii Remote + Nunchuk connected — the game gates
on a connected controller before it will start a race. The GameCube pad is an
*alternate* whose input is injected on top.

## Usage

### Dolphin

Copy `codes/RDKE01.ini` to your Dolphin `GameSettings` folder:

- macOS: `~/Library/Application Support/Dolphin/GameSettings/`
- Windows: `%USERPROFILE%\Documents\Dolphin Emulator\GameSettings\`
- Linux: `~/.config/dolphin-emu/GameSettings/`

Then enable the code under **Properties → Gecko Codes**, and set GameCube Port 1
to your adapter **before** booting. Avoid hot-plugging mid-game.

### Console

Load the codes with any Gecko-code loader (Riivolution patch, Gecko OS, a loader
with cheat support). Only the USA revision (`RDKE01`) is supported — the hook
addresses are hardcoded and will crash on other regions.

### Patcher tool

`tools/gui.py` bakes the codes directly into a copy of your own dump instead
of relying on a Gecko loader at runtime — drop a `.wbfs` or `.iso` on the
window (or a prebuilt binary from a [release](../../releases), which bundles
[Wiimms ISO Tool](https://wit.wiimm.de/) so you don't need to install it) and
it patches `sys/main.dol` in place, keeping the original alongside as
`<name>.bak`. Pick `autopoll` (default) or `stash` from the window before
dropping the image — see "Reading the GameCube controller" above for what the
two variants actually do differently.

**The tool never ships or touches anyone else's copy of the game** — it only
operates on a disc image you already have locally. `tools/build.py` is the
same patch logic as a standalone module (`static_patches()`/
`poller_gecko_lines()`) if you'd rather drive it from a script; it checks the
base DOL against the exact bytes these offsets were computed against before
writing anything, so a foreign or already-patched dump fails loudly instead
of silently corrupting.

## Sources

`src/` holds the PowerPC assembly and a `build.py` that turns it into Gecko
codes — but **it does not build the codeA-D codes shipped here**. It is a
later revision in which GameCube detection regressed, and it is included only
because the sources for the working build were lost. Read
[`src/README.md`](src/README.md) before touching it.

`tools/build.py` is unrelated to `src/build.py` (same filename, different
directory, different purpose): it's where the fifth code — the SI poller
described below — is defined, both as Gecko code text and as a direct
`main.dol` patch. `codeA`-`codeD` are hand-maintained in `codes/RDKE01.ini`
directly (see the caveat above); only the poller is generated.

## How it works

Everything below refers to the USA `main.dol`.

### KPAD injection points

The game links an older Wii SDK where the button state is composed inside
`KPADiRead` itself:

| Hook | Address | Notes |
| --- | --- | --- |
| Button compose | `0x80248090` | `andi. r0, r7, 0x9fff`; `r7` = Wii Remote buttons, `r27` = channel. Both the Classic Controller remap and the GameCube button injection run here. |
| Nunchuk stick read | return `0x8024791c` | `r30` = channel base + 0x60; `r12` holds a converter pointer that **must** be preserved |
| Accelerometer read | return `0x80246588` | `r30` = channel base |
| DPD / IR read | `0x802470c0`, epilogue hook `0x80247500` | |

Player 1's KPAD channel base is `0x803C91C0`, with a `0x524` stride per player.
Persistent state for the drum edge-trigger state machines is kept at offset
`0x100` of the *active* channel's KPAD struct — offsets `0x100`–`0x110` are unused
by every Wii Remote extension (they all end at `0xC0`), so per-player state can
never clobber another player or fake a button press.

### Reading the GameCube controller

The Serial Interface on Wii/Hollywood is at **`0xCD006400`**, not `0xCC006400`
(that's the GameCube/Flipper address). Dolphin mirrors `0xCC` ↔ `0xCD`, which is
why an earlier revision of these codes worked in the emulator and did nothing at
all on console. The correct base is confirmed by the game's own linked SDK —
`SISetXY`, `__SITransfer` (`0x801f48ec`) and `SIInterruptHandler` (`0x801f4440`)
all use `0xCD006400`.

Relevant registers: `SIPOLL 0x6430`, `SICOMCSR 0x6434`, `SISR 0x6438`, channel 0
`INBUFH 0x6404` / `INBUFL 0x6408` (channel stride `0xC`), I/O buffer `0x6480`.

The second half of the console problem is that *nothing polls*. Barrel Blast links
the full `si::` library (`SIInit` runs at boot from `OSInit`) but **not** the `PAD`
library — there is no `PADInit`/`PADRead`, and auto-polling is never enabled. On
real hardware `INBUFH` therefore stays empty forever, the validity bit fails, and
injection is skipped. Dolphin hides this because it fills `INBUFH` itself in
`UpdateDevices()`.

The four `C2` codes only ever *read* `INBUFH`/`INBUFL`. Under Dolphin that's
enough, because the emulator fills those registers itself whenever software
writes to them. On real hardware it is not: **`SIC0INBUFH`/`SIC0INBUFL` are
hardware-written auto-poll result registers. Writes to them from software are
silently ignored on real silicon.** An earlier version of the fifth code tried
exactly that (copy the I/O buffer response into `INBUFH`/`INBUFL` by hand) —
it's a no-op on console, which is why "works in Dolphin, does nothing on
hardware" was the exact symptom this project got stuck on. Dolphin doesn't
model that restriction, so the divergence only ever showed up on real
hardware.

The fifth code included here (`build.py`'s `autopoll` variant, hooking
`KPADiRead`'s entry at `0x80247ADC`, which runs once per channel per frame
before all three read hooks since they're `bl`-called from inside it) takes
the other path instead — it drives the SI hardware's own auto-polling logic
so the console fills `INBUFH`/`INBUFL` itself, the same way `PADRead` would if
this game linked the `PAD` library:

1. Write poll command `0x00400300` to `SIC0OUTBUF` (`0x6400`).
2. Read `SIPOLL` (`0x6430`); `SIInit` already programmed the X (rate) field,
   so this only needs to force the Y field to 1 poll/frame if it's unset.
3. OR in `EN0 | VBCPY0` (`0x88`) and write it back to `SIPOLL`.

That's it — no `SICOMCSR` kick, no `TSTART` polling, no interrupt handling.
The hardware's own auto-poll state machine (the same one `SIInit`/`SIProbe`
already exercise for the boot-time `SIGetType` probes) takes it from there
every VBlank.

A second variant (`build.py`'s `stash`) is included as a fallback in case the
`SIPOLL` enable-bit assumption above turns out wrong on real hardware: it
issues one SI immediate transfer per frame and stashes the response — read
from the I/O buffer at `0xCD006480`, which Dolphin and real hardware
implement identically for immediate transfers — into unused RAM (codeD's own
leading pad words) instead of trying to write `INBUFH`/`INBUFL`, then
repoints the four read hooks there. See `tools/gui.py` to try either one.

### Input decoding

`INBUFH` for a valid GameCube response:

```
byte0 = [ERRSTAT, 1, 0, Start, Y, X, B, A]
byte1 = [1, L, R, Z, DUp, DDown, DRight, DLeft]
byte2 = Stick X (0-255, centre 128)
byte3 = Stick Y
```

Byte 1 bit 7 (`INBUFH` bit 23) is always 1 in a valid response, so
`andis. r0, rX, 0x0080` is used as a presence check — when a pad is unplugged or
mid-hot-plug the whole word reads 0, the check fails, and injection is skipped so
the real Wii Remote takes over cleanly.

### Faking the motion

Barrel Blast does not look at absolute accelerometer magnitude — it looks at
**frame-to-frame deltas** across the three axes. A static injected vector reads as
"no motion". Each drum therefore oscillates its axis between `+10.0f` and
`-10.0f` every frame while active, which produces a delta far above the game's
shake threshold.

Drum hits are edge-triggered: a released→pressed transition arms a 4-frame
oscillation and then stops until the button is released again. Without this the
game reads a continuous shake and the karts accelerate without limit; with it you
have to physically alternate L/R hits to build speed, exactly like real bongos.

Jump is the exception. It is **angle**-based, not magnitude-based (parameters
`nBuraJumpAngleWM` / `L` / `R`, cached at config `+0x2C8` / `+0x2C0` / `+0x2C4`),
so faking it needs a genuine upward acceleration *vector* across `+0x0c/+0x10/+0x14`
and `+0x68/+0x6c/+0x70`. The current values are a placeholder — this is the main
piece of unfinished work.

All three hooks allocate proper stack frames and save/restore the volatile
registers (`r0`, `r3`–`r12`, `f0`–`f6`) the game's own compiled code is using for
locals. Skipping that corrupts the caller's frame and crashes.

## Known issues

- Classic Controller support covers buttons only — no drumming and no jump, since
  the motion-synthesis hooks are still gated to the GameCube path.
- Jump uses a placeholder acceleration vector; real captured values are needed.
- 4-player support exists as a variant that round-robins the SI channel each frame,
  but is not included here pending single-player console verification.
- USA (`RDKE01`) only.
- The `autopoll` poller's hook installs correctly and runs without crashing in
  Dolphin (checked with a GDB-stub debugger against the compiled code, not
  just read from source), but it has **not** been confirmed to actually fire
  during gameplay in Dolphin or on real hardware yet, and the `SIPOLL` enable-
  bit values it writes (`EN0`/`VBCPY0`) are inferred from the documented
  register layout, not independently confirmed against this game's linked SDK
  the way the SI base address and register offsets were. If it doesn't work
  on your console, try the `stash` variant, which sidesteps that assumption
  entirely.

## Credits

- Inspired by Vague Rant's Classic Controller hacks for *Donkey Kong Jungle Beat*.
- Gecko code format and code handler by the Gecko / WiiRD community.

## Contact

quatricsoftware@gmail.com

No support will be provided for this tool.

## License

MIT — see [LICENSE](LICENSE).

Copyright (c) 2026 quatric
