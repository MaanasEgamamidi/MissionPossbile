extends SceneTree
## The whiteboard tutorial (owner decisions 2026-11-14), which replaces the Prompt Pack's old ten-stage tutorial:
## arrival outside the open base, the first team's 6 room tapes (found n/6, played n/6 at the Command Room cassette
## player), Mission Control's "Fix the base", the 10 broken spots (T05 and T07 not required), then "Base operational"
## and the held doors released. Also: the tutorial station lock, the wrong-specialist scrambled panel, the crew radio
## gate, save/load, replication and late join, the colony goal (certification) after the tutorial, and the optional
## first-crew story (shared machinery that still applies).
## SYNTHETIC headless checks on the real model and real actions (no scene, no player, no network): crew move by the
## host's own position reports; tapes are collected and played with the real cassette actions; every broken spot is
## fixed through the real RepairRuntime path (task_claim, task_move) with a stand-in "finish" rule, because each real
## puzzle is solved in its own tests/test_puzzle_tNN.gd. Set-ups that jump ahead are marked "synthetic set-up".
## Run: ..\godot.cmd --headless --path . --script res://tests/test_tutorial.gd

const TutorialLock := preload("res://scripts/session/tutorial_lock.gd")
const CommsGate := preload("res://scripts/voice/comms_gate.gd")
const MANIFEST := "res://data/colony_manifest.json"
const SUITS := &"al_suit_rack"
const COMMS := &"cm_comms_console"
const POWER := &"pw_panel"
const PLAYER := &"cassette_player_command_center"
const TRACKER := &"sf_solar_tracker"
const STAGE_TITLES: Array[String] = ["Arrival", "The first team's tapes", "Fix the base"]
const KINDS: Array[String] = ["inside_base", "tapes_found", "tapes_played", "fixes"]
## Owner 2026-11-14 / docs/revisions/BROKEN_PARTS_BRIEF.md: the 10 broken spots (T05 and T07 have no broken part).
const TEN: Array[String] = ["T01", "T02", "T03", "T04", "T06", "T08", "T09", "T10", "T11", "T12"]
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
## Per session: Mission Control alerts and objective events seen.
var _alerts := {}
var _objective_events := {}


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
	_test_solo_flow()
	_test_order()
	_test_lock_host()
	_test_voice_gate()
	_test_save_and_late_join()
	_test_migration()
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
## Zones are wired as in the game (cassette playback and repairs check the room).
func _session(active: int, seed_value := 4242) -> SessionService:
	var ev := GameEvents.new()
	_event_nodes.append(ev)
	var s := SessionService.new(GameConfig.new(), GameBalance.new(), ev)
	var st := ColonyState.new_game(s.balance, seed_value, _zones.names)
	st.stations = _catalog.duplicate(true)
	s.outside_test = func(p: Vector3) -> bool: return _zones.zone_at_world(p) == ColonyZones.EXTERIOR
	s.zone_at_position = func(p: Vector3) -> String: return _zones.zone_at_world(p)
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
	var heard: Array[String] = []
	var events: Array[String] = []
	_alerts[s] = heard
	_objective_events[s] = events
	ev.system_alert.connect(func(id: StringName, _level: StringName, text: String) -> void:
		if id == &"mission_control":
			heard.append(text))
	ev.objective_changed.connect(func(id: StringName) -> void: events.append(String(id)))
	return s


## A new game in tutorial mode as the real game starts it (synthetic set-up of GameServices._tutorial_start and the
## presenter's mode switch): the active crew suited at the tutorial spawn outside, tutorial mode on.
func _tutorial_session(active: int, seed_value := 4242) -> SessionService:
	var s := _session(active, seed_value)
	for i in active:
		var c := s.state.character(StringName("crew_%d" % (i + 1)))
		c.suit_on = true
		c.suit_charge = 100.0
		c.suit_integrity = 1.0
		_go(s, c.id, s.config.tutorial_spawn_position + s.config.tutorial_spawn_offsets[i])
	TutorialSystem.begin_tutorial_mode(s.state, true)
	return s


## A second session that continues from `d` (a saved colony, as JSON text would give it back).
func _resume(s: SessionService, d: Dictionary) -> SessionService:
	var ev := GameEvents.new()
	_event_nodes.append(ev)
	var s2 := SessionService.new(GameConfig.new(), GameBalance.new(), ev)
	s2.outside_test = s.outside_test
	s2.zone_at_position = s.zone_at_position
	var c := SolClock.from_dict(s.clock.to_dict())
	s2.begin(ColonyState.from_dict(d), c)
	for p: int in s.peers:
		s2.peer_joined(p)
	var heard: Array[String] = []
	_alerts[s2] = heard
	_objective_events[s2] = [] as Array[String]
	ev.system_alert.connect(func(id: StringName, _level: StringName, text: String) -> void:
		if id == &"mission_control":
			heard.append(text))
	return s2


## The colony as a save holds it (the repair records through their save projection), back from JSON text.
func _json(st: ColonyState) -> Dictionary:
	var d := st.to_dict()
	d["repair"] = RepairCatalog.for_save(st.repair)
	return JSON.parse_string(JSON.stringify(d))


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
		or t.contains("choose them on the crew screen") or t.contains("change crew") or t.contains("switch to") or t.contains("swap")


func _heard(s: SessionService) -> Array:
	return _alerts.get(s, []) as Array


func _count_heard(s: SessionService, needle: String) -> int:
	var n := 0
	for line: String in _heard(s):
		if line.contains(needle):
			n += 1
	return n


## Collects one tape with the real action by `crew`.
func _collect(s: SessionService, crew: StringName, id: String) -> ActionResult:
	return _do(s, crew, &"cassette_collect", StringName(id))


## Plays one tape at the Command Room cassette player with the real actions (open the player, choose the tape).
func _play(s: SessionService, crew: StringName, id: String) -> ActionResult:
	var opened := _do(s, crew, &"cassette_open", PLAYER)
	if not opened.ok:
		return opened
	return s.request(&"cassette_select", PLAYER, {"cassette_id": id}, _peer(s, crew))


