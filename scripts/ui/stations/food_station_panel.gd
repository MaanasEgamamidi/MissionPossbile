class_name FoodStationPanel
extends StationPanel
## The greenhouse console: every bed at a glance, the grow-light switch, a shortcut to the greenhouse water
## allocation, the food store and the meals the crew eats per sol, why light, water and nutrients matter, the
## automation upgrades and (with the evidence-based settings upgrade) lab nutrient settings to apply.
## Every control asks the host (`set_grow_lights`, `set_greenhouse_water`, `apply_nutrient_result`).

## The grow-light switch.
var lights_switch: CheckButton
## Greenhouse water to send, litres per game hour.
var water_slider: HSlider
## The "Send water" button.
var water_button: Button
## Buttons that apply a lab result, by result id.
var result_buttons: Dictionary = {}

var _alerts_box: VBoxContainer
var _lights_status: Label
var _water_value: Label
var _beds_box: VBoxContainer
var _automation_box: VBoxContainer
var _results_box: VBoxContainer
var _results_note: Label
var _start_note: Label
var _lights_pending := false


func _shows_later_note() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["See every bed: what grows, how far it is and what is wrong.",
		"Switch the grow lights and send water to the greenhouse.",
		"See the food store and how much the crew eats each sol."])


## The bed overview lines as shown.
func bed_lines() -> PackedStringArray:
	return StationPanel._box_lines(_beds_box)


## The automation lines as shown.
func automation_lines() -> PackedStringArray:
	return StationPanel._box_lines(_automation_box)


## The alert lines as shown.
func alert_texts() -> PackedStringArray:
	return StationPanel._box_lines(_alerts_box)


## The note about the stored meals at the start.
func start_note_text() -> String:
	return _start_note.text


func _build_body() -> void:
	var fb := FoodBalance.shared()
	_add_text(_body, "%s Biology and food specialists know the greenhouse best, but anyone in the crew can use it." % String(StationPanels.SPECIALTY_SYMBOLS[FoodActions.SPECIALIST]), UiTheme.MUTED)
	_add_heading(_body, "Warnings")
	_alerts_box = VBoxContainer.new()
	_alerts_box.name = "Alerts"
	_body.add_child(_alerts_box)

	# ---- food store
	_add_heading_with_help(_body, "Food store", "food")
	var store := VBoxContainer.new()
	store.name = "Store"
	_body.add_child(store)
	_add_reading(&"food", "❀", "Food in store", "food", store)
	_add_reading(&"food_use", "↓", "The crew eats", "stock_vs_flow", store)
	_add_reading(&"food_left", "⧗", "Food lasts", "food", store)
	_add_reading(&"food_growing", "↗", "Meals growing in the beds", "food", store)
	_start_note = _add_text(store, "", UiTheme.MUTED)

	# ---- grow lights
	_add_heading_with_help(_body, "Grow lights", "zones_power")
	lights_switch = CheckButton.new()
	lights_switch.name = "LightsSwitch"
	lights_switch.text = "Grow lights · %s kW" % num(services.balance.load_of_zone(fb.light_zone))
	lights_switch.toggled.connect(_on_lights_toggled)
	_body.add_child(lights_switch)
	_lights_status = _add_text(_body, "")

	# ---- water
	_add_heading_with_help(_body, "Greenhouse water", "water_allocation")
	_add_reading(&"allocated", "≈", "Water sent to the greenhouse", "water_allocation", _body)
	_add_reading(&"delivered", "⇣", "Water that really arrives", "water_allocation", _body)
	var row := HFlowContainer.new()
	row.name = "WaterRow"
	_body.add_child(row)
	var label := Label.new()
	label.text = "Send"
	row.add_child(label)
	water_slider = HSlider.new()
	water_slider.name = "WaterSlider"
	water_slider.min_value = 0.0
	water_slider.max_value = 20.0
	water_slider.step = 0.5
	water_slider.custom_minimum_size.x = 160.0
	water_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	water_slider.tooltip_text = "Greenhouse water, litres per hour (0 to 20)"
	water_slider.set_value_no_signal(float(services.state().water_allocation.get("greenhouse_l_per_hour", 0.0)))
	water_slider.value_changed.connect(func(_v: float) -> void: _update_water_label())
	row.add_child(water_slider)
	_water_value = Label.new()
	_water_value.name = "WaterValue"
	row.add_child(_water_value)
	water_button = Button.new()
	water_button.name = "SendWater"
	water_button.text = "Send water"
	water_button.pressed.connect(func() -> void: _ask(&"set_greenhouse_water", {"greenhouse_l_per_hour": water_slider.value}, _on_answer))
	row.add_child(water_button)
	_add_text(_body, "Drinking water always comes first: the greenhouse only gets water above the drinking reserve. The beds use only the water that really arrives; it then goes to the wastewater tank for the recycler.", UiTheme.MUTED)
	_update_water_label()

	# ---- beds
	_add_heading(_body, "Beds")
	_beds_box = VBoxContainer.new()
	_beds_box.name = "Beds"
	_body.add_child(_beds_box)

	# ---- why
	_add_heading_with_help(_body, "Why light, water and nutrients matter", "food")
	_add_text(_body, "Plants make their food from light, so with no light they stop growing. Water carries food through the plant and keeps it firm: too little and it slows down and wilts. Nutrients build new leaves: too few and the leaves turn yellow and growth slows.")
	_add_text(_body, "Time is squeezed in the colony: lettuce takes about %s sols here and tomato about %s sols, but weeks to months on Earth. Lettuce has been grown on the International Space Station; tomato is only a plan there. Neither proves that crops grow on Mars." % [
		num(float(FoodBalance.crop("lettuce").get("cycle_sols", 0.0))), num(float(FoodBalance.crop("tomato").get("cycle_sols", 0.0)))], UiTheme.MUTED)

	# ---- automation and lab results
	_add_heading_with_help(_body, "Automation", "upgrades")
	_automation_box = VBoxContainer.new()
	_automation_box.name = "Automation"
	_body.add_child(_automation_box)
	_add_heading(_body, "Lab results")
	_results_note = _add_text(_body, "", UiTheme.MUTED)
	_results_box = VBoxContainer.new()
	_results_box.name = "Results"
	_body.add_child(_results_box)


