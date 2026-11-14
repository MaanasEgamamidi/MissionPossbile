class_name ColonyLod
extends Node
## Hierarchical LOD for the colony seen from far outside (Perf.cfg().colony_lod_enabled, OFF by default: it changes
## pixels and has not had an idle-GPU visual check yet).
##
##   Tier 0  the existing colony (every mesh of the Colony scene)        close
##   Tier 1  one merged, simplified exterior shell (~25 % triangles)     middle distance
##   Tier 2  one very low-poly silhouette (~5 %), no shadows             far away
##
## Uses visibility ranges + Visibility Parent (Godot's HLOD): a node is hidden while its visibility-parent is visible
## according to the parent's own range, so the tiers swap without gaps or double drawing. Distances are measured from
## each proxy's ORIGIN, which tools/perf/build_colony_lod.gd puts at the colony centre (res://lod/colony_lod.json).
## Defaults: tier1_begin = radius + 40 m, tier2_begin = radius + 200 m, 8 m hysteresis, hard swap (no alpha fade).
## Switching it off clears every visibility parent and hides both proxies, which restores the authored scene exactly.

const T1_PATH := "res://lod/colony_t1.res"
const T2_PATH := "res://lod/colony_t2.res"
const INFO_PATH := "res://lod/colony_lod.json"

var tier0_root: Node3D
var tier1: MeshInstance3D
var tier2: MeshInstance3D
var tier1_begin := 120.0
var tier2_begin := 280.0
var margin := 8.0
var use_alpha_fade := false
var radius := 0.0

var _applied := false
var _tier0: Array[GeometryInstance3D] = []


func setup(colony: Node3D) -> bool:
	tier0_root = colony
	if not (ResourceLoader.exists(T1_PATH) and ResourceLoader.exists(T2_PATH) and FileAccess.file_exists(INFO_PATH)):
		push_warning("ColonyLod: proxies not built (run tools/perf/build_colony_lod.gd); colony LOD stays off")
		return false
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INFO_PATH))
	var c: Array = info.centre
	radius = float(info.radius)
	tier1_begin = Perf.cfg().colony_tier1_begin if Perf.cfg().colony_tier1_begin > 0.0 else radius + 40.0
	tier2_begin = Perf.cfg().colony_tier2_begin if Perf.cfg().colony_tier2_begin > 0.0 else radius + 200.0
	var holder := Node3D.new()
	holder.name = "ColonyLodProxies"
	add_child(holder)
	holder.global_position = Vector3(float(c[0]), float(c[1]), float(c[2]))
	tier1 = _proxy(holder, "ColonyT1", load(T1_PATH) as Mesh)
	tier2 = _proxy(holder, "ColonyT2", load(T2_PATH) as Mesh)
	for n in tier0_root.find_children("*", "GeometryInstance3D", true, false):
		_tier0.append(n as GeometryInstance3D)
	add_to_group(&"colony_lod")
	return true


func _proxy(parent: Node3D, n: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.visible = false
	mi.layers = 1 << (ColonyZones.SUN_LAYER - 1)   # never in a zone layer: the zone system must not hide it
	parent.add_child(mi)
	return mi


func _process(_delta: float) -> void:
	if tier1 == null:
		return
	if Perf.cfg().colony_lod_enabled != _applied:
		if Perf.cfg().colony_lod_enabled:
			_apply()
		else:
			_clear()


func _apply() -> void:
	_applied = true
	var mode: GeometryInstance3D.VisibilityRangeFadeMode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if use_alpha_fade else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	tier2.visibility_range_begin = tier2_begin
	tier2.visibility_range_begin_margin = margin
	tier2.visibility_range_end = 0.0
	tier2.visibility_range_fade_mode = mode
	tier2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tier1.visibility_range_begin = tier1_begin
	tier1.visibility_range_begin_margin = margin
	tier1.visibility_range_end = 0.0
	tier1.visibility_range_fade_mode = mode
	tier1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	tier1.visibility_parent = tier1.get_path_to(tier2)
	tier1.visible = true
	tier2.visible = true
	for g in _tier0:
		if is_instance_valid(g):
			g.visibility_parent = g.get_path_to(tier1)


func _clear() -> void:
	_applied = false
	for g in _tier0:
		if is_instance_valid(g):
			g.visibility_parent = NodePath()
	tier1.visibility_parent = NodePath()
	tier1.visible = false
	tier2.visible = false


func _exit_tree() -> void:
	if _applied:
		_clear()
