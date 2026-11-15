extends "res://scripts/tasks/puzzles/med_ui.gd"
## T09 "Sort the Lab Samples" mini-game (Med Bay workbench, medical specialist). UI overhaul 2026-11-15: the test-tube
## rack is the interface, in the spirit of Among Us "Sort Samples". One picture, no words on it:
##   Left    the rack with five glass tubes standing in it. Every dose of practice liquid carries its colour AND its
##           shape (teal circle, rose triangle, amber square, purple diamond); the strip on the rack's front shows the
##           kinds in play. A tube full of one kind is settled: it gets a tick.
##   Right   the bench mat where the fallen tubes lie (target rings on them, a ghost outline at their empty slot).
## Play: click a fallen tube to stand it back in its slot ("rack"). Then click a tube: it lifts out of the rack, the
## tubes it may pour into get the target ring, and it tilts toward the one you point at; click that one and a dose
## pours across ("pour"). Click the lifted tube again to put it back.
## The host rule (t09_rule.gd) decides every move and the completion; the panel only sends moves and draws `puzzle`.
## Keyboard: Tab / Left / Right move between the tubes, Enter / Space acts.

const Rule := preload("res://scripts/tasks/puzzles/t09_rule.gd")
## Liquid colours and shapes by reagent id (Rule.REAGENTS). Ids 0..2 have a dose sprite; id 3 is drawn.
const LIQUID := [Color(0.26, 0.66, 0.6), Color(0.86, 0.42, 0.44), Color(0.93, 0.68, 0.22), Color(0.6, 0.44, 0.84)]
const LIQUID_SHAPE := [Kit.CIRCLE, Kit.TRIANGLE, Kit.SQUARE, Kit.DIAMOND]
const DOSE_TEX := ["samples/dose_teal_circle", "samples/dose_rose_triangle", "samples/dose_amber_square", ""]
const SHAPE_WORDS := ["Circles", "Triangles", "Squares", "Diamonds"]
## Source pixels: the glass tube, the band of a dose sprite with its shape, the rack and its five holes.
const TUBE_TEX := Vector2(139, 376)
const TUBE_INNER_X := Vector2(22, 117)
const TUBE_FLOOR := 348.0
const DOSE_SRC := Rect2(8, 60, 169, 118)
const RACK_TEX := Vector2(420, 154)
const HOLE_X := [80.0, 145.0, 210.5, 276.0, 341.0]
const HOLE_Y := 42.0
const CUE_RACK := "Stand the tubes up [Enter]"
const CUE_PICK := "Pick a tube to pour [Enter]"
const CUE_POUR := "Pour into a glowing tube [Enter]"
const POUR_S := 0.55
const MARK_S := 0.9

## One flat button over each tube, by tube index (tests and tools/godot/capture_puzzles.gd press them).
var tube_buttons: Array[Button] = []
## The picture: rack, tubes, bench mat (one drawn control).
var bench: Control
## The tube lifted out to pour from (-1 = none). Local only: nothing is sent until the second tube is picked.
var selected := -1
var _hover := -1
var _lift := PackedFloat32Array()
var _prev_tubes: Array = []
var _pour: Dictionary = {}
var _wrong := -1
var _wrong_left := 0.0
var _calm := false


func rule_script() -> Script:
	return Rule


func setup(p_services: GameServices) -> void:
	task_title = "Sort the Lab Samples"
	instructions = ("Some tubes fell over: click them to stand them back in the rack. Then sort the practice liquids "
		+ "(made up, not real medicine) so each tube holds one kind: pick a tube, then the tube to pour into. A dose "
		+ "goes into an empty tube or onto the same kind.")
	super.setup(p_services)
	name = "T09MixturePanel"


func build_game() -> void:
	bench = make_box("Bench", Vector2(900, 420), _paint)
	bench.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Kit.smooth(bench)
	bench.resized.connect(_place)
	play_area.add_child(bench)
	_lift.resize(Rule.TUBES)
	_lift.fill(0.0)
	for i in Rule.TUBES:
		var b := Button.new()
		b.name = "Tube%d" % (i + 1)
		b.flat = true
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = "Tube %d" % (i + 1)
		# The bench draws the shared focus ring (Kit.focus_ring); the button's own focus box stays invisible.
		var clear := StyleBoxFlat.new()
		clear.draw_center = false
		b.add_theme_stylebox_override(&"focus", clear)
		b.pressed.connect(pick.bind(i))
		b.mouse_entered.connect(func() -> void: _hover = i)
		b.mouse_exited.connect(func() -> void:
			if _hover == i:
				_hover = -1)
		if i > 0:
			b.focus_neighbor_left = NodePath("../Tube%d" % i)
		if i < Rule.TUBES - 1:
			b.focus_neighbor_right = NodePath("../Tube%d" % (i + 2))
		bench.add_child(b)
		tube_buttons.append(b)
	set_cue(CUE_RACK)


