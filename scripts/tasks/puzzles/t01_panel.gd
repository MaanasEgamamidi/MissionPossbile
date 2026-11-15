extends "res://scripts/tasks/puzzles/electric_ui.gd"
## T01 Comms mini-game: the "NO SIGNAL" console in the Command Room. Two traces on a console screen (target signal
## and your signal), one tuning dial (drag or mouse wheel; arrow keys when focused) and the same dial as a keyboard
## slider. The panel only sends tune / hold / transfer / reset moves; the host rule (t01_rule.gd) decides.
## Pacing: a tune is sent TUNE_DEBOUNCE s after the dial stops moving (one request per adjustment, not per frame);
## while the host confirms a match the panel sends one hold step every HOLD_SECONDS, then one transfer block every
## TRANSFER_SECONDS.

const Rule := preload("res://scripts/tasks/puzzles/t01_rule.gd")
const TUNE_DEBOUNCE := 0.25
const TARGET_COLOR := Color(0.45, 0.8, 1.0)
const YOURS_COLOR := Color(0.98, 0.6, 0.25)

var screen: DrawBox
var dial: DrawBox
var slider: HSlider
var hint_label: Label
var strength_label: Label
var transfer_bar: ProgressBar

var _layout: Dictionary = {"target": Rule.START_DIAL, "phase": 0.0}
var _host: Dictionary = Rule.initial_state()
var _local := Rule.START_DIAL
var _tune_dirty := false
var _tune_wait := 0.0
var _dragging := false
var _drag_accum := 0.0
var _hold_timer := 0.0
var _transfer_timer := 0.0
var _time := 0.0
var _syncing := false


func setup(p_services: GameServices) -> void:
	task_title = "Fix the radio signal"
	instructions = "Turn the tuning dial until your orange signal wave sits right on top of the blue target wave. Keep it still for a moment to lock the link, then the data sends by itself. Mouse: drag the dial or use the scroll wheel. Keyboard: Tab to the tuning slider and use the arrow keys."
	super.setup(p_services)
	if ui_ready:
		return
	name = "CommsPanel"
	screen = DrawBox.new()
	screen.name = "SignalScreen"
	screen.custom_minimum_size = Vector2(0, 220)
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.painter = _draw_screen
	play_area.add_child(screen)
	var row := HBoxContainer.new()
	row.name = "TuningRow"
	play_area.add_child(row)
	dial = DrawBox.new()
	dial.name = "TuningDial"
	dial.custom_minimum_size = Vector2(120, 120)
	dial.focus_mode = Control.FOCUS_ALL
	dial.tooltip_text = "Tuning dial: drag, scroll, or use the arrow keys"
	dial.painter = _draw_dial
	dial.handler = _dial_input
	row.add_child(dial)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	var slider_label := _label("TuningLabel", UiTheme.HEADING)
	slider_label.text = "Tuning (keyboard: arrow keys)"
	column.add_child(slider_label)
	slider = HSlider.new()
	slider.name = "TuningSlider"
	slider.min_value = 0
	slider.max_value = Rule.DIAL_MAX
	slider.step = 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(200, 32)
	slider.focus_mode = Control.FOCUS_ALL
	slider.value_changed.connect(func(v: float) -> void:
		if not _syncing:
			_set_local(int(round(v))))
	column.add_child(slider)
	strength_label = _label("SignalStrength", UiTheme.MUTED)
	column.add_child(strength_label)
	hint_label = _label("Hint", UiTheme.HEADING)
	play_area.add_child(hint_label)
	var transfer_label := _label("TransferLabel", UiTheme.MUTED)
	transfer_label.text = "Data transfer"
	play_area.add_child(transfer_label)
	transfer_bar = ProgressBar.new()
	transfer_bar.name = "TransferBar"
	transfer_bar.max_value = Rule.TRANSFER_STEPS
	transfer_bar.step = 0.0
	transfer_bar.theme_type_variation = UiTheme.BAR_GOOD
	play_area.add_child(transfer_bar)
	reset_requested.connect(func() -> void:
		_tune_dirty = false
		send_move("reset", 0))
	ui_ready = true
	refresh_from_host()


func first_focus() -> Control:
	return cancel_button if pending or slider == null else slider


