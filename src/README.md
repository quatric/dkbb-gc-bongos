# Sources — read this before using them

⚠️ **These sources do not assemble to the codes in [`../codes/RDKE01.ini`](../codes/RDKE01.ini).**

They are a **later, known-regressed revision**. They are included because they are
the only surviving source form of this hack, not because they are the good one.

## What happened

The working codes shipped in `codes/RDKE01.ini` were assembled from an earlier
revision whose `.s` files no longer exist. What survives is a later revision in
which the drum/bongo detection had been reworked, and in that revision the
GameCube controller stopped being recognised at all — the regression was never
tracked down before the sources were lost.

Assembling these files with `build.py` gives header lines that do not match the
shipped codes:

| Hook | Shipped (working) | These sources |
| --- | --- | --- |
| `C2248090` (codeA) | `00000020` | `00000062` |
| `C2246588` (codeB) | `00000043` | `00000055` |
| `C224791C` (codeC) | `00000028` | `00000025` |
| `C2247500` (codeD) | `00000059` | `00000058` |

Note also that `build.py` has the `codeB.s` line commented out, so it emits only
three of the four hooks — another way this tree differs from the shipped set.

Treat these as a **starting point for re-deriving the hack**, and diff their
output against `codes/RDKE01.ini` as you go.

## Files

| File | Hook | Role |
| --- | --- | --- |
| `codeA.s` | `0x80248090` | Classic Controller button remap + GameCube button injection |
| `codeB.s` | `0x80246588` | Accelerometer — synthesised drum/shake motion |
| `codeC.s` | `0x8024791C` | Nunchuk stick from GameCube control stick |
| `codeD.s` | `0x80247500` | IR pointer from GameCube C-stick |
| `build.py` | — | Assembles each `.s` and prints Gecko `C2` code lines |

## Building

Requires [devkitPPC](https://devkitpro.org/):

```bash
PATH=/opt/devkitpro/devkitPPC/bin:$PATH python3 build.py
```

`build.py` assembles each source with `powerpc-eabi-gcc -O2 -mbig-endian`,
flattens it to a raw big-endian binary, pads to a 4-byte boundary, and appends a
trailing `60000000` (`nop`). That last word matters: the Gecko `C2` handler
overwrites the final word of the payload with its return branch, so without the
pad the last real instruction is destroyed.

## Recovery caveat

`codeA.s` is the least trustworthy file here. Its final revision was 289 lines,
but only lines 115–250 of that revision were ever captured; what is committed is
the last *complete* snapshot, an earlier 319-line version. It assembles, but it
is not the last state the file was in. `codeB.s`, `codeC.s`, `codeD.s` and
`build.py` are complete captures of their final revisions.
