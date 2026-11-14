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
## True while the character is outside the pressurised habitat (set by the host from SessionService.outside_test).
var outside := false
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
	for e in d.get("equipment", []):
		c.equipment.append(StringName(String(e)))
	for e in d.get("cargo", []):
		c.cargo.append(StringName(String(e)))
	return c


static func _v3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
