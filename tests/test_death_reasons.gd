extends SceneTree
## Death record (CharacterState.last_death), Med Bay respawn, med station healing and the four-second death on every
## way out of the base. Headless; host real time is stepped the way test_survival does it (session.advance in frames).

const DeathReasons := preload("res://scripts/survival/death_reasons.gd")
const MedCare := preload("res://scripts/survival/med_care.gd")
const MARS := Vector3(200, 0.04, 200)
const CHAMBER := Vector3(22, 0.04, 12)
const FRAME := 1.0 / 60.0
const KEYS := ["cause", "title", "text", "area", "at_hours", "count"]
var _passed := 0
var _total := 0
var _sessions: Array[SessionService] = []
var _recoveries: Dictionary = {}
var _events: Dictionary = {}
var _zones: ColonyZones
var _catalog: Dictionary

func _initialize() -> void:
	_zones = ColonyZones.from_manifest("res://data/colony_manifest.json")
	_catalog = StationCatalog.from_manifest("res://data/colony_manifest.json", _zones)
	_catalog_words()
	_exposure_causes()
	_cabin_causes()
	_health_causes()
	_other_paths()
	_every_way_out()
	_suit_oxygen_timing()
	_count_event_and_replication()
	_save_load_and_med_bay()
	_healing_and_levels()
	for session: SessionService in _sessions:
		session.events.free()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)

func _check(label: String, okay: bool, detail := "") -> void:
	_total += 1
	if okay:
		_passed += 1
	print(("PASS " if okay else "FAIL ") + label + ("" if okay or detail == "" else "  [" + detail + "]"))

func _session(sol_minutes := 20.0) -> SessionService:
	var balance := GameBalance.new()
	balance.maintenance_enabled = false
	var s := SessionService.new(GameConfig.new(), balance, GameEvents.new())
	s.zone_at_position = func(point: Vector3) -> String: return _zones.zone_at_world(point)
	s.outside_test = func(point: Vector3) -> bool: return _zones.zone_at_world(point) == ColonyZones.EXTERIOR
	var state := ColonyState.new_game(balance, 4417, _zones.names)
	state.stations = _catalog.duplicate(true)
	state.repair.tasks.T10.broken = false
	for actor: CharacterState in state.characters.values():
		actor.position = s.config.hub_position
		actor.hub_spot = actor.position
	var clock := SolClock.new()
	clock.sol_minutes = sol_minutes
	s.begin(state, clock)
	s.request(&"claim_character", &"crew_1")
	_sessions.append(s)
	var key := s.get_instance_id()
	_recoveries[key] = 0
	_events[key] = []
	s.events.character_recovered.connect(func(id: StringName, info: Dictionary) -> void:
		_recoveries[key] = int(_recoveries[key]) + 1
		# The record must already be on the character when the event fires (the UI reads either).
		(_events[key] as Array).append({"id": id, "info": info.duplicate(true), "record": s.state.character(id).last_death.duplicate(true)}))
	return s

func _me(s: SessionService) -> CharacterState:
	return s.state.character_of_peer(1)

func _at(s: SessionService, point: Vector3) -> void:
	s.report_position(1, _me(s).id, point, 0.0)

func _run(s: SessionService, seconds: float, frame := FRAME) -> void:
	var left := seconds
	while left > 1e-8:
		var step := minf(frame, left)
		s.advance(step)
		left -= step

func _count(s: SessionService) -> int:
	return int(_recoveries.get(s.get_instance_id(), 0))

func _last_event(s: SessionService) -> Dictionary:
	var list: Array = _events.get(s.get_instance_id(), [])
	return list.back() if not list.is_empty() else {}

func _valid_record(r: Dictionary) -> bool:
	for k: String in KEYS:
		if not r.has(k):
			return false
	return DeathReasons.CAUSES.has(String(r.cause)) and String(r.title) != "" and String(r.text).length() > 20 and int(r.count) >= 1

## Dies from the current position within one more frame after 4 s; returns the record.
func _expect_death(s: SessionService, cause: String, label: String) -> Dictionary:
	var me := _me(s)
	var before := _count(s)
	_run(s, 3.98)
	var alive := _count(s) == before
	_run(s, 0.04)
	var r := me.last_death
	_check(label + ": alive at 3.98 s, dead by 4.02 s", alive and _count(s) == before + 1, "count %d->%d" % [before, _count(s)])
	_check(label + ": record cause " + cause, String(r.get("cause", "")) == cause and _valid_record(r), str(r))
	return r

