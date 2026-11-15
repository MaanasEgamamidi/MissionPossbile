extends SceneTree
## C01/C02 UI integration uses real host actions and the actual offline NASA bundle.

class QueuedServices:
	extends GameServices
	var queue_requests := false
	var queued_action: StringName = &""
	var queued_target: StringName = &""
	var queued_params := {}
	func request(action: StringName, target: StringName = &"", params := {}) -> ActionResult:
		if queue_requests and action != &"cassette_close":
			queued_action = action
			queued_target = target
			queued_params = params.duplicate(true)
			return ActionResult.pending_answer("queued-cassette")
		return super.request(action, target, params)

var services: QueuedServices
var ui: UiRoot
var _passed := 0
var _total := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
	print(("PASS " if ok else "FAIL ") + label + (": " + detail if not detail.is_empty() else ""))


func _frames(count := 5) -> void:
	for i in count:
		await process_frame


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	var up := event.duplicate() as InputEventKey
	up.pressed = false
	root.push_input(up)


func _at_station(id: String) -> void:
	var station: Dictionary = services.state().stations[id]
	services.report_position(services.local_character().id, CharacterState._v3(station.position), 0.0)


func _open() -> CassettePlayerPanel:
	var panel := StationPanels.for_station(CassetteLibrary.PLAYER_ID, services) as CassettePlayerPanel
	ui.open(panel)
	return panel


