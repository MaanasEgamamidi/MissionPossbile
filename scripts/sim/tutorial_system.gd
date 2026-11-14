class_name TutorialSystem
extends RefCounted
## Prompt 12: the ten-stage tutorial, the first campaign milestone (full-sol certification) and the optional
## first-crew mystery. Host only: SessionService runs `step()` every tick as a ColonySim post-system, and
## TutorialActions calls `observe()` from inside the real actions it watches. Presentation (TutorialPresenter,
## TutorialHud, StoryLogPanel, the record panel) only reads the plain data below; nothing here creates nodes.
##
## state.campaign (plain JSON, saved and replicated with the rest of ColonyState):
##   "version": 1
##   "tutorial": {
##       "stage": 1..10 (the current stage; stays 10 when done), "started": bool (the stage's start was handled),
##       "current": objective id now open, "marks": what the open objective is measured from (positions, hours),
##       "objectives": {objective id: {"done", "at_hours", "by", "skipped" (true = already mastered)}},
##       "credit": {objective id: {"by", "at_hours"}} real actions of the current stage already seen,
##       "completed": {"<n>": {"at_hours"}} each stage once, "done": bool, "done_at_hours",
##       "replay": {} or {"stage", "objectives", "credit", "marks", "current", "started_at_hours"} (a reminder run)}
##   "stage9": {"variant", "injected", "at_hours", "held_hours", "solved", "solved_at_hours", "trips", "limit_kw"}
##   "certification": {"status": "locked" | "waiting" | "paused_reserve" | "running" | "complete",
##       "elapsed_hours", "started_at_hours", "attempts", "resets": [{"reason", "detail", "at_hours", "elapsed_hours"}],
##       "completed_at_hours", "watch": {"food", "eaten", "recovery"}}
## state.discoveries: [{"id", "kind": "record" | "discovery", "by", "at_hours", "via", "station", "from"}], each id once.
##
## Rules (see docs_draft/TUTORIAL_GRAPH.md):
##   * Stages run in the supplied order; inside a stage objectives complete in order. A real action of the current
##     stage done a little early is credited when its objective opens; work from another stage never counts.
##   * An objective is checked from the colony state (positions, suits, equipment, stores, knowledge, comms stage) or
##     from a real action that changed the simulation. A knowledge objective the colony already knows is skipped.
##   * Stage 9 injects one of three real greenhouse-power faults, chosen from the colony seed. Each is harmless
##     (lights or trackers off) and solved with ordinary actions.
##   * Certification (after stage 10): every sector at tier >= 1 and CommsStage.stage >= 1, then one full sol with the
##     battery, water, oxygen and food above zero and no emergency recovery. A failure restarts the sol and keeps
##     every other kind of progress.

const DATA_PATH := "res://data/tutorial.json"
const LORE_PATH := "res://data/lore.json"
const CONFIG_PATH := "res://config/game_config.tres"
const VERSION := 1
const STAGE_COUNT := 10
## The stage 9 faults, in the order the seed picks from.
const VARIANTS: Array[String] = ["greenhouse_breaker", "trackers_stopped", "lighting_overload"]
## Essential reserves of the certification sol.
const RESERVES: Array[StringName] = [&"battery_kwh", &"water_l", &"oxygen_kg", &"food_meals"]
const RESERVE_WORDS := {&"battery_kwh": "battery", &"water_l": "clean water", &"oxygen_kg": "oxygen", &"food_meals": "food"}
## A store at or below this counts as empty.
const EMPTY := 1e-6
const RESETS_KEPT := 8
## Actions TutorialActions always watches (objectives add theirs from the data): records at salvage donors and the
## oxygen store a suit refill can empty between ticks.
const ALWAYS_WATCHED: Array[String] = ["inspect_donor", "refill_suit"]

static var _data: Dictionary = {}
static var _lore: Dictionary = {}
static var _config: GameConfig

## Host signals this system listens to (character_recovered resets the certification sol).
var _events: GameEvents
## The state of the last tick (the recovery signal arrives right after that tick, on the same state).
var _state: ColonyState


# ================================================================ data

