extends "res://scripts/tasks/puzzles/board_ui.gd"
## T08 "Glaze the Dome" mini-game (Garden dome, broken pane BP05): fit five glass pieces into the dome window.
## The host rule (t08_rule.gd) checks every placement and decides completion; this panel only sends "place" / "lift"
## moves and draws the host's puzzle_state.
##
## UI overhaul (2026-11-15, docs/revisions/ui_overhaul/MINIGAME_BRIEF.md): ONE scene drawn on a single control.
##   Left   the dome window: a metal frame (sprite dome/dome_frame) whose opening shows the Mars sky (dome/mars_view)
##          and the 4 x 4 squares of the missing pane. Under it the sill, where the sunlight that passes through every
##          fitted piece lands as a patch of its colour.
##   Right  the tray with the five loose glass pieces (each colour carries its own shape mark) and the turn knob.
## Play: pick a piece (click / Enter: it lifts, Kit.focus_ring), turn it (R, right-click or the knob), point at a
## window square (mouse or arrow keys): a preview of the piece shows where it would land, pale when it fits, amber
## with a cross on every blocked square when it does not; click / Enter places it. A piece can also be dragged from
## the tray onto the window. Pressing a fitted piece (in the window or its empty tray place) takes it back out.
## When the fifth piece is in, one shimmer sweeps across the pane (not with "less motion").
## Every part is a flat focusable button laid over the art (frame_tiles, piece_tiles, turn_button).

const RULE := preload("res://scripts/tasks/puzzles/t08_rule.gd")
## Glass colours and the shape mark each one carries (colour is never the only cue).
const TINTS := [Color(0.36, 0.66, 0.98), Color(0.97, 0.47, 0.6), Color(0.2, 0.8, 0.72), Color(0.72, 0.56, 0.97), Color(0.8, 0.9, 0.36)]
const MARKS := [Kit.CIRCLE, Kit.TRIANGLE, Kit.SQUARE, Kit.DIAMOND, Kit.STAR]
const MARK_WORDS := ["Circle", "Triangle", "Square", "Diamond", "Star"]
## How far the frame sprite's metal reaches in from each side, as a part of its width (the rest is the opening).
const FRAME_RIM := 0.15
const FELT := Color(0.125, 0.15, 0.185)
const CUE_PICK := "Pick a glass piece [Enter]"
const CUE_FIT := "Turn it [R] then fit it [Enter]"
const LINE_PICK_FIRST := "Pick a glass piece first."
const LINE_NO_FIT := "It does not fit there."
const LINE_SOLVED := "The dome is sealed!"
const SHAKE_SECONDS := 0.35

## The one drawn control (window, sill, tray) and the clipped overlay the shimmer is drawn on.
var board: Paint
var shine: Paint
var frame_tiles: Array = []
var piece_tiles: Array = []
var turn_button: Button
## Tray piece picked for placing, or -1.
var selected := -1
## Quarter turns the player has given each tray piece (the host only sees the turn inside a "place" move).
var ui_turns: Array[int] = [0, 0, 0, 0, 0]
## The window square under the mouse or keyboard focus.
var anchor := Vector2i.ZERO

# Layout, worked out from the board's size.
var _window := Rect2()
var _opening := Rect2()
var _sill := Rect2()
var _tray := Rect2()
var _slots: Array[Rect2] = []
var _cell := 0.0
var _unit := 0.0
# Animation state (seconds or 0..1); all of it is only for show.
var _lit: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _spin := 0.0
var _shake := 0.0
var _shimmer := -1.0
var _seen_filled := -1
# A piece on its way out of the window is picked up again once the host confirms the lift.
var _lifting := -1
# Dragging a tray piece with the mouse.
var _drag_piece := -1
var _drag_from := Vector2.ZERO
var _drag_at := Vector2.ZERO
var _dragging := false
var _drag_over := false


func setup(p_services: GameServices) -> void:
	rule = RULE
	task_title = "Glaze the Dome"
	instructions = ("Fit all five glass pieces into the window. Pick a piece, turn it with R, then point at the "
		+ "window and press Enter or click. Press a fitted piece to take it back out.")
	super.setup(p_services)
	name = "T08GlassPanel"
	_update_cue()


