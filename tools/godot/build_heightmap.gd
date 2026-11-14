class_name BuildHeightmap
extends SceneTree
## Headless terrain sampler; accepts --scene, --cell, --out and optional --bounds.

func _initialize() -> void:
	var options: Dictionary = {}
	var args := OS.get_cmdline_user_args()
	for index: int in range(0, args.size(), 2):
		if index + 1 >= args.size():
			_fail("Expected a value for " + args[index])
			return
		options[args[index]] = args[index + 1]
	var spacing := float(options.get("--cell", "1.0"))
	if not options.has("--scene") or not options.has("--out") or spacing <= 0.0:
		_fail("Usage: --scene <scene> --cell <metres> --out <resource> [--bounds x0,z0,x1,z1]")
		return
	var scene := load(String(options["--scene"])) as PackedScene
	if scene == null:
		_fail("Cannot load terrain scene")
		return
	var terrain := scene.instantiate() as Node3D
	if terrain == null:
		_fail("Scene root must be Node3D")
		return
	root.add_child.call_deferred(terrain)
	await process_frame
	var bounds: Rect2
	if options.has("--bounds"):
		var parts := String(options["--bounds"]).split(",")
		if parts.size() != 4:
			_fail("Bounds need four comma-separated numbers")
			return
		bounds = Rect2(Vector2(float(parts[0]), float(parts[1])), Vector2(float(parts[2]) - float(parts[0]), float(parts[3]) - float(parts[1])))
	else:
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		var nodes: Array[Node] = [terrain]
		nodes.append_array(terrain.find_children("*", "MeshInstance3D", true, false))
		for node: Node in nodes:
			var mesh := node as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				continue
			for surface: int in range(mesh.mesh.get_surface_count()):
				var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for vertex: Vector3 in vertices:
					var point := mesh.global_transform * vertex
					low = low.min(Vector2(point.x, point.z))
					high = high.max(Vector2(point.x, point.z))
		bounds = Rect2(low, high - low)
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x <= 0 or bounds.size.y <= 0:
		_fail("Terrain bounds must have positive finite area")
		return
	var grid := TerrainHeight.from_meshes(terrain, spacing, bounds)
	var error := ResourceSaver.save(grid, String(options["--out"]))
	if error != OK:
		_fail("Cannot save heightmap: " + error_string(error))
		return
	print("HEIGHTMAP %dx%d -> %s" % [grid.width, grid.depth, options["--out"]])
	quit(0)

func _fail(message: String) -> void:
	printerr(message)
	quit(1)
