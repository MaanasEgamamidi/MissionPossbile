extends SceneTree
## Night energy and NASA crew rates (energy and NASA worker, 2026-11-14). Every PASS is measured on the running model:
## solar is exactly 0 kW at night, the battery falls by the load per night hour, a wasteful night runs the battery flat
## before sunrise while a careful one does not, the shed order, PowerModel.outlook() fields and text, each area-level
## effect key changes its machine, and one crew member's use over one sol matches the NASA BVAD Rev2 per-day values
## (source S20) times 24.6598 / 24.
## Run: godot --headless --path . --script res://tests/test_energy_night.gd

const MANIFEST := "res://data/colony_manifest.json"

var _passed := 0
var _total := 0
var _event_nodes: Array[GameEvents] = []
var _zones: ColonyZones
var _catalog: Dictionary


func _initialize() -> void:
	_zones = ColonyZones.from_manifest(MANIFEST)
	_catalog = StationCatalog.from_manifest(MANIFEST, _zones)
	AreaLevels.reload()
	_solar_zero_at_night()
	_battery_per_night_hour()
	_careful_and_wasteful()
	_shed_order()
	_outlook()
	_effects()
	_nasa_totals()
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


## A host session on the real map with `active` crew, at the new-game time of day (as in test_life_support).
func _session(active: int = 4) -> SessionService:
	var ev := GameEvents.new()
	_event_nodes.append(ev)
	var s := SessionService.new(GameConfig.new(), GameBalance.new(), ev)
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


func _until_phase(s: SessionService, target: float, dt: float = 0.05) -> void:
	_hours(s, fposmod(target - s.clock.phase, 1.0) * GameConfig.SOL_HOURS, dt)


func _demand(st: ColonyState, b: GameBalance) -> float:
	var process := {"electrolyser": float(st.unit("electrolyser").get("kw", 0.0)), "co2_unit": float(st.unit("co2_unit").get("kw", 0.0))}
	var kw := 0.0
	for g in PowerModel.demand_groups(st, b, process):
		kw += float(g.kw)
	return kw


## Careful night: only the critical room lights stay on, greenhouse grow lights off.
func _make_careful(st: ColonyState, b: GameBalance) -> void:
	for z: String in st.zones:
		if not b.critical_light_zones.has(z):
			st.zones[z]["powered"] = false


## Wasteful night: every room light, greenhouse lights and both oxygen machines on.
func _make_wasteful(st: ColonyState) -> void:
	for z: String in st.zones:
		st.zones[z]["powered"] = true
	st.equipment.electrolyser.on = true
	st.equipment.co2_unit.on = true
	st.water_allocation.electrolysis_feed_l_per_hour = 1.0


# ------------------------------------------------------------------ night solar

