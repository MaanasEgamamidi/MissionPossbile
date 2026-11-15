extends "res://scripts/tasks/puzzles/electric_ui.gd"
## T02 "Patch the Relay" mini-game (Command Room wiring rack, BP03; electrical specialist only). UI overhaul
## 2026-11-15: the equipment is the interface, in the spirit of Among Us "Fix Wiring". One wide apparatus in a bay:
## four cables come out of a conduit on the left, each ending in a chunky plug (the pair's colour, with its shape
## stamped on the body); in the middle a patch bay with four shape-keyed sockets (the hollow shape in the hole, in the
## pair's colour); on the right the relay. A seated plug sits in its socket, the socket lights up and a lit trace
## (with moving sparks, so never colour alone) runs from it to the relay; the relay's lens lights once all four are in.
## Pairs: Rule.SHAPES (triangle, circle, square, diamond) in Rule.COLORS; the plug of left terminal i carries pair
## layout.left[i], the socket of right terminal j pair layout.right[j].
## Controls: click a plug, then its socket, or drag the plug onto the socket; Tab / arrow keys move between plugs and
## sockets, Enter / Space picks and places. The host rule (t02_rule.gd) checks every connection; a wrong socket is
## refused (gentle amber shake, the plug goes back), a right one locks.
## Public members read by tests and tools/godot/capture_puzzles.gd: left_buttons (plugs), right_buttons (sockets).
## Wrong specialist (concept: "show the electrical specialist badge where the first plug would be"): PuzzleRegistry
## opens this panel locked (set_locked) instead of the shell's scrambled view. The bay is dimmed with no plugs, the
## badge (padlock + the specialist's symbol) sits in a target ring where the first plug would be, every plug and
## socket is disabled, and nothing is ever sent (TaskPanel.unreadable blocks the claim, the moves and the release).

const Rule := preload("res://scripts/tasks/puzzles/t02_rule.gd")
## Rule.SHAPES (electric_ui order: triangle, circle, square, diamond) as Kit shape kinds.
const KIT_SHAPE := [Kit.TRIANGLE, Kit.CIRCLE, Kit.SQUARE, Kit.DIAMOND]

## The design space the apparatus is laid out in (scaled uniformly to fit the board).
const DESIGN := Vector2(1000, 460)
const ROW_Y := [80.0, 180.0, 280.0, 380.0]
const TRUNK := Rect2(26, 22, 46, 416)
## Plug sprite: 512 x 222, cord on the left, prongs on the right; drawn PLUG_W wide.
const PLUG_SRC := Vector2(512, 222)
const PLUG_W := 176.0
const DOCK_X := 112.0
## Socket sprite: 511 x 512, the hole centred with radius about 0.325 of the width.
const SOCKET_X := 520.0
const SOCKET_W := 90.0
const HOLE_R := 0.3
const BAY_PLATE := Rect2(436, 18, 168, 424)
## Relay sprite: 294 x 512, the lens centred at (145, 227) with radius 60.
const RELAY_SRC := Vector2(294, 512)
const RELAY_RECT := Rect2(764, 40, 190, 330.9)
const LENS := Vector2(145.5, 227.5)
const LENS_R := 58.0
## Where each socket's trace enters the relay, and the x of its vertical run (top to bottom by row).
const ENTRY_Y := [250.0, 280.0, 310.0, 340.0]
const RUN_X := [700.0, 668.0, 636.0, 700.0]
const CABLE_EDGE := Color(0.05, 0.06, 0.08)
const TRACE_OFF := Color(0.24, 0.27, 0.31)
## Seconds for a plug to slide in, for the light to run to the relay, and for a refused plug to shake.
const SEAT_SECONDS := 0.18
const TRACE_SECONDS := 0.45
const SHAKE_SECONDS := 0.6

## The plugs (left terminals) and the sockets (right terminals), by terminal index.
var left_buttons: Array[Button] = []
var right_buttons: Array[Button] = []
## The apparatus (one drawn control) and the marks drawn over the buttons.
var canvas: DrawBox
var marks: DrawBox

