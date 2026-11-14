extends SceneTree
## Prompt 12: the ten-stage tutorial, the first campaign milestone and the optional first-crew story.
## SYNTHETIC headless checks on the real model and real actions (no scene, no player, no network): crew move by the
## host's own position reports, and every objective is completed by a real action or real colony state. A few set-ups
## are marked "synthetic set-up" where a test jumps straight to the part it is about (for example stage 9 or the
## certification sol); the full solo and four-player runs never do that: even the first radio card is installed with
## real actions (its questions at the comms console, then install_upgrade by the electrical specialist).
## Run: ..\godot.cmd --headless --path . --script res://tests/test_tutorial.gd

const MANIFEST := "res://data/colony_manifest.json"
const SUITS := &"al_suit_rack"
const COMPUTER := &"cm_colony_computer"
const COMMS := &"cm_comms_console"
const POWER := &"pw_panel"
const LS := &"ls_console"
const FOOD := &"gh_console"
const BED := &"gd_planter"
const BED2 := &"gd_planter.001"
const GYM := &"rk_treadmill"
const TRACKER := &"sf_solar_tracker"
const TRACKER2 := &"sf_solar_tracker.001"
const DONOR := &"pr_swgr_burnt"
const SITE := &"site_east_rocks"
const STAGE_TITLES: Array[String] = ["Arrival and movement", "Airlock interaction", "Hub monitoring and crew selection",
	"Solar maintenance", "Energy distribution", "Greenhouse operations", "Personal health and body energy",
	"Communications", "Independent problem: greenhouse power", "Back to the hub, then explore"]
const KINDS: Array[String] = ["moved", "near", "suit_on", "outside", "inside", "at_hub", "specialist_played", "knowledge",
	"action", "suit_topped", "cleaner_ok", "oxygen_makers_on", "greenhouse_water", "comms_stage", "stage9_fixed", "stage9_holds"]
const FORBIDDEN_WORDS: Array[String] = ["alien", "dead", "died", "death", "dying", "body", "bodies", "blood", "corpse", "killed",
	"monster", "remains", "grave", "skeleton", "injured", "wounded"]
const SIZES := [[Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 1.0], [Vector2i(1280, 720), 1.5]]


## Collects engine and script errors raised while the test runs.
class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR or error_type == ERROR_TYPE_SCRIPT:
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


## Stand-in for GameMain in the presentation checks: just the two nodes the presenter looks for.
class FakeGame extends Node:
	var hud: GameHud
	var ui: UiRoot


var _passed := 0
var _total := 0
var _catcher := ErrorCatcher.new()
var _event_nodes: Array[GameEvents] = []
var _zones: ColonyZones
var _catalog: Dictionary
var _notes := PackedStringArray()


func _initialize() -> void:
	OS.add_logger(_catcher)
	PlayerInput.ensure_actions()
	TutorialSystem.reload()
	ProgressionSystem.reload()
	_zones = ColonyZones.from_manifest(MANIFEST)
	_catalog = StationCatalog.from_manifest(MANIFEST, _zones)
	_test_data()
	_test_lore_data()
	_test_sources()
	_test_wrapping()
	_test_solo_run()
	_test_four_players()
	_test_order()
	_test_repeat_and_replay()
	_test_hints_and_mastery()
	_test_stage9_variants()
	_test_certification()
	_test_lore_runtime()
	await _test_presentation()
	for n in _notes:
		print("NOTE " + n)
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


## A host session on the real map with `active` players (peers 1..active), each claiming crew_1..crew_N for real.
func _session(active: int, seed_value := 4242) -> SessionService:
	var ev := GameEvents.new()
	_event_nodes.append(ev)
	var s := SessionService.new(GameConfig.new(), GameBalance.new(), ev)
	var st := ColonyState.new_game(s.balance, seed_value, _zones.names)
	st.stations = _catalog.duplicate(true)
	s.outside_test = func(p: Vector3) -> bool: return _zones.zone_at_world(p) == ColonyZones.EXTERIOR
	var ids: Array = st.characters.keys()
	ids.sort()
	for i in ids.size():
		var c := st.characters[ids[i]] as CharacterState
		var angle := TAU * float(i) / float(ids.size())
		c.hub_spot = s.config.hub_position + Vector3(cos(angle), 0.0, sin(angle)) * 1.2
		c.position = c.hub_spot
	var game_clock := SolClock.new()
	game_clock.phase = s.config.start_phase
	s.begin(st, game_clock)
	for i in range(1, active):
		s.peer_joined(i + 1)
	for i in active:
		var r := s.request(&"claim_character", StringName("crew_%d" % (i + 1)), {}, i + 1)
		if not r.ok:
			push_error("claim failed: %s" % r.message)
	return s


## A second session that continues from `d` (a saved colony, as JSON text would give it back).
func _resume(s: SessionService, d: Dictionary) -> SessionService:
	var ev := GameEvents.new()
	_event_nodes.append(ev)
	var s2 := SessionService.new(GameConfig.new(), GameBalance.new(), ev)
	s2.outside_test = s.outside_test
	var c := SolClock.from_dict(s.clock.to_dict())
	s2.begin(ColonyState.from_dict(d), c)
	for p: int in s.peers:
		s2.peer_joined(p)
	return s2


func _json(st: ColonyState) -> Dictionary:
	return JSON.parse_string(JSON.stringify(st.to_dict()))


func _peer(s: SessionService, crew: StringName) -> int:
	return s.state.character(crew).owner_peer


func _pos(s: SessionService, station: StringName) -> Vector3:
	return CharacterState._v3((s.state.stations[String(station)] as Dictionary).position)


## Moves a crew member by the host's own position report (as the player body does ~20 times a second).
func _go(s: SessionService, crew: StringName, p: Vector3) -> void:
	s.report_position(_peer(s, crew), crew, p, 0.0)


func _do(s: SessionService, crew: StringName, action: StringName, station: StringName, params: Dictionary = {}) -> ActionResult:
	_go(s, crew, _pos(s, station))
	return s.request(action, station, params, _peer(s, crew))


func _answer(s: SessionService, crew: StringName, station: StringName, qid: String) -> ActionResult:
	var choice := int(ProgressionSystem.current_variant(s.state, StringName(qid)).get("correct", 0))
	return _do(s, crew, &"answer_question", station, {"question_id": qid, "choice": choice})


## Real time passes: SessionService.advance in 0.2 s steps (one 5 Hz tick each).
func _tick(s: SessionService, seconds: float) -> void:
	var n := ceili(seconds / 0.2 - 1e-6)
	for i in n:
		s.advance(0.2)


func _game_hours(s: SessionService, hours: float) -> void:
	_tick(s, hours / s.clock.hours_per_real_second())


## Hub switch by the player of `from`: walk to the hub, then claim `to` (real claim_character).
func _switch(s: SessionService, from: StringName, to: StringName) -> ActionResult:
	var peer := _peer(s, from)
	_go(s, from, s.config.hub_position)
	return s.request(&"claim_character", to, {}, peer)


func _stage(s: SessionService) -> int:
	return TutorialSystem.current_stage(s.state)


func _current(s: SessionService) -> String:
	return String(TutorialSystem.current_objective(s.state).get("id", ""))


func _done(s: SessionService, id: String) -> bool:
	return TutorialSystem.is_objective_done(s.state, id)


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


func _words(text: String) -> int:
	var n := 0
	for w in text.split(" ", false):
		if w.strip_edges() != "" and w != "—" and w != "·":
			n += 1
	return n


func _mentions_switch(text: String) -> bool:
	var t := text.to_lower()
	return t.contains("switch at the hub") or t.contains("switch crew") or t.contains("play as") or t.contains("and choose them") \
		or t.contains("choose them on the crew screen") or t.contains("change crew") or t.contains("switch to")


## Installs the first radio card with real actions: answer its questions at the comms console, then install with the
## electrical specialist (the card comes from data/upgrades.json, Prompt 11).
func _install_radio(s: SessionService, elec: StringName) -> bool:
	var c := ProgressionSystem.card(&"comms_radio_1")
	if c == null:
		_notes.append("comms_radio_1 is missing from data/upgrades.json")
		return false
	for q in c.questions:
		_answer(s, elec, COMMS, String(q))
	var r := _do(s, elec, &"install_upgrade", COMMS, {"upgrade_id": "comms_radio_1"})
	if not r.ok:
		_notes.append("comms_radio_1 could not be installed with real actions after stages 1-7: %s (executor: give the card evidence the tutorial earns)" % r.message)
	return r.ok


