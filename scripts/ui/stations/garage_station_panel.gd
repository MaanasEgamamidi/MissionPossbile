class_name GarageStationPanel
extends StationPanel
## The rover garage (Prompt 10, part 1). Five sliders (levels 1-5) for speed, torque, battery range, cargo and
## traction are the controls: each row shows the level now, the planned level and the parts it costs (or gives back).
## Totals show parts invested, parts the colony has and the change. The table shows the stats now and planned,
## including the honest range with the cargo aboard now and the energy stored (a bigger battery is not filled by a
## refit). Anyone can plan. Only the field engineering and geology specialist ⛏ gets the assembly check and the
## Assemble / Refit button; the check (module, socket, power or load check for each changed module) runs here too.
## The planning is local (no request); only the commit goes to the host (rover_assemble / rover_refit).

const FIELD := &"field_engineering_geology"
## Example builds shown as explanations only: the sliders are the control.
const EXAMPLES := [["Long trips", {"range": 3, "cargo": 2}], ["Heavy hauler", {"torque": 3, "cargo": 3, "traction": 2}],
	["Quick scout", {"speed": 3, "traction": 2}]]
## Rows of the stats table: key, words.
const TABLE := [["speed", "Top speed"], ["push", "Push of the wheels"], ["slope", "Steepest slope"], ["accel", "Pulling away"],
	["capacity", "Battery holds"], ["stored", "Energy stored now"], ["cargo", "Cargo bay"], ["grip", "Tyre grip"], ["mass", "Mass with crew and cargo"],
	["range", "Range with the cargo aboard now"]]

## The planned level of each stat (the sliders).
var plan: Dictionary = {}
## Sliders by stat.
var sliders: Dictionary = {}
## The engineer's answers so far: stat -> {"module": index, "port": id, "check": index}.
var choices: Dictionary = {}
## Choice buttons by "stat|step|value", for tests.
var choice_buttons: Dictionary = {}
## Assemble / Refit.
var commit_button: Button
## Puts the sliders back to the rover as it is.
var reset_button: Button

var _row_labels: Dictionary = {}
var _table: Dictionary = {}
var _totals: Label
var _battery_note: Label
var _who: Label
var _commit_reason: Label
var _challenge_box: VBoxContainer
var _challenge: Dictionary = {}
var _sig := ""
var _syncing := false


func _title_text() -> String:
	return "Rover garage"


func _shows_room_power() -> bool:
	return false


func _shows_later_note() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["Plan the rover with the five sliders and see what each change costs and does (anyone).",
		"Assemble or refit the rover after a short assembly check (field engineering and geology specialist ⛏).",
		"A refit gives back every part of a lowered stat. It keeps the battery's energy: charge it at the charger."])


# ---------------------------------------------------------------- public helpers (also for tests)

## The levels the sliders show.
func plan_levels() -> Dictionary:
	return plan.duplicate()


## Moves one slider (as the player would).
func set_plan(stat: String, level: int) -> void:
	var s := sliders.get(stat) as HSlider
	if s != null:
		s.value = clampi(level, 1, RoverModel.MAX_LEVEL)
	else:
		plan[stat] = clampi(level, 1, RoverModel.MAX_LEVEL)
		refresh()


## The words of a slider row ("Level 2 now → 3 planned · costs 2 parts").
func slider_text(stat: String) -> String:
	var l := _row_labels.get(stat) as Label
	return l.text if l != null else ""


## The totals line.
func totals_text() -> String:
	return _totals.text if _totals != null else ""


## One cell of the stats table: `column` "now" or "plan".
func table_text(key: String, column: String) -> String:
	var row: Dictionary = _table.get(key, {})
	var l := row.get(column) as Label
	return l.text if l != null else ""


## Who may assemble (the line above the button).
func who_text() -> String:
	return _who.text if _who != null else ""


## Why the commit button is disabled ("" when it can be pressed).
func commit_reason_text() -> String:
	return _commit_reason.text if _commit_reason != null and commit_button != null and commit_button.disabled else ""