# ------------------------------------------------------------------------------------------------------------------

func _catalog_words() -> void:
	for id: String in ["no_suit_outside", "suit_oxygen_out", "suit_damaged", "airlock_pressure", "cabin_air", "low_oxygen", "co2",
			"starvation", "dehydration", "cold", "injury", "unknown"]:
		var r := DeathReasons.make_record(id, "Med Bay", 12.5, {})
		_check("catalog record " + id, _valid_record(r) and r.cause == id and r.count == 1 and r.at_hours == 12.5 and r.title.length() <= 30)
	var odd := DeathReasons.make_record("made_up", "", 0.0, {"count": 4})
	_check("unknown ids fall back to the unknown record and still count", odd.cause == "unknown" and odd.count == 5)
	var title_ok := String(DeathReasons.CAUSES.no_suit_outside.title) == "No suit outside" and String(DeathReasons.CAUSES.no_suit_outside.text).contains("suit rack")
	_check("no-suit words match the brief", title_ok)

func _exposure_causes() -> void:
	var s := _session()
	_at(s, MARS)
	var r := _expect_death(s, "no_suit_outside", "no suit outside")
	_check("no suit outside: area words and time stamp", r.area == "Outside the base" and float(r.at_hours) > 0.0 and int(r.count) == 1, str(r))
	_check("no suit outside: respawn after the record, in the Med Bay", _zones.zone_at_world(_me(s).position) == "Med Bay" and _me(s).hazard_cause == "")

	var torn := _session()
	_me(torn).suit_on = true
	_me(torn).suit_integrity = 0.0
	_at(torn, MARS)
	_expect_death(torn, "suit_damaged", "broken suit seal")

	var empty := _session()
	_me(empty).suit_on = true
	_me(empty).suit_charge = 0.0
	_at(empty, MARS)
	_expect_death(empty, "suit_oxygen_out", "empty suit tank outside")

	var vented := _session()
	vented.survival.set_airlock_door_open(902, true)
	_at(vented, CHAMBER)
	var a := _expect_death(vented, "airlock_pressure", "exit tunnel with the outer door open")
	_check("airlock record names the vestibule", a.area == "Airlock exit vestibule", str(a))

	var fault := _session()
	fault.survival.debug_trigger_airlock_fault()
	_at(fault, CHAMBER)
	_expect_death(fault, "airlock_pressure", "exit tunnel with a seal leak")

func _cabin_causes() -> void:
	var thin := _session()
	thin.state.stores[&"oxygen_kg"] = 0.0
	thin.state.stores[&"n2_reserve_kg"] = 0.0
	thin.state.cabin_n2_kg = 0.0
	thin.state.cabin_o2_kg = thin.balance.gas_kg_for_kpa(18.0, GameBalance.MOLAR_O2)
	_at(thin, thin.config.hub_position)
	var r := _expect_death(thin, "cabin_air", "base air pressure too low")
	_check("cabin record names the room", r.area == "Med Bay", str(r))

	var low := _session()
	low.state.stores[&"oxygen_kg"] = 0.0
	low.state.cabin_o2_kg = low.balance.gas_kg_for_kpa(low.balance.o2_low_kpa * 0.5, GameBalance.MOLAR_O2)
	_at(low, low.config.hub_position)
	_expect_death(low, "low_oxygen", "cabin oxygen too low")

	var stale := _session()
	stale.state.cabin_co2_kg = stale.balance.gas_kg_for_kpa(stale.balance.co2_danger_kpa * 4.0, GameBalance.MOLAR_CO2)
	_at(stale, stale.config.hub_position)
	_expect_death(stale, "co2", "too much carbon dioxide")

func _health_causes() -> void:
	for case: Array in [["dehydration", true, false], ["starvation", false, true], ["dehydration", true, true]]:
		var s := _session()
		if case[1]:
			s.state.stores[&"water_l"] = 0.0
		if case[2]:
			s.state.stores[&"food_meals"] = 0.0
		_me(s).health = 0.001
		_run(s, 1.0, 0.05)
		var r := _me(s).last_death
		var label := "simulation health loss (water %s, food %s)" % ["out" if case[1] else "ok", "out" if case[2] else "ok"]
		_check(label + " -> " + String(case[0]), _count(s) == 1 and String(r.get("cause", "")) == String(case[0]) and _valid_record(r), str(r))
		_check(label + ": not an air death", r.area == "Med Bay")

