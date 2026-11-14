class_name ScienceActions
extends RefCounted
## Field-sample science and salvage fabrication (Prompt 08, Part S). Host actions, each validated by ActionService
## like every other action; the effect is written in plain words in the result ("text") and announced through
## events.system_alert.
##
## Field sample -> lab comparison (one activity):
##   take_sample      at a sample site (field engineering and geology specialist). Puts a `sample` item in the pack
##                    and stores where, when and in what conditions it was taken (evidence sci_record_context).
##   analyze_sample   at the lab glovebox: measures the carried sample next to a reference and a blank control.
##   interpret_sample at the lab: the player picks one of 3 interpretations. Right: a lab result (a nutrient setting)
##                    and evidence sci_compare_controls. Wrong: feedback and a fresh measurement (retry variant);
##                    nobody is hurt and nothing is lost.
##   apply_result     at a garden bed or the greenhouse console (or at the lab with sci_evidence_settings): uses the
##                    result once for a real colony setting (evidence sci_apply_result).
## Compatible salvage -> usable component (one workflow):
##   inspect_donor    at a damaged object (anyone): shows its parts; choosing the part that fits records
##                    res_identify_compatible.
##   recover_part     at the donor (field engineering and geology specialist): a `salvaged_<part>` item. Each donor
##                    part can be recovered once, ever (saved in state).
##   refurbish        at the workbench: the carried salvaged part goes on the bench (the item is used up).
##   bench_test       at the workbench: when the part is ready, the test passes and adds exactly one spare part
##                    (state.parts, ledger parts_from_salvage) and evidence res_assembly_test.
##
## State (all plain JSON data in state.science):
##   samples[sample_id]   {"site", "site_name", "taken_by", "at_hours", "sol", "phase", "time_text", "conditions", "analysed", "result_id"}
##   site_counts[site_id] samples taken there
##   lab[sample_id]       {"reference", "control", "variant", "attempts", "ran_at_hours", "uncertainty_pct"}
##   results[result_id]   {"kind": "nutrient_setting", "value", "uncertainty", "sample", "site", "rock_type", "reference",
##                         "control", "by", "at_hours", "applied", "applied_to", "applied_by", "applied_at_hours"}
##   nutrient_targets[station id or "all_beds"]  {"value", "result_id"}  (read by the food part; see nutrient_target())
##   donors[donor_id]     {"inspected", "identified": {part: true}, "rejected": {part: true}, "recovered": {part: {"by", "at_hours", "item"}}, "wrong_choices"}
##   bench[job_id]        {"part", "donor", "name", "by", "started_at_hours", "ready_at_hours", "done", "tested"}
##   components[part_id]  how many of that component type were finished (res_repeat_assembly uses it)

const SAMPLES_PATH := "res://data/samples.json"
const SALVAGE_PATH := "res://data/salvage.json"
## The one specialist for the field steps (taking a sample, recovering a donor part).
const FIELD_SPECIALTY := &"field_engineering_geology"
## Item kind of a field sample; salvaged parts are "salvaged_<part id>".
const SAMPLE_KIND := "sample"
const SALVAGED_PREFIX := "salvaged_"
## Ledger entry for working components made from salvage (one per refurbished part).
const LEDGER_PARTS := "parts_from_salvage"

const ACTIONS: Array[StringName] = [&"take_sample", &"analyze_sample", &"interpret_sample", &"apply_result",
	&"inspect_donor", &"recover_part", &"refurbish", &"bench_test"]

static var _samples: Dictionary = {}
static var _salvage: Dictionary = {}


static func register(service: ActionService) -> void:
	for id: StringName in ACTIONS:
		var d := ActionService.Definition.new()
		d.id = id
		d.check = _check
		d.apply = _apply
		d.target_kind = &"station"
		match id:
			&"take_sample":
				d.station_kinds = PackedStringArray(["sample_site"])
				d.specialty = FIELD_SPECIALTY
				d.important = true
			&"analyze_sample":
				d.station_kinds = PackedStringArray(["lab"])
				d.params = {"sample": {"type": TYPE_STRING}, "reference": {"type": TYPE_STRING, "optional": true}}
			&"interpret_sample":
				d.station_kinds = PackedStringArray(["lab"])
				d.params = {"sample": {"type": TYPE_STRING}, "choice": {"type": TYPE_INT, "min": 0, "max": 2}}
				d.important = true
			&"apply_result":
				d.station_kinds = PackedStringArray(["lab", "bed", "food"])
				d.params = {"result_id": {"type": TYPE_STRING}}
				d.important = true
			&"inspect_donor":
				d.station_kinds = PackedStringArray(["salvage"])
				d.params = {"choice": {"type": TYPE_STRING, "optional": true}}
			&"recover_part":
				d.station_kinds = PackedStringArray(["salvage"])
				d.specialty = FIELD_SPECIALTY
				d.params = {"part": {"type": TYPE_STRING}}
				d.important = true
			&"refurbish":
				d.station_kinds = PackedStringArray(["workbench"])
				d.params = {"item": {"type": TYPE_STRING}}
				d.important = true
			&"bench_test":
				d.station_kinds = PackedStringArray(["workbench"])
				d.params = {"job": {"type": TYPE_STRING}}
				d.important = true
		service.register(d)


