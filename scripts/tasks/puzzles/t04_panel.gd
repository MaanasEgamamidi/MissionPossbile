extends "res://scripts/tasks/puzzles/electric_ui.gd"
## T04 Circuits mini-game: the schematic board of the Power Room panel (BP07, red lines on a light board). Pick a
## part from the tray, put it on a cell, click it again to turn it, right-click (or Delete) to take it out. Power comes
## in on the left and must reach the lamp on the right with exactly the target voltage (t04_rule.gd: source volts +
## the voltage parts on the route). Current is drawn only along the connected part of the route.
## Keyboard: 1-9 pick a tray part, R turns the part in your hand (or the part on the selected cell), arrows / Tab
## move between cells, Enter places or turns, Delete / Backspace takes a part out. Reset puts every part back.

const Rule := preload("res://scripts/tasks/puzzles/t04_rule.gd")
const CURRENT_COLOR := Color(1.0, 0.85, 0.2)
const CELL_SIZE := 70.0

var cells: Array[Button] = []
var slot_buttons: Array[Button] = []
var reading_label: Label
var hand_label: Label
var hint_label: Label
var turn_button: Button
var remove_button: Button

var _layout: Dictionary = {}
var _board: Array = Rule.empty_board()
var _trace: Dictionary = {"connected": false, "volts": Rule.BASE_VOLTS, "cells": []}
var _hand_slot := -1
var _hand_rot := 0
var _cursor := -1
var _time := 0.0
var _in_labels: Array[Label] = []
var _out_labels: Array[Label] = []


func setup(p_services: GameServices) -> void:
	task_title = "Repair the power circuit"
	instructions = "Build a path for the power from IN on the left to the LAMP on the right. Pick a part from the tray, then click a cell to put it there. Click a part again to turn it. The voltage parts change the voltage: the lamp only works when Actual matches Target. Keys: 1-9 pick a part, R turns, arrows move, Enter places, Delete takes a part out."
	super.setup(p_services)
	if ui_ready:
		return
	name = "CircuitsPanel"
	reading_label = _label("Voltage", UiTheme.READING)
	play_area.add_child(reading_label)
	var board_row := HBoxContainer.new()
	board_row.name = "BoardRow"
	board_row.alignment = BoxContainer.ALIGNMENT_CENTER
	play_area.add_child(board_row)
	var in_column := VBoxContainer.new()
	in_column.name = "InMarkers"
	board_row.add_child(in_column)
	var grid := GridContainer.new()
	grid.name = "CircuitGrid"
	grid.columns = Rule.GRID_W
	board_row.add_child(grid)
	var out_column := VBoxContainer.new()
	out_column.name = "OutMarkers"
	board_row.add_child(out_column)
	for y in Rule.GRID_H:
		for column: VBoxContainer in [in_column, out_column]:
			var marker := _label("Row%d" % y, UiTheme.HEADING)
			marker.autowrap_mode = TextServer.AUTOWRAP_OFF
			marker.custom_minimum_size = Vector2(0, CELL_SIZE)
			marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			marker.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			column.add_child(marker)
			(_in_labels if column == in_column else _out_labels).append(marker)
	for cell in Rule.GRID_W * Rule.GRID_H:
		var b := Button.new()
		b.name = "Cell%d" % cell
		b.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
		b.pressed.connect(_on_cell_pressed.bind(cell))
		b.focus_entered.connect(func() -> void:
			_cursor = cell
			_update_hand())
		b.gui_input.connect(_on_cell_gui_input.bind(cell))
		var overlay := DrawBox.new()
		overlay.name = "Piece"
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.offset_left = 4
		overlay.offset_top = 4
		overlay.offset_right = -4
		overlay.offset_bottom = -4
		overlay.painter = _draw_cell.bind(cell)
		b.add_child(overlay)
		grid.add_child(b)
		cells.append(b)
	var tray_title := _label("TrayTitle", UiTheme.HEADING)
	tray_title.text = "Parts tray"
	play_area.add_child(tray_title)
	var tray := HFlowContainer.new()
	tray.name = "Tray"
	play_area.add_child(tray)
	var group := ButtonGroup.new()
	group.allow_unpress = true
	for slot in 6:
		var sb := Button.new()
		sb.name = "Slot%d" % slot
		sb.toggle_mode = true
		sb.button_group = group
		sb.custom_minimum_size = Vector2(150, 44)
		sb.toggled.connect(func(on: bool) -> void:
			if on:
				_hand_slot = slot
			elif _hand_slot == slot:
				_hand_slot = -1
			_update_hand())
		tray.add_child(sb)
		slot_buttons.append(sb)
	hand_label = _label("Hand", UiTheme.MUTED)
	play_area.add_child(hand_label)
	var tools := HBoxContainer.new()
	tools.name = "Tools"
	play_area.add_child(tools)
	turn_button = make_button("Turn", "Turn part (R)")
	turn_button.pressed.connect(_turn)
	tools.add_child(turn_button)
	remove_button = make_button("Remove", "Take part out (Delete)")
	remove_button.pressed.connect(_remove)
	tools.add_child(remove_button)
	hint_label = _label("Hint", UiTheme.HEADING)
	play_area.add_child(hint_label)
	reset_requested.connect(func() -> void: send_move("reset", 0))
	ui_ready = true
	refresh_from_host()


