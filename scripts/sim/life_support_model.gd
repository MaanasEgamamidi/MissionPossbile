class_name LifeSupportModel
extends RefCounted
## Water, the two oxygen processes, cabin air and suits. Pure functions on ColonyState; no nodes.
##
## Water stores: clean water (`water_l`) and wastewater. Ledger identity (L):
##   clean + waste + body loss + overflow + brine + electrolysis water + recovery water = clean and waste at start
## Oxygen reserve (`oxygen_kg`, stored tanks, not the cabin air):
##   reserve now = start + electrolysis O2 + CO2-unit O2 + plant O2 banked - regulator O2 - suit refills
## Cabin air (kg):  O2 now = start + regulator O2 + plant O2 - plant O2 banked - breathed - airlock loss
##                  N2 now = start + regulator N2 - airlock loss
##                  CO2 now = start + exhaled - scrubbed - plant CO2 - airlock loss
## (plant_o2_kg, plant_co2_kg and plant_o2_banked_kg are 0 until the Garden dome is upgraded past V1.)
## Crew rates are NASA per-day values / 24 per game hour (GameBalance, source S20). Area levels (2026-11-14): the
## life_support track's scrubber_factor, o2_production_factor and recycler_factor scale those machines, and the
## garden track's plant_o2_kg_per_hour adds plant oxygen to the cabin air (read with AreaLevels.effectf).
## Nitrogen reserve: now = start - regulator N2.   Suits: tanks now = start + refills - suit O2 used.
## Upgrades (Prompt 08, numbers in ProgressionBalance): ls_water_reliability (recycler +1 L/h, condition floor 0.8),
## ls_electrolysis and ls_co2_processing (more oxygen per hour at the same kWh per kg), ls_oxygen_monitoring (earlier,
## clearer warnings and an oxygen forecast alert). None of them changes a ledger identity.

## Plain names of the processes for panels and alerts.
const STATUS_TEXT := {
	"off": "switched off", "running": "running", "broken": "broken", "no_power": "no power", "no_feed": "no feed water",
	"dirty_water": "water not clean enough", "tanks_full": "oxygen tanks full", "feed_short": "running, short of feed water",
}


## Partial pressure of each cabin gas and the total, in kPa (ideal gas law).
static func update_pressures(state: ColonyState, balance: GameBalance) -> void:
	state.cabin_o2_kpa = balance.gas_kpa(state.cabin_o2_kg, GameBalance.MOLAR_O2)
	state.cabin_n2_kpa = balance.gas_kpa(state.cabin_n2_kg, GameBalance.MOLAR_N2)
	state.cabin_co2_kpa = balance.gas_kpa(state.cabin_co2_kg, GameBalance.MOLAR_CO2)
	state.cabin_pressure_kpa = state.cabin_o2_kpa + state.cabin_n2_kpa + state.cabin_co2_kpa


## Drinking and washing by `count` active astronauts. Always first. Returns the unmet share 0..1.
static func use_water(state: ColonyState, balance: GameBalance, count: int, dt: float) -> float:
	var need := float(count) * balance.water_l_per_hour * dt
	if need <= 0.0:
		return 0.0
	var got := -state.add_to_store(&"water_l", -need)
	var returning := got * balance.water_to_wastewater
	var returned := state.add_to_store(&"wastewater_l", returning)
	state.ledger["water_used_l"] += got
	state.ledger["water_to_wastewater_l"] += returned
	state.ledger["water_body_loss_l"] += got - returning
	state.ledger["wastewater_overflow_l"] += returning - returned
	state.unmet["water_l"] = need - got
	return (need - got) / need


