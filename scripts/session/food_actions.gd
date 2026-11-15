class_name FoodActions
extends RefCounted
## Greenhouse actions (Prompt 08, food part). Anyone may do them: the biology and food specialist is the expert
## (the panels show the ❀ symbol), but the greenhouse stays usable by every crew member.
## Each is validated by ActionService like every other action; the effect is described in plain words in the result
## ("text") and announced through events.system_alert.
##
##   plant (bed, crop)                 a new crop in an empty or wilted bed, with fresh growing mix
##   inspect_bed (bed)                 records a measurement; a bed with a symptom records food_compare_symptom
##                                     and starts a diagnosis ("trial")
##   adjust_nutrients (bed, level)     sets the nutrient level 0..1
##   set_bed_water (bed, on)           opens (and flushes) or closes the bed's drip line
##   set_grow_lights (food, on)        the grow lights: the Greenhouse lighting circuit
##   set_greenhouse_water (food, L/h)  shortcut to the greenhouse water allocation (the life-support console has it too)
##   harvest (bed)                     ready crops only: adds meals to food_meals once and clears the bed (meals x the
##                                     greenhouse racks' yield factor: CropSystem.harvest_meals)
##   apply_nutrient_result (food, id)  needs sci_evidence_settings: applies a lab nutrient setting to every bed
##
## Diagnosis: inspecting a bed with a symptom starts a trial. Changing exactly one input of that bed (water,
## nutrients or light) records food_adjust_one_cause; if the bed's growth rate then rises, CropSystem records
## food_observe_response. Changing a second input makes the trial "mixed" (you cannot tell which change helped).

const SPECIALIST := &"biology_food"
## What each input is called in words.
const INPUT_WORDS := {"water": "water", "nutrients": "nutrients", "light": "light"}


static func register(service: ActionService) -> void:
	for id: StringName in [&"plant", &"inspect_bed", &"adjust_nutrients", &"set_bed_water", &"set_grow_lights",
			&"set_greenhouse_water", &"harvest", &"apply_nutrient_result"]:
		var d := ActionService.Definition.new()
		d.id = id
		d.check = _check
		d.apply = _apply
		d.target_kind = &"station"
		d.station_kinds = PackedStringArray(["bed"])
		match id:
			&"plant":
				d.params = {"crop": {"type": TYPE_STRING}}
				d.important = true
			&"adjust_nutrients":
				d.params = {"level": {"type": TYPE_FLOAT, "min": 0.0, "max": 1.0}}
			&"set_bed_water":
				d.params = {"on": {"type": TYPE_BOOL}}
			&"set_grow_lights":
				d.station_kinds = PackedStringArray(["food"])
				d.params = {"on": {"type": TYPE_BOOL}}
			&"set_greenhouse_water":
				d.station_kinds = PackedStringArray(["food"])
				d.params = {"greenhouse_l_per_hour": {"type": TYPE_FLOAT, "min": 0.0, "max": 20.0}}
			&"harvest":
				d.important = true
			&"apply_nutrient_result":
				d.station_kinds = PackedStringArray(["food"])
				d.params = {"result_id": {"type": TYPE_STRING}}
				d.important = true
		service.register(d)


