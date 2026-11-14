class_name RoverChargerStationPanel
extends StationPanel
## The rover charger in the garage (Prompt 10, part 1). Shows the rover battery, whether it is charging (or why it
## paused), and what charging costs the colony battery. Anyone can plug the rover in or out (rover_set_charging) when
## it is parked within the cable's reach. Charging takes RoverBalance.charger_kw from the colony battery and stops at
## the colony's charging reserve, so the base keeps power for the night.

## Start / stop charging.
var charge_button: Button


func _title_text() -> String:
	return "Rover charger"


func _shows_room_power() -> bool:
	return false


func _shows_later_note() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["Plug the rover in to charge its battery, or unplug it (anyone).",
		"See how much energy charging takes from the colony battery."])


func _build_body() -> void:
	_add_reading(&"rover_battery", "⚡", "Rover battery", "battery")
	_add_reading(&"status", "↯", "Charging", "load")
	_add_reading(&"parked", "⌂", "Rover parked", "cargo")
	_add_reading(&"colony", "⚡", "Colony battery", "battery")
	_add_reading(&"cost", "↓", "Charging takes from the colony battery", "load")
	_add_reading(&"used", "Σ", "Taken for the rover so far", "stock_vs_flow")
	var row := HBoxContainer.new()
	_body.add_child(row)
	charge_button = Button.new()
	charge_button.name = "Charge"
	charge_button.theme_type_variation = UiTheme.PRIMARY_BUTTON
	charge_button.pressed.connect(_on_charge)
	row.add_child(charge_button)
	_add_text(_body, "Some energy is lost as heat in the charger, so the rover gets a little less than the colony gives. The charger's numbers are game values.", UiTheme.MUTED)


func _refresh_body(st: ColonyState) -> void:
	RoverModel.ensure(st)
	var r := st.rover
	var b := RoverBalance.get_current()
	var built := bool(r.built)
	var cap := float(RoverModel.stats(r.levels, 0.0).battery_capacity_kwh)
	var battery := float(r.battery_kwh)
	if built:
		_show_reading(&"rover_battery", "%s of %s kWh (%d %%)" % [num(battery, 1), num(cap, 0), roundi(100.0 * battery / maxf(cap, 1e-6))], stock_level(battery, cap))
	else:
		_show_reading(&"rover_battery", "No rover yet", &"warn")
	var status := String(r.charge_status)
	var level: StringName = &"ok"
	if status.begins_with("paused") or status == "unplugged":
		level = &"warn"
	_show_reading(&"status", String(RoverSystem.STATUS_TEXT.get(status, status)), level)
	var d := RoverSystem.rover_distance_to_station(st, String(station_id))
	var reach := d <= b.charge_radius_m
	_show_reading(&"parked", "%s m away · %s" % [num(d, 1), "the cable reaches" if reach else "too far for the cable (%s m)" % num(b.charge_radius_m, 0)], &"ok" if reach else &"warn")
	var colony := st.store(&"battery_kwh")
	var ccap := float(st.capacities.get(&"battery_kwh", 0.0))
	_show_reading(&"colony", "%s of %s kWh · charging stops at %s kWh" % [num(colony, 0), num(ccap, 0), num(RoverSystem.charge_reserve_kwh(st), 0)],
		&"warn" if colony <= RoverSystem.charge_reserve_kwh(st) else stock_level(colony, ccap))
	_show_reading(&"cost", "%s kW while charging (%s kWh each game hour)" % [num(b.charger_kw, 1), num(b.charger_kw, 1)], &"ok")
	var taken := float(st.ledger.get(RoverSystem.LEDGER_CHARGE, 0.0))
	var lost := float(st.ledger.get(RoverSystem.LEDGER_LOSS, 0.0))
	_show_reading(&"used", "%s kWh (%s kWh reached the rover)" % [num(taken, 1), num(taken - lost, 1)], &"ok")
	var on := bool(r.charging)
	charge_button.text = "Stop charging" if on else "Start charging"
	var reason := ""
	if services.local_character() == null:
		reason = "Choose a crew member first."
	elif not built:
		reason = "There is no rover yet."
	elif not on and not reach:
		reason = "Park the rover in the garage, next to the charger."
	charge_button.disabled = reason != ""
	charge_button.tooltip_text = reason


func _on_charge() -> void:
	_ask(&"rover_set_charging", {"on": not bool(services.state().rover.charging)}, _on_answer)


func _on_answer(result: ActionResult) -> void:
	if result.ok:
		_show_message("")
		_show_cause(answer_text(result))
	else:
		_show_refusal(result)
	refresh()