var _layout: Dictionary = {"left": [0, 1, 2, 3], "right": [0, 1, 2, 3]}
var _links: Array = [-1, -1, -1, -1]
var _shown_links: Array = []
var _selected := -1
var _drag_left := -1
var _drag_active := false
var _drag_from := Vector2.ZERO
var _mouse := Vector2.ZERO
var _attempt := Vector2i(-1, -1)
var _k := 1.0
var _origin := Vector2.ZERO
var _seat := PackedFloat32Array([1, 1, 1, 1])
var _trace := PackedFloat32Array([0, 0, 0, 0])
var _shake_socket := -1
var _shake_left := 0.0
## Locked for a crew member who cannot do this repair (set_locked). The badge drawn where the first plug would be.
var locked := false
var badge: PanelContainer
var _locked_line := ""


## This panel draws its own wrong-specialist view (PuzzleRegistry.make_panel asks).
static func supports_locked_view() -> bool:
	return true


## Locks (or unlocks) the panel for a crew member of another specialty. Call before setup() (make_panel does).
## line: how to get the right specialist (PuzzleRegistry.unreadable_line), shown under the bay.
func set_locked(on: bool, line := "") -> void:
	locked = on
	unreadable = on
	_locked_line = line
	if ui_ready and on:
		_apply_locked()


func setup(p_services: GameServices) -> void:
	task_title = "Patch the Relay"
	instructions = ("Every plug has a shape. Put each plug into the socket with the same shape. "
		+ "Click a plug and then its socket, or drag it across. Keyboard: Tab or arrow keys to move, Enter to pick.")
	super.setup(p_services)
	if ui_ready:
		return
	name = "RelayPanel"
	canvas = DrawBox.new()
	canvas.name = "PatchBay"
	canvas.custom_minimum_size = Vector2(900, 420)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.painter = _paint_equipment
	Kit.smooth(canvas)
	play_area.add_child(canvas)
	for i in Rule.PAIRS:
		var plug := _hit_button("Plug%d" % i)
		plug.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		plug.pressed.connect(_on_left_pressed.bind(i))
		plug.button_down.connect(_on_left_down.bind(i))
		left_buttons.append(plug)
	for j in Rule.PAIRS:
		var socket := _hit_button("Socket%d" % j)
		socket.pressed.connect(_on_right_pressed.bind(j))
		right_buttons.append(socket)
	for i in Rule.PAIRS:
		var up := posmod(i - 1, Rule.PAIRS)
		var down := posmod(i + 1, Rule.PAIRS)
		left_buttons[i].focus_neighbor_top = NodePath("../Plug%d" % up)
		left_buttons[i].focus_neighbor_bottom = NodePath("../Plug%d" % down)
		left_buttons[i].focus_neighbor_right = NodePath("../Socket%d" % i)
		right_buttons[i].focus_neighbor_top = NodePath("../Socket%d" % up)
		right_buttons[i].focus_neighbor_bottom = NodePath("../Socket%d" % down)
		right_buttons[i].focus_neighbor_left = NodePath("../Plug%d" % i)
	marks = DrawBox.new()
	marks.name = "Marks"
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marks.painter = _paint_marks
	canvas.add_child(marks)
	canvas.resized.connect(_place)
	reset_requested.connect(func() -> void:
		_selected = -1
		send_move("reset", 0))
	set_cue("Match the shapes [Enter]")
	ui_ready = true
	refresh_from_host()
	if locked:
		_apply_locked()


## The locked view: the badge over the first plug's place, one short cue, the how-to line, nothing to press.
func _apply_locked() -> void:
	if badge == null:
		badge = PanelContainer.new()
		badge.name = "SpecialistBadge"
		badge.theme_type_variation = UiTheme.CARD
		badge.mouse_filter = Control.MOUSE_FILTER_PASS
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(row)
		var padlock := Control.new()
		padlock.name = "Padlock"
		padlock.custom_minimum_size = Vector2(60, 70)
		padlock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		padlock.draw.connect(func() -> void:
			Kit.lock(padlock, padlock.size * 0.5 + Vector2(0, 6), 26.0, true, UiTheme.palette().warn))
		row.add_child(padlock)
		var symbol := Label.new()
		symbol.name = "Symbol"
		symbol.text = String(StationPanels.SPECIALTY_SYMBOLS.get(StringName(required_role), "●"))
		symbol.theme_type_variation = UiTheme.DISPLAY
		symbol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(symbol)
		canvas.add_child(badge)
		badge.resized.connect(_place)
		unreadable_label = _label("UnreadableLine", UiTheme.WARN)
		unreadable_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		play_area.add_child(unreadable_label)
	badge.tooltip_text = _locked_line
	unreadable_label.text = _locked_line
	unreadable_label.visible = not _locked_line.is_empty()
	_selected = -1
	_drag_left = -1
	progress_bar.visible = false
	reset_button.visible = false
	set_cue("Electrical engineer only")
	_update_enabled()
	_place()
	_repaint()