func _all_racked() -> bool:
	return not puzzle.is_empty() and (puzzle.racked as Array).all(func(r: bool) -> bool: return r)


## Player picked tube i (click or keyboard).
func pick(i: int) -> void:
	if pending or succeeded or puzzle.is_empty():
		return
	var racked: Array = puzzle.racked
	var tubes: Array = puzzle.tubes
	if not _all_racked():
		if bool(racked[i]):
			_nudge(i, "Stand the fallen tubes up first.")
		else:
			send("rack", i)
		return
	if selected == -1:
		if (tubes[i] as Array).is_empty():
			_nudge(i, "That tube is empty.")
			return
		selected = i
		_sync_view()
		return
	if selected == i:
		selected = -1
		_sync_view()
		return
	var from := selected
	selected = -1
	send("pour", from * 10 + i)


## A gentle "not that one": an amber cross on the tube for a moment and a short line.
func _nudge(i: int, text: String) -> void:
	_wrong = i
	_wrong_left = MARK_S
	hint(text)
	status_label.theme_type_variation = UiTheme.WARN


func redraw() -> void:
	if puzzle.is_empty():
		return
	var tubes: Array = puzzle.tubes
	# A dose that just moved: pour it across from the tube that lost one to the tube that gained one.
	if _prev_tubes.size() == tubes.size() and not _calm:
		var from := -1
		var to := -1
		for i in tubes.size():
			var d := (tubes[i] as Array).size() - (_prev_tubes[i] as Array).size()
			if d == -1:
				from = i
			elif d == 1:
				to = i
		if from >= 0 and to >= 0:
			_pour = {"from": from, "to": to, "id": int((tubes[to] as Array).back()), "t": 0.0}
	_prev_tubes = tubes.duplicate(true)
	if selected >= 0 and (succeeded or not _all_racked() or (tubes[selected] as Array).is_empty()):
		selected = -1
	_sync_view()


func _sync_view() -> void:
	if bench == null or puzzle.is_empty():
		return
	var tubes: Array = puzzle.tubes
	var racked: Array = puzzle.racked
	for i in Rule.TUBES:
		var b := tube_buttons[i]
		var tube: Array = tubes[i]
		var words := "Tube %d" % (i + 1)
		if not bool(racked[i]):
			words += ": lying down"
		elif tube.is_empty():
			words += ": empty"
		else:
			words += ": %s on top, %d of %d" % [SHAPE_WORDS[int(tube.back())].to_lower(), tube.size(), Rule.CAPACITY]
		if i == selected:
			words += ", lifted to pour"
		b.tooltip_text = words
	if succeeded:
		set_cue("")
	elif not _all_racked():
		set_cue(CUE_RACK)
	elif selected >= 0:
		set_cue(CUE_POUR)
	else:
		set_cue(CUE_PICK)
	_place()
	bench.queue_redraw()


func explain(move: Dictionary) -> String:
	var payload := int(move.get("value", 0))
	match String(move.get("move", "")):
		"rack":
			return "That tube is already standing."
		"pour":
			var tubes: Array = puzzle.get("tubes", [])
			var from := payload / 10
			var to := payload % 10
			if from >= tubes.size() or to >= tubes.size():
				return "Pick two tubes in the rack."
			_wrong = to
			_wrong_left = MARK_S
			var a: Array = tubes[from]
			var b: Array = tubes[to]
			if a.is_empty():
				return "That tube is empty."
			if b.size() >= Rule.CAPACITY:
				return "That tube is full. Try another."
			if not b.is_empty() and int(b.back()) != int(a.back()):
				return "%s can only go onto %s." % [SHAPE_WORDS[int(a.back())], SHAPE_WORDS[int(a.back())].to_lower()]
			return "That pour does not work."
		"reset":
			return "The tubes are already at the start."
	return "That doesn't work here. Try something else."


