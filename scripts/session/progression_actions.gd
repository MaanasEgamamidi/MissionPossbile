class_name ProgressionActions
extends RefCounted
## Host actions of the upgrade, knowledge and learning system (Prompt 08, part G). Each is validated by ActionService
## like every other action and answers in plain words ("text").
##   answer_question  at the colony computer or an install station of the question's sector (a question that records
##                    evidence at a station kind, only there); params question_id, choice 0..2. Right: knowledge is
##                    recorded once. Wrong: the explanation and a changed version next time; never any health loss.
##   install_upgrade  at the card's install station, by the card's installer specialty; params upgrade_id. Checks the
##                    sector tier, the questions, the evidence and the parts; consumes the parts exactly once. Asking
##                    again for an installed card changes nothing.
##   exercise         at the gym spot (station kind "gym"): uses body energy now, raises conditioning. Never touches
##                    the battery.

const ACTIONS: Array[StringName] = [&"answer_question", &"install_upgrade", &"exercise"]


static func register(service: ActionService) -> void:
	for id: StringName in ACTIONS:
		var d := ActionService.Definition.new()
		d.id = id
		d.check = _check
		d.apply = _apply
		d.target_kind = &"station"
		match id:
			&"answer_question":
				d.params = {"question_id": {"type": TYPE_STRING}, "choice": {"type": TYPE_INT, "min": 0, "max": 2}}
				d.important = true
			&"install_upgrade":
				d.params = {"upgrade_id": {"type": TYPE_STRING}}
				d.important = true
			&"exercise":
				d.station_kinds = PackedStringArray(["gym"])
		service.register(d)


static func _check(ctx: ActionService.Context) -> ActionResult:
	match ctx.request.action:
		&"answer_question":
			return _check_answer(ctx)
		&"install_upgrade":
			return _check_install(ctx)
		&"exercise":
			var pb := ProgressionBalance.shared()
			if ctx.actor.stamina < pb.exercise_stamina_cost:
				return _fail(ctx, &"insufficient", "Too tired to exercise: body energy is %d %%. Rest first." % roundi(ctx.actor.stamina))
	return null


static func _apply(ctx: ActionService.Context) -> Dictionary:
	var changes := {"action": String(ctx.request.action), "target": String(ctx.request.target)}
	match ctx.request.action:
		&"answer_question":
			_apply_answer(ctx, changes)
		&"install_upgrade":
			_apply_install(ctx, changes)
		&"exercise":
			_apply_exercise(ctx, changes)
	return changes


static func _fail(ctx: ActionService.Context, reason: StringName, text: String) -> ActionResult:
	return ActionResult.failure(ctx.request.request_id, reason, text)


# ---------------------------------------------------------------- answer_question

static func _check_answer(ctx: ActionService.Context) -> ActionResult:
	var qid := StringName(String(ctx.request.params.question_id))
	var q := ProgressionSystem.question(qid)
	if q.is_empty():
		return _fail(ctx, &"unknown_target", "That question is not in the colony's list.")
	if not ProgressionSystem.answer_station_ok(ctx.state, q, ctx.request.target):
		return _fail(ctx, &"wrong_target", "Answer this at %s." % ProgressionSystem.answer_place_words(q))
	var guided := String(q.get("changed_from", ""))
	if guided != "" and not ProgressionSystem.is_known(ctx.state, StringName(guided)):
		return _fail(ctx, &"missing_prerequisite", "First answer the guided question: %s." % ProgressionSystem.question_title(StringName(guided)))
	return null


