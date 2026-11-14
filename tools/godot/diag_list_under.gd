extends SceneTree
## Lists every mesh under a node of the world scene with its bounds and surface materials.
## Run: godot --headless --path . --script res://tools/godot/diag_list_under.gd -- <node name>

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var world := (load("res://scenes/world/colony_world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	await process_frame
	var top := world.get_node(a[0]) if "/" in a[0] else world.find_child(a[0], true, false)
	print("ROOT %s children=%d" % [world.get_path_to(top), top.get_child_count()])
	var found := top.find_children("*", "MeshInstance3D", true, false)
	if top is MeshInstance3D:
		found.push_front(top)
	for n: Node in found:
		var mi := n as MeshInstance3D
		var box := mi.global_transform * mi.mesh.get_aabb()
		var mats := PackedStringArray()
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			mats.append(m.resource_name if m != null else "-")
		print("MESH %s c=%s s=%s tris=%d mats=%s" % [top.get_path_to(mi), box.get_center(), box.size, _tris(mi.mesh), ",".join(mats)])
	quit(0)

func _tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		t += (idx.size() if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t


