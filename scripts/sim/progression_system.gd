class_name ProgressionSystem
extends RefCounted
## Upgrades, knowledge and learning (Prompt 08, part G). Two halves:
##   * static helpers on ColonyState that the actions and the panels share: the card catalogue (data/upgrades.json),
##     the questions (data/questions.json), sector tiers, which question version is shown, and what a card still needs.
##   * `step()`, run every tick by ColonySim.post_systems: it watches the energy and life-support model for practical
##     evidence, runs the automation upgrades, adds the conditioning bonus to body energy and updates the sector tiers.
##
## Colony progress lives in plain data (saved and sent to clients as is):
##   state.knowledge[question_id] = {"by", "sector", "at_hours", "variant", "example"}      (answered right, once)
##   state.evidence[evidence_id]  = see ProgressEvidence                                    (recorded once)
##   state.upgrades[card_id]      = {"installed": true, "by", "at_hours", "parts", "station", "sector"}
##   state.progress = {"tiers": {sector: 0..3}, "quiz": {question_id: {"variant", "tries", "wrong"}},
##                     "watch": {...model observations...}, "automation": {...}, "conditioning": {character_id: 0..1}}
## Tier rule: tier 1 = guided task done and its explanation question answered; tier 2 = a diagnosis question answered
## in a changed example (a different situation from the one the guided question was answered in) plus the sector's
## next evidence; tier 3 = a transfer or controlled comparison. Tiers never go down.

const SECTORS: Array[String] = ["energy", "life_support", "food", "resources", "science"]
const UPGRADES_PATH := "res://data/upgrades.json"
const QUESTIONS_PATH := "res://data/questions.json"
const MAX_TIER := 3
## Actions whose actor is remembered so evidence seen in the model can name who did it.
const WATCHED_ACTIONS: Array[String] = ["clean_panel", "repair_cleaner", "set_equipment", "set_water_allocation"]

static var _catalogue: Dictionary = {}
static var _cards: Array[UpgradeDefinition] = []
static var _questions: Dictionary = {}

## Action id -> peer that last did it (set from events.action_resolved; host only, never saved).
var _recent := {}
var _events: GameEvents


# ================================================================ catalogue

## Re-reads both data files (tests and tools).
static func reload() -> void:
	_catalogue = {}
	_cards = []
	_questions = {}


## The parsed data/upgrades.json.
static func catalogue() -> Dictionary:
	if _catalogue.is_empty():
		var text := FileAccess.get_file_as_string(UPGRADES_PATH)
		var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
		if data is Dictionary:
			_catalogue = data
		else:
			push_warning("Upgrade cards could not be read from %s." % UPGRADES_PATH)
			_catalogue = {"cards": [], "sectors": {}, "evidence": {}}
	return _catalogue


## Every card, in file order. Parts costs come from ProgressionBalance when it lists the card.
static func cards() -> Array[UpgradeDefinition]:
	if _cards.is_empty():
		var pb := ProgressionBalance.shared()
		for c: Dictionary in catalogue().get("cards", []):
			_cards.append(UpgradeDefinition.from_dict(c, pb.parts_for(String(c.get("id", "")))))
	return _cards


static func card(id: StringName) -> UpgradeDefinition:
	for c in cards():
		if c.id == id:
			return c
	return null


static func cards_of(sector: String) -> Array[UpgradeDefinition]:
	var out: Array[UpgradeDefinition] = []
	for c in cards():
		if c.sector == sector:
			out.append(c)
	return out


## {"name", "symbol", "installer", "tiers": [...]} of a sector.
static func sector_info(sector: String) -> Dictionary:
	return (catalogue().get("sectors", {}) as Dictionary).get(sector, {}) as Dictionary


static func sector_name(sector: String) -> String:
	return String(sector_info(sector).get("name", sector))


static func sector_symbol(sector: String) -> String:
	return String(sector_info(sector).get("symbol", "●"))


## What an evidence id asks the players to do, in words.
static func evidence_words(id: StringName) -> String:
	var e: Dictionary = (catalogue().get("evidence", {}) as Dictionary).get(String(id), {})
	return String(e.get("words", String(id)))


