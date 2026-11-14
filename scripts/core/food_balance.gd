class_name FoodBalance
extends Resource
## Numbers of the greenhouse food model (Prompt 08, food part). Every field says its evidence category:
##   balance  game tuning with no source. NEVER present a balance number as a NASA figure.
##   physics  standard science
##   S11      NASA "Growing Plants in Space": lettuce grown in Veggie on the ISS (ISS analog, not Mars evidence)
## Crop numbers (cycle length, meals, water and nutrient use) live in data/crops.json, also marked "balance".
## The same categories are listed per field in data/model_sources_food.json.
## Rates are per GAME hour (one sol = GameConfig.SOL_HOURS game hours). Crop cycles are TIME-COMPRESSED: a few sols
## here stand for weeks to months on Earth.

## Where the crop table is read from.
const CROPS_PATH := "res://data/crops.json"

@export_group("Light")
## Zone whose lighting circuit is the grow lights. balance (game layout: the Greenhouse circuit lights every bed).
@export var light_zone := "Greenhouse"

@export_group("Soil water")
## Water a bed's soil (or the hydroponic tank) holds when full, litres. balance
@export var bed_water_capacity_l := 6.0
## Soil water share at or above which plants grow at full speed (0..1); below it they droop (the wilting symptom). balance
@export var water_good := 0.5
## Soil water share below which the colony warns that a bed is drying out (0..1). balance
@export var water_low := 0.25
## Most water a clean drip line takes into one bed, litres per game hour. balance
@export var drip_max_l_per_hour := 1.0
## How much a drip line clogs each sol (share of its flow lost). balance: the watering chore.
@export var drip_clog_per_sol := 0.25
## Game hours a bed may stay completely dry before the plant wilts for good (one sol). balance
@export var wilt_after_dry_hours := 24.6598

@export_group("Nutrients")
## Nutrient level of fresh growing mix when a bed is planted (0..1). balance
@export var nutrients_at_planting := 0.7
## Nutrient level at or above which plants grow at full speed (bottom of the good band). balance
@export var nutrient_good_low := 0.4
## Top of the good band (0..1). balance: above it plants do not grow faster; the feed is only used up later.
@export var nutrient_good_high := 0.8
## Share of full speed a plant still grows at with no nutrients at all (it lives on what it has stored). balance
@export var nutrient_floor_factor := 0.15
## Level the nutrient meter holds when food_nutrient_metering is installed (inside the good band). balance
@export var metering_target := 0.6

@export_group("Diagnosis")
## The growth rate must rise by at least this share over the rate measured at inspection to count as a response. balance
@export var response_rise := 0.1
## Game hours after a change in which a response is looked for (one sol). balance
@export var trial_window_hours := 24.6598

@export_group("Scheduled care (food_scheduled_care)")
## Greenhouse water the schedule sends per planted bed when less is allocated, litres per game hour. balance
@export var schedule_l_per_bed_hour := 0.35
## Time of day (sol phase 0..1) the schedule flushes every drip line once per sol. balance
@export var schedule_flush_phase := 0.3

static var _shared: FoodBalance
static var _crops: Dictionary = {}


## The food numbers the colony uses (one shared copy; tests may change it and call reset_shared() after).
static func shared() -> FoodBalance:
	if _shared == null:
		_shared = FoodBalance.new()
	return _shared


## Puts the shared numbers back to their defaults.
static func reset_shared() -> void:
	_shared = FoodBalance.new()


## The crop table from data/crops.json: crop id -> record (see that file). Read once.
static func crops() -> Dictionary:
	if _crops.is_empty() and FileAccess.file_exists(CROPS_PATH):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CROPS_PATH))
		if data is Dictionary and (data as Dictionary).get("crops", null) is Dictionary:
			_crops = data.crops
	return _crops


## One crop's record, or {} if unknown.
static func crop(id: String) -> Dictionary:
	return crops().get(id, {}) as Dictionary


## Growth per game hour at full speed for a crop (progress 0..1 per hour): 1 / (cycle sols x sol hours).
static func base_rate(crop_id: String) -> float:
	var sols := float(crop(crop_id).get("cycle_sols", 0.0))
	return 0.0 if sols <= 0.0 else 1.0 / (sols * GameConfig.SOL_HOURS)


## Water factor 0..1: full speed at `water_good` or more, slower below, stopped when dry.
func water_factor(water_share: float) -> float:
	return clampf(water_share / water_good, 0.0, 1.0) if water_good > 0.0 else 1.0


## Nutrient factor: full speed in the good band or above, down to `nutrient_floor_factor` with none.
func nutrient_factor(level: float) -> float:
	if nutrient_good_low <= 0.0 or level >= nutrient_good_low:
		return 1.0
	return nutrient_floor_factor + (1.0 - nutrient_floor_factor) * clampf(level / nutrient_good_low, 0.0, 1.0)
