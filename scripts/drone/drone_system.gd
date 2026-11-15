extends RefCounted
## The flying scout drone (upgrade paths plan §6.2), host side. No class_name: load it by path
## (const DroneSystem := preload("res://scripts/drone/drone_system.gd")).
##
## A post-system of the colony simulation (SessionService adds one instance to sim.post_systems). It runs on the HOST
## only, in REAL seconds (the drone flies in metres per second, not per game hour), and moves the drone: manual flight
## from the pilot's inputs, the autopilot's flights, the flight home, the battery, the charging and the ore scans.
## Clients receive state.drone with the colony and only draw it (DronePresenter).
##
## Flight feel (2026-11-15, the owner's FPV example docs/revisions/reference/fpv_drone/flight_controller.gd): W A S D
## move the way the drone faces, the mouse sets the heading, Space up, Ctrl / Shift down; every response is
## exponential (horizontal 4.2, brake 6.5, vertical 7.5, yaw 28), with horizontal_speed = the level's speed_mps and
## vertical_speed = vertical_mps. The model and camera tilt (pitch 8, forward 7°, back 5°) is drawn by DronePresenter.
##
## Levels (AreaLevels, track "scout_drone"; data/drone.json "level_defaults" when a key is missing):
##   speed_mps, vertical_mps, flight_seconds (battery), flights_per_sol, survey_radius_m and ability:
##   "manual" (V1: fly it yourself) < "prescout" (V2: reveals ore deposits within survey_radius_m while flying and
##   radios a mineral report; "revisit" flies by itself to an explored spot) < "find_known" (V3: flies to the nearest
##   KNOWN deposit of an ore with units left and confirms it) < "scan_anywhere" (V4: flies a search pattern to the
##   nearest UNREVEALED deposit of an ore and reveals it). Every level has the abilities of the levels below.
## Battery rules: a flight starts only with a full battery and a flight left today (flights_per_sol); it always keeps
## enough to come home (turns home by itself when the battery holds only the trip home x home_margin + home_reserve_s);
## after each flight it charges on the pad for (1 - battery) x flight_seconds x charge_factor real seconds.
## The radio range is the command room's (command.drone_range_m). Flight rules: data/drone.json.
##
## state.drone (plain JSON dictionary, saved and replicated with the colony; ensure() fills it):
##   status: "docked" | "manual" | "auto" | "returning"
##             docked     on its pad, charging
##             manual     a player flies it (pilot)
##             auto       the autopilot flies a mission (revisit / find / scan, V2+), also while nobody watches
##             returning  flying home by itself (R, E hand-back, low battery, mission done, recall)
##   pilot: character id whose camera rides the drone: the pilot in "manual", and the same player still watching while
##          it flies home after R or a low battery ("" after E / when nobody watches)
##   position: [x, y, z]       Godot metres; y is the real height (ground + altitude)
##   yaw: float                heading in radians (Godot: 0 faces -z = north on the compass)
##   vel: [x, y, z]            velocity in m/s (presenters glide between the host updates with it)
##   battery: float            0..1 (full = flight_seconds of flying at this level)
##   flights: int              take-offs so far (all sols)
##   flights_today: int        take-offs on sol flights_sol
##   flights_sol: int          the sol flights_today counts (a new sol starts the count again)
##   flight_s: float           real seconds since this flight's take-off (HUD flight time)
##   far_m: float, far_pos: [x, y, z]   farthest point from the pad on this flight (becomes an explored spot)
##   found: [deposit ids]      deposits revealed on this flight (HUD pip row in manual flight)
##   mission: {} or {"mode": "revisit"|"find"|"scan", "ore": ore id, "target": spot id or deposit id, "label": text}
##   route: [{"pos": [x,y,z], "hover_s": s, "kind": "search"|"target"|"spot", "deposit": id, "spot": id, "label": text}]
##             autopilot waypoints still to fly, the current one first
##   targets_total, targets_done: int   waypoints of this flight's mission (HUD pip row)
##   target: label of the waypoint flown to now ("" when none)
##   hover_left_s: float       seconds left hovering over the current waypoint
##   home_reason: "" | "r" | "hand_back" | "battery" | "done" | "recall" | "pilot_left"
##   spots: [{"id", "name", "position": [x,y,z], "sol", "ores": [ore ids]}]  explored spots (newest last, max_spots)
##   spot_n: int               counter for spot ids
##   surveyed: {site_id: {"sol", "at_hours", "by"}}   scout-rover sites this drone photographed
##   last_report: {"kind": "site"|"minerals"|"find"|"scan"|"revisit", "name", "text", "sol", "at_hours", "ids": [...],
##                 "revealed": [...]}
##   report_n: int             +1 on every new report (the HUD pops the report up when it changes)
##   scan_left_s: float        seconds to the next ore scan
##   sent_by: character id of the last person who flew it or sent it
##   range_warned, at_edge, low_announced, charged_announced: bool   one-shot alert flags
## Surveys of scout-rover sites still write state.scout like the scout rover (photos at every level; the old ore
## stations are marked only from V2, the multispectral camera).

const DATA_PATH := "res://data/drone.json"
const SCRIPT_PATH := "res://scripts/drone/drone_system.gd"
const OreCatalog := preload("res://scripts/science/ore_catalog.gd")
const TRACK := "scout_drone"
const ALERT_REPORT := &"drone_report"
const ALERT_RANGE := &"drone_range"
const ALERT_BATTERY := &"drone_battery"
const ALERT_HOME := &"drone_home"
const STATUSES := ["docked", "manual", "auto", "returning"]
const ABILITIES := ["manual", "prescout", "find_known", "scan_anywhere"]
const ORE_IDS := ["regolith", "magnetite", "hematite", "iron_meteorite", "olivine", "clay", "gypsum", "sulfate", "sulfur",
	"carbonate", "silica", "ice", "perchlorate"]
