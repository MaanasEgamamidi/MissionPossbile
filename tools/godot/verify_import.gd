extends SceneTree
## Compares the imported world with the source manifest: object counts, names, world transforms, triangles,
## mesh sharing, door and station identifiers, terrain vertex colours, glass transparency, lights and cameras.
##   godot --headless --path . --script res://tools/godot/verify_import.gd -- --out <file.json>

const MANIFEST := "res://data/colony_manifest.json"
const WORLD := "res://scenes/world/colony_world.tscn"

var C := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame          # the tree must be running before global transforms can be read
	var out := "res://data/verify_import.json"
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	var rep := _verify()
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(rep, " "))
	f.close()
	print("verify_import: ok=", rep.ok, " objects ", rep.colony.matched, "/", rep.colony.expected, " max_pos_err_m=", rep.colony.max_position_error_m,
		" max_basis_err=", rep.colony.max_basis_error, " tris=", rep.colony.triangles_godot, "/", rep.colony.triangles_manifest)
	quit(0 if rep.ok else 1)


func _key(s: String) -> String:
	return s.replace(".", "_").replace(" ", "_")


func _tris(mesh: Mesh) -> int:
	var n := 0
	for i in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(i)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			n += (idx as PackedInt32Array).size() / 3
		else:
			n += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _collect(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)


