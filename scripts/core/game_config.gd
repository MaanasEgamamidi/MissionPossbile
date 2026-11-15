class_name GameConfig
extends Resource
## Engineering and session settings. Nothing here is a scientific constant unless it says so and names its source.
## Designer balance values live in GameBalance.
# Push check (2026-11-14): this line was pushed to both GitHub repositories, JoseVGerald and MaanasEgamamidi.

## Length of a Martian solar day in hours: 24 h 39 min 35.244 s (NASA GISS Mars24 notes, source S02).
## Used only to express game time in hours; the playable sol length is `sol_minutes_default`.
const SOL_HOURS := 24.6598
## Mean surface gravity of Mars in m/s^2 (NASA Mars Fact Sheet, source S01).
const MARS_GRAVITY := 3.73

@export_group("Time")
## Real minutes one sol takes. A game-time control set by the host, not the scientific length of a Martian day.
@export_range(5.0, 120.0, 0.5) var sol_minutes_default := 20.0
@export var sol_minutes_min := 5.0
@export var sol_minutes_max := 120.0
## Colony simulation ticks per real second. An engineering default to profile.
@export var sim_tick_hz := 5.0
## Most simulation ticks processed in one rendered frame; the remainder carries over, no time is dropped.
@export var max_ticks_per_frame := 25
## Host hazard integration step in unpaused real seconds, independent of the playable sol length.
@export_range(0.01, 0.2, 0.01) var hazard_step_seconds := 0.05
## Gameplay deadlines, not physiological predictions.
@export var exposure_lethal_seconds := 4.0
@export var exposure_safe_recovery_seconds := 2.0
@export_range(0.0, 1.0, 0.01) var suit_min_integrity := 0.5
## The explicit local exit vestibule uses a pressure proxy, not another colony gas-mass simulation.
@export var airlock_pressure_nominal_kpa := 101.3
@export var airlock_pressure_mars_kpa := 0.6
@export var airlock_pressure_unsafe_kpa := 70.0
@export var airlock_pressure_safe_kpa := 80.0
@export var airlock_pressure_loss_kpa_per_second := 200.0
@export var airlock_pressure_recovery_seconds := 5.0
## Phase of the sol a new game starts at (0 = midnight, 0.5 = noon).
@export_range(0.0, 1.0) var start_phase := 0.3

@export_group("Saving")
@export var autosave_seconds := 60.0
@export var backup_count := 2
@export var save_dir := "user://saves"
@export var save_name := "colony"

@export_group("Interaction")
## How close an actor must be to a station to act on it, in metres.
@export var interact_distance_m := 2.6
## Requests remembered per peer so a repeated request id returns its first result instead of running twice.
@export var remembered_requests := 256

@export_group("Hub")
## Med Bay safe switching/recovery area. Feet sit 4 cm above the measured room floor.
@export var hub_position := Vector3(-7.3, 0.04, -14.5)
@export var hub_radius_m := 6.0
## Collision-probed parking positions relative to the Med Bay hub (fourth avoids bedside equipment).
@export var crew_hub_offsets: Array[Vector3] = [Vector3(1.2, 0, 0), Vector3(0, 0, 1.2), Vector3(-1.2, 0, 0), Vector3(-0.3, 0, -1.2)]

@export_group("Player (initial tuning, Prompt 04)")
@export var fov_degrees := 72.0
@export var third_person_distance_m := 2.5
@export_range(0.0, 1.0) var suit_speed_factor := 0.8
## The suit check takes this long in real seconds; it does not scale with the sol length.
@export var suit_check_seconds := 1.0

@export_group("Recovery")
## Share of one active astronaut's daily food and water charged on recovery.
@export var recovery_cost_sols := 0.1


func clamp_sol_minutes(minutes: float) -> float:
	return clampf(minutes, sol_minutes_min, sol_minutes_max)
