class_name CrewPortrait
extends Control
## A portrait of one crew member.
## With the rigged astronaut available it renders a head-and-shoulders view of a PlayerVisual once, in a small
## SubViewport of its own (own world, own camera and lights). Without it, or when `prefer_rig` is false, it draws a
## badge: a circle in the crew accent colour with the crew symbol (CrewLooks, as on the suit and name tag).

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
## Crew colours, hair, skin and height come from CrewLooks (the same table the 3D bodies use).

## True: use the rigged 3D portrait when the astronaut model exists. False: always draw the badge.
var prefer_rig := true
## The crew member shown.
var character: CharacterState
## Crew index 0..3 (the look shown when the character's specialty is not one of CrewLooks').
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


## The crew member's identity mark (CrewLooks glyph: ▲ ✚ ● ◆), as on their suit and name tag.
static func crew_glyph(specialty: StringName) -> String:
	var i := CrewLooks.index_of(specialty)
	return CrewLooks.glyph(i) if i >= 0 else "●"


static func specialty_color(specialty: StringName) -> Color:
	var i := CrewLooks.index_of(specialty)
	return CrewLooks.accent(i) if i >= 0 else Color(0.5, 0.5, 0.5)


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
	var look := CrewLooks.index_of(character.specialty) if character != null else -1
	_visual.set_crew_identity(look if look >= 0 else index)
	_visual.set_first_person(false)
	if character != null:
		_visual.set_suit(character.suit_on)
	# head and shoulders, seen from the front (the body faces -Z)
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = 30.0
	var tall := float(CrewLooks.look(_visual.crew_identity()).height)   # frame the head at any crew height
	var eye := Vector3(0.0, 1.5 * tall, -1.6)
	var aim := Vector3(0.0, 1.42 * tall, 0.0)
	camera.transform = Transform3D(Basis.looking_at(aim - eye, Vector3.UP), eye)
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
	# The crew mark (CrewLooks symbol) drawn as a shape, dark on the accent disc: every mark the same size, centred,
	# readable on yellow as well as on blue (font glyphs differ in size and sit on the text baseline).
	draw_crew_mark(self, CrewLooks.index_of(character.specialty), centre, radius * 0.55, MARK_COLOR)


## Colour of the crew mark on the badge disc (the suit's dark backing plate).
const MARK_COLOR := Color("1a1a1f")


## Draws crew `index`'s mark (triangle, plus, circle, diamond) on `canvas`, fitting a circle of `r` around `centre`.
static func draw_crew_mark(canvas: CanvasItem, index: int, centre: Vector2, r: float, colour: Color) -> void:
	match String(CrewLooks.look(index).symbol) if index >= 0 else "":
		"Triangle":
			canvas.draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -r), centre + Vector2(r * 0.95, r * 0.7),
				centre + Vector2(-r * 0.95, r * 0.7)]), colour)
		"Plus":
			var w := r * 0.36
			canvas.draw_rect(Rect2(centre - Vector2(w, r * 0.9), Vector2(w * 2.0, r * 1.8)), colour)
			canvas.draw_rect(Rect2(centre - Vector2(r * 0.9, w), Vector2(r * 1.8, w * 2.0)), colour)
		"Diamond":
			canvas.draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -r), centre + Vector2(r * 0.75, 0),
				centre + Vector2(0, r), centre + Vector2(-r * 0.75, 0)]), colour)
		_:
			canvas.draw_circle(centre, r * 0.75, colour)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