func _solar_zero_at_night() -> void:
	var b := GameBalance.new()
	var st := ColonyState.new_game(b, 7, _zones.names)
	st.dust_tau = 0.0                                          # the clearest sky possible
	for i in ColonyState.TRACKER_COUNT:
		st.panel_dust[i] = 0.0
	var worst := 0.0
	var samples := 0
	for setup in [{"level": 1, "upgrade": false, "track": true}, {"level": 4, "upgrade": true, "track": true}, {"level": 4, "upgrade": true, "track": false}]:
		st.levels["energy"] = int(setup.level)
		st.upgrades["energy_solar_tracking"] = {"installed": bool(setup.upgrade)}
		for k in 1001:
			var ph := PowerModel.SUNSET + 0.5 * float(k) / 1000.0          # sunset .. sunrise of the next sol
			ph = fposmod(ph, 1.0)
			samples += 1
			worst = maxf(worst, absf(PowerModel.solar_kw(st, b, ph, bool(setup.track))))
			for i in ColonyState.TRACKER_COUNT:
				worst = maxf(worst, absf(PowerModel.tracker_kw(st, b, ph, bool(setup.track), i)))
	_check("night: solar is exactly 0 kW at %d night phases (sunset and sunrise included), V1 and V4, tracking upgrade, trackers on and off" % samples, worst == 0.0, "largest %s kW" % worst)
	st.levels["energy"] = 1
	st.upgrades["energy_solar_tracking"] = {"installed": false}
	var just_after := PowerModel.solar_kw(st, b, PowerModel.SUNRISE + 0.01, true)
	_check("day: the same panels give power just after sunrise (%.2f kW)" % just_after, just_after > 0.0)

	# a full night through the real session: no solar energy offered at all, trackers still drawing their drive power
	var s := _session(4)
	_until_phase(s, PowerModel.SUNSET + 0.001)
	var offered := float(s.state.ledger.solar_offered_kwh)
	var max_solar := [0.0]
	_hours(s, 0.5 * GameConfig.SOL_HOURS - 0.05, 0.05, func(_t: float) -> void: max_solar[0] = maxf(float(max_solar[0]), s.state.solar_kw))
	_check("night in the session: 0 kWh of solar offered and solar_kw 0 for the whole %.2f h night" % (0.5 * GameConfig.SOL_HOURS),
		float(s.state.ledger.solar_offered_kwh) - offered == 0.0 and float(max_solar[0]) == 0.0, "offered %s, max %s" % [float(s.state.ledger.solar_offered_kwh) - offered, max_solar[0]])


# ------------------------------------------------------------------ battery per night hour

func _battery_per_night_hour() -> void:
	var s := _session(4)
	var st := s.state
	var b := s.balance
	_until_phase(s, 0.8)
	st.stores[&"battery_kwh"] = 0.9 * float(st.capacities[&"battery_kwh"])
	_hours(s, 0.05)
	var load := _demand(st, b)
	var before := st.store(&"battery_kwh")
	var out0 := float(st.ledger.battery_out_kwh)
	var drops: Array = []
	for hour in 3:
		var h0 := st.store(&"battery_kwh")
		_hours(s, 1.0, 0.01)
		drops.append(h0 - st.store(&"battery_kwh"))
	var each_ok := true
	for d: float in drops:
		each_ok = each_ok and absf(d - load) < 1e-6
	_check("night: the battery falls by the load each hour (%.1f kW -> %s kWh per hour)" % [load, str(drops.map(func(x: float) -> String: return "%.3f" % x))],
		each_ok and absf((before - st.store(&"battery_kwh")) - (float(st.ledger.battery_out_kwh) - out0)) < 1e-6, str(drops))
	_check("night: the arrival night load is the documented 23.1 kW (285 kWh per 12.33 h night)", absf(load - 23.1) < 1e-6, "%.4f kW" % load)
	var cap := float(st.capacities[&"battery_kwh"])
	var share := load * 0.5 * GameConfig.SOL_HOURS / cap
	_check("night: one arrival night takes %.0f %% of the %.0f kWh battery (visible: at least 40 %%), %.1f %% per game hour" % [share * 100.0, cap, 100.0 * load / cap],
		share >= 0.4 and share < 1.0)


# ------------------------------------------------------------------ careful and wasteful

func _night_from(mode: String, battery: float) -> Dictionary:
	var s := _session(4)
	var st := s.state
	_until_phase(s, PowerModel.SUNSET - 0.001)
	if mode == "careful":
		_make_careful(st, s.balance)
	else:
		_make_wasteful(st)
	st.stores[&"battery_kwh"] = battery
	_hours(s, 0.0011 * GameConfig.SOL_HOURS, 0.01)           # just past sunset, flows settled
	var res := {"load": _demand(st, s.balance), "shed_at": -1.0, "first_shed": "", "outlook": PowerModel.outlook(st, s.balance, s.clock.phase)}
	var night := fposmod(PowerModel.SUNRISE - s.clock.phase, 1.0) * GameConfig.SOL_HOURS
	_hours(s, night, 0.01, func(t: float) -> void:
		if float(res.shed_at) < 0.0 and not st.shed.is_empty():
			res.shed_at = t
			res.first_shed = String(st.shed[0]))
	res["night"] = night
	res["end"] = st.store(&"battery_kwh")
	res["harmed"] = st.characters.values().any(func(c: CharacterState) -> bool: return c.health < 100.0)
	return res


