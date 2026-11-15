extends SceneTree
## Prompt 08 part G: upgrades, knowledge and learning. Every PASS below is measured on the running model and actions:
## the catalogue and questions, eligibility (tier + knowledge + evidence + parts, each missing one alone), installing
## (parts once, idempotent, wrong installer or place refused), answers (once; wrong = explanation + changed version, no
## health change), tier 2 needs a changed example, practical evidence seen in the model, every energy and
## life-support effect (and nothing else changes), automation for 10 sols, exercise, a solo run with hub-only crew
## switching that installs one card per sector, save/load, and the panels at three screen sizes.
## Food, resources and science evidence (parts F and S) are recorded here directly with ProgressEvidence.record.
## Run: ..\godot.cmd --headless --path . --script res://tests/test_progression.gd

const MANIFEST := "res://data/colony_manifest.json"
const POWER := &"pw_panel"
const LS := &"ls_console"
const FOOD := &"gh_console"
const COMPUTER := &"cm_colony_computer"
const GYM := &"rk_treadmill"
## Stand-ins for the stations parts S adds (the lab and the workbench), at their map objects.
const STAND_INS := {"mb_glovebox": "lab", "hg_control_board": "workbench"}
const CARD_IDS: Array[String] = ["energy_battery_reserve", "energy_solar_tracking", "energy_cleaner_automation",
	"ls_water_reliability", "ls_electrolysis", "ls_co2_processing", "ls_oxygen_monitoring",
	"food_irrigation_reliability", "food_nutrient_metering", "food_scheduled_care",
	"res_salvage_inspection", "res_component_refurbishment", "res_repeat_assembly",
	"sci_instrument_calibration", "sci_sample_comparison", "sci_evidence_settings"]
const EVIDENCE_IDS: Array[String] = ["energy_predict_net_power", "energy_diagnose_output_loss", "energy_verify_recovery",
	"ls_distinguish_inputs", "ls_co2_removal", "ls_storage_vs_pressure", "food_compare_symptom", "food_adjust_one_cause",
	"food_observe_response", "res_identify_compatible", "res_assembly_test", "sci_record_context", "sci_compare_controls",
	"sci_apply_result", "comms_radio_check"]
const INSTALLERS := {"energy": "electrical_comms", "life_support": "medical_life_support", "food": "biology_food",
	"resources": "field_engineering_geology", "science": ""}
const SIZES := [[Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 1.0], [Vector2i(1280, 720), 1.5]]


## Collects engine and script errors raised while the test runs.
class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR or error_type == ERROR_TYPE_SCRIPT:
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _passed := 0
var _total := 0
var _catcher := ErrorCatcher.new()
var _event_nodes: Array[GameEvents] = []
var _zones: ColonyZones
var _catalog: Dictionary
var _objects: Dictionary = {}
var _noted_stub_scale := false


func _initialize() -> void:
	OS.add_logger(_catcher)
	PlayerInput.ensure_actions()
	_zones = ColonyZones.from_manifest(MANIFEST)
	_catalog = StationCatalog.from_manifest(MANIFEST, _zones)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for o: Dictionary in data.objects:
		var m: Array = o.matrix_world
		_objects[String(o.name)] = Vector3(float(m[0][3]), float(m[2][3]), -float(m[1][3]))
	_test_catalogue()
	_test_eligibility()
	_test_install()
	_test_answers()
	_test_changed_example()
	_test_energy_evidence()
	_test_life_support_evidence()
	_test_effect_solar_tracking()
	_test_effect_battery_reserve()
	_test_effect_cleaner_automation()
	_test_effect_water_reliability()
	_test_effect_electrolysis()
	_test_effect_co2_processing()
	_test_effect_monitoring()
	_test_automation_ten_sols()
	_test_exercise()
	_test_solo_run()
	await _test_save_load()
	await _test_panels()
	_check("no script or engine errors during the test", _catcher.errors.is_empty(), "\n".join(_catcher.errors))
	OS.remove_logger(_catcher)
	for node: GameEvents in _event_nodes:
		node.free()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


# ================================================================ helpers

func _check(label: String, condition: bool, detail: String = "state mismatch") -> void:
	_total += 1
	if condition:
		_passed += 1
		print("PASS " + label)
	else:
		print("FAIL " + label + ": " + detail)


## Adds the lab and workbench stations of part S if this copy does not have them yet.
func _add_stand_ins(stations: Dictionary) -> void:
	for id: String in STAND_INS:
		if not stations.has(id):
			var p: Vector3 = _objects[id]
			stations[id] = {"kind": STAND_INS[id], "zone": _zones.zone_of("", p), "position": [p.x, p.y, p.z], "specialty": ""}


## A host session on the real map with `active` crew controlled by peers 1..active, at the new-game time of day.
func _session(active: int = 1) -> SessionService:
	var ev := GameEvents.new()
	_event_nodes.append(ev)
	var s := SessionService.new(GameConfig.new(), GameBalance.new(), ev)
	var st := ColonyState.new_game(s.balance, 4242, _zones.names)
	st.stations = _catalog.duplicate(true)
	_add_stand_ins(st.stations)
	for c: CharacterState in st.characters.values():
		c.hub_spot = s.config.hub_position
		c.position = c.hub_spot
	var game_clock := SolClock.new()
	game_clock.phase = s.config.start_phase
	s.begin(st, game_clock)
	for i in active:
		st.character(StringName("crew_%d" % (i + 1))).owner_peer = i + 1
		if i > 0:
			s.peer_joined(i + 1)
	return s


func _at(s: SessionService, crew: StringName, station: StringName) -> void:
	s.state.character(crew).position = CharacterState._v3(s.state.stations[station].position)


func _do(s: SessionService, crew: StringName, action: StringName, station: StringName, params: Dictionary = {}) -> ActionResult:
	_at(s, crew, station)
	return s.request(action, station, params, s.state.character(crew).owner_peer)


## Advances the clock and model by `hours` game hours in ticks of `dt`.
func _hours(s: SessionService, hours: float, dt: float = 0.05, each: Callable = Callable()) -> void:
	var t := 0.0
	while t < hours - 1e-9:
		var h := minf(dt, hours - t)
		var phase_before := s.clock.phase
		var got := s.clock.advance(h / s.clock.hours_per_real_second())
		for id: StringName in s.sim.step(s.state, s.balance, phase_before, got):
			s.recover_character(id)
		t += h
		if each.is_valid():
			each.call(t)


func _right(st: ColonyState, qid: String) -> int:
	return int(ProgressionSystem.current_variant(st, StringName(qid)).get("correct", 0))


func _wrong(st: ColonyState, qid: String) -> int:
	return (_right(st, qid) + 1) % 3


func _answer(s: SessionService, crew: StringName, station: StringName, qid: String, right := true) -> ActionResult:
	var choice := _right(s.state, qid) if right else _wrong(s.state, qid)
	return _do(s, crew, &"answer_question", station, {"question_id": qid, "choice": choice})


## Records knowledge of `qid` directly in its first (or given) variant, as a stand-in for an earlier answer.
func _know(st: ColonyState, qid: String, variant := 0) -> void:
	var v: Dictionary = (ProgressionSystem.question(StringName(qid)).variants as Array)[variant]
	st.knowledge[qid] = {"by": "crew_1", "sector": String(ProgressionSystem.question(StringName(qid)).sector), "at_hours": 0.0, "variant": variant, "example": String(v.example)}


func _evidence(s: SessionService, id: String, actor: StringName = &"crew_1") -> void:
	ProgressEvidence.record(s.state, s.events, StringName(id), String((ProgressionSystem.catalogue().evidence as Dictionary)[id].sector), actor)


## Makes the card's requirements true directly (tier rule of its tier and below, its questions and evidence).
func _make_eligible(s: SessionService, card_id: String) -> void:
	var c := ProgressionSystem.card(StringName(card_id))
	for level in range(1, c.tier + 1):
		var rule := ProgressionSystem.tier_rule(c.sector, level)
		for q in rule.get("questions", []):
			_know(s.state, String(q))
		var d := String(rule.get("diagnosis", ""))
		if d != "":
			var guided := String(ProgressionSystem.question(StringName(d)).changed_from)
			_know(s.state, guided, 0)
			_know(s.state, d, 1)
		for e in rule.get("evidence", []):
			_evidence(s, String(e))
	for q in c.questions:
		if not s.state.knowledge.has(String(q)):
			_know(s.state, String(q))
	for e in c.evidence:
		_evidence(s, String(e))


func _installer_of(s: SessionService, c: UpgradeDefinition) -> StringName:
	for ch: CharacterState in s.state.characters.values():
		if c.specialty == &"" or ch.specialty == c.specialty:
			return ch.id
	return &""


## Gives the session's peer 1 the crew member `crew` (test shortcut for the tests that are not about switching).
func _control(s: SessionService, crew: StringName) -> void:
	for ch: CharacterState in s.state.characters.values():
		if ch.owner_peer == 1:
			ch.owner_peer = 0
	s.state.character(crew).owner_peer = 1


