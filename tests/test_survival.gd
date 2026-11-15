extends SceneTree
## S01/S04: real-time lethal exposure, protection, durable recovery interval and localized airlock pressure.

const MARS := Vector3(200, 0.04, 200)
const CHAMBER := Vector3(22, 0.04, 12)
var _passed := 0
var _total := 0
var _sessions: Array[SessionService] = []
var _recoveries: Dictionary = {}
var _zones: ColonyZones
var _catalog: Dictionary

func _initialize() -> void:
	_zones = ColonyZones.from_manifest("res://data/colony_manifest.json")
	_catalog = StationCatalog.from_manifest("res://data/colony_manifest.json", _zones)
	_timing()
	_protection_and_boundaries()
	_persistence_and_authority()
	_restore_remote_pressure()
	_pressure_and_maintenance()
	for session: SessionService in _sessions:
		session.events.free()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)

func _check(label: String, okay: bool) -> void:
	_total += 1
	if okay:
		_passed += 1
	print(("PASS " if okay else "FAIL ") + label)

func _session(sol_minutes := 20.0) -> SessionService:
	var balance := GameBalance.new()
	balance.maintenance_enabled = false # Isolate S01 timing; test_wear owns continuous-wear cadence.
	var s := SessionService.new(GameConfig.new(), balance, GameEvents.new())
	s.zone_at_position = func(point: Vector3) -> String: return _zones.zone_at_world(point)
	s.outside_test = func(point: Vector3) -> bool: return _zones.zone_at_world(point) == ColonyZones.EXTERIOR
	var state := ColonyState.new_game(balance, 1731, _zones.names)
	state.stations = _catalog.duplicate(true)
	for actor: CharacterState in state.characters.values():
		actor.position = s.config.hub_position
		actor.hub_spot = actor.position
	var clock := SolClock.new()
	clock.sol_minutes = sol_minutes
	s.begin(state, clock)
	s.request(&"claim_character", &"crew_1")
	_sessions.append(s)
	_watch_recovery(s)
	return s

func _watch_recovery(s: SessionService) -> void:
	var key := s.get_instance_id()
	_recoveries[key] = 0
	s.events.character_recovered.connect(func(_id: StringName, _info: Dictionary) -> void: _recoveries[key] = int(_recoveries.get(key, 0)) + 1)

func _at(s: SessionService, point: Vector3) -> void:
	var actor := s.state.character_of_peer(1)
	s.report_position(1, actor.id, point, 0.0)

func _run(s: SessionService, seconds: float, frame: float) -> void:
	var left := seconds
	while left > 1e-8:
		var step := minf(frame, left)
		s.advance(step)
		left -= step

func _count(s: SessionService) -> int:
	return int(_recoveries.get(s.get_instance_id(), 0))

