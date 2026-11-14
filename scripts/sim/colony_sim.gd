class_name ColonySim
extends RefCounted
## One simulation tick of the colony model. Pure: it reads GameBalance, changes ColonyState, and knows nothing about
## nodes, input or the network. Every flow is `rate x game hours`, so the length of a sol in real minutes cannot
## create or destroy anything.
##
## Energy bookkeeping each tick (all kWh):
##   solar offered = solar_kw x dt        load wanted = load_kw x dt
##   solar feeds the load first; what is left charges the battery; what does not fit is curtailed (wasted);
##   load the sun cannot cover comes from the battery; what the battery cannot cover is unserved.
## So always: battery now = battery at start + ledger.solar_used_kwh - ledger.load_served_kwh.
## This is the simple placeholder model. The life-support and power milestones replace the rates, not the bookkeeping.

const LIFE_SUPPORT_ZONE := "Life Support"


## Share of peak solar output at a given sol phase: 0 at night, a half sine from sunrise (0.25) to sunset (0.75).
static func sun_factor(phase: float) -> float:
	if phase <= 0.25 or phase >= 0.75:
		return 0.0
	return sin(PI * (phase - 0.25) / 0.5)


## Advances `state` by `dt_hours` game hours at sol phase `phase`.
## Returns the ids of active characters whose health reached zero this tick (the session recovers them).
func step(state: ColonyState, balance: GameBalance, phase: float, dt_hours: float) -> Array[StringName]:
	var down: Array[StringName] = []
	if dt_hours <= 0.0:
		return down
	var crew := state.active_characters()
	var n := float(crew.size())
	var life_support_on := state.is_zone_powered(LIFE_SUPPORT_ZONE)

	# ---- power
	state.solar_kw = balance.solar_kw_peak * sun_factor(phase)
	var load_kw := balance.base_load_kw
	for zone: String in state.zones:
		if state.is_zone_powered(zone):
			load_kw += balance.load_of_zone(zone)
	if life_support_on:
		load_kw += balance.oxygen_generation_kw
	state.load_kw = load_kw

	var offered := state.solar_kw * dt_hours
	var wanted := load_kw * dt_hours
	var direct := minf(offered, wanted)
	var charged := state.add_to_store(&"battery_kwh", offered - direct)
	var curtailed := (offered - direct) - charged
	var discharged := -state.add_to_store(&"battery_kwh", -(wanted - direct))
	var unserved := (wanted - direct) - discharged
	var served_share := 1.0 if wanted <= 0.0 else (wanted - unserved) / wanted
	state.power_deficit = unserved > 1e-9
	state.ledger["solar_used_kwh"] += direct + charged
	state.ledger["solar_curtailed_kwh"] += curtailed
	state.ledger["load_served_kwh"] += direct + discharged
	state.ledger["load_unserved_kwh"] += unserved

	# ---- oxygen: make first, then breathe
	var plant_share := served_share if life_support_on else 0.0
	state.ledger["oxygen_made_kg"] += state.add_to_store(&"oxygen_kg", balance.oxygen_kg_per_hour_generated * dt_hours * plant_share)
	var oxygen_need := n * balance.oxygen_kg_per_hour * dt_hours
	var oxygen_got := -state.add_to_store(&"oxygen_kg", -oxygen_need)
	state.ledger["oxygen_used_kg"] += oxygen_got

	# ---- water: use, then return the recycled share
	var water_need := n * balance.water_l_per_hour * dt_hours
	var water_got := -state.add_to_store(&"water_l", -water_need)
	state.ledger["water_used_l"] += water_got
	state.ledger["water_recycled_l"] += state.add_to_store(&"water_l", water_got * balance.water_recycle_fraction * plant_share)

	# ---- food
	var food_need := n * balance.meals_per_sol / GameConfig.SOL_HOURS * dt_hours
	var food_got := -state.add_to_store(&"food_meals", -food_need)
	state.ledger["meals_eaten"] += food_got

	state.unmet["oxygen_kg"] = oxygen_need - oxygen_got
	state.unmet["water_l"] = water_need - water_got
	state.unmet["food_meals"] = food_need - food_got

	# ---- condition of active crew only; parked crew are frozen
	if n > 0.0:
		var loss := 0.0
		if oxygen_need > 0.0:
			loss += balance.health_loss_per_hour_no_oxygen * (oxygen_need - oxygen_got) / oxygen_need
		if water_need > 0.0:
			loss += balance.health_loss_per_hour_no_water * (water_need - water_got) / water_need
		if food_need > 0.0:
			loss += balance.health_loss_per_hour_no_food * (food_need - food_got) / food_need
		if loss > 0.0:
			for c in crew:
				if c.health > 0.0:
					c.health = maxf(0.0, c.health - loss * dt_hours)
					if c.health <= 0.0:
						down.append(c.id)
	return down
