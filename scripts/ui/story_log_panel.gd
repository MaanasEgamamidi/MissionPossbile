class_name StoryLogPanel
extends UiPanel
## The colony journal (L), as five boxes with a pictogram and a heading each: what Mission Control asks now (with the
## step's checklist), Mission Control's log, hearing a finished step again, the colony goal, and the optional story of
## the first crew. It only reads state.campaign and state.discoveries and sends
## ordinary requests:
##   * "Show a hint" (local), "Answer here" opens the question of a knowledge step (QuizPanel finds the station in reach;
##     the whiteboard tutorial has no question steps, so it stays hidden there),
##   * "Remind me" asks the host to repeat Mission Control's lines of a finished step (`tutorial_replay`; nothing
##     counts twice),
##   * the story lists each discovery with its clue records: found ones with their text, fiction label and the real
##     science they touch (source ids from the register), missing ones with where to look. Solving it is optional.

const MenuKit := preload("res://scripts/ui/menu_kit.gd")

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
var _list_label: Label
var _log_label: Label
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
	column.add_theme_constant_override(&"separation", 10)
	margin.add_child(column)
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override(&"separation", 12)
	column.add_child(header)
	header.add_child(MenuKit.scaled_picture(&"book", 34.0, &"heading"))
	var title := Label.new()
	title.text = "Colony journal"
	title.theme_type_variation = UiTheme.TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(UiTheme.key_cap("Esc"))
	_close = Button.new()
	_close.name = "Close"
	_close.text = "Close"
	_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(_close)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	_scroll.custom_minimum_size = Vector2(0, 320)
	column.add_child(_scroll)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 10)
	_scroll.add_child(body)

	# ---- now
	var now := _section(body, "Now", &"play")
	_stage_label = _text(now, "")
	_objective_label = _text(now, "")
	_cue_label = _text(now, "", UiTheme.GOOD)
	_explain_label = _text(now, "", UiTheme.MUTED)
	_hint_label = _text(now, "", UiTheme.WARN)
	_list_label = _text(now, "")
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	now.add_child(row)
	hint_button = Button.new()
	hint_button.name = "Hint"
	hint_button.text = "Show a hint"
	hint_button.icon = MenuKit.scaled_pic(&"flash", 22.0)
	hint_button.pressed.connect(_on_hint)
	row.add_child(hint_button)
	answer_button = Button.new()
	answer_button.name = "Answer"
	answer_button.text = "Answer the question"
	answer_button.icon = MenuKit.scaled_pic(&"bubble", 22.0, &"primary_text")
	answer_button.theme_type_variation = UiTheme.PRIMARY_BUTTON
	answer_button.pressed.connect(_on_answer)
	row.add_child(answer_button)
	_answer_note = _text(now, "", UiTheme.MUTED)

	# ---- Mission Control's log
	_log_label = _text(_section(body, "%s says" % TutorialSystem.speaker(), &"bubble"), "", UiTheme.MUTED)

	# ---- reminders
	var reminders := _section(body, "Hear a step again", &"reset")
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override(&"separation", 12)
	reminders.add_child(rrow)
	replay_option = OptionButton.new()
	replay_option.name = "ReplayStage"
	replay_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rrow.add_child(replay_option)
	replay_button = Button.new()
	replay_button.name = "Replay"
	replay_button.text = "Remind me"
	replay_button.icon = MenuKit.scaled_pic(&"sound", 22.0)
	replay_button.pressed.connect(_on_replay)
	rrow.add_child(replay_button)
	stop_button = Button.new()
	stop_button.name = "StopReplay"
	stop_button.text = "Stop reminder"
	stop_button.pressed.connect(_on_stop_replay)
	rrow.add_child(stop_button)
	_replay_note = _text(reminders, "", UiTheme.MUTED)

	# ---- campaign goal
	var goal := _section(body, "Colony goal", &"star")
	_text(goal, String((TutorialSystem.data().get("certification", {}) as Dictionary).get("words", "")), UiTheme.MUTED)
	_goal_box = VBoxContainer.new()
	_goal_box.name = "Goal"
	goal.add_child(_goal_box)

	# ---- story
	var story := _section(body, "The first crew's story (optional)", &"pencil")
	_text(story, String(TutorialSystem.lore().get("premise", "")))
	_text(story, "Solving it is never needed. Records hide in old consoles and broken machines: read them, or inspect salvage donors.", UiTheme.MUTED)
	_story_box = VBoxContainer.new()
	_story_box.name = "Story"
	_story_box.add_theme_constant_override(&"separation", 6)
	story.add_child(_story_box)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.visible = false
	column.add_child(_message)


## A section of the journal: a box with a pictogram and a heading. Returns the column its lines go in.
func _section(parent: Control, text: String, kind: StringName) -> VBoxContainer:
	var card := PanelContainer.new()
	card.name = "Section_" + String(kind)
	card.theme_type_variation = UiTheme.CARD
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 10)
	col.add_child(head)
	head.add_child(MenuKit.scaled_picture(kind, 26.0, &"heading"))
	var l := Label.new()
	l.text = text
	l.theme_type_variation = UiTheme.HEADING
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)
	return col


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
	var now_line := String(v.get("objective", ""))
	if String(v.get("progress", "")) != "":
		now_line = (now_line + "\n" if now_line != "" else "") + String(v.get("progress", ""))
	_show(_objective_label, now_line)
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
	_show(_list_label, "\n".join(v.get("list", PackedStringArray()) as PackedStringArray))
	var log := PackedStringArray()
	for entry: Variant in TutorialSystem.mission_log(st):
		if entry is Dictionary:
			log.append("“%s”" % String((entry as Dictionary).get("text", "")))
	_show(_log_label, "\n".join(log.slice(maxi(0, log.size() - 12))) if not log.is_empty() else "Nothing yet.")
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
	var key := ",".join(done)
	if key != _replay_key:
		_replay_key = key
		var keep := replay_option.get_selected_id()
		replay_option.clear()
		for n_text in done:
			var n := int(n_text)
			replay_option.add_item("Step %d: %s" % [n, String(TutorialSystem.stage_def(n).get("title", ""))], n)
		if keep >= 0 and replay_option.get_item_index(keep) >= 0:
			replay_option.select(replay_option.get_item_index(keep))
	replay_option.disabled = done.is_empty()
	replay_button.disabled = done.is_empty()
	stop_button.visible = false
	if done.is_empty():
		_show(_replay_note, "Finish a step first.")
	elif _replay_note.text.begins_with("Finish"):
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
		_message.text = "One moment…"
	elif result.ok and action == &"tutorial_replay":
		_message.text = ""
		_show(_replay_note, String(result.changes.get("text", "")))
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
			line = "The certification sol starts once the base is operational."
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
