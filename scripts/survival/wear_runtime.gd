class_name WearRuntime
extends RefCounted
## The single real-second operational-wear owner. It never runs from room or UI nodes.
## Maintenance restores condition only; future puzzle milestones and rewards remain separate.

var jobs: Dictionary = {}
const EPSILON := 0.00000001

static func register_actions(service: ActionService) -> void:
	for id: StringName in [&"maintenance_start", &"maintenance_cancel"]:
		var definition := ActionService.Definition.new()
		definition.id = id
		definition.target_kind = &"station"
		definition.station_kinds = PackedStringArray(["repair_task"])
		definition.params = {"generation": {"type": TYPE_INT, "min": 1}}
		if id == &"maintenance_cancel":
			definition.needs_actor = false
			definition.target_kind = &""
			definition.check_distance = false
			definition.allowed_while_paused = true
		definition.check = func(ctx: ActionService.Context) -> ActionResult: return ctx.session.wear_runtime.check(ctx)
		definition.apply = func(ctx: ActionService.Context) -> Dictionary: return ctx.session.wear_runtime.apply(ctx)
		service.register(definition)

func clear_session() -> void:
	jobs.clear()

func release_character(character_id: StringName) -> void:
	for task_id: String in jobs.keys():
		if String(jobs[task_id].actor) == String(character_id):
			jobs.erase(task_id)

func status(task_id: String) -> Dictionary:
	if not jobs.has(task_id):
		return {"active": false, "progress": 0.0, "elapsed_seconds": 0.0, "duration_seconds": 0.0}
	var result: Dictionary = jobs[task_id].duplicate(true)
	result.active = true
	result.progress = clampf(float(result.elapsed_seconds) / maxf(EPSILON, float(result.duration_seconds)), 0.0, 1.0)
	return result

func _valid_operator(session: SessionService, actor: CharacterState, task: Dictionary, generation: int) -> bool:
	if actor == null or actor.health <= 0.0 or actor.exposure_active or task.is_empty() or int(task.fault_generation) != generation:
		return false
	var specialty := String(task.required_specialty)
	if specialty != "general" and String(actor.specialty) != specialty:
		return false
	var station: Dictionary = session.state.stations.get(String(task.anchor_id), {})
	if String(station.get("kind", "")) != "repair_task" or String(station.get("task_id", "")) != String(task.task_id) or String(station.get("room_id", "")) != String(task.room_id):
		return false
	if actor.position.distance_to(CharacterState._v3(station.get("position", []))) > session.config.interact_distance_m:
		return false
	var zones: Array = RepairCatalog.ROOMS[String(task.room_id)].zones
	return zones.has(String(station.get("zone", ""))) and session.zone_at_position.is_valid() and zones.has(String(session.zone_at_position.call(actor.position)))

func check(ctx: ActionService.Context) -> ActionResult:
	if not ctx.session.authoritative:
		return ActionResult.failure(ctx.request.request_id, &"host_only")
	var task_id := _task_id(ctx)
	var task: Dictionary = ctx.state.repair.tasks.get(task_id, {})
	if task.is_empty() or String(task.anchor_id) != String(ctx.request.target):
		return ActionResult.failure(ctx.request.request_id, &"unknown_target")
	if ctx.request.action == &"maintenance_cancel":
		if jobs.has(task_id) and int(jobs[task_id].peer) != ctx.request.peer_id:
			return ActionResult.failure(ctx.request.request_id, &"not_owner")
		return null
	if int(task.fault_generation) != int(ctx.request.params.generation):
		return ActionResult.failure(ctx.request.request_id, &"stale_fault", "This equipment fault changed. Reopen maintenance.")
	if RepairCatalog.is_broken(ctx.state, task_id) and RepairCatalog.has_puzzle(task_id):
		return ActionResult.failure(ctx.request.request_id, &"repair_required", "Complete this machine's repair mini-game first.")
	if ctx.actor.exposure_active:
		return ActionResult.failure(ctx.request.request_id, &"unsafe_maintenance", "Use a functional suit or return to safe pressure before maintenance.")
	if not _valid_operator(ctx.session, ctx.actor, task, int(ctx.request.params.generation)):
		return ActionResult.failure(ctx.request.request_id, &"wrong_room", "Stand beside this equipment with the required healthy specialist.")
	if jobs.has(task_id) or ctx.session.repair_runtime.locks.has(task_id):
		return ActionResult.failure(ctx.request.request_id, &"task_busy", "Another operation is already using this equipment.")
	if float(task.condition) >= 1.0 - EPSILON and not bool(task.get("maintenance_fault", false)):
		return ActionResult.failure(ctx.request.request_id, &"missing_prerequisite", "This equipment is already in full condition.")
	return null

