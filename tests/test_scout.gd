extends SceneTree
## Scout update: the scout rover (finished by the field engineer, sent out, surveying, reporting, coming home), the ore
## deposits (found by the scout or on foot, collected, worked at the workbench), the broken-down rover as a salvage
## donor, the energy upgrades built at a sun tracker, the goals, saving and loading, and the mission-control HUD and
## its drawers (built, refreshed and laid out at 1280x720, 1920x1080 and 1280x720 with large text). Synthetic: every
## check runs headless on the real game services; no player has tried it.
## Run: godot --headless --path . --script res://tests/test_scout.gd


class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR or error_type == ERROR_TYPE_SCRIPT:
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


const SIZES := [[Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 1.0], [Vector2i(1280, 720), 1.5]]
const ORES: Array[String] = ["ore_hematite_a", "ore_hematite_b", "ore_olivine_a", "ore_gypsum_a", "ore_carbonate_a"]
const BENCH := &"hg_control_board"
const FIELD := &"crew_4"

var _passed := 0
var _total := 0
var _catcher := ErrorCatcher.new()
var services: GameServices
var _alerts: Array[String] = []


func _initialize() -> void:
	OS.add_logger(_catcher)
	PlayerInput.ensure_actions()
	services = GameServices.new()
	services.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/scout"), "colony", 2)
	root.add_child(services)
	services.start_new_game(1)
	await _frames()
	services.set_process(false)
	services.events.system_alert.connect(func(id: StringName, _l: StringName, _t: String) -> void: _alerts.append(String(id)))

	_test_stations()
	_test_assemble()
	_test_trip()
	_test_ore()
	_test_salvage_donor()
	_test_energy_at_tracker()
	_test_goals()
	await _test_save_load()
	await _test_hud()
	await _test_panels()

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


func st() -> ColonyState:
	return services.state()


func me() -> CharacterState:
	return services.local_character()


func _at(id: String) -> void:
	me().position = CharacterState._v3(st().stations[id].position)


func _become(id: StringName) -> void:
	if me() != null and me().id == id:
		return
	me().position = me().hub_spot
	services.session.request(&"claim_character", id)


func _req(action: StringName, target: StringName, params := {}) -> ActionResult:
	return services.session.request(action, target, params)


func _run_hours(hours: float) -> void:
	var target := st().sim_hours + hours
	var guard := 0
	while st().sim_hours < target and guard < 40000:
		services.session.advance(1.0 / services.config.sim_tick_hz)
		guard += 1


# ---------------------------------------------------------------- tests

func _test_stations() -> void:
	var ok := st().stations.has("scout_bay") and String(st().stations.scout_bay.kind) == "scout_bay" and st().stations.has("broken_rover")
	for id in ORES:
		ok = ok and st().stations.has(id) and String(st().stations[id].kind) == "ore_deposit"
	_check("stations: scout bay, broken-down rover and five ore deposits come from data/stations_scout.json", ok, str(st().stations.keys()))
	var h := load("res://data/terrain_height.res") as TerrainHeight
	var flat := true
	var detail := PackedStringArray()
	for id: String in ["scout_bay", "broken_rover"] + ORES:
		var p := CharacterState._v3(st().stations[id].position)
		var ground := h.height_at(p.x, p.z)
		var slope := absf(h.height_at(p.x + 1.0, p.z) - ground) + absf(h.height_at(p.x, p.z + 1.0) - ground)
		if absf(ground - p.y) > 0.6 or slope > 0.5:
			flat = false
			detail.append("%s ground %.2f slope %.2f" % [id, ground, slope])
		if String(services.zones.zone_at_world(p)) != ColonyZones.EXTERIOR:
			flat = false
			detail.append("%s not outside" % id)
	_check("stations: every new station is outside on walkable ground near its data height", flat, ", ".join(detail))
	_check("new game: the scout starts half built at its bay", ScoutSystem.status(st()) in ["kit", ""] and not ScoutSystem.is_built(st()), str(st().scout))
	_check("data: five survey sites, four ore kinds with a use and a source id", ScoutSystem.sites().size() == 5 and ScoutSystem.ore_kinds().size() == 4
		and String(ScoutSystem.ore_info("hematite").use) == "parts" and not (ScoutSystem.ore_info("gypsum").source_ids as Array).is_empty())