## Stand-in rule for every broken spot: one "finish" move completes it (the real puzzles: tests/test_puzzle_tNN.gd).
func _stand_in_rules(s: SessionService) -> void:
	var finish := func(_task: Dictionary, move: Dictionary) -> Dictionary:
		if String(move.get("move", "")) != "finish":
			return {"accepted": false}
		return {"accepted": true, "puzzle_state": {"done": 1}, "progress": 1.0, "complete": true}
	for id: String in TEN:
		s.repair_runtime.register_rule(id, finish, false)


## Fixes broken spot `task` by `crew` through the real RepairRuntime path; returns the move's answer.
func _fix(s: SessionService, crew: StringName, task: String) -> ActionResult:
	var station := StringName(RepairCatalog.anchor_id(task))
	var gen := int(s.state.repair.tasks[task].fault_generation)
	var claim := _do(s, crew, &"task_claim", station, {"generation": gen})
	if not claim.ok:
		return claim
	return s.request(&"task_move", station, {"generation": gen, "move": "finish", "value": 1}, _peer(s, crew))


## The crew member of `specialty`.
func _crew_of(specialty: String) -> StringName:
	return StringName("crew_%d" % (CharacterState.SPECIALTIES.find(StringName(specialty)) + 1))


## Fixes every listed spot solo by `start` crew, switching at the hub to the right specialist (real claims).
## Returns the crew member played at the end.
func _fix_all_solo(s: SessionService, start: StringName, counts: Array) -> StringName:
	var me := start
	for task: String in TEN:
		if TutorialSystem.is_fixed(s.state, task):
			continue
		var spec := String(s.state.repair.tasks[task].required_specialty)
		var who := me
		if spec != "general" and String(s.state.character(me).specialty) != spec:
			who = _crew_of(spec)
			if s.state.character(who).owner_peer == 0:
				if not _switch(s, me, who).ok:
					push_error("switch to %s failed" % who)
				me = who
		var r := _fix(s, who, task)
		if not r.ok:
			_notes.append("fix %s failed: %s %s" % [task, r.reason, r.message])
		_go(s, who, s.config.hub_position)        # back to the hub (the leaking vestibule is no place to wait)
		_tick(s, 0.4)
		counts.append(TutorialSystem.fixed_count(s.state))
	return me


# ================================================================ data

func _test_data() -> void:
	var stages := TutorialSystem.stages()
	var titles: Array[String] = []
	var order_ok := stages.size() == TutorialSystem.STAGE_COUNT
	for i in stages.size():
		order_ok = order_ok and int((stages[i] as Dictionary).n) == i + 1
		titles.append(String((stages[i] as Dictionary).title))
	_check("data: three steps in order (arrival, the first team's tapes, fix the base)", order_ok and titles == STAGE_TITLES, str(titles))
	var ids := {}
	var bad := PackedStringArray()
	for s: Dictionary in stages:
		if String(s.get("intro", "")) == "" or (s.get("start_messages", []) as Array).is_empty():
			bad.append("step %d: no intro or Mission Control line" % int(s.n))
		for m in s.get("start_messages", []):
			if TutorialSystem.message_text(String(m)) == "":
				bad.append("step %d: message %s missing" % [int(s.n), m])
		for o: Dictionary in s.get("objectives", []):
			var id := String(o.get("id", ""))
			if id == "" or ids.has(id):
				bad.append("objective id missing or repeated: %s" % id)
			ids[id] = true
			if not KINDS.has(String(o.get("kind", ""))):
				bad.append("%s: unknown kind %s" % [id, o.get("kind", "")])
			if String(o.get("text", "")) == "" or String(o.get("explain", "")) == "" or (o.get("hints", []) as Array).is_empty():
				bad.append("%s: text, explanation or hints missing" % id)
			if _mentions_switch(TutorialSystem.objective_text(o, true)):
				bad.append("%s: the four-player text asks to switch" % id)
			for h in TutorialSystem.hints_for(null, o, true):
				if _mentions_switch(h):
					bad.append("%s: a four-player hint asks to switch: %s" % [id, h])
	_check("data: every objective has a known kind, words, an explanation and hints; every step has Mission Control lines; with four players none asks to switch crew",
		bad.is_empty(), "\n  ".join(bad))
	var listed: Array[String] = []
	for f: Dictionary in TutorialSystem.fix_defs():
		listed.append(String(f.task))
	var fbad := PackedStringArray()
	for id: String in TEN:
		if not PuzzleRegistry.has_puzzle(id):
			fbad.append("%s has no puzzle installed" % id)
		if String(TutorialSystem.fix_def(id).get("text", "")) == "" or String(TutorialSystem.fix_def(id).get("done", "")) == "":
			fbad.append("%s has no words" % id)
	_check("data: the fix list is the 10 broken spots in room order (T05 and T07 not required), each with its puzzle installed and words",
		listed == TEN and Array(TutorialSystem.required_fixes()) == TEN and fbad.is_empty(), "%s %s" % [listed, fbad])
	var text := ""
	for m: String in (TutorialSystem.data().get("messages", {}) as Dictionary):
		text += " " + TutorialSystem.message_text(m)
	var low := text.to_lower()
	var scary := PackedStringArray()
	for w in FORBIDDEN_WORDS:
		for token in low.replace(".", " ").replace(",", " ").replace(":", " ").replace("!", " ").split(" ", false):
			if token == w:
				scary.append(w)
	_check("data: Mission Control tells the story (2060s, Earth, the second team, the first team's tapes) with no scary words; the fix line says 'Fix the base: get it to operational condition.'",
		low.contains("2060s") and low.contains("earth") and low.contains("second team") and low.contains("tape") and scary.is_empty()
		and TutorialSystem.message_text("fix_start").begins_with("Fix the base: get it to operational condition."), str(scary))
	var rows := TutorialSystem.fix_rows(null)
	var specs := {}
	for r: Dictionary in rows:
		specs[String(r.task)] = String(r.specialty)
	_check("data: the list shows the specialist each spot needs (T02, T04 electrical; T09 medical; T12 field engineering; the rest anyone)",
		specs.T02 == "electrical_comms" and specs.T04 == "electrical_comms" and specs.T09 == "medical_life_support" and specs.T12 == "field_engineering_geology"
		and specs.T01 == "" and specs.T03 == "" and specs.T06 == "" and specs.T08 == "" and specs.T10 == "" and specs.T11 == "", str(specs))


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
	for r: Dictionary in recs:
		if not used.has(String(r.id)) and String(r.id) != "rec_handover":
			dbad.append("%s is no clue of any discovery" % r.id)
	_check("lore: four discoveries and a final one; every clue exists and every record (except the handover note) is a clue", TutorialSystem.discovery_defs().size() == 5 and dbad.is_empty(), "\n  ".join(dbad))


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
	_check("sources: every record's source id is a VERIFIED register entry", bad.is_empty(), "\n  ".join(bad))
	var cats: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/model_sources_campaign.json"))
	var ok := cats is Dictionary and _approx(float(TutorialSystem.data().hint_after_s), float((cats as Dictionary).hint_after_s.value)) \
		and String(((cats as Dictionary).get("certification.sols", {}) as Dictionary).get("category", "")) != ""
	_check("sources: the hint timing and the certification sol keep their categories in model_sources_campaign.json", ok)


