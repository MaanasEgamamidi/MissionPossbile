class_name PlayerController
extends CharacterBody3D
## Local movement and presentation. Gameplay changes go through host callables.

## Emitted after the active perspective changes.
signal perspective_changed(first_person: bool)
## Host answer for each interaction, pickup or drop request.
signal action_answered(result: ActionResult)
## Prompt 10: E on a vehicle (aimed at while standing) or E while seated in one. The vehicle's presenter decides
## whether that means getting in or out; `vehicle` is the vehicle body (null while seated: the seat's own vehicle).
signal vehicle_interact(vehicle: Node)
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
## Settings: mouse up looks down.
var invert_y: bool = false
## Settings: Shift switches sprint on and off instead of being held (an alternative to holding a key).
var toggle_sprint: bool = false
var _sprint_latched: bool = false
var _rig: PlayerCameraRig
var _visual: PlayerVisual
var _held: CarryItem
## Client only: pick_up / drop requests sent to the host, by request id, until the answer arrives.
var _waiting := {}
var _buttons: Dictionary = {}
var _was_on_floor: bool = true
## Seconds since the body last stood on the floor; 0 while grounded.
var _air_time: float = 0.0
## True from a jump press until the next touchdown.
var _jumped: bool = false
var _ladder: ClimbableLadder
## Shorter flights than this (a stair step-up, a bump, a floor-contact flicker) neither show the in-air
## pose nor play the landing; a jump always does both.
const MIN_AIR_TIME_S: float = 0.15
## Locomotion is picked from the real horizontal ground speed, not from the sprint key (m/s).
const IDLE_BELOW: float = 0.15
## 2.6 (was 3.1): the unsuited 3.0 m/s walk would need the walk clip at 1.5x; above 2.75 it borrows the sprint lope.
const SPRINT_ABOVE: float = 2.6
const SPRINT_HYSTERESIS: float = 0.15
## Touching down faster than this skips the standing land clip: a short hip dip and straight back into the gait.
const RUNNING_LANDING_SPEED: float = 1.0
## Walk input may cut a standing landing short after this long.
const LAND_INTERRUPT_AFTER_S: float = 0.2
## How far behind the first thing the aim ray hits a broken part's target may still be (see aimed_target).
const PART_REACH_SLACK_M: float = 0.6
## How deep inside a part's whole-model target a smaller station still wins the aim (see _station_inside_part).
const PART_INNER_DEPTH_M: float = 1.5
## Current locomotion choice: idle, walk or sprint.
var _locomotion: StringName = &"idle"
## Prompt 10: the seat anchor this body sits on (null when standing), its vehicle, and the standing collision
## layers to restore. While seated the body follows the anchor, does not collide and ignores movement input.
var _seat: Node3D
var _collider: CollisionShape3D
var _standing_layers := Vector2i.ZERO

## Builds the collider, cameras and visible body using the supplied crew record.
func setup(p_config: GameConfig, p_tuning: PlayerTuning, p_character: CharacterState, p_submit: Callable, p_report_position: Callable) -> void:
	config = p_config
	tuning = p_tuning
	character = p_character
	submit = p_submit
	report_position = p_report_position
	PlayerInput.ensure_actions()
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.DOOR | Layers.ITEM | Layers.CREW_SOLID
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
	_collider = collider
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
	_ladder = null
	_jumped = false
	_air_time = 0.0
	_rig.add_look(yaw - _rig.yaw(), -_rig.pitch())
	_visual.rotation.y = yaw

## The prop attached after a successful host pickup, or null.
func held_item() -> CarryItem:
	return _held if is_instance_valid(_held) else null

