extends SceneTree
## Perf overhaul Phase 5: builds the two far-distance proxies of the colony exterior (headless, no Blender needed).
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/perf/build_colony_lod.gd [-- --dry-run]
##
## Source: every colony mesh on render layer 20 ("can shadow the sun": roofs, outer walls, outdoor objects), i.e. the
## exterior shell; interior-only meshes are left out (they are COLD from outside anyway). Glass surfaces are left out
## (an opaque proxy of glass would be wrong; the hall's dome glass is environment scenery and is not tiered).
## All of it is merged into one mesh around the colony centre with the surface colour (the colony shader's `albedo`)
## written as a vertex colour, then simplified with Godot's own meshoptimizer LOD generator:
##   res://lod/colony_t1.res  about 25 % of the triangles, one vertex-colour material, casts shadows
##   res://lod/colony_t2.res  about 5 %, one unshaded vertex-colour material, no shadows
##   res://lod/colony_lod.json  centre, radius and triangle counts (read by perf/colony_lod.gd)

const OUT_DIR := "res://lod"
const TIERS := {"t1": 0.25, "t2": 0.05}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var dry := OS.get_cmdline_user_args().has("--dry-run")
	var world: Node3D = (load("res://scenes/world/colony_world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var colony := world.get_node("Colony") as Node3D
	var sun_bit := 1 << (ColonyZones.SUN_LAYER - 1)
	var sources: Array[MeshInstance3D] = []
	var box := AABB()
	for n in colony.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not (mi.layers & sun_bit) or not mi.is_visible_in_tree():
			continue
		sources.append(mi)
		var b := mi.global_transform * mi.mesh.get_aabb()
		box = b if box.size == Vector3.ZERO else box.merge(b)
	var centre := box.get_center()
	centre.y = box.position.y
	var radius := Vector2(box.size.x, box.size.z).length() * 0.5
	print("SOURCES %d meshes, box %s, centre %s, radius %.1f m" % [sources.size(), box, centre, radius])

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := 0
	var skipped_glass := 0
	for mi in sources:
		var xf := Transform3D(Basis.IDENTITY, -centre) * mi.global_transform
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat := mi.get_active_material(s)
			if ZoneManager._mesh_has_glass_material(mat):
				skipped_glass += 1
				continue
			var col := _albedo(mat)
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				idx.resize(verts.size())
				for i in verts.size():
					idx[i] = i
			for i in idx.size():
				var v := idx[i]
				st.set_color(col)
				if not norms.is_empty():
					st.set_normal((xf.basis * norms[v]).normalized())
				st.add_vertex(xf * verts[v])
			tris += idx.size() / 3
	print("MERGED %d triangles (%d glass surfaces left out)" % [tris, skipped_glass])
	st.index()
	var merged := st.commit_to_arrays()

	var info := {"centre": [centre.x, centre.y, centre.z], "radius": radius, "source_meshes": sources.size(), "source_triangles": tris, "tiers": {}}
	# Tier 1: the LOD level of the merged shell closest to TIERS.t1. Tier 2: the same simplifier run again on tier 1,
	# closest to TIERS.t2 of the source (meshoptimizer stops early on this dense map, so record what it really gave).
	var t1_arrays := _simplified(merged, float(TIERS.t1))
	var t1_tris := (t1_arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	var t2_ratio_of_t1 := clampf(float(TIERS.t2) * tris / maxf(t1_tris, 1.0), 0.05, 0.5)
	var t2_arrays := _simplified(t1_arrays, t2_ratio_of_t1)
	for tier: String in ["t1", "t2"]:
		var arrays: Array = t1_arrays if tier == "t1" else t2_arrays
		var out := ArrayMesh.new()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(0, _material(tier == "t2"))
		var t := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		info.tiers[tier] = {"triangles": t, "ratio": float(t) / maxf(tris, 1.0)}
		print("TIER %s: %d triangles (%.2f %% of %d)" % [tier, t, 100.0 * t / maxf(tris, 1.0), tris])
		if not dry:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
			var err := ResourceSaver.save(out, "%s/colony_%s.res" % [OUT_DIR, tier], ResourceSaver.FLAG_COMPRESS)
			print("  saved colony_%s.res: %s" % [tier, error_string(err)])
	if not dry:
		var f := FileAccess.open(OUT_DIR + "/colony_lod.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(info, "  "))
		f.close()
	print("INFO ", JSON.stringify(info))
	quit(0)


## Simplifies `arrays` with ImporterMesh.generate_lods and returns the level whose index count is closest to `ratio`,
## with only the vertices that level still uses.
func _simplified(arrays: Array, ratio: float) -> Array:
	var mesh := ImporterMesh.new()
	mesh.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.generate_lods(25.0, 60.0, [])
	var base: int = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	var want := int(base * ratio)
	var best: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for l in mesh.get_surface_lod_count(0):
		var idx := mesh.get_surface_lod_indices(0, l)
		print("  lod %d: %d indices (%.1f %%)" % [l, idx.size(), 100.0 * idx.size() / maxf(base, 1.0)])
		if absi(idx.size() - want) < absi(best.size() - want):
			best = idx
	# compact: keep only the vertices this level uses
	var remap := {}
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nc := PackedColorArray()
	var ni := PackedInt32Array()
	ni.resize(best.size())
	for i in best.size():
		var v := best[i]
		if not remap.has(v):
			remap[v] = nv.size()
			nv.append(verts[v])
			if not norms.is_empty():
				nn.append(norms[v])
			if not cols.is_empty():
				nc.append(cols[v])
		ni[i] = remap[v]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = nv
	if not nn.is_empty():
		out[Mesh.ARRAY_NORMAL] = nn
	if not nc.is_empty():
		out[Mesh.ARRAY_COLOR] = nc
	out[Mesh.ARRAY_INDEX] = ni
	return out


func _albedo(mat: Material) -> Color:
	var sm := mat as ShaderMaterial
	if sm != null:
		var a: Variant = sm.get_shader_parameter("albedo")
		if a is Color:
			return a
		if a is Vector3:
			return Color((a as Vector3).x, (a as Vector3).y, (a as Vector3).z)
	var bm := mat as BaseMaterial3D
	if bm != null:
		return bm.albedo_color
	return Color(0.7, 0.7, 0.7)


func _material(unshaded: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.85
	m.metallic = 0.0
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	return m