func _build_board() -> void:
	board = Paint.new()
	board.name = "Dome"
	board.custom_minimum_size = Vector2(900, 420)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.painter = _paint_board
	Kit.smooth(board)
	play_area.add_child(board)
	# The tray pieces come first: the keyboard starts on a piece, because picking one is the first step.
	for piece in RULE.PIECES:
		var tile := _part("Piece%d" % piece, piece)
		tile.tooltip_text = "%s glass piece" % MARK_WORDS[piece]
		tile.pressed.connect(_on_piece_pressed.bind(piece))
		tile.gui_input.connect(_on_piece_input.bind(piece))
		piece_tiles.append(tile)
	for cell in RULE.SIZE * RULE.SIZE:
		var tile := _part("Frame%d" % cell, cell)
		tile.tooltip_text = "Window square, row %d, column %d" % [cell / RULE.SIZE + 1, cell % RULE.SIZE + 1]
		tile.pressed.connect(_on_frame_pressed.bind(cell))
		tile.focus_entered.connect(_point_at.bind(cell))
		tile.mouse_entered.connect(_on_frame_hover.bind(cell))
		frame_tiles.append(tile)
	turn_button = _part("TurnPiece", -1)
	turn_button.tooltip_text = "Turn the glass piece (R)"
	turn_button.pressed.connect(turn_selected)
	shine = Paint.new()
	shine.name = "Shimmer"
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shine.clip_contents = true
	shine.painter = _paint_shine
	board.add_child(shine)
	board.resized.connect(_layout)


## A flat, focusable button with no look of its own: the board draws the part underneath it and its focus ring.
func _part(node_name: String, index: int) -> Tile:
	var tile := make_tile(node_name, index, Vector2.ZERO, Callable())
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		tile.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	# The focus mark is Kit.focus_ring, drawn by the board around the part (see _paint_board).
	var quiet := StyleBoxFlat.new()
	quiet.draw_center = false
	tile.add_theme_stylebox_override(&"focus", quiet)
	tile.gui_input.connect(_on_tile_input)
	tile.focus_entered.connect(_repaint)
	tile.focus_exited.connect(_repaint)
	board.add_child(tile)
	return tile


# ---------------------------------------------------------------- layout

func _layout() -> void:
	var s := board.size
	if s.x < 80.0 or s.y < 80.0:
		return
	var pad := clampf(s.y * 0.035, 10.0, 20.0)
	var avail := s.y - pad * 2.0
	var sill_h := avail * 0.17
	var side := minf(avail - sill_h, s.x * 0.44)
	_window = Rect2(pad, (s.y - side - sill_h) * 0.5, side, side)
	_opening = _window.grow(-side * FRAME_RIM)
	_cell = _opening.size.x / float(RULE.SIZE)
	_sill = Rect2(_window.position.x, _window.end.y, side, sill_h)
	_tray = Rect2(_window.end.x + pad, pad, s.x - _window.end.x - pad * 2.0, avail)
	# Six places on the tray (five pieces and the turn knob): three across or two across, whichever shows the pieces
	# larger. A place holds a piece in any turn, so it is four squares wide and high.
	var felt := _tray.grow(-14.0)
	var cols := 3
	var unit := 0.0
	for try_cols: int in [3, 2]:
		var u := minf(felt.size.x / float(try_cols), felt.size.y / float(6 / try_cols)) * 0.84 / 4.0
		if u > unit + 0.5:
			unit = u
			cols = try_cols
	var rows := 6 / cols
	_unit = minf(unit, _cell)
	var slot_size := Vector2(felt.size.x / float(cols), felt.size.y / float(rows))
	_slots.clear()
	for i in 6:
		_slots.append(Rect2(felt.position + Vector2(float(i % cols), float(i / cols)) * slot_size, slot_size).grow(-4.0))
	var slot_tiles: Array = piece_tiles + [turn_button]
	for i in 6:
		var tile := slot_tiles[i] as Control
		tile.position = _slots[i].position
		tile.size = _slots[i].size
		var col := i % cols
		var row := i / cols
		var frame_row := clampi(int((float(row) + 0.5) * float(RULE.SIZE) / float(rows)), 0, RULE.SIZE - 1)
		_neighbours(tile, frame_tiles[frame_row * RULE.SIZE + RULE.SIZE - 1] if col == 0 else slot_tiles[i - 1],
			slot_tiles[i + 1] if col < cols - 1 else tile, slot_tiles[i - cols] if row > 0 else tile,
			slot_tiles[i + cols] if row < rows - 1 else tile)
	for cell in frame_tiles.size():
		var tile := frame_tiles[cell] as Control
		var x := cell % RULE.SIZE
		var y := cell / RULE.SIZE
		tile.position = _opening.position + Vector2(x, y) * _cell
		tile.size = Vector2(_cell, _cell)
		var slot_row := clampi(int((float(y) + 0.5) * float(rows) / float(RULE.SIZE)), 0, rows - 1)
		_neighbours(tile, frame_tiles[cell - 1] if x > 0 else tile,
			frame_tiles[cell + 1] if x < RULE.SIZE - 1 else slot_tiles[slot_row * cols],
			frame_tiles[cell - RULE.SIZE] if y > 0 else tile, frame_tiles[cell + RULE.SIZE] if y < RULE.SIZE - 1 else tile)
	shine.position = _opening.position
	shine.size = _opening.size
	_repaint()


