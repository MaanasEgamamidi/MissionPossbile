class_name RepairActions
extends RefCounted
## Additive actions; completion has no client-callable action or boolean parameter.

static func register(service: ActionService) -> void:
	# Demo cheat (mouse back button): every tutorial repair finished as if its mini-game was solved.
	var demo := ActionService.Definition.new()
	demo.id = &"demo_fix_repairs"
	demo.host_only = false  # demo cheats: every player may use them
	demo.needs_actor = false
	demo.check_distance = false
	demo.allowed_while_paused = true
	demo.important = true
	demo.check = func(ctx: ActionService.Context) -> ActionResult:
		return null if ctx.state != null else ActionResult.failure(ctx.request.request_id, &"no_game")
	demo.apply = func(ctx: ActionService.Context) -> Dictionary:
		var fixed := fix_all_areas(ctx)
		TutorialSystem.advance_tutorial(ctx.state, ctx.balance, ctx.session.events)
		return {"fixed": fixed, "text": "Demo: all %d tutorial repairs fixed." % TutorialSystem.required_fixes().size()}
	service.register(demo)
	# Demo cheat (P): ONLY a teleport. Every other human player is moved diagonally behind-left of the one who pressed
	# it (the first 1 m back and 1 m left, each next one another step further along the same diagonal), facing the
	# same way. Nothing is fixed or upgraded. Clients take the new pose through the replicated character_recovered
	# event, flagged demo_teleport.
	var summon := ActionService.Definition.new()
	summon.id = &"demo_summon_players"
	summon.host_only = false  # demo cheats: every player may use them
	summon.needs_actor = false
	summon.check_distance = false
	summon.allowed_while_paused = true
	summon.important = false  # no save on press: the teleport replicates at once
	summon.check = func(ctx: ActionService.Context) -> ActionResult:
		return null if ctx.state != null else ActionResult.failure(ctx.request.request_id, &"no_game")
	summon.apply = func(ctx: ActionService.Context) -> Dictionary:
		var st := ctx.state
		var me := st.character_of_peer(ctx.request.peer_id)
		if me == null:
			return {"text": "Demo: no character to bring players to."}
		var basis := Basis(Vector3.UP, me.yaw)
		var moved: Array[String] = []
		for c: CharacterState in st.active_characters():
			if c.id == me.id or c.owner_peer <= 0 or c.owner_peer == ctx.request.peer_id:
				continue
			var step := float(moved.size() + 1)
			c.position = me.position + basis * Vector3(-1.0 * step, 0.0, 1.0 * step)  # left (-x) and back (+z)
			c.yaw = me.yaw
			c.outside = me.outside
			if ctx.session.events != null:
				ctx.session.events.character_recovered.emit(c.id, {"demo_teleport": true})
			moved.append(c.display_name)
		if moved.is_empty():
			return {"text": "Demo: no other players to bring over."}
		return {"text": "Demo: %s behind you." % ", ".join(moved)}
	service.register(summon)
	for id: StringName in [&"task_claim", &"task_resume", &"task_move", &"task_release"]:
		var definition := ActionService.Definition.new()
		definition.id = id
		definition.target_kind = &"station"
		definition.station_kinds = PackedStringArray(["repair_task"])
		definition.important = id == &"task_move"
		definition.params = {"generation": {"type": TYPE_INT, "min": 1}}
		if id == &"task_move":
			definition.params["move"] = {"type": TYPE_STRING}
			definition.params["value"] = {"type": TYPE_INT}
		definition.check = func(ctx: ActionService.Context) -> ActionResult: return ctx.session.repair_runtime.check(ctx)
		definition.apply = func(ctx: ActionService.Context) -> Dictionary: return ctx.session.repair_runtime.apply(ctx)
		service.register(definition)


## Demo cheats: every repair in every area finished, so every room looks fixed, except the tasks of the rooms in
## `skip_rooms` (RepairCatalog.ROOMS ids, e.g. "med_bay"). Returns how many changed.
static func fix_all_areas(ctx: ActionService.Context, skip_rooms: Array = []) -> int:
	var fixed := 0
	var skip := {}
	for room_id: String in skip_rooms:
		for task_id: String in (RepairCatalog.ROOMS.get(room_id, {}) as Dictionary).get("tasks", []):
			skip[task_id] = true
	for task_id: String in TutorialSystem.required_fixes():
		if not skip.has(task_id) and ctx.session.repair_runtime.force_complete(ctx.session, task_id):
			fixed += 1
	for task_id: String in ctx.state.repair.tasks.keys():
		if not skip.has(task_id) and ctx.session.repair_runtime.force_complete(ctx.session, task_id):
			fixed += 1
	return fixed
