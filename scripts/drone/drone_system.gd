extends RefCounted
## The flying scout drone (2026-11-14 upgrade paths), host side. No class_name: load it by path
## (const DroneSystem := preload("res://scripts/drone/drone_system.gd")).
##
## A post-system of the colony simulation (SessionService adds one instance to sim.post_systems). It runs on the HOST
## only, five times a real second, in REAL seconds (the drone flies in metres per second, not per game hour), and
## moves the drone: manual flight from the pilot's inputs, the autopilot's route, the flight home, the battery and the
## surveys. Clients receive state.drone with the colony and only draw it (DronePresenter).
##
## Levels (AreaLevels, track "scout_drone", data/area_levels.json): speed_mps, flight_seconds (battery), survey_radius_m,
## autopilot (0/1, V3+) and max_waypoints. The radio range is the command room's: command.drone_range_m. Flight rules
## shared by every level: data/drone.json. Every number is designer balance.
##
## state.drone (plain JSON dictionary, saved and replicated with the colony; ensure() fills it):
##   status: "docked" | "manual" | "auto" | "returning"
##             docked     on its pad, charging
##             manual     a player flies it (pilot); V1+
##             auto       the autopilot flies the route by itself (V3+), also while nobody watches
##             returning  flying home by itself (hand-back, low or empty battery, end of the route, recall)
##   pilot: character id of the player flying it in "manual", else ""
##   position: [x, y, z]       Godot metres; y is the real height (ground + altitude)
##   yaw: float                heading in radians (Godot: 0 faces -z)
##   vel: [x, y, z]            velocity in m/s (presenters glide between the 5 Hz updates with it)
##   battery: float            0..1 (full = flight_seconds of flying at this level)
##   route: [site ids]         autopilot waypoints still to fly, the current one first (V3: 1, V4: up to 4)
##   target: site id or ""     the waypoint flown to now
##   hover_left_s: float       seconds left filming the waypoint
##   surveyed: {site_id: {"sol", "at_hours", "by"}}   places this drone surveyed
##   last_report: {"site", "name", "text", "hazard", "sol", "at_hours", "revealed": [ore station ids]}
##   flights: int              take-offs so far
##   sent_by: character id of the last person who flew it or sent it
##   range_warned: bool        the 90 % radio-range warning was given on this flight (cleared below 85 %)
##   at_edge: bool             it is held at the edge of the radio range now
##   low_announced: bool       the low-battery turn-home was announced on this flight
## Surveys write the same reveal data as the scout rover (state.scout.revealed / surveyed, ScoutSystem's sites and
## reveal radius), so the map, the ore flags and the goals show what the drone found.

const DATA_PATH := "res://data/drone.json"
const SCRIPT_PATH := "res://scripts/drone/drone_system.gd"
const TRACK := "scout_drone"
const ALERT_REPORT := &"drone_report"
const ALERT_RANGE := &"drone_range"
const ALERT_BATTERY := &"drone_battery"
const ALERT_HOME := &"drone_home"
const STATUSES := ["docked", "manual", "auto", "returning"]
## Real seconds per substep when a long stretch is simulated at once, and the most simulated in one call.
const SUBSTEP_S := 0.25
const MAX_STEP_S := 120.0

static var _data: Dictionary = {}
static var _height: Resource = null
static var _height_loaded := false

## The session (for the clock: game hours -> real seconds), held weakly (the session owns this system). May be empty
## in tests that call fly() or advance() directly.
var _session: WeakRef = null
## Manual input from the pilot (host): {"pilot": id, "move": Vector2(right, forward) -1..1, "climb": -1..1, "yaw": rad}.
var _input := {}
var _input_age := 999.0


func _init(p_session: Object = null) -> void:
	_session = weakref(p_session) if p_session != null else null


# ================================================================ data

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data


static func num(key: String, fallback: float) -> float:
	return float(data().get(key, fallback))


