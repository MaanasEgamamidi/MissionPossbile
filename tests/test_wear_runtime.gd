extends SceneTree
## S03 behavioral checks: real-second wear, maintenance ownership, durable state and mapped repairs.

var _passed := 0
var _total := 0
var _sessions: Array[SessionService] = []
var _zones: ColonyZones
var _stations: Dictionary

func _initialize() -> void:
	_zones = ColonyZones.from_manifest("res://data/colony_manifest.json")
	_stations = StationCatalog.from_manifest("res://data/colony_manifest.json", _zones)
	_migration()
	_timing_and_pause()
	_maintenance_and_recurrence()
	_operator_rules()
	_legacy_inventory()
	_persistence_and_replication()
	_puzzle_completion_hook()
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
	var state := ColonyState.new_game(session.balance, 8831, _zones.names)
	state.stations = _stations.duplicate(true)
	session.zone_at_position = func(position: Vector3) -> String: return _zones.zone_at_world(position)
	session.outside_test = func(position: Vector3) -> bool: return _zones.zone_at_world(position) == ColonyZones.EXTERIOR
	for actor: CharacterState in state.characters.values():
		actor.hub_spot = session.config.hub_position
		actor.position = actor.hub_spot
	session.begin(state, SolClock.new())
	state.character(&"crew_1").owner_peer = 1
	_sessions.append(session)
	return session

func _at(session: SessionService, task_id: String, peer := 1) -> void:
	var actor := session.state.character_of_peer(peer)
	session.report_position(peer, actor.id, CharacterState._v3(session.state.stations[RepairCatalog.anchor_id(task_id)].position), 0.0)

func _start(session: SessionService, task_id: String, peer := 1) -> ActionResult:
	return session.request(&"maintenance_start", StringName(RepairCatalog.anchor_id(task_id)), {"generation": int(session.state.repair.tasks[task_id].fault_generation)}, peer)

func _migration() -> void:
	var s := _session()
	_check("new operational condition does not award any puzzle milestone", s.state.repair.tasks.values().all(func(task: Dictionary) -> bool: return float(task.condition) == 1.0 and float(task.progress) == 0.0 and not bool(task.first_completed) and not bool(task.maintenance_fault)))
	var old: Dictionary = s.state.repair.duplicate(true)
	old.version = 1
	old.erase("maintenance_schema")
	for task: Dictionary in old.tasks.values():
		task.erase("maintenance_schema")
		task.condition = 0.0
		task.erase("maintenance_fault")
	old.tasks.T01.progress = 0.5
	old.tasks.T01.puzzle_state = {"partial": 1}
	old.tasks.T02.fault_generation = 3
	old.tasks.T02.condition = 0.2
	old.tasks.T02.first_completed = true
	old.collected_cassettes = ["cassette_med_bay"]
	old.seen_beauty_shots = ["command_center"]
	var restored := RepairCatalog.restore(old, s.state.rng_seed)
	_check("v1 placeholder condition migrates operational without achievement", restored.version == 2 and restored.tasks.T03.condition == 1.0 and not restored.tasks.T03.first_completed)
	_check("migration preserves a real partial puzzle", restored.tasks.T01.progress == 0.5 and restored.tasks.T01.puzzle_state == {"partial": 1} and restored.tasks.T01.condition == 0.0)
	_check("migration preserves explicit fault generations and milestone", restored.tasks.T02.fault_generation == 3 and restored.tasks.T02.condition == 0.2 and restored.tasks.T02.maintenance_fault and restored.tasks.T02.first_completed)
	_check("migration preserves collection and beauty history", restored.collected_cassettes == old.collected_cassettes and restored.seen_beauty_shots == old.seen_beauty_shots)
	_check("migration does not mutate old payload", old.tasks.T03.condition == 0.0 and not old.has("maintenance_schema"))

