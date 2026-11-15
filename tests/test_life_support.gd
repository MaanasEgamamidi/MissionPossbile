extends SceneTree
## Energy and life-support model (Prompt 07). Every PASS below is measured on the running model:
## conservation, capacities, zero input, overload shedding, panels and cleaner, trackers, recycler, both oxygen
## paths, water quality, CO2, airlock and pressure, suits, active crew, recovery, toggling, save/load, arrival,
## the reserve forecast and the independence from the real length of a sol.

const MANIFEST := "res://data/colony_manifest.json"
const LS := &"ls_console"
const POWER := &"pw_panel"
const RACK := &"al_suit_rack"

var _passed := 0
var _total := 0
var _event_nodes: Array[GameEvents] = []
var _zones: ColonyZones
var _catalog: Dictionary


func _initialize() -> void:
	_zones = ColonyZones.from_manifest(MANIFEST)
	_catalog = StationCatalog.from_manifest(MANIFEST, _zones)
	_catalog_and_actions()
	_sources()
	_conservation()
	_capacities()
	_zero_input()
	_overload()
	_solar_cleaning()
	_trackers()
	_recycler()
	_oxygen_paths()
	_co2_unit_never_uses_water()
	_water_quality()
	_scrubber()
	_airlock()
	_suits()
	_active_count()
	_recovery_with_empty_stores()
	_toggling()
	_save_load()
	_arrival()
	_forecast()
	_sol_length()
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


## A host session on the real map with `active` crew controlled by peers 1..active, at the new-game time of day.
func _session(active: int = 4) -> SessionService:
	var ev := GameEvents.new()
	_event_nodes.append(ev)
	var s := SessionService.new(GameConfig.new(), GameBalance.new(), ev)
	# _hours deliberately exercises the standalone game-hour model directly, bypassing
	# Session.advance. Retain that model's legacy gas-health compatibility here;
	# test_survival verifies production's replacement real-time atmospheric rule.
	s.sim.exposure_managed = false
	var st := ColonyState.new_game(s.balance, 4242, _zones.names)
	st.stations = _catalog.duplicate(true)
	for c: CharacterState in st.characters.values():
		c.hub_spot = s.config.hub_position
		c.position = c.hub_spot
	var game_clock := SolClock.new()
	game_clock.phase = s.config.start_phase
	s.begin(st, game_clock)
	for i in active:
		st.character(StringName("crew_%d" % (i + 1))).owner_peer = i + 1
		if i > 0:
			s.peer_joined(i + 1)
	s.outside_test = func(p: Vector3) -> bool: return p.x > 500.0
	return s


## Plenty of power: a very large full battery that can give any power. For tests that are not about energy.
func _plenty_of_power(s: SessionService) -> void:
	s.balance.battery_discharge_kw_max = 1.0e5
	s.balance.battery_charge_kw_max = 1.0e5
	s.state.capacities[&"battery_kwh"] = 1.0e7
	s.state.stores[&"battery_kwh"] = 5.0e6


func _at(s: SessionService, crew: StringName, station: StringName) -> void:
	s.state.character(crew).position = CharacterState._v3(s.state.stations[station].position)


func _peer(s: SessionService, crew: StringName) -> int:
	return s.state.character(crew).owner_peer


func _do(s: SessionService, crew: StringName, action: StringName, station: StringName, params: Dictionary = {}) -> ActionResult:
	_at(s, crew, station)
	return s.request(action, station, params, _peer(s, crew))


## Advances the session's clock and model by `hours` game hours in ticks of `dt` (bigger than the real tick, same
## model). Recovers characters that reach zero health. `each` is called after every tick with the hours done.
func _hours(s: SessionService, hours: float, dt: float = 0.05, each: Callable = Callable()) -> void:
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


## Runs until the clock is exactly at `target` phase (it may stop a little short of a full tick).
func _until_phase(s: SessionService, target: float, dt: float = 0.05) -> void:
	var left := fposmod(target - s.clock.phase, 1.0) * GameConfig.SOL_HOURS
	_hours(s, left, dt)


func _counter(s: SessionService) -> Dictionary:
	var counts := {}
	s.events.system_alert.connect(func(id: StringName, _level: StringName, _text: String) -> void:
		counts[String(id)] = int(counts.get(String(id), 0)) + 1)
	return counts


func _alert(st: ColonyState, id: String) -> Dictionary:
	for a: Dictionary in st.alerts:
		if String(a.id) == id:
			return a
	return {}


func _snap(st: ColonyState, b: GameBalance) -> Dictionary:
	var suits := 0.0
	for c: CharacterState in st.characters.values():
		suits += LifeSupportModel.suit_kg(b, c)
	return {"stores": st.stores.duplicate(), "o2": st.cabin_o2_kg, "n2": st.cabin_n2_kg, "co2": st.cabin_co2_kg, "suits": suits, "ledger": st.ledger.duplicate()}


## Every ledger identity of the model, as "measured change - booked change" (all should be 0).
func _identities(st: ColonyState, b: GameBalance, start: Dictionary) -> Dictionary:
	var now := _snap(st, b)
	var l := {}
	for k: String in now.ledger:
		l[k] = float(now.ledger[k]) - float((start.ledger as Dictionary).get(k, 0.0))
	var d := {}
	for k: StringName in ColonyState.STORE_KEYS:
		d[k] = float(now.stores[k]) - float(start.stores[k])
	return {
		"battery": d[&"battery_kwh"] - (l.battery_in_kwh - l.battery_loss_kwh - l.battery_out_kwh - float(l.get("rover_charge_kwh", 0.0))),
		"solar": l.solar_offered_kwh - l.solar_used_kwh - l.solar_curtailed_kwh,
		"load served": l.load_served_kwh - (l.solar_used_kwh - l.battery_in_kwh + l.battery_out_kwh),
		"clean water": d[&"water_l"] - (l.water_recycled_l - l.water_used_l - l.greenhouse_water_l - l.electrolysis_water_l - l.recovery_water_l),
		"wastewater": d[&"wastewater_l"] - (l.water_to_wastewater_l + l.greenhouse_water_l - l.recycler_in_l),
		"all water": d[&"water_l"] + d[&"wastewater_l"] + l.water_body_loss_l + l.wastewater_overflow_l + l.brine_l + l.electrolysis_water_l + l.recovery_water_l,
		"oxygen reserve": d[&"oxygen_kg"] - (l.electrolysis_o2_kg + l.co2_unit_o2_kg - l.regulator_o2_kg - l.suit_refill_kg),
		"cabin O2": (float(now.o2) - float(start.o2)) - (l.regulator_o2_kg - l.cabin_o2_breathed_kg - l.airlock_o2_lost_kg),
		"cabin N2": (float(now.n2) - float(start.n2)) - (l.regulator_n2_kg - l.airlock_n2_lost_kg),
		"cabin CO2": (float(now.co2) - float(start.co2)) - (l.co2_exhaled_kg - l.co2_scrubbed_kg - l.airlock_co2_lost_kg),
		"N2 reserve": d[&"n2_reserve_kg"] + l.regulator_n2_kg,
		"suit tanks": (float(now.suits) - float(start.suits)) - (l.suit_refill_kg - l.suit_o2_used_kg),
		"food": d[&"food_meals"] + l.meals_eaten + l.recovery_meals,
	}


func _sci(x: float) -> String:
	return String.num_scientific(x)


func _worst(errors: Dictionary) -> float:
	var w := 0.0
	for k: String in errors:
		w = maxf(w, absf(float(errors[k])))
	return w


func _ledger_delta(st: ColonyState, start: Dictionary, key: String) -> float:
	return float(st.ledger[key]) - float((start.ledger as Dictionary)[key])


# ------------------------------------------------------------------ tests

