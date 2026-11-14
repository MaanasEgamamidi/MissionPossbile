class_name PlayerCameraRig
extends Node3D
## Shared look pivot with mutually exclusive first and third person cameras.

## Maximum pitch; controller supplies the designer's tuning.
var pitch_limit_degrees: float = 85.0
## How far in front of the head pivot the first-person camera sits, in metres.
const FIRST_PERSON_FORWARD_M: float = 0.1
var _first: Camera3D
var _third: Camera3D
var _arm: SpringArm3D
var _first_person: bool = true
var _fill: OmniLight3D
## Third person, looking level: the boots sit this fraction of the screen height above the bottom edge.
const THIRD_PERSON_FEET_MARGIN: float = 0.08
## 0.7 (was 0.35): legs still read near-black outdoors in round-2 captures.
const FILL_ENERGY: float = 0.7
const FILL_RANGE_M: float = 3.5

## Builds the eye cameras and excludes the owning body from the spring arm.
func setup(config: GameConfig, body: CollisionObject3D, eye_height: float) -> void:
	position.y = eye_height
	_first = Camera3D.new()
	_first.name = "FirstPerson"
	_first.fov = config.fov_degrees
	_first.cull_mask &= ~Layers.render_bit(Layers.RENDER_FIRST_PERSON_HIDDEN)
	# A little in front of the head centre, where the eyes are, so looking down shows the chest and feet
	# and not the inside of the collar. Still well inside the 0.32 m body capsule, so it cannot reach through a wall.
	_first.position.z = -FIRST_PERSON_FORWARD_M
	add_child(_first)
	_arm = SpringArm3D.new()
	_arm.name = "SpringArm"
	_arm.spring_length = config.third_person_distance_m
	_arm.collision_mask = Layers.WORLD | Layers.DOOR | Layers.CREW_SOLID
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	_arm.shape = sphere
	_arm.add_excluded_object(body.get_rid())
	add_child(_arm)
	_third = Camera3D.new()
	_third.name = "ThirdPerson"
	_third.fov = config.fov_degrees
	_third.cull_mask |= Layers.render_bit(Layers.RENDER_FIRST_PERSON_HIDDEN)
	_arm.add_child(_third)
	# Weak fill so the character reads in dark rooms. Every render layer is taken (1-18 zones, 19, 20), so it cannot be
	# limited to the body: it uses the player's own zone layers (set_fill_layers), is short-range and shadowless,
	# and exists only in third person.
	_fill = OmniLight3D.new()
	_fill.name = "ThirdPersonFill"
	_fill.light_energy = FILL_ENERGY
	_fill.omni_range = FILL_RANGE_M
	_fill.shadow_enabled = false
	_fill.light_specular = 0.1
	_fill.position = Vector3(0.4, 0.3, 0.0)
	_third.add_child(_fill)
	set_first_person(_first_person)
	_frame_third_person()

## Field of view of both cameras, in degrees (settings screen).
func set_fov(degrees: float) -> void:
	if _first != null:
		_first.fov = degrees
		_third.fov = degrees

## Selects exactly one active camera.
func set_first_person(on: bool) -> void:
	_first_person = on
	if _first != null:
		_first.current = on
		_third.current = not on
		_fill.visible = not on

## Render layers the third-person fill light affects (the player's current lighting zone).
func set_fill_layers(mask: int) -> void:
	if _fill != null and _fill.light_cull_mask != mask:
		_fill.light_cull_mask = mask

## The third-person fill light (null before setup).
func fill_light() -> OmniLight3D:
	return _fill

## Tilts only the third-person camera down a little so the whole body, boots included, is in frame at level look.
## Feet are eye-height below the pivot and spring_length behind it; the tilt follows the FOV setting.
func _frame_third_person() -> void:
	if _third == null:
		return
	var half := deg_to_rad(_third.fov) * 0.5
	var feet := atan(position.y / maxf(_arm.spring_length, 0.1))
	var wanted := atan((1.0 - 2.0 * THIRD_PERSON_FEET_MARGIN) * tan(half))
	_third.rotation.x = -clampf(feet - wanted, 0.0, deg_to_rad(15.0))

## Whether the eye camera is selected.
func is_first_person() -> bool:
	return _first_person

## Currently selected camera.
func camera() -> Camera3D:
	return _first if _first_person else _third

## Adds look angles in radians and clamps vertical look.
func add_look(yaw_delta: float, pitch_delta: float) -> void:
	rotation.y += yaw_delta
	rotation.x = clampf(rotation.x + pitch_delta, -deg_to_rad(pitch_limit_degrees), deg_to_rad(pitch_limit_degrees))
	_place_eye()

## Extra forward distance of the eye when looking straight down, so it clears the chest (body front is about 0.2 m out).
const LOOK_DOWN_FORWARD_M: float = 0.2

func _process(_delta: float) -> void:
	_place_eye()   # pitch can also be set directly (tests, cut-ins); keep the eye where it belongs
	_frame_third_person()   # follows FOV changes from the settings

## Keeps the eye a fixed distance forward along the *ground* direction, not along the view. Before, the offset turned
## with the pitch, so looking down moved the eye down into the chest and the player saw the inside of their own body.
## Looking down also leans the eye further forward, the way a person bends their neck to see their feet.
func _place_eye() -> void:
	if _first == null:
		return
	var down := clampf(-sin(rotation.x), 0.0, 1.0)
	var forward := FIRST_PERSON_FORWARD_M + LOOK_DOWN_FORWARD_M * down
	# the camera is a child of this pitched pivot: undo the pitch so the offset stays level
	_first.position = Basis(Vector3.RIGHT, -rotation.x) * Vector3(0, 0, -forward)

## Horizontal look in radians.
func yaw() -> float:
	return rotation.y

## Vertical look in radians.
func pitch() -> float:
	return rotation.x
