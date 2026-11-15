extends "res://scripts/tasks/puzzles/electric_ui.gd"
## T02 Wires mini-game: the open wiring rack in the Command Room (BP03). Four cables on the left, four shuffled plugs
## on the right. Every pair has a letter, a colour word and a shape (A red triangle, B blue circle, C yellow square,
## D pink diamond), so colour is never the only cue. Connect by dragging a cable onto a plug, or by picking a cable
## and then a plug (mouse, or Tab / arrows + Enter). Cables are drawn as soft curves with a dark edge, and each cable
## carries its shape at the middle so crossings stay readable. The host rule (t02_rule.gd) checks every connection;
## a wrong one is explained and the cable comes back out, a right one locks.

const Rule := preload("res://scripts/tasks/puzzles/t02_rule.gd")

var left_buttons: Array[Button] = []
var right_buttons: Array[Button] = []
var canvas: DrawBox
var hint_label: Label

var _layout: Dictionary = {"left": [0, 1, 2, 3], "right": [0, 1, 2, 3]}
var _links: Array = [-1, -1, -1, -1]
var _selected := -1
var _drag_left := -1
var _drag_active := false
var _drag_from := Vector2.ZERO
var _mouse := Vector2.ZERO
var _attempt := Vector2i(-1, -1)


func setup(p_services: GameServices) -> void:
	task_title = "Fix the wires"
	instructions = "Plug each cable on the left into the plug with the same letter and shape on the right. Drag a cable across, or pick a cable and then its plug. Keyboard: Tab or the arrow keys to move, Enter to pick."
	super.setup(p_services)
	if ui_ready:
		return
	name = "WiresPanel"
	var board := HBoxContainer.new()
	board.name = "WiringBoard"
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_area.add_child(board)
	var left_column := VBoxContainer.new()
	left_column.name = "Cables"
	board.add_child(left_column)
	canvas = DrawBox.new()
	canvas.name = "CableCanvas"
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(200, 0)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.painter = _draw_cables
	board.add_child(canvas)
	var right_column := VBoxContainer.new()
	right_column.name = "Plugs"
	board.add_child(right_column)
	for i in Rule.PAIRS:
		var lb := make_button("Cable%d" % i, "")
		lb.custom_minimum_size = Vector2(190, 52)
		lb.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		lb.pressed.connect(_on_left_pressed.bind(i))
		lb.button_down.connect(_on_left_down.bind(i))
		left_buttons.append(lb)
		left_column.add_child(_terminal_row(lb, i, true))
		var rb := make_button("Plug%d" % i, "")
		rb.custom_minimum_size = Vector2(190, 52)
		rb.pressed.connect(_on_right_pressed.bind(i))
		right_buttons.append(rb)
		right_column.add_child(_terminal_row(rb, i, false))
	hint_label = _label("Hint", UiTheme.HEADING)
	play_area.add_child(hint_label)
	reset_requested.connect(func() -> void:
		_selected = -1
		send_move("reset", 0))
	ui_ready = true
	refresh_from_host()


