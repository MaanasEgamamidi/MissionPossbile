class_name QuizPanel
extends UiPanel
## Knowledge questions (Prompt 08): each question shows the version the host chooses now, three answers, and the
## feedback after an answer. A right answer is recorded once for the whole colony. A wrong answer shows the explanation
## and the host gives a changed version (retry variant) next time; nobody loses health.
## Questions are answered at the colony computer or an install station of their sector (a few only at one station,
## where the readings they ask about are on screen). The panel finds the right station within reach; it only asks the
## host (`answer_question`) and never edits state.

## Question ids shown, in order.
var question_ids: Array[StringName] = []
## Header line.
var heading := "Questions"
## Station the panel was opened at (empty: the nearest suitable station within reach is used).
var station_id: StringName = &""
## Answer buttons of each question id (3 each).
var answer_buttons: Dictionary = {}

var _built := false
var _scroll: ScrollContainer
var _body: VBoxContainer
var _close_button: Button
var _status: Dictionary = {}
var _texts: Dictionary = {}
var _readings: Dictionary = {}
var _places: Dictionary = {}
var _feedback: Dictionary = {}
var _feedback_text: Dictionary = {}
var _waiting: Dictionary = {}


## A quiz for the questions of one upgrade card.
static func for_card(def: UpgradeDefinition, at_station: StringName = &"") -> QuizPanel:
	var q := QuizPanel.new()
	q.question_ids = def.questions.duplicate()
	q.heading = "Questions for “%s”" % def.title
	q.station_id = at_station
	return q


func setup(p_services: GameServices) -> void:
	if _built:
		return
	super.setup(p_services)
	_built = true
	name = "Quiz"
	theme_type_variation = UiTheme.PANEL
	_build()
	refresh()


func panel_title() -> String:
	return "Questions"


func first_focus() -> Control:
	for id in question_ids:
		for b: Button in answer_buttons.get(id, []):
			if b.is_visible_in_tree() and not b.disabled:
				return b
	return _close_button


## The question text shown now for `id`.
func question_text(id: StringName) -> String:
	var l := _texts.get(id) as Label
	return l.text if l != null else ""


## The feedback shown under `id` after the last answer ("✓ Right! …" / "✖ Not quite. …"), or "".
func feedback_text(id: StringName) -> String:
	return String(_feedback_text.get(id, ""))


## The status line of `id` ("✓ The colony knows this" / "○ Not answered yet").
func status_text(id: StringName) -> String:
	var l := _status.get(id) as Label
	return l.text if l != null else ""


## The "where to answer" line of `id`, or "" when it is hidden.
func place_text(id: StringName) -> String:
	var l := _places.get(id) as Label
	return l.text if l != null and l.visible else ""


## The live readings line of `id`, or "" when it has none.
func readings_text(id: StringName) -> String:
	var l := _readings.get(id) as Label
	return l.text if l != null and l.visible else ""


## The station where `id` would be answered from here, or &"" when none is within reach.
func answer_station(id: StringName) -> StringName:
	var st := _state()
	var me := services.local_character() if services != null else null
	if st == null or me == null:
		return &""
	var q := ProgressionSystem.question(id)
	var reach := services.config.interact_distance_m
	var best: StringName = &""
	var best_d := INF
	for sid: String in st.stations:
		if not ProgressionSystem.answer_station_ok(st, q, StringName(sid)):
			continue
		var d := me.position.distance_to(CharacterState._v3((st.stations[sid] as Dictionary).get("position", [0, 0, 0])))
		if StringName(sid) == station_id:
			d = -1.0
		if d <= reach and d < best_d:
			best_d = d
			best = StringName(sid)
	return best


## Sends answer `choice` (0..2) to question `id`, as pressing its button does.
func answer(id: StringName, choice: int) -> ActionResult:
	var where := answer_station(id)
	var result := services.request(&"answer_question", where, {"question_id": String(id), "choice": choice})
	if result.pending:
		_waiting[result.request_id] = id
		if not services.events.action_resolved.is_connected(_on_action_resolved):
			services.events.action_resolved.connect(_on_action_resolved)
		_feedback_text[id] = "Asked the host…"
		refresh()
	else:
		_show_result(id, result)
	return result


func refresh() -> void:
	if not _built or services == null or not services.has_game():
		return
	var st := _state()
	for id in question_ids:
		var q := ProgressionSystem.question(id)
		var known := ProgressionSystem.is_known(st, id)
		var status := _status[id] as Label
		var buttons: Array = answer_buttons[id]
		var where := answer_station(id)
		if known:
			status.text = "✓ The colony knows this (answered by %s)." % _who((st.knowledge[String(id)] as Dictionary).get("by", ""))
			status.theme_type_variation = UiTheme.GOOD
			var rec: Dictionary = st.knowledge[String(id)]
			var variants: Array = q.get("variants", [])
			var v: Dictionary = variants[clampi(int(rec.get("variant", 0)), 0, variants.size() - 1)] if not variants.is_empty() else {}
			(_texts[id] as Label).text = "%s\n%s" % [String(v.get("text", "")), String(v.get("explanation", ""))]
			for b: Button in buttons:
				b.visible = false
		else:
			var guided := String(q.get("changed_from", ""))
			var locked := guided != "" and not ProgressionSystem.is_known(st, StringName(guided))
			var tries := int(((ProgressionSystem.progress_of(st)["quiz"] as Dictionary).get(String(id), {}) as Dictionary).get("wrong", 0))
			status.text = "○ Not answered yet." if tries == 0 else "○ Not answered yet. This is a new version of the question (try %d)." % (tries + 1)
			status.theme_type_variation = UiTheme.MUTED
			var v := ProgressionSystem.current_variant(st, id)
			var answers: Array = v.get("answers", [])
			if locked:
				(_texts[id] as Label).text = "First answer the guided question “%s”. This one then shows a different situation." % ProgressionSystem.question_title(StringName(guided))
			else:
				(_texts[id] as Label).text = String(v.get("text", ""))
			for i in buttons.size():
				var b := buttons[i] as Button
				b.visible = not locked and i < answers.size()
				if i < answers.size():
					b.text = "%s  %s" % [["A", "B", "C"][i], String(answers[i])]
				b.disabled = where == &""
		var place := _places[id] as Label
		if known:
			place.visible = false
		else:
			place.visible = true
			place.text = "✓ Answering at the %s." % _station_words(where) if where != &"" else "! Go to %s to answer this." % ProgressionSystem.answer_place_words(q)
			place.theme_type_variation = UiTheme.GOOD if where != &"" else UiTheme.WARN
		var readings := _readings[id] as Label
		readings.text = _readings_text(st, String(q.get("readings", "")))
		readings.visible = not readings.text.is_empty() and not known
		var fb := _feedback[id] as Label
		fb.text = feedback_text(id)
		fb.visible = not fb.text.is_empty()