# ---------------------------------------------------------------- data (read only)

## data/samples.json, read once.
static func samples_data() -> Dictionary:
	if _samples.is_empty():
		_samples = _read_json(SAMPLES_PATH)
	return _samples


## data/salvage.json, read once.
static func salvage_data() -> Dictionary:
	if _salvage.is_empty():
		_salvage = _read_json(SALVAGE_PATH)
	return _salvage


## The data of a sample site station, or {}.
static func site_info(site_id: String) -> Dictionary:
	for s: Dictionary in samples_data().get("sites", []):
		if String(s.get("id", "")) == site_id:
			return s
	return {}


## A reference sample by id, or {}.
static func reference_info(ref_id: String) -> Dictionary:
	for r: Dictionary in samples_data().get("references", []):
		if String(r.get("id", "")) == ref_id:
			return r
	return {}


## Ids of the references the colony can use now. The second one needs the sci_sample_comparison upgrade.
static func references_available(state: ColonyState) -> PackedStringArray:
	var out := PackedStringArray()
	for r: Dictionary in samples_data().get("references", []):
		var need := String(r.get("needs_upgrade", ""))
		if need == "" or state.has_upgrade(need):
			out.append(String(r.id))
	return out


## The id of the first reference (always available).
static func default_reference() -> String:
	var refs: Array = samples_data().get("references", [])
	return String((refs[0] as Dictionary).get("id", "")) if not refs.is_empty() else ""


## The blank control.
static func control_info() -> Dictionary:
	return samples_data().get("control", {})


## The data of a salvage donor station (by map object name), or {}.
static func donor_info(donor_id: String) -> Dictionary:
	for d: Dictionary in salvage_data().get("donors", []):
		if String(d.get("object", "")) == donor_id:
			return d
	return {}


## One part of a donor, or {}.
static func part_info(donor_id: String, part_id: String) -> Dictionary:
	for p: Dictionary in donor_info(donor_id).get("parts", []):
		if String(p.get("id", "")) == part_id:
			return p
	return {}


## The 3 interpretation choices in the order shown for retry variant `variant` (each variant moves them round).
static func interpretation_options(variant: int) -> Array:
	var all: Array = samples_data().get("interpretations", [])
	var out: Array = []
	for i in all.size():
		out.append(all[(i + maxi(variant, 0)) % all.size()])
	return out


## The mineral shares the lab measures for a sample from `site_id`, for retry variant `variant`.
static func sample_readout(site_id: String, variant: int) -> Dictionary:
	var readouts: Array = site_info(site_id).get("readouts", [])
	if readouts.is_empty():
		return {}
	return readouts[maxi(variant, 0) % readouts.size()]


# ---------------------------------------------------------------- state (read only for panels)

## A sub-dictionary of state.science ("samples", "lab", "results", "donors", "bench", ...), or {} if there is none yet.
## Panels use this; it never changes state.
static func read(state: ColonyState, key: String) -> Dictionary:
	var v: Variant = state.science.get(key, {})
	return v if v is Dictionary else {}


## Plus-or-minus on mineral shares in percentage points, with the calibration upgrade applied.
static func mineral_uncertainty(state: ColonyState) -> float:
	var b := ScienceBalance.get_current()
	return b.calibrated_mineral_uncertainty_pct if state.has_upgrade("sci_instrument_calibration") else b.mineral_uncertainty_pct


## Plus-or-minus on the nutrient setting of a new lab result, with the calibration upgrade applied.
static func result_uncertainty(state: ColonyState) -> float:
	var b := ScienceBalance.get_current()
	return b.calibrated_result_uncertainty if state.has_upgrade("sci_instrument_calibration") else b.result_uncertainty


