extends RefCounted
## Pictures for the goals card (scripts/ui/hud/goals_card.gd) and the big goals screen (goals_big_panel.gd), all drawn
## in code (no image files): one pictogram per goal, the status mark (ring / green tick), the "who can do it" badge
## (the specialist's symbol on their crew colour, or the "everyone" mark), progress pips and the map's marks (also
## used by the legend, so the legend shows exactly what is on the map).
## Colour is never the only cue: every mark has its own shape. Loaded with preload (no class_name):
##   const GoalArt := preload("res://scripts/ui/hud/goal_art.gd")

const GOLD := Color(1.0, 0.8, 0.22)
const INK := Color(0.05, 0.07, 0.14)
## Pictograms in a 1 x 1 box (y down), as lists of strokes. A "!" after the stroke's name draws it in the tint colour.
##   line / loop   [x, y, x, y, ...] open / closed outline       fill   [x, y, ...] filled shape
##   arc           cx, cy, radius, from degrees, to degrees      ring   cx, cy, radius (outline circle)
##   dot           cx, cy, radius (filled circle)                box    x0, y0, x1, y1, corner radius (outline)
##   half          cx, cy, radius (filled top half of a circle)  star   cx, cy, radius
const ICONS := {
	# a cassette tape
	"tape": [["box", 0.07, 0.22, 0.93, 0.78, 0.09], ["ring!", 0.33, 0.46, 0.09], ["ring!", 0.67, 0.46, 0.09],
		["line", [0.27, 0.78, 0.35, 0.64, 0.65, 0.64, 0.73, 0.78]]],
	# the tape player: a box with a play arrow
	"play": [["box", 0.09, 0.17, 0.91, 0.83, 0.11], ["fill!", [0.39, 0.32, 0.39, 0.68, 0.70, 0.50]]],
	# T01 Lock the Relay: a radio mast sending waves
	"T01": [["line", [0.5, 0.56, 0.5, 0.94]], ["arc", 0.5, 0.46, 0.22, -50.0, 50.0], ["arc", 0.5, 0.46, 0.22, 130.0, 230.0],
		["arc", 0.5, 0.46, 0.39, -50.0, 50.0], ["arc", 0.5, 0.46, 0.39, 130.0, 230.0], ["dot!", 0.5, 0.46, 0.09]],
	# T02 Patch the Relay: a plug on a cable
	"T02": [["line", [0.42, 0.10, 0.42, 0.30]], ["line", [0.58, 0.10, 0.58, 0.30]],
		["fill!", [0.29, 0.29, 0.71, 0.29, 0.71, 0.49, 0.60, 0.62, 0.40, 0.62, 0.29, 0.49]],
		["line", [0.5, 0.62, 0.5, 0.75]], ["arc", 0.66, 0.75, 0.16, 90.0, 180.0], ["line", [0.66, 0.91, 0.92, 0.91]]],
	# T03 Sync the Turbine: three rings, each with its pointer
	"T03": [["ring", 0.5, 0.5, 0.41], ["ring", 0.5, 0.5, 0.27], ["ring", 0.5, 0.5, 0.13],
		["dot!", 0.5, 0.09, 0.07], ["dot!", 0.734, 0.635, 0.07], ["dot!", 0.378, 0.456, 0.07]],
	# T04 Light the Power Bench: a lamp
	"T04": [["dot!", 0.5, 0.39, 0.13], ["arc", 0.5, 0.39, 0.26, 130.0, 410.0],
		["line", [0.333, 0.589, 0.40, 0.72, 0.60, 0.72, 0.667, 0.589]], ["line", [0.40, 0.82, 0.60, 0.82]], ["line", [0.45, 0.92, 0.55, 0.92]]],
	# T06 Water the Kale: a drop over a plant
	"T06": [["fill!", [0.5, 0.03, 0.60, 0.23, 0.40, 0.23]], ["dot!", 0.5, 0.27, 0.105],
		["line", [0.5, 0.94, 0.5, 0.62]], ["fill", [0.5, 0.70, 0.38, 0.50, 0.14, 0.48, 0.28, 0.70]],
		["fill", [0.5, 0.70, 0.62, 0.50, 0.86, 0.48, 0.72, 0.70]], ["line", [0.18, 0.94, 0.82, 0.94]]],
	# T08 Glaze the Dome: a dome made of panes
	"T08": [["fill!", [0.5, 0.60, 0.359, 0.659, 0.217, 0.517, 0.347, 0.43, 0.5, 0.40]],
		["arc", 0.5, 0.80, 0.40, 180.0, 360.0], ["arc", 0.5, 0.80, 0.20, 180.0, 360.0], ["line", [0.05, 0.80, 0.95, 0.80]],
		["line", [0.5, 0.60, 0.5, 0.40]], ["line", [0.359, 0.659, 0.217, 0.517]], ["line", [0.641, 0.659, 0.783, 0.517]]],
	# T09 Sort the Lab Samples: three test tubes
	"T09": [["fill!", [0.165, 0.50, 0.315, 0.50, 0.315, 0.72, 0.165, 0.72]], ["dot!", 0.24, 0.72, 0.075],
		["fill!", [0.425, 0.34, 0.575, 0.34, 0.575, 0.72, 0.425, 0.72]], ["dot!", 0.5, 0.72, 0.075],
		["fill!", [0.685, 0.58, 0.835, 0.58, 0.835, 0.72, 0.685, 0.72]], ["dot!", 0.76, 0.72, 0.075],
		["line", [0.165, 0.16, 0.165, 0.72]], ["arc", 0.24, 0.72, 0.075, 0.0, 180.0], ["line", [0.315, 0.72, 0.315, 0.16]], ["line", [0.12, 0.16, 0.36, 0.16]],
		["line", [0.425, 0.16, 0.425, 0.72]], ["arc", 0.5, 0.72, 0.075, 0.0, 180.0], ["line", [0.575, 0.72, 0.575, 0.16]], ["line", [0.38, 0.16, 0.62, 0.16]],
		["line", [0.685, 0.16, 0.685, 0.72]], ["arc", 0.76, 0.72, 0.075, 0.0, 180.0], ["line", [0.835, 0.72, 0.835, 0.16]], ["line", [0.64, 0.16, 0.88, 0.16]]],
	# T10 Revive the Med Bay: a heartbeat on a monitor
	"T10": [["box", 0.07, 0.14, 0.93, 0.72, 0.08], ["line!", [0.16, 0.45, 0.34, 0.45, 0.42, 0.27, 0.53, 0.61, 0.61, 0.45, 0.84, 0.45]],
		["line", [0.5, 0.72, 0.5, 0.88]], ["line", [0.30, 0.89, 0.70, 0.89]]],
	# T11 Clear the Landing Lines: a broom over painted floor lines
	"T11": [["line!", [0.06, 0.88, 0.28, 0.88]], ["line!", [0.39, 0.88, 0.61, 0.88]], ["line!", [0.72, 0.88, 0.94, 0.88]],
		["line", [0.86, 0.06, 0.52, 0.48]], ["fill", [0.367, 0.394, 0.633, 0.606, 0.577, 0.676, 0.311, 0.464]],
		["line", [0.311, 0.464, 0.25, 0.56]], ["line", [0.40, 0.535, 0.34, 0.63]], ["line", [0.49, 0.605, 0.43, 0.70]], ["line", [0.577, 0.676, 0.52, 0.77]]],
	# T12 Seal the Airlock: a round hatch with its wheel
	"T12": [["ring", 0.5, 0.5, 0.41], ["ring", 0.5, 0.5, 0.25], ["line", [0.5, 0.25, 0.5, 0.75]],
		["line", [0.284, 0.375, 0.716, 0.625]], ["line", [0.284, 0.625, 0.716, 0.375]], ["dot!", 0.5, 0.5, 0.085]],
	# any other goal
	"star": [["star!", 0.5, 0.52, 0.44]],
	# who can do it (drawn on the crew colour)
	"electrical_comms": [["fill", [0.62, 0.05, 0.22, 0.56, 0.46, 0.56, 0.37, 0.95, 0.78, 0.42, 0.54, 0.42]]],
	"medical_life_support": [["fill", [0.37, 0.12, 0.63, 0.12, 0.63, 0.88, 0.37, 0.88]], ["fill", [0.12, 0.37, 0.88, 0.37, 0.88, 0.63, 0.12, 0.63]]],
	"biology_food": [["dot", 0.5, 0.24, 0.17], ["dot", 0.747, 0.42, 0.17], ["dot", 0.653, 0.71, 0.17], ["dot", 0.347, 0.71, 0.17],
		["dot", 0.253, 0.42, 0.17], ["dot!", 0.5, 0.5, 0.10]],
	"field_engineering_geology": [["line", [0.20, 0.88, 0.66, 0.34]], ["arc", 0.26, 0.80, 0.61, -84.0, -6.0]],
	"everyone": [["dot", 0.33, 0.36, 0.12], ["half", 0.33, 0.84, 0.21], ["dot", 0.64, 0.32, 0.15], ["half", 0.64, 0.88, 0.27]],
	# small marks
	"tick": [["line", [0.24, 0.53, 0.43, 0.71, 0.77, 0.31]]],
	"lock": [["arc", 0.5, 0.42, 0.20, 180.0, 360.0], ["line", [0.30, 0.42, 0.30, 0.50]], ["line", [0.70, 0.42, 0.70, 0.50]],
		["fill", [0.18, 0.48, 0.82, 0.48, 0.82, 0.92, 0.18, 0.92]]],
}