func _process(delta: float) -> void:
	super._process(delta)
	if not ui_ready:
		return
	_time += delta
	screen.queue_redraw()
	if succeeded or pending:
		return
	if _tune_dirty:
		if _dragging:
			return
		_tune_wait -= delta
		if _tune_wait <= 0.0:
			_tune_dirty = false
			if _local != int(_host.dial) and not bool(_host.locked):
				send_move("tune", _local)
		return
	if not bool(_host.locked):
		if _local == int(_host.dial) and Rule.is_match(int(_host.dial), int(_layout.target)):
			_hold_timer += delta
			if _hold_timer >= Rule.HOLD_SECONDS:
				_hold_timer = 0.0
				send_move("hold", int(_host.holds) + 1)
		else:
			_hold_timer = 0.0
	elif int(_host.sent) < Rule.TRANSFER_STEPS:
		_transfer_timer += delta
		if _transfer_timer >= Rule.TRANSFER_SECONDS:
			_transfer_timer = 0.0
			send_move("transfer", int(_host.sent) + 1)


func _set_local(value: int) -> void:
	if bool(_host.locked) or succeeded:
		_sync_controls()
		return
	value = clampi(value, 0, Rule.DIAL_MAX)
	if value == _local:
		return
	_local = value
	_tune_dirty = true
	_tune_wait = TUNE_DEBOUNCE
	_hold_timer = 0.0
	_sync_controls()


func _sync_controls() -> void:
	_syncing = true
	slider.value = _local
	_syncing = false
	slider.editable = not bool(_host.locked) and not succeeded
	var distance := absi(_local - int(_layout.target))
	var bars := clampi(5 - distance / 6, 0, 5)
	strength_label.text = "Signal strength: %s%s  (dial %d)" % ["|".repeat(bars), ".".repeat(5 - bars), _local]
	dial.queue_redraw()


func _on_host_state(seed_value: int, _puzzle: Dictionary, record: Dictionary) -> void:
	_layout = Rule.layout(seed_value)
	_host = Rule.state_of(record)
	if not _tune_dirty and not _dragging:
		_local = int(_host.dial)
	transfer_bar.value = int(_host.sent)
	if succeeded:
		hint_label.text = "Data sent. The radio link works again!"
	elif bool(_host.locked):
		hint_label.text = "Link locked! Sending data... %d of %d blocks" % [int(_host.sent), Rule.TRANSFER_STEPS]
	elif Rule.is_match(int(_host.dial), int(_layout.target)):
		hint_label.text = "Match! Keep the dial still... hold %d of %d" % [int(_host.holds), Rule.HOLD_STEPS]
	else:
		hint_label.text = "No signal yet. Turn the dial until the two waves line up."
	_sync_controls()


func _explain_rejection(move: Dictionary) -> String:
	match String(move.get("move", "")):
		"tune":
			return "The link is already locked, so the dial stays put."
		"hold":
			_hold_timer = 0.0
			return "The signal slipped off the target. Line the two waves up again."
		"transfer":
			return "Lock the link first by holding a match."
	return ""


func _after_reclaim() -> void:
	if _local != int(_host.dial):
		_tune_dirty = true
		_tune_wait = 0.0


func _dial_input(_box: Control, event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_drag_accum = 0.0
			if mb.pressed:
				dial.grab_focus()
			return true
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_RIGHT]:
			_set_local(_local + 1)
			return true
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT]:
			_set_local(_local - 1)
			return true
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_drag_accum += motion.relative.x - motion.relative.y
		var steps := int(_drag_accum / 4.0)
		if steps != 0:
			_drag_accum -= steps * 4.0
			_set_local(_local + steps)
		return true
	elif event is InputEventKey and event.is_pressed():
		var step := 0
		match (event as InputEventKey).keycode:
			KEY_RIGHT, KEY_UP:
				step = 1
			KEY_LEFT, KEY_DOWN:
				step = -1
			KEY_PAGEUP:
				step = 10
			KEY_PAGEDOWN:
				step = -10
		if step != 0:
			_set_local(_local + step)
			return true
	return false


# ---------------------------------------------------------------- drawing

func _wave_y(x01: float, dial_value: int, noise: float) -> float:
	var cycles := 1.0 + 0.06 * float(dial_value)
	var y := sin(x01 * cycles * TAU + float(_layout.phase) + _time * 2.0)
	if noise > 0.0:
		y += noise * sin(x01 * 97.0 + _time * 23.0) * sin(x01 * 31.0 - _time * 7.0)
	return y