func _approx(a: float, b: float, tol := 1e-6) -> bool:
	return absf(a - b) <= tol * maxf(1.0, maxf(absf(a), absf(b)))


## Deep comparison of plain data, numbers compared as floats (JSON turns ints into floats).
func _same(a: Variant, b: Variant) -> bool:
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		return _approx(float(a), float(b), 1e-9)
	if a is Dictionary and b is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k in a:
			var kb: Variant = k if (b as Dictionary).has(k) else String(k)
			if not (b as Dictionary).has(kb) or not _same(a[k], b[kb]):
				return false
		return true
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not _same(a[i], b[i]):
				return false
		return true
	return typeof(a) == typeof(b) and a == b or String(a) == String(b)


## Two identical sessions: A without, B with the upgrade `id` (set directly as installed).
func _pair(id: String, active := 1) -> Array[SessionService]:
	var a := _session(active)
	var b := _session(active)
	b.state.upgrades[id] = {"installed": true}
	return [a, b]


## Store, cabin and ledger snapshot for "nothing else changed" comparisons.
func _numbers(st: ColonyState) -> Dictionary:
	var d := {}
	for k in ColonyState.STORE_KEYS:
		d[String(k)] = st.store(k)
	d["cabin_o2_kg"] = st.cabin_o2_kg
	d["cabin_n2_kg"] = st.cabin_n2_kg
	d["cabin_co2_kg"] = st.cabin_co2_kg
	d["water_quality"] = st.water_quality
	for k: String in st.ledger:
		d["ledger." + k] = float(st.ledger[k])
	return d