## How many parts one donor may give, with the refurbishment upgrade applied.
static func donor_limit(state: ColonyState) -> int:
	var b := ScienceBalance.get_current()
	return b.parts_per_donor_upgraded if state.has_upgrade("res_component_refurbishment") else b.parts_per_donor


## Game hours a part needs on the workbench, with the refurbishment upgrade applied.
static func refurbish_hours(state: ColonyState) -> float:
	var b := ScienceBalance.get_current()
	return b.refurbish_hours_upgraded if state.has_upgrade("res_component_refurbishment") else b.refurbish_hours


## Parts already recovered from a donor.
static func recovered_count(state: ColonyState, donor_id: String) -> int:
	var rec: Dictionary = read(state, "donors").get(donor_id, {})
	var recovered: Dictionary = rec.get("recovered", {})
	return recovered.size()


## True if `part_id` of `donor_id` is known to fit: chosen by a player, or shown by the salvage inspection upgrade.
static func is_identified(state: ColonyState, donor_id: String, part_id: String) -> bool:
	if not bool(part_info(donor_id, part_id).get("compatible", false)):
		return false
	var rec: Dictionary = read(state, "donors").get(donor_id, {})
	if bool((rec.get("identified", {}) as Dictionary).get(part_id, false)):
		return true
	return state.has_upgrade("res_salvage_inspection") and bool(rec.get("inspected", false))


## True if that donor part has been recovered (by anyone, in this game or before a reload).
static func is_recovered(state: ColonyState, donor_id: String, part_id: String) -> bool:
	return ((read(state, "donors").get(donor_id, {}) as Dictionary).get("recovered", {}) as Dictionary).has(part_id)


## True if a component of this type was finished before (res_repeat_assembly then skips the bench test).
static func assembled_before(state: ColonyState, part_id: String) -> bool:
	return int(read(state, "components").get(part_id, 0)) > 0


## The nutrient setting (0..1) a lab result set for a bed or the greenhouse console, or -1. The food part can read it:
## a value for the station itself wins over one applied to every bed ("all_beds").
static func nutrient_target(state: ColonyState, station_id: String) -> float:
	var targets := read(state, "nutrient_targets")
	if targets.has(station_id):
		return float((targets[station_id] as Dictionary).get("value", -1.0))
	if targets.has("all_beds"):
		return float((targets["all_beds"] as Dictionary).get("value", -1.0))
	return -1.0


## Items of `kind_prefix` an actor carries, in cargo order.
static func carried(state: ColonyState, actor: CharacterState, kind_prefix: String) -> Array[String]:
	var out: Array[String] = []
	if actor == null:
		return out
	for id: StringName in actor.cargo:
		var rec: Dictionary = state.items.get(String(id), state.items.get(id, {}))
		if String(rec.get("kind", "")).begins_with(kind_prefix):
			out.append(String(id))
	return out


## "Sol 2, 07:12 Mars clock (morning)" for a sol number (0-based) and a sol phase.
static func time_text(sol_index: int, phase: float) -> String:
	var minutes := int(floor(clampf(phase, 0.0, 0.99999) * 24.0 * 60.0))
	var part := "night"
	if phase >= 0.25 and phase < 0.4:
		part = "morning"
	elif phase >= 0.4 and phase < 0.6:
		part = "midday"
	elif phase >= 0.6 and phase < 0.75:
		part = "afternoon"
	return "Sol %d, %02d:%02d on the Mars clock (%s)" % [sol_index + 1, minutes / 60, minutes % 60, part]


## Words for the dust in the air.
static func sky_text(tau: float) -> String:
	var b := ScienceBalance.get_current()
	if tau < b.clear_sky_tau:
		return "clear sky"
	if tau <= b.dusty_sky_tau:
		return "hazy sky"
	return "dusty sky"


## Records that a lab result was used for a real colony setting at `where` (a station id or "all_beds"), once.
## apply_result calls it; the food part may call it too when it applies a result itself. Returns true when new.
static func mark_result_applied(state: ColonyState, events: GameEvents, result_id: String, actor: StringName, where: String) -> bool:
	var results := _sub(state, "results")
	if not results.has(result_id):
		return false
	var r: Dictionary = results[result_id]
	if bool(r.get("applied", false)):
		return false
	r["applied"] = true
	r["applied_to"] = where
	r["applied_by"] = String(actor)
	r["applied_at_hours"] = state.sim_hours
	_sub(state, "nutrient_targets")[where] = {"value": float(r.get("value", 0.0)), "result_id": result_id}
	ProgressEvidence.record(state, events, &"sci_apply_result", "science", actor,
		{"result": result_id, "where": where, "kind": String(r.get("kind", "")), "value": float(r.get("value", 0.0))})
	return true


