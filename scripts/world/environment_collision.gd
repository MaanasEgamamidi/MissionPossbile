class_name EnvironmentCollision
extends RefCounted
## Collision and working doors for the glass hall around the colony. The hall, its exit tunnel and the tunnel's two
## sliding doors are scenery in the environment file (Exterior env / Glass hall), not objects of the map manifest, so
## WorldCollision never gave them collision: players walked through the glass and the tunnel walls, and the tunnel
## doors were painted shut. This builds solid collision from the scenery meshes and cuts the door leaves out of the
## tunnel mesh so they can slide like every other colony door.

## Scenery meshes that become solid exactly as drawn (two-sided, so they stop players from inside and outside).
const SOLID: Array[String] = ["SFX_hall_glass", "SFX_hall_portal", "SFX_tunnel_shell"]
## The tunnel lining; its door leaves are cut out, the rest becomes solid.
const TUNNEL := "SFX_tunnel_inside"
## Door leaf slabs in world coordinates (metres), measured from the tunnel mesh: x across the tunnel, y up, z along it.
## Inner door: airlock side. Outer door: Mars side.
const DOORS: Array[Dictionary] = [
	{"id": 901, "name": "TunnelDoorInner", "z": Vector2(10.30, 10.65)},
	{"id": 902, "name": "TunnelDoorOuter", "z": Vector2(14.55, 14.85)},
]
const DOOR_X := Vector2(20.2, 23.8)
const DOOR_Y := Vector2(-0.01, 3.02)
const DOOR_CENTRE_X := 22.0
## How far each leaf slides into the tunnel wall.
const SLIDE_M := 1.75

## Adds the collision under `parent` and returns the door controllers it made (empty if the hall is not in `world`).
static func build(world: Node, parent: Node3D) -> Array[DoorController]:
	var made: Array[DoorController] = []
	var hall := _find_hall(world)
	if hall == null:
		return made
	var body := StaticBody3D.new()
	body.name = "GlassHall"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	parent.add_child(body)
	for mesh_name: String in SOLID:
		var mi := hall.find_child(mesh_name, true, false) as MeshInstance3D
		if mi != null:
			_add_trimesh(body, mi.mesh.get_faces(), mi.global_transform, mesh_name)
	var tunnel := hall.find_child(TUNNEL, true, false) as MeshInstance3D
	if tunnel == null:
		return made
	var split := _split_tunnel(tunnel)
	tunnel.mesh = split.rest
	_add_trimesh(body, (split.rest as ArrayMesh).get_faces(), tunnel.global_transform, TUNNEL)
	var doors_node := Node3D.new()
	doors_node.name = "EnvironmentDoors"
	parent.add_child(doors_node)
	for d: Dictionary in DOORS:
		var door := DoorController.new()
		door.name = d.name
		door.door_id = int(d.id)
		var z: Vector2 = d.z
		for side: int in [-1, 1]:
			var leaf_name := "%s_%s" % [d.name, "L" if side < 0 else "R"]
			var leaf_mesh: ArrayMesh = split.leaves[leaf_name]
			if leaf_mesh.get_surface_count() == 0:
				continue
			var visual := MeshInstance3D.new()
			visual.name = leaf_name
			visual.mesh = leaf_mesh
			visual.layers = tunnel.layers
			tunnel.get_parent().add_child(visual)
			visual.global_transform = tunnel.global_transform
			var x0 := DOOR_X.x if side < 0 else DOOR_CENTRE_X
			var x1 := DOOR_CENTRE_X if side < 0 else DOOR_X.y
			var centre := Vector3((x0 + x1) * 0.5, (DOOR_Y.x + DOOR_Y.y) * 0.5, (z.x + z.y) * 0.5)
			var half := Vector3((x1 - x0) * 0.5, (DOOR_Y.y - DOOR_Y.x) * 0.5, (z.y - z.x) * 0.5)
			# add_leaf slides along the pose's x axis; boxes are in the leaf's own space
			door.add_leaf(leaf_name, Transform3D(Basis(), centre), SLIDE_M * side, [{"c": [0, 0, 0], "h": [half.x, half.y, half.z], "q": [0, 0, 0, 1]}])
		doors_node.add_child(door)
		door.attach_visuals(world)
		made.append(door)
	# the tunnel is an airlock: one door at a time, with a pressure cycle in between
	if made.size() == 2:
		made[0].partner = made[1]
		made[1].partner = made[0]
	return made


static func _find_hall(world: Node) -> Node:
	for n: Node in world.find_children("Glass hall", "", true, false):
		if n.find_child("SFX_hall_glass", true, false) != null:
			return n
	return null


static func _add_trimesh(body: StaticBody3D, faces: PackedVector3Array, xf: Transform3D, shape_name: String) -> void:
	if faces.is_empty():
		return
	var world_faces := PackedVector3Array()
	world_faces.resize(faces.size())
	for i in faces.size():
		world_faces[i] = xf * faces[i]
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(world_faces)
	var cs := CollisionShape3D.new()
	cs.name = shape_name
	cs.shape = shape
	body.add_child(cs)


## Splits the tunnel mesh into the lining and one mesh per door leaf. A triangle belongs to a leaf when all three
## corners lie inside that leaf's slab.
static func _split_tunnel(mi: MeshInstance3D) -> Dictionary:
	var xf := mi.global_transform
	var rest := ArrayMesh.new()
	var leaves := {}
	for d: Dictionary in DOORS:
		for s: String in ["L", "R"]:
			leaves["%s_%s" % [d.name, s]] = ArrayMesh.new()
	var src := mi.mesh
	for surface in src.get_surface_count():
		var arr := src.surface_get_arrays(surface)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var keep := PackedInt32Array()
		var leaf_idx := {}
		for t in range(0, idx.size(), 3):
			var owner := ""
			for d: Dictionary in DOORS:
				var all_in := true
				var sum_x := 0.0
				for k in 3:
					var p := xf * verts[idx[t + k]]
					sum_x += p.x
					var z: Vector2 = d.z
					if p.x < DOOR_X.x or p.x > DOOR_X.y or p.y < DOOR_Y.x or p.y > DOOR_Y.y or p.z < z.x or p.z > z.y:
						all_in = false
						break
				if all_in:
					owner = "%s_%s" % [d.name, "L" if sum_x / 3.0 < DOOR_CENTRE_X else "R"]
					break
			if owner == "":
				keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
			else:
				# packed arrays are values: append to a copy and store it back
				var list: PackedInt32Array = leaf_idx.get(owner, PackedInt32Array())
				list.append_array([idx[t], idx[t + 1], idx[t + 2]])
				leaf_idx[owner] = list
		var material := src.surface_get_material(surface)
		if not keep.is_empty():
			_add_surface(rest, arr, keep, material)
		for owner: String in leaf_idx:
			_add_surface(leaves[owner], arr, leaf_idx[owner], material)
	return {"rest": rest, "leaves": leaves}


static func _add_surface(target: ArrayMesh, arr: Array, indices: PackedInt32Array, material: Material) -> void:
	var copy := arr.duplicate()
	copy[Mesh.ARRAY_INDEX] = indices
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, copy)
	target.surface_set_material(target.get_surface_count() - 1, material)
