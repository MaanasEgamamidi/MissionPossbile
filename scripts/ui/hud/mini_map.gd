class_name MiniMap
extends PanelContainer
## The small map in the top-right corner: the base and its dome, the two solar fields, the scout bay, the places the
## scout can survey (? until it has been there, ✓ after), ore deposits once found (◆ in the ore's colour), the
## broken-down rover, the scout rover with its route, the crew, and you (the white arrow). North is up.
## Owner 2026-11-14: hidden for now (MissionHud no longer creates it; the big goals screen, J, has the map).

const CENTRE := Vector2(15.0, 26.0)        # Godot x, z at the middle of the map
const HALF := 62.0                          # metres from the middle to each edge
const MANIFEST_PATH := "res://data/colony_manifest.json"

static var _rooms: Array = []               # [Rect2 in Godot x, z]
static var _trackers: Array = []            # [Vector2]

var services: GameServices
var _canvas: MapCanvas


func setup(p_services: GameServices) -> void:
	services = p_services
	name = "MiniMap"
	add_theme_stylebox_override(&"panel", AstraStyle.glass(AstraStyle.RADIUS, 10, 8))
	mouse_filter = Control.MOUSE_FILTER_PASS
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 6)
	col.add_child(head)
	head.add_child(AstraStyle.label("▦", 13, AstraStyle.TEXT_2, "", true))
	var t := AstraStyle.label("Map", 14, AstraStyle.TEXT, "Title")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(AstraStyle.label("%d m × %d m" % [roundi(HALF * 2), roundi(HALF * 2)], 10, AstraStyle.TEXT_3))
	head.add_child(AstraStyle.keycap("M", 10))
	_canvas = MapCanvas.new()
	_canvas.name = "Canvas"
	_canvas.map = self
	_canvas.custom_minimum_size = Vector2(230, 200)
	col.add_child(_canvas)
	var key := HBoxContainer.new()
	key.add_theme_constant_override(&"separation", 8)
	col.add_child(key)
	for k: Array in [["◆", AstraStyle.C_ORE, "Ore"], ["?", AstraStyle.TEXT_2, "To explore"], ["●", AstraStyle.C_O2, "Scout"], ["▲", AstraStyle.TEXT, "You"]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 3)
		h.add_child(AstraStyle.label(String(k[0]), 10, k[1], "", true))
		h.add_child(AstraStyle.label(String(k[2]), 10, AstraStyle.TEXT_3))
		key.add_child(h)
	_load()


func refresh() -> void:
	_canvas.queue_redraw()


static func _load() -> void:
	if not _rooms.is_empty():
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not data is Dictionary:
		return
	for r: Dictionary in (data as Dictionary).get("rooms", []):
		# Blender x, y -> Godot x, z = -y
		var x0 := float(r.x0)
		var x1 := float(r.x1)
		var z0 := -float(r.y1)
		var z1 := -float(r.y0)
		_rooms.append(Rect2(Vector2(x0, z0), Vector2(x1 - x0, z1 - z0)))
	for o: Dictionary in (data as Dictionary).get("objects", []):
		if String(o.name).begins_with("sf_solar_tracker"):
			var m: Array = o.matrix_world
			_trackers.append(Vector2(float(m[0][3]), -float(m[1][3])))


## Godot x, z -> point on the canvas.
func to_canvas(p: Vector2, sz: Vector2) -> Vector2:
	var s := minf(sz.x, sz.y) / (HALF * 2.0)
	var off := (sz - Vector2(HALF * 2.0, HALF * 2.0) * s) * 0.5
	return off + (p - CENTRE + Vector2(HALF, HALF)) * s


