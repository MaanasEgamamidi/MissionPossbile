extends "res://scripts/tasks/puzzles/electric_ui.gd"
## T01 "Lock the Relay" mini-game (Command Room radio console, anyone can do it). UI overhaul 2026-11-15: the radio
## console is the interface, in the spirit of Among Us "Find Signal". One picture, no words on it:
##   Left    the scope: a pale, thick ghost trace (the relay's signal) and your live wave, thin and bright, jittery while
##           it is off. Turn the knob until the live wave lies on the ghost. On the scope too: the hold pips and a
##           padlock (open while you hold, closed once the link locks), then the data blocks filling as they are sent.
##           Under the scope, the tuning strip: a needle on a scale (the keyboard's way in; a click jumps the needle).
##   Middle  one oversized tuning knob (drag or scroll it) with the target ring and a "turn" pictogram while the waves
##           do not match.
##   Right   the relay dish. After the lock, data pulses run along the cable from the console to the dish; when the
##           last block arrives the dish sends out signal arcs and gets a tick.
## The host rule (t01_rule.gd) decides everything; the panel only sends tune / hold / transfer / reset moves.
## Pacing: a tune is sent TUNE_DEBOUNCE s after the dial stops moving (one request per adjustment, not per frame);
## while the host confirms a match the panel sends one hold step every HOLD_SECONDS, then one transfer block every
## TRANSFER_SECONDS.
## Keyboard: the strip (first focus) and the knob both take the arrow keys (Page Up / Down = ten steps).

const Rule := preload("res://scripts/tasks/puzzles/t01_rule.gd")
const TUNE_DEBOUNCE := 0.25
const GHOST := Color(0.7, 0.93, 1.0)
const LIVE := Color(1.0, 0.68, 0.28)
const ELECTRIC_SCREEN := Color(0.02, 0.07, 0.08)
## Source pixels of the sprites.
const SCOPE_TEX := Vector2(512, 312)
const SCOPE_GLASS := Rect2(30, 30, 452, 252)
const DISH_TEX := Vector2(313, 512)
## The dish's feed horn (where the signal arcs start) and the foot of its stand (where the cable plugs in).
const DISH_HORN := Vector2(0.62, 0.21)
const DISH_FOOT := Vector2(0.62, 0.93)
## The knob turns 270 degrees over the dial's range.
const KNOB_SWEEP := 270.0
const CUE_TUNE := "Match the waves [Left] [Right]"
const CUE_HOLD := "Hold it still"
const CUE_SEND := "Sending to the relay"

## The picture: scope, knob, dish (one drawn control).
var console: DrawBox
## The tuning knob's hit area (drag, wheel, arrow keys).
var dial: DrawBox
## The tuning strip under the scope (keyboard first focus; a click jumps the needle).
var slider: HSlider

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
var _was_locked := false
var _arrived := 0.0
var _hover_strip := false
var _hover_knob := false


func setup(p_services: GameServices) -> void:
	task_title = "Lock the Relay"
	instructions = ("Turn the big knob until your bright wave lies on the pale ghost wave, then keep it still to lock "
		+ "the link. The data then flies to the relay dish by itself. Drag or scroll the knob, click the strip, or "
		+ "use the arrow keys.")
	super.setup(p_services)
	if ui_ready:
		return
	name = "CommsPanel"
	console = DrawBox.new()
	console.name = "RadioConsole"
	console.custom_minimum_size = Vector2(900, 420)
	console.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	console.size_flags_vertical = Control.SIZE_EXPAND_FILL
	console.mouse_filter = Control.MOUSE_FILTER_PASS
	console.painter = _paint
	Kit.smooth(console)
	console.resized.connect(_place)
	play_area.add_child(console)
	slider = HSlider.new()
	slider.name = "TuningSlider"
	slider.min_value = 0
	slider.max_value = Rule.DIAL_MAX
	slider.step = 1
	slider.focus_mode = Control.FOCUS_ALL
	slider.tooltip_text = "Tuning strip"
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# The strip is drawn by the console: the slider itself only takes the clicks and the keys.
	var blank := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	for icon: StringName in [&"grabber", &"grabber_highlight", &"grabber_disabled", &"tick"]:
		slider.add_theme_icon_override(icon, blank)
	for style: StringName in [&"slider", &"grabber_area", &"grabber_area_highlight"]:
		slider.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	slider.value_changed.connect(func(v: float) -> void:
		if not _syncing:
			_set_local(int(round(v))))
	slider.mouse_entered.connect(func() -> void: _hover_strip = true)
	slider.mouse_exited.connect(func() -> void: _hover_strip = false)
	slider.focus_entered.connect(console.queue_redraw)
	slider.focus_exited.connect(console.queue_redraw)
	console.add_child(slider)
	dial = DrawBox.new()
	dial.name = "TuningDial"
	dial.focus_mode = Control.FOCUS_ALL
	dial.mouse_default_cursor_shape = Control.CURSOR_DRAG
	dial.tooltip_text = "Tuning knob"
	dial.handler = _dial_input
	dial.mouse_entered.connect(func() -> void: _hover_knob = true)
	dial.mouse_exited.connect(func() -> void: _hover_knob = false)
	dial.focus_entered.connect(console.queue_redraw)
	dial.focus_exited.connect(console.queue_redraw)
	console.add_child(dial)
	slider.focus_neighbor_right = NodePath("../TuningDial")
	slider.focus_neighbor_top = NodePath("../TuningDial")
	dial.focus_neighbor_left = NodePath("../TuningSlider")
	reset_requested.connect(func() -> void:
		_tune_dirty = false
		send_move("reset", 0))
	set_cue(CUE_TUNE)
	ui_ready = true
	refresh_from_host()


