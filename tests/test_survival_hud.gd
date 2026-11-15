extends SceneTree
## S02: real authoritative exposure facts, local-peer warning isolation and accessible UI.

class PerspectiveServices:
	extends GameServices
	var viewing_peer := 1
	func local_peer() -> int:
		return viewing_peer

var services: PerspectiveServices
var ui: UiRoot
var warning: SurvivalHud
var settings: GameSettings
var _forced_outside := false
var _danger_origin := Vector3.ZERO
var _passed := 0
var _total := 0
var _test_dir := ""


func _check(label: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
	print(("PASS " if ok else "FAIL ") + label + (": " + detail if not detail.is_empty() else ""))


func _frames(count := 5) -> void:
	for i in count:
		await process_frame


func _danger() -> void:
	_forced_outside = true
	var actor := services.local_character()
	_danger_origin = actor.position
	services.report_position(actor.id, actor.position, actor.yaw)
	warning.refresh_from_host()


func _safe() -> void:
	_forced_outside = false
	var actor := services.local_character()
	actor.suit_on = false
	services.report_position(actor.id, services.config.hub_position, 0.0)
	services.session.advance(services.config.exposure_safe_recovery_seconds + 0.1)
	warning.refresh_from_host()


func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	_test_dir = ProjectSettings.globalize_path("res://_test_saves/survival_hud")
	DirAccess.make_dir_recursive_absolute(_test_dir)
	services = PerspectiveServices.new()
	services.saves = SaveService.new(_test_dir, "colony", 1)
	root.add_child(services)
	services.set_process(false)
	services.start_new_game(2302)
	services.session.outside_test = func(position: Vector3) -> bool: return _forced_outside and position.distance_to(_danger_origin) < 3.0
	settings = GameSettings.new()
	settings.reduce_motion = true
	ui = UiRoot.new()
	root.add_child(ui)
	ui.setup(services, settings)
	warning = SurvivalHud.new()
	root.add_child(warning)
	warning.setup(services, settings, ui)
	await _frames()
	_check("safe start has no danger overlay", not warning.active and not warning.screen.visible)
	_check("static warning is the default", settings.reduce_flashes)
	var audio_options := SettingsPanel.new()
	audio_options.settings = settings
	audio_options.settings_path = _test_dir.path_join("settings_panel.json")
	audio_options.input_path = _test_dir.path_join("input_panel.json")
	ui.open(audio_options)
	audio_options.tabs().current_tab = 3
	await _frames()
	audio_options._warning_muted.button_pressed = true
	audio_options._warning_volume.value = 0.25
	_check("Audio tab controls actual warning preferences", settings.warning_sound_muted and is_equal_approx(settings.warning_sound_volume, 0.25))
	_check("Audio settings fit 720p and remain keyboard reachable", UiLayoutCheck.problems(audio_options, Vector2(1280, 720)).is_empty() and UiLayoutCheck.focus_problems(audio_options).is_empty())
	ui.close_all()
	await _frames()
	settings.warning_sound_muted = false
	settings.warning_sound_volume = 0.65
	var master := AudioServer.get_bus_index(&"Master")
	var old_master_muted := AudioServer.is_bus_mute(master)
	AudioServer.set_bus_mute(master, false)
	ui.open_task_sample()
	await _frames()
	_danger()
	_check("host entry immediately warns above task layer", warning.active and warning.screen.visible and warning.layer > ui.layer and not ui.is_open())
	_check("cause symbol countdown and escape action are labeled", warning.cause_label.text.begins_with("!") and "NO BREATHABLE AIR" in warning.cause_label.text and "RECOVERY" in warning.countdown_label.text and "safe air" in warning.action_label.text)
	_check("entry emits one brief nonvoice alarm", warning.alarm_count == 1 and warning.alarm.stream is AudioStreamWAV and (warning.alarm.stream as AudioStreamWAV).get_length() < 0.5)
	services.events.state_changed.emit(&"unrelated")
	warning.refresh_from_host()
	_check("ordinary host updates do not repeat alarm", warning.alarm_count == 1)
	var overlay_settings := SettingsPanel.new()
	overlay_settings.settings = settings
	overlay_settings.settings_path = _test_dir.path_join("overlay_settings.json")
	overlay_settings.input_path = _test_dir.path_join("overlay_input.json")
	ui.open(overlay_settings)
	_check("warning remains above local menus without pausing", warning.active and warning.layer > ui.layer and ui.is_open() and not services.session.paused)
	services.request(&"vote_pause", &"", {"paused": true})
	var paused_display := warning.remaining_seconds
	services.session.advance(0.5)
	await _frames()
	_check("actual global pause also freezes presentation countdown", is_equal_approx(paused_display, warning.remaining_seconds))
	services.request(&"vote_pause", &"", {"paused": false})
	ui.close_all()
	var health := services.local_character().health
	await _frames()
	_check("smooth display does not decide death", services.local_character().health == health and warning.remaining_seconds >= 0.0)
	var empty_settings := GameSettings.new()
	empty_settings.warning_sound_volume = 4.0
	_check("warning volume clamps to valid range", empty_settings.warning_sound_volume == 1.0)
	settings.warning_sound_muted = true
	settings.warning_sound_volume = 0.35
	settings.reduce_flashes = true
	var settings_file := _test_dir.path_join("warning_settings.json")
	settings.save(settings_file)
	var restored := GameSettings.load_or_default(settings_file)
	_check("mute volume static preference survive settings save", restored.warning_sound_muted and is_equal_approx(restored.warning_sound_volume, 0.35) and restored.reduce_flashes)
	_safe()
	_check("host-validated safe air clears warning", not warning.active)
	_danger()
	_check("silent audio still has fatal warning", warning.active and warning.alarm_count == 1 and not warning.alarm.playing)
	_safe()
	settings.warning_sound_muted = false
	settings.warning_sound_volume = 0.0
	_danger()
	_check("zero warning volume is silent", warning.active and warning.alarm_count == 1)
	_safe()
	settings.warning_sound_volume = 0.65
	AudioServer.set_bus_mute(master, true)
	_danger()
	_check("Master bus mute is respected", warning.active and warning.alarm_count == 1)
	AudioServer.set_bus_mute(master, false)
	_safe()
	settings.warning_sound_muted = true
	_danger()
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		for scale: Vector2 in [Vector2(1.0, 1.0), Vector2(1.5, 1.0), Vector2(1.5, 2.0)]:
			root.size = resolution
			root.content_scale_factor = scale.y
			settings.text_scale = scale.x
			settings.high_contrast = scale.x > 1.0
			UiTheme.apply_text_scale(scale.x)
			UiTheme.set_high_contrast(settings.high_contrast)
			await _frames(10)
			var canvas := root.get_visible_rect().size
			var problems := UiLayoutCheck.problems(warning.screen, canvas)
			_check("warning layout %s text%s UI%s" % [resolution, scale.x, scale.y], problems.is_empty(), " | ".join(problems))
			_check("banner leaves central escape route and bottom controls clear", warning.banner.get_global_rect().end.y < canvas.y * 0.5, str(warning.banner.get_global_rect()))
			_check("warning text has strong contrast", UiTheme.contrast(warning.cause_label.get_theme_color(&"font_color"), warning._banner_style.bg_color) >= 4.5)
			_check("overlay cannot intercept escape mouse input", warning.screen.mouse_filter == Control.MOUSE_FILTER_IGNORE and warning.banner.mouse_filter == Control.MOUSE_FILTER_IGNORE and warning.border.mouse_filter == Control.MOUSE_FILTER_IGNORE)
			var static_alpha := warning.border.modulate.a
			await _frames()
			_check("reduced flash is a static readable warning", is_equal_approx(static_alpha, warning.border.modulate.a) and is_equal_approx(static_alpha, 1.0))
	root.content_scale_factor = 1.0
	root.size = Vector2i(1280, 720)
	settings.text_scale = 1.0
	settings.high_contrast = false
	UiTheme.apply_text_scale(1.0)
	UiTheme.set_high_contrast(false)
	_safe()
	var fault := services.session.survival.debug_trigger_airlock_fault()
	var vestibule := LocalPressure.VOLUME.get_center()
	services.report_position(services.local_character().id, vestibule, 0.0)
	warning.refresh_from_host()
	_check("airlock warning names affected area and immediate inner-door escape", fault and warning.active and "Airlock" in warning.protection_label.text and "Field engineer" in warning.action_label.text and "Retreat through inner door" in warning.action_label.text)
	services.local_character().suit_on = true
	services.local_character().suit_integrity = 1.0
	services.local_character().suit_charge = 0.0
	services.report_position(services.local_character().id, vestibule, 0.0)
	_check("empty reserve has accurate suit cause", "OXYGEN EMPTY" in warning.cause_label.text)
	services.local_character().suit_charge = 100.0
	services.local_character().suit_integrity = 0.0
	services.report_position(services.local_character().id, vestibule, 0.0)
	_check("failed suit seal has accurate cause", "SUIT SEAL FAILED" in warning.cause_label.text)
	services.local_character().suit_integrity = 1.0
	services.report_position(services.local_character().id, vestibule, 0.0)
	_check("host-validated functional suit clears danger", not warning.active)
	_safe()
	var maintenance_station: Dictionary = services.state().stations["repair_t01"]
	services.report_position(services.local_character().id, CharacterState._v3(maintenance_station.position), 0.0)
	services.state().repair.tasks.T01.condition = 0.6
	var maintenance := StationPanels.for_station(&"repair_t01", services) as MaintenanceStationPanel
	ui.open(maintenance)
	maintenance._start.pressed.emit()
	_check("real maintenance job starts behind native panel", bool(services.session.wear_runtime.status("T01").active))
	_danger()
	_check("fatal warning interrupts maintenance surface", warning.active and not ui.is_open())
	_check("critical close releases authoritative maintenance job", not bool(services.session.wear_runtime.status("T01").active))
	_safe()
	# The player remains at the real deck; a test danger predicate changes only atmospheric breathability.
	var deck: Dictionary = services.state().stations[String(CassetteLibrary.PLAYER_ID)]
	services.report_position(services.local_character().id, CharacterState._v3(deck.position), 0.0)
	var collect := services.state().repair.collected_cassettes as Array
	if not collect.has("cassette_command_center"):
		collect.append("cassette_command_center")
	var reader := StationPanels.for_station(CassetteLibrary.PLAYER_ID, services) as CassettePlayerPanel
	ui.open(reader)
	reader.select_tape("cassette_command_center")
	await _frames()
	_check("cassette opens safely before exposure", ui.top() == reader and reader.photo.texture != null)
	_danger()
	_check("fatal warning interrupts cassette without pausing", warning.active and not ui.is_open() and not services.session.paused and ui.wanted_mouse_mode() == Input.MOUSE_MODE_CAPTURED)
	ui.open_task_sample()
	services.session.advance(services.config.exposure_lethal_seconds + 0.01)
	await _frames()
	_check("host recovery clears countdown and closes task", not warning.active and not ui.is_open())
	_safe()
	# Independent peer views share the same authoritative session, never a global warning flag.
	services.session.peer_joined(2)
	var claim := services.session.request(&"claim_character", &"crew_2", {}, 2)
	_check("second peer claims its own crew member", claim.ok, claim.message)
	services.session.outside_test = func(position: Vector3) -> bool: return position.x > 900.0
	var first_actor := services.state().character_of_peer(1)
	services.report_position(first_actor.id, Vector3(1000.0, 0.0, 1000.0), 0.0)
	warning.refresh_from_host()
	_check("first peer sees its own hazard", warning.active)
	services.viewing_peer = 2
	warning.refresh_from_host()
	_check("safe second peer does not inherit first peer warning", not warning.active)
	services.session.advance(0.2)
	_check("legacy teammate alert cannot create false local fatal banner", not ui._critical_banner.visible and not warning.active)
	var second_actor := services.state().character_of_peer(2)
	services.session.report_position(2, second_actor.id, Vector3(1001.0, 0.0, 1000.0), 0.0)
	warning.refresh_from_host()
	_check("second peer sees its own hazard", warning.active)
	services.events.character_recovered.emit(first_actor.id, {})
	_check("other peer recovery cannot clear local danger", warning.active)
	services.session.recover_character(second_actor.id)
	warning.refresh_from_host()
	_check("local authoritative recovery leaves no stale countdown", not warning.active and warning.remaining_seconds == 0.0)
	_check("recovery leaves no duplicate legacy no-air banner", not ui._critical_banner.visible)
	AudioServer.set_bus_mute(master, old_master_muted)
	services.saves.delete_all()
	ui.queue_free()
	warning.queue_free()
	services.queue_free()
	await _frames()
	UiTheme.release()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)