# ---------------------------------------------------------------- building

func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = heading
	title.theme_type_variation = UiTheme.TITLE
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(ExplainButton.make("upgrades", "Answer to unlock upgrade cards. A right answer counts for the whole colony. A wrong answer is fine: read why, then try the new version. Nobody loses health."))
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(_close_button)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	for id in question_ids:
		_body.add_child(_make_question(id))


func _make_question(id: StringName) -> Control:
	var card := PanelContainer.new()
	card.name = "Question_%s" % id
	card.theme_type_variation = UiTheme.CARD
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	card.add_child(box)
	var q := ProgressionSystem.question(id)
	box.add_child(_label("%s %s" % [ProgressionSystem.sector_symbol(String(q.get("sector", ""))), ProgressionSystem.question_title(id)], UiTheme.HEADING))
	_status[id] = _label("", UiTheme.MUTED)
	box.add_child(_status[id])
	_readings[id] = _label("", UiTheme.MUTED)
	box.add_child(_readings[id])
	_texts[id] = _label("", &"")
	box.add_child(_texts[id])
	var buttons: Array = []
	for i in 3:
		var b := Button.new()
		b.name = "Answer_%d" % i
		b.focus_mode = Control.FOCUS_ALL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: answer(id, i))
		box.add_child(b)
		buttons.append(b)
	answer_buttons[id] = buttons
	_places[id] = _label("", UiTheme.MUTED)
	box.add_child(_places[id])
	_feedback[id] = _label("", &"")
	box.add_child(_feedback[id])
	return card


func _label(text: String, variation: StringName) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != &"":
		l.theme_type_variation = variation
	return l


# ---------------------------------------------------------------- answers

func _on_action_resolved(result: ActionResult) -> void:
	if _waiting.has(result.request_id):
		var id: StringName = _waiting[result.request_id]
		_waiting.erase(result.request_id)
		_show_result(id, result)


func _show_result(id: StringName, result: ActionResult) -> void:
	var fb := _feedback.get(id) as Label
	if result.ok:
		_feedback_text[id] = StationPanel.answer_text(result)
		if fb != null:
			fb.theme_type_variation = UiTheme.GOOD if bool(result.changes.get("correct", false)) else UiTheme.WARN
	else:
		_feedback_text[id] = "✖ " + result.message
		if fb != null:
			fb.theme_type_variation = UiTheme.URGENT
	refresh()


## Live readings for questions about what a station's panel shows.
func _readings_text(st: ColonyState, kind: String) -> String:
	match kind:
		"power":
			var load := StationPanel.colony_load_kw(st, services.balance)
			return "Readings now: the sun gives %s kW, the colony asks for %s kW, the battery %s." % [StationPanel.num(st.solar_kw),
				StationPanel.num(load), StationPanel.signed_kw(st.battery_kw)]
		"lifesupport":
			var kpa := StationPanel.cabin_kpa(st, services.balance)
			return "Readings now: oxygen reserve %s kg (tanks), cabin oxygen %s kPa, cabin pressure %s kPa." % [StationPanel.num(st.store(&"oxygen_kg")),
				StationPanel.num(float(kpa.o2)), StationPanel.num(float(kpa.total))]
	return ""


func _station_words(id: StringName) -> String:
	var st := _state()
	var kind := String((st.stations.get(String(id), {}) as Dictionary).get("kind", ""))
	return StationPanels.name_of(kind).to_lower()


func _who(id: Variant) -> String:
	var c := _state().character(StringName(String(id)))
	return c.display_name if c != null else "the crew"


func _state() -> ColonyState:
	return services.state() if services != null and services.has_game() else null


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		var vp := get_viewport()
		if vp != null and not vp.size_changed.is_connected(_fit_to_screen):
			vp.size_changed.connect(_fit_to_screen)
		_fit_to_screen()
	elif what == NOTIFICATION_EXIT_TREE:
		var vp := get_viewport()
		if vp != null and vp.size_changed.is_connected(_fit_to_screen):
			vp.size_changed.disconnect(_fit_to_screen)


func _fit_to_screen() -> void:
	if _scroll == null or not is_inside_tree():
		return
	var screen := get_viewport_rect().size
	_scroll.custom_minimum_size = Vector2(minf(900.0, screen.x * 0.65), minf(480.0, screen.y * 0.5))
