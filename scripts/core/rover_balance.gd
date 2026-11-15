class_name RoverBalance
extends Resource
## Numbers for the shared rover (Prompt 10, part 1): stat curves per level, mass, energy use, the charger, reach
## distances, cargo masses, fallback geometry and the assembly challenge. Every field says its evidence category, and
## data/model_sources_rover.json lists the same:
##   fictional  fictional game tuning supported by real principles (more motor power -> higher top speed, more
##              battery -> more stored energy, friction x normal load -> grip, m*g*h -> climbing energy). These are NOT
##              NASA measurements of a crewed rover; no register entry gives rover specifications.
##   balance    game tuning with no source. NEVER present a balance number as a NASA figure.
##   map        read from the supplied map (data/colony_manifest.json), in Godot coordinates (x, z, -y of Blender).
##   S01        NASA NSSDCA Mars Fact Sheet (VERIFIED in docs/source_register.md): mean surface gravity 3.73 m/s^2.
## Times are GAME hours (one sol = GameConfig.SOL_HOURS). Distances are metres on the map.

## Mars mean surface gravity in m/s^2 (S01). A physical constant from the register, not tuning.
const MARS_GRAVITY := 3.73

## The numbers in use. Tests may replace it; the game uses the defaults below.
static var current: RoverBalance = null

@export_group("Stat curves (index 0 = level 1 ... index 4 = level 5)")
## Every curve has the upgrade plan's BIG-JUMP-FIRST shape (docs/revisions/UPGRADE_PATHS_PLAN.md 6.3): the first
## upgrade gives the biggest gain and each later one a smaller one (about 0, 40, 70, 88 and 100 % of the way from the
## level-1 to the level-5 value), so the first part spent on a module is the one the player feels most.
## fictional: top speed in m/s for the speed (drive motor) levels. A stronger motor reaches a higher speed. Game
## balance: real crewed rovers are slower (Apollo's LRV and NASA's pressurized-rover concepts drive about 2.8-3.6 m/s,
## 10-13 km/h), so only level 1 is a realistic speed; the higher ones make the small map quick to cross.
@export var top_speed_mps := PackedFloat32Array([3.0, 4.8, 6.2, 7.0, 7.5])
## fictional: drive motor power in kW for the speed levels (shown in the garage and used by the assembly checks).
@export var motor_power_kw := PackedFloat32Array([4.0, 7.2, 9.6, 11.0, 12.0])
## fictional: total push of the four wheels in N for the torque (gearbox) levels: climbing and pulling away with a load.
@export var drive_force_n := PackedFloat32Array([3000.0, 4200.0, 5100.0, 5650.0, 6000.0])
## fictional: battery capacity in kWh for the battery range levels (the fuel cell and RTG of the rover upgrade path
## come on top: see "Rover upgrade path" below).
@export var battery_capacity_kwh := PackedFloat32Array([20.0, 32.0, 42.0, 48.0, 52.0])
## fictional: cargo bay capacity in kg for the cargo levels. Never a passenger count: four seats in every build.
@export var cargo_capacity_kg := PackedFloat32Array([100.0, 240.0, 345.0, 410.0, 450.0])
## fictional: tyre-to-ground friction coefficient for the traction (tyre) levels. Grip = this x the normal load.
@export var traction_mu := PackedFloat32Array([0.45, 0.57, 0.66, 0.71, 0.75])

## The rover upgrade path: the "rover" track of data/area_levels.json, read with AreaLevels.level(state, "rover").
@export_group("Rover upgrade path")
## balance: from this rover level the cabin is pressurized and has a suitport (like NASA's Space Exploration Vehicle
## concept): seated crew breathe cabin air instead of suit oxygen and are sheltered from solar-storm radiation.
@export var cabin_level := 3
## balance: from this rover level a fuel-cell range extender rides along (hydrogen + oxygen -> water + electricity).
@export var fuel_cell_level := 4
## balance: usable energy of the full fuel-cell tanks, kWh (extra range on top of the battery).
@export var fuel_cell_kwh := 14.0
## fictional (principle): oxygen the fuel cell uses per kWh it delivers, kg. 2 H2 + O2 -> 2 H2O: 1 kg of hydrogen
## (33.3 kWh lower heating value) needs 8 kg of oxygen; at about 55 % cell efficiency that is ~18 kWh of electricity
## per 8 kg O2, so ~0.45 kg O2 per kWh. A full refill (14 kWh) takes ~6.3 kg O2 from the colony's oxygen store. The
## hydrogen side is not tracked: the game treats it as recovered from the base's electrolyser (which already splits
## water to make the oxygen), and the product water is not tracked either.
@export var fuel_cell_o2_kg_per_kwh := 0.45
## balance: the fuel cell feeds the battery at up to this power, kW (game hours), once the battery is below
## fuel_cell_start_fraction and the rover is not plugged in. It cannot outrun the motors at speed, so it extends range.
@export var fuel_cell_kw := 3.0
## balance: the range extender starts once the battery is below this share of its capacity.
@export_range(0.0, 1.0) var fuel_cell_start_fraction := 0.5
## balance: refill rate of the fuel-cell tanks at the garage charger while plugged in, kWh of fuel per game hour
## (so 8 x 0.45 = 3.6 kg O2 per game hour at most).
@export var fuel_cell_refill_kwh_per_hour := 8.0
## balance: the refill never takes the colony's oxygen store below this share of its capacity (the crew's air first).
@export_range(0.0, 1.0) var fuel_cell_o2_reserve_fraction := 0.25
## balance: from this rover level a small nuclear power cart (radioisotope generators, RTG) trickle-charges the rover
## battery, parked or driving, and the sample arm with a laser spectrometer can assay ore on site.
@export var rtg_level := 5
## balance: the RTG cart's electric power, kW (game hours). About three MMRTG-class generators (Curiosity's and
## Perseverance's MMRTG gives ~0.11 kW electric); far too little to drive on, enough to top the battery up slowly.
@export var rtg_kw := 0.3
## balance: from this rover level the sample arm (laser spectrometer, like ChemCam/SuperCam) can assay on site.
@export var sample_arm_level := 5