func _test_wrapping() -> void:
	var s := _session(1)
	var missing := TutorialActions.observe_watched(s.actions)
	var all_wrapped := true
	for id: String in TutorialSystem.watched_actions():
		all_wrapped = all_wrapped and TutorialActions.is_observed(s.actions, StringName(id))
	_check("actions: every action the tutorial watches is registered and observed (TutorialActions registered last): %s" % ", ".join(TutorialSystem.watched_actions()),
		missing.is_empty() and all_wrapped and TutorialSystem.watched_actions().has("cassette_select"), "missing %s" % str(missing))


# ================================================================ the flow, solo

func _test_solo_flow() -> void:
	var s := _tutorial_session(1, 4242)
	var st := s.state
	_stand_in_rules(s)
	_tick(s, 0.4)
	var heard := _heard(s)
	_check("arrival: tutorial mode, step 1, Mission Control speaks first (welcome to Mars in the 2060s, the crew radio is down)",
		TutorialSystem.tutorial_active(st) and TutorialSystem.current_stage(st) == 1 and heard.size() >= 2
		and String(heard[0]).begins_with("Mission Control: Welcome to Mars") and String(heard[1]).contains("radio is broken"), str(heard))
	_check("arrival: still outside, so the step stays open", String(TutorialSystem.current_objective(st).get("id", "")) == "arrival_inside" and st.character(&"crew_1").outside)
	_go(s, &"crew_1", s.config.hub_position)
	_tick(s, 0.4)
	_check("arrival: walking into the base finishes step 1; step 2 asks for the 6 tapes", TutorialSystem.current_stage(st) == 2
		and String(TutorialSystem.current_objective(st).get("id", "")) == "tapes_found" and _count_heard(s, "Find all 6 tapes") == 1, str(_heard(s)))
	# find the tapes with the real pickup, play some on the way
	var found_counts: Array[int] = []
	var ids: Array = CassetteCatalog.TAPES.keys()
	for i in ids.size():
		var r := _collect(s, &"crew_1", String(ids[i]))
		if not r.ok:
			_notes.append("collect %s: %s %s" % [ids[i], r.reason, r.message])
		_tick(s, 0.2)
		found_counts.append(TutorialSystem.tapes_found(st))
	var view_after_find := TutorialPresenter.list_lines(st, 2)
	_check("tapes: 'Tapes found' counts 1/6 .. 6/6 with the real pickup, and Mission Control says when all are found",
		Array(found_counts) == [1, 2, 3, 4, 5, 6] and TutorialSystem.is_objective_done(st, "tapes_found") and _count_heard(s, "All 6 tapes found") == 1
		and String(TutorialSystem.current_objective(st).get("id", "")) == "tapes_played", "%s %s" % [found_counts, _heard(s)])
	var goal_card: Array = st.campaign.get("objectives", [])
	_check("tapes: the goal card shows 'Tapes found 6/6' and 'Tapes played 0/6'", goal_card.size() == 2 and String(goal_card[0].text) == "Tapes found" and String(goal_card[0].label) == "6/6"
		and String(goal_card[1].text) == "Tapes played" and String(goal_card[1].label) == "0/6" and view_after_find.size() == 6, str(goal_card))
	# playing away from the player is refused by the cassette rules; playing at the player counts once
	_go(s, &"crew_1", s.config.hub_position)
	var far := s.request(&"cassette_select", PLAYER, {"cassette_id": String(ids[0])}, 1)
	var played_counts: Array[int] = []
	for i in ids.size():
		var r := _play(s, &"crew_1", String(ids[i]))
		if not r.ok:
			_notes.append("play %s: %s %s" % [ids[i], r.reason, r.message])
		if i == 0:
			_play(s, &"crew_1", String(ids[0]))     # the same tape again counts once
		_tick(s, 0.2)
		played_counts.append(TutorialSystem.tapes_played(st))
		if i == 4:
			_check("tapes: no 'Fix the base' before every tape is played (5 of 6 played)", TutorialSystem.current_stage(st) == 2
				and _count_heard(s, "Fix the base") == 0)
	_check("tapes: 'Tapes played' counts 1/6 .. 6/6 at the Command Room player; a replay counts once; from afar it is refused",
		not far.ok and Array(played_counts) == [1, 2, 3, 4, 5, 6] and (TutorialSystem.tutorial_of(st).played as Array).size() == 6, "%s %s" % [played_counts, far.reason])
	s.request(&"cassette_close", PLAYER, {}, 1)
	_check("fix: once all 6 are played Mission Control says 'Fix the base: get it to operational condition.' (once) and step 3 opens",
		TutorialSystem.current_stage(st) == 3 and _count_heard(s, "Mission Control: Fix the base: get it to operational condition.") == 1
		and String(TutorialSystem.current_objective(st).get("id", "")) == "fix_all", str(_heard(s)))
	var lines := TutorialPresenter.list_lines(st, 3)
	var joined := "\n".join(lines)
	_check("fix: the list shows the 10 broken spots by room with the specialist each needs; T05 and T07 are not on it",
		lines.size() == 10 and joined.contains("Command Room: Fix the wires (⚡ Electrical and comms specialist)") and joined.contains("Med Bay: Fix the test-tube rack (✚ Medical and life support specialist)")
		and joined.contains("Hangar and airlock: Repair the air leak (⛏ Field engineering and geology specialist)") and joined.contains("Command Room: Fix the radio signal")
		and not joined.contains("Command Room: Fix the radio signal (") and not joined.contains("Elements") and not joined.contains("Pipes"), joined)
	var card: Array = st.campaign.get("objectives", [])
	_check("fix: the goal card lists the 6 rooms with their fixed counts", card.size() == 6 and String(card[0].text) == "Fix the Command Room" and String(card[0].label) == "0/2", str(card))
	# wrong specialist refused on the host; the right one fixes it
	var wrong := _fix(s, &"crew_1", "T09")
	_check("fix: the host refuses a specialised spot for the wrong specialist (T09 by the electrical specialist)", not wrong.ok and wrong.reason == &"wrong_specialty"
		and PuzzleRegistry.is_broken(st, "T09"), "%s %s" % [wrong.reason, wrong.message])
	_go(s, &"crew_1", s.config.hub_position)
	var counts: Array = []
	var last := _fix_all_solo(s, &"crew_1", counts)
	_check("fix: each of the 10 fixes counts once, in order (solo, switching to the medical and field specialists at the hub)",
		counts == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] and TutorialSystem.fixed_count(st) == 10 and last == &"crew_4", "%s" % [counts])
	_check("fix: Mission Control counts each fix ('... 3 of 10 fixed.') and says when a room is restored",
		_count_heard(s, "of 10 fixed.") == 10 and _count_heard(s, "3 of 10 fixed.") == 1 and _count_heard(s, "is restored!") == 6
		and _count_heard(s, "The Command Room is restored!") == 1, "\n".join(PackedStringArray(_heard(s))))
	var info := TutorialSystem.base_operational_info(st)
	var events: Array = _objective_events[s]
	_check("done: all 10 fixed finishes the tutorial; campaign.base_operational is set with at_hours; 'base_operational' fires exactly once",
		TutorialSystem.is_tutorial_done(st) and TutorialSystem.is_base_operational(st) and bool(info.done) and float(info.at_hours) > 0.0
		and _approx(float(info.at_hours), float(TutorialSystem.tutorial_of(st).done_at_hours)) and events.count("base_operational") == 1
		and _count_heard(s, "The base is operational!") == 1, "%s %s" % [info, events.count("base_operational")])
	_check("done: tutorial mode ends (stations unlocked, held doors released: GameMain reads is_tutorial_done)", not TutorialSystem.tutorial_active(st)
		and not TutorialLock.active(st))
	var power := _do(s, last, &"set_zone_power", POWER, {"zone": "Hangar bay", "on": false})
	_check("done: after the tutorial a locked station works again (power panel)", power.ok, "%s %s" % [power.reason, power.message])
	_tick(s, 1.0)
	_check("done: nothing fires twice later", (_objective_events[s] as Array).count("base_operational") == 1 and _count_heard(s, "The base is operational!") == 1)
	var card2: Array = st.campaign.get("objectives", [])
	_check("done: the goal card shows 'Base operational'", card2.size() == 1 and String(card2[0].text) == "Base operational" and bool(card2[0].done), str(card2))
	# reminders repeat Mission Control's lines of a finished step and change nothing
	var before := JSON.stringify(st.campaign)
	var remind := s.request(&"tutorial_replay", &"", {"stage": 2}, 1)
	_check("reminder: a finished step's Mission Control lines come back on request, and nothing changes", remind.ok and String(remind.changes.text).contains("Find all 6 tapes")
		and JSON.stringify(st.campaign) == before, String(remind.changes.get("text", remind.message)))


