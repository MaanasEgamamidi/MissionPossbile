extends SceneTree
## F02-F04 behavioral checks; synthetic host rule only, no production puzzle implementation.

var _total := 0
var _passed := 0
var _sessions: Array[SessionService] = []

func _initialize() -> void:
	_roles()
	_validation_and_leases()
	_completion_and_wear()
	_persistence_and_replication()
	_safe_switching()
	_disconnect_exposure()
	for session: SessionService in _sessions:
		session.events.free()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)

func _check(label: String, okay: bool) -> void:
	_total += 1
	if okay:
		_passed += 1
		print("PASS " + label)
	else:
		print("FAIL " + label)

func _session() -> SessionService:
	var session := SessionService.new(GameConfig.new(), GameBalance.new(), GameEvents.new())
	var state := ColonyState.new_game(session.balance, 927)
	for task_id: String in RepairCatalog.TASKS:
		var task: Dictionary = state.repair.tasks[task_id]
		state.stations[task.anchor_id] = {"kind": "repair_task", "zone": RepairCatalog.ROOMS[task.room_id].zones[0],
			"room_id": task.room_id, "task_id": task_id, "specialty": "", "position": [0, 0, 0]}
	for actor: CharacterState in state.characters.values():
		actor.hub_spot = session.config.hub_position
		actor.position = Vector3.ZERO
	session.begin(state, SolClock.new())
	_sessions.append(session)
	return session

func _claim(session: SessionService, task_id: String, peer := 1) -> ActionResult:
	return session.request(&"task_claim", StringName(RepairCatalog.anchor_id(task_id)), {"generation": int(session.state.repair.tasks[task_id].fault_generation)}, peer)

func _move(session: SessionService, task_id: String, value: int, peer := 1) -> ActionResult:
	return session.request(&"task_move", StringName(RepairCatalog.anchor_id(task_id)), {"generation": int(session.state.repair.tasks[task_id].fault_generation), "move": "step", "value": value}, peer)

func _rule(task: Dictionary, move: Dictionary) -> Dictionary:
	var expected := int((task.puzzle_state as Dictionary).get("step", 0)) + 1
	if String(move.move) != "step" or int(move.value) != expected or expected > 2:
		return {"accepted": false}
	return {"accepted": true, "puzzle_state": {"step": expected}, "progress": float(expected) / 2.0, "complete": expected == 2}

func _roles() -> void:
	var s := _session()
	_check("six room and twelve task identities", s.state.repair.rooms.size() == 6 and s.state.repair.tasks.size() == 12)
	for task_id: String in RepairCatalog.TASKS:
		var task: Dictionary = s.state.repair.tasks[task_id]
		for actor: CharacterState in s.state.characters.values():
			actor.owner_peer = 1
			var result := s.submit(ActionRequest.make("role_%s_%s" % [task_id, actor.id], 1, actor.id, &"task_claim", StringName(task.anchor_id), {"generation": 1}))
			var allowed := String(task.required_specialty) == "general" or String(actor.specialty) == String(task.required_specialty)
			_check("%s access %s" % [task_id, actor.specialty], result.ok == allowed and (allowed or result.reason == &"wrong_specialty"))
			s.repair_runtime.clear_session()
			actor.owner_peer = 0