## Real seconds per substep while flying (the exponential responses need short steps), and the most simulated in one call.
const SUBSTEP_S := 0.05
const MAX_STEP_S := 120.0

static var _data: Dictionary = {}
static var _height: Resource = null
static var _height_loaded := false

## The session (for the clock: game hours -> real seconds), held weakly (the session owns this system). May be empty
## in tests that call fly() or advance() directly.
var _session: WeakRef = null
## Manual input from the pilot (host): {"pilot": id, "move": Vector2(right, forward) -1..1, "climb": -1..1, "yaw": rad}.
## "yaw" is the heading the pilot's mouse asks for; the drone turns to it with the yaw response.
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


## A level effect: AreaLevels first, else data/drone.json level_defaults[key][level - 1], else `fallback`.
static func level_value(state: ColonyState, key: String, fallback: Variant) -> Variant:
	var v: Variant = AreaLevels.effect(state, TRACK, key, null) if state != null else null
	if v != null:
		return v
	var defaults: Variant = (data().get("level_defaults", {}) as Dictionary).get(key, null)
	if defaults is Array and not (defaults as Array).is_empty():
		var a: Array = defaults
		var lvl := level(state) if state != null else 1
		return a[clampi(lvl, 1, a.size()) - 1]
	return fallback


static func speed_mps(state: ColonyState) -> float:
	return maxf(0.5, float(level_value(state, "speed_mps", 3.0)))


static func vertical_mps(state: ColonyState) -> float:
	return maxf(0.5, float(level_value(state, "vertical_mps", 1.5)))


static func flight_seconds(state: ColonyState) -> float:
	return maxf(1.0, float(level_value(state, "flight_seconds", 50.0)))


static func flights_per_sol(state: ColonyState) -> int:
	return maxi(1, int(level_value(state, "flights_per_sol", 1)))


static func survey_radius_m(state: ColonyState) -> float:
	return maxf(1.0, float(level_value(state, "survey_radius_m", 20.0)))


## The level's ability ("manual" / "prescout" / "find_known" / "scan_anywhere").
static func ability(state: ColonyState) -> String:
	var a := String(level_value(state, "ability", "manual"))
	return a if ABILITIES.has(a) else "manual"


## True when the drone's level has `what` or a better ability (abilities add up level by level).
static func has_ability(state: ColonyState, what: String) -> bool:
	return ABILITIES.find(ability(state)) >= ABILITIES.find(what) and ABILITIES.has(what)


## Old name kept for callers: any flight by itself (V2+ revisit).
static func has_autopilot(state: ColonyState) -> bool:
	return has_ability(state, "prescout")


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


## Compass heading in degrees (0 = north = Godot -z, 90 = east = +x) for a yaw in radians.
static func heading_deg(yaw: float) -> float:
	return fposmod(rad_to_deg(-yaw), 360.0)


static func sol_now(state: ColonyState) -> int:
	return int(floor(state.sim_hours / GameConfig.SOL_HOURS)) + 1


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
	for key: String in ["surveyed", "last_report", "mission"]:
		if not d.has(key) or not (d[key] is Dictionary):
			d[key] = {}
	for key: String in ["route", "found", "spots"]:
		if not d.has(key) or not (d[key] is Array):
			d[key] = []
	# older saves flew routes of scout-site ids: turn them into waypoints
	var route: Array = d.route
	for i in route.size():
		if not (route[i] is Dictionary):
			var sid := String(route[i])
			var sp := ScoutSystem.site_position(sid)
			route[i] = {"pos": [sp.x, sp.y, sp.z], "hover_s": num("spot_hover_s", 4.0), "kind": "spot", "spot": "site:" + sid,
				"label": String(ScoutSystem.site(sid).get("name", sid))}
	for key: String in ["pilot", "target", "sent_by", "home_reason"]:
		if not d.has(key):
			d[key] = ""
	for key: String in ["hover_left_s", "flight_s", "far_m", "scan_left_s"]:
		if not d.has(key):
			d[key] = 0.0
	if not d.has("far_pos") or not (d.far_pos is Array):
		d["far_pos"] = []
	for key: String in ["flights", "flights_today", "flights_sol", "targets_total", "targets_done", "spot_n", "report_n"]:
		if not d.has(key):
			d[key] = 0
	for key: String in ["range_warned", "at_edge", "low_announced", "charged_announced"]:
		if not d.has(key):
			d[key] = false


static func status(state: ColonyState) -> String:
	return String(state.drone.get("status", "docked"))


static func is_flying(state: ColonyState) -> bool:
	return status(state) in ["manual", "auto", "returning"]


## The player who flies the drone now ("" unless status is "manual").
static func pilot(state: ColonyState) -> String:
	return String(state.drone.get("pilot", "")) if status(state) == "manual" else ""


## The player whose camera rides the drone: the pilot, or the same player watching it fly home after R / low battery.
static func watcher(state: ColonyState) -> String:
	return String(state.drone.get("pilot", "")) if is_flying(state) else ""


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


static func ground_speed(state: ColonyState) -> float:
	var v := _v3(state.drone.get("vel", []))
	return Vector2(v.x, v.z).length()


static func is_surveyed(state: ColonyState, site_id: String) -> bool:
	return (state.drone.get("surveyed", {}) as Dictionary).has(site_id)


## Seconds of flying the battery holds now.
static func seconds_left(state: ColonyState) -> float:
	return battery(state) * flight_seconds(state)


## Seconds the flight home takes from where the drone is now (horizontal leg at the level's speed, the descent, landing).
static func seconds_to_home(state: ColonyState) -> float:
	return distance_from_pad(state) / speed_mps(state) + maxf(0.0, altitude(state)) / vertical_mps(state) + num("landing_s", 2.0)


## Battery share the drone keeps for the flight home: the trip x home_margin + home_reserve_s.
static func battery_to_home(state: ColonyState) -> float:
	return (seconds_to_home(state) * num("home_margin", 1.1) + num("home_reserve_s", 3.0)) / flight_seconds(state)


