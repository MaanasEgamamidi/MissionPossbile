class_name SessionService
extends RefCounted
## Coordinates host actions, simulation and real-time suit checks.

## Host network id.
const HOST_PEER: int = 1
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
	sim = ColonySim.new()
	sim.set_events(events)
	rng = RandomNumberGenerator.new()
	actions = ActionService.new()
	BuiltinActions.register(actions)
	SystemActions.register(actions)

## Attaches a new or restored game and resets transient session state.
func begin(p_state: ColonyState, p_clock: SolClock) -> void:
	for peer: int in peers:
		actions.forget_peer(peer)
	state = p_state
	clock = p_clock
	peers = [HOST_PEER]
	rng.seed = state.rng_seed
	rng.state = state.rng_state
	_votes.clear()
	_suit_checks.clear()
	_accumulator = 0.0
	_recompute_pause()

## Advances real-time checks and fixed simulation ticks without dropping time.
func advance(real_delta: float) -> int:
	if state == null:
		return 0
	_advance_suit_checks(0.0 if paused else real_delta)
	if paused:
		return 0
	_accumulator += real_delta
	var tick: float = 1.0 / config.sim_tick_hz
	var count: int = 0
	while _accumulator >= tick - 1e-9 and count < config.max_ticks_per_frame:
		_accumulator -= tick
		var phase_before: float = clock.phase
		var dt_hours: float = clock.advance(tick)
		for id: StringName in sim.step(state, balance, phase_before, dt_hours):
			recover_character(id)
		for rollover: int in clock.rolled_over:
			events.sol_started.emit(clock.sol_index - clock.rolled_over + rollover + 1)
		count += 1
	if count > 0:
		events.state_changed.emit(&"tick")
	return count

## Submits a request to the authoritative validator.
func submit(action_request: ActionRequest) -> ActionResult:
	return actions.resolve(self, action_request)

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
	var actor: CharacterState = state.character(character_id) if state != null else null
	if actor == null or peer <= 0 or actor.owner_peer != peer:
		return false
	actor.position = position
	actor.yaw = yaw
	if outside_test.is_valid():
		actor.outside = bool(outside_test.call(position))
	return true

## Queues one airlock cycle (host). The next tick takes its air loss from the cabin; the regulator then tops the
## cabin up from the oxygen and nitrogen reserves.
func note_airlock_cycle() -> void:
	if state != null:
		state.pending_airlock_cycles += 1

## Recovers a downed character and leaves carried items at the incident.
func recover_character(id: StringName) -> Dictionary:
	var actor := state.character(id)
	var info: Dictionary = {"meals": 0.0, "water_l": 0.0, "cache_id": "", "cache_position": []}
	if actor == null:
		return info
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
	actor.position = actor.hub_spot
	actor.health = balance.recovery_health
	_cancel_suit_check(id)
	events.character_recovered.emit(id, info)
	return info

## Tests whether a point is within the hub boundary.
func is_at_hub(position: Vector3) -> bool:
	return position.distance_to(config.hub_position) <= config.hub_radius_m

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
	return {"peers": peers.duplicate(), "paused": paused, "votes": votes, "suit_checks": checks}


## Client: copies the host's session facts (see replica_dict). Emits nothing; the host's forwarded events do that.
func apply_replica(d: Dictionary) -> void:
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
	_cancel_suit_check(actor.id)
	actor.owner_peer = 0
	actor.position = actor.hub_spot
	events.crew_ownership_changed.emit(actor.id, 0)

func _start_suit_check(actor: CharacterState, station: StringName, on: bool) -> void:
	_suit_checks[actor.id] = {"peer": actor.owner_peer, "station": station, "on": on, "elapsed": 0.0}
	events.suit_check_started.emit(actor.id, config.suit_check_seconds)

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
			_suit_checks.erase(id)
			events.suit_check_finished.emit(id, actor.suit_on, true)
