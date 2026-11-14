@tool
extends EditorScenePostImport
## Runs when colony.glb / environment.glb are imported.
##  - replaces each embedded material by the external one in res://materials/colony/<name>.tres (if it exists);
##  - gives every mesh the render layers of the zones it stands in, so unshadowed fixture lights can be limited to
##    their own room with Light3D.light_cull_mask (see ColonyZones);
##  - copies the Blender custom properties (glTF extras) to node metadata.
## It changes nothing else: transforms, names and mesh sharing stay as exported.

const Zones := preload("res://scripts/world/colony_zones.gd")
const MATERIAL_DIR := "res://materials/colony/"

var _zones: Zones
var _report := {"meshes": 0, "surfaces": 0, "external": 0, "embedded_kept": {}, "layers": {}}
var _mat_cache := {}
var _done_meshes := {}


func _post_import(scene: Node) -> Object:
	_zones = Zones.from_manifest("res://data/colony_manifest.json")
	var fname := get_source_file().get_file()
	var is_env := fname.begins_with("environment") or fname.begins_with("terrain")
	_walk(scene, Transform3D.IDENTITY, is_env)
	var path := "res://data/import_report_%s.json" % get_source_file().get_file().get_basename()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_report, " "))
	return scene


func _walk(node: Node, parent_xf: Transform3D, is_env: bool) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	if node.has_meta("extras"):
		var ex: Variant = node.get_meta("extras")
		if ex is Dictionary:
			for k in ex:
				node.set_meta(String(k), ex[k])
	if node is MeshInstance3D:
		_fix_mesh(node as MeshInstance3D, xf, is_env)
	for c in node.get_children():
		_walk(c, xf, is_env)


func _fix_mesh(mi: MeshInstance3D, xf: Transform3D, is_env: bool) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	_report.meshes += 1
	if not _done_meshes.has(mesh):
		_done_meshes[mesh] = true
		for i in mesh.get_surface_count():
			_report.surfaces += 1
			var m := mesh.surface_get_material(i)
			if m == null:
				continue
			var mname := m.resource_name
			var ext := _external(mname)
			if ext:
				mesh.surface_set_material(i, ext)
				_report.external += 1
			else:
				_report.embedded_kept[mname] = int(_report.embedded_kept.get(mname, 0)) + 1
	var mask := 0
	if is_env:
		mask = _zones.outdoor_mask()
		# Blender-only pieces that stand at room height inside the base (the airlock tunnel and its inner door) are
		# seen from the rooms as well; terrain tiles and the hall frame are not, and stay outdoor-only.
		var box: AABB = xf * mesh.get_aabb()
		if box.size.x < 12.0 and box.size.z < 12.0 and box.end.y < 6.0 and box.position.y > -1.0:
			mask |= _zones.mask_for_aabb(box)
	else:
		mask = _zones.mask_for_aabb(xf * mesh.get_aabb(), String(mi.get_meta("area", "")))
	# Sun shadows only need roofs, outer walls and outdoor objects. Everything indoors sits under a roof slab, so it is
	# left out of the directional shadow passes (Light3D.shadow_caster_mask), which would otherwise redraw every room.
	var area := String(mi.get_meta("area", ""))
	if is_env or area in ["Roofs", "Exterior", "Dome plaza", "Garden Dome"] or (mask & _zones.outdoor_mask()) != 0:
		mask |= _zones.sun_bit()
	mi.layers = mask
	# Small props stop being drawn once they are a few pixels tall; rooms are at most 24 m long, so 30 m is never
	# reached inside the room the prop stands in.
	var longest: float = (xf * mesh.get_aabb()).get_longest_axis_size()
	if is_env:
		if String(mi.name).begins_with("rock_"):
			mi.visibility_range_end = maxf(90.0, longest * 140.0)
			mi.visibility_range_end_margin = 10.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	elif longest < 3.0:
		mi.visibility_range_end = maxf(30.0, longest * 45.0)
		mi.visibility_range_end_margin = 4.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if mi.has_meta("dust"):
		# drives the dust layer of colony_surface.gdshader for this object (source: the object's 'dust' property)
		mi.set_instance_shader_parameter("dust", float(mi.get_meta("dust")))
		_report.dusted = int(_report.get("dusted", 0)) + 1
	var key := str(mask)
	_report.layers[key] = int(_report.layers.get(key, 0)) + 1


func _external(mname: String) -> Material:
	if _mat_cache.has(mname):
		return _mat_cache[mname]
	var p := MATERIAL_DIR + mname + ".tres"
	var m: Material = null
	if ResourceLoader.exists(p):
		m = load(p)
	_mat_cache[mname] = m
	return m
