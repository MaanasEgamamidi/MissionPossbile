extends SceneTree
## Rover economy, salvage supply and the garage (Prompt 10, part 1). Headless, no game scene: the real GameServices
## with the real map catalogue, ticked by hand. Every PASS is measured on the running model: stations and their
## reach, the donor data and the supply/demand table, the stat curves and energy model, assembly and refits (custom
## builds, unaffordable, all stats to 5, battery kept or clamped, cargo limits, stale/duplicate/replayed requests),
## the assembly check (wrong answer -> new example, no penalty), seats (four riders, a fifth refused, disconnect and
## recovery free seats, exits, suits), cargo loading, charging against the colony battery ledger and its reserve,
## drive accounting, save/load of every rover field, and both station panels at three screen sizes.
## Synthetic parts are said so: a test-only fifth character, positions set by hand, parts given by hand where a test
## needs "enough parts", and power_deficit set by hand for one direct system step.
## Run: ..\godot.cmd --headless --path . --script res://tests/test_rover.gd


## Collects engine and script errors raised while the test runs.
class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR or error_type == ERROR_TYPE_SCRIPT:
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


const SIZES := [[Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 1.0], [Vector2i(1280, 720), 1.5]]
const GARAGE := &"sf_print_garage"
const CHARGER := &"garage_charger"
const ORIGINAL_DONORS: Array[String] = ["ls_filter_old", "pr_bat_rack_alarm", "pr_swgr_burnt", "cr_console_alarm", "sf_crash_tank"]
const NEW_DONORS: Array[String] = ["sf_crash_stage", "sf_crash_shield", "sf_crash_debris_a", "sf_crash_debris_b", "sf_crash_debris_c",
	"pr_bat_hv_alarm", "pr_bat_rack_alarm.001", "pr_bat_rack_alarm.002", "gr_rack_fault"]
## The communications cards P11 adds (1, 2, 3, 4 parts). Used only while they are not in data/upgrades.json yet.
const COMMS_COSTS_UNTIL_P11 := [1, 2, 3, 4]
const FIELD := &"crew_4"

var _passed := 0
var _total := 0
var _catcher := ErrorCatcher.new()
var services: GameServices
var _boxes: Array = []


func _initialize() -> void:
	OS.add_logger(_catcher)
	PlayerInput.ensure_actions()
	services = GameServices.new()
	services.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/rover"), "colony", 2)
	root.add_child(services)
	services.start_new_game(7)
	await _frames()
	services.set_process(false)          # ticks only by hand
	_tick()

	_test_stations()
	_test_reach()
	_test_donors()
	_test_supply_table()
	_test_sources()
	_test_model()
	_test_energy()
	_test_assemble_rules()
	_test_challenge_and_assemble()
	_test_refit_economy()
	_test_all_five()
	_test_battery_refits()
	_test_cargo()
	await _test_save_load()
	_test_seats()
	_test_exit_and_suit()
	_test_charging()
	_test_note_driven()
	await _test_panels()
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


func st() -> ColonyState:
	return services.state()


func me() -> CharacterState:
	return services.local_character()


func _pos(id: String) -> Vector3:
	return CharacterState._v3(st().stations[id].position)


func _at(id: String) -> void:
	me().position = _pos(id)


## The local player stands beside the rover (2.4 m to its side, within reach).
func _by_rover() -> void:
	me().position = RoverModel.pose_position(st()) + RoverModel.pose_quat(st()) * Vector3(2.4, 0.0, 0.0)


## Hands the local player over to crew member `id` (the old one is walked to the hub first).
func _become(id: StringName) -> void:
	if me() != null and me().id == id:
		return
	if me() != null:
		RoverSystem.free_seat_of(st(), String(me().id))
		me().position = me().hub_spot
	services.session.request(&"claim_character", id)


func _req(action: StringName, target: StringName, params := {}) -> ActionResult:
	return services.session.request(action, target, params)


func _tick(n := 1) -> void:
	for i in n:
		services.session.advance(1.0 / services.config.sim_tick_hz)


## Runs the model for `hours` game hours in steps of `dt` (bigger than the real tick, same model).
func _hours(hours: float, dt := 0.05) -> void:
	var s := services.session
	var t := 0.0
	while t < hours - 1e-9:
		var h := minf(dt, hours - t)
		var phase_before := s.clock.phase
		var got := s.clock.advance(h / s.clock.hours_per_real_second())
		for id: StringName in s.sim.step(s.state, s.balance, phase_before, got):
			s.recover_character(id)
		t += h


## Request params for `levels` with the right answers to the assembly check (one stat's check answer made wrong when `wrong_stat` is set).
func _answers(levels: Dictionary, wrong_stat := "") -> Dictionary:
	var ch := RoverModel.challenge(st(), levels)
	var ans := {}
	for step: Dictionary in ch.steps:
		var mi := 0
		var mods: Array = step.modules
		for i in mods.size():
			if bool((mods[i] as Dictionary).ok):
				mi = i
		var a := {"module": mi, "port": String(step.port), "check": int(step.answer)}
		if String(step.stat) == wrong_stat:
			a["check"] = (int(step.answer) + 1) % 3
		ans[String(step.stat)] = a
	return RoverModel.build_params(levels, ch, ans)


## A copy of `d` with `key` set to `value`.
func _with(d: Dictionary, key: String, value: Variant) -> Dictionary:
	var out := d.duplicate(true)
	out[key] = value
	return out


## As the field engineer at the garage: assemble or refit to `levels` with the right answers.
func _build(levels: Dictionary, wrong_stat := "") -> ActionResult:
	_become(FIELD)
	_at(String(GARAGE))
	var action := &"rover_refit" if bool(st().rover.built) else &"rover_assemble"
	return _req(action, GARAGE, _answers(levels, wrong_stat))


func _levels(speed: int, torque: int, range_level: int, cargo: int, traction: int) -> Dictionary:
	return {"speed": speed, "torque": torque, "range": range_level, "cargo": cargo, "traction": traction}


func _park() -> void:
	var g := RoverModel.geometry()
	var p: Vector3 = g.park_position
	var q: Quaternion = g.park_quat
	RoverSystem.note_pose(st(), {"position": [p.x, p.y, p.z], "quat": [q.x, q.y, q.z, q.w]})


func _move_rover(p: Vector3) -> void:
	var q := RoverModel.pose_quat(st())
	RoverSystem.note_pose(st(), {"position": [p.x, p.y, p.z], "quat": [q.x, q.y, q.z, q.w]})


func _empty_pack(c: CharacterState) -> void:
	for id: StringName in c.cargo.duplicate():
		st().items.erase(String(id))
	c.cargo.clear()


func _new_crate(holder: CharacterState) -> String:
	var n := int(st().counters.get("test_crate", 0)) + 1
	st().counters["test_crate"] = n
	var id := "test_crate_%d" % n
	var p := holder.position
	st().items[id] = {"kind": "supply_crate", "position": [p.x, p.y, p.z], "holder": String(holder.id)}
	holder.cargo.append(StringName(id))
	return id


## Plain JSON text of a value as a save holds it (numbers as JSON numbers, keys sorted, full precision).
func _norm(v: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v, "", true, true)), "", true, true)


func _snap() -> Dictionary:
	return {"battery": st().store(&"battery_kwh"), "rover": float(st().rover.battery_kwh), "ledger": st().ledger.duplicate()}


func _ld(start: Dictionary, key: String) -> float:
	return float(st().ledger.get(key, 0.0)) - float((start.ledger as Dictionary).get(key, 0.0))


