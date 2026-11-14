extends SceneTree
## F06: the imported map, real collision, local walking/aiming, spawn and old-save integration.

var passed := 0
var total := 0
var main: GameMain
var capture_dir := ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="):
			capture_dir = arg.trim_prefix("--captures=")
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.show_menu = false
	main.check_weather_updates = false
	main.save_directory = "res://_test_saves/repair_anchors"
	root.add_child(main)
	await _frames(5)
	main.services.start_new_game(90210)
	main._rebuild_crew()
	await _frames(5)
	var services := main.services
	_check("new game starts in Med Bay", services.zones.zone_at_world(main.player.global_position) == "Med Bay")
	for actor: CharacterState in services.state().characters.values():
		_check("safe parked feet " + String(actor.id), _clear(actor.hub_spot), str(actor.hub_spot))
	_check("switching point reachable from spawn", services.session.is_at_hub(main.player.global_position))
	await _capture("med_bay_spawn")
	var snapshot := services.snapshot()
	var continued := Vector3(29, 0.04, -13)
	snapshot.colony.characters.crew_1.position = [continued.x, continued.y, continued.z]
	snapshot.colony.characters.crew_4.hub_spot = [-7.3, 0, -15.7]
	snapshot.colony.characters.crew_3.position = [22, 0.1, 18]
	snapshot.colony.characters.crew_3.lethal_exposure_seconds = 2.75
	snapshot.colony.characters.crew_3.outside = true
	snapshot.colony.characters.crew_3.health = 43.0
	var entries := StationCatalog.extra_entries().filter(func(entry: Dictionary) -> bool: return entry.has("room_id"))
	for entry: Dictionary in entries: snapshot.colony.stations.erase(String(entry.id))
	services.restore(snapshot)
	_check("continue keeps host position", services.local_character().position == continued)
	_check("continue upgrades old recovery spot", services.state().character(&"crew_4").hub_spot.is_equal_approx(Vector3(-7.6, 0.04, -15.7)), str(services.state().character(&"crew_4").hub_spot))
	var exposed := services.state().character(&"crew_3")
	_check("continue preserves remote exposure encounter", exposed.position == Vector3(22, 0.1, 18) and exposed.outside and exposed.lethal_exposure_seconds == 2.75 and exposed.health == 43.0)
	_check("continue adds all reserved anchors", entries.all(func(entry: Dictionary) -> bool: return services.state().stations.has(String(entry.id))))
	main._rebuild_crew()
	await _frames(3)
	_check("nineteen new locations", entries.size() == 19, str(entries.size()))
	var captured := {}
	var tape_ids := {}
	var task_count := 0
	for entry: Dictionary in entries:
		var id := String(entry.id)
		var record: Dictionary = services.state().stations[id]
		var at := CharacterState._v3(record.position)
		_check("capsule clear " + id, _clear(at), str(at))
		var allowed: Array = RepairCatalog.ROOMS[String(entry.room_id)].zones
		_check("correct zone " + id, allowed.has(services.zones.zone_at_world(at)), services.zones.zone_at_world(at))
		if entry.kind == "repair_task":
			task_count += 1
			_check("stable task anchor " + id, RepairCatalog.anchor_id(String(entry.task_id)) == id)
		elif entry.kind == "cassette_anchor": tape_ids[String(entry.cassette_id)] = true
		var approached := false
		for direction: Vector3 in [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT]:
			var start := at + direction * 1.1
			if not _clear(start): continue
			var yaw := atan2(direction.x, direction.z)
			main.player.teleport(start, yaw)
			await _frames(2)
			var before := main.player.global_position
			Input.action_press("move_forward")
			await _frames(10)
			Input.action_release("move_forward")
			await _frames(3)
			var to_target := at + Vector3.UP - main.player.camera_rig().global_position
			main.player.camera_rig().add_look(atan2(-to_target.x, -to_target.z) - main.player.camera_rig().yaw(), 0)
			main.player.camera_rig().rotation.x = atan2(to_target.y, Vector2(to_target.x, to_target.z).length())
			await _frames(1)
			if main.player.aimed_target().id != StringName(id): continue
			approached = main.player.global_position.distance_to(before) > 0.05
			if approached: break
		_check("walk and aim " + id, approached, str(main.player.aimed_target()))
		var panel := StationPanels.for_station(StringName(id), services)
		_check("reserved station opens " + id, panel != null and panel.panel_title() == String(entry.name))
		if panel != null: panel.free()
		if not captured.has(entry.room_id):
			captured[entry.room_id] = true
			await _capture(String(entry.room_id))
	_check("twelve task anchors and six distinct tapes", task_count == 12 and tape_ids.size() == 6)
	_check("greenhouse and dome cassette distinct", tape_ids.has("cassette_greenhouse") and tape_ids.has("cassette_green_dome"))
	_check("player only in Command Room", (services.state().stations["cassette_player_command_center"] as Dictionary).zone == "Command Room")
	services.saves.delete_all()
	main.queue_free()
	await process_frame
	print("RESULT %d/%d" % [passed, total])
	quit(0 if passed == total else 1)

func _clear(at: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.23
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform.origin = at + Vector3.UP * 0.9
	query.collision_mask = Layers.WORLD | Layers.DOOR
	return root.get_world_3d().direct_space_state.intersect_shape(query).is_empty()

func _frames(count: int) -> void:
	for i in count: await physics_frame

func _capture(label: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png"))

func _check(label: String, ok: bool, detail := "") -> void:
	total += 1
	if ok: passed += 1
	print("PASS " if ok else "FAIL ", label, " ", detail)