## The assembly check shown now (RoverModel.challenge for the planned levels).
func current_challenge() -> Dictionary:
	return _challenge


## Picks an answer as the player would: `step` "module" (index), "port" (id) or "check" (index).
func choose(stat: String, step: String, value: Variant) -> void:
	var b := choice_buttons.get("%s|%s|%s" % [stat, step, str(value)]) as Button
	if b != null:
		b.button_pressed = true
	else:
		_on_choice(true, stat, step, value)


## Presses Assemble / Refit.
func press_commit() -> ActionResult:
	if commit_button == null or commit_button.disabled:
		return null
	return _commit()


# ---------------------------------------------------------------- building

func _build_body() -> void:
	var st := services.state()
	RoverModel.ensure(st)
	plan = RoverModel.clean_levels(st.rover.levels)
	_add_reading(&"rover", "⌂", "Rover", "specialists")
	_add_reading(&"parts", "⚙", "Spare parts", "parts")
	_add_reading(&"battery", "▮", "Rover battery", "battery")
	_add_reading(&"cargo", "♻", "Cargo aboard", "cargo")
	_add_reading(&"range", "↔", "Range now", "load")

	_add_heading_with_help(_body, "Plan the rover", "parts")
	_add_note(_body, "Each step up costs 1, 2, 3 then 4 spare parts. Lowering a stat gives its parts back. Four seats in every build.")
	for s: String in RoverModel.STATS:
		var box := VBoxContainer.new()
		box.name = "Plan_%s" % s
		_body.add_child(box)
		var head := HBoxContainer.new()
		box.add_child(head)
		var name_label := _add_text(head, String(RoverModel.STAT_NAMES[s]), UiTheme.HEADING)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var info := Label.new()
		info.name = "Info"
		head.add_child(info)
		_row_labels[s] = info
		var slider := HSlider.new()
		slider.name = "Slider_%s" % s
		slider.min_value = 1
		slider.max_value = RoverModel.MAX_LEVEL
		slider.step = 1
		slider.tick_count = RoverModel.MAX_LEVEL
		slider.ticks_on_borders = true
		slider.focus_mode = Control.FOCUS_ALL
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(240, 24)
		slider.set_value_no_signal(int(plan[s]))
		slider.value_changed.connect(_on_slider.bind(s))
		box.add_child(slider)
		sliders[s] = slider
	_totals = _add_text(_body, "")
	_totals.name = "Totals"
	var reset_row := HBoxContainer.new()
	_body.add_child(reset_row)
	reset_button = Button.new()
	reset_button.name = "Reset"
	reset_button.text = "Undo plan"
	StationKit.button_pic(reset_button, &"reset", 22.0)
	reset_button.tooltip_text = "Back to the rover as it is"
	reset_button.pressed.connect(_on_reset)
	reset_row.add_child(reset_button)

	_add_heading(_body, "Now and planned")
	var grid := GridContainer.new()
	grid.name = "Stats"
	grid.columns = 3
	_body.add_child(grid)
	for h: String in ["", "Now", "Planned"]:
		var l := Label.new()
		l.text = h
		l.theme_type_variation = UiTheme.MUTED
		grid.add_child(l)
	for row: Array in TABLE:
		var label := Label.new()
		label.text = String(row[1])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size = Vector2(160, 0)
		grid.add_child(label)
		var now := Label.new()
		now.name = "Now_%s" % row[0]
		grid.add_child(now)
		var planned := Label.new()
		planned.name = "Plan_%s" % row[0]
		grid.add_child(planned)
		_table[String(row[0])] = {"now": now, "plan": planned}
	_battery_note = _add_text(_body, "", UiTheme.MUTED)
	_add_note(_body, "The rover's numbers are made up for the game, using real rules: a stronger motor goes faster, more mass and climbing use more energy (Mars gravity 3.73 m/s²), and grip is friction × weight. They are not NASA rover data.")
	var ex := PackedStringArray()
	for e: Array in EXAMPLES:
		var lv := {}
		for s: String in RoverModel.STATS:
			lv[s] = int((e[1] as Dictionary).get(s, 1))
		var parts := PackedStringArray()
		for s: String in e[1]:
			parts.append("%s %d" % [String(RoverModel.STAT_NAMES[s]).to_lower(), int(e[1][s])])
		ex.append("%s: %s (%d parts)" % [String(e[0]), ", ".join(parts), RoverModel.invested(lv)])
	_add_note(_body, "Example ideas, not presets (set the sliders yourself): %s." % "; ".join(ex))

	_add_heading_with_help(_body, "Assembly", "specialists")
	_who = _add_text(_body, "")
	_challenge_box = VBoxContainer.new()
	_challenge_box.name = "Challenge"
	_body.add_child(_challenge_box)
	var commit_row := HBoxContainer.new()
	_body.add_child(commit_row)
	commit_button = StationKit.action("", &"wrench")
	commit_button.name = "Commit"
	commit_button.pressed.connect(_on_commit_pressed)
	commit_row.add_child(commit_button)
	_commit_reason = _add_text(commit_row, "", UiTheme.MUTED)


