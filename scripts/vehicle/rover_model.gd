class_name RoverModel
extends RefCounted
## The shared rover's numbers (Prompt 10): levels, part costs, resulting stats, energy use, seats and exits, and the
## assembly challenge. Pure functions over `state.rover`, so the garage panel, the host's actions, the vehicle body and
## the tutorial all read one model. Every tunable number is in RoverBalance (categories in data/model_sources_rover.json).
## The stat curves are FICTIONAL GAME TUNING supported by real principles, not NASA measurements of a crewed rover.
##
## state.rover (plain JSON, saved and replicated):
##   built: bool                 assembled at the garage by the field engineer
##   levels: {stat: 1..5}        for STATS
##   battery_kwh: float          stored energy, never refilled by a refit
##   cargo: [item ids]           items loaded in the cargo bay (their items[id].holder is "rover")
##   seats: ["", "", "", ""]     character ids; index 0 is the driver, 1..3 passengers
##   pose: {"position": [x, y, z], "quat": [x, y, z, w]}   last pose reported by the driver (saved)
## Added by the rover-economy part (Prompt 10, part 1):
##   charging: bool              plugged in at the garage charger (RoverSystem moves the energy)
##   charge_status: String       "off", "charging", "full", "paused_reserve", "paused_deficit", "unplugged"
##   trip: {"distance_m", "climb_m", "energy_kwh"}   since charging last started (for the HUD)
##   odometer_m: float           every metre ever driven
##   refit_seq: int              number of assemblies and refits done; a refit request must name it (no replay)
##   challenge_variant: int      the assembly check's example number; a wrong answer moves it on (a new example)
##   last_refit: {...}           who changed what, when, and the parts it cost (negative = given back)
##   empty_announced: bool       the "battery empty" alert was shown for this empty battery
## Added by the rover upgrade path (phase 1, the "rover" track of data/area_levels.json):
##   fuel_cell_kwh: float        usable energy left in the fuel-cell tanks (0 below RoverBalance.fuel_cell_level)
##
## Rover upgrade path levels (RoverModel.track_level(state) = AreaLevels.level(state, "rover"), 1 when unknown):
##   L3 pressurized cabin with suitport: seated crew breathe cabin air (no suit oxygen) and are sheltered from
##      solar-storm radiation while seated (cabin_sheltered).
##   L4 fuel-cell range extender: +RoverBalance.fuel_cell_kwh of range; it feeds the battery once the battery is low
##      and is refilled at the garage charger from the colony's oxygen store (RoverSystem).
##   L5 RTG trickle charge (parked or driving) and the sample arm (can_assay).

const STATS: PackedStringArray = ["speed", "torque", "range", "cargo", "traction"]
const SEATS := 4
const MAX_LEVEL := 5
const ROVER_JSON := "res://data/rover.json"
## Holder of an item in the cargo bay (ColonyState.items[id].holder).
const HOLDER := "rover"

## Words for each stat in the garage.
const STAT_NAMES := {"speed": "Speed (drive motor)", "torque": "Torque (wheel gearboxes)", "range": "Battery range",
	"cargo": "Cargo bay", "traction": "Traction (tyres)"}
## The module each stat changes, for the assembly check.
const MODULE_NAMES := {"speed": "drive motor", "torque": "wheel gearboxes", "range": "battery pack", "cargo": "cargo frame",
	"traction": "tyres"}
## Sockets on the chassis that a module can be connected to: id -> words.
const PORTS := {"motor": "Motor port (MOTOR-4 socket)", "battery": "Battery bus (orange high-voltage socket)",
	"hub": "Wheel hubs (splined shaft, 5 bolts)", "deck": "Deck rails (4 bolt holes)", "data": "Data port (small grey socket)"}
## The socket each module belongs on.
const RIGHT_PORT := {"speed": "motor", "torque": "hub", "range": "battery", "cargo": "deck", "traction": "hub"}

static var _geometry: Dictionary = {}


