extends SceneTree
## Walks through the garden dome (greenhouse) airlock both ways and checks its sliding doors: both start shut and block
## the doorway, the two doors are never open together, the player still gets through, and the pressure cycle runs.
## Run: godot --headless --path . --script res://tools/godot/diag_garden_airlock.gd

var main: GameMain


func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame


func _walk(player: PlayerController, from: Vector3, to: Vector3, doors: Array[DoorController], max_s: float) -> Dictionary:
	player.teleport(from, atan2(-(to - from).x, -(to - from).z))
	player.camera_rig().rotation.x = 0
	await _frames(10)
	Input.action_press(&"move_forward")
	var both := 0
	var frames := 0
	var waited := 0
	var opened := [false, false]
	for f in int(max_s * 60.0):
		await physics_frame
		frames += 1
		for i in 2:
			opened[i] = opened[i] or doors[i].is_open()
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
		"blocked_seconds": snappedf(waited / 60.0, 0.01), "frames_both_open": both, "inner_opened": opened[0],
		"outer_opened": opened[1], "end": [snappedf(p.x, 0.01), snappedf(p.z, 0.01)]}


func _initialize() -> void:
	var save_dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/diag/garden_airlock_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir.path_join(f))
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	main.show_menu = false   # straight into the game, no main menu
	root.add_child(main)
	await _frames(30)
	var doors := main.garden_airlock_doors
	var ok := doors.size() == 2 and doors[0].partner == doors[1] and doors[1].partner == doors[0]
	print("garden airlock doors: %d paired=%s" % [doors.size(), ok])
	if not ok:
		quit(1)
		return
	var height := load(GameMain.TERRAIN_HEIGHT_PATH) as TerrainHeight
	var outside := Vector3(37.5, height.height_at(37.5, 27.0) + 0.05, 27.0)
	var inside := Vector3(46.5, 0.05, 27.0)
	var visuals := 0
	for d: DoorController in doors:
		for c in d.get_children():
			if c is AnimatableBody3D and main.world.find_child(String(c.name), true, false) != null:
				visuals += 1
	print("leaf visuals found: %d of 4" % visuals)

	# 1. a closed door blocks: lock the outer door and try to walk in
	doors[1].set_locked(true)
	var blocked := await _walk(main.player, outside, inside, doors, 6.0)
	doors[1].set_locked(false)
	print("LOCKED %s  (expect reached=false, end x < 41.4)" % blocked)

	var cycles := []
	for d: DoorController in doors:
		d.cycle_started.connect(func(id: int, s: float) -> void: cycles.append([id, snappedf(s, 0.01)]))
	# let the outer door's partner (inner) count its shut time from now, as in play
	await _frames(200)
	var into := await _walk(main.player, outside, inside, doors, 25.0)
	print("IN   %s cycles=%s" % [into, cycles])
	cycles.clear()
	var back := await _walk(main.player, inside, outside, doors, 25.0)
	print("OUT  %s cycles=%s" % [back, cycles])

	# 2. standing still in the chamber between the doors: neither holds the other shut, never both open
	main.player.teleport(Vector3(42.3, 0.1, 27.0), 0.0)
	var both := 0
	for f in 360:
		await physics_frame
		if doors[0].open_amount > 0.0 and doors[1].open_amount > 0.0:
			both += 1
	print("CHAMBER inner=%.2f outer=%.2f frames_both_open=%d" % [doors[0].open_amount, doors[1].open_amount, both])
	var pass_all: bool = (not blocked.reached) and into.reached and back.reached and into.frames_both_open == 0 \
		and back.frames_both_open == 0 and both == 0 and visuals == 4
	print("RESULT %s" % ("PASS" if pass_all else "FAIL"))
	main.services.saves.delete_all()
	quit(0 if pass_all else 1)