## Arrow keys walk the window squares and the tray places (all of them are children of the board).
func _neighbours(tile: Control, left: Control, right: Control, up: Control, down: Control) -> void:
	tile.focus_neighbor_left = NodePath("../" + String(left.name))
	tile.focus_neighbor_right = NodePath("../" + String(right.name))
	tile.focus_neighbor_top = NodePath("../" + String(up.name))
	tile.focus_neighbor_bottom = NodePath("../" + String(down.name))


# ---------------------------------------------------------------- state from the host

func _redraw() -> void:
	var placed: Array = puzzle_state.get("placed", [])
	var pieces: Array = puzzle_state.get("pieces", [])
	if _lifting >= 0 and _lifting < placed.size() and (placed[_lifting] as Array).is_empty():
		selected = _lifting
	_lifting = -1
	if selected >= 0 and selected < placed.size() and not (placed[selected] as Array).is_empty():
		# The piece went in: the hand is empty again and the keyboard goes back to the tray for the next piece.
		var next := _next_free(selected)
		selected = -1
		var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
		if next >= 0 and (owner == null or frame_tiles.has(owner)):
			(piece_tiles[next] as Control).grab_focus()
	for i in mini(piece_tiles.size(), mini(pieces.size(), placed.size())):
		var words := "%s glass piece (%s)" % [MARK_WORDS[i], String(pieces[i].name).to_lower()]
		if not (placed[i] as Array).is_empty():
			words += ", in the window. Press to take it out."
		(piece_tiles[i] as Control).tooltip_text = words
	var filled := 0
	for owner_piece: Variant in puzzle_state.get("board", []):
		if int(owner_piece) >= 0:
			filled += 1
	var whole := RULE.SIZE * RULE.SIZE
	if filled == whole and _seen_filled >= 0 and _seen_filled < whole and not wants_less_motion():
		_shimmer = 0.0
	_seen_filled = filled
	_update_cue()
	_repaint()


func _status_line() -> String:
	return LINE_SOLVED if succeeded else ""


func accept_host_result(result: ActionResult, record := {}) -> void:
	super.accept_host_result(result, record)
	if succeeded and status_label != null:
		status_label.text = LINE_SOLVED


func _update_cue() -> void:
	if not succeeded:
		set_cue(CUE_FIT if selected >= 0 else CUE_PICK)


func _repaint() -> void:
	if board != null:
		board.queue_redraw()


func _process(delta: float) -> void:
	super._process(delta)
	if board == null or _cell <= 0.0:
		return
	var calm := wants_less_motion()
	var changed := false
	var placed: Array = puzzle_state.get("placed", [])
	for i in RULE.PIECES:
		var inside := i < placed.size() and not (placed[i] as Array).is_empty()
		var light := 0.0 if not inside else (1.0 if calm else minf(1.0, _lit[i] + delta / 0.45))
		changed = changed or light != _lit[i]
		_lit[i] = light
	if _spin > 0.0:
		_spin = 0.0 if calm else maxf(0.0, _spin - delta / 0.16)
		changed = true
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		changed = true
	if _shimmer >= 0.0:
		_shimmer += delta / 0.9
		if _shimmer >= 1.0 or calm:
			_shimmer = -1.0
		shine.queue_redraw()
	# The target ring breathes, so the board is drawn every frame unless the player asked for less motion.
	if changed or not calm:
		board.queue_redraw()