func _test_assemble() -> void:
	_become(&"crew_1")
	_at("scout_bay")
	var r := _req(&"scout_assemble", &"scout_bay")
	_check("assemble: only the field engineering and geology specialist may finish the scout", not r.ok, String(r.reason))
	_become(FIELD)
	_at("scout_bay")
	var parts := st().parts
	st().parts = 1
	r = _req(&"scout_assemble", &"scout_bay")
	_check("assemble: refused without enough parts, with the reason in words", not r.ok and r.message.contains("parts"), r.message)
	st().parts = parts
	me().position = CharacterState._v3(st().stations.scout_bay.position) + Vector3(30, 0, 0)
	r = _req(&"scout_assemble", &"scout_bay")
	_check("assemble: refused from far away", not r.ok, String(r.reason))
	_at("scout_bay")
	r = _req(&"scout_send", &"scout_bay", {"site": "east_plain"})
	_check("send: refused while the scout is a kit", not r.ok and r.message.contains("not finished"), r.message)
	r = _req(&"scout_assemble", &"scout_bay")
	_check("assemble: the field engineer finishes it for %d parts (ledger parts_used_scout)" % ScoutSystem.ASSEMBLE_PARTS,
		r.ok and ScoutSystem.is_built(st()) and st().parts == parts - ScoutSystem.ASSEMBLE_PARTS
		and is_equal_approx(float(st().ledger.get("parts_used_scout", 0.0)), float(ScoutSystem.ASSEMBLE_PARTS)) and ScoutSystem.status(st()) == "docked",
		"%s %s %d" % [r.message, st().scout, st().parts])
	r = _req(&"scout_assemble", &"scout_bay")
	_check("assemble: once only", not r.ok and st().parts == parts - ScoutSystem.ASSEMBLE_PARTS)
	_check("colony invariants hold after assembling", st().invariants_ok().is_empty(), str(st().invariants_ok()))


func _test_trip() -> void:
	_become(&"crew_2")
	_at("scout_bay")
	var r := _req(&"scout_send", &"scout_bay", {"site": "nowhere"})
	_check("send: an unknown place is refused", not r.ok)
	r = _req(&"scout_send", &"scout_bay", {"site": "east_plain"})
	_check("send: anyone can send it; it drives off with an arrival time in words", r.ok and ScoutSystem.status(st()) == "driving"
		and String(r.changes.get("text", "")).contains("east plain"), r.message + str(r.changes))
	r = _req(&"scout_send", &"scout_bay", {"site": "crash_field"})
	_check("send: refused while it is already on a trip", not r.ok)
	var start := ScoutSystem.position(st())
	_run_hours(0.2)
	var moved := ScoutSystem.position(st()).distance_to(start)
	_check("trip: it moves at about %d m per game hour" % roundi(ScoutSystem.SPEED_M_PER_HOUR), absf(moved - ScoutSystem.SPEED_M_PER_HOUR * 0.2) < 8.0, "moved %.1f m" % moved)
	_alerts.clear()
	_run_hours(ScoutSystem.hours_to(st(), "east_plain") + 0.1)
	_check("trip: it arrives and looks around the site", ScoutSystem.status(st()) == "surveying", ScoutSystem.status(st()))
	_run_hours(ScoutSystem.SURVEY_HOURS + 0.05)
	var rep: Dictionary = st().scout.get("last_report", {})
	var revealed: Array = rep.get("revealed", [])
	_check("report: after looking around it radios a report home (alert and discovery) and heads back",
		ScoutSystem.is_surveyed(st(), "east_plain") and _alerts.has(String(ScoutSystem.ALERT_ID)) and ScoutSystem.status(st()) == "returning"
		and st().discoveries.any(func(d: Variant) -> bool: return d is Dictionary and String(d.get("kind", "")) == "scout_survey"), "%s %s" % [_alerts, ScoutSystem.status(st())])
	_check("report: the ore deposits near the site are marked on the map, the others are not", revealed.has("ore_hematite_a") and revealed.has("ore_hematite_b")
		and ScoutSystem.is_revealed(st(), "ore_hematite_a") and not ScoutSystem.is_revealed(st(), "ore_gypsum_a"), str(revealed))
	_run_hours(ScoutSystem.hours_to(st(), "east_plain") + 0.5)
	_check("trip: it comes home and parks at its bay", ScoutSystem.status(st()) == "docked" and ScoutSystem.position(st()).distance_to(ScoutSystem.dock_position()) < 0.5,
		"%s %s" % [ScoutSystem.status(st()), ScoutSystem.position(st())])
	r = _req(&"scout_send", &"scout_bay", {"site": "west_dunes"})
	_run_hours(0.1)
	var r2 := _req(&"scout_recall", &"scout_bay")
	_check("recall: it turns round on the way", r.ok and r2.ok and ScoutSystem.status(st()) == "returning", r2.message)
	_run_hours(2.0)
	_check("recall: and parks again without a report", ScoutSystem.status(st()) == "docked" and not ScoutSystem.is_surveyed(st(), "west_dunes"))
	if st().stations.has("cm_colony_computer"):
		_at("cm_colony_computer")
		r = _req(&"scout_send", &"cm_colony_computer", {"site": "south_slope"})
		_check("send: the colony computer can send it too", r.ok, r.message)
		_run_hours(ScoutSystem.hours_to(st(), "south_slope") + ScoutSystem.SURVEY_HOURS + 0.2)
		_run_hours(ScoutSystem.hours_to(st(), "south_slope") + 0.5)


