class_name WeatherSystem
extends RefCounted
## Dust weather of the colony (Prompt 09). A pre-system: it runs first in every tick on the HOST only (clients never
## step the simulation; they receive state.weather, state.weather_queue and state.data_snapshot_id with the colony).
##
## What it does each tick:
##   1. pins the data: the first tick of a new game takes WeatherArchive.active() and saves its snapshot id in
##      state.data_snapshot_id; a loaded game adopts the newest validated data for events not yet issued, and keeps
##      every issued event and a running storm exactly as saved.
##   2. teaching first: no event until the panels' answer to dust has been taught (a panel was cleaned or the
##      evidence `energy_diagnose_output_loss` exists) AND the colony has run 2 sols, whichever is later. The first
##      event is minor (the archive's smallest episode, scaled to at most WeatherConfig.minor_severity_max).
##   3. keeps state.weather_queue filled with future events, made deterministically from the colony seed and the
##      pinned bundle: each takes an observed episode (its opacity curve, wind and solar effect), scales its opacity
##      rise above its own background by a severity, stretches its duration, and draws the calm gap before it. Gaps,
##      durations and severities differ per seed; a later event may be stronger (escalation).
##   4. warns ahead: at least WeatherConfig.return_margin x the longest current outdoor walk home (ReturnRoutes, suit
##      walking speed) and at least min_warning_hours before the opacity starts to rise. When the warning is issued the
##      severity is capped by the colony's readiness (battery above the reserve, cleaner working, clean panels, life
##      support fine); a colony that is not ready gets the event held back, and the recovery interval after an event
##      is longer when the colony is less ready.
##   5. sets state.dust_tau from the seasonal background plus the running event (continuous in time, bounded).
##      The game's Ls comes from the sol count: sols = state.sim_hours / SOL_HOURS, mean anomaly advances by
##      360 degrees per Mars year (668.6 sols), Ls = true anomaly (equation of the centre, eccentricity 0.0935)
##      + 251 degrees (Ls of perihelion); sol 0 sits at WeatherConfig.start_ls (default: the archive's first Ls).
## Events: events.weather_changed({"type": "warning"|"start"|"peak"|"end", ...}) and a system_alert warning ahead.
##
## Words matter: these are ARCHIVE OBSERVATIONS FROM JEZERO, PLAYED FASTER, and NOT A FORECAST FOR THIS COLONY. The
## gaps between events are a game transformation (accelerated), not NASA-observed storm frequency.

const SOL := GameConfig.SOL_HOURS
const ALERT_ID := &"weather_warning"
const LABEL_ARCHIVE := "Archive observations from Jezero, played faster"
const LABEL_NOT_FORECAST := "Not a forecast for this colony"

var config: WeatherConfig
## Optional: the session, so a walk in real seconds can be turned into game hours at the real sol length. Without it
## the fastest allowed sol is assumed (the warning is then long enough at any sol length).
var session: SessionService
## The data pinned for the bound game.
var archive: WeatherArchive
## False switches the weather off (tests that compare with a constant sky).
var enabled := true
## Suit walking speed in m/s: PlayerTuning.walk_speed x GameConfig.suit_speed_factor.
var walk_speed_mps := 2.4

var _bound := 0
var _routes: ReturnRoutes
var _station_return_s := -1.0
var _fastest_hours_per_second := SOL / (5.0 * 60.0)


func _init(p_config: WeatherConfig = null) -> void:
	config = p_config if p_config != null else WeatherConfig.new()
	var game := GameConfig.new()
	if ResourceLoader.exists("res://config/game_config.tres"):
		var loaded := load("res://config/game_config.tres") as GameConfig
		if loaded != null:
			game = loaded
	walk_speed_mps = PlayerTuning.new().walk_speed * game.suit_speed_factor
	_fastest_hours_per_second = SOL / (maxf(game.sol_minutes_min, 0.1) * 60.0)


## The WeatherSystem a session runs, or null.
static func of_session(s: SessionService) -> WeatherSystem:
	if s == null or s.sim == null:
		return null
	for system: Variant in s.sim.pre_systems:
		if system is WeatherSystem:
			return system
	return null