## Real seconds the pad needs to charge the drone to full now.
static func seconds_to_full(state: ColonyState) -> float:
	return (1.0 - battery(state)) * flight_seconds(state) * num("charge_factor", 2.0)


## Flights flown on today's sol.
static func flights_today(state: ColonyState) -> int:
	var d := state.drone
	return int(d.get("flights_today", 0)) if int(d.get("flights_sol", 0)) == sol_now(state) else 0


static func flights_left_today(state: ColonyState) -> int:
	return maxi(0, flights_per_sol(state) - flights_today(state))


## Why the drone cannot take off now, or "" when it can (docked, fully charged, a flight left today).
static func launch_refusal(state: ColonyState) -> String:
	ensure(state)
	match status(state):
		"manual":
			return "Someone is already flying the drone."
		"auto", "returning":
			return "The drone is out flying. Wait until it lands on its pad."
	if flights_left_today(state) <= 0:
		var n := flights_per_sol(state)
		return "The drone has flown its %d flight%s for today. It can fly again tomorrow (sol %d). Upgrade it for more flights per sol." % [
			n, "" if n == 1 else "s", sol_now(state) + 1]
	if battery(state) < 0.999:
		return "The drone is charging on its pad (%d %%, about %d s to full). It takes off only with a full battery." % [
			floori(battery(state) * 100.0), ceili(seconds_to_full(state))]
	return ""


## Seconds of flying a list of waypoints needs: pad -> each waypoint -> pad, the hovers, the climb and the landing.
static func route_seconds(state: ColonyState, points: Array) -> float:
	var pad := pad_position(state)
	var at := pad
	var dist := 0.0
	var hover := 0.0
	for wp: Variant in points:
		if not (wp is Dictionary):
			continue
		var to := _v3((wp as Dictionary).get("pos", []))
		dist += Vector2(to.x - at.x, to.z - at.z).length()
		hover += float((wp as Dictionary).get("hover_s", 0.0))
		at = to
	dist += Vector2(pad.x - at.x, pad.z - at.z).length()
	var climb := 2.0 * num("cruise_altitude_m", 10.0) / vertical_mps(state)
	return dist / speed_mps(state) + climb + hover + num("landing_s", 2.0)


## True when a full battery flies `points` with the home margin to spare.
static func route_fits(state: ColonyState, points: Array) -> bool:
	return route_seconds(state, points) * num("home_margin", 1.1) + num("home_reserve_s", 3.0) <= flight_seconds(state)


## How far (metres) an autopilot flight can go out and come back on a full battery (panel text).
static func reach_m(state: ColonyState) -> float:
	var t := (flight_seconds(state) - num("home_reserve_s", 3.0)) / num("home_margin", 1.1)
	t -= 2.0 * num("cruise_altitude_m", 10.0) / vertical_mps(state) + num("landing_s", 2.0)
	return maxf(0.0, t * speed_mps(state) * 0.5)


## Short status line for the panel.
static func status_text(state: ColonyState) -> String:
	var d := state.drone
	match status(state):
		"docked":
			if battery(state) < 0.999:
				return "On its pad, charging: %d %%, about %d s to full." % [floori(battery(state) * 100.0), ceili(seconds_to_full(state))]
			if flights_left_today(state) <= 0:
				return "On its pad, charged. No flights left today."
			return "On its pad, fully charged and ready to fly."
		"manual":
			var c := state.character(StringName(pilot(state)))
			return "Flown by %s · %d m from the pad." % [c.display_name if c != null else "a crew member", roundi(distance_from_pad(state))]
		"auto":
			var name := String(d.get("target", ""))
			if float(d.get("hover_left_s", 0.0)) > 0.0:
				return "Autopilot: scanning over %s." % name
			return "Autopilot: flying to %s (%d of %d)." % [name, int(d.get("targets_done", 0)) + 1, maxi(1, int(d.get("targets_total", 1)))]
		"returning":
			return "Flying home to its pad by itself · %d m to go." % roundi(distance_from_pad(state))
	return ""


# ================================================================ ores (OreCatalog, scripts/science/ore_catalog.gd)

## Every ore id the catalog knows.
static func ore_ids() -> PackedStringArray:
	var out := PackedStringArray()
	var raw: Variant = OreCatalog.types()
	if raw is Dictionary:
		for k: Variant in (raw as Dictionary).keys():
			out.append(String(k))
	elif raw is Array:
		for t: Variant in raw:
			if t is Dictionary:
				out.append(String((t as Dictionary).get("id", "")))
			else:
				out.append(String(t))
	if out.is_empty():
		out = PackedStringArray(ORE_IDS)
	return out


## "Rust rock (hematite)" (OreCatalog.label).
static func ore_name(ore_id: String) -> String:
	return String(OreCatalog.label(ore_id))


## The same inside a sentence: "rust rock (hematite)".
static func ore_words(ore_id: String) -> String:
	return String(OreCatalog.label_in_sentence(ore_id))


static func _dep_id(v: Variant) -> String:
	return String((v as Dictionary).get("id", "")) if v is Dictionary else String(v)


static func _dep_pos(dep: Dictionary) -> Vector3:
	var p := _v3(dep.get("position", []))
	return Vector3(p.x, ground(p.x, p.z), p.z)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Known (revealed) deposits of `ore_id` with units left (OreCatalog.known_deposits), nearest to the pad first.
static func known_with_units(state: ColonyState, ore_id: String) -> Array:
	var out: Array = []
	for v: Variant in OreCatalog.known_deposits(state, ore_id):
		if v is Dictionary and OreCatalog.units_left(state, _dep_id(v)) > 0:
			out.append(v)
	return _by_distance(state, out)


## Deposits of `ore_id` nobody revealed yet, nearest to the pad first.
static func unrevealed(state: ColonyState, ore_id: String) -> Array:
	var out: Array = []
	for v: Variant in OreCatalog.deposits_of(ore_id):
		if v is Dictionary and not OreCatalog.is_revealed(state, _dep_id(v)):
			out.append(v)
	return _by_distance(state, out)