## Colony battery: now - start - (in - loss - out - rover_charge); rover battery: now - start - (charge - loss - drive - clamp).
func _identities(start: Dictionary) -> Dictionary:
	var colony := (st().store(&"battery_kwh") - float(start.battery)) - (_ld(start, "battery_in_kwh") - _ld(start, "battery_loss_kwh")
		- _ld(start, "battery_out_kwh") - _ld(start, "rover_charge_kwh"))
	var rover := (float(st().rover.battery_kwh) - float(start.rover)) - (_ld(start, "rover_charge_kwh") - _ld(start, "rover_charge_loss_kwh")
		- _ld(start, "rover_drive_kwh") - _ld(start, "rover_refit_clamped_kwh"))
	return {"colony": colony, "rover": rover}


# ---------------------------------------------------------------- stations

func _test_stations() -> void:
	var g: Dictionary = st().stations.get(String(GARAGE), {})
	var c: Dictionary = st().stations.get(String(CHARGER), {})
	_check("stations: the garage station is on the map's print garage, the charger beside it, both outside",
		String(g.get("kind", "")) == "garage" and String(c.get("kind", "")) == "rover_charger"
		and String(g.get("zone", "")) == ColonyZones.EXTERIOR and String(c.get("zone", "")) == ColonyZones.EXTERIOR, str(g) + str(c))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameServices.MANIFEST_PATH))
	var rover_obj := {}
	var garage_obj := {}
	for o: Dictionary in manifest.objects:
		if String(o.name) == "sf_rover":
			rover_obj = o
		elif String(o.name) == "sf_print_garage":
			garage_obj = o
	var rp := Vector3(float(rover_obj.matrix_world[0][3]), float(rover_obj.matrix_world[2][3]), -float(rover_obj.matrix_world[1][3]))
	var gp := Vector3(float(garage_obj.matrix_world[0][3]), float(garage_obj.matrix_world[2][3]), -float(garage_obj.matrix_world[1][3]))
	var b := RoverBalance.get_current()
	_check("map: the drivable rover sf_rover stands in sf_print_garage (fallback park pose = its origin)",
		rp.distance_to(b.park_position) < 0.01 and Vector2(rp.x - gp.x, rp.z - gp.z).length() < 0.5, "%s %s" % [rp, gp])
	_check("map: the parked rover is in the garage and within the charger's cable reach",
		RoverSystem.in_garage(st()) and RoverSystem.in_charge_reach(st()) and RoverSystem.rover_distance_to_station(st(), String(CHARGER)) < 4.0,
		"garage %.2f m, charger %.2f m" % [RoverSystem.rover_distance_to_station(st(), String(GARAGE)), RoverSystem.rover_distance_to_station(st(), String(CHARGER))])
	var gp_panel := StationPanels.for_station(GARAGE, services)
	var cp_panel := StationPanels.for_station(CHARGER, services)
	_check("stations: their panels come from scripts/ui/stations/<kind>_station_panel.gd",
		gp_panel is GarageStationPanel and cp_panel is RoverChargerStationPanel and StationPanels.name_of("garage") == "Rover garage"
		and StationPanels.name_of("rover_charger") == "Rover charger" and StationPanels.symbol_of("garage") != "●")
	if gp_panel != null:
		gp_panel.free()
	if cp_panel != null:
		cp_panel.free()
	RoverModel.ensure(st())
	_check("new game: no rover yet, empty battery, four empty seats, parked at the garage",
		not bool(st().rover.built) and float(st().rover.battery_kwh) == 0.0 and (st().rover.seats as Array) == ["", "", "", ""]
		and RoverModel.pose_position(st()).distance_to(b.park_position) < 0.01)


## Every new station has a standing spot within 2.3 m (interact distance 2.6 m) that is clear of every map collision
## box (a 0.35 m body radius, at 0.3, 0.9 and 1.5 m height); outdoor ones stand on the height grid.
func _test_reach() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameServices.MANIFEST_PATH))
	var colliders: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/colliders.json")) as Dictionary).get("assets", {})
	for o: Dictionary in manifest.objects:
		var xf := _object_xf(o.matrix_world)
		for c: Dictionary in (colliders.get(String(o.get("gc_asset", "")), {}) as Dictionary).get("cols", []):
			var q: Array = c.q
			var local := Transform3D(Basis(Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3]))), Vector3(float(c.c[0]), float(c.c[1]), float(c.c[2])))
			_boxes.append({"name": String(o.name), "inv": (xf * local).affine_inverse(), "h": Vector3(float(c.h[0]), float(c.h[1]), float(c.h[2]))})
	var height := load("res://data/terrain_height.res") as TerrainHeight
	var problems := PackedStringArray()
	var lines := PackedStringArray()
	for id: String in [String(GARAGE), String(CHARGER)] + NEW_DONORS:
		var p := _pos(id)
		var nearest := INF
		for ri in 12:
			var rad := 0.2 * float(ri)
			for ai in 24:
				var a := TAU * float(ai) / 24.0
				var s := p + Vector3(cos(a) * rad, 0.0, sin(a) * rad)
				if rad <= 2.3 and rad < nearest and _clear(s):
					nearest = rad
		var ground_ok := true
		if String(st().stations[id].zone) == ColonyZones.EXTERIOR:
			ground_ok = height != null and absf(height.height_at(p.x, p.z) - p.y) <= 0.15
		lines.append("%s: clear spot %s m away%s" % [id, "none" if nearest == INF else String.num(nearest, 1), "" if ground_ok else ", NOT on the ground"])
		if nearest == INF or not ground_ok:
			problems.append(lines[lines.size() - 1])
	_check("reach: the garage, the charger and the 9 new donors each have a clear standing spot within reach (on the ground outside)",
		problems.is_empty(), "; ".join(problems))
	print("  " + "\n  ".join(lines))


func _clear(s: Vector3) -> bool:
	for b: Dictionary in _boxes:
		var inv: Transform3D = b.inv
		var h: Vector3 = b.h
		for y: float in [0.3, 0.9, 1.5]:
			var l := inv * (s + Vector3(0.0, y, 0.0))
			if absf(l.x) < h.x + 0.35 and absf(l.y) < h.y + 0.05 and absf(l.z) < h.z + 0.35:
				return false
	return true


## Blender matrix_world -> Godot transform: v -> (x, z, -y) for both the axes and the origin.
func _object_xf(m: Array) -> Transform3D:
	var bx := Vector3(float(m[0][0]), float(m[1][0]), float(m[2][0]))
	var by := Vector3(float(m[0][1]), float(m[1][1]), float(m[2][1]))
	var bz := Vector3(float(m[0][2]), float(m[1][2]), float(m[2][2]))
	return Transform3D(Basis(Vector3(bx.x, bx.z, -bx.y), Vector3(bz.x, bz.z, -bz.y), -Vector3(by.x, by.z, -by.y)),
		Vector3(float(m[0][3]), float(m[2][3]), -float(m[1][3])))


