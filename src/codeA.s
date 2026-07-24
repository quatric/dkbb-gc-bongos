    .machine any
    .text
    # Code A @ 0x80248090
    # Hook: "andi. 0, r7, 0x9fff" at the end of KPADRead main handler
    # r27 = player channel (0-3)
    # r31 = KPADStatus* for this channel
    # r7  = Wiimote button bits (we OR into this)
    # r4  = extension type (0=none, 1=nunchuk, 2=classic, 5=bongo)
    # r9  = CC held buttons (if ext==2)

    b       code_start
data_section:
    # Per-channel persistent state, 8 bytes each:
    #  [0] byte: toggle flag (0 or 1)
    #  [1] byte: left shake frames remaining
    #  [2] byte: right shake frames remaining
    #  [3-7] bytes: unused
    .long 0, 0    # ch0
    .long 0, 0    # ch1
    .long 0, 0    # ch2
    .long 0, 0    # ch3

code_start:
    stwu    1, -80(1)
    stw     0, 8(1)
    stw     3, 12(1)
    stw     4, 16(1)
    stw     5, 20(1)
    stw     6, 24(1)
    stw     8, 28(1)
    stw     9, 32(1)
    stw     10, 36(1)
    stw     11, 40(1)
    stw     12, 44(1)
    stw     25, 48(1)   # left_drum flag
    stw     26, 52(1)   # right_drum flag
    stw     28, 56(1)   # extra scratch
    stw     29, 60(1)   # float val scratch

    # NOTE: No custom SI init needed. The game's own __si_init already polls GC ports.
    # v36 (working reference code) also does NOT write OUTBUF or SIPOLL.
    # Writing these registers was interfering with the game's SI timing.

    # ---- Initialize left/right drum flags to 0 ----
    li      25, 0    # left drum hit this frame
    li      26, 0    # right drum hit this frame

    # ---- Classic Controller branch ----
    cmpwi   4, 2
    bne     check_bongo

    # CC button -> Wiimote button translation (r9 = CC buttons held)
    andi.   0, 9, 0x0400    # CC +
    beq     cc_no_plus
    ori     7, 7, 0x0010
cc_no_plus:
    andi.   0, 9, 0x0010    # CC A
    beq     cc_no_a
    ori     7, 7, 0x0800
cc_no_a:
    andi.   0, 9, 0x0040    # CC B
    beq     cc_no_b
    ori     7, 7, 0x0400
cc_no_b:
    andi.   0, 9, 0x0800    # CC Home
    beq     cc_no_home
    ori     7, 7, 0x8000
cc_no_home:
    andi.   0, 9, 0x1000    # CC -
    beq     cc_no_minus
    ori     7, 7, 0x1000
cc_no_minus:
    andi.   0, 9, 0x0001    # CC D-Up
    beq     cc_no_up
    ori     7, 7, 0x0008
cc_no_up:
    andi.   0, 9, 0x4000    # CC D-Down
    beq     cc_no_down
    ori     7, 7, 0x0004
cc_no_down:
    andi.   0, 9, 0x0002    # CC D-Left
    beq     cc_no_left
    ori     7, 7, 0x0001
cc_no_left:
    andis.  0, 9, 0x8000    # CC D-Right (bit 31)
    beq     cc_no_right
    ori     7, 7, 0x0002
cc_no_right:

    # CC Left drum: X(0x0008) | L(0x2000) | ZL(0x0080)
    andi.   0, 9, 0x2088
    beq     cc_no_ldrum
    li      25, 1
cc_no_ldrum:
    # CC Right drum: Y(0x0020) | R(0x0200)
    andi.   0, 9, 0x0220
    beq     cc_no_rdrum
    li      26, 1
cc_no_rdrum:
    # CC ZR = Jump: triggers both left AND right drum simultaneously
    andi.   0, 9, 0x0004
    beq     cc_no_zr
    li      25, 1
    li      26, 1