static func _by_distance(state: ColonyState, deps: Array) -> Array:
	var pad := pad_position(state)
	var out := deps.duplicate()
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		return _flat(_dep_pos(a as Dictionary), pad) < _flat(_dep_pos(b as Dictionary), pad))
	return out


# ================================================================ explored spots (V2 revisit)

## Every place the drone can revisit: its own explored spots and the scout-rover sites already surveyed
## ({"id", "name", "position": Vector3, "far_m"}), nearest first.
static func revisit_places(state: ColonyState) -> Array:
	var out: Array = []
	var pad := pad_position(state)
	for s: Variant in state.drone.get("spots", []):
		if s is Dictionary:
			var p := _v3((s as Dictionary).get("position", []))
			out.append({"id": String((s as Dictionary).get("id", "")), "name": String((s as Dictionary).get("name", "")), "position": p, "far_m": _flat(p, pad)})
	for site: Dictionary in ScoutSystem.sites():
		var sid := String(site.get("id", ""))
		if is_surveyed(state, sid) or ScoutSystem.is_surveyed(state, sid):
			var p := ScoutSystem.site_position(sid)
			out.append({"id": "site:" + sid, "name": String(site.get("name", sid)), "position": p, "far_m": _flat(p, pad)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.far_m) < float(b.far_m))
	return out


static func revisit_place(state: ColonyState, place_id: String) -> Dictionary:
	for p: Dictionary in revisit_places(state):
		if String(p.id) == place_id:
			return p
	return {}


## Remembers an explored spot (merged with one closer than spot_merge_m; the oldest dropped past max_spots).
static func _remember_spot(state: ColonyState, at: Vector3, name: String, ores: Array) -> void:
	var d := state.drone
	if _flat(at, pad_position(state)) < num("spot_min_m", 15.0):
		return
	var spots: Array = d.spots
	for s: Variant in spots:
		if s is Dictionary and _flat(_v3((s as Dictionary).get("position", [])), at) < num("spot_merge_m", 10.0):
			var have: Array = (s as Dictionary).get("ores", [])
			for o: Variant in ores:
				if not have.has(o):
					have.append(o)
			(s as Dictionary)["ores"] = have
			if not ores.is_empty():
				(s as Dictionary)["name"] = name
			return
	d.spot_n = int(d.spot_n) + 1
	spots.append({"id": "spot_%d" % int(d.spot_n), "name": name, "position": [at.x, ground(at.x, at.z), at.z],
		"sol": sol_now(state), "ores": ores.duplicate()})
	while spots.size() > int(num("max_spots", 12.0)):
		spots.pop_front()


## "Spot 3 · 64 m north-east" for a point.
static func _spot_name(state: ColonyState, at: Vector3) -> String:
	var pad := pad_position(state)
	var dir := Vector2(at.x - pad.x, at.z - pad.z)
	var points := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	var bearing := fposmod(rad_to_deg(atan2(dir.x, -dir.y)), 360.0)
	return "Spot %d · %d m %s" % [int(state.drone.get("spot_n", 0)) + 1, roundi(dir.length()), points[roundi(bearing / 45.0) % 8]]


# ================================================================ mission planning (checked by DroneActions)

## Plans an autopilot flight. mode: "revisit" (target = a revisit place id), "find" (target = ore id, V3+) or "scan"
## (target = ore id, V4). Returns {"ok": bool, "text": refusal or summary, "route": [...], "mission": {...}, "seconds"}.
static func plan(state: ColonyState, mode: String, target: String) -> Dictionary:
	ensure(state)
	match mode:
		"revisit":
			return _plan_revisit(state, target)
		"find":
			return _plan_find(state, target)
		"scan":
			return _plan_scan(state, target)
	return {"ok": false, "text": "The drone does not know that kind of flight."}


static func _plan_revisit(state: ColonyState, place_id: String) -> Dictionary:
	if not has_ability(state, "prescout"):
		return {"ok": false, "text": "This drone cannot fly by itself yet. Upgrade it to V2 at the drone pad. Until then, fly it yourself: press E at the pad."}
	var place := revisit_place(state, place_id)
	if place.is_empty():
		return {"ok": false, "text": "Pick a place the drone has explored before."}
	var p: Vector3 = place.position
	var far := _flat(p, pad_position(state))
	if far > range_m(state):
		return {"ok": false, "text": "%s is %d m away, but the command room's radio reaches only %d m." % [String(place.name), roundi(far), roundi(range_m(state))]}
	var route: Array = [{"pos": [p.x, p.y, p.z], "hover_s": num("spot_hover_s", 4.0), "kind": "spot", "spot": place_id, "label": String(place.name)}]
	if not route_fits(state, route):
		return {"ok": false, "text": "%s is %d m away: too far for one battery at this level (out and back about %d m)." % [String(place.name), roundi(far), roundi(reach_m(state))]}
	var secs := route_seconds(state, route)
	return {"ok": true, "route": route, "seconds": secs, "mission": {"mode": "revisit", "ore": "", "target": place_id, "label": String(place.name)},
		"text": "The drone is flying back to %s by itself to scan it again (about %d s there and back)." % [String(place.name), roundi(secs)]}


