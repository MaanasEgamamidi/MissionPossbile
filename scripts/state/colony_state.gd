class_name ColonyState
extends RefCounted
## The authoritative colony state. Only the host changes it, and only through the simulation tick or a validated
## ActionRequest. It serialises to plain JSON types; SaveService wraps it with a schema version.
##
## Units are part of the field names: kWh stored energy, kW power, L water, kg oxygen or gas, kPa pressure, meals.

const STORE_KEYS: Array[StringName] = [&"battery_kwh", &"water_l", &"oxygen_kg", &"food_meals", &"wastewater_l", &"n2_reserve_kg"]
## Switchable equipment. Each entry of `equipment` is {"on": bool, "powered": bool, "condition": 0..1, "kw": float}.
const EQUIPMENT_IDS: Array[String] = ["trackers", "cleaner", "recycler", "scrubber", "electrolyser", "co2_unit", "cabin_fans"]
## Number of sun trackers on the map (sf_solar_tracker, .001 ... .011).
const TRACKER_COUNT := 12

# ---- stores (amount and capacity per key of STORE_KEYS)
var stores := {}
var capacities := {}
var parts := 0

# ---- energy and life-support equipment (saved)
var equipment := {}
## Settled dust on each tracker, 0 (clean) .. 1 (covered).
var panel_dust: Array = []
## Dust in the air (optical depth). The weather milestone will drive it.
var dust_tau := 0.5
## Quality of the clean water, 0..1 (mixes by volume).
var water_quality := 1.0
## Water the players send to the greenhouse and to the electrolyser, litres per game hour.
var water_allocation := {"greenhouse_l_per_hour": 0.0, "electrolysis_feed_l_per_hour": 0.0}
## Cabin air masses in kg. Partial pressures come from the ideal gas law (see LifeSupportModel).
var cabin_o2_kg := 0.0
var cabin_n2_kg := 0.0
var cabin_co2_kg := 0.0
## Airlock cycles queued by SessionService.note_airlock_cycle(); the next tick applies them.
var pending_airlock_cycles := 0
## Active problems, recomputed every tick: [{"id", "level", "text", "since_hours"}].
var alerts: Array = []
## Game hours simulated since the game began (alerts use it for "since_hours").
var sim_hours := 0.0

# ---- last-tick flows, for display only (never integrated, never saved)
var solar_kw := 0.0
## Power wanted by everything switched on (kW), and power actually delivered.
var load_kw := 0.0
var served_kw := 0.0
## Battery power: + charging, - discharging (kW).
var battery_kw := 0.0
var power_deficit := false
## Load groups switched on but without power this tick, lowest priority first.
var shed: Array = []
var unmet := {"oxygen_kg": 0.0, "water_l": 0.0, "food_meals": 0.0}
var cabin_o2_kpa := 0.0
var cabin_n2_kpa := 0.0
var cabin_co2_kpa := 0.0
var cabin_pressure_kpa := 0.0
## Status of both oxygen processes: {"electrolyser": text, "co2_unit": text}. Either, both or neither may run.
var oxygen_process := {"electrolyser": "off", "co2_unit": "off"}
## Net change per game hour of each store during the last tick (for the reserve forecast).
var rates := {}

# ---- facilities: zone name -> {"powered": bool, "condition": float 0..1, "tier": int}
var zones := {}
# ---- stations: stable id -> {"kind", "zone", "position": [x, y, z], "specialty": String or "", ("tracker": index)}
var stations := {}

# ---- crew
var characters := {}          # StringName -> CharacterState

# ---- world items that can be carried: id -> {"kind": String, "position": [x, y, z], "holder": String or ""}
var items := {}
# ---- recoverable cargo caches left at incident locations: [{"id", "position", "items": [...]}]
var caches: Array = []

# ---- progression (filled by later milestones; saved from the start so the schema is stable)
var knowledge := {}
var evidence := {}
var upgrades := {}
var tasks := {}
var discoveries: Array = []
var rover := {"built": false, "levels": {"speed": 1, "torque": 1, "range": 1, "cargo": 1, "traction": 1}, "battery_kwh": 0.0, "cargo": []}

# ---- data and randomness
var data_snapshot_id := ""
var weather_queue: Array = []
## Timed events waiting to happen: [{"at_hours": float, "type": String, ...}], oldest first.
var event_queue: Array = []
var rng_seed := 0
var rng_state := 0

# ---- running totals since the game began. Each store obeys: now = start + in - out (see ColonySim).
var ledger := _empty_ledger()
## Next number for generated ids ("cache_3"), so ids stay unique across saves.
var counters := {"cache": 0}