func _test_ore() -> void:
	_become(&"crew_3")
	_at("ore_hematite_a")
	var r := _req(&"collect_ore", &"ore_hematite_a")
	_check("ore: anyone collects a piece; it goes into the colony store", r.ok and ScoutSystem.ore_count(st(), "hematite") == 1 and ScoutSystem.ore_left(st(), "ore_hematite_a") == ScoutSystem.ORE_PER_DEPOSIT - 1, r.message)
	_req(&"collect_ore", &"ore_hematite_a")
	_req(&"collect_ore", &"ore_hematite_a")
	r = _req(&"collect_ore", &"ore_hematite_a")
	_check("ore: a deposit gives %d pieces, then says it is empty" % ScoutSystem.ORE_PER_DEPOSIT, not r.ok and ScoutSystem.ore_count(st(), "hematite") == ScoutSystem.ORE_PER_DEPOSIT, r.message)
	_at("ore_olivine_a")
	r = _req(&"collect_ore", &"ore_olivine_a")
	_check("ore: walking to a deposit the scout never saw finds it and marks it", r.ok and ScoutSystem.is_revealed(st(), "ore_olivine_a"))
	_at(String(BENCH))
	var parts := st().parts
	r = _req(&"process_ore", BENCH, {"kind": "hematite"})
	_check("workbench: %d hematite become one spare part (ledger parts_from_ore)" % ScoutSystem.HEMATITE_PER_PART, r.ok and st().parts == parts + 1
		and ScoutSystem.ore_count(st(), "hematite") == ScoutSystem.ORE_PER_DEPOSIT - ScoutSystem.HEMATITE_PER_PART and is_equal_approx(float(st().ledger.parts_from_ore), 1.0), r.message)
	r = _req(&"process_ore", BENCH, {"kind": "hematite"})
	_check("workbench: one hematite left is not enough for a part", not r.ok and st().parts == parts + 1, r.message)
	r = _req(&"process_ore", BENCH, {"kind": "olivine"})
	_check("workbench: a science ore studied raises the science score by one", r.ok and ScoutSystem.science_points(st()) == 1 and ScoutSystem.ore_count(st(), "olivine") == 0, r.message)
	r = _req(&"process_ore", BENCH, {"kind": "gold"})
	_check("workbench: an unknown ore is refused", not r.ok)
	_check("colony invariants hold after ore work", st().invariants_ok().is_empty(), str(st().invariants_ok()))


func _test_salvage_donor() -> void:
	_become(&"crew_2")
	_at("broken_rover")
	var r := _req(&"inspect_donor", &"broken_rover", {"choice": "rover_toolkit"})
	_check("broken-down rover: it is a salvage donor; the tool kit fits", r.ok and ScienceActions.donor_info("broken_rover").get("name", "") == "Broken-down rover", r.message)
	_become(FIELD)
	_at("broken_rover")
	r = _req(&"recover_part", &"broken_rover", {"part": "rover_toolkit"})
	_check("broken-down rover: the field engineer takes the tool kit out", r.ok, r.message)


