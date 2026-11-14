extends SceneTree
## Rendered F05 evidence over the real world. Never reads or writes player save files.
## godot --path . --script res://tools/godot/capture_task_shell.gd

var main: GameMain
var output_dir := ""


func _frames(count := 10) -> void:
	for i in count:
		await process_frame


func _shot(label: String) -> void:
	await _frames(10)
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output_dir.path_join(label + ".png"))
	print("SHOT ", label, " result=", error, " size=", root.size, " canvas=", root.get_visible_rect().size)


func _initialize() -> void:
	output_dir = ProjectSettings.globalize_path("res://docs/revisions/evidence")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var isolated_dir := ProjectSettings.globalize_path("res://_test_saves/capture_task_shell")
	DirAccess.make_dir_recursive_absolute(isolated_dir)
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = isolated_dir
	main.check_weather_updates = false
	root.add_child(main)
	await _frames(30)
	main._on_menu_new()
	await _frames(60)
	# Check physical 720p/1080p plus the hardest supported accessibility combination.
	root.mode = Window.MODE_WINDOWED
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	main.settings.reduce_motion = true
	for screen: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = screen
		for large: bool in [false, true]:
			main.ui.close_all()
			main.settings.text_scale = 1.5 if large else 1.0
			main.settings.ui_scale = 2.0 if large else 1.0
			main.settings.high_contrast = large
			main.settings.apply(self)
			await _frames()
			main.ui.open_task_sample()
			await _shot("task_%d_%s" % [screen.x, "large_high_contrast" if large else "normal"])
			# Scroll to bottom too: at maximum UI scale the shell intentionally scrolls.
			if large:
				var sample := main.ui.top() as TaskSamplePanel
				sample.cancel_button.grab_focus()
				var scroll := sample.find_child("TaskScroll", true, false) as ScrollContainer
				scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
				await _shot("task_%d_large_actions" % screen.x)
	main.ui.close_all()
	main.settings.ui_scale = 1.0
	main.settings.text_scale = 1.0
	main.settings.high_contrast = false
	main.settings.apply(self)
	root.size = Vector2i(1280, 720)
	main.ui.open_task_sample()
	await _frames()
	main.ui.show_critical_alert("Lethal atmosphere: return to safety. Repair task interrupted.", 30.0)
	await _shot("task_critical_alert")
	main.services.saves.delete_all()
	quit(0)