func apply(ctx: ActionService.Context) -> Dictionary:
	var task_id := _task_id(ctx)
	if ctx.request.action == &"maintenance_cancel":
		jobs.erase(task_id)
		return {"task_id": task_id, "cancelled": true}
	jobs[task_id] = {"peer": ctx.request.peer_id, "actor": String(ctx.actor.id), "generation": int(ctx.request.params.generation),
		"elapsed_seconds": 0.0, "duration_seconds": maxf(0.1, ctx.balance.maintenance_repair_seconds)}
	return {"task_id": task_id, "maintenance_started": true, "duration_seconds": jobs[task_id].duration_seconds}

func _task_id(ctx: ActionService.Context) -> String:
	if not ctx.target.is_empty():
		return String(ctx.target.get("task_id", ""))
	for task_id: String in RepairCatalog.TASKS:
		if RepairCatalog.anchor_id(task_id) == String(ctx.request.target):
			return task_id
	return ""

func prune(session: SessionService) -> void:
	for task_id: String in jobs.keys():
		var job: Dictionary = jobs[task_id]
		var actor := session.state.character(StringName(job.actor))
		var task: Dictionary = session.state.repair.tasks.get(task_id, {})
		if actor == null or actor.owner_peer != int(job.peer) or not _valid_operator(session, actor, task, int(job.generation)):
			jobs.erase(task_id)
			session.events.state_changed.emit(&"maintenance_cancelled")

func advance(session: SessionService, real_delta: float) -> void:
	if not session.authoritative or session.paused or session.state == null or real_delta <= 0.0:
		return
	prune(session)
	# The opening restoration phase cannot use maintenance stations. Keep its repaired
	# machines intact, and never reset an unfinished mini-game through background wear.
	if TutorialSystem.tutorial_active(session.state):
		return
	for task_id: String in RepairCatalog.TASKS:
		var remaining := real_delta
		if jobs.has(task_id):
			var job: Dictionary = jobs[task_id]
			var until_done := maxf(0.0, float(job.duration_seconds) - float(job.elapsed_seconds))
			var working := minf(remaining, until_done)
			_wear_task(session, task_id, working)
			job.elapsed_seconds = float(job.elapsed_seconds) + working
			remaining -= working
			if float(job.elapsed_seconds) >= float(job.duration_seconds) - EPSILON:
				if restore_task(session, task_id, int(job.generation)):
					session.events.system_alert.emit(StringName("maintenance_" + task_id), &"info", "%s equipment maintained. Room puzzle milestones are unchanged." % String(session.state.repair.tasks[task_id].title))
				jobs.erase(task_id)
				session.events.state_changed.emit(&"maintenance_completed")
		_wear_task(session, task_id, remaining)
	_wear_cleaner(session, real_delta)
	_update_rooms(session.state)

func _wear_task(session: SessionService, task_id: String, real_delta: float) -> void:
	if real_delta <= 0.0 or not session.balance.maintenance_enabled:
		return
	var task: Dictionary = session.state.repair.tasks[task_id]
	var grace := minf(real_delta, maxf(0.0, float(task.get("maintenance_cooldown_seconds", 0.0))))
	task.maintenance_cooldown_seconds = maxf(0.0, float(task.get("maintenance_cooldown_seconds", 0.0)) - grace)
	var elapsed := real_delta - grace
	var rate := maxf(0.0, session.balance.maintenance_wear_per_second)
	if elapsed <= 0.0 or rate <= 0.0:
		return
	task.wear_elapsed_seconds = float(task.get("wear_elapsed_seconds", 0.0)) + elapsed
	task.condition = maxf(0.0, float(task.condition) - elapsed * rate)
	if float(task.condition) <= session.balance.maintenance_warning_condition + EPSILON and not bool(task.get("warning_active", false)):
		task.warning_active = true
		session.events.system_alert.emit(StringName("wear_" + task_id), &"warn", "%s: %s equipment condition is %.0f %%. Maintenance is available at its station." % [RepairCatalog.ROOMS[String(task.room_id)].title, task.title, float(task.condition) * 100.0])
	if float(task.condition) <= session.balance.maintenance_fault_condition + EPSILON and not bool(task.get("maintenance_fault", false)):
		var seed_value := int(task.puzzle_seed) + 7919
		session.repair_runtime.begin_fault(session.state, task_id, seed_value, float(task.condition))
		if jobs.has(task_id):
			# Keep an already authorized host-timed maintenance job through the wear transition.
			jobs[task_id].generation = int(task.fault_generation)
		session.events.system_alert.emit(StringName("fault_" + task_id), &"warn", "%s: %s maintenance fault. Use Equipment maintenance with the required specialist." % [RepairCatalog.ROOMS[String(task.room_id)].title, task.title])
		session.events.state_changed.emit(&"maintenance_fault")

