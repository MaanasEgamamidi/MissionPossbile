extends "res://scripts/tasks/puzzles/board_ui.gd"
## T11 "Clear the Landing Lines" (Hangar, BP10, anyone): the hangar floor seen from above is the board. Six concrete
## patches (the rule's six areas, back row on top) with the yellow landing stripe painted across them, buried under
## Mars dust: clumps (dust_heavy) where the dust is thick, powder (dust_light) where it is loose. Every stroke thins
## the dust on that patch, so the stripe shows through more and more; a clean patch shows a sharp stripe and a tick.
## A recessed rack on the left edge holds the two tools as pictures: the brush and the vacuum nozzle.
## The host rule (t11_rule.gd) checks every stroke and decides completion; this panel only sends "brush" / "vacuum"
## moves and draws the host's puzzle_state. Thick and loose dust differ by shape (clumps or powder), not by colour.
## Controls: pick a tool (click it, or B = brush, V = vacuum), then click a patch, or move to it with the arrow keys /
## Tab and press Enter / Space, for one stroke.

const RULE := preload("res://scripts/tasks/puzzles/t11_rule.gd")
const SET := "hangar/"
const DUST := Color(0.72, 0.37, 0.2)
## Tints for the two dust sprites (the pack's powder is pale: this makes it Mars dust on the grey floor).
const POWDER := Color(0.82, 0.5, 0.33)
const CLUMP := Color(1.0, 0.84, 0.74)
const COLS := 3
const LIGHT_COUNT := 8
const HEAVY_COUNT := 6
## Seconds the tool takes to sweep over a patch after the host accepted a stroke.
const SWEEP_SECONDS := 0.5
## Seconds the amber "not with this tool" mark stays on a patch.
const NOPE_SECONDS := 1.0
## Seconds the other tool pulses in the rack after a stroke with the wrong tool.
const SUGGEST_SECONDS := 3.0
const LINE_CLEAR := "The landing lines are clear!"
const LINE_BRUSH_FIRST := "Brush the clumps first."
const LINE_ALREADY_CLEAN := "Already clean. Try a dusty patch."

var area_tiles: Array = []
var brush_button: Button
var vacuum_button: Button
## "brush" or "vacuum".
var current_tool := "brush"
## The whole apparatus: housing, tool rack and floor bay (the patches and the tools are its children).
var board: Paint
## Drawn over the floor: the shared marks (rings, ticks) and the tool in hand.
var marks: Paint

var _rack := Rect2()
var _bay := Rect2()
var _slots: Array[Rect2] = []
var _patches: Array[Rect2] = []
## Dust drawn on each patch right now (eases towards the host's level).
var _shown: Array[float] = []
## The host's levels the panel saw last (to tell which patch a stroke changed).
var _seen: Array[float] = []
var _hover := -1
var _sweep_area := -1
var _sweep_tool := ""
var _sweep_time := 0.0
var _nope_area := -1
var _nope_time := 0.0
var _nudge_tool := ""
var _nudge_time := 0.0
var _standing_tool := ""
var _clear_style: StyleBoxFlat


func setup(p_services: GameServices) -> void:
	rule = RULE
	task_title = "Clear the Landing Lines"
	instructions = ("Mars dust hides the landing lines on the hangar floor. Use the brush to break up the clumps, "
		+ "then the vacuum to suck up the loose dust. Clean every patch of the floor.")
	super.setup(p_services)
	name = "T11DustPanel"


