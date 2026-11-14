class_name BlueprintView
extends Control
## A top-down plan of the colony drawn with draw_* calls: rooms, the dome wall, the pads outside, the stations and
## live markers (you, the other crew, things on the ground, caches). Rooms without power are drawn dim with ✖.
## Plan coordinates are the source map's (Blender) x, y in metres: x to the right (east), y up the screen (north).
## Godot world x, z become plan x = x, y = -z.
## Zoom with the mouse wheel or zoom_by(), pan by dragging; a click on a room emits room_selected.

## The player clicked a zone (room, dome plaza, garden dome or exterior).
signal room_selected(zone: String)

const MANIFEST_PATH := "res://data/colony_manifest.json"
const ZOOM_MIN := 0.5
const ZOOM_MAX := 10.0
## Pixels the mouse must move with the button down before a click becomes a drag.
const DRAG_THRESHOLD := 5.0
## Share of the view the whole plan fills at zoom 1.
const FIT := 0.92
## Plan scale (pixels per metre) above which station names are written next to their symbols.
const NAME_SCALE := 11.0
## A sun tracker whose panel dust is above this share gets the word DUSTY_WORD under its ☀.
const DUSTY_SHARE := 0.3
const DUSTY_WORD := "dusty"

## Letter drawn in each crew member's marker: the first letter of their specialty.
const SPECIALTY_INITIALS := {
	&"electrical_comms": "E",
	&"medical_life_support": "M",
	&"biology_food": "B",
	&"field_engineering_geology": "F",
}
## Marker colour of each specialty, and the colour in words for the legend.
const SPECIALTY_COLOURS := {
	&"electrical_comms": [Color(1.0, 0.82, 0.25), "yellow"],
	&"medical_life_support": [Color(0.96, 0.45, 0.52), "pink"],
	&"biology_food": [Color(0.45, 0.86, 0.45), "green"],
	&"field_engineering_geology": [Color(0.45, 0.66, 1.0), "blue"],
}
## Drawing colours of the plan itself (shapes, not text; text uses the theme's label colour).
const PLAN_COLOURS := {
	"background": Color(0.05, 0.06, 0.08, 0.55),
	"room": Color(0.22, 0.52, 0.56, 0.75),
	"room_dim": Color(0.16, 0.16, 0.18, 0.75),
	"line": Color(0.75, 0.92, 0.95, 0.9),
	"line_dim": Color(0.45, 0.45, 0.48, 0.9),
	"dome": Color(0.95, 0.62, 0.35, 0.9),
	"pad": Color(0.8, 0.75, 0.68, 0.7),
	"selected": Color(1.0, 1.0, 1.0, 1.0),
	"you": Color(1.0, 1.0, 1.0, 1.0),
	"item": Color(0.9, 0.9, 0.82, 1.0),
	"cache": Color(1.0, 0.55, 0.12, 1.0),
	"station": Color(0.98, 0.95, 0.85, 1.0),
	"outline": Color(0.0, 0.0, 0.0, 0.85),
}

static var _layout_cache: Dictionary = {}

var services: GameServices
## 1 = the whole plan fits the view.
var zoom := 1.0
## Offset of the plan in pixels.
var pan := Vector2.ZERO
## Zone last clicked, or "".
var selected_zone := ""
## Filled by every draw: room name -> {"rect": Rect2 (view pixels), "dim": bool}.
var drawn_rooms: Dictionary = {}
## Filled by every draw: every legend symbol that was drawn -> true.
var symbols_used: Dictionary = {}
## Number of times the plan has been drawn.
var draw_count := 0
## Filled by every draw: tracker index -> true if it was marked dusty.
var dusty_trackers: Dictionary = {}

var _rooms: Array = []
var _dome: Dictionary = {}
var _pads: Array = []
var _bounds := Rect2(-50, -50, 100, 100)
var _pressed := false
var _dragging := false
var _press_pos := Vector2.ZERO


