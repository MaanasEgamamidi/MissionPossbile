class_name TaskPanel
extends UiPanel
## Shared repair frame. The host owns progress; this frame never changes colony state.
## Concrete puzzles populate play_area and send discrete, host-validated moves.
##
## UI overhaul (2026-11-15, docs/revisions/ui_overhaul/): the frame is now a quiet shell around the equipment, in the
## spirit of Among Us task screens: a child should see the apparatus, not a form.
##   Header    action title ("Water the Kale"), who can do it (specialist chip), "?" help, start again, close.
##   PlayArea  the mini-game's equipment, as large as the frame allows. Nothing else competes with it.
##   CueBar    ONE short line: the standing cue (set_cue, key caps written as [Enter]) and, for a few seconds after
##             a move, the feedback line (whatever a puzzle writes to status_label, or flash()).
##   Progress  a slim bar along the bottom edge (the host's progress).
## The long instructions are one press away behind "?" and never shown by default. When the host confirms the
## repair the frame shows the shared success mark and closes itself, so the player sees the fixed part in the world.
## status_label, progress_bar, reset_button and cancel_button keep their names and meaning (puzzles and tests use them).

const Kit := preload("res://scripts/tasks/puzzles/kit.gd")
## Seconds a feedback line stays in the cue bar before the standing cue comes back.
const FLASH_SECONDS := 3.5
## Seconds the success mark shows before the panel closes itself (0 = stay open; tests and captures may set it).
static var auto_close_seconds := 2.8
## Seconds after the repair before the success mark pops in: first the equipment shows its own result (water
## reaches the kale, the lamp lights), then the mark.
const STAMP_DELAY := 0.8

signal move_requested(move: Dictionary)
signal reset_requested
signal operator_released

var task_id := ""
var anchor_id := ""
var fault_generation := 1
var task_title := "Repair task"
var room_title := ""
var required_role := "general"
var instructions := ""
var pending := false
var succeeded := false
## Wrong specialist (owner 2026-11-14): the controls are scrambled symbols nobody can read and no move can be sent.
var unreadable := false
## The clear line under the scrambled controls ("Only the ⚡ Electrical and comms specialist can read this. ...").
var unreadable_label: Label
var play_area: VBoxContainer
var progress_bar: ProgressBar
var status_label: Label
var reset_button: Button
var cancel_button: Button

## The standing one-line cue under the equipment ("Turn the pipes [Enter]").
var cue_text := ""
var help_button: Button
var role_chip: PanelContainer

var _title: Label
var _context: Label
var _instructions: Label
var _cue_row: HBoxContainer
var _cue_shown := ""
var _cue_variation: StringName = &""
var _flash_left := 0.0
var _seen_status := ""
var _stamp: Control
var _success_time := -1.0
var _auto_closed := false
var _pending_id := ""
var _pending_seconds := 0.0
var _operator_id: StringName = &""
var _claimed := false
var _built := false
var _closing := false
var _used_host := false
var _released := false


