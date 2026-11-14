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
const WALK_CLIP_SPEED: float = 2.0
const SPRINT_CLIP_SPEED: float = 4.2
const LOOPING: Array[StringName] = [&"idle", &"walk", &"sprint", &"carry", &"seated"]
## "jump" is a non-looping rise-apex-fall arc whose time the controller drives from vertical velocity (set_jump_phase).
const NON_LOOPING: Array[StringName] = [&"jump", &"jump_start", &"land"]
## Locomotion clips play between these speed scales; slower than the minimum reads as slow motion.
const MIN_CLIP_SCALE: float = 0.75
const MAX_CLIP_SCALE: float = 1.5
## Switching between these starts the new clip at the same normalised phase, so the feet keep their rhythm.
const PHASE_SYNC: Array[StringName] = [&"walk", &"sprint"]
## Normalised time of a heel strike in each locomotion clip; a running landing enters the gait here instead of at 0.
## Measured on the current astronaut.glb with tools/godot/measure_contacts.gd (foot furthest forward):
## walk 0.25 / 0.75, sprint 0.20 / 0.70. Re-measure after re-exporting either clip.
const CONTACT_PHASE: Dictionary = {&"walk": 0.25, &"sprint": 0.20}
## States that may cut a play_once() hold short once its interruptible_after time has passed.
const INTERRUPTERS: Array[StringName] = [&"walk", &"sprint", &"carry"]
## Emitted whenever the shown state changes (play() or play_once()); tests use it to follow the jump phases.
signal state_changed(state: StringName)
var _limbs: Array[Node3D] = []
var _patch_material := StandardMaterial3D.new()
## Mat_IdentDark surfaces: the accent darkened (CrewLooks.IDENT_DARK_AMOUNT).
var _patch_dark_material := StandardMaterial3D.new()
## Hair_* (unsuited) and HairIn_* (under the helmet) meshes; _apply_look_parts shows this crew member's.
var _hair_parts: Array[MeshInstance3D] = []
## Ident_Symbol_* and Ident_Band_* suit meshes; only this crew member's symbol and band, only while suited.
var _ident_parts: Array[MeshInstance3D] = []
## Imported Mat_Skin / Mat_Hair -> this body's own copy (other bodies share the imported one: never edit it).
var _look_materials := {}
## This body's Mat_Skin copies: they glow faintly while the helmet is on, so faces read through the visor.
var _skin_copies: Array[BaseMaterial3D] = []
## Name over the head (other crew only; see set_name_tag): a node turned to the camera each frame, holding the
## symbol (accent colour) and the word (near-white).
var _name_tag: Node3D
var _tag_symbol: Label3D
var _tag_word: Label3D
## Symbol and word widths in tag units, and whether only the symbol is shown.
var _tag_symbol_w := 0.0
var _tag_word_w := 0.0
var _tag_collapsed := false
## Every body that has a name tag, for the overlap check.
static var _tagged: Array[PlayerVisual] = []
## Each crew index raises its tag this much more, so tags of crew standing together do not sit on one line.
const NAME_TAG_STAGGER_M := 0.12
## A tag collapses to its symbol when a nearer tag is within this many tag-widths of it on screen.
const NAME_TAG_OVERLAP := 1.2
## ...and within this many lines of text above or below it.
const NAME_TAG_OVERLAP_LINES := 2.5
## Height of the name tag above the feet for a model at scale 1 (head top is about 1.8 m, helmet top 1.86 m).
const NAME_TAG_HEIGHT_M := 2.05
## Extra height over a helmet.
const NAME_TAG_SUITED_LIFT_M := 0.15
## Text height on a 1080-pixel-tall screen, kept between NAME_TAG_NEAR_M and NAME_TAG_FAR_M from the camera.
const NAME_TAG_PIXELS := 22.0
const NAME_TAG_NEAR_M := 4.0
const NAME_TAG_FAR_M := 25.0
## Fully faded out beyond NAME_TAG_FADE_END_M (from NAME_TAG_FAR_M + 2) and closer than NAME_TAG_FADE_NEAR_M (from +1 m).
const NAME_TAG_FADE_END_M := 30.0
const NAME_TAG_FADE_NEAR_M := 2.0
const NAME_TAG_TEXT := Color("f4f1ea")
## Font size the tag labels are rasterised at; the node's scale sets their size in the world.
const NAME_TAG_FONT_SIZE := 64
## Emission energy of the skin while suited (a faint "helmet light" on the face).
const SUITED_FACE_GLOW := 0.18
var _first_person: bool = true
var _camera_obstructed := false
var _suited: bool = false
var _zone_mask: int = 1
var _identity: int = 0
var _state: StringName = &"idle"
var _speed: float = 1.0
var _time: float = 0.0
## play_once() hold, counted in the same process time the AnimationPlayer advances by (not wall clock: under a
## slow frame the old millisecond hold ran out before the clip had advanced, so jump_start never showed).
var _hold_left: float = 0.0
var _hold_elapsed: float = 0.0
var _interrupt_after: float = -1.0
## Last fraction (0 rise .. 0.5 apex .. 1 fall) handed to set_jump_phase().
var _jump_fraction: float = 0.0
## Procedural hip dip (running landings, which skip the standing land clip).
var _dip_depth: float = 0.0
var _dip_seconds: float = 0.0
var _dip_time: float = 0.0
var _model_base_y: float = 0.0

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
	_hair_parts.clear()
	_ident_parts.clear()
	_look_materials.clear()
	_skin_copies.clear()
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
		elif node.name.begins_with("Hair_") or node.name.begins_with("HairIn_"):
			_hair_parts.append(node as MeshInstance3D)
		elif node.name.begins_with("Ident_Symbol_") or node.name.begins_with("Ident_Band_"):
			_ident_parts.append(node as MeshInstance3D)
	_model_base_y = _model.position.y
	_finish_suit_materials()
	if _animation != null:
		for clip: StringName in LOOPING:
			if _animation.has_animation(clip):
				_animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		for clip: StringName in NON_LOOPING:
			if _animation.has_animation(clip):
				_animation.get_animation(clip).loop_mode = Animation.LOOP_NONE
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

