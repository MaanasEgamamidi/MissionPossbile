extends SceneTree
## One-off probe (drone worker): loads the real game with the map and lists open, flat spots for the drone pad near the
## scout bay (no WORLD/DOOR/ITEM collision in a 3.2 x 2.5 x 3.2 m box, flat terrain). Not a test.
## Run: godot --headless --path . --script res://tools/blender/drone/probe_pad_spot.gd

func _initialize() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() if ResourceLoader.exists("res://scenes/game.tscn") else null
	if game == null:
		game = GameMain.new()
	game.set("show_menu", false)
	game.set("check_weather_updates", false)
	game.set("save_directory", ProjectSettings.globalize_path("res://").path_join("_test_saves/drone/probe"))
	root.add_child(game)
	for i in 30:
		await physics_frame
	var space := (game as Node3D).get_world_3d().direct_space_state
	var h := load("res://data/terrain_height.res") as TerrainHeight
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.4, 2.4, 3.4)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collision_mask = Layers.WORLD | Layers.DOOR | Layers.ITEM
	var svc: GameServices = game.get("services")
	var out := PackedStringArray()
	for x in range(12, 34):
		for z in range(13, 33):
			var g := h.height_at(x, z)
			var slope := absf(h.height_at(x + 1.5, z) - h.height_at(x - 1.5, z)) + absf(h.height_at(x, z + 1.5) - h.height_at(x, z - 1.5))
			params.transform = Transform3D(Basis.IDENTITY, Vector3(x, g + 1.45, z))
			var hits := space.intersect_shape(params, 4)
			var names := PackedStringArray()
			for hit in hits:
				names.append(str(hit.collider.name))
			var zone := svc.zones.zone_at_world(Vector3(x, g, z)) if svc != null and svc.zones != null else "?"
			if hits.is_empty() and slope < 0.35 and zone == ColonyZones.EXTERIOR:
				out.append("%d,%d g=%.2f s=%.2f" % [x, z, g, slope])
	print("CLEAR ", " | ".join(out))
	quit(0)