func step(state: ColonyState, balance: GameBalance, _phase: float, dt_hours: float, events: GameEvents) -> void:
	if not enabled or state == null or dt_hours <= 0.0:
		return
	if state.get_instance_id() != _bound:
		_bind(state, balance)
	var w := state.weather
	var t0 := state.sim_hours
	var t1 := t0 + dt_hours
	_note_teaching(state, w)
	_fill_queue(w, state)
	_resolve_times(w, state, balance)
	_warn(state, balance, events, w, t1, dt_hours)
	_start_due(state, events, w, t1)
	_advance_active(state, balance, events, w, t1)
	_fill_queue(w, state)
	_set_sky(state, balance, w, t0 + 0.5 * dt_hours)


# ---------------------------------------------------------------- binding and data

func _bind(state: ColonyState, balance: GameBalance) -> void:
	_bound = state.get_instance_id()
	_station_return_s = -1.0
	archive = WeatherArchive.active()
	if state.weather.is_empty() or not state.weather.has("rng_state"):
		_start_weather(state, balance)
		return
	# A loaded game: issued events and a running storm stay exactly as saved; newer validated data (if any) is used
	# for events made from now on.
	if state.data_snapshot_id != archive.snapshot_id():
		state.weather["adopted"] = {"from": state.data_snapshot_id, "to": archive.snapshot_id(), "at_hours": state.sim_hours}
		state.data_snapshot_id = archive.snapshot_id()
		state.weather["data"] = data_info(archive)


func _start_weather(state: ColonyState, balance: GameBalance) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("weather:%d" % state.rng_seed)
	var ls0 := config.start_ls if config.start_ls >= 0.0 else archive.start_ls(0.0)
	var bg0 := archive.background_tau(ls0)
	var scale := balance.dust_tau_default / bg0 if config.scale_sky_to_default and bg0 > 1e-6 else 1.0
	# background wind: the mean of the measured wind-speed columns (m/s); -1 = the archive has no measured wind
	var bg_wind := archive.mean_of_kind("wind", -1.0, "m/s")
	# on a brand-new colony every panel carries the arrival dust: a panel cleaned before the first tick counts too
	var seen := state.panel_dust.duplicate()
	if state.sim_hours < 1e-9:
		seen = []
		for i in state.panel_dust.size():
			seen.append(maxf(float(state.panel_dust[i]), balance.panel_dust_start))
	state.data_snapshot_id = archive.snapshot_id()
	state.weather_queue = []
	state.weather = {
		"data": data_info(archive), "rng_seed": str(rng.seed), "rng_state": str(rng.state), "start_ls": ls0, "sky_scale": scale,
		"background_wind_ms": bg_wind, "phase": "calm", "event_id": "", "episode_id": "", "tau": scale * bg0, "tau_background": scale * bg0,
		"wind_ms": bg_wind, "ls": ls0, "warning": {}, "active": {}, "taught_at_hours": -1.0, "condition_at_hours": -1.0,
		"dust_seen": seen, "generated": 0, "history": [], "last_end_hours": -1.0, "recovery_hours": config.recovery_hours_min,
	}


## What the screens show about the data, saved with the game so every player (late joiners too) sees it.
static func data_info(a: WeatherArchive) -> Dictionary:
	var period := a.observation_period()
	return {"snapshot_id": a.snapshot_id(), "bundle_id": a.bundle_id(), "site": a.site(), "source": a.source,
		"validation": a.validation_words(), "observation_start": String(period.get("start", "")), "observation_end": String(period.get("end", "")),
		"sol_start": float(period.get("sol_start", 0.0)) if not period.is_empty() else 0.0,
		"sol_end": float(period.get("sol_end", 0.0)) if not period.is_empty() else 0.0,
		"episodes": a.episodes.size(), "described": a.describe()}


# ---------------------------------------------------------------- teaching

func _note_teaching(state: ColonyState, w: Dictionary) -> void:
	if float(w.taught_at_hours) < 0.0:
		var taught := ProgressEvidence.has(state, &"energy_diagnose_output_loss")
		for key: String in ["panels_cleaned", "panel_cleanings", "panels_cleaned_by_hand"]:
			if float(state.ledger.get(key, 0.0)) > 0.0:
				taught = true
		# dust only settles; a panel that got cleaner was cleaned (by hand, or by the cleaner after a repair)
		var seen: Array = w.get("dust_seen", [])
		for i in mini(seen.size(), state.panel_dust.size()):
			if float(state.panel_dust[i]) < float(seen[i]) - 1e-6:
				taught = true
		if taught:
			w.taught_at_hours = state.sim_hours
			w.condition_at_hours = maxf(state.sim_hours, config.teach_min_sols * SOL)
	w.dust_seen = state.panel_dust.duplicate()


