extends SceneTree

var _passed: int = 0
var _total: int = 0
var _sessions: Array[SessionService] = []
var _catalog: Dictionary
var _all_invariants: bool = true

func _initialize() -> void:
	_catalog = StationCatalog.from_manifest("res://data/colony_manifest.json", ColonyZones.from_manifest("res://data/colony_manifest.json"))
	var kinds: Array = []
	for station: Dictionary in _catalog.values():
		kinds.append(station.kind)
	kinds.sort()
	var expected_kinds: Array = ["board", "comms", "computer", "food", "heal", "lifesupport", "power"]
	for tracker: int in 12: expected_kinds.append("solar")
	expected_kinds.append_array(["suits", "survivor"])
	_check("manifest stations", _catalog.size() == 21 and kinds == expected_kinds)
	var s := _new_session()
	var power: StringName = LegacyStations.stations_of_kind(s.state, "power")[0]
	_check("power zone", s.state.stations[power].zone == "Power Room")
	_fail("bad shape", s.submit(ActionRequest.make("", 1, &"", &"claim_character")), &"bad_request")
	_fail("unknown action", s.request(&"nothing"), &"unknown_action")
	for params: Dictionary in [{}, {"minutes": true}, {"minutes": 4.0}, {"minutes": 121.0}, {"minutes": 20, "extra": 1}]:
		_fail("parameter validation", s.request(&"set_sol_minutes", &"", params), &"bad_request")
	_fail("long string", s.request(&"set_zone_power", power, {"zone": "x".repeat(65), "on": true}), &"bad_request")
	_fail("host only", s.request(&"set_sol_minutes", &"", {"minutes": 5}, 2), &"host_only")
	_fail("no actor", s.request(&"pick_up", &"item"), &"no_actor")
	_fail("unknown actor", s.submit(ActionRequest.make("unknownactor", 1, &"absent", &"pick_up", &"item")), &"not_owner")
	_check("first claim", s.request(&"claim_character", &"crew_1").ok and s.state.character(&"crew_1").owner_peer == 1)
	_fail("already yours", s.request(&"claim_character", &"crew_1"), &"already_yours")
	s.peer_joined(2)
	_fail("taken", s.request(&"claim_character", &"crew_1", {}, 2), &"character_taken")
	_fail("not owner", s.submit(ActionRequest.make("owner", 2, &"crew_1", &"pick_up", &"item")), &"not_owner")
	_fail("missing target", s.request(&"pick_up", &"missing"), &"unknown_target")
	_fail("wrong target category", s.request(&"pick_up", power), &"unknown_target")
	_fail("wrong station", s.request(&"begin_suit_check", power, {"on": true}), &"wrong_target")
	_fail("too far", s.request(&"set_zone_power", power, {"zone": "Power Room", "on": false}), &"too_far")
	s.state.character(&"crew_1").position = CharacterState._v3(s.state.stations[power].position)
	_fail("unknown zone", s.request(&"set_zone_power", power, {"zone": "absent", "on": false}), &"unknown_target")
	_check("power action", LegacyStations.interact(s, 1, power, {"zone": "Power Room", "on": false}).ok and not s.state.is_zone_powered("Power Room"))
	_fail("legacy unknown", LegacyStations.interact(s, 1, &"absent"), &"unknown_target")
	_fail("legacy unavailable", LegacyStations.interact(s, 1, LegacyStations.stations_of_kind(s.state, "food")[0]), &"not_available_yet")
	var d := ActionService.Definition.new()
	d.id = &"test"
	d.specialty = &"biology_food"
	d.params = {"mode": {"type": TYPE_STRING}, "optional": {"type": TYPE_INT, "optional": true}}
	d.check = func(ctx: ActionService.Context) -> ActionResult: return ActionResult.failure(ctx.request.request_id, StringName(ctx.request.params.mode))
	s.actions.register(d)
	_fail("specialty", s.request(&"test", &"", {"mode": "insufficient"}), &"wrong_specialty")
	d.specialty = &""
	_fail("prerequisite", s.request(&"test", &"", {"mode": "missing_prerequisite"}), &"missing_prerequisite")
	_fail("quantity", s.request(&"test", &"", {"mode": "insufficient"}), &"insufficient")
	s.state.stations[power].specialty = "biology_food"
	_fail("station specialty", s.request(&"set_zone_power", power, {"zone": "Power Room", "on": true}), &"wrong_specialty")
	_carry_and_switch()
	_pause_and_suits()
	_recovery()
	_timing()
	_history_and_recovery_tick()
	_check("invariants after every action", _all_invariants)
	for session: SessionService in _sessions:
		session.events.free()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)