func praise(move: Dictionary) -> String:
	match String(move.get("move", "")):
		"rack":
			return "All standing! Now sort them." if _all_racked() else "Back in the rack!"
		"pour":
			var to := int(move.get("value", 0)) % 10
			var tube: Array = (puzzle.tubes as Array)[to]
			if tube.size() == Rule.CAPACITY and tube.all(func(d: int) -> bool: return d == int(tube[0])):
				return "One kind sorted!"
			return ""
		"reset":
			return "Back to the start."
	return ""


func solved_text() -> String:
	return "The samples are sorted!"


func first_focus() -> Control:
	if pending or succeeded or puzzle.is_empty() or tube_buttons.is_empty():
		return super.first_focus()
	for i in Rule.TUBES:
		if not bool(puzzle.racked[i]):
			return tube_buttons[i]
	return tube_buttons[0]


func _process(delta: float) -> void:
	super._process(delta)
	if bench == null or puzzle.is_empty():
		return
	_calm = wants_less_motion()
	_wrong_left = maxf(0.0, _wrong_left - delta)
	if _wrong_left <= 0.0:
		_wrong = -1
	for i in _lift.size():
		var up := 1.0 if i == selected else 0.0
		_lift[i] = up if _calm else move_toward(_lift[i], up, delta / 0.18)
	if not _pour.is_empty():
		_pour.t = float(_pour.t) + delta
		if _calm or float(_pour.t) >= POUR_S:
			_pour = {}
	if is_visible_in_tree():
		bench.queue_redraw()


# ---------------------------------------------------------------- layout (relative to the bench's size)

func _rack_rect() -> Rect2:
	var s := bench.size
	var m := 16.0
	var rw := minf(s.x * 0.64, (s.y * 0.86 - m) / 0.55)
	var rh := rw / 3.4
	var x := m + (s.x * 0.72 - m - rw) * 0.5
	return Rect2(x, s.y - m - rh, rw, rh)


func _tube_size() -> Vector2:
	var rack := _rack_rect()
	var w := rack.size.x * (HOLE_X[1] - HOLE_X[0]) / RACK_TEX.x * 0.8
	# As tall as the bench allows (room above for the lift and the tick), up to a third longer than the sprite.
	var natural := w * TUBE_TEX.y / TUBE_TEX.x
	var room := rack.position.y + HOLE_Y / RACK_TEX.y * rack.size.y - bench.size.y * 0.17 - w * 0.6
	return Vector2(w, clampf(room, natural, natural * 1.35))


## The foot of tube i standing in its slot.
func _slot_foot(i: int) -> Vector2:
	var rack := _rack_rect()
	return rack.position + Vector2(HOLE_X[i] / RACK_TEX.x * rack.size.x, HOLE_Y / RACK_TEX.y * rack.size.y + 2.0)


func _mat_rect() -> Rect2:
	var s := bench.size
	return Rect2(s.x * 0.75, s.y * 0.08, s.x * 0.22, s.y * 0.84)


## Where fallen tube i lies on the mat (its order among the fallen tubes).
func _lying_centre(i: int) -> Vector2:
	var mat := _mat_rect()
	var n := 0
	for j in i:
		if not bool(puzzle.racked[j]):
			n += 1
	return Vector2(mat.get_center().x, mat.position.y + mat.size.y * (0.2 + 0.3 * float(n)))


func _lying_size() -> Vector2:
	var tube := _tube_size()
	var length := minf(tube.y, _mat_rect().size.x * 0.86)
	return Vector2(minf(tube.x, length * 0.42), length)


## The axis-aligned box of tube i as it is drawn now (standing, lifted, or lying).
func _tube_rect(i: int) -> Rect2:
	if not bool(puzzle.racked[i]):
		var lie := _lying_size()
		return Rect2(_lying_centre(i) - Vector2(lie.y, lie.x) * 0.5, Vector2(lie.y, lie.x))
	var t := _tube_size()
	var foot := _slot_foot(i)
	return Rect2(foot.x - t.x * 0.5, foot.y - t.y, t.x, t.y)


func _lift_px() -> float:
	return _tube_size().y * 0.16


func _place() -> void:
	if bench == null or puzzle.is_empty() or bench.size.x < 8.0:
		return
	for i in Rule.TUBES:
		var r := _tube_rect(i)
		if bool(puzzle.racked[i]):
			r = r.grow_individual(4.0, _lift_px(), 4.0, 0.0)
		tube_buttons[i].position = r.position
		tube_buttons[i].size = r.size


# ---------------------------------------------------------------- drawing

