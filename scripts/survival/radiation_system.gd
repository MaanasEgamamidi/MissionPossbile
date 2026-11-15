extends RefCounted
## Radiation: each crewmate's dose, solar storms (solar particle events), the storm shelter and isolation at the
## limit (upgrade paths plan §5.2 and §10, owner decisions 2026-11-15). HOST ONLY: the host calls step() once per
## simulation tick; clients only read the replicated state (state.radiation, CharacterState.dose_msv / isolation).
## Loaded by path (no class_name):
##     const RadiationSystem := preload("res://scripts/survival/radiation_system.gd")
##
## ---- The dose model (numbers and where they come from)
##   * Real science: Curiosity's RAD measured about 0.67 mSv per sol on the surface of Mars (Hassler et al. 2014,
##     plan sources 43-44). Outside on the ground and inside a bare habitat are about the same in real life.
##   * GAMEPLAY SCALING (not NASA data): at the real rate a crewmate would need ~900 sols (about 300 hours of play) to
##     reach NASA's 600 mSv career limit, so the game speeds dose up by GAME_DOSE_FACTOR = 20 (game mSv = 20 x real
##     mSv). It also makes being outside OUTDOOR_FACTOR = 3 times worse than inside a bare base, so where you stand
##     matters. Both are said in the science text (data/radiation.json, "dose_game_scale").
##       inside the base   0.67 / 24.66 x 20 x radiation_indoor_factor   = 0.543 mSv per game hour at V1 (13.4 per sol)
##       outside           0.67 / 24.66 x 20 x 3                          = 1.630 mSv per game hour (40.2 per sol)
##       sealed rover cabin  like a bare base (factor 1; the base's shielding does not ride along)
##     So a crewmate who never goes out reaches 600 mSv in about 45 sols without shielding and about 107 sols at
##     radiation_indoor_factor 0.42. Every crewmate is dosed, also the ones nobody plays (they wait in the Med Bay).
##   * Solar storms add a big extra dose (below). NASA's 600 mSv limit (plan source 45) is the isolation limit.
##
## ---- Solar storms (solar particle events)
##   * Real science: 1-3 big ones per Mars year near solar maximum; 15-60 minutes of warning; the crew may need to
##     shelter for hours to days. The biggest seen at Mars (20 May 2024) gave Curiosity ~8.1 mGy at once.
##   * GAME TRANSFORMATION: like the dust-storm gaps of WeatherSystem, the gaps are ACCELERATED: one storm every
##     STORM_GAP_SOLS_MIN..MAX = 5..12 sols (real: ~220-670 sols; about 40x faster). Drawn from the colony seed, so
##     the same seed gives the same storms. The first one comes 2..5 sols after the tutorial is done.
##   * Warning: 15..60 game MINUTES (the real number, played in game time) x command `storm_warning_factor`
##     (1, 1.5, 2, 2.5, 3). At the default 20-minute sol, 15 game minutes is about 12 real seconds: get to the shelter
##     fast, or upgrade comms for a longer warning.
##   * Lasts 1..3 sols. The particle flux rises over RISE_HOURS (2 game hours), then fades (exponential, 1/3 of the
##     rest per e-fold). An unsheltered crewmate outside gets the whole event dose: 4..12 real mSv on the surface
##     (the first storm at most 6) x GAME_DOSE_FACTOR = 80..240 game mSv.
##   * Where you are during a storm (factor on the storm dose):
##       outside                       1
##       inside the base               protection `radiation_indoor_factor`
##       in the storm shelter          min(indoor factor, protection `storm_shelter_factor`) when protection
##                                     `storm_shelter` is true. The shelter area is the Med Bay for now (SHELTER_ZONE).
##       sealed rover cabin            min(ROVER_CABIN_STORM_FACTOR = 0.25, storm_shelter_factor), when
##                                     RoverModel.cabin_sheltered(state, actor) says so (like NASA's SEV).
##   * Mission Control (events.system_alert): the warning (urgent), the start (warn), the end (info).
##
## ---- Dose warnings and isolation
##   * Warnings at 400 and 500 mSv per crewmate (once each).
##   * At 600 mSv (owner: "get sick and go to isolation"): health drops to at most 50, the crewmate is moved to an
##     isolation bed in the Med Bay (their own collision-probed Med Bay spot, CharacterState.hub_spot from
##     GameConfig.crew_hub_offsets), and CharacterState.isolation = {"since_hours", "until_hours"} for
##     ISOLATION_HOURS (48) x health `isolation_hours_factor` game hours. While isolated they cannot go outside
##     (the host moves them back to the bed if they do) or do work (is_isolated() for the schedule and actions).
##     The move is sent as events.character_recovered(id, {"isolation": true, ...}) so every machine takes the new
##     pose (the GameMain handler should show isolation words for it, not the respawn cost).
##   * Afterwards: indoor work only (indoor_only()) for good, because the dose never resets. More dose outside sends
##     them back into isolation at every further REISOLATION_STEP_MSV (700, 800 ...).
##   * Every crewmate isolated -> COLONY OVER (scripts/survival/colony_over.gd reads is_isolated()).
##
## ---- state.radiation (plain JSON, saved and replicated)
##   "version"        1
##   "rng_seed", "rng_state"   the storm stream (strings: 64-bit)
##   "generated"      storms made so far (int)
##   "armed_at_hours" game hour the tutorial was first seen done (-1 = not yet)
##   "phase"          "calm" | "warned" | "active"
##   "active"         bool: true while a storm runs
##   "warned_at_hours"  game hour the warning of the warned or running storm came (-1 when calm)
##   "starts_at_hours"  game hour the warned or running storm starts (-1 when calm)
##   "ends_at_hours"    game hour the warned or running storm ends (-1 when calm)
##   "shelter"        [x, y, z]: the storm shelter spot (GameConfig.hub_position, the Med Bay for now)
##   "next"           the coming storm, or {}: {"id", "index", "at_hours", "duration_hours", "warn_minutes",
##                    "dose_real_msv", "peak_msv_per_hour" (game mSv per game hour, unsheltered), "rise_hours",
##                    "fade_hours", "warned" (bool), "warned_at_hours", "warn_hours"}
##   "storm"          the running storm (same fields), or {}
##   "history"        the last HISTORY_LENGTH storms: {"id", "at_hours", "duration_hours", "dose_real_msv"}
##   "storm_share"    0..1, the storm flux now as a share of its peak (0 when calm)
##   "crew"           id -> {"place": "outside"|"rover"|"shelter"|"inside", "rate_msv_h": game mSv per game hour now,
##                    "warned": [400, 500 ...], "next_isolation_msv", "isolations" (int)}
##   "colony_dose_msv"  every crewmate's dose added up since the game began (bookkeeping)