## The third-person arm can retract into the body against a wall: preserve shadows without drawing its inside.
func set_camera_obstructed(on: bool) -> void:
	if _camera_obstructed != on:
		_camera_obstructed = on
		_apply_layers()

func _finish_suit_materials() -> void:
	for part: MeshInstance3D in _parts:
		if part.mesh == null:
			continue
		for surface in part.mesh.get_surface_count():
			var original := part.mesh.surface_get_material(surface) as BaseMaterial3D
			if original == null or not (original.resource_name.begins_with("Mat_Suit") or original.resource_name == "Mat_Visor"):
				continue
			var copy := original.duplicate() as BaseMaterial3D
			copy.metallic = 0.0
			copy.metallic_specular = 0.0 if original.resource_name == "Mat_Visor" else 0.1
			copy.clearcoat_enabled = false
			copy.roughness = maxf(copy.roughness, 0.65 if original.resource_name == "Mat_Visor" else 0.85)
			part.set_surface_override_material(surface, copy)

## Applies room-light layers while preserving first-person head exclusion.
func set_zone_layers(mask: int) -> void:
	_zone_mask = mask
	_apply_layers()

## Render layers last set by set_zone_layers().
func zone_layers() -> int:
	return _zone_mask

## Shows helmet, pack and suit overlays without duplicating limbs.
func set_suit(on: bool) -> void:
	_suited = on
	if _helmet != null:
		_helmet.visible = on
	for part: Node3D in _suit_parts:
		part.visible = on
	for part: Node3D in _under_suit_parts:
		part.visible = not on
	_apply_look_parts()
	_apply_face_glow()
	_update_name_tag()

