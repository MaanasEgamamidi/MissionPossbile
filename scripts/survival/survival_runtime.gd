class_name SurvivalRuntime
extends RefCounted
## Host real-time exposure integration. Only authoritative session steps can advance or resolve a hazard.
## Also runs med station healing (MedCare) and names each hazard for the death record (DeathReasons).

const DeathReasons := preload("res://scripts/survival/death_reasons.gd")
const MedCare := preload("res://scripts/survival/med_care.gd")

var pressure := LocalPressure.new()
var _session_ref: WeakRef

func _init(session: SessionService) -> void:
	_session_ref = weakref(session)

func clear_session() -> void:
	pressure.clear_session()

func functional_suit(actor: CharacterState) -> bool:
	var session := _session_ref.get_ref() as SessionService
	return session != null and actor.suit_on and actor.suit_integrity >= session.config.suit_min_integrity and actor.suit_charge > 0.0 and session.balance.suit_o2_capacity_kg > 0.0

func breathable_at(point: Vector3, was_in_chamber := false) -> bool:
	var session := _session_ref.get_ref() as SessionService
	return session != null and session.state != null and bool(pressure.query(session, point, was_in_chamber).breathable)

func status(character_id: StringName) -> Dictionary:
	var session := _session_ref.get_ref() as SessionService
	if session == null or session.state == null:
		return {"active": false, "remaining_seconds": 0.0}
	var actor := session.state.character(character_id)
	if actor == null:
		return {"active": false, "remaining_seconds": 0.0}
	return {"active": actor.exposure_active, "remaining_seconds": maxf(0.0, session.config.exposure_lethal_seconds - actor.lethal_exposure_seconds),
		"elapsed_seconds": actor.lethal_exposure_seconds, "deadline_seconds": session.config.exposure_lethal_seconds,
		"cause": actor.exposure_cause, "cause_id": actor.hazard_cause, "area": actor.exposure_area, "protected": actor.exposure_protected,
		"safe_recovery_seconds": actor.exposure_safe_seconds, "safe_recovery_required": session.config.exposure_safe_recovery_seconds,
		"action": "Return through the inner door to safe pressure, equip a suit, or ask the field engineer to service the seal." if actor.in_airlock_pressure_volume else "Reach breathable shelter or use a sealed suit with oxygen."}

func refresh_actor(actor: CharacterState) -> void:
	var session := _session_ref.get_ref() as SessionService
	if session == null or session.state == null or not session.authoritative or not actor.is_active():
		return
	var before := [actor.exposure_active, actor.exposure_protected, actor.exposure_cause, actor.exposure_area]
	var air := pressure.query(session, actor.position, actor.in_airlock_pressure_volume)
	actor.in_airlock_pressure_volume = bool(air.in_airlock)
	actor.outside = not bool(air.breathable)
	actor.exposure_protected = actor.outside and (functional_suit(actor) or RoverModel.cabin_sheltered(session.state, actor))   # rover L3 sealed cabin
	actor.exposure_active = actor.health > 0.0 and actor.outside and not actor.exposure_protected
	actor.exposure_area = String(air.area)
	actor.exposure_cause = ""
	if actor.exposure_active:
		actor.exposure_cause = String(air.cause)
		if actor.suit_on and actor.suit_integrity < session.config.suit_min_integrity:
			actor.exposure_cause = "SUIT SEAL FAILED - REACH SAFE PRESSURE"
		elif actor.suit_on and (actor.suit_charge <= 0.0 or session.balance.suit_o2_capacity_kg <= 0.0):
			actor.exposure_cause = "SUIT OXYGEN EMPTY - REACH SAFE PRESSURE"
		actor.hazard_cause = DeathReasons.hazard_id(session, actor, air)
		actor.exposure_safe_seconds = 0.0
	if before != [actor.exposure_active, actor.exposure_protected, actor.exposure_cause, actor.exposure_area]:
		_publish(session, actor)

func refresh_all() -> void:
	var session := _session_ref.get_ref() as SessionService
	if session == null or session.state == null or not session.authoritative:
		return
	for actor: CharacterState in session.state.active_characters():
		refresh_actor(actor)

