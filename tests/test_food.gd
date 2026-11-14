extends SceneTree
## Greenhouse food system (Prompt 08, food part). Every PASS below is measured on the running model:
## stations and data, growth with each input alone, harvest once, water drawn only from the delivered greenhouse
## allocation (ledger identities), wilting after an alert, automation upgrades over 10 sols, evidence once and in
## order, lab nutrient settings, save/load mid-growth, and the two panels (content, requests, layout).
## Run: ..\godot.cmd --headless --path . --script res://tests/test_food.gd


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


const MANIFEST := "res://data/colony_manifest.json"
const CONSOLE := &"gh_console"
const BEDS: Array[StringName] = [&"gd_planter", &"gd_planter.001", &"gd_planter.002", &"gd_planter.003", &"gd_planter.004", &"gd_planter.005", &"gd_hydro"]
const BIO := &"crew_3"
const SIZES := [[Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 1.0], [Vector2i(1280, 720), 1.5]]

var _passed := 0
var _total := 0
var _event_nodes: Array[GameEvents] = []
var _zones: ColonyZones
var _catalog: Dictionary
var _catcher := ErrorCatcher.new()


func _initialize() -> void:
	OS.add_logger(_catcher)
	_zones = ColonyZones.from_manifest(MANIFEST)
	_catalog = StationCatalog.from_manifest(MANIFEST, _zones)
	_stations_and_data()
	_actions_basics()
	_growth_inputs()
	_full_cycle_and_harvest()
	_water_only_from_allocation()
	_wilting_after_alert()
	_automation()
	_evidence_order()
	_mixed_change()
	_lab_setting()
	await _save_load()
	await _panels()
	_check("no script or engine errors during the test", _catcher.errors.is_empty(), "\n".join(_catcher.errors))
	OS.remove_logger(_catcher)
	for node: GameEvents in _event_nodes:
		node.free()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


# ------------------------------------------------------------------ helpers

func _check(label: String, condition: bool, detail: String = "state mismatch") -> void:
	_total += 1
	if condition:
		_passed += 1
		print("PASS " + label)
	else:
		print("FAIL " + label + ": " + detail)


## A host session on the real map with `active` crew controlled by peers 1..active, plenty of power.
func _session(active: int = 1) -> SessionService:
	var ev := GameEvents.new()
	_event_nodes.append(ev)
	var s := SessionService.new(GameConfig.new(), GameBalance.new(), ev)
	var st := ColonyState.new_game(s.balance, 777, _zones.names)
	st.stations = _catalog.duplicate(true)
	for c: CharacterState in st.characters.values():
		c.hub_spot = s.config.hub_position
		c.position = c.hub_spot
	var game_clock := SolClock.new()
	game_clock.phase = s.config.start_phase
	s.begin(st, game_clock)
	# crew_3 (biology and food) first, then the others
	var order: Array[StringName] = [&"crew_3", &"crew_1", &"crew_2", &"crew_4"]
	for i in active:
		st.character(order[i]).owner_peer = i + 1
		if i > 0:
			s.peer_joined(i + 1)
	s.balance.battery_discharge_kw_max = 1.0e5
	s.balance.battery_charge_kw_max = 1.0e5
	st.capacities[&"battery_kwh"] = 1.0e7
	st.stores[&"battery_kwh"] = 5.0e6
	return s


func _do(s: SessionService, crew: StringName, action: StringName, station: StringName, params: Dictionary = {}) -> ActionResult:
	var c := s.state.character(crew)
	c.position = CharacterState._v3(s.state.stations[station].position)
	return s.request(action, station, params, c.owner_peer)


## Advances the clock and model by `hours` game hours in ticks of `dt`. `each` is called after every tick.
func _hours(s: SessionService, hours: float, dt: float = 0.1, each: Callable = Callable()) -> void:
	var t := 0.0
	while t < hours - 1e-9:
		var h := minf(dt, hours - t)
		var phase_before := s.clock.phase
		var got := s.clock.advance(h / s.clock.hours_per_real_second())
		for id: StringName in s.sim.step(s.state, s.balance, phase_before, got):
			s.recover_character(id)
		t += h
		if each.is_valid():
			each.call(t)


func _bed(s: SessionService, id: StringName) -> Dictionary:
	return CropSystem.bed(s.state, String(id))


func _snap(st: ColonyState) -> Dictionary:
	return {"stores": st.stores.duplicate(), "o2": st.cabin_o2_kg, "n2": st.cabin_n2_kg, "co2": st.cabin_co2_kg, "ledger": st.ledger.duplicate()}


## Ledger identities of water and food, as "measured change - booked change" (all should be 0).
func _identities(st: ColonyState, start: Dictionary) -> Dictionary:
	var l := {}
	for k: String in st.ledger:
		l[k] = float(st.ledger[k]) - float((start.ledger as Dictionary).get(k, 0.0))
	var d := {}
	for k: StringName in ColonyState.STORE_KEYS:
		d[k] = st.store(k) - float(start.stores[k])
	return {
		"clean water": d[&"water_l"] - (l.water_recycled_l - l.water_used_l - l.greenhouse_water_l - l.electrolysis_water_l - l.recovery_water_l),
		"wastewater": d[&"wastewater_l"] - (l.water_to_wastewater_l + l.greenhouse_water_l - l.recycler_in_l),
		"all water": d[&"water_l"] + d[&"wastewater_l"] + l.water_body_loss_l + l.wastewater_overflow_l + l.brine_l + l.electrolysis_water_l + l.recovery_water_l,
		"food": d[&"food_meals"] - (float(l.get("meals_harvested", 0.0)) - l.meals_eaten - l.recovery_meals),
	}


func _worst(errors: Dictionary) -> float:
	var w := 0.0
	for k: String in errors:
		w = maxf(w, absf(float(errors[k])))
	return w


func _counter(s: SessionService) -> Dictionary:
	var counts := {}
	s.events.system_alert.connect(func(id: StringName, _level: StringName, _text: String) -> void:
		counts[String(id)] = int(counts.get(String(id), 0)) + 1)
	return counts


## Puts a bed into a known growing state (test setup: the host's state, not a player action).
func _setup_bed(s: SessionService, id: StringName, crop: String, progress: float, water_share: float, nutrients: float) -> Dictionary:
	CropSystem.ensure(s.state)
	var b := CropSystem.new_bed()
	b["crop"] = crop
	b["progress"] = progress
	b["stage"] = CropSystem.stage_for(crop, progress)
	b["water_l"] = water_share * FoodBalance.shared().bed_water_capacity_l
	b["nutrients"] = nutrients
	b["planted_at"] = 0.0
	(s.state.crops.beds as Dictionary)[String(id)] = b
	return b