## Fills missing rover fields with defaults (older saves, new games) and puts numbers back to their JSON-safe types.
static func ensure(state: ColonyState) -> void:
	var r := state.rover
	if not (r.get("levels", null) is Dictionary):
		r["levels"] = {}
	var levels: Dictionary = r["levels"]
	for s: String in STATS:
		levels[s] = clampi(int(levels.get(s, 1)), 1, MAX_LEVEL)
	r["built"] = bool(r.get("built", false))
	r["battery_kwh"] = maxf(0.0, float(r.get("battery_kwh", 0.0)))
	if not (r.get("cargo", null) is Array):
		r["cargo"] = []
	var seats: Variant = r.get("seats", null)
	if not (seats is Array) or (seats as Array).size() != SEATS:
		r["seats"] = ["", "", "", ""]
	else:
		for i in SEATS:
			(seats as Array)[i] = String((seats as Array)[i])
	var pose: Variant = r.get("pose", null)
	if not (pose is Dictionary) or not ((pose as Dictionary).get("position", null) is Array) or not ((pose as Dictionary).get("quat", null) is Array):
		var g := geometry()
		var p: Vector3 = g.park_position
		var q: Quaternion = g.park_quat
		r["pose"] = {"position": [p.x, p.y, p.z], "quat": [q.x, q.y, q.z, q.w]}
	r["charging"] = bool(r.get("charging", false))
	r["charge_status"] = String(r.get("charge_status", "off"))
	if not (r.get("trip", null) is Dictionary):
		r["trip"] = {}
	for k: String in ["distance_m", "climb_m", "energy_kwh"]:
		r["trip"][k] = float((r["trip"] as Dictionary).get(k, 0.0))
	r["odometer_m"] = float(r.get("odometer_m", 0.0))
	r["refit_seq"] = int(r.get("refit_seq", 0))
	r["challenge_variant"] = int(r.get("challenge_variant", 0))
	r["empty_announced"] = bool(r.get("empty_announced", false))
	r["fuel_cell_kwh"] = clampf(float(r.get("fuel_cell_kwh", 0.0)), 0.0, fuel_cell_capacity_kwh(state))


# ---------------------------------------------------------------- rover upgrade path (area_levels "rover" track)

## Track id of the rover's upgrade path in data/area_levels.json.
const TRACK_ID := "rover"


## The rover's upgrade-path level (1..5): AreaLevels.level(state, "rover"), 1 without a state.
static func track_level(state: ColonyState) -> int:
	if state == null:
		return 1
	return clampi(AreaLevels.level(state, TRACK_ID), 1, MAX_LEVEL)


## True when the cabin is pressurized (suitport): from RoverBalance.cabin_level.
static func has_cabin(state: ColonyState) -> bool:
	return track_level(state) >= RoverBalance.get_current().cabin_level


## True when the fuel-cell range extender is fitted: from RoverBalance.fuel_cell_level.
static func has_fuel_cell(state: ColonyState) -> bool:
	return track_level(state) >= RoverBalance.get_current().fuel_cell_level


## True when the RTG power cart is fitted: from RoverBalance.rtg_level.
static func has_rtg(state: ColonyState) -> bool:
	return track_level(state) >= RoverBalance.get_current().rtg_level


## Usable energy of full fuel-cell tanks at the current level, kWh (0 without the fuel cell).
static func fuel_cell_capacity_kwh(state: ColonyState) -> float:
	return RoverBalance.get_current().fuel_cell_kwh if has_fuel_cell(state) else 0.0


## RTG trickle-charge power at the current level, kW (0 without the RTG).
static func rtg_kw(state: ColonyState) -> float:
	return RoverBalance.get_current().rtg_kw if has_rtg(state) else 0.0


## For the radiation and life-support helpers: true when `actor` sits in the rover (any seat) and the rover has its
## pressurized cabin (L3+). Such crew breathe cabin air (no suit oxygen) and are sheltered from solar-storm radiation.
static func cabin_sheltered(state: ColonyState, actor: CharacterState) -> bool:
	if state == null or actor == null or not bool(state.rover.get("built", false)):
		return false
	return seat_of(state, String(actor.id)) >= 0 and has_cabin(state)


## For the science and survey helpers: true when the rover's sample arm with its laser spectrometer is fitted (L5),
## so ore can be assayed on site from the rover.
static func can_assay(state: ColonyState) -> bool:
	return state != null and bool(state.rover.get("built", false)) and track_level(state) >= RoverBalance.get_current().sample_arm_level


## Parts needed to raise a stat from `level` to `level + 1` (approved: 1, 2, 3, 4).
static func step_cost(level: int) -> int:
	return clampi(level, 1, MAX_LEVEL - 1)


## Parts invested in these levels above the base equipment (all five stats at 5 = 50).
static func invested(levels: Dictionary) -> int:
	var total := 0
	for s: String in STATS:
		for l in range(1, clampi(int(levels.get(s, 1)), 1, MAX_LEVEL)):
			total += step_cost(l)
	return total


## Level of one stat, 1..5.
static func level_of(levels: Dictionary, stat: String) -> int:
	return clampi(int(levels.get(stat, 1)), 1, MAX_LEVEL)


## The levels of `levels` for every stat, as ints 1..5.
static func clean_levels(levels: Dictionary) -> Dictionary:
	var out := {}
	for s: String in STATS:
		out[s] = level_of(levels, s)
	return out


## Mass of the rover with these modules and this cargo, without crew, kg.
static func rover_mass_kg(levels: Dictionary, cargo_kg: float) -> float:
	var b := RoverBalance.get_current()
	return b.chassis_mass_kg + b.battery_mass_per_level_kg * float(level_of(levels, "range") - 1) \
		+ b.cargo_frame_mass_per_level_kg * float(level_of(levels, "cargo") - 1) + maxf(0.0, cargo_kg)