func _test_donors() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameServices.MANIFEST_PATH))
	var names := {}
	for o: Dictionary in manifest.objects:
		names[String(o.name)] = true
	var donors: Array = ScienceActions.salvage_data().get("donors", [])
	var first: Array = []
	for i in mini(5, donors.size()):
		first.append(String((donors[i] as Dictionary).object))
	_check("donors: the five P08 donors are still first and unchanged in salvage.json", first == ORIGINAL_DONORS, str(first))
	var bad := PackedStringArray()
	for d: String in NEW_DONORS:
		var info := ScienceActions.donor_info(d)
		var good := 0
		var badp := 0
		var clues := true
		for p: Dictionary in info.get("parts", []):
			if bool(p.get("compatible", false)):
				good += 1
				clues = clues and String(p.get("fits", "")) != "" and String(p.get("test", "")).contains("illustrative")
			else:
				badp += 1
			clues = clues and String(p.get("clue", "")).length() > 10
		var station: Dictionary = st().stations.get(d, {})
		if not names.has(d) or info.is_empty() or good < 2 or badp < 2 or not clues or String(station.get("kind", "")) != "salvage":
			bad.append("%s (in map %s, compatible %d, not %d, clues %s, station %s)" % [d, names.has(d), good, badp, clues, station.get("kind", "-")])
	_check("donors: 9 new donors are existing map objects with a salvage station, 2+ compatible and 2+ unusable parts with clues",
		bad.is_empty(), "; ".join(bad))
	var salvage_stations := 0
	for id: String in st().stations:
		if String(st().stations[id].kind) == "salvage":
			salvage_stations += 1
	_check("donors: 14 salvage stations, one per donor in salvage.json", salvage_stations == 14 and donors.size() == 14, "%d %d" % [salvage_stations, donors.size()])
	# a new donor works in the real P08 flow: inspect, recover once, refurbish, bench test -> exactly one spare part
	_become(FIELD)
	_empty_pack(me())
	_at("sf_crash_stage")
	var r1 := _req(&"inspect_donor", &"sf_crash_stage", {"choice": "bearing"})
	var r2 := _req(&"recover_part", &"sf_crash_stage", {"part": "bearing"})
	var r3 := _req(&"recover_part", &"sf_crash_stage", {"part": "nozzle"})
	var item := String(r2.changes.get("item", "")) if r2.ok else ""
	_at("hg_control_board")
	var parts := st().parts
	var rf := _req(&"refurbish", &"hg_control_board", {"item": item})
	_hours(ScienceActions.refurbish_hours(st()) + 0.1)
	var bt := _req(&"bench_test", &"hg_control_board", {"job": String(rf.changes.get("job", ""))})
	_check("donors: a new donor gives a part through the P08 flow (inspect, recover, refurbish, bench test: +1 spare part); an unusable part is refused",
		r1.ok and bool(r1.changes.fits) and r2.ok and not r3.ok and r3.reason == &"wrong_target" and rf.ok and bt.ok and st().parts == parts + 1,
		"%s %s %s %s %s parts %d->%d" % [r1.reason, r2.reason, r3.reason, rf.reason, bt.reason, parts, st().parts])
	st().parts = parts           # back to the start count for the economy tests below


func _test_supply_table() -> void:
	var table: Dictionary = ((JSON.parse_string(FileAccess.get_file_as_string("res://data/model_sources_rover.json")) as Dictionary).get("supply_demand", {}))
	var sb := ScienceBalance.new()
	var donors: Array = ScienceActions.salvage_data().get("donors", [])
	var listed := 0
	var base := 0
	var upgraded := 0
	for d: Dictionary in donors:
		var good := 0
		for p: Dictionary in d.get("parts", []):
			if bool(p.get("compatible", false)):
				good += 1
		listed += good
		base += mini(good, sb.parts_per_donor)
		upgraded += mini(good, sb.parts_per_donor_upgraded)
	var start := GameBalance.new().parts_start
	var cards: Array = (JSON.parse_string(FileAccess.get_file_as_string("res://data/upgrades.json")) as Dictionary).get("cards", [])
	var facility := 0
	var comms := 0
	var comms_found := 0
	var comms_first := 0
	for c: Dictionary in cards:
		if String(c.id).begins_with("comms_radio_"):
			comms += int(c.get("cost_parts", 0))
			comms_found += 1
			if String(c.id) == "comms_radio_1":
				comms_first = int(c.get("cost_parts", 0))
		else:
			facility += int(c.get("cost_parts", 0))
	if comms_found == 0:
		for v: int in COMMS_COSTS_UNTIL_P11:
			comms += v
		comms_first = COMMS_COSTS_UNTIL_P11[0]
	var rover := RoverModel.invested(_levels(5, 5, 5, 5, 5))
	var supply_max := start + upgraded
	var demand := facility + comms + rover
	var want := {"start_parts": start, "donors": donors.size(), "compatible_parts_listed": listed, "recoverable_base": base,
		"recoverable_with_refurbishment": upgraded, "supply_base": start + base, "supply_max": supply_max, "demand_facility_cards": facility,
		"demand_comms_cards": comms, "demand_rover_all_level_5": rover, "demand_total": demand, "required_for_campaign": comms_first,
		"shortfall_total": maxi(0, demand - supply_max)}
	var diff := PackedStringArray()
	for k: String in want:
		if int(table.get(k, -1)) != int(want[k]):
			diff.append("%s: table %s, data %s" % [k, str(table.get(k, "-")), str(want[k])])
	_check("supply/demand: every number of the table in model_sources_rover.json matches the data files", diff.is_empty(), "; ".join(diff))
	_check("supply/demand: the shortfall is flagged (a fully upgraded rover is not reachable from approved map salvage), the campaign needs %d part" % comms_first,
		bool(table.get("rover_max_reachable", true)) == (supply_max >= rover) and String(table.get("flag", "")).begins_with("SHORTFALL")
		and comms_first <= start, str(table.get("rover_max_reachable")))
	print("  supply: start %d + recovered %d (base) / %d (with the refurbishing jig) = %d / %d; listed compatible %d" % [start, base, upgraded, start + base, supply_max, listed])
	print("  demand: facility cards %d + comms %d%s + rover %d = %d; shortfall %d" % [facility, comms, "" if comms_found > 0 else " (P11 values, until P11 merges)", rover, demand, demand - supply_max])


func _test_sources() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/model_sources_rover.json"))
	var register := FileAccess.get_file_as_string("res://docs/source_register.md")
	var allowed := ["fictional", "balance", "map", "S01", "index"]
	var missing := PackedStringArray()
	if data is Dictionary:
		for p: Dictionary in RoverBalance.new().get_property_list():
			if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and String(p.name) != "current":
				var e: Variant = (data as Dictionary).get(String(p.name))
				if not (e is Dictionary) or not allowed.has(String((e as Dictionary).get("category", ""))):
					missing.append(String(p.name))
		for key: String in data:
			for sid: Variant in ((data as Dictionary)[key] as Dictionary).get("source_ids", []):
				if not register.contains("| %s |" % String(sid)):
					missing.append("%s cites %s, not in the register" % [key, sid])
	_check("sources: every RoverBalance field has a category in model_sources_rover.json; every cited id is in the register",
		data is Dictionary and missing.is_empty(), ", ".join(missing))
	_check("sources: Mars gravity is the register's S01 value (3.73 m/s²) and the curves are labelled fictional, not NASA data",
		RoverBalance.MARS_GRAVITY == 3.73 and register.contains("3.73 m/s²") and String((data as Dictionary)["top_speed_mps"].category) == "fictional"
		and String((data as Dictionary)["_about"].note).contains("NOT NASA measurements"))


# ---------------------------------------------------------------- model