# ------------------------------------------------------------------ stations and data

func _stations_and_data() -> void:
	var beds: Array = []
	var problems := PackedStringArray()
	for id: String in _catalog:
		if String(_catalog[id].kind) == "bed":
			beds.append(id)
			if String(_catalog[id].zone) != ColonyZones.GARDEN or String(_catalog[id].specialty) != "":
				problems.append("%s zone %s specialty '%s'" % [id, _catalog[id].zone, _catalog[id].specialty])
	beds.sort()
	var want: Array = []
	for b in BEDS:
		want.append(String(b))
	want.sort()
	_check("stations: the six garden-dome planters and the hydroponics unit are beds anyone may use", beds == want and problems.is_empty(), "%s %s" % [beds, problems])
	_check("stations: the greenhouse console is the food station in the Greenhouse", String(_catalog[String(CONSOLE)].kind) == "food" and String(_catalog[String(CONSOLE)].zone) == "Greenhouse")
	_check("map: the Greenhouse zone exists (the grow-light circuit)", _zones.names.has("Greenhouse"))
	var lettuce := FoodBalance.crop("lettuce")
	var tomato := FoodBalance.crop("tomato")
	_check("crops: lettuce is ISS analog evidence, tomato is labelled 'plan, not yet grown on the ISS'",
		String(lettuce.get("evidence", "")).contains("ISS analog") and String(tomato.get("evidence_short", "")) == "plan, not yet grown on the ISS"
		and String(tomato.get("evidence", "")).contains("Plan, not yet grown on the ISS") and String(lettuce.get("evidence", "")).contains("not proof"),
		"%s / %s" % [lettuce.get("evidence", ""), tomato.get("evidence", "")])
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/model_sources_food.json"))
	var missing: Array = []
	var fields := 0
	if data is Dictionary:
		for p: Dictionary in FoodBalance.new().get_property_list():
			if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and not String(p.name).begins_with("_"):
				fields += 1
				if not (data as Dictionary).has(String(p.name)):
					missing.append(p.name)
		for crop_id: String in ["lettuce", "tomato"]:
			for key: String in ["cycle_sols", "meals", "water_l_per_hour", "nutrient_use_per_cycle", "evidence"]:
				if not (data as Dictionary).has("crops.%s.%s" % [crop_id, key]):
					missing.append("crops.%s.%s" % [crop_id, key])
		for k: String in data:
			if not ["balance", "physics", "S11", "index"].has(String(data[k].get("category", ""))):
				missing.append(k + " (category)")
	_check("model_sources_food.json: all %d FoodBalance fields and every crop number have a category" % fields, fields >= 15 and missing.is_empty(), str(missing))


func _actions_basics() -> void:
	var s := _session(2)
	var r := _do(s, &"crew_1", &"plant", BEDS[0], {"crop": "lettuce"})
	_check("plant: anyone may plant (an electrical specialist here)", r.ok and String(_bed(s, BEDS[0]).crop) == "lettuce" and String(_bed(s, BEDS[0]).stage) == "seed", str(r.to_dict()))
	r = _do(s, &"crew_1", &"plant", BEDS[0], {"crop": "tomato"})
	_check("plant: refused while something grows", not r.ok and r.reason == &"missing_prerequisite")
	r = _do(s, BIO, &"plant", BEDS[1], {"crop": "cactus"})
	_check("plant: unknown crop refused", not r.ok and r.reason == &"unknown_target")
	r = _do(s, BIO, &"plant", CONSOLE, {"crop": "lettuce"})
	_check("plant: only at a bed", not r.ok and r.reason == &"wrong_target")
	r = _do(s, BIO, &"set_grow_lights", BEDS[1], {"on": true})
	_check("set_grow_lights: only at the greenhouse console", not r.ok and r.reason == &"wrong_target")
	var c := s.state.character(BIO)
	c.position = CharacterState._v3(s.state.stations[String(BEDS[2])].position) + Vector3(10.0, 0.0, 0.0)
	r = s.request(&"plant", BEDS[2], {"crop": "lettuce"}, c.owner_peer)
	_check("plant: too far refused", not r.ok and r.reason == &"too_far")
	r = _do(s, BIO, &"adjust_nutrients", BEDS[1], {"level": 1.5})
	_check("adjust_nutrients: level 0..1 only", not r.ok and r.reason == &"bad_request")
	r = _do(s, BIO, &"adjust_nutrients", BEDS[1], {"level": 0.5})
	_check("adjust_nutrients: refused on an empty bed", not r.ok and r.reason == &"missing_prerequisite")
	r = _do(s, BIO, &"set_greenhouse_water", CONSOLE, {"greenhouse_l_per_hour": 2.5})
	_check("set_greenhouse_water: the console shortcut sets the greenhouse allocation", r.ok and float(s.state.water_allocation.greenhouse_l_per_hour) == 2.5)
	r = _do(s, BIO, &"set_grow_lights", CONSOLE, {"on": false})
	_check("set_grow_lights: switches the Greenhouse lighting circuit (its 9 kW load)", r.ok and not s.state.is_zone_powered("Greenhouse") and String(r.changes.text).contains("kW"))
	_do(s, BIO, &"set_grow_lights", CONSOLE, {"on": true})
	r = _do(s, BIO, &"inspect_bed", BEDS[0])
	_check("inspect_bed: records a measurement (water, nutrients, light, rate)", r.ok and (_bed(s, BEDS[0]).inspection as Dictionary).has("nutrients")
		and (r.changes.measurement as Dictionary).has("water_share") and (r.changes.measurement as Dictionary).has("light"), str(r.changes))
	_check("inspect_bed: a healthy bed records no evidence", not ProgressEvidence.has(s.state, &"food_compare_symptom"))
	_check("invariants after the actions", s.state.invariants_ok().is_empty(), str(s.state.invariants_ok()))


# ------------------------------------------------------------------ growth

