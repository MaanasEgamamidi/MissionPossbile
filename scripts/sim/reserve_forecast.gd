class_name ReserveForecast
extends RefCounted
## How long the reserves last at the current flows, in game hours, and what the battery will hold at the next sunrise.
## Pure: it reads the state and never changes it. -1 means "not falling".
##
## Oxygen reserve, water and food: straight line at the net rate of the last tick (ColonyState.rates).
## Suits: tank charge / breathing rate, for every active character outside with the suit on.
## Battery: the sun matters, so the battery is stepped forward on a copy of its numbers with the loads as they are
## switched now and the sun as it will be (same panels, dust and trackers), for up to FORECAST_SOLS sols.

const FORECAST_SOLS := 3.0
## Step of the battery projection, game hours.
const STEP_HOURS := 0.05


static func compute(state: ColonyState, balance: GameBalance, clock: SolClock) -> Dictionary:
	var out := {}
	var battery := _battery(state, balance, clock.phase)
	out["battery_hours"] = battery.hours
	out["battery_at_sunrise_kwh"] = battery.at_sunrise
	out["hours_to_sunrise"] = battery.to_sunrise
	out["oxygen_hours"] = _linear_hours(state.store(&"oxygen_kg"), float(state.rates.get("oxygen_kg", 0.0)))
	out["water_hours"] = _linear_hours(state.store(&"water_l"), float(state.rates.get("water_l", 0.0)))
	out["food_hours"] = _linear_hours(state.store(&"food_meals"), float(state.rates.get("food_meals", 0.0)))
	var suits := {}
	for c in state.active_characters():
		if c.outside:
			var hours := -1.0
			if c.suit_on and balance.oxygen_kg_per_hour > 0.0:
				hours = LifeSupportModel.suit_kg(balance, c) / balance.oxygen_kg_per_hour
			elif not c.suit_on:
				hours = 0.0
			suits[String(c.id)] = hours
	out["suit_hours"] = suits

	var lines: Array[String] = []
	var battery_text := _lasts(float(out.battery_hours), clock) if float(out.battery_hours) >= 0.0 else "not running out in the next %.0f sols at this rate" % FORECAST_SOLS
	lines.append("Battery: %.0f kWh, %s" % [state.store(&"battery_kwh"), battery_text])
	lines.append("Battery at the next sunrise: about %.0f kWh" % float(out.battery_at_sunrise_kwh))
	lines.append("Oxygen reserve: %.1f kg, %s" % [state.store(&"oxygen_kg"), _lasts(float(out.oxygen_hours), clock)])
	lines.append("Water: %.0f L, %s" % [state.store(&"water_l"), _lasts(float(out.water_hours), clock)])
	lines.append("Food: %.1f meals, %s" % [state.store(&"food_meals"), _lasts(float(out.food_hours), clock)])
	for id: String in suits:
		var c := state.character(StringName(id))
		lines.append("Suit of %s: %.0f %%, %s" % [c.display_name, c.suit_charge, _lasts(float(suits[id]), clock)])
	out["text"] = lines
	return out


static func _linear_hours(amount: float, rate_per_hour: float) -> float:
	if rate_per_hour >= -1e-12:
		return -1.0
	return amount / -rate_per_hour


## Projects the battery forward. Returns {"hours": until empty, or -1 if it does not run out within FORECAST_SOLS, "at_sunrise": kWh, "to_sunrise": hours}.
static func _battery(state: ColonyState, balance: GameBalance, phase: float) -> Dictionary:
	var process := {"electrolyser": float(state.unit("electrolyser").get("kw", 0.0)), "co2_unit": float(state.unit("co2_unit").get("kw", 0.0))}
	var demand := 0.0
	for g in PowerModel.demand_groups(state, balance, process):
		demand += float(g.kw)
	var tracking := PowerModel.trackers_can_track(state, balance)
	var battery := state.store(&"battery_kwh")
	var cap := float(state.capacities.get(&"battery_kwh", 0.0))
	var to_sunrise := fposmod(PowerModel.SUNRISE - phase, 1.0) * GameConfig.SOL_HOURS
	if to_sunrise <= 1e-9:
		to_sunrise = GameConfig.SOL_HOURS
	var result := {"hours": -1.0, "at_sunrise": battery, "to_sunrise": to_sunrise}
	var t := 0.0
	var horizon := FORECAST_SOLS * GameConfig.SOL_HOURS
	var sunrise_done := false
	while t < horizon - 1e-9:
		var dt := minf(STEP_HOURS, horizon - t)
		if not sunrise_done and t + dt >= to_sunrise:
			dt = to_sunrise - t
		var p := fposmod(phase + (t + 0.5 * dt) / GameConfig.SOL_HOURS, 1.0)
		var solar := PowerModel.solar_kw(state, balance, p, tracking)
		if solar >= demand:
			var e_in := minf((solar - demand) * dt, balance.battery_charge_kw_max * dt)
			battery = minf(cap, battery + e_in * balance.battery_charge_efficiency)
		else:
			var draw := minf(demand - solar, balance.battery_discharge_kw_max) * dt
			if draw >= battery:
				var empty_at := t + (battery / draw) * dt
				battery = 0.0
				if result.hours < 0.0:
					result.hours = empty_at
			else:
				battery -= draw
		t += dt
		if not sunrise_done and t >= to_sunrise - 1e-9:
			sunrise_done = true
			result.at_sunrise = battery
	return result


## "lasts until about 06:30 tomorrow at this rate", or "not falling at this rate".
static func _lasts(hours: float, clock: SolClock) -> String:
	if hours < 0.0:
		return "not falling at this rate"
	if hours <= 0.0:
		return "empty now"
	var t := clock.phase * GameConfig.SOL_HOURS + hours
	var sols := int(floorf(t / GameConfig.SOL_HOURS))
	var h := fposmod(t, GameConfig.SOL_HOURS)
	var when := "%02d:%02d" % [int(floorf(h)), int(floorf(fposmod(h, 1.0) * 60.0))]
	var day := "today"
	if sols == 1:
		day = "tomorrow"
	elif sols > 1:
		day = "in %d sols" % sols
	return "lasts until about %s %s at this rate" % [when, day]
