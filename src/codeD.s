    .machine any
    .text
    # Code D @ 0x80247500: C-stick IR Pointer injector (Relative movement, Persistent)
    
    b       code_start
data_section:
    .long 0, 0      # ch0 x, y
    .long 0, 0      # ch1 x, y
    .long 0, 0      # ch2 x, y
    .long 0, 0      # ch3 x, y
code_start:
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
    stfd    7, 112(1)

    cmpwi   27, 0
    beq     got_ch0_D
    cmpwi   27, 1
    beq     got_ch1_D
    cmpwi   27, 2
    beq     got_ch2_D
    cmpwi   27, 3
    beq     got_ch3_D
    b       restore_D
    
got_ch0_D:
    li      3, 0
    b       process_D
got_ch1_D:
    li      3, 1
    b       process_D
got_ch2_D:
    li      3, 2
    b       process_D
got_ch3_D:
    li      3, 3

process_D:
    # Get PC for persistent data
    bl      get_pc
get_pc:
    mflr    11
    addi    11, 11, -40         # r11 points to data_section
    
    # Calculate offset for channel: r3 * 8
    slwi    10, 3, 3
    add     11, 11, 10          # r11 = data_section + ch * 8

    lbz     10, 0x5C(31)
    cmpwi   10, 2
    bne     read_gc_D
    
    lfs     1, 116(31)          # f1 = r_stick.x
    lfs     2, 120(31)          # f2 = r_stick.y
    b       apply_dz

read_gc_D:
    mulli   10, 3, 12
    lis     5, 0xCD00
    addi    12, 10, 0x6404
    lwzx    6, 5, 12
    andis.  0, 6, 0x8000
    bne     restore_D
    andis.  0, 6, 0x0080
    beq     restore_D
    
    addi    12, 10, 0x6408
    lwzx    12, 5, 12
    
    srwi    8, 12, 24
    rlwinm  9, 12, 16, 24, 31
    
    lis     5, 0x4330
    stw     5, 264(31)
    stw     8, 268(31)
    lfd     1, 264(31)
    li      8, 0
    stw     8, 268(31)
    lfd     2, 264(31)
    fsub    1, 1, 2
    
    stw     5, 264(31)
    stw     9, 268(31)
    lfd     0, 264(31)
    fsub    2, 0, 2
    
    lis     8, 0x4300
    stw     8, 268(31)
    lfs     3, 268(31)
    
    lis     8, 0x3C00
    stw     8, 268(31)
    lfs     4, 268(31)
    
    fsub    1, 1, 3
    fmuls   1, 1, 4
    
    fsub    2, 2, 3
    fmuls   2, 2, 4

apply_dz:
    # Deadzone (0.15f)
    lis     8, 0x3E19
    stw     8, 268(31)
    lfs     3, 268(31)
    
    fabs    4, 1
    fcmpo   cr0, 4, 3
    bge     x_ok
    fsubs   1, 1, 1
x_ok:
    fabs    4, 2
    fcmpo   cr0, 4, 3
    bge     y_ok
    fsubs   2, 2, 2
y_ok:
    fsubs   3, 3, 3
    fcmpo   cr0, 1, 3
    bne     stick_active
    fcmpo   cr0, 2, 3
    beq     restore_D
stick_active:

    # Speed (0.035f for slightly faster IR)
    lis     8, 0x3D0F           # 0.035f (0x3D0F5C29, we'll use 0x3D0F0000 = ~0.0349)
    stw     8, 268(31)
    lfs     3, 268(31)
    fmuls   1, 1, 3
    fmuls   2, 2, 3
    
    # Load persistent position from r11
    lfs     4, 0(11)            # f4 = pos.x
    lfs     5, 4(11)            # f5 = pos.y
    
    lis     8, 0x3F80           # 1.0f
    stw     8, 268(31)
    lfs     6, 268(31)
    lis     8, 0xBF80           # -1.0f
    stw     8, 268(31)
    lfs     7, 268(31)
    
    # Sanitize X
    fcmpo   cr0, 4, 6
    bgt     reset_x
    fcmpo   cr0, 4, 7
    blt     reset_x
    b       check_y
reset_x:
    fsubs   4, 4, 4
    
check_y:
    # Sanitize Y
    fcmpo   cr0, 5, 6
    bgt     reset_y
    fcmpo   cr0, 5, 7
    blt     reset_y
    b       add_vel
reset_y:
    fsubs   5, 5, 5

add_vel:
    fadds   4, 4, 1             # pos.x += stickX * speed
    fsubs   5, 5, 2             # pos.y -= stickY * speed (Invert Y)
    
    # Clamp X
    fcmpo   cr0, 4, 6
    ble     x_not_max
    fmr     4, 6
x_not_max:
    fcmpo   cr0, 4, 7
    bge     x_not_min
    fmr     4, 7
x_not_min:

    # Clamp Y
    fcmpo   cr0, 5, 6
    ble     y_not_max
    fmr     5, 6
y_not_max:
    fcmpo   cr0, 5, 7
    bge     y_not_min
    fmr     5, 7
y_not_min:

    # Store persistent to r11
    stfs    4, 0(11)
    stfs    5, 4(11)

write_D:
    # Write to pos.x and pos.y in KPADStatus
    stfs    4, 32(31)
    stfs    5, 36(31)
    stfs    4, 40(31)
    stfs    5, 44(31)
    
    lbz     8, 94(31)
    ori     8, 8, 2
    stb     8, 94(31)

restore_D:
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
    lfd     7, 112(1)
    addi    1, 1, 128
    
done_D:
    lwz     31, 0x1c(1)         # ORIGINAL