## TaskPanel re-enables the equipment after every host answer; a locked bay stays shut.
func _update_enabled() -> void:
	super._update_enabled()
	if not locked:
		return
	for b: Button in left_buttons + right_buttons:
		b.disabled = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_ARROW
		b.tooltip_text = _locked_line


func _hit_button(node_name: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_entered.connect(_repaint)
	b.focus_exited.connect(_repaint)
	b.mouse_entered.connect(_repaint)
	b.mouse_exited.connect(_repaint)
	canvas.add_child(b)
	return b


## The keyboard starts on the first plug still out.
func first_focus() -> Control:
	if pending or locked or left_buttons.is_empty():
		return cancel_button
	for i in Rule.PAIRS:
		if int(_links[i]) < 0 and not succeeded:
			return left_buttons[i]
	return left_buttons[0]


func _pair_name(pair: int) -> String:
	return "%s %s" % [Rule.NAMES[pair], Rule.SHAPE_NAMES[pair]]


func _on_host_state(seed_value: int, _puzzle: Dictionary, record: Dictionary) -> void:
	_layout = Rule.layout(seed_value)
	_links = Rule.links_of(record)
	var less := wants_less_motion()
	var fresh := 0
	for i in Rule.PAIRS:
		var seated := int(_links[i]) >= 0
		var was := _shown_links.size() == Rule.PAIRS and int(_shown_links[i]) >= 0
		if seated and not was and _shown_links.size() == Rule.PAIRS:
			fresh += 1
			_seat[i] = 1.0 if less else 0.0
			_trace[i] = 1.0 if less else 0.0
		elif not seated:
			_seat[i] = 1.0
			_trace[i] = 0.0
		elif _shown_links.size() != Rule.PAIRS:
			_seat[i] = 1.0
			_trace[i] = 1.0
		if seated and _selected == i:
			_selected = -1
	_shown_links = _links.duplicate()
	for i in Rule.PAIRS:
		var lp := int(_layout.left[i])
		left_buttons[i].tooltip_text = "Plug, %s%s" % [_pair_name(lp), " (in)" if int(_links[i]) >= 0 else ""]
		var rp := int(_layout.right[i])
		right_buttons[i].tooltip_text = "Socket, %s%s" % [_pair_name(rp), " (full)" if _links.has(i) else ""]
	if locked:
		_update_enabled()          # the plug and socket names are not for the wrong specialist
	elif fresh > 0 and not succeeded:
		_say("Click! It fits.", &"good")
	_place()
	_repaint()


func _on_solved() -> void:
	_selected = -1
	_say("The relay is live!", &"good")


func _say(text: String, kind: StringName) -> void:
	status_label.text = text
	status_label.theme_type_variation = UiTheme.GOOD if kind == &"good" else (UiTheme.WARN if kind == &"warn" else &"")
	flash(text, kind)


func _on_left_pressed(i: int) -> void:
	if _drag_active:
		return
	if int(_links[i]) >= 0:
		_say("That plug is in already.", &"")
		return
	_selected = -1 if _selected == i else i
	_repaint()


func _on_left_down(i: int) -> void:
	if int(_links[i]) >= 0 or pending or succeeded or locked:
		return
	_drag_left = i
	_drag_active = false
	_drag_from = get_global_mouse_position()
	_mouse = _drag_from


func _on_right_pressed(j: int) -> void:
	if _links.has(j):
		_say("That socket is full.", &"")
		return
	if _selected < 0:
		_say("Pick a plug first.", &"")
		return
	var i := _selected
	_selected = -1
	_connect(i, j)


func _connect(i: int, j: int) -> void:
	if locked:
		return
	_attempt = Vector2i(i, j)
	send_move("connect", i * 10 + j)
	refresh_from_host()


func _input(event: InputEvent) -> void:
	if _drag_left < 0 or not ui_ready:
		return
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).global_position
		if not _drag_active and _mouse.distance_to(_drag_from) > 10.0:
			_drag_active = true
			_selected = -1
		_repaint()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not event.is_pressed():
		var from := _drag_left
		var was_active := _drag_active
		_drag_left = -1
		if was_active:
			var target := _right_under((event as InputEventMouseButton).global_position)
			if target >= 0:
				_connect(from, target)
			# Let the plug button's own release run first, then clear the flag.
			set_deferred(&"_drag_active", false)
		_repaint()


