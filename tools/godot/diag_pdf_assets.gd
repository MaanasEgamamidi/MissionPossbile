extends SceneTree
## Geometry/material evidence for the scoped PDF corrections, without modifying source assets.
func _initialize() -> void:
	await process_frame
	var scene := (load("res://assets/colony/colony.glb") as PackedScene).instantiate()
	root.add_child(scene)
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var asset := String(mi.get_meta("gc_asset", String(mi.name)))
		if asset not in ["hgw_ladder", "rk_chess", "co_planter", "sc_floor", "sc_e_panel", "co_chair", "rk_hood", "al_suit_rack"]:
			continue
		if String(mi.name).contains("_") and String(mi.name).contains("001"):
			continue
		print("ASSET ", mi.name, " ", asset, " transform=", mi.global_transform, " bounds=", mi.mesh.get_aabb())
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var box := AABB(verts[0], Vector3.ZERO)
			for v in verts:
				box = box.expand(v)
			print("  SURFACE ", s, " ", mi.mesh.surface_get_material(s).resource_name, " ", box)
	scene.free()
	quit()