func _catalog_and_actions() -> void:
	var trackers := {}
	for id: String in _catalog:
		var station: Dictionary = _catalog[id]
		if station.kind == "solar":
			trackers[int(station.tracker)] = id
			if station.zone != "Exterior" or not id.begins_with("sf_solar_tracker"):
				trackers[-1] = id
	_check("catalog: 12 sun trackers as solar stations in the Exterior, indices 0..11", trackers.size() == 12 and not trackers.has(-1) and trackers[0] == "sf_solar_tracker" and trackers[11] == "sf_solar_tracker.011", str(trackers))
	var s := _session(2)
	var r := _do(s, &"crew_1", &"set_equipment", LS, {"equipment": "warp_drive", "on": true})
	_check("set_equipment: unknown equipment is unknown_target", not r.ok and r.reason == &"unknown_target", String(r.reason))
	r = _do(s, &"crew_1", &"set_equipment", RACK, {"equipment": "scrubber", "on": true})
	_check("set_equipment: only at life support or power", not r.ok and r.reason == &"wrong_target", String(r.reason))
	r = _do(s, &"crew_1", &"set_equipment", POWER, {"equipment": "electrolyser", "on": true})
	_check("set_equipment: switches and says what it does", r.ok and s.state.is_on("electrolyser") and String(r.changes.text).contains("oxygen"), str(r.changes))
	r = _do(s, &"crew_1", &"set_water_allocation", LS, {"greenhouse_l_per_hour": 25.0, "electrolysis_feed_l_per_hour": 1.0})
	_check("set_water_allocation: 0..20 L per hour", not r.ok and r.reason == &"bad_request", String(r.reason))
	r = _do(s, &"crew_1", &"set_water_allocation", LS, {"greenhouse_l_per_hour": 2.0, "electrolysis_feed_l_per_hour": 0.5})
	_check("set_water_allocation: sets both", r.ok and float(s.state.water_allocation.greenhouse_l_per_hour) == 2.0 and float(s.state.water_allocation.electrolysis_feed_l_per_hour) == 0.5)
	r = _do(s, &"crew_1", &"clean_panel", LS)
	_check("clean_panel: only at a tracker", not r.ok and r.reason == &"wrong_target", String(r.reason))


func _sources() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/model_sources.json"))
	var missing: Array = []
	var fields := 0
	var categories := ["physics", "S08", "fiction scaled from S09", "S01", "S02", "balance", "index"]
	if data is Dictionary:
		for p: Dictionary in GameBalance.new().get_property_list():
			if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				fields += 1
				if not (data as Dictionary).has(String(p.name)):
					missing.append(p.name)
		for k: String in data:
			if not categories.has(String(data[k].get("category", ""))):
				missing.append(k + " (category)")
	_check("model_sources.json: all %d GameBalance fields have an evidence category" % fields, data is Dictionary and fields > 50 and missing.is_empty(), str(missing))


func _conservation() -> void:
	var s := _session(4)
	var st := s.state
	var b := s.balance
	var start := _snap(st, b)
	var invariants_ok := [true]
	var last_hour := [-1]
	var actions_ok := [true]
	var worst_tick := [0.0]
	_at(s, &"crew_2", LS)
	_at(s, &"crew_3", RACK)
	var each := func(t: float) -> void:
		if not st.invariants_ok().is_empty():
			invariants_ok[0] = false
		worst_tick[0] = maxf(float(worst_tick[0]), _worst(_identities(st, b, start)))
		var h := int(floorf(t))
		if h == int(last_hour[0]):
			return
		last_hour[0] = h
		if h % 2 == 0:
			var id: String = ColonyState.EQUIPMENT_IDS[(h / 2) % ColonyState.EQUIPMENT_IDS.size()]
			actions_ok[0] = bool(actions_ok[0]) and s.request(&"set_equipment", LS, {"equipment": id, "on": not st.is_on(id)}, 2).ok
		if h % 5 == 0:
			actions_ok[0] = bool(actions_ok[0]) and s.request(&"set_water_allocation", LS, {"greenhouse_l_per_hour": float(h % 3), "electrolysis_feed_l_per_hour": 0.1 * float(h % 7)}, 2).ok
		if h % 7 == 0:
			s.note_airlock_cycle()
			s.note_airlock_cycle()
		if h % 3 == 0:
			st.zones["Greenhouse"].powered = not st.is_zone_powered("Greenhouse")
		var crew_4 := st.character(&"crew_4")
		if h == 10 or h == 40:
			crew_4.suit_on = h == 10
			s.report_position(4, &"crew_4", Vector3(1000, 0, 0), 0.0)
		if h == 16 or h == 45:
			s.report_position(4, &"crew_4", s.config.hub_position, 0.0)
		if h == 16:
			actions_ok[0] = bool(actions_ok[0]) and _do(s, &"crew_4", &"refill_suit", RACK).ok
		if h == 30:
			actions_ok[0] = bool(actions_ok[0]) and _do(s, &"crew_1", &"clean_panel", &"sf_solar_tracker.004").ok
		if h == 31:
			actions_ok[0] = bool(actions_ok[0]) and _do(s, &"crew_1", &"repair_cleaner", &"sf_solar_tracker.004").ok
		if h == 60:
			st.dust_tau = 1.5
		if h == 80:
			st.dust_tau = s.balance.dust_tau_default
	_hours(s, 5.0 * GameConfig.SOL_HOURS, 0.05, each)
	var errors := _identities(st, b, start)
	_check("conservation over 5 sols with switching: every ledger identity within 1e-6 (worst %s, worst on any tick %s)" % [_sci(_worst(errors)), _sci(float(worst_tick[0]))],
		_worst(errors) < 1e-6 and float(worst_tick[0]) < 1e-6 and bool(actions_ok[0]), str(errors))
	_check("conservation run: invariants (no negative or over-capacity store, no NaN) on every tick", bool(invariants_ok[0]))
	_check("conservation run: things really flowed (airlock, suits, electrolysis, recycling, greenhouse)", float(st.ledger.airlock_cycles) > 10.0 and float(st.ledger.suit_o2_used_kg) > 0.0 and float(st.ledger.electrolysis_o2_kg) > 0.0 and float(st.ledger.water_recycled_l) > 0.0 and float(st.ledger.greenhouse_water_l) > 0.0, str(st.ledger))


func _capacities() -> void:
	# battery: full battery in strong sun -> stays at capacity, the surplus is curtailed
	var s := _session(1)
	var st := s.state
	_until_phase(s, 0.45)
	st.stores[&"battery_kwh"] = float(st.capacities[&"battery_kwh"]) - 1.0
	var start := _snap(st, s.balance)
	_hours(s, 2.0)
	_check("capacity: battery never above capacity, the rest of the sun is curtailed", st.store(&"battery_kwh") <= float(st.capacities[&"battery_kwh"]) + 1e-9 and _ledger_delta(st, start, "solar_curtailed_kwh") > 1.0)
	# oxygen reserve full: both processes idle, the electrolyser takes no water
	s = _session(1)
	st = s.state
	_plenty_of_power(s)
	st.water_allocation.electrolysis_feed_l_per_hour = 1.0
	st.equipment.electrolyser.on = true
	st.equipment.co2_unit.on = true
	st.stores[&"oxygen_kg"] = float(st.capacities[&"oxygen_kg"])
	st.cabin_o2_kg = s.balance.gas_kg_for_kpa(s.balance.o2_setpoint_kpa, GameBalance.MOLAR_O2) + 50.0     # regulator idle
	start = _snap(st, s.balance)
	_hours(s, 1.0)
	_check("capacity: full oxygen tanks stop both processes, no water used", st.store(&"oxygen_kg") <= float(st.capacities[&"oxygen_kg"]) + 1e-9 and _ledger_delta(st, start, "oxygen_made_kg") == 0.0 and _ledger_delta(st, start, "electrolysis_water_l") == 0.0 and st.oxygen_process.electrolyser == "tanks_full")
	# clean water full: the recycler only cleans what fits; wastewater full: the overflow is ledgered
	s = _session(4)
	st = s.state
	_plenty_of_power(s)
	st.stores[&"water_l"] = float(st.capacities[&"water_l"])
	st.stores[&"wastewater_l"] = float(st.capacities[&"wastewater_l"])
	start = _snap(st, s.balance)
	_hours(s, 3.0)
	_check("capacity: water and wastewater stay within capacity; overflow ledgered", st.store(&"water_l") <= float(st.capacities[&"water_l"]) + 1e-9 and st.store(&"wastewater_l") <= float(st.capacities[&"wastewater_l"]) + 1e-9 and _ledger_delta(st, start, "wastewater_overflow_l") >= 0.0 and _worst(_identities(st, s.balance, start)) < 1e-6)


