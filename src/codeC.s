    .machine any
    .text
    # Code C @ 0x8024791C: stick injector. Reads GC buffer (INBUFH) for all 4 channels,
    # OR Classic Controller Left Stick, and injects into Nunchuk stick parser.
    
    stwu    1, -64(1)
    stw     0, 8(1)
    stw     6, 12(1)
    stw     7, 16(1)
    stw     9, 20(1)
    stw     10, 24(1)
    stfd    1, 32(1)
    stfd    2, 40(1)
    stfd    3, 48(1)
    
    cmpwi   27, 0
    beq     ch0_C
    cmpwi   27, 1
    beq     ch1_C
    cmpwi   27, 2
    beq     ch2_C
    cmpwi   27, 3
    beq     ch3_C
    b       restore_C
    
ch0_C:
    li      9, 0
    b       read_C
ch1_C:
    li      9, 12
    b       read_C
ch2_C:
    li      9, 24
    b       read_C
ch3_C:
    li      9, 36

read_C:
    # 1. Check Classic Controller (extType == 2)
    lbz     10, 0x5C(30)
    cmpwi   10, 2
    bne     read_gc_C
    
    # CC connected! Read l_stick.x (108) and l_stick.y (112)
    lis     10, 0x42FE          # 127.0f
    stw     10, 264(30)
    lfs     1, 264(30)          # f1 = 127.0f
    
    lfs     2, 108(30)          # f2 = l_stick.x
    fmuls   2, 2, 1
    fctiwz  2, 2
    stfd    2, 264(30)
    lwz     4, 268(30)          # r4 = signed stick X
    
    lfs     3, 112(30)          # f3 = l_stick.y
    fmuls   3, 3, 1
    fctiwz  3, 3
    stfd    3, 264(30)
    lwz     5, 268(30)          # r5 = signed stick Y
    
    b       restore_C
    
read_gc_C:
    # 2. Check GameCube Controller
    lis     6, 0xCD00
    addi    10, 9, 0x6404
    lwzx    10, 6, 10
    andis.  0, 10, 0x8000
    bne     restore_C
    andis.  0, 10, 0x0080
    beq     restore_C
    
    # Check X deadzone
    rlwinm  6, 10, 24, 24, 31   # r6 = GC stick X [0, 255]
    xori    6, 6, 0x80          # r6 = signed [-128, 127]
    addi    0, 6, 16            # r0 = r6 + 16
    cmplwi  0, 32               # If r6 in [-16,16], r0 is in [0,32]
    bgt     apply_C             # outside deadzone? apply!
    
    # Check Y deadzone
    rlwinm  7, 10, 0, 24, 31    # r7 = GC stick Y [0, 255]
    xori    7, 7, 0x80
    addi    0, 7, 16
    cmplwi  0, 32
    ble     restore_C           # both X and Y in deadzone? skip!
    
apply_C:
    mr      4, 6                # r4 = signed GC stick X
    rlwinm  5, 10, 0, 24, 31    # r5 = GC stick Y
    xori    5, 5, 0x80          # r5 = signed GC stick Y
    
restore_C:
    lwz     0, 8(1)
    lwz     6, 12(1)
    lwz     7, 16(1)
    lwz     9, 20(1)
    lwz     10, 24(1)
    lfd     1, 32(1)
    lfd     2, 40(1)
    lfd     3, 48(1)
    addi    1, 1, 64
    
done_C:
    or      3, 30, 30           # ORIGINAL