const SOL := GameConfig.SOL_HOURS
const TRACK_PROTECTION := "protection"
const TRACK_HEALTH := "health"
const TRACK_COMMAND := "command"

## Real science: Curiosity RAD on the surface, mSv per sol (Hassler et al. 2014).
const CURIOSITY_MSV_PER_SOL := 0.67
## Gameplay scaling (not NASA data): game mSv per real mSv, so the 600 mSv limit is reachable in a game.
const GAME_DOSE_FACTOR := 20.0
## Gameplay choice (not NASA data): outside is this many times worse than inside a bare base.
const OUTDOOR_FACTOR := 3.0
## NASA career limit (OCHMO brief): isolation at this dose.
const LIMIT_MSV := 600.0
const WARN_MSV: Array[float] = [400.0, 500.0]
## After an isolation, more dose sends the crewmate back at every further step.
const REISOLATION_STEP_MSV := 100.0
## Game hours in isolation at Medical care V1 (x isolation_hours_factor).
const ISOLATION_HOURS := 48.0
## Health of a crewmate who goes into isolation (at most).
const ISOLATION_HEALTH := 50.0
## The storm shelter area: the Med Bay for now (a constant to move later).
const SHELTER_ZONE := "Med Bay"
const SHELTER_NAME := "Med Bay"
## A sealed rover cabin blocks at least this share of a solar storm (like NASA's SEV).
const ROVER_CABIN_STORM_FACTOR := 0.25
## True: the crewmates nobody plays are dosed too (they wait inside the Med Bay).
const DOSE_PARKED_CREW := true