func _right_under(global_point: Vector2) -> int:
	for j in right_buttons.size():
		if right_buttons[j].get_global_rect().grow(10.0).has_point(global_point):
			return j
	return -1


func _explain_rejection(_move: Dictionary) -> String:
	var i := _attempt.x
	var j := _attempt.y
	if i < 0 or j < 0:
		return ""
	if int(_links[i]) >= 0:
		return "That plug is in already."
	if _links.has(j):
		return "That socket is full."
	_shake_socket = j
	_shake_left = SHAKE_SECONDS
	_repaint()
	return "Not that one. Match the shape!"


func _process(delta: float) -> void:
	super._process(delta)
	if canvas == null or not canvas.is_visible_in_tree():
		return
	var less := wants_less_motion()
	for i in Rule.PAIRS:
		_seat[i] = 1.0 if less else move_toward(_seat[i], 1.0, delta / SEAT_SECONDS)
		if _seat[i] >= 1.0 and int(_links[i]) >= 0:
			_trace[i] = 1.0 if less else move_toward(_trace[i], 1.0, delta / TRACE_SECONDS)
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
	for i in Rule.PAIRS:
		var rect := _plug_rect(i, 1.0).grow(6.0)
		if int(_links[i]) >= 0:
			rect.size.x = minf(rect.size.x, _socket_rect(int(_links[i])).position.x - rect.position.x - 4.0)
		left_buttons[i].position = rect.position
		left_buttons[i].size = rect.size
	for j in Rule.PAIRS:
		var rect := _socket_rect(j).grow(6.0)
		right_buttons[j].position = rect.position
		right_buttons[j].size = rect.size
	if badge != null:
		badge.reset_size()
		badge.position = (_plug_rect(0, 1.0).get_center() - badge.size * 0.5).round()


## The plug of left terminal i, where it is drawn: in its dock, or (seat 0..1 of the way) in its socket.
func _plug_rect(i: int, seat: float) -> Rect2:
	var h := PLUG_W * PLUG_SRC.y / PLUG_SRC.x
	var dock := Rect2(DOCK_X, float(ROW_Y[i]) - h * 0.5, PLUG_W, h)
	var j := int(_links[i])
	if j < 0:
		return _r(dock)
	var socket := _socket_design(j)
	# The prongs disappear under the socket's frame, the nose stops at the hole's rim.
	var seated := Rect2(socket.position.x + SOCKET_W * 0.2 - PLUG_W, socket.get_center().y - h * 0.5, PLUG_W, h)
	return _r(Rect2(seated.position - Vector2(36.0 * (1.0 - seat), 0.0), dock.size))


func _socket_design(j: int) -> Rect2:
	return Rect2(SOCKET_X - SOCKET_W * 0.5, float(ROW_Y[j]) - SOCKET_W * 0.5, SOCKET_W, SOCKET_W)


func _socket_rect(j: int) -> Rect2:
	var rect := _r(_socket_design(j))
	if j == _shake_socket and _shake_left > 0.0 and not wants_less_motion():
		rect.position.x += sin(_shake_left * 40.0) * 6.0 * (_shake_left / SHAKE_SECONDS)
	return rect


## Where the cable of left terminal i leaves the conduit.
func _cable_root(i: int) -> Vector2:
	return _p(Vector2(TRUNK.end.x - 4.0, float(ROW_Y[i])))


## The trace from socket j to the relay, as a polyline.
func _trace_path(j: int) -> PackedVector2Array:
	var y := float(ROW_Y[j])
	var entry := float(ENTRY_Y[j])
	var x := float(RUN_X[j])
	var start := SOCKET_X + SOCKET_W * 0.5 - 2.0
	var end := RELAY_RECT.position.x + 24.0
	return PackedVector2Array([_p(Vector2(start, y)), _p(Vector2(x, y)), _p(Vector2(x, entry)), _p(Vector2(end, entry))])