## Level of the drone track (1..4).
static func level(state: ColonyState) -> int:
	return AreaLevels.level(state, TRACK)


static func speed_mps(state: ColonyState) -> float:
	return AreaLevels.effectf(state, TRACK, "speed_mps", 5.0)


static func flight_seconds(state: ColonyState) -> float:
	return maxf(1.0, AreaLevels.effectf(state, TRACK, "flight_seconds", 90.0))


static func survey_radius_m(state: ColonyState) -> float:
	return AreaLevels.effectf(state, TRACK, "survey_radius_m", 20.0)


static func has_autopilot(state: ColonyState) -> bool:
	return int(AreaLevels.effect(state, TRACK, "autopilot", 0)) > 0


static func max_waypoints(state: ColonyState) -> int:
	return int(AreaLevels.effect(state, TRACK, "max_waypoints", 0))


## The command room's radio range: the drone must stay this close to its pad (metres, horizontal).
static func range_m(state: ColonyState) -> float:
	return maxf(10.0, AreaLevels.effectf(state, "command", "drone_range_m", 150.0))


static func pad_id() -> String:
	return String(data().get("pad_station", "drone_pad"))


## The pad station's ground point (x, ground height, z).
static func pad_position(state: ColonyState) -> Vector3:
	var p := Vector3(23.5, 0.0, 18.0)
	if state != null and state.stations.has(pad_id()):
		p = _v3((state.stations[pad_id()] as Dictionary).get("position", [p.x, p.y, p.z]))
	return Vector3(p.x, ground(p.x, p.z), p.z)


## Where the drone stands when docked: on the pad's charging plate.
static func dock_position(state: ColonyState) -> Vector3:
	return pad_position(state) + Vector3(0.0, num("dock_height_m", 0.085), 0.0)


static func pad_yaw() -> float:
	return deg_to_rad(num("pad_yaw_deg", 180.0))


## Ground height at (x, z): the sampled terrain grid, or 0 without it.
static func ground(x: float, z: float) -> float:
	if not _height_loaded:
		_height_loaded = true
		if ResourceLoader.exists("res://data/terrain_height.res"):
			_height = load("res://data/terrain_height.res")
	if _height != null and _height.has_method("height_at"):
		return float(_height.call("height_at", x, z))
	return 0.0


# ================================================================ state helpers

## Fills missing drone fields with defaults (new games and older saves). The drone starts docked and charged.
static func ensure(state: ColonyState) -> void:
	var d := state.drone
	if not d.has("status") or not STATUSES.has(String(d.status)):
		d["status"] = "docked"
	if not d.has("position") or not (d.position is Array) or (d.position as Array).size() < 3:
		var p := dock_position(state)
		d["position"] = [p.x, p.y, p.z]
	if not d.has("yaw"):
		d["yaw"] = pad_yaw()
	if not d.has("vel") or not (d.vel is Array):
		d["vel"] = [0.0, 0.0, 0.0]
	if not d.has("battery"):
		d["battery"] = 1.0
	for key: String in ["surveyed", "last_report"]:
		if not d.has(key) or not (d[key] is Dictionary):
			d[key] = {}
	if not d.has("route") or not (d.route is Array):
		d["route"] = []
	for key: String in ["pilot", "target", "sent_by"]:
		if not d.has(key):
			d[key] = ""
	if not d.has("hover_left_s"):
		d["hover_left_s"] = 0.0
	if not d.has("flights"):
		d["flights"] = 0
	for key: String in ["range_warned", "at_edge", "low_announced"]:
		if not d.has(key):
			d[key] = false


static func status(state: ColonyState) -> String:
	return String(state.drone.get("status", "docked"))


static func is_flying(state: ColonyState) -> bool:
	return status(state) in ["manual", "auto", "returning"]


static func pilot(state: ColonyState) -> String:
	return String(state.drone.get("pilot", "")) if status(state) == "manual" else ""


static func position(state: ColonyState) -> Vector3:
	return _v3(state.drone.get("position", []))