# ---------------------------------------------------------------- the queue

func _rng(w: Dictionary) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(String(w.rng_seed))
	rng.state = int(String(w.rng_state))
	return rng


func _fill_queue(w: Dictionary, state: ColonyState) -> void:
	if archive == null or archive.episodes.is_empty():
		return
	while state.weather_queue.size() < config.queue_length:
		state.weather_queue.append(_make_event(w))


## One future event from the pinned bundle and the weather's own random stream.
func _make_event(w: Dictionary) -> Dictionary:
	var rng := _rng(w)
	var k := int(w.generated)
	var ep: Dictionary
	var severity: float
	if k == 0:
		ep = _smallest_episode()
		severity = rng.randf_range(config.minor_severity_min, config.minor_severity_max)
	else:
		ep = archive.episodes[rng.randi_range(0, archive.episodes.size() - 1)]
		var ceiling := minf(config.severity_max, config.minor_severity_max + config.severity_step * float(k))
		severity = ceiling * rng.randf_range(config.severity_low_share, 1.0)
	var stretch := rng.randf_range(config.stretch_min, config.stretch_max)
	var gap := rng.randf_range(config.first_gap_hours_min, config.first_gap_hours_max) if k == 0 \
		else lerpf(config.gap_sols_min, config.gap_sols_max, pow(rng.randf(), config.gap_shape)) * SOL
	w.rng_state = str(rng.state)
	w.generated = k + 1
	var curve: Array = ep.tau_curve
	var base := minf(float(curve[0]), float(curve[curve.size() - 1]))
	var excess: Array = []
	var peak_i := 0
	for i in curve.size():
		var x := snappedf(maxf(0.0, float(curve[i]) - base), 0.0001)
		excess.append(x)
		if x > float(excess[peak_i]):
			peak_i = i
	var duration := float(ep.duration_sols) * stretch * SOL
	return {
		"id": "wx_%d" % (k + 1), "index": k, "episode_id": String(ep.id), "observed": String(ep.observed),
		"source_product_ids": (ep.source_product_ids as Array).duplicate(), "snapshot_id": archive.snapshot_id(),
		"severity_planned": snappedf(severity, 0.0001), "severity": snappedf(severity, 0.0001), "stretch": snappedf(stretch, 0.0001),
		"gap_hours": snappedf(gap, 0.001), "at_hours": -1.0, "duration_hours": snappedf(duration, 0.001),
		"step_hours": snappedf(duration / float(curve.size() - 1), 0.0001), "excess_curve": excess, "peak_index": peak_i,
		"excess_peak": float(excess[peak_i]), "peak_tau_observed": float(ep.peak_tau),
		# -999.0 in the bundle = not measured (most MEDA wind is withheld): never used as a number
		"wind_ms_mean": -1.0 if WeatherArchive.is_missing(float(ep.wind_ms_mean)) else float(ep.wind_ms_mean),
		"wind_measured": not WeatherArchive.is_missing(float(ep.wind_ms_mean)),
		"solar_factor_observed": float(ep.solar_factor_at_peak), "warned": false, "shifted_hours": 0.0, "moves": [],
	}


func _smallest_episode() -> Dictionary:
	var best: Dictionary = archive.episodes[0]
	var best_x := INF
	for ep: Dictionary in archive.episodes:
		var curve: Array = ep.tau_curve
		var base := minf(float(curve[0]), float(curve[curve.size() - 1]))
		var top := 0.0
		for v: Variant in curve:
			top = maxf(top, float(v) - base)
		if top < best_x:
			best_x = top
			best = ep
	return best