func _zero_input() -> void:
	var s := _session(4)
	var st := s.state
	_until_phase(s, 0.8)
	var start := _snap(st, s.balance)
	_hours(s, 3.0)
	var used := _ledger_delta(st, start, "load_served_kwh")
	_check("zero input: no sun at night, the battery alone carries the load", _ledger_delta(st, start, "solar_offered_kwh") == 0.0 and used > 0.0 and absf((float(start.stores[&"battery_kwh"]) - st.store(&"battery_kwh")) - used) < 1e-9 and _ledger_delta(st, start, "battery_in_kwh") == 0.0)
	s = _session(4)
	st = s.state
	_plenty_of_power(s)
	st.stores[&"water_l"] = 0.0
	st.stores[&"wastewater_l"] = 0.0
	st.equipment.recycler.on = false
	st.equipment.electrolyser.on = true
	st.water_allocation.electrolysis_feed_l_per_hour = 5.0
	start = _snap(st, s.balance)
	_hours(s, 2.0)
	_check("zero input: no water, the electrolyser makes nothing", _ledger_delta(st, start, "electrolysis_o2_kg") == 0.0 and st.store(&"water_l") == 0.0 and st.oxygen_process.electrolyser == "no_feed", str(st.oxygen_process))


func _overload() -> void:
	var s := _session(4)
	var st := s.state
	var b := s.balance
	for id in ColonyState.EQUIPMENT_IDS:
		st.equipment[id].on = true
		st.equipment[id].condition = 1.0
	st.water_allocation.electrolysis_feed_l_per_hour = 1.0
	var dt := 0.05
	var plan := LifeSupportModel.plan_processes(st, b, dt)
	var groups := PowerModel.demand_groups(st, b, plan.kw)
	var ids: Array = []
	var total := 0.0
	for g: Dictionary in groups:
		ids.append(g.id)
		total += float(g.kw)
	var order: Array = []
	for id: String in PowerModel.SHED_ORDER:
		order.append(id)
	_check("overload: all ten load groups switched on, in priority order", ids == order, str(ids))
	var order_ok := true
	var text_ok := true
	var unserved_ok := true
	var detail := ""
	var cum := 0.0
	for k in range(1, groups.size() + 1):
		cum += float(groups[k - 1].kw)
		var copy := ColonyState.from_dict(st.to_dict())
		var tight := b.duplicate() as GameBalance
		tight.battery_discharge_kw_max = total - cum + 0.01          # just enough after shedding exactly k groups
		var sim := ColonySim.new()
		var before := float(copy.ledger.load_unserved_kwh)
		sim.step(copy, tight, 0.8, dt)
		var expected: Array = order.slice(0, k)
		if copy.shed != expected:
			order_ok = false
			detail += " k=%d shed=%s" % [k, copy.shed]
		for id: String in expected:
			var a := _alert(copy, "shed_" + id)
			if a.is_empty() or a.text != PowerModel.SHED_TEXT[id] or not String(a.text).contains("no power"):
				text_ok = false
			if id in ColonyState.EQUIPMENT_IDS and copy.is_powered(id):
				text_ok = false
		if absf((float(copy.ledger.load_unserved_kwh) - before) - cum * dt) > 1e-9:
			unserved_ok = false
	_check("overload: loads shed exactly in the listed order (lights, greenhouse, CO2 unit, electrolyser, recycler, trackers, cleaner, scrubber, fans, base)", order_ok, detail)
	_check("overload: an alert names each shed load and says why; shed equipment is 'on but unpowered'", text_ok)
	_check("overload: unserved energy = shed kW x hours, in the ledger", unserved_ok)
	var copy := ColonyState.from_dict(st.to_dict())
	var tight := b.duplicate() as GameBalance
	tight.battery_discharge_kw_max = total - float(groups[0].kw) - float(groups[1].kw) - float(groups[2].kw) - float(groups[3].kw) - float(groups[4].kw) + 0.01
	var sim := ColonySim.new()
	sim.set_events(s.events)
	var counts := _counter(s)
	var phase := 0.8
	for i in 3:
		sim.step(copy, tight, phase, dt)
		phase += dt / GameConfig.SOL_HOURS
	_check("overload: 'Water pump stopped: no power. Wastewater is building up.' announced once over three ticks", int(counts.get("shed_recycler", 0)) == 1 and String(_alert(copy, "shed_recycler").get("text", "")) == "Water pump stopped: no power. Wastewater is building up.", str(counts))
	# losing power has an effect: trackers shed -> panels fixed -> less sun
	copy = ColonyState.from_dict(st.to_dict())
	for i in ColonyState.TRACKER_COUNT:
		copy.panel_dust[i] = 0.9
	copy.stores[&"battery_kwh"] = 0.0
	var mid := 0.3 + 0.5 * dt / GameConfig.SOL_HOURS
	var fixed_kw := PowerModel.solar_kw(copy, b, mid, false)
	var tracking_kw := PowerModel.solar_kw(copy, b, mid, true)
	sim = ColonySim.new()
	sim.step(copy, b, 0.3, dt)
	_check("overload: shed trackers stop following the sun, output falls to the fixed-panel value", copy.shed.has("trackers") and absf(copy.solar_kw - fixed_kw) < 1e-9 and copy.solar_kw < tracking_kw - 0.1, "%s %.3f" % [copy.shed, copy.solar_kw])


func _solar_cleaning() -> void:
	var s := _session(4)
	var st := s.state
	var b := s.balance
	var tracker := &"sf_solar_tracker.003"
	var index := int(st.stations[tracker].tracker)
	var before := PowerModel.solar_kw(st, b, 0.5, true)
	var dust_sum := 0.0
	for d: Variant in st.panel_dust:
		dust_sum += 1.0 - float(d)
	var expected := float(st.panel_dust[index]) / dust_sum
	var r := _do(s, &"crew_2", &"clean_panel", tracker)
	var after := PowerModel.solar_kw(st, b, 0.5, true)
	_check("cleaning: anyone cleans a tracker; output rises by dust/sum(1-dust) = %.4f" % expected, r.ok and float(st.panel_dust[index]) == 0.0 and absf((after - before) / before - expected) < 1e-9, "%.6f vs %.6f" % [(after - before) / before, expected])
	r = _do(s, &"crew_2", &"repair_cleaner", tracker)
	_check("cleaner repair: needs the electrical specialist", not r.ok and r.reason == &"wrong_specialty", String(r.reason))
	var dust_before := float(st.panel_dust[0])
	_hours(s, GameConfig.SOL_HOURS)
	_check("cleaner failed: dust keeps settling through sunrise", float(st.panel_dust[0]) > dust_before and _alert(st, "cleaner_failed").size() > 0)
	r = _do(s, &"crew_1", &"repair_cleaner", tracker)
	_check("cleaner repair: electrical specialist repairs it", r.ok and st.condition_of("cleaner") == 1.0, String(r.reason))
	r = _do(s, &"crew_1", &"repair_cleaner", tracker)
	_check("cleaner repair: refused when not failed", not r.ok and r.reason == &"missing_prerequisite", String(r.reason))
	var cleaned_at_sunrise := [0]
	var max_dust_after := [0.0]
	var each := func(_t: float) -> void:
		var p := s.clock.phase
		if p >= 0.25 and p < 0.25 + 0.05 / GameConfig.SOL_HOURS + 1e-9:
			if PowerModel.average_dust(st) == 0.0:
				cleaned_at_sunrise[0] = int(cleaned_at_sunrise[0]) + 1
		if int(cleaned_at_sunrise[0]) > 0:
			max_dust_after[0] = maxf(float(max_dust_after[0]), PowerModel.average_dust(st))
	_hours(s, 2.0 * GameConfig.SOL_HOURS, 0.05, each)
	_check("cleaner: wipes every panel at each sunrise and keeps them clean (max dust %.4f)" % float(max_dust_after[0]), int(cleaned_at_sunrise[0]) == 2 and float(max_dust_after[0]) <= b.dust_deposit_per_sol + 1e-9, str(cleaned_at_sunrise))


