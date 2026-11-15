class_name RoverSystem
extends RefCounted
## The rover's part of the 5 Hz host tick (Prompt 10, part 1), run by ColonySim.post_systems after power and life
## support: charging at the garage charger, freeing seats of crew nobody plays any more, keeping loaded cargo (and
## seated crew) at the rover's pose. `note_driven()` is the host's drive accounting, called by the vehicle part.
##
## Ledger (ColonyState.ledger, running totals since the game began):
##   rover_charge_kwh         taken from the colony battery by the charger. Colony battery identity:
##                            battery now = start + battery_in - battery_loss - battery_out - rover_charge_kwh
##   rover_charge_loss_kwh    lost as heat in the charger
##   rover_drive_kwh          used from the rover battery by driving
##   rover_refit_clamped_kwh  energy that did not fit in a smaller battery after a refit (it left with the removed modules)
## Rover upgrade path (RoverModel.track_level, RoverBalance "Rover upgrade path"):
##   rover_rtg_kwh            put into the rover battery by the RTG cart (L5), parked or driving
##   rover_fuel_cell_kwh      moved from the fuel-cell tanks into the rover battery by the range extender (L4+)
##   rover_fuel_cell_o2_kg    taken from the colony's oxygen store to refill the fuel cell at the charger (L4+), at
##                            RoverBalance.fuel_cell_o2_kg_per_kwh (0.45 kg O2 per kWh: 6.3 kg for a full 14 kWh)
##   rover_cabin_o2_kg        breathed by crew seated in the pressurized cabin (L3+), from the colony's oxygen store
##   Rover battery identity:  rover now = start + rover_charge_kwh - rover_charge_loss_kwh - rover_drive_kwh
##                            - rover_refit_clamped_kwh + rover_rtg_kwh + rover_fuel_cell_kwh
##   Fuel-cell identity:      tanks now = rover_fuel_cell_o2_kg / fuel_cell_o2_kg_per_kwh - rover_fuel_cell_kwh

const LEDGER_CHARGE := "rover_charge_kwh"
const LEDGER_LOSS := "rover_charge_loss_kwh"
const LEDGER_DRIVE := "rover_drive_kwh"
const LEDGER_CLAMP := "rover_refit_clamped_kwh"
const LEDGER_RTG := "rover_rtg_kwh"
const LEDGER_FC := "rover_fuel_cell_kwh"
const LEDGER_FC_O2 := "rover_fuel_cell_o2_kg"
const LEDGER_CABIN_O2 := "rover_cabin_o2_kg"
## Kind of the charger station (data/stations_rover.json).
const CHARGER_KIND := "rover_charger"
## Kind of the garage station.
const GARAGE_KIND := "garage"

## Words for each charge status.
const STATUS_TEXT := {"off": "Not charging", "charging": "Charging", "full": "Battery full",
	"paused_reserve": "Paused: the colony battery is down to its reserve", "paused_deficit": "Paused: the colony is short of power",
	"unplugged": "Stopped: the rover drove away from the charger", "not_built": "No rover yet"}

## Last pose this system moved the seated crew to (not saved; only avoids moving them when the rover has not moved).
var _last_pose := ""
## GameEvents this system has connected to (seats are freed at once on a disconnect or a recovery).
var _hooked: GameEvents = null
var _state: ColonyState = null


func step(state: ColonyState, balance: GameBalance, _phase: float, dt_hours: float, events: GameEvents) -> void:
	_state = state
	RoverModel.ensure(state)
	_hook(events)
	free_unplayed_seats(state)
	follow_pose(state, _last_pose != JSON.stringify(state.rover.pose))
	_last_pose = JSON.stringify(state.rover.pose)
	_charge(state, balance, dt_hours, events)
	run_upgrade_power(state, dt_hours)


