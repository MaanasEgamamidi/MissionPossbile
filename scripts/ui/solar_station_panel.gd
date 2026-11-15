class_name SolarStationPanel
extends StationPanel
## One of the 12 sun trackers outside: how dusty its panel is and what it makes, what the whole array makes, whether
## the trackers follow the sun, and how the automatic cleaner is doing. "Clean panel" wipes this one panel by
## hand (`clean_panel`). "Repair cleaner" (`repair_cleaner`) is shown to everyone while the cleaner is broken but only
## works for the electrical and communications specialist; for anyone else the reason is written under the buttons.

## The specialist who can repair the cleaner.
const REPAIR_SPECIALTY := &"electrical_comms"
## Dust share above which a panel counts as dusty.
const DUSTY := 0.3

## "Clean panel".
var clean_button: Button
## "Repair cleaner" (hidden while the cleaner works).
var repair_button: Button

var _repair_reason: Label


## This tracker's index in ColonyState.panel_dust (0..11), or -1.
func tracker_index() -> int:
	if services == null or not services.has_game():
		return -1
	var rec: Dictionary = services.state().stations.get(String(station_id), {})
	return int(rec.get("tracker", -1))


## Why the repair button is disabled, in words ("" when it can be pressed).
func repair_reason_text() -> String:
	return _repair_reason.text if _repair_reason != null else ""


func _title_text() -> String:
	var i := tracker_index()
	return "Sun tracker %d" % (i + 1) if i >= 0 else StationPanels.name_of(kind)


func _shows_room_power() -> bool:
	return false


func _shows_later_note() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["See how dusty this solar panel is and how much power it makes.",
		"Clean this panel by hand.", "Repair the automatic panel cleaner (electrical and communications specialist)."])


## A word for how dusty a panel is.
static func dust_word(dust: float) -> String:
	if dust < 0.05:
		return "clean"
	if dust <= DUSTY:
		return "a little dusty"
	if dust < 0.7:
		return "dusty"
	return "very dusty"


func _build_body() -> void:
	clean_button = _add_action("Clean panel", &"sparkle", _on_clean)
	clean_button.name = "Clean"
	# Shown only while the cleaner is broken: one obvious button the rest of the time.
	repair_button = _add_action("Repair cleaner", &"wrench", _on_repair, false)
	repair_button.name = "Repair"
	var repair_row := HBoxContainer.new()
	repair_row.name = "RepairRow"
	_body.add_child(repair_row)
	_body.move_child(repair_row, _actions.get_index() + 1)
	_repair_reason = Label.new()
	_repair_reason.name = "RepairReason"
	_repair_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_repair_reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_repair_reason.theme_type_variation = UiTheme.MUTED
	repair_row.add_child(_repair_reason)
	repair_row.add_child(_help_only(ExplainButton.make("specialists")))

	_add_reading(&"dust", "◌", "Dust", "panel_dust")
	_add_reading(&"output", "☀", "This panel", "solar_power")
	_add_reading(&"array", "☀", "All panels", "solar_power")
	_add_reading(&"tracking", "↻", "Follows the sun", "sun_trackers")
	_add_reading(&"cleaner", "✧", "Cleaner", "panel_dust")
	_add_note(_body, "Cleaning by hand wipes the dust off this one panel, so it makes its full power again.")


func _refresh_body(st: ColonyState) -> void:
	var bal := services.balance
	var index := tracker_index()
	var dust := float(st.panel_dust[index]) if index >= 0 and index < st.panel_dust.size() else 0.0
	_show_reading(&"dust", "%s %% · %s" % [num(dust * 100.0, 0), dust_word(dust)], &"warn" if dust > DUSTY else &"ok", dust)
	var tracking := PowerModel.trackers_can_track(st, bal) and st.is_powered("trackers")
	var phase := services.clock().phase
	var mine := PowerModel.tracker_kw(st, bal, phase, tracking, index) if index >= 0 else 0.0
	var night := phase <= PowerModel.SUNRISE or phase >= PowerModel.SUNSET
	_show_reading(&"output", "%s kW%s" % [num(mine, 2), " · night" if night else ""], &"ok")
	_show_reading(&"array", "%s kW" % num(st.solar_kw), &"ok" if st.solar_kw > 0.0 or night else &"warn")
	if tracking:
		_show_reading(&"tracking", "Yes", &"ok")
	elif not st.is_on("trackers"):
		_show_reading(&"tracking", "No: switched off", &"warn")
	elif st.condition_of("trackers") < bal.equipment_min_condition:
		_show_reading(&"tracking", "No: broken", &"warn")
	else:
		_show_reading(&"tracking", "No: no power", &"warn")
	var broken := st.condition_of("cleaner") < bal.equipment_min_condition
	if broken:
		_show_reading(&"cleaner", "Broken", &"warn")
	elif not st.is_on("cleaner"):
		_show_reading(&"cleaner", "Switched off", &"warn")
	elif not st.is_powered("cleaner"):
		_show_reading(&"cleaner", "No power", &"warn")
	else:
		_show_reading(&"cleaner", "Working", &"ok")

	var me := services.local_character()
	var reason := ""
	if me == null:
		reason = "Choose a crew member first."
	elif me.specialty != REPAIR_SPECIALTY:
		reason = "Only the electrical and communications specialist can repair the cleaner."
		if not broken:
			reason += " It is working anyway."
	elif not broken:
		reason = "The cleaner is not broken, so there is nothing to repair."
	repair_button.disabled = reason != ""
	repair_button.tooltip_text = reason if reason != "" else "Repair the automatic panel cleaner."
	_repair_reason.text = reason if reason != "" else "You can repair it: you are the electrical and communications specialist."
	# The button and its reason matter only while the cleaner is broken.
	repair_button.visible = broken
	(_repair_reason.get_parent() as Control).visible = broken and reason != ""
	clean_button.disabled = me == null
	clean_button.tooltip_text = "Choose a crew member first." if me == null else "Wipe the dust off this panel."


func _on_clean() -> void:
	_ask(&"clean_panel", {}, _on_answer)


func _on_repair() -> void:
	_ask(&"repair_cleaner", {}, _on_answer)


func _on_answer(result: ActionResult) -> void:
	if result.ok:
		_show_message("")
		_show_cause(answer_text(result))
	else:
		_show_refusal(result)
	refresh()
