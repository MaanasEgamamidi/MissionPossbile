extends "res://scripts/tasks/puzzles/board_ui.gd"
## T06 "Water the Kale" mini-game (Greenhouse kale rack, broken pipe BP09; anyone can do it). UI overhaul 2026-11-15:
## the equipment is the interface. One wide apparatus in a bay: the water tank on the left, a board of chunky pipe
## tiles in the middle, the kale planter on the right. Water (cyan, with moving white droplets, so never colour alone)
## runs from the tank along the joined pipes and stops at the first break; pipes beyond are dry grey. The pipe to
## turn next carries the shared target ring and a small "turn" pictogram. The kale droops (short, yellowed) until the
## water arrives, then stands up green.
## The host rule (t06_rule.gd) decides every turn and the completion; this panel only sends "turn" moves and draws
## the host's puzzle_state. The ring is a hint read from the seeded layout (the first pipe of the seeded route that
## is out of line), never a decision.
## Controls: click / Enter / Space turns a pipe clockwise; right-click / Q turns it back; arrow keys and Tab move
## between pipes.
##
## Sprites: res://assets/ui/minigames/irrigation/. Their rotation-0 openings (measured on the PNGs):
##   pipe_straight  left + right  (the rule's straight at rotation 0 is up + down: drawn a quarter turn on)
##   pipe_elbow     left + down   (the rule's elbow at rotation 0 is up + right: drawn a half turn on)
## Each pipe is scaled so its ends sit exactly on the middle of the tile's edges, where the neighbour's end meets it.

const RULE := preload("res://scripts/tasks/puzzles/t06_rule.gd")

## Source pixels of the sprites (trim boxes and fitting centres).
const BOARD_SRC := Rect2(8, 8, 321, 329)
const ELBOW_SIZE := Vector2(307, 313)
## The corner of the elbow's centre line; both ends are ELBOW_REACH pixels from it.
const ELBOW_PIVOT := Vector2(225, 82.5)
const ELBOW_REACH := 220.0
const STRAIGHT_SIZE := Vector2(400, 170)
const STRAIGHT_PIVOT := Vector2(200, 85.5)
const STRAIGHT_LENGTH := 384.0
const TANK_SIZE := Vector2(411, 387)
## The tip of the tank's outlet (meets the first pipe tile).
const TANK_NOZZLE := Vector2(403, 270)
## The water behind the tank's glass.
const TANK_WATER := Rect2(47, 186, 261, 118)
const PLANTER_SIZE := Vector2(482, 319)
## The tip of the planter's inlet (meets the last pipe tile).
const PLANTER_INLET := Vector2(8, 228.5)
## Above this line of the planter sprite are the leaves, below it the box.
const PLANTER_SPLIT := 163.0

## Layout, in tile widths.
const TANK_HEIGHT := 1.7
const PLANTER_WIDTH := 2.1
const PLATE_PAD := 0.15
const MARGIN := 14.0
## Where the cyan starts inside a pipe end (the fittings stay metal), as a fraction of the tile.
const FITTING_STRAIGHT := 0.215
const FITTING_ELBOW := 0.165
## How far from the tile's middle the elbow's centre line cuts the corner.
const BEND := 0.09
## Tiles of water per second, seconds for a quarter turn, seconds for the kale to stand up.
const FLOW_SPEED := 6.5
const TURN_SECONDS := 0.14
const PERK_SECONDS := 0.5
const DRY_PIPE := Color(0.74, 0.76, 0.8)
const DRY_LEAF := Color(0.78, 0.68, 0.4)

## The pipe tile buttons, cell by cell (tests and tools/godot/capture_puzzles.gd press them).
var tiles: Array = []
## The apparatus (tank, pipe board, planter): one drawn control.
var board: Control
## The pipe the ring is on: the first pipe of the seeded route that is out of line (-1 when none).
var target_cell := -1