# ================================================================ order: early fixes, T05/T07

func _test_order() -> void:
	var s := _tutorial_session(1, 99)
	var st := s.state
	_stand_in_rules(s)
	_go(s, &"crew_1", s.config.hub_position)
	_tick(s, 0.4)
	var early := _fix(s, &"crew_1", "T01")
	_go(s, &"crew_1", s.config.hub_position)
	_tick(s, 0.4)
	_check("order: a broken spot fixed during the tapes step works and counts at once", early.ok and TutorialSystem.fixed_count(st) == 1 and TutorialSystem.current_stage(st) == 2, "%s %s" % [early.reason, early.message])
	for task: String in TEN:
		st.repair.tasks[task].first_completed = true      # synthetic set-up: every spot fixed before the tapes
	_tick(s, 0.4)
	_check("order: even with every spot fixed the tutorial waits for the tapes", not TutorialSystem.is_tutorial_done(st) and TutorialSystem.current_stage(st) == 2
		and TutorialSystem.tutorial_active(st))
	for id: String in CassetteCatalog.TAPES:
		_collect(s, &"crew_1", id)
		_play(s, &"crew_1", id)
	_tick(s, 0.4)
	_check("order: the last tape played then finishes it straight away (fix step done at once) with Base operational",
		TutorialSystem.is_tutorial_done(st) and TutorialSystem.is_base_operational(st) and TutorialSystem.is_stage_completed(st, 3))
	_check("order: T05 and T07 (no broken part) are never needed", not PuzzleRegistry.is_broken(st, "T05") and not PuzzleRegistry.is_broken(st, "T07")
		and not st.repair.tasks.T05.first_completed and not st.repair.tasks.T07.first_completed)


# ================================================================ station lock (host)