func first_focus() -> Control:
	return cancel_button if pending or slider == null else slider


func _process(delta: float) -> void:
	super._process(delta)
	if not ui_ready:
		return
	_time += delta
	var sent := float(int(_host.sent))
	_arrived = sent if wants_less_motion() else move_toward(_arrived, sent, delta / maxf(0.05, Rule.TRANSFER_SECONDS * 0.8))
	if is_visible_in_tree():
		console.queue_redraw()
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
	_update_cue()
	console.queue_redraw()


func _matched() -> bool:
	return Rule.is_match(_local, int(_layout.target))


func _update_cue() -> void:
	if succeeded:
		set_cue("")
	elif bool(_host.locked):
		set_cue(CUE_SEND)
	elif _matched():
		set_cue(CUE_HOLD)
	else:
		set_cue(CUE_TUNE)


func _on_host_state(seed_value: int, _puzzle: Dictionary, record: Dictionary) -> void:
	_layout = Rule.layout(seed_value)
	_host = Rule.state_of(record)
	if not _tune_dirty and not _dragging:
		_local = int(_host.dial)
	var locked := bool(_host.locked)
	if locked and not _was_locked and not succeeded:
		_say("Locked! Sending the data.", &"good")
	_was_locked = locked
	if not locked:
		_arrived = 0.0
	_sync_controls()


func _on_solved() -> void:
	_say("The relay hears us again!", &"good")
	_update_cue()


func _say(text: String, kind: StringName) -> void:
	status_label.text = text
	status_label.theme_type_variation = UiTheme.GOOD if kind == &"good" else (UiTheme.WARN if kind == &"warn" else UiTheme.MUTED)


func _explain_rejection(move: Dictionary) -> String:
	match String(move.get("move", "")):
		"tune":
			return "The link is locked. Leave the knob."
		"hold":
			_hold_timer = 0.0
			return "The wave slipped. Match it again."
		"transfer":
			return "Lock the link first."
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
		# Dragging round the knob: the turn about its centre, a step every few degrees.
		var motion := event as InputEventMouseMotion
		var centre := dial.size * 0.5
		var before := motion.position - motion.relative - centre
		var after := motion.position - centre
		if before.length() > 6.0 and after.length() > 6.0:
			_drag_accum += rad_to_deg(before.angle_to(after)) / (KNOB_SWEEP / float(Rule.DIAL_MAX))
		else:
			_drag_accum += (motion.relative.x - motion.relative.y) / 4.0
		var steps := int(_drag_accum)
		if steps != 0:
			_drag_accum -= float(steps)
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


# ---------------------------------------------------------------- layout (relative to the console's size)

func _scope_rect() -> Rect2:
	var s := console.size
	var r := Kit.fit(SCOPE_TEX.x / SCOPE_TEX.y, Rect2(s.x * 0.035, s.y * 0.06, s.x * 0.53, s.y * 0.66))
	# On a tall screen the scope and its strip sit in the middle, not at the top.
	var block := r.size.y + s.y * 0.05 + clampf(s.y * 0.12, 38.0, 60.0)
	r.position.y = maxf(s.y * 0.06, (s.y - block) * 0.5 - s.y * 0.02)
	return r


