extends SceneTree
## Walks the player in a straight line and reports where it stopped, to prove a wall blocks or a passage is open.
## Run: godot --headless --path . --script res://tools/godot/diag_walk_lines.gd -- name,x0,z0,x1,z1 ...

var main: GameMain


func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame


func _initialize() -> void:
	var save_dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/diag_walk_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir.path_join(f))
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	root.add_child(main)
	await _frames(30)
	var player := main.player
	for line: String in OS.get_cmdline_user_args():
		var s := line.split(",")
		var a := Vector3(float(s[1]), 0, float(s[2]))
		var b := Vector3(float(s[3]), 0, float(s[4]))
		var h := main.services.config  # unused, keeps the services alive in headless runs
		player.teleport(a + Vector3.UP * 1.0, atan2(-(b - a).x, -(b - a).z))
		player.camera_rig().rotation.x = 0
		await _frames(30)
		Input.action_press(&"move_forward")
		var frames := int((b - a).length() / 2.0 * 60.0) + 120
		for f in frames:
			await physics_frame
			if Vector2(player.global_position.x - b.x, player.global_position.z - b.z).length() < 0.4:
				break
		Input.action_release(&"move_forward")
		await _frames(5)
		var p := player.global_position
		print("LINE %s from %s to %s ended at (%.2f, %.2f, %.2f) left %.2f m" % [s[0], a, b, p.x, p.y, p.z, Vector2(p.x - b.x, p.z - b.z).length()])
	main.services.saves.delete_all()
	quit(0)