# ---------------------------------------------------------------- checks

static func _check(ctx: ActionService.Context) -> ActionResult:
	var st := ctx.state
	var rid := ctx.request.request_id
	var p := ctx.request.params
	var station := String(ctx.request.target)
	match ctx.request.action:
		&"take_sample":
			if site_info(station).is_empty():
				return ActionResult.failure(rid, &"unknown_target")
			if ctx.actor.cargo.size() >= ctx.balance.cargo_slots:
				return ActionResult.failure(rid, &"cargo_full")
			var taken := int(read(st, "site_counts").get(station, 0))
			if taken >= ScienceBalance.get_current().samples_per_site:
				return ActionResult.failure(rid, &"insufficient", "This site has given all the samples it can (%d). Try another site." % taken)
		&"analyze_sample", &"interpret_sample":
			var sample := String(p.sample)
			if not ctx.actor.cargo.has(StringName(sample)) or not read(st, "samples").has(sample):
				return ActionResult.failure(rid, &"not_held", "Carry the sample to the lab first.")
			if bool((read(st, "samples")[sample] as Dictionary).get("analysed", false)):
				return ActionResult.failure(rid, &"missing_prerequisite", "This sample has already been worked out.")
			if ctx.request.action == &"analyze_sample":
				var ref := String(p.get("reference", default_reference()))
				if reference_info(ref).is_empty():
					return ActionResult.failure(rid, &"unknown_target")
				if not references_available(st).has(ref):
					return ActionResult.failure(rid, &"missing_prerequisite", "The second reference sample needs the sample comparison upgrade.")
			elif not read(st, "lab").has(sample):
				return ActionResult.failure(rid, &"missing_prerequisite", "Run the comparison first: measure the sample next to the reference and the control.")
		&"apply_result":
			var results := read(st, "results")
			var id := String(p.result_id)
			if not results.has(id):
				return ActionResult.failure(rid, &"unknown_target", "There is no lab result with that name.")
			if bool((results[id] as Dictionary).get("applied", false)):
				return ActionResult.failure(rid, &"missing_prerequisite", "This lab result has already been used.")
			if String(ctx.target.get("kind", "")) == "lab" and not st.has_upgrade("sci_evidence_settings"):
				return ActionResult.failure(rid, &"missing_prerequisite",
					"From the lab this needs the evidence-based settings upgrade. Take the result to a garden bed or the greenhouse console.")
		&"inspect_donor":
			if donor_info(station).is_empty():
				return ActionResult.failure(rid, &"unknown_target")
			if p.has("choice") and part_info(station, String(p.choice)).is_empty():
				return ActionResult.failure(rid, &"unknown_target", "That part is not in this donor.")
		&"recover_part":
			var part := String(p.part)
			var info := part_info(station, part)
			if info.is_empty():
				return ActionResult.failure(rid, &"unknown_target", "That part is not in this donor.")
			if is_recovered(st, station, part):
				return ActionResult.failure(rid, &"missing_prerequisite", "That part has already been taken out.")
			if not bool(info.get("compatible", false)):
				return ActionResult.failure(rid, &"wrong_target", "That part does not fit anything in the colony: %s" % String(info.get("clue", "")))
			if not is_identified(st, station, part):
				return ActionResult.failure(rid, &"missing_prerequisite", "Inspect the donor and choose the part that fits first.")
			if recovered_count(st, station) >= donor_limit(st):
				return ActionResult.failure(rid, &"insufficient", "Nothing more can be saved from this donor (%d part%s taken)." % [recovered_count(st, station), "" if recovered_count(st, station) == 1 else "s"])
			if ctx.actor.cargo.size() >= ctx.balance.cargo_slots:
				return ActionResult.failure(rid, &"cargo_full")
		&"refurbish":
			var item := String(p.item)
			if not ctx.actor.cargo.has(StringName(item)) or not st.items.has(item):
				return ActionResult.failure(rid, &"not_held", "Carry the salvaged part to the workbench first.")
			if not String((st.items[item] as Dictionary).get("kind", "")).begins_with(SALVAGED_PREFIX):
				return ActionResult.failure(rid, &"wrong_target", "Only salvaged parts can be refurbished. No machine part is made from rock or soil.")
		&"bench_test":
			var bench := read(st, "bench")
			var job := String(p.job)
			if not bench.has(job):
				return ActionResult.failure(rid, &"unknown_target", "There is no part with that name on the bench.")
			var j: Dictionary = bench[job]
			if bool(j.get("done", false)):
				return ActionResult.failure(rid, &"missing_prerequisite", "That part has already passed its test.")
			var left := float(j.get("ready_at_hours", 0.0)) - st.sim_hours
			if left > 1e-6:
				return ActionResult.failure(rid, &"missing_prerequisite", "Still being refurbished: ready in %s." % hours_text(left))
	return null


