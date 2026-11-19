class_name ShadowProxies
extends Node
## Shadow proxies (2026-11-18, docs/perf/ultra_60fps.md): the colony map's meshes are merged across rooms and carry
## ~5.4 materials each, and Godot draws every surface separately in every shadow pass (the sun's splits and each
## shadowed fixture light). At the tutorial start the sun's shadow alone was 7.7k of 12.9k draw calls (render thread
## 16 ms a frame at Ultra). For every colony mesh whose materials are all opaque and leave the vertices where they are
## (colony_surface / colony_glow / colony_screen: cull_back, no ALPHA, no VERTEX change), this adds one child mesh that
## holds the same triangles in a single surface and only casts shadows, and stops the original from casting. The
## shadow maps are drawn from the same geometry, so nothing changes on screen; meshes with glass (transparent) keep
## casting as before. The proxy is a child of its original: it follows its visibility, transform and layers.
##
## Switch: PerfSettings.shadow_proxies_enabled (on by default, off with --perf-off). Built once per mesh resource.

const PROXY_NAME := "ShadowProxy"
const PLAIN_SHADERS := ["colony_surface.gdshader", "colony_glow.gdshader", "colony_screen.gdshader"]
const META_CAST := &"perf_shadow_proxy_cast"

var colony: Node3D
var built := 0
var skipped := 0
var build_ms := 0
var _applied := false
var _cache := {}        # Mesh -> ArrayMesh (single surface, positions + indices)


func setup(colony_root: Node3D) -> void:
	colony = colony_root


func _process(_delta: float) -> void:
	var want: bool = Perf.cfg().shadow_proxies_enabled and colony != null and is_instance_valid(colony) and DisplayServer.get_name() != "headless"
	if want != _applied:
		_apply(want)


func _apply(on: bool) -> void:
	_applied = on
	if colony == null or not is_instance_valid(colony):
		return
	var t0 := Time.get_ticks_msec()
	for n: Node in colony.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.name == PROXY_NAME:
			continue
		if on:
			_add_proxy(mi)
		else:
			_remove_proxy(mi)
	if on:
		build_ms = Time.get_ticks_msec() - t0
		print_verbose("ShadowProxies: %d proxies, %d meshes left as they are, %d ms" % [built, skipped, Time.get_ticks_msec() - t0])


func _add_proxy(mi: MeshInstance3D) -> void:
	if mi.mesh == null or mi.has_meta(META_CAST) or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		return
	if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON or not _plain(mi):
		skipped += 1
		return
	var proxy_mesh: ArrayMesh = _cache.get(mi.mesh)
	if proxy_mesh == null:
		proxy_mesh = _build(mi.mesh)
		if proxy_mesh == null:
			skipped += 1
			return
		_cache[mi.mesh] = proxy_mesh
	var p := MeshInstance3D.new()
	p.name = PROXY_NAME
	p.mesh = proxy_mesh
	p.layers = mi.layers
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	p.visibility_range_begin = mi.visibility_range_begin
	p.visibility_range_end = mi.visibility_range_end
	p.visibility_range_begin_margin = mi.visibility_range_begin_margin
	p.visibility_range_end_margin = mi.visibility_range_end_margin
	mi.add_child(p, false, Node.INTERNAL_MODE_BACK)
	mi.set_meta(META_CAST, mi.cast_shadow)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	built += 1


func _remove_proxy(mi: MeshInstance3D) -> void:
	if not mi.has_meta(META_CAST):
		return
	mi.cast_shadow = int(mi.get_meta(META_CAST)) as GeometryInstance3D.ShadowCastingSetting
	mi.remove_meta(META_CAST)
	for c in mi.get_children(true):
		if c.name == PROXY_NAME:
			c.queue_free()


## Every surface opaque, culled like the default material and leaving the vertices in place.
static func _plain(mi: MeshInstance3D) -> bool:
	if not (mi.mesh is ArrayMesh):
		return false   # primitive meshes (BoxMesh ...) are single-surface already
	for i in mi.mesh.get_surface_count():
		var m := mi.get_active_material(i) as ShaderMaterial
		if m == null or m.shader == null or not PLAIN_SHADERS.has(m.shader.resource_path.get_file()):
			return false
		if mi.mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
			return false
	return true


## The mesh's triangles in one surface (positions and indices only; a shadow pass needs nothing else).
static func _build(mesh: Mesh) -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var base := verts.size()
		verts.append_array(v)
		var ix: Variant = arrays[Mesh.ARRAY_INDEX]
		if ix == null or (ix as PackedInt32Array).is_empty():
			for k in v.size():
				idx.append(base + k)
		else:
			var src := ix as PackedInt32Array
			if base == 0:
				idx.append_array(src)
			else:
				for k in src.size():
					idx.append(src[k] + base)
	if verts.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


func _exit_tree() -> void:
	if _applied:
		_apply(false)
