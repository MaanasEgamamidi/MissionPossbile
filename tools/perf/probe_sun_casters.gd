extends "res://tools/perf/perf_bench.gd"
## Counts the sun's shadow casters by where they come from (diagnostic only). WINDOWED (a running game).
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/perf/probe_sun_casters.gd -- --views=tutorial_start

func _process(delta: float) -> bool:
	if _phase != "next":
		return super(delta)
	_enter_view(_views[0])
	var sun := get_first_node_in_group(&"sun") as DirectionalLight3D
	var mask := sun.shadow_caster_mask if sun != null else 0
	var world: Node = _game.get("world")
	var groups := {}
	var surfaces := {}
	for g: Node in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if not gi.is_visible_in_tree() or gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or (gi.layers & mask) == 0:
			continue
		var key := "other"
		var p := gi.get_path()
		var rel := String(world.get_path_to(gi)) if world.is_ancestor_of(gi) else String(p)
		key = rel.get_slice("/", 0) if world.is_ancestor_of(gi) else "game:" + String(p).get_slice("/", 3)
		if gi.has_meta(&"perf_pinned_layer"):
			key += " (pinned to layer 20)"
		groups[key] = int(groups.get(key, 0)) + 1
		var n := 1
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
			n = (gi as MeshInstance3D).mesh.get_surface_count()
		surfaces[key] = int(surfaces.get(key, 0)) + n
	for k: String in groups:
		print("SUNCASTER %-50s instances %5d surfaces %5d" % [k, groups[k], surfaces[k]])
	quit(0)
	return true