func _growth_inputs() -> void:
	var s := _session(1)
	var fb := FoodBalance.shared()
	var base := FoodBalance.base_rate("lettuce")
	s.state.water_allocation["greenhouse_l_per_hour"] = 0.0
	_setup_bed(s, BEDS[0], "lettuce", 0.3, 0.9, 0.7)      # everything good
	_setup_bed(s, BEDS[1], "lettuce", 0.3, 0.3, 0.7)      # low water only
	_setup_bed(s, BEDS[2], "lettuce", 0.3, 0.9, 0.2)      # low nutrients only
	_setup_bed(s, BEDS[3], "lettuce", 0.3, 0.0, 0.7)      # dry
	var p0 := float(_bed(s, BEDS[0]).progress)
	_hours(s, 0.1, 0.1)
	var good := _bed(s, BEDS[0])
	var low_w := _bed(s, BEDS[1])
	var low_n := _bed(s, BEDS[2])
	var dry := _bed(s, BEDS[3])
	_check("growth: all inputs good grows at the full base rate (progress = rate x hours)", absf(float(good.rate) - base) < 1e-12 and absf((float(good.progress) - p0) - base * 0.1) < 1e-12,
		"rate %s base %s" % [good.rate, base])
	var want_w := base * fb.water_factor(0.3)
	_check("growth: low water alone slows growth (soil water 30 %% -> %.0f %% of full speed)" % (100.0 * fb.water_factor(0.3)),
		float(low_w.rate) > 0.0 and float(low_w.rate) < base and absf(float(low_w.rate) - want_w) < 1e-12 and (low_w.symptoms as Array).has("wilting") and (low_w.symptoms as Array).size() == 1, str(low_w))
	var want_n := base * fb.nutrient_factor(0.2)
	_check("growth: low nutrients alone slow growth (nutrients 20 %% -> %.1f %% of full speed)" % (100.0 * fb.nutrient_factor(0.2)),
		float(low_n.rate) > 0.0 and float(low_n.rate) < base and absf(float(low_n.rate) - want_n) < 1e-12 and (low_n.symptoms as Array) == ["yellow_leaves"], str(low_n))
	_check("growth: a completely dry bed stops growing (but has not wilted yet)", float(dry.rate) == 0.0 and String(dry.stage) != "wilted" and float(dry.dry_hours) > 0.0, str(dry))
	# no light alone
	_setup_bed(s, BEDS[0], "lettuce", 0.3, 0.9, 0.7)
	_do(s, BIO, &"set_grow_lights", CONSOLE, {"on": false})
	_hours(s, 3.0, 0.1)
	var dark := _bed(s, BEDS[0])
	_check("growth: no light alone stops growth (3 h with the grow lights off: progress unchanged)", float(dark.rate) == 0.0 and absf(float(dark.progress) - 0.3) < 1e-12
		and (dark.symptoms as Array) == ["leggy_pale"], str(dark))
	_check("growth: the grow lights draw no power while off", not s.state.is_zone_powered("Greenhouse"))
	_do(s, BIO, &"set_grow_lights", CONSOLE, {"on": true})
	_hours(s, 0.2, 0.1)
	_check("growth: light back on, growth restarts", float(_bed(s, BEDS[0]).rate) > 0.0 and float(_bed(s, BEDS[0]).progress) > 0.3)
	# shed lights give no light either
	s.state.shed = ["lights", "greenhouse"]
	_check("growth: grow lights that were shed for lack of power give no light", not CropSystem.lights_working(s.state) and CropSystem.lights_switched_on(s.state))
	s.state.shed = []
	# nutrients fall as plants grow
	var n_before := float(_bed(s, BEDS[0]).nutrients)
	var pr_before := float(_bed(s, BEDS[0]).progress)
	_hours(s, 5.0, 0.1)
	var used := n_before - float(_bed(s, BEDS[0]).nutrients)
	var grown := float(_bed(s, BEDS[0]).progress) - pr_before
	_check("growth: nutrients fall as the plants grow (%.4f used for %.4f growth)" % [used, grown], used > 0.0 and absf(used - 0.6 * grown) < 1e-9)


func _full_cycle_and_harvest() -> void:
	var s := _session(1)
	var start := _snap(s.state)
	_do(s, BIO, &"set_greenhouse_water", CONSOLE, {"greenhouse_l_per_hour": 3.0})
	var r := _do(s, BIO, &"plant", BEDS[0], {"crop": "lettuce"})
	var stages: Array = []
	var ready_at := [-1.0]
	_hours(s, 4.0 * GameConfig.SOL_HOURS, 0.25, func(t: float) -> void:
		var b := _bed(s, BEDS[0])
		if stages.is_empty() or stages[-1] != String(b.stage):
			stages.append(String(b.stage))
		if String(b.stage) == "ready" and ready_at[0] < 0.0:
			ready_at[0] = t
		if float(b.nutrients) < 0.45:
			b["nutrients"] = 0.7)            # test keeps the nutrients up: this check is about the cycle
	_check("cycle: lettuce goes seed -> sprout -> leafy -> ready in about 3 sols with good care (%.2f sols)" % (ready_at[0] / GameConfig.SOL_HOURS),
		r.ok and stages == ["seed", "sprout", "leafy", "ready"] and absf(ready_at[0] / GameConfig.SOL_HOURS - 3.0) < 0.02, "%s at %s h" % [stages, ready_at[0]])
	var b := _bed(s, BEDS[0])
	_check("cycle: a ready crop waits (no more growth, progress 100 %)", float(b.rate) == 0.0 and float(b.progress) == 1.0)
	var r2 := _do(s, BIO, &"harvest", BEDS[1])
	_check("harvest: refused on a bed with nothing ready", not r2.ok and r2.reason == &"missing_prerequisite")
	var food := s.state.store(&"food_meals")
	var c := s.state.character(BIO)
	c.position = CharacterState._v3(s.state.stations[String(BEDS[0])].position)
	var req := ActionRequest.make("harvest-once", c.owner_peer, BIO, &"harvest", BEDS[0])
	var h1 := s.submit(req)
	var after_one := s.state.store(&"food_meals")
	var h2 := s.submit(ActionRequest.make("harvest-once", c.owner_peer, BIO, &"harvest", BEDS[0]))
	var h3 := _do(s, BIO, &"harvest", BEDS[0])
	_check("harvest: adds exactly the crop's meals (5) to food_meals and clears the bed", h1.ok and absf(after_one - food - 5.0) < 1e-9 and String(_bed(s, BEDS[0]).crop) == ""
		and String(_bed(s, BEDS[0]).stage) == "empty" and float(h1.changes.meals) == 5.0, "%s -> %s" % [food, after_one])
	_check("harvest: the repeated request is a duplicate and adds nothing", h2.ok and h2.duplicate and s.state.store(&"food_meals") == after_one)
	_check("harvest: a new request on the cleared bed is refused and adds nothing", not h3.ok and h3.reason == &"missing_prerequisite" and s.state.store(&"food_meals") == after_one)
	_check("harvest: ledger meals_harvested counts it once", float(s.state.ledger.meals_harvested) == 5.0)
	_check("harvest: food ledger identity holds (now = start + harvested - eaten - recovery)", _worst(_identities(s.state, start)) < 1e-6, str(_identities(s.state, start)))
	# a full store takes only what fits
	_setup_bed(s, BEDS[1], "tomato", 1.0, 0.9, 0.7)
	s.state.stores[&"food_meals"] = float(s.state.capacities[&"food_meals"]) - 4.0
	var h4 := _do(s, BIO, &"harvest", BEDS[1])
	_check("harvest: a nearly full store takes only what fits (4 of 12 meals), and the ledger books 4",
		h4.ok and float(h4.changes.meals) == 4.0 and s.state.store(&"food_meals") == float(s.state.capacities[&"food_meals"]) and float(s.state.ledger.meals_harvested) == 9.0)


