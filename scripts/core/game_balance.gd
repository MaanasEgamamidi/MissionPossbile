class_name GameBalance
extends Resource
## Designer balance values. Every number here is GAME TUNING, not a measurement and not a NASA specification.
## Rates are per GAME hour (one sol = GameConfig.SOL_HOURS game hours), so changing how many real minutes a sol takes
## never changes how much is produced or used per sol. Prompt 07 replaces the simple flows below with the full model.

@export_group("Starting stores")
@export var battery_kwh_start := 180.0
@export var battery_kwh_capacity := 400.0
@export var water_l_start := 900.0
@export var water_l_capacity := 2000.0
@export var oxygen_kg_start := 60.0
@export var oxygen_kg_capacity := 150.0
@export var food_meals_start := 96.0
@export var food_meals_capacity := 400.0
@export var parts_start := 10

@export_group("Power (kW)")
## Array output at local noon with clean panels.
@export var solar_kw_peak := 60.0
## Load that stays on whatever the room switches say: life support, pumps, control.
@export var base_load_kw := 6.0
## Load of each lighting zone when its power is on. Keyed by zone name; unknown zones use `zone_load_default_kw`.
@export var zone_load_kw := {"Greenhouse": 9.0, "Hangar bay": 5.0, "Power Room": 2.0, "Life Support": 4.0, "Command Room": 3.0, "Med Bay": 3.0}
@export var zone_load_default_kw := 1.5

@export_group("Life support, per active astronaut")
@export var oxygen_kg_per_hour := 0.035
@export var water_l_per_hour := 0.16
@export var meals_per_sol := 3.0
## Share of used water returned by recycling while life support has power.
@export_range(0.0, 1.0) var water_recycle_fraction := 0.85
## Oxygen made per hour while life support has power.
@export var oxygen_kg_per_hour_generated := 0.2
## Electrical draw of oxygen generation while it runs.
@export var oxygen_generation_kw := 3.0

@export_group("Condition (placeholder until the life-support milestone)")
## Health points lost per game hour while a need is completely unmet; scaled by the unmet share.
@export var health_loss_per_hour_no_oxygen := 60.0
@export var health_loss_per_hour_no_water := 6.0
@export var health_loss_per_hour_no_food := 3.0
## Health a character has after being recovered at the hub.
@export var recovery_health := 50.0

@export_group("Carrying")
@export var cargo_slots := 6


func load_of_zone(zone: String) -> float:
	return float(zone_load_kw.get(zone, zone_load_default_kw))
