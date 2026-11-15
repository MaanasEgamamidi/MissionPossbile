extends "res://scripts/tasks/puzzles/med_ui.gd"
## T12 Seal mini-game (airlock exit-tunnel inner door, field engineer). Owner, 2026-11-14: "instead of clicking buttons,
## you actually click on the 1, 2, 3, 4, 5 to seal it down. But there's also a time limit on it. So if you don't do it
## fast enough, then it will ask you to restart it."
## One picture: the real door (dark tunnel frame, yellow/black hazard jambs, two grey sliding leaves meeting at a centre
## seam, red warning light bar above) with white vapour puffing out of the leaking gap, and five big numbered seal
## points along that gap. Click 1 -> 2 -> 3 -> 4 -> 5; each right click is one host move ("press") and seals that part of
## the gap. A wrong number flashes red and sends nothing. The clock (TIME_LIMIT_S) starts at the first right click; if
## it runs out the vapour bursts back and the Restart button sends the host "reset". The host rule (t12_rule.gd)
## decides; pressing 5 completes the task, which clears the T12 seal fault that the S04 airlock pressure reads.
## Safe side: the panel says to work from the hangar side of the inner door or in a working suit. It never pauses the
## hazard: an unprotected player in the vestibule still gets the 4 s warning, and a critical alert closes this panel.
## Keyboard: Tab / arrows move across the five points, Enter / Space presses the focused one. The leak is named in
## words and the sealed points are dark (not only a colour change).

const Rule := preload("res://scripts/tasks/puzzles/t12_rule.gd")
## Designer balance: seconds to press all five once the first one is down.
const TIME_LIMIT_S := 10.0
const POINT_SIZE := 44.0
const DOOR_BOX := Vector2(380, 236)
const DOOR_W := 250.0
const DOOR := Color(0.6, 0.62, 0.64)
const DOOR_DARK := Color(0.47, 0.49, 0.52)
const FRAME := Color(0.13, 0.14, 0.16)
const TUNNEL := Color(0.045, 0.05, 0.06)
const STRIPE := Color(0.95, 0.76, 0.12)
const STRIPE_DARK := Color(0.06, 0.06, 0.07)
const SEAL := Color(0.08, 0.08, 0.09)
const LIGHT_RED := Color(0.92, 0.13, 0.1)
const LIGHT_GREEN := Color(0.25, 0.88, 0.4)
const FLASH := Color(0.88, 0.16, 0.12)
const FLASH_S := 0.6
const TIMEOUT_TEXT := "Too slow - the seal peeled off. Press Restart and try again."

var door_box: Control
var safety_label: Label
var leak_label: Label
## The five seal point buttons, by spot (0 = top or left end of the leaking edge).
var press_buttons: Array[Button] = []
var timer_row: HBoxContainer
var time_label: Label
var time_bar: ProgressBar
var timeout_row: HBoxContainer
var timeout_label: Label
var restart_button: Button
## The client-side clock: running from the first right press until 5 is pressed or the time is up.
var timer_running := false
var time_left := TIME_LIMIT_S
var timed_out := false
## The spot that flashes red after a wrong number (-1 = none).
var flash_spot := -1
var _flash_left := 0.0
var _burst := 0.0
var _time := 0.0


func rule_script() -> Script:
	return Rule


func setup(p_services: GameServices) -> void:
	instructions = "Air is leaking out of the door seal. Click the numbers 1 to 5 in order to press the new seal down. Be quick - you have %d seconds once you start!" % int(TIME_LIMIT_S)
	super.setup(p_services)
	name = "T12SealPanel"


