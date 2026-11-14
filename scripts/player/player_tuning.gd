class_name PlayerTuning
extends Resource
## Designer movement tuning in real seconds, independent of sol length.

## Unsuit walking metres per second; comfortable inside narrow rooms.
@export var walk_speed: float = 3.0
## Sprint speed ratio; useful without making corridors hard to navigate.
@export var sprint_multiplier: float = 1.6
## Ground acceleration in m/s²; reaches walking speed promptly.
@export var ground_acceleration: float = 18.0
## Ground braking in m/s²; stops before nearby stations.
@export var ground_deceleration: float = 22.0
## Fraction of ground acceleration in air; permits small landing corrections.
@export var air_control: float = 0.25
## Height of a standing jump. 0.5 m under 3.73 m/s² needs a take-off speed of 1.93 m/s and lasts 1.04 s:
## visibly floatier than Earth (the same push on Earth gives 0.19 m and 0.39 s) yet short enough to steer and land.
@export var jump_height_m: float = 0.5
## Floor adhesion distance; keeps feet on descending ramps.
@export var floor_snap_m: float = 0.15
## Steepest walkable slope; rejects the 50 degree test ramp.
@export var max_slope_degrees: float = 40.0
## Maximum stair rise; clears 0.2 m steps without climbing walls.
@export var step_height_m: float = 0.25
## Radians per mouse pixel; modest mouse motion gives precise aiming.
@export var mouse_sensitivity: float = 0.002
## Vertical look limit; avoids flipping the camera over.
@export var pitch_limit_degrees: float = 85.0
## Standing capsule height; matches the placeholder astronaut.
@export var body_height_m: float = 1.8
## Capsule radius; fits colony doorways.
@export var body_radius_m: float = 0.32
## Eye level below the top of the head.
@export var eye_height_m: float = 1.65
## Interaction reach in metres; matches nearby station use.
@export var reach_m: float = 2.6
## Temporary local stamina drain per real sprint second.
@export var sprint_stamina_per_second: float = 12.0
## Temporary local stamina recovery per real resting second.
@export var stamina_recover_per_second: float = 8.0
## Throw speed in m/s; a gentle forward toss in low gravity.
@export var throw_speed: float = 4.0