func advance(seconds: float) -> void:
	var session := _session_ref.get_ref() as SessionService
	if session == null or session.state == null or not session.authoritative or session.paused:
		return
	if seconds <= 0.0:
		refresh_all()
		return
	for actor: CharacterState in session.state.active_characters():
		refresh_actor(actor)
		var previous_remaining := ceili(maxf(0.0, session.config.exposure_lethal_seconds - actor.lethal_exposure_seconds))
		if actor.exposure_active:
			actor.lethal_exposure_seconds += seconds
			if actor.lethal_exposure_seconds >= maxf(0.05, session.config.exposure_lethal_seconds) - 1e-8:
				var cause := actor.hazard_cause if actor.hazard_cause != "" else "unknown"
				actor.health = 0.0
				session.recover_character(actor.id, cause)
				continue
			if previous_remaining != ceili(maxf(0.0, session.config.exposure_lethal_seconds - actor.lethal_exposure_seconds)):
				_publish(session, actor)
		elif actor.lethal_exposure_seconds > 0.0:
			actor.exposure_safe_seconds += seconds
			if actor.exposure_safe_seconds >= maxf(0.0, session.config.exposure_safe_recovery_seconds) - 1e-8:
				actor.lethal_exposure_seconds = 0.0
				actor.exposure_safe_seconds = 0.0
				actor.hazard_cause = ""
				_publish(session, actor)
		else:
			MedCare.advance_actor(session, actor, seconds)

func reset_character(actor: CharacterState) -> void:
	var session := _session_ref.get_ref() as SessionService
	actor.lethal_exposure_seconds = 0.0
	actor.exposure_safe_seconds = 0.0
	actor.exposure_active = false
	actor.exposure_protected = false
	actor.exposure_cause = ""
	actor.hazard_cause = ""
	actor.in_airlock_pressure_volume = false
	if session != null:
		_publish(session, actor)

## Door facts from the world: 901/902 exit tunnel inner/outer, 912 garden dome outer door (its vestibule is Mars air
## while that door is open). Other ids are ignored.
func set_airlock_door_open(door_id: int, opened: bool) -> void:
	var session := _session_ref.get_ref() as SessionService
	if session == null or not session.authoritative:
		return
	pressure.set_door_open(door_id, opened)
	if session.state == null:
		return
	if door_id == 902 and opened and not session.paused:
		session.state.pressure.airlock_kpa = session.config.airlock_pressure_mars_kpa
		session.state.pressure.airlock_breathable = false
	pressure.advance(session, 0.0)
	refresh_all()
	session.events.state_changed.emit(&"local_pressure")

func pressure_info() -> Dictionary:
	var session := _session_ref.get_ref() as SessionService
	return pressure.info(session) if session != null and session.state != null else {}

## Developer-only host hook, deliberately absent from ActionService and any player-facing control.
func debug_trigger_airlock_fault() -> bool:
	var session := _session_ref.get_ref() as SessionService
	if not OS.is_debug_build() or session == null or not session.authoritative or session.state == null:
		return false
	var task: Dictionary = session.state.repair.tasks.get("T12", {})
	if task.is_empty():
		return false
	session.repair_runtime.begin_fault(session.state, "T12", int(task.puzzle_seed) + 1, 0.15)
	task.maintenance_schema = 1
	task.maintenance_fault = true
	task.maintenance_cooldown_seconds = 0.0
	session.state.pressure.airlock_kpa = session.config.airlock_pressure_mars_kpa
	session.state.pressure.airlock_breathable = false
	pressure.advance(session, 0.0)
	refresh_all()
	session.events.state_changed.emit(&"debug_airlock_fault")
	return true

func _publish(session: SessionService, actor: CharacterState) -> void:
	session.events.hazard_changed.emit(actor.id, status(actor.id))
	session.events.state_changed.emit(&"hazard")

func replica_dict() -> Dictionary:
	return {"pressure_doors": pressure.replica_dict()}

func apply_replica(data: Dictionary) -> void:
	pressure.apply_replica(data.get("pressure_doors", {}))
