class_name GameBalance
extends Resource
## Game configuration for the colony model. Every rate, capacity, timer and scaled hardware figure lives here, and
## each one says its evidence category:
##   physics  standard science (stoichiometry, ideal gas law); no register id needed
##   S08      ISS life support (NASA ECLSS page): water electrolysis, CO2 removal with molecular sieves, ~90 % water recovery
##   S09      MOXIE on Mars (NASA JPL release): oxygen from Mars CO2, best 12 g/h, 98 % purity.
##            A colony-size unit is FICTION SCALED FROM S09, not a NASA figure.
##   S01/S02  Mars gravity and the length of a sol (see GameConfig)
##   S20      NASA Life Support Baseline Values and Assumptions Document (BVAD), NASA/TP-2015-218570/REV2, Feb 2022.
##            Crew use per crew member per day (kg/CM-d) and ISS power and battery reference values.
##   balance  game tuning with no source. NEVER present a balance number as a NASA figure.
## The same categories are listed per field in data/model_sources.json; S20 is in docs/source_register.md section 11.
## Resource rates are per GAME hour (one sol = GameConfig.SOL_HOURS game hours), so the real length of a sol never
## changes resource use per sol. Equipment maintenance explicitly uses unpaused REAL seconds instead.
## Time base: one game hour is one hour of colony time (an Earth hour, the unit NASA uses). A sol holds 24.6598 game
## hours (S02), so a NASA per-day figure becomes a per-game-hour rate by dividing by 24, and one sol uses
## 24.6598 / 24 = 1.0275 NASA days. With the default 20-minute sol, one game hour passes in 48.7 real seconds, but no
## resource rate is ever per real second (S01 suit exposure is the separate real-second rule in SessionService).
## kW is a rate of energy use, kWh an amount; they are never mixed.

# ---- physics constants (not tuning)
## Water used per kg of oxygen made by electrolysis: 2 H2O -> 2 H2 + O2, 36 g of water gives 32 g of oxygen. (physics)
const WATER_KG_PER_KG_O2 := 1.126
## Share of split water that leaves as hydrogen: 2 g of hydrogen in every 18 g of water. (physics)
const HYDROGEN_PER_KG_WATER := 2.0 / 18.0
## CO2-oxygen unit: 2 CO2 -> 2 CO + O2, so 88 g CO2 in, 56 g CO vented and 32 g O2 out. (physics)
const CO2_KG_PER_KG_O2 := 88.0 / 32.0
const CO_KG_PER_KG_O2 := 56.0 / 32.0
## Gas constant J/(mol K) and molar masses kg/mol for p = m / M x R x T / V. (physics)
const GAS_R := 8.314
const MOLAR_O2 := 0.032
const MOLAR_N2 := 0.028
const MOLAR_CO2 := 0.044
## Hours in the day NASA's per-day crew figures use. (definition)
const HOURS_PER_DAY := 24.0
## Food energy units. (physics)
const KJ_PER_KCAL := 4.184
## Plants: CO2 + H2O -> CH2O + O2, so 44 g of CO2 is taken up for every 32 g of O2 given off. (physics; S20 Table 4-91
## lettuce 10.70 g CO2 per 7.78 g O2 per m2 per day agrees)
const PLANT_CO2_KG_PER_KG_O2 := 44.0 / 32.0

# ---- NASA per crew member per day (S20 BVAD Rev2, 82 kg reference crew member). The game rates below derive from these.
## NASA: S20 Table 3-31 oxygen consumed 0.895 kg/CM-d
const NASA_O2_KG_PER_CREW_DAY := 0.895
## NASA: S20 Table 3-31 carbon dioxide load 1.085 kg/CM-d
const NASA_CO2_KG_PER_CREW_DAY := 1.085
## NASA: S20 Table 4-20 Early Planetary Base total water consumption 4.48 kg/CM-d = drinking 2.00 + food rehydration
## 0.50 + urinal flush 0.50 + personal hygiene 0.40 + hand wash 1.08 (1 kg of water = 1 L)
const NASA_WATER_KG_PER_CREW_DAY := 4.48
## NASA: S20 Table 3-31 food consumed, energy content 12.778 MJ/CM-d (3,054 kcal)
const NASA_FOOD_MJ_PER_CREW_DAY := 12.778
## NASA: S20 section 3.3.5 (Table 3-31 notes) 1.56 kg/CM-d of food eaten at 48.7 % water
const NASA_FOOD_KG_PER_CREW_DAY := 1.56
## NASA: S20 Table 3-31 food solids 0.800 kg/CM-d (dry, without packaging)
const NASA_FOOD_DRY_KG_PER_CREW_DAY := 0.8
## NASA: S20 Table 3-2 average ECLSS power on the International Space Station 5.31 kW (whole station crew). A
## cross-check for the game's life-support loads, not a game value.
const NASA_ISS_ECLSS_KW := 5.31