static func _check(ctx: ActionService.Context) -> ActionResult:
	var reason: StringName = &""
	var message := ""
	var id := String(ctx.request.target)
	var b := CropSystem.bed(ctx.state, id)
	match ctx.request.action:
		&"plant":
			if FoodBalance.crop(String(ctx.request.params.crop)).is_empty():
				reason = &"unknown_target"
				message = "Nobody has seeds for that. Choose lettuce or tomato."
			elif CropSystem.is_alive(b):
				reason = &"missing_prerequisite"
				message = "Something is already growing here. Harvest it first."
		&"harvest":
			if String(b.get("stage", "empty")) != "ready":
				reason = &"missing_prerequisite"
				message = "Nothing is ready to harvest here." if String(b.get("crop", "")) == "" else "The %s is not ready to harvest yet." % _crop_word(b)
		&"adjust_nutrients":
			if not CropSystem.is_alive(b):
				reason = &"missing_prerequisite"
				message = "Plant something first: an empty bed does not need nutrients."
		&"apply_nutrient_result":
			var rid := String(ctx.request.params.result_id)
			var results: Dictionary = ctx.state.science.get("results", {}) if ctx.state.science.get("results", null) is Dictionary else {}
			var r: Dictionary = results.get(rid, {}) if results.get(rid, null) is Dictionary else {}
			if not ctx.state.has_upgrade("sci_evidence_settings"):
				reason = &"missing_prerequisite"
				message = "Lab results can only be applied directly after the evidence-based settings upgrade."
			elif r.is_empty() or String(r.get("kind", "")) != "nutrient_setting":
				reason = &"unknown_target"
				message = "There is no nutrient setting from the lab with that name."
			elif (ctx.state.crops.get("applied_results", []) as Array).has(rid) or bool(r.get("applied", false)):
				reason = &"missing_prerequisite"
				message = "This lab result is already applied to the beds."
			else:
				var v := float(r.get("value", -1.0))
				if is_nan(v) or v < 0.0 or v > 1.0:
					reason = &"bad_request"
	if reason == &"":
		return null
	return ActionResult.failure(ctx.request.request_id, reason, message)