func _new_session() -> SessionService:
	var s := SessionService.new(GameConfig.new(), GameBalance.new(), GameEvents.new())
	var state := ColonyState.new_game(s.balance, 12345, PackedStringArray(["Power Room", "Life Support"]))
	state.stations = _catalog.duplicate(true)
	for actor: CharacterState in state.characters.values():
		actor.hub_spot = s.config.hub_position
		actor.position = actor.hub_spot
	s.begin(state, SolClock.new())
	s.events.action_resolved.connect(func(_result: ActionResult) -> void: _all_invariants = _all_invariants and _invariant(s))
	_sessions.append(s)
	return s

func _check(label: String, condition: bool, detail: String = "state mismatch") -> void:
	_total += 1
	if condition:
		_passed += 1
		print("PASS " + label)
	else:
		print("FAIL " + label + ": " + detail)

func _fail(label: String, result: ActionResult, reason: StringName) -> void:
	_check(label, not result.ok and result.reason == reason, "expected %s, got %s" % [reason, result.reason])

func _item(s: SessionService, id: StringName, p: Vector3) -> void:
	s.state.items[id] = {"kind": "crate", "position": [p.x, p.y, p.z], "holder": ""}

func _invariant(s: SessionService) -> bool:
	if not s.state.invariants_ok().is_empty():
		return false
	for id: StringName in s.state.items:
		var count: int = 0
		var holder: String = s.state.items[id].holder
		for c: CharacterState in s.state.characters.values():
			if c.cargo.has(id):
				count += 1
				if holder != String(c.id): return false
		for cache: Dictionary in s.state.caches:
			if cache.items.has(String(id)):
				count += 1
				if holder != "cache:" + String(cache.id): return false
		if count != (0 if holder == "" else 1): return false
	return true

func _carry_and_switch() -> void:
	var s := _new_session()
	s.request(&"claim_character", &"crew_1")
	var c := s.state.character(&"crew_1")
	_item(s, &"box", c.position)
	var r := ActionRequest.make("repeat", 1, c.id, &"pick_up", &"box")
	_check("pick up", s.submit(r).ok and c.cargo == [&"box"] and _invariant(s))
	var before: Dictionary = s.state.to_dict()
	var duplicate := s.submit(r)
	_check("duplicate success", duplicate.ok and duplicate.duplicate and s.state.to_dict() == before and _invariant(s))
	s.peer_joined(2)
	s.request(&"claim_character", &"crew_2", {}, 2)
	_fail("cannot hold twice", s.request(&"pick_up", &"box", {}, 2), &"already_held")
	_check("carrying invariant", _invariant(s))
	_check("drop", s.request(&"drop", &"box").ok and c.cargo.is_empty() and s.state.items[&"box"].holder == "" and _invariant(s))
	_fail("not held", s.request(&"drop", &"box"), &"not_held")
	s.balance.cargo_slots = 1
	s.request(&"pick_up", &"box")
	_item(s, &"other", c.position)
	var failed := ActionRequest.make("failed", 1, c.id, &"pick_up", &"other")
	_fail("cargo full", s.submit(failed), &"cargo_full")
	s.request(&"drop", &"box")
	before = s.state.to_dict()
	duplicate = s.submit(failed)
	_check("duplicate failure stays failed", duplicate.duplicate and duplicate.reason == &"cargo_full" and before == s.state.to_dict() and _invariant(s))
	s.request(&"pick_up", &"box")
	c.health = 73.0
	c.suit_charge = 41.0
	c.equipment = [&"radio"]
	var personal: Dictionary = c.to_dict()
	s.peer_left(2)
	for peers_count: int in [1, 2, 3]:
		if peers_count > 1: s.peer_joined(peers_count)
		_check("switch with %d peers" % peers_count, s.request(&"claim_character", &"crew_2").ok and c.owner_peer == 0 and c.cargo == [&"box"] and c.health == 73.0 and c.suit_charge == 41.0 and c.stamina == float(personal.stamina) and c.equipment == [&"radio"] and _invariant(s))
		s.request(&"claim_character", &"crew_1")
	c.position += Vector3(100, 0, 0)
	_fail("switch outside hub", s.request(&"claim_character", &"crew_2"), &"not_at_hub")
	c.position = c.hub_spot
	s.peer_joined(4)
	_fail("four peer switch", s.request(&"claim_character", &"crew_2"), &"switch_disabled")
	before = s.state.stores.duplicate()
	s.peer_left(1)
	_check("peer loss preserves cargo and stores", c.owner_peer == 0 and c.position == c.hub_spot and c.cargo == [&"box"] and before == s.state.stores and _invariant(s))
	_check("position ownership", not s.report_position(2, c.id, Vector3.ONE, 1.0))
	s.peer_joined(1)
	s.request(&"claim_character", c.id)
	_check("position accepted", s.report_position(1, c.id, c.hub_spot, 0.7) and c.yaw == 0.7)
	_check("release", s.request(&"release_character").ok and c.owner_peer == 0 and c.cargo == [&"box"] and c.position == c.hub_spot)
	var frozen: Dictionary = c.to_dict()
	_run(s, 1200.0, 1.0)
	_check("parked sol frozen and no consumption", c.to_dict() == frozen and s.state.ledger.meals_eaten == 0.0 and s.state.ledger.water_used_l == 0.0 and s.state.ledger.oxygen_used_kg == 0.0)

