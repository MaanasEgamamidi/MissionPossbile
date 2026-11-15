extends "res://scripts/tasks/puzzles/board_ui.gd"
## T06 Water mini-game (Greenhouse kale rack, broken pipe BP09): turn the straight and elbow pipe pieces until water
## flows from the supply tank to the rack. The host rule (t06_rule.gd) decides every turn and the completion; this
## panel only sends "turn" moves and draws the host's puzzle_state.
## Controls: click / Enter / Space turns the focused pipe clockwise; right-click / Q turns it back; arrow keys and
## Tab move between pipes. Water is drawn blue with white droplets (not colour alone), and the hint line counts it.

const RULE := preload("res://scripts/tasks/puzzles/t06_rule.gd")
const TILE := 72.0
const FLOW_SECONDS := 0.07

var tiles: Array = []
var board: GridContainer
var _supply_marks: Array = []
var _rack_marks: Array = []
var _flow_shown := 0
var _flow_clock := 0.0


func setup(p_services: GameServices) -> void:
	rule = RULE
	task_title = "Fix the broken pipe"
	instructions = ("Water must flow from the supply tank on the left to the kale rack on the right. Turn the pipe "
		+ "pieces until they join up. Click, Enter or Space turns a pipe clockwise; right-click or Q turns it back. "
		+ "Arrow keys move between pipes.")
	super.setup(p_services)
	name = "T06WaterPanel"


func _build_board() -> void:
	board = GridContainer.new()
	board.name = "PipeBoard"
	board.columns = RULE.COLS + 2
	board.add_theme_constant_override(&"h_separation", 2)
	board.add_theme_constant_override(&"v_separation", 2)
	board.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play_area.add_child(board)
	for row in RULE.ROWS:
		var supply := Paint.new()
		supply.name = "Supply%d" % row
		supply.custom_minimum_size = Vector2(TILE * 1.3, TILE)
		supply.painter = _paint_supply.bind(row)
		board.add_child(supply)
		_supply_marks.append(supply)
		for col in RULE.COLS:
			var cell: int = row * RULE.COLS + col
			var tile := make_tile("Pipe%d" % cell, cell, Vector2(TILE, TILE), _paint_pipe)
			tile.tooltip_text = "Pipe row %d, column %d" % [row + 1, col + 1]
			tile.pressed.connect(_turn.bind(cell, 1))
			tile.gui_input.connect(_on_tile_input.bind(cell))
			board.add_child(tile)
			tiles.append(tile)
		var rack := Paint.new()
		rack.name = "Rack%d" % row
		rack.custom_minimum_size = Vector2(TILE * 1.3, TILE)
		rack.painter = _paint_rack.bind(row)
		board.add_child(rack)
		_rack_marks.append(rack)


func _redraw() -> void:
	var water: Array = puzzle_state.get("water", [])
	_flow_shown = water.size() if reduce_motion() else mini(_flow_shown, water.size())
	_flow_clock = 0.0
	for c: Control in tiles + _supply_marks + _rack_marks:
		c.queue_redraw()


func _status_line() -> String:
	if succeeded:
		return "Water is flowing to the kale rack. Great job!"
	var water: Array = puzzle_state.get("water", [])
	if water.is_empty():
		return "No water yet: the first pipe must open toward the supply tank."
	return "Water reaches %d pipe%s. Keep joining pipes toward the rack." % [water.size(), "" if water.size() == 1 else "s"]


func _process(delta: float) -> void:
	super._process(delta)
	var water: Array = puzzle_state.get("water", [])
	if _flow_shown < water.size():
		_flow_clock += delta
		if _flow_clock >= FLOW_SECONDS:
			_flow_clock = 0.0
			_flow_shown += 1
			for c: Control in tiles + _rack_marks:
				c.queue_redraw()


## Turns one pipe a quarter turn (direction 1 clockwise, -1 back).
func _turn(cell: int, direction: int) -> void:
	var rots: Array = puzzle_state.get("rot", [])
	if cell < 0 or cell >= rots.size():
		return
	send_move("turn", cell * 4 + posmod(int(rots[cell]) + direction, 4))


