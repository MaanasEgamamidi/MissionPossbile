class_name CassetteActions
extends RefCounted

static func register(service: ActionService) -> void:
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