func _pause_and_suits() -> void:
	var s := _new_session()
	s.request(&"claim_character", &"crew_1")
	var c := s.state.character(&"crew_1")
	var suit: StringName = LegacyStations.stations_of_kind(s.state, "suits")[0]
	c.position = CharacterState._v3(s.state.stations[suit].position)
	_check("start suit", s.request(&"begin_suit_check", suit, {"on": true}).ok)
	_fail("check already running", s.request(&"begin_suit_check", suit, {"on": true}), &"missing_prerequisite")
	s.request(&"vote_pause", &"", {"paused": true})
	_check("solo pause freezes ticks and suit", s.paused and s.advance(2.0) == 0 and s.suit_check_progress(c.id) == 0.0 and not c.suit_on)
	_fail("paused action", s.request(&"release_character"), &"paused")
	s.peer_joined(2)
	_check("one of two votes", not s.paused)
	s.set_pause_vote(2, true)
	_check("two votes pause", s.paused)
	s.set_pause_vote(2, false)
	s.peer_left(2)
	_check("leaving dissenter pauses", s.paused)
	s.set_pause_vote(1, false)
	_check("unvote resumes", not s.paused)
	for minutes: float in [20.0, 5.0]:
		s.request(&"set_sol_minutes", &"", {"minutes": minutes})
		if s.suit_check_progress(c.id) < 0.0: s.request(&"begin_suit_check", suit, {"on": not c.suit_on})
		var old: bool = c.suit_on
		s.advance(0.99)
		_check("suit waits at %.0f minutes" % minutes, c.suit_on == old and s.suit_check_progress(c.id) > 0.98)
		s.advance(0.01)
		_check("suit completes at %.0f minutes" % minutes, c.suit_on != old and s.suit_check_progress(c.id) == -1.0)
	_fail("same suit state", s.request(&"begin_suit_check", suit, {"on": c.suit_on}), &"missing_prerequisite")
	s.request(&"begin_suit_check", suit, {"on": not c.suit_on})
	var old: bool = c.suit_on
	c.position += Vector3(20, 0, 0)
	s.advance(1.0)
	_check("walking cancels suit", c.suit_on == old and s.suit_check_progress(c.id) == -1.0)
	c.position = CharacterState._v3(s.state.stations[suit].position)
	c.suit_charge = 37.25
	var cycles_ok: bool = true
	for cycle: int in 20:
		cycles_ok = s.request(&"begin_suit_check", suit, {"on": not c.suit_on}).ok and cycles_ok
		s.advance(1.0)
		cycles_ok = cycles_ok and c.suit_charge == 37.25 and s.suit_check_progress(c.id) == -1.0
	_check("ten on off cycles preserve charge", cycles_ok)
	s.request(&"begin_suit_check", suit, {"on": not c.suit_on})
	s.peer_left(1)
	_check("peer loss cancels suit", s.suit_check_progress(c.id) == -1.0)

