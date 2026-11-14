class_name PlayerController
extends CharacterBody3D
## Local movement and presentation. Gameplay changes go through host callables.

## Emitted after the active perspective changes.
signal perspective_changed(first_person: bool)
## Host answer for each interaction, pickup or drop request.
signal action_answered(result: ActionResult)
## Shared engineering configuration.
var config: GameConfig
## Designer movement tuning.
var tuning: PlayerTuning
## Authoritative crew record; only the temporary stamina feel model writes locally.
var character: CharacterState
## Host action callback: (action, target, params) -> ActionResult.
var submit: Callable = Callable()
## Position reporting callback: (position, yaw) -> void.
var report_position: Callable = Callable()
## Enables local controls; gravity and position reporting continue when disabled.
var input_enabled: bool = true
var _rig: PlayerCameraRig
var _visual: PlayerVisual
var _held: CarryItem
var _buttons: Dictionary = {}
var _was_on_floor: bool = true
## Seconds since the body last stood on the floor; 0 while grounded.
var _air_time: float = 0.0
## True from a jump press until the next touchdown.
var _jumped: bool = false
## Shorter flights than this (a stair step-up, a bump, a floor-contact flicker) neither show the in-air
## pose nor play the landing; a jump always does both.
const MIN_AIR_TIME_S: float = 0.15

## Builds the collider, cameras and visible body using the supplied crew record.
func setup(p_config: GameConfig, p_tuning: PlayerTuning, p_character: CharacterState, p_submit: Callable, p_report_position: Callable) -> void:
	config = p_config
	tuning = p_tuning
	character = p_character
	submit = p_submit
	report_position = p_report_position
	PlayerInput.ensure_actions()
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.DOOR | Layers.ITEM
	floor_snap_length = tuning.floor_snap_m
	floor_max_angle = deg_to_rad(tuning.max_slope_degrees)
	floor_constant_speed = true
	var capsule := CapsuleShape3D.new()
	capsule.radius = tuning.body_radius_m
	capsule.height = tuning.body_height_m
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position.y = tuning.body_height_m / 2.0
	add_child(collider)
	_visual = PlayerVisual.new()
	add_child(_visual)
	_visual.set_suit(character.suit_on)
	_rig = PlayerCameraRig.new()
	add_child(_rig)
	_rig.pitch_limit_degrees = tuning.pitch_limit_degrees
	_rig.setup(config, self, tuning.eye_height_m)
	position = character.position
	_rig.add_look(character.yaw, 0.0)
	set_first_person(true)

## Changes presentation only, without changing ownership or cargo.
func set_first_person(on: bool) -> void:
	_rig.set_first_person(on)
	_visual.set_first_person(on)
	perspective_changed.emit(on)

## True when the eye camera is selected.
func is_first_person() -> bool:
	return _rig.is_first_person()

## The shared look and camera rig.
func camera_rig() -> PlayerCameraRig:
	return _rig

## The single visible astronaut body.
func visual() -> PlayerVisual:
	return _visual

## Moves this body without writing the authoritative record.
func teleport(world_position: Vector3, yaw: float) -> void:
	global_position = world_position
	velocity = Vector3.ZERO
	_jumped = false
	_air_time = 0.0
	_rig.add_look(yaw - _rig.yaw(), -_rig.pitch())
	_visual.rotation.y = yaw

## The prop attached after a successful host pickup, or null.
func held_item() -> CarryItem:
	return _held if is_instance_valid(_held) else null