## Plans this tick's water allocations and oxygen output before power is allocated (the two oxygen processes ask
## for the power their output needs). Allocations take only water above the drinking reserve; if both together
## want more than that, each gets the same share of what it asked for. The CO2-oxygen unit never touches water.
static func plan_processes(state: ColonyState, balance: GameBalance, dt: float) -> Dictionary:
	apply_condition_floors(state)
	var e_rate := electrolysis_o2_kg_per_hour(state, balance)
	var spare := maxf(0.0, state.store(&"water_l") - balance.water_reserve_l)
	var o2_room := state.room_in(&"oxygen_kg")
	var ok := balance.equipment_min_condition
	# electrolyser (S08 mechanism): needs feed water of good quality
	var e_status := "off"
	var want_feed := 0.0
	if state.is_on("electrolyser"):
		if state.condition_of("electrolyser") < ok:
			e_status = "broken"
		elif state.water_quality < balance.electrolyser_min_quality:
			e_status = "dirty_water"
		elif float(state.water_allocation.electrolysis_feed_l_per_hour) <= 0.0:
			e_status = "no_feed"
		elif o2_room <= 1e-12:
			e_status = "tanks_full"
		else:
			e_status = "running"
			want_feed = minf(float(state.water_allocation.electrolysis_feed_l_per_hour) * dt,
				minf(e_rate * dt, o2_room) * GameBalance.WATER_KG_PER_KG_O2)
	var want_greenhouse := minf(float(state.water_allocation.greenhouse_l_per_hour) * dt, state.room_in(&"wastewater_l"))
	var share := 1.0
	if want_feed + want_greenhouse > spare:
		share = spare / (want_feed + want_greenhouse)
	var feed := want_feed * share
	var e_o2 := feed / GameBalance.WATER_KG_PER_KG_O2
	if e_status == "running" and (share < 1.0 or float(state.water_allocation.electrolysis_feed_l_per_hour) * dt < e_rate * dt * GameBalance.WATER_KG_PER_KG_O2):
		e_status = "feed_short"
	if e_status == "feed_short" and e_o2 <= 0.0:
		e_status = "no_feed"
	# CO2-oxygen unit (MOXIE mechanism, colony scale is fiction scaled from S09): Mars air and power only
	var c_status := "off"
	var c_o2 := 0.0
	if state.is_on("co2_unit"):
		if state.condition_of("co2_unit") < ok:
			c_status = "broken"
		elif o2_room - e_o2 <= 1e-12:
			c_status = "tanks_full"
		else:
			c_status = "running"
			c_o2 = minf(co2_unit_o2_kg_per_hour(state, balance) * dt, o2_room - e_o2)
	return {
		"greenhouse_l": want_greenhouse * share, "electrolyser_o2_kg": e_o2, "co2_unit_o2_kg": c_o2,
		"kw": {"electrolyser": e_o2 * balance.electrolysis_kwh_per_kg_o2 / dt, "co2_unit": c_o2 * balance.co2_unit_kwh_per_kg_o2 / dt},
		"status": {"electrolyser": e_status, "co2_unit": c_status},
	}


