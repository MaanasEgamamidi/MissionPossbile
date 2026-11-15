extends RefCounted
## T11 Dust (2026-11-14, docs/revisions/BROKEN_PARTS_BRIEF.md): while the hangar is "broken", Mars dust tracked in
## through the airlock lies on every hangar object (the colony surface shader's own dust layer) and the dust mesh of
## the broken part (hg_dust__broken) covers the floor. The T11 puzzle cleans the hangar area by area: its host
## puzzle_state lowers the dust of the objects in each cleaned area and hides that area's dust patches. Fixed: the
## hangar is clean again and the floor markings show (HabitatFinish's clean indoor look comes back exactly).
## Loaded by path from broken_part_presenter.gd (no class_name).

const SURFACE_SHADER := "res://materials/colony_surface.gdshader"
## Map area (mesh metadata "area") whose objects get dusty.
const DEFAULT_AREA := "Hangar"
## Hangar floor in Godot world coordinates (brief: x 14-30, z -8..2).
const DEFAULT_REGION := AABB(Vector3(14.0, -0.5, -8.0), Vector3(16.0, 6.0, 10.0))
## Dust value (the shader's per-object "dust") on hangar objects while nothing has been cleaned, when the data file
## gives none (it gives dust.broken_value, from BP10_hangar_dust.blend). Designer balance.
const DEFAULT_AMOUNT := 0.85
const RULE_PATH := "res://scripts/tasks/puzzles/t11_rule.gd"

## Hangar objects that carry the dust layer.
var meshes: Array[MeshInstance3D] = []
## Dust patches (nodes of the broken model) that disappear area by area.
var patches: Array[Node3D] = []
var amount := DEFAULT_AMOUNT
var region := DEFAULT_REGION
## Dust left per cleaning area, 0 (clean) .. 1 (as dusty as at the start).
var levels: Array[float] = [1.0]
## True while the dusty look is applied.
var dusty := false
## The T11 rule's cleaning areas (x, z floor rectangles); empty = a grid over `region`.
var rects: Array[Rect2] = []

var _shader: Shader
var _dusty_materials := {}      # source material -> copy with the dust layer switched back on
var _saved := {}                # mesh -> {"dust": float, "overrides": Array}
var _patch_area := {}           # patch -> area index (for the current number of areas)
var _mesh_area := {}            # mesh -> area index


## `entry` is the part's record from data/broken_parts.json. Its "dust" record gives "area" (mesh metadata),
## "broken_value" (the shader's dust while broken) and "dust_mesh_node" (the dust mesh of the broken model). Also
## read: "dust_region": {"center", "size"} (default: the part's "bounds") and "dust_nodes" (several patch nodes).
func setup(world: Node, entry: Dictionary, model: Node3D) -> void:
	_shader = load(SURFACE_SHADER) as Shader
	rects = rule_rects()
	var spec: Dictionary = entry.get("dust", {}) if entry.get("dust") is Dictionary else {}
	amount = maxf(0.0, float(spec.get("broken_value", entry.get("dust_amount", DEFAULT_AMOUNT))))
	var r: Dictionary = entry.get("dust_region", entry.get("bounds", {}))
	if r.has("center") and r.has("size"):
		var c := _v3(r.center)
		var s := _v3(r.size)
		region = AABB(c - s * 0.5, s)
	var area := String(spec.get("area", entry.get("dust_area", DEFAULT_AREA)))
	var named: Array = (entry.get("dust_nodes", []) as Array).duplicate()
	if spec.has("dust_mesh_node") and not named.has(String(spec.dust_mesh_node)):
		named.append(String(spec.dust_mesh_node))
	if world != null:
		for node in world.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			var a := String(mi.get_meta("area", ""))
			if a == area:
				meshes.append(mi)
	if model != null:
		for node in model.find_children("*", "Node3D", true, false):
			var n := node as Node3D
			if named.has(String(n.name)) or (named.is_empty() and n is MeshInstance3D and String(n.name).to_lower().contains("dust")):
				patches.append(n)