func build_game() -> void:
	safety_label = _label("Safety", UiTheme.WARN)
	play_area.add_child(safety_label)
	leak_label = _label("Leak", UiTheme.MUTED)
	play_area.add_child(leak_label)
	door_box = make_box("Door", DOOR_BOX, _paint_door)
	door_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	door_box.clip_contents = true
	door_box.resized.connect(_layout_points)
	play_area.add_child(door_box)
	for spot in Rule.POINTS:
		var b := Button.new()
		b.name = "Point%d" % (spot + 1)
		b.flat = true
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.custom_minimum_size = Vector2(POINT_SIZE, POINT_SIZE)
		b.size = Vector2(POINT_SIZE, POINT_SIZE)
		b.pressed.connect(_on_point.bind(spot))
		b.draw.connect(_paint_point.bind(b, spot))
		door_box.add_child(b)
		press_buttons.append(b)
	# Arrows step along the edge in spot order (left / up = back, right / down = on); the ends find their own way out.
	for spot in Rule.POINTS:
		var b := press_buttons[spot]
		if spot > 0:
			b.focus_neighbor_left = NodePath("../Point%d" % spot)
			b.focus_neighbor_top = NodePath("../Point%d" % spot)
			b.focus_previous = NodePath("../Point%d" % spot)
		if spot < Rule.POINTS - 1:
			b.focus_neighbor_right = NodePath("../Point%d" % (spot + 2))
			b.focus_neighbor_bottom = NodePath("../Point%d" % (spot + 2))
			b.focus_next = NodePath("../Point%d" % (spot + 2))
	timer_row = HBoxContainer.new()
	timer_row.name = "TimerRow"
	play_area.add_child(timer_row)
	time_label = _label("TimeLeft", UiTheme.HEADING)
	time_label.size_flags_horizontal = Control.SIZE_FILL
	time_label.custom_minimum_size = Vector2(300, 0)
	time_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	timer_row.add_child(time_label)
	time_bar = ProgressBar.new()
	time_bar.name = "TimeBar"
	time_bar.max_value = TIME_LIMIT_S
	time_bar.step = 0.0
	time_bar.show_percentage = false
	time_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	time_bar.custom_minimum_size = Vector2(0, 18)
	timer_row.add_child(time_bar)
	timeout_row = HBoxContainer.new()
	timeout_row.name = "TimeoutRow"
	timeout_row.visible = false
	play_area.add_child(timeout_row)
	timeout_label = _label("TimeoutMessage", UiTheme.URGENT)
	timeout_label.text = TIMEOUT_TEXT
	timeout_row.add_child(timeout_label)
	restart_button = make_button("Restart", "Restart", true)
	restart_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	restart_button.custom_minimum_size = Vector2(200, 52)
	restart_button.pressed.connect(_on_restart)
	timeout_row.add_child(restart_button)
	# The clock and the Restart row go above the door, so they are on screen at 1280x720 without scrolling.
	play_area.move_child(timer_row, door_box.get_index())
	play_area.move_child(timeout_row, door_box.get_index())
	_update_timer_view()


func _process(delta: float) -> void:
	super._process(delta)
	_time += delta
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0 and flash_spot >= 0:
			var was := flash_spot
			flash_spot = -1
			press_buttons[was].queue_redraw()
		elif flash_spot >= 0:
			press_buttons[flash_spot].queue_redraw()
	if timed_out:
		_burst += delta
	if timer_running and not succeeded and not puzzle.is_empty():
		time_left = maxf(0.0, time_left - delta)
		if time_left <= 0.0 and not pending and int(puzzle.pressed) < Rule.POINTS:
			_time_up()
		_update_timer_view()
	if door_box != null and is_visible_in_tree():
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


# ---------------------------------------------------------------- play

func _on_point(spot: int) -> void:
	if puzzle.is_empty() or pending or succeeded or timed_out:
		return
	var pressed := int(puzzle.pressed)
	var n := Rule.order_number(puzzle, spot)
	if n <= pressed:
		hint("Number %d is already pressed down. Find number %d!" % [n, pressed + 1])
		return
	if n != pressed + 1:
		# Wrong number: a short red flash, nothing goes to the host, no penalty.
		flash_spot = spot
		_flash_left = FLASH_S
		press_buttons[spot].queue_redraw()
		hint("That's number %d. %s" % [n, "Start with number 1!" if pressed == 0 else "Find number %d first!" % (pressed + 1)])
		return
	send("press", n)


func _on_restart() -> void:
	if not timed_out or pending or succeeded:
		return
	send("reset", 0)


