extends Node
## The H key (owner 2026-11-15, docs/revisions/UPGRADE_PATHS_PLAN.md §1.6: "H should make the sparkle lines pop up").
## Owner's constant rule: gold + sparkles always mean "this works / go this way".
## H picks WHAT MATTERS NOW for this machine's player and draws the gold sparkle line there (guide_sparkles.gd,
## show_line_to, following the player) for SHOW_S seconds; H again ends it early. Mission Control says one short line
## of what to do. The order:
##   (a) an emergency with a place:
##         no air around you (the lethal exposure timer runs)  -> safe air (back through the tunnel's inner door, or
##                                                                the tunnel's outer door from outside)
##         a solar (radiation) storm warned or running          -> the storm shelter (state.radiation, else the Med Bay)
##         a dust storm warned or running while you are outside -> the exit tunnel's outer door (the airlock)
##         the COLONY OVER countdown                            -> the room that makes the store that ran out
##         the exit tunnel door leaking air (T12)               -> the leak, when you can fix it
##         a broken part's alarm (maintenance fault)            -> the nearest one you can fix
##   (b) your schedule block's place when you are late (ScheduleSystem.where_to_be, only when that script has it);
##   (c) the first unfinished goal (ColonyGoals.all): the nearest tape still lying out, the tape player, the nearest
##       broken part this crew member can fix, else the Med Bay crew hub (C changes crew member);
##   (d) outside: the airlock. Otherwise only the message "Nothing urgent right now - check your goals (J)".
## The choice is looked at again every REPICK_S while the line shows (a tape picked up, a fault fixed, a new storm).
## Works while walking and seated in the rover (the line starts at the seat); MissionHud does not pass H on while a
## panel or mini-game is open. timed_emergencies() feeds the "Press H for help" pop-up (scripts/ui/hud/help_prompt.gd).
## Presentation only, this machine's own player; it never changes the colony. Made by MissionHud. Loaded by path (no
## class_name).

const WalkPaths := preload("res://scripts/guide/walk_paths.gd")
const CrewDay := preload("res://scripts/schedule/crew_day.gd")
const GoalsBigPanel := preload("res://scripts/ui/hud/goals_big_panel.gd")
## The schedule system another helper adds; used only when the file and its where_to_be exist.
const SCHEDULE_PATH := "res://scripts/schedule/schedule_system.gd"

## How long one H shows the line, real seconds.
const SHOW_S := 20.0
## Seconds between looks at what matters now while the line shows.
const REPICK_S := 1.0
## A new target this far from the old one moves the line, metres.
const MOVE_M := 0.3
## Farther than this from the schedule block's place counts as late (when the schedule system does not say), metres.
const LATE_M := 6.0
## Candidates compared by walking distance (the nearest ones in a straight line).
const CHOOSE_BY_WALK := 3
## Safe air from the exit tunnel's vestibule: just inside its inner door 901 (LocalPressure.VOLUME starts at z 10.3).
const SAFE_AIR := Vector3(22.0, 0.0, 9.3)
## The room that makes each life store, by a repair task in it (the station there is the place to fix it).
const STORE_TASK := {"oxygen": "T09", "power": "T03", "electricity": "T03", "battery": "T03", "water": "T06", "food": "T05"}
const STORE_WORDS := {"oxygen": "Oxygen", "power": "Electricity", "electricity": "Electricity", "battery": "Electricity",
	"water": "Water", "food": "Food"}

var services: GameServices
## MissionHud (for its `mission_control` card and `game`).
var hud: Node
## True while an H line shows.
var active := false
## The current choice: {"at": Vector3, "why": String, "say": String, "kind": StringName} or {}.
var pick := {}

var _left := 0.0
var _repick_left := 0.0
var _said_text := ""
## Station floor anchors: station id -> Vector3 (repair stations and the cassette player).
var _anchors := {}
var _paths: WalkPaths


