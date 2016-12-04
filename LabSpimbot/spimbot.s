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
// BEN
flagFire:       .word 0
flagWhatever:   .word 0 // TEMPLETE: flags for interrupts
// BEN

.text
main:
	# go wild
	# the world is your oyster :)
	j	main

// BEN
.kdata                              # interrupt handler data (separated just for readability)
chunkIH:	.space 8                # space for two registers


.ktext 0x80000180
interrupt_handler:
.set noat
    move	$k1, $at                # Save $at # don't change k1!
.set at
    la      $k0, chunkIH
    sw      $a0, 0($k0)             # Get some free registers
    sw      $a1, 4($k0)             # by storing them to a global variable

interrupt_dispatch:                 # Interrupt:
    mfc0	$k0, $13                # Get Cause register, again
    beq     $k0, 0, done            # handled all outstanding interrupts

    and     $a0, $k0, ON_FIRE_MASK  # is there a on-fire interrupt?
    bne     $a0, 0, on_fire_interrupt

    and     $a0, $k0, SOME_MASK
    bne     $a0, 0, some_interrupt  # TEMPLATE: some other interrupts

on_fire_interrupt:
    sw      $0, ON_FIRE_ACK         # acknowledge interrupt
    # get location
    lw      $k0, GET_FIRE_LOC

    srl     $a0, $k0, 16
    sw      $a0, X
    sll     $a0, $k0, 16
    srl     $a0, $a0, 16
    sw      $a0, Y
    li      $k0, 1
    sw      $k0, flag               # flag = 1

    j	interrupt_dispatch          # see if other interrupts are waiting

some_interrupt:                     # TEMPLETE
    sw  $0, SOME_ACK
# code
    j   interrupt_dispatch

done:
    la      $k0, chunkIH
    lw      $a0, 0($k0)
    lw      $a1, 4($k0)             # Restore saved registers
.set noat
    move	$at, $k1                # Restore $at
.set at
    eret
// BEN