## Resulting stats for these levels and this cargo mass. Keys (units in the names): top_speed_mps, drive_force_n,
## battery_capacity_kwh, cargo_capacity_kg, traction_mu, mass_kg, range_km, plus motor_power_kw, crew, crew_kg,
## total_mass_kg, kwh_per_km, battery_kwh, accel_mps2, max_slope_deg.
## mass_kg is the rover with its cargo but no crew (the body adds seated crew if it wants: crew_kg).
## range_km is the honest range ON THE MAP from `battery_kwh` stored energy (< 0: a full battery), with `crew` people
## aboard and this cargo, on ground that needs RoverBalance.range_terrain_factor times the energy of flat firm ground,
## with no energy back downhill. range_now_km(state) uses the real battery, cargo and crew.
static func stats(levels: Dictionary, cargo_kg: float, battery_kwh := -1.0, crew := SEATS) -> Dictionary:
	var b := RoverBalance.get_current()
	var g := RoverBalance.MARS_GRAVITY
	var cap := RoverBalance.at_level(b.battery_capacity_kwh, level_of(levels, "range"))
	var mass := rover_mass_kg(levels, cargo_kg)
	var crew_n := clampi(crew, 0, SEATS)
	var total := mass + float(crew_n) * b.crew_member_kg
	var force := RoverBalance.at_level(b.drive_force_n, level_of(levels, "torque"))
	var mu := RoverBalance.at_level(b.traction_mu, level_of(levels, "traction"))
	var per_km := energy_kwh_for_move(levels, cargo_kg, 1000.0, 0.0, crew_n)
	var stored := cap if battery_kwh < 0.0 else clampf(battery_kwh, 0.0, cap)
	var range_km := 0.0 if per_km <= 0.0 else stored / (per_km * b.range_terrain_factor)
	# Pulling away on flat ground: the push is limited by the gearbox force and by grip (friction x weight).
	var push := minf(force, mu * total * g)
	var accel := maxf(0.0, (push - b.rolling_resistance * total * g) / total)
	return {"top_speed_mps": RoverBalance.at_level(b.top_speed_mps, level_of(levels, "speed")),
		"motor_power_kw": RoverBalance.at_level(b.motor_power_kw, level_of(levels, "speed")),
		"drive_force_n": force, "battery_capacity_kwh": cap,
		"cargo_capacity_kg": RoverBalance.at_level(b.cargo_capacity_kg, level_of(levels, "cargo")),
		"traction_mu": mu, "mass_kg": mass, "crew": crew_n, "crew_kg": float(crew_n) * b.crew_member_kg, "total_mass_kg": total,
		"cargo_kg": maxf(0.0, cargo_kg), "kwh_per_km": per_km, "battery_kwh": stored, "range_km": range_km,
		"accel_mps2": accel, "max_slope_deg": max_slope_deg(force, mu, total)}


## The steepest slope the rover can climb slowly, degrees: limited by the gearbox push (m g (sin a + c cos a) = F) and
## by grip (the wheels slip when tan a + c > friction). c = rolling resistance.
static func max_slope_deg(force_n: float, mu: float, total_kg: float) -> float:
	var b := RoverBalance.get_current()
	var c := b.rolling_resistance
	var w := total_kg * RoverBalance.MARS_GRAVITY
	if w <= 0.0:
		return 0.0
	var ratio := force_n / (w * sqrt(1.0 + c * c))
	var by_force := 90.0 if ratio >= 1.0 else rad_to_deg(asin(ratio) - atan(c))
	var by_grip := rad_to_deg(atan(maxf(0.0, mu - c)))
	return maxf(0.0, minf(by_force, by_grip))


## Energy in kWh for driving `distance_m` with `climb_m` of net height gain (negative climb recovers nothing), with
## `crew` people aboard (each RoverBalance.crew_member_kg). Rolling resistance (c m g d) plus lifting (m g h), divided
## by the drivetrain efficiency; both distances count RoverBalance.map_distance_factor times on the small map.
static func energy_kwh_for_move(levels: Dictionary, cargo_kg: float, distance_m: float, climb_m: float, crew := SEATS) -> float:
	var b := RoverBalance.get_current()
	var g := RoverBalance.MARS_GRAVITY
	var m := rover_mass_kg(levels, cargo_kg) + float(clampi(crew, 0, SEATS)) * b.crew_member_kg
	var d := maxf(0.0, distance_m) * b.map_distance_factor
	var h := maxf(0.0, climb_m) * b.map_distance_factor
	var joules := (b.rolling_resistance * m * g * d + m * g * h) / maxf(0.05, b.drivetrain_efficiency)
	return joules / 3.6e6