var _marks: Control
var _pitch := 0.0
var _grid_at := Vector2.ZERO
var _tank_rect := Rect2()
var _planter_rect := Rect2()
var _flow := 0.0
var _perk := 0.0
var _spin := PackedFloat32Array()
var _shown_water: Array = []
var _shown_rot: Array = []
var _prev_wet := 0
var _prev_target := -1
var _hint_seed := -1
var _hint_layout: Dictionary = {}


func setup(p_services: GameServices) -> void:
	rule = RULE
	task_title = "Water the Kale"
	instructions = ("The kale is thirsty. Turn the pipes until water runs from the tank to the kale. "
		+ "Click a pipe (or press Enter) to turn it; right-click or Q turns it back. Arrow keys move between pipes.")
	super.setup(p_services)
	name = "T06WaterPanel"
	set_cue("Turn the pipes [Enter]")


func _build_board() -> void:
	board = Paint.new()
	board.name = "PipeBoard"
	board.custom_minimum_size = Vector2(900, 420)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(board as Paint).painter = _paint_equipment
	Kit.smooth(board)
	play_area.add_child(board)
	var count: int = RULE.COLS * RULE.ROWS
	_spin.resize(count)
	_spin.fill(0.0)
	for cell in count:
		var col: int = cell % RULE.COLS
		var row: int = cell / RULE.COLS
		var tile := make_tile("Pipe%d" % cell, cell, Vector2.ZERO, _paint_pipe)
		tile.flat = true
		tile.tooltip_text = "Pipe, row %d, column %d" % [row + 1, col + 1]
		tile.pressed.connect(_turn.bind(cell, 1))
		tile.gui_input.connect(_on_tile_input.bind(cell))
		if col > 0:
			tile.focus_neighbor_left = NodePath("../Pipe%d" % (cell - 1))
		if col < RULE.COLS - 1:
			tile.focus_neighbor_right = NodePath("../Pipe%d" % (cell + 1))
		if row > 0:
			tile.focus_neighbor_top = NodePath("../Pipe%d" % (cell - RULE.COLS))
		if row < RULE.ROWS - 1:
			tile.focus_neighbor_bottom = NodePath("../Pipe%d" % (cell + RULE.COLS))
		board.add_child(tile)
		tiles.append(tile)
	# The shared marks (target ring, focus ring, tick) are drawn over every tile.
	_marks = Paint.new()
	_marks.name = "Marks"
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(_marks as Paint).painter = _paint_marks
	board.add_child(_marks)
	board.resized.connect(_place)


## The keyboard starts on the pipe to turn.
func first_focus() -> Control:
	if not pending and not succeeded and target_cell >= 0 and target_cell < tiles.size():
		return tiles[target_cell]
	return super.first_focus()


## True once the water has reached the planter (the kale stands up).
func kale_watered() -> bool:
	var water := _water()
	return not water.is_empty() and _flow >= float(water.size()) - 0.01 and RULE.is_complete(
		puzzle_state.get("kinds", []), puzzle_state.get("rot", []), int(puzzle_state.get("supply_row", 0)),
		int(puzzle_state.get("rack_row", 0)))


func _redraw() -> void:
	var water := _water()
	var rots: Array = puzzle_state.get("rot", [])
	var less := wants_less_motion()
	# Water that was already there stays; the new stretch runs in from where the old one ended.
	var keep := 0
	while keep < water.size() and keep < _shown_water.size() and int(water[keep]) == int(_shown_water[keep]):
		keep += 1
	_flow = float(water.size()) if less else minf(_flow, float(keep))
	# A pipe that was just turned swings from where it was.
	if not less and _shown_rot.size() == rots.size():
		for cell in mini(rots.size(), _spin.size()):
			var turned := posmod(int(rots[cell]) - int(_shown_rot[cell]), 4)
			if turned == 1:
				_spin[cell] -= PI * 0.5
			elif turned == 3:
				_spin[cell] += PI * 0.5
	_prev_wet = _shown_water.size()
	_prev_target = target_cell
	_shown_water = water.duplicate()
	_shown_rot = rots.duplicate()
	target_cell = _find_target()
	if less:
		_perk = 1.0 if kale_watered() else 0.0
	_place()
	_repaint()


