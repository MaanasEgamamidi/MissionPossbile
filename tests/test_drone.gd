extends SceneTree
## Scout drone (2026-11-14 upgrade paths): the drone pad station, manual flight (V1+) and its limits (the command
## room's radio range, the battery and the flight home), surveys that reveal ore like the scout rover's, the
## autopilot (refused below V3, one place at V3, a route at V4, flown by the host while nobody watches), saves and the
## replicated state, the co-op input path (host accepts inputs only from the pilot's peer), the presenter (model of the
## level riding on the drone body, rotors, follow camera, HUD), the pad panel, and the four drone glbs and the pad glb.
## Synthetic: every check runs headless on the real game services; no player has tried it.
## Run: godot --headless --path . --script res://tests/test_drone.gd


class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR or error_type == ERROR_TYPE_SCRIPT:
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


const DroneSystem := preload("res://scripts/drone/drone_system.gd")
const DroneModels := preload("res://scripts/drone/drone_models.gd")
const PRESENTER := "res://scripts/drone/drone_presenter.gd"
const STAGES := "res://scripts/upgrades/stages/scout_drone_stages.gd"
const PAD := &"drone_pad"

var _passed := 0
var _total := 0
var _catcher := ErrorCatcher.new()
var services: GameServices
var _alerts: Array[String] = []
var _texts: Array[String] = []


func _initialize() -> void:
	OS.add_logger(_catcher)
	PlayerInput.ensure_actions()
	services = GameServices.new()
	services.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/drone"), "colony", 2)
	root.add_child(services)
	services.start_new_game(1)
	await _frames()
	services.set_process(false)
	services.events.system_alert.connect(func(id: StringName, _l: StringName, t: String) -> void:
		_alerts.append(String(id))
		_texts.append(t))

	_test_station_and_data()
	_test_manual_flight()
	_test_range_limit()
	_test_battery_limit()
	_test_survey()
	_test_autopilot_refused_below_v3()
	_test_autopilot_v3()
	_test_route_v4()
	_test_save_load_and_replication()
	_test_coop_inputs()
	await _test_presenter()
	await _test_panel()
	await _test_glbs()
	await _test_game_main()

	_check("no script or engine errors during the test", _catcher.errors.is_empty(), "\n".join(_catcher.errors))
	OS.remove_logger(_catcher)
	services.queue_free()
	await process_frame
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


# ---------------------------------------------------------------- helpers