@export_group("Starting stores")
## balance: fiction 2080 battery bank, 90 % charged at arrival.
@export var battery_kwh_start := 630.0
## balance (sized with S20): usable energy of the fiction 2080 battery bank. Sized so the battery visibly falls at
## night (the arrival loads of 23.1 kW take 41 % of it in one 12.3 h night) and a colony that leaves every light on
## and never cleans the panels runs it flat on its fifth night, while a careful one (about 9 kW at night) uses 16 %.
## A restored colony with every light on still gains over a sol from 300 kWh (it must hold 300 + 50 + one 337 kWh
## wasteful night). For scale: 700 kWh usable is 1,167 kWh of lithium-ion cells used to the 60 % depth of discharge
## per cycle (S20 Table 3-17, 1,500 cycles), about 7.8 t of cells at 150 Wh/kg (Table 3-17: 100 to 150 Wh/kg).
@export var battery_kwh_capacity := 700.0
## balance
@export var water_l_start := 900.0
## balance
@export var water_l_capacity := 2000.0
## balance: used water waiting for the recycler at arrival.
@export var wastewater_l_start := 20.0
## balance
@export var wastewater_l_capacity := 400.0
## balance: the oxygen reserve (stored tanks), not the cabin air.
@export var oxygen_kg_start := 60.0
## balance
@export var oxygen_kg_capacity := 150.0
## balance: nitrogen tanks that top up cabin air after airlock losses.
@export var n2_reserve_kg_start := 60.0
## balance
@export var n2_reserve_kg_capacity := 120.0
## balance
@export var food_meals_start := 96.0
## balance
@export var food_meals_capacity := 400.0
## balance
@export var parts_start := 10

@export_group("Solar (12 sun trackers)")
## balance (fiction 2080 array): output of all 12 trackers together at noon, clean, tracking, default sky. Each tracker
## has 1/12 of it. For scale only: sunlight above Mars is 586.2 W/m2 (S01), so 100 kW needs several hundred square
## metres of panels. Solar gives exactly 0 kW from sunset to sunrise (PowerModel.sun_term); the night is half a sol,
## 12.33 game hours (S02 sol length / 2, the equator at equinox), 10 real minutes at the default 20-minute sol.
@export var solar_kw_peak := 100.0
## balance: dust in the air at the start (optical depth). The weather milestone will drive state.dust_tau.
@export var dust_tau_default := 0.5
## balance with mechanism: dust in the air blocks sunlight; output x exp(-factor x tau), normalised to 1 at the default.
@export var dust_tau_factor := 0.6
## balance: share of a panel covered by settled dust per sol at the default sky (scaled by dust_tau / default).
@export var dust_deposit_per_sol := 0.02
## balance: panel dust at arrival (part of the arrival restoration).
@export_range(0.0, 1.0) var panel_dust_start := 0.45
## balance: the automatic cleaner has failed at arrival.
@export_range(0.0, 1.0) var cleaner_condition_start := 0.0

@export_group("Battery")
## balance
@export var battery_charge_kw_max := 80.0
## balance
@export var battery_discharge_kw_max := 45.0
## balance: energy stored = energy in x efficiency; the rest is ledgered as battery_loss_kwh.
@export_range(0.0, 1.0) var battery_charge_efficiency := 0.9
## balance: warn below this share of capacity.
@export_range(0.0, 1.0) var battery_warn_fraction := 0.3

@export_group("Power loads (kW)")
## Night loads at arrival (every room on, oxygen machines off): base 4 + critical room lights 1.2 + other room lights
## 5.2 + greenhouse lights 9 + trackers 0.6 + recycler 1 + scrubber 1.5 + fans 0.6 = 23.1 kW, 285 kWh per night.
## Careful night (only the critical room lights, greenhouse lights off): 8.9 kW, 110 kWh per night.
## Life-support machines (scrubber, fans, recycler, electrolyser at full rate) come to 4.3 kW for 4 crew, about
## 1.1 kW per crew member; ISS ECLSS averages 5.31 kW (S20 Table 3-2) for its larger crew, so the scale is realistic.
## The individual numbers stay balance.
## balance: control and heating; stays on whatever the room switches say.
@export var base_load_kw := 4.0
## balance: lights of each zone when its switch is on. Unknown zones use `zone_load_default_kw`.
@export var zone_load_kw := {"Greenhouse": 9.0, "Hangar bay": 1.0, "Dome plaza": 0.8, "Garden dome": 0.8, "Exterior": 0.6,
	"Command Room": 0.4, "Med Bay": 0.4, "Life Support": 0.3, "Power Room": 0.3}