## Prompt 10: sits this body on `anchor` (a seat of `vehicle`): no collision, no movement input, the body follows the
## seat and plays the seated pose, the eye drops to `eye_height` above the anchor and third person becomes a chase
## camera `chase_length` behind that ignores the vehicle's own body. Look stays free (relative to the vehicle).
func sit(anchor: Node3D, vehicle: CollisionObject3D, eye_height: float, chase_length: float) -> void:
	if anchor == null:
		return
	if _seat == null:
		_standing_layers = Vector2i(collision_layer, collision_mask)
	_seat = anchor
	collision_layer = 0
	collision_mask = 0
	_collider.disabled = true
	velocity = Vector3.ZERO
	_jumped = false
	_air_time = 0.0
	_sprint_latched = false
	_rig.set_seated(true, eye_height, chase_length, vehicle)
	_follow_seat()
	_visual.rotation = Vector3.ZERO
	_visual.clear_hold()
	_visual.play(&"seated")


## Prompt 10: gets up from the seat and stands upright at `world_position` facing `yaw` (radians).
func stand(world_position: Vector3, yaw: float) -> void:
	if _seat == null:
		teleport(world_position, yaw)
		return
	_seat = null
	_rig.set_seated(false)
	global_transform = Transform3D(Basis.IDENTITY, global_position)   # upright again (the seat followed the vehicle's tilt)
	collision_layer = _standing_layers.x
	collision_mask = _standing_layers.y
	_collider.disabled = false
	teleport(world_position, yaw)
	_visual.play(&"idle")


## True while sitting in a vehicle seat.
func is_seated() -> bool:
	return _seat != null and is_instance_valid(_seat)


## The seat anchor sat on, or null.
func seat_anchor() -> Node3D:
	return _seat if is_seated() else null


## World yaw of the view while seated or standing (the vehicle's heading plus the look).
func view_yaw() -> float:
	return _rig.global_basis.get_euler().y


func _follow_seat() -> void:
	if is_seated():
		global_transform = _seat.global_transform


func _process(_delta: float) -> void:
	# Seated: follow the seat every drawn frame, after the vehicle's physics step, so the camera never lags it.
	_follow_seat()


## Closest crosshair hit within reach; walls block interaction rays.
func aimed_target() -> Dictionary:
	var empty := {"kind": "", "id": &"", "node": null}
	if not is_inside_tree() or is_seated():
		return empty
	var cam := _rig.camera()
	var start := cam.global_position
	var query := PhysicsRayQueryParameters3D.create(start, start - cam.global_basis.z * (tuning.reach_m + config.third_person_distance_m), Layers.WORLD | Layers.DOOR | Layers.ITEM | Layers.STATION)
	query.exclude = [get_rid()]
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var ladder_query := PhysicsRayQueryParameters3D.create(start, query.to, Layers.LADDER)
	ladder_query.collide_with_areas = true
	ladder_query.collide_with_bodies = false
	ladder_query.hit_from_inside = true
	var ladder_hit := get_world_3d().direct_space_state.intersect_ray(ladder_query)
	if not ladder_hit.is_empty() and (hit.is_empty() or start.distance_squared_to(ladder_hit.position) <= start.distance_squared_to(hit.position)):
		hit = ladder_hit
	# A broken part's whole model is its repair target (owner 2026-11-14, shapes added by BrokenPartPresenter). The
	# intact object's collision box around it usually stops the ray a few centimetres first, so a part's target counts
	# when it is hit within PART_REACH_SLACK_M behind that first hit (a real wall in front still blocks it).
	if not hit.is_empty() and not (hit.collider is Area3D and (hit.collider as Node).has_meta("station_id")):
		var part_query := PhysicsRayQueryParameters3D.create(start, query.to, Layers.STATION)
		part_query.exclude = [get_rid()]
		part_query.collide_with_areas = true
		part_query.collide_with_bodies = false
		var part_hit := get_world_3d().direct_space_state.intersect_ray(part_query)
		if not part_hit.is_empty() and (part_hit.collider as Node).has_meta("part_reach") \
				and start.distance_to(part_hit.position) <= start.distance_to(hit.position) + PART_REACH_SLACK_M:
			hit = part_hit
	# A part's whole-model target is a big box and can wrap a small station inside it (the Command Room tape sits in
	# the broken T02 rack). The specific station inside the box wins over the box itself.
	if not hit.is_empty() and (hit.collider as Node).has_meta("part_reach"):
		var inner := _station_inside_part(start, query.to, hit)
		if not inner.is_empty():
			hit = inner
	if hit.is_empty() or (hit.position as Vector3).distance_to(global_position + Vector3.UP * tuning.eye_height_m) > tuning.reach_m:
		return empty
	var node: Node = hit.collider
	if node is ClimbableLadder:
		return {"kind": "ladder", "id": StringName(node.name), "node": node}
	if node is CarryItem:
		return {"kind": "item", "id": node.item_id, "node": node}
	if node.has_meta("vehicle_id"):
		# Prompt 10: a vehicle body (the rover). E on it is handled by its presenter (vehicle_interact).
		return {"kind": "vehicle", "id": StringName(node.get_meta("vehicle_id")), "node": node}
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

