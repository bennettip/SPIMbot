# syscall constants
PRINT_STRING = 4
PRINT_CHAR   = 11
PRINT_INT    = 1

# debug constants
PRINT_INT_ADDR   = 0xffff0080
PRINT_FLOAT_ADDR = 0xffff0084
PRINT_HEX_ADDR   = 0xffff0088

# spimbot constants
VELOCITY       = 0xffff0010
ANGLE          = 0xffff0014
ANGLE_CONTROL  = 0xffff0018
BOT_X          = 0xffff0020
BOT_Y          = 0xffff0024
OTHER_BOT_X    = 0xffff00a0
OTHER_BOT_Y    = 0xffff00a4
TIMER          = 0xffff001c
SCORES_REQUEST = 0xffff1018

TILE_SCAN       = 0xffff0024
SEED_TILE       = 0xffff0054
WATER_TILE      = 0xffff002c
MAX_GROWTH_TILE = 0xffff0030
HARVEST_TILE    = 0xffff0020
BURN_TILE       = 0xffff0058
GET_FIRE_LOC    = 0xffff0028
PUT_OUT_FIRE    = 0xffff0040

GET_NUM_WATER_DROPS   = 0xffff0044
GET_NUM_SEEDS         = 0xffff0048
GET_NUM_FIRE_STARTERS = 0xffff004c
SET_RESOURCE_TYPE     = 0xffff00dc
REQUEST_PUZZLE        = 0xffff00d0
SUBMIT_SOLUTION       = 0xffff00d4

# interrupt constants
BONK_MASK               = 0x1000
BONK_ACK                = 0xffff0060
TIMER_MASK              = 0x8000
TIMER_ACK               = 0xffff006c
ON_FIRE_MASK            = 0x400
ON_FIRE_ACK             = 0xffff0050
MAX_GROWTH_ACK          = 0xffff005c
MAX_GROWTH_INT_MASK     = 0x2000
REQUEST_PUZZLE_ACK      = 0xffff00d8
REQUEST_PUZZLE_INT_MASK = 0x800

.data
# data things go here
#interrupt flags
fire_flag:			.space 4	# 32 bit, 1 or 0
max_growth_flag:    .space 4	# 32 bit, 1 or 0
puzzle_flag:		.space 4	# 32 bit, 1 or 0

# for the trig functions
three:	.float	3.0
five:	.float	5.0
PI:     .float	3.141592
F180:	.float  180.0

# misc use
currently_moving_flag:  .space 4	#32 bit, 1 or 0

fireX:  .word 0
fireY:  .word 0

# TODO: Still need data structures for tile array, puzzles

.align  4
puzzle_1_data:  .space  4096
puzzle_2_data:  .space  4096
solution_data:  .space  328
requested_flag: .space  4
received_flag:  .space  4

.text
main: # This part used to initialize values
    #saves registers. DO I EVEN NEED TO DO THIS? WE NEVER EXIT THE FUNCTION
    sub     $sp, $sp, 36
    sw      $ra, 0($sp)
    sw      $s0, 4($sp)
    sw      $s1, 8($sp)
    sw      $s2, 12($sp)
    sw      $s3, 16($sp)
    sw      $s4, 20($sp)
    sw      $s5, 24($sp)        # $a0. may not need these
    sw      $s6, 28($sp)        # $a1. may not need these.

	# initialize interrupt flags

	sw      $0, fire_flag
	sw      $0, max_growth_flag
	sw      $0, currently_moving_flag

	#Enable all interrupts
	li		$t4, BONK_MASK
	or		$t4, TIMER_MASK
	or		$t4, ON_FIRE_MASK
	or		$t4, MAX_GROWTH_INT_MASK
	or		$t4, REQUEST_PUZZLE_INT_MASK
	or		$t4, $t4, 1         # global interrupt enable
	mtc0	$t4, $12            # set interrupt mask (Status register)

    #initialization
    la      $s0, solution_data	# address for solution
    la      $s1, puzzle_1_data	# address for puzzle 1
    la      $s2, puzzle_2_data	# address for puzzle 2
    la      $s3, requested_flag
    la      $s4, received_flag

    li      $t0, 0
    sw      $t0, 0($s3)         # flag. 0 = nothing requested; 1 = 1 requested; 2 = 2 requested
    sw      $t0, 0($s4)         # flag. 0 = nothing received; 1 = 1 received only; 2 = 2 received only; 3 = both received

    move	$s5, $a0            # may not need this statement
    move	$s6, $a1            # may not need this statement

    li      $t0, 0              # 0 for water, 1 for seeds, 2 for fire starters [to change next time]
    sw      $t0, SET_RESOURCE_TYPE

    li      $t0, 0
    sw      $t0, VELOCITY

#    li		$a0, 12	#bot will move to tile at index 12 in the tile array
#    jal		move_to
#useless_loop:
#    j		useless_loop

