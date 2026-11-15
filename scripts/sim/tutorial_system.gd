class_name TutorialSystem
extends RefCounted
## The whiteboard tutorial (owner decisions 2026-11-14; it replaces the Prompt Pack's old ten-stage tutorial), the
## "Base operational" moment, the colony goal after it (full-sol certification) and the optional first-crew story.
## Host only: SessionService runs `step()` every tick as a ColonySim post-system, and TutorialActions calls `observe()`
## from inside the real actions it watches. Presentation (TutorialPresenter, TutorialHud, StoryLogPanel, the HUD goal
## card) only reads the plain data below; nothing here creates nodes.
##
## The flow (data/tutorial.json), as the players see it:
##   1 Arrival     the crew stand suited outside the open exit-tunnel door. Mission Control welcomes them (2060s,
##                 Earth in trouble, the second team on Mars) and says the crew radio is down. Done when anyone is
##                 inside the base.
##   2 Tapes       find the 6 room tapes (Prompt Pack C01) and play each at the Command Room cassette player (C02):
##                 "Tapes found n/6", "Tapes played n/6".
##   3 Fix         Mission Control: "Fix the base: get it to operational condition." The list shows the 10 broken
##                 spots by room with the specialist each needs (T05 and T07 have no broken part). A room is restored
##                 when its broken spots are fixed.
##   Done          all 10 fixed: the tutorial is done (the held doors are released), campaign.base_operational is set
##                 and objective_changed("base_operational") fires once (the cinematics worker plays the beauty shot).
## Fixes made early count; the tutorial still finishes only after every tape was played.
##
## state.campaign (plain JSON, saved and replicated with the rest of ColonyState):
##   "version": 2
##   "tutorial": {"flow": 2, "stage": 1..3, "started": bool, "current": open objective id,
##       "objectives": {id: {"done", "at_hours", "by"}}, "completed": {"<n>": {"at_hours"}},
##       "done": bool, "done_at_hours",
##       "locks": bool (absent until the game decides; true = tutorial mode: stations locked, crew radio down),
##       "played": [cassette ids played at the Command Room player, in order],
##       "fixed": {task id: {"at_hours", "by"}}, "restored": {room id: at_hours},
##       "log": [{"id", "text", "at_hours"}] Mission Control's lines so far (each line once)}
##   "base_operational": {} until the base works, then {"done": true, "at_hours"}
##   "objectives": [{"id", "text", "done", "fraction", "label"}] what the HUD goal card shows (ColonyGoals)
##   "certification": {"status": "locked" | "waiting" | "paused_reserve" | "running" | "complete",
##       "elapsed_hours", "started_at_hours", "attempts", "resets": [{"reason", "detail", "at_hours", "elapsed_hours"}],
##       "completed_at_hours", "watch": {"food", "eaten", "recovery"}}
## state.discoveries: [{"id", "kind": "record" | "discovery", "by", "at_hours", "via", "station", "from"}], each id once.
##
## Saves of the old ten-stage tutorial (version 1): a finished tutorial stays finished; an unfinished one starts this
## flow from the beginning (stores, upgrades, knowledge and the story are kept). The old stage 9 fault is retired.
## Certification (after the tutorial): every sector at tier >= 1 and CommsStage.stage >= 1, then one full sol with the
## battery, water, oxygen and food above zero and no emergency recovery. A failure restarts the sol.

const DATA_PATH := "res://data/tutorial.json"
const LORE_PATH := "res://data/lore.json"
const CONFIG_PATH := "res://config/game_config.tres"
const VERSION := 2
const FLOW := 2
const STAGE_COUNT := 3
## Essential reserves of the certification sol.
const RESERVES: Array[StringName] = [&"battery_kwh", &"water_l", &"oxygen_kg", &"food_meals"]
const RESERVE_WORDS := {&"battery_kwh": "battery", &"water_l": "clean water", &"oxygen_kg": "oxygen", &"food_meals": "food"}
## A store at or below this counts as empty.
const EMPTY := 1e-6
const RESETS_KEPT := 8
## Mission Control lines kept in the colony's log.
const LOG_KEPT := 40
## The task whose fix brings the crew radio back.
const RADIO_TASK := "T01"
## Actions TutorialActions always watches: the tapes played at the Command Room player, records at salvage donors and
## the oxygen store a suit refill can empty between ticks.
const ALWAYS_WATCHED: Array[String] = ["cassette_select", "cassette_read", "inspect_donor", "refill_suit"]

static var _data: Dictionary = {}
static var _lore: Dictionary = {}
static var _config: GameConfig
static var _required: PackedStringArray = PackedStringArray()
static var _required_ready := false

## Host signals this system listens to (character_recovered resets the certification sol).
var _events: GameEvents
## The state of the last tick (the recovery signal arrives right after that tick, on the same state).
var _state: ColonyState


# ================================================================ data

## Re-reads data/tutorial.json and data/lore.json (tests and tools).
static func reload() -> void:
	_data = {}
	_lore = {}
	_required_ready = false


