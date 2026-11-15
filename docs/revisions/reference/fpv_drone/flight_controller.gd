extends CharacterBody3D

signal camera_changed(chase: bool)

@export_range(1.0, 40.0, 0.1) var horizontal_speed := 18.0
@export_range(1.0, 15.0, 0.1) var vertical_speed := 6.0
@export_range(0.01, 1.0, 0.01) var yaw_degrees_per_pixel := 0.15
@export_range(0.0, 20.0, 0.1) var forward_pitch_degrees := 7.0
@export_range(0.0, 20.0, 0.1) var reverse_pitch_degrees := 5.0

const HORIZONTAL_RESPONSE := 4.2
const BRAKE_RESPONSE := 6.5
const VERTICAL_RESPONSE := 7.5
const YAW_RESPONSE := 28.0
const PITCH_RESPONSE := 8.0

@onready var pitch_pivot: Node3D = $PitchPivot
@onready var fpv_camera: Camera3D = $PitchPivot/FPV
@onready var chase_camera: Camera3D = $ChaseArm/Chase
@onready var rotor_player: AnimationPlayer = $PitchPivot/Racer/AnimationPlayer
@onready var spawn_transform := global_transform

var _controls_active := false
var _target_yaw := 0.0


func _ready() -> void:
	_target_yaw = rotation.y
	var rotor_spin := rotor_player.get_animation(&"rotor-spin")
	rotor_spin.loop_mode = Animation.LOOP_LINEAR
	rotor_player.play(&"rotor-spin")
	rotor_player.pause()


func set_controls_active(active: bool) -> void:
	_controls_active = active
	_target_yaw = rotation.y
	if active:
		rotor_player.play()
	else:
		rotor_player.pause()


func steer_mouse(relative_x: float) -> void:
	_target_yaw = wrapf(_target_yaw - deg_to_rad(relative_x * yaw_degrees_per_pixel), -PI, PI)


func toggle_camera() -> void:
	if fpv_camera.current:
		chase_camera.make_current()
	else:
		fpv_camera.make_current()
	camera_changed.emit(chase_camera.current)


func respawn() -> void:
	global_transform = spawn_transform
	_target_yaw = rotation.y
	velocity = Vector3.ZERO
	pitch_pivot.rotation.x = 0.0
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if not _controls_active:
		return

	var movement := Input.get_vector(&"fly_left", &"fly_right", &"fly_forward", &"fly_back")
	var lift := Input.get_axis(&"fly_down", &"fly_up")
	rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-YAW_RESPONSE * delta))

	# Only yaw steers translation. Pitch is shared by the model and FPV camera.
	var planar_target := basis * Vector3(movement.x, 0.0, movement.y) * horizontal_speed
	var planar_velocity := Vector2(velocity.x, velocity.z)
	var response := BRAKE_RESPONSE if movement.is_zero_approx() else HORIZONTAL_RESPONSE
	planar_velocity = planar_velocity.lerp(Vector2(planar_target.x, planar_target.z), 1.0 - exp(-response * delta))
	if movement.is_zero_approx() and planar_velocity.length_squared() < 0.000001:
		planar_velocity = Vector2.ZERO
	velocity.x = planar_velocity.x
	velocity.z = planar_velocity.y
	velocity.y = lerpf(velocity.y, lift * vertical_speed, 1.0 - exp(-VERTICAL_RESPONSE * delta))
	if is_zero_approx(lift) and absf(velocity.y) < 0.001:
		velocity.y = 0.0

	var pitch_limit := forward_pitch_degrees if movement.y < 0.0 else reverse_pitch_degrees
	pitch_pivot.rotation.x = lerpf(
		pitch_pivot.rotation.x, deg_to_rad(pitch_limit) * movement.y,
		1.0 - exp(-PITCH_RESPONSE * delta)
	)
	move_and_slide()
