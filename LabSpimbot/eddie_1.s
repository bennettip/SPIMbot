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
.align 2
.globl tile_data
tile_data: .space 1600
# -----------------------------------------------------------------------
.globl puzzle
puzzle: .space 4096 # seems to start at 0x10010640
.globl cells
cells: .space 8 * 81 * 82 # seems to start at 0x10011640
.globl solution
solution: .space 328	# seems to start at 0x1001e5d0
.globl progress
progress: .word 0
.globl need_to_submit_a_new_puzzle
need_to_submit_a_new_puzzle: .word 1
.globl cells_are_initialized
cells_are_initialized: .word 0
.globl puzzle_is_ready
puzzle_is_ready: .word 0
# -----------------------------------------------------------------------
.globl ready_to_harvest
ready_to_harvest: .word 0
# -----------------------------------------------------------------------
.globl fire_history
fire_history: .space 8 * 200	# an array of fire_records
.globl last_fire_index
last_fire_index: .word 0

.globl random_seed
random_seed: .word 659

# location of fire (from interrupt handler)
# initialized to 0x1111, and restored to this value after a fire is put out
.globl fire_location
fire_location: .word 0

.text
main:
	li		$t1, 0x1111
	sw		$t1, fire_location

	# enable interrupts
	li	$t4, TIMER_MASK		# timer interrupt enable bit
	or	$t4, $t4, BONK_MASK	# bonk interrupt bit
	or	$t4, $t4, ON_FIRE_MASK	# on_fire interrupt bit
	or	$t4, $t4, MAX_GROWTH_INT_MASK	# max_growth interrupt bit
	or	$t4, $t4, REQUEST_PUZZLE_INT_MASK	# request_puzzle interrupt bit
	or	$t4, $t4, 1		# global interrupt enable
	mtc0	$t4, $12		# set interrupt mask (Status register)

	# initialize things
	la		$t0, tile_data		#
	sw		$t0, TILE_SCAN		#
	jal		orient_center				# jump to orient_center and save position to $ra

main_loop:

	jal		attack				# jump to attack and save position to $ra
	jal		farm				# jump to farm and save position to $ra

	j	main_loop

#END_MAIN
.data
water_fill: .float 1200.0
seed_fill: .float 50.0
fire_fill: .float 2.0
enough_farming_resource_percentage: .float 0.15

.text

# -----------------------------------------------------------------------
# returns the fire rate on a scale of 0 to 3, 0 being safe and 3 being annoying based on time
# annoying - 2 fires within the last 80000 cycles
# cautious - 2 fires within the last 200000 cycles
# moderate - 1 fire within the last 200000 cycles
# safe - 0 fires within the last 500000 cycles
# struct fire_record {
# 	short x_index;
# 	short y_index;
# 	int cycle_recorded;
# }
# TODO: optimize these fire rate definitions
# -----------------------------------------------------------------------
get_enemy_fire_rate:
	lw		$t0, last_fire_index		# number of fires
	lw		$t1, TIMER		#
	la		$t2, fire_history		#
get_enemy_fire_rate_check_annoying:
	blt		$t0, 2, get_enemy_fire_rate_check_cautious	# if  <  then
	sub		$t3, $t0, 2		# second latest fire
	mul		$t3, $t3, 8		# sizeof(fire_record) = 8
	add		$t4, $t2, $t3		# fire_history + index of second latest fire
	lw		$t5, 4($t4)		# cycle_recorded
	sub		$t6, $t1, $t5		# how long ago it was
	bgt		$t6, 5000000, get_enemy_fire_rate_check_cautious	# if $t6 > 80000 then get_enemy_fire_rate_check_cautious
	li		$v0, 3		# $v0 = 3
	jr		$ra					# jump to
get_enemy_fire_rate_check_cautious:
	blt		$t0, 2, get_enemy_fire_rate_check_moderate	# if $t0 < 2 then
	sub		$t3, $t0, 2		# second latest fire
	mul		$t3, $t3, 8		# sizeof(fire_record) = 8
	add		$t4, $t2, $t3		# fire_history + index of second latest fire
	lw		$t5, 4($t4)		# cycle_recorded
	sub		$t6, $t1, $t5		# how long ago it was
	bgt		$t6, 3000000, get_enemy_fire_rate_check_moderate	# if $t6 > 200000 then get_enemy_fire_rate_check_moderate
	li		$v0, 2		# $v0 = 2
	jr		$ra					# jump to
get_enemy_fire_rate_check_moderate:
	blt		$t0, 1, get_enemy_fire_rate_check_safe	# if $t0 < 1 then
	sub		$t3, $t0, 1		# latest fire
	mul		$t3, $t3, 8		# sizeof(fire_record) = 8
	add		$t4, $t2, $t3		# fire_history + index of latest fire
	lw		$t5, 4($t4)		# cycle_recorded
	sub		$t6, $t1, $t5		# how long ago it was
	bgt		$t6, 200000, get_enemy_fire_rate_check_safe	# if $t6 > 200000 then get_enemy_fire_rate_check_moderate
	li		$v0, 1		# $v0 = 2
	jr		$ra					# jump to
get_enemy_fire_rate_check_safe:
	li		$v0, 0		# $v0 = 0
	jr		$ra					# jump to



# -----------------------------------------------------------------------
# helper attack and farm function
# returns whether or not both water and seeds have at least the required percentage of their 'filled' resource
# -----------------------------------------------------------------------
have_enough_farm_resources:
	lw		$t0, GET_NUM_WATER_DROPS		#
	lw		$t1, GET_NUM_SEEDS		#

	mtc1		$t0, $f0
	mtc1		$t1, $f1
	cvt.s.w 	$f0, $f0
	cvt.s.w 	$f1, $f1	# convert from ints to floats

	l.s		$f3, water_fill
	l.s		$f4, seed_fill
	l.s		$f5, enough_farming_resource_percentage

	div.s		$f6, $f0, $f3
	div.s		$f7, $f1, $f4	# get percentages

	c.lt.s		$f6, $f5
	bc1f		have_enough_farm_resources_check_seeds
	li		$v0, 0		# $v0 = 0
	jr		$ra					# return false
have_enough_farm_resources_check_seeds:
	c.lt.s		$f7, $f5
	bc1f		have_enough_farm_resources_return_true
	li		$v0, 0		# $v0 = 0
	jr		$ra					# return false
have_enough_farm_resources_return_true:
	li		$v0, 1		# $v0 = 1
	jr		$ra					# return true
# END_HAVE_ENOUGH_FARM_RESOURCES

# -----------------------------------------------------------------------
# Sets the resource type to whatever resource we are lacking the most
# Let A, B, C be the amounts considered 'full' for water, seeds, and fire
# Let a, b, c be the percentage filled for each resource respectively
# This function will set the corresponding resource to the minimum of a, b, c
# TODO: play around with the fill values for optimization
# 0 for now
# -----------------------------------------------------------------------
set_limiting_resource:
	lw		$t0, GET_NUM_WATER_DROPS		#
	lw		$t1, GET_NUM_SEEDS		#
	lw		$t2, GET_NUM_FIRE_STARTERS		#

	mtc1		$t0, $f0
	mtc1		$t1, $f1
	mtc1		$t2, $f2
	cvt.s.w 	$f0, $f0
	cvt.s.w 	$f1, $f1
	cvt.s.w 	$f2, $f2	# convert from ints to floats

	l.s		$f3, water_fill
	l.s		$f4, seed_fill
	l.s		$f5, fire_fill

	div.s		$f6, $f0, $f3
	div.s		$f7, $f1, $f4
	div.s		$f8, $f2, $f5	# get percentages

	# get the minimum
	c.le.s		$f6, $f7
	bc1t		set_limiting_resource_water_or_fire
	j		set_limiting_resource_seed_or_fire				# jump to set_limiting_resource_seed_or_fire
set_limiting_resource_water_or_fire:
	c.le.s		$f6, $f8
	bc1t		set_limiting_resource_water
	li		$t0, 2		# $t0 = 2
	sw		$t0, SET_RESOURCE_TYPE		# fire is the minimum
	j		set_limiting_resource_end				# jump to set_limiting_resource_end
set_limiting_resource_seed_or_fire:
	c.le.s		$f7, $f8
	bc1t		set_limiting_resource_seed
	li		$t0, 2		# $t0 = 2
	sw		$t0, SET_RESOURCE_TYPE		# fire is the minimum
	j		set_limiting_resource_end				# jump to set_limiting_resource_end
set_limiting_resource_water:
	sw		$zero, SET_RESOURCE_TYPE		# water is the minimum
	j		set_limiting_resource_end				# jump to set_limiting_resource_end
set_limiting_resource_seed:
	li		$t0, 1		# $t0 = 1
	sw		$t0, SET_RESOURCE_TYPE		# seed is the minimum
set_limiting_resource_end:
	jr		$ra					# jump to
# END_SET_LIMITING_RESOURCE

# -----------------------------------------------------------------------
# outputs 1 for yes, 0 for no
# $a0 - makes the chance of saying yes = 1/$a0
# -----------------------------------------------------------------------
randomly_decide:
	lw		$t1, TIMER		#
	lw		$t2, random_seed		#
	add		$t1, $t1, $t2		# $t1 = $t1 +


	rem		$t1, $t1, $a0
	beq		$t1, 0, randomly_decide_yes
	li		$v0, 0
	jr		$ra			# decide no
randomly_decide_yes:
	li		$v0, 1
	jr		$ra			# decide yes
# END_RANDOMLY_DECIDE

# -----------------------------------------------------------------------
# returns a random number from 0 to ($a0 - 1) inclusive
# -----------------------------------------------------------------------
random_number:
	lw		$t1, TIMER		#
	lw		$t2, random_seed		#
	add		$t1, $t1, $t2		# $t1 = $t1 +

	abs		$t1, $t1
	rem		$v0, $t1, $a0
	jr		$ra
# END_RANDOM_NUMBER

# -----------------------------------------------------------------------
# gets the number of enemy plants
# -----------------------------------------------------------------------
get_num_enemy_plants:
	la		$t0, tile_data		#
	sw		$t0, TILE_SCAN		#

	li		$v0, 0		# $v0 = 0

	li		$t1, 0		# $t1 = 0
get_num_enemy_plants_loop:
	bge		$t1, 100, get_num_enemy_plants_end	# if $t1 >= 100 then get_num_enemy_plants_end

	mul		$t2, $t1, 16		# sizeof(TileInfo) = 16
	add		$t2, $t0, $t2		# tile_data + index
	lw		$t3, 0($t2)		# state
	bne		$t3, 1, get_num_enemy_plants_skip	# if $t3 != 1 then get_num_enemy_plants_skip

	lw		$t3, 4($t2)		#
	beq		$t3, 0, get_num_enemy_plants_skip	# if $t3 == 0 then get_num_enemy_plants_skip

	add		$v0, $v0, 1		# $v0 = $v0 + 1

get_num_enemy_plants_skip:
	add		$t1, $t1, 1		# $t1 =  + 1
	j		get_num_enemy_plants_loop				# jump to get_num_enemy_plants_loop

get_num_enemy_plants_end:
	jr		$ra					# jump to



# -----------------------------------------------------------------------
# gets next available plant
# $a0 - owner or enemy
# NOTE: if $a0 - 1 (enemy), get next plant will only return a plant that the bot is not on (for attacking reasons)
# $v0 - x index of plant
# $v1 - y index of plant
# returns -1 in $v0 if there are none
# -----------------------------------------------------------------------
get_next_plant:	# returns the index of the tile with a harvestable plant, -1 otherwise
	# //update the tile_data
	# for ( int i = 0; i < 100; i++) {
	# 	if (tile_data[i].state == 1 && tile_data[i].owning_bot == 0) {//found a harvestable tile
	# 		return i;
	#	}
	# }
	# return -1;
	la		$t0, tile_data		#
	sw		$t0, TILE_SCAN		# update tile_data

	li		$t0, 0		# int i = 0
next_plant_loop:
	bge		$t0, 100, next_plant_end	# if  >= 100 then end

	mul	$t1, $t0, 16		# sizeof(TileInfo) = 16
	la		$t2, tile_data		#
	add		$t3, $t2, $t1		# tile_data + i
	lw		$t4, 0($t3)		# tile_data[i].state
	bne		$t4, 1, next_plant_skip	# if $t0 != 1 then skip

	lw		$t4, 4($t3)		# tile_data[i].owning_bot
	bne		$t4, $a0, next_plant_skip
	bne		$a0, 1, next_plant_found	# if $a0 != 1 then next_plant_found

	# check if bot is on this plant
	lw		$t2, BOT_X		#
	lw		$t3, BOT_Y		#
	div		$t2, $t2, 30			#  /
	div		$t3, $t3, 30			#  /
	mul		$t3, $t3, 10
	add		$t2, $t3, $t2		# index
	beq		$t0, $t2, next_plant_skip	# if  == $t2 then next_plant_skip
next_plant_found:
	li		$t1, 10		#  = 10
	div		$t0, $t1			#  / 10
	mflo	$v1					#  = floor( / 10)
	mfhi	$v0					#  =  mod 10
	jr		$ra					# return i
next_plant_skip:
	addi		$t0, $t0, 1		# i++
	j		next_plant_loop				# jump to loop:
next_plant_end:
	li		$v0, -1		# $v0 = -1
	jr		$ra					# jump to
# END_GET_NEXT_PLANT


# -----------------------------------------------------------------------
# returns the plant with the most neighboring plants (enemy's of course)
# $v0 - x index of plant
# $v1 - y index of plant
# returns -1 in $v0 if there are none
# -----------------------------------------------------------------------
get_best_plant_to_burn:
	la		$t0, tile_data		#  =
	sw		$t0, TILE_SCAN		#
	li		$v0, -1		# $v0 = -1
	li		$t2, 0		# best number of adjacents

	li		$t1, 0		# index
get_best_plant_to_burn_loop:
	bge		$t1, 100, get_best_plant_to_burn_end	# if $t1 >= 100 then get_best_plant_to_burn_end
	mul		$t3, $t1, 16	# sizeof(TileInfo) = 16
	add		$t4, $t0, $t3		# tile_data + index
	lw		$t5, 0($t4)		# state
	beq		$t5, 0, get_best_plant_to_burn_skip	# if $t5 == 0 then get_best_plant_to_burn_skip
	lw		$t5, 4($t4)		# owning_bot
	beq		$t5, 0, get_best_plant_to_burn_skip	# if $t5 == 0 then get_best_plant_to_burn_skip


	li		$t9, 0		# current number of adjacents for current tile
get_best_plant_to_burn_get_adjacents_top:
	sub		$t5, $t4, 160		# $t5 = $t4 - 160
	blt		$t5, $t0, get_best_plant_to_burn_get_adjacents_right	# if $t5 < tile_data then get_best_plant_to_burn_get_adjacents_right
	lw		$t6, 0($t5)		# state
	beq		$t6, 0, get_best_plant_to_burn_get_adjacents_right	# if $t6 == 0 then get_best_plant_to_burn_get_adjacents_right
	lw		$t6, 4($t5)		# owning_bot
	beq		$t6, 0, get_best_plant_to_burn_get_adjacents_right	# if $t6 == 0 then get_best_plant_to_burn_get_adjacents_right
	add		$t9, $t9, 1		# $t9 = $t9 + 1