## Mass of the items in the cargo bay.
static func cargo_mass_kg(state: ColonyState) -> float:
	var b := RoverBalance.get_current()
	var total := 0.0
	for id: Variant in state.rover.get("cargo", []):
		var rec: Dictionary = state.items.get(String(id), {})
		total += b.mass_of_kind(String(rec.get("kind", "")))
	return total


## Mass of one world item, kg.
static func item_mass_kg(state: ColonyState, item_id: String) -> float:
	var rec: Dictionary = state.items.get(item_id, {})
	return RoverBalance.get_current().mass_of_kind(String(rec.get("kind", "")))


## People in the seats.
static func crew_aboard(state: ColonyState) -> int:
	var n := 0
	for id: Variant in state.rover.get("seats", []):
		if String(id) != "":
			n += 1
	return n


## The seat index of a character, or -1.
static func seat_of(state: ColonyState, character_id: String) -> int:
	var seats: Array = state.rover.get("seats", [])
	for i in seats.size():
		if String(seats[i]) == character_id and character_id != "":
			return i
	return -1


## True if seat `index` can be taken: nobody is in it, or the one recorded there is no longer played (parked crew are
## at the hub, so their seat is free; RoverSystem clears it on the next tick).
static func seat_free(state: ColonyState, index: int) -> bool:
	var seats: Array = state.rover.get("seats", [])
	if index < 0 or index >= seats.size():
		return false
	var who := String(seats[index])
	if who == "":
		return true
	var c := state.character(StringName(who))
	return c == null or not c.is_active()


## The stats of the rover as it is now: its levels, its real cargo, battery and crew (at least the driver). With the
## fuel cell (L4+) range_km also counts the energy left in its tanks; extra keys: fuel_cell_kwh,
## fuel_cell_capacity_kwh, rtg_kw, track_level, cabin (bool), battery_range_km (the battery alone).
static func current_stats(state: ColonyState) -> Dictionary:
	var s := stats(state.rover.get("levels", {}), cargo_mass_kg(state), float(state.rover.get("battery_kwh", 0.0)), maxi(1, crew_aboard(state)))
	var fc_cap := fuel_cell_capacity_kwh(state)
	var fc := clampf(float(state.rover.get("fuel_cell_kwh", 0.0)), 0.0, fc_cap)
	var per_km := float(s.kwh_per_km) * RoverBalance.get_current().range_terrain_factor
	s["battery_range_km"] = float(s.range_km)
	if per_km > 0.0:
		s["range_km"] = float(s.range_km) + fc / per_km
	s["fuel_cell_kwh"] = fc
	s["fuel_cell_capacity_kwh"] = fc_cap
	s["rtg_kw"] = rtg_kw(state)
	s["track_level"] = track_level(state)
	s["cabin"] = has_cabin(state)
	return s


## The honest range now, km on the map: stored energy (battery and fuel cell), cargo and crew aboard (at least a
## driver), terrain allowance.
static func range_now_km(state: ColonyState) -> float:
	return float(current_stats(state).range_km)


# ---------------------------------------------------------------- pose, seats and exits

## Seats, exits and the garage park pose: from data/rover.json (written by the vehicle part) when it exists and can be
## read, else RoverBalance's fallback. {"seats": Array[Vector3], "exits": Array[Vector3], "park_position": Vector3,
## "park_quat": Quaternion, "source": String}. Keys read from rover.json: "seats" and "exits" (or "exit_points" /
## "exit_offsets"): arrays of [x, y, z] or {"position"|"local"|"offset": [x, y, z]} in the rover's frame; the park pose
## from "garage_park_pose" (or "park_pose" / "park"): {"position": [x, y, z], "quat": [x, y, z, w]} or "yaw_deg".
static func geometry() -> Dictionary:
	if not _geometry.is_empty():
		return _geometry
	var b := RoverBalance.get_current()
	var g := {"seats": b.seat_offsets.duplicate(), "exits": b.exit_offsets.duplicate(), "park_position": b.park_position,
		"park_quat": Quaternion(Vector3.UP, deg_to_rad(b.park_yaw_deg)), "source": "RoverBalance fallback"}
	if FileAccess.file_exists(ROVER_JSON):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROVER_JSON))
		if d is Dictionary:
			var seats := _vectors(_first(d, ["seats", "seat_positions"]))
			var exits := _vectors(_first(d, ["exits", "exit_points", "exit_offsets"]))
			if seats.size() >= SEATS:
				g["seats"] = seats.slice(0, SEATS)
			if not exits.is_empty():
				g["exits"] = exits
			var park: Variant = _first(d, ["garage_park_pose", "park_pose", "park"])
			if park is Dictionary:
				var pd := park as Dictionary
				if pd.get("position", null) is Array and (pd.position as Array).size() >= 3:
					g["park_position"] = _vec(pd.position)
				if pd.get("quat", null) is Array and (pd.quat as Array).size() >= 4:
					var qa: Array = pd.quat
					g["park_quat"] = Quaternion(float(qa[0]), float(qa[1]), float(qa[2]), float(qa[3])).normalized()
				elif pd.has("yaw_deg"):
					g["park_quat"] = Quaternion(Vector3.UP, deg_to_rad(float(pd.yaw_deg)))
			g["source"] = ROVER_JSON
	_geometry = g
	return _geometry


