extends "res://scripts/tasks/puzzles/electric_ui.gd"
## T03 Rings mini-game: the three round dials on the Power Room distributor cabinet (BP06). Each numbered dial has a
## spinning pointer and a green marked sector. Press STOP (Enter / Space, or click) while the pointer is inside the
## sector: the host checks the stop time against the seeded spin (t03_rule.gd) and locks that channel; a miss only
## restarts the active ring. Lamps under each dial say WAITING / SPINNING / LOCKED in words as well as colour.
## The stop time is taken from the input moment (Time.get_ticks_msec), not from a frame, so low frame rates and LAN
## latency do not change the result.

const Rule := preload("res://scripts/tasks/puzzles/t03_rule.gd")
const SECTOR_COLOR := Color(0.35, 0.85, 0.45, 0.55)
const POINTER_COLOR := Color(0.85, 0.2, 0.18)

var dials: DrawBox
var stop_button: Button
var assist_toggle: CheckButton
var hint_label: Label

var _layout: Dictionary = {"rings": []}
var _host: Dictionary = {"ring": 0, "assist": false}
var _shown_ring := -1
## When the active ring (re)started spinning, in Time.get_ticks_msec() units. Tests may set it.
var ring_start_ms := 0
var _last_stop_ms := 0


func setup(p_services: GameServices) -> void:
	task_title = "Fix the power dials"
	instructions = "Each dial has a spinning red pointer and a green zone. Press STOP while the pointer is inside the green zone to lock that dial. Lock all three. Keyboard: Enter or Space presses STOP. Turn on Wide window if the timing feels too hard."
	super.setup(p_services)
	if ui_ready:
		return
	name = "RingsPanel"
	dials = DrawBox.new()
	dials.name = "Dials"
	dials.custom_minimum_size = Vector2(0, 250)
	dials.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dials.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dials.painter = _draw_dials
	play_area.add_child(dials)
	stop_button = make_button("Stop", "STOP", true)
	stop_button.custom_minimum_size = Vector2(0, 56)
	stop_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	stop_button.pressed.connect(_on_stop)
	play_area.add_child(stop_button)
	assist_toggle = CheckButton.new()
	assist_toggle.name = "WideWindow"
	assist_toggle.text = "Wide window (easier timing)"
	assist_toggle.toggled.connect(func(on: bool) -> void: send_move("assist", 1 if on else 0))
	play_area.add_child(assist_toggle)
	hint_label = _label("Hint", UiTheme.HEADING)
	play_area.add_child(hint_label)
	reset_requested.connect(func() -> void: send_move("reset", 0))
	ui_ready = true
	ring_start_ms = Time.get_ticks_msec()
	refresh_from_host()


func first_focus() -> Control:
	return cancel_button if pending or stop_button == null else stop_button


func now_ms() -> int:
	return Time.get_ticks_msec()


## Time since the active ring started, in ms.
func ring_time_ms() -> int:
	return now_ms() - ring_start_ms


func _process(delta: float) -> void:
	super._process(delta)
	if not ui_ready:
		return
	if ring_time_ms() > Rule.MAX_STOP_MS - 5000:
		ring_start_ms = now_ms()
	dials.queue_redraw()


func _on_host_state(seed_value: int, _puzzle: Dictionary, record: Dictionary) -> void:
	_layout = Rule.layout(seed_value)
	_host = Rule.state_of(record)
	if int(_host.ring) != _shown_ring:
		_shown_ring = int(_host.ring)
		ring_start_ms = now_ms()
	assist_toggle.set_pressed_no_signal(bool(_host.assist))
	var ring := int(_host.ring)
	if succeeded or ring >= Rule.RINGS:
		stop_button.text = "All dials locked"
		hint_label.text = "All three dials are locked. The power works again!"
	else:
		stop_button.text = "STOP dial %d (Enter / Space)" % (ring + 1)
		hint_label.text = "Dials locked: %d of %d. Watch dial %d." % [ring, Rule.RINGS, ring + 1]


