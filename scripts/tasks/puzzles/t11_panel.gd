extends "res://scripts/tasks/puzzles/board_ui.gd"
## T11 Dust mini-game (Hangar, BP10): clean the six areas of the hangar floor, stroke by stroke, with the brush or the
## vacuum. The host rule (t11_rule.gd) checks every stroke and decides completion; this panel only sends "brush" /
## "vacuum" moves and draws the host's puzzle_state. Dust is shown by speckles, a four-step meter and words (Thick /
## Loose / Light / Clean), not by colour alone; the yellow floor lines show again as the dust goes.
## Controls: pick a tool (click, or B = brush, V = vacuum), then click an area or move to it with the arrow keys and
## press Enter / Space for one stroke.

const RULE := preload("res://scripts/tasks/puzzles/t11_rule.gd")
const DUST := Color(0.8, 0.47, 0.3)

var area_tiles: Array = []
var brush_button: Button
var vacuum_button: Button
## "brush" or "vacuum".
var current_tool := "brush"


func setup(p_services: GameServices) -> void:
	rule = RULE
	task_title = "Clean the dusty hangar"
	instructions = ("Mars dust got tracked all over the hangar. Clean every area of the floor. The brush loosens any "
		+ "dust a little at a time; the vacuum takes away loose dust twice as fast, but thick dust must be brushed "
		+ "first. Pick a tool (B = brush, V = vacuum), then click an area or move to it with the arrow keys and press "
		+ "Enter.")
	super.setup(p_services)
	name = "T11DustPanel"


func _build_board() -> void:
	var tools := HBoxContainer.new()
	tools.name = "Tools"
	tools.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play_area.add_child(tools)
	var group := ButtonGroup.new()
	brush_button = _tool_button("ToolBrush", "Brush (B)", "brush", group)
	tools.add_child(brush_button)
	vacuum_button = _tool_button("ToolVacuum", "Vacuum (V)", "vacuum", group)
	tools.add_child(vacuum_button)
	brush_button.button_pressed = true
	var map := GridContainer.new()
	map.name = "HangarMap"
	map.columns = 3
	map.add_theme_constant_override(&"h_separation", 4)
	map.add_theme_constant_override(&"v_separation", 4)
	map.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play_area.add_child(map)
	for i in RULE.AREAS.size():
		var tile := make_tile("Area%d" % i, i, Vector2(196, 112), _paint_area)
		tile.tooltip_text = String(RULE.AREAS[i].name)
		tile.pressed.connect(_stroke.bind(i))
		tile.gui_input.connect(_on_key_input)
		map.add_child(tile)
		area_tiles.append(tile)


func _tool_button(node_name: String, text: String, tool_id: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.pressed.connect(set_tool.bind(tool_id))
	button.gui_input.connect(_on_key_input)
	return button


## Chooses the cleaning tool ("brush" or "vacuum").
func set_tool(tool_id: String) -> void:
	current_tool = tool_id
	(brush_button if current_tool == "brush" else vacuum_button).set_pressed_no_signal(true)
	show_hint("%s ready. Pick an area to clean." % ("Brush" if current_tool == "brush" else "Vacuum"), false)


func _redraw() -> void:
	for c: Control in area_tiles:
		c.queue_redraw()


func _status_line() -> String:
	if succeeded:
		return "The hangar is clean and the floor lines show again. Great job!"
	var dusty := 0
	for level: Variant in (puzzle_state.get("areas", {}) as Dictionary).values():
		if float(level) > 0.0:
			dusty += 1
	return "%d area%s still dusty." % [dusty, " is" if dusty == 1 else "s are"]


func _stroke(area: int) -> void:
	var problem: String = RULE.why_not(puzzle_state, current_tool, area)
	if not problem.is_empty():
		show_hint(problem)
		return
	send_move(current_tool, area)


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


static func dust_words(level: float) -> String:
	if level <= 0.0:
		return "Clean!"
	if level > 0.5:
		return "Thick dust"
	return "Loose dust" if level > 0.25 else "Light dust"


func _paint_area(tile: Tile) -> void:
	var p := UiTheme.palette()
	var areas: Dictionary = puzzle_state.get("areas", {})
	if tile.index >= RULE.AREAS.size() or areas.is_empty():
		return
	var info: Dictionary = RULE.AREAS[tile.index]
	var level := float(areas.get(info.id, 0.0))
	var rect := Rect2(Vector2.ZERO, tile.size).grow(-5.0)
	tile.draw_rect(rect, Color(0.62, 0.64, 0.66))
	# Floor markings: a yellow and dark band that the dust hides.
	var band := Rect2(rect.position + Vector2(0, rect.size.y * 0.18), Vector2(rect.size.x, 14))
	tile.draw_rect(band, Color(0.95, 0.78, 0.2))
	for i in int(band.size.x / 18.0):
		var x := band.position.x + i * 18.0
		tile.draw_colored_polygon(PackedVector2Array([Vector2(x, band.end.y), Vector2(x + 7, band.position.y),
			Vector2(x + 13, band.position.y), Vector2(x + 6, band.end.y)]), Color(0.12, 0.12, 0.12))
	if level > 0.0:
		tile.draw_rect(rect, Color(DUST, 0.3 + 0.6 * level))
		var speckles := int(level * 40.0)
		for i in speckles:
			var h := hash([tile.index, i])
			var at := rect.position + Vector2(float(h % 1000) / 1000.0 * rect.size.x, float((h / 1000) % 1000) / 1000.0 * rect.size.y * 0.7)
			tile.draw_circle(at, 2.0 + float(h % 3), Color(0.55, 0.3, 0.18, 0.9))
	# Name, words and a four-step meter on a dark strip for readability.
	var strip := Rect2(Vector2(rect.position.x, rect.end.y - 46), Vector2(rect.size.x, 46))
	tile.draw_rect(strip, Color(0.03, 0.04, 0.06, 0.82))
	draw_text(tile, Rect2(strip.position, Vector2(strip.size.x, 22)), "%s: %s" % [String(info.name), dust_words(level)],
		p.good if level <= 0.0 else p.text, 0.72)
	var quarters := int(round(level / RULE.STROKE))
	for q in 4:
		var seg := Rect2(Vector2(strip.position.x + strip.size.x * 0.5 - 52 + q * 26, strip.end.y - 18), Vector2(22, 10))
		if q < quarters:
			tile.draw_rect(seg, DUST)
		tile.draw_rect(seg, p.text, false, 1.0)
