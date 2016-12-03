# SPIMbot

Tasks:
  -build interrupt structure(B)
    -handle fires
    -handle bonk
    -
    
  -build KenKen solver structure
  
  -design plant harvesting algorithm
  
  -design seed planting algorithm
  
  -design watering algorithm
  
  -build generalized move function with trig (to a given location)
  
  
  priorities
    -if fire, put out fire
     -if there is a puzzle, solve puzzle
     -if there is a fully grown crop, harvest
     -MAX_GROWTH is an interrupt that triggers when a crop becomes fully grown
     
 Basic logic:
 1. First complete water puzzles to maintain water above threshold
     - let's say able to put out 3 fires
 2. Complete puzzles to plant seeds
     - generally plant seeds as early as possible
 3. Water plants in an evenly distributed way
 4. The robot should be doing puzzles most of the time (in the main thread)
     - interrupts (e.g MAX_GROWTH) will tell the robot to start walking
     - interrupts (e.g TIMER) will tell the robot to stop walking and harvest/water plants/etc
     
 Jing Rong suggestions:
 - I think we should have some firestarters, and set fire to enemy's plants if they are within a certain distance (and not next to our own crops)
 
 What we still need to decide:
 - When should we decide to harvest seeds and not water? When water >> water threshold? And when we should harvest water and not seeds
 - Where we want to plant our plants (e.g do we plant right where we stand? do we plant if there's a enemy robot's plant next to it? do we want to water our plants if the enemy suddenly plants next to our plant?)
     
     