## The feedback line after the host accepted a move (shown in the shell's cue bar).
func _status_line() -> String:
	var wet := _shown_water.size()
	if succeeded:
		_say("The kale has water!", &"good")
	elif String(_last_move.get("move", "")) == "reset":
		_say("Back to the start.", &"")
	elif wet > _prev_wet:
		_say("Water is flowing!", &"good")
	elif wet < _prev_wet:
		_say("Oops! The water stopped.", &"warn")
	elif int(_last_move.get("payload", -4)) / 4 == _prev_target:
		_say("Nearly! Turn it again.", &"")
	else:
		_say("Try the glowing pipe.", &"")
	return ""


func _say(text: String, kind: StringName) -> void:
	hint_label.text = text
	status_label.text = text
	status_label.theme_type_variation = UiTheme.GOOD if kind == &"good" else (UiTheme.WARN if kind == &"warn" else &"")
	flash(text, kind)


func _process(delta: float) -> void:
	super._process(delta)
	if board == null or not board.is_visible_in_tree():
		return
	var less := wants_less_motion()
	var wet := float(_water().size())
	_flow = wet if less else minf(wet, _flow + delta * FLOW_SPEED)
	for cell in _spin.size():
		_spin[cell] = 0.0 if less else move_toward(_spin[cell], 0.0, delta * PI * 0.5 / TURN_SECONDS)
	var perked := 1.0 if kale_watered() else 0.0
	_perk = perked if less else move_toward(_perk, perked, delta / PERK_SECONDS)
	_repaint()


func _repaint() -> void:
	if board == null:
		return
	board.queue_redraw()
	_marks.queue_redraw()
	for tile: Control in tiles:
		tile.queue_redraw()


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


func _water() -> Array:
	return puzzle_state.get("water", [])


## The hint: the first pipe of the seeded route that does not sit as in the seeded solution.
func _find_target() -> int:
	var kinds: Array = puzzle_state.get("kinds", [])
	var rots: Array = puzzle_state.get("rot", [])
	if kinds.is_empty() or rots.size() != kinds.size():
		return -1
	var seed_value := int(puzzle_state.get("seed", 0))
	if seed_value != _hint_seed or _hint_layout.is_empty():
		_hint_seed = seed_value
		_hint_layout = RULE.layout(seed_value)
	var solution: Array = _hint_layout.solution
	for cell: int in _hint_layout.route:
		if cell >= kinds.size():
			return -1
		var kind := int(kinds[cell])
		if RULE.mask_of(kind, int(rots[cell])) != RULE.mask_of(kind, int(solution[cell])):
			return cell
	return -1


# ---------------------------------------------------------------- layout

## Places the tank, the tiles and the planter inside the bay: the tank's outlet sits on the supply row, the
## planter's inlet on the rack row, and the tile is as large as the bay allows.
func _place() -> void:
	if board == null or board.size.x <= 0.0 or board.size.y <= 0.0:
		return
	var area := Rect2(Vector2.ZERO, board.size).grow(-MARGIN)
	var supply := float(int(puzzle_state.get("supply_row", 0))) + 0.5
	var rack := float(int(puzzle_state.get("rack_row", 0))) + 0.5
	var tank_k := TANK_HEIGHT / TANK_SIZE.y
	var planter_k := PLANTER_WIDTH / PLANTER_SIZE.x
	var top := maxf(PLATE_PAD, maxf(TANK_NOZZLE.y * tank_k - supply, PLANTER_INLET.y * planter_k - rack))
	var bottom := maxf(PLATE_PAD, maxf(supply + (TANK_SIZE.y - TANK_NOZZLE.y) * tank_k,
		rack + (PLANTER_SIZE.y - PLANTER_INLET.y) * planter_k) + 0.1 - float(RULE.ROWS))
	var left := TANK_NOZZLE.x * tank_k
	var right := (PLANTER_SIZE.x - PLANTER_INLET.x) * planter_k
	var units := Vector2(left + float(RULE.COLS) + right, top + float(RULE.ROWS) + bottom)
	_pitch = floorf(minf(area.size.x / units.x, area.size.y / units.y))
	if _pitch <= 0.0:
		return
	_grid_at = (area.position + (area.size - units * _pitch) * 0.5 + Vector2(left, top) * _pitch).round()
	_tank_rect = Rect2(_grid_at + Vector2(0.0, supply * _pitch) - TANK_NOZZLE * tank_k * _pitch, TANK_SIZE * tank_k * _pitch)
	_planter_rect = Rect2(_grid_at + Vector2(float(RULE.COLS), rack) * _pitch - PLANTER_INLET * planter_k * _pitch,
		PLANTER_SIZE * planter_k * _pitch)
	for cell in tiles.size():
		var tile: Control = tiles[cell]
		tile.position = _cell_rect(cell).position
		tile.size = Vector2(_pitch, _pitch)