## Forgets the cached geometry (tests, or after data/rover.json changed).
static func reload_geometry() -> void:
	_geometry = {}


## Where the rover is now (state.rover.pose), Godot coordinates.
static func pose_position(state: ColonyState) -> Vector3:
	var pose: Dictionary = state.rover.get("pose", {})
	if pose.get("position", null) is Array and (pose.position as Array).size() >= 3:
		return _vec(pose.position)
	return geometry().park_position


## Which way the rover faces now.
static func pose_quat(state: ColonyState) -> Quaternion:
	var pose: Dictionary = state.rover.get("pose", {})
	if pose.get("quat", null) is Array and (pose.quat as Array).size() >= 4:
		var q: Array = pose.quat
		var quat := Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3]))
		if quat.length_squared() > 1e-9:
			return quat.normalized()
	return geometry().park_quat


## A point in the rover's own frame, in world coordinates at the current pose.
static func to_world(state: ColonyState, local: Vector3) -> Vector3:
	return pose_position(state) + pose_quat(state) * local


## World position of seat `index`.
static func seat_world_position(state: ColonyState, index: int) -> Vector3:
	var seats: Array = geometry().seats
	return to_world(state, seats[clampi(index, 0, seats.size() - 1)] as Vector3)


## How many exit points the rover has.
static func exit_count() -> int:
	return (geometry().exits as Array).size()


## World position of exit point `index`.
static func exit_world_position(state: ColonyState, index: int) -> Vector3:
	var exits: Array = geometry().exits
	return to_world(state, exits[clampi(index, 0, exits.size() - 1)] as Vector3)


## Horizontal distance from the rover's centre to a point (height differences on the slope do not count).
static func distance_to_rover(state: ColonyState, point: Vector3) -> float:
	var p := pose_position(state)
	return Vector2(point.x - p.x, point.z - p.z).length()


# ---------------------------------------------------------------- assembly challenge

## The stats the assembly check covers when going from `from_levels` to `to_levels`: the changed stats, biggest change
## first (STATS order breaks ties), and on the first build also the drive motor and the battery (the rover cannot move
## without them). At most RoverBalance.challenge_max_stats.
static func challenge_stats(from_levels: Dictionary, to_levels: Dictionary, first_build: bool) -> PackedStringArray:
	var picked: Array = []
	for i in STATS.size():
		var s := STATS[i]
		var delta := absi(level_of(to_levels, s) - level_of(from_levels, s))
		if delta > 0 or (first_build and (s == "speed" or s == "range")):
			picked.append([delta, i, s])
	picked.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1])))
	var out := PackedStringArray()
	for p: Array in picked:
		if out.size() < maxi(1, RoverBalance.get_current().challenge_max_stats):
			out.append(String(p[2]))
	return out


## The assembly check for changing the rover from its current levels to `to_levels`. Deterministic: seeded from the
## colony seed, the refit number, the example number (challenge_variant) and each stat's levels, so the panel (on any
## machine) and the host build the same example. A wrong answer moves challenge_variant on, which gives new numbers.
## {"seq", "variant", "first_build", "steps": [{"stat", "module", "from", "to", "need", "modules": [{"text", "ok", "why"}],
##   "ports": [{"id", "text"}], "port": id, "question", "options": [text], "answer": index, "explain"}]}
static func challenge(state: ColonyState, to_levels: Dictionary) -> Dictionary:
	ensure(state)
	var r := state.rover
	var from: Dictionary = r.levels
	var first := not bool(r.built)
	var seq := int(r.refit_seq)
	var variant := int(r.challenge_variant)
	var steps: Array = []
	for s: String in challenge_stats(from, to_levels, first):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("rover|%d|%d|%d|%s|%d|%d" % [state.rng_seed, seq, variant, s, level_of(from, s), level_of(to_levels, s)])
		steps.append(_step(s, level_of(from, s), level_of(to_levels, s), rng))
	return {"seq": seq, "variant": variant, "first_build": first, "steps": steps}


## One letter per stat and per socket, for the compact answers text of a request.
const STAT_CODE := {"speed": "s", "torque": "t", "range": "r", "cargo": "c", "traction": "g"}
const PORT_CODE := {"motor": "m", "battery": "b", "hub": "h", "deck": "d", "data": "x"}