## The pictogram name of a goal (ColonyGoals): "tape", "play", "T01".."T12", else "star".
static func icon_of(g: Dictionary) -> String:
	match String(g.get("kind", "")):
		"tapes_found":
			return "tape"
		"tapes_played":
			return "play"
		"fix":
			var task := String(g.get("task", ""))
			return task if ICONS.has(task) else "star"
	return "star"


## Draws pictogram `kind` inside `rect` (kept square, centred): outlines in `ink`, the highlighted part in `tint`.
static func draw_icon(c: CanvasItem, kind: String, rect: Rect2, ink: Color, tint: Color, weight := 1.0) -> void:
	var s := minf(rect.size.x, rect.size.y)
	var o := rect.position + (rect.size - Vector2(s, s)) * 0.5
	var w := maxf(1.6, s * 0.085 * weight)
	for stroke: Array in ICONS.get(kind, ICONS["star"]):
		var op := String(stroke[0])
		var col := ink
		if op.ends_with("!"):
			op = op.trim_suffix("!")
			col = tint
		match op:
			"line", "loop":
				var pts := _points(stroke[1], o, s)
				if op == "loop":
					pts.append(pts[0])
				c.draw_polyline(pts, col, w, true)
				if op == "line":
					# round ends, so short strokes do not look chopped
					c.draw_circle(pts[0], w * 0.5, col)
					c.draw_circle(pts[pts.size() - 1], w * 0.5, col)
			"fill":
				c.draw_colored_polygon(_points(stroke[1], o, s), col)
			"arc":
				var sweep := absf(float(stroke[5]) - float(stroke[4]))
				c.draw_arc(o + Vector2(float(stroke[1]), float(stroke[2])) * s, float(stroke[3]) * s, deg_to_rad(float(stroke[4])),
					deg_to_rad(float(stroke[5])), maxi(8, int(sweep / 9.0)), col, w, true)
			"ring":
				c.draw_arc(o + Vector2(float(stroke[1]), float(stroke[2])) * s, float(stroke[3]) * s, 0.0, TAU, 40, col, w, true)
			"dot":
				c.draw_circle(o + Vector2(float(stroke[1]), float(stroke[2])) * s, float(stroke[3]) * s, col)
			"half":
				var centre := o + Vector2(float(stroke[1]), float(stroke[2])) * s
				var pts2 := PackedVector2Array()
				for i in 17:
					var a := PI + PI * float(i) / 16.0
					pts2.append(centre + Vector2(cos(a), sin(a)) * float(stroke[3]) * s)
				c.draw_colored_polygon(pts2, col)
			"box":
				c.draw_polyline(_round_rect(Rect2(o + Vector2(float(stroke[1]), float(stroke[2])) * s,
					Vector2(float(stroke[3]) - float(stroke[1]), float(stroke[4]) - float(stroke[2])) * s), float(stroke[5]) * s), col, w, true)
			"star":
				var mid := o + Vector2(float(stroke[1]), float(stroke[2])) * s
				var star := PackedVector2Array()
				for i in 10:
					var a2 := -PI * 0.5 + TAU * float(i) / 10.0
					star.append(mid + Vector2(cos(a2), sin(a2)) * float(stroke[3]) * s * (1.0 if i % 2 == 0 else 0.45))
				for i in 5:
					# five kites around the middle: a star is not convex, so it is filled piece by piece
					c.draw_colored_polygon(PackedVector2Array([mid, star[(i * 2 + 9) % 10], star[i * 2], star[i * 2 + 1]]), col)