func _test_energy_at_tracker() -> void:
	var c := ProgressionSystem.card(&"energy_solar_tracking")
	var tracker := ""
	for id: String in st().stations:
		if String(st().stations[id].kind) == "solar":
			tracker = id
			break
	_check("build: the energy cards can be installed at a sun tracker as well as at the power panel", c != null and c.also_install_kinds.has("solar")
		and ProgressionSystem.at_install_station(st(), c, StringName(tracker)) and ProgressionSystem.at_install_station(st(), c, &"pw_panel")
		and not ProgressionSystem.at_install_station(st(), c, BENCH))
	_check("build: the card says where it can be built", ProgressionSystem.install_place_words(c).contains("sun tracker"), ProgressionSystem.install_place_words(c))


func _test_goals() -> void:
	var goals := ColonyGoals.all(st())
	var by := {}
	for g in goals:
		by[String(g.id)] = g
	_check("goals: checked from the colony (scout finished, 2 places surveyed, ore collected)", bool(by.scout_built.done) and int(by.scout_survey.fraction * 3.0 + 0.01) >= 2
		and float(by.collect_ore.fraction) >= 1.0, str(goals))
	_check("goals: at most %d shown, unfinished first" % ColonyGoals.MAX_SHOWN, ColonyGoals.shown(st()).size() <= ColonyGoals.MAX_SHOWN and not bool(ColonyGoals.shown(st())[0].done))
	st().campaign["objectives"] = [{"text": "Tutorial step", "done": false}]
	_check("goals: objectives published by the campaign come first", String(ColonyGoals.all(st())[0].text) == "Tutorial step")
	st().campaign.erase("objectives")


func _test_save_load() -> void:
	# JSON turns whole numbers into floats (3 -> 3.0) on every save and on every client: compare the parsed forms
	var before := JSON.stringify(JSON.parse_string(JSON.stringify(st().scout)))
	var copy := ColonyState.from_dict(JSON.parse_string(JSON.stringify(st().to_dict())))
	_check("save: the scout, its surveys and the ores survive a JSON round trip", JSON.stringify(copy.scout) == before
		and ScoutSystem.science_points(copy) == ScoutSystem.science_points(st()) and ScoutSystem.ore_left(copy, "ore_hematite_a") == 0, JSON.stringify(copy.scout))
	var old := st().to_dict()
	old.erase("scout")
	var older := ColonyState.from_dict(old)
	ScoutSystem.ensure(older)
	_check("save: an older save without the scout gets a half-built scout", not ScoutSystem.is_built(older) and ScoutSystem.status(older) == "kit")
	await _frames(1)


func _test_hud() -> void:
	var holder := CanvasLayer.new()
	root.add_child(holder)
	var bar := VitalsBar.new()
	holder.add_child(bar)
	bar.setup(services)
	bar.refresh()
	var full := bar.get_combined_minimum_size().x
	bar.set_compact(true)
	await _frames(1)
	var small := bar.get_combined_minimum_size().x
	var trend := bar.find_child("Trend", true, false) as Label
	_check("vitals: ⋯ folds the bar down to the numbers and opens it again", small < full * 0.8 and not trend.visible, "%d -> %d" % [full, small])
	bar.set_compact(false)
	_check("vitals: four supplies with amounts and a trend in words", bar.find_children("Value", "Label", true, false).size() >= 7
		and ["rising", "steady", "sols", " h", "kW", "falling"].any(func(w: String) -> bool: return trend.text.contains(w)), trend.text)
	var goals := GoalsCard.new()
	holder.add_child(goals)
	goals.setup(services)
	var shown := (goals.find_child("List", true, false) as Control).get_child_count()
	goals.toggle()
	_check("goals card: lists goals and folds to its header", shown >= 4 and not (goals.find_child("List", true, false) as Control).visible, str(shown))
	var map := MiniMap.new()
	holder.add_child(map)
	map.setup(services)
	map.refresh()
	var toasts := ToastStack.new()
	holder.add_child(toasts)
	for i in 6:
		toasts.push("Note %d" % i, &"info")
	toasts.push("Note 5", &"info")
	_check("pop-ups: at most %d at once, no repeats" % ToastStack.MAX, toasts.texts().size() == ToastStack.MAX and toasts.texts()[ToastStack.MAX - 1] == "Note 5", str(toasts.texts()))
	toasts._process(20.0)
	_check("pop-ups: they go away by themselves", toasts.texts().is_empty())
	var mc := MissionControlCard.new()
	holder.add_child(mc)
	st().weather["phase"] = "warned"
	st().weather["warning"] = {"starts_at_hours": st().sim_hours + 6.0, "severity": 0.5}
	var advice := StormOutlook.warning_advice(st())
	mc.say("Dust storm coming", advice, &"warn")
	mc.say("Second", "Another message", &"info")
	_check("mission control: a storm warning says when, what it does and what to do", mc.visible and mc.current_text().contains("6 h") and advice.contains("battery")
		and advice.contains("not a forecast"), advice)
	mc.dismiss()
	_check("mission control: messages wait their turn", mc.current_text() == "Another message")
	_check("storm chip: words for a warned storm", StormOutlook.now(st()).text == "Dust storm in 6 h", str(StormOutlook.now(st())))
	st().weather["phase"] = "calm"
	st().weather.erase("warning")
	holder.queue_free()
	await _frames(1)


