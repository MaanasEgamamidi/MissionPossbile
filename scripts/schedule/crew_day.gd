extends RefCounted
## The crew's strict day (owner, 2026-11-15; docs/revisions/UPGRADE_PATHS_PLAN.md §1.7). NASA crews follow a fixed
## timeline, so the game does too: one sol is split into blocks, and during a block only that block's activities are
## open (plus emergencies). This file is the SHARED, pure lookup every system uses (build-a-day, radiation, comms, the
## HUD); the schedule system that enforces blocks, attendance and lateness builds on it in scripts/schedule/.
## Times are hours of the sol on the HUD clock (0 .. GameConfig.SOL_HOURS, the same hour GameHud shows), read from the
## replicated state, so every machine agrees. Loaded by path (no class_name):
##     const CrewDay := preload("res://scripts/schedule/crew_day.gd")
##
## state.schedule (owned by the schedule system, plain JSON): see scripts/schedule/schedule_system.gd.

## Blocks in order. "start" is the hour the block begins; it lasts until the next block's start (the last one wraps
## to the first). "where": the area the crew should be in (room id / "outside" / "anywhere"); "kind": what it gates.
const BLOCKS: Array[Dictionary] = [
	{"id": "sleep", "start": 0.0, "name": "Sleep", "where": "anywhere", "kind": "rest"},
	{"id": "wake", "start": 6.5, "name": "Wake up", "where": "anywhere", "kind": "auto"},
	{"id": "meal", "start": 7.0, "name": "Meal", "where": "mess_hall", "kind": "meal"},
	{"id": "systems", "start": 7.5, "name": "Systems round", "where": "anywhere", "kind": "systems"},
	{"id": "work", "start": 8.0, "name": "Work block", "where": "role", "kind": "work"},
	{"id": "exercise", "start": 12.5, "name": "Exercise", "where": "anywhere", "kind": "exercise"},
	{"id": "chores", "start": 14.5, "name": "Base chores", "where": "anywhere", "kind": "chores"},
	{"id": "field", "start": 18.0, "name": "Field mission", "where": "outside", "kind": "field"},
	{"id": "plan", "start": 20.0, "name": "Plan", "where": "anywhere", "kind": "plan"},
	{"id": "free", "start": 21.0, "name": "Free time", "where": "anywhere", "kind": "rest"},
	{"id": "sleep_evening", "start": 22.5, "name": "Sleep", "where": "anywhere", "kind": "rest"},
]


## state.sim_hours starts at 0 when a colony begins, but the HUD clock (SolClock) starts at GameConfig.start_phase
## (0.3 of a sol, about 07:24). This offset lines the two up, so a block starts exactly when the HUD clock shows it.
static var _start_offset_hours := -1.0


static func start_offset_hours() -> float:
	if _start_offset_hours < 0.0:
		_start_offset_hours = 0.0
		var config := load("res://config/game_config.tres") as GameConfig
		if config != null:
			_start_offset_hours = config.start_phase * GameConfig.SOL_HOURS
	return _start_offset_hours


## Hours since the first midnight (sim time plus the start offset).
static func clock_hours(state: ColonyState) -> float:
	if state == null:
		return 0.0
	return maxf(state.sim_hours, 0.0) + start_offset_hours()


## Hour of the sol (0 .. SOL_HOURS) on the HUD clock.
static func hour_of(state: ColonyState) -> float:
	if state == null:
		return 0.0
	return fmod(clock_hours(state), GameConfig.SOL_HOURS)


## The sol number (1 = the first sol), as the HUD clock counts it.
static func sol_of(state: ColonyState) -> int:
	if state == null:
		return 1
	return int(floor(clock_hours(state) / GameConfig.SOL_HOURS)) + 1


## The block at an hour of the sol.
static func block_at_hour(hour: float) -> Dictionary:
	var found: Dictionary = BLOCKS[0]
	for b: Dictionary in BLOCKS:
		if hour >= float(b.start):
			found = b
	return found


## The block the colony is in now ({} without a state).
static func current_block(state: ColonyState) -> Dictionary:
	if state == null:
		return {}
	return block_at_hour(hour_of(state))


## True when the current block's id is `id` ("sleep_evening" counts as "sleep").
static func is_block(state: ColonyState, id: String) -> bool:
	var b := current_block(state)
	var cur := String(b.get("id", ""))
	return cur == id or (id == "sleep" and cur == "sleep_evening")


## Hours until block `id` next starts (0 while it runs).
static func hours_until(state: ColonyState, id: String) -> float:
	var h := hour_of(state)
	for b: Dictionary in BLOCKS:
		if String(b.id) == id:
			if is_block(state, id):
				return 0.0
			var start := float(b.start)
			return start - h if start > h else GameConfig.SOL_HOURS - h + start
	return INF