func configure_task(record: Dictionary, title := "Repair task", room := "", help_text := "") -> void:
	task_id = String(record.get("task_id", ""))
	anchor_id = String(record.get("anchor_id", ""))
	fault_generation = int(record.get("fault_generation", 1))
	required_role = String(record.get("required_specialty", "general"))
	task_title = title
	room_title = room
	instructions = help_text
	if _built:
		_update_headings()
		apply_host_state(record)


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	if _built:
		return
	_built = true
	name = "TaskPanel"
	interrupt_on_critical = true
	theme_type_variation = UiTheme.PANEL
	max_width = 1100.0
	max_height = 820.0
	var frame := VBoxContainer.new()
	frame.name = "Frame"
	add_child(frame)
	# ---- header: title, who can do it, help, start again, close
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override(&"separation", 10)
	frame.add_child(header)
	_title = _label("Title", UiTheme.TITLE)
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_title)
	role_chip = PanelContainer.new()
	role_chip.name = "RoleChip"
	role_chip.theme_type_variation = UiTheme.CHIP
	role_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var role_label := Label.new()
	role_label.name = "Role"
	role_chip.add_child(role_label)
	header.add_child(role_chip)
	help_button = _icon_button("Help", &"help", "How to do this repair")
	help_button.toggle_mode = true
	help_button.toggled.connect(func(on: bool) -> void:
		_instructions.visible = on and not _instructions.text.is_empty())
	header.add_child(help_button)
	reset_button = _icon_button("Reset", &"reset", "Start again")
	reset_button.pressed.connect(func() -> void:
		if not pending and not succeeded:
			reset_requested.emit())
	header.add_child(reset_button)
	cancel_button = _icon_button("Cancel", &"close", "Close (Esc)")
	cancel_button.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(cancel_button)
	# ---- the equipment
	var scroll := ScrollContainer.new()
	scroll.name = "TaskScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	# Kept for screen readers, tests and tooltips; the role chip and the "?" button show them on demand.
	_context = _label("RoomAndRole", UiTheme.MUTED)
	_context.visible = false
	body.add_child(_context)
	_instructions = _label("Instructions")
	_instructions.visible = false
	body.add_child(_instructions)
	play_area = VBoxContainer.new()
	play_area.name = "PlayArea"
	play_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(play_area)
	# The puzzles' feedback channel. Not shown itself: the cue bar shows what is written here for a few seconds.
	status_label = _label("Status", UiTheme.MUTED)
	status_label.text = ""
	status_label.visible = false
	body.add_child(status_label)
	# ---- one short line under the equipment
	var cue_holder := CenterContainer.new()
	cue_holder.name = "CueBar"
	frame.add_child(cue_holder)
	_cue_row = HBoxContainer.new()
	_cue_row.name = "Cue"
	_cue_row.add_theme_constant_override(&"separation", 8)
	cue_holder.add_child(_cue_row)
	progress_bar = ProgressBar.new()
	progress_bar.name = "HostProgress"
	progress_bar.max_value = 100.0
	progress_bar.step = 0.0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 10)
	progress_bar.theme_type_variation = UiTheme.BAR_COOL
	progress_bar.tooltip_text = "How much of the repair is done"
	frame.add_child(progress_bar)
	# ---- the shared success mark, over everything
	_stamp = Control.new()
	_stamp.name = "SuccessMark"
	_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamp.visible = false
	_stamp.draw.connect(_draw_stamp)
	add_child(_stamp)
	_update_headings()
	_show_cue(cue_text, UiTheme.HEADING)
	if services != null:
		var actor := services.local_character()
		_operator_id = actor.id if actor != null else &""
		services.events.action_resolved.connect(_on_action_resolved)
		services.events.character_recovered.connect(_on_recovered)
		services.events.crew_ownership_changed.connect(_on_ownership_changed)
		if services.net != null:
			services.net.host_lost.connect(_on_host_lost)


func panel_title() -> String:
	return task_title


## The equipment gets the keyboard first, not the header buttons.
func first_focus() -> Control:
	if pending:
		return cancel_button
	var inside := _first_focusable(play_area) if play_area != null else null
	return inside if inside != null else cancel_button


## Sets the standing cue: ONE short line (aim for six words or fewer) saying what to do, with the keys to use written
## in square brackets: set_cue("Turn the pipes [Enter]"). Shown under the equipment whenever no feedback is showing.
func set_cue(text: String) -> void:
	cue_text = text
	if _built and _flash_left <= 0.0 and not succeeded:
		_show_cue(cue_text, UiTheme.HEADING)


