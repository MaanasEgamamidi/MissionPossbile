extends "res://scripts/tasks/puzzles/med_ui.gd"
## T10 Equipment mini-game (Med Bay, any role). Drag each machine's lead to the power-unit socket with the same colour
## AND shape; the machine's screen lights up. Then run the self-test. A wrong socket is explained and the plug pops
## back out (the host refuses it, nothing is seated).
## Keyboard: Tab / arrows to a plug, Enter picks it up, Tab to a socket, Enter plugs it in; "Run self-test" last.
## Mouse: drag a plug button onto a socket, or click plug then socket. Plugs and sockets carry colour words, a shape
## and a letter, never colour alone. Only sends moves; the host rule (t10_rule.gd) decides everything.

const Rule := preload("res://scripts/tasks/puzzles/t10_rule.gd")
## Lead colours (designer art values, matching the BP02 leads: green and blue).
const COLOURS := {"green": Color(0.47, 0.75, 0.32), "blue": Color(0.33, 0.6, 0.92)}
const SOCKET_LETTERS := ["A", "B", "C", "D"]
const SCREEN_OFF := Color(0.06, 0.08, 0.1)
const SCREEN_ON := Color(0.16, 0.42, 0.36)
const SCREEN_OK := Color(0.25, 0.62, 0.36)

var lead_buttons: Array[Button] = []
var socket_buttons: Array[Button] = []
var screen_boxes: Array[Control] = []
var screen_labels: Array[Label] = []
var socket_boxes: Array[Control] = []
var test_button: Button
var held := -1


func rule_script() -> Script:
	return Rule


func setup(p_services: GameServices) -> void:
	instructions = "Two Med Bay machines came unplugged. Drag each plug to the socket with the same colour AND the same shape (or pick a plug, then a socket). Watch the screens light up, then run the self-test."
	super.setup(p_services)
	name = "T10EquipmentPanel"


func build_game() -> void:
	var devices := HBoxContainer.new()
	devices.name = "Devices"
	play_area.add_child(devices)
	for lead in Rule.LEADS:
		var card := VBoxContainer.new()
		card.name = "Device%d" % (lead + 1)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		devices.add_child(card)
		var screen := make_box("Screen", Vector2(160, 84), _paint_screen.bind(lead))
		card.add_child(screen)
		screen_boxes.append(screen)
		var label := _label("ScreenText")
		card.add_child(label)
		screen_labels.append(label)
	var leads_heading := _label("LeadsHeading", UiTheme.HEADING)
	leads_heading.text = "Plugs"
	play_area.add_child(leads_heading)
	var leads := HBoxContainer.new()
	leads.name = "Leads"
	play_area.add_child(leads)
	for lead in Rule.LEADS:
		var column := VBoxContainer.new()
		column.name = "Lead%d" % (lead + 1)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		leads.add_child(column)
		column.add_child(make_box("Plug", Vector2(80, 56), _paint_plug.bind(lead), func(_b: Control, _p: Vector2) -> void: pick_lead(lead)))
		var button := make_button("Pick", "")
		button.pressed.connect(pick_lead.bind(lead))
		button.set_drag_forwarding(_drag_lead.bind(lead), Callable(), Callable())
		column.add_child(button)
		lead_buttons.append(button)
	var sockets_heading := _label("SocketsHeading", UiTheme.HEADING)
	sockets_heading.text = "Sockets on the power unit"
	play_area.add_child(sockets_heading)
	var sockets := HBoxContainer.new()
	sockets.name = "Sockets"
	play_area.add_child(sockets)
	for socket in Rule.SOCKETS:
		var column := VBoxContainer.new()
		column.name = "Socket%s" % SOCKET_LETTERS[socket]
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sockets.add_child(column)
		var face := make_box("Face", Vector2(70, 64), _paint_socket.bind(socket), func(_b: Control, _p: Vector2) -> void: pick_socket(socket))
		face.set_drag_forwarding(Callable(), _can_drop.bind(socket), _drop.bind(socket))
		column.add_child(face)
		socket_boxes.append(face)
		var button := make_button("Plug", "")
		button.pressed.connect(pick_socket.bind(socket))
		button.set_drag_forwarding(Callable(), _can_drop.bind(socket), _drop.bind(socket))
		column.add_child(button)
		socket_buttons.append(button)
	test_button = make_button("SelfTest", "Run self-test", true)
	test_button.pressed.connect(run_test)
	play_area.add_child(test_button)


