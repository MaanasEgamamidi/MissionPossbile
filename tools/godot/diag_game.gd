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
	var report := {"stations": [], "doors": []}
	# ---- stations: stand 1.3 m away in 8 directions, look at chest height
	for st: Node in main.collision.get_node("Stations").get_children():
		var c := (st as Node3D).global_position
		var row := {"id": String(st.name), "kind": String(st.get_meta("kind")), "pos": [c.x, c.y, c.z], "hits": []}
		for k in 8:
			var a := k * TAU / 8.0
			var at := c + Vector3(sin(a), 0, cos(a)) * 1.3
			var yaw := atan2(at.x - c.x, at.z - c.z)  # face the station: forward is -Z
			player.teleport(at + Vector3.UP * 0.05, yaw)
			await _frames(3)
			var rig := player.camera_rig()
			var eye := player.global_position + Vector3.UP * 1.65
			var aim := c + Vector3.UP * 0.1
			rig.rotation.x = atan2(aim.y - eye.y, Vector2(aim.x - eye.x, aim.z - eye.z).length())
			await _frames(2)
			var t := player.aimed_target()
			var cam := rig.camera()
			var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 4.0, Layers.WORLD | Layers.DOOR | Layers.ITEM | Layers.STATION)
			q.exclude = [player.get_rid()]
			q.collide_with_areas = true
			var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
			var hit_name := ""
			if not hit.is_empty():
				hit_name = String((hit.collider as Node).name)
				if hit.has("shape") and hit.collider is CollisionObject3D:
					var owner_id: int = (hit.collider as CollisionObject3D).shape_find_owner(int(hit.shape))
					var sh := (hit.collider as CollisionObject3D).shape_owner_get_owner(owner_id)
					if sh != null:
						hit_name += "/" + String(sh.name)
			row.hits.append({"dir": k, "player": [player.global_position.x, player.global_position.z], "target": String(t.id), "ray_hit": hit_name})
		report.stations.append(row)
	# ---- doors: start 1.6 m on one side, walk through for 4 s, check the other side is reached
	player.set_first_person(true)
	for door: Node in main.collision.get_node("Doors").get_children() + (main.collision.get_node("EnvironmentDoors").get_children() if main.collision.has_node("EnvironmentDoors") else []):
		var dc := door as DoorController
		var leaves := dc.get_children().filter(func(n: Node) -> bool: return n is AnimatableBody3D)
		if leaves.is_empty():
			continue
		var centre := Vector3.ZERO
		for l: Node in leaves:
			centre += (l as Node3D).global_position
		centre /= leaves.size()
		var normal := (leaves[0] as Node3D).global_basis.z
		normal.y = 0
		normal = normal.normalized()
		for side: float in [1.0, -1.0]:
			var start := centre + normal * 1.6 * side
			var goal := centre - normal * 1.6 * side
			player.teleport(start + Vector3.UP * 0.1, atan2(-(goal - start).x, -(goal - start).z))
			player.camera_rig().rotation.x = 0
			await _frames(5)
			Input.action_press(&"move_forward")
			var best := 99.0
			var max_open := 0.0
			for f in 240:
				await physics_frame
				best = minf(best, Vector2(player.global_position.x - goal.x, player.global_position.z - goal.z).length())
				max_open = maxf(max_open, dc.open_amount)
			Input.action_release(&"move_forward")
			await _frames(5)
			report.doors.append({"door": dc.door_id, "side": side, "centre": [centre.x, centre.z], "reached": best < 0.6, "closest_m": snappedf(best, 0.01), "max_open": snappedf(max_open, 0.01), "end": [snappedf(player.global_position.x, 0.01), snappedf(player.global_position.z, 0.01)]})
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	f.close()
	main.services.saves.delete_all()
	print("done -> " + out)
	quit(0)


