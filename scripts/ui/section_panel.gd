extends StationPanel
## The choices panel of one core section (upgrade paths plan §1.3 / §2, 2026-11-15): opened from the section's core
## spot (the power panel, the Greenhouse console, the med station, the workbench or lab glovebox, the comms console).
## It lists every track of the section: V1..Vn pips, the stage now, what the next level gives, its cost in spare parts
## and ores (have / need), its upkeep, a "Big jump" / "Small step + new ability" tag and what must come first. Choosing
## a build shows the permanent-choice card ("This is permanent: you can't take it back. You will be strong at X and
## still weak at Y."), then sends build_propose; fork levels (night power V3) pick a side first. The top card shows the
## day's state (Plan block, today's build done, the open vote with Yes / No buttons) and the colony's weakest system.
## Only shows; every change goes through services.request() (AreaLevelActions / ColonyBuilds).
## Loaded by path (no class_name): StationPanels.section_panel() makes it.

const ColonyBuilds := preload("res://scripts/upgrades/colony_builds.gd")
const ColonyBalance := preload("res://scripts/upgrades/colony_balance.gd")
const CrewDay := preload("res://scripts/schedule/crew_day.gd")

## Section id in data/area_levels.json ("energy", "biology", ...). Set before setup().
var section_id := ""
## One card per track, by track id.
var section_rows: Dictionary = {}

var _day_label: Label
var _vote_label: Label
var _balance_label: Label
var _vote_yes: Button
var _vote_no: Button
var _vote_cancel: Button
var _confirm: PanelContainer
var _confirm_title: Label
var _confirm_text: Label
var _confirm_yes: Button
var _confirm_no: Button
var _pending_track := ""
var _pending_choice := ""
var _busy := false


## One track's card.
class SectionRow extends PanelContainer:
	var track := ""
	var name_label: Label
	var tag_label: Label
	var pips: Array[Label] = []
	var now_label: Label
	var next_label: Label
	var gives_label: Label
	var cost_label: Label
	var upkeep_label: Label
	var badge_label: Label
	var choose_button: Button
	var choice_box: HBoxContainer
	var choice_buttons: Dictionary = {}
	var reason_label: Label

	## Every line shown now, top to bottom (for tests and the layout check).
	func shown_lines() -> PackedStringArray:
		var pip_text := PackedStringArray()
		for p: Label in pips:
			pip_text.append(p.text)
		var out := PackedStringArray([name_label.text, " ".join(pip_text)])
		for l: Label in [tag_label, now_label, next_label, gives_label, cost_label, upkeep_label, badge_label, reason_label]:
			if l.visible and l.text != "":
				out.append(l.text)
		if choose_button.visible:
			out.append("[%s]%s" % [choose_button.text, " (greyed out)" if choose_button.disabled else ""])
		for id: String in choice_buttons:
			var b := choice_buttons[id] as Button
			if b.visible:
				out.append("[%s]%s" % [b.text, " (greyed out)" if b.disabled else ""])
		return out


func _section() -> Dictionary:
	return AreaLevels.section(section_id)


func _title_text() -> String:
	return "%s upgrades" % String(_section().get("name", "Colony"))


func panel_title() -> String:
	return _title_text()


func _shows_later_note() -> bool:
	return false


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	if _title != null:
		_title.text = "%s  %s" % [String(_section().get("symbol", "●")), _title_text()]


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray([
		"Choose the colony's one build for today, in the Plan block at %s." % ColonyBuilds.PLAN_TIME_WORDS,
		"Everyone in radio contact votes. Every build is permanent, so choose with care.",
	])


## The section panel has its own track cards, not the station's upgrade strip.
func _build_upgrades() -> void:
	pass


func _refresh_upgrades(_st: ColonyState) -> void:
	pass


# ---------------------------------------------------------------- building

