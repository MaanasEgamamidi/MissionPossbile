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
	player.set_first_person(false)
	player.teleport(Vector3(-5, 0.1, 3), PI)
	await _frames(10)
	var aabb := AABB()
	var first := true
	for n: Node in player.visual().find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var a := mi.global_transform * mi.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
	print("MODEL AABB pos=", aabb.position - player.global_position, " size=", aabb.size)
	# open door 18 and scan the opening at three heights along the door line z=0
	for dc: Node in main.collision.get_node("Doors").get_children():
		(dc as DoorController).open_seconds = 99.0
	player.teleport(Vector3(-5, 0.1, 1.0), PI)
	await _frames(60)
	for y in [0.3, 1.0, 1.7, 2.3]:
		var hits := []
		var x := -6.5
		while x <= -3.5:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, y, 2.0), Vector3(x, y, -2.0), Layers.WORLD | Layers.DOOR)
			q.exclude = [player.get_rid()]
			var h := player.get_world_3d().direct_space_state.intersect_ray(q)
			hits.append("%.2f:%s" % [x, ("-" if h.is_empty() else "%.2f" % h.position.z)])
			x += 0.1
		print("SCAN y=", y, " ", " ".join(hits))
	quit(0)