func _trackers() -> void:
	var s := _session(4)
	var st := s.state
	var b := s.balance
	var p := 0.4
	var ratio := PowerModel.solar_kw(st, b, p, false) / PowerModel.solar_kw(st, b, p, true)
	var expected := sqrt(sin(PI * (p - 0.25) / 0.5))
	_check("trackers: fixed / tracking output = sqrt(sun half-sine) = %.4f" % expected, absf(ratio - expected) < 1e-12, "%.6f" % ratio)
	_until_phase(s, p)
	var on_state := ColonyState.from_dict(st.to_dict())
	var r := _do(s, &"crew_1", &"set_equipment", POWER, {"equipment": "trackers", "on": false})
	var sim := ColonySim.new()
	var dt := 0.05
	sim.step(on_state, b, s.clock.phase, dt)
	sim.step(st, b, s.clock.phase, dt)
	var mid := s.clock.phase + 0.5 * dt / GameConfig.SOL_HOURS
	var expected_tick := sqrt(sin(PI * (mid - 0.25) / 0.5))
	_check("trackers: switching their power off lowers the output by the expected ratio", r.ok and absf(st.solar_kw / on_state.solar_kw - expected_tick) < 1e-9 and on_state.load_kw - st.load_kw > b.tracker_drive_kw - 1e-9, "%.6f vs %.6f" % [st.solar_kw / on_state.solar_kw, expected_tick])
	var arc_tracking := 0.0
	var arc_fixed := 0.0
	for i in 1000:
		var ph := 0.25 + 0.5 * (float(i) + 0.5) / 1000.0
		arc_tracking += PowerModel.sun_term(ph, true)
		arc_fixed += PowerModel.sun_term(ph, false)
	_check("trackers: over a sol, tracking collects about 20 %% more sunlight (%.3f x)" % (arc_tracking / arc_fixed), arc_tracking / arc_fixed > 1.18 and arc_tracking / arc_fixed < 1.22)


func _recycler() -> void:
	var s := _session(4)
	var st := s.state
	_plenty_of_power(s)
	var counts := _counter(s)
	var start := _snap(st, s.balance)
	_hours(s, 6.0)
	_check("recycler on: wastewater does not build up", st.store(&"wastewater_l") <= float(start.stores[&"wastewater_l"]) and _ledger_delta(st, start, "water_recycled_l") > 0.0)
	var r := _do(s, &"crew_2", &"set_equipment", LS, {"equipment": "recycler", "on": false})
	start = _snap(st, s.balance)
	_hours(s, 6.0)
	var expected := 4.0 * s.balance.water_l_per_hour * s.balance.water_to_wastewater * 6.0
	_check("recycler off: wastewater builds up by exactly the returned water (%.2f L), alert once" % expected,
		r.ok and absf((st.store(&"wastewater_l") - float(start.stores[&"wastewater_l"])) - expected) < 1e-9 and _ledger_delta(st, start, "water_recycled_l") == 0.0 and int(counts.get("recycler_off", 0)) == 1, str(counts))
	s = _session(4)
	st = s.state
	counts = _counter(s)
	_until_phase(s, 0.8)
	st.stores[&"battery_kwh"] = 0.0
	start = _snap(st, s.balance)
	_hours(s, 3.0)
	_check("recycler unpowered: wastewater builds up, 'Water pump stopped: no power' announced once", st.store(&"wastewater_l") > float(start.stores[&"wastewater_l"]) + 1.0 and int(counts.get("shed_recycler", 0)) == 1 and not st.is_powered("recycler") and st.is_on("recycler"), str(counts))


func _oxygen_paths() -> void:
	var hours := 10.0
	for combo: Array in [[false, false], [true, false], [false, true], [true, true]]:
		var s := _session(4)
		var st := s.state
		var b := s.balance
		_plenty_of_power(s)
		st.water_allocation.electrolysis_feed_l_per_hour = 0.5
		_do(s, &"crew_2", &"set_equipment", LS, {"equipment": "electrolyser", "on": combo[0]})
		_do(s, &"crew_2", &"set_equipment", LS, {"equipment": "co2_unit", "on": combo[1]})
		var start := _snap(st, b)
		_hours(s, hours)
		var e := _ledger_delta(st, start, "electrolysis_o2_kg")
		var c := _ledger_delta(st, start, "co2_unit_o2_kg")
		var e_expected := b.electrolysis_o2_kg_per_hour * hours if combo[0] else 0.0
		var c_expected := b.co2_unit_o2_kg_per_hour * hours if combo[1] else 0.0
		var reserve_change := st.store(&"oxygen_kg") - float(start.stores[&"oxygen_kg"])
		var label := "neither"
		if combo[0] and combo[1]:
			label = "both"
		elif combo[0]:
			label = "electrolyser alone"
		elif combo[1]:
			label = "CO2-oxygen unit alone"
		_check("oxygen %s: electrolyser %.2f kg, CO2 unit %.2f kg in %.0f h, reserve change %+.2f kg; both statuses reported" % [label, e, c, hours, reserve_change],
			absf(e - e_expected) < 1e-9 and absf(c - c_expected) < 1e-9 and absf(reserve_change - (e + c - _ledger_delta(st, start, "regulator_o2_kg"))) < 1e-9
			and st.oxygen_process.electrolyser == ("running" if combo[0] else "off") and st.oxygen_process.co2_unit == ("running" if combo[1] else "off"), str(st.oxygen_process))
		if combo[0] and not combo[1]:
			var water := _ledger_delta(st, start, "electrolysis_water_l")
			_check("electrolyser: exactly 1.126 L of water per kg of oxygen (%.9f), hydrogen vented = water x 2/18" % (water / e),
				absf(water / e - 1.126) < 1e-9 and absf(_ledger_delta(st, start, "hydrogen_vented_kg") - water * 2.0 / 18.0) < 1e-12)
	var s := _session(4)
	_plenty_of_power(s)
	s.state.equipment.electrolyser.on = true
	s.state.water_allocation.electrolysis_feed_l_per_hour = 0.5 * s.balance.electrolysis_o2_kg_per_hour * GameBalance.WATER_KG_PER_KG_O2
	var start := _snap(s.state, s.balance)
	_hours(s, 4.0)
	_check("electrolyser: half the feed water makes half the oxygen", absf(_ledger_delta(s.state, start, "electrolysis_o2_kg") - 0.5 * s.balance.electrolysis_o2_kg_per_hour * 4.0) < 1e-9 and s.state.oxygen_process.electrolyser == "feed_short")
	s = _session(4)
	_plenty_of_power(s)
	s.state.equipment.electrolyser.on = true
	s.state.water_allocation.electrolysis_feed_l_per_hour = 1.0
	s.state.stores[&"water_l"] = s.balance.water_reserve_l + 0.01
	s.state.equipment.recycler.on = false
	start = _snap(s.state, s.balance)
	_hours(s, 2.0)
	_check("electrolyser: never takes clean water below the drinking reserve", _ledger_delta(s.state, start, "electrolysis_water_l") <= 0.01 + 1e-9 and _ledger_delta(s.state, start, "water_used_l") > 0.0)