## "about 1.5 game hours" / "about 20 game minutes".
static func hours_text(hours: float) -> String:
	if hours >= 1.0:
		return "about %s game hours" % num(hours, 1)
	var minutes := roundi(hours * 60.0)
	return "about %d game minutes" % maxi(minutes, 1)


## A number with at most `decimals` decimals and no trailing zeros ("0.45", "2").
static func num(value: float, decimals := 2) -> String:
	var t := String.num(value, decimals)
	if t.contains("."):
		t = t.rstrip("0").rstrip(".")
	return "0" if t == "-0" else t


# ---------------------------------------------------------------- effects

static func _apply(ctx: ActionService.Context) -> Dictionary:
	var changes := {"action": String(ctx.request.action), "target": String(ctx.request.target)}
	match ctx.request.action:
		&"take_sample": _take_sample(ctx, changes)
		&"analyze_sample": _analyze(ctx, changes)
		&"interpret_sample": _interpret(ctx, changes)
		&"apply_result": _apply_result(ctx, changes)
		&"inspect_donor": _inspect(ctx, changes)
		&"recover_part": _recover(ctx, changes)
		&"refurbish": _refurbish(ctx, changes)
		&"bench_test": _bench_test(ctx, changes)
	ctx.session.events.system_alert.emit(StringName(String(ctx.request.action)), &"info", String(changes.get("text", "")))
	return changes


