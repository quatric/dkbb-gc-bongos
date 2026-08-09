#!/usr/bin/env python3
"""Append the "No Nunchuk Required" opt-in code to codes/RDKE01.ini.

Seven call sites across the game gate on `*(byte*)(param+0x5c) != 0` (an
extension-present check -- see codeC's use of the same offset) before doing
per-extension setup; each is `lbz r0,0x5c(rX)` immediately followed by
`cmpwi r0,0`. Patching that comparison to `cmpwi r0,-1` (a value the byte
can never hold) makes the "extension present" branch always taken, so the
game no longer requires a physical Nunchuk to be connected before it will
accept other extension types.

Independent of and untouched by ccpatch.py's codeA-D changes -- ships as its
own $-titled block so it can be enabled separately in Dolphin's Gecko Codes
list. Run once; the result is committed.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
INI = os.path.join(HERE, '..', 'codes', 'RDKE01.ini')
sys.path.insert(0, HERE)
from paths import DKBB_DOL

# Each site: `lbz r0,0x5c(rX); cmpwi r0,0`. Patching the second instruction.
SITES = [0x8011859C, 0x80119D34, 0x8011F4B8, 0x8012C8AC,
         0x80138248, 0x80148498, 0x80159648]
OLD = 0x2C000000   # cmpwi r0, 0
NEW = 0x2C00FFFF   # cmpwi r0, -1  (never matches a byte load)

TITLE = [
    '$No Nunchuk Required (opt-in) [quatric]',
    '*Bypasses the extension-present check at 7 sites so a Classic',
    '*Controller/GC pad works without a physical Nunchuk plugged in.',
    '*Independent of the main code -- enable separately if needed.',
]


def verify():
    from dol import Dol
    d = Dol(DKBB_DOL)
    for addr in SITES:
        data = d.read(addr, 4)
        if data is None:
            raise AssertionError(f'0x{addr:08X} not mapped in {DKBB_DOL}')
        got = struct.unpack('>I', data)[0]
        if got != OLD:
            raise AssertionError(
                f'0x{addr:08X}: expected {OLD:#010X}, found {got:#010X} -- '
                f'this is not the DOL these addresses were found against')
    # also check for the lbz r0,0x5c(rX) that feeds each cmpwi, within the
    # two preceding instructions (some sites have an intervening `mr`)
    for addr in SITES:
        window = [struct.unpack('>I', d.read(addr - off, 4))[0] for off in (4, 8)]
        if not any((w >> 16) == 0x8803 and (w & 0xFFFF) == 0x005C for w in window):
            raise AssertionError(f'0x{addr:08X}: no lbz r0,0x5c(rX) in the two preceding words')


def main():
    verify()
    print(f'verified {len(SITES)} sites against {DKBB_DOL}')

    lines = open(INI).read().splitlines()
    already = any('No Nunchuk Required' in l for l in lines)
    if already:
        print('already present in codes/RDKE01.ini, nothing to do')
        return

    out = list(TITLE)
    for addr in sorted(SITES):
        out.append(f'04{addr & 0x01FFFFFF:06X} {NEW:08X}')

    with open(INI, 'a') as f:
        f.write('\n' + '\n'.join(out) + '\n')
    print(f'appended {len(SITES)}-site opt-in block to {os.path.relpath(INI, HERE)}')


if __name__ == '__main__':
    main()