get_best_plant_to_burn_get_adjacents_right:
	rem		$t5, $t1, 10
	beq		$t5, 9, get_best_plant_to_burn_get_adjacents_left	# if $t5 == 9 then get_best_plant_to_burn_get_adjacents_left
	add		$t5, $t4, 16		# $t5 = $t4 + 16
	lw		$t6, 0($t5)		# state
	beq		$t6, 0, get_best_plant_to_burn_get_adjacents_left	# if $t6 == 0 then get_best_plant_to_burn_get_adjacents_right
	lw		$t6, 4($t5)		# owning_bot
	beq		$t6, 0, get_best_plant_to_burn_get_adjacents_left	# if $t6 == 0 then get_best_plant_to_burn_get_adjacents_right
	add		$t9, $t9, 1		# $t9 = $t9 + 1

get_best_plant_to_burn_get_adjacents_left:
	rem		$t5, $t1, 10
	beq		$t5, 0, get_best_plant_to_burn_get_adjacents_bottom	# if $t5 == 0 then get_best_plant_to_burn_get_adjacents_bottom
	sub		$t5, $t4, 16		# $t5 = $t4 - 16
	lw		$t6, 0($t5)		# state
	beq		$t6, 0, get_best_plant_to_burn_get_adjacents_bottom	# if $t6 == 0 then get_best_plant_to_burn_get_adjacents_right
	lw		$t6, 4($t5)		# owning_bot
	beq		$t6, 0, get_best_plant_to_burn_get_adjacents_bottom	# if $t6 == 0 then get_best_plant_to_burn_get_adjacents_right
	add		$t9, $t9, 1		# $t9 = $t9 + 1

get_best_plant_to_burn_get_adjacents_bottom:
	div		$t5, $t1, 10			#  /
	beq		$t5, 9, get_best_plant_to_burn_compare_with_best	# if $t5 == 9 then
	add		$t5, $t4, 160		# $t5 = $t4 + 160
	lw		$t6, 0($t5)		# state
	beq		$t6, 0, get_best_plant_to_burn_compare_with_best	# if $t6 == 0 then get_best_plant_to_burn_get_adjacents_right
	lw		$t6, 4($t5)		# owning_bot
	beq		$t6, 0, get_best_plant_to_burn_compare_with_best	# if $t6 == 0 then get_best_plant_to_burn_get_adjacents_right
	add		$t9, $t9, 1		# $t9 = $t9 + 1

get_best_plant_to_burn_compare_with_best:
	blt		$t9, $t2, get_best_plant_to_burn_skip	# if $t9 < $t2 then get_best_plant_to_burn_skip
	move 	$t2, $t9		# $t2 = $t9
	li		$t3, 10		# $t3 = 10
	div		$t1, $t3			# $t1 / 10
	mflo	$v1					#  = floor($t1 / 10)
	mfhi	$v0					#  = $t1 mod 10

get_best_plant_to_burn_skip:
	add		$t1, $t1, 1		# $t1 =  + 1
	j		get_best_plant_to_burn_loop				# jump to get_best_plant_to_burn_loop
get_best_plant_to_burn_end:
	jr		$ra					# jump to



# -----------------------------------------------------------------------
# zeroes out the solution
# -----------------------------------------------------------------------
zero_out_solution:
	la		$t0, solution		#
	li		$t1, 0		# byte index
zero_out_solution_loop:
	bge		$t1, 82, zero_out_solution_end	# if $t1 >= 82 then zero_out_solution_end
	add		$t2, $t0, $t1		# solution + byte index
	sw		$zero, 0($t2)		# zero out a word

	add		$t1, $t1, 4		# $t1 =  + 4
	j		zero_out_solution_loop				# jump to zero_out_solution_loop
zero_out_solution_end:
	jr		$ra					# jump to
# END_ZERO_OUT_SOLUTION

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


# -----------------------------------------------------------------------
# helper farm function
# gets the quadrant the enemy is in, then moves to a random location (1 unit
# away from any 2 sides) in the opposite quadrant.
# e.g. enemy is in Q1, we move to Q4
# |0|1|
# |3|2|
# -----------------------------------------------------------------------
find_loc_away_from_enemy:
	sub		$sp, $sp, 4				# alloc stack
	sw		$ra, 0($sp)

	jal 	get_enemy_quadrant
	move 	$a0, $v0					# a0 = enemies quadrant

	jal 	get_opposite_quadrant
	move 	$a0, $v0					# a0 = quadrant we need to be in

	jal 	calculate_coords_in_quadrant

	lw		$ra, 0($sp)
	add		$sp, $sp, 4	# reset stack

	jr 		$ra
# FIND_LOC_AWAY_FROM_ENEMY


# -----------------------------------------------------------------------
# helper find_loc_away_from_enemy function
# return: quadrant the enemy is in (1,2,3, or 4)
# -----------------------------------------------------------------------
get_enemy_quadrant:
	li		$t0, 150
	lw    $t1, OTHER_BOT_X
	lw    $t2, OTHER_BOT_Y

	bge		$t1, $t0, x_greater_5		# if (x < 5)
	bge   $t2, $t0, y_greater_5  # if (y < 5)

	# return 1
	li		$v0, 0
	jr		$ra
y_greater_5:			# else // y > 5

	# return 3
	li		$v0, 3
	jr		$ra
x_greater_5:			# else // x > 5

	bge   $t2, $t0, _y_greater_5		# if (y < 5)

	# return 2
	li		$v0, 1
	jr		$ra
_y_greater_5:			# else // y > 5
	li		$v0, 2
	jr		$ra
# GET_ENEMY_QUADRANT

# -----------------------------------------------------------------------
# helper find_loc_away_from_enemy function
# $a0 - enemy quadrant
# return: quadrant opposite to the enemy
# e.g. if 1 return 4, if 2 return 3...
# -----------------------------------------------------------------------
get_opposite_quadrant:
# add 1
add $v0, $a0, 2
# mod 4
rem $v0, $v0, 4
jr		$ra
# END_GET_OPPOSITE_QUADRANT

# -----------------------------------------------------------------------
# helper find_loc_away_from_enemy function
# $a0 - desired quadrant
# return:
# $v0 - random x in desired quadrant
# $v1 - random y in desired quadrant
# -----------------------------------------------------------------------
calculate_coords_in_quadrant:
	sub		$sp, $sp, 16		# alloc stack space
	sw		$ra, 0($sp)
	sw		$s0, 4($sp)
	sw		$s1, 8($sp)
	sw		$s2, 12($sp)

	move  $s0, $a0

	# get random x and y between 0 1 2 3 4 | 5 6 7 8 9
	li		$a0, 3
	jal		random_number
	move  $s1, $v0
	add   $s1, $s1, 1

	li		$a0, 3
	jal		random_number
	move  $s2, $v0
	add   $s2, $s2, 1

	# if (Q1)
	li		$t2, 0
	bne		$s0, $t2, not_Q0
	move 	$v0, $s1
	move  $v1, $s2
	j			exit
not_Q0:
	li		$t2, 1
	bne		$s0, $t2, not_Q1
	add		$s1, $s1, 5
	move 	$v0, $s1
	move  $v1, $s2
	j     exit
not_Q1:
	li		$t2, 2
	bne		$s0, $t2, not_Q2
	add		$s2, $s2, 5
	add		$s1, $s1, 5
	move 	$v0, $s1
	move  $v1, $s2
	j     exit
not_Q2:
	add		$s2, $s2, 5
	move 	$v0, $s1
	move  $v1, $s2
exit:
	lw		$ra, 0($sp)
	lw		$s0, 4($sp)
	lw		$s1, 8($sp)
	lw		$s2, 12($sp)
	add		$sp, $sp, 16
	jr		$ra
# END_GET_ENEMY_QUADRANT



# -----------------------------------------------------------------------
# fills up the bot's resources to at least the amounts specified
# NOTE: this function blocks
# NOTE: No longer compatible with moving the spimbot
# $a0 - water
# $a1 - seeds
# $s2 - fire starters
# -----------------------------------------------------------------------
restock:
	sub		$sp, $sp, 8		# $sp = $sp - _
	sw		$ra, 0($sp)		#
	sw		$a0, 4($sp)		#
restock_water:
	lw		$t0, GET_NUM_WATER_DROPS		#
	lw		$t1, 4($sp)		#
	bge		$t0, $t1, restock_water_end	# if $t0 >= $a0 then restock_water_end
	li		$a0, 0		# $a0 = 0
	jal		restock_specific				# jump to restock_specific and save position to $ra
	j		restock_water				# jump to restock_water
restock_water_end:
restock_seed:
	lw		$t0, GET_NUM_SEEDS		#
	bge		$t0, $a1, restock_seed_end	# if $t0 >= $a1 then restock_seed_end
	li		$a0, 1		# $a0 = 1
	jal		restock_specific				# jump to restock_specific and save position to $ra
	j		restock_seed				# jump to restock_seed
restock_seed_end:
restock_fire_starter:
	lw		$t0, GET_NUM_FIRE_STARTERS		#
	bge		$t0, $a2, restock_fire_starter_end	# if $t0 >= $a2 then restock_fire_starter_end
	li		$a0, 2		# $a0 = 2
	jal		restock_specific				# jump to restock_specific and save position to $ra
	j		restock_fire_starter				# jump to restock_fire_starter
restock_fire_starter_end:
	lw		$ra, 0($sp)		#
	lw		$a0, 4($sp)		#
	add		$sp, $sp, 8		# $sp = $sp + _
	jr		$ra					# jump to
#END_RESTOCK

# -----------------------------------------------------------------------
# blocking function to restock a specific item
# waits for and then solves ken ken puzzles
# NOTE: No longer compatible with moving the spimbot
# $a0 - resource type
# -----------------------------------------------------------------------
restock_specific:
	sub		$sp, $sp, 16		# $sp = $sp - 12
	sw		$ra, 0($sp)		#
	sw		$a0, 4($sp)		#
	sw		$a1, 8($sp)		#
	sw		$a2, 12($sp)		#

	sw		$a0, SET_RESOURCE_TYPE		#

	li		$a0, 0x7fffffff		# $a0 = 0x7fffffff
	jal		partial_solve				# jump to partial_solve and save position to $ra

	lw		$ra, 0($sp)		#
	lw		$a0, 4($sp)		#
	lw		$a1, 8($sp)		#
	lw		$a2, 12($sp)		#
	add		$sp, $sp, 16		# $sp = $sp + 12
	jr		$ra					# jump to
# END_RESTOCK_SPECIFIC
.kdata				# interrupt handler data (separated just for readability)
chunkIH:	.space 32	# space for eight registers
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
	sw		$v0, 8($k0)		#
	sw		$t0, 12($k0)		#
	sw		$t1, 16($k0)		#
	sw		$t2, 20($k0)		#
	sw		$t3, 24($k0)		#




	mfc0	$k0, $13		# Get Cause register
	srl	$a0, $k0, 2
	and	$a0, $a0, 0xf		# ExcCode field
	bne	$a0, 0, non_intrpt

interrupt_dispatch:			# Interrupt:
	mfc0	$k0, $13		# Get Cause register, again
	beq	$k0, 0, done		# handled all outstanding interrupts

	and	$a0, $k0, BONK_MASK	# is there a bonk interrupt?
	bne	$a0, 0, bonk_interrupt

	and	$a0, $k0, TIMER_MASK	# is there a timer interrupt?
	bne	$a0, 0, timer_interrupt

	and	$a0, $k0, ON_FIRE_MASK 	# is there a fire interrupt?
	bne	$a0, 0, fire_interrupt	# if $a0 != 0 then fire_interrupt

        and	$a0, $k0, MAX_GROWTH_INT_MASK	# is there a max growth interrupt?
	bne	$a0, 0, max_growth_interrupt

        and	$a0, $k0, REQUEST_PUZZLE_INT_MASK	# is there a request puzzle interrupt?
	bne	$a0, 0, request_puzzle_interrupt

	li	$v0, PRINT_STRING	# Unhandled interrupt types
	la	$a0, unhandled_str
	syscall
	j	done

bonk_interrupt:
	sw	$a1, BONK_ACK		# acknowledge interrupt
	# do nothing
	j	interrupt_dispatch	# see if other interrupts are waiting

timer_interrupt:
	sw	$zero, TIMER_ACK		# acknowledge interrupt
	sw	$zero, VELOCITY		# stop the bot
	j	interrupt_dispatch	# see if other interrupts are waiting

fire_interrupt:
	sw		$zero, ON_FIRE_ACK		# acknowledge interrupt
	lw		$t3, GET_FIRE_LOC		#

	lw		$t1, TIMER		#

	# check who's fire it is
	la		$t0, tile_data		#
	sw		$t0, TILE_SCAN		#

	and		$a1, $t3, 0x0000ffff	# y index
	srl		$a0, $t3, 16		# x index

	mul		$a1, $a1, 10
	add		$a1, $a1, $a0		# index

	mul		$a1, $a1, 16			# sizeof(TileInfo) = 16

	add		$t0, $t0, $a1		# tile_data + index
	lw		$t0, 4($t0)		# owning_bot
	beq		$t0, 1, fire_interrupt_end	# It was our fire, ignore it

	# set global fire_location
	sw		$t3, fire_location

	lw		$t0, last_fire_index		#
	mul		$t1, $t0, 8		# sizeof(fire_record) = 8
	la		$a0, fire_history		#
	add		$a0, $a0, $t1		# fire_history + fire index

	sw		$t3, 0($a0)		#
	sw		$t1, 4($a0)		# store info
	add		$t0, $t0, 1		# last_fire_index ++
	sw		$t0, last_fire_index		#
fire_interrupt_end:
	j		interrupt_dispatch				# jump to interrupt_dispatch

max_growth_interrupt:
	sw		$zero, MAX_GROWTH_ACK		# acknowledge interrupt
        la                $a0, tile_data                #
        sw                $a0, TILE_SCAN                #

        lw                $a1, MAX_GROWTH_TILE                #
	srl		$t0, $a1, 16
	and		$a1, $a1, 0x0000ffff
	mul		$a1, $a1, 10
	add		$a1, $a1, $t0		# tile index
	mul		$a1, $a1, 16			# sizeof(TileInfo) = 16

        add                $a0, $a0, $a1                # tile_data + tile index
        lw                $a0, 4($a0)                # tile_data[tile index].owning_bot
        bne                $a0, 0, max_growth_interrupt_end        # if $a0 != 0 then max_growth_interrupt_end
        li                $a0, 1                # $a0 = 1
        sw                $a0, ready_to_harvest                #

max_growth_interrupt_end:
	j		interrupt_dispatch				# jump to interrupt_dispatch

request_puzzle_interrupt:
	sw		$zero, REQUEST_PUZZLE_ACK		# acknowledge interrupt
	li		$a0, 1		# $a0 = 1
	la		$a1, puzzle_is_ready		#
	sw		$a0, 0($a1)		#
	j		interrupt_dispatch				# jump to interrupt_dispatch

