extends SceneTree
## Prompt 07 panels: the power panel, the life-support console, the sun trackers, the suit rack, the colony summary,
## the blueprint and the HUD, all reading the real energy and life-support model.
## Run: ..\godot.cmd --headless --path . --script res://tests/test_p07_panels.gd
## The simulation is ticked by hand (services.session.advance one tick at a time), so every value is known.


## Records every request a panel sends, then lets the host answer it as usual.
class RecordingServices extends GameServices:
	var sent: Array = []

	func request(action: StringName, target: StringName = &"", params := {}) -> ActionResult:
		sent.append({"action": action, "target": target, "params": params.duplicate()})
		return super.request(action, target, params)

	func sent_of(action: StringName) -> Array:
		return sent.filter(func(r: Dictionary) -> bool: return r.action == action)


## Collects engine and script errors raised while the test runs.
class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR or error_type == ERROR_TYPE_SCRIPT:
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


const SIZES := [[Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 1.0], [Vector2i(1280, 720), 1.5]]

var _passed := 0
var _total := 0
var _catcher := ErrorCatcher.new()
var services: RecordingServices


func _initialize() -> void:
	OS.add_logger(_catcher)
	PlayerInput.ensure_actions()
	services = RecordingServices.new()
	services.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/p07"), "colony", 2)
	root.add_child(services)
	services.start_new_game(1)
	await _frames()
	services.set_process(false)          # ticks only by hand
	_tick()

	_test_mapping()
	await _test_power_switches()
	await _test_power_forecast_and_shedding()
	await _test_life_support_switches()
	await _test_water_sliders()
	await _test_oxygen_processes()
	await _test_cabin_air()
	await _test_solar()
	await _test_suit_rack()
	await _test_hud()
	await _test_layouts()

	_check("no script or engine errors during the test", _catcher.errors.is_empty(), "\n".join(_catcher.errors))
	OS.remove_logger(_catcher)
	services.queue_free()
	await process_frame
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


# ---------------------------------------------------------------- helpers