func first_focus() -> Control:
	if pending or slot_buttons.is_empty():
		return cancel_button
	return slot_buttons[0]


func _process(delta: float) -> void:
	super._process(delta)
	if not ui_ready:
		return
	_time += delta
	for cell: int in _trace.cells:
		(cells[cell].get_node("Piece") as Control).queue_redraw()


func _on_host_state(seed_value: int, _puzzle: Dictionary, record: Dictionary) -> void:
	_layout = Rule.layout(seed_value)
	_board = Rule.board_of(record, _layout)
	_trace = Rule.trace(_layout, _board)
	var target := int(_layout.target)
	if bool(_trace.connected):
		reading_label.text = "Target: %d V    Actual: %d V  %s" % [target, int(_trace.volts), "- MATCH" if int(_trace.volts) == target else "- not the target yet"]
	else:
		reading_label.text = "Target: %d V    Actual: no current yet (the path is not finished)" % target
	for y in Rule.GRID_H:
		_in_labels[y].text = "IN %d V >" % Rule.BASE_VOLTS if y == int(_layout.source_row) else ""
		_out_labels[y].text = "> LAMP" if y == int(_layout.load_row) else ""
	var slots: Array = _layout.slots
	for slot in slot_buttons.size():
		var sb := slot_buttons[slot]
		sb.visible = slot < slots.size()
		if slot < slots.size():
			sb.text = "%d: %s x%d" % [slot + 1, _slot_name(slots[slot]), Rule.remaining(_layout, _board, slot)]
	if _hand_slot >= slots.size():
		_hand_slot = -1
	for cell in cells.size():
		cells[cell].tooltip_text = _cell_words(cell)
		(cells[cell].get_node("Piece") as Control).queue_redraw()
	if succeeded:
		hint_label.text = "The lamp is on: the circuit works again!"
	elif bool(_trace.connected):
		hint_label.text = "The path is connected, but the voltage is %d V and the lamp needs %d V. Swap a voltage part." % [int(_trace.volts), target]
	else:
		hint_label.text = "Connect IN to the LAMP. Every piece's lines must touch the next piece's lines."
	_update_hand()


func _slot_name(slot: Dictionary) -> String:
	match int(slot.kind):
		Rule.STRAIGHT:
			return "Straight"
		Rule.CORNER:
			return "Corner"
	return "%+d V part" % int(slot.volts)


func _cell_words(cell: int) -> String:
	var where := "Row %d, column %d" % [cell / Rule.GRID_W + 1, cell % Rule.GRID_W + 1]
	if (_layout.blocked as Array).has(cell):
		return where + ": blocked"
	var piece := Rule.piece_at(_layout, _board, cell)
	if piece.is_empty():
		return where + ": empty"
	return where + ": %s%s" % [_slot_name({"kind": piece.kind, "volts": piece.volts}), " (bolted in)" if bool(piece.fixed) else ""]


func _update_hand() -> void:
	if hand_label == null or _layout.is_empty():
		return
	if _hand_slot < 0:
		hand_label.text = "In hand: nothing. Pick a part from the tray (keys 1-%d)." % (_layout.slots as Array).size()
	else:
		hand_label.text = "In hand: %s, turned %d degrees (R turns it). Selected cell: %s" % [_slot_name(_layout.slots[_hand_slot]), _hand_rot * 90, _cell_words(_cursor) if _cursor >= 0 else "none"]
	for slot in slot_buttons.size():
		slot_buttons[slot].set_pressed_no_signal(slot == _hand_slot)


func _on_cell_pressed(cell: int) -> void:
	_cursor = cell
	if _layout.is_empty():
		return
	if (_layout.blocked as Array).has(cell):
		hint_label.text = "That cell is blocked. Nothing fits there."
		return
	var piece := Rule.piece_at(_layout, _board, cell)
	if not piece.is_empty():
		if bool(piece.fixed):
			hint_label.text = "That part is bolted in. Build around it."
		else:
			send_move("rotate", cell)
		return
	if _hand_slot < 0:
		hint_label.text = "Pick a part from the tray first."
		return
	if Rule.remaining(_layout, _board, _hand_slot) <= 0:
		hint_label.text = "No more of that part. Take one out of the board or pick another."
		return
	send_move("place", cell * 100 + _hand_slot * 10 + _hand_rot)


