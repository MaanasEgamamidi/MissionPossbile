extends "res://scripts/tasks/puzzles/med_ui.gd"
## T10 "Revive the Med Bay" mini-game (Med Bay, any role). UI overhaul 2026-11-15: the equipment is the interface, in
## the spirit of Among Us "Fix Wiring". One wide scene in a bay: the heal station on the left and the CT scanner on the
## right, each with its lead and a chunky plug lying in front of it (the heal station's plug is GREEN and ROUND, the
## scanner's BLUE and SQUARE); between them the power unit with four keyed sockets (green round, blue square and two
## look-alikes, green square and blue round, so colour AND shape matter) and a self-test button. A seated plug powers
## its machine at once, and each machine answers in its own way: the heal station's screen shows a beating pulse
## trace, the scanner's ring lights and a sweep runs round it. With both on, the self-test button glows; pressing it
## runs a short check across both screens and each one shows a tick.
## Controls: click a plug, then a socket, or drag the plug onto the socket; Tab / arrow keys move between plugs,
## sockets and the self-test, Enter / Space picks, places and presses. A wrong socket is refused by the host (gentle
## amber shake, the plug goes back). Only sends moves; the host rule (t10_rule.gd) decides everything.
## Public members read by tests and tools/godot/capture_puzzles.gd: lead_buttons, socket_buttons, test_button, held,
## device_state(), _can_drop() / _drop().
## Two-player task (2026-11-15): one player plugs in the left machine, a different player the right one; either one
## runs the self-test. The partner's plug shows up live (the panel redraws from the host's state).

const Rule := preload("res://scripts/tasks/puzzles/t10_rule.gd")
## Lead colours (designer art values, matching the BP02 leads: green and blue).
const COLOURS := {"green": Color(0.47, 0.78, 0.36), "blue": Color(0.36, 0.62, 0.95)}

## The design space the scene is laid out in (scaled uniformly to fit the board).
const DESIGN := Vector2(1000, 460)
## Heal station sprite (484 x 512): its screen.
const HEAL_SRC := Vector2(484, 512)
const HEAL_RECT := Rect2(22, 18, 283.6, 300)
const HEAL_SCREEN := Rect2(53, 61, 376, 202)
## CT scanner sprite (440 x 512): the ring (see-through hole) and the screen in its base.
const CT_SRC := Vector2(440, 512)
const CT_RECT := Rect2(716, 18, 257.8, 300)
const CT_HOLE := Vector2(219.5, 175)
const CT_HOLE_R := 70.0
const CT_RING_R := 160.0
const CT_SCREEN := Rect2(70, 344, 299, 111)
## The power unit, its sockets and the self-test button.
const UNIT := Rect2(352, 196, 296, 236)
const SOCKET_Y := 268.0
const SOCKET_X := [404.0, 468.0, 532.0, 596.0]
const SOCKET_W := 56.0
const TEST_RECT := Rect2(430, 340, 140, 62)
## Where each lead leaves its machine and where its plug lies while it is out.
const CABLE_FROM := [Vector2(163, 312), Vector2(845, 312)]
const PLUG_REST := [Vector2(262, 398), Vector2(738, 398)]
const PLUG_R := 30.0
const CABLE := Color(0.09, 0.1, 0.12)
## Seconds for the self-test sweep and for a refused socket to shake.
const TEST_SECONDS := 1.3
const SHAKE_SECONDS := 0.6
const PARTNER_LINE := "You did your machine! A second player has to plug in the other one."

var lead_buttons: Array[Button] = []
var socket_buttons: Array[Button] = []
var test_button: Button
## The plug being held (picked by click / keyboard), or -1.
var held := -1
## The scene (one drawn control) and the marks drawn over the buttons.
var canvas: DrawBox
var marks: DrawBox

var _k := 1.0
var _origin := Vector2.ZERO
var _dragging := -1
var _test_t := 0.0
var _shake_socket := -1
var _shake_left := 0.0
var _tried_socket := -1


func rule_script() -> Script:
	return Rule


func setup(p_services: GameServices) -> void:
	task_title = "Revive the Med Bay"
	instructions = ("Two-player job! Two Med Bay machines came unplugged. One player plugs in the LEFT machine, a "
		+ "different player plugs in the RIGHT one: each plug goes into the socket with the same colour and the same "
		+ "shape. With both on, either player presses the self-test button. Click a plug and then a socket, or drag "
		+ "it; Tab and Enter work too.")
	set_cue("Plug in the machines [Enter]")
	super.setup(p_services)
	name = "T10EquipmentPanel"


