extends SceneTree
## Screenshots of the scout update in the running game (needs a window).

var main: GameMain
var out_dir := ""


func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame


func _shot(name: String) -> void:
	await _frames(20)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "C:/tmp/shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var save_dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/capture_scout")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir.path_join(f))
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	main.show_menu = false
	main.check_weather_updates = false
	root.add_child(main)
	await _frames(90)
	var player := main.player
	var st := main.services.state()
	var hud := main.mission_hud
	# 1. inside the base: the whole HUD
	player.set_first_person(true)
	await _shot("01_hud_inside")
	# 2. outside by the scout bay, the half-built scout (third person)
	st.character_of_peer(SessionService.HOST_PEER).suit_on = true
	player.set_first_person(false)
	player.teleport(Vector3(14.5, 0.0, 28.5), deg_to_rad(-20.0))
	player.camera_rig().rotation.x = deg_to_rad(-12.0)
	await _shot("02_scout_kit")
	# 3. by a sun tracker: the build chip, then the build drawer
	player.teleport(Vector3(-19.5, 0.0, 3.0), deg_to_rad(0.0))
	await _frames(10)
	hud.refresh()
	await _shot("03_near_tracker")
	hud.open_build()
	await _shot("04_build_drawer")
	main.ui.close_all()
	# 4. the power and life support drawer
	hud.open_power()
	await _shot("05_power_drawer")
	main.ui.close_all()
	hud.open_science()
	await _shot("06_science_panel")
	main.ui.close_all()
	# 5. vitals folded
	hud.vitals.set_compact(true)
	hud._user_compact = true
	await _shot("07_vitals_compact")
	hud.vitals.set_compact(false)
	hud._user_compact = false
	# 6. the scout finished and out near the east plain; the broken-down rover and ore
	st.scout["built"] = true
	ScoutSystem.ensure(st)
	ScoutSystem.send(st, "east_plain", "crew_4")
	st.scout["position"] = [34.0, 0.0, 33.0]
	player.teleport(Vector3(30.0, 0.0, 26.0), deg_to_rad(-150.0))
	player.camera_rig().rotation.x = deg_to_rad(-8.0)
	await _frames(30)
	hud.refresh()
	await _shot("08_scout_out_broken_rover")
	# 7. storm warning from Mission Control
	st.weather["phase"] = "warned"
	st.weather["warning"] = {"starts_at_hours": st.sim_hours + 6.0, "severity": 0.6, "text": "test"}
	main.services.events.system_alert.emit(WeatherSystem.ALERT_ID, &"warn", "Dust warning: test")
	await _shot("09_storm_warning")
	hud.mission_control.dismiss()
	# 8. survey finishes: report with the mast camera picture
	st.scout["position"] = [40.0, 0.0, 40.0]
	st.scout["status"] = "surveying"
	st.scout["survey_left_h"] = 0.02
	st.scout["yaw"] = deg_to_rad(90.0)
	await _frames(240)
	hud.refresh()
	await _shot("10_scout_report")
	# 9. small window
	root.size = Vector2i(1280, 720)
	await _frames(20)
	await _shot("11_hud_1280")
	main.services.saves.delete_all()
	quit(0)
