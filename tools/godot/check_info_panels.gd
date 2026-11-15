extends SceneTree
## Checks the four "information" panels after the UI overhaul: upgrade cards, colony summary, quiz, colony journal.
## For each: what a child sees first is short (one state per card, one word per supply), everything else is one press
## away and still there, the main actions still send their request, the keyboard reaches every button, and the panel
## fits a 1280x720 window at text size 1.0 and 1.5 (and with high contrast).
## Run: godot --headless --path . --script res://tools/godot/check_info_panels.gd
## Prints PASS / FAIL lines and "RESULT n/m". Saves go to res://_test_saves/check_info_panels and are deleted.


## Collects engine and script errors raised while the check runs.
class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR or error_type == ERROR_TYPE_SCRIPT:
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


## GameServices that remembers every request a panel sends.
class RecordingServices extends GameServices:
	var sent: Array = []

	func request(action: StringName, target: StringName = &"", params := {}) -> ActionResult:
		sent.append({"action": action, "target": target, "params": params})
		return super.request(action, target, params)

	func sent_of(action: StringName) -> Array:
		return sent.filter(func(r: Dictionary) -> bool: return r.action == action)


const SAVE_DIR := "res://_test_saves/check_info_panels"
const COMPUTER := "cm_colony_computer"
const POWER := "pw_panel"
## [window size, text scale, high contrast]
const CASES := [[Vector2i(1280, 720), 1.0, false], [Vector2i(1280, 720), 1.5, false], [Vector2i(1280, 720), 1.0, true]]
## Most words a standing cue may have (UI_OVERHAUL.md §3).
const CUE_WORDS := 6

var _passed := 0
var _total := 0
var _catcher := ErrorCatcher.new()
var g: RecordingServices


func _initialize() -> void:
	OS.add_logger(_catcher)
	PlayerInput.ensure_actions()
	g = RecordingServices.new()
	g.saves = SaveService.new(ProjectSettings.globalize_path(SAVE_DIR), "colony", 2)
	root.add_child(g)
	g.start_new_game(7)
	await process_frame
	g.set_process(false)          # no simulation ticks: the check sets every value itself
	await _check_upgrades()
	await _check_summary()
	await _check_quiz()
	await _check_journal()
	_check("no errors while the panels were open", _catcher.errors.is_empty(), "\n  ".join(_catcher.errors))
	OS.remove_logger(_catcher)
	g.saves.delete_all()
	g.queue_free()
	await process_frame
	UiTheme.set_high_contrast(false)
	UiTheme.apply_text_scale(1.0)
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


# ---------------------------------------------------------------- helpers

