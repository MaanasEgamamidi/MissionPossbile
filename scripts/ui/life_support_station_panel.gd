class_name LifeSupportStationPanel
extends StationPanel
## The life-support console, in three parts:
##   Water      clean water and wastewater, water quality, the recycler, and where spare water goes (two sliders)
##   Oxygen     the oxygen reserve in its tanks with its forecast, and the two oxygen makers side by side:
##              the electrolyser (uses water) and the CO2-oxygen unit (uses Mars air, no water)
##   Cabin air  O2, CO2 and the total pressure in kPa, the CO2 scrubber and the cabin fans
## Problems with these systems are listed at the top in words. Every control is its own request to the host.

## Alerts shown at the top of this panel.
const ALERT_PREFIXES: Array[String] = ["recycler", "wastewater", "water_", "electrolyser", "co2_", "oxygen_", "cabin_",
	"scrubber", "fans", "pressure", "n2_", "shed_recycler", "shed_scrubber", "shed_cabin_fans", "shed_electrolyser",
	"shed_co2_unit", "no_air_", "suit_low_"]
## The two allocation sliders: key in ColonyState.water_allocation -> words.
const ALLOCATIONS := {
	"greenhouse_l_per_hour": "To the greenhouse",
	"electrolysis_feed_l_per_hour": "To the electrolyser",
}
const SLIDER_MAX := 20.0
const SLIDER_STEP := 0.5

## Allocation sliders by key ("greenhouse_l_per_hour", "electrolysis_feed_l_per_hour").
var sliders: Dictionary = {}

var _alerts_box: VBoxContainer
var _slider_values: Dictionary = {}
var _dragging: Dictionary = {}
var _allocation_pending := false
var _reserve_note: Label
var _oxygen_forecast: Label
var _water_forecast: Label
## Per oxygen process ("electrolyser", "co2_unit"): {"status", "made", "power", "water"} labels.
var _process_labels: Dictionary = {}


## The allocation slider for `key`, or null.
func slider(key: String) -> HSlider:
	return sliders.get(key) as HSlider


## The alert lines at the top of the panel.
func alert_texts() -> PackedStringArray:
	return StationPanel._box_lines(_alerts_box)


## The status sentence of one oxygen process ("Stopped: no water is sent to it…").
func process_status_text(id: String) -> String:
	return _process_text(id, "status")


## How much water one oxygen process takes ("Takes 0.23 L of water per hour" / "Takes no water: it uses Mars air").
func process_water_text(id: String) -> String:
	return _process_text(id, "water")


## Everything written on one process card, joined by new lines.
func process_card_text(id: String) -> String:
	var parts := PackedStringArray()
	for key: String in ["title", "uses", "status", "made", "power", "water"]:
		parts.append(_process_text(id, key))
	return "\n".join(parts)


func _process_text(id: String, key: String) -> String:
	var labels: Dictionary = _process_labels.get(id, {})
	var l := labels.get(key) as Label
	return l.text if l != null else ""


func _shows_later_note() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["Look after the water: the recycler and where spare water goes.",
		"Run the two oxygen makers that fill the oxygen tanks.", "Keep the cabin air safe to breathe."])


