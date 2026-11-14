extends SceneTree
## Prompts 14/16: AGENT/TECHNICAL PLAYTEST (no human or child testers). Headless, real model, real actions only:
## crew move by host position reports, every objective is met by a real request or real colony state. No debug
## shortcut (no _skip_to, no direct state writes) is used to finish a task. Measures, per run: game hours and real
## requests ("steps") to each stage, refused requests with their reason text, hub trips, warnings and weather events.
## Run: Godot_console --headless --path . --script res://tools/playtest/playtest_run.gd [-- --tag=one|two]
## Writes user://playtest_<tag>.json and prints one "PT" line per run.

const MANIFEST := "res://data/colony_manifest.json"
const SUITS := &"al_suit_rack"
const COMPUTER := &"cm_colony_computer"
const COMMS := &"cm_comms_console"
const POWER := &"pw_panel"
const LS := &"ls_console"
const FOOD := &"gh_console"
const BED := &"gd_planter"
const GYM := &"rk_treadmill"
const TRACKER := &"sf_solar_tracker"
const DONOR := &"pr_swgr_burnt"
const SITE := &"site_east_rocks"
const ROLE_OF_STAGE := {6: &"crew_3", 8: &"crew_1", 10: &"crew_4"}

var _zones: ColonyZones
var _catalog: Dictionary
var _events: Array[GameEvents] = []
var _run: Dictionary = {}
var _runs: Array = []
var _problems := 0
## Sols of continued play after the tutorial (playtest one: 3; playtest two: 10, to reach a second weather event).
var _cont_sols := 3.0


func _initialize() -> void:
	PlayerInput.ensure_actions()
	TutorialSystem.reload()
	ProgressionSystem.reload()
	_zones = ColonyZones.from_manifest(MANIFEST)
	_catalog = StationCatalog.from_manifest(MANIFEST, _zones)
	var tag := "one"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
	var seeds := [4242, 7, 99] if tag == "one" else [4242, 7, 99, 2027]
	_cont_sols = 3.0 if tag == "one" else 10.0
	print("PT data_source %s" % WeatherArchive.active().source)
	for sd: int in seeds:
		_play(1, sd, true)
	for n in [2, 3, 4]:
		_hub_rules(n, 4242)
		_play(n, 4242, false)
	for sd: int in ([4242] if tag == "one" else [4242, 2027]):
		_storms(sd, 12.0)
	var f := FileAccess.open("user://playtest_%s.json" % tag, FileAccess.WRITE)
	f.store_string(JSON.stringify(_runs, "  "))
	f.close()
	print("PT file %s" % ProjectSettings.globalize_path("user://playtest_%s.json" % tag))
	print("RESULT %d runs, %d problems" % [_runs.size(), _problems])
	for ev in _events:
		ev.free()
	quit(0)


func _session(active: int, seed_value: int) -> SessionService:
	var ev := GameEvents.new()
	_events.append(ev)
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
	var clock := SolClock.new()
	clock.phase = s.config.start_phase
	s.begin(st, clock)
	for i in range(1, active):
		s.peer_joined(i + 1)
	for i in active:
		_req(s, &"claim_character", StringName("crew_%d" % (i + 1)), {}, i + 1)
	ev.weather_changed.connect(func(d: Dictionary) -> void:
		if not _run.is_empty():
			(_run.weather as Array).append({"h": snappedf(s.state.sim_hours, 0.01), "type": String(d.get("type", "")), "severity": float(d.get("severity", -1.0))}))
	return s


func _new_run(kind: String, players: int, seed_value: int) -> void:
	_run = {"kind": kind, "players": players, "seed": seed_value, "steps": 0, "blocked": [], "hub_trips": 0, "stages": [],
		"weather": [], "warnings": [], "notes": [], "stage9": ""}
	_runs.append(_run)


