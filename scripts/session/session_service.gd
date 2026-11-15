class_name SessionService
extends RefCounted
## Coordinates host actions, simulation and real-time suit checks.

## Host network id.
const HOST_PEER: int = 1
const SUITS_PER_RACK := 4
## Engineering settings.
var config: GameConfig
## Designer tuning.
var balance: GameBalance
## Gameplay signals.
var events: GameEvents
## Attached authoritative game, or null before begin.
var state: ColonyState
## Attached game clock.
var clock: SolClock
## Colony flow simulation.
var sim: ColonySim
## Registered actions and request history.
var actions: ActionService
## Authoritative random stream.
var rng: RandomNumberGenerator
## Connected peers, host first.
var peers: Array[int] = []
## Host test for "is this point outside the pressurised habitat?" The game sets it; by default nowhere is outside.
var outside_test: Callable = func(_point: Vector3) -> bool: return false
## Optional host room lookup, wired by GameServices for room-specific repair validation.
var zone_at_position := Callable()
var repair_runtime := RepairRuntime.new()
var cassette_runtime: CassetteRuntime
var survival: SurvivalRuntime
var wear_runtime := WearRuntime.new()
## A replicated client can inspect state and presentation, but cannot advance survival, pressure or wear.
var authoritative := true
## True when every connected peer votes to pause.
var paused: bool = false
var _votes: Dictionary = {}
var _suit_checks: Dictionary = {}
var _accumulator: float = 0.0
var _counter: int = 0

func _init(p_config: GameConfig, p_balance: GameBalance, p_events: GameEvents) -> void:
	config = p_config
	balance = p_balance
	events = p_events
	cassette_runtime = CassetteRuntime.new(self)
	survival = SurvivalRuntime.new(self)
	sim = ColonySim.new()
	sim.exposure_managed = true
	sim.set_events(events)
	rng = RandomNumberGenerator.new()
	actions = ActionService.new()
	BuiltinActions.register(actions)
	RepairActions.register(actions)
	# Broken parts (2026-11-14): every installed T01-T12 puzzle rule (scripts/tasks/puzzles/) is the host validator.
	PuzzleRegistry.register_all(repair_runtime)
	CassetteActions.register(actions)
	WearRuntime.register_actions(actions)
	SystemActions.register(actions)
	# Prompts 08 and 09: each part registers its actions and adds its simulation system.
	FoodActions.register(actions)
	ScienceActions.register(actions)
	ProgressionActions.register(actions)
	WeatherActions.register(actions)
	ScoutActions.register(actions)
	RoverActions.register(actions)
	# 2026-11-14: visible upgrade paths V1..V4 for every area, the scout drone and the rover.
	AreaLevelActions.register(actions)
	# 2026-11-14: the scout drone (scripts/drone/, loaded by path): its host actions and its real-time flight system.
	var drone_actions: Variant = load("res://scripts/drone/drone_actions.gd")
	drone_actions.register(actions)
	var drone_system: Variant = load("res://scripts/drone/drone_system.gd")
	sim.post_systems.append(drone_system.new(self))
	# Prompt 12: tutorial, campaign and story. Registered last: it watches actions the parts above registered.
	TutorialActions.register(actions)
	sim.pre_systems.append(WeatherSystem.new())
	sim.post_systems.append(CropSystem.new())
	sim.post_systems.append(ProgressionSystem.new())
	sim.post_systems.append(ScoutSystem.new())
	sim.post_systems.append(RoverSystem.new())
	sim.post_systems.append(TutorialSystem.new())

## Attaches a new or restored game and resets transient session state.
func begin(p_state: ColonyState, p_clock: SolClock) -> void:
	for peer: int in peers:
		actions.forget_peer(peer)
	state = p_state
	authoritative = true
	clock = p_clock
	peers = [HOST_PEER]
	rng.seed = state.rng_seed
	rng.state = state.rng_state
	_votes.clear()
	_suit_checks.clear()
	repair_runtime.clear_session()
	cassette_runtime.clear_session()
	survival.clear_session()
	wear_runtime.clear_session()
	_accumulator = 0.0
	_restore_suit_slots()
	_recompute_pause()
	survival.pressure.advance(self, 0.0)
	survival.refresh_all()