func _test_lock_host() -> void:
	var s := _tutorial_session(1, 321)
	var st := s.state
	_tick(s, 0.4)
	_go(s, &"crew_1", s.config.hub_position)
	_tick(s, 0.4)
	var power := _do(s, &"crew_1", &"set_zone_power", POWER, {"zone": "Hangar bay", "on": false})
	var solar := _do(s, &"crew_1", &"clean_panel", TRACKER)
	var record := _do(s, &"crew_1", &"read_record", &"pr_fsp_console")
	_check("lock: during the tutorial other stations are refused on the host with a plain message (power panel, sun tracker, record console)",
		not power.ok and power.reason == TutorialLock.REASON and power.message == TutorialLock.MESSAGE and not solar.ok and solar.reason == TutorialLock.REASON
		and not record.ok and record.reason == TutorialLock.REASON and st.is_zone_powered("Hangar bay"), "%s / %s / %s" % [power.reason, solar.reason, record.reason])
	var suit := _do(s, &"crew_1", &"begin_suit_check", SUITS, {"on": false})
	var tape := _collect(s, &"crew_1", "cassette_med_bay")
	var player := _do(s, &"crew_1", &"cassette_open", PLAYER)
	s.request(&"cassette_close", PLAYER, {}, 1)
	var gen := int(st.repair.tasks.T01.fault_generation)
	var broken := _do(s, &"crew_1", &"task_claim", &"repair_t01", {"generation": gen})
	var release := s.request(&"task_release", &"repair_t01", {"generation": gen}, 1)
	var t05 := _do(s, &"crew_1", &"task_claim", &"repair_t05", {"generation": int(st.repair.tasks.T05.fault_generation)})
	_check("lock: the suit rack, tape pickups, the cassette player and broken spots still work; releasing a spot always works; T05 (no broken part) is locked",
		suit.ok and tape.ok and player.ok and broken.ok and release.ok and not t05.ok and t05.reason == TutorialLock.REASON,
		"%s %s %s %s %s %s" % [suit.reason, tape.reason, player.reason, broken.reason, release.reason, t05.reason])
	var swap := _switch(s, &"crew_1", &"crew_2")
	_check("lock: the crew screen (C) at the hub still swaps crew", swap.ok and st.character(&"crew_2").owner_peer == 1, swap.message)
	_check("lock: what the HUD hides matches the host (power locked; suits, tapes, player and broken spots usable; fixed spots locked)",
		not TutorialLock.station_usable(st, st.stations[String(POWER)]) and TutorialLock.station_usable(st, st.stations[String(SUITS)])
		and TutorialLock.station_usable(st, st.stations["cassette_hangar"]) and TutorialLock.station_usable(st, st.stations[String(PLAYER)])
		and TutorialLock.station_usable(st, st.stations["repair_t02"]) and not TutorialLock.station_usable(st, st.stations["repair_t07"]))
	st.repair.tasks.T02.first_completed = true       # synthetic set-up: T02 fixed
	_check("lock: a fixed spot locks again until the base is fixed, with its own message", not TutorialLock.station_usable(st, st.stations["repair_t02"])
		and TutorialLock.message_for(st, st.stations["repair_t02"]) == TutorialLock.FIXED_MESSAGE)
	TutorialSystem.skip_tutorial(st, s.events)
	var after := _do(s, &"crew_2", &"set_zone_power", POWER, {"zone": "Hangar bay", "on": false})
	_check("lock: after the tutorial every station works as before (skipped tutorial: no Base operational moment)", after.ok and not st.is_zone_powered("Hangar bay")
		and TutorialSystem.is_tutorial_done(st) and not TutorialSystem.is_base_operational(st), after.message)
	# a simulation harness that never switches tutorial mode on keeps every station working
	var h := _session(1, 322)
	_tick(h, 0.4)
	var plain := _do(h, &"crew_1", &"set_zone_power", POWER, {"zone": "Hangar bay", "on": false})
	_check("lock: without tutorial mode (simulation harnesses) nothing is locked and the crew radio is up", plain.ok and not TutorialSystem.tutorial_active(h.state)
		and not CommsGate.voice_down(h.state), plain.message)


# ================================================================ crew radio gate

func _test_voice_gate() -> void:
	var s := _tutorial_session(2, 555)
	var st := s.state
	_stand_in_rules(s)
	_tick(s, 0.4)
	var down := CommsGate.voice_down(st)
	var vs := VoiceService.new()
	var gs_stub := GameServices.new()
	gs_stub.session = s
	vs.services = gs_stub
	var line_down := vs.own_line() if gs_stub.has_game() else CommsGate.MESSAGE
	_go(s, &"crew_1", s.config.hub_position)
	_tick(s, 0.4)
	var r := _fix(s, &"crew_1", "T01")
	_go(s, &"crew_1", s.config.hub_position)
	_tick(s, 0.4)
	var up := not CommsGate.voice_down(st) and not vs.comms_down()
	_check("voice: crew voice is down at the start of the tutorial with a clear line, and back once the T01 radio is fixed (Mission Control says so)",
		down and line_down == CommsGate.MESSAGE and r.ok and up and _count_heard(s, "your crew radio works") == 1, "%s %s %s" % [down, line_down, r.message])
	vs.free()
	gs_stub.free()


# ================================================================ save/load, replication, late join

