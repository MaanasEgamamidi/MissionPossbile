class_name RepairRuntime
extends RefCounted
## Host-only rule registry and transient leases. Neither callbacks nor operator leases enter a save.
## A future puzzle registers a pure validator: (task_copy, {move, value}) ->
## {accepted, puzzle_state, progress, complete}. Only that server rule can decide completion.

const CLAIM_SECONDS := 30.0
## Reach is measured to the whole broken object (2026-11-14), not only the floor anchor.
const RepairReach := preload("res://scripts/tasks/repair_reach.gd")
var locks: Dictionary = {}
var _rules: Dictionary = {}
var _resume_rules: Dictionary = {}
var _accepted: Dictionary = {}
var _elapsed := 0.0

func register_rule(task_id: String, validator: Callable, supports_resume := false) -> void:
	if RepairCatalog.TASKS.has(task_id) and validator.is_valid():
		_rules[task_id] = validator
		_resume_rules[task_id] = supports_resume

func clear_session() -> void:
	locks.clear()
	_accepted.clear()
	_elapsed = 0.0

func release_character(character_id: StringName) -> void:
	for task_id: String in locks.keys():
		if String(locks[task_id].actor) == String(character_id):
			locks.erase(task_id)

func advance(session: SessionService, real_delta: float) -> void:
	_elapsed += maxf(0.0, real_delta)
	prune(session)

func prune(session: SessionService) -> void:
	var changed := false
	for task_id: String in locks.keys():
		var lease: Dictionary = locks[task_id]
		var actor := session.state.character(StringName(lease.actor))
		var task: Dictionary = session.state.repair.tasks.get(task_id, {})
		if _elapsed >= float(lease.expires) or actor == null or actor.owner_peer != int(lease.peer) or not _eligible(session, actor, task):
			locks.erase(task_id)
			changed = true
	if changed:
		session.events.state_changed.emit(&"repair_lock")

func _eligible(session: SessionService, actor: CharacterState, task: Dictionary) -> bool:
	if task.is_empty() or actor.health <= 0.0:
		return false
	var specialty := String(task.required_specialty)
	if specialty != "general" and String(actor.specialty) != specialty:
		return false
	var station: Dictionary = session.state.stations.get(String(task.anchor_id), {})
	if station.is_empty() or not RepairReach.within(station, actor.position, session.config.interact_distance_m):
		return false
	if String(station.get("task_id", "")) != String(task.task_id) or String(station.get("room_id", "")) != String(task.room_id):
		return false
	var zones: Array = RepairCatalog.ROOMS[String(task.room_id)].zones
	if not zones.has(String(station.get("zone", ""))):
		return false
	return not session.zone_at_position.is_valid() or zones.has(String(session.zone_at_position.call(actor.position)))

func check(ctx: ActionService.Context) -> ActionResult:
	var task_id := String(ctx.target.get("task_id", ""))
	var task: Dictionary = ctx.state.repair.tasks.get(task_id, {})
	if task.is_empty() or String(task.anchor_id) != String(ctx.request.target):
		return ActionResult.failure(ctx.request.request_id, &"unknown_target")
	if ctx.session.wear_runtime.jobs.has(task_id):
		return ActionResult.failure(ctx.request.request_id, &"task_busy", "Equipment maintenance is already running here.")
	if int(ctx.request.params.generation) != int(task.fault_generation):
		return ActionResult.failure(ctx.request.request_id, &"stale_fault", "This fault changed. Reopen the task to refresh it.")
	var specialty := String(task.required_specialty)
	if specialty != "general" and String(ctx.actor.specialty) != specialty:
		return ActionResult.failure(ctx.request.request_id, &"wrong_specialty", "Switch to %s to work on %s." % [specialty.replace("_", " "), task.title])
	if not _eligible(ctx.session, ctx.actor, task):
		return ActionResult.failure(ctx.request.request_id, &"wrong_room", "Stand beside this task in its room with a healthy crew member.")
	var lease: Dictionary = locks.get(task_id, {})
	if not lease.is_empty() and (int(lease.peer) != ctx.request.peer_id or String(lease.actor) != String(ctx.actor.id)):
		return ActionResult.failure(ctx.request.request_id, &"task_busy", "Another crew member is operating this task.")
	if ctx.request.action in [&"task_claim", &"task_resume"]:
		return null
	if lease.is_empty():
		return ActionResult.failure(ctx.request.request_id, &"task_unclaimed", "Reopen the task to claim it before making a move.")
	if ctx.request.action == &"task_release":
		return null
	if float(task.progress) >= 1.0:
		return ActionResult.failure(ctx.request.request_id, &"task_complete", "This fault is already repaired.")
	if not _rules.has(task_id):
		return ActionResult.failure(ctx.request.request_id, &"not_available_yet", "This repair puzzle is not installed yet.")
	var result: Variant = (_rules[task_id] as Callable).call(task.duplicate(true), {"move": ctx.request.params.move, "value": int(ctx.request.params.value)})
	if not result is Dictionary or not bool(result.get("accepted", false)):
		return ActionResult.failure(ctx.request.request_id, &"invalid_move", "That move is not valid for the current puzzle.")
	var progress := float(result.get("progress", task.progress))
	if is_nan(progress) or is_inf(progress) or progress > 1.0 or progress < 0.0:
		return ActionResult.failure(ctx.request.request_id, &"invalid_move")
	if not result.get("puzzle_state", {}) is Dictionary or (progress >= 1.0) != bool(result.get("complete", false)):
		return ActionResult.failure(ctx.request.request_id, &"invalid_move")
	_accepted[ctx.request.request_id] = result.duplicate(true)
	return null

