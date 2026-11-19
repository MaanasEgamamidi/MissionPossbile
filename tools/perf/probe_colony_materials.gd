extends SceneTree
## Which materials the colony map's surfaces use, and how many mesh instances have only "plain" ones (headless).
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/perf/probe_colony_materials.gd

func _initialize() -> void:
	var world: Node3D = (load("res://scenes/world/colony_world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	var by_kind := {}
	var all_plain := 0
	var total := 0
	var surf_plain := 0
	var surf_total := 0
	for n: Node in world.get_node("Colony").find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		total += 1
		var plain := mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mi.mesh.get_surface_count():
			surf_total += 1
			var m := mi.get_active_material(i)
			var kind := "null"
			if m is ShaderMaterial:
				kind = String((m as ShaderMaterial).shader.resource_path.get_file()) if (m as ShaderMaterial).shader != null else "shader:null"
			elif m is BaseMaterial3D:
				var bm := m as BaseMaterial3D
				kind = "Standard transp=%d" % bm.transparency
			by_kind[kind] = int(by_kind.get(kind, 0)) + 1
			if kind != "colony_surface.gdshader":
				plain = false
		if plain:
			all_plain += 1
			surf_plain += mi.mesh.get_surface_count()
	print("COLONY instances %d, all-plain %d (surfaces %d of %d)" % [total, all_plain, surf_plain, surf_total])
	for k: String in by_kind:
		print("MATERIAL %-40s surfaces %d" % [k, by_kind[k]])
	quit(0)
