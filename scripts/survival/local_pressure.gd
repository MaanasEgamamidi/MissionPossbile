class_name LocalPressure
extends RefCounted
## Explicit exit vestibule only. Chamber kPa is a local gameplay proxy, not a second mass-loss integrator.
## Existing note_airlock_cycle / LifeSupportModel remain the sole global airlock gas-ledger path.

const VOLUME := AABB(Vector3(20.2, -0.2, 10.3), Vector3(3.6, 3.7, 4.55))
const BOUNDARY_HYSTERESIS_M := 0.15
## Garden dome breathing volume (Godot x, z). The lighting zone "Garden dome" is the 11 m landing pad, but the glass
## shell and its ring wall end at about 8 m (gd_shell AABB half-size 7.95 m, gd_ring segments centred at 7.85 m,
## 0.3 m thick). The 8..11 m ring is Mars air: without this check a player who walked out of the garden airlock (or
## through a gap in the shell) could stand there with no suit and never start the four-second exposure.
const GARDEN_CENTRE_XZ := Vector2(50.0, 27.0)
const GARDEN_SHELL_RADIUS_M := 8.15
## The garden airlock vestibule between its outer door 912 (x 41.40..41.48) and the shell; it reaches past the shell
## radius (GardenDomeDoors). Breathable while the outer door is shut.
const GARDEN_VESTIBULE := AABB(Vector3(41.48, -0.2, 26.2), Vector3(2.4, 3.7, 1.6))
var doors := {901: false, 902: false, 912: false}

static func fresh() -> Dictionary:
	return {"version": 1, "airlock_kpa": 101.3, "airlock_breathable": true, "leaking": false, "repressurizing": false}

static func restore(saved: Dictionary) -> Dictionary:
	var result := fresh()
	result.airlock_kpa = clampf(float(saved.get("airlock_kpa", 101.3)), 0.0, 150.0)
	for key: String in ["airlock_breathable", "leaking", "repressurizing"]:
		result[key] = bool(saved.get(key, result[key]))
	return result

func clear_session() -> void:
	doors = {901: false, 902: false, 912: false}

func set_door_open(door_id: int, opened: bool) -> void:
	if doors.has(door_id):
		doors[door_id] = opened

func advance(session: SessionService, seconds: float) -> void:
	var data: Dictionary = session.state.pressure
	var task: Dictionary = session.state.repair.tasks.get("T12", {})
	# Owner, 2026-11-14: the broken exit-tunnel door (BP08, task T12) really leaks from the start of a new game until
	# its seal puzzle is solved; the tutorial makes everyone wear a helmet, so the suit keeps them safe meanwhile.
	var leaking := bool(task.get("maintenance_fault", false)) or PuzzleRegistry.is_broken(session.state, "T12")
	var vented := leaking or bool(doors[902])
	var target := session.config.airlock_pressure_mars_kpa if vented else session.config.airlock_pressure_nominal_kpa
	var speed := session.config.airlock_pressure_loss_kpa_per_second if vented else (session.config.airlock_pressure_nominal_kpa - session.config.airlock_pressure_mars_kpa) / maxf(0.05, session.config.airlock_pressure_recovery_seconds)
	data.airlock_kpa = move_toward(float(data.airlock_kpa), target, speed * maxf(0.0, seconds))
	data.leaking = leaking
	data.repressurizing = not vented and float(data.airlock_kpa) < session.config.airlock_pressure_nominal_kpa - 0.01
	if float(data.airlock_kpa) <= session.config.airlock_pressure_unsafe_kpa:
		data.airlock_breathable = false
	elif float(data.airlock_kpa) >= session.config.airlock_pressure_safe_kpa:
		data.airlock_breathable = true