func _time_up() -> void:
	timer_running = false
	timed_out = true
	time_left = 0.0
	_burst = 0.0
	var had_focus := _panel_has_focus()
	status_label.text = TIMEOUT_TEXT
	status_label.theme_type_variation = UiTheme.URGENT
	_update_timer_view()
	_update_enabled()
	for b in press_buttons:
		b.queue_redraw()
	if had_focus:
		restart_button.grab_focus()


func _update_timer_view() -> void:
	if timer_row == null:
		return
	timeout_row.visible = timed_out and not succeeded
	timer_row.visible = not timeout_row.visible
	time_bar.value = time_left
	var pressed := 0 if puzzle.is_empty() else int(puzzle.pressed)
	if succeeded or pressed >= Rule.POINTS:
		time_label.text = "Sealed with %.1f s to spare!" % time_left
	elif timer_running:
		time_label.text = "Time left: %.1f s" % time_left
	else:
		time_label.text = "%d seconds. The clock starts at number 1." % int(TIME_LIMIT_S)
	time_bar.theme_type_variation = UiTheme.BAR_GOOD if time_left > TIME_LIMIT_S * 0.5 else (UiTheme.BAR_WARN if time_left > TIME_LIMIT_S * 0.25 else UiTheme.BAR_URGENT)


func _update_enabled() -> void:
	super._update_enabled()
	for b in press_buttons:
		b.disabled = b.disabled or timed_out
	if restart_button != null:
		restart_button.disabled = pending or succeeded or not timed_out


func _panel_has_focus() -> bool:
	var vp := get_viewport()
	return vp != null and vp.gui_get_focus_owner() != null and is_ancestor_of(vp.gui_get_focus_owner())


func redraw() -> void:
	if puzzle.is_empty():
		return
	_update_safety()
	var had_focus := _panel_has_focus()
	var pressed := int(puzzle.pressed)
	if pressed == 0:
		timer_running = false
		timed_out = false
		time_left = TIME_LIMIT_S
	elif pressed >= Rule.POINTS or succeeded:
		timer_running = false
		timed_out = false
	elif not timer_running and not timed_out:
		# The first right press (or a half-done seal picked up again) starts the clock.
		timer_running = true
		time_left = TIME_LIMIT_S
	var section: String = Rule.SECTIONS[int(puzzle.leak)]
	if succeeded or pressed >= Rule.POINTS:
		leak_label.text = "The %s is sealed. No more air is leaking out." % section.to_lower()
	else:
		leak_label.text = "Air is hissing out of the %s of the door. %d of %d seal points pressed." % [section.to_lower(), pressed, Rule.POINTS]
	for spot in Rule.POINTS:
		var n := Rule.order_number(puzzle, spot)
		press_buttons[spot].tooltip_text = "Seal point %d%s" % [n, " (pressed down)" if n <= pressed else ""]
		press_buttons[spot].queue_redraw()
	_layout_points()
	_update_timer_view()
	_update_enabled()
	door_box.queue_redraw()
	# Keep keyboard play going when the Restart row comes or goes.
	if had_focus:
		var focus := get_viewport().gui_get_focus_owner()
		if focus == null or not focus.is_visible_in_tree():
			var next := first_focus()
			if next != null:
				next.grab_focus()


func first_focus() -> Control:
	if pending or puzzle.is_empty() or succeeded or press_buttons.is_empty():
		return super.first_focus()
	if timed_out:
		return restart_button
	return press_buttons[0]


func explain(move: Dictionary) -> String:
	match String(move.get("move", "")):
		"press":
			return "Press number %d next." % (int(puzzle.pressed) + 1)
		"reset":
			return "Nothing to restart yet."
	return "That doesn't work here. Try something else."


func praise(move: Dictionary) -> String:
	match String(move.get("move", "")):
		"press":
			var pressed := int(puzzle.pressed)
			if pressed == 1:
				return "Number 1 is down. The clock is running - find number 2!"
			return "Pressed %d of %d. Now find number %d!" % [pressed, Rule.POINTS, pressed + 1]
		"reset":
			return "The old seal is off. Start again at number 1 - be quick!"
	return "Done."