## Request params of an assembly or refit (ActionRequest allows at most 8 plain params, strings up to 64 letters):
## the five levels as ints, the transaction number "seq", the example number "variant" and the answers as text
## (encode_answers). `challenge` is RoverModel.challenge(state, levels).
static func build_params(levels: Dictionary, challenge_data: Dictionary, answers: Dictionary) -> Dictionary:
	var p := {}
	for s: String in STATS:
		p[s] = level_of(levels, s)
	p["seq"] = int(challenge_data.get("seq", 0))
	p["variant"] = int(challenge_data.get("variant", 0))
	p["answers"] = encode_answers(answers)
	return p


## The levels named in request params (a stat that is missing keeps `fallback`'s level).
static func levels_from_params(params: Dictionary, fallback: Dictionary) -> Dictionary:
	var out := clean_levels(fallback)
	for s: String in STATS:
		if params.has(s):
			out[s] = clampi(int(params[s]), 1, MAX_LEVEL)
	return out


## {stat: {"module": i, "port": id, "check": i}} as text: 4 letters per stat ("r0b2s1m0" = range: module 0, battery
## bus, check 2; speed: module 1, motor port, check 0). Unknown or incomplete answers are left out.
static func encode_answers(answers: Dictionary) -> String:
	var out := ""
	for s: String in STATS:
		var a: Variant = answers.get(s, null)
		if not (a is Dictionary):
			continue
		var ad := a as Dictionary
		if not (ad.has("module") and ad.has("port") and ad.has("check")) or not PORT_CODE.has(String(ad.port)):
			continue
		out += "%s%d%s%d" % [String(STAT_CODE[s]), clampi(int(ad.module), 0, 9), String(PORT_CODE[String(ad.port)]), clampi(int(ad.check), 0, 9)]
	return out


## The answers dictionary of an encoded text ({} parts for anything that does not read).
static func decode_answers(text: String) -> Dictionary:
	var stat_of := {}
	for s: String in STAT_CODE:
		stat_of[String(STAT_CODE[s])] = s
	var port_of := {}
	for p: String in PORT_CODE:
		port_of[String(PORT_CODE[p])] = p
	var out := {}
	var i := 0
	while i + 4 <= text.length():
		var chunk := text.substr(i, 4)
		i += 4
		var s := String(stat_of.get(chunk[0], ""))
		var port := String(port_of.get(chunk[2], ""))
		if s == "" or port == "" or not chunk[1].is_valid_int() or not chunk[3].is_valid_int():
			continue
		out[s] = {"module": int(chunk[1]), "port": port, "check": int(chunk[3])}
	return out


## Checks answers {stat: {"module": int, "port": String, "check": int}} against a challenge.
## {"ok": bool, "missing": bool, "feedback": {stat: [words]}}.
static func check_answers(ch: Dictionary, answers: Dictionary) -> Dictionary:
	var feedback := {}
	var missing := false
	for step: Dictionary in ch.get("steps", []):
		var s := String(step.stat)
		var a: Variant = answers.get(s, null)
		if not (a is Dictionary) or not (a as Dictionary).has("module") or not (a as Dictionary).has("port") or not (a as Dictionary).has("check"):
			missing = true
			continue
		var ad := a as Dictionary
		var lines: Array = []
		var mods: Array = step.modules
		var mi := int(ad.module) if (ad.module is int or ad.module is float) else -1
		if mi < 0 or mi >= mods.size() or not bool((mods[mi] as Dictionary).ok):
			var why := String((mods[mi] as Dictionary).why) if mi >= 0 and mi < mods.size() else "no module was chosen"
			lines.append("Module: that one does not fit (%s). %s" % [why, String(step.need)])
		if String(ad.port) != String(step.port):
			lines.append("Socket: the %s connects to the %s." % [String(step.module), String(PORTS.get(String(step.port), step.port)).to_lower()])
		var ci := int(ad.check) if (ad.check is int or ad.check is float) else -1
		if ci != int(step.answer):
			lines.append("Check: not quite. %s" % String(step.explain))
		if not lines.is_empty():
			feedback[s] = lines
	return {"ok": not missing and feedback.is_empty(), "missing": missing, "feedback": feedback}