func _careful_and_wasteful() -> void:
	var cap := GameBalance.new().battery_kwh_capacity
	var half := 0.4 * cap                                     # a battery the dusty day only part-filled
	var careful := _night_from("careful", half)
	var wasteful := _night_from("wasteful", half)
	_check("careful night from a 40 %% battery (%.0f kWh): %.1f kW, survives to sunrise with %.0f kWh, nothing shed" % [half, float(careful.load), float(careful.end)],
		float(careful.shed_at) < 0.0 and float(careful.end) > 0.4 * half and absf(float(careful.load) - 8.9) < 1e-6, str(careful))
	_check("wasteful night from the same battery: %.1f kW, runs flat %.1f h after sunset, %.1f h before sunrise; the first thing cut is room lights" % [float(wasteful.load), float(wasteful.shed_at), float(wasteful.night) - float(wasteful.shed_at)],
		float(wasteful.shed_at) > 0.0 and float(wasteful.shed_at) < float(wasteful.night) and String(wasteful.first_shed) == "lights" and float(wasteful.load) > 25.0, str(wasteful))
	_check("wasteful night: the outlook warned at sunset that the battery runs out before sunrise; the careful one did not",
		bool((wasteful.outlook as Dictionary).runs_out_before_sunrise) and not bool((careful.outlook as Dictionary).runs_out_before_sunrise)
		and String((wasteful.outlook as Dictionary).text).contains("runs out before sunrise"), String((wasteful.outlook as Dictionary).text))
	_check("wasteful night: running flat sheds power but harms nobody within the night (life support is cut last)", not bool(wasteful.harmed))
	var full_careful := _night_from("careful", cap)
	var full_wasteful := _night_from("wasteful", cap)
	_check("from a full battery both survive one night (careful ends at %.0f %%, wasteful at %.0f %%): the danger is a battery the day did not refill" % [100.0 * float(full_careful.end) / cap, 100.0 * float(full_wasteful.end) / cap],
		float(full_careful.shed_at) < 0.0 and float(full_wasteful.shed_at) < 0.0 and float(full_wasteful.end) < 0.6 * cap)


# ------------------------------------------------------------------ shed order

func _shed_order() -> void:
	var s := _session(4)
	var st := s.state
	_until_phase(s, 0.9)
	_make_wasteful(st)
	_hours(s, 0.05)
	st.stores[&"battery_kwh"] = 0.0
	_hours(s, 0.05)
	var order_ok := st.shed.size() == PowerModel.SHED_ORDER.size()
	for i in st.shed.size():
		order_ok = order_ok and String(st.shed[i]) == PowerModel.SHED_ORDER[i]
	_check("empty battery at night: every group is cut, in the priority order lights first, control and heating last (%s)" % ", ".join(PackedStringArray(st.shed)), order_ok, str(st.shed))
	var o := PowerModel.outlook(st, s.balance, s.clock.phase)
	_check("empty battery: outlook text says so ('%s')" % String(o.text), String(o.text).begins_with("Night: no sun. Battery empty") and String(o.next_shed) == "lights")
	var words := PowerModel.shed_order_words()
	var low := {}
	for a: Dictionary in st.alerts:
		if String(a.id) == "battery_low":
			low = a
	_check("battery low alert names the order power is cut ('%s')" % words, String(low.get("text", "")).contains(words) and words.begins_with("room lights, greenhouse lights") and words.ends_with("and last control and heating"), String(low.get("text", "")))


# ------------------------------------------------------------------ outlook

