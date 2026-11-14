@tool
extends EditorScript
## Perf overhaul Phase 5.3, editor tool (File > Run with this script open). DRY RUN ONLY: prints the draw-distance
## plan VisibilityRanges applies at run time (end = PerfSettings.range_per_metre x largest dimension, 10 % margin) for
## every Mars scenery node of the open colony_world scene that has no range yet. It never writes: the scenery lives
## inside the imported environment.glb, and the runtime switch (PerfSettings.visibility_ranges_enabled) is what applies
## it. The 996 rocks already carry hand-authored ranges from tools/godot/colony_post_import.gd and are skipped.

const DRY_RUN := true


func _run() -> void:
	var scene := get_editor_interface().get_edited_scene_root()
	if scene == null:
		print("apply_visibility_ranges: open res://scenes/world/colony_world.tscn first")
		return
	var roots: Array[Node3D] = []
	for n: String in ["Environment", "Terrain"]:
		var r := scene.get_node_or_null(n) as Node3D
		if r != null:
			roots.append(r)
	var plan := VisibilityRanges.make_plan(roots, 150.0, 30.0)
	for item: Array in plan:
		var g := item[0] as GeometryInstance3D
		print("%s %s: visibility_range_end %.0f m (margin %.0f m)" % ["WOULD SET" if DRY_RUN else "SET", scene.get_path_to(g), item[1], float(item[1]) * 0.1])
	print("apply_visibility_ranges: %d nodes in the plan (dry run, nothing written)" % plan.size())