func _check(test_name: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS %s" % test_name)
	else:
		print("FAIL %s: %s" % [test_name, detail])


func _frames(n := 2) -> void:
	for i in n:
		await process_frame


func st() -> ColonyState:
	return services.state()


func me() -> CharacterState:
	return services.local_character()


func sys() -> Object:
	return DroneSystem.find(services.session)


func _req(action: StringName, target: StringName = &"", params := {}) -> ActionResult:
	return services.session.request(action, target, params)


func _at_pad() -> void:
	me().suit_on = true
	me().position = CharacterState._v3(st().stations[String(PAD)].position) + Vector3(1.5, 0.0, 0.0)
	me().outside = true


func _inside() -> void:
	me().position = me().hub_spot
	me().outside = false


func _computer() -> StringName:
	for id: String in st().stations:
		if String((st().stations[id] as Dictionary).get("kind", "")) == "computer":
			return StringName(id)
	return &""


func _set_level(track: String, lvl: int) -> void:
	st().levels[track] = lvl


func _reset_drone() -> void:
	st().drone = {}
	DroneSystem.ensure(st())


## Forgets every survey and reveal (earlier flights may have passed near a site).
func _clear_surveys() -> void:
	ScoutSystem.ensure(st())
	st().scout.revealed = {}
	st().scout.surveyed = {}
	_reset_drone()


## Manual flight on the host's drone system for `seconds`, re-sending the stick every substep like the presenter does.
func _fly(pilot: String, move: Vector2, climb: float, yaw: float, seconds: float) -> void:
	var s := sys()
	var t := 0.0
	while t < seconds - 1e-6:
		s.call(&"set_input", pilot, move, climb, yaw)
		s.call(&"advance", st(), 0.25, services.events)
		t += 0.25


## Runs the real session (simulation ticks at 5 Hz) until the drone is docked or `max_s` real seconds passed.
func _run_until_docked(max_s: float, watch := {}) -> float:
	var t := 0.0
	var tick := 1.0 / services.config.sim_tick_hz
	while t < max_s:
		services.session.advance(tick)
		t += tick
		if watch.has("targets"):
			var tg := String(st().drone.get("target", ""))
			var seen: Array = watch.targets
			if tg != "" and (seen.is_empty() or seen.back() != tg):
				seen.append(tg)
		if watch.has("statuses"):
			var s: Dictionary = watch.statuses
			s[DroneSystem.status(st())] = true
		if watch.has("far"):
			watch.far = maxf(float(watch.far), DroneSystem.distance_from_pad(st()))
		if DroneSystem.status(st()) == "docked":
			return t
	return t


# ---------------------------------------------------------------- tests

func _test_station_and_data() -> void:
	services.session.advance(1.0 / services.config.sim_tick_hz)      # the first simulation tick fills state.drone
	var rec: Dictionary = st().stations.get(String(PAD), {})
	_check("station: the drone pad comes from data/stations_drone.json (kind drone_pad)", String(rec.get("kind", "")) == "drone_pad", str(rec))
	var p := CharacterState._v3(rec.get("position", [0, 0, 0]))
	var h := load("res://data/terrain_height.res") as TerrainHeight
	var ground := h.height_at(p.x, p.z)
	var slope := absf(h.height_at(p.x + 1.5, p.z) - h.height_at(p.x - 1.5, p.z)) + absf(h.height_at(p.x, p.z + 1.5) - h.height_at(p.x, p.z - 1.5))
	_check("station: the pad is outside on flat ground", services.zones.zone_at_world(p) == ColonyZones.EXTERIOR and absf(ground - p.y) < 0.6 and slope < 0.35,
		"zone %s ground %.2f slope %.2f" % [services.zones.zone_at_world(p), ground, slope])
	var near := PackedStringArray()
	for id: String in st().stations:
		if id == String(PAD):
			continue
		var q := CharacterState._v3((st().stations[id] as Dictionary).get("position", [0, 0, 0]))
		if Vector2(q.x - p.x, q.z - p.z).length() < 4.0:
			near.append(id)
	_check("station: no other station within 4 m of the pad (the scout bay stays clear)", near.is_empty(), ", ".join(near))
	_check("station: the pad is out of the crew rover's lane from the garage (z 21.5..24.5)", p.z + 1.6 < 21.5 or p.z - 1.6 > 24.5, str(p))
	_check("new game: the drone starts docked on its pad, fully charged", DroneSystem.status(st()) == "docked" and is_equal_approx(DroneSystem.battery(st()), 1.0)
		and DroneSystem.position(st()).distance_to(DroneSystem.dock_position(st())) < 0.01, str(st().drone))
	_check("levels: V1 effects come from data/area_levels.json (5 m/s, 90 s, 20 m survey, no autopilot) and the command range is 150 m",
		is_equal_approx(DroneSystem.speed_mps(st()), 5.0) and is_equal_approx(DroneSystem.flight_seconds(st()), 90.0)
		and is_equal_approx(DroneSystem.survey_radius_m(st()), 20.0) and not DroneSystem.has_autopilot(st()) and is_equal_approx(DroneSystem.range_m(st()), 150.0),
		"%s %s %s %s" % [DroneSystem.speed_mps(st()), DroneSystem.flight_seconds(st()), DroneSystem.survey_radius_m(st()), DroneSystem.range_m(st())])
	_check("session: the drone system runs as a post-system of the simulation", sys() != null)


func _test_manual_flight() -> void:
	_at_pad()
	me().position += Vector3(30, 0, 0)
	var r := _req(&"drone_fly", PAD)
	_check("fly: refused from far away", not r.ok, String(r.reason))
	_at_pad()
	r = _req(&"drone_fly", PAD)
	_check("fly: E at the pad takes the controls; the drone lifts off with the pilot set", r.ok and DroneSystem.status(st()) == "manual"
		and DroneSystem.pilot(st()) == String(me().id) and DroneSystem.altitude(st()) > 1.0, "%s %s" % [r.message, st().drone])
	r = _req(&"drone_fly", PAD)
	_check("fly: a second pilot is refused while someone flies it", not r.ok and r.message.contains("already flying"), r.message)
	var start := DroneSystem.position(st())
	var yaw := float(st().drone.yaw)
	var forward := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	_fly(String(me().id), Vector2(0, 1), 0.0, yaw, 3.0)
	var moved := DroneSystem.position(st()) - start
	var flat := Vector3(moved.x, 0, moved.z)
	_check("manual: W flies it forward at the level's speed (about 13 m in 3 s at 5 m/s)", flat.length() > 10.0 and flat.length() < 16.0
		and flat.normalized().dot(forward) > 0.95, "moved %s" % moved)
	var y0 := DroneSystem.altitude(st())
	_fly(String(me().id), Vector2.ZERO, 1.0, yaw, 2.0)
	_check("manual: Space climbs", DroneSystem.altitude(st()) > y0 + 3.0, "%.1f -> %.1f" % [y0, DroneSystem.altitude(st())])
	var p0 := DroneSystem.position(st())
	_fly(String(me().id), Vector2(1, 0), 0.0, yaw + PI * 0.5, 2.0)
	var side := DroneSystem.position(st()) - p0
	var right := Basis(Vector3.UP, yaw + PI * 0.5) * Vector3(1, 0, 0)
	_check("manual: the mouse turns it (the stick is relative to its heading)", absf(wrapf(float(st().drone.yaw) - (yaw + PI * 0.5), -PI, PI)) < 1e-3
		and Vector3(side.x, 0, side.z).normalized().dot(right) > 0.9, str(side))
	var p1 := DroneSystem.position(st())
	var s := sys()
	s.call(&"set_input", String(me().id), Vector2(0, 1), 0.0, yaw)
	s.call(&"advance", st(), 2.0, services.events)
	var coast := DroneSystem.position(st()).distance_to(p1)
	_check("manual: when the pilot's inputs stop arriving it slows down and hovers", coast < 4.0 and _v3(st().drone.vel).length() < 0.5, "coasted %.1f m" % coast)
	r = _req(&"drone_land")
	_check("hand back: E hands the drone back; it flies home by itself", r.ok and DroneSystem.status(st()) == "returning" and DroneSystem.pilot(st()) == "", r.message)
	var t := 0.0
	while DroneSystem.status(st()) != "docked" and t < 120.0:
		s.call(&"advance", st(), 0.5, services.events)
		t += 0.5
	_check("hand back: it lands on its pad and charges", DroneSystem.status(st()) == "docked"
		and DroneSystem.position(st()).distance_to(DroneSystem.dock_position(st())) < 0.05, "%s after %.1f s" % [DroneSystem.status(st()), t])


func _test_range_limit() -> void:
	_reset_drone()
	_at_pad()
	var r := _req(&"drone_fly", PAD)
	var pad := DroneSystem.pad_position(st())
	var range_m := DroneSystem.range_m(st())
	var yaw := DroneSystem.pad_yaw()         # faces +z, away from the base
	var dir := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	var at := pad + dir * (range_m * 0.85)
	st().drone.position = [at.x, DroneSystem.ground(at.x, at.z) + 10.0, at.z]
	_alerts.clear()
	_fly(String(me().id), Vector2(0, 1), 0.0, yaw, 3.0)
	_check("range: a warning at 90 % of the command room's radio range", r.ok and _alerts.has("drone_range") and bool(st().drone.range_warned),
		"%s %s %.1f" % [r.message, _alerts, DroneSystem.distance_from_pad(st())])
	_fly(String(me().id), Vector2(0, 1), 0.0, yaw, 6.0)
	var dist := DroneSystem.distance_from_pad(st())
	_check("range: it stops at the edge (%d m) and cannot fly further" % roundi(range_m), dist <= range_m + 0.01 and dist > range_m - 1.0
		and bool(st().drone.at_edge) and DroneSystem.range_state(st()) == "edge", "%.2f m" % dist)
	_set_level("command", 2)
	_check("range: the command room upgrade widens it (V2: 300 m)", is_equal_approx(DroneSystem.range_m(st()), 300.0))
	_fly(String(me().id), Vector2(0, 1), 0.0, yaw, 2.0)
	_check("range: with more range it flies on past the old edge", DroneSystem.distance_from_pad(st()) > range_m + 3.0, "%.1f" % DroneSystem.distance_from_pad(st()))
	_set_level("command", 1)
	_reset_drone()


func _test_battery_limit() -> void:
	_reset_drone()
	_at_pad()
	_req(&"drone_fly", PAD)
	var yaw := DroneSystem.pad_yaw()
	_fly(String(me().id), Vector2(0, 1), 0.5, yaw, 4.0)
	var b0 := DroneSystem.battery(st())
	_check("battery: flying uses 1/flight_seconds of it per second (V1: 90 s)", absf((1.0 - b0) - 4.0 / 90.0) < 0.01, "%.4f" % b0)
	st().drone.battery = DroneSystem.battery_to_home(st()) + 0.06
	_alerts.clear()
	_fly(String(me().id), Vector2(0, 1), 0.0, yaw, 3.0)
	_check("battery: when only the trip home is left it takes the controls away and flies home, with a warning",
		DroneSystem.status(st()) == "returning" and DroneSystem.pilot(st()) == "" and _alerts.has("drone_battery") and bool(st().drone.low_announced),
		"%s %s" % [DroneSystem.status(st()), _alerts])
	var s := sys()
	var t := 0.0
	while DroneSystem.status(st()) != "docked" and t < 200.0:
		s.call(&"advance", st(), 0.5, services.events)
		t += 0.5
	_check("battery: it reaches its pad and lands", DroneSystem.status(st()) == "docked", "%s %.1f s" % [DroneSystem.status(st()), t])
	# an empty battery far out: it still limps home on its emergency cell, at half speed
	var far := DroneSystem.pad_position(st()) + Vector3(0, 8, 60)
	st().drone.status = "returning"
	st().drone.position = [far.x, far.y, far.z]
	st().drone.battery = 0.0
	s.call(&"advance", st(), 1.0, services.events)
	var step := DroneSystem.distance_from_pad(st())
	t = 0.0
	while DroneSystem.status(st()) != "docked" and t < 200.0:
		s.call(&"advance", st(), 0.5, services.events)
		t += 0.5
	_check("battery: an empty battery makes it fly home slowly and land", DroneSystem.status(st()) == "docked" and step > 56.0 and step < 58.5, "%.2f m after 1 s, %s" % [step, DroneSystem.status(st())])
	var r := _req(&"drone_fly", PAD)
	_check("battery: it will not take off nearly empty; the reason is in words", not r.ok and r.message.contains("charge"), r.message)
	var b1 := DroneSystem.battery(st())
	s.call(&"advance", st(), 30.0, services.events)
	_check("battery: it charges on the pad", DroneSystem.battery(st()) > b1 + 0.25, "%.2f -> %.2f" % [b1, DroneSystem.battery(st())])
	_reset_drone()


func _test_survey() -> void:
	_clear_surveys()
	_at_pad()
	_req(&"drone_fly", PAD)
	var site := ScoutSystem.site_position("east_plain")
	var start := site + Vector3(26, 0, 0)
	st().drone.position = [start.x, DroneSystem.ground(start.x, start.z) + 8.0, start.z]
	var yaw := atan2(1.0, 0.0)           # faces -x, toward the site
	var revealed_before := ScoutSystem.is_revealed(st(), "ore_hematite_a")
	_alerts.clear()
	_fly(String(me().id), Vector2.ZERO, 0.0, yaw, 1.0)
	_check("survey: nothing happens outside the survey radius (V1: 20 m)", not DroneSystem.is_surveyed(st(), "east_plain"))
	_fly(String(me().id), Vector2(0, 1), 0.0, yaw, 2.5)
	var rep: Dictionary = st().drone.get("last_report", {})
	_check("survey: flying within the survey radius surveys the place and radios the scout report home",
		DroneSystem.is_surveyed(st(), "east_plain") and _alerts.has("drone_report") and String(rep.get("site", "")) == "east_plain"
		and String(rep.get("text", "")) == String(ScoutSystem.site("east_plain").report), "%s %s" % [_alerts, rep])
	_check("survey: it reveals the site's ore deposits exactly like the scout rover (and not the others)", not revealed_before
		and ScoutSystem.is_revealed(st(), "ore_hematite_a") and ScoutSystem.is_revealed(st(), "ore_hematite_b") and not ScoutSystem.is_revealed(st(), "ore_gypsum_a")
		and (rep.get("revealed", []) as Array).has("ore_hematite_a"), str(st().scout.get("revealed", {})))
	_check("survey: the colony counts the place as surveyed (map, goals) and a discovery is logged",
		ScoutSystem.is_surveyed(st(), "east_plain") and String((st().scout.surveyed as Dictionary).east_plain.get("by", "")) == "drone"
		and st().discoveries.any(func(d: Variant) -> bool: return d is Dictionary and String(d.get("kind", "")) == "drone_survey"))
	_req(&"drone_land")
	_reset_drone()


func _test_autopilot_refused_below_v3() -> void:
	_reset_drone()
	_at_pad()
	for lvl in [1, 2]:
		_set_level("scout_drone", lvl)
		var r := _req(&"drone_send", PAD, {"route": "south_slope"})
		_check("autopilot: refused at V%d with a plain message (needs V3)" % lvl, not r.ok and r.message.contains("V3") and DroneSystem.status(st()) == "docked", r.message)


func _test_autopilot_v3() -> void:
	_clear_surveys()
	_set_level("scout_drone", 3)
	_inside()
	var computer := _computer()
	me().position = CharacterState._v3(st().stations[String(computer)].position)
	var r := _req(&"drone_send", computer, {"route": "south_slope,west_dunes"})
	_check("autopilot V3: one place per trip (two are refused)", not r.ok and r.message.contains("1 place"), r.message)
	r = _req(&"drone_send", computer, {"route": "nowhere"})
	_check("autopilot V3: an unknown place is refused", not r.ok)
	r = _req(&"drone_send", computer, {"route": "south_slope"})
	_check("autopilot V3: it takes off for the chosen place by itself (sent from the colony computer)", r.ok and DroneSystem.status(st()) == "auto"
		and String(st().drone.target) == "south_slope" and DroneSystem.pilot(st()) == "", r.message)
	_inside()
	var watch := {"statuses": {}, "far": 0.0}
	var t := _run_until_docked(240.0, watch)
	var site := ScoutSystem.site_position("south_slope")
	var pad := DroneSystem.pad_position(st())
	var site_dist := Vector2(site.x - pad.x, site.z - pad.z).length()
	_check("autopilot V3: the host flies it there, surveys, comes back and lands while nobody watches (%.0f s)" % t,
		DroneSystem.status(st()) == "docked" and DroneSystem.is_surveyed(st(), "south_slope") and (watch.statuses as Dictionary).has("returning")
		and float(watch.far) > site_dist - 2.0, "%s far %.1f of %.1f" % [DroneSystem.status(st()), float(watch.far), site_dist])
	_check("autopilot V3: the survey revealed the gypsum deposit", ScoutSystem.is_revealed(st(), "ore_gypsum_a"))
	_inside()
	me().position = CharacterState._v3(st().stations[String(computer)].position)
	st().drone.battery = 1.0
	r = _req(&"drone_send", computer, {"route": "far_crater"})
	var r2 := _req(&"drone_recall", computer)
	_check("autopilot: it can be called home on the way", r.ok and r2.ok and DroneSystem.status(st()) == "returning", r2.message)
	_run_until_docked(120.0)
	_reset_drone()


func _test_route_v4() -> void:
	_clear_surveys()
	_set_level("scout_drone", 4)
	var computer := _computer()
	me().position = CharacterState._v3(st().stations[String(computer)].position)
	var r := _req(&"drone_send", computer, {"route": "east_plain,crash_field,south_slope,west_dunes,far_crater"})
	_check("route V4: at most 4 places", not r.ok and r.message.contains("4 places"), r.message)
	st().drone.battery = 0.1
	r = _req(&"drone_send", computer, {"route": "west_dunes,crash_field,far_crater"})
	_check("route V4: refused when the battery cannot hold the whole trip", not r.ok and r.message.contains("battery"), r.message)
	st().drone.battery = 1.0
	r = _req(&"drone_send", computer, {"route": "west_dunes,crash_field,far_crater"})
	_check("route V4: a route of three places is accepted", r.ok and (st().drone.route as Array).size() == 3, r.message)
	_inside()
	var watch := {"targets": [], "statuses": {}}
	_run_until_docked(300.0, watch)
	_check("route V4: it flies the waypoints in order, surveys each and lands", DroneSystem.status(st()) == "docked"
		and str(watch.targets) == str(["west_dunes", "crash_field", "far_crater"]) and DroneSystem.is_surveyed(st(), "west_dunes")
		and DroneSystem.is_surveyed(st(), "crash_field") and DroneSystem.is_surveyed(st(), "far_crater") and (st().drone.route as Array).is_empty(),
		"%s %s" % [watch.targets, DroneSystem.status(st())])
	_check("route V4: carbonate and olivine deposits are on the map now", ScoutSystem.is_revealed(st(), "ore_carbonate_a") and ScoutSystem.is_revealed(st(), "ore_olivine_a"))


func _test_save_load_and_replication() -> void:
	_set_level("scout_drone", 4)
	var computer := _computer()
	me().position = CharacterState._v3(st().stations[String(computer)].position)
	st().drone.battery = 1.0
	var r := _req(&"drone_send", computer, {"route": "east_plain,far_crater"})
	for i in 25:
		services.session.advance(0.2)
	var before := JSON.stringify(JSON.parse_string(JSON.stringify(st().drone)))
	var copy := ColonyState.from_dict(JSON.parse_string(JSON.stringify(st().to_dict())))
	_check("save: state.drone (mid-flight on a route) survives a JSON round trip", r.ok and JSON.stringify(copy.drone) == before
		and DroneSystem.status(copy) == "auto" and is_equal_approx(DroneSystem.battery(copy), DroneSystem.battery(st())), JSON.stringify(copy.drone))
	var replica := ColonyState.from_dict(st().to_dict())
	_check("replication: a client's copy (to_dict/from_dict) has the same drone: status, position, route, battery, level",
		DroneSystem.status(replica) == DroneSystem.status(st()) and DroneSystem.position(replica).distance_to(DroneSystem.position(st())) < 1e-4
		and str(replica.drone.route) == str(st().drone.route) and is_equal_approx(DroneSystem.battery(replica), DroneSystem.battery(st()))
		and DroneSystem.level(replica) == 4)
	var old := st().to_dict()
	old.erase("drone")
	var older := ColonyState.from_dict(old)
	DroneSystem.ensure(older)
	_check("save: an older save without the drone gets a docked, charged drone", DroneSystem.status(older) == "docked" and is_equal_approx(DroneSystem.battery(older), 1.0))
	_req(&"drone_recall", computer)
	_run_until_docked(120.0)
	_reset_drone()


func _test_coop_inputs() -> void:
	_reset_drone()
	_set_level("scout_drone", 1)
	var other := st().character(&"crew_2")
	var saved_peer := other.owner_peer
	other.owner_peer = 7                       # a client on peer 7 plays crew_2
	DroneSystem.take_control(st(), "crew_2")
	var pres: Node = (load(PRESENTER) as Script).new()
	root.add_child(pres)
	pres.call(&"setup", null, services, null)
	var yaw := float(st().drone.yaw)
	var start := DroneSystem.position(st())
	var good := {"pilot": "crew_2", "move": Vector2(0, 1), "climb": 0.0, "yaw": yaw}
	pres.call(&"_on_motion_extra", 9, "drone", good)
	pres.call(&"_on_motion_extra", 7, "drone", {"pilot": "crew_3", "move": Vector2(0, 1), "climb": 0.0, "yaw": yaw})
	pres.call(&"_on_motion_extra", 7, "drone", {"pilot": "crew_2", "move": Vector2(INF, 0), "climb": 0.0, "yaw": yaw})
	_check("co-op: the host refuses drone inputs from other peers, for another pilot, or with bad numbers", int(pres.get("inputs_refused")) == 3
		and int(pres.get("inputs_accepted")) == 0, "%s/%s" % [pres.get("inputs_accepted"), pres.get("inputs_refused")])
	for i in 8:
		pres.call(&"_on_motion_extra", 7, "drone", good)
		sys().call(&"advance", st(), 0.25, services.events)
	_check("co-op: inputs from the pilot's own peer (motion extra \"drone\") fly the drone on the host", int(pres.get("inputs_accepted")) == 8
		and DroneSystem.position(st()).distance_to(start) > 5.0, "%.1f m" % DroneSystem.position(st()).distance_to(start))
	var r := _req(&"drone_land")
	_check("co-op: only the pilot can hand the drone back", not r.ok)
	other.owner_peer = 0                       # the pilot's player left
	sys().call(&"advance", st(), 0.5, services.events)
	_check("co-op: when the pilot's player leaves, the drone flies home by itself", DroneSystem.status(st()) == "returning")
	other.owner_peer = saved_peer
	pres.queue_free()
	_reset_drone()


func _test_presenter() -> void:
	await _frames(2)                          # the co-op test's presenter is gone
	_reset_drone()
	_set_level("scout_drone", 1)
	var pres: Node = (load(PRESENTER) as Script).new()
	root.add_child(pres)
	pres.call(&"setup", null, services, null)
	var stages: AreaStagePresenter = (load(STAGES) as Script).new()
	root.add_child(stages)
	stages.setup(null, services, null)
	stages.refresh()
	await _frames(3)
	var body := pres.get("body") as Node3D
	var m := pres.call(&"model") as Node3D
	_check("presenter: the V1 model of the stage presenter rides on the drone body (docked on the pad)", m != null and String(m.name) == "Stage_V1"
		and body.global_position.distance_to(DroneSystem.dock_position(st())) < 0.05 and (pres.call(&"rotors") as Array).size() == 4,
		"%s %s" % [m.name if m != null else "none", body.global_position])
	_check("presenter: the pad model and its charger stand on the pad station", (pres.get("pad_model") as Node3D) != null
		and (pres.get("pad_model") as Node3D).global_position.distance_to(DroneSystem.pad_position(st())) < 0.01
		and (pres.get("pad_model") as Node3D).find_child("ChargerSolid", true, false) != null)
	_set_level("scout_drone", 3)
	stages.refresh()
	await _frames(2)
	m = pres.call(&"model") as Node3D
	_check("presenter: after an upgrade the drone shows the new level (V3: gimbal camera)", m != null and String(m.name) == "Stage_V3"
		and m.find_child("Gimbal*", true, false) != null and (pres.call(&"rotors") as Array).size() == 4, m.name if m != null else "none")
	_at_pad()
	var r := _req(&"drone_fly", PAD)
	await _frames(4)
	_check("pilot: taking control switches to the drone's follow camera and shows the drone HUD", r.ok and bool(pres.get("piloting"))
		and (pres.get("camera") as Camera3D).current and bool((pres.get("hud_widget") as Control).call(&"is_showing")), r.message)
	_check("pilot: the walking body is held still while flying", bool(pres.call(&"blocks_player_input")))
	pres.call(&"send_input", String(me().id), Vector2(0, 1), 0.0, float(st().drone.yaw))
	_check("pilot: on the host the presenter's input goes straight into the drone system", not (sys().call(&"input_now", st()) as Dictionary).is_empty())
	for i in 10:
		pres.call(&"send_input", String(me().id), Vector2(0, 1), 0.0, float(st().drone.yaw))
		services.session.advance(0.2)
		await process_frame
	await create_timer(0.6).timeout          # real time for the glide and the rotors to spin up
	_check("presenter: the body follows the flying drone and the rotors spin", body.global_position.distance_to(DroneSystem.position(st())) < 3.5
		and float(pres.call(&"rotor_speed")) > 1.0 and DroneSystem.distance_from_pad(st()) > 3.0,
		"%s vs %s, rotors %.1f" % [body.global_position, DroneSystem.position(st()), float(pres.call(&"rotor_speed"))])
	var text := String((pres.get("hud_widget") as Control).call(&"text"))
	_check("pilot: the HUD shows battery, radio range and the keys", text.contains("Battery") and text.contains("of 150 m") and text.contains("hand back"), text)
	var hb: ActionResult = pres.call(&"hand_back")
	await _frames(2)
	_check("pilot: E hands it back; the player's camera returns", hb.ok and not bool(pres.get("piloting")) and not (pres.get("camera") as Camera3D).current
		and DroneSystem.status(st()) == "returning")
	_run_until_docked(120.0)
	stages.queue_free()
	pres.queue_free()
	await _frames(2)
	_reset_drone()


func _test_panel() -> void:
	_reset_drone()
	_set_level("scout_drone", 1)
	_at_pad()
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var panel := StationPanels.for_station(PAD, services) as StationPanel
	_check("panel: the pad opens its own panel (scripts/ui/stations/drone_pad_station_panel.gd)", panel != null
		and panel.get_script() != null and (panel.get_script() as Script).resource_path.ends_with("drone_pad_station_panel.gd"))
	layer.add_child(panel)
	panel.refresh()
	var send := panel.get("send_button") as Button
	var checks: Dictionary = panel.get("site_checks")
	_check("panel V1: level and battery shown; the autopilot list is locked with a note about V3", panel.reading_text(&"level") == "V1"
		and panel.reading_text(&"battery").contains("100 %") and send.disabled and (checks.values() as Array).all(func(c: Variant) -> bool: return (c as CheckBox).disabled)
		and (panel.get("_autopilot_note") as Label).text.contains("V3"), (panel.get("_autopilot_note") as Label).text)
	_set_level("scout_drone", 4)
	panel.refresh()
	checks = panel.get("site_checks")
	panel.call(&"pick", ["east_plain", "south_slope"])
	_check("panel V4: places can be ticked into a route", not send.disabled and not (checks["east_plain"] as CheckBox).disabled
		and (checks["east_plain"] as CheckBox).button_pressed and (checks["south_slope"] as CheckBox).button_pressed)
	var r: ActionResult = panel.call(&"send_route")
	_check("panel V4: Send starts the autopilot on the ticked route", r.ok and DroneSystem.status(st()) == "auto" and str(st().drone.route) == str(["east_plain", "south_slope"]), r.message)
	panel.refresh()
	_check("panel: Take control is off while the drone is out; Call it home is shown", (panel.get("fly_button") as Button).disabled and (panel.get("recall_button") as Button).visible)
	(panel.get("recall_button") as Button).pressed.emit()
	_run_until_docked(120.0)
	st().drone.battery = 1.0
	_at_pad()
	panel.refresh()
	var fr: ActionResult = panel.call(&"take_control")
	_check("panel: Take control starts manual flight", fr.ok and DroneSystem.status(st()) == "manual" and DroneSystem.pilot(st()) == String(me().id), fr.message)
	_req(&"drone_land")
	_run_until_docked(120.0)
	await _frames(1)
	layer.queue_free()
	_reset_drone()


func _test_glbs() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var spans: Array[float] = []
	var ok := true
	var detail := PackedStringArray()
	for lvl in [1, 2, 3, 4]:
		var path := DroneModels.drone_path(lvl)
		var scene := load(path) as PackedScene
		if scene == null:
			ok = false
			detail.append("%s does not load" % path)
			continue
		var n := scene.instantiate() as Node3D
		holder.add_child(n)
		var box := _aabb(n)
		spans.append(maxf(box.size.x, box.size.z))
		var rotor_names := PackedStringArray()
		for r in DroneModels.rotors(n):
			rotor_names.append(String(r.name))
		rotor_names.sort()
		if str(rotor_names) != str(PackedStringArray(["RotorHub_BL", "RotorHub_BR", "RotorHub_FL", "RotorHub_FR"])):
			ok = false
			detail.append("V%d rotors %s" % [lvl, rotor_names])
		if absf(box.position.y) > 0.03 or box.size.x < 0.7 or box.size.x > 1.4:
			ok = false
			detail.append("V%d box %s" % [lvl, box])
		var has := func(pattern: String) -> bool: return n.find_child(pattern, true, false) != null
		var want: Dictionary = {1: [], 2: ["BatteryPod*"], 3: ["BatteryPod*", "Gimbal*", "Antenna_Whip*", "AutopilotPuck*"], 4: ["BatteryPod*", "Gimbal*", "SensorPod*", "LandingLight_FL*", "LongAntenna_Dish*"]}
		for p: String in want[lvl]:
			if not has.call(p):
				ok = false
				detail.append("V%d lacks %s" % [lvl, p])
		if lvl == 1 and (has.call("BatteryPod*") or has.call("Gimbal*")):
			ok = false
			detail.append("V1 has later parts")
		n.queue_free()
	_check("glbs: all four drone stages load, about 1 m across, origin at the feet, four named rotor hubs, the parts of each stage", ok, ", ".join(detail))
	_check("glbs: V2 has longer rotors than V1 (wider span)", spans.size() == 4 and spans[1] > spans[0] + 0.05, str(spans))
	var pad := load(DroneModels.PAD_PATH) as PackedScene
	var pn := pad.instantiate() as Node3D if pad != null else null
	if pn != null:
		holder.add_child(pn)
	var pbox := _aabb(pn) if pn != null else AABB()
	_check("glbs: the landing pad loads (about 2.5 m wide, charger cabinet on its +z side)", pn != null and pbox.size.x > 2.0 and pbox.size.x < 3.0
		and _cabinet_z(pn) > 1.0, "%s cabinet z %.2f" % [pbox, _cabinet_z(pn) if pn != null else 0.0])
	holder.queue_free()
	await _frames(1)


## Centre z of the pad's charger cabinet mesh (pad space; the pad is at the origin).
static func _cabinet_z(pad: Node3D) -> float:
	var m := pad.find_child("Charger_Cabinet*", true, false) as MeshInstance3D
	return (m.global_transform * m.get_aabb()).get_center().z if m != null else 0.0


static func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.global_transform * m.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


static func _v3(a: Variant) -> Vector3:
	return DroneSystem._v3(a)


## The game itself (without the 300 MB map): GameMain adds the drone presenter, the scout_drone stage rides on its
## body, E at the pad opens the panel and E again takes control, W flies, the walking body stays still, E hands back.
func _test_game_main() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/drone/game")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	var main := (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.load_world = false
	main.show_menu = false
	main.check_weather_updates = false
	main.save_directory = dir
	root.add_child(main)
	await _frames(30)
	var gs := main.services
	var gst := gs.state()
	var drone := main.get("drone") as Node
	var stages := main.area_stages.get("scout_drone") as AreaStagePresenter
	_check("game: GameMain adds the drone presenter, and the scout_drone stage rides on its body", drone != null and stages != null
		and stages.stage_node() != null and stages.stage_node().get_parent() == drone.get("body"),
		"%s %s" % [drone, stages.stage_node().get_parent() if stages != null and stages.stage_node() != null else null])
	var me2 := gs.local_character()
	var pad := DroneSystem.pad_position(gst) + Vector3(1.6, 0.05, 0.0)
	me2.suit_on = true
	main.player.teleport(pad, 0.0)
	me2.position = pad
	await _frames(3)
	TutorialSystem.skip_tutorial(gs.state(), gs.events)  # the pad is locked during the tutorial; this test is about the pad
	main._submit(&"use_station", PAD, {})
	await _frames(3)
	var top := main.ui.top()
	_check("game: E at the pad opens the drone pad panel", top != null and top.get_script() != null
		and (top.get_script() as Script).resource_path.ends_with("drone_pad_station_panel.gd"), str(top))
	var press := InputEventAction.new()
	press.action = &"interact"
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(4)
	var release := InputEventAction.new()
	release.action = &"interact"
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(4)
	_check("game: E again on the panel takes control; the panel closes and the walking body is held still",
		DroneSystem.status(gst) == "manual" and DroneSystem.pilot(gst) == String(me2.id) and not main.ui.is_open()
		and bool(drone.get("piloting")) and not main.player.input_enabled, "%s %s open=%s input=%s" % [DroneSystem.status(gst), DroneSystem.pilot(gst), main.ui.is_open(), main.player.input_enabled])
	var start := DroneSystem.position(gst)
	var body_start := main.player.global_position
	Input.action_press(&"move_forward")
	await create_timer(1.5).timeout
	Input.action_release(&"move_forward")
	var flown := Vector2(DroneSystem.position(gst).x - start.x, DroneSystem.position(gst).z - start.z).length()
	_check("game: W flies the drone (keys reach the host's drone system) while the astronaut stays at the pad", flown > 2.0
		and main.player.global_position.distance_to(body_start) < 0.3, "drone %.1f m, body %.2f m" % [flown, main.player.global_position.distance_to(body_start)])
	Input.action_press(&"interact")
	await _frames(4)
	_check("game: E hands the drone back; it flies home by itself", DroneSystem.status(gst) == "returning" and not bool(drone.get("piloting")))
	Input.action_release(&"interact")
	await _frames(4)
	_check("game: once E is let go the astronaut walks again", main.player.input_enabled)
	main.queue_free()
	await _frames(3)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