func _build_board() -> void:
	board = Paint.new()
	board.name = "HangarFloor"
	board.custom_minimum_size = Vector2(900, 420)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.painter = _paint_board
	Kit.smooth(board)
	play_area.add_child(board)
	for i in RULE.AREAS.size():
		var tile := make_tile("Area%d" % i, i, Vector2.ZERO, _paint_patch)
		tile.tooltip_text = String(RULE.AREAS[i].name)
		tile.clip_contents = true
		_plain(tile)
		tile.pressed.connect(_stroke.bind(i))
		tile.gui_input.connect(_on_key_input)
		tile.mouse_entered.connect(_on_hover.bind(i, true))
		tile.mouse_exited.connect(_on_hover.bind(i, false))
		board.add_child(tile)
		area_tiles.append(tile)
		_shown.append(0.0)
		_seen.append(-1.0)
	brush_button = _tool_button("ToolBrush", "Brush (B)", "brush")
	vacuum_button = _tool_button("ToolVacuum", "Vacuum (V)", "vacuum")
	marks = Paint.new()
	marks.name = "Marks"
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.painter = _paint_marks
	board.add_child(marks)
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Arrow keys: across the floor, and from its left column into the rack.
	var rows := RULE.AREAS.size() / COLS
	for i in area_tiles.size():
		var tile: Control = area_tiles[i]
		var col := i % COLS
		var row := i / COLS
		tile.focus_neighbor_left = _beside(area_tiles[i - 1] if col > 0 else (brush_button if row == 0 else vacuum_button))
		tile.focus_neighbor_right = _beside(area_tiles[i + 1] if col < COLS - 1 else tile)
		tile.focus_neighbor_top = _beside(area_tiles[i - COLS] if row > 0 else tile)
		tile.focus_neighbor_bottom = _beside(area_tiles[i + COLS] if row < rows - 1 else tile)
	brush_button.focus_neighbor_right = _beside(area_tiles[0])
	brush_button.focus_neighbor_bottom = _beside(vacuum_button)
	brush_button.focus_neighbor_top = _beside(brush_button)
	brush_button.focus_neighbor_left = _beside(brush_button)
	vacuum_button.focus_neighbor_right = _beside(area_tiles[(rows - 1) * COLS])
	vacuum_button.focus_neighbor_top = _beside(brush_button)
	vacuum_button.focus_neighbor_bottom = _beside(vacuum_button)
	vacuum_button.focus_neighbor_left = _beside(vacuum_button)
	board.resized.connect(_layout)
	_layout()
	_update_cue()


func _beside(control: Control) -> NodePath:
	return NodePath("../" + String(control.name))


## A tool in the rack: an invisible button over its picture (the board draws the picture, the marks its ring).
func _tool_button(node_name: String, tip: String, tool_id: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_ALL
	_plain(button)
	button.pressed.connect(set_tool.bind(tool_id))
	button.gui_input.connect(_on_key_input)
	board.add_child(button)
	return button


## The buttons draw nothing themselves: the equipment under them is the picture, and the kit's focus ring (drawn by
## the marks layer) is their focus style.
func _plain(button: Button) -> void:
	if _clear_style == null:
		_clear_style = StyleBoxFlat.new()
		_clear_style.draw_center = false
		_clear_style.set_border_width_all(0)
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]:
		button.add_theme_stylebox_override(state, _clear_style)


## Places the rack, the floor bay, the tool slots and the patches inside the board's current size.
func _layout() -> void:
	var size := board.size
	if size.x < 40.0 or size.y < 40.0:
		return
	var pad := clampf(size.y * 0.035, 10.0, 18.0)
	var rack_w := clampf(size.x * 0.125, 104.0, 150.0)
	_rack = Rect2(pad, pad, rack_w, size.y - pad * 2.0 - 5.0)
	_bay = Rect2(_rack.end.x + pad, pad, size.x - _rack.end.x - pad * 2.0, size.y - pad * 2.0 - 5.0)
	var slot_w := rack_w - 22.0
	var slot_gap := 12.0
	var slot_h := minf((_rack.size.y - 22.0 - slot_gap) * 0.5, slot_w * 1.55)
	var top := _rack.get_center().y - slot_h - slot_gap * 0.5
	_slots = [Rect2(_rack.position.x + 11.0, top, slot_w, slot_h),
		Rect2(_rack.position.x + 11.0, top + slot_h + slot_gap, slot_w, slot_h)]
	var floor_rect := _bay.grow(-10.0)
	var gap := 8.0
	var rows := RULE.AREAS.size() / COLS
	var patch := Vector2((floor_rect.size.x - gap * float(COLS - 1)) / float(COLS), (floor_rect.size.y - gap * float(rows - 1)) / float(rows))
	_patches = []
	for i in area_tiles.size():
		var at := floor_rect.position + Vector2(float(i % COLS) * (patch.x + gap), float(i / COLS) * (patch.y + gap))
		_patches.append(Rect2(at, patch))
		(area_tiles[i] as Control).position = at
		(area_tiles[i] as Control).size = patch
	brush_button.position = _slots[0].position
	brush_button.size = _slots[0].size
	vacuum_button.position = _slots[1].position
	vacuum_button.size = _slots[1].size
	_redraw_all()


func _redraw_all() -> void:
	if board == null:
		return
	board.queue_redraw()
	marks.queue_redraw()
	for c: Control in area_tiles:
		c.queue_redraw()


## Chooses the cleaning tool ("brush" or "vacuum").
func set_tool(tool_id: String) -> void:
	if tool_id != "brush" and tool_id != "vacuum":
		return
	current_tool = tool_id
	if _nudge_tool == tool_id:
		_nudge_tool = ""
	_update_cue()
	_redraw_all()