## Real fix of each stage 9 fault at the power panel, by `crew`.
func _solve_stage9(s: SessionService, crew: StringName) -> bool:
	var st := s.state
	var s9 := TutorialSystem.stage9_of(st)
	var ok := true
	match String(s9.get("variant", "")):
		"greenhouse_breaker":
			ok = _do(s, crew, &"set_zone_power", POWER, {"zone": "Greenhouse", "on": true}).ok
		"trackers_stopped":
			ok = _do(s, crew, &"set_equipment", POWER, {"equipment": "trackers", "on": true}).ok
		"lighting_overload":
			for zone: String in ["Hangar bay", "Dome plaza", "Garden dome", "Exterior", "Command Room", "Mess hall"]:
				if TutorialSystem.room_light_kw(st, s.balance) <= float(s9.limit_kw):
					break
				ok = _do(s, crew, &"set_zone_power", POWER, {"zone": zone, "on": false}).ok and ok
			ok = _do(s, crew, &"set_zone_power", POWER, {"zone": "Greenhouse", "on": true}).ok and ok
	return ok


## Plays the tutorial with one player (crew_1, the electrical specialist) from stage 1 until stage `until` starts.
## With `switches` the player changes crew at the hub where a specialist fits the work (stage 6, 8, 10).
## Returns the requests that were refused, as text (empty: all real actions were accepted).
func _solo_flow(s: SessionService, until: int, switches := false, at_boundary := Callable()) -> PackedStringArray:
	var bad := PackedStringArray()
	var me: StringName = &"crew_1"
	var st := s.state
	_tick(s, 0.4)
	for n in range(1, until):
		if at_boundary.is_valid():
			at_boundary.call(n)
		var r: ActionResult
		match n:
			1:
				_go(s, me, s.state.character(me).position + Vector3(9.0, 0.0, 0.0))
				_tick(s, 0.4)
				_go(s, me, _pos(s, SUITS) + Vector3(0.5, 0.0, 0.0))
			2:
				r = _do(s, me, &"begin_suit_check", SUITS, {"on": true})
				if not r.ok: bad.append("suit: " + r.message)
				_tick(s, 1.4)
				_go(s, me, _pos(s, TRACKER) + Vector3(2.0, 0.0, 0.0))
				s.note_airlock_cycle()
				_tick(s, 0.4)
				_go(s, me, _pos(s, SUITS))
			3:
				_go(s, me, s.config.hub_position)
				_tick(s, 0.4)
				r = _answer(s, me, COMPUTER, "energy_q_battery_night")
				if not r.ok: bad.append("battery question: " + r.message)
			4:
				r = _do(s, me, &"clean_panel", TRACKER)
				if not r.ok: bad.append("clean: " + r.message)
				_tick(s, 0.4)
				r = _do(s, me, &"repair_cleaner", TRACKER)
				if not r.ok: bad.append("repair: " + r.message)
				_tick(s, 0.4)
				r = _answer(s, me, POWER, "energy_q_dust_output")
				if not r.ok: bad.append("dust question: " + r.message)
			5:
				r = _answer(s, me, POWER, "energy_q_net_power")
				if not r.ok: bad.append("net power question: " + r.message)
				_tick(s, 0.4)
				r = _do(s, me, &"set_zone_power", POWER, {"zone": "Hangar bay", "on": false})
				if not r.ok: bad.append("room off: " + r.message)
				_tick(s, 0.4)
				r = _do(s, me, &"set_water_allocation", LS, {"electrolysis_feed_l_per_hour": 1.0})
				if not r.ok: bad.append("feed: " + r.message)
				r = _do(s, me, &"set_equipment", LS, {"equipment": "electrolyser", "on": true})
				if not r.ok: bad.append("electrolyser: " + r.message)
				r = _do(s, me, &"set_equipment", LS, {"equipment": "co2_unit", "on": true})
				if not r.ok: bad.append("co2 unit: " + r.message)
				_tick(s, 0.4)
				r = _answer(s, me, LS, "ls_q_two_paths")
				if not r.ok: bad.append("two paths: " + r.message)
			6:
				if switches:
					r = _switch(s, me, &"crew_3")
					if not r.ok: bad.append("switch to biology: " + r.message)
					me = &"crew_3"
				r = _do(s, me, &"plant", BED, {"crop": "lettuce"})
				if not r.ok: bad.append("plant: " + r.message)
				_tick(s, 0.4)
				r = _do(s, me, &"set_greenhouse_water", FOOD, {"greenhouse_l_per_hour": 1.0})
				if not r.ok: bad.append("greenhouse water: " + r.message)
				_tick(s, 0.4)
				r = _do(s, me, &"inspect_bed", BED)
				if not r.ok: bad.append("inspect: " + r.message)
				_tick(s, 0.4)
				r = _answer(s, me, FOOD, "food_q_light")
				if not r.ok: bad.append("light question: " + r.message)
			7:
				r = _do(s, me, &"exercise", GYM)
				if not r.ok: bad.append("exercise: " + r.message)
				_tick(s, 0.4)
				if st.character(me).suit_charge < 95.0:
					r = _do(s, me, &"refill_suit", SUITS)
					if not r.ok: bad.append("refill: " + r.message)
			8:
				if switches and me != &"crew_1":
					r = _switch(s, me, &"crew_1")
					if not r.ok: bad.append("switch to electrical: " + r.message)
					me = &"crew_1"
				_go(s, me, _pos(s, COMMS))
				_tick(s, 0.4)
				if not _install_radio(s, me): bad.append("radio card")
			9:
				if not _solve_stage9(s, me): bad.append("stage 9 fix")
				_game_hours(s, 1.3)
			10:
				_go(s, me, s.config.hub_position)
				_tick(s, 0.4)
				r = _switch(s, me, &"crew_4")
				if not r.ok: bad.append("switch to field engineer: " + r.message)
				me = &"crew_4"
				_tick(s, 0.4)
				r = _do(s, me, &"inspect_donor", DONOR)
				if not r.ok: bad.append("inspect donor: " + r.message)
		_tick(s, 0.6)
		if _stage(s) != n + 1 and not (n == 10 and TutorialSystem.is_tutorial_done(st)):
			bad.append("stage %d did not finish (stage %d, open: %s)" % [n, _stage(s), _current(s)])
			return bad
	if at_boundary.is_valid():
		at_boundary.call(until)
	return bad


## Synthetic set-up: marks stages 1..n-1 done (as if played) so a test can start at stage n.
func _skip_to(s: SessionService, n: int) -> void:
	var t: Dictionary = TutorialSystem.ensure(s.state).tutorial
	for k in range(1, n):
		for o: Dictionary in TutorialSystem.objectives_of(k):
			(t.objectives as Dictionary)[String(o.id)] = {"done": true, "at_hours": 0.0, "by": "crew_1", "skipped": false}
		(t.completed as Dictionary)[str(k)] = {"at_hours": 0.0}
	t["stage"] = n
	t["started"] = false
	t["current"] = ""


## Synthetic set-up: tier 1 in every sector (questions and evidence recorded directly) and the first radio card.
func _make_sectors_work(s: SessionService) -> void:
	var st := s.state
	for sector: String in ProgressionSystem.SECTORS:
		var rule := ProgressionSystem.tier_rule(sector, 1)
		for q in rule.get("questions", []):
			var v: Dictionary = (ProgressionSystem.question(StringName(q)).variants as Array)[0]
			st.knowledge[String(q)] = {"by": "crew_1", "sector": sector, "at_hours": 0.0, "variant": 0, "example": String(v.example)}
		for e in rule.get("evidence", []):
			ProgressEvidence.record(st, s.events, StringName(e), sector, &"crew_1")
	st.upgrades["comms_radio_1"] = {"installed": true, "by": "crew_1", "at_hours": 0.0, "parts": 1, "station": String(COMMS), "sector": "comms"}


# ================================================================ data