## The installed T11 rule (scripts/tasks/puzzles/t11_rule.gd) when it offers area_dust(task) and AREAS, else null.
static func rule() -> Script:
	if not ResourceLoader.exists(RULE_PATH):
		return null
	var script := load(RULE_PATH) as Script
	if script == null or not script.get_script_constant_map().has("AREAS"):
		return null
	for m: Dictionary in script.get_script_method_list():
		if String(m.name) == "area_dust":
			return script
	return null


## The T11 rule's cleaning areas as floor rectangles (x, z), in its AREAS order; empty without the rule.
static func rule_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var script := rule()
	if script == null:
		return out
	for area: Variant in script.get_script_constant_map().AREAS:
		var r: Array = (area as Dictionary).get("rect", []) if area is Dictionary else []
		if r.size() < 4:
			return [] as Array[Rect2]
		out.append(Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1])))
	return out


## The dust left in each cleaning area, read from the T11 task record (host state). With the T11 rule installed and
## its own state format ({"seed", "step", "areas": {id: 0..1}}, or empty = the seeded start) its area_dust() decides,
## in AREAS order. Otherwise tolerant of other formats: puzzle_state.dust / .levels / .patches (numbers 0..1 or 0..max,
## booleans, or {dust|left|clean} records) or puzzle_state.cleaned (indices or booleans with .count); else one area at
## 1 - progress.
static func levels_from_task(task: Dictionary) -> Array[float]:
	var out: Array[float] = []
	var ps: Variant = task.get("puzzle_state", {})
	var script := rule()
	if script != null and ps is Dictionary and ((ps as Dictionary).is_empty() or (ps as Dictionary).get("areas") is Dictionary):
		var by_id: Variant = script.call(&"area_dust", task)
		if by_id is Dictionary:
			for area: Variant in script.get_script_constant_map().AREAS:
				out.append(clampf(float((by_id as Dictionary).get(String((area as Dictionary).get("id", "")), 1.0)), 0.0, 1.0))
			return out
	if ps is Dictionary:
		var state: Dictionary = ps
		for key: String in ["dust", "levels", "patches", "areas"]:
			if state.get(key) is Array and not (state[key] as Array).is_empty():
				var top := maxf(1.0, float(state.get("max", 1.0)))
				for v: Variant in state[key]:
					out.append(_level_of(v, top))
				return out
		for key: String in ["cleaned", "clean"]:
			if state.get(key) is Array:
				var list: Array = state[key]
				var count := int(state.get("count", state.get("patch_count", 0)))
				if not list.is_empty() and list[0] is bool:
					for v: Variant in list:
						out.append(0.0 if bool(v) else 1.0)
					return out
				if count > 0:
					for i in count:
						out.append(0.0 if list.has(i) or list.has(float(i)) else 1.0)
					return out
	out.append(clampf(1.0 - float(task.get("progress", 0.0)), 0.0, 1.0))
	return out


static func _level_of(v: Variant, top: float) -> float:
	if v is bool:
		return 0.0 if bool(v) else 1.0
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("clean"):
			return 0.0 if bool(d.clean) else 1.0
		if d.has("cleaned"):
			return 0.0 if bool(d.cleaned) else 1.0
		for k: String in ["dust", "left", "level"]:
			if d.has(k):
				return clampf(float(d[k]) / maxf(1.0, float(d.get("max", top))), 0.0, 1.0)
		return 1.0
	return clampf(float(v) / top, 0.0, 1.0)


## Cleaning area of a world point: the T11 rule's floor rectangle that holds it (or the nearest one); without the
## rule, the hangar region split into a grid (2 rows when the count is even and >= 4).
func area_of(p: Vector3, count: int) -> int:
	if count <= 1:
		return 0
	if rects.size() == count:
		var best := 0
		var best_d := INF
		var q := Vector2(p.x, p.z)
		for i in rects.size():
			var r := rects[i]
			var d := q.distance_to(q.clamp(r.position, r.end))
			if d < best_d:
				best_d = d
				best = i
		return best
	var rows := 2 if count >= 4 and count % 2 == 0 else 1
	var cols := ceili(float(count) / float(rows))
	var u := clampf((p.x - region.position.x) / maxf(region.size.x, 0.001), 0.0, 0.999)
	var v := clampf((p.z - region.position.z) / maxf(region.size.z, 0.001), 0.0, 0.999)
	return mini(count - 1, int(v * rows) * cols + int(u * cols))