func _outlook() -> void:
	var s := _session(4)
	var st := s.state
	var b := s.balance
	_until_phase(s, 0.8)
	st.stores[&"battery_kwh"] = 0.62 * float(st.capacities[&"battery_kwh"])
	_hours(s, 0.01)
	var o := PowerModel.outlook(st, b, s.clock.phase)
	var keys := ["sun_up", "solar_kw", "load_kw", "battery_kwh", "battery_capacity_kwh", "net_kw", "hours_left", "hours_to_sunrise", "text"]
	var missing: Array = keys.filter(func(k: String) -> bool: return not o.has(k))
	_check("outlook: every contract field is there", missing.is_empty(), str(missing))
	var load := _demand(st, b)
	var to_sunrise := fposmod(PowerModel.SUNRISE - s.clock.phase, 1.0) * GameConfig.SOL_HOURS
	_check("outlook at night: sun down, 0 kW solar, load %.1f kW, net = -load, hours left = battery / load (%.2f h), sunrise in %.2f h" % [load, float(o.hours_left), float(o.hours_to_sunrise)],
		not bool(o.sun_up) and float(o.solar_kw) == 0.0 and absf(float(o.load_kw) - load) < 1e-9 and absf(float(o.net_kw) + load) < 1e-9
		and absf(float(o.hours_left) - st.store(&"battery_kwh") / load) < 1e-9 and absf(float(o.hours_to_sunrise) - to_sunrise) < 1e-9
		and absf(float(o.battery_capacity_kwh) - float(st.capacities[&"battery_kwh"])) < 1e-9, str(o))
	var want := "Night: no sun. Battery 62 %%, falling %.1f kW, about %d h left, sunrise in %d h." % [load, roundi(float(o.hours_left)), roundi(to_sunrise)]
	_check("outlook night text: '%s'" % String(o.text), String(o.text) == want, "want '%s'" % want)
	# hours_left against the simulation: when is the first load shed? (from a battery that empties before sunrise)
	st.stores[&"battery_kwh"] = 150.0
	_hours(s, 0.01)
	o = PowerModel.outlook(st, b, s.clock.phase)
	_check("outlook: a battery that empties before sunrise is flagged ('%s')" % String(o.text),
		bool(o.runs_out_before_sunrise) and String(o.text).ends_with("It runs out before sunrise: switch off lights and machines you do not need."))
	var t_empty := [-1.0]
	_hours(s, 12.0, 0.01, func(t: float) -> void:
		if float(t_empty[0]) < 0.0 and not st.shed.is_empty():
			t_empty[0] = t)
	_check("outlook: 'hours left' %.2f h matches the simulation running flat at %.2f h (within 2 %%)" % [float(o.hours_left), float(t_empty[0])],
		float(t_empty[0]) > 0.0 and absf(float(o.hours_left) - float(t_empty[0])) <= 0.02 * float(t_empty[0]))
	# day: charging, INF hours left
	var d := _session(4)
	_until_phase(d, 0.5)
	for i in ColonyState.TRACKER_COUNT:
		d.state.panel_dust[i] = 0.0
	_make_careful(d.state, d.balance)
	d.state.stores[&"battery_kwh"] = 100.0
	_hours(d, 0.01)
	var od := PowerModel.outlook(d.state, d.balance, d.clock.phase)
	_check("outlook at noon with clean panels: sun up, charging, hours left INF, text '%s'" % String(od.text),
		bool(od.sun_up) and float(od.solar_kw) > float(od.load_kw) and float(od.net_kw) > 0.0 and is_inf(float(od.hours_left))
		and String(od.text).begins_with("Day: the sun gives") and String(od.text).contains("charging") and String(od.text).contains("sunset in 6 h"))
	_check("outlook solar matches the model's solar this tick (%.3f vs %.3f kW)" % [float(od.solar_kw), d.state.solar_kw], absf(float(od.solar_kw) - d.state.solar_kw) < 0.05 * d.state.solar_kw)


# ------------------------------------------------------------------ effect keys

