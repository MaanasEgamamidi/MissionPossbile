class_name ScoutSystem
extends RefCounted
## The robotic scout rover (scout update). A post-system of the colony simulation: it runs on the HOST only, after the
## other systems, and moves the scout along its trip in game time. Clients receive `state.scout` with the colony and
## only draw it (ScoutPresenter).
##
## What the scout is for: before the crew go anywhere, the scout drives out on its own, looks around a site with its
## mast camera and radios home a report (terrain, hazards, what the crew rover could do there). Every ore deposit near
## the site then shows on the map. It carries nothing home: the crew collect the ore themselves on foot.
##
## state.scout (plain JSON, saved and replicated):
##   built: bool                 finished at the scout bay by the field engineer (it starts half built)
##   status: "kit" | "docked" | "driving" | "surveying" | "returning"
##   position: [x, y, z]         Godot metres; y is 0 (the presenter puts the model on the ground)
##   yaw: float                  heading in radians (Godot: 0 faces -z)
##   target: site id or ""
##   leg_to: [x, y, z]           where the current leg ends
##   survey_left_h: float        game hours left looking around the site
##   surveyed: {site_id: {"sol", "at_hours", "sent_by"}}
##   revealed: {ore station id: true}
##   ores: {ore kind: count}     ore the crew have collected, in the colony store
##   ore_taken: {ore station id: count}
##   science_points: int         science ores studied at the workbench
##   studied: {ore kind: count}
##   trips: int
##   sent_by: character id of the last person who sent it
##   last_report: {"site", "name", "text", "hazard", "rover_note", "sol", "at_hours", "revealed": [ids]}

const DATA_PATH := "res://data/scout_sites.json"
## Balance (data/model_sources_scout.json): metres driven per game hour, hours spent looking around a site, parts to
## finish the kit, pieces of ore per deposit, hematite per spare part, science points before the crew rover goal.
const SPEED_M_PER_HOUR := 150.0
const SURVEY_HOURS := 0.5
const ASSEMBLE_PARTS := 2
const ORE_PER_DEPOSIT := 3
const HEMATITE_PER_PART := 2
const CREW_ROVER_SCIENCE := 3
## Close enough to call a leg finished (metres).
const ARRIVE_M := 0.25
const ALERT_ID := &"scout_report"
const LEDGER_PARTS_FROM_ORE := "parts_from_ore"
const LEDGER_PARTS_USED := "parts_used_scout"

static var _data: Dictionary = {}


# ================================================================ data

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {"sites": [], "ores": {}, "dock": {"position": [18.0, 0.0, 14.5]}}
	return _data


static func sites() -> Array:
	return data().get("sites", [])


static func site(id: String) -> Dictionary:
	for s: Dictionary in sites():
		if String(s.get("id", "")) == id:
			return s
	return {}


static func ore_info(kind: String) -> Dictionary:
	return (data().get("ores", {}) as Dictionary).get(kind, {})


static func ore_kinds() -> PackedStringArray:
	return PackedStringArray((data().get("ores", {}) as Dictionary).keys())


static func dock_position() -> Vector3:
	return _v3((data().get("dock", {}) as Dictionary).get("position", [18.0, 0.0, 14.5]))


static func dock_yaw() -> float:
	return deg_to_rad(float((data().get("dock", {}) as Dictionary).get("yaw_deg", 180.0)))


static func site_position(id: String) -> Vector3:
	return _v3(site(id).get("position", [0.0, 0.0, 0.0]))


# ================================================================ state helpers

## Fills missing scout fields with defaults (new games and older saves).
static func ensure(state: ColonyState) -> void:
	var s := state.scout
	if not s.has("built"):
		s["built"] = false
	if not s.has("status"):
		s["status"] = "docked" if bool(s.built) else "kit"
	if not s.has("position"):
		var p := dock_position()
		s["position"] = [p.x, p.y, p.z]
	if not s.has("yaw"):
		s["yaw"] = dock_yaw()
	for key: String in ["surveyed", "revealed", "ores", "ore_taken", "studied", "last_report"]:
		if not s.has(key) or not (s[key] is Dictionary):
			s[key] = {}
	for key: String in ["target", "sent_by"]:
		if not s.has(key):
			s[key] = ""
	for key: String in ["survey_left_h"]:
		if not s.has(key):
			s[key] = 0.0
	for key: String in ["science_points", "trips"]:
		if not s.has(key):
			s[key] = 0
	if not s.has("leg_to"):
		s["leg_to"] = (s.position as Array).duplicate()