## Every symbol the map can draw, with what it means in words: [[symbol, words], ...].
static func legend() -> Array:
	var out: Array = [
		["▭", "A room. Bright means it has power."],
		["✖", "A room with no power. It is drawn dim."],
		["▢", "The room you clicked (thick outline)."],
		["◯", "The dome wall around the plaza, seen from above."],
		["◌", "A pad outside: landing pad, crash site or garden dome."],
		["▲", "You. The point shows the way you face."],
	]
	for sp: StringName in SPECIALTY_INITIALS:
		out.append([String(SPECIALTY_INITIALS[sp]), "Crew member: %s (%s circle)." % [String(StationPanels.SPECIALTY_WORDS[sp]).to_lower(), String(SPECIALTY_COLOURS[sp][1])]])
	out.append(["■", "Something on the ground that you can pick up."])
	out.append(["!", "A cache (orange circle): things left behind when someone was brought back to the hub."])
	for kind: String in StationPanels.SYMBOLS:
		out.append([String(StationPanels.SYMBOLS[kind]), "Station: %s." % StationPanels.name_of(kind).to_lower()])
	out.append([DUSTY_WORD, "Under a sun tracker ☀: its solar panel is more than %d %% covered in dust, so it makes less power." % roundi(DUSTY_SHARE * 100.0)])
	out.append(["↑", "North arrow. The top of the map is north (N)."])
	return out


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var layout := _layout()
	_rooms = layout["rooms"]
	_dome = layout["dome"]
	_pads = layout["pads"]
	_bounds = layout["bounds"]


func setup(p_services: GameServices) -> void:
	services = p_services
	queue_redraw()


# ---------------------------------------------------------------- coordinates

## Pixels per metre at the current size and zoom.
func plan_scale() -> float:
	if size.x <= 1.0 or size.y <= 1.0:
		return 1.0
	return minf(size.x / _bounds.size.x, size.y / _bounds.size.y) * FIT * zoom


## Plan point (Blender x, y in metres) -> view pixel.
func world_to_view(p: Vector2) -> Vector2:
	var c := _bounds.get_center()
	return size * 0.5 + pan + Vector2(p.x - c.x, c.y - p.y) * plan_scale()


## View pixel -> plan point (Blender x, y in metres).
func view_to_world(v: Vector2) -> Vector2:
	var c := _bounds.get_center()
	var d := (v - size * 0.5 - pan) / plan_scale()
	return Vector2(c.x + d.x, c.y - d.y)


## Godot world position -> plan point.
static func godot_to_plan(p: Vector3) -> Vector2:
	return Vector2(p.x, -p.z)


## Where room `room_name` is drawn, in view pixels (empty rect if unknown).
func room_rect(room_name: String) -> Rect2:
	for r: Dictionary in _rooms:
		if String(r.name) == room_name:
			var a := world_to_view(Vector2(float(r.x0), float(r.y1)))
			var b := world_to_view(Vector2(float(r.x1), float(r.y0)))
			return Rect2(a, b - a)
	return Rect2()


## The room records from the map: {name, x0, y0, x1, y1, ...} in plan metres.
func rooms() -> Array:
	return _rooms


## The zone under a view pixel.
func zone_at_view(v: Vector2) -> String:
	var w := view_to_world(v)
	if services != null and services.zones != null:
		return services.zones.zone_at(w.x, w.y)
	for r: Dictionary in _rooms:
		if w.x > float(r.x0) and w.x < float(r.x1) and w.y > float(r.y0) and w.y < float(r.y1):
			return String(r.name)
	return ColonyZones.EXTERIOR


# ---------------------------------------------------------------- zoom and pan

## Zooms by `factor`, keeping the plan point under `around` (view pixels; default the centre) in place.
func zoom_by(factor: float, around := Vector2(-1, -1)) -> void:
	if around.x < 0.0:
		around = size * 0.5
	var w := view_to_world(around)
	zoom = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	pan += around - world_to_view(w)
	queue_redraw()


