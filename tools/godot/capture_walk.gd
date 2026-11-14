extends SceneTree
## Walks the player forward in third person and saves frames, to check the walk clip in the real game.
## Needs a window (no --headless). Run: godot --path . --resolution 1280x720 --script res://tools/godot/capture_walk.gd -- --out <folder>

var out_dir := ""
var main: GameMain


func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = ProjectSettings.globalize_path("res://").path_join("_test_saves/capture_walk")
	for i in args.size():
		if args[i] == "--out":
			out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var save_dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/capture_walk_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir.path_join(f))
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	root.add_child(main)
	await _frames(90)
	var player := main.player
	player.set_first_person(false)
	player.teleport(Vector3(-18.0, 0.3, 33.0), 0.79)  # open ground outside: room to walk
	var anim := player.visual().find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	print("walk clip length=%.4f loop=%d" % [anim.get_animation(&"walk").length, anim.get_animation(&"walk").loop_mode])
	await _frames(30)
	await _shot("00_idle")
	Input.action_press(&"move_forward")
	await _frames(45)
	for i in 6:
		await _frames(6)
		var v := Vector3(player.velocity.x, 0, player.velocity.z).length()
		print("frame %d anim=%s pos=%.3f speed_scale=%.2f ground=%.2f m/s" % [i, anim.current_animation, anim.current_animation_position, anim.speed_scale, v])
		await _shot("walk_%d" % i)
	Input.action_release(&"move_forward")
	await _frames(40)
	print("after stop anim=%s" % anim.current_animation)
	main.services.saves.delete_all()
	quit(0)