## Dresses the body as crew member 0..3 from CrewLooks: hair style and colour, skin colour, the "Feminine" blend
## shape, accent surfaces (Mat_Ident, Mat_IdentDark), suit symbol and band, and height. Whatever the model lacks is
## skipped. (Not called set_identity: Node3D already has a method of that name that resets the transform.)
func set_crew_identity(index: int = 0) -> void:
	_identity = clampi(index, 0, 3)
	var look := CrewLooks.look(_identity)
	_patch_material.albedo_color = look.accent
	_patch_material.roughness = 1.0
	_patch_material.emission_enabled = true
	_patch_material.emission = look.accent
	_patch_material.emission_energy_multiplier = CrewLooks.IDENT_EMISSION
	_patch_dark_material.albedo_color = CrewLooks.accent_dark(_identity)
	_patch_dark_material.roughness = 1.0
	var feminine := float(look.feminine)
	for part: MeshInstance3D in _parts:
		if part.name == &"ShoulderPatch" or part.name == &"ChestStripe":
			part.material_override = _patch_material
		elif part.mesh != null:
			# rigged model: surfaces are recognised by the name of their imported material
			for surface: int in part.mesh.get_surface_count():
				var material := part.mesh.surface_get_material(surface)
				if material == null:
					continue
				var material_name := material.resource_name
				if material_name.begins_with("Mat_IdentDark"):
					part.set_surface_override_material(surface, _patch_dark_material)
				elif material_name.begins_with("Mat_Ident"):
					part.set_surface_override_material(surface, _patch_material)
				elif material_name.begins_with("Mat_Skin"):
					part.set_surface_override_material(surface, _look_copy(material, look.skin_color, true))
				elif material_name.begins_with("Mat_Hair"):
					part.set_surface_override_material(surface, _look_copy(material, look.hair_color, false))
			var shape := part.find_blend_shape_by_name(&"Feminine")
			if shape >= 0:
				part.set_blend_shape_value(shape, feminine)
	# The model's origin is between its feet, so a uniform scale keeps them on the floor.
	_model.scale = Vector3.ONE * float(look.height)
	_apply_look_parts()
	_apply_face_glow()
	_update_name_tag()

## Crew index 0..3 last set by set_crew_identity().
func crew_identity() -> int:
	return _identity

## This body's own copy of an imported material, recoloured.
func _look_copy(material: Material, color: Color, skin: bool) -> Material:
	var copy := _look_materials.get(material) as Material
	if copy == null:
		copy = material.duplicate() as Material
		_look_materials[material] = copy
		if skin and copy is BaseMaterial3D:
			_skin_copies.append(copy as BaseMaterial3D)
	if copy is BaseMaterial3D:
		(copy as BaseMaterial3D).albedo_color = color
	return copy

## Hair: this crew member's Hair_* unsuited, their HairIn_* (and beard) under the helmet. Suit symbol and band: this
## crew member's Ident_Symbol_* / Ident_Band_*, only while the suit is on.
func _apply_look_parts() -> void:
	var look := CrewLooks.look(_identity)
	var wanted: Array = look.hair_suited if _suited else look.hair
	for hair: MeshInstance3D in _hair_parts:
		hair.visible = wanted.has(hair.name)
	var symbol := "Ident_Symbol_" + String(look.symbol)
	var band := "Ident_Band_" + String(look.band)
	for part: MeshInstance3D in _ident_parts:
		part.visible = _suited and (part.name == symbol or part.name == band)

## Inside the helmet the face has no light of its own and goes dark in dim rooms: a faint skin glow stands in for a
## helmet light while suited.
func _apply_face_glow() -> void:
	for skin: BaseMaterial3D in _skin_copies:
		skin.emission_enabled = _suited
		skin.emission = skin.albedo_color
		skin.emission_energy_multiplier = SUITED_FACE_GLOW

## Floats `text` over the head: the crew symbol in the accent colour, then the word in near-white, both outlined.
## "" removes it. For other crew only: the game never gives the local player's own body a tag. The tag keeps about
## NAME_TAG_PIXELS of text height between NAME_TAG_NEAR_M and NAME_TAG_FAR_M, fades out beyond NAME_TAG_FADE_END_M
## and very close up, and walls hide it (depth tested).
func set_name_tag(text: String) -> void:
	if text == "":
		if _name_tag != null:
			_name_tag.queue_free()
			_name_tag = null
			_tag_symbol = null
			_tag_word = null
			_tagged.erase(self)
		return
	if _name_tag == null:
		_name_tag = Node3D.new()
		_name_tag.name = "NameTag"
		add_child(_name_tag)
		_tag_symbol = _tag_label("Symbol", HORIZONTAL_ALIGNMENT_RIGHT)
		_tag_word = _tag_label("Word", HORIZONTAL_ALIGNMENT_LEFT)
		if not _tagged.has(self):
			_tagged.append(self)
	_tag_word.text = text
	_update_name_tag()