func _timing_and_pause() -> void:
	var s := _session()
	var before := s.state.stores.duplicate()
	var ledger := s.state.ledger.duplicate()
	s.wear_runtime.advance(s, 30.0)
	_check("condition measurably changes within thirty real seconds", is_equal_approx(float(s.state.repair.tasks.T01.condition), 0.9375))
	_check("all twelve systems wear without presentation nodes", s.state.repair.tasks.values().all(func(task: Dictionary) -> bool: return is_equal_approx(float(task.condition), 0.9375)))
	s.wear_runtime.advance(s, 90.0)
	_check("default warning is reached near two minutes", is_equal_approx(float(s.state.repair.tasks.T01.condition), 0.75) and s.state.repair.tasks.T01.warning_active and not s.state.repair.tasks.T01.maintenance_fault)
	s.wear_runtime.advance(s, 120.0)
	_check("default maintenance fault is reached near four minutes", is_equal_approx(float(s.state.repair.tasks.T01.condition), 0.5) and s.state.repair.tasks.T01.maintenance_fault and s.state.repair.tasks.T01.fault_generation == 2)
	s.wear_runtime.advance(s, 240.0)
	_check("one unattended fault advances generation only once", s.state.repair.tasks.T01.fault_generation == 2 and s.state.repair.tasks.T01.condition == 0.0)
	_check("wear never directly changes resource ledgers or stores", s.state.stores == before and s.state.ledger == ledger)
	var paused := s.state.repair.duplicate(true)
	s.set_pause_vote(1, true)
	s.wear_runtime.advance(s, 90.0)
	_check("genuine global pause freezes wear", s.state.repair == paused)
	s.set_pause_vote(1, false)
	var large := _session()
	var small := _session()
	large.wear_runtime.advance(large, 240.0)
	for i in 2400:
		small.wear_runtime.advance(small, 0.1)
	_check("low and high frame rates reach the same condition and fault", is_equal_approx(float(large.state.repair.tasks.T04.condition), float(small.state.repair.tasks.T04.condition)) and large.state.repair.tasks.T04.fault_generation == small.state.repair.tasks.T04.fault_generation)
	var slow_sol := _session()
	var fast_sol := _session()
	slow_sol.clock.sol_minutes = 120.0
	fast_sol.clock.sol_minutes = 5.0
	slow_sol.advance(30.0)
	fast_sol.advance(30.0)
	_check("session wears by real time independent of sol length", is_equal_approx(float(slow_sol.state.repair.tasks.T03.condition), float(fast_sol.state.repair.tasks.T03.condition)) and is_equal_approx(float(fast_sol.state.repair.tasks.T03.condition), 0.9375))

func _maintenance_and_recurrence() -> void:
	var s := _session()
	s.balance.maintenance_wear_per_second = 0.0
	var task: Dictionary = s.state.repair.tasks.T02
	task.condition = 0.4
	task.maintenance_fault = true
	task.fault_generation = 4
	task.progress = 0.375
	task.puzzle_state = {"pending": 3}
	s.state.repair.tasks.T01.condition = 0.3
	s.state.repair.seen_beauty_shots = ["med_bay"]
	var parts := s.state.parts
	_at(s, "T02")
	var started := _start(s, "T02")
	_check("maintenance starts with configured twenty-second duration", started.ok and started.changes.duration_seconds == 20.0 and s.wear_runtime.status("T02").active)
	s.wear_runtime.advance(s, 19.95)
	_check("maintenance cannot finish early", task.condition == 0.4 and s.wear_runtime.status("T02").active and float(s.wear_runtime.status("T02").progress) < 1.0)
	s.wear_runtime.advance(s, 0.05)
	_check("maintenance restores only the mapped condition and fault", task.condition == 1.0 and not task.maintenance_fault and s.state.repair.tasks.T01.condition == 0.3 and not s.wear_runtime.status("T02").active)
	_check("maintenance leaves task progress and puzzle state unchanged", task.progress == 0.375 and task.puzzle_state == {"pending": 3})
	_check("maintenance does not award milestones rewards or replay beauty shots", not task.first_completed and not s.state.repair.rooms.command_center.first_completed and s.state.parts == parts and s.state.repair.seen_beauty_shots == ["med_bay"])
	_check("repair retains generation and starts saved cooldown", task.fault_generation == 4 and task.maintenance_cooldown_seconds == 15.0)
	s.balance.maintenance_wear_per_second = 1.0 / 480.0
	s.wear_runtime.advance(s, 14.0)
	_check("cooldown prevents immediate rewear", task.condition == 1.0 and is_equal_approx(float(task.maintenance_cooldown_seconds), 1.0))
	s.wear_runtime.advance(s, 241.0)
	_check("a later neglected repair can fault again without achievement reset", task.maintenance_fault and task.fault_generation == 5 and not task.first_completed and task.progress == 0.0 and s.state.repair.seen_beauty_shots == ["med_bay"])
	_check("stale maintenance generation is rejected", s.request(&"maintenance_start", &"repair_t02", {"generation": 4}).reason == &"stale_fault")
	_check("debug fault hook is not exposed as a player action", s.request(&"force_fault", &"repair_t01").reason == &"unknown_action")

