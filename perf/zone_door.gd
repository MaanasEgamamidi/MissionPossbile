class_name ZoneDoor
extends Node3D
## A connection between two Zones (or between one Zone and the outside): a sliding door, or a window.
## Doors follow their DoorController: is_open turns true on the frame the door STARTS to open (before its leaves have
## moved: DoorController.opening_started) and false once it is fully shut again (DoorController.closed_fully).
## Windows have no controller and are always transparent.

signal open_changed(opened: bool)
signal opening_started

var zone_a: Zone
var zone_b: Zone                 ## null for an exterior door (airlock outer door)
var leads_outside := false       ## true for doors that open onto Mars
var transparent := false         ## glass in the leaves, or a window: a sight line exists even when closed
var is_window := false
var controller: DoorController   ## null for a window
var closed_occluder: OccluderInstance3D  ## optional: only enabled while the door is closed
var is_open := false: set = set_open


func setup(door: DoorController) -> void:
	add_to_group(&"zone_door")
	controller = door
	if door != null:
		door.opening_started.connect(func(_id: int) -> void: set_open(true))
		door.closed_fully.connect(func(_id: int) -> void: set_open(false))
		is_open = door.open_amount > 0.0
	_sync_occluder()


func other(z: Zone) -> Zone:
	return zone_b if z == zone_a else zone_a


func joins(z: Zone) -> bool:
	return z != null and (zone_a == z or zone_b == z)


func lets_sight_through() -> bool:
	return is_open or transparent


func set_open(v: bool) -> void:
	if v == is_open:
		return
	is_open = v
	if is_open:
		opening_started.emit()
	_sync_occluder()
	open_changed.emit(is_open)


func _sync_occluder() -> void:
	if closed_occluder != null:
		closed_occluder.visible = not is_open