func _terminal_row(button: Button, index: int, left: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = ("CableRow%d" if left else "PlugRow%d") % index
	var chip := make_symbol_chip(0, Color.WHITE)
	chip.name = "Symbol"
	if left:
		row.add_child(chip)
		row.add_child(button)
	else:
		row.add_child(button)
		row.add_child(chip)
	return row


func first_focus() -> Control:
	return cancel_button if pending or left_buttons.is_empty() else left_buttons[0]


func _pair_name(pair: int) -> String:
	return "%s %s %s" % [Rule.LETTERS[pair], Rule.NAMES[pair], Rule.SHAPE_NAMES[pair]]


func _on_host_state(seed_value: int, _puzzle: Dictionary, record: Dictionary) -> void:
	_layout = Rule.layout(seed_value)
	_links = Rule.links_of(record)
	for i in Rule.PAIRS:
		var lp := int(_layout.left[i])
		var rp := int(_layout.right[i])
		var locked := int(_links[i]) >= 0
		left_buttons[i].text = "%s %s cable%s" % [Rule.LETTERS[lp], Rule.NAMES[lp], "  - locked" if locked else ("  - picked" if _selected == i else "")]
		right_buttons[i].text = "%s %s plug%s" % [Rule.LETTERS[rp], Rule.NAMES[rp], "  - locked" if _links.has(i) else ""]
		_set_chip(left_buttons[i], lp)
		_set_chip(right_buttons[i], rp)
	var done := 0
	for j: int in _links:
		done += 1 if j >= 0 else 0
	if succeeded:
		hint_label.text = "All four cables are in. The wires work again!"
	elif _selected >= 0:
		hint_label.text = "Now pick the plug for the %s cable." % _pair_name(int(_layout.left[_selected]))
	else:
		hint_label.text = "Cables connected: %d of %d. Match the letter and the shape." % [done, Rule.PAIRS]
	canvas.queue_redraw()


func _set_chip(button: Button, pair: int) -> void:
	var chip := button.get_parent().get_node("Symbol") as DrawBox
	var shape: int = Rule.SHAPES[pair]
	var color: Color = Rule.COLORS[pair]
	chip.painter = paint_symbol_chip.bind(shape, color)
	chip.queue_redraw()


func _on_left_pressed(i: int) -> void:
	if _drag_active:
		return
	if int(_links[i]) >= 0:
		hint_label.text = "That cable is already plugged in and locked."
		return
	_selected = -1 if _selected == i else i
	refresh_from_host()


func _on_left_down(i: int) -> void:
	if int(_links[i]) >= 0 or pending or succeeded:
		return
	_drag_left = i
	_drag_active = false
	_drag_from = get_global_mouse_position()
	_mouse = _drag_from


func _on_right_pressed(j: int) -> void:
	if _selected < 0:
		hint_label.text = "Pick a cable on the left first."
		return
	var i := _selected
	_selected = -1
	_connect(i, j)


func _connect(i: int, j: int) -> void:
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
		canvas.queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not event.is_pressed():
		var from := _drag_left
		var was_active := _drag_active
		_drag_left = -1
		if was_active:
			var target := _right_under((event as InputEventMouseButton).global_position)
			if target >= 0:
				_connect(from, target)
			else:
				hint_label.text = "Drop the cable onto a plug on the right."
			# Let the left button's own release run first, then clear the flag.
			set_deferred(&"_drag_active", false)
		canvas.queue_redraw()


func _right_under(global_point: Vector2) -> int:
	for j in right_buttons.size():
		if right_buttons[j].get_global_rect().grow(6.0).has_point(global_point):
			return j
	return -1


func _explain_rejection(_move: Dictionary) -> String:
	var i := _attempt.x
	var j := _attempt.y
	if i < 0 or j < 0:
		return ""
	if int(_links[i]) >= 0:
		return "That cable is already plugged in and locked."
	if _links.has(j):
		return "That plug already has a cable in it. Try another plug."
	var want := int(_layout.left[i])
	var got := int(_layout.right[j])
	return "Not that one: the %s cable needs the %s plug, but this plug is %s. The cable comes back out - try again." % [_pair_name(want), _pair_name(want), _pair_name(got)]


# ---------------------------------------------------------------- drawing

func _end_y(button: Button) -> float:
	return button.get_global_rect().get_center().y - canvas.get_global_rect().position.y


func _draw_cables(box: Control) -> void:
	var w := box.size.x
	box.draw_rect(Rect2(Vector2.ZERO, box.size), BOARD_BG)
	box.draw_rect(Rect2(Vector2.ZERO, box.size), METAL, false, 4.0)
	# Terminal posts on both edges.
	for k in Rule.PAIRS:
		if k < left_buttons.size():
			box.draw_circle(Vector2(8, _end_y(left_buttons[k])), 7.0, METAL_DARK)
			box.draw_circle(Vector2(w - 8, _end_y(right_buttons[k])), 7.0, METAL_DARK)
	for i in Rule.PAIRS:
		if i >= left_buttons.size() or int(_links[i]) < 0:
			continue
		_cable(box, Vector2(8, _end_y(left_buttons[i])), Vector2(w - 8, _end_y(right_buttons[int(_links[i])])), int(_layout.left[i]), true)
	var hover := -1
	if _drag_left >= 0 and _drag_active:
		var local := _mouse - box.get_global_rect().position
		hover = _right_under(_mouse)
		var end := Vector2(w - 8, _end_y(right_buttons[hover])) if hover >= 0 else local
		_cable(box, Vector2(8, _end_y(left_buttons[_drag_left])), end, int(_layout.left[_drag_left]), false)
	elif _selected >= 0 and _selected < left_buttons.size():
		var start := Vector2(8, _end_y(left_buttons[_selected]))
		_cable(box, start, start + Vector2(w * 0.25, 30.0), int(_layout.left[_selected]), false)
	if hover >= 0:
		box.draw_arc(Vector2(w - 8, _end_y(right_buttons[hover])), 14.0, 0.0, TAU, 32, UiTheme.palette().focus, 3.0)


func _cable(box: Control, a: Vector2, b: Vector2, pair: int, plugged: bool) -> void:
	var color: Color = Rule.COLORS[pair]
	var dx := maxf(40.0, absf(b.x - a.x) * 0.45)
	var sag := 18.0
	var c1 := a + Vector2(dx, sag)
	var c2 := b + Vector2(-dx, sag)
	var pts := PackedVector2Array()
	for s in 33:
		var t := float(s) / 32.0
		var u := 1.0 - t
		pts.append(a * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + b * t * t * t)
	box.draw_polyline(pts, Color(0.08, 0.08, 0.1), 11.0, true)
	box.draw_polyline(pts, color, 6.0, true)
	var mid := pts[16]
	draw_symbol(box, int(Rule.SHAPES[pair]), mid, 8.0, color, Color(0.08, 0.08, 0.1))
	box.draw_circle(a, 6.0, color)
	if plugged:
		box.draw_circle(b, 6.0, color)
		box.draw_circle(b, 2.5, LAMP_GOOD)
