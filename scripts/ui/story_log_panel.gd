class_name StoryLogPanel
extends UiPanel
## The colony journal (L): what the tutorial asks now, the campaign goal, and the optional story of the first crew
## (Prompt 12). It only reads state.campaign and state.discoveries and sends ordinary requests:
##   * "Show a hint" (local), "Answer here" opens the question of a knowledge step (QuizPanel finds the station in reach),
##   * "Remind me" asks the host for a reminder run of a finished stage (`tutorial_replay`),
##   * the story lists each discovery with its clue records: found ones with their text, fiction label and the real
##     science they touch (source ids from the register), missing ones with where to look. Solving it is optional.

## The presenter that owns the hint count, or null (then the panel counts its own hint requests).
var presenter: TutorialPresenter
var answer_button: Button
var hint_button: Button
var replay_option: OptionButton
var replay_button: Button
var stop_button: Button

var _built := false
var _close: Button
var _scroll: ScrollContainer
var _stage_label: Label
var _objective_label: Label
var _cue_label: Label
var _explain_label: Label
var _hint_label: Label
var _answer_note: Label
var _replay_note: Label
var _goal_box: VBoxContainer
var _story_box: VBoxContainer
var _message: Label
var _local_hints := 0
var _story_key := ""
var _goal_key := ""
var _replay_key := ""


func setup(p_services: GameServices) -> void:
	if _built:
		return
	super.setup(p_services)
	_built = true
	name = "StoryLogPanel"
	theme_type_variation = UiTheme.PANEL
	max_width = 1240.0
	_build()
	refresh()


func panel_title() -> String:
	return "Colony journal"


func first_focus() -> Control:
	if hint_button != null and hint_button.visible and not hint_button.disabled:
		return hint_button
	return _close


func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "✎  Colony journal"
	title.theme_type_variation = UiTheme.TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_close = Button.new()
	_close.name = "Close"
	_close.text = "Close"
	_close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(_close)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 320)
	column.add_child(_scroll)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 8)
	_scroll.add_child(body)

	# ---- now
	_heading(body, "Now")
	_stage_label = _text(body, "", UiTheme.HEADING)
	_objective_label = _text(body, "")
	_cue_label = _text(body, "", UiTheme.GOOD)
	_explain_label = _text(body, "", UiTheme.MUTED)
	_hint_label = _text(body, "", UiTheme.WARN)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	body.add_child(row)
	hint_button = Button.new()
	hint_button.name = "Hint"
	hint_button.text = "Show a hint"
	hint_button.pressed.connect(_on_hint)
	row.add_child(hint_button)
	answer_button = Button.new()
	answer_button.name = "Answer"
	answer_button.text = "Answer the question here"
	answer_button.theme_type_variation = UiTheme.PRIMARY_BUTTON
	answer_button.pressed.connect(_on_answer)
	row.add_child(answer_button)
	_answer_note = _text(body, "", UiTheme.MUTED)

	# ---- reminders
	_heading(body, "Reminders")
	_text(body, "Replay a stage you have finished, as a reminder. Nothing in a reminder counts twice.", UiTheme.MUTED)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override(&"separation", 12)
	body.add_child(rrow)
	replay_option = OptionButton.new()
	replay_option.name = "ReplayStage"
	replay_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rrow.add_child(replay_option)
	replay_button = Button.new()
	replay_button.name = "Replay"
	replay_button.text = "Remind me"
	replay_button.pressed.connect(_on_replay)
	rrow.add_child(replay_button)
	stop_button = Button.new()
	stop_button.name = "StopReplay"
	stop_button.text = "Stop reminder"
	stop_button.pressed.connect(_on_stop_replay)
	rrow.add_child(stop_button)
	_replay_note = _text(body, "", UiTheme.MUTED)

	# ---- campaign goal
	_heading(body, "Colony goal")
	_text(body, String((TutorialSystem.data().get("certification", {}) as Dictionary).get("words", "")), UiTheme.MUTED)
	_goal_box = VBoxContainer.new()
	_goal_box.name = "Goal"
	body.add_child(_goal_box)

	# ---- story
	_heading(body, "The first crew's story (optional)")
	_text(body, String(TutorialSystem.lore().get("premise", "")))
	_text(body, "Solving it is never needed. Records hide in old consoles and broken machines: read them, or inspect salvage donors.", UiTheme.MUTED)
	_story_box = VBoxContainer.new()
	_story_box.name = "Story"
	_story_box.add_theme_constant_override(&"separation", 6)
	body.add_child(_story_box)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.visible = false
	column.add_child(_message)
	var keys := Label.new()
	keys.theme_type_variation = UiTheme.MUTED
	keys.text = "Press Esc to close."
	column.add_child(keys)


func _heading(parent: Control, text: String) -> Label:
	var l := _text(parent, text, UiTheme.HEADING)
	return l