func _on_cell_gui_input(event: InputEvent, cell: int) -> void:
	if event is InputEventMouseButton and event.is_pressed() and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_cursor = cell
		_remove()
		cells[cell].accept_event()


func _turn() -> void:
	if _cursor >= 0 and not _layout.is_empty():
		var piece := Rule.piece_at(_layout, _board, _cursor)
		if not piece.is_empty() and not bool(piece.fixed):
			send_move("rotate", _cursor)
			return
	_hand_rot = (_hand_rot + 1) % 4
	_update_hand()


func _remove() -> void:
	if _cursor < 0 or _layout.is_empty():
		hint_label.text = "Select a cell first."
		return
	var piece := Rule.piece_at(_layout, _board, _cursor)
	if piece.is_empty():
		hint_label.text = "That cell is already empty."
	elif bool(piece.fixed):
		hint_label.text = "That part is bolted in. It stays."
	else:
		send_move("remove", _cursor)


func _unhandled_key_input(event: InputEvent) -> void:
	if not ui_ready or not is_visible_in_tree() or not event.is_pressed() or event.is_echo():
		return
	var key := event as InputEventKey
	if key == null or key.shift_pressed or key.ctrl_pressed or key.alt_pressed:
		return
	var code := key.keycode
	if code == KEY_R:
		_turn()
	elif code == KEY_DELETE or code == KEY_BACKSPACE:
		_remove()
	elif code >= KEY_1 and code <= KEY_9 and int(code - KEY_1) < (_layout.get("slots", []) as Array).size():
		var slot := int(code - KEY_1)
		_hand_slot = -1 if _hand_slot == slot else slot
		_update_hand()
	else:
		return
	get_viewport().set_input_as_handled()


func _explain_rejection(move: Dictionary) -> String:
	match String(move.get("move", "")):
		"place":
			return "That part cannot go there. Try an empty cell and a part you still have."
		"rotate", "remove":
			return "Only parts you placed can be turned or taken out."
	return ""


# ---------------------------------------------------------------- drawing

func _draw_cell(box: Control, cell: int) -> void:
	if _layout.is_empty():
		return
	var r := Rect2(Vector2.ZERO, box.size)
	var c := box.size * 0.5
	if (_layout.blocked as Array).has(cell):
		box.draw_rect(r, METAL_DARK)
		for k in 4:
			var o := box.size.x * (0.25 * k)
			box.draw_line(Vector2(o, box.size.y), Vector2(o + box.size.x * 0.5, 0), Color(0.35, 0.36, 0.4), 3.0)
		draw_text_centered(box, "X", c, 22, Color(0.85, 0.85, 0.88))
		return
	var piece := Rule.piece_at(_layout, _board, cell)
	box.draw_rect(r, Color(0.8, 0.82, 0.84) if not piece.is_empty() and bool(piece.fixed) else BOARD_BG)
	var x := cell % Rule.GRID_W
	var y := cell / Rule.GRID_W
	if x == 0 and y == int(_layout.source_row):
		box.draw_colored_polygon(PackedVector2Array([Vector2(0, c.y - 9), Vector2(12, c.y), Vector2(0, c.y + 9)]), Color(0.2, 0.45, 0.9))
	if x == Rule.GRID_W - 1 and y == int(_layout.load_row):
		draw_lamp(box, Vector2(box.size.x - 9, c.y), 6.0, CURRENT_COLOR if succeeded else LAMP_OFF)
	if piece.is_empty():
		return
	var live := (_trace.cells as Array).has(cell)
	var line_color := CURRENT_COLOR if live else BOARD_LINE
	for port: int in Rule.ports(int(piece.kind), int(piece.rot)):
		var edge := c + Vector2(float(Rule.DX[port]), float(Rule.DY[port])) * box.size * 0.5
		box.draw_line(c, edge, Color(0.15, 0.1, 0.1) if live else BOARD_LINE.darkened(0.3), 10.0)
		box.draw_line(c, edge, line_color, 6.0)
		if live:
			# Moving dots show the current flowing along the connected route only.
			var t := fposmod(_time * 1.5, 1.0)
			box.draw_circle(c.lerp(edge, t), 3.0, Color(1, 1, 1))
	box.draw_circle(c, 5.0, line_color)
	if int(piece.kind) == Rule.VOLT:
		var tag := Rect2(c - Vector2(24, 13), Vector2(48, 26))
		box.draw_rect(tag, Color(0.12, 0.14, 0.18))
		box.draw_rect(tag, line_color, false, 2.0)
		draw_text_centered(box, "%+dV" % int(piece.volts), c, 15, Color(1, 1, 1))
	if bool(piece.fixed):
		for corner: Vector2 in [Vector2(7, 7), Vector2(box.size.x - 7, 7), Vector2(7, box.size.y - 7), Vector2(box.size.x - 7, box.size.y - 7)]:
			box.draw_circle(corner, 3.5, METAL_DARK)
