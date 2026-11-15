class_name QuizPanel
extends UiPanel
## Knowledge questions (Prompt 08; simplified in the UI overhaul, 2026-11-15): each question shows the version the host
## chooses now in large text, its three answers as large buttons (A, B, C) and, after an answer, a short friendly
## result ("Right!" / "Not quite. Try again!") with the explanation under it.
## A right answer is recorded once for the whole colony. A wrong answer shows the explanation and the host gives a
## changed version (retry variant) next time; nobody loses health. The longer introduction is behind "?".
## Questions are answered at the colony computer or an install station of their sector (a few only at one station,
## where the readings they ask about are on screen). The panel finds the right station within reach; it only asks the
## host (`answer_question`) and never edits state.

const MenuKit := preload("res://scripts/ui/menu_kit.gd")
const HudKit := preload("res://scripts/ui/hud/hud_kit.gd")
const LETTERS: Array[String] = ["A", "B", "C"]
## How much larger than normal text the question and its answers are.
const QUESTION_SCALE := 1.3
const ANSWER_SCALE := 1.15

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
var _help_button: Button
var _help_box: Control
var _status: Dictionary = {}
var _texts: Dictionary = {}
var _explains: Dictionary = {}
var _readings: Dictionary = {}
var _places: Dictionary = {}
var _feedback: Dictionary = {}          # id -> {"box", "mark", "head", "body"}
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


## The feedback shown under `id` after the last answer ("✓ Right! …" / "✖ Not quite. …"), or "". On screen it is a
## short headline with a mark and the explanation under it (split_feedback).
func feedback_text(id: StringName) -> String:
	return String(_feedback_text.get(id, ""))


## The status line of `id` ("✓ Answered by …"; empty before the first try; "Try 2 · a new question" after a miss).
func status_text(id: StringName) -> String:
	var l := _status.get(id) as Label
	return l.text if l != null else ""


## The "where to answer" line of `id`, or "" when it is hidden (it shows only when this is not the place).
func place_text(id: StringName) -> String:
	var l := _places.get(id) as Label
	return l.text if l != null and l.visible else ""


## The live readings line of `id`, or "" when it has none.
func readings_text(id: StringName) -> String:
	var l := _readings.get(id) as Label
	return l.text if l != null and l.visible else ""


## Opens or closes the "?" box under the header (as the "?" switch does).
func set_help_open(open: bool) -> void:
	if _help_button != null:
		_help_button.button_pressed = open


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
		_feedback_text[id] = "One moment…"
		refresh()
	else:
		_show_result(id, result)
	return result


## A feedback text as [tone, headline, explanation]. tone: "good" (right), "try" (not quite), "bad" (refused) or "".
static func split_feedback(text: String) -> Array:
	if text.begins_with("✓ Right!"):
		return ["good", "Right!", text.trim_prefix("✓ Right!").strip_edges()]
	if text.begins_with("✖ Not quite."):
		return ["try", "Not quite. Try again!", text.trim_prefix("✖ Not quite.").trim_suffix("Try the new version of the question.").strip_edges()]
	if text.begins_with("✖ "):
		return ["bad", text.trim_prefix("✖ "), ""]
	return ["", text, ""]


func refresh() -> void:
	if not _built or services == null or not services.has_game():
		return
	var st := _state()
	for id in question_ids:
		var q := ProgressionSystem.question(id)
		var known := ProgressionSystem.is_known(st, id)
		var status := _status[id] as Label
		var explain := _explains[id] as Label
		var buttons: Array = answer_buttons[id]
		var where := answer_station(id)
		if known:
			status.text = "✓ Answered by %s" % _who((st.knowledge[String(id)] as Dictionary).get("by", ""))
			status.theme_type_variation = UiTheme.GOOD
			var rec: Dictionary = st.knowledge[String(id)]
			var variants: Array = q.get("variants", [])
			var v: Dictionary = variants[clampi(int(rec.get("variant", 0)), 0, variants.size() - 1)] if not variants.is_empty() else {}
			(_texts[id] as Label).text = String(v.get("text", ""))
			# the explanation stays readable once the result line of this visit is gone
			explain.text = String(v.get("explanation", "")) if feedback_text(id).is_empty() else ""
			for b: Button in buttons:
				b.visible = false
		else:
			var guided := String(q.get("changed_from", ""))
			var locked := guided != "" and not ProgressionSystem.is_known(st, StringName(guided))
			var tries := int(((ProgressionSystem.progress_of(st)["quiz"] as Dictionary).get(String(id), {}) as Dictionary).get("wrong", 0))
			status.text = "" if tries == 0 else "Try %d · a new question" % (tries + 1)
			status.theme_type_variation = UiTheme.MUTED
			explain.text = ""
			var v := ProgressionSystem.current_variant(st, id)
			var answers: Array = v.get("answers", [])
			if locked:
				(_texts[id] as Label).text = "First answer “%s”." % ProgressionSystem.question_title(StringName(guided))
			else:
				(_texts[id] as Label).text = String(v.get("text", ""))
			for i in buttons.size():
				var b := buttons[i] as Button
				b.visible = not locked and i < answers.size()
				if i < answers.size():
					b.text = "%s   %s" % [LETTERS[i], String(answers[i])]
				b.disabled = where == &""
		status.visible = not status.text.is_empty()
		explain.visible = not explain.text.is_empty()
		var place := _places[id] as Label
		place.visible = not known and where == &""
		place.text = "! Go to %s to answer this." % ProgressionSystem.answer_place_words(q)
		var readings := _readings[id] as Label
		readings.text = _readings_text(st, String(q.get("readings", "")))
		readings.visible = not readings.text.is_empty() and not known
		_refresh_feedback(id)


