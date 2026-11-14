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
	_check("capsule and collision layers", _player.collision_layer == Layers.PLAYER and _player.collision_mask == (Layers.WORLD | Layers.DOOR | Layers.ITEM | Layers.CREW_SOLID) and (_player.get_child(0) as CollisionShape3D).shape is CapsuleShape3D)
	await _test_motion()
	await _test_cameras()
	await _test_authority()
	await _test_visual()
	_test_crew_looks()
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
	var visual := _player.visual()
	var fractions: Array[float] = []
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
		if visual.get("_state") == &"jump":
			fractions.append(visual.get("_jump_fraction"))
		if _player.is_on_floor():
			break
	apex -= base
	_check("jump apex %.4f m airtime %.4f s" % [apex, float(air_frames) / Engine.physics_ticks_per_second], absf(apex / _tuning.jump_height_m - 1.0) < 0.05 and air_frames < 90)
	await _frames(45)   # let the landing hold finish
	_check("standing jump plays jump_start, jump, land in order", _jump_phases() == [&"jump_start", &"jump", &"land"] and _states.back() == &"idle", str(_states))
	var rising := not fractions.is_empty()
	for i: int in range(1, fractions.size()):
		rising = rising and fractions[i] >= fractions[i - 1] - 0.0001
	_check("jump arc time follows vertical velocity: rise, apex, fall", rising and fractions[0] < 0.35 and fractions.back() > 0.85, str(fractions))
	# Running jump: the push-off and the air arc, then no standing land and no loss of speed.
	_player.teleport(Vector3(-20, 0.01, 30), 0)
	_crew.suit_on = false
	await _frames(5)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(40)
	var before_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	_states.clear()
	await _tap("jump")
	while not _player.is_on_floor():
		await _frames(1)
	await _frames(3)
	var after_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	Input.action_release("move_forward")
	Input.action_release("sprint")
	_check("running jump skips land, keeps speed %.2f -> %.2f m/s" % [before_speed, after_speed], _jump_phases() == [&"jump_start", &"jump"] and _states.back() == &"sprint" and after_speed > before_speed * 0.97, str(_states))
	await _frames(30)
	# Walking off a 1 m ledge: no push-off, the arc entered at the apex, and (still moving) no standing land.
	_player.teleport(Vector3(-40, 1.01, -20), 0)
	await _frames(10)
	_states.clear()
	var entry := -1.0
	Input.action_press("move_forward")
	for i: int in 140:
		await _frames(1)
		if entry < 0.0 and visual.get("_state") == &"jump":
			entry = visual.get("_jump_fraction")
	var landed_in: StringName = visual.get("_state")
	Input.action_release("move_forward")
	await _frames(45)
	_check("walking off a ledge enters the arc at the apex (%.3f), no jump_start, no standing land" % entry, _jump_phases() == [&"jump"] and absf(entry - 0.5) < 0.05 and landed_in in [&"walk", &"sprint"] and _player.position.y < 0.05 and _player.is_on_floor(), str(_states) + " " + str(_player.position))
	# Locomotion follows ground speed, not the sprint key: from standing, sprint shows only once fast enough,
	# the clip scale stays within 0.75-1.5, and stopping settles into idle instead of slow-motion steps.
	_player.teleport(Vector3(-20, 0.01, 30), 0)
	await _frames(10)
	_states.clear()
	var scale_ok := true
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for i: int in 40:
		await _frames(1)
		if visual.get("_state") in [&"walk", &"sprint"]:
			var s: float = visual.get("_speed")
			scale_ok = scale_ok and s >= PlayerVisual.MIN_CLIP_SCALE - 0.001 and s <= PlayerVisual.MAX_CLIP_SCALE + 0.001
	Input.action_release("move_forward")
	Input.action_release("sprint")
	var idle_frame := -1
	for i: int in 30:
		await _frames(1)
		if idle_frame < 0 and visual.get("_state") == &"idle":
			idle_frame = i
		if visual.get("_state") in [&"walk", &"sprint"]:
			var s: float = visual.get("_speed")
			scale_ok = scale_ok and s >= PlayerVisual.MIN_CLIP_SCALE - 0.001
	var walk_at := _states.find(&"walk")
	var sprint_at := _states.find(&"sprint")
	_check("sprint key from standing: walk first, sprint by speed", walk_at >= 0 and sprint_at > walk_at, str(_states))
	_check("locomotion clip scale stays within 0.75-1.5", scale_ok)
	_check("stopping settles into idle within 0.25 s (frame %d)" % idle_frame, idle_frame >= 0 and idle_frame <= 15, str(_states))
	# Gait by speed at steady pace: suited 2.4 m/s walks at 1.2x; the unsuited 3.0 m/s walk borrows the sprint lope
	# (above 2.75 m/s) instead of overdriving the walk clip to its 1.5x limit.
	for suited: bool in [true, false]:
		_crew.suit_on = suited
		_player.teleport(Vector3(-20, 0.01, 30), 0)
		await _frames(5)
		Input.action_press("move_forward")
		await _frames(40)
		var gait_state: StringName = visual.get("_state")
		var gait_scale: float = visual.get("_speed")
		Input.action_release("move_forward")
		await _frames(20)
		var wanted: StringName = &"walk" if suited else &"sprint"
		_check("steady %s walk shows %s at %.2fx" % ["suited" if suited else "unsuited", wanted, gait_scale], gait_state == wanted and gait_scale >= PlayerVisual.MIN_CLIP_SCALE and gait_scale < PlayerVisual.MAX_CLIP_SCALE)
	_crew.suit_on = false
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
	var cam3 := rig.camera()
	var feet_local := cam3.global_transform.affine_inverse() * _player.global_position
	var feet_ndc_y := (feet_local.y / -feet_local.z) / tan(deg_to_rad(cam3.fov) * 0.5)
	var feet_margin := (feet_ndc_y + 1.0) * 0.5
	_check("third person level look: boots %.3f of screen height above the bottom edge" % feet_margin, absf(feet_margin - 0.08) < 0.015)
	_check("third-person fill light only in third person", rig.fill_light().visible and not rig.fill_light().shadow_enabled and rig.fill_light().light_energy <= 1.0)
	_player.set_first_person(true)
	var fill_hidden := not rig.fill_light().visible
	_player.set_first_person(false)
	_check("first person hides the fill light", fill_hidden)
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
	# Prompt 07: the suit rack has a surface (suit check and tank refill), so E asks to open it like any station.
	_check("suit station dispatch", _calls.back().action == &"use_station" and _calls.back().target == &"suits_test")
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
	for clip: Array in [[&"idle", 1.0], [&"walk", 1.0], [&"sprint", 0.5], [&"land", 0.42], [&"jump", 1.0]]:
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
	var player_anim := visual.get("_animation") as AnimationPlayer
	_check("jump clip is non-looping, walk loops", player_anim.get_animation(&"jump").loop_mode == Animation.LOOP_NONE and player_anim.get_animation(&"walk").loop_mode == Animation.LOOP_LINEAR)
	_check("per-transition blend times", is_equal_approx(PlayerVisual.blend_time(&"idle", &"walk"), 0.2) and is_equal_approx(PlayerVisual.blend_time(&"walk", &"sprint"), 0.25)
		and is_equal_approx(PlayerVisual.blend_time(&"walk", &"jump_start"), 0.07) and is_equal_approx(PlayerVisual.blend_time(&"jump_start", &"jump"), 0.1)
		and is_equal_approx(PlayerVisual.blend_time(&"jump", &"land"), 0.06) and is_equal_approx(PlayerVisual.blend_time(&"walk", &"idle"), 0.2)
		and is_equal_approx(PlayerVisual.blend_time(&"land", &"idle"), 0.2) and is_equal_approx(PlayerVisual.blend_time(&"walk", &"jump"), 0.15))
	visual.play(&"walk")
	player_anim.seek(0.3, true)
	visual.play(&"sprint")
	_check("walk to sprint keeps the step phase (0.3 of 1.0 s -> 0.15 of 0.5 s)", absf(player_anim.current_animation_position - 0.15) < 0.01, str(player_anim.current_animation_position))
	visual.play(&"jump")
	visual.set_jump_phase(0.5)
	var at_apex := player_anim.current_animation_position
	visual.set_jump_phase(3.0)
	_check("set_jump_phase seeks the arc and holds the fall pose", absf(at_apex - 0.5) < 0.01 and player_anim.current_animation_position <= 0.96 and player_anim.current_animation_position > 0.9, "%.3f %.3f" % [at_apex, player_anim.current_animation_position])
	visual.play(&"land")
	player_anim.seek(0.4, true)
	player_anim.advance(0.1)
	var finished := not player_anim.is_playing()
	visual.play(&"land")
	_check("a finished non-looping clip is not restarted by play()", finished and player_anim.assigned_animation == "land" and player_anim.current_animation_position > 0.3,"%s %.3f" % [player_anim.is_playing(), player_anim.current_animation_position])
	visual.play(&"idle")
	visual.play_once(&"land", 0.42, 0.2)
	visual.play(&"walk")
	var held_early: bool = visual.get("_state") == &"land"
	visual._process(0.25)
	visual.play(&"idle")
	var idle_waits: bool = visual.get("_state") == &"land"
	visual.play(&"walk")
	_check("landing hold: walk may cut it after 0.2 s, idle waits (process-time hold)", held_early and idle_waits and visual.get("_state") == &"walk")
	visual.play(&"idle")
	visual.dip(0.05, 0.2)
	visual._process(0.1)
	var model_node := visual.get("_model") as Node3D
	var dipped := model_node.position.y < -0.04
	visual._process(0.15)
	_check("running-landing hip dip goes 5 cm down and back", dipped and is_zero_approx(model_node.position.y))
	# The first drawn frame after play() already advances (no lost start step).
	visual.play(&"walk")
	visual.play(&"idle")
	player_anim.advance(0.05)
	_check("first frame after a clip change advances the clip", absf(player_anim.current_animation_position - 0.05) < 0.005, "%.4f" % player_anim.current_animation_position)
	# A long frame that runs the jump arc past its end must not leave nothing playing.
	visual.play(&"jump")
	visual.set_jump_phase(0.9)
	player_anim.advance(0.5)
	var ran_out := not player_anim.is_playing()
	visual.set_jump_phase(1.0)
	_check("jump arc run past its end resumes on the held fall pose", ran_out and player_anim.is_playing() and player_anim.current_animation == "jump" and absf(player_anim.current_animation_position - 0.95) < 0.01, "%s %.3f" % [player_anim.current_animation, player_anim.current_animation_position])
	# A running landing enters the gait on a heel strike, not at 0.
	visual.play(&"sprint")
	_check("running landing starts sprint at the contact phase", absf(player_anim.current_animation_position - PlayerVisual.CONTACT_PHASE[&"sprint"] * 0.5) < 0.01, "%.3f" % player_anim.current_animation_position)
	_player.set_physics_process(true)
	await _frames(2)