## Advances real-time checks and fixed simulation ticks without dropping time.
func advance(real_delta: float) -> int:
	if state == null or not authoritative:
		return 0
	cassette_runtime.prune(self)
	if paused:
		_advance_suit_checks(0.0)
		return 0
	var tick: float = 1.0 / config.sim_tick_hz
	var count: int = 0
	var remaining := maxf(0.0, real_delta)
	var first_pass := true
	# Interleave protection/resource updates with the real-time timer. A tank that empties mid-frame
	# cannot grant the remainder of that rendered frame as free protection; hazards also outlive a tick backlog.
	while first_pass or remaining > 1e-8:
		first_pass = false
		var step := minf(remaining, clampf(config.hazard_step_seconds, 0.01, 0.2))
		repair_runtime.advance(self, step)
		wear_runtime.advance(self, step)
		survival.pressure.advance(self, step)
		survival.refresh_all()
		_advance_suit_checks(step)
		_accumulator += step
		while _accumulator >= tick - 1e-9 and count < config.max_ticks_per_frame:
			_accumulator -= tick
			var phase_before: float = clock.phase
			var dt_hours: float = clock.advance(tick)
			for id: StringName in sim.step(state, balance, phase_before, dt_hours):
				# Simulation health loss: no water or no food (atmosphere harm is the real-time SurvivalRuntime's).
				recover_character(id, SurvivalRuntime.DeathReasons.health_id(self, state.character(id)))
			for rollover: int in clock.rolled_over:
				events.sol_started.emit(clock.sol_index - clock.rolled_over + rollover + 1)
			count += 1
		survival.advance(step)
		remaining -= step
	if count > 0:
		events.state_changed.emit(&"tick")
	return count

## Submits a request to the authoritative validator.
func submit(action_request: ActionRequest) -> ActionResult:
	if not authoritative:
		return ActionResult.failure(action_request.request_id, &"host_only", "Only the authoritative host can apply gameplay actions.")
	if state != null:
		survival.refresh_all()
		repair_runtime.prune(self)
		cassette_runtime.prune(self)
		wear_runtime.prune(self)
	var answer := actions.resolve(self, action_request)
	survival.refresh_all()
	return answer

## Builds a fresh request using the peer's current character.
func request(action: StringName, target: StringName = &"", params: Dictionary = {}, peer: int = HOST_PEER) -> ActionResult:
	_counter += 1
	var actor: CharacterState = state.character_of_peer(peer) if state != null else null
	return submit(ActionRequest.make("p%d-%d" % [peer, _counter], peer, actor.id if actor != null else &"", action, target, params))

## Adds a peer up to the four-player limit.
func peer_joined(peer: int) -> void:
	if peer > 0 and not peers.has(peer) and peers.size() < 4:
		peers.append(peer)
		_recompute_pause()

## Parks the departing peer's character without charging supplies.
func peer_left(peer: int) -> void:
	var actor: CharacterState = state.character_of_peer(peer) if state != null else null
	if actor != null:
		# A dropped connection cannot replace an ongoing lethal encounter with a free teleport.
		# Resolve through the same recovery/cache/resource-cost flow used by ordinary death.
		var exterior := not survival.breathable_at(actor.position, actor.in_airlock_pressure_volume)
		var protected := survival.functional_suit(actor)
		if actor.lethal_exposure_seconds > 0.0 or actor.health <= 0.0 or (exterior and not protected):
			recover_character(actor.id)
		_release(actor)
	peers.erase(peer)
	_votes.erase(peer)
	actions.forget_peer(peer)
	_recompute_pause()

## Records a connected peer's pause vote.
func set_pause_vote(peer: int, wants_pause: bool) -> void:
	if peers.has(peer):
		_votes[peer] = wants_pause
		_recompute_pause()

## Accepts position reports only from the character's owner.
func report_position(peer: int, character_id: StringName, position: Vector3, yaw: float) -> bool:
	if not authoritative:
		return false
	var actor: CharacterState = state.character(character_id) if state != null else null
	if actor == null or peer <= 0 or actor.owner_peer != peer:
		return false
	actor.position = position
	actor.yaw = yaw
	if outside_test.is_valid():
		actor.outside = bool(outside_test.call(position))
	survival.refresh_actor(actor)
	repair_runtime.prune(self)
	cassette_runtime.prune(self)
	wear_runtime.prune(self)
	return true

## Queues one airlock cycle (host). The next tick takes its air loss from the cabin; the regulator then tops the
## cabin up from the oxygen and nitrogen reserves.
func note_airlock_cycle() -> void:
	if state != null and authoritative:
		state.pending_airlock_cycles += 1