non_intrpt:				# was some non-interrupt
	li	$v0, PRINT_STRING
	la	$a0, non_intrpt_str
	syscall				# print out an error message
	# fall through to done

done:
	la	$k0, chunkIH
	lw	$a0, 0($k0)		# Restore saved registers
	lw	$a1, 4($k0)
	lw		$v0, 8($k0)		#
	lw		$t0, 12($k0)		#
	lw		$t1, 16($k0)		#
	lw		$t2, 20($k0)		#
	lw		$t3, 24($k0)		#

.set noat
	move	$at, $k1		# Restore $at
.set at
	eret
.text
# -----------------------------------------------------------------------
# Main function
# -----------------------------------------------------------------------
attack:
	sub		$sp, $sp, 4		# $sp = $sp - 4
	sw		$ra, 0($sp)		#
attack_burn_plants:
	jal		get_num_enemy_plants				# jump to get_num_enemy_plants and save position to $ra
	ble		$v0, 4, attack_stalk_enemy	# if $v0 <= 3 then attack_stalk_enemy

	li		$a0, 1		# $a0 = 1
	jal		get_best_plant_to_burn				# jump to get_next_enemy_plant and save position to $ra
	beq		$v0, -1, attack_stalk_enemy	# if $v0 == -1 then attack_stalk_enemy
	lw		$t0, GET_NUM_FIRE_STARTERS		#
	beq		$t0, 0, attack_stalk_enemy	# don't have any fire starters yet

	move 	$a0, $v0		# $a0 = $v0
	move 	$a1, $v1		# $a1 = $v1
	jal		burn_enemy_plant				# jump to burn_enemy_plant and save position to $ra
	jal		have_enough_farm_resources				# jump to have_enough_farm_resources and save position to $ra
	beq		$v0, 1, attack_end	# if $v0 == 1 then attack_end

attack_stalk_enemy:
	li		$a0, 200000		# $a0 = 100000
	jal		stalk_enemy				# jump to stalk_enemy and save position to $ra

	jal		have_enough_farm_resources				# jump to have_enough_farm_resources and save position to $ra
	beq		$v0, 1, attack_end	# if $v0 == 1 then attack_end
	j		attack_burn_plants				# jump to attack
attack_end:
	# also check that fire rate isn't too 'annoying'
	jal		get_enemy_fire_rate				# jump to get_enemy_fire_rate and save position to $ra
	beq		$v0, 3, attack_stalk_enemy	# if $v0 == 3 then

	jal		harvest_any				# jump to harvest_any and save position to $ra

	lw		$ra, 0($sp)		#
	add		$sp, $sp, 4		# $sp = $sp + 4
	jr		$ra					# jump to
# END_ATTACK

# -----------------------------------------------------------------------
# helper attack function
# does not waste fires
# $a0 - x coordinate
# $a1 - y coordinate
# -----------------------------------------------------------------------
burn_enemy_plant:
	sub             $sp, $sp, 4
	sw              $ra, 0($sp)

	jal		move_to				# jump to move_to and save position to $ra

	la		$t0, tile_data		#
	sw		$t0, TILE_SCAN		#

	mul		$t1, $a1, 10
	add		$t1, $t1, $a0		# $t1 =  + $a0
	mul		$t1, $t1, 16		# sizeof(TileInfo) = 16
	add		$t0, $t0, $t1		# tile_data + index

	lw		$t0, 0($t0)		# state
	beq		$t0, 0, burn_enemy_plant_end	# if  == 0 then burn_enemy_plant_end

	sw	$zero, BURN_TILE	# burn plant

burn_enemy_plant_end:
	lw              $ra, 0($sp)
	add             $sp, $sp, 4
	jr  $ra
# END_BURN_ENEMY_PLANT

# -----------------------------------------------------------------------
# helper attack function
# follows the enemy for a 'period' of time
# $a0 - number of cycles to stalk for
# -----------------------------------------------------------------------
stalk_enemy:
	sub		$sp, $sp, 12		# $sp = $sp - __
	sw		$ra, 0($sp)		#
	sw		$s0, 4($sp)		# starting number of cycles
	sw		$s1, 8($sp)		# number of cycles to stalk for

	lw		$s0, TIMER		#
	move 	$s1, $a0		# $s1 = $a0

stalk_enemy_loop:
	lw		$t0, TIMER		#
	sub		$t0, $t0, $s0		# current duration
	bge		$t0, $s1, stalk_enemy_end	# if  >= $s1 then stalk_enemy_end

	lw		$t0, OTHER_BOT_X		#
	lw		$t1, OTHER_BOT_Y		#

	lw		$t2, BOT_X		#
	lw		$t3, BOT_Y		#

	# Determine euclidean_dist
	sub		$a0, $t0, $t2		# $a0 = $t0 - $t2
	sub		$a1, $t1, $t3		# $a1 = $t1 - $t3
	jal		euclidean_dist				# jump to euclidean_dist and save position to $ra
	bgt		$v0, 30, stalk_enemy_follow	# if $v0 > 900 then
	# not worth to follow, just solve some puzzles standing still
	li		$a0, 30000		# $a0 = 30000
	li		$a1, 0		# $a1 = 0
	jal		partial_solve				# jump to partial_solve and save position to $ra
	j		stalk_enemy_loop				# jump to stalk_enemy_loop
stalk_enemy_follow:
	lw		$t0, OTHER_BOT_X		#
	lw		$t1, OTHER_BOT_Y		#
	div		$a0, $t0, 30
	div		$a1, $t1, 30
	jal		move_to				# jump to move_to and save position to $ra
	j		stalk_enemy_loop				# jump to stalk_enemy_loop

stalk_enemy_end:
	lw		$ra, 0($sp)		#
	lw		$s0, 4($sp)		#
	lw		$s1, 8($sp)		#
	add		$sp, $sp, 12		# $sp = $sp + 4
	jr		$ra					# jump to
# END_STALK_ENEMY
.text

# -----------------------------------------------------------------------
# A modified version of iterative_backtracking
# Will work on the ken-ken solver for a limited amount of cycles (e.g. 30,000)
# Handles requesting and submitting puzzles and setting the resource type
# $a0 - number of cycles we want this to run for
# $a1 - enable premature exit if not moving
# -----------------------------------------------------------------------
partial_solve:
        sub                $sp, $sp, 32                # $sp = $sp - _
        sw                $ra, 0($sp)                #
        sw                $s0, 4($sp)                # progress
        sw                $s1, 8($sp)                # puzzle->size
        sw                $s2, 12($sp)                # reset_back_to_0
        sw                $s3, 16($sp)                # val
        sw                $s4, 20($sp)                # cycle_counter
        sw                $s5, 24($sp)                # cycle_duration
        sw                $s6, 28($sp)                # premature exit enabler


        lw                $s4, TIMER                # get the starting cycle
        move         $s5, $a0                # $s5 = $a0
        move         $s6, $a1                # $s6 = $a1

        lw                $s0, progress                # progress

partial_solve_check_need_for_new_puzzle:
        lw                $t0, need_to_submit_a_new_puzzle                #
        beq                $t0, 0, partial_solve_wait_for_puzzle        # if  == 0 then partial_solve_wait_for_puzzle
        sw                $zero, need_to_submit_a_new_puzzle                #
        jal                set_limiting_resource                                # jump to set_limiting_resource and save position to $ra
        la                $t0, puzzle                #
        sw                $t0, REQUEST_PUZZLE                #
        jal                zero_out_solution                                # jump to zero_out_solution and save position to $ra


partial_solve_wait_for_puzzle:
        # TODO:  check time
        lw                $t0, TIMER                #
        sub                $t0, $t0, $s4                #  = $t0 - $s4
        bgt                $t0, $s5, partial_solve_return        # check if it's time to pause our work
        beq                $s6, 0, partial_solve_wait_for_puzzle_no_premature_exit        # if $s6 == 0 then partial_solve_loop_no_premature_exit
        lw                $t0, VELOCITY                #
        beq                $t0, 0, partial_solve_return        # if $t0 == 0 then partial_solve_return

partial_solve_wait_for_puzzle_no_premature_exit:
        lw                $t0, puzzle_is_ready                #
        beq                $t0, 0, partial_solve_wait_for_puzzle        # if $t0 == 0 then partial_solve_wait_for_puzzle

partial_solve_check_cells_initialized:
        lw                $t0, cells_are_initialized                #
        bne                $t0, 0, partial_solve_ready_to_solve        # if  != 0 then partial_solve_cells_have_been_initialized
        jal                initialize_cells                                # jump to initialize_cells and save position to $ra

partial_solve_ready_to_solve:

# NOTE: At this point, a puzzle should be ready, our solution struct and cells initialized OR in a state of progress
# Start solving
        la                $t0, puzzle                #
        lw                $s1, 0($t0)                # puzzle->size

partial_solve_loop:
        mul               $t1, $s1, $s1                 # puzzle->size ^ 2
        bge                $s0, $t1, partial_solve_solved_puzzle        # if  >=  then partial_solve_solved_puzzle

        # TODO:  check time
        lw                $t0, TIMER                #
        sub                $t0, $t0, $s4                #  = $t0 - $s4
        bgt                $t0, $s5, partial_solve_return        # check if it's time to pause our work
        beq                $s6, 0, partial_solve_loop_no_premature_exit        # if $s6 == 0 then partial_solve_loop_no_premature_exit
        lw                $t0, VELOCITY                #
        beq                $t0, 0, partial_solve_return        # if $t0 == 0 then partial_solve_return

partial_solve_loop_no_premature_exit:

        li                $s2, 1                # reset_back_to_0
        la                $t3, solution                #
        add                $t3, $t3, 4                # solution->assignment
        mul               $t4, $s0, 4                   # sizeof(assignment) = 4
        add                $t5, $t3, $t4                # solution->assignment + progress
        lw                $s3, 0($t5)                # solution->assignment[progress]
        add                $s3, $s3, 1                # $s3 = $s3 + 1
        add                $t0, $s1, 1                # puzzle->size + 1
        rem               $s3, $s3, $t0               # (solution->assignment[progress] + 1) % (puzzle->size + 1)
                                                                # also serves as int val
        sw                $s3, 0($t5)                # solution->assignment[progress] = (solution->assignment[progress] + 1) % (puzzle->size + 1)

        beq                $s3, 0, partial_solve_check_reset        # if $s3 == 0 then partial_solve_check_reset
        li                $s2, 0                # reset_back_to_0 = 0

        la                $t7, puzzle                #
        lw                $t7, 4($t7)                # puzzle->grid
        mul               $t8, $s0, 8                   # sizeof(Cell) = 8
        add                $t7, $t7, $t8                # puzzle->grid + progress
        lw                $t9, 0($t7)                # puzzle->grid[progress].domain
        li                $t3, 1                # 0x1
        sub                $t6, $s3, 1                # val - 1
        sll               $t3, $t3, $t6         # 0x1 << (val - 1)

        and               $t4, $t9, $t3              # puzzle->grid[progress].domain & 0x1 << (val - 1)
        beq                $t4, 0, partial_solve_check_reset        # if $t4 == 0 then partial_solve_check_reset

        move         $a0, $s0                # pass in progress
        jal                clone_to_next_grid                                # jump to clone_to_next_grid and save position to $ra

        la                $t4, cells                # cells
        add                $t0, $s0, 1                # progress + 1
        mul               $t5, $t0, 648                 # (progress + 1) * 81 * sizeof(Cell) = progress * 648
        add                $t6, $t4, $t5                # cells + (progress + 1) * 81 * sizeof(Cell)
        la                $t4, puzzle                #
        sw                $t6, 4($t4)                # puzzle->grid = cells + (progress + 1) * 81 * sizeof(Cell)

        mul             $t5, $s0, 8                     # sizeof(Cell) = 8
        add                $t7, $t6, $t5                # puzzle->grid + progress
        li                $t3, 1                # 0x1
        sub                $t6, $s3, 1                # val - 1
        sll               $t3, $t3, $t6         # 0x1 << (val - 1)
        sw                $t3, 0($t7)                # puzzle->grid[progress].domain = 0x1 << (val - 1)

        move         $a0, $s0                # progress
        la                $a1, puzzle                #
        jal                forward_checking                                # jump to forward_checking and save position to $ra

        beq                $v0, 0, partial_solve_forward_check        # if $v0 == 0 then partial_solve_forward_check
        add                $s0, $s0, 1                # progress ++
        j                partial_solve_check_reset                                # jump to partial_solve_check_reset
partial_solve_forward_check:
        la                $t4, cells                # cells
        mul               $t5, $s0, 648                 # progress * 81 * sizeof(Cell) = progress * 648
        add                $t6, $t4, $t5                # cells + progress * 81 * sizeof(Cell)
        la                $t4, puzzle                #
        sw                $t6, 4($t4)                # puzzle->grid = cells + progress * 81 * sizeof(Cell)

partial_solve_check_reset:
        beq                $s2, 0, partial_solve_loop_back        # if $s2 == 0 then partial_solve_loop_back
        sub                $s0, $s0, 1                # progress--
        la                $t4, cells                # cells
        mul               $t5, $s0, 648                 # progress * 81 * sizeof(Cell) = progress * 648
        add                $t6, $t4, $t5                # cells + progress * 81 * sizeof(Cell)
        la                $t4, puzzle                #
        sw                $t6, 4($t4)                # puzzle->grid = cells + progress * 81 * sizeof(Cell)

        bne                $s0, 0, partial_solve_loop_back        # if  != 0 then partial_solve_loop_back
        la                $t0, solution                #
        add                $t0, $t0, 4                # solution->assignment
        lw                $t0, 0($t0)                # solution->assignment[0]
        bne                $t0, 0, partial_solve_loop_back        # if  != 0 then partial_solve_loop_back
        j                partial_solve_solved_puzzle                                #
partial_solve_loop_back:
        j                partial_solve_loop                                # jump to partial_solve_loop

partial_solve_solved_puzzle:
        mul             $t0, $s1, $s1
        la                $t1, solution                #
        sw                $t0, 0($t1)                # solution->size = puzzle->size ^ 2
        sw                $t1, SUBMIT_SOLUTION                #

# indicate that we need a new puzzle
        li                $t0, 1                # $t0 = 1
        sw                $t0, need_to_submit_a_new_puzzle                #
        sw                $zero, puzzle_is_ready                #
        sw                $zero, cells_are_initialized                #
        li                $s0, 0                # $s0 = 0

partial_solve_return:
        sw                $s0, progress                # write_back to progress

        lw                $ra, 0($sp)                #
        lw                $s0, 4($sp)                # progress
        lw                $s1, 8($sp)                # puzzle->size
        lw                $s2, 12($sp)                # reset_back_to_0
        lw                $s3, 16($sp)                # value
        lw                $s4, 20($sp)                #
        lw                $s5, 24($sp)                # cycle_duration
        lw                $s6, 28($sp)                # premature exit enabler
        add                $sp, $sp, 32                # $sp = $sp - _
        jr                $ra                                        # jump to
.text