## The rover upgrade path's energy (host, every tick): the RTG trickle (L5) into the battery, and the fuel cell (L4+):
## refilled from the colony's oxygen store while the rover is plugged in at the charger, otherwise feeding the battery
## once it is below RoverBalance.fuel_cell_start_fraction (a range extender).
static func run_upgrade_power(state: ColonyState, dt_hours: float) -> void:
	var r := state.rover
	if not bool(r.get("built", false)) or dt_hours <= 0.0:
		return
	var b := RoverBalance.get_current()
	var cap := float(RoverModel.stats(r.levels, 0.0).battery_capacity_kwh)
	var battery := float(r.battery_kwh)
	var rtg := RoverModel.rtg_kw(state) * dt_hours
	if rtg > 0.0:
		var add := minf(rtg, maxf(0.0, cap - battery))
		if add > 0.0:
			battery += add
			state.ledger[LEDGER_RTG] = float(state.ledger.get(LEDGER_RTG, 0.0)) + add
	var fc_cap := RoverModel.fuel_cell_capacity_kwh(state)
	var fc := clampf(float(r.get("fuel_cell_kwh", 0.0)), 0.0, fc_cap)
	if fc_cap > 0.0:
		if bool(r.charging) and in_charge_reach(state):
			var rate := maxf(1e-6, b.fuel_cell_o2_kg_per_kwh)
			var want_kwh := minf(fc_cap - fc, b.fuel_cell_refill_kwh_per_hour * dt_hours)
			var o2_floor := b.fuel_cell_o2_reserve_fraction * float(state.capacities.get(&"oxygen_kg", 0.0))
			var o2_free := maxf(0.0, state.store(&"oxygen_kg") - o2_floor)
			var kg := minf(maxf(0.0, want_kwh) * rate, o2_free)
			if kg > 0.0:
				var taken := -state.add_to_store(&"oxygen_kg", -kg)
				fc = minf(fc_cap, fc + taken / rate)
				state.ledger[LEDGER_FC_O2] = float(state.ledger.get(LEDGER_FC_O2, 0.0)) + taken
		elif fc > 0.0 and battery < cap * b.fuel_cell_start_fraction:
			var move := minf(minf(b.fuel_cell_kw * dt_hours, fc), maxf(0.0, cap - battery))
			if move > 0.0:
				battery += move
				fc -= move
				state.ledger[LEDGER_FC] = float(state.ledger.get(LEDGER_FC, 0.0)) + move
	r["fuel_cell_kwh"] = fc
	if battery > float(r.battery_kwh):
		r["empty_announced"] = false
		r["battery_kwh"] = battery


## Life-support hook (L3+ cabin): air for one crew member seated in the pressurized cabin over `dt` game hours,
## breathed instead of suit oxygen. The cabin's tanks are filled from the colony's oxygen store (game simplification:
## taken from the store directly). Returns the share of air it did not get (0..1), like LifeSupportModel.run_suit.
static func cabin_breathe(state: ColonyState, balance: GameBalance, _c: CharacterState, dt: float) -> float:
	var need := balance.oxygen_kg_per_hour * dt
	if need <= 0.0:
		return 0.0
	var got := -state.add_to_store(&"oxygen_kg", -need)
	state.ledger[LEDGER_CABIN_O2] = float(state.ledger.get(LEDGER_CABIN_O2, 0.0)) + got
	state.ledger["oxygen_used_kg"] = float(state.ledger.get("oxygen_used_kg", 0.0)) + got
	return (need - got) / need


## Frees the seat of a character on a disconnect (no owner any more) or a recovery, at once (also while paused).
func _hook(events: GameEvents) -> void:
	if events == null or _hooked == events:
		return
	_hooked = events
	# Methods, not lambdas: Godot drops these connections by itself if this system is freed before the events object.
	events.crew_ownership_changed.connect(_on_owner_changed)
	events.character_recovered.connect(_on_recovered)


func _on_owner_changed(id: StringName, peer: int) -> void:
	if peer == 0 and _state != null:
		free_seat_of(_state, String(id))


func _on_recovered(id: StringName, _info: Dictionary) -> void:
	if _state != null:
		free_seat_of(_state, String(id))