## Start times of events not yet warned: after the teaching condition (first event) or after the previous event
## plus its gap (and at least the recovery interval), plus any time the event was moved back.
func _resolve_times(w: Dictionary, state: ColonyState, _balance: GameBalance) -> void:
	var prev_end := -1.0
	var recovery := float(w.get("recovery_hours", config.recovery_hours_min))
	var active: Dictionary = w.active
	if not active.is_empty():
		prev_end = float(active.at_hours) + float(active.duration_hours)
	elif float(w.last_end_hours) >= 0.0:
		prev_end = float(w.last_end_hours)
	for i in state.weather_queue.size():
		var e: Dictionary = state.weather_queue[i]
		if bool(e.warned):
			prev_end = float(e.at_hours) + float(e.duration_hours)
			recovery = config.recovery_hours_min
			continue
		var at := -1.0
		if int(e.index) == 0:
			if float(w.condition_at_hours) >= 0.0:
				at = float(w.condition_at_hours) + float(e.gap_hours)
		elif prev_end >= 0.0:
			at = prev_end + maxf(float(e.gap_hours), recovery)
		if at >= 0.0:
			at += float(e.shifted_hours)
		e.at_hours = at
		if at < 0.0:
			prev_end = -1.0
			continue
		prev_end = at + float(e.duration_hours)
		recovery = config.recovery_hours_min


# ---------------------------------------------------------------- warning

## The warning is issued at the last tick that still leaves the full lead (t1 + this tick's length + lead >= start),
## so the start is not pushed back by a fraction of a tick; it is only moved back if the needed lead grew.
func _warn(state: ColonyState, balance: GameBalance, events: GameEvents, w: Dictionary, t1: float, dt: float) -> void:
	if state.weather_queue.is_empty() or not (w.active as Dictionary).is_empty():
		return
	var e: Dictionary = state.weather_queue[0]
	if bool(e.warned) or float(e.at_hours) < 0.0:
		return
	var longest := longest_return_seconds(state)
	var lead := lead_hours_for(longest)
	if t1 + dt + lead < float(e.at_hours):
		return
	var hold := hold_reason(state, balance, int(e.index))
	if hold != "":
		e.shifted_hours = float(e.shifted_hours) + config.hold_hours
		(e.moves as Array).append({"at_hours": t1, "hours": config.hold_hours, "why": "held back: the colony is not ready (%s)" % hold})
		e.at_hours = float(e.at_hours) + config.hold_hours
		return
	var left := float(e.at_hours) - t1
	if left < lead:
		e.shifted_hours = float(e.shifted_hours) + (lead - left)
		(e.moves as Array).append({"at_hours": t1, "hours": lead - left, "why": "moved back so the warning gives the full walking margin"})
		e.at_hours = t1 + lead
	var ready := readiness(state, balance)
	var cap := lerpf(config.readiness_cap_low, config.readiness_cap_high, float(ready.value))
	e.severity = snappedf(minf(float(e.severity_planned), cap), 0.0001)
	e.readiness = snappedf(float(ready.value), 0.0001)
	e.severity_cap = snappedf(cap, 0.0001)
	e.warned = true
	e.warned_at_hours = t1
	e.lead_hours = float(e.at_hours) - t1
	e.return_seconds = longest
	var hps := hours_per_real_second()
	var text := warning_text(e, longest, hps)
	w.warning = {"event_id": String(e.id), "issued_at_hours": t1, "starts_at_hours": float(e.at_hours), "lead_hours": float(e.lead_hours),
		"return_seconds": longest, "margin": config.return_margin, "severity": float(e.severity), "text": text, "acknowledged_by": []}
	w.phase = "warned"
	if events != null:
		events.system_alert.emit(ALERT_ID, &"warn", text)
		events.weather_changed.emit({"type": "warning", "event_id": String(e.id), "episode_id": String(e.episode_id),
			"starts_at_hours": float(e.at_hours), "lead_hours": float(e.lead_hours), "severity": float(e.severity), "text": text})


## The warning in plain words.
static func warning_text(e: Dictionary, return_seconds: float, hours_per_second: float) -> String:
	var lead_h := float(e.get("lead_hours", 0.0))
	var real_min := lead_h / maxf(hours_per_second, 1e-9) / 60.0
	var walk := "about %d seconds" % roundi(return_seconds) if return_seconds < 90.0 else "about %d minutes" % roundi(return_seconds / 60.0)
	return ("Dust warning: in about %d game hours (about %d real minutes) dust will start to darken the sky and the solar panels will "
		+ "make less power. Anyone outside: walk back to the airlock in good time (the longest walk back right now is %s). After the "
		+ "dust, clean the panels. (%s. %s.)") % [roundi(lead_h), maxi(1, roundi(real_min)), walk, LABEL_ARCHIVE, LABEL_NOT_FORECAST]