cc_no_zr:

    # Zero out processed motion vectors (0x4DC-0x4F0) when CC is plugged in
    # so physical Wiimote accel doesn't override our button swings
    li      28, 0
    stw     28, 0x4DC(31)   # Wiimote X
    stw     28, 0x4E0(31)   # Wiimote Y
    stw     28, 0x4E4(31)   # Wiimote Z
    stw     28, 0x4E8(31)   # Nunchuk X
    stw     28, 0x4EC(31)   # Nunchuk Y
    stw     28, 0x4F0(31)   # Nunchuk Z
    b       process_swings

check_bongo:
    # Check for DK Bongos (ext type 5) or fallback to GC
    cmpwi   4, 5
    beq     do_gc_bongo

    # ---- GC Controller ----
    cmpwi   27, 4
    bge     process_swings

    lis     5, 0xCD00
    mulli   3, 27, 12           # r3 = ch * 12 (stride between SI channel regs)

    # Load INBUFH for this channel: 0xCD006404 + ch*12
    addi    12, 3, 0x6404
    lwzx    12, 5, 12           # r12 = INBUFH (raw 32-bit SI packet bytes 0-3)
    andis.  0, 12, 0x8000       # error bit (byte 0 bit 7 = bit 31)
    bne     process_swings
    andis.  0, 12, 0x0080       # valid data bit (byte 1 bit 7 = bit 23)
    beq     process_swings

    # Shift button bits into low halfword (same as v36)
    srwi    12, 12, 16          # r12 = [byte0][byte1] in bits 15:0
    andi.   12, 12, 0x1FFF      # mask to button bits only, clear error/valid
    # Now: Start=0x1000, Y=0x0800, X=0x0400, B=0x0200, A=0x0100
    #      L=0x0040, R=0x0020, Z=0x0010, D-pad=0x000F

    addi    8, 3, 0x6408
    lwzx    8, 5, 8             # r8 = INBUFL: [CStickX(31-24)][CStickY(23-16)][LAnalog(15-8)][RAnalog(7-0)]

    # Detect bongos: DK Bongo via GC port has CStick = 0x00
    # Standard GC controller has CStick centered at ~0x80
    srwi    28, 8, 24           # r28 = CStickX (bits 31-24 -> 7-0)
    cmpwi   28, 0
    bne     gc_normal
    rlwinm  28, 8, 16, 24, 31  # r28 = CStickY (bits 23-16 -> 7-0: ROTL16 then mask 0xFF)
    cmpwi   28, 0
    bne     gc_normal

do_gc_bongo:
    # Bongo: Z button mic, R button right drum; they came through as DK Bongo ext type 5
    # But on GC: Z trigger (bit 4 of INBUFH) = left drum, R button (bit 5) = right drum
    # Swap Z and R for bongo: mic tap = R trigger area (already in right drum)
    # If ext==5 (actual bongos), r9 already has bongo bits, r12 has 0
    cmpwi   4, 5
    bne     gc_bongo_from_gc

    # Actual DK Bongos via Wiimote (ext type 5)
    # r9 = bongo button bits: bit 0=left, bit 1=right, bit 2=start/pause
    # (These are already in the kpad ext status; we just fire swings here)
    andi.   0, 9, 0x0001        # left bongo
    beq     bongo_no_left
    li      25, 1
bongo_no_left:
    andi.   0, 9, 0x0002        # right bongo
    beq     bongo_no_right
    li      26, 1
bongo_no_right:
    b       process_swings

gc_bongo_from_gc:
    # GC bongo via GC port: Z(0x0010)=left drum, R(0x0020)=right drum
    # (After shift: Z=0x0010, R=0x0020)
    andi.   0, 12, 0x0010       # Z = left drum (left bongo)
    beq     gcb_no_left
    li      25, 1
gcb_no_left:
    andi.   0, 12, 0x0020       # R = right drum (right bongo)
    beq     gcb_no_right
    li      26, 1
gcb_no_right:
    b       process_swings

gc_normal:
    # Standard GC button mapping
gc_map_buttons:
    # Zero out processed motion vectors so physical Wiimote doesn't interfere
    li      28, 0
    stw     28, 0x4DC(31)
    stw     28, 0x4E0(31)
    stw     28, 0x4E4(31)
    stw     28, 0x4E8(31)
    stw     28, 0x4EC(31)
    stw     28, 0x4F0(31)

    andi.   0, 12, 0x0100   # GC A -> Wiimote A
    beq     gc_no_a
    ori     7, 7, 0x0800