## Game transformation (accelerated): sols between storms, and before the first one after the tutorial.
const STORM_GAP_SOLS_MIN := 5.0
const STORM_GAP_SOLS_MAX := 12.0
const FIRST_GAP_SOLS_MIN := 2.0
const FIRST_GAP_SOLS_MAX := 5.0
## Real science: warning time in minutes (played as game minutes, x storm_warning_factor).
const WARNING_MINUTES_MIN := 15.0
const WARNING_MINUTES_MAX := 60.0
## Real science: how long a storm keeps the crew sheltered, in sols.
const STORM_SOLS_MIN := 1.0
const STORM_SOLS_MAX := 3.0
## Real-science scale (est.): surface dose of a big storm for someone unsheltered, real mSv (x GAME_DOSE_FACTOR).
const STORM_DOSE_REAL_MSV_MIN := 4.0
const STORM_DOSE_REAL_MSV_MAX := 12.0
const FIRST_STORM_DOSE_REAL_MSV_MAX := 6.0
## Game hours the flux takes to reach its peak.
const RISE_HOURS := 2.0
## Below this share of the peak the worst of the storm is over (the banner says so).
const FADED_SHARE := 0.15
const HISTORY_LENGTH := 8

const ALERT_WARNING := &"solar_storm_warning"
const ALERT_START := &"solar_storm_start"
const ALERT_END := &"solar_storm_end"
const ALERT_DOSE_PREFIX := "radiation_dose_"
const ALERT_ISOLATION_PREFIX := "radiation_isolation_"

# ---------------------------------------------------------------- the host step

## One host step: `delta_hours` game hours of this simulation tick. Does nothing once the colony is over.
static func step(session: SessionService, delta_hours: float) -> void:
	if session == null or session.state == null or not session.authoritative or delta_hours <= 0.0:
		return
	var state := session.state
	if bool(state.colony_over.get("over", false)):
		return
	var r := ensure(state)
	_storms(session, r, delta_hours)
	var share := float(r.get("storm_share", 0.0))
	var running: Dictionary = r.storm
	var peak := float(running.get("peak_msv_per_hour", 0.0)) if not running.is_empty() else 0.0
	var crew: Dictionary = r.crew
	var worst_rate := 0.0
	for c: CharacterState in state.characters.values():
		if not DOSE_PARKED_CREW and not c.is_active():
			continue
		if c.health <= 0.0:
			continue
		var key := String(c.id)
		var rec: Dictionary = crew.get(key, {})
		if rec.is_empty():
			rec = {"place": "inside", "rate_msv_h": 0.0, "warned": [], "next_isolation_msv": LIMIT_MSV, "isolations": 0}
			crew[key] = rec
		var place := place_of(session, c)
		var rate := background_rate(state, place) + peak * share * storm_factor(state, place)
		var dose := rate * delta_hours
		c.dose_msv += dose
		r.colony_dose_msv = float(r.get("colony_dose_msv", 0.0)) + dose
		rec.place = place
		rec.rate_msv_h = rate
		worst_rate = maxf(worst_rate, rate)
		_dose_warnings(session, c, rec)
		_isolation(session, c, rec)
	# The colony balance meter's trend (scripts/upgrades/colony_balance.gd): the worst crewmate's rate, per sol.
	r["dose_rate_msv_per_sol"] = worst_rate * SOL


## state.radiation with every field present (fills a new or old record in place).
static func ensure(state: ColonyState) -> Dictionary:
	var r := state.radiation
	if not r.has("version"):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("radiation:%d" % state.rng_seed)
		r.version = 1
		r.rng_seed = str(rng.seed)
		r.rng_state = str(rng.state)
		r.generated = 0
		r.armed_at_hours = -1.0
		r.phase = "calm"
		r.active = false
		r.warned_at_hours = -1.0
		r.starts_at_hours = -1.0
		r.ends_at_hours = -1.0
		r.shelter = []
		r.next = {}
		r.storm = {}
		r.history = []
		r.storm_share = 0.0
		r.crew = {}
		r.colony_dose_msv = 0.0
	for k: String in ["next", "storm", "crew"]:
		if not (r.get(k) is Dictionary):
			r[k] = {}
	if not (r.get("history") is Array):
		r.history = []
	if not (r.get("shelter") is Array):
		r.shelter = []
	return r