## Every question by id.
static func questions() -> Dictionary:
	if _questions.is_empty():
		var text := FileAccess.get_file_as_string(QUESTIONS_PATH)
		var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
		if data is Dictionary:
			for q: Dictionary in (data as Dictionary).get("questions", []):
				_questions[String(q.get("id", ""))] = q
		else:
			push_warning("Questions could not be read from %s." % QUESTIONS_PATH)
	return _questions


static func question(id: StringName) -> Dictionary:
	return questions().get(String(id), {}) as Dictionary


static func question_title(id: StringName) -> String:
	return String(question(id).get("title", String(id)))


# ================================================================ progress data

## state.progress with every key present (it may come from an older save or a client copy).
static func progress_of(state: ColonyState) -> Dictionary:
	var p := state.progress
	for key: String in ["tiers", "quiz", "watch", "automation", "conditioning"]:
		if not p.get(key, null) is Dictionary:
			p[key] = {}
	return p


static func is_known(state: ColonyState, question_id: StringName) -> bool:
	return state.knowledge.has(String(question_id))


static func is_installed(state: ColonyState, id: StringName) -> bool:
	return state.has_upgrade(String(id))


## Conditioning of a crew member, 0..ProgressionBalance.conditioning_max.
static func conditioning(state: ColonyState, character_id: StringName) -> float:
	return float((progress_of(state)["conditioning"] as Dictionary).get(String(character_id), 0.0))


## Share of the clean output the panels can give now: mean of (1 - dust) over the 12 trackers.
static func clean_share(state: ColonyState) -> float:
	var total := 0.0
	for d: Variant in state.panel_dust:
		total += 1.0 - clampf(float(d), 0.0, 1.0)
	return total / float(maxi(1, state.panel_dust.size()))


# ================================================================ tiers

## The sector tier the colony has: the stored tier, or more if the evidence and knowledge already reach higher.
static func tier(state: ColonyState, sector: String) -> int:
	return maxi(int((progress_of(state)["tiers"] as Dictionary).get(sector, 0)), compute_tier(state, sector))


## Tier reached by the knowledge and evidence alone (each tier needs the one before).
static func compute_tier(state: ColonyState, sector: String) -> int:
	var reached := 0
	for rule: Dictionary in sector_info(sector).get("tiers", []):
		if int(rule.get("tier", 0)) != reached + 1 or not tier_rule_met(state, rule):
			break
		reached += 1
	return reached


static func tier_rule_met(state: ColonyState, rule: Dictionary) -> bool:
	for line in tier_rule_lines(state, rule):
		if not bool(line.ok):
			return false
	return true


