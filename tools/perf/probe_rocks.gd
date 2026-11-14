extends SceneTree
## Perf overhaul helper (headless): visibility settings and mesh sharing of the environment rocks.
func _initialize() -> void:
	var world: Node3D = (load("res://scenes/world/colony_world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	var rocks := world.get_node("Environment").find_children("rock_*", "MeshInstance3D", true, false)
	var meshes := {}
	var with_range := 0
	var with_parent := 0
	for r in rocks:
		var g := r as GeometryInstance3D
		meshes[(r as MeshInstance3D).mesh] = true
		if g.visibility_range_end > 0.0 or g.visibility_range_begin > 0.0:
			with_range += 1
		if String(g.visibility_parent) != "":
			with_parent += 1
	var r0 := rocks[0] as MeshInstance3D
	print("ROCKS n=%d unique_meshes=%d with_range=%d with_parent=%d first: end=%.1f margin=%.1f fade=%d lods=%s aabb=%s" % [rocks.size(), meshes.size(), with_range, with_parent, r0.visibility_range_end, r0.visibility_range_end_margin, r0.visibility_range_fade_mode, str(r0.mesh.get_class()), r0.get_aabb()])
	var ends := {}
	for r in rocks:
		var e := snappedf((r as GeometryInstance3D).visibility_range_end, 10.0)
		ends[e] = int(ends.get(e, 0)) + 1
	print("ROCK END HISTOGRAM ", ends)
	quit(0)