# ------------------------------------------------------------------ water

func _water_only_from_allocation() -> void:
	var s := _session(2)
	var start := _snap(s.state)
	for id in BEDS:
		_do(s, BIO, &"plant", id, {"crop": "tomato"})
	var w0 := 0.0
	for id in BEDS:
		w0 += float(_bed(s, id).water_l)
	var gained := [false]
	var prev := {}
	for id in BEDS:
		prev[id] = float(_bed(s, id).water_l)
	_hours(s, 6.0, 0.1, func(_t: float) -> void:
		for id in BEDS:
			if float(_bed(s, id).water_l) > float(prev[id]) + 1e-12:
				gained[0] = true
			prev[id] = float(_bed(s, id).water_l))
	var totals: Dictionary = s.state.crops.totals
	_check("water: with no greenhouse allocation no bed gains water (6 h)", not gained[0] and float(totals.absorbed_l) == 0.0 and float(s.state.ledger.greenhouse_water_l) == 0.0)
	_do(s, BIO, &"set_greenhouse_water", CONSOLE, {"greenhouse_l_per_hour": 1.0})
	var ledger0 := float(s.state.ledger.greenhouse_water_l)
	var abs0 := float(totals.absorbed_l)
	var worst_tick := [0.0]
	var over := [false]
	_hours(s, GameConfig.SOL_HOURS, 0.1, func(_t: float) -> void:
		var errs := _identities(s.state, start)
		worst_tick[0] = maxf(worst_tick[0], _worst(errs))
		var t: Dictionary = s.state.crops.totals
		if float(t.absorbed_l) > float(t.delivered_l) + 1e-9 or float(s.state.crops.absorbed_l_per_hour) > float(s.state.crops.delivered_l_per_hour) + 1e-9:
			over[0] = true)
	var delivered := float(s.state.ledger.greenhouse_water_l) - ledger0
	var absorbed := float(totals.absorbed_l) - abs0
	_check("water: beds take only the delivered greenhouse water (%.2f L absorbed of %.2f L delivered in a sol)" % [absorbed, delivered],
		absorbed > 0.0 and absorbed <= delivered + 1e-9 and not over[0] and absf(float(totals.delivered_l) - float(s.state.ledger.greenhouse_water_l)) < 1e-9)
	_check("water: every water and food ledger identity holds on every tick (worst %s)" % String.num_scientific(worst_tick[0]), worst_tick[0] < 1e-6)
	# below the drinking reserve nothing is delivered, so the beds get nothing
	s.state.stores[&"water_l"] = s.balance.water_reserve_l - 1.0
	var abs1 := float(totals.absorbed_l)
	_hours(s, 2.0, 0.1)
	_check("water: below the drinking reserve the greenhouse gets nothing and the beds absorb nothing", float(totals.absorbed_l) == abs1 and float(s.state.crops.delivered_l_per_hour) == 0.0)
	_check("water: invariants hold", s.state.invariants_ok().is_empty(), str(s.state.invariants_ok()))


func _wilting_after_alert() -> void:
	var s := _session(1)
	var counts := _counter(s)
	var first_alert := [-1.0]
	var texts := [""]
	s.events.system_alert.connect(func(id: StringName, _level: StringName, text: String) -> void:
		if String(id) == "bed_dry_" + String(BEDS[4]) and first_alert[0] < 0.0:
			first_alert[0] = s.state.sim_hours
			texts[0] = text)
	_do(s, BIO, &"plant", BEDS[4], {"crop": "lettuce"})
	_do(s, BIO, &"set_bed_water", BEDS[4], {"on": false})
	var wilted_at := [-1.0]
	_hours(s, 3.0 * GameConfig.SOL_HOURS, 0.1, func(_t: float) -> void:
		if wilted_at[0] < 0.0 and String(_bed(s, BEDS[4]).stage) == "wilted":
			wilted_at[0] = s.state.sim_hours)
	_check("wilting: a dry bed is announced first ('will wilt'), and wilts a sol later (alert %.1f h, wilted %.1f h)" % [first_alert[0], wilted_at[0]],
		first_alert[0] >= 0.0 and wilted_at[0] > first_alert[0] and absf((wilted_at[0] - first_alert[0]) - FoodBalance.shared().wilt_after_dry_hours) < 0.2
		and texts[0].contains("wilt") and int(counts.get("bed_dry_" + String(BEDS[4]), 0)) == 1, "%s %s" % [texts[0], counts])
	_check("wilting: a wilted bed says so and must be replanted", int(counts.get("bed_wilted_" + String(BEDS[4]), 0)) == 1 and _do(s, BIO, &"harvest", BEDS[4]).reason == &"missing_prerequisite"
		and _do(s, BIO, &"plant", BEDS[4], {"crop": "tomato"}).ok and String(_bed(s, BEDS[4]).stage) == "seed")
	# water that comes back in time saves the plant
	var s2 := _session(1)
	_do(s2, BIO, &"plant", BEDS[4], {"crop": "lettuce"})
	_do(s2, BIO, &"set_bed_water", BEDS[4], {"on": false})
	_hours(s2, 40.0, 0.2)
	var dry_h := float(_bed(s2, BEDS[4]).dry_hours)
	_do(s2, BIO, &"set_bed_water", BEDS[4], {"on": true})
	_do(s2, BIO, &"set_greenhouse_water", CONSOLE, {"greenhouse_l_per_hour": 2.0})
	_hours(s2, 20.0, 0.2)
	_check("wilting: water back before a full dry sol saves the plant (dry %.1f h, then growing again)" % dry_h,
		dry_h > 5.0 and String(_bed(s2, BEDS[4]).stage) != "wilted" and float(_bed(s2, BEDS[4]).rate) > 0.0 and float(_bed(s2, BEDS[4]).dry_hours) == 0.0)