# ---------------------------------------------------------------- moves

## Gives the picked piece a quarter turn clockwise (only on screen until it is placed).
func turn_selected() -> void:
	if succeeded:
		return
	if selected < 0:
		show_hint(LINE_PICK_FIRST)
		return
	ui_turns[selected] = (ui_turns[selected] + 1) % 4
	_spin = 1.0
	_repaint()


## The top-left square the picked piece would use when pointed at `cell`, pulled inside the frame.
func placement_for(cell: int) -> Vector2i:
	if selected < 0:
		return Vector2i(cell % RULE.SIZE, cell / RULE.SIZE)
	var size := RULE.extent(RULE.turned(puzzle_state.pieces[selected].cells, ui_turns[selected]))
	return Vector2i(clampi(cell % RULE.SIZE, 0, RULE.SIZE - size.x), clampi(cell / RULE.SIZE, 0, RULE.SIZE - size.y))


func _on_piece_pressed(piece: int) -> void:
	var placed: Array = puzzle_state.get("placed", [])
	if piece >= placed.size() or _dragging:
		return
	if not (placed[piece] as Array).is_empty():
		_lifting = piece
		send_move("lift", piece)
		return
	selected = piece
	_update_cue()
	_repaint()
	(frame_tiles[anchor.y * RULE.SIZE + anchor.x] as Control).grab_focus()


func _on_frame_pressed(cell: int) -> void:
	_point_at(cell)
	var squares: Array = puzzle_state.get("board", [])
	if selected < 0:
		if cell < squares.size() and int(squares[cell]) >= 0:
			_lifting = int(squares[cell])
			send_move("lift", _lifting)
		else:
			show_hint(LINE_PICK_FIRST)
		return
	var at := placement_for(cell)
	if not String(RULE.why_not(puzzle_state, selected, at.x, at.y, ui_turns[selected])).is_empty():
		_shake = SHAKE_SECONDS
		show_hint(LINE_NO_FIT)
		_repaint()
		return
	send_move("place", selected * 64 + ui_turns[selected] * 16 + at.y * 4 + at.x)


func _point_at(cell: int) -> void:
	anchor = Vector2i(cell % RULE.SIZE, cell / RULE.SIZE)
	_repaint()


## The mouse over a window square moves the keyboard there too, so there is one cursor, not two.
func _on_frame_hover(cell: int) -> void:
	var tile := frame_tiles[cell] as Button
	if tile.disabled or _drag_piece >= 0:
		return
	if tile.has_focus():
		_point_at(cell)
	else:
		tile.grab_focus()


func _on_tile_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_R:
		turn_selected()
		accept_event()
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		turn_selected()
		accept_event()


## Dragging: press a loose piece, carry it over the window and let go on a square.
func _on_piece_input(event: InputEvent, piece: int) -> void:
	var placed: Array = puzzle_state.get("placed", [])
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if succeeded or pending or piece >= placed.size() or not (placed[piece] as Array).is_empty():
				return
			selected = piece
			_drag_piece = piece
			_drag_from = board.get_local_mouse_position()
			_dragging = false
			_update_cue()
			_repaint()
		elif _drag_piece == piece:
			var drop := _dragging and _drag_over
			_drag_piece = -1
			_dragging = false
			if drop:
				_on_frame_pressed(anchor.y * RULE.SIZE + anchor.x)
			_repaint()
	elif event is InputEventMouseMotion and _drag_piece == piece:
		_drag_at = board.get_local_mouse_position()
		if not _dragging and _drag_at.distance_to(_drag_from) > 10.0:
			_dragging = true
		_drag_over = _opening.grow(_cell * 0.35).has_point(_drag_at)
		if _drag_over:
			var at := ((_drag_at - _opening.position) / _cell).floor()
			anchor = Vector2i(clampi(int(at.x), 0, RULE.SIZE - 1), clampi(int(at.y), 0, RULE.SIZE - 1))
		_repaint()


