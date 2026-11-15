extends RefCounted
## The crew's strict day, enforced (owner 2026-11-15: "NASA crews follow a fixed timeline"; plan
## docs/revisions/UPGRADE_PATHS_PLAN.md §1.7 and Appendix A). The block table itself is the shared lookup
## scripts/schedule/crew_day.gd; this file decides WHERE each block wants a crewmate, records who was there, and gives
## the modest costs and rewards. HOST ONLY: step() changes state; everything else is a pure read any machine may call
## (the HUD chip, the station gate, the H-key sparkle line). Loaded by path (no class_name):
##     const ScheduleSystem := preload("res://scripts/schedule/schedule_system.gd")
##
## The crew day only counts once the tutorial is done (TutorialSystem.is_tutorial_done): before that the block is
## tracked, but nobody is late, nothing is missed and the station gate is open.
##
## Where each block wants a crewmate (zone names are ColonyZones names: data/colony_manifest.json rooms, plus
## "Garden dome" and "Exterior"):
##   Sleep, Wake up, Base chores, Plan, Free time   anywhere (Plan: the build helper's vote; this file only shows it)
##   Meal (07:00)            Mess hall
##   Systems round (07:30)   Power Room, Life Support (air and water) or outside (the solar panels)
##   Work block (08:00)      by role: Biologist (biology_food) Greenhouse or Garden dome; Field engineer
##                           (field_engineering_geology) outside; Electrical engineer (electrical_comms) Power Room,
##                           Command Room (comms), or at any repair (holding a repair / maintenance job, or standing
##                           at a broken spot); Medic (medical_life_support) Med Bay
##   Exercise (12:30)        Rec kitchen: the exercise corner (treadmill, station kind "gym") is there
##   Field mission (18:00)   outside; OPTIONAL: never late, never missed
## Crewmates no player controls (owner_peer 0, parked) count as attending every block automatically: no lateness, no
## costs, and no science either (science comes from players' work).
##
## Effects (tunable constants below):
##   Meal attended        body energy (stamina) back to 100 %; a missed meal makes the crewmate "hungry" until the
##                        next meal: body energy drains HUNGRY_DRAIN_PER_HOUR and is held at most HUNGRY_STAMINA_CAP.
##   Work attended        science points by role (WORK_SCIENCE), added to ScoutSystem's score
##                        (state.scout.science_points, the number the vitals bar shows), once per work block.
##   Exercise missed      health -EXERCISE_MISSED_HEALTH (never below 1) and "bones and muscles get weaker without
##                        exercise".
##   Systems / Work missed  recorded in "missed" and said once; a missed work block simply gives no science.
##   Weekly vitals        every VITALS_EVERY_SOLS sols each crewmate visits the Med Bay during a morning block (Wake
##                        up, Meal, Systems round, Work block). Due at wake-up: a reminder; still not done when the
##                        morning ends: a medic warning.
##   Lateness             a required block (meal, systems, work, exercise) has run LATE_AFTER_HOURS (at most half the
##                        block) and a player's crewmate is not where it wants them: Mission Control says once
##                        "Sam, you are late for Exercise (Rec kitchen)."
## Excused (never late, never missed): during an emergency (emergency(): an urgent alert, a dust storm warned or
## running, a radiation storm, the COLONY OVER countdown; a block that had one is not graded at all), a crewmate in
## radiation isolation, and the block that was running when the game started or when the tutorial ended.
##
## ColonyState.schedule (plain JSON, saved and replicated; owned here):
##   "sol": int                     sol of the block below
##   "block": String                current block id (CrewDay.BLOCKS ids)
##   "block_key": String            "<sol>:<block id>", one per block per sol
##   "graded": bool                 this block is graded when it ends (it began while the crew day counted)
##   "emergency": bool              an emergency was on at some point during this block (the block is not graded)
##   "attended": {actor_id: {block_id: true}}   today (cleared when a new sol begins)
##   "missed": {actor_id: [block ids]}          today (cleared when a new sol begins)
##   "late_said": {actor_id: block_key}         the block whose "you are late" was said
##   "science_given": {actor_id: block_key}     the work block that already paid science
##   "hungry": {actor_id: true}                 missed the last meal
##   "vitals_week": {actor_id: last sol}        the sol of the last weekly vitals check (first seen = that sol)
##   "vitals_said": {actor_id: "<kind>:<sol>"}  the last vitals reminder / warning said ("remind" or "warn")
## Alerts: GameEvents.system_alert with ids starting ALERT_PREFIX ("schedule_late", "schedule_missed",
## "schedule_vitals", "schedule_meal", "schedule_work").