## Keys whose values differ between two snapshots.
func _differences(x: Dictionary, y: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in x:
		if not _approx(float(x[k]), float(y.get(k, 0.0)), 1e-9):
			out.append(k)
	return out


## Every water and oxygen ledger identity error (all should be 0).
func _identity_errors(st: ColonyState, start: Dictionary) -> float:
	var l := {}
	for k: String in st.ledger:
		l[k] = float(st.ledger[k]) - float(start.get("ledger." + k, 0.0))
	var dw := st.store(&"water_l") - float(start.water_l)
	var dww := st.store(&"wastewater_l") - float(start.wastewater_l)
	var do2 := st.store(&"oxygen_kg") - float(start.oxygen_kg)
	var all_water: float = dw + dww + l.water_body_loss_l + l.wastewater_overflow_l + l.brine_l + l.electrolysis_water_l + l.recovery_water_l
	var o2: float = do2 - (l.electrolysis_o2_kg + l.co2_unit_o2_kg - l.regulator_o2_kg - l.suit_refill_kg)
	var battery: float = st.store(&"battery_kwh") - float(start.battery_kwh) - (l.battery_in_kwh - l.battery_loss_kwh - l.battery_out_kwh)
	return maxf(absf(all_water), maxf(absf(o2), absf(battery)))


# ================================================================ catalogue

func _test_catalogue() -> void:
	ProgressionSystem.reload()
	var cards := ProgressionSystem.cards()
	var ids := PackedStringArray()
	var bad := PackedStringArray()
	var pb := ProgressionBalance.shared()
	var questions := ProgressionSystem.questions()
	for c in cards:
		ids.append(String(c.id))
		var problems := PackedStringArray()
		if c.title.is_empty() or c.function_text.is_empty() or c.effect.is_empty() or c.zone.is_empty():
			problems.append("words missing")
		if not INSTALLERS.has(c.sector) or String(c.specialty) != String(INSTALLERS[c.sector]):
			problems.append("installer %s" % c.specialty)
		if c.tier < 0 or c.tier > ProgressionSystem.MAX_TIER:
			problems.append("tier")
		if c.questions.size() < 2 or c.questions.size() > 4:
			problems.append("%d questions" % c.questions.size())
		for q in c.questions:
			if not questions.has(String(q)) or String(questions[String(q)].sector) != c.sector:
				problems.append("question %s" % q)
		if c.evidence.is_empty():
			problems.append("no evidence")
		for e in c.evidence:
			if not EVIDENCE_IDS.has(String(e)):
				problems.append("evidence %s" % e)
		# Prompt 11: the four radio cards cost 1-4 parts by contract (CommsStage.CARD_PARTS), not ProgressionBalance.
		var comms_i := CommsStage.CARD_IDS.find(String(c.id))
		var want_cost := CommsStage.CARD_PARTS[comms_i] if comms_i >= 0 else pb.parts_for(String(c.id))
		if c.cost_parts <= 0 or c.cost_parts != want_cost:
			problems.append("cost %d vs balance %d" % [c.cost_parts, want_cost])
		if not _catalog.has(String(c.install_station)) and not STAND_INS.has(String(c.install_station)):
			problems.append("install station %s" % c.install_station)
		if not _objects.has(String(c.install_station)):
			problems.append("install station is not a map object")
		if c.source_labels.is_empty() or c.effect_owner.is_empty():
			problems.append("labels")
		if not problems.is_empty():
			bad.append("%s: %s" % [c.id, ", ".join(problems)])
	var all_ids := true
	for id in CARD_IDS + Array(CommsStage.CARD_IDS):
		all_ids = all_ids and ids.has(id)
	_check("catalogue: the 16 contract upgrade ids and the 4 radio cards load into UpgradeDefinition with every field", cards.size() == 16 + CommsStage.CARD_IDS.size() and all_ids and bad.is_empty(),
		"%d cards; %s" % [cards.size(), "; ".join(bad)])
	# the json cost matches the balance resource
	var raw_costs := true
	for c: Dictionary in ProgressionSystem.catalogue().cards:
		if not CommsStage.CARD_IDS.has(String(c.id)):
			raw_costs = raw_costs and int(c.cost_parts) == pb.parts_for(String(c.id))
	_check("catalogue: parts costs in upgrades.json equal ProgressionBalance.card_parts", raw_costs and pb.card_parts.size() == 16)

	# branching: in every sector at least two cards share a tier; every sector has tiers 1..3 and the cheapest card of
	# each sector together fit the starting parts
	var branching := PackedStringArray()
	var cheapest := 0
	for sector in ProgressionSystem.SECTORS:
		var per_tier := {}
		var low := 1 << 20
		for c in ProgressionSystem.cards_of(sector):
			per_tier[c.tier] = int(per_tier.get(c.tier, 0)) + 1
			low = mini(low, c.cost_parts)
		cheapest += low
		var best := 0
		for t: int in per_tier:
			best = maxi(best, int(per_tier[t]))
		var tiers: Array = ProgressionSystem.sector_info(sector).get("tiers", [])
		if best < 2 or tiers.size() != 3:
			branching.append("%s: %s, %d tier rules" % [sector, per_tier, tiers.size()])
	_check("catalogue: every sector has 2+ cards eligible from the same tier and tier rules 1..3; one card per sector fits the 10 starting parts",
		branching.is_empty() and cheapest <= GameBalance.new().parts_start, "%s; cheapest set %d" % [", ".join(branching), cheapest])

	# questions: 3 answers, the right one, an explanation, a retry variant; diagnosis questions have a changed example
	var qbad := PackedStringArray()
	for qid: String in questions:
		var q: Dictionary = questions[qid]
		var variants: Array = q.get("variants", [])
		if variants.size() < 2 or not ProgressionSystem.SECTORS.has(String(q.get("sector", ""))):
			qbad.append("%s: %d variants" % [qid, variants.size()])
		var texts := {}
		for v: Dictionary in variants:
			texts[String(v.get("text", ""))] = true
			if (v.get("answers", []) as Array).size() != 3 or int(v.get("correct", -1)) < 0 or int(v.get("correct", -1)) > 2 \
					or String(v.get("explanation", "")).length() < 20 or String(v.get("example", "")).is_empty():
				qbad.append("%s variant" % qid)
		if texts.size() != variants.size():
			qbad.append("%s: variants not different" % qid)
		if String(q.get("role", "")) == "diagnosis":
			var guided := String(q.get("changed_from", ""))
			var gex := {}
			for v: Dictionary in (questions.get(guided, {}) as Dictionary).get("variants", []):
				gex[String(v.example)] = true
			var changed := 0
			for v: Dictionary in variants:
				if not gex.has(String(v.example)):
					changed += 1
			if not questions.has(guided) or changed < 1:
				qbad.append("%s: no changed example" % qid)
		var ev := String(q.get("records_evidence", ""))
		if ev != "" and not EVIDENCE_IDS.has(ev):
			qbad.append("%s evidence %s" % [qid, ev])
	_check("questions: each has 3 answers, the right one, an explanation and a different retry variant (%d questions)" % questions.size(),
		questions.size() >= 25 and qbad.is_empty(), "; ".join(qbad))

	var sources: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/model_sources_progression.json"))
	var missing := PackedStringArray()
	var fields := 0
	if sources is Dictionary:
		for p: Dictionary in ProgressionBalance.new().get_property_list():
			if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				fields += 1
				if not (sources as Dictionary).has(String(p.name)) or String((sources as Dictionary)[String(p.name)].get("category", "")).is_empty():
					missing.append(String(p.name))
	_check("model_sources_progression.json: all %d ProgressionBalance fields have an evidence category" % fields, sources is Dictionary and fields >= 20 and missing.is_empty(), str(missing))
	_check("stations_progression.json: the gym spot is a station in the rec kitchen next to the mess hall", _catalog.has(String(GYM)) and String(_catalog[String(GYM)].kind) == "gym",
		str(_catalog.get(String(GYM), {})))


# ================================================================ eligibility

func _test_eligibility() -> void:
	var id := "energy_battery_reserve"
	var c := ProgressionSystem.card(StringName(id))
	var base := _session()
	_make_eligible(base, id)
	_check("eligibility: with tier, questions, evidence and parts the card is eligible", ProgressionSystem.is_eligible(base.state, c),
		str(ProgressionSystem.missing(base.state, c)))
	# take away one requirement at a time
	var cases := [
		["tier", "energy", func(st: ColonyState) -> void: st.evidence.erase("energy_diagnose_output_loss")],
		["question", "energy_q_battery_night", func(st: ColonyState) -> void: st.knowledge.erase("energy_q_battery_night")],
		["question", "energy_q_net_power", func(st: ColonyState) -> void: st.knowledge.erase("energy_q_net_power")],
		["evidence", "energy_predict_net_power", func(st: ColonyState) -> void: st.evidence.erase("energy_predict_net_power")],
		["parts", "parts", func(st: ColonyState) -> void: st.parts = c.cost_parts - 1],
	]
	for entry: Array in cases:
		var s := _session()
		_make_eligible(s, id)
		(entry[2] as Callable).call(s.state)
		var lacking := ProgressionSystem.missing(s.state, c)
		var parts_before := s.state.parts
		var r := _do(s, &"crew_1", &"install_upgrade", POWER, {"upgrade_id": id})
		var reason_ok := r.reason == (&"insufficient" if entry[0] == "parts" else &"missing_prerequisite")
		var text := String(lacking[0].text) if lacking.size() == 1 else ""
		_check("eligibility: missing only the %s '%s' keeps it locked with that reason" % [entry[0], entry[1]],
			lacking.size() == 1 and String(lacking[0].kind) == String(entry[0]) and String(lacking[0].id) == String(entry[1])
			and not ProgressionSystem.is_eligible(s.state, c) and not r.ok and reason_ok and r.message.contains(text) and not text.is_empty()
			and s.state.parts == parts_before and not s.state.has_upgrade(id),
			"missing %s, answer %s '%s'" % [str(lacking), r.reason, r.message])


# ================================================================ install

func _test_install() -> void:
	var s := _session(2)
	var id := "energy_battery_reserve"
	var c := ProgressionSystem.card(StringName(id))
	_make_eligible(s, id)
	var parts := s.state.parts
	var cap := float(s.state.capacities[&"battery_kwh"])
	var r := _do(s, &"crew_2", &"install_upgrade", POWER, {"upgrade_id": id})
	_check("install: wrong installer (medical specialist) is refused", not r.ok and r.reason == &"wrong_specialty" and s.state.parts == parts and not s.state.has_upgrade(id),
		"%s %s" % [r.reason, r.message])
	r = _do(s, &"crew_1", &"install_upgrade", LS, {"upgrade_id": id})
	_check("install: wrong place (life-support console) is refused and says where", not r.ok and r.reason == &"wrong_target" and r.message.contains("power panel") and not s.state.has_upgrade(id),
		"%s %s" % [r.reason, r.message])
	_at(s, &"crew_1", POWER)
	s.state.character(&"crew_1").position += Vector3(5.0, 0.0, 0.0)
	r = s.request(&"install_upgrade", POWER, {"upgrade_id": id}, 1)
	_check("install: too far from the install station is refused", not r.ok and r.reason == &"too_far")
	r = _do(s, &"crew_1", &"install_upgrade", POWER, {"upgrade_id": "warp_drive"})
	_check("install: unknown card is refused", not r.ok and r.reason == &"unknown_target")

	var req := ActionRequest.make("install-1", 1, &"crew_1", &"install_upgrade", POWER, {"upgrade_id": id})
	_at(s, &"crew_1", POWER)
	r = s.submit(req)
	var after_parts := s.state.parts
	_check("install: consumes exactly the card's parts and records the upgrade", r.ok and after_parts == parts - c.cost_parts and s.state.has_upgrade(id)
		and String(s.state.upgrades[id].by) == "crew_1" and int(r.changes.parts_used) == c.cost_parts, "%s parts %d -> %d" % [r.reason, parts, after_parts])
	_check("install: battery capacity +25 %% once (%.0f -> %.0f kWh)" % [cap, float(s.state.capacities[&"battery_kwh"])],
		_approx(float(s.state.capacities[&"battery_kwh"]), cap * 1.25))
	var dup := s.submit(ActionRequest.make("install-1", 1, &"crew_1", &"install_upgrade", POWER, {"upgrade_id": id}))
	var again := _do(s, &"crew_1", &"install_upgrade", POWER, {"upgrade_id": id})
	_check("install: idempotent — the same request is a duplicate and a new request changes nothing",
		dup.duplicate and again.ok and bool(again.changes.already_installed) and s.state.parts == after_parts
		and _approx(float(s.state.capacities[&"battery_kwh"]), cap * 1.25) and float(s.state.ledger.parts_used_upgrades) == float(c.cost_parts),
		"dup %s, again %s, parts %d" % [dup.duplicate, again.changes, s.state.parts])


# ================================================================ answers

func _test_answers() -> void:
	var s := _session(2)
	var st := s.state
	var qid := "energy_q_battery_night"
	var health := [st.character(&"crew_1").health, st.character(&"crew_2").health]
	var v0 := ProgressionSystem.current_variant_index(st, StringName(qid))
	var text0 := String(ProgressionSystem.current_variant(st, StringName(qid)).text)
	var r := _answer(s, &"crew_1", COMPUTER, qid, false)
	var v1 := ProgressionSystem.current_variant_index(st, StringName(qid))
	_check("answer: a wrong answer gives the explanation and a changed version next time, no knowledge",
		r.ok and not bool(r.changes.correct) and String(r.changes.explanation).length() > 20 and String(r.changes.text).contains(String(r.changes.explanation))
		and v1 != v0 and int(r.changes.next_variant) == v1 and String(ProgressionSystem.current_variant(st, StringName(qid)).text) != text0 and not st.knowledge.has(qid),
		"%s %s v%d -> v%d" % [r.reason, r.changes, v0, v1])
	_check("answer: a wrong answer costs no health", st.character(&"crew_1").health == health[0] and st.character(&"crew_2").health == health[1])
	r = _answer(s, &"crew_1", COMPUTER, qid, true)
	var record: Dictionary = st.knowledge.get(qid, {}).duplicate()
	_check("answer: a right answer records the knowledge once for the colony", r.ok and bool(r.changes.correct) and String(record.get("by", "")) == "crew_1"
		and int(record.variant) == v1, str(record))
	var count := st.knowledge.size()
	var quiz_before: Dictionary = (ProgressionSystem.progress_of(st).quiz as Dictionary).duplicate(true)
	_hours(s, 0.5)
	var again := _answer(s, &"crew_2", COMPUTER, qid, true)
	var wrong_again := _answer(s, &"crew_2", COMPUTER, qid, false)
	_check("answer: repeating a right (or a wrong) answer adds nothing", again.ok and bool(again.changes.already_known) and wrong_again.ok and bool(wrong_again.changes.already_known)
		and st.knowledge.size() == count and _same(st.knowledge[qid], record) and _same(ProgressionSystem.progress_of(st).quiz, quiz_before), str(st.knowledge[qid]))
	r = _answer(s, &"crew_1", LS, "energy_q_tracking", true)
	_check("answer: refused at a station of another sector", not r.ok and r.reason == &"wrong_target" and r.message.contains("colony computer"), "%s %s" % [r.reason, r.message])
	r = _answer(s, &"crew_1", POWER, "energy_q_tracking", true)
	_check("answer: allowed at the sector's install station", r.ok and bool(r.changes.correct), "%s %s" % [r.reason, r.message])
	r = _answer(s, &"crew_1", COMPUTER, "energy_q_net_power", true)
	_check("answer: the readings question is refused away from the power panel", not r.ok and r.reason == &"wrong_target" and r.message.contains("power panel"), r.message)
	r = _answer(s, &"crew_1", POWER, "energy_q_net_power", true)
	_check("answer: right at the power panel records energy_predict_net_power once", r.ok and String(r.changes.get("evidence", "")) == "energy_predict_net_power"
		and st.evidence.has("energy_predict_net_power") and String(st.evidence.energy_predict_net_power.by) == "crew_1", str(r.changes))
	r = _do(s, &"crew_1", &"answer_question", COMPUTER, {"question_id": "nope", "choice": 0})
	var r2 := _do(s, &"crew_1", &"answer_question", COMPUTER, {"question_id": qid, "choice": 3})
	_check("answer: unknown question and a choice out of 0..2 are refused", not r.ok and r.reason == &"unknown_target" and not r2.ok and r2.reason == &"bad_request")


# ================================================================ tier 2 needs a changed example

func _test_changed_example() -> void:
	var s := _session()
	var st := s.state
	var r := _answer(s, &"crew_1", COMPUTER, "energy_q_diagnose", true)
	_check("tier 2: the diagnosis question waits for the guided question", not r.ok and r.reason == &"missing_prerequisite", "%s %s" % [r.reason, r.message])
	_evidence(s, "energy_diagnose_output_loss")
	r = _answer(s, &"crew_1", COMPUTER, "energy_q_dust_output", true)
	var guided_example := String(st.knowledge.energy_q_dust_output.example)
	_check("tier 1: guided task + its explanation question give level 1", r.ok and ProgressionSystem.tier(st, "energy") == 1
		and int(ProgressionSystem.progress_of(st).tiers.energy) == 1, "tier %d" % ProgressionSystem.tier(st, "energy"))
	_evidence(s, "energy_predict_net_power")
	var shown := String(ProgressionSystem.current_variant(st, &"energy_q_diagnose").example)
	_check("tier 2: the diagnosis is shown in a changed example ('%s', guided was '%s')" % [shown, guided_example], shown != guided_example and not shown.is_empty())

	# the same example as the guided one does not count (a stand-in record, as a naive answer would leave it)
	var copy := ColonyState.from_dict(st.to_dict())
	copy.knowledge["energy_q_diagnose"] = {"by": "crew_1", "sector": "energy", "at_hours": 0.0, "variant": 0, "example": guided_example}
	_check("tier 2: a diagnosis in the same example as the guided one keeps level 1", ProgressionSystem.compute_tier(copy, "energy") == 1
		and not ProgressionSystem.diagnosis_changed(copy, &"energy_q_diagnose"), "tier %d" % ProgressionSystem.compute_tier(copy, "energy"))
	r = _answer(s, &"crew_1", COMPUTER, "energy_q_diagnose", true)
	_check("tier 2: answering the changed example gives level 2", r.ok and bool(r.changes.correct) and ProgressionSystem.tier(st, "energy") == 2
		and String(st.knowledge.energy_q_diagnose.example) != guided_example and int(ProgressionSystem.progress_of(st).tiers.energy) == 2,
		"tier %d %s" % [ProgressionSystem.tier(st, "energy"), st.knowledge.get("energy_q_diagnose", {})])
	# a wrong diagnosis answer moves to another changed example, never the guided one
	var s2 := _session()
	_answer(s2, &"crew_1", COMPUTER, "energy_q_dust_output", true)
	var g2 := String(s2.state.knowledge.energy_q_dust_output.example)
	var seen := PackedStringArray()
	for i in 4:
		seen.append(String(ProgressionSystem.current_variant(s2.state, &"energy_q_diagnose").example))
		_answer(s2, &"crew_1", COMPUTER, "energy_q_diagnose", false)
	_check("tier 2: retry versions of the diagnosis never repeat the guided example", not seen.has(g2) and seen[0] != seen[1], "guided %s, shown %s" % [g2, seen])
	# tiers never go down
	st.evidence.erase("energy_predict_net_power")
	ProgressionSystem.update_tiers(st, s.events)
	_check("tiers: stored colony tiers never go down", ProgressionSystem.tier(st, "energy") == 2)


# ================================================================ practical evidence in the model

func _test_energy_evidence() -> void:
	# clean one dusty panel while output is low
	var s := _session()
	var st := s.state
	_hours(s, 0.1)
	var r := _do(s, &"crew_1", &"clean_panel", &"sf_solar_tracker")
	_hours(s, 0.05)
	_check("evidence: cleaning a panel while the panels give < 80 % records energy_diagnose_output_loss (by crew_1)", r.ok and st.evidence.has("energy_diagnose_output_loss")
		and String(st.evidence.energy_diagnose_output_loss.by) == "crew_1" and not st.evidence.has("energy_verify_recovery"), str(st.evidence))
	for i in range(1, 12):
		_do(s, &"crew_1", &"clean_panel", StringName("sf_solar_tracker.%03d" % i))
	_hours(s, 0.05)
	_check("evidence: output back above 95 % within a sol records energy_verify_recovery", st.evidence.has("energy_verify_recovery")
		and ProgressionSystem.clean_share(st) > 0.95, str(st.evidence.keys()))
	# the cleaner repaired while output is low; the sunrise wipe then shows the recovery
	var s2 := _session()
	_hours(s2, 0.1)
	r = _do(s2, &"crew_1", &"repair_cleaner", &"sf_solar_tracker.003")
	_hours(s2, 0.05)
	var got_fix := s2.state.evidence.has("energy_diagnose_output_loss") and String(s2.state.evidence.energy_diagnose_output_loss.detail.fix) == "repair_cleaner"
	_hours(s2, GameConfig.SOL_HOURS * 0.98)
	_check("evidence: repairing the cleaner while output is low, then the sunrise wipe, records both energy ids", r.ok and got_fix and s2.state.evidence.has("energy_verify_recovery"),
		"%s %s" % [r.reason, s2.state.evidence.keys()])
	# a fix while output is fine is not a diagnosis
	var s3 := _session()
	for i in ColonyState.TRACKER_COUNT:
		s3.state.panel_dust[i] = 0.1
	_hours(s3, 0.1)
	_do(s3, &"crew_1", &"clean_panel", &"sf_solar_tracker")
	_hours(s3, 0.05)
	_check("evidence: cleaning while output is above 80 % records nothing", s3.state.evidence.is_empty(), str(s3.state.evidence.keys()))


func _test_life_support_evidence() -> void:
	var s := _session()
	var st := s.state
	_do(s, &"crew_1", &"set_water_allocation", LS, {"electrolysis_feed_l_per_hour": 1.0})
	_do(s, &"crew_1", &"set_equipment", LS, {"equipment": "electrolyser", "on": true})
	_do(s, &"crew_1", &"set_equipment", LS, {"equipment": "co2_unit", "on": true})
	_hours(s, 0.8)
	var early := st.evidence.has("ls_distinguish_inputs")
	_hours(s, 0.4)
	_check("evidence: electrolyser and CO2 unit one hour each record ls_distinguish_inputs (not before)", not early and st.evidence.has("ls_distinguish_inputs")
		and String(st.evidence.ls_distinguish_inputs.by) == "crew_1", str(st.evidence.keys()))
	# CO2 rises with the scrubber off and falls again with it on
	var s2 := _session(4)
	_do(s2, &"crew_1", &"set_equipment", LS, {"equipment": "scrubber", "on": false})
	var hours := 0.0
	while s2.state.cabin_co2_kpa < s2.balance.co2_warn_kpa and hours < 200.0:
		_hours(s2, 1.0)
		hours += 1.0
	var high := s2.state.cabin_co2_kpa >= s2.balance.co2_warn_kpa and not s2.state.evidence.has("ls_co2_removal")
	_do(s2, &"crew_1", &"set_equipment", LS, {"equipment": "scrubber", "on": true})
	var back := 0.0
	while s2.state.cabin_co2_kpa >= s2.balance.co2_warn_kpa and back < 50.0:
		_hours(s2, 0.25)
		back += 0.25
	_hours(s2, 0.05)
	_check("evidence: CO2 above the warning level, then back below records ls_co2_removal (%.0f h up, %.2f h down)" % [hours, back],
		high and s2.state.evidence.has("ls_co2_removal") and s2.state.cabin_co2_kpa < s2.balance.co2_warn_kpa, str(s2.state.evidence.keys()))


# ================================================================ effects (each changes the model and nothing else)

func _test_effect_solar_tracking() -> void:
	var p := _pair("energy_solar_tracking")
	var a := p[0]
	var b := p[1]
	var phase := 0.5
	var ratio := PowerModel.solar_kw(b.state, b.balance, phase, true) / PowerModel.solar_kw(a.state, a.balance, phase, true)
	var fixed := PowerModel.solar_kw(b.state, b.balance, phase, false) / PowerModel.solar_kw(a.state, a.balance, phase, false)
	var drive_a := PowerModel.equipment_kw(a.state, a.balance, "trackers", {})
	var drive_b := PowerModel.equipment_kw(b.state, b.balance, "trackers", {})
	_check("effect solar tracking: tracking panels +10 %% (x%.3f), fixed panels unchanged, drives %.2f -> %.2f kW" % [ratio, drive_a, drive_b],
		_approx(ratio, 1.1) and _approx(fixed, 1.0) and _approx(drive_a, 0.6) and _approx(drive_b, 0.3))
	var start := _numbers(b.state)
	_hours(a, 3.0)
	_hours(b, 3.0)
	var na := _numbers(a.state)
	var nb := _numbers(b.state)
	var diff := _differences(na, nb)
	var allowed := ["battery_kwh", "ledger.solar_offered_kwh", "ledger.solar_used_kwh", "ledger.solar_curtailed_kwh", "ledger.battery_in_kwh",
		"ledger.battery_loss_kwh", "ledger.load_served_kwh", "ledger.battery_out_kwh"]
	var extra := PackedStringArray()
	for k in diff:
		if not allowed.has(k):
			extra.append(k)
	_check("effect solar tracking: over 3 h more solar energy and nothing else changes (water, oxygen, cabin, food)",
		float(nb["ledger.solar_offered_kwh"]) > float(na["ledger.solar_offered_kwh"]) * 1.05 and extra.is_empty() and _identity_errors(b.state, start) < 1e-6,
		"different: %s" % ", ".join(extra))


func _test_effect_battery_reserve() -> void:
	var p := _pair("energy_battery_reserve")
	var a := p[0]
	var b := p[1]
	for s in p:
		s.state.capacities[&"battery_kwh"] = 1000.0
		s.state.stores[&"battery_kwh"] = 240.0
		s.clock.phase = 0.85
	var reserve := PowerModel.life_support_reserve_kwh(b.state)
	_hours(a, 4.0)
	_hours(b, 4.0)
	var shed_b := b.state.shed.duplicate()
	_check("effect battery reserve: at night lights may not use the last %.0f kWh; life support keeps running" % reserve,
		_approx(reserve, 200.0) and PowerModel.life_support_reserve_kwh(a.state) == 0.0 and shed_b.has("lights") and shed_b.has("greenhouse")
		and b.state.is_powered("scrubber") and b.state.is_powered("cabin_fans") and b.state.is_powered("recycler") and a.state.shed.is_empty()
		and b.state.store(&"battery_kwh") > a.state.store(&"battery_kwh") + 20.0,
		"battery A %.1f B %.1f, shed B %s A %s" % [a.state.store(&"battery_kwh"), b.state.store(&"battery_kwh"), shed_b, a.state.shed])
	var diff := _differences(_numbers(a.state), _numbers(b.state))
	var extra := PackedStringArray()
	for k in diff:
		if not (k.begins_with("ledger.battery") or k.begins_with("ledger.load_") or k == "battery_kwh"):
			extra.append(k)
	_check("effect battery reserve: only the battery and the shed loads change (water, oxygen, cabin air the same)", extra.is_empty(), ", ".join(extra))


func _test_effect_cleaner_automation() -> void:
	var p := _pair("energy_cleaner_automation")
	var a := p[0]
	var b := p[1]
	_hours(a, GameConfig.SOL_HOURS * 1.2)
	_hours(b, GameConfig.SOL_HOURS * 1.2)
	_check("effect cleaner automation: a broken cleaner repairs itself after a sol (without the upgrade it stays broken)",
		a.state.condition_of("cleaner") < a.balance.equipment_min_condition and b.state.condition_of("cleaner") >= 1.0
		and int(ProgressionSystem.progress_of(b.state).automation.cleaner_self_repairs) == 1,
		"A %.2f B %.2f" % [a.state.condition_of("cleaner"), b.state.condition_of("cleaner")])
	_hours(a, GameConfig.SOL_HOURS)
	_hours(b, GameConfig.SOL_HOURS)
	var diff := _differences(_numbers(a.state), _numbers(b.state))
	var extra := PackedStringArray()
	for k in diff:
		if not (k.begins_with("ledger.battery") or k.begins_with("ledger.solar") or k.begins_with("ledger.load_") or k == "battery_kwh"):
			extra.append(k)
	_check("effect cleaner automation: the panels get wiped again (dust %.2f vs %.2f), only energy numbers change" % [PowerModel.average_dust(b.state), PowerModel.average_dust(a.state)],
		PowerModel.average_dust(b.state) < 0.05 and PowerModel.average_dust(a.state) > 0.4 and extra.is_empty(), ", ".join(extra))


func _test_effect_water_reliability() -> void:
	var p := _pair("ls_water_reliability")
	for s in p:
		s.state.equipment["recycler"]["condition"] = 0.6
		s.state.stores[&"wastewater_l"] = 300.0
	var a := p[0]
	var b := p[1]
	var start := _numbers(b.state)
	_hours(a, 5.0)
	_hours(b, 5.0)
	var in_a := float(a.state.ledger.recycler_in_l)
	var in_b := float(b.state.ledger.recycler_in_l)
	_check("effect water reliability: recycler cleans 4 instead of 3 L/h (%.2f vs %.2f L in 5 h), condition floor 0.8 keeps the water clean" % [in_b, in_a],
		_approx(in_a, 15.0, 1e-4) and _approx(in_b, 20.0, 1e-4) and b.state.condition_of("recycler") >= 0.8 - 1e-9 and a.state.condition_of("recycler") < 0.7
		and b.state.water_quality > 0.999 and a.state.water_quality < b.state.water_quality, "quality A %.3f B %.3f" % [a.state.water_quality, b.state.water_quality])
	var diff := _differences(_numbers(a.state), _numbers(b.state))
	var allowed := ["water_l", "wastewater_l", "water_quality", "ledger.recycler_in_l", "ledger.water_recycled_l", "ledger.brine_l"]
	var extra := PackedStringArray()
	for k in diff:
		if not allowed.has(k):
			extra.append(k)
	_check("effect water reliability: only water numbers change (battery, oxygen, cabin air the same); water ledger still balances",
		extra.is_empty() and _identity_errors(b.state, start) < 1e-6, ", ".join(extra))


func _test_effect_electrolysis() -> void:
	var p := _pair("ls_electrolysis")
	for s in p:
		_do(s, &"crew_1", &"set_water_allocation", LS, {"electrolysis_feed_l_per_hour": 1.0})
		_do(s, &"crew_1", &"set_equipment", LS, {"equipment": "electrolyser", "on": true})
		s.balance.battery_discharge_kw_max = 1.0e5
		s.state.capacities[&"battery_kwh"] = 1.0e7
		s.state.stores[&"battery_kwh"] = 5.0e6
	var a := p[0]
	var b := p[1]
	var start := _numbers(b.state)
	_hours(a, 4.0)
	_hours(b, 4.0)
	var oa := float(a.state.ledger.electrolysis_o2_kg)
	var ob := float(b.state.ledger.electrolysis_o2_kg)
	var kwh_a := float(a.state.unit("electrolyser").kw) / LifeSupportModel.electrolysis_o2_kg_per_hour(a.state, a.balance)
	var kwh_b := float(b.state.unit("electrolyser").kw) / LifeSupportModel.electrolysis_o2_kg_per_hour(b.state, b.balance)
	_check("effect electrolysis: +50 %% oxygen (%.3f vs %.3f kg in 4 h) at the same %.1f kWh per kg and 1.126 L water per kg" % [ob, oa, kwh_b],
		_approx(ob, oa * 1.5, 1e-6) and _approx(oa, 0.8, 1e-6) and _approx(kwh_a, kwh_b) and _approx(kwh_b, b.balance.electrolysis_kwh_per_kg_o2)
		and _approx(float(b.state.ledger.electrolysis_water_l) / ob, GameBalance.WATER_KG_PER_KG_O2))
	var diff := _differences(_numbers(a.state), _numbers(b.state))
	var extra := PackedStringArray()
	for k in ["ledger.co2_unit_o2_kg", "cabin_co2_kg", "ledger.recycler_in_l", "ledger.co2_scrubbed_kg", "food_meals"]:
		if diff.has(k):
			extra.append(k)
	_check("effect electrolysis: the CO2 unit, cabin CO2, recycler and food do not change; ledgers balance", extra.is_empty() and _identity_errors(b.state, start) < 1e-6,
		", ".join(extra))


func _test_effect_co2_processing() -> void:
	var p := _pair("ls_co2_processing")
	for s in p:
		_do(s, &"crew_1", &"set_equipment", LS, {"equipment": "co2_unit", "on": true})
		s.balance.battery_discharge_kw_max = 1.0e5
		s.state.capacities[&"battery_kwh"] = 1.0e7
		s.state.stores[&"battery_kwh"] = 5.0e6
	var a := p[0]
	var b := p[1]
	_hours(a, 4.0)
	_hours(b, 4.0)
	var oa := float(a.state.ledger.co2_unit_o2_kg)
	var ob := float(b.state.ledger.co2_unit_o2_kg)
	_check("effect CO2 processing: +50 %% oxygen from Mars CO2 (%.3f vs %.3f kg in 4 h)" % [ob, oa], _approx(ob, oa * 1.5, 1e-6) and _approx(oa, 0.6, 1e-6))
	var water_same := _approx(a.state.store(&"water_l"), b.state.store(&"water_l"), 1e-12) and _approx(a.state.store(&"wastewater_l"), b.state.store(&"wastewater_l"), 1e-12) \
		and float(b.state.ledger.electrolysis_water_l) == 0.0
	_check("effect CO2 processing: still no water at all (water and wastewater identical with and without)", water_same,
		"water A %.6f B %.6f" % [a.state.store(&"water_l"), b.state.store(&"water_l")])


func _test_effect_monitoring() -> void:
	var p := _pair("ls_oxygen_monitoring")
	var counts := {}
	p[1].events.system_alert.connect(func(id: StringName, _level: StringName, _text: String) -> void: counts[String(id)] = int(counts.get(String(id), 0)) + 1)
	for s in p:
		s.state.stores[&"oxygen_kg"] = 25.0
		s.state.cabin_o2_kg = s.balance.gas_kg_for_kpa(19.5, GameBalance.MOLAR_O2)
		s.state.cabin_co2_kg = s.balance.gas_kg_for_kpa(0.46, GameBalance.MOLAR_CO2)
	var a := p[0]
	var b := p[1]
	_hours(a, 0.05)
	_hours(b, 0.05)
	var ids_a := {}
	for al: Dictionary in a.state.alerts:
		ids_a[String(al.id)] = String(al.text)
	var ids_b := {}
	for al: Dictionary in b.state.alerts:
		ids_b[String(al.id)] = String(al.text)
	_check("effect oxygen monitoring: earlier warnings for the reserve (25 kg), cabin oxygen (19.5 kPa) and CO2 (0.46 kPa)",
		ids_b.has("oxygen_reserve_low") and ids_b.has("cabin_o2_low") and ids_b.has("co2_high")
		and not ids_a.has("oxygen_reserve_low") and not ids_a.has("cabin_o2_low") and not ids_a.has("co2_high"), "A %s | B %s" % [ids_a.keys(), ids_b.keys()])
	_check("effect oxygen monitoring: clearer words (how long is left, harm levels) and a forecast line announced on the HUD",
		String(ids_b.get("oxygen_reserve_low", "")).contains("at this rate") and String(ids_b.get("cabin_o2_low", "")).contains("harmed below")
		and ids_b.has("oxygen_forecast") and int(counts.get("oxygen_forecast", 0)) == 1 and not ids_a.has("oxygen_forecast"), str(ids_b))
	_hours(a, 2.0)
	_hours(b, 2.0)
	var diff := _differences(_numbers(a.state), _numbers(b.state))
	_check("effect oxygen monitoring: the air, the stores and every ledger stay exactly the same", diff.is_empty(), ", ".join(diff))


func _test_automation_ten_sols() -> void:
	var s := _session()
	s.state.upgrades["energy_cleaner_automation"] = {"installed": true}
	s.state.equipment["cleaner"]["condition"] = 1.0
	for i in ColonyState.TRACKER_COUNT:
		s.state.panel_dust[i] = 0.0
	var worst := {"broken_hours": 0.0, "run": 0.0, "dust": 0.0, "never_broke": true}
	var breaks := [2.0 * GameConfig.SOL_HOURS, 6.5 * GameConfig.SOL_HOURS]
	var done := [false, false]
	var each := func(t: float) -> void:
		for i in breaks.size():
			if t >= float(breaks[i]) and not bool(done[i]):
				done[i] = true
				s.state.equipment["cleaner"]["condition"] = 0.0           # a failure from outside (dust storm grit)
		if s.state.condition_of("cleaner") < s.balance.equipment_min_condition:
			worst.run = float(worst.run) + 0.1
			worst.broken_hours = maxf(float(worst.broken_hours), float(worst.run))
		else:
			worst.run = 0.0
		worst.dust = maxf(float(worst.dust), PowerModel.average_dust(s.state))
	_hours(s, 10.0 * GameConfig.SOL_HOURS, 0.1, each)
	_check("automation: over 10 sols the cleaner is never broken longer than a sol (longest %.1f h) and the panels stay clean (worst dust %.3f)" % [worst.broken_hours, worst.dust],
		float(worst.broken_hours) <= GameConfig.SOL_HOURS + 0.3 and float(worst.dust) < 0.1 and int(ProgressionSystem.progress_of(s.state).automation.cleaner_self_repairs) == 2
		and s.state.condition_of("cleaner") >= 1.0)
	var calm := _session()
	calm.state.upgrades["energy_cleaner_automation"] = {"installed": true}
	calm.state.equipment["cleaner"]["condition"] = 1.0
	var ok := [true]
	_hours(calm, 10.0 * GameConfig.SOL_HOURS, 0.2, func(_t: float) -> void:
		for id in ColonyState.EQUIPMENT_IDS:
			if calm.state.condition_of(id) < 1.0:
				ok[0] = false)
	_check("automation: nothing breaks on a schedule in 10 sols (every machine stays at condition 1)", bool(ok[0]))


# ================================================================ exercise

func _test_exercise() -> void:
	var a := _session()
	var b := _session()
	_hours(a, 0.1)
	_hours(b, 0.1)
	var me := b.state.character(&"crew_1")
	me.stamina = 90.0
	a.state.character(&"crew_1").stamina = 90.0
	var battery := b.state.store(&"battery_kwh")
	var r := _do(b, &"crew_1", &"exercise", GYM)
	_check("exercise: uses body energy now and raises conditioning; the battery does not change",
		r.ok and _approx(me.stamina, 65.0) and _approx(ProgressionSystem.conditioning(b.state, &"crew_1"), 0.1) and b.state.store(&"battery_kwh") == battery
		and String(r.changes.text).contains("not colony electricity"), "%s stamina %.1f" % [r.reason, me.stamina])
	a.state.character(&"crew_1").stamina = me.stamina
	_hours(a, 2.0)
	_hours(b, 2.0)
	var sa := a.state.character(&"crew_1").stamina
	_check("exercise: body energy recovers faster with conditioning (%.2f vs %.2f after 2 h), capped at 100" % [me.stamina, sa],
		me.stamina > sa + 1.0 and _approx(me.stamina - sa, 0.1 * ProgressionBalance.shared().conditioning_recovery_per_hour * 2.0, 1e-3) and me.stamina <= 100.0)
	_check("exercise: the battery is the same as without exercise after 2 h", _approx(a.state.store(&"battery_kwh"), b.state.store(&"battery_kwh"), 1e-12),
		"A %.6f B %.6f" % [a.state.store(&"battery_kwh"), b.state.store(&"battery_kwh")])
	me.stamina = 10.0
	r = _do(b, &"crew_1", &"exercise", GYM)
	var w := _do(b, &"crew_1", &"exercise", POWER)
	_check("exercise: refused when too tired (no health change) and away from the gym spot", not r.ok and r.reason == &"insufficient" and me.stamina == 10.0
		and me.health == 100.0 and not w.ok and w.reason == &"wrong_target", "%s %s" % [r.reason, w.reason])
	me.stamina = 100.0
	for i in 15:
		_do(b, &"crew_1", &"exercise", GYM)
		me.stamina = 100.0
	_check("exercise: conditioning is capped", _approx(ProgressionSystem.conditioning(b.state, &"crew_1"), ProgressionBalance.shared().conditioning_max))


# ================================================================ solo run, hub-only switching

func _test_solo_run() -> void:
	var s := _session(1)
	var st := s.state
	var log := PackedStringArray()
	var ok := true
	var installs := {}
	var hub := s.config.hub_position
	_hours(s, 0.1)
	# --- energy with the electrical specialist (crew_1)
	for i in ColonyState.TRACKER_COUNT:
		var tid := "sf_solar_tracker" if i == 0 else "sf_solar_tracker.%03d" % i
		ok = _do(s, &"crew_1", &"clean_panel", StringName(tid)).ok and ok
	_hours(s, 0.05)
	ok = _answer(s, &"crew_1", POWER, "energy_q_dust_output").ok and ok
	ok = _answer(s, &"crew_1", POWER, "energy_q_tracking").ok and ok
	var r := _do(s, &"crew_1", &"install_upgrade", POWER, {"upgrade_id": "energy_solar_tracking"})
	installs["energy"] = r.ok
	log.append("energy %s %s" % [r.reason, r.message])
	# --- switching is only at the hub
	r = s.request(&"claim_character", &"crew_2", {}, 1)
	var refused_away := not r.ok and r.reason == &"not_at_hub"
	st.character(&"crew_1").position = hub
	r = s.request(&"claim_character", &"crew_2", {}, 1)
	var switched := r.ok and st.character(&"crew_2").owner_peer == 1 and st.character(&"crew_1").owner_peer == 0
	# --- life support with the medical specialist (crew_2)
	_do(s, &"crew_2", &"set_water_allocation", LS, {"electrolysis_feed_l_per_hour": 1.0})
	_do(s, &"crew_2", &"set_equipment", LS, {"equipment": "electrolyser", "on": true})
	_do(s, &"crew_2", &"set_equipment", LS, {"equipment": "co2_unit", "on": true})
	_hours(s, 1.2)
	ok = _answer(s, &"crew_2", LS, "ls_q_two_paths").ok and ok
	ok = _answer(s, &"crew_2", LS, "ls_q_recycler").ok and ok
	r = _do(s, &"crew_2", &"install_upgrade", LS, {"upgrade_id": "ls_water_reliability"})
	installs["life_support"] = r.ok
	log.append("ls %s %s" % [r.reason, r.message])
	# --- food with the biology specialist (crew_3); part F's evidence recorded as a stand-in
	st.character(&"crew_2").position = hub
	switched = s.request(&"claim_character", &"crew_3", {}, 1).ok and switched
	_evidence(s, "food_compare_symptom", &"crew_3")
	ok = _answer(s, &"crew_3", FOOD, "food_q_symptom").ok and ok
	ok = _answer(s, &"crew_3", FOOD, "food_q_water").ok and ok
	r = _do(s, &"crew_3", &"install_upgrade", FOOD, {"upgrade_id": "food_irrigation_reliability"})
	installs["food"] = r.ok
	log.append("food %s %s" % [r.reason, r.message])
	# --- resources and science with the field engineering and geology specialist (crew_4); part S stand-ins
	st.character(&"crew_3").position = hub
	switched = s.request(&"claim_character", &"crew_4", {}, 1).ok and switched
	_evidence(s, "res_identify_compatible", &"crew_4")
	ok = _answer(s, &"crew_4", COMPUTER, "res_q_compatible").ok and ok
	ok = _answer(s, &"crew_4", &"hg_control_board", "res_q_matter").ok and ok
	r = _do(s, &"crew_4", &"install_upgrade", &"hg_control_board", {"upgrade_id": "res_salvage_inspection"})
	installs["resources"] = r.ok
	log.append("res %s %s" % [r.reason, r.message])
	_evidence(s, "sci_record_context", &"crew_4")
	ok = _answer(s, &"crew_4", COMPUTER, "sci_q_context").ok and ok
	ok = _answer(s, &"crew_4", COMPUTER, "sci_q_reference").ok and ok
	ok = _answer(s, &"crew_4", &"mb_glovebox", "sci_q_control").ok and ok
	r = _do(s, &"crew_4", &"install_upgrade", &"mb_glovebox", {"upgrade_id": "sci_sample_comparison"})
	installs["science"] = r.ok
	log.append("sci %s %s" % [r.reason, r.message])
	var per_sector := true
	for sector in ProgressionSystem.SECTORS:
		per_sector = per_sector and bool(installs.get(sector, false)) and ProgressionSystem.tier(st, sector) >= 1
	_check("solo run: one player switching crew only at the hub installs one card per sector (parts 10 -> %d)" % st.parts,
		ok and per_sector and refused_away and switched and st.parts == 0 and s.peers.size() == 1 and st.upgrades.size() == 5
		and String(st.upgrades.energy_solar_tracking.by) == "crew_1" and String(st.upgrades.ls_water_reliability.by) == "crew_2"
		and String(st.upgrades.food_irrigation_reliability.by) == "crew_3" and String(st.upgrades.res_salvage_inspection.by) == "crew_4",
		"ok %s, installs %s, away refused %s, switched %s, parts %d\n  %s" % [ok, installs, refused_away, switched, st.parts, "\n  ".join(log)])
	_check("solo run: every state invariant still holds", st.invariants_ok().is_empty(), str(st.invariants_ok()))


# ================================================================ save / load

func _test_save_load() -> void:
	var g := GameServices.new()
	g.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/wG"), "colony", 2)
	root.add_child(g)
	g.saves.delete_all()
	g.start_new_game(5)
	await process_frame
	g.set_process(false)
	var st := g.state()
	_add_stand_ins(st.stations)
	var s := g.session
	_evidence(s, "energy_diagnose_output_loss")
	_evidence(s, "energy_predict_net_power")
	_answer(s, &"crew_1", POWER, "energy_q_tracking", false)
	_answer(s, &"crew_1", POWER, "energy_q_dust_output")
	_answer(s, &"crew_1", POWER, "energy_q_tracking")
	_answer(s, &"crew_1", POWER, "energy_q_diagnose")
	var r := _do(s, &"crew_1", &"install_upgrade", POWER, {"upgrade_id": "energy_solar_tracking"})
	_do(s, &"crew_1", &"exercise", GYM)
	g.session.advance(1.0)
	var before := {"knowledge": st.knowledge.duplicate(true), "evidence": st.evidence.duplicate(true), "progress": st.progress.duplicate(true),
		"upgrades": st.upgrades.duplicate(true), "parts": st.parts, "battery_cap": float(st.capacities[&"battery_kwh"])}
	var saved := g.save_now(&"manual")
	# lose everything in memory; only the save file can bring it back
	st.knowledge.clear()
	st.evidence.clear()
	st.upgrades.clear()
	st.progress.clear()
	st.parts = 0
	var fresh_empty := g.state().knowledge.is_empty() and g.state().upgrades.is_empty()
	var loaded := g.continue_game()
	var st2 := g.state()
	var same := _same(st2.knowledge, before.knowledge) and _same(st2.evidence, before.evidence) and _same(st2.progress, before.progress) \
		and _same(st2.upgrades, before.upgrades) and st2.parts == int(before.parts)
	_check("save/load: knowledge, evidence, tiers, quiz versions, conditioning and upgrades come back the same",
		r.ok and saved == OK and fresh_empty and loaded.is_usable() and same and ProgressionSystem.tier(st2, "energy") == 2
		and int(ProgressionSystem.progress_of(st2).tiers.energy) == 2 and st2.has_upgrade("energy_solar_tracking")
		and ProgressionSystem.conditioning(st2, &"crew_1") > 0.0, "install %s, saved %s, loaded %s" % [r.reason, saved, loaded.status])
	# after loading, repeating answers and installs still adds nothing
	_add_stand_ins(st2.stations)
	var again := _answer(g.session, &"crew_1", POWER, "energy_q_tracking")
	var inst := _do(g.session, &"crew_1", &"install_upgrade", POWER, {"upgrade_id": "energy_solar_tracking"})
	_check("save/load: after loading, a repeated answer and install change nothing", again.ok and bool(again.changes.already_known) and inst.ok
		and bool(inst.changes.already_installed) and st2.parts == int(before.parts))
	g.saves.delete_all()
	g.queue_free()
	await process_frame


# ================================================================ panels

func _test_panels() -> void:
	var g := GameServices.new()
	g.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/wG"), "colony", 2)
	root.add_child(g)
	g.start_new_game(7)
	await process_frame
	g.set_process(false)
	var st := g.state()
	_add_stand_ins(st.stations)
	var me := g.local_character()
	me.position = CharacterState._v3(st.stations[String(COMPUTER)].position)

	var up := UpgradeCardsPanel.new()
	up.setup(g)
	root.add_child(up)
	up.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	up.refresh()
	var sectors_ok := true
	for sector in ProgressionSystem.SECTORS:
		sectors_ok = sectors_ok and up.sector_text(sector).contains("level 0 of 3") and up.find_child("Sector_" + sector, true, false) != null
	var lines := up.requirement_lines(&"energy_solar_tracking")
	var locked_ok := up.install_button(&"energy_solar_tracking").disabled and up.reason_label(&"energy_solar_tracking").text == "Answer 2 questions"
	var n_cards := 16 + CommsStage.CARD_IDS.size()       # Prompt 11 added the four radio cards (energy sector)
	_check("cards panel: %d cards grouped in 5 sectors with the sector level" % n_cards, up.definitions.size() == n_cards and up.install_buttons.size() == n_cards and sectors_ok,
		"%d cards, %s" % [up.definitions.size(), up.sector_text("energy")])
	_check("cards panel: each requirement is shown with ✖/✓ and words (level, questions, evidence, parts, installer, station)",
		lines.size() == 7 and lines[0].begins_with("✖ Energy level 1 needed") and lines[1].begins_with("✖ Answer: ") and lines[3].begins_with("✖ Do: ")
		and lines[4].contains("Needs 2 parts — the colony has 10") and lines[4].begins_with("✓") and lines[5].begins_with("✓ Installed by: ⚡")
		and lines[6].begins_with("✖ Install at: the power panel") and locked_ok, "\n  ".join(lines))

	# make two energy cards eligible: they are listed together, the Install button needs the right person at the station
	var s := g.session
	_evidence(s, "energy_diagnose_output_loss")
	_evidence(s, "energy_predict_net_power")
	for q in ["energy_q_dust_output", "energy_q_tracking", "energy_q_battery_night", "energy_q_net_power"]:
		_know(st, q)
	up.refresh()
	var ready := up.ready_text("energy")
	_check("cards panel: eligible cards are shown together so players can choose", ready.contains("Better sun tracking") and ready.contains("Battery reserve for life support")
		and up.sector_text("energy").contains("level 1 of 3"), ready)
	var at_computer := up.install_button(&"energy_solar_tracking").disabled and up.reason_label(&"energy_solar_tracking").text.contains("Go to the power panel")
	me.position = CharacterState._v3(st.stations[String(POWER)].position)
	up.refresh()
	var at_station := not up.install_button(&"energy_solar_tracking").disabled and up.install_button(&"energy_solar_tracking").text == "Upgrade"
	_check("cards panel: Install is enabled only at the install station (disabled at the computer, with the reason)", at_computer and at_station,
		up.reason_label(&"energy_solar_tracking").text)
	# the wrong installer at the right station
	me.position = g.config.hub_position
	g.request(&"claim_character", &"crew_2")
	var med := g.local_character()
	med.position = CharacterState._v3(st.stations[String(POWER)].position)
	up.refresh()
	var wrong_person := up.install_button(&"energy_solar_tracking").disabled and up.reason_label(&"energy_solar_tracking").text.contains("Electrical and comms specialist")
	med.position = g.config.hub_position
	g.request(&"claim_character", &"crew_1")
	me = g.local_character()
	me.position = CharacterState._v3(st.stations[String(POWER)].position)
	up.refresh()
	var parts := st.parts
	up.install_button(&"energy_solar_tracking").pressed.emit()
	_check("cards panel: wrong installer keeps Install disabled; pressing Install with the right one installs the card once",
		wrong_person and st.has_upgrade("energy_solar_tracking") and st.parts == parts - 2 and up.install_button(&"energy_solar_tracking").disabled
		and up.install_button(&"energy_solar_tracking").text.contains("Installed") and up.message_text().contains("installed"), up.message_text())

	# the quiz: wrong answer -> explanation and a new version; right -> known
	var quiz := QuizPanel.new()
	quiz.question_ids = [&"energy_q_cleaner", &"ls_q_tank_vs_cabin"]
	quiz.setup(g)
	root.add_child(quiz)
	await process_frame
	quiz.refresh()
	var before_text := quiz.question_text(&"energy_q_cleaner")
	var health := me.health
	quiz.answer(&"energy_q_cleaner", _wrong(st, "energy_q_cleaner"))
	var fb := quiz.feedback_text(&"energy_q_cleaner")
	var changed := quiz.question_text(&"energy_q_cleaner") != before_text
	quiz.answer(&"energy_q_cleaner", _right(st, "energy_q_cleaner"))
	_check("quiz panel: a wrong answer shows the explanation and a changed version; a right one marks it known; no health change",
		fb.begins_with("✖ Not quite.") and changed and quiz.status_text(&"energy_q_cleaner").begins_with("✓") and st.knowledge.has("energy_q_cleaner")
		and quiz.feedback_text(&"energy_q_cleaner").begins_with("✓ Right!") and me.health == health, "%s | %s" % [fb, quiz.status_text(&"energy_q_cleaner")])
	var buttons: Array = quiz.answer_buttons[&"ls_q_tank_vs_cabin"]
	_check("quiz panel: away from its station the answers are disabled and it says where to go", (buttons[0] as Button).disabled
		and quiz.answer_station(&"ls_q_tank_vs_cabin") == &"" and quiz.place_text(&"ls_q_tank_vs_cabin").contains("life support console"),
		quiz.place_text(&"ls_q_tank_vs_cabin"))
	me.position = CharacterState._v3(st.stations[String(LS)].position)
	quiz.refresh()
	_check("quiz panel: the tank-or-cabin question shows the live readings at the life-support console", quiz.answer_station(&"ls_q_tank_vs_cabin") == LS
		and not (buttons[0] as Button).disabled and quiz.readings_text(&"ls_q_tank_vs_cabin").contains("oxygen reserve %s kg" % StationPanel.num(st.store(&"oxygen_kg"))),
		quiz.readings_text(&"ls_q_tank_vs_cabin"))
	quiz.queue_free()
	up.queue_free()
	await process_frame

	# computer opens the cards panel; card Questions opens a quiz
	var comp := StationPanels.for_station(COMPUTER, g) as StationPanel
	root.add_child(comp)
	await process_frame
	var opened: Array[UiPanel] = []
	comp.open_requested.connect(func(p: UiPanel) -> void: opened.append(p))
	(comp.computer_buttons["upgrades"] as Button).pressed.emit()
	var cards := opened[0] as UpgradeCardsPanel if not opened.is_empty() else null
	var quiz_opened := false
	if cards != null:
		cards.setup(g)
		cards.open_requested.connect(func(p: UiPanel) -> void: opened.append(p))
		(cards.question_buttons[&"ls_electrolysis"] as Button).pressed.emit()
		quiz_opened = opened.size() == 2 and opened[1] is QuizPanel and (opened[1] as QuizPanel).question_ids.size() == 2
	_check("panels: the colony computer opens the cards, a card's Questions button opens its quiz", cards != null and quiz_opened, str(opened))
	for p in opened:
		p.free()
	comp.queue_free()
	await process_frame

	# layout at three sizes: cards, quiz, gym
	me.position = CharacterState._v3(st.stations[String(GYM)].position)
	# Built the way StationPanels.for_station builds a custom panel (its `match` currently replaces custom panels with
	# the plain StationPanel, see the report), so the gym panel itself is tested here.
	var gym := (load("res://scripts/ui/stations/gym_station_panel.gd") as Script).new() as StationPanel
	gym.station_id = GYM
	gym.kind = "gym"
	gym.set_meta(&"station_surface", true)
	gym.set_meta(&"station_id", GYM)
	gym.setup(g)
	var gym_ok := gym != null and gym is StationPanel and gym.find_child("Exercise", true, false) is Button
	var gym_detail := "panel %s" % gym
	if gym_ok:
		var bat := st.store(&"battery_kwh")
		var fit := ProgressionSystem.conditioning(st, me.id)
		(gym.find_child("Exercise", true, false) as Button).pressed.emit()
		gym_ok = ProgressionSystem.conditioning(st, me.id) > fit and st.store(&"battery_kwh") == bat and (gym as StationPanel).cause_text().contains("not colony electricity")
		gym_detail = "fitness %.2f -> %.2f, cause '%s', message '%s'" % [fit, ProgressionSystem.conditioning(st, me.id), (gym as StationPanel).cause_text(), (gym as StationPanel).message_text()]
	_check("gym panel: the Exercise button asks the host; fitness goes up, the battery does not move", gym_ok, gym_detail)
	var panels: Array[UiPanel] = []
	var c2 := UpgradeCardsPanel.new()
	c2.setup(g)
	panels.append(c2)
	var q2 := QuizPanel.for_card(ProgressionSystem.card(&"ls_oxygen_monitoring"))
	q2.setup(g)
	panels.append(q2)
	if gym != null:
		panels.append(gym)
	var stretch := root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	for panel in panels:
		if panel.get_parent() == null:
			root.add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var layout := PackedStringArray()
		var focus := PackedStringArray()
		for size: Array in SIZES:
			root.size = size[0]
			_apply_text_scale(float(size[1]))
			await process_frame
			await process_frame
			panel.refresh()
			await process_frame
			for line in UiLayoutCheck.problems(panel, Vector2(size[0])):
				layout.append("%s at %s text %s: %s" % [panel.name, size[0], size[1], line])
			var min_size := panel.get_combined_minimum_size()
			if min_size.x > float(size[0].x) or min_size.y > float(size[0].y):
				layout.append("%s at %s text %s: minimum size %s is bigger than the screen" % [panel.name, size[0], size[1], min_size])
			for line in UiLayoutCheck.focus_problems(panel):
				focus.append("%s at %s text %s: %s" % [panel.name, size[0], size[1], line])
		_apply_text_scale(1.0)
		_check("layout %s (%s) at 1280x720, 1920x1080 and text 1.5" % [panel.name, panel.panel_title()], layout.is_empty(), "\n  ".join(layout))
		_check("focus %s (%s)" % [panel.name, panel.panel_title()], focus.is_empty() and not UiLayoutCheck.focusable(panel).is_empty(), "\n  ".join(focus))
		panel.queue_free()
		await process_frame
	root.content_scale_mode = stretch
	g.saves.delete_all()
	g.queue_free()
	await process_frame


## Applies a text scale (with the same fallback as the other UI tests if UiTheme.apply_text_scale is a stub).
func _apply_text_scale(s: float) -> void:
	UiTheme.apply_text_scale(s)
	var t := UiTheme.get_theme()
	var wanted := roundi(UiTheme.BASE_FONT_SIZE * s)
	if s != 1.0 and t.default_font_size == UiTheme.BASE_FONT_SIZE:
		if not _noted_stub_scale:
			print("NOTE UiTheme.apply_text_scale is the stub: the test sets the theme's default font size to %d itself" % wanted)
			_noted_stub_scale = true
		t.default_font_size = wanted
	elif s == 1.0 and _noted_stub_scale:
		t.default_font_size = UiTheme.BASE_FONT_SIZE