## Re-reads data/tutorial.json and data/lore.json (tests and tools).
static func reload() -> void:
	_data = {}
	_lore = {}


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


## Engineering settings for the hub test (the same file GameServices loads).
static func config() -> GameConfig:
	if _config == null:
		var r: Resource = load(CONFIG_PATH) if ResourceLoader.exists(CONFIG_PATH) else null
		_config = r as GameConfig if r is GameConfig else GameConfig.new()
	return _config


static func number(key: String, fallback: float) -> float:
	return float(data().get(key, fallback))


static func stages() -> Array:
	return data().get("stages", []) as Array


## The definition of stage `n` (1..10), or {}.
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


static func stage9_data() -> Dictionary:
	return data().get("stage9", {}) as Dictionary


static func variant_data(variant: String) -> Dictionary:
	return (stage9_data().get("variants", {}) as Dictionary).get(variant, {}) as Dictionary


## Every action the tutorial and the story need to see (TutorialActions wraps these).
static func watched_actions() -> PackedStringArray:
	var out := PackedStringArray(ALWAYS_WATCHED)
	for s: Dictionary in stages():
		for o: Dictionary in s.get("objectives", []):
			for a in _actions_of(o):
				if not out.has(String(a)):
					out.append(String(a))
	return out


static func _actions_of(o: Dictionary) -> Array:
	match String(o.get("kind", "")):
		"action":
			return ((o.get("params", {}) as Dictionary).get("actions", []) as Array)
		"suit_topped":
			return ["refill_suit"]
	return []


# ================================================================ read-only views (safe on clients)

static func campaign_part(state: ColonyState, key: String) -> Dictionary:
	if state == null:
		return {}
	var v: Variant = state.campaign.get(key, {})
	return v if v is Dictionary else {}


static func tutorial_of(state: ColonyState) -> Dictionary:
	return campaign_part(state, "tutorial")


static func certification_of(state: ColonyState) -> Dictionary:
	return campaign_part(state, "certification")


static func stage9_of(state: ColonyState) -> Dictionary:
	return campaign_part(state, "stage9")


## The current stage, 1..10.
static func current_stage(state: ColonyState) -> int:
	return clampi(int(tutorial_of(state).get("stage", 1)), 1, STAGE_COUNT)


static func is_tutorial_done(state: ColonyState) -> bool:
	return bool(tutorial_of(state).get("done", false))


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
	var done: Dictionary = tutorial_of(state).get("objectives", {})
	return _first_open(done, current_stage(state))


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


## The reminder run in progress, or {}.
static func replay_of(state: ColonyState) -> Dictionary:
	var r: Variant = tutorial_of(state).get("replay", {})
	return r if r is Dictionary else {}


## The open objective of the reminder run, or {}.
static func replay_objective(state: ColonyState) -> Dictionary:
	var r := replay_of(state)
	if r.is_empty():
		return {}
	return _first_open(r.get("objectives", {}) as Dictionary, int(r.get("stage", 0)))


# ================================================================ texts for presentation (pure)

## The objective's words for this group: with four players (switching disabled) the team text, which never asks
## anyone to switch crew.
static func objective_text(o: Dictionary, switching_disabled: bool) -> String:
	if switching_disabled and o.has("text_team"):
		return String(o.text_team)
	return String(o.get("text", ""))


## The explanation of an objective, or "" when it is already mastered: the colony knows its question, or the stage
## was done before in this colony. A reminder (`reminder` true) always shows it.
static func explanation_for(state: ColonyState, o: Dictionary, reminder := false) -> String:
	var text := String(o.get("explain", ""))
	if reminder or text == "":
		return text
	if mastered(state, o):
		return ""
	return text


## True when the objective's explanation is already mastered in this colony.
static func mastered(state: ColonyState, o: Dictionary) -> bool:
	var q := String(o.get("question", ""))
	if q != "" and state != null and state.knowledge.has(q):
		return true
	var n := stage_of_objective(String(o.get("id", "")))
	return n > 0 and is_stage_completed(state, n)


