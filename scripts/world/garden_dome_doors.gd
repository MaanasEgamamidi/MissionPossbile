class_name GardenDomeDoors
extends RefCounted
## Sliding airlock doors for the garden dome (the greenhouse south-east of the base). Its airlock vestibule (manifest
## object gd_airlock) is modelled as an open tunnel with no door leaves, so the dome was open to Mars. This adds an
## outer and an inner pair of sliding leaves, paired like the exit tunnel airlock (EnvironmentCollision): one door at a
## time, with the same pressure cycle in between.
##
## Measured from the gd_airlock triangles (tools/godot/diag_gd_airlock_geom.gd), Godot world metres: the tunnel runs
## along x from 41.04 (Mars side) to 43.56 (dome side), inside z 26.2..27.8 (1.6 m), floor y 0.09, ceiling y 2.35,
## side walls 0.7 m thick (outer faces z 25.5 and 28.5). Leaves slide sideways (along z) into those walls.

## Inner door (dome side) first: the lower id has the right of way when someone stands where both doors sense them.
const DOORS: Array[Dictionary] = [
	{"id": 911, "name": "GardenDoorInner", "x": Vector2(43.16, 43.24), "out": 1.0},
	{"id": 912, "name": "GardenDoorOuter", "x": Vector2(41.40, 41.48), "out": -1.0},
]
const DOOR_Z := Vector2(26.2, 27.8)
const DOOR_Y := Vector2(0.09, 2.34)
## How far each 0.8 m leaf slides into its side wall (the wall is 0.7 m thick plus the jamb: the leaf never shows outside).
const SLIDE_M := 0.72
## The chamber between the doors is only 1.7 m long, so each door senses on its own side of it: the sensing sphere is
## moved SENSE_SHIFT_M away from the chamber. A player between the two reaches is sensed by neither door (the one behind
## closes, then the one ahead cycles and opens), so they never hold each other shut.
const SENSE_SHIFT_M := 0.9
const SENSE_RADIUS_M := 1.3
## Materials of the vestibule itself, so the leaves match it.
const LEAF_MATERIAL := "steel"
const STRIPE_MATERIAL := "kit_hazard_y"


## Adds the doors under `parent` and returns their controllers (empty if the vestibule is not in `world`).
static func build(world: Node, parent: Node3D) -> Array[DoorController]:
	var made: Array[DoorController] = []
	var vestibule := world.find_child("gd_airlock", true, false) as MeshInstance3D
	if vestibule == null:
		return made
	var leaf_mat := _material(vestibule, LEAF_MATERIAL)
	var stripe_mat := _material(vestibule, STRIPE_MATERIAL)
	var doors_node := Node3D.new()
	doors_node.name = "GardenDomeDoors"
	parent.add_child(doors_node)
	# leaf space: x across the doorway (world +z, the slide direction), y up, z through the door (world -x)
	var basis := Basis(Vector3.UP, -PI / 2.0)
	var centre_z := (DOOR_Z.x + DOOR_Z.y) * 0.5
	for d: Dictionary in DOORS:
		var door := DoorController.new()
		door.name = d.name
		door.door_id = int(d.id)
		door.sense_radius = SENSE_RADIUS_M
		door.sense_offset = Vector3(SENSE_SHIFT_M * float(d.out), 0.0, 0.0)
		var x: Vector2 = d.x
		for side: int in [-1, 1]:
			var leaf_name := "%s_%s" % [d.name, "L" if side < 0 else "R"]
			var z0 := DOOR_Z.x if side < 0 else centre_z
			var z1 := centre_z if side < 0 else DOOR_Z.y
			var centre := Vector3((x.x + x.y) * 0.5, (DOOR_Y.x + DOOR_Y.y) * 0.5, (z0 + z1) * 0.5)
			var size := Vector3(z1 - z0, DOOR_Y.y - DOOR_Y.x, x.y - x.x)   # in leaf space
			var pose := Transform3D(basis, centre)
			door.add_leaf(leaf_name, pose, SLIDE_M * side, [{"c": [0, 0, 0], "h": [size.x * 0.5, size.y * 0.5, size.z * 0.5], "q": [0, 0, 0, 1]}])
			var visual := _leaf_visual(leaf_name, size, side, leaf_mat, stripe_mat)
			visual.layers = vestibule.layers
			vestibule.get_parent().add_child(visual)
			visual.global_transform = pose
		doors_node.add_child(door)
		door.attach_visuals(world)
		made.append(door)
	made[0].partner = made[1]
	made[1].partner = made[0]
	return made


## One leaf: a steel slab with a hazard stripe down its meeting edge, on both faces.
static func _leaf_visual(leaf_name: String, size: Vector3, side: int, leaf_mat: Material, stripe_mat: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = leaf_name
	var slab := BoxMesh.new()
	slab.size = size
	slab.material = leaf_mat
	visual.mesh = slab
	var stripe := MeshInstance3D.new()
	stripe.name = "Stripe"
	var bar := BoxMesh.new()
	bar.size = Vector3(0.08, size.y * 0.9, size.z + 0.01)
	bar.material = stripe_mat
	stripe.mesh = bar
	stripe.position = Vector3((size.x * 0.5 - 0.06) * -side, 0.0, 0.0)   # the edge nearest the doorway centre
	visual.add_child(stripe)
	return visual


static func _material(mi: MeshInstance3D, wanted: String) -> Material:
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s)
		if m != null and m.resource_name == wanted:
			return m
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color(0.62, 0.64, 0.66)
	fallback.metallic = 0.6
	fallback.roughness = 0.45
	return fallback