main_after_init:

	#note only one thing
	li	$t0, 1
	sw	$t0, VELOCITY
	lw	$t3, 0($s3)
	lw	$t4, 0($s4)
	beq	$t3, 0, request_1		#if i have not requested anything, request puzzle_1

	beq	$t4, 1, request_2_before_solving_1		#if i have puzzle 1, solve it
	beq	$t4, 2, request_1_before_solving_2		#if i have puzzle 2, solve it


	li	$t0, -1
	sw	$t0, VELOCITY

	j	main_after_init			#loop if i already requested for puzzles but I haven't received anything yet

request_1:
	sw	$s1, REQUEST_PUZZLE		#request for puzzle 1
	li	$t0, 1
	sw	$t0, 0($s3)			#set flag to 'requested 1'

	j	main_after_init

request_1_before_solving_2:
	sw	$s1, REQUEST_PUZZLE		#request for puzzle 1
	li	$t0, 1
	sw	$t0, 0($s3)			#set flag to 'requested 1'

	j	before_puzzle_2

request_2_before_solving_1:
	sw	$s2, REQUEST_PUZZLE		#request for puzzle 2
	li	$t0, 2
	sw	$t0, 0($s3)			#set flag to 'requested 2'

	j	before_puzzle_1

before_puzzle_1:
	j	zero_solution_1

solve_puzzle_1:
	move	$a0, $s0			#solution address
	move	$a1, $s1			#puzzle 1 address
	jal	recursive_backtracking
	sw	$s0, SUBMIT_SOLUTION

	lw	$t4, 0($s4)
	beq	$t4, 3, set_3_to_2
	li	$t4, 0
	sw	$t4, 0($s4)

	j	main_after_init

set_3_to_2:
	li	$t4, 2
	sw	$t4, 0($s4)
	j	main_after_init

zero_solution_1:
	li	$t0, 0
	j	zero_solution_loop_1

zero_solution_loop_1:
	bge	$t0, 82, solve_puzzle_1
	mul	$t1, $t0, 4
	add	$t1, $t1, $s0
	li	$t2, 0
	sw	$t2, 0($t1)
	add	$t0, $t0, 1
	j	zero_solution_loop_1


before_puzzle_2:
	j	zero_solution_2

zero_solution_2:
	li	$t0, 0
	j	zero_solution_loop_2

zero_solution_loop_2:
	bge	$t0, 82, solve_puzzle_2
	mul	$t1, $t0, 4
	add	$t1, $t1, $s0
	li	$t2, 0
	sw	$t2, 0($t1)
	add	$t0, $t0, 1
	j	zero_solution_loop_2

solve_puzzle_2:
	move	$a0, $s0			#solution address
	move	$a1, $s2			#puzzle 2 address
	jal	recursive_backtracking
	sw	$s0, SUBMIT_SOLUTION

	lw	$t4, 0($s4)
	beq	$t4, 3, set_3_to_1
	li	$t4, 0
	sw	$t4, 0($s4)
	j	main_after_init

set_3_to_1:
	li	$t4, 1
	sw	$t4, 0($s4)
	j	main_after_init

#HELPER FUNCTIONS---------------------------------------------------------------

# -----------------------------------------------------------------------
# move_to - Given dest_tile_number...
#			-calculate the angle we need to start moving, and change the bot's abs velocity to it
#			-calculate the number of cycles(c) it'll take to get there with VELOCITY=10
#			-set the TIMER_INTERRUPT to happen after (c) cycles, so main will know when to stop
# $a0 - destination tile number (0-99)
# returns nothing
# -----------------------------------------------------------------------
move_to:
	sub		$sp, $sp, 36
	sw		$ra, 0($sp)
	sw		$s0, 4($sp)		#destx
	sw		$s1, 8($sp)		#desty
	sw		$s2, 12($sp)	#botx
	sw		$s3, 16($sp)	#boty
	sw		$s4, 20($sp)	#x_diff
	sw		$s5, 24($sp)	#y_diff
	sw		$s6, 28($sp)	#angle returned by arctan
	sw		$a0, 32($sp)	#dest_tile_number

	# STOP MOVING FIRST
	sw		$zero, VELOCITY

	# FIND DEST X-COORDINATE
	jal		calc_tile_x
	move	$s0, $v0		# dest x-coordinate
	# restore
	lw		$ra, 0($sp)
	lw		$a0, 32($sp)
	# CALCULATE THE X DIFFERENCE
	li		$s2, BOT_X		# get botx
	lw		$s2, 0($s2)
	sub		$s4, $s0, $s2	# x_diff = destx - botx


	# FIND DEST Y-COORDINATE
	jal		calc_tile_y
	move	$s1, $v0		# dest y-coordinate
	# restore
	lw		$ra, 0($sp)
	lw		$a0, 32($sp)
	# CALCULATE THE Y DIFFERENCE
	li		$s3, BOT_Y		# get boty
	lw		$s3, 0($s3)
	sub		$s5, $s1, $s3	# y_diff = desty - boty

	# CALCULATE THE ARCTAN OF X_DIFF, Y_DIFF
	move	$a0, $s4		# x_diff
	move	$a1, $s5		# y_diff
	jal		sb_arctan
	# restore
	lw		$ra, 0($sp)
	lw		$a0, 32($sp)

	move	$s6, $v0		# angle returned by arctan
	# turn the bot to the angle
	li		$t1, 1
	sw		$s6, ANGLE
	sw		$t1, ANGLE_CONTROL

	# we are now facing directly to the tile we want to go to.
	# calculate the euclidean dist
	move	$a0, $s4		# x_diff
	move	$a1, $s5		# y_diff
	jal		euclidean_dist
	move	$t0, $v0		# hypotenuse dist
	# restore
	lw		$ra, 0($sp)
	lw		$a0, 32($sp)
	# calculate the cycles needed to get to the dest tile
	mul		$t2, $t0, 1000	# multiply dist by 1000 so its more precise = number of cycles before timer interrupt

	# G0!
	li		$t9, 10
	sw		$t9, VELOCITY
    li      $t3, 1
	sw		$t3, currently_moving_flag	# raise moving flag

	# request timer interrupt
	lw		$t1, TIMER		# get current cycle
	add		$t1, $t1, $t2
	sw		$t1, TIMER		# request timer interrupt at cycle = $t1

