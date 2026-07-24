# Donkey Kong Barrel Blast — Classic Controller, GameCube Controller & DK Bongos support

Gecko codes that let you play the Wii release of **Donkey Kong Barrel Blast**
(`RDKE01`, USA) with a **Classic Controller**, a **GameCube controller**, or a set
of **DK Bongos** plugged into the console's GameCube ports.

The Wii version of Barrel Blast is a motion-controlled game: everything is driven
by Wii Remote / Nunchuk shake detection, and the game has no GameCube input path
at all. These codes hook the KPAD library, poll the Serial Interface directly, and
synthesise the motion the game is looking for from GameCube button and stick state.

> **⚠️ This project is incomplete.**
> The codes work in Dolphin, and the Serial Interface polling path needed for real
> hardware is implemented, but the console-side behaviour has **not** been fully
> verified. Jump (the "pull up on both bongos" gesture) is still driven by a
> placeholder acceleration vector rather than captured real-controller values.
> Classic Controller support is **buttons only** so far — see below.
> Treat this as a work in progress, not a finished hack.

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

So a poller runs once per frame at the entry to `KPADiRead` (`0x80247ADC`, which
runs before all three read hooks, since they are `bl`-called from inside it):

1. Read `SICOMCSR`; bail out if `TSTART` (bit 0) is still set.
2. Copy the previous response from the I/O buffer (`0x6480`/`0x6484`) into
   `INBUFH`/`INBUFL`.
3. Write poll command `0x40030000` to `0x6480` and kick `SICOMCSR = 0x80030801`
   (channel 0, OUT=3, IN=8, ack `TCINT`, `TSTART`).

`TCINTMSK` and `RDSTINTMSK` are both left clear, so the transfer completes
silently and the game's own SI interrupt handler never fires. Cost is one frame
of input latency.

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
- Console behaviour is not fully verified.

## Credits

- Inspired by Vague Rant's Classic Controller hacks for *Donkey Kong Jungle Beat*.
- Gecko code format and code handler by the Gecko / WiiRD community.

## Contact

quatricsoftware@gmail.com

No support will be provided for this tool.

## License

MIT — see [LICENSE](LICENSE).

Copyright (c) 2026 quatric