func _validation_and_leases() -> void:
	var s := _session()
	var a := s.state.character(&"crew_1")
	a.owner_peer = 1
	s.peer_joined(2)
	s.state.character(&"crew_2").owner_peer = 2
	_check("host can claim", _claim(s, "T01").ok)
	_check("same puzzle has one operator", _claim(s, "T01", 2).reason == &"task_busy")
	_check("helper can operate other general puzzle", _claim(s, "T03", 2).ok)
	s.repair_runtime.clear_session()
	_check("specialist and helper work concurrently in same room", _claim(s, "T02").ok and _claim(s, "T01", 2).ok and s.repair_runtime.locks.has("T01") and s.repair_runtime.locks.has("T02"))
	s.repair_runtime.clear_session()
	_claim(s, "T01")
	# Broken parts (2026-11-14): ten tasks now have production rules (scripts/tasks/puzzles/). T05 and T07 still have
	# none, so the "no rule installed" path is checked on T05 (biology_food) instead of T01.
	a.specialty = &"biology_food"
	_claim(s, "T05")
	_check("no production rule accepts completion", _move(s, "T05", 2).reason == &"not_available_yet")
	a.specialty = &"electrical_comms"
	_check("untrusted completion boolean rejected", s.request(&"task_move", &"repair_t01", {"generation": 1, "move": "step", "value": 2, "complete": true}).reason == &"bad_request")
	s.state.stations["repair_t01"].room_id = "med_bay"
	_check("wrong room metadata rejected", _claim(s, "T01").reason == &"wrong_room")
	s.state.stations["repair_t01"].room_id = "command_center"
	s.zone_at_position = func(_position: Vector3) -> String: return "Med Bay"
	_check("wrong physical room rejected", _claim(s, "T01").reason == &"wrong_room")
	s.zone_at_position = Callable()
	_check("reclaim after room corrected", _claim(s, "T01").ok)
	s.repair_runtime.advance(s, RepairRuntime.CLAIM_SECONDS + 0.1)
	_check("idle lease expires", not s.repair_runtime.locks.has("T01"))
	_check("new operator after timeout", _claim(s, "T01", 2).ok)
	s.peer_left(2)
	_check("disconnect releases all owned puzzles", not s.repair_runtime.locks.has("T01") and not s.repair_runtime.locks.has("T03"))
	_claim(s, "T01")
	a.position = Vector3(100, 0, 100)
	s.repair_runtime.prune(s)
	_check("loss of reach releases claim", not s.repair_runtime.locks.has("T01"))
	a.position = Vector3.ZERO
	_claim(s, "T02")
	a.specialty = &"biology_food"
	_check("role revalidated on move", _move(s, "T02", 1).reason == &"wrong_specialty" and not s.repair_runtime.locks.has("T02"))
	_check("role revalidated on resume", s.request(&"task_resume", &"repair_t02", {"generation": 1}).reason == &"wrong_specialty")
	a.specialty = &"electrical_comms"
	_claim(s, "T01")
	a.health = 0.0
	s.repair_runtime.prune(s)
	_check("death releases puzzle", not s.repair_runtime.locks.has("T01"))
	a.health = 50.0
	_claim(s, "T01")
	s.recover_character(a.id)
	_check("recovery releases puzzle", s.repair_runtime.locks.is_empty())

func _completion_and_wear() -> void:
	var s := _session()
	s.state.character(&"crew_1").owner_peer = 1
	for task_id: String in ["T01", "T02"]:
		s.repair_runtime.register_rule(task_id, _rule)
		_claim(s, task_id)
		_check("%s rejects invalid move" % task_id, _move(s, task_id, 2).reason == &"invalid_move")
		_check("%s accepted partial progress" % task_id, _move(s, task_id, 1).ok and float(s.state.repair.tasks[task_id].progress) == 0.5)
		var req := ActionRequest.make("finish_" + task_id, 1, &"crew_1", &"task_move", StringName(RepairCatalog.anchor_id(task_id)), {"generation": 1, "move": "step", "value": 2})
		var result := s.submit(req)
		_check("%s host establishes first milestone" % task_id, result.ok and result.changes.first_completion and s.state.repair.tasks[task_id].first_completed)
		_check("%s duplicate applies once" % task_id, s.submit(req).duplicate and not s.repair_runtime.locks.has(task_id))
		_claim(s, task_id)
		_check("%s fresh replay cannot complete again" % task_id, _move(s, task_id, 2).reason == &"task_complete")
	_check("both task milestones complete room", s.state.repair.rooms.command_center.first_completed)
	s.state.repair.seen_beauty_shots.append("command_center")
	s.repair_runtime.begin_fault(s.state, "T01", 17, 0.3)
	_check("wear separates current condition from achievement", float(s.state.repair.tasks.T01.condition) == 0.3 and s.state.repair.tasks.T01.first_completed and s.state.repair.rooms.command_center.first_completed)
	_check("wear preserves shot history", s.state.repair.seen_beauty_shots == ["command_center"])
	_check("stale generation rejected", s.request(&"task_claim", &"repair_t01", {"generation": 1}).reason == &"stale_fault")
	_check("new generation can be claimed", _claim(s, "T01").ok)

