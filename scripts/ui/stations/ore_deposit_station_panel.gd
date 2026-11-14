class_name OreDepositStationPanel
extends StationPanel
## An ore deposit outside (scout update): what the ore is, why the colony wants it, how much good ore is left here,
## and "Collect a piece" (collect_ore, anyone). Collected ore waits in the colony store until someone works it at the
## workbench in the Hangar: hematite becomes spare parts, the other ores raise the science score.

var collect_button: Button
var _what: Label
var _why: Label


func _shows_later_note() -> bool:
	return false


func _shows_room_power() -> bool:
	return false


func _title_text() -> String:
	var st := services.state() if services != null and services.has_game() else null
	if st == null:
		return "Ore deposit"
	return "%s deposit" % String(ScoutSystem.ore_info(ScoutSystem.ore_kind_of(st, String(station_id))).get("name", "Ore"))


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["Collect a piece of ore (anyone). Each deposit has %d good pieces." % ScoutSystem.ORE_PER_DEPOSIT,
		"Take it to the workbench in the Hangar: hematite becomes spare parts, the other ores raise the science score."])


func _build_body() -> void:
	_add_reading(&"left", "◆", "Good ore left here", "parts")
	_add_reading(&"store", "⌂", "This ore in the colony store", "cargo")
	_what = _add_text(_body, "")
	_why = _add_text(_body, "", UiTheme.MUTED)
	collect_button = Button.new()
	collect_button.name = "Collect"
	collect_button.text = "◆ Collect a piece"
	collect_button.theme_type_variation = UiTheme.PRIMARY_BUTTON
	collect_button.pressed.connect(func() -> void: _ask(&"collect_ore", {}, _on_answer))
	_body.add_child(collect_button)


func _refresh_body(st: ColonyState) -> void:
	var kind := ScoutSystem.ore_kind_of(st, String(station_id))
	var info := ScoutSystem.ore_info(kind)
	var left := ScoutSystem.ore_left(st, String(station_id))
	_show_reading(&"left", "%d of %d" % [left, ScoutSystem.ORE_PER_DEPOSIT], &"ok" if left > 0 else &"warn")
	_show_reading(&"store", "%d" % ScoutSystem.ore_count(st, kind), &"ok")
	_what.text = "%s: %s" % [String(info.get("name", kind)), String(info.get("what", ""))]
	_why.text = String(info.get("why", ""))
	collect_button.disabled = left <= 0 or services.local_character() == null
	collect_button.tooltip_text = "Nothing good is left here." if left <= 0 else "Put a piece in the colony store."


func _on_answer(result: ActionResult) -> void:
	if result.ok:
		_show_message("")
		_show_cause(answer_text(result))
	else:
		_show_refusal(result)
	refresh()