func _on_tile_input(event: InputEvent, cell: int) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_Q:
		_turn(cell, -1)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_turn(cell, -1)
		accept_event()


func _is_wet(cell: int) -> bool:
	var water: Array = puzzle_state.get("water", [])
	var at := water.find(cell)
	return at >= 0 and at < _flow_shown


func _paint_pipe(tile: Tile) -> void:
	var p := UiTheme.palette()
	var kinds: Array = puzzle_state.get("kinds", [])
	var rots: Array = puzzle_state.get("rot", [])
	if tile.index >= kinds.size():
		return
	var rect := Rect2(Vector2.ZERO, tile.size).grow(-5.0)
	tile.draw_rect(rect, p.field)
	var wet := _is_wet(tile.index)
	var mask: int = RULE.mask_of(int(kinds[tile.index]), int(rots[tile.index]))
	var centre := tile.size * 0.5
	var width := tile.size.x * 0.24
	var colour: Color = p.cool if wet else Color(0.55, 0.6, 0.66)
	var edge: Color = p.border
	for d in 4:
		if mask & (1 << d) == 0:
			continue
		var to := centre + Vector2(RULE.OFFSETS[d]) * tile.size.x * 0.5
		tile.draw_line(centre, to, edge, width + 4.0)
	tile.draw_circle(centre, width * 0.5 + 2.0, edge)
	for d in 4:
		if mask & (1 << d) == 0:
			continue
		var to := centre + Vector2(RULE.OFFSETS[d]) * tile.size.x * 0.5
		tile.draw_line(centre, to, colour, width)
		if wet:
			# Droplets: water is shown by shape too, not by colour alone.
			tile.draw_circle(centre.lerp(to, 0.55), width * 0.18, Color(1, 1, 1, 0.95))
	tile.draw_circle(centre, width * 0.5, colour)
	if wet:
		tile.draw_circle(centre, width * 0.18, Color(1, 1, 1, 0.95))


func _paint_supply(c: Control, row: int) -> void:
	if row != int(puzzle_state.get("supply_row", -1)):
		return
	var p := UiTheme.palette()
	var tank := Rect2(Vector2(4, 8), Vector2(c.size.x * 0.62, c.size.y - 16))
	c.draw_rect(tank, p.card)
	c.draw_rect(tank, p.cool, false, 2.0)
	c.draw_rect(Rect2(tank.position + Vector2(3, tank.size.y * 0.45), Vector2(tank.size.x - 6, tank.size.y * 0.55 - 3)), p.cool)
	c.draw_line(Vector2(tank.end.x, c.size.y * 0.5), Vector2(c.size.x, c.size.y * 0.5), p.cool, c.size.y * 0.24)
	draw_text(c, Rect2(tank.position, Vector2(tank.size.x, tank.size.y * 0.45)), "Tank", p.text, 0.75)


func _paint_rack(c: Control, row: int) -> void:
	if row != int(puzzle_state.get("rack_row", -1)):
		return
	var p := UiTheme.palette()
	var water: Array = puzzle_state.get("water", [])
	var rack_cell: int = row * RULE.COLS + RULE.COLS - 1
	var flowing := succeeded and water.find(rack_cell) < _flow_shown
	var bed := Rect2(Vector2(c.size.x * 0.3, c.size.y * 0.5), Vector2(c.size.x * 0.66, c.size.y * 0.42))
	c.draw_line(Vector2(0, c.size.y * 0.5), Vector2(bed.position.x + 4, c.size.y * 0.5), p.cool if flowing else Color(0.55, 0.6, 0.66), c.size.y * 0.24)
	c.draw_rect(bed, Color(0.42, 0.3, 0.2))
	var leaf: Color = p.good if flowing else Color(0.72, 0.62, 0.3)
	for i in 3:
		var at := Vector2(bed.position.x + bed.size.x * (0.2 + 0.3 * i), bed.position.y - 6.0)
		c.draw_circle(at, 9.0 if flowing else 6.0, leaf)
	draw_text(c, Rect2(Vector2(bed.position.x - 8, 0), Vector2(bed.size.x + 12, c.size.y * 0.3)), "Kale" if flowing else "Dry", p.text, 0.75)