move_to_done:
	# restore all saved registers
	lw		$ra, 0($sp)
	lw		$s0, 4($sp)		# destx
	lw		$s1, 8($sp)		# desty
	lw		$s2, 12($sp)	# botx
	lw		$s3, 16($sp)	# boty
	lw		$s4, 20($sp)	# x_diff
	lw		$s5, 24($sp)	# y_diff
	lw		$s6, 28($sp)	# angle returned by arctan
	lw		$a0, 32($sp)	# dest_tile_number
	add		$sp, $sp, 36
	jr		$ra

# -----------------------------------------------------------------------
# calc_tile_x - computes the x coordinate of a given tile number
# $a0 - tile number
# returns the x coordinate
# -----------------------------------------------------------------------
calc_tile_x:
	# given the tile number(0-99) ($a0), returns the corresponding x coordinate (center of tile)
	move	$t0, $a0		# tilenum
	li		$t5, 10
	div		$t0, $t5		# LO = tilenum / 10, HI = tilenum % 10
	mfhi	$t1				# remainder = tilenum % num
	mul		$t1, $t1, 30
	add		$t1, $t1, 15	# $t1 is now the x-coordinate of this tiles center
	move	$v0, $t1
	jr		$ra

# -----------------------------------------------------------------------
# calc_tile_y - computes the y coordinate of a given tile number
# $a0 - tile number
# returns the y coordinate
# -----------------------------------------------------------------------
calc_tile_y:
	# given the tile number(0-99) ($a0), returns the corresponding y coordinate (center of tile)
	move	$t0, $a0		# tilenum
	li		$t5, 10
	div		$t0, $t5		# LO = tilenum / 10, HI = tilenum % 10
	mflo	$t1				# remainder = tilenum / num (truncated)(79 / 10 = 7)
	mul		$t1, $t1, 30
	add		$t1, $t1, 15	# $t1 is now the y-coordinate of this tiles center
	move	$v0, $t1
	jr		$ra

# -----------------------------------------------------------------------
# sb_arctan - computes the arctangent of y / x
# $a0 - x
# $a1 - y
# returns the arctangent
# -----------------------------------------------------------------------
sb_arctan:
	li	$v0, 0          # angle = 0;

	abs	$t0, $a0        # get absolute values
	abs	$t1, $a1
	ble	$t1, $t0, no_TURN_90

	## if (abs(y) > abs(x)) { rotate 90 degrees }
	move	$t0, $a1	# int temp = y;
	neg	$a1, $a0        # y = -x;
	move	$a0, $t0    # x = temp;
	li	$v0, 90         # angle = 90;

no_TURN_90:
	bgez	$a0, pos_x 	# skip if (x >= 0)

	## if (x < 0)
	add	$v0, $v0, 180	# angle += 180;

pos_x:
	mtc1	$a0, $f0
	mtc1	$a1, $f1
	cvt.s.w $f0, $f0        # convert from ints to floats
	cvt.s.w $f1, $f1

	div.s	$f0, $f1, $f0	# float v = (float) y / (float) x;

	mul.s	$f1, $f0, $f0	# v^^2
	mul.s	$f2, $f1, $f0	# v^^3
	l.s	$f3, three          # load 5.0
	div.s 	$f3, $f2, $f3	# v^^3/3
	sub.s	$f6, $f0, $f3	# v - v^^3/3

	mul.s	$f4, $f1, $f2	# v^^5
	l.s	$f5, five           # load 3.0
	div.s 	$f5, $f4, $f5	# v^^5/5
	add.s	$f6, $f6, $f5	# value = v - v^^3/3 + v^^5/5

	l.s	$f8, PI             # load PI
	div.s	$f6, $f6, $f8	# value / PI
	l.s	$f7, F180           # load 180.0
	mul.s	$f6, $f6, $f7	# 180.0 * value / PI

	cvt.w.s $f6, $f6        # convert "delta" back to integer
	mfc1	$t0, $f6
	add	$v0, $v0, $t0       # angle += delta

	jr 	$ra