static func _plan_find(state: ColonyState, ore_id: String) -> Dictionary:
	if not has_ability(state, "find_known"):
		return {"ok": false, "text": "Finding an ore needs the V3 drone (smart search). Upgrade it at the drone pad."}
	if not ore_ids().has(ore_id):
		return {"ok": false, "text": "Pick an ore first."}
	var known := known_with_units(state, ore_id)
	if known.is_empty():
		return {"ok": false, "text": "No known %s with anything left to mine. Scout for it first%s." % [ore_words(ore_id), " (V4 can scan for it)" if not has_ability(state, "scan_anywhere") else " with Scan"]}
	for dep: Dictionary in known:
		var p := _dep_pos(dep)
		if _flat(p, pad_position(state)) > range_m(state):
			continue
		var route: Array = [{"pos": [p.x, p.y, p.z], "hover_s": num("target_hover_s", 4.0), "kind": "target", "deposit": _dep_id(dep),
			"label": "the %s deposit" % ore_words(ore_id)}]
		if not route_fits(state, route):
			continue
		var secs := route_seconds(state, route)
		return {"ok": true, "route": route, "seconds": secs, "mission": {"mode": "find", "ore": ore_id, "target": _dep_id(dep), "label": ore_name(ore_id)},
			"text": "The drone is flying to the nearest known %s, %d m away, to check it is still there (about %d s there and back)." % [
				ore_words(ore_id), roundi(_flat(p, pad_position(state))), roundi(secs)]}
	return {"ok": false, "text": "Every known %s is too far for one battery at this level (out and back about %d m)." % [ore_words(ore_id), roundi(reach_m(state))]}


static func _plan_scan(state: ColonyState, ore_id: String) -> Dictionary:
	if not has_ability(state, "scan_anywhere"):
		return {"ok": false, "text": "Scanning for an ore anywhere needs the V4 drone (ground radar). Upgrade it at the drone pad."}
	if not ore_ids().has(ore_id):
		return {"ok": false, "text": "Pick an ore first."}
	var pad := pad_position(state)
	for dep: Dictionary in unrevealed(state, ore_id):
		var p := _dep_pos(dep)
		if _flat(p, pad) > range_m(state):
			continue
		var route := _search_pattern(state, p)
		route.append({"pos": [p.x, p.y, p.z], "hover_s": num("target_hover_s", 4.0), "kind": "target", "deposit": _dep_id(dep),
			"label": "the search area"})
		if not route_fits(state, route):
			continue
		var secs := route_seconds(state, route)
		return {"ok": true, "route": route, "seconds": secs, "mission": {"mode": "scan", "ore": ore_id, "target": _dep_id(dep), "label": ore_name(ore_id)},
			"text": "The drone is flying a search pattern with its ground radar, looking for %s (about %d s there and back)." % [ore_words(ore_id), roundi(secs)]}
	return {"ok": false, "text": "The drone's radar finds no unmapped %s it can reach on one battery from here." % ore_words(ore_id)}


## Zig-zag legs from the pad toward `to` (search_legs points, search_offset_m to the side, narrowing).
static func _search_pattern(state: ColonyState, to: Vector3) -> Array:
	var pad := pad_position(state)
	var v := Vector2(to.x - pad.x, to.z - pad.z)
	var out: Array = []
	if v.length() < 1.0:
		return out
	var side := Vector2(-v.y, v.x).normalized()
	var offset := minf(num("search_offset_m", 14.0), v.length() * 0.3)
	var legs := int(num("search_legs", 2.0))
	for i in legs:
		var t := float(i + 1) / float(legs + 1)
		var s := (1.0 if i % 2 == 0 else -1.0) * offset * (1.0 - 0.5 * t)
		var q := Vector2(pad.x, pad.z) + v * t + side * s
		out.append({"pos": [q.x, ground(q.x, q.y), q.y], "hover_s": 0.0, "kind": "search", "label": "the search area"})
	return out


# ================================================================ commands (called by DroneActions on the host)

## A player takes the controls at the pad: it lifts off and waits for their inputs.
static func take_control(state: ColonyState, actor_id: String) -> void:
	ensure(state)
	var d := state.drone
	_start_flight(state, actor_id)
	d.status = "manual"
	d.pilot = actor_id


## The autopilot takes off for a planned mission (plan()["route"] / ["mission"], already checked).
static func send_mission(state: ColonyState, route: Array, mission: Dictionary, actor_id: String) -> void:
	ensure(state)
	var d := state.drone
	_start_flight(state, actor_id)
	d.status = "auto"
	d.pilot = ""
	d.route = route.duplicate(true)
	d.mission = mission.duplicate(true)
	d.targets_total = route.size()
	d.target = String((route[0] as Dictionary).get("label", "")) if not route.is_empty() else ""


static func _start_flight(state: ColonyState, actor_id: String) -> void:
	var d := state.drone
	var p := dock_position(state) + Vector3(0.0, num("lift_off_m", 1.2), 0.0)
	var sol := sol_now(state)
	if int(d.get("flights_sol", 0)) != sol:
		d.flights_sol = sol
		d.flights_today = 0
	d.flights_today = int(d.flights_today) + 1
	d.flights = int(d.flights) + 1
	d.sent_by = actor_id
	d.position = [p.x, p.y, p.z]
	d.vel = [0.0, 0.0, 0.0]
	d.route = []
	d.mission = {}
	d.target = ""
	d.hover_left_s = 0.0
	d.targets_total = 0
	d.targets_done = 0
	d.flight_s = 0.0
	d.far_m = 0.0
	d.far_pos = []
	d.found = []
	d.scan_left_s = 0.0
	d.home_reason = ""
	d.range_warned = false
	d.at_edge = false
	d.low_announced = false
	d.charged_announced = false


## R: the drone flies home by itself now; the pilot keeps watching through its camera (AUTO on the HUD).
static func fly_home(state: ColonyState, reason := "r") -> void:
	ensure(state)
	var d := state.drone
	if not is_flying(state):
		return
	d.status = "returning"
	d.route = []
	d.target = ""
	d.hover_left_s = 0.0
	d.home_reason = reason


## E: the pilot (or the player watching) hands the drone back; it flies home by itself and their camera returns.
static func release(state: ColonyState, reason := "hand_back") -> void:
	ensure(state)
	var d := state.drone
	var was_manual := status(state) == "manual"
	d.pilot = ""
	if was_manual:
		fly_home(state, reason)


## The autopilot is called home from the panel.
static func recall(state: ColonyState) -> void:
	fly_home(state, "recall")