## Moves the plan so plan point `p` is in the middle of the view.
func centre_on(p: Vector2) -> void:
	pan += size * 0.5 - world_to_view(p)
	queue_redraw()


## Moves the plan so your crew member is in the middle. Returns false if you have none.
func centre_on_me() -> bool:
	if services == null or services.local_character() == null:
		return false
	centre_on(godot_to_plan(services.local_character().position))
	return true


## Selects the zone under a view pixel, as a click does. Returns its name.
func select_at(v: Vector2) -> String:
	selected_zone = zone_at_view(v)
	room_selected.emit(selected_zone)
	queue_redraw()
	return selected_zone


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_by(1.2, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_by(1.0 / 1.2, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_dragging = false
				_press_pos = mb.position
				grab_focus()
			else:
				if _pressed and not _dragging:
					select_at(mb.position)
				_pressed = false
				_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _pressed:
		var mm := event as InputEventMouseMotion
		if not _dragging and mm.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			pan += mm.relative
			queue_redraw()
		accept_event()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		var key := (event as InputEventKey).keycode
		var step := 40.0
		match key:
			KEY_LEFT: pan.x += step
			KEY_RIGHT: pan.x -= step
			KEY_UP: pan.y += step
			KEY_DOWN: pan.y -= step
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: zoom_by(1.2)
			KEY_MINUS, KEY_KP_SUBTRACT: zoom_by(1.0 / 1.2)
			_: return
		queue_redraw()
		accept_event()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_count += 1
	drawn_rooms.clear()
	symbols_used.clear()
	dusty_trackers.clear()
	var font := get_theme_default_font()
	var fs := get_theme_default_font_size()
	var text_colour := get_theme_color(&"font_color", &"Label")
	var k := plan_scale()
	var st: ColonyState = services.state() if services != null and services.has_game() else null
	draw_rect(Rect2(Vector2.ZERO, size), PLAN_COLOURS["background"])

	# pads outside
	for pad: Dictionary in _pads:
		var centre := world_to_view(Vector2(float(pad.x), float(pad.y)))
		var r := float(pad.r) * k
		var dim := st != null and bool(pad.room) and not st.is_zone_powered(String(pad.name))
		draw_arc(centre, r, 0.0, TAU, 64, PLAN_COLOURS["line_dim"] if dim else PLAN_COLOURS["pad"], 2.0, true)
		_text(font, centre + Vector2(0, -r - 4.0), String(pad.name), fs, text_colour)
		symbols_used["◌"] = true
		if dim:
			_text(font, centre, "✖", fs, text_colour)
			symbols_used["✖"] = true

	# dome wall: a superellipse |x/rx|^n + |y/ry|^n = 1
	if not _dome.is_empty():
		var pts := PackedVector2Array()
		var n := float(_dome.n)
		for i in 129:
			var t := TAU * float(i) / 128.0
			var cx := cos(t)
			var sy := sin(t)
			var px := float(_dome.cx) + float(_dome.rx) * signf(cx) * pow(absf(cx), 2.0 / n)
			var py := float(_dome.cy) + float(_dome.ry) * signf(sy) * pow(absf(sy), 2.0 / n)
			pts.append(world_to_view(Vector2(px, py)))
		var plaza_dim := st != null and not st.is_zone_powered(ColonyZones.PLAZA)
		draw_polyline(pts, PLAN_COLOURS["line_dim"] if plaza_dim else PLAN_COLOURS["dome"], 2.0, true)
		symbols_used["◯"] = true
		if plaza_dim:
			var top := world_to_view(Vector2(float(_dome.cx), float(_dome.cy) + float(_dome.ry)))
			_text(font, top + Vector2(0, fs), "✖ " + ColonyZones.PLAZA, fs, text_colour)
			symbols_used["✖"] = true

	# rooms
	for room: Dictionary in _rooms:
		var room_name := String(room.name)
		var rect := room_rect(room_name)
		var powered := st == null or st.is_zone_powered(room_name)
		draw_rect(rect, PLAN_COLOURS["room"] if powered else PLAN_COLOURS["room_dim"])
		draw_rect(rect, PLAN_COLOURS["line"] if powered else PLAN_COLOURS["line_dim"], false, 1.5)
		drawn_rooms[room_name] = {"rect": rect, "dim": not powered}
		symbols_used["▭"] = true
		var label_size := font.get_string_size(room_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		if label_size.x < rect.size.x - 4.0 and label_size.y * 2.2 < rect.size.y:
			_text(font, rect.get_center() + Vector2(0, -label_size.y * 0.6), room_name, fs, text_colour)
		if not powered:
			_text(font, rect.get_center() + Vector2(0, fs * 0.5), "✖", fs, text_colour)
			symbols_used["✖"] = true
		if room_name == selected_zone:
			draw_rect(rect.grow(2.0), PLAN_COLOURS["selected"], false, 4.0)
			symbols_used["▢"] = true

	if st != null:
		_draw_stations(st, font, fs, text_colour, k)
		_draw_items(st, font, fs)
		_draw_crew(st, font, fs)

	# north arrow, top right
	var arrow_at := Vector2(size.x - fs * 1.5, fs * 1.4)
	_text(font, arrow_at, "↑", fs, text_colour)
	_text(font, arrow_at + Vector2(0, fs * 1.1), "N", fs, text_colour)
	symbols_used["↑"] = true

	if has_focus():
		var focus := get_theme_stylebox(&"focus", &"Button")
		if focus != null:
			draw_style_box(focus, Rect2(Vector2.ZERO, size))


func _draw_stations(st: ColonyState, font: Font, fs: int, text_colour: Color, k: float) -> void:
	for id: String in st.stations:
		var rec: Dictionary = st.stations[id]
		var kind := String(rec.get("kind", ""))
		var at := world_to_view(godot_to_plan(CharacterState._v3(rec.get("position", [0, 0, 0]))))
		var symbol := StationPanels.symbol_of(kind)
		_text(font, at, symbol, fs, PLAN_COLOURS["station"])
		symbols_used[symbol] = true
		var below := 1.0
		if kind == "solar":
			var index := int(rec.get("tracker", -1))
			var dusty := index >= 0 and index < st.panel_dust.size() and float(st.panel_dust[index]) > DUSTY_SHARE
			dusty_trackers[index] = dusty
			if dusty:
				_text(font, at + Vector2(0, fs * below), DUSTY_WORD, fs, text_colour)
				symbols_used[DUSTY_WORD] = true
				below += 1.0
		if k >= NAME_SCALE:
			_text(font, at + Vector2(0, fs * below), StationPanels.short_name_of(kind), fs, text_colour)


func _draw_items(st: ColonyState, font: Font, fs: int) -> void:
	var side := maxf(5.0, fs * 0.4)
	for id: String in st.items:
		var item: Dictionary = st.items[id]
		if String(item.get("holder", "")) != "":
			continue
		var at := world_to_view(godot_to_plan(CharacterState._v3(item.get("position", [0, 0, 0]))))
		draw_rect(Rect2(at - Vector2(side, side) * 0.5, Vector2(side, side)), PLAN_COLOURS["item"])
		draw_rect(Rect2(at - Vector2(side, side) * 0.5, Vector2(side, side)), PLAN_COLOURS["outline"], false, 1.0)
		symbols_used["■"] = true
	for cache: Dictionary in st.caches:
		var at := world_to_view(godot_to_plan(CharacterState._v3(cache.get("position", [0, 0, 0]))))
		var r := maxf(7.0, fs * 0.6)
		draw_circle(at, r, PLAN_COLOURS["cache"])
		draw_arc(at, r, 0.0, TAU, 24, PLAN_COLOURS["outline"], 1.5, true)
		_text(font, at, "!", fs, PLAN_COLOURS["outline"])
		symbols_used["!"] = true


func _draw_crew(st: ColonyState, font: Font, fs: int) -> void:
	var mine := services.local_character()
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: StringName in ids:
		var c := st.character(id)
		if c == mine:
			continue
		var at := world_to_view(godot_to_plan(c.position))
		var r := maxf(8.0, fs * 0.6)
		var colour: Color = (SPECIALTY_COLOURS.get(c.specialty, [PLAN_COLOURS["item"], ""]) as Array)[0]
		draw_circle(at, r, colour)
		draw_arc(at, r, 0.0, TAU, 24, PLAN_COLOURS["outline"], 1.5, true)
		var initial := String(SPECIALTY_INITIALS.get(c.specialty, "?"))
		_text(font, at, initial, fs, PLAN_COLOURS["outline"])
		symbols_used[initial] = true
	if mine != null:
		var at := world_to_view(godot_to_plan(mine.position))
		# Godot forward is -Z turned by yaw; on the plan (x, -z) and the screen (x, -y) that is (-sin, -cos).
		var forward := Vector2(-sin(mine.yaw), -cos(mine.yaw))
		var side := Vector2(-forward.y, forward.x)
		var r := maxf(10.0, fs * 0.75)
		var tri := PackedVector2Array([at + forward * r, at - forward * r * 0.6 + side * r * 0.7, at - forward * r * 0.6 - side * r * 0.7])
		draw_colored_polygon(tri, PLAN_COLOURS["you"])
		tri.append(tri[0])
		draw_polyline(tri, PLAN_COLOURS["outline"], 1.5, true)
		_text(font, at + Vector2(0, r + fs * 0.6), "You", fs, PLAN_COLOURS["you"])
		symbols_used["▲"] = true


## Draws `text` centred on `at`.
func _text(font: Font, at: Vector2, text: String, fs: int, colour: Color) -> void:
	var s := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var base := at + Vector2(-s.x * 0.5, font.get_ascent(fs) - s.y * 0.5)
	draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, PLAN_COLOURS["outline"])
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, colour)


# ---------------------------------------------------------------- map data

## Rooms, dome and pads from the map, read once. Pads in the file are y-up (Godot x, z); plan y = -z.
static func _layout() -> Dictionary:
	if not _layout_cache.is_empty():
		return _layout_cache
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH)) if FileAccess.file_exists(MANIFEST_PATH) else null
	var room_list: Array = []
	var dome := {}
	var pads: Array = []
	if data is Dictionary:
		room_list = (data as Dictionary).get("rooms", [])
		dome = (data as Dictionary).get("dome", {})
		for p: Dictionary in (data as Dictionary).get("pads_y_up", []):
			pads.append({"name": String(p.get("name", "")), "x": float(p.get("x", 0.0)), "y": -float(p.get("z", 0.0)),
				"r": float(p.get("r", 1.0)), "room": bool(p.get("room", false))})
	var bounds := Rect2()
	var first := true
	for r: Dictionary in room_list:
		var rect := Rect2(float(r.x0), float(r.y0), float(r.x1) - float(r.x0), float(r.y1) - float(r.y0))
		bounds = rect if first else bounds.merge(rect)
		first = false
	if not dome.is_empty():
		var d := Rect2(float(dome.cx) - float(dome.rx), float(dome.cy) - float(dome.ry), 2.0 * float(dome.rx), 2.0 * float(dome.ry))
		bounds = d if first else bounds.merge(d)
		first = false
	for p: Dictionary in pads:
		var pr := Rect2(float(p.x) - float(p.r), float(p.y) - float(p.r), 2.0 * float(p.r), 2.0 * float(p.r))
		bounds = pr if first else bounds.merge(pr)
		first = false
	if first:
		bounds = Rect2(-50, -50, 100, 100)
	_layout_cache = {"rooms": room_list, "dome": dome, "pads": pads, "bounds": bounds.grow(2.0)}
	return _layout_cache