## Game hours of warning needed for a walk home of `return_seconds` real seconds.
func lead_hours_for(return_seconds: float) -> float:
	return maxf(config.min_warning_hours, config.return_margin * return_seconds * hours_per_real_second())


## Game hours per real second: the session's sol length if known, else the fastest allowed sol (the safe side).
func hours_per_real_second() -> float:
	if session != null and session.clock != null:
		return session.clock.hours_per_real_second()
	return _fastest_hours_per_second


## The longest walk home, in real seconds, from where anyone could be working outside right now: every crew member
## who is outside and every outdoor station (the sun trackers).
func longest_return_seconds(state: ColonyState) -> float:
	var routes := _get_routes()
	if _station_return_s < 0.0:
		_station_return_s = 0.0
		for id: String in state.stations:
			var st: Dictionary = state.stations[id]
			if String(st.get("zone", "")) == ColonyZones.EXTERIOR:
				_station_return_s = maxf(_station_return_s, _walk_seconds(routes, CharacterState._v3(st.position)))
	var longest := _station_return_s
	for c: CharacterState in state.active_characters():
		if c.outside:
			longest = maxf(longest, _walk_seconds(routes, c.position))
	return longest


func _walk_seconds(routes: ReturnRoutes, p: Vector3) -> float:
	var s := routes.return_seconds(p, walk_speed_mps)
	if s < 0.0:
		# no known route from there (for example on a rock): be generous, 1.5 x the straight line
		var e: Vector3 = ReturnRoutes.ENTRANCES[0].position
		s = 1.5 * Vector2(p.x, p.z).distance_to(Vector2(e.x, e.z)) / walk_speed_mps
	return s


func _get_routes() -> ReturnRoutes:
	if _routes == null:
		_routes = ReturnRoutes.shared()
	return _routes


## How ready the colony is for dust, 0..1, with its four parts.
func readiness(state: ColonyState, balance: GameBalance) -> Dictionary:
	var cap := float(state.capacities.get(&"battery_kwh", 0.0))
	var battery := state.store(&"battery_kwh")
	var span := maxf(1.0, 0.5 * cap - config.battery_reserve_kwh)
	var b := clampf((battery - config.battery_reserve_kwh) / span, 0.0, 1.0)
	var cleaner := 1.0 if PowerModel.cleaner_working(state, balance) else 0.0
	var panels := clampf(1.0 - PowerModel.average_dust(state) / 0.5, 0.0, 1.0)
	var life := 1.0
	for a: Dictionary in state.alerts:
		if String(a.get("level", "")) == "urgent":
			life = 0.0
	if life > 0.0 and state.store(&"oxygen_kg") < balance.oxygen_reserve_warn_kg:
		life = 0.5
	var wts := config.readiness_weights
	var value := (wts.x * b + wts.y * cleaner + wts.z * panels + wts.w * life) / maxf(1e-6, wts.x + wts.y + wts.z + wts.w)
	return {"value": value, "battery": b, "cleaner": cleaner, "panels": panels, "life_support": life}


## Why event number `index` (0 = the first) must wait now, or "": battery below hold_battery_factor x the reserve,
## an urgent alert, or (after the first event) dusty panels with no working cleaner.
func hold_reason(state: ColonyState, balance: GameBalance, index: int = 1) -> String:
	if state.store(&"battery_kwh") < config.battery_reserve_kwh * config.hold_battery_factor:
		return "battery below %d kWh" % roundi(config.battery_reserve_kwh * config.hold_battery_factor)
	for a: Dictionary in state.alerts:
		if String(a.get("level", "")) == "urgent":
			return "an urgent life-support or power alert"
	if index > 0 and not PowerModel.cleaner_working(state, balance) and PowerModel.average_dust(state) >= config.hold_dust:
		return "dusty panels and no working cleaner"
	return ""


