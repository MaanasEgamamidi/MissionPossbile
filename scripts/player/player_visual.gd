class_name PlayerVisual
extends Node3D
## One jointed body used in both perspectives, replaceable by an authored model.

var _model: Node3D
var _head: Node3D
var _helmet: Node3D
var _right: Node3D
var _left: Node3D
var _animation: AnimationPlayer
var _parts: Array[MeshInstance3D] = []
var _suit_parts: Array[Node3D] = []
## Body meshes that sit inside the suit and are hidden while it is worn (rigged model only).
var _under_suit_parts: Array[Node3D] = []
## Where the rigged astronaut is looked for, newest build first.
const RIG_PATHS: Array[String] = ["res://assets/characters/astronaut.glb", "res://assets/characters/final01/astronaut.glb"]
## Ground speed (m/s) the clips cover at speed 1. Walk: the owner's Mixamo walk, retargeted with narrow-feet leg IK by
## tools/blender/character/retarget_mixamo_walk.py (source_speed_m_s). Sprint: tools/blender/character/make_gait.py
## (14 frames at the scene's 30 fps: 0.72 m stance travel in 0.38 of 0.467 s).
const WALK_CLIP_SPEED: float = 1.545
const SPRINT_CLIP_SPEED: float = 4.06
## "jump" is the in-air pose: it loops for as long as the player is airborne (about 1 s for a 0.5 m Mars jump).
const LOOPING: Array[StringName] = [&"idle", &"walk", &"sprint", &"carry", &"seated", &"jump"]
## Emitted whenever the shown state changes (play() or play_once()); tests use it to follow the jump phases.
signal state_changed(state: StringName)
var _limbs: Array[Node3D] = []
var _patch_material := StandardMaterial3D.new()
var _first_person: bool = true
var _suited: bool = false
var _zone_mask: int = 1
var _identity: int = 0
var _state: StringName = &"idle"
var _speed: float = 1.0
var _time: float = 0.0
var _held_until_msec: int = 0

func _init() -> void:
	_build_standin()

## The rigged astronaut scene if it has been built and imported, else null (the stand-in stays).
static func rigged_scene() -> PackedScene:
	for path: String in RIG_PATHS:
		if ResourceLoader.exists(path):
			return load(path) as PackedScene
	return null


## Swaps the stand-in for the rigged astronaut when it exists. Returns true if it did.
func use_rig_if_available() -> bool:
	var scene := rigged_scene()
	if scene == null:
		return false
	set_model(scene)
	return true


## Replaces the placeholder and discovers standard model attachment names.
## Understands two layouts: plain nodes called Head, Helmet, HandAnchorR, HandAnchorL (tests, simple models), and the
## rigged astronaut (meshes Body_Head, Body_Torso, Body_Arms, Body_Legs, Suit_Helmet, Suit_*; bones HandAnchorR/L).
func set_model(scene: PackedScene) -> void:
	remove_child(_model)
	_model.queue_free()
	_parts.clear()
	_suit_parts.clear()
	_under_suit_parts.clear()
	_limbs.clear()
	_model = scene.instantiate() as Node3D
	add_child(_model)
	_head = _model.find_child("Head", true, false) as Node3D
	_helmet = _model.find_child("Helmet", true, false) as Node3D
	_right = _model.find_child("HandAnchorR", true, false) as Node3D
	_left = _model.find_child("HandAnchorL", true, false) as Node3D
	if _head == null:
		_head = _model.find_child("Body_Head", true, false) as Node3D
	if _helmet == null:
		_helmet = _model.find_child("Suit_Helmet", true, false) as Node3D
	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		# The rig is built facing Blender -Y, which arrives as +Z; the game's forward is -Z.
		_model.rotation.y = PI
		if _right == null and skeleton.find_bone("HandAnchorR") >= 0:
			_right = _bone_anchor(skeleton, "HandAnchorR")
		if _left == null and skeleton.find_bone("HandAnchorL") >= 0:
			_left = _bone_anchor(skeleton, "HandAnchorL")
		for part_name: String in ["Body_Torso", "Body_Arms", "Body_Legs"]:
			var under := _model.find_child(part_name, true, false) as Node3D
			if under != null:
				_under_suit_parts.append(under)
	_animation = _model.find_child("*", true, false) as AnimationPlayer
	for node: Node in _model.find_children("*", "AnimationPlayer", true, false):
		_animation = node as AnimationPlayer
		break
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		_parts.append(node as MeshInstance3D)
		if node.name.begins_with("Suit") or node.name == &"Pack":
			_suit_parts.append(node as Node3D)
	if _animation != null:
		for clip: StringName in LOOPING:
			if _animation.has_animation(clip):
				_animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	set_first_person(_first_person)
	set_suit(_suited)
	set_crew_identity(_identity)
	_state = &""
	play(&"idle")