func _paint(c: Control) -> void:
	if puzzle.is_empty():
		return
	var area := Rect2(Vector2.ZERO, c.size)
	Kit.bay(c, area)
	Kit.housing(c, area.grow(-9.0), 14.0)
	var tubes: Array = puzzle.tubes
	var racked: Array = puzzle.racked
	var mat := _mat_rect()
	Kit.box(c, mat.grow(6.0), Kit.HOUSING_DARK, 16.0)
	Kit.draw_fill(c, Kit.tex("samples/bench_mat"), mat.grow(3.0))
	var rack := _rack_rect()
	Kit.draw_fill(c, Kit.tex("samples/tube_rack"), rack)
	_paint_strip(c, rack, tubes)
	var t := _tube_size()
	var all_in := _all_racked()
	var valid := _destinations()
	# Ghost outlines where the fallen tubes go.
	for i in Rule.TUBES:
		if not bool(racked[i]):
			var r := _tube_rect_standing(i)
			Kit.box(c, r, Color(1, 1, 1, 0.08), t.x * 0.45, Color(1, 1, 1, 0.55), 2.0)
	# The tubes: the lifted one last, so it is drawn over its neighbours.
	var order: Array = range(Rule.TUBES)
	if selected >= 0:
		order.erase(selected)
		order.append(selected)
	for i: int in order:
		var tube: Array = tubes[i]
		if not bool(racked[i]):
			var lie := _lying_size()
			_draw_tube(c, _lying_centre(i) + _shake(i), lie, -PI * 0.5, tube)
			continue
		var foot := _slot_foot(i) + Vector2(0.0, -_lift_px() * _lift[i]) + _shake(i)
		var angle := _tilt(i)
		# Turn about the foot: the centre swings with it.
		var centre := foot + Vector2(0.0, -t.y * 0.5).rotated(angle)
		_draw_tube(c, centre, t, angle, tube)
		if tube.size() == Rule.CAPACITY and tube.all(func(d: int) -> bool: return d == int(tube[0])):
			Kit.tick(c, Vector2(_slot_foot(i).x, _slot_foot(i).y - t.y - t.x * 0.32), t.x * 0.26)
	_paint_pour(c)
	# The shared marks.
	for i in Rule.TUBES:
		var r := _mark_rect(i)
		var radius := minf(r.size.x, r.size.y) * 0.45
		if not all_in and not bool(racked[i]):
			Kit.target_ring(c, r, radius, _calm)
		elif i in valid:
			Kit.target_ring(c, r, radius, _calm)
		if i == _hover and not tube_buttons[i].has_focus() and not succeeded:
			Kit.box(c, r, Color(1, 1, 1, 0.06), radius, Color(1, 1, 1, 0.5), 2.0)
		if tube_buttons[i].has_focus() or i == selected:
			Kit.focus_ring(c, r, radius, 4.0)
		if i == _wrong:
			Kit.cross(c, r.get_center() + _shake(i), t.x * 0.26)


func _tube_rect_standing(i: int) -> Rect2:
	var t := _tube_size()
	var foot := _slot_foot(i)
	return Rect2(foot.x - t.x * 0.5, foot.y - t.y, t.x, t.y)


## The box the rings go round: the tube as drawn now (lifted when selected).
func _mark_rect(i: int) -> Rect2:
	var r := _tube_rect(i)
	if bool(puzzle.racked[i]):
		r.position.y -= _lift_px() * _lift[i]
	return r.grow(4.0)


## The tubes tube `selected` may pour into (the rule's own test; a hint, not a decision).
func _destinations() -> Array:
	var out: Array = []
	if selected < 0 or succeeded or not _all_racked():
		return out
	for i in Rule.TUBES:
		if i != selected and Rule.can_pour(puzzle.tubes, selected, i):
			out.append(i)
	return out


## The lifted tube leans toward the tube the player points at (or pours into).
func _tilt(i: int) -> float:
	var toward := -1
	if not _pour.is_empty() and int(_pour.from) == i:
		toward = int(_pour.to)
	elif i == selected:
		var at := _hover
		for j in Rule.TUBES:
			if tube_buttons[j].has_focus():
				at = j
		if at in _destinations():
			toward = at
	if toward < 0:
		return 0.0
	var lean := 0.22 * (_lift[i] if _pour.is_empty() else 1.0)
	return lean * signf(_slot_foot(toward).x - _slot_foot(i).x)


