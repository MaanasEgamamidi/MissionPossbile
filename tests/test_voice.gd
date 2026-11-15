extends SceneTree
## Prompt 11, voice worker: radio stages and cards, the router (proximity, doors, radio, rover seats), the packet
## format, the timed buffer (delay, order, disorder, loss, FEC, bounds, clearing), a real TwoVoIP Opus round trip,
## three headless machines over ENet (relay, routing, stage delay, mute, disconnect, session exit), the HUD corner,
## the voice settings and the credits.
## Run: ..\godot.cmd --headless --path . --script res://tests/test_voice.gd
## SYNTHETIC: there is no microphone and no speaker in a headless run. Speech is a generated 440 Hz sine; "heard"
## means decoded into the Opus playback buffer. Nothing here proves microphone-to-ear usability with real players.
## Latency numbers are in-process only (all machines in one process on 127.0.0.1); they are not LAN measurements.

const MANIFEST := "res://data/colony_manifest.json"
const PORT := 24811
## Godot points: inside the mess hall (Blender x 0..14, y 6..18) and outside on the east tracker field.
const MESS_A := Vector3(5.0, 0.0, -10.0)
const MESS_B := Vector3(7.0, 0.0, -10.0)
const MESS_C := Vector3(9.0, 0.0, -12.0)
const OUTSIDE := Vector3(52.0, 0.0, 0.0)
const OUTSIDE_2 := Vector3(54.0, 0.0, 3.0)
## Hangar bay (the garage): Blender x 14..30, y -2..8.
const HANGAR := Vector3(20.0, 0.0, -3.0)


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
var _zones: ColonyZones
var _catalog: Dictionary
var _event_nodes: Array[GameEvents] = []
var _catcher := ErrorCatcher.new()
var _tmp := ""
var _phase := 0.0


func _check(label: String, condition: bool, detail: String = "state mismatch") -> void:
	_total += 1
	if condition:
		_passed += 1
		print("PASS " + label)
	else:
		print("FAIL " + label + ": " + detail)


func _info(text: String) -> void:
	print("INFO " + text)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.add_logger(_catcher)
	PlayerInput.ensure_actions()
	_tmp = ProjectSettings.globalize_path("res://").path_join("_test_saves/voice")
	DirAccess.make_dir_recursive_absolute(_tmp)
	_zones = ColonyZones.from_manifest(MANIFEST)
	_catalog = StationCatalog.from_manifest(MANIFEST, _zones)
	print("INFO SYNTHETIC test: no microphone, no speaker; speech is a generated sine and 'heard' means decoded.")

	_test_stages()
	_test_cards()
	_test_install_flow()
	_test_router_distance()
	_test_router_doors()
	_test_router_inside_outside()
	_test_router_rover()
	_test_packets()
	_test_schedule_delay_and_order()
	_test_schedule_disorder_loss()
	_test_schedule_upgrade_mid_utterance()
	_test_schedule_stall_timeout()
	_test_schedule_bounds()
	_test_schedule_clearing()
	_test_schedule_two_speakers()
	_test_schedule_latency()
	_test_opus_round_trip()
	_test_mic_auto_gain()
	_test_settings_file()
	_test_sources_and_privacy()
	await _test_net()
	await _test_hud_and_panels()

	_check("no script or engine errors during the test", _catcher.errors.is_empty(), "\n".join(_catcher.errors))
	OS.remove_logger(_catcher)
	for node: GameEvents in _event_nodes:
		node.free()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


# ================================================================ helpers

func _frames(n := 2) -> void:
	for i in n:
		await process_frame