func _build_body() -> void:
	# The day: Plan block, today's build, the vote.
	var day := PanelContainer.new()
	day.name = "Today"
	day.theme_type_variation = UiTheme.CARD
	_body.add_child(day)
	var col := VBoxContainer.new()
	day.add_child(col)
	_add_heading(col, "Today's build")
	_day_label = _add_text(col, "")
	_day_label.name = "Day"
	_vote_label = _add_text(col, "")
	_vote_label.name = "Vote"
	var vote_row := HBoxContainer.new()
	col.add_child(vote_row)
	_vote_yes = Button.new()
	_vote_yes.name = "VoteYes"
	_vote_yes.text = "Vote yes"
	_vote_yes.theme_type_variation = UiTheme.PRIMARY_BUTTON
	_vote_yes.pressed.connect(_on_vote.bind(true))
	vote_row.add_child(_vote_yes)
	_vote_no = Button.new()
	_vote_no.name = "VoteNo"
	_vote_no.text = "Vote no"
	_vote_no.theme_type_variation = UiTheme.DANGER_BUTTON
	_vote_no.pressed.connect(_on_vote.bind(false))
	vote_row.add_child(_vote_no)
	_vote_cancel = Button.new()
	_vote_cancel.name = "VoteCancel"
	_vote_cancel.text = "Take my vote back"
	_vote_cancel.pressed.connect(_on_cancel)
	vote_row.add_child(_vote_cancel)
	_balance_label = _add_text(col, "", UiTheme.MUTED)
	_balance_label.name = "Balance"

	# The permanent-choice card (hidden until a build is picked).
	_confirm = PanelContainer.new()
	_confirm.name = "Confirm"
	_confirm.theme_type_variation = UiTheme.CARD
	_confirm.visible = false
	_body.add_child(_confirm)
	var ccol := VBoxContainer.new()
	_confirm.add_child(ccol)
	_confirm_title = _add_heading(ccol, "")
	_confirm_text = _add_text(ccol, "")
	var crow := HBoxContainer.new()
	ccol.add_child(crow)
	_confirm_yes = Button.new()
	_confirm_yes.name = "ConfirmYes"
	_confirm_yes.text = "Yes, build it"
	_confirm_yes.theme_type_variation = UiTheme.PRIMARY_BUTTON
	_confirm_yes.pressed.connect(_on_confirm_yes)
	crow.add_child(_confirm_yes)
	_confirm_no = Button.new()
	_confirm_no.name = "ConfirmNo"
	_confirm_no.text = "Not now"
	_confirm_no.pressed.connect(_hide_confirm)
	crow.add_child(_confirm_no)

	# One card per track.
	_add_heading(_body, "Paths")
	for track: String in AreaLevels.section_tracks(section_id):
		_build_row(track)


func _build_row(track: String) -> void:
	var row := SectionRow.new()
	row.name = "Path_%s" % track
	row.track = track
	row.theme_type_variation = UiTheme.CARD
	_body.add_child(row)
	var col := VBoxContainer.new()
	row.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	row.name_label = Label.new()
	row.name_label.text = AreaLevels.track_name(track)
	row.name_label.theme_type_variation = UiTheme.HEADING
	row.name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(row.name_label)
	var pip_row := HBoxContainer.new()
	pip_row.name = "Pips"
	top.add_child(pip_row)
	for lvl in range(1, AreaLevels.levels_of(track) + 1):
		var pip := Label.new()
		pip.name = "V%d" % lvl
		pip_row.add_child(pip)
		row.pips.append(pip)
	row.tag_label = _add_text(col, "", UiTheme.MUTED)
	row.now_label = _add_text(col, "")
	row.next_label = _add_text(col, "")
	row.gives_label = _add_text(col, "", UiTheme.MUTED)
	row.cost_label = _add_text(col, "")
	row.upkeep_label = _add_text(col, "", UiTheme.MUTED)
	row.badge_label = _add_text(col, "")
	var buttons := HBoxContainer.new()
	col.add_child(buttons)
	row.choose_button = Button.new()
	row.choose_button.name = "Choose"
	row.choose_button.theme_type_variation = UiTheme.PRIMARY_BUTTON
	row.choose_button.pressed.connect(_on_choose.bind(track, ""))
	buttons.add_child(row.choose_button)
	row.choice_box = HBoxContainer.new()
	row.choice_box.name = "Choices"
	col.add_child(row.choice_box)
	var fid := String(AreaLevels.track(track).get("fork", ""))
	if fid != "":
		for c: Dictionary in AreaLevels.fork(fid).get("choices", []):
			var cid := String(c.get("id", ""))
			var b := Button.new()
			b.name = "Pick_%s" % cid
			var badge := String(c.get("badge", ""))
			b.text = "Pick: %s%s" % [String(c.get("name", cid)), (" · " + badge) if badge != "" else ""]
			b.tooltip_text = String(c.get("text", ""))
			b.theme_type_variation = UiTheme.PRIMARY_BUTTON
			b.pressed.connect(_on_choose.bind(track, cid))
			row.choice_box.add_child(b)
			row.choice_buttons[cid] = b
	row.reason_label = _add_text(col, "", UiTheme.WARN)
	section_rows[track] = row


# ---------------------------------------------------------------- refresh

func _refresh_body(st: ColonyState) -> void:
	var me := services.local_character()
	_refresh_day(st, me)
	for track: String in section_rows:
		_refresh_row(st, section_rows[track] as SectionRow)
	if _confirm.visible and _pending_track != "":
		_fill_confirm(st)