func setup(p_services: GameServices, p_hud: Node) -> void:
	services = p_services
	hud = p_hud
	name = "HelpKey"
	for entry: Dictionary in StationCatalog.extra_entries():
		if entry.has("position") and entry.has("id"):
			var q: Array = entry.position
			if q.size() >= 3:
				_anchors[String(entry.id)] = Vector3(float(q[0]), float(q[1]), float(q[2]))


# ---------------------------------------------------------------- the key

## H: show the way to what matters now, or end the line early.
func toggle() -> void:
	if active:
		stop()
	else:
		start()


func start() -> void:
	if services == null or not services.has_game():
		return
	var p := pick_target()
	if p.is_empty():
		stop()
		_say("Nothing urgent right now - check your goals (%s)." % _key_name(&"goals", "J"), &"info")
		return
	active = true
	_left = SHOW_S
	_repick_left = REPICK_S
	pick = p
	_show(p)
	_say(String(p.say), p.kind)


func stop() -> void:
	var was := active
	active = false
	pick = {}
	var guide := _guide()
	if was and guide != null:
		guide.call(&"clear")


func _process(delta: float) -> void:
	if not active:
		return
	if services == null or not services.has_game():
		stop()
		return
	_left -= delta
	if _left <= 0.0:
		stop()
		return
	_repick_left -= delta
	if _repick_left > 0.0:
		return
	_repick_left = REPICK_S
	var p := pick_target()
	if p.is_empty():
		stop()
		return
	var changed := String(p.why) != String(pick.get("why", ""))
	var at: Vector3 = p.at
	var old: Variant = pick.get("at")
	if changed or not old is Vector3 or at.distance_to(old as Vector3) > MOVE_M:
		pick = p
		_show(p)
	if changed:
		_say(String(p.say), p.kind)


func _show(p: Dictionary) -> void:
	var guide := _guide()
	if guide != null:
		guide.call(&"show_line_to", p.at as Vector3, true)


# ---------------------------------------------------------------- what matters now

## {"at": Vector3, "why", "say", "kind"} for this machine's player, or {} (see the header for the order).
func pick_target() -> Dictionary:
	if services == null or not services.has_game():
		return {}
	var st := services.state()
	var me := services.local_character()
	if st == null or me == null:
		return {}
	var from := _player_position(me)
	var found := emergency_target(st, me, from)
	if found.is_empty():
		found = schedule_target(st, me, from)
	if found.is_empty():
		found = goal_target(st, me, from)
	if found.is_empty() and me.outside:
		found = _entry(_airlock(), "airlock", "Follow the gold sparkles back to the airlock.", &"info")
	return found