## The tool the rack is pointing the player to right now ("" when the tool in hand is the right one).
func suggested_tool() -> String:
	if succeeded:
		return ""
	if not _nudge_tool.is_empty() and _nudge_tool != current_tool:
		return _nudge_tool
	return _standing_tool


## Dust drawn on a patch right now, 0.0 (clean, sharp stripe) .. 1.0 (buried).
func shown_dust(area: int) -> float:
	return _shown[area] if area >= 0 and area < _shown.size() else 0.0


func _level(area: int) -> float:
	return float((puzzle_state.get("areas", {}) as Dictionary).get(RULE.AREAS[area].id, 0.0))


## True for the patches the tool in hand is meant for: clumps for the brush, loose dust for the vacuum.
func _wants(area: int) -> bool:
	var level := _level(area)
	return level > 0.5 if current_tool == "brush" else (level > 0.0 and level <= 0.5)


func _redraw() -> void:
	if board == null:
		return
	var less := wants_less_motion()
	for i in area_tiles.size():
		var level := _level(i)
		if _seen[i] < 0.0 or less:
			_shown[i] = level
		elif level < _seen[i] and not less:
			# The host took dust off this patch: run the tool over it (a quarter = the brush, a half = the vacuum).
			_sweep_area = i
			_sweep_tool = "brush" if _seen[i] - level < 0.4 else "vacuum"
			_sweep_time = SWEEP_SECONDS
		_seen[i] = level
	_update_cue()
	_redraw_all()


## The one standing line, following the tool in hand; when that tool has nothing left to do, the other one pulses.
func _update_cue() -> void:
	_standing_tool = ""
	if succeeded:
		set_cue(LINE_CLEAR)
		return
	var thick := 0
	var loose := 0
	for i in area_tiles.size():
		var level := _level(i)
		if level > 0.5:
			thick += 1
		elif level > 0.0:
			loose += 1
	if current_tool == "brush":
		if thick > 0 or loose == 0:
			set_cue("Brush the clumps [Enter]")
		else:
			_standing_tool = "vacuum"
			set_cue("Pick the vacuum [V]")
	elif loose > 0 or thick == 0:
		set_cue("Vacuum the dust [Enter]")
	else:
		_standing_tool = "brush"
		set_cue("Pick the brush [B]")


func _status_line() -> String:
	return LINE_CLEAR if succeeded else ""


func accept_host_result(result: ActionResult, record := {}) -> void:
	super.accept_host_result(result, record)
	if result == null or result.pending:
		return
	if succeeded:
		status_label.text = LINE_CLEAR
		status_label.theme_type_variation = UiTheme.GOOD
	_update_cue()
	_redraw_all()


func _stroke(area: int) -> void:
	if pending or succeeded:
		return
	var problem: String = RULE.why_not(puzzle_state, current_tool, area)
	if problem.is_empty():
		send_move(current_tool, area)
		return
	# The rule says this stroke cannot work: a gentle mark on the patch and a short line, nothing is sent.
	_nope_area = area
	_nope_time = NOPE_SECONDS
	if _level(area) <= 0.0:
		show_hint(LINE_ALREADY_CLEAN)
	else:
		_nudge_tool = "brush"
		_nudge_time = SUGGEST_SECONDS
		show_hint(LINE_BRUSH_FIRST)
	_redraw_all()


func _on_hover(area: int, inside: bool) -> void:
	if inside:
		_hover = area
	elif _hover == area:
		_hover = -1


func _on_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_B:
			set_tool("brush")
			accept_event()
		KEY_V:
			set_tool("vacuum")
			accept_event()


func _process(delta: float) -> void:
	super._process(delta)
	if marks == null:
		return
	var less := wants_less_motion()
	for i in area_tiles.size():
		var level := _level(i)
		if _shown[i] != level:
			_shown[i] = level if less else move_toward(_shown[i], level, delta * 0.9)
			(area_tiles[i] as Control).queue_redraw()
	if _sweep_time > 0.0:
		_sweep_time = maxf(0.0, _sweep_time - delta)
		if _sweep_time <= 0.0:
			_sweep_area = -1
	if _nope_time > 0.0:
		_nope_time = maxf(0.0, _nope_time - delta)
		if _nope_area >= 0:
			(area_tiles[_nope_area] as Control).queue_redraw()
		if _nope_time <= 0.0:
			_nope_area = -1
	if _nudge_time > 0.0:
		_nudge_time = maxf(0.0, _nudge_time - delta)
		if _nudge_time <= 0.0:
			_nudge_tool = ""
	# The rings breathe and the tool follows the pointer.
	marks.queue_redraw()


