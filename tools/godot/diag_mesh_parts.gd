extends SceneTree
## Per-surface bounds of one world mesh, plus a histogram of triangle centres along an axis inside a box.
## Run: godot --headless --path . --script res://tools/godot/diag_mesh_parts.gd -- <node path>

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var world := (load("res://scenes/world/colony_world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	await process_frame
	var mi := world.get_node(a[0]) as MeshInstance3D
	var xf := mi.global_transform
	print("XF %s" % xf)
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var box := AABB(xf * v[0], Vector3.ZERO)
		for p in v:
			box = box.expand(xf * p)
		var mat := mi.mesh.surface_get_material(s)
		# z histogram of vertices in the door zone
		var hist := {}
		for p in v:
			var w := xf * p
			if w.y > 0.1 and w.y < 2.4 and absf(w.x - 22.0) < 2.2:
				var k := snappedf(w.z, 0.05)
				hist[k] = int(hist.get(k, 0)) + 1
		var keys := hist.keys()
		keys.sort()
		var hs := PackedStringArray()
		for k in keys:
			hs.append("%s:%d" % [k, hist[k]])
		print("SURF %d %s verts=%d box=%s..%s  z:%s" % [s, mat.resource_name if mat else "-", v.size(), box.position, box.end, " ".join(hs)])
	quit(0)