## (a) An emergency with a place, or {}.
func emergency_target(st: ColonyState, me: CharacterState, from: Vector3) -> Dictionary:
	# No air around you: the lethal timer runs (a suit stops it, so this is only without one).
	if me.exposure_active and me.lethal_exposure_seconds > 0.0:
		if me.in_airlock_pressure_volume:
			return _entry(SAFE_AIR, "exposure", "No air here! Follow the gold sparkles back through the inner door, now.", &"danger")
		if me.outside:
			return _entry(_airlock(), "exposure", "No air out here! Follow the gold sparkles to the airlock, now.", &"danger")
	# A solar (radiation) storm: everyone to the storm shelter.
	var rad := radiation_info(st)
	if not rad.is_empty():
		return _entry(rad.shelter as Vector3, "radiation", "Solar storm! Follow the gold sparkles to the storm shelter in the Med Bay.", &"danger")
	# A dust storm while you are outside: back in.
	var storm := StormOutlook.now(st)
	if me.outside and String(storm.get("phase", "calm")) != "calm":
		var words := "A dust storm is coming" if String(storm.phase) == "warned" else "You are out in a dust storm"
		return _entry(_airlock(), "dust_storm", "%s. Follow the gold sparkles back to the airlock." % words, &"warn")
	# COLONY OVER is counting down: the room that makes the store that ran out.
	var over := colony_over_info(st)
	if not over.is_empty():
		var store := String(over.store)
		var spot: Variant = _task_spot(st, String(STORE_TASK.get(store, "")))
		var what := String(STORE_WORDS.get(store, "A life supply"))
		if spot is Vector3:
			return _entry(spot as Vector3, "colony_over", "%s has run out! Follow the gold sparkles and get it back above zero before the countdown ends." % what, &"danger")
	# The exit tunnel door leaks air (T12), for the crew member who can seal it. Not while the tapes are still being
	# found in the tutorial: the leak is there from the start and the suits keep everyone safe meanwhile.
	if bool(st.pressure.get("leaking", false)) and _can_fix(me, "T12") and \
			TutorialSystem.task_unlocked(st, "T12"):
		var leak: Variant = _task_spot(st, "T12")
		if leak is Vector3:
			return _entry(leak as Vector3, "air_leak", "Air is leaking at the exit tunnel door. Follow the gold sparkles and seal it (keep your helmet on).", &"danger")
	# A broken part's alarm (maintenance fault) this crew member can fix: the nearest.
	var faults: Array[Dictionary] = []
	for task_id: String in RepairCatalog.TASKS:
		if task_id == "T12" and bool(st.pressure.get("leaking", false)):
			continue
		var task: Dictionary = st.repair.tasks.get(task_id, {})
		if not bool(task.get("maintenance_fault", false)) or not _can_fix(me, task_id):
			continue
		var at: Variant = _task_spot(st, task_id)
		if at is Vector3:
			var room := String((RepairCatalog.ROOMS.get(String(task.get("room_id", "")), {}) as Dictionary).get("title", "the base"))
			faults.append(_entry(at as Vector3, "fault:" + task_id,
				"Alarm: the %s in the %s is broken. Follow the gold sparkles and fix it." % [String(task.get("title", "part")).to_lower(), room], &"warn"))
	if not faults.is_empty():
		return _nearest(faults, from)
	return {}


## (b) The schedule block's place when this player is late, or {}.
func schedule_target(st: ColonyState, me: CharacterState, from: Vector3) -> Dictionary:
	var where: Variant = _schedule_call(&"where_to_be", st, me)
	if not where is Vector3 or not (where as Vector3).is_finite():
		return {}
	var at := where as Vector3
	var late: Variant = _schedule_call(&"is_late", st, me)
	var is_late := bool(late) if late is bool else _far(from, at, LATE_M)
	if not is_late:
		return {}
	var block := String(CrewDay.current_block(st).get("name", "your schedule block"))
	return _entry(at, "schedule", "You are late for %s. Follow the gold sparkles there." % block, &"warn")


## (c) The first unfinished goal's place, or {}.
func goal_target(st: ColonyState, me: CharacterState, from: Vector3) -> Dictionary:
	var goals := ColonyGoals.all(st)
	for g: Dictionary in goals:
		if bool(g.get("done", false)):
			continue
		match String(g.get("kind", "")):
			"tapes_found":
				var tapes: Array[Dictionary] = []
				for id: String in st.stations:
					var rec: Dictionary = st.stations[id]
					if String(rec.get("kind", "")) != "cassette_anchor":
						continue
					if CassetteCatalog.collected(st, String(rec.get("cassette_id", id))):
						continue
					tapes.append(_entry(CharacterState._v3(rec.get("position", rec.get("prop_position", [0, 0, 0]))), "tape:" + id,
						"Follow the gold sparkles to the nearest tape.", &"good"))
				if not tapes.is_empty():
					return _nearest(tapes, from)
			"tapes_played":
				var deck: Variant = _anchors.get(CassetteCatalog.PLAYER_ID, GoalsBigPanel.player_spot())
				if deck is Vector3 and TutorialSystem.tapes_played(st) < TutorialSystem.tapes_found(st):
					return _entry(deck as Vector3, "tape_player", "Follow the gold sparkles to the tape player in the Command Room and play your tapes.", &"good")
			"fix":
				# Every broken part this crew member can fix, the nearest first; none left for them: change crew member.
				var mine: Array[Dictionary] = []
				for h: Dictionary in goals:
					if String(h.get("kind", "")) != "fix" or bool(h.get("done", false)) or not TutorialSystem.task_unlocked(st, String(h.get("task", ""))):
						continue
					var task := String(h.get("task", ""))
					if not _can_fix(me, task):
						continue
					var at: Variant = _task_spot(st, task)
					if at is Vector3:
						var title := String((RepairCatalog.TASKS.get(task, ["", "part"]) as Array)[1]).to_lower()
						mine.append(_entry(at as Vector3, "repair:" + task,
							"Follow the gold sparkles to the broken %s in the %s and fix it." % [title, String(h.get("room", "base"))], &"good"))
				if not mine.is_empty():
					return _nearest(mine, from)
				return _entry(services.config.hub_position, "crew_hub",
					"Another crew member must fix what is left. Follow the gold sparkles to the Med Bay and press %s to change crew member." % _key_name(&"crew", "C"), &"info")
	return {}


