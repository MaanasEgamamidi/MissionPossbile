extends SceneTree
## Diagnostic: where is the ground? Prints, for the hub and every room centre, the zone, the terrain height from the
## sampled grid, and what a downward ray hits in the built collision. Read-only.
## Run: godot --headless --path . --script res://tools/godot/diag_ground.gd


func _initialize() -> void:
	var zones := ColonyZones.from_manifest("res://data/colony_manifest.json")
	var collision := WorldCollision.build("res://data/colony_manifest.json", "res://data/colliders.json")
	root.add_child(collision)
	var height := load("res://data/terrain_height.res") as TerrainHeight
	var terrain_body: StaticBody3D = null
	if height != null:
		terrain_body = height.make_body()
		collision.add_child(terrain_body)
		print("terrain grid %dx%d cell %.2f origin %s" % [height.width, height.depth, height.cell, height.origin])
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	var config := GameConfig.new()
	var points := {"HUB": config.hub_position}
	for r: Dictionary in zones.rooms:
		points[String(r.name)] = Vector3((float(r.x0) + float(r.x1)) * 0.5, 0.0, -(float(r.y0) + float(r.y1)) * 0.5)
	points["Landing pad"] = Vector3(-27.0, 0.0, 33.0)
	points["Garden dome"] = Vector3(50.0, 0.0, 27.0)
	points["Plaza"] = Vector3(15.0, 0.0, 14.0)
	var worst_room_terrain := -INF
	for name: String in points:
		var p: Vector3 = points[name]
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 3.0, 0), p + Vector3(0, -30.0, 0), Layers.WORLD)
		var hit := space.intersect_ray(q)
		var th := height.height_at(p.x, p.z) if height != null else NAN
		var what := "nothing"
		if not hit.is_empty():
			var col := hit.collider as Node
			what = "%s y=%.3f" % ["TERRAIN" if col == terrain_body else String(col.name), float(hit.position.y)]
		print("%-20s zone=%-18s terrain=%.3f  ray-> %s" % [name, zones.zone_at_world(p), th, what])
	# highest terrain sample inside any room rectangle (should be below the floors at y = 0)
	if height != null:
		for r: Dictionary in zones.rooms:
			var top := -INF
			var x := float(r.x0) + 0.5
			while x < float(r.x1):
				var y := float(r.y0) + 0.5
				while y < float(r.y1):
					top = maxf(top, height.height_at(x, -y))
					y += 1.0
				x += 1.0
			worst_room_terrain = maxf(worst_room_terrain, top)
			if top > -0.02:
				print("  terrain reaches %.3f inside %s" % [top, r.name])
		print("highest terrain inside any room: %.3f" % worst_room_terrain)
	print(WorldCollision.stats(collision))
	quit(0)
