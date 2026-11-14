extends SceneTree
## Perf overhaul inventory helper (headless): what sits under the Environment and Terrain scenes.
func _initialize() -> void:
	var world: Node3D = (load("res://scenes/world/colony_world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for top in ["Environment", "Terrain", "ScoutWorld", "Colony"]:
		var sc := world.get_node(top)
		for g in sc.get_child(0).get_children() if sc.get_child_count() > 0 and top != "ScoutWorld" else sc.get_children():
			var names := []
			var tris := 0
			for mi in g.find_children("*", "MeshInstance3D", true, false):
				var m := (mi as MeshInstance3D).mesh
				for s in m.get_surface_count():
					var a := m.surface_get_arrays(s)
					tris += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null else a[Mesh.ARRAY_VERTEX].size()) / 3
				if names.size() < 8:
					names.append("%s[L%d]" % [mi.name, (mi as VisualInstance3D).layers])
			print("%s/%s meshes=%d tris=%d e.g. %s" % [top, g.name, g.find_children("*", "MeshInstance3D", true, false).size(), tris, names])
	quit(0)
