extends TaskPanel
## Shared base of the four Command Room / Power Room mini-games (T01 Comms, T02 Wires, T03 Rings, T04 Circuits).
## Loaded by path only (no class_name). It adds the host plumbing every puzzle needs on top of TaskPanel:
## - claims the task when the panel opens (task_claim), and claims it again if the 30 s lease ran out;
## - send_move(name, value) sends one discrete task_move to the host (never a completion flag);
## - redraws from the host's replicated task.puzzle_state (_on_host_state), never from local guesses;
## - lets a puzzle replace the generic "Move rejected" text with a kid-friendly explanation (_explain_rejection).
## It also holds the shared drawing helpers: the colour-blind symbols (triangle, circle, square, diamond) and a
## DrawBox control whose drawing and input are forwarded to the panel.

## Board colours that echo the broken parts (dark console glass, light schematic boards). Designer art values.
const SCREEN_BG := Color(0.03, 0.06, 0.08)
const SCREEN_GRID := Color(0.12, 0.2, 0.24)
const BOARD_BG := Color(0.9, 0.91, 0.88)
const BOARD_LINE := Color(0.72, 0.2, 0.18)
const METAL := Color(0.55, 0.58, 0.62)
const METAL_DARK := Color(0.2, 0.22, 0.25)
const LAMP_OFF := Color(0.25, 0.27, 0.3)
const LAMP_GOOD := Color(0.35, 0.9, 0.45)
const LAMP_WAIT := Color(0.98, 0.78, 0.3)

## Symbol shapes (never colour alone).
enum Shape { TRIANGLE, CIRCLE, SQUARE, DIAMOND }

var last_move: Dictionary = {}
var _last_action: StringName = &""
var _reclaim_pending := false
var _state_hash := 0
## Set by each puzzle at the end of its setup(), once its own controls exist.
var ui_ready := false


## A Control that hands its drawing and its input to the panel. painter(box) draws; handler(box, event) -> bool
## returns true when it used the event.
class DrawBox extends Control:
	var painter := Callable()
	var handler := Callable()

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)

	func _gui_input(event: InputEvent) -> void:
		if handler.is_valid() and bool(handler.call(self, event)):
			accept_event()


func _ready() -> void:
	if services != null and services.has_game() and not anchor_id.is_empty() and not succeeded:
		claim()


## Asks the host for this task's operator lease (the panel's first request when it opens).
func claim() -> void:
	_last_action = &"task_claim"
	request_host(&"task_claim")


## Sends one discrete move. The host rule alone decides whether it counts and whether the repair is complete.
func send_move(move_name: String, value: int) -> void:
	if pending or succeeded or services == null:
		return
	last_move = {"move": move_name, "value": value}
	_last_action = &"task_move"
	request_host(&"task_move", {"move": move_name, "value": value})


## The host's current record of this task (a copy), or {}.
func host_record() -> Dictionary:
	if services == null or not services.has_game() or task_id.is_empty():
		return {}
	return (services.state().repair.get("tasks", {}) as Dictionary).get(task_id, {}).duplicate(true)


## Re-reads the host record and redraws (used after setup and from refresh()).
func refresh_from_host() -> void:
	var record := host_record()
	if not record.is_empty():
		apply_host_state(record)


func apply_host_state(record: Dictionary) -> void:
	super.apply_host_state(record)
	if not _built_ui():
		return
	var puzzle: Dictionary = record.get("puzzle_state", {}) if record.get("puzzle_state", {}) is Dictionary else {}
	_state_hash = hash([puzzle, record.get("progress", 0.0)])
	_on_host_state(int(record.get("puzzle_seed", 0)), puzzle, record)


func accept_host_result(result: ActionResult, record := {}) -> void:
	super.accept_host_result(result, record)
	if result == null or result.pending:
		return
	var action := _last_action
	if result.ok and action == &"task_claim" and _reclaim_pending:
		_reclaim_pending = false
		status_label.text = "Back at the controls. Try that again."
		_after_reclaim()
		return
	if result.ok and action == &"task_claim" and not succeeded:
		status_label.text = ""        # no words needed: the equipment is in front of the player
		return
	if result.ok or succeeded:
		if succeeded:
			_on_solved()
		return
	if action == &"task_claim" and _reclaim_pending:
		_reclaim_pending = false
	if result.reason == &"task_unclaimed" and not _reclaim_pending:
		# The 30 s operator lease ran out while the player was thinking: pick the task up again.
		_reclaim_pending = true
		claim.call_deferred()
		return
	if action == &"task_claim":
		status_label.text = "Can't start this repair: " + result.message
		return
	if result.reason == &"invalid_move":
		var text := _explain_rejection(last_move)
		if not text.is_empty():
			status_label.text = text
			status_label.theme_type_variation = UiTheme.WARN


