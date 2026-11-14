class_name BuiltinActions
extends RefCounted
## The initial host-authoritative actions.

## Registers the shared action contract.
static func register(service: ActionService) -> void:
	for id: StringName in [&"claim_character", &"release_character", &"vote_pause", &"set_sol_minutes", &"set_zone_power", &"pick_up", &"drop", &"collect_cache", &"begin_suit_check"]:
		var d := ActionService.Definition.new()
		d.id = id
		d.check = _check
		d.apply = _apply
		match id:
			&"claim_character":
				d.needs_actor = false
				d.target_kind = &"character"
				d.important = true
			&"release_character": d.important = true
			&"vote_pause":
				d.needs_actor = false
				d.allowed_while_paused = true
				d.params = {"paused": {"type": TYPE_BOOL}}
			&"set_sol_minutes":
				d.needs_actor = false
				d.host_only = true
				d.allowed_while_paused = true
				d.important = true
				d.params = {"minutes": {"type": TYPE_FLOAT, "min": 5.0, "max": 120.0}}
			&"set_zone_power":
				d.target_kind = &"station"
				d.station_kinds = PackedStringArray(["power"])
				d.params = {"zone": {"type": TYPE_STRING}, "on": {"type": TYPE_BOOL}}
			&"pick_up": d.target_kind = &"item"
			&"drop":
				d.target_kind = &"item"
				d.check_distance = false
			&"collect_cache":
				d.target_kind = &"cache"
				d.important = true
			&"begin_suit_check":
				d.target_kind = &"station"
				d.station_kinds = PackedStringArray(["suits"])
				d.params = {"on": {"type": TYPE_BOOL}}
		service.register(d)

static func _check(ctx: ActionService.Context) -> ActionResult:
	var reason: StringName = &""
	match ctx.request.action:
		&"claim_character":
			var old := ctx.state.character_of_peer(ctx.request.peer_id)
			if ctx.target_character.owner_peer == ctx.request.peer_id:
				reason = &"already_yours"
			elif ctx.target_character.owner_peer != 0:
				reason = &"character_taken"
			elif old != null:
				if ctx.session.peers.size() >= 4:
					reason = &"switch_disabled"
				elif not ctx.session.is_at_hub(old.position):
					reason = &"not_at_hub"
		&"set_zone_power":
			if not ctx.state.zones.has(ctx.request.params.zone):
				reason = &"unknown_target"
		&"pick_up":
			if String(ctx.target.holder) != "":
				reason = &"already_held"
			elif ctx.actor.cargo.size() >= ctx.balance.cargo_slots:
				reason = &"cargo_full"
		&"drop":
			if not ctx.actor.cargo.has(ctx.request.target):
				reason = &"not_held"
		&"collect_cache":
			if ctx.actor.cargo.size() >= ctx.balance.cargo_slots:
				reason = &"cargo_full"
		&"begin_suit_check":
			if ctx.actor.suit_on == bool(ctx.request.params.on) or ctx.session.suit_check_progress(ctx.actor.id) >= 0.0:
				reason = &"missing_prerequisite"
			elif bool(ctx.request.params.on) and ctx.session.available_suit_slot(ctx.request.target) < 0:
				reason = &"missing_prerequisite"
	return null if reason == &"" else ActionResult.failure(ctx.request.request_id, reason)

static func _apply(ctx: ActionService.Context) -> Dictionary:
	match ctx.request.action:
		&"claim_character":
			var old := ctx.state.character_of_peer(ctx.request.peer_id)
			if old != null:
				ctx.session._release(old)
			ctx.target_character.owner_peer = ctx.request.peer_id
			ctx.session.events.crew_ownership_changed.emit(ctx.target_character.id, ctx.request.peer_id)
		&"release_character": ctx.session._release(ctx.actor)
		&"vote_pause": ctx.session.set_pause_vote(ctx.request.peer_id, bool(ctx.request.params.paused))
		&"set_sol_minutes":
			ctx.clock.set_sol_minutes(float(ctx.request.params.minutes), ctx.config)
			ctx.session.events.sol_settings_changed.emit(ctx.clock.sol_minutes)
		&"set_zone_power":
			var zone: String = ctx.request.params.zone
			var on: bool = ctx.request.params.on
			if bool(ctx.state.zones[zone].powered) != on:
				ctx.state.zones[zone].powered = on
				ctx.session.events.zone_power_changed.emit(zone, on)
		&"pick_up":
			ctx.target.holder = String(ctx.actor.id)
			ctx.actor.cargo.append(ctx.request.target)
		&"drop":
			ctx.actor.cargo.erase(ctx.request.target)
			ctx.target.holder = ""
			ctx.target.position = [ctx.actor.position.x, ctx.actor.position.y, ctx.actor.position.z]
		&"collect_cache":
			var items: Array = ctx.target.items
			while not items.is_empty() and ctx.actor.cargo.size() < ctx.balance.cargo_slots:
				var id := StringName(items.pop_front())
				ctx.state.items[id].holder = String(ctx.actor.id)
				ctx.actor.cargo.append(id)
			if items.is_empty():
				ctx.state.caches.erase(ctx.target)
		&"begin_suit_check": ctx.session._start_suit_check(ctx.actor, ctx.request.target, bool(ctx.request.params.on))
	return {"action": String(ctx.request.action), "target": String(ctx.request.target)}
