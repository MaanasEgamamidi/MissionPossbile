class_name CarryItem
extends RigidBody3D
## Physical prop whose held transform follows a hand exactly.

## Stable authoritative item identifier, also exposed to ray queries as metadata.
var item_id: StringName = &"":
	set(value):
		item_id = value
		set_meta("item_id", value)
var _anchor: Node3D
var _home: Node

func _init() -> void:
	collision_layer = Layers.ITEM
	collision_mask = Layers.WORLD | Layers.ITEM | Layers.DOOR
	# Project gravity is not edited; each free prop uses Mars gravity explicitly.
	custom_integrator = true

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	state.linear_velocity += Vector3.DOWN * GameConfig.MARS_GRAVITY * state.step

## Freezes and reparents to a hand, preserving exact follow during movement.
func attach_to(anchor: Node3D) -> void:
	if is_held():
		return
	_home = get_parent()
	_anchor = anchor
	freeze = true
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reparent(anchor, false)
	transform = Transform3D.IDENTITY

## Restores a free body in the world with optional throwing velocity.
func release(world_position: Vector3, velocity: Vector3 = Vector3.ZERO) -> void:
	if is_instance_valid(_home):
		reparent(_home, true)
	_anchor = null
	global_position = world_position
	collision_layer = Layers.ITEM
	collision_mask = Layers.WORLD | Layers.ITEM | Layers.DOOR
	freeze = false
	sleeping = false
	linear_velocity = velocity

## True while parented to a valid hand anchor.
func is_held() -> bool:
	return is_instance_valid(_anchor)

## Creates a visible box prop and matching collision shape.
static func make_crate(id: StringName, size: float = 0.4) -> CarryItem:
	var item := CarryItem.new()
	item.item_id = id
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	item.add_child(collider)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	item.add_child(mesh)
	return item