func _timing() -> void:
	for sol: float in [5.0, 20.0, 120.0]:
		for frame: float in [1.0 / 144.0, 0.016, 0.2, 1.0, 10.0]:
			var s := _session(sol)
			var actor := s.state.character_of_peer(1)
			_at(s, MARS)
			_check("immediate entry warning sol%.0f delta%.3f" % [sol, frame], actor.exposure_active and actor.lethal_exposure_seconds == 0.0 and s.survival.status(actor.id).cause.contains("SUIT REQUIRED"))
			_run(s, 3.99, frame)
			_check("healthy through3.99 no doubled gas damage sol%.0f delta%.3f" % [sol, frame], _count(s) == 0 and actor.health == 100.0 and actor.lethal_exposure_seconds >= 3.98)
			s.advance(0.01)
			_check("exactly one recovery at4 sol%.0f delta%.3f" % [sol, frame], _count(s) == 1 and actor.position == actor.hub_spot and actor.lethal_exposure_seconds == 0.0 and not actor.exposure_active)
			_check("recovery retains existing cost ledgers sol%.0f delta%.3f" % [sol, frame], is_equal_approx(float(s.state.ledger.recovery_meals), s.config.recovery_cost_sols * s.balance.meals_per_sol) and float(s.state.ledger.recovery_water_l) > 0.0)
	var capped := _session()
	capped.config.max_ticks_per_frame = 1
	_at(capped, MARS)
	capped.advance(10.0)
	_check("large delta and simulation backlog cannot delay four-second recovery", _count(capped) == 1 and capped.clock.ticks == 1)
	capped.advance(0.0)
	_check("backlog drains without advancing hazard real time", _count(capped) == 1 and capped.clock.ticks == 2)
	var paused := _session()
	_at(paused, MARS)
	paused.advance(1.5)
	paused.set_pause_vote(1, true)
	paused.advance(20.0)
	_check("actual global pause freezes hazard and pressure", is_equal_approx(paused.state.character_of_peer(1).lethal_exposure_seconds, 1.5) and _count(paused) == 0)
	paused.set_pause_vote(1, false)
	paused.advance(2.5)
	_check("unpause resumes existing deadline", _count(paused) == 1)
	var needs := _session()
	needs.state.stores[&"water_l"] = 0.0
	needs.state.stores[&"food_meals"] = 0.0
	var health := needs.state.character_of_peer(1).health
	needs.advance(1.0)
	_check("non-exposure water and food health accounting remains active", needs.state.character_of_peer(1).health < health and _count(needs) == 0)
	var remote := _session()
	remote.peer_joined(2)
	var remote_actor := remote.state.character(&"crew_2")
	remote_actor.owner_peer = 2
	var global_alert_ids: Array[String] = []
	remote.events.system_alert.connect(func(id: StringName, _level: StringName, _text: String) -> void: global_alert_ids.append(String(id)))
	remote.report_position(2, remote_actor.id, MARS, 0.0)
	remote.advance(0.2)
	_check("one peer's fatal exposure does not broadcast a global modal interruption", remote_actor.exposure_active and not remote.state.character_of_peer(1).exposure_active and not global_alert_ids.any(func(id: String) -> bool: return id.begins_with("no_air_")))

func _protection_and_boundaries() -> void:
	var s := _session()
	var actor := s.state.character_of_peer(1)
	actor.suit_on = true
	actor.suit_charge = 100.0
	_at(s, MARS)
	s.advance(3.0)
	_check("functional sealed suit protects and consumes tank once", not actor.exposure_active and actor.lethal_exposure_seconds == 0.0 and actor.suit_charge < 100.0 and float(s.state.ledger.suit_o2_used_kg) > 0.0 and _count(s) == 0)
	for sol: float in [5.0, 120.0]:
		for frame: float in [0.016, 0.2, 1.0, 10.0]:
			var drain := _session(sol)
			var suited := drain.state.character_of_peer(1)
			suited.suit_on = true
			suited.suit_charge = 0.0001
			var initial_kg := suited.suit_charge / 100.0 * drain.balance.suit_o2_capacity_kg
			_at(drain, MARS)
			_run(drain, 4.3, frame)
			_check("reserve exhaustion has no full-frame grace sol%.0f delta%.3f" % [sol, frame], _count(drain) == 1 and suited.suit_charge == 0.0 and is_equal_approx(float(drain.state.ledger.suit_o2_used_kg), initial_kg))
	var broken := _session()
	var huge_frame := _session(5.0)
	var huge_actor := huge_frame.state.character_of_peer(1)
	huge_actor.suit_on = true
	huge_actor.suit_charge = 0.0001
	_at(huge_frame, MARS)
	huge_frame.advance(10.0)
	_check("single actual ten-second frame interleaves reserve failure and recovery", _count(huge_frame) == 1 and huge_actor.suit_charge == 0.0 and huge_actor.position == huge_actor.hub_spot)
	var damaged := broken.state.character_of_peer(1)
	damaged.suit_on = true
	damaged.suit_integrity = 0.0
	_at(broken, MARS)
	_check("failed suit seal cannot protect a charged tank", damaged.exposure_active and damaged.exposure_cause.contains("SEAL FAILED"))
	var boundary := _session()
	var walker := boundary.state.character_of_peer(1)
	_at(boundary, MARS)
	boundary.advance(2.0)
	_at(boundary, walker.hub_spot)
	boundary.advance(1.0)
	_check("breathable entry ends danger without a free full timer", not walker.exposure_active and is_equal_approx(walker.lethal_exposure_seconds, 2.0) and is_equal_approx(walker.exposure_safe_seconds, 1.0))
	_at(boundary, MARS)
	boundary.advance(1.99)
	_check("boundary crossing preserves prior exposure debt", _count(boundary) == 0 and walker.lethal_exposure_seconds > 3.98)
	boundary.advance(0.01)
	_check("repeated boundary use still reaches original cumulative deadline", _count(boundary) == 1)
	var toggles := _session()
	var toggle_actor := toggles.state.character_of_peer(1)
	_at(toggles, MARS)
	toggles.advance(2.0)
	toggle_actor.suit_on = true
	toggles.advance(1.0)
	_check("brief valid protection ends active hazard without clearing debt", not toggle_actor.exposure_active and toggle_actor.lethal_exposure_seconds >= 1.99)
	toggle_actor.suit_on = false
	toggles.advance(2.0)
	_check("equipment toggling cannot refresh the countdown", _count(toggles) == 1)
	var safe := _session()
	var resting := safe.state.character_of_peer(1)
	_at(safe, MARS)
	safe.advance(2.0)
	_at(safe, resting.hub_spot)
	safe.advance(2.0)
	_check("explicit uninterrupted safe interval clears exposure", resting.lethal_exposure_seconds == 0.0 and not resting.exposure_active and safe.safe_to_switch(resting))
	_at(safe, Vector3(50, 0.04, 27))
	safe.advance(5.0)
	_check("enclosed Garden dome is breathable", not resting.exposure_active and _count(safe) == 0)