## balance
@export var zone_load_default_kw := 0.2
## balance: room lights that count as part of the base load (shed last). Other rooms are "non-critical room lights".
@export var critical_light_zones := PackedStringArray(["Life Support", "Power Room", "Airlock", "Med Bay"])
## balance: drives of all 12 sun trackers together.
@export var tracker_drive_kw := 0.6
## balance
@export var cleaner_kw := 0.2
## balance
@export var recycler_kw := 1.0
## balance
@export var scrubber_kw := 1.5
## balance
@export var cabin_fans_kw := 0.6
## balance: equipment below this condition does not run.
@export_range(0.0, 1.0) var equipment_min_condition := 0.5

@export_group("Water")
## NASA: S20 Table 4-20 4.48 kg/CM-d (Early Planetary Base: drinking, food rehydration, flush, hygiene, hand wash)
## / 24 h = 0.1867 L per active astronaut per game hour, 4.60 L per sol. Was 0.25 L/h (balance).
@export var water_l_per_hour := NASA_WATER_KG_PER_CREW_DAY / HOURS_PER_DAY
## NASA-derived (S20): share of used water that returns as wastewater; the rest leaves in breath, sweat and solid
## waste. S20 Table 4-21 ISS column: 3.77 kg/CM-d of wastewater for 4.45 kg/CM-d of water in (Table 4-20 ISS 3.20 drink,
## food water, flush and hygiene + Table 3-31 water in food 0.76 + metabolic water 0.49): 3.77 / 4.45 = 0.85.
@export_range(0.0, 1.0) var water_to_wastewater := 0.85
## balance: clean water kept for drinking; allocations never take the store below it.
@export var water_reserve_l := 100.0
## balance
@export var recycler_l_per_hour := 3.0
## S08 (ISS water recovery "about 90 percent"): share of cleaned wastewater returned as clean water; the rest is brine.
@export_range(0.0, 1.0) var recycler_recovery := 0.90
## balance: a recycler below this condition makes less clean water (quality = condition / this value).
@export_range(0.0, 1.0) var recycler_good_condition := 0.8
## balance: the electrolyser stops if the water quality is below this.
@export_range(0.0, 1.0) var electrolyser_min_quality := 0.9
## balance: warn when wastewater fills this share of its tank.
@export_range(0.0, 1.0) var wastewater_warn_fraction := 0.8

@export_group("Oxygen production")
## balance (S08 mechanism: electrolysis of water).
@export var electrolysis_o2_kg_per_hour := 0.2
## balance (above the physics minimum of about 4.1 kWh per kg O2).
@export var electrolysis_kwh_per_kg_o2 := 6.0
## fiction scaled from S09: about 12.5 x MOXIE's best 12 g/h. A colony-size unit is fiction.
@export var co2_unit_o2_kg_per_hour := 0.15
## balance: more energy per kg than electrolysis, but it needs no water.
@export var co2_unit_kwh_per_kg_o2 := 20.0
## balance: warn when the oxygen reserve is below this.
@export var oxygen_reserve_warn_kg := 20.0

@export_group("Cabin air")
## balance (fiction): one pressurised volume for the whole habitat.
@export var cabin_volume_m3 := 400.0
## balance
@export var cabin_temperature_k := 295.0
## balance: Earth-like cabin.
@export var o2_setpoint_kpa := 21.0
## balance: Earth-like cabin.
@export var n2_setpoint_kpa := 79.0
## balance
@export var co2_start_kpa := 0.1
## balance: most oxygen or nitrogen the regulator releases per hour (each gas).
@export var regulator_kg_per_hour := 3.0
## balance (S08 mechanism: molecular sieves): most CO2 removed per hour with the cabin fans running.
@export var scrubber_co2_kg_per_hour := 0.4
## balance: the scrubber does not pull CO2 below this.
@export var scrubber_floor_kpa := 0.1
## balance: share of scrubber capacity left when the cabin fans are not running.
@export_range(0.0, 1.0) var fans_off_scrubber_share := 0.25
## balance
@export var co2_warn_kpa := 0.5
## balance: above this, CO2 harms the crew.
@export var co2_danger_kpa := 1.0
## balance
@export var o2_warn_kpa := 19.0
## balance: below this, low oxygen harms the crew.
@export var o2_low_kpa := 16.0
## balance
@export var pressure_warn_kpa := 90.0
## balance: cabin air lost each time the airlock cycles (mixed in proportion).
@export var airlock_cycle_loss_kg := 2.0
## balance
@export var n2_reserve_warn_kg := 15.0