## Hints for the objective: its own list, the team list with four players, or the stage 9 variant's list.
static func hints_for(state: ColonyState, o: Dictionary, switching_disabled: bool) -> PackedStringArray:
	var out := PackedStringArray()
	var list: Array = o.get("hints", [])
	if switching_disabled and o.has("hints_team"):
		list = o.hints_team
	if String(o.get("kind", "")) == "stage9_fixed":
		var v := String(stage9_of(state).get("variant", ""))
		list = variant_data(v).get("hints", [])
		var limit := float(stage9_of(state).get("limit_kw", stage9_data().get("lighting_line_room_kw", 3.5)))
		var formatted: Array = []
		for h in list:
			formatted.append(String(h).replace("%s", StationPanel.num(limit, 1)))
		list = formatted
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
	return "%s This step needs the %s specialist. Switch at the hub crew screen (C)." % [sym, words]


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


# ================================================================ stage 9 (pure helpers)

## The fault of stage 9 for a colony seed: the same seed always gives the same variant.
static func variant_for_seed(seed_value: int) -> String:
	var x := seed_value & 0x7fffffff
	x = (((x >> 16) ^ x) * 0x45d9f3b) & 0xffffffff
	x = (((x >> 16) ^ x) * 0x45d9f3b) & 0xffffffff
	x = (x >> 16) ^ x
	return VARIANTS[x % VARIANTS.size()]


## Room lights that are not critical and not the grow lights, switched on now (kW): the other users of the lighting line.
static func room_light_kw(state: ColonyState, balance: GameBalance) -> float:
	var total := 0.0
	var grow := FoodBalance.shared().light_zone
	for zone: String in state.zones:
		if zone == grow or balance.critical_light_zones.has(zone):
			continue
		if state.is_zone_powered(zone):
			total += balance.load_of_zone(zone)
	return total


## True when the stage 9 fault of `s9` is fixed in the colony right now.
static func stage9_fixed(state: ColonyState, balance: GameBalance, s9: Dictionary) -> bool:
	if not bool(s9.get("injected", false)):
		return false
	match String(s9.get("variant", "")):
		"greenhouse_breaker":
			return CropSystem.lights_working(state)
		"trackers_stopped":
			return PowerModel.trackers_can_track(state, balance) and not state.shed.has("trackers")
		"lighting_overload":
			return CropSystem.lights_working(state) and room_light_kw(state, balance) <= float(s9.get("limit_kw", 0.0)) + 1e-9
	return false


# ================================================================ host: campaign data

## state.campaign with every key present. Host only (it writes state).
static func ensure(state: ColonyState) -> Dictionary:
	var c := state.campaign
	if int(c.get("version", 0)) < VERSION:
		c["version"] = VERSION
	if not (c.get("tutorial", null) is Dictionary):
		c["tutorial"] = {}
	var t: Dictionary = c.tutorial
	var defaults := {"stage": 1, "started": false, "current": "", "done": false, "done_at_hours": -1.0}
	for k: String in defaults:
		if not t.has(k):
			t[k] = defaults[k]
	for k: String in ["marks", "objectives", "credit", "completed", "replay"]:
		if not (t.get(k, null) is Dictionary):
			t[k] = {}
	if not (c.get("stage9", null) is Dictionary):
		c["stage9"] = {}
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


# ================================================================ host: tick

func step(state: ColonyState, balance: GameBalance, _phase: float, dt_hours: float, events: GameEvents) -> void:
	if state == null or dt_hours <= 0.0:
		return
	_listen(events)
	_state = state
	var c := ensure(state)
	_step_stage9(state, balance, c, dt_hours, events)
	advance_tutorial(state, balance, events)
	_advance_replay(state, balance, events)
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


