class_name RoverActions
extends RefCounted
## The shared rover's host actions (Prompt 10, part 1). Each is validated by ActionService like every other action;
## the effect is written in plain words in the result ("text").
##
##   rover_assemble     at the garage (field engineering and geology specialist ⛏): the first build, at any levels the
##                      colony can pay for, after the assembly check. params (RoverModel.build_params): "speed",
##                      "torque", "range", "cargo", "traction" (ints 1..5), "seq", "variant" (ints) and "answers" (text).
##   rover_refit        the same for a built rover in the garage. Cost = invested(new) - invested(old); a negative cost
##                      gives the parts back to state.parts. The battery keeps its energy (clamped to a smaller
##                      battery, never filled). Refused while cargo would not fit or anyone is seated.
##   rover_enter        anyone near the rover: params {"seat": 0..3} (0 drives). A free seat only; suit on outside.
##   rover_exit         a seated character gets out at exit point params {"exit_index": int} (data/rover.json); the
##                      client picks a clear one, the host checks the index and puts the character there.
##   rover_load_cargo   anyone near the rover: a carried item (target) goes into the cargo bay, within its capacity.
##   rover_unload_cargo anyone near the rover: an item of the cargo bay (target) goes into the actor's pack.
##   rover_set_charging anyone at the charger, rover parked within its cable reach: params {"on": bool}.
##
## The assembly check: "seq" = rover.refit_seq, "variant" = rover.challenge_variant and "answers" =
##   RoverModel.encode_answers({stat: {"module": index, "port": port id, "check": index}}) for the steps of
##   RoverModel.challenge(state, levels). (The params are flat because ActionRequest.shape_problem allows at most 8
##   plain params - bool, int, float, text up to 64 letters - and no dictionaries.) The seq makes every assembly or
##   refit a one-time transaction: a repeated, replayed or reloaded request names an old seq and changes nothing. A
##   wrong answer is not a failure: it gives feedback, moves challenge_variant on (a new example) and costs nothing.

const FIELD_SPECIALTY := &"field_engineering_geology"
## Practical evidence recorded by the first successful assembly or refit (ProgressEvidence, sector resources).
const EVIDENCE := &"res_rover_assembly"
## Ledger entry: parts put into the rover, minus parts given back by refits.
const LEDGER_PARTS := "rover_parts_net"

const ACTIONS: Array[StringName] = [&"rover_assemble", &"rover_refit", &"rover_enter", &"rover_exit", &"rover_load_cargo",
	&"rover_unload_cargo", &"rover_set_charging"]


static func register(service: ActionService) -> void:
	for id: StringName in ACTIONS:
		var d := ActionService.Definition.new()
		d.id = id
		d.check = _check
		d.apply = _apply
		match id:
			&"rover_assemble", &"rover_refit":
				d.target_kind = &"station"
				d.station_kinds = PackedStringArray([RoverSystem.GARAGE_KIND])
				d.specialty = FIELD_SPECIALTY
				d.params = {"seq": {"type": TYPE_INT, "min": 0}, "variant": {"type": TYPE_INT, "min": 0}, "answers": {"type": TYPE_STRING}}
				for s: String in RoverModel.STATS:
					d.params[s] = {"type": TYPE_INT, "min": 1, "max": RoverModel.MAX_LEVEL}
				d.important = true
			&"rover_enter":
				d.params = {"seat": {"type": TYPE_INT, "min": 0, "max": RoverModel.SEATS - 1}}
			&"rover_exit":
				d.params = {"exit_index": {"type": TYPE_INT, "min": 0, "max": 63}}
			&"rover_load_cargo", &"rover_unload_cargo":
				d.target_kind = &"item"
				d.important = true
			&"rover_set_charging":
				d.target_kind = &"station"
				d.station_kinds = PackedStringArray([RoverSystem.CHARGER_KIND])
				d.params = {"on": {"type": TYPE_BOOL}}
		service.register(d)


# ---------------------------------------------------------------- checks

