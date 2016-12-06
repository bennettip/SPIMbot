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
#interrupt data
fire_flag:			.space 4	#32 bit, 1 or 0

max_growth_flag:		.space 4	#32 bit, 1 or 0
max_growth_location:	.space 4
#for the trig functions
three:	.float	3.0
five:	.float	5.0
PI:	.float	3.141592
F180:	.float  180.0
#misc use
currently_moving_flag:		.space 4	#32 bit, 1 or 0
next_seed_location:			.space 4	#stores the next location to plant(0-99)
timer_cause:				.space 4	#0-nothing,
										#interrupt happened: 1-fire, 2-harvest, 3-seed planting, 4-watering
										#waiting for interrupt: 5-fire, 6-harvest, 7-seed planting, 8-watering

#TODO: Still need data structures for tile array, puzzles
#for tile array
.align 2
tile_data: .space 1600

.text
main: #This part used to initialize values
	#initialize interrupt flags
#li		fire_flag, 0
#	li		max_growth_flag, 0
#	li		currently_moving_flag, 0

	#Enable all interrupts
	li		$t4, BONK_MASK
	or		$t4, TIMER_MASK
	or		$t4, ON_FIRE_MASK
	or		$t4, MAX_GROWTH_INT_MASK
	or		$t4, REQUEST_PUZZLE_INT_MASK
	or		$t4, $t4, 1			#global interrupt enable
	mtc0	$t4, $12		#set interrupt mask (Status register)

	#initialize
	sw		$zero, currently_moving_flag
	sw		$zero, timer_cause

	#initialize next_seed_location
	lw		$t0, BOT_X	#x-coordinate(0-300)
	lw		$t1, BOT_Y	#y-coordinate(0-300)
	move	$a0, $t0
	move	$a1, $t1
	jal		xy_coordinate_to_tilenum
	sw		$v0, next_seed_location	#curr bot tile

	lw		$t0, GET_NUM_FIRE_STARTERS
main_loop:
	lw		$s0, timer_cause


	bne		$zero, $s0, cont
	#go to plant
	jal		go_to_next_seed_location
cont:
	li		$t0, 3
	bne		$t0, $s0, cont2

	jal		plant_and_water
cont2:


do_puzzle:

	j		main_loop
#End of main_loop

j	main
#End of main

#HELPER FUNCTIONS---------------------------------------------------------------------------------

# -----------------------------------------------------------------------
# xy_index_to_tilenum: Converts xy(0-9) coordinates to tilenum
# $a0 - x
# $a1 - y
# returns - corresponding tilenum(0-99)
# -----------------------------------------------------------------------
xy_index_to_tilenum:
	mul		$t0, $a1, 10
	add		$t0, $t0, $a0
	move	$v0, $t0

	jr		$ra

# -----------------------------------------------------------------------
# xy_coordinate_to_tilenum: Converts xy(0-300) coordinates to tilenum
# $a0 - x
# $a1 - y
# returns - corresponding tilenum(0-99)
# -----------------------------------------------------------------------
xy_coordinate_to_tilenum:
	li		$t0, 30
	div		$a0, $t0	#LO = x/30, HI = x%30
	mflo	$a0			#x/30

	div		$a1, $t0
	mflo	$a1			#y/30

	mul		$t0, $a1, 10
	add		$t0, $t0, $a0
	move	$v0, $t0
	jr		$ra


# -----------------------------------------------------------------------
# go_to_next_seed_location: start moving to next_seed_location
# -----------------------------------------------------------------------
go_to_next_seed_location:
	sub		$sp, $sp, 4
	sw		$ra, 0($sp)

	lw		$t0, next_seed_location
	move	$a0, $t0
	jal		move_to
	#update timer_cause flag
	li		$t0, 7			#indicates waiting for seed planting
	sw		$t0, timer_cause

	lw		$ra, 0($sp)
	add		$sp, $sp, 4
	j		do_puzzle