static func battery(state: ColonyState) -> float:
	return clampf(float(state.drone.get("battery", 1.0)), 0.0, 1.0)


## Horizontal distance from the pad, metres.
static func distance_from_pad(state: ColonyState) -> float:
	var p := position(state)
	var pad := pad_position(state)
	return Vector2(p.x - pad.x, p.z - pad.z).length()


static func altitude(state: ColonyState) -> float:
	var p := position(state)
	return p.y - ground(p.x, p.z)


static func is_surveyed(state: ColonyState, site_id: String) -> bool:
	return (state.drone.get("surveyed", {}) as Dictionary).has(site_id)


## Seconds of flying the battery holds now.
static func seconds_left(state: ColonyState) -> float:
	return battery(state) * flight_seconds(state)


## Battery share needed to fly home from where the drone is now (horizontal leg plus the landing).
static func battery_to_home(state: ColonyState) -> float:
	var t := distance_from_pad(state) / maxf(0.5, speed_mps(state)) + maxf(0.0, altitude(state)) / maxf(0.5, num("climb_mps", 3.0))
	return t / flight_seconds(state)


## Seconds of flying a route needs: pad -> each site -> pad, hover at each, the climb and the landing.
static func route_seconds(state: ColonyState, route: Array) -> float:
	var at := pad_position(state)
	var dist := 0.0
	for id: Variant in route:
		var to := ScoutSystem.site_position(String(id))
		dist += Vector2(to.x - at.x, to.z - at.z).length()
		at = to
	var pad := pad_position(state)
	dist += Vector2(pad.x - at.x, pad.z - at.z).length()
	var climb := 2.0 * num("cruise_altitude_m", 12.0) / maxf(0.5, num("climb_mps", 3.0))
	return dist / maxf(0.5, speed_mps(state)) + climb + num("survey_hover_s", 5.0) * route.size()


## Parses "east_plain,far_crater" into an array of site ids (blank parts dropped).
static func parse_route(text: String) -> Array:
	var out: Array = []
	for part in text.split(",", false):
		var id := part.strip_edges()
		if id != "":
			out.append(id)
	return out


## Short status line for the panel and the HUD.
static func status_text(state: ColonyState) -> String:
	var d := state.drone
	match status(state):
		"docked":
			if battery(state) < 0.999:
				return "On its pad, charging (%d %%)." % roundi(battery(state) * 100.0)
			return "On its pad, fully charged and ready to fly."
		"manual":
			var c := state.character(StringName(pilot(state)))
			return "Flown by %s · %d m from the pad." % [c.display_name if c != null else "a crew member", roundi(distance_from_pad(state))]
		"auto":
			var t := String(d.get("target", ""))
			var name := String(ScoutSystem.site(t).get("name", t)).to_lower()
			if float(d.get("hover_left_s", 0.0)) > 0.0:
				return "Autopilot: filming the %s with its survey camera." % name
			var left := (d.get("route", []) as Array).size()
			return "Autopilot: flying to the %s (%d waypoint%s left)." % [name, left, "" if left == 1 else "s"]
		"returning":
			return "Flying home to its pad by itself · %d m to go." % roundi(distance_from_pad(state))
	return ""


# ================================================================ commands (called by DroneActions on the host)

## A player takes the controls at the pad: it lifts off and waits for their inputs.
static func take_control(state: ColonyState, actor_id: String) -> void:
	ensure(state)
	var d := state.drone
	var p := dock_position(state) + Vector3(0.0, num("lift_off_m", 1.2), 0.0)
	d.status = "manual"
	d.pilot = actor_id
	d.sent_by = actor_id
	d.position = [p.x, p.y, p.z]
	d.vel = [0.0, 0.0, 0.0]
	d.route = []
	d.target = ""
	d.hover_left_s = 0.0
	d.flights = int(d.flights) + 1
	_new_flight_flags(d)


