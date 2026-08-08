"""Where the reference DOL lives.

Nothing here is committed with a real path -- set this to wherever your own
dump is. Every tool reads it from here (or the matching environment
variable), so no script carries a hardcoded path.

  DKBB_DOL   RDKE01 (USA) sys/main.dol -- the reference these patches were
             computed against. build.py's verify_patches() checks the base
             DOL against this before writing anything, so a wrong/foreign
             dump fails loudly instead of silently corrupting.
"""
import os

DKBB_DOL = os.environ.get('DKBB_DOL', 'dumps/RDKE01/sys/main.dol')