static func _apply(ctx: ActionService.Context) -> Dictionary:
	var crops := CropSystem.ensure(ctx.state)
	var fb := FoodBalance.shared()
	var id := String(ctx.request.target)
	var changes := {"action": String(ctx.request.action), "target": id}
	var text := ""
	var name := CropSystem.bed_name(ctx.state, id)
	var b: Dictionary = (crops.beds as Dictionary).get(id, {})
	match ctx.request.action:
		&"plant":
			var crop_id := String(ctx.request.params.crop)
			var fresh := CropSystem.new_bed()
			fresh["water_l"] = float(b.get("water_l", fresh.water_l))
			fresh["valve"] = bool(b.get("valve", true))
			fresh["flow"] = float(b.get("flow", 1.0))
			fresh["crop"] = crop_id
			fresh["stage"] = CropSystem.stage_for(crop_id, 0.0)
			fresh["nutrients"] = fb.nutrients_at_planting
			fresh["planted_at"] = ctx.state.sim_hours
			crops.beds[id] = fresh
			var c := FoodBalance.crop(crop_id)
			text = "%s: %s planted with fresh growing mix. At full speed it is ready in about %s sols here (%s)." % [
				name, String(c.get("name", crop_id)), _num(float(c.get("cycle_sols", 0.0))), String(c.get("earth_words", "much longer on Earth"))]
			changes["crop"] = crop_id
		&"inspect_bed":
			var symptoms := CropSystem.symptoms_of(ctx.state, b, fb)
			var m := {"at_hours": ctx.state.sim_hours, "by": String(ctx.actor.id), "water_l": float(b.get("water_l", 0.0)),
				"water_share": float(b.get("water_l", 0.0)) / maxf(fb.bed_water_capacity_l, 1e-9), "nutrients": float(b.get("nutrients", 0.0)),
				"light": 1.0 if CropSystem.lights_working(ctx.state, fb) else 0.0, "rate": float(b.get("rate", 0.0)),
				"flow": float(b.get("flow", 1.0)), "symptoms": symptoms.duplicate()}
			b["inspection"] = m
			changes["measurement"] = m.duplicate(true)
			if symptoms.is_empty():
				text = "%s: %s" % [name, _healthy_words(ctx.state, b)]
			else:
				var lines := PackedStringArray()
				for s: String in symptoms:
					lines.append(CropSystem.symptom_sentence(ctx.state, b, s))
				text = "%s: %s Change one thing at a time, then watch the growth rate." % [name, " ".join(lines)]
				if CropSystem.is_growing(b):
					b["trial"] = {"status": "open", "by": String(ctx.actor.id), "symptoms": symptoms.duplicate(), "rate_before": float(b.get("rate", 0.0)),
						"at_hours": ctx.state.sim_hours, "changed": []}
				ProgressEvidence.record(ctx.state, ctx.session.events, &"food_compare_symptom", "food", ctx.actor.id,
					{"bed": id, "symptoms": symptoms.duplicate(), "measurement": text})
			changes["symptoms"] = symptoms
		&"adjust_nutrients":
			var level := float(ctx.request.params.level)
			var before := float(b.get("nutrients", 0.0))
			b["nutrients"] = level
			text = "%s: nutrients set to %d %% (were %d %%). The good band is %d to %d %%." % [name, roundi(level * 100.0), roundi(before * 100.0),
				roundi(fb.nutrient_good_low * 100.0), roundi(fb.nutrient_good_high * 100.0)]
			if absf(level - before) > 0.005:
				text += _note_change(ctx, id, "nutrients")
			changes["level"] = level
		&"set_bed_water":
			var on := bool(ctx.request.params.on)
			var was_on := bool(b.get("valve", true))
			var was_flow := float(b.get("flow", 1.0))
			b["valve"] = on
			if on:
				b["flow"] = 1.0
				text = "%s: water on. Its drip line is flushed and clean (100 %% flow). It takes water only from what the greenhouse gets." % name
			else:
				text = "%s: water off. The soil will dry out." % name
			if was_on != on or (on and was_flow < 0.99):
				text += _note_change(ctx, id, "water")
			changes["on"] = on
		&"set_grow_lights":
			var on := bool(ctx.request.params.on)
			var zone := fb.light_zone
			var was := ctx.state.is_zone_powered(zone)
			if ctx.state.zones.has(zone) and was != on:
				(ctx.state.zones[zone] as Dictionary)["powered"] = on
				ctx.session.events.zone_power_changed.emit(zone, on)
			text = "Grow lights %s. They use %s kW while on." % ["on" if on else "off: the plants stop growing", _num(ctx.balance.load_of_zone(zone))]
			if was != on:
				for bed_id: String in CropSystem.bed_ids(ctx.state):
					text += _note_change(ctx, bed_id, "light", true)
			changes["on"] = on
		&"set_greenhouse_water":
			var lph := float(ctx.request.params.greenhouse_l_per_hour)
			var was := float(ctx.state.water_allocation.get("greenhouse_l_per_hour", 0.0))
			ctx.state.water_allocation["greenhouse_l_per_hour"] = lph
			text = "Greenhouse water: %s L per hour. It only takes water above the drinking reserve; drinking water always comes first." % _num(lph)
			if absf(lph - was) > 1e-6:
				for bed_id: String in CropSystem.bed_ids(ctx.state):
					text += _note_change(ctx, bed_id, "water", true)
			changes["water_allocation"] = ctx.state.water_allocation.duplicate()
		&"harvest":
			var c := FoodBalance.crop(String(b.crop))
			# more grow layers in the greenhouse racks = more food per harvest (CropSystem.harvest_meals, food track)
			var meals := CropSystem.harvest_meals(ctx.state, String(b.crop))
			var added := ctx.state.add_to_store(&"food_meals", meals)
			ctx.state.ledger["meals_harvested"] = float(ctx.state.ledger.get("meals_harvested", 0.0)) + added
			var fresh := CropSystem.new_bed()
			fresh["water_l"] = float(b.get("water_l", fresh.water_l))
			fresh["valve"] = bool(b.get("valve", true))
			fresh["flow"] = float(b.get("flow", 1.0))
			crops.beds[id] = fresh
			text = "%s: harvested the %s: %s meals into the food store." % [name, String(c.get("name", "crop")).to_lower(), _num(added)]
			var racks := CropSystem.yield_words(ctx.state)
			if racks != "":
				text += " " + racks
			if added < meals - 1e-9:
				text += " The food store is full, so %s meals did not fit." % _num(meals - added)
			changes["meals"] = added
		&"apply_nutrient_result":
			var rid := String(ctx.request.params.result_id)
			var r: Dictionary = (ctx.state.science.results as Dictionary)[rid]
			var v := float(r.value)
			(crops.applied_results as Array).append(rid)
			crops["nutrient_setting"] = {"result_id": rid, "value": v, "at_hours": ctx.state.sim_hours}
			var olds := {}
			for bed_id: String in CropSystem.bed_ids(ctx.state):
				var bb: Dictionary = (crops.beds as Dictionary).get(bed_id, {})
				olds[bed_id] = float(bb.get("nutrients", 0.0))
			var count := CropSystem.apply_nutrient_setting(ctx.state, "all_beds", v)
			for bed_id: String in olds:
				var bb: Dictionary = (crops.beds as Dictionary).get(bed_id, {})
				if CropSystem.is_alive(bb) and absf(v - float(olds[bed_id])) > 0.005:
					_note_change(ctx, bed_id, "nutrients")
			# Marks the result used in the science record and records sci_apply_result once (one path for both parts).
			ScienceActions.mark_result_applied(ctx.state, ctx.session.events, rid, ctx.actor.id, "all_beds")
			text = "Lab result applied: nutrients set to %d %% in %d growing beds." % [roundi(v * 100.0), count]
			changes["value"] = v
	changes["text"] = text
	ctx.session.events.system_alert.emit(StringName(String(ctx.request.action)), &"info", text)
	return changes