const CrewDay := preload("res://scripts/schedule/crew_day.gd")
const MANIFEST_PATH := "res://data/colony_manifest.json"

const ALERT_PREFIX := "schedule_"

# ---------------------------------------------------------------- tuning (keep modest)
## Game hours after a block starts before a crewmate counts as late (at most half the block).
const LATE_AFTER_HOURS := 1.0
## Body energy lost per game hour while hungry (missed the last meal), and the most it can be until the next meal.
const HUNGRY_DRAIN_PER_HOUR := 3.0
const HUNGRY_STAMINA_CAP := 70.0
## Health a missed exercise block costs.
const EXERCISE_MISSED_HEALTH := 5.0
## Science points one attended work block gives, by specialty.
const WORK_SCIENCE := {
	"biology_food": 2, "field_engineering_geology": 3, "electrical_comms": 2, "medical_life_support": 2,
}
## Sols between weekly vitals checks.
const VITALS_EVERY_SOLS := 7
## Morning blocks, when the weekly vitals check can be done.
const MORNING_BLOCKS: PackedStringArray = ["wake", "meal", "systems", "work"]
## Blocks that cost something when missed (the others are anywhere, automatic or optional).
const GRADED_BLOCKS: PackedStringArray = ["meal", "systems", "work", "exercise"]
## Blocks that are optional: never late, never missed.
const OPTIONAL_BLOCKS: PackedStringArray = ["field"]
## Alert levels in state.alerts that count as an emergency (add "warn" to make the day looser).
const EMERGENCY_LEVELS: PackedStringArray = ["urgent"]
## Standing this close (metres, plan distance) to a broken repair spot counts as "at a repair".
const REPAIR_NEAR_M := 4.0

# ---------------------------------------------------------------- where
## Zones a block wants (blocks not listed: anywhere). "work" goes by role (ROLE_ZONES).
const BLOCK_ZONES := {
	"meal": ["Mess hall"],
	"systems": ["Power Room", "Life Support", "Exterior"],
	"exercise": ["Rec kitchen"],
	"field": ["Exterior"],
}
## Work block zones by specialty.
const ROLE_ZONES := {
	"biology_food": ["Greenhouse", "Garden dome"],
	"field_engineering_geology": ["Exterior"],
	"electrical_comms": ["Power Room", "Command Room"],
	"medical_life_support": ["Med Bay"],
}
## Short place words for the HUD and Mission Control.
const BLOCK_PLACE := {"meal": "Mess hall", "systems": "Power Room", "exercise": "Rec kitchen", "field": "outside"}
const ROLE_PLACE := {
	"biology_food": "Greenhouse", "field_engineering_geology": "outside", "electrical_comms": "Power Room",
	"medical_life_support": "Med Bay",
}
## Station kinds whose spot is the target of the sparkle line (nearest one wins); a zone centre otherwise.
const BLOCK_SPOT_KINDS := {"systems": ["power", "lifesupport"], "exercise": ["gym"]}
const ROLE_SPOT_KINDS := {
	"biology_food": ["food"], "field_engineering_geology": ["sample_site", "ore_deposit"], "electrical_comms": ["power"],
	"medical_life_support": ["heal"],
}
const MED_BAY := "Med Bay"
const EXTERIOR := "Exterior"
## Godot positions used when the map has no better spot: just outside the airlock's outer door, the garden dome.
const OUTSIDE_SPOT := Vector3(22.0, 0.0, 16.5)
const GARDEN_SPOT := Vector3(50.0, 0.0, 27.0)

static var _zones: ColonyZones = null
static var _zones_tried := false


# ================================================================ host step

