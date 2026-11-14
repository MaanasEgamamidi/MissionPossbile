extends SceneTree
## Headless integration tests using real collision and action input.

var _passed: int = 0
var _total: int = 0
var _world: Node3D
var _player: PlayerController
var _crew := CharacterState.new()
var _config := GameConfig.new()
var _tuning := PlayerTuning.new()
var _calls: Array[Dictionary] = []
var _refuse: bool = false
var _reports: int = 0
var _reported_position := Vector3.ZERO
var _answers: Array[ActionResult] = []
## Every state the player's visual changed to, in order.
var _states: Array[StringName] = []

func _initialize() -> void:
	await process_frame
	_test_input()
	_world = Node3D.new()
	root.add_child(_world)
	_box(Vector3(0, -0.5, 0), Vector3(100, 1, 100))
	_box(Vector3(0, 2, 8), Vector3(12, 4, 0.2))
	_box(Vector3(20, 0.1, -3), Vector3(4, 0.2, 4))
	_ramp(30.0, 20.0)
	_ramp(40.0, 50.0)
	_box(Vector3(-40, 0.5, -20), Vector3(4, 1, 4))   # 1 m ledge to walk off
	_crew.owner_peer = 1
	_crew.cargo = [&"existing"]
	_player = PlayerController.new()
	_player.setup(_config, _tuning, _crew, _submit, _report)
	_world.add_child(_player)
	_player.action_answered.connect(func(result: ActionResult) -> void: _answers.append(result))
	_player.visual().state_changed.connect(func(state: StringName) -> void: _states.append(state))
	await _frames(5)
	_check("capsule and collision layers", _player.collision_layer == Layers.PLAYER and _player.collision_mask == (Layers.WORLD | Layers.DOOR | Layers.ITEM) and (_player.get_child(0) as CollisionShape3D).shape is CapsuleShape3D)
	await _test_motion()
	await _test_cameras()
	await _test_authority()
	await _test_visual()
	_check("position reported every physics frame", _reports > 100 and _reported_position.distance_to(_player.global_position) < 0.001)
	_world.queue_free()
	await process_frame
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)

func _test_input() -> void:
	PlayerInput.ensure_actions()
	var expected: Dictionary = {
		&"move_forward": [KEY_W], &"move_back": [KEY_S], &"move_left": [KEY_A], &"move_right": [KEY_D],
		&"sprint": [KEY_SHIFT], &"jump": [KEY_SPACE], &"interact": [KEY_E], &"grab": [KEY_G, -MOUSE_BUTTON_LEFT],
		&"toggle_view": [KEY_TAB], &"map": [KEY_M], &"push_to_talk": [KEY_V], &"back": [KEY_ESCAPE],
		&"source_register": [KEY_BACKSPACE | KEY_MASK_SHIFT],
	}
	for action: StringName in expected:
		var codes: Array[int] = []
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				codes.append(event.physical_keycode | (KEY_MASK_SHIFT if event.shift_pressed else 0))
			elif event is InputEventMouseButton:
				codes.append(-event.button_index)
		_check("input " + String(action), InputMap.has_action(action) and codes == expected[action], str(codes))
	var f5_free := true
	for action: StringName in InputMap.get_actions():
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey and (event.keycode == KEY_F5 or event.physical_keycode == KEY_F5):
				f5_free = false
	_check("F5 unbound", f5_free)
	_check("view and map separate", PlayerInput.describe(&"toggle_view") == "Tab" and PlayerInput.describe(&"map") == "M")
	_check("grab help", PlayerInput.describe(&"grab") == "G / Left mouse")
	var remap := InputEventKey.new()
	remap.physical_keycode = KEY_R
	PlayerInput.rebind(&"interact", remap)
	PlayerInput.ensure_actions()
	_check("ensure preserves remap", InputMap.action_get_events(&"interact").size() == 1 and PlayerInput.describe(&"interact") == "R")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/tmp"))
	var saved := PlayerInput.save("res://tests/tmp/player_input.json")
	PlayerInput.reset(&"interact")
	var reset_ok := PlayerInput.describe(&"interact") == "E"
	var loaded := PlayerInput.load("res://tests/tmp/player_input.json")
	_check("remap save reset load", saved == OK and loaded == OK and reset_ok and PlayerInput.describe(&"interact") == "R")
	PlayerInput.reset(&"interact")