func _build_body() -> void:
	var bal := services.balance
	_add_heading(_body, "Warnings")
	_alerts_box = VBoxContainer.new()
	_alerts_box.name = "Alerts"
	_body.add_child(_alerts_box)

	# ---- water
	_add_heading_with_help(_body, "Water", "water")
	var water := VBoxContainer.new()
	water.name = "Water"
	_body.add_child(water)
	_add_reading(&"water", "≈", "Clean water", "water", water)
	_add_reading(&"wastewater", "≋", "Wastewater (used water)", "wastewater", water)
	_add_reading(&"quality", "◇", "Water quality", "water_quality", water)
	_water_forecast = _add_text(water, "", UiTheme.MUTED)
	_add_equipment_switch(water, "recycler")

	_add_heading_with_help(water, "Where spare water goes", "water_allocation")
	for key: String in ALLOCATIONS:
		var row := HBoxContainer.new()
		row.name = "Allocation_%s" % key
		water.add_child(row)
		var label := Label.new()
		label.text = String(ALLOCATIONS[key])
		label.custom_minimum_size.x = 0.0
		row.add_child(label)
		var s := HSlider.new()
		s.name = "Slider_%s" % key
		s.min_value = 0.0
		s.max_value = SLIDER_MAX
		s.step = SLIDER_STEP
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.custom_minimum_size.x = 160.0
		s.tooltip_text = "%s, litres per hour (0 to %s)" % [String(ALLOCATIONS[key]), num(SLIDER_MAX)]
		s.set_value_no_signal(float(services.state().water_allocation.get(key, 0.0)))
		s.drag_started.connect(func() -> void: _dragging[key] = true)
		s.drag_ended.connect(_on_drag_ended.bind(key))
		s.value_changed.connect(_on_slider_changed.bind(key))
		row.add_child(s)
		var value := Label.new()
		value.name = "Value_%s" % key
		row.add_child(value)
		sliders[key] = s
		_slider_values[key] = value
	_reserve_note = _add_text(water, "Drinking water always comes first. %s L stays in the tank as a drinking reserve, and only water above it goes to the greenhouse or the electrolyser. If there is not enough for both, they get the same share." % num(bal.water_reserve_l, 0), UiTheme.MUTED)

	# ---- oxygen
	_add_heading_with_help(_body, "Oxygen", "oxygen")
	var oxygen := VBoxContainer.new()
	oxygen.name = "Oxygen"
	_body.add_child(oxygen)
	_add_reading(&"oxygen", "O₂", "Oxygen reserve (in the tanks)", "oxygen", oxygen)
	_oxygen_forecast = _add_text(oxygen, "", UiTheme.MUTED)
	_add_text(oxygen, "Two machines can fill the oxygen tanks. Either, both or neither may run. Only the electrolyser uses water.")
	var pair := HBoxContainer.new()
	pair.name = "Processes"
	oxygen.add_child(pair)
	_add_process_card(pair, "electrolyser", "electrolysis", "Uses water: it splits water into oxygen and hydrogen.")
	_add_process_card(pair, "co2_unit", "co2_oxygen_unit", "Uses Mars air and power, no water.")

	# ---- cabin air
	_add_heading_with_help(_body, "Cabin air", "cabin_air")
	var cabin := VBoxContainer.new()
	cabin.name = "Cabin"
	_body.add_child(cabin)
	_add_reading(&"o2", "O₂", "Oxygen in the cabin air", "cabin_air", cabin)
	_add_reading(&"co2", "CO₂", "Carbon dioxide in the cabin air", "co2_scrubber", cabin)
	_add_reading(&"pressure", "◎", "Air pressure in the cabin", "pressure", cabin)
	_add_equipment_switch(cabin, "scrubber")
	_add_equipment_switch(cabin, "cabin_fans")
	_add_text(cabin, "Safe air in the rooms is not the same as the oxygen in the tanks. The tanks are the reserve; a regulator lets oxygen from them into the rooms when the cabin air needs it.", UiTheme.MUTED)


func _add_process_card(parent: Control, id: String, explanation_id: String, uses: String) -> void:
	var card := PanelContainer.new()
	card.name = "Card_%s" % id
	card.theme_type_variation = UiTheme.CARD
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var box := VBoxContainer.new()
	card.add_child(box)
	var labels := {}
	var head := HBoxContainer.new()
	box.add_child(head)
	labels["title"] = _add_heading(head, StationPanel.equipment_name(id))
	(labels["title"] as Label).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(ExplainButton.make(explanation_id))
	labels["uses"] = _add_text(box, uses)
	var button := CheckButton.new()
	button.name = "Switch_%s" % id
	button.text = "Switched on"
	button.set_pressed_no_signal(services.state().is_on(id))
	button.toggled.connect(_on_equipment_toggled.bind(id))
	box.add_child(button)
	equipment_switches[id] = button
	var switch_status := _add_text(box, "")
	_equipment_status[id] = switch_status
	switch_status.visible = false
	labels["status"] = _add_text(box, "")
	labels["made"] = _add_text(box, "")
	labels["power"] = _add_text(box, "")
	labels["water"] = _add_text(box, "")
	_process_labels[id] = labels


## The status of an oxygen process as a sentence.
static func process_status_words(status: String, balance: GameBalance) -> String:
	match status:
		"running": return "✓ Running."
		"feed_short": return "! Running, but short of feed water: it makes less oxygen. Send it more water."
		"no_feed": return "! Stopped: no water is sent to it. Set \"To the electrolyser\" above 0 L per hour."
		"dirty_water": return "! Stopped: the water is not clean enough. It needs %s %% or better." % num(balance.electrolyser_min_quality * 100.0, 0)
		"broken": return "! Stopped: it is broken."
		"no_power": return "✖ Stopped: no power. It was shed because power is short."
		"tanks_full": return "✓ Waiting: the oxygen tanks are full."
	return "○ Switched off."


## A word for the water quality.
static func quality_word(quality: float, balance: GameBalance) -> String:
	if quality >= 0.99:
		return "Very clean"
	if quality >= balance.electrolyser_min_quality:
		return "Clean"
	return "Not clean enough for the electrolyser"