func _bone_anchor(skeleton: Skeleton3D, bone: String) -> Node3D:
	var anchor := BoneAttachment3D.new()
	anchor.name = bone
	skeleton.add_child(anchor)
	anchor.bone_name = bone
	return anchor

## Hides only the head and helmet from the first-person camera.
func set_first_person(on: bool) -> void:
	_first_person = on
	_apply_layers()

## Applies room-light layers while preserving first-person head exclusion.
func set_zone_layers(mask: int) -> void:
	_zone_mask = mask
	_apply_layers()

## Shows helmet, pack and suit overlays without duplicating limbs.
func set_suit(on: bool) -> void:
	_suited = on
	if _helmet != null:
		_helmet.visible = on
	for part: Node3D in _suit_parts:
		part.visible = on
	for part: Node3D in _under_suit_parts:
		part.visible = not on

## Selects a restrained shoulder patch and chest stripe colour for crew member 0..3.
## (Not called set_identity: Node3D already has a method of that name that resets the transform.)
func set_crew_identity(index: int = 0) -> void:
	_identity = clampi(index, 0, 3)
	var colors: Array[Color] = [Color("b96045"), Color("47849c"), Color("c0a34c"), Color("788e65")]
	_patch_material.albedo_color = colors[_identity]
	for part: MeshInstance3D in _parts:
		if part.name == &"ShoulderPatch" or part.name == &"ChestStripe":
			part.material_override = _patch_material
		elif part.mesh != null:
			# rigged model: the patch and stripe are the surfaces that use the material called Mat_Ident
			for surface: int in part.mesh.get_surface_count():
				var material := part.mesh.surface_get_material(surface)
				if material != null and material.resource_name.begins_with("Mat_Ident"):
					part.set_surface_override_material(surface, _patch_material)

## Returns a hand attachment point, right by default.
func hand_anchor(right: bool = true) -> Node3D:
	return _right if right else _left

## Plays a clip now and holds it for `seconds`; movement states asked for meanwhile are ignored.
## Used for short actions that are not a way of moving: landing, using a panel, the suit check.
## A rigged model without that clip skips it entirely (no hold), so the current pose is not frozen on a
## clip that does not exist. The procedural stand-in has a pose for every state and always holds.
func play_once(state: StringName, seconds: float) -> void:
	if not has_clip(state):
		return
	_held_until_msec = 0
	play(state)
	_held_until_msec = Time.get_ticks_msec() + int(seconds * 1000.0)

## True when this body can show `state`: the rig has that clip, or the procedural stand-in is in use.
func has_clip(state: StringName) -> bool:
	return _animation == null or _animation.has_animation(state)

## Length in seconds of the rig's clip `state`, or `fallback` when there is no rig or no such clip.
func clip_length(state: StringName, fallback: float) -> float:
	if _animation != null and _animation.has_animation(state):
		var length := _animation.get_animation(state).length
		if length > 0.0:
			return length
	return fallback

## Ends a play_once() hold early, so the next play() takes effect at once.
func clear_hold() -> void:
	_held_until_msec = 0

## Plays a named animation or its procedural placeholder equivalent.
func play(state: StringName, speed: float = 1.0) -> void:
	if Time.get_ticks_msec() < _held_until_msec:
		return
	if _animation != null and _animation.has_animation(state):
		if state != _state or not _animation.is_playing():
			_animation.play(state, 0.15)      # short blend so changes of gait do not snap
		_animation.speed_scale = speed     # updated every call so the walk follows the ground speed
	var changed := state != _state
	_state = state
	if changed:
		state_changed.emit(state)
	_speed = speed