## Applies the dusty look with `area_levels` (see levels_from_task).
func apply_levels(area_levels: Array[float]) -> void:
	if area_levels.is_empty():
		area_levels = [1.0]
	var recount := area_levels.size() != levels.size() or _mesh_area.is_empty()
	levels = area_levels.duplicate()
	if not dusty:
		dusty = true
		for mi in meshes:
			if is_instance_valid(mi):
				_make_dusty(mi)
	if recount:
		_mesh_area.clear()
		_patch_area.clear()
		for mi in meshes:
			if is_instance_valid(mi):
				_mesh_area[mi] = area_of(_centre(mi), levels.size())
		for n in patches:
			if is_instance_valid(n):
				_patch_area[n] = area_of(_centre(n), levels.size())
	for mi in meshes:
		if is_instance_valid(mi):
			mi.set_instance_shader_parameter(&"dust", amount * levels[int(_mesh_area.get(mi, 0))])
	if patches.size() == 1:
		# One dust mesh over the whole floor: it thins out as the areas are cleaned.
		var left := 0.0
		for v in levels:
			left += v / float(levels.size())
		var only := patches[0]
		if is_instance_valid(only):
			only.visible = left > 0.02
			if only is GeometryInstance3D:
				(only as GeometryInstance3D).transparency = clampf(1.0 - left, 0.0, 0.95)
		return
	for n in patches:
		if is_instance_valid(n):
			n.visible = levels[int(_patch_area.get(n, 0))] > 0.02


## The dust level a hangar object shows now (tests).
func dust_of(mi: MeshInstance3D) -> float:
	return float(mi.get_instance_shader_parameter(&"dust"))


## Clean hangar: every object exactly as it was before the dust came (materials and dust value).
func clean() -> void:
	dusty = false
	levels = [0.0]
	for mi: MeshInstance3D in _saved:
		if not is_instance_valid(mi):
			continue
		var s: Dictionary = _saved[mi]
		var overrides: Array = s.overrides
		for i in mini(overrides.size(), mi.get_surface_override_material_count()):
			mi.set_surface_override_material(i, overrides[i])
		mi.set_instance_shader_parameter(&"dust", float(s.dust))
	_saved.clear()
	_mesh_area.clear()
	_patch_area.clear()


func _make_dusty(mi: MeshInstance3D) -> void:
	if _saved.has(mi):
		return
	var overrides := []
	for i in mi.get_surface_override_material_count():
		overrides.append(mi.get_surface_override_material(i))
	var before: Variant = mi.get_instance_shader_parameter(&"dust")
	_saved[mi] = {"dust": float(before) if before != null else 0.0, "overrides": overrides}
	# Indoor objects were given dust-free copies of their materials (HabitatFinish): put the dust layer back on a copy.
	for i in mi.get_surface_override_material_count():
		var mat := mi.get_active_material(i) as ShaderMaterial
		if mat == null or mat.shader != _shader:
			continue
		var gain: Variant = mat.get_shader_parameter(&"dust_gain")
		if gain != null and float(gain) >= 0.99:
			continue
		if not _dusty_materials.has(mat):
			var copy := mat.duplicate() as ShaderMaterial
			copy.set_shader_parameter(&"dust_gain", 1.0)
			_dusty_materials[mat] = copy
		mi.set_surface_override_material(i, _dusty_materials[mat])


static func _centre(n: Node3D) -> Vector3:
	var xf := n.global_transform if n.is_inside_tree() else n.transform
	if n is VisualInstance3D:
		return xf * (n as VisualInstance3D).get_aabb().get_center()
	return xf.origin


static func _v3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