func _other_paths() -> void:
	var direct := _session()
	direct.recover_character(&"crew_1")
	_check("direct recovery with nothing wrong is the last-resort unknown", String(_me(direct).last_death.get("cause", "")) == "unknown")
	var explicit := _session()
	explicit.recover_character(&"crew_1", "injury")
	_check("an explicit cause id is kept (injury)", String(_me(explicit).last_death.get("cause", "")) == "injury" and _me(explicit).last_death.title == "Badly hurt")
	var gone := _session()
	gone.peer_joined(2)
	var remote := gone.state.character(&"crew_2")
	remote.owner_peer = 2
	gone.report_position(2, remote.id, MARS, 0.0)
	gone.advance(1.0)
	gone.peer_left(2)
	_check("disconnecting during exposure records the exposure cause", String(remote.last_death.get("cause", "")) == "no_suit_outside" and remote.position == remote.hub_spot, str(remote.last_death))
	var safe := _session()
	safe.peer_joined(2)
	var parked := safe.state.character(&"crew_2")
	parked.owner_peer = 2
	safe.peer_left(2)
	_check("a safe disconnect is not a death", parked.last_death.is_empty())
	var replica := _session()
	replica.state.assign_from(direct.state.to_dict())
	replica.apply_replica(direct.replica_dict())
	var copy := replica.state.character(&"crew_1").last_death.duplicate()
	replica.recover_character(&"crew_1", "co2")
	_check("a client replica cannot write a death record", replica.state.character(&"crew_1").last_death == copy)

## The four-second death on every way out. A walker reports a pose every frame at walking speed (1.4 m/s) along a
## path from breathable air out onto Mars; the death must come 4 s after the first unbreathable pose.
func _walk_out(label: String, from: Vector3, to: Vector3, setup := Callable(), cause := "no_suit_outside") -> void:
	var s := _session()
	if setup.is_valid():
		setup.call(s)
	var me := _me(s)
	_at(s, from)
	s.advance(0.0)
	var started := not me.exposure_active
	var t := 0.0
	var exposed_at := -1.0
	var died_at := -1.0
	var length := from.distance_to(to)
	while t < length / 1.4 + 6.0 and died_at < 0.0:
		var along := minf(1.0, t * 1.4 / maxf(0.01, length))
		if _count(s) == 0:
			_at(s, from.lerp(to, along))
		if exposed_at < 0.0 and me.exposure_active:
			exposed_at = t
		s.advance(FRAME)
		t += FRAME
		if _count(s) > 0:
			died_at = t
	var gap := died_at - exposed_at
	_check("%s: starts safe, then the 4 s death" % label, started and exposed_at >= 0.0 and died_at > 0.0 and gap >= 3.98 and gap <= 4.0 + FRAME + 1e-6,
		"exposed %.3f died %.3f" % [exposed_at, died_at])
	_check("%s: record %s" % [label, cause], String(me.last_death.get("cause", "")) == cause, str(me.last_death))