func _test_save_and_late_join() -> void:
	var s := _tutorial_session(2, 777)
	var st := s.state
	_stand_in_rules(s)
	_tick(s, 0.4)
	_go(s, &"crew_1", s.config.hub_position)
	_go(s, &"crew_2", s.config.hub_position)
	_tick(s, 0.4)
	var ids: Array = CassetteCatalog.TAPES.keys()
	for i in 4:
		_collect(s, &"crew_1", String(ids[i]))
	for i in 2:
		_play(s, &"crew_2", String(ids[i]))
	s.request(&"cassette_close", PLAYER, {}, 2)
	_tick(s, 0.4)
	var s2 := _resume(s, _json(st))
	_tick(s2, 0.4)
	_check("save: mid-tapes the colony resumes at the same step with 4/6 found and 2/6 played; Mission Control does not repeat itself",
		TutorialSystem.current_stage(s2.state) == 2 and TutorialSystem.tapes_found(s2.state) == 4 and TutorialSystem.tapes_played(s2.state) == 2
		and TutorialSystem.tutorial_active(s2.state) and _heard(s2).is_empty(), "%d %d %s" % [TutorialSystem.tapes_found(s2.state), TutorialSystem.tapes_played(s2.state), _heard(s2)])
	# finish the tapes and fix some spots in the resumed colony
	s2.request(&"claim_character", &"crew_1", {}, 1)
	s2.request(&"claim_character", &"crew_2", {}, 2)
	_stand_in_rules(s2)
	for i in ids.size():
		_collect(s2, &"crew_1", String(ids[i]))
		_play(s2, &"crew_1", String(ids[i]))
	s2.request(&"cassette_close", PLAYER, {}, 1)
	_fix(s2, &"crew_1", "T01")
	_fix(s2, &"crew_1", "T02")
	_go(s2, &"crew_1", s2.config.hub_position)
	_tick(s2, 0.4)
	# a late joiner gets the host's state as a whole (ColonyState dictionary, as NetSession sends it)
	var client := ColonyState.from_dict(JSON.parse_string(JSON.stringify(s2.state.to_dict())))
	var same := (TutorialSystem.current_stage(client) == 3 and TutorialSystem.tapes_played(client) == 6 and TutorialSystem.fixed_count(client) == 2
		and TutorialPresenter.list_lines(client, 3) == TutorialPresenter.list_lines(s2.state, 3) and TutorialSystem.tutorial_active(client)
		and _same(client.campaign.objectives, s2.state.campaign.objectives) and TutorialSystem.last_message(client) == TutorialSystem.last_message(s2.state))
	var locks_same := true
	for sid: String in s2.state.stations:
		locks_same = locks_same and TutorialLock.station_usable(client, s2.state.stations[sid]) == TutorialLock.station_usable(s2.state, s2.state.stations[sid])
	_check("late join: a client sees the same step, counts, fix list, goal card, Mission Control line and station locks as the host", same and locks_same)
	var s3 := _resume(s2, _json(s2.state))
	_check("save: fixes and played tapes survive save/load (2 of 10 fixed, step 3)", TutorialSystem.current_stage(s3.state) == 3 and TutorialSystem.fixed_count(s3.state) == 2
		and TutorialSystem.tapes_played(s3.state) == 6)
	s3.request(&"claim_character", &"crew_1", {}, 1)
	s3.request(&"claim_character", &"crew_2", {}, 2)
	_stand_in_rules(s3)
	_fix_all_solo(s3, &"crew_1", [])
	var s4 := _resume(s3, _json(s3.state))
	_tick(s4, 0.4)
	var late := ColonyState.from_dict(JSON.parse_string(JSON.stringify(s4.state.to_dict())))
	_check("save + late join: Base operational and the finished tutorial survive save/load and reach a late joiner (no second moment)",
		TutorialSystem.is_base_operational(s4.state) and TutorialSystem.is_tutorial_done(s4.state) and TutorialSystem.is_base_operational(late)
		and not TutorialSystem.tutorial_active(late) and _heard(s4).is_empty() and _approx(float(TutorialSystem.base_operational_info(late).at_hours), float(TutorialSystem.base_operational_info(s3.state).at_hours)))


func _test_migration() -> void:
	var s := _session(1, 31)
	var st := s.state
	st.campaign = {"version": 1, "tutorial": {"stage": 10, "done": true, "done_at_hours": 5.0, "objectives": {}, "completed": {"10": {"at_hours": 5.0}}},
		"stage9": {"variant": "trackers_stopped", "injected": true}, "certification": {"status": "waiting"}}
	_tick(s, 0.4)
	_check("old saves: a colony that finished the old ten-stage tutorial stays finished (no locks, no Base operational moment), and stage 9 is retired",
		TutorialSystem.is_tutorial_done(st) and not TutorialSystem.tutorial_active(st) and not TutorialSystem.is_base_operational(st) and not st.campaign.has("stage9")
		and int(st.campaign.version) == TutorialSystem.VERSION)
	var s2 := _session(1, 32)
	s2.state.campaign = {"version": 1, "tutorial": {"stage": 4, "done": false, "objectives": {"arrival_walk": {"done": true}}, "completed": {"1": {}}}}
	_tick(s2, 0.4)
	_check("old saves: an unfinished old tutorial starts the new flow from the beginning",
		not TutorialSystem.is_tutorial_done(s2.state) and int(TutorialSystem.tutorial_of(s2.state).flow) == TutorialSystem.FLOW and TutorialSystem.current_stage(s2.state) == 2
		and not (TutorialSystem.tutorial_of(s2.state).objectives as Dictionary).has("arrival_walk"))


# ================================================================ colony goal after the tutorial (certification)

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


func _test_certification() -> void:
	var s := _session(1, 808)
	var st := s.state
	s.request(&"set_sol_minutes", &"", {"minutes": 5.0}, 1)
	_tick(s, 0.4)
	_check("certification: locked during the tutorial", String(TutorialSystem.certification_of(st).status) == "locked")
	TutorialSystem.skip_tutorial(st, s.events)        # synthetic set-up: the tutorial finished
	_tick(s, 0.6)
	var waiting := String(TutorialSystem.certification_of(st).status) == "waiting" and TutorialSystem.requirements_missing(st).size() == 6
	_make_sectors_work(s)                             # synthetic set-up: tier 1 everywhere and the first radio card
	_tick(s, 0.6)
	var cert := TutorialSystem.certification_of(st)
	_check("certification (kept after the base works): waits for all five sectors and the radio, then the sol starts", waiting and String(cert.status) == "running", str(cert))
	_game_hours(s, 0.5 * GameConfig.SOL_HOURS)
	var half := float(TutorialSystem.certification_of(st).elapsed_hours)
	s.recover_character(&"crew_1")
	_tick(s, 0.4)
	cert = TutorialSystem.certification_of(st)
	_check("certification: an emergency recovery restarts the sol (%.1f h were done) and keeps running" % half, half > 10.0 and float(cert.elapsed_hours) < 0.1
		and String(cert.status) == "running" and (cert.resets as Array).size() == 1, str(cert))
	var s2 := _resume(s, _json(st))
	for i in 1700:
		s2.advance(0.2)
		if String(TutorialSystem.certification_of(s2.state).status) == "complete":
			break
	cert = TutorialSystem.certification_of(s2.state)
	_check("certification: after save/load one full sol completes the first milestone", String(cert.status) == "complete"
		and float(cert.elapsed_hours) >= GameConfig.SOL_HOURS - 0.01, str(cert))


# ================================================================ story records