# ---------------------------------------------------------------- refresh

func _refresh_body(st: ColonyState) -> void:
	RoverModel.ensure(st)
	var r := st.rover
	var now := RoverModel.clean_levels(r.levels)
	var built := bool(r.built)
	_syncing = true
	for s: String in RoverModel.STATS:
		(sliders[s] as HSlider).set_value_no_signal(int(plan.get(s, now[s])))
	_syncing = false
	var aboard := RoverModel.cargo_mass_kg(st)
	var crew := maxi(1, RoverModel.crew_aboard(st))
	var battery := float(r.battery_kwh)
	var cur := RoverModel.stats(now, aboard, battery, crew)
	var nxt := RoverModel.stats(plan, aboard, battery, crew)
	var where := "in the garage" if RoverSystem.in_garage(st) else "away from the garage"
	_show_reading(&"rover", ("Built · %s" % where) if built else "Not assembled yet", &"ok" if built else &"warn")
	_show_reading(&"parts", "%d" % st.parts, &"ok" if st.parts > 0 else &"warn")
	_show_reading(&"battery", "%s of %s kWh" % [num(battery, 1), num(float(cur.battery_capacity_kwh), 0)],
		stock_level(battery, float(cur.battery_capacity_kwh)) if built else &"ok", battery / maxf(float(cur.battery_capacity_kwh), 0.001))
	_show_reading(&"cargo", "%s of %s kg" % [num(aboard, 0), num(float(cur.cargo_capacity_kg), 0)], &"ok", aboard / maxf(float(cur.cargo_capacity_kg), 0.001))
	_show_reading(&"range", RoverActions._range_text(float(cur.range_km)), &"ok" if float(cur.range_km) > 0.2 else &"warn")
	for s: String in RoverModel.STATS:
		var a := int(now[s])
		var b := int(plan[s])
		var cost := RoverModel.invested({s: b}) - RoverModel.invested({s: a})
		var cost_text := "no change"
		if cost > 0:
			cost_text = "costs %d part%s" % [cost, "" if cost == 1 else "s"]
		elif cost < 0:
			cost_text = "gives back %d part%s" % [-cost, "" if cost == -1 else "s"]
		(_row_labels[s] as Label).text = "Level %d now → %d planned · %s" % [a, b, cost_text]
	var inv_now := RoverModel.invested(now)
	var inv_plan := RoverModel.invested(plan)
	var change := inv_plan - inv_now
	var change_text := "no change in parts"
	if change > 0:
		change_text = "uses %d of the colony's %d parts" % [change, st.parts]
	elif change < 0:
		change_text = "gives %d parts back to the colony's %d" % [-change, st.parts]
	_totals.text = "Parts in the rover: %d now, %d planned · this plan %s." % [inv_now, inv_plan, change_text]
	_totals.theme_type_variation = UiTheme.URGENT if change > st.parts else &""
	_fill_table(cur, nxt)
	if int(plan["range"]) > int(now["range"]):
		_battery_note.text = "A bigger battery does not fill itself: the %s kWh stored now stay the same. Charge it at the charger." % num(battery, 1)
	elif int(plan["range"]) < int(now["range"]) and battery > float(nxt.battery_capacity_kwh):
		_battery_note.text = "The smaller battery holds %s kWh, so %s kWh would leave with the removed modules." % [
			num(float(nxt.battery_capacity_kwh), 1), num(battery - float(nxt.battery_capacity_kwh), 1)]
	else:
		_battery_note.text = "A refit keeps the energy stored in the battery; it never fills it."
	var me := services.local_character()
	var engineer := me != null and me.specialty == FIELD
	if engineer:
		_who.text = "⛏ You are the field engineering and geology specialist: you can %s the rover." % ("refit" if built else "assemble")
	else:
		_who.text = "⛏ Only the field engineering and geology specialist can assemble or refit the rover. Anyone can plan with the sliders."
	var sig := "%s|%d|%d|%s|%s" % [JSON.stringify(plan), int(r.refit_seq), int(r.challenge_variant), str(built), str(engineer)]
	if sig != _sig:
		_sig = sig
		_build_challenge(st, engineer)
	commit_button.text = "Refit rover" if built else "Build rover"
	commit_button.visible = engineer
	var reason := _commit_block(st, now, built, aboard, nxt, me)
	commit_button.disabled = reason != ""
	commit_button.tooltip_text = reason
	_commit_reason.text = reason
	_commit_reason.visible = engineer