func _refresh_day(st: ColonyState, me: CharacterState) -> void:
	var done := ColonyBuilds.today(st)
	if not done.is_empty():
		_day_label.text = "✓ %s built %s. %s" % [String(done.get("by_name", "The crew")),
			AreaLevels.stage_text_for(st, String(done.get("track", "")), int(done.get("level", 1))), ColonyBuilds.DONE_TEXT]
		_day_label.theme_type_variation = UiTheme.GOOD
	elif not TutorialSystem.specialty_features_unlocked(st):
		_day_label.text = ColonyBuilds.TUTORIAL_TEXT
		_day_label.theme_type_variation = UiTheme.MUTED
	elif TutorialSystem.tutorial_active(st):
		_day_label.text = "First tape played: you can choose today's one build now."
		_day_label.theme_type_variation = UiTheme.GOOD
	elif CrewDay.is_block(st, "plan"):
		_day_label.text = "It is the Plan block: choose today's one build now."
		_day_label.theme_type_variation = UiTheme.GOOD
	else:
		var h := CrewDay.hours_until(st, "plan")
		_day_label.text = "Builds are chosen in the Plan block at %s (in about %d hour%s). You can look now." % [
			ColonyBuilds.PLAN_TIME_WORDS, maxi(1, roundi(h)), "" if roundi(h) == 1 else "s"]
		_day_label.theme_type_variation = UiTheme.MUTED
	var vote := ColonyBuilds.vote_text_for(st, me)
	_vote_label.text = vote
	_vote_label.visible = vote != ""
	_vote_label.theme_type_variation = UiTheme.WARN if vote == ColonyBuilds.MISSED_TEXT else UiTheme.MUTED
	var p := ColonyBuilds.proposal(st)
	var waiting := ColonyBuilds.waiting_for(st, me)
	_vote_yes.visible = waiting
	_vote_no.visible = waiting
	_vote_yes.disabled = _busy
	_vote_no.disabled = _busy
	_vote_cancel.visible = not p.is_empty() and me != null and String(p.get("by", "")) == String(me.id)
	_vote_cancel.disabled = _busy
	var weak := ColonyBalance.weakest(st)
	_balance_label.visible = not weak.is_empty()
	if not weak.is_empty():
		_balance_label.text = "Colony balance: weakest is %s (%d %%)." % [String(weak.word), roundi(float(weak.share) * 100.0)]


## "Costs 3 spare parts (you have 5) · 2 rust rock (have 1)".
static func cost_text(st: ColonyState, track: String, next: int) -> String:
	var c := AreaLevels.cost_of(track, next)
	if c.is_empty():
		return ""
	var parts := int(c.get("parts", 0))
	var bits := PackedStringArray()
	bits.append("%d spare part%s (have %d)" % [parts, "" if parts == 1 else "s", st.parts])
	var ores: Dictionary = c.get("ores", {})
	for ore: String in ores:
		bits.append("%d %s (have %d)" % [int(ores[ore]), AreaLevels.ore_word(ore), AreaLevels.ore_stock(st, ore)])
	return "Costs " + " · ".join(bits)


func _refresh_row(st: ColonyState, row: SectionRow) -> void:
	var track := row.track
	var lvl := AreaLevels.level(st, track)
	var top := AreaLevels.levels_of(track)
	for i in row.pips.size():
		var reached := i + 1 <= lvl
		row.pips[i].text = "%s V%d" % ["●" if reached else "○", i + 1]
		row.pips[i].theme_type_variation = UiTheme.GOOD if reached else UiTheme.MUTED
	row.now_label.text = "Now: %s" % AreaLevels.stage_text_for(st, track, lvl)
	var at_top := lvl >= top
	var next := lvl + 1
	var has_next := not at_top
	for l: Label in [row.tag_label, row.next_label, row.gives_label, row.cost_label, row.upkeep_label]:
		l.visible = has_next
	var choice_now := AreaLevels.fork_choice_of_track(st, track)
	var badge := ""
	if choice_now != "":
		var cdef := AreaLevels.fork_choice_def(String(AreaLevels.track(track).get("fork", "")), choice_now)
		badge = String(cdef.get("badge", ""))
	row.badge_label.text = badge
	row.badge_label.visible = badge != ""
	row.badge_label.theme_type_variation = UiTheme.WARN if badge == "Not renewable" else UiTheme.MUTED
	if at_top:
		row.choose_button.visible = false
		row.choice_box.visible = false
		row.reason_label.text = "✓ Fully upgraded (V%d)." % lvl
		row.reason_label.theme_type_variation = UiTheme.GOOD
		row.reason_label.visible = true
		return
	row.tag_label.text = AreaLevels.step_tag(track, next)
	row.next_label.text = "Next: %s" % AreaLevels.stage_text(track, next)
	var gives := StationPanel.upgrade_gives_text(track, next)
	row.gives_label.text = "It gives: %s" % gives
	row.gives_label.visible = gives != ""
	row.cost_label.text = cost_text(st, track, next)
	row.cost_label.theme_type_variation = UiTheme.GOOD if AreaLevels.can_afford(st, track, next) else UiTheme.WARN
	var up_now := AreaLevels.upkeep_kw_at(track, lvl)
	var up_next := AreaLevels.upkeep_kw_at(track, next)
	if up_next > up_now + 0.001:
		row.upkeep_label.text = "Upkeep: uses %s kW more power" % StationPanel.num(up_next - up_now, 2)
	elif up_next < up_now - 0.001:
		row.upkeep_label.text = "Upkeep: uses %s kW less power" % StationPanel.num(up_now - up_next, 2)
	else:
		row.upkeep_label.text = "Upkeep: no extra power"
	var fork := AreaLevels.fork_at(track, next)
	var blockers := ColonyBuilds.blockers(st, track)
	var p := ColonyBuilds.proposal(st)
	if not p.is_empty() and String(p.get("track", "")) == track:
		blockers.append({"kind": "vote_open", "text": "The vote on this is open."})
	var blocked := _busy or not blockers.is_empty()
	row.choose_button.visible = fork.is_empty()
	row.choose_button.text = "Choose V%d" % next
	row.choose_button.disabled = blocked
	row.choice_box.visible = not fork.is_empty()
	for cid: String in row.choice_buttons:
		(row.choice_buttons[cid] as Button).disabled = blocked
	if not fork.is_empty():
		row.next_label.text = "Next: %s. %s" % [AreaLevels.stage_text(track, next), String(fork.get("title", "Pick one"))]
	var reasons := PackedStringArray()
	for b: Dictionary in blockers:
		reasons.append("✖ " + String(b.get("text", "")))
	row.reason_label.text = "\n".join(reasons)
	row.reason_label.theme_type_variation = UiTheme.WARN
	row.reason_label.visible = not reasons.is_empty()