func _test_data() -> void:
	var stages := TutorialSystem.stages()
	var titles: Array[String] = []
	var order_ok := stages.size() == 10
	for i in stages.size():
		order_ok = order_ok and int((stages[i] as Dictionary).n) == i + 1
		titles.append(String((stages[i] as Dictionary).title))
	_check("data: ten stages in the supplied order (arrival, airlock, hub, solar, energy, greenhouse, health, comms, independent problem, hub and exploration)",
		order_ok and titles == STAGE_TITLES, str(titles))
	var ids := {}
	var bad := PackedStringArray()
	var session := _session(1)
	for s: Dictionary in stages:
		if (s.get("teaches", []) as Array).is_empty() or String(s.get("intro", "")) == "":
			bad.append("stage %d: no teaches or intro" % int(s.n))
		if (s.get("objectives", []) as Array).is_empty():
			bad.append("stage %d: no objectives" % int(s.n))
		for o: Dictionary in s.get("objectives", []):
			var id := String(o.get("id", ""))
			if id == "" or ids.has(id):
				bad.append("objective id missing or repeated: %s" % id)
			ids[id] = true
			if not KINDS.has(String(o.get("kind", ""))):
				bad.append("%s: unknown kind %s" % [id, o.get("kind", "")])
			if String(o.get("text", "")) == "" or String(o.get("explain", "")) == "":
				bad.append("%s: text or explanation missing" % id)
			if String(o.kind) != "stage9_fixed" and (o.get("hints", []) as Array).is_empty():
				bad.append("%s: no hints" % id)
			var p: Dictionary = o.get("params", {})
			if p.has("station") and not _catalog.has(String(p.station)):
				bad.append("%s: station %s is not on the map" % [id, p.station])
			if String(o.kind) == "knowledge" and ProgressionSystem.question(StringName(String(p.get("question", "")))).is_empty():
				bad.append("%s: question %s does not exist" % [id, p.get("question", "")])
			for a in p.get("actions", []):
				if session.actions.definition(StringName(String(a))) == null:
					bad.append("%s: action %s is not registered" % [id, a])
			for key in ["specialty", "specialty_hint"]:
				if o.has(key) and not CharacterState.SPECIALTIES.has(StringName(String(o[key]))):
					bad.append("%s: unknown specialty %s" % [id, o[key]])
			# with four players nothing may ask anyone to switch crew
			if _mentions_switch(TutorialSystem.objective_text(o, true)):
				bad.append("%s: the four-player text asks to switch: %s" % [id, TutorialSystem.objective_text(o, true)])
			for h in TutorialSystem.hints_for(session.state, o, true):
				if _mentions_switch(h):
					bad.append("%s: a four-player hint asks to switch: %s" % [id, h])
	_check("data: every objective has a known kind, words, an explanation, hints, real stations, questions and actions; with four players none asks to switch crew",
		bad.is_empty(), "\n  ".join(bad))
	var variants: Dictionary = TutorialSystem.stage9_data().get("variants", {})
	var vbad := PackedStringArray()
	for v: String in TutorialSystem.VARIANTS:
		var vd: Dictionary = variants.get(v, {})
		if String(vd.get("problem", "")) == "" or (vd.get("hints", []) as Array).size() < 2 or String(vd.get("solved", "")) == "":
			vbad.append(v)
	_check("data: three stage 9 variants, each with a problem, at least two hints and a solved line", variants.size() == 3 and vbad.is_empty(), str(vbad))


func _test_lore_data() -> void:
	var recs := TutorialSystem.records()
	var bad := PackedStringArray()
	var longest := 0
	for r: Dictionary in recs:
		var id := String(r.get("id", ""))
		var n := _words(String(r.get("text", "")))
		longest = maxi(longest, n)
		if n > 60 or n < 10:
			bad.append("%s has %d words" % [id, n])
		var station := String(r.get("station", ""))
		var kind := String((_catalog.get(station, {}) as Dictionary).get("kind", ""))
		var via := String(r.get("via", ""))
		if not ((via == "read_record" and kind == "record") or (via == "inspect_donor" and kind == "salvage")):
			bad.append("%s: %s at %s (kind %s)" % [id, via, station, kind])
		if String(r.get("science", "")) == "" or String(r.get("title", "")) == "" or String(r.get("place", "")) == "":
			bad.append("%s: science, title or place missing" % id)
		var low := (String(r.text) + " " + String(r.science)).to_lower()
		for w in FORBIDDEN_WORDS:
			for token in low.replace(".", " ").replace(",", " ").replace(":", " ").split(" ", false):
				if token == w:
					bad.append("%s uses '%s'" % [id, w])
	_check("lore: %d records (8-14), each 10-60 words (longest %d), on an existing damaged object or console of its kind, with science and a place; no graphic or alien words" % [recs.size(), longest],
		recs.size() >= 8 and recs.size() <= 14 and bad.is_empty(), "\n  ".join(bad))
	var used := {}
	var dbad := PackedStringArray()
	for d: Dictionary in TutorialSystem.discovery_defs():
		for clue in d.get("clues", []):
			if TutorialSystem.record_def(String(clue)).is_empty():
				dbad.append("%s: unknown clue %s" % [d.id, clue])
			used[String(clue)] = true
		for need in d.get("requires", []):
			var found := false
			for other: Dictionary in TutorialSystem.discovery_defs():
				found = found or String(other.id) == String(need)
			if not found:
				dbad.append("%s needs unknown %s" % [d.id, need])
		if _words(String(d.get("text", ""))) > 60:
			dbad.append("%s is longer than 60 words" % d.id)
	for r: Dictionary in recs:
		if not used.has(String(r.id)) and String(r.id) != "rec_handover":
			dbad.append("%s is no clue of any discovery" % r.id)
	_check("lore: four discoveries and a final one; every clue exists and every record (except the handover note) is a clue", TutorialSystem.discovery_defs().size() == 5 and dbad.is_empty(), "\n  ".join(dbad))
	var lore := TutorialSystem.lore()
	_check("lore: the premise and the record label say it is fiction, and the premise is hopeful (everyone got home safely)",
		String(lore.get("premise", "")).begins_with("Fiction") and String(lore.get("fiction_label", "")).begins_with("Fiction")
		and String(lore.get("premise", "")).contains("safely"), String(lore.get("premise", "")))
	# record stations: existing map objects, not claimed by any other stations_*.json file
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/stations_lore.json"))
	var objects := {}
	for o: Dictionary in (JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) as Dictionary).objects:
		objects[String(o.name)] = true
	var sbad := PackedStringArray()
	var others := {}
	for entry: Dictionary in StationCatalog.extra_entries():
		if entry.has("object") and String(entry.get("kind", "")) != "record":
			others[String(entry.object)] = true
	for entry: Dictionary in data.stations:
		var name := String(entry.object)
		if not objects.has(name):
			sbad.append("%s is not in the map" % name)
		if others.has(name):
			sbad.append("%s is also a station of another part" % name)
		if String((_catalog.get(name, {}) as Dictionary).get("kind", "")) != "record":
			sbad.append("%s is not a record station" % name)
		if TutorialSystem.records_at(name, "read_record").size() != 1:
			sbad.append("%s holds %d records" % [name, TutorialSystem.records_at(name, "read_record").size()])
	_check("lore: %d record stations on existing map objects, each holding one record, none claimed by another part" % (data.stations as Array).size(), sbad.is_empty(), "\n  ".join(sbad))


func _test_sources() -> void:
	var known := {}
	for path: String in ["res://data/sources.json", "res://data/sources_weather.json"]:
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			for src: Dictionary in (d as Dictionary).get("sources", []):
				known[String(src.get("id", ""))] = String(src.get("status", ""))
	var bad := PackedStringArray()
	for r: Dictionary in TutorialSystem.records():
		for id in r.get("source_ids", []):
			if not known.has(String(id)):
				bad.append("%s cites %s, not in the register" % [r.id, id])
			elif String(known[String(id)]) != "VERIFIED":
				bad.append("%s cites %s (%s), not a verified source" % [r.id, id, known[String(id)]])
		if (r.get("source_ids", []) as Array).is_empty():
			var sci := String(r.science).to_lower()
			if not (sci.contains("game") or sci.contains("principle")):
				bad.append("%s has no source and does not say it is a game rule or a general principle" % r.id)
	_check("sources: every record's source id is a VERIFIED register entry; records without one say they are a game rule or a general principle", bad.is_empty(), "\n  ".join(bad))
	var cats: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/model_sources_campaign.json"))
	var need := ["hint_after_s", "hint_repeat_s", "near_m", "move_m", "stage9.hold_hours", "stage9.lighting_line_room_kw", "certification.sols",
		"objective_params.metres", "objective_params.min_l_per_hour", "objective_params.min_charge", "objective_params.min"]
	var missing := PackedStringArray()
	var allowed := ["requirement", "design", "balance", "fiction", "index"]
	if cats is Dictionary:
		for key: String in need:
			var e: Dictionary = (cats as Dictionary).get(key, {})
			if not allowed.has(String(e.get("category", ""))):
				missing.append(key)
		for key: String in (cats as Dictionary):
			var e: Dictionary = (cats as Dictionary)[key]
			for id in e.get("source_ids", []):
				if not known.has(String(id)):
					missing.append("%s cites unknown %s" % [key, id])
		var data := TutorialSystem.data()
		var values_ok := _approx(float(data.hint_after_s), float((cats as Dictionary).hint_after_s.value)) and _approx(float(data.stage9.lighting_line_room_kw), float((cats as Dictionary)["stage9.lighting_line_room_kw"].value))
		if not values_ok:
			missing.append("values in model_sources_campaign.json differ from data/tutorial.json")
	else:
		missing.append("model_sources_campaign.json unreadable")
	_check("sources: every tutorial and campaign number has a category (requirement, design, balance or fiction) in model_sources_campaign.json", missing.is_empty(), "\n  ".join(missing))


