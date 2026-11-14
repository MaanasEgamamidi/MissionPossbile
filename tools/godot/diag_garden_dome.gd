extends SceneTree
## Can the player get into and out of the garden dome (the greenhouse dome south-east of the base)?
## 1. walk from outside, through the dome's airlock, to the far end of the central path;
## 2. turn round (no teleport) and walk back out through the airlock;
## 3. teleport inside the dome to positions a save could hold (on the floor) and walk out from each.
## Also reports the sampled ground height under each start, to explain any stuck teleport.
## Run: godot --headless --path . --script res://tools/godot/diag_garden_dome.gd [-- --out <file.json>]
## Writes _test_saves/diag/diag_garden_dome.json by default. Godot coordinates: dome centre (50, 0, 27), airlock to
## the west at x 42.35, outside door step near x 40.6.

const OUTSIDE := Vector3(36.0, 0.0, 27.0)
const FAR_END := 53.0

var main: GameMain


func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame


## Holds forward until `done` says so or `frames` pass; returns the trace summary.
func _walk(frames: int, done: Callable) -> Dictionary:
	var p := main.player
	var start := p.global_position
	var y_min := 99.0
	var y_max := -99.0
	Input.action_press(&"move_forward")
	var n := 0
	for f in frames:
		await physics_frame
		n += 1
		y_min = minf(y_min, p.global_position.y)
		y_max = maxf(y_max, p.global_position.y)
		if done.call(p.global_position):
			break
	Input.action_release(&"move_forward")
	await _frames(3)
	var e := p.global_position
	return {"from": [snappedf(start.x, 0.01), snappedf(start.y, 0.01), snappedf(start.z, 0.01)],
		"end": [snappedf(e.x, 0.01), snappedf(e.y, 0.01), snappedf(e.z, 0.01)], "frames": n,
		"y_min": snappedf(y_min, 0.01), "y_max": snappedf(y_max, 0.01), "moved_m": snappedf(Vector2(e.x - start.x, e.z - start.z).length(), 0.01)}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var diag := ProjectSettings.globalize_path("res://").path_join("_test_saves/diag")
	var out := diag.path_join("diag_garden_dome.json")
	for i in args.size():
		if args[i] == "--out":
			out = args[i + 1]
	var save_dir := diag.path_join("garden_dome_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir.path_join(f))
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	main.show_menu = false   # straight into the game, no main menu
	root.add_child(main)
	await _frames(30)
	var height := load(GameMain.TERRAIN_HEIGHT_PATH) as TerrainHeight
	var p := main.player
	p.set_first_person(true)
	var report := {"walk_in": {}, "walk_out": {}, "reload_starts": []}

	# 1. in, from outside the airlock, facing east (+x)
	var o := Vector3(OUTSIDE.x, height.height_at(OUTSIDE.x, OUTSIDE.z) + 0.05, OUTSIDE.z)
	p.teleport(o, -PI / 2.0)
	p.camera_rig().rotation.x = 0
	await _frames(5)
	report.walk_in = await _walk(900, func(pos: Vector3) -> bool: return pos.x >= FAR_END)
	report.walk_in.reached_far_end = float(report.walk_in.end[0]) >= FAR_END - 0.3
	print("WALK_IN %s" % report.walk_in)

	# 2. turn round where it stands and walk back out (no teleport)
	p.camera_rig().add_look(PI, 0.0)
	await _frames(3)
	report.walk_out = await _walk(1200, func(pos: Vector3) -> bool: return pos.x <= OUTSIDE.x + 0.5)
	report.walk_out.reached_outside = float(report.walk_out.end[0]) <= OUTSIDE.x + 1.0
	print("WALK_OUT %s" % report.walk_out)

	# 3. starts a save could hold: standing on the dome floor (y 0.0) at points along the path, then walk out
	for x: float in [45.0, 48.0, 50.0, 52.0]:
		for z: float in [27.0, 27.4]:
			p.teleport(Vector3(x, 0.0, z), PI / 2.0)
			p.camera_rig().rotation.x = 0
			await _frames(5)
			var r := await _walk(900, func(pos: Vector3) -> bool: return pos.x <= OUTSIDE.x + 0.5)
			r.ground_sample = snappedf(height.height_at(x, z), 0.01)
			r.reached_outside = float(r.end[0]) <= OUTSIDE.x + 1.0
			report.reload_starts.append(r)
			print("RELOAD_START %s" % r)

	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	f.close()
	main.services.saves.delete_all()
	print("done -> " + out)
	quit(0)
