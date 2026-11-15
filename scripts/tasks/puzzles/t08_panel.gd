extends "res://scripts/tasks/puzzles/board_ui.gd"
## T08 Glass mini-game (Garden dome, broken pane BP05): fit five glass pieces into the empty square frame.
## The host rule (t08_rule.gd) checks every placement and decides completion; this panel only sends "place" / "lift"
## moves and draws the host's puzzle_state. A ghost shows where the picked piece would go before it is placed.
## Controls: pick a piece in the tray (click / Enter), turn it with R, the Turn button or a right-click, point at a
## frame square (mouse, or arrow keys) and click / Enter to place it. Pressing a placed piece takes it back out.
## Each piece has its own tint AND its letter and name drawn on it, so colour is never the only cue.

const RULE := preload("res://scripts/tasks/puzzles/t08_rule.gd")
const CELL := 74.0
const TINTS := [Color(0.45, 0.78, 0.98), Color(0.98, 0.72, 0.38), Color(0.62, 0.9, 0.55), Color(0.85, 0.6, 0.95), Color(0.98, 0.9, 0.45)]

var frame_tiles: Array = []
var piece_tiles: Array = []
var turn_button: Button
## Tray piece picked for placing, or -1.
var selected := -1
## Quarter turns the player has given each tray piece (the host only sees the turn inside a "place" move).
var ui_turns: Array[int] = [0, 0, 0, 0, 0]
## The frame square under the mouse or keyboard focus.
var anchor := Vector2i.ZERO


func setup(p_services: GameServices) -> void:
	rule = RULE
	task_title = "Repair the broken glass"
	instructions = ("Fit all five glass pieces into the empty frame to make a whole square pane. Pick a piece, turn "
		+ "it with R (or the Turn button), point at a frame square and press Enter or click to place it. The ghost "
		+ "shows where it will go. Press a placed piece to take it back out.")
	super.setup(p_services)
	name = "T08GlassPanel"


func _build_board() -> void:
	var row := HBoxContainer.new()
	row.name = "GlassRow"
	row.add_theme_constant_override(&"separation", 24)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play_area.add_child(row)
	var frame := GridContainer.new()
	frame.name = "PaneFrame"
	frame.columns = RULE.SIZE
	frame.add_theme_constant_override(&"h_separation", 2)
	frame.add_theme_constant_override(&"v_separation", 2)
	row.add_child(frame)
	for cell in RULE.SIZE * RULE.SIZE:
		var tile := make_tile("Frame%d" % cell, cell, Vector2(CELL, CELL), _paint_frame)
		tile.tooltip_text = "Frame square row %d, column %d" % [cell / RULE.SIZE + 1, cell % RULE.SIZE + 1]
		tile.pressed.connect(_on_frame_pressed.bind(cell))
		tile.focus_entered.connect(_point_at.bind(cell))
		tile.mouse_entered.connect(_point_at.bind(cell))
		tile.gui_input.connect(_on_tile_input)
		frame.add_child(tile)
		frame_tiles.append(tile)
	var side := VBoxContainer.new()
	side.name = "Tray"
	row.add_child(side)
	var tray_title := _label("TrayTitle", UiTheme.MUTED)
	tray_title.text = "Glass pieces"
	side.add_child(tray_title)
	var tray := GridContainer.new()
	tray.name = "TrayPieces"
	tray.columns = 3
	tray.add_theme_constant_override(&"h_separation", 6)
	tray.add_theme_constant_override(&"v_separation", 6)
	side.add_child(tray)
	for piece in RULE.PIECES:
		var tile := make_tile("Piece%d" % piece, piece, Vector2(128, 116), _paint_piece)
		tile.pressed.connect(_on_piece_pressed.bind(piece))
		tile.gui_input.connect(_on_tile_input)
		tray.add_child(tile)
		piece_tiles.append(tile)
	turn_button = Button.new()
	turn_button.name = "TurnPiece"
	turn_button.text = "Turn piece (R)"
	turn_button.pressed.connect(turn_selected)
	side.add_child(turn_button)


func _redraw() -> void:
	var placed: Array = puzzle_state.get("placed", [])
	if selected >= 0 and selected < placed.size() and not (placed[selected] as Array).is_empty():
		selected = _next_free(selected)
	for c: Control in frame_tiles + piece_tiles:
		c.queue_redraw()


func _status_line() -> String:
	if succeeded:
		return "The new glass pane is whole again. Great job!"
	var count := 0
	for at: Array in puzzle_state.get("placed", []):
		if not at.is_empty():
			count += 1
	return "%d of %d pieces are in the frame." % [count, RULE.PIECES]


## Gives the picked piece a quarter turn clockwise (only on screen until it is placed).
func turn_selected() -> void:
	if selected < 0:
		show_hint("Pick a piece from the tray first.")
		return
	ui_turns[selected] = (ui_turns[selected] + 1) % 4
	_redraw()


## The top-left square the picked piece would use when pointed at `cell`, pulled inside the frame.
func placement_for(cell: int) -> Vector2i:
	if selected < 0:
		return Vector2i(cell % RULE.SIZE, cell / RULE.SIZE)
	var size := RULE.extent(RULE.turned(puzzle_state.pieces[selected].cells, ui_turns[selected]))
	return Vector2i(clampi(cell % RULE.SIZE, 0, RULE.SIZE - size.x), clampi(cell / RULE.SIZE, 0, RULE.SIZE - size.y))


