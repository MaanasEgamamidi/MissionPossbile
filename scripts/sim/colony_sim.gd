class_name ColonySim
extends RefCounted
## One simulation tick of the colony model. Pure: it reads GameBalance, changes ColonyState, and knows nothing about
## nodes, input or the network. Every flow is `rate x game hours`, so the length of a sol in real minutes cannot
## create or destroy anything.
##
## Order inside a tick (each step only uses what the steps before it left):
##   1. drinking and washing (always first)
##   2. plan the water allocations and the two oxygen processes (they ask for the power their output needs)
##   3. power: solar, battery, automatic shedding by priority (PowerModel)
##   4. panel dust and the cleaner at sunrise
##   5. greenhouse water, electrolyser, CO2-oxygen unit, water recycler (LifeSupportModel)
##   6. cabin air: airlock losses, breathing, CO2 scrubber, regulator
##   7. suits of crew outside, food, health of active crew
##   8. alerts (a new alert is announced once through events.system_alert)
## Only active characters (controlled by a player) use anything; parked characters are frozen.

## Optional: where new alerts are announced. Set by SessionService.
var events: GameEvents
## Systems added by later milestones, run every tick. Each is an object with
##   func step(state: ColonyState, balance: GameBalance, phase: float, dt_hours: float, events: GameEvents) -> void
## pre_systems run first (weather sets dust_tau before solar power is worked out);
## post_systems run after water, oxygen and cabin air and before food and health (crops, automation).
var pre_systems: Array = []
var post_systems: Array = []


func set_events(p_events: GameEvents) -> void:
	events = p_events


## Advances `state` by `dt_hours` game hours from sol phase `phase`.
## Returns the ids of active characters whose health reached zero this tick (the session recovers them).
func step(state: ColonyState, balance: GameBalance, phase: float, dt_hours: float) -> Array[StringName]:
	var down: Array[StringName] = []
	if dt_hours <= 0.0:
		return down
	var dt := dt_hours
	var before := {}
	for k in ColonyState.STORE_KEYS:
		before[k] = state.store(k)
	var crew := state.active_characters()
	var inside := 0
	for c in crew:
		if not c.outside:
			inside += 1
	state.unmet = {"oxygen_kg": 0.0, "water_l": 0.0, "food_meals": 0.0}
	var mid_phase := fposmod(phase + 0.5 * dt / GameConfig.SOL_HOURS, 1.0)

	for system in pre_systems:
		system.step(state, balance, phase, dt, events)
	var water_share := _share(LifeSupportModel.use_water(state, balance, crew.size(), dt))
	var plan := LifeSupportModel.plan_processes(state, balance, dt)
	PowerModel.allocate(state, balance, mid_phase, dt, plan.kw)
	PowerModel.settle_dust(state, balance, phase, dt)
	LifeSupportModel.run_processes(state, balance, plan, dt)
	var o2_short := LifeSupportModel.run_cabin(state, balance, inside, dt)
	for system in post_systems:
		system.step(state, balance, phase, dt, events)

	var no_air := {}
	for c in crew:
		if c.outside:
			no_air[c.id] = LifeSupportModel.run_suit(state, balance, c, dt)
			o2_short += float(no_air[c.id]) * balance.oxygen_kg_per_hour * dt
	state.unmet["oxygen_kg"] = o2_short

	var food_need := float(crew.size()) * balance.meals_per_sol / GameConfig.SOL_HOURS * dt
	var food_got := -state.add_to_store(&"food_meals", -food_need)
	state.ledger["meals_eaten"] += food_got
	state.unmet["food_meals"] = food_need - food_got
	var food_share := 0.0 if food_need <= 0.0 else _share((food_need - food_got) / food_need)

	for c in crew:
		if c.health <= 0.0:
			continue
		var loss := LifeSupportModel.health_loss_per_hour(state, balance, c, float(no_air.get(c.id, 0.0)), water_share, food_share)
		if loss > 0.0:
			c.health = maxf(0.0, c.health - loss * dt)
			if c.health <= 0.0:
				down.append(c.id)

	for k in ColonyState.STORE_KEYS:
		state.rates[String(k)] = (state.store(k) - float(before[k])) / dt
	state.sim_hours += dt
	_update_alerts(state, balance, fposmod(phase + dt / GameConfig.SOL_HOURS, 1.0), no_air)
	return down


## An unmet share below 1e-9 is rounding in the store arithmetic, not a real shortage.
static func _share(x: float) -> float:
	return 0.0 if x < 1e-9 else x


## Recomputes the active alerts. An alert that was not active last tick is announced once.
func _update_alerts(state: ColonyState, balance: GameBalance, phase_end: float, no_air: Dictionary) -> void:
	var previous := {}
	for a: Dictionary in state.alerts:
		previous[String(a.id)] = a
	var fresh: Array = []
	for entry: Array in PowerModel.alerts(state, balance, phase_end) + LifeSupportModel.alerts(state, balance, no_air):
		var id := String(entry[0])
		var since := state.sim_hours
		if previous.has(id):
			since = float((previous[id] as Dictionary).since_hours)
		fresh.append({"id": id, "level": String(entry[1]), "text": String(entry[2]), "since_hours": since})
		if not previous.has(id) and events != null:
			events.system_alert.emit(StringName(id), StringName(entry[1]), String(entry[2]))
	# Greenhouse warnings (Prompt 08) join the list the panels read; CropSystem already announced each one once.
	for entry: Array in CropSystem.alerts(state):
		var crop_id := String(entry[0])
		var crop_since := float((previous[crop_id] as Dictionary).since_hours) if previous.has(crop_id) else state.sim_hours
		fresh.append({"id": crop_id, "level": String(entry[1]), "text": String(entry[2]), "since_hours": crop_since})
	state.alerts = fresh