## Every player request goes through here: counted, refusals recorded with the reason text the player sees.
func _req(s: SessionService, action: StringName, target: StringName, params: Dictionary, peer: int) -> ActionResult:
	var r := s.request(action, target, params, peer)
	if not _run.is_empty():
		_run.steps = int(_run.steps) + 1
		if not r.ok:
			(_run.blocked as Array).append({"h": snappedf(s.state.sim_hours, 0.01), "action": String(action), "target": String(target),
				"reason": String(r.reason), "text": r.message})
	return r


func _peer(s: SessionService, crew: StringName) -> int:
	return s.state.character(crew).owner_peer


func _pos(s: SessionService, station: StringName) -> Vector3:
	return CharacterState._v3((s.state.stations[String(station)] as Dictionary).position)


func _go(s: SessionService, crew: StringName, p: Vector3) -> void:
	if p.distance_to(s.config.hub_position) < 0.5 and s.state.character(crew).position.distance_to(p) > 3.0:
		_run.hub_trips = int(_run.hub_trips) + 1
	s.report_position(_peer(s, crew), crew, p, 0.0)


func _do(s: SessionService, crew: StringName, action: StringName, station: StringName, params: Dictionary = {}) -> ActionResult:
	_go(s, crew, _pos(s, station))
	return _req(s, action, station, params, _peer(s, crew))


func _answer(s: SessionService, crew: StringName, station: StringName, qid: String) -> ActionResult:
	var choice := int(ProgressionSystem.current_variant(s.state, StringName(qid)).get("correct", 0))
	return _do(s, crew, &"answer_question", station, {"question_id": qid, "choice": choice})


func _tick(s: SessionService, seconds: float) -> void:
	for i in ceili(seconds / 0.2 - 1e-6):
		s.advance(0.2)


func _game_hours(s: SessionService, hours: float) -> void:
	_tick(s, hours / s.clock.hours_per_real_second())


func _switch(s: SessionService, from: StringName, to: StringName) -> ActionResult:
	var peer := _peer(s, from)
	_go(s, from, s.config.hub_position)
	return _req(s, &"claim_character", to, {}, peer)


func _stage(s: SessionService) -> int:
	return TutorialSystem.current_stage(s.state)


func _solve_stage9(s: SessionService, crew: StringName) -> bool:
	var st := s.state
	var s9 := TutorialSystem.stage9_of(st)
	_run.stage9 = String(s9.get("variant", ""))
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


## Who acts for a stage: the player who already plays the needed specialist; otherwise player 1 switches at the hub.
func _actor(s: SessionService, me: StringName, n: int) -> StringName:
	if not ROLE_OF_STAGE.has(n):
		return me
	var need: StringName = ROLE_OF_STAGE[n]
	if s.state.character(need).owner_peer > 0:
		return need
	if _switch(s, me, need).ok:
		return need
	return me


