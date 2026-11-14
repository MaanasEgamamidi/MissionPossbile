extends SceneTree
## Bakes the walking-route grid used by the dust warning's return margin: data/weather/route_grid.res.
## Run: ..\godot.cmd --headless --path . --script res://tools/godot/bake_route_grid.gd
## Reads the exact rock boxes (mesh bounds + placement) from the environment scene when it is present; otherwise the
## rocks come from the manifest's placement matrices (see ReturnRoutes.build).

const ENVIRONMENT := "res://assets/colony/environment.glb"


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var rocks: Array = []
	if ResourceLoader.exists(ENVIRONMENT):
		var root := (load(ENVIRONMENT) as PackedScene).instantiate() as Node3D
		for node in root.find_children("rock_*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh != null:
				rocks.append({"xf": _world_transform(mi), "aabb": mi.mesh.get_aabb()})
		root.free()
	print("rocks from the environment scene: %d" % rocks.size())
	var routes := ReturnRoutes.build(WeatherConfig.new(), rocks)
	var blocked := 0
	for w in routes.weight:
		if w <= 0.0:
			blocked += 1
	var err := routes.save()
	print("grid %d x %d cells of %.1f m, blocked %d, reachable %d, entrances %s, saved: %s (%d ms)" % [routes.width, routes.depth, routes.cell,
		blocked, routes.reachable_cells(), routes.entrance_cells, error_string(err), Time.get_ticks_msec() - t0])
	var check := ReturnRoutes.load_baked()
	print("reload: %s" % ("ok" if check != null and check.width == routes.width else "FAILED"))
	for p: Vector3 in [Vector3(54.5, 0, 0.0), Vector3(-25.5, 0, -7.0), Vector3(-20.0, 0, 40.0), Vector3(0.0, 0, 60.0)]:
		print("  %s: field %.1f m, A* %.1f m" % [p, routes.return_metres(p), routes.astar_metres(p)])
	quit(0 if err == OK else 1)


static func _world_transform(node: Node3D) -> Transform3D:
	var pose := node.transform
	var parent := node.get_parent_node_3d()
	while parent != null:
		pose = parent.transform * pose
		parent = parent.get_parent_node_3d()
	return pose