## The pilot hands the drone back (or loses it): it flies home by itself.
static func release(state: ColonyState) -> void:
	ensure(state)
	var d := state.drone
	d.pilot = ""
	if is_flying(state):
		d.status = "returning"
		d.route = []
		d.target = ""
		d.hover_left_s = 0.0


## The autopilot takes off for `route` (site ids, already checked).
static func send(state: ColonyState, route: Array, actor_id: String) -> void:
	ensure(state)
	var d := state.drone
	var p := dock_position(state) + Vector3(0.0, num("lift_off_m", 1.2), 0.0)
	d.status = "auto"
	d.pilot = ""
	d.sent_by = actor_id
	d.position = [p.x, p.y, p.z]
	d.vel = [0.0, 0.0, 0.0]
	d.route = route.duplicate()
	d.target = String(route[0]) if not route.is_empty() else ""
	d.hover_left_s = 0.0
	d.flights = int(d.flights) + 1
	_new_flight_flags(d)


static func recall(state: ColonyState) -> void:
	release(state)


static func _new_flight_flags(d: Dictionary) -> void:
	d.range_warned = false
	d.at_edge = false
	d.low_announced = false


# ================================================================ manual input (host)

## The pilot's latest inputs. Ignored unless `pilot_id` flies the drone now. An input older than input_timeout_s
## counts as "let go of the sticks": the drone hovers.
func set_input(pilot_id: String, move: Vector2, climb: float, yaw: float) -> void:
	_input = {"pilot": pilot_id, "move": move.limit_length(1.0), "climb": clampf(climb, -1.0, 1.0), "yaw": wrapf(yaw, -PI, PI)}
	_input_age = 0.0


func input_now(state: ColonyState) -> Dictionary:
	if _input.is_empty() or _input_age > num("input_timeout_s", 0.6) or String(_input.get("pilot", "")) != pilot(state):
		return {}
	return _input


## The drone system in a session's simulation, or null.
static func find(p_session: Object) -> Object:
	if p_session == null:
		return null
	var sim: Variant = p_session.get("sim")
	if sim == null:
		return null
	for system: Variant in sim.post_systems:
		if system is Object and (system as Object).get_script() != null and ((system as Object).get_script() as Script).resource_path == SCRIPT_PATH:
			return system
	return null


# ================================================================ tick

func step(state: ColonyState, _balance: GameBalance, _phase: float, dt_hours: float, events: GameEvents) -> void:
	if dt_hours <= 0.0:
		return
	var per_s := GameConfig.SOL_HOURS / (20.0 * 60.0)
	var session: Object = _session.get_ref() if _session != null else null
	if session != null and session.get("clock") != null:
		per_s = float(session.get("clock").call("hours_per_real_second"))
	advance(state, minf(dt_hours / maxf(per_s, 1e-9), MAX_STEP_S), events)


## Flies the drone on by `dt_s` real seconds (in substeps).
func advance(state: ColonyState, dt_s: float, events: GameEvents) -> void:
	if state.drone.is_empty() or not state.drone.has("battery"):
		ensure(state)
	var left := dt_s
	while left > 1e-6:
		var dt := minf(left, SUBSTEP_S)
		_input_age += dt
		fly(state, dt, input_now(state), events)
		left -= dt