## Runs the greenhouse water, both oxygen processes (if powered) and the recycler.
static func run_processes(state: ColonyState, balance: GameBalance, plan: Dictionary, dt: float) -> void:
	# greenhouse water: for now it only goes to wastewater (the food milestone will use it)
	var gh := -state.add_to_store(&"water_l", -minf(float(plan.greenhouse_l), state.room_in(&"wastewater_l")))
	var gh_in := state.add_to_store(&"wastewater_l", gh)
	state.ledger["greenhouse_water_l"] += gh
	state.ledger["wastewater_overflow_l"] += gh - gh_in

	var status: Dictionary = (plan.status as Dictionary).duplicate()
	# path 1: electrolyser, 2 H2O -> 2 H2 + O2, exactly WATER_KG_PER_KG_O2 litres of water per kg of oxygen
	if float(plan.electrolyser_o2_kg) > 0.0:
		if state.is_powered("electrolyser"):
			var water := -state.add_to_store(&"water_l", -float(plan.electrolyser_o2_kg) * GameBalance.WATER_KG_PER_KG_O2)
			var made := state.add_to_store(&"oxygen_kg", water / GameBalance.WATER_KG_PER_KG_O2)
			state.ledger["electrolysis_water_l"] += water
			state.ledger["electrolysis_o2_kg"] += made
			state.ledger["oxygen_made_kg"] += made
			state.ledger["hydrogen_vented_kg"] += water * GameBalance.HYDROGEN_PER_KG_WATER
		else:
			status["electrolyser"] = "no_power"
	# path 2: CO2-oxygen unit, 2 CO2 -> 2 CO + O2 from the Mars atmosphere. No water at all.
	if float(plan.co2_unit_o2_kg) > 0.0:
		if state.is_powered("co2_unit"):
			var made := state.add_to_store(&"oxygen_kg", float(plan.co2_unit_o2_kg))
			state.ledger["co2_unit_o2_kg"] += made
			state.ledger["oxygen_made_kg"] += made
			state.ledger["co2_intake_kg"] += made * GameBalance.CO2_KG_PER_KG_O2
			state.ledger["co_vented_kg"] += made * GameBalance.CO_KG_PER_KG_O2
		else:
			status["co2_unit"] = "no_power"
	state.oxygen_process = status

	# recycler: cleans wastewater; recycler_recovery of it comes back clean, the rest is brine
	if recycler_working(state, balance):
		var cap := recycler_l_per_hour(state, balance) * dt
		if balance.recycler_recovery > 0.0:
			cap = minf(cap, state.room_in(&"water_l") / balance.recycler_recovery)
		var taken := -state.add_to_store(&"wastewater_l", -cap)
		var before := state.store(&"water_l")
		var added := state.add_to_store(&"water_l", taken * balance.recycler_recovery)
		var quality_out := clampf(state.condition_of("recycler") / balance.recycler_good_condition, 0.0, 1.0)
		if before + added > 0.0:
			state.water_quality = clampf((state.water_quality * before + quality_out * added) / (before + added), 0.0, 1.0)
		state.ledger["recycler_in_l"] += taken
		state.ledger["water_recycled_l"] += added
		state.ledger["brine_l"] += taken - added


## ls_water_reliability: the recycler's condition never drops below ProgressionBalance.recycler_condition_floor.
## Applied at the start of every tick (before power is allocated), so every model reads the same condition.
static func apply_condition_floors(state: ColonyState) -> void:
	if state.has_upgrade("ls_water_reliability") and state.equipment.has("recycler"):
		var floor_value := ProgressionBalance.shared().recycler_condition_floor
		var e: Dictionary = state.equipment["recycler"]
		e["condition"] = maxf(float(e.get("condition", 0.0)), floor_value)


## Wastewater the recycler can clean per game hour (ls_water_reliability adds to it; the life_support area level's
## recycler_factor multiplies the total).
static func recycler_l_per_hour(state: ColonyState, balance: GameBalance) -> float:
	var bonus := ProgressionBalance.shared().recycler_bonus_l_per_hour if state.has_upgrade("ls_water_reliability") else 0.0
	return (balance.recycler_l_per_hour + bonus) * level_factor(state, "recycler_factor")


## Top oxygen output of the electrolyser per game hour (ls_electrolysis and the life_support area level's
## o2_production_factor raise it; kWh per kg stays the same, so the power it asks for rises with it).
static func electrolysis_o2_kg_per_hour(state: ColonyState, balance: GameBalance) -> float:
	var factor := ProgressionBalance.shared().electrolysis_output_factor if state.has_upgrade("ls_electrolysis") else 1.0
	return balance.electrolysis_o2_kg_per_hour * factor * level_factor(state, "o2_production_factor")


## Top oxygen output of the CO2-oxygen unit per game hour (ls_co2_processing and the life_support area level's
## o2_production_factor raise it; kWh per kg stays the same).
static func co2_unit_o2_kg_per_hour(state: ColonyState, balance: GameBalance) -> float:
	var factor := ProgressionBalance.shared().co2_unit_output_factor if state.has_upgrade("ls_co2_processing") else 1.0
	return balance.co2_unit_o2_kg_per_hour * factor * level_factor(state, "o2_production_factor")


## Most CO2 the scrubber removes per game hour with the cabin fans running (the life_support area level's
## scrubber_factor adds scrubber beds).
static func scrubber_co2_kg_per_hour(state: ColonyState, balance: GameBalance) -> float:
	return balance.scrubber_co2_kg_per_hour * level_factor(state, "scrubber_factor")