## struct Cage {
##   char operation;
##   int target;
##   int num_cell;
##   int* positions;
## };
##
## struct Cell {
##   int domain;
##   Cage* cage;
## };
##
## struct Puzzle {
##   int size;
##   Cell* grid;
## };
##
## // Given the assignment at current position, removes all inconsistent values
## // for cells in the same row, column, and cage.
## int forward_checking(int position, Puzzle* puzzle) {
##   int size = puzzle->size;
##   // Removes inconsistent values in the row.
##   for (int col = 0; col < size; col++) {
##     if (col != position % size) {
##       puzzle->grid[position / size * size + col].domain &=
##           ~ puzzle->grid[position].domain;
##       if (!puzzle->grid[position / size * size + col].domain) {
##         return 0;
##       }
##     }
##   }
##   // Removes inconsistent values in the column.
##   for (int row = 0; row < size; row++) {
##     if (row != position / size) {
##       puzzle->grid[row * size + position % size].domain &=
##           ~ puzzle->grid[position].domain;
##       if (!puzzle->grid[row * size + position % size].domain) {
##         return 0;
##       }
##     }
##   }
##   // Removes inconsistent values in the cage.
##   for (int i = 0; i < puzzle->grid[position].cage->num_cell; i++) {
##     int pos = puzzle->grid[position].cage->positions[i];
##     puzzle->grid[pos].domain &= get_domain_for_cell(pos, puzzle);
##     if (!puzzle->grid[pos].domain) {
##       return 0;
##     }
##   }
##   return 1;
## }

forward_checking:
  sub   $sp, $sp, 24
  sw    $ra, 0($sp)
  sw    $a0, 4($sp)
  sw    $a1, 8($sp)
  sw    $s0, 12($sp)
  sw    $s1, 16($sp)
  sw    $s2, 20($sp)
  lw    $t0, 0($a1)     # size
  li    $t1, 0          # col = 0
fc_for_col:
  bge   $t1, $t0, fc_end_for_col  # col < size
  div   $a0, $t0
  mfhi  $t2             # position % size
  mflo  $t3             # position / size
  beq   $t1, $t2, fc_for_col_continue    # if (col != position % size)
  mul   $t4, $t3, $t0
  add   $t4, $t4, $t1   # position / size * size + col
  mul   $t4, $t4, 8
  lw    $t5, 4($a1) # puzzle->grid
  add   $t4, $t4, $t5   # &puzzle->grid[position / size * size + col].domain
  mul   $t2, $a0, 8   # position * 8
  add   $t2, $t5, $t2 # puzzle->grid[position]
  lw    $t2, 0($t2) # puzzle -> grid[position].domain
  not   $t2, $t2        # ~puzzle->grid[position].domain
  lw    $t3, 0($t4) #
  and   $t3, $t3, $t2
  sw    $t3, 0($t4)
  beq   $t3, $0, fc_return_zero # if (!puzzle->grid[position / size * size + col].domain)
fc_for_col_continue:
  add   $t1, $t1, 1     # col++
  j     fc_for_col
fc_end_for_col:
  li    $t1, 0          # row = 0
fc_for_row:
  bge   $t1, $t0, fc_end_for_row  # row < size
  div   $a0, $t0
  mflo  $t2             # position / size
  mfhi  $t3             # position % size
  beq   $t1, $t2, fc_for_row_continue
  lw    $t2, 4($a1)     # puzzle->grid
  mul   $t4, $t1, $t0
  add   $t4, $t4, $t3
  mul   $t4, $t4, 8
  add   $t4, $t2, $t4   # &puzzle->grid[row * size + position % size]
  lw    $t6, 0($t4)
  mul   $t5, $a0, 8
  add   $t5, $t2, $t5
  lw    $t5, 0($t5)     # puzzle->grid[position].domain
  not   $t5, $t5
  and   $t5, $t6, $t5
  sw    $t5, 0($t4)
  beq   $t5, $0, fc_return_zero
fc_for_row_continue:
  add   $t1, $t1, 1     # row++
  j     fc_for_row
fc_end_for_row:

  li    $s0, 0          # i = 0
fc_for_i:
  lw    $t2, 4($a1)
  mul   $t3, $a0, 8
  add   $t2, $t2, $t3
  lw    $t2, 4($t2)     # &puzzle->grid[position].cage
  lw    $t3, 8($t2)     # puzzle->grid[position].cage->num_cell
  bge   $s0, $t3, fc_return_one
  lw    $t3, 12($t2)    # puzzle->grid[position].cage->positions
  mul   $s1, $s0, 4
  add   $t3, $t3, $s1
  lw    $t3, 0($t3)     # pos
  lw    $s1, 4($a1)
  mul   $s2, $t3, 8
  add   $s2, $s1, $s2   # &puzzle->grid[pos].domain
  lw    $s1, 0($s2)
  move  $a0, $t3
  jal get_domain_for_cell
  lw    $a0, 4($sp)
  lw    $a1, 8($sp)
  and   $s1, $s1, $v0
  sw    $s1, 0($s2)     # puzzle->grid[pos].domain &= get_domain_for_cell(pos, puzzle)
  beq   $s1, $0, fc_return_zero
fc_for_i_continue:
  add   $s0, $s0, 1     # i++
  j     fc_for_i
fc_return_one:
  li    $v0, 1
  j     fc_return
fc_return_zero:
  li    $v0, 0
fc_return:
  lw    $ra, 0($sp)
  lw    $a0, 4($sp)
  lw    $a1, 8($sp)
  lw    $s0, 12($sp)
  lw    $s1, 16($sp)
  lw    $s2, 20($sp)
  add   $sp, $sp, 24
  jr    $ra
.text

## struct Puzzle {
##   int size;
##   Cell* grid;
## };
##
## struct Solution {
##   int size;
##   int assignment[81];
## };
##
## // Returns next position for assignment.
## int get_unassigned_position(const Solution* solution, const Puzzle* puzzle) {
##   int unassigned_pos = 0;
##   for (; unassigned_pos < puzzle->size * puzzle->size; unassigned_pos++) {
##     if (solution->assignment[unassigned_pos] == 0) {
##       break;
##     }
##   }
##   return unassigned_pos;
## }

get_unassigned_position:
  li    $v0, 0            # unassigned_pos = 0
  lw    $t0, 0($a1)       # puzzle->size
  mul  $t0, $t0, $t0     # puzzle->size * puzzle->size
  add   $t1, $a0, 4       # &solution->assignment[0]
get_unassigned_position_for_begin:
  bge   $v0, $t0, get_unassigned_position_return  # if (unassigned_pos < puzzle->size * puzzle->size)
  mul  $t2, $v0, 4
  add   $t2, $t1, $t2     # &solution->assignment[unassigned_pos]
  lw    $t2, 0($t2)       # solution->assignment[unassigned_pos]
  beq   $t2, 0, get_unassigned_position_return  # if (solution->assignment[unassigned_pos] == 0)
  add   $v0, $v0, 1       # unassigned_pos++
  j   get_unassigned_position_for_begin
get_unassigned_position_return:
  jr    $ra
.text

## struct Puzzle {
##   int size;
##   Cell* grid;
## };
##
## struct Solution {
##   int size;
##   int assignment[81];
## };
##
## // Checks if the solution is complete.
## int is_complete(const Solution* solution, const Puzzle* puzzle) {
##   return solution->size == puzzle->size * puzzle->size;
## }

is_complete:
  lw    $t0, 0($a0)       # solution->size
  lw    $t1, 0($a1)       # puzzle->size
  mul   $t1, $t1, $t1     # puzzle->size * puzzle->size
  move	$v0, $0
  seq   $v0, $t0, $t1
  j     $ra
.text

## struct Cage {
##   char operation;
##   int target;
##   int num_cell;
##   int* positions;
## };
##
## struct Cell {
##   int domain;
##   Cage* cage;
## };
##
## struct Puzzle {
##   int size;
##   Cell* grid;
## };
##
## struct Solution {
##   int size;
##   int assignment[81];
## };
##
## int recursive_backtracking(Solution* solution, Puzzle* puzzle) {
##   if (is_complete(solution, puzzle)) {
##     return 1;
##   }
##   int position = get_unassigned_position(solution, puzzle);          // Get next cell to work on
##   for (int val = 1; val < puzzle->size + 1; val++) {                 // Try out a value
##     if (puzzle->grid[position].domain & (0x1 << (val - 1))) {        // Is this value possible?
##       solution->assignment[position] = val;                          // Let's assume that this is answer
##       solution->size += 1;
##       // Applies inference to reduce space of possible assignment.
##       Puzzle puzzle_copy;
##       Cell grid_copy [81]; // 81 is the maximum size of the grid.
##       puzzle_copy.grid = grid_copy;
##       clone(puzzle, &puzzle_copy);                                   // Copy stuff in case this isn't really the right answer
##       puzzle_copy.grid[position].domain = 0x1 << (val - 1);          // Treat the puzzle as if this was a given solution
##       if (forward_checking(position, &puzzle_copy)) {                // Does it check out so far?
##         if (recursive_backtracking(solution, &puzzle_copy)) {        // Let's keep going!
##           return 1;
##         }
##       }
##       solution->assignment[position] = 0;                            // JK, this wasn't actually the right answer
##       solution->size -= 1;
##     }
##   }
##   return 0;                                                          // There was no solution for this version
## }


recursive_backtracking:
  sub   $sp, $sp, 680
  sw    $ra, 0($sp)
  sw    $a0, 4($sp)     # solution
  sw    $a1, 8($sp)     # puzzle
  sw    $s0, 12($sp)    # position
  sw    $s1, 16($sp)    # val
  sw    $s2, 20($sp)    # 0x1 << (val - 1)
                        # sizeof(Puzzle) = 8
                        # sizeof(Cell [81]) = 648

  jal   is_complete
  bne   $v0, $0, recursive_backtracking_return_one
  lw    $a0, 4($sp)     # solution
  lw    $a1, 8($sp)     # puzzle
  jal   get_unassigned_position
  move  $s0, $v0        # position
  li    $s1, 1          # val = 1
recursive_backtracking_for_loop:
  lw    $a0, 4($sp)     # solution
  lw    $a1, 8($sp)     # puzzle
  lw    $t0, 0($a1)     # puzzle->size
  add   $t1, $t0, 1     # puzzle->size + 1
  bge   $s1, $t1, recursive_backtracking_return_zero  # val < puzzle->size + 1
  lw    $t1, 4($a1)     # puzzle->grid
  mul   $t4, $s0, 8     # sizeof(Cell) = 8
  add   $t1, $t1, $t4   # &puzzle->grid[position]
  lw    $t1, 0($t1)     # puzzle->grid[position].domain
  sub   $t4, $s1, 1     # val - 1
  li    $t5, 1
  sll   $s2, $t5, $t4   # 0x1 << (val - 1)
  and   $t1, $t1, $s2   # puzzle->grid[position].domain & (0x1 << (val - 1))
  beq   $t1, $0, recursive_backtracking_for_loop_continue # if (domain & (0x1 << (val - 1)))
  mul   $t0, $s0, 4     # position * 4
  add   $t0, $t0, $a0
  add   $t0, $t0, 4     # &solution->assignment[position]
  sw    $s1, 0($t0)     # solution->assignment[position] = val
  lw    $t0, 0($a0)     # solution->size
  add   $t0, $t0, 1
  sw    $t0, 0($a0)     # solution->size++
  add   $t0, $sp, 32    # &grid_copy
  sw    $t0, 28($sp)    # puzzle_copy.grid = grid_copy !!!
  move  $a0, $a1        # &puzzle
  add   $a1, $sp, 24    # &puzzle_copy
  jal   clone           # clone(puzzle, &puzzle_copy)
  mul   $t0, $s0, 8     # !!! grid size 8
  lw    $t1, 28($sp)

  add   $t1, $t1, $t0   # &puzzle_copy.grid[position]
  sw    $s2, 0($t1)     # puzzle_copy.grid[position].domain = 0x1 << (val - 1);
  move  $a0, $s0
  add   $a1, $sp, 24
  jal   forward_checking  # forward_checking(position, &puzzle_copy)
  beq   $v0, $0, recursive_backtracking_skip

  lw    $a0, 4($sp)     # solution
  add   $a1, $sp, 24    # &puzzle_copy
  jal   recursive_backtracking
  beq   $v0, $0, recursive_backtracking_skip
  j     recursive_backtracking_return_one # if (recursive_backtracking(solution, &puzzle_copy))
recursive_backtracking_skip:
  lw    $a0, 4($sp)     # solution
  mul   $t0, $s0, 4
  add   $t1, $a0, 4
  add   $t1, $t1, $t0
  sw    $0, 0($t1)      # solution->assignment[position] = 0
  lw    $t0, 0($a0)
  sub   $t0, $t0, 1
  sw    $t0, 0($a0)     # solution->size -= 1
recursive_backtracking_for_loop_continue:
  add   $s1, $s1, 1     # val++
  j     recursive_backtracking_for_loop
recursive_backtracking_return_zero:
  li    $v0, 0
  j     recursive_backtracking_return
recursive_backtracking_return_one:
  li    $v0, 1
recursive_backtracking_return:
  lw    $ra, 0($sp)
  lw    $a0, 4($sp)
  lw    $a1, 8($sp)
  lw    $s0, 12($sp)
  lw    $s1, 16($sp)
  lw    $s2, 20($sp)
  add   $sp, $sp, 680
  jr    $ra
.text
# NOTE: the original cells must be copied into the first set of cells
# int iterative_backtracking() {
#         // While we still have more cells to work on
#                 // Get next empty cell in solution
#                 // While increment that cell to potential new value is good
#                         // If this value is possible
#                                 // Let's assume that this is the answer
#                                 // Copy stuff into next cell grid & make that the current grid
#                                 // If forward checking is good
#                                         // Break
#                                 // Go back to the old grid
#                 // If we couldn't find a potential value
#                         // Set back the solution & current grid appropriately
#                         // If set back made the whole solution go to 0, then return 0
#                 // Else do nothing
#         // We did it!
#
#         // While progress < puzzle->size * puzzle->size
#                 // bool reset_back_to_0 = 1
#                 // If ( solution->assignment[progress] = (solution->assignment[progress] + 1) % (puzzle->size + 1) )
#                         // reset_back_to_0 = 0
#                         // int val = solution->assignment[progress]
#                         // If (puzzle->grid[progress].domain & (0x1 << (val - 1))
#                                 // clone_to_next_grid()
#                                 // puzzle->grid = cells + (progress + 1) * 81 * sizeof(Cell)
#                                 // puzzle->grid[progress].domain = 0x1 << (val - 1)
#                                 // If (forward_checking(progress, puzzle))
#                                         // progress ++
#                                 // Else puzzle->grid = cells + (progress) * 81 * sizeof(Cell)
#                 // If (reset_back_to_0)
#                         // progress--
#                         // puzzle->grid = cells + (progress) * 81 * sizeof(Cell)
#                         // If (progress == 0 && solution->assignment[progress] == 0) return 0
#
#         // Done!
#         // return 1
# }

iterative_backtracking:
        sub                $sp, $sp, 20                # $sp = $sp - _
        sw                $ra, 0($sp)                #
        sw                $s0, 4($sp)                # progress
        sw                $s1, 8($sp)                # puzzle->size
        sw                $s2, 12($sp)                # reset_back_to_0
        sw                $s3, 16($sp)                # val


        la                $s0, progress                #
        lw                $s0, 0($s0)                # progress

        la                $t0, puzzle                #
        lw                $s1, 0($t0)                # puzzle->size

