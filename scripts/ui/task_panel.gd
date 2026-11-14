class_name TaskPanel
extends UiPanel
## Shared repair frame. The host owns progress; this frame never changes colony state.
## Concrete puzzles populate play_area and send discrete, host-validated moves.

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
var play_area: VBoxContainer
var progress_bar: ProgressBar
var status_label: Label
var reset_button: Button
var cancel_button: Button

var _title: Label
var _context: Label
var _instructions: Label
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
	var scroll := ScrollContainer.new()
	scroll.name = "TaskScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_title = _label("Title", UiTheme.TITLE)
	body.add_child(_title)
	_context = _label("RoomAndRole", UiTheme.MUTED)
	body.add_child(_context)
	_instructions = _label("Instructions")
	body.add_child(_instructions)
	play_area = VBoxContainer.new()
	play_area.name = "PlayArea"
	play_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(play_area)
	progress_bar = ProgressBar.new()
	progress_bar.name = "HostProgress"
	progress_bar.max_value = 100.0
	progress_bar.step = 0.0
	progress_bar.theme_type_variation = UiTheme.BAR_COOL
	body.add_child(progress_bar)
	status_label = _label("Status", UiTheme.MUTED)
	status_label.text = "Ready. Progress is confirmed by the host."
	body.add_child(status_label)
	# Vertical actions still fit at 720p with maximum text size.
	reset_button = Button.new()
	reset_button.name = "Reset"
	reset_button.text = "Reset puzzle"
	reset_button.pressed.connect(func() -> void:
		if not pending and not succeeded:
			reset_requested.emit())
	body.add_child(reset_button)
	cancel_button = Button.new()
	cancel_button.name = "Cancel"
	cancel_button.text = "Cancel / close (Esc)"
	cancel_button.pressed.connect(func() -> void: close_requested.emit())
	# Cancel remains reachable even when enlarged content needs scrolling.
	frame.add_child(cancel_button)
	var live_note := _label("WorldContinues", UiTheme.MUTED)
	live_note.text = "The colony keeps running while this panel is open."
	body.add_child(live_note)
	_update_headings()
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


func first_focus() -> Control:
	return cancel_button if pending else super.first_focus()


## A puzzle emits only discrete moves; no completion boolean is accepted by this frame.
func submit_move(move: Dictionary) -> void:
	if pending or succeeded or _closing:
		return
	set_pending()
	move_requested.emit(move.duplicate(true))


func set_pending(request_id := "") -> void:
	pending = true
	_pending_id = request_id
	_pending_seconds = 0.0
	status_label.text = "Waiting for host validation..."
	status_label.theme_type_variation = UiTheme.MUTED
	_update_enabled()


## Optional services adapter for real puzzles. The generic shell registers no puzzle rules.
func request_host(action: StringName, params := {}) -> ActionResult:
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
	status_label.text = ("Validated. " if result.ok else "Move rejected. ") + result.message
	status_label.theme_type_variation = UiTheme.GOOD if result.ok else UiTheme.WARN
	if succeeded:
		status_label.text = "Complete - repair confirmed by the host."
	_update_enabled()


func apply_host_state(record: Dictionary) -> void:
	if not _built:
		return
	fault_generation = int(record.get("fault_generation", fault_generation))
	progress_bar.value = clampf(float(record.get("progress", 0.0)), 0.0, 1.0) * 100.0
	succeeded = progress_bar.value >= 100.0
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
			accept_host_result(ActionResult.failure(_pending_id, &"offline", "No answer yet. Check the connection, then retry or cancel."))


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
	_context.text = "%s | Role: %s" % [room_title, "All crew" if required_role == "general" else required_role.replace("_", " ")]
	_instructions.text = instructions


func _label(node_name: String, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
