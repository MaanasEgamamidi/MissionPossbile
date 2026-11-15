extends RefCounted
## One build a day for the whole colony (upgrade paths plan §1.3, owner 2026-11-15). Host-authoritative rules; the
## actions are registered by AreaLevelActions (build_propose, build_vote, build_cancel, and upgrade_area, which is the
## same as build_propose for older callers). Loaded by path (no class_name):
##     const ColonyBuilds := preload("res://scripts/upgrades/colony_builds.gd")
##
## The rules:
##   * A build is proposed at the core spot of the track's section (AreaLevels.core_serves), only during the evening
##     Plan block (CrewDay.is_block(state, "plan"), 20:00-21:00), never while the tutorial is on (the base is not
##     fixed yet, and tutorial levels such as the comms fix are never bought), and at most ONE completed build per sol.
##   * The track must pay its next level: spare parts (state.parts) and ores (state.ores.stock), and meet its
##     requirements (another track's level). A fork level (night power V3) needs a choice: fuel_cell or reactor. Both
##     are allowed; the reactor is "not renewable". The choice is permanent (state.build.forks).
##   * The colony votes. Voters = every active crewmate a player controls (owner_peer != 0) who is within comms reach
##     (in_comms_reach: inside the base always; outside only with the comms track at V2 or more). The proposer votes
##     yes by proposing. The build passes when every voter in reach said yes (solo: the proposer alone = pass at once);
##     one "no" ends the vote. Player crewmates out of reach are listed in proposal.missed and are told
##     "You missed the vote: no radio contact." The vote ends without a build when the Plan block ends.
##   * When it passes, the level goes up by one, the materials are spent exactly once, the fork choice is saved, the
##     stored-number effects (battery capacity) are applied once, and a record goes into build.history and the ledger.
##
## state.build (plain JSON, saved and replicated with the colony; this file owns it):
##   last_sol   int   the sol of the last completed build (0 = none yet)
##   today      {track, level, choice, sol, by, by_name} of the last completed build, or {}
##   proposal   {track, level, choice, by, by_name, sol, station, votes: {actor_id: bool}, missed: [actor_id]} or {}
##   forks      {fork_id: choice}   permanent choices ("night_power": "fuel_cell" | "reactor")
##   last_vote  {track, level, result: "built" | "rejected" | "expired" | "cancelled" | "blocked", text, sol, missed}
##   history    [{sol, track, level, choice, by}] (newest last, at most HISTORY_MAX)

const CrewDay := preload("res://scripts/schedule/crew_day.gd")
const SuitRadio := preload("res://scripts/voice/suit_radio.gd")

const HISTORY_MAX := 30
## The Plan block's start hour, in words for the players.
const PLAN_TIME_WORDS := "20:00"
const MISSED_TEXT := "You missed the vote: no radio contact."
const DONE_TEXT := "Today's build is done — next build tomorrow at 20:00."
const TUTORIAL_TEXT := "Play one collected cassette in the Command Room to unlock builds."
## Alert ids (GameEvents.system_alert). Level ups keep "area_level_<track>" (MissionHud shows them as a pop-up).
const ALERT_VOTE := &"build_vote"
const LEVEL_ALERT_PREFIX := "area_level_"


# ---------------------------------------------------------------- state

## Makes sure state.build has every field (safe to call on any machine; only the host writes).
static func ensure(st: ColonyState) -> void:
	if st == null:
		return
	if not (st.build.get("forks") is Dictionary):
		st.build["forks"] = {}
	if not (st.build.get("today") is Dictionary):
		st.build["today"] = {}
	if not (st.build.get("proposal") is Dictionary):
		st.build["proposal"] = {}
	if not (st.build.get("history") is Array):
		st.build["history"] = []
	if not st.build.has("last_sol"):
		st.build["last_sol"] = 0


## The open vote, or {}.
static func proposal(st: ColonyState) -> Dictionary:
	if st == null:
		return {}
	var p: Variant = st.build.get("proposal", {})
	return (p as Dictionary) if p is Dictionary else {}