func _cell_rect(cell: int) -> Rect2:
	return Rect2(_grid_at + Vector2(cell % RULE.COLS, cell / RULE.COLS) * _pitch, Vector2(_pitch, _pitch))


# ---------------------------------------------------------------- drawing

func _paint_equipment(c: Control) -> void:
	Kit.bay(c, Rect2(Vector2.ZERO, c.size))
	if _pitch <= 0.0:
		return
	var p := _pitch
	_draw_mount(c, _tank_rect, TANK_SIZE, 16.0, 343.0, 379.0)
	_draw_mount(c, _planter_rect, PLANTER_SIZE, 56.0, 474.0, 311.0)
	var plate := Rect2(_grid_at, Vector2(RULE.COLS, RULE.ROWS) * p).grow(PLATE_PAD * p)
	Kit.housing(c, plate, 16.0, false)
	var inset := PLATE_PAD * p * 0.5
	for corner: Vector2 in [Vector2(inset, inset), Vector2(plate.size.x - inset, inset),
			Vector2(inset, plate.size.y - inset - 3.0), Vector2(plate.size.x - inset, plate.size.y - inset - 3.0)]:
		Kit.screw(c, plate.position + corner, clampf(inset * 0.5, 2.5, 5.0))
	_draw_tank(c)
	_draw_planter(c)


## A wall rail and a small shelf, so the tank and the planter hang at the height of their pipe.
func _draw_mount(c: Control, rect: Rect2, source: Vector2, body_from: float, body_to: float, foot: float) -> void:
	var k := rect.size.x / source.x
	var from := rect.position.x + body_from * k
	var to := rect.position.x + body_to * k
	var rail_w := _pitch * 0.16
	Kit.box(c, Rect2((from + to) * 0.5 - rail_w * 0.5, MARGIN + 4.0, rail_w, c.size.y - (MARGIN + 4.0) * 2.0), Kit.BAY_EDGE, 6.0,
		Kit.BAY_LIP, 2.0)
	var shelf := Rect2(from - _pitch * 0.05, rect.position.y + foot * k - 2.0, to - from + _pitch * 0.1, _pitch * 0.09)
	Kit.box(c, shelf, Kit.METAL_DARK, 5.0, Kit.METAL, 2.0)


func _draw_tank(c: Control) -> void:
	var t := Kit.tex("irrigation/header_tank")
	if t == null:
		return
	var k := _tank_rect.size.x / TANK_SIZE.x
	c.draw_texture_rect(t, _tank_rect, false)
	var glass := Rect2(_tank_rect.position + TANK_WATER.position * k, TANK_WATER.size * k)
	var time := 0.0 if wants_less_motion() else float(Time.get_ticks_msec()) * 0.001
	c.draw_rect(glass, Color(Kit.WATER, 0.3))
	# The water line: a bright ripple along the surface.
	var line := PackedVector2Array()
	for i in 15:
		line.append(Vector2(glass.position.x + glass.size.x * float(i) / 14.0,
			glass.position.y + sin(float(i) * 1.2 + time * 2.6) * 3.0 * k))
	c.draw_polyline(line, Color(0.88, 0.98, 1.0, 0.9), maxf(2.0, 5.0 * k), true)
	for i in 5:
		var rise := fposmod(time * (0.16 + 0.05 * float(i)) + 0.23 * float(i) + 0.1, 1.0)
		var at := Vector2(glass.position.x + glass.size.x * (0.14 + 0.18 * float(i)),
			glass.end.y - 10.0 * k - rise * (glass.size.y - 30.0 * k))
		c.draw_arc(at, (5.0 + 2.5 * float(i % 3)) * k, 0.0, TAU, 16, Color(1, 1, 1, 0.85 - 0.5 * rise), maxf(1.5, 2.4 * k), true)