class MapCanvas extends Control:
	var map: MiniMap

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func _draw() -> void:
		if map == null or map.services == null or not map.services.has_game():
			return
		var st := map.services.state()
		var sz := size
		var scale := minf(sz.x, sz.y) / (HALF * 2.0)
		var font := AstraStyle.symbol_font()
		var fsize := AstraStyle.fs(11)
		# ground
		var ground := Rect2(map.to_canvas(CENTRE - Vector2(HALF, HALF), sz), Vector2(HALF * 2.0, HALF * 2.0) * scale)
		draw_rect(ground, Color(0.43, 0.26, 0.17))
		for c: Array in [[Vector2(70, 72), 12.0], [Vector2(-38, 70), 7.0], [Vector2(55, 60), 5.0], [Vector2(-20, -25), 6.0]]:
			draw_circle(map.to_canvas(c[0], sz), float(c[1]) * scale, Color(0.33, 0.19, 0.12))
			draw_arc(map.to_canvas(c[0], sz), float(c[1]) * scale, 0.0, TAU, 32, Color(0.6, 0.4, 0.28, 0.7), 1.2, true)
		# dome and rooms
		var dome_c := map.to_canvas(Vector2(15.0, -4.0), sz)
		var pts := PackedVector2Array()
		for i in 49:
			var a := TAU * i / 48.0
			pts.append(dome_c + Vector2(cos(a) * 27.3, sin(a) * 16.3) * scale)
		draw_colored_polygon(pts, Color(0.95, 0.62, 0.35, 0.18))
		draw_polyline(pts, Color(0.95, 0.75, 0.55, 0.7), 1.2, true)
		# the garden dome (greenhouse) east of the base
		var gd := map.to_canvas(Vector2(50.0, 27.0), sz)
		draw_circle(gd, 11.0 * scale, Color(0.55, 0.85, 0.6, 0.2))
		draw_arc(gd, 11.0 * scale, 0.0, TAU, 32, Color(0.6, 0.9, 0.65, 0.7), 1.2, true)
		for r: Rect2 in MiniMap._rooms:
			var a := map.to_canvas(r.position, sz)
			draw_rect(Rect2(a, r.size * scale), Color(0.85, 0.9, 1.0, 0.22))
			draw_rect(Rect2(a, r.size * scale), Color(0.85, 0.9, 1.0, 0.35), false, 1.0)
		for t: Vector2 in MiniMap._trackers:
			var p := map.to_canvas(t, sz)
			draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), AstraStyle.C_POWER)
		# survey sites
		for s: Dictionary in ScoutSystem.sites():
			var sp := map.to_canvas(_xz(s.position), sz)
			var done := ScoutSystem.is_surveyed(st, String(s.id))
			draw_circle(sp, 6.5, Color(0, 0, 0, 0.35))
			draw_arc(sp, 6.5, 0.0, TAU, 20, AstraStyle.C_SCIENCE if done else Color(1, 1, 1, 0.7), 1.4, true)
			_glyph(font, sp, "✓" if done else "?", fsize, AstraStyle.C_SCIENCE if done else AstraStyle.TEXT)
		# stations: scout bay, broken rover, ore deposits once found
		var bay: Dictionary = st.stations.get("scout_bay", {})
		if not bay.is_empty():
			var bp := map.to_canvas(_xz(bay.position), sz)
			draw_rect(Rect2(bp - Vector2(4, 4), Vector2(8, 8)), AstraStyle.ACCENT, false, 1.5)
		var br: Dictionary = st.stations.get("broken_rover", {})
		if not br.is_empty():
			_glyph(font, map.to_canvas(_xz(br.position), sz), "♻", fsize, AstraStyle.TEXT_2)
		for id in ScoutSystem.ore_stations(st):
			if not ScoutSystem.is_revealed(st, id):
				continue
			var c: Array = ScoutSystem.ore_info(ScoutSystem.ore_kind_of(st, id)).get("color", [0.8, 0.6, 1.0])
			var col := Color(float(c[0]), float(c[1]), float(c[2])).lightened(0.25) if ScoutSystem.ore_left(st, id) > 0 else Color(0.5, 0.5, 0.5)
			_glyph(font, map.to_canvas(_xz(st.stations[id].position), sz), "◆", fsize + 2, col)
		# the scout and its route
		if ScoutSystem.is_built(st):
			var sp2 := map.to_canvas(_xz(st.scout.get("position", [0, 0, 0])), sz)
			if ScoutSystem.is_out(st):
				var to := map.to_canvas(_xz(st.scout.get("leg_to", [0, 0, 0])), sz)
				draw_dashed_line(sp2, to, Color(AstraStyle.C_O2, 0.8), 1.5, 4.0)
			draw_circle(sp2, 5.0, AstraStyle.C_O2)
			draw_arc(sp2, 5.0, 0.0, TAU, 16, Color(0, 0, 0, 0.6), 1.0, true)
		# crew
		var me := map.services.local_character()
		for c: CharacterState in st.active_characters():
			if me != null and c.id == me.id:
				continue
			var cp := map.to_canvas(Vector2(c.position.x, c.position.z), sz)
			draw_circle(cp, 4.0, CrewLooks.accent(CrewLooks.index_of(c.specialty)))
		if me != null:
			var p := map.to_canvas(Vector2(me.position.x, me.position.z), sz)
			var fwd := Vector2(-sin(me.yaw), -cos(me.yaw))
			var side := Vector2(fwd.y, -fwd.x)
			var tri := PackedVector2Array([p + fwd * 8.0, p - fwd * 5.0 + side * 5.0, p - fwd * 2.5, p - fwd * 5.0 - side * 5.0])
			draw_colored_polygon(tri, AstraStyle.TEXT)
			draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color(0, 0, 0, 0.7), 1.0, true)
		draw_string(font, Vector2(6, 14), "N ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, AstraStyle.fs(10), AstraStyle.TEXT_2)

	func _glyph(font: Font, at: Vector2, text: String, fsize: int, color: Color) -> void:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
		var pos := at + Vector2(-w.x * 0.5, fsize * 0.36)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.7))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)

	static func _xz(a: Variant) -> Vector2:
		if a is Array and (a as Array).size() >= 3:
			return Vector2(float(a[0]), float(a[2]))
		return Vector2.ZERO