## A life_support area-level effect (data/area_levels.json), 1.0 at V1 or when the key is missing.
static func level_factor(state: ColonyState, key: String) -> float:
	return maxf(0.0, AreaLevels.effectf(state, "life_support", key, 1.0))


## Oxygen the Garden dome plants give off per game hour (garden.plant_o2_kg_per_hour, 0 at V1). A sol average: S20
## Table 4-91 rates are per day over the crop's life.
static func plant_o2_kg_per_hour(state: ColonyState) -> float:
	return maxf(0.0, AreaLevels.effectf(state, "garden", "plant_o2_kg_per_hour", 0.0))


static func recycler_working(state: ColonyState, balance: GameBalance) -> bool:
	return state.is_on("recycler") and state.condition_of("recycler") >= balance.equipment_min_condition and state.is_powered("recycler")


static func scrubber_working(state: ColonyState, balance: GameBalance) -> bool:
	return state.is_on("scrubber") and state.condition_of("scrubber") >= balance.equipment_min_condition and state.is_powered("scrubber")


static func fans_working(state: ColonyState, balance: GameBalance) -> bool:
	return state.is_on("cabin_fans") and state.condition_of("cabin_fans") >= balance.equipment_min_condition and state.is_powered("cabin_fans")


## Cabin air for one tick: airlock losses, breathing by `inside` astronauts, the CO2 scrubber and the regulator that
## tops up O2 from the oxygen reserve and N2 from the nitrogen reserve. Returns the O2 that could not be breathed (kg).
static func run_cabin(state: ColonyState, balance: GameBalance, inside: int, dt: float) -> float:
	# airlock: each queued cycle loses cabin air, mixed in proportion
	if state.pending_airlock_cycles > 0:
		var total := state.cabin_o2_kg + state.cabin_n2_kg + state.cabin_co2_kg
		var f := 0.0
		if total > 0.0:
			f = minf(1.0, float(state.pending_airlock_cycles) * balance.airlock_cycle_loss_kg / total)
		var lo2 := state.cabin_o2_kg * f
		var ln2 := state.cabin_n2_kg * f
		var lco2 := state.cabin_co2_kg * f
		state.cabin_o2_kg -= lo2
		state.cabin_n2_kg -= ln2
		state.cabin_co2_kg -= lco2
		state.ledger["airlock_o2_lost_kg"] += lo2
		state.ledger["airlock_n2_lost_kg"] += ln2
		state.ledger["airlock_co2_lost_kg"] += lco2
		state.ledger["airlock_cycles"] += float(state.pending_airlock_cycles)
		state.pending_airlock_cycles = 0
	# breathing
	var need := float(inside) * balance.oxygen_kg_per_hour * dt
	var got := minf(need, state.cabin_o2_kg)
	state.cabin_o2_kg -= got
	state.ledger["cabin_o2_breathed_kg"] += got
	state.ledger["oxygen_used_kg"] += got
	var exhaled := float(inside) * balance.co2_kg_per_hour * dt
	state.cabin_co2_kg += exhaled
	state.ledger["co2_exhaled_kg"] += exhaled
	# CO2 scrubber (S08 mechanism: molecular sieves). Without the fans it gets only part of the air.
	if scrubber_working(state, balance):
		var cap := scrubber_co2_kg_per_hour(state, balance) * dt * (1.0 if fans_working(state, balance) else balance.fans_off_scrubber_share)
		var floor_kg := balance.gas_kg_for_kpa(balance.scrubber_floor_kpa, GameBalance.MOLAR_CO2)
		var removed := clampf(state.cabin_co2_kg - floor_kg, 0.0, cap)
		state.cabin_co2_kg -= removed
		state.ledger["co2_scrubbed_kg"] += removed
	# Garden dome plants (garden.plant_o2_kg_per_hour): they give O2 to the cabin air and take up CO2 (44 g per 32 g O2).
	# With too little CO2 they make less. O2 they push above the set point is banked in the oxygen reserve.
	var plant_want := plant_o2_kg_per_hour(state) * dt
	if plant_want > 0.0:
		var co2_take := minf(plant_want * GameBalance.PLANT_CO2_KG_PER_KG_O2, maxf(0.0, state.cabin_co2_kg))
		var plant_o2 := co2_take / GameBalance.PLANT_CO2_KG_PER_KG_O2
		state.cabin_co2_kg -= co2_take
		state.cabin_o2_kg += plant_o2
		_ledger_add(state, "plant_o2_kg", plant_o2)
		_ledger_add(state, "plant_co2_kg", co2_take)
		var excess := minf(plant_o2, state.cabin_o2_kg - balance.gas_kg_for_kpa(balance.o2_setpoint_kpa, GameBalance.MOLAR_O2))
		if excess > 0.0:
			var banked := state.add_to_store(&"oxygen_kg", excess)
			state.cabin_o2_kg -= banked
			_ledger_add(state, "plant_o2_banked_kg", banked)
	# regulator: back to the set points from the reserves, at a limited flow
	var o2_want := clampf(balance.gas_kg_for_kpa(balance.o2_setpoint_kpa, GameBalance.MOLAR_O2) - state.cabin_o2_kg, 0.0, balance.regulator_kg_per_hour * dt)
	var o2_got := -state.add_to_store(&"oxygen_kg", -o2_want)
	state.cabin_o2_kg += o2_got
	state.ledger["regulator_o2_kg"] += o2_got
	var n2_want := clampf(balance.gas_kg_for_kpa(balance.n2_setpoint_kpa, GameBalance.MOLAR_N2) - state.cabin_n2_kg, 0.0, balance.regulator_kg_per_hour * dt)
	var n2_got := -state.add_to_store(&"n2_reserve_kg", -n2_want)
	state.cabin_n2_kg += n2_got
	state.ledger["regulator_n2_kg"] += n2_got
	update_pressures(state, balance)
	return need - got