## The planter: the box as it is, the leaves short and yellowed while dry, tall and green once watered.
func _draw_planter(c: Control) -> void:
	var t := Kit.tex("irrigation/kale_planter")
	if t == null:
		return
	var r := _planter_rect
	var k := r.size.x / PLANTER_SIZE.x
	var split_y := r.position.y + PLANTER_SPLIT * k
	c.draw_texture_rect_region(t, Rect2(r.position.x, split_y, r.size.x, r.size.y - PLANTER_SPLIT * k),
		Rect2(0.0, PLANTER_SPLIT, PLANTER_SIZE.x, PLANTER_SIZE.y - PLANTER_SPLIT))
	var tall := lerpf(0.62, 1.0, _perk) + 0.08 * sin(_perk * PI)
	var height := (PLANTER_SPLIT + 1.0) * k * tall
	c.draw_texture_rect_region(t, Rect2(r.position.x, split_y + k - height, r.size.x, height),
		Rect2(0.0, 0.0, PLANTER_SIZE.x, PLANTER_SPLIT + 1.0), DRY_LEAF.lerp(Color.WHITE, _perk))


func _paint_pipe(tile: Tile) -> void:
	var size := tile.size
	Kit.draw_fill(tile, Kit.tex("irrigation/pipe_board"), Rect2(Vector2.ZERO, size))
	var kinds: Array = puzzle_state.get("kinds", [])
	var rots: Array = puzzle_state.get("rot", [])
	if tile.index < 0 or tile.index >= kinds.size() or tile.index >= rots.size():
		return
	var p := size.x
	var centre := size * 0.5
	var kind := int(kinds[tile.index])
	var rot := int(rots[tile.index])
	var spin: float = _spin[tile.index] if tile.index < _spin.size() else 0.0
	var order := _water().find(tile.index)
	var fill := clampf(_flow - float(order), 0.0, 1.0) if order >= 0 else 0.0
	var tint := Color.WHITE if fill > 0.0 else DRY_PIPE
	var k := p * 0.5 / ELBOW_REACH
	if kind == RULE.ELBOW:
		Kit.draw_turned(tile, Kit.tex("irrigation/pipe_elbow"), centre, ELBOW_SIZE * k, PI + float(rot) * PI * 0.5 + spin, tint,
			ELBOW_PIVOT / ELBOW_SIZE)
	else:
		Kit.draw_turned(tile, Kit.tex("irrigation/pipe_straight"), centre,
			Vector2(STRAIGHT_SIZE.x * p / STRAIGHT_LENGTH, STRAIGHT_SIZE.y * k), PI * 0.5 + float(rot) * PI * 0.5 + spin, tint,
			STRAIGHT_PIVOT / STRAIGHT_SIZE)
	if fill <= 0.0:
		return
	tile.draw_set_transform(centre, spin, Vector2.ONE)
	_draw_water(tile, _water_path(tile.index, order, kind, rot, p), fill, p,
		(FITTING_ELBOW if kind == RULE.ELBOW else FITTING_STRAIGHT) * p)
	tile.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The centre line of a wet pipe from the side the water comes in to the side it leaves, relative to the tile's
