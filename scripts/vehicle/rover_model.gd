class_name RoverModel
extends RefCounted
## The shared rover's numbers (Prompt 10): levels, part costs, resulting stats and energy use. Pure functions over
## `state.rover`, so the garage panel, the host's actions, the vehicle body and the tutorial all read one model.
## INTERFACE STUB written before the parallel work; the rover-economy worker owns this file and fills it in.
##
## state.rover (plain JSON, saved and replicated):
##   built: bool                 assembled at the garage by the field engineer
##   levels: {stat: 1..5}        for STATS
##   battery_kwh: float          stored energy, never refilled by a refit
##   cargo: [item ids]           items loaded in the cargo bay
##   seats: ["", "", "", ""]     character ids; index 0 is the driver, 1..3 passengers
##   pose: {"position": [x, y, z], "quat": [x, y, z, w]}   last pose reported by the driver (saved)

const STATS: PackedStringArray = ["speed", "torque", "range", "cargo", "traction"]
const SEATS := 4
const MAX_LEVEL := 5


## Fills missing rover fields with defaults (older saves, new games).
static func ensure(state: ColonyState) -> void:
	var r := state.rover
	if not r.has("levels"):
		r["levels"] = {}
	for s: String in STATS:
		if not (r["levels"] as Dictionary).has(s):
			r["levels"][s] = 1
	if not r.has("built"):
		r["built"] = false
	if not r.has("battery_kwh"):
		r["battery_kwh"] = 0.0
	if not r.has("cargo"):
		r["cargo"] = []
	if not r.has("seats") or (r["seats"] as Array).size() != SEATS:
		r["seats"] = ["", "", "", ""]


## Parts needed to raise a stat from `level` to `level + 1` (approved: 1, 2, 3, 4).
static func step_cost(level: int) -> int:
	return clampi(level, 1, MAX_LEVEL - 1)


## Parts invested in these levels above the base equipment.
static func invested(levels: Dictionary) -> int:
	var total := 0
	for s: String in STATS:
		for l in range(1, int(levels.get(s, 1))):
			total += step_cost(l)
	return total


## Resulting stats for these levels and this cargo mass. Keys (units in the names): top_speed_mps, drive_force_n,
## battery_capacity_kwh, cargo_capacity_kg, traction_mu, mass_kg, range_km.
static func stats(_levels: Dictionary, _cargo_kg: float) -> Dictionary:
	return {"top_speed_mps": 3.0, "drive_force_n": 1500.0, "battery_capacity_kwh": 10.0, "cargo_capacity_kg": 100.0,
		"traction_mu": 0.6, "mass_kg": 900.0, "range_km": 5.0}


## Energy in kWh for driving `distance_m` with `climb_m` of net height gain (negative climb recovers nothing).
static func energy_kwh_for_move(_levels: Dictionary, _cargo_kg: float, distance_m: float, _climb_m: float) -> float:
	return maxf(0.0, distance_m) * 0.0002


## Mass of the items in the cargo bay.
static func cargo_mass_kg(_state: ColonyState) -> float:
	return 0.0
