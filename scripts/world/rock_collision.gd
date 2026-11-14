class_name RockCollision
extends RefCounted
## Gives the 996 outdoor rocks ("Terrain rocks (realised)" in environment.glb, nodes named rock_NNNN) solid
## collision, so the player can no longer walk into them.
##
## The rocks are 14 distinct meshes placed with rotation and NON-UNIFORM scale. Physics shapes do not support
## non-uniform scale reliably, so each mesh gets one simplified convex hull (computed once), and each rock gets its
## own copy of that hull's points transformed into world space. A convex hull is slightly fuller than a craggy rock,
## which is the safe side: the player stands on or stops at the rock instead of sinking into it.

const NAME_PREFIX := "rock_"


## Adds a StaticBody3D named "Rocks" under `collision` with one convex shape per rock found under `world`.
## Returns the number of rocks given collision.
static func build(world: Node3D, collision: Node3D) -> int:
	var body := StaticBody3D.new()
	body.name = "Rocks"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	collision.add_child(body)
	var hulls := {}           # Mesh -> PackedVector3Array (mesh-local hull points)
	var count := 0
	for node in world.find_children(NAME_PREFIX + "*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var local: PackedVector3Array = hulls.get(mi.mesh, PackedVector3Array())
		if local.is_empty():
			var hull := mi.mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
			if hull == null:
				continue
			local = hull.points
			hulls[mi.mesh] = local
		var to_world := body.global_transform.affine_inverse() * mi.global_transform
		var points := PackedVector3Array()
		points.resize(local.size())
		for i in local.size():
			points[i] = to_world * local[i]
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		var owner_node := CollisionShape3D.new()
		owner_node.name = String(mi.name)
		owner_node.shape = shape
		owner_node.set_meta("object_name", String(mi.name))
		body.add_child(owner_node)
		count += 1
	return count