# ================================================================ manual input (host)

## The pilot's latest inputs. Ignored unless `pilot_id` flies the drone now. An input older than input_timeout_s
## counts as "let go of the sticks": the drone brakes and hovers. `yaw` is the heading the mouse asks for.
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


## Flies the drone on by `dt_s` real seconds (in substeps; on the pad it charges in one step).
func advance(state: ColonyState, dt_s: float, events: GameEvents) -> void:
	if state.drone.is_empty() or not state.drone.has("battery"):
		ensure(state)
	if status(state) == "docked":
		_input_age += dt_s
		fly(state, dt_s, {}, events)
		return
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
	if status(state) == "docked":
		_charge(state, dt, events)
		return
	# the player flying or watching left the game
	var who := String(d.get("pilot", ""))
	if who != "":
		var c := state.character(StringName(who))
		if c == null or not c.is_active():
			var was_manual := status(state) == "manual"
			d.pilot = ""
			if was_manual:
				fly_home(state, "pilot_left")
				if events != null:
					events.system_alert.emit(ALERT_HOME, &"info", "Nobody is flying the scout drone any more, so it is flying home by itself.")
	d.flight_s = float(d.flight_s) + dt
	# battery: every flying second costs 1 / flight_seconds; it always keeps enough to come home
	d.battery = maxf(0.0, battery(state) - dt / flight_seconds(state))
	var st := status(state)
	if (st == "manual" or st == "auto") and battery(state) <= battery_to_home(state):
		fly_home(state, "battery")
		st = "returning"
		if not bool(d.low_announced):
			d.low_announced = true
			if events != null:
				events.system_alert.emit(ALERT_BATTERY, &"warn", "The scout drone kept just enough battery to come home, so it turned round and is flying home by itself.")
	match st:
		"manual":
			_fly_manual(state, dt, input)
		"auto":
			_fly_auto(state, dt, events)
		"returning":
			_fly_home(state, dt, events)
	if is_flying(state):
		_keep_in_range(state, events)
		var far := distance_from_pad(state)
		if far > float(d.far_m):
			d.far_m = far
			var p := position(state)
			d.far_pos = [p.x, p.y, p.z]
		d.scan_left_s = float(d.scan_left_s) - dt
		if float(d.scan_left_s) <= 0.0:
			d.scan_left_s = num("scan_interval_s", 0.5)
			_survey_nearby(state, events)
			_scan_ores(state, events)


static func _charge(state: ColonyState, dt: float, events: GameEvents) -> void:
	var d := state.drone
	var full_before := battery(state) >= 0.999
	d.battery = minf(1.0, battery(state) + dt / (flight_seconds(state) * maxf(0.01, num("charge_factor", 2.0))))
	d.vel = [0.0, 0.0, 0.0]
	var dock := dock_position(state)
	d.position = [dock.x, dock.y, dock.z]
	if not full_before and battery(state) >= 0.999 and not bool(d.get("charged_announced", false)):
		d.battery = 1.0
		d.charged_announced = true
		if events != null:
			var left := flights_left_today(state)
			events.system_alert.emit(ALERT_BATTERY, &"info", "The scout drone is fully charged. %s" % (
				"Flights left today: %d." % left if left > 0 else "No flights left today; it can fly again tomorrow."))


## The FPV model: the heading eases to the mouse's, W A S D push the way it faces, Space / Ctrl climb and sink,
## letting go brakes harder than pushing accelerates.
static func _fly_manual(state: ColonyState, dt: float, input: Dictionary) -> void:
	var d := state.drone
	var yaw := float(d.yaw)
	var target_yaw := float(input.get("yaw", yaw)) if not input.is_empty() else yaw
	yaw = lerp_angle(yaw, target_yaw, 1.0 - exp(-num("yaw_response", 28.0) * dt))
	d.yaw = wrapf(yaw, -PI, PI)
	var move: Vector2 = input.get("move", Vector2.ZERO) if not input.is_empty() else Vector2.ZERO
	var climb := float(input.get("climb", 0.0)) if not input.is_empty() else 0.0
	var vel := _v3(d.vel)
	# Godot: forward is -z; only the heading turns the stick (the tilt is drawn, it does not steer)
	var planar_target := Basis(Vector3.UP, yaw) * Vector3(move.x, 0.0, -move.y) * speed_mps(state)
	var planar := Vector2(vel.x, vel.z)
	var response := num("brake_response", 6.5) if move.is_zero_approx() else num("horizontal_response", 4.2)
	planar = planar.lerp(Vector2(planar_target.x, planar_target.z), 1.0 - exp(-response * dt))
	if move.is_zero_approx() and planar.length_squared() < 0.000001:
		planar = Vector2.ZERO
	var vy := lerpf(vel.y, climb * vertical_mps(state), 1.0 - exp(-num("vertical_response", 7.5) * dt))
	if is_zero_approx(climb) and absf(vy) < 0.001:
		vy = 0.0
	_move(state, Vector3(planar.x, vy, planar.y), dt)


static func _fly_auto(state: ColonyState, dt: float, events: GameEvents) -> void:
	var d := state.drone
	var route: Array = d.get("route", [])
	if route.is_empty() or not (route[0] is Dictionary):
		_mission_done(state, events)
		return
	var wp: Dictionary = route[0]
	d.target = String(wp.get("label", ""))
	if float(d.get("hover_left_s", 0.0)) > 0.0:
		# over the waypoint: hover and turn slowly while the sensors scan
		d.hover_left_s = float(d.hover_left_s) - dt
		d.yaw = wrapf(float(d.yaw) + num("hover_turn_rad_s", 0.6) * dt, -PI, PI)
		_ease_to(state, Vector3.ZERO, dt)
		if float(d.hover_left_s) <= 0.0:
			_finish_waypoint(state, wp, events)
		return
	if _cruise_to(state, _v3(wp.get("pos", [])), speed_mps(state), dt):
		if float(wp.get("hover_s", 0.0)) > 0.0:
			d.hover_left_s = float(wp.get("hover_s", 0.0))
		else:
			_finish_waypoint(state, wp, events)