# -----------------------------------------------------------------------
# euclidean_dist - computes sqrt(x^2 + y^2)
# $a0 - x
# $a1 - y
# returns the distance
# -----------------------------------------------------------------------
euclidean_dist:
	mul	$a0, $a0, $a0	# x^2
	mul	$a1, $a1, $a1	# y^2
	add	$v0, $a0, $a1	# x^2 + y^2
	mtc1	$v0, $f0
	cvt.s.w	$f0, $f0	# float(x^2 + y^2)
	sqrt.s	$f0, $f0	# sqrt(x^2 + y^2)
	cvt.w.s	$f0, $f0	# int(sqrt(...))
	mfc1	$v0, $f0
	jr	$ra

################################################################################
# Lab 8 helper functions.s | Should contain Lab 7 functions | can consider remove .globl tag?
################################################################################
.text   # Ben: ?
.globl convert_highest_bit_to_int
convert_highest_bit_to_int:
    move  $v0, $0             # result = 0

chbti_loop:
    beq $a0, $0, chbti_end
    add $v0, $v0, 1 # result ++
    sra $a0, $a0, 1 # domain >>= 1
    j   chbti_loop

chbti_end:
    jr  $ra

.globl is_single_value_domain
is_single_value_domain:
    beq $a0, $0, isvd_zero  # return 0 if domain == 0
    sub $t0, $a0, 1	        # (domain - 1)
    and $t0, $t0, $a0       # (domain & (domain - 1))
    bne $t0, $0, isvd_zero  # return 0 if (domain & (domain - 1)) != 0
    li  $v0, 1
    jr	$ra

isvd_zero:
    li	$v0, 0
    jr	$ra


.globl get_domain_for_addition
get_domain_for_addition:
    sub    $sp, $sp, 20
    sw     $ra, 0($sp)
    sw     $s0, 4($sp)
    sw     $s1, 8($sp)
    sw     $s2, 12($sp)
    sw     $s3, 16($sp)
    move   $s0, $a0                     # s0 = target
    move   $s1, $a1                     # s1 = num_cell
    move   $s2, $a2                     # s2 = domain

    move   $a0, $a2
    jal    convert_highest_bit_to_int
    move   $s3, $v0                     # s3 = upper_bound

    sub    $a0, $0, $s2	                # -domain
    and    $a0, $a0, $s2                # domain & (-domain)
    jal    convert_highest_bit_to_int   # v0 = lower_bound

    sub    $t0, $s1, 1                  # num_cell - 1
    mul    $t0, $t0, $v0                # (num_cell - 1) * lower_bound
    sub    $t0, $s0, $t0                # t0 = high_bits
    bge    $t0, 0, gdfa_skip0

    li     $t0, 0

gdfa_skip0:
    bge    $t0, $s3, gdfa_skip1

    li     $t1, 1
    sll    $t0, $t1, $t0    # 1 << high_bits
    sub    $t0, $t0, 1      # (1 << high_bits) - 1
    and    $s2, $s2, $t0    # domain & ((1 << high_bits) - 1)

    gdfa_skip1:
    sub    $t0, $s1, 1      # num_cell - 1
    mul    $t0, $t0, $s3    # (num_cell - 1) * upper_bound
    sub    $t0, $s0, $t0    # t0 = low_bits
    ble    $t0, $0, gdfa_skip2

    sub    $t0, $t0, 1      # low_bits - 1
    sra    $s2, $s2, $t0    # domain >> (low_bits - 1)
    sll    $s2, $s2, $t0    # domain >> (low_bits - 1) << (low_bits - 1)

gdfa_skip2:
    move   $v0, $s2         # return domain
    lw     $ra, 0($sp)
    lw     $s0, 4($sp)
    lw     $s1, 8($sp)
    lw     $s2, 12($sp)
    lw     $s3, 16($sp)
    add    $sp, $sp, 20
    jr     $ra


.globl get_domain_for_subtraction
get_domain_for_subtraction:
    li     $t0, 1
    li     $t1, 2
    mul    $t1, $t1, $a0    # target * 2
    sll    $t1, $t0, $t1    # 1 << (target * 2)
    or     $t0, $t0, $t1    # t0 = base_mask
    li     $t1, 0           # t1 = mask

gdfs_loop:
    beq    $a2, $0, gdfs_loop_end
    and    $t2, $a2, 1      # other_domain & 1
    beq    $t2, $0, gdfs_if_end

    sra    $t2, $t0, $a0    # base_mask >> target
    or     $t1, $t1, $t2    # mask |= (base_mask >> target)

gdfs_if_end:
    sll    $t0, $t0, 1  # base_mask <<= 1
    sra    $a2, $a2, 1  # other_domain >>= 1
    j      gdfs_loop

gdfs_loop_end:
    and    $v0, $a1, $t1    # domain & mask
    jr	   $ra