func solved_text() -> String:
	return "Fixed! The seal holds. The leak has stopped and the vestibule is filling back up with air."


# ---------------------------------------------------------------- drawing

## The door opening inside the picture.
func _door_rect(box_size: Vector2) -> Rect2:
	return Rect2(Vector2((box_size.x - DOOR_W) * 0.5, 44.0), Vector2(DOOR_W, box_size.y - 64.0))


## Door edge sections in the door picture: [start, end] (start = top or left end).
func _segments(r: Rect2) -> Array:
	var cx := r.get_center().x
	var mid := r.get_center().y
	return [[r.position, Vector2(r.end.x, r.position.y)], [r.position, Vector2(r.position.x, r.end.y)],
		[Vector2(cx, r.position.y), Vector2(cx, mid)], [Vector2(cx, mid), Vector2(cx, r.end.y)],
		[Vector2(r.end.x, r.position.y), r.end], [Vector2(r.position.x, r.end.y), r.end]]


## The point on the gap that `spot` seals.
func _gap_point(box_size: Vector2, spot: int) -> Vector2:
	var seg: Array = _segments(_door_rect(box_size))[int(puzzle.leak)]
	return (seg[0] as Vector2).lerp(seg[1], (float(spot) + 0.5) / float(Rule.POINTS))


## Centre of the round button for `spot`: on the gap for flat edges, zig-zagging either side of it for upright ones (so
## five 44 px circles fit on half a seam).
func _point_center(box_size: Vector2, spot: int) -> Vector2:
	var at := _gap_point(box_size, spot)
	if bool(Rule.VERTICAL[int(puzzle.leak)]):
		at.x += -24.0 if spot % 2 == 0 else 24.0
	var half := POINT_SIZE * 0.5 + 1.0
	return Vector2(clampf(at.x, half, box_size.x - half), clampf(at.y, half, box_size.y - half))


func _layout_points() -> void:
	if door_box == null or puzzle.is_empty():
		return
	for spot in press_buttons.size():
		var b := press_buttons[spot]
		b.size = Vector2(POINT_SIZE, POINT_SIZE)
		b.position = _point_center(door_box.size, spot) - b.size * 0.5


## Which way the vapour drifts out of each section.
func _away(leak: int) -> Vector2:
	match leak:
		0: return Vector2(0, -1)
		1: return Vector2(-1, -0.3).normalized()
		4: return Vector2(1, -0.3).normalized()
		5: return Vector2(0.15, -1).normalized()
	return Vector2(0.55, -0.45).normalized()