func _test_model() -> void:
	_check("costs: the steps cost 1, 2, 3, 4 parts; one stat to 5 costs 10, all five 50",
		[RoverModel.step_cost(1), RoverModel.step_cost(2), RoverModel.step_cost(3), RoverModel.step_cost(4)] == [1, 2, 3, 4]
		and RoverModel.invested(_levels(5, 1, 1, 1, 1)) == 10 and RoverModel.invested(_levels(5, 5, 5, 5, 5)) == 50 and RoverModel.invested({}) == 0)
	var mono := true
	var keys := {"speed": "top_speed_mps", "torque": "drive_force_n", "range": "battery_capacity_kwh", "cargo": "cargo_capacity_kg", "traction": "traction_mu"}
	for s: String in RoverModel.STATS:
		var prev := -INF
		for l in range(1, 6):
			var lv := _levels(1, 1, 1, 1, 1)
			lv[s] = l
			var v := float(RoverModel.stats(lv, 0.0)[keys[s]])
			mono = mono and v > prev
			prev = v
	_check("stats: each slider raises its own stat at every level (speed, push, battery, cargo, grip)", mono)
	var base := RoverModel.stats(_levels(1, 1, 1, 1, 1), 0.0)
	var big_cargo := RoverModel.stats(_levels(1, 1, 1, 5, 1), 0.0)
	_check("stats: the cargo slider changes cargo capacity only, never the four seats",
		RoverModel.SEATS == 4 and not big_cargo.has("seats") and float(big_cargo.cargo_capacity_kg) > float(base.cargo_capacity_kg)
		and float(big_cargo.top_speed_mps) == float(base.top_speed_mps))
	var loaded := RoverModel.stats(_levels(1, 1, 1, 1, 1), 100.0)
	_check("stats: real cargo changes the forecasts (range, pulling away, slope) without changing the levels' stats",
		float(loaded.range_km) < float(base.range_km) and float(loaded.accel_mps2) < float(base.accel_mps2) and float(loaded.max_slope_deg) < float(base.max_slope_deg)
		and float(loaded.top_speed_mps) == float(base.top_speed_mps) and float(loaded.cargo_capacity_kg) == float(base.cargo_capacity_kg))
	var half := RoverModel.stats(_levels(1, 1, 1, 1, 1), 0.0, 10.0, 2)
	var per_km := float(half.kwh_per_km)
	_check("range: honest = stored energy / (kWh per km x terrain factor), with the crew and cargo aboard (%.2f km from 10 kWh)" % float(half.range_km),
		absf(float(half.range_km) - 10.0 / (per_km * RoverBalance.get_current().range_terrain_factor)) < 1e-9
		and float(RoverModel.stats(_levels(1, 1, 1, 1, 1), 0.0, 10.0, 4).range_km) < float(half.range_km))
	_check("stats: more torque climbs steeper, more grip allows a steeper slope before slipping",
		float(RoverModel.stats(_levels(1, 5, 1, 1, 5), 0.0).max_slope_deg) > float(base.max_slope_deg))


func _test_energy() -> void:
	var lv := _levels(1, 1, 1, 1, 1)
	var flat := RoverModel.energy_kwh_for_move(lv, 0.0, 100.0, 0.0, 1)
	var cargo := RoverModel.energy_kwh_for_move(lv, 100.0, 100.0, 0.0, 1)
	var climb := RoverModel.energy_kwh_for_move(lv, 0.0, 100.0, 5.0, 1)
	var down := RoverModel.energy_kwh_for_move(lv, 0.0, 100.0, -5.0, 1)
	var crew := RoverModel.energy_kwh_for_move(lv, 0.0, 100.0, 0.0, 4)
	var b := RoverBalance.get_current()
	var m := b.chassis_mass_kg + b.crew_member_kg
	var expect := (b.rolling_resistance * m * 3.73 * 100.0 * b.map_distance_factor + m * 3.73 * 5.0 * b.map_distance_factor) / b.drivetrain_efficiency / 3.6e6
	_check("energy: more with cargo, more with crew, more on a climb (m g h at Mars g); downhill recovers nothing",
		cargo > flat and crew > flat and climb > flat and is_equal_approx(down, flat) and RoverModel.energy_kwh_for_move(lv, 0.0, 0.0, 0.0, 1) == 0.0,
		"flat %.4f cargo %.4f crew %.4f climb %.4f down %.4f" % [flat, cargo, crew, climb, down])
	_check("energy: c m g d + m g h over the drivetrain efficiency, with the map distance factor (%.4f kWh)" % climb, absf(climb - expect) < 1e-9, "%.6f vs %.6f" % [climb, expect])


# ---------------------------------------------------------------- assembly and refits

func _test_assemble_rules() -> void:
	var lv := _levels(1, 1, 1, 1, 1)
	_become(&"crew_1")
	_at(String(GARAGE))
	var wrong := _req(&"rover_assemble", GARAGE, _answers(lv))
	_become(FIELD)
	me().position = _pos(String(GARAGE)) + Vector3(0.0, 0.0, 5.0)
	var far := _req(&"rover_assemble", GARAGE, _answers(lv))
	_at(String(CHARGER))
	var at_charger := _req(&"rover_assemble", CHARGER, _answers(lv))
	_check("assemble: refused for the wrong specialist, from too far away and at the wrong station",
		not wrong.ok and wrong.reason == &"wrong_specialty" and not far.ok and far.reason == &"too_far" and not at_charger.ok and at_charger.reason == &"wrong_target",
		"%s %s %s" % [wrong.reason, far.reason, at_charger.reason])
	_at(String(GARAGE))
	var refit_first := _req(&"rover_refit", GARAGE, _answers(lv))
	var bad_level := _req(&"rover_assemble", GARAGE, _with(_answers(lv), "speed", 6))
	var bad_stat := _req(&"rover_assemble", GARAGE, _with(_answers(lv), "seats", 5))
	var no_check := _req(&"rover_assemble", GARAGE, _with(_answers(lv), "answers", ""))
	_check("assemble: a refit before the build, a level of 6, an unknown stat and missing check answers are refused; nothing changed",
		not refit_first.ok and not bad_level.ok and bad_level.reason == &"bad_request" and not bad_stat.ok and not no_check.ok
		and not bool(st().rover.built) and st().parts == 10, "%s %s %s %s" % [refit_first.reason, bad_level.reason, bad_stat.reason, no_check.reason])


## Each step has 3 modules (exactly one fits), 3 sockets (one right) and 3 different check answers.
func _steps_well_formed(steps: Array) -> bool:
	for x: Dictionary in steps:
		var mods: Array = x.modules
		var ports: Array = x.ports
		var opts: Array = x.options
		var fits := 0
		for m: Dictionary in mods:
			if bool(m.ok):
				fits += 1
		var port_ok := false
		for p: Dictionary in ports:
			port_ok = port_ok or String(p.id) == String(x.port)
		var distinct: bool = opts.size() == 3 and opts[0] != opts[1] and opts[1] != opts[2] and opts[0] != opts[2]
		if mods.size() != 3 or ports.size() != 3 or fits != 1 or not port_ok or not distinct or int(x.answer) < 0 or int(x.answer) > 2:
			return false
	return not steps.is_empty()


