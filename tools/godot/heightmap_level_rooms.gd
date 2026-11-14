extends SceneTree
## Levels the sampled terrain under and right around the buildings.
## The terrain mesh is cut away under the base (about 0.5 m down). Sampled on a 1 m grid, that pit bleeds out past the
## walls and leaves a step in front of every outside door that is taller than a person can climb. Under a floor the
## terrain is never walked on, so every sample inside a room rectangle grown by `--margin` metres is raised to
## `--level` (the height of the ground just outside), never lowered.
## Run: godot --headless --path . --script res://tools/godot/heightmap_level_rooms.gd -- [--in res://data/terrain_height.res] [--level -0.05] [--margin 2.0]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "res://data/terrain_height.res"
	var level := -0.05
	var margin := 2.0
	for i in args.size():
		match args[i]:
			"--in": path = args[i + 1]
			"--level": level = float(args[i + 1])
			"--margin": margin = float(args[i + 1])
	var height := load(path) as TerrainHeight
	if height == null:
		push_error("No height grid at " + path)
		quit(1)
		return
	var zones := ColonyZones.from_manifest("res://data/colony_manifest.json")
	var raised := 0
	var biggest := 0.0
	for r: Dictionary in zones.rooms:
		# room rectangles are in Blender x, y; world z = -y
		var x0 := float(r.x0) - margin
		var x1 := float(r.x1) + margin
		var z0 := -float(r.y1) - margin
		var z1 := -float(r.y0) + margin
		var ix0 := maxi(0, int(floor((x0 - height.origin.x) / height.cell)))
		var ix1 := mini(height.width - 1, int(ceil((x1 - height.origin.x) / height.cell)))
		var iz0 := maxi(0, int(floor((z0 - height.origin.y) / height.cell)))
		var iz1 := mini(height.depth - 1, int(ceil((z1 - height.origin.y) / height.cell)))
		for iz in range(iz0, iz1 + 1):
			for ix in range(ix0, ix1 + 1):
				var i := iz * height.width + ix
				if height.heights[i] < level:
					biggest = maxf(biggest, level - height.heights[i])
					height.heights[i] = level
					raised += 1
	var err := ResourceSaver.save(height, path)
	print("LEVELLED %d samples to %.3f m (largest lift %.3f m), margin %.1f m, saved %s: %s" % [raised, level, biggest, margin, path, error_string(err)])
	quit(0 if err == OK else 1)
