extends SceneTree
## Writes every mesh of the food and garden upgrade stages (V1..V4) as plain JSON, so render_stages.py can rebuild them
## in Blender over the real map and render check images (headless Godot cannot render). The meshes are built by the
## same presenter scripts the game uses, with no game running (station positions fall back to the data file values).
## Run: godot --headless --path . --script res://tools/blender/food_stages/dump_stages.gd
## Output: res://assets_src/food_stages/stages_dump.json (assets_src has a .gdignore).

const FOOD := preload("res://scripts/upgrades/stages/food_stages.gd")
const GARDEN := preload("res://scripts/upgrades/stages/garden_stages.gd")
const OUT := "res://assets_src/food_stages/stages_dump.json"


func _initialize() -> void:
	var out := {"note": "Godot world coordinates (y up). Each part: mesh kind and size, world transforms (basis columns x, y, z then origin), colour, glow.", "levels": {}}
	for level in range(1, 5):
		var parts: Array = []
		for script: Script in [FOOD, GARDEN]:
			var p: AreaStagePresenter = script.new()
			var holder := Node3D.new()
			get_root().add_child(holder)
			var stage := p.build_stage(level)
			if stage != null:
				holder.add_child(stage)
				_collect(stage, p.track_id(), parts)
			holder.free()
			p.free()
		out.levels[str(level)] = parts
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("DUMP OK ", ProjectSettings.globalize_path(OUT))
	quit(0)


func _collect(n: Node, track: String, parts: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		parts.append(_part(track, String(mi.name), mi.mesh, mi.material_override, [_world(mi)], []))
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		# placements from the copy the presenters keep (a headless renderer does not keep MultiMesh data)
		var mmi := n as MultiMeshInstance3D
		var xs: Array[Transform3D] = []
		for t: Transform3D in mmi.get_meta("xforms", []):
			xs.append(_world(mmi) * t)
		var cs: Array = mmi.get_meta("colours", [])
		parts.append(_part(track, String(mmi.name), mmi.multimesh.mesh, mmi.material_override, xs, cs))
	for c in n.get_children():
		_collect(c, track, parts)


## World transform from the local ones (the holder sits at the origin; works outside the tree too).
static func _world(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _part(track: String, part_name: String, mesh: Mesh, material: Material, xs: Array[Transform3D], colours: Array) -> Dictionary:
	var d := {"track": track, "name": part_name}
	if mesh is BoxMesh:
		var s := (mesh as BoxMesh).size
		d["kind"] = "box"
		d["size"] = [s.x, s.y, s.z]
	elif mesh is CylinderMesh:
		var c := mesh as CylinderMesh
		d["kind"] = "cylinder"
		d["size"] = [c.bottom_radius, c.height, c.top_radius]
	elif mesh is SphereMesh:
		var sp := mesh as SphereMesh
		d["kind"] = "sphere"
		d["size"] = [sp.radius, sp.height, sp.radius]
	else:
		d["kind"] = "other"
		d["size"] = [1, 1, 1]
	var colour := Color.WHITE
	var glow := 0.0
	if material is StandardMaterial3D:
		var m := material as StandardMaterial3D
		colour = m.albedo_color
		if m.emission_enabled:
			glow = m.emission_energy_multiplier
	d["colour"] = [colour.r, colour.g, colour.b]
	d["glow"] = glow
	var flat: Array = []
	for t: Transform3D in xs:
		flat.append([t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z, t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z])
	d["xforms"] = flat
	if not colours.is_empty():
		d["colours"] = colours.map(func(c: Color) -> Array: return [snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001)])
	return d