## Player picked up plug `lead` (keyboard / click).
func pick_lead(lead: int) -> void:
	if pending or succeeded or puzzle.is_empty():
		return
	if int(puzzle.plugged[lead]) != -1:
		hint("The %s is already plugged in." % _device(lead))
		return
	held = -1 if held == lead else lead
	redraw()
	if held == -1:
		hint("Plug put down.")
	else:
		hint("Holding the %s plug. Now pick the socket with the same colour AND shape." % _plug_words(lead))


## Player picked socket `socket` (keyboard / click) while holding a plug.
func pick_socket(socket: int) -> void:
	if pending or succeeded or puzzle.is_empty():
		return
	if held == -1:
		hint("Pick up a plug first, then choose its socket.")
		return
	plug(held, socket)


## Sends one plug move (also the drop target of a drag).
func plug(lead: int, socket: int) -> void:
	held = -1
	send("plug", lead * 10 + socket)


func run_test() -> void:
	if pending or succeeded or puzzle.is_empty():
		return
	send("test", 0)


func _drag_lead(_at: Vector2, lead: int) -> Variant:
	if pending or succeeded or puzzle.is_empty() or int(puzzle.plugged[lead]) != -1:
		return null
	var preview := Label.new()
	preview.text = "%s plug" % _plug_words(lead)
	lead_buttons[lead].set_drag_preview(preview)
	return {"t10_lead": lead}


func _can_drop(_at: Vector2, data: Variant, _socket: int) -> bool:
	return data is Dictionary and (data as Dictionary).has("t10_lead") and not pending and not succeeded


func _drop(_at: Vector2, data: Variant, socket: int) -> void:
	if _can_drop(_at, data, socket):
		plug(int((data as Dictionary).t10_lead), socket)


func redraw() -> void:
	if puzzle.is_empty():
		return
	var plugged: Array = puzzle.plugged
	for lead in Rule.LEADS:
		var socket := int(plugged[lead])
		var text := "%s plug (%s)" % [_plug_words(lead), _device(lead)]
		if socket != -1:
			text += ": in socket %s" % SOCKET_LETTERS[socket]
		elif held == lead:
			text += ": holding it"
		lead_buttons[lead].text = text
		var state := "screen off, not plugged in"
		if bool(puzzle.tested):
			state = "self-test OK"
		elif socket != -1:
			state = "screen on, power OK"
		screen_labels[lead].text = "%s: %s" % [_device(lead), state]
		screen_boxes[lead].queue_redraw()
	for socket in Rule.SOCKETS:
		var text := "Socket %s: %s" % [SOCKET_LETTERS[socket], _socket_words(socket)]
		var holder := plugged.find(socket)
		if holder != -1:
			text += " (in use)"
		socket_buttons[socket].text = text
		socket_boxes[socket].queue_redraw()
	test_button.text = "Self-test passed" if bool(puzzle.tested) else "Run self-test"


func explain(move: Dictionary) -> String:
	var payload := int(move.get("value", 0))
	match String(move.get("move", "")):
		"plug":
			var lead := payload / 10
			var socket := payload % 10
			if lead >= Rule.LEADS or socket >= Rule.SOCKETS:
				return "Pick a plug, then a socket."
			if (puzzle.plugged as Array).has(socket):
				return "Socket %s already has a plug in it." % SOCKET_LETTERS[socket]
			if int(puzzle.plugged[lead]) != -1:
				return "The %s is already plugged in." % _device(lead)
			var want: Array = Rule.KINDS[Rule.lead_kind(lead)]
			var have: Array = Rule.KINDS[int(puzzle.sockets[socket])]
			var wrong := PackedStringArray()
			if want[0] != have[0]:
				wrong.append("colour")
			if want[1] != have[1]:
				wrong.append("shape")
			return "The %s plug doesn't fit socket %s (%s): wrong %s. It pops back out. Look for %s." % [_plug_words(lead), SOCKET_LETTERS[socket], _socket_words(socket), " and ".join(wrong), " ".join(want)]
		"test":
			return "Plug in both machines first, then run the self-test."
		"reset":
			return "Nothing is plugged in yet."
	return "That doesn't work here. Try something else."


func praise(move: Dictionary) -> String:
	match String(move.get("move", "")):
		"plug":
			var lead := int(move.get("value", 0)) / 10
			if not (puzzle.plugged as Array).has(-1):
				return "Click! The %s screen lights up. Both machines have power: run the self-test." % _device(lead)
			return "Click! The %s screen lights up." % _device(lead)
		"reset":
			return "Both plugs are out again."
	return "Done."