static func data() -> Dictionary:
	if _data.is_empty():
		_data = _read_json(DATA_PATH)
		if _data.is_empty():
			push_warning("The tutorial could not be read from %s." % DATA_PATH)
			_data = {"stages": []}
	return _data


static func lore() -> Dictionary:
	if _lore.is_empty():
		_lore = _read_json(LORE_PATH)
		if _lore.is_empty():
			push_warning("The story records could not be read from %s." % LORE_PATH)
			_lore = {"records": [], "discoveries": []}
	return _lore


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Engineering settings (the same file GameServices loads).
static func config() -> GameConfig:
	if _config == null:
		var r: Resource = load(CONFIG_PATH) if ResourceLoader.exists(CONFIG_PATH) else null
		_config = r as GameConfig if r is GameConfig else GameConfig.new()
	return _config


static func number(key: String, fallback: float) -> float:
	return float(data().get(key, fallback))


static func stages() -> Array:
	return data().get("stages", []) as Array


## The definition of stage `n` (1..3), or {}.
static func stage_def(n: int) -> Dictionary:
	for s: Dictionary in stages():
		if int(s.get("n", 0)) == n:
			return s
	return {}


static func objectives_of(n: int) -> Array:
	return stage_def(n).get("objectives", []) as Array


## The objective definition with this id, or {}.
static func objective_def(id: String) -> Dictionary:
	for s: Dictionary in stages():
		for o: Dictionary in s.get("objectives", []):
			if String(o.get("id", "")) == id:
				return o
	return {}


## The stage number an objective belongs to, or 0.
static func stage_of_objective(id: String) -> int:
	for s: Dictionary in stages():
		for o: Dictionary in s.get("objectives", []):
			if String(o.get("id", "")) == id:
				return int(s.get("n", 0))
	return 0


## Mission Control's line `id` with {placeholders} filled in, or "".
static func message_text(id: String, fill := {}) -> String:
	var text := String((data().get("messages", {}) as Dictionary).get(id, ""))
	for k: String in fill:
		text = text.replace("{%s}" % k, str(fill[k]))
	return text


## Who speaks the guide lines ("Mission Control").
static func speaker() -> String:
	return String(data().get("speaker", "Mission Control"))


## Every action the tutorial and the story need to see (TutorialActions wraps these).
static func watched_actions() -> PackedStringArray:
	return PackedStringArray(ALWAYS_WATCHED)


## The broken spots of the fix step, in list order: [{"task", "text", "done"}].
static func fix_defs() -> Array:
	return data().get("fixes", []) as Array


static func fix_def(task_id: String) -> Dictionary:
	for f: Dictionary in fix_defs():
		if String(f.get("task", "")) == task_id:
			return f
	return {}


## The spots the tutorial needs fixed: the list's tasks whose puzzle is installed (PuzzleRegistry), so a missing
## puzzle never blocks the tutorial. Owner 2026-11-14: T05 and T07 have no broken part and are not on the list.
static func required_fixes() -> PackedStringArray:
	if not _required_ready:
		_required = PackedStringArray()
		for f: Dictionary in fix_defs():
			var id := String(f.get("task", ""))
			if RepairCatalog.TASKS.has(id) and PuzzleRegistry.has_puzzle(id):
				_required.append(id)
		_required_ready = true
	return _required


## The room words of a repair room id ("command_center" -> "Command Room").
static func room_words(room_id: String) -> String:
	var words := String((data().get("rooms", {}) as Dictionary).get(room_id, ""))
	if words == "":
		words = String((RepairCatalog.ROOMS.get(room_id, {}) as Dictionary).get("title", room_id))
	return words


# ================================================================ read-only views (safe on clients)

static func campaign_part(state: ColonyState, key: String) -> Dictionary:
	if state == null:
		return {}
	var v: Variant = state.campaign.get(key, {})
	return v if v is Dictionary else {}


static func tutorial_of(state: ColonyState) -> Dictionary:
	var t := campaign_part(state, "tutorial")
	# an old ten-stage record the host has not migrated yet reads as a fresh start (or as done)
	if int(t.get("flow", 0)) != FLOW and not bool(t.get("done", false)):
		return {}
	return t


static func certification_of(state: ColonyState) -> Dictionary:
	return campaign_part(state, "certification")


## Retired with the old stage 9 (kept so older tools still compile): always {}.
static func stage9_of(_state: ColonyState) -> Dictionary:
	return {}


## The current stage, 1..3.
static func current_stage(state: ColonyState) -> int:
	return clampi(int(tutorial_of(state).get("stage", 1)), 1, STAGE_COUNT)


static func is_tutorial_done(state: ColonyState) -> bool:
	return bool(campaign_part(state, "tutorial").get("done", false))


## True while the colony is in tutorial mode: the game switched it on (begin_tutorial_mode) and the tutorial is not
## done. Then only tapes, broken spots, doors and the suit rack respond to E, and the crew radio is down until T01.
static func tutorial_active(state: ColonyState) -> bool:
	var t := campaign_part(state, "tutorial")
	return bool(t.get("locks", false)) and not bool(t.get("done", false))