static func _finish_waypoint(state: ColonyState, wp: Dictionary, events: GameEvents) -> void:
	var d := state.drone
	var mission: Dictionary = d.get("mission", {})
	match String(wp.get("kind", "")):
		"target":
			if String(mission.get("mode", "")) == "find":
				_confirm_known(state, String(wp.get("deposit", "")), String(mission.get("ore", "")), events)
			elif String(mission.get("mode", "")) == "scan":
				_reveal_found(state, String(wp.get("deposit", "")), String(mission.get("ore", "")), events)
		"spot":
			_rescan_spot(state, wp, events)
	d.targets_done = int(d.get("targets_done", 0)) + 1
	d.hover_left_s = 0.0
	var route: Array = d.get("route", [])
	if not route.is_empty():
		route.pop_front()
	d.route = route
	if route.is_empty():
		_mission_done(state, events)


static func _mission_done(state: ColonyState, events: GameEvents) -> void:
	fly_home(state, "done")
	if events != null:
		events.system_alert.emit(ALERT_HOME, &"info", "The scout drone finished its flight and is flying home.")


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
	var ny := move_toward(p.y, dock.y, vertical_mps(state) * dt)
	d.position = [dock.x, ny, dock.z]
	d.vel = [0.0, (ny - p.y) / maxf(dt, 1e-6), 0.0]
	d.yaw = lerp_angle(float(d.yaw), pad_yaw(), clampf(dt * 2.0, 0.0, 1.0))
	if absf(ny - dock.y) < 0.02:
		_land(state, events)


static func _land(state: ColonyState, events: GameEvents) -> void:
	var d := state.drone
	var dock := dock_position(state)
	d.status = "docked"
	d.position = [dock.x, dock.y, dock.z]
	d.vel = [0.0, 0.0, 0.0]
	d.yaw = pad_yaw()
	d.pilot = ""
	d.at_edge = false
	d.route = []
	d.target = ""
	d.hover_left_s = 0.0
	d.charged_announced = false
	# the farthest point of a flight becomes an explored spot (revisit, V2+)
	var far_pos := _v3(d.get("far_pos", []))
	if (d.get("far_pos", []) as Array).size() >= 3 and float(d.get("far_m", 0.0)) >= num("spot_min_m", 15.0):
		_remember_spot(state, far_pos, _spot_name(state, far_pos), [])
	if events != null:
		var left := flights_left_today(state)
		events.system_alert.emit(ALERT_HOME, &"info", "The scout drone landed on its pad and is charging (about %d s to full). %s" % [
			ceili(seconds_to_full(state)), "Flights left today: %d." % left if left > 0 else "No flights left today."])


## Eases the velocity toward `wish` with the FPV responses (horizontal, brake, vertical).
static func _ease_to(state: ColonyState, wish: Vector3, dt: float) -> void:
	var vel := _v3(state.drone.vel)
	var planar := Vector2(vel.x, vel.z)
	var want := Vector2(wish.x, wish.z)
	var response := num("brake_response", 6.5) if want.length() < planar.length() else num("horizontal_response", 4.2)
	planar = planar.lerp(want, 1.0 - exp(-response * dt))
	var vy := lerpf(vel.y, wish.y, 1.0 - exp(-num("vertical_response", 7.5) * dt))
	_move(state, Vector3(planar.x, vy, planar.y), dt)


## Flies toward `to` at cruise height (or down to landing height when `low`), easing in and slowing near it; turns to
## face the way it flies. True on arrival.
static func _cruise_to(state: ColonyState, to: Vector3, speed: float, dt: float, low := false) -> bool:
	var d := state.drone
	var p := position(state)
	var flat := Vector2(to.x - p.x, to.z - p.z)
	var want_y := ground(p.x, p.z) + num("cruise_altitude_m", 10.0)
	if low:
		want_y = to.y + num("lift_off_m", 1.2)
	var vmax := vertical_mps(state)
	var vy := clampf((want_y - p.y) * 1.5, -vmax, vmax)
	var arrive := num("arrive_m", 1.5) if not low else 0.3
	if flat.length() <= maxf(arrive, speed * dt):
		var stop := Vector3(to.x, p.y + vy * dt, to.z)
		d.position = [stop.x, stop.y, stop.z]
		d.vel = [0.0, vy, 0.0]
		return true
	var dir := flat.normalized()
	d.yaw = lerp_angle(float(d.yaw), atan2(-dir.x, -dir.y), 1.0 - exp(-num("auto_yaw_response", 4.0) * dt))
	var s := minf(speed, maxf(0.6, flat.length() * 1.2))
	_ease_to(state, Vector3(dir.x * s, vy, dir.y * s), dt)
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


# ================================================================ ore scans and reports

## V2+ (prescout): every deposit within survey_radius_m of the point under the drone is revealed; new ones are radioed
## home as a mineral report and their spot is remembered for revisits.
static func _scan_ores(state: ColonyState, events: GameEvents) -> void:
	if not has_ability(state, "prescout"):
		return
	var p := position(state)
	var under := Vector3(p.x, ground(p.x, p.z), p.z)
	var ids: Array = []
	for v: Variant in OreCatalog.near(under, survey_radius_m(state)):
		ids.append(_dep_id(v))
	if ids.is_empty():
		return
	var fresh := _ids_of(OreCatalog.reveal(state, ids))
	if fresh.is_empty():
		return
	var d := state.drone
	var found: Array = d.get("found", [])
	for id: Variant in fresh:
		if not found.has(id):
			found.append(id)
	d.found = found
	var ores := _ores_of(fresh)
	var names := PackedStringArray()
	for o: Variant in ores:
		names.append(ore_name(String(o)))
	_remember_spot(state, under, "%s · %s" % [_spot_name(state, under), ", ".join(names)], ores)
	_report(state, "minerals", "Mineral report", String(OreCatalog.report_text(state, fresh)), fresh, fresh, events)


