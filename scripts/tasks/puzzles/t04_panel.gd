extends "res://scripts/tasks/puzzles/electric_ui.gd"
## T04 "Light the Power Bench" mini-game (Power Room service board, BP07; electrical specialist only). UI overhaul
## 2026-11-15: the equipment is the interface, in the spirit of Among Us "Divert Power" / "Fix Weather Node". One
## service board in a bay: the power jack plugs into the left edge of its row, a real lamp into the right edge of its
## row, and a 5 x 4 grid of cell plates lies between (some bolted-in parts, some blocked plates with hazard stripes).
## Underneath, the parts tray: straights, corners, boosters (+ volts, coil) and a reducer (- volts, fins), with pips for
## how many are left, plus a turn and a take-out pictogram button. Current runs from the jack along the joined parts
## and stops at the first gap (bright traces with moving sparks; parts beyond stay dull copper); the gap carries the
## shared target ring. A small meter beside the lamp shows the volts the lamp needs, the volts reaching the end of the
## lit path, and whether a booster (up arrow) or a reducer (down arrow) is still needed; the lamp lights when the path
## is joined at the right voltage.
## The host rule (t04_rule.gd) decides every move and the completion; this panel only sends place / rotate / remove /
## reset moves and draws the host's puzzle_state.
## Controls: click a tray part, then a cell to put it there; click a placed part to turn it; right-click (or Delete)
## takes it out. Keys: 1-5 pick a tray part, R turns the part in your hand (or the part on the selected cell), arrow
## keys / Tab move between cells, Enter places or turns, Delete / Backspace takes a part out.
## Public members read by tests and tools/godot/capture_puzzles.gd: cells, slot_buttons, _hand_slot, _hand_rot, meter().

const Rule := preload("res://scripts/tasks/puzzles/t04_rule.gd")
const MAX_SLOTS := 5

## The design space the bench is laid out in (scaled uniformly to fit the board).
const DESIGN := Vector2(1000, 460)
const CELL := 76.0
const GRID_AT := Vector2(262, 30)
## Power jack sprite (512 x 412): its plug tip at the right edge, y 207. Lamp sprites (512 x 458): inlet tip at x 0, y 230.
const JACK_SRC := Vector2(512, 412)
const JACK_TIP_Y := 207.0
const JACK_W := 150.0
const LAMP_SRC := Vector2(512, 458)
const LAMP_TIP_Y := 230.0
const LAMP_W := 132.0
const METER_W := 104.0
const METER_H := 214.0
const TRAY := Rect2(150, 362, 700, 92)
const SLOT_W := 88.0
const SLOT_GAP := 96.0
const TOOL_W := 76.0
const COPPER := Color(0.62, 0.4, 0.24)
const LIVE := Color(1.0, 0.86, 0.32)
## Seconds for the current to run one cell.
const FLOW_SECONDS := 0.12

var cells: Array[Button] = []
var slot_buttons: Array[Button] = []
var turn_button: Button
var remove_button: Button
## The bench (one drawn control) and the marks drawn over the buttons.
var canvas: DrawBox
var marks: DrawBox

var _layout: Dictionary = {}
var _board: Array = Rule.empty_board()
var _trace: Dictionary = {"connected": false, "volts": Rule.BASE_VOLTS, "cells": []}
var _hand_slot := -1
var _hand_rot := 0
var _cursor := -1
var _k := 1.0
var _origin := Vector2.ZERO
var _flow := 0.0
var _shown_lit := 0
var _gap := -1
var _last_sent := ""