func _test_wrapping() -> void:
	var s := _session(1)
	var missing := TutorialActions.observe_watched(s.actions)
	var all_wrapped := true
	for id: String in TutorialSystem.watched_actions():
		all_wrapped = all_wrapped and TutorialActions.is_observed(s.actions, StringName(id))
	_check("actions: every action the tutorial and story watch is registered and observed (TutorialActions registered last): %s" % ", ".join(TutorialSystem.watched_actions()),
		missing.is_empty() and all_wrapped, "missing %s" % str(missing))
	# a watched action behaves exactly as before: same answer and the same change of the colony
	var a := _session(1)
	var b := _session(1)
	var d := ActionService.Definition.new()
	d.id = &"clean_panel"
	d.target_kind = &"station"
	d.station_kinds = PackedStringArray(["solar"])
	d.check = func(_ctx: ActionService.Context) -> ActionResult: return null
	d.apply = func(ctx: ActionService.Context) -> Dictionary:
		ctx.state.panel_dust[0] = 0.0
		return {"action": "clean_panel", "target": String(ctx.request.target), "text": "Panel 1 is clean: it makes its full power again."}
	b.actions.register(d)               # b: the unwrapped stand-in with the same effect on panel 1
	var ra := _do(a, &"crew_1", &"clean_panel", TRACKER)
	var rb := _do(b, &"crew_1", &"clean_panel", TRACKER)
	_check("actions: a watched action gives the same answer and changes the colony the same way", ra.ok and rb.ok
		and _approx(float(a.state.panel_dust[0]), float(b.state.panel_dust[0])) and String(ra.changes.text) == String(rb.changes.text), "%s / %s" % [ra.changes, rb.changes])


# ================================================================ solo run

func _test_solo_run() -> void:
	var s := _session(1, 4242)
	var st := s.state
	var boundary_bad := PackedStringArray()
	var seen_stages := PackedInt32Array()
	# save/load at every stage boundary: the colony saved as JSON resumes at the same stage and objectives
	var at_boundary := func(n: int) -> void:
		seen_stages.append(n)
		var d := _json(st)
		var copy := ColonyState.from_dict(d)
		if TutorialSystem.current_stage(copy) != _stage(s) or String(TutorialSystem.current_objective(copy).get("id", "")) != _current(s):
			boundary_bad.append("stage %d: saved copy at %d/%s, game at %d/%s" % [n, TutorialSystem.current_stage(copy), TutorialSystem.current_objective(copy).get("id", ""), _stage(s), _current(s)])
		if not _same(copy.campaign, st.campaign):
			boundary_bad.append("stage %d: campaign data changed by save/load" % n)
		var s2 := _resume(s, d)
		var zones_before := s2.state.zones.duplicate(true)
		var trackers_before := s2.state.is_on("trackers")
		_tick(s2, 0.6)
		if TutorialSystem.current_stage(s2.state) != _stage(s) or String(TutorialSystem.current_objective(s2.state).get("id", "")) != _current(s):
			boundary_bad.append("stage %d: resumed game moved to %d/%s" % [n, TutorialSystem.current_stage(s2.state), TutorialSystem.current_objective(s2.state).get("id", "")])
		if n >= 9 and (not _same(zones_before, s2.state.zones) or trackers_before != s2.state.is_on("trackers")):
			boundary_bad.append("stage %d: the resumed game injected the stage 9 fault again" % n)
	var bad := _solo_flow(s, 11, true, at_boundary)
	var t := TutorialSystem.tutorial_of(st)
	var real_switches := 0
	_check("solo: one player completes all ten stages with real actions only, switching crew only at the hub (biology for the greenhouse, electrical for comms, field engineer to explore)",
		bad.is_empty() and TutorialSystem.is_tutorial_done(st) and (t.completed as Dictionary).size() == 10 and s.peers.size() == 1
		and st.character(&"crew_4").owner_peer == 1, "\n  ".join(bad))
	_check("solo: save/load at every stage boundary resumes the same stage and the same objective, without injecting the stage 9 fault twice (%d boundaries)" % seen_stages.size(),
		boundary_bad.is_empty() and seen_stages.size() == 11, "\n  ".join(boundary_bad))
	var who_bad := PackedStringArray()
	for o: Dictionary in TutorialSystem.objectives_of(4) + TutorialSystem.objectives_of(8):
		var rec := TutorialSystem.objective_record(st, String(o.id))
		if not bool(rec.get("done", false)):
			who_bad.append(String(o.id))
	_check("solo: the specialist steps were done (cleaner repaired by the electrical specialist, comms reached by them)", who_bad.is_empty()
		and st.condition_of("cleaner") >= s.balance.equipment_min_condition and String((st.upgrades.get("comms_radio_1", {}) as Dictionary).get("by", "")) == "crew_1", str(who_bad))
	_check("solo: the tutorial earned energy and life-support competence through its own steps (energy tier 1 at stage 4, the life-support answer at stage 5)",
		ProgressionSystem.tier(st, "energy") >= 1 and st.knowledge.has("ls_q_two_paths") and st.evidence.has("energy_diagnose_output_loss"), str(st.progress.get("tiers", {})))
	_check("solo: free exploration reached: tutorial done, certification waiting for the sectors, a first-crew record found on the way",
		String(TutorialSystem.certification_of(st).status) == "waiting" and TutorialSystem.is_found(st, "rec_switchgear"), str(TutorialSystem.certification_of(st)))
	# ---- continuation to the first campaign milestone, still one player, still real actions
	var me: StringName = &"crew_4"
	var log := PackedStringArray()
	var r := _do(s, me, &"adjust_nutrients", BED, {"level": 0.2})
	log.append("nutrients %s" % r.ok)
	_tick(s, 0.4)
	r = _do(s, me, &"inspect_bed", BED)
	log.append("inspect %s" % r.ok)
	r = _answer(s, me, FOOD, "food_q_symptom")
	log.append("symptom %s" % r.ok)
	r = _do(s, me, &"adjust_nutrients", BED, {"level": 0.7})
	r = _do(s, me, &"inspect_donor", DONOR, {"choice": "relay"})
	log.append("donor %s" % r.ok)
	r = _answer(s, me, COMPUTER, "res_q_compatible")
	log.append("res question %s" % r.ok)
	r = _do(s, me, &"begin_suit_check", SUITS, {"on": true})
	_tick(s, 1.4)
	r = _do(s, me, &"take_sample", SITE)
	log.append("sample %s %s" % [r.ok, r.message])
	_go(s, me, _pos(s, SUITS))
	r = _answer(s, me, COMPUTER, "sci_q_context")
	log.append("sci question %s" % r.ok)
	_game_hours(s, 1.2)
	var missing := TutorialSystem.requirements_missing(st)
	_check("solo: after the tutorial one player brings all five sectors to tier 1 with real actions (food symptom, salvage, field sample), and the radio works",
		missing.is_empty(), "%s\n  %s" % [str(missing), ", ".join(log)])
	_tick(s, 0.6)
	var running := String(TutorialSystem.certification_of(st).status) == "running"
	s.request(&"set_sol_minutes", &"", {"minutes": 5.0}, 1)
	var lowest := INF
	for i in 1600:
		s.advance(0.2)
		for k: StringName in TutorialSystem.RESERVES:
			lowest = minf(lowest, st.store(k))
		if String(TutorialSystem.certification_of(st).status) == "complete":
			break
	var cert := TutorialSystem.certification_of(st)
	_check("solo: the certification sol starts after the tutorial and completes after one full sol with every reserve above zero (lowest %.2f)" % lowest,
		running and String(cert.status) == "complete" and lowest > 0.0 and float(cert.completed_at_hours) - float(cert.started_at_hours) >= GameConfig.SOL_HOURS - 0.01,
		str(cert))
	var records_found := 0
	for d: Variant in st.discoveries:
		if d is Dictionary and String((d as Dictionary).get("kind", "")) == "record":
			records_found += 1
	_check("solo: the mystery is optional: the milestone completed with %d of %d records found" % [records_found, TutorialSystem.records().size()],
		records_found < TutorialSystem.records().size())
	# ---- play continues in the same world
	var parts_before := st.parts
	r = _answer(s, me, COMPUTER, "energy_q_tracking")
	var r2 := _do(s, &"crew_4", &"set_equipment", POWER, {"equipment": "cabin_fans", "on": true})
	_game_hours(s, 2.0)
	var d2 := _json(st)
	var s3 := _resume(s, d2)
	_tick(s3, 0.6)
	_check("solo: after the milestone everything keeps working: questions, switches, the simulation, save/load; the milestone stays complete",
		r.ok and r2.ok and st.parts == parts_before and String(TutorialSystem.certification_of(s3.state).status) == "complete"
		and TutorialSystem.is_tutorial_done(s3.state) and st.invariants_ok().is_empty(), "%s %s %s" % [r.message, r2.message, st.invariants_ok()])


# ================================================================ four players