func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	services = QueuedServices.new()
	var test_dir := ProjectSettings.globalize_path("res://_test_saves/cassette_ui")
	DirAccess.make_dir_recursive_absolute(test_dir)
	services.saves = SaveService.new(test_dir, "colony", 1)
	root.add_child(services)
	services.start_new_game(12817)
	ui = UiRoot.new()
	root.add_child(ui)
	var settings := GameSettings.new()
	settings.reduce_motion = true
	ui.setup(services, settings)
	await _frames()
	var away := CassettePlayerPanel.new()
	ui.open(away)
	_check("direct instantiation away reveals no content", away.photo.texture == null and away.briefing_text.text.is_empty() and not ui.is_open())
	await _frames()
	_at_station(String(CassetteLibrary.PLAYER_ID))
	var panel := _open()
	await _frames()
	# UI overhaul: the drop-down is now one picture button per tape; a tape that has not been found is greyed out.
	var tiles: Array = panel.tape_buttons.values()
	_check("player lists all six missing locked entries", tiles.size() == 6 and tiles.all(func(tile: Button) -> bool: return tile.disabled and tile.is_visible_in_tree() and tile.icon != null))
	_check("opening library alone reveals no tape content", panel.photo.texture == null and panel.briefing_text.text.is_empty())
	panel.select_tape("cassette_med_bay")
	_check("uncollected direct selection fails closed", not ui.is_open() and panel.photo.texture == null and panel.briefing_text.text.is_empty())
	await _frames()
	var inventory := InventoryPanel.new()
	ui.open(inventory)
	await _frames()
	_check("inventory exposes six metadata-only statuses", inventory._cassette_rows.size() == 6 and inventory.find_child("CassettePlaybackLocation", true, false).text == CassetteCatalog.PLAY_INSTRUCTION and inventory._cassette_rows.values().all(func(row: Variant) -> bool: return row is Label))
	for id: String in CassetteCatalog.TAPES:
		_at_station(id)
		var result := services.request(&"cassette_collect", StringName(id))
		_check("real pickup " + id, result.ok, result.message)
	inventory.refresh()
	_check("inventory updates shared pickup state without cargo change", inventory._cassette_rows.values().all(func(row: Label) -> bool: return "Collected" in row.tooltip_text))
	ui.close_all()
	await _frames()
	_at_station(String(CassetteLibrary.PLAYER_ID))
	panel = _open()
	await _frames()
	for entry: Dictionary in CassetteLibrary.metadata():
		panel.select_tape(String(entry.id))
		await _frames()
		_check("offline photo and matching briefing " + String(entry.id), panel.photo.texture != null and panel.selected_cassette == String(entry.id) and not panel.briefing_text.text.is_empty() and not panel.caption.text.is_empty() and not panel.credit.text.is_empty())
		var pages: Array = panel._record.get("pages", [])
		if pages.size() > 1:
			panel.read_page(1)
			await _frames()
			_check("host-authorized page " + String(entry.id), panel.page_index == 1 and services.session.cassette_runtime.readers["1"].page == 1)
	_check("reading never pauses the colony", not services.session.paused)
	var phase := services.clock().phase
	services.session.advance(0.5)
	_check("clock continues while briefing visible", services.clock().phase > phase)
	ui.close_all()
	await _frames()
	for screen: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		for scale: Vector2 in [Vector2(1.0, 1.0), Vector2(1.5, 1.0), Vector2(1.5, 2.0)]:
			root.size = screen
			root.content_scale_factor = scale.y
			UiTheme.apply_text_scale(scale.x)
			UiTheme.set_high_contrast(scale.x > 1.0)
			panel = _open()
			panel.select_tape("cassette_command_center")
			await _frames(10)
			var canvas := root.get_visible_rect().size
			var problems := UiLayoutCheck.problems(panel, canvas)
			_check("layout %s text%s UI%s" % [screen, scale.x, scale.y], problems.is_empty(), " | ".join(problems))
			var rect := panel.get_global_rect()
			_check("world at every edge and corners", rect.position.x > 0.0 and rect.position.y > 0.0 and rect.end.x < canvas.x and rect.end.y < canvas.y)
			_check("photo remains left and preserves aspect", panel.photo.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED and panel.photo.get_global_rect().get_center().x < panel.briefing_text.get_global_rect().get_center().x)
			var photo_column := panel.find_child("PhotoColumn", true, false) as ScrollContainer
			var briefing_column := panel.find_child("BriefingColumn", true, false) as ScrollContainer
			_check("both content panes retain useful visible height", photo_column.size.y >= 80.0 and briefing_column.size.y >= 80.0 and photo_column.size.x >= 150.0 and briefing_column.size.x >= 150.0, str(photo_column.size))
			var contrast_ok := true
			for tile: Button in panel.tape_buttons.values():
				var tile_style := tile.get_theme_stylebox(&"normal") as StyleBoxFlat
				contrast_ok = contrast_ok and not tile.flat and tile_style != null and UiTheme.contrast(tile.get_theme_color(&"font_color"), tile_style.bg_color) >= 4.5
			var playing := panel.tape_buttons["cassette_command_center"] as Button
			_check("tape selector text has readable contrast", contrast_ok and playing.theme_type_variation == UiTheme.PRIMARY_BUTTON and not playing.disabled)
			if scale.y > 1.0:
				for column: ScrollContainer in [photo_column, briefing_column]:
					column.grab_focus()
					_key(KEY_HOME)
					_key(KEY_PAGEDOWN)
					await _frames(2)
					_check("keyboard Page Down scrolls " + String(column.name), column.scroll_vertical > 0)
					_key(KEY_HOME)
					await _frames(2)
					_check("keyboard Home returns " + String(column.name), column.scroll_vertical == 0)
			_check("keyboard focus styles", UiLayoutCheck.focus_problems(panel).is_empty())
			ui.close_all()
			await _frames()
	UiTheme.apply_text_scale(1.0)
	UiTheme.set_high_contrast(false)
	root.content_scale_factor = 1.0
	root.size = Vector2i(1280, 720)
	panel = _open()
	panel.select_tape("cassette_med_bay")
	await _frames()
	services.queue_requests = true
	panel.select_tape("cassette_hangar")
	_check("pending host request clears previous text and photo", panel.pending and panel.photo.texture == null and panel.briefing_text.text.is_empty())
	var stale := services.session.request(services.queued_action, services.queued_target, services.queued_params)
	_at_station("cassette_med_bay")
	stale.request_id = "queued-cassette"
	services.events.action_resolved.emit(stale)
	_check("late approved response after moving away cannot reveal content", not ui.is_open() and panel.photo.texture == null and panel.briefing_text.text.is_empty())
	services.queue_requests = false
	await _frames()
	_at_station(String(CassetteLibrary.PLAYER_ID))
	panel = _open()
	panel.select_tape("cassette_greenhouse")
	await _frames()
	services.events.system_alert.emit(&"critical_test", &"urgent", "Return to safety.")
	await _frames()
	_check("critical warning closes playback and restores cursor", not ui.is_open() and ui.wanted_mouse_mode() == Input.MOUSE_MODE_CAPTURED)
	panel = _open()
	panel.select_tape("cassette_green_dome")
	await _frames()
	services.events.character_recovered.emit(services.local_character().id, {})
	await _frames()
	_check("recovery closes playback", not ui.is_open())
	panel = _open()
	await _frames()
	services.net.host_lost.emit("Lost host")
	await _frames()
	_check("disconnect closes playback", not ui.is_open())
	panel = _open()
	panel.select_tape("cassette_med_bay")
	await _frames()
	services.state().stations.erase(String(CassetteLibrary.PLAYER_ID))
	panel.refresh()
	_check("invalidated station clears content and closes", not ui.is_open() and panel.photo.texture == null and panel.briefing_text.text.is_empty())
	services.saves.delete_all()
	ui.queue_free()
	services.queue_free()
	await _frames()
	UiTheme.release()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)