# ------------------------------------------------------------------ automation

## Runs 10 sols with every bed planted with lettuce and no chore action at all. Ready beds are harvested and
## replanted by action (that is not one of the chores). Returns what was measured.
func _chore_run(upgrades: Array, lights_on: bool, allocation: float) -> Dictionary:
	var s := _session(1)
	for id: String in upgrades:
		s.state.upgrades[id] = {"installed": true}
	for id in BEDS:
		_do(s, BIO, &"plant", id, {"crop": "lettuce"})
	if allocation > 0.0:
		_do(s, BIO, &"set_greenhouse_water", CONSOLE, {"greenhouse_l_per_hour": allocation})
	_do(s, BIO, &"set_grow_lights", CONSOLE, {"on": lights_on})
	var m := {"min_water": INF, "min_nutrients": INF, "dark_growing_hours": 0.0, "dry_ticks": 0, "wilted": 0, "harvests": 0, "late_min_water": INF, "late_min_nutrients": INF}
	var fb := FoodBalance.shared()
	_hours(s, 10.0 * GameConfig.SOL_HOURS, 0.25, func(t: float) -> void:
		var growing := 0
		for id in BEDS:
			var b := _bed(s, id)
			if String(b.stage) == "wilted":
				m["wilted"] = int(m.wilted) + 1
				_do(s, BIO, &"plant", id, {"crop": "lettuce"})
				continue
			if String(b.stage) == "ready":
				if _do(s, BIO, &"harvest", id).ok:
					m["harvests"] = int(m.harvests) + 1
				_do(s, BIO, &"plant", id, {"crop": "lettuce"})
				continue
			growing += 1
			var share := float(b.water_l) / fb.bed_water_capacity_l
			m["min_water"] = minf(float(m.min_water), share)
			m["min_nutrients"] = minf(float(m.min_nutrients), float(b.nutrients))
			if t > 8.0 * GameConfig.SOL_HOURS:
				m["late_min_water"] = minf(float(m.late_min_water), share)
				m["late_min_nutrients"] = minf(float(m.late_min_nutrients), float(b.nutrients))
			if float(b.water_l) <= 0.0:
				m["dry_ticks"] = int(m.dry_ticks) + 1
		if growing > 0 and not CropSystem.lights_working(s.state):
			m["dark_growing_hours"] = float(m.dark_growing_hours) + 0.25)
	m["allocation"] = float(s.state.water_allocation.greenhouse_l_per_hour)
	m["invariants"] = s.state.invariants_ok()
	return m


func _automation() -> void:
	var fb := FoodBalance.shared()
	var none := _chore_run([], true, 3.0)
	_check("automation: without upgrades the chores are real in 10 sols (drip lines clog and beds dry; nutrients drop below the good band)",
		int(none.dry_ticks) > 0 and float(none.min_nutrients) < fb.nutrient_good_low and float(none.dark_growing_hours) == 0.0, str(none))
	var irr := _chore_run(["food_irrigation_reliability"], true, 3.0)
	_check("automation: food_irrigation_reliability: no bed dries for 10 sols with water allocated, also in the last 2 sols (min soil water %d %%)" % roundi(100.0 * float(irr.min_water)),
		int(irr.dry_ticks) == 0 and int(irr.wilted) == 0 and float(irr.min_water) >= fb.water_good and float(irr.late_min_water) >= fb.water_good and int(irr.harvests) > 0, str(irr))
	var met := _chore_run(["food_nutrient_metering"], true, 3.0)
	_check("automation: food_nutrient_metering: nutrients stay in the good band for 10 sols with no action (min %d %%)" % roundi(100.0 * float(met.min_nutrients)),
		float(met.min_nutrients) >= fb.nutrient_good_low and float(met.late_min_nutrients) >= fb.nutrient_good_low and float(met.min_nutrients) <= fb.nutrient_good_high, str(met))
	var sch := _chore_run(["food_scheduled_care"], false, 0.0)
	_check("automation: food_scheduled_care: lights and watering with no player action for 10 sols (starts dark and dry-allocated)",
		int(sch.dry_ticks) == 0 and int(sch.wilted) == 0 and float(sch.dark_growing_hours) <= 0.25 and float(sch.allocation) > 0.0 and float(sch.late_min_water) >= fb.water_low and int(sch.harvests) > 0, str(sch))
	var all := _chore_run(["food_irrigation_reliability", "food_nutrient_metering", "food_scheduled_care"], false, 0.0)
	_check("automation: all three together keep every bed healthy for 10 sols and harvests keep coming (%d harvests)" % int(all.harvests),
		int(all.dry_ticks) == 0 and int(all.wilted) == 0 and float(all.min_nutrients) >= fb.nutrient_good_low and float(all.min_water) >= fb.water_good
		and int(all.harvests) >= 14 and (all.invariants as PackedStringArray).is_empty(), str(all))


# ------------------------------------------------------------------ evidence