## A small mesh with the given surface materials (named like the imported ones) and, optionally, a "Feminine" shape.
func _look_mesh(part_name: String, materials: Array[String], feminine: bool) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	if feminine:
		mesh.add_blend_shape(&"Feminine")
	for material_name: String in materials:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
		var shapes := []
		if feminine:
			var shape := []
			shape.resize(Mesh.ARRAY_MAX)
			shape[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT * 0.9, Vector3.UP * 0.9])
			shapes.append(shape)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
		var material := StandardMaterial3D.new()
		material.resource_name = material_name
		material.albedo_color = Color.WHITE
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	return part

## The surface override of `part` whose imported material is called `material_name`, or null.
func _override_of(part: MeshInstance3D, material_name: String) -> Material:
	for surface: int in part.mesh.get_surface_count():
		if part.mesh.surface_get_material(surface).resource_name == material_name:
			return part.get_surface_override_material(surface)
	return null

func _test_crew_looks() -> void:
	# Synthetic stand-in for the astronaut model the Blender agent is building: hair meshes, the "Feminine" shape,
	# Mat_Skin / Mat_Hair / Mat_Ident / Mat_IdentDark surfaces.
	var model := Node3D.new()
	var parts: Array[MeshInstance3D] = [
		_look_mesh("Body_Head", ["Mat_Skin", "Mat_Hair"], true), _look_mesh("Body_Torso", ["Mat_Skin"], true),
		_look_mesh("Suit_Helmet", ["Mat_SuitWhite", "Mat_Ident"], false), _look_mesh("Suit_Torso", ["Mat_SuitWhite", "Mat_Ident", "Mat_IdentDark"], true)]
	for hair_name: String in ["Hair_Ponytail", "Hair_Curly", "Hair_Bob", "Hair_Buzz", "Hair_Beard", "HairIn_Ponytail", "HairIn_Curly", "HairIn_Bob", "HairIn_Buzz"]:
		parts.append(_look_mesh(hair_name, ["Mat_Hair"], false))
	for ident_name: String in ["Ident_Symbol_Triangle", "Ident_Symbol_Plus", "Ident_Symbol_Circle", "Ident_Symbol_Diamond", "Ident_Band_Solid", "Ident_Band_Double", "Ident_Band_Dots", "Ident_Band_Chevron"]:
		parts.append(_look_mesh(ident_name, ["Mat_Ident"], false))
	for part: MeshInstance3D in parts:
		model.add_child(part)
		part.owner = model
	var packed := PackedScene.new()
	packed.pack(model)
	model.free()
	var a := PlayerVisual.new()
	var b := PlayerVisual.new()
	_world.add_child(a)
	_world.add_child(b)
	a.set_model(packed)
	b.set_model(packed)
	a.set_suit(false)
	b.set_suit(false)
	a.set_crew_identity(0)
	b.set_crew_identity(3)
	var shown := func(v: PlayerVisual) -> Array[String]:
		var out: Array[String] = []
		for hair: Node in v.find_children("Hair*", "MeshInstance3D", true, false) + v.find_children("Ident_*", "MeshInstance3D", true, false):
			if (hair as Node3D).visible:
				out.append(String(hair.name))
		out.sort()
		return out
	_check("looks: each crew member shows only their own hair", shown.call(a) == ["Hair_Ponytail"] and shown.call(b) == ["Hair_Beard", "Hair_Buzz"], "%s / %s" % [shown.call(a), shown.call(b)])
	a.set_crew_identity(1)
	var curly: Array[String] = shown.call(a)
	a.set_crew_identity(2)
	_check("looks: changing identity swaps the hair", curly == ["Hair_Curly"] and shown.call(a) == ["Hair_Bob"])
	a.set_suit(true)
	var suited_hair: Array[String] = shown.call(a)
	a.set_suit(false)
	b.set_suit(true)
	var suited_b: Array[String] = shown.call(b)
	b.set_suit(false)
	_check("looks: suited shows the in-helmet hair (beard stays), the crew's own symbol and band", suited_hair == ["HairIn_Bob", "Ident_Band_Dots", "Ident_Symbol_Circle"]
		and suited_b == ["HairIn_Buzz", "Hair_Beard", "Ident_Band_Chevron", "Ident_Symbol_Diamond"] and shown.call(a) == ["Hair_Bob"], "%s / %s" % [suited_hair, suited_b])
	a.set_first_person(true)
	var fp_ok := true
	for hair: Node in a.find_children("Hair*", "MeshInstance3D", true, false):
		fp_ok = fp_ok and (hair as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	var a_torso := a.find_child("Body_Torso", true, false) as MeshInstance3D
	fp_ok = fp_ok and a_torso.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	a.set_first_person(false)
	var hair_drawn := (a.find_child("Hair_Bob", true, false) as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_check("looks: hair is hidden from the first-person camera like the head", fp_ok and hair_drawn)
	var fem := func(v: PlayerVisual, part_name: String) -> float:
		var mi := v.find_child(part_name, true, false) as MeshInstance3D
		return mi.get_blend_shape_value(mi.find_blend_shape_by_name(&"Feminine"))
	_check("looks: Feminine shape follows the identity on body and suit", is_equal_approx(fem.call(a, "Body_Head"), 1.0) and is_equal_approx(fem.call(a, "Suit_Torso"), 1.0)
		and is_equal_approx(fem.call(b, "Body_Head"), 0.0) and is_equal_approx(fem.call(b, "Body_Torso"), 0.0))
	var a_head := a.find_child("Body_Head", true, false) as MeshInstance3D
	var b_head := b.find_child("Body_Head", true, false) as MeshInstance3D
	var a_skin := _override_of(a_head, "Mat_Skin") as StandardMaterial3D
	var b_skin := _override_of(b_head, "Mat_Skin") as StandardMaterial3D
	var a_hair := _override_of(a_head, "Mat_Hair") as StandardMaterial3D
	var b_hair := _override_of(b_head, "Mat_Hair") as StandardMaterial3D
	var imported := a_head.mesh.surface_get_material(0) as StandardMaterial3D
	_check("looks: skin and hair are per-body copies in the crew's colours", a_skin != null and b_skin != null and a_skin != b_skin and a_hair != b_hair
		and a_skin.albedo_color.is_equal_approx(CrewLooks.look(2).skin_color) and b_skin.albedo_color.is_equal_approx(CrewLooks.look(3).skin_color)
		and b_hair.albedo_color.is_equal_approx(CrewLooks.look(3).hair_color) and imported.albedo_color == Color.WHITE
		and (_override_of(a_torso, "Mat_Skin") as StandardMaterial3D).albedo_color.is_equal_approx(a_skin.albedo_color))
	var b_suit := b.find_child("Suit_Torso", true, false) as MeshInstance3D
	var ident := _override_of(b_suit, "Mat_Ident") as StandardMaterial3D
	var ident_dark := _override_of(b_suit, "Mat_IdentDark") as StandardMaterial3D
	_check("looks: accent and darkened accent surfaces", ident != null and ident_dark != null and ident.albedo_color.is_equal_approx(CrewLooks.accent(3))
		and ident_dark.albedo_color.is_equal_approx(CrewLooks.accent_dark(3)) and ident_dark.albedo_color.v < ident.albedo_color.v
		and ident.emission_enabled and ident.emission.is_equal_approx(CrewLooks.accent(3)) and is_equal_approx(ident.roughness, 1.0))
	a.set_suit(true)
	var glow_on := a_skin.emission_enabled
	a.set_suit(false)
	_check("looks: the face glows faintly only under the helmet", glow_on and not a_skin.emission_enabled)
	var a_model := a.get("_model") as Node3D
	_check("looks: height scales the model, not the body node (feet stay at the origin)", a_model.scale.is_equal_approx(Vector3.ONE * float(CrewLooks.look(2).height))
		and a.scale == Vector3.ONE and is_zero_approx(a_model.position.y))
	a.set_name_tag(CrewLooks.tag_text("Electrical and communications", 2))
	var tag := a.name_tag()
	var symbol := tag.get_node("Symbol") as Label3D if tag != null else null
	var word := tag.get_node("Word") as Label3D if tag != null else null
	var low := tag.position.y if tag != null else 0.0
	a.set_suit(true)
	var lift := tag.position.y - low if tag != null else 0.0
	a.set_suit(false)
	_check("looks: name tag is the crew symbol in the accent colour and a near-white word, higher over a helmet", tag != null and a.name_tag_text() == "● Biology"
		and symbol.modulate.is_equal_approx(CrewLooks.accent(2)) and word.modulate.is_equal_approx(PlayerVisual.NAME_TAG_TEXT) and word.outline_size > 0
		and low > 1.7 and is_equal_approx(lift, PlayerVisual.NAME_TAG_SUITED_LIFT_M), a.name_tag_text())
	var tag_cam := Camera3D.new()
	_world.add_child(tag_cam)
	var sizes: Array[float] = []
	var alphas: Array[float] = []
	for d: float in [1.0, 6.0, 20.0, 40.0]:
		tag_cam.global_transform = Transform3D(Basis(), tag.global_position + Vector3(0, 0, d))
		a.call("_place_name_tag", tag_cam)
		var pixels := tag.global_basis.get_scale().y / (2.0 * d * tan(deg_to_rad(tag_cam.fov) * 0.5)) * 1080.0
		sizes.append(pixels)
		alphas.append(word.modulate.a if tag.visible else 0.0)
	# Two crew standing together: the farther tag shows its symbol only, the nearer one stays whole; apart, both whole.
	b.set_name_tag("Geology")
	a.global_position = Vector3(0, 0, 0)
	b.global_position = Vector3(0.3, 0, -1.0)
	tag_cam.global_transform = Transform3D(Basis(), Vector3(0, 2.2, 8.0))
	a.call("_place_name_tag", tag_cam)
	b.call("_place_name_tag", tag_cam)
	var together := [a.name_tag_collapsed(), b.name_tag_collapsed()]
	b.global_position = Vector3(6.0, 0, -1.0)
	a.call("_place_name_tag", tag_cam)
	b.call("_place_name_tag", tag_cam)
	var apart := [a.name_tag_collapsed(), b.name_tag_collapsed()]
	_check("looks: tags of crew standing together: the farther one collapses to its symbol", together == [false, true] and apart == [false, false], "%s %s" % [together, apart])
	_check("looks: tags are staggered by crew index", is_equal_approx(b.name_tag().position.y - a.name_tag().position.y,
		PlayerVisual.NAME_TAG_HEIGHT_M * (float(CrewLooks.look(3).height) - float(CrewLooks.look(2).height)) + PlayerVisual.NAME_TAG_STAGGER_M))
	var circle_size := (a.name_tag().get_node("Symbol") as Label3D).font_size
	a.set_crew_identity(0)
	var triangle_size := (a.name_tag().get_node("Symbol") as Label3D).font_size
	a.set_crew_identity(2)
	_check("looks: small glyphs are drawn larger so every symbol matches the capitals", circle_size > triangle_size and triangle_size == PlayerVisual.NAME_TAG_FONT_SIZE)
	b.set_name_tag("")
	a.global_position = Vector3.ZERO
	b.global_position = Vector3.ZERO
	tag_cam.queue_free()
	_check("looks: name tag about 22 px at 6 and 20 m, gone up close and far away", absf(sizes[1] - 22.0) < 0.5 and absf(sizes[2] - 22.0) < 0.5
		and is_zero_approx(alphas[0]) and is_equal_approx(alphas[1], 1.0) and is_equal_approx(alphas[2], 1.0) and is_zero_approx(alphas[3]), "%s %s" % [sizes, alphas])
	a.set_name_tag("")
	_check("looks: name tag can be removed; a short display name is shown as is", a.name_tag() == null and CrewLooks.tag_text("Ana", 0) == "Ana")
	# Graceful fallback: the stand-in and a model without hair, shapes or look materials.
	var plain := PlayerVisual.new()
	_world.add_child(plain)
	var fallback_ok := true
	for i: int in 4:
		plain.set_crew_identity(i)
		plain.set_suit(i % 2 == 0)
		fallback_ok = fallback_ok and plain.crew_identity() == i
	var bare := Node3D.new()
	var only_head := MeshInstance3D.new()
	only_head.name = "Head"
	only_head.mesh = BoxMesh.new()
	bare.add_child(only_head)
	only_head.owner = bare
	var bare_packed := PackedScene.new()
	bare_packed.pack(bare)
	bare.free()
	plain.set_model(bare_packed)
	plain.set_crew_identity(1)
	_check("looks: stand-in and bare models take every identity without the new parts", fallback_ok and plain.crew_identity() == 1 and plain.find_children("Hair_*", "", true, false).is_empty())
	# The real astronaut, when imported: two bodies never share a recoloured skin.
	var scene := PlayerVisual.rigged_scene()
	if scene != null:
		var r0 := PlayerVisual.new()
		var r1 := PlayerVisual.new()
		_world.add_child(r0)
		_world.add_child(r1)
		r0.set_model(scene)
		r1.set_model(scene)
		r0.set_crew_identity(0)
		r1.set_crew_identity(1)
		var h0 := r0.find_child("Body_Head", true, false) as MeshInstance3D
		var h1 := r1.find_child("Body_Head", true, false) as MeshInstance3D
		var s0 := _override_of(h0, "Mat_Skin") if h0 != null else null
		var s1 := _override_of(h1, "Mat_Skin") if h1 != null else null
		var hair_count := r0.find_children("Hair_*", "MeshInstance3D", true, false).size()
		_check("looks: real astronaut gets per-body skin (hair meshes in this build: %d)" % hair_count, s0 != null and s1 != null and s0 != s1)
		r0.queue_free()
		r1.queue_free()
	a.queue_free()
	b.queue_free()
	plain.queue_free()
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