func _refresh_body(st: ColonyState) -> void:
	var bal := services.balance
	_fill_alerts(_alerts_box, _alerts_matching(st, ALERT_PREFIXES), "No problems with water, oxygen or cabin air.")
	var forecast := ReserveForecast.compute(st, bal, services.clock())

	# water
	var water := st.store(&"water_l")
	var water_cap := float(st.capacities.get(&"water_l", 0.0))
	_show_reading(&"water", "%s of %s L" % [num(water, 0), num(water_cap, 0)], &"urgent" if water <= 0.0 else (&"warn" if water < bal.water_reserve_l else &"ok"))
	var waste := st.store(&"wastewater_l")
	var waste_cap := float(st.capacities.get(&"wastewater_l", 0.0))
	_show_reading(&"wastewater", "%s of %s L" % [num(waste, 0), num(waste_cap, 0)], &"warn" if waste_cap > 0.0 and waste >= bal.wastewater_warn_fraction * waste_cap else &"ok")
	var q := st.water_quality
	_show_reading(&"quality", "%s %% · %s" % [num(q * 100.0, 0), quality_word(q, bal)], &"ok" if q >= bal.electrolyser_min_quality else &"warn")
	_water_forecast.text = _forecast_line(forecast, 3)
	for key: String in sliders:
		var s := sliders[key] as HSlider
		if not _allocation_pending and not bool(_dragging.get(key, false)):
			s.set_value_no_signal(float(st.water_allocation.get(key, 0.0)))
		(_slider_values[key] as Label).text = "%s L per hour" % num(s.value)
	var spare := maxf(0.0, water - bal.water_reserve_l)
	_reserve_note.text = "Drinking water always comes first. %s L stays in the tank as a drinking reserve, and only water above it goes to the greenhouse or the electrolyser (%s L spare now). If there is not enough for both, they get the same share." % [num(bal.water_reserve_l, 0), num(spare, 0)]

	# oxygen
	var oxygen := st.store(&"oxygen_kg")
	var oxygen_cap := float(st.capacities.get(&"oxygen_kg", 0.0))
	var oxygen_level: StringName = &"ok"
	if oxygen <= 0.0:
		oxygen_level = &"urgent"
	elif oxygen < bal.oxygen_reserve_warn_kg:
		oxygen_level = &"warn"
	_show_reading(&"oxygen", "%s of %s kg" % [num(oxygen, 1), num(oxygen_cap, 0)], oxygen_level)
	_oxygen_forecast.text = _forecast_line(forecast, 2)
	for id: String in _process_labels:
		var labels: Dictionary = _process_labels[id]
		var status := String(st.oxygen_process.get(id, "off"))
		if not st.is_on(id):
			status = "off"
		(labels["status"] as Label).text = process_status_words(status, bal)
		var kg := StationPanel.process_o2_kg_per_hour(st, bal, id)
		(labels["made"] as Label).text = "Makes %s kg of oxygen per hour" % num(kg, 3)
		(labels["power"] as Label).text = "Uses %s kW" % num(float(st.unit(id).get("kw", 0.0)) if st.is_powered(id) else 0.0, 2)
		if id == "electrolyser":
			(labels["water"] as Label).text = "Takes %s L of water per hour" % num(kg * GameBalance.WATER_KG_PER_KG_O2, 3)
		else:
			(labels["water"] as Label).text = "Takes no water: it uses carbon dioxide from the Mars air"

	# cabin air
	var kpa := StationPanel.cabin_kpa(st, bal)
	var o2_lvl := StationPanel.o2_level(float(kpa.o2), bal)
	_show_reading(&"o2", "%s kPa · %s" % [num(float(kpa.o2), 1), StationPanel.o2_word(o2_lvl)], o2_lvl)
	var co2_lvl := StationPanel.co2_level(float(kpa.co2), bal)
	_show_reading(&"co2", "%s kPa · %s" % [num(float(kpa.co2), 2), StationPanel.co2_word(co2_lvl)], co2_lvl)
	var total := float(kpa.total)
	_show_reading(&"pressure", "%s kPa · %s" % [num(total, 1), "Safe" if total >= bal.pressure_warn_kpa else "Low"], &"ok" if total >= bal.pressure_warn_kpa else &"warn")


## Line `index` of the reserve forecast text, or "".
static func _forecast_line(forecast: Dictionary, index: int) -> String:
	var lines: Array = forecast.get("text", [])
	return String(lines[index]) if index < lines.size() else ""


func _on_slider_changed(value: float, key: String) -> void:
	(_slider_values[key] as Label).text = "%s L per hour" % num(value)
	if not bool(_dragging.get(key, false)):
		_send_allocation()          # keyboard: every arrow press is one finished change


func _on_drag_ended(value_changed: bool, key: String) -> void:
	_dragging[key] = false
	if value_changed:
		_send_allocation()


func _send_allocation() -> void:
	var params := {}
	for key: String in sliders:
		params[key] = float((sliders[key] as HSlider).value)
	_allocation_pending = true
	_ask(&"set_water_allocation", params, _on_allocation_answer)


func _on_allocation_answer(result: ActionResult) -> void:
	_allocation_pending = false
	if result.ok:
		_show_message("")
		_show_cause(answer_text(result))
	else:
		_show_refusal(result)
	refresh()