# ---------------------------------------------------------------- drawing

func _paint_equipment(c: Control) -> void:
	Kit.bay(c, Rect2(Vector2.ZERO, c.size))
	if _k <= 0.0:
		return
	_draw_relay(c)
	_draw_traces(c)
	# The patch bay plate with its four sockets.
	Kit.housing(c, _r(BAY_PLATE), 16.0 * _k)
	for j in Rule.PAIRS:
		_draw_socket(c, j)
	# The conduit the cables come out of.
	Kit.box(c, _r(TRUNK), Kit.METAL_DARK, 12.0 * _k, Kit.BAY_LIP, 2.0)
	Kit.hazard_stripes(c, _r(Rect2(TRUNK.position.x + 6.0, TRUNK.position.y + 6.0, TRUNK.size.x - 12.0, 14.0)), 3)
	for i in Rule.PAIRS:
		var at := _p(Vector2(TRUNK.end.x - 6.0, float(ROW_Y[i])))
		c.draw_circle(at, 13.0 * _k, Kit.INK)
		c.draw_circle(at, 9.0 * _k, Kit.METAL)
	# Empty dock clips for the plugs that are in.
	for i in Rule.PAIRS:
		var dock := _r(Rect2(DOCK_X + 30.0, float(ROW_Y[i]) - 30.0, PLUG_W - 60.0, 60.0))
		Kit.box(c, dock, Color(0, 0, 0, 0.18), 10.0 * _k, Color(Kit.BAY_LIP, 0.6), 2.0)
	if locked:
		# No plugs for the wrong specialist: the bay dims and the badge (a child control) sits on the first dock.
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0, 0, 0, 0.5))
		return
	# Cables and plugs: the ones in their sockets first, the held one last (on top).
	var order: Array = []
	for i in Rule.PAIRS:
		if int(_links[i]) >= 0:
			order.push_front(i)
		elif i != _selected and i != _drag_left:
			order.append(i)
	for i in Rule.PAIRS:
		if not order.has(i):
			order.append(i)
	for i: int in order:
		_draw_cable_and_plug(c, i)
	# The socket frames go over the seated plugs' prongs.
	for j in Rule.PAIRS:
		if _links.has(j):
			_draw_socket(c, j)


func _draw_relay(c: Control) -> void:
	var rect := _r(RELAY_RECT)
	var stand := Rect2(rect.position.x + rect.size.x * 0.3, rect.end.y - 10.0 * _k, rect.size.x * 0.4, 28.0 * _k)
	Kit.box(c, stand, Kit.METAL_DARK, 6.0, Kit.BAY_LIP, 2.0)
	var t := Kit.tex("relay/relay")
	if t != null:
		c.draw_texture_rect(t, rect, false)
	var k := rect.size.x / RELAY_SRC.x
	var lens := rect.position + LENS * k
	var done := 0
	var lit := 0.0
	for i in Rule.PAIRS:
		if int(_links[i]) >= 0:
			done += 1
			lit += _trace[i]
	var good: Color = UiTheme.palette().good
	if lit > 0.0:
		var beat := 1.0 if wants_less_motion() else 0.85 + 0.15 * Kit.pulse(1.2)
		var share := lit / float(Rule.PAIRS)
		var glow := Kit.HAZARD.lerp(good.lightened(0.3), 1.0 if lit >= float(Rule.PAIRS) - 0.01 else 0.0)
		c.draw_circle(lens, LENS_R * k * (0.55 + 0.45 * share), Color(glow, 0.55 * share * beat))
		c.draw_circle(lens, LENS_R * k * 0.55 * share, Color(1, 1, 0.9, 0.85 * share))
		if lit >= float(Rule.PAIRS) - 0.01:
			for n in 8:
				var a := TAU * float(n) / 8.0
				c.draw_line(lens + Vector2.from_angle(a) * LENS_R * k * 1.15, lens + Vector2.from_angle(a) * LENS_R * k * 1.45,
					Color(good.lightened(0.4), 0.9 * beat), maxf(2.0, 5.0 * k), true)
	Kit.pips(c, Vector2(rect.get_center().x, rect.end.y + 46.0 * _k), Rule.PAIRS, done, maxf(5.0, 9.0 * _k))