.globl get_domain_for_cell
get_domain_for_cell:
    # save registers
    sub     $sp, $sp, 36
    sw      $ra, 0($sp)
    sw      $s0, 4($sp)
    sw      $s1, 8($sp)
    sw      $s2, 12($sp)
    sw      $s3, 16($sp)
    sw      $s4, 20($sp)
    sw      $s5, 24($sp)
    sw      $s6, 28($sp)
    sw      $s7, 32($sp)

    li      $t0, 0          # valid_domain
    lw      $t1, 4($a1)     # puzzle->grid (t1 free)
    sll     $t2, $a0, 3     # position*8 (actual offset) (t2 free)
    add     $t3, $t1, $t2   # &puzzle->grid[position]
    lw      $t4, 4($t3)     # &puzzle->grid[position].cage
    lw      $t5, 0($t4)     # puzzle->grid[posiition].cage->operation

    lw      $t2, 4($t4)     # puzzle->grid[position].cage->target

    move    $s0, $t2        # remain_target = $s0  *!*!
    lw      $s1, 8($t4)     # remain_cell = $s1 = puzzle->grid[position].cage->num_cell
    lw      $s2, 0($t3)     # domain_union = $s2 = puzzle->grid[position].domain
    move    $s3, $t4        # puzzle->grid[position].cage
    li      $s4, 0          # i = 0
    move    $s5, $t1        # $s5 = puzzle->grid
    move    $s6, $a0        # $s6 = position
    # move $s7, $s2 # $s7 = puzzle->grid[position].domain

    bne     $t5, 0, gdfc_check_else_if

    li      $t1, 1
    sub     $t2, $t2, $t1   # (puzzle->grid[position].cage->target-1)
    sll     $v0, $t1, $t2   # valid_domain = 0x1 << (prev line comment)
    j       gdfc_end        # somewhere!!!!!!!!

gdfc_check_else_if:
    bne $t5, '+', gdfc_check_else

gdfc_else_if_loop:
    lw      $t5, 8($s3)                 # puzzle->grid[position].cage->num_cell
    bge     $s4, $t5, gdfc_for_end      # branch if i >= puzzle->grid[position].cage->num_cell
    sll     $t1, $s4, 2                 # i*4
    lw      $t6, 12($s3)                # puzzle->grid[position].cage->positions
    add     $t1, $t6, $t1               # &puzzle->grid[position].cage->positions[i]
    lw      $t1, 0($t1)                 # pos = puzzle->grid[position].cage->positions[i]
    add     $s4, $s4, 1                 # i++

    sll     $t2, $t1, 3                 # pos * 8
    add     $s7, $s5, $t2               # &puzzle->grid[pos]
    lw      $s7, 0($s7)                 # puzzle->grid[pos].domain

    beq     $t1, $s6 gdfc_else_if_else  # branch if pos == position



    move    $a0, $s7                    # $a0 = puzzle->grid[pos].domain
    jal     is_single_value_domain
    bne     $v0, 1 gdfc_else_if_else    # branch if !is_single_value_domain()
    move    $a0, $s7
    jal     convert_highest_bit_to_int
    sub     $s0, $s0, $v0               # remain_target -= convert_highest_bit_to_int
    addi    $s1, $s1, -1                # remain_cell -= 1
    j       gdfc_else_if_loop
gdfc_else_if_else:
    or  $s2, $s2, $s7   # domain_union |= puzzle->grid[pos].domain
    j   gdfc_else_if_loop

gdfc_for_end:
    move    $a0, $s0
    move    $a1, $s1
    move    $a2, $s2
    jal     get_domain_for_addition # $v0 = valid_domain = get_domain_for_addition()
    j       gdfc_end

gdfc_check_else:
    lw  $t3, 12($s3)                # puzzle->grid[position].cage->positions
    lw  $t0, 0($t3)                 # puzzle->grid[position].cage->positions[0]
    lw  $t1, 4($t3)                 # puzzle->grid[position].cage->positions[1]
    xor $t0, $t0, $t1
    xor $t0, $t0, $s6               # other_pos = $t0 = $t0 ^ position
    lw  $a0, 4($s3)                 # puzzle->grid[position].cage->target

    sll $t2, $s6, 3                 # position * 8
    add $a1, $s5, $t2               # &puzzle->grid[position]
    lw  $a1, 0($a1)                 # puzzle->grid[position].domain
    # move $a1, $s7

    sll $t1, $t0, 3                 # other_pos*8 (actual offset)
    add $t3, $s5, $t1               # &puzzle->grid[other_pos]
    lw  $a2, 0($t3)                 # puzzle->grid[other_pos].domian

    jal get_domain_for_subtraction  # $v0 = valid_domain = get_domain_for_subtraction()
    # j gdfc_end
gdfc_end:
    # restore registers

    lw  $ra, 0($sp)
    lw  $s0, 4($sp)
    lw  $s1, 8($sp)
    lw  $s2, 12($sp)
    lw  $s3, 16($sp)
    lw  $s4, 20($sp)
    lw  $s5, 24($sp)
    lw  $s6, 28($sp)
    lw  $s7, 32($sp)
    add $sp, $sp, 36
    jr  $ra