func _co2_unit_never_uses_water() -> void:
	var worst := 0.0
	var ran := true
	var combos := 0
	var water_keys: Array[String] = ["water_used_l", "water_to_wastewater_l", "water_body_loss_l", "wastewater_overflow_l", "greenhouse_water_l",
		"electrolysis_water_l", "recycler_in_l", "water_recycled_l", "brine_l"]
	for mask in 64:
		var results: Array = []
		for co2_on: bool in [false, true]:
			var s := _session(4)
			var st := s.state
			_plenty_of_power(s)
			st.equipment.electrolyser.on = (mask & 1) != 0
			st.equipment.recycler.on = (mask & 2) != 0
			st.water_allocation.greenhouse_l_per_hour = 3.0 if (mask & 4) != 0 else 0.0
			st.water_allocation.electrolysis_feed_l_per_hour = 0.5 if (mask & 8) != 0 else 0.0
			st.water_quality = 0.85 if (mask & 16) != 0 else 1.0
			if (mask & 32) != 0:
				st.stores[&"water_l"] = 60.0
			st.equipment.co2_unit.on = co2_on
			var start := _snap(st, s.balance)
			_hours(s, 2.0, 0.1)
			var row := [st.store(&"water_l"), st.store(&"wastewater_l"), st.water_quality]
			for k in water_keys:
				row.append(float(st.ledger[k]))
			results.append(row)
			if co2_on and _ledger_delta(st, start, "co2_unit_o2_kg") <= 0.0:
				ran = false
		for i in (results[0] as Array).size():
			worst = maxf(worst, absf(float(results[0][i]) - float(results[1][i])))
		combos += 1
	_check("CO2-oxygen unit uses no water in any of %d switch combinations (largest water difference %s)" % [combos, _sci(worst)], worst == 0.0 and ran)


func _water_quality() -> void:
	var s := _session(4)
	var st := s.state
	_plenty_of_power(s)
	var counts := _counter(s)
	st.equipment.electrolyser.on = true
	st.equipment.recycler.on = false
	st.water_allocation.electrolysis_feed_l_per_hour = 0.5
	st.water_quality = 0.89
	var start := _snap(st, s.balance)
	_hours(s, 2.0)
	var a := _alert(st, "electrolyser_dirty_water")
	_check("electrolyser stops below water quality 0.9, with 'Electrolyser stopped: the water is not clean enough.'",
		_ledger_delta(st, start, "electrolysis_o2_kg") == 0.0 and String(a.get("text", "")) == "Electrolyser stopped: the water is not clean enough." and int(counts.get("electrolyser_dirty_water", 0)) == 1)
	st.water_quality = 0.9
	start = _snap(st, s.balance)
	_hours(s, 1.0)
	_check("electrolyser runs again at quality 0.9", _ledger_delta(st, start, "electrolysis_o2_kg") > 0.0 and _alert(st, "electrolyser_dirty_water").is_empty())
	# mixing by volume: a recycler in poor condition (0.6) makes water of quality 0.6 / 0.8 = 0.75
	var b := s.balance
	var t := ColonyState.new_game(b, 1)
	t.stores[&"water_l"] = 100.0
	t.stores[&"wastewater_l"] = 10.0
	t.water_quality = 1.0
	t.equipment.recycler.condition = 0.6
	t.equipment.recycler.powered = true
	var none := {"greenhouse_l": 0.0, "electrolyser_o2_kg": 0.0, "co2_unit_o2_kg": 0.0, "status": {"electrolyser": "off", "co2_unit": "off"}}
	LifeSupportModel.run_processes(t, b, none, 1.0)
	var added := b.recycler_l_per_hour * b.recycler_recovery
	var q := (100.0 * 1.0 + 0.75 * added) / (100.0 + added)
	_check("water quality mixes by volume (poor recycler: %.4f)" % q, absf(t.water_quality - q) < 1e-12, "%.6f" % t.water_quality)


func _scrubber() -> void:
	var s := _session(4)
	var st := s.state
	var b := s.balance
	_plenty_of_power(s)
	var counts := _counter(s)
	_do(s, &"crew_2", &"set_equipment", LS, {"equipment": "scrubber", "on": false})
	var co2_start := st.cabin_co2_kg
	var t_warn := [-1.0]
	var t_harm := [-1.0]
	var each := func(t: float) -> void:
		if float(t_warn[0]) < 0.0 and not _alert(st, "co2_high").is_empty():
			t_warn[0] = t
		if float(t_harm[0]) < 0.0:
			for c: CharacterState in st.characters.values():
				if c.health < 100.0:
					t_harm[0] = t
	_hours(s, 60.0, 0.05, each)
	var expected_warn := (b.gas_kg_for_kpa(b.co2_warn_kpa, GameBalance.MOLAR_CO2) - co2_start) / (4.0 * b.co2_kg_per_hour)
	_check("scrubber off: CO2 reaches the warning level at %.1f h (expected %.1f h), alert once" % [float(t_warn[0]), expected_warn],
		float(t_warn[0]) > 0.0 and absf(float(t_warn[0]) - expected_warn) < 0.1 and int(counts.get("co2_high", 0)) == 1, str(counts))
	_check("scrubber off: the warning comes %.1f h before any harm (at least 12 h)" % (float(t_harm[0]) - float(t_warn[0])), float(t_harm[0]) > 0.0 and float(t_harm[0]) - float(t_warn[0]) >= 12.0 and int(counts.get("co2_danger", 0)) == 1)


func _airlock() -> void:
	var s := _session(4)
	var st := s.state
	var b := s.balance
	_plenty_of_power(s)
	_hours(s, 0.5)
	var p0 := st.cabin_pressure_kpa
	for i in 3:
		s.note_airlock_cycle()
	var queued := st.pending_airlock_cycles
	var start := _snap(st, b)
	_hours(s, 0.05)
	var p1 := st.cabin_pressure_kpa
	_check("airlock: three cycles lower cabin pressure (%.2f -> %.2f kPa)" % [p0, p1], queued == 3 and st.pending_airlock_cycles == 0 and p1 < p0 - 0.5 and _ledger_delta(st, start, "airlock_cycles") == 3.0)
	_hours(s, 5.0)
	var n2_used := float(start.stores[&"n2_reserve_kg"]) - st.store(&"n2_reserve_kg")
	var o2_used := float(start.stores[&"oxygen_kg"]) - st.store(&"oxygen_kg")
	_check("airlock: the regulator restores pressure (%.3f kPa) from the reserves" % st.cabin_pressure_kpa,
		absf(st.cabin_pressure_kpa - p0) < 0.01 and absf(st.cabin_o2_kpa - b.o2_setpoint_kpa) < 1e-9
		and absf(n2_used - _ledger_delta(st, start, "airlock_n2_lost_kg")) < 1e-9
		and absf(o2_used - (_ledger_delta(st, start, "airlock_o2_lost_kg") + _ledger_delta(st, start, "cabin_o2_breathed_kg"))) < 1e-9)
	st.stores[&"n2_reserve_kg"] = 0.0
	for i in 40:
		s.note_airlock_cycle()
	_hours(s, 1.0)
	_check("airlock: with no nitrogen left, pressure stays low and an alert says so", st.cabin_pressure_kpa < b.pressure_warn_kpa and not _alert(st, "pressure_low").is_empty() and not _alert(st, "n2_reserve_low").is_empty(), "%.1f kPa" % st.cabin_pressure_kpa)


