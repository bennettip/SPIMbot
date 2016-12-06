main_loop:
	bne		currently_moving_flag, $zero, bot_currently_moving
	# If bot stopped, then we can proceed to do these tasks

	# If our current tile is on fire, put it out! might reach here after moving to a fire tile

	# If our current tile has a grown crop, harvest! might reach here after moving to a grown tile

	#Here, we can assume that any puzzles worked on while moving have been finished right?
	#	-if we get to the desired tile before we finish the puzzle, we'd get interrupted/stopped, then continue solving it right?

checked_for_fire:
    beq fire_flag, $zero, checked_if_needed_puzzles # not checked_fire?
	# THIS FUNCTION SHOULDN'T PUT OUT THE FIRE; this should j to bot_currently_moving after we start moving towards fire
    lw  $a0, fireX
    lw  $t0, fireY
    mul $t0, $t0, 10
    add $a0, $a0, $t0                               # a0 = tileNum
    # helper function
    jal move_to
    j   bot_currently_moving                        # ?

checked_if_needed_puzzles:
	# Check if we need to request puzzles <-- here in priority because puzzles take time to arrive
	# Ordered by priority (Can we request more than one puzzle at once?)
	# 0 - water - If we have below the water needed to put out 3 fires
	# 1 - seeds - If we have below the seed threshold
	# 2 - fire starters

checked_for_grown_crop:
	# Check for fully grown crop
	beq		max_growth_flag, $zero, checked_for_grown_crop
	# THIS FUNCTION SHOULDN'T HARVEST; this should j to bot_currently_moving after we start moving towards grown crop
	jal		(go_to_grown_crop_function)

	# P lanting algorithm
#		-At first, plant in a spiral/circle pattern such that fire can't spread among crops
#		-If enemy not aggressive, switch to a method that takes advantage of water spread. (if we have time?)

	# Watering algorithm

	j		main_loop

#bot_currently_moving:
	# Check if there's a puzzle available to solve
#	bne	puzzle_flag, $zero, (solve_puzzle_function)



# This snippet of code used to test moving--------------------------------
#    li		$a0, 12	#bot will move to tile at index 12 in the tile array
#    jal		move_to
#useless_loop:
#    j		useless_loop
# -------------------------------------------------------------------------

	j		main_loop
    # End of main_loop

    j	main
    # End of main



main:
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


# BENNETT
set_resource:
    lw  $t0, GET_NUM_WATER_DROPS
    lw  $t1, GET_NUM_SEEDS
    mul $t1, $t1, 10
    lw  $t2, GET_NUM_FIRE_STARTERS
    mul $t2, $t2, 100

    ble $t1, $t0, seeds_le_water
    bgt $t0, $t2    # water < seeds. if (water < fire_starters)
    li  $t3, 0      # least water
    j   done_set_resource

seeds_le_water:
    ble $t1, $t2, least_seeds
    li  $t3, 2  # least fire starters
    j   done_set_resource

least_seeds:
    li  $t3, 1
    j   done_set_resource

done_set_resource:
    sw  $t3, SET_RESOURCE_TYPE