## Shows a feedback line in the cue bar for a few seconds ("Nearly! Turn it once more."), then the standing cue
## returns. kind: &"good", &"warn" or &"" (plain). Writing to status_label does the same.
func flash(text: String, kind: StringName = &"") -> void:
	if not _built or text.is_empty():
		return
	_flash_left = FLASH_SECONDS
	_show_cue(text, UiTheme.GOOD if kind == &"good" else (UiTheme.WARN if kind == &"warn" else &""))


## True when the player asked for less motion (UiRoot's settings): animations then show their end state at once.
func wants_less_motion() -> bool:
	var node: Node = get_parent()
	while node != null:
		var found: Variant = node.get(&"settings") if &"settings" in node else null
		if found is GameSettings:
			return (found as GameSettings).reduce_motion
		node = node.get_parent()
	return false


## A puzzle emits only discrete moves; no completion boolean is accepted by this frame.
func submit_move(move: Dictionary) -> void:
	if pending or succeeded or _closing or unreadable:
		return
	set_pending()
	move_requested.emit(move.duplicate(true))


## Turns this frame into the wrong-specialist view: the equipment is locked behind the badge of the crew member who
## can do it (their symbol and name, large), with one clear `line` saying how to get them, over a dim strip of
## scrambled symbols where the controls would be (unreadable on purpose, the same for the same `seed_value`). No
## reset, no moves. Only close works.
func show_unreadable(line: String, seed_value := 0) -> void:
	if not _built:
		return
	unreadable = true
	for child in play_area.get_children():
		play_area.remove_child(child)
		child.queue_free()
	_instructions.text = ""
	_instructions.visible = false
	help_button.visible = false
	role_chip.visible = false
	var centre := CenterContainer.new()
	centre.name = "Locked"
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	play_area.add_child(centre)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	centre.add_child(column)
	# The badge: a padlock, then the specialist's symbol and name, as large as a title.
	var badge := PanelContainer.new()
	badge.name = "SpecialistBadge"
	badge.theme_type_variation = UiTheme.CARD
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var badge_row := HBoxContainer.new()
	badge_row.add_theme_constant_override(&"separation", 16)
	badge.add_child(badge_row)
	var padlock := Control.new()
	padlock.name = "Padlock"
	padlock.custom_minimum_size = Vector2(64, 72)
	padlock.draw.connect(func() -> void:
		Kit.lock(padlock, padlock.size * 0.5 + Vector2(0, 6), 26.0, true, UiTheme.palette().warn))
	badge_row.add_child(padlock)
	var symbol := Label.new()
	symbol.name = "Symbol"
	symbol.text = String(StationPanels.SPECIALTY_SYMBOLS.get(StringName(required_role), "●"))
	symbol.theme_type_variation = UiTheme.DISPLAY
	symbol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge_row.add_child(symbol)
	var who := Label.new()
	who.name = "Who"
	who.text = String(StationPanels.SPECIALTY_WORDS.get(StringName(required_role), required_role.replace("_", " ")))
	who.theme_type_variation = UiTheme.TITLE
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge_row.add_child(who)
	column.add_child(badge)
	unreadable_label = _label("UnreadableLine", UiTheme.WARN)
	unreadable_label.text = line
	unreadable_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unreadable_label.custom_minimum_size = Vector2(560, 0)
	column.add_child(unreadable_label)
	var grid := GridContainer.new()
	grid.name = "Scrambled"
	grid.columns = 6
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.modulate = Color(1, 1, 1, 0.55)
	column.add_child(grid)
	for i in 12:
		var cell := PanelContainer.new()
		cell.name = "Cell%d" % i
		cell.theme_type_variation = UiTheme.HUD_PANEL
		var glyphs := Label.new()
		glyphs.text = scrambled_text(seed_value * 31 + i, 4 + (i % 3))
		glyphs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyphs.theme_type_variation = UiTheme.MUTED
		cell.add_child(glyphs)
		grid.add_child(cell)
	progress_bar.visible = false
	reset_button.visible = false
	status_label.text = "Your crew member cannot read these controls."
	status_label.theme_type_variation = UiTheme.MUTED
	_seen_status = status_label.text
	cue_text = ""
	_flash_left = 0.0
	_show_cue("", UiTheme.HEADING)
	_update_enabled()