func _persistence_and_authority() -> void:
	var game := GameServices.new()
	game.balance = GameBalance.new()
	game.balance.maintenance_enabled = false
	game.session.balance = game.balance
	game.saves = SaveService.new(ProjectSettings.globalize_path("res://tests/tmp/survival"), "fixture")
	game.saves.delete_all()
	# S01 reload timing needs an unsuited astronaut from the Med Bay, not the tutorial start (suited, outside).
	game.config.tutorial_start_outside = false
	game.config.tutorial_start_suited = false
	game.start_new_game(729)
	_watch_recovery(game.session)
	var actor := game.local_character()
	game.report_position(actor.id, MARS, 0.0)
	game.session.advance(2.5)
	_check("ongoing exposure disk write", game.save_now(&"survival_fixture") == OK)
	game.restore(game.saves.read().payload)
	actor = game.local_character()
	_check("reload retains active encounter and cumulative real seconds", actor.position == MARS and actor.exposure_active and is_equal_approx(actor.lethal_exposure_seconds, 2.5))
	game.session.advance(1.49)
	_check("reload grants no new full timer", _count(game.session) == 0 and actor.lethal_exposure_seconds > 3.98)
	game.session.advance(0.01)
	_check("reload encounter recovers exactly once at remaining deadline", _count(game.session) == 1 and actor.position == actor.hub_spot)
	game.report_position(actor.id, MARS, 0.0)
	game.session.advance(2.0)
	game.report_position(actor.id, actor.hub_spot, 0.0)
	game.session.advance(1.0)
	game.save_now(&"safe_interval_fixture")
	game.restore(game.saves.read().payload)
	actor = game.local_character()
	_check("reload preserves partial safe interval without offline recovery", is_equal_approx(actor.lethal_exposure_seconds, 2.0) and is_equal_approx(actor.exposure_safe_seconds, 1.0))
	game.session.advance(0.99)
	_check("reload cannot immediately clear pending exposure debt", actor.lethal_exposure_seconds >= 1.99)
	game.session.advance(0.01)
	_check("persisted safe interval finishes after remaining real time", actor.lethal_exposure_seconds == 0.0 and actor.exposure_safe_seconds == 0.0)
	var host := _session()
	host.survival.debug_trigger_airlock_fault()
	_at(host, CHAMBER)
	host.advance(1.0)
	var replica := _session()
	replica.state.assign_from(host.state.to_dict())
	replica.apply_replica(host.replica_dict())
	var before := replica.state.character(&"crew_1").lethal_exposure_seconds
	replica.advance(30.0)
	_check("replicated client cannot advance death, pressure or wear", not replica.authoritative and replica.state.character(&"crew_1").lethal_exposure_seconds == before and _count(replica) == 0 and replica.state.pressure == host.state.pressure)
	var replica_snapshot := replica.state.to_dict()
	var direct := replica.request(&"vote_pause", &"", {"paused": true})
	var moved := replica.report_position(1, &"crew_1", replica.config.hub_position, 0.0)
	replica.note_airlock_cycle()
	replica.recover_character(&"crew_1")
	_check("direct replica backend entry points cannot mutate host-owned gameplay", not direct.ok and direct.reason == &"host_only" and not moved and replica.state.to_dict() == replica_snapshot and _count(replica) == 0)
	_check("debug fault hook is host only and not a network action", not replica.survival.debug_trigger_airlock_fault() and host.request(&"debug_airlock_fault").reason == &"unknown_action")
	game.saves.delete_all()
	game.free()

