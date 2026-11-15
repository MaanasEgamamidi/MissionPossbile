extends "res://scripts/tasks/puzzles/med_ui.gd"
## T12 Seal mini-game (airlock exit-tunnel inner door, field engineer). Step 1: find the leaking part of the door edge
## by the white vapour. Step 2: pick the seal as wide as the gap. Step 3: press the seal down point by point in the
## numbered order. Step 4: pressure check. The host rule (t12_rule.gd) decides; completion clears the T12 seal fault,
## which is what the S04 airlock pressure (LocalPressure) reads, so the vestibule fills back up with air.
## Safe side: the panel says to work from the hangar side of the inner door or in a working suit. It never pauses the
## hazard: an unprotected player in the vestibule still gets the 4 s warning, and a critical alert closes this panel.
## Keyboard: Tab / arrows through the buttons of the current step, Enter / Space to use one. Focusing a door part
## also tells, in words, whether air blows out there (so the vapour is never a colour-only cue).

const Rule := preload("res://scripts/tasks/puzzles/t12_rule.gd")
const DOOR := Color(0.6, 0.62, 0.64)
const FRAME := Color(0.13, 0.14, 0.16)
const STRIPE := Color(0.86, 0.6, 0.18)
const SEAL := Color(0.08, 0.08, 0.09)

var door_box: Control
var safety_label: Label
var feel_label: Label
var step_labels: Array[Label] = []
var step_groups: Array[Control] = []
var section_buttons: Array[Button] = []
var seal_buttons: Array[Button] = []
var press_buttons: Array[Button] = []
var test_button: Button
var gap_label: Label
var _focus_section := -1
var _time := 0.0


func rule_script() -> Script:
	return Rule


func setup(p_services: GameServices) -> void:
	instructions = "Air is leaking out around the airlock's inner door. Find where the white vapour puffs out, fit a new seal that is as wide as the gap, press it down in the numbered order, then check the pressure."
	super.setup(p_services)
	name = "T12SealPanel"


func build_game() -> void:
	safety_label = _label("Safety", UiTheme.WARN)
	play_area.add_child(safety_label)
	door_box = make_box("Door", Vector2(320, 250), _paint_door)
	play_area.add_child(door_box)
	feel_label = _label("FeelForAir", UiTheme.MUTED)
	play_area.add_child(feel_label)
	var titles := ["Step 1: find the leak", "Step 2: fit the new seal", "Step 3: press the seal down", "Step 4: pressure check"]
	for k in titles.size():
		var heading := _label("Step%dTitle" % (k + 1), UiTheme.HEADING)
		heading.text = titles[k]
		play_area.add_child(heading)
		step_labels.append(heading)
		var grid := GridContainer.new()
		grid.name = "Step%d" % (k + 1)
		grid.columns = 3 if k == 0 else (3 if k == 1 else (5 if k == 2 else 1))
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play_area.add_child(grid)
		step_groups.append(grid)
	for s in Rule.SECTIONS.size():
		var b := make_button("Section%d" % (s + 1), "%d  %s" % [s + 1, Rule.SECTIONS[s]])
		b.pressed.connect(send.bind("find", s))
		b.focus_entered.connect(_feel.bind(s))
		b.mouse_entered.connect(_feel.bind(s))
		b.focus_exited.connect(_feel.bind(-1))
		step_groups[0].add_child(b)
		section_buttons.append(b)
	gap_label = _label("Gap")
	play_area.add_child(gap_label)
	play_area.move_child(gap_label, step_groups[1].get_index())
	for k in Rule.SEALS.size():
		var b := make_button("Seal%d" % (k + 1), Rule.SEALS[k])
		b.pressed.connect(send.bind("fit", k))
		step_groups[1].add_child(b)
		seal_buttons.append(b)
	for p in Rule.POINTS:
		var b := make_button("Point%d" % (p + 1), "")
		b.pressed.connect(send.bind("press", p))
		step_groups[2].add_child(b)
		press_buttons.append(b)
	test_button = make_button("PressureCheck", "Check the pressure", true)
	test_button.pressed.connect(send.bind("test", 0))
	step_groups[3].add_child(test_button)


func _process(delta: float) -> void:
	super._process(delta)
	_time += delta
	if door_box != null and is_visible_in_tree() and not puzzle.is_empty() and not bool(puzzle.fitted):
		door_box.queue_redraw()


