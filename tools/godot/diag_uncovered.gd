extends SceneTree
## Audit: loads the full game (game.tscn) and, for every visible mesh of the world, samples points on its near-vertical
## faces inside the body band (0.1 to 1.9 m above the ground under them) and asks the physics space whether collision
## lies between 0.6 m in front of and 0.25 m behind each point (from either side). Lists the meshes whose sampled surface is mostly not covered.
## Run: godot --headless --path . --script res://tools/godot/diag_uncovered.gd -- [--out <file.json>] [--min 0.6]
## Writes _test_saves/diag/diag_uncovered.json by default.

const SAMPLES := 48
## A surface point counts as covered when collision lies between REACH in front of it and 0.25 m behind it (from either
## side): the player is then stopped before reaching the visible surface.
const REACH := 0.6
var main: GameMain


func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var diag := ProjectSettings.globalize_path("res://").path_join("_test_saves/diag")
	var out := diag.path_join("diag_uncovered.json")
	var min_cov := 0.6
	for i in args.size():
		if args[i] == "--out":
			out = args[i + 1]
		elif args[i] == "--min":
			min_cov = float(args[i + 1])
	var save_dir := diag.path_join("uncovered_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir.path_join(f))
	var t0 := Time.get_ticks_msec()
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	main.show_menu = false   # straight into the game, no main menu
	root.add_child(main)
	print("game ready in %d ms; prop collision %s" % [Time.get_ticks_msec() - t0, main.prop_collision_stats])
	await _frames(5)
	print("prop collision %s" % main.prop_collision_stats)
	var space := main.get_world_3d().direct_space_state
	var faces_of := {}
	var rows: Array = []
	var rng := RandomNumberGenerator.new()
	var total := 0
	for node: Node in main.world.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		total += 1
		var faces: PackedVector3Array = faces_of.get(mi.mesh, PackedVector3Array())
		if faces.is_empty():
			faces = mi.mesh.get_faces()
			faces_of[mi.mesh] = faces
		var tri_count := faces.size() / 3
		if tri_count == 0:
			continue
		var xf := mi.global_transform
		var aabb := xf * mi.mesh.get_aabb()
		rng.seed = hash(str(mi.get_path()))
		var valid := 0
		var covered := 0
		var tries := 0
		while valid < SAMPLES and tries < SAMPLES * 8:
			tries += 1
			var t := rng.randi_range(0, tri_count - 1) * 3
			var a := xf * faces[t]
			var b := xf * faces[t + 1]
			var c := xf * faces[t + 2]
			var nrm := (b - a).cross(c - a)
			if nrm.length_squared() < 1e-12:
				continue
			nrm = nrm.normalized()
			if absf(nrm.y) > 0.7:
				continue
			var p := (a + b + c) / 3.0
			var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.02, p + Vector3.DOWN * 40.0, Layers.WORLD))
			var ground := (down.position as Vector3).y if not down.is_empty() else aabb.position.y
			if p.y < ground + 0.1 or p.y > ground + 1.9:
				continue
			valid += 1
			var q := PhysicsRayQueryParameters3D.create(p + nrm * REACH, p - nrm * 0.25, Layers.WORLD | Layers.DOOR)
			q.hit_back_faces = true
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				q = PhysicsRayQueryParameters3D.create(p - nrm * REACH, p + nrm * 0.25, Layers.WORLD | Layers.DOOR)
				q.hit_back_faces = true
				hit = space.intersect_ray(q)
			if not hit.is_empty():
				covered += 1
		if valid < 3:
			continue
		var cov := float(covered) / valid
		if cov >= min_cov:
			continue
		var mats := PackedStringArray()
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			mats.append(m.resource_path.get_file().get_basename() if m != null and m.resource_path != "" else (m.resource_name if m != null else "-"))
		rows.append({"path": str(main.world.get_path_to(mi)), "tris": tri_count, "coverage": snappedf(cov, 0.01), "valid": valid,
			"center": [snappedf(aabb.get_center().x, 0.01), snappedf(aabb.get_center().y, 0.01), snappedf(aabb.get_center().z, 0.01)],
			"size": [snappedf(aabb.size.x, 0.01), snappedf(aabb.size.y, 0.01), snappedf(aabb.size.z, 0.01)], "mats": ",".join(mats)})
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.size[0] * x.size[1] * x.size[2] > y.size[0] * y.size[1] * y.size[2])
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"visible_meshes": total, "uncovered": rows}, " "))
	f.close()
	print("visible meshes=%d uncovered=%d -> %s" % [total, rows.size(), out])
	main.services.saves.delete_all()
	quit(0)