func _next_free(after: int) -> int:
	var placed: Array = puzzle_state.get("placed", [])
	for i in placed.size():
		var piece := (after + 1 + i) % placed.size()
		if (placed[piece] as Array).is_empty():
			return piece
	return -1


## The preview: where the picked piece would land at the anchor, its squares there and whether it fits.
func _ghost() -> Dictionary:
	if selected < 0 or not puzzle_state.has("pieces"):
		return {}
	var at := placement_for(anchor.y * RULE.SIZE + anchor.x)
	return {"at": at, "shape": RULE.turned(puzzle_state.pieces[selected].cells, ui_turns[selected]),
		"cells": RULE.covered(puzzle_state.pieces[selected].cells, at.x, at.y, ui_turns[selected]),
		"fits": String(RULE.why_not(puzzle_state, selected, at.x, at.y, ui_turns[selected])).is_empty()}


# ---------------------------------------------------------------- drawing

func _paint_board(c: Control) -> void:
	if _cell <= 0.0:
		return
	var calm := wants_less_motion()
	Kit.bay(c, Rect2(Vector2.ZERO, c.size))
	_paint_sill(c)
	_paint_window(c, calm)
	_paint_tray(c, calm)
	if _dragging and selected >= 0 and puzzle_state.has("pieces"):
		# The piece in the hand: its top-left square rides on the pointer, just where the preview lands.
		var cells := RULE.turned(puzzle_state.pieces[selected].cells, ui_turns[selected])
		var origin := _drag_at - Vector2(_cell, _cell) * 0.5
		_shadow(c, cells, origin, _cell, 0.4)
		_glass(c, cells, origin, _cell, selected, 0.82)


func _paint_window(c: Control, calm: bool) -> void:
	var p := UiTheme.palette()
	var pieces: Array = puzzle_state.get("pieces", [])
	var placed: Array = puzzle_state.get("placed", [])
	var squares: Array = puzzle_state.get("board", [])
	# Outside: the Mars sky. It tucks a little under the frame.
	var view := _opening.grow(_cell * 0.12)
	var sky := Kit.tex("dome/mars_view")
	if sky != null:
		c.draw_texture_rect(sky, view, false, Color(0.9, 0.9, 0.9))
	else:
		c.draw_polygon(PackedVector2Array([view.position, Vector2(view.end.x, view.position.y), view.end, Vector2(view.position.x, view.end.y)]),
			PackedColorArray([Color(0.8, 0.6, 0.45), Color(0.93, 0.74, 0.52), Color(0.62, 0.36, 0.25), Color(0.55, 0.32, 0.23)]))
	# The squares of the missing pane.
	var guide := Color(1, 1, 1, 0.3)
	for i in range(1, RULE.SIZE):
		var d := float(i) * _cell
		c.draw_line(_opening.position + Vector2(d, 0), _opening.position + Vector2(d, _opening.size.y), guide, 1.5)
		c.draw_line(_opening.position + Vector2(0, d), _opening.position + Vector2(_opening.size.x, d), guide, 1.5)
	# Fitted glass: see-through colour, brighter for a moment as it goes in.
	for piece in mini(pieces.size(), placed.size()):
		var at: Array = placed[piece]
		if at.is_empty():
			continue
		var cells := RULE.turned(pieces[piece].cells, int(at[2]))
		_glass(c, cells, _opening.position + Vector2(int(at[0]), int(at[1])) * _cell, _cell, piece, 0.66, 1.0 - _lit[piece])
	# The frame over the edges of the glass.
	var frame := Kit.tex("dome/dome_frame")
	if frame != null:
		c.draw_texture_rect(frame, _window, false)
	else:
		_plain_frame(c)
	if succeeded:
		return
	# The preview of the picked piece, or the keyboard's square when the hand is empty.
	var ghost := _ghost()
	if not ghost.is_empty():
		if _dragging and not _drag_over:
			return
		var nudge := sin(_shake * 46.0) * 6.0 * (_shake / SHAKE_SECONDS) if _shake > 0.0 else 0.0
		var origin := _opening.position + Vector2(ghost.at) * _cell + Vector2(nudge, 0.0)
		var line_width := maxf(3.0, _cell * 0.07)
		if bool(ghost.fits):
			var beat := 0.5 if calm else Kit.pulse(0.9)
			_outline(c, ghost.shape, origin, _cell, Color(TINTS[selected], 0.3 + 0.12 * beat), Color(0.93, 0.98, 1.0, 0.96), line_width)
			for cell: Array in ghost.shape:
				var mid := origin + (Vector2(int(cell[0]), int(cell[1])) + Vector2(0.5, 0.5)) * _cell
				Kit.shape(c, MARKS[selected], mid, _cell * 0.15, Color(1, 1, 1, 0.8), Color(Kit.INK, 0.55))
		else:
			_outline(c, ghost.shape, origin, _cell, Color(p.warn, 0.2), p.warn, line_width)
			# A cross on every square that is already taken: "does not fit" by shape as well as colour.
			for cell: int in ghost.cells:
				if cell >= 0 and cell < squares.size() and int(squares[cell]) >= 0:
					Kit.cross(c, _square(cell).get_center() + Vector2(nudge, 0.0), _cell * 0.2)
	else:
		var here := anchor.y * RULE.SIZE + anchor.x
		if here < frame_tiles.size() and (frame_tiles[here] as Control).has_focus():
			Kit.focus_ring(c, _square(here).grow(-5.0), 8.0, 4.0)