## Writes the shared keys other helpers read (phase, active, warned/starts/ends_at_hours, shelter).
static func _publish(session: SessionService, r: Dictionary) -> void:
	var running: Dictionary = r.storm
	var nxt: Dictionary = r.next
	var p := session.config.hub_position
	r.shelter = [p.x, p.y, p.z]
	var shown: Dictionary = running if not running.is_empty() else (nxt if not nxt.is_empty() and bool(nxt.get("warned", false)) else {})
	r.active = not running.is_empty()
	r.phase = "active" if not running.is_empty() else ("warned" if not shown.is_empty() else "calm")
	if shown.is_empty():
		r.warned_at_hours = -1.0
		r.starts_at_hours = -1.0
		r.ends_at_hours = -1.0
	else:
		r.warned_at_hours = float(shown.get("warned_at_hours", -1.0))
		r.starts_at_hours = float(shown.get("at_hours", -1.0))
		r.ends_at_hours = float(shown.get("at_hours", 0.0)) + float(shown.get("duration_hours", 0.0))


# ---------------------------------------------------------------- where a crewmate is

## "outside", "rover" (a sealed rover cabin), "shelter" (the storm shelter area) or "inside".
static func place_of(session: SessionService, c: CharacterState) -> String:
	if rover_sheltered(session.state, c):
		return "rover"
	if c.outside:
		return "outside"
	if in_shelter_area(session, c):
		return "shelter"
	return "inside"


## True when the crewmate is inside the storm shelter area (the Med Bay for now).
static func in_shelter_area(session: SessionService, c: CharacterState) -> bool:
	if session.zone_at_position.is_valid():
		return String(session.zone_at_position.call(c.position)) == SHELTER_ZONE
	return session.is_at_hub(c.position)


## True when the crewmate sits in a sealed rover cabin (RoverModel.cabin_sheltered, scripts/vehicle/rover_model.gd).
static func rover_sheltered(state: ColonyState, c: CharacterState) -> bool:
	return RoverModel.cabin_sheltered(state, c)


## True when the colony has a storm shelter (protection track).
static func has_shelter(state: ColonyState) -> bool:
	return bool(AreaLevels.effect(state, TRACK_PROTECTION, "storm_shelter", false))


static func indoor_factor(state: ColonyState) -> float:
	return clampf(AreaLevels.effectf(state, TRACK_PROTECTION, "radiation_indoor_factor", 1.0), 0.0, 1.0)


static func shelter_factor(state: ColonyState) -> float:
	if not has_shelter(state):
		return 1.0
	return clampf(AreaLevels.effectf(state, TRACK_PROTECTION, "storm_shelter_factor", 1.0), 0.0, 1.0)


## Game mSv per game hour from the steady cosmic rays at a place.
static func background_rate(state: ColonyState, place: String) -> float:
	var base := CURIOSITY_MSV_PER_SOL / SOL * GAME_DOSE_FACTOR
	match place:
		"outside":
			return base * OUTDOOR_FACTOR
		"rover":
			return base
		_:
			return base * indoor_factor(state)


## Share of a solar storm's dose that reaches a crewmate at a place.
static func storm_factor(state: ColonyState, place: String) -> float:
	match place:
		"outside":
			return 1.0
		"rover":
			return minf(ROVER_CABIN_STORM_FACTOR, shelter_factor(state))
		"shelter":
			return minf(indoor_factor(state), shelter_factor(state))
		_:
			return indoor_factor(state)


# ---------------------------------------------------------------- solar storms

static func _rng(r: Dictionary) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(String(r.rng_seed))
	rng.state = int(String(r.rng_state))
	return rng