## One step of `dt` real seconds. `input` is the pilot's input ({} = hover) and is used only in "manual".
static func fly(state: ColonyState, dt: float, input: Dictionary, events: GameEvents) -> void:
	ensure(state)
	var d := state.drone
	var st := status(state)
	if st == "docked":
		var full := battery(state) >= 1.0
		d.battery = minf(1.0, battery(state) + num("charge_per_s", 0.0111) * dt)
		d.vel = [0.0, 0.0, 0.0]
		var dock := dock_position(state)
		d.position = [dock.x, dock.y, dock.z]
		if not full and battery(state) >= 1.0 and events != null:
			events.system_alert.emit(ALERT_BATTERY, &"info", "The scout drone is fully charged.")
		return
	if st == "manual":
		var c := state.character(StringName(pilot(state)))
		if c == null or not c.is_active():
			release(state)
			if events != null:
				events.system_alert.emit(ALERT_HOME, &"info", "Nobody is flying the scout drone any more, so it is flying home by itself.")
			st = "returning"
	# battery: every flying second costs 1 / flight_seconds
	var before := battery(state)
	d.battery = maxf(0.0, before - dt / flight_seconds(state))
	if st == "manual" or st == "auto":
		if battery(state) <= battery_to_home(state) + num("battery_reserve", 0.05):
			release(state)
			st = "returning"
			if not bool(d.low_announced):
				d.low_announced = true
				if events != null:
					events.system_alert.emit(ALERT_BATTERY, &"warn", "The scout drone's battery is low, so it turned round and is flying home by itself.")
	match st:
		"manual":
			_fly_manual(state, dt, input)
		"auto":
			_fly_auto(state, dt, events)
		"returning":
			_fly_home(state, dt, events)
	if is_flying(state):
		_keep_in_range(state, events)
		_survey_nearby(state, events)


static func _fly_manual(state: ColonyState, dt: float, input: Dictionary) -> void:
	var d := state.drone
	var yaw := float(input.get("yaw", float(d.yaw))) if not input.is_empty() else float(d.yaw)
	d.yaw = yaw
	var move: Vector2 = input.get("move", Vector2.ZERO) if not input.is_empty() else Vector2.ZERO
	var climb := float(input.get("climb", 0.0)) if not input.is_empty() else 0.0
	# Godot: forward is -z; the basis turns the stick into the drone's heading
	var wish := Basis(Vector3.UP, yaw) * Vector3(move.x, 0.0, -move.y) * speed_mps(state)
	wish.y = climb * num("climb_mps", 3.0)
	var vel := _v3(d.vel).move_toward(wish, num("accel_mps2", 8.0) * dt)
	_move(state, vel, dt)


static func _fly_auto(state: ColonyState, dt: float, events: GameEvents) -> void:
	var d := state.drone
	var target := String(d.get("target", ""))
	if ScoutSystem.site(target).is_empty():
		_next_waypoint(state, events)
		return
	if float(d.get("hover_left_s", 0.0)) > 0.0:
		# filming the waypoint: hover and turn slowly with the survey camera
		d.hover_left_s = float(d.hover_left_s) - dt
		d.yaw = wrapf(float(d.yaw) + num("turn_rate_rad_s", 1.2) * 0.5 * dt, -PI, PI)
		_move(state, _v3(d.vel).move_toward(Vector3.ZERO, num("accel_mps2", 8.0) * dt), dt)
		if float(d.hover_left_s) <= 0.0:
			_survey(state, target, events)
			_next_waypoint(state, events)
		return
	var to := ScoutSystem.site_position(target)
	if _cruise_to(state, to, speed_mps(state), dt):
		d.hover_left_s = num("survey_hover_s", 5.0)


static func _next_waypoint(state: ColonyState, events: GameEvents) -> void:
	var d := state.drone
	var route: Array = d.get("route", [])
	if not route.is_empty():
		route.pop_front()
	d.route = route
	d.hover_left_s = 0.0
	if route.is_empty():
		d.target = ""
		d.status = "returning"
		if events != null:
			events.system_alert.emit(ALERT_HOME, &"info", "The scout drone finished its route and is flying home.")
	else:
		d.target = String(route[0])