static func _empty_ledger() -> Dictionary:
	var l := {}
	for k: String in [
		# energy
		"solar_offered_kwh", "solar_used_kwh", "solar_curtailed_kwh", "battery_in_kwh", "battery_out_kwh", "battery_loss_kwh",
		"load_served_kwh", "load_unserved_kwh",
		# water
		"water_used_l", "water_to_wastewater_l", "water_body_loss_l", "wastewater_overflow_l", "greenhouse_water_l",
		"electrolysis_water_l", "recycler_in_l", "water_recycled_l", "brine_l", "recovery_water_l",
		# oxygen reserve and processes
		"oxygen_made_kg", "electrolysis_o2_kg", "co2_unit_o2_kg", "hydrogen_vented_kg", "co2_intake_kg", "co_vented_kg",
		"regulator_o2_kg", "suit_refill_kg",
		# breathing and cabin air
		"oxygen_used_kg", "cabin_o2_breathed_kg", "suit_o2_used_kg", "co2_exhaled_kg", "co2_scrubbed_kg",
		"regulator_n2_kg", "airlock_o2_lost_kg", "airlock_n2_lost_kg", "airlock_co2_lost_kg", "airlock_cycles",
		# food
		"meals_eaten", "recovery_meals",
	]:
		l[k] = 0.0
	return l


static func new_game(balance: GameBalance, seed_value: int, zone_names: PackedStringArray = PackedStringArray()) -> ColonyState:
	var s := ColonyState.new()
	s.stores = {&"battery_kwh": balance.battery_kwh_start, &"water_l": balance.water_l_start, &"oxygen_kg": balance.oxygen_kg_start,
		&"food_meals": balance.food_meals_start, &"wastewater_l": balance.wastewater_l_start, &"n2_reserve_kg": balance.n2_reserve_kg_start}
	s.capacities = {&"battery_kwh": balance.battery_kwh_capacity, &"water_l": balance.water_l_capacity, &"oxygen_kg": balance.oxygen_kg_capacity,
		&"food_meals": balance.food_meals_capacity, &"wastewater_l": balance.wastewater_l_capacity, &"n2_reserve_kg": balance.n2_reserve_kg_capacity}
	s.parts = balance.parts_start
	s._start_systems(balance)
	for z in zone_names:
		s.zones[z] = {"powered": true, "condition": 1.0, "tier": 0}
	var names := ["Electrical and communications", "Medical and life support", "Biology and food", "Field engineering and geology"]
	for i in CharacterState.SPECIALTIES.size():
		var c := CharacterState.new()
		c.id = StringName("crew_%d" % (i + 1))
		c.specialty = CharacterState.SPECIALTIES[i]
		c.display_name = names[i]
		s.characters[c.id] = c
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	s.rng_seed = seed_value
	s.rng_state = rng.state
	return s


## Arrival condition of the energy and life-support systems: the cleaner has failed, the panels are dusty, the
## electrolyser and the CO2-oxygen unit are off, everything else runs. Cabin air is Earth-like.
func _start_systems(balance: GameBalance) -> void:
	equipment = {}
	for id in EQUIPMENT_IDS:
		var on := id != "electrolyser" and id != "co2_unit"
		equipment[id] = {"on": on, "powered": on, "condition": 1.0, "kw": 0.0}
	equipment["cleaner"]["condition"] = balance.cleaner_condition_start
	panel_dust = []
	for i in TRACKER_COUNT:
		panel_dust.append(balance.panel_dust_start)
	dust_tau = balance.dust_tau_default
	water_quality = 1.0
	water_allocation = {"greenhouse_l_per_hour": 0.0, "electrolysis_feed_l_per_hour": 0.0}
	cabin_o2_kg = balance.gas_kg_for_kpa(balance.o2_setpoint_kpa, GameBalance.MOLAR_O2)
	cabin_n2_kg = balance.gas_kg_for_kpa(balance.n2_setpoint_kpa, GameBalance.MOLAR_N2)
	cabin_co2_kg = balance.gas_kg_for_kpa(balance.co2_start_kpa, GameBalance.MOLAR_CO2)
	pending_airlock_cycles = 0
	alerts = []
	sim_hours = 0.0


func store(key: StringName) -> float:
	return float(stores.get(key, 0.0))


## Adds (or removes, if negative) from a store, clamped to 0..capacity. Returns what was actually added or removed.
func add_to_store(key: StringName, amount: float) -> float:
	var before := store(key)
	var after := clampf(before + amount, 0.0, float(capacities.get(key, INF)))
	stores[key] = after
	return after - before


