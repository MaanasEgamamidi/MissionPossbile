extends SceneTree
## S02 visual verification over the real map, with isolated saves and explicit host steps.
## Automatic simulation is disabled only in this capture tool so each resolution gets the same host sample.
## Ordinary runtime and test_survival_hud verify active simulation and authoritative recovery separately.

var main: GameMain
var output_dir := ""
var _forced_danger := false
var _danger_origin := Vector3.ZERO


func _frames(count := 8) -> void:
	for i in count:
		await process_frame


func _shot(label: String) -> void:
	await _frames()
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(output_dir.path_join(label + ".png"))
	print("SHOT ", label, " result=", result, " active=", main.survival_hud.active, " remaining=", main.survival_hud.remaining_seconds)


func _teleport(at: Vector3, yaw := 0.0) -> void:
	main.player.teleport(at, yaw)
	main.services.report_position(main.services.local_character().id, at, yaw)


func _safe() -> void:
	main.ui.close_all()
	_forced_danger = false
	main.services.local_character().suit_on = false
	_teleport(main.services.config.hub_position)
	main.services.session.advance(main.services.config.exposure_safe_recovery_seconds + 0.1)
	main.survival_hud.refresh_from_host()


func _force_danger() -> void:
	_danger_origin = main.services.local_character().position
	_forced_danger = true
	main.services.report_position(main.services.local_character().id, _danger_origin, 0.0)
	main.survival_hud.refresh_from_host()


func _initialize() -> void:
	output_dir = ProjectSettings.globalize_path("res://docs/revisions/evidence/survival_ui")
	if OS.get_cmdline_user_args().has("--compatibility"):
		output_dir += "_compatibility"
	DirAccess.make_dir_recursive_absolute(output_dir)
	var isolated_dir := ProjectSettings.globalize_path("res://_test_saves/capture_survival_ui")
	DirAccess.make_dir_recursive_absolute(isolated_dir)
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = isolated_dir
	main.check_weather_updates = false
	root.add_child(main)
	await _frames(25)
	main.services.saves.delete_all()
	main._on_menu_new()
	await _frames(35)
	main.services.set_process(false)
	var original_outside := main.services.session.outside_test
	main.services.session.outside_test = func(at: Vector3) -> bool:
		return (_forced_danger and at.distance_to(_danger_origin) < 3.0) or bool(original_outside.call(at))
	root.mode = Window.MODE_WINDOWED
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	main.settings.warning_sound_muted = true
	main.settings.reduce_flashes = true
	main.settings.reduce_motion = true
	if OS.get_cmdline_user_args().has("--airlock-only"):
		root.size = Vector2i(1280, 720)
		main.settings.ui_scale = 1.0
		main.settings.text_scale = 1.0
		main.settings.high_contrast = false
		main.settings.apply(self)
		main.services.session.survival.debug_trigger_airlock_fault()
		_teleport(Vector3(22.0, 0.05, 12.5), PI)
		await _shot("airlock_pressure_warning")
		main.services.saves.delete_all()
		quit(0)
		return
	var ground := load("res://data/terrain_height.res") as TerrainHeight
	var exterior := Vector3(14.0, ground.height_at(14.0, 26.0) + 0.05, 26.0)
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		for large: bool in [false, true]:
			_safe()
			root.size = size
			main.settings.ui_scale = 2.0 if large else 1.0
			main.settings.text_scale = 1.5 if large else 1.0
			main.settings.high_contrast = large
			main.settings.apply(self)
			_teleport(exterior, 0.0)
			await _shot("warning_%d_%s" % [size.x, "large_high_contrast" if large else "normal"])
	_safe()
	root.size = Vector2i(1280, 720)
	main.settings.ui_scale = 1.0
	main.settings.text_scale = 1.0
	main.settings.high_contrast = false
	main.settings.apply(self)
	main.services.session.survival.debug_trigger_airlock_fault()
	_teleport(Vector3(22.0, 0.05, 12.5), PI)
	await _shot("airlock_pressure_warning")
	_safe()
	var anchor: Dictionary = main.services.state().stations["repair_t01"]
	_teleport(CharacterState._v3(anchor.position))
	main.services.session.wear_runtime.force_fault(main.services.session, "T01", 0.4)
	var maintenance := StationPanels.for_station(&"repair_t01", main.services) as MaintenanceStationPanel
	main.ui.open(maintenance)
	maintenance._start.pressed.emit()
	await _shot("maintenance_before_warning")
	_force_danger()
	await _shot("maintenance_interrupted_by_warning")
	print("MAINTENANCE_RELEASED ", not bool(main.services.session.wear_runtime.status("T01").active))
	var options := SettingsPanel.new()
	options.settings = main.settings
	options.settings_path = isolated_dir.path_join("settings.json")
	options.input_path = isolated_dir.path_join("input.json")
	main.ui.open(options)
	options.tabs().current_tab = 3
	await _shot("warning_above_audio_settings")
	_safe()
	var tape: Dictionary = main.services.state().stations["cassette_command_center"]
	_teleport(CharacterState._v3(tape.position))
	main.services.request(&"cassette_collect", &"cassette_command_center")
	var deck: Dictionary = main.services.state().stations[String(CassetteLibrary.PLAYER_ID)]
	_teleport(CharacterState._v3(deck.position) + Vector3(0.0, 0.0, 0.7))
	var reader := StationPanels.for_station(CassetteLibrary.PLAYER_ID, main.services) as CassettePlayerPanel
	main.ui.open(reader)
	reader.select_tape("cassette_command_center")
	_force_danger()
	print("CASSETTE_INTERRUPTED ", not main.ui.is_open())
	# Reopen while the host's danger remains active to verify layering over a modal surface.
	reader = StationPanels.for_station(CassetteLibrary.PLAYER_ID, main.services) as CassettePlayerPanel
	main.ui.open(reader)
	reader.select_tape("cassette_command_center")
	await _shot("warning_above_cassette")
	main.services.session.advance(main.services.config.exposure_lethal_seconds + 0.01)
	await _shot("recovery_without_stale_countdown")
	main.services.saves.delete_all()
	quit(0)