static func _fly_home(state: ColonyState, dt: float, events: GameEvents) -> void:
	var d := state.drone
	var dock := dock_position(state)
	var p := position(state)
	var speed := speed_mps(state) * (num("empty_return_speed_factor", 0.5) if battery(state) <= 0.0 else 1.0)
	var flat := Vector2(dock.x - p.x, dock.z - p.z)
	if flat.length() > 0.3:
		_cruise_to(state, dock, speed, dt, flat.length() < 4.0)
		return
	# over the pad: settle down onto the charging plate
	var climb := num("climb_mps", 3.0)
	var ny := move_toward(p.y, dock.y, climb * dt)
	d.position = [dock.x, ny, dock.z]
	d.vel = [0.0, (ny - p.y) / maxf(dt, 1e-6), 0.0]
	d.yaw = lerp_angle(float(d.yaw), pad_yaw(), clampf(dt * 2.0, 0.0, 1.0))
	if absf(ny - dock.y) < 0.02:
		d.status = "docked"
		d.position = [dock.x, dock.y, dock.z]
		d.vel = [0.0, 0.0, 0.0]
		d.yaw = pad_yaw()
		d.pilot = ""
		d.at_edge = false
		if events != null:
			events.system_alert.emit(ALERT_HOME, &"info", "The scout drone landed on its pad and is charging.")


## Flies toward `to` at cruise height (or down to landing height when `low`); faces the way it flies. True on arrival.
static func _cruise_to(state: ColonyState, to: Vector3, speed: float, dt: float, low := false) -> bool:
	var d := state.drone
	var p := position(state)
	var flat := Vector2(to.x - p.x, to.z - p.z)
	var want_y := ground(p.x, p.z) + num("cruise_altitude_m", 12.0)
	if low:
		want_y = to.y + num("lift_off_m", 1.2)
	var vy := clampf((want_y - p.y) / maxf(dt, 1e-6), -num("climb_mps", 3.0), num("climb_mps", 3.0))
	var step := speed * dt
	if flat.length() <= maxf(step, num("arrive_m", 1.5) if not low else 0.3):
		var arrive := Vector3(to.x, p.y + vy * dt, to.z)
		d.position = [arrive.x, arrive.y, arrive.z]
		d.vel = [0.0, vy, 0.0]
		return true
	var dir := flat.normalized()
	d.yaw = atan2(-dir.x, -dir.y)
	_move(state, Vector3(dir.x * speed, vy, dir.y * speed), dt)
	return false


## Moves by `vel` for `dt`, kept between min_clearance_m and max_altitude_m above the ground.
static func _move(state: ColonyState, vel: Vector3, dt: float) -> void:
	var d := state.drone
	var p := position(state) + vel * dt
	var g := ground(p.x, p.z)
	var lo := g + num("min_clearance_m", 0.6)
	var hi := g + num("max_altitude_m", 40.0)
	if p.y < lo:
		p.y = lo
		vel.y = maxf(vel.y, 0.0)
	elif p.y > hi:
		p.y = hi
		vel.y = minf(vel.y, 0.0)
	d.position = [p.x, p.y, p.z]
	d.vel = [vel.x, vel.y, vel.z]


## The radio range: a warning at range_warn_fraction, and the drone is held at the edge.
static func _keep_in_range(state: ColonyState, events: GameEvents) -> void:
	var d := state.drone
	var r := range_m(state)
	var pad := pad_position(state)
	var p := position(state)
	var flat := Vector2(p.x - pad.x, p.z - pad.z)
	var dist := flat.length()
	if dist > r:
		var edge := flat.normalized() * r
		d.position = [pad.x + edge.x, p.y, pad.z + edge.y]
		var v := _v3(d.vel)
		var out := Vector2(v.x, v.z).dot(flat.normalized())
		if out > 0.0:
			var keep := Vector2(v.x, v.z) - flat.normalized() * out
			d.vel = [keep.x, v.y, keep.y]
		if not bool(d.at_edge):
			d.at_edge = true
			if events != null:
				events.system_alert.emit(ALERT_RANGE, &"warn", "The scout drone reached the edge of the command room's radio range (%d m) and cannot fly further. Upgrade the command room for more range." % roundi(r))
	else:
		d.at_edge = dist >= r - 0.05
	if dist >= r * num("range_warn_fraction", 0.9) and not bool(d.range_warned):
		d.range_warned = true
		if events != null:
			events.system_alert.emit(ALERT_RANGE, &"warn", "Careful: the scout drone is near the edge of the radio range (%d of %d m)." % [roundi(minf(dist, r)), roundi(r)])
	elif dist < r * 0.85:
		d.range_warned = false