@export_group("Per active astronaut")
## NASA: S20 Table 3-31 oxygen consumed 0.895 kg/CM-d / 24 h = 0.03729 kg per game hour (was 0.035, balance).
## Breathed from the cabin indoors and from the suit tank outside, never both in the same tick.
@export var oxygen_kg_per_hour := NASA_O2_KG_PER_CREW_DAY / HOURS_PER_DAY
## NASA: S20 Table 3-31 carbon dioxide load 1.085 kg/CM-d / 24 h = 0.04521 kg per game hour (was 0.042, balance).
@export var co2_kg_per_hour := NASA_CO2_KG_PER_CREW_DAY / HOURS_PER_DAY
## balance (game unit): meals eaten per sol. What a meal holds comes from NASA: see meal_mj() and meal_kg(); 3 meals
## per sol are S20's 12.778 MJ and 1.56 kg per day times 24.6598 / 24, so each meal is 4.38 MJ (1,046 kcal), 0.53 kg.
@export var meals_per_sol := 3.0
## balance: suit tank size (suit_charge is 0..100 % of this).
@export var suit_o2_capacity_kg := 0.4
## balance: warn when a suit outside is below this charge (%).
@export var suit_warn_charge := 25.0

@export_group("Condition")
## balance: health points lost per game hour at the worst; each is scaled by how bad the problem is.
@export var health_loss_per_hour_low_o2 := 40.0
@export var health_loss_per_hour_co2 := 20.0
@export var health_loss_per_hour_no_air := 25.0
@export var health_loss_per_hour_no_water := 6.0
@export var health_loss_per_hour_no_food := 3.0
## balance: health a character has after being recovered at the hub.
@export var recovery_health := 50.0

@export_group("Carrying")
## balance
@export var cargo_slots := 6

@export_group("Equipment maintenance (real seconds)")
## balance: the authoritative session is the single owner of operational wear. No room/panel ticker is used.
@export var maintenance_enabled := true
## balance: condition lost per unpaused real second; 1 -> 0.75 at 120 s and 0.5 at 240 s before repair grace.
@export var maintenance_wear_per_second := 1.0 / 480.0
## balance: a warning threshold, independent of the first-repair narrative milestone.
@export_range(0.0, 1.0) var maintenance_warning_condition := 0.75
## balance: a maintenance fault advances its generation once at this condition.
@export_range(0.0, 1.0) var maintenance_fault_condition := 0.5
## balance: a role-checked equipment maintenance job, not a replacement for a future room minigame.
@export var maintenance_repair_seconds := 20.0
## balance: safe grace after repair before wear resumes; the remaining grace is saved.
@export var maintenance_repair_cooldown_seconds := 15.0
## balance: only the already repairable legacy panel cleaner receives additional condition wear.
@export var cleaner_wear_per_second := 1.0 / 480.0


func load_of_zone(zone: String) -> float:
	return float(zone_load_kw.get(zone, zone_load_default_kw))


## A NASA per-day amount turned into what one crew member uses in one sol (24.6598 / 24 = 1.0275 days).
static func per_sol_from_per_day(per_day: float) -> float:
	return per_day * GameConfig.SOL_HOURS / HOURS_PER_DAY


## Food energy in one meal, MJ: one sol of S20's 12.778 MJ/CM-d split into meals_per_sol meals.
func meal_mj() -> float:
	return per_sol_from_per_day(NASA_FOOD_MJ_PER_CREW_DAY) / maxf(meals_per_sol, 1e-9)


## Food energy in one meal, kcal (about 1,046 with 3 meals per sol).
func meal_kcal() -> float:
	return meal_mj() * 1000.0 / KJ_PER_KCAL


## Food eaten in one meal, kg as eaten (S20: 1.56 kg/CM-d, 48.7 % water).
func meal_kg() -> float:
	return per_sol_from_per_day(NASA_FOOD_KG_PER_CREW_DAY) / maxf(meals_per_sol, 1e-9)


## Kilograms of a gas that give `kpa` in the cabin (ideal gas law, physics).
func gas_kg_for_kpa(kpa: float, molar_mass: float) -> float:
	return kpa * 1000.0 * cabin_volume_m3 * molar_mass / (GAS_R * cabin_temperature_k)


## Partial pressure in kPa of `kg` of a gas in the cabin (ideal gas law, physics).
func gas_kpa(kg: float, molar_mass: float) -> float:
	return kg / molar_mass * GAS_R * cabin_temperature_k / cabin_volume_m3 / 1000.0
