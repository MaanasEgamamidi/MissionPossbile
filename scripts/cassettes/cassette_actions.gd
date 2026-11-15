class_name CassetteActions
extends RefCounted

static func register(service: ActionService) -> void:
	var demo := ActionService.Definition.new()
	demo.id = &"demo_collect_cassettes"
	demo.host_only = false  # demo cheats: every player may use them
	demo.needs_actor = false
	demo.check_distance = false
	demo.allowed_while_paused = true
	demo.important = true
	demo.check = func(ctx: ActionService.Context) -> ActionResult:
		return null if ctx.state != null else ActionResult.failure(ctx.request.request_id, &"no_game")
	demo.apply = func(ctx: ActionService.Context) -> Dictionary:
		var added := 0
		for tape_id: String in CassetteCatalog.TAPES:
			if not CassetteCatalog.collected(ctx.state, tape_id):
				(ctx.state.repair.collected_cassettes as Array).append(tape_id)
				added += 1
		TutorialSystem.advance_tutorial(ctx.state, ctx.balance, ctx.session.events)
		return {"added": added, "collected": TutorialSystem.tapes_found(ctx.state), "text": "Demo: all 6 cassettes collected. Play any tape in the Command Room."}
	service.register(demo)
	# Demo cheat (mouse forward button): every tape collected AND played at the Command Room deck.
	var demo_play := ActionService.Definition.new()
	demo_play.id = &"demo_play_cassettes"
	demo_play.host_only = false  # demo cheats: every player may use them
	demo_play.needs_actor = false
	demo_play.check_distance = false
	demo_play.allowed_while_paused = true
	demo_play.important = true
	demo_play.check = func(ctx: ActionService.Context) -> ActionResult:
		return null if ctx.state != null else ActionResult.failure(ctx.request.request_id, &"no_game")
	demo_play.apply = func(ctx: ActionService.Context) -> Dictionary:
		var events := ctx.session.events if ctx.session != null else null
		var played: Array = TutorialSystem.ensure(ctx.state).tutorial.played
		for tape_id: String in CassetteCatalog.TAPES:
			if not CassetteCatalog.collected(ctx.state, tape_id):
				(ctx.state.repair.collected_cassettes as Array).append(tape_id)
			if not played.has(tape_id):
				played.append(tape_id)
				if events != null:
					events.objective_changed.emit(StringName("played_" + tape_id))
		RepairActions.fix_all_areas(ctx)
		TutorialSystem.advance_tutorial(ctx.state, ctx.balance, events)
		return {"text": "Demo: all %d cassettes found and played." % TutorialSystem.tape_count()}
	service.register(demo_play)
	for id: StringName in [&"cassette_collect", &"cassette_open", &"cassette_select", &"cassette_read", &"cassette_close"]:
		var definition := ActionService.Definition.new()
		definition.id = id
		definition.target_kind = &"station"
		definition.station_kinds = PackedStringArray(["cassette_anchor"] if id == &"cassette_collect" else ["cassette_player_anchor"])
		definition.important = id == &"cassette_collect"
		if id in [&"cassette_select", &"cassette_read"]:
			definition.params = {"cassette_id": {"type": TYPE_STRING}}
		if id == &"cassette_read":
			definition.params["page"] = {"type": TYPE_INT, "min": 0, "max": 1000}
		if id == &"cassette_close":
			definition.needs_actor = false
			definition.target_kind = &""
			definition.check_distance = false
			definition.allowed_while_paused = true
		definition.check = func(ctx: ActionService.Context) -> ActionResult: return ctx.session.cassette_runtime.check(ctx)
		definition.apply = func(ctx: ActionService.Context) -> Dictionary: return ctx.session.cassette_runtime.apply(ctx)
		service.register(definition)
