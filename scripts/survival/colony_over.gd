extends RefCounted
## COLONY OVER (upgrade paths plan §1.5, owner decisions 2026-11-15: a 5-minute countdown). HOST ONLY: the host calls
## step() once per simulation tick; clients read the replicated state.colony_over. Loaded by path (no class_name):
##     const ColonyOver := preload("res://scripts/survival/colony_over.gd")
##
## Rules
##   * Life stores: oxygen (oxygen_kg), water (water_l), food (food_meals) and power. Power counts as empty only when
##     the battery is empty AND nothing else makes power right now (solar_kw and served_kw both ~0): with the Sun up
##     the colony still has power.
##   * Warnings at 25 % and 10 % of the store's capacity, once each, armed again when the store is back above the
##     level + REARM_MARGIN. A store that is already low the first time it is seen (a new colony starts with 24 % food)
##     is noted silently, so a new game does not open with a warning.
##   * When a store reaches zero a COUNTDOWN_SECONDS = 300 (5 minutes) REAL-TIME countdown starts. Its start is kept in
##     SolClock.real_seconds (simulated real seconds), so pausing stops it, and a changed sol length does not change it.
##     Getting the store above zero cancels it. Each store has its own countdown; the HUD shows the one that ends first.
##   * All crew isolated (RadiationSystem.is_isolated for every crewmate) runs the same countdown with reason "crew";
##     it is cancelled as soon as one crewmate comes out of isolation. (The game has no "lost crew" yet: dead crew
##     wake up in the Med Bay. A lost-crew rule can join the "crew" reason later.)
##   * When a countdown ends the colony is over: state.colony_over.over = true with the reason, the words, the sol and
##     what would have helped. The host must stop the simulation and the actions then (is_over()); this step does
##     nothing more after that.
##   * During the tutorial no countdown starts (SAFE_DURING_TUTORIAL): the base is broken on purpose there.
##   * A save loaded with a countdown running gets at least GRACE_AFTER_LOAD_SECONDS (60 s) left.
##
## state.colony_over (plain JSON, saved and replicated)
##   "version"     1
##   "over"        bool; when true also: "reason" ("oxygen" | "water" | "food" | "power" | "crew"), "text" ("The colony
##                 ran out of oxygen."), "sol" (int, 1 = the first sol), "hint" (what would have helped), "at_hours"
##   "counting"    bool: a 5-minute countdown is running (shared key: the H help and schedule helpers read it)
##   "store"       the store of the countdown that ends first: "oxygen_kg" | "water_l" | "food_meals" | "battery_kwh",
##                 "" for the all-crew-isolated countdown and when nothing counts down
##   "seconds_left"  real seconds left on that countdown (0 when not counting)
##   "countdown_s" 300.0 (COUNTDOWN_SECONDS)
##   "countdowns"  reason ->{"started_real_s": SolClock.real_seconds at the start, "left_s": real seconds left,
##                 "last_minute": bool (the 1-minute call was made)}
##   "countdown"   the countdown that ends first, for the HUD, or {}: {"reason", "left_s", "name", "action"}
##   "warned"      reason -> [0.25, 0.1 ...] warning levels already given
##   "seen"        reason -> true once the store was looked at (for the silent first look)

const RadiationSystem := preload("res://scripts/survival/radiation_system.gd")

## Owner rule: 5 real minutes.
const COUNTDOWN_SECONDS := 300.0
const GRACE_AFTER_LOAD_SECONDS := 60.0
const LAST_MINUTE_SECONDS := 60.0
## A store at or below this is empty.
const EMPTY_EPS := 0.001
## Power: below this many kW the colony makes no power.
const NO_POWER_KW := 0.05
const WARN_SHARES: Array[float] = [0.25, 0.10]
const REARM_MARGIN := 0.02
const SAFE_DURING_TUTORIAL := true

const ALERT_PREFIX := "colony_over_"

