@tool
extends EditorScenePostImport
## Runs when a broken-part glb (assets/broken_parts/BPnn.glb, tools/blender/broken_parts/export_broken_parts.py) is
## imported. Same treatment as the map's own pieces (tools/godot/colony_post_import.gd), without writing a report:
##  - replaces each embedded material by the external one in res://materials/colony/<name>.tres (if it exists);
##  - gives every mesh the render layers of the zones it stands in (ColonyZones), so room fixture lights reach it;
##    BP08's door pieces are tunnel scenery and are lit like environment.glb's tunnel (outdoor zones + their room);
##  - copies the Blender custom properties (glTF extras) to node metadata and sets the `dust` instance uniform of
##    colony_surface.gdshader from the object's dust value.
## Transforms, names and mesh sharing stay as exported (already in Godot world coordinates).

const Zones := preload("res://scripts/world/colony_zones.gd")
const MATERIAL_DIR := "res://materials/colony/"

var _zones: Zones
var _mat_cache := {}
var _done_meshes := {}


func _post_import(scene: Node) -> Object:
	_zones = Zones.from_manifest("res://data/colony_manifest.json")
	_walk(scene, Transform3D.IDENTITY)
	return scene


func _walk(node: Node, parent_xf: Transform3D) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	if node.has_meta("extras"):
		var ex: Variant = node.get_meta("extras")
		if ex is Dictionary:
			for k in ex:
				node.set_meta(String(k), ex[k])
	if node is MeshInstance3D:
		_fix_mesh(node as MeshInstance3D, xf)
	for c in node.get_children():
		_walk(c, xf)


func _fix_mesh(mi: MeshInstance3D, xf: Transform3D) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	if not _done_meshes.has(mesh):
		_done_meshes[mesh] = true
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m == null:
				continue
			var ext := _external(m.resource_name)
			if ext:
				mesh.surface_set_material(i, ext)
	var box: AABB = xf * mesh.get_aabb()
	var area := String(mi.get_meta("area", ""))
	var mask := 0
	if mi.has_meta("env_scenery"):
		mask = _zones.outdoor_mask() | _zones.mask_for_aabb(box)
	else:
		mask = _zones.mask_for_aabb(box, area)
	if area in ["Garden Dome", "Exterior"] or (mask & _zones.outdoor_mask()) != 0:
		mask |= _zones.sun_bit()
	mi.layers = mask
	if mi.has_meta("dust"):
		mi.set_instance_shader_parameter("dust", float(mi.get_meta("dust")))


func _external(mname: String) -> Material:
	if _mat_cache.has(mname):
		return _mat_cache[mname]
	var p := MATERIAL_DIR + mname + ".tres"
	var m: Material = null
	if ResourceLoader.exists(p):
		m = load(p)
	_mat_cache[mname] = m
	return m