static func _points(flat: Array, o: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(0, flat.size() - 1, 2):
		pts.append(o + Vector2(float(flat[i]), float(flat[i + 1])) * s)
	return pts


## The closed outline of a rectangle with round corners.
static func _round_rect(r: Rect2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rad := minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var corners := [r.position + Vector2(rad, rad), Vector2(r.end.x - rad, r.position.y + rad), r.end - Vector2(rad, rad), Vector2(r.position.x + rad, r.end.y - rad)]
	for k in 4:
		for i in 6:
			var a := PI + PI * 0.5 * float(k) + PI * 0.5 * float(i) / 5.0
			pts.append((corners[k] as Vector2) + Vector2(cos(a), sin(a)) * rad)
	pts.append(pts[0])
	return pts


## A filled rectangle with round corners.
static func fill_round_rect(c: CanvasItem, r: Rect2, radius: float, col: Color) -> void:
	var pts := _round_rect(r, radius)
	pts.remove_at(pts.size() - 1)
	c.draw_colored_polygon(pts, col)


## The status mark of a goal: an empty ring while it is open, a green disc with a tick once it is done.
static func draw_status(c: CanvasItem, rect: Rect2, done: bool) -> void:
	var s := minf(rect.size.x, rect.size.y)
	var mid := rect.get_center()
	if done:
		c.draw_circle(mid, s * 0.46, AstraStyle.GOOD)
		draw_icon(c, "tick", Rect2(mid - Vector2(s, s) * 0.5, Vector2(s, s)), INK, INK, 1.5)
	else:
		c.draw_arc(mid, s * 0.40, 0.0, TAU, 40, AstraStyle.TEXT_2 if UiTheme.is_high_contrast() else AstraStyle.TEXT_3, maxf(2.0, s * 0.09), true)


## The colour of a specialist (their suit colour, CrewLooks), or a soft white for "everyone".
static func who_colour(spec: String) -> Color:
	var i := CrewLooks.index_of(StringName(spec))
	return CrewLooks.accent(i) if i >= 0 else Color(0.80, 0.85, 1.0)


## The "who can do it" badge: the specialist's symbol on a disc in their crew colour, or two people on a pale disc
## for "everyone". `locked` adds a small padlock: this job belongs to another crew member.
static func draw_who(c: CanvasItem, rect: Rect2, spec: String, locked := false) -> void:
	var s := minf(rect.size.x, rect.size.y)
	var mid := rect.get_center()
	var everyone := spec == "" or spec == "general" or not ICONS.has(spec)
	var fill := who_colour("" if everyone else spec)
	var r := s * 0.47
	if everyone:
		c.draw_circle(mid, r, Color(fill, 0.16))
		c.draw_arc(mid, r - 1.0, 0.0, TAU, 40, Color(fill, 0.75), maxf(1.5, s * 0.05), true)
		draw_icon(c, "everyone", Rect2(mid - Vector2(s, s) * 0.33 + Vector2(0, -s * 0.03), Vector2(s, s) * 0.66), fill, fill)
	else:
		c.draw_circle(mid, r, fill)
		c.draw_arc(mid, r - 0.5, 0.0, TAU, 40, Color(1, 1, 1, 0.85), maxf(1.5, s * 0.045), true)
		# dark ink on the light colours (yellow), white on the dark ones (blue, green, magenta)
		var ink := INK if UiTheme.luminance(fill) > 0.4 else Color.WHITE
		draw_icon(c, spec, Rect2(mid - Vector2(s, s) * 0.29, Vector2(s, s) * 0.58), ink, fill, 1.5)
	if locked:
		var ls := s * 0.46
		var at := rect.get_center() + Vector2(s * 0.5 - ls * 0.62, s * 0.5 - ls * 0.62)
		c.draw_circle(at, ls * 0.56, INK)
		c.draw_arc(at, ls * 0.56, 0.0, TAU, 28, AstraStyle.TEXT, 1.5, true)
		draw_icon(c, "lock", Rect2(at - Vector2(ls, ls) * 0.36, Vector2(ls, ls) * 0.72), AstraStyle.TEXT, AstraStyle.TEXT, 1.3)


## A mark of the goals map, centred on `at` with radius `r`. `kind`: "you", "tape", "player" (the tape player) or
## "fix" (a broken part: an orange ring with "!", or a green ring with a tick once fixed). `pulse` 0..1 animates the
## ring around it; a negative pulse draws none (the legend, and reduce motion).
static func draw_marker(c: CanvasItem, kind: String, at: Vector2, r: float, done := false, pulse := -1.0) -> void:
	var outline := Color(0, 0, 0, 0.85)
	match kind:
		"you":
			var tri := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r * 0.8, r * 0.7), at + Vector2(-r * 0.8, r * 0.7)])
			c.draw_colored_polygon(tri, Color.WHITE)
			tri.append(tri[0])
			c.draw_polyline(tri, outline, 1.5, true)
		"tape":
			if pulse >= 0.0:
				c.draw_circle(at, r + 4.0 * pulse, Color(GOLD, 0.25))
			c.draw_circle(at, r, GOLD)
			c.draw_arc(at, r, 0.0, TAU, 24, outline, 2.0, true)
		"player", "fix":
			var col: Color = AstraStyle.GOOD if done else (GOLD if kind == "player" else AstraStyle.ACCENT)
			var w := maxf(2.5, r * 0.24)
			c.draw_circle(at, r, Color(0, 0, 0, 0.6))
			c.draw_arc(at, r, 0.0, TAU, 40, col, w, true)
			if not done and pulse >= 0.0:
				c.draw_arc(at, r + 4.0 + 7.0 * pulse, 0.0, TAU, 48, Color(col, 0.7 * (1.0 - pulse)), 2.5, true)
			var inner := Rect2(at - Vector2(r, r) * 0.62, Vector2(r, r) * 1.24)
			if done:
				draw_icon(c, "tick", inner, col, col, 1.6)
			elif kind == "player":
				c.draw_colored_polygon(PackedVector2Array([at + Vector2(-r * 0.26, -r * 0.42), at + Vector2(-r * 0.26, r * 0.42), at + Vector2(r * 0.46, 0)]), col)
			else:
				c.draw_line(at + Vector2(0, -r * 0.5), at + Vector2(0, r * 0.12), col, maxf(2.5, r * 0.26), true)
				c.draw_circle(at + Vector2(0, r * 0.44), maxf(1.5, r * 0.15), col)