static func _check(ctx: ActionService.Context) -> ActionResult:
	var st := ctx.state
	var rid := ctx.request.request_id
	var p := ctx.request.params
	RoverModel.ensure(st)
	var r := st.rover
	match ctx.request.action:
		&"rover_assemble", &"rover_refit":
			return _check_build(ctx)
		&"rover_enter":
			if not bool(r.built):
				return ActionResult.failure(rid, &"missing_prerequisite", "There is no rover yet. The field engineering and geology specialist ⛏ assembles it at the garage.")
			if RoverModel.seat_of(st, String(ctx.actor.id)) >= 0:
				return ActionResult.failure(rid, &"missing_prerequisite", "You are already in the rover.")
			if RoverModel.distance_to_rover(st, ctx.actor.position) > RoverBalance.get_current().rover_reach_m:
				return ActionResult.failure(rid, &"too_far", "Walk up to the rover to get in.")
			var seat := int(p.seat)
			if not RoverModel.seat_free(st, seat):
				return ActionResult.failure(rid, &"missing_prerequisite", "That seat is taken. %s" % _free_seats_text(st))
			if _rover_outside(ctx) and not ctx.actor.suit_on:
				if RoverModel.has_cabin(st):
					return ActionResult.failure(rid, &"missing_prerequisite", "Put your suit on first: the rover is outside, and you dock your suit at its suitport to get in.")
				return ActionResult.failure(rid, &"missing_prerequisite", "Put your suit on first: the rover is outside and its cabin has no air.")
		&"rover_exit":
			if RoverModel.seat_of(st, String(ctx.actor.id)) < 0:
				return ActionResult.failure(rid, &"missing_prerequisite", "You are not in the rover.")
			if int(p.exit_index) >= RoverModel.exit_count():
				return ActionResult.failure(rid, &"unknown_target", "The rover has no door there.")
		&"rover_load_cargo":
			var item := String(ctx.request.target)
			if not bool(r.built):
				return ActionResult.failure(rid, &"missing_prerequisite", "There is no rover yet.")
			if not ctx.actor.cargo.has(StringName(item)) or String((st.items.get(item, {}) as Dictionary).get("holder", "")) != String(ctx.actor.id):
				return ActionResult.failure(rid, &"not_held", "Carry the item to the rover first.")
			if not _near_rover(ctx):
				return ActionResult.failure(rid, &"too_far", "Walk up to the rover to load it.")
			var mass := RoverModel.item_mass_kg(st, item)
			var aboard := RoverModel.cargo_mass_kg(st)
			var cap := float(RoverModel.stats(r.levels, 0.0).cargo_capacity_kg)
			if aboard + mass > cap + 1e-6:
				return ActionResult.failure(rid, &"insufficient", "Too heavy: %s kg is aboard and this is %s kg, but the cargo bay holds %s kg. Unload something, or refit a bigger cargo bay." % [
					_n(aboard), _n(mass), _n(cap)])
		&"rover_unload_cargo":
			var item := String(ctx.request.target)
			if not (r.cargo as Array).has(item):
				return ActionResult.failure(rid, &"unknown_target", "That is not in the rover's cargo bay.")
			if not _near_rover(ctx):
				return ActionResult.failure(rid, &"too_far", "Walk up to the rover to unload it.")
			if ctx.actor.cargo.size() >= ctx.balance.cargo_slots:
				return ActionResult.failure(rid, &"cargo_full")
		&"rover_set_charging":
			var on := bool(p.on)
			if not bool(r.built):
				return ActionResult.failure(rid, &"missing_prerequisite", "There is no rover to charge yet.")
			if on and not RoverSystem.in_charge_reach(st):
				return ActionResult.failure(rid, &"too_far", "Park the rover in the garage, next to the charger (within %s m), to plug it in." % _n(RoverBalance.get_current().charge_radius_m))
			if on == bool(r.charging):
				return ActionResult.failure(rid, &"missing_prerequisite", "Charging is already on." if on else "Charging is already off.")
	return null