func _every_way_out() -> void:
	# 1. The exit tunnel: inner door (z 10.3) to outer door (z 14.85) and out onto Mars, outer door open.
	_walk_out("exit tunnel through the open outer door", Vector3(22, 0.04, 9.5), Vector3(22, 0.04, 22.0),
		func(s: SessionService) -> void:
			s.survival.set_airlock_door_open(901, true)
			s.survival.set_airlock_door_open(902, true))
	# (The danger starts in the vented tunnel; 4 s at walking speed later the walker is out on Mars, which is what
	# the record names. A walker who stops in the tunnel gets airlock_pressure: see _exposure_causes.)
	# 1b. The same tunnel while the chamber still holds air: the death starts just past the outer door (z 14.85).
	_walk_out("out of a pressurised tunnel past its outer door", Vector3(22, 0.04, 13.0), Vector3(22, 0.04, 25.0))
	# 2. The airlock room's own exit is the tunnel; the hangar has no outside door. The glass hall wall itself:
	_walk_out("through a gap in the glass hall wall (west)", Vector3(-11.6, 0.04, -5.0), Vector3(-18.0, 0.04, -5.0))
	_walk_out("through a gap in the glass hall wall (north)", Vector3(5.0, 0.04, -19.5), Vector3(5.0, 0.04, -26.0))
	_walk_out("through a gap in the glass hall wall (east)", Vector3(42.1, 0.04, -5.0), Vector3(48.0, 0.04, -5.0))
	# 3. The garden dome: from its beds out through the vestibule's outer door (x 41.4) and on (the 8..11 m pad ring
	#    is Mars air, not dome air).
	_walk_out("garden dome out through its airlock", Vector3(46.0, 0.04, 27.0), Vector3(36.0, 0.04, 27.0))
	_walk_out("garden dome out through a gap in its glass", Vector3(50.0, 0.04, 31.0), Vector3(50.0, 0.04, 40.0))
	var s := _session()
	var garden_ring := Vector3(50.0 + 9.5, 0.04, 27.0)
	_check("garden pad ring is still the Garden dome lighting zone", _zones.zone_at_world(garden_ring) == ColonyZones.GARDEN)
	_check("... but it is Mars air", not s.survival.breathable_at(garden_ring))
	_check("garden dome centre and beds are breathable", s.survival.breathable_at(Vector3(50, 0.04, 27)) and s.survival.breathable_at(Vector3(46.2, 0.04, 23.5)))
	var vestibule := Vector3(41.8, 0.04, 27.0)
	var shut := s.survival.breathable_at(vestibule)
	s.survival.set_airlock_door_open(912, true)
	var open := s.survival.breathable_at(vestibule)
	s.survival.set_airlock_door_open(912, false)
	_check("garden vestibule breathes with its outer door shut, not with it open", shut and not open)
	var garden_beds := 0
	var bad_beds: Array[String] = []
	for id: String in s.state.stations:
		var record: Dictionary = s.state.stations[id]
		if String(record.get("zone", "")) == ColonyZones.GARDEN:
			garden_beds += 1
			if not s.survival.breathable_at(CharacterState._v3(record.position)):
				bad_beds.append(id)
	_check("every garden dome station stays in breathable air", garden_beds > 0 and bad_beds.is_empty(), str(bad_beds))
	# 4. Any gap: no breathable pocket anywhere outside the glass hall, the garden shell, the garden vestibule and the
	#    exit tunnel (1 m grid over the whole base and garden).
	var pockets: Array[String] = []
	var inside_ok := 0
	var inside_bad: Array[String] = []
	for gx in range(-30, 76):
		for gz in range(-40, 51):
			var p := Vector3(float(gx) + 0.5, 0.04, float(gz) + 0.5)
			var hall := _zones.in_dome(p.x, -p.z)
			var shell := Vector2(p.x, p.z).distance_to(Vector2(50, 27)) <= 8.15
			var chamber := LocalPressure.VOLUME.has_point(p)
			var vest := LocalPressure.GARDEN_VESTIBULE.has_point(p)
			var breathes := s.survival.breathable_at(p)
			if not (hall or shell or chamber or vest) and breathes:
				pockets.append(str(p))
			if (hall or shell) and not chamber:
				if breathes:
					inside_ok += 1
				else:
					inside_bad.append(str(p))
	_check("no breathable pocket outside the hall, the garden shell and the airlocks", pockets.is_empty(), "%d pockets e.g. %s" % [pockets.size(), pockets.slice(0, 5)])
	_check("inside the hall and the garden shell the air is breathable", inside_ok > 1000 and inside_bad.is_empty(), "%d bad e.g. %s" % [inside_bad.size(), inside_bad.slice(0, 5)])
	# 5. The old game-hour no-air loss is off in the session: 3.98 s outside costs no health at any sol length.
	for sol: float in [5.0, 120.0]:
		var slow := _session(sol)
		_at(slow, MARS)
		_run(slow, 3.98, 0.1)
		_check("sol %.0f min: no slow health loss outside, only the 4 s deadline" % sol, _me(slow).health == 100.0 and _count(slow) == 0 and slow.sim.exposure_managed)
		_run(slow, 0.04, 0.1)
		_check("sol %.0f min: dead at 4 s" % sol, _count(slow) == 1)

