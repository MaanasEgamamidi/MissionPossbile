class_name ScienceBalance
extends Resource
## Numbers for the field-sample science and salvage-fabrication systems (Prompt 08, Part S). Every field says its
## evidence category, and data/model_sources_science.json lists the same:
##   balance       game tuning with no source. NEVER present a balance number as a NASA figure.
##   illustrative  a made-up value shown in place of a real measurement (for example a mineral share).
##   S06           PDS Geosciences Node page for MSL CheMin: it supports only the mission, instrument, site and archive
##                 data set of the lab reference, and that CheMin measures mineral abundance by X-ray diffraction. It
##                 holds no mineral values, so every mineral number in the game is illustrative.
## Times are GAME hours (one sol = GameConfig.SOL_HOURS), so the real length of a sol never changes them.

## The numbers in use. Tests may replace it; the game uses the defaults below.
static var current: ScienceBalance = null

@export_group("Field samples")
## balance: samples one site can give before it is used up (keeps one site from filling every pack).
@export var samples_per_site := 3
## balance: dust in the air (optical depth) below which the sky is written as "clear" on the sample label.
@export var clear_sky_tau := 0.6
## balance: dust in the air above which the sky is written as "dusty" on the sample label.
@export var dusty_sky_tau := 1.0

@export_group("Lab comparison")
## illustrative: plus-or-minus on every mineral share the glovebox lab shows, in percentage points.
@export var mineral_uncertainty_pct := 6.0
## illustrative: the same after the instrument calibration upgrade (sci_instrument_calibration).
@export var calibrated_mineral_uncertainty_pct := 2.0
## balance: plus-or-minus on the nutrient setting a lab result suggests (0..1 scale).
@export var result_uncertainty := 0.08
## balance: the same after the instrument calibration upgrade (sci_instrument_calibration).
@export var calibrated_result_uncertainty := 0.03
## balance (made up for the game): nutrient setting for a bed mixed with dark volcanic sand, which adds little plant food.
@export var nutrient_setting_volcanic := 0.6
## balance (made up for the game): nutrient setting for a bed mixed with clay-rich soil, which holds on to plant food.
@export var nutrient_setting_clay := 0.45
## balance (made up for the game): nutrient setting for a bed mixed with salty sulfate crust: less plant food, so the
## mix does not get too salty.
@export var nutrient_setting_sulfate := 0.3

@export_group("Salvage and the workbench")
## balance: parts one donor can give (the rest stay as they are).
@export var parts_per_donor := 1
## balance: the same after the component refurbishment upgrade (res_component_refurbishment): one more.
@export var parts_per_donor_upgraded := 2
## balance: game hours a salvaged part needs on the workbench before its bench test.
@export var refurbish_hours := 2.0
## balance: the same after the component refurbishment upgrade (res_component_refurbishment).
@export var refurbish_hours_upgraded := 1.0
## balance: working components one refurbished part gives (one in, one out: no matter is made).
@export var components_per_part := 1


## The numbers in use (the defaults unless a test set `current`).
static func get_current() -> ScienceBalance:
	if current == null:
		current = ScienceBalance.new()
	return current


## Nutrient setting (0..1) for a rock type id from data/samples.json; -1 if unknown.
func nutrient_setting_for(rock_type: String) -> float:
	match rock_type:
		"volcanic": return nutrient_setting_volcanic
		"clay": return nutrient_setting_clay
		"sulfate": return nutrient_setting_sulfate
	return -1.0