func _glass_rect() -> Rect2:
	var scope := _scope_rect()
	var k := scope.size.x / SCOPE_TEX.x
	return Rect2(scope.position + SCOPE_GLASS.position * k, SCOPE_GLASS.size * k)


func _strip_rect() -> Rect2:
	var scope := _scope_rect()
	var h := clampf(console.size.y * 0.12, 38.0, 60.0)
	return Rect2(scope.position.x + scope.size.x * 0.05, scope.end.y + console.size.y * 0.05, scope.size.x * 0.9, h)


func _knob_centre() -> Vector2:
	return Vector2(console.size.x * 0.695, console.size.y * 0.45)


func _knob_radius() -> float:
	return minf(console.size.x * 0.085, console.size.y * 0.25)


func _dish_rect() -> Rect2:
	var s := console.size
	return Kit.fit(DISH_TEX.x / DISH_TEX.y, Rect2(s.x * 0.815, s.y * 0.08, s.x * 0.16, s.y * 0.7))


func _place() -> void:
	if console == null or console.size.x < 8.0:
		return
	var strip := _strip_rect()
	slider.position = strip.position
	slider.size = strip.size
	var r := _knob_radius() * 1.12
	dial.position = _knob_centre() - Vector2(r, r)
	dial.size = Vector2(r, r) * 2.0


# ---------------------------------------------------------------- drawing

func _paint(c: Control) -> void:
	var area := Rect2(Vector2.ZERO, c.size)
	Kit.bay(c, area)
	Kit.housing(c, area.grow(-9.0), 14.0)
	_paint_cable(c)
	_paint_scope(c)
	_paint_strip(c)
	_paint_knob(c)
	_paint_dish(c)