iterative_backtracking_loop:
        mul               $t1, $s1, $s1                 # puzzle->size ^ 2
        bge                $s0, $t1, iterative_backtracking_end        # if  >=  then iterative_backtracking_end
        li                $s2, 1                # reset_back_to_0
        la                $t3, solution                #
        add                $t3, $t3, 4                # solution->assignment
        mul               $t4, $s0, 4                   # sizeof(assignment) = 4
        add                $t5, $t3, $t4                # solution->assignment + progress
        lw                $s3, 0($t5)                # solution->assignment[progress]
        add                $s3, $s3, 1                # $s3 = $s3 + 1
        add                $t0, $s1, 1                # puzzle->size + 1
        rem               $s3, $s3, $t0               # (solution->assignment[progress] + 1) % (puzzle->size + 1)
                                                                # also serves as int val
        sw                $s3, 0($t5)                # solution->assignment[progress] = (solution->assignment[progress] + 1) % (puzzle->size + 1)


        beq                $s3, 0, iterative_backtracking_check_reset        # if $s3 == 0 then iterative_backtracking_check_reset
        li                $s2, 0                # reset_back_to_0 = 0

        la                $t7, puzzle                #
        lw                $t7, 4($t7)                # puzzle->grid
        mul               $t8, $s0, 8                   # sizeof(Cell) = 8
        add                $t7, $t7, $t8                # puzzle->grid + progress
        lw                $t9, 0($t7)                # puzzle->grid[progress].domain
        li                $t3, 1                # 0x1
        sub                $t6, $s3, 1                # val - 1
        sll               $t3, $t3, $t6         # 0x1 << (val - 1)

        and               $t4, $t9, $t3              # puzzle->grid[progress].domain & 0x1 << (val - 1)
        beq                $t4, 0, iterative_backtracking_check_reset        # if $t4 == 0 then iterative_backtracking_check_reset

        move         $a0, $s0                # pass in progress
        jal                clone_to_next_grid                                # jump to clone_to_next_grid and save position to $ra

        la                $t4, cells                # cells
        add                $t0, $s0, 1                # progress + 1
        mul               $t5, $t0, 648                 # (progress + 1) * 81 * sizeof(Cell) = progress * 648
        add                $t6, $t4, $t5                # cells + (progress + 1) * 81 * sizeof(Cell)
        la                $t4, puzzle                #
        sw                $t6, 4($t4)                # puzzle->grid = cells + (progress + 1) * 81 * sizeof(Cell)

        mul             $t5, $s0, 8                     # sizeof(Cell) = 8
        add                $t7, $t6, $t5                # puzzle->grid + progress
        li                $t3, 1                # 0x1
        sub                $t6, $s3, 1                # val - 1
        sll               $t3, $t3, $t6         # 0x1 << (val - 1)
        sw                $t3, 0($t7)                # puzzle->grid[progress].domain = 0x1 << (val - 1)

        move         $a0, $s0                # progress
        la                $a1, puzzle                #
        jal                forward_checking                                # jump to forward_checking and save position to $ra
        beq                $v0, 0, iterative_backtracking_forward_check        # if $v0 == 0 then iterative_backtracking_forward_check
        add                $s0, $s0, 1                # progress ++
        j                iterative_backtracking_check_reset                                # jump to iterative_backtracking_check_reset
iterative_backtracking_forward_check:
        la                $t4, cells                # cells
        mul               $t5, $s0, 648                 # progress * 81 * sizeof(Cell) = progress * 648
        add                $t6, $t4, $t5                # cells + progress * 81 * sizeof(Cell)
        la                $t4, puzzle                #
        sw                $t6, 4($t4)                # puzzle->grid = cells + progress * 81 * sizeof(Cell)

iterative_backtracking_check_reset:
        beq                $s2, 0, iterative_backtracking_loop_back        # if $s2 == 0 then iterative_backtracking_loop_back
        sub                $s0, $s0, 1                # progress--
        la                $t4, cells                # cells
        mul               $t5, $s0, 648                 # progress * 81 * sizeof(Cell) = progress * 648
        add                $t6, $t4, $t5                # cells + progress * 81 * sizeof(Cell)
        la                $t4, puzzle                #
        sw                $t6, 4($t4)                # puzzle->grid = cells + progress * 81 * sizeof(Cell)

        bne                $s0, 0, iterative_backtracking_loop_back        # if  != 0 then iterative_backtracking_loop_back
        la                $t0, solution                #
        add                $t0, $t0, 4                # solution->assignment
        lw                $t0, 0($t0)                # solution->assignment[0]
        bne                $t0, 0, iterative_backtracking_loop_back        # if  != 0 then iterative_backtracking_loop_back
        j                iterative_backtracking_end                                #
iterative_backtracking_loop_back:
        j                iterative_backtracking_loop                                # jump to iterative_backtracking_loop

iterative_backtracking_end:
        mul             $t0, $s1, $s1
        la                $t1, solution                #
        sw                $t0, 0($t1)                # solution->size = puzzle->size ^ 2

        beq                $s0, 0, iterative_backtracking_failure        # if $s0 == 0 then iterative_backtracking_failure
        li                $v0, 1                # $v0 = 1
        j                iterative_backtracking_return                                # jump to iterative_backtracking_return
iterative_backtracking_failure:
        li                $v0, 0                # $v0 = 0
iterative_backtracking_return:
        lw                $ra, 0($sp)                #
        lw                $s0, 4($sp)                # progress
        lw                $s1, 8($sp)                # puzzle->size
        lw                $s2, 12($sp)                # reset_back_to_0
        lw                $s3, 16($sp)                # value
        add                $sp, $sp, 20                # $sp = $sp - _
        jr                $ra                                        # jump to


# -----------------------------------
# $a0 - progress
# -----------------------------------
clone_to_next_grid:

        la                $t4, cells                # cells
        mul               $t5, $a0, 648                 # progress * 81 * sizeof(Cell) = progress * 648
        add                $t6, $t4, $t5                # cells + progress * 81 * sizeof(Cell)

        add                $t7, $t6, 648                # cells + (progress + 1) * 81 * sizeof(Cell)

        lw                $t0, puzzle                #
        mul             $t0, $t0, $t0           # puzzle->size ^ 2
        li                $t1, 0                # $t1 = 0
clone_to_next_grid_loop:
        bge                $t1, $t0, clone_to_next_grid_end        # if $t1 >= 162 then clone_to_next_grid_end
        lw                $t2, 0($t6)                # source
        sw                $t2, 0($t7)                # dest

        lw                $t2, 4($t6)                # source
        sw                $t2, 4($t7)                # dest

        add                $t6, $t6, 8                #
        add                $t7, $t7, 8                # sizeof(Cell) = 8

        add                $t1, $t1, 1                # $t1 = $t1 + 1
        j                clone_to_next_grid_loop                                # jump to clone_to_next_grid_loop
clone_to_next_grid_end:
        jr                $ra                                        # jump to

initialize_cells:
        la                $t0, puzzle                #
        lw                $t1, 4($t0)                # puzzle->grid

        la                $t2, cells                #
        sw                $t2, 4($t0)                # puzzle->grid = cells

        lw                $t5, puzzle                #
        mul             $t5, $t5, $t5           # puzzle->size ^ 2

        li                $t3, 0                # $t3 = 0
initialize_cells_loop:
        bge                $t3, $t5, initialize_cells_end        # if $t3 >= 81 then initialize_cells_end
        lw                $t4, 0($t1)                #
        sw                $t4, 0($t2)                #

        lw                $t4, 4($t1)                #
        sw                $t4, 4($t2)                #

        add                $t1, $t1, 8                #
        add                $t2, $t2, 8                # sizeof(Cell) = 8

        add                $t3, $t3, 1                # $t3 = $t3 + 1
        j                initialize_cells_loop                                # jump to initialize_cells_loop
initialize_cells_end:
        li                $t0, 1                # $t0 = 1
        sw                $t0, cells_are_initialized                # 
        jr                $ra                                        # jump to $ra
.text

## int
## convert_highest_bit_to_int(int domain) {
##     int result = 0;
##     for (; domain; domain >>= 1) {
##         result++;
##     }
##     return result;
## }

convert_highest_bit_to_int:
    move  $v0, $0             # result = 0

chbti_loop:
    beq   $a0, $0, chbti_end
    add   $v0, $v0, 1         # result ++
    sra   $a0, $a0, 1         # domain >>= 1
    j     chbti_loop

chbti_end:
    jr    $ra

is_single_value_domain:
    beq    $a0, $0, isvd_zero     # return 0 if domain == 0
    sub    $t0, $a0, 1	          # (domain - 1)
    and    $t0, $t0, $a0          # (domain & (domain - 1))
    bne    $t0, $0, isvd_zero     # return 0 if (domain & (domain - 1)) != 0
    li     $v0, 1
    jr	   $ra

isvd_zero:
    li	   $v0, 0
    jr	   $ra

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
    sll    $t0, $t1, $t0                # 1 << high_bits
    sub    $t0, $t0, 1                  # (1 << high_bits) - 1
    and    $s2, $s2, $t0                # domain & ((1 << high_bits) - 1)

gdfa_skip1:
    sub    $t0, $s1, 1                  # num_cell - 1
    mul    $t0, $t0, $s3                # (num_cell - 1) * upper_bound
    sub    $t0, $s0, $t0                # t0 = low_bits
    ble    $t0, $0, gdfa_skip2

    sub    $t0, $t0, 1                  # low_bits - 1
    sra    $s2, $s2, $t0                # domain >> (low_bits - 1)
    sll    $s2, $s2, $t0                # domain >> (low_bits - 1) << (low_bits - 1)

gdfa_skip2:
    move   $v0, $s2                     # return domain
    lw     $ra, 0($sp)
    lw     $s0, 4($sp)
    lw     $s1, 8($sp)
    lw     $s2, 12($sp)
    lw     $s3, 16($sp)
    add    $sp, $sp, 20
    jr     $ra

get_domain_for_subtraction:
        li     $t0, 1
        li     $t1, 2
        mul    $t1, $t1, $a0            # target * 2
        sll    $t1, $t0, $t1            # 1 << (target * 2)
        or     $t0, $t0, $t1            # t0 = base_mask
        li     $t1, 0                   # t1 = mask

gdfs_loop:
        beq    $a2, $0, gdfs_loop_end
        and    $t2, $a2, 1              # other_domain & 1
        beq    $t2, $0, gdfs_if_end

        sra    $t2, $t0, $a0            # base_mask >> target
        or     $t1, $t1, $t2            # mask |= (base_mask >> target)

gdfs_if_end:
        sll    $t0, $t0, 1              # base_mask <<= 1
        sra    $a2, $a2, 1              # other_domain >>= 1
        j      gdfs_loop

gdfs_loop_end:
        and    $v0, $a1, $t1            # domain & mask
        jr	   $ra

get_domain_for_cell:
    # save registers
    sub $sp, $sp, 36
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)
    sw $s4, 20($sp)
    sw $s5, 24($sp)
    sw $s6, 28($sp)
    sw $s7, 32($sp)

    li $t0, 0 # valid_domain
    lw $t1, 4($a1) # puzzle->grid (t1 free)
    sll $t2, $a0, 3 # position*8 (actual offset) (t2 free)
    add $t3, $t1, $t2 # &puzzle->grid[position]
    lw  $t4, 4($t3) # &puzzle->grid[position].cage
    lw  $t5, 0($t4) # puzzle->grid[posiition].cage->operation

    lw $t2, 4($t4) # puzzle->grid[position].cage->target

    move $s0, $t2   # remain_target = $s0  *!*!
    lw $s1, 8($t4) # remain_cell = $s1 = puzzle->grid[position].cage->num_cell
    lw $s2, 0($t3) # domain_union = $s2 = puzzle->grid[position].domain
    move $s3, $t4 # puzzle->grid[position].cage
    li $s4, 0   # i = 0
    move $s5, $t1 # $s5 = puzzle->grid
    move $s6, $a0 # $s6 = position
    # move $s7, $s2 # $s7 = puzzle->grid[position].domain

    bne $t5, 0, gdfc_check_else_if

    li $t1, 1
    sub $t2, $t2, $t1 # (puzzle->grid[position].cage->target-1)
    sll $v0, $t1, $t2 # valid_domain = 0x1 << (prev line comment)
    j gdfc_end # somewhere!!!!!!!!

gdfc_check_else_if:
    bne $t5, '+', gdfc_check_else

gdfc_else_if_loop:
    lw $t5, 8($s3) # puzzle->grid[position].cage->num_cell
    bge $s4, $t5, gdfc_for_end # branch if i >= puzzle->grid[position].cage->num_cell
    sll $t1, $s4, 2 # i*4
    lw $t6, 12($s3) # puzzle->grid[position].cage->positions
    add $t1, $t6, $t1 # &puzzle->grid[position].cage->positions[i]
    lw $t1, 0($t1) # pos = puzzle->grid[position].cage->positions[i]
    add $s4, $s4, 1 # i++

    sll $t2, $t1, 3 # pos * 8
    add $s7, $s5, $t2 # &puzzle->grid[pos]
    lw  $s7, 0($s7) # puzzle->grid[pos].domain

    beq $t1, $s6 gdfc_else_if_else # branch if pos == position



    move $a0, $s7 # $a0 = puzzle->grid[pos].domain
    jal is_single_value_domain
    bne $v0, 1 gdfc_else_if_else # branch if !is_single_value_domain()
    move $a0, $s7
    jal convert_highest_bit_to_int
    sub $s0, $s0, $v0 # remain_target -= convert_highest_bit_to_int
    addi $s1, $s1, -1 # remain_cell -= 1
    j gdfc_else_if_loop
gdfc_else_if_else:
    or $s2, $s2, $s7 # domain_union |= puzzle->grid[pos].domain
    j gdfc_else_if_loop

gdfc_for_end:
    move $a0, $s0
    move $a1, $s1
    move $a2, $s2
    jal get_domain_for_addition # $v0 = valid_domain = get_domain_for_addition()
    j gdfc_end

gdfc_check_else:
    lw $t3, 12($s3) # puzzle->grid[position].cage->positions
    lw $t0, 0($t3) # puzzle->grid[position].cage->positions[0]
    lw $t1, 4($t3) # puzzle->grid[position].cage->positions[1]
    xor $t0, $t0, $t1
    xor $t0, $t0, $s6 # other_pos = $t0 = $t0 ^ position
    lw $a0, 4($s3) # puzzle->grid[position].cage->target

    sll $t2, $s6, 3 # position * 8
    add $a1, $s5, $t2 # &puzzle->grid[position]
    lw  $a1, 0($a1) # puzzle->grid[position].domain
    # move $a1, $s7

    sll $t1, $t0, 3 # other_pos*8 (actual offset)
    add $t3, $s5, $t1 # &puzzle->grid[other_pos]
    lw $a2, 0($t3)  # puzzle->grid[other_pos].domian

    jal get_domain_for_subtraction # $v0 = valid_domain = get_domain_for_subtraction()
    # j gdfc_end