func _verify() -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var world: Node3D = (load(WORLD) as PackedScene).instantiate()
	root.add_child(world)
	var rep := {"ok": false, "source_sha256": manifest.source.sha256}

	# ---- colony objects
	var meshes: Array = []
	_collect(world.get_node("Colony"), meshes)
	var by_name := {}
	for m in meshes:
		by_name[_key(String(m.name))] = m
	var matched := 0
	var missing: Array = []
	var max_pos := 0.0
	var max_basis := 0.0
	var worst := ""
	var tri_cache := {}
	var tris_g := 0
	var tris_m := 0
	var unique_meshes := {}
	var area_ok := {}
	var door_ids := {}
	var door_leaves := 0
	var inter: Array = []
	var meta_mismatch := 0
	var parent_mismatch := 0
	for o in manifest.objects:
		var k := _key(String(o.name))
		tris_m += int(o.tris)
		if not by_name.has(k):
			missing.append(o.name)
			continue
		matched += 1
		var mi: MeshInstance3D = by_name[k]
		var m: Array = o.matrix_world
		var bb := Basis(Vector3(m[0][0], m[1][0], m[2][0]), Vector3(m[0][1], m[1][1], m[2][1]), Vector3(m[0][2], m[1][2], m[2][2]))
		var expect := Transform3D(C * bb * C.inverse(), C * Vector3(m[0][3], m[1][3], m[2][3]))
		var got := mi.global_transform
		var pe := got.origin.distance_to(expect.origin)
		var be := maxf((got.basis.x - expect.basis.x).length(), maxf((got.basis.y - expect.basis.y).length(), (got.basis.z - expect.basis.z).length()))
		if pe > max_pos or be > max_basis:
			worst = String(o.name)
		max_pos = maxf(max_pos, pe)
		max_basis = maxf(max_basis, be)
		if not tri_cache.has(mi.mesh):
			tri_cache[mi.mesh] = _tris(mi.mesh)
		tris_g += int(tri_cache[mi.mesh])
		unique_meshes[mi.mesh] = true
		if String(mi.get_meta("gc_asset", "")) != String(o.gc_asset):
			meta_mismatch += 1
		if _key(String(mi.get_parent().name)) != _key(String(o.area)):
			parent_mismatch += 1
		area_ok[o.area] = int(area_ok.get(o.area, 0)) + 1
		if o.has("door_id"):
			if int(mi.get_meta("door_id", -1)) == int(o.door_id) and absf(float(mi.get_meta("door_slide", 0.0)) - float(o.door_slide)) < 1e-4:
				door_ids[int(o.door_id)] = true
				door_leaves += 1
		if o.has("inter") and String(mi.get_meta("inter", "")) == String(o.inter):
			inter.append(o.inter)
	inter.sort()
	var floors := 0
	for mi in meshes:
		if String(mi.get_meta("cls", "")) == "floor":
			floors += 1
	rep.colony = {"expected": manifest.objects.size(), "mesh_nodes": meshes.size(), "matched": matched, "missing": missing.slice(0, 20),
		"max_position_error_m": snappedf(max_pos, 0.000001), "max_basis_error": snappedf(max_basis, 0.000001), "worst": worst,
		"triangles_godot": tris_g, "triangles_manifest": tris_m, "unique_mesh_resources": unique_meshes.size(),
		"gc_asset_meta_mismatch": meta_mismatch, "area_parent_mismatch": parent_mismatch, "by_area": area_ok,
		"doors": door_ids.size(), "door_leaves": door_leaves, "interactables": inter, "floor_class_nodes": floors}

	# ---- environment
	var env: Array = []
	_collect(world.get_node("Environment"), env)
	if world.has_node("Terrain"):
		_collect(world.get_node("Terrain"), env)
	var env_by := {}
	for m in env:
		env_by[_key(String(m.name))] = m
	var env_matched := 0
	var env_max_pos := 0.0
	var env_tris := 0
	var env_tris_m := 0
	var env_unique := {}
	var terrain_with_color := 0
	var terrain_tiles := 0
	var white_terrain: Array = []
	for o in manifest.environment_objects:
		env_tris_m += int(o.tris)
		var k := _key(String(o.name))
		if not env_by.has(k):
			continue
		env_matched += 1
		var mi: MeshInstance3D = env_by[k]
		var m: Array = o.matrix_world
		env_max_pos = maxf(env_max_pos, mi.global_transform.origin.distance_to(C * Vector3(m[0][3], m[1][3], m[2][3])))
		if not tri_cache.has(mi.mesh):
			tri_cache[mi.mesh] = _tris(mi.mesh)
		env_tris += int(tri_cache[mi.mesh])
		env_unique[mi.mesh] = true
		if String(o.name).begins_with("Terrain_"):
			terrain_tiles += 1
			var arr := mi.mesh.surface_get_arrays(0)
			var col: Variant = arr[Mesh.ARRAY_COLOR]
			var tmat := mi.mesh.surface_get_material(0) as ShaderMaterial
			var is_terrain_shader := tmat != null and tmat.shader != null and tmat.shader.resource_path.ends_with("colony_terrain.gdshader")
			if not is_terrain_shader:
				# a terrain mesh with no colour attribute: acceptable only if its flat material is not white
				var acv: Variant = tmat.get_shader_parameter("albedo") if tmat != null else null
				if acv == null or ((acv as Color).r > 0.95 and (acv as Color).g > 0.95 and (acv as Color).b > 0.95):
					white_terrain.append(o.name)
			elif col != null and (col as PackedColorArray).size() > 0:
				var ca := col as PackedColorArray
				var mean := Vector3.ZERO
				var step := maxi(1, ca.size() / 2000)
				var n := 0
				for i in range(0, ca.size(), step):
					mean += Vector3(ca[i].r, ca[i].g, ca[i].b)
					n += 1
				mean /= float(n)
				terrain_with_color += 1
				if mean.x > 0.95 and mean.y > 0.95 and mean.z > 0.95:
					white_terrain.append(o.name)
			else:
				white_terrain.append(o.name)
	rep.environment = {"expected": manifest.environment_objects.size(), "mesh_nodes": env.size(), "matched": env_matched,
		"max_position_error_m": snappedf(env_max_pos, 0.000001), "triangles_godot": env_tris, "triangles_manifest": env_tris_m,
		"unique_mesh_resources": env_unique.size(), "terrain_tiles": terrain_tiles, "terrain_tiles_with_vertex_colour": terrain_with_color,
		"terrain_tiles_white_or_uncoloured": white_terrain}

	# ---- materials: transparency of glass roles
	var glass := {}
	var mats := {}
	for mi: MeshInstance3D in meshes + env:
		for i in mi.mesh.get_surface_count():
			var mat: Material = mi.mesh.surface_get_material(i)
			if mat != null:
				mats[mat.resource_name] = mat.resource_path
			var gsm := mat as ShaderMaterial
			if gsm != null and gsm.shader != null and gsm.shader.resource_path.ends_with("colony_glass.gdshader"):
				glass[String(mat.resource_name)] = {"shader": "colony_glass", "opacity": snappedf(float(gsm.get_shader_parameter("opacity")), 0.001)}
	var embedded := 0
	for n in mats:
		if not String(mats[n]).begins_with("res://materials/"):
			embedded += 1
	rep.materials = {"used": mats.size(), "not_external": embedded, "glass": glass}

	# ---- lights and cameras
	var want_lights := 0
	for l in manifest.lights:
		if bool(l.in_blender_render):
			want_lights += 1
	var fixtures := get_nodes_in_group("fixture_lights").size()
	var suns := get_nodes_in_group("sun").size()
	var cams := world.get_node("ReferenceCameras").get_child_count()
	var cam_err := 0.0
	for c in manifest.cameras:
		var cn := world.get_node("ReferenceCameras").get_node_or_null(String(c.name))
		if cn:
			var m: Array = c.matrix_world
			cam_err = maxf(cam_err, (cn as Node3D).global_transform.origin.distance_to(C * Vector3(m[0][3], m[1][3], m[2][3])))
	rep.lights = {"in_blender_render": want_lights, "godot_fixture_lights": fixtures, "godot_suns": suns,
		"source_lights_total": manifest.lights.size(), "not_carried": manifest.lights.size() - want_lights}
	rep.cameras = {"expected": manifest.cameras.size(), "godot": cams, "max_position_error_m": snappedf(cam_err, 0.000001)}
	rep.ok = (matched == manifest.objects.size() and max_pos < 0.002 and max_basis < 0.002 and absf(float(tris_g - tris_m)) <= float(tris_m) * 0.0001 and meta_mismatch == 0
		and env_matched == manifest.environment_objects.size() and white_terrain.is_empty() and embedded == 0
		and fixtures + suns == want_lights and cams == manifest.cameras.size())
	return rep