## A wave across the glass: dial sets the frequency, noise makes it jitter.
func _wave(glass: Rect2, dial_value: int, noise: float, amp: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var t := 0.0 if wants_less_motion() else _time
	var mid := glass.get_center().y
	for i in n + 1:
		var x01 := float(i) / float(n)
		var cycles := 1.0 + 0.06 * float(dial_value)
		var y := sin(x01 * cycles * TAU + float(_layout.phase) + t * 2.0)
		if noise > 0.0:
			y += noise * sin(x01 * 97.0 + t * 23.0) * sin(x01 * 31.0 - t * 7.0)
		pts.append(Vector2(glass.position.x + glass.size.x * (0.04 + 0.92 * x01), mid - amp * y))
	return pts


func _paint_scope(c: Control) -> void:
	var scope := _scope_rect()
	var glass := _glass_rect()
	Kit.box(c, scope.grow(6.0), Kit.HOUSING_DARK, 22.0)
	# The bezel's screen is dark glass: the traces are drawn on it.
	Kit.draw_fill(c, Kit.tex("comms/scope_bezel"), scope)
	var grid := Color(0.16, 0.3, 0.34, 0.8)
	for i in range(1, 8):
		var gx := glass.position.x + glass.size.x * float(i) / 8.0
		c.draw_line(Vector2(gx, glass.position.y + 4.0), Vector2(gx, glass.end.y - 4.0), grid, 1.0)
	for i in range(1, 4):
		var gy := glass.position.y + glass.size.y * float(i) / 4.0
		c.draw_line(Vector2(glass.position.x + 4.0, gy), Vector2(glass.end.x - 4.0, gy), grid, 1.0)
	var locked := bool(_host.locked) or succeeded
	var matched := _matched()
	var amp := glass.size.y * 0.27
	var n := 140
	# The ghost: the relay's signal, thick and pale.
	c.draw_polyline(_wave(glass, int(_layout.target), 0.0, amp, n), Color(GHOST, 0.42), maxf(9.0, glass.size.y * 0.065), true)
	# The live wave: thin and bright; jittery while it is off, green once the link is locked.
	var noise := 0.0 if matched or locked else clampf(absi(_local - int(_layout.target)) / 40.0, 0.12, 0.5)
	var good: Color = UiTheme.palette().good
	var live := good.lightened(0.2) if locked else (LIVE.lerp(Color.WHITE, 0.25) if matched else LIVE)
	c.draw_polyline(_wave(glass, _local, noise, amp, n), live, maxf(2.5, glass.size.y * 0.018), true)
	# The screen's glare.
	c.draw_colored_polygon(PackedVector2Array([glass.position, glass.position + Vector2(glass.size.x * 0.32, 0.0),
		glass.position + Vector2(glass.size.x * 0.18, glass.size.y), glass.position + Vector2(0.0, glass.size.y)]), Color(1, 1, 1, 0.035))
	# Hold feedback (top left): the padlock, open while holding, closed once locked, and one pip per hold step.
	var r := clampf(glass.size.y * 0.075, 9.0, 18.0)
	var lock_at := glass.position + Vector2(r * 1.9, r * 1.9)
	if locked or matched:
		c.draw_circle(lock_at, r * 1.45, Color(Kit.INK, 0.85))
		Kit.lock(c, lock_at + Vector2(0.0, r * 0.1), r, locked, good if locked else LIVE)
		var holds := Rule.HOLD_STEPS if locked else int(_host.holds)
		Kit.pips(c, lock_at + Vector2(r * 1.6 + r * 0.6 * 3.0 * float(Rule.HOLD_STEPS - 1) * 0.5 + r * 0.9, 0.0), Rule.HOLD_STEPS, holds, r * 0.6)
	# Transfer feedback (bottom): one block per data packet, lit as each reaches the dish.
	if locked:
		var bw := glass.size.x * 0.07
		var gap := bw * 0.35
		var total := bw * float(Rule.TRANSFER_STEPS) + gap * float(Rule.TRANSFER_STEPS - 1)
		var x := glass.end.x - total - r
		var y := glass.end.y - r - bw * 0.55
		for i in Rule.TRANSFER_STEPS:
			var cell := Rect2(x + float(i) * (bw + gap), y, bw, bw * 0.55)
			var lit := float(i) < _arrived - 0.01
			Kit.box(c, cell, good.darkened(0.1) if lit else Color(1, 1, 1, 0.08), 4.0, Color(GHOST, 0.5), 1.5)
	if succeeded:
		Kit.tick(c, Vector2(glass.end.x - r * 1.6, glass.position.y + r * 1.9), r * 1.2)



## The tuning strip: a scale with a needle at the dial (no target mark: the scope tells you where to go).
func _paint_strip(c: Control) -> void:
	var strip := _strip_rect()
	Kit.box(c, strip.grow(5.0), Kit.HOUSING_DARK, 12.0)
	Kit.box(c, strip, ELECTRIC_SCREEN, 9.0, Kit.METAL_DARK, 2.0)
	var inner := strip.grow_individual(-16.0, -6.0, -16.0, -6.0)
	for i in 21:
		var x := inner.position.x + inner.size.x * float(i) / 20.0
		var tall := 0.55 if i % 5 == 0 else 0.3
		c.draw_line(Vector2(x, inner.end.y), Vector2(x, inner.end.y - inner.size.y * tall), Color(GHOST, 0.55), 2.0 if i % 5 == 0 else 1.0)
	var nx := inner.position.x + inner.size.x * float(_local) / float(Rule.DIAL_MAX)
	c.draw_line(Vector2(nx, strip.position.y + 3.0), Vector2(nx, strip.end.y - 3.0), LIVE, 4.0)
	c.draw_circle(Vector2(nx, strip.position.y + 6.0), 5.0, LIVE)
	if _hover_strip and slider.editable:
		Kit.box(c, strip, Color(1, 1, 1, 0.06), 9.0)
	if slider.has_focus():
		Kit.focus_ring(c, strip, 10.0, 4.0)


func _paint_knob(c: Control) -> void:
	var centre := _knob_centre()
	var r := _knob_radius()
	var locked := bool(_host.locked) or succeeded
	# The scale plate round the knob: ticks over the sweep, the arc it can turn through.
	c.draw_circle(centre + Vector2(0, 4), r * 1.36, Kit.HOUSING_DARK)
	c.draw_circle(centre, r * 1.36, Kit.METAL_DARK)
	c.draw_circle(centre, r * 1.3, Color(0.13, 0.15, 0.18))
	for i in 11:
		var a := deg_to_rad(-90.0 - KNOB_SWEEP * 0.5 + KNOB_SWEEP * float(i) / 10.0)
		var dir := Vector2.from_angle(a)
		c.draw_line(centre + dir * r * 1.12, centre + dir * r * (1.26 if i % 5 == 0 else 1.2), Color(Kit.HOUSING_LIGHT, 0.8), 3.0 if i % 5 == 0 else 2.0, true)
	var angle := deg_to_rad(-KNOB_SWEEP * 0.5 + KNOB_SWEEP * float(_local) / float(Rule.DIAL_MAX))
	Kit.draw_turned(c, Kit.tex("comms/tuning_knob"), centre, Vector2(r, r) * 2.0, angle, Color(0.8, 0.8, 0.8) if locked else Color.WHITE)
	var box := Rect2(centre - Vector2(r, r) * 1.38, Vector2(r, r) * 2.76)
	if locked:
		Kit.lock(c, centre, r * 0.32, true)
		return
	if not _matched():
		Kit.target_ring(c, box, r * 1.38, wants_less_motion())
		var at := centre + Vector2(r * 1.15, -r * 1.15)
		c.draw_circle(at, r * 0.24, Color(Kit.INK, 0.85))
		Kit.turn_arrows(c, at, r * 0.14, UiTheme.palette().focus)
	if _hover_knob and not _dragging:
		c.draw_circle(centre, r * 1.32, Color(1, 1, 1, 0.05))
	if dial.has_focus():
		Kit.focus_ring(c, box, r * 1.38, 4.0)


## The cable from the console to the dish, with data pulses running along it during the transfer.
func _paint_cable(c: Control) -> void:
	var scope := _scope_rect()
	var dish := _dish_rect()
	var y := minf(console.size.y * 0.9, console.size.y - 24.0)
	var foot := dish.position + DISH_FOOT * dish.size
	var path := PackedVector2Array([Vector2(scope.end.x - scope.size.x * 0.08, scope.end.y - 4.0),
		Vector2(scope.end.x - scope.size.x * 0.08, y), Vector2(foot.x, y), Vector2(foot.x, foot.y)])
	var w := clampf(console.size.y * 0.025, 8.0, 14.0)
	c.draw_polyline(path, Kit.METAL_DARK, w + 4.0, true)
	c.draw_polyline(path, Kit.METAL, w, true)
	if not (bool(_host.locked) or succeeded) or _arrived >= float(Rule.TRANSFER_STEPS):
		return
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	var good: Color = UiTheme.palette().good
	var t := 0.4 if wants_less_motion() else fposmod(_time / maxf(0.1, Rule.TRANSFER_SECONDS), 1.0)
	for k in 2:
		var at := _along(path, fposmod(t + 0.5 * float(k), 1.0) * length)
		c.draw_circle(at, w * 1.0, Kit.INK)
		c.draw_circle(at, w * 0.75, good.lightened(0.3))


static func _along(path: PackedVector2Array, distance: float) -> Vector2:
	var walked := 0.0
	for i in range(1, path.size()):
		var d := path[i - 1].distance_to(path[i])
		if walked + d >= distance and d > 0.0:
			return path[i - 1].lerp(path[i], (distance - walked) / d)
		walked += d
	return path[path.size() - 1]


func _paint_dish(c: Control) -> void:
	var dish := _dish_rect()
	Kit.draw_fill(c, Kit.tex("comms/relay_dish"), dish, Color.WHITE if (bool(_host.locked) or succeeded) else Color(0.78, 0.78, 0.8))
	var horn := dish.position + DISH_HORN * dish.size
	var done := succeeded or _arrived >= float(Rule.TRANSFER_STEPS)
	var r := dish.size.x * 0.16
	if done:
		# Signal arcs out of the feed horn, and the tick.
		var good: Color = UiTheme.palette().good
		for i in 3:
			var grow := 0.0 if wants_less_motion() else fposmod(_time * 0.8, 1.0) * 0.6
			var radius := r * (1.0 + 0.7 * float(i) + grow)
			c.draw_arc(horn, radius, -PI * 0.5 - 0.6, -PI * 0.5 + 0.6, 14, Color(good.lightened(0.3), 0.9 - 0.25 * float(i)), maxf(3.0, r * 0.18), true)
		Kit.tick(c, dish.position + Vector2(dish.size.x * 0.2, dish.size.y * 0.62), r * 0.8)
	elif bool(_host.locked) and not wants_less_motion():
		c.draw_circle(horn, r * 0.45, Color(UiTheme.palette().good, 0.35 + 0.35 * Kit.pulse(2.0)))
