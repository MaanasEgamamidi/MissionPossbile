extends SceneTree
## Lists the shapes PropCollision built at load (kind, triangle or point count, bounds), biggest first, plus its stats.
## Run: godot --headless --path . --script res://tools/godot/diag_props.gd [-- --top 60]

var main: GameMain


func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var top := 60
	for i in args.size():
		if args[i] == "--top":
			top = int(args[i + 1])
	var save_dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/diag/props_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir.path_join(f))
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	main.show_menu = false   # straight into the game, no main menu
	root.add_child(main)
	await _frames(2)
	print("STATS %s" % main.prop_collision_stats)
	var rows: Array = []
	for cs: Node in main.collision.get_node("Props").get_children():
		var s := (cs as CollisionShape3D).shape
		var n := 0
		var box := AABB()
		if s is ConcavePolygonShape3D:
			var f := (s as ConcavePolygonShape3D).get_faces()
			n = f.size() / 3
			box = _bounds(f)
		elif s is ConvexPolygonShape3D:
			n = (s as ConvexPolygonShape3D).points.size()
			box = _bounds((s as ConvexPolygonShape3D).points)
		rows.append([String(cs.get_meta("prop_collision")), n, String(cs.name), String(cs.get_meta("object_name")), box])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1] if a[0] == b[0] else a[0] > b[0])
	var shown := {}
	for r: Array in rows:
		shown[r[0]] = int(shown.get(r[0], 0)) + 1
		if int(shown[r[0]]) <= top:
			var b: AABB = r[4]
			print("%s %7d %-34s c=(%.1f, %.1f, %.1f) s=(%.1f, %.1f, %.1f)" % [r[0], r[1], r[2], b.get_center().x, b.get_center().y, b.get_center().z, b.size.x, b.size.y, b.size.z])
	main.services.saves.delete_all()
	quit(0)


func _bounds(p: PackedVector3Array) -> AABB:
	if p.is_empty():
		return AABB()
	var b := AABB(p[0], Vector3.ZERO)
	for v in p:
		b = b.expand(v)
	return b