func _tag_label(label_name: String, align: HorizontalAlignment) -> Label3D:
	var label := Label3D.new()
	label.name = label_name
	label.font_size = NAME_TAG_FONT_SIZE
	label.pixel_size = 1.0 / NAME_TAG_FONT_SIZE      # one metre per line at scale 1; _place_name_tag scales the node
	label.outline_size = 14
	label.outline_modulate = Color(0.05, 0.04, 0.04, 0.9)
	label.horizontal_alignment = align
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_name_tag.add_child(label)
	return label

## The name tag node (children Symbol and Word), or null when there is none.
func name_tag() -> Node3D:
	return _name_tag

## The name tag as one string ("▲ Electrical"), or "" when there is none.
func name_tag_text() -> String:
	return "%s %s" % [_tag_symbol.text, _tag_word.text] if _name_tag != null else ""

func _update_name_tag() -> void:
	if _name_tag == null:
		return
	_tag_symbol.text = CrewLooks.glyph(_identity)
	# Glyphs differ in size within a font (● is far smaller than ▲): each is scaled to the height of the capitals.
	_tag_symbol.font_size = roundi(NAME_TAG_FONT_SIZE * CrewLooks.glyph_scale(_identity))
	_tag_symbol.modulate = CrewLooks.accent(_identity)
	_tag_word.modulate = NAME_TAG_TEXT
	var font := _tag_word.font if _tag_word.font != null else ThemeDB.fallback_font
	_tag_word_w = font.get_string_size(_tag_word.text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_TAG_FONT_SIZE).x * _tag_word.pixel_size
	_tag_symbol_w = font.get_string_size(_tag_symbol.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _tag_symbol.font_size).x * _tag_symbol.pixel_size
	_lay_out_tag(false)
	var lift := NAME_TAG_SUITED_LIFT_M if _suited else 0.0
	_name_tag.position = Vector3(0.0, NAME_TAG_HEIGHT_M * float(CrewLooks.look(_identity).height) + lift + NAME_TAG_STAGGER_M * _identity, 0.0)

## Centres the symbol and word side by side, or the symbol alone when `collapsed`.
func _lay_out_tag(collapsed: bool) -> void:
	_tag_collapsed = collapsed
	_tag_word.visible = not collapsed
	var gap := 0.25
	var total := _tag_symbol_w if collapsed else _tag_symbol_w + gap + _tag_word_w
	var left := -total / 2.0
	_tag_symbol.position = Vector3(left + _tag_symbol_w, 0.0, 0.0)
	_tag_word.position = Vector3(left + _tag_symbol_w + gap, 0.0, 0.0)

## Tag width in tag units (one unit = one line of text), symbol and word.
func _tag_width() -> float:
	return _tag_symbol_w + 0.25 + _tag_word_w

## True when the name tag shows only its symbol (another, nearer tag is next to it on screen).
func name_tag_collapsed() -> bool:
	return _tag_collapsed

## Faces the tag to `camera`, sizes it to about NAME_TAG_PIXELS on screen, fades it by distance, and collapses it to
## its symbol when a nearer crew member's tag sits within NAME_TAG_OVERLAP tag-widths of it on screen.
func _place_name_tag(camera: Camera3D) -> void:
	var to_camera := camera.global_position - _name_tag.global_position
	var distance := to_camera.length()
	var height := _tag_height_at(camera, distance)
	_name_tag.global_basis = camera.global_basis.orthonormalized().scaled(Vector3.ONE * height)
	var alpha := 1.0
	if distance > NAME_TAG_FAR_M + 2.0:
		alpha = clampf((NAME_TAG_FADE_END_M - distance) / (NAME_TAG_FADE_END_M - NAME_TAG_FAR_M - 2.0), 0.0, 1.0)
	elif distance < NAME_TAG_FADE_NEAR_M + 1.0:
		alpha = clampf(distance - NAME_TAG_FADE_NEAR_M, 0.0, 1.0)
	_name_tag.visible = alpha > 0.0
	_tag_symbol.modulate.a = alpha
	_tag_word.modulate.a = alpha
	_tag_symbol.outline_modulate.a = 0.9 * alpha
	_tag_word.outline_modulate.a = 0.9 * alpha
	_lay_out_tag(_crowded(camera, distance))