func _test_four_players() -> void:
	var s := _session(4, 777)
	var st := s.state
	var bad := PackedStringArray()
	var said := PackedStringArray()
	var cast := {"a": &"crew_2", "b": &"crew_3", "c": &"crew_4", "elec": &"crew_1", "bio": &"crew_3", "field": &"crew_4"}
	# every text a four-player group sees, for every crew member's screen
	var collect := func() -> void:
		var o := TutorialSystem.current_objective(st)
		if o.is_empty():
			return
		said.append(TutorialSystem.objective_text(o, true))
		for h in TutorialSystem.hints_for(st, o, true):
			said.append(h)
		for id: StringName in [&"crew_1", &"crew_2", &"crew_3", &"crew_4"]:
			var spec := String(o.get("specialty", o.get("specialty_hint", "")))
			said.append(TutorialSystem.specialist_cue(st, spec, id, true, o.has("specialty_hint")))
	var claim := s.request(&"claim_character", &"crew_2", {}, 1)
	_tick(s, 0.4)
	collect.call()
	var a: StringName = cast.a
	_go(s, a, st.character(a).position + Vector3(0.0, 0.0, 9.0))
	_tick(s, 0.4)
	collect.call()
	_go(s, cast.b, _pos(s, SUITS))
	_tick(s, 0.4)
	collect.call()
	# stage 2 by player 4 alone
	var c: StringName = cast.c
	var r := _do(s, c, &"begin_suit_check", SUITS, {"on": true})
	_tick(s, 1.4)
	collect.call()
	_go(s, c, _pos(s, TRACKER) + Vector3(2.0, 0, 0))
	_tick(s, 0.4)
	collect.call()
	_go(s, c, _pos(s, SUITS))
	_tick(s, 0.6)
	collect.call()
	if _stage(s) != 3: bad.append("stage 2 not done (%d %s)" % [_stage(s), _current(s)])
	# stage 3: the team is at the hub already; the electrical specialist is played (no switch); player 2 answers
	_go(s, a, s.config.hub_position)
	_tick(s, 0.4)
	collect.call()
	r = _answer(s, a, COMPUTER, "energy_q_battery_night")
	_tick(s, 0.6)
	collect.call()
	if _stage(s) != 4: bad.append("stage 3 not done (%d %s)" % [_stage(s), _current(s)])
	# stage 4: player 4 (outside, suited) cleans, player 1 (electrical) repairs, player 3 answers
	r = _do(s, c, &"clean_panel", TRACKER2)
	if not r.ok: bad.append("clean " + r.message)
	_tick(s, 0.4)
	collect.call()
	r = _do(s, cast.elec, &"repair_cleaner", TRACKER2)
	if not r.ok: bad.append("repair " + r.message)
	_tick(s, 0.4)
	collect.call()
	r = _answer(s, cast.b, POWER, "energy_q_dust_output")
	_tick(s, 0.6)
	collect.call()
	if _stage(s) != 5: bad.append("stage 4 not done (%d %s)" % [_stage(s), _current(s)])
	# stage 5: each step by a different player
	r = _answer(s, cast.elec, POWER, "energy_q_net_power")
	_tick(s, 0.4)
	collect.call()
	r = _do(s, a, &"set_zone_power", POWER, {"zone": "Dome plaza", "on": false})
	_tick(s, 0.4)
	collect.call()
	_do(s, cast.b, &"set_water_allocation", LS, {"electrolysis_feed_l_per_hour": 1.0})
	_do(s, cast.b, &"set_equipment", LS, {"equipment": "electrolyser", "on": true})
	_do(s, cast.b, &"set_equipment", LS, {"equipment": "co2_unit", "on": true})
	_tick(s, 0.4)
	collect.call()
	r = _answer(s, c, LS, "ls_q_two_paths")
	_tick(s, 0.6)
	collect.call()
	if _stage(s) != 6: bad.append("stage 5 not done (%d %s)" % [_stage(s), _current(s)])
	# stage 6 by the biology player, stage 7 by player 2
	r = _do(s, cast.bio, &"plant", BED2, {"crop": "lettuce"})
	_tick(s, 0.4)
	collect.call()
	r = _do(s, cast.bio, &"set_greenhouse_water", FOOD, {"greenhouse_l_per_hour": 1.0})
	_tick(s, 0.4)
	collect.call()
	r = _do(s, a, &"inspect_bed", BED2)
	_tick(s, 0.4)
	collect.call()
	r = _answer(s, cast.bio, FOOD, "food_q_light")
	_tick(s, 0.6)
	collect.call()
	if _stage(s) != 7: bad.append("stage 6 not done (%d %s)" % [_stage(s), _current(s)])
	r = _do(s, a, &"exercise", GYM)
	_tick(s, 0.4)
	collect.call()
	r = _do(s, c, &"refill_suit", SUITS)          # player 4 was outside: their tank is not full
	_tick(s, 0.6)
	collect.call()
	if _stage(s) != 8: bad.append("stage 7 not done (%d %s)" % [_stage(s), _current(s)])
	_go(s, cast.elec, _pos(s, COMMS))
	_tick(s, 0.4)
	collect.call()
	_install_radio(s, cast.elec)
	_tick(s, 0.6)
	collect.call()
	if _stage(s) != 9: bad.append("stage 8 not done (%d %s)" % [_stage(s), _current(s)])
	if not _solve_stage9(s, a): bad.append("stage 9 fix")
	_game_hours(s, 1.3)
	collect.call()
	if _stage(s) != 10: bad.append("stage 9 not done (%d %s)" % [_stage(s), _current(s)])
	_go(s, a, s.config.hub_position)
	_tick(s, 0.4)
	collect.call()
	r = _do(s, cast.field, &"inspect_donor", &"ls_filter_old")
	_tick(s, 0.6)
	var all_said := "\n".join(said)
	var asks := PackedStringArray()
	for line in said:
		if _mentions_switch(line):
			asks.append(line)
	var actors := {}
	for o_id: String in (TutorialSystem.tutorial_of(st).objectives as Dictionary):
		var by := String((TutorialSystem.objective_record(st, o_id)).get("by", ""))
		if by != "":
			actors[by] = true
	_check("four players: all ten stages done with real actions, no crew switch (switching refused as disabled), every step by one player",
		bad.is_empty() and TutorialSystem.is_tutorial_done(st) and not claim.ok and claim.reason == &"character_taken" and s.peers.size() == 4
		and st.character(&"crew_1").owner_peer == 1 and st.character(&"crew_4").owner_peer == 4, "\n  ".join(bad))
	_check("four players: nothing shown to the group asks anyone to switch crew; the cues name who should act (%d lines checked)" % said.size(),
		asks.is_empty() and all_said.contains("played by another player") and all_said.contains("You are the"), "\n  ".join(asks))
	_check("four players: work was shared (%d different crew members completed steps); no step waited for two players at once" % actors.size(), actors.size() >= 3, str(actors.keys()))


# ================================================================ order

func _test_order() -> void:
	var s := _session(1, 99)
	var st := s.state
	_tick(s, 0.4)
	# a stage 4 action done during stage 1 does not count later
	var early := _do(s, &"crew_1", &"clean_panel", TRACKER)
	_go(s, &"crew_1", s.config.hub_position)
	_tick(s, 0.4)
	var credited_early := (TutorialSystem.tutorial_of(st).credit as Dictionary).has("solar_clean")
	var bad := _solo_flow(s, 4)
	_tick(s, 0.6)
	_check("order: a stage 4 action done during stage 1 is not counted; stage 4 asks for it again",
		early.ok and not credited_early and bad.is_empty() and _stage(s) == 4 and not _done(s, "solar_clean") and _current(s) == "solar_clean", "%s %s" % [bad, _current(s)])
	# finish stage 4 for real
	_do(s, &"crew_1", &"clean_panel", TRACKER)
	_tick(s, 0.4)
	_do(s, &"crew_1", &"repair_cleaner", TRACKER)
	_tick(s, 0.4)
	_answer(s, &"crew_1", POWER, "energy_q_dust_output")
	_tick(s, 0.6)
	# stage 5: step 2 done before step 1 is credited but only completes after step 1
	var off := _do(s, &"crew_1", &"set_zone_power", POWER, {"zone": "Hangar bay", "on": false})
	var planted := _do(s, &"crew_1", &"plant", BED, {"crop": "lettuce"})          # a stage 6 action, early
	_tick(s, 0.6)
	var held := not _done(s, "energy_switch_off") and not _done(s, "energy_predict") and _current(s) == "energy_predict"
	_answer(s, &"crew_1", POWER, "energy_q_net_power")
	_tick(s, 0.6)
	_check("order: inside a stage, a step done early is kept but completes only after the step before it",
		off.ok and held and _done(s, "energy_predict") and _done(s, "energy_switch_off") and _current(s) == "energy_oxygen_on",
		"held %s, current %s" % [held, _current(s)])
	var order_ok := true
	var t := TutorialSystem.tutorial_of(st)
	var prev := -1.0
	for n in range(1, 6):
		for o: Dictionary in TutorialSystem.objectives_of(n):
			var rec := TutorialSystem.objective_record(st, String(o.id))
			if bool(rec.get("done", false)):
				order_ok = order_ok and float(rec.at_hours) >= prev - 1e-9
				prev = float(rec.at_hours)
	_check("order: objectives were completed in the data's order across stages", order_ok)
	_do(s, &"crew_1", &"set_water_allocation", LS, {"electrolysis_feed_l_per_hour": 1.0})
	_do(s, &"crew_1", &"set_equipment", LS, {"equipment": "electrolyser", "on": true})
	_do(s, &"crew_1", &"set_equipment", LS, {"equipment": "co2_unit", "on": true})
	_tick(s, 0.4)
	_answer(s, &"crew_1", LS, "ls_q_two_paths")
	_tick(s, 0.6)
	_check("order: a stage 6 action done during stage 5 does not count for stage 6; nothing of stage 6 is done when it starts",
		planted.ok and _stage(s) == 6 and not _done(s, "greenhouse_plant") and not (t.completed as Dictionary).has("6"), _current(s))