func _test_lore_runtime() -> void:
	var s := _session(1, 1234)
	var st := s.state
	_tick(s, 0.4)
	var stage_before := TutorialSystem.current_stage(st)
	var r1 := _do(s, &"crew_1", &"read_record", &"pr_fsp_console")
	var r2 := _do(s, &"crew_1", &"read_record", &"pr_fsp_console")
	var count := st.discoveries.size()
	var wrong := _do(s, &"crew_1", &"read_record", POWER)
	_go(s, &"crew_1", s.config.hub_position)
	var far := s.request(&"read_record", &"pr_fsp_console", {}, 1)
	_check("story: a record is found once by reading it at its console; reading again adds nothing; elsewhere or from afar it is refused",
		r1.ok and bool(r1.changes.new) and r2.ok and not bool(r2.changes.new) and count == 1 and TutorialSystem.is_found(st, "rec_power_console")
		and not wrong.ok and not far.ok and far.reason == &"too_far", "%s %s %s" % [r1.message, wrong.reason, far.reason])
	_do(s, &"crew_1", &"inspect_donor", &"pr_bat_rack_alarm")
	_do(s, &"crew_1", &"begin_suit_check", SUITS, {"on": true})
	_tick(s, 1.4)
	_do(s, &"crew_1", &"inspect_donor", &"sf_crash_tank")
	_do(s, &"crew_1", &"inspect_donor", &"sf_crash_tank", {"choice": "valve"})
	var discs := 0
	for d: Variant in st.discoveries:
		if d is Dictionary and String((d as Dictionary).id) == "disc_small_battery":
			discs += 1
	_check("story: inspecting salvage donors finds their records; three clues make the discovery, recorded once",
		discs == 1 and TutorialSystem.is_found(st, "rec_battery_rack") and TutorialSystem.is_found(st, "rec_crash_tank"))
	var copy := ColonyState.from_dict(_json(st))
	_check("story: discoveries survive save/load and change nothing in the tutorial or the colony stores", copy.discoveries.size() == st.discoveries.size()
		and TutorialSystem.current_stage(st) == stage_before and st.invariants_ok().is_empty())


# ================================================================ presentation (HUD, lock on screen, scrambled panel, journal)