func _on_piece_pressed(piece: int) -> void:
	var placed: Array = puzzle_state.get("placed", [])
	if piece >= placed.size():
		return
	if not (placed[piece] as Array).is_empty():
		send_move("lift", piece)
		return
	selected = piece
	show_hint("Picked %s. Press R to turn it, then choose a frame square." % String(puzzle_state.pieces[piece].label), false)
	_redraw()
	(frame_tiles[anchor.y * RULE.SIZE + anchor.x] as Control).grab_focus()


func _on_frame_pressed(cell: int) -> void:
	_point_at(cell)
	var board: Array = puzzle_state.get("board", [])
	if selected < 0:
		if cell < board.size() and int(board[cell]) >= 0:
			send_move("lift", int(board[cell]))
		else:
			show_hint("Pick a glass piece from the tray first.")
		return
	var at := placement_for(cell)
	var problem: String = RULE.why_not(puzzle_state, selected, at.x, at.y, ui_turns[selected])
	if not problem.is_empty():
		show_hint(problem)
		return
	send_move("place", selected * 64 + ui_turns[selected] * 16 + at.y * 4 + at.x)


func _point_at(cell: int) -> void:
	anchor = Vector2i(cell % RULE.SIZE, cell / RULE.SIZE)
	for c: Control in frame_tiles:
		c.queue_redraw()


func _on_tile_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_R:
		turn_selected()
		accept_event()
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		turn_selected()
		accept_event()


func _next_free(after: int) -> int:
	var placed: Array = puzzle_state.get("placed", [])
	for i in placed.size():
		var piece := (after + 1 + i) % placed.size()
		if (placed[piece] as Array).is_empty():
			return piece
	return -1


## The ghost: squares the picked piece would cover at the anchor, and whether it fits there.
func _ghost() -> Dictionary:
	if selected < 0 or not puzzle_state.has("pieces"):
		return {}
	var at := placement_for(anchor.y * RULE.SIZE + anchor.x)
	return {"cells": RULE.covered(puzzle_state.pieces[selected].cells, at.x, at.y, ui_turns[selected]),
		"fits": String(RULE.why_not(puzzle_state, selected, at.x, at.y, ui_turns[selected])).is_empty()}


func _paint_frame(tile: Tile) -> void:
	var p := UiTheme.palette()
	var board: Array = puzzle_state.get("board", [])
	if tile.index >= board.size():
		return
	var rect := Rect2(Vector2.ZERO, tile.size).grow(-4.0)
	var owner := int(board[tile.index])
	if owner >= 0:
		tile.draw_rect(rect, TINTS[owner])
		tile.draw_line(rect.position + Vector2(6, 6), rect.position + Vector2(rect.size.x * 0.4, 6), Color(1, 1, 1, 0.8), 3.0)
		draw_text(tile, rect, String(puzzle_state.pieces[owner].letter), Color(0.05, 0.08, 0.12), 1.3)
	else:
		tile.draw_rect(rect, p.field)
		var crack := Color(p.muted, 0.5)
		tile.draw_line(rect.position + Vector2(rect.size.x * 0.2, 0), rect.get_center(), crack, 1.5)
		tile.draw_line(rect.get_center(), rect.end - Vector2(0, rect.size.y * 0.3), crack, 1.5)
	var ghost := _ghost()
	if not ghost.is_empty() and (ghost.cells as Array).has(tile.index):
		var fits := bool(ghost.fits)
		var colour: Color = TINTS[selected] if fits else p.warn
		tile.draw_rect(rect, Color(colour, 0.45))
		tile.draw_rect(rect, colour, false, 3.0)
		if fits:
			draw_text(tile, rect, String(puzzle_state.pieces[selected].letter), p.text, 1.1)
		else:
			# A cross marks "does not fit" by shape as well as colour.
			tile.draw_line(rect.position + Vector2(10, 10), rect.end - Vector2(10, 10), colour, 4.0)
			tile.draw_line(Vector2(rect.end.x - 10, rect.position.y + 10), Vector2(rect.position.x + 10, rect.end.y - 10), colour, 4.0)


func _paint_piece(tile: Tile) -> void:
	var p := UiTheme.palette()
	var pieces: Array = puzzle_state.get("pieces", [])
	var placed: Array = puzzle_state.get("placed", [])
	if tile.index >= pieces.size() or tile.index >= placed.size():
		return
	var info: Dictionary = pieces[tile.index]
	var in_frame := not (placed[tile.index] as Array).is_empty()
	var cells := RULE.turned(info.cells, ui_turns[tile.index])
	var size := RULE.extent(cells)
	var unit := minf((tile.size.x - 24.0) / 4.0, (tile.size.y - 40.0) / 4.0)
	var origin := Vector2((tile.size.x - unit * size.x) * 0.5, 8.0 + (unit * 4.0 - unit * size.y) * 0.5)
	var tint: Color = TINTS[tile.index] if not in_frame else Color(TINTS[tile.index], 0.25)
	for c: Array in cells:
		var r := Rect2(origin + Vector2(c[0], c[1]) * unit, Vector2(unit, unit)).grow(-1.0)
		tile.draw_rect(r, tint)
		tile.draw_rect(r, Color(0.05, 0.08, 0.12, 0.6), false, 1.0)
	if tile.index == selected:
		tile.draw_rect(Rect2(Vector2(4, 4), tile.size - Vector2(8, 8)), p.accent, false, 3.0)
	var text := String(info.label) if not in_frame else "%s - in frame" % String(info.letter)
	draw_text(tile, Rect2(Vector2(0, tile.size.y - 30.0), Vector2(tile.size.x, 26.0)), text, p.text if not in_frame else p.muted, 0.72)