# ---------------------------------------------------------------- drawing

## A steady number 0..1 for patch `area`, item `k` (where a clump sits, how it is turned).
static func _rand(area: int, k: int, salt: int) -> float:
	return float(absi(hash([area, k, salt])) % 10007) / 10007.0


func _tool_tex(tool_id: String) -> Texture2D:
	return Kit.tex(SET + ("work_brush" if tool_id == "brush" else "vacuum_nozzle"))


## The housing, the recessed tool rack with the two tools, and the floor bay.
func _paint_board(c: Control) -> void:
	if _patches.is_empty():
		return
	Kit.housing(c, Rect2(Vector2.ZERO, c.size), 22.0, false)
	Kit.bay(c, _rack, 16.0)
	Kit.bay(c, _bay, 16.0)
	for i in 2:
		var tool_id := "brush" if i == 0 else "vacuum"
		var slot := _slots[i]
		var chosen := tool_id == current_tool
		Kit.box(c, slot, Color(0.2, 0.235, 0.28) if chosen else Color(0.075, 0.095, 0.12), 12.0, Kit.BAY_EDGE, 2.0)
		var inner := slot.grow(-slot.size.x * 0.13)
		var t := _tool_tex(tool_id)
		Kit.draw_fit(c, t, Rect2(inner.position + Vector2(3, 5), inner.size), Color(0, 0, 0, 0.4))
		Kit.draw_fit(c, t, inner, Color.WHITE if chosen else Color(0.82, 0.84, 0.88))


## One floor patch: the concrete slab, the landing stripe painted across it, then the dust that is left on top.
func _paint_patch(tile: Tile) -> void:
	var i := tile.index
	if i < 0 or i >= _shown.size() or tile.size.x < 4.0:
		return
	var rect := Rect2(Vector2.ZERO, tile.size)
	var shift := Vector2.ZERO
	if _nope_area == i and _nope_time > NOPE_SECONDS - 0.35 and not wants_less_motion():
		var k := (_nope_time - (NOPE_SECONDS - 0.35)) / 0.35
		shift = Vector2(sin(k * 24.0) * 5.0 * k, 0.0)
		tile.draw_set_transform(shift)
	var slab := Kit.tex(SET + "concrete_tile")
	if slab != null:
		tile.draw_texture_rect_region(slab, rect, Rect2(9, 9, 335, 344), Color(0.74, 0.8, 0.88))
	else:
		tile.draw_rect(rect, Color(0.38, 0.4, 0.44))
	var stripe_h := clampf(rect.size.y * 0.2, 28.0, 64.0)
	var stripe := Rect2(0.0, (rect.size.y - stripe_h) * 0.5, rect.size.x, stripe_h)
	var decal := Kit.tex(SET + "yellow_lane_decal")
	if decal != null:
		tile.draw_texture_rect_region(decal, stripe, Rect2(26, 9, 376, 65))
	else:
		tile.draw_rect(stripe, Kit.HAZARD)
	var level := clampf(_shown[i], 0.0, 1.0)
	if level <= 0.0:
		tile.draw_set_transform(Vector2.ZERO)
		return
	var side := minf(rect.size.x, rect.size.y)
	# A film of dust over everything, thinner with every stroke, so the stripe shows through more and more.
	tile.draw_rect(rect, Color(DUST, 0.66 * level))
	# Loose powder: all of it from "loose" (0.5) up, half of it on the last quarter.
	var light := Kit.tex(SET + "dust_light")
	var loose := clampf(level / 0.5, 0.0, 1.0)
	for k in LIGHT_COUNT:
		var a := clampf(loose * float(LIGHT_COUNT) - float(k) * 0.75, 0.0, 1.0)
		if a <= 0.0:
			break
		var cell := (k * 3 + i) % LIGHT_COUNT
		var at := Vector2((float(cell % 4) + 0.5 + (_rand(i, k, 1) - 0.5) * 0.7) / 4.0 * rect.size.x,
			(float(cell / 4) + 0.5 + (_rand(i, k, 2) - 0.5) * 0.6) / 2.0 * rect.size.y)
		var s := side * lerpf(0.9, 1.3, _rand(i, k, 3))
		_blob(tile, light, shift + at, Vector2(s * 1.06, s), _rand(i, k, 4) * TAU, Color(POWDER, a))
	# Clumps: only on thick dust (above 0.5), fewer after each brush stroke.
	var heavy := Kit.tex(SET + "dust_heavy")
	var thick := clampf((level - 0.5) / 0.5, 0.0, 1.0)
	for k in HEAVY_COUNT:
		var a := clampf(thick * float(HEAVY_COUNT) - float(k) * 0.8, 0.0, 1.0)
		if a <= 0.0:
			break
		var cell := (k * 5 + i) % HEAVY_COUNT
		var at := Vector2((float(cell % 3) + 0.5 + (_rand(i, k, 5) - 0.5) * 0.5) / 3.0 * rect.size.x,
			(float(cell / 3) + 0.5 + (_rand(i, k, 6) - 0.5) * 0.4) / 2.0 * rect.size.y)
		var s := side * lerpf(0.52, 0.7, _rand(i, k, 7))
		_blob(tile, heavy, shift + at, Vector2(s, s), _rand(i, k, 8) * TAU, Color(CLUMP, a))
	tile.draw_set_transform(Vector2.ZERO)