## World height of one line of tag text at `distance` (NAME_TAG_PIXELS on a 1080-pixel-tall view, clamped range).
func _tag_height_at(camera: Camera3D, distance: float) -> float:
	var clamped := clampf(distance, NAME_TAG_NEAR_M, NAME_TAG_FAR_M)
	return NAME_TAG_PIXELS / 1080.0 * 2.0 * clamped * tan(deg_to_rad(camera.fov) * 0.5)

## True when a nearer crew member's tag is close to this one on screen (within NAME_TAG_OVERLAP tag-widths across and
## NAME_TAG_OVERLAP_LINES lines of text up or down: the stagger alone separates them by less than that).
func _crowded(camera: Camera3D, distance: float) -> bool:
	if not _name_tag.visible or camera.is_position_behind(_name_tag.global_position):
		return false
	var mine := camera.unproject_position(_name_tag.global_position)
	var view_h := camera.get_viewport().get_visible_rect().size.y
	var px_per_m := view_h / (2.0 * distance * tan(deg_to_rad(camera.fov) * 0.5))
	var line_px := _tag_height_at(camera, distance) * px_per_m
	for other: PlayerVisual in _tagged:
		if other == self or other._name_tag == null or not other.is_visible_in_tree() or not other._name_tag.visible:
			continue
		var at := other._name_tag.global_position
		var other_distance := camera.global_position.distance_to(at)
		if other_distance > distance or (is_equal_approx(other_distance, distance) and other.get_instance_id() > get_instance_id()):
			continue
		if camera.is_position_behind(at):
			continue
		var theirs := camera.unproject_position(at)
		var other_px_per_m := view_h / (2.0 * other_distance * tan(deg_to_rad(camera.fov) * 0.5))
		var width_px := maxf(_tag_width() * line_px, other._tag_width() * other._tag_height_at(camera, other_distance) * other_px_per_m)
		if absf(theirs.x - mine.x) < NAME_TAG_OVERLAP * width_px and absf(theirs.y - mine.y) < NAME_TAG_OVERLAP_LINES * line_px:
			return true
	return false
## Returns a hand attachment point, right by default.
func hand_anchor(right: bool = true) -> Node3D:
	return _right if right else _left

## Plays a clip now and holds it for `seconds`; movement states asked for meanwhile are ignored.
## Used for short actions that are not a way of moving: landing, using a panel, the suit check.
## A rigged model without that clip skips it entirely (no hold), so the current pose is not frozen on a
## clip that does not exist. The procedural stand-in has a pose for every state and always holds.
## `interruptible_after` >= 0 lets walk, sprint or carry take over once that much of the hold has passed
## (the landing: walk input may cut it after 0.2 s, but idle waits for the whole clip).
func play_once(state: StringName, seconds: float, interruptible_after: float = -1.0) -> void:
	if not has_clip(state):
		return
	_hold_left = 0.0
	play(state)
	_hold_left = seconds
	_hold_elapsed = 0.0
	_interrupt_after = interruptible_after

## True while a play_once() hold is running.
func is_holding() -> bool:
	return _hold_left > 0.0

## Cross-fade length for a change of clip, per the animation review (fable_verdict_1, "Game side" 3).
static func blend_time(from: StringName, to: StringName) -> float:
	if from == &"":
		return 0.0                                      # first clip on a fresh model: nothing to blend from
	match to:
		&"jump_start":
			return 0.07
		&"jump":
			return 0.1 if from == &"jump_start" else 0.15   # 0.15: walking off a ledge into the apex pose
		&"land":
			return 0.06
		&"idle":
			return 0.2
		&"walk":
			return 0.25 if from == &"sprint" else (0.15 if from == &"jump" else 0.2)
		&"sprint":
			return 0.15 if from == &"jump" else 0.25         # 0.15: running landing, land skipped
	return 0.2