## middle. `order` is the pipe's place in the flow (the water enters the first one from the tank, on the left).
func _water_path(cell: int, order: int, kind: int, rot: int, p: float) -> PackedVector2Array:
	var water := _water()
	var mask: int = RULE.mask_of(kind, rot)
	var entry := 3
	if order > 0:
		var before := int(water[order - 1])
		var step := Vector2i(before % RULE.COLS - cell % RULE.COLS, before / RULE.COLS - cell / RULE.COLS)
		entry = maxi(0, RULE.OFFSETS.find(step))
	var exit := entry
	for d in 4:
		if d != entry and mask & (1 << d) != 0:
			exit = d
	var a := Vector2(RULE.OFFSETS[entry])
	var b := Vector2(RULE.OFFSETS[exit])
	if kind == RULE.ELBOW:
		return PackedVector2Array([a * p * 0.5, a * p * BEND, b * p * BEND, b * p * 0.5])
	return PackedVector2Array([a * p * 0.5, b * p * 0.5])


## Water inside a pipe: a cyan stretch between the two fittings, filled as far as `fill` (0..1) of the way, with
## white droplets running along it (shape and motion, not colour alone).
func _draw_water(c: Control, path: PackedVector2Array, fill: float, p: float, fitting: float) -> void:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	var from := fitting
	var to := minf(fill * total, total - fitting)
	if to <= from:
		return
	var stretch := _slice(path, from, to)
	_stroke(c, stretch, p * 0.19, Color(0.03, 0.2, 0.3))
	_stroke(c, stretch, p * 0.145, Kit.WATER)
	_stroke(c, stretch, p * 0.035, Color(0.85, 0.98, 1.0, 0.45))
	var phase := 0.3 if wants_less_motion() else fposmod(float(Time.get_ticks_msec()) * 0.001 * 0.9, 1.0)
	var r := p * 0.032
	for n in 2:
		var at := fposmod(phase + 0.5 * float(n), 1.0) * total
		if at > from + r and at < to - r:
			var drop := _slice(path, at, at)
			c.draw_circle(drop[0], r, Color(1, 1, 1, 0.95))


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


## A thick line along a polyline with flat ends and round corners.
static func _stroke(c: Control, path: PackedVector2Array, width: float, color: Color) -> void:
	for i in range(1, path.size()):
		c.draw_line(path[i - 1], path[i], color, width, true)
		if i < path.size() - 1:
			c.draw_circle(path[i], width * 0.5, color)


## The shared marks, over every tile: the hover outline, the target ring with its "turn" pictogram, the focus ring,
## and the planter's badge (an empty drop while the kale is dry, the tick once it has water).
func _paint_marks(c: Control) -> void:
	if _pitch <= 0.0:
		return
	var p := _pitch
	var less := wants_less_motion()
	for cell in tiles.size():
		var tile: Button = tiles[cell]
		if tile.is_hovered() and not tile.disabled and not tile.has_focus():
			Kit.box(c, _cell_rect(cell).grow(-4.0), Color(1, 1, 1, 0.05), 12.0, Color(1, 1, 1, 0.55), 2.0)
	if target_cell >= 0 and target_cell < tiles.size() and not succeeded:
		var rect := _cell_rect(target_cell).grow(-5.0)
		Kit.target_ring(c, rect, 12.0, less)
		var at := Vector2(rect.end.x - p * 0.19, rect.position.y + p * 0.19)
		c.draw_circle(at, p * 0.15, Color(Kit.INK, 0.85))
		Kit.turn_arrows(c, at, p * 0.085, UiTheme.palette().focus)
	for cell in tiles.size():
		if (tiles[cell] as Control).has_focus():
			Kit.focus_ring(c, _cell_rect(cell).grow(-6.0), 12.0, 4.0)
	var k := _planter_rect.size.x / PLANTER_SIZE.x
	var badge := _planter_rect.position + Vector2(265.0, 248.0) * k
	var r := p * 0.15
	if _perk >= 1.0:
		Kit.tick(c, badge, r)
	else:
		c.draw_circle(badge, r, Color(Kit.INK, 0.85))
		var drop := PackedVector2Array([badge + Vector2(0.0, -r * 0.62)])
		for i in 13:
			drop.append(badge + Vector2(0.0, r * 0.14) + Vector2.from_angle(-PI * 0.18 + float(i) / 12.0 * PI * 1.36) * r * 0.42)
		drop.append(drop[0])
		c.draw_polyline(drop, Kit.WATER, maxf(2.0, r * 0.14), true)
