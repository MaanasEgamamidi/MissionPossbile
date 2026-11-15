extends RefCounted
## The strict day's station gate (owner 2026-11-15; docs/revisions/UPGRADE_PATHS_PLAN.md §1.7): once the tutorial is
## done (TutorialSystem.is_tutorial_done), a station action that belongs to a block works only during that block, with
## a plain message otherwise ("It's Free time: the lab is closed until the Work block at 08:00."). Same shape as
## scripts/session/tutorial_lock.gd: refusal(ctx) on the host (ActionService, right after TutorialLock), and
## station_usable() for the HUD's "[E]" prompt. Loaded by path (no class_name):
##     const ScheduleGate := preload("res://scripts/schedule/schedule_gate.gd")
##
## Conservative: ONLY the actions in ACTION_BLOCKS are ever gated; anything not listed always works. Never gated:
##   - repairs and maintenance (task_*, maintenance_*), suits (begin_suit_check, refill_suit), doors (not stations),
##     crew swap (claim/release_character, not stations), medical care (the heal station is passive), the cassette
##     player and tapes, old records, the comms / colony computer, power and life-support settings, panel cleaning,
##     upgrades and the build vote (the build helper's own rules), release / cancel / land / recall actions;
##   - everything while an emergency is on (ScheduleSystem.emergency: urgent alert, dust storm, radiation storm,
##     COLONY OVER countdown) or while the acting crewmate is in danger (exposure / hazard).

const CrewDay := preload("res://scripts/schedule/crew_day.gd")
const ScheduleSystem := preload("res://scripts/schedule/schedule_system.gd")

const REASON := &"schedule_closed"

## THE TABLE. Action id -> [blocks it works in, the place words for the message]. Not listed = always works.
## Block ids are CrewDay.BLOCKS ids ("sleep" also covers "sleep_evening").
const ACTION_BLOCKS := {
	# lab glovebox (Science)
	"analyze_sample": [["work"], "lab"],
	"interpret_sample": [["work"], "lab"],
	"apply_result": [["work"], "lab"],
	# sample sites and ore deposits outside (Work for the geologist, and the evening Field mission)
	"take_sample": [["work", "field"], "sample site"],
	"collect_ore": [["work", "field"], "ore deposit"],
	# workbench and salvage donors (Work, and Base chores: logging, tidying, care of the kit)
	"process_ore": [["work", "chores"], "workbench"],
	"refurbish": [["work", "chores"], "workbench"],
	"bench_test": [["work", "chores"], "workbench"],
	"inspect_donor": [["work", "chores", "field"], "salvage donor"],
	"recover_part": [["work", "chores", "field"], "salvage donor"],
	# greenhouse beds (Work for the biologist, and Base chores). The grow lights and greenhouse water stay open.
	"plant": [["work", "chores"], "greenhouse"],
	"inspect_bed": [["work", "chores"], "greenhouse"],
	"adjust_nutrients": [["work", "chores"], "greenhouse"],
	"set_bed_water": [["work", "chores"], "greenhouse"],
	"harvest": [["work", "chores"], "greenhouse"],
	"apply_nutrient_result": [["work", "chores"], "greenhouse"],
	# the exercise corner
	"exercise": [["exercise"], "exercise corner"],
	# vehicles: building and refitting (Work, Base chores: rover care), trips (Work, Field mission)
	"scout_assemble": [["work", "chores"], "scout bay"],
	"scout_send": [["work", "field", "chores"], "scout rover"],
	"rover_assemble": [["work", "chores"], "rover garage"],
	"rover_refit": [["work", "chores"], "rover garage"],
	"drone_fly": [["work", "field"], "drone pad"],
	"drone_send": [["work", "field"], "drone autopilot"],
}

## Station kind -> blocks, for the HUD prompt (station_usable). A kind is listed only when EVERY action at it is gated
## the same way; mixed stations (the greenhouse console, the colony computer, the garage charger) stay open.
const KIND_BLOCKS := {
	"lab": ["work"],
	"sample_site": ["work", "field"],
	"ore_deposit": ["work", "field"],
	"workbench": ["work", "chores"],
	"salvage": ["work", "chores", "field"],
	"bed": ["work", "chores"],
	"gym": ["exercise"],
	"scout_bay": ["work", "chores", "field"],
	"drone_pad": ["work", "field"],
}
const KIND_PLACE := {
	"lab": "lab", "sample_site": "sample site", "ore_deposit": "ore deposit", "workbench": "workbench",
	"salvage": "salvage donor", "bed": "greenhouse", "gym": "exercise corner", "scout_bay": "scout bay",
	"drone_pad": "drone pad",
}