## The ten stages with real actions (the same steps as tests/test_tutorial.gd's solo run), then the post-tutorial
## sector work and the certification sol at the DEFAULT sol length.
func _play(players: int, seed_value: int, certify: bool) -> void:
	_new_run("tutorial%s" % ("+certification" if certify else ""), players, seed_value)
	var s := _session(players, seed_value)
	var st := s.state
	var me: StringName = &"crew_1"   # player 1 (peer 1)
	_tick(s, 0.4)
	var stage_start_h := st.sim_hours
	var stage_start_steps := 0
	for n in range(1, 11):
		match n:
			1:
				_go(s, me, st.character(me).position + Vector3(9.0, 0.0, 0.0))
				_tick(s, 0.4)
				_go(s, me, _pos(s, SUITS) + Vector3(0.5, 0.0, 0.0))
			2:
				_do(s, me, &"begin_suit_check", SUITS, {"on": true})
				_tick(s, 1.4)
				_go(s, me, _pos(s, TRACKER) + Vector3(2.0, 0.0, 0.0))
				s.note_airlock_cycle()
				_tick(s, 0.4)
				_go(s, me, _pos(s, SUITS))
			3:
				_go(s, me, s.config.hub_position)
				_tick(s, 0.4)
				_answer(s, me, COMPUTER, "energy_q_battery_night")
			4:
				_do(s, me, &"clean_panel", TRACKER)
				_tick(s, 0.4)
				_do(s, me, &"repair_cleaner", TRACKER)
				_tick(s, 0.4)
				_answer(s, me, POWER, "energy_q_dust_output")
			5:
				_answer(s, me, POWER, "energy_q_net_power")
				_tick(s, 0.4)
				_do(s, me, &"set_zone_power", POWER, {"zone": "Hangar bay", "on": false})
				_tick(s, 0.4)
				_do(s, me, &"set_water_allocation", LS, {"electrolysis_feed_l_per_hour": 1.0})
				_do(s, me, &"set_equipment", LS, {"equipment": "electrolyser", "on": true})
				_do(s, me, &"set_equipment", LS, {"equipment": "co2_unit", "on": true})
				_tick(s, 0.4)
				_answer(s, me, LS, "ls_q_two_paths")
			6:
				var a := _actor(s, me, 6)
				if _peer(s, a) == 1: me = a
				_do(s, a, &"plant", BED, {"crop": "lettuce"})
				_tick(s, 0.4)
				_do(s, a, &"set_greenhouse_water", FOOD, {"greenhouse_l_per_hour": 1.0})
				_tick(s, 0.4)
				_do(s, a, &"inspect_bed", BED)
				_tick(s, 0.4)
				_answer(s, a, FOOD, "food_q_light")
			7:
				_do(s, me, &"exercise", GYM)
				_tick(s, 0.4)
				if st.character(me).suit_charge < 95.0:
					_do(s, me, &"refill_suit", SUITS)
			8:
				var a := _actor(s, me, 8)
				if _peer(s, a) == 1: me = a
				_go(s, a, _pos(s, COMMS))
				_tick(s, 0.4)
				var c := ProgressionSystem.card(&"comms_radio_1")
				for q in c.questions:
					_answer(s, a, COMMS, String(q))
				_do(s, a, &"install_upgrade", COMMS, {"upgrade_id": "comms_radio_1"})
			9:
				_solve_stage9(s, &"crew_1" if _peer(s, &"crew_1") > 0 else me)
				_game_hours(s, 1.3)
			10:
				_go(s, me, s.config.hub_position)
				_tick(s, 0.4)
				var a := _actor(s, me, 10)
				if _peer(s, a) == 1: me = a
				_tick(s, 0.4)
				_do(s, a, &"inspect_donor", DONOR)
		_tick(s, 0.6)
		var reached := _stage(s) == n + 1 or (n == 10 and TutorialSystem.is_tutorial_done(st))
		(_run.stages as Array).append({"stage": n, "done": reached, "game_h": snappedf(st.sim_hours - stage_start_h, 0.001),
			"steps": int(_run.steps) - stage_start_steps, "at_h": snappedf(st.sim_hours, 0.001)})
		stage_start_h = st.sim_hours
		stage_start_steps = int(_run.steps)
		if not reached:
			(_run.notes as Array).append("stage %d did not finish; open objective %s" % [n, TutorialSystem.current_objective(st).get("id", "")])
			_problems += 1
			print("PT %s" % JSON.stringify(_run))
			return
	_run["tutorial_done_h"] = snappedf(st.sim_hours, 0.001)
	if not certify:
		print("PT %s" % JSON.stringify(_run))
		return
	# post-tutorial sector work with the field engineer (crew_4), real actions only
	var fe: StringName = &"crew_4"
	_do(s, fe, &"adjust_nutrients", BED, {"level": 0.2})
	_tick(s, 0.4)
	_do(s, fe, &"inspect_bed", BED)
	_answer(s, fe, FOOD, "food_q_symptom")
	_do(s, fe, &"adjust_nutrients", BED, {"level": 0.7})
	_do(s, fe, &"inspect_donor", DONOR, {"choice": "relay"})
	_answer(s, fe, COMPUTER, "res_q_compatible")
	_do(s, fe, &"begin_suit_check", SUITS, {"on": true})
	_tick(s, 1.4)
	_do(s, fe, &"take_sample", SITE)
	_go(s, fe, _pos(s, SUITS))
	_answer(s, fe, COMPUTER, "sci_q_context")
	_game_hours(s, 1.2)
	_run["requirements_missing"] = TutorialSystem.requirements_missing(st)
	# certification at the default sol length, then continued play to 3 sols; warnings acknowledged like a player would
	var lowest := INF
	var limit_h := st.sim_hours + _cont_sols * GameConfig.SOL_HOURS
	var acked := false
	while st.sim_hours < limit_h:
		s.advance(0.2)
		for k: StringName in TutorialSystem.RESERVES:
			lowest = minf(lowest, st.store(k))
		var warned := String(st.weather.get("phase", "")) == "warned"
		if warned and not acked:
			(_run.warnings as Array).append({"h": snappedf(st.sim_hours, 0.01)})
			_req(s, &"acknowledge_weather_warning", &"", {}, 1)
			acked = true
		elif not warned:
			acked = false
		if String(TutorialSystem.certification_of(st).status) == "complete" and not _run.has("certified_h"):
			_run["certified_h"] = snappedf(st.sim_hours, 0.001)
	var cert := TutorialSystem.certification_of(st)
	_run["certification"] = String(cert.status)
	_run["lowest_reserve"] = snappedf(lowest, 0.001)
	_run["end_h"] = snappedf(st.sim_hours, 0.001)
	_run["invariants"] = st.invariants_ok()
	if String(cert.status) != "complete":
		_problems += 1
	print("PT %s" % JSON.stringify(_run))