func _evidence_order() -> void:
	var s := _session(1)
	_do(s, BIO, &"plant", BEDS[0], {"crop": "lettuce"})
	_do(s, BIO, &"plant", BEDS[1], {"crop": "lettuce"})
	_hours(s, 0.5, 0.1)
	_do(s, BIO, &"adjust_nutrients", BEDS[0], {"level": 0.1})
	_check("evidence: changing an input before any inspection records nothing", s.state.evidence.is_empty(), str(s.state.evidence))
	_hours(s, 0.5, 0.1)
	var r := _do(s, BIO, &"inspect_bed", BEDS[0])
	var e1 := s.state.evidence.duplicate(true)
	_check("evidence: inspecting yellow leaves records food_compare_symptom with the measurement",
		r.ok and e1.has("food_compare_symptom") and e1.size() == 1 and String(r.changes.text).contains("Yellow leaves") and String(r.changes.text).contains("Nutrients 10 %")
		and String((e1.food_compare_symptom as Dictionary).sector) == "food" and String((e1.food_compare_symptom as Dictionary).by) == String(BIO), str(r.changes.text))
	var rate_before := float(_bed(s, BEDS[0]).rate)
	r = _do(s, BIO, &"adjust_nutrients", BEDS[0], {"level": 0.6})
	_check("evidence: exactly one input changed on that bed records food_adjust_one_cause", r.ok and s.state.evidence.has("food_adjust_one_cause") and not s.state.evidence.has("food_observe_response")
		and String(_bed(s, BEDS[0]).trial.status) == "one_change")
	_hours(s, 0.2, 0.1)
	var b := _bed(s, BEDS[0])
	_check("evidence: the bed's growth rate rose afterwards, so food_observe_response is recorded (%.5f -> %.5f per h)" % [rate_before, float(b.rate)],
		s.state.evidence.has("food_observe_response") and float(b.rate) > rate_before and String(b.trial.status) == "improved")
	var order: Array = s.state.evidence.keys()
	var t1 := float(s.state.evidence.food_compare_symptom.at_hours)
	var t2 := float(s.state.evidence.food_adjust_one_cause.at_hours)
	var t3 := float(s.state.evidence.food_observe_response.at_hours)
	_check("evidence: recorded in the right order (compare, adjust one cause, observe response)",
		order == ["food_compare_symptom", "food_adjust_one_cause", "food_observe_response"] and t1 <= t2 and t2 <= t3, "%s %s %s %s" % [order, t1, t2, t3])
	# repeating the whole task on another bed adds nothing
	var before := s.state.evidence.duplicate(true)
	var events_seen := [0]
	s.events.upgrade_eligibility_changed.connect(func(_id: StringName) -> void: events_seen[0] += 1)
	(s.state.crops.beds[String(BEDS[1])] as Dictionary)["nutrients"] = 0.1
	_hours(s, 0.2, 0.1)
	_do(s, BIO, &"inspect_bed", BEDS[1])
	_do(s, BIO, &"adjust_nutrients", BEDS[1], {"level": 0.6})
	_hours(s, 0.3, 0.1)
	_check("evidence: repeating the task on another bed adds nothing (each id once, same times, no new event)",
		s.state.evidence == before and events_seen[0] == 0 and String(_bed(s, BEDS[1]).trial.status) == "improved")


func _mixed_change() -> void:
	var s := _session(1)
	_setup_bed(s, BEDS[2], "lettuce", 0.3, 0.1, 0.1)    # dry and hungry
	_hours(s, 0.1, 0.1)
	_do(s, BIO, &"inspect_bed", BEDS[2])
	_do(s, BIO, &"adjust_nutrients", BEDS[2], {"level": 0.6})
	var r := _do(s, BIO, &"set_greenhouse_water", CONSOLE, {"greenhouse_l_per_hour": 4.0})
	_hours(s, 2.0, 0.1)
	_check("evidence: two inputs changed on one bed makes the test 'mixed': no response is recorded although growth rose",
		r.ok and String(_bed(s, BEDS[2]).trial.status) == "mixed" and s.state.evidence.has("food_adjust_one_cause") and not s.state.evidence.has("food_observe_response")
		and float(_bed(s, BEDS[2]).rate) > 0.0, str(_bed(s, BEDS[2]).trial))
	# the wrong single change gives no response within a sol
	var s2 := _session(1)
	_setup_bed(s2, BEDS[3], "lettuce", 0.3, 0.9, 0.1)   # hungry only
	_hours(s2, 0.1, 0.1)
	_do(s2, BIO, &"inspect_bed", BEDS[3])
	_do(s2, BIO, &"set_bed_water", BEDS[3], {"on": false})
	_hours(s2, GameConfig.SOL_HOURS + 1.0, 0.25)
	_check("evidence: changing the wrong input gives no response, and the test ends as 'no change' after a sol",
		String(_bed(s2, BEDS[3]).trial.get("status", "")) == "no_change" and not s2.state.evidence.has("food_observe_response"), str(_bed(s2, BEDS[3]).trial))


func _lab_setting() -> void:
	var s := _session(1)
	_do(s, BIO, &"plant", BEDS[0], {"crop": "lettuce"})
	_do(s, BIO, &"plant", BEDS[1], {"crop": "tomato"})
	s.state.science["results"] = {"lab_1": {"kind": "nutrient_setting", "value": 0.55}, "rock_2": {"kind": "rock_type", "value": "basalt"}}
	var r := _do(s, BIO, &"apply_nutrient_result", CONSOLE, {"result_id": "lab_1"})
	_check("lab setting: refused without the sci_evidence_settings upgrade", not r.ok and r.reason == &"missing_prerequisite")
	s.state.upgrades["sci_evidence_settings"] = {"installed": true}
	r = _do(s, BIO, &"apply_nutrient_result", CONSOLE, {"result_id": "rock_2"})
	_check("lab setting: a result that is not a nutrient setting is refused", not r.ok and r.reason == &"unknown_target")
	r = _do(s, BIO, &"apply_nutrient_result", CONSOLE, {"result_id": "lab_1"})
	_check("lab setting: applies the lab value to every growing bed and records sci_apply_result",
		r.ok and float(_bed(s, BEDS[0]).nutrients) == 0.55 and float(_bed(s, BEDS[1]).nutrients) == 0.55 and String(_bed(s, BEDS[2]).crop) == ""
		and s.state.evidence.has("sci_apply_result") and String(s.state.evidence.sci_apply_result.sector) == "science")
	var r2 := _do(s, BIO, &"apply_nutrient_result", CONSOLE, {"result_id": "lab_1"})
	_check("lab setting: the same result applies once only", not r2.ok and r2.reason == &"missing_prerequisite" and (s.state.crops.applied_results as Array).count("lab_1") == 1)


# ------------------------------------------------------------------ save and load

