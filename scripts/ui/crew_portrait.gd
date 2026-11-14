class_name CrewPortrait
extends Control
## A portrait of one crew member.
## With the rigged astronaut available it renders a head-and-shoulders view of a PlayerVisual once, in a small
## SubViewport of its own (own world, own camera and lights). Without it, or when `prefer_rig` is false, it draws a
## badge: a circle in the specialist colour with the specialist symbol.

## Pixel size of the rendered portrait.
const PORTRAIT_SIZE := Vector2i(160, 200)

## Specialist symbol, words and colour, keyed by CharacterState.specialty.
const SYMBOLS := {
	&"electrical_comms": "⚡",
	&"medical_life_support": "✚",
	&"biology_food": "❀",
	&"field_engineering_geology": "⛏",
}
const WORDS := {
	&"electrical_comms": "Electrical and comms",
	&"medical_life_support": "Medical and life support",
	&"biology_food": "Biology and food",
	&"field_engineering_geology": "Field engineering and geology",
}
## Same colours as the shoulder patch and chest stripe of each crew member (PlayerVisual.set_crew_identity).
## UiTheme has no crew colours yet; these move there when it does.
const COLORS := {
	&"electrical_comms": Color("b96045"),
	&"medical_life_support": Color("47849c"),
	&"biology_food": Color("c0a34c"),
	&"field_engineering_geology": Color("788e65"),
}

## True: use the rigged 3D portrait when the astronaut model exists. False: always draw the badge.
var prefer_rig := true
## The crew member shown.
var character: CharacterState
## Crew index 0..3 (for the suit patch colour).
var index := 0

var _viewport: SubViewport
var _container: SubViewportContainer
var _visual: PlayerVisual


## Shows `p_character`; `p_index` is the crew index 0..3. Builds the 3D portrait or the badge.
func setup(p_character: CharacterState, p_index: int) -> void:
	character = p_character
	index = p_index
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(PORTRAIT_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clear_rig()
	if prefer_rig and PlayerVisual.rigged_scene() != null:
		_build_rig()
	queue_redraw()


## True when the portrait is the rendered 3D view; false when it is the drawn badge.
func uses_rig() -> bool:
	return _viewport != null


## The SubViewport of the 3D portrait, or null when the badge is drawn.
func viewport() -> SubViewport:
	return _viewport


## The PlayerVisual in the 3D portrait, or null.
func visual() -> PlayerVisual:
	return _visual


## Shows the suit on or off in the 3D portrait and renders it again.
func set_suit(on: bool) -> void:
	if _visual != null:
		_visual.set_suit(on)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Crew ids of a colony in order ("crew_1" first). Sorted as text: StringNames do not sort alphabetically.
static func sorted_crew_ids(state: ColonyState) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in state.characters:
		out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a).naturalnocasecmp_to(String(b)) < 0)
	return out


## Crew index 0..3 of a character (its place in sorted_crew_ids), used for its suit patch colour.
static func crew_index(state: ColonyState, id: StringName) -> int:
	return maxi(0, sorted_crew_ids(state).find(id))


static func specialty_symbol(specialty: StringName) -> String:
	return String(SYMBOLS.get(specialty, "●"))


static func specialty_words(specialty: StringName) -> String:
	return String(WORDS.get(specialty, "Crew member"))


static func specialty_color(specialty: StringName) -> Color:
	return COLORS.get(specialty, Color(0.5, 0.5, 0.5)) as Color


func _build_rig() -> void:
	_container = SubViewportContainer.new()
	_container.name = "Portrait3D"
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.name = "Viewport"
	_viewport.size = PORTRAIT_SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_container.add_child(_viewport)
	_visual = PlayerVisual.new()
	_visual.name = "Body"
	_viewport.add_child(_visual)
	_visual.use_rig_if_available()
	_visual.set_crew_identity(index)
	_visual.set_first_person(false)
	if character != null:
		_visual.set_suit(character.suit_on)
	# head and shoulders, seen from the front (the body faces -Z)
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = 30.0
	var eye := Vector3(0.0, 1.5, -1.6)
	var look := Vector3(0.0, 1.42, 0.0)
	camera.transform = Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)
	camera.current = true
	_viewport.add_child(camera)
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.transform = Transform3D(Basis.looking_at(Vector3(0.4, -0.5, 1.0), Vector3.UP), Vector3.ZERO)
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_energy = 0.4
	fill.transform = Transform3D(Basis.looking_at(Vector3(-0.6, -0.2, 1.0), Vector3.UP), Vector3.ZERO)
	_viewport.add_child(fill)


func _clear_rig() -> void:
	if _container != null:
		remove_child(_container)
		_container.queue_free()
	_container = null
	_viewport = null
	_visual = null


func _draw() -> void:
	if uses_rig() or character == null:
		return
	var radius := minf(size.x, size.y) * 0.45
	var centre := size * 0.5
	draw_circle(centre, radius, specialty_color(character.specialty))
	var font := get_theme_font(&"font", &"Label")
	var font_size := maxi(8, int(radius))
	var text := specialty_symbol(character.specialty)
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var baseline := centre.y + (ascent - descent) * 0.5
	draw_string(font, Vector2(centre.x - radius, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size,
		get_theme_color(&"font_color", &"Label"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