static func _check_build(ctx: ActionService.Context) -> ActionResult:
	var st := ctx.state
	var rid := ctx.request.request_id
	var r := st.rover
	var first := ctx.request.action == &"rover_assemble"
	if first and bool(r.built):
		return ActionResult.failure(rid, &"missing_prerequisite", "The rover is already built. Use Refit to change it.")
	if not first and not bool(r.built):
		return ActionResult.failure(rid, &"missing_prerequisite", "Assemble the rover first.")
	var old := RoverModel.clean_levels(r.levels)
	var want := RoverModel.levels_from_params(ctx.request.params, old)
	if not first and want == old:
		return ActionResult.failure(rid, &"missing_prerequisite", "Nothing to change: the sliders show the rover as it is.")
	if not RoverSystem.in_garage(st):
		return ActionResult.failure(rid, &"missing_prerequisite", "Drive the rover into the garage first.")
	if RoverModel.crew_aboard(st) > 0:
		return ActionResult.failure(rid, &"missing_prerequisite", "Everyone must get out of the rover before it is worked on.")
	var cost := RoverModel.invested(want) - RoverModel.invested(old)
	if cost > st.parts:
		return ActionResult.failure(rid, &"insufficient", "This needs %d spare parts, and the colony has %d. Recover and refurbish salvage, or plan a smaller change." % [cost, st.parts])
	var aboard := RoverModel.cargo_mass_kg(st)
	var new_cap := float(RoverModel.stats(want, 0.0).cargo_capacity_kg)
	if aboard > new_cap + 1e-6:
		return ActionResult.failure(rid, &"insufficient", "Unload the cargo first: %s kg is aboard, but the new cargo bay would hold only %s kg." % [_n(aboard), _n(new_cap)])
	var p := ctx.request.params
	if int(p.seq) != int(r.refit_seq) or int(p.variant) != int(r.challenge_variant):
		return ActionResult.failure(rid, &"missing_prerequisite", "This plan is out of date: the rover was changed or a new example was shown. Look at the garage panel again.")
	var check := RoverModel.check_answers(RoverModel.challenge(st, want), RoverModel.decode_answers(String(p.answers)))
	if bool(check.missing):
		return ActionResult.failure(rid, &"missing_prerequisite", "Answer every step of the assembly check first: the module, the socket and the check.")
	return null


# ---------------------------------------------------------------- effects

static func _apply(ctx: ActionService.Context) -> Dictionary:
	var changes := {"action": String(ctx.request.action), "target": String(ctx.request.target)}
	match ctx.request.action:
		&"rover_assemble", &"rover_refit": _build(ctx, changes)
		&"rover_enter": _enter(ctx, changes)
		&"rover_exit": _exit(ctx, changes)
		&"rover_load_cargo": _load(ctx, changes)
		&"rover_unload_cargo": _unload(ctx, changes)
		&"rover_set_charging": _set_charging(ctx, changes)
	ctx.session.events.system_alert.emit(StringName(String(ctx.request.action)), &"info", String(changes.get("text", "")))
	return changes