## Closest crosshair hit within reach; walls block interaction rays.
func aimed_target() -> Dictionary:
	var empty := {"kind": "", "id": &"", "node": null}
	if not is_inside_tree():
		return empty
	var cam := _rig.camera()
	var start := cam.global_position
	var query := PhysicsRayQueryParameters3D.create(start, start - cam.global_basis.z * (tuning.reach_m + config.third_person_distance_m), Layers.WORLD | Layers.DOOR | Layers.ITEM | Layers.STATION)
	query.exclude = [get_rid()]
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit.position as Vector3).distance_to(global_position + Vector3.UP * tuning.eye_height_m) > tuning.reach_m:
		return empty
	var node: Node = hit.collider
	if node is CarryItem:
		return {"kind": "item", "id": node.item_id, "node": node}
	if node.has_meta("station_id"):
		return {"kind": "station", "id": StringName(node.get_meta("station_id")), "node": node}
	# Looking at the station's own solid body (a rack, console or panel) counts as looking at the station:
	# its collision box is usually in front of the station's sensing sphere, so the ray stops there first.
	if node is CollisionObject3D and hit.has("shape"):
		var body := node as CollisionObject3D
		var shape_node := body.shape_owner_get_owner(body.shape_find_owner(int(hit.shape)))
		if shape_node != null and shape_node.has_meta("object_name"):
			var station := _station_node(String(shape_node.get_meta("object_name")))
			if station != null:
				return {"kind": "station", "id": StringName(station.get_meta("station_id")), "node": station}
	return empty

## Station sensing node of a map object, or null if that object is not a station.
func _station_node(object_name: String) -> Node:
	for group: Node in get_tree().get_nodes_in_group(&"station_volume"):
		if String(group.get_meta("station_id")) == object_name:
			return group
	return null

func _unhandled_input(event: InputEvent) -> void:
	if input_enabled and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rig.add_look(-event.relative.x * tuning.mouse_sensitivity, -event.relative.y * tuning.mouse_sensitivity)

