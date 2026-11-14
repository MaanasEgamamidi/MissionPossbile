class_name VisibilityRanges
extends Node
## Phase 5.3: per-object draw distance for Mars scenery (Perf.cfg().visibility_ranges_enabled, OFF by default).
## Rule: visibility_range_end = range_per_metre (150) x the object's largest dimension, at least range_min, with a 10 %
## end margin: at 1080p and the game's 72 degree FOV that is roughly where the object is 5 pixels tall.
## Examples: 0.3 m pebble -> 45 m; 1 m rock -> 150 m; 4 m boulder -> 600 m. Landmarks (terrain chunks, the glass hall,
## anything larger than LANDMARK_M) keep no end. Nodes that already have a hand-authored range are never touched.
## Applied at run time to the imported environment scene (the rocks live inside environment.glb, so there is no scene
## file of ours to write them into); switching off restores every node exactly.
## tools/perf/apply_visibility_ranges.gd prints the same plan in the editor (dry run).

const LANDMARK_M := 40.0

var roots: Array[Node3D] = []
var plan: Array = []          # [GeometryInstance3D, end_m]
var _applied := false


func setup(mars_roots: Array[Node3D]) -> void:
	roots = mars_roots
	plan = make_plan(roots, Perf.cfg().range_per_metre, Perf.cfg().range_min)
	add_to_group(&"visibility_ranges")


static func make_plan(from: Array[Node3D], per_metre: float, min_end: float) -> Array:
	var out: Array = []
	for r in from:
		for n in r.find_children("*", "GeometryInstance3D", true, false):
			var g := n as GeometryInstance3D
			if g.visibility_range_end > 0.0 or g.visibility_range_begin > 0.0 or String(g.visibility_parent) != "":
				continue   # hand-authored range or HLOD member: leave it
			var size := _largest_dimension(g)
			if size <= 0.0 or size >= LANDMARK_M:
				continue
			out.append([g, maxf(size * per_metre, min_end)])
	return out


static func _largest_dimension(g: GeometryInstance3D) -> float:
	var box := g.get_aabb()
	var s := g.global_basis.get_scale() if g.is_inside_tree() else g.basis.get_scale()
	var size := box.size * s.abs()
	return maxf(size.x, maxf(size.y, size.z))


func _process(_delta: float) -> void:
	if Perf.cfg().visibility_ranges_enabled != _applied:
		_set_applied(Perf.cfg().visibility_ranges_enabled)


func _set_applied(on: bool) -> void:
	_applied = on
	for item: Array in plan:
		var g := item[0] as GeometryInstance3D
		if not is_instance_valid(g):
			continue
		var end: float = item[1]
		g.visibility_range_end = end if on else 0.0
		g.visibility_range_end_margin = end * 0.1 if on else 0.0


func _exit_tree() -> void:
	if _applied:
		_set_applied(false)