## The first non-part station hit behind a part's whole-model target, within PART_INNER_DEPTH_M of it and not behind a
## solid surface (beyond PART_REACH_SLACK_M); empty when there is none.
func _station_inside_part(start: Vector3, to: Vector3, part_hit: Dictionary) -> Dictionary:
	var part_dist := start.distance_to(part_hit.position)
	var inner_query := PhysicsRayQueryParameters3D.create(start, to, Layers.STATION)
	inner_query.exclude = [get_rid(), (part_hit.collider as CollisionObject3D).get_rid()]
	inner_query.collide_with_areas = true
	inner_query.collide_with_bodies = false
	var inner := get_world_3d().direct_space_state.intersect_ray(inner_query)
	if inner.is_empty() or (inner.collider as Node).has_meta("part_reach") or not (inner.collider as Node).has_meta("station_id"):
		return {}
	var inner_dist := start.distance_to(inner.position)
	if inner_dist > part_dist + PART_INNER_DEPTH_M:
		return {}
	var solid_query := PhysicsRayQueryParameters3D.create(start, inner.position, Layers.WORLD | Layers.DOOR)
	solid_query.exclude = [get_rid()]
	var solid := get_world_3d().direct_space_state.intersect_ray(solid_query)
	if not solid.is_empty() and start.distance_to(solid.position) + PART_REACH_SLACK_M < inner_dist:
		return {}
	return inner

## Station sensing node of a map object, or null if that object is not a station.
func _station_node(object_name: String) -> Node:
	for group: Node in get_tree().get_nodes_in_group(&"station_volume"):
		if String(group.get_meta("station_id")) == object_name:
			return group
	return null

func _unhandled_input(event: InputEvent) -> void:
	if input_enabled and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rig.add_look(-event.relative.x * tuning.mouse_sensitivity, (1.0 if invert_y else -1.0) * event.relative.y * tuning.mouse_sensitivity)

