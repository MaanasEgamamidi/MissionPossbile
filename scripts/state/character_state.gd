class_name CharacterState
extends RefCounted
## One of the four crew members. Everything personal travels with the character when control changes hands:
## equipment, cargo, health, stamina and suit charge. A character nobody controls is parked: it uses no supplies and
## its condition is frozen.

const SPECIALTIES: Array[StringName] = [&"electrical_comms", &"medical_life_support", &"biology_food", &"field_engineering_geology"]

var id: StringName = &""
var specialty: StringName = &""
var display_name := ""
## Multiplayer peer controlling this character; 0 = nobody (parked).
var owner_peer := 0
var position := Vector3.ZERO
var yaw := 0.0
var hub_spot := Vector3.ZERO
var health := 100.0
var stamina := 100.0
var suit_on := false
## Original rack and slot of the worn suit. Older saves are assigned a free slot on session begin.
var suit_rack: StringName = &""
var suit_slot := -1
## Portable tank charge, 0..100. Never refilled by equipping the suit or changing the camera.
var suit_charge := 100.0
## A closed suit with a failed seal is not protective even if its tank still has oxygen.
var suit_integrity := 1.0
## True while the character is outside the pressurised habitat (set by the host from SessionService.outside_test).
var outside := false
## Durable unpaused real-second hazard time. Only the authoritative SurvivalRuntime advances it.
var lethal_exposure_seconds := 0.0
var exposure_safe_seconds := 0.0
var exposure_active := false
var exposure_protected := false
var exposure_cause := ""
var exposure_area := ""
## Cause id (scripts/survival/death_reasons.gd) of the current or last air danger; cleared on recovery.
var hazard_cause := ""
## Why this crew member last died (contract in docs/revisions/UPGRADES_BRIEF.md): {"cause", "title", "text", "area",
## "at_hours", "count"}. Empty = never died. Written by the host before the Med Bay respawn; saved and replicated.
var last_death: Dictionary = {}
## Spatial hysteresis across the explicit airlock boundary; unrelated to lighting-zone membership.
var in_airlock_pressure_volume := false
var equipment: Array[StringName] = []
## Item ids carried by this character (see ColonyState.items).
var cargo: Array[StringName] = []


func is_active() -> bool:
	return owner_peer != 0


func to_dict() -> Dictionary:
	return {
		"id": String(id), "specialty": String(specialty), "display_name": display_name, "owner_peer": owner_peer,
		"position": [position.x, position.y, position.z], "yaw": yaw, "hub_spot": [hub_spot.x, hub_spot.y, hub_spot.z],
		"health": health, "stamina": stamina, "suit_on": suit_on, "suit_charge": suit_charge, "outside": outside,
		"lethal_exposure_seconds": lethal_exposure_seconds,
		"exposure_safe_seconds": exposure_safe_seconds, "exposure_active": exposure_active,
		"exposure_protected": exposure_protected, "exposure_cause": exposure_cause, "exposure_area": exposure_area,
		"hazard_cause": hazard_cause, "last_death": last_death.duplicate(true),
		"in_airlock_pressure_volume": in_airlock_pressure_volume, "suit_integrity": suit_integrity,
		"suit_rack": String(suit_rack), "suit_slot": suit_slot,
		"equipment": equipment.map(func(e: StringName) -> String: return String(e)),
		"cargo": cargo.map(func(e: StringName) -> String: return String(e)),
	}


## Copies a replicated record into this object in place, so nodes holding this CharacterState stay valid.
## `keep_pose` keeps position and yaw: a client keeps its own body's pose, which it is the authority for.
func assign_from(d: Dictionary, keep_pose := false) -> void:
	var c := CharacterState.from_dict(d)
	specialty = c.specialty
	display_name = c.display_name
	owner_peer = c.owner_peer
	if not keep_pose:
		position = c.position
		yaw = c.yaw
	hub_spot = c.hub_spot
	health = c.health
	stamina = c.stamina
	suit_on = c.suit_on
	suit_rack = c.suit_rack
	suit_slot = c.suit_slot
	suit_charge = c.suit_charge
	outside = c.outside
	lethal_exposure_seconds = c.lethal_exposure_seconds
	exposure_safe_seconds = c.exposure_safe_seconds
	exposure_active = c.exposure_active
	exposure_protected = c.exposure_protected
	exposure_cause = c.exposure_cause
	exposure_area = c.exposure_area
	hazard_cause = c.hazard_cause
	last_death = c.last_death
	in_airlock_pressure_volume = c.in_airlock_pressure_volume
	suit_integrity = c.suit_integrity
	equipment = c.equipment
	cargo = c.cargo


static func from_dict(d: Dictionary) -> CharacterState:
	var c := CharacterState.new()
	c.id = StringName(String(d.get("id", "")))
	c.specialty = StringName(String(d.get("specialty", "")))
	c.display_name = String(d.get("display_name", ""))
	c.owner_peer = int(d.get("owner_peer", 0))
	c.position = _v3(d.get("position", [0, 0, 0]))
	c.yaw = float(d.get("yaw", 0.0))
	c.hub_spot = _v3(d.get("hub_spot", [0, 0, 0]))
	c.health = float(d.get("health", 100.0))
	c.stamina = float(d.get("stamina", 100.0))
	c.suit_on = bool(d.get("suit_on", false))
	c.suit_rack = StringName(String(d.get("suit_rack", "")))
	c.suit_slot = int(d.get("suit_slot", -1))
	c.suit_charge = float(d.get("suit_charge", 100.0))
	c.outside = bool(d.get("outside", false))
	c.lethal_exposure_seconds = maxf(0.0, float(d.get("lethal_exposure_seconds", 0.0)))
	c.exposure_safe_seconds = maxf(0.0, float(d.get("exposure_safe_seconds", 0.0)))
	c.exposure_active = bool(d.get("exposure_active", false))
	c.exposure_protected = bool(d.get("exposure_protected", false))
	c.exposure_cause = String(d.get("exposure_cause", ""))
	c.exposure_area = String(d.get("exposure_area", ""))
	c.hazard_cause = String(d.get("hazard_cause", ""))
	c.last_death = _death(d.get("last_death", {}))
	c.in_airlock_pressure_volume = bool(d.get("in_airlock_pressure_volume", false))
	c.suit_integrity = clampf(float(d.get("suit_integrity", 1.0)), 0.0, 1.0)
	for e in d.get("equipment", []):
		c.equipment.append(StringName(String(e)))
	for e in d.get("cargo", []):
		c.cargo.append(StringName(String(e)))
	return c


## A saved or replicated death record in the contract's types; anything else becomes "never died".
static func _death(v: Variant) -> Dictionary:
	if not (v is Dictionary) or (v as Dictionary).is_empty():
		return {}
	var d: Dictionary = v
	return {"cause": String(d.get("cause", "unknown")), "title": String(d.get("title", "")), "text": String(d.get("text", "")),
		"area": String(d.get("area", "")), "at_hours": float(d.get("at_hours", 0.0)), "count": maxi(1, int(d.get("count", 1)))}


static func _v3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
