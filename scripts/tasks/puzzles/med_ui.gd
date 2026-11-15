extends TaskPanel
## Shared base of puzzle worker C's mini-games: T09 Mixture and T10 Equipment (Med Bay) and T12 Seal (airlock).
## Loaded by path only (no class_name). It adds the host plumbing on top of TaskPanel:
## - claims the task when the panel enters the tree (task_claim) and claims it again if the 30 s lease ran out;
## - send(name, payload) numbers every move with the host's step counter (value = step * STEP_BASE + payload), so a
##   doubled or replayed request is refused by the rule; it never sends a completion flag;
## - redraws only from the host's task record (puzzle_state through the rule's current_state()), also on clients;
## - turns a refused move into a kid-friendly reason (explain()).
## Plus small drawing helpers: shapes for colour-blind players, a DrawBox control that forwards drawing and clicks.

const STEP_BASE := 1000
enum Shape { CIRCLE, TRIANGLE, SQUARE, DIAMOND }

## The current puzzle state as the host has it (the rule's current_state(), so the seeded start before any move).
var puzzle: Dictionary = {}
var last_move: Dictionary = {}
## Set by each puzzle at the end of build_game(), once its own controls exist.
var ui_ready := false
var _last_action: StringName = &""
var _reclaim_pending := false
var _state_hash := 0


## A Control that hands its drawing and its mouse clicks to the panel.
class DrawBox extends Control:
	var painter := Callable()
	var clicked := Callable()

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and clicked.is_valid():
			clicked.call(self, mb.position)
			accept_event()


# ---------------------------------------------------------------- hooks for the puzzles

## The puzzle's rule script (preloaded tNN_rule.gd).
func rule_script() -> Script:
	return null


## Builds the puzzle's controls inside play_area (called once from setup()).
func build_game() -> void:
	pass


## Redraws from `puzzle` (the host's state).
func redraw() -> void:
	pass


## Kid-friendly reason for a refused move.
func explain(_move: Dictionary) -> String:
	return "That doesn't work here. Try something else."


## Short words after an accepted move.
func praise(_move: Dictionary) -> String:
	return "Done."


## Words once the host says the repair is complete.
func solved_text() -> String:
	return "Fixed! The host confirmed the repair."


# ---------------------------------------------------------------- plumbing

func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	reset_requested.connect(func() -> void: send("reset", 0))
	build_game()
	ui_ready = true
	refresh_from_host()


func _ready() -> void:
	if services != null and services.has_game() and not anchor_id.is_empty() and not succeeded:
		claim()


## Asks the host for this task's operator lease (the first request when the panel opens).
func claim() -> void:
	_last_action = &"task_claim"
	request_host(&"task_claim")


## Sends one discrete move, numbered with the host's step counter. The host rule alone decides what it does.
func send(move_name: String, payload: int) -> void:
	if pending or succeeded or services == null:
		return
	last_move = {"move": move_name, "value": payload}
	_last_action = &"task_move"
	request_host(&"task_move", {"move": move_name, "value": int(puzzle.get("step", 0)) * STEP_BASE + payload})


## The host's current record of this task (a copy), or {}.
func host_record() -> Dictionary:
	if services == null or not services.has_game() or task_id.is_empty():
		return {}
	return (services.state().repair.get("tasks", {}) as Dictionary).get(task_id, {}).duplicate(true)


func refresh_from_host() -> void:
	var record := host_record()
	if not record.is_empty():
		apply_host_state(record)


func apply_host_state(record: Dictionary) -> void:
	super.apply_host_state(record)
	if not ui_ready or rule_script() == null:
		return
	_state_hash = hash([record.get("puzzle_state", {}), record.get("progress", 0.0), record.get("puzzle_seed", 0)])
	puzzle = rule_script().call(&"current_state", record)
	redraw()


func accept_host_result(result: ActionResult, record := {}) -> void:
	super.accept_host_result(result, record)
	if result == null or result.pending:
		return
	var action := _last_action
	if succeeded:
		status_label.text = solved_text()
		status_label.theme_type_variation = UiTheme.GOOD
		return
	if action == &"task_claim":
		if result.ok:
			status_label.text = "Back at the controls. Try that again." if _reclaim_pending else "Ready. The host checks every step."
			_reclaim_pending = false
		else:
			status_label.text = "You can't start this repair: " + result.message
		return
	if result.ok:
		status_label.text = praise(last_move)
		return
	if result.reason == &"task_unclaimed" and not _reclaim_pending:
		# The 30 s operator lease ran out while the player was thinking: pick the task up again.
		_reclaim_pending = true
		claim.call_deferred()
		return
	if result.reason == &"invalid_move":
		status_label.text = explain(last_move)
		status_label.theme_type_variation = UiTheme.WARN


func refresh() -> void:
	super.refresh()
	if pending or not ui_ready:
		return
	var record := host_record()
	if record.is_empty():
		return
	if hash([record.get("puzzle_state", {}), record.get("progress", 0.0), record.get("puzzle_seed", 0)]) != _state_hash:
		apply_host_state(record)


## Local hint without asking the host (for a click that cannot be a move yet).
func hint(text: String) -> void:
	status_label.text = text
	status_label.theme_type_variation = UiTheme.MUTED


# ---------------------------------------------------------------- shared drawing

## A labelled, focusable button for the play area.
static func make_button(node_name: String, text: String, primary := false) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if primary:
		b.theme_type_variation = UiTheme.PRIMARY_BUTTON
	return b


static func make_box(node_name: String, min_size: Vector2, painter: Callable, clicked := Callable()) -> DrawBox:
	var box := DrawBox.new()
	box.name = node_name
	box.custom_minimum_size = min_size
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.painter = painter
	box.clicked = clicked
	box.mouse_filter = Control.MOUSE_FILTER_STOP if clicked.is_valid() else Control.MOUSE_FILTER_IGNORE
	return box


## A filled shape with a dark outline (colour-blind cue next to colour).
static func draw_shape(ci: CanvasItem, shape: int, center: Vector2, r: float, fill: Color, outline := Color(0.05, 0.05, 0.08)) -> void:
	if shape == Shape.CIRCLE:
		ci.draw_circle(center, r + 2.0, outline)
		ci.draw_circle(center, r, fill)
		return
	ci.draw_colored_polygon(shape_points(shape, center, r + 2.5), outline)
	ci.draw_colored_polygon(shape_points(shape, center, r), fill)


static func shape_points(shape: int, center: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match shape:
		Shape.TRIANGLE:
			for i in 3:
				var a := -PI / 2.0 + TAU * float(i) / 3.0
				pts.append(center + Vector2(cos(a), sin(a)) * r * 1.15)
		Shape.SQUARE:
			var h := r * 0.85
			pts = PackedVector2Array([center + Vector2(-h, -h), center + Vector2(h, -h), center + Vector2(h, h), center + Vector2(-h, h)])
		Shape.DIAMOND:
			pts = PackedVector2Array([center + Vector2(0, -r * 1.15), center + Vector2(r, 0), center + Vector2(0, r * 1.15), center + Vector2(-r, 0)])
		_:
			for i in 16:
				var a := TAU * float(i) / 16.0
				pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts


## Text centred on a point, in the theme's font.
static func draw_text_centered(ci: CanvasItem, text: String, center: Vector2, font_size: int, color: Color) -> void:
	var font: Font = UiTheme.get_theme().default_font
	if font == null:
		font = ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	ci.draw_string(font, center + Vector2(-w * 0.5, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
