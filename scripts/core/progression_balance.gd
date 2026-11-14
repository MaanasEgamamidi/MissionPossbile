class_name ProgressionBalance
extends Resource
## Numbers of the upgrade, knowledge and learning system (Prompt 08, part G). Every field says its evidence category:
##   balance  game tuning with no source. NEVER present a balance number as a NASA figure.
##   S02      the length of a sol (GameConfig.SOL_HOURS)
##   S08/S09  the mechanism an upgrade improves (ISS life support / MOXIE); the size of the improvement is balance.
## The same categories are listed per field in data/model_sources_progression.json.
## The energy and life-support models read these through ProgressionBalance.shared() when an upgrade is installed.

const PATH := "res://config/progression_balance.tres"

static var _shared: ProgressionBalance

@export_group("Parts cost of each card")
## balance: spare parts each upgrade card consumes when it is installed. The cheapest card of every sector costs 2, so
## the 10 starting parts pay for one card per sector. data/upgrades.json repeats these as "cost_parts".
@export var card_parts := {
	"energy_battery_reserve": 3, "energy_solar_tracking": 2, "energy_cleaner_automation": 4,
	"ls_water_reliability": 2, "ls_electrolysis": 3, "ls_co2_processing": 4, "ls_oxygen_monitoring": 3,
	"food_irrigation_reliability": 2, "food_nutrient_metering": 2, "food_scheduled_care": 3,
	"res_salvage_inspection": 2, "res_component_refurbishment": 2, "res_repeat_assembly": 3,
	"sci_instrument_calibration": 2, "sci_sample_comparison": 2, "sci_evidence_settings": 3,
}

@export_group("Energy upgrades")
## balance: energy_battery_reserve multiplies the battery capacity by this once, when it is installed (800 -> 1000 kWh).
@export var battery_capacity_factor := 1.25
## balance: with energy_battery_reserve, this share of the battery capacity is kept for life support. Room lights and
## greenhouse lights may not use it: they are switched off first when only the reserve is left.
@export_range(0.0, 1.0) var battery_life_support_reserve_fraction := 0.2
## balance: with energy_solar_tracking the tracker drives use this share of their normal power.
@export_range(0.0, 1.0) var tracking_drive_factor := 0.5
## balance: with energy_solar_tracking, panels that track give this times their normal output (+10 %).
@export var tracking_output_factor := 1.1
## balance (sol length S02): with energy_cleaner_automation a broken cleaner repairs itself after this many sols.
@export var cleaner_self_repair_sols := 1.0

@export_group("Life-support upgrades")
## balance (S08 mechanism: water recovery): with ls_water_reliability the recycler cleans this many more litres per hour.
@export var recycler_bonus_l_per_hour := 1.0
## balance: with ls_water_reliability the recycler's condition never drops below this.
@export_range(0.0, 1.0) var recycler_condition_floor := 0.8
## balance (S08 mechanism: electrolysis): with ls_electrolysis the electrolyser's top output is this times higher, at
## the same kWh per kg (water per kg stays the physics value).
@export var electrolysis_output_factor := 1.5
## balance (fiction scaled from S09): with ls_co2_processing the CO2-oxygen unit's top output is this times higher, at
## the same kWh per kg.
@export var co2_unit_output_factor := 1.5
## balance: with ls_oxygen_monitoring the oxygen reserve warning comes at this times the normal level (20 -> 30 kg).
@export var monitoring_reserve_warn_factor := 1.5
## balance: with ls_oxygen_monitoring the cabin oxygen warning comes this many kPa earlier (19 -> 20 kPa).
@export var monitoring_o2_warn_margin_kpa := 1.0
## balance: with ls_oxygen_monitoring the cabin CO2 warning comes this many kPa earlier (0.5 -> 0.4 kPa).
@export var monitoring_co2_warn_margin_kpa := 0.1

@export_group("Practical evidence")
## balance (contract): "output was low" means the panels gave less than this share of their clean output.
@export_range(0.0, 1.0) var low_output_share := 0.8
## balance (contract): "recovered" means the panels give more than this share of their clean output again.
@export_range(0.0, 1.0) var recovered_output_share := 0.95
## balance (contract, sol length S02): the recovery must be seen within this many sols of the fix.
@export var recovery_window_sols := 1.0
## balance (contract): game hours each oxygen process must run for ls_distinguish_inputs.
@export var process_run_hours := 1.0

@export_group("Exercise (body energy, not electricity)")
## balance: body energy (stamina, 0..100) one exercise session uses.
@export var exercise_stamina_cost := 25.0
## balance: conditioning (0..conditioning_max) one session adds.
@export var exercise_conditioning_gain := 0.1
## balance: most conditioning a crew member can have.
@export var conditioning_max := 1.0
## balance: extra body energy recovered per game hour at full conditioning (scaled by conditioning; 0 when untrained).
@export var conditioning_recovery_per_hour := 6.0


## The balance the game uses: res://config/progression_balance.tres if it exists, else the defaults above.
static func shared() -> ProgressionBalance:
	if _shared == null:
		if ResourceLoader.exists(PATH):
			_shared = load(PATH) as ProgressionBalance
		if _shared == null:
			_shared = ProgressionBalance.new()
	return _shared


## Replaces the shared balance (tests and tools). Pass null to go back to the default.
static func set_shared(b: ProgressionBalance) -> void:
	_shared = b


## Parts the card `id` costs, or -1 if this balance does not list it.
func parts_for(id: String) -> int:
	return int(card_parts.get(id, -1))