func _recovery() -> void:
	var s := _new_session()
	s.request(&"claim_character", &"crew_1")
	var c := s.state.character(&"crew_1")
	c.position = Vector3(10, 2, 30)
	c.equipment = [&"radio"]
	c.suit_on = true
	c.suit_charge = 23.0
	for id: StringName in [&"a", &"b"]:
		_item(s, id, c.position)
		s.request(&"pick_up", id)
	var food: float = s.state.store(&"food_meals")
	var water: float = s.state.store(&"water_l")
	var info := s.recover_character(c.id)
	_check("recovery cache exact", s.state.caches.size() == 1 and s.state.caches[0].items == ["a", "b"] and info.cache_position == [10.0, 2.0, 30.0] and c.cargo.is_empty() and _invariant(s))
	_check("recovery cost once", is_equal_approx(food - s.state.store(&"food_meals"), s.config.recovery_cost_sols * s.balance.meals_per_sol) and is_equal_approx(water - s.state.store(&"water_l"), s.config.recovery_cost_sols * s.balance.water_l_per_hour * GameConfig.SOL_HOURS) and s.state.ledger.recovery_meals == info.meals and s.state.ledger.recovery_water_l == info.water_l)
	_check("recovery preserves personal gear", c.position == c.hub_spot and c.health == s.balance.recovery_health and c.suit_on and c.suit_charge == 23.0 and c.equipment == [&"radio"] and c.owner_peer == 1)
	c.position = Vector3(10, 2, 30)
	s.balance.cargo_slots = 1
	_check("partial cache collect", s.request(&"collect_cache", StringName(info.cache_id)).ok and c.cargo.size() == 1 and s.state.caches[0].items.size() == 1 and _invariant(s))
	_fail("cache cargo full", s.request(&"collect_cache", StringName(info.cache_id)), &"cargo_full")
	s.balance.cargo_slots = 6
	_check("cache collect complete", s.request(&"collect_cache", StringName(info.cache_id)).ok and c.cargo == [&"a", &"b"] and s.state.caches.is_empty() and _invariant(s))
	for id: StringName in c.cargo.duplicate(): s.request(&"drop", id)
	s.state.stores[&"food_meals"] = 0.0
	s.state.stores[&"water_l"] = 0.0
	info = s.recover_character(c.id)
	_check("empty stores recovery", info.meals == 0.0 and info.water_l == 0.0 and info.cache_id == "" and c.health == s.balance.recovery_health and s.state.store(&"food_meals") == 0.0 and s.state.store(&"water_l") == 0.0 and _invariant(s))

