class_name SolClock
extends RefCounted
## Game time. A sol always holds GameConfig.SOL_HOURS game hours; `sol_minutes` only sets how many real minutes that
## takes. The position in the sol is stored as `phase`, so changing `sol_minutes` never moves the time of day.
## Real-second things (input, the suit check, radio delay) do not read this clock.

var sol_minutes := 20.0
## Whole sols finished since the game began.
var sol_index := 0
## Position in the current sol: 0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset.
var phase := 0.0
## Simulation ticks done since the game began.
var ticks := 0
## Real seconds simulated (paused time does not count).
var real_seconds := 0.0
## Sols that ended during the last call to advance().
var rolled_over := 0


func hours_per_real_second() -> float:
	return GameConfig.SOL_HOURS / (sol_minutes * 60.0)


## Game hours since the game began.
func game_hours() -> float:
	return (float(sol_index) + phase) * GameConfig.SOL_HOURS


func hour_of_sol() -> float:
	return phase * GameConfig.SOL_HOURS


func is_daylight() -> bool:
	return phase > 0.25 and phase < 0.75


## Moves the clock on by `real_dt` real seconds (one simulation tick). Returns the game hours that passed.
func advance(real_dt: float) -> float:
	var dt_hours := real_dt * hours_per_real_second()
	phase += real_dt / (sol_minutes * 60.0)
	rolled_over = 0
	while phase >= 1.0:
		phase -= 1.0
		sol_index += 1
		rolled_over += 1
	ticks += 1
	real_seconds += real_dt
	return dt_hours


## Changes how long a sol takes. The time of day (phase) and the sol number stay exactly as they were.
func set_sol_minutes(minutes: float, config: GameConfig) -> void:
	sol_minutes = config.clamp_sol_minutes(minutes)


func to_dict() -> Dictionary:
	return {"sol_minutes": sol_minutes, "sol_index": sol_index, "phase": phase, "ticks": ticks, "real_seconds": real_seconds}


static func from_dict(d: Dictionary) -> SolClock:
	var c := SolClock.new()
	c.sol_minutes = float(d.get("sol_minutes", 20.0))
	c.sol_index = int(d.get("sol_index", 0))
	c.phase = clampf(float(d.get("phase", 0.0)), 0.0, 0.999999)
	c.ticks = int(d.get("ticks", 0))
	c.real_seconds = float(d.get("real_seconds", 0.0))
	return c
