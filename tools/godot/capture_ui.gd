extends SceneTree
## Screenshots of the game's screens (Prompts 05 and 07) in the real game window with the map loaded.
## Saves go to a folder inside the project, never to the player's own save.
## Run: godot --path . --resolution 1920x1080 --script res://tools/godot/capture_ui.gd -- --out <folder>

var out_dir := ""
var main: GameMain


func _frames(n: int) -> void:
	var target := Engine.get_process_frames() + n
	while Engine.get_process_frames() < target:
		await process_frame


func _shot(name: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("SHOT ", name)


func _panel(name: String, panel: UiPanel) -> void:
	main.ui.close_all()
	await _frames(2)
	main.ui.open(panel)
	await _shot(name)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = ProjectSettings.globalize_path("res://").path_join("_test_saves/capture_ui")
	for i in args.size():
		if args[i] == "--out":
			out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var save_dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/capture_ui_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir.path_join(f))
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	root.add_child(main)
	await _frames(30)
	await _shot("01_main_menu")
	main._on_menu_new()
	await _frames(90)
	var s := main.services
	var me := s.local_character()
	main.player.teleport(me.position, me.yaw)
	await _frames(30)
	await _shot("02_hud_first_person")
	await _panel("03_colony_summary", ColonySummaryPanel.new())
	await _panel("04_power_panel", StationPanels.for_station(&"pw_panel", s))
	await _panel("05_life_support", StationPanels.for_station(&"ls_console", s))
	await _panel("06_solar_tracker", StationPanels.for_station(&"sf_solar_tracker", s))
	await _panel("07_suit_rack", StationPanels.for_station(&"al_suit_rack", s))
	await _panel("08_crew", CrewSelectPanel.new())
	await _panel("09_cargo", InventoryPanel.new())
	await _panel("10_blueprint", BlueprintPanel.new())
	await _panel("11_upgrades", UpgradeCardsPanel.new())
	await _panel("12_sources", SourceRegisterPanel.new())
	await _panel("13_settings", SettingsPanel.new())
	main.ui.close_all()
	main.ui.open_pause_menu()
	await _shot("14_pause_menu")
	main.ui.close_all()
	await _frames(10)
	print("STATIONS ", s.state().stations.size(), " ALERTS ", s.state().alerts.size())
	s.saves.delete_all()
	quit(0)
