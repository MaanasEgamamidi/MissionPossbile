extends SceneTree
## Walks the real player into every shape PropCollision built (and into named spots given on the command line) and
## checks that it is stopped at the surface: it never ends up overlapping the shape (tested with a capsule 0.08 m
## thinner than the body) and never passes the object's centre. Starts that are blocked or off the ground are skipped.
## Run: godot --headless --path . --script res://tools/godot/diag_walk_into.gd [-- --dirs 4 --only <substring>]
##      [--line name,x0,z0,x1,z1 ...]   (extra straight walks: reports where the player stopped)
## Writes _test_saves/diag/diag_walk_into.json.

var main: GameMain
var space: PhysicsDirectSpaceState3D
var probe := CapsuleShape3D.new()


func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame


func _overlaps(at: Vector3, only_rid: RID, only_shape: int) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.transform = Transform3D(Basis(), at + Vector3.UP * 0.9)
	q.collision_mask = Layers.WORLD | Layers.DOOR
	q.exclude = [main.player.get_rid()]
	for r: Dictionary in space.intersect_shape(q, 64):
		if only_rid == RID() or (r.rid == only_rid and (only_shape < 0 or int(r.shape) == only_shape)):
			return true
	return false


func _walk(from: Vector3, to: Vector3, frames: int, rid: RID, shape_idx: int) -> Dictionary:
	var player := main.player
	player.teleport(from + Vector3.UP * 0.05, atan2(-(to - from).x, -(to - from).z))
	player.camera_rig().rotation.x = 0
	await _frames(4)
	Input.action_press(&"move_forward")
	var inside := 0
	for f in frames:
		await physics_frame
		if rid != RID() and _overlaps(player.global_position, rid, shape_idx):
			inside += 1
		if Vector2(player.global_position.x - to.x, player.global_position.z - to.z).length() < 0.3:
			break
	Input.action_release(&"move_forward")
	await _frames(3)
	return {"end": player.global_position, "inside_frames": inside}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dirs := 4
	var only := ""
	var lines: Array[PackedStringArray] = []
	var i := 0
	while i < args.size():
		match args[i]:
			"--dirs": dirs = int(args[i + 1]); i += 1
			"--only": only = args[i + 1]; i += 1
			"--line": lines.append(args[i + 1].split(",")); i += 1
		i += 1
	probe.radius = 0.24
	probe.height = 1.6
	var diag := ProjectSettings.globalize_path("res://").path_join("_test_saves/diag")
	var save_dir := diag.path_join("walk_into_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir.path_join(f))
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	main.show_menu = false   # straight into the game, no main menu
	root.add_child(main)
	await _frames(20)
	space = main.get_world_3d().direct_space_state
	var height := load(GameMain.TERRAIN_HEIGHT_PATH) as TerrainHeight
	print("STATS %s" % main.prop_collision_stats)
	var report := {"stats": main.prop_collision_stats, "tested": 0, "blocked": 0, "slid_past": 0, "skipped_starts": 0, "failures": [], "lines": []}
	var props := main.collision.get_node("Props") as StaticBody3D
	for line: PackedStringArray in lines:
		var a := Vector3(float(line[1]), 0, float(line[2]))
		var b := Vector3(float(line[3]), 0, float(line[4]))
		a.y = height.height_at(a.x, a.z)
		var r := await _walk(a, b, int(a.distance_to(b) / 2.5 * 60.0) + 60, RID(), -1)
		var e: Vector3 = r.end
		var row := {"name": line[0], "from": [a.x, a.z], "to": [b.x, b.z], "end": [snappedf(e.x, 0.01), snappedf(e.y, 0.01), snappedf(e.z, 0.01)], "left_m": snappedf(Vector2(e.x - b.x, e.z - b.z).length(), 0.01)}
		report.lines.append(row)
		print("LINE %s" % row)
	var shape_idx := 0
	for cs: Node in props.get_children():
		var idx := shape_idx
		shape_idx += 1
		if only != "" and not (only in String(cs.name)):
			continue
		var shape := (cs as CollisionShape3D).shape
		var pts: PackedVector3Array = (shape as ConvexPolygonShape3D).points if shape is ConvexPolygonShape3D else (shape as ConcavePolygonShape3D).get_faces()
		var box := AABB(pts[0], Vector3.ZERO)
		for p in pts:
			box = box.expand(p)
		var c := box.get_center()
		for k in dirs:
			var a := k * TAU / dirs
			var dir := Vector3(sin(a), 0, cos(a))
			var reach := absf(dir.x) * box.size.x * 0.5 + absf(dir.z) * box.size.z * 0.5
			if reach > 6.0:
				continue   # big shells are walked with --line instead
			var start := c + dir * (reach + 1.0)
			start.y = height.height_at(start.x, start.z)
			if box.position.y > start.y + 1.9 or box.end.y < start.y + 0.15:
				continue   # nothing at body height on this side
			if _overlaps(start, RID(), -1):
				report.skipped_starts += 1
				continue
			var goal := Vector3(c.x, start.y, c.z)
			var r := await _walk(start, goal, 70, props.get_rid(), idx)
			var e: Vector3 = r.end
			report.tested += 1
			var progress := (e - start).dot(-dir)
			var passed_centre := progress > reach + 1.0 + 0.05
			if int(r.inside_frames) > 0:
				report.failures.append({"shape": String(cs.name), "kind": String(cs.get_meta("prop_collision")), "dir": k, "inside_frames": r.inside_frames,
					"passed_centre": passed_centre, "start": [snappedf(start.x, 0.01), snappedf(start.z, 0.01)], "end": [snappedf(e.x, 0.01), snappedf(e.z, 0.01)]})
			elif progress < reach + 1.0 - 0.25:
				report.blocked += 1
			else:
				report.slid_past += 1
	var f := FileAccess.open(diag.path_join("diag_walk_into.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	f.close()
	print("tested=%d blocked=%d slid_past=%d skipped_starts=%d failures=%d" % [report.tested, report.blocked, report.slid_past, report.skipped_starts, report.failures.size()])
	for fl: Dictionary in report.failures:
		print("FAIL %s" % fl)
	main.services.saves.delete_all()
	quit(0)
