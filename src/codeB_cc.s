# Classic Controller branch appended to codeB (accelerometer hook, 0x80246588).
#
# Entered from codeB's channel-detect fan-in with r30 = KPAD channel base and
# r3 = channel index. Synthesises the same two registers the existing GC drum
# logic consumes -- r6 (button word, as if it were SI in_hi >> 16) and r12
# (analog word, as if it were SI in_lo) -- then falls into that shared code
# unchanged. Nothing downstream knows a Classic Controller is involved.
#
#   r6  bit11 ("Y") = right drum   <- CC R (0x200) or ZR (0x004)
#   r6  bit10 ("X") = left  drum   <- CC L (0x2000) or ZL (0x080)
#   r12 byte0 = analog R, byte1 = analog L   (0..255, from the 0..1 floats)
#
# Analog triggers live at KPAD +0x7c (L) and +0x80 (R) as normalised floats --
# confirmed by decompiling the stick reader (zz_80247864_), which fills them
# from raw bytes +0x34/+0x35 scaled between nDigitalLRBorder-style bounds.
#
# FP<->int conversion goes through the hook's OWN stack frame (0x70/0x74),
# not KPAD scratch: codeB's frame is 0x80 bytes and only 0x08-0x6f is used,
# and this avoids the +0x108/+0x10c scratch the other hooks use, which
# overruns into +0x10e/+0x10f -- the KPAD sample ring index and count.

    lbz     9, 0x5c(30)         # extension type
    cmpwi   9, 2                # 2 = Classic Controller
    bne     gc_back

    lwz     9, 0x60(30)         # CC button word
    li      6, 0
    andi.   0, 9, 0x204         # R | ZR
    beq     cc_left
    ori     6, 6, 0x800         # -> right drum
cc_left:
    andi.   0, 9, 0x2080        # L | ZL
    beq     cc_analog
    ori     6, 6, 0x400         # -> left drum
cc_analog:
    lis     0, 0x437F           # 255.0f
    stw     0, 0x74(1)
    lfs     3, 0x74(1)
    lfs     1, 0x7c(30)         # L trigger 0.0 - 1.0
    lfs     2, 0x80(30)         # R trigger 0.0 - 1.0
    fmuls   1, 1, 3
    fmuls   2, 2, 3
    fctiwz  1, 1
    fctiwz  2, 2
    stfd    1, 0x70(1)
    lwz     10, 0x74(1)         # analog L as int
    stfd    2, 0x70(1)
    lwz     12, 0x74(1)         # analog R as int
    andi.   12, 12, 0xff
    andi.   10, 10, 0xff
    slwi    10, 10, 8
    or      12, 12, 10          # [-, -, aL, aR]
    b       .                   # -> common   (patched by ccpatch.py)
gc_back:
    b       .                   # -> gc_si    (patched by ccpatch.py)