static func _storms(session: SessionService, r: Dictionary, dt: float) -> void:
	var state := session.state
	var events := session.events
	var now := state.sim_hours
	if float(r.armed_at_hours) < 0.0:
		if TutorialSystem.is_tutorial_done(state):
			r.armed_at_hours = now
		else:
			r.storm_share = 0.0
			_publish(session, r)
			return
	var running: Dictionary = r.storm
	if running.is_empty() and (r.next as Dictionary).is_empty():
		var after := float(r.armed_at_hours)
		var history: Array = r.history
		if not history.is_empty():
			var last: Dictionary = history[history.size() - 1]
			after = float(last.at_hours) + float(last.duration_hours)
		r.next = _make_storm(r, maxf(after, now))
	var nxt: Dictionary = r.next
	# warning
	if running.is_empty() and not nxt.is_empty() and not bool(nxt.warned):
		var warn_h := float(nxt.warn_minutes) / 60.0 * maxf(1.0, AreaLevels.effectf(state, TRACK_COMMAND, "storm_warning_factor", 1.0))
		if now + dt >= float(nxt.at_hours) - warn_h:
			# never less warning than promised: a late warning moves the start back
			nxt.at_hours = maxf(float(nxt.at_hours), now + warn_h)
			nxt.warned = true
			nxt.warned_at_hours = now
			nxt.warn_hours = warn_h
			if events != null:
				events.system_alert.emit(ALERT_WARNING, &"urgent", warning_text(session, nxt))
	# start
	if running.is_empty() and not nxt.is_empty() and bool(nxt.warned) and now >= float(nxt.at_hours):
		r.storm = nxt
		r.next = {}
		running = r.storm
		if events != null:
			events.system_alert.emit(ALERT_START, &"warn", start_text(state, running))
	# running
	if not running.is_empty():
		var t := now - float(running.at_hours)
		if t >= float(running.duration_hours):
			var history: Array = r.history
			history.append({"id": String(running.id), "at_hours": float(running.at_hours), "duration_hours": float(running.duration_hours),
				"dose_real_msv": float(running.dose_real_msv)})
			while history.size() > HISTORY_LENGTH:
				history.pop_front()
			r.storm = {}
			r.storm_share = 0.0
			if events != null:
				events.system_alert.emit(ALERT_END, &"info", "Mission Control: the solar storm is over. Radiation is back to normal, so the crew can leave the shelter and go outside again.")
		else:
			# the share at the middle of this tick
			r.storm_share = share_at(running, maxf(0.0, t - 0.5 * dt))
	else:
		r.storm_share = 0.0
	_publish(session, r)


static func _make_storm(r: Dictionary, after_hours: float) -> Dictionary:
	var rng := _rng(r)
	var k := int(r.generated)
	var gap := rng.randf_range(FIRST_GAP_SOLS_MIN, FIRST_GAP_SOLS_MAX) if k == 0 else rng.randf_range(STORM_GAP_SOLS_MIN, STORM_GAP_SOLS_MAX)
	var duration := rng.randf_range(STORM_SOLS_MIN, STORM_SOLS_MAX) * SOL
	var warn_min := rng.randf_range(WARNING_MINUTES_MIN, WARNING_MINUTES_MAX)
	var dose_real := rng.randf_range(STORM_DOSE_REAL_MSV_MIN, FIRST_STORM_DOSE_REAL_MSV_MAX if k == 0 else STORM_DOSE_REAL_MSV_MAX)
	r.rng_state = str(rng.state)
	r.generated = k + 1
	var rise := minf(RISE_HOURS, 0.2 * duration)
	var fade := maxf(0.1, (duration - rise) / 3.0)
	var area := 0.5 * rise + fade * (1.0 - exp(-(duration - rise) / fade))
	var peak := dose_real * GAME_DOSE_FACTOR / maxf(area, 1e-6)
	return {"id": "spe_%d" % (k + 1), "index": k, "at_hours": snappedf(after_hours + gap * SOL, 0.001),
		"duration_hours": snappedf(duration, 0.001), "warn_minutes": snappedf(warn_min, 0.01), "dose_real_msv": snappedf(dose_real, 0.01),
		"peak_msv_per_hour": peak, "rise_hours": rise, "fade_hours": fade, "warned": false, "warned_at_hours": -1.0, "warn_hours": 0.0}