gc_no_a:
    andi.   0, 12, 0x0200   # GC B -> Wiimote B
    beq     gc_no_b
    ori     7, 7, 0x0400
gc_no_b:
    andi.   0, 12, 0x1000   # GC Start -> Wiimote +
    beq     gc_no_start
    ori     7, 7, 0x0010
gc_no_start:
    andi.   28, 12, 0x000F  # GC D-pad passthrough
    or      7, 7, 28

    # GC Z = Jump: both drums simultaneously (Left + Right Shake = Jump)
    andi.   0, 12, 0x0010
    beq     gc_no_z_jump
    li      25, 1
    li      26, 1
gc_no_z_jump:

    # GC Left drum: X(0x0400) | L(0x0040)
    andi.   0, 12, 0x0440
    beq     gc_no_ldrum
    li      25, 1
gc_no_ldrum:
    # GC L analog trigger = INBUFL bits 15-8 = LAnalog
    rlwinm  28, 8, 24, 24, 31   # r28 = LAnalog (bits 15-8 -> 7-0: ROTL24 then mask 0xFF)
    cmpwi   28, 40
    ble     gc_check_rdrum
    li      25, 1

gc_check_rdrum:
    # GC Right drum: Y(0x0800) | R(0x0020)
    andi.   0, 12, 0x0820
    beq     gc_no_rdrum
    li      26, 1
gc_no_rdrum:
    # GC R analog trigger = INBUFL bits 7-0 = RAnalog
    andi.   28, 8, 0x00FF       # r28 = RAnalog (bits 7-0)
    cmpwi   28, 40
    ble     process_swings
    li      26, 1

process_swings:
    # ---- Load per-channel persistent state ----
    bl      get_pc_state
get_pc_state:
    mflr    28
    addi    28, 28, (data_section - get_pc_state)

    slwi    29, 27, 3           # ch * 8
    add     28, 28, 29          # r28 = &data_section[ch]

    lbz     29, 0(28)           # toggle flag
    lbz     8, 1(28)            # left shake frames remaining
    lbz     12, 2(28)           # right shake frames remaining

    # Load alternating float into r3 (10.0f or -10.0f based on toggle)
    xori    29, 29, 1
    cmpwi   29, 0
    beq     load_pos
    lis     3, 0xC120           # -10.0f
    b       float_sel_done
load_pos:
    lis     3, 0x4120           # +10.0f
float_sel_done:

    # Reset/arm counters if drum was hit this frame
    cmpwi   25, 1               # left drum?
    bne     no_arm_left
    li      8, 5                # arm for 5 frames
no_arm_left:
    cmpwi   26, 1               # right drum?
    bne     no_arm_right
    li      12, 5
no_arm_right:

    # ---- Write Left swing (nunchuk accel) ----
    cmpwi   8, 0
    beq     left_done
    addi    8, 8, -1
    stw     3, 0x4EC(31)        # PlayerState Nunchuk Y = alternating 10.0f
left_done:

    # ---- Write Right swing (Wiimote accel) ----
    cmpwi   12, 0
    beq     right_done
    addi    12, 12, -1
    stw     3, 0x4E0(31)        # PlayerState Wiimote Y = alternating 10.0f
right_done:

    # ---- Save state back ----
    stb     29, 0(28)           # toggle
    stb     8,  1(28)           # left counter
    stb     12, 2(28)           # right counter

restore_A:
    lwz     0, 8(1)
    lwz     3, 12(1)
    lwz     4, 16(1)
    lwz     5, 20(1)
    lwz     6, 24(1)
    lwz     8, 28(1)
    lwz     9, 32(1)
    lwz     10, 36(1)
    lwz     11, 40(1)
    lwz     12, 44(1)
    lwz     25, 48(1)
    lwz     26, 52(1)
    lwz     28, 56(1)
    lwz     29, 60(1)
    addi    1, 1, 80

done_A:
    andi.   0, 7, 0x9fff        # ORIGINAL INSTRUCTION