func setup(p_services: GameServices) -> void:
	task_title = "Light the Power Bench"
	instructions = ("Build a path from the power jack to the lamp. Pick a part from the tray and put it on the board; "
		+ "click a part to turn it. Boosters raise the volts and reducers lower them: the meter shows what the lamp needs.")
	super.setup(p_services)
	if ui_ready:
		return
	name = "CircuitsPanel"
	canvas = DrawBox.new()
	canvas.name = "ServiceBoard"
	canvas.custom_minimum_size = Vector2(900, 420)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.painter = _paint_bench
	Kit.smooth(canvas)
	play_area.add_child(canvas)
	for cell in Rule.GRID_W * Rule.GRID_H:
		var b := _hit_button("Cell%d" % cell)
		b.pressed.connect(_on_cell_pressed.bind(cell))
		b.focus_entered.connect(func() -> void:
			_cursor = cell
			_repaint())
		b.gui_input.connect(_on_cell_gui_input.bind(cell))
		var x := cell % Rule.GRID_W
		var y := cell / Rule.GRID_W
		if x > 0:
			b.focus_neighbor_left = NodePath("../Cell%d" % (cell - 1))
		if x < Rule.GRID_W - 1:
			b.focus_neighbor_right = NodePath("../Cell%d" % (cell + 1))
		if y > 0:
			b.focus_neighbor_top = NodePath("../Cell%d" % (cell - Rule.GRID_W))
		cells.append(b)
	for slot in MAX_SLOTS:
		var sb := _hit_button("Slot%d" % slot)
		sb.pressed.connect(_pick_slot.bind(slot))
		slot_buttons.append(sb)
	turn_button = _hit_button("Turn")
	turn_button.tooltip_text = "Turn the part (R)"
	turn_button.pressed.connect(_turn)
	remove_button = _hit_button("Remove")
	remove_button.tooltip_text = "Take the part out (Delete)"
	remove_button.pressed.connect(_remove)
	marks = DrawBox.new()
	marks.name = "Marks"
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marks.painter = _paint_marks
	canvas.add_child(marks)
	canvas.resized.connect(_place)
	reset_requested.connect(func() -> void:
		_last_sent = "reset"
		send_move("reset", 0))
	ui_ready = true
	refresh_from_host()