func _test_motion() -> void:
	_player.teleport(Vector3(0, 3, 0), 0)
	var fall_frames := 0
	while fall_frames < 180:
		await _frames(1)
		fall_frames += 1
		if _player.is_on_floor():
			break
	var fall_time := float(fall_frames) / Engine.physics_ticks_per_second
	var expected := sqrt(6.0 / GameConfig.MARS_GRAVITY)
	_check("Mars free fall %.4f s" % fall_time, absf(fall_time / expected - 1.0) < 0.05)
	await _frames(3)
	var base := _player.position.y
	var apex := base
	var air_frames := 0
	_states.clear()
	Input.action_press("jump")
	await _frames(1)
	Input.action_release("jump")
	apex = maxf(apex, _player.position.y)
	air_frames += 1
	while air_frames < 120:
		await _frames(1)
		air_frames += 1
		apex = maxf(apex, _player.position.y)
		if _player.is_on_floor():
			break
	apex -= base
	_check("jump apex %.4f m airtime %.4f s" % [apex, float(air_frames) / Engine.physics_ticks_per_second], absf(apex / _tuning.jump_height_m - 1.0) < 0.05 and air_frames < 90)
	await _frames(45)   # let the landing hold finish
	_check("jump plays jump_start, jump, land in order", _jump_phases() == [&"jump_start", &"jump", &"land"] and _states.back() == &"idle", str(_states))
	# Walking off a 1 m ledge: no push-off, straight to the in-air pose, then the landing.
	_player.teleport(Vector3(-40, 1.01, -20), 0)
	await _frames(10)
	_states.clear()
	Input.action_press("move_forward")
	await _frames(100)
	Input.action_release("move_forward")
	await _frames(45)
	_check("walking off a ledge goes straight to jump then land", _jump_phases() == [&"jump", &"land"] and _player.position.y < 0.05 and _player.is_on_floor(), str(_states) + " " + str(_player.position))
	var walk := await _speed(false, false)
	_check("walk speed %.4f m/s" % walk, absf(walk / _tuning.walk_speed - 1.0) < 0.03)
	var suited := await _speed(true, false)
	_check("suit speed %.4f m/s" % suited, absf(suited / (walk * 0.8) - 1.0) < 0.03)
	var sprint := await _speed(false, true)
	_check("sprint ratio %.4f" % (sprint / walk), absf(sprint / walk / _tuning.sprint_multiplier - 1.0) < 0.03)
	_check("local sprint stamina drains", _crew.stamina < 100.0)
	_player.teleport(Vector3(30, 0.01, 1), 0)
	await _frames(5)
	Input.action_press("move_forward")
	await _frames(110)
	Input.action_release("move_forward")
	_check("climbs 20 degree ramp", _player.position.y > 0.9 and _player.position.z < -2.5, str(_player.position))
	_player.teleport(Vector3(40, 0.01, 1), 0)
	await _frames(5)
	Input.action_press("move_forward")
	await _frames(110)
	Input.action_release("move_forward")
	_check("rejects 50 degree ramp", _player.position.z > -0.6 and _player.position.y < 0.4, str(_player.position))
	_player.teleport(Vector3(20, 0.01, 0), 0)
	await _frames(5)
	_states.clear()
	Input.action_press("move_forward")
	await _frames(60)
	Input.action_release("move_forward")
	_check("climbs 0.2 m step", _player.position.z < -1.5 and absf(_player.position.y - 0.2) < 0.02, str(_player.position))
	_check("a step-up plays neither jump nor land", _jump_phases().is_empty(), str(_states))
	_player.teleport(Vector3(0, 0.01, 6), PI)
	await _frames(5)
	Input.action_press("move_forward")
	var through := false
	for i: int in 120:
		await _frames(1)
		through = through or _player.position.z > 7.9 - _tuning.body_radius_m + 0.01
	Input.action_release("move_forward")
	_check("wall blocks for two seconds", not through and _player.position.z > 7.4, str(_player.position))