## Adds to a ledger total that ColonyState may not list yet (the plant entries, 2026-11-14); saves keep any key.
static func _ledger_add(state: ColonyState, key: String, amount: float) -> void:
	state.ledger[key] = float(state.ledger.get(key, 0.0)) + amount


## Suit air for one active character outside. Returns the share of air it did not get (0..1).
static func run_suit(state: ColonyState, balance: GameBalance, c: CharacterState, dt: float) -> float:
	var need := balance.oxygen_kg_per_hour * dt
	if need <= 0.0:
		return 0.0
	if not c.suit_on or c.suit_charge <= 0.0 or balance.suit_o2_capacity_kg <= 0.0:
		return 1.0
	var tank := c.suit_charge / 100.0 * balance.suit_o2_capacity_kg
	var got := minf(need, tank)
	c.suit_charge = clampf((tank - got) / balance.suit_o2_capacity_kg * 100.0, 0.0, 100.0)
	state.ledger["suit_o2_used_kg"] += got
	state.ledger["oxygen_used_kg"] += got
	return (need - got) / need


## Oxygen in a character's suit tank, kg.
static func suit_kg(balance: GameBalance, c: CharacterState) -> float:
	return c.suit_charge / 100.0 * balance.suit_o2_capacity_kg


## Health lost per game hour by one active character, each cause scaled by how bad it is.
static func health_loss_per_hour(state: ColonyState, balance: GameBalance, c: CharacterState, no_air_share: float, water_share: float, food_share: float, atmosphere_damage := true) -> float:
	var loss := balance.health_loss_per_hour_no_water * water_share + balance.health_loss_per_hour_no_food * food_share
	if not atmosphere_damage:
		return loss
	if c.outside:
		loss += balance.health_loss_per_hour_no_air * no_air_share
	else:
		if state.cabin_o2_kpa < balance.o2_low_kpa and balance.o2_low_kpa > 0.0:
			loss += balance.health_loss_per_hour_low_o2 * clampf((balance.o2_low_kpa - state.cabin_o2_kpa) / balance.o2_low_kpa, 0.0, 1.0)
		if state.cabin_co2_kpa > balance.co2_danger_kpa and balance.co2_danger_kpa > 0.0:
			loss += balance.health_loss_per_hour_co2 * clampf((state.cabin_co2_kpa - balance.co2_danger_kpa) / balance.co2_danger_kpa, 0.0, 1.0)
	return loss