# ---------------------------------------------------------------- small controls that show the drawings

## A goal's pictogram, on a soft tile when `tile` is true.
class Icon extends Control:
	const Art := preload("res://scripts/ui/hud/goal_art.gd")
	var kind := "star"
	var ink := AstraStyle.TEXT
	var tint := AstraStyle.ACCENT
	var tile := true

	func _init(p_kind := "star", side := 36.0, p_tint := AstraStyle.ACCENT, p_tile := true) -> void:
		kind = p_kind
		tint = p_tint
		tile = p_tile
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if tile:
			Art.fill_round_rect(self, r, size.x * 0.24, Color(tint, 0.2 if UiTheme.is_high_contrast() else 0.14))
			draw_polyline(Art._round_rect(r.grow(-0.5), size.x * 0.24), Color(tint, 0.9 if UiTheme.is_high_contrast() else 0.45), 1.5, true)
			r = r.grow(-size.x * 0.17)
		Art.draw_icon(self, kind, r, ink, tint)


## The ring (open) or green tick (done) in front of a goal.
class Status extends Control:
	const Art := preload("res://scripts/ui/hud/goal_art.gd")
	var done := false

	func _init(p_done := false, side := 26.0) -> void:
		done = p_done
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		Art.draw_status(self, Rect2(Vector2.ZERO, size), done)


