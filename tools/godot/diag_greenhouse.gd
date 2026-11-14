extends SceneTree
## In-game checks for things a player reported: can the suit rack be aimed at, and does every door let the player through.
## Run: godot --headless --path . --script res://tools/godot/diag_game.gd -- --out <file.json>

var main: GameMain


func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := ProjectSettings.globalize_path("res://").path_join("_test_saves/diag/diag_game.json")
	for i in args.size():
		if args[i] == "--out":
			out = args[i + 1]
	var save_dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/diag/game_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir.path_join(f))
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	main.show_menu = false   # straight into the game, no main menu
	root.add_child(main)
	await _frames(30)
	var player := main.player
	var report := []
	player.set_first_person(true)
	for door: Node in main.collision.get_node("Doors").get_children():
		var dc := door as DoorController
		if dc.door_id < 18 or dc.door_id > 21:
			continue
		var leaves := dc.get_children().filter(func(n: Node) -> bool: return n is AnimatableBody3D)
		var centre := Vector3.ZERO
		for l: Node in leaves:
			centre += (l as Node3D).global_position
		centre /= leaves.size()
		var normal := (leaves[0] as Node3D).global_basis.z
		normal.y = 0
		normal = normal.normalized()
		var tangent := normal.cross(Vector3.UP)
		for off: float in [-0.45, -0.35, -0.25, 0.25, 0.35, 0.45]:
			var start := centre + normal * 1.6 + tangent * off
			var goal := centre - normal * 1.6 + tangent * off
			player.teleport(start + Vector3.UP * 0.1, atan2(-(goal - start).x, -(goal - start).z))
			player.camera_rig().rotation.x = 0
			await _frames(5)
			Input.action_press(&"move_forward")
			var best := 99.0
			for f in 240:
				await physics_frame
				best = minf(best, Vector2(player.global_position.x - goal.x, player.global_position.z - goal.z).length())
			Input.action_release(&"move_forward")
			await _frames(5)
			report.append({"door": dc.door_id, "offset": off, "reached": best < 0.6, "closest_m": snappedf(best, 0.01)})
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	f.close()
	main.services.saves.delete_all()
	print("done -> " + out)
	quit(0)