## V3 find: is the known deposit still there with units left?
static func _confirm_known(state: ColonyState, dep_id: String, ore_id: String, events: GameEvents) -> void:
	var units := OreCatalog.units_left(state, dep_id)
	var text := ""
	if OreCatalog.is_revealed(state, dep_id) and units > 0:
		text = "Checked: the %s is still there (%d unit%s left). %s" % [ore_words(ore_id), units, "" if units == 1 else "s",
			String(OreCatalog.report_text(state, [dep_id]))]
	else:
		text = "The %s here is used up: nothing left to mine." % ore_words(ore_id)
	_report(state, "find", "Find %s" % ore_words(ore_id), text, [dep_id], [], events)


## V4 scan: the radar pins the deposit down; it goes on the map.
static func _reveal_found(state: ColonyState, dep_id: String, ore_id: String, events: GameEvents) -> void:
	var fresh := _ids_of(OreCatalog.reveal(state, [dep_id]))
	var d := state.drone
	var found: Array = d.get("found", [])
	if not found.has(dep_id):
		found.append(dep_id)
	d.found = found
	var p := position(state)
	var under := Vector3(p.x, ground(p.x, p.z), p.z)
	_remember_spot(state, under, "%s · %s" % [_spot_name(state, under), ore_name(ore_id)], [ore_id])
	var text := "The ground radar found %s here. %s" % [ore_words(ore_id), String(OreCatalog.report_text(state, [dep_id]))]
	_report(state, "scan", "Scan for %s" % ore_words(ore_id), text, [dep_id], fresh, events)


## V2 revisit: scans the explored spot again and reports every deposit around it.
static func _rescan_spot(state: ColonyState, wp: Dictionary, events: GameEvents) -> void:
	var p := position(state)
	var under := Vector3(p.x, ground(p.x, p.z), p.z)
	var ids: Array = []
	for v: Variant in OreCatalog.near(under, survey_radius_m(state)):
		ids.append(_dep_id(v))
	var fresh: Array = []
	var text := "No ore within %d m of this spot." % roundi(survey_radius_m(state))
	if not ids.is_empty():
		fresh = _ids_of(OreCatalog.reveal(state, ids))
		text = String(OreCatalog.report_text(state, ids))
	_report(state, "revisit", String(wp.get("label", "Explored spot")), text, ids, fresh, events)


static func _report(state: ColonyState, kind: String, name: String, text: String, ids: Array, revealed: Array, events: GameEvents) -> void:
	var d := state.drone
	var sol := sol_now(state)
	d.last_report = {"kind": kind, "name": name, "text": text, "sol": sol, "at_hours": state.sim_hours,
		"ids": ids.duplicate(), "revealed": revealed.duplicate()}
	d.report_n = int(d.get("report_n", 0)) + 1
	if events != null:
		events.system_alert.emit(ALERT_REPORT, &"info", "Drone · %s: %s" % [name, text])
		if not revealed.is_empty():
			events.objective_changed.emit(&"scout_survey")


static func _ids_of(a: Variant) -> Array:
	var out: Array = []
	if a is Array:
		for v: Variant in a:
			var id := _dep_id(v)
			if id != "":
				out.append(id)
	return out


## Ore ids of deposit ids (each once).
static func _ores_of(ids: Array) -> Array:
	var want := {}
	for id: Variant in ids:
		want[String(id)] = true
	var out: Array = []
	for v: Variant in OreCatalog.deposits():
		if v is Dictionary and want.has(_dep_id(v)):
			var o := String((v as Dictionary).get("ore", ""))
			if o != "" and not out.has(o):
				out.append(o)
	return out


# ================================================================ scout-rover sites (photos)

## Every scout-rover site within survey_radius_m of the drone that it has not photographed yet is surveyed now.
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


## Surveys `site_id` the way the scout rover does: the site counts as surveyed for the colony (state.scout.surveyed,
## by "drone") and its report (data/scout_sites.json) is radioed home. From V2 (multispectral camera) the old ore
## stations within the site's reveal_radius_m are marked too. Returns the newly revealed ore station ids.
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
	if has_ability(state, "prescout"):
		for id in ScoutSystem.ore_stations(state):
			var op := _v3((state.stations[id] as Dictionary).get("position", [0, 0, 0]))
			if Vector2(op.x, op.z).distance_to(Vector2(centre.x, centre.z)) <= radius and not ScoutSystem.is_revealed(state, id):
				(s.revealed as Dictionary)[id] = true
				found.append(id)
	var sol := sol_now(state)
	var by := String(d.get("pilot", "")) if String(d.get("pilot", "")) != "" else String(d.get("sent_by", ""))
	(d.surveyed as Dictionary)[site_id] = {"sol": sol, "at_hours": state.sim_hours, "by": by}
	if not ScoutSystem.is_surveyed(state, site_id):
		(s.surveyed as Dictionary)[site_id] = {"sol": sol, "at_hours": state.sim_hours, "sent_by": by, "by": "drone"}
	var kinds := PackedStringArray()
	for id: String in found:
		var k := String(ScoutSystem.ore_info(ScoutSystem.ore_kind_of(state, id)).get("name", ScoutSystem.ore_kind_of(state, id)))
		if not kinds.has(k):
			kinds.append(k)
	var text := String(rec.get("report", ""))
	if not kinds.is_empty():
		text += " Ore marked on the map: %s." % ", ".join(kinds)
	state.discoveries.append({"kind": "drone_survey", "id": site_id, "sol": sol, "at_hours": state.sim_hours,
		"text": "Drone report from the %s: %s" % [String(rec.get("name", site_id)).to_lower(), text]})
	_report(state, "site", String(rec.get("name", site_id)), text, [site_id], found, events)
	if events != null:
		events.objective_changed.emit(&"scout_survey")
	return found


static func _v3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