# ================================================================ repeat and replay

func _test_repeat_and_replay() -> void:
	var s := _session(1, 31)
	var st := s.state
	var bad := _solo_flow(s, 5)
	var t := TutorialSystem.tutorial_of(st)
	var completed_before: Dictionary = (t.completed as Dictionary).duplicate(true)
	var evidence_before := st.evidence.duplicate(true)
	var knowledge_before := st.knowledge.duplicate(true)
	var objectives_before: Dictionary = (t.objectives as Dictionary).duplicate(true)
	# doing stage 4 work again changes nothing in the tutorial
	_do(s, &"crew_1", &"clean_panel", TRACKER2)
	_answer(s, &"crew_1", POWER, "energy_q_dust_output")
	_tick(s, 0.6)
	_check("repeat: doing a finished stage's work again adds nothing (stage records, evidence, knowledge and objectives unchanged)",
		bad.is_empty() and _same(t.completed, completed_before) and _same(st.evidence, evidence_before) and _same(st.knowledge, knowledge_before)
		and _same(t.objectives, objectives_before) and _stage(s) == 5, "%s" % bad)
	# a reminder run of stage 4
	var refused := s.request(&"tutorial_replay", &"", {"stage": 7}, 1)
	var no_stop := s.request(&"tutorial_replay", &"", {"stage": 0}, 1)
	var start := s.request(&"tutorial_replay", &"", {"stage": 4}, 1)
	_tick(s, 0.4)
	var replay_open := String(TutorialSystem.replay_objective(st).get("id", ""))
	_do(s, &"crew_1", &"clean_panel", TRACKER)
	_tick(s, 1.0)
	var finished := TutorialSystem.replay_of(st).is_empty()
	_check("replay: only finished stages can be replayed; the reminder asks for the stage's work again and ends by itself",
		not refused.ok and refused.reason == &"missing_prerequisite" and not no_stop.ok and start.ok and replay_open == "solar_clean" and finished,
		"%s / %s / open %s / finished %s" % [refused.message, start.message, replay_open, finished])
	_check("replay: nothing in the reminder counted twice (stage records, evidence, knowledge, main objectives and stage unchanged)",
		_same(t.completed, completed_before) and _same(st.evidence, evidence_before) and _same(st.knowledge, knowledge_before)
		and _same(t.objectives, objectives_before) and _stage(s) == 5)
	# a reminder of stage 2 needs the walk again; it can be stopped
	s.request(&"tutorial_replay", &"", {"stage": 2}, 1)
	_tick(s, 0.4)
	var stop := s.request(&"tutorial_replay", &"", {"stage": 0}, 1)
	_check("replay: a reminder can be stopped and shows explanations even when mastered",
		stop.ok and TutorialSystem.replay_of(st).is_empty() and TutorialSystem.explanation_for(st, TutorialSystem.objective_def("airlock_suit"), true) != ""
		and TutorialSystem.explanation_for(st, TutorialSystem.objective_def("airlock_suit")) == "", stop.message)


# ================================================================ hints and mastery

func _test_hints_and_mastery() -> void:
	var after := TutorialSystem.number("hint_after_s", 75.0)
	var rep := TutorialSystem.number("hint_repeat_s", 60.0)
	var table := [TutorialSystem.hint_count(0.0, 0, 3), TutorialSystem.hint_count(after - 0.1, 0, 3), TutorialSystem.hint_count(after, 0, 3),
		TutorialSystem.hint_count(after + rep, 0, 3), TutorialSystem.hint_count(after + 10.0 * rep, 0, 3), TutorialSystem.hint_count(0.0, 1, 3),
		TutorialSystem.hint_count(after, 5, 3), TutorialSystem.hint_count(1000.0, 0, 0)]
	_check("hints: none at first, one after %d real seconds without progress, one more every %d s, one per request, never more than there are" % [roundi(after), roundi(rep)],
		table == [0, 0, 1, 2, 3, 1, 3, 0], str(table))
	# mastery: the battery question answered before stage 3 makes its step skip, with no explanation
	var s := _session(1, 55)
	var st := s.state
	_tick(s, 0.4)
	var r := _answer(s, &"crew_1", COMPUTER, "energy_q_battery_night")
	var o := TutorialSystem.objective_def("hub_reserves")
	var shown_before_stage := TutorialSystem.explanation_for(st, o)
	var fresh := TutorialSystem.explanation_for(st, TutorialSystem.objective_def("arrival_walk"))
	var bad := _solo_flow(s, 4)
	var rec := TutorialSystem.objective_record(st, "hub_reserves")
	_check("mastery: a question the colony already knows skips its step and its explanation; an unknown step shows its explanation",
		r.ok and bad.is_empty() and bool(rec.get("skipped", false)) and shown_before_stage == "" and fresh != "", "%s %s %s" % [bad, rec, shown_before_stage])
	_check("mastery: a finished stage's explanations are skipped from then on", TutorialSystem.explanation_for(st, TutorialSystem.objective_def("arrival_walk")) == ""
		and TutorialSystem.explanation_for(st, TutorialSystem.objective_def("solar_clean")) != "")
	# cues: one to three players are told to switch only when nobody plays the specialist
	var s2 := _session(2, 56)
	var cue_mine := TutorialSystem.specialist_cue(s2.state, "electrical_comms", &"crew_1", false)
	var cue_other := TutorialSystem.specialist_cue(s2.state, "electrical_comms", &"crew_2", false)
	var cue_nobody := TutorialSystem.specialist_cue(s2.state, "field_engineering_geology", &"crew_2", false)
	var cue_team := TutorialSystem.specialist_cue(s2.state, "field_engineering_geology", &"crew_2", true)
	_check("cues: your own specialist step, a step another player's specialist does, a switch cue only when nobody plays the specialist (never with four players)",
		cue_mine.contains("You are the") and cue_other.contains("played by another player") and cue_nobody.contains("Switch at the hub")
		and not _mentions_switch(cue_team) and cue_mine.contains("⚡") and cue_nobody.contains("⛏"), "\n  %s\n  %s\n  %s\n  %s" % [cue_mine, cue_other, cue_nobody, cue_team])


# ================================================================ stage 9

func _test_stage9_variants() -> void:
	var seen := {}
	var first := {}
	var stable := true
	for seed_value in range(1, 41):
		var v := TutorialSystem.variant_for_seed(seed_value)
		stable = stable and v == TutorialSystem.variant_for_seed(seed_value)
		seen[v] = true
		if not first.has(v):
			first[v] = seed_value
	var three := {}
	for seed_value in [1, 2, 3]:
		three[TutorialSystem.variant_for_seed(seed_value)] = true
	_check("stage 9: the variant comes from the colony seed (same seed, same variant); seeds 1, 2, 3 give %d different variants; all three appear" % three.size(),
		stable and three.size() >= 2 and seen.size() == 3, "%s %s" % [three.keys(), first])
	for v: String in TutorialSystem.VARIANTS:
		var seed_value := int(first.get(v, 1))
		var s := _session(1, seed_value)
		var st := s.state
		_do(s, &"crew_1", &"plant", BED, {"crop": "lettuce"})
		_do(s, &"crew_1", &"set_greenhouse_water", FOOD, {"greenhouse_l_per_hour": 1.0})
		_tick(s, 0.4)
		_skip_to(s, 9)                            # synthetic set-up: stages 1-8 marked done
		_tick(s, 0.6)
		var s9 := TutorialSystem.stage9_of(st)
		var injected_ok := bool(s9.get("injected", false)) and String(s9.variant) == v
		match v:
			"greenhouse_breaker":
				injected_ok = injected_ok and not st.is_zone_powered("Greenhouse")
			"trackers_stopped":
				injected_ok = injected_ok and not st.is_on("trackers")
			"lighting_overload":
				injected_ok = injected_ok and not st.is_zone_powered("Greenhouse") and TutorialSystem.room_light_kw(st, s.balance) > float(s9.limit_kw)
		# harmless: two sols unsolved, nobody loses health, stores stay valid
		var health := {}
		for c: CharacterState in st.active_characters():
			health[c.id] = c.health
		s.request(&"set_sol_minutes", &"", {"minutes": 5.0}, 1)
		_game_hours(s, 2.0 * GameConfig.SOL_HOURS)
		var harmless := st.invariants_ok().is_empty() and not bool(TutorialSystem.stage9_of(st).solved)
		for c: CharacterState in st.active_characters():
			harmless = harmless and c.health >= float(health[c.id]) - 1e-6
		# save and load mid-problem: no second injection
		var s2 := _resume(s, _json(st))
		var trips_before := int(TutorialSystem.stage9_of(s2.state).get("trips", 0))
		var at_before := float(TutorialSystem.stage9_of(s2.state).at_hours)
		_tick(s2, 0.6)
		var once := float(TutorialSystem.stage9_of(s2.state).at_hours) == at_before and int(TutorialSystem.stage9_of(s2.state).get("trips", 0)) == trips_before
		# the overload breaker opens again if the grow lights come back with every room light on
		var retrip := true
		if v == "lighting_overload":
			_do(s2, &"crew_1", &"set_zone_power", POWER, {"zone": "Greenhouse", "on": true})
			_tick(s2, 0.6)
			retrip = not s2.state.is_zone_powered("Greenhouse") and int(TutorialSystem.stage9_of(s2.state).trips) > trips_before
		var fixed := _solve_stage9(s2, &"crew_1")
		_tick(s2, 0.6)
		var half := _done(s2, "challenge_fix") and not _done(s2, "challenge_hold")
		_game_hours(s2, 1.2)
		_tick(s2, 0.6)
		_check("stage 9 %s (seed %d): injected into the real colony, harmless for two sols, not injected again after save/load%s, solved with real power-panel actions held for an hour" % [v, seed_value, ", the breaker re-opens while the room lights are too many" if v == "lighting_overload" else ""],
			injected_ok and harmless and once and retrip and fixed and half and bool(TutorialSystem.stage9_of(s2.state).solved) and _stage(s2) == 10,
			"injected %s harmless %s once %s retrip %s fixed %s half %s solved %s stage %d" % [injected_ok, harmless, once, retrip, fixed, half, TutorialSystem.stage9_of(s2.state).get("solved"), _stage(s2)])


