class_name AreaLevelActions
extends RefCounted
## Host action of the visible upgrade paths (data/area_levels.json, AreaLevels).
##   upgrade_area  at a station that serves the track, by the track's specialist (empty = anyone); params track.
##                 Raises state.levels[track] by one, spends the next level's spare parts exactly once, and keeps a
##                 record in state.ledger. Effects that change a stored number (the battery capacity) are applied here,
##                 once; every other effect is read each tick through AreaLevels.effect().

const ACTIONS: Array[StringName] = [&"upgrade_area"]


static func register(service: ActionService) -> void:
	var d := ActionService.Definition.new()
	d.id = &"upgrade_area"
	d.check = _check
	d.apply = _apply
	d.target_kind = &"station"
	d.params = {"track": {"type": TYPE_STRING}}
	d.important = true
	service.register(d)


static func _fail(ctx: ActionService.Context, reason: StringName, text: String) -> ActionResult:
	return ActionResult.failure(ctx.request.request_id, reason, text)


static func _check(ctx: ActionService.Context) -> ActionResult:
	var id := String(ctx.request.params.track)
	if AreaLevels.track(id).is_empty():
		return _fail(ctx, &"unknown_target", "That upgrade path does not exist.")
	if not AreaLevels.station_serves(id, String(ctx.request.target), ctx.target):
		return _fail(ctx, &"wrong_target", "Upgrade %s at its own station." % AreaLevels.track_name(id).to_lower())
	var lacking := AreaLevels.blockers(ctx.state, id, ctx.actor)
	if not lacking.is_empty():
		var first: Dictionary = lacking[0]
		var reason: StringName = &"insufficient" if String(first.kind) == "parts" else &"missing_prerequisite"
		if String(first.kind) == "max":
			reason = &"already_done"
		return _fail(ctx, reason, String(first.text))
	return null


static func _apply(ctx: ActionService.Context) -> Dictionary:
	var st := ctx.state
	var id := String(ctx.request.params.track)
	var before := AreaLevels.level(st, id)
	var after := before + 1
	var cost := AreaLevels.cost_to_reach(id, after)
	st.parts -= cost
	st.levels[id] = after
	st.ledger["parts_used_area_levels"] = float(st.ledger.get("parts_used_area_levels", 0.0)) + float(cost)
	# Stored-number effects, applied once at the level change.
	var cap_before := -1.0
	if id == "energy":
		var f0 := float(AreaLevels.effect_at(id, "battery_capacity_factor", before, 1.0))
		var f1 := float(AreaLevels.effect_at(id, "battery_capacity_factor", after, 1.0))
		cap_before = float(st.capacities.get(&"battery_kwh", 0.0))
		if f0 > 0.0:
			st.capacities[&"battery_kwh"] = cap_before * f1 / f0
	var text := "%s upgraded to %s." % [AreaLevels.track_name(id), AreaLevels.stage_text(id, after)]
	var changes := {"action": "upgrade_area", "target": String(ctx.request.target), "track": id,
		"level_before": before, "level": after, "parts_used": cost, "text": text}
	if cap_before >= 0.0:
		changes["battery_capacity_before_kwh"] = cap_before
		changes["battery_capacity_after_kwh"] = float(st.capacities.get(&"battery_kwh", 0.0))
	ctx.session.events.system_alert.emit(StringName("area_level_" + id), &"info", text)
	return changes