# ---------------------------------------------------------------- timed emergencies (the "Press H for help" pop-up)

## The timed emergencies running for this player now: [{"id": String, "fraction": 0..1 of its time gone}].
## The lethal exposure timer, a dust storm's arrival countdown (while outside), the COLONY OVER countdown and a solar
## storm's warning.
func timed_emergencies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if services == null or not services.has_game():
		return out
	var st := services.state()
	var me := services.local_character()
	if st == null or me == null:
		return out
	if me.exposure_active and me.lethal_exposure_seconds > 0.0:
		out.append({"id": "exposure", "fraction": clampf(me.lethal_exposure_seconds / maxf(0.05, services.config.exposure_lethal_seconds), 0.0, 1.0)})
	var w: Dictionary = st.weather
	if me.outside and String(w.get("phase", "calm")) == "warned":
		var warning: Dictionary = w.get("warning", {})
		var f := _fraction(st.sim_hours, float(warning.get("issued_at_hours", NAN)), float(warning.get("starts_at_hours", NAN)))
		if is_finite(f):
			out.append({"id": "dust_storm:" + String(warning.get("event_id", "")), "fraction": f})
	var over := colony_over_info(st)
	if not over.is_empty() and is_finite(float(over.fraction)):
		out.append({"id": "colony_over:" + String(over.store), "fraction": float(over.fraction)})
	var rad := radiation_info(st)
	if not rad.is_empty() and is_finite(float(rad.fraction)):
		out.append({"id": "radiation", "fraction": float(rad.fraction)})
	return out


## A solar storm warned or running: {"shelter": Vector3, "fraction": share of the warning gone (NAN when unknown or
## already arrived)}, or {}. Read defensively from state.radiation (scripts/survival/radiation_system.gd, another
## helper's): a "phase" / "state" word, or an "active" / "warned" flag; times in game hours or real seconds; an optional
## "shelter" spot (else the Med Bay crew hub).
func radiation_info(st: ColonyState) -> Dictionary:
	var r: Variant = st.get("radiation")
	if not r is Dictionary or (r as Dictionary).is_empty():
		return {}
	var d := r as Dictionary
	var storm: Dictionary = d.get("storm", d.get("warning", {})) if d.get("storm", d.get("warning", {})) is Dictionary else {}
	var phase := String(d.get("phase", d.get("state", storm.get("phase", ""))))
	var warned := phase in ["warned", "warning", "incoming"] or bool(d.get("warned", false))
	var running := phase in ["storm", "active", "peak", "running", "rising"] or bool(d.get("active", false))
	if not warned and not running:
		return {}
	var fraction := NAN
	if warned and not running:
		var now := st.sim_hours
		var a := _num([d, storm], ["warned_at_hours", "issued_at_hours", "warning_at_hours"])
		var b := _num([d, storm], ["starts_at_hours", "arrives_at_hours", "at_hours"])
		fraction = _fraction(now, a, b)
		if not is_finite(fraction):
			var left := _num([d, storm], ["warning_left_s", "seconds_left", "remaining_s"])
			var total := _num([d, storm], ["warning_s", "warning_total_s", "lead_s"])
			if is_finite(left) and is_finite(total) and total > 0.0:
				fraction = clampf(1.0 - left / total, 0.0, 1.0)
	var shelter: Variant = d.get("shelter", storm.get("shelter", null))
	var spot := services.config.hub_position
	if shelter is Vector3:
		spot = shelter as Vector3
	elif shelter is Array and (shelter as Array).size() >= 3:
		spot = CharacterState._v3(shelter)
	return {"shelter": spot, "fraction": fraction}


