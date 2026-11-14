class_name PowerLifePanel
extends UiPanel
## "Power & life support": the drawer that opens on the right when you click a supply on the vitals bar or press P.
## What the colony makes against what it uses, the battery and when it runs out, every room and machine that draws
## power, and what the crew's air, water and food did in the last game hour, scaled to a sol. It only shows: rooms and
## machines are switched at the power panel in the Power Room, by someone standing there. The ? opens the science.

var _making: AstraStyle.Meter
var _making_l: Label
var _using: AstraStyle.Meter
var _using_l: Label
var _battery: AstraStyle.Meter
var _battery_l: Label
var _verdict: Label
var _verdict_box: PanelContainer
var _sources: VBoxContainer
var _problems: VBoxContainer
var _expanded: Dictionary = {}
var _loads: VBoxContainer
var _life: VBoxContainer
var _air: Label
var _sig := ""


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	name = "PowerLifePanel"
	align_right = true
	max_width = 470
	accent_line = false
	add_theme_stylebox_override(&"panel", AstraStyle.glass(AstraStyle.RADIUS, 18, 16, true))
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := AstraStyle.label("Power & life support", 20, AstraStyle.TEXT, "Title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var help := AstraStyle.flat_button("?", 18, AstraStyle.TEXT_2)
	help.name = "Help"
	help.focus_mode = Control.FOCUS_ALL
	help.tooltip_text = "The science behind these numbers"
	help.pressed.connect(func() -> void:
		var p := VitalsSciencePanel.new()
		open_requested.emit(p))
	head.add_child(help)
	var close := AstraStyle.flat_button("×", 20, AstraStyle.TEXT_2)
	close.name = "Close"
	close.focus_mode = Control.FOCUS_ALL
	close.tooltip_text = "Close (Esc or P)"
	close.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override(&"separation", 10)
	scroll.add_child(content)

	var meters := AstraStyle.panel(AstraStyle.pill(Color(1, 1, 1, 0.04), AstraStyle.RADIUS_SM + 2, 14, 12, AstraStyle.LINE), "Balance")
	content.add_child(meters)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	meters.add_child(grid)
	_making = _meter_row(grid, "☀", "Making", AstraStyle.C_POWER)
	_making_l = grid.get_child(grid.get_child_count() - 1) as Label
	_using = _meter_row(grid, "⏻", "Using", AstraStyle.ACCENT)
	_using_l = grid.get_child(grid.get_child_count() - 1) as Label
	_battery = _meter_row(grid, "▮", "Battery", AstraStyle.GOOD)
	_battery_l = grid.get_child(grid.get_child_count() - 1) as Label
	_verdict_box = AstraStyle.panel(AstraStyle.pill(Color(AstraStyle.GOOD, 0.12), AstraStyle.RADIUS_SM, 12, 8), "Verdict")
	content.add_child(_verdict_box)
	_verdict = AstraStyle.label("", 14, AstraStyle.GOOD, "Text")
	_verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_verdict_box.add_child(_verdict)

	content.add_child(_section("MAKING POWER"))
	_sources = VBoxContainer.new()
	_sources.add_theme_constant_override(&"separation", 8)
	content.add_child(_sources)
	_problems = VBoxContainer.new()
	_problems.name = "PowerProblems"
	content.add_child(_problems)
	content.add_child(_section("USING POWER"))
	_loads = VBoxContainer.new()
	_loads.add_theme_constant_override(&"separation", 6)
	content.add_child(_loads)
	var note := AstraStyle.label("Rooms and machines are switched at the power panel in the Power Room, by someone standing there.", 12, AstraStyle.TEXT_3)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note)
	content.add_child(_section("LIFE SUPPORT TODAY"))
	_life = VBoxContainer.new()
	_life.add_theme_constant_override(&"separation", 6)
	content.add_child(_life)
	_air = AstraStyle.label("", 13, AstraStyle.TEXT_2, "CabinAir")
	_air.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_air)


func panel_title() -> String:
	return "Power & life support"


func first_focus() -> Control:
	return find_child("Close", true, false) as Control


func _meter_row(grid: GridContainer, symbol: String, word: String, color: Color) -> AstraStyle.Meter:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 6)
	h.custom_minimum_size.x = 92
	h.add_child(AstraStyle.label(symbol, 15, color, "", true))
	h.add_child(AstraStyle.label(word, 14, AstraStyle.TEXT_2))
	grid.add_child(h)
	var m := AstraStyle.Meter.new(color, 9.0)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.custom_minimum_size.x = 160
	grid.add_child(m)
	var l := AstraStyle.label("", 14, AstraStyle.TEXT, word)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size.x = 112
	grid.add_child(l)
	return m


func _section(text: String) -> Label:
	var l := AstraStyle.label(text, 11, AstraStyle.TEXT_3)
	return l