## Room left in a store before it is full.
func room_in(key: StringName) -> float:
	return maxf(0.0, float(capacities.get(key, INF)) - store(key))


func active_characters() -> Array[CharacterState]:
	var out: Array[CharacterState] = []
	for c: CharacterState in characters.values():
		if c.is_active():
			out.append(c)
	return out


func character(id: StringName) -> CharacterState:
	return characters.get(id) as CharacterState


func character_of_peer(peer_id: int) -> CharacterState:
	for c: CharacterState in characters.values():
		if c.owner_peer == peer_id:
			return c
	return null


func is_zone_powered(zone: String) -> bool:
	return bool((zones.get(zone, {}) as Dictionary).get("powered", true))


## One piece of equipment, or an empty dictionary.
func unit(id: String) -> Dictionary:
	return equipment.get(id, {}) as Dictionary


func is_on(id: String) -> bool:
	return bool(unit(id).get("on", false))


func condition_of(id: String) -> float:
	return float(unit(id).get("condition", 0.0))


func is_powered(id: String) -> bool:
	return bool(unit(id).get("powered", false))


## True if nothing that must never happen has happened: no negative or over-capacity store, no NaN.
func invariants_ok() -> PackedStringArray:
	var problems := PackedStringArray()
	for k in STORE_KEYS:
		var v := store(k)
		if is_nan(v) or v < -1e-9:
			problems.append("%s is %s" % [k, v])
		if v > float(capacities.get(k, INF)) + 1e-9:
			problems.append("%s above capacity" % k)
	for gas: Array in [["cabin_o2_kg", cabin_o2_kg], ["cabin_n2_kg", cabin_n2_kg], ["cabin_co2_kg", cabin_co2_kg]]:
		if is_nan(float(gas[1])) or float(gas[1]) < -1e-9:
			problems.append("%s is %s" % [gas[0], gas[1]])
	if panel_dust.size() != TRACKER_COUNT:
		problems.append("panel_dust has %d entries" % panel_dust.size())
	for d: Variant in panel_dust:
		if is_nan(float(d)) or float(d) < -1e-9 or float(d) > 1.0 + 1e-9:
			problems.append("panel dust out of range: %s" % d)
	if is_nan(water_quality) or water_quality < -1e-9 or water_quality > 1.0 + 1e-9:
		problems.append("water_quality out of range: %s" % water_quality)
	for id in EQUIPMENT_IDS:
		if not equipment.has(id):
			problems.append("equipment %s missing" % id)
		elif condition_of(id) < -1e-9 or condition_of(id) > 1.0 + 1e-9:
			problems.append("equipment %s condition out of range" % id)
	if pending_airlock_cycles < 0:
		problems.append("pending_airlock_cycles negative")
	if parts < 0:
		problems.append("parts negative")
	var holders := {}
	for c: CharacterState in characters.values():
		if is_nan(c.suit_charge) or c.suit_charge < -1e-9 or c.suit_charge > 100.0 + 1e-9:
			problems.append("suit charge of %s out of range" % c.id)
		for item in c.cargo:
			if holders.has(item):
				problems.append("item %s carried twice" % item)
			holders[item] = c.id
	var owners := {}
	for c: CharacterState in characters.values():
		if c.owner_peer != 0:
			if owners.has(c.owner_peer):
				problems.append("peer %d controls two characters" % c.owner_peer)
			owners[c.owner_peer] = true
	return problems


func to_dict() -> Dictionary:
	var chars := {}
	for id in characters:
		chars[String(id)] = (characters[id] as CharacterState).to_dict()
	var st := {}
	var cap := {}
	for k in STORE_KEYS:
		st[String(k)] = store(k)
		cap[String(k)] = float(capacities.get(k, 0.0))
	return {
		"stores": st, "capacities": cap, "parts": parts, "zones": zones.duplicate(true), "stations": stations.duplicate(true),
		"characters": chars, "items": items.duplicate(true), "caches": caches.duplicate(true),
		"equipment": equipment.duplicate(true), "panel_dust": panel_dust.duplicate(), "dust_tau": dust_tau,
		"water_quality": water_quality, "water_allocation": water_allocation.duplicate(),
		"cabin_o2_kg": cabin_o2_kg, "cabin_n2_kg": cabin_n2_kg, "cabin_co2_kg": cabin_co2_kg,
		"pending_airlock_cycles": pending_airlock_cycles, "alerts": alerts.duplicate(true), "sim_hours": sim_hours,
		"knowledge": knowledge.duplicate(true), "evidence": evidence.duplicate(true), "upgrades": upgrades.duplicate(true), "tasks": tasks.duplicate(true),
		"discoveries": discoveries.duplicate(true), "rover": rover.duplicate(true),
		"data_snapshot_id": data_snapshot_id, "weather_queue": weather_queue.duplicate(true), "event_queue": event_queue.duplicate(true),
		"ledger": ledger.duplicate(true), "counters": counters.duplicate(true),
		# 64-bit values go out as strings: JSON numbers are doubles and would lose the low bits
		"rng_seed": str(rng_seed), "rng_state": str(rng_state),
	}