func _test_challenge_and_assemble() -> void:
	var custom := _levels(2, 1, 3, 1, 2)          # 1 + 3 + 1 = 5 parts, not one of the examples
	var ch1 := RoverModel.challenge(st(), custom)
	var ch1b := RoverModel.challenge(st(), custom)
	var stats1 := PackedStringArray()
	for s: Dictionary in ch1.steps:
		stats1.append(String(s.stat))
	_check("challenge: deterministic, covers the changed modules (biggest change first, at most 3), each with 3 modules, 3 sockets and 3 answers",
		JSON.stringify(ch1) == JSON.stringify(ch1b) and stats1 == PackedStringArray(["range", "speed", "traction"])
		and _steps_well_formed(ch1.steps), str(stats1))
	var other := RoverModel.challenge(st(), _levels(1, 3, 1, 3, 1))
	var other_stats := PackedStringArray()
	for s: Dictionary in other.steps:
		other_stats.append(String(s.stat))
	_check("challenge: different stats give different modules and checks", other_stats != stats1 and JSON.stringify(other.steps[0]) != JSON.stringify(ch1.steps[0]), str(other_stats))
	var is_example := false
	for e: Array in GarageStationPanel.EXAMPLES:
		var lv := _levels(1, 1, 1, 1, 1)
		for k: String in e[1]:
			lv[k] = int(e[1][k])
		is_example = is_example or lv == custom
	# a wrong answer: feedback, a changed example, no penalty
	var wrong := _build(custom, "range")
	var ch2 := RoverModel.challenge(st(), custom)
	var changed := false
	for i in ch2.steps.size():
		changed = changed or String(ch2.steps[i].question) != String(ch1.steps[i].question) or JSON.stringify(ch2.steps[i].modules) != JSON.stringify(ch1.steps[i].modules)
	_check("challenge: a wrong check answer explains why, changes nothing, costs nothing and gives a changed example",
		wrong.ok and not bool(wrong.changes.assembled) and (wrong.changes.feedback as Dictionary).has("range") and not bool(st().rover.built)
		and st().parts == 10 and int(st().rover.challenge_variant) == 1 and changed and String(wrong.changes.text).contains("new example"),
		"%s %s" % [wrong.reason, wrong.changes])
	var stale := _req(&"rover_assemble", GARAGE, _with(_answers(custom), "variant", 0))
	_check("challenge: answers to the old example are refused as out of date", not stale.ok and stale.reason == &"missing_prerequisite", String(stale.reason))
	var ok := _build(custom)
	_check("assemble: a custom build beyond any example (speed 2, battery 3, traction 2) costs exactly 5 parts after the check",
		ok.ok and bool(ok.changes.assembled) and not is_example and bool(st().rover.built) and st().parts == 5 and RoverModel.clean_levels(st().rover.levels) == custom
		and int(st().rover.refit_seq) == 1 and int(st().rover.challenge_variant) == 0 and float(st().ledger.get("rover_parts_net", 0.0)) == 5.0, str(ok.changes))
	_check("assemble: the first build creates no energy (the battery is empty until charged) and records evidence res_rover_assembly once",
		float(st().rover.battery_kwh) == 0.0 and st().evidence.has("res_rover_assembly") and bool(ok.changes.evidence) and String(ok.changes.text).contains("charge"))
	var again := _req(&"rover_assemble", GARAGE, _answers(custom))
	_check("assemble: a second assembly is refused (use refit)", not again.ok and again.reason == &"missing_prerequisite")


func _test_refit_economy() -> void:
	var now := RoverModel.clean_levels(st().rover.levels)
	var huge := _levels(5, 5, 5, 5, 5)
	var r := _build(huge)
	_check("refit: an unaffordable change is refused with the numbers, and nothing changes",
		not r.ok and r.reason == &"insufficient" and r.message.contains("45") and r.message.contains("5") and RoverModel.clean_levels(st().rover.levels) == now and st().parts == 5,
		r.message)
	var same := _build(now)
	_check("refit: a plan equal to the rover is refused (nothing to change)", not same.ok and same.reason == &"missing_prerequisite")
	# a refit that lowers the battery gives its parts back, exactly once
	var lower := _levels(2, 1, 1, 1, 2)
	_become(FIELD)
	_at(String(GARAGE))
	var req := ActionRequest.make("refit-lower", SessionService.HOST_PEER, FIELD, &"rover_refit", GARAGE, _answers(lower))
	var first := services.session.submit(req)
	var parts_after := st().parts
	var dup := services.session.submit(req)
	_check("refit: lowering the battery 3 -> 1 gives back its 3 parts; the same request again is a duplicate and gives nothing",
		first.ok and bool(first.changes.assembled) and int(first.changes.parts) == -3 and parts_after == 8 and dup.duplicate and st().parts == 8,
		"%s %s parts %d" % [first.changes, dup.duplicate, st().parts])
	# a request with a new id but the old transaction number is refused (no replayed refund)
	var replay := services.session.submit(ActionRequest.make("refit-lower-replay", SessionService.HOST_PEER, FIELD, &"rover_refit", GARAGE, req.params))
	_check("refit: replaying the refund under a new request id is refused (its transaction number is used)",
		not replay.ok and replay.reason == &"missing_prerequisite" and st().parts == 8 and int(st().rover.refit_seq) == 2, String(replay.reason))
	# raise it back: refits fully reuse invested parts (3 parts again)
	var back := _build(_levels(2, 1, 3, 1, 2))
	_check("refit: raising the battery again uses the same 3 parts (refits fully reuse invested parts)", back.ok and int(back.changes.parts) == 3 and st().parts == 5)
	# the rover must be in the garage and empty
	_move_rover(RoverModel.pose_position(st()) + Vector3(0.0, 0.0, 15.0))
	var away := _build(_levels(3, 1, 3, 1, 2))
	_park()
	_check("refit: refused when the rover is away from the garage", not away.ok and away.message.contains("garage"), away.message)


func _test_all_five() -> void:
	var before := st().parts
	var invested_now := RoverModel.invested(st().rover.levels)
	st().parts = before + (50 - invested_now)          # test setup: "enough parts" for all five at level 5
	var steps := [_levels(3, 3, 3, 3, 3), _levels(4, 4, 4, 4, 4), _levels(5, 5, 5, 5, 5)]
	var ok := true
	for lv: Dictionary in steps:
		var r := _build(lv)
		ok = ok and r.ok and bool(r.changes.assembled)
	_check("refit: with enough parts all five stats reach level 5, exactly 50 parts invested, no hidden cap",
		ok and RoverModel.clean_levels(st().rover.levels) == _levels(5, 5, 5, 5, 5) and RoverModel.invested(st().rover.levels) == 50
		and st().parts == before and float(st().ledger.rover_parts_net) == 50.0, "parts %d, ledger %s" % [st().parts, str(st().ledger.get("rover_parts_net"))])
	var all_seats := (st().rover.seats as Array).size() == 4
	_check("refit: four seats in every configuration", all_seats)


func _test_battery_refits() -> void:
	# fill the level-5 battery (56 kWh) for real at the charger; test setup: a well-filled colony battery
	st().rover.battery_kwh = 0.0
	st().stores[&"battery_kwh"] = 790.0
	var start := _snap()
	_become(&"crew_1")
	_at(String(CHARGER))
	var plug := _req(&"rover_set_charging", CHARGER, {"on": true})
	_hours(14.0)
	var full := float(st().rover.battery_kwh)
	_req(&"rover_set_charging", CHARGER, {"on": false})
	_check("charging: the battery fills to its capacity and no further (56 kWh at level 5)", plug.ok and is_equal_approx(full, 56.0) and String(st().rover.charge_status) == "off",
		"%.3f %s" % [full, st().rover.charge_status])
	# downgrade the battery 5 -> 1: clamped to 20 kWh, 36 kWh recorded, no energy created
	var parts := st().parts
	var r := _build(_levels(5, 5, 1, 5, 5))
	_check("refit: a smaller battery keeps only what fits (56 -> 20 kWh) and records the 36 kWh that left with the modules",
		r.ok and is_equal_approx(float(st().rover.battery_kwh), 20.0) and is_equal_approx(float(r.changes.clamped_kwh), 36.0) and st().parts == parts + 10
		and is_equal_approx(_ld(start, "rover_refit_clamped_kwh"), 36.0), str(r.changes))
	# upgrade 1 -> 3: the stored energy is kept, never filled
	var r2 := _build(_levels(5, 5, 3, 5, 5))
	_check("refit: a bigger battery keeps the stored energy (20 kWh) and does not fill it", r2.ok and is_equal_approx(float(st().rover.battery_kwh), 20.0)
		and float(RoverModel.stats(st().rover.levels, 0.0).battery_capacity_kwh) == 36.0 and String(r2.changes.text).contains("never fills"), str(r2.changes))
	var ids := _identities(start)
	_check("ledger: colony and rover battery identities hold through charging and refits (worst %s)" % String.num_scientific(maxf(absf(float(ids.colony)), absf(float(ids.rover)))),
		absf(float(ids.colony)) < 1e-6 and absf(float(ids.rover)) < 1e-6, str(ids))


