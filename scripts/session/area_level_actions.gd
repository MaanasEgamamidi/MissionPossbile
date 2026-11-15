class_name AreaLevelActions
extends RefCounted
## Host actions of the upgrade paths (data/area_levels.json, AreaLevels) and the colony's one build a day
## (scripts/upgrades/colony_builds.gd has the rules and the state.build fields):
##   build_propose  at the core spot of the track's section; params track, choice (optional: the fork side, e.g.
##                  "fuel_cell" or "reactor" for night power V3). Opens the colony's vote with the proposer's yes; in
##                  solo play (or when every player crewmate in radio reach already agrees) it builds at once.
##   upgrade_area   the same as build_propose (kept for older callers and tests).
##   build_vote     from anywhere; params yes (bool). Only player crewmates within comms reach can vote; one "no" ends
##                  the vote. When every voter in reach said yes, the level goes up and the materials are spent once.
##   build_cancel   from anywhere; the proposer takes the open vote back.
## Effects that change a stored number (the battery capacity) are applied once by ColonyBuilds.complete(); every other
## effect is read each tick through AreaLevels.effect().

const ColonyBuilds := preload("res://scripts/upgrades/colony_builds.gd")

const ACTIONS: Array[StringName] = [&"upgrade_area", &"build_propose", &"build_vote", &"build_cancel"]


static func register(service: ActionService) -> void:
	for id: StringName in [&"upgrade_area", &"build_propose"]:
		var d := ActionService.Definition.new()
		d.id = id
		d.check = _check_propose
		d.apply = _apply_propose
		d.target_kind = &"station"
		d.params = {"track": {"type": TYPE_STRING}, "choice": {"type": TYPE_STRING, "optional": true}}
		d.important = true
		service.register(d)
	var v := ActionService.Definition.new()
	v.id = &"build_vote"
	v.check = _check_vote
	v.apply = _apply_vote
	v.params = {"yes": {"type": TYPE_BOOL}}
	v.important = true
	service.register(v)
	var c := ActionService.Definition.new()
	c.id = &"build_cancel"
	c.check = _check_cancel
	c.apply = _apply_cancel
	c.important = true
	service.register(c)


static func _fail(ctx: ActionService.Context, reason: StringName, text: String) -> ActionResult:
	return ActionResult.failure(ctx.request.request_id, reason, text)


static func _choice(ctx: ActionService.Context) -> String:
	return String(ctx.request.params.get("choice", ""))


static func _check_propose(ctx: ActionService.Context) -> ActionResult:
	var id := String(ctx.request.params.track)
	if AreaLevels.track(id).is_empty():
		return _fail(ctx, &"unknown_target", "That upgrade path does not exist.")
	if not AreaLevels.core_serves(id, String(ctx.request.target), ctx.target):
		return _fail(ctx, &"wrong_target", "Choose %s upgrades at %s." % [AreaLevels.track_name(id).to_lower(), AreaLevels.spot_words(id)])
	var lacking := ColonyBuilds.blockers(ctx.state, id)
	if not lacking.is_empty():
		var first: Dictionary = lacking[0]
		var reason: StringName = &"missing_prerequisite"
		match String(first.kind):
			"parts", "ores": reason = &"insufficient"
			"max", "done_today": reason = &"already_done"
			"not_plan", "vote_open", "tutorial": reason = &"not_now"
		return _fail(ctx, reason, String(first.text))
	var p := ColonyBuilds.proposal(ctx.state)
	if not p.is_empty():
		return _fail(ctx, &"not_now", "A vote on %s is already open. Vote on it first." % ColonyBuilds.proposal_words(p))
	var problem := ColonyBuilds.choice_problem(ctx.state, id, _choice(ctx))
	if problem != "":
		return _fail(ctx, &"bad_request", problem)
	return null


static func _apply_propose(ctx: ActionService.Context) -> Dictionary:
	var id := String(ctx.request.params.track)
	var changes := ColonyBuilds.propose(ctx.session, ctx.state, ctx.actor, id, _choice(ctx), String(ctx.request.target))
	changes["target"] = String(ctx.request.target)
	return changes


static func _check_vote(ctx: ActionService.Context) -> ActionResult:
	var p := ColonyBuilds.proposal(ctx.state)
	if p.is_empty():
		return _fail(ctx, &"not_now", "There is no vote open right now.")
	if not ColonyBuilds.in_comms_reach(ctx.state, ctx.actor):
		return _fail(ctx, &"out_of_range", ColonyBuilds.MISSED_TEXT)
	if (p.get("votes", {}) as Dictionary).has(String(ctx.actor.id)):
		return _fail(ctx, &"already_done", "You already voted on %s." % ColonyBuilds.proposal_words(p))
	return null


static func _apply_vote(ctx: ActionService.Context) -> Dictionary:
	return ColonyBuilds.vote(ctx.session, ctx.state, ctx.actor, bool(ctx.request.params.yes))


static func _check_cancel(ctx: ActionService.Context) -> ActionResult:
	var p := ColonyBuilds.proposal(ctx.state)
	if p.is_empty():
		return _fail(ctx, &"not_now", "There is no vote open right now.")
	if String(p.get("by", "")) != String(ctx.actor.id):
		return _fail(ctx, &"not_owner", "Only %s can take this vote back." % String(p.get("by_name", "the crewmate who asked")))
	return null


static func _apply_cancel(ctx: ActionService.Context) -> Dictionary:
	return ColonyBuilds.cancel(ctx.session, ctx.state, ctx.actor)
