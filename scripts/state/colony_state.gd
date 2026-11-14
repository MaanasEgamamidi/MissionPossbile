class_name ColonyState
extends RefCounted
## The authoritative colony state. Only the host changes it, and only through the simulation tick or a validated
## ActionRequest. It serialises to plain JSON types; SaveService wraps it with a schema version.
##
## Units are part of the field names: kWh stored energy, kW power, L water, kg oxygen, meals of food.

const STORE_KEYS: Array[StringName] = [&"battery_kwh", &"water_l", &"oxygen_kg", &"food_meals"]

# ---- stores (amount and capacity per key of STORE_KEYS)
var stores := {}
var capacities := {}
var parts := 0

# ---- last-tick flows, for display only (never integrated)
var solar_kw := 0.0
var load_kw := 0.0
var power_deficit := false
var unmet := {"oxygen_kg": 0.0, "water_l": 0.0, "food_meals": 0.0}

# ---- facilities: zone name -> {"powered": bool, "condition": float 0..1, "tier": int}
var zones := {}
# ---- stations: stable id -> {"zone": String, "position": [x, y, z], "specialty": String or ""}
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
var ledger := {
	"solar_used_kwh": 0.0, "load_served_kwh": 0.0, "solar_curtailed_kwh": 0.0, "load_unserved_kwh": 0.0,
	"oxygen_made_kg": 0.0, "oxygen_used_kg": 0.0, "water_used_l": 0.0, "water_recycled_l": 0.0, "meals_eaten": 0.0,
	"recovery_meals": 0.0, "recovery_water_l": 0.0,
}
## Next number for generated ids ("cache_3"), so ids stay unique across saves.
var counters := {"cache": 0}


static func new_game(balance: GameBalance, seed_value: int, zone_names: PackedStringArray = PackedStringArray()) -> ColonyState:
	var s := ColonyState.new()
	s.stores = {&"battery_kwh": balance.battery_kwh_start, &"water_l": balance.water_l_start, &"oxygen_kg": balance.oxygen_kg_start, &"food_meals": balance.food_meals_start}
	s.capacities = {&"battery_kwh": balance.battery_kwh_capacity, &"water_l": balance.water_l_capacity, &"oxygen_kg": balance.oxygen_kg_capacity,
		&"food_meals": balance.food_meals_capacity}
	s.parts = balance.parts_start
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


func store(key: StringName) -> float:
	return float(stores.get(key, 0.0))


## Adds (or removes, if negative) from a store, clamped to 0..capacity. Returns what was actually added or removed.
func add_to_store(key: StringName, amount: float) -> float:
	var before := store(key)
	var after := clampf(before + amount, 0.0, float(capacities.get(key, INF)))
	stores[key] = after
	return after - before


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


## True if nothing that must never happen has happened: no negative or over-capacity store, no NaN.
func invariants_ok() -> PackedStringArray:
	var problems := PackedStringArray()
	for k in STORE_KEYS:
		var v := store(k)
		if is_nan(v) or v < -1e-9:
			problems.append("%s is %s" % [k, v])
		if v > float(capacities.get(k, INF)) + 1e-9:
			problems.append("%s above capacity" % k)
	if parts < 0:
		problems.append("parts negative")
	var holders := {}
	for c: CharacterState in characters.values():
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
	power_deficit = bool(flows.get("power_deficit", power_deficit))
	if flows.has("unmet"):
		unmet = (flows["unmet"] as Dictionary).duplicate()


## Display-only values recomputed every tick, for replication (never saved).
func flows_dict() -> Dictionary:
	return {"solar_kw": solar_kw, "load_kw": load_kw, "power_deficit": power_deficit, "unmet": unmet.duplicate()}


static func from_dict(d: Dictionary) -> ColonyState:
	var s := ColonyState.new()
	for k in STORE_KEYS:
		s.stores[k] = float((d.get("stores", {}) as Dictionary).get(String(k), 0.0))
		s.capacities[k] = float((d.get("capacities", {}) as Dictionary).get(String(k), 0.0))
	s.parts = int(d.get("parts", 0))
	s.zones = (d.get("zones", {}) as Dictionary).duplicate(true)
	for z in s.zones:
		(s.zones[z] as Dictionary)["tier"] = int((s.zones[z] as Dictionary).get("tier", 0))
	s.stations = (d.get("stations", {}) as Dictionary).duplicate(true)
	for id in (d.get("characters", {}) as Dictionary):
		s.characters[StringName(String(id))] = CharacterState.from_dict(d.characters[id])
	s.items = (d.get("items", {}) as Dictionary).duplicate(true)
	s.caches = (d.get("caches", []) as Array).duplicate(true)
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