func _until(cond: Callable, seconds := 5.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return bool(cond.call())


## A host session on the real map, crew 1..active controlled by peers 1..active.
func _session(active := 1) -> SessionService:
	var ev := GameEvents.new()
	_event_nodes.append(ev)
	var s := SessionService.new(GameConfig.new(), GameBalance.new(), ev)
	var st := ColonyState.new_game(s.balance, 4242, _zones.names)
	st.stations = _catalog.duplicate(true)
	var game_clock := SolClock.new()
	game_clock.phase = s.config.start_phase
	s.begin(st, game_clock)
	for i in active:
		st.character(StringName("crew_%d" % (i + 1))).owner_peer = i + 1
		if i > 0:
			s.peer_joined(i + 1)
	return s


func _person(pos: Vector3, outside := false, zone := "") -> Dictionary:
	return {"id": &"x", "position": pos, "outside": outside, "zone": zone, "seated": false}


func _install(st: ColonyState, n: int) -> void:
	for i in CommsStage.CARD_IDS.size():
		if i < n:
			st.upgrades[CommsStage.CARD_IDS[i]] = {"installed": true}
		else:
			st.upgrades.erase(CommsStage.CARD_IDS[i])


## A synthetic 440 Hz sine chunk of `frames` frames at the input mix rate (continuous phase across calls).
func _sine_chunk(frames: int, amplitude := 0.5) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	var rate := AudioServer.get_input_mix_rate()
	for i in frames:
		var s := amplitude * sin(_phase)
		_phase += TAU * 440.0 / rate
		out[i] = Vector2(s, s)
	return out


## Releases scheduler events between t0 and t1 in 5 ms steps; returns [[time, event], ...].
func _drain(sch: VoiceScheduler, t0: float, t1: float, step := 0.005) -> Array:
	var out := []
	var t := t0
	while t <= t1 + 1e-9:
		for e: Dictionary in sch.pop_due(t):
			out.append([t, e])
		t += step
	return out


func _frames_of(events: Array) -> Array:
	return events.filter(func(x: Array) -> bool: return (x[1] as Dictionary).type == &"frame")


func _fake_frame(stream: int, seq: int, index: int, start_ms: int, send_ms: int) -> PackedByteArray:
	return VoiceScheduler.make_frame(stream, seq, index, start_ms, send_ms, "crew_2", PackedByteArray([0xf8, 0xff, 0xfe, index & 0xff]))


# ================================================================ stages and cards

## Microphone auto-gain (2026-11-15): quiet speech is lifted toward the target, loud input is never pushed past full
## scale, and room silence does not raise the gain.
func _test_mic_auto_gain() -> void:
	var g := VoiceService.MIC_START_GAIN
	for i: int in 200:                                 # 4 s of quiet speech, peak 0.03
		g = VoiceService.next_mic_gain(g, 0.03)
	var quiet := VoiceService.chunk_peak(VoiceService.apply_mic_gain(_sine_chunk(882, 0.03), g))
	_check("mic gain: quiet speech (peak 0.03) is lifted to %.2f (gain %.1fx, at most %.0fx)" % [quiet, g, VoiceService.MIC_MAX_GAIN],
		quiet > 0.4 and g <= VoiceService.MIC_MAX_GAIN)
	var held := VoiceService.next_mic_gain(5.0, 0.001)
	_check("mic gain: silence below the speech floor holds the gain (no hiss pumping)", is_equal_approx(held, 5.0))
	var loud_g := VoiceService.next_mic_gain(16.0, 0.9)
	var loud := VoiceService.chunk_peak(VoiceService.apply_mic_gain(_sine_chunk(882, 0.9), loud_g))
	_check("mic gain: a shout drops the gain at once and never clips (peak %.3f)" % loud, loud_g <= 1.0 and loud < 1.0)
	var hot := VoiceService.chunk_peak(VoiceService.apply_mic_gain(_sine_chunk(882, 0.5), 16.0))
	var mac := PackedStringArray(["Default", "Tribit XSound Go (108)", "Steam Streaming Microphone (74)", "MacBook Air Microphone (97)"])
	_check("built-in mic: picked over a Bluetooth speaker and Steam's virtual mic", VoiceService.built_in_device(mac) == "MacBook Air Microphone (97)", VoiceService.built_in_device(mac))
	var win := PackedStringArray(["Default", "Headset Microphone (AirPods Hands-Free)", "Microphone Array (Realtek(R) Audio)"])
	_check("built-in mic: a laptop's microphone array on Windows, not the AirPods", VoiceService.built_in_device(win) == "Microphone Array (Realtek(R) Audio)", VoiceService.built_in_device(win))
	_check("built-in mic: none recognised means no microphone (never Default)", VoiceService.built_in_device(PackedStringArray(["Default", "USB Audio (3)"])) == "")
	_check("mic gain: the soft limiter keeps an over-boosted chunk under full scale (%.3f)" % hot, hot <= 1.0 and hot > VoiceService.MIC_KNEE)


func _test_stages() -> void:
	var delays: Array = []
	for s in 5:
		delays.append(CommsStage.delay_seconds(s))
	_check("stages: delays 0..4 are no link, 30, 15, 5, 0 s", delays == [-1.0, 30.0, 15.0, 5.0, 0.0] and not CommsStage.has_link(0)
		and CommsStage.has_link(1) and CommsStage.has_link(4), str(delays))
	var st := ColonyState.new_game(GameBalance.new(), 1, _zones.names)
	var counted: Array = []
	for n in 5:
		_install(st, n)
		counted.append(CommsStage.stage(st))
	st.upgrades.clear()
	st.upgrades["comms_radio_2"] = {"installed": true}
	_check("stages: stage counts the cards installed in order (only card 2 installed is still stage 0)", counted == [0, 1, 2, 3, 4] and CommsStage.stage(st) == 0, str(counted))
	_check("stages: words for the HUD", CommsStage.stage_text(0).contains("no radio link") and CommsStage.stage_text(2).contains("after 15 s")
		and CommsStage.stage_text(4).contains("almost at once") and CommsStage.explanation().contains("not the computer network")
		and CommsStage.explanation().contains("Earth"), CommsStage.stage_text(2))


func _test_cards() -> void:
	ProgressionSystem.reload()
	var bad := PackedStringArray()
	var words := ["30 s", "15 s", "5 s", "almost at once"]
	for i in CommsStage.CARD_IDS.size():
		var id := CommsStage.CARD_IDS[i]
		var c := ProgressionSystem.card(StringName(id))
		if c == null:
			bad.append(id + " missing")
			continue
		if c.cost_parts != i + 1 or c.cost_parts != CommsStage.CARD_PARTS[i]:
			bad.append("%s cost %d" % [id, c.cost_parts])
		if c.specialty != &"electrical_comms" or c.install_kind != "comms" or String(c.install_station) != CommsStage.INSTALL_STATION:
			bad.append("%s installer/station" % id)
		if c.sector != "energy" or c.tier != i:
			bad.append("%s sector %s tier %d" % [id, c.sector, c.tier])
		var want_pre: Array[StringName] = []
		if i > 0:
			want_pre.append(StringName(CommsStage.CARD_IDS[i - 1]))
		if c.prerequisites != want_pre:
			bad.append("%s prerequisites %s" % [id, c.prerequisites])
		if not c.effect.contains(String(words[i])) or not c.effect.contains("Earth"):
			bad.append("%s effect words" % id)
		if c.questions.size() < 2 or c.evidence.is_empty():
			bad.append("%s questions/evidence" % id)
		for q in c.questions:
			var qd := ProgressionSystem.question(q)
			if qd.is_empty() or String(qd.sector) != "energy" or (qd.variants as Array).size() < 2:
				bad.append("%s question %s" % [id, q])
		for e in c.evidence:
			if not (ProgressionSystem.catalogue().evidence as Dictionary).has(String(e)):
				bad.append("%s evidence %s" % [id, e])
	_check("cards: comms_radio_1..4 cost 1-4 parts, electrical specialist at the comms console, chained in order, energy levels 0-3", bad.is_empty(), "; ".join(bad))
	var one := ProgressionSystem.card(&"comms_radio_1")
	_check("cards: the effect says the delay is the radio's buffering, not network delay and not Earth-Mars light time",
		one != null and one.effect.contains("buffering") and one.effect.contains("not network delay") and one.effect.contains("light time"), one.effect if one != null else "")
	var check_q := ProgressionSystem.question(&"comms_q_radio_check")
	_check("cards: the practical evidence is the radio check answered at the comms console (existing answer_question action)",
		String(check_q.get("records_evidence", "")) == "comms_radio_check" and String(check_q.get("answer_at_kind", "")) == "comms"
		and String(_catalog.get(CommsStage.INSTALL_STATION, {}).get("kind", "")) == "comms")
	var retry_ok := true
	for qid: String in ["comms_q_buffer_delay", "comms_q_radio_check", "comms_q_earth_delay", "comms_q_inside_outside", "comms_q_plan_delay"]:
		var q := ProgressionSystem.question(StringName(qid))
		var texts := {}
		for v: Dictionary in q.get("variants", []):
			texts[String(v.text)] = true
			retry_ok = retry_ok and (v.answers as Array).size() == 3 and String(v.explanation).length() >= 20
		retry_ok = retry_ok and texts.size() >= 2
	_check("cards: every radio question has 3 answers, an explanation and a different retry variant", retry_ok)


func _test_install_flow() -> void:
	var s := _session(2)
	var st := s.state
	var sparky: CharacterState = null
	var other: CharacterState = null
	for c: CharacterState in st.characters.values():
		if c.specialty == &"electrical_comms":
			sparky = c
		elif other == null:
			other = c
	sparky.owner_peer = 1
	other.owner_peer = 2
	var console := CommsStage.INSTALL_STATION
	var at := CharacterState._v3(st.stations[console].position)
	sparky.position = at
	other.position = at
	st.parts = 20
	var r0 := s.request(&"install_upgrade", StringName(console), {"upgrade_id": "comms_radio_1"}, 1)
	var answers_ok := true
	for qid: String in ["comms_q_buffer_delay", "comms_q_radio_check"]:
		var choice := int(ProgressionSystem.current_variant(st, StringName(qid)).get("correct", 0))
		answers_ok = s.request(&"answer_question", StringName(console), {"question_id": qid, "choice": choice}, 1).ok and answers_ok
	var evidence := st.evidence.has("comms_radio_check")
	var wrong_person := s.request(&"install_upgrade", StringName(console), {"upgrade_id": "comms_radio_1"}, 2)
	var r1 := s.request(&"install_upgrade", StringName(console), {"upgrade_id": "comms_radio_1"}, 1)
	_check("install: the radio check answered at the comms console records the evidence; only the electrical specialist installs card 1 -> stage 1",
		not r0.ok and answers_ok and evidence and not wrong_person.ok and wrong_person.reason == &"wrong_specialty" and r1.ok and CommsStage.stage(st) == 1
		and st.parts == 19, "%s / %s / %s / %s" % [r0.message, wrong_person.message, r1.message, st.parts])
	var choice2 := int(ProgressionSystem.current_variant(st, &"comms_q_earth_delay").get("correct", 0))
	s.request(&"answer_question", StringName(console), {"question_id": "comms_q_earth_delay", "choice": choice2}, 1)
	var r2 := s.request(&"install_upgrade", StringName(console), {"upgrade_id": "comms_radio_2"}, 1)
	_check("install: card 2 waits for Energy level 1 (the colony's electrical learning)", not r2.ok and r2.message.contains("Energy level 1"), r2.message)
	var st2 := _session(1).state
	st2.parts = 20
	for q: String in ["comms_q_earth_delay", "comms_q_radio_check"]:
		var v: Dictionary = ProgressionSystem.current_variant(st2, StringName(q))
		st2.knowledge[q] = {"by": "crew_1", "sector": "energy", "at_hours": 0.0, "variant": 0, "example": String(v.example)}
	st2.evidence["comms_radio_check"] = {"by": "crew_1"}
	st2.progress["tiers"] = {"energy": 1}
	var lacking := ProgressionSystem.missing(st2, ProgressionSystem.card(&"comms_radio_2"))
	_check("install: card 2 needs card 1 first (installed in order)", lacking.size() == 1 and String(lacking[0].kind) == "prerequisite", str(lacking))


# ================================================================ router

func _test_router_distance() -> void:
	var gains: Array = []
	for d: float in [0.0, 5.0, 15.0, 25.0, 30.0]:
		var r := VoiceRouter.decide(_person(Vector3.ZERO), _person(Vector3(d, 0.0, 0.0)), 1, [], {})
		gains.append(snappedf(float(r.gain), 0.0001))
	_check("router: same zone, gain 1 at 0 and 5 m, 0.5 at 15 m, silent at 25 and 30 m", gains == [1.0, 1.0, 0.5, 0.0, 0.0], str(gains))
	var smooth := true
	var last := 1.0
	for i in 41:
		var g := VoiceRouter.fade(5.0 + 0.5 * float(i))
		smooth = smooth and g <= last + 1e-9
		last = g
	_check("router: the fade from 5 to 25 m never rises", smooth)
	var a := VoiceRouter.participant(null, _char(MESS_A), _zones)
	var b := VoiceRouter.participant(null, _char(MESS_B), _zones)
	var r := VoiceRouter.decide(a, b, 0, [], {})
	_check("router: two people 2 m apart in the mess hall talk nearby at full level, even with no radio (stage 0)",
		a.zone == "Mess hall" and r.route == VoiceRouter.ROUTE_PROXIMITY and is_equal_approx(float(r.gain), 1.0) and float(r.delay_s) == 0.0, str(r))


func _char(pos: Vector3, outside := false, id := &"crew_9") -> CharacterState:
	var c := CharacterState.new()
	c.id = id
	c.position = pos
	c.outside = outside
	return c


func _test_router_doors() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var portals := VoiceRouter.portals_from_manifest(data, _zones)
	var door5: Dictionary = {}
	for p: Dictionary in portals:
		if int(p.door_id) == 5:
			door5 = p
	_check("router: 24 room doors become portals between two zones (door 5 joins the mess hall and the crew corridor)",
		portals.size() == 24 and not door5.is_empty() and (door5.zones as Array).has("Mess hall") and (door5.zones as Array).has("Crew corridor"),
		"%d portals, door 5 %s" % [portals.size(), door5])
	# speaker in the mess hall, listener in the crew corridor, both 3.6 m from door 5 at Godot (13, 0, -6)
	var s := VoiceRouter.participant(null, _char(Vector3(11.0, 0.0, -9.0)), _zones)
	var l := VoiceRouter.participant(null, _char(Vector3(11.0, 0.0, -3.0)), _zones)
	var open := VoiceRouter.decide(s, l, 1, portals, {5: 1.0})
	var half := VoiceRouter.decide(s, l, 1, portals, {5: 0.5})
	var shut := VoiceRouter.decide(s, l, 1, portals, {5: 0.0})
	var other_open := VoiceRouter.decide(s, l, 1, portals, {7: 1.0})
	var path := 2.0 * Vector2(2.0, 3.0).length()
	var expect := VoiceRouter.fade(path) * VoiceRouter.DOOR_FACTOR
	_check("router: through an open door, half level along speaker->door->listener (%.2f m): %.3f" % [path, expect],
		open.route == VoiceRouter.ROUTE_PROXIMITY and is_equal_approx(float(open.gain), expect) and int(open.via_door) == 5 and open.reason == "open_door", str(open))
	_check("router: a half-open door gives half of that, a closed door silence (reason door_closed), another room's door does not help",
		is_equal_approx(float(half.gain), expect * 0.5) and float(shut.gain) == 0.0 and shut.reason == "door_closed" and float(other_open.gain) == 0.0,
		"%s | %s | %s" % [half, shut, other_open])
	var med := VoiceRouter.participant(null, _char(Vector3(-6.0, 0.0, -12.0)), _zones)
	var corridor := VoiceRouter.participant(null, _char(Vector3(4.0, 0.0, -3.0)), _zones)
	var none := VoiceRouter.decide(med, corridor, 1, portals, {5: 1.0, 7: 1.0})
	_check("router: rooms with no door between them are silent (one door, not a chain of doors)",
		med.zone == "Med Bay" and corridor.zone == "Crew corridor" and float(none.gain) == 0.0 and none.reason == "other_zone", "%s %s %s" % [med.zone, corridor.zone, none])
	var tunnel := VoiceRouter.portal_from_door(901, Vector3(22.0, 1.5, 10.475), Vector3(0.0, 0.0, 1.0), _zones)
	_check("router: a door the manifest does not list (exit tunnel inner door 901) becomes a portal from its position",
		not tunnel.is_empty() and (tunnel.zones as Array).has("Airlock"), str(tunnel))


func _test_router_inside_outside() -> void:
	var inside := VoiceRouter.participant(null, _char(MESS_A), _zones)
	var out := VoiceRouter.participant(null, _char(OUTSIDE), _zones)
	var out2 := VoiceRouter.participant(null, _char(OUTSIDE_2), _zones)
	var rows := PackedStringArray()
	var ok: bool = inside.outside == false and out.outside == true
	for stage_n in 5:
		var a := VoiceRouter.decide(out, inside, stage_n, [], {})
		var b := VoiceRouter.decide(inside, out, stage_n, [], {})
		var c := VoiceRouter.decide(out, out2, stage_n, [], {})
		rows.append("%d: %s %.0f / %s / %s" % [stage_n, a.route, float(a.delay_s), b.route, c.route])
		if stage_n == 0:
			ok = ok and a.route == VoiceRouter.ROUTE_NONE and b.route == VoiceRouter.ROUTE_NONE and c.route == VoiceRouter.ROUTE_NONE and a.reason == "no_radio_link"
		else:
			var want := CommsStage.delay_seconds(stage_n)
			ok = ok and a.route == VoiceRouter.ROUTE_RADIO and b.route == VoiceRouter.ROUTE_RADIO and c.route == VoiceRouter.ROUTE_RADIO
			ok = ok and float(a.delay_s) == want and float(b.delay_s) == want and float(a.gain) == 1.0
			ok = ok and a.reason == "speaker_outside" and b.reason == "listener_outside"
	_check("router: outside->inside, inside->outside and outside->outside use the radio at the stage delay; stage 0 is silent", ok, "; ".join(rows))
	var far_inside := VoiceRouter.participant(null, _char(Vector3(-6.0, 0.0, -12.0)), _zones)
	var far := VoiceRouter.decide(out, far_inside, 2, [], {})
	_check("router: the radio is not spatial: an indoor listener anywhere on the map hears an outdoor speaker at full level", far.route == VoiceRouter.ROUTE_RADIO and float(far.gain) == 1.0)
	_check("router: the HUD words for the speaker", VoiceRouter.speaking_text(false, 2, 0) == "● Speaking nearby"
		and VoiceRouter.speaking_text(true, 2, 0) == "● Radio — heard after 15 s" and VoiceRouter.speaking_text(true, 0, 0).begins_with("✖ No radio link outside")
		and VoiceRouter.speaking_text(false, 1, 1).contains("crew outside hear you by radio after 30 s")
		and VoiceRouter.speaking_text(false, 0, 1).contains("cannot hear you (no radio link)") and VoiceRouter.speaking_text(true, 4, 0).contains("almost at once"))


func _test_router_rover() -> void:
	var st := ColonyState.new_game(GameBalance.new(), 2, _zones.names)
	RoverModel.ensure(st)
	var rider := st.character(&"crew_2")
	rider.position = MESS_A                 # where the body was last reported; seated, the rover's pose counts
	rider.outside = false
	st.rover["seats"] = ["crew_1", "crew_2", "", ""]
	st.rover["pose"] = {"position": [OUTSIDE.x, OUTSIDE.y, OUTSIDE.z], "quat": [0, 0, 0, 1]}
	var seated := VoiceRouter.participant(st, rider, _zones)
	var listener := VoiceRouter.participant(st, _char(MESS_B), _zones)
	var r := VoiceRouter.decide(seated, listener, 3, [], {})
	st.rover["pose"] = {"position": [HANGAR.x, HANGAR.y, HANGAR.z], "quat": [0, 0, 0, 1]}
	var parked := VoiceRouter.participant(st, rider, _zones)
	var mate := VoiceRouter.participant(st, _char(HANGAR + Vector3(2.0, 0.0, 0.0)), _zones)
	var r2 := VoiceRouter.decide(parked, mate, 3, [], {})
	st.rover["seats"] = ["", "", "", ""]
	var walking := VoiceRouter.participant(st, rider, _zones)
	_check("router: a rover passenger outside counts as outside (radio, 5 s at stage 3), even though their body was last inside",
		bool(seated.seated) and bool(seated.outside) and r.route == VoiceRouter.ROUTE_RADIO and float(r.delay_s) == 5.0, str(r))
	_check("router: seated in the rover parked in the garage is inside (nearby voice); getting out uses the body's own place",
		parked.zone == "Hangar bay" and not bool(parked.outside) and r2.route == VoiceRouter.ROUTE_PROXIMITY and is_equal_approx(float(r2.gain), 1.0)
		and walking.zone == "Mess hall" and not bool(walking.seated), "%s %s %s" % [parked, r2, walking])


# ================================================================ packets

func _test_packets() -> void:
	var start := VoiceScheduler.make_start(0xBEEF, 65535, 4000000000, 4000000020, "crew_3")
	var frame := VoiceScheduler.make_frame(7, 12, 345, 1000, 7900, "crew_3", PackedByteArray([1, 2, 3]))
	var end := VoiceScheduler.make_end(7, 12, 346, 1000, 8000, "crew_3")
	var hs := VoiceScheduler.parse(start)
	var hf := VoiceScheduler.parse(frame)
	var he := VoiceScheduler.parse(end)
	_check("packets: start, frame and end headers round trip (stream, sequence, frame number, times, character, format)",
		int(hs.kind) == VoiceScheduler.KIND_START and int(hs.stream) == 0xBEEF and int(hs.seq) == 65535 and int(hs.start_ms) == 4000000000
		and int(hs.send_ms) == 4000000020 and String(hs.character) == "crew_3" and int(hs.sample_rate) == 48000 and int(hs.frame_samples) == 960 and int(hs.channels) == 1
		and int(hf.kind) == VoiceScheduler.KIND_FRAME and int(hf.index) == 345 and int(hf.header_len) == VoiceScheduler.FIXED_HEADER + 6
		and frame.slice(int(hf.header_len)) == PackedByteArray([1, 2, 3]) and int(he.kind) == VoiceScheduler.KIND_END and int(he.index) == 346,
		"%s | %s | %s" % [hs, hf, he])
	_check("packets: elapsed time from the speaker's own clock (wraps at 32 bits)", is_equal_approx(VoiceScheduler.elapsed_s(hf), 6.9)
		and is_equal_approx(VoiceScheduler.elapsed_s(hs), 0.02) and is_equal_approx(VoiceScheduler.elapsed_s({"start_ms": 0xffffff00, "send_ms": 0x100}), 0.512))
	var broken := frame.duplicate()
	broken[0] = 0
	var no_payload := VoiceScheduler.make_header(VoiceScheduler.KIND_FRAME, 1, 1, 1, 0, 0, "x")
	var bad_kind := frame.duplicate()
	bad_kind[2] = 9
	var long_id := frame.duplicate()
	long_id[18] = 200
	_check("packets: anything malformed parses to nothing", VoiceScheduler.parse(broken).is_empty() and VoiceScheduler.parse(no_payload).is_empty()
		and VoiceScheduler.parse(bad_kind).is_empty() and VoiceScheduler.parse(long_id).is_empty() and VoiceScheduler.parse(PackedByteArray([0x56])).is_empty()
		and VoiceScheduler.parse(start.slice(0, start.size() - 1)).is_empty())
	_check("packets: sequence numbers wrap (0 is newer than 65535)", VoiceScheduler.seq_newer(0, 65535) and not VoiceScheduler.seq_newer(65535, 0)
		and VoiceScheduler.seq_newer(5, 4) and not VoiceScheduler.seq_newer(4, 4))
	_check("packets: a frame header is small (%d bytes with a 6-letter id); the largest start packet fits NetSession.VOICE_PACKET_MAX" % (VoiceScheduler.FIXED_HEADER + 6),
		VoiceScheduler.make_start(1, 1, 0, 0, "x".repeat(80)).size() <= NetSession.VOICE_PACKET_MAX and VoiceScheduler.FIXED_HEADER + 6 == 25)


# ================================================================ scheduler

func _test_schedule_delay_and_order() -> void:
	for stage_n: int in [1, 2, 3, 4]:
		var sch := VoiceScheduler.new()
		var delay := CommsStage.delay_seconds(stage_n)
		sch.open(2, 1, 1, VoiceRouter.ROUTE_RADIO, 100.0, delay, {}, 100.0)
		for i in 10:
			sch.push_frame(2, 1, 1, i, _fake_frame(1, 1, i, 0, i * 20), VoiceScheduler.FIXED_HEADER + 6, 100.0 + 0.02 * i)
		sch.end(2, 1, 1, 10, 100.25)
		var events := _drain(sch, 100.0, 100.0 + delay + 0.5)
		var frames := _frames_of(events)
		var early := false
		var order := []
		for x: Array in frames:
			var e: Dictionary = x[1]
			order.append(int(e.index))
			early = early or float(x[0]) + 1e-9 < 100.0 + delay + VoiceScheduler.JITTER_S + 0.02 * float(e.index)
		var first := float(frames[0][0]) if not frames.is_empty() else -1.0
		var ended: bool = not events.is_empty() and (events[-1][1] as Dictionary).type == &"end" and (events[-1][1] as Dictionary).reason == &"footer"
		_check("schedule: stage %d plays the 10 frames in order, never before start + %.0f s + reorder window + i x 20 ms (first at +%.3f s), then ends" % [stage_n, delay, first - 100.0],
			order == range(10) and not early and absf(first - (100.0 + delay + VoiceScheduler.JITTER_S)) < 0.006 and ended, "%s %s %s" % [order, early, ended])


func _test_schedule_disorder_loss() -> void:
	var sch := VoiceScheduler.new()
	sch.open(2, 1, 1, VoiceRouter.ROUTE_RADIO, 0.0, 5.0, {}, 0.0)
	# arrival order with disorder; frame 3 lost (4 is there: FEC), frames 6 and 7 lost (8 is there: 6 lost, 7 by FEC)
	for i: int in [0, 2, 1, 5, 4, 8, 9, 10, 11]:
		sch.push_frame(2, 1, 1, i, _fake_frame(1, 1, i, 0, i * 20), 25, 0.02 * i)
	var dup := sch.push_frame(2, 1, 1, 2, _fake_frame(1, 1, 2, 0, 40), 25, 0.3)
	sch.end(2, 1, 1, 12, 0.3)
	var events := _drain(sch, 0.0, 6.0)
	var seq := PackedStringArray()
	for x: Array in events:
		var e: Dictionary = x[1]
		match e.type:
			&"frame":
				seq.append(("F%d" if bool(e.fec) else "%d") % int(e.index))
			&"lost":
				seq.append("L%d" % int(e.index))
			&"start":
				seq.append("S")
			&"end":
				seq.append("E")
	var want := "S,0,1,2,F3,4,5,L6,F7,8,9,10,11,E"
	var fec_from_next := true
	for x: Array in events:
		var e: Dictionary = x[1]
		if e.type == &"frame" and bool(e.fec):
			fec_from_next = fec_from_next and VoiceScheduler.parse(e.packet).index == int(e.index) + 1
	var late := sch.push_frame(2, 1, 1, 3, _fake_frame(1, 1, 3, 0, 60), 25, 6.1)
	_check("schedule: disorder is put back in order; a missing frame with the next one present is rebuilt by FEC from the next packet; a gap is skipped as lost",
		",".join(seq) == want and fec_from_next and dup == &"duplicate" and sch.stats.fec == 2 and sch.stats.lost == 1, ",".join(seq))
	_check("schedule: a frame that comes after its time is dropped as late", late == &"unknown" or late == &"late", String(late))
	# the start packet was lost: the first packet seen is frame 3, sent 60 ms after the start (back-dated)
	var sch2 := VoiceScheduler.new()
	var h := VoiceScheduler.parse(_fake_frame(9, 4, 3, 1000, 1060))
	sch2.open(3, 9, 4, VoiceRouter.ROUTE_PROXIMITY, 50.0 - VoiceScheduler.elapsed_s(h), 0.0, {}, 50.0)
	for i in range(3, 8):
		sch2.push_frame(3, 9, 4, i, _fake_frame(9, 4, i, 1000, 1000 + 20 * i), 25, 50.0 + 0.02 * float(i - 3))
	sch2.end(3, 9, 4, 8, 50.2)
	var ev2 := _frames_of(_drain(sch2, 50.0, 51.0))
	var idx := ev2.map(func(x: Array) -> int: return int((x[1] as Dictionary).index))
	_check("schedule: when the start packet is lost, the first frame seen opens the utterance on the speaker's own timing (frames 0-1 lost, 2 by FEC)",
		idx == [2, 3, 4, 5, 6, 7] and bool((ev2[0][1] as Dictionary).fec) and absf(float(ev2[0][0]) - (49.94 + VoiceScheduler.JITTER_S + 0.04)) < 0.006, "%s %s" % [idx, ev2[0][0] if not ev2.is_empty() else -1])


func _test_schedule_upgrade_mid_utterance() -> void:
	var sch := VoiceScheduler.new()
	# utterance 1 starts at stage 1 (30 s) and lasts 2 s; the radio is upgraded to stage 3 (5 s) while it is waiting;
	# utterance 2 starts at t = 3 s at the new delay
	sch.open(2, 1, 1, VoiceRouter.ROUTE_RADIO, 0.0, CommsStage.delay_seconds(1), {}, 0.0)
	for i in 100:
		sch.push_frame(2, 1, 1, i, _fake_frame(1, 1, i, 0, i * 20), 25, 0.02 * i)
	sch.end(2, 1, 1, 100, 2.0)
	sch.open(2, 1, 2, VoiceRouter.ROUTE_RADIO, 3.0, CommsStage.delay_seconds(3), {}, 3.0)
	for i in 50:
		sch.push_frame(2, 1, 2, i, _fake_frame(1, 2, i, 3000, 3000 + i * 20), 25, 3.0 + 0.02 * i)
	sch.end(2, 1, 2, 50, 4.0)
	var events := _drain(sch, 0.0, 34.0, 0.01)
	var first_1 := -1.0
	var last_1 := -1.0
	var first_2 := -1.0
	var delays := {}
	for x: Array in events:
		var e: Dictionary = x[1]
		if e.type != &"frame":
			continue
		delays[int(e.seq)] = float(e.delay_s)
		if int(e.seq) == 1:
			last_1 = float(x[0])
			if first_1 < 0.0:
				first_1 = float(x[0])
		elif first_2 < 0.0:
			first_2 = float(x[0])
	_check("schedule: an upgrade mid-transmission keeps the old 30 s for speech already in the radio (first at %.2f s)" % first_1,
		first_1 >= 30.0 and float(delays.get(1, 0.0)) == 30.0, str(delays))
	_check("schedule: the next utterance uses the new 5 s but never overtakes the older one (it starts at %.2f s, after %.2f s)" % [first_2, last_1],
		float(delays.get(2, 0.0)) == 5.0 and first_2 >= last_1 and first_2 > 8.08 + 1.0, "%f %f" % [first_2, last_1])


func _test_schedule_stall_timeout() -> void:
	var sch := VoiceScheduler.new()
	sch.open(2, 1, 1, VoiceRouter.ROUTE_PROXIMITY, 0.0, 0.0, {}, 0.0)
	for i in 5:
		sch.push_frame(2, 1, 1, i, _fake_frame(1, 1, i, 0, i * 20), 25, 0.02 * i)
	var a := _drain(sch, 0.0, 0.5)
	# the network stalls 0.4 s; frames 5..9 then arrive together
	for i in range(5, 10):
		sch.push_frame(2, 1, 1, i, _fake_frame(1, 1, i, 0, i * 20), 25, 0.5)
	var b := _drain(sch, 0.505, 0.8)
	var first_after := float(_frames_of(b)[0][0]) if not _frames_of(b).is_empty() else -1.0
	var due5 := VoiceScheduler.JITTER_S + 5.0 * 0.02
	var idx := _frames_of(a + b).map(func(x: Array) -> int: return int((x[1] as Dictionary).index))
	_check("schedule: a stalled stream waits (no frame skipped), then goes on from the late frames, later than planned, never earlier",
		idx == range(10) and first_after >= 0.5 and first_after > due5 and sch.stats.stalls >= 1 and sch.stats.lost == 0, "%s first %.3f" % [idx, first_after])
	# the speaker goes away with no end packet
	var c := _drain(sch, 0.8, 0.5 + VoiceScheduler.STALL_S + 0.2, 0.01)
	var ended := c.filter(func(x: Array) -> bool: return (x[1] as Dictionary).type == &"end")
	_check("schedule: no packet for %.0f s and no end packet ends the utterance cleanly (timeout)" % VoiceScheduler.STALL_S,
		ended.size() == 1 and (ended[0][1] as Dictionary).reason == &"timeout" and sch.utterance_count() == 0 and sch.stats.timeouts == 1)


func _test_schedule_bounds() -> void:
	_check("bounds: 40 s per speaker = %d frames of 20 ms; above the longest delay (30 s)" % VoiceScheduler.MAX_QUEUE_FRAMES,
		VoiceScheduler.MAX_QUEUE_FRAMES == roundi(VoiceScheduler.MAX_QUEUE_S / VoiceScheduler.FRAME_S) and VoiceScheduler.MAX_QUEUE_S > CommsStage.delay_seconds(1))
	var sch := VoiceScheduler.new()
	for u in range(1, 18):
		sch.open(2, 1, u, VoiceRouter.ROUTE_RADIO, float(u), 30.0, {}, float(u))
		sch.push_frame(2, 1, u, 0, _fake_frame(1, u, 0, 0, 0), 25, float(u))
	var notes_ok := sch.notes.size() >= 1 and sch.notes[-1].contains("Dropped the oldest")
	_check("bounds: at most %d utterances wait per speaker; the 17th drops the oldest whole one with a note" % VoiceScheduler.MAX_UTTERANCES,
		sch.utterance_count(2) == VoiceScheduler.MAX_UTTERANCES and sch.stats.dropped_utterances == 1 and sch.classify(2, 1, 1) == &"old" and notes_ok, str(sch.notes))
	var sch2 := VoiceScheduler.new()
	for u in [1, 2]:
		sch2.open(2, 1, u, VoiceRouter.ROUTE_RADIO, float(u) * 30.0, 30.0, {}, 0.0)
		for i in 1200:
			sch2.push_frame(2, 1, u, i, _fake_frame(1, u, i, 0, i * 20), 25, 0.0)
	_check("bounds: more than %d frames waiting for one speaker drops the oldest utterance (%d left)" % [VoiceScheduler.MAX_QUEUE_FRAMES, sch2.queued_frames(2)],
		sch2.queued_frames(2) <= VoiceScheduler.MAX_QUEUE_FRAMES and sch2.utterance_count(2) == 1 and sch2.classify(2, 1, 2) == &"queued")
	var sch3 := VoiceScheduler.new()
	for p in [2, 3, 4, 5]:
		sch3.open(p, 1, 1, VoiceRouter.ROUTE_RADIO, float(p), 30.0, {}, 0.0)
		for i in 1600:
			sch3.push_frame(p, 1, 1, i, _fake_frame(1, 1, i, 0, i * 20), 25, 0.0)
	_check("bounds: all speakers together keep at most %d frames (%d now; the oldest speaker's utterance was dropped)" % [VoiceScheduler.MAX_TOTAL_FRAMES, sch3.queued_frames()],
		sch3.queued_frames() <= VoiceScheduler.MAX_TOTAL_FRAMES and sch3.utterance_count(2) == 0 and sch3.utterance_count(5) == 1)
	var sch4 := VoiceScheduler.new()
	sch4.open(2, 1, 1, VoiceRouter.ROUTE_RADIO, 0.0, 30.0, {}, 0.0)
	var r := sch4.push_frame(2, 1, 1, VoiceScheduler.MAX_UTTERANCE_FRAMES, _fake_frame(1, 1, 0, 0, 0), 25, 0.0)
	_check("bounds: a frame number beyond 60 s is rejected", r == &"rejected")


func _test_schedule_clearing() -> void:
	var sch := VoiceScheduler.new()
	sch.open(2, 1, 1, VoiceRouter.ROUTE_PROXIMITY, 0.0, 0.0, {}, 0.0)
	sch.open(3, 1, 1, VoiceRouter.ROUTE_RADIO, 0.0, 15.0, {}, 0.0)
	for i in 20:
		sch.push_frame(2, 1, 1, i, _fake_frame(1, 1, i, 0, i * 20), 25, 0.02 * i)
		sch.push_frame(3, 1, 1, i, _fake_frame(1, 1, i, 0, i * 20), 25, 0.02 * i)
	_drain(sch, 0.0, 0.15)
	var cleared := sch.clear_speaker(2, "muted")
	var after := sch.pop_due(0.2)
	var end_cleared := after.any(func(e: Dictionary) -> bool: return e.type == &"end" and e.reason == &"cleared" and int(e.peer) == 2)
	var rest := sch.push_frame(2, 1, 1, 20, _fake_frame(1, 1, 20, 0, 400), 25, 0.4)
	_check("clear: mute clears that speaker's waiting and playing speech (end event 'cleared'), others keep theirs; the rest of that utterance is dropped",
		cleared == 1 and end_cleared and sch.queued_frames(2) == 0 and sch.queued_frames(3) == 20 and rest == &"unknown" and sch.classify(2, 1, 1) == &"old")
	_check("clear: the muted speaker's next utterance is new again", sch.classify(2, 1, 2) == &"new")
	sch.forget_speaker(3, "left")
	_check("clear: a disconnect forgets the speaker", sch.queued_frames(3) == 0 and not sch.speakers().has(3))
	sch.open(4, 1, 1, VoiceRouter.ROUTE_RADIO, 0.0, 30.0, {}, 0.0)
	sch.push_frame(4, 1, 1, 0, _fake_frame(1, 1, 0, 0, 0), 25, 0.0)
	var n := sch.clear_all("session ended")
	_check("clear: leaving the session clears everything", n >= 1 and sch.queued_frames() == 0 and sch.speakers().is_empty())
	var sch2 := VoiceScheduler.new()
	sch2.open(2, 1, 5, VoiceRouter.ROUTE_RADIO, 0.0, 30.0, {}, 0.0)
	var restarted := sch2.open(2, 2, 1, VoiceRouter.ROUTE_RADIO, 1.0, 30.0, {}, 1.0)
	_check("clear: a new stream id from the same peer (the voice restarted) replaces its old speech", restarted and sch2.utterance_count(2) == 1 and sch2.classify(2, 1, 5) == &"new")
	var sch3 := VoiceScheduler.new()
	var unrouted := sch3.open(2, 1, 1, &"", 0.0, 0.0, {}, 0.0)
	_check("clear: an utterance with no route (stage 0, someone outside) queues nothing and its frames are dropped",
		not unrouted and sch3.classify(2, 1, 1) == &"old" and sch3.queued_frames() == 0 and sch3.stats.unrouted == 1)


func _test_schedule_two_speakers() -> void:
	var sch := VoiceScheduler.new()
	sch.open(2, 1, 1, VoiceRouter.ROUTE_RADIO, 0.0, 5.0, {}, 0.0)
	sch.open(3, 7, 9, VoiceRouter.ROUTE_RADIO, 0.0, 5.0, {}, 0.0)
	for i in 25:
		sch.push_frame(3, 7, 9, i, _fake_frame(7, 9, i, 0, i * 20), 25, 0.02 * i)
		sch.push_frame(2, 1, 1, i, _fake_frame(1, 1, i, 0, i * 20), 25, 0.02 * i)
	sch.end(2, 1, 1, 25, 0.5)
	sch.end(3, 7, 9, 25, 0.5)
	var events := _frames_of(_drain(sch, 0.0, 6.0))
	var a := []
	var b := []
	var same_time := true
	var at := {}
	for x: Array in events:
		var e: Dictionary = x[1]
		(a if int(e.peer) == 2 else b).append(int(e.index))
		var key := int(e.index)
		if at.has(key):
			same_time = same_time and absf(float(at[key]) - float(x[0])) < 1e-6
		else:
			at[key] = float(x[0])
	_check("schedule: two speakers at once each come out whole and in order, side by side", a == range(25) and b == range(25) and same_time)


func _test_schedule_latency() -> void:
	# in-process: frames arrive exactly on the speaker's 20 ms cadence; released by a 60 Hz frame loop (stage 4)
	var sch := VoiceScheduler.new()
	sch.open(2, 1, 1, VoiceRouter.ROUTE_RADIO, 0.0, CommsStage.delay_seconds(4), {}, 0.0)
	var lat: Array[float] = []
	var t := 0.0
	var next := 0
	while t < 1.2:
		while next < 50 and 0.02 * float(next + 1) <= t:
			sch.push_frame(2, 1, 1, next, _fake_frame(1, 1, next, 0, next * 20), 25, 0.02 * float(next + 1))
			next += 1
		for e: Dictionary in sch.pop_due(t):
			if e.type == &"frame":
				lat.append(t - 0.02 * float(int(e.index) + 1))
		t += 1.0 / 60.0
	var worst := 0.0
	var total := 0.0
	for v in lat:
		worst = maxf(worst, v)
		total += v
	_info("in-process scheduling latency at stage 4 (frame complete -> released, 60 Hz loop, no network): mean %.1f ms, max %.1f ms over %d frames" % [total / maxf(1.0, lat.size()) * 1000.0, worst * 1000.0, lat.size()])
	_check("latency: at stage 4 the buffer adds only the reorder window (in-process, %.0f ms max)" % (worst * 1000.0), lat.size() == 50 and worst < VoiceScheduler.JITTER_S + 0.02)


# ================================================================ codec

func _test_opus_round_trip() -> void:
	var problem := VoiceService.library_problem()
	_check("codec: TwoVoIP 6.1 classes and every method the voice code calls exist in this build", problem == "", problem)
	if problem != "":
		return
	var enc: Object = ClassDB.instantiate(VoiceService.ENCODER_CLASS)
	var in_rate := int(AudioServer.get_input_mix_rate())
	var ok := bool(enc.call(&"create_sampler", in_rate, VoiceScheduler.SAMPLE_RATE, VoiceScheduler.CHANNELS, false)) and bool(enc.call(&"create_opus_encoder", VoiceService.OPUS_BITRATE, VoiceService.OPUS_COMPLEXITY, true))
	var chunk := int(enc.call(&"calc_audio_chunk_size", VoiceScheduler.FRAME_SAMPLES))
	var packets: Array[PackedByteArray] = []
	_phase = 0.0
	for i in 50:
		enc.call(&"process_pre_encoded_chunk", _sine_chunk(chunk, 0.5), VoiceScheduler.FRAME_SAMPLES, false, false)
		var prefix := VoiceScheduler.make_header(VoiceScheduler.KIND_FRAME, 3, 1, i, 0, i * 20, "crew_2")
		packets.append(enc.call(&"encode_chunk", prefix, 1.0))
	var sizes := packets.map(func(p: PackedByteArray) -> int: return p.size())
	var parsed_ok := true
	for i in packets.size():
		var h := VoiceScheduler.parse(packets[i])
		parsed_ok = parsed_ok and int(h.index) == i and packets[i].size() > int(h.header_len) and packets[i].size() <= NetSession.VOICE_PACKET_MAX
	var stream := ClassDB.instantiate(VoiceService.STREAM_CLASS) as AudioStream
	stream.set(&"opus_sample_rate", VoiceScheduler.SAMPLE_RATE)
	stream.set(&"opus_channels", VoiceScheduler.CHANNELS)
	var pb: Object = stream.instantiate_playback()
	pb.call(&"start", 0.0)
	for i in packets.size():
		if i == 20:
			pb.call(&"push_opus_packet", packets[21], int(VoiceScheduler.parse(packets[21]).header_len), 1)    # frame 20 "lost": FEC from 21
		else:
			pb.call(&"push_opus_packet", packets[i], int(VoiceScheduler.parse(packets[i]).header_len), 0)
	var queued := int(pb.call(&"queue_length_frames"))
	pb.call(&"mark_end_opus_stream", true)
	var rate := AudioServer.get_mix_rate()
	var out: PackedVector2Array = pb.call(&"mix_audio", 1.0, int(rate * 0.9))
	var peak := 0.0
	var crossings := 0
	var prev := 0.0
	var from := int(rate * 0.1)
	var to := int(rate * 0.6)
	for i in range(from, to):
		var v := out[i].x
		peak = maxf(peak, absf(v))
		if prev < 0.0 and v >= 0.0:
			crossings += 1
		prev = v
	var freq := float(crossings) / ((to - from) / rate)
	_info("codec: 50 frames of a synthetic 440 Hz sine, %d-%d bytes each with the 25-byte header; decoded peak %.3f, frequency %.1f Hz" % [sizes.min(), sizes.max(), peak, freq])
	_check("codec: real TwoVoIP Opus encode -> game packet (header as the encoder prefix) -> decode of a synthetic sine (one frame by FEC) gives the same tone",
		ok and chunk > 0 and parsed_ok and queued == 50 * VoiceScheduler.FRAME_SAMPLES and peak > 0.3 and peak < 0.75 and absf(freq - 440.0) < 22.0,
		"ok %s chunk %d parsed %s queued %d peak %.3f freq %.1f" % [ok, chunk, parsed_ok, queued, peak, freq])


# ================================================================ settings, sources, privacy

func _test_settings_file() -> void:
	var path := _tmp.path_join("settings.json")
	var s := GameSettings.new()
	var changes := [0]
	s.changed.connect(func() -> void: changes[0] += 1)
	s.voice_input_device = "USB Headset"
	s.voice_mic_muted = true
	s.voice_volume = 1.4
	var err := s.save(path)
	var back := GameSettings.load_or_default(path)
	var clamped := GameSettings.new()
	clamped.voice_volume = 9.0
	var fresh := GameSettings.new()
	_check("settings: microphone, own mute and voice volume are saved with the other settings (defaults: default mic, not muted, 100 %)",
		err == OK and back.voice_input_device == "USB Headset" and back.voice_mic_muted and is_equal_approx(back.voice_volume, 1.4) and changes[0] == 3
		and clamped.voice_volume == 2.0 and fresh.voice_input_device == "" and not fresh.voice_mic_muted and fresh.voice_volume == 1.0, str(back.to_dict()))


func _test_sources_and_privacy() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/model_sources_voice.json"))
	var missing := PackedStringArray()
	var scripts := {"CommsStage": CommsStage, "VoiceRouter": VoiceRouter, "VoiceScheduler": VoiceScheduler, "VoiceService": VoiceService}
	var named := ["CommsStage.DELAY_S", "CommsStage.CARD_PARTS", "VoiceRouter.FULL_M", "VoiceRouter.SILENT_M", "VoiceRouter.DOOR_FACTOR",
		"VoiceRouter.DOOR_OPEN_MIN", "VoiceRouter.SILENT_GAIN", "VoiceRouter.PORTAL_PROBE_M", "VoiceScheduler.SAMPLE_RATE",
		"VoiceScheduler.FRAME_SAMPLES", "VoiceScheduler.FRAME_S", "VoiceScheduler.JITTER_S", "VoiceScheduler.PLAYBACK_TARGET_S",
		"VoiceScheduler.MAX_QUEUE_S", "VoiceScheduler.MAX_QUEUE_FRAMES", "VoiceScheduler.MAX_UTTERANCES", "VoiceScheduler.MAX_TOTAL_FRAMES",
		"VoiceScheduler.STALL_S", "VoiceScheduler.MAX_UTTERANCE_FRAMES", "VoiceService.OPUS_BITRATE", "VoiceService.OPUS_COMPLEXITY",
		"VoiceService.MIC_HANG_S", "VoiceService.MIC_SIGNAL_TIMEOUT_S", "VoiceService.MOUTH_HEIGHT_M", "VoiceService.VOLUME_MAX",
		"VoiceService.MIC_TARGET_PEAK", "VoiceService.MIC_MAX_GAIN", "VoiceService.MIC_START_GAIN", "VoiceService.MIC_SPEECH_FLOOR",
		"VoiceService.MIC_GAIN_RISE", "VoiceService.MIC_KNEE", "VoiceService.LOW_INPUT_RATE_HZ"]
	for key: String in named:
		var cls := key.get_slice(".", 0)
		var constant := key.get_slice(".", 1)
		var consts: Dictionary = (scripts[cls] as Script).get_script_constant_map()
		if not consts.has(constant):
			missing.append(key + " (not in the code)")
		elif not data is Dictionary or not (data as Dictionary).has(key) or String(((data as Dictionary)[key] as Dictionary).get("category", "")) == "":
			missing.append(key)
	_check("sources: every voice number has a category in model_sources_voice.json (contract, balance, engineering or physics)", missing.is_empty(), str(missing))
	var writes := PackedStringArray()
	for path: String in ["res://scripts/voice/voice_service.gd", "res://scripts/voice/voice_scheduler.gd", "res://scripts/voice/voice_router.gd",
			"res://scripts/voice/voice_hud.gd", "res://scripts/voice/comms_stage.gd"]:
		var text := FileAccess.get_file_as_string(path)
		for bad: String in ["FileAccess.open", "save_to_wav", "AudioStreamWAV", "AudioEffectRecord", "store_buffer", "DirAccess"]:
			if text.contains(bad):
				writes.append("%s uses %s" % [path.get_file(), bad])
	_check("privacy: the voice code never opens a file, records or saves audio (no file or recording calls in scripts/voice)", writes.is_empty(), str(writes))
	var saved := JSON.stringify(ColonyState.new_game(GameBalance.new(), 3, _zones.names).to_dict()).to_lower()
	_check("privacy: the saved and replicated colony state has no voice data in it", not saved.contains("voice") and not saved.contains("opus"))
	var helper_free := true
	for path: String in ["res://scripts/voice/voice_service.gd"]:
		var text := FileAccess.get_file_as_string(path)
		helper_free = helper_free and not text.contains("pitch_scale =") and not text.contains("set_pitch_scale") and not text.to_lower().contains("mqtt.")
	_check("catch-up: the voice code never changes pitch_scale (no speed-up or slow-down) and uses no MQTT", helper_free)


# ================================================================ three machines over ENet

func _machine(branch: String, save_dir: String, synthetic: bool) -> Array:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var g := GameServices.new()
	g.name = "Services"
	g.saves = SaveService.new(save_dir, "colony", 2)
	holder.add_child(g)
	var v := VoiceService.new()
	v.synthetic_input = synthetic
	v.measure_same_clock = true
	v.settings = GameSettings.new()
	holder.add_child(v)
	v.setup(null, g, null)
	return [g, v]


## Holds V on `v` for `seconds`, feeding synthetic sine chunks at the real-time pace of a microphone.
func _speak(v: VoiceService, seconds: float) -> void:
	v.set_ptt_override(1)
	var start := Time.get_ticks_usec()
	var fed := 0
	var chunk := v.audio_chunk_frames()
	while true:
		var elapsed := float(Time.get_ticks_usec() - start) / 1e6
		while float(fed + 1) * VoiceScheduler.FRAME_S <= elapsed and float(fed) * VoiceScheduler.FRAME_S < seconds:
			v.inject_capture(_sine_chunk(chunk, 0.4))
			fed += 1
		if elapsed >= seconds:
			break
		await process_frame
	await process_frame
	v.set_ptt_override(0)
	await process_frame


## Moves this machine's player. A client reports its body like the game does every frame (positions go unreliable,
## and NetSession skips a report equal to the last one, so a single lost report would never be repeated): it keeps
## reporting, with a millimetre wobble, until the host has the exact place.
func _place(g: GameServices, pos: Vector3, host: GameServices) -> void:
	var me := g.local_character()
	if g.is_authority():
		g.session.report_position(g.local_peer(), me.id, pos, 0.0)
		return
	var end := Time.get_ticks_msec() + 3000
	var k := 0
	while Time.get_ticks_msec() < end:
		g.report_position(me.id, pos if k % 2 == 0 else pos + Vector3(0.003, 0.0, 0.0), 0.0)
		await process_frame
		if k % 2 == 0 and host.state().character(me.id).position.is_equal_approx(pos):
			break
		k += 1
	g.report_position(me.id, pos, 0.0)


func _test_net() -> void:
	var host_m := _machine("VoiceHost", _tmp.path_join("host"), true)
	var a_m := _machine("VoiceA", _tmp.path_join("a"), true)
	var b_m := _machine("VoiceB", _tmp.path_join("b"), false)     # B has no microphone at all (headless): listening only
	var host: GameServices = host_m[0]
	var a: GameServices = a_m[0]
	var b: GameServices = b_m[0]
	var hv: VoiceService = host_m[1]
	var av: VoiceService = a_m[1]
	var bv: VoiceService = b_m[1]
	host.saves.delete_all()
	host.start_new_game(77)
	var hosting := host.net.host(PORT) == OK
	a.net.join("127.0.0.1", PORT)
	var a_in := await _until(func() -> bool: return a.net.is_client() and a.local_character() != null)
	b.net.join("127.0.0.1", PORT)
	var b_in := await _until(func() -> bool: return b.net.is_client() and b.local_character() != null and a.session.peers.size() == 3)
	_check("net: a host and two headless clients are connected, each with a crew member", hosting and a_in and b_in and host.session.peers.size() == 3,
		str(host.session.peers))
	if not (hosting and a_in and b_in):
		return
	var a_peer := a.local_peer()
	_check("net: a machine without a microphone is told so and stays playable (B: %s)" % bv.mic_state(),
		bv.mic_state() == &"headless" and not bv.can_capture() and bv.own_line().contains("No microphone") and av.mic_state() == &"synthetic")

	# ---- relay: client A -> host -> client B, unchanged and in order
	await _until(func() -> bool: return false, 0.5)
	var got: Array = []
	var catch_raw := func(from: int, p: PackedByteArray) -> void:
		if p.size() > 0 and p[0] == 0x11:
			got.append([from, p])
	b.net.voice_packet_received.connect(catch_raw)
	# reliable (as start and end packets go): every one must arrive, unchanged and in order
	var sent: Array[PackedByteArray] = []
	for i in 30:
		var p := PackedByteArray([0x11, i, 0xAA, 0xBB, i * 3 & 0xff])
		sent.append(p)
		a.net.send_voice(p, true)
		if i % 5 == 4:
			await process_frame
	var relayed := await _until(func() -> bool: return got.size() >= 30, 3.0)
	var same := relayed and got.size() == 30
	for i in mini(got.size(), 30):
		same = same and int(got[i][0]) == a_peer and got[i][1] == sent[i]
	_check("net: 30 reliable voice packets from client A arrive at client B through the host relay, from A's peer id, unchanged and in order (in-process ENet)",
		same, "%d of 30" % got.size())
	# unreliable (as frames go): ENet may drop some; those that arrive are unchanged and in order
	got.clear()
	var sent_u: Array[PackedByteArray] = []
	for i in 30:
		var p := PackedByteArray([0x11, 100 + i, 0xCC, i])
		sent_u.append(p)
		a.net.send_voice(p, false)
		if i % 5 == 4:
			await process_frame
	await _until(func() -> bool: return got.size() >= 30, 2.0)
	var in_order := not got.is_empty()
	var last_i := -1
	for g_: Array in got:
		var i := sent_u.find(g_[1] as PackedByteArray)
		in_order = in_order and int(g_[0]) == a_peer and i > last_i
		last_i = i
	b.net.voice_packet_received.disconnect(catch_raw)
	_info("unreliable relay: %d of 30 frames-like packets arrived at B (in-process ENet can drop unreliable packets)" % got.size())
	_check("net: unreliable voice packets that arrive through the relay are unchanged, from A, and in order", in_order, "%d arrived" % got.size())

	# ---- everyone inside the mess hall: A talks, B hears nearby at once
	await _place(host, MESS_C, host)
	await _place(a, MESS_A, host)
	await _place(b, MESS_B, host)
	var placed := await _until(func() -> bool: return (b.state().character(a.local_character().id).position.distance_to(MESS_A) < 0.01
		and a.state().character(b.local_character().id).position.distance_to(MESS_B) < 0.01), 3.0)
	var route := bv.route_for(a_peer)
	var before := int(bv.counters.decoded_frames)
	bv.same_clock_latency_ms.clear()
	var sent0 := int(av.counters.sent_frames)
	var at_host := [0]
	var count_host := func(_f: int, p: PackedByteArray) -> void:
		var hh := VoiceScheduler.parse(p)
		if not hh.is_empty() and int(hh.kind) == VoiceScheduler.KIND_FRAME:
			at_host[0] += 1
	host.net.voice_packet_received.connect(count_host)
	await _speak(av, 0.6)
	var heard := await _until(func() -> bool: return int(bv.counters.decoded_frames) - before >= 5, 3.0)
	host.net.voice_packet_received.disconnect(count_host)
	var throttle := -1.0
	for pp: ENetPacketPeer in (a.net._peer as ENetMultiplayerPeer).host.get_peers():
		throttle = pp.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)
	_info("transport: A sent %d frames (reliable on the voice channel), the host received %d; ENet's PEER_PACKET_THROTTLE statistic on A's link to the host reads %d of 32 (when frames were sent unreliable, this throttle dropped about half of them)"
		% [int(av.counters.sent_frames) - sent0, int(at_host[0]), roundi(throttle)])
	_check("net: every voice frame A sent reached the host (voice packets go reliable and ordered on the voice channel)",
		int(at_host[0]) == int(av.counters.sent_frames) - sent0 and int(at_host[0]) > 0, "%d of %d" % [int(at_host[0]), int(av.counters.sent_frames) - sent0])
	var lane_ok := bv.outs_of(a_peer).any(func(o: VoiceService.VoiceOut) -> bool: return o.lane == VoiceRouter.ROUTE_PROXIMITY and o.pushed > 0)
	await _until(func() -> bool: return bv.scheduler.utterance_count() == 0, 2.0)
	var hv_heard := int(hv.counters.decoded_frames) >= 5
	var lat := bv.same_clock_latency_ms.duplicate()
	var mean := 0.0
	var worst := 0.0
	for v: float in lat:
		mean += v
		worst = maxf(worst, v)
	mean /= maxf(1.0, float(lat.size()))
	_info("in-process end-to-end at the nearby route (speaker send -> released to the listener's player, one process, 127.0.0.1): mean %.0f ms, max %.0f ms over %d frames; plus the %.0f ms player buffer target and the audio output latency, not measured here"
		% [mean, worst, lat.size(), VoiceScheduler.PLAYBACK_TARGET_S * 1000.0])
	_check("net: inside the mess hall, A's synthetic speech is sent by push-to-talk and B (no microphone) hears it nearby, decoded into the player (%d frames)" % (int(bv.counters.decoded_frames) - before),
		placed and route.route == VoiceRouter.ROUTE_PROXIMITY and heard and lane_ok and hv_heard and int(av.counters.utterances_sent) == 1, "placed %s route %s heard %s lane %s host %d sent %d; at B: A %s, B %s" % [placed, route, heard, lane_ok, int(hv.counters.decoded_frames), int(av.counters.utterances_sent), b.state().character(a.local_character().id).position, b.local_character().position])
	_check("net: the near-immediate route is measured in-process and stays under the 200 ms target on average (mean %.0f ms + %.0f ms buffer target; in-process only)" % [mean, VoiceScheduler.PLAYBACK_TARGET_S * 1000.0],
		lat.size() >= 10 and mean + VoiceScheduler.PLAYBACK_TARGET_S * 1000.0 < 200.0)
	var pitch_ok := true
	for o: VoiceService.VoiceOut in bv.outs_of(a_peer):
		pitch_ok = pitch_ok and is_equal_approx(float(o.player.get(&"pitch_scale")), 1.0)
	_check("net: no catch-up: every voice player keeps pitch_scale 1.0", pitch_ok)

	# ---- A walks outside with no radio: B hears nothing and the HUD says why; A's own line says so too
	await _until(func() -> bool: return bv.scheduler.utterance_count() == 0 and bv.heard_lines().is_empty(), 3.0)
	await _place(a, OUTSIDE, host)
	await _until(func() -> bool: return bool(bv.route_for(a_peer).route == VoiceRouter.ROUTE_NONE), 3.0)
	before = int(bv.counters.decoded_frames)
	av.set_ptt_override(1)
	av.inject_capture(_sine_chunk(av.audio_chunk_frames()))
	await process_frame
	var a_line := av.own_line()
	var b_lines := [""]
	var check_lines := func() -> bool:
		b_lines[0] = "\n".join(bv.heard_lines())
		return String(b_lines[0]).contains("no radio link")
	var told := await _until(check_lines, 2.0)
	for i in 10:
		av.inject_capture(_sine_chunk(av.audio_chunk_frames()))
		await process_frame
	av.set_ptt_override(0)
	await _until(func() -> bool: return false, 0.4)
	_check("net: stage 0 and A outside: B hears nothing, B's HUD says there is no radio link, A's HUD says nobody can hear",
		int(bv.counters.decoded_frames) == before and told and a_line.begins_with("✖ No radio link outside"), "%s | %s" % [a_line, b_lines[0]])
	var transition := av.transition_line()
	_check("net: going outside shows what changed for the voice", transition.contains("outside now"), transition)

	# ---- radio stage 3 (5 s): A outside, B inside hears after the equipment delay
	await _until(func() -> bool: return bv.scheduler.utterance_count() == 0, 3.0)
	_install(host.state(), 3)
	var synced := await _until(func() -> bool: return CommsStage.stage(b.state()) == 3 and CommsStage.stage(a.state()) == 3, 3.0)
	before = int(bv.counters.decoded_frames)
	var t0 := Time.get_ticks_msec()
	var first_ms := [-1]
	await _speak(av, 0.5)
	var pending_seen := "\n".join(bv.heard_lines())
	var a_radio := VoiceRouter.speaking_text(true, 3, 0)
	var arrived := await _until(func() -> bool:
		if first_ms[0] < 0 and int(bv.counters.decoded_frames) > before:
			first_ms[0] = Time.get_ticks_msec()
		return int(bv.counters.decoded_frames) - before >= 5, 8.0)
	var measured := float(first_ms[0] - t0) / 1000.0
	_info("radio stage 3: requested delay 5.000 s; measured in-process from push-to-talk to the first decoded frame %.3f s" % measured)
	_check("net: radio stage 3: A outside, B inside hears A after the 5 s equipment delay (measured %.2f s), not before; the HUD shows the message waiting" % measured,
		synced and arrived and measured >= 5.0 and measured < 5.6 and pending_seen.contains("Radio message from") and a_radio.contains("after 5 s")
		and bv.outs_of(a_peer).any(func(o: VoiceService.VoiceOut) -> bool: return o.lane == VoiceRouter.ROUTE_RADIO and o.pushed > 0),
		"synced %s arrived %s measured %.3f pending %s" % [synced, arrived, measured, pending_seen])

	# ---- both speak at once: host (inside) and A (outside, radio stage 4) reach B together
	await _until(func() -> bool: return bv.scheduler.utterance_count() == 0, 3.0)
	_install(host.state(), 4)
	await _until(func() -> bool: return CommsStage.stage(b.state()) == 4, 3.0)
	var from_host := func() -> int:
		var n := 0
		for o: VoiceService.VoiceOut in bv.outs_of(1):
			n += o.pushed
		return n
	var from_a := func() -> int:
		var n := 0
		for o: VoiceService.VoiceOut in bv.outs_of(a_peer):
			n += o.pushed
		return n
	var h0: int = from_host.call()
	var a0: int = from_a.call()
	hv.set_ptt_override(1)
	var chunk := av.audio_chunk_frames()
	var start := Time.get_ticks_usec()
	var fed := 0
	while float(Time.get_ticks_usec() - start) / 1e6 < 0.5:
		while float(fed + 1) * VoiceScheduler.FRAME_S <= float(Time.get_ticks_usec() - start) / 1e6:
			av.set_ptt_override(1)
			hv.inject_capture(_sine_chunk(chunk, 0.3))
			av.inject_capture(_sine_chunk(chunk, 0.3))
			fed += 1
		await process_frame
	hv.set_ptt_override(0)
	av.set_ptt_override(0)
	var both := await _until(func() -> bool: return int(from_host.call()) - h0 >= 5 and int(from_a.call()) - a0 >= 5, 3.0)
	_check("net: two speakers at once (host nearby, A by radio at stage 4) are both heard by B on their own players",
		both, "host %d, A %d" % [int(from_host.call()) - h0, int(from_a.call()) - a0])

	# ---- mute: B mutes A; A's speech is dropped and nothing of A's is left waiting
	await _until(func() -> bool: return bv.scheduler.utterance_count() == 0, 3.0)
	bv.set_player_muted(a_peer, true)
	var a_before: int = from_a.call()
	await _speak(av, 0.3)
	await _until(func() -> bool: return false, 0.4)
	_check("net: B mutes A: nothing of A is decoded or left waiting", int(from_a.call()) == a_before and bv.scheduler.queued_frames(a_peer) == 0
		and bv.player_rows().any(func(r: Dictionary) -> bool: return int(r.peer) == a_peer and bool(r.muted)))
	bv.set_player_muted(a_peer, false)

	# ---- disconnect: a long radio message from A waits at B (stage 1, 30 s); A leaves; B clears it
	_install(host.state(), 1)
	await _until(func() -> bool: return CommsStage.stage(b.state()) == 1, 3.0)
	await _speak(av, 0.4)
	var waiting := await _until(func() -> bool: return bv.scheduler.queued_frames(a_peer) > 0, 2.0)
	a.net.leave()
	var cleared := await _until(func() -> bool: return bv.scheduler.queued_frames(a_peer) == 0 and not bv.scheduler.speakers().has(a_peer), 3.0)
	_check("net: when A disconnects, B clears A's waiting radio speech", waiting and cleared, "waiting %s" % waiting)

	# ---- session exit: the host's queued speech at B is cleared when B leaves
	await _place(host, OUTSIDE_2, host)
	await _until(func() -> bool: return bv.route_for(1).route == VoiceRouter.ROUTE_RADIO, 3.0)
	await _speak(hv, 0.4)
	var host_waiting := await _until(func() -> bool: return bv.scheduler.queued_frames(1) > 0, 2.0)
	b.net.leave()
	var b_cleared := await _until(func() -> bool: return bv.scheduler.queued_frames() == 0 and bv.scheduler.speakers().is_empty(), 2.0)
	_check("net: leaving the session clears every voice buffer", host_waiting and b_cleared)
	_info("voice counters at B: %s; scheduler %s; at A: %s" % [bv.counters, bv.scheduler.stats, av.counters])

	host.net.leave()
	await _frames(3)
	host.saves.delete_all()
	for m: Array in [host_m, a_m, b_m]:
		((m[0] as Node).get_parent()).queue_free()
	await _frames(3)