func _process(delta: float) -> void:
	_time += delta * _speed
	if _limbs.is_empty():
		return
	for limb: Node3D in _limbs:
		limb.rotation.x = 0.0
	var swing := sin(_time * (10.0 if _state == &"sprint" else 7.0))
	match _state:
		&"walk", &"sprint":
			var amplitude := 0.65 if _state == &"sprint" else 0.35
			for i: int in _limbs.size():
				_limbs[i].rotation.x = swing * amplitude * (1.0 if i % 2 == 0 else -1.0)
		&"jump_start":
			# crouched push-off: arms swung back, knees bent
			_limbs[0].rotation.x = 0.45
			_limbs[1].rotation.x = 0.45
			_limbs[2].rotation.x = -0.35
			_limbs[3].rotation.x = -0.35
		&"jump":
			_limbs[0].rotation.x = -0.5
			_limbs[1].rotation.x = -0.5
		&"land":
			_limbs[2].rotation.x = 0.2
			_limbs[3].rotation.x = 0.2
		&"carry", &"use", &"suit":
			_limbs[0].rotation.x = -1.1
			_limbs[1].rotation.x = -0.9 if _state != &"use" else swing * 0.2
		&"seated":
			_limbs[2].rotation.x = -PI / 2.0
			_limbs[3].rotation.x = -PI / 2.0
		&"idle":
			_limbs[0].rotation.x = sin(_time * 1.5) * 0.025

## In first person the head and helmet are drawn "shadows only": the player's own camera does not see them,
## but they still cast a shadow, so the body's shadow keeps its head. (Moving them to a layer the camera skips
## also took them out of every light's shadow casters: the shadow was headless.)
func _apply_layers() -> void:
	for part: MeshInstance3D in _parts:
		var hidden: bool = part == _head or part == _helmet
		if _head != null and _head.is_ancestor_of(part):
			hidden = true
		if _helmet != null and _helmet.is_ancestor_of(part):
			hidden = true
		part.layers = _zone_mask
		if hidden and _first_person:
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		else:
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _build_standin() -> void:
	_model = Node3D.new()
	_model.name = "StandIn"
	add_child(_model)
	_box("Torso", _model, Vector3(0, 1.15, 0), Vector3(0.48, 0.55, 0.26))
	_head = _capsule("Head", _model, Vector3(0, 1.63, 0), 0.14, 0.34)
	_helmet = _capsule("Helmet", _model, Vector3(0, 1.63, 0), 0.17, 0.36)
	_suit_parts.append(_box("Pack", _model, Vector3(0, 1.2, 0.23), Vector3(0.34, 0.42, 0.18)))
	_suit_parts.append(_box("SuitChest", _model, Vector3(0, 1.15, -0.145), Vector3(0.38, 0.35, 0.04)))
	_box("ShoulderPatch", _model, Vector3(0.25, 1.38, 0), Vector3(0.025, 0.11, 0.12)).material_override = _patch_material
	_box("ChestStripe", _model, Vector3(0, 1.3, -0.175), Vector3(0.3, 0.035, 0.02)).material_override = _patch_material
	for side: int in [1, -1]:
		var suffix := "R" if side == 1 else "L"
		var shoulder := Node3D.new()
		shoulder.name = "Shoulder" + suffix
		shoulder.position = Vector3(side * 0.32, 1.4, 0)
		_model.add_child(shoulder)
		_limbs.append(shoulder)
		_capsule("Arm" + suffix, shoulder, Vector3(0, -0.24, 0), 0.075, 0.48)
		_box("Hand" + suffix, shoulder, Vector3(0, -0.52, 0), Vector3(0.12, 0.15, 0.12))
		var anchor := Node3D.new()
		anchor.name = "HandAnchor" + suffix
		anchor.position = Vector3(0, -0.56, -0.16)
		shoulder.add_child(anchor)
		if side == 1:
			_right = anchor
		else:
			_left = anchor
	for side: int in [1, -1]:
		var suffix := "R" if side == 1 else "L"
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.14, 0.9, 0)
		_model.add_child(hip)
		_limbs.append(hip)
		_capsule("Leg" + suffix, hip, Vector3(0, -0.35, 0), 0.095, 0.7)
		_box("Boot" + suffix, hip, Vector3(0, -0.8, -0.045), Vector3(0.2, 0.2, 0.3))
	set_first_person(true)
	set_suit(false)
	set_crew_identity(0)

func _box(part_name: String, parent: Node3D, at: Vector3, size: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _part(part_name, parent, at, mesh)

func _capsule(part_name: String, parent: Node3D, at: Vector3, radius: float, height: float) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	return _part(part_name, parent, at, mesh)

func _part(part_name: String, parent: Node3D, at: Vector3, mesh: Mesh) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = at
	parent.add_child(part)
	_parts.append(part)
	return part