func solved_text() -> String:
	return "Fixed! The self-test passed: both screens say OK and the Med Bay machines work again."


func _device(lead: int) -> String:
	return String(Rule.LEAD_INFO[lead][0])


func _plug_words(lead: int) -> String:
	var kind: Array = Rule.KINDS[Rule.lead_kind(lead)]
	return "%s %s" % [String(kind[0]).to_upper(), String(kind[1]).to_upper()]


func _socket_words(socket: int) -> String:
	var kind: Array = Rule.KINDS[int(puzzle.sockets[socket])]
	return "%s %s" % [kind[0], kind[1]]


func _draw_kind(ci: CanvasItem, kind: int, center: Vector2, r: float, hollow := false) -> void:
	var info: Array = Rule.KINDS[kind]
	var fill: Color = COLOURS[String(info[0])]
	var shape := Shape.CIRCLE if String(info[1]) == "round" else Shape.SQUARE
	draw_shape(ci, shape, center, r, fill)
	if hollow:
		draw_shape(ci, shape, center, r * 0.55, Color(0.04, 0.05, 0.06), Color(0.04, 0.05, 0.06))
	draw_text_centered(ci, String(info[0]).left(1).to_upper(), center + Vector2(0, -2) if not hollow else center + Vector2(0, r + 12.0), 15, Color(0.02, 0.02, 0.03) if not hollow else UiTheme.palette().text)


func _paint_plug(box: Control, lead: int) -> void:
	if puzzle.is_empty():
		return
	var pal := UiTheme.palette()
	var c := box.size * 0.5
	var seated := int(puzzle.plugged[lead]) != -1
	box.draw_line(Vector2(0, c.y), c, Color(0.12, 0.12, 0.14), 6.0)
	_draw_kind(box, Rule.lead_kind(lead), c, 18.0)
	if held == lead:
		box.draw_rect(Rect2(c - Vector2(26, 26), Vector2(52, 52)), pal.focus, false, 3.0)
	if seated:
		draw_text_centered(box, "in", c + Vector2(38, 0), 15, pal.good)


func _paint_socket(box: Control, socket: int) -> void:
	if puzzle.is_empty():
		return
	var c := box.size * 0.5 - Vector2(0, 6)
	box.draw_rect(Rect2(c - Vector2(30, 26), Vector2(60, 52)), Color(0.32, 0.34, 0.38))
	_draw_kind(box, int(puzzle.sockets[socket]), c, 17.0, true)
	draw_text_centered(box, SOCKET_LETTERS[socket], c + Vector2(-22, -16), 13, UiTheme.palette().text)
	var holder := (puzzle.plugged as Array).find(socket)
	if holder != -1:
		_draw_kind(box, Rule.lead_kind(holder), c, 11.0)


func _paint_screen(box: Control, lead: int) -> void:
	if puzzle.is_empty():
		return
	var pal := UiTheme.palette()
	var on := int(puzzle.plugged[lead]) != -1
	var ok := bool(puzzle.tested)
	var r := Rect2(Vector2(8, 6), box.size - Vector2(16, 12))
	box.draw_rect(r, Color(0.78, 0.8, 0.82))
	var inner := r.grow(-8.0)
	box.draw_rect(inner, SCREEN_OK if ok else (SCREEN_ON if on else SCREEN_OFF))
	if not on:
		draw_text_centered(box, "OFF", inner.get_center(), 18, pal.muted)
		return
	if lead == 0:
		# Heal station: a calm pulse line.
		var pts := PackedVector2Array()
		var y := inner.get_center().y
		for k in 9:
			var x := inner.position.x + inner.size.x * float(k) / 8.0
			pts.append(Vector2(x, y - (14.0 if k == 4 else (-8.0 if k == 5 else 0.0))))
		box.draw_polyline(pts, Color(0.85, 1.0, 0.9), 2.0)
	else:
		# CT scanner: a scan ring.
		box.draw_arc(inner.get_center(), minf(inner.size.x, inner.size.y) * 0.32, 0.0, TAU, 32, Color(0.85, 0.95, 1.0), 3.0)
	draw_text_centered(box, "OK" if ok else "ON", inner.position + Vector2(22, 14), 15, Color(1, 1, 1))
