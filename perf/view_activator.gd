class_name ViewActivator
extends Node
## Gameplay-side "only care about what the player can see" system.
##
## IMPORTANT: this does NOT hide or show anything. Godot already frustum-culls rendering every frame, so a fast camera
## turn can never cause a rendering spike. This node only puts EXPENSIVE ENTITIES to sleep when they are outside the
## view cone, and wakes them before they come into view.
##
## In this game the tagged entities are the animated models of the other crew (PerfRig tags each crew body's model
## node, never the crew body itself: the body carries the door-sensing "Presence" physics body, which must keep working
## unseen). Pausing the model stops its AnimationPlayer and skeleton; positions are still set by GameMain.
##
## An entity opts in by being in group "view_gated" (a Node3D). Optional hooks on the entity:
##   _view_state_changed(awake: bool)
## Optional meta on the entity:
##   "view_radius" (float, default 1.0) rough size, so large things wake earlier.
##
## How it handles fast turning:
##   1. Wide cone: half-diagonal FOV + cone_margin_deg.
##   2. Look-ahead: the cone grows with the camera's angular speed (up to max_extra_deg).
##   3. Anything within near_radius is always awake (covers "behind you").
##   4. Sleeping needs a bigger cone (sleep_extra_deg) AND sleep_delay seconds: no flicker.
##   5. Wake-ups are rate limited (wakes_per_tick) and sorted by angle, closest-to-centre first.

@export var camera: Camera3D   ## leave empty to follow the main viewport's current camera
@export var near_radius := 12.0
@export var far_radius := 90.0
@export var cone_margin_deg := 20.0
@export var sleep_extra_deg := 10.0
@export var lookahead_s := 0.25
@export var max_extra_deg := 60.0
@export var sleep_delay := 1.5
@export var tick_hz := 10.0
@export var wakes_per_tick := 6

const META_AWAKE := &"va_awake"
const META_MODE := &"va_mode"
const META_OUT := &"va_out_since"
const META_RADIUS := &"view_radius"

var _acc := 0.0
var _last_fwd := Vector3.ZERO
var _ang_speed := 0.0
var _was_enabled := true


func _ready() -> void:
	add_to_group(&"view_activator")


func _current_camera() -> Camera3D:
	if camera != null and is_instance_valid(camera):
		return camera
	return get_viewport().get_camera_3d()


func _process(delta: float) -> void:
	if not Perf.cfg().view_activation_enabled:
		if _was_enabled:
			_was_enabled = false
			wake_all()
		return
	_was_enabled = true
	var cam := _current_camera()
	if cam == null:
		return
	_acc += delta
	if _acc < 1.0 / tick_hz:
		return
	var dt := _acc
	_acc = 0.0
	_tick(cam, dt)


func wake_all() -> void:
	for n in get_tree().get_nodes_in_group(&"view_gated"):
		_set_awake(n as Node3D, true)


func asleep_count() -> int:
	var c := 0
	for n in get_tree().get_nodes_in_group(&"view_gated"):
		if not bool(n.get_meta(META_AWAKE, true)):
			c += 1
	return c


func _tick(cam: Camera3D, dt: float) -> void:
	var cam_pos := cam.global_position
	var fwd := -cam.global_transform.basis.z
	if _last_fwd != Vector3.ZERO:
		_ang_speed = lerpf(_ang_speed, fwd.angle_to(_last_fwd) / dt, 0.5)
	_last_fwd = fwd

	var half := _half_diag_angle(cam)
	var extra := clampf(_ang_speed * lookahead_s, 0.0, deg_to_rad(max_extra_deg))
	var wake_angle := half + deg_to_rad(cone_margin_deg) + extra
	var sleep_angle := wake_angle + deg_to_rad(sleep_extra_deg)
	var now := Time.get_ticks_msec() * 0.001

	var to_wake: Array = []  # items: [angle, node, is_near]
	for n in get_tree().get_nodes_in_group(&"view_gated"):
		var e := n as Node3D
		if e == null or not e.is_inside_tree():
			continue
		var awake: bool = e.get_meta(META_AWAKE, true)
		var to := e.global_position - cam_pos
		var d := to.length()
		var near := d <= near_radius
		var inside := false
		var angle := 0.0
		if near:
			inside = true
		elif d <= far_radius * (1.1 if awake else 1.0):
			var r: float = e.get_meta(META_RADIUS, 1.0)
			angle = to.angle_to(fwd) - asin(clampf(r / d, 0.0, 1.0))
			inside = angle <= (sleep_angle if awake else wake_angle)

		if awake:
			if inside:
				e.set_meta(META_OUT, -1.0)
			else:
				var since: float = e.get_meta(META_OUT, -1.0)
				if since < 0.0:
					e.set_meta(META_OUT, now)
				elif now - since >= sleep_delay:
					_set_awake(e, false)
		elif inside:
			to_wake.append([angle, e, near])

	to_wake.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var budget := wakes_per_tick
	for item in to_wake:
		var is_near: bool = item[2]
		if budget <= 0 and not is_near:
			break
		_set_awake(item[1] as Node3D, true)
		budget -= 1


func _set_awake(e: Node3D, awake: bool) -> void:
	if e == null:
		return
	e.set_meta(META_AWAKE, awake)
	e.set_meta(META_OUT, -1.0)
	if not e.has_meta(META_MODE):
		e.set_meta(META_MODE, int(e.process_mode))
	var base: int = e.get_meta(META_MODE)
	if base == Node.PROCESS_MODE_DISABLED:
		base = Node.PROCESS_MODE_INHERIT
	# Only ever toggles between the node's own authored mode and DISABLED, so it composes with other systems.
	e.set(&"process_mode", base if awake else int(Node.PROCESS_MODE_DISABLED))
	if e.has_method(&"_view_state_changed"):
		e.call(&"_view_state_changed", awake)


## Half of the screen diagonal's field of view, in radians (the widest angle that can be on screen).
func _half_diag_angle(cam: Camera3D) -> float:
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var tan_half := tan(deg_to_rad(cam.fov) * 0.5)
	if cam.keep_aspect == Camera3D.KEEP_WIDTH:
		tan_half /= aspect  # fov was horizontal; convert to vertical
	return atan(tan_half * sqrt(1.0 + aspect * aspect))