.globl clone
clone:

    lw  $t0, 0($a0)
    sw  $t0, 0($a1)

    mul $t0, $t0, $t0
    mul $t0, $t0, 2 # two words in one grid

    lw  $t1, 4($a0) # &puzzle(ori).grid
    lw  $t2, 4($a1) # &puzzle(clone).grid

    li  $t3, 0 # i = 0;
clone_for_loop:
    bge     $t3, $t0, clone_for_loop_end
    sll     $t4, $t3, 2     # i * 4
    add     $t5, $t1, $t4   # puzzle(ori).grid ith word
    lw      $t6, 0($t5)

    add     $t5, $t2, $t4   # puzzle(clone).grid ith word
    sw      $t6, 0($t5)

    addi    $t3, $t3, 1     # i++

    j       clone_for_loop
clone_for_loop_end:

    jr  $ra

################################################################################
# Lab 8 forward_checking.s | can consider remove .globl tag?
################################################################################
.globl forward_checking
forward_checking:
    sub $sp, $sp, 24
    sw  $ra, 0($sp)
    sw  $a0, 4($sp)
    sw  $a1, 8($sp)
    sw  $s0, 12($sp)
    sw  $s1, 16($sp)
    sw  $s2, 20($sp)
    lw  $t0, 0($a1) # size
    li  $t1, 0      # col = 0
fc_for_col:
    bge     $t1, $t0, fc_end_for_col        # col < size
    div     $a0, $t0
    mfhi    $t2                             # position % size
    mflo    $t3                             # position / size
    beq     $t1, $t2, fc_for_col_continue   # if (col != position % size)
    mul     $t4, $t3, $t0
    add     $t4, $t4, $t1                   # position / size * size + col
    mul     $t4, $t4, 8
    lw      $t5, 4($a1)                     # puzzle->grid
    add     $t4, $t4, $t5                   # &puzzle->grid[position / size * size + col].domain
    mul     $t2, $a0, 8                     # position * 8
    add     $t2, $t5, $t2                   # puzzle->grid[position]
    lw      $t2, 0($t2)                     # puzzle -> grid[position].domain
    not     $t2, $t2                        # ~puzzle->grid[position].domain
    lw      $t3, 0($t4)
    and     $t3, $t3, $t2
    sw      $t3, 0($t4)
    beq     $t3, $0, fc_return_zero         # if (!puzzle->grid[position / size * size + col].domain)
fc_for_col_continue:
    add $t1, $t1, 1   # col++
    j   fc_for_col
fc_end_for_col:
    li  $t1, 0    # row = 0
fc_for_row:
    bge   $t1, $t0, fc_end_for_row  # row < size
    div   $a0, $t0
    mflo  $t2           # position / size
    mfhi  $t3           # position % size
    beq   $t1, $t2, fc_for_row_continue
    lw    $t2, 4($a1)   # puzzle->grid
    mul   $t4, $t1, $t0
    add   $t4, $t4, $t3
    mul   $t4, $t4, 8
    add   $t4, $t2, $t4 # &puzzle->grid[row * size + position % size]
    lw    $t6, 0($t4)
    mul   $t5, $a0, 8
    add   $t5, $t2, $t5
    lw    $t5, 0($t5)   # puzzle->grid[position].domain
    not   $t5, $t5
    and   $t5, $t6, $t5
    sw    $t5, 0($t4)
    beq   $t5, $0, fc_return_zero
fc_for_row_continue:
    add $t1, $t1, 1   # row++
    j   fc_for_row
fc_end_for_row:
    li  $s0, 0    # i = 0
fc_for_i:
    lw      $t2, 4($a1)
    mul     $t3, $a0, 8
    add     $t2, $t2, $t3
    lw      $t2, 4($t2)     # &puzzle->grid[position].cage
    lw      $t3, 8($t2)     # puzzle->grid[position].cage->num_cell
    bge     $s0, $t3, fc_return_one
    lw      $t3, 12($t2)    # puzzle->grid[position].cage->positions
    mul     $s1, $s0, 4
    add     $t3, $t3, $s1
    lw      $t3, 0($t3)     # pos
    lw      $s1, 4($a1)
    mul     $s2, $t3, 8
    add     $s2, $s1, $s2   # &puzzle->grid[pos].domain
    lw      $s1, 0($s2)
    move    $a0, $t3
    jal     get_domain_for_cell
    lw      $a0, 4($sp)
    lw      $a1, 8($sp)
    and     $s1, $s1, $v0
    sw      $s1, 0($s2)     # puzzle->grid[pos].domain &= get_domain_for_cell(pos, puzzle)
    beq     $s1, $0, fc_return_zero
fc_for_i_continue:
    add $s0, $s0, 1   # i++
    j   fc_for_i
fc_return_one:
    li  $v0, 1
    j   fc_return
fc_return_zero:
    li  $v0, 0
fc_return:
    lw  $ra, 0($sp)
    lw  $a0, 4($sp)
    lw  $a1, 8($sp)
    lw  $s0, 12($sp)
    lw  $s1, 16($sp)
    lw  $s2, 20($sp)
    add $sp, $sp, 24
    jr  $ra