func _update_water_label() -> void:
	if _water_value != null:
		_water_value.text = "%s L per hour" % num(water_slider.value)


func _on_lights_toggled(on: bool) -> void:
	_lights_pending = true
	_ask(&"set_grow_lights", {"on": on}, _on_answer)


func _on_answer(result: ActionResult) -> void:
	_lights_pending = false
	if result.ok:
		_show_message("")
		_show_cause(answer_text(result))
	else:
		_show_refusal(result)
	refresh()


func _refresh_body(st: ColonyState) -> void:
	var fb := FoodBalance.shared()
	var bal := services.balance
	var alerts: Array = []
	for a: Dictionary in st.crops.get("alerts", []):
		alerts.append({"text": String(a.text), "level": String(a.level)})
	_fill_alerts(_alerts_box, alerts, "No greenhouse problems right now.")

	# store
	var crew := float(st.active_characters().size())
	var food := st.store(&"food_meals")
	var cap := float(st.capacities.get(&"food_meals", 0.0))
	var per_sol := crew * bal.meals_per_sol
	_show_reading(&"food", "%s of %s meals" % [num(food, 0), num(cap, 0)], StationPanel.stock_level(food, cap))
	_show_reading(&"food_use", "%s meals per sol" % num(per_sol, 1), &"ok")
	_show_reading(&"food_left", StationPanel.time_left_text(food, per_sol / GameConfig.SOL_HOURS), StationPanel._left_level(food, per_sol / GameConfig.SOL_HOURS))
	var growing := 0.0
	for id: String in CropSystem.bed_ids(st):
		var b := CropSystem.bed(st, id)
		if CropSystem.is_alive(b):
			growing += float(FoodBalance.crop(String(b.crop)).get("meals", 0.0))
	_show_reading(&"food_growing", "%s meals" % num(growing, 0), &"ok" if growing > 0.0 else &"warn")
	var start_sols := bal.food_meals_start / maxf(per_sol, bal.meals_per_sol)
	_start_note.text = "Stored meals cover the start: the colony landed with %s meals, about %s sols for %d crew, while the first crops grow." % [
		num(bal.food_meals_start, 0), num(start_sols, 0), maxi(1, int(crew))]

	# lights
	var on := CropSystem.lights_switched_on(st)
	if not _lights_pending:
		lights_switch.set_pressed_no_signal(on)
	if CropSystem.lights_working(st, fb):
		_lights_status.text = "✓ On: the plants get light."
		_lights_status.theme_type_variation = UiTheme.GOOD
	elif on:
		_lights_status.text = "✖ Switched on but shed: there is not enough power, so the plants get no light."
		_lights_status.theme_type_variation = UiTheme.URGENT
	else:
		_lights_status.text = "○ Off: plants do not grow without light."
		_lights_status.theme_type_variation = UiTheme.MUTED

	# water
	var alloc := float(st.water_allocation.get("greenhouse_l_per_hour", 0.0))
	_show_reading(&"allocated", "%s L per hour" % num(alloc), &"ok" if alloc > 0.0 else &"warn")
	var delivered := float(st.crops.get("delivered_l_per_hour", 0.0))
	_show_reading(&"delivered", "%s L per hour" % num(delivered, 2), &"ok" if delivered >= alloc - 1e-6 else &"warn")

	# beds
	var lines: Array = []
	for id: String in CropSystem.bed_ids(st):
		lines.append(_bed_line(st, id))
	while _beds_box.get_child_count() < lines.size():
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_beds_box.add_child(l)
	for i in _beds_box.get_child_count():
		var l := _beds_box.get_child(i) as Label
		l.visible = i < lines.size()
		if l.visible:
			l.text = String(lines[i][0])
			l.theme_type_variation = StringName(lines[i][1])

	# automation
	var auto_lines: Array = []
	for pair: Array in [["food_irrigation_reliability", "Reliable irrigation: beds never dry out while water is sent."],
			["food_nutrient_metering", "Nutrient metering: nutrients stay in the good band by themselves."],
			["food_scheduled_care", "Scheduled care: lights and watering run on a schedule."]]:
		if st.has_upgrade(String(pair[0])):
			auto_lines.append({"text": String(pair[1]), "level": "ok"})
		else:
			auto_lines.append({"text": "Not installed yet. " + String(pair[1]), "level": "info"})
	_fill_automation(auto_lines)

	# lab results
	_refresh_results(st)