## Poses the non-looping "jump" arc: 0 = take-off, 0.5 = apex, 1 = fall (held). Only acts while "jump" is shown.
func set_jump_phase(fraction: float) -> void:
	_jump_fraction = clampf(fraction, 0.0, 1.0)
	if _state != &"jump" or _animation == null or _animation.assigned_animation != "jump":
		return
	var length := _animation.get_animation(&"jump").length
	if not _animation.is_playing():
		# A long frame ran the clip past its end and the player stopped (current_animation went blank). Resume it
		# so the fall pose stays on until the locomotion blend starts at touchdown.
		_animation.play(&"jump", 0.0)
	# Stop a frame short of the end: the next process step's small advance should not run past the held fall pose.
	_animation.seek(minf(_jump_fraction * length, maxf(length - 0.05, 0.0)), true)
	_animation.speed_scale = 1.0

## A quick procedural hip dip (metres, seconds), used for running landings instead of the standing land clip.
func dip(depth: float, seconds: float) -> void:
	_dip_depth = depth
	_dip_seconds = maxf(seconds, 0.01)
	_dip_time = 0.0

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
	_hold_left = 0.0

## Plays a named animation or its procedural placeholder equivalent.
func play(state: StringName, speed: float = 1.0) -> void:
	if _hold_left > 0.0:
		if not (state in INTERRUPTERS and _interrupt_after >= 0.0 and _hold_elapsed >= _interrupt_after):
			return
		_hold_left = 0.0
	if _animation != null and _animation.has_animation(state):
		if state != _state or _animation.assigned_animation != String(state):
			var phase := -1.0
			if state in PHASE_SYNC and _state in PHASE_SYNC and _animation.assigned_animation == String(_state) and _animation.current_animation_length > 0.0:
				phase = fposmod(_animation.current_animation_position / _animation.current_animation_length, 1.0)
			elif state in PHASE_SYNC and _state == &"jump":
				phase = float(CONTACT_PHASE.get(state, 0.0))   # running landing: come down on a heel strike
			_animation.play(state, blend_time(_state, state))
			if phase >= 0.0:
				_animation.seek(phase * _animation.get_animation(state).length)
			# Consume Godot's start step now: otherwise the first drawn frame after play() does not advance the clip
			# (measured: one frame at t=0 per transition; 0.13 s of a slow capture).
			_animation.advance(0.0)
		elif not _animation.is_playing() and _animation.get_animation(state).loop_mode != Animation.LOOP_NONE:
			_animation.play(state)
			_animation.advance(0.0)
		# A finished non-looping clip (jump, land) is left on its last frame: re-calling play() used to restart it
		# from 0 every frame, because a finished clip reports not playing.
		_animation.speed_scale = speed     # updated every call so the walk follows the ground speed
	var changed := state != _state
	_state = state
	if changed:
		state_changed.emit(state)
	_speed = speed

func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		_tagged.erase(self)
	elif what == NOTIFICATION_ENTER_TREE and _name_tag != null and not _tagged.has(self):
		_tagged.append(self)

func _process(delta: float) -> void:
	if _name_tag != null and is_inside_tree():
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			_place_name_tag(camera)
	_time += delta * _speed
	if _hold_left > 0.0:
		_hold_left -= delta
		_hold_elapsed += delta
	if _dip_depth > 0.0:
		_dip_time += delta
		var k := _dip_time / _dip_seconds
		_model.position.y = _model_base_y - _dip_depth * sin(PI * clampf(k, 0.0, 1.0))
		if k >= 1.0:
			_dip_depth = 0.0
			_model.position.y = _model_base_y
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
		# Identity meshes include the helmet/collar band as well as sleeve badges. In a jump the helmet band
		# crosses the eye even though Suit_Helmet itself is hidden, producing the reported yellow arc.
		var hidden: bool = part == _head or part == _helmet or _hair_parts.has(part) or _ident_parts.has(part)
		if _head != null and _head.is_ancestor_of(part):
			hidden = true
		if _helmet != null and _helmet.is_ancestor_of(part):
			hidden = true
		part.layers = _zone_mask
		if (hidden and _first_person) or _camera_obstructed:
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