func _test_panels() -> void:
	var stretch := root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_become(FIELD)
	_at("scout_bay")
	var bay := StationPanels.for_station(&"scout_bay", services) as ScoutBayStationPanel
	root.add_child(bay)
	bay.refresh()
	_check("scout bay panel: a Send button for every place, the status in words", bay.send_buttons.size() == ScoutSystem.sites().size()
		and bay.find_child("ScoutStatus", true, false) != null, str(bay.send_buttons.keys()))
	(bay.send_buttons["far_crater"] as Button).pressed.emit()
	bay.refresh()
	_check("scout bay panel: Send asks the host and the scout drives off", ScoutSystem.status(st()) == "driving" and String(st().scout.target) == "far_crater")
	await _check_layout(bay, "scout bay")
	bay.queue_free()
	_at("ore_gypsum_a")
	var ore := StationPanels.for_station(&"ore_gypsum_a", services) as OreDepositStationPanel
	root.add_child(ore)
	ore.refresh()
	ore.collect_button.pressed.emit()
	ore.refresh()
	_check("ore panel: Collect puts a piece in the store", ScoutSystem.ore_count(st(), "gypsum") == 1)
	await _check_layout(ore, "ore deposit")
	ore.queue_free()
	_at(String(BENCH))
	var bench := StationPanels.for_station(BENCH, services) as WorkbenchStationPanel
	root.add_child(bench)
	bench.refresh()
	_check("workbench panel: a button for the ore in store", bench.ore_buttons.has("gypsum"), str(bench.ore_buttons.keys()))
	bench.queue_free()
	var power := PowerLifePanel.new()
	power.setup(services)
	root.add_child(power)
	power.refresh()
	_check("power drawer: making, using, battery and a verdict in words", (power.find_child("Text", true, false) as Label).text.length() > 10)
	await _check_layout(power, "power and life support")
	power.queue_free()
	var science := VitalsSciencePanel.new()
	science.setup(services)
	root.add_child(science)
	_check("science panel: one card per idea with its sources button", science.find_children("*", "ExplainButton", true, false).size() >= 10)
	await _check_layout(science, "science behind the numbers")
	science.queue_free()
	var build := SolarBuildPanel.new()
	build.setup(services)
	build.tracker_id = &"sf_solar_tracker"
	root.add_child(build)
	build.refresh()
	_check("build drawer: one card per energy upgrade with a Build button", build.build_buttons.size() == 3, str(build.build_buttons.keys()))
	await _check_layout(build, "build at the solar field")
	build.queue_free()
	root.content_scale_mode = stretch
	await _frames(1)


func _check_layout(ctl: Control, label: String) -> void:
	var layout := PackedStringArray()
	for size: Array in SIZES:
		root.size = size[0]
		UiTheme.apply_text_scale(float(size[1]))
		ctl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await _frames(2)
		(ctl as UiPanel).refresh()
		await _frames(2)
		for line in UiLayoutCheck.problems(ctl, Vector2(size[0])):
			layout.append("%s text %s: %s" % [size[0], size[1], line])
		var min_size := ctl.get_combined_minimum_size()
		if min_size.x > float(size[0].x) or min_size.y > float(size[0].y):
			layout.append("%s text %s: minimum size %s is bigger than the screen" % [size[0], size[1], min_size])
	UiTheme.apply_text_scale(1.0)
	root.size = Vector2i(1280, 720)
	_check("layout %s at 1280x720, 1920x1080 and 1280x720 text 1.5" % label, layout.is_empty(), "\n  ".join(layout))