## Advances the tutorial as far as the colony state allows. Host only.
static func advance_tutorial(state: ColonyState, balance: GameBalance, events: GameEvents) -> void:
	var t: Dictionary = ensure(state).tutorial
	if bool(t.done):
		return
	for _guard in 64:
		var n := int(t.stage)
		if stage_def(n).is_empty():
			_finish_tutorial(state, t, events)
			return
		if not bool(t.get("started", false)):
			_start_stage(state, balance, t, n, events)
		var o := _first_open(t.objectives, n)
		if o.is_empty():
			_complete_stage(state, t, n, events)
			if bool(t.done):
				return
			continue
		var id := String(o.id)
		if String(t.current) != id:
			_activate(state, t, t.objectives, t.credit, o, events)
			if _done_in(t.objectives, id):
				continue
		var res := _check(state, balance, t.marks, t.objectives, t.credit, o)
		if bool(res.ok):
			_mark_done(state, t.objectives, o, String(res.by), false, events)
			continue
		return


static func _done_in(objectives: Dictionary, id: String) -> bool:
	return bool((objectives.get(id, {}) as Dictionary).get("done", false))


static func _start_stage(state: ColonyState, balance: GameBalance, t: Dictionary, n: int, events: GameEvents) -> void:
	t["started"] = true
	t["stage_started_at"] = state.sim_hours
	t["credit"] = {}
	t["current"] = ""
	if n == 9:
		_inject_stage9(state, balance, events)


## Opens objective `o`: what it is measured from, and at once done if the colony already knows its question or a real
## action of this stage already did it.
static func _activate(state: ColonyState, holder: Dictionary, objectives: Dictionary, credit: Dictionary, o: Dictionary, events: GameEvents) -> void:
	var id := String(o.id)
	holder["current"] = id
	var positions := {}
	for c: CharacterState in state.active_characters():
		positions[String(c.id)] = [c.position.x, c.position.y, c.position.z]
	holder["marks"] = {"positions": positions, "at_hours": state.sim_hours}
	var kind := String(o.get("kind", ""))
	if kind == "knowledge":
		var q := String((o.get("params", {}) as Dictionary).get("question", o.get("question", "")))
		if state.knowledge.has(q):
			_mark_done(state, objectives, o, String((state.knowledge[q] as Dictionary).get("by", "")), true, events)
			return
	if credit.has(id):
		_mark_done(state, objectives, o, String((credit[id] as Dictionary).get("by", "")), false, events)


static func _mark_done(state: ColonyState, objectives: Dictionary, o: Dictionary, by: String, skipped: bool, events: GameEvents) -> void:
	var id := String(o.id)
	objectives[id] = {"done": true, "at_hours": state.sim_hours, "by": by, "skipped": skipped}
	if events != null and is_same(objectives, tutorial_of(state).get("objectives", null)):
		events.objective_changed.emit(StringName(id))


static func _complete_stage(state: ColonyState, t: Dictionary, n: int, events: GameEvents) -> void:
	var completed: Dictionary = t.completed
	if not completed.has(str(n)):
		completed[str(n)] = {"at_hours": state.sim_hours}
	t["started"] = false
	t["current"] = ""
	t["marks"] = {}
	t["credit"] = {}
	var sdef := stage_def(n)
	if n >= STAGE_COUNT:
		_finish_tutorial(state, t, events)
		return
	t["stage"] = n + 1
	if events != null:
		var next := stage_def(n + 1)
		events.objective_changed.emit(StringName("stage_%d" % (n + 1)))
		events.system_alert.emit(&"tutorial_stage", &"info", "Tutorial %d of %d done: %s. Next: %s." % [n, STAGE_COUNT,
			String(sdef.get("title", "")), String(next.get("title", ""))])


static func _finish_tutorial(state: ColonyState, t: Dictionary, events: GameEvents) -> void:
	t["done"] = true
	t["done_at_hours"] = state.sim_hours
	t["stage"] = STAGE_COUNT
	var cert: Dictionary = ensure(state).certification
	if String(cert.status) == "locked":
		cert["status"] = "waiting"
	if events != null:
		events.objective_changed.emit(&"tutorial_done")
		events.system_alert.emit(&"tutorial_done", &"info", "Tutorial complete! The colony is yours to explore. Next goal: get all five sectors and the radio working, then keep the stores above zero for a whole sol.")