# ================================================================ HUD and panels

func _test_hud_and_panels() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	var g := GameServices.new()
	g.name = "Services"
	g.saves = SaveService.new(_tmp.path_join("solo"), "colony", 2)
	root.add_child(g)
	g.start_new_game(5)
	g.set_process(false)
	var hud := GameHud.new()
	hud.name = "Hud"
	root.add_child(hud)
	hud.setup(g)
	hud.set_status("Hosting on 192.168.1.20:24680, 2 players")
	var v := VoiceService.new()
	v.synthetic_input = true
	v.settings = GameSettings.new()
	root.add_child(v)
	v.setup(null, g, null)
	var widget := VoiceHud.new()
	hud.add_child(widget)
	widget.setup(v)
	var me := g.local_character()
	me.position = MESS_A
	_install(g.state(), 1)
	v.set_ptt_override(1)
	v.inject_capture(_sine_chunk(v.audio_chunk_frames()))
	await _frames(3)
	widget.refresh()
	await _frames(2)
	var inside_text := widget.own_text()
	var crew2 := g.state().character(&"crew_2")
	crew2.owner_peer = 2
	crew2.position = OUTSIDE
	widget.refresh()
	var with_outside := widget.own_text()
	me.position = OUTSIDE
	v.inject_capture(_sine_chunk(v.audio_chunk_frames()))
	await _frames(2)
	widget.refresh()
	var outside_text := widget.own_text()
	var note := widget.note_text()
	await _frames(2)
	var r := widget.get_global_rect()
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var overlaps := PackedStringArray()
	for n: String in ["TopLeft", "TopRight", "Hints", "Status", "Crosshair"]:
		var c := hud.find_child(n, true, false) as Control
		if c != null and c.is_visible_in_tree() and c.get_global_rect().intersects(r):
			overlaps.append(n)
	_check("hud: the voice corner sits bottom right inside the screen, clear of the colony corner, crew card, hints, status and crosshair",
		screen.encloses(r) and overlaps.is_empty() and r.position.x > 640.0 and r.end.y > 600.0, "%s overlaps %s" % [r, overlaps])
	_check("hud: transmitting shows the route: nearby, nearby + crew outside by radio, then radio when outside, and the change note",
		inside_text.begins_with("● Speaking nearby") and with_outside.contains("crew outside hear you by radio after 30 s")
		and outside_text.begins_with("● Radio — heard after 30 s") and note.contains("outside now"), "%s | %s | %s | %s" % [inside_text, with_outside, outside_text, note])
	v.set_ptt_override(0)
	await _frames(2)
	v.set_mic_muted(true)
	widget.refresh()
	var muted_text := widget.own_text()
	v.set_mic_muted(false)
	_check("hud: own microphone muted is shown", muted_text.contains("muted"), muted_text)

	# ---- voice settings panel: layout, state, controls
	g.session.peers.append(2)
	var panel := VoiceSettingsPanel.new()
	panel.settings = v.settings
	panel.settings_path = _tmp.path_join("voice_settings.json")
	panel.voice = v
	panel.setup(g)
	root.add_child(panel)
	var layout := PackedStringArray()
	for sz: Array in [[Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 1.0], [Vector2i(1280, 720), 1.5]]:
		root.size = sz[0]
		UiTheme.apply_text_scale(float(sz[1]))
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.refresh()
		await _frames(3)
		for p in UiLayoutCheck.problems(panel, Vector2(sz[0])):
			layout.append("%s: %s" % [sz, p])
		for p in UiLayoutCheck.focus_problems(panel):
			layout.append("%s: %s" % [sz, p])
	root.size = Vector2i(1280, 720)
	UiTheme.apply_text_scale(1.0)
	_check("settings panel: fits 1280x720 and 1920x1080 (text 1.0 and 1.5), every control reachable by keyboard", layout.is_empty(), "; ".join(layout))
	var row := panel.player_row(2)
	var row_ok := not row.is_empty()
	if row_ok:
		(row.mute as CheckButton).button_pressed = true
		(row.slider as HSlider).value = 0.5
	panel.mute_button().button_pressed = true
	await _frames(2)
	_check("settings panel: per-player mute and volume reach the voice service; muting my microphone saves in the settings",
		row_ok and v.is_player_muted(2) and is_equal_approx(v.player_volume(2), 0.5) and v.settings.voice_mic_muted and v.mic_muted()
		and panel.status_text().contains("muted") and panel.device_button().item_count >= 1)
	panel.mute_button().button_pressed = false
	v.inject_capture(_sine_chunk(v.audio_chunk_frames(), 0.6))
	panel.refresh()
	await _frames(3)
	_check("settings panel: the input level meter moves with the (synthetic) input while the panel is open; nothing is sent without V",
		panel.meter_value() > 10.0 and not v.is_transmitting(), "%.1f" % panel.meter_value())
	panel.queue_free()
	await _frames(2)
	_check("settings panel: closing it saves the voice settings", FileAccess.file_exists(_tmp.path_join("voice_settings.json")))

	# ---- Settings > Controls has the one button that opens it
	var sp := SettingsPanel.new()
	sp.settings = GameSettings.new()
	sp.settings_path = _tmp.path_join("settings_panel.json")
	sp.input_path = _tmp.path_join("input.json")
	sp.setup(g)
	root.add_child(sp)
	await _frames(2)
	var opened: Array = []
	sp.open_requested.connect(func(p: UiPanel) -> void: opened.append(p))
	var button := sp.find_child("VoiceSettingsButton", true, false) as Button
	if button != null:
		button.pressed.emit()
	_check("settings: Controls has a 'Voice and microphone…' button that opens the voice settings with the same settings",
		button != null and opened.size() == 1 and opened[0] is VoiceSettingsPanel and (opened[0] as VoiceSettingsPanel).settings == sp.settings)
	for p: Variant in opened:
		(p as Node).free()
	sp.queue_free()

	# ---- credits list the voice libraries
	var credits := CreditsPanel.new()
	credits.setup(g)
	root.add_child(credits)
	await _frames(2)
	var text := ""
	for l in credits.find_children("*", "Label", true, false):
		text += (l as Label).text + "\n"
	_check("credits: TwoVoIP (MIT) and Opus, SpeexDSP and RNNoise (BSD-style) are listed with the tools; groups unchanged",
		text.contains("TwoVoIP 6.1") and text.contains("MIT licence") and text.contains("Opus") and text.contains("SpeexDSP") and text.contains("RNNoise")
		and text.contains("BSD-style") and credits.group_titles() == PackedStringArray(["Engine", "Tools", "Assets", "Science sources"]), str(credits.group_titles()))
	credits.queue_free()
	widget.queue_free()
	hud.queue_free()
	v.queue_free()
	g.saves.delete_all()
	g.queue_free()
	await _frames(3)