func _check(label: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS %s" % label)
	else:
		print("FAIL %s%s" % [label, "" if detail == "" else "\n  " + detail])


func _frames(n := 2) -> void:
	for i in n:
		await process_frame


func _stand_at(station: String) -> void:
	var st := g.state()
	g.local_character().position = CharacterState._v3((st.stations[station] as Dictionary).get("position", [0, 0, 0]))


func _know(qid: String) -> void:
	var st := g.state()
	var q := ProgressionSystem.question(StringName(qid))
	var v: Dictionary = (q.variants as Array)[0]
	st.knowledge[qid] = {"by": "crew_1", "sector": String(q.sector), "at_hours": 0.0, "variant": 0, "example": String(v.example)}


func _evidence(id: String) -> void:
	var s := g.session
	ProgressEvidence.record(s.state, s.events, StringName(id), String((ProgressionSystem.catalogue().evidence as Dictionary)[id].sector), &"crew_1")


func _open(panel: UiPanel) -> void:
	panel.setup(g)
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames(3)
	panel.refresh()
	await _frames(1)


func _apply_text_scale(s: float) -> void:
	UiTheme.apply_text_scale(s)
	var t := UiTheme.get_theme()
	var wanted := roundi(UiTheme.BASE_FONT_SIZE * s)
	if t.default_font_size != wanted:
		t.default_font_size = wanted


## UiLayoutCheck at 1280x720 in real pixels, text 1.0 and 1.5 and high contrast: nothing outside the screen, nothing
## clipped, the panel's minimum size fits, every button takes the keyboard and shows its focus.
func _layout(label: String, panel: UiPanel) -> void:
	var stretch := root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	for c: Array in CASES:
		var size: Vector2i = c[0]
		root.size = size
		UiTheme.set_high_contrast(bool(c[2]))
		_apply_text_scale(float(c[1]))
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await _frames(3)
		panel.refresh()
		await _frames(2)
		var problems := UiLayoutCheck.problems(panel, Vector2(size))
		var min_size := panel.get_combined_minimum_size()
		if min_size.x > float(size.x) or min_size.y > float(size.y):
			problems.append("minimum size %s is bigger than the screen" % min_size)
		problems.append_array(UiLayoutCheck.focus_problems(panel))
		if UiLayoutCheck.focusable(panel).is_empty():
			problems.append("nothing takes keyboard focus")
		_check("%s: layout and focus at %dx%d, text x%.1f%s" % [label, size.x, size.y, float(c[1]), ", high contrast" if bool(c[2]) else ""],
			problems.is_empty(), "\n  ".join(problems))
	UiTheme.set_high_contrast(false)
	_apply_text_scale(1.0)
	root.content_scale_mode = stretch
	await _frames(2)


func _labels(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	for child in node.get_children():
		if child is Label and (child as Label).is_visible_in_tree():
			out.append(child as Label)
		out.append_array(_labels(child))
	return out


## Every word a player can read on `node` right now (visible labels and button texts).
func _visible_text(node: Node) -> String:
	var parts := PackedStringArray()
	for l in _labels(node):
		parts.append(l.text)
	for b: Node in node.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree():
			parts.append((b as Button).text)
	return "\n".join(parts)


func _words(text: String) -> int:
	return text.split(" ", false).size() if not text.strip_edges().is_empty() else 0


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e


# ---------------------------------------------------------------- upgrade cards

func _check_upgrades() -> void:
	var st := g.state()
	_stand_at(COMPUTER)
	var up := UpgradeCardsPanel.new()
	await _open(up)
	var n := up.definitions.size()
	_check("upgrades: every card of the catalogue is there (%d)" % n, n == ProgressionSystem.cards().size() and up.install_buttons.size() == n
		and up.question_buttons.size() == n and up.more_buttons.size() == n)

	# what a child sees first
	var bad := PackedStringArray()
	var most_words := 0
	for i in n:
		var d := up.definitions[i]
		var card := up.find_child("Card_%s" % d.id, true, false)
		var gives := UpgradeCardsPanel.gives_text(d)
		var state := up.reason_label(d.id).text
		if _words(gives) == 0 or _words(gives) > CUE_WORDS:
			bad.append("%s gives '%s'" % [d.id, gives])
		if up.card_state(d.id) != &"wait" or _words(state) == 0 or _words(state) > CUE_WORDS or not up.reason_label(d.id).is_visible_in_tree():
			bad.append("%s state %s '%s'" % [d.id, up.card_state(d.id), state])
		if not up.cost_chip_text(d.id).contains("%d part" % d.cost_parts) or not up.cost_chip_text(d.id).contains("have %d" % st.parts):
			bad.append("%s cost '%s'" % [d.id, up.cost_chip_text(d.id)])
		var who := card.find_child("Who", true, false) as Control
		if who == null or not who.is_visible_in_tree() or not String(who.accessibility_name).begins_with("Installed by:"):
			bad.append("%s who badge" % d.id)
		var b := up.install_buttons[i]
		if not b.disabled or b.text != "Upgrade" or b.tooltip_text.is_empty() or b.icon == null:
			bad.append("%s button" % d.id)
		if up.is_more_open(d.id) or _visible_text(card).contains("What it does") or _visible_text(card).contains("Needs:"):
			bad.append("%s shows its details without being asked" % d.id)
		most_words = maxi(most_words, _words(_visible_text(card).replace("\n", " ")))
	_check("upgrades: a card shows its name, one line of what it gives, cost against parts, the installer's badge and ONE state (six words or fewer); details are closed",
		bad.is_empty(), "; ".join(bad))
	_check("upgrades: at most 30 words on the face of a card (%d on the wordiest; about 150 before)" % most_words, most_words > 0 and most_words <= 30)
	var page := _visible_text(up)
	_check("upgrades: the introduction and 'where the numbers come from' are not on the page until asked for",
		not page.contains("game balance") and not page.contains("Where the numbers come from") and not page.contains("Next level 1:"), page.substr(0, 200))
	var first := up.definitions[0]
	_check("upgrades: the first thing to do is the card's own questions", up.short_reason(first).get("kind", "") == "question"
		and up.reason_label(first.id).text == "Answer %d questions" % first.questions.size(), up.reason_label(first.id).text)

	# everything is one press away
	(up.more_buttons[first.id] as Button).button_pressed = true
	await _frames(1)
	var card0 := up.find_child("Card_%s" % first.id, true, false)
	var more_text := _visible_text(card0)
	var lines := up.requirement_lines(first.id)
	_check("upgrades: 'More' shows what it does, the effect, the sources and every requirement with a ✓ or ✖", up.is_more_open(first.id)
		and more_text.contains("What it does: " + first.function_text) and more_text.contains("Effect: " + first.effect)
		and more_text.contains("Where the numbers come from:") and lines.size() == 1 + first.questions.size() + first.evidence.size() + first.prerequisites.size() + 3
		and "\n".join(lines).contains("Installed by: ") and "\n".join(lines).contains("Install at: the ") and up.cost_label(first.id).is_visible_in_tree()
		and up.cost_label(first.id).text.contains("Needs %d parts — the colony has %d" % [first.cost_parts, st.parts]), "\n  ".join(lines))
	up.set_help_open(true)
	up.set_sector_open("energy", true)
	await _frames(1)
	page = _visible_text(up)
	_check("upgrades: '?' shows the introduction and where you stand; 'Next level' shows what the sector's next level needs",
		page.contains("game balance, not NASA numbers") and page.contains("You are at the colony computer.") and page.contains("Next level 1:")
		and page.contains("No card is ready yet in this sector."), page.substr(0, 300))
	await _layout("upgrades (More, ? and Next level open)", up)
	(up.more_buttons[first.id] as Button).button_pressed = false
	up.set_help_open(false)
	up.set_sector_open("energy", false)
	await _layout("upgrades", up)

	# keyboard: Tab order is the tree's; arrows walk Upgrade -> Questions -> More and on to the next card
	up.first_focus().grab_focus()
	await _frames(1)
	var started := up.install_buttons[0].has_focus()
	root.push_input(_key(KEY_DOWN))
	await _frames(1)
	var on_questions := (up.question_buttons[first.id] as Button).has_focus()
	root.push_input(_key(KEY_RIGHT))
	await _frames(1)
	var on_more := (up.more_buttons[first.id] as Button).has_focus()
	root.push_input(_key(KEY_UP))
	await _frames(1)
	var back_up := up.install_buttons[0].has_focus()
	root.push_input(_key(KEY_RIGHT))
	await _frames(1)
	var next_card := up.install_buttons[1].has_focus()
	_check("upgrades: arrow keys reach Upgrade, Questions and More of a card and the next card", started and on_questions and on_more and back_up and next_card,
		"start %s, questions %s, more %s, back %s, next card %s" % [started, on_questions, on_more, back_up, next_card])

	# Questions opens the card's quiz
	var opened: Array[UiPanel] = []
	up.open_requested.connect(func(p: UiPanel) -> void: opened.append(p))
	(up.question_buttons[&"ls_electrolysis"] as Button).pressed.emit()
	_check("upgrades: Questions opens the card's quiz", opened.size() == 1 and opened[0] is QuizPanel
		and (opened[0] as QuizPanel).question_ids == ProgressionSystem.card(&"ls_electrolysis").questions)
	for p in opened:
		p.free()

	# ready: the colony has everything -> go to the station -> one Upgrade press sends one request
	_evidence("energy_diagnose_output_loss")
	_evidence("energy_predict_net_power")
	for q in ["energy_q_dust_output", "energy_q_tracking", "energy_q_battery_night", "energy_q_net_power"]:
		_know(q)
	up.refresh()
	var id := &"energy_solar_tracking"
	var b := up.install_button(id)
	_check("upgrades: everything collected but not at the station: 'Go to the power panel', button still locked; the sector says how many are ready",
		up.card_state(id) == &"go" and up.reason_label(id).text == "Go to the power panel" and b.disabled
		and (up.find_child("Sector_energy", true, false).find_child("Ready", true, false) as Label).text == "★ 2 ready"
		and up.ready_text("energy").contains("Better sun tracking"), "%s '%s'" % [up.card_state(id), up.reason_label(id).text])
	g.local_character().position = g.config.hub_position
	g.request(&"claim_character", &"crew_2")
	var other := g.local_character()
	_stand_at(POWER)
	up.refresh()
	_check("upgrades: the wrong specialist at the station: one short reason naming the specialist", other != null and other.id == &"crew_2" and up.card_state(id) == &"go" and b.disabled
		and up.reason_label(id).text == "Needs the Electrical and comms specialist", up.reason_label(id).text)
	other.position = g.config.hub_position
	g.request(&"claim_character", &"crew_1")
	_stand_at(POWER)
	up.refresh()
	_check("upgrades: ready: 'Ready!' and one big primary Upgrade button", up.card_state(id) == &"ready" and not b.disabled and b.text == "Upgrade"
		and b.theme_type_variation == UiTheme.PRIMARY_BUTTON and up.reason_label(id).text == "Ready!", "%s '%s' %s" % [up.card_state(id), b.text, b.theme_type_variation])
	var primary := 0
	for other_b: Button in up.install_buttons:
		if other_b.theme_type_variation == UiTheme.PRIMARY_BUTTON:
			primary += 1
	_check("upgrades: only cards that can be installed now have a filled button", primary == 2, str(primary))
	var parts := st.parts
	g.sent.clear()
	b.pressed.emit()
	await _frames(1)
	var installs := g.sent_of(&"install_upgrade")
	_check("upgrades: pressing Upgrade sends exactly one install_upgrade for that card at the station", installs.size() == 1
		and String(installs[0].params.get("upgrade_id", "")) == String(id) and installs[0].target == StringName(POWER), str(g.sent))
	_check("upgrades: installed: a ticked 'Installed' button, parts spent, the host's answer shown", st.has_upgrade(String(id)) and st.parts == parts - 2
		and up.card_state(id) == &"done" and b.disabled and b.text == "Installed" and b.icon != null and not up.reason_label(id).is_visible_in_tree()
		and up.message_text().begins_with("✓ "), "%s '%s' '%s'" % [up.card_state(id), b.text, up.message_text()])
	up.queue_free()
	await _frames(1)


# ---------------------------------------------------------------- colony summary

func _check_summary() -> void:
	var st := g.state()
	for key: StringName in [&"battery_kwh", &"oxygen_kg", &"water_l", &"food_meals"]:
		st.stores[key] = float(st.capacities.get(key, 0.0)) * 0.8
	st.rates = {}
	var panel := ColonySummaryPanel.new()
	await _open(panel)
	var bad := PackedStringArray()
	for s: Dictionary in ColonySummaryPanel.STOCKS:
		var tile := panel.find_child("Tile_" + String(s.key), true, false) as Control
		var r := panel.tile_reading(s.key)
		if tile == null or not tile.is_visible_in_tree() or tile.find_child("Picture", true, false) == null or tile.find_child("Bar", true, false) == null:
			bad.append("%s tile" % s.key)
			continue
		var word := (tile.find_child("Word", true, false) as Label).text
		if word != "OK" or String(r.word) != "OK" or not (tile.find_child("Mark", true, false) as Control).is_visible_in_tree():
			bad.append("%s word '%s'" % [s.key, word])
		if absf(float(tile.find_child("Bar", true, false).get(&"share")) - 0.8) > 0.01:
			bad.append("%s bar %s" % [s.key, tile.find_child("Bar", true, false).get(&"share")])
	_check("summary: four supply tiles, each a picture, a level bar, a mark and ONE status word", bad.is_empty(), "; ".join(bad))
	var digits := RegEx.new()
	digits.compile("\\d")
	var numbers := PackedStringArray()
	for l in _labels(panel):
		if digits.search(l.text) != null and not l.text.ends_with("parts"):
			numbers.append(l.text)
	var page := _visible_text(panel)
	_check("summary: while everything is fine there are no numbers and no explanations on the page; the details are closed", numbers.is_empty()
		and not panel.details_open() and not page.contains("Stock or flow?") and not page.contains("kWh") and page.contains("What we have")
		and page.contains("✓ Colony OK"), "; ".join(numbers))
	_check("summary: about a dozen words at a glance (%d; about 250 before)" % _words(page.replace("\n", " ")), _words(page.replace("\n", " ")) <= 25, page.replace("\n", " | "))

	# a low supply says so in a word, a mark and how long it lasts
	st.stores[&"oxygen_kg"] = 4.0
	st.rates = {"oxygen_kg": -0.1}
	panel.refresh()
	await _frames(1)
	var o2 := panel.find_child("Tile_oxygen_kg", true, false) as Control
	var left := (o2.find_child("Left", true, false) as Label)
	_check("summary: a low supply shows 'Low' or 'Very low', a falling arrow and how long it lasts; the header names it",
		(o2.find_child("Word", true, false) as Label).text in ["Low", "Very low"] and left.is_visible_in_tree() and left.text == "about 1.6 sols left"
		and (o2.find_child("Trend", true, false) as Control).is_visible_in_tree() and String((o2.find_child("Trend", true, false) as Control).accessibility_name) == "Falling"
		and _visible_text(panel).contains("! Low: oxygen"), "%s / %s" % [(o2.find_child("Word", true, false) as Label).text, left.text])
	await _layout("summary", panel)

	# the details
	g.sent.clear()
	var toggle := panel.find_child("Details", true, false) as Button
	toggle.button_pressed = true
	await _frames(2)
	panel.refresh()
	page = _visible_text(panel)
	_check("summary: 'Details' opens the numbers with units, what is changing, how long it lasts, the two ideas and the rooms", panel.details_open()
		and toggle.text == "Hide details" and page.contains("4.0 kg of 150.0 kg") and page.contains("What is changing") and page.contains("How long it lasts")
		and page.contains("Oxygen lasts about 1.6 sols at this rate") and page.contains("Stock or flow?") and page.contains("Body energy or electricity?")
		and page.contains("Rooms with power") and page.contains("✓ On"), page.substr(0, 300).replace("\n", " | "))
	_check("summary: the panel only reads (no request sent)", g.sent.is_empty(), str(g.sent))
	await _layout("summary (details open)", panel)
	var closed := [false]
	panel.close_requested.connect(func() -> void: closed[0] = true)
	(panel.find_child("Close", true, false) as Button).pressed.emit()
	_check("summary: Close asks to close; it has the first focus", closed[0] and panel.first_focus() == panel.find_child("Close", true, false))
	st.rates = {}
	panel.queue_free()
	await _frames(1)


# ---------------------------------------------------------------- quiz

func _check_quiz() -> void:
	var st := g.state()
	_stand_at(COMPUTER)
	var card := ProgressionSystem.card(&"ls_electrolysis")
	var quiz := QuizPanel.for_card(card)
	await _open(quiz)
	var qid: StringName = card.questions[0]
	var buttons: Array = quiz.answer_buttons[qid]
	var base_size := UiTheme.get_theme().default_font_size
	var text_label := quiz.find_child("Question_%s" % qid, true, false).find_children("*", "Label", true, false).filter(
		func(l: Label) -> bool: return l.text == quiz.question_text(qid))
	var big := not text_label.is_empty() and (text_label[0] as Label).get_theme_font_size(&"font_size") > base_size
	var answers_ok := buttons.size() == 3
	for i in buttons.size():
		var b := buttons[i] as Button
		answers_ok = answers_ok and b.is_visible_in_tree() and not b.disabled and b.size.y >= 56.0 and b.get_theme_font_size(&"font_size") > base_size \
			and b.text.begins_with(["A", "B", "C"][i] + " ")
	_check("quiz: the question is large and its three answers are large buttons A, B, C", big and answers_ok and not quiz.question_text(qid).is_empty(),
		"big %s, answers %s" % [big, answers_ok])
	var intro := (quiz.find_child("Intro", true, false) as Label).text
	_check("quiz: one short line of introduction; the long one is behind '?'", _words(intro) <= 8 and not _visible_text(quiz).contains("Nobody loses health"), intro)
	quiz.set_help_open(true)
	await _frames(1)
	_check("quiz: '?' shows the full introduction", _visible_text(quiz).contains("A right answer counts for the whole colony") and _visible_text(quiz).contains("Nobody loses health"))
	quiz.set_help_open(false)
	_check("quiz: the first answer has the first focus", quiz.first_focus() == buttons[0])
	await _layout("quiz", quiz)

	var right := int(ProgressionSystem.current_variant(st, qid).get("correct", 0))
	var wrong := (right + 1) % 3
	var before := quiz.question_text(qid)
	g.sent.clear()
	(buttons[wrong] as Button).pressed.emit()
	await _frames(1)
	var sent := g.sent_of(&"answer_question")
	var fb := quiz.find_child("Question_%s" % qid, true, false).find_child("Feedback", true, false) as Control
	_check("quiz: pressing an answer sends exactly one answer_question with that choice", sent.size() == 1 and String(sent[0].params.get("question_id", "")) == String(qid)
		and int(sent[0].params.get("choice", -1)) == wrong and sent[0].target == StringName(COMPUTER), str(g.sent))
	_check("quiz: a wrong answer: 'Not quite. Try again!', the explanation under it, a new version of the question, nothing lost", fb.is_visible_in_tree()
		and (fb.find_child("Head", true, false) as Label).text == "Not quite. Try again!" and not (fb.find_child("Why", true, false) as Label).text.is_empty()
		and quiz.feedback_text(qid).begins_with("✖ Not quite.") and quiz.question_text(qid) != before and quiz.status_text(qid) == "Try 2 · a new question"
		and not st.knowledge.has(String(qid)), "%s | %s" % [(fb.find_child("Head", true, false) as Label).text, quiz.status_text(qid)])
	await _layout("quiz (after a wrong answer)", quiz)
	g.sent.clear()
	(buttons[int(ProgressionSystem.current_variant(st, qid).get("correct", 0))] as Button).pressed.emit()
	await _frames(1)
	_check("quiz: a right answer: 'Right!' with the explanation, the colony knows it, the answers go away", g.sent_of(&"answer_question").size() == 1
		and (fb.find_child("Head", true, false) as Label).text == "Right!" and not (fb.find_child("Why", true, false) as Label).text.is_empty()
		and st.knowledge.has(String(qid)) and quiz.status_text(qid).begins_with("✓ Answered by") and not (buttons[0] as Button).is_visible_in_tree(),
		"%s | %s" % [(fb.find_child("Head", true, false) as Label).text, quiz.status_text(qid)])
	var second: StringName = card.questions[1]
	g.local_character().position = g.config.hub_position
	quiz.refresh()
	await _frames(1)
	var second_buttons: Array = quiz.answer_buttons[second]
	_check("quiz: away from a station the answers are locked and one line says where to go", (second_buttons[0] as Button).disabled
		and quiz.place_text(second).begins_with("! Go to ") and quiz.answer_station(second) == &"", quiz.place_text(second))
	quiz.queue_free()
	await _frames(1)


# ---------------------------------------------------------------- journal

func _check_journal() -> void:
	var st := g.state()
	var journal := StoryLogPanel.new()
	await _open(journal)
	var sections := journal.find_children("Section_*", "PanelContainer", true, false)
	var pictures := 0
	var headings := PackedStringArray()
	for s: Node in sections:
		if not s.find_children("*", "TextureRect", true, false).is_empty():
			pictures += 1
		for l: Node in s.find_children("*", "Label", true, false):
			if (l as Label).theme_type_variation == UiTheme.HEADING:
				headings.append((l as Label).text)
				break
	_check("journal: five boxes, each with a pictogram and a heading", sections.size() == 5 and pictures == 5 and headings.size() == 5
		and headings[0] == "Now" and headings[3] == "Colony goal" and headings[4].begins_with("The first crew's story"), ", ".join(headings))
	var story := "\n".join(journal.story_lines())
	_check("journal: the story is all there (premise, the records, where to look)", _visible_text(journal).contains(String(TutorialSystem.lore().get("premise", "")))
		and story.contains("Records found: 0 of %d." % TutorialSystem.records().size()) and journal.story_lines().size() > TutorialSystem.discovery_defs().size(), story.substr(0, 200))
	_check("journal: no leftover chrome ('Press Esc to close.', the pencil glyph in the title)", not _visible_text(journal).contains("Press Esc")
		and not _visible_text(journal).contains("✎  Colony journal") and journal.find_child("Close", true, false) != null)
	await _layout("journal", journal)
	if journal.hint_button.is_visible_in_tree() and not journal.hint_button.disabled:
		g.sent.clear()
		journal.hint_button.pressed.emit()
		await _frames(1)
		_check("journal: 'Show a hint' shows a hint on the page", journal._hint_label.visible and journal._hint_label.text.begins_with("Hint: ") and g.sent.is_empty(),
			journal._hint_label.text)
	else:
		_check("journal: no open step, so no hint button", not journal.hint_button.visible)
	_check("journal: nothing finished yet: 'Remind me' is off and one short line says why", journal.replay_button.disabled and journal._replay_note.text == "Finish a step first.",
		journal._replay_note.text)
	# synthetic set-up: the first step is finished, as after playing it
	var t: Dictionary = TutorialSystem.ensure(st).tutorial
	if not t.get("completed", null) is Dictionary:
		t["completed"] = {}
	(t["completed"] as Dictionary)["1"] = {"at_hours": st.sim_hours}
	journal.refresh()
	await _frames(1)
	if journal.replay_option.item_count > 0 and not journal.replay_button.disabled:
		g.sent.clear()
		journal.replay_option.select(0)
		journal.replay_button.pressed.emit()
		await _frames(1)
		var replays := g.sent_of(&"tutorial_replay")
		_check("journal: 'Remind me' sends exactly one tutorial_replay for the chosen step and shows Mission Control's lines", replays.size() == 1
			and int(replays[0].params.get("stage", 0)) == 1 and journal.replay_option.get_item_id(0) == 1 and journal._replay_note.visible
			and not journal._replay_note.text.is_empty(), "%s | %s" % [g.sent, journal._replay_note.text])
	else:
		_check("journal: 'Remind me' could be tried (a finished step exists)", false, "no finished step listed")
	await _layout("journal (a step finished)", journal)
	var closed := [false]
	journal.close_requested.connect(func() -> void: closed[0] = true)
	(journal.find_child("Close", true, false) as Button).pressed.emit()
	_check("journal: Close asks to close", closed[0])
	journal.queue_free()
	await _frames(1)