static func has_proposal(st: ColonyState) -> bool:
	return not proposal(st).is_empty()


## True when the colony already finished its build this sol.
static func built_today(st: ColonyState) -> bool:
	return st != null and int(st.build.get("last_sol", 0)) == CrewDay.sol_of(st)


## Today's finished build ({track, level, ...}) or {}.
static func today(st: ColonyState) -> Dictionary:
	if not built_today(st):
		return {}
	var t: Variant = st.build.get("today", {})
	return (t as Dictionary) if t is Dictionary else {}


## The result of the last vote ({} before any).
static func last_vote(st: ColonyState) -> Dictionary:
	if st == null:
		return {}
	var v: Variant = st.build.get("last_vote", {})
	return (v as Dictionary) if v is Dictionary else {}


# ---------------------------------------------------------------- comms reach and voters

## True when this crewmate can hear the colony's vote by radio. Inside the base: always (talk face to face and the
## base intercom). Outside: only when the suit radio has a signal (comms track "command" at V2 or more). The rule is
## the suit radio's own (scripts/voice/suit_radio.gd, authoritative); `zones` may be null (the replicated outside flag).
static func in_comms_reach(state: ColonyState, actor: CharacterState, zones: ColonyZones = null) -> bool:
	if state == null or actor == null or not actor.is_active():
		return false
	return SuitRadio.in_comms_reach(state, actor, zones)


## Active crewmates a player controls, sorted by id.
static func player_crew(st: ColonyState) -> Array[CharacterState]:
	var out: Array[CharacterState] = []
	if st == null:
		return out
	for c: CharacterState in st.active_characters():
		if c.owner_peer != 0:
			out.append(c)
	out.sort_custom(func(a: CharacterState, b: CharacterState) -> bool: return String(a.id) < String(b.id))
	return out


## Player crewmates who can vote now (within comms reach).
static func voters(st: ColonyState) -> Array[CharacterState]:
	var out: Array[CharacterState] = []
	for c: CharacterState in player_crew(st):
		if in_comms_reach(st, c):
			out.append(c)
	return out


## Ids of the player crewmates out of radio contact now.
static func missed_ids(st: ColonyState) -> Array:
	var out: Array = []
	for c: CharacterState in player_crew(st):
		if not in_comms_reach(st, c):
			out.append(String(c.id))
	return out


## True when this crewmate's vote is still missing in the open vote.
static func waiting_for(st: ColonyState, actor: CharacterState) -> bool:
	var p := proposal(st)
	if p.is_empty() or actor == null:
		return false
	return not (p.get("votes", {}) as Dictionary).has(String(actor.id)) and in_comms_reach(st, actor)


## Names of the voters who have not voted yet.
static func waiting_names(st: ColonyState) -> PackedStringArray:
	var out := PackedStringArray()
	var p := proposal(st)
	if p.is_empty():
		return out
	var votes: Dictionary = p.get("votes", {})
	for c: CharacterState in voters(st):
		if not votes.has(String(c.id)):
			out.append(c.display_name)
	return out


# ---------------------------------------------------------------- the day's rules

## Planning is available after the first playback while the tutorial clock is held.
## The normal Plan block takes over once the tutorial is complete.
static func planning_open(st: ColonyState) -> bool:
	return (TutorialSystem.tutorial_active(st) and TutorialSystem.specialty_features_unlocked(st)) or CrewDay.is_block(st, "plan")