static func _apply_answer(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	var qid := StringName(String(ctx.request.params.question_id))
	var q := ProgressionSystem.question(qid)
	var sector := String(q.get("sector", ""))
	changes["question_id"] = String(qid)
	if ProgressionSystem.is_known(st, qid):
		changes["already_known"] = true
		changes["correct"] = true
		changes["text"] = "The colony already knows this. Answering again adds nothing."
		return
	var index := ProgressionSystem.current_variant_index(st, qid)
	var variant: Dictionary = (q.variants as Array)[index]
	var choice := int(ctx.request.params.choice)
	var correct := choice == int(variant.get("correct", -1))
	var quiz: Dictionary = ProgressionSystem.progress_of(st)["quiz"]
	var rec: Dictionary = quiz.get(String(qid), {"variant": index, "tries": 0, "wrong": 0})
	rec["tries"] = int(rec.get("tries", 0)) + 1
	changes["already_known"] = false
	changes["correct"] = correct
	changes["variant"] = index
	changes["explanation"] = String(variant.get("explanation", ""))
	if correct:
		st.knowledge[String(qid)] = {"by": String(ctx.actor.id), "sector": sector, "at_hours": st.sim_hours, "variant": index,
			"example": String(variant.get("example", ""))}
		rec["variant"] = index
		quiz[String(qid)] = rec
		var text := "✓ Right! %s" % String(variant.get("explanation", ""))
		var ev := StringName(String(q.get("records_evidence", "")))
		if ev != &"":
			if ProgressEvidence.record(st, ctx.session.events, ev, sector, ctx.actor.id, {"question_id": String(qid), "station": String(ctx.request.target)}):
				changes["evidence"] = String(ev)
		ctx.session.events.upgrade_eligibility_changed.emit(qid)
		var raised := ProgressionSystem.update_tiers(st, ctx.session.events)
		if raised.has(sector):
			text += " %s level %d reached." % [ProgressionSystem.sector_name(sector), ProgressionSystem.tier(st, sector)]
		changes["text"] = text
	else:
		rec["wrong"] = int(rec.get("wrong", 0)) + 1
		rec["variant"] = index + 1
		quiz[String(qid)] = rec
		var next := ProgressionSystem.current_variant_index(st, qid)
		changes["next_variant"] = next
		changes["text"] = "✖ Not quite. %s Try the new version of the question." % String(variant.get("explanation", ""))
	changes["tier"] = ProgressionSystem.tier(st, sector)


# ---------------------------------------------------------------- install_upgrade

static func _check_install(ctx: ActionService.Context) -> ActionResult:
	var c := ProgressionSystem.card(StringName(String(ctx.request.params.upgrade_id)))
	if c == null:
		return _fail(ctx, &"unknown_target", "That upgrade is not in the catalogue.")
	if ProgressionSystem.is_installed(ctx.state, c.id):
		return null                        # idempotent: _apply says so and changes nothing
	if not ProgressionSystem.at_install_station(ctx.state, c, ctx.request.target):
		return _fail(ctx, &"wrong_target", "Install %s at the %s." % [c.title, ProgressionSystem.install_place_words(c)])
	if c.specialty != &"" and ctx.actor.specialty != c.specialty:
		return _fail(ctx, &"wrong_specialty", "%s is installed by the %s." % [c.title, ProgressionSystem.installer_words(c)])
	var lacking := ProgressionSystem.missing(ctx.state, c)
	if not lacking.is_empty():
		var first: Dictionary = lacking[0]
		var reason: StringName = &"insufficient" if String(first.kind) == "parts" else &"missing_prerequisite"
		return _fail(ctx, reason, "Locked: %s." % String(first.text))
	return null


static func _apply_install(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	var c := ProgressionSystem.card(StringName(String(ctx.request.params.upgrade_id)))
	changes["upgrade_id"] = String(c.id)
	if ProgressionSystem.is_installed(st, c.id):
		changes["already_installed"] = true
		changes["parts_used"] = 0
		changes["text"] = "%s is already installed. Nothing changed." % c.title
		return
	st.parts -= c.cost_parts
	st.ledger["parts_used_upgrades"] = float(st.ledger.get("parts_used_upgrades", 0.0)) + float(c.cost_parts)
	var record := {"installed": true, "by": String(ctx.actor.id), "at_hours": st.sim_hours, "parts": c.cost_parts,
		"station": String(ctx.request.target), "sector": c.sector}
	# Effects that change a stored number happen once, here; the rest are read every tick by the models.
	if c.id == &"energy_battery_reserve":
		var cap := float(st.capacities.get(&"battery_kwh", 0.0))
		var new_cap := cap * ProgressionBalance.shared().battery_capacity_factor
		st.capacities[&"battery_kwh"] = new_cap
		record["battery_capacity_before_kwh"] = cap
		record["battery_capacity_after_kwh"] = new_cap
	st.upgrades[String(c.id)] = record
	changes["already_installed"] = false
	changes["parts_used"] = c.cost_parts
	var text := "%s installed. %s" % [c.title, c.effect]
	changes["text"] = text
	ctx.session.events.upgrade_eligibility_changed.emit(c.id)
	ctx.session.events.system_alert.emit(StringName("upgrade_" + String(c.id)), &"info", text)


# ---------------------------------------------------------------- exercise

static func _apply_exercise(ctx: ActionService.Context, changes: Dictionary) -> void:
	var pb := ProgressionBalance.shared()
	var actor := ctx.actor
	actor.stamina = maxf(0.0, actor.stamina - pb.exercise_stamina_cost)
	var table: Dictionary = ProgressionSystem.progress_of(ctx.state)["conditioning"]
	var before := float(table.get(String(actor.id), 0.0))
	var after := minf(pb.conditioning_max, before + pb.exercise_conditioning_gain)
	table[String(actor.id)] = after
	changes["stamina"] = actor.stamina
	changes["conditioning"] = after
	var text := "Good workout! Body energy is now %d %%. Fitness is %d %%, so body energy comes back a little faster. This is body energy, not colony electricity: the battery did not change." % [roundi(actor.stamina), roundi(after * 100.0)]
	if after <= before:
		text = "Good workout! Body energy is now %d %%. Fitness is already at its best (%d %%)." % [roundi(actor.stamina), roundi(after * 100.0)]
	changes["text"] = text
	ctx.session.events.system_alert.emit(&"exercise", &"info", text)