func refresh() -> void:
	super.refresh()
	_update_safety()


func _update_safety() -> void:
	if safety_label == null or services == null or not services.has_game():
		return
	var info: Dictionary = services.session.survival.pressure_info()
	safety_label.text = "Exit vestibule: %.0f kPa, %s. Work from the hangar side of the inner door, or wear a working suit if you must step inside." % [float(info.get("pressure_kpa", 0.0)), String(info.get("status", "")).to_lower()]
	safety_label.theme_type_variation = UiTheme.GOOD if bool(info.get("breathable", true)) else UiTheme.WARN


func _feel(section: int) -> void:
	_focus_section = section
	if feel_label == null or puzzle.is_empty():
		return
	if section < 0 or bool(puzzle.found):
		feel_label.text = ""
	elif section == int(puzzle.leak):
		feel_label.text = "%s: a cold breeze and lots of white vapour here!" % Rule.SECTIONS[section]
	else:
		feel_label.text = "%s: no breeze, no vapour." % Rule.SECTIONS[section]
	if door_box != null:
		door_box.queue_redraw()


func _phase() -> int:
	if not bool(puzzle.found):
		return 0
	if not bool(puzzle.fitted):
		return 1
	if int(puzzle.pressed) < Rule.POINTS:
		return 2
	return 3


func redraw() -> void:
	if puzzle.is_empty():
		return
	_update_safety()
	var phase := _phase()
	var leak := int(puzzle.leak)
	var had_focus := get_viewport() != null and get_viewport().gui_get_focus_owner() != null and is_ancestor_of(get_viewport().gui_get_focus_owner())
	for k in step_groups.size():
		step_groups[k].visible = k == phase and not succeeded
		step_labels[k].text = step_labels[k].text.trim_suffix(" (done)") + (" (done)" if k < phase or succeeded else "")
	gap_label.visible = phase >= 1
	gap_label.text = "The gap in the %s is %d mm wide." % [Rule.SECTIONS[leak], int(Rule.GAP_MM[int(puzzle.gap)])] if phase >= 1 else ""
	for p in Rule.POINTS:
		var n := Rule.order_number(puzzle, p)
		var pressed := n <= int(puzzle.pressed)
		press_buttons[p].text = "%d %s" % [n, "pressed" if pressed else _point_words(leak, p)]
	if phase != 0:
		feel_label.text = ""
	door_box.queue_redraw()
	# Keep keyboard play going when the step's buttons change.
	if had_focus:
		var focus := get_viewport().gui_get_focus_owner()
		if focus == null or not focus.is_visible_in_tree():
			_focus_current_step()


func _focus_current_step() -> void:
	var group := step_groups[_phase()]
	for child in group.get_children():
		if child is Button and (child as Button).is_visible_in_tree():
			(child as Button).grab_focus()
			return
	cancel_button.grab_focus()


func first_focus() -> Control:
	if pending or puzzle.is_empty() or succeeded:
		return super.first_focus()
	var group := step_groups[_phase()]
	return group.get_child(0) as Control if group.get_child_count() > 0 else super.first_focus()


func _point_words(leak: int, p: int) -> String:
	var vertical: bool = Rule.VERTICAL[leak]
	if p == 0:
		return "(top end)" if vertical else "(left end)"
	if p == Rule.POINTS - 1:
		return "(bottom end)" if vertical else "(right end)"
	return "(middle)" if p == Rule.POINTS / 2 else ""


func explain(move: Dictionary) -> String:
	var payload := int(move.get("value", 0))
	match String(move.get("move", "")):
		"find":
			if payload < Rule.SECTIONS.size():
				return "No vapour comes out at the %s. Look for the white puffs, or check each part for a breeze." % Rule.SECTIONS[payload].to_lower()
		"fit":
			if payload < Rule.SEALS.size():
				var gap := int(Rule.GAP_MM[int(puzzle.gap)])
				var size := int(Rule.GAP_MM[payload])
				return "The %s is too %s for a %d mm gap. Pick the seal as wide as the gap." % [Rule.SEALS[payload].to_lower(), "thin" if size < gap else "thick", gap]
		"press":
			return "Press point %d next, so no air bubble gets trapped under the seal." % (int(puzzle.pressed) + 1)
		"test":
			return "Press the whole seal down first."
		"reset":
			return "Nothing to undo yet."
	return "That doesn't work here. Try something else."