func _physics_process(delta: float) -> void:
	if character == null:
		return
	_visual.set_camera_obstructed(not is_first_person() and _rig.camera().global_position.distance_to(_rig.global_position) < 0.6)
	if is_seated():
		_seated_step()
		return
	# Edge tracking also supports Input.action_press in headless tests.
	for action: StringName in [&"toggle_view", &"interact", &"grab", &"jump", &"sprint"]:
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
						# Push-off first; the velocity-driven in-air "jump" takes over when this hold ends.
						# A rig without a jump_start clip skips it and goes straight to "jump".
						_visual.play_once(&"jump_start", clampf(_visual.clip_length(&"jump_start", 0.25), 0.1, 0.5))
				&"sprint":
					_sprint_latched = not _sprint_latched
		_buttons[action] = pressed
	if _climb_motion(delta):
		if report_position.is_valid():
			report_position.call(global_position, _rig.yaw())
		return
	var axis := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if input_enabled else Vector2.ZERO
	var direction := Basis(Vector3.UP, _rig.yaw()) * Vector3(axis.x, 0, axis.y)
	var sprint_wanted := _sprint_latched if toggle_sprint else Input.is_action_pressed("sprint")
	var sprinting := input_enabled and sprint_wanted and character.stamina > 0.0 and not axis.is_zero_approx()
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
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor():
		if not _was_on_floor and (_jumped or _air_time >= MIN_AIR_TIME_S):
			if ground_speed > RUNNING_LANDING_SPEED:
				# Moving landing: the standing absorb would slide; keep the gait (0.15 s blend) with a 5 cm hip dip.
				# Horizontal speed is not touched.
				_visual.dip(0.05, 0.2)
			else:
				# Standing landing: hold for the clip's own length; idle waits for all of it, walk input may cut it after 0.2 s.
				_visual.play_once(&"land", clampf(_visual.clip_length(&"land", 0.4), 0.25, 0.6), LAND_INTERRUPT_AFTER_S)
		_air_time = 0.0
		_jumped = false
	else:
		_air_time += delta
	_was_on_floor = is_on_floor()
	_visual.rotation.y = _rig.yaw()
	_visual.set_suit(character.suit_on)
	_rig.set_fill_layers(_visual.zone_layers())
	var in_air := not is_on_floor() and (_jumped or _air_time >= MIN_AIR_TIME_S)
	_locomotion = _pick_locomotion(ground_speed, axis.is_zero_approx())
	var gait: StringName = &"carry" if held_item() != null else (&"jump" if in_air else _locomotion)
	# The walk and sprint clips cover a known ground speed; play them at the real ground speed so feet do not slide.
	var gait_speed := 1.0
	if gait == &"walk":
		gait_speed = clampf(ground_speed / PlayerVisual.WALK_CLIP_SPEED, PlayerVisual.MIN_CLIP_SCALE, PlayerVisual.MAX_CLIP_SCALE)
	elif gait == &"sprint":
		gait_speed = clampf(ground_speed / PlayerVisual.SPRINT_CLIP_SPEED, PlayerVisual.MIN_CLIP_SCALE, PlayerVisual.MAX_CLIP_SCALE)
	_visual.play(gait, gait_speed)
	if gait == &"jump":
		# Rise, apex, fall from vertical velocity: take-off speed v0 -> 0, apex -> 0.5, -v0 or faster -> 1 (fall pose held).
		# Walking off a ledge enters at the apex pose: the in-air pose only starts MIN_AIR_TIME_S after leaving the
		# floor, so that much fall speed is discounted and the arc runs on from 0.5.
		var v0 := sqrt(2.0 * GameConfig.MARS_GRAVITY * tuning.jump_height_m)
		var vy := velocity.y if _jumped else minf(velocity.y + GameConfig.MARS_GRAVITY * MIN_AIR_TIME_S, 0.0)
		_visual.set_jump_phase((v0 - vy) / (2.0 * v0))
	if report_position.is_valid():
		report_position.call(global_position, _rig.yaw())

## Prompt 10: one physics step in a seat. Tab still switches the view and E asks the vehicle to let this body out;
## movement, jump, sprint and grab do nothing here (WASD and Space drive and brake through the vehicle's presenter).
func _seated_step() -> void:
	for action: StringName in [&"toggle_view", &"interact", &"grab", &"jump", &"sprint"]:
		var pressed := input_enabled and Input.is_action_pressed(action)
		if pressed and not bool(_buttons.get(action, false)):
			match action:
				&"toggle_view": set_first_person(not is_first_person())
				&"interact": vehicle_interact.emit(null)
		_buttons[action] = pressed
	_follow_seat()
	_visual.rotation = Vector3.ZERO
	_visual.set_suit(character.suit_on)
	_rig.set_fill_layers(_visual.zone_layers())
	_visual.play(&"seated")
	if report_position.is_valid():
		report_position.call(global_position, view_yaw())