func _test_cargo() -> void:
	# back to a small cargo bay: level 1 holds 100 kg (4 crates of 25 kg)
	var r := _build(_levels(5, 5, 3, 1, 5))
	_become(&"crew_2")
	_empty_pack(me())
	_by_rover()
	var loaded := 0
	var refused: ActionResult = null
	for i in 5:
		var id := _new_crate(me())
		var lr := _req(&"rover_load_cargo", StringName(id))
		if lr.ok:
			loaded += 1
		else:
			refused = lr
	_check("cargo: anyone may load; 4 crates (100 kg) fit the level-1 bay, the 5th is refused as too heavy",
		r.ok and loaded == 4 and refused != null and refused.reason == &"insufficient" and refused.message.contains("100") and is_equal_approx(RoverModel.cargo_mass_kg(st()), 100.0),
		"%d %s" % [loaded, refused.message if refused != null else "-"])
	var aboard: Array = (st().rover.cargo as Array).duplicate()
	var holders_ok := true
	for id: Variant in aboard:
		holders_ok = holders_ok and String((st().items[String(id)] as Dictionary).holder) == "rover"
	var pick := _req(&"pick_up", StringName(String(aboard[0])))
	_check("cargo: loaded items are held by the rover (nobody can pick them off the ground)", holders_ok and not pick.ok and pick.reason == &"already_held")
	# a refit that would strand cargo is refused until it is unloaded (the cargo bay cannot shrink below the load)
	var shrink := _levels(5, 5, 3, 1, 5)
	var grow := _build(_levels(5, 5, 3, 2, 5))
	_become(&"crew_2")
	_by_rover()
	var extra := _new_crate(me())
	_req(&"rover_load_cargo", StringName(extra))
	var strand := _build(shrink)
	_check("cargo: a refit to a cargo bay smaller than the load (125 kg aboard, 100 kg bay) is refused and says to unload",
		grow.ok and not strand.ok and strand.reason == &"insufficient" and strand.message.contains("Unload") and RoverModel.level_of(st().rover.levels, "cargo") == 2, strand.message)
	# loaded items travel with the rover
	_move_rover(RoverModel.pose_position(st()) + Vector3(3.0, 0.0, 4.0))
	_tick()
	var p := RoverModel.pose_position(st())
	var follow := true
	for id: Variant in st().rover.cargo:
		follow = follow and CharacterState._v3(st().items[String(id)].position).distance_to(p) < 1e-4
	_park()
	_tick()
	_check("cargo: loaded items move with the rover's pose (positions saved right)", follow)
	# unload one: into the pack, out of the bay
	_become(&"crew_2")
	_empty_pack(me())
	_by_rover()
	var first_item := String((st().rover.cargo as Array)[0])
	var un := _req(&"rover_unload_cargo", StringName(first_item))
	me().position += Vector3(30.0, 0.0, 0.0)
	var un_far := _req(&"rover_unload_cargo", StringName(String((st().rover.cargo as Array)[0])))
	_check("cargo: unloading puts the item in the actor's pack; from too far it is refused",
		un.ok and me().cargo.has(StringName(first_item)) and String(st().items[first_item].holder) == String(me().id) and not (st().rover.cargo as Array).has(first_item)
		and not un_far.ok and un_far.reason == &"too_far", "%s %s" % [un.reason, un_far.reason])
	_by_rover()
	_req(&"rover_load_cargo", StringName(first_item))


func _test_save_load() -> void:
	# mid-refit: a wrong answer moved the example on; cargo aboard; some energy stored; a trip on the clock
	var plan := _levels(5, 5, 4, 2, 5)
	var wrong := _build(plan, "range")
	RoverSystem.note_driven(st(), services.events, 12.0, 0.5)
	_become(&"crew_2")
	var before: Dictionary = st().rover.duplicate(true)
	var before_text := _norm(st().rover)
	var items_before := {}
	for id: Variant in st().rover.cargo:
		items_before[String(id)] = _norm(st().items[String(id)])
	var ledger_before := {}
	for k: String in ["rover_charge_kwh", "rover_charge_loss_kwh", "rover_drive_kwh", "rover_refit_clamped_kwh", "rover_parts_net"]:
		ledger_before[k] = float(st().ledger.get(k, 0.0))
	var parts := st().parts
	var err := services.save_now(&"test")
	var loaded := services.continue_game()
	await _frames()
	RoverModel.ensure(st())
	var after_text := _norm(st().rover)
	var same_items := true
	for id: String in items_before:
		same_items = same_items and st().items.has(id) and _norm(st().items[id]) == String(items_before[id])
	var same_ledger := true
	for k: String in ledger_before:
		same_ledger = same_ledger and is_equal_approx(float(st().ledger.get(k, 0.0)), float(ledger_before[k]))
	_check("save/load: every rover field (levels, battery, cargo, seats, pose, charging, trip, refit number, example number) comes back the same, mid-refit with cargo aboard",
		err == OK and loaded.is_usable() and wrong.ok and not bool(wrong.changes.assembled) and after_text == before_text
		and same_items and same_ledger and st().parts == parts and int(st().rover.challenge_variant) == int(before.challenge_variant)
		and int(before.challenge_variant) == 1 and not (before.cargo as Array).is_empty(), "%s\n%s" % [before_text, after_text])
	# after the load the host has forgotten request ids: an old refund request (transaction 1) must still refund nothing
	_become(FIELD)
	_at(String(GARAGE))
	var replay := services.session.submit(ActionRequest.make("refit-lower", SessionService.HOST_PEER, FIELD, &"rover_refit", GARAGE,
		_with(_with(_answers(_with(RoverModel.clean_levels(st().rover.levels), "speed", 4)), "seq", 1), "variant", 0)))
	_check("save/load: replaying an old refund request after the load refunds nothing (its transaction number is used)",
		not replay.ok and not replay.duplicate and replay.message.contains("out of date") and st().parts == parts, replay.message)
	var r := _build(plan)
	_check("save/load: the refit goes on after the load with the saved example number", r.ok and bool(r.changes.assembled) and RoverModel.clean_levels(st().rover.levels) == plan, str(r.changes))


# ---------------------------------------------------------------- seats

func _claim_for(peer: int, id: StringName) -> void:
	services.session.peer_joined(peer)
	services.session.request(&"claim_character", id, {}, peer)


## Peer `peer` walks up to the rover (suit on unless `suit` is false: the garage is outside) and asks for `seat`.
func _enter(peer: int, seat: int, suit := true) -> ActionResult:
	var c := st().character_of_peer(peer)
	if c != null:
		c.position = RoverModel.pose_position(st()) + RoverModel.pose_quat(st()) * Vector3(-2.4, 0.0, 0.5)
		c.suit_on = suit
	return services.session.request(&"rover_enter", &"", {"seat": seat}, peer)