func _text(parent: Control, text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.visible = text != ""
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != &"":
		l.theme_type_variation = variation
	parent.add_child(l)
	return l


func _show(l: Label, text: String) -> void:
	l.text = text
	l.visible = text != ""


func refresh() -> void:
	if not _built or services == null or not services.has_game():
		return
	var st := services.state()
	var idle := presenter.idle_seconds if presenter != null else 0.0
	var asked := presenter.requested_hints if presenter != null else _local_hints
	var v := TutorialPresenter.view(services, idle, asked)
	_show(_stage_label, String(v.get("title", "")))
	_show(_objective_label, String(v.get("objective", "")) if String(v.get("objective", "")) != "" else String(v.get("progress", "")))
	_show(_cue_label, String(v.get("cue", "")))
	var o := TutorialSystem.current_objective(st)
	var explain := String(v.get("explain", ""))
	if explain == "" and not o.is_empty() and String(o.get("explain", "")) != "":
		explain = "✓ The colony already knows this."
	_show(_explain_label, explain)
	var hints: PackedStringArray = v.get("hints", PackedStringArray())
	var lines := PackedStringArray()
	for h in hints:
		lines.append("Hint: " + h)
	_show(_hint_label, "\n".join(lines))
	hint_button.visible = not o.is_empty()
	hint_button.disabled = hints.size() >= int(v.get("hints_total", 0))
	hint_button.text = "Show a hint" if not hint_button.disabled else "No more hints"
	_refresh_answer(st, o)
	_refresh_replay(st)
	_refresh_goal(st)
	_refresh_story(st)


# ---------------------------------------------------------------- now

## The question of the open step, or "" when the step is not a question.
static func question_of(o: Dictionary) -> String:
	if String(o.get("kind", "")) != "knowledge":
		return ""
	return String((o.get("params", {}) as Dictionary).get("question", o.get("question", "")))


## A station within reach where `question_id` can be answered now, or &"".
static func answer_station(p_services: GameServices, question_id: String) -> StringName:
	var me := p_services.local_character()
	if me == null or question_id == "":
		return &""
	var st := p_services.state()
	var q := ProgressionSystem.question(StringName(question_id))
	var best: StringName = &""
	var best_d := INF
	for sid: String in st.stations:
		if not ProgressionSystem.answer_station_ok(st, q, StringName(sid)):
			continue
		var d := me.position.distance_to(CharacterState._v3((st.stations[sid] as Dictionary).get("position", [0, 0, 0])))
		if d <= p_services.config.interact_distance_m and d < best_d:
			best_d = d
			best = StringName(sid)
	return best


func _refresh_answer(st: ColonyState, o: Dictionary) -> void:
	var q := question_of(o)
	answer_button.visible = q != "" and not st.knowledge.has(q)
	_answer_note.visible = false
	if not answer_button.visible:
		return
	var where := answer_station(services, q)
	answer_button.disabled = where == &""
	if where == &"":
		_show(_answer_note, "To answer, stand at %s and open the journal there." % ProgressionSystem.answer_place_words(ProgressionSystem.question(StringName(q))))
	else:
		_show(_answer_note, "")


func _on_hint() -> void:
	if presenter != null:
		presenter.request_hint()
	else:
		_local_hints += 1
	refresh()


func _on_answer() -> void:
	var q := question_of(TutorialSystem.current_objective(services.state()))
	if q == "":
		return
	var quiz := QuizPanel.new()
	var ids: Array[StringName] = [StringName(q)]
	quiz.question_ids = ids
	quiz.heading = "Tutorial question"
	open_requested.emit(quiz)


# ---------------------------------------------------------------- reminders

func _refresh_replay(st: ColonyState) -> void:
	var done := PackedStringArray()
	for s: Dictionary in TutorialSystem.stages():
		if TutorialSystem.is_stage_completed(st, int(s.n)):
			done.append(str(int(s.n)))
	var r := TutorialSystem.replay_of(st)
	var key := ",".join(done) + "|" + str(r.get("stage", 0))
	if key != _replay_key:
		_replay_key = key
		var keep := replay_option.get_selected_id()
		replay_option.clear()
		for n_text in done:
			var n := int(n_text)
			replay_option.add_item("Stage %d: %s" % [n, String(TutorialSystem.stage_def(n).get("title", ""))], n)
		if keep >= 0 and replay_option.get_item_index(keep) >= 0:
			replay_option.select(replay_option.get_item_index(keep))
	replay_option.disabled = done.is_empty()
	replay_button.disabled = done.is_empty() or not r.is_empty()
	stop_button.visible = not r.is_empty()
	if not r.is_empty():
		var ro := TutorialSystem.replay_objective(st)
		_show(_replay_note, "Reminder running: %s. Next: %s" % [String(TutorialSystem.stage_def(int(r.stage)).get("title", "")),
			TutorialSystem.objective_text(ro, TutorialPresenter.switching_disabled(services)) if not ro.is_empty() else "finishing"])
	elif done.is_empty():
		_show(_replay_note, "Finish a stage first; then you can replay it here.")
	else:
		_show(_replay_note, "")


func _on_replay() -> void:
	var n := replay_option.get_selected_id()
	if n <= 0:
		return
	_send(&"tutorial_replay", {"stage": n})


func _on_stop_replay() -> void:
	_send(&"tutorial_replay", {"stage": 0})


func _send(action: StringName, params: Dictionary) -> void:
	var result := services.request(action, &"", params)
	if result.pending:
		_message.text = "Asked the host…"
	elif result.ok:
		_message.text = String(result.changes.get("text", ""))
	else:
		_message.text = "✖ " + result.message
	_message.visible = _message.text != ""
	refresh()


# ---------------------------------------------------------------- campaign goal

func _refresh_goal(st: ColonyState) -> void:
	var cert := TutorialSystem.certification_of(st)
	var ops := TutorialSystem.sectors_operating(st)
	var key := "%s|%s|%d|%d" % [String(cert.get("status", "")), str(ops), roundi(100.0 * TutorialSystem.certification_share(st)), (cert.get("resets", []) as Array).size()]
	if key == _goal_key:
		return
	_goal_key = key
	for child in _goal_box.get_children():
		child.queue_free()
	var tips: Dictionary = TutorialSystem.data().get("campaign_tips", {})
	for sector: String in ProgressionSystem.SECTORS:
		var ok := bool(ops.get(sector, false))
		_text(_goal_box, ("✓ " if ok else "· ") + (ProgressionSystem.sector_name(sector) + " works" if ok else String(tips.get(sector, sector))), UiTheme.GOOD if ok else &"")
	var comms_ok := bool(ops.get("comms", false))
	_text(_goal_box, "✓ Communications work" if comms_ok else "· " + String(tips.get("comms", "Communications")), UiTheme.GOOD if comms_ok else &"")
	var status := String(cert.get("status", "locked"))
	var line := ""
	match status:
		"locked":
			line = "The certification sol starts after the tutorial."
		"waiting":
			line = "The certification sol starts when every line above has a ✓."
		"paused_reserve":
			line = "The certification sol waits: a store is empty. Refill it and the sol starts again."
		"running":
			line = "Certification sol: %d %% done. Keep battery, water, oxygen and food above zero, and nobody needing a rescue." % roundi(100.0 * TutorialSystem.certification_share(st))
		"complete":
			line = "✓ First campaign milestone complete: a sustainable colony. Everything keeps working; explore as long as you like."
	_text(_goal_box, line, UiTheme.GOOD if status == "complete" else UiTheme.HEADING)
	var resets: Array = cert.get("resets", [])
	if not resets.is_empty() and status != "complete":
		var last: Dictionary = resets[resets.size() - 1]
		var why := "a rescue" if String(last.get("reason", "")) == "recovery" else "an empty %s store" % String(TutorialSystem.RESERVE_WORDS.get(StringName(String(last.get("detail", ""))), "supply"))
		_text(_goal_box, "Last restart: %s. Your progress was kept." % why, UiTheme.MUTED)


# ---------------------------------------------------------------- story

func _refresh_story(st: ColonyState) -> void:
	var key := str(st.discoveries.size())
	if key == _story_key:
		return
	_story_key = key
	for child in _story_box.get_children():
		child.queue_free()
	var label := String(TutorialSystem.lore().get("fiction_label", "Fiction."))
	var found_count := 0
	for r: Dictionary in TutorialSystem.records():
		if TutorialSystem.is_found(st, String(r.id)):
			found_count += 1
	_text(_story_box, "Records found: %d of %d." % [found_count, TutorialSystem.records().size()], UiTheme.MUTED)
	for d: Dictionary in TutorialSystem.discovery_defs():
		var did := String(d.get("id", ""))
		var got := TutorialSystem.is_found(st, did)
		_text(_story_box, ("✓ " if got else "? ") + String(d.get("title", did)), UiTheme.HEADING)
		if got:
			_text(_story_box, String(d.get("text", "")))
		for clue in d.get("clues", []):
			var r := TutorialSystem.record_def(String(clue))
			if r.is_empty():
				continue
			if TutorialSystem.is_found(st, String(clue)):
				_text(_story_box, "✎ %s: %s" % [String(r.get("title", "")), String(r.get("text", ""))])
				_text(_story_box, label, UiTheme.MUTED)
				var ids: Array = r.get("source_ids", [])
				var science := String(r.get("science", ""))
				_text(_story_box, "Science: %s%s" % [science, "" if ids.is_empty() else " Sources: %s (Shift + Backspace)." % ", ".join(PackedStringArray(ids))], UiTheme.MUTED)
			else:
				_text(_story_box, "? A record still waits at %s." % String(r.get("place", "somewhere in the colony")), UiTheme.MUTED)
		if d.has("requires") and not got:
			_text(_story_box, "Find the four discoveries above to solve it.", UiTheme.MUTED)
	var handover := TutorialSystem.record_def("rec_handover")
	if not handover.is_empty():
		if TutorialSystem.is_found(st, "rec_handover"):
			_text(_story_box, "✎ %s: %s" % [String(handover.title), String(handover.text)])
			_text(_story_box, label, UiTheme.MUTED)
		else:
			_text(_story_box, "? One more record waits at %s." % String(handover.get("place", "a console")), UiTheme.MUTED)


## Every line of the story section, for tests.
func story_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _story_box.get_children():
		if child is Label and not child.is_queued_for_deletion():
			out.append((child as Label).text)
	return out