@export_group("Mass")
## fictional: empty rover with the level-1 modules, kg.
@export var chassis_mass_kg := 1400.0
## fictional: extra battery modules per battery level above 1, kg.
@export var battery_mass_per_level_kg := 40.0
## fictional: stronger cargo frame per cargo level above 1, kg.
@export var cargo_frame_mass_per_level_kg := 20.0
## balance: one crew member in a suit, kg (person plus suit and pack). Counted for every occupied seat.
@export var crew_member_kg := 150.0

@export_group("Energy")
## fictional: rolling resistance of the wheels on loose Mars ground (share of the weight that pushes back).
@export var rolling_resistance := 0.15
## fictional: share of battery energy that reaches the wheels (motor, gearbox, wiring losses).
@export_range(0.05, 1.0) var drivetrain_efficiency := 0.8
## balance: every metre driven or climbed on the small map uses the energy of this many metres. The playable map is
## about 150 m across, so without this a battery would never matter (the same idea as the short game sol).
@export var map_distance_factor := 60.0
## balance: the range estimate assumes the ground needs this much more energy than flat, firm ground (slopes, soft sand).
@export var range_terrain_factor := 1.3

@export_group("Charger")
## balance: power the garage charger takes from the colony battery, kW.
@export var charger_kw := 5.0
## fictional: share of that energy that reaches the rover battery (the rest is lost as heat).
@export_range(0.05, 1.0) var charger_efficiency := 0.9
## balance: the rover must be parked within this distance of the charger (the cable length), m.
@export var charge_radius_m := 7.0
## balance: charging pauses when the colony battery is at or below this share of its capacity (or the life-support
## reserve of the energy_battery_reserve upgrade, whichever is higher), so the base keeps power for the night.
@export_range(0.0, 1.0) var charge_reserve_fraction := 0.35

@export_group("Reach")
## balance: how close a character must be to the rover's centre to get in, load or unload, m: half the rover's length (3.1 m)
## plus the 2.6 m interaction reach, the same value as data/rover.json enter_distance_m (what the vehicle uses).
@export var rover_reach_m := 6.0
## balance: the rover counts as "in the garage" (for an assembly or refit) within this distance of the garage station, m.
@export var garage_radius_m := 6.0

@export_group("Cargo item masses (game values)")
## balance: mass of a carried item by its kind, kg. Salvaged parts ("salvaged_<part>") use salvaged_part_kg.
@export var item_mass_kg := {"supply_crate": 25.0, "sample": 2.0}
## balance: mass of one salvaged part, kg.
@export var salvaged_part_kg := 12.0
## balance: mass of an item of any other kind, kg.
@export var default_item_kg := 10.0

@export_group("Fallback geometry (used until data/rover.json gives the real one)")
## map: where the rover stands in the print garage (sf_rover's origin in data/colony_manifest.json, Godot coordinates).
@export var park_position := Vector3(8.3, 0.0, 23.0)
## map: the rover's heading there, degrees about the up axis (sf_rover is turned +90 degrees; its front faces +x).
@export var park_yaw_deg := 90.0
## balance: four seat positions in the rover's own frame (x across, y up, z along the rover, front = +z), m.
@export var seat_offsets: Array[Vector3] = [Vector3(-0.55, 1.2, 0.9), Vector3(0.55, 1.2, 0.9), Vector3(-0.55, 1.2, -0.3), Vector3(0.55, 1.2, -0.3)]
## balance: exit points beside the rover in its own frame, m (left front, right front, left rear, right rear, behind).
@export var exit_offsets: Array[Vector3] = [Vector3(-2.3, 0.0, 1.0), Vector3(2.3, 0.0, 1.0), Vector3(-2.3, 0.0, -1.0), Vector3(2.3, 0.0, -1.0), Vector3(0.0, 0.0, -3.6)]

@export_group("Assembly challenge")
## balance: at most this many changed stats are checked in one assembly or refit (the biggest changes first).
@export var challenge_max_stats := 3
## balance: battery voltages the examples use, V (one is picked per example).
@export var example_voltages := PackedInt32Array([96, 120, 144])
## balance: wheel radii the torque examples use, m.
@export var example_wheel_radii := PackedFloat32Array([0.4, 0.5])


## The numbers in use (the defaults unless a test set `current`).
static func get_current() -> RoverBalance:
	if current == null:
		current = RoverBalance.new()
	return current


## The value of a level table for `level` (1..5, clamped).
static func at_level(table: PackedFloat32Array, level: int) -> float:
	if table.is_empty():
		return 0.0
	return float(table[clampi(level, 1, table.size()) - 1])


## Mass of one item of `kind`, kg.
func mass_of_kind(kind: String) -> float:
	if kind.begins_with("salvaged_"):
		return salvaged_part_kg
	return float(item_mass_kg.get(kind, default_item_kg))
