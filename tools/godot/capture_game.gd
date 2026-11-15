extends SceneTree
## Runs the real game scene with the full map for a few seconds and saves evidence screenshots.
## Needs a window (no --headless). Saves go to a folder inside the project, not user://.
## Run: godot --path . --resolution 1920x1080 --script res://tools/godot/capture_game.gd -- --out <folder>
## HUD shots only (UI overhaul): add `--hud` and, to pick the window size, `--size 1280x720` (default 1920x1080):
##   godot --path . --script res://tools/godot/capture_game.gd -- --hud --size 1280x720 --out <folder>
## It saves hud_calm, hud_busy, hud_low, hud_scout_card and hud_large_contrast (text x1.5, high contrast) as
## <name>_<width>.png: the HUD with nothing going on, with everything going on, and with supplies and vitals low.

var out_dir := ""
var main: GameMain


func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("SHOT %s  fps=%d  draw_calls=%d" % [name, int(Engine.get_frames_per_second()), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = ProjectSettings.globalize_path("res://").path_join("_test_saves/capture")
	for i in args.size():
		if args[i] == "--out":
			out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var save_dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/capture_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir.path_join(f))

	if args.has("--hud"):
		var size := Vector2i(1920, 1080)
		for i in args.size():
			if args[i] == "--size" and i + 1 < args.size():
				var wh := args[i + 1].split("x")
				size = Vector2i(int(wh[0]), int(wh[1]))
		await _hud_shots(save_dir, size)
		return

	var t0 := Time.get_ticks_msec()
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	root.add_child(main)
	await _frames(90)
	print("LOADED in %.1f s; door visuals attached: %d of 52; world=%s" % [(Time.get_ticks_msec() - t0) / 1000.0, main.door_visuals_attached, main.world != null])
	var player := main.player
	var st := main.services.state()
	var me := st.character_of_peer(1)
	print("player at %s zone=%s on_floor=%s first_person=%s" % [player.global_position, main.services.zones.zone_at_world(player.global_position), player.is_on_floor(), player.is_first_person()])

	# 1. first person at the hub, looking at the parked crew
	var crew2 := st.character(&"crew_2")
	var to := crew2.position - player.global_position
	player.teleport(player.global_position, atan2(-to.x, -to.z))
	await _frames(20)
	await _shot("01_first_person_hub")

	# 2. first person looking down: own arms, torso, legs, boots; no head in the way
	player.camera_rig().add_look(0.0, -1.1)
	await _frames(10)
	await _shot("02_first_person_look_down")
	player.camera_rig().add_look(0.0, 1.1)

	# 3. third person
	player.set_first_person(false)
	await _frames(30)
	await _shot("03_third_person_hub")

	# 4. third person with the suit on, carrying a crate
	me.suit_on = true
	var crate := main._item_nodes["crate_1"] as CarryItem
	player.teleport(crate.global_position + Vector3(0.9, 0.0, 0.0), PI * 0.5)
	await _frames(20)
	main._submit(&"pick_up", &"crate_1", {})
	await _frames(30)
	await _shot("04_third_person_suit_carry")
	main._submit(&"drop", &"crate_1", {})

	# 5. a door opening in front of the player (first person)
	player.set_first_person(true)
	var best: DoorController = null
	for d in main.collision.get_node("Doors").get_children():
		var door := d as DoorController
		var c := (door.get_node("Sense") as Node3D).global_position
		if best == null or c.distance_to(player.global_position) < (best.get_node("Sense") as Node3D).global_position.distance_to(player.global_position):
			best = door
	var centre := (best.get_node("Sense") as Node3D).global_position
	var leaf: Node3D = null
	for c in best.get_children():
		if c is AnimatableBody3D:
			leaf = c
			break
	var normal := leaf.global_basis.z
	normal.y = 0.0
	normal = normal.normalized()
	var from := Vector3(centre.x, 0.05, centre.z) + normal * 3.2
	player.teleport(from, atan2(normal.x, normal.z))
	await _frames(8)
	await _shot("05_door_closed_from_3m")
	player.teleport(Vector3(centre.x, 0.05, centre.z) + normal * 1.8, atan2(normal.x, normal.z))
	await _frames(60)
	print("door %d open=%s" % [best.door_id, best.is_open()])
	await _shot("06_door_open")

	# 6. power panel menu
	var panel: Dictionary = st.stations["pw_panel"]
	player.teleport(Vector3(float(panel.position[0]), 0.05, float(panel.position[2])) + Vector3(0.0, 0.0, 1.4), 0.0)
	await _frames(20)
	main._submit(&"use_station", &"pw_panel", {})
	await _frames(10)
	await _shot("07_power_panel")
	main.services.session.request(&"set_zone_power", &"pw_panel", {"zone": "Power Room", "on": false})
	main.hud.close_menu()
	main._set_menu_mode(false)
	await _frames(40)
	await _shot("08_power_room_switched_off")
	main.services.session.request(&"set_zone_power", &"pw_panel", {"zone": "Power Room", "on": true})

	# 7. outdoors in the suit, third person
	player.set_first_person(false)
	player.teleport(Vector3(-18.0, 0.3, 33.0), 0.79)
	await _frames(60)
	await _shot("09_outdoors_third_person")

	main.services.saves.delete_all()
	quit(0)


# ---------------------------------------------------------------- HUD shots (UI overhaul)

## The in-game HUD in its main states, over the real map. `size` is the window size in pixels.
func _hud_shots(save_dir: String, size: Vector2i) -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = size
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	main.show_menu = false
	main.check_weather_updates = false
	root.add_child(main)
	await _frames(90)
	root.size = size
	var tag := "_%d" % size.x
	var player := main.player
	var st := main.services.state()
	var me := st.character_of_peer(SessionService.HOST_PEER)
	var mh := main.mission_hud
	main.settings.reduce_motion = true          # no fades: every shot shows the settled HUD
	main.settings.apply(self)

	# 1. nothing going on: inside the base, third person
	player.set_first_person(false)
	await _frames(40)
	await _shot("hud_calm" + tag)

	# 2. everything going on: outside by the broken-down rover, the scout out, a storm warned, pop-ups, an [E] prompt
	me.suit_on = true
	st.scout["built"] = true
	ScoutSystem.ensure(st)
	ScoutSystem.send(st, "east_plain", "crew_4")
	st.scout["position"] = [34.0, 0.0, 33.0]
	player.teleport(Vector3(30.0, 0.0, 26.0), deg_to_rad(-150.0))
	player.camera_rig().rotation.x = deg_to_rad(-8.0)
	await _frames(30)
	st.weather["phase"] = "warned"
	st.weather["warning"] = {"starts_at_hours": st.sim_hours + 6.0, "severity": 0.6, "text": "test"}
	main.services.events.system_alert.emit(&"capture_cleaner", &"warn",
		"Panel cleaner is broken. Dust stays on the panels, so they make less power. An electrical specialist can repair it at a sun tracker.")
	main.services.events.system_alert.emit(WeatherSystem.ALERT_ID, &"warn", "Dust warning: test")
	main.services.events.system_alert.emit(&"capture_info", &"good", "New scout report: the east plain.")
	await _frames(20)
	mh.refresh()
	main.set_process(false)                     # keep the prompt: game_main sets the target every frame
	main.hud.set_target({"kind": "station", "id": &"pw_panel", "node": null})
	await _shot("hud_busy" + tag)
	main.set_process(true)

	# 3. the scout's report (Mission Control) with the mast camera's picture
	mh.mission_control.dismiss()
	st.scout["position"] = [40.0, 0.0, 40.0]
	st.scout["status"] = "surveying"
	st.scout["survey_left_h"] = 0.02
	st.scout["yaw"] = deg_to_rad(90.0)
	await _frames(240)
	mh.refresh()
	await _shot("hud_scout_card" + tag)
	mh.mission_control.dismiss()

	# 4. supplies and vitals low, something in the hands
	main.services.set_process(false)            # no simulation ticks: the low values stay as set
	st.weather["phase"] = "calm"
	st.weather.erase("warning")
	st.stores[&"battery_kwh"] = float(st.capacities[&"battery_kwh"]) * 0.12
	st.stores[&"oxygen_kg"] = 1.0
	st.stores[&"water_l"] = float(st.capacities[&"water_l"]) * 0.9
	st.battery_kw = -4.2
	me.health = 24.0
	me.stamina = 18.0
	me.suit_charge = 8.0
	main.set_process(false)
	main.hud.set_target({"kind": "item", "id": &"crate_1", "node": null})
	main.hud.set_held(&"crate_1")
	main.hud.refresh()
	mh.refresh()
	await _frames(20)
	await _shot("hud_low" + tag)

	# 5. the same with large text and high contrast
	main.settings.text_scale = 1.5
	main.settings.high_contrast = true
	main.settings.apply(self)
	main.hud.refresh()
	mh.refresh()
	await _frames(20)
	await _shot("hud_large_contrast" + tag)

	main.services.saves.delete_all()
	quit(0)