################################################################################
# Lab 8 get_unassigned_position.s | can consider remove .globl tag?
################################################################################
.globl get_unassigned_position
get_unassigned_position:
    li  $v0, 0          # unassigned_pos = 0
    lw  $t0, 0($a1)     # puzzle->size
    mul $t0, $t0, $t0   # puzzle->size * puzzle->size
    add $t1, $a0, 4     # &solution->assignment[0]
get_unassigned_position_for_begin:
    bge $v0, $t0, get_unassigned_position_return    # if (unassigned_pos < puzzle->size * puzzle->size)
    mul $t2, $v0, 4
    add $t2, $t1, $t2                               # &solution->assignment[unassigned_pos]
    lw  $t2, 0($t2)                                 # solution->assignment[unassigned_pos]
    beq $t2, 0, get_unassigned_position_return      # if (solution->assignment[unassigned_pos] == 0)
    add $v0, $v0, 1                                 # unassigned_pos++
    j   get_unassigned_position_for_begin
get_unassigned_position_return:
    jr  $ra

################################################################################
# Lab 8 is_complete.s | can consider remove .globl tag?
################################################################################
.globl is_complete
is_complete:
    lw      $t0, 0($a0)     # solution->size
    lw      $t1, 0($a1)     # puzzle->size
    mul     $t1, $t1, $t1   # puzzle->size * puzzle->size
    move    $v0, $0
    seq     $v0, $t0, $t1
    j       $ra

################################################################################
# Lab 8 recursive_backtracking.s | can consider remove .globl tag?
################################################################################
.globl recursive_backtracking
recursive_backtracking:
    sub     $sp, $sp, 680
    sw      $ra, 0($sp)
    sw      $a0, 4($sp)     # solution
    sw      $a1, 8($sp)     # puzzle
    sw      $s0, 12($sp)    # position
    sw      $s1, 16($sp)    # val
    sw      $s2, 20($sp)    # 0x1 << (val - 1)
    # sizeof(Puzzle) = 8
    # sizeof(Cell [81]) = 648

    jal     is_complete
    bne     $v0, $0, recursive_backtracking_return_one
    lw      $a0, 4($sp)     # solution
    lw      $a1, 8($sp)     # puzzle
    jal     get_unassigned_position
    move    $s0, $v0        # position
    li      $s1, 1          # val = 1
recursive_backtracking_for_loop:
    lw      $a0, 4($sp)                                     # solution
    lw      $a1, 8($sp)                                     # puzzle
    lw      $t0, 0($a1)                                     # puzzle->size
    add     $t1, $t0, 1                                     # puzzle->size + 1
    bge     $s1, $t1, recursive_backtracking_return_zero    # val < puzzle->size + 1
    lw      $t1, 4($a1)                                     # puzzle->grid
    mul     $t4, $s0, 8                                     # sizeof(Cell) = 8
    add     $t1, $t1, $t4                                   # &puzzle->grid[position]
    lw      $t1, 0($t1)                                     # puzzle->grid[position].domain
    sub     $t4, $s1, 1                                     # val - 1
    li      $t5, 1
    sll     $s2, $t5, $t4                                   # 0x1 << (val - 1)
    and     $t1, $t1, $s2                                   # puzzle->grid[position].domain & (0x1 << (val - 1))
    beq     $t1, $0, recursive_backtracking_for_loop_continue # if (domain & (0x1 << (val - 1)))
    mul     $t0, $s0, 4                                     # position * 4
    add     $t0, $t0, $a0
    add     $t0, $t0, 4                                     # &solution->assignment[position]
    sw      $s1, 0($t0)                                     # solution->assignment[position] = val
    lw      $t0, 0($a0)                                     # solution->size
    add     $t0, $t0, 1
    sw      $t0, 0($a0)                                     # solution->size++
    add     $t0, $sp, 32                                    # &grid_copy
    sw      $t0, 28($sp)                                    # puzzle_copy.grid = grid_copy !!!
    move    $a0, $a1                                        # &puzzle
    add     $a1, $sp, 24                                    # &puzzle_copy
    jal     clone                                           # clone(puzzle, &puzzle_copy)
    mul     $t0, $s0, 8                                     # !!! grid size 8
    lw      $t1, 28($sp)

    add     $t1, $t1, $t0                                   # &puzzle_copy.grid[position]
    sw      $s2, 0($t1)                                     # puzzle_copy.grid[position].domain = 0x1 << (val - 1);
    move    $a0, $s0
    add     $a1, $sp, 24
    jal     forward_checking                                # forward_checking(position, &puzzle_copy)
    beq     $v0, $0, recursive_backtracking_skip

    lw      $a0, 4($sp)                                     # solution
    add     $a1, $sp, 24                                    # &puzzle_copy
    jal     recursive_backtracking
    beq     $v0, $0, recursive_backtracking_skip
    j       recursive_backtracking_return_one               # if (recursive_backtracking(solution, &puzzle_copy))