func _hit_button(node_name: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for sig: Signal in [b.focus_entered, b.focus_exited, b.mouse_entered, b.mouse_exited]:
		sig.connect(_repaint)
	canvas.add_child(b)
	return b


func first_focus() -> Control:
	if pending or slot_buttons.is_empty():
		return cancel_button
	return slot_buttons[0]


## The meter's reading: {target (volts the lamp needs), volts (at the end of the lit path), connected}.
func meter() -> Dictionary:
	return {"target": int(_layout.get("target", 0)), "volts": int(_trace.volts), "connected": bool(_trace.connected)}


func _on_host_state(seed_value: int, _puzzle: Dictionary, record: Dictionary) -> void:
	_layout = Rule.layout(seed_value)
	_board = Rule.board_of(record, _layout)
	var before := (_trace.cells as Array).size()
	_trace = Rule.trace(_layout, _board)
	var lit := (_trace.cells as Array).size()
	if wants_less_motion():
		_flow = float(lit)
	else:
		_flow = minf(_flow, float(lit))
	_gap = _find_gap()
	var slots: Array = _layout.slots
	if _hand_slot >= slots.size():
		_hand_slot = -1
	for slot in slot_buttons.size():
		slot_buttons[slot].visible = slot < slots.size()
		if slot < slots.size():
			slot_buttons[slot].tooltip_text = "%s (%d left, key %d)" % [_slot_name(slots[slot]), Rule.remaining(_layout, _board, slot), slot + 1]
	for cell in cells.size():
		cells[cell].tooltip_text = _cell_words(cell)
	# Feedback for the move the host just accepted.
	var sent := _last_sent
	_last_sent = ""
	if succeeded:
		_say("The lamp is on!", &"good")
	elif sent == "reset":
		_say("All parts back in the tray.", &"")
	elif sent == "remove":
		_say("Part back in the tray.", &"")
	elif bool(_trace.connected):
		var need := int(_layout.target) - int(_trace.volts)
		_say("Too low! It needs a booster." if need > 0 else "Too high! It needs a reducer.", &"warn")
	elif lit > before and not sent.is_empty():
		_say("Power is flowing!", &"good")
	_shown_lit = lit
	_update_cue()
	_place()
	_repaint()


func _on_solved() -> void:
	_say("The lamp is on!", &"good")


func _say(text: String, kind: StringName) -> void:
	status_label.text = text
	status_label.theme_type_variation = UiTheme.GOOD if kind == &"good" else (UiTheme.WARN if kind == &"warn" else &"")
	flash(text, kind)


func _update_cue() -> void:
	if _layout.is_empty():
		return
	if _hand_slot < 0:
		set_cue("Pick a part [1]-[%d]" % (_layout.slots as Array).size())
	else:
		set_cue("Place it [Enter]  Turn it [R]")


func _slot_name(slot: Dictionary) -> String:
	match int(slot.kind):
		Rule.STRAIGHT:
			return "Straight"
		Rule.CORNER:
			return "Corner"
	return ("Booster %+d V" if int(slot.volts) > 0 else "Reducer %+d V") % int(slot.volts)


func _cell_words(cell: int) -> String:
	var where := "Row %d, column %d" % [cell / Rule.GRID_W + 1, cell % Rule.GRID_W + 1]
	if (_layout.blocked as Array).has(cell):
		return where + ": blocked"
	var piece := Rule.piece_at(_layout, _board, cell)
	if piece.is_empty():
		return where + ": empty"
	return where + ": %s%s" % [_slot_name({"kind": piece.kind, "volts": piece.volts}), " (bolted in)" if bool(piece.fixed) else ""]


func _pick_slot(slot: int) -> void:
	if _layout.is_empty() or slot >= (_layout.slots as Array).size():
		return
	if _hand_slot != slot and Rule.remaining(_layout, _board, slot) <= 0:
		_say("None of those left.", &"")
		return
	_hand_slot = -1 if _hand_slot == slot else slot
	_update_cue()
	_repaint()


func _on_cell_pressed(cell: int) -> void:
	_cursor = cell
	if _layout.is_empty():
		return
	if (_layout.blocked as Array).has(cell):
		_say("That spot is blocked.", &"")
		return
	var piece := Rule.piece_at(_layout, _board, cell)
	if not piece.is_empty():
		if bool(piece.fixed):
			_say("That part is bolted in.", &"")
		else:
			_last_sent = "rotate"
			send_move("rotate", cell)
		return
	if _hand_slot < 0:
		_say("Pick a part from the tray.", &"")
		return
	if Rule.remaining(_layout, _board, _hand_slot) <= 0:
		_say("None of those left.", &"")
		return
	_last_sent = "place"
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
			_last_sent = "rotate"
			send_move("rotate", _cursor)
			return
	_hand_rot = (_hand_rot + 1) % 4
	_repaint()


func _remove() -> void:
	if _cursor < 0 or _layout.is_empty():
		_say("Pick a part on the board.", &"")
		return
	var piece := Rule.piece_at(_layout, _board, _cursor)
	if piece.is_empty():
		_say("That spot is empty.", &"")
	elif bool(piece.fixed):
		_say("That part is bolted in.", &"")
	else:
		_last_sent = "remove"
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
		_update_cue()
		_repaint()
	else:
		return
	get_viewport().set_input_as_handled()


func _explain_rejection(move: Dictionary) -> String:
	_last_sent = ""
	match String(move.get("move", "")):
		"place":
			return "That part can't go there."
		"rotate", "remove":
			return "That part is bolted in."
	return ""


func _process(delta: float) -> void:
	super._process(delta)
	if canvas == null or not canvas.is_visible_in_tree():
		return
	var lit := float((_trace.cells as Array).size())
	_flow = lit if wants_less_motion() else minf(lit, _flow + delta / FLOW_SECONDS)
	_repaint()


func _repaint() -> void:
	if canvas == null or marks == null:
		return
	canvas.queue_redraw()
	marks.queue_redraw()


## The cell where the current stops: the first spot on its way with no part, or a part that does not join (-1 once
## the path reaches the lamp). A hint drawn from the host's board, never a decision.
func _find_gap() -> int:
	if _layout.is_empty() or bool(_trace.connected):
		return -1
	var x := 0
	var y := int(_layout.source_row)
	var enter := 3
	for _guard in Rule.GRID_W * Rule.GRID_H + 1:
		var cell := y * Rule.GRID_W + x
		var piece := Rule.piece_at(_layout, _board, cell)
		if piece.is_empty():
			return cell
		var p := Rule.ports(int(piece.kind), int(piece.rot))
		if not p.has(enter):
			return cell
		var exit_dir: int = p[0] if int(p[1]) == enter else p[1]
		var nx := x + int(Rule.DX[exit_dir])
		var ny := y + int(Rule.DY[exit_dir])
		if nx < 0 or ny < 0 or nx >= Rule.GRID_W or ny >= Rule.GRID_H:
			return cell
		x = nx
		y = ny
		enter = (exit_dir + 2) % 4
	return -1


# ---------------------------------------------------------------- layout

func _p(v: Vector2) -> Vector2:
	return _origin + v * _k


func _r(rect: Rect2) -> Rect2:
	return Rect2(_p(rect.position), rect.size * _k)


func _cell_rect(cell: int) -> Rect2:
	return _r(Rect2(GRID_AT + Vector2(cell % Rule.GRID_W, cell / Rule.GRID_W) * CELL, Vector2(CELL, CELL)))


func _row_y(row: int) -> float:
	return GRID_AT.y + (float(row) + 0.5) * CELL


func _slot_rect(slot: int) -> Rect2:
	return _r(Rect2(TRAY.position.x + 14.0 + float(slot) * SLOT_GAP, TRAY.position.y + 8.0, SLOT_W, TRAY.size.y - 16.0))


func _tool_rect(index: int) -> Rect2:
	return _r(Rect2(TRAY.end.x - 14.0 - TOOL_W * float(2 - index) - 8.0 * float(1 - index), TRAY.position.y + 8.0, TOOL_W, TRAY.size.y - 16.0))


func _lamp_rect() -> Rect2:
	var h := LAMP_W * LAMP_SRC.y / LAMP_SRC.x
	var y := _row_y(int(_layout.get("load_row", 0))) - LAMP_TIP_Y * LAMP_W / LAMP_SRC.x
	return _r(Rect2(GRID_AT.x + CELL * Rule.GRID_W - 4.0, y, LAMP_W, h))


func _meter_rect() -> Rect2:
	var lamp_y := _row_y(int(_layout.get("load_row", 0)))
	var y := clampf(lamp_y - METER_H * 0.5, 14.0, TRAY.position.y - 10.0 - METER_H)
	return _r(Rect2(GRID_AT.x + CELL * Rule.GRID_W + LAMP_W + 8.0, y, METER_W, METER_H))


func _place() -> void:
	if canvas == null or canvas.size.x <= 0.0 or canvas.size.y <= 0.0:
		return
	_k = minf(canvas.size.x / DESIGN.x, canvas.size.y / DESIGN.y)
	_origin = ((canvas.size - DESIGN * _k) * 0.5).round()
	for cell in cells.size():
		var rect := _cell_rect(cell)
		cells[cell].position = rect.position
		cells[cell].size = rect.size
	for slot in slot_buttons.size():
		var rect := _slot_rect(slot)
		slot_buttons[slot].position = rect.position
		slot_buttons[slot].size = rect.size
	for i in 2:
		var b: Button = turn_button if i == 0 else remove_button
		var rect := _tool_rect(i)
		b.position = rect.position
		b.size = rect.size


# ---------------------------------------------------------------- drawing

func _paint_bench(c: Control) -> void:
	Kit.bay(c, Rect2(Vector2.ZERO, c.size))
	if _k <= 0.0 or _layout.is_empty():
		return
	# The service board under the cells.
	var board := _r(Rect2(GRID_AT, Vector2(Rule.GRID_W, Rule.GRID_H) * CELL)).grow(10.0 * _k)
	Kit.housing(c, board, 14.0 * _k)
	for cell in cells.size():
		_draw_cell(c, cell)
	_draw_jack(c)
	_draw_lamp(c)
	_draw_meter(c)
	_draw_tray(c)


func _draw_jack(c: Control) -> void:
	var w := JACK_W * _k
	var h := w * JACK_SRC.y / JACK_SRC.x
	var tip := _p(Vector2(GRID_AT.x + 4.0, _row_y(int(_layout.source_row))))
	var rect := Rect2(tip.x - w, tip.y - JACK_TIP_Y * w / JACK_SRC.x, w, h)
	var t := Kit.tex("power_bench/power_jack")
	if t != null:
		c.draw_texture_rect(t, rect, false)
	# The jack is always live: a soft glow on its plug tip.
	c.draw_circle(tip, 9.0 * _k, Color(LIVE, 0.35 + 0.15 * (0.0 if wants_less_motion() else Kit.pulse(1.5))))


func _draw_lamp(c: Control) -> void:
	var rect := _lamp_rect()
	if succeeded:
		var glow := rect.get_center() + Vector2(rect.size.x * 0.12, 0)
		for n in 4:
			c.draw_circle(glow, rect.size.y * (0.72 - 0.12 * float(n)), Color(LIVE, 0.08 + 0.05 * float(n)))
	var t := Kit.tex("power_bench/lamp_lit" if succeeded else "power_bench/lamp_off")
	if t != null:
		c.draw_texture_rect(t, rect, false)


## The meter beside the lamp: the volts the lamp needs (number + notch), the volts reaching the end of the lit path
## (the bar), and what is still needed: a booster with an up arrow, a reducer with a down arrow, or a tick.
func _draw_meter(c: Control) -> void:
	var rect := _meter_rect()
	Kit.box(c, rect, Kit.HOUSING_DARK, 12.0 * _k)
	Kit.box(c, Rect2(rect.position, rect.size - Vector2(0, 4)), Kit.HOUSING, 12.0 * _k)
	var target := int(_layout.target)
	var volts := int(_trace.volts)
	var top := Rect2(rect.position + Vector2(8, 8) * _k, Vector2(rect.size.x - 16.0 * _k, 34.0 * _k))
	Kit.box(c, top, Kit.INK, 6.0 * _k)
	# A small bulb, then the volts the lamp needs.
	var bulb := top.position + Vector2(16.0, top.size.y * 0.5 / _k) * _k
	c.draw_circle(bulb, 8.0 * _k, LIVE if succeeded else Color(LIVE, 0.55))
	c.draw_rect(Rect2(bulb + Vector2(-4, 6) * _k, Vector2(8, 6) * _k), Kit.METAL)
	Kit.text(c, Rect2(top.position + Vector2(24.0 * _k, 0), top.size - Vector2(24.0 * _k, 0)), "%d V" % target, LIVE, 0.9 * _k / 0.95)
	# The bar: 0 at the bottom, the notch at the target.
	var top_v := float(maxi(target + 3, volts + 1))
	var bar := Rect2(rect.position.x + rect.size.x * 0.5 - 13.0 * _k, top.end.y + 10.0 * _k, 26.0 * _k, rect.size.y - 34.0 * _k - top.size.y - 56.0 * _k)
	Kit.box(c, bar, Kit.INK, 6.0 * _k)
	var lit := bool(_trace.connected) or not (_trace.cells as Array).is_empty()
	var fill := clampf(float(volts) / top_v, 0.0, 1.0)
	var level_color: Color = UiTheme.palette().good if volts == target else LIVE
	if lit:
		Kit.box(c, Rect2(bar.position.x + 3.0, bar.end.y - (bar.size.y - 6.0) * fill - 3.0, bar.size.x - 6.0, (bar.size.y - 6.0) * fill), level_color, 4.0 * _k)
	var notch_y := bar.end.y - 3.0 - (bar.size.y - 6.0) * float(target) / top_v
	c.draw_line(Vector2(bar.position.x - 6.0 * _k, notch_y), Vector2(bar.end.x + 6.0 * _k, notch_y), Color.WHITE, maxf(2.0, 3.0 * _k))
	c.draw_colored_polygon(PackedVector2Array([Vector2(bar.end.x + 4.0 * _k, notch_y), Vector2(bar.end.x + 14.0 * _k, notch_y - 7.0 * _k),
		Vector2(bar.end.x + 14.0 * _k, notch_y + 7.0 * _k)]), Color.WHITE)
	# What is still needed.
	var at := Vector2(rect.get_center().x, rect.end.y - 30.0 * _k)
	var r := 20.0 * _k
	if volts == target and bool(_trace.connected):
		Kit.tick(c, at, r)
	elif volts < target:
		Kit.draw_fit(c, Kit.tex("power_bench/booster"), Rect2(at - Vector2(r + 14.0 * _k, r), Vector2(r, r) * 2.0))
		Kit.arrow(c, at + Vector2(r + 2.0 * _k, r * 0.8), at + Vector2(r + 2.0 * _k, -r * 0.9), Kit.HAZARD, maxf(3.0, 5.0 * _k))
	else:
		Kit.draw_fit(c, Kit.tex("power_bench/reducer"), Rect2(at - Vector2(r + 14.0 * _k, r), Vector2(r, r) * 2.0))
		Kit.arrow(c, at + Vector2(r + 2.0 * _k, -r * 0.9), at + Vector2(r + 2.0 * _k, r * 0.8), Kit.HAZARD, maxf(3.0, 5.0 * _k))


func _draw_cell(c: Control, cell: int) -> void:
	var rect := _cell_rect(cell)
	var plate := rect.grow(-2.0 * _k)
	if (_layout.blocked as Array).has(cell):
		Kit.box(c, plate, Kit.METAL_DARK, 8.0 * _k, Kit.INK, 2.0)
		Kit.hazard_stripes(c, plate.grow(-12.0 * _k), 3)
		Kit.box(c, plate.grow(-12.0 * _k), Color(0, 0, 0, 0.35), 4.0)
		return
	Kit.draw_fill(c, Kit.tex("power_bench/cell_plate"), plate)
	var piece := Rule.piece_at(_layout, _board, cell)
	if piece.is_empty():
		return
	var order := (_trace.cells as Array).find(cell)
	var live := clampf(_flow - float(order), 0.0, 1.0) if order >= 0 else 0.0
	_draw_piece(c, rect, int(piece.kind), int(piece.rot), int(piece.volts), live, 1.0)
	if bool(piece.fixed):
		for corner: Vector2 in [Vector2(0.14, 0.14), Vector2(0.86, 0.14), Vector2(0.14, 0.86), Vector2(0.86, 0.86)]:
			Kit.screw(c, rect.position + rect.size * corner, 5.0 * _k)


## One part drawn in `rect`: copper traces from the middle to its ports (bright, with sparks, once `live` > 0),
## and a booster / reducer body with its volts for a voltage part.
func _draw_piece(c: Control, rect: Rect2, kind: int, rot: int, volts: int, live: float, alpha: float) -> void:
	var centre := rect.get_center()
	var half := rect.size.x * 0.5
	var w := maxf(4.0, rect.size.x * 0.16)
	for port: int in Rule.ports(kind, rot):
		var edge := centre + Vector2(float(Rule.DX[port]), float(Rule.DY[port])) * half
		c.draw_line(centre, edge, Color(Kit.INK, alpha), w + 4.0, true)
		c.draw_line(centre, edge, Color(COPPER, alpha), w, true)
	c.draw_circle(centre, w * 0.5 + 2.0, Color(Kit.INK, alpha))
	c.draw_circle(centre, w * 0.5, Color(COPPER, alpha))
	if live > 0.0:
		for port: int in Rule.ports(kind, rot):
			var edge := centre + Vector2(float(Rule.DX[port]), float(Rule.DY[port])) * half
			c.draw_line(centre, centre.lerp(edge, minf(1.0, live * 1.4)), Color(LIVE, 0.35), w + 8.0, true)
			c.draw_line(centre, centre.lerp(edge, minf(1.0, live * 1.4)), LIVE, w, true)
		c.draw_circle(centre, w * 0.5, LIVE)
		var phase := 0.3 if wants_less_motion() else fposmod(float(Time.get_ticks_msec()) * 0.001 * 1.4, 1.0)
		for port: int in Rule.ports(kind, rot):
			var edge := centre + Vector2(float(Rule.DX[port]), float(Rule.DY[port])) * half
			c.draw_circle(centre.lerp(edge, phase), w * 0.32, Color(1, 1, 1, 0.95))
	if kind == Rule.VOLT:
		var body := Rect2(centre - Vector2(half, half) * 0.62, Vector2(half, half) * 1.24)
		var t := Kit.tex("power_bench/booster" if volts > 0 else "power_bench/reducer")
		Kit.draw_fit(c, t, body, Color(1, 1, 1, alpha))
		_volt_badge(c, rect.position + Vector2(rect.size.x * 0.78, rect.size.y * 0.2), rect.size.x * 0.17, volts, alpha)


## "+2" / "-1" on a small disc, with an up or down arrow shape (never colour alone).
func _volt_badge(c: Control, at: Vector2, r: float, volts: int, alpha: float) -> void:
	c.draw_circle(at, r, Color(Kit.INK, alpha))
	var color := LIVE if volts > 0 else Color(0.55, 0.8, 1.0)
	c.draw_arc(at, r, 0.0, TAU, 20, Color(color, alpha), maxf(1.5, r * 0.14), true)
	Kit.text(c, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), "%+d" % volts, Color(color, alpha), r / 15.0)