func _square(cell: int) -> Rect2:
	return Rect2(_opening.position + Vector2(cell % RULE.SIZE, cell / RULE.SIZE) * _cell, Vector2(_cell, _cell))


## The frame without its sprite: four metal bars round the opening.
func _plain_frame(c: Control) -> void:
	var rim := _opening.position.x - _window.position.x
	for bar: Rect2 in [Rect2(_window.position, Vector2(_window.size.x, rim)), Rect2(_window.position.x, _opening.end.y, _window.size.x, rim),
			Rect2(_window.position, Vector2(rim, _window.size.y)), Rect2(_opening.end.x, _window.position.y, rim, _window.size.y)]:
		c.draw_rect(bar, Kit.METAL)
	c.draw_rect(_opening.grow(3.0), Kit.HOUSING, false, 6.0)
	c.draw_rect(_window, Kit.METAL_DARK, false, 4.0)
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		Kit.screw(c, _window.position + Vector2(rim, rim) * 0.5 + corner * (_window.size - Vector2(rim, rim)), rim * 0.16)


## The sill under the window: the window's light lands on it, one patch for every square of fitted glass.
func _paint_sill(c: Control) -> void:
	var top := Rect2(_sill.position, _sill.size - Vector2(0, _sill.size.y * 0.14))
	Kit.box(c, _sill, Kit.HOUSING_DARK.darkened(0.5), 10.0)
	Kit.box(c, top, Kit.HOUSING_DARK.darkened(0.22), 10.0)
	var pieces: Array = puzzle_state.get("pieces", [])
	var placed: Array = puzzle_state.get("placed", [])
	var squares: Array = puzzle_state.get("board", [])
	var from := Vector2(_opening.position.x, top.position.y + top.size.y * 0.16)
	var row_h := top.size.y * 0.7 / float(RULE.SIZE)
	const SLANT := 0.8
	for cell in mini(squares.size(), RULE.SIZE * RULE.SIZE):
		var x := cell % RULE.SIZE
		var depth := float(RULE.SIZE - 1 - cell / RULE.SIZE) * row_h
		var quad := PackedVector2Array([from + Vector2(float(x) * _cell - depth * SLANT, depth),
			from + Vector2(float(x + 1) * _cell - depth * SLANT, depth),
			from + Vector2(float(x + 1) * _cell - (depth + row_h) * SLANT, depth + row_h),
			from + Vector2(float(x) * _cell - (depth + row_h) * SLANT, depth + row_h)])
		var piece := int(squares[cell])
		if piece >= 0 and piece < pieces.size() and piece < placed.size():
			c.draw_colored_polygon(quad, Color((TINTS[piece] as Color).lightened(0.3), 0.9 * _lit[piece]))
		quad.append(quad[0])
		c.draw_polyline(quad, Color(0, 0, 0, 0.16), 1.0, true)