func _bed_line(st: ColonyState, id: String) -> Array:
	var b := CropSystem.bed(st, id)
	var name := CropSystem.bed_name(st, id)
	var crop_id := String(b.get("crop", ""))
	if crop_id == "":
		return ["○ %s: empty" % name, UiTheme.MUTED]
	var stage := String(b.get("stage", ""))
	var text := "%s: %s, %s, %d %%" % [name, String(FoodBalance.crop(crop_id).get("name", crop_id)),
		String(CropSystem.STAGE_WORDS.get(stage, stage)).to_lower(), floori(float(b.get("progress", 0.0)) * 100.0 + 1e-6)]
	if stage == "wilted":
		return ["✖ %s: wilted, plant again" % name, UiTheme.URGENT]
	if stage == "ready":
		return ["✓ %s · ready to harvest" % text, UiTheme.GOOD]
	var symptoms := CropSystem.symptoms_of(st, b)
	if symptoms.is_empty():
		return ["✓ %s · healthy" % text, UiTheme.GOOD]
	var words := PackedStringArray()
	for s: String in symptoms:
		var info: Dictionary = CropSystem.SYMPTOMS[s]
		words.append("%s (%s)" % [String(info.see).to_lower(), String(info.cause)])
	return ["! %s · %s" % [text, ", ".join(words)], UiTheme.WARN]


func _fill_automation(lines: Array) -> void:
	while _automation_box.get_child_count() < lines.size():
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_automation_box.add_child(l)
	for i in _automation_box.get_child_count():
		var l := _automation_box.get_child(i) as Label
		var ok := String(lines[i].level) == "ok"
		l.text = ("✓ " if ok else "○ ") + String(lines[i].text)
		l.theme_type_variation = UiTheme.GOOD if ok else UiTheme.MUTED


func _refresh_results(st: ColonyState) -> void:
	var results: Dictionary = st.science.get("results", {}) if st.science.get("results", null) is Dictionary else {}
	var applied: Array = st.crops.get("applied_results", [])
	var usable: Array = []
	for rid: String in results:
		var r: Variant = results[rid]
		if r is Dictionary and String((r as Dictionary).get("kind", "")) == "nutrient_setting":
			usable.append(rid)
	usable.sort()
	var allowed := st.has_upgrade("sci_evidence_settings")
	if usable.is_empty():
		_results_note.text = "No nutrient setting from the lab yet. Compare a field sample in the lab to get one."
	elif not allowed:
		_results_note.text = "The lab has a nutrient setting. With the evidence-based settings upgrade you can apply it here; until then set nutrients by hand at each bed."
	else:
		_results_note.text = "Apply a lab nutrient setting to every growing bed."
	for rid: String in usable:
		if not result_buttons.has(rid):
			var b := Button.new()
			b.name = "Apply_%s" % rid.validate_node_name()
			b.pressed.connect(func() -> void: _ask(&"apply_nutrient_result", {"result_id": rid}, _on_answer))
			_results_box.add_child(b)
			result_buttons[rid] = b
	for rid: String in result_buttons:
		var b := result_buttons[rid] as Button
		var r: Dictionary = results.get(rid, {}) if results.get(rid, null) is Dictionary else {}
		b.visible = usable.has(rid)
		var done := applied.has(rid)
		b.text = "%s Lab result: nutrients %d %%" % ["✓ Applied ·" if done else "Apply ·", roundi(float(r.get("value", 0.0)) * 100.0)]
		b.disabled = done or not allowed