static func _take_sample(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	var site_id := String(ctx.request.target)
	var site := site_info(site_id)
	var id := _next_id(st, "sample")
	var pos := ctx.actor.position
	var sol := ctx.clock.sol_index if ctx.clock != null else 0
	var phase := ctx.clock.phase if ctx.clock != null else 0.0
	var daylight := ctx.clock.is_daylight() if ctx.clock != null else true
	var conditions := {"dust_tau": st.dust_tau, "sky": sky_text(st.dust_tau), "daylight": daylight}
	var label := {"site": site_id, "site_name": String(site.get("name", site_id)), "ground": String(site.get("ground", "")),
		"position": [pos.x, pos.y, pos.z], "taken_by": String(ctx.actor.id), "at_hours": st.sim_hours, "sol": sol + 1, "phase": phase,
		"time_text": time_text(sol, phase), "conditions": conditions, "analysed": false, "result_id": ""}
	_sub(st, "samples")[id] = label
	var counts := _sub(st, "site_counts")
	counts[site_id] = int(counts.get(site_id, 0)) + 1
	st.items[id] = {"kind": SAMPLE_KIND, "position": [pos.x, pos.y, pos.z], "holder": String(ctx.actor.id), "sample": id, "site": site_id}
	ctx.actor.cargo.append(StringName(id))
	var new_evidence := ProgressEvidence.record(st, ctx.session.events, &"sci_record_context", "science", ctx.actor.id,
		{"sample": id, "site": site_id, "sol": sol + 1, "at_hours": st.sim_hours, "time": label.time_text, "conditions": conditions.duplicate()})
	changes["item"] = id
	changes["sample"] = label.duplicate(true)
	changes["evidence"] = new_evidence
	changes["text"] = "Sample taken at the %s and put in your pack. Its label says: %s, %s, %s, dust in the air %s." % [
		label.site_name, label.time_text, "daylight" if daylight else "night", conditions.sky, num(st.dust_tau, 2)]


static func _analyze(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	var sample := String(ctx.request.params.sample)
	var ref := String(ctx.request.params.get("reference", default_reference()))
	var lab := _sub(st, "lab")
	var rec: Dictionary = lab.get(sample, {"variant": 0, "attempts": 0})
	rec["reference"] = ref
	rec["control"] = String(control_info().get("id", "blank_holder"))
	rec["variant"] = int(rec.get("variant", 0))
	rec["attempts"] = int(rec.get("attempts", 0))
	rec["ran_at_hours"] = st.sim_hours
	rec["uncertainty_pct"] = mineral_uncertainty(st)
	lab[sample] = rec
	var site := String((read(st, "samples")[sample] as Dictionary).get("site", ""))
	changes["sample"] = sample
	changes["reference"] = ref
	changes["control"] = rec.control
	changes["variant"] = rec.variant
	changes["readout"] = sample_readout(site, int(rec.variant)).duplicate()
	changes["options"] = interpretation_options(int(rec.variant)).map(func(o: Dictionary) -> String: return String(o.text))
	changes["text"] = "The lab measured the sample, %s and the empty holder (the control) the same way. Compare them and choose what the sample is." % String(reference_info(ref).get("name", ref)).to_lower()


static func _interpret(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	var sample := String(ctx.request.params.sample)
	var lab: Dictionary = _sub(st, "lab")[sample]
	var variant := int(lab.get("variant", 0))
	var label: Dictionary = _sub(st, "samples")[sample]
	var site_id := String(label.get("site", ""))
	var site := site_info(site_id)
	var truth := String(site.get("rock_type", ""))
	var options := interpretation_options(variant)
	var chosen := String((options[int(ctx.request.params.choice)] as Dictionary).get("id", ""))
	lab["attempts"] = int(lab.get("attempts", 0)) + 1
	changes["sample"] = sample
	changes["chosen"] = chosen
	if chosen != truth:
		lab["variant"] = variant + 1
		changes["correct"] = false
		changes["variant"] = variant + 1
		changes["text"] = "%s The lab has measured a fresh part of the same sample (try %d). Compare again: nothing is lost by trying." % [
			_wrong_feedback(chosen, truth, sample_readout(site_id, variant)), variant + 2]
		return
	var rock: Dictionary = (samples_data().get("rock_types", {}) as Dictionary).get(truth, {})
	var value := ScienceBalance.get_current().nutrient_setting_for(truth)
	var unc := result_uncertainty(st)
	var result_id := _next_id(st, "result")
	_sub(st, "results")[result_id] = {"kind": "nutrient_setting", "value": value, "uncertainty": unc, "sample": sample, "site": site_id,
		"rock_type": truth, "reference": String(lab.get("reference", "")), "control": String(lab.get("control", "")), "by": String(ctx.actor.id),
		"at_hours": st.sim_hours, "applied": false, "applied_to": "", "applied_by": "", "applied_at_hours": -1.0}
	label["analysed"] = true
	label["result_id"] = result_id
	# The analysed sample stays in the lab's sample store: it leaves the pack (nothing is made or destroyed).
	ctx.actor.cargo.erase(StringName(sample))
	st.items.erase(sample)
	var new_evidence := ProgressEvidence.record(st, ctx.session.events, &"sci_compare_controls", "science", ctx.actor.id,
		{"sample": sample, "site": site_id, "reference": String(lab.get("reference", "")), "control": String(lab.get("control", "")), "attempts": int(lab.attempts)})
	changes["correct"] = true
	changes["result_id"] = result_id
	changes["value"] = value
	changes["uncertainty"] = unc
	changes["evidence"] = new_evidence
	changes["text"] = "Right: the sample is %s. Lab result: nutrient setting %s ± %s for a bed mixed with this ground. %s Use the result at a garden bed or the greenhouse console." % [
		String(rock.get("name", truth)), num(value, 2), num(unc, 2), String(rock.get("use", ""))]


## Why a wrong interpretation is wrong, in words, using the numbers the player saw. The choices are worded against
## reference 1, so the feedback compares with reference 1 too.
static func _wrong_feedback(chosen: String, truth: String, readout: Dictionary) -> String:
	var ref: Dictionary = reference_info(default_reference()).get("readout", {})
	var group_names := {}
	for g: Dictionary in samples_data().get("groups", []):
		group_names[String(g.id)] = String(g.name).to_lower()
	if chosen == "volcanic":
		return "Not quite. The sample is not like reference 1: %s are %d %% in the sample but only %d %% in the reference." % [
			String(group_names.get(truth, truth)), int(readout.get(truth, 0)), int(ref.get(truth, 0))]
	var word := String(group_names.get(chosen, chosen))
	var text := "Not quite. %s are %d %% in the sample and %d %% in the reference: about the same, so that is not what makes this sample different." % [
		word.left(1).to_upper() + word.substr(1), int(readout.get(chosen, 0)), int(ref.get(chosen, 0))]
	if truth == "volcanic":
		return text + " No group is far from the reference, so the sample is like it."
	return text + " Look for the group that is far bigger in the sample."


static func _apply_result(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	var id := String(ctx.request.params.result_id)
	var where := String(ctx.request.target)
	if String(ctx.target.get("kind", "")) == "lab":
		where = "all_beds"
	mark_result_applied(st, ctx.session.events, id, ctx.actor.id, where)
	var r: Dictionary = read(st, "results")[id]
	if String(r.get("kind", "")) == "nutrient_setting":
		changes["beds"] = CropSystem.apply_nutrient_setting(st, where, float(r.get("value", 0.0)))
		var applied: Array = CropSystem.ensure(st).applied_results
		if not applied.has(id):
			applied.append(id)
	changes["result_id"] = id
	changes["applied_to"] = where
	changes["value"] = float(r.get("value", 0.0))
	var place := "every garden bed" if where == "all_beds" else ("this bed" if String(ctx.target.get("kind", "")) == "bed" else "the greenhouse beds")
	changes["text"] = "Lab result used: the nutrient setting for %s is now %s (%d %%), the value the lab worked out from the sample." % [
		place, num(float(r.get("value", 0.0)), 2), roundi(100.0 * float(r.get("value", 0.0)))]


static func _inspect(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	var donor_id := String(ctx.request.target)
	var info := donor_info(donor_id)
	var rec := _donor(st, donor_id)
	rec["inspected"] = true
	var parts: Array = []
	for p: Dictionary in info.get("parts", []):
		parts.append({"id": String(p.id), "name": String(p.name), "clue": String(p.get("clue", "")),
			"fits": is_identified(st, donor_id, String(p.id)), "recovered": is_recovered(st, donor_id, String(p.id))})
	changes["parts"] = parts
	if not ctx.request.params.has("choice"):
		var shown := ""
		if st.has_upgrade("res_salvage_inspection"):
			var names := PackedStringArray()
			for p: Dictionary in parts:
				if bool(p.fits):
					names.append(String(p.name).to_lower())
			shown = " The salvage inspection shows every part that fits: %s." % ", ".join(names)
		changes["text"] = "You looked over the %s. Read the clue for each part and choose the one that fits the colony.%s" % [String(info.get("name", donor_id)).to_lower(), shown]
		return
	var choice := String(ctx.request.params.choice)
	var part := part_info(donor_id, choice)
	changes["choice"] = choice
	if bool(part.get("compatible", false)):
		(rec["identified"] as Dictionary)[choice] = true
		changes["fits"] = true
		changes["evidence"] = ProgressEvidence.record(st, ctx.session.events, &"res_identify_compatible", "resources", ctx.actor.id,
			{"donor": donor_id, "part": choice})
		changes["text"] = "Yes: the %s fits %s. %s The field engineering and geology specialist can now take it out." % [
			String(part.name).to_lower(), String(part.get("fits", "the colony")), String(part.get("clue", ""))]
	else:
		rec["wrong_choices"] = int(rec.get("wrong_choices", 0)) + 1
		(rec["rejected"] as Dictionary)[choice] = true
		changes["fits"] = false
		changes["text"] = "Not this one: %s Look for a part with no damage that matches the colony's own parts." % String(part.get("clue", ""))


static func _recover(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	var donor_id := String(ctx.request.target)
	var part_id := String(ctx.request.params.part)
	var part := part_info(donor_id, part_id)
	var item_id := _next_id(st, "salvage")
	var pos := ctx.actor.position
	st.items[item_id] = {"kind": SALVAGED_PREFIX + part_id, "position": [pos.x, pos.y, pos.z], "holder": String(ctx.actor.id),
		"donor": donor_id, "part": part_id}
	ctx.actor.cargo.append(StringName(item_id))
	((_donor(st, donor_id))["recovered"] as Dictionary)[part_id] = {"by": String(ctx.actor.id), "at_hours": st.sim_hours, "item": item_id}
	changes["item"] = item_id
	changes["part"] = part_id
	changes["text"] = "You took the %s out of the %s and put it in your pack. Take it to the workbench in the Hangar to refurbish it." % [
		String(part.get("name", part_id)).to_lower(), String(donor_info(donor_id).get("name", donor_id)).to_lower()]


static func _refurbish(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	var item_id := String(ctx.request.params.item)
	var item: Dictionary = st.items[item_id]
	var part_id := String(item.get("part", String(item.get("kind", "")).trim_prefix(SALVAGED_PREFIX)))
	var donor_id := String(item.get("donor", ""))
	var part := part_info(donor_id, part_id)
	var name := String(part.get("name", part_id.replace("_", " ")))
	# The salvaged part goes on the bench: the item is used up, exactly once.
	ctx.actor.cargo.erase(StringName(item_id))
	st.items.erase(item_id)
	changes["consumed"] = item_id
	changes["part"] = part_id
	if st.has_upgrade("res_repeat_assembly") and assembled_before(st, part_id):
		var added := _finish_component(st, part_id)
		changes["added_parts"] = added
		changes["tested"] = false
		changes["text"] = "The %s is refurbished. The colony has made this kind of component before, so it needs no bench test: +%d spare part (now %d)." % [
			name.to_lower(), added, st.parts]
		return
	var job_id := _next_id(st, "bench")
	var hours := refurbish_hours(st)
	_sub(st, "bench")[job_id] = {"part": part_id, "donor": donor_id, "name": name, "by": String(ctx.actor.id), "item": item_id,
		"started_at_hours": st.sim_hours, "ready_at_hours": st.sim_hours + hours, "done": false, "tested": false}
	changes["job"] = job_id
	changes["added_parts"] = 0
	changes["ready_in_hours"] = hours
	changes["text"] = "The %s is on the workbench being cleaned and fitted. It is ready for its bench test in %s." % [name.to_lower(), hours_text(hours)]


static func _bench_test(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	var job_id := String(ctx.request.params.job)
	var job: Dictionary = _sub(st, "bench")[job_id]
	var part_id := String(job.get("part", ""))
	var part := part_info(String(job.get("donor", "")), part_id)
	job["done"] = true
	job["tested"] = true
	job["tested_at_hours"] = st.sim_hours
	var added := _finish_component(st, part_id)
	changes["job"] = job_id
	changes["part"] = part_id
	changes["added_parts"] = added
	changes["tested"] = true
	changes["evidence"] = ProgressEvidence.record(st, ctx.session.events, &"res_assembly_test", "resources", ctx.actor.id,
		{"job": job_id, "part": part_id, "donor": String(job.get("donor", ""))})
	changes["text"] = "Bench test passed: %s The refurbished %s is a working spare part: +%d (now %d)." % [
		String(part.get("test", "it works.")), String(job.get("name", part_id)).to_lower(), added, st.parts]


## Adds the finished component: exactly ScienceBalance.components_per_part spare parts, counted in the ledger.
static func _finish_component(st: ColonyState, part_id: String) -> int:
	var added := ScienceBalance.get_current().components_per_part
	st.parts += added
	st.ledger[LEDGER_PARTS] = float(st.ledger.get(LEDGER_PARTS, 0.0)) + float(added)
	var comps := _sub(st, "components")
	comps[part_id] = int(comps.get(part_id, 0)) + 1
	return added


# ---------------------------------------------------------------- helpers (host only: they create missing records)

## A sub-dictionary of state.science, created if missing.
static func _sub(state: ColonyState, key: String) -> Dictionary:
	if not (state.science.get(key, null) is Dictionary):
		state.science[key] = {}
	return state.science[key]


static func _donor(state: ColonyState, donor_id: String) -> Dictionary:
	var donors := _sub(state, "donors")
	if not (donors.get(donor_id, null) is Dictionary):
		donors[donor_id] = {"inspected": false, "identified": {}, "rejected": {}, "recovered": {}, "wrong_choices": 0}
	var rec: Dictionary = donors[donor_id]
	for key: String in ["identified", "rejected", "recovered"]:
		if not (rec.get(key, null) is Dictionary):
			rec[key] = {}
	return rec


## A new id "<prefix>_<n>" from ColonyState.counters, unique across saves.
static func _next_id(state: ColonyState, prefix: String) -> String:
	var n := int(state.counters.get(prefix, 0)) + 1
	state.counters[prefix] = n
	var id := "%s_%d" % [prefix, n]
	while state.items.has(id) or read(state, "samples").has(id) or read(state, "results").has(id) or read(state, "bench").has(id):
		n += 1
		state.counters[prefix] = n
		id = "%s_%d" % [prefix, n]
	return id


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("ScienceActions: missing " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_warning("ScienceActions: could not read " + path)
	return {}