## Checks objective `o` against the colony now: {"ok": bool, "by": character id}.
static func _check(state: ColonyState, balance: GameBalance, marks: Dictionary, objectives: Dictionary, credit: Dictionary, o: Dictionary) -> Dictionary:
	var p: Dictionary = o.get("params", {})
	var no := {"ok": false, "by": ""}
	var id := String(o.id)
	match String(o.get("kind", "")):
		"moved":
			var metres := float(p.get("metres", number("move_m", 8.0)))
			if not (marks.get("positions", null) is Dictionary):
				marks["positions"] = {}
			var pos: Dictionary = marks.positions
			for c: CharacterState in state.active_characters():
				var key := String(c.id)
				if not pos.has(key):
					pos[key] = [c.position.x, c.position.y, c.position.z]
					continue
				if c.position.distance_to(CharacterState._v3(pos[key])) >= metres:
					return {"ok": true, "by": key}
		"near":
			var station: Dictionary = state.stations.get(String(p.get("station", "")), {})
			if station.is_empty():
				return no
			var at := CharacterState._v3(station.position)
			var r := float(p.get("metres", number("near_m", 3.0)))
			for c: CharacterState in state.active_characters():
				if c.position.distance_to(at) <= r:
					return {"ok": true, "by": String(c.id)}
		"suit_on":
			for c: CharacterState in state.active_characters():
				if c.suit_on:
					return {"ok": true, "by": String(c.id)}
		"outside":
			for c: CharacterState in _actors(state, objectives, o):
				if c.outside:
					return {"ok": true, "by": String(c.id)}
		"inside":
			var who := _same_actor(state, objectives, o)
			if who == null:
				return {"ok": true, "by": ""}
			if not who.is_active() or not who.outside:
				return {"ok": true, "by": String(who.id)}
		"at_hub":
			var cfg := config()
			for c: CharacterState in state.active_characters():
				if c.position.distance_to(cfg.hub_position) <= cfg.hub_radius_m:
					return {"ok": true, "by": String(c.id)}
		"specialist_played":
			for c: CharacterState in state.active_characters():
				if String(c.specialty) == String(p.get("specialty", "")):
					return {"ok": true, "by": String(c.id)}
		"knowledge":
			var q := String(p.get("question", o.get("question", "")))
			if state.knowledge.has(q):
				return {"ok": true, "by": String((state.knowledge[q] as Dictionary).get("by", ""))}
		"action":
			if credit.has(id):
				return {"ok": true, "by": String((credit[id] as Dictionary).get("by", ""))}
		"suit_topped":
			if credit.has(id):
				return {"ok": true, "by": String((credit[id] as Dictionary).get("by", ""))}
			var need := float(p.get("min_charge", 95.0))
			var crew := state.active_characters()
			var all_full := not crew.is_empty()
			for c: CharacterState in crew:
				all_full = all_full and c.suit_charge >= need - 1e-9
			if all_full:
				return {"ok": true, "by": String(crew[0].id)}
		"cleaner_ok":
			if state.condition_of("cleaner") >= balance.equipment_min_condition:
				return {"ok": true, "by": ""}
		"oxygen_makers_on":
			if state.is_on("electrolyser") and state.is_on("co2_unit") and float(state.water_allocation.get("electrolysis_feed_l_per_hour", 0.0)) > 0.0:
				return {"ok": true, "by": ""}
		"greenhouse_water":
			if float(state.water_allocation.get("greenhouse_l_per_hour", 0.0)) >= float(p.get("min_l_per_hour", 0.5)) - 1e-9:
				return {"ok": true, "by": ""}
		"comms_stage":
			if CommsStage.stage(state) >= int(p.get("min", 1)):
				return {"ok": true, "by": ""}
		"stage9_fixed":
			if stage9_fixed(state, balance, stage9_of(state)):
				return {"ok": true, "by": ""}
		"stage9_holds":
			if bool(stage9_of(state).get("solved", false)):
				return {"ok": true, "by": ""}
	return no


## The crew an objective looks at: the actor of `same_actor_as` if set and known, else every active crew member.
static func _actors(state: ColonyState, objectives: Dictionary, o: Dictionary) -> Array[CharacterState]:
	var who := _same_actor(state, objectives, o)
	if who != null and who.is_active():
		var one: Array[CharacterState] = [who]
		return one
	return state.active_characters()