## Replaces this state's contents with a replicated copy, in place. CharacterState objects are updated, not
## replaced, so the player body and UI that hold them keep working. `keep_pose_of` names the character whose
## position and yaw are left alone (the one this client controls). Display-only flow values are copied too.
func assign_from(d: Dictionary, keep_pose_of: StringName = &"") -> void:
	var fresh := ColonyState.from_dict(d)
	stores = fresh.stores
	capacities = fresh.capacities
	parts = fresh.parts
	zones = fresh.zones
	stations = fresh.stations
	items = fresh.items
	caches = fresh.caches
	equipment = fresh.equipment
	panel_dust = fresh.panel_dust
	dust_tau = fresh.dust_tau
	water_quality = fresh.water_quality
	water_allocation = fresh.water_allocation
	cabin_o2_kg = fresh.cabin_o2_kg
	cabin_n2_kg = fresh.cabin_n2_kg
	cabin_co2_kg = fresh.cabin_co2_kg
	pending_airlock_cycles = fresh.pending_airlock_cycles
	alerts = fresh.alerts
	sim_hours = fresh.sim_hours
	knowledge = fresh.knowledge
	evidence = fresh.evidence
	upgrades = fresh.upgrades
	tasks = fresh.tasks
	discoveries = fresh.discoveries
	rover = fresh.rover
	data_snapshot_id = fresh.data_snapshot_id
	weather_queue = fresh.weather_queue
	event_queue = fresh.event_queue
	rng_seed = fresh.rng_seed
	rng_state = fresh.rng_state
	ledger = fresh.ledger
	counters = fresh.counters
	for id: StringName in fresh.characters:
		var incoming := fresh.characters[id] as CharacterState
		var mine := characters.get(id) as CharacterState
		if mine == null:
			characters[id] = incoming
		else:
			mine.assign_from((d["characters"] as Dictionary)[String(id)], id == keep_pose_of)
	for id: StringName in characters.keys():
		if not fresh.characters.has(id):
			characters.erase(id)
	var flows: Dictionary = d.get("flows", {})
	solar_kw = float(flows.get("solar_kw", solar_kw))
	load_kw = float(flows.get("load_kw", load_kw))
	served_kw = float(flows.get("served_kw", served_kw))
	battery_kw = float(flows.get("battery_kw", battery_kw))
	power_deficit = bool(flows.get("power_deficit", power_deficit))
	cabin_o2_kpa = float(flows.get("cabin_o2_kpa", cabin_o2_kpa))
	cabin_n2_kpa = float(flows.get("cabin_n2_kpa", cabin_n2_kpa))
	cabin_co2_kpa = float(flows.get("cabin_co2_kpa", cabin_co2_kpa))
	cabin_pressure_kpa = float(flows.get("cabin_pressure_kpa", cabin_pressure_kpa))
	if flows.has("shed"):
		shed = (flows["shed"] as Array).duplicate()
	if flows.has("unmet"):
		unmet = (flows["unmet"] as Dictionary).duplicate()
	if flows.has("oxygen_process"):
		oxygen_process = (flows["oxygen_process"] as Dictionary).duplicate()
	if flows.has("rates"):
		rates = (flows["rates"] as Dictionary).duplicate()


## Display-only values recomputed every tick, for replication (never saved).
func flows_dict() -> Dictionary:
	return {"solar_kw": solar_kw, "load_kw": load_kw, "served_kw": served_kw, "battery_kw": battery_kw, "power_deficit": power_deficit,
		"shed": shed.duplicate(), "unmet": unmet.duplicate(), "cabin_o2_kpa": cabin_o2_kpa, "cabin_n2_kpa": cabin_n2_kpa,
		"cabin_co2_kpa": cabin_co2_kpa, "cabin_pressure_kpa": cabin_pressure_kpa, "oxygen_process": oxygen_process.duplicate(),
		"rates": rates.duplicate()}