func _suits() -> void:
	var s := _session(4)
	var st := s.state
	var b := s.balance
	_plenty_of_power(s)
	var counts := _counter(s)
	var walker := st.character(&"crew_4")
	var indoor := st.character(&"crew_3")
	walker.suit_on = true
	indoor.suit_on = true
	s.report_position(4, &"crew_4", Vector3(1000, 0, 0), 0.0)
	_check("suits: report_position marks a character outside", walker.outside and not indoor.outside)
	var start := _snap(st, b)
	_hours(s, 2.0)
	var expected := 100.0 - 2.0 * b.oxygen_kg_per_hour / b.suit_o2_capacity_kg * 100.0
	_check("suits: used only outside (outside %.1f %%, inside 100 %%), cabin feeds only the 3 inside" % walker.suit_charge,
		absf(walker.suit_charge - expected) < 1e-9 and indoor.suit_charge == 100.0 and absf(_ledger_delta(st, start, "cabin_o2_breathed_kg") - 3.0 * b.oxygen_kg_per_hour * 2.0) < 1e-9 and walker.health == 100.0)
	walker.suit_on = false
	_hours(s, 1.0)
	_check("suits: outside without a suit, health falls gradually (%.1f after 1 h) with an urgent alert" % walker.health,
		absf(walker.health - (100.0 - b.health_loss_per_hour_no_air)) < 1e-6 and walker.health > 0.0 and String(_alert(st, "no_air_crew_4").get("level", "")) == "urgent" and int(counts.get("no_air_crew_4", 0)) == 1)
	walker.suit_on = true
	walker.suit_charge = 0.0
	var h0 := walker.health
	_hours(s, 1.0)
	_check("suits: an empty tank outside harms the same way", absf((h0 - walker.health) - b.health_loss_per_hour_no_air) < 1e-6)
	s.report_position(4, &"crew_4", s.config.hub_position, 0.0)
	# refill at the rack
	indoor.suit_charge = 50.0
	var reserve := st.store(&"oxygen_kg")
	var r := _do(s, &"crew_3", &"refill_suit", RACK)
	_check("refill: moves oxygen from the reserve to the tank", r.ok and indoor.suit_charge == 100.0 and absf((reserve - st.store(&"oxygen_kg")) - 0.5 * b.suit_o2_capacity_kg) < 1e-12 and not bool(r.changes.short))
	r = _do(s, &"crew_3", &"refill_suit", RACK)
	_check("refill: a full tank is refused", not r.ok and r.reason == &"missing_prerequisite", String(r.reason))
	indoor.suit_charge = 0.0
	st.stores[&"oxygen_kg"] = 0.25 * b.suit_o2_capacity_kg
	r = _do(s, &"crew_3", &"refill_suit", RACK)
	_check("refill: a short reserve fills what it can and says so", r.ok and absf(indoor.suit_charge - 25.0) < 1e-9 and st.store(&"oxygen_kg") == 0.0 and bool(r.changes.short) and String(r.changes.text).contains("short"))
	r = _do(s, &"crew_3", &"refill_suit", RACK)
	_check("refill: an empty reserve is insufficient", not r.ok and r.reason == &"insufficient", String(r.reason))
	indoor.suit_charge = 37.5
	indoor.suit_on = false
	r = _do(s, &"crew_3", &"begin_suit_check", RACK, {"on": true})
	for i in 12:
		s.advance(0.1)
	_check("suit check: no free refill, the tank is unchanged", r.ok and indoor.suit_on and indoor.suit_charge == 37.5)


func _active_count() -> void:
	var ok := true
	var detail := ""
	for n in [0, 1, 2, 3, 4]:
		var s := _session(n)
		var st := s.state
		_plenty_of_power(s)
		var parked := {}
		for c: CharacterState in st.characters.values():
			if not c.is_active():
				parked[c.id] = c.to_dict()
		var start := _snap(st, s.balance)
		_hours(s, 5.0)
		var b := s.balance
		var breathed := _ledger_delta(st, start, "cabin_o2_breathed_kg")
		var drunk := _ledger_delta(st, start, "water_used_l")
		var eaten := _ledger_delta(st, start, "meals_eaten")
		var exhaled := _ledger_delta(st, start, "co2_exhaled_kg")
		var this_ok := absf(breathed - n * b.oxygen_kg_per_hour * 5.0) < 1e-9 and absf(drunk - n * b.water_l_per_hour * 5.0) < 1e-9 \
			and absf(eaten - n * b.meals_per_sol / GameConfig.SOL_HOURS * 5.0) < 1e-9 and absf(exhaled - n * b.co2_kg_per_hour * 5.0) < 1e-9
		for id: StringName in parked:
			if st.character(id).to_dict() != parked[id]:
				this_ok = false
		if not this_ok:
			detail += " n=%d breathed %.4f drunk %.4f eaten %.4f" % [n, breathed, drunk, eaten]
		ok = ok and this_ok
	_check("active crew 0..4: use scales exactly with the active count; parked crew use nothing and stay frozen", ok, detail)


func _recovery_with_empty_stores() -> void:
	var s := _session(4)
	var st := s.state
	var recovered := []
	s.events.character_recovered.connect(func(id: StringName, info: Dictionary) -> void: recovered.append([id, info]))
	for k in ColonyState.STORE_KEYS:
		st.stores[k] = 0.0
	st.cabin_o2_kg = 0.0
	st.cabin_n2_kg = 0.0
	var invariants := [true]
	_hours(s, 8.0, 0.05, func(_t: float) -> void:
		if not st.invariants_ok().is_empty():
			invariants[0] = false)
	var free_ok := true
	for entry: Array in recovered:
		if float(entry[1].meals) != 0.0 or float(entry[1].water_l) != 0.0:
			free_ok = false
	_check("recovery with empty shared stores still works (%d recoveries), stores stay >= 0" % recovered.size(), recovered.size() >= 4 and free_ok and bool(invariants[0]))


func _toggling() -> void:
	var s := _session(4)
	var st := s.state
	_at(s, &"crew_2", LS)
	var before := st.to_dict()
	var ok := true
	for i in 500:
		var id: String = ColonyState.EQUIPMENT_IDS[i % ColonyState.EQUIPMENT_IDS.size()]
		var was := st.is_on(id)
		ok = s.request(&"set_equipment", LS, {"equipment": id, "on": not was}, 2).ok and ok
		ok = s.request(&"set_equipment", LS, {"equipment": id, "on": was}, 2).ok and ok
	var after := st.to_dict()
	_check("toggling equipment 1,000 times with no time passing changes no store, gas or ledger", ok and after.stores == before.stores and after.ledger == before.ledger and after.cabin_o2_kg == before.cabin_o2_kg and after.equipment == before.equipment)
	var start := _snap(st, s.balance)
	for i in 1000:
		var id: String = ColonyState.EQUIPMENT_IDS[(i * 3) % ColonyState.EQUIPMENT_IDS.size()]
		s.request(&"set_equipment", LS, {"equipment": id, "on": not st.is_on(id)}, 2)
		_hours(s, 0.01, 0.01)
	_check("toggling 1,000 times between ticks creates nothing (identities within %s)" % _sci(_worst(_identities(st, s.balance, start))), _worst(_identities(st, s.balance, start)) < 1e-6 and st.invariants_ok().is_empty())