## The result of the last answer: a mark, a short headline and the explanation.
func _refresh_feedback(id: StringName) -> void:
	var ui: Dictionary = _feedback[id]
	var parts := split_feedback(feedback_text(id))
	var tone := String(parts[0])
	(ui.box as Control).visible = not String(parts[1]).is_empty()
	var head := ui.head as Label
	head.text = String(parts[1])
	head.theme_type_variation = UiTheme.GOOD if tone == "good" else (UiTheme.WARN if tone == "try" else (UiTheme.URGENT if tone == "bad" else UiTheme.MUTED))
	var mark: Control = ui.mark
	mark.visible = tone != ""
	mark.set(&"kind", &"check" if tone == "good" else &"close")
	mark.set(&"color", AstraStyle.GOOD if tone == "good" else AstraStyle.WARN)
	var body := ui.body as Label
	body.text = String(parts[2])
	body.visible = not body.text.is_empty()


# ---------------------------------------------------------------- building

func _build() -> void:
	var ts := UiTheme.text_scale()
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	margin.add_child(column)
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override(&"separation", 12)
	column.add_child(header)
	header.add_child(MenuKit.picture(&"bubble", 34.0 * ts, &"heading"))
	var title := Label.new()
	title.text = heading
	title.theme_type_variation = UiTheme.TITLE
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_help_button = Button.new()
	_help_button.name = "Help"
	_help_button.text = "?"
	_help_button.toggle_mode = true
	_help_button.tooltip_text = "How the questions work."
	_help_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_help_button.toggled.connect(func(on: bool) -> void:
		_help_box.visible = on
		if on:
			_scroll.scroll_vertical = 0)
	header.add_child(_help_button)
	_close_button = Button.new()
	_close_button.name = "Close"
	_close_button.text = "Close"
	_close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close_button.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(_close_button)
	var intro := Label.new()
	intro.name = "Intro"
	intro.text = "Pick an answer. Wrong is fine: try again."
	intro.theme_type_variation = UiTheme.MUTED
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(intro)
	var help := PanelContainer.new()
	help.name = "HelpBox"
	help.theme_type_variation = UiTheme.CARD
	help.visible = false
	_help_box = help
	var help_col := VBoxContainer.new()
	help.add_child(help_col)
	help_col.add_child(_label("Answer to unlock upgrade cards. A right answer counts for the whole colony. A wrong answer is fine: read why, then try the new version. Nobody loses health.", &""))
	var about := ExplainButton.make("upgrades")
	about.text = "About upgrades"
	about.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	help_col.add_child(about)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override(&"separation", 12)
	_scroll.add_child(_body)
	_body.add_child(help)                # first in the scrolling part, so the panel never grows taller than the screen
	for id in question_ids:
		_body.add_child(_make_question(id))


func _make_question(id: StringName) -> Control:
	var card := PanelContainer.new()
	card.name = "Question_%s" % id
	card.theme_type_variation = UiTheme.CARD
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	card.add_child(box)
	var q := ProgressionSystem.question(id)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 12)
	box.add_child(top)
	var title := _label("%s %s" % [ProgressionSystem.sector_symbol(String(q.get("sector", ""))), ProgressionSystem.question_title(id)], UiTheme.HEADING)
	top.add_child(title)
	_status[id] = Label.new()
	(_status[id] as Label).theme_type_variation = UiTheme.MUTED
	top.add_child(_status[id])
	_readings[id] = _label("", UiTheme.MUTED)
	box.add_child(_readings[id])
	var text := BigLabel.new()
	text.font_scale = QUESTION_SCALE
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_texts[id] = text
	box.add_child(text)
	_explains[id] = _label("", &"")
	box.add_child(_explains[id])
	var buttons: Array = []
	for i in 3:
		var b := MenuKit.ScaledButton.new()
		b.font_scale = ANSWER_SCALE
		b.name = "Answer_%d" % i
		b.focus_mode = Control.FOCUS_ALL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 58.0
		b.pressed.connect(func() -> void: answer(id, i))
		box.add_child(b)
		buttons.append(b)
	answer_buttons[id] = buttons
	_places[id] = _label("", UiTheme.WARN)
	box.add_child(_places[id])
	var fb := HBoxContainer.new()
	fb.name = "Feedback"
	fb.add_theme_constant_override(&"separation", 10)
	fb.visible = false
	box.add_child(fb)
	var mark := HudKit.Icon.new(&"check", AstraStyle.GOOD, 30.0, "Mark")
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	fb.add_child(mark)
	var fb_col := VBoxContainer.new()
	fb_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fb.add_child(fb_col)
	var head := BigLabel.new()
	head.font_scale = QUESTION_SCALE
	head.name = "Head"
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fb_col.add_child(head)
	var body := _label("", &"")
	body.name = "Why"
	fb_col.add_child(body)
	_feedback[id] = {"box": fb, "mark": mark, "head": head, "body": body}
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
	if result.ok:
		_feedback_text[id] = StationPanel.answer_text(result)
	else:
		_feedback_text[id] = "✖ " + result.message
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


## A label whose text is `font_scale` times the normal text and keeps following the player's text size.
class BigLabel extends Label:
	var font_scale := 1.0:
		set(value):
			font_scale = value
			_fit_font()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
			_fit_font()

	func _fit_font() -> void:
		var want := roundi(UiTheme.BASE_FONT_SIZE * UiTheme.text_scale() * font_scale)
		if not has_theme_font_size_override(&"font_size") or get_theme_font_size(&"font_size") != want:
			add_theme_font_size_override(&"font_size", want)
