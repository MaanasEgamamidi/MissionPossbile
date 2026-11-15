extends SceneTree
## F05 integration: native frame, keyboard operation, live sim and safe interruptions.

var _passed := 0
var _total := 0
var services: GameServices
var ui: UiRoot


func _check(label: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
	print(("PASS " if ok else "FAIL ") + label + (": " + detail if not detail.is_empty() else ""))


func _frames(count := 3) -> void:
	for i in count:
		await process_frame


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	var released := event.duplicate() as InputEventKey
	released.pressed = false
	root.push_input(released)


func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	services = GameServices.new()
	var test_dir := ProjectSettings.globalize_path("res://_test_saves/task_panel")
	DirAccess.make_dir_recursive_absolute(test_dir)
	services.saves = SaveService.new(test_dir, "colony", 1)
	root.add_child(services)
	services.start_new_game(481)
	ui = UiRoot.new()
	root.add_child(ui)
	var settings := GameSettings.new()
	settings.reduce_motion = true
	ui.setup(services, settings)
	await _frames()
	for screen: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		for scale_setting: Vector2 in [Vector2(1.0, 1.0), Vector2(1.5, 1.0), Vector2(1.5, 2.0)]:
			var text_scale := scale_setting.x
			root.size = screen
			root.content_scale_factor = scale_setting.y
			UiTheme.apply_text_scale(text_scale)
			UiTheme.set_high_contrast(text_scale > 1.0)
			ui.open_task_sample()
			await _frames(8)
			var panel := ui.top() as TaskSamplePanel
			var canvas := root.get_visible_rect().size
			var issues := UiLayoutCheck.problems(panel, canvas)
			_check("layout %s text %.1f UI %.1f" % [screen, text_scale, scale_setting.y], issues.is_empty(), " | ".join(issues))
			_check("focus styles %s text %.1f UI %.1f" % [screen, text_scale, scale_setting.y], UiLayoutCheck.focus_problems(panel).is_empty())
			_check("world visible around task", panel.get_global_rect().size.x < canvas.x and panel.get_global_rect().size.y < canvas.y)
			ui.close_all()
			await _frames()
	UiTheme.apply_text_scale(1.0)
	UiTheme.set_high_contrast(false)
	root.content_scale_factor = 1.0
	root.size = Vector2i(1280, 720)
	ui.open_task_sample()
	await _frames(8)
	var sample := ui.top() as TaskSamplePanel
	_check("sample frees mouse without pausing", ui.wanted_mouse_mode() == Input.MOUSE_MODE_VISIBLE and not services.session.paused)
	var phase := services.clock().phase
	services.session.advance(0.5)
	_check("authoritative clock advances with sample open", services.clock().phase > phase and not services.session.paused)
	var buttons := UiLayoutCheck.focusable(sample)
	var visited := {}
	buttons[0].grab_focus()
	for i in buttons.size() * 2:
		var focused := root.gui_get_focus_owner()
		if focused != null:
			visited[focused] = true
		_key(KEY_TAB)
	_check("Tab reaches every sample action", buttons.all(func(control: Control) -> bool: return visited.has(control)))
	var activate := sample.play_area.find_child("Activate", true, false) as Button
	activate.grab_focus()
	_key(KEY_ENTER)
	await _frames()
	_check("keyboard activates labeled sample shape", sample.sample_moves == 1 and is_equal_approx(sample.progress_bar.value, 100.0 / 3.0), "moves=%d progress=%s focus=%s" % [sample.sample_moves, sample.progress_bar.value, root.gui_get_focus_owner()])
	sample.set_pending("stale")
	_check("host wait disables puzzle controls but leaves cancel", sample.pending and activate.disabled and not sample.cancel_button.disabled)
	sample.accept_host_result(ActionResult.failure("stale", &"bad_request", "Fault generation changed; refresh and retry."), {"fault_generation": 2, "progress": 0.0})
	_check("stale response recovers and uses host generation", not sample.pending and not activate.disabled and sample.fault_generation == 2 and "retry" in sample.status_label.text)
	_key(KEY_ESCAPE)
	await _frames()
	_check("Esc closes and restores capture", not ui.is_open() and ui.wanted_mouse_mode() == Input.MOUSE_MODE_CAPTURED)
	ui.open_task_sample()
	await _frames()
	services.events.system_alert.emit(&"test_critical", &"urgent", "Lethal atmosphere: return to safety.")
	await _frames()
	_check("critical alert interrupts task and is above frame", not ui.is_open() and ui._critical_banner.visible and ui._critical_banner.get_index() > ui._frame.get_index())
	_check("critical interruption leaves simulation running", not services.session.paused and ui.wanted_mouse_mode() == Input.MOUSE_MODE_CAPTURED)
	ui.open_task_sample()
	await _frames()
	services.events.character_recovered.emit(services.local_character().id, {})
	await _frames()
	_check("recovery closes task and restores capture", not ui.is_open() and ui.wanted_mouse_mode() == Input.MOUSE_MODE_CAPTURED)
	ui.open_task_sample()
	await _frames()
	services.net.host_lost.emit("Connection lost")
	await _frames()
	_check("disconnect closes task", not ui.is_open())
	services.saves.delete_all()
	ui.queue_free()
	services.queue_free()
	await _frames()
	UiTheme.release()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)