func _on_stop() -> void:
	var ring := int(_host.ring)
	if pending or succeeded or ring >= Rule.RINGS:
		return
	var t := ring_time_ms()
	if t < Rule.MIN_STOP_MS:
		return
	_last_stop_ms = t
	send_move("stop", ring * Rule.RING_FACTOR + t)


func _explain_rejection(move: Dictionary) -> String:
	if String(move.get("move", "")) != "stop" or (_layout.rings as Array).is_empty():
		return ""
	var ring := int(_host.ring)
	var off := Rule.offset_deg(_layout.rings[mini(ring, Rule.RINGS - 1)], _last_stop_ms)
	ring_start_ms = now_ms()
	return "Missed by %d degrees. Dial %d starts again - press STOP when the pointer is in the green zone." % [int(round(off)), ring + 1]


# ---------------------------------------------------------------- drawing

func _draw_dials(box: Control) -> void:
	box.draw_rect(Rect2(Vector2.ZERO, box.size), Color(0.78, 0.8, 0.82))
	box.draw_rect(Rect2(Vector2.ZERO, box.size), METAL_DARK, false, 4.0)
	var rings: Array = _layout.rings
	if rings.is_empty():
		return
	var slot := box.size.x / Rule.RINGS
	var r := minf(slot * 0.36, box.size.y * 0.3)
	var active := int(_host.ring)
	var assist := bool(_host.assist)
	for i in Rule.RINGS:
		var ring: Dictionary = rings[i]
		var c := Vector2(slot * (i + 0.5), box.size.y * 0.44)
		draw_text_centered(box, "%d" % (i + 1), c + Vector2(0, -r - 22.0), 22, Color(0.1, 0.1, 0.12))
		box.draw_circle(c, r + 8.0, METAL_DARK)
		box.draw_circle(c, r, Color(0.96, 0.96, 0.94))
		# Marked sector (green) with a dark notch at the mark itself.
		var mark := deg_to_rad(float(ring.mark) - 90.0)
		var half := deg_to_rad(Rule.window(assist))
		var wedge := PackedVector2Array([c])
		for s in 13:
			var a := mark - half + 2.0 * half * float(s) / 12.0
			wedge.append(c + Vector2(cos(a), sin(a)) * r * 0.95)
		box.draw_colored_polygon(wedge, SECTOR_COLOR)
		box.draw_line(c + Vector2(cos(mark), sin(mark)) * r * 0.8, c + Vector2(cos(mark), sin(mark)) * (r + 8.0), Color(0.05, 0.3, 0.1), 4.0)
		for k in 12:
			var tick := TAU * float(k) / 12.0
			box.draw_line(c + Vector2(cos(tick), sin(tick)) * r * 0.86, c + Vector2(cos(tick), sin(tick)) * r * 0.95, Color(0.3, 0.3, 0.32), 2.0)
		# Pointer: locked dials rest on the mark, the active one spins, later ones wait at their start.
		var angle_deg := float(ring.start)
		if i < active:
			angle_deg = float(ring.mark)
		elif i == active and not succeeded:
			angle_deg = Rule.angle_at(ring, ring_time_ms())
		var p := deg_to_rad(angle_deg - 90.0)
		box.draw_line(c, c + Vector2(cos(p), sin(p)) * r * 0.9, POINTER_COLOR, 5.0)
		box.draw_circle(c, r * 0.12, METAL_DARK)
		if i == active and not succeeded:
			box.draw_arc(c, r + 13.0, 0.0, TAU, 48, UiTheme.palette().focus, 3.0)
		# Lamp and word under the dial.
		var lamp_color := LAMP_OFF
		var word := "WAITING"
		if i < active:
			lamp_color = LAMP_GOOD
			word = "LOCKED"
		elif i == active and not succeeded:
			lamp_color = LAMP_WAIT
			word = "SPINNING"
		var lamp := c + Vector2(0, r + 28.0)
		draw_lamp(box, lamp + Vector2(-44, 0), 8.0, lamp_color)
		draw_text_centered(box, word, lamp + Vector2(10, 0), 16, Color(0.1, 0.1, 0.12))