## The storm flux `t` game hours after its start, as a share of its peak (0..1).
static func share_at(storm: Dictionary, t: float) -> float:
	if storm.is_empty() or t < 0.0 or t > float(storm.get("duration_hours", 0.0)):
		return 0.0
	var rise := float(storm.get("rise_hours", RISE_HOURS))
	if t < rise:
		return t / maxf(rise, 1e-6)
	return exp(-(t - rise) / maxf(float(storm.get("fade_hours", 1.0)), 1e-6))


# ---------------------------------------------------------------- dose warnings and isolation

static func _dose_warnings(session: SessionService, c: CharacterState, rec: Dictionary) -> void:
	var warned: Array = rec.warned
	for level: float in WARN_MSV:
		if c.dose_msv >= level and not warned.has(level):
			warned.append(level)
			if session.events != null:
				session.events.system_alert.emit(StringName(ALERT_DOSE_PREFIX + String(c.id)), &"warn",
					("Mission Control: %s's radiation dose is %d mSv. At %d mSv they get sick and must go into isolation. Keep them inside "
					+ "and give the outside work to someone else.") % [c.display_name, roundi(level), roundi(LIMIT_MSV)])


static func _isolation(session: SessionService, c: CharacterState, rec: Dictionary) -> void:
	var state := session.state
	if not c.isolation.is_empty():
		if state.sim_hours >= float(c.isolation.get("until_hours", 0.0)):
			c.isolation = {}
			if session.events != null:
				session.events.system_alert.emit(StringName(ALERT_ISOLATION_PREFIX + String(c.id)), &"info",
					"Mission Control: %s is out of isolation, but can do indoor work only from now on. Their dose (%d mSv) never goes down, so going outside again could make them sick again." % [c.display_name, roundi(c.dose_msv)])
		elif c.outside:
			# isolated crew cannot go outside: back to the bed
			move_to_bed(session, c)
			if session.events != null:
				session.events.system_alert.emit(StringName(ALERT_ISOLATION_PREFIX + String(c.id)), &"warn", blocked_text(c))
		return
	if c.dose_msv < float(rec.get("next_isolation_msv", LIMIT_MSV)):
		return
	var hours := ISOLATION_HOURS * clampf(AreaLevels.effectf(state, TRACK_HEALTH, "isolation_hours_factor", 1.0), 0.05, 4.0)
	c.isolation = {"since_hours": state.sim_hours, "until_hours": state.sim_hours + hours}
	c.health = clampf(minf(c.health, ISOLATION_HEALTH), 1.0, ISOLATION_HEALTH)
	rec.isolations = int(rec.get("isolations", 0)) + 1
	rec.next_isolation_msv = maxf(LIMIT_MSV, c.dose_msv) + REISOLATION_STEP_MSV
	move_to_bed(session, c)
	if session.events != null:
		session.events.system_alert.emit(StringName(ALERT_ISOLATION_PREFIX + String(c.id)), &"urgent",
			("Mission Control: %s reached %d mSv, NASA's limit, and is sick. They are in isolation in the Med Bay for about %d game hours "
			+ "and cannot work or go outside. Swap to another crewmate (C).") % [c.display_name, roundi(c.dose_msv), roundi(hours)])


## Where a crewmate's isolation bed is: their own collision-probed Med Bay spot (GameConfig.crew_hub_offsets).
static func bed_position(session: SessionService, c: CharacterState) -> Vector3:
	if c.hub_spot != Vector3.ZERO:
		return c.hub_spot
	var ids := session.state.characters.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	var i := ids.find(c.id)
	var offsets := session.config.crew_hub_offsets
	var offset := offsets[i] if i >= 0 and i < offsets.size() else Vector3.ZERO
	return session.config.hub_position + offset


## Moves a crewmate to their isolation bed (host). Every machine takes the new pose from the
## character_recovered event, which carries {"isolation": true} (no cost, not a death).
static func move_to_bed(session: SessionService, c: CharacterState) -> void:
	session.repair_runtime.release_character(c.id)
	session.cassette_runtime.release_character(c.id)
	session.wear_runtime.release_character(c.id)
	c.position = bed_position(session, c)
	c.outside = bool(session.outside_test.call(c.position)) if session.outside_test.is_valid() else false
	if session.survival != null:
		session.survival.reset_character(c)
	if session.events != null:
		session.events.character_recovered.emit(c.id, {"isolation": true, "cause": "radiation_isolation", "meals": 0.0, "water_l": 0.0,
			"cache_id": "", "cache_position": []})


