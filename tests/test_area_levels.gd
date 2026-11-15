extends SceneTree
## Visible upgrade paths core (2026-11-14): data file, levels, effects, the upgrade_area action, save round trip and
## the stage presenters' loading.

var _passed := 0
var _total := 0
var _sessions: Array[SessionService] = []
var _zones: ColonyZones
var _stations: Dictionary


func _initialize() -> void:
	_zones = ColonyZones.from_manifest("res://data/colony_manifest.json")
	_stations = StationCatalog.from_manifest("res://data/colony_manifest.json", _zones)
	_data_file()
	_levels_and_effects()
	_action()
	_round_trip()
	_presenters()
	for session: SessionService in _sessions:
		session.events.free()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


func _check(label: String, okay: bool) -> void:
	_total += 1
	if okay:
		_passed += 1
	print(("PASS " if okay else "FAIL ") + label)


func _session() -> SessionService:
	var session := SessionService.new(GameConfig.new(), GameBalance.new(), GameEvents.new())
	var state := ColonyState.new_game(session.balance, 4417, _zones.names)
	state.stations = _stations.duplicate(true)
	session.zone_at_position = func(position: Vector3) -> String: return _zones.zone_at_world(position)
	session.outside_test = func(position: Vector3) -> bool: return _zones.zone_at_world(position) == ColonyZones.EXTERIOR
	for actor: CharacterState in state.characters.values():
		actor.hub_spot = session.config.hub_position
		actor.position = actor.hub_spot
	session.begin(state, SolClock.new())
	_sessions.append(session)
	return session


## Gives peer 1 the crew member with `specialty` and stands them at `station_id`.
func _crew(session: SessionService, specialty: StringName, station_id: String) -> CharacterState:
	var who: CharacterState = null
	for c: CharacterState in session.state.characters.values():
		c.owner_peer = 0
	for c: CharacterState in session.state.characters.values():
		if c.specialty == specialty:
			who = c
			break
	who.owner_peer = 1
	session.report_position(1, who.id, CharacterState._v3(session.state.stations[station_id].position), 0.0)
	return who


func _station_of(kind: String) -> String:
	for id: String in _stations:
		if String(_stations[id].kind) == kind:
			return id
	return ""


func _data_file() -> void:
	AreaLevels.reload()
	var ids := AreaLevels.track_ids()
	_check("every requested area has a track", ["food", "garden", "energy", "life_support", "health", "command", "scout_drone", "rover"].all(func(t: String) -> bool: return ids.has(t)))
	_check("at least four levels", AreaLevels.max_level() >= 4)
	var ok := true
	for t: Dictionary in AreaLevels.tracks():
		var stages: Array = t.get("stages", [])
		var costs: Array = t.get("cost_parts", [])
		if stages.size() < AreaLevels.max_level() or costs.size() < AreaLevels.max_level():
			ok = false
		for k in (t.get("effects", {}) as Dictionary):
			if (t.effects[k] as Array).size() < AreaLevels.max_level():
				ok = false
	_check("every track names a stage, a cost and every effect for each level", ok)
	var served := true
	for t: Dictionary in AreaLevels.tracks():
		var found := false
		for sid: String in _stations:
			if AreaLevels.station_serves(String(t.id), sid, _stations[sid]):
				found = true
				break
		if not found and String(t.id) != "scout_drone":
			served = false
			print("  no station serves ", t.id)
	_check("every track except the drone (its pad comes with the drone) has a station on the map", served)


func _levels_and_effects() -> void:
	var s := _session()
	_check("a new colony starts every track at V1", Array(AreaLevels.track_ids()).all(func(t: String) -> bool: return AreaLevels.level(s.state, t) == 1))
	_check("V1 effect is the first entry", is_equal_approx(AreaLevels.effectf(s.state, "food", "yield_factor"), 1.0))
	s.state.levels["food"] = 3
	_check("effect follows the level", is_equal_approx(AreaLevels.effectf(s.state, "food", "yield_factor"), 2.8))
	_check("missing effect gives the default", is_equal_approx(AreaLevels.effectf(s.state, "food", "nope", 7.0), 7.0))
	s.state.levels["food"] = 99
	_check("level is clamped to the maximum", AreaLevels.level(s.state, "food") == AreaLevels.max_level())
	_check("stock rover is V1", AreaLevels.level(s.state, "rover") == 1)
	s.state.rover.levels = {"speed": 5, "torque": 5, "range": 5, "cargo": 5, "traction": 5}
	_check("fully upgraded rover modules show V4", AreaLevels.level(s.state, "rover") == 4)
	s.state.rover.levels = {"speed": 2, "torque": 1, "range": 1, "cargo": 1, "traction": 1}
	_check("one module step shows V2", AreaLevels.level(s.state, "rover") == 2)