gdfc_end:
# restore registers

    lw $ra, 0($sp)
    lw $s0, 4($sp)
    lw $s1, 8($sp)
    lw $s2, 12($sp)
    lw $s3, 16($sp)
    lw $s4, 20($sp)
    lw $s5, 24($sp)
    lw $s6, 28($sp)
    lw $s7, 32($sp)
    add $sp, $sp, 36
    jr $ra


clone:

    lw  $t0, 0($a0)
    sw  $t0, 0($a1)

    mul $t0, $t0, $t0
    mul $t0, $t0, 2 # two words in one grid

    lw  $t1, 4($a0) # &puzzle(ori).grid
    lw  $t2, 4($a1) # &puzzle(clone).grid

    li  $t3, 0 # i = 0;
clone_for_loop:
    bge  $t3, $t0, clone_for_loop_end
    sll $t4, $t3, 2 # i * 4
    add $t5, $t1, $t4 # puzzle(ori).grid ith word
    lw   $t6, 0($t5)

    add $t5, $t2, $t4 # puzzle(clone).grid ith word
    sw   $t6, 0($t5)

    addi $t3, $t3, 1 # i++

    j    clone_for_loop
clone_for_loop_end:

    jr  $ra
.text
# -----------------------------------------------------------------------
# Main function
# -----------------------------------------------------------------------
harvest_any:
	# while(get_next_plant() != -1) {
	# 	move_to harvestable plant
	# 	harevest the plant
	# }
	sub		$sp, $sp, 8		# $sp = $sp - 4
	sw		$ra, 0($sp)		#
	sw		$s0, 4($sp)		#
harvest_any_loop:
	li		$a0, 0		# $a0 = 0
	jal		get_next_plant				# jump to get_next_plant and save position to $ra
	beq		$v0, -1, harvest_any_end	# if $v0 == -1 then harvest_any_end
	move 	$a0, $v0		# $a0 = $v0
	move 	$a1, $v1		# $a1 = $v1
	jal		try_to_harvest				# jump to try_to_harvest and save position to $ra
	j		harvest_any_loop				# jump to harvest_any_loop
harvest_any_end:
	lw		$ra, 0($sp)		#
	lw		$s0, 4($sp)		#
	add		$sp, $sp, 8		# $sp = $sp + 4
	jr		$ra					# jump to
# END_HARVEST_ANY


# -----------------------------------------------------------------------
# Main function
# -----------------------------------------------------------------------
farm:
	sub		$sp, $sp, 8		# $sp = $sp - 4
	sw		$ra, 0($sp)		#
	sw		$s0, 4($sp)		#

farm_loop:
	jal		have_enough_farm_resources				# jump to have_enough_farm_resources and save position to $ra
	bne		$v0, 1, farm_end	# if $v0 != 1 then farm_end

	jal		get_enemy_fire_rate				# jump to get_enemy_fire_rate and save position to $ra
	move 	$s0, $v0		# $s0 = $v0
	bne		$s0, 3, farm_fire_rate_not_annoying	# if $v0 != 3 then
	jal		plant_few				# jump to plant_few and save position to $ra
	j		farm_end				# jump to farm_end
farm_fire_rate_not_annoying:

farm_get_away_from_enemy:
	jal		find_loc_away_from_enemy				# jump to find_loc_away_from_enemy and save position to $ra
	move 	$a0, $v0		# $a0 = $v0
	move 	$a1, $v1		# $a1 = $v1
	jal		move_to				# jump to move_to and save position to $ra
	lw		$t0, BOT_X		#
	lw		$t1, OTHER_BOT_X		#
	sub		$a0, $t0, $t1		# x difference

	lw		$t0, BOT_Y		#
	lw		$t1, OTHER_BOT_Y		#
	sub		$a1, $t0, $t1		# y difference
	jal		euclidean_dist				# jump to euclidean_dist and save position to $ra
	blt		$v0, 45, farm_get_away_from_enemy	# enemy might have been following us

	jal		find_loc_away_from_enemy				# jump to find_loc_away_from_enemy and save position to $ra
	move 	$a0, $v0		# $a0 = $v0
	move 	$a1, $v1		# $a1 = $v1
	move 	$a2, $s0		# $a0 = $s0
	jal		actually_farm				# jump to actually_farm and save position to $ra

	j		farm_loop				# jump to farm

farm_end:
	lw		$ra, 0($sp)		#
	lw		$s0, 4($sp)		#
	add		$sp, $sp, 8		# $sp = $sp + 4
	jr		$ra					# jump to
# END_FARM

# -----------------------------------------------------------------------
# helper farm function
# $a0 - x coordinate
# $a1 - y coordinate
# $a2 - fire rate
# -----------------------------------------------------------------------
actually_farm:
	sub		$sp, $sp, 8		# $sp = $sp - _
	sw		$ra, 0($sp)		#
	sw		$s0, 4($sp)		#

	move 	$s0, $a2		# $s0 = $a2
	jal		move_to				# jump to move_to and save position to $ra

	# call one of these three function
	blt		$s0, 2, actually_farm_check_moderate_or_safe	# if $a2 < 3 then actually_farm_check_moderate_or_safe
	jal		plant_and_harvest_cross				# jump to plant_and_harvest_cross and save position to $ra
	j		actually_farm_end				# jump to actually_farm_end

actually_farm_check_moderate_or_safe:
	blt		$s0, 1, actually_farm_plant_and_harvest_safe	# if $a2 < 2 then
	jal		plant_and_harvest_moderate				# jump to plant_and_harvest_moderate and save position to $ra
	j		actually_farm_end				# jump to actually_farm_end

actually_farm_plant_and_harvest_safe:
	jal		plant_and_harvest_safe				# jump to plant_and_harvest_safe and save position to $ra

actually_farm_end:
	lw		$ra, 0($sp)		#
	lw		$s0, 4($sp)		#
	add		$sp, $sp, 8		# $sp = $sp + _
	jr		$ra					# jump to
# END_ACTUALLY_FARM

# -----------------------------------------------------------------------
# waters a tile by a certain amount
# does not waste water by checking just the state
# $a0 - x index
# $a1 - y index
# $a2 - amount
# -----------------------------------------------------------------------
water:
	sub		$sp, $sp, 12		# $sp = $sp - 12
	sw		$ra, 0($sp)		#
	sw		$s0, 4($sp)		#
	sw		$s1, 8($sp)		#

	mul		$s1, $a1, 10
	add		$s1, $s1, $a0		# index

	move 	$s0, $a2		# $s0 = $a2
	jal		move_to				# jump to move_to and save position to $ra

	la		$t0, tile_data		#
	sw		$t0, TILE_SCAN		#
	mul		$s1, $s1, 16		# sizeof(TileInfo) = 16
	add		$t0, $t0, $s1		#  = $t0 + $s1
	lw		$t0, 0($t0)		# state
	beq		$t0, 0, water_skip	# if  == 0 then water_skip

	sw		$s0, WATER_TILE		#
water_skip:

	lw		$ra, 0($sp)		#
	lw		$s0, 4($sp)		#
	lw		$s1, 8($sp)		#
	add		$sp, $sp, 12		# $sp = $sp - 12
	jr		$ra					# jump to
# END WATER

# -----------------------------------------------------------------------
# checks if there is a fire at the provided location,
# if there is then it calls harvest_any and returns 1, otherwise it return 0
# NOTE: retains the $a0 and $a1 registers
# $v0 - 1 is there was fires and caller needs to exit prematurely, 0 if no fire or
# 					it wasn't on the bots current location
# -----------------------------------------------------------------------
check_fire:
	# if (fire_loc != initial_value && fire_loc.x == BOT.X && fire_loc.y == BOT.y) {
	#     PUT_OUT_FIRE(fire_loc.x, fire_loc.y)
	#     harvest_any()
	#     fire_location = 0x1111 				// reset
	# 		return 1;
	# } else {
	#			return 0;
	# }
	sub		$sp, $sp, 12
	sw		$ra, 0($sp)
	sw		$s0, 4($sp)
	sw    		$s1, 8($sp)

	# save before calling harvest_any
	move 	$s0, $a0
	move 	$s1, $a1

	li    $t1, 0x1111						# val to check against...
	lw    $t0, fire_location

	beq   $t0, $t1, no_fire			# if (fire_loc != initial_value)
	srl		$a0, $t0, 16					# t2 = fire_loc.x
	and		$a1, $t0, 0x0000ffff	# t3 = fire_loc.y

	jal		move_to				# jump to move_to and save position to $ra
	sw    $0, PUT_OUT_FIRE

	jal   harvest_any						# jump to harvest_any

	li    $t1, 0x1111
	sw    $t1, fire_location		# reset fire_location

	li    $v0, 1
	j 		end_check_fire
no_fire:
	li    $v0, 0
end_check_fire:
	# restore a resisters for calling function
	move 	$a0, $s0
	move 	$a1, $s1

	lw		$ra, 0($sp)
	lw		$s0, 4($sp)
	lw    		$s1, 8($sp)
	add		$sp, $sp, 12

	jr		$ra
# END CHECK_FIRE


# -----------------------------------------------------------------------
# plants seeds in a cross
# NOTE: does not assume any of the tiles may be enemy's plant tiles
# $a0 - x coordinate of the center
# $a1 - y coordinate of the center
# -----------------------------------------------------------------------
plant_and_harvest_cross:
	sub		$sp, $sp, 12		# $sp = $sp - 12
	sw		$ra, 0($sp)		#
	sw		$s0, 4($sp)		#
	sw		$s1, 8($sp)		#

	move 	$s0, $a0		# $s0 = $a0
	move 	$s1, $a1		# $s1 = $a1

	jal   check_fire
	beq   $v0, 1, cleanup_return_cross	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_plant				# jump to try_to_plant and save position to $ra

	move 	$a0, $s0		# $a0 = $s0
	sub		$a1, $s1, 1		# $a1 = $a1 - 1
	jal   check_fire
	beq   $v0, 1, cleanup_return_cross	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_plant				# jump to try_to_plant and save position to $ra

	add		$a0, $s0, 1		# $a0 = $a0 + 1
	move 	$a1, $s1		# $a1 = $s1
	jal   check_fire
	beq   $v0, 1, cleanup_return_cross	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_plant				# jump to try_to_plant and save position to $ra

	move 	$a0, $s0		# $a0 = $s0
	add		$a1, $s1, 1		# $a1 = $a1 + 1
	jal   check_fire
	beq   $v0, 1, cleanup_return_cross	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_plant				# jump to try_to_plant and save position to $ra

	move 	$a1, $s1		# $a1 = $s1
	sub		$a0, $s0, 1		# $a0 = $a0 - 1
	jal   check_fire
	beq   $v0, 1, cleanup_return_cross	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_plant				# jump to try_to_plant and save position to $ra

	move 	$a0, $s0		# $s0 = $a0
	move 	$a1, $s1		# $s1 = $a1

	jal   check_fire
	beq   $v0, 1, cleanup_return_cross	# if (check_fire == 1) go_to cleanup_return
	li		$a2, 24		# $a2 = 20
	jal		water				# jump to water and save position to $ra

	move 	$a0, $s0		# $a0 = $s0
	sub		$a1, $s1, 1		# $a1 = $a1 - 1
	jal   check_fire
	beq   $v0, 1, cleanup_return_cross	# if (check_fire == 1) go_to cleanup_return
	li		$a2, 24		# $a2 = 20
	jal		water				# jump to try_to_plant and save position to $ra

	add		$a0, $s0, 1		# $a0 = $a0 + 1
	move 	$a1, $s1		# $a1 = $s1
	li		$a2, 24		# $a2 = 20
	jal   check_fire
	beq   $v0, 1, cleanup_return_cross	# if (check_fire == 1) go_to cleanup_return
	jal		water				# jump to try_to_plant and save position to $ra

	move 	$a0, $s0		# $a0 = $s0
	add		$a1, $s1, 1		# $a1 = $a1 + 1
	jal   check_fire
	beq   $v0, 1, cleanup_return_cross	# if (check_fire == 1) go_to cleanup_return
	li		$a2, 24		# $a2 = 20
	jal		water				# jump to try_to_plant and save position to $ra

	move 	$a1, $s1		# $a1 = $s1
	sub		$a0, $s0, 1		# $a0 = $a0 - 1
	jal   check_fire
	beq   $v0, 1, cleanup_return_cross	# if (check_fire == 1) go_to cleanup_return
	li		$a2, 24		# $a2 = 20
	jal		water				# jump to try_to_plant and save position to $ra

	move 	$a0, $s0		# $s0 = $a0
	move 	$a1, $s1		# $s1 = $a1

	jal   check_fire
	beq   $v0, 1, cleanup_return_cross	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_harvest				# jump to water and save position to $ra

	move 	$a0, $s0		# $a0 = $s0
	sub		$a1, $s1, 1		# $a1 = $a1 - 1
	jal   check_fire
	beq   $v0, 1, cleanup_return_cross	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_harvest				# jump to try_to_plant and save position to $ra

	add		$a0, $s0, 1		# $a0 = $a0 + 1
	move 	$a1, $s1		# $a1 = $s1
	jal   check_fire
	beq   $v0, 1, cleanup_return_cross	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_harvest				# jump to try_to_plant and save position to $ra

	move 	$a0, $s0		# $a0 = $s0
	add		$a1, $s1, 1		# $a1 = $a1 + 1
	jal   check_fire
	beq   $v0, 1, cleanup_return_cross	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_harvest				# jump to try_to_plant and save position to $ra

	move 	$a1, $s1		# $a1 = $s1
	sub		$a0, $s0, 1		# $a0 = $a0 - 1
	jal   check_fire
	beq   $v0, 1, cleanup_return_cross	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_harvest				# jump to try_to_plant and save position to $ra
cleanup_return_cross:
	lw		$ra, 0($sp)		#
	lw		$s0, 4($sp)		#
	lw		$s1, 8($sp)		#
	add		$sp, $sp, 12		# $sp = $sp + 12

	jr		$ra					# jump to
#END_plant_and_harvest_cross