# ================================================================ certification

func _test_certification() -> void:
	var s := _session(1, 808)
	var st := s.state
	s.request(&"set_sol_minutes", &"", {"minutes": 5.0}, 1)
	_tick(s, 0.4)
	_check("certification: locked during the tutorial", String(TutorialSystem.certification_of(st).status) == "locked")
	_skip_to(s, 11)                               # synthetic set-up: the tutorial marked done
	_tick(s, 0.6)
	var waiting := String(TutorialSystem.certification_of(st).status) == "waiting" and TutorialSystem.requirements_missing(st).size() == 6
	_make_sectors_work(s)                         # synthetic set-up: tier 1 everywhere and the first radio card
	_tick(s, 0.6)
	var cert := TutorialSystem.certification_of(st)
	_check("certification: waits for all five sectors and the radio, then the sol starts", waiting and String(cert.status) == "running", str(cert))
	var progress_before := {"knowledge": st.knowledge.duplicate(true), "evidence": st.evidence.duplicate(true), "upgrades": st.upgrades.duplicate(true),
		"tiers": (st.progress.get("tiers", {}) as Dictionary).duplicate(true), "tutorial": (TutorialSystem.tutorial_of(st)).duplicate(true)}
	# an emergency recovery restarts the sol
	_game_hours(s, 0.5 * GameConfig.SOL_HOURS)
	var half := float(TutorialSystem.certification_of(st).elapsed_hours)
	s.recover_character(&"crew_1")
	_tick(s, 0.4)
	cert = TutorialSystem.certification_of(st)
	var after_recovery := float(cert.elapsed_hours) < 0.1 and String(cert.status) == "running" and (cert.resets as Array).size() == 1 \
		and String((cert.resets as Array)[0].reason) == "recovery"
	_check("certification: an emergency recovery restarts the sol (%.1f h were done) and keeps running" % half, half > 10.0 and after_recovery, str(cert))
	# a reserve reaching zero restarts it and holds it until the store is above zero again (synthetic: food nearly gone)
	_game_hours(s, 0.3 * GameConfig.SOL_HOURS)
	st.stores[&"food_meals"] = 0.002
	_tick(s, 1.0)
	cert = TutorialSystem.certification_of(st)
	var paused := String(cert.status) == "paused_reserve" and (cert.resets as Array).size() == 2 and String((cert.resets as Array)[1].detail) == "food_meals"
	st.add_to_store(&"food_meals", 60.0)          # synthetic: a harvest
	_tick(s, 0.6)
	var resumed := String(TutorialSystem.certification_of(st).status) == "running"
	_check("certification: the food store reaching zero restarts the sol and holds it until food is back; then it starts again", paused and resumed, str(cert))
	# a real action that empties a store (a suit refill taking the last oxygen) restarts it too
	_game_hours(s, 0.1 * GameConfig.SOL_HOURS)
	st.stores[&"oxygen_kg"] = 0.05                # synthetic: oxygen nearly gone
	st.character(&"crew_1").suit_charge = 0.0
	var refill := _do(s, &"crew_1", &"refill_suit", SUITS)
	cert = TutorialSystem.certification_of(st)
	var o2_reset := refill.ok and String(cert.status) == "paused_reserve" and String((cert.resets as Array).back().detail) == "oxygen_kg"
	st.add_to_store(&"oxygen_kg", 60.0)           # synthetic: oxygen restored
	_tick(s, 0.6)
	_check("certification: a suit refill that takes the last oxygen restarts the sol at once", o2_reset and String(TutorialSystem.certification_of(st).status) == "running", str(cert))
	var kept := _same(st.knowledge, progress_before.knowledge) and _same(st.evidence, progress_before.evidence) and _same(st.upgrades, progress_before.upgrades) \
		and _same(st.progress.get("tiers", {}), progress_before.tiers) and _same(TutorialSystem.tutorial_of(st).completed, (progress_before.tutorial as Dictionary).completed)
	_check("certification: restarts never wipe progress (knowledge, evidence, upgrades, tiers, tutorial)", kept)
	# save/load mid-sol keeps the count; then a full sol completes it
	var s2 := _resume(s, _json(st))
	var e_before := float(TutorialSystem.certification_of(s2.state).elapsed_hours)
	_tick(s2, 0.4)
	var continued := float(TutorialSystem.certification_of(s2.state).elapsed_hours) >= e_before and String(TutorialSystem.certification_of(s2.state).status) == "running"
	for i in 1700:
		s2.advance(0.2)
		if String(TutorialSystem.certification_of(s2.state).status) == "complete":
			break
	cert = TutorialSystem.certification_of(s2.state)
	_check("certification: save/load mid-sol keeps the count; one full sol later the first milestone is complete",
		continued and String(cert.status) == "complete" and float(cert.completed_at_hours) - float(cert.started_at_hours) >= GameConfig.SOL_HOURS - 0.01, str(cert))
	# after completion nothing undoes it
	s2.state.stores[&"food_meals"] = 0.0
	s2.recover_character(&"crew_1")
	_tick(s2, 1.0)
	_check("certification: after completion a later shortage or rescue does not undo the milestone", String(TutorialSystem.certification_of(s2.state).status) == "complete")


# ================================================================ story records