func _blob(tile: Control, t: Texture2D, at: Vector2, size: Vector2, angle: float, tint: Color) -> void:
	if t == null:
		tile.draw_circle(at, size.x * 0.3, Color(DUST.darkened(0.2), tint.a * 0.8))
		return
	tile.draw_set_transform(at, angle)
	tile.draw_texture_rect(t, Rect2(-size * 0.5, size), false, tint)


## The shared marks over the floor and the rack, and the tool in hand.
func _paint_marks(c: Control) -> void:
	if _patches.is_empty():
		return
	var less := wants_less_motion()
	var focus: Color = UiTheme.palette().focus
	# The rack: the tool in hand has the focus ring; the tool to switch to breathes.
	var hinted := suggested_tool()
	for i in 2:
		var tool_id := "brush" if i == 0 else "vacuum"
		var slot := _slots[i]
		if tool_id == current_tool:
			Kit.focus_ring(c, slot, 12.0)
		elif tool_id == hinted:
			Kit.target_ring(c, slot, 12.0, less)
		if (brush_button if i == 0 else vacuum_button).has_focus():
			Kit.box(c, slot.grow(-6.0), Color(0, 0, 0, 0), 8.0, focus, 2.0)
	# The floor: a tick on every clean patch, a halo on the patches the tool in hand is for, the focus ring.
	var focused := -1
	for i in _patches.size():
		var rect := _patches[i]
		if _level(i) <= 0.0 and _shown[i] <= 0.01:
			var r := clampf(rect.size.y * 0.085, 13.0, 22.0)
			Kit.tick(c, Vector2(rect.end.x - r * 1.6, rect.position.y + r * 1.6), r)
		elif not succeeded and _wants(i) and _sweep_area != i:
			Kit.target_ring(c, rect.grow(-7.0), 8.0, less)
		if (area_tiles[i] as Control).has_focus():
			focused = i
	if focused >= 0:
		Kit.focus_ring(c, _patches[focused].grow(-5.0), 8.0)
	if _nope_area >= 0 and _nope_time > 0.0:
		Kit.cross(c, _patches[_nope_area].get_center(), clampf(_patches[_nope_area].size.y * 0.13, 18.0, 30.0))
	# The tool in hand: sweeping over the patch the host just cleaned, else at the pointer, else on the focused patch.
	var tool_h := clampf(_patches[0].size.y * 0.56, 84.0, 150.0)
	if _sweep_area >= 0 and _sweep_time > 0.0:
		var rect := _patches[_sweep_area]
		var t := 1.0 - _sweep_time / SWEEP_SECONDS
		var at := rect.get_center() + Vector2(lerpf(-0.3, 0.3, smoothstep(0.0, 1.0, t)) * rect.size.x, sin(t * TAU * 1.5) * rect.size.y * 0.15)
		_draw_tool(c, _sweep_tool, at, tool_h)
	elif succeeded:
		return
	elif _hover >= 0:
		_draw_tool(c, current_tool, c.get_local_mouse_position(), tool_h)
	elif focused >= 0:
		var rect := _patches[focused]
		_draw_tool(c, current_tool, rect.position + rect.size * Vector2(0.66, 0.5), tool_h)


## A tool lying on the floor with its working end at `head` and its handle towards the lower right.
func _draw_tool(c: Control, tool_id: String, head: Vector2, height: float) -> void:
	var t := _tool_tex(tool_id)
	if t == null:
		return
	if tool_id == "vacuum":
		height *= 0.8
	var size := Vector2(height * t.get_size().x / t.get_size().y, height)
	var pivot := Vector2(0.5, 0.1)
	Kit.draw_turned(c, t, head + Vector2(5, 8), size, -0.6, Color(0, 0, 0, 0.38), pivot)
	Kit.draw_turned(c, t, head, size, -0.6, Color.WHITE, pivot)
