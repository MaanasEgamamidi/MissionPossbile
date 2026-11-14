extends SceneTree
## Debug helper: list colony meshes inside a Blender-space box with their zone layers, dust and material colours.
##   godot --headless --path . --script res://tools/godot/inspect_nodes.gd -- --box x0,y0,x1,y1 [--min-size 1.5]

const Zones := preload("res://scripts/world/colony_zones.gd")


func _initialize() -> void:
	_run()


func _arg(name: String, def: String) -> String:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == name and i + 1 < a.size():
			return a[i + 1]
	return def


func _walk(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_walk(c, out)


func _run() -> void:
	await process_frame
	var b := _arg("--box", "0,0,1,1").split(",")
	var min_size := float(_arg("--min-size", "1.5"))
	var zones := Zones.from_manifest("res://data/colony_manifest.json")
	var world: Node3D = (load("res://scenes/world/colony_world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var meshes: Array = []
	_walk(world.get_node("Colony"), meshes)
	for mi: MeshInstance3D in meshes:
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		var c := box.get_center()
		if c.x < float(b[0]) or c.x > float(b[2]) or -c.z < float(b[1]) or -c.z > float(b[3]) or box.get_longest_axis_size() < min_size:
			continue
		var bits: Array = []
		for i in 20:
			if mi.layers & (1 << i):
				bits.append(zones.names[i] if i < zones.names.size() else str(i + 1))
		var mats: Array = []
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			var col := ""
			if m is ShaderMaterial:
				var sm := m as ShaderMaterial
				var av: Variant = sm.get_shader_parameter("albedo")
				col = "%s m%s r%s c%s w%s g%s" % [(av as Color).to_html(false) if av != null else "-", str(sm.get_shader_parameter("metallic")), str(sm.get_shader_parameter("roughness")),
					str(sm.get_shader_parameter("class_id")), str(sm.get_shader_parameter("wear")), str(sm.get_shader_parameter("grime"))]
			elif m is BaseMaterial3D:
				col = (m as BaseMaterial3D).albedo_color.to_html(true)
			mats.append("%s#%s" % [m.resource_name if m else "null", col])
		print("%s  area=%s  centre=(%.1f, %.1f, z %.1f) size=(%.1f, %.1f, %.1f)  dust=%s  zones=%s  mats=%s" % [mi.name, mi.get_meta("area", "?"), c.x, -c.z, c.y,
			box.size.x, box.size.z, box.size.y, str(mi.get_meta("dust", "-")), str(bits), str(mats)])
	quit(0)