func _persistence_and_replication() -> void:
	var s := _session()
	s.state.character(&"crew_1").owner_peer = 1
	s.repair_runtime.register_rule("T01", _rule, true)
	_claim(s, "T01")
	_move(s, "T01", 1)
	s.state.character(&"crew_1").health = 41.25
	s.state.character(&"crew_1").suit_charge = 12.5
	s.state.character(&"crew_1").outside = true
	s.state.character(&"crew_1").lethal_exposure_seconds = 2.75
	s.state.repair.collected_cassettes = ["cassette_command_center"]
	s.state.repair.seen_beauty_shots = ["command_center"]
	var saved := s.state.to_dict()
	var unsafe_partial: Dictionary = saved.repair.duplicate(true)
	unsafe_partial.tasks.T01.resume_supported = false
	_check("unsupported partial puzzle resets only in disk projection", RepairCatalog.for_save(unsafe_partial).tasks.T01.progress == 0.0 and RepairCatalog.for_save(unsafe_partial).tasks.T01.puzzle_state.is_empty() and unsafe_partial.tasks.T01.progress == 0.5)
	_check("safe partial puzzle persists in disk projection", RepairCatalog.for_save(saved.repair).tasks.T01.progress == 0.5)
	_check("disk state has no operator leases", not JSON.stringify(saved.repair).contains("expires") and not JSON.stringify(saved.repair).contains("locks"))
	var old := saved.duplicate(true)
	old.erase("repair")
	old.crops = {"fixture": {"age": 17}}
	var migrated := ColonyState.from_dict(old)
	_check("old save additive defaults preserve colony", migrated.repair.tasks.size() == 12 and migrated.crops == old.crops and migrated.parts == s.state.parts and migrated.stores == s.state.stores)
	var restored := ColonyState.from_dict(JSON.parse_string(JSON.stringify(saved)))
	_check("partial puzzle progress and seed roundtrip", int(restored.repair.tasks.T01.puzzle_state.get("step", -1)) == 1 and restored.repair.tasks.T01.puzzle_seed == s.state.repair.tasks.T01.puzzle_seed and restored.repair.tasks.T01.fault_generation == 1)
	_check("collection and shot history roundtrip", restored.repair.collected_cassettes == ["cassette_command_center"] and restored.repair.seen_beauty_shots == ["command_center"])
	_check("reload retains encounter health and equipment", restored.character(&"crew_1").health == 41.25 and restored.character(&"crew_1").suit_charge == 12.5 and restored.character(&"crew_1").outside)
	_check("reload and replica retain exposure accumulator", restored.character(&"crew_1").lethal_exposure_seconds == 2.75)
	var late := _session()
	late.state.assign_from(saved)
	late.apply_replica(s.replica_dict())
	_check("late join reconstructs partial puzzle and lease", late.state.repair.tasks.T01.progress == 0.5 and late.repair_runtime.locks.has("T01"))
	_check("late join retains exposure", late.state.character(&"crew_1").lethal_exposure_seconds == 2.75)
	late.begin(restored, SolClock.new())
	_check("restart drops transient lease", late.repair_runtime.locks.is_empty())
	var saves := SaveService.new(ProjectSettings.globalize_path("res://tests/tmp/repair_foundations"), "fixture")
	saves.delete_all()
	_check("old payload disk save", saves.write({"colony": old, "clock": SolClock.new().to_dict(), "session": {"host_character": "crew_1"}}) == OK)
	var load_result := saves.read()
	_check("old payload disk load", load_result.is_usable())
	var upgraded := ColonyState.from_dict(load_result.payload.colony)
	_check("migrated payload save again", saves.write({"colony": upgraded.to_dict(), "clock": SolClock.new().to_dict(), "session": {"host_character": "crew_1"}}) == OK)
	_check("reopened migration retains progress", saves.read().is_usable() and SaveService.canonical_text(ColonyState.from_dict(saves.read().payload.colony).crops) == SaveService.canonical_text(old.crops))
	saves.delete_all()
	var services := GameServices.new()
	services.saves = saves
	services.session.begin(s.state, s.clock)
	s.state.repair.tasks.T02.progress = 0.5
	s.state.repair.tasks.T02.puzzle_state = {"unsafe_transient_step": 1}
	var game_snapshot := services.snapshot()
	_check("real snapshot separates safe and unsafe partial state", game_snapshot.colony.repair.tasks.T01.progress == 0.5 and game_snapshot.colony.repair.tasks.T02.progress == 0.0 and game_snapshot.colony.repair.tasks.T02.puzzle_state.is_empty())
	_check("real snapshot stores exposure", game_snapshot.colony.characters.crew_1.lethal_exposure_seconds == 2.75)
	_check("real GameServices writes fixture only", services.save_now(&"foundation_fixture") == OK)
	services.restore(saves.read().payload)
	_check("GameServices disk restore keeps ongoing encounter", services.local_character() != null and services.local_character().lethal_exposure_seconds == 2.75 and services.local_character().health == 41.25 and services.local_character().suit_charge == 12.5)
	_check("disk restore resumes safe puzzle without lease", services.state().repair.tasks.T01.progress == 0.5 and services.session.repair_runtime.locks.is_empty())
	saves.delete_all()
	services.free()