func _physics_process(delta: float) -> void:
	if character == null:
		return
	# Edge tracking also supports Input.action_press in headless tests.
	for action: StringName in [&"toggle_view", &"interact", &"grab", &"jump"]:
		var pressed := input_enabled and Input.is_action_pressed(action)
		if pressed and not bool(_buttons.get(action, false)):
			match action:
				&"toggle_view": set_first_person(not is_first_person())
				&"interact": _interact()
				&"grab": _grab()
				&"jump":
					if is_on_floor():
						velocity.y = sqrt(2.0 * GameConfig.MARS_GRAVITY * tuning.jump_height_m)
						_jumped = true
						# Push-off first; the looping in-air "jump" takes over when this hold ends.
						# A rig without a jump_start clip skips it and goes straight to "jump".
						_visual.play_once(&"jump_start", clampf(_visual.clip_length(&"jump_start", 0.25), 0.1, 0.5))
		_buttons[action] = pressed
	var axis := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if input_enabled else Vector2.ZERO
	var direction := Basis(Vector3.UP, _rig.yaw()) * Vector3(axis.x, 0, axis.y)
	var sprinting := input_enabled and Input.is_action_pressed("sprint") and character.stamina > 0.0 and not axis.is_zero_approx()
	var speed := tuning.walk_speed * (config.suit_speed_factor if character.suit_on else 1.0) * (tuning.sprint_multiplier if sprinting else 1.0)
	# Local feel only: the authoritative stamina model is a later milestone.
	character.stamina = clampf(character.stamina + (-tuning.sprint_stamina_per_second if sprinting else tuning.stamina_recover_per_second) * delta, 0.0, 100.0)
	var acceleration := tuning.ground_deceleration if axis.is_zero_approx() else tuning.ground_acceleration
	if not is_on_floor():
		acceleration *= tuning.air_control
	var horizontal := Vector3(velocity.x, 0, velocity.z).move_toward(direction * speed, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	# Midpoint gravity gives accurate short-hop height even at 60 Hz.
	if not is_on_floor() or velocity.y > 0.0:
		velocity.y -= GameConfig.MARS_GRAVITY * delta * 0.5
	var airborne := not is_on_floor() or velocity.y > 0.0
	if is_on_floor() and velocity.y <= 0.0:
		_try_step(horizontal * delta)
	move_and_slide()
	if airborne and not is_on_floor():
		velocity.y -= GameConfig.MARS_GRAVITY * delta * 0.5
	if is_on_floor():
		if not _was_on_floor and (_jumped or _air_time >= MIN_AIR_TIME_S):
			# The landing absorb holds for the clip's own length; movement asked for meanwhile waits,
			# then walking or sprinting resumes on the next play() after the hold.
			_visual.play_once(&"land", clampf(_visual.clip_length(&"land", 0.4), 0.25, 0.6))
		_air_time = 0.0
		_jumped = false
	else:
		_air_time += delta
	_was_on_floor = is_on_floor()
	_visual.rotation.y = _rig.yaw()
	_visual.set_suit(character.suit_on)
	var in_air := not is_on_floor() and (_jumped or _air_time >= MIN_AIR_TIME_S)
	var gait: StringName = &"carry" if held_item() != null else (&"jump" if in_air else (&"sprint" if sprinting else (&"walk" if not axis.is_zero_approx() else &"idle")))
	# The walk and sprint clips cover a known ground speed; play them at the real ground speed so feet do not slide.
	var gait_speed := 1.0
	if gait == &"walk":
		gait_speed = clampf(horizontal.length() / PlayerVisual.WALK_CLIP_SPEED, 0.5, 2.5)
	elif gait == &"sprint":
		gait_speed = clampf(horizontal.length() / PlayerVisual.SPRINT_CLIP_SPEED, 0.5, 2.5)
	_visual.play(gait, gait_speed)
	if report_position.is_valid():
		report_position.call(global_position, _rig.yaw())

func _try_step(motion: Vector3) -> void:
	if motion.is_zero_approx() or tuning.step_height_m <= 0.0:
		return
	var obstacle := KinematicCollision3D.new()
	if not test_move(global_transform, motion, obstacle):
		return
	if obstacle.get_normal().y >= cos(floor_max_angle):
		return
	var lift := Vector3.UP * tuning.step_height_m
	if test_move(global_transform, lift):
		return
	var raised := global_transform
	raised.origin += lift
	# Probe past the capsule's curved toe so the downward hit measures the tread.
	var forward := motion + motion.normalized() * tuning.body_radius_m
	if test_move(raised, forward):
		return
	raised.origin += forward
	var landing := KinematicCollision3D.new()
	if test_move(raised, -lift, landing) and landing.get_normal().y >= cos(floor_max_angle):
		var rise := tuning.step_height_m + landing.get_travel().y
		if rise > 0.001:
			# Lift only. Moving the body forward here as well made every small bump a free push
			# (measured: 4.6 m/s on rough ground at a 2.4 m/s walk); move_and_slide carries it over the edge.
			global_position.y += rise

func _answer(action: StringName, target: StringName, params: Dictionary) -> ActionResult:
	var result: ActionResult = submit.call(action, target, params) if submit.is_valid() else ActionResult.failure("", &"not_available_yet")
	action_answered.emit(result)
	return result

## E is the one key for every interaction (owner's instruction, 2026-11-12): a station you look at is used;
## otherwise an item you look at is picked up, or the item in your hands is put down (thrown while sprinting).
## G and the left mouse button still pick up and put down.
func _interact() -> void:
	var target := aimed_target()
	if target.kind != "station":
		if target.kind == "item" or held_item() != null:
			_grab()
		return
	var node: Node = target.node
	if String(node.get_meta("kind", "")) == "suits":
		_answer(&"begin_suit_check", target.id, {"on": not character.suit_on})
	else:
		_visual.play_once(&"use", 1.0)
		_answer(&"use_station", target.id, {})

func _grab() -> void:
	if held_item() != null:
		if _answer(&"drop", _held.item_id, {}).ok:
			var forward := -Basis(Vector3.UP, _rig.yaw()).z
			var toss := forward * tuning.throw_speed if Input.is_action_pressed("sprint") else Vector3.ZERO
			_held.release(global_position + Vector3.UP * tuning.eye_height_m + forward * (tuning.body_radius_m + 0.5), toss)
			_held = null
		return
	var target := aimed_target()
	if target.kind == "item" and _answer(&"pick_up", target.id, {}).ok:
		_held = target.node as CarryItem
		_held.attach_to(_visual.hand_anchor())
