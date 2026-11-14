extends SceneTree
## C02 rendered review with real host pickup/player requests and isolated saves.
## godot --path . --resolution 1920x1080 --script res://tools/godot/capture_cassette_player.gd

var main: GameMain
var output_dir := ""


func _frames(count := 8) -> void:
	for i in count:
		await process_frame


func _shot(label: String) -> void:
	await _frames()
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output_dir.path_join(label + ".png"))
	print("SHOT ", label, " result=", error)


func _initialize() -> void:
	output_dir = ProjectSettings.globalize_path("res://docs/revisions/evidence/cassettes")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var isolated_dir := ProjectSettings.globalize_path("res://_test_saves/capture_cassettes")
	DirAccess.make_dir_recursive_absolute(isolated_dir)
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = isolated_dir
	main.check_weather_updates = false
	root.add_child(main)
	await _frames(25)
	main.services.saves.delete_all()
	main._on_menu_new()
	await _frames(40)
	var services := main.services
	for id: String in CassetteCatalog.TAPES:
		var station: Dictionary = services.state().stations[id]
		var at := CharacterState._v3(station.position)
		main.player.teleport(at, 0.0)
		services.report_position(services.local_character().id, at, 0.0)
		var result := services.request(&"cassette_collect", StringName(id))
		print("COLLECT ", id, " ok=", result.ok, " ", result.message)
		if OS.get_cmdline_user_args().has("--menu-only") and (services.state().repair.collected_cassettes as Array).size() == 3:
			var deck: Dictionary = services.state().stations[String(CassetteLibrary.PLAYER_ID)]
			var deck_at := CharacterState._v3(deck.position) + Vector3(0.0, 0.0, 0.7)
			main.player.teleport(deck_at, 0.0)
			services.report_position(services.local_character().id, deck_at, 0.0)
			root.mode = Window.MODE_WINDOWED
			root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
			root.size = Vector2i(1280, 720)
			root.gui_embed_subwindows = true
			main.settings.ui_scale = 1.0
			main.settings.text_scale = 1.0
			main.settings.high_contrast = false
			main.settings.apply(self)
			var library := StationPanels.for_station(CassetteLibrary.PLAYER_ID, services) as CassettePlayerPanel
			main.ui.open(library)
			await _frames()
			var menu := library._tapes.get_popup()
			menu.position = Vector2i(library._tapes.get_global_rect().position + Vector2(0.0, library._tapes.size.y))
			menu.popup()
			await _shot("library_collected_and_missing")
			services.saves.delete_all()
			quit(0)
			return
	var player_station: Dictionary = services.state().stations[String(CassetteLibrary.PLAYER_ID)]
	var player_at := CharacterState._v3(player_station.position) + Vector3(0.0, 0.0, 0.7)
	main.player.teleport(player_at, 0.0)
	services.report_position(services.local_character().id, player_at, 0.0)
	await _frames(15)
	root.mode = Window.MODE_WINDOWED
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1920, 1080)
	main.settings.reduce_motion = true
	main.settings.ui_scale = 1.0
	main.settings.text_scale = 1.0
	main.settings.high_contrast = false
	main.settings.apply(self)
	var panel := StationPanels.for_station(CassetteLibrary.PLAYER_ID, services) as CassettePlayerPanel
	main.ui.open(panel)
	for entry: Dictionary in CassetteLibrary.metadata():
		panel.select_tape(String(entry.id))
		await _shot(String(entry.id) + "_1080")
	main.ui.close_all()
	await _frames()
	for screen: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		for large: bool in [false, true]:
			root.size = screen
			main.settings.ui_scale = 2.0 if large else 1.0
			main.settings.text_scale = 1.5 if large else 1.0
			main.settings.high_contrast = large
			main.settings.apply(self)
			panel = StationPanels.for_station(CassetteLibrary.PLAYER_ID, services) as CassettePlayerPanel
			main.ui.open(panel)
			panel.select_tape("cassette_command_center")
			await _shot("player_%d_%s" % [screen.x, "large_high_contrast" if large else "normal"])
			if large:
				panel.read_page(1)
				var scroll := panel.find_child("BriefingColumn", true, false) as ScrollContainer
				scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
				await _shot("player_%d_large_controls" % screen.x)
			main.ui.close_all()
			await _frames()
	main.settings.ui_scale = 1.0
	main.settings.text_scale = 1.0
	main.settings.high_contrast = false
	main.settings.apply(self)
	root.size = Vector2i(1280, 720)
	main.ui.open(InventoryPanel.new())
	await _shot("inventory_metadata_only")
	main.ui.close_all()
	panel = StationPanels.for_station(CassetteLibrary.PLAYER_ID, services) as CassettePlayerPanel
	main.ui.open(panel)
	panel.select_tape("cassette_hangar")
	main.ui.show_critical_alert("Danger: playback interrupted. Return to safety.", 30.0)
	await _shot("playback_critical_interrupt")
	services.saves.delete_all()
	quit(0)