func _test_seats() -> void:
	_park()
	_tick()             # the rover system follows the loaded state from its first tick
	_become(&"crew_1")
	for i in RoverModel.SEATS:
		(st().rover.seats as Array)[i] = ""
	_claim_for(2, &"crew_2")
	_claim_for(3, &"crew_3")
	_claim_for(4, &"crew_4")
	var results: Array = []
	for peer in [1, 2, 3, 4]:
		results.append(_enter(peer, peer - 1))
	var all_in := results.all(func(x: ActionResult) -> bool: return x.ok)
	_check("seats: four people ride (driver in seat 0, three passengers), each recorded in rover.seats",
		all_in and (st().rover.seats as Array) == ["crew_1", "crew_2", "crew_3", "crew_4"] and bool((results[0] as ActionResult).changes.driver),
		str(st().rover.seats))
	var seated_pos := st().character(&"crew_3").position.distance_to(RoverModel.seat_world_position(st(), 2)) < 1e-4
	_check("seats: a seated character is placed at its seat", seated_pos)
	# a fifth person: a test-only fifth character controlled by peer 5
	var fifth := CharacterState.new()
	fifth.id = &"crew_5"
	fifth.specialty = &"biology_food"
	fifth.owner_peer = 5
	st().characters[&"crew_5"] = fifth
	var r5 := _enter(5, 2)
	var again := _enter(2, 3)
	_check("seats: a fifth person is refused (all four seats taken); a seated person cannot take a second seat",
		not r5.ok and r5.message.contains("All four seats are taken") and not again.ok, "%s / %s" % [r5.message, again.message])
	st().characters.erase(&"crew_5")
	var bad_seat := services.session.request(&"rover_enter", &"", {"seat": 4}, 1)
	_check("seats: there is no seat 4 (bad request)", not bad_seat.ok and bad_seat.reason == &"bad_request")
	# driver disconnect: the seat is freed at once, the character is back at the hub
	services.session.peer_left(1)
	var driver_free := String((st().rover.seats as Array)[0]) == "" and st().character(&"crew_1").position.distance_to(st().character(&"crew_1").hub_spot) < 1e-4
	_tick()
	_check("seats: a driver disconnect frees the driver's seat (the character returns to the hub); the passengers keep theirs",
		driver_free and (st().rover.seats as Array) == ["", "crew_2", "crew_3", "crew_4"], str(st().rover.seats))
	# recovery frees the seat
	services.session.recover_character(&"crew_3")
	_check("seats: an emergency recovery frees that character's seat", String((st().rover.seats as Array)[2]) == "" and RoverModel.seat_of(st(), "crew_3") < 0)
	# the freed driver's seat can be taken by a passenger after getting out, and parked characters' seats are freed by the tick
	services.session.peer_left(4)
	_tick()
	_check("seats: a parked character's seat is free on the next tick", String((st().rover.seats as Array)[3]) == "")
	# put the host back on crew_1
	services.session.peer_joined(1)
	services.session.request(&"claim_character", &"crew_1", {}, 1)
	for peer in [2, 3]:
		services.session.request(&"release_character", &"", {}, peer)
		services.session.peer_left(peer)
	_tick()
	_check("seats: releasing a seated character (peer 2) frees its seat; the rover is empty again", (st().rover.seats as Array) == ["", "", "", ""], str(st().rover.seats))


func _test_exit_and_suit() -> void:
	_become(&"crew_2")
	var e := _enter(1, 0)
	var bad := services.session.request(&"rover_exit", &"", {"exit_index": RoverModel.exit_count()}, 1)
	var ex := services.session.request(&"rover_exit", &"", {"exit_index": 1}, 1)
	var want := RoverModel.exit_world_position(st(), 1)
	var not_in := services.session.request(&"rover_exit", &"", {"exit_index": 0}, 1)
	_check("exit: the host checks the exit index and puts the character at the pose + exit offset; the seat is freed; leaving twice is refused",
		e.ok and not bad.ok and bad.reason == &"unknown_target" and ex.ok and me().position.distance_to(want) < 1e-4 and RoverModel.seat_of(st(), "crew_2") < 0
		and CharacterState._v3(ex.changes.position).distance_to(want) < 1e-4 and not not_in.ok, "%s %s %s" % [bad.reason, ex.reason, not_in.reason])
	# the garage is outside (the game's own zone test): a suit is needed to get in
	var outside := bool(services.session.outside_test.call(RoverModel.pose_position(st())))
	var no_suit := _enter(1, 0, false)
	var suit := _enter(1, 0, true)
	services.session.request(&"rover_exit", &"", {"exit_index": 0}, 1)
	# a rover inside the habitat would need no suit (zone test replaced by hand for this one request)
	var old_test := services.session.outside_test
	services.session.outside_test = func(_p: Vector3) -> bool: return false
	var inside := _enter(1, 0, false)
	services.session.request(&"rover_exit", &"", {"exit_index": 0}, 1)
	services.session.outside_test = old_test
	me().suit_on = false
	_check("enter: the garage is outside, so getting in needs the suit on; with it on it works (and inside no suit is needed)",
		outside and not no_suit.ok and no_suit.message.contains("suit") and suit.ok and inside.ok, no_suit.message)
	me().position = RoverModel.pose_position(st()) + Vector3(40.0, 0.0, 0.0)
	var far := services.session.request(&"rover_enter", &"", {"seat": 0}, 1)
	_check("enter: refused from too far away", not far.ok and far.reason == &"too_far")


# ---------------------------------------------------------------- charging and driving

func _test_charging() -> void:
	_park()
	_become(&"crew_1")
	st().rover.battery_kwh = 5.0
	me().position = _pos(String(CHARGER)) + Vector3(0.0, 0.0, 6.0)
	var far := _req(&"rover_set_charging", CHARGER, {"on": true})
	_at(String(CHARGER))
	_move_rover(RoverModel.pose_position(st()) + Vector3(0.0, 0.0, 20.0))
	var unplugged_far := _req(&"rover_set_charging", CHARGER, {"on": true})
	_park()
	st().stores[&"battery_kwh"] = 700.0          # test setup: well above the charging reserve
	var start := _snap()
	var on := _req(&"rover_set_charging", CHARGER, {"on": true})
	_hours(2.0)
	var ids := _identities(start)
	var moved := _ld(start, "rover_charge_kwh")
	var gained := float(st().rover.battery_kwh) - float(start.rover)
	var b := RoverBalance.get_current()
	_check("charging: refused from too far (actor) and with the rover out of cable reach; anyone can plug in at the charger",
		not far.ok and far.reason == &"too_far" and not unplugged_far.ok and unplugged_far.reason == &"too_far" and on.ok, "%s %s %s" % [far.reason, unplugged_far.reason, on.reason])
	_check("charging: 2 game hours at %s kW move exactly %s kWh from the colony battery; the rover gets %s %% of it (all ledgered)" % [str(b.charger_kw), str(b.charger_kw * 2.0), str(roundi(b.charger_efficiency * 100.0))],
		absf(moved - b.charger_kw * 2.0) < 1e-6 and absf(gained - moved * b.charger_efficiency) < 1e-6 and absf(float(ids.colony)) < 1e-6 and absf(float(ids.rover)) < 1e-6,
		"moved %.6f gained %.6f ids %s" % [moved, gained, ids])
	# at the reserve: charging pauses with a reason and the charger never takes the colony battery below it
	# (two direct system steps, no power model, so only the charger moves energy)
	var sys := RoverSystem.new()
	var reserve := RoverSystem.charge_reserve_kwh(st())
	st().stores[&"battery_kwh"] = reserve + 0.01
	var start2 := _snap()
	sys.step(st(), services.balance, 0.5, 0.1, null)
	var first_status := String(st().rover.charge_status)
	sys.step(st(), services.balance, 0.5, 0.1, null)
	var taken := _ld(start2, "rover_charge_kwh")
	_check("charging: at the colony's charging reserve (%s kWh) it takes only the 0.01 kWh above it, then pauses with a reason, still plugged in" % String.num(reserve, 0),
		absf(taken - 0.01) < 1e-9 and first_status == "charging" and String(st().rover.charge_status) == "paused_reserve" and bool(st().rover.charging)
		and absf(st().store(&"battery_kwh") - reserve) < 1e-9 and absf(float(_identities(start2).colony)) < 1e-9, "taken %.4f status %s" % [taken, st().rover.charge_status])
	# with the whole model running near the reserve, no tick ends with the charger having taken the battery below it
	st().stores[&"battery_kwh"] = reserve + 2.0
	var below := 0
	for i in 40:
		var l0 := float(st().ledger.rover_charge_kwh)
		_hours(0.05)
		if float(st().ledger.rover_charge_kwh) > l0 + 1e-12 and st().store(&"battery_kwh") < reserve - 1e-9:
			below += 1
	_check("charging: over 2 game hours near the reserve the charger never takes the colony battery below it", below == 0, "%d ticks" % below)
	st().stores[&"battery_kwh"] = 600.0
	# a power deficit pauses it too (power_deficit set by hand for one direct system step)
	st().power_deficit = true
	var before := float(st().rover.battery_kwh)
	sys.step(st(), services.balance, 0.5, 0.1, null)
	_check("charging: a colony power deficit pauses charging (direct system step)", String(st().rover.charge_status) == "paused_deficit" and float(st().rover.battery_kwh) == before)
	st().power_deficit = false
	# driving away unplugs it
	_move_rover(RoverModel.pose_position(st()) + Vector3(0.0, 0.0, 20.0))
	_tick()
	_check("charging: driving away from the charger stops charging and says why", not bool(st().rover.charging) and String(st().rover.charge_status) == "unplugged")
	_park()