## Recovers a downed character and leaves carried items at the incident.
## `cause` is a death id (scripts/survival/death_reasons.gd); "" lets DeathReasons work it out. The death record is
## written to `actor.last_death` here, before the respawn moves the actor, and is also sent as `info.death` with
## GameEvents.character_recovered (the event the UI listens to for "why did I die").
func recover_character(id: StringName, cause := "") -> Dictionary:
	var info: Dictionary = {"meals": 0.0, "water_l": 0.0, "cache_id": "", "cache_position": []}
	if state == null or not authoritative:
		return info
	var actor := state.character(id)
	if actor == null:
		return info
	info.death = SurvivalRuntime.DeathReasons.record(self, actor, cause).duplicate()
	info.cause = String(actor.last_death.cause)
	repair_runtime.release_character(id)
	cassette_runtime.release_character(id)
	wear_runtime.release_character(id)
	if not actor.cargo.is_empty():
		var cache_id: String = "cache_%d" % int(state.counters["cache"])
		state.counters["cache"] = int(state.counters["cache"]) + 1
		var position: Array = [actor.position.x, actor.position.y, actor.position.z]
		var items: Array = []
		for item: StringName in actor.cargo:
			items.append(String(item))
			state.items[item]["holder"] = "cache:" + cache_id
			state.items[item]["position"] = position.duplicate()
		state.caches.append({"id": cache_id, "position": position, "items": items})
		actor.cargo.clear()
		info.cache_id = cache_id
		info.cache_position = position.duplicate()
	info.meals = -state.add_to_store(&"food_meals", -config.recovery_cost_sols * balance.meals_per_sol)
	info.water_l = -state.add_to_store(&"water_l", -config.recovery_cost_sols * balance.water_l_per_hour * GameConfig.SOL_HOURS)
	state.ledger["recovery_meals"] += info.meals
	state.ledger["recovery_water_l"] += info.water_l
	# Respawn in the Med Bay: the crew member's own hub spot there (a never-placed record falls back to the hub).
	if actor.hub_spot == Vector3.ZERO:
		actor.hub_spot = config.hub_position
	actor.position = actor.hub_spot
	if outside_test.is_valid():
		actor.outside = bool(outside_test.call(actor.position))
	# balance.recovery_health plus the Med bay level's recovery_health_bonus, capped at full health.
	actor.health = SurvivalRuntime.MedCare.recovery_health(self)
	survival.reset_character(actor)
	_cancel_suit_check(id)
	events.character_recovered.emit(id, info)
	return info

## Tests whether a point is within the hub boundary.
func is_at_hub(position: Vector3) -> bool:
	return position.distance_to(config.hub_position) <= config.hub_radius_m

## Switching never cancels a dangerous atmosphere encounter. Read gas masses so this also works before a tick.
func safe_to_switch(actor: CharacterState) -> bool:
	if actor.health <= 0.0 or actor.lethal_exposure_seconds > 0.0 or not survival.breathable_at(actor.position, actor.in_airlock_pressure_volume):
		return false
	return balance.gas_kpa(state.cabin_o2_kg, GameBalance.MOLAR_O2) >= balance.o2_low_kpa and balance.gas_kpa(state.cabin_co2_kg, GameBalance.MOLAR_CO2) <= balance.co2_danger_kpa

## Copies random state before saving.
func sync_rng_to_state() -> void:
	if state != null:
		state.rng_state = rng.state

## Session facts a networked client shows but never decides: peers, pause votes, running suit checks.
func replica_dict() -> Dictionary:
	var checks := {}
	for id: StringName in _suit_checks:
		checks[String(id)] = float(_suit_checks[id].elapsed)
	var votes := {}
	for peer: int in _votes:
		votes[peer] = bool(_votes[peer])
	return {"peers": peers.duplicate(), "paused": paused, "votes": votes, "suit_checks": checks, "repair": repair_runtime.replica_dict(), "cassettes": cassette_runtime.replica_dict(), "survival": survival.replica_dict(), "wear": wear_runtime.replica_dict()}


## Client: copies the host's session facts (see replica_dict). Emits nothing; the host's forwarded events do that.
func apply_replica(d: Dictionary) -> void:
	authoritative = false
	repair_runtime.apply_replica(d.get("repair", {}))
	cassette_runtime.apply_replica(d.get("cassettes", {}))
	survival.apply_replica(d.get("survival", {}))
	wear_runtime.apply_replica(d.get("wear", {}))
	peers.clear()
	for p in d.get("peers", [HOST_PEER]):
		peers.append(int(p))
	paused = bool(d.get("paused", false))
	_votes.clear()
	var votes: Dictionary = d.get("votes", {})
	for p in votes:
		_votes[int(p)] = bool(votes[p])
	_suit_checks.clear()
	var checks: Dictionary = d.get("suit_checks", {})
	for id in checks:
		_suit_checks[StringName(String(id))] = {"elapsed": float(checks[id])}


