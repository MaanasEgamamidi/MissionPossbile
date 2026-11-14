class_name ActionService
extends RefCounted
## Validates actions and remembers each peer's recent answers.

## Rules and callbacks for one action.
class Definition extends RefCounted:
	## Stable action name.
	var id: StringName
	## Requires an owned character.
	var needs_actor: bool = true
	## Restricts the action to the host.
	var host_only: bool = false
	## Allows the action during a pause.
	var allowed_while_paused: bool = false
	## Required target category.
	var target_kind: StringName = &""
	## Permitted station kinds; empty allows all.
	var station_kinds := PackedStringArray()
	## Required actor specialty.
	var specialty: StringName = &""
	## Enforces interaction reach.
	var check_distance: bool = true
	## Parameter schemas.
	var params: Dictionary = {}
	## Marks successful actions for the saving layer.
	var important: bool = false
	## Additional prerequisites, returning a failure or null.
	var check := Callable()
	## Applies the action and returns its changes.
	var apply := Callable()

## Validated inputs passed to action callbacks.
class Context extends RefCounted:
	## Owning session.
	var session: SessionService
	## Authoritative state.
	var state: ColonyState
	## Game clock.
	var clock: SolClock
	## Engineering settings.
	var config: GameConfig
	## Designer tuning.
	var balance: GameBalance
	## Original request.
	var request: ActionRequest
	## Registered rules.
	var definition: Definition
	## Owned actor, if required.
	var actor: CharacterState
	## Resolved station, item or cache.
	var target: Dictionary = {}
	## Resolved character target.
	var target_character: CharacterState
	## Target world position.
	var target_position := Vector3.ZERO
	## Whether distance applies to the target.
	var has_target_position: bool = false

var _definitions: Dictionary = {}
var _logs: Dictionary = {}

## Adds or replaces an action definition.
func register(action_definition: Definition) -> void:
	_definitions[action_definition.id] = action_definition

## Returns the rules, or null for an unknown action.
func definition(id: StringName) -> Definition:
	return _definitions.get(id) as Definition

## Drops remembered answers for a disconnected peer.
func forget_peer(peer_id: int) -> void:
	_logs.erase(peer_id)

## Resolves once, then emits the answer and successful state change.
func resolve(session: SessionService, request: ActionRequest) -> ActionResult:
	var result: ActionResult
	if not request.shape_problem().is_empty():
		result = ActionResult.failure(request.request_id, &"bad_request")
	else:
		var log: Dictionary = _logs.get(request.peer_id, {})
		if log.has(request.request_id):
			result = (log[request.request_id] as ActionResult).as_duplicate()
		else:
			result = _resolve_new(session, request)
			log[request.request_id] = ActionResult.from_dict(result.to_dict())
			while log.size() > maxi(0, session.config.remembered_requests):
				log.erase(log.keys()[0])
			_logs[request.peer_id] = log
	session.events.action_resolved.emit(result)
	if result.ok:
		session.events.state_changed.emit(request.action)
	return result

func _resolve_new(session: SessionService, request: ActionRequest) -> ActionResult:
	var d := definition(request.action)
	if d == null:
		return ActionResult.failure(request.request_id, &"unknown_action")
	if not _params_valid(d, request.params):
		return ActionResult.failure(request.request_id, &"bad_request")
	if d.host_only and request.peer_id != SessionService.HOST_PEER:
		return ActionResult.failure(request.request_id, &"host_only")
	if session.paused and not d.allowed_while_paused:
		return ActionResult.failure(request.request_id, &"paused")
	var ctx := Context.new()
	ctx.session = session
	ctx.state = session.state
	ctx.clock = session.clock
	ctx.config = session.config
	ctx.balance = session.balance
	ctx.request = request
	ctx.definition = d
	if d.needs_actor:
		if request.actor == &"":
			return ActionResult.failure(request.request_id, &"no_actor")
		ctx.actor = ctx.state.character(request.actor) if ctx.state != null else null
		if ctx.actor == null or ctx.actor.owner_peer != request.peer_id:
			return ActionResult.failure(request.request_id, &"not_owner")
	if d.target_kind != &"":
		if ctx.state == null:
			return ActionResult.failure(request.request_id, &"unknown_target")
		match d.target_kind:
			&"station": ctx.target = ctx.state.stations.get(request.target, {})
			&"item": ctx.target = ctx.state.items.get(request.target, {})
			&"cache":
				for cache: Dictionary in ctx.state.caches:
					if String(cache.id) == String(request.target):
						ctx.target = cache
			&"character": ctx.target_character = ctx.state.character(request.target)
		if ctx.target.is_empty() and ctx.target_character == null:
			return ActionResult.failure(request.request_id, &"unknown_target")
		if d.target_kind == &"station" and not d.station_kinds.is_empty() and not d.station_kinds.has(String(ctx.target.get("kind", ""))):
			return ActionResult.failure(request.request_id, &"wrong_target")
		ctx.has_target_position = ctx.target.has("position")
		if d.target_kind == &"item" and String(ctx.target.get("holder", "")) != "":
			ctx.has_target_position = false
		if ctx.has_target_position:
			ctx.target_position = CharacterState._v3(ctx.target.position)
	if d.check_distance and ctx.actor != null and ctx.has_target_position and ctx.actor.position.distance_to(ctx.target_position) > ctx.config.interact_distance_m:
		return ActionResult.failure(request.request_id, &"too_far")
	var specialty := d.specialty
	if specialty == &"" and d.target_kind == &"station":
		specialty = StringName(ctx.target.get("specialty", ""))
	if specialty != &"" and (ctx.actor == null or ctx.actor.specialty != specialty):
		return ActionResult.failure(request.request_id, &"wrong_specialty")
	if d.check.is_valid():
		var failure: ActionResult = d.check.call(ctx)
		if failure != null:
			return failure
	var changes: Dictionary = d.apply.call(ctx) if d.apply.is_valid() else {}
	return ActionResult.success(request.request_id, changes)

func _params_valid(d: Definition, params: Dictionary) -> bool:
	for key: Variant in params:
		if not d.params.has(key):
			return false
	for key: Variant in d.params:
		var rule: Dictionary = d.params[key]
		if not params.has(key):
			if not bool(rule.get("optional", false)):
				return false
			continue
		var value: Variant = params[key]
		var expected: int = rule.type
		if typeof(value) != expected and not (expected == TYPE_FLOAT and typeof(value) == TYPE_INT):
			return false
		if expected == TYPE_STRING and String(value).length() > 64:
			return false
		if expected == TYPE_INT or expected == TYPE_FLOAT:
			if float(value) < float(rule.get("min", -INF)) or float(value) > float(rule.get("max", INF)):
				return false
	return true