static func _same_actor(state: ColonyState, objectives: Dictionary, o: Dictionary) -> CharacterState:
	var other := String(o.get("same_actor_as", ""))
	if other == "":
		return null
	var by := String((objectives.get(other, {}) as Dictionary).get("by", ""))
	return state.character(StringName(by)) if by != "" else null


# ================================================================ host: real actions seen (TutorialActions)

## Called from inside a watched action after it changed the colony. Credits matching objectives of the current
## stage (and of a reminder run), finds story records at salvage donors, and notices a reserve emptied by the action.
static func observe(ctx: ActionService.Context, changes: Dictionary) -> void:
	var st := ctx.state
	if st == null:
		return
	var c := ensure(st)
	var t: Dictionary = c.tutorial
	if not bool(t.done):
		_credit(ctx, changes, int(t.stage), t.objectives, t.credit)
	var r: Dictionary = t.replay
	if not r.is_empty():
		_credit(ctx, changes, int(r.get("stage", 0)), r.objectives as Dictionary, r.credit as Dictionary)
	var action := String(ctx.request.action)
	var events := ctx.session.events if ctx.session != null else null
	if action == "inspect_donor":
		for rec: Dictionary in records_at(String(ctx.request.target), "inspect_donor"):
			discover_record(st, events, String(rec.id), ctx.actor.id if ctx.actor != null else &"", "inspect_donor", String(ctx.request.target))
	var cert: Dictionary = c.certification
	if String(cert.get("status", "")) == "running":
		var empty := _empty_reserve_now(st)
		if empty != "":
			_reset_certification(st, cert, "reserve", empty, events)
			cert["status"] = "paused_reserve"


static func _credit(ctx: ActionService.Context, changes: Dictionary, n: int, objectives: Dictionary, credit: Dictionary) -> void:
	for o: Dictionary in objectives_of(n):
		var id := String(o.id)
		if _done_in(objectives, id) or credit.has(id):
			continue
		if _matches(o, ctx, changes):
			credit[id] = {"by": String(ctx.actor.id) if ctx.actor != null else "", "at_hours": ctx.state.sim_hours}


static func _matches(o: Dictionary, ctx: ActionService.Context, _changes: Dictionary) -> bool:
	var action := String(ctx.request.action)
	if not _actions_of(o).has(action):
		return false
	var p: Dictionary = o.get("params", {})
	var rp: Dictionary = ctx.request.params
	if p.has("on") and (not rp.has("on") or bool(rp.on) != bool(p.on)):
		return false
	if bool(p.get("noncritical_room", false)):
		var zone := String(rp.get("zone", ""))
		if zone == "" or zone == FoodBalance.shared().light_zone or ctx.balance.critical_light_zones.has(zone):
			return false
	if bool(p.get("living_bed", false)):
		if not CropSystem.is_alive(CropSystem.bed(ctx.state, String(ctx.request.target))):
			return false
	return true


# ================================================================ host: reminder runs

## Starts a reminder run of a completed stage (stage 0 stops it). Nothing it does counts twice: it records no stage,
## no evidence and no certification; it only ticks its own copy of the objectives.
static func start_replay(state: ColonyState, n: int) -> void:
	var t: Dictionary = ensure(state).tutorial
	if n <= 0:
		t["replay"] = {}
		return
	t["replay"] = {"stage": n, "objectives": {}, "credit": {}, "marks": {}, "current": "", "started_at_hours": state.sim_hours}