func _draw_traces(c: Control) -> void:
	var width := maxf(3.0, 9.0 * _k)
	for j in Rule.PAIRS:
		var path := _trace_path(j)
		_stroke(c, path, width + 4.0, Kit.INK)
		_stroke(c, path, width, TRACE_OFF)
	for j in Rule.PAIRS:
		var i := _links.find(j)
		if i < 0 or _trace[i] <= 0.0:
			continue
		var path := _trace_path(j)
		var total := _length(path)
		var color: Color = Rule.COLORS[int(_layout.right[j])]
		var lit := _slice(path, 0.0, total * _trace[i])
		_stroke(c, lit, width + 6.0, Color(color, 0.25))
		_stroke(c, lit, width, color)
		# Sparks running towards the relay (motion and shape, not colour alone).
		var phase := 0.25 if wants_less_motion() else fposmod(float(Time.get_ticks_msec()) * 0.001 * 0.7, 1.0)
		for n in 3:
			var at := fposmod(phase + float(n) / 3.0, 1.0) * total
			if at <= total * _trace[i]:
				c.draw_circle(_slice(path, at, at)[0], width * 0.42, Color(1, 1, 0.92, 0.95))
	# The relay's input pins.
	for j in Rule.PAIRS:
		var p := _trace_path(j)
		c.draw_circle(p[p.size() - 1], width * 0.8, Kit.INK)
		c.draw_circle(p[p.size() - 1], width * 0.55, Kit.METAL if _links.find(j) < 0 else Color.WHITE)


func _draw_socket(c: Control, j: int) -> void:
	var rect := _socket_rect(j)
	var t := Kit.tex("relay/socket")
	if t != null:
		c.draw_texture_rect(t, rect, false)
	var centre := rect.get_center()
	var r := rect.size.x * HOLE_R
	var pair := int(_layout.right[j])
	var color: Color = Rule.COLORS[pair]
	var kind: int = KIT_SHAPE[int(Rule.SHAPES[pair])]
	var i := _links.find(j)
	if i >= 0 and _seat[i] >= 1.0:
		# Seated: the plug's lit face fills the hole.
		c.draw_circle(centre, r, color.darkened(0.35))
		c.draw_circle(centre, r * 0.86, color)
		Kit.shape(c, kind, centre, r * 0.5, Color.WHITE)
		return
	# Empty: the shape key, a hollow outline of the shape in the pair's colour.
	c.draw_circle(centre, r, Color(0.02, 0.025, 0.03))
	Kit.shape(c, kind, centre, r * 0.62, color, color.darkened(0.45))
	Kit.shape(c, kind, centre, r * 0.36, Color(0.03, 0.035, 0.04), Color(0.03, 0.035, 0.04))


func _draw_cable_and_plug(c: Control, i: int) -> void:
	var pair := int(_layout.left[i])
	var color: Color = Rule.COLORS[pair]
	var rect := _plug_rect(i, _seat[i])
	var held := false
	if i == _drag_left and _drag_active:
		var local := _mouse - c.get_global_rect().position
		var target := _right_under(_mouse)
		if target >= 0:
			local = _socket_rect(target).get_center() - Vector2(_socket_rect(target).size.x * 0.35, 0.0)
		rect.position = local - Vector2(rect.size.x * 0.92, rect.size.y * 0.5)
		held = true
	elif i == _selected:
		rect.position += Vector2(26.0, -6.0) * _k
		held = true
	var cord := Vector2(rect.position.x + 2.0 * _k, rect.get_center().y)
	_cable(c, _cable_root(i), cord, color)
	if held:
		Kit.box(c, Rect2(rect.position + Vector2(6, 10) * _k, rect.size), Color(0, 0, 0, 0.35), 18.0 * _k)
	var t := Kit.tex("relay/plug")
	if t != null:
		c.draw_texture_rect(t, rect, false, color.lightened(0.15))
	# The plug's shape, stamped on its body.
	var body := rect.position + Vector2(rect.size.x * 0.47, rect.size.y * 0.5)
	Kit.shape(c, KIT_SHAPE[int(Rule.SHAPES[pair])], body, rect.size.y * 0.27, Color.WHITE)


