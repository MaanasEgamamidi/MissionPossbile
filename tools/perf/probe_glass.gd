extends SceneTree
## Perf overhaul inventory helper (headless): names, layers and sizes of glazed colony meshes, to tell windows from door glass.
func _initialize() -> void:
	var world: Node3D = (load("res://scenes/world/colony_world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	var zones := ColonyZones.from_manifest("res://data/colony_manifest.json")
	for top in ["Colony", "Environment"]:
		for mi in world.get_node(top).find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			for i in m3.mesh.get_surface_count():
				var m := m3.mesh.surface_get_material(i) as Material
				var sm := m as ShaderMaterial
				var glass := sm != null and sm.shader != null and sm.shader.resource_path.ends_with("colony_glass.gdshader")
				if glass:
					var box: AABB = m3.global_transform * m3.mesh.get_aabb()
					var zs: Array = []
					for b in 20:
						if m3.layers & (1 << b):
							zs.append(zones.names[b] if b < zones.names.size() else "L%d" % (b + 1))
					print("GLASS %s/%s asset=%s c=(%.1f,%.1f,%.1f) size=(%.1f,%.1f,%.1f) zones=%s" % [top, m3.name, m3.get_meta("gc_asset", "?"), box.get_center().x, box.get_center().y, box.get_center().z, box.size.x, box.size.y, box.size.z, zs])
					break
	quit(0)