## Host: advance the crew day by `delta_hours` game hours (call once per simulation tick, after the colony sim).
static func step(session: SessionService, delta_hours: float) -> void:
	if session == null or session.state == null or not session.authoritative:
		return
	var state := session.state
	var sch := state.schedule
	var block := CrewDay.current_block(state)
	if block.is_empty():
		return
	var sol := CrewDay.sol_of(state)
	var id := String(block.id)
	var key := "%d:%s" % [sol, id]
	var on := day_on(state)
	if String(sch.get("block_key", "")) != key:
		var first := not sch.has("block_key")
		if not first:
			_end_block(session, String(sch.get("block", "")))
		if int(sch.get("sol", 0)) != sol:
			sch["attended"] = {}
			sch["missed"] = {}
		sch["sol"] = sol
		sch["block"] = id
		sch["block_key"] = key
		sch["graded"] = on and not first
		sch["emergency"] = false
		if not first and on:
			_start_block(session, id, sol)
	if not on:
		sch["graded"] = false
		return
	var urgent := emergency(state)
	if urgent:
		sch["emergency"] = true
	var elapsed := hours_into_block(state)
	for cid: Variant in state.characters:
		var c: CharacterState = state.characters[cid]
		if c == null:
			continue
		var aid := String(c.id)
		var vitals: Dictionary = _sub(sch, "vitals_week")
		if not vitals.has(aid):
			vitals[aid] = sol
		if not c.is_active():
			_mark(sch, aid, id)
			if MORNING_BLOCKS.has(id):
				vitals[aid] = sol
			continue
		var here := zone_of(session, c.position)
		if MORNING_BLOCKS.has(id) and here == MED_BAY:
			vitals[aid] = sol
		if is_at_place(state, c, id, here, session):
			if not attended(state, aid, id):
				_mark(sch, aid, id)
				_arrived(session, c, id, key)
		elif not urgent and _needs_place(state, c, id) and c.isolation.is_empty() \
				and elapsed >= late_after(id) and String(_sub(sch, "late_said").get(aid, "")) != key:
			var late_said := _sub(sch, "late_said")
			late_said[aid] = key
			_say(session, &"schedule_late", &"warn", "%s, you are late for %s (%s)." % [name_of(c), String(block.name), place_words(state, c, id)])
	_hunger(state, delta_hours)


## The block that just ended: who missed it, and what that costs.
static func _end_block(session: SessionService, id: String) -> void:
	var state := session.state
	var sch := state.schedule
	if not bool(sch.get("graded", false)) or bool(sch.get("emergency", false)) or not GRADED_BLOCKS.has(id):
		return
	for cid: Variant in state.characters:
		var c: CharacterState = state.characters[cid]
		if c == null or not c.is_active() or not c.isolation.is_empty():
			continue
		var aid := String(c.id)
		if attended(state, aid, id) or not _needs_place(state, c, id):
			continue
		var missed: Dictionary = _sub(sch, "missed")
		if not (missed.get(aid, null) is Array):
			missed[aid] = []
		(missed[aid] as Array).append(id)
		var who := name_of(c)
		match id:
			"meal":
				var hungry := _sub(sch, "hungry")
				hungry[aid] = true
				_say(session, &"schedule_missed", &"warn", "%s missed the Meal. Body energy drops faster until the next meal." % who)
			"work":
				_say(session, &"schedule_missed", &"warn", "%s missed the Work block: no science from it today." % who)
			"exercise":
				if c.health > 1.0:
					c.health = maxf(1.0, c.health - EXERCISE_MISSED_HEALTH)
				_say(session, &"schedule_missed", &"warn", "%s missed Exercise: bones and muscles get weaker without exercise (health -%d)." % [who, roundi(EXERCISE_MISSED_HEALTH)])
			"systems":
				_say(session, &"schedule_missed", &"info", "%s missed the Systems round. Checking the machines every morning catches faults early." % who)


## A new block began (the crew day counts): the weekly vitals reminder and warning.
static func _start_block(session: SessionService, id: String, sol: int) -> void:
	var state := session.state
	var sch := state.schedule
	if id != "wake" and id != "exercise":
		return
	for cid: Variant in state.characters:
		var c: CharacterState = state.characters[cid]
		if c == null or not c.is_active():
			continue
		if not vitals_due(state, c):
			continue
		var aid := String(c.id)
		var said: Dictionary = _sub(sch, "vitals_said")
		if id == "wake" and String(said.get(aid, "")) != "remind:%d" % sol:
			said[aid] = "remind:%d" % sol
			_say(session, &"schedule_vitals", &"info", "%s, your weekly vitals check is due: visit the Med Bay this morning (before 12:30)." % name_of(c))
		elif id == "exercise" and String(said.get(aid, "")) != "warn:%d" % sol:
			said[aid] = "warn:%d" % sol
			_say(session, &"schedule_vitals", &"warn", "Medic: %s skipped the weekly vitals check. Without it we can't spot bone, heart or blood-pressure changes early. Visit the Med Bay tomorrow morning." % name_of(c))