static func status(state: ColonyState) -> String:
	return String(state.scout.get("status", "kit"))


static func is_built(state: ColonyState) -> bool:
	return bool(state.scout.get("built", false))


static func is_out(state: ColonyState) -> bool:
	return status(state) in ["driving", "surveying", "returning"]


static func position(state: ColonyState) -> Vector3:
	return _v3(state.scout.get("position", [dock_position().x, 0.0, dock_position().z]))


static func is_surveyed(state: ColonyState, site_id: String) -> bool:
	return (state.scout.get("surveyed", {}) as Dictionary).has(site_id)


static func is_revealed(state: ColonyState, ore_station: String) -> bool:
	return (state.scout.get("revealed", {}) as Dictionary).has(ore_station)


static func ore_count(state: ColonyState, kind: String) -> int:
	return int((state.scout.get("ores", {}) as Dictionary).get(kind, 0))


static func ore_left(state: ColonyState, ore_station: String) -> int:
	return maxi(0, ORE_PER_DEPOSIT - int((state.scout.get("ore_taken", {}) as Dictionary).get(ore_station, 0)))


static func science_points(state: ColonyState) -> int:
	return int(state.scout.get("science_points", 0))


## Ore deposit station ids, sorted.
static func ore_stations(state: ColonyState) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in state.stations:
		if String((state.stations[id] as Dictionary).get("kind", "")) == "ore_deposit":
			out.append(id)
	out.sort()
	return out


static func ore_kind_of(state: ColonyState, ore_station: String) -> String:
	var rec: Dictionary = state.stations.get(ore_station, {})
	var kind := String(rec.get("ore", ""))
	if kind == "":
		# a saved station record from before the "ore" field: the kind is in the id (ore_<kind>_<letter>)
		var parts := ore_station.split("_")
		kind = parts[1] if parts.size() >= 3 else ""
	return kind


## Game hours for the scout to drive from where it is now to `site_id` (straight line).
static func hours_to(state: ColonyState, site_id: String) -> float:
	var from := position(state)
	var to := site_position(site_id)
	return Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z)) / SPEED_M_PER_HOUR


## A short status line for HUD and panels.
static func status_text(state: ColonyState) -> String:
	var s := state.scout
	match status(state):
		"kit":
			return "Half built: the field engineer can finish it at the scout bay (%d parts)." % ASSEMBLE_PARTS
		"docked":
			return "Parked at the scout bay, ready to go."
		"driving":
			var to := String(s.get("target", ""))
			var left := _leg_hours_left(state)
			return "Driving to the %s · about %s" % [String(site(to).get("name", to)).to_lower(), _hours_words(left)]
		"surveying":
			var to2 := String(s.get("target", ""))
			return "Looking around the %s with its mast camera" % String(site(to2).get("name", to2)).to_lower()
		"returning":
			return "Driving back to the bay · about %s" % _hours_words(_leg_hours_left(state))
	return ""


static func _leg_hours_left(state: ColonyState) -> float:
	var p := position(state)
	var to := _v3(state.scout.get("leg_to", [p.x, p.y, p.z]))
	return Vector2(p.x, p.z).distance_to(Vector2(to.x, to.z)) / SPEED_M_PER_HOUR


static func _hours_words(h: float) -> String:
	if h < 0.75:
		return "under an hour"
	return "%d game hours" % roundi(h)


# ================================================================ commands (called by ScoutActions on the host)

static func send(state: ColonyState, site_id: String, actor_id: String) -> void:
	ensure(state)
	var s := state.scout
	var to := site_position(site_id)
	s.target = site_id
	s.leg_to = [to.x, 0.0, to.z]
	s.status = "driving"
	s.survey_left_h = 0.0
	s.trips = int(s.trips) + 1
	s.sent_by = actor_id
	_face(state, to)