func _fill_table(cur: Dictionary, nxt: Dictionary) -> void:
	for pair: Array in [[cur, "now"], [nxt, "plan"]]:
		var s: Dictionary = pair[0]
		var col := String(pair[1])
		var cells := {
			"speed": "%s km/h" % num(float(s.top_speed_mps) * 3.6, 1),
			"push": "%s N" % num(float(s.drive_force_n), 0),
			"slope": "%s°" % num(float(s.max_slope_deg), 0),
			"accel": "%s m/s²" % num(float(s.accel_mps2), 2),
			"capacity": "%s kWh" % num(float(s.battery_capacity_kwh), 0),
			"stored": "%s kWh" % num(float(s.battery_kwh), 1),
			"cargo": "%s kg" % num(float(s.cargo_capacity_kg), 0),
			"grip": num(float(s.traction_mu), 2),
			"mass": "%s kg" % num(float(s.total_mass_kg), 0),
			"range": RoverActions._range_text(float(s.range_km)),
		}
		for key: String in cells:
			var l := (_table[key] as Dictionary).get(col) as Label
			l.text = String(cells[key])


## Why the engineer cannot commit now ("" if they can).
func _commit_block(st: ColonyState, now: Dictionary, built: bool, aboard: float, nxt: Dictionary, me: CharacterState) -> String:
	if me == null:
		return "Choose a crew member first."
	if built and plan == now:
		return "Move a slider to plan a change."
	if not RoverSystem.in_garage(st):
		return "Drive the rover into the garage first."
	if RoverModel.crew_aboard(st) > 0:
		return "Everyone must get out of the rover first."
	var cost := RoverModel.invested(plan) - RoverModel.invested(now)
	if cost > st.parts:
		return "Not enough parts: this plan needs %d and the colony has %d." % [cost, st.parts]
	if aboard > float(nxt.cargo_capacity_kg) + 1e-6:
		return "Unload the cargo first: %s kg is aboard, the planned bay holds %s kg." % [num(aboard, 0), num(float(nxt.cargo_capacity_kg), 0)]
	for step: Dictionary in _challenge.get("steps", []):
		var a: Dictionary = choices.get(String(step.stat), {})
		if not (a.has("module") and a.has("port") and a.has("check")):
			return "Answer every step of the assembly check above."
	return ""