func _save_load() -> void:
	var services := GameServices.new()
	services.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/food"), "colony", 2)
	root.add_child(services)
	services.start_new_game(1, BIO)
	await process_frame
	services.set_process(false)
	var s := services.session
	var tick := 1.0 / services.config.sim_tick_hz
	_do(s, BIO, &"set_greenhouse_water", CONSOLE, {"greenhouse_l_per_hour": 2.0})
	_do(s, BIO, &"plant", BEDS[0], {"crop": "lettuce"})
	_do(s, BIO, &"plant", BEDS[6], {"crop": "tomato"})
	for i in 600:
		s.advance(tick)
	(s.state.crops.beds[String(BEDS[0])] as Dictionary)["nutrients"] = 0.2
	s.advance(tick)
	_do(s, BIO, &"inspect_bed", BEDS[0])
	# what the file holds is the state written once and parsed once (SaveService does the same)
	var saved_crops: Variant = JSON.parse_string(JSON.stringify(s.state.crops, "", true, true))
	var err := services.save_now(&"manual")
	for i in 300:
		s.advance(tick)
	var after_a: Dictionary = s.state.crops.duplicate(true)
	var food_a := s.state.store(&"food_meals")
	var load := services.continue_game()
	var loaded_crops: Dictionary = services.session.state.crops.duplicate(true)
	s = services.session
	for i in 300:
		s.advance(tick)
	var after_b: Dictionary = s.state.crops.duplicate(true)
	var mid := float(CropSystem.bed(s.state, String(BEDS[0])).progress)
	_check("save/load: mid-growth crops come back exactly as written to the file (beds, trial, totals)", err == OK and load.is_usable() and _same(loaded_crops, saved_crops, 0.0)
		and String(CropSystem.bed(services.state(), String(BEDS[0])).trial.status) == "open", _diff(loaded_crops, saved_crops, 0.0))
	_check("save/load: growth after loading matches growth without the save, every number within 1e-9 (%.4f progress)" % mid,
		_same(after_a, after_b, 1e-9) and absf(s.state.store(&"food_meals") - food_a) < 1e-9 and mid > 0.0 and mid < 1.0, _diff(after_a, after_b, 1e-9))
	services.queue_free()
	await process_frame


# ------------------------------------------------------------------ panels

func _frames(n := 2) -> void:
	for i in n:
		await process_frame


func _panels() -> void:
	PlayerInput.ensure_actions()
	var services := RecordingServices.new()
	services.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/food_panels"), "colony", 2)
	root.add_child(services)
	services.start_new_game(1, BIO)
	await _frames()
	services.set_process(false)
	var tick := 1.0 / services.config.sim_tick_hz
	services.session.advance(tick)
	var st := services.state()
	var me := services.local_character()
	var mapping_ok := true
	for id in BEDS:
		var p := _make_panel(id, services)
		mapping_ok = mapping_ok and p is BedStationPanel and p.panel_title() == CropSystem.bed_name(st, String(id))
		p.free()
	var cp := _make_panel(CONSOLE, services)
	mapping_ok = mapping_ok and cp is FoodStationPanel
	cp.free()
	_check("panels: the hook scripts res://scripts/ui/stations/bed_ and food_station_panel.gd build the bed panel (titled by bed) and the console panel", mapping_ok)

	# ---- bed panel
	me.position = CharacterState._v3(st.stations[String(BEDS[2])].position)
	var bed := _make_panel(BEDS[2], services) as BedStationPanel
	root.add_child(bed)
	bed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames()
	bed.refresh()
	services.sent.clear()
	(bed.buttons["plant_tomato"] as Button).pressed.emit()
	var sent := services.sent_of(&"plant")
	_check("bed panel: 'Plant tomato' asks the host to plant a tomato here", sent.size() == 1 and String(sent[0].params.crop) == "tomato" and sent[0].target == BEDS[2]
		and String(CropSystem.bed(st, String(BEDS[2])).crop) == "tomato")
	bed.refresh()
	var notes := bed.notes_text()
	_check("bed panel: says tomato is a plan, not yet grown on the ISS, and that time is squeezed ('about 6 sols here', months on Earth)",
		notes.contains("Plan, not yet grown on the ISS") and notes.contains("about 6 sols here") and notes.contains("months on Earth"), notes)
	_check("bed panel: crop, stage, growth, time to harvest and the three inputs with units", bed.reading_text(&"crop") == "Tomato" and bed.reading_text(&"stage") == "Seed"
		and bed.reading_text(&"progress").ends_with("%") and bed.reading_text(&"water").contains(" L") and bed.reading_text(&"nutrients") == "70 %"
		and bed.reading_text(&"light").begins_with("On") and bed.reading_text(&"rate").ends_with("per sol") and (bed.reading_text(&"harvest_in") == "Stopped" or bed.reading_text(&"harvest_in").begins_with("about")),
		"%s | %s | %s | %s | %s | %s" % [bed.reading_text(&"crop"), bed.reading_text(&"stage"), bed.reading_text(&"water"), bed.reading_text(&"nutrients"), bed.reading_text(&"light"), bed.reading_text(&"harvest_in")])
	(st.crops.beds[String(BEDS[2])] as Dictionary)["nutrients"] = 0.2
	services.session.advance(tick)
	bed.refresh()
	var lines := bed.symptom_texts()
	_check("bed panel: a symptom is shown in words with its cause and the measurement that proves it",
		lines.size() == 1 and lines[0].contains("Yellow leaves") and lines[0].contains("too few nutrients") and lines[0].contains("Nutrients 20 %"), str(lines))
	services.sent.clear()
	(bed.buttons["inspect"] as Button).pressed.emit()
	bed.nutrient_slider.value = 0.65
	(bed.buttons["set_nutrients"] as Button).pressed.emit()
	_check("bed panel: Inspect and Set nutrients ask the host (inspect_bed, adjust_nutrients 0.65)", services.sent_of(&"inspect_bed").size() == 1
		and services.sent_of(&"adjust_nutrients").size() == 1 and absf(float(services.sent_of(&"adjust_nutrients")[0].params.level) - 0.65) < 1e-9
		and absf(float(CropSystem.bed(st, String(BEDS[2])).nutrients) - 0.65) < 1e-9 and bed.diagnosis_text().contains("only the nutrients"), bed.diagnosis_text())
	services.sent.clear()
	bed.water_switch.button_pressed = false
	_check("bed panel: the water switch asks set_bed_water and shows the real state", services.sent_of(&"set_bed_water").size() == 1 and not bool(CropSystem.bed(st, String(BEDS[2])).valve) and not bed.water_switch.button_pressed)
	_check("bed panel: Harvest is disabled until the crop is ready; the specialist symbol is on the panel", (bed.buttons["harvest"] as Button).disabled and _all_text(bed).contains("❀ Biology and food specialists"))

	# ---- console
	me.position = CharacterState._v3(st.stations[String(CONSOLE)].position)
	var con := _make_panel(CONSOLE, services) as FoodStationPanel
	root.add_child(con)
	con.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames()
	con.refresh()
	var beds_shown := con.bed_lines()
	_check("console: lists all 7 beds, with the tomato's stage", beds_shown.size() == 7 and "\n".join(beds_shown).contains("Tomato, seed"), "\n".join(beds_shown))
	_check("console: food store and meals per sol for the crew; stored meals cover the start",
		con.reading_text(&"food").contains("meals") and con.reading_text(&"food_use") == "3 meals per sol" and con.start_note_text().contains("Stored meals cover the start"), con.reading_text(&"food_use"))
	_check("console: a '?' explains why light, water and nutrients matter", _has_explain(con, "food") and _all_text(con).contains("Why light, water and nutrients matter") and _all_text(con).contains("weeks to months on Earth"))
	services.sent.clear()
	con.lights_switch.button_pressed = false
	_check("console: the grow-light switch asks set_grow_lights and the lights go off", services.sent_of(&"set_grow_lights").size() == 1 and not st.is_zone_powered("Greenhouse") and not con.lights_switch.button_pressed)
	con.lights_switch.button_pressed = true
	services.sent.clear()
	con.water_slider.value = 2.5
	con.water_button.pressed.emit()
	_check("console: the water shortcut asks set_greenhouse_water", services.sent_of(&"set_greenhouse_water").size() == 1 and float(st.water_allocation.greenhouse_l_per_hour) == 2.5)
	st.science["results"] = {"lab_7": {"kind": "nutrient_setting", "value": 0.5}}
	con.refresh()
	var apply := con.result_buttons.get("lab_7") as Button
	_check("console: a lab nutrient setting is shown but locked without the upgrade", apply != null and apply.disabled)
	st.upgrades["sci_evidence_settings"] = {"installed": true}
	st.upgrades["food_scheduled_care"] = {"installed": true}
	con.refresh()
	apply.pressed.emit()
	con.refresh()
	_check("console: with the upgrade the lab setting applies once and shows as applied; automation shows what is installed",
		apply.disabled and apply.text.begins_with("✓") and float(CropSystem.bed(st, String(BEDS[2])).nutrients) == 0.5 and "\n".join(con.automation_lines()).contains("✓ Scheduled care"))
	bed.queue_free()
	con.queue_free()
	await _frames()

	# ---- layout
	var stretch := root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	(st.crops.beds[String(BEDS[2])] as Dictionary)["water_l"] = 0.0
	(st.crops.beds[String(BEDS[2])] as Dictionary)["nutrients"] = 0.1
	_do(services.session, BIO, &"set_grow_lights", CONSOLE, {"on": false})
	_do(services.session, BIO, &"inspect_bed", BEDS[2])
	services.session.advance(tick)
	for id: StringName in [BEDS[2], BEDS[6], CONSOLE]:
		me.position = CharacterState._v3(st.stations[String(id)].position)
		var p := _make_panel(id, services)
		root.add_child(p)
		await _check_layout(p, "%s (%s)" % [(p as UiPanel).panel_title(), id])
		p.queue_free()
		await process_frame
	root.content_scale_mode = stretch
	services.queue_free()
	await process_frame