## True while an event must wait (see hold_reason).
func must_hold(state: ColonyState, balance: GameBalance) -> bool:
	return hold_reason(state, balance) != ""


# ---------------------------------------------------------------- running events

func _start_due(state: ColonyState, events: GameEvents, w: Dictionary, t1: float) -> void:
	if not (w.active as Dictionary).is_empty() or state.weather_queue.is_empty():
		return
	var e: Dictionary = state.weather_queue[0]
	if not bool(e.warned) or t1 < float(e.at_hours):
		return
	state.weather_queue.pop_front()
	e.peaked = false
	w.active = e
	w.warning = {}
	w.event_id = String(e.id)
	w.episode_id = String(e.episode_id)
	w.phase = "rising"
	if events != null:
		events.weather_changed.emit({"type": "start", "event_id": String(e.id), "episode_id": String(e.episode_id), "severity": float(e.severity),
			"at_hours": float(e.at_hours), "duration_hours": float(e.duration_hours), "observed": String(e.observed)})


func _advance_active(state: ColonyState, balance: GameBalance, events: GameEvents, w: Dictionary, t1: float) -> void:
	var a: Dictionary = w.active
	if a.is_empty():
		return
	var at := float(a.at_hours)
	var peak_t := at + float(a.peak_index) * float(a.step_hours)
	var scale := float(w.sky_scale)
	if not bool(a.peaked) and t1 >= peak_t:
		a.peaked = true
		if events != null:
			events.weather_changed.emit({"type": "peak", "event_id": String(a.id), "episode_id": String(a.episode_id),
				"tau": scale * float(a.severity) * float(a.excess_peak) + float(w.tau_background), "severity": float(a.severity)})
	var end := at + float(a.duration_hours)
	if t1 < end:
		return
	var ready := readiness(state, balance)
	var recovery := config.recovery_hours_min * (2.0 - float(ready.value))
	var history: Array = w.history
	history.append({"id": String(a.id), "episode_id": String(a.episode_id), "at_hours": at, "duration_hours": float(a.duration_hours),
		"severity": float(a.severity), "severity_planned": float(a.severity_planned), "peak_tau": scale * float(a.severity) * float(a.excess_peak) + float(w.tau_background),
		"lead_hours": float(a.get("lead_hours", 0.0)), "readiness": float(a.get("readiness", 0.0)), "recovery_hours": recovery,
		"shifted_hours": float(a.shifted_hours), "wind_measured": bool(a.get("wind_measured", false))})
	while history.size() > config.history_length:
		history.pop_front()
	w.active = {}
	w.last_end_hours = end
	w.recovery_hours = recovery
	w.event_id = ""
	w.episode_id = ""
	w.phase = "calm"
	if events != null:
		events.weather_changed.emit({"type": "end", "event_id": String(a.id), "episode_id": String(a.episode_id), "at_hours": end,
			"recovery_hours": recovery})
		events.system_alert.emit(&"weather_clear", &"info", "The dust has passed. Clean the solar panels to get their full power back.")


## Opacity rise of the running event at game hour `t`, before the sky scale (0 outside the event).
static func excess_at(a: Dictionary, t: float) -> float:
	if a.is_empty():
		return 0.0
	var at := float(a.at_hours)
	var curve: Array = a.excess_curve
	var step := float(a.step_hours)
	if t <= at or step <= 0.0 or curve.is_empty():
		return 0.0
	var x := (t - at) / step
	var i := int(floor(x))
	if i >= curve.size() - 1:
		return 0.0 if t >= at + float(a.duration_hours) else float(curve[curve.size() - 1]) * float(a.severity)
	var f := x - float(i)
	# smoothstep between samples: continuous, no corners at the samples
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(float(curve[i]), float(curve[i + 1]), f) * float(a.severity)