## How many connected peers currently vote to pause.
func pause_votes() -> int:
	var yes := 0
	for peer: int in peers:
		if bool(_votes.get(peer, false)):
			yes += 1
	return yes

## Returns check progress, or -1 when no check is running.
func suit_check_progress(character_id: StringName) -> float:
	if not _suit_checks.has(character_id):
		return -1.0
	return clampf(float(_suit_checks[character_id].elapsed) / config.suit_check_seconds, 0.0, 1.0)

func _recompute_pause() -> void:
	var value: bool = not peers.is_empty()
	for peer: int in peers:
		value = value and bool(_votes.get(peer, false))
	if value != paused:
		paused = value
		events.pause_changed.emit(paused)

func _release(actor: CharacterState) -> void:
	repair_runtime.release_character(actor.id)
	cassette_runtime.release_character(actor.id)
	wear_runtime.release_character(actor.id)
	_cancel_suit_check(actor.id)
	actor.owner_peer = 0
	actor.position = actor.hub_spot
	if outside_test.is_valid():
		actor.outside = bool(outside_test.call(actor.position))
	events.crew_ownership_changed.emit(actor.id, 0)

func _start_suit_check(actor: CharacterState, station: StringName, on: bool) -> void:
	_suit_checks[actor.id] = {"peer": actor.owner_peer, "station": station, "on": on, "elapsed": 0.0}
	_suit_checks[actor.id].slot = available_suit_slot(station) if on else actor.suit_slot
	events.suit_check_started.emit(actor.id, config.suit_check_seconds)

## Includes in-progress checks so simultaneous requests cannot take the same suit.
func available_suit_slot(rack: StringName) -> int:
	for slot in SUITS_PER_RACK:
		var taken := false
		for c: CharacterState in state.characters.values():
			if c.suit_on and c.suit_rack == rack and c.suit_slot == slot:
				taken = true
		for check: Dictionary in _suit_checks.values():
			if bool(check.get("on", false)) and StringName(check.get("station", "")) == rack and int(check.get("slot", -1)) == slot:
				taken = true
		if not taken:
			return slot
	return -1

func _restore_suit_slots() -> void:
	var rack: StringName = &""
	for id in state.stations:
		if String(state.stations[id].get("kind", "")) == "suits":
			rack = StringName(id)
			break
	var occupied := {}
	for c: CharacterState in state.characters.values():
		if not c.suit_on:
			c.suit_rack = &""
			c.suit_slot = -1
			continue
		var key := "%s:%d" % [c.suit_rack, c.suit_slot]
		if c.suit_rack == &"" or c.suit_slot < 0 or c.suit_slot >= SUITS_PER_RACK or occupied.has(key):
			c.suit_rack = rack
			c.suit_slot = -1
		else:
			occupied[key] = true
	for c: CharacterState in state.characters.values():
		if c.suit_on and c.suit_slot < 0 and rack != &"":
			c.suit_slot = available_suit_slot(rack)

func _cancel_suit_check(id: StringName) -> void:
	if _suit_checks.has(id):
		_suit_checks.erase(id)
		events.suit_check_finished.emit(id, state.character(id).suit_on, false)

func _advance_suit_checks(delta: float) -> void:
	for id: StringName in _suit_checks.keys():
		var check: Dictionary = _suit_checks[id]
		var actor := state.character(id)
		var station: Dictionary = state.stations.get(check.station, {})
		if actor.owner_peer != int(check.peer) or station.is_empty() or actor.position.distance_to(CharacterState._v3(station.position)) > config.interact_distance_m:
			_cancel_suit_check(id)
			continue
		check.elapsed += delta
		if not paused and float(check.elapsed) >= config.suit_check_seconds - 1e-9:
			actor.suit_on = bool(check.on)
			actor.suit_rack = StringName(check.station) if actor.suit_on else &""
			actor.suit_slot = int(check.slot) if actor.suit_on else -1
			_suit_checks.erase(id)
			events.suit_check_finished.emit(id, actor.suit_on, true)