## The COLONY OVER countdown running: {"store": "oxygen" | "water" | "food" | "power" | ..., "fraction": share of the
## countdown gone (NAN when unknown)}, or {}. Read defensively from state.colony_over (scripts/survival/colony_over.gd,
## another helper's).
func colony_over_info(st: ColonyState) -> Dictionary:
	var c: Variant = st.get("colony_over")
	if not c is Dictionary or (c as Dictionary).is_empty():
		return {}
	var d := c as Dictionary
	if bool(d.get("over", d.get("ended", false))):
		return {}
	var counting := bool(d.get("active", d.get("counting", d.get("running", false))))
	if not counting:
		return {}
	var store := String(d.get("store", d.get("reason", d.get("cause", "")))).to_lower()
	for key: String in STORE_TASK:
		if store.contains(key):
			store = key
			break
	var total := _num([d], ["countdown_s", "total_s", "duration_s"])
	if not is_finite(total) or total <= 0.0:
		total = 300.0
	var fraction := NAN
	var left := _num([d], ["seconds_left", "remaining_s", "left_s"])
	var gone := _num([d], ["elapsed_s", "seconds_elapsed"])
	if is_finite(left):
		fraction = clampf(1.0 - left / total, 0.0, 1.0)
	elif is_finite(gone):
		fraction = clampf(gone / total, 0.0, 1.0)
	return {"store": store, "fraction": fraction}


# ---------------------------------------------------------------- helpers

func _entry(at: Vector3, why: String, say: String, kind: StringName) -> Dictionary:
	return {"at": at, "why": why, "say": say, "kind": kind}


## True when this crew member can fix a task: a general job or their own specialty.
func _can_fix(me: CharacterState, task_id: String) -> bool:
	if not RepairCatalog.TASKS.has(task_id):
		return false
	var spec := String((RepairCatalog.TASKS[task_id] as Array)[2])
	return spec == "general" or spec == String(me.specialty)


## The floor spot of a task's repair station (else the middle of its broken part, else its station record), or null.
func _task_spot(st: ColonyState, task_id: String) -> Variant:
	if task_id == "":
		return null
	var at: Variant = _anchors.get(RepairCatalog.anchor_id(task_id))
	if at is Vector3:
		return at
	at = GoalsBigPanel.part_spot(task_id)
	if at is Vector3:
		return at
	for id: String in st.stations:
		var rec: Dictionary = st.stations[id]
		if String(rec.get("kind", "")) == "repair_task" and String(rec.get("task_id", "")) == task_id:
			return CharacterState._v3(rec.get("position", [0, 0, 0]))
	return null


## The way in from outside: the open ground just past the exit tunnel's outer door (ReturnRoutes).
func _airlock() -> Vector3:
	return ReturnRoutes.ENTRANCES[0].position as Vector3


## The nearest choice by walking distance (the CHOOSE_BY_WALK nearest in a straight line are compared). While a line
## shows, the current choice is kept when it is still on the list, so the line does not flip between two parts.
func _nearest(choices: Array[Dictionary], from: Vector3) -> Dictionary:
	if active:
		for c: Dictionary in choices:
			if String(c.why) == String(pick.get("why", "")):
				return c
	if not from.is_finite():
		return choices[0]
	choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Vector3 = a.at
		var pb: Vector3 = b.at
		return from.distance_squared_to(pa) < from.distance_squared_to(pb))
	if _paths == null:
		_paths = WalkPaths.shared() as WalkPaths
	if _paths == null or not _paths.ok:
		return choices[0]
	var best := choices[0]
	var best_len := INF
	for i in mini(CHOOSE_BY_WALK, choices.size()):
		var length := _paths.walk_length(from, choices[i].at as Vector3)
		if length < best_len:
			best_len = length
			best = choices[i]
	return best


