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
	# Demo cheat (P): Communication track to its top level, every radio card installed, and only the comms area's repairs
	# fixed (nothing else). With "summon", the other
	# human player's character is moved 1 m behind and 1 m left of the host (the client takes the host's pose through
	# the replicated character_recovered event, flagged demo_teleport).
	var comms := ActionService.Definition.new()
	comms.id = &"demo_max_comms"
	comms.host_only = false  # demo cheats: every player may use them
	comms.needs_actor = false
	comms.check_distance = false
	comms.allowed_while_paused = true
	comms.important = false  # no save on press: the teleport replicates at once
	comms.params = {"summon": {"type": TYPE_BOOL}}
	comms.check = func(ctx: ActionService.Context) -> ActionResult:
		return null if ctx.state != null else ActionResult.failure(ctx.request.request_id, &"no_game")
	comms.apply = func(ctx: ActionService.Context) -> Dictionary:
		var st := ctx.state
		st.levels["command"] = AreaLevels.levels_of("command")
		for card: String in CommsStage.CARD_IDS:
			if not st.has_upgrade(card):
				st.upgrades[card] = {"installed": true, "by": "demo", "at_hours": st.sim_hours, "parts": 0,
					"station": CommsStage.INSTALL_STATION, "sector": "energy"}
		fix_rooms(ctx, ["command_center"])  # only the comms area (T01 comms, T02 wires); every other area stays broken
		TutorialSystem.advance_tutorial(st, ctx.balance, ctx.session.events)
		var text := "Demo: radio communication maxed out; the comms area is fixed."
		if bool(ctx.request.params.get("summon", false)):
			var me := st.character_of_peer(ctx.request.peer_id)
			var other: CharacterState = null
			for c: CharacterState in st.active_characters():
				if me != null and c.id != me.id and c.owner_peer > 0 and c.owner_peer != ctx.request.peer_id:
					other = c
					break
			if me == null or other == null:
				text += " No other player to bring over."
			else:
				other.position = me.position + Basis(Vector3.UP, me.yaw) * Vector3(-1.0, 0.0, 1.0)
				other.yaw = me.yaw
				other.outside = me.outside
				if ctx.session.events != null:
					ctx.session.events.character_recovered.emit(other.id, {"demo_teleport": true})
				text += " %s is behind you." % other.display_name
				return {"text": text, "summoned": true}
		return {"text": text}
	service.register(comms)
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


## Demo cheat (P): only the repairs of the rooms in `rooms` (RepairCatalog.ROOMS ids) finished. Returns how many changed.
static func fix_rooms(ctx: ActionService.Context, rooms: Array) -> int:
	var fixed := 0
	for room_id: String in rooms:
		for task_id: String in (RepairCatalog.ROOMS.get(room_id, {}) as Dictionary).get("tasks", []):
			if ctx.session.repair_runtime.force_complete(ctx.session, task_id):
				fixed += 1
	return fixed


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