# -----------------------------------------------------------------------
# plant_and_water: plant and water (if possible) at curr location
# -----------------------------------------------------------------------
plant_and_water:
	sub		$sp, $sp, 12
	sw		$ra, 0($sp)
	sw		$s0, 4($sp)		#curr bot tile
	sw		$s1, 8($sp)		#tile_data

	#get current number of seeds
	lw		$t0, GET_NUM_SEEDS
	ble		$t0, $zero, planting_and_watering_done #no more seeds


	#if we have seeds
	lw		$t0, BOT_X	#x-coordinate(0-300)
	lw		$t1, BOT_Y	#y-coordinate(0-300)
	move	$a0, $t0
	move	$a1, $t1
	jal		xy_coordinate_to_tilenum
	move	$s0, $v0	#curr bot tile
	#get updated tile array
	la		$s1, tile_data
	sw		$s1, TILE_SCAN		#tile_data has array of TileInfo structs
	#check this tile to see if it's empty
	mul		$t1, $s0, 16		#offset of curr tile
	add		$t1, $t1, $s1		#tile of curr tile
	lw		$t2, 0($t1)			#load state of curr tile
	beq		$t2, $zero, check_side_tiles
	#if this tile if full, check to see if we can set fire to this tile if it's our enemy's crops
	lw		$t2, 4($t1)			#0 - ours, 1 - enemy
	beq		$t2, $zero, planting_and_watering_done
	#if this tile is our enemy's
	sw		$zero, BURN_TILE
	j		planting_and_watering_done

check_side_tiles:
	#check 4 sides to see if anything growing
	#get up tile
	add		$t1, $s0, -10		#get up tilenum
	#check if we'd be out of bounds
	blt		$t1, $zero, check_right_tile	#because up tile out of bounds, don't check
	mul		$t1, $t1, 16		#offset of up tile
	add		$t1, $t1, $s1		#tile of uptile
	lw		$t2, 0($t1)			#load state of up tile
	bne		$t2, $zero, planting_and_watering_done
check_right_tile:#get right tile
	add		$t1, $s0, 1		#get right tilenum
	li		$t2, 270
	lw		$t5, BOT_X
	bge		$t5, $t2, check_down_tile
	mul		$t1, $t1, 16		#offset of right tile
	add		$t1, $t1, $s1		#tile of right tile
	lw		$t2, 0($t1)
	bne		$t2, $zero, planting_and_watering_done
check_down_tile:	#get down tile
	add		$t1, $s0, 10		#get down tilenum
	li		$t2, 99
	bgt		$t1, $t2, check_left_tile
	mul		$t1, $t1, 16		#offset of down tile
	add		$t1, $t1, $s1		#tile of downtile
	lw		$t2, 0($t1)
	bne		$t2, $zero, planting_and_watering_done
check_left_tile:	#get left tile
	add		$t1, $s0, -1		#get left tilenum
	li		$t2, 29
	lw		$t5, BOT_X
	ble		$t5, $t2, done_checking_neighbor_tiles
	mul		$t1, $t1, 16		#offset of left tile
	add		$t1, $t1, $s1		#tile of lefttile
	lw		$t2, 0($t1)
	bne		$t2, $zero, planting_and_watering_done

done_checking_neighbor_tiles:
	#WE'RE CLEAR TO PLANT AND WATER at current location!
	sw		$zero, SEED_TILE		#attempt to plant seed here
	lw		$t0, GET_NUM_WATER_DROPS

	ble		$t0, $zero, planted
	#if we can water...
	li		$t1, 2				#water here
	sw		$t1, WATER_TILE



planted:
	#update next_seed_location
	lw		$t0, next_seed_location

	li		$t5, 10
	div		$t0, $t5
	mflo	$t6			#curr next_seed_location/10
	add		$t1, $t0, $zero	#curr next_seed_location

	add		$t0, $t0, 2	#increment next_seed_location

	div		$t0, $t5
	mflo	$t7			#new next_seed_location/10
	add		$t2, $t0, $zero	#new next_seed_location

	beq		$t6, $t7, next_seed_loc_on_same_row
	#we changed our row
	div		$t2, $t5		#new next_seed_location/10
	mfhi	$t3				#new next_seed_location%10
	bne		$t3, $zero, currently_on_right_border
		#if t3 == 0 (currently one left of right border)
	add		$t0, $t0, 1 # <--- do this only if we're one tile away from right border
	j		next_seed_loc_on_same_row

currently_on_right_border:
	add		$t0, $t0, -1 # <--- do this only if we're on the right border

next_seed_loc_on_same_row:
	li		$t1, 100
	blt		$t0, $t1, updated_next_seed_location
	#if next_seed_location >= 99, wrap around
	sub		$t0, $t0, $t1 #if it was 101, then 101-100 = 1 = new tile number

updated_next_seed_location:
	sw		$t0, next_seed_location

planting_and_watering_done:
	lw		$ra, 0($sp)
	lw		$s0, 4($sp)		#curr bot tile
	lw		$s1, 8($sp)
	add		$sp, $sp, 12
	#reset timer_cause to 0
	sw		$zero, timer_cause
	j		do_puzzle