func _check_layout(ctl: Control, label: String) -> void:
	var layout := PackedStringArray()
	var focus := PackedStringArray()
	for s: Array in SIZES:
		root.size = s[0]
		UiTheme.apply_text_scale(float(s[1]))
		ctl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await _frames(2)
		(ctl as UiPanel).refresh()
		await _frames(2)
		for line in UiLayoutCheck.problems(ctl, Vector2(s[0])):
			layout.append("%s text %s: %s" % [s[0], s[1], line])
		var min_size := ctl.get_combined_minimum_size()
		if min_size.x > float(s[0].x) or min_size.y > float(s[0].y):
			layout.append("%s text %s: minimum size %s is bigger than the screen" % [s[0], s[1], min_size])
		for line in UiLayoutCheck.focus_problems(ctl):
			focus.append("%s text %s: %s" % [s[0], s[1], line])
	UiTheme.apply_text_scale(1.0)
	root.size = Vector2i(1280, 720)
	_check("layout %s at 1280x720, 1920x1080 and 1280x720 text 1.5" % label, layout.is_empty(), "\n  ".join(layout))
	_check("focus %s: every control reachable by keyboard with a visible focus" % label, focus.is_empty() and not UiLayoutCheck.focusable(ctl).is_empty(), "\n  ".join(focus))


func _all_text(node: Node) -> String:
	var parts := PackedStringArray()
	for l in node.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree():
			parts.append((l as Label).text)
	return "\n".join(parts)


func _has_explain(node: Node, id: String) -> bool:
	for b in node.find_children("*", "ExplainButton", true, false):
		if (b as ExplainButton).explanation_id == id:
			return true
	return false


## The panel the StationPanels hook is meant to build: res://scripts/ui/stations/<kind>_station_panel.gd, set up the
## way StationPanels.for_station() sets up panels. (for_station itself currently replaces any custom panel with a plain
## StationPanel: `match kind if panel == null else ""` falls through to its `_` branch. Reported for the merge.)
func _make_panel(id: StringName, services: GameServices) -> StationPanel:
	var kind := String(services.state().stations[String(id)].kind)
	var path := "res://scripts/ui/stations/%s_station_panel.gd" % kind
	if not ResourceLoader.exists(path):
		return null
	var panel := (load(path) as Script).new() as StationPanel
	panel.station_id = id
	panel.kind = kind
	panel.set_meta(&"station_surface", true)
	panel.set_meta(&"station_id", id)
	panel.setup(services)
	return panel


func _same(a: Variant, b: Variant, tol: float) -> bool:
	return _diff(a, b, tol) == ""


## The first difference between two JSON-like values ("" if none); numbers may differ by `tol` (relative, at least 1).
func _diff(a: Variant, b: Variant, tol: float, path := "") -> String:
	var na := typeof(a) == TYPE_FLOAT or typeof(a) == TYPE_INT
	var nb := typeof(b) == TYPE_FLOAT or typeof(b) == TYPE_INT
	if na and nb:
		var x := float(a)
		var y := float(b)
		return "" if absf(x - y) <= tol * maxf(1.0, maxf(absf(x), absf(y))) else "%s: %s vs %s" % [path, x, y]
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return "%s: %d vs %d keys" % [path, da.size(), db.size()]
		for k: Variant in da:
			if not db.has(k):
				return "%s/%s missing" % [path, k]
			var d := _diff(da[k], db[k], tol, "%s/%s" % [path, k])
			if d != "":
				return d
		return ""
	if a is Array and b is Array:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return "%s: %d vs %d items" % [path, aa.size(), ab.size()]
		for i in aa.size():
			var d := _diff(aa[i], ab[i], tol, "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	return "" if typeof(a) == typeof(b) and a == b else "%s: %s vs %s" % [path, a, b]