## A player's crewmate reached the place of the block.
static func _arrived(session: SessionService, c: CharacterState, id: String, key: String) -> void:
	var sch := session.state.schedule
	var aid := String(c.id)
	match id:
		"meal":
			c.stamina = 100.0
			_sub(sch, "hungry").erase(aid)
		"work":
			if String(_sub(sch, "science_given").get(aid, "")) == key:
				return
			var points := int(WORK_SCIENCE.get(String(c.specialty), 0))
			if points <= 0:
				return
			var given := _sub(sch, "science_given")
			given[aid] = key
			add_science(session.state, points)
			_say(session, &"schedule_work", &"good", "%s is at work in the %s: +%d science." % [name_of(c), place_words(session.state, c, id), points])


## Hungry crewmates (missed the last meal) lose body energy a little faster.
static func _hunger(state: ColonyState, delta_hours: float) -> void:
	var hungry: Dictionary = _sub(state.schedule, "hungry")
	for aid: Variant in hungry.keys():
		var c := state.character(StringName(String(aid)))
		if c == null:
			hungry.erase(aid)
			continue
		if not c.is_active():
			continue
		c.stamina = minf(HUNGRY_STAMINA_CAP, maxf(0.0, c.stamina - HUNGRY_DRAIN_PER_HOUR * maxf(0.0, delta_hours)))


## Adds to the colony's science score (ScoutSystem.science_points reads state.scout.science_points; there is no adder
## function, scout_actions.gd writes the key the same way).
static func add_science(state: ColonyState, points: int) -> void:
	state.scout["science_points"] = ScoutSystem.science_points(state) + points


# ================================================================ reads (any machine)

## True once the crew day counts: the tutorial is done.
static func day_on(state: ColonyState) -> bool:
	return state != null and TutorialSystem.is_tutorial_done(state)


## True while something urgent is going on, so every station opens and nobody is late.
static func emergency(state: ColonyState) -> bool:
	if state == null:
		return false
	for a: Variant in state.alerts:
		if a is Dictionary and EMERGENCY_LEVELS.has(String((a as Dictionary).get("level", ""))):
			return true
	if String(state.weather.get("phase", "calm")) != "calm":
		return true
	if bool(state.radiation.get("active", false)) or bool(state.radiation.get("storm", false)) \
			or String(state.radiation.get("phase", "calm")) not in ["", "calm"]:
		return true
	if bool(state.colony_over.get("active", false)) or bool(state.colony_over.get("counting", false)):
		return true
	return false


## True when this crewmate is in danger themself (exposure or a hazard), so their actions are never gated.
static func actor_in_danger(actor: CharacterState) -> bool:
	return actor != null and (actor.exposure_active or actor.hazard_cause != "" or actor.lethal_exposure_seconds > 0.0)


## Has `actor_id` attended block `id` today?
static func attended(state: ColonyState, actor_id: String, id: String) -> bool:
	var a: Variant = (state.schedule.get("attended", {}) as Dictionary).get(actor_id, null)
	return a is Dictionary and bool((a as Dictionary).get(id, false))


## Blocks `actor_id` missed today.
static func missed_today(state: ColonyState, actor_id: String) -> Array:
	var m: Variant = (state.schedule.get("missed", {}) as Dictionary).get(actor_id, null)
	return (m as Array).duplicate() if m is Array else []


static func is_hungry(state: ColonyState, actor_id: String) -> bool:
	return bool((state.schedule.get("hungry", {}) as Dictionary).get(actor_id, false))


## True when the weekly vitals check is due for this crewmate.
static func vitals_due(state: ColonyState, actor: CharacterState) -> bool:
	if state == null or actor == null:
		return false
	var last := int((state.schedule.get("vitals_week", {}) as Dictionary).get(String(actor.id), CrewDay.sol_of(state)))
	return CrewDay.sol_of(state) - last >= VITALS_EVERY_SOLS