func build_game() -> void:
	canvas = DrawBox.new()
	canvas.name = "MedBay"
	canvas.custom_minimum_size = Vector2(900, 420)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.painter = _paint_scene
	Kit.smooth(canvas)
	play_area.add_child(canvas)
	for lead in Rule.LEADS:
		var b := _hit_button("Plug%d" % lead, "%s plug" % String(Rule.LEAD_INFO[lead][0]))
		b.pressed.connect(pick_lead.bind(lead))
		b.set_drag_forwarding(_drag_lead.bind(lead), Callable(), Callable())
		lead_buttons.append(b)
	for socket in Rule.SOCKETS:
		var b := _hit_button("Socket%d" % socket, "Socket")
		b.pressed.connect(pick_socket.bind(socket))
		b.set_drag_forwarding(Callable(), _can_drop.bind(socket), _drop.bind(socket))
		socket_buttons.append(b)
	test_button = _hit_button("SelfTest", "Self-test button")
	test_button.pressed.connect(run_test)
	marks = DrawBox.new()
	marks.name = "Marks"
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marks.painter = _paint_marks
	canvas.add_child(marks)
	canvas.resized.connect(_place)


func _hit_button(node_name: String, tip: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = tip
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for sig: Signal in [b.focus_entered, b.focus_exited, b.mouse_entered, b.mouse_exited]:
		sig.connect(_repaint)
	canvas.add_child(b)
	return b


## The keyboard starts on the first plug still out (or the self-test once both are in).
func first_focus() -> Control:
	if pending or lead_buttons.is_empty() or puzzle.is_empty() or succeeded:
		return super.first_focus()
	for lead in Rule.LEADS:
		if int(puzzle.plugged[lead]) == -1:
			return lead_buttons[lead]
	return test_button


## "off", "on" (plugged in, powered) or "ok" (self-test passed) for machine `lead` (0 heal station, 1 CT scanner).
func device_state(lead: int) -> String:
	if puzzle.is_empty():
		return "off"
	if bool(puzzle.tested):
		return "ok"
	return "on" if int(puzzle.plugged[lead]) != -1 else "off"


## Player picked up plug `lead` (keyboard / click).
func pick_lead(lead: int) -> void:
	if pending or succeeded or puzzle.is_empty():
		return
	if int(puzzle.plugged[lead]) != -1:
		hint("That plug is in already.")
		return
	if _partners_job(lead):
		hint(PARTNER_LINE)
		return
	held = -1 if held == lead else lead
	_repaint()


## Player picked socket `socket` (keyboard / click) while holding a plug.
func pick_socket(socket: int) -> void:
	if pending or succeeded or puzzle.is_empty():
		return
	if held == -1:
		hint("Pick up a plug first.")
		return
	plug(held, socket)


## Sends one plug move (also the drop target of a drag).
func plug(lead: int, socket: int) -> void:
	held = -1
	_tried_socket = socket
	send("plug", lead * 10 + socket)


func run_test() -> void:
	if pending or succeeded or puzzle.is_empty():
		return
	send("test", 0)


func _drag_lead(_at: Vector2, lead: int) -> Variant:
	if pending or succeeded or puzzle.is_empty() or int(puzzle.plugged[lead]) != -1:
		return null
	if _partners_job(lead):
		hint(PARTNER_LINE)
		return null
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := DrawBox.new()
	var r := PLUG_R * _k
	head.size = Vector2(r, r) * 2.6
	head.position = -head.size * 0.5
	head.painter = func(c: Control) -> void: _draw_plug_head(c, lead, c.size * 0.5, r, false)
	holder.add_child(head)
	lead_buttons[lead].set_drag_preview(holder)
	_dragging = lead
	held = -1
	_repaint()
	return {"t10_lead": lead}


## True when this player already plugged in the other machine, so `lead` is for the second player.
func _partners_job(lead: int) -> bool:
	return services != null and Rule.partners_job(puzzle, lead, services.local_peer())


func _can_drop(_at: Vector2, data: Variant, _socket: int) -> bool:
	return data is Dictionary and (data as Dictionary).has("t10_lead") and not pending and not succeeded


func _drop(_at: Vector2, data: Variant, socket: int) -> void:
	if _can_drop(_at, data, socket):
		_dragging = -1
		plug(int((data as Dictionary).t10_lead), socket)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _dragging != -1:
		_dragging = -1
		_repaint()


func redraw() -> void:
	if puzzle.is_empty() or canvas == null:
		return
	var plugged: Array = puzzle.plugged
	if bool(puzzle.tested):
		if wants_less_motion():
			_test_t = 1.0
	else:
		_test_t = 0.0
	for lead in Rule.LEADS:
		var words := "%s plug" % String(Rule.LEAD_INFO[lead][0])
		lead_buttons[lead].tooltip_text = words + (" (in)" if int(plugged[lead]) != -1 else "")
	for socket in Rule.SOCKETS:
		socket_buttons[socket].tooltip_text = "Socket, %s%s" % [_kind_words(int(puzzle.sockets[socket])),
			" (in use)" if plugged.has(socket) else ""]
	set_cue("Run the self-test [Enter]" if not plugged.has(-1) else "Plug in the machines [Enter]")
	_place()
	_repaint()


func explain(move: Dictionary) -> String:
	var payload := int(move.get("value", 0))
	match String(move.get("move", "")):
		"plug":
			var lead := payload / 10
			var socket := payload % 10
			if lead >= Rule.LEADS or socket >= Rule.SOCKETS:
				return "Pick a plug, then a socket."
			if (puzzle.plugged as Array).has(socket):
				return "That socket is full."
			if int(puzzle.plugged[lead]) != -1:
				return "That plug is in already."
			if _partners_job(lead):
				return PARTNER_LINE
			_shake_socket = socket
			_shake_left = SHAKE_SECONDS
			_repaint()
			var want: Array = Rule.KINDS[Rule.lead_kind(lead)]
			var have: Array = Rule.KINDS[int(puzzle.sockets[socket])]
			if want[0] != have[0] and want[1] != have[1]:
				return "Wrong colour and shape. Look again!"
			if want[0] != have[0]:
				return "Wrong colour. Match both!"
			return "Wrong shape. Match both!"
		"test":
			return "Plug in both machines first."
		"reset":
			return "Nothing is plugged in yet."
	return "That doesn't work here."


func praise(move: Dictionary) -> String:
	match String(move.get("move", "")):
		"plug":
			if not (puzzle.plugged as Array).has(-1):
				return "Both on! Now the self-test."
			var lead := int(move.get("value", 0)) % STEP_BASE / 10
			var line := "Click! The heal station is on." if lead == 0 else "Click! The scanner is on."
			return line + " Now a second player plugs in the other machine."
		"reset":
			return "Both plugs are out."
	return "Done."


func solved_text() -> String:
	return "Fixed! Both machines pass."


func _kind_words(kind: int) -> String:
	var info: Array = Rule.KINDS[kind]
	return "%s %s" % [info[0], info[1]]


func _process(delta: float) -> void:
	super._process(delta)
	if canvas == null or not canvas.is_visible_in_tree():
		return
	if not puzzle.is_empty() and bool(puzzle.tested):
		_test_t = 1.0 if wants_less_motion() else minf(1.0, _test_t + delta / TEST_SECONDS)
	if _shake_left > 0.0:
		_shake_left -= delta
		if _shake_left <= 0.0:
			_shake_socket = -1
	_repaint()


func _repaint() -> void:
	if canvas == null or marks == null:
		return
	canvas.queue_redraw()
	marks.queue_redraw()


# ---------------------------------------------------------------- layout

func _p(v: Vector2) -> Vector2:
	return _origin + v * _k


func _r(rect: Rect2) -> Rect2:
	return Rect2(_p(rect.position), rect.size * _k)


func _place() -> void:
	if canvas == null or canvas.size.x <= 0.0 or canvas.size.y <= 0.0:
		return
	_k = minf(canvas.size.x / DESIGN.x, canvas.size.y / DESIGN.y)
	_origin = ((canvas.size - DESIGN * _k) * 0.5).round()
	for lead in Rule.LEADS:
		var r := _plug_radius(lead) * 1.35
		var rect := Rect2(_plug_at(lead) - Vector2(r, r), Vector2(r, r) * 2.0)
		lead_buttons[lead].position = rect.position
		lead_buttons[lead].size = rect.size
	for socket in Rule.SOCKETS:
		var rect := _socket_rect(socket).grow(4.0)
		socket_buttons[socket].position = rect.position
		socket_buttons[socket].size = rect.size
	var t := _r(TEST_RECT)
	test_button.position = t.position
	test_button.size = t.size


func _socket_rect(socket: int) -> Rect2:
	var rect := _r(Rect2(float(SOCKET_X[socket]) - SOCKET_W * 0.5, SOCKET_Y - SOCKET_W * 0.5, SOCKET_W, SOCKET_W))
	if socket == _shake_socket and _shake_left > 0.0 and not wants_less_motion():
		rect.position.x += sin(_shake_left * 40.0) * 5.0 * (_shake_left / SHAKE_SECONDS)
	return rect


## Where plug `lead`'s head is drawn: in its socket, lifted while held, or lying in front of its machine.
func _plug_at(lead: int) -> Vector2:
	if puzzle.is_empty():
		return _p(PLUG_REST[lead])
	var socket := int(puzzle.plugged[lead])
	if socket != -1:
		return _socket_rect(socket).get_center()
	var at := _p(PLUG_REST[lead])
	if held == lead:
		at += Vector2(0.0, -16.0) * _k
	return at


func _plug_radius(lead: int) -> float:
	var seated := not puzzle.is_empty() and int(puzzle.plugged[lead]) != -1
	return (SOCKET_W * 0.36 if seated else PLUG_R) * _k


# ---------------------------------------------------------------- drawing

func _paint_scene(c: Control) -> void:
	Kit.bay(c, Rect2(Vector2.ZERO, c.size))
	if _k <= 0.0 or puzzle.is_empty():
		return
	# The floor line the machines stand on.
	Kit.box(c, _r(Rect2(14, 312, 972, 8)), Kit.BAY_LIP, 4.0)
	_draw_heal_station(c)
	_draw_scanner(c)
	_draw_unit(c)
	for lead in Rule.LEADS:
		if lead == _dragging:
			_draw_cable(c, lead, _p(PLUG_REST[lead]) + Vector2(0, 12) * _k, 0.5)
			continue
		_draw_cable(c, lead, _plug_at(lead), 1.0)
		if held == lead:
			c.draw_circle(_plug_at(lead) + Vector2(5, 14) * _k, _plug_radius(lead), Color(0, 0, 0, 0.35))
		_draw_plug_head(c, lead, _plug_at(lead), _plug_radius(lead), int(puzzle.plugged[lead]) != -1)


func _draw_heal_station(c: Control) -> void:
	var rect := _r(HEAL_RECT)
	var t := Kit.tex("medbay/heal_station")
	if t != null:
		c.draw_texture_rect(t, rect, false)
	var k := rect.size.x / HEAL_SRC.x
	var screen := Rect2(rect.position + HEAL_SCREEN.position * k, HEAL_SCREEN.size * k).grow(-4.0 * _k)
	var state := device_state(0)
	if state == "off":
		_power_symbol(c, screen.get_center(), screen.size.y * 0.16)
		return
	var good: Color = UiTheme.palette().good
	c.draw_rect(screen, Color(0.04, 0.16, 0.1))
	for gx in 6:
		var x := screen.position.x + screen.size.x * float(gx + 1) / 7.0
		c.draw_line(Vector2(x, screen.position.y), Vector2(x, screen.end.y), Color(good, 0.12), 1.0)
	# The pulse trace: a heartbeat that scrolls across the screen.
	var time := 0.35 if wants_less_motion() else float(Time.get_ticks_msec()) * 0.001
	var mid := screen.position.y + screen.size.y * 0.55
	var amp := screen.size.y * 0.32
	var pts := PackedVector2Array()
	for s in 81:
		var u := float(s) / 80.0
		var phase := fposmod(u * 2.0 - time * 0.8, 1.0)
		var y := 0.0
		if phase > 0.40 and phase < 0.44:
			y = -0.25
		elif phase >= 0.46 and phase < 0.50:
			y = 1.0
		elif phase >= 0.50 and phase < 0.53:
			y = -0.45
		elif phase > 0.62 and phase < 0.70:
			y = 0.18 * sin((phase - 0.62) / 0.08 * PI)
		pts.append(Vector2(screen.position.x + u * screen.size.x, mid - y * amp))
	c.draw_polyline(pts, Color(good.lightened(0.4), 0.35), maxf(4.0, 7.0 * _k), true)
	c.draw_polyline(pts, good.lightened(0.5), maxf(2.0, 3.0 * _k), true)
	# A heart that beats with the trace (shape, not colour alone).
	var beat := 1.0 if wants_less_motion() else 0.9 + 0.2 * Kit.pulse(1.6)
	_heart(c, screen.position + Vector2(screen.size.x * 0.12, screen.size.y * 0.22), screen.size.y * 0.1 * beat, good.lightened(0.3))
	_draw_check(c, screen)


func _draw_scanner(c: Control) -> void:
	var rect := _r(CT_RECT)
	var k := rect.size.x / CT_SRC.x
	var hole := rect.position + CT_HOLE * k
	var state := device_state(1)
	var time := 0.0 if wants_less_motion() else float(Time.get_ticks_msec()) * 0.001
	var cyan := Color(0.5, 0.9, 1.0)
	if state != "off":
		# Light through the ring's hole.
		c.draw_circle(hole, CT_HOLE_R * k, Color(0.2, 0.55, 0.7, 0.45))
	var t := Kit.tex("medbay/ct_scanner")
	if t != null:
		c.draw_texture_rect(t, rect, false)
	var screen := Rect2(rect.position + CT_SCREEN.position * k, CT_SCREEN.size * k).grow(-3.0 * _k)
	if state == "off":
		_power_symbol(c, screen.get_center(), screen.size.y * 0.24)
		return
	# The sweep: a bright arc running round the ring, and a scan line across the base screen.
	var mid_r := (CT_HOLE_R + CT_RING_R) * 0.5 * k
	var start := 0.6 if wants_less_motion() else time * 2.4
	for n in 8:
		var a := start - float(n) * 0.14
		c.draw_arc(hole, mid_r, a - 0.16, a, 10, Color(cyan.lightened(0.3), 0.95 - 0.11 * float(n)), (CT_RING_R - CT_HOLE_R) * k * 0.42, true)
	c.draw_arc(hole, CT_HOLE_R * k + 2.0, 0.0, TAU, 48, Color(cyan, 0.9), maxf(2.0, 4.0 * _k), true)
	c.draw_rect(screen, Color(0.03, 0.12, 0.17))
	for row in 3:
		var y := screen.position.y + screen.size.y * (0.3 + 0.2 * float(row))
		c.draw_line(Vector2(screen.position.x + 8.0 * _k, y), Vector2(screen.end.x - 8.0 * _k, y), Color(cyan, 0.18), 1.0)
	var sweep := 0.5 + 0.5 * sin(time * 2.4) if not wants_less_motion() else 0.62
	var x := screen.position.x + screen.size.x * (0.06 + 0.88 * sweep)
	c.draw_line(Vector2(x, screen.position.y + 4.0), Vector2(x, screen.end.y - 4.0), cyan, maxf(2.0, 4.0 * _k), true)
	c.draw_rect(Rect2(screen.position.x, screen.position.y, x - screen.position.x, screen.size.y), Color(cyan, 0.12))
	_draw_check(c, screen)


## The self-test on a machine's screen: a bar that fills, then a tick.
func _draw_check(c: Control, screen: Rect2) -> void:
	if device_state(0) != "ok":
		return
	var bar := Rect2(screen.position.x + screen.size.x * 0.1, screen.end.y - screen.size.y * 0.16, screen.size.x * 0.8, screen.size.y * 0.08)
	Kit.box(c, bar, Color(0, 0, 0, 0.5), 4.0)
	Kit.box(c, Rect2(bar.position, Vector2(bar.size.x * _test_t, bar.size.y)), UiTheme.palette().good.lightened(0.2), 4.0)
	if _test_t >= 1.0:
		Kit.tick(c, Vector2(screen.end.x - screen.size.y * 0.24, screen.position.y + screen.size.y * 0.26), screen.size.y * 0.2)


## "Off": a dim power symbol on a dark screen.
func _power_symbol(c: Control, at: Vector2, r: float) -> void:
	var dim := Color(0.45, 0.5, 0.55, 0.7)
	c.draw_arc(at, r, -PI * 0.5 + 0.6, PI * 1.5 - 0.6, 24, dim, maxf(2.0, r * 0.2), true)
	c.draw_line(at - Vector2(0, r * 1.15), at - Vector2(0, r * 0.2), dim, maxf(2.0, r * 0.2), true)


func _heart(c: Control, at: Vector2, r: float, color: Color) -> void:
	c.draw_circle(at + Vector2(-r * 0.5, 0), r * 0.55, color)
	c.draw_circle(at + Vector2(r * 0.5, 0), r * 0.55, color)
	c.draw_colored_polygon(PackedVector2Array([at + Vector2(-r * 1.02, r * 0.15), at + Vector2(r * 1.02, r * 0.15), at + Vector2(0, r * 1.25)]), color)


func _draw_unit(c: Control) -> void:
	var unit := _r(UNIT)
	Kit.housing(c, unit, 18.0 * _k)
	# A power bolt on top (no words).
	_bolt(c, _p(Vector2(UNIT.get_center().x, UNIT.position.y + 26.0)), 13.0 * _k)
	var strip := _r(Rect2(UNIT.position.x + 22.0, SOCKET_Y - 40.0, UNIT.size.x - 44.0, 80.0))
	Kit.box(c, strip, Kit.METAL_DARK, 10.0 * _k, Kit.INK, 2.0)
	for socket in Rule.SOCKETS:
		_draw_socket(c, socket)
	# The self-test button: dim until both machines have power, then lit; a tick once the test passed.
	var b := _r(TEST_RECT)
	var both := not (puzzle.plugged as Array).has(-1)
	var good: Color = UiTheme.palette().good
	Kit.box(c, Rect2(b.position + Vector2(0, 5) * _k, b.size), Kit.INK, b.size.y * 0.5)
	var face := good.darkened(0.15) if both else Kit.METAL
	if test_button.button_pressed:
		b.position.y += 3.0 * _k
	Kit.box(c, b, face, b.size.y * 0.5, face.lightened(0.3), 2.0)
	var icon := b.get_center()
	var s := b.size.y * 0.22
	if bool(puzzle.tested):
		Kit.tick(c, icon, s * 1.3)
		return
	var ink := Color.WHITE if both else Color(Kit.INK, 0.7)
	# A heartbeat with a play arrow: "check the machines".
	c.draw_polyline(PackedVector2Array([icon + Vector2(-s * 3.0, 0), icon + Vector2(-s * 1.6, 0), icon + Vector2(-s * 1.1, -s),
		icon + Vector2(-s * 0.5, s), icon + Vector2(0, 0), icon + Vector2(s * 0.6, 0)]), ink, maxf(2.0, s * 0.3), true)
	c.draw_colored_polygon(PackedVector2Array([icon + Vector2(s * 1.4, -s), icon + Vector2(s * 2.8, 0), icon + Vector2(s * 1.4, s)]), ink)


func _bolt(c: Control, at: Vector2, r: float) -> void:
	c.draw_colored_polygon(PackedVector2Array([at + Vector2(r * 0.2, -r), at + Vector2(-r * 0.55, r * 0.15), at + Vector2(-r * 0.05, r * 0.15),
		at + Vector2(-r * 0.2, r), at + Vector2(r * 0.55, -r * 0.15), at + Vector2(r * 0.05, -r * 0.15)]), Kit.HAZARD)


func _draw_socket(c: Control, socket: int) -> void:
	var rect := _socket_rect(socket)
	Kit.box(c, rect, Color(0.13, 0.15, 0.18), 8.0 * _k, Kit.METAL, 2.0)
	var info: Array = Rule.KINDS[int(puzzle.sockets[socket])]
	var color: Color = COLOURS[String(info[0])]
	var kind := Kit.CIRCLE if String(info[1]) == "round" else Kit.SQUARE
	var r := rect.size.x * 0.36
	# The key: the socket's shape as a hollow outline in its colour.
	Kit.shape(c, kind, rect.get_center(), r, color, color.darkened(0.5))
	Kit.shape(c, kind, rect.get_center(), r * 0.66, Color(0.03, 0.035, 0.04), Color(0.03, 0.035, 0.04))
	var lamp := rect.get_center() + Vector2(0, -rect.size.y * 0.68)
	c.draw_circle(lamp, 5.0 * _k, Kit.INK)
	c.draw_circle(lamp, 3.6 * _k, UiTheme.palette().good if (puzzle.plugged as Array).has(socket) else Kit.METAL_DARK)


## Plug `lead`'s chunky head: GREEN ROUND for the heal station, BLUE SQUARE for the scanner, with two prongs and a
## white mark of its shape.
func _draw_plug_head(c: Control, lead: int, at: Vector2, r: float, seated: bool) -> void:
	var info: Array = Rule.KINDS[Rule.lead_kind(lead)]
	var color: Color = COLOURS[String(info[0])]
	var kind := Kit.CIRCLE if String(info[1]) == "round" else Kit.SQUARE
	if not seated:
		for side: float in [-1.0, 1.0]:
			Kit.box(c, Rect2(at + Vector2(side * r * 0.32 - r * 0.08, -r * 1.35), Vector2(r * 0.16, r * 0.5)), Kit.METAL, 2.0)
	if kind == Kit.SQUARE:
		r *= 1.12
	Kit.shape(c, kind, at, r, color, Kit.INK)
	Kit.shape(c, kind, at, r * 0.78, color.lightened(0.12), color.darkened(0.35))
	Kit.shape(c, kind, at, r * 0.34, Color.WHITE, Kit.INK)


## The lead from its machine to its plug: down from the machine, along the floor, up into the plug.
func _draw_cable(c: Control, lead: int, to: Vector2, alpha: float) -> void:
	var from := _p(CABLE_FROM[lead])
	var seated := int(puzzle.plugged[lead]) != -1
	var low := maxf(from.y, to.y) + (70.0 if seated else 40.0) * _k
	var c1 := Vector2(from.x, low)
	var c2 := Vector2(to.x, low + (0.0 if seated else 10.0 * _k))
	var pts := PackedVector2Array()
	for s in 33:
		var t := float(s) / 32.0
		var u := 1.0 - t
		pts.append(from * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + to * t * t * t)
	var info: Array = Rule.KINDS[Rule.lead_kind(lead)]
	var color: Color = COLOURS[String(info[0])]
	c.draw_polyline(pts, Color(CABLE, alpha), maxf(6.0, 16.0 * _k), true)
	c.draw_polyline(pts, Color(color.darkened(0.3), alpha), maxf(3.0, 9.0 * _k), true)


## The shared marks over the buttons: hover, the target ring (the plug to pick; while a plug is held, every free
## socket; with both in, the self-test), the focus ring and an amber cross on a refused socket.
func _paint_marks(c: Control) -> void:
	if _k <= 0.0 or puzzle.is_empty():
		return
	var less := wants_less_motion()
	var all: Array[Button] = []
	all.append_array(lead_buttons)
	all.append_array(socket_buttons)
	all.append(test_button)
	for b in all:
		if b.is_hovered() and not b.disabled and not b.has_focus():
			Kit.box(c, Rect2(b.position, b.size), Color(1, 1, 1, 0.05), 12.0 * _k, Color(1, 1, 1, 0.5), 2.0)
	var plugged: Array = puzzle.plugged
	if not succeeded and not pending:
		if held != -1 or _dragging != -1:
			for socket in Rule.SOCKETS:
				if not plugged.has(socket):
					Kit.target_ring(c, _socket_rect(socket).grow(5.0), 10.0 * _k, less)
		elif plugged.has(-1):
			var lead := plugged.find(-1)
			var r := _plug_radius(lead) * 1.3
			Kit.target_ring(c, Rect2(_plug_at(lead) - Vector2(r, r), Vector2(r, r) * 2.0), r, less)
		elif not bool(puzzle.tested):
			Kit.target_ring(c, Rect2(test_button.position, test_button.size), test_button.size.y * 0.5, less)
	for b in all:
		if b.has_focus():
			var rect := Rect2(b.position, b.size)
			var radius := 12.0 * _k
			var at := lead_buttons.find(b)
			if at != -1:
				rect = Rect2(_plug_at(at) - Vector2.ONE * _plug_radius(at) * 1.3, Vector2.ONE * _plug_radius(at) * 2.6)
				radius = rect.size.x * 0.5 if at == 0 else 12.0 * _k
			elif b == test_button:
				radius = rect.size.y * 0.5
			Kit.focus_ring(c, rect, radius, 4.0)
	if _shake_socket != -1:
		var rect := _socket_rect(_shake_socket)
		Kit.cross(c, rect.position + Vector2(rect.size.x * 0.95, rect.size.y * 0.05), maxf(8.0, 12.0 * _k))