func _set_sky(state: ColonyState, _balance: GameBalance, w: Dictionary, t: float) -> void:
	var ls := ls_at(float(w.start_ls), t / SOL, config)
	var scale := float(w.sky_scale)
	var bg := scale * archive.background_tau(ls)
	var a: Dictionary = w.active
	var ex := scale * excess_at(a, t)
	var tau := clampf(bg + ex, 0.0, config.max_tau)
	state.dust_tau = tau
	w.tau = tau
	w.tau_background = bg
	w.ls = ls
	# Wind is shown, never used by the model (no destructive wind). It comes only from measured archive values:
	# the background mean of the wind products, and an episode's own mean wind when it was measured; else -1 =
	# "not measured". `wind_source` says which.
	var bg_wind := float(w.background_wind_ms)
	var wind := bg_wind
	var source := "archive background wind" if bg_wind >= 0.0 else "not measured"
	if not a.is_empty() and bool(a.get("wind_measured", false)) and float(a.excess_peak) > 0.0 and float(a.severity) > 0.0:
		var base := maxf(bg_wind, 0.0)
		var event_wind := base + (float(a.wind_ms_mean) - base) * float(a.severity)
		wind = lerpf(base, event_wind, clampf(excess_at(a, t) / (float(a.excess_peak) * float(a.severity)), 0.0, 1.0))
		source = "this episode's measured wind"
	elif not a.is_empty() and bg_wind >= 0.0:
		source = "archive background wind (not measured for this episode)"
	w.wind_ms = wind
	w.wind_source = source
	if not a.is_empty():
		var peak_t := float(a.at_hours) + float(a.peak_index) * float(a.step_hours)
		w.phase = "rising" if t < peak_t - 0.5 * float(a.step_hours) else ("peak" if t < peak_t + 0.5 * float(a.step_hours) else "falling")
	elif not (w.warning as Dictionary).is_empty():
		w.phase = "warned"
	else:
		w.phase = "calm"


# ---------------------------------------------------------------- Ls from the sol count

## Solar longitude (degrees) `sols` after a sol whose Ls is `start_ls`.
static func ls_at(start_ls: float, sols: float, cfg: WeatherConfig) -> float:
	var e := cfg.orbit_eccentricity
	var m0 := _mean_anomaly_for(start_ls, e, cfg.ls_perihelion_deg)
	return _ls_of(m0 + TAU * sols / cfg.mars_year_sols, e, cfg.ls_perihelion_deg)


static func _true_anomaly(m: float, e: float) -> float:
	return m + (2.0 * e - 0.25 * e * e * e) * sin(m) + 1.25 * e * e * sin(2.0 * m) + 13.0 / 12.0 * e * e * e * sin(3.0 * m)


static func _ls_of(m: float, e: float, perihelion_deg: float) -> float:
	return fposmod(rad_to_deg(_true_anomaly(m, e)) + perihelion_deg, 360.0)


static func _mean_anomaly_for(ls: float, e: float, perihelion_deg: float) -> float:
	var target := deg_to_rad(fposmod(ls - perihelion_deg, 360.0))
	var m := target
	for i in 12:
		var diff := wrapf(_true_anomaly(m, e) - target, -PI, PI)
		var slope := 1.0 + (2.0 * e - 0.25 * e * e * e) * cos(m) + 2.5 * e * e * cos(2.0 * m) + 3.25 * e * e * e * cos(3.0 * m)
		m -= diff / slope
	return m


# ---------------------------------------------------------------- words for the screens

## The sky in words for an opacity.
static func opacity_words(tau: float) -> String:
	if tau < 0.6:
		return "clear for Mars"
	if tau < 0.9:
		return "a little hazy"
	if tau < 1.4:
		return "dusty"
	if tau < 2.2:
		return "very dusty"
	return "dark with dust"


## Share of the usual sunlight (the game's default sky) that reaches the panels now (PowerModel's sky term).
static func sunlight_share(state: ColonyState, balance: GameBalance) -> float:
	return PowerModel.atmosphere_term(state, balance)


## "The sky lets through about 74 % of the usual sunlight, so the panels make about 26 % less power."
static func solar_words(state: ColonyState, balance: GameBalance) -> String:
	var share := sunlight_share(state, balance)
	var pct := roundi(share * 100.0)
	if pct >= 99 and pct <= 101:
		return "The sky lets through the usual sunlight, so the panels make their usual power."
	if share > 1.0:
		return "The sky is clearer than usual: about %d %% of the usual sunlight, so the panels make a little more power." % pct
	return "The sky lets through about %d %% of the usual sunlight, so the panels make about %d %% less power." % [pct, 100 - pct]