## A thick, slightly sagging cable with a dark edge.
func _cable(c: Control, a: Vector2, b: Vector2, color: Color) -> void:
	var dx := maxf(30.0 * _k, absf(b.x - a.x) * 0.45)
	var sag := 26.0 * _k
	var c1 := a + Vector2(dx, sag)
	var c2 := b + Vector2(-dx, sag)
	var pts := PackedVector2Array()
	for s in 33:
		var t := float(s) / 32.0
		var u := 1.0 - t
		pts.append(a * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + b * t * t * t)
	c.draw_polyline(pts, CABLE_EDGE, maxf(6.0, 22.0 * _k), true)
	c.draw_polyline(pts, color.darkened(0.15), maxf(4.0, 15.0 * _k), true)
	c.draw_polyline(pts, Color(1, 1, 1, 0.25), maxf(1.5, 4.0 * _k), true)


## The shared marks over the buttons: hover, the target ring (the plug to pick; while a plug is held, every free
## socket), the focus ring, a tick on each seated socket and an amber cross on a refused one.
func _paint_marks(c: Control) -> void:
	if _k <= 0.0:
		return
	var less := wants_less_motion()
	if locked:
		if badge != null:
			Kit.target_ring(c, Rect2(badge.position, badge.size).grow(8.0), 18.0 * _k, less)
		return
	for list: Array in [left_buttons, right_buttons]:
		for b: Button in list:
			if b.is_hovered() and not b.disabled and not b.has_focus():
				Kit.box(c, Rect2(b.position, b.size).grow(-2.0), Color(1, 1, 1, 0.05), 14.0 * _k, Color(1, 1, 1, 0.5), 2.0)
	if not succeeded and not pending:
		var holding := _selected >= 0 or (_drag_left >= 0 and _drag_active)
		if holding:
			for j in Rule.PAIRS:
				if not _links.has(j):
					Kit.target_ring(c, _socket_rect(j).grow(4.0), 16.0 * _k, less)
		else:
			for i in Rule.PAIRS:
				if int(_links[i]) < 0:
					Kit.target_ring(c, _plug_rect(i, 1.0).grow(2.0), 18.0 * _k, less)
					break
	for list: Array in [left_buttons, right_buttons]:
		for b: Button in list:
			if b.has_focus():
				var rect := Rect2(b.position, b.size).grow(-2.0)
				var at := left_buttons.find(b)
				if at >= 0 and at == _selected:
					rect.position += Vector2(26.0, -6.0) * _k
				Kit.focus_ring(c, rect, 16.0 * _k, 4.0)
	for j in Rule.PAIRS:
		var rect := _socket_rect(j)
		var badge := rect.position + Vector2(rect.size.x * 0.92, rect.size.y * 0.1)
		var i := _links.find(j)
		if i >= 0 and _seat[i] >= 1.0:
			Kit.tick(c, badge, maxf(9.0, 15.0 * _k))
		elif j == _shake_socket:
			Kit.cross(c, badge, maxf(9.0, 15.0 * _k))


static func _length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


## The part of a polyline between two distances along it.
static func _slice(path: PackedVector2Array, from: float, to: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var walked := 0.0
	for i in range(1, path.size()):
		var length := path[i - 1].distance_to(path[i])
		if length <= 0.0:
			continue
		var start := walked
		walked += length
		if walked < from:
			continue
		if out.is_empty():
			out.append(path[i - 1].lerp(path[i], clampf((from - start) / length, 0.0, 1.0)))
		if walked >= to:
			out.append(path[i - 1].lerp(path[i], clampf((to - start) / length, 0.0, 1.0)))
			return out
		out.append(path[i])
	if out.is_empty() and not path.is_empty():
		out.append(path[path.size() - 1])
	return out


## A thick line along a polyline with round corners.
static func _stroke(c: Control, path: PackedVector2Array, width: float, color: Color) -> void:
	for i in range(1, path.size()):
		c.draw_line(path[i - 1], path[i], color, width, true)
		c.draw_circle(path[i - 1], width * 0.5, color)
	if path.size() > 1:
		c.draw_circle(path[path.size() - 1], width * 0.5, color)