## The "who can do it" badge. `spec` is a crew specialty id, or "" for everyone.
class Who extends Control:
	const Art := preload("res://scripts/ui/hud/goal_art.gd")
	var spec := ""
	var locked := false

	func _init(p_spec := "", side := 32.0, p_locked := false) -> void:
		spec = p_spec
		locked = p_locked
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		Art.draw_who(self, Rect2(Vector2.ZERO, size), spec, locked)


## Progress pips for a counted goal: `have` filled dots out of `need` (a bar instead when there are too many).
class Pips extends Control:
	const MAX_PIPS := 8
	var have := 0
	var need := 0
	var colour := AstraStyle.ACCENT
	var dot := 12.0

	func _init(p_have := 0, p_need := 0, p_dot := 12.0, p_colour := AstraStyle.ACCENT) -> void:
		have = p_have
		need = maxi(1, p_need)
		dot = p_dot
		colour = p_colour
		custom_minimum_size = Vector2(dot * 1.5 * mini(need, MAX_PIPS) - dot * 0.5 if need <= MAX_PIPS else dot * 8.0, dot)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	func _draw() -> void:
		var y := size.y * 0.5
		if need > MAX_PIPS:
			var track := Rect2(0, y - dot * 0.3, size.x, dot * 0.6)
			draw_rect(track, Color(1, 1, 1, 0.14))
			draw_rect(Rect2(track.position, Vector2(track.size.x * clampf(float(have) / float(need), 0.0, 1.0), track.size.y)), colour)
			return
		for i in need:
			var at := Vector2(dot * 0.5 + dot * 1.5 * i, y)
			if i < have:
				draw_circle(at, dot * 0.5, colour)
			else:
				draw_arc(at, dot * 0.5 - 1.0, 0.0, TAU, 20, AstraStyle.TEXT_2 if UiTheme.is_high_contrast() else AstraStyle.TEXT_3, 2.0, true)


## One mark of the goals map, for the legend.
class Mark extends Control:
	const Art := preload("res://scripts/ui/hud/goal_art.gd")
	var kind := "fix"
	var done := false

	func _init(p_kind := "fix", p_done := false, side := 24.0) -> void:
		kind = p_kind
		done = p_done
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var r := minf(size.x, size.y) * (0.30 if kind == "tape" else 0.42)
		Art.draw_marker(self, kind, size * 0.5, r, done)
