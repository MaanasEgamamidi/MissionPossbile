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
	# The big buttons: only the ones that fit the bed's state are shown (plant an empty bed, harvest a ready crop).
	for crop_id: String in ["lettuce", "tomato"]:
		var c := FoodBalance.crop(crop_id)
		buttons["plant_" + crop_id] = _add_action_button("Plant %s" % String(c.get("name", crop_id)).to_lower(), &"sprout", &"plant", {"crop": crop_id}, true)
	buttons["harvest"] = _add_action_button("Harvest", &"bowl", &"harvest", {}, true)
	buttons["inspect"] = _add_action_button("Inspect", &"zoom", &"inspect_bed", {}, false)
	(buttons["inspect"] as Button).tooltip_text = "Look closely at the plants. It starts a test when something looks wrong."

	# Problems first: alerts of this bed, what the plants look like, and the test in progress.
	_alerts_box = _add_alerts_box()
	_symptoms_box = VBoxContainer.new()
	_symptoms_box.name = "Symptoms"
	_body.add_child(_symptoms_box)
	_body.move_child(_symptoms_box, _alerts_box.get_index() + 1)
	_diagnosis = _add_text(_body, "")
	_diagnosis.name = "Diagnosis"
	_body.move_child(_diagnosis, _symptoms_box.get_index() + 1)

	_add_reading(&"crop", "❀", "Crop", "food")
	_add_reading(&"stage", "◔", "Stage", "food")
	_add_reading(&"progress", "↑", "Growth", "food")
	_add_reading(&"rate", "↗", "Growth speed", "stock_vs_flow")
	_add_reading(&"harvest_in", "⧗", "Harvest in", "sol_length")
	_add_note(_body, "%s Agriculture specialists know this job best, but anyone in the crew can do it." % String(StationPanels.SPECIALTY_SYMBOLS[FoodActions.SPECIALIST]))
	_crop_note = _add_note(_body, "")
	_time_note = _add_note(_body, "")

	_add_heading_with_help(_body, "What the plants get", "food")
	var inputs := VBoxContainer.new()
	inputs.name = "Inputs"
	_body.add_child(inputs)
	_add_reading(&"light", "☀", "Light", "zones_power", inputs)
	_add_reading(&"water", "≈", "Soil water", "water_allocation", inputs)
	_add_reading(&"nutrients", "✿", "Nutrients", "food", inputs)
	_add_reading(&"drip", "⇣", "Drip line", "water_allocation", inputs)
	_add_note(inputs, "Growth rate = full speed × light × water × nutrients. No light stops growth; too little water or nutrients slows it. A bed that stays dry for a sol wilts and must be planted again.")

	water_switch = CheckButton.new()
	water_switch.name = "WaterSwitch"
	water_switch.text = "Water"
	water_switch.icon = StationKit.pic(&"water", 24.0, &"heading")
	water_switch.tooltip_text = "Opens or closes this bed's drip line."
	water_switch.toggled.connect(_on_water_toggled)
	_body.add_child(water_switch)

	var feed := HFlowContainer.new()
	feed.name = "Nutrients"
	feed.add_theme_constant_override(&"h_separation", 10)
	_body.add_child(feed)
	feed.add_child(StationKit.picture(&"sprout", 24.0, &"heading"))
	var label := Label.new()
	label.text = "Nutrients"
	feed.add_child(label)
	nutrient_slider = HSlider.new()
	nutrient_slider.name = "NutrientSlider"
	nutrient_slider.min_value = 0.0
	nutrient_slider.max_value = 1.0
	nutrient_slider.step = 0.05
	nutrient_slider.custom_minimum_size.x = 200.0
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
	set_button.text = "Set"
	set_button.tooltip_text = "Set the nutrients to this level"
	set_button.pressed.connect(func() -> void: _send(&"adjust_nutrients", {"level": snappedf(nutrient_slider.value, 0.01)}))
	feed.add_child(set_button)
	buttons["set_nutrients"] = set_button
	_update_slider_label()


## One of the big buttons at the top: a picture, one or two words, and the host action it sends.
func _add_action_button(text: String, pic_kind: StringName, action: StringName, params: Dictionary, primary: bool) -> Button:
	var b := _add_action(text, pic_kind, func() -> void: _send(action, params), primary)
	b.name = "Button_%s" % text.validate_node_name().replace(" ", "_")
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
	_fill_alerts(_alerts_box, bed_alerts, "")

	_show_reading(&"crop", String(c.get("name", "Nothing")) if crop_id != "" else "Nothing planted", &"ok" if crop_id != "" else &"warn")
	_show_reading(&"stage", String(CropSystem.STAGE_WORDS.get(stage, stage.capitalize())), &"urgent" if stage == "wilted" else &"ok")
	_show_reading(&"progress", "%d %%" % floori(float(b.get("progress", 0.0)) * 100.0 + 1e-6), &"ok", float(b.get("progress", 0.0)))
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
		_crop_note.text = "%s: %s. %s meals per harvest (game balance)." % [String(c.get("name", crop_id)), String(c.get("evidence", "")), num(CropSystem.harvest_meals(services.state(), crop_id))]
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
	_show_reading(&"water", "%d %% · %s L" % [roundi(share * 100.0), num(water_l, 1)], water_level, share)
	var nut := float(b.get("nutrients", 0.0))
	_show_reading(&"nutrients", "%d %%" % roundi(nut * 100.0), &"ok" if nut >= fb.nutrient_good_low or not alive else &"warn", nut)
	if bool(b.get("valve", true)):
		var flow := float(b.get("flow", 1.0))
		_show_reading(&"drip", "On · %d %% flow" % roundi(flow * 100.0), &"ok" if flow >= 0.5 else &"warn")
	else:
		_show_reading(&"drip", "Off", &"warn" if alive else &"ok")

	# symptoms
	var lines: Array = []
	for s: String in CropSystem.symptoms_of(st, b, fb):
		lines.append({"text": CropSystem.symptom_sentence(st, b, s), "level": "warn"})
	# A tick only for healthy plants; an empty bed says so in its "Crop" reading, a wilted one gets a warning line.
	if stage == "wilted":
		lines.append({"text": "The plant has wilted. Plant again.", "level": "urgent"})
	_fill_alerts(_symptoms_box, lines, "The plants look healthy." if alive else "")
	_diagnosis.text = _trial_words(b)
	# The standing hint ("Inspect the plants to start a test…") is the Inspect button's tooltip, not a sentence here.
	_diagnosis.visible = String((b.get("trial", {}) as Dictionary).get("status", "")) != ""

	# actions: plant an empty bed; harvest and inspect a growing one
	(buttons["plant_lettuce"] as Button).disabled = alive
	(buttons["plant_tomato"] as Button).disabled = alive
	(buttons["plant_lettuce"] as Button).visible = not alive
	(buttons["plant_tomato"] as Button).visible = not alive
	(buttons["harvest"] as Button).disabled = stage != "ready"
	(buttons["harvest"] as Button).visible = alive
	(buttons["inspect"] as Button).visible = alive
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