func _advance_replay(state: ColonyState, balance: GameBalance, events: GameEvents) -> void:
	var t: Dictionary = ensure(state).tutorial
	var r: Dictionary = t.replay
	if r.is_empty():
		return
	var n := int(r.get("stage", 0))
	for _guard in 16:
		var o := _first_open(r.objectives, n)
		if o.is_empty():
			t["replay"] = {}
			if events != null:
				events.system_alert.emit(&"tutorial_reminder", &"info", "Reminder of '%s' finished. Nothing was counted twice." % String(stage_def(n).get("title", "")))
			return
		var id := String(o.id)
		var kind := String(o.get("kind", ""))
		if kind == "stage9_fixed" or kind == "stage9_holds":
			# a reminder never injects the fault again: these steps are read, not played
			_mark_done(state, r.objectives, o, "", true, events)
			continue
		if String(r.current) != id:
			_activate(state, r, r.objectives, r.credit, o, events)
			if _done_in(r.objectives, id):
				continue
		var res := _check(state, balance, r.marks, r.objectives, r.credit, o)
		if bool(res.ok):
			_mark_done(state, r.objectives, o, String(res.by), false, events)
			continue
		return


# ================================================================ host: stage 9

static func _inject_stage9(state: ColonyState, balance: GameBalance, events: GameEvents) -> void:
	var c := ensure(state)
	var s9: Dictionary = c.stage9
	if bool(s9.get("injected", false)):
		return
	var variant := variant_for_seed(state.rng_seed)
	var grow := FoodBalance.shared().light_zone
	if variant != "trackers_stopped" and not state.zones.has(grow):
		variant = "trackers_stopped"            # a colony without the greenhouse circuit (tests without zones)
	var fresh := {"variant": variant, "injected": true, "at_hours": state.sim_hours, "held_hours": 0.0, "solved": false,
		"solved_at_hours": -1.0, "trips": 0, "limit_kw": 0.0}
	match variant:
		"greenhouse_breaker":
			_set_zone(state, events, grow, false)
		"trackers_stopped":
			(state.equipment["trackers"] as Dictionary)["on"] = false
		"lighting_overload":
			for zone: String in state.zones:
				if zone != grow and not balance.critical_light_zones.has(zone):
					_set_zone(state, events, zone, true)
			_set_zone(state, events, grow, false)
			# The line's rating; when the colony has fewer room lights than that (a smaller map), 60 % of what is on.
			var total := room_light_kw(state, balance)
			var limit := float(stage9_data().get("lighting_line_room_kw", 3.5))
			if total <= limit + 0.5:
				limit = 0.6 * total
			fresh["limit_kw"] = limit
	c["stage9"] = fresh
	if events != null:
		events.system_alert.emit(&"tutorial_problem", &"warn", String(variant_data(variant).get("problem", "A greenhouse power problem started.")))


static func _set_zone(state: ColonyState, events: GameEvents, zone: String, on: bool) -> void:
	if not state.zones.has(zone):
		return
	if state.is_zone_powered(zone) != on:
		(state.zones[zone] as Dictionary)["powered"] = on
		if events != null:
			events.zone_power_changed.emit(zone, on)


func _step_stage9(state: ColonyState, balance: GameBalance, c: Dictionary, dt: float, events: GameEvents) -> void:
	var s9: Dictionary = c.stage9
	if not bool(s9.get("injected", false)) or bool(s9.get("solved", false)):
		return
	var grow := FoodBalance.shared().light_zone
	if String(s9.variant) == "lighting_overload" and state.is_zone_powered(grow) and room_light_kw(state, balance) > float(s9.limit_kw) + 1e-9:
		# the shared lighting line's breaker (the injected fault): it opens while the room lights are too many
		_set_zone(state, events, grow, false)
		s9["trips"] = int(s9.get("trips", 0)) + 1
		if events != null:
			events.system_alert.emit(&"tutorial_breaker", &"warn", "The lighting breaker opened again: the grow lights and %s kW of room lights were too much for one line." % StationPanel.num(room_light_kw(state, balance), 1))
	if stage9_fixed(state, balance, s9):
		s9["held_hours"] = float(s9.get("held_hours", 0.0)) + dt
	else:
		s9["held_hours"] = 0.0
	if float(s9.held_hours) >= float(stage9_data().get("hold_hours", 1.0)) - 1e-9:
		s9["solved"] = true
		s9["solved_at_hours"] = state.sim_hours
		if events != null:
			events.system_alert.emit(&"tutorial_problem_solved", &"info", "Well done! %s" % String(variant_data(String(s9.variant)).get("solved", "The problem is solved.")))


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
