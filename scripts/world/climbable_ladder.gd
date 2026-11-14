class_name ClimbableLadder
extends Area3D
## The hangar's authored mezzanine deck is 2.70 m. Its ladder rails stay solid, but rungs do not seal the exit.
var deck_height := 2.70

func _init() -> void:
	collision_layer = Layers.LADDER
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.95, 3.6, 1.9)
	shape.shape = box
	shape.position = Vector3(0, 1.5, 0)
	add_child(shape)

func front() -> Vector3:
	return global_basis.z.normalized()

func bottom_y() -> float:
	return global_position.y

func top_y() -> float:
	return global_position.y + deck_height
