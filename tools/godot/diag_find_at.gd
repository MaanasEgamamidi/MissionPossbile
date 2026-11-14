extends SceneTree
## Lists visual meshes whose bounds contain a point. Run: godot --headless --path . --script res://tools/godot/diag_find_at.gd -- x y z [radius]

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var p := Vector3(float(a[0]), float(a[1]), float(a[2]))
	var r := float(a[3]) if a.size() > 3 else 0.3
	var world := (load("res://scenes/world/colony_world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	await process_frame
	for n: Node in world.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var box := mi.global_transform * mi.mesh.get_aabb()
		if box.grow(r).has_point(p) and box.size.length() < 60.0:
			print("HIT %s  centre=%s size=%s" % [world.get_path_to(mi), box.get_center(), box.size])
	quit(0)