## The jump-related states among the recorded ones, in order.
func _jump_phases() -> Array[StringName]:
	var phases: Array[StringName] = []
	for state: StringName in _states:
		if state in [&"jump_start", &"jump", &"land"]:
			phases.append(state)
	return phases

func _speed(suited: bool, sprint: bool) -> float:
	_player.teleport(Vector3(-20, 0.01, 10), 0)
	_crew.suit_on = suited
	await _frames(5)
	Input.action_press("move_forward")
	if sprint:
		Input.action_press("sprint")
	await _frames(30)
	var start := _player.position
	await _frames(30)
	var speed := (_player.position - start).length() * 2.0
	Input.action_release("move_forward")
	Input.action_release("sprint")
	return speed

func _test_cameras() -> void:
	_check("starts first person", _player.is_first_person())
	var rig := _player.camera_rig()
	_check("first person FOV", is_equal_approx(rig.camera().fov, 72.0))
	_crew.suit_on = true
	await _frames(2)
	var hidden := Layers.render_bit(Layers.RENDER_FIRST_PERSON_HIDDEN)
	var masks_ok := (rig.camera().cull_mask & hidden) == 0
	var visible_count := 0
	for node: Node in _player.visual().find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.name == &"Head" or mesh.name == &"Helmet":
			# not drawn for the player's own camera, but still casting a shadow
			masks_ok = masks_ok and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and (mesh.layers & hidden) == 0
		elif mesh.name.begins_with("Arm") or mesh.name.begins_with("Hand") or mesh.name.begins_with("Leg") or mesh.name.begins_with("Boot") or mesh.name == &"Torso":
			visible_count += 1
			masks_ok = masks_ok and (mesh.layers & rig.camera().cull_mask) != 0
	_check("first person head hidden limbs visible", masks_ok and visible_count == 9)
	_player.visual().set_zone_layers(6)
	var head := _player.visual().find_child("Head", true, false) as MeshInstance3D
	_check("zone layers keep the head shadow-only and lit by the room", head.layers == 6 and head.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and (_player.visual().find_child("Torso", true, false) as MeshInstance3D).layers == 6)
	_player.set_first_person(false)
	_check("third person draws the head normally", head.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	_player.set_first_person(true)
	_player.teleport(Vector3(0, 0.01, 0), 0)
	_player.set_first_person(false)
	await _frames(6)
	var distance := rig.camera().global_position.z - _player.global_position.z
	_check("third person FOV and distance %.3f m" % distance, is_equal_approx(rig.camera().fov, 72.0) and absf(distance - _config.third_person_distance_m) < 0.1 and (rig.camera().cull_mask & hidden) != 0)
	_player.teleport(Vector3(0, 0.01, 7.3), 0)
	await _frames(6)
	_check("camera stays before wall", rig.camera().global_position.z < 7.9 and rig.camera().global_position.z > _player.global_position.z, str(rig.camera().global_position))
	var arm := rig.get_node("SpringArm") as SpringArm3D
	_check("spring arm sphere and mask", arm.shape is SphereShape3D and is_equal_approx((arm.shape as SphereShape3D).radius, 0.2) and arm.collision_mask == (Layers.WORLD | Layers.DOOR))
	for first: bool in [true, false]:
		_player.set_first_person(first)
		var current_count := 0
		for node: Node in rig.find_children("*", "Camera3D", true, false):
			if (node as Camera3D).current:
				current_count += 1
		_check("one current camera " + str(first), current_count == 1 and rig.camera().current)
	rig.add_look(0.5, 10)
	_check("look and pitch clamp", is_equal_approx(rig.yaw(), 0.5) and is_equal_approx(rig.pitch(), deg_to_rad(_tuning.pitch_limit_degrees)))
	_player.teleport(Vector3.ZERO, 0)
	_player.set_first_person(true)

func _test_authority() -> void:
	var owner := _crew.owner_peer
	var cargo := _crew.cargo.duplicate()
	for i: int in 20:
		await _tap("toggle_view")
	_crew.suit_on = not _crew.suit_on
	await _frames(2)
	_check("20 view toggles and suit preserve authority", _crew.owner_peer == owner and _crew.cargo == cargo and _player.is_first_person())
	await _tap("map")
	_check("map never toggles perspective", _player.is_first_person())
	_player.teleport(Vector3.ZERO, 0)
	await _frames(5)
	var item := CarryItem.make_crate(&"crate")
	_world.add_child(item)
	item.position = Vector3(0, _tuning.eye_height_m, -1.5)
	item.freeze = true
	await _frames(3)
	_check("aim identifies item", _player.aimed_target().id == &"crate")
	_calls.clear()
	Input.action_press("grab")
	await _frames(5)
	Input.action_release("grab")
	await _frames(2)
	_check("grab sends one pickup and attaches", _calls.size() == 1 and _calls[0].action == &"pick_up" and _calls[0].target == &"crate" and _player.held_item() == item and item.is_held() and item.freeze and item.collision_layer == 0)
	var follow_error := 0.0
	Input.action_press("move_forward")
	for i: int in 30:
		await _frames(1)
		follow_error = maxf(follow_error, item.global_position.distance_to(_player.visual().hand_anchor().global_position))
	Input.action_release("move_forward")
	_check("held item follows hand within 1 cm", follow_error < 0.01, str(follow_error))
	await _tap("grab")
	_check("drop sends once and restores free body", _calls.size() == 2 and _calls[1].action == &"drop" and _player.held_item() == null and not item.is_held() and not item.freeze and item.collision_layer == Layers.ITEM and item.collision_mask == (Layers.WORLD | Layers.ITEM | Layers.DOOR))
	_check("controller never changes cargo or owner", _crew.cargo == cargo and _crew.owner_peer == owner)
	item.freeze = true
	_player.teleport(Vector3.ZERO, 0)
	item.global_position = Vector3(0, _tuning.eye_height_m, -1.5)
	await _frames(4)
	_refuse = true
	await _tap("grab")
	_check("refused pickup attaches nothing", _calls.size() == 3 and _calls[2].action == &"pick_up" and _player.held_item() == null and not item.is_held() and not _answers.back().ok)
	_refuse = false
	await _tap("grab")
	_refuse = true
	await _tap("grab")
	_check("refused drop keeps prop held", _player.held_item() == item and item.is_held() and not _answers.back().ok)
	_refuse = false
	Input.action_press("sprint")
	await _tap("grab")
	Input.action_release("sprint")
	_check("sprint drop throws forward", _player.held_item() == null and not item.freeze and absf(item.linear_velocity.z + _tuning.throw_speed) < 0.05, str(item.linear_velocity))
	# E is the default for every interaction: it picks up what you look at and puts down what you hold.
	item.freeze = true
	item.linear_velocity = Vector3.ZERO
	_player.teleport(Vector3.ZERO, 0)
	item.global_position = Vector3(0, _tuning.eye_height_m, -1.5)
	await _frames(4)
	var before := _calls.size()
	await _tap("interact")
	var picked: bool = _calls.size() == before + 1 and _calls[before].action == &"pick_up" and _player.held_item() == item
	await _tap("interact")
	_check("E picks up and puts down", picked and _calls.size() == before + 2 and _calls[before + 1].action == &"drop" and _player.held_item() == null)
	item.queue_free()
	await _frames(2)
	var station := Area3D.new()
	station.collision_layer = Layers.STATION
	station.collision_mask = 0
	station.set_meta("station_id", &"suits_test")
	station.set_meta("kind", "suits")
	var collider := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	collider.shape = sphere
	station.add_child(collider)
	_world.add_child(station)
	station.position = Vector3(0, _tuning.eye_height_m, -1.5)
	await _frames(3)
	await _tap("interact")
	_check("suit station dispatch", _calls.back().action == &"begin_suit_check" and _calls.back().params == {"on": not _crew.suit_on})
	station.set_meta("kind", "computer")
	await _tap("interact")
	_check("other station returns host failure", _calls.back().action == &"use_station" and _answers.back().reason == &"unknown_action")
	station.queue_free()

func _test_visual() -> void:
	var visual := _player.visual()
	var colors: Array[Color] = []
	for i: int in 4:
		visual.set_crew_identity(i)
		var patch := visual.find_child("ShoulderPatch", true, false) as MeshInstance3D
		var color := (patch.material_override as StandardMaterial3D).albedo_color
		if not colors.has(color):
			colors.append(color)
	_check("four distinct identity patches", colors.size() == 4)
	_check("both hand anchors exist", visual.hand_anchor() != null and visual.hand_anchor(false) != null)
	# Pause the controller so it does not replace the requested visual state.
	_player.set_physics_process(false)
	visual.play_once(&"use", 5.0)
	visual.play(&"walk")
	_check("a held one-shot clip is not replaced by a movement state", visual.get("_state") == &"use")
	visual.clear_hold()
	for state: StringName in [&"idle", &"walk", &"sprint", &"jump_start", &"jump", &"land", &"carry", &"use", &"suit", &"seated"]:
		visual.play(state)
		visual._process(0.1)
		var right := visual.find_child("ShoulderR", true, false) as Node3D
		_check("visual state " + String(state), is_finite(right.rotation.x) and visual.get("_state") == state)
	visual.set_suit(false)
	var helmet := visual.find_child("Helmet", true, false) as Node3D
	var pack := visual.find_child("Pack", true, false) as Node3D
	var hidden := not helmet.visible and not pack.visible
	visual.set_suit(true)
	_check("suit toggles helmet and pack", hidden and helmet.visible and pack.visible)
	# Exercise replacement discovery using a small synthetic authored model.
	var model := Node3D.new()
	for part_name: String in ["Head", "Helmet", "Torso"]:
		var mesh := MeshInstance3D.new()
		mesh.name = part_name
		mesh.mesh = BoxMesh.new()
		model.add_child(mesh)
		mesh.owner = model
	for anchor_name: String in ["HandAnchorR", "HandAnchorL"]:
		var anchor := Node3D.new()
		anchor.name = anchor_name
		model.add_child(anchor)
		anchor.owner = model
	var animation := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	for clip: Array in [[&"idle", 1.0], [&"walk", 1.0], [&"land", 0.42]]:
		var anim := Animation.new()
		anim.length = clip[1]
		library.add_animation(clip[0], anim)
	animation.add_animation_library(&"", library)
	model.add_child(animation)
	animation.owner = model
	var packed := PackedScene.new()
	var packed_ok := packed.pack(model) == OK
	model.free()
	visual.set_model(packed)
	_check("replacement model anchors and head layers", packed_ok and visual.hand_anchor() != null and visual.hand_anchor(false) != null and (visual.find_child("Head", true, false) as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	_check("clip_length reads the rig clip or falls back", is_equal_approx(visual.clip_length(&"land", 0.4), 0.42) and is_equal_approx(visual.clip_length(&"jump_start", 0.25), 0.25))
	visual.play(&"walk")
	visual.play_once(&"jump_start", 0.3)
	visual.play(&"idle")
	_check("a rig without jump_start skips it and does not hold", visual.get("_state") == &"idle" and not visual.has_clip(&"jump_start"))
	visual.play_once(&"land", 5.0)
	visual.play(&"walk")
	_check("a rig clip that exists is held", visual.get("_state") == &"land")
	visual.clear_hold()
	_player.set_physics_process(true)
	await _frames(2)

func _submit(action: StringName, target: StringName, params: Dictionary) -> ActionResult:
	_calls.append({"action": action, "target": target, "params": params.duplicate(true)})
	if _refuse:
		return ActionResult.failure("test", &"cargo_full")
	if action == &"use_station":
		return ActionResult.failure("test", &"unknown_action")
	return ActionResult.success("test")

func _report(at: Vector3, _yaw: float) -> void:
	_reports += 1
	_reported_position = at

func _frames(count: int) -> void:
	for i: int in count:
		await physics_frame
		await process_frame

func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _frames(1)
	Input.action_release(action)
	await _frames(1)

func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	_world.add_child(body)
	body.position = at
	return body

func _ramp(x: float, degrees: float) -> void:
	var angle := deg_to_rad(degrees)
	var length := 8.0
	var body := _box(Vector3(x, sin(angle) * length / 2.0 - cos(angle) * 0.1, -cos(angle) * length / 2.0), Vector3(4, 0.2, length))
	body.rotation.x = angle

func _check(label: String, condition: bool, detail: String = "condition false") -> void:
	_total += 1
	if condition:
		_passed += 1
		print("PASS " + label)
	else:
		print("FAIL " + label + ": " + detail)