func _effects() -> void:
	var b := GameBalance.new()
	# energy.solar_factor
	var st := ColonyState.new_game(b, 11, _zones.names)
	var base_kw := PowerModel.solar_kw(st, b, 0.5, true)
	var ratios := []
	var solar_ok := true
	for lvl in [2, 3, 4]:
		st.levels["energy"] = lvl
		var f := float(AreaLevels.effect_at("energy", "solar_factor", lvl, 1.0))
		var r := PowerModel.solar_kw(st, b, 0.5, true) / base_kw
		ratios.append("%.2f" % r)
		solar_ok = solar_ok and absf(r - f) < 1e-9 and f > 1.0
	_check("energy.solar_factor multiplies noon solar (V2..V4 ratios %s)" % str(ratios), solar_ok)

	# life_support.scrubber_factor: CO2 removed in one hour with no crew
	var removed := []
	for lvl in [1, 4]:
		var s := ColonyState.new_game(b, 12, _zones.names)
		s.levels["life_support"] = lvl
		s.equipment.scrubber.powered = true
		s.equipment.cabin_fans.powered = true
		s.cabin_co2_kg = b.gas_kg_for_kpa(1.5, GameBalance.MOLAR_CO2)
		var c0 := s.cabin_co2_kg
		LifeSupportModel.run_cabin(s, b, 0, 1.0)
		removed.append(c0 - s.cabin_co2_kg)
	var sf := float(AreaLevels.effect_at("life_support", "scrubber_factor", 4, 1.0))
	_check("life_support.scrubber_factor: the scrubber removes %.3f kg/h at V1 and %.3f kg/h at V4 (x%.2f)" % [removed[0], removed[1], sf],
		absf(float(removed[0]) - b.scrubber_co2_kg_per_hour) < 1e-9 and absf(float(removed[1]) - b.scrubber_co2_kg_per_hour * sf) < 1e-9 and sf > 1.0)

	# life_support.o2_production_factor: both oxygen machines, and the power they ask for
	var made := []
	var kw := []
	for lvl in [1, 3]:
		var s := ColonyState.new_game(b, 13, _zones.names)
		s.levels["life_support"] = lvl
		s.stores[&"oxygen_kg"] = 0.0
		s.equipment.electrolyser.on = true
		s.equipment.co2_unit.on = true
		s.water_allocation.electrolysis_feed_l_per_hour = 10.0
		var plan := LifeSupportModel.plan_processes(s, b, 1.0)
		made.append([float(plan.electrolyser_o2_kg), float(plan.co2_unit_o2_kg)])
		kw.append(float(plan.kw.electrolyser) + float(plan.kw.co2_unit))
	var of := float(AreaLevels.effect_at("life_support", "o2_production_factor", 3, 1.0))
	_check("life_support.o2_production_factor: electrolyser %.3f -> %.3f kg/h, CO2-oxygen unit %.3f -> %.3f kg/h (x%.2f), power asked x%.2f" % [made[0][0], made[1][0], made[0][1], made[1][1], of, float(kw[1]) / float(kw[0])],
		absf(float(made[0][0]) - b.electrolysis_o2_kg_per_hour) < 1e-9 and absf(float(made[1][0]) - b.electrolysis_o2_kg_per_hour * of) < 1e-9
		and absf(float(made[1][1]) - b.co2_unit_o2_kg_per_hour * of) < 1e-9 and absf(float(kw[1]) / float(kw[0]) - of) < 1e-9 and of > 1.0)

	# life_support.recycler_factor: wastewater cleaned in one hour
	var cleaned := []
	for lvl in [1, 4]:
		var s := ColonyState.new_game(b, 14, _zones.names)
		s.levels["life_support"] = lvl
		s.equipment.recycler.powered = true
		s.stores[&"wastewater_l"] = 100.0
		var w0 := float(s.ledger.recycler_in_l)
		var none := {"greenhouse_l": 0.0, "electrolyser_o2_kg": 0.0, "co2_unit_o2_kg": 0.0, "status": {"electrolyser": "off", "co2_unit": "off"}}
		LifeSupportModel.run_processes(s, b, none, 1.0)
		cleaned.append(float(s.ledger.recycler_in_l) - w0)
	var rf := float(AreaLevels.effect_at("life_support", "recycler_factor", 4, 1.0))
	_check("life_support.recycler_factor: the recycler cleans %.2f L/h at V1 and %.2f L/h at V4 (x%.2f)" % [cleaned[0], cleaned[1], rf],
		absf(float(cleaned[0]) - b.recycler_l_per_hour) < 1e-9 and absf(float(cleaned[1]) - b.recycler_l_per_hour * rf) < 1e-9 and rf > 1.0)

	# garden.plant_o2_kg_per_hour: oxygen into the cabin air, CO2 out (44/32), nothing at V1
	var gained := []
	for lvl in [1, 4]:
		var s := ColonyState.new_game(b, 15, _zones.names)
		s.levels["garden"] = lvl
		s.equipment.scrubber.on = false
		s.stores[&"oxygen_kg"] = 0.0                               # the regulator cannot add any oxygen
		s.cabin_o2_kg -= 5.0                                       # below the set point: nothing is banked
		var o0 := s.cabin_o2_kg
		var c0 := s.cabin_co2_kg
		LifeSupportModel.run_cabin(s, b, 0, 2.0)
		gained.append([s.cabin_o2_kg - o0, c0 - s.cabin_co2_kg, float(s.ledger.get("plant_o2_kg", 0.0))])
	var pg := float(AreaLevels.effect_at("garden", "plant_o2_kg_per_hour", 4, 0.0))
	_check("garden.plant_o2_kg_per_hour: V1 plants give 0 kg; V4 plants give %.3f kg O2 in 2 h (%.3f kg/h) and take up %.3f kg CO2" % [gained[1][0], pg, gained[1][1]],
		absf(float(gained[0][0])) < 1e-12 and absf(float(gained[0][1])) < 1e-12 and absf(float(gained[1][0]) - 2.0 * pg) < 1e-9
		and absf(float(gained[1][1]) - 2.0 * pg * GameBalance.PLANT_CO2_KG_PER_KG_O2) < 1e-9 and absf(float(gained[1][2]) - 2.0 * pg) < 1e-9 and pg > 0.0, str(gained))
	# plant oxygen pushed above the set point is banked in the reserve, never lost or doubled
	var full := ColonyState.new_game(b, 16, _zones.names)
	full.levels["garden"] = 4
	full.equipment.scrubber.on = false
	var r0 := full.store(&"oxygen_kg")
	var cab0 := full.cabin_o2_kg
	LifeSupportModel.run_cabin(full, b, 0, 1.0)
	var banked := float(full.ledger.get("plant_o2_banked_kg", 0.0))
	_check("garden plants with a full cabin: %.4f kg banked in the oxygen reserve, cabin stays at its set point" % banked,
		absf(banked - pg) < 1e-9 and absf(full.store(&"oxygen_kg") - r0 - pg) < 1e-9 and absf(full.cabin_o2_kg - cab0) < 1e-9)


