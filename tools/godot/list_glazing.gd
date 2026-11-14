extends SceneTree
## Debug helper: list colony meshes that carry a see-through surface (so wall occluders can leave them alone).
##   godot --headless --path . --script res://tools/godot/list_glazing.gd


func _initialize() -> void:
	_run()


func _walk(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_walk(c, out)


func _run() -> void:
	await process_frame
	var world: Node3D = (load("res://scenes/world/colony_world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var meshes: Array = []
	_walk(world.get_node("Colony"), meshes)
	var by_asset := {}
	for mi: MeshInstance3D in meshes:
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as ShaderMaterial
			if m != null and m.shader != null and m.shader.resource_path.ends_with("colony_glass.gdshader"):
				var a := String(mi.get_meta("gc_asset", mi.name))
				if not by_asset.has(a):
					var box: AABB = mi.global_transform * mi.mesh.get_aabb()
					by_asset[a] = {"n": 0, "area": mi.get_meta("area", "?"), "size": [snappedf(box.size.x, 0.1), snappedf(box.size.y, 0.1), snappedf(box.size.z, 0.1)], "mat": m.resource_name}
				by_asset[a].n += 1
				break
	for a in by_asset:
		print("GLAZED %s x%d area=%s size=%s mat=%s" % [a, by_asset[a].n, by_asset[a].area, str(by_asset[a].size), by_asset[a].mat])
	quit(0)