## "about 3.2 sols at this rate" / "about 14 hours at this rate" / "not falling at this rate".
static func _time_left_words(amount: float, rate_per_hour: float) -> String:
	if rate_per_hour >= -1e-9:
		return "not falling at this rate"
	var hours := amount / -rate_per_hour
	if hours >= GameConfig.SOL_HOURS:
		return "about %.1f sols at this rate" % (hours / GameConfig.SOL_HOURS)
	return "about %d hours at this rate" % maxi(1, roundi(hours))


## Life-support alerts as [id, level, text]. `no_air` maps character id -> share of air missing outside.
static func alerts(state: ColonyState, balance: GameBalance, no_air: Dictionary) -> Array:
	var out: Array = []
	# water
	if state.is_on("recycler") and state.condition_of("recycler") < balance.equipment_min_condition:
		out.append(["recycler_broken", "warn", "Water recycler is broken. Wastewater is building up."])
	elif not state.is_on("recycler"):
		out.append(["recycler_off", "warn", "Water recycler is switched off. Wastewater is building up."])
	var waste_cap := float(state.capacities.get(&"wastewater_l", 0.0))
	if waste_cap > 0.0 and state.store(&"wastewater_l") >= balance.wastewater_warn_fraction * waste_cap:
		out.append(["wastewater_high", "warn", "Wastewater tank is nearly full. Turn on the water recycler or send less water to the greenhouse."])
	if state.store(&"water_l") <= 0.0:
		out.append(["water_empty", "urgent", "No clean water left. The crew is getting thirsty and losing health."])
	elif state.store(&"water_l") < balance.water_reserve_l:
		out.append(["water_low", "warn", "Clean water is below the drinking reserve. Nothing goes to the greenhouse or the water splitter."])
	if state.water_quality < balance.recycler_good_condition + 0.1 and state.water_quality < 1.0 - 1e-9 and state.water_quality >= balance.electrolyser_min_quality:
		out.append(["water_quality", "info", "Water quality is %.0f %%. Below %.0f %% the water splitter stops." % [state.water_quality * 100.0, balance.electrolyser_min_quality * 100.0]])
	# oxygen processes
	var e_status := String(state.oxygen_process.get("electrolyser", "off"))
	match e_status:
		"dirty_water": out.append(["electrolyser_dirty_water", "warn", "Water splitter stopped: the water is not clean enough."])
		"no_feed": out.append(["electrolyser_no_feed", "info", "Water splitter is waiting: no water is sent to it. Set the water allocation at life support."])
		"broken": out.append(["electrolyser_broken", "warn", "Water splitter is broken. It makes no oxygen."])
		"feed_short": out.append(["electrolyser_feed_short", "info", "Water splitter is short of feed water, so it makes less oxygen."])
	if String(state.oxygen_process.get("co2_unit", "off")) == "broken":
		out.append(["co2_unit_broken", "warn", "CO2 splitter is broken. It makes no oxygen."])
	# oxygen reserve and cabin air (ls_oxygen_monitoring: earlier warnings that say how long is left, and a forecast)
	var monitor := state.has_upgrade("ls_oxygen_monitoring")
	var pb := ProgressionBalance.shared()
	var reserve_warn := balance.oxygen_reserve_warn_kg * (pb.monitoring_reserve_warn_factor if monitor else 1.0)
	var o2_warn := balance.o2_warn_kpa + (pb.monitoring_o2_warn_margin_kpa if monitor else 0.0)
	var co2_warn := balance.co2_warn_kpa - (pb.monitoring_co2_warn_margin_kpa if monitor else 0.0)
	var reserve := state.store(&"oxygen_kg")
	var reserve_rate := float(state.rates.get("oxygen_kg", 0.0))
	if reserve <= 0.0:
		out.append(["oxygen_reserve_empty", "urgent", "Oxygen reserve is empty. Cabin oxygen will slowly fall. Start the water splitter or the CO2 splitter."])
	elif reserve < reserve_warn:
		var text := "Oxygen reserve low: %.1f kg left. Start the water splitter or the CO2 splitter." % reserve
		if monitor:
			text = "Oxygen reserve low: %.1f kg left, %s. Start the water splitter or the CO2 splitter." % [reserve, _time_left_words(reserve, reserve_rate)]
		out.append(["oxygen_reserve_low", "warn", text])
	if state.cabin_o2_kpa < balance.o2_low_kpa:
		out.append(["cabin_o2_danger", "urgent", "Cabin oxygen is too low (%.1f kPa). The crew is losing health." % state.cabin_o2_kpa])
	elif state.cabin_o2_kpa < o2_warn:
		var text := "Cabin oxygen is falling (%.1f kPa). Refill the oxygen reserve." % state.cabin_o2_kpa
		if monitor:
			text = "Cabin oxygen is falling: %.1f kPa (safe is 21 kPa; the crew is harmed below %.0f kPa). Refill the oxygen reserve." % [state.cabin_o2_kpa, balance.o2_low_kpa]
		out.append(["cabin_o2_low", "warn", text])
	if state.cabin_co2_kpa >= balance.co2_danger_kpa:
		out.append(["co2_danger", "urgent", "Carbon dioxide is dangerous (%.2f kPa). The crew is losing health. Run the CO2 scrubber." % state.cabin_co2_kpa])
	elif state.cabin_co2_kpa >= co2_warn:
		var text := "Carbon dioxide is building up (%.2f kPa). Check the CO2 scrubber and the cabin fans." % state.cabin_co2_kpa
		if monitor:
			text = "Carbon dioxide is building up: %.2f kPa (harmful above %.1f kPa). Check the CO2 scrubber and the cabin fans." % [state.cabin_co2_kpa, balance.co2_danger_kpa]
		out.append(["co2_high", "warn", text])
	if monitor:
		var forecast := "Oxygen forecast: the reserve of %.1f kg is not falling at this rate." % reserve
		if reserve_rate < -1e-9:
			forecast = "Oxygen forecast: the reserve of %.1f kg lasts %s." % [reserve, _time_left_words(reserve, reserve_rate)]
		out.append(["oxygen_forecast", "info", forecast])
	if not state.is_on("scrubber"):
		out.append(["scrubber_off", "warn", "CO2 scrubber is switched off. Carbon dioxide is building up in the cabin."])
	if not state.is_on("cabin_fans"):
		out.append(["fans_off", "info", "Cabin fans are switched off. The CO2 scrubber cleans the air more slowly."])
	if state.cabin_pressure_kpa < balance.pressure_warn_kpa:
		out.append(["pressure_low", "warn", "Cabin pressure is low (%.1f kPa). The air reserves are running out." % state.cabin_pressure_kpa])
	if state.store(&"n2_reserve_kg") < balance.n2_reserve_warn_kg:
		out.append(["n2_reserve_low", "warn", "Nitrogen reserve low: %.1f kg left. Each airlock cycle uses some." % state.store(&"n2_reserve_kg")])
	# suits
	for id: StringName in no_air:
		var c := state.character(id)
		if float(no_air[id]) > 0.0:
			out.append(["no_air_" + String(id), "urgent", "%s has no air outside. Health is falling. Go inside or refill the suit." % c.display_name])
		elif c.suit_charge < balance.suit_warn_charge:
			out.append(["suit_low_" + String(id), "warn", "%s: suit air is low (%.0f %%). Head back to the airlock." % [c.display_name, c.suit_charge]])
	# food
	var crew := state.active_characters().size()
	if crew > 0:
		if state.store(&"food_meals") <= 0.0:
			out.append(["food_empty", "urgent", "No food left. The crew is hungry and losing health."])
		elif state.store(&"food_meals") < float(crew) * balance.meals_per_sol:
			out.append(["food_low", "warn", "Food for less than one sol is left."])
	return out