## Host-only repair hook shared by generic maintenance and a future completed puzzle.
func restore_task(session: SessionService, task_id: String, generation: int) -> bool:
	if not session.authoritative or session.state == null or not session.state.repair.tasks.has(task_id):
		return false
	var task: Dictionary = session.state.repair.tasks[task_id]
	if int(task.fault_generation) != generation:
		return false
	if RepairCatalog.is_broken(session.state, task_id) and RepairCatalog.has_puzzle(task_id):
		return false
	task.condition = 1.0
	task.broken = false
	task.maintenance_fault = false
	task.warning_active = false
	task.wear_elapsed_seconds = 0.0
	task.maintenance_cooldown_seconds = maxf(0.0, session.balance.maintenance_repair_cooldown_seconds)
	_update_rooms(session.state)
	return true

func on_task_repaired(session: SessionService, task_id: String) -> void:
	if session.state != null and session.state.repair.tasks.has(task_id):
		restore_task(session, task_id, int(session.state.repair.tasks[task_id].fault_generation))

func on_legacy_repaired(session: SessionService, equipment_id: String) -> void:
	if not session.authoritative or session.state == null or equipment_id != "cleaner":
		return
	var record: Dictionary = session.state.repair.legacy_maintenance.cleaner
	record.last_condition = session.state.condition_of("cleaner")
	record.maintenance_cooldown_seconds = maxf(0.0, session.balance.maintenance_repair_cooldown_seconds)
	record.wear_elapsed_seconds = 0.0
	record.warning_active = false

## Controlled verification hook; no player action registers this operation.
func force_fault(session: SessionService, task_id: String, condition := 0.4) -> bool:
	if not session.authoritative or session.state == null or not session.state.repair.tasks.has(task_id):
		return false
	var task: Dictionary = session.state.repair.tasks[task_id]
	return session.repair_runtime.begin_fault(session.state, task_id, int(task.puzzle_seed) + 7919, clampf(condition, 0.0, 1.0))

func _wear_cleaner(session: SessionService, real_delta: float) -> void:
	if not session.balance.maintenance_enabled or not session.state.equipment.has("cleaner"):
		return
	var cleaner: Dictionary = session.state.equipment.cleaner
	var record: Dictionary = session.state.repair.legacy_maintenance.cleaner
	var condition := float(cleaner.condition)
	if float(record.last_condition) >= 0.0 and condition > float(record.last_condition) + EPSILON:
		record.maintenance_cooldown_seconds = maxf(0.0, session.balance.maintenance_repair_cooldown_seconds)
		record.wear_elapsed_seconds = 0.0
		record.warning_active = false
	var grace := minf(real_delta, maxf(0.0, float(record.maintenance_cooldown_seconds)))
	record.maintenance_cooldown_seconds = maxf(0.0, float(record.maintenance_cooldown_seconds) - grace)
	var elapsed := real_delta - grace
	cleaner.condition = maxf(0.0, condition - maxf(0.0, session.balance.cleaner_wear_per_second) * elapsed)
	record.wear_elapsed_seconds = float(record.wear_elapsed_seconds) + elapsed
	record.last_condition = float(cleaner.condition)
	if condition > session.balance.maintenance_warning_condition and float(cleaner.condition) <= session.balance.maintenance_warning_condition and not bool(record.warning_active):
		record.warning_active = true
		session.events.system_alert.emit(&"cleaner_wear", &"warn", "Panel cleaner condition is falling. The electrical specialist can repair it at a sun tracker after it fails.")

func _update_rooms(state: ColonyState) -> void:
	for room_id: String in RepairCatalog.ROOMS:
		var condition := 0.0
		var ids: Array = RepairCatalog.ROOMS[room_id].tasks
		for task_id: String in ids:
			condition += float(state.repair.tasks[task_id].condition) / float(ids.size())
		state.repair.rooms[room_id].condition = condition

func replica_dict() -> Dictionary:
	return {"jobs": jobs.duplicate(true)}

func apply_replica(data: Dictionary) -> void:
	jobs = (data.get("jobs", {}) as Dictionary).duplicate(true)