# -----------------------------------------------------------------------
# helper farm function
# plants in configuration and order shown below:
# |2|3|
# |1|4|
# |6|5|
# where the 1 is the start
# NOTE currently assumes that find_loc_away_from_enemy() finds a spot that is at least
# 1 tile away from any 2 edges (so it doesn't hit wall while planting)
# $a0 - x coordinate of the 1 plant
# $a1 - y coordinate of the 1 plant
# -----------------------------------------------------------------------
plant_and_harvest_moderate:
	sub		$sp, $sp, 12			# alloc stack
	sw		$ra, 0($sp)
	sw		$s0, 4($sp)
	sw		$s1, 8($sp)

	move 	$s0, $a0		# $s0 = $a0
	move 	$s1, $a1		# $s1 = $s1

	# plant 1						# @ (a0,a1)
	jal		try_to_plant	# jump to try_to_plant and save position to $ra

	# plant 2
	move 	$a0, $s0		# $a0 = $s0
	sub		$a1, $s1, 1		# $a1 = $s1 - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_moderate_cleanup_return	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_plant	# jump to try_to_plant and save position to $ra

	# plant 3
	add		$a0, $s0, 1		# $a0 = $s0 + 1
	sub		$a1, $s1, 1		# $a1 = $s1 - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_moderate_cleanup_return	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_plant	# jump to try_to_plant and save position to $ra

	# plant 4
	add		$a0, $s0, 1		# $s0a= $s0 + 1
	move 	$a1, $s1		# $s1 = $a1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_moderate_cleanup_return	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_plant	# jump to try_to_plant and save position to $ra

	# plant 5
	add		$a0, $s0, 1		# $a0 = $a0 + 1
	add		$a1, $s1, 1		# $a1 = $s1 - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_moderate_cleanup_return	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_plant	# jump to try_to_plant and save position to $ra

	# plant 6
	move 	$a0, $s0		# $a0 = $s0
	add		$a1, $s1, 1		# $a1 = $s1 + 1
	jal		try_to_plant	# jump to try_to_plant and save position to $ra

	move 	$a0, $s0		# $a0 = $s0
	move 	$a1, $s1		# $a1 = $s1
	# plant 1						# @ (a0,a1)
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_moderate_cleanup_return	# if (check_fire == 1) go_to cleanup_return
	li		$a2, 20		# $a2 = 12
	jal		water	# jump to water and save position to $ra

	# plant 2
	move 	$a0, $s0		# $a0 = $s0
	sub		$a1, $s1, 1		# $a1 = $s1 - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_moderate_cleanup_return	# if (check_fire == 1) go_to cleanup_return
	li		$a2, 20		# $a2 = 12
	jal		water	# jump to water and save position to $ra

	# plant 3
	add		$a0, $s0, 1		# $a0 = $s0 + 1
	sub		$a1, $s1, 1		# $a1 = $s1 - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_moderate_cleanup_return	# if (check_fire == 1) go_to cleanup_return
	li		$a2, 20		# $a2 = 12
	jal		water	# jump to water and save position to $ra

	# plant 4
	add		$a0, $s0, 1		# $s0a= $s0 + 1
	move 	$a1, $s1		# $s1 = $a1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_moderate_cleanup_return	# if (check_fire == 1) go_to cleanup_return
	li		$a2, 20		# $a2 = 12
	jal		water	# jump to water and save position to $ra

	# plant 5
	add		$a0, $s0, 1		# $a0 = $a0 + 1
	add		$a1, $s1, 1		# $a1 = $s1 - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_moderate_cleanup_return	# if (check_fire == 1) go_to cleanup_return
	li		$a2, 20		# $a2 = 12
	jal		water	# jump to water and save position to $ra

	# plant 6
	move 	$a0, $s0		# $a0 = $s0
	add		$a1, $s1, 1		# $a1 = $s1 + 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_moderate_cleanup_return	# if (check_fire == 1) go_to cleanup_return
	li		$a2, 20		# $a2 = 12
	jal		water	# jump to water and save position to $ra


	move 	$a0, $s0		# $a0 = $s0
	move 	$a1, $s1		# $a1 = $s1
	# plant 1						# @ (a0,a1)
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_moderate_cleanup_return	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_harvest	# jump to try_to_harvest and save position to $ra

	# plant 2
	move 	$a0, $s0		# $a0 = $s0
	sub		$a1, $s1, 1		# $a1 = $s1 - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_moderate_cleanup_return	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_harvest	# jump to try_to_harvest and save position to $ra

	# plant 3
	add		$a0, $s0, 1		# $a0 = $s0 + 1
	sub		$a1, $s1, 1		# $a1 = $s1 - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_moderate_cleanup_return	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_harvest	# jump to try_to_harvest and save position to $ra

	# plant 4
	add		$a0, $s0, 1		# $s0a= $s0 + 1
	move 	$a1, $s1		# $s1 = $a1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_moderate_cleanup_return	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_harvest	# jump to try_to_harvest and save position to $ra

	# plant 5
	add		$a0, $s0, 1		# $a0 = $a0 + 1
	add		$a1, $s1, 1		# $a1 = $s1 - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_moderate_cleanup_return	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_harvest	# jump to try_to_harvest and save position to $ra

	# plant 6
	move 	$a0, $s0		# $a0 = $s0
	add		$a1, $s1, 1		# $a1 = $s1 + 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_moderate_cleanup_return	# if (check_fire == 1) go_to cleanup_return
	jal		try_to_harvest	# jump to try_to_harvest and save position to $ra

plant_and_harvest_moderate_cleanup_return:
	lw		$ra, 0($sp)
	lw		$s0, 4($sp)
	lw		$s1, 8($sp)
	add		$sp, $sp, 12	# reset stack

	jr		$ra						# return
# END_plant_and_harvest_moderate

# -----------------------------------------------------------------------
# helper farm function
# plants in configuration and order shown below:
# |3|4|5|
# |2|1|6|
# |9|8|7|
# where the 1 is the start
# NOTE currently assumes that find_loc_away_from_enemy() finds a spot that is at least
# 1 tile away from any 2 edges (so it doesn't hit wall while planting)
# $a0 - x coordinate of the 1 plant
# $a1 - y coordinate of the 1 plant
# -----------------------------------------------------------------------
plant_and_harvest_safe:
	sub		$sp, $sp, 12			# alloc stack
	sw		$ra, 0($sp)
	sw		$s0, 4($sp)
	sw		$s1, 8($sp)

	move 	$s0, $a0		# $s0 = $a0
	move 	$s1, $a1		# $s1 = $a1

	# plant 1						# @ (a0,a1)
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_plant	# jump to try_to_plant and save position to $ra

	# plant 2
	move 	$a1, $s1
	sub		$a0, $s0, 1		# x = x - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_plant	# jump to try_to_plant and save position to $ra

	# plant 3
	sub 	$a0, $s0, 1
	sub		$a1, $s1, 1		# y = y - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_plant	# jump to try_to_plant and save position to $ra

	# plant 4
	move 	$a0, $s0
	sub		$a1, $s1, 1	# x = x + 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_plant	# jump to try_to_plant and save position to $ra

	# plant 5
	sub 	$a1, $s1, 1
	add		$a0, $s0, 1		# x = x + 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_plant	# jump to try_to_plant and save position to $ra

	# plant 6
	move 	$a1, $s1
	add		$a0, $s0, 1		# y = y + 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_plant	# jump to try_to_plant and save position to $ra

	# plant 7
	add 	$a0, $s0, 1
	add		$a1, $s1, 1		# y = y + 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_plant	# jump to try_to_plant and save position to $ra

	# plant 8
	add 	$a1, $s1, 1
	move	$a0, $s0
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_plant	# jump to try_to_plant and save position to $ra

	# plant 9
	add 	$a1, $s1, 1
	sub		$a0, $s0, 1		# x = x - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_plant	# jump to try_to_plant and save position to $ra

	move 	$a0, $s0		# $a0 = $s0
	move 	$a1, $s1		# $a1 = $s1

	# plant 1						# @ (a0,a1)

	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	li 	  $a2, 15
	jal		water	# jump to try_to_plant and save position to $ra

	# plant 2
	move 	$a1, $s1
	sub		$a0, $s0, 1		# x = x - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	li 	  $a2, 15
	jal		water	# jump to try_to_plant and save position to $ra

	# plant 3
	sub 	$a0, $s0, 1
	sub		$a1, $s1, 1		# y = y - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	li 	  $a2, 15
	jal		water	# jump to try_to_plant and save position to $ra

	# plant 4
	move 	$a0, $s0
	sub		$a1, $s1, 1	# x = x + 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	li 	  $a2, 15
	jal		water	# jump to try_to_plant and save position to $ra

	# plant 5
	sub 	$a1, $s1, 1
	add		$a0, $s0, 1		# x = x +
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	li 	  $a2, 15
	jal		water	# jump to try_to_plant and save position to $ra

	# plant 6
	move 	$a1, $s1
	add		$a0, $s0, 1		# y = y + 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	li 	  $a2, 15
	jal		water	# jump to try_to_plant and save position to $ra

	# plant 7
	add 	$a0, $s0, 1
	add		$a1, $s1, 1		# y = y + 1

	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	li 	  $a2, 15
	jal		water	# jump to try_to_plant and save position to $ra

	# plant 8
	add 	$a1, $s1, 1
	move	$a0, $s0
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	li 	  $a2, 15
	jal		water	# jump to try_to_plant and save position to $ra

	# plant 9
	add 	$a1, $s1, 1
	sub		$a0, $s0, 1		# x = x - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	li 	  $a2, 15
	jal		water	# jump to try_to_plant and save position to $ra

	move 	$a0, $s0		# $a0 = $s0
	move 	$a1, $s1		# $a1 = $s1

	# plant 1						# @ (a0,a1)
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_harvest	# jump to try_to_plant and save position to $ra

	# plant 2
	move 	$a1, $s1
	sub		$a0, $s0, 1		# x = x - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_harvest	# jump to try_to_plant and save position to $ra

	# plant 3
	sub 	$a0, $s0, 1
	sub		$a1, $s1, 1		# y = y - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_harvest	# jump to try_to_plant and save position to $ra

	# plant 4
	move 	$a0, $s0
	sub		$a1, $s1, 1	# x = x + 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_harvest	# jump to try_to_plant and save position to $ra

	# plant 5
	sub 	$a1, $s1, 1
	add		$a0, $s0, 1		# x = x + 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_harvest	# jump to try_to_plant and save position to $ra

	# plant 6
	move 	$a1, $s1
	add		$a0, $s0, 1		# y = y + 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_harvest	# jump to try_to_plant and save position to $ra

	# plant 7
	add 	$a0, $s0, 1
	add		$a1, $s1, 1		# y = y + 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_harvest	# jump to try_to_plant and save position to $ra

	# plant 8
	add 	$a1, $s1, 1
	move	$a0, $s0
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_harvest	# jump to try_to_plant and save position to $ra

	# plant 9
	add 	$a1, $s1, 1
	sub		$a0, $s0, 1		# x = x - 1
	jal   check_fire
	beq   $v0, 1, plant_and_harvest_safe_cleanup_return	# if (check_fire == 1) go_to plant_and_harvest_safe_cleanup_return
	jal		try_to_harvest	# jump to try_to_plant and save position to $ra

plant_and_harvest_safe_cleanup_return:
	lw		$ra, 0($sp)
	lw		$s0, 4($sp)
	lw		$s1, 8($sp)
	add		$sp, $sp, 12			# alloc stack
	jr		$ra

# END_plant_and_harvest_safe

# -----------------------------------------------------------------------
# helper farm function
# -----------------------------------------------------------------------
plant_few:
	sub		$sp, $sp, 4		# $sp = $sp - 4
	sw		$ra, 0($sp)		#

	jal		try_to_plant				# jump to try_to_plant and save position to $ra

	lw		$ra, 0($sp)		#
	add		$sp, $sp, 4		# $sp = $sp - 4
	jr		$ra					# jump to
# END_PLANT_FEW

# -----------------------------------------------------------------------
# attempts to harvest a plant, does not harvest a plant if there isn't any
# NOTE: this may be unnecessary because I don't know if you get points off in the tournament for harvesting a bad tile
# $a0 - x index
# $a1 - y index
# -----------------------------------------------------------------------
try_to_harvest:
	sub		$sp, $sp, 4		# $sp = $sp - 4
	sw		$ra, 0($sp)		#
	jal		move_to				# jump to move_to and save position to $ra
	sw		$zero, PUT_OUT_FIRE		#
	sw		$zero, HARVEST_TILE		#
harvest_end:
	lw		$ra, 0($sp)		#
	add		$sp, $sp, 4		# $sp = $sp + 4
	jr		$ra					# return
# END_TRY_TO_HARVEST

# -----------------------------------------------------------------------
# attempts to plant a seed at a given tile. does not plant if the tile is occupied
# $a0 - x coordinate
# $a1 - y coordinate
# -----------------------------------------------------------------------
try_to_plant:
	sub		$sp, $sp, 12		# $sp = $sp - 12
	sw		$ra, 0($sp)		#
	sw		$s0, 4($sp)		#
	sw		$s1, 8($sp)		#

	move 	$s0, $a0		# $s0 = $a0
	move 	$s1, $a1		# $s1 = $a1

	jal		move_to				# jump to move_to and save position to $ra
	la		$t0, tile_data		#
	sw		$t0, TILE_SCAN		#

	# get tile info
	mul		$t1, $s1, 10
	add		$t1, $t1, $s0		# tile index

	mul		$t1, $t1, 16		# sizeof(TileInfo) = 16
	add		$t0, $t0, $t1		# tile_data + tile index

	lw		$t0, 0($t0)		# tile_data[tile index].state
	bne		$t0, 0, try_to_plant_end	# if $t0 != 0 then try_to_plant_end

	sw		$zero, SEED_TILE		#
try_to_plant_end:
	lw		$ra, 0($sp)		#
	lw		$s0, 4($sp)		#
	lw		$s1, 8($sp)		#
	add		$sp, $sp, 12		# $sp = $sp + 12
	jr		$ra					# jump to
#END_TRY_TO_PLANT
.text
# -----------------------------------------------------------------------
# Attempts to set fire to enemy bot's plants
# NOTE: This will not work in tournament mode because it uses syscall
# -----------------------------------------------------------------------
simulate_fire_bully:
        # run around randomly (Not really)
        # at each stopping point randomly decide whether set fire to an enemy plant if possible
        sub             $sp, $sp, 12
        sw              $ra, 0($sp)
        sw                $s0, 4($sp)                #
        sw                $s1, 8($sp)                #


simulate_fire_bully_loop:
        li                $a0, 10                # $a0 = 10
        jal                random_number                                # jump to random_number and save position to $ra
        move         $s0, $v0                # $s0 = $v0

        li                $a0, 10                # $a0 = 10
        jal                random_number                                # jump to random_number and save position to $ra
        move         $a1, $v0                # $a1 = $v0
        move         $a0, $s0                # $a0 = $s0
        jal                move_to                                # jump to move_to and save position to $ra

        li                $a0, 2                # $a0 = 2
        jal                randomly_decide                                # jump to randomly_decide and save position to $ra
        beq                $v0, 1, simulate_fire_bully_try_to_set_fire        # if $v0 == 1 then simulate_fire_bully_try_to_set_fire

        j               simulate_fire_bully_loop
simulate_fire_bully_try_to_set_fire:
        # try to set fire
        li                $a0, 1                # $a0 = 1
        jal             get_best_plant_to_burn
        beq             $v0, -1, simulate_fire_bully_try_to_set_fire_skip
        move         $a0, $v0                # $a0 = $v0
        move         $a1, $v1                # $a1 = $v1
        jal                burn_enemy_plant                                # jump to burn_enemy_plant and save position to $ra

simulate_fire_bully_try_to_set_fire_skip:
        j               simulate_fire_bully_loop

        lw              $ra, 0($sp)
        lw                $s0, 4($sp)                #
        lw                $s1, 8($sp)                #
        add             $sp, $sp, 12
        jr              $ra

# -----------------------------------------------------------------------
# simulates a farming bot
# -----------------------------------------------------------------------
simulate_farming:
        sub             $sp, $sp, 12
        sw              $ra, 0($sp)
        sw                $s0, 4($sp)                #
        sw                $s1, 8($sp)                #

