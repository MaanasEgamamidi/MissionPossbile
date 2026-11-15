extends SceneTree
## Screenshots of the menus only: main menu (without and with a save), "Play with friends" (host and join), pause menu,
## the four settings tabs, voice settings, crew and credits. No map is loaded (GameServices + UiRoot, as the UI tests
## do), so it starts in a few seconds. Needs a real window (headless cannot draw):
##   godot --path . --resolution 1920x1080 --script res://tools/godot/capture_menus.gd -- --out <folder>
##       [--size 1280x720] [--text 1.5] [--hc] [--real-pixels] [--only main,friends,pause,settings,voice,crew,credits]
## --real-pixels lays the panels out in the window's own pixels (the UI tests' hardest case) instead of the game's
## stretched 1920x1080 canvas. Saves go to res://_test_saves/capture_menus and are deleted at the end; the player's
## own settings and key file are never read or written.
## Writes <folder>/<WxH>[_tNNN][_hc][_px]_<name>.png and prints UiLayoutCheck's findings for every shot.

const SAVE_DIR := "res://_test_saves/capture_menus"

var out_dir := ""
var prefix := ""
var services: GameServices
var ui: UiRoot
var settings: GameSettings
var only: PackedStringArray = []


func _arg(name: String, def: String) -> String:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == name and i + 1 < a.size():
			return a[i + 1]
	return def


func _flag(name: String) -> bool:
	return OS.get_cmdline_user_args().has(name)


func _frames(count := 3) -> void:
	for i in count:
		await process_frame


func _wants(group: String) -> bool:
	return only.is_empty() or only.has(group)


func _shot(label: String) -> void:
	await _frames(10)
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("%s_%s.png" % [prefix, label])
	var error := root.get_texture().get_image().save_png(path)
	var top := ui.top()
	var issues := PackedStringArray()
	if top != null:
		issues = UiLayoutCheck.problems(top, root.get_visible_rect().size)
		issues.append_array(UiLayoutCheck.focus_problems(top))
	print("SHOT %s result=%d canvas=%s layout: %s" % [label, error, root.get_visible_rect().size, "ok" if issues.is_empty() else " | ".join(issues)])


func _open(panel: UiPanel) -> UiPanel:
	ui.close_all()
	await _frames(2)
	ui.open(panel)
	return panel


func _settings_panel() -> SettingsPanel:
	var p := SettingsPanel.new()
	p.settings = settings
	p.settings_path = ProjectSettings.globalize_path(SAVE_DIR).path_join("settings.json")
	p.input_path = ProjectSettings.globalize_path(SAVE_DIR).path_join("input.json")
	return p


func _initialize() -> void:
	var size_text := _arg("--size", "1920x1080")
	var window_size := Vector2i(int(size_text.get_slice("x", 0)), int(size_text.get_slice("x", 1)))
	# No title bar, top left corner: a 1920x1080 window then really is 1920x1080 on a 1920x1080 screen.
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.position = Vector2i.ZERO
	root.size = window_size
	if _flag("--real-pixels"):
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var text_scale := float(_arg("--text", "1.0"))
	out_dir = _arg("--out", ProjectSettings.globalize_path("res://_test_saves/capture_menus_shots"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	only = _arg("--only", "").split(",", false)
	PlayerInput.ensure_actions()
	prefix = "%dx%d" % [window_size.x, window_size.y]
	if not is_equal_approx(text_scale, 1.0):
		prefix += "_t%d" % roundi(text_scale * 100.0)
	if _flag("--hc"):
		prefix += "_hc"
	if _flag("--real-pixels"):
		prefix += "_px"

	var dir := ProjectSettings.globalize_path(SAVE_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	services = GameServices.new()
	services.saves = SaveService.new(dir, "colony", 1)
	root.add_child(services)
	services.saves.delete_all()
	settings = GameSettings.new()
	settings.reduce_motion = true
	settings.text_scale = text_scale
	settings.high_contrast = _flag("--hc")
	UiTheme.set_high_contrast(settings.high_contrast)
	UiTheme.apply_text_scale(settings.text_scale)
	ui = UiRoot.new()
	root.add_child(ui)
	ui.setup(services, settings)
	await _frames(4)
	root.size = window_size
	await _frames(2)
	print("WINDOW %s canvas %s" % [root.size, root.get_visible_rect().size])

	if _wants("main"):
		await _open(MainMenu.new())
		await _shot("01_main_first_time")
	services.start_new_game(4171)
	services.save_now(&"manual")
	await _frames(2)
	if _wants("main"):
		await _open(MainMenu.new())
		await _shot("02_main_with_save")
	if _wants("friends"):
		var menu := await _open(MainMenu.new()) as MainMenu
		menu.open_host_section()
		await _shot("03_friends_host")
		menu.open_join_section()
		menu.show_notice("Type your friend's address first.")
		await _shot("04_friends_join")
	if _wants("pause"):
		ui.close_all()
		await _frames(2)
		ui.open_pause_menu()
		await _shot("05_pause")
	if _wants("settings"):
		var names := ["display", "controls", "graphics", "audio"]
		for tab in 4:
			var p := await _open(_settings_panel()) as SettingsPanel
			p.tabs().current_tab = tab
			await _shot("0%d_settings_%s" % [6 + tab, names[tab]])
	if _wants("voice"):
		var v := VoiceSettingsPanel.new()
		v.settings = settings
		v.settings_path = ""
		await _open(v)
		await _shot("10_voice")
	if _wants("crew"):
		var st := services.state()
		st.character(&"crew_3").owner_peer = 2
		var crew := await _open(CrewSelectPanel.new())
		await _shot("11_crew")
		if crew.has_method(&"show_details"):
			crew.call(&"show_details", true)
			await _shot("12_crew_details")
		var me := services.local_character()
		me.position += Vector3(40.0, 0.0, 0.0)
		crew.refresh()
		await _shot("13_crew_away_from_hub")
		st.character(&"crew_3").owner_peer = 0
	if _wants("credits"):
		await _open(CreditsPanel.new())
		await _shot("14_credits")

	ui.close_all()
	await _frames(2)
	ui.queue_free()
	services.saves.delete_all()
	services.queue_free()
	await _frames()
	UiTheme.set_high_contrast(false)
	UiTheme.apply_text_scale(1.0)
	UiTheme.release()
	quit(0)