func _safe_switching() -> void:
	var s := _session()
	var actor := s.state.character(&"crew_1")
	actor.owner_peer = 1
	actor.position = s.config.hub_position
	actor.health = 36.0
	actor.suit_charge = 27.0
	# Hazard classification is now recomputed from the host query on every request.
	s.outside_test = func(_position: Vector3) -> bool: return true
	_check("exposed switch rejected", s.request(&"claim_character", &"crew_2").reason == &"unsafe_switch")
	_check("release cannot bypass exposure", s.request(&"release_character").reason == &"unsafe_switch" and actor.owner_peer == 1)
	s.outside_test = func(_position: Vector3) -> bool: return false
	actor.lethal_exposure_seconds = 1.0
	_check("persisted exposure blocks switching", s.request(&"claim_character", &"crew_2").reason == &"unsafe_switch")
	actor.lethal_exposure_seconds = 0.0
	actor.position = Vector3.ZERO
	_check("release cannot bypass hub-only specialist switch", s.request(&"release_character").reason == &"not_at_hub" and actor.owner_peer == 1)
	actor.position = s.config.hub_position
	s.state.cabin_o2_kg = 0.0
	_check("unsafe indoor atmosphere blocks switch", s.request(&"claim_character", &"crew_2").reason == &"unsafe_switch")
	s.state.cabin_o2_kg = s.balance.gas_kg_for_kpa(s.balance.o2_setpoint_kpa, GameBalance.MOLAR_O2)
	for id: StringName in [&"crew_2", &"crew_3", &"crew_4", &"crew_1"]:
		s.state.character_of_peer(1).position = s.config.hub_position
		_check("solo route can select %s" % id, s.request(&"claim_character", id).ok)
	_check("switching preserves health and tank", actor.health == 36.0 and actor.suit_charge == 27.0)
	actor.lethal_exposure_seconds = 3.0
	actor.outside = true
	s.recover_character(actor.id)
	_check("recovery clears exposure through existing recovery flow", actor.lethal_exposure_seconds == 0.0)
	_check("recovery updates outside before autosave", not actor.outside and actor.position == actor.hub_spot and s.safe_to_switch(actor))

func _disconnect_exposure() -> void:
	var s := _session()
	s.peer_joined(2)
	var actor := s.state.character(&"crew_2")
	actor.owner_peer = 2
	actor.position = Vector3(200, 0, 200)
	actor.health = 37.0
	actor.outside = true
	actor.lethal_exposure_seconds = 2.5
	s.outside_test = func(position: Vector3) -> bool: return position.x > 100.0
	var meals := s.state.store(&"food_meals")
	s.peer_left(2)
	_check("exposed disconnect uses costed recovery", actor.owner_peer == 0 and actor.health == s.balance.recovery_health and actor.lethal_exposure_seconds == 0.0 and s.state.store(&"food_meals") < meals)
	_check("disconnect recovery classifies safe parked position", actor.position == actor.hub_spot and not actor.outside)
	var after := s.state.store(&"food_meals")
	s.peer_left(2)
	_check("duplicate disconnect does not charge recovery twice", s.state.store(&"food_meals") == after)
	s.peer_joined(2)
	actor.owner_peer = 2
	actor.position = Vector3(200, 0, 200)
	actor.outside = true
	actor.health = 37.0
	actor.suit_on = true
	actor.suit_charge = 29.0
	s.peer_left(2)
	_check("protected disconnect preserves equipment and health", actor.owner_peer == 0 and actor.health == 37.0 and actor.suit_charge == 29.0 and s.state.store(&"food_meals") == after)
	_check("normal parking refreshes outside flag immediately", actor.position == actor.hub_spot and not actor.outside)
	s.peer_joined(2)
	actor.owner_peer = 2
	actor.position = Vector3(200, 0, 200)
	actor.outside = true
	actor.suit_on = false
	actor.lethal_exposure_seconds = 0.0
	s.peer_left(2)
	_check("unprotected disconnect cannot bypass current hazard", actor.health == s.balance.recovery_health and s.state.store(&"food_meals") < after)