func _restore_remote_pressure() -> void:
	var game := GameServices.new()
	game.balance = GameBalance.new()
	game.balance.maintenance_enabled = false
	game.session.balance = game.balance
	game.saves = SaveService.new(ProjectSettings.globalize_path("res://tests/tmp/survival_remote"), "fixture")
	game.saves.delete_all()
	game.start_new_game(821)
	var saved := game.snapshot()
	saved.colony.pressure = {"version": 1, "airlock_kpa": 0.6, "airlock_breathable": false, "leaking": true, "repressurizing": false}
	saved.colony.repair.tasks.T12.maintenance_fault = true
	saved.colony.repair.tasks.T12.condition = 0.15
	for id: String in ["crew_2", "crew_3", "crew_4"]:
		var record: Dictionary = saved.colony.characters[id]
		record.position = [CHAMBER.x, CHAMBER.y, CHAMBER.z]
		record.lethal_exposure_seconds = 0.0
		record.health = 43.0
		record.suit_charge = 29.0
		record.suit_on = id != "crew_2"
		record.suit_integrity = 0.0 if id == "crew_4" else 1.0
	game.restore(saved)
	var unprotected := game.state().character(&"crew_2")
	var protected := game.state().character(&"crew_3")
	var broken := game.state().character(&"crew_4")
	_check("restore retains unprotected remote chamber encounter even with zero timer", unprotected.position == CHAMBER and unprotected.outside and unprotected.lethal_exposure_seconds == 0.0)
	_check("restore parks healthy sealed charged remote crew safely", protected.position == protected.hub_spot and not protected.outside and protected.health == 43.0 and protected.suit_charge == 29.0)
	_check("restore retains broken-seal remote chamber encounter", broken.position == CHAMBER and broken.outside and broken.suit_integrity == 0.0 and broken.health == 43.0)
	_check("restore uses saved local pressure before parking decisions", is_equal_approx(float(game.state().pressure.airlock_kpa), 0.6) and not bool(game.state().pressure.airlock_breathable))
	var garden_saved := game.snapshot()
	garden_saved.colony.characters.crew_2.position = [50, 0.04, 27]
	garden_saved.colony.characters.crew_2.outside = true # Deliberately stale legacy lighting-derived flag.
	game.restore(garden_saved)
	unprotected = game.state().character(&"crew_2")
	_check("Garden dome remains safe when restoring a local airlock failure", unprotected.position == unprotected.hub_spot and not unprotected.outside and unprotected.health == 43.0)
	game.saves.delete_all()
	game.free()