## One stat's part of the assembly check, for the module at level `to` (a lower level fits a smaller module).
static func _step(s: String, from: int, to: int, rng: RandomNumberGenerator) -> Dictionary:
	var b := RoverBalance.get_current()
	var volts: int = b.example_voltages[rng.randi() % b.example_voltages.size()] if not b.example_voltages.is_empty() else 120
	var step := {"stat": s, "module": String(MODULE_NAMES[s]), "from": from, "to": to, "port": String(RIGHT_PORT[s])}
	var right := {}
	var wrong: Array = []
	match s:
		"speed":
			var kw := RoverBalance.at_level(b.motor_power_kw, to)
			var amps := roundi(kw * 1000.0 / float(volts))
			step.need = "Look for: a %s kW drive motor for the %d V battery, with a MOTOR-4 plug." % [_n(kw), volts]
			right = {"text": "Drive motor · %s kW · %d V · MOTOR-4 plug" % [_n(kw), volts], "ok": true, "why": ""}
			wrong = [{"text": "Drive motor · %s kW · 24 V · MOTOR-4 plug" % _n(kw), "ok": false, "why": "it is made for 24 V, not the %d V battery" % volts},
				{"text": "Water pump motor · %s kW · %d V · PUMP-2 plug" % [_n(kw), volts], "ok": false, "why": "it is a pump motor with a PUMP-2 plug"},
				{"text": "Drive motor · %s kW · %d V · MOTOR-4 plug · shaft will not turn" % [_n(kw), volts], "ok": false, "why": "its shaft is stuck, so it is broken"}]
			step.question = "The motor uses %s kW from the %d V battery. How much current flows? (current = power ÷ voltage)" % [_n(kw), volts]
			step.explain = "%s kW is %d W, and %d W ÷ %d V = about %d A." % [_n(kw), roundi(kw * 1000.0), roundi(kw * 1000.0), volts, amps]
			_options(step, amps, [maxi(1, roundi(amps / 2.0)), amps * 2, roundi(kw * float(volts) / 100.0)], "%d A", rng)
		"torque":
			var force := RoverBalance.at_level(b.drive_force_n, to)
			var radius: float = b.example_wheel_radii[rng.randi() % b.example_wheel_radii.size()] if not b.example_wheel_radii.is_empty() else 0.5
			var per_wheel := roundi(force / 4.0)
			var torque := roundi(float(per_wheel) * radius)
			var push := roundi(float(torque) / radius)
			step.need = "Look for: gearboxes that give each wheel %d N·m, with a splined shaft that fits the hubs." % torque
			right = {"text": "Wheel gearbox ×4 · %d N·m · splined shaft fits the hubs" % torque, "ok": true, "why": ""}
			wrong = [{"text": "Wheel gearbox ×4 · %d N·m · thin round shaft" % torque, "ok": false, "why": "its round shaft does not fit the splined hubs"},
				{"text": "Wheel gearbox ×4 · %d N·m · splined shaft fits the hubs" % roundi(torque / 2.0), "ok": false, "why": "it gives only half the turning force needed"},
				{"text": "Wheel gearbox ×4 · %d N·m · cracked case, oil leaking" % torque, "ok": false, "why": "its case is cracked"}]
			step.question = "Each wheel turns with %d N·m and its radius is %s m. How hard does one wheel push the ground? (push = turning force ÷ radius)" % [torque, _n(radius)]
			step.explain = "%d N·m ÷ %s m = about %d N for each wheel." % [torque, _n(radius), push]
			_options(step, push, [roundi(float(torque) * radius), push * 2, maxi(1, roundi(push / 4.0))], "%d N", rng)
		"range":
			var kwh := RoverBalance.at_level(b.battery_capacity_kwh, to)
			var ah := roundi(kwh * 1000.0 / float(volts))
			var stored := float(ah * volts) / 1000.0
			step.need = "Look for: a %d V battery pack of about %s kWh, with an orange high-voltage plug." % [volts, _n(kwh)]
			right = {"text": "Battery pack · %d Ah at %d V · orange high-voltage plug" % [ah, volts], "ok": true, "why": ""}
			wrong = [{"text": "Battery pack · %d Ah at %d V · swollen case" % [ah, volts], "ok": false, "why": "a swollen case means damaged cells, which are unsafe"},
				{"text": "Battery pack · %d Ah at 24 V · small grey plug" % ah, "ok": false, "why": "it is a 24 V pack with the wrong plug"},
				{"text": "Battery pack · %d Ah at %d V · orange high-voltage plug" % [roundi(ah / 2.0), volts], "ok": false, "why": "it stores only half the energy needed"}]
			step.question = "The pack holds %d Ah at %d V. How much energy can it store? (kWh = volts × amp-hours ÷ 1000)" % [ah, volts]
			step.explain = "%d V × %d Ah = %d Wh, which is %s kWh." % [volts, ah, ah * volts, _n(stored)]
			var tenths := roundi(stored * 10.0)
			_options(step, tenths, [tenths * 2, maxi(1, roundi(tenths / 2.0)), roundi(float(ah) * 10.0 / float(volts))], "kwh10", rng)
		"cargo":
			var cap := roundi(RoverBalance.at_level(b.cargo_capacity_kg, to))
			var weak := roundi(cap * 0.6 / 5.0) * 5
			step.need = "Look for: a cargo frame rated for %d kg whose 4 bolt holes match the deck rails." % cap
			right = {"text": "Cargo frame · rated %d kg · 4 bolt holes match the deck" % cap, "ok": true, "why": ""}
			wrong = [{"text": "Cargo frame · rated %d kg · 4 bolt holes match the deck" % weak, "ok": false, "why": "it is rated for less than %d kg" % cap},
				{"text": "Cargo frame · rated %d kg · 6 bolt holes in the wrong places" % cap, "ok": false, "why": "its bolt holes do not line up with the deck"},
				{"text": "Cargo frame · rated %d kg · bent rail" % cap, "ok": false, "why": "a bent frame is not safe to load"}]
			var safe := roundi(cap * rng.randf_range(0.55, 0.9) / 5.0) * 5
			var over := cap + 5 * rng.randi_range(5, 20)
			step.question = "The new frame is rated %d kg. Which load is safe to carry in it?" % cap
			step.explain = "A load must not be more than the rating: %d kg is safe, %d kg and %d kg are too heavy." % [safe, over, cap * 2]
			_options(step, safe, [over, cap * 2, over + 50], "%d kg", rng)
		"traction":
			var mu := RoverBalance.at_level(b.traction_mu, to)
			var mass := roundi((b.chassis_mass_kg + 2.0 * b.crew_member_kg) / 100.0) * 100 + 100 * rng.randi_range(0, 3)
			var weight := roundi(float(mass) * RoverBalance.MARS_GRAVITY)
			var grip := roundi(mu * float(weight))
			step.need = "Look for: four tyres with a grip of %s on sand that bolt onto the 5-bolt wheel hubs." % _n(mu)
			right = {"text": "Mesh tyres ×4 · grip %s on sand · 5-bolt pattern" % _n(mu), "ok": true, "why": ""}
			wrong = [{"text": "Mesh tyres ×4 · grip %s on sand · 5-bolt pattern · treads worn smooth" % _n(mu), "ok": false, "why": "worn treads grip much less than their label says"},
				{"text": "Mesh tyres ×4 · grip %s on sand · 4-bolt pattern" % _n(mu), "ok": false, "why": "they have 4 bolt holes, the hubs have 5"},
				{"text": "Mesh tyres ×4 · grip %s on sand · 5-bolt pattern" % _n(maxf(0.1, mu - 0.2)), "ok": false, "why": "they grip less than needed"}]
			step.question = "On Mars this rover presses on the ground with %d N. With a grip of %s, how hard can the wheels push before they slip? (push = grip × weight)" % [weight, _n(mu)]
			step.explain = "%s × %d N = about %d N. Pushing harder than that makes the wheels spin." % [_n(mu), weight, grip]
			_options(step, grip, [roundi(float(weight) / mu), maxi(1, roundi(grip / 2.0)), weight], "%d N", rng)
	# (a) modules: the right one and two of the wrong ones, in a seeded order
	var pool := wrong.duplicate()
	_shuffle(pool, rng)
	var mods: Array = [right, pool[0], pool[1]]
	_shuffle(mods, rng)
	step.modules = mods
	# (b) sockets: the right one and two others, in a seeded order
	var others: Array = []
	for id: String in PORTS:
		if id != String(step.port):
			others.append(id)
	_shuffle(others, rng)
	var ports: Array = [String(step.port), others[0], others[1]]
	_shuffle(ports, rng)
	var port_list: Array = []
	for id: String in ports:
		port_list.append({"id": id, "text": String(PORTS[id])})
	step.ports = port_list
	return step