## What one tier rule needs, as [{"kind", "id", "ok", "text"}].
static func tier_rule_lines(state: ColonyState, rule: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q in rule.get("questions", []):
		out.append({"kind": "question", "id": String(q), "ok": is_known(state, StringName(q)), "text": "Answer: " + question_title(StringName(q))})
	var d := String(rule.get("diagnosis", ""))
	if d != "":
		out.append({"kind": "diagnosis", "id": d, "ok": diagnosis_changed(state, StringName(d)),
			"text": "Diagnose a changed example: " + question_title(StringName(d))})
	for e in rule.get("evidence", []):
		out.append({"kind": "evidence", "id": String(e), "ok": ProgressEvidence.has(state, StringName(e)), "text": "Do: " + evidence_words(StringName(e))})
	return out


## The rule of `level` in a sector, or {}.
static func tier_rule(sector: String, level: int) -> Dictionary:
	for rule: Dictionary in sector_info(sector).get("tiers", []):
		if int(rule.get("tier", 0)) == level:
			return rule
	return {}


## True when diagnosis question `id` was answered right in a different example from its guided question.
static func diagnosis_changed(state: ColonyState, id: StringName) -> bool:
	var guided := String(question(id).get("changed_from", ""))
	if not is_known(state, id) or guided == "" or not is_known(state, StringName(guided)):
		return false
	var mine := String((state.knowledge[String(id)] as Dictionary).get("example", ""))
	var theirs := String((state.knowledge[guided] as Dictionary).get("example", ""))
	return mine != "" and mine != theirs


## Stores any higher tier reached. Returns the sectors whose tier went up.
static func update_tiers(state: ColonyState, events: GameEvents) -> PackedStringArray:
	var tiers: Dictionary = progress_of(state)["tiers"]
	var raised := PackedStringArray()
	for sector in SECTORS:
		var now := compute_tier(state, sector)
		if now > int(tiers.get(sector, 0)):
			tiers[sector] = now
			raised.append(sector)
			if events != null:
				events.upgrade_eligibility_changed.emit(StringName("tier_" + sector))
				events.system_alert.emit(StringName("tier_" + sector), &"info",
					"%s %s level %d reached: new upgrade cards may be ready." % [sector_symbol(sector), sector_name(sector), now])
	return raised


# ================================================================ questions

## Index of the question version the host shows now. A wrong answer moves to the next version (a retry variant).
## A diagnosis question never shows the example its guided question was answered in.
static func current_variant_index(state: ColonyState, question_id: StringName) -> int:
	var q := question(question_id)
	var variants: Array = q.get("variants", [])
	if variants.is_empty():
		return -1
	var rec: Dictionary = (progress_of(state)["quiz"] as Dictionary).get(String(question_id), {})
	var index := int(rec.get("variant", 0)) % variants.size()
	if String(q.get("role", "")) == "diagnosis":
		var avoid := _guided_example(state, q)
		for i in variants.size():
			var candidate := (index + i) % variants.size()
			if avoid == "" or String((variants[candidate] as Dictionary).get("example", "")) != avoid:
				return candidate
	return index


static func current_variant(state: ColonyState, question_id: StringName) -> Dictionary:
	var i := current_variant_index(state, question_id)
	return (question(question_id).get("variants", []) as Array)[i] if i >= 0 else {}


## The example the guided question of `q` was answered in, or "".
static func _guided_example(state: ColonyState, q: Dictionary) -> String:
	var guided := String(q.get("changed_from", ""))
	if guided == "" or not is_known(state, StringName(guided)):
		return ""
	return String((state.knowledge[guided] as Dictionary).get("example", ""))


## True if question `q` may be answered at `station_id`: a question that records evidence at a station kind only
## there; otherwise the colony computer or an install station of the question's sector.
static func answer_station_ok(state: ColonyState, q: Dictionary, station_id: StringName) -> bool:
	var st: Dictionary = state.stations.get(String(station_id), {})
	if st.is_empty() or q.is_empty():
		return false
	var kind := String(st.get("kind", ""))
	var only := String(q.get("answer_at_kind", ""))
	if only != "":
		return kind == only
	if kind == "computer":
		return true
	for c in cards_of(String(q.get("sector", ""))):
		if at_install_station(state, c, station_id):
			return true
	return false


## Where a question can be answered, in words.
static func answer_place_words(q: Dictionary) -> String:
	var only := String(q.get("answer_at_kind", ""))
	if only != "":
		return "the %s" % StationPanels.name_of(only).to_lower()
	var names := PackedStringArray(["the colony computer"])
	for c in cards_of(String(q.get("sector", ""))):
		var n := "the %s" % install_place_words(c)
		if not names.has(n):
			names.append(n)
	return " or ".join(names)


# ================================================================ cards

## True if `station_id` is the card's install station (by id, or by the kind another part gives that station).
static func at_install_station(state: ColonyState, c: UpgradeDefinition, station_id: StringName) -> bool:
	if c == null or not state.stations.has(String(station_id)):
		return false
	if station_id == c.install_station:
		return true
	var kind := String((state.stations[String(station_id)] as Dictionary).get("kind", ""))
	return (c.install_kind != "" and kind == c.install_kind) or (kind != "" and c.also_install_kinds.has(kind))


## The install station in words ("power panel in the Power Room").
static func install_place_words(c: UpgradeDefinition) -> String:
	var kind := c.install_kind
	var words := "%s in the %s" % [StationPanels.name_of(kind).to_lower() if kind != "" else String(c.install_station), c.zone]
	if c.also_install_kinds.has("solar"):
		words += " or at any sun tracker outside"
	return words


## Everything a card needs before it can be installed (not counting who installs it and where), in order:
## [{"kind": "installed"|"tier"|"question"|"evidence"|"parts"|"prerequisite", "id", "ok", "text"}].
static func requirements(state: ColonyState, c: UpgradeDefinition) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var have := tier(state, c.sector)
	var sname := sector_name(c.sector)
	out.append({"kind": "tier", "id": c.sector, "ok": have >= c.tier,
		"text": "%s level %d needed — the colony is at level %d" % [sname, c.tier, have] if have < c.tier else "%s level %d reached" % [sname, c.tier]})
	for q in c.questions:
		out.append({"kind": "question", "id": String(q), "ok": is_known(state, q), "text": "Answer: " + question_title(q)})
	for e in c.evidence:
		out.append({"kind": "evidence", "id": String(e), "ok": ProgressEvidence.has(state, e), "text": "Do: " + evidence_words(e)})
	for p in c.prerequisites:
		var other := card(p)
		out.append({"kind": "prerequisite", "id": String(p), "ok": is_installed(state, p), "text": "First install: " + (other.title if other != null else String(p))})
	out.append({"kind": "parts", "id": "parts", "ok": state.parts >= c.cost_parts, "text": "Needs %d parts — the colony has %d" % [c.cost_parts, state.parts]})
	return out


## The requirements not met yet.
static func missing(state: ColonyState, c: UpgradeDefinition) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in requirements(state, c):
		if not bool(r.ok):
			out.append(r)
	return out


## True when the colony has everything the card needs; the right specialist only has to install it at its station.
static func is_eligible(state: ColonyState, c: UpgradeDefinition) -> bool:
	return c != null and not is_installed(state, c.id) and missing(state, c).is_empty()


## The specialist that installs a card, in words.
static func installer_words(c: UpgradeDefinition) -> String:
	if c.specialty == &"":
		return "anyone"
	return "%s %s specialist" % [String(StationPanels.SPECIALTY_SYMBOLS.get(c.specialty, "●")),
		String(StationPanels.SPECIALTY_WORDS.get(c.specialty, String(c.specialty)))]


# ================================================================ tick

func step(state: ColonyState, balance: GameBalance, phase: float, dt_hours: float, events: GameEvents) -> void:
	if dt_hours <= 0.0:
		return
	_listen(events)
	var pb := ProgressionBalance.shared()
	var p := progress_of(state)
	var w: Dictionary = p["watch"]
	if w.has("share"):
		_watch_energy(state, balance, pb, w, phase, dt_hours, events)
	_watch_life_support(state, balance, pb, w, dt_hours, events)
	_automation(state, balance, pb, p["automation"], dt_hours, events)
	_body_energy(state, pb, dt_hours)
	update_tiers(state, events)
	w["share"] = clean_share(state)
	w["dust"] = state.panel_dust.duplicate()
	w["cleaner_ok"] = state.condition_of("cleaner") >= balance.equipment_min_condition


func _listen(events: GameEvents) -> void:
	if events == null or events == _events:
		return
	if _events != null and is_instance_valid(_events) and _events.action_resolved.is_connected(_on_action_resolved):
		_events.action_resolved.disconnect(_on_action_resolved)
	_events = events
	events.action_resolved.connect(_on_action_resolved)


func _on_action_resolved(result: ActionResult) -> void:
	if result.ok and not result.duplicate:
		var action := String(result.changes.get("action", ""))
		if WATCHED_ACTIONS.has(action):
			_recent[action] = result.peer


## The crew member who last did `action`, else the first active crew member, else "".
func _actor(state: ColonyState, action: String) -> StringName:
	var c: CharacterState = null
	if _recent.has(action):
		c = state.character_of_peer(int(_recent[action]))
	if c == null:
		var crew := state.active_characters()
		if not crew.is_empty():
			c = crew[0]
	return c.id if c != null else &""


## energy_diagnose_output_loss: a panel cleaned or the cleaner repaired while the panels gave < 80 % of clean output.
## energy_verify_recovery: output back above 95 % within a sol of such a fix.
func _watch_energy(state: ColonyState, balance: GameBalance, pb: ProgressionBalance, w: Dictionary, phase: float, dt: float, events: GameEvents) -> void:
	var share := clean_share(state)
	var auto_wipe := PowerModel.cleaner_working(state, balance) and PowerModel.crosses_sunrise(phase, dt)
	var cleaned := false
	var before: Array = w.get("dust", [])
	if not auto_wipe and before.size() == state.panel_dust.size():
		for i in before.size():
			if float(state.panel_dust[i]) < float(before[i]) - 1e-9:
				cleaned = true
	var repaired := not bool(w.get("cleaner_ok", true)) and state.condition_of("cleaner") >= balance.equipment_min_condition
	var share_before := float(w.get("share", 1.0))
	if (cleaned or repaired) and share_before < pb.low_output_share:
		var fix := "repair_cleaner" if repaired else "clean_panel"
		ProgressEvidence.record(state, events, &"energy_diagnose_output_loss", "energy", _actor(state, fix),
			{"fix": fix, "output_share_before": share_before})
		w["fix_at"] = state.sim_hours
	var fix_at := float(w.get("fix_at", -1.0))
	if fix_at >= 0.0:
		if share > pb.recovered_output_share:
			ProgressEvidence.record(state, events, &"energy_verify_recovery", "energy", _actor(state, "clean_panel"),
				{"output_share": share, "hours_after_fix": state.sim_hours + dt - fix_at})
			w["fix_at"] = -1.0
		elif state.sim_hours + dt - fix_at > pb.recovery_window_sols * GameConfig.SOL_HOURS:
			w["fix_at"] = -1.0


## ls_distinguish_inputs: both oxygen makers ran an hour each. ls_co2_removal: cabin CO2 back below the warning level.
func _watch_life_support(state: ColonyState, balance: GameBalance, pb: ProgressionBalance, w: Dictionary, dt: float, events: GameEvents) -> void:
	var e_status := String(state.oxygen_process.get("electrolyser", "off"))
	if (e_status == "running" or e_status == "feed_short") and state.is_powered("electrolyser"):
		w["electrolyser_hours"] = float(w.get("electrolyser_hours", 0.0)) + dt
	if String(state.oxygen_process.get("co2_unit", "off")) == "running" and state.is_powered("co2_unit"):
		w["co2_unit_hours"] = float(w.get("co2_unit_hours", 0.0)) + dt
	if float(w.get("electrolyser_hours", 0.0)) >= pb.process_run_hours - 1e-9 and float(w.get("co2_unit_hours", 0.0)) >= pb.process_run_hours - 1e-9:
		ProgressEvidence.record(state, events, &"ls_distinguish_inputs", "life_support", _actor(state, "set_equipment"),
			{"electrolyser_hours": w.electrolyser_hours, "co2_unit_hours": w.co2_unit_hours})
	if state.cabin_co2_kpa >= balance.co2_warn_kpa:
		w["co2_high"] = true
		w["co2_peak_kpa"] = maxf(float(w.get("co2_peak_kpa", 0.0)), state.cabin_co2_kpa)
	elif bool(w.get("co2_high", false)):
		ProgressEvidence.record(state, events, &"ls_co2_removal", "life_support", _actor(state, "set_equipment"),
			{"peak_kpa": float(w.get("co2_peak_kpa", 0.0)), "now_kpa": state.cabin_co2_kpa})
		w["co2_high"] = false
		w["co2_peak_kpa"] = 0.0


## energy_cleaner_automation: a broken cleaner repairs itself after a sol. Nothing here ever breaks equipment.
func _automation(state: ColonyState, balance: GameBalance, pb: ProgressionBalance, a: Dictionary, dt: float, events: GameEvents) -> void:
	if not state.has_upgrade("energy_cleaner_automation"):
		return
	if state.condition_of("cleaner") >= balance.equipment_min_condition:
		a.erase("cleaner_broken_at")
		return
	if not a.has("cleaner_broken_at"):
		a["cleaner_broken_at"] = state.sim_hours
	if state.sim_hours + dt - float(a.cleaner_broken_at) >= pb.cleaner_self_repair_sols * GameConfig.SOL_HOURS - 1e-9:
		(state.equipment["cleaner"] as Dictionary)["condition"] = 1.0
		a.erase("cleaner_broken_at")
		a["cleaner_self_repairs"] = int(a.get("cleaner_self_repairs", 0)) + 1
		if events != null:
			events.system_alert.emit(&"cleaner_self_repair", &"info", "The panel cleaner repaired itself (self-repairing cleaner upgrade). It will wipe the panels at sunrise.")


## Conditioning makes body energy (stamina) come back a little faster. It never touches colony electricity.
func _body_energy(state: ColonyState, pb: ProgressionBalance, dt: float) -> void:
	for c in state.active_characters():
		var k := conditioning(state, c.id)
		if k > 0.0 and c.stamina < 100.0:
			c.stamina = minf(100.0, c.stamina + k * pb.conditioning_recovery_per_hour * dt)
