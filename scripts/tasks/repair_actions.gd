class_name RepairActions
extends RefCounted
## Additive actions; completion has no client-callable action or boolean parameter.

static func register(service: ActionService) -> void:
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