## Puts the right number and distinct wrong ones in a seeded order: step.options (words) and step.answer (index).
## `fmt` "kwh10" shows tenths of a kWh.
static func _options(step: Dictionary, right: int, wrongs: Array, fmt: String, rng: RandomNumberGenerator) -> void:
	var values: Array = [right]
	for w: Variant in wrongs:
		var v := int(w)
		while values.has(v) or v <= 0:
			v += maxi(1, absi(right) / 3)
		values.append(v)
		if values.size() == 3:
			break
	var order: Array = [0, 1, 2]
	_shuffle(order, rng)
	var texts: Array = []
	for i: int in order:
		var v := int(values[i])
		texts.append("%s kWh" % _n(float(v) / 10.0) if fmt == "kwh10" else fmt % v)
	step.options = texts
	step.answer = order.find(0)


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = list[i]
		list[i] = list[j]
		list[j] = t


## A number with at most 2 decimals and no trailing zeros.
static func _n(v: float) -> String:
	var t := String.num(v, 2)
	if t.contains("."):
		t = t.rstrip("0").rstrip(".")
	return t


static func _first(d: Dictionary, keys: Array) -> Variant:
	for k: String in keys:
		if d.has(k):
			return d[k]
	return null


static func _vectors(v: Variant) -> Array:
	var out: Array = []
	if not (v is Array):
		return out
	for e: Variant in v:
		var a: Variant = e
		if e is Dictionary:
			a = _first(e, ["position", "local", "offset", "pos"])
		if a is Array and (a as Array).size() >= 3:
			out.append(_vec(a))
	return out


static func _vec(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