func _operator_rules() -> void:
	var s := _session()
	s.state.repair.tasks.T02.condition = 0.8
	s.state.repair.tasks.T01.condition = 0.8
	s.peer_joined(2)
	s.state.character(&"crew_2").owner_peer = 2
	_at(s, "T02", 2)
	_check("wrong specialist cannot start maintenance", _start(s, "T02", 2).reason == &"wrong_specialty")
	_at(s, "T02")
	_at(s, "T01", 2)
	_check("specialist and helper maintain different tasks concurrently", _start(s, "T02").ok and _start(s, "T01", 2).ok and s.wear_runtime.jobs.size() == 2)
	_check("another peer cannot cancel a maintenance job", s.request(&"maintenance_cancel", &"repair_t02", {"generation": 1}, 2).reason == &"not_owner")
	_check("a future puzzle cannot claim equipment being maintained", s.request(&"task_claim", &"repair_t02", {"generation": 1}).reason == &"task_busy")
	var actor := s.state.character_of_peer(1)
	actor.position = s.config.hub_position
	s.wear_runtime.prune(s)
	_check("losing reach cancels maintenance", not s.wear_runtime.jobs.has("T02"))
	_at(s, "T02")
	_start(s, "T02")
	actor.specialty = &"biology_food"
	s.wear_runtime.prune(s)
	_check("role is revalidated during maintenance", not s.wear_runtime.jobs.has("T02"))
	actor.specialty = &"electrical_comms"
	_start(s, "T02")
	actor.exposure_active = true
	s.wear_runtime.prune(s)
	_check("fatal atmospheric danger cancels backend maintenance without UI", not s.wear_runtime.jobs.has("T02"))
	var normal_outside := s.outside_test
	var danger_origin := actor.position
	s.outside_test = func(point: Vector3) -> bool: return point.distance_to(danger_origin) < 0.1
	_check("unsafe atmospheric entry blocks a direct maintenance request", _start(s, "T02").reason == &"unsafe_maintenance")
	s.outside_test = normal_outside
	s.survival.refresh_all()
	_start(s, "T02")
	actor.health = 0.0
	s.wear_runtime.prune(s)
	_check("death cancels maintenance", not s.wear_runtime.jobs.has("T02"))
	actor.health = 100.0
	_start(s, "T02")
	s.peer_left(2)
	_check("disconnect releases helper maintenance", not s.wear_runtime.jobs.has("T01"))
	s._release(actor)
	_check("crew release clears the operator", s.wear_runtime.jobs.is_empty())
	_check("cleanup remains possible without an actor", s.request(&"maintenance_cancel", &"repair_t02", {"generation": 1}).ok)