## Counts a changed input in the bed's diagnosis. Exactly one changed input records food_adjust_one_cause.
## Returns a sentence about the diagnosis to add to the answer ("" if there is none). `quiet` leaves out the sentence.
static func _note_change(ctx: ActionService.Context, bed_id: String, input: String, quiet := false) -> String:
	var b := CropSystem.bed(ctx.state, bed_id)
	var t: Dictionary = b.get("trial", {})
	var status := String(t.get("status", ""))
	if status != "open" and status != "one_change":
		return ""
	var changed: Array = t.get("changed", [])
	if not changed.has(input):
		changed.append(input)
	t["changed"] = changed
	if changed.size() == 1:
		if status == "open":
			t["status"] = "one_change"
			t["changed_at"] = ctx.state.sim_hours
			t["by"] = String(ctx.actor.id)
			ProgressEvidence.record(ctx.state, ctx.session.events, &"food_adjust_one_cause", "food", ctx.actor.id,
				{"bed": bed_id, "input": input, "symptoms": (t.get("symptoms", []) as Array).duplicate()})
		return "" if quiet else " Only the %s changed, so watch the growth rate to see if it helped." % String(INPUT_WORDS.get(input, input))
	t["status"] = "mixed"
	return "" if quiet else " More than one thing changed on this bed, so you cannot tell which change helped. Inspect it again to start a new test."


static func _healthy_words(st: ColonyState, b: Dictionary) -> String:
	if String(b.get("crop", "")) == "":
		return "Empty bed. Soil water %d %%." % roundi(100.0 * float(b.get("water_l", 0.0)) / FoodBalance.shared().bed_water_capacity_l)
	if String(b.stage) == "wilted":
		return "The plant has wilted. Plant again."
	return "The %s looks healthy: soil water %d %%, nutrients %d %%, light %s." % [_crop_word(b),
		roundi(100.0 * float(b.water_l) / FoodBalance.shared().bed_water_capacity_l), roundi(float(b.nutrients) * 100.0),
		"on" if CropSystem.lights_working(st) else "off"]


static func _crop_word(b: Dictionary) -> String:
	return String(FoodBalance.crop(String(b.get("crop", ""))).get("name", "plant")).to_lower()


static func _num(value: float, decimals := 1) -> String:
	return CropSystem._num(value, decimals)