func _draw_screen(box: Control) -> void:
	var r := Rect2(Vector2.ZERO, box.size)
	box.draw_rect(r, METAL_DARK)
	var glass := r.grow(-6.0)
	box.draw_rect(glass, SCREEN_BG)
	for i in range(1, 8):
		var gx := glass.position.x + glass.size.x * float(i) / 8.0
		box.draw_line(Vector2(gx, glass.position.y), Vector2(gx, glass.end.y), SCREEN_GRID, 1.0)
	var mid := glass.position.y + glass.size.y * 0.55
	box.draw_line(Vector2(glass.position.x, mid), Vector2(glass.end.x, mid), SCREEN_GRID, 1.0)
	var amp := glass.size.y * 0.28
	var matched := Rule.is_match(_local, int(_layout.target))
	var noise := 0.0 if matched else clampf(absi(_local - int(_layout.target)) / 30.0, 0.15, 0.8)
	var target_pts := PackedVector2Array()
	var your_pts := PackedVector2Array()
	var n := 160
	for i in n + 1:
		var x01 := float(i) / n
		var x := glass.position.x + 10.0 + (glass.size.x - 20.0) * x01
		target_pts.append(Vector2(x, mid - amp * _wave_y(x01, int(_layout.target), 0.0)))
		your_pts.append(Vector2(x, mid - amp * _wave_y(x01, _local, noise)))
	box.draw_polyline(target_pts, TARGET_COLOR, 5.0, true)
	box.draw_polyline(your_pts, LAMP_GOOD if matched else YOURS_COLOR, 2.5, true)
	# Legend: a line sample and a word for each trace (colour is not the only cue: thick vs thin line too).
	var lx := glass.position.x + 14.0
	box.draw_line(Vector2(lx, glass.position.y + 18), Vector2(lx + 26, glass.position.y + 18), TARGET_COLOR, 5.0)
	box.draw_string(ThemeDB.fallback_font, Vector2(lx + 34, glass.position.y + 24), "TARGET SIGNAL (thick)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TARGET_COLOR)
	box.draw_line(Vector2(lx, glass.position.y + 40), Vector2(lx + 26, glass.position.y + 40), YOURS_COLOR, 2.5)
	box.draw_string(ThemeDB.fallback_font, Vector2(lx + 34, glass.position.y + 46), "YOUR SIGNAL (thin)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, YOURS_COLOR)
	# Lamps with words: red-orange NO SIGNAL, yellow MATCH, green LINK LOCKED.
	var lamp_x := glass.end.x - 120.0
	var word := "NO SIGNAL"
	var color := Color(0.9, 0.3, 0.25)
	if succeeded:
		word = "DATA SENT"
		color = LAMP_GOOD
	elif bool(_host.locked):
		word = "LINK LOCKED"
		color = LAMP_GOOD
	elif matched:
		word = "MATCH - HOLD"
		color = LAMP_WAIT
	draw_lamp(box, Vector2(lamp_x, glass.position.y + 24), 9.0, color)
	box.draw_string(ThemeDB.fallback_font, Vector2(lamp_x + 16, glass.position.y + 30), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)


func _draw_dial(box: Control) -> void:
	var c := box.size * 0.5
	var r := minf(box.size.x, box.size.y) * 0.42
	box.draw_circle(c, r + 6.0, METAL_DARK)
	box.draw_circle(c, r, METAL)
	for i in 11:
		var a := deg_to_rad(-225.0 + 27.0 * i)
		box.draw_line(c + Vector2(cos(a), sin(a)) * (r + 1.0), c + Vector2(cos(a), sin(a)) * (r + 6.0), Color(0.85, 0.87, 0.9), 2.0)
	var angle := deg_to_rad(-225.0 + 270.0 * float(_local) / Rule.DIAL_MAX)
	box.draw_line(c, c + Vector2(cos(angle), sin(angle)) * r * 0.85, Color(0.08, 0.08, 0.1), 5.0)
	box.draw_circle(c, r * 0.18, METAL_DARK)
	if box.has_focus():
		box.draw_arc(c, r + 9.0, 0.0, TAU, 48, UiTheme.palette().focus, 3.0)