func _test_note_driven() -> void:
	_park()
	st().rover.battery_kwh = 30.0
	var empty_bay: Array = (st().rover.cargo as Array).duplicate()
	var cargo_items := {}
	for id: Variant in empty_bay:
		cargo_items[String(id)] = st().items[String(id)]
	st().rover.cargo = []
	var flat := RoverSystem.note_driven(st(), services.events, 50.0, 0.0)
	st().rover.cargo = empty_bay
	var loaded := RoverSystem.note_driven(st(), services.events, 50.0, 0.0)
	var climb := RoverSystem.note_driven(st(), services.events, 50.0, 3.0)
	var start := _snap()
	var trip_before := float(st().rover.trip.distance_m)
	var used := RoverSystem.note_driven(st(), services.events, 10.0, 0.0)
	_check("note_driven: more energy with cargo aboard and on a climb; the trip totals and the ledger count it",
		loaded > flat and climb > loaded and is_equal_approx(float(st().rover.trip.distance_m) - trip_before, 10.0) and absf(_ld(start, "rover_drive_kwh") - used) < 1e-12
		and absf(float(_identities(start).rover)) < 1e-9, "flat %.4f loaded %.4f climb %.4f" % [flat, loaded, climb])
	st().rover.battery_kwh = 0.2
	var alerts := []
	var cb := func(id: StringName, _l: StringName, _t: String) -> void: alerts.append(String(id))
	services.events.system_alert.connect(cb)
	var last := RoverSystem.note_driven(st(), services.events, 500.0, 0.0)
	var none := RoverSystem.note_driven(st(), services.events, 500.0, 0.0)
	services.events.system_alert.disconnect(cb)
	_check("note_driven: an empty battery gives only what it holds (0.2 kWh), then nothing (coast and brake only), with one alert",
		is_equal_approx(last, 0.2) and none == 0.0 and float(st().rover.battery_kwh) == 0.0 and alerts.count("rover_battery_empty") == 1, "%s %s %s" % [last, none, alerts])
	st().rover.battery_kwh = 10.0


# ---------------------------------------------------------------- panels

func _test_panels() -> void:
	_park()
	_become(&"crew_1")
	_at(String(GARAGE))
	var panel := StationPanels.for_station(GARAGE, services) as GarageStationPanel
	root.add_child(panel)
	await _frames()
	panel.refresh()
	var levels := RoverModel.clean_levels(st().rover.levels)
	var lower := levels.duplicate()
	lower["speed"] = 3
	panel.set_plan("speed", 3)
	_check("garage panel: five sliders 1-5 with the level now, planned and the parts given back (speed 5 -> 3 gives 7)",
		panel.sliders.size() == 5 and panel.slider_text("speed").contains("5 now → 3 planned") and panel.slider_text("speed").contains("gives back 7")
		and panel.totals_text().contains("gives 7 parts back"), panel.slider_text("speed") + " | " + panel.totals_text())
	_check("garage panel: stats now and planned, battery stored, honest range with the cargo aboard",
		panel.table_text("speed", "now") == "25.2 km/h" and panel.table_text("speed", "plan") == "18 km/h" and panel.table_text("stored", "now").contains("kWh")
		and panel.table_text("range", "now") != "" and panel.reading_text(&"cargo").contains("of"), panel.table_text("speed", "plan"))
	_check("garage panel: anyone can plan, but only the field specialist ⛏ gets the button (others are told who can)",
		not panel.commit_button.visible and panel.who_text().contains("⛏") and panel.who_text().contains("Only"), panel.who_text())
	panel.queue_free()
	await _frames()
	# as the field engineer, through the panel: answer the check and refit
	_become(FIELD)
	_at(String(GARAGE))
	panel = StationPanels.for_station(GARAGE, services) as GarageStationPanel
	root.add_child(panel)
	await _frames()
	panel.set_plan("speed", 3)
	var ch := panel.current_challenge()
	var blocked := panel.commit_reason_text()
	for step: Dictionary in ch.steps:
		var mods: Array = step.modules
		for i in mods.size():
			if bool((mods[i] as Dictionary).ok):
				panel.choose(String(step.stat), "module", i)
		panel.choose(String(step.stat), "port", String(step.port))
		panel.choose(String(step.stat), "check", int(step.answer))
	var parts := st().parts
	var r := panel.press_commit()
	_check("garage panel: the engineer answers the check in the panel and refits (speed 5 -> 3, 7 parts back)",
		blocked.contains("assembly check") and r != null and r.ok and bool(r.changes.assembled) and st().parts == parts + 7 and RoverModel.level_of(st().rover.levels, "speed") == 3
		and panel.cause_text().contains("Refit done"), "%s %s" % [blocked, r.changes if r != null else "no commit"])
	panel.queue_free()
	await _frames()
	# charger panel
	_become(&"crew_1")
	_at(String(CHARGER))
	var cp := StationPanels.for_station(CHARGER, services) as RoverChargerStationPanel
	root.add_child(cp)
	await _frames()
	cp.refresh()
	var was := bool(st().rover.charging)
	cp.charge_button.pressed.emit()
	cp.refresh()
	_check("charger panel: shows the rover battery, the colony cost and plugs the rover in or out",
		cp.reading_text(&"rover_battery").contains("kWh") and cp.reading_text(&"cost").contains("kW") and bool(st().rover.charging) != was
		and cp.charge_button.text == ("Stop charging" if bool(st().rover.charging) else "Start charging"), cp.reading_text(&"rover_battery"))
	if bool(st().rover.charging):
		_req(&"rover_set_charging", CHARGER, {"on": false})
	cp.queue_free()
	await _frames()


func _test_layouts() -> void:
	var stretch := root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	# the engineer's view is the largest: the sliders, the table and three check cards
	_become(FIELD)
	_at(String(GARAGE))
	var panel := StationPanels.for_station(GARAGE, services) as GarageStationPanel
	root.add_child(panel)
	panel.set_plan("speed", 1)
	panel.set_plan("torque", 3)
	panel.set_plan("traction", 2)
	await _check_layout(panel, "garage (engineer, 3 check cards)")
	panel.queue_free()
	await process_frame
	_at(String(CHARGER))
	var cp := StationPanels.for_station(CHARGER, services)
	root.add_child(cp)
	await _check_layout(cp, "charger")
	cp.queue_free()
	await process_frame
	root.content_scale_mode = stretch


func _check_layout(ctl: Control, label: String) -> void:
	var layout := PackedStringArray()
	var focus := PackedStringArray()
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
		for line in UiLayoutCheck.focus_problems(ctl):
			focus.append("%s text %s: %s" % [size[0], size[1], line])
	UiTheme.apply_text_scale(1.0)
	root.size = Vector2i(1280, 720)
	_check("layout %s at 1280x720, 1920x1080 and 1280x720 text 1.5" % label, layout.is_empty(), "\n  ".join(layout))
	_check("focus %s" % label, focus.is_empty() and not UiLayoutCheck.focusable(ctl).is_empty(), "\n  ".join(focus))
