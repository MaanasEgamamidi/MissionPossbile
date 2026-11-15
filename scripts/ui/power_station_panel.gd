class_name PowerStationPanel
extends StationPanel
## The power panel: what the sun gives and the colony asks for right now, the battery (an amount in kWh) with its
## forecast, one switch per room and one per machine, and which loads have no power now and why.
## Every switch asks the host (`set_zone_power`, `set_equipment`); the switch shows the real state on refresh(),
## and a refused switch flips back and says why.

## Machines with a switch here, in the order they are listed.
const EQUIPMENT_ORDER: Array[String] = ["trackers", "cleaner", "recycler", "scrubber", "cabin_fans", "electrolyser", "co2_unit"]
## Alerts shown at the top of this panel (energy problems).
const ALERT_PREFIXES: Array[String] = ["shed_", "battery_", "cleaner_", "panels_", "trackers_"]

## Room switches by zone name.
var switches: Dictionary = {}

var _alerts_box: VBoxContainer
var _forecast_box: VBoxContainer
var _shed_heading: Control
var _shed_why: Label
var _shed_box: VBoxContainer
## Room switches waiting for the host: zone -> true.
var _zone_pending: Dictionary = {}


## The switch of `zone`, or null.
func switch_for(zone: String) -> CheckButton:
	return switches.get(zone) as CheckButton


## The text of the colony load reading ("53 kW").
func load_text() -> String:
	return reading_text(&"load")


## The battery forecast lines as shown ("Battery: 560 kWh, lasts until about …", "Battery at the next sunrise: …").
func forecast_text() -> String:
	return "\n".join(StationPanel._box_lines(_forecast_box))


## Every line of the "Loads without power" section, joined by new lines.
func shed_text() -> String:
	var lines := PackedStringArray([_shed_why.text])
	lines.append_array(StationPanel._box_lines(_shed_box))
	return "\n".join(lines)


## The alert lines at the top of the panel.
func alert_texts() -> PackedStringArray:
	return StationPanel._box_lines(_alerts_box)


func _shows_later_note() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["See how much power the sun gives and the colony uses.",
		"Switch rooms and machines off to make the battery last.",
		"See what has no power, and why."])


func _build_body() -> void:
	_alerts_box = _add_alerts_box()

	_add_reading(&"battery", "▮", "Battery", "battery")
	_add_reading(&"solar", "☀", "Sun gives", "solar_power")
	_add_reading(&"load", "⚡", "Colony uses", "load")
	_add_reading(&"battery_flow", "⇅", "Battery now", "stock_vs_flow")
	_add_reading(&"served", "✓", "Delivered", "power_deficit")

	var forecast_card := PanelContainer.new()
	forecast_card.theme_type_variation = UiTheme.CARD
	_body.add_child(forecast_card)
	var forecast_row := HBoxContainer.new()
	forecast_card.add_child(forecast_row)
	forecast_row.add_child(StationKit.picture(&"clock", 26.0, &"muted"))
	_forecast_box = VBoxContainer.new()
	_forecast_box.name = "Forecast"
	_forecast_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forecast_row.add_child(_forecast_box)
	for i in 2:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_forecast_box.add_child(l)
	forecast_row.add_child(_help_only(ExplainButton.make("battery_forecast")))

	_add_heading_with_help(_body, "Rooms", "zones_power")
	_add_note(_body, "Each room uses power while its lights are on. Switch off rooms nobody needs to make the battery last longer.")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(grid)
	var st := services.state()
	var zones: Array = st.zones.keys()
	zones.sort()
	for zone: String in zones:
		var button := CheckButton.new()
		button.name = "Switch_%s" % ColonyZones.slug(zone)
		button.text = "%s · %s kW" % [zone, num(services.balance.load_of_zone(zone))]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_pressed_no_signal(st.is_zone_powered(zone))
		button.toggled.connect(_on_switch_toggled.bind(zone))
		grid.add_child(button)
		switches[zone] = button

	_add_heading_with_help(_body, "Machines", "load")
	_add_note(_body, "Machines use power too. The two oxygen makers ask for more power the more oxygen they make.")
	var machines := VBoxContainer.new()
	machines.name = "Machines"
	_body.add_child(machines)
	for id in EQUIPMENT_ORDER:
		_add_equipment_switch(machines, id)

	# Shown only while something has no power: a calm panel does not need the sentence "every load has power".
	_shed_heading = _add_heading_with_help(_body, "No power", "load_shedding").get_parent() as Control
	_shed_why = _add_text(_body, "")
	_shed_box = VBoxContainer.new()
	_shed_box.name = "Shed"
	_body.add_child(_shed_box)
	_add_note(_body, shedding_order_text())