# ------------------------------------------------------------------ NASA totals

func _nasa_totals() -> void:
	var b := GameBalance.new()
	var st := ColonyState.new_game(b, 21, _zones.names)
	st.capacities[&"battery_kwh"] = 1.0e7
	st.stores[&"battery_kwh"] = 5.0e6
	st.character(&"crew_1").owner_peer = 1                      # one active crew member, indoors
	var sim := ColonySim.new()
	var marks := {}
	var t := 0.0
	var phase := 0.3
	var dt := 0.01
	var total := GameConfig.SOL_HOURS
	while t < total - 1e-9:
		var h := minf(dt, total - t)
		if t < 24.0 and t + h > 24.0:
			h = 24.0 - t                                         # stop exactly at 24 h to read one NASA day
		sim.step(st, b, phase, h)
		phase = fposmod(phase + h / GameConfig.SOL_HOURS, 1.0)
		t += h
		if absf(t - 24.0) < 1e-9:
			marks = {"o2": float(st.ledger.cabin_o2_breathed_kg), "co2": float(st.ledger.co2_exhaled_kg), "water": float(st.ledger.water_used_l), "meals": float(st.ledger.meals_eaten)}
	var sol :=GameConfig.SOL_HOURS / GameBalance.HOURS_PER_DAY
	var rows := [
		["oxygen", float(marks.get("o2", -1.0)), float(st.ledger.cabin_o2_breathed_kg), GameBalance.NASA_O2_KG_PER_CREW_DAY, "kg"],
		["CO2", float(marks.get("co2", -1.0)), float(st.ledger.co2_exhaled_kg), GameBalance.NASA_CO2_KG_PER_CREW_DAY, "kg"],
		["water", float(marks.get("water", -1.0)), float(st.ledger.water_used_l), GameBalance.NASA_WATER_KG_PER_CREW_DAY, "L"],
		["food energy", float(marks.get("meals", -1.0)) * b.meal_mj(), float(st.ledger.meals_eaten) * b.meal_mj(), GameBalance.NASA_FOOD_MJ_PER_CREW_DAY, "MJ"],
		["food eaten", float(marks.get("meals", -1.0)) * b.meal_kg(), float(st.ledger.meals_eaten) * b.meal_kg(), GameBalance.NASA_FOOD_KG_PER_CREW_DAY, "kg"],
	]
	for r: Array in rows:
		var per_day := float(r[3])
		_check("NASA (S20): one crew member uses %.3f %s of %s in 24 game hours (BVAD %.3f per day) and %.4f in one sol (BVAD x %.4f = %.4f)" % [float(r[1]), r[4], r[0], per_day, float(r[2]), sol, per_day * sol],
			snappedf(float(r[1]), 0.001) == snappedf(per_day, 0.001) and absf(float(r[2]) - per_day * sol) < 1e-6, str(r))
	_check("NASA (S20): the BVAD values in the code are the published ones (0.895 O2, 1.085 CO2, 4.48 water, 12.778 MJ, 1.56 kg food)",
		GameBalance.NASA_O2_KG_PER_CREW_DAY == 0.895 and GameBalance.NASA_CO2_KG_PER_CREW_DAY == 1.085 and GameBalance.NASA_WATER_KG_PER_CREW_DAY == 4.48
		and GameBalance.NASA_FOOD_MJ_PER_CREW_DAY == 12.778 and GameBalance.NASA_FOOD_KG_PER_CREW_DAY == 1.56)
	_check("NASA (S20): a meal holds %.0f kcal and %.3f kg; 3 meals per sol are %.0f kcal (BVAD 3,054 kcal per day x %.4f)" % [b.meal_kcal(), b.meal_kg(), 3.0 * b.meal_kcal(), sol],
		absf(b.meal_kcal() - 1046.0) < 1.0 and absf(b.meal_kg() - 0.534) < 0.001)
	# the per-game-hour rates are per GAME hour: a faster sol must not change what one sol uses
	var rates_ok := absf(b.oxygen_kg_per_hour * 24.0 - 0.895) < 1e-12 and absf(b.co2_kg_per_hour * 24.0 - 1.085) < 1e-12 and absf(b.water_l_per_hour * 24.0 - 4.48) < 1e-12
	var clock := SolClock.new()
	clock.sol_minutes = 5.0
	var fast := clock.hours_per_real_second()
	clock.sol_minutes = 120.0
	var slow := clock.hours_per_real_second()
	_check("time base: rates are NASA per day / 24 per GAME hour; a sol is %.4f game hours whether it lasts 5 or 120 real minutes (%.4f vs %.4f game h per real s)" % [GameConfig.SOL_HOURS, fast, slow],
		rates_ok and absf(fast * 5.0 * 60.0 - GameConfig.SOL_HOURS) < 1e-9 and absf(slow * 120.0 * 60.0 - GameConfig.SOL_HOURS) < 1e-9)
