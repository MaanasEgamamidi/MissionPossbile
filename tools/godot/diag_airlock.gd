extends SceneTree
## Walks through the exit tunnel airlock both ways and checks the interlock: the two doors are never open together,
## the player still gets through, and the pressure cycle wait is reported.
## Run: godot --headless --path . --script res://tools/godot/diag_airlock.gd

var main: GameMain


func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame


func _walk(player: PlayerController, from: Vector3, to: Vector3, doors: Array[DoorController], max_s: float) -> Dictionary:
	player.teleport(from + Vector3.UP * 0.1, atan2(-(to - from).x, -(to - from).z))
	player.camera_rig().rotation.x = 0
	await _frames(10)
	Input.action_press(&"move_forward")
	var both := 0
	var frames := 0
	var waited := 0
	var messages := 0
	for f in int(max_s * 60.0):
		await physics_frame
		frames += 1
		if doors[0].open_amount > 0.0 and doors[1].open_amount > 0.0:
			both += 1
		if Vector3(player.velocity.x, 0, player.velocity.z).length() < 0.2:
			waited += 1
		if Vector2(player.global_position.x - to.x, player.global_position.z - to.z).length() < 0.5:
			break
	Input.action_release(&"move_forward")
	await _frames(5)
	var p := player.global_position
	return {"reached": Vector2(p.x - to.x, p.z - to.z).length() < 0.6, "seconds": snappedf(frames / 60.0, 0.01),
		"blocked_seconds": snappedf(waited / 60.0, 0.01), "frames_both_open": both, "end": [snappedf(p.x, 0.01), snappedf(p.z, 0.01)]}


func _initialize() -> void:
	var save_dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/diag/airlock_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir.path_join(f))
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	root.add_child(main)
	await _frames(30)
	var doors := main.airlock_doors
	print("airlock doors: %d paired=%s" % [doors.size(), doors.size() == 2 and doors[0].partner == doors[1]])
	var cycles := []
	for d: DoorController in doors:
		d.cycle_started.connect(func(id: int, s: float) -> void: cycles.append([id, snappedf(s, 0.01)]))
	var out := await _walk(main.player, Vector3(22, 0, 6), Vector3(22, 0, 20), doors, 20.0)
	print("OUT  %s cycles=%s" % [out, cycles])
	cycles.clear()
	var back := await _walk(main.player, Vector3(22, 0, 20), Vector3(22, 0, 6), doors, 20.0)
	print("BACK %s cycles=%s" % [back, cycles])
	# someone standing in the middle of the tunnel, where both doors can sense them
	main.player.teleport(Vector3(22, 0.1, 12.59), 0.0)
	var both := 0
	for f in 360:
		await physics_frame
		if doors[0].open_amount > 0.0 and doors[1].open_amount > 0.0:
			both += 1
	print("MIDDLE inner=%.2f outer=%.2f frames_both_open=%d" % [doors[0].open_amount, doors[1].open_amount, both])
	main.services.saves.delete_all()
	quit(0)