static func recall(state: ColonyState) -> void:
	ensure(state)
	var s := state.scout
	var dock := dock_position()
	s.leg_to = [dock.x, 0.0, dock.z]
	s.status = "returning"
	s.survey_left_h = 0.0
	_face(state, dock)


# ================================================================ tick

func step(state: ColonyState, _balance: GameBalance, _phase: float, dt_hours: float, events: GameEvents) -> void:
	if state.scout.is_empty() or not state.scout.has("ores"):
		ensure(state)
	if not is_built(state) or dt_hours <= 0.0:
		return
	var s := state.scout
	match String(s.status):
		"driving", "returning":
			_drive(state, dt_hours, events)
		"surveying":
			s.survey_left_h = float(s.survey_left_h) - dt_hours
			if float(s.survey_left_h) <= 0.0:
				_finish_survey(state, events)


func _drive(state: ColonyState, dt_hours: float, events: GameEvents) -> void:
	var s := state.scout
	var p := position(state)
	var to := _v3(s.leg_to)
	var flat := Vector2(to.x - p.x, to.z - p.z)
	var step_m := SPEED_M_PER_HOUR * dt_hours
	if flat.length() <= maxf(step_m, ARRIVE_M):
		s.position = [to.x, 0.0, to.z]
		if String(s.status) == "driving":
			s.status = "surveying"
			s.survey_left_h = SURVEY_HOURS
			var site_rec := site(String(s.target))
			s.yaw = deg_to_rad(float(site_rec.get("look_yaw_deg", rad_to_deg(float(s.yaw)))))
		else:
			s.status = "docked"
			s.target = ""
			s.yaw = dock_yaw()
			if events != null:
				events.system_alert.emit(ALERT_ID, &"info", "The scout rover is back at its bay, ready for the next trip.")
		return
	var move := flat.normalized() * step_m
	s.position = [p.x + move.x, 0.0, p.z + move.y]
	_face(state, to)


func _finish_survey(state: ColonyState, events: GameEvents) -> void:
	var s := state.scout
	var site_id := String(s.target)
	var rec := site(site_id)
	var centre := site_position(site_id)
	var radius := float(rec.get("reveal_radius_m", 12.0))
	var found: Array = []
	for id in ore_stations(state):
		var p := _v3((state.stations[id] as Dictionary).get("position", [0, 0, 0]))
		if Vector2(p.x, p.z).distance_to(Vector2(centre.x, centre.z)) <= radius and not is_revealed(state, id):
			(s.revealed as Dictionary)[id] = true
			found.append(id)
	var sol := int(floor(state.sim_hours / GameConfig.SOL_HOURS)) + 1
	(s.surveyed as Dictionary)[site_id] = {"sol": sol, "at_hours": state.sim_hours, "sent_by": String(s.get("sent_by", ""))}
	var kinds := PackedStringArray()
	for id: String in found:
		var k := String(ore_info(ore_kind_of(state, id)).get("name", ore_kind_of(state, id)))
		if not kinds.has(k):
			kinds.append(k)
	var text := "Scout report from the %s: %s" % [String(rec.get("name", site_id)).to_lower(), String(rec.get("report", ""))]
	if not kinds.is_empty():
		text += " Ore marked on the map: %s." % ", ".join(kinds)
	s.last_report = {"site": site_id, "name": String(rec.get("name", site_id)), "text": String(rec.get("report", "")),
		"hazard": String(rec.get("hazard", "")), "rover_note": String(rec.get("rover_note", "")), "sol": sol,
		"at_hours": state.sim_hours, "revealed": found.duplicate()}
	state.discoveries.append({"kind": "scout_survey", "id": site_id, "sol": sol, "at_hours": state.sim_hours, "text": text})
	recall(state)
	if events != null:
		events.system_alert.emit(ALERT_ID, &"info", text)
		events.objective_changed.emit(&"scout_survey")


static func _face(state: ColonyState, to: Vector3) -> void:
	var p := position(state)
	var d := Vector2(to.x - p.x, to.z - p.z)
	if d.length() > 1e-4:
		# Godot yaw: a node looking along -z has yaw 0; atan2(-dx, -dz) turns that into the travel direction.
		state.scout.yaw = atan2(-d.x, -d.y)


static func _v3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