## Reasons: the store, words for the screens and what would have helped.
const REASONS: Dictionary = {
	"oxygen": {"key": &"oxygen_kg", "name": "Oxygen", "action": "make oxygen now", "text": "The colony ran out of oxygen.",
		"hint": "Keep the oxygen plant (electrolyser) running and powered, fix the CO₂ scrubber early, and upgrade Life support (Agriculture) for Sabatier and oxygen from Mars air."},
	"water": {"key": &"water_l", "name": "Water", "action": "get water flowing now", "text": "The colony ran out of water.",
		"hint": "Keep the water recycler working, ration water, and upgrade the Food track's water steps: the urine processor, the brine processor and, later, the ice drill."},
	"food": {"key": &"food_meals", "name": "Food", "action": "find or grow food now", "text": "The colony ran out of food.",
		"hint": "Grow food in the greenhouse early, eat packed meals in order, and upgrade the Food track to a staple farm. Remember: grow lights need power, so food needs energy too."},
	"power": {"key": &"battery_kwh", "name": "Power", "action": "get power back now", "text": "The colony ran out of power.",
		"hint": "Clean the solar panels, switch off what you do not need at night, keep the battery above a reserve before dark and before dust storms, and upgrade Night power (a second battery bank, fuel cells or a reactor)."},
	"crew": {"key": &"", "name": "Crew", "action": "get a crewmate out of isolation", "text": "No crewmate could work: everyone was sick in isolation.",
		"hint": "Keep the crew inside during solar storms and use the storm shelter, share the outside work, build radiation shielding (Health: Protection) and medical care (shorter isolation)."},
}
const ORDER: Array[String] = ["oxygen", "water", "food", "power", "crew"]

static var _bound := 0


# ---------------------------------------------------------------- the host step

static func step(session: SessionService, _delta_hours: float) -> void:
	if session == null or session.state == null or session.clock == null or not session.authoritative:
		return
	var state := session.state
	var o := ensure(state)
	if bool(o.over):
		return
	var now := session.clock.real_seconds
	var countdowns: Dictionary = o.countdowns
	if state.get_instance_id() != _bound:
		_bound = state.get_instance_id()
		# a loaded game: never less than a minute left on a running countdown
		for reason: String in countdowns:
			var cd: Dictionary = countdowns[reason]
			if COUNTDOWN_SECONDS - (now - float(cd.started_real_s)) < GRACE_AFTER_LOAD_SECONDS:
				cd.started_real_s = now - (COUNTDOWN_SECONDS - GRACE_AFTER_LOAD_SECONDS)
	var safe := SAFE_DURING_TUTORIAL and not TutorialSystem.is_tutorial_done(state)
	for reason: String in ORDER:
		if reason != "crew":
			_warnings(session, o, reason)
		var empty := is_empty(state, reason)
		if empty and not safe:
			if not countdowns.has(reason):
				countdowns[reason] = {"started_real_s": now, "left_s": COUNTDOWN_SECONDS, "last_minute": false}
				_say(session, reason, &"urgent", "%s! The colony has 5 minutes to %s, or it is over." % [empty_words(reason), String(REASONS[reason].action)])
		elif countdowns.has(reason):
			countdowns.erase(reason)
			if not safe:
				_say(session, reason, &"info", "Well done: %s. The countdown has stopped." % back_words(reason))
	var soonest := {}
	for reason: String in ORDER:
		if not countdowns.has(reason):
			continue
		var cd: Dictionary = countdowns[reason]
		var left := maxf(0.0, COUNTDOWN_SECONDS - (now - float(cd.started_real_s)))
		cd.left_s = left
		if left <= LAST_MINUTE_SECONDS and not bool(cd.get("last_minute", false)) and left > 0.0:
			cd.last_minute = true
			_say(session, reason, &"urgent", "One minute left! %s: %s, or the colony is over." % [String(REASONS[reason].name), String(REASONS[reason].action)])
		if left <= 0.0:
			_end(session, o, reason)
			return
		if soonest.is_empty() or left < float(soonest.left_s):
			soonest = {"reason": reason, "left_s": left, "name": String(REASONS[reason].name), "action": String(REASONS[reason].action)}
	o.countdown = soonest
	_publish(o)


## Writes the shared keys other helpers read: counting, store, seconds_left, countdown_s.
static func _publish(o: Dictionary) -> void:
	var cd: Dictionary = o.get("countdown", {})
	o.countdown_s = COUNTDOWN_SECONDS
	o.counting = not cd.is_empty() and not bool(o.get("over", false))
	o.store = String((REASONS[String(cd.reason)] as Dictionary).key) if o.counting else ""
	o.seconds_left = float(cd.left_s) if o.counting else 0.0