func _pressure_and_maintenance() -> void:
	var s := _session()
	# 2026-11-14: a new game's T12 seal is the broken part (BP08) and leaks until its puzzle is solved. This scenario is
	# S03/S04 wear on a seal that was already repaired once, so the fixture starts from a fixed seal.
	s.state.repair.tasks.T12.first_completed = true
	_check("controlled debug seal fault exists", s.survival.debug_trigger_airlock_fault())
	var actor := s.state.character_of_peer(1)
	_at(s, Vector3(16.4, 0.04, 9.55))
	_check("working suit rack remains on breathable safe side", not actor.exposure_active and s.survival.breathable_at(actor.position))
	_at(s, Vector3(50, 0.04, 27))
	_check("local seal fault does not depressurize Garden dome", not actor.exposure_active)
	_at(s, CHAMBER)
	_check("failed chamber has immediate localized danger cause", actor.exposure_active and actor.exposure_area == "Airlock exit vestibule" and s.survival.status(actor.id).cause.contains("AIRLOCK"))
	s.advance(4.0)
	_check("unsuited chamber entry recovers on four-second schedule", _count(s) == 1)
	var chamber_loss := float(s.state.ledger.airlock_o2_lost_kg)
	s.survival.set_airlock_door_open(902, true)
	s.survival.set_airlock_door_open(902, true)
	s.advance(1.0)
	_check("local door pressure model does not duplicate global gas loss", float(s.state.ledger.airlock_o2_lost_kg) == chamber_loss and float(s.state.ledger.airlock_cycles) == 0.0)
	s.note_airlock_cycle()
	s.advance(0.2)
	_check("existing global airlock cycle ledger still applies exactly once", float(s.state.ledger.airlock_cycles) == 1.0 and float(s.state.ledger.airlock_o2_lost_kg) > chamber_loss)
	s.survival.set_airlock_door_open(902, false)
	_at(s, CharacterState._v3(s.state.stations.repair_t12.position))
	_check("seal maintenance requires field engineer even from safe side", s.request(&"maintenance_start", &"repair_t12", {"generation": int(s.state.repair.tasks.T12.fault_generation)}).reason == &"wrong_specialty")
	_at(s, actor.hub_spot)
	s.request(&"claim_character", &"crew_4")
	var engineer := s.state.character_of_peer(1)
	engineer.suit_on = true
	engineer.suit_charge = 100.0
	_at(s, CHAMBER)
	s.advance(4.5)
	_check("properly suited engineer can enter failed volume", not engineer.exposure_active and _count(s) == 1 and engineer.suit_charge < 100.0)
	_at(s, CharacterState._v3(s.state.stations.repair_t12.position))
	var task: Dictionary = s.state.repair.tasks.T12
	var milestone := bool(task.first_completed)
	var room_milestone := bool(s.state.repair.rooms.hangar.first_completed)
	var parts := s.state.parts
	var repair := s.request(&"maintenance_start", &"repair_t12", {"generation": int(task.fault_generation)})
	_check("field engineer starts host-timed safe-side seal maintenance", repair.ok and float(repair.changes.duration_seconds) >= 20.0 and float(repair.changes.duration_seconds) <= 45.0)
	_run(s, s.balance.maintenance_repair_seconds, 0.2)
	_check("seal service stops leak without puzzle milestone or reward", not bool(task.maintenance_fault) and is_equal_approx(float(task.condition), 1.0) and bool(task.first_completed) == milestone and bool(s.state.repair.rooms.hangar.first_completed) == room_milestone and s.state.parts == parts)
	_check("sealed chamber enters readable repressurization", bool(s.survival.pressure_info().repressurizing) and not bool(s.survival.pressure_info().breathable))
	s.advance(s.config.airlock_pressure_recovery_seconds)
	_check("sealed chamber returns to safe pressure over time", bool(s.survival.pressure_info().breathable) and not bool(s.survival.pressure_info().repressurizing))
	s.request(&"claim_character", &"crew_1") # Refused away from hub; ownership/role still enforced.
	_check("repair does not create a role-switch bypass", s.state.character_of_peer(1).id == &"crew_4")
	s.survival.set_airlock_door_open(902, true)
	_check("first outer-door motion invalidates safe pressure", not bool(s.survival.pressure_info().breathable))
	s.survival.set_airlock_door_open(902, false)
	_check("shutting outer door is not instantly safe", not bool(s.survival.pressure_info().breathable) and bool(s.survival.pressure_info().repressurizing))
	s.survival.debug_trigger_airlock_fault()
	engineer.suit_on = false
	_at(s, Vector3(22, 0.04, 10.31))
	s.advance(1.0)
	_at(s, Vector3(22, 0.04, 10.25))
	_check("door boundary hysteresis prevents tiny-step warning flicker", engineer.exposure_active and engineer.in_airlock_pressure_volume)
	s.survival.set_airlock_door_open(901, true)
	_check("inner egress flag does not falsify failed pressure safety", bool(s.survival.pressure_info().inner_open) and not bool(s.survival.pressure_info().breathable))
	_at(s, Vector3(22, 0.04, 9.9))
	_check("safe inner-side escape remains available", not engineer.exposure_active and engineer.lethal_exposure_seconds > 0.0)