## Same scripted actions for any run: chosen by the game hour since the start of the script.
func _scripted(s: SessionService, from_hour: float, hours: float) -> void:
	var last := [int(floorf(from_hour)) - 1]
	_at(s, &"crew_2", LS)
	var each := func(t: float) -> void:
		var h := int(floorf(from_hour + t))
		if h == int(last[0]):
			return
		last[0] = h
		if h % 6 == 0:
			s.request(&"set_equipment", LS, {"equipment": "electrolyser", "on": not s.state.is_on("electrolyser")}, 2)
		if h % 9 == 0:
			s.note_airlock_cycle()
		if h % 11 == 0:
			s.request(&"set_water_allocation", LS, {"greenhouse_l_per_hour": float(h % 4), "electrolysis_feed_l_per_hour": 0.3}, 2)
		if h % 13 == 0:
			s.request(&"set_equipment", LS, {"equipment": "co2_unit", "on": not s.state.is_on("co2_unit")}, 2)
		if h == 30:
			s.state.character(&"crew_4").suit_on = true
			s.report_position(4, &"crew_4", Vector3(1000, 0, 0), 0.0)
		if h == 36:
			s.report_position(4, &"crew_4", s.config.hub_position, 0.0)
	_hours(s, hours, 0.05, each)


func _fingerprint(s: SessionService) -> Array:
	var st := s.state
	var out: Array = []
	for k in ColonyState.STORE_KEYS:
		out.append(st.store(k))
	out.append_array([st.cabin_o2_kg, st.cabin_n2_kg, st.cabin_co2_kg, st.water_quality, st.sim_hours, s.clock.phase])
	var keys: Array = st.ledger.keys()
	keys.sort()
	for k: String in keys:
		out.append(float(st.ledger[k]))
	for d: Variant in st.panel_dust:
		out.append(float(d))
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: StringName in ids:
		var c := st.character(id)
		out.append_array([c.health, c.suit_charge])
	return out


func _save_load() -> void:
	var a := _session(4)
	var b := _session(4)
	_scripted(a, 0.0, GameConfig.SOL_HOURS)
	_scripted(b, 0.0, GameConfig.SOL_HOURS)
	var text := JSON.stringify({"colony": b.state.to_dict(), "clock": b.clock.to_dict()}, "", true, true)
	var parsed: Dictionary = JSON.parse_string(text)
	b.begin(ColonyState.from_dict(parsed.colony), SolClock.from_dict(parsed.clock))
	_scripted(a, GameConfig.SOL_HOURS, 2.0 * GameConfig.SOL_HOURS)
	_scripted(b, GameConfig.SOL_HOURS, 2.0 * GameConfig.SOL_HOURS)
	var fa := _fingerprint(a)
	var fb := _fingerprint(b)
	var worst := 0.0
	for i in fa.size():
		worst = maxf(worst, absf(float(fa[i]) - float(fb[i])))
	var alert_ids_a: Array = a.state.alerts.map(func(x: Dictionary) -> String: return String(x.id))
	var alert_ids_b: Array = b.state.alerts.map(func(x: Dictionary) -> String: return String(x.id))
	_check("save -> load -> continue matches an uninterrupted run (%d values, largest difference %s)" % [fa.size(), _sci(worst)], fa.size() == fb.size() and worst <= 1e-9 and alert_ids_a == alert_ids_b)


func _arrival() -> void:
	# ---- nobody does anything for 3 sols
	var s := _session(4)
	var st := s.state
	var counts := _counter(s)
	var first_warn := [-1.0]
	var first_harm := [-1.0]
	var first_air_or_battery := [-1.0]
	var first_food_warn := [-1.0]
	var food_at_harm := [-1.0]
	var low := {"battery_kwh": INF, "water_l": INF, "oxygen_kg": INF, "food_meals": INF, "n2_reserve_kg": INF, "cabin_o2_kg": INF}
	var min_health := [100.0]
	var watch := func(t: float) -> void:
		for k: String in low:
			var v := st.cabin_o2_kg if k == "cabin_o2_kg" else st.store(StringName(k))
			low[k] = minf(float(low[k]), v)
		for a: Dictionary in st.alerts:
			if float(first_warn[0]) < 0.0 and String(a.level) != "info":
				first_warn[0] = t
			var aid := String(a.id)
			if float(first_air_or_battery[0]) < 0.0 and String(a.level) != "info" and (aid.begins_with("battery_") or aid.begins_with("shed_") or aid.begins_with("cabin_") or aid.begins_with("co2_") or aid.begins_with("oxygen_") or aid.begins_with("pressure_")):
				first_air_or_battery[0] = t
			if float(first_food_warn[0]) < 0.0 and aid.begins_with("food_"):
				first_food_warn[0] = t
		for c: CharacterState in st.characters.values():
			min_health[0] = minf(float(min_health[0]), c.health)
			if float(first_harm[0]) < 0.0 and c.health < 100.0:
				first_harm[0] = t
				food_at_harm[0] = st.store(&"food_meals")
	var sunrise_battery := []
	_hours(s, 3.0 * GameConfig.SOL_HOURS, 0.05, func(t: float) -> void:
		watch.call(t)
		if PowerModel.crosses_sunrise(fposmod(s.clock.phase - 0.05 / GameConfig.SOL_HOURS, 1.0), 0.05):
			sunrise_battery.append(st.store(&"battery_kwh")))
	var all_above := true
	for k: String in low:
		all_above = all_above and float(low[k]) > 0.0
	_check("arrival, no action for 3 sols: nobody reaches zero health (lowest %.1f), every supply store stays above zero (lowest battery %.0f kWh, oxygen %.1f kg)" % [float(min_health[0]), float(low.battery_kwh), float(low.oxygen_kg)],
		float(min_health[0]) > 0.0 and all_above, str(low))
	_check("arrival, 3 sols: first warning of any kind at %.2f h (the failed cleaner); battery or air warning %s; harm %s" % [float(first_warn[0]), "none" if float(first_air_or_battery[0]) < 0.0 else "at %.1f h" % float(first_air_or_battery[0]), "none" if float(first_harm[0]) < 0.0 else "at %.1f h" % float(first_harm[0])],
		float(first_warn[0]) >= 0.0 and (float(first_harm[0]) < 0.0 or (float(first_air_or_battery[0]) >= 0.0 and float(first_harm[0]) - float(first_air_or_battery[0]) >= 12.0)))
	_check("arrival: energy-negative before the restoration (battery at sunrise %s kWh)" % str(sunrise_battery.map(func(x: float) -> int: return int(x))),
		sunrise_battery.size() >= 2 and float(sunrise_battery[-1]) < float(sunrise_battery[0]))
	# keep going with no action: the battery warning comes well before the battery runs dry, and before any harm
	var t_battery_warn := [-1.0]
	var t_shed := [-1.0]
	var t0 := 3.0 * GameConfig.SOL_HOURS
	_hours(s, 7.0 * GameConfig.SOL_HOURS, 0.05, func(t: float) -> void:
		watch.call(t0 + t)
		if float(t_battery_warn[0]) < 0.0 and not _alert(st, "battery_low").is_empty():
			t_battery_warn[0] = t0 + t
		if float(t_shed[0]) < 0.0 and not st.shed.is_empty():
			t_shed[0] = t0 + t)
	_check("no action for 10 sols: 'battery low' at %.1f h, %.1f h before the first load is shed" % [float(t_battery_warn[0]), float(t_shed[0]) - float(t_battery_warn[0])],
		float(t_battery_warn[0]) > 0.0 and float(t_shed[0]) - float(t_battery_warn[0]) >= 12.0)
	_check("no action for 10 sols: first battery or air warning (%.1f h) comes %.1f h before the first harm (%.1f h)" % [float(first_air_or_battery[0]), float(first_harm[0]) - float(first_air_or_battery[0]), float(first_harm[0])],
		float(first_harm[0]) < 0.0 or (float(first_air_or_battery[0]) >= 0.0 and float(first_harm[0]) - float(first_air_or_battery[0]) >= 12.0))
	_check("no action for 10 sols: the first harm is hunger (food %.2f meals left), and 'food low' came %.1f h before it" % [float(food_at_harm[0]), float(first_harm[0]) - float(first_food_warn[0])],
		float(first_harm[0]) > 0.0 and float(food_at_harm[0]) <= 1e-9 and float(first_harm[0]) - float(first_food_warn[0]) >= 12.0)

	# ---- arrival restoration through the real actions, then one sol
	for mode: String in ["electrolyser", "co2_unit", "both"]:
		var r := _session(4)
		var rs := r.state
		var ok := true
		for id: String in _catalog:
			if String(_catalog[id].kind) == "solar":
				ok = _do(r, &"crew_2", &"clean_panel", StringName(id)).ok and ok
		ok = _do(r, &"crew_1", &"repair_cleaner", &"sf_solar_tracker").ok and ok
		if mode != "co2_unit":
			ok = _do(r, &"crew_2", &"set_water_allocation", LS, {"electrolysis_feed_l_per_hour": 0.5}).ok and ok
			ok = _do(r, &"crew_2", &"set_equipment", LS, {"equipment": "electrolyser", "on": true}).ok and ok
		if mode != "electrolyser":
			ok = _do(r, &"crew_2", &"set_equipment", LS, {"equipment": "co2_unit", "on": true}).ok and ok
		_until_phase(r, 0.25)
		for c: CharacterState in rs.characters.values():
			c.position = c.hub_spot
		var start := _snap(rs, r.balance)
		_hours(r, GameConfig.SOL_HOURS)
		var offered := _ledger_delta(rs, start, "solar_offered_kwh")
		var served := _ledger_delta(rs, start, "load_served_kwh")
		var loss := _ledger_delta(rs, start, "battery_loss_kwh")
		var battery_change := rs.store(&"battery_kwh") - float(start.stores[&"battery_kwh"])
		var o2_change := rs.store(&"oxygen_kg") - float(start.stores[&"oxygen_kg"])
		_check("restored (%s): energy-positive over a sol (sun %.0f kWh > used %.0f + battery loss %.0f; battery %+.0f kWh), oxygen-positive (%+.2f kg), nothing unserved" % [mode, offered, served, loss, battery_change, o2_change],
			ok and offered > served + loss and o2_change > 0.0 and _ledger_delta(rs, start, "load_unserved_kwh") == 0.0)
		# from a low battery at sunrise the battery gains over the sol
		rs.stores[&"battery_kwh"] = 300.0
		var b0 := rs.store(&"battery_kwh")
		_hours(r, GameConfig.SOL_HOURS)
		_check("restored (%s): from 300 kWh at sunrise the battery ends the sol higher (%.0f kWh)" % [mode, rs.store(&"battery_kwh")], rs.store(&"battery_kwh") > b0 + 50.0)