func _run(s: SessionService, seconds: float, dt: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds - 1e-9:
		var step: float = minf(dt, seconds - elapsed)
		s.advance(step)
		elapsed += step
	while s.advance(0.0) > 0: pass

func _timing() -> void:
	var s := _new_session()
	_check("unattached session", SessionService.new(s.config, s.balance, s.events).advance(1.0) == 0)
	s.request(&"claim_character", &"crew_1")
	var battery_start: float = s.state.store(&"battery_kwh")
	var instant_ok: bool = true
	for minutes: float in [5.0, 120.0, 20.0, 8.0]:
		_run(s, 40.0, 0.1)
		var phase: float = s.clock.phase
		var index: int = s.clock.sol_index
		var battery: float = s.state.store(&"battery_kwh")
		instant_ok = instant_ok and s.request(&"set_sol_minutes", &"", {"minutes": minutes}).ok and phase == s.clock.phase and index == s.clock.sol_index and battery == s.state.store(&"battery_kwh")
	_check("sol settings preserve instant state", instant_ok)
	_check("battery ledger identity", absf(s.state.store(&"battery_kwh") - battery_start - float(s.state.ledger.battery_in_kwh) + float(s.state.ledger.battery_loss_kwh) + float(s.state.ledger.battery_out_kwh)) < 1e-6)
	var reference: Dictionary = {}
	for minutes: float in [5.0, 20.0, 120.0]:
		var sol := _new_session()
		sol.request(&"claim_character", &"crew_1")
		sol.request(&"set_sol_minutes", &"", {"minutes": minutes})
		_run(sol, minutes * 60.0, 1.0)
		if reference.is_empty(): reference = sol.state.stores.duplicate()
		var max_relative: float = 0.0
		for key: StringName in ColonyState.STORE_KEYS:
			max_relative = maxf(max_relative, absf(sol.state.store(key) - float(reference[key])) / maxf(1.0, absf(float(reference[key]))))
		_check("full sol %.0f minutes difference %.8f" % [minutes, max_relative], max_relative <= 0.01 and absf(sol.clock.game_hours() - GameConfig.SOL_HOURS) < 1e-6 and absf(float(sol.state.ledger.meals_eaten) - sol.balance.meals_per_sol) < 1e-6)
	var baseline: SessionService
	for fps: int in [30, 60, 144, 0]:
		var run := _new_session()
		run.request(&"claim_character", &"crew_1")
		var elapsed: float = 0.0
		var frame: int = 0
		for boundary: float in [15.0, 30.0, 45.0, 60.0]:
			while elapsed < boundary - 1e-9:
				var dt: float = 1.0 / float(fps) if fps > 0 else [0.011, 0.079, 0.003, 0.41, 0.017][frame % 5]
				dt = minf(dt, boundary - elapsed)
				run.advance(dt)
				elapsed += dt
				frame += 1
			run.request(&"set_sol_minutes", &"", {"minutes": 5.0 if boundary == 30.0 else 20.0})
		while run.advance(0.0) > 0: pass
		if baseline == null: baseline = run
		var diff: float = 0.0
		for key: StringName in ColonyState.STORE_KEYS:
			diff = maxf(diff, absf(run.state.store(key) - baseline.state.store(key)))
		_check("frame rate %d tick difference %d store difference %.9f" % [fps, run.clock.ticks - baseline.clock.ticks, diff], absi(run.clock.ticks - baseline.clock.ticks) <= 1 and diff < 1e-6)
	var backlog := _new_session()
	_check("tick cap", backlog.advance(10.0) == backlog.config.max_ticks_per_frame)
	while backlog.advance(0.0) > 0: pass
	_check("backlog retained", backlog.clock.ticks == 50)
	var expected := RandomNumberGenerator.new()
	expected.seed = s.state.rng_seed
	expected.state = s.state.rng_state
	_check("rng restored", s.rng.randi() == expected.randi())
	s.sync_rng_to_state()
	_check("rng synchronized", s.state.rng_state == s.rng.state)


func _history_and_recovery_tick() -> void:
	var s := _new_session()
	s.config.remembered_requests = 2
	s.request(&"claim_character", &"crew_1")
	var c := s.state.character(&"crew_1")
	_item(s, &"logbox", c.position)
	var r := ActionRequest.make("evicted", 1, c.id, &"drop", &"logbox")
	_fail("remember failure", s.submit(r), &"not_held")
	s.request(&"pick_up", &"logbox")
	s.request(&"set_sol_minutes", &"", {"minutes": 20})
	var result := s.submit(r)
	_check("request log evicts oldest", result.ok and not result.duplicate and c.cargo.is_empty())
	s.actions.forget_peer(1)
	result = s.submit(r)
	_check("forget peer clears history", not result.duplicate and result.reason == &"not_held")
	s.request(&"pick_up", &"logbox")
	c.health = 0.001
	s.state.stores[&"oxygen_kg"] = 0.0
	s.state.cabin_o2_kg = 0.0
	s.state.zones["Life Support"].powered = false
	var recovered: Array = []
	s.events.character_recovered.connect(func(id: StringName, info: Dictionary) -> void: recovered.append([id, info]))
	s.advance(0.2)
	_check("simulation triggers recovery once", recovered.size() == 1 and c.health == s.balance.recovery_health and s.state.caches.size() == 1 and _invariant(s))
	s.advance(0.2)
	_check("later tick does not repeat recovery", recovered.size() == 1 and s.state.caches.size() == 1)
	var state: ColonyState = s.state
	var saved_rng: int = state.rng_state
	s.set_pause_vote(1, true)
	s.begin(state, SolClock.new())
	s.events.action_resolved.connect(func(_result: ActionResult) -> void: _all_invariants = _all_invariants and _invariant(s))
	_check("begin resets transient state", not s.paused and s.peers == [1] and s.advance(0.0) == 0 and s.rng.state == saved_rng)