# ---------------------------------------------------------------- the permanent-choice card

func _on_choose(track: String, choice: String) -> void:
	if _busy:
		return
	_pending_track = track
	_pending_choice = choice
	_fill_confirm(services.state())
	_confirm.visible = true
	_confirm_yes.grab_focus.call_deferred()


func _fill_confirm(st: ColonyState) -> void:
	var track := _pending_track
	var next := AreaLevels.level(st, track) + 1
	var what := "%s V%d" % [AreaLevels.track_name(track), next]
	var lines := PackedStringArray()
	var fork := AreaLevels.fork_at(track, next)
	if _pending_choice != "" and not fork.is_empty():
		var c := AreaLevels.fork_choice_def(String(fork.id), _pending_choice)
		what += ": %s" % String(c.get("name", _pending_choice))
		lines.append(String(c.get("text", "")))
		if not bool(c.get("renewable", true)):
			lines.append("! Not renewable: it uses up nuclear fuel brought from Earth.")
		for other: Dictionary in fork.get("choices", []):
			if String(other.get("id", "")) != _pending_choice:
				lines.append("The other choice (%s) will be locked forever." % String(other.get("name", "")).to_lower())
	_confirm_title.text = "Build %s?" % what
	lines.append("This is permanent: you can't take it back. %s" % ColonyBalance.strong_weak_text(st, track))
	lines.append(cost_text(st, track, next))
	if ColonyBuilds.voters(st).size() > 1:
		lines.append("Then everyone in radio contact votes. It is built when they all say yes.")
	_confirm_text.text = "\n".join(lines)
	_confirm_yes.disabled = _busy


func _hide_confirm() -> void:
	_confirm.visible = false
	_pending_track = ""
	_pending_choice = ""


func _on_confirm_yes() -> void:
	if _busy or _pending_track == "":
		return
	var params := {"track": _pending_track}
	if _pending_choice != "":
		params["choice"] = _pending_choice
	_busy = true
	_hide_confirm()
	_ask(&"build_propose", params, _on_answer)


func _on_vote(yes: bool) -> void:
	if _busy:
		return
	_busy = true
	_ask(&"build_vote", {"yes": yes}, _on_answer)


func _on_cancel() -> void:
	if _busy:
		return
	_busy = true
	_ask(&"build_cancel", {}, _on_answer)


func _on_answer(result: ActionResult) -> void:
	_busy = false
	if result.ok:
		var text := answer_text(result)
		var built := String(result.changes.get("status", "")) == "built"
		if text != "":
			_show_message(("✓ " if built else "• ") + text, UiTheme.GOOD if built else &"")
		else:
			_show_message("")
	else:
		_show_refusal(result)
	refresh()


## Every line the card of `track` shows now (empty when the section has no such track).
func section_lines(track: String) -> PackedStringArray:
	var row := section_rows.get(track) as SectionRow
	return row.shown_lines() if row != null else PackedStringArray()