static func from_dict(d: Dictionary) -> ColonyState:
	var s := ColonyState.new()
	# Fields missing from an older save take the values of a fresh game (safe defaults, no schema change needed).
	var base := ColonyState.new_game(GameBalance.new(), 0)
	var d_stores: Dictionary = d.get("stores", {})
	var d_caps: Dictionary = d.get("capacities", {})
	for k in STORE_KEYS:
		s.stores[k] = float(d_stores.get(String(k), base.store(k)))
		s.capacities[k] = float(d_caps.get(String(k), base.capacities[k]))
	s.parts = int(d.get("parts", 0))
	s.zones = (d.get("zones", {}) as Dictionary).duplicate(true)
	for z in s.zones:
		(s.zones[z] as Dictionary)["tier"] = int((s.zones[z] as Dictionary).get("tier", 0))
	s.stations = (d.get("stations", {}) as Dictionary).duplicate(true)
	for id in s.stations:
		var st: Dictionary = s.stations[id]
		if st.has("tracker"):
			st["tracker"] = int(st["tracker"])
	for id in (d.get("characters", {}) as Dictionary):
		s.characters[StringName(String(id))] = CharacterState.from_dict(d.characters[id])
	s.items = (d.get("items", {}) as Dictionary).duplicate(true)
	s.caches = (d.get("caches", []) as Array).duplicate(true)
	s.equipment = base.equipment.duplicate(true)
	var d_equipment: Dictionary = d.get("equipment", {})
	for id in EQUIPMENT_IDS:
		if d_equipment.has(id):
			var e: Dictionary = d_equipment[id]
			s.equipment[id] = {"on": bool(e.get("on", false)), "powered": bool(e.get("powered", false)),
				"condition": float(e.get("condition", 1.0)), "kw": float(e.get("kw", 0.0))}
	s.panel_dust = []
	var d_dust: Array = d.get("panel_dust", base.panel_dust)
	for i in TRACKER_COUNT:
		s.panel_dust.append(float(d_dust[i]) if i < d_dust.size() else base.panel_dust[i])
	s.dust_tau = float(d.get("dust_tau", base.dust_tau))
	s.water_quality = float(d.get("water_quality", base.water_quality))
	var d_alloc: Dictionary = d.get("water_allocation", {})
	for k: String in base.water_allocation:
		s.water_allocation[k] = float(d_alloc.get(k, 0.0))
	s.cabin_o2_kg = float(d.get("cabin_o2_kg", base.cabin_o2_kg))
	s.cabin_n2_kg = float(d.get("cabin_n2_kg", base.cabin_n2_kg))
	s.cabin_co2_kg = float(d.get("cabin_co2_kg", base.cabin_co2_kg))
	s.pending_airlock_cycles = int(d.get("pending_airlock_cycles", 0))
	s.alerts = []
	for a: Dictionary in d.get("alerts", []):
		s.alerts.append({"id": String(a.get("id", "")), "level": String(a.get("level", "info")), "text": String(a.get("text", "")),
			"since_hours": float(a.get("since_hours", 0.0))})
	s.sim_hours = float(d.get("sim_hours", 0.0))
	s.knowledge = (d.get("knowledge", {}) as Dictionary).duplicate(true)
	s.evidence = (d.get("evidence", {}) as Dictionary).duplicate(true)
	s.upgrades = (d.get("upgrades", {}) as Dictionary).duplicate(true)
	s.tasks = (d.get("tasks", {}) as Dictionary).duplicate(true)
	s.discoveries = (d.get("discoveries", []) as Array).duplicate(true)
	if d.has("rover"):
		s.rover = (d.rover as Dictionary).duplicate(true)
		var levels: Dictionary = s.rover.get("levels", {})
		for k in levels:
			levels[k] = int(levels[k])
	s.data_snapshot_id = String(d.get("data_snapshot_id", ""))
	s.weather_queue = (d.get("weather_queue", []) as Array).duplicate(true)
	s.event_queue = (d.get("event_queue", []) as Array).duplicate(true)
	for k in (d.get("ledger", {}) as Dictionary):
		s.ledger[String(k)] = float(d.ledger[k])
	for k in (d.get("counters", {}) as Dictionary):
		s.counters[String(k)] = int(d.counters[k])
	s.rng_seed = int(String(d.get("rng_seed", "0")))
	s.rng_state = int(String(d.get("rng_state", "0")))
	return s