## Start and end hour of block `id` (end = the next block's start, or the end of the sol).
static func block_bounds(id: String) -> Vector2:
	var blocks := CrewDay.BLOCKS
	for i in blocks.size():
		if String(blocks[i].id) == id:
			var end := GameConfig.SOL_HOURS if i + 1 >= blocks.size() else float(blocks[i + 1].start)
			return Vector2(float(blocks[i].start), end)
	return Vector2(0.0, GameConfig.SOL_HOURS)


## Game hours since the current block began.
static func hours_into_block(state: ColonyState) -> float:
	var b := CrewDay.current_block(state)
	if b.is_empty():
		return 0.0
	return maxf(0.0, CrewDay.hour_of(state) - float(b.start))


## Hours a required block runs before its crew are late.
static func late_after(id: String) -> float:
	var span := block_bounds(id)
	return minf(LATE_AFTER_HOURS, 0.5 * (span.y - span.x))


## The block after the current one ({} without a state); the evening sleep and the night sleep count as one.
static func next_block(state: ColonyState) -> Dictionary:
	var b := CrewDay.current_block(state)
	if b.is_empty():
		return {}
	var blocks := CrewDay.BLOCKS
	var id := String(b.id)
	if id == "sleep" or id == "sleep_evening":
		return blocks[1]
	for i in blocks.size():
		if String(blocks[i].id) == id:
			return blocks[(i + 1) % blocks.size()]
	return {}


## Zones block `id` wants of this crewmate ([] = anywhere).
static func wanted_zones(actor: CharacterState, id: String) -> Array:
	if id == "work":
		return ROLE_ZONES.get(String(actor.specialty), []) if actor != null else []
	return BLOCK_ZONES.get(id, [])


## True when block `id` asks this crewmate to be somewhere (and is not optional).
static func _needs_place(_state: ColonyState, actor: CharacterState, id: String) -> bool:
	return GRADED_BLOCKS.has(id) and not OPTIONAL_BLOCKS.has(id) and not wanted_zones(actor, id).is_empty()


## True when the crewmate is where block `id` wants them. `here` = their zone ("" = look it up). `session` (host
## only, may be null) adds the repair / maintenance jobs the electrical engineer holds.
static func is_at_place(state: ColonyState, actor: CharacterState, id: String, here := "", session: SessionService = null) -> bool:
	var want := wanted_zones(actor, id)
	if want.is_empty():
		return true
	if here == "":
		here = zone_of(session, actor.position)
	if want.has(here):
		return true
	if id == "work" and String(actor.specialty) == "electrical_comms":
		return _at_repair(state, actor, session)
	return false


## The electrical engineer's "or any repair": holding a repair or maintenance job, or standing at a broken spot.
static func _at_repair(state: ColonyState, actor: CharacterState, session: SessionService) -> bool:
	if session != null:
		for task_id: Variant in session.repair_runtime.locks:
			if String((session.repair_runtime.locks[task_id] as Dictionary).get("actor", "")) == String(actor.id):
				return true
		for task_id: Variant in session.wear_runtime.jobs:
			if String((session.wear_runtime.jobs[task_id] as Dictionary).get("actor", "")) == String(actor.id):
				return true
	var me := Vector2(actor.position.x, actor.position.z)
	for sid: Variant in state.stations:
		var rec: Dictionary = state.stations[sid]
		if String(rec.get("kind", "")) != "repair_task":
			continue
		if not PuzzleRegistry.is_broken(state, String(rec.get("task_id", ""))):
			continue
		var p := CharacterState._v3(rec.get("position", [0, 0, 0]))
		if Vector2(p.x, p.z).distance_to(me) <= REPAIR_NEAR_M:
			return true
	return false


## True when a player's crewmate is late for the current block now (the HUD's "Late!").
static func is_late(state: ColonyState, actor: CharacterState) -> bool:
	if not day_on(state) or actor == null or not actor.is_active() or not actor.isolation.is_empty():
		return false
	var b := CrewDay.current_block(state)
	var id := String(b.get("id", ""))
	if not _needs_place(state, actor, id) or emergency(state):
		return false
	if hours_into_block(state) < late_after(id):
		return false
	return not attended(state, String(actor.id), id) and not is_at_place(state, actor, id)