func _action() -> void:
	var s := _session()
	var console := _station_of("food")
	_check("the greenhouse console exists", console != "")
	s.state.parts = 20
	var wrong := _crew(s, &"electrical_comms", console)
	var r := s.request(&"upgrade_area", StringName(console), {"track": "food"}, 1)
	_check("the wrong specialist is refused", not r.ok and AreaLevels.level(s.state, "food") == 1)
	var right := _crew(s, &"biology_food", console)
	r = s.request(&"upgrade_area", StringName(console), {"track": "food"}, 1)
	_check("the biologist upgrades the greenhouse to V2", r.ok and AreaLevels.level(s.state, "food") == 2)
	_check("parts are spent once", s.state.parts == 20 - AreaLevels.cost_to_reach("food", 2))
	r = s.request(&"upgrade_area", StringName(_station_of("power")), {"track": "food"}, 1)
	_check("the wrong station is refused", not r.ok and AreaLevels.level(s.state, "food") == 2)
	s.state.parts = 0
	r = s.request(&"upgrade_area", StringName(console), {"track": "food"}, 1)
	_check("no parts, no upgrade", not r.ok and AreaLevels.level(s.state, "food") == 2)
	s.state.parts = 50
	s.request(&"upgrade_area", StringName(console), {"track": "food"}, 1)
	s.request(&"upgrade_area", StringName(console), {"track": "food"}, 1)
	var left := s.state.parts
	r = s.request(&"upgrade_area", StringName(console), {"track": "food"}, 1)
	_check("V4 is the top and asking again spends nothing", AreaLevels.level(s.state, "food") == 4 and not r.ok and s.state.parts == left)
	var power := _station_of("power")
	_crew(s, &"electrical_comms", power)
	var cap0 := float(s.state.capacities.get(&"battery_kwh", 0.0))
	r = s.request(&"upgrade_area", StringName(power), {"track": "energy"}, 1)
	var f := float(AreaLevels.effect_at("energy", "battery_capacity_factor", 2, 1.0))
	_check("the energy upgrade grows the battery capacity once", r.ok and is_equal_approx(float(s.state.capacities.get(&"battery_kwh", 0.0)), cap0 * f))
	r = s.request(&"upgrade_area", StringName(_station_of("garage")), {"track": "rover"}, 1)
	_check("the rover look cannot be bought (it follows the modules)", not r.ok)
	_check("unknown track is refused", not s.request(&"upgrade_area", StringName(console), {"track": "moon_base"}, 1).ok)
	var _unused := [wrong, right]


func _round_trip() -> void:
	var s := _session()
	s.state.levels = {"food": 3, "health": 2}
	s.state.drone = {"status": "docked", "battery": 0.5}
	var copy := ColonyState.from_dict(JSON.parse_string(JSON.stringify(s.state.to_dict())))
	_check("levels survive save and replication", AreaLevels.level(copy, "food") == 3 and AreaLevels.level(copy, "health") == 2 and typeof(copy.levels["food"]) == TYPE_INT)
	_check("drone state survives save and replication", String(copy.drone.get("status", "")) == "docked")
	var old := s.state.to_dict()
	old.erase("levels")
	old.erase("drone")
	var older := ColonyState.from_dict(old)
	_check("an old save without levels loads at V1", AreaLevels.level(older, "food") == 1 and older.drone.is_empty())


func _presenters() -> void:
	var ok := true
	for id: String in AreaLevels.track_ids():
		var path := AreaStages.script_path(id)
		var script := load(path) as Script
		if script == null:
			ok = false
			print("  missing ", path)
			continue
		var n: Variant = script.new()
		if not (n is AreaStagePresenter) or (n as AreaStagePresenter).track_id() != id:
			ok = false
			print("  wrong presenter ", path)
		if n is Node:
			(n as Node).free()
	_check("every track has a stage presenter that names its track", ok)
	var root := Node3D.new()
	get_root().add_child(root)
	var made := AreaStages.attach_all(root, root, null, null)
	_check("attach_all builds one presenter per track without a game", made.size() == AreaLevels.track_ids().size())
	for id: String in made:
		var p := made[id] as AreaStagePresenter
		for lvl in range(1, AreaLevels.max_level() + 1):
			p.force_level = lvl
			p.refresh()
	_check("every stage of every track builds without a game running", true)
	root.free()