## Scrambled symbols for the wrong-specialist view: `count` characters from a fixed set, the same for the same seed.
## Only characters every UI font has, so it reads as nonsense, not as missing letters.
static func scrambled_text(seed_value: int, count: int) -> String:
	const GLYPHS := "#%&@?~^*=+<>/\\|{}[]§¤¥ÆØÐÞßµ¿¡"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value)
	var out := ""
	for i in count:
		out += GLYPHS[rng.randi_range(0, GLYPHS.length() - 1)]
		if i % 3 == 2 and i < count - 1:
			out += " "
	return out


func set_pending(request_id := "") -> void:
	pending = true
	_pending_id = request_id
	_pending_seconds = 0.0
	_update_enabled()


## Optional services adapter for real puzzles. The generic shell registers no puzzle rules.
func request_host(action: StringName, params := {}) -> ActionResult:
	if unreadable:
		return ActionResult.failure("", &"wrong_specialty", unreadable_label.text if unreadable_label != null else "")
	if services == null or anchor_id.is_empty():
		var missing := ActionResult.failure("", &"not_available_yet")
		accept_host_result(missing)
		return missing
	var request_params := params.duplicate(true)
	request_params["generation"] = fault_generation
	_used_host = true
	set_pending()
	var result := services.request(action, StringName(anchor_id), request_params)
	if result.pending:
		_pending_id = result.request_id
	else:
		if result.ok and (action == &"task_claim" or action == &"task_resume"):
			_claimed = true
		accept_host_result(result)
	return result


func accept_host_result(result: ActionResult, record := {}) -> void:
	if result == null or result.pending:
		return
	pending = false
	_pending_id = ""
	if not record.is_empty():
		apply_host_state(record)
	elif services != null and services.has_game() and not task_id.is_empty():
		var repair: Dictionary = services.state().get("repair")
		var tasks: Dictionary = repair.get("tasks", {})
		if tasks.has(task_id):
			apply_host_state(tasks[task_id])
	# Feedback for the cue bar. A move that worked needs no words (the equipment shows it); one that did not gets a
	# short friendly line. Puzzles replace these with their own.
	if result.ok:
		status_label.text = result.message
		status_label.theme_type_variation = UiTheme.GOOD
	else:
		status_label.text = result.message if not result.message.is_empty() else "Not that one. Try again."
		status_label.theme_type_variation = UiTheme.WARN
	if succeeded:
		status_label.text = "Complete! Great job."
		status_label.theme_type_variation = UiTheme.GOOD
	_update_enabled()


func apply_host_state(record: Dictionary) -> void:
	if not _built:
		return
	fault_generation = int(record.get("fault_generation", fault_generation))
	progress_bar.value = clampf(float(record.get("progress", 0.0)), 0.0, 1.0) * 100.0
	succeeded = progress_bar.value >= 100.0
	if succeeded and _success_time < 0.0:
		_success_time = 0.0
		_stamp.visible = true
	elif not succeeded and _success_time >= 0.0:
		_success_time = -1.0
		_auto_closed = false
		_stamp.visible = false
	_update_enabled()


## Interrupts never pause the simulation. UiRoot owns the critical message above the panel.
func interrupt(_reason := "") -> void:
	if _closing:
		return
	_closing = true
	_release_operator()
	close_requested.emit()


func refresh() -> void:
	if services == null or _operator_id == &"" or _closing:
		return
	var actor := services.local_character()
	if actor == null or actor.id != _operator_id or actor.health <= 0.0:
		interrupt("Crew member unavailable")