func _build_challenge(st: ColonyState, engineer: bool) -> void:
	for child in _challenge_box.get_children():
		_challenge_box.remove_child(child)
		child.queue_free()
	choice_buttons.clear()
	choices.clear()
	_challenge = RoverModel.challenge(st, plan)
	if not engineer:
		return
	var now := RoverModel.clean_levels(st.rover.levels)
	if bool(st.rover.built) and plan == now:
		_add_text(_challenge_box, "Move a slider to plan a change.", UiTheme.MUTED)
		return
	_add_text(_challenge_box, "Pick the module, its socket and the answer.", UiTheme.MUTED)
	_add_note(_challenge_box, "A wrong answer costs nothing: you get a new example.")
	for step: Dictionary in _challenge.get("steps", []):
		var s := String(step.stat)
		var card := PanelContainer.new()
		card.name = "Step_%s" % s
		card.theme_type_variation = UiTheme.CARD
		_challenge_box.add_child(card)
		var col := VBoxContainer.new()
		card.add_child(col)
		var change := "level %d → %d" % [int(step.from), int(step.to)] if int(step.from) != int(step.to) else "level %d" % int(step.to)
		_add_text(col, "⛏ Fit the %s (%s)" % [String(step.module), change], UiTheme.HEADING)
		_add_text(col, String(step.need))
		_add_text(col, "1. Choose the module:")
		var g1 := ButtonGroup.new()
		var mods: Array = step.modules
		for i in mods.size():
			_add_choice(col, g1, s, "module", i, String((mods[i] as Dictionary).text))
		_add_text(col, "2. Connect it to:")
		var g2 := ButtonGroup.new()
		var row2 := HFlowContainer.new()
		col.add_child(row2)
		for p: Dictionary in step.ports:
			_add_choice(row2, g2, s, "port", String(p.id), String(p.text))
		_add_text(col, "3. Check: %s" % String(step.question))
		var g3 := ButtonGroup.new()
		var row3 := HFlowContainer.new()
		col.add_child(row3)
		var opts: Array = step.options
		for i in opts.size():
			_add_choice(row3, g3, s, "check", i, String(opts[i]))


func _add_choice(parent: Control, group: ButtonGroup, stat: String, step: String, value: Variant, text: String) -> void:
	var b := Button.new()
	b.name = "Choice_%s_%s_%s" % [stat, step, str(value)]
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.toggled.connect(_on_choice.bind(stat, step, value))
	parent.add_child(b)
	choice_buttons["%s|%s|%s" % [stat, step, str(value)]] = b


# ---------------------------------------------------------------- input

func _on_slider(value: float, stat: String) -> void:
	if _syncing:
		return
	plan[stat] = clampi(roundi(value), 1, RoverModel.MAX_LEVEL)
	refresh()


func _on_reset() -> void:
	plan = RoverModel.clean_levels(services.state().rover.levels)
	refresh()


func _on_choice(pressed: bool, stat: String, step: String, value: Variant) -> void:
	if not pressed:
		return
	if not choices.has(stat):
		choices[stat] = {}
	(choices[stat] as Dictionary)[step] = value
	refresh()


func _on_commit_pressed() -> void:
	_commit()


func _commit() -> ActionResult:
	var st := services.state()
	var action := &"rover_refit" if bool(st.rover.built) else &"rover_assemble"
	return _ask(action, RoverModel.build_params(plan, _challenge, choices), _on_answer)


func _on_answer(result: ActionResult) -> void:
	if result.ok:
		_show_message("")
		_show_cause(answer_text(result))
		if bool(result.changes.get("assembled", false)):
			plan = RoverModel.clean_levels(services.state().rover.levels)
	else:
		_show_refusal(result)
	_sig = ""
	refresh()