static func _build(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	var r := st.rover
	var first := ctx.request.action == &"rover_assemble"
	var old := RoverModel.clean_levels(r.levels)
	var want := RoverModel.levels_from_params(ctx.request.params, old)
	var check := RoverModel.check_answers(RoverModel.challenge(st, want), RoverModel.decode_answers(String(ctx.request.params.answers)))
	changes["levels_from"] = old.duplicate()
	changes["levels_to"] = want.duplicate()
	if not bool(check.ok):
		# no penalty: nothing is spent or changed except the example, which moves on so the retry is a new one
		r["challenge_variant"] = int(r.challenge_variant) + 1
		changes["assembled"] = false
		changes["feedback"] = (check.feedback as Dictionary).duplicate(true)
		var lines := PackedStringArray()
		for s: String in check.feedback:
			lines.append("%s: %s" % [String(RoverModel.STAT_NAMES.get(s, s)), " ".join(PackedStringArray(check.feedback[s]))])
		changes["text"] = "The assembly check found a problem, so nothing was changed and no parts were used. %s A new example is ready: try again." % " ".join(lines)
		return
	var cost := RoverModel.invested(want) - RoverModel.invested(old)
	st.parts -= cost
	st.ledger[LEDGER_PARTS] = float(st.ledger.get(LEDGER_PARTS, 0.0)) + float(cost)
	r["levels"] = want
	r["built"] = true
	var cap := float(RoverModel.stats(want, 0.0).battery_capacity_kwh)
	var before := float(r.battery_kwh)
	var clamped := maxf(0.0, before - cap)
	if clamped > 0.0:
		r["battery_kwh"] = cap
		st.ledger[RoverSystem.LEDGER_CLAMP] = float(st.ledger.get(RoverSystem.LEDGER_CLAMP, 0.0)) + clamped
	r["refit_seq"] = int(r.refit_seq) + 1
	r["challenge_variant"] = 0
	r["last_refit"] = {"by": String(ctx.actor.id), "at_hours": st.sim_hours, "from": old.duplicate(), "to": want.duplicate(), "parts": cost,
		"first": first, "battery_before_kwh": before, "battery_after_kwh": float(r.battery_kwh), "clamped_kwh": clamped}
	var evidence := ProgressEvidence.record(st, ctx.session.events, EVIDENCE, "resources", ctx.actor.id,
		{"from": old.duplicate(), "to": want.duplicate(), "parts": cost, "seq": int(r.refit_seq)})
	changes["assembled"] = true
	changes["parts"] = cost
	changes["parts_now"] = st.parts
	changes["battery_kwh"] = float(r.battery_kwh)
	changes["clamped_kwh"] = clamped
	changes["evidence"] = evidence
	var diffs := PackedStringArray()
	for s: String in RoverModel.STATS:
		if int(old[s]) != int(want[s]):
			diffs.append("%s %d → %d" % [String(RoverModel.STAT_NAMES[s]).to_lower(), int(old[s]), int(want[s])])
	var what := ("The rover is assembled" if first else "Refit done") + (": " + ", ".join(diffs) if not diffs.is_empty() else " with the base equipment")
	var parts_text := "No parts used" if cost == 0 else ("%d spare part%s used" % [cost, "" if cost == 1 else "s"] if cost > 0 else "%d spare part%s given back" % [-cost, "" if cost == -1 else "s"])
	var battery_text := "The battery keeps its %s kWh (it now holds up to %s kWh; a refit never fills it, so charge it at the charger)." % [_n(float(r.battery_kwh)), _n(cap)]
	if clamped > 0.0:
		battery_text = "The smaller battery holds only %s kWh, so %s kWh left with the removed modules." % [_n(cap), _n(clamped)]
	changes["text"] = "%s. %s (now %d). %s" % [what, parts_text, st.parts, battery_text]


static func _enter(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	var seat := int(ctx.request.params.seat)
	(st.rover.seats as Array)[seat] = String(ctx.actor.id)
	var pos := RoverModel.seat_world_position(st, seat)
	ctx.actor.position = pos
	changes["seat"] = seat
	changes["driver"] = seat == 0
	changes["position"] = [pos.x, pos.y, pos.z]
	var cabin := " The cabin is sealed: you breathe cabin air, not your suit tank, and it shelters you from solar storms." if RoverModel.has_cabin(st) else ""
	changes["cabin_sheltered"] = RoverModel.has_cabin(st)
	if seat == 0:
		var battery := float(st.rover.battery_kwh)
		changes["text"] = "You are in the driver's seat. Battery %s kWh: about %s of driving. Space brakes; E gets out.%s" % [_n(battery), _range_text(RoverModel.range_now_km(st)), cabin]
	else:
		changes["text"] = "You are in passenger seat %d. E gets out.%s" % [seat, cabin]


static func _exit(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	var seat := RoverSystem.free_seat_of(st, String(ctx.actor.id))
	var index := int(ctx.request.params.exit_index)
	var pos := RoverModel.exit_world_position(st, index)
	ctx.actor.position = pos
	if ctx.session.outside_test.is_valid():
		ctx.actor.outside = bool(ctx.session.outside_test.call(pos))
	changes["seat"] = seat
	changes["exit_index"] = index
	changes["position"] = [pos.x, pos.y, pos.z]
	changes["text"] = "You got out of the rover."


static func _load(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	var id := String(ctx.request.target)
	var rec: Dictionary = st.items[id]
	ctx.actor.cargo.erase(StringName(id))
	rec["holder"] = RoverModel.HOLDER
	var p := RoverModel.pose_position(st)
	rec["position"] = [p.x, p.y, p.z]
	(st.rover.cargo as Array).append(id)
	var cap := float(RoverModel.stats(st.rover.levels, 0.0).cargo_capacity_kg)
	changes["item"] = id
	changes["mass_kg"] = RoverModel.item_mass_kg(st, id)
	changes["cargo_kg"] = RoverModel.cargo_mass_kg(st)
	changes["text"] = "Loaded (%s kg). Cargo bay: %s of %s kg. More cargo means more energy per metre: range now about %s." % [
		_n(float(changes.mass_kg)), _n(float(changes.cargo_kg)), _n(cap), _range_text(RoverModel.range_now_km(st))]


static func _unload(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	var id := String(ctx.request.target)
	var rec: Dictionary = st.items[id]
	(st.rover.cargo as Array).erase(id)
	rec["holder"] = String(ctx.actor.id)
	var p := ctx.actor.position
	rec["position"] = [p.x, p.y, p.z]
	ctx.actor.cargo.append(StringName(id))
	changes["item"] = id
	changes["cargo_kg"] = RoverModel.cargo_mass_kg(st)
	changes["text"] = "Unloaded into your pack. Cargo bay: %s kg aboard." % _n(float(changes.cargo_kg))


static func _set_charging(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	var r := st.rover
	var on := bool(ctx.request.params.on)
	r["charging"] = on
	if on:
		r["trip"] = {"distance_m": 0.0, "climb_m": 0.0, "energy_kwh": 0.0}
		var block := RoverSystem.charge_block(st)
		r["charge_status"] = block if block != "" else "charging"
	else:
		r["charge_status"] = "off"
	changes["on"] = on
	changes["status"] = String(r.charge_status)
	if on:
		var b := RoverBalance.get_current()
		var extra := "" if String(r.charge_status) == "charging" else " %s." % String(RoverSystem.STATUS_TEXT.get(String(r.charge_status), ""))
		if RoverModel.has_fuel_cell(st):
			extra += " The fuel cell refills too, using %s kg of the colony's oxygen per kWh." % _n(b.fuel_cell_o2_kg_per_kwh)
		changes["text"] = "Rover plugged in. The charger takes %s kW from the colony battery while it charges.%s" % [_n(b.charger_kw), extra]
	else:
		changes["text"] = "Rover unplugged. Battery: %s kWh." % _n(float(r.battery_kwh))


# ---------------------------------------------------------------- helpers

static func _near_rover(ctx: ActionService.Context) -> bool:
	if RoverModel.seat_of(ctx.state, String(ctx.actor.id)) >= 0:
		return true
	return RoverModel.distance_to_rover(ctx.state, ctx.actor.position) <= RoverBalance.get_current().rover_reach_m


static func _rover_outside(ctx: ActionService.Context) -> bool:
	if not ctx.session.outside_test.is_valid():
		return false
	return bool(ctx.session.outside_test.call(RoverModel.pose_position(ctx.state)))


static func _free_seats_text(st: ColonyState) -> String:
	var free := PackedStringArray()
	for i in RoverModel.SEATS:
		if RoverModel.seat_free(st, i):
			free.append("driver's seat" if i == 0 else "seat %d" % i)
	return "Free: %s." % ", ".join(free) if not free.is_empty() else "All four seats are taken."


## "about 850 m" / "about 1.2 km" for a range in km.
static func _range_text(km: float) -> String:
	if km < 1.0:
		return "%d m" % (roundi(km * 100.0) * 10)
	return "%s km" % _n(snappedf(km, 0.1))


static func _n(v: float) -> String:
	return RoverModel._n(v)