func _process(delta: float) -> void:
	if pending:
		_pending_seconds += delta
		if _pending_seconds >= 8.0:
			accept_host_result(ActionResult.failure(_pending_id, &"offline", "No answer yet. Check the connection, then try again."))
	if not _built:
		return
	# Whatever a puzzle writes to status_label is the feedback line: show it for a few seconds, then the cue again.
	if status_label.text != _seen_status:
		_seen_status = status_label.text
		if not _seen_status.is_empty() and not unreadable:
			_flash_left = FLASH_SECONDS
			_show_cue(_seen_status, status_label.theme_type_variation)
	if _flash_left > 0.0 and not succeeded:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_show_cue(cue_text, UiTheme.HEADING)
	if _success_time >= 0.0:
		_success_time += delta
		_stamp.queue_redraw()
		if auto_close_seconds > 0.0 and _success_time >= auto_close_seconds and not _auto_closed and not _closing:
			_auto_closed = true
			close_requested.emit()


func _exit_tree() -> void:
	_release_operator()
	if services != null and is_instance_valid(services):
		for connection in [[services.events.action_resolved, _on_action_resolved],
			[services.events.character_recovered, _on_recovered],
			[services.events.crew_ownership_changed, _on_ownership_changed]]:
			var sig: Signal = connection[0]
			var callback: Callable = connection[1]
			if sig.is_connected(callback):
				sig.disconnect(callback)
		if services.net != null and services.net.host_lost.is_connected(_on_host_lost):
			services.net.host_lost.disconnect(_on_host_lost)


func _release_operator() -> void:
	if _released:
		return
	_released = true
	# Release even a pending claim: reliable requests reach the host in order.
	if _used_host and services != null and is_instance_valid(services) and not anchor_id.is_empty():
		services.request(&"task_release", StringName(anchor_id), {"generation": fault_generation})
	_claimed = false
	operator_released.emit()


func _on_action_resolved(result: ActionResult) -> void:
	if pending and not _pending_id.is_empty() and result.request_id == _pending_id:
		# The host's replicated state is already available before this result arrives.
		if result.ok:
			_claimed = true
		accept_host_result(result)


func _on_recovered(character: StringName, _info: Dictionary) -> void:
	if character == _operator_id:
		interrupt("Crew recovered")


func _on_ownership_changed(character: StringName, peer: int) -> void:
	if character == _operator_id and services != null and peer != services.local_peer():
		interrupt("Crew changed")


func _on_host_lost(reason: String) -> void:
	interrupt(reason)


func _update_enabled() -> void:
	if reset_button != null:
		reset_button.disabled = pending or succeeded
	if play_area != null:
		for node in play_area.find_children("*", "BaseButton", true, false):
			(node as BaseButton).disabled = pending or succeeded


func _update_headings() -> void:
	_title.text = task_title
	_title.tooltip_text = room_title
	_context.text = "%s | Role: %s" % [room_title, "All crew" if required_role == "general" else required_role.replace("_", " ")]
	_instructions.text = instructions
	if help_button != null:
		help_button.visible = not instructions.is_empty() and not unreadable
		_instructions.visible = help_button.visible and help_button.button_pressed
	if role_chip != null:
		# Who can do it: the specialist's symbol and name. Nothing for a repair anyone can do.
		role_chip.visible = required_role != "general" and not unreadable
		var words := String(StationPanels.SPECIALTY_WORDS.get(StringName(required_role), required_role.replace("_", " ")))
		(role_chip.get_node("Role") as Label).text = "%s %s" % [String(StationPanels.SPECIALTY_SYMBOLS.get(StringName(required_role), "●")), words]
		role_chip.tooltip_text = "Only the %s specialist can do this repair." % words