func _far(from: Vector3, to: Vector3, metres: float) -> bool:
	if not from.is_finite():
		return false
	return Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z)) > metres or absf(from.y - to.y) > 2.5


## Share of the way from a to b that `now` has gone, 0..1 (NAN when a or b is unknown).
static func _fraction(now: float, a: float, b: float) -> float:
	if not is_finite(a) or not is_finite(b) or b <= a:
		return NAN
	return clampf((now - a) / (b - a), 0.0, 1.0)


## The first number found under any of `keys` in any of the dictionaries, or NAN.
static func _num(dicts: Array, keys: Array) -> float:
	for d: Variant in dicts:
		if not d is Dictionary:
			continue
		for k: Variant in keys:
			var v: Variant = (d as Dictionary).get(k)
			if v is float or v is int:
				return float(v)
	return NAN


## Calls the schedule system's `method`(state, actor) when it exists: a live instance on the session first (its
## "schedule_system" or "schedule" member), else the script's static function. The actor goes in as the
## CharacterState, or its id when the method's second argument is typed String / StringName. null when absent.
func _schedule_call(method: StringName, st: ColonyState, me: CharacterState) -> Variant:
	var session: Object = services.session if services != null else null
	if session != null:
		for member: StringName in [&"schedule_system", &"schedule"]:
			var obj: Variant = session.get(member)
			if obj is Object and is_instance_valid(obj) and (obj as Object).has_method(method):
				return (obj as Object).callv(method, [st, _actor_arg((obj as Object).get_method_list(), method, me)])
	if not ResourceLoader.exists(SCHEDULE_PATH):
		return null
	var script := load(SCHEDULE_PATH) as Script
	if script == null:
		return null
	for m: Dictionary in script.get_script_method_list():
		if StringName(m.get("name", "")) != method:
			continue
		if (int(m.get("flags", 0)) & METHOD_FLAG_STATIC) == 0 or (m.get("args", []) as Array).size() < 2:
			return null
		return script.callv(method, [st, _actor_arg([m], method, me)])
	return null


static func _actor_arg(methods: Array, method: StringName, me: CharacterState) -> Variant:
	for m: Variant in methods:
		if not m is Dictionary or StringName((m as Dictionary).get("name", "")) != method:
			continue
		var args: Array = (m as Dictionary).get("args", [])
		if args.size() >= 2 and args[1] is Dictionary:
			match int((args[1] as Dictionary).get("type", TYPE_NIL)):
				TYPE_STRING:
					return String(me.id)
				TYPE_STRING_NAME:
					return me.id
		break
	return me


func _game() -> Node:
	if hud == null or not is_instance_valid(hud):
		return null
	var g: Variant = hud.get("game")
	return g as Node if g is Node and is_instance_valid(g) else null


## Where this machine's player is: the body (the seat while in the rover), else the replicated record.
func _player_position(me: CharacterState) -> Vector3:
	var game := _game()
	if game != null:
		var p: Variant = game.get("player")
		if p is Node3D and is_instance_valid(p) and (p as Node3D).is_inside_tree():
			return (p as Node3D).global_position
	return me.position


func _guide() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(&"guide_sparkles")


## One short Mission Control line. An older help line still on the card makes way for the new one.
func _say(text: String, kind: StringName) -> void:
	var mc: Variant = hud.get("mission_control") if hud != null and is_instance_valid(hud) else null
	if not mc is MissionControlCard:
		return
	var card := mc as MissionControlCard
	if _said_text != "" and _said_text != text and card.current_text() == _said_text:
		card.dismiss()
	card.say("Mission Control", text, kind, null, "Help (%s)" % _key_name(&"help", "H"))
	_said_text = text


## The key an action is on now (the player may have moved it), else `fallback`.
static func _key_name(action: StringName, fallback: String) -> String:
	if not InputMap.has_action(action):
		return fallback
	var words := PlayerInput.describe(action)
	return words if words != "" else fallback
