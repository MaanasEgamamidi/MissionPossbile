class_name TutorialActions
extends RefCounted
## Host actions of the tutorial and the optional story, validated by ActionService like every other action.
##   read_record      at a record station (kind "record", data/stations_lore.json): finds its first-crew record
##                    once for the colony (state.discoveries) and any discovery it completes. Reading it again shows
##                    the same text and changes nothing.
##   tutorial_replay  params {"stage": 1..3}: a reminder of a step the colony has already finished. It repeats Mission
##                    Control's lines of that step to the player who asked and changes nothing (nothing counts twice).
##                    0 is accepted and does nothing (the old "stop the reminder").
## It also lets the tutorial see the real actions it is about (TutorialSystem.watched_actions(): the tapes played at
## the Command Room cassette player, records at salvage donors, suit refills): each of those definitions gets its
## `apply` wrapped so that, after the action has changed the colony, TutorialSystem.observe records it. The wrapped
## action behaves exactly as before and returns the same changes; no other part's file is edited.
## Register this LAST in SessionService._init, after every part whose actions the tutorial watches.

const ACTIONS: Array[StringName] = [&"read_record", &"tutorial_replay"]
const WRAPPED_META := &"tutorial_observed"


static func register(service: ActionService) -> void:
	var read := ActionService.Definition.new()
	read.id = &"read_record"
	read.target_kind = &"station"
	read.station_kinds = PackedStringArray(["record"])
	read.important = true
	read.check = _check
	read.apply = _apply
	service.register(read)
	var replay := ActionService.Definition.new()
	replay.id = &"tutorial_replay"
	replay.check_distance = false
	replay.allowed_while_paused = true
	replay.params = {"stage": {"type": TYPE_INT, "min": 0, "max": TutorialSystem.STAGE_COUNT}}
	replay.check = _check
	replay.apply = _apply
	service.register(replay)
	observe_watched(service)


## Wraps every watched action that is registered. Safe to call again (a definition is wrapped once).
## Returns the watched action ids that are not registered (yet).
static func observe_watched(service: ActionService) -> PackedStringArray:
	var missing := PackedStringArray()
	for id: String in TutorialSystem.watched_actions():
		var d := service.definition(StringName(id))
		if d == null:
			missing.append(id)
			continue
		if d.has_meta(WRAPPED_META):
			continue
		var inner: Callable = d.apply
		d.apply = func(ctx: ActionService.Context) -> Dictionary:
			var changes: Dictionary = inner.call(ctx) if inner.is_valid() else {}
			TutorialSystem.observe(ctx, changes)
			return changes
		d.set_meta(WRAPPED_META, true)
	return missing


## True when the action `id` is watched by the tutorial in this service.
static func is_observed(service: ActionService, id: StringName) -> bool:
	var d := service.definition(id)
	return d != null and d.has_meta(WRAPPED_META)


static func _check(ctx: ActionService.Context) -> ActionResult:
	match ctx.request.action:
		&"read_record":
			if TutorialSystem.records_at(String(ctx.request.target), "read_record").is_empty():
				return ActionResult.failure(ctx.request.request_id, &"unknown_target", "There is nothing to read here.")
		&"tutorial_replay":
			var n := int(ctx.request.params.stage)
			if n > 0 and not TutorialSystem.is_stage_completed(ctx.state, n):
				return ActionResult.failure(ctx.request.request_id, &"missing_prerequisite",
					"Step %d is not done yet, so there is nothing to remind you of. Follow Mission Control instead." % n)
	return null


static func _apply(ctx: ActionService.Context) -> Dictionary:
	var changes := {"action": String(ctx.request.action), "target": String(ctx.request.target)}
	match ctx.request.action:
		&"read_record":
			var rec: Dictionary = TutorialSystem.records_at(String(ctx.request.target), "read_record")[0]
			var id := String(rec.id)
			var found := TutorialSystem.discover_record(ctx.state, ctx.session.events, id, ctx.actor.id, "read_record", String(ctx.request.target))
			changes["record_id"] = id
			changes["new"] = bool(found.new)
			changes["discoveries"] = (found.discoveries as Array).duplicate()
			changes["text"] = "%s: %s" % [String(rec.get("title", "")), String(rec.get("text", ""))]
			if not bool(found.new):
				changes["text"] += " (The colony has read this record before.)"
		&"tutorial_replay":
			var n := int(ctx.request.params.stage)
			changes["stage"] = n
			if n == 0:
				changes["text"] = ""
			else:
				var lines := TutorialSystem.reminder_lines(n)
				changes["lines"] = Array(lines)
				changes["text"] = "Reminder of step %d, %s:\n%s" % [n, String(TutorialSystem.stage_def(n).get("title", "")), "\n".join(lines)]
	return changes