# ---------------------------------------------------------------- questions for the schedule, actions and HUD

## True while the crewmate is in isolation (no outside, no work).
static func is_isolated(actor: CharacterState) -> bool:
	return actor != null and not actor.isolation.is_empty()


## True once the crewmate has reached the limit: indoor work only, for good (also while isolated).
static func indoor_only(actor: CharacterState) -> bool:
	return actor != null and actor.dose_msv >= LIMIT_MSV


## Game hours of isolation left (0 when not isolated).
static func isolation_hours_left(state: ColonyState, actor: CharacterState) -> float:
	if not is_isolated(actor) or state == null:
		return 0.0
	return maxf(0.0, float(actor.isolation.get("until_hours", 0.0)) - state.sim_hours)


## What to tell a player who tries something the crewmate may not do now, or "".
static func blocked_text(actor: CharacterState, outside := true) -> String:
	if is_isolated(actor):
		return "%s is in isolation. Swap to another crewmate in the Med Bay (C)." % actor.display_name
	if outside and indoor_only(actor):
		return "%s has reached the radiation limit (%d mSv) and can do indoor work only." % [actor.display_name, roundi(actor.dose_msv)]
	return ""


## Dose band for colours: "ok" (< 400), "warn" (400..500), "high" (500..600), "limit" (>= 600).
static func band(dose_msv: float) -> String:
	if dose_msv >= LIMIT_MSV:
		return "limit"
	if dose_msv >= WARN_MSV[1]:
		return "high"
	if dose_msv >= WARN_MSV[0]:
		return "warn"
	return "ok"


## The solar storm now, for the HUD: {"phase": "calm"|"warned"|"active", "hours": game hours until it starts
## (warned) or until it ends (active), "share": flux share now, "faded": true when the worst is over, "shelter": bool}.
static func storm_now(state: ColonyState) -> Dictionary:
	var r := state.radiation
	var out := {"phase": "calm", "hours": 0.0, "share": 0.0, "faded": false, "shelter": has_shelter(state)}
	var running: Dictionary = r.get("storm", {}) if r.get("storm") is Dictionary else {}
	var nxt: Dictionary = r.get("next", {}) if r.get("next") is Dictionary else {}
	if not running.is_empty():
		var share := float(r.get("storm_share", 0.0))
		var t := state.sim_hours - float(running.get("at_hours", 0.0))
		out.phase = "active"
		out.hours = maxf(0.0, float(running.get("duration_hours", 0.0)) - t)
		out.share = share
		out.faded = t > float(running.get("rise_hours", RISE_HOURS)) and share < FADED_SHARE
	elif not nxt.is_empty() and bool(nxt.get("warned", false)):
		out.phase = "warned"
		out.hours = maxf(0.0, float(nxt.get("at_hours", 0.0)) - state.sim_hours)
	return out


## Where to go in a storm, in words.
static func shelter_words(state: ColonyState) -> String:
	if has_shelter(state):
		return "Go to the shelter (%s)" % SHELTER_NAME
	return "Get inside: the base has no storm shelter yet (Health: Protection)"


## The warning Mission Control sends.
static func warning_text(session: SessionService, storm: Dictionary) -> String:
	var hours := float(storm.get("warn_hours", 0.0))
	var hps := session.clock.hours_per_real_second() if session.clock != null else 1.0
	var real_s := hours / maxf(hps, 1e-9)
	var when := "about %d seconds" % maxi(1, roundi(real_s)) if real_s < 90.0 else "about %d minutes" % roundi(real_s / 60.0)
	return ("Mission Control: SOLAR STORM WARNING. A burst of fast particles from the Sun reaches Mars in %s. %s and stay there "
		+ "until it is over (1 to 3 sols). Anyone outside: come in now.") % [when, shelter_words(session.state)]


static func start_text(state: ColonyState, storm: Dictionary) -> String:
	return ("Mission Control: the solar storm has started and will last about %.1f sols. %s. The worst comes in the first hours; "
		+ "it fades after that.") % [float(storm.get("duration_hours", SOL)) / SOL, shelter_words(state)]
