extends SceneTree
## Fits the walkable height grid to the real surface of scenery meshes by probing them with downward rays.
##   --mode raise (default): keep the higher of grid and mesh. Used for meshes that sit on the ground, such as the
##     sand drifts (`SFX_drifts` in environment.glb), which are not part of terrain.glb: without this the player's
##     legs sank into them.
##   --mode set: replace the grid with the mesh surface wherever a ray hits. Used to rebuild the grid from the
##     terrain itself: the first grid kept the HIGHEST vertex in each 1 m cell, which lies above the true surface on
##     every slope, so the player hovered over dunes.
##   --nodes A,B (default SFX_drifts) or --all (every mesh in the scene).
## Before and after, it reports how far the grid is from the probed surface at 4,000 random points inside the meshes.
## Run: godot --headless --path . --script res://tools/godot/heightmap_add_meshes.gd --
##        [--scene res://assets/colony/environment.glb] [--nodes SFX_drifts | --all] [--mode raise|set] [--grid res://data/terrain_height.res]

const PROBE_LAYER := 1 << 30


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := "res://assets/colony/environment.glb"
	var node_names := PackedStringArray(["SFX_drifts"])
	var use_all := false
	var mode := "raise"
	var grid_path := "res://data/terrain_height.res"
	for i in args.size():
		match args[i]:
			"--scene": scene_path = args[i + 1]
			"--nodes": node_names = args[i + 1].split(",")
			"--all": use_all = true
			"--mode": mode = args[i + 1]
			"--grid": grid_path = args[i + 1]
	var grid := load(grid_path) as TerrainHeight
	var packed := load(scene_path) as PackedScene
	if grid == null or packed == null or not (mode in ["raise", "set"]):
		push_error("Cannot load %s or %s, or bad --mode" % [grid_path, scene_path])
		quit(1)
		return
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	await process_frame          # global transforms are only valid once the scene is in the running tree
	var meshes: Array[MeshInstance3D] = []
	if use_all:
		for m in scene.find_children("*", "MeshInstance3D", true, false):
			meshes.append(m as MeshInstance3D)
	else:
		for node_name in node_names:
			var found := scene.find_child(node_name, true, false)
			if found == null:
				push_error("No node named %s in %s" % [node_name, scene_path])
				quit(1)
				return
			if found is MeshInstance3D:
				meshes.append(found as MeshInstance3D)
			for m in found.find_children("*", "MeshInstance3D", true, false):
				meshes.append(m as MeshInstance3D)
	var boxes: Array[AABB] = []
	for mi: MeshInstance3D in meshes:
		var body := StaticBody3D.new()
		body.collision_layer = PROBE_LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = mi.mesh.create_trimesh_shape()
		body.add_child(shape)
		root.add_child(body)
		body.global_transform = mi.global_transform
		boxes.append(mi.global_transform * mi.get_aabb())
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	print("BEFORE %s" % _error_report(grid, space, boxes))
	var changed := 0
	var largest := 0.0
	var probed := 0
	for box: AABB in boxes:
		var ix0 := maxi(0, int(floor((box.position.x - grid.origin.x) / grid.cell)))
		var ix1 := mini(grid.width - 1, int(ceil((box.end.x - grid.origin.x) / grid.cell)))
		var iz0 := maxi(0, int(floor((box.position.z - grid.origin.y) / grid.cell)))
		var iz1 := mini(grid.depth - 1, int(ceil((box.end.z - grid.origin.y) / grid.cell)))
		for iz in range(iz0, iz1 + 1):
			for ix in range(ix0, ix1 + 1):
				var x := grid.origin.x + float(ix) * grid.cell
				var z := grid.origin.y + float(iz) * grid.cell
				var y := _surface(space, x, z)
				probed += 1
				if is_nan(y):
					continue
				var i := iz * grid.width + ix
				var old := grid.heights[i]
				if (mode == "raise" and y > old + 0.005) or (mode == "set" and absf(y - old) > 0.0005):
					largest = maxf(largest, absf(y - old))
					grid.heights[i] = y
					changed += 1
	print("AFTER  %s" % _error_report(grid, space, boxes))
	var err := ResourceSaver.save(grid, grid_path)
	print("CHANGED %d of %d probed cells (mode %s, largest change %.3f m) from %s; saved %s: %s" % [
		changed, probed, mode, largest, "all meshes" if use_all else ",".join(node_names), grid_path, error_string(err)])
	quit(0 if err == OK else 1)


## Height of the highest probed surface under (x, z), or NAN.
func _surface(space: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -400.0, z), PROBE_LAYER)
	var hit := space.intersect_ray(q)
	return NAN if hit.is_empty() else float((hit.position as Vector3).y)


## Grid minus surface at random points: positive = the grid (where the player stands) is above the drawn ground.
func _error_report(grid: TerrainHeight, space: PhysicsDirectSpaceState3D, boxes: Array[AABB]) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var diffs: Array[float] = []
	var tries := 0
	while diffs.size() < 4000 and tries < 40000:
		tries += 1
		var box := boxes[rng.randi_range(0, boxes.size() - 1)]
		var x := rng.randf_range(box.position.x, box.end.x)
		var z := rng.randf_range(box.position.z, box.end.z)
		var y := _surface(space, x, z)
		if not is_nan(y):
			diffs.append(grid.height_at(x, z) - y)
	if diffs.is_empty():
		return "no surface found"
	diffs.sort()
	var mean := 0.0
	for d in diffs:
		mean += d
	mean /= float(diffs.size())
	var n := diffs.size()
	return "grid - surface over %d points: mean %+.3f m, median %+.3f, 95th %+.3f, max %+.3f, min %+.3f" % [
		n, mean, diffs[n / 2], diffs[int(n * 0.95)], diffs[n - 1], diffs[0]]