func refresh() -> void:
	super.refresh()
	if pending or not _built_ui():
		return
	var record := host_record()
	if record.is_empty():
		return
	var puzzle: Dictionary = record.get("puzzle_state", {}) if record.get("puzzle_state", {}) is Dictionary else {}
	if hash([puzzle, record.get("progress", 0.0)]) != _state_hash:
		apply_host_state(record)


# ---------------------------------------------------------------- hooks for the puzzles

## True once the puzzle's own controls exist.
func _built_ui() -> bool:
	return ui_ready


## Redraw from the host's state. seed = task.puzzle_seed, puzzle = task.puzzle_state.
func _on_host_state(_seed: int, _puzzle: Dictionary, _record: Dictionary) -> void:
	pass


## Kid-friendly text for a rejected move, or "" to keep the generic message.
func _explain_rejection(_move: Dictionary) -> String:
	return ""


## Called after the lease was claimed again.
func _after_reclaim() -> void:
	pass


## Called once the host says the repair is complete.
func _on_solved() -> void:
	pass


# ---------------------------------------------------------------- shared drawing

## Draws a colour-blind-safe symbol: a filled shape with a dark outline.
static func draw_symbol(ci: CanvasItem, shape: int, center: Vector2, r: float, fill: Color, outline: Color) -> void:
	var points := symbol_points(shape, center, r)
	if shape == Shape.CIRCLE:
		ci.draw_circle(center, r + 2.0, outline)
		ci.draw_circle(center, r, fill)
		return
	var outer := symbol_points(shape, center, r + 2.5)
	ci.draw_colored_polygon(outer, outline)
	ci.draw_colored_polygon(points, fill)


static func symbol_points(shape: int, center: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match shape:
		Shape.TRIANGLE:
			for i in 3:
				var a := -PI / 2.0 + TAU * float(i) / 3.0
				pts.append(center + Vector2(cos(a), sin(a)) * r * 1.1)
		Shape.SQUARE:
			var h := r * 0.85
			pts = PackedVector2Array([center + Vector2(-h, -h), center + Vector2(h, -h), center + Vector2(h, h), center + Vector2(-h, h)])
		Shape.DIAMOND:
			pts = PackedVector2Array([center + Vector2(0, -r * 1.1), center + Vector2(r, 0), center + Vector2(0, r * 1.1), center + Vector2(-r, 0)])
		_:
			for i in 16:
				var a := TAU * float(i) / 16.0
				pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts


## A round status lamp with a dark rim.
static func draw_lamp(ci: CanvasItem, center: Vector2, r: float, color: Color) -> void:
	ci.draw_circle(center, r + 3.0, METAL_DARK)
	ci.draw_circle(center, r, color)
	ci.draw_circle(center + Vector2(-r * 0.3, -r * 0.3), r * 0.28, Color(1, 1, 1, 0.35))


## Text centred on a point, in the theme's font.
static func draw_text_centered(ci: CanvasItem, text: String, center: Vector2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var theme_font := UiTheme.get_theme().default_font
	if theme_font != null:
		font = theme_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	ci.draw_string(font, center + Vector2(-w * 0.5, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## A small symbol chip for inside a button (ignores the mouse, so the button still gets the clicks).
func make_symbol_chip(shape: int, color: Color) -> DrawBox:
	var chip := DrawBox.new()
	chip.name = "Symbol"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.custom_minimum_size = Vector2(30, 30)
	chip.painter = paint_symbol_chip.bind(shape, color)
	return chip


## Painter for make_symbol_chip (also used to recolour a chip: chip.painter = paint_symbol_chip.bind(shape, color)).
func paint_symbol_chip(box: Control, shape: int, color: Color) -> void:
	draw_symbol(box, shape, box.size * 0.5, minf(box.size.x, box.size.y) * 0.4, color, Color(0.05, 0.05, 0.07))


## A labelled button for the play area.
static func make_button(node_name: String, text: String, primary := false) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if primary:
		b.theme_type_variation = UiTheme.PRIMARY_BUTTON
	return b