func _test_lore_runtime() -> void:
	var s := _session(1, 1234)
	var st := s.state
	_tick(s, 0.4)
	var r1 := _do(s, &"crew_1", &"read_record", &"pr_fsp_console")
	var r2 := _do(s, &"crew_1", &"read_record", &"pr_fsp_console")
	var count := st.discoveries.size()
	var wrong := _do(s, &"crew_1", &"read_record", POWER)
	_go(s, &"crew_1", s.config.hub_position)
	var far := s.request(&"read_record", &"pr_fsp_console", {}, 1)
	_check("story: a record is found once by reading it at its console; reading again adds nothing; elsewhere or from afar it is refused",
		r1.ok and bool(r1.changes.new) and r2.ok and not bool(r2.changes.new) and count == 1 and TutorialSystem.is_found(st, "rec_power_console")
		and not wrong.ok and not far.ok and far.reason == &"too_far", "%s %s %s" % [r1.message, wrong.reason, far.reason])
	# records at salvage donors come with the real inspect action, then a discovery completes once
	_do(s, &"crew_1", &"inspect_donor", &"pr_bat_rack_alarm")
	var before_crash := TutorialSystem.is_found(st, "disc_small_battery")
	_do(s, &"crew_1", &"begin_suit_check", SUITS, {"on": true})
	_tick(s, 1.4)
	_do(s, &"crew_1", &"inspect_donor", &"sf_crash_tank")
	_do(s, &"crew_1", &"inspect_donor", &"sf_crash_tank", {"choice": "valve"})
	var discs := 0
	for d: Variant in st.discoveries:
		if d is Dictionary and String((d as Dictionary).id) == "disc_small_battery":
			discs += 1
	_check("story: inspecting salvage donors finds their records; three clues make the discovery, recorded once",
		not before_crash and discs == 1 and TutorialSystem.is_found(st, "rec_battery_rack") and TutorialSystem.is_found(st, "rec_crash_tank"))
	# every other record, then the final discovery
	var all_ok := true
	for r: Dictionary in TutorialSystem.records():
		if TutorialSystem.is_found(st, String(r.id)):
			continue
		var station := StringName(String(r.station))
		if String(r.via) == "read_record":
			all_ok = _do(s, &"crew_1", &"read_record", station).ok and all_ok
		else:
			all_ok = _do(s, &"crew_1", &"inspect_donor", station).ok and all_ok
	var ids := {}
	for d: Variant in st.discoveries:
		ids[String((d as Dictionary).id)] = int(ids.get(String((d as Dictionary).id), 0)) + 1
	var once := true
	for k in ids:
		once = once and int(ids[k]) == 1
	_check("story: all %d records and %d discoveries (the final one last) are found, each exactly once, saved in state.discoveries" % [TutorialSystem.records().size(), TutorialSystem.discovery_defs().size()],
		all_ok and once and ids.size() == TutorialSystem.records().size() + TutorialSystem.discovery_defs().size() and TutorialSystem.is_found(st, "disc_cascade_solved")
		and _index_of(st, "disc_cascade_solved") > _index_of(st, "disc_small_battery") and _index_of(st, "disc_cascade_solved") > _index_of(st, "disc_less_sun") and _index_of(st, "disc_cascade_solved") > _index_of(st, "disc_one_line") and _index_of(st, "disc_cascade_solved") > _index_of(st, "disc_safe_return"), str(ids))
	var copy := ColonyState.from_dict(_json(st))
	_check("story: discoveries survive save/load", copy.discoveries.size() == st.discoveries.size() and TutorialSystem.is_found(copy, "disc_cascade_solved"))
	_check("story: finding records changes nothing in the tutorial or the colony stores", TutorialSystem.current_stage(st) <= 2 and st.invariants_ok().is_empty())


# ================================================================ presentation

func _test_presentation() -> void:
	var gs := GameServices.new()
	gs.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/wT"), "colony", 2)
	root.add_child(gs)
	gs.start_new_game(4242)
	var stretch := root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	await process_frame
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	var game := FakeGame.new()
	game.name = "FakeGame"
	root.add_child(game)
	game.hud = GameHud.new()
	game.add_child(game.hud)
	game.hud.setup(gs)
	game.ui = UiRoot.new()
	game.add_child(game.ui)
	game.ui.setup(gs, GameSettings.new())
	var presenter := TutorialPresenter.new()
	game.add_child(presenter)
	presenter.setup(null, gs, game)
	for i in 4:
		await process_frame
	presenter.refresh()
	await process_frame
	await process_frame
	var w := presenter.hud_widget
	var lines := w.lines()
	var rect := w.get_global_rect()
	var top_right := game.hud.root_control().find_child("TopRight", true, false) as Control
	var top_left := game.hud.root_control().find_child("TopLeft", true, false) as Control
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var centre := Rect2(Vector2(640 - 120, 360 - 80), Vector2(240, 160))
	_check("hud: the tracker is under the GameHud and shows stage 1 with its first step", w.get_parent() == game.hud and w.visible and "\n".join(lines).contains("Tutorial 1 of 10")
		and "\n".join(lines).contains("W A S D"), "\n".join(lines))
	_check("hud: at 1280x720 the tracker is on screen and covers neither the colony corner, the crew box nor the crosshair",
		screen.encloses(rect) and not rect.intersects(top_right.get_global_rect()) and not rect.intersects(top_left.get_global_rect()) and not rect.intersects(centre)
		and UiLayoutCheck.problems(w, Vector2(1280, 720)).is_empty(), "%s vs %s / %s %s" % [rect, top_right.get_global_rect(), top_left.get_global_rect(), UiLayoutCheck.problems(w, Vector2(1280, 720))])
	# hints come with time without progress and on request; progress clears them
	presenter._process(80.0)
	presenter.refresh()
	var timed := (presenter.current_view().hints as PackedStringArray).size()
	presenter.request_hint()
	var asked := (presenter.current_view().hints as PackedStringArray).size()
	var me := gs.local_character()
	gs.report_position(me.id, me.position + Vector3(9.0, 0.0, 0.0), 0.0)
	gs.session.advance(0.4)
	presenter._process(0.3)
	presenter.refresh()
	var after := (presenter.current_view().hints as PackedStringArray).size()
	_check("hud: a hint after 80 s without progress, a second on request (N), none again once the step is done",
		timed == 1 and asked == 2 and after == 0 and presenter.idle_seconds < 1.0, "%d %d %d" % [timed, asked, after])
	# the journal fits every screen size, its buttons can be focused
	var panels: Array[UiPanel] = []
	var journal := StoryLogPanel.new()
	journal.presenter = presenter
	journal.setup(gs)
	panels.append(journal)
	var layout := PackedStringArray()
	for panel in panels:
		root.add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for sz: Array in SIZES:
			root.size = sz[0]
			_apply_text_scale(float(sz[1]))
			await process_frame
			await process_frame
			panel.refresh()
			await process_frame
			for line in UiLayoutCheck.problems(panel, Vector2(sz[0])):
				layout.append("%s at %s: %s" % [panel.name, sz[0], line])
			var min_size := panel.get_combined_minimum_size()
			if min_size.x > float(sz[0].x) or min_size.y > float(sz[0].y):
				layout.append("%s at %s: minimum size %s is bigger than the screen" % [panel.name, sz[0], min_size])
			for line in UiLayoutCheck.focus_problems(panel):
				layout.append("%s focus: %s" % [panel.name, line])
		_apply_text_scale(1.0)
	_check("journal: fits 1280x720, 1920x1080 and text 1.5; every button takes focus", layout.is_empty() and not UiLayoutCheck.focusable(journal).is_empty(), "\n  ".join(layout))
	# the journal's answer button works where the question can be answered
	root.size = Vector2i(1280, 720)
	var t: Dictionary = TutorialSystem.ensure(gs.state()).tutorial
	_skip_to_gs(gs, 3)
	gs.session.advance(0.4)
	gs.report_position(me.id, gs.config.hub_position, 0.0)
	gs.session.advance(0.4)
	journal.refresh()
	var away := journal.answer_button.visible and journal.answer_button.disabled
	gs.report_position(me.id, CharacterState._v3((gs.state().stations["cm_colony_computer"] as Dictionary).position), 0.0)
	journal.refresh()
	var near := journal.answer_button.visible and not journal.answer_button.disabled
	_check("journal: 'Answer the question here' opens only where the step's question can be answered (the colony computer)", away and near and String(t.current) == "hub_reserves",
		"away %s near %s current %s" % [away, near, t.current])
	# four players: nothing on the tracker asks to switch
	for p in [2, 3, 4]:
		gs.session.peer_joined(p)
		gs.session.request(&"claim_character", StringName("crew_%d" % p), {}, p)
	_skip_to_gs(gs, 10)
	gs.session.advance(0.6)
	presenter.refresh()
	var team_lines := "\n".join(presenter.hud_widget.lines())
	journal.refresh()
	var journal_text := journal._objective_label.text + " " + journal._cue_label.text
	_check("hud: with four players the screens are in team mode, the crew-selection step names who leads, and nothing asks to switch", TutorialPresenter.switching_disabled(gs) and TutorialSystem.objective_text(TutorialSystem.objective_def("explore_engineer"), true).contains("player leads") and TutorialSystem.is_objective_done(gs.state(), "explore_engineer") and not _mentions_switch(team_lines)
		and not _mentions_switch(journal_text), team_lines)
	journal.queue_free()
	game.queue_free()
	root.content_scale_mode = stretch
	gs.queue_free()
	await process_frame


func _index_of(st: ColonyState, id: String) -> int:
	for i in st.discoveries.size():
		if String((st.discoveries[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


func _skip_to_gs(gs: GameServices, n: int) -> void:
	var t: Dictionary = TutorialSystem.ensure(gs.state()).tutorial
	for k in range(1, n):
		for o: Dictionary in TutorialSystem.objectives_of(k):
			(t.objectives as Dictionary)[String(o.id)] = {"done": true, "at_hours": 0.0, "by": "crew_1", "skipped": false}
		(t.completed as Dictionary)[str(k)] = {"at_hours": 0.0}
	t["stage"] = n
	t["started"] = false
	t["current"] = ""


## Applies a text scale (the same way tests\test_station_panels.gd does while UiTheme's scale is a stub).
func _apply_text_scale(sc: float) -> void:
	UiTheme.apply_text_scale(sc)
	var th := UiTheme.get_theme()
	var wanted := roundi(UiTheme.BASE_FONT_SIZE * sc)
	if sc != 1.0 and th.default_font_size == UiTheme.BASE_FONT_SIZE:
		th.default_font_size = wanted
	elif sc == 1.0:
		th.default_font_size = UiTheme.BASE_FONT_SIZE