func apply(ctx: ActionService.Context) -> Dictionary:
	var task_id := String(ctx.target.task_id)
	var task: Dictionary = ctx.state.repair.tasks[task_id]
	if ctx.request.action == &"task_release":
		locks.erase(task_id)
		return {"task_id": task_id, "released": true}
	locks[task_id] = {"peer": ctx.request.peer_id, "actor": String(ctx.actor.id), "expires": _elapsed + CLAIM_SECONDS}
	if ctx.request.action != &"task_move":
		return {"task_id": task_id, "claimed": true, "generation": int(task.fault_generation)}
	var outcome: Dictionary = _accepted[ctx.request.request_id]
	_accepted.erase(ctx.request.request_id)
	task.puzzle_state = (outcome.get("puzzle_state", {}) as Dictionary).duplicate(true)
	task.resume_supported = bool(_resume_rules.get(task_id, false))
	task.progress = float(outcome.get("progress", task.progress))
	var first_completion := false
	if bool(outcome.get("complete", false)):
		first_completion = not bool(task.first_completed)
		task.first_completed = true
		task.condition = 1.0
		locks.erase(task_id)
		ctx.session.wear_runtime.on_task_repaired(ctx.session, task_id)
		_update_room(ctx.state, String(task.room_id))
	return {"task_id": task_id, "progress": task.progress, "first_completion": first_completion,
		"generation": int(task.fault_generation)}

## Future host deterioration systems call this, never a client action. Achievements and shot history survive wear.
func begin_fault(state: ColonyState, task_id: String, puzzle_seed: int, condition: float = 0.0) -> bool:
	if not state.repair.tasks.has(task_id):
		return false
	var task: Dictionary = state.repair.tasks[task_id]
	task.fault_generation = int(task.fault_generation) + 1
	task.puzzle_seed = puzzle_seed
	task.progress = 0.0
	task.condition = clampf(condition, 0.0, 1.0)
	task.puzzle_state = {}
	task.resume_supported = false
	task.maintenance_fault = true
	locks.erase(task_id)
	_update_room(state, String(task.room_id))
	return true

func _update_room(state: ColonyState, room_id: String) -> void:
	var completed := true
	var condition := 0.0
	var ids: Array = RepairCatalog.ROOMS[room_id].tasks
	for id: String in ids:
		var task: Dictionary = state.repair.tasks[id]
		completed = completed and bool(task.first_completed)
		condition += float(task.condition) / float(ids.size())
	var room: Dictionary = state.repair.rooms[room_id]
	room.first_completed = bool(room.first_completed) or completed
	room.condition = condition

func replica_dict() -> Dictionary:
	return {"locks": locks.duplicate(true), "elapsed": _elapsed}

func apply_replica(data: Dictionary) -> void:
	locks = (data.get("locks", {}) as Dictionary).duplicate(true)
	_elapsed = float(data.get("elapsed", 0.0))