## Fills the cue bar with `text`; a key written as [Enter] becomes a key cap.
func _show_cue(text: String, variation: StringName) -> void:
	if _cue_row == null or (text == _cue_shown and variation == _cue_variation and _cue_row.get_child_count() > 0):
		return
	_cue_shown = text
	_cue_variation = variation
	for child in _cue_row.get_children():
		_cue_row.remove_child(child)
		child.queue_free()
	var rest := text
	while not rest.is_empty():
		var open := rest.find("[")
		var close := rest.find("]", open + 1) if open >= 0 else -1
		if open < 0 or close < 0:
			_cue_row.add_child(_cue_piece(rest, variation))
			break
		if open > 0:
			_cue_row.add_child(_cue_piece(rest.substr(0, open), variation))
		_cue_row.add_child(UiTheme.key_cap(rest.substr(open + 1, close - open - 1)))
		rest = rest.substr(close + 1)
	# The bar keeps its height when it is empty, so the equipment does not jump.
	var keep := Label.new()
	keep.name = "Keep"
	keep.text = " "
	keep.theme_type_variation = UiTheme.HEADING
	_cue_row.add_child(keep)


func _cue_piece(text: String, variation: StringName) -> Label:
	var piece := Label.new()
	piece.text = text.strip_edges()
	piece.theme_type_variation = variation if variation != &"" else UiTheme.HEADING
	if variation == &"":
		piece.add_theme_color_override(&"font_color", UiTheme.palette().text)
	piece.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return piece


## The shared success mark: a large green tick that pops in over the equipment, with a ring of small stars.
func _draw_stamp() -> void:
	if _success_time < 0.0 or play_area == null:
		return
	var area := Rect2(play_area.global_position - _stamp.global_position, play_area.size)
	var centre := area.get_center()
	if _success_time < STAMP_DELAY:
		return
	var grow := 1.0 if wants_less_motion() else clampf((_success_time - STAMP_DELAY) / 0.28, 0.0, 1.0)
	var pop := 1.0 + 0.18 * sin(grow * PI) if grow < 1.0 else 1.0
	var r := minf(area.size.x, area.size.y) * 0.17 * grow * pop
	if r < 2.0:
		return
	_stamp.draw_circle(centre, r * 1.5, Color(0.02, 0.04, 0.05, 0.4 * grow))
	var good: Color = UiTheme.palette().good
	for i in 8:
		var spin := 0.0 if wants_less_motion() else _success_time * 0.5
		var at := centre + Vector2.from_angle(TAU * float(i) / 8.0 + spin) * r * 1.42
		Kit.shape(_stamp, Kit.STAR, at, r * 0.14, good.lightened(0.35), Color(0, 0, 0, 0))
	Kit.tick(_stamp, centre, r)


## A small square header button drawn as a pictogram (kind: &"help", &"reset" or &"close"), with its words in the
## tooltip. Focusable like any button.
func _icon_button(node_name: String, kind: StringName, tip: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.tooltip_text = tip
	button.custom_minimum_size = Vector2(46, 46)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.draw.connect(_draw_icon.bind(button, kind))
	return button


func _label(node_name: String, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _draw_icon(button: Button, kind: StringName) -> void:
	var p := UiTheme.palette()
	var ink: Color = p.text_disabled if button.disabled else p.text
	var mid := button.size * 0.5
	var r := minf(button.size.x, button.size.y) * 0.24
	if kind == &"help":
		Kit.text(button, Rect2(Vector2.ZERO, button.size), "?", ink, 1.3)
	elif kind == &"reset":
		# A three-quarter circle with an arrow head: "start again".
		button.draw_arc(mid, r, -PI * 0.5, PI, 20, ink, 3.0, true)
		var tip_at := mid + Vector2(0, -r)
		button.draw_colored_polygon(PackedVector2Array([tip_at + Vector2(-r * 0.75, 0), tip_at + Vector2(r * 0.15, -r * 0.6),
			tip_at + Vector2(r * 0.15, r * 0.6)]), ink)
	else:
		button.draw_line(mid - Vector2(r, r), mid + Vector2(r, r), ink, 3.5, true)
		button.draw_line(mid + Vector2(r, -r), mid - Vector2(r, -r), ink, 3.5, true)
