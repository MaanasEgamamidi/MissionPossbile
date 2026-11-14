class_name BedStationPanel
extends StationPanel
## A greenhouse bed (a garden-dome planter or the hydroponics unit): the crop, its stage, growth and time to harvest,
## the three inputs (light, soil water, nutrients) with words and units, any symptom with its cause and the
## measurement that proves it, the diagnosis in progress, and the actions. Every action asks the host
## (`plant`, `inspect_bed`, `set_bed_water`, `adjust_nutrients`, `harvest`); the panel never edits state.

## Action buttons by key: "plant_lettuce", "plant_tomato", "inspect", "set_nutrients", "harvest".
var buttons: Dictionary = {}
## The bed's water switch (drip line on/off).
var water_switch: CheckButton
## The nutrient level to send with "Set nutrients" (0..1).
var nutrient_slider: HSlider

var _crop_note: Label
var _time_note: Label
var _alerts_box: VBoxContainer
var _symptoms_box: VBoxContainer
var _diagnosis: Label
var _slider_value: Label
var _water_pending := false


## The station record's own name ("Planter 3").
func _title_text() -> String:
	if services != null and services.has_game():
		return CropSystem.bed_name(services.state(), String(station_id))
	return "Greenhouse bed"


func panel_title() -> String:
	return _title_text()


func _shows_later_note() -> bool:
	return false


## The light comes from the Greenhouse lighting circuit, not the room this bed stands in: the light reading says it.
func _shows_room_power() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["Plant lettuce or tomato, and harvest meals when the crop is ready.",
		"Inspect the plants: see a problem and the measurement that proves it.",
		"Change one thing at a time (water or nutrients here, grow lights at the greenhouse console) and watch the growth rate."])


## The symptom lines as shown.
func symptom_texts() -> PackedStringArray:
	return StationPanel._box_lines(_symptoms_box)


## The diagnosis line as shown.
func diagnosis_text() -> String:
	return _diagnosis.text if _diagnosis != null else ""


## The note about the crop's evidence and the time compression, as shown.
func notes_text() -> String:
	return "%s\n%s" % [_crop_note.text, _time_note.text]


func _build_body() -> void:
	_add_text(_body, "%s Biology and food specialists know this job best, but anyone in the crew can do it." % String(StationPanels.SPECIALTY_SYMBOLS[FoodActions.SPECIALIST]), UiTheme.MUTED)
	_alerts_box = VBoxContainer.new()
	_alerts_box.name = "Alerts"
	_body.add_child(_alerts_box)

	_add_reading(&"crop", "❀", "Crop", "food")
	_add_reading(&"stage", "◔", "Stage", "food")
	_add_reading(&"progress", "▮", "Growth so far", "food")
	_add_reading(&"rate", "↗", "Growth rate", "stock_vs_flow")
	_add_reading(&"harvest_in", "⧗", "Time to harvest", "sol_length")
	_crop_note = _add_text(_body, "", UiTheme.MUTED)
	_time_note = _add_text(_body, "", UiTheme.MUTED)

	_add_heading_with_help(_body, "What the plants get", "food")
	var inputs := VBoxContainer.new()
	inputs.name = "Inputs"
	_body.add_child(inputs)
	_add_reading(&"light", "☀", "Light (grow lights)", "zones_power", inputs)
	_add_reading(&"water", "≈", "Soil water", "water_allocation", inputs)
	_add_reading(&"nutrients", "✿", "Nutrients", "food", inputs)
	_add_reading(&"drip", "⇣", "Drip line", "water_allocation", inputs)
	_add_text(inputs, "Growth rate = full speed × light × water × nutrients. No light stops growth; too little water or nutrients slows it. A bed that stays dry for a sol wilts and must be planted again.", UiTheme.MUTED)

	_add_heading(_body, "What you see")
	_symptoms_box = VBoxContainer.new()
	_symptoms_box.name = "Symptoms"
	_body.add_child(_symptoms_box)
	_diagnosis = _add_text(_body, "")

	_add_heading(_body, "Actions")
	var row := HFlowContainer.new()
	row.name = "Actions"
	_body.add_child(row)
	for crop_id: String in ["lettuce", "tomato"]:
		var c := FoodBalance.crop(crop_id)
		buttons["plant_" + crop_id] = _add_action_button(row, "Plant %s" % String(c.get("name", crop_id)).to_lower(), &"plant", {"crop": crop_id})
	buttons["inspect"] = _add_action_button(row, "Inspect the plants", &"inspect_bed", {})
	buttons["harvest"] = _add_action_button(row, "Harvest", &"harvest", {})
	(buttons["harvest"] as Button).theme_type_variation = UiTheme.PRIMARY_BUTTON

	water_switch = CheckButton.new()
	water_switch.name = "WaterSwitch"
	water_switch.text = "Water on (drip line)"
	water_switch.toggled.connect(_on_water_toggled)
	_body.add_child(water_switch)

	var feed := HFlowContainer.new()
	feed.name = "Nutrients"
	_body.add_child(feed)
	var label := Label.new()
	label.text = "Nutrients to"
	feed.add_child(label)
	nutrient_slider = HSlider.new()
	nutrient_slider.name = "NutrientSlider"
	nutrient_slider.min_value = 0.0
	nutrient_slider.max_value = 1.0
	nutrient_slider.step = 0.05
	nutrient_slider.custom_minimum_size.x = 160.0
	nutrient_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nutrient_slider.tooltip_text = "Nutrient level to set, 0 to 100 %"
	nutrient_slider.set_value_no_signal(FoodBalance.shared().metering_target)
	nutrient_slider.value_changed.connect(func(_v: float) -> void: _update_slider_label())
	feed.add_child(nutrient_slider)
	_slider_value = Label.new()
	_slider_value.name = "NutrientValue"
	feed.add_child(_slider_value)
	var set_button := Button.new()
	set_button.name = "SetNutrients"
	set_button.text = "Set nutrients"
	set_button.pressed.connect(func() -> void: _send(&"adjust_nutrients", {"level": snappedf(nutrient_slider.value, 0.01)}))
	feed.add_child(set_button)
	buttons["set_nutrients"] = set_button
	_update_slider_label()