## The cassette player and repair goals become available with the first pickup.
## Individual repairs still require their own room's tape (task_unlocked).
static func repairs_unlocked(state: ColonyState) -> bool:
	return not tutorial_active(state) or tapes_found(state) > 0


static func task_unlocked(state: ColonyState, task_id: String) -> bool:
	if not tutorial_active(state):
		return true
	var info: Array = RepairCatalog.TASKS.get(task_id, [])
	return not info.is_empty() and CassetteCatalog.collected(state, "cassette_" + String(info[0]))


## Other station features return after the crew plays its first collected tape.
static func specialty_features_unlocked(state: ColonyState) -> bool:
	return not tutorial_active(state) or tapes_played(state) > 0


## True while the crew can not talk to each other: tutorial mode and the T01 radio is still broken.
static func crew_radio_down(state: ColonyState) -> bool:
	return tutorial_active(state) and PuzzleRegistry.is_broken(state, RADIO_TASK)


static func is_base_operational(state: ColonyState) -> bool:
	return bool(campaign_part(state, "base_operational").get("done", false))


## {"done": true, "at_hours"} once the base is operational, else {}.
static func base_operational_info(state: ColonyState) -> Dictionary:
	return campaign_part(state, "base_operational")


static func is_stage_completed(state: ColonyState, n: int) -> bool:
	return (tutorial_of(state).get("completed", {}) as Dictionary).has(str(n))


static func objective_record(state: ColonyState, id: String) -> Dictionary:
	return (tutorial_of(state).get("objectives", {}) as Dictionary).get(id, {}) as Dictionary


static func is_objective_done(state: ColonyState, id: String) -> bool:
	return bool(objective_record(state, id).get("done", false))


## The open objective's definition (the first one not done in the current stage), or {} when the tutorial is done.
static func current_objective(state: ColonyState) -> Dictionary:
	if is_tutorial_done(state):
		return {}
	return _first_open(tutorial_of(state).get("objectives", {}) as Dictionary, current_stage(state))


static func _first_open(done: Dictionary, n: int) -> Dictionary:
	for o: Dictionary in objectives_of(n):
		if not bool((done.get(String(o.id), {}) as Dictionary).get("done", false)):
			return o
	return {}


## Number of objectives done in stage `n`, and how many it has.
static func stage_progress(state: ColonyState, n: int) -> Vector2i:
	var done := 0
	var all := objectives_of(n)
	for o: Dictionary in all:
		if is_objective_done(state, String(o.id)):
			done += 1
	return Vector2i(done, all.size())


## Reminder runs of the old tutorial are retired: a reminder now just repeats Mission Control's lines (TutorialActions).
static func replay_of(_state: ColonyState) -> Dictionary:
	return {}


static func replay_objective(_state: ColonyState) -> Dictionary:
	return {}


static func tape_count() -> int:
	return CassetteCatalog.TAPES.size()


## Tapes the colony has collected (shared library, state.repair.collected_cassettes).
static func tapes_found(state: ColonyState) -> int:
	var n := 0
	for id: String in CassetteCatalog.TAPES:
		if state != null and CassetteCatalog.collected(state, id):
			n += 1
	return n


static func is_tape_played(state: ColonyState, cassette_id: String) -> bool:
	return (tutorial_of(state).get("played", []) as Array).has(cassette_id)


static func tapes_played(state: ColonyState) -> int:
	var n := 0
	for id: String in CassetteCatalog.TAPES:
		if is_tape_played(state, id):
			n += 1
	return n


## True when the broken spot of `task_id` is fixed (its puzzle solved once, from the real repair state).
static func is_fixed(state: ColonyState, task_id: String) -> bool:
	if state == null:
		return false
	var task: Dictionary = (state.repair.get("tasks", {}) as Dictionary).get(task_id, {})
	return bool(task.get("first_completed", false))


static func fixed_count(state: ColonyState) -> int:
	var n := 0
	for id: String in required_fixes():
		if is_fixed(state, id):
			n += 1
	return n


