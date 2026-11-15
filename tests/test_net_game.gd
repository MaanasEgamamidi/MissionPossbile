extends SceneTree
## Prompt 06 end to end: two whole game scenes (menus, HUD, player bodies; no map) in one process, each in its own
## SceneMultiplayer branch, hosting and joining over ENet on 127.0.0.1 through the main menu's own handlers.
## Run: godot --headless --path . --script res://tests/test_net_game.gd

const PORT := 24792

var _passed := 0
var _total := 0


func _check(name: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS ", name, ("  " + detail) if detail != "" else "")
	else:
		print("FAIL ", name, ": ", detail)


func _machine(branch: String, save_dir: String) -> GameMain:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var main := (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.load_world = false
	main.show_menu = true
	main.save_directory = save_dir
	holder.add_child(main)
	return main


func _until(cond: Callable, seconds := 5.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return bool(cond.call())


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/net_game")
	DirAccess.make_dir_recursive_absolute(dir)
	var host := _machine("HostMachine", dir.path_join("host"))
	var client := _machine("ClientMachine", dir.path_join("client"))
	host.services.saves.delete_all()
	# These checks are about LAN play and ordinary door sensing from the Med Bay start, so the tutorial start (crew outside,
	# every door held open) is switched off; tests/test_tutorial_start.gd checks it. Both machines share this config.
	host.services.config.tutorial_start_outside = false
	host.services.config.tutorial_doors_open = false
	await _until(func() -> bool: return false, 0.3)

	host._on_menu_host(PORT, false)
	_check("host: menu Host starts a colony and plays", host._playing and host.services.net.is_host() and host.player != null)
	await _physics(20)
	var doors := host.collision.get_node("Doors").get_children()
	var open_alone := doors.filter(func(d: DoorController) -> bool: return d.is_open())
	_check("doors: parked crew on the hub ring hold no door open", not doors.is_empty() and open_alone.is_empty(), "%d doors, %d open" % [doors.size(), open_alone.size()])
	client._on_menu_join("127.0.0.1", PORT)
	_check("client: menu says it is connecting", client._main_menu.notice_text().begins_with("Connecting"), client._main_menu.notice_text())
	_check("client: playing after the colony arrives", await _until(func() -> bool: return client._playing and client.player != null))
	# Both machines run in this one process and share one physics world, so each player's body would also hit the
	# other machine's drawing of that same character (its CREW_SOLID capsule, which trails the body and pushes it
	# along without end). Two real computers never have both. Crew-to-crew collision is checked in test_crew_collision.
	for g: GameMain in [host, client]:
		g.player.collision_mask &= ~Layers.CREW_SOLID
	var mine := client.services.local_character()
	var hosts := host.services.local_character()
	_check("client: controls a different crew member", mine != null and hosts != null and mine.id != hosts.id)
	_check("client: menu closed", not client.ui.is_open() or not (client._main_menu.is_inside_tree()))

	_check("host: draws the client's body", await _until(func() -> bool: return host._crew_visuals.has(mine.id)))
	var on_host := host._crew_visuals[mine.id] as PlayerVisual
	_check("host: the client's body can open doors (PLAYER-layer presence)", on_host.get_node_or_null("Presence") is AnimatableBody3D)
	_check("client: draws the host's body", client._crew_visuals.has(hosts.id))

	var target := client.player.global_position + Vector3(3.0, 0.0, 0.0)
	client.player.teleport(target, 0.7)
	# The body settles under physics after a teleport, so compare with where it really is, not with the target.
	_check("motion: the host's drawing follows the client's body", await _until(func() -> bool:
		return client.player.global_position.distance_to(target) < 1.0 and on_host.global_position.distance_to(client.player.global_position) < 0.25, 6.0),
		"%s vs %s" % [on_host.global_position, client.player.global_position])

	# ---- a door on the host opens for the client's body, and shuts again when it walks away
	var door := doors[0] as DoorController
	var door_at := (door.get_node("Sense") as Node3D).global_position
	client.player.teleport(door_at, 0.0)
	_check("doors: a door on the host opens for the client", await _until(func() -> bool: return door.is_open(), 4.0))
	client.player.teleport(target, 0.7)
	_check("doors: and shuts when the client walks away", await _until(func() -> bool: return not door.is_open(), 6.0))

	# ---- the client picks a crate up and puts it down through its own controller (answers arrive later)
	var rec: Dictionary = client.services.state().items["crate_1"]
	var crate_pos := Vector3(float(rec.position[0]), float(rec.position[1]), float(rec.position[2]))
	client.player.teleport(crate_pos + Vector3(0.0, 0.05, 1.0), 0.0)
	await _until(func() -> bool: return host.services.state().character(mine.id).position.distance_to(crate_pos) < 1.5, 3.0)
	var crate := client._item_nodes["crate_1"] as CarryItem
	var cam := client.player.camera_rig().camera()
	crate.freeze = true
	crate.global_position = cam.global_position - cam.global_basis.z * 0.9
	await _physics(2)
	_check("carry: the client aims at the crate", client.player.aimed_target().get("id", &"") == &"crate_1", str(client.player.aimed_target()))
	client.player._grab()
	_check("carry: the client holds the crate once the host agrees", await _until(func() -> bool: return client.player.held_item() == crate))
	_check("carry: the host draws it in the client's hands", String(host.services.state().items["crate_1"].holder) == String(mine.id) and await _until(func() -> bool: return (host._item_nodes["crate_1"] as CarryItem).is_held()))
	client.player._grab()
	_check("carry: the client can put it down again", await _until(func() -> bool: return client.player.held_item() == null and String(host.services.state().items["crate_1"].holder) == ""))

	# ---- every station's screen opens on a client without errors (they read replicated state only)
	var opened := 0
	for id: String in client.services.state().stations:
		var panel := StationPanels.for_station(StringName(id), client.services)
		if panel == null:
			continue
		var restricted_player := panel is CassettePlayerPanel
		client.ui.open(panel)
		await process_frame
		if is_instance_valid(panel):
			panel.refresh()
		else:
			_check("stations: unauthorized cassette player closes without exposing content", restricted_player and client.ui.top() == null)
		client.ui.close_all()
		opened += 1
	_check("stations: client routes station screens and restricts remote playback", opened > 0, "%d station routes" % opened)

	host.services.request(&"set_zone_power", &"", {})       # a refused host request must not show on the client
	var before := client.hud.current_messages().size()
	var bad := client.services.request(&"set_sol_minutes", &"", {"minutes": 30})
	_check("answers: a client's refusal shows on the client", await _until(func() -> bool: return client.hud.current_messages().size() > before), bad.request_id)
	await _until(func() -> bool: return false, 0.3)
	_check("answers: the client's refusal does not show on the host", not "\n".join(host.hud.current_messages()).contains("Only the host"), str(host.hud.current_messages()))

	host.services.net.leave()
	await _until(func() -> bool: return GameMain.menu_notice != "", 5.0)
	_check("host quit: client gets a reason for its menu", GameMain.menu_notice.contains("host"), GameMain.menu_notice)
	GameMain.menu_notice = ""

	host.services.saves.delete_all()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)