## Range state for HUDs: "ok", "warn" (past the warning line) or "edge".
static func range_state(state: ColonyState) -> String:
	var r := range_m(state)
	var dist := distance_from_pad(state)
	if dist >= r - 0.05:
		return "edge"
	if dist >= r * num("range_warn_fraction", 0.9):
		return "warn"
	return "ok"


# ================================================================ surveys

## Every site within survey_radius_m of the drone that it has not surveyed yet is surveyed now.
static func _survey_nearby(state: ColonyState, events: GameEvents) -> void:
	var p := position(state)
	var r := survey_radius_m(state)
	for s: Dictionary in ScoutSystem.sites():
		var id := String(s.get("id", ""))
		if is_surveyed(state, id):
			continue
		var c := ScoutSystem.site_position(id)
		if Vector2(c.x - p.x, c.z - p.z).length() <= r:
			_survey(state, id, events)


## Surveys `site_id` the way the scout rover does: every ore deposit within the site's reveal_radius_m is marked on the
## map (state.scout.revealed), the site counts as surveyed for the colony (state.scout.surveyed, by "drone"), and the
## site's own report (data/scout_sites.json) is radioed home. Returns the newly revealed ore station ids.
static func _survey(state: ColonyState, site_id: String, events: GameEvents) -> Array:
	var rec := ScoutSystem.site(site_id)
	if rec.is_empty() or is_surveyed(state, site_id):
		return []
	ScoutSystem.ensure(state)
	var d := state.drone
	var s := state.scout
	var centre := ScoutSystem.site_position(site_id)
	var radius := float(rec.get("reveal_radius_m", 12.0))
	var found: Array = []
	for id in ScoutSystem.ore_stations(state):
		var op := _v3((state.stations[id] as Dictionary).get("position", [0, 0, 0]))
		if Vector2(op.x, op.z).distance_to(Vector2(centre.x, centre.z)) <= radius and not ScoutSystem.is_revealed(state, id):
			(s.revealed as Dictionary)[id] = true
			found.append(id)
	var sol := int(floor(state.sim_hours / GameConfig.SOL_HOURS)) + 1
	var by := String(d.get("pilot", "")) if String(d.get("pilot", "")) != "" else String(d.get("sent_by", ""))
	(d.surveyed as Dictionary)[site_id] = {"sol": sol, "at_hours": state.sim_hours, "by": by}
	if not ScoutSystem.is_surveyed(state, site_id):
		(s.surveyed as Dictionary)[site_id] = {"sol": sol, "at_hours": state.sim_hours, "sent_by": by, "by": "drone"}
	var kinds := PackedStringArray()
	for id: String in found:
		var k := String(ScoutSystem.ore_info(ScoutSystem.ore_kind_of(state, id)).get("name", ScoutSystem.ore_kind_of(state, id)))
		if not kinds.has(k):
			kinds.append(k)
	var text := "Drone report from the %s: %s" % [String(rec.get("name", site_id)).to_lower(), String(rec.get("report", ""))]
	if not kinds.is_empty():
		text += " Ore marked on the map: %s." % ", ".join(kinds)
	d.last_report = {"site": site_id, "name": String(rec.get("name", site_id)), "text": String(rec.get("report", "")),
		"hazard": String(rec.get("hazard", "")), "sol": sol, "at_hours": state.sim_hours, "revealed": found.duplicate()}
	state.discoveries.append({"kind": "drone_survey", "id": site_id, "sol": sol, "at_hours": state.sim_hours, "text": text})
	if events != null:
		events.system_alert.emit(ALERT_REPORT, &"info", text)
		events.objective_changed.emit(&"scout_survey")
	return found


static func _v3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