simulate_farming_move_around:
        li                $a0, 8                # $a0 = 10
        jal                random_number                                # jump to random_number and save position to $ra
        add                $s0, $v0, 1                # $s0 = $v0 + 1

        li                $a0, 8                # $a0 = 10
        jal                random_number                                # jump to random_number and save position to $ra
        add                $a1, $v0, 1                # $s0 = $v0 + 1
        move         $a0, $s0                # $a0 = $s0
        jal                move_to                                # jump to move_to and save position to $ra
        jal                have_enough_farm_resources                                # jump to have_enough_farm_resources and save position to $ra
        beq                $v0, 1, simulate_farming_enough_resources        # if $v0 == 1 then simulate_farming_enough_resources
        j                simulate_farming_move_around                                # jump to simulate_farming_move_around

simulate_farming_enough_resources:
        jal                plant_and_harvest_cross                                # jump to plant_and_harvest_cross and save position to $ra

        lw              $ra, 0($sp)
        lw                $s0, 4($sp)                #
        lw                $s1, 8($sp)                #
        add             $sp, $sp, 12
        jr                $ra                                        # jump to





# -----------------------------------------------------------------------
# simulates a fire spread by covering the whole board with plants and setting fire to the middle tile
# -----------------------------------------------------------------------
simulate_fire_spread:
        sub                $sp, $sp, 12                # $sp = $sp - 12
        sw                $ra, 0($sp)                #
        sw                $s0, 4($sp)                #
        sw                $s1, 8($sp)                #


        li                $a0, 0                # $a0 = 0
        li                $a1, 64                # $a1 = 100
        li                $a2, 1                # $a2 = 1
        jal                restock                                # jump to restock and save position to $ra

        li                $s0, 0                # x index
        li                $s1, 0                # y index
simulate_fire_spread_outer_loop:
        bge                $s1, 8, simulate_fire_spread_outer_loop_end        # if $s0 >= 10 then

        li                $s0, 0                # x index
simulate_fire_spread_inner_loop:
        bge                $s0, 8, simulate_fire_spread_inner_loop_end        # if $s0 >= 10 then simulate_fire_spread_inner_loop_end

        move         $a0, $s0                # $a0 = $s0
        move         $a1, $s1                # $a1 = $s1
        jal                move_to                                # jump to move_to and save position to $ra
        sw                $zero, SEED_TILE                #

        add                $s0, $s0, 1                # $s0 = $s0 + 1
        j                simulate_fire_spread_inner_loop                                # jump to simulate_fire_spread_inner_loop
simulate_fire_spread_inner_loop_end:
        add                $s1, $s1, 1                # $s1 = $s1 + 1
        j                simulate_fire_spread_outer_loop                                # jump to simulate_fire_outer_loop
simulate_fire_spread_outer_loop_end:

        li                $a0, 4                # $a0 = 5
        li                $a1, 4                # $a1 = 5
        jal                move_to                                # jump to move_to and save position to $ra
        sw                $zero, BURN_TILE                #

        lw                $ra, 0($sp)                #
        lw                $s0, 4($sp)                #
        lw                $s1, 8($sp)                #
        add                $sp, $sp, 12                # $sp = $sp + 12
        jr                $ra                                        # jump to
.data
three:	.float	3.0
five:	.float	5.0
PI:	.float	3.141592
F180:	.float  180.0

.text
# -----------------------------------------------------------------------
# moves the bot to the desired tile location
# TODO: solve ken-ken puzzle while traveling
# $a0 - x index
# $a1 - y index
# -----------------------------------------------------------------------
move_to:
	# turn towards fire
	#temporary
	sub		$sp, $sp, 24		# $sp = $sp - 8
	sw		$ra, 0($sp)		#
	sw		$a0, 4($sp)		#
	sw		$a1, 8($sp)		#
	sw		$s0, 12($sp)		#
	sw		$s1, 16($sp)		#
	sw		$s2, 20($sp)		#

	# get x_diff and y_diff
	mul	$t0, $a0, 30
	add		$t0, $t0, 15		# pixel_x
	mul	$t1, $a1, 30
	add		$t1, $t1, 15		# pixel_y

	lw		$t2, BOT_X		#
	lw		$t3, BOT_Y		#

	sub		$s0, $t0, $t2		# x_diff
	sub		$s1, $t1, $t3		# y_diff

	move 	$a0, $s0		# $a0 = $s0
	move 	$a1, $s1		# $a1 = $s1
	jal		sb_arctan				# jump to arctan and save position to $ra
	sw		$v0, ANGLE		#
	li		$t0, 1		# $t0 = 1
	sw		$t0, ANGLE_CONTROL		#

	# move towards fire
	move 	$a0, $s0		# $a0 = $s0
	move 	$a1, $s1		# $a1 = $s1
	jal		euclidean_dist				# jump to euclidean_dist and save position to $ra

	move 	$a0, $v0		# $a0 = $v0
	jal		move_distance				# jump to move_distance and save position to $ra
	jal		orient_center				# jump to orient_center and save position to $ra

	lw		$a0, 4($sp)		#
	lw		$a1, 8($sp)		#
	mul	$a1, $a1, 10
	add		$s0, $a0, $a1		# index
	jal		horizontally_align				# jump to horizontally_align and save position to $ra

	move 	$a0, $s0		# index
	jal		vertically_align				# jump to vertically_align and save position to $ra

	lw		$ra, 0($sp)		#
	lw		$a0, 4($sp)		#
	lw		$a1, 8($sp)		#
	lw		$s0, 12($sp)		#
	lw		$s1, 16($sp)		#
	lw		$s2, 20($sp)		#
	add		$sp, $sp, 24		# $sp = $sp + 8

	jr		$ra					# jump to
#END_MOVE_TO

# -----------------------------------------------------------------------
# helper function
# takes an integer argument and moves the bot forward that amount of pixels, undefined behavior if it hits a wall
# this function uses the timer interrupt to stop the bot after it has moved the specified distance
# therefore, the timer interrupt should not be used for anything else
# -----------------------------------------------------------------------
move_distance:
        sub                $sp, $sp, 4                # $sp = $sp - 4
        sw                $ra, 0($sp)                #


	# request timer interrupt
	beq		$a0, 0, move_distance_complete	# if $a0 == 0 then move_distance_complete
	lw	$t0, TIMER		# read current time
	mul	$a0, $a0, 1000
	add	$t0, $t0, $a0		# add argument amount to current time
	sw	$t0, TIMER		# request timer interrupt in argument amount of time

	li	$t1, 10
	sw	$t1, VELOCITY		# drive
move_distance_wait:
	lw		$t0, VELOCITY		#
	beq		$t0, 0, move_distance_complete	# done

        li                $a0, 0x7fffffff                # $a0 = 30000
	li		$a1, 1		# $a1 = 1
        jal                partial_solve                                # jump to partial_solve and save position to $ra

	j      move_distance_wait
move_distance_complete:
        lw                $ra, 0($sp)                #
        add                $sp, $sp, 4                # $sp = $sp + 4
	jr		$ra					# return
#END_MOVE_DISTANCE

# -----------------------------------------------------------------------
# orients the bot onto the center of the tile that it is currently on
# -----------------------------------------------------------------------
orient_center:
	sub		$sp, $sp, 20		# $sp = $sp -
	sw		$ra, 0($sp)		#
	sw		$s0, 4($sp)		#
	sw		$s1, 8($sp)		#
	sw		$s2, 12($sp)		#
	sw		$s3, 16($sp)		#

	lw		$s0, BOT_X		#
	lw		$s1, BOT_Y		#
	# we want the X and Y coordinates to be 14mod30 or 15mod30
	# if (x < 14) { face east and move until x is 14 }
	# else if (x > 15) { face west and move until x is 15 }
	rem	$s2, $s0, 30
	bge		$s2, 14, check_x_high	# checking x
	sw		$zero, ANGLE		#
	li		$s3, 1		# $s3 = 1
	sw		$s3, ANGLE_CONTROL		# face east

	li		$t0, 14		# $t0 = 14
	sub		$a0, $t0, $s2		# $a0 = 14 - $s2
	jal		move_distance				# jump to move_distance and save position to $ra

	j		x_is_aligned
check_x_high:
	ble		$s2, 15, x_is_aligned	# checking x
	li		$s3, 180		# $s3 = 180
	sw		$s3, ANGLE		#
	li		$s3, 1		# $s3 = 1
	sw		$s3, ANGLE_CONTROL		# face west

	sub		$a0, $s2, 15		# $a0 = $s2 - 15
	jal		move_distance				# jump to move_distance and save position to $ra

	j		x_is_aligned
x_is_aligned:
	# repeat for y
	rem	$s2, $s1, 30
	bge		$s2, 14, check_y_high	# checking y
	li		$s3, 90		# $s3 = -90
	sw		$s3, ANGLE		#
	li		$s3, 1		# $s3 = 1
	sw		$s3, ANGLE_CONTROL		# face south

	li		$t0, 14		# $t0 = 14
	sub		$a0, $t0, $s2		# $a0 = 14 - $s2
	jal		move_distance				# jump to move_distance and save position to $ra

	j		y_is_aligned
check_y_high:
	ble		$s2, 15, y_is_aligned	# checking y
	li		$s3, -90		# $s3 = -90
	sw		$s3, ANGLE		#
	li		$s3, 1		# $s3 = 1
	sw		$s3, ANGLE_CONTROL		# face north

	sub		$a0, $s2, 15		# $a0 = $s2 - 15
	jal		move_distance				# jump to move_distance and save position to $ra

	j		y_is_aligned
y_is_aligned:
	lw		$ra, 0($sp)		#
	lw		$s0, 4($sp)		#
	lw		$s1, 8($sp)		#
	lw		$s2, 12($sp)		#
	lw		$s3, 16($sp)		#
	add		$sp, $sp, 20		# $sp = $sp -
	jr		$ra					# return
#END_ORIENT_CENTER

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
# helper function
# takes in the index as an argument and aligns the bot horizontally
# Note that it doesn't update the real tiles
# -----------------------------------------------------------------------
horizontally_align:
	sub		$sp, $sp, 20		#
	sw		$ra, 0($sp)		#
	sw		$s0, 4($sp)		#
	sw		$s1, 8($sp)		#
	sw		$s2, 12($sp)		#
	sw		$s3, 16($sp)		#
	# int x_target = index % 10;
	# int curr_x = BOT_X / 30;
	# int distance;
	rem	$s0, $a0, 10		# x_target
	lw		$t0, BOT_X		#
	div	$s1, $t0, 30		# curr_x
	# if (x_target == curr_x) {
	# 	return;
	# }
	# if (x_target > curr_x) {
	# 	distance = x_target - curr_x;
	# 	//face east
	# } else {
	# 	distance = curr_x - x_target;
	# 	//face west
	# }
	# for (int i = 0; i < distance; i++) { //i and distance will be saved in registers $s2 and $s3 respectively
	# 	move_distance(30);
	# }
	# return;
	bne		$s0, $s1, not_horizontally_aligned	#
	j		horizontally_align_end				# jump to horizontally_align_end
not_horizontally_aligned:
	ble		$s0, $s1, horizontal_face_west	# if $s0 <= $s1 then horizontal_face_west
	sub		$s3, $s0, $s1		# distance = x_target - curr_x
	sw		$zero, ANGLE		#
	li		$t0, 1		# $t0 = 1
	sw		$t0, ANGLE_CONTROL		# face east
	j		horizontal_loop				# jump to horizontal_loop
horizontal_face_west:
	sub		$s3, $s1, $s0		# distance = curr_x - x_target
	li		$t0, 180		# $t0 = 180
	sw		$t0, ANGLE		#
	li		$t0, 1		# $t0 = 1
	sw		$t0, ANGLE_CONTROL		# face west
horizontal_loop:
	bge		$s2, $s3, horizontally_align_end	# if $s2 >= $s3 then horizontally_align_end
	li		$a0, 30		# $a0 = 30
	jal		move_distance				# jump to move_distance and save position to $ra
	addi	$s2, $s2, 1			# i++
	j		horizontal_loop				# jump to horizontal_loop
horizontally_align_end:
	lw		$ra, 0($sp)		#
	lw		$s0, 4($sp)		#
	lw		$s1, 8($sp)		#
	lw		$s2, 12($sp)		#
	lw		$s3, 16($sp)		#
	add		$sp, $sp, 20		#
	jr		$ra					# return
# END_HORIZONTALLY_ALIGN

# -----------------------------------------------------------------------
# helper function
# takes in the index as an argument and aligns the bot vertically
# Note that it doesn't update the real tiles
# -----------------------------------------------------------------------
vertically_align:
	sub		$sp, $sp, 20		#
	sw		$ra, 0($sp)		#
	sw		$s0, 4($sp)		#
	sw		$s1, 8($sp)		#
	sw		$s2, 12($sp)		#
	sw		$s3, 16($sp)		#

	# int y_target = index / 10;
	# int curr_y = BOT_Y / 30;
	# int distance;
	div	$s0, $a0, 10		# y_target
	lw		$t0, BOT_Y		#
	div	$s1, $t0, 30		# curr_y
	# if (y_target == curr_y) {
	# 	return;
	# }
	# if (y_target > curr_y) {
	# 	distance = x_target - curr_x;
	# 	//face south
	# } else {
	# 	distance = curr_y - y_target;
	# 	//face north
	# }
	# for (int i = 0; i < distance; i++) { //i and distance will be saved in registers $s2 and $s3 respectively
	# 	move_distance(30);
	# }
	# return;
	bne		$s0, $s1, not_vertically_aligned	# if $s0 != $s1 then not_vertically_aligned
	j		vertically_align_end				# jump to vertically_align_end
not_vertically_aligned:
	ble		$s0, $s1, vertical_face_north	# if $s0 <= $s1 then vertical_face_north
	sub		$s3, $s0, $s1		# distance = y_target - curr_y
	li		$t0, 90		# $t0 = 90
	sw		$t0, ANGLE		#
	li		$t0, 1		# $t0 = 1
	sw		$t0, ANGLE_CONTROL		# face south
	j		vertical_loop				# jump to vertical_loop
vertical_face_north:
	sub		$s3, $s1, $s0		# distance = curr_y - y_target
	li		$t0, -90		# $t0 = -90
	sw		$t0, ANGLE		#
	li		$t0, 1		# $t0 = 1
	sw		$t0, ANGLE_CONTROL		# face north
vertical_loop:
	bge		$s2, $s3, vertically_align_end	# if $s2 >= $s3 then vertically_align_end
	li		$a0, 30		# $a0 = 30
	jal		move_distance				# jump to move_distance and save position to $ra
	addi	$s2, $s2, 1			# i++
	j		vertical_loop				# jump to vertical_loop
vertically_align_end:
	lw		$ra, 0($sp)		#
	lw		$s0, 4($sp)		#
	lw		$s1, 8($sp)		#
	lw		$s2, 12($sp)		#
	lw		$s3, 16($sp)		#
	add		$sp, $sp, 20		#
	jr		$ra					# return
# END_VERTICALLY_ALIGN