func info(session: SessionService) -> Dictionary:
	var data: Dictionary = session.state.pressure
	var task: Dictionary = session.state.repair.tasks.get("T12", {})
	return {"pressure_kpa": float(data.airlock_kpa), "breathable": bool(data.airlock_breathable),
		"leaking": bool(data.leaking), "repressurizing": bool(data.repressurizing), "seal_condition": float(task.get("condition", 1.0)),
		"inner_open": bool(doors[901]), "outer_open": bool(doors[902]),
		"status": "Seal leaking" if bool(data.leaking) else ("Outer door open" if bool(doors[902]) else ("Repressurizing" if bool(data.repressurizing) else "Pressurized"))}

func query(session: SessionService, point: Vector3, was_inside := false) -> Dictionary:
	var box := VOLUME.grow(BOUNDARY_HYSTERESIS_M) if was_inside else VOLUME
	var chamber := box.has_point(point)
	var zone := String(session.zone_at_position.call(point)) if session.zone_at_position.is_valid() else "Habitat"
	if chamber:
		var info_now := info(session)
		return {"breathable": bool(info_now.breathable), "pressure_kpa": info_now.pressure_kpa, "kind": "airlock",
			"area": "Airlock exit vestibule", "in_airlock": true, "cause": "AIRLOCK PRESSURE LOST - SUIT REQUIRED",
			"action": "Return through the inner door to safe pressure, wear a suit, or ask the field engineer to service the seal."}
	if zone == ColonyZones.GARDEN and not _inside_garden(point):
		return {"breathable": false, "pressure_kpa": session.config.airlock_pressure_mars_kpa, "kind": "exterior",
			"area": "Outside the garden dome", "in_airlock": false,
			"cause": "NO BREATHABLE AIR - SUIT REQUIRED", "action": "Return to breathable shelter or use a sealed suit with oxygen."}
	if session.outside_test.is_valid() and bool(session.outside_test.call(point)):
		return {"breathable": false, "pressure_kpa": session.config.airlock_pressure_mars_kpa, "kind": "exterior",
			"area": zone if zone != "Habitat" else "Exterior", "in_airlock": false,
			"cause": "NO BREATHABLE AIR - SUIT REQUIRED", "action": "Return to breathable shelter or use a sealed suit with oxygen."}
	var o2 := session.balance.gas_kpa(session.state.cabin_o2_kg, GameBalance.MOLAR_O2)
	var n2 := session.balance.gas_kpa(session.state.cabin_n2_kg, GameBalance.MOLAR_N2)
	var co2 := session.balance.gas_kpa(session.state.cabin_co2_kg, GameBalance.MOLAR_CO2)
	var total := o2 + n2 + co2
	var safe := o2 >= session.balance.o2_low_kpa and co2 <= session.balance.co2_danger_kpa and total >= session.config.airlock_pressure_unsafe_kpa
	# Which cabin limit failed, for the death record: thin air first, then low oxygen, then carbon dioxide.
	var reason := "cabin_air" if total < session.config.airlock_pressure_unsafe_kpa else ("low_oxygen" if o2 < session.balance.o2_low_kpa else ("co2" if co2 > session.balance.co2_danger_kpa else ""))
	return {"breathable": safe, "pressure_kpa": total, "kind": "cabin", "reason": reason, "area": zone, "in_airlock": false,
		"cause": "CABIN AIR UNSAFE - SUIT REQUIRED", "action": "Reach safe pressure or use a sealed suit while life support is restored."}

func _inside_garden(point: Vector3) -> bool:
	if Vector2(point.x, point.z).distance_to(GARDEN_CENTRE_XZ) <= GARDEN_SHELL_RADIUS_M:
		return true
	return not bool(doors[912]) and GARDEN_VESTIBULE.has_point(point)

func replica_dict() -> Dictionary:
	return {"inner_open": bool(doors[901]), "outer_open": bool(doors[902]), "garden_outer_open": bool(doors[912])}

func apply_replica(data: Dictionary) -> void:
	doors[901] = bool(data.get("inner_open", false))
	doors[902] = bool(data.get("outer_open", false))
	doors[912] = bool(data.get("garden_outer_open", false))