# -----------------------------------------------------------------------
# move_to - Given dest_tile_number...
#			-calculate the angle we need to start moving, and change the bot's abs velocity to it
#			-calculate the number of cycles(c) it'll take to get there with VELOCITY=10
#			-set the TIMER_INTERRUPT to happen after (c) cycles, so main will know when to stop
# $a0 - dest x
# $a1 - dest y
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

	#STOP MOVING FIRST
	sw		$zero, VELOCITY

	#FIND DEST X-COORDINATE
	jal		calc_tile_x
	move	$s0, $v0		#dest x-coordinate
	#restore
	lw		$ra, 0($sp)
	lw		$a0, 32($sp)
	#CALCULATE THE X DIFFERENCE
	li		$s2, BOT_X		#get botx
	lw		$s2, 0($s2)
	sub		$s4, $s0, $s2	#x_diff = destx - botx


	#FIND DEST Y-COORDINATE
	jal		calc_tile_y
	move	$s1, $v0		#dest y-coordinate
	#restore
	lw		$ra, 0($sp)
	lw		$a0, 32($sp)
	#CALCULATE THE Y DIFFERENCE
	li		$s3, BOT_Y		#get boty
	lw		$s3, 0($s3)
	sub		$s5, $s1, $s3	#y_diff = desty - boty

	#CALCULATE THE ARCTAN OF X_DIFF, Y_DIFF
	move	$a0, $s4		#x_diff
	move	$a1, $s5		#y_diff
	jal		sb_arctan
	#restore
	lw		$ra, 0($sp)
	lw		$a0, 32($sp)

	move	$s6, $v0		#angle returned by arctan
	#turn the bot to the angle
	li		$t1, 1
	sw		$s6, ANGLE
	sw		$t1, ANGLE_CONTROL

	#we are now facing directly to the tile we want to go to.
	#calculate the euclidean dist
	move	$a0, $s4		#x_diff
	move	$a1, $s5		#y_diff
	jal		euclidean_dist
	move	$t0, $v0		#hypotenuse dist
	#restore
	lw		$ra, 0($sp)
	lw		$a0, 32($sp)
	#calculate the cycles needed to get to the dest tile
	mul		$t2, $t0, 1000	#multiply dist by 1000 so its more precise = number of cycles before timer interrupt

	#G0!
	li		$t9, 10
	sw		$t9, VELOCITY
	li		$t1, 1
	sw		$t1, currently_moving_flag	#raise moving flag

	#request timer interrupt
	lw		$t1, TIMER		#get current cycle
	add		$t1, $t1, $t2
	sw		$t1, TIMER		#request timer interrupt at cycle = $t1

move_to_done:
	#restore all saved registers
	lw		$ra, 0($sp)
	lw		$s0, 4($sp)		#destx
	lw		$s1, 8($sp)		#desty
	lw		$s2, 12($sp)	#botx
	lw		$s3, 16($sp)	#boty
	lw		$s4, 20($sp)	#x_diff
	lw		$s5, 24($sp)	#y_diff
	lw		$s6, 28($sp)	#angle returned by arctan
	lw		$a0, 32($sp)	#dest_tile_number
	add		$sp, $sp, 36
	jr		$ra

# -----------------------------------------------------------------------
# calc_tile_x - computes the x coordinate of a given tile number
# $a0 - tile number
# returns the x coordinate
# -----------------------------------------------------------------------
calc_tile_x:
	#given the tile number(0-99) ($a0), returns the corresponding x coordinate (center of tile)
	move	$t0, $a0		#tilenum
	li		$t5, 10
	div		$t0, $t5		#LO = tilenum/10, HI = tilenum%10
	mfhi	$t1				#remainder = tilenum%num
	mul		$t1, $t1, 30
	add		$t1, $t1, 15	#$t1 is now the x-coordinate of this tiles center
	move	$v0, $t1
	jr		$ra

# -----------------------------------------------------------------------
# calc_tile_y - computes the y coordinate of a given tile number
# $a0 - tile number
# returns the y coordinate
# -----------------------------------------------------------------------
calc_tile_y:
	#given the tile number(0-99) ($a0), returns the corresponding y coordinate (center of tile)
	move	$t0, $a0		#tilenum
	li		$t5, 10
	div		$t0, $t5			#LO = tilenum/10, HI = tilenum%10
	mflo	$t1				#remainder = tilenum/num (truncated) (79/10 = 7)
	mul		$t1, $t1, 30
	add		$t1, $t1, 15	#$t1 is now the y-coordinate of this tiles center
	move	$v0, $t1
	jr		$ra