func _paint_door(box: Control) -> void:
	if puzzle.is_empty():
		return
	var door := _door_rect(box.size)
	var leak := int(puzzle.leak)
	var pressed := int(puzzle.pressed)
	var done := succeeded or pressed >= Rule.POINTS
	# Tunnel and frame.
	box.draw_rect(Rect2(Vector2.ZERO, box.size), TUNNEL)
	var frame := Rect2(door.position - Vector2(46, 28), door.size + Vector2(92, 44))
	box.draw_rect(frame, FRAME)
	# Red warning light bar above the door (green once sealed); a soft pulse while it leaks.
	var bar := Rect2(Vector2(box.size.x * 0.5 - 80.0, 6.0), Vector2(160, 14))
	var light := LIGHT_GREEN if done else LIGHT_RED
	var pulse := 0.5 if done else 0.35 + 0.25 * sin(_time * 5.0)
	box.draw_rect(bar.grow(5.0), Color(light, 0.18 * pulse + 0.08))
	box.draw_rect(bar.grow(2.0), Color(0.05, 0.05, 0.06))
	box.draw_rect(bar, light)
	box.draw_rect(Rect2(bar.position + Vector2(4, 3), Vector2(bar.size.x - 8, 3)), Color(1, 1, 1, 0.35))
	# Hazard-striped jambs either side of the opening.
	var jamb_w := 34.0
	for side in 2:
		var jamb := Rect2(Vector2(door.position.x - jamb_w if side == 0 else door.end.x, door.position.y), Vector2(jamb_w, door.size.y))
		_paint_stripes(box, jamb)
	# Lintel and sill.
	box.draw_rect(Rect2(Vector2(door.position.x - jamb_w, door.position.y - 18.0), Vector2(door.size.x + jamb_w * 2.0, 18)), Color(0.19, 0.2, 0.22))
	box.draw_rect(Rect2(Vector2(door.position.x - jamb_w, door.end.y), Vector2(door.size.x + jamb_w * 2.0, 14)), Color(0.19, 0.2, 0.22))
	# Two grey sliding leaves meeting at the centre seam.
	var half_w := door.size.x * 0.5
	for side in 2:
		var leaf := Rect2(Vector2(door.position.x + half_w * side, door.position.y), Vector2(half_w, door.size.y))
		box.draw_rect(leaf, DOOR)
		box.draw_rect(Rect2(leaf.position, Vector2(leaf.size.x, 6)), Color(0.7, 0.72, 0.74))
		var outer_x := leaf.position.x if side == 0 else leaf.end.x - 8.0
		box.draw_rect(Rect2(Vector2(outer_x, leaf.position.y), Vector2(8, leaf.size.y)), DOOR_DARK)
		var window := Rect2(leaf.position + Vector2(leaf.size.x * 0.22, 26.0), Vector2(leaf.size.x * 0.56, leaf.size.y * 0.2))
		box.draw_rect(window.grow(3.0), DOOR_DARK)
		box.draw_rect(window, Color(0.16, 0.2, 0.26))
		box.draw_line(window.position + Vector2(6, window.size.y - 6), window.position + Vector2(window.size.x * 0.4, 6), Color(1, 1, 1, 0.15), 3.0)
		for k in 3:
			var y := leaf.position.y + leaf.size.y * (0.56 + 0.07 * k)
			box.draw_line(Vector2(leaf.position.x + 14, y), Vector2(leaf.end.x - 14, y), DOOR_DARK, 2.0)
		var handle_x := leaf.end.x - 22.0 if side == 0 else leaf.position.x + 12.0
		box.draw_rect(Rect2(Vector2(handle_x, door.get_center().y - 18.0), Vector2(10, 36)), Color(0.32, 0.34, 0.37))
	box.draw_line(Vector2(door.get_center().x, door.position.y), Vector2(door.get_center().x, door.end.y), Color(0.2, 0.21, 0.23), 2.0)
	# The leaking gap, then the seal strip over each pressed part (peeled off when the time ran out).
	var seg: Array = _segments(door)[leak]
	var la: Vector2 = seg[0]
	var lb: Vector2 = seg[1]
	box.draw_line(la, lb, Color(0.02, 0.02, 0.03), 7.0)
	box.draw_line(la, lb, Color(0.75, 0.85, 0.95, 0.25), 2.0)
	var away := _away(leak)
	for spot in Rule.POINTS:
		var a := la.lerp(lb, float(spot) / float(Rule.POINTS))
		var b := la.lerp(lb, float(spot + 1) / float(Rule.POINTS))
		var sealed := done or Rule.order_number(puzzle, spot) <= pressed
		if sealed and not timed_out:
			box.draw_line(a, b, SEAL, 13.0)
			box.draw_line(a, b, Color(0.26, 0.27, 0.29), 2.0)
		elif sealed:
			box.draw_line(a + away * 7.0, b + away * 9.0, Color(0.3, 0.3, 0.32), 7.0)
	# Thin leader lines from the gap to the zig-zag points of an upright edge.
	if bool(Rule.VERTICAL[leak]):
		for spot in Rule.POINTS:
			var on_gap := _gap_point(box.size, spot)
			box.draw_line(on_gap, _point_center(box.size, spot), Color(0.05, 0.05, 0.06, 0.85), 3.0)
			box.draw_circle(on_gap, 3.0, Color(0.05, 0.05, 0.06))
	if done:
		return
	# Soft white vapour puffs out of every open part of the gap (and all of it bursts back when the time ran out).
	var burst := timed_out
	var per := 6 if burst else 3
	var speed := 1.3 if burst else 0.6
	for spot in Rule.POINTS:
		if not burst and Rule.order_number(puzzle, spot) <= pressed:
			continue
		for k in per:
			var t := fmod(_time * speed + float(k) / float(per) + float(spot) * 0.21, 1.0)
			var along := (float(spot) + 0.15 + 0.7 * fmod(float(k) * 0.37 + float(spot) * 0.13, 1.0)) / float(Rule.POINTS)
			var base := la.lerp(lb, along)
			var reach := (10.0 + 70.0 * t) if burst else (6.0 + 42.0 * t)
			var at := base + away * reach + Vector2(sin(_time * 2.0 + float(k + spot)) * 4.0, -10.0 * t)
			var r := (6.0 + 13.0 * t) if burst else (4.0 + 9.0 * t)
			var alpha := (0.85 if burst and _burst < 1.5 else 0.7) * (1.0 - t)
			box.draw_circle(at, r, Color(1, 1, 1, alpha))