func _forecast() -> void:
	# battery at night: hours until empty and charge at the next sunrise
	var s := _session(4)
	var st := s.state
	_until_phase(s, 0.8)
	st.stores[&"battery_kwh"] = 150.0
	_hours(s, 0.05)
	var f := ReserveForecast.compute(st, s.balance, s.clock)
	var t_empty := [-1.0]
	_hours(s, 12.0, 0.01, func(t: float) -> void:
		if float(t_empty[0]) < 0.0 and not st.shed.is_empty():
			t_empty[0] = t)
	_check("forecast: battery lasts %.2f h, simulation runs out (first load shed) at %.2f h (within 2 %%)" % [float(f.battery_hours), float(t_empty[0])],
		float(t_empty[0]) > 0.0 and absf(float(f.battery_hours) - float(t_empty[0])) <= 0.02 * float(t_empty[0]))
	for start_phase: float in [0.8, 0.4]:
		s = _session(4)
		st = s.state
		_until_phase(s, start_phase)
		st.stores[&"battery_kwh"] = 500.0 if start_phase > 0.5 else 300.0
		_hours(s, 0.05)
		f = ReserveForecast.compute(st, s.balance, s.clock)
		_hours(s, float(f.hours_to_sunrise), 0.01)
		var measured := st.store(&"battery_kwh")
		_check("forecast: battery at next sunrise from phase %.1f: %.1f kWh, simulation %.1f kWh (within 2 %%)" % [start_phase, float(f.battery_at_sunrise_kwh), measured],
			absf(float(f.battery_at_sunrise_kwh) - measured) <= 0.02 * measured)
	# oxygen reserve, water, food and a suit, each against its own forward simulation
	var lines: Array = []
	for what: String in ["oxygen_kg", "water_l", "food_meals", "suit"]:
		s = _session(4)
		st = s.state
		_plenty_of_power(s)
		st.stores[&"wastewater_l"] = 0.0                     # no recycling backlog: steady flows from the first tick
		match what:
			"oxygen_kg": st.stores[&"oxygen_kg"] = 5.0
			"water_l": st.stores[&"water_l"] = 30.0
			"food_meals": st.stores[&"food_meals"] = 6.0
			"suit":
				st.character(&"crew_4").suit_on = true
				st.character(&"crew_4").suit_charge = 50.0
				s.report_position(4, &"crew_4", Vector3(1000, 0, 0), 0.0)
		_hours(s, 0.5)
		f = ReserveForecast.compute(st, s.balance, s.clock)
		if what == "suit":
			lines = f.text
		var predicted := float((f.suit_hours as Dictionary).get("crew_4", -1.0)) if what == "suit" else float(f[what.split("_")[0] + "_hours"])
		var t_empty_res := [-1.0]
		_hours(s, maxf(5.0, predicted * 1.2), 0.02, func(t: float) -> void:
			var left := st.character(&"crew_4").suit_charge if what == "suit" else st.store(StringName(what))
			if float(t_empty_res[0]) < 0.0 and left <= 1e-9:
				t_empty_res[0] = t)
		var measured := float(t_empty_res[0])
		_check("forecast: %s lasts %.2f h, simulation %.2f h (within 2 %%)" % [what, predicted, measured], measured > 0.0 and absf(predicted - measured) <= 0.02 * measured)
	_check("forecast: plain text lines ('%s')" % String(lines[0]), lines.size() >= 6 and String(lines[0]).begins_with("Battery:") and String(lines[2]).contains("lasts until about"))
	s = _session(4)
	_plenty_of_power(s)
	s.state.equipment.electrolyser.on = true
	s.state.water_allocation.electrolysis_feed_l_per_hour = 1.0
	_hours(s, 0.5)
	f = ReserveForecast.compute(s.state, s.balance, s.clock)
	_check("forecast: -1 for a reserve that is not falling (oxygen with the electrolyser on)", float(f.oxygen_hours) == -1.0 and float(f.battery_hours) == -1.0)


func _sol_length() -> void:
	var reference: Array = []
	for minutes: float in [5.0, 20.0, 120.0]:
		var s := _session(4)
		var st := s.state
		st.equipment.electrolyser.on = true
		st.water_allocation.electrolysis_feed_l_per_hour = 0.5
		st.water_allocation.greenhouse_l_per_hour = 1.0
		st.equipment.co2_unit.on = true
		st.equipment.cleaner.condition = 1.0
		s.request(&"set_sol_minutes", &"", {"minutes": minutes})
		var seconds := minutes * 60.0
		var done := 0.0
		while done < seconds - 1e-9:
			s.advance(1.0)
			done += 1.0
		while s.advance(0.0) > 0:
			pass
		var values: Array = []
		for k in ColonyState.STORE_KEYS:
			values.append(st.store(k))
		values.append_array([st.cabin_o2_kg, st.cabin_n2_kg, st.cabin_co2_kg])
		if reference.is_empty():
			reference = values
		var worst := 0.0
		for i in values.size():
			worst = maxf(worst, absf(float(values[i]) - float(reference[i])) / maxf(1.0, absf(float(reference[i]))))
		_check("full sol at %.0f real minutes: stores within 1 %% of the 5-minute sol (largest difference %.4f %%)" % [minutes, worst * 100.0],
			worst <= 0.01 and absf(s.clock.game_hours() - GameConfig.SOL_HOURS * (1.0 + s.config.start_phase)) < 1e-6 and st.invariants_ok().is_empty())
