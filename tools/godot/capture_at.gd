extends SceneTree
## Saves screenshots from given spots. Needs a window (no --headless).
## Run: godot --path . --resolution 1280x720 --script res://tools/godot/capture_at.gd -- --out <folder> --shot name,x,y,z,yaw_deg,pitch_deg,view[,suit] ...
## view is "fp" (first person) or "tp" (third person); y is the feet height.

var main: GameMain


func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/capture_at")
	var shots: Array[PackedStringArray] = []
	var i := 0
	while i < args.size():
		if args[i] == "--out":
			out_dir = args[i + 1]
			i += 1
		elif args[i] == "--shot":
			shots.append(args[i + 1].split(","))
			i += 1
		i += 1
	DirAccess.make_dir_recursive_absolute(out_dir)
	var save_dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/capture_at_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir.path_join(f))
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	root.add_child(main)
	await _frames(60)
	var player := main.player
	for s: PackedStringArray in shots:
		player.set_first_person(s[6] == "fp")
		if s.size() > 7:
			main.services.state().character_of_peer(SessionService.HOST_PEER).suit_on = s[7] == "suit"
		player.teleport(Vector3(float(s[1]), float(s[2]), float(s[3])), deg_to_rad(float(s[4])))
		player.camera_rig().rotation.x = deg_to_rad(float(s[5]))
		await _frames(40)
		await process_frame
		await RenderingServer.frame_post_draw
		var t := player.aimed_target()
		print("%s at %s target=%s" % [s[0], player.global_position, t.id])
		root.get_texture().get_image().save_png(out_dir.path_join(s[0] + ".png"))
	main.services.saves.delete_all()
	quit(0)