func _check(test_name: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS %s" % test_name)
	else:
		print("FAIL %s: %s" % [test_name, detail])


func _frames(n := 2) -> void:
	for i in n:
		await process_frame


## Runs `n` simulation ticks.
func _tick(n := 1) -> void:
	for i in n:
		services.session.advance(1.0 / services.config.sim_tick_hz)


func _station_pos(id: String) -> Vector3:
	return CharacterState._v3(services.state().stations[id].position)


## Opens the station panel for `id` with the local character standing at it.
func _open(id: String) -> StationPanel:
	services.local_character().position = _station_pos(id)
	var panel := StationPanels.for_station(StringName(id), services) as StationPanel
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames()
	panel.refresh()
	return panel


func _close(panel: Control) -> void:
	panel.queue_free()
	await process_frame


## Sets equipment through the host, standing at the power panel (test setup, not a panel action).
func _set_equipment(id: String, on: bool) -> void:
	var me := services.local_character()
	var keep := me.position
	me.position = _station_pos("pw_panel")
	services.session.request(&"set_equipment", &"pw_panel", {"equipment": id, "on": on})
	me.position = keep


func _set_allocation(greenhouse: float, feed: float) -> void:
	var me := services.local_character()
	var keep := me.position
	me.position = _station_pos("ls_console")
	services.session.request(&"set_water_allocation", &"ls_console", {"greenhouse_l_per_hour": greenhouse, "electrolysis_feed_l_per_hour": feed})
	me.position = keep


## Switches every machine back to its arrival state (electrolyser and CO2 unit off, everything else on).
func _arrival_equipment() -> void:
	for id in ColonyState.EQUIPMENT_IDS:
		_set_equipment(id, id != "electrolyser" and id != "co2_unit")


## Hands the local player over to crew member `id` (the old one is walked to the hub first).
func _become(id: StringName) -> void:
	var me := services.local_character()
	me.position = me.hub_spot
	services.session.request(&"claim_character", id)


# ---------------------------------------------------------------- station mapping

func _test_mapping() -> void:
	var st := services.state()
	var bad := PackedStringArray()
	var kinds := {}
	for id: String in st.stations:
		var kind := String(st.stations[id].kind)
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		var panel := StationPanels.for_station(StringName(id), services)
		var ok := false
		match kind:
			"power": ok = panel is PowerStationPanel
			"lifesupport": ok = panel is LifeSupportStationPanel
			"solar": ok = panel is SolarStationPanel
			"suits": ok = panel is SuitRackPanel
			_: ok = panel is StationPanel and not (panel is PowerStationPanel or panel is LifeSupportStationPanel or panel is SolarStationPanel or panel is SuitRackPanel)
		if panel != null:
			ok = ok and bool(panel.get_meta(&"station_surface", false)) and StringName(panel.get_meta(&"station_id", &"")) == StringName(id)
			panel.free()
		if not ok:
			bad.append("%s (%s)" % [id, kind])
	var base_count := 0
	for k: String in ["power", "computer", "comms", "food", "lifesupport", "heal", "board", "survivor", "suits", "solar"]:
		base_count += int(kinds.get(k, 0))
	_check("every station of a new game maps to the right panel class (21 base + those added by data files)", base_count == 21
		and int(kinds.get("solar", 0)) == 12 and int(kinds.get("suits", 0)) == 1 and int(kinds.get("lifesupport", 0)) == 1 and bad.is_empty(),
		"%d stations %s, wrong: %s" % [st.stations.size(), kinds, ", ".join(bad)])


# ---------------------------------------------------------------- power panel

## Toggles every equipment switch of `panel` once: exactly one set_equipment with the right id and value, and after
## the host's answer and a tick the switch and its status show the new state. Returns the problems found.
func _toggle_all(panel: StationPanel, ids: Array) -> PackedStringArray:
	var st := services.state()
	var problems := PackedStringArray()
	for id: String in ids:
		var sw := panel.equipment_switches.get(id) as CheckButton
		if sw == null:
			problems.append("%s has no switch" % id)
			continue
		var want := not st.is_on(id)
		services.sent.clear()
		sw.button_pressed = want
		var sent := services.sent_of(&"set_equipment")
		if services.sent.size() != 1 or sent.size() != 1 or String(sent[0].params.get("equipment", "")) != id or bool(sent[0].params.get("on", not want)) != want \
				or sent[0].target != panel.station_id:
			problems.append("%s: sent %s" % [id, str(services.sent)])
		_tick()
		panel.refresh()
		var status := panel.equipment_status_text(id)
		if st.is_on(id) != want or sw.button_pressed != want or (want and status.begins_with("○ Off")) or (not want and status != "○ Off"):
			problems.append("%s: on %s, switch %s, status '%s'" % [id, st.is_on(id), sw.button_pressed, status])
	return problems


func _test_power_switches() -> void:
	var panel: PowerStationPanel = await _open("pw_panel")
	var problems := _toggle_all(panel, PowerStationPanel.EQUIPMENT_ORDER)
	var cause := panel.cause_text()
	_check("power panel: each equipment switch sends one set_equipment and shows the state after the answer and a tick",
		problems.is_empty(), "; ".join(problems))
	_check("power panel: a cause-and-effect sentence after a machine switch", cause.contains("The colony now asks for") and cause.contains(" kW"), cause)
	_arrival_equipment()
	_tick()
	panel.refresh()
	var labels_ok := true
	for id in PowerStationPanel.EQUIPMENT_ORDER:
		labels_ok = labels_ok and (panel.equipment_switches[id] as CheckButton).text.contains(" kW")
	_check("power panel: every machine switch shows its kW", labels_ok)
	await _close(panel)


func _test_power_forecast_and_shedding() -> void:
	var st := services.state()
	var clock := services.clock()
	var panel: PowerStationPanel = await _open("pw_panel")
	panel.refresh()
	var forecast := ReserveForecast.compute(st, services.balance, clock)
	var lines: Array = forecast.text
	var want := "%s\n%s" % [lines[0], lines[1]]
	_check("power panel: forecast text matches ReserveForecast.compute()", panel.forecast_text() == want
		and want.contains("Battery at the next sunrise: about"), "%s | %s" % [panel.forecast_text(), want])
	_check("power panel: battery as an amount (kWh of capacity, %)", panel.reading_text(&"battery").contains(" kWh (") and panel.reading_text(&"battery").contains("%)"),
		panel.reading_text(&"battery"))
	_check("power panel: no loads shed at the start, said in words", st.shed.is_empty() and panel.shed_text().contains("Every load that is switched on has power"), panel.shed_text())

	# Overload: night, a nearly empty battery, everything switched on.
	var saved_phase := clock.phase
	var saved_battery := st.store(&"battery_kwh")
	clock.phase = 0.9
	st.stores[&"battery_kwh"] = 0.05
	_set_allocation(0.0, 1.0)
	for id in ColonyState.EQUIPMENT_IDS:
		_set_equipment(id, true)
	for zone: String in st.zones:
		st.zones[zone]["powered"] = true
	_tick()
	panel.refresh()
	var text := panel.shed_text()
	var missing := PackedStringArray()
	for id: String in st.shed:
		if not text.contains(StationPanel.words(String(PowerModel.SHED_TEXT[id]))):
			missing.append(id)
	_check("power panel: after an overload the shed loads are listed in words, with why (%s)" % ", ".join(st.shed), not st.shed.is_empty()
		and missing.is_empty() and text.contains("Not enough power") and panel.reading_text(&"served").contains("some loads have no power"),
		"shed %s, missing %s, text: %s" % [st.shed, missing, text.replace("\n", " | ")])
	_check("power panel: shedding order explained", PowerStationPanel.shedding_order_text().begins_with("When power is short")
		and PowerStationPanel.shedding_order_text().contains("room lights, greenhouse lights, CO₂-oxygen unit"), PowerStationPanel.shedding_order_text())
	var shed_status := panel.equipment_status_text(String(st.shed[st.shed.size() - 1])) if not st.shed.is_empty() and ColonyState.EQUIPMENT_IDS.has(String(st.shed[st.shed.size() - 1])) else ""
	_check("power panel: a shed machine's switch says it has no power", shed_status == "" or shed_status.contains("No power"), shed_status)
	var alerts := "\n".join(panel.alert_texts())
	_check("power panel: energy alerts shown at the top in words", alerts.contains("stopped: no power"), alerts)

	# back to normal
	clock.phase = saved_phase
	st.stores[&"battery_kwh"] = saved_battery
	_arrival_equipment()
	_set_allocation(0.0, 0.0)
	_tick()
	await _close(panel)


# ---------------------------------------------------------------- life support

func _test_life_support_switches() -> void:
	var panel: LifeSupportStationPanel = await _open("ls_console")
	var problems := _toggle_all(panel, ["recycler", "electrolyser", "co2_unit", "scrubber", "cabin_fans"])
	_check("life support: each equipment switch sends one set_equipment and shows the state after the answer and a tick",
		problems.is_empty(), "; ".join(problems))
	_arrival_equipment()
	_tick()
	panel.refresh()
	var alerts := panel.alert_texts()
	_check("life support: alerts for these systems at the top in words", not alerts.is_empty() and not "\n".join(alerts).contains("Panel cleaner"),
		"\n".join(alerts))
	await _close(panel)


func _test_water_sliders() -> void:
	var st := services.state()
	var panel: LifeSupportStationPanel = await _open("ls_console")
	var gh := panel.slider("greenhouse_l_per_hour")
	var feed := panel.slider("electrolysis_feed_l_per_hour")
	var details := PackedStringArray()
	# a mouse drag: many value changes while dragging, one request on release
	services.sent.clear()
	gh.drag_started.emit()
	gh.value = 1.0
	gh.value = 2.5
	gh.value = 4.0
	var during := services.sent.size()
	gh.drag_ended.emit(true)
	var sent := services.sent_of(&"set_water_allocation")
	var ok_gh := during == 0 and services.sent.size() == 1 and sent.size() == 1 and is_equal_approx(float(sent[0].params.greenhouse_l_per_hour), 4.0) \
		and is_equal_approx(float(sent[0].params.electrolysis_feed_l_per_hour), 0.0) and is_equal_approx(float(st.water_allocation.greenhouse_l_per_hour), 4.0)
	details.append("greenhouse: %d while dragging, sent %s" % [during, str(services.sent)])
	services.sent.clear()
	feed.drag_started.emit()
	feed.value = 2.0
	feed.drag_ended.emit(true)
	sent = services.sent_of(&"set_water_allocation")
	var ok_feed := services.sent.size() == 1 and sent.size() == 1 and is_equal_approx(float(sent[0].params.electrolysis_feed_l_per_hour), 2.0) \
		and is_equal_approx(float(sent[0].params.greenhouse_l_per_hour), 4.0) and is_equal_approx(float(st.water_allocation.electrolysis_feed_l_per_hour), 2.0)
	details.append("feed: sent %s" % str(services.sent))
	_check("life support: each water slider sends one set_water_allocation per release with both values", ok_gh and ok_feed, "; ".join(details))
	# keyboard: one arrow press is one finished change
	services.sent.clear()
	feed.value = 2.5
	sent = services.sent_of(&"set_water_allocation")
	_check("life support: a keyboard change of a slider sends one request", sent.size() == 1 and is_equal_approx(float(sent[0].params.electrolysis_feed_l_per_hour), 2.5),
		str(services.sent))
	_tick()
	panel.refresh()
	var all := _all_text(panel)
	_check("life support: protected reserve is stated and allocation changes are confirmed", all.contains("Drinking reserve: %s L" % StationPanel.num(services.balance.water_reserve_l, 0))
		and panel.cause_text().contains("Water allocation"),
		panel.cause_text())
	_set_allocation(0.0, 0.0)
	await _close(panel)


func _test_oxygen_processes() -> void:
	var st := services.state()
	var bal := services.balance
	var panel: LifeSupportStationPanel = await _open("ls_console")
	_set_allocation(0.0, 0.5)
	_set_equipment("electrolyser", true)
	_set_equipment("co2_unit", true)
	_tick()
	panel.refresh()
	var kg := StationPanel.process_o2_kg_per_hour(st, bal, "electrolyser")
	var e_water := panel.process_water_text("electrolyser")
	var c_water := panel.process_water_text("co2_unit")
	var c_card := panel.process_card_text("co2_unit")
	_check("life support: the electrolyser shows its water use (L per hour)", kg > 0.0 and e_water == "Takes %s L of water per hour" % StationPanel.num(kg * GameBalance.WATER_KG_PER_KG_O2, 3)
		and String(st.oxygen_process.electrolyser) in ["running", "feed_short"], "%s (status %s, %.4f kg/h)" % [e_water, st.oxygen_process.electrolyser, kg])
	_check("life support: the CO2-oxygen unit shows no water use", c_water.contains("no water") and not c_card.contains("L of water")
		and StationPanel.process_o2_kg_per_hour(st, bal, "co2_unit") > 0.0 and panel.process_card_text("co2_unit").contains("Makes"), c_card.replace("\n", " | "))
	_check("life support: both processes side by side with kg per hour and kW", panel.process_card_text("electrolyser").contains("kg of oxygen per hour")
		and panel.process_card_text("electrolyser").contains(" kW") and panel.process_card_text("co2_unit").contains(" kW"), panel.process_card_text("electrolyser").replace("\n", " | "))

	_set_allocation(0.0, 0.0)
	_tick()
	panel.refresh()
	var no_feed := panel.process_status_text("electrolyser")
	_check("life support: stopped reason when the feed is 0", String(st.oxygen_process.electrolyser) == "no_feed" and no_feed.contains("Stopped: no water is sent to it")
		and panel.process_water_text("electrolyser") == "Takes 0 L of water per hour", "%s / %s" % [no_feed, panel.process_water_text("electrolyser")])

	_set_allocation(0.0, 0.5)
	st.water_quality = 0.5
	_tick()
	panel.refresh()
	var dirty := panel.process_status_text("electrolyser")
	_check("life support: stopped reason when the water quality is low", String(st.oxygen_process.electrolyser) == "dirty_water" and dirty.contains("not clean enough")
		and panel.reading_text(&"quality").contains("Not clean enough"), "%s / %s" % [dirty, panel.reading_text(&"quality")])
	st.water_quality = 1.0
	_set_allocation(0.0, 0.0)
	_arrival_equipment()
	_tick()
	await _close(panel)


func _test_cabin_air() -> void:
	var st := services.state()
	var bal := services.balance
	var panel: LifeSupportStationPanel = await _open("ls_console")
	panel.refresh()
	var o2 := panel.readings[&"o2"] as StationPanel.Reading
	var co2 := panel.readings[&"co2"] as StationPanel.Reading
	var pressure := panel.readings[&"pressure"] as StationPanel.Reading
	_check("cabin air: O2, CO2 and pressure in kPa with words", o2.value_label.text.ends_with("kPa · Safe") and co2.value_label.text.ends_with("kPa · Safe")
		and pressure.value_label.text.ends_with("kPa · Safe") and o2.level == &"ok" and co2.level == &"ok",
		"%s / %s / %s" % [o2.value_label.text, co2.value_label.text, pressure.value_label.text])
	var saved := st.cabin_co2_kg
	st.cabin_co2_kg = bal.gas_kg_for_kpa(0.7, GameBalance.MOLAR_CO2)
	_tick()
	panel.refresh()
	var warn_text := co2.value_label.text
	var warn_level := co2.level
	var alert_seen := "\n".join(panel.alert_texts()).contains("Carbon dioxide is building up")
	st.cabin_co2_kg = bal.gas_kg_for_kpa(1.3, GameBalance.MOLAR_CO2)
	panel.refresh()
	_check("cabin air: raising CO2 changes the level and the word (High, then Dangerous)", warn_level == &"warn" and warn_text.contains("High")
		and co2.level == &"urgent" and co2.value_label.text.contains("Dangerous") and co2.mark_label.text == "✖", "%s / %s" % [warn_text, co2.value_label.text])
	_check("cabin air: the CO2 alert appears at the top in words", alert_seen, "\n".join(panel.alert_texts()))
	_check("cabin air: room air is explained in help", String(Explanations.get_entry("cabin_air").long).contains("tank"))
	st.cabin_co2_kg = saved
	_tick()
	await _close(panel)


# ---------------------------------------------------------------- sun tracker

func _test_solar() -> void:
	var st := services.state()
	var tracker := "sf_solar_tracker.003"
	var index := int(st.stations[tracker].tracker)
	var me := services.local_character()
	var panel: SolarStationPanel = await _open(tracker)
	var others_before: Array = st.panel_dust.duplicate()
	services.sent.clear()
	panel.clean_button.pressed.emit()
	panel.refresh()
	var others_same := true
	for i in st.panel_dust.size():
		if i != index:
			others_same = others_same and is_equal_approx(float(st.panel_dust[i]), float(others_before[i]))
	_check("solar: 'Clean this panel' sends one clean_panel and this tracker's dust goes to 0", services.sent_of(&"clean_panel").size() == 1 and services.sent.size() == 1
		and float(st.panel_dust[index]) == 0.0 and others_same and panel.reading_text(&"dust").begins_with("0 %"), "%s / %s" % [st.panel_dust, panel.reading_text(&"dust")])
	_check("solar: shows this panel's output, the whole array and the trackers", panel.reading_text(&"output").contains(" kW") and panel.reading_text(&"array").contains(" kW")
		and panel.reading_text(&"tracking").begins_with("Yes") and panel.reading_text(&"cleaner").begins_with("Broken"),
		"%s | %s | %s | %s" % [panel.reading_text(&"output"), panel.reading_text(&"array"), panel.reading_text(&"tracking"), panel.reading_text(&"cleaner")])

	_check("solar: repair enabled for the electrical specialist while the cleaner is broken", me.specialty == &"electrical_comms" and not panel.repair_button.disabled,
		"%s disabled %s: %s" % [me.specialty, panel.repair_button.disabled, panel.repair_reason_text()])
	_become(&"crew_2")
	var medic := services.local_character()
	medic.position = _station_pos(tracker)
	panel.refresh()
	var host := services.session.request(&"repair_cleaner", StringName(tracker))
	_check("solar: repair disabled for a non-electrical crew member, with the reason in words", medic.id == &"crew_2" and panel.repair_button.disabled and panel.repair_button.visible
		and panel.repair_reason_text().contains("Only the electrical and communications specialist") and host.reason == &"wrong_specialty",
		"%s: %s (host %s)" % [medic.id, panel.repair_reason_text(), host.reason])
	_become(&"crew_1")
	me = services.local_character()
	me.position = _station_pos(tracker)
	panel.refresh()
	services.sent.clear()
	panel.repair_button.pressed.emit()
	panel.refresh()
	_check("solar: the electrical specialist repairs the cleaner, then the button says why it is off", services.sent_of(&"repair_cleaner").size() == 1
		and st.condition_of("cleaner") >= 1.0 and panel.repair_button.disabled and panel.repair_reason_text().contains("not broken")
		and panel.cause_text().contains("Panel cleaner repaired"), "%s / %s" % [panel.repair_reason_text(), panel.cause_text()])
	await _close(panel)


# ---------------------------------------------------------------- suit rack

func _test_suit_rack() -> void:
	var st := services.state()
	var bal := services.balance
	var me := services.local_character()
	var panel: SuitRackPanel = await _open("al_suit_rack")
	me.suit_on = false
	me.suit_charge = 40.0
	panel.refresh()
	var note := panel.fill_note_text()
	var reserve_before := st.store(&"oxygen_kg")
	var tank_before := LifeSupportModel.suit_kg(bal, me)
	services.sent.clear()
	panel.fill_button.pressed.emit()
	var gained := LifeSupportModel.suit_kg(bal, me) - tank_before
	var taken := reserve_before - st.store(&"oxygen_kg")
	_check("suit rack: fill sends one refill_suit; the reserve falls by exactly what the tank gains", services.sent_of(&"refill_suit").size() == 1 and services.sent.size() == 1
		and absf(gained - taken) < 1e-9 and absf(gained - 0.6 * bal.suit_o2_capacity_kg) < 1e-9 and me.suit_charge == 100.0,
		"gained %.6f kg, taken %.6f kg" % [gained, taken])
	_check("suit rack: shows the oxygen cost and explains refilling in help",
		note.contains("Filling takes %s kg of oxygen from the colony reserve" % StationPanel.num(0.6 * bal.suit_o2_capacity_kg, 3)) and String(Explanations.get_entry("suit_refill").long).contains("does not fill the tank"), note)
	panel.refresh()
	_check("suit rack: a full tank disables the fill button with the reason", panel.fill_button.disabled and panel.fill_note_text().contains("already full"), panel.fill_note_text())

	services.sent.clear()
	panel.suit_button.pressed.emit()
	var checks := services.sent_of(&"begin_suit_check")
	panel.refresh()
	var running := services.session.suit_check_progress(me.id) >= 0.0
	_check("suit rack: the suit button starts the suit check (begin_suit_check on)", checks.size() == 1 and bool(checks[0].params.on) and running and panel.suit_button.disabled,
		"%s, running %s" % [str(services.sent), running])
	services.session.advance(services.config.suit_check_seconds + 0.1)
	panel.refresh()
	_check("suit rack: after the check the suit is on and the button takes it off", me.suit_on and panel.reading_text(&"suit") == "On"
		and panel.suit_button.text == "Take the suit off" and not panel.suit_button.disabled, "%s %s" % [me.suit_on, panel.suit_button.text])
	me.suit_on = false
	await _close(panel)


# ---------------------------------------------------------------- HUD

func _test_hud() -> void:
	var st := services.state()
	var bal := services.balance
	var hud := GameHud.new()
	root.add_child(hud)
	hud.setup(services)
	await _frames()
	for i in 3:
		hud.show_message("Filler message %d." % i, 30.0)
	services.events.system_alert.emit(&"test_alert", &"warn", "Water pump stopped: no power. Wastewater is building up.")
	var now := hud.current_messages()
	_check("HUD: a system_alert reaches the message line at once, even when it is full", now.has("Water pump stopped: no power. Wastewater is building up.")
		and now.size() == GameHud.MAX_MESSAGES and hud.last_alert_text.begins_with("Water pump stopped"), str(now))
	_set_equipment("scrubber", false)
	var after_action := hud.current_messages()
	_tick()
	var after_tick := hud.current_messages()
	_check("HUD: system alerts from an action and from the next tick show in the message line", "\n".join(after_action).contains("CO₂ scrubber off")
		and "\n".join(after_tick).contains("CO₂ scrubber is switched off"), "%s / %s" % [after_action, after_tick])
	_set_equipment("scrubber", true)

	var saved_co2 := st.cabin_co2_kg
	var saved_o2 := st.cabin_o2_kg
	hud.refresh()
	var calm := hud.shown_readings()
	st.cabin_co2_kg = bal.gas_kg_for_kpa(0.7, GameBalance.MOLAR_CO2)
	hud.refresh()
	var co2_shown := "\n".join(hud.shown_readings())
	st.cabin_co2_kg = saved_co2
	st.cabin_o2_kg = bal.gas_kg_for_kpa(15.0, GameBalance.MOLAR_O2)
	hud.refresh()
	var o2_shown := hud.shown_readings()
	_check("HUD: urgent readings use the cabin air (CO2 high, O2 low) with kPa and a word", "\n".join(calm).find("Cabin") < 0
		and co2_shown.contains("Cabin CO₂ 0.7 kPa") and co2_shown.contains("! High")
		and not o2_shown.is_empty() and o2_shown[0].contains("Cabin oxygen 15 kPa") and o2_shown[0].contains("✖ Too low"), "%s / %s / %s" % [calm, co2_shown, o2_shown])
	st.cabin_o2_kg = saved_o2
	hud.set_target({"kind": "station", "id": &"sf_solar_tracker", "node": null})
	_check("HUD: cue for a sun tracker", hud.cue_text() == "[E] Use sun tracker", hud.cue_text())
	hud.queue_free()
	await _frames()


# ---------------------------------------------------------------- layout

func _test_layouts() -> void:
	var panels: Array[Control] = []
	for id: String in ["pw_panel", "ls_console", "sf_solar_tracker.007", "al_suit_rack"]:
		services.local_character().position = _station_pos(id)
		panels.append(StationPanels.for_station(StringName(id), services))
	var summary := ColonySummaryPanel.new()
	summary.setup(services)
	panels.append(summary)
	var bp := BlueprintPanel.new()
	bp.setup(services)
	panels.append(bp)
	var stretch := root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	for panel in panels:
		root.add_child(panel)
		await _check_layout(panel, (panel as UiPanel).panel_title(), true)
		panel.queue_free()
		await process_frame
	var hud := GameHud.new()
	root.add_child(hud)
	hud.setup(services)
	hud.show_message("A long colony message to check wrapping: the CO₂ scrubber is off and carbon dioxide is building up in the cabin.", 30.0)
	await _check_layout(hud.root_control(), "HUD", false)
	hud.queue_free()
	await process_frame
	root.content_scale_mode = stretch


func _check_layout(ctl: Control, label: String, full_rect: bool) -> void:
	var layout := PackedStringArray()
	var focus := PackedStringArray()
	for s: Array in SIZES:
		root.size = s[0]
		UiTheme.apply_text_scale(float(s[1]))
		if full_rect:
			ctl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await _frames(2)
		if ctl is UiPanel:
			(ctl as UiPanel).refresh()
		await _frames(2)
		for line in UiLayoutCheck.problems(ctl, Vector2(s[0])):
			layout.append("%s text %s: %s" % [s[0], s[1], line])
		var min_size := ctl.get_combined_minimum_size()
		if full_rect and (min_size.x > float(s[0].x) or min_size.y > float(s[0].y)):
			layout.append("%s text %s: minimum size %s is bigger than the screen" % [s[0], s[1], min_size])
		for line in UiLayoutCheck.focus_problems(ctl):
			focus.append("%s text %s: %s" % [s[0], s[1], line])
	UiTheme.apply_text_scale(1.0)
	root.size = Vector2i(1280, 720)
	_check("layout %s at 1280x720, 1920x1080 and 1280x720 text 1.5" % label, layout.is_empty(), "\n  ".join(layout))
	_check("focus %s" % label, focus.is_empty() and (not full_rect or not UiLayoutCheck.focusable(ctl).is_empty()), "\n  ".join(focus))


func _labels(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	for child in node.get_children():
		if child is Label and (child as Label).is_visible_in_tree():
			out.append(child as Label)
		out.append_array(_labels(child))
	return out


func _all_text(node: Node) -> String:
	var parts := PackedStringArray()
	for l in _labels(node):
		parts.append(l.text)
	return "\n".join(parts)