func _shake(i: int) -> Vector2:
	return Vector2(sin(_wrong_left * 40.0) * 4.0 * (_wrong_left / MARK_S), 0.0) if i == _wrong and not _calm else Vector2.ZERO


## One tube: the glass, the doses in it bottom first, a soft shine over them. `size` is the upright tube's size.
func _draw_tube(c: Control, centre: Vector2, size: Vector2, angle: float, layers: Array) -> void:
	var k := size.x / TUBE_TEX.x
	c.draw_set_transform(centre, angle, Vector2.ONE)
	var origin := -size * 0.5
	c.draw_texture_rect(Kit.tex("samples/test_tube_glass"), Rect2(origin, size), false)
	var inner_w := (TUBE_INNER_X.y - TUBE_INNER_X.x) * k
	var dose_h := inner_w * DOSE_SRC.size.y / DOSE_SRC.size.x
	# The floor stays at its place in the (maybe longer) tube; the doses keep their own shape.
	var floor_y := origin.y + size.y - (TUBE_TEX.y - TUBE_FLOOR) * k
	for d in layers.size():
		var id := int(layers[d])
		var rect := Rect2(origin.x + TUBE_INNER_X.x * k, floor_y - dose_h * float(d + 1), inner_w, dose_h)
		_draw_dose(c, rect, id)
	c.draw_rect(Rect2(origin + Vector2(size.x * 0.24, size.y * 0.1), Vector2(size.x * 0.08, size.y * 0.75)), Color(1, 1, 1, 0.22))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_dose(c: Control, rect: Rect2, id: int) -> void:
	var path: String = DOSE_TEX[id] if id >= 0 and id < DOSE_TEX.size() else ""
	var tex := Kit.tex(path) if not path.is_empty() else null
	if tex != null:
		c.draw_texture_rect_region(tex, rect, DOSE_SRC)
		return
	# The fourth liquid has no sprite: a purple band with a pale diamond outline, in the same style.
	var col: Color = LIQUID[clampi(id, 0, LIQUID.size() - 1)]
	c.draw_rect(rect.grow(-1.0), col)
	var pts := Kit.shape_points(Kit.DIAMOND, rect.get_center(), rect.size.y * 0.3)
	pts.append(pts[0])
	c.draw_polyline(pts, Color(0.95, 0.92, 0.85), maxf(2.0, rect.size.y * 0.07), true)


## The strip on the rack's front: the kinds of liquid in play, each a coloured shape.
func _paint_strip(c: Control, rack: Rect2, tubes: Array) -> void:
	var used: Array = []
	for t: Array in tubes:
		for d: Variant in t:
			if not used.has(int(d)):
				used.append(int(d))
	used.sort()
	var r := rack.size.y * 0.1
	var w := r * 3.0 * float(used.size()) + r
	var at := Rect2(rack.get_center().x - w * 0.5, rack.position.y + rack.size.y * 0.6, w, r * 2.8)
	Kit.box(c, at, Kit.METAL_DARK, r * 1.4, Kit.INK, 2.0)
	for n in used.size():
		var id: int = used[n]
		Kit.shape(c, LIQUID_SHAPE[id], Vector2(at.position.x + r * 2.0 + r * 3.0 * float(n), at.get_center().y), r, LIQUID[id].lightened(0.15))


## A dose flying from one mouth to the other.
func _paint_pour(c: Control) -> void:
	if _pour.is_empty():
		return
	var t := _tube_size()
	var a := _slot_foot(int(_pour.from)) + Vector2(0.0, -t.y - _lift_px() * 0.5)
	var b := _slot_foot(int(_pour.to)) + Vector2(0.0, -t.y)
	var top := Vector2((a.x + b.x) * 0.5, minf(a.y, b.y) - t.y * 0.18)
	var f := clampf(float(_pour.t) / POUR_S, 0.0, 1.0)
	var pts := PackedVector2Array()
	for s in 13:
		var u := float(s) / 12.0 * f
		pts.append(a.lerp(top, u).lerp(top.lerp(b, u), u))
	var col: Color = LIQUID[clampi(int(_pour.id), 0, LIQUID.size() - 1)]
	c.draw_polyline(pts, Kit.INK, t.x * 0.2, true)
	c.draw_polyline(pts, col, t.x * 0.14, true)
	if pts.size() > 0:
		Kit.shape(c, LIQUID_SHAPE[int(_pour.id)], pts[pts.size() - 1], t.x * 0.13, col.lightened(0.2))