## Place words for block `id` and this crewmate ("Mess hall", "Greenhouse", "outside"; "" = anywhere).
static func place_words(_state: ColonyState, actor: CharacterState, id: String) -> String:
	if id == "work":
		return String(ROLE_PLACE.get(String(actor.specialty), "")) if actor != null else ""
	return String(BLOCK_PLACE.get(id, ""))


## Where the H-key sparkle line should lead for the current block: the role spot (a station of the right kind,
## nearest first) or the room's centre; Vector3.INF when anywhere is fine, the crewmate is already there, or the crew
## day does not count yet.
static func where_to_be(state: ColonyState, actor: CharacterState) -> Vector3:
	if not day_on(state) or actor == null:
		return Vector3.INF
	var b := CrewDay.current_block(state)
	var id := String(b.get("id", ""))
	var want := wanted_zones(actor, id)
	if want.is_empty() or OPTIONAL_BLOCKS.has(id) or is_at_place(state, actor, id):
		return Vector3.INF
	var kinds: Array = ROLE_SPOT_KINDS.get(String(actor.specialty), []) if id == "work" else BLOCK_SPOT_KINDS.get(id, [])
	var best := Vector3.INF
	var best_d := INF
	for sid: Variant in state.stations:
		var rec: Dictionary = state.stations[sid]
		if not kinds.has(String(rec.get("kind", ""))):
			continue
		var p := CharacterState._v3(rec.get("position", [0, 0, 0]))
		var d := Vector2(p.x, p.z).distance_to(Vector2(actor.position.x, actor.position.z))
		if d < best_d:
			best_d = d
			best = p
	if best != Vector3.INF:
		return best
	return zone_spot(String(want[0]))


## A point in a zone, Godot coordinates: the room rectangle's centre on the floor, or a fixed outdoor spot.
static func zone_spot(zone: String) -> Vector3:
	if zone == EXTERIOR:
		return OUTSIDE_SPOT
	if zone == ColonyZones.GARDEN:
		return GARDEN_SPOT
	var z := zones()
	if z != null:
		for r: Variant in z.rooms:
			var room: Dictionary = r
			if String(room.get("name", "")) == zone:
				var cx := (float(room.x0) + float(room.x1)) * 0.5
				var cy := (float(room.y0) + float(room.y1)) * 0.5
				return Vector3(cx, 0.0, -cy)          # Blender (x, y) -> Godot (x, -y)
	return Vector3.INF


## The crewmate's name for messages.
static func name_of(c: CharacterState) -> String:
	return c.display_name if c.display_name != "" else String(c.id)


# ================================================================ zones

## Lets the game hand over its already-loaded zones (GameServices.zones), so the manifest is not parsed twice.
static func use_zones(z: ColonyZones) -> void:
	if z != null:
		_zones = z
		_zones_tried = true


## The colony's zones (loaded from the manifest once when nobody handed them over).
static func zones() -> ColonyZones:
	if not _zones_tried:
		_zones_tried = true
		if FileAccess.file_exists(MANIFEST_PATH):
			_zones = ColonyZones.from_manifest(MANIFEST_PATH)
	return _zones


## Zone name at a Godot position: the host's own lookup when there is one, else the manifest zones.
static func zone_of(session: SessionService, p: Vector3) -> String:
	if session != null and session.zone_at_position.is_valid():
		return String(session.zone_at_position.call(p))
	var z := zones()
	return z.zone_at_world(p) if z != null else ""


# ================================================================ helpers

static func _sub(sch: Dictionary, key: String) -> Dictionary:
	if not (sch.get(key, null) is Dictionary):
		sch[key] = {}
	return sch[key]


static func _mark(sch: Dictionary, actor_id: String, id: String) -> void:
	var att := _sub(sch, "attended")
	if not (att.get(actor_id, null) is Dictionary):
		att[actor_id] = {}
	(att[actor_id] as Dictionary)[id] = true


static func _say(session: SessionService, alert_id: StringName, level: StringName, text: String) -> void:
	if session.events != null:
		session.events.system_alert.emit(alert_id, level, "Mission Control: " + text)