## Yellow with black diagonal bands, clipped to the jamb.
func _paint_stripes(box: Control, jamb: Rect2) -> void:
	box.draw_rect(jamb, STRIPE)
	var clip := PackedVector2Array([jamb.position, Vector2(jamb.end.x, jamb.position.y), jamb.end, Vector2(jamb.position.x, jamb.end.y)])
	var band := 18.0
	var y := jamb.position.y - band * 2.0
	while y < jamb.end.y + band:
		var quad := PackedVector2Array([Vector2(jamb.position.x, y), Vector2(jamb.end.x, y - 16.0),
			Vector2(jamb.end.x, y - 16.0 + band * 0.5), Vector2(jamb.position.x, y + band * 0.5)])
		for piece in Geometry2D.intersect_polygons(quad, clip):
			if (piece as PackedVector2Array).size() >= 3:
				box.draw_colored_polygon(piece, STRIPE_DARK)
		y += band
	box.draw_rect(jamb, Color(0, 0, 0, 0.6), false, 2.0)


## One round seal point: bright with a dark number while open, a dark pressed-in dot once sealed, red for a moment
## after a wrong number, greyed while the time is up. The focused point gets a thick ring.
func _paint_point(b: Button, spot: int) -> void:
	if puzzle.is_empty():
		return
	var pal := UiTheme.palette()
	var c := b.size * 0.5
	var r := POINT_SIZE * 0.5 - 3.0
	var n := Rule.order_number(puzzle, spot)
	var sealed := succeeded or n <= int(puzzle.pressed)
	var fill := Color(0.98, 0.97, 0.92)
	var ink := Color(0.05, 0.05, 0.06)
	if spot == flash_spot and _flash_left > 0.0:
		fill = FLASH
		ink = Color(1, 1, 1)
	elif sealed and not timed_out:
		fill = SEAL
		ink = Color(0.62, 0.65, 0.68)
	elif timed_out:
		fill = Color(0.55, 0.56, 0.58)
	b.draw_circle(c + Vector2(0, 2), r + 2.0, Color(0, 0, 0, 0.45))
	b.draw_circle(c, r + 2.0, Color(0.05, 0.05, 0.06))
	b.draw_circle(c, r, fill)
	if sealed and not timed_out:
		# Pressed in: an inner shadow ring instead of a raised rim.
		b.draw_arc(c, r - 3.0, 0.0, TAU, 24, Color(0, 0, 0, 0.8), 3.0)
	else:
		b.draw_arc(c, r - 2.0, PI, TAU, 16, Color(1, 1, 1, 0.5), 2.0)
	if b.is_hovered() and not b.disabled:
		b.draw_arc(c, r + 1.0, 0.0, TAU, 32, pal.accent, 2.0)
	if b.has_focus():
		b.draw_arc(c, r + 3.0, 0.0, TAU, 32, pal.focus, 3.0)
	draw_text_centered(b, str(n), c + Vector2(0, 1), 22, ink)