func praise(move: Dictionary) -> String:
	match String(move.get("move", "")):
		"find":
			return "Found it! Air is rushing out of the %s. The gap is %d mm wide: pick a seal that fits." % [Rule.SECTIONS[int(puzzle.leak)].to_lower(), int(Rule.GAP_MM[int(puzzle.gap)])]
		"fit":
			return "The new seal fits. Now press it down, starting at number 1."
		"press":
			if int(puzzle.pressed) >= Rule.POINTS:
				return "The whole edge is sealed. Now check the pressure."
			return "Pressed %d of %d." % [int(puzzle.pressed), Rule.POINTS]
		"reset":
			return "Seal peeled off. Find the leak again."
	return "Done."


func solved_text() -> String:
	return "Fixed! The seal holds. The leak has stopped and the vestibule is filling back up with air."


## Door edge sections in the door picture: [start, end] (start = top or left end).
func _segments(r: Rect2) -> Array:
	var cx := r.get_center().x
	var mid := r.get_center().y
	return [[r.position, Vector2(r.end.x, r.position.y)], [r.position, Vector2(r.position.x, r.end.y)],
		[Vector2(cx, r.position.y), Vector2(cx, mid)], [Vector2(cx, mid), Vector2(cx, r.end.y)],
		[Vector2(r.end.x, r.position.y), r.end], [Vector2(r.position.x, r.end.y), r.end]]


func _paint_door(box: Control) -> void:
	if puzzle.is_empty():
		return
	var pal := UiTheme.palette()
	var w := minf(box.size.x, box.size.y * 1.3)
	var door := Rect2(Vector2((box.size.x - w * 0.8) * 0.5, 18.0), Vector2(w * 0.8, box.size.y - 36.0))
	box.draw_rect(door.grow(12.0), FRAME)
	box.draw_rect(door, DOOR)
	box.draw_rect(Rect2(door.position.x, door.get_center().y + 10.0, door.size.x, 10.0), STRIPE)
	for side in 2:
		var x := door.position.x + door.size.x * (0.12 + 0.5 * side)
		box.draw_rect(Rect2(x, door.position.y + 20.0, door.size.x * 0.26, door.size.y * 0.22), Color(0.2, 0.21, 0.24))
	var segs := _segments(door)
	var leak := int(puzzle.leak)
	for s in segs.size():
		var a: Vector2 = segs[s][0]
		var b: Vector2 = segs[s][1]
		var focused := s == _focus_section and not bool(puzzle.found)
		box.draw_line(a, b, pal.focus if focused else Color(0.3, 0.32, 0.35), 6.0 if focused else 3.0)
		draw_text_centered(box, str(s + 1), (a + b) * 0.5 + _label_offset(s), 15, pal.text)
	var la: Vector2 = segs[leak][0]
	var lb: Vector2 = segs[leak][1]
	if bool(puzzle.fitted):
		box.draw_line(la, lb, SEAL, 9.0)
		for p in Rule.POINTS:
			var at := la.lerp(lb, (float(p) + 0.5) / float(Rule.POINTS))
			var n := Rule.order_number(puzzle, p)
			var done := n <= int(puzzle.pressed)
			box.draw_circle(at, 11.0, pal.good if done else Color(0.95, 0.95, 0.95))
			draw_text_centered(box, str(n), at, 13, Color(0.05, 0.05, 0.06))
		return
	# White vapour puffs drift out of the gap (shape and motion, not colour, show where).
	var away := Vector2(0, -1) if leak == 0 else (Vector2(0, 1) if leak == 5 else (Vector2(-1, 0) if leak == 1 else Vector2(1, 0)))
	if leak in [2, 3]:
		away = Vector2(0.6, -0.2)
	for k in 7:
		var t := fmod(_time * 0.6 + float(k) / 7.0, 1.0)
		var base := la.lerp(lb, fmod(float(k) * 0.37, 1.0))
		var at := base + away * (6.0 + 46.0 * t) + Vector2(sin(_time * 2.0 + k) * 4.0, 0)
		box.draw_circle(at, 5.0 + 9.0 * t, Color(1, 1, 1, 0.75 * (1.0 - t)))


func _label_offset(s: int) -> Vector2:
	match s:
		0: return Vector2(0, -12)
		1: return Vector2(-14, 0)
		4: return Vector2(14, 0)
		5: return Vector2(0, 12)
	return Vector2(-12, 0)