## What the day's rules say against building `track` now, as [{"kind", "text"}] (empty = the day allows it).
static func day_blockers(st: ColonyState, track: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if st == null:
		return out
	if not TutorialSystem.specialty_features_unlocked(st):
		out.append({"kind": "tutorial", "text": TUTORIAL_TEXT})
		return out
	if built_today(st):
		out.append({"kind": "done_today", "text": DONE_TEXT})
		return out
	if not planning_open(st):
		var h := CrewDay.hours_until(st, "plan")
		var when := "in about %d hour%s" % [maxi(1, roundi(h)), "" if roundi(h) == 1 else "s"] if h < INF else "later"
		out.append({"kind": "not_plan", "text": "Builds are chosen in the Plan block at %s (%s)." % [PLAN_TIME_WORDS, when]})
	var p := proposal(st)
	if not p.is_empty() and String(p.get("track", "")) != track:
		out.append({"kind": "vote_open", "text": "A vote is already open on %s. Vote on it first." % proposal_words(p)})
	return out


## Everything that stops building the next level of `track` now: the track's own (materials, max, requirements)
## first, then the day's rules.
static func blockers(st: ColonyState, track: String) -> Array[Dictionary]:
	var out := AreaLevels.blockers(st, track)
	if not out.is_empty() and String(out[0].get("kind", "")) in ["unknown", "derived", "max"]:
		return out
	out.append_array(day_blockers(st, track))
	return out


## "Night power V3 (Small fission reactor)".
static func proposal_words(p: Dictionary) -> String:
	var track := String(p.get("track", ""))
	var text := "%s V%d" % [AreaLevels.track_name(track), int(p.get("level", 0))]
	var choice := String(p.get("choice", ""))
	if choice != "":
		var c := AreaLevels.fork_choice_def(String(AreaLevels.track(track).get("fork", "")), choice)
		if not c.is_empty():
			text += " (%s)" % String(c.get("name", choice))
	return text


## Checks a fork choice for the next level of a track: "" when fine, else the refusal words.
static func choice_problem(st: ColonyState, track: String, choice: String) -> String:
	var next := AreaLevels.level(st, track) + 1
	var f := AreaLevels.fork_at(track, next)
	if f.is_empty():
		return ""
	if choice == "":
		var names := PackedStringArray()
		for c: Dictionary in f.get("choices", []):
			names.append(String(c.get("name", c.get("id", ""))).to_lower())
		return "Pick one first: %s." % " or ".join(names)
	if AreaLevels.fork_choice_def(String(f.id), choice).is_empty():
		return "That choice does not exist."
	return ""


# ---------------------------------------------------------------- host: propose, vote, cancel, tick

## Host: opens the vote (the checks passed). The proposer's yes is counted; solo play passes at once.
static func propose(session: SessionService, st: ColonyState, actor: CharacterState, track: String, choice: String, station_id: String) -> Dictionary:
	ensure(st)
	var next := AreaLevels.level(st, track) + 1
	var f := AreaLevels.fork_at(track, next)
	var p := {
		"track": track, "level": next, "choice": choice if not f.is_empty() else "",
		"by": String(actor.id), "by_name": actor.display_name, "sol": CrewDay.sol_of(st), "station": station_id,
		"votes": {String(actor.id): true}, "missed": missed_ids(st),
	}
	st.build["proposal"] = p
	var changes := evaluate(session, st)
	if String(changes.get("status", "")) == "open":
		var text := "%s wants to build %s. Everyone in radio contact: vote now (Y = yes, X = no)." % [actor.display_name, proposal_words(p)]
		_alert(session, ALERT_VOTE, &"info", text)
		changes["text"] = "Vote open on %s. Waiting for: %s." % [proposal_words(p), ", ".join(waiting_names(st))]
	changes["action"] = "build_propose"
	return changes


## Host: one crewmate's vote (the checks passed).
static func vote(session: SessionService, st: ColonyState, actor: CharacterState, yes: bool) -> Dictionary:
	ensure(st)
	var p := proposal(st)
	var votes: Dictionary = p.get("votes", {})
	votes[String(actor.id)] = yes
	p["votes"] = votes
	if not yes:
		var text := "No build yet: %s voted no on %s. Talk it over and try again." % [actor.display_name, proposal_words(p)]
		_close(st, p, "rejected", text)
		_alert(session, ALERT_VOTE, &"warn", text)
		return {"action": "build_vote", "status": "rejected", "track": String(p.get("track", "")), "text": text}
	var changes := evaluate(session, st)
	changes["action"] = "build_vote"
	if String(changes.get("status", "")) == "open":
		changes["text"] = "You voted yes. Waiting for: %s." % ", ".join(waiting_names(st))
	return changes


## Host: the proposer takes the proposal back.
static func cancel(session: SessionService, st: ColonyState, actor: CharacterState) -> Dictionary:
	var p := proposal(st)
	var text := "%s took back the vote on %s." % [actor.display_name, proposal_words(p)]
	_close(st, p, "cancelled", text)
	_alert(session, ALERT_VOTE, &"info", text)
	return {"action": "build_cancel", "status": "cancelled", "text": text}


## Host: looks at the open vote again: builds when every voter in reach said yes, keeps it open otherwise.
## Returns {"status": "open" | "built" | "blocked" | "expired" | "none", ...}.
static func evaluate(session: SessionService, st: ColonyState) -> Dictionary:
	var p := proposal(st)
	if p.is_empty():
		return {"status": "none"}
	p["missed"] = missed_ids(st)
	var track := String(p.get("track", ""))
	var vs := voters(st)
	if vs.is_empty():
		var text := "The vote on %s ended: nobody is in radio contact." % proposal_words(p)
		_close(st, p, "expired", text)
		_alert(session, ALERT_VOTE, &"warn", text)
		return {"status": "expired", "track": track, "text": text}
	var votes: Dictionary = p.get("votes", {})
	for c: CharacterState in vs:
		if not bool(votes.get(String(c.id), false)):
			return {"status": "open", "track": track, "level": int(p.get("level", 0)), "waiting": waiting_names(st)}
	# Everyone in reach said yes. The colony may have spent parts or ores since the vote opened: check again.
	var lacking := AreaLevels.blockers(st, track)
	if AreaLevels.level(st, track) + 1 != int(p.get("level", 0)):
		lacking.append({"kind": "changed", "text": "That level is already built."})
	if not lacking.is_empty():
		var text := "Everyone said yes, but %s can't be built: %s" % [proposal_words(p), String(lacking[0].get("text", ""))]
		_close(st, p, "blocked", text)
		_alert(session, ALERT_VOTE, &"warn", text)
		return {"status": "blocked", "track": track, "text": text}
	var missed: Array = p.get("missed", [])
	var changes := complete(session, st, track, String(p.get("choice", "")), String(p.get("by", "")), String(p.get("by_name", "")))
	_close(st, p, "built", String(changes.get("text", "")))
	changes["status"] = "built"
	changes["missed"] = missed
	return changes


## Host: applies a passed build exactly once and returns its changes.
static func complete(session: SessionService, st: ColonyState, track: String, choice: String, by: String, by_name: String) -> Dictionary:
	ensure(st)
	var before := AreaLevels.level(st, track)
	var after := before + 1
	var cost := AreaLevels.cost_of(track, after)
	var parts := int(cost.get("parts", 0))
	var ores: Dictionary = cost.get("ores", {})
	st.parts -= parts
	var stock: Dictionary = st.ores.get("stock", {}) if st.ores.get("stock") is Dictionary else {}
	var ore_total := 0
	for ore: String in ores:
		var n := int(ores[ore])
		stock[ore] = maxi(0, int(stock.get(ore, 0)) - n)
		ore_total += n
	st.ores["stock"] = stock
	st.levels[track] = after
	# A better lab can identify ore samples that were waiting (scripts/science/ore_catalog.gd).
	if track == "lab":
		var ore_catalog: Variant = load("res://scripts/science/ore_catalog.gd")
		if ore_catalog != null:
			ore_catalog.settle(st)
	var f := AreaLevels.fork_at(track, after)
	if not f.is_empty() and choice != "":
		var forks: Dictionary = st.build.get("forks", {})
		forks[String(f.id)] = choice
		st.build["forks"] = forks
	st.ledger["parts_used_area_levels"] = float(st.ledger.get("parts_used_area_levels", 0.0)) + float(parts)
	st.ledger["ores_used_area_levels"] = float(st.ledger.get("ores_used_area_levels", 0.0)) + float(ore_total)
	# Stored-number effects, applied once at the level change.
	var changes := {"track": track, "level_before": before, "level": after, "parts_used": parts, "ores_used": ores.duplicate(), "choice": choice}
	if track == "energy":
		var f0 := float(AreaLevels.effect_at(track, "battery_capacity_factor", before, 1.0))
		var f1 := float(AreaLevels.effect_at(track, "battery_capacity_factor", after, 1.0))
		var cap_before := float(st.capacities.get(&"battery_kwh", 0.0))
		if f0 > 0.0 and not is_equal_approx(f0, f1):
			st.capacities[&"battery_kwh"] = cap_before * f1 / f0
		changes["battery_capacity_before_kwh"] = cap_before
		changes["battery_capacity_after_kwh"] = float(st.capacities.get(&"battery_kwh", 0.0))
	var sol := CrewDay.sol_of(st)
	st.build["last_sol"] = sol
	st.build["today"] = {"track": track, "level": after, "choice": choice, "sol": sol, "by": by, "by_name": by_name}
	var history: Array = st.build.get("history", [])
	history.append({"sol": sol, "track": track, "level": after, "choice": choice, "by": by})
	while history.size() > HISTORY_MAX:
		history.pop_front()
	st.build["history"] = history
	var text := "%s upgraded to %s." % [AreaLevels.track_name(track), AreaLevels.stage_text_for(st, track, after)]
	changes["text"] = text
	_alert(session, StringName(LEVEL_ALERT_PREFIX + track), &"info", text)
	return changes


## Host, every simulation tick (cheap while no vote is open): ends a vote when the Plan block or the sol is over, and
## lets it pass when the last missing voter went out of radio contact or left the game.
static func tick(session: SessionService) -> void:
	if session == null or session.state == null:
		return
	var st := session.state
	var p := proposal(st)
	if p.is_empty():
		return
	if int(p.get("sol", 0)) != CrewDay.sol_of(st) or not planning_open(st):
		var text := "The Plan block is over: no build today. Try again tomorrow at %s." % PLAN_TIME_WORDS
		_close(st, p, "expired", text)
		_alert(session, ALERT_VOTE, &"warn", text)
		return
	evaluate(session, st)


static func _close(st: ColonyState, p: Dictionary, result: String, text: String) -> void:
	st.build["last_vote"] = {"track": String(p.get("track", "")), "level": int(p.get("level", 0)), "choice": String(p.get("choice", "")),
		"result": result, "text": text, "sol": CrewDay.sol_of(st), "missed": (p.get("missed", []) as Array).duplicate()}
	st.build["proposal"] = {}


static func _alert(session: SessionService, id: StringName, level: StringName, text: String) -> void:
	if session != null and session.events != null:
		session.events.system_alert.emit(id, level, text)


# ---------------------------------------------------------------- words for the UI

## The vote line for a player ("Vote open on Day power V3: waiting for Ana.", "You missed the vote: no radio contact.").
static func vote_text_for(st: ColonyState, me: CharacterState) -> String:
	var p := proposal(st)
	if p.is_empty():
		var lv := last_vote(st)
		if not lv.is_empty() and int(lv.get("sol", 0)) == CrewDay.sol_of(st):
			if me != null and (lv.get("missed", []) as Array).has(String(me.id)):
				return MISSED_TEXT
			return String(lv.get("text", ""))
		return ""
	if me != null and me.owner_peer != 0 and not in_comms_reach(st, me):
		return MISSED_TEXT
	var names := waiting_names(st)
	var line := "Vote open on %s (by %s)." % [proposal_words(p), String(p.get("by_name", "a crewmate"))]
	if not names.is_empty():
		line += " Waiting for: %s." % ", ".join(names)
	return line
