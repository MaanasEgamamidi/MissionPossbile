extends TaskPanel
## Shared frame of the T06 Water, T08 Glass and T11 Dust mini-games (broken parts, 2026-11-14). Not a registered
## class: the three panels extend it by path. It
##   - claims the task when the panel opens (the host's RepairRuntime lease),
##   - sends one task_move per real player action, numbered with the rule's step counter so a replayed or stale move
##     is refused by the host: value = (puzzle_state.step + 1) * STEP_SHIFT + payload,
##   - takes the task back and re-sends the move once if the lease ran out while the player was thinking,
##   - redraws only from the host's task record (task.puzzle_state, read through the rule's state_of()).
## Subclasses set `rule`, build their controls in _build_board() and draw in _redraw().

## Must match STEP_SHIFT in the t06/t08/t11 rules.
const STEP_SHIFT := 1024


## A plain control drawn by a callback (boards, gauges, legends).
class Paint extends Control:
	var painter := Callable()

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


## A focusable board square or piece button drawn by a callback. Keyboard: arrows move focus, Enter / Space press.
class Tile extends Button:
	var painter := Callable()
	var index := -1

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


## The puzzle's host rule script (preloaded by the subclass).
var rule: Script
## The host's puzzle state, normalised by the rule (never decided here).
var puzzle_state: Dictionary = {}
## Short friendly line shown under the board after each answer.
var hint_label: Label

var _last_move: Dictionary = {}
var _resend: Dictionary = {}
var _last_action: StringName = &""
var _shown_step := -1
var _shown_progress := -1.0


func setup(p_services: GameServices) -> void:
	var first := play_area == null
	super.setup(p_services)
	if not first:
		return
	reset_requested.connect(func() -> void: send_move("reset", 0))
	_build_board()
	# The hint line is kept (tests and tools read it) but not shown: its text goes to the shell's cue bar.
	hint_label = _label("Hint", UiTheme.HEADING)
	hint_label.visible = false
	play_area.add_child(hint_label)
	_read_record()
	if services != null and services.has_game() and not anchor_id.is_empty() and not succeeded:
		_ask(&"task_claim", {})


## Builds the board controls inside play_area. Override.
func _build_board() -> void:
	pass


## Redraws every control from puzzle_state. Override; must not rebuild nodes (focus stays where it is).
func _redraw() -> void:
	pass


## Text for the hint line after the host accepted a move. Override.
func _status_line() -> String:
	return ""


## The current task record from the host's replicated state (empty without a game).
func task_record() -> Dictionary:
	if services == null or not services.has_game() or task_id.is_empty():
		return {}
	return (services.state().repair.get("tasks", {}) as Dictionary).get(task_id, {})


## The step number the next move must carry.
func next_step() -> int:
	return int(puzzle_state.get("step", 0)) + 1


## Sends one move. The value carries the step counter and the payload (payload < STEP_SHIFT).
func send_move(move_name: String, payload: int) -> void:
	if pending or succeeded:
		return
	_last_move = {"move": move_name, "payload": payload}
	_ask(&"task_move", {"move": move_name, "value": next_step() * STEP_SHIFT + payload})


## Shows a friendly line without asking the host (for a move the panel already knows cannot work).
func show_hint(text: String, warn := true) -> void:
	hint_label.text = text
	hint_label.theme_type_variation = UiTheme.WARN if warn else UiTheme.HEADING
	flash(text, &"warn" if warn else &"good")


func apply_host_state(record: Dictionary) -> void:
	super.apply_host_state(record)
	if not _built or rule == null or record.is_empty():
		return
	puzzle_state = rule.call(&"state_of", record)
	_shown_step = int(puzzle_state.get("step", 0))
	_shown_progress = float(record.get("progress", 0.0))
	_redraw()


func accept_host_result(result: ActionResult, record := {}) -> void:
	super.accept_host_result(result, record)
	if result == null or result.pending:
		return
	if result.ok:
		if _last_action == &"task_claim" and not _resend.is_empty():
			var again := _resend
			_resend = {}
			_resend_move.call_deferred(again)
			return
		var line := _status_line()
		if not line.is_empty():
			show_hint(line, false)
	elif result.reason == &"task_unclaimed" and _last_action == &"task_move" and not _last_move.is_empty() and _resend.is_empty():
		# The lease ends after 30 s without a move; take the task again and repeat the move once.
		_resend = _last_move.duplicate()
		_reclaim.call_deferred()
	elif result.reason == &"invalid_move":
		show_hint("That move does not fit the puzzle right now. Look again and try another one.")
	elif not result.message.is_empty():
		show_hint(result.message)


## Clients get the host's state by replication: redraw when it changed.
func refresh() -> void:
	super.refresh()
	var record := task_record()
	if record.is_empty() or pending:
		return
	var step := int((record.get("puzzle_state", {}) as Dictionary).get("step", 0))
	if step != _shown_step or float(record.get("progress", 0.0)) != _shown_progress:
		apply_host_state(record)


## True when the player asked for less motion (UiRoot's settings), so animations show their end state at once.
func reduce_motion() -> bool:
	var node: Node = get_parent()
	while node != null:
		var settings: Variant = node.get(&"settings") if &"settings" in node else null
		if settings is GameSettings:
			return (settings as GameSettings).reduce_motion
		node = node.get_parent()
	return false


## A focusable board square or piece of the given minimum size, drawn by `painter`.
func make_tile(node_name: String, index: int, min_size: Vector2, painter: Callable) -> Tile:
	var tile := Tile.new()
	tile.name = node_name
	tile.index = index
	tile.custom_minimum_size = min_size
	tile.focus_mode = Control.FOCUS_ALL
	tile.painter = painter
	return tile


## Draws centred text inside rect on a control with the theme font.
static func draw_text(c: Control, rect: Rect2, text: String, color: Color, scale := 1.0) -> void:
	var font := c.get_theme_font(&"font", &"Label")
	var font_size := int(round(c.get_theme_font_size(&"font_size", &"Label") * scale))
	var height := font.get_height(font_size)
	var baseline := rect.position.y + (rect.size.y - height) * 0.5 + font.get_ascent(font_size)
	c.draw_string(font, Vector2(rect.position.x, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, color)


func _read_record() -> void:
	var record := task_record()
	if not record.is_empty():
		apply_host_state(record)
	elif rule != null:
		puzzle_state = rule.call(&"state_of", {"puzzle_seed": 0})
		_redraw()


func _ask(action: StringName, params: Dictionary) -> void:
	_last_action = action
	request_host(action, params)


func _reclaim() -> void:
	if not is_inside_tree() or succeeded:
		_resend = {}
		return
	_ask(&"task_claim", {})


func _resend_move(move: Dictionary) -> void:
	if is_inside_tree() and not succeeded:
		send_move(String(move.move), int(move.payload))