func _line(parent: Control, symbol: String, color: Color, title: String, sub: String, value: String, value_color: Color, problem := false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	parent.add_child(row)
	var badge := AstraStyle.panel(AstraStyle.pill(Color(color, 0.14), 8, 7, 3), "")
	badge.add_child(AstraStyle.label(symbol, 14, color, "", true))
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", -2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(AstraStyle.label(title, 14, AstraStyle.DANGER if problem else AstraStyle.TEXT))
	if sub != "":
		var s := AstraStyle.label(sub, 11, AstraStyle.DANGER if problem else AstraStyle.TEXT_3)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(s)
	var v := AstraStyle.label(value, 14, value_color)
	row.add_child(v)


func refresh() -> void:
	if services == null or not services.has_game():
		return
	var st := services.state()
	var b := services.balance
	var cap := float(st.capacities.get(&"battery_kwh", 0.0))
	var stored := st.store(&"battery_kwh")
	var top := maxf(maxf(st.solar_kw, st.load_kw), 0.1)
	_making.share = st.solar_kw / top
	_making_l.text = "%s kW" % ColonySummaryPanel.num(st.solar_kw)
	_using.share = st.load_kw / top
	_using_l.text = "%s kW" % ColonySummaryPanel.num(st.load_kw)
	_battery.share = stored / cap if cap > 0.0 else 0.0
	_battery_l.text = "%d/%d kWh" % [roundi(stored), roundi(cap)]
	var forecast := ReserveForecast.compute(st, b, services.clock())
	var day := services.clock().is_daylight()
	var verdict := ""
	var vc := AstraStyle.GOOD
	if st.power_deficit:
		verdict = "Not enough power! Some rooms or machines are going without. Switch off what you do not need at the power panel."
		vc = AstraStyle.DANGER
	elif st.battery_kw > 0.05:
		verdict = "Making more than you use: the battery is charging."
	elif st.battery_kw < -0.05:
		var h := float(forecast.get("battery_hours", -1.0))
		verdict = "Using more than you make: the battery is draining%s." % (" and lasts about %s at this rate" % VitalsBar._left_words(h) if h >= 0.0 and h < 1000.0 else "")
		if not day:
			verdict += " It is night: the panels make nothing until sunrise."
		vc = AstraStyle.WARN
	else:
		verdict = "Making exactly what you use."
	_verdict.text = verdict
	AstraStyle.set_color(_verdict, vc)
	_verdict_box.add_theme_stylebox_override(&"panel", AstraStyle.pill(Color(vc, 0.12), AstraStyle.RADIUS_SM, 12, 8))

	var sig := JSON.stringify([st.zones, st.equipment, snappedf(st.solar_kw, 0.1), st.rates, st.shed, st.panel_dust, day, snappedf(st.battery_kw, 0.1), _expanded])
	if sig == _sig:
		return
	_sig = sig
	for box: VBoxContainer in [_sources, _loads, _life, _problems]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	var dust := 0.0
	for d: Variant in st.panel_dust:
		dust += float(d)
	dust = dust / maxf(1.0, st.panel_dust.size())
	_line(_sources, "☀", AstraStyle.C_POWER, "Sun trackers (%d)" % ColonyState.TRACKER_COUNT,
		"Electricity while the Sun shines · dust on the panels %d %%" % roundi(dust * 100.0) if day else "Night: no sunlight, no power",
		"+%s kW" % ColonySummaryPanel.num(st.solar_kw), AstraStyle.C_POWER)
	if st.battery_kw < -0.05:
		_line(_sources, "▮", AstraStyle.GOOD, "Battery", "Covering the gap", "+%s kW" % ColonySummaryPanel.num(-st.battery_kw), AstraStyle.GOOD)
	var categories := {"Room lighting": [], "Greenhouse": [], "Life support machines": [], "Solar equipment": [], "Control & heating": []}
	var problems: Array[Dictionary] = []
	var zones: Array = st.zones.keys()
	zones.sort()
	for zone: String in zones:
		var on := st.is_zone_powered(zone)
		var expected := b.load_of_zone(zone)
		if expected <= 0.0:
			continue
		var group := "greenhouse" if zone == PowerModel.GREENHOUSE_ZONE else ("base" if b.critical_light_zones.has(zone) else "lights")
		var missing := on and st.shed.has(group)
		var row := {"title": zone, "kw": expected if on and not missing else 0.0,
			"sub": "No power: supply shortage switched these lights off." if missing else ("Lights and room systems" if on else "Switched off"), "problem": missing}
		categories["Greenhouse" if zone == PowerModel.GREENHOUSE_ZONE else "Room lighting"].append(row)
		if missing:
			problems.append(row)
	for id: String in ColonyState.EQUIPMENT_IDS:
		var e: Dictionary = st.equipment.get(id, {})
		if e.is_empty():
			continue
		var problem := equipment_problem(st, b, id)
		var running := st.is_on(id) and st.is_powered(id) and st.condition_of(id) >= b.equipment_min_condition
		var row := {"title": StationPanel.equipment_name(id), "kw": float(e.get("kw", 0.0)) if running else 0.0,
			"sub": problem if problem != "" else ("Running" if running else ("Idle: no production needed" if st.is_on(id) else "Switched off")), "problem": problem != ""}
		categories["Solar equipment" if id in ["trackers", "cleaner"] else "Life support machines"].append(row)
		if problem != "":
			problems.append(row)
	var base_missing := st.shed.has("base")
	var base_row := {"title": "Control & heating", "kw": 0.0 if base_missing else b.base_load_kw,
		"sub": "No power: control and heating stopped." if base_missing else "Essential colony systems", "problem": base_missing}
	categories["Control & heating"].append(base_row)
	if base_missing:
		problems.append(base_row)
	# Compare solar with a clean, working array at this time of day, never with noon output at night.
	var solar_problem := solar_problem_text(st, b, day)
	if solar_problem != "":
		problems.append({"title": "Solar generation", "kw": st.solar_kw, "sub": solar_problem, "problem": true})
	_problems.visible = not problems.is_empty()
	if not problems.is_empty():
		_problems.add_child(AstraStyle.label("POWER PROBLEMS", 11, AstraStyle.DANGER))
		for row: Dictionary in problems:
			_power_row(_problems, row)
	for category: String in categories:
		_category(category, categories[category])
	for s: Dictionary in VitalsBar.STOCKS:
		if s.key == &"battery_kwh":
			continue
		var per_sol := float(st.rates.get(String(s.key), 0.0)) * GameConfig.SOL_HOURS
		var sign := "+" if per_sol >= 0.0 else ""
		_line(_life, String(s.symbol), s.color, String(s.name), "%s %s in store" % [VitalsBar._amount(s.key, st.store(s.key)), s.unit],
			"%s%s %s/sol" % [sign, ColonySummaryPanel.num(per_sol), s.unit], AstraStyle.GOOD if per_sol >= 0.0 else AstraStyle.TEXT_2)
	var kpa := StationPanel.cabin_kpa(st, b)
	_air.text = "Cabin air: oxygen %s kPa (%s) · carbon dioxide %s kPa (%s)" % [StationPanel.num(float(kpa.o2), 1),
		StationPanel.o2_word(StationPanel.o2_level(float(kpa.o2), b)).to_lower(), StationPanel.num(float(kpa.co2), 2),
		StationPanel.co2_word(StationPanel.co2_level(float(kpa.co2), b)).to_lower()]


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"power_view"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


## Significant deviations are relative to this machine, not to unrelated rooms.
static func equipment_problem(st: ColonyState, b: GameBalance, id: String) -> String:
	if not st.is_on(id):
		return ""
	if st.condition_of(id) < b.equipment_min_condition:
		return "Drawing no power: equipment is broken. Repair it."
	if st.shed.has(id) or not st.is_powered(id):
		return "Drawing no power: insufficient supply. Reduce other loads or restore generation."
	# Oxygen makers vary with demand and available inputs; low production is not an electrical fault.
	if id in ["electrolyser", "co2_unit"]:
		return ""
	var expected := PowerModel.equipment_kw(st, b, id, {})
	var actual := float(st.unit(id).get("kw", 0.0))
	if expected <= 0.05 or absf(actual - expected) <= maxf(0.1, expected * 0.3):
		return ""
	return "%s power draw: %s kW; expected %s kW. Check this machine." % ["Unusually high" if actual > expected else "Unusually low", ColonySummaryPanel.num(actual), ColonySummaryPanel.num(expected)]


static func solar_problem_text(st: ColonyState, b: GameBalance, day: bool) -> String:
	if not day:
		return ""
	if st.condition_of("trackers") < b.equipment_min_condition:
		return "Low output: sun trackers are broken. Repair the tracker drives."
	if PowerModel.average_dust(st) >= 0.3:
		return "Low output: dust blocks %d %% of panel output. Clean the panels." % roundi(PowerModel.average_dust(st) * 100.0)
	if st.is_on("trackers") and not st.is_powered("trackers"):
		return "Low output: tracker drives have no power; panels cannot follow the Sun."
	return ""


func _power_row(parent: Control, row: Dictionary) -> void:
	var issue := bool(row.problem)
	var color := AstraStyle.DANGER if issue else AstraStyle.TEXT_2
	_line(parent, "!" if issue else "•", color, String(row.title), String(row.sub),
		"%s kW" % ColonySummaryPanel.num(float(row.kw)), color, issue)


func _category(title: String, rows: Array) -> void:
	if rows.is_empty():
		return
	var total := 0.0
	for row: Dictionary in rows:
		total += float(row.kw)
	var open := bool(_expanded.get(title, false))
	var button := AstraStyle.flat_button("%s %s · %s kW" % ["−" if open else "+", title, ColonySummaryPanel.num(total)], 14, AstraStyle.TEXT_2)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = "Show or hide individual readings"
	button.pressed.connect(func() -> void:
		_expanded[title] = not bool(_expanded.get(title, false))
		refresh())
	_loads.add_child(button)
	if open:
		for row: Dictionary in rows:
			_power_row(_loads, row)