## state.colony_over with every field present.
static func ensure(state: ColonyState) -> Dictionary:
	var o := state.colony_over
	if not o.has("version"):
		o.version = 1
		o.over = false
		o.counting = false
		o.store = ""
		o.seconds_left = 0.0
		o.countdown_s = COUNTDOWN_SECONDS
	for k: String in ["countdowns", "countdown", "warned", "seen"]:
		if not (o.get(k) is Dictionary):
			o[k] = {}
	if not o.has("over"):
		o.over = false
	return o


static func _end(session: SessionService, o: Dictionary, reason: String) -> void:
	var state := session.state
	o.over = true
	o.reason = reason
	o.text = String(REASONS[reason].text)
	o.sol = int(floor(maxf(state.sim_hours, 0.0) / GameConfig.SOL_HOURS)) + 1
	o.hint = String(REASONS[reason].hint)
	o.at_hours = state.sim_hours
	o.countdown = {}
	_publish(o)
	_say(session, reason, &"urgent", "COLONY OVER. %s" % String(o.text))


static func _warnings(session: SessionService, o: Dictionary, reason: String) -> void:
	var state := session.state
	var key: StringName = REASONS[reason].key
	var cap := float(state.capacities.get(key, 0.0))
	if cap <= 0.0:
		return
	var share := state.store(key) / cap
	var warned: Dictionary = o.warned
	var list: Array = warned.get(reason, [])
	warned[reason] = list
	var seen: Dictionary = o.seen
	var first := not bool(seen.get(reason, false))
	seen[reason] = true
	for level: float in WARN_SHARES:
		if share > level + REARM_MARGIN and list.has(level):
			list.erase(level)
	for level: float in WARN_SHARES:
		if share <= level and not list.has(level):
			list.append(level)
			if first:
				continue
			var what := "the battery" if reason == "power" else String(REASONS[reason].name).to_lower()
			var act := String(REASONS[reason].action)
			act = act.substr(0, 1).to_upper() + act.substr(1)
			if level <= WARN_SHARES[WARN_SHARES.size() - 1]:
				_say(session, reason, &"urgent", "Mission Control: %s is down to %d %% of capacity. If it runs out, the colony has only 5 minutes. %s." % [what, roundi(level * 100.0), act])
			else:
				_say(session, reason, &"warn", "Mission Control: %s is down to a quarter (%d %%). Plan now so it does not run out." % [what, roundi(level * 100.0)])


static func _say(session: SessionService, reason: String, level: StringName, text: String) -> void:
	if session.events != null:
		session.events.system_alert.emit(StringName(ALERT_PREFIX + reason), level, text)


# ---------------------------------------------------------------- questions

## True once the colony is over: the host stops the simulation and the actions.
static func is_over(state: ColonyState) -> bool:
	return state != null and bool(state.colony_over.get("over", false))


## True when the reason's store is empty now (or, for "crew", every crewmate is isolated).
static func is_empty(state: ColonyState, reason: String) -> bool:
	match reason:
		"crew":
			if state.characters.is_empty():
				return false
			for c: CharacterState in state.characters.values():
				if not RadiationSystem.is_isolated(c):
					return false
			return true
		"power":
			return state.store(&"battery_kwh") <= EMPTY_EPS and maxf(state.solar_kw, state.served_kw) <= NO_POWER_KW
		_:
			if not REASONS.has(reason):
				return false
			return state.store(REASONS[reason].key) <= EMPTY_EPS


## The countdown that ends first, or {}: {"reason", "left_s", "name", "action"} (replicated; clients read it too).
static func countdown_now(state: ColonyState) -> Dictionary:
	if state == null or is_over(state):
		return {}
	var c: Variant = state.colony_over.get("countdown", {})
	return c if c is Dictionary else {}


## "Oxygen is empty", "Every crewmate is in isolation".
static func empty_words(reason: String) -> String:
	if reason == "crew":
		return "Every crewmate is in isolation"
	if reason == "power":
		return "The battery is empty and nothing is making power"
	return "%s is empty" % String(REASONS.get(reason, {}).get("name", reason))


static func back_words(reason: String) -> String:
	match reason:
		"crew":
			return "a crewmate is out of isolation"
		"power":
			return "the colony has power again"
	return "%s is back above zero" % String(REASONS.get(reason, {}).get("name", reason)).to_lower()


## "4:32" for 272 seconds.
static func clock_text(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [floori(s / 60.0), s % 60]
