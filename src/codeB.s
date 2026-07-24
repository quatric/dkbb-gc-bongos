    .machine any
    .text
    # Code B @ 0x80246588: stroke injector (read GC and CC mapped to left/right).
    
    stwu    1, -128(1)
    stw     0, 8(1)
    stw     3, 12(1)
    stw     4, 16(1)
    stw     5, 20(1)
    stw     6, 24(1)
    stw     7, 28(1)
    stw     8, 32(1)
    stw     9, 36(1)
    stw     10, 40(1)
    stw     11, 44(1)
    stw     12, 48(1)
    stfd    0, 56(1)
    stfd    1, 64(1)
    stfd    2, 72(1)
    stfd    3, 80(1)
    stfd    4, 88(1)
    stfd    5, 96(1)
    stfd    6, 104(1)

    lis     5, 0x803C
    ori     5, 5, 0x91C0
    cmpw    30, 5
    beq     got_ch0
    
    ori     5, 5, 0x0524
    cmpw    30, 5
    beq     got_ch1
    
    lis     5, 0x803C
    ori     5, 5, 0x9C08
    cmpw    30, 5
    beq     got_ch2
    
    lis     5, 0x803C
    ori     5, 5, 0xA12C
    cmpw    30, 5
    beq     got_ch3
    
    b       restore_B
    
got_ch0:
    li      3, 0
    b       process_B
got_ch1:
    li      3, 1
    b       process_B
got_ch2:
    li      3, 2
    b       process_B
got_ch3:
    li      3, 3

process_B:
    mulli   10, 3, 12
    lis     5, 0xCD00
    
    addi    12, 10, 0x6404
    lwzx    6, 5, 12            # r6 = in_hi
    andis.  0, 6, 0x8000
    bne     no_gc
    andis.  0, 6, 0x0080
    beq     no_gc
    
    addi    12, 10, 0x6408
    lwzx    12, 5, 12           # r12 = in_lo
    
    # Check for DK Bongos!
    lis     8, 0xFCFC
    ori     8, 8, 0xFCFC
    and.    0, 12, 8
    bne     shift_gc
    
    andi.   0, 6, 0xFCFC
    bne     shift_gc
    
    li      10, 1               # Bongo flag = 1
    b       do_shift
    
shift_gc:
    li      10, 0               # Bongo flag = 0
    
do_shift:
    rlwinm  6, 6, 16, 16, 31    # r6 now has buttons in lower 16 bits
    
    cmpwi   10, 1
    bne     not_bongo
    
    # Bongo detected! Swap Z (0x0010, bit 27) and R (0x0020, bit 26)
    rlwinm  8, 6, 0, 27, 27     # isolate Z
    rlwinm  9, 6, 0, 26, 26     # isolate R
    
    rlwinm  8, 8, 1, 26, 26     # Z to R
    rlwinm  9, 9, 31, 27, 27    # R to Z
    
    rlwinm  6, 6, 0, 28, 25     # clear Z and R
    or      6, 6, 8
    or      6, 6, 9
    
not_bongo:
    # Now r6 contains the swapped buttons if it's a Bongo
    lis     7, 0x4120           # r7 = 10.0f
    
    lwz     5, 256(30)
    xori    5, 5, 1
    stw     5, 256(30)
    
    cmpwi   5, 0
    beq     pos_float
    lis     11, 0xC120
    b       load_state
pos_float:
    lis     11, 0x4120

load_state:
    lwz     5, 260(30)
    
    # Check Right Drum
    # GC buttons: Y (0x0800), R (0x0020), Z (0x0010)
    andi.   9, 6, 0x0830
    bne     press_R
    andi.   9, 12, 0x00FF       # AnalogR
    cmpwi   9, 40
    bgt     press_R
    
    # CC buttons: Y (0x0020), R (0x0200), ZR (0x0004)
    lbz     10, 0x5C(30)
    cmpwi   10, 2
    bne     no_cc_R
    lwz     10, 0x60(30)
    andi.   9, 10, 0x0224
    bne     press_R
no_cc_R:
    li      9, 0
    b       check_state_R
press_R:
    li      9, 1

check_state_R:
    srwi    3, 5, 24
    rlwinm  4, 5, 24, 24, 31
    
    cmpwi   9, 1
    bne     no_new_R
    cmpwi   3, 0
    bne     no_new_R
    li      4, 4
no_new_R:
    cmpwi   4, 0
    beq     pack_R
    addi    4, 4, -1
    stw     7, 24(30)
    stw     7, 28(30)
    stw     11, 16(30)
pack_R:
    slwi    9, 9, 24
    slwi    4, 4, 8
    or      8, 9, 4

    # Check Left Drum
    # GC buttons: X (0x0400), L (0x0040), Z (0x0010)
    andi.   9, 6, 0x0450
    bne     press_L
    srwi    9, 12, 8
    andi.   9, 9, 0x00FF        # AnalogL
    cmpwi   9, 40
    bgt     press_L
    
    # CC buttons: X (0x0008), L (0x2000), ZL (0x0080), ZR (0x0004)
    lbz     10, 0x5C(30)
    cmpwi   10, 2
    bne     no_cc_L
    lwz     10, 0x60(30)
    andi.   9, 10, 0x208C
    bne     press_L
no_cc_L:
    li      9, 0
    b       check_state_L
press_L:
    li      9, 1

check_state_L:
    rlwinm  3, 5, 16, 24, 31
    andi.   4, 5, 0xFF
    
    cmpwi   9, 1
    bne     no_new_L
    cmpwi   3, 0
    bne     no_new_L
    li      4, 4
no_new_L:
    cmpwi   4, 0
    beq     pack_L
    addi    4, 4, -1
    stw     7, 116(30)
    stw     7, 120(30)
    stw     11, 108(30)
pack_L:
    slwi    9, 9, 16
    or      8, 8, 9
    or      8, 8, 4
    stw     8, 260(30)
    b       restore_B

no_gc:
    li      6, 0
    li      12, 0
    li      10, 0
    b       do_shift

restore_B:
    lwz     0, 8(1)
    lwz     3, 12(1)
    lwz     4, 16(1)
    lwz     5, 20(1)
    lwz     6, 24(1)
    lwz     7, 28(1)
    lwz     8, 32(1)
    lwz     9, 36(1)
    lwz     10, 40(1)
    lwz     11, 44(1)
    lwz     12, 48(1)
    lfd     0, 56(1)
    lfd     1, 64(1)
    lfd     2, 72(1)
    lfd     3, 80(1)
    lfd     4, 88(1)
    lfd     5, 96(1)
    lfd     6, 104(1)
    addi    1, 1, 128
    
done_B:
    lwz     0, 0x0044(1)        # ORIGINAL