## Hub-only switching rules with n players: away from the hub refused, an occupied crew member refused, a free one at
## the hub accepted (n < 4); with 4 players nobody is free.
func _hub_rules(n: int, seed_value: int) -> void:
	_new_run("hub_rules", n, seed_value)
	var s := _session(n, seed_value)
	_tick(s, 0.4)
	_go(s, &"crew_1", _pos(s, SUITS))
	var away := _req(s, &"claim_character", StringName("crew_%d" % mini(n + 1, 4)), {}, 1)
	_go(s, &"crew_1", s.config.hub_position)
	var occupied := _req(s, &"claim_character", &"crew_2", {}, 1)
	var free_ok := true
	if n < 4:
		free_ok = _req(s, &"claim_character", StringName("crew_%d" % (n + 1)), {}, 1).ok
	_run["away_refused"] = not away.ok
	_run["occupied_refused"] = not occupied.ok
	_run["free_at_hub_ok"] = free_ok
	if away.ok or occupied.ok or not free_ok:
		_problems += 1
	print("PT %s" % JSON.stringify(_run))


## Continued play with an idle colony for `sols` sols at the default sol length: every weather event (warning, start,
## end) with its severity, the warning lead, and the lowest value of each reserve (shortage check). Warnings are
## acknowledged like a player would; nothing else is done (the colony runs on its starting settings).
func _storms(seed_value: int, sols: float) -> void:
	_new_run("storm_sequence", 1, seed_value)
	var s := _session(1, seed_value)
	var st := s.state
	var lowest := {}
	var acked := false
	var limit_h := st.sim_hours + sols * GameConfig.SOL_HOURS
	while st.sim_hours < limit_h:
		s.advance(0.2)
		for k: StringName in TutorialSystem.RESERVES:
			lowest[String(k)] = minf(float(lowest.get(String(k), INF)), st.store(k))
		var warned := String(st.weather.get("phase", "")) == "warned"
		if warned and not acked:
			_req(s, &"acknowledge_weather_warning", &"", {}, 1)
			acked = true
		elif not warned:
			acked = false
	for k in lowest:
		lowest[k] = snappedf(float(lowest[k]), 0.001)
	_run["lowest_by_reserve"] = lowest
	_run["end_h"] = snappedf(st.sim_hours, 0.01)
	print("PT %s" % JSON.stringify(_run))