recursive_backtracking_skip:
    lw  $a0, 4($sp) # solution
    mul $t0, $s0, 4
    add $t1, $a0, 4
    add $t1, $t1, $t0
    sw  $0, 0($t1)  # solution->assignment[position] = 0
    lw  $t0, 0($a0)
    sub $t0, $t0, 1
    sw  $t0, 0($a0) # solution->size -= 1
recursive_backtracking_for_loop_continue:
    add $s1, $s1, 1   # val++
    j   recursive_backtracking_for_loop
recursive_backtracking_return_zero:
    li  $v0, 0
    j   recursive_backtracking_return
recursive_backtracking_return_one:
    li  $v0, 1
recursive_backtracking_return:
    lw  $ra, 0($sp)
    lw  $a0, 4($sp)
    lw  $a1, 8($sp)
    lw  $s0, 12($sp)
    lw  $s1, 16($sp)
    lw  $s2, 20($sp)
    add $sp, $sp, 680
    jr  $ra


#INTERRUPT HANDLER--------------------------------------------------------------

.kdata                      # interrupt handler data (separated just for readability)
chunkIH:        .space 20   # space for two registers
non_intrpt_str:	.asciiz     "Non-interrupt exception\n"
unhandled_str:	.asciiz     "Unhandled interrupt type\n"

.ktext 0x80000180
interrupt_handler:
    .set noat
    move	$k1, $at        # Save $at # don't change k1!
    .set at
    la      $k0, chunkIH
    sw      $a0, 0($k0)     # Get some free registers
    sw      $a1, 4($k0)     # by storing them to a global variable
    sw      $v0, 8($k0)		# by storing them to a global variable

    mfc0    $k0, $13        # Get Cause register
    srl     $a0, $k0, 2
    and     $a0, $a0, 0xf   # ExcCode field
    bne     $a0, 0, non_intrpt

interrupt_dispatch:                             # Interrupt:
    mfc0	$k0, $13                            # Get Cause register, again
    beq     $k0, 0, done                        # handled all outstanding interrupts

    and     $a0, $k0, ON_FIRE_MASK              # is there a on-fire interrupt?
    bne     $a0, 0, on_fire_interrupt

	and     $a0, $k0, TIMER_MASK                # is there a timer interrupt?
	bne     $a0, 0, timer_interrupt

    and     $a0, $k0, REQUEST_PUZZLE_INT_MASK   # is there a puzzle interrupt?
    bne     $a0, 0, puzzle_interrupt

	# add dispatch for other interrupt types here.
    #and     $a0, $k0, SOME_MASK
    #bne     $a0, 0, some_interrupt

	li      $v0, PRINT_STRING                   # Unhandled interrupt types
    la      $a0, unhandled_str
    syscall
    j       done

on_fire_interrupt:
    sw  $0, ON_FIRE_ACK     # acknowledge interrupt
    # get location
    lw  $k0, GET_FIRE_LOC

    srl $a0, $k0, 16
    sw  $a0, fireX
    sll $a0, $k0, 16
    srl $a0, $a0, 16
    sw  $a0, fireY
    li  $k0, 1
    sw  $k0, fire_flag      # fire_flag = 1

    j	interrupt_dispatch  # see if other interrupts are waiting

timer_interrupt:
	sw	$a1, TIMER_ACK              # acknowledge timer interrupt
	# STOP BOT. We've reached our desired location
	sw	$zero, VELOCITY
    li  $t0, 1
	sw	$t0, currently_moving_flag   # lower moving flag
	j	interrupt_dispatch

puzzle_interrupt:
    sw	$a0, REQUEST_PUZZLE_ACK	# acknowledge interrupt

    la	$k0, requested_flag
    lw	$k0, 0($k0)             # value of requested_flag
    beq	$k0, 1, set_received_1  # if i requested puzzle 1
    la	$k0, received_flag
    lw	$v0, 0($k0)             # value of received_flag
    beq	$v0, 1, set_to_3        # otherwise i have puzzle 2. if i already have puzzle 1
    li	$v0, 2                  # otherwise, i only have puzzle 2
    sw	$v0, 0($k0)
    j   interrupt_dispatch

set_received_1:
    la	$k0, received_flag
    lw	$v0, 0($k0)         # value of received_flag
    beq	$v0, 2, set_to_3    # if i already have puzzle 2 and received puzzle 1
    li	$v0, 1              # otherwise, i received puzzle 1 only
    sw	$v0, 0($k0)
    j	interrupt_dispatch

set_to_3:
    li	$v0, 3  # set that both puzzle 1 and 2 were received
    sw	$v0, 0($k0)
    j	interrupt_dispatch

# some_interrupt: # template
#    sw  $0, SOME_ACK
#    # code
#    j   interrupt_dispatch

non_intrpt:				# was some non-interrupt
	li	$v0, PRINT_STRING
	la	$a0, non_intrpt_str
	syscall				# print out an error message
	# fall through to done

done:
	la      $k0, chunkIH
	lw      $a0, 0($k0) # Restore saved registers
	lw      $a1, 4($k0)
	lw      $v0, 8($k0)
	.set noat
	move	$at, $k1    # Restore $at
	.set at
	eret