func _legacy_inventory() -> void:
	var s := _session()
	s.state.equipment.cleaner.condition = 1.0
	var other := {}
	for id: String in ColonyState.EQUIPMENT_IDS:
		if id != "cleaner":
			other[id] = s.state.equipment[id].duplicate(true)
	var dust := s.state.panel_dust.duplicate()
	s.wear_runtime.advance(s, 240.1)
	_check("repairable legacy cleaner wears and becomes nonfunctional", float(s.state.equipment.cleaner.condition) < s.balance.equipment_min_condition and not PowerModel.cleaner_working(s.state, s.balance))
	_check("unrepairable legacy units receive no second wear ticker", other.keys().all(func(id: String) -> bool: return s.state.equipment[id] == other[id]))
	_check("existing panel dust ticker is not duplicated", s.state.panel_dust == dust)
	var actor := s.state.character_of_peer(1)
	s.report_position(1, actor.id, CharacterState._v3(s.state.stations.sf_solar_tracker.position), 0.0)
	var repaired := s.request(&"repair_cleaner", &"sf_solar_tracker")
	_check("cleaner repair grants durable grace immediately", repaired.ok and s.state.repair.legacy_maintenance.cleaner.maintenance_cooldown_seconds == 15.0)
	s.wear_runtime.advance(s, 1.0)
	_check("existing cleaner repair restores only its own equipment and gets grace", repaired.ok and s.state.equipment.cleaner.condition == 1.0 and s.state.repair.legacy_maintenance.cleaner.maintenance_cooldown_seconds > 0.0 and other.keys().all(func(id: String) -> bool: return s.state.equipment[id] == other[id]))

func _persistence_and_replication() -> void:
	var host := _session()
	_at(host, "T01")
	host.wear_runtime.advance(host, 60.0)
	_start(host, "T01")
	var saved := host.state.to_dict()
	var restored := ColonyState.from_dict(JSON.parse_string(JSON.stringify(saved)))
	_check("wear condition elapsed and flags survive serialization", restored.repair.tasks.T01.condition == host.state.repair.tasks.T01.condition and restored.repair.tasks.T01.wear_elapsed_seconds == 60.0 and restored.repair.maintenance_schema == 1)
	_check("maintenance operators never enter disk state", not saved.repair.has("jobs") and not saved.repair.tasks.T01.has("operator"))
	for i in 2:
		var replica := _session()
		replica.state.assign_from(saved)
		replica.apply_replica(host.replica_dict())
		_check("late client %d reconstructs the current job" % i, replica.wear_runtime.status("T01").active)
		var before := replica.state.repair.duplicate(true)
		replica.wear_runtime.advance(replica, 120.0)
		var denied := _start(replica, "T01")
		_check("client %d never advances authoritative wear" % i, not replica.authoritative and denied.reason == &"host_only" and not replica.wear_runtime.force_fault(replica, "T01") and replica.state.repair == before)
	_check("two clients cannot double the host wear", host.state.repair.tasks.T01.wear_elapsed_seconds == 60.0)
	var resumed := _session()
	resumed.begin(restored, SolClock.new())
	_check("restart clears transient maintenance ownership", resumed.wear_runtime.jobs.is_empty())
	host.wear_runtime.restore_task(host, "T01", int(host.state.repair.tasks.T01.fault_generation))
	host.wear_runtime.advance(host, 7.0)
	var grace := ColonyState.from_dict(host.state.to_dict())
	resumed.begin(grace, SolClock.new())
	_check("reload preserves remaining repair grace", is_equal_approx(float(resumed.state.repair.tasks.T01.maintenance_cooldown_seconds), 8.0))
	resumed.wear_runtime.advance(resumed, 9.0)
	_check("only real resumed time consumes grace and condition", is_equal_approx(float(resumed.state.repair.tasks.T01.condition), 1.0 - 1.0 / 480.0))

func _puzzle_completion_hook() -> void:
	var s := _session()
	_at(s, "T01")
	s.wear_runtime.force_fault(s, "T01")
	s.repair_runtime.register_rule("T01", func(_task: Dictionary, _move: Dictionary) -> Dictionary: return {"accepted": true, "puzzle_state": {"test": true}, "progress": 1.0, "complete": true})
	var generation := int(s.state.repair.tasks.T01.fault_generation)
	s.request(&"task_claim", &"repair_t01", {"generation": generation})
	var result := s.request(&"task_move", &"repair_t01", {"generation": generation, "move": "test", "value": 1})
	_check("a real host validator completion shares mapped maintenance restoration", result.ok and s.state.repair.tasks.T01.first_completed and s.state.repair.tasks.T01.condition == 1.0 and not s.state.repair.tasks.T01.maintenance_fault and s.state.repair.tasks.T01.maintenance_cooldown_seconds == 15.0)