func _draw_tray(c: Control) -> void:
	var tray := _r(TRAY)
	Kit.box(c, tray, Kit.METAL_DARK, 14.0 * _k, Kit.BAY_LIP, 2.0)
	var slots: Array = _layout.slots
	for slot in mini(slots.size(), MAX_SLOTS):
		var rect := _slot_rect(slot)
		var info: Dictionary = slots[slot]
		var left := Rule.remaining(_layout, _board, slot)
		var held := slot == _hand_slot
		var face := rect
		if held:
			face.position.y -= 6.0 * _k
		Kit.box(c, face, Kit.BAY if not held else Kit.BAY_LIP, 10.0 * _k, Kit.BAY_LIP if not held else UiTheme.palette().focus, 2.0)
		var piece := Rect2(face.get_center() - Vector2(1, 1) * face.size.x * 0.36 - Vector2(0, 8.0 * _k), Vector2(1, 1) * face.size.x * 0.72)
		var alpha := 1.0 if left > 0 else 0.3
		Kit.draw_fill(c, Kit.tex("power_bench/cell_plate"), piece, Color(1, 1, 1, alpha))
		_draw_piece(c, piece, int(info.kind), _hand_rot if held else 0, int(info.volts), 0.0, alpha)
		Kit.pips(c, Vector2(face.get_center().x, face.end.y - 9.0 * _k), maxi(1, int(info.count)), left, maxf(3.0, 4.5 * _k))
		# The number key for the part.
		Kit.text(c, Rect2(face.position + Vector2(4, 2) * _k, Vector2(18, 18) * _k), str(slot + 1), Color(1, 1, 1, 0.55), 0.6 * _k / 0.95)
	# The two tools: turn, and take out.
	for i in 2:
		var rect := _tool_rect(i)
		Kit.box(c, rect, Kit.BAY, 10.0 * _k, Kit.BAY_LIP, 2.0)
		var at := rect.get_center() - Vector2(0, 6.0 * _k)
		var r := rect.size.x * 0.24
		if i == 0:
			Kit.turn_arrows(c, at, r, Color.WHITE)
			Kit.text(c, Rect2(rect.position.x, rect.end.y - 22.0 * _k, rect.size.x, 18.0 * _k), "R", Color(1, 1, 1, 0.55), 0.6 * _k / 0.95)
		else:
			Kit.box(c, Rect2(at + Vector2(-r, -r * 0.2), Vector2(r * 2.0, r * 1.1)), Color(0, 0, 0, 0), 4.0, Color.WHITE, 2.0)
			Kit.arrow(c, at + Vector2(0, r * 0.4), at + Vector2(0, -r * 1.2), Color.WHITE, maxf(2.0, 3.0 * _k))
			Kit.text(c, Rect2(rect.position.x, rect.end.y - 22.0 * _k, rect.size.x, 18.0 * _k), "Del", Color(1, 1, 1, 0.55), 0.6 * _k / 0.95)