## Idle below 0.15 m/s, walk up to SPRINT_ABOVE (2.6 m/s), sprint above, with +-0.15 m/s hysteresis at the walk/sprint split.
## Coasting to a stop with no input below the walk clip's slowest scale settles into idle instead of slow-motion steps.
func _pick_locomotion(ground_speed: float, no_input: bool) -> StringName:
	if ground_speed < IDLE_BELOW:
		return &"idle"
	var next: StringName = &"walk"
	if _locomotion == &"sprint":
		next = &"walk" if ground_speed < SPRINT_ABOVE - SPRINT_HYSTERESIS else &"sprint"
	elif ground_speed > SPRINT_ABOVE + SPRINT_HYSTERESIS:
		next = &"sprint"
	if next == &"walk" and no_input and ground_speed < PlayerVisual.WALK_CLIP_SPEED * PlayerVisual.MIN_CLIP_SCALE:
		next = &"idle"
	return next

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
	if is_instance_valid(_ladder):
		_ladder = null
		return
	var target := aimed_target()
	if target.kind == "ladder":
		_ladder = target.node as ClimbableLadder
		velocity = Vector3.ZERO
		return
	if target.kind == "vehicle" and held_item() == null:
		vehicle_interact.emit(target.node)
		return
	if target.kind != "station":
		if target.kind == "item" or held_item() != null:
			_grab()
		return
	# Every station opens its surface; the suit rack's has the suit check and the tank refill (Prompt 07).
	_visual.play_once(&"use", 1.0)
	_answer(&"use_station", target.id, {})

## E holds/releases the ladder; W/S climb, A/D or Space release it. All motion still uses real collision.
func _climb_motion(delta: float) -> bool:
	if not is_instance_valid(_ladder):
		return false
	if not input_enabled:
		velocity = Vector3.ZERO
		return true
	if Input.is_action_pressed("jump") or Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right"):
		_ladder = null
		return false
	var axis := Input.get_axis("move_forward", "move_back")
	var anchor := _ladder.global_position + _ladder.front() * 0.36
	var correction := Vector3(anchor.x - global_position.x, 0, anchor.z - global_position.z)
	velocity = correction.limit_length(2.5 * delta) / maxf(delta, 0.001)
	velocity.y = -axis * 1.6
	move_and_slide()
	_visual.play(&"use")
	if axis < 0.0 and global_position.y >= _ladder.top_y() + 0.02:
		var across := -_ladder.front() * 0.95
		if not test_move(global_transform, across):
			move_and_collide(across)
			_ladder = null
			velocity = Vector3.ZERO
	elif axis > 0.0 and global_position.y <= _ladder.bottom_y() + 0.02:
		_ladder = null
		velocity = Vector3.ZERO
	return true

func _grab() -> void:
	if held_item() != null:
		var throwing := Input.is_action_pressed("sprint")
		var answer := _answer(&"drop", _held.item_id, {})
		if answer.ok:
			_finish_drop(throwing)
		elif answer.pending:
			_waiting[answer.request_id] = {"action": &"drop", "throw": throwing}
		return
	var target := aimed_target()
	if target.kind != "item":
		return
	var answer := _answer(&"pick_up", target.id, {})
	if answer.ok:
		_finish_pick_up(target.node as CarryItem)
	elif answer.pending:
		_waiting[answer.request_id] = {"action": &"pick_up", "node": target.node}


## On a networked client the host answers pick_up and drop later (GameEvents.action_resolved): finish them here.
func resolve_answer(result: ActionResult) -> void:
	if not _waiting.has(result.request_id):
		return
	var w: Dictionary = _waiting[result.request_id]
	_waiting.erase(result.request_id)
	action_answered.emit(result)
	if not result.ok:
		return
	if w.action == &"drop" and held_item() != null:
		_finish_drop(bool(w.throw))
	elif w.action == &"pick_up" and is_instance_valid(w.node):
		_finish_pick_up(w.node as CarryItem)


func _finish_pick_up(item: CarryItem) -> void:
	_held = item
	if not _held.is_held():
		_held.attach_to(_visual.hand_anchor())


func _finish_drop(throwing: bool) -> void:
	var forward := -Basis(Vector3.UP, _rig.yaw()).z
	var toss := forward * tuning.throw_speed if throwing else Vector3.ZERO
	_held.release(global_position + Vector3.UP * tuning.eye_height_m + forward * (tuning.body_radius_m + 0.5), toss)
	_held = null