func _test_presentation() -> void:
	var gs := GameServices.new()
	gs.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/test_tutorial"), "colony", 2)
	root.add_child(gs)
	gs.set_process(false)
	gs.start_new_game(4242)
	var stretch := root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	await process_frame
	root.size = Vector2i(1280, 720)
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
	gs.session.advance(0.4)
	for i in 3:
		await process_frame
	presenter.refresh()
	await process_frame
	var st := gs.state()
	var w := presenter.hud_widget
	var lines := "\n".join(w.lines())
	_check("hud: a new game is in tutorial mode (the presenter switches it on from the game's settings)", TutorialSystem.tutorial_active(st) and gs.config.tutorial_start_outside)
	_check("hud: the tracker is under the GameHud and shows Mission Control, step 1 and its newest line", w.get_parent() == game.hud and w.visible
		and lines.contains("Mission Control · step 1 of 3: Arrival") and lines.contains("Walk into the base") and lines.contains("“"), lines)
	var rect := w.get_global_rect()
	var top_right := game.hud.root_control().find_child("TopRight", true, false) as Control
	var top_left := game.hud.root_control().find_child("TopLeft", true, false) as Control
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var centre := Rect2(Vector2(640 - 120, 360 - 80), Vector2(240, 160))
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
	gs.report_position(me.id, gs.config.hub_position, 0.0)
	gs.session.advance(0.4)
	presenter._process(0.3)
	presenter.refresh()
	var after := (presenter.current_view().hints as PackedStringArray).size()
	_check("hud: a hint after 80 s without progress, a second on request (N), none once the step is done", timed == 1 and asked == 2 and after == 0
		and TutorialSystem.current_stage(st) == 2 and String(presenter.current_view().progress) == "Tapes found 0/6 · Tapes played 0/6", "%d %d %d %s" % [timed, asked, after, presenter.current_view().progress])
	# the [E] prompt: only tapes, broken spots and the suit rack
	var hud := game.hud
	hud.set_target({"kind": "station", "id": String(POWER)})
	var power_cue := hud.cue_text()
	hud.set_target({"kind": "station", "id": String(SUITS)})
	var suit_cue := hud.cue_text()
	hud.set_target({"kind": "station", "id": "repair_t02"})
	var broken_cue := hud.cue_text()
	hud.set_target({"kind": "station", "id": "cassette_med_bay"})
	var tape_cue := hud.cue_text()
	hud.set_target({"kind": "station", "id": "repair_t05"})
	var t05_cue := hud.cue_text()
	_check("hud: during the tutorial the power panel and T05 show no [E] prompt; the suit rack, a tape and a broken spot do",
		power_cue == "" and t05_cue == "" and suit_cue.begins_with("[E]") and broken_cue.begins_with("[E]") and tape_cue.begins_with("[E]"),
		"'%s' '%s' '%s' '%s' '%s'" % [power_cue, t05_cue, suit_cue, broken_cue, tape_cue])
	# a locked station's panel closes at once with the plain message; the cassette player stays open
	game.ui.open(StationPanels.for_station(POWER, gs))
	await process_frame
	await process_frame
	var said := "\n".join(hud.current_messages() + hud.waiting_messages()).contains("Not yet: Mission Control")
	var closed := game.ui.top() == null and presenter.closed_locked_panels == 1
	gs.report_position(me.id, CharacterState._v3(st.stations[String(SUITS)].position), 0.0)
	game.ui.open(StationPanels.for_station(SUITS, gs))
	await process_frame
	await process_frame
	var suits_open := game.ui.top() != null and presenter.closed_locked_panels == 1
	game.ui.close_all()
	gs.report_position(me.id, gs.config.hub_position, 0.0)
	_check("lock on screen: E on a locked station closes its panel at once and says why; the suit rack's panel stays open", closed and said and suits_open,
		"closed %s said %s suits %s: %s" % [closed, said, suits_open, hud.current_messages() + hud.waiting_messages()])
	# wrong specialist: the scrambled panel (crew_1 is the electrical specialist)
	var resolved := [0]
	gs.events.action_resolved.connect(func(_r: ActionResult) -> void: resolved[0] += 1)
	var t09 := PuzzleRegistry.make_panel("T09", &"repair_t09", gs) as TaskPanel
	game.ui.open(t09)
	await process_frame
	var buttons := t09.play_area.find_children("*", "BaseButton", true, false).size()
	var n_before: int = resolved[0]
	t09.submit_move({"move": "pour", "value": 1})
	var claim := t09.request_host(&"task_claim")
	var line := t09.unreadable_label.text if t09.unreadable_label != null else ""
	var scrambled := (t09.play_area.find_child("Scrambled", true, false) as Control)
	_check("scrambled panel: the wrong specialist sees the mini-game frame with scrambled symbols, no controls, and 'Only the ✚ Medical and life support specialist can read this. Press C to swap to them at the Med Bay hub.'",
		t09.unreadable and game.ui.top() == t09 and scrambled != null and scrambled.get_child_count() == 12 and buttons == 0 and not t09.reset_button.visible
		and line == "Only the ✚ Medical and life support specialist can read this. Press C to swap to them at the Med Bay hub.", "%s buttons=%d" % [line, buttons])
	_check("scrambled panel: no move is possible (nothing reaches the host)", not t09.pending and not claim.ok and resolved[0] == n_before, "%d %d" % [resolved[0], n_before])
	_check("scrambled panel: the scramble is the same for the same seed and unreadable (no words)", TaskPanel.scrambled_text(7, 8) == TaskPanel.scrambled_text(7, 8)
		and not TaskPanel.scrambled_text(7, 8).to_lower().contains("pour"))
	game.ui.close_all()
	var t02 := PuzzleRegistry.make_panel("T02", &"repair_t02", gs) as TaskPanel
	var t01 := PuzzleRegistry.make_panel("T01", &"repair_t01", gs) as TaskPanel
	_check("scrambled panel: the right specialist gets the real mini-game (T02 by the electrical specialist); a general task opens for anyone (T01)",
		t02 != null and not t02.unreadable and (t02.get_script() as Script).resource_path.ends_with("t02_panel.gd")
		and t01 != null and not t01.unreadable and (t01.get_script() as Script).resource_path.ends_with("t01_panel.gd"))
	t02.free()
	t01.free()
	# the journal fits every screen size and its buttons can be focused
	var layout := PackedStringArray()
	var journal := StoryLogPanel.new()
	journal.presenter = presenter
	journal.setup(gs)
	root.add_child(journal)
	journal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for sz: Array in SIZES:
		root.size = sz[0]
		_apply_text_scale(float(sz[1]))
		await process_frame
		await process_frame
		journal.refresh()
		await process_frame
		for l in UiLayoutCheck.problems(journal, Vector2(sz[0])):
			layout.append("journal at %s: %s" % [sz[0], l])
		var min_size := journal.get_combined_minimum_size()
		if min_size.x > float(sz[0].x) or min_size.y > float(sz[0].y):
			layout.append("journal at %s: minimum size %s is bigger than the screen" % [sz[0], min_size])
		for l in UiLayoutCheck.focus_problems(journal):
			layout.append("journal focus: %s" % l)
	_apply_text_scale(1.0)
	root.size = Vector2i(1280, 720)
	_check("journal: fits 1280x720, 1920x1080 and text 1.5; every button takes focus", layout.is_empty() and not UiLayoutCheck.focusable(journal).is_empty(), "\n  ".join(layout))
	_check("journal: shows Mission Control's log (the welcome line) and the step's tape checklist", journal._log_label.text.contains("Welcome to Mars")
		and journal._list_label.text.contains("Med Bay tape"), journal._log_label.text)
	# four players: nothing on the tracker asks to switch; the scrambled line names the other player
	for p in [2, 3, 4]:
		gs.session.peer_joined(p)
		gs.session.request(&"claim_character", StringName("crew_%d" % p), {}, p)
		gs.session.report_position(p, StringName("crew_%d" % p), gs.config.hub_position, 0.0)
	for id: String in CassetteCatalog.TAPES:
		(st.repair.collected_cassettes as Array).append(id)          # synthetic set-up: every tape found and played
		(TutorialSystem.tutorial_of(st).played as Array).append(id)
	gs.session.advance(0.4)
	presenter.refresh()
	var team_lines := "\n".join(presenter.hud_widget.lines())
	journal.refresh()
	var journal_text := journal._objective_label.text + " " + journal._cue_label.text + " " + journal._list_label.text
	var t09b := PuzzleRegistry.make_panel("T09", &"repair_t09", gs) as TaskPanel
	_check("hud: with four players the fix step lists who fixes what and nothing asks to switch; the scrambled line says another player plays the specialist",
		TutorialPresenter.switching_disabled(gs) and TutorialSystem.current_stage(st) == 3 and team_lines.contains("Fixed 0 of 10") and not _mentions_switch(team_lines)
		and not _mentions_switch(journal_text) and t09b.unreadable_label.text.contains("Another player plays them"), team_lines)
	t09b.free()
	# the held doors: GameMain reads the replicated tutorial state
	var gm := GameMain.new()
	gm.services = gs
	var held := gm.tutorial_doors_open()
	TutorialSystem.skip_tutorial(st, gs.events)
	var released := not gm.tutorial_doors_open()
	gm.free()
	hud.set_target({"kind": "station", "id": "cm_comms_console"})
	hud.refresh()
	hud.set_target({"kind": "station", "id": String(POWER)})
	_check("after the tutorial: the doors are released and the power panel shows its [E] prompt again", held and released and hud.cue_text().begins_with("[E]"), hud.cue_text())
	journal.queue_free()
	game.queue_free()
	root.content_scale_mode = stretch
	gs.saves.delete_all()
	gs.queue_free()
	await process_frame


## Applies a text scale (the same way tests\test_station_panels.gd does while UiTheme's scale is a stub).
func _apply_text_scale(sc: float) -> void:
	UiTheme.apply_text_scale(sc)
	var th := UiTheme.get_theme()
	var wanted := roundi(UiTheme.BASE_FONT_SIZE * sc)
	if sc != 1.0 and th.default_font_size == UiTheme.BASE_FONT_SIZE:
		th.default_font_size = wanted
	elif sc == 1.0:
		th.default_font_size = UiTheme.BASE_FONT_SIZE