## Frees the seat of `character_id`. Returns the seat index it had, or -1.
static func free_seat_of(state: ColonyState, character_id: String) -> int:
	var i := RoverModel.seat_of(state, character_id)
	if i >= 0:
		(state.rover.seats as Array)[i] = ""
	return i


## Frees every seat whose character is gone or parked (nobody controls it: it waits at the hub).
static func free_unplayed_seats(state: ColonyState) -> void:
	var seats: Array = state.rover.get("seats", [])
	for i in seats.size():
		if String(seats[i]) != "" and RoverModel.seat_free(state, i):
			seats[i] = ""


## Puts the cargo bay's items at the rover's position (saves and caches stay right) and, when `move_crew`, the seated
## crew at their seats.
static func follow_pose(state: ColonyState, move_crew: bool) -> void:
	var p := RoverModel.pose_position(state)
	for id: Variant in state.rover.get("cargo", []):
		var rec: Dictionary = state.items.get(String(id), {})
		if not rec.is_empty():
			rec["position"] = [p.x, p.y, p.z]
	if not move_crew:
		return
	var seats: Array = state.rover.get("seats", [])
	for i in seats.size():
		var c := state.character(StringName(String(seats[i]))) if String(seats[i]) != "" else null
		if c != null:
			c.position = RoverModel.seat_world_position(state, i)


## The vehicle part stores a new pose of the rover (host): cargo and seated crew follow it at once.
static func note_pose(state: ColonyState, pose: Dictionary) -> void:
	RoverModel.ensure(state)
	if pose.get("position", null) is Array and pose.get("quat", null) is Array:
		state.rover["pose"] = {"position": (pose.position as Array).duplicate(), "quat": (pose.quat as Array).duplicate()}
	follow_pose(state, true)


## Host drive accounting: the rover drove `distance_m` with `climb_m` of net height gain. Takes the energy from the
## rover battery (RoverModel.energy_kwh_for_move with the cargo and crew aboard now), but never more than it holds:
## an empty battery leaves the rover able to coast and brake only. Returns the kWh used.
static func note_driven(state: ColonyState, events: GameEvents, distance_m: float, climb_m: float) -> float:
	RoverModel.ensure(state)
	var r := state.rover
	if not bool(r.built):
		return 0.0
	var d := maxf(0.0, distance_m)
	var need := RoverModel.energy_kwh_for_move(r.levels, RoverModel.cargo_mass_kg(state), d, climb_m, RoverModel.crew_aboard(state))
	var have := float(r.battery_kwh)
	var used := minf(need, have)
	r["battery_kwh"] = have - used
	state.ledger[LEDGER_DRIVE] = float(state.ledger.get(LEDGER_DRIVE, 0.0)) + used
	var trip: Dictionary = r.trip
	trip["distance_m"] = float(trip.distance_m) + d
	trip["climb_m"] = float(trip.climb_m) + maxf(0.0, climb_m)
	trip["energy_kwh"] = float(trip.energy_kwh) + used
	r["odometer_m"] = float(r.odometer_m) + d
	if float(r.battery_kwh) <= 1e-9 and need > 0.0 and not bool(r.empty_announced):
		r["empty_announced"] = true
		if events != null:
			events.system_alert.emit(&"rover_battery_empty", &"warn",
				"The rover battery is empty. The rover can only roll and brake now. Charge it at the garage charger.")
	return used


## The charger station's id, or "".
static func charger_id(state: ColonyState) -> String:
	for id: String in state.stations:
		if String((state.stations[id] as Dictionary).get("kind", "")) == CHARGER_KIND:
			return id
	return ""


## The garage station's id, or "".
static func garage_id(state: ColonyState) -> String:
	for id: String in state.stations:
		if String((state.stations[id] as Dictionary).get("kind", "")) == GARAGE_KIND:
			return id
	return ""


## Distance from the rover to a station, m (horizontal), or INF if there is no such station.
static func rover_distance_to_station(state: ColonyState, station_id: String) -> float:
	var st: Dictionary = state.stations.get(station_id, {})
	if st.is_empty():
		return INF
	return RoverModel.distance_to_rover(state, CharacterState._v3(st.position))


