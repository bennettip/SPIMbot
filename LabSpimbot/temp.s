#DAN=======
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
#DAN_2=====================
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
#=============