func _add_action_button(parent: Control, text: String, action: StringName, params: Dictionary) -> Button:
	var b := Button.new()
	b.name = "Button_%s" % text.validate_node_name().replace(" ", "_")
	b.text = text
	b.pressed.connect(func() -> void: _send(action, params))
	parent.add_child(b)
	return b


func _update_slider_label() -> void:
	if _slider_value != null and nutrient_slider != null:
		_slider_value.text = "%d %%" % roundi(nutrient_slider.value * 100.0)


func _send(action: StringName, params: Dictionary) -> void:
	_ask(action, params, _on_answer)


func _on_answer(result: ActionResult) -> void:
	_water_pending = false
	if result.ok:
		_show_message("")
		_show_cause(answer_text(result))
	else:
		_show_refusal(result)
	refresh()


func _on_water_toggled(on: bool) -> void:
	_water_pending = true
	_send(&"set_bed_water", {"on": on})


func _refresh_body(st: ColonyState) -> void:
	var fb := FoodBalance.shared()
	var id := String(station_id)
	var b := CropSystem.bed(st, id)
	var crop_id := String(b.get("crop", ""))
	var c := FoodBalance.crop(crop_id)
	var alive := CropSystem.is_alive(b)
	var stage := String(b.get("stage", "empty"))
	var bed_alerts: Array = []
	for a: Dictionary in st.crops.get("alerts", []):
		if String(a.id).ends_with("_" + id):
			bed_alerts.append({"text": String(a.text), "level": String(a.level)})
	_fill_alerts(_alerts_box, bed_alerts, "No problems in this bed.")

	_show_reading(&"crop", String(c.get("name", "Nothing")) if crop_id != "" else "Nothing planted", &"ok" if crop_id != "" else &"warn")
	_show_reading(&"stage", String(CropSystem.STAGE_WORDS.get(stage, stage.capitalize())), &"urgent" if stage == "wilted" else &"ok")
	_show_reading(&"progress", "%d %%" % floori(float(b.get("progress", 0.0)) * 100.0 + 1e-6), &"ok")
	var rate := float(b.get("rate", 0.0))
	var full := FoodBalance.base_rate(crop_id)
	var rate_level: StringName = &"ok"
	if alive and stage != "ready":
		if rate <= 1e-12:
			rate_level = &"urgent"
		elif rate < full * 0.99:
			rate_level = &"warn"
	_show_reading(&"rate", "%s %% per sol" % num(rate * GameConfig.SOL_HOURS * 100.0, 1), rate_level)
	var left := CropSystem.hours_to_harvest(b)
	var left_text := "—"
	if stage == "ready":
		left_text = "Now"
	elif alive and left < 0.0:
		left_text = "Stopped"
	elif alive:
		left_text = "about %s sols" % num(left / GameConfig.SOL_HOURS, 1) if left >= GameConfig.SOL_HOURS else "about %d hours" % ceili(left)
	_show_reading(&"harvest_in", left_text, &"urgent" if left_text == "Stopped" else &"ok")
	if crop_id != "":
		_crop_note.text = "%s: %s. %s meals per harvest (game balance)." % [String(c.get("name", crop_id)), String(c.get("evidence", "")), num(float(c.get("meals", 0.0)))]
		_time_note.text = "Time is squeezed: a %s crop takes about %s sols here; it takes %s." % [String(c.get("name", crop_id)).to_lower(), num(float(c.get("cycle_sols", 0.0))), String(c.get("earth_words", "much longer on Earth"))]
	else:
		_crop_note.text = "Lettuce has been grown on the International Space Station (an ISS analog, not Mars evidence). Tomato is a plan, not yet grown on the ISS."
		_time_note.text = "Time is squeezed: lettuce takes about %s sols here and tomato about %s sols; on Earth they take weeks to months." % [
			num(float(FoodBalance.crop("lettuce").get("cycle_sols", 0.0))), num(float(FoodBalance.crop("tomato").get("cycle_sols", 0.0)))]

	# inputs
	var lit := CropSystem.lights_working(st, fb)
	if lit:
		_show_reading(&"light", "On · 100 %", &"ok")
	elif not CropSystem.lights_switched_on(st):
		_show_reading(&"light", "Off · 0 %", &"urgent" if alive else &"warn")
	else:
		_show_reading(&"light", "No power · 0 %", &"urgent")
	var water_l := float(b.get("water_l", 0.0))
	var share := water_l / maxf(fb.bed_water_capacity_l, 1e-9)
	var water_level: StringName = &"ok"
	if share <= 0.0:
		water_level = &"urgent"
	elif share < fb.water_good:
		water_level = &"warn"
	_show_reading(&"water", "%d %% · %s L" % [roundi(share * 100.0), num(water_l, 1)], water_level)
	var nut := float(b.get("nutrients", 0.0))
	_show_reading(&"nutrients", "%d %%" % roundi(nut * 100.0), &"ok" if nut >= fb.nutrient_good_low or not alive else &"warn")
	if bool(b.get("valve", true)):
		var flow := float(b.get("flow", 1.0))
		_show_reading(&"drip", "On · %d %% flow" % roundi(flow * 100.0), &"ok" if flow >= 0.5 else &"warn")
	else:
		_show_reading(&"drip", "Off", &"warn" if alive else &"ok")

	# symptoms
	var lines: Array = []
	for s: String in CropSystem.symptoms_of(st, b, fb):
		lines.append({"text": CropSystem.symptom_sentence(st, b, s), "level": "warn"})
	var none_text := "The plants look healthy." if alive else ("Nothing is growing here." if stage != "wilted" else "The plant has wilted. Plant again to start over.")
	_fill_alerts(_symptoms_box, lines, none_text)
	_diagnosis.text = _trial_words(b)

	# actions
	(buttons["plant_lettuce"] as Button).disabled = alive
	(buttons["plant_tomato"] as Button).disabled = alive
	(buttons["harvest"] as Button).disabled = stage != "ready"
	(buttons["set_nutrients"] as Button).disabled = not alive
	if not _water_pending:
		water_switch.set_pressed_no_signal(bool(b.get("valve", true)))


## The diagnosis in progress, in words.
static func _trial_words(b: Dictionary) -> String:
	var t: Dictionary = b.get("trial", {})
	var changed: Array = t.get("changed", [])
	match String(t.get("status", "")):
		"open":
			return "Test started: the growth rate was %s %% per sol when you looked. Change one thing, then watch it." % num(float(t.get("rate_before", 0.0)) * GameConfig.SOL_HOURS * 100.0, 1)
		"one_change":
			return "Test running: you changed only the %s. Watch whether the growth rate rises." % String(changed[0]) if not changed.is_empty() else ""
		"mixed":
			return "! More than one thing changed, so the test cannot tell which change helped. Inspect again to start a new test."
		"improved":
			return "✓ It worked: after changing the %s, growth rose from %s to %s %% per sol." % [String(changed[0]) if not changed.is_empty() else "input",
				num(float(t.get("rate_before", 0.0)) * GameConfig.SOL_HOURS * 100.0, 1), num(float(t.get("rate_after", 0.0)) * GameConfig.SOL_HOURS * 100.0, 1)]
		"no_change":
			return "! The growth rate did not rise within a sol. That was not the cause, or something else is also missing. Inspect again."
	return "Inspect the plants to start a test when something looks wrong."