## A suited walker whose tank runs dry outside dies 4 s after the tank is empty.
func _suit_oxygen_timing() -> void:
	for frame: float in [1.0 / 144.0, FRAME, 0.2]:
		var s := _session()
		var me := _me(s)
		me.suit_on = true
		me.suit_charge = 0.01
		_at(s, MARS)
		s.advance(0.0)
		var protected := not me.exposure_active
		var t := 0.0
		var empty_at := -1.0
		var died_at := -1.0
		while t < 30.0 and died_at < 0.0:
			s.advance(frame)
			t += frame
			if empty_at < 0.0 and me.suit_charge <= 0.0:
				empty_at = t
			if _count(s) > 0:
				died_at = t
		_check("frame %.3f: suit protects while its tank has air" % frame, protected)
		_check("frame %.3f: tank runs dry, then the 4 s death" % frame, empty_at >= 0.0 and died_at - empty_at <= 4.0 + frame + 1e-6 and died_at - empty_at >= 3.9,
			"empty %.3f died %.3f" % [empty_at, died_at])
		_check("frame %.3f: record suit_oxygen_out" % frame, String(me.last_death.get("cause", "")) == "suit_oxygen_out")

func _count_event_and_replication() -> void:
	var s := _session()
	_at(s, MARS)
	_run(s, 4.1)
	var first := _me(s).last_death.duplicate()
	var event := _last_event(s)
	_check("character_recovered carries the record as info.death", not event.is_empty() and event.info.get("death", {}) == first and String(event.info.get("cause", "")) == "no_suit_outside")
	_check("the record is on the character before the event fires", event.get("record", {}) == first)
	_check("old recovery info is unchanged", event.info.has("meals") and event.info.has("water_l") and event.info.has("cache_id"))
	s.state.stores[&"food_meals"] = 0.0
	_me(s).health = 0.001
	_run(s, 1.0, 0.05)
	var second := _me(s).last_death
	_check("count rises with each death and the newest cause wins", int(second.count) == 2 and second.cause == "starvation" and float(second.at_hours) >= float(first.at_hours))
	# Replication: the same snapshot path NetSession uses (ColonyState.to_dict -> assign_from on the client).
	var client := _session()
	client.state.assign_from(s.state.to_dict())
	var mirrored := client.state.character(&"crew_1").last_death
	_check("replicated record is identical", mirrored == second, "%s vs %s" % [mirrored, second])
	var c := CharacterState.new()
	c.assign_from(_me(s).to_dict())
	_check("CharacterState.assign_from copies the record", c.last_death == second)
	var round_trip := CharacterState.from_dict(JSON.parse_string(JSON.stringify(_me(s).to_dict())))
	var rt: Dictionary = round_trip.last_death
	_check("record survives JSON (count int, hours float)", rt.cause == second.cause and rt.title == second.title and rt.text == second.text
		and rt.area == second.area and rt.count is int and rt.count == second.count and rt.at_hours is float and absf(rt.at_hours - second.at_hours) < 1e-4, str(rt))
	_check("never died = empty dictionary", CharacterState.from_dict({"id": "x"}).last_death.is_empty() and CharacterState.new().to_dict().last_death.is_empty())
	_check("mid-encounter hazard id is saved too", CharacterState.from_dict({"hazard_cause": "co2"}).hazard_cause == "co2")

func _save_load_and_med_bay() -> void:
	var game := GameServices.new()
	game.balance = GameBalance.new()
	game.balance.maintenance_enabled = false
	game.session.balance = game.balance
	game.saves = SaveService.new(ProjectSettings.globalize_path("res://_test_saves/test_death_reasons"), "fixture")
	game.saves.delete_all()
	game.start_new_game(733)
	var key := game.session.get_instance_id()
	_recoveries[key] = 0
	game.session.events.character_recovered.connect(func(_id: StringName, _info: Dictionary) -> void: _recoveries[key] = int(_recoveries[key]) + 1)
	var me := game.local_character()
	var heal := CharacterState._v3(game.state().stations.md_heal_station.position)
	_check("real hub spots are all in the Med Bay", game.state().characters.values().all(func(c: CharacterState) -> bool: return _zones.zone_at_world(c.hub_spot) == "Med Bay"))
	# The tutorial start suits everyone up; this check is about walking out without a suit.
	me.suit_on = false
	game.report_position(me.id, MARS, 0.0)
	_run(game.session, 4.05)
	_check("real game: dies in 4 s outside", int(_recoveries[key]) == 1 and me.last_death.cause == "no_suit_outside")
	_check("real game: respawns in the Med Bay near the med station", _zones.zone_at_world(me.position) == "Med Bay" and me.position == me.hub_spot and me.position.distance_to(heal) < 6.0, str(me.position))
	var record := me.last_death.duplicate()
	_check("save with a death record", game.save_now(&"death_fixture") == OK)
	game.restore(game.saves.read().payload)
	_check("load keeps the death record", game.local_character().last_death == record, str(game.local_character().last_death))
	game.saves.delete_all()
	game.free()