## The fix list as rows: [{"task", "room_id", "room", "text", "specialty" ("" for anyone), "done"}].
static func fix_rows(state: ColonyState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in required_fixes():
		var info: Array = RepairCatalog.TASKS[id]
		var spec := String(info[2])
		if state != null:
			spec = String(((state.repair.get("tasks", {}) as Dictionary).get(id, {}) as Dictionary).get("required_specialty", spec))
		out.append({"task": id, "room_id": String(info[0]), "room": room_words(String(info[0])), "text": String(fix_def(id).get("text", id)),
			"specialty": "" if spec == "general" else spec, "done": is_fixed(state, id)})
	return out


## Rooms with broken spots on the list: [{"room_id", "room", "fixed", "total", "restored"}], in list order.
static func room_rows(state: ColonyState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var index := {}
	for r: Dictionary in fix_rows(state):
		var rid := String(r.room_id)
		if not index.has(rid):
			index[rid] = out.size()
			out.append({"room_id": rid, "room": String(r.room), "fixed": 0, "total": 0, "restored": false})
		var row: Dictionary = out[int(index[rid])]
		row["total"] = int(row.total) + 1
		if bool(r.done):
			row["fixed"] = int(row.fixed) + 1
		row["restored"] = int(row.fixed) == int(row.total)
	return out


## Mission Control's lines so far, oldest first: [{"id", "text", "at_hours"}].
static func mission_log(state: ColonyState) -> Array:
	return (tutorial_of(state).get("log", []) as Array)


## The newest Mission Control line, or "".
static func last_message(state: ColonyState) -> String:
	var log := mission_log(state)
	return String((log[log.size() - 1] as Dictionary).get("text", "")) if not log.is_empty() else ""


# ================================================================ texts for presentation (pure)

## The objective's words for this group: with four players (switching disabled) the team text, which never asks
## anyone to switch crew.
static func objective_text(o: Dictionary, switching_disabled: bool) -> String:
	if switching_disabled and o.has("text_team"):
		return String(o.text_team)
	return String(o.get("text", ""))


## The explanation of an objective, or "" when its stage was already done in this colony. A reminder always shows it.
static func explanation_for(state: ColonyState, o: Dictionary, reminder := false) -> String:
	var text := String(o.get("explain", ""))
	if reminder or text == "":
		return text
	if mastered(state, o):
		return ""
	return text


## True when the objective's stage was done before in this colony.
static func mastered(state: ColonyState, o: Dictionary) -> bool:
	var n := stage_of_objective(String(o.get("id", "")))
	return n > 0 and is_stage_completed(state, n)


## Hints for the objective: its own list, or the team list with four players.
static func hints_for(_state: ColonyState, o: Dictionary, switching_disabled: bool) -> PackedStringArray:
	var out := PackedStringArray()
	var list: Array = o.get("hints", [])
	if switching_disabled and o.has("hints_team"):
		list = o.hints_team
	for h in list:
		out.append(String(h))
	return out


## How many hints to show: one after `hint_after_s` real seconds without progress, one more every `hint_repeat_s`,
## plus one for each request, never more than there are.
static func hint_count(idle_seconds: float, requested: int, available: int) -> int:
	var after := number("hint_after_s", 75.0)
	var repeat := maxf(1.0, number("hint_repeat_s", 60.0))
	var by_time := 0
	if idle_seconds >= after:
		by_time = 1 + int(floorf((idle_seconds - after) / repeat))
	return clampi(by_time + maxi(0, requested), 0, available)


## The specialist cue for a step. Never asks a four-player group to switch: it names who should act instead.
## `local_id` is the character this screen's player controls ("" for none).
static func specialist_cue(state: ColonyState, specialty: String, local_id: StringName, switching_disabled: bool, soft := false) -> String:
	if specialty == "" or state == null:
		return ""
	var sym := String(StationPanels.SPECIALTY_SYMBOLS.get(StringName(specialty), "●"))
	var words := String(StationPanels.SPECIALTY_WORDS.get(StringName(specialty), specialty))
	var mine := state.character(local_id) if local_id != &"" else null
	if mine != null and String(mine.specialty) == specialty:
		return "%s You are the %s specialist: this step is yours." % [sym, words]
	if soft:
		return "%s The %s specialist is the expert here, but anyone can do this step." % [sym, words]
	for c: CharacterState in state.active_characters():
		if String(c.specialty) == specialty:
			return "%s The %s specialist (played by another player) does this step." % [sym, words]
	if switching_disabled:
		return "%s This step is for the %s specialist. Ask the player of that crew member." % [sym, words]
	return "%s This step needs the %s specialist. Switch crew member in the Med Bay (C)." % [sym, words]


## What the campaign still needs before the certification sol can start: [{"id", "text"}].
static func requirements_missing(state: ColonyState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tips: Dictionary = data().get("campaign_tips", {})
	for sector: String in ProgressionSystem.SECTORS:
		if ProgressionSystem.tier(state, sector) < 1:
			out.append({"id": sector, "text": String(tips.get(sector, ProgressionSystem.sector_name(sector)))})
	if CommsStage.stage(state) < 1:
		out.append({"id": "comms", "text": String(tips.get("comms", "Communications"))})
	return out


## Which sectors work now, by the certification rule: {sector: bool, "comms": bool}.
static func sectors_operating(state: ColonyState) -> Dictionary:
	var out := {}
	for sector: String in ProgressionSystem.SECTORS:
		out[sector] = ProgressionSystem.tier(state, sector) >= 1
	out["comms"] = CommsStage.stage(state) >= 1
	return out


## Room lights that are not critical and not the grow lights, switched on now (kW). Kept for tools/playtest.
static func room_light_kw(state: ColonyState, balance: GameBalance) -> float:
	var total := 0.0
	var grow := FoodBalance.shared().light_zone
	for zone: String in state.zones:
		if zone == grow or balance.critical_light_zones.has(zone):
			continue
		if state.is_zone_powered(zone):
			total += balance.load_of_zone(zone)
	return total


# ================================================================ host: campaign data

static func _fresh_tutorial() -> Dictionary:
	return {"flow": FLOW, "stage": 1, "started": false, "current": "", "objectives": {}, "completed": {}, "done": false,
		"done_at_hours": -1.0, "played": [], "fixed": {}, "restored": {}, "log": []}


## state.campaign with every key present (an old ten-stage record is migrated). Host only (it writes state).
static func ensure(state: ColonyState) -> Dictionary:
	var c := state.campaign
	if int(c.get("version", 0)) < VERSION or not (c.get("tutorial", null) is Dictionary) or int((c.tutorial as Dictionary).get("flow", 0)) != FLOW:
		var old: Dictionary = c.get("tutorial", {}) if c.get("tutorial", null) is Dictionary else {}
		if int(old.get("flow", 0)) != FLOW:
			var t := _fresh_tutorial()
			if bool(old.get("done", false)):
				# a colony that finished the old tutorial stays finished
				t["done"] = true
				t["done_at_hours"] = float(old.get("done_at_hours", state.sim_hours))
				t["stage"] = STAGE_COUNT
			if old.has("locks"):
				t["locks"] = bool(old.locks)
			c["tutorial"] = t
		c.erase("stage9")
		c["version"] = VERSION
	var tut: Dictionary = c.tutorial
	var fresh := _fresh_tutorial()
	for k: String in fresh:
		var container: bool = fresh[k] is Array or fresh[k] is Dictionary
		if not tut.has(k) or (container and typeof(tut[k]) != typeof(fresh[k])):
			tut[k] = fresh[k]
	if not (c.get("base_operational", null) is Dictionary):
		c["base_operational"] = {}
	if not (c.get("objectives", null) is Array):
		c["objectives"] = []
	if not (c.get("certification", null) is Dictionary):
		c["certification"] = {}
	var cert: Dictionary = c.certification
	var cdef := {"status": "locked", "elapsed_hours": 0.0, "started_at_hours": -1.0, "attempts": 0, "completed_at_hours": -1.0}
	for k: String in cdef:
		if not cert.has(k):
			cert[k] = cdef[k]
	if not (cert.get("resets", null) is Array):
		cert["resets"] = []
	if not (cert.get("watch", null) is Dictionary):
		cert["watch"] = {}
	return c


## Tutorial mode is decided once per colony, by the game (TutorialPresenter on the host, from
## GameConfig.tutorial_start_outside): `on` = stations locked and the crew radio down until the tutorial is done.
## Simulation-only harnesses never call this, so their stations work as before. Host only. Returns the mode now.
static func begin_tutorial_mode(state: ColonyState, on: bool) -> bool:
	if state == null:
		return false
	var t: Dictionary = ensure(state).tutorial
	if not t.has("locks"):
		t["locks"] = on and not bool(t.done)
	return bool(t.locks)


## Ends the tutorial at once without the "Base operational" moment (test fixtures and tools that need every station
## usable in a new game). Host only.
static func skip_tutorial(state: ColonyState, events: GameEvents = null) -> void:
	var t: Dictionary = ensure(state).tutorial
	if bool(t.done):
		return
	t["skipped"] = true
	_finish_tutorial(state, t, events, false)


# ================================================================ host: tick

func step(state: ColonyState, balance: GameBalance, _phase: float, dt_hours: float, events: GameEvents) -> void:
	if state == null or dt_hours <= 0.0:
		return
	_listen(events)
	_state = state
	var c := ensure(state)
	advance_tutorial(state, balance, events)
	_step_certification(state, c, dt_hours, events)


func _listen(events: GameEvents) -> void:
	if events == null or events == _events:
		return
	if _events != null and is_instance_valid(_events) and _events.character_recovered.is_connected(_on_recovered):
		_events.character_recovered.disconnect(_on_recovered)
	_events = events
	events.character_recovered.connect(_on_recovered)


## An emergency recovery during the certification sol restarts the sol (progress is kept).
func _on_recovered(id: StringName, _info: Dictionary) -> void:
	if _state == null:
		return
	var cert := certification_of(_state)
	if String(cert.get("status", "")) == "running":
		_reset_certification(_state, cert, "recovery", String(id), _events)


## Advances the tutorial as far as the colony state allows, and keeps the goal card's list current. Host only.
static func advance_tutorial(state: ColonyState, _balance: GameBalance, events: GameEvents) -> void:
	var t: Dictionary = ensure(state).tutorial
	if not bool(t.done):
		_note_fixes(state, t, events)
		for _guard in 32:
			var n := int(t.stage)
			if stage_def(n).is_empty():
				_finish_tutorial(state, t, events, true)
				break
			if not bool(t.get("started", false)):
				_start_stage(state, t, n, events)
			var o := _first_open(t.objectives, n)
			if o.is_empty():
				_complete_stage(state, t, n, events)
				if bool(t.done):
					break
				continue
			var id := String(o.id)
			if String(t.current) != id:
				t["current"] = id
			if _check(state, o):
				_mark_done(state, t, o, events)
				continue
			break
	_publish_objectives(state)


static func _start_stage(state: ColonyState, t: Dictionary, n: int, events: GameEvents) -> void:
	t["started"] = true
	t["current"] = ""
	t["stage_started_at"] = state.sim_hours
	for id in stage_def(n).get("start_messages", []):
		say(state, events, String(id))


static func _mark_done(state: ColonyState, t: Dictionary, o: Dictionary, events: GameEvents) -> void:
	var id := String(o.id)
	(t.objectives as Dictionary)[id] = {"done": true, "at_hours": state.sim_hours, "by": ""}
	if String(o.get("done_message", "")) != "":
		say(state, events, String(o.done_message))
	if events != null:
		events.objective_changed.emit(StringName(id))


static func _complete_stage(state: ColonyState, t: Dictionary, n: int, events: GameEvents) -> void:
	var completed: Dictionary = t.completed
	if not completed.has(str(n)):
		completed[str(n)] = {"at_hours": state.sim_hours}
	t["started"] = false
	t["current"] = ""
	if n >= STAGE_COUNT:
		_finish_tutorial(state, t, events, true)
		return
	t["stage"] = n + 1
	if events != null:
		events.objective_changed.emit(StringName("stage_%d" % (n + 1)))


## The tutorial is done: doors are released (GameMain reads is_tutorial_done) and, when the base really works
## (`operational`), the "Base operational" moment fires once.
static func _finish_tutorial(state: ColonyState, t: Dictionary, events: GameEvents, operational: bool) -> void:
	t["done"] = true
	t["done_at_hours"] = state.sim_hours
	t["stage"] = STAGE_COUNT
	t["current"] = ""
	var c := ensure(state)
	var cert: Dictionary = c.certification
	if String(cert.status) == "locked":
		cert["status"] = "waiting"
	if operational and not bool((c.base_operational as Dictionary).get("done", false)):
		c["base_operational"] = {"done": true, "at_hours": state.sim_hours}
		say(state, events, "base_operational")
		if events != null:
			events.objective_changed.emit(&"base_operational")
	if events != null:
		events.objective_changed.emit(&"tutorial_done")
	_publish_objectives(state)


## Checks objective `o` against the colony now.
static func _check(state: ColonyState, o: Dictionary) -> bool:
	match String(o.get("kind", "")):
		"inside_base":
			if tapes_found(state) > 0:
				return true
			for c: CharacterState in state.active_characters():
				if not c.outside:
					return true
		"tapes_found":
			return tapes_found(state) >= tape_count()
		"tapes_played":
			return tapes_played(state) >= tape_count()
		"fixes":
			return fixed_count(state) >= required_fixes().size()
	return false


## Notices broken spots fixed since the last check (from the real repair state): records them, says so, and says
## when a room is restored. Fixes made before the fix step count too.
static func _note_fixes(state: ColonyState, t: Dictionary, events: GameEvents) -> void:
	var fixed: Dictionary = t.fixed
	var total := required_fixes().size()
	var restored: Dictionary = t.restored
	for id: String in required_fixes():
		if fixed.has(id) or not is_fixed(state, id):
			continue
		fixed[id] = {"at_hours": state.sim_hours, "by": ""}
		say(state, events, "fixed", {"done": String(fix_def(id).get("done", id)), "n": fixed.size(), "total": total})
		if id == RADIO_TASK and bool(t.get("locks", false)):
			say(state, events, "radio_back")
		if events != null:
			events.objective_changed.emit(StringName("fixed_" + id))
	for r: Dictionary in room_rows(state):
		if bool(r.restored) and not restored.has(String(r.room_id)):
			restored[String(r.room_id)] = state.sim_hours
			say(state, events, "room_restored", {"room": String(r.room)})


## Sends one of Mission Control's lines (data/tutorial.json "messages") once per colony: as a system alert for every
## player and into the colony's log. Host only. Returns true when it was sent now.
static func say(state: ColonyState, events: GameEvents, id: String, fill := {}) -> bool:
	var text := message_text(id, fill)
	if text == "":
		return false
	var t: Dictionary = ensure(state).tutorial
	var log: Array = t.log
	var key := id if fill.is_empty() else "%s:%s" % [id, text]
	for entry: Variant in log:
		if entry is Dictionary and String((entry as Dictionary).get("id", "")) == key:
			return false
	log.append({"id": key, "text": text, "at_hours": state.sim_hours})
	while log.size() > LOG_KEPT:
		log.pop_front()
	if events != null:
		events.system_alert.emit(&"mission_control", &"info", "%s: %s" % [speaker(), text])
	return true


## The HUD goal card's list (ColonyGoals reads state.campaign.objectives): the open step's goals while the tutorial
## runs, the base as a whole once it is operational.
static func _publish_objectives(state: ColonyState) -> void:
	var c := state.campaign
	var list: Array = []
	if not is_tutorial_done(state):
		var n := current_stage(state)
		if n == 1:
			list.append(_goal("tutorial_arrival", "Walk into the base", false, 0.0, ""))
		elif n == 2:
			var found := tapes_found(state)
			var played := tapes_played(state)
			list.append(_goal("tapes_found", "Tapes found", found >= tape_count(), float(found) / float(tape_count()), "%d/%d" % [found, tape_count()]))
			list.append(_goal("tapes_played", "Tapes played", played >= tape_count(), float(played) / float(tape_count()), "%d/%d" % [played, tape_count()]))
		else:
			for r: Dictionary in room_rows(state):
				list.append(_goal("room_" + String(r.room_id), "Fix the %s" % String(r.room), bool(r.restored),
					float(r.fixed) / float(maxi(1, int(r.total))), "%d/%d" % [int(r.fixed), int(r.total)]))
	elif is_base_operational(state):
		list.append(_goal("base_operational", "Base operational", true, 1.0, ""))
	if not _same_list(c.get("objectives", []), list):
		c["objectives"] = list


static func _goal(id: String, text: String, done: bool, fraction: float, label: String) -> Dictionary:
	return {"id": id, "text": text, "done": done, "fraction": clampf(fraction, 0.0, 1.0), "label": label}


static func _same_list(a: Variant, b: Array) -> bool:
	return a is Array and JSON.stringify(a) == JSON.stringify(b)


# ================================================================ host: real actions seen (TutorialActions)

## Called from inside a watched action after it changed the colony: records a tape played at the Command Room player,
## finds story records at salvage donors, and notices a reserve emptied by the action.
static func observe(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	if st == null:
		return
	var c := ensure(st)
	var t: Dictionary = c.tutorial
	var action := String(ctx.request.action)
	var events := ctx.session.events if ctx.session != null else null
	if action == "cassette_select" or action == "cassette_read":
		var id := String(changes.get("cassette_id", ctx.request.params.get("cassette_id", "")))
		if bool(changes.get("authorized", false)) and CassetteCatalog.collected(st, id) and not (t.played as Array).has(id):
			(t.played as Array).append(id)
			if events != null:
				events.objective_changed.emit(StringName("played_" + id))
	if action == "inspect_donor":
		for rec: Dictionary in records_at(String(ctx.request.target), "inspect_donor"):
			discover_record(st, events, String(rec.id), ctx.actor.id if ctx.actor != null else &"", "inspect_donor", String(ctx.request.target))
	var cert: Dictionary = c.certification
	if String(cert.get("status", "")) == "running":
		var empty := _empty_reserve_now(st)
		if empty != "":
			_reset_certification(st, cert, "reserve", empty, events)
			cert["status"] = "paused_reserve"


## Mission Control's lines of a finished stage, for a reminder (TutorialActions "tutorial_replay").
static func reminder_lines(n: int) -> PackedStringArray:
	var out := PackedStringArray()
	for id in stage_def(n).get("start_messages", []):
		var text := message_text(String(id))
		if text != "":
			out.append("%s: %s" % [speaker(), text])
	for o: Dictionary in objectives_of(n):
		out.append("▶ " + String(o.get("text", "")))
	return out


# ================================================================ host: certification

func _step_certification(state: ColonyState, c: Dictionary, dt: float, events: GameEvents) -> void:
	var cert: Dictionary = c.certification
	var status := String(cert.status)
	if status == "complete":
		return
	var empty := _empty_reserve(state, cert)
	_watch(state, cert)
	if not bool((c.tutorial as Dictionary).get("done", false)):
		cert["status"] = "locked"
		return
	if not requirements_missing(state).is_empty():
		cert["status"] = "waiting"
		cert["elapsed_hours"] = 0.0
		return
	if empty != "":
		if status == "running":
			_reset_certification(state, cert, "reserve", empty, events)
		cert["status"] = "paused_reserve"
		return
	if status != "running":
		cert["status"] = "running"
		cert["started_at_hours"] = state.sim_hours
		cert["elapsed_hours"] = 0.0
		cert["attempts"] = int(cert.get("attempts", 0)) + 1
		if events != null:
			events.system_alert.emit(&"certification_started", &"info", "Certification sol started: keep the battery, water, oxygen and food above zero for one whole sol, with nobody needing a rescue.")
		return
	cert["elapsed_hours"] = float(cert.elapsed_hours) + dt
	var need := float((data().get("certification", {}) as Dictionary).get("sols", 1.0)) * GameConfig.SOL_HOURS
	if float(cert.elapsed_hours) >= need - 1e-9:
		cert["status"] = "complete"
		cert["completed_at_hours"] = state.sim_hours
		if events != null:
			events.objective_changed.emit(&"campaign_milestone_1")
			events.system_alert.emit(&"campaign_milestone", &"info", "First campaign milestone: a sustainable colony! Every sector works and the stores stayed above zero for a whole sol. The colony keeps running: explore, upgrade and solve the first crew's mystery if you like.")


## The reserve that is empty now or was empty at the end of the last tick ("" for none). Food is eaten after this
## system runs, so the food left at the end of the last tick is worked out from the ledger.
static func _empty_reserve(state: ColonyState, cert: Dictionary) -> String:
	var now := _empty_reserve_now(state)
	if now != "":
		return now
	var w: Dictionary = cert.get("watch", {})
	if w.has("food"):
		var eaten := float(state.ledger.get("meals_eaten", 0.0)) - float(w.get("eaten", 0.0))
		var rescued := float(state.ledger.get("recovery_meals", 0.0)) - float(w.get("recovery", 0.0))
		if float(w.food) - eaten - rescued <= EMPTY:
			return "food_meals"
	return ""


static func _empty_reserve_now(state: ColonyState) -> String:
	for k: StringName in RESERVES:
		if state.store(k) <= EMPTY:
			return String(k)
	return ""


static func _watch(state: ColonyState, cert: Dictionary) -> void:
	cert["watch"] = {"food": state.store(&"food_meals"), "eaten": float(state.ledger.get("meals_eaten", 0.0)),
		"recovery": float(state.ledger.get("recovery_meals", 0.0))}


## Restarts the certification sol. Every other kind of progress is kept.
static func _reset_certification(state: ColonyState, cert: Dictionary, reason: String, detail: String, events: GameEvents) -> void:
	var elapsed := float(cert.get("elapsed_hours", 0.0))
	cert["elapsed_hours"] = 0.0
	cert["started_at_hours"] = state.sim_hours
	if elapsed <= 0.0:
		return
	var resets: Array = cert.get("resets", [])
	resets.append({"reason": reason, "detail": detail, "at_hours": state.sim_hours, "elapsed_hours": elapsed})
	while resets.size() > RESETS_KEPT:
		resets.pop_front()
	cert["resets"] = resets
	if events != null:
		var why := "a crew member needed an emergency rescue" if reason == "recovery" else "the %s store reached zero" % String(RESERVE_WORDS.get(StringName(detail), detail))
		events.system_alert.emit(&"certification_reset", &"warn", "Certification sol restarted: %s. Everything you built is kept; the sol starts again when the stores are above zero." % why)


## Share of the certification sol done, 0..1.
static func certification_share(state: ColonyState) -> float:
	var cert := certification_of(state)
	if String(cert.get("status", "")) == "complete":
		return 1.0
	var need := float((data().get("certification", {}) as Dictionary).get("sols", 1.0)) * GameConfig.SOL_HOURS
	return clampf(float(cert.get("elapsed_hours", 0.0)) / maxf(need, 1e-9), 0.0, 1.0)


# ================================================================ story records (optional mystery)

static func records() -> Array:
	return lore().get("records", []) as Array


static func record_def(id: String) -> Dictionary:
	for r: Dictionary in records():
		if String(r.get("id", "")) == id:
			return r
	return {}


## Records found at `station_id` by the action `via` ("read_record" or "inspect_donor").
static func records_at(station_id: String, via: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in records():
		if String(r.get("station", "")) == station_id and String(r.get("via", "")) == via:
			out.append(r)
	return out


## Every discovery definition: the four middle discoveries, then the final one.
static func discovery_defs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in lore().get("discoveries", []):
		out.append(d)
	var final: Variant = lore().get("final", null)
	if final is Dictionary:
		out.append(final)
	return out


static func is_found(state: ColonyState, id: String) -> bool:
	if state == null:
		return false
	for d: Variant in state.discoveries:
		if d is Dictionary and String((d as Dictionary).get("id", "")) == id:
			return true
	return false


## Records the record `record_id` as found (once) and any discovery it completes. Host only.
## Returns {"new": bool, "discoveries": [ids completed now]}.
static func discover_record(state: ColonyState, events: GameEvents, record_id: String, actor: StringName, via: String, station: String) -> Dictionary:
	var out := {"new": false, "discoveries": []}
	var rec := record_def(record_id)
	if rec.is_empty() or is_found(state, record_id):
		return out
	state.discoveries.append({"id": record_id, "kind": "record", "by": String(actor), "at_hours": state.sim_hours, "via": via, "station": station})
	out["new"] = true
	if events != null:
		events.system_alert.emit(&"story_record", &"info", "Record found: %s. Read it in the colony journal (L)." % String(rec.get("title", record_id)))
	for d: Dictionary in discovery_defs():
		var did := String(d.get("id", ""))
		if did == "" or is_found(state, did):
			continue
		var needs: Array = d.get("clues", d.get("requires", []))
		var all_found := not needs.is_empty()
		for need in needs:
			all_found = all_found and is_found(state, String(need))
		if all_found:
			state.discoveries.append({"id": did, "kind": "discovery", "by": String(actor), "at_hours": state.sim_hours, "from": needs.duplicate()})
			(out.discoveries as Array).append(did)
			if events != null:
				events.system_alert.emit(&"story_discovery", &"info", "Discovery: %s." % String(d.get("title", did)))
	return out