func _paint_tray(c: Control, calm: bool) -> void:
	var p := UiTheme.palette()
	var pieces: Array = puzzle_state.get("pieces", [])
	var placed: Array = puzzle_state.get("placed", [])
	Kit.housing(c, _tray, 18.0, false)
	Kit.box(c, _tray.grow(-12.0), FELT, 12.0, Kit.BAY_EDGE, 2.0)
	var suggest := _next_free(-1) if selected < 0 and not succeeded else -1
	for piece in mini(pieces.size(), mini(placed.size(), _slots.size())):
		var slot := _slots[piece]
		var held := piece == selected
		var away := not (placed[piece] as Array).is_empty()
		var cells := RULE.turned(pieces[piece].cells, ui_turns[piece])
		var half := Vector2(RULE.extent(cells)) * _unit * 0.5
		if away or (held and _dragging):
			# Its place on the tray is empty: only the outline is left.
			_outline(c, cells, slot.get_center() - half, _unit, Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.16), 2.0)
		else:
			var lift := Vector2(0, -_unit * 0.16) if held else Vector2.ZERO
			var angle := -PI * 0.5 * _spin if held else 0.0
			c.draw_set_transform(slot.get_center() + lift, angle, Vector2.ONE)
			_shadow(c, cells, -half - lift * 0.5, _unit, 0.45 if held else 0.3)
			_glass(c, cells, -half, _unit, piece, 0.94)
			c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if succeeded:
			continue
		if held or (piece_tiles[piece] as Control).has_focus():
			Kit.focus_ring(c, slot.grow(-5.0), 14.0, 4.0)
		elif piece == suggest:
			Kit.target_ring(c, slot.grow(-7.0), 14.0, calm)
	# The turn knob: two chasing arrows and the key that does the same.
	if _slots.size() < 6:
		return
	var knob := _slots[5]
	var live := selected >= 0 and not succeeded
	var r := minf(knob.size.x, knob.size.y) * 0.26
	var mid := knob.get_center() - Vector2(0, r * 0.3)
	c.draw_circle(mid + Vector2(0, 4), r, Kit.BAY_EDGE)
	c.draw_circle(mid, r, Kit.METAL_DARK)
	c.draw_arc(mid, r - 2.0, 0.0, TAU, 40, Kit.HAZARD if live else Kit.METAL, 3.0, true)
	Kit.turn_arrows(c, mid, r * 0.52, p.text if live else Color(p.muted, 0.55))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var cap := Kit.key_cap(c, mid + Vector2(0, r + c.get_theme_font_size(&"font_size", &"Label") * 0.95), "R", 0.8)
	if not live:
		Kit.box(c, cap.grow(2.0), Color(FELT, 0.55), 7.0)
	if turn_button.has_focus() and not succeeded:
		Kit.focus_ring(c, knob.grow(-5.0), 14.0, 4.0)


## The one shimmer across the whole pane when the fifth piece is in (drawn on the clipped overlay).
func _paint_shine(c: Control) -> void:
	if _shimmer < 0.0:
		return
	var t := smoothstep(0.0, 1.0, _shimmer)
	var band := c.size.x * 0.22
	var lean := c.size.y * 0.45
	var x := lerpf(-band - lean, c.size.x + band + lean, t)
	var bright := Color(1, 1, 1, 0.7)
	var clear := Color(1, 1, 1, 0.0)
	var top := Vector2(x + lean * 0.5, 0.0)
	var foot := Vector2(x - lean * 0.5, c.size.y)
	c.draw_polygon(PackedVector2Array([top - Vector2(band, 0), top, foot, foot - Vector2(band, 0)]), PackedColorArray([clear, bright, bright, clear]))
	c.draw_polygon(PackedVector2Array([top, top + Vector2(band, 0), foot + Vector2(band, 0), foot]), PackedColorArray([bright, clear, clear, bright]))


static func _cell_set(cells: Array) -> Dictionary:
	var has := {}
	for cell: Variant in cells:
		has[Vector2i(int(cell[0]), int(cell[1]))] = true
	return has