# -----------------------------------------------------------------------
# sb_arctan - computes the arctangent of y / x
# $a0 - x
# $a1 - y
# returns the arctangent
# -----------------------------------------------------------------------
sb_arctan:
	li	$v0, 0		# angle = 0;

	abs	$t0, $a0	# get absolute values
	abs	$t1, $a1
	ble	$t1, $t0, no_TURN_90

	## if (abs(y) > abs(x)) { rotate 90 degrees }
	move	$t0, $a1	# int temp = y;
	neg	$a1, $a0	# y = -x;
	move	$a0, $t0	# x = temp;
	li	$v0, 90		# angle = 90;

	no_TURN_90:
	bgez	$a0, pos_x 	# skip if (x >= 0)

	## if (x < 0)
	add	$v0, $v0, 180	# angle += 180;

	pos_x:
	mtc1	$a0, $f0
	mtc1	$a1, $f1
	cvt.s.w $f0, $f0	# convert from ints to floats
	cvt.s.w $f1, $f1

	div.s	$f0, $f1, $f0	# float v = (float) y / (float) x;

	mul.s	$f1, $f0, $f0	# v^^2
	mul.s	$f2, $f1, $f0	# v^^3
	l.s	$f3, three	# load 5.0
	div.s 	$f3, $f2, $f3	# v^^3/3
	sub.s	$f6, $f0, $f3	# v - v^^3/3

	mul.s	$f4, $f1, $f2	# v^^5
	l.s	$f5, five	# load 3.0
	div.s 	$f5, $f4, $f5	# v^^5/5
	add.s	$f6, $f6, $f5	# value = v - v^^3/3 + v^^5/5

	l.s	$f8, PI		# load PI
	div.s	$f6, $f6, $f8	# value / PI
	l.s	$f7, F180	# load 180.0
	mul.s	$f6, $f6, $f7	# 180.0 * value / PI

	cvt.w.s $f6, $f6	# convert "delta" back to integer
	mfc1	$t0, $f6
	add	$v0, $v0, $t0	# angle += delta

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



#INTERRUPT HANDLER-----------------------------------------------------------------------

.kdata				# interrupt handler data (separated just for readability)
chunkIH:	.space 8	# space for two registers
non_intrpt_str:	.asciiz "Non-interrupt exception\n"
unhandled_str:	.asciiz "Unhandled interrupt type\n"

.ktext 0x80000180
interrupt_handler:
	.set noat
	move	$k1, $at		# Save $at
	.set at
	la	$k0, chunkIH
	sw	$a0, 0($k0)		# Get some free registers
	sw	$a1, 4($k0)		# by storing them to a global variable

	mfc0	$k0, $13		# Get Cause register
	srl	$a0, $k0, 2
	and	$a0, $a0, 0xf		# ExcCode field
	bne	$a0, 0, non_intrpt

interrupt_dispatch:			# Interrupt:
	mfc0	$k0, $13		# Get Cause register, again
	beq	$k0, 0, done		# handled all outstanding interrupts

	and	$a0, $k0, TIMER_MASK	# is there a timer interrupt?
	bne	$a0, 0, timer_interrupt

	and $a0, $k0, MAX_GROWTH_INT_MASK
	bne $a0, $k0, max_growth_interrupt

	# add dispatch for other interrupt types here.

	li	$v0, PRINT_STRING	# Unhandled interrupt types
	la	$a0, unhandled_str
	syscall
	j	done

timer_interrupt:
	sw	$a1, TIMER_ACK	#acknowledge timer interrupt
	#STOP BOT. We've reached our desired location
	sw	$zero, VELOCITY
	li	$a1, 0
	sw	$a1, currently_moving_flag	#lower moving flag
	#update timer_cause
	lw	$a1, timer_cause
	add	$a1, $a1, -4		#subtract 4 to get the cause of timer interrupt i.e. 7->3
	sw	$a1, timer_cause

	j	interrupt_dispatch

max_growth_interrupt:
	lw	$a1, MAX_GROWTH_TILE
	sw	$a1, max_growth_location	#store location of crop
	j	interrupt_dispatch

non_intrpt:				# was some non-interrupt
	li	$v0, PRINT_STRING
	la	$a0, non_intrpt_str
	syscall				# print out an error message
	# fall through to done

done:
	la	$k0, chunkIH
	lw	$a0, 0($k0)		# Restore saved registers
	lw	$a1, 4($k0)
	.set noat
	move	$at, $k1		# Restore $at
	.set at
	eret