## The shared marks over the buttons: hover, a ghost of the part in hand over the cell under the keyboard / mouse,
## the target ring on the gap (where the current stops), the focus ring.
func _paint_marks(c: Control) -> void:
	if _k <= 0.0 or _layout.is_empty():
		return
	var less := wants_less_motion()
	var all: Array[Button] = []
	all.append_array(cells)
	all.append_array(slot_buttons)
	all.append(turn_button)
	all.append(remove_button)
	var ghost_cell := -1
	for b in all:
		if not b.visible:
			continue
		if b.is_hovered() and not b.disabled and not b.has_focus():
			Kit.box(c, Rect2(b.position, b.size).grow(-2.0), Color(1, 1, 1, 0.05), 10.0 * _k, Color(1, 1, 1, 0.5), 2.0)
		if (b.is_hovered() or b.has_focus()) and cells.has(b):
			ghost_cell = cells.find(b)
	if _hand_slot >= 0 and ghost_cell >= 0 and not succeeded and not (_layout.blocked as Array).has(ghost_cell) \
			and Rule.piece_at(_layout, _board, ghost_cell).is_empty():
		var info: Dictionary = _layout.slots[_hand_slot]
		_draw_piece(c, _cell_rect(ghost_cell), int(info.kind), _hand_rot, int(info.volts), 0.0, 0.55)
	if _gap >= 0 and not succeeded and not pending:
		Kit.target_ring(c, _cell_rect(_gap).grow(-3.0), 10.0 * _k, less)
	for b in all:
		if b.visible and b.has_focus():
			Kit.focus_ring(c, Rect2(b.position, b.size).grow(-3.0), 10.0 * _k, 4.0)