## "It's ___" for each block, and how a later block is named ("until ___ at 08:00").
const NOW_WORDS := {
	"sleep": "sleep time", "sleep_evening": "sleep time", "wake": "wake-up time", "meal": "Meal time",
	"systems": "the Systems round", "work": "the Work block", "exercise": "Exercise time", "chores": "Base chores time",
	"field": "the Field mission", "plan": "the Plan block", "free": "Free time",
}
const NEXT_WORDS := {
	"meal": "the Meal", "systems": "the Systems round", "work": "the Work block", "exercise": "Exercise",
	"chores": "Base chores", "field": "the Field mission", "plan": "the Plan block", "free": "Free time",
	"wake": "wake-up", "sleep": "sleep time",
}


## True while the gate can refuse anything: the tutorial is done and no emergency is on.
static func active(state: ColonyState) -> bool:
	return ScheduleSystem.day_on(state) and not ScheduleSystem.emergency(state)


## True when the current block is one of `blocks`.
static func block_open(state: ColonyState, blocks: Array) -> bool:
	for id: Variant in blocks:
		if CrewDay.is_block(state, String(id)):
			return true
	return false


## True when E may use the station `record` (a state.stations entry) now, for the HUD prompt.
static func station_usable(state: ColonyState, record: Dictionary, actor: CharacterState) -> bool:
	if record.is_empty() or not active(state) or ScheduleSystem.actor_in_danger(actor):
		return true
	var kind := String(record.get("kind", ""))
	if not KIND_BLOCKS.has(kind):
		return true
	return block_open(state, KIND_BLOCKS[kind])


## The plain message for a station whose block is not now (HUD / panel use).
static func message_for_station(state: ColonyState, record: Dictionary) -> String:
	var kind := String(record.get("kind", ""))
	return closed_message(state, KIND_BLOCKS.get(kind, []), String(KIND_PLACE.get(kind, "station")))


## "It's Free time: the lab is closed until the Work block at 08:00."
static func closed_message(state: ColonyState, blocks: Array, place: String) -> String:
	var now := String(CrewDay.current_block(state).get("id", ""))
	var best_id := ""
	var best_h := INF
	for id: Variant in blocks:
		var h := CrewDay.hours_until(state, String(id))
		if h < best_h:
			best_h = h
			best_id = String(id)
	var line := "It's %s: the %s is closed" % [String(NOW_WORDS.get(now, "not time yet")), place]
	if best_id == "":
		return line + "."
	var start := ScheduleSystem.block_bounds(best_id).x
	return "%s until %s at %s." % [line, String(NEXT_WORDS.get(best_id, best_id)), clock_words(start)]


## "08:00" for an hour of the sol.
static func clock_words(hour: float) -> String:
	var minutes := roundi(hour * 60.0)
	return "%02d:%02d" % [floori(minutes / 60.0), minutes % 60]


## Host: the refusal for a resolved request (an ActionService.Context), or null when the day lets it through.
static func refusal(ctx: RefCounted) -> ActionResult:
	var state: ColonyState = ctx.get(&"state")
	if not active(state):
		return null
	var d: RefCounted = ctx.get(&"definition")
	var request: ActionRequest = ctx.get(&"request")
	if d == null or request == null or StringName(d.get(&"target_kind")) != &"station":
		return null
	var rule: Variant = ACTION_BLOCKS.get(String(request.action), null)
	if not (rule is Array):
		return null
	var actor: CharacterState = ctx.get(&"actor")
	if ScheduleSystem.actor_in_danger(actor):
		return null
	var blocks: Array = (rule as Array)[0]
	if block_open(state, blocks):
		return null
	return ActionResult.failure(request.request_id, REASON, closed_message(state, blocks, String((rule as Array)[1])))