## One piece of glass: `cells` squares of `unit` pixels from `origin`. One sheet of colour that is lighter towards
## its top-left, a glint and the piece's shape mark on every square, and a dark edge all the way round.
## `flash` (0..1) whitens it (the moment it goes into the window).
func _glass(c: CanvasItem, cells: Array, origin: Vector2, unit: float, piece: int, alpha: float, flash_amount := 0.0) -> void:
	var tint: Color = TINTS[piece]
	var has := _cell_set(cells)
	var size := RULE.extent(cells)
	var span := float(size.x + size.y)
	for at: Vector2i in has:
		var r := Rect2(origin + Vector2(at) * unit, Vector2(unit, unit))
		var colours := PackedColorArray()
		for corner: Vector2i in [at, at + Vector2i(1, 0), at + Vector2i(1, 1), at + Vector2i(0, 1)]:
			var t := float(corner.x + corner.y) / span
			colours.append(Color(tint.lightened(0.36 * (1.0 - t)).darkened(0.14 * t), alpha))
		c.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), colours)
		if flash_amount > 0.0:
			c.draw_rect(r, Color(1, 1, 1, 0.55 * flash_amount))
		# Seams between the squares of one piece, so they can be counted.
		var seam := Color(tint.darkened(0.45), 0.4)
		if has.has(at + Vector2i(1, 0)):
			c.draw_line(Vector2(r.end.x, r.position.y), r.end, seam, 1.0)
		if has.has(at + Vector2i(0, 1)):
			c.draw_line(Vector2(r.position.x, r.end.y), r.end, seam, 1.0)
		var glint := Color(1, 1, 1, 0.5)
		c.draw_line(r.position + Vector2(0.14, 0.4) * unit, r.position + Vector2(0.4, 0.14) * unit, glint, maxf(1.5, unit * 0.055), true)
		c.draw_line(r.position + Vector2(0.14, 0.58) * unit, r.position + Vector2(0.24, 0.48) * unit, glint, maxf(1.5, unit * 0.055), true)
		Kit.shape(c, MARKS[piece], r.position + Vector2(0.56, 0.58) * unit, unit * 0.17, tint.lightened(0.72), tint.darkened(0.62))
	_edges(c, has, origin, unit, tint.darkened(0.55), maxf(2.0, unit * 0.075))


## The soft shadow a loose piece throws on the tray.
func _shadow(c: CanvasItem, cells: Array, origin: Vector2, unit: float, alpha: float) -> void:
	for cell: Variant in cells:
		c.draw_rect(Rect2(origin + Vector2(int(cell[0]), int(cell[1])) * unit + Vector2(unit * 0.07, unit * 0.12), Vector2(unit, unit)), Color(0, 0, 0, alpha))


## The shape of a piece as a filled outline (the preview in the window, an empty place on the tray).
func _outline(c: CanvasItem, cells: Array, origin: Vector2, unit: float, fill: Color, line: Color, width: float) -> void:
	var has := _cell_set(cells)
	if fill.a > 0.0:
		for at: Vector2i in has:
			c.draw_rect(Rect2(origin + Vector2(at) * unit, Vector2(unit, unit)), fill)
	_edges(c, has, origin, unit, line, width)


## A line along every side of the piece that has no neighbour square (its outer edge).
func _edges(c: CanvasItem, has: Dictionary, origin: Vector2, unit: float, line: Color, width: float) -> void:
	var h := width * 0.5
	for at: Vector2i in has:
		var r := Rect2(origin + Vector2(at) * unit, Vector2(unit, unit))
		if not has.has(at + Vector2i(0, -1)):
			c.draw_rect(Rect2(r.position.x - h, r.position.y - h, unit + width, width), line)
		if not has.has(at + Vector2i(0, 1)):
			c.draw_rect(Rect2(r.position.x - h, r.end.y - h, unit + width, width), line)
		if not has.has(at + Vector2i(-1, 0)):
			c.draw_rect(Rect2(r.position.x - h, r.position.y - h, width, unit + width), line)
		if not has.has(at + Vector2i(1, 0)):
			c.draw_rect(Rect2(r.end.x - h, r.position.y - h, width, unit + width), line)