func _healing_and_levels() -> void:
	var heal_pos := CharacterState._v3(_catalog.md_heal_station.position)
	_check("med station is the md_heal_station map object, kind heal, in the Med Bay", String(_catalog.md_heal_station.kind) == "heal" and String(_catalog.md_heal_station.zone) == "Med Bay")
	for lvl in range(1, 5):
		var s := _session()
		s.state.levels["health"] = lvl
		var factor := float(AreaLevels.effect_at("health", "heal_rate_factor", lvl, 1.0))
		var bonus := float(AreaLevels.effect_at("health", "recovery_health_bonus", lvl, 0.0))
		var me := _me(s)
		_at(s, heal_pos)
		me.health = 20.0
		_run(s, 2.0, 0.05)
		var want := 20.0 + 2.0 * MedCare.HEAL_PER_SECOND * factor
		_check("V%d: heals %.1f health per second at the med station" % [lvl, MedCare.HEAL_PER_SECOND * factor], absf(me.health - want) < 0.06, "health %.3f want %.3f" % [me.health, want])
		_at(s, MARS)
		_run(s, 4.05)
		var expect := minf(100.0, s.balance.recovery_health + bonus)
		_check("V%d: respawn health = recovery_health + %.0f" % [lvl, bonus], _count(s) == 1 and is_equal_approx(me.health, expect), "health %.2f want %.2f" % [me.health, expect])
	var factors: Array = AreaLevels.track("health").effects.heal_rate_factor
	var bonuses: Array = AreaLevels.track("health").effects.recovery_health_bonus
	_check("health track: four rising heal factors and bonuses", factors.size() == 4 and bonuses.size() == 4 and float(factors[3]) > float(factors[0]) and float(bonuses[3]) > float(bonuses[0]))
	var capped := _session()
	capped.balance.recovery_health = 95.0
	capped.state.levels["health"] = 4
	capped.recover_character(&"crew_1")
	_check("respawn health is capped at full health", _me(capped).health == MedCare.MAX_HEALTH)
	# Where healing does not run.
	var far := _session()
	_me(far).health = 40.0
	_run(far, 2.0, 0.05)
	_check("no healing at the hub, out of the station's reach", _me(far).health <= 40.0)
	var dark := _session()
	_at(dark, heal_pos)
	_me(dark).health = 40.0
	dark.state.zones["Med Bay"] = {"powered": false}
	_check("no healing while the Med Bay has no power", MedCare.advance_actor(dark, _me(dark), 2.0) == 0.0)
	var debt := _session()
	_at(debt, MARS)
	_run(debt, 1.0)
	_at(debt, heal_pos)
	_me(debt).health = 40.0
	_run(debt, 1.0, 0.05)
	_check("no healing until the 2 s safe recovery has cleared the exposure", _me(debt).health <= 40.0 and _me(debt).lethal_exposure_seconds > 0.0)
	_run(debt, 2.0, 0.05)
	_check("healing resumes after the safe interval", _me(debt).health > 40.0)
	var parked := _session()
	var other := parked.state.character(&"crew_2")
	other.position = heal_pos
	other.health = 30.0
	_run(parked, 2.0, 0.05)
	_check("parked crew are frozen (no healing)", other.health == 30.0)
	var paused := _session()
	_at(paused, heal_pos)
	_me(paused).health = 30.0
	paused.set_pause_vote(1, true)
	_run(paused, 2.0, 0.05)
	_check("pause freezes healing", _me(paused).health == 30.0)
	var full := _session()
	_at(full, heal_pos)
	_me(full).health = 99.5
	_run(full, 3.0, 0.05)
	_check("healing stops at full health", _me(full).health == MedCare.MAX_HEALTH)