## The shedding order in one sentence.
static func shedding_order_text() -> String:
	var names := PackedStringArray()
	for id in PowerModel.SHED_ORDER:
		var n := StationPanel.equipment_name(id)
		if not n.begins_with("CO"):
			n = n.substr(0, 1).to_lower() + n.substr(1)
		names.append(n)
	var last := names[names.size() - 1]
	names.remove_at(names.size() - 1)
	return "When power is short, the colony switches loads off by itself in this order: %s, and last %s. They get power again by themselves when there is enough." % [", ".join(names), last]


func _refresh_body(st: ColonyState) -> void:
	var bal := services.balance
	_fill_alerts(_alerts_box, _alerts_matching(st, ALERT_PREFIXES), "No power problems right now.")
	var solar := st.solar_kw
	var load := StationPanel.colony_load_kw(st, bal)
	var battery := st.store(&"battery_kwh")
	var cap := float(st.capacities.get(&"battery_kwh", 0.0))
	_show_reading(&"solar", "%s kW" % num(solar), &"ok" if solar > 0.0 else &"warn")
	if st.battery_kw > 0.05:
		_show_reading(&"battery_flow", "%s · charging" % signed_kw(st.battery_kw), &"ok")
	elif st.battery_kw < -0.05:
		_show_reading(&"battery_flow", "%s · giving power" % signed_kw(st.battery_kw), &"warn")
	else:
		_show_reading(&"battery_flow", "0 kW · steady", &"ok")
	_show_reading(&"load", "%s kW" % num(load), &"ok")
	if st.shed.is_empty():
		_show_reading(&"served", "%s kW · all on" % num(st.served_kw), &"ok")
	else:
		_show_reading(&"served", "%s of %s kW · some loads have no power" % [num(st.served_kw), num(st.load_kw)], &"urgent")
	_show_reading(&"battery", "%s of %s kWh (%d %%)" % [num(battery, 0), num(cap, 0), roundi(100.0 * battery / maxf(cap, 1.0))], StationPanel.stock_level(battery, cap), battery / maxf(cap, 1.0))

	var forecast := ReserveForecast.compute(st, bal, services.clock())
	var lines: Array = forecast.get("text", [])
	for i in _forecast_box.get_child_count():
		(_forecast_box.get_child(i) as Label).text = String(lines[i]) if i < lines.size() else ""

	for zone: String in switches:
		if not _zone_pending.has(zone):
			(switches[zone] as CheckButton).set_pressed_no_signal(st.is_zone_powered(zone))

	if st.shed.is_empty():
		_shed_why.text = "✓ Every load that is switched on has power."
		_shed_why.theme_type_variation = UiTheme.GOOD
	else:
		var can_give := "is empty" if battery <= 1e-6 else "can give at most %s kW" % num(bal.battery_discharge_kw_max)
		_shed_why.text = "✖ Not enough power: the loads want %s kW, but the sun gives %s kW and the battery %s." % [num(st.load_kw), num(solar), can_give]
		_shed_why.theme_type_variation = UiTheme.URGENT
	var shed_alerts: Array = []
	for id: String in st.shed:
		shed_alerts.append({"text": StationPanel.words(String(PowerModel.SHED_TEXT.get(id, id))), "level": "urgent"})
	_fill_alerts(_shed_box, shed_alerts, "Nothing is shed.")
	_shed_box.visible = not st.shed.is_empty()
	_shed_heading.visible = not st.shed.is_empty()
	_shed_why.visible = not st.shed.is_empty()


func _on_switch_toggled(on: bool, zone: String) -> void:
	_zone_pending[zone] = true
	_ask(&"set_zone_power", {"zone": zone, "on": on}, _on_zone_answer.bind(zone, on))


func _on_zone_answer(result: ActionResult, zone: String, on: bool) -> void:
	_zone_pending.erase(zone)
	var button := switch_for(zone)
	if result.ok:
		_show_message("")
		refresh()
		var load := StationPanel.colony_load_kw(services.state(), services.balance)
		_show_cause("%s %s: the colony now uses %s kW." % [zone, "on" if on else "off", num(load)])
	else:
		if button != null:
			button.set_pressed_no_signal(not on)
		_show_refusal(result)
		refresh()


func _equipment_cause(result: ActionResult, _id: String, _on: bool) -> String:
	var load := StationPanel.colony_load_kw(services.state(), services.balance)
	return "%s The colony now asks for %s kW." % [answer_text(result), num(load)]