## True if the rover is parked close enough to the charger for its cable.
static func in_charge_reach(state: ColonyState) -> bool:
	return rover_distance_to_station(state, charger_id(state)) <= RoverBalance.get_current().charge_radius_m


## True if the rover stands in the garage (assembly and refits happen there).
static func in_garage(state: ColonyState) -> bool:
	return rover_distance_to_station(state, garage_id(state)) <= RoverBalance.get_current().garage_radius_m


## Colony battery energy the charger leaves alone, kWh: RoverBalance.charge_reserve_fraction of the capacity, or the
## life-support reserve of the energy_battery_reserve upgrade if that is higher.
static func charge_reserve_kwh(state: ColonyState) -> float:
	var cap := float(state.capacities.get(&"battery_kwh", 0.0))
	return maxf(PowerModel.life_support_reserve_kwh(state), RoverBalance.get_current().charge_reserve_fraction * cap)


## Why charging cannot run now ("" if it can), as a charge status: "not_built", "unplugged", "full", "paused_reserve",
## "paused_deficit".
static func charge_block(state: ColonyState) -> String:
	var r := state.rover
	if not bool(r.get("built", false)):
		return "not_built"
	if not in_charge_reach(state):
		return "unplugged"
	var cap := float(RoverModel.stats(r.levels, 0.0).battery_capacity_kwh)
	if float(r.battery_kwh) >= cap - 1e-9:
		return "full"
	if state.store(&"battery_kwh") <= charge_reserve_kwh(state) + 1e-9:
		return "paused_reserve"
	if state.power_deficit:
		return "paused_deficit"
	return ""


func _charge(state: ColonyState, balance: GameBalance, dt_hours: float, events: GameEvents) -> void:
	var r := state.rover
	if not bool(r.charging):
		r["charge_status"] = "off" if bool(r.built) else "not_built"
		return
	var block := charge_block(state)
	if block == "not_built" or block == "unplugged":
		r["charging"] = false
		r["charge_status"] = block
		if block == "unplugged" and events != null:
			events.system_alert.emit(&"rover_unplugged", &"info", "The rover left the charger, so charging stopped.")
		return
	if block != "":
		r["charge_status"] = block
		return
	var b := RoverBalance.get_current()
	var eff := clampf(b.charger_efficiency, 0.05, 1.0)
	var cap := float(RoverModel.stats(r.levels, 0.0).battery_capacity_kwh)
	var room := maxf(0.0, cap - float(r.battery_kwh))
	# The charger is a real load on the colony battery: never below the reserve, never past the battery's discharge limit.
	var discharge_left_kw := maxf(0.0, balance.battery_discharge_kw_max - maxf(0.0, -state.battery_kw))
	var draw := minf(minf(b.charger_kw, discharge_left_kw) * dt_hours, room / eff)
	draw = minf(draw, maxf(0.0, state.store(&"battery_kwh") - charge_reserve_kwh(state)))
	if draw <= 0.0:
		r["charge_status"] = "paused_reserve"
		return
	var taken := -state.add_to_store(&"battery_kwh", -draw)
	var into := taken * eff
	r["battery_kwh"] = minf(cap, float(r.battery_kwh) + into)
	if r.battery_kwh > 0.0:
		r["empty_announced"] = false
	state.ledger[LEDGER_CHARGE] = float(state.ledger.get(LEDGER_CHARGE, 0.0)) + taken
	state.ledger[LEDGER_LOSS] = float(state.ledger.get(LEDGER_LOSS, 0.0)) + (taken - into)
	# display only: the charger shows up in the colony's load and battery flow for this tick
	if dt_hours > 0.0:
		state.load_kw += taken / dt_hours
		state.served_kw += taken / dt_hours
		state.battery_kw -= taken / dt_hours
	r["charge_status"] = "charging" if float(r.battery_kwh) < cap - 1e-9 else "full"
