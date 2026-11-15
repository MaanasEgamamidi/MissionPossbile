extends SceneTree
## Screenshots of the four "information" panels: upgrade cards, colony summary, quiz and the colony journal.
## No map is loaded (GameServices + UiRoot, as tools/godot/capture_menus.gd does). Needs a real window:
##   godot --path . --script res://tools/godot/capture_info_panels.gd -- --out <folder>
##       [--size 1280x720] [--text 1.5] [--hc] [--real-pixels] [--only upgrades,summary,quiz,journal]
## --real-pixels lays the panels out in the window's own pixels (the UI tests' hardest case) instead of the game's
## stretched 1920x1080 canvas. Saves go to res://_test_saves/menu_sheet_capture_info_panels and are deleted at the end; the
## player's own settings are never read or written.
## Writes <folder>/<WxH>[_tNNN][_hc][_px]_<name>.png and prints UiLayoutCheck's findings for every shot.

const SAVE_DIR := "res://_test_saves/menu_sheet_capture_info_panels"
const COMPUTER := "cm_colony_computer"
const POWER := "pw_panel"

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
	await _frames(2)
	return panel


func _stand_at(station: String) -> void:
	var st := services.state()
	if st.stations.has(station):
		services.local_character().position = CharacterState._v3((st.stations[station] as Dictionary).get("position", [0, 0, 0]))


func _know(qid: String) -> void:
	var st := services.state()
	var q := ProgressionSystem.question(StringName(qid))
	var v: Dictionary = (q.variants as Array)[0]
	st.knowledge[qid] = {"by": "crew_1", "sector": String(q.sector), "at_hours": 0.0, "variant": 0, "example": String(v.example)}


func _evidence(id: String) -> void:
	var s := services.session
	ProgressEvidence.record(s.state, s.events, StringName(id), String((ProgressionSystem.catalogue().evidence as Dictionary)[id].sector), &"crew_1")


func _initialize() -> void:
	var size_text := _arg("--size", "1920x1080")
	var window_size := Vector2i(int(size_text.get_slice("x", 0)), int(size_text.get_slice("x", 1)))
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.position = Vector2i.ZERO
	root.size = window_size
	if _flag("--real-pixels"):
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var text_scale := float(_arg("--text", "1.0"))
	out_dir = _arg("--out", ProjectSettings.globalize_path("res://_test_saves/menu_sheet_capture_info_panels_shots"))
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
	services.start_new_game(4171)
	await _frames(2)
	services.set_process(false)          # no simulation ticks: the shots show the values set here
	print("WINDOW %s canvas %s" % [root.size, root.get_visible_rect().size])
	var st := services.state()

	if _wants("journal"):
		await _open(StoryLogPanel.new())
		await _shot("40_journal")

	if _wants("summary"):
		var summary := await _open(ColonySummaryPanel.new())
		await _shot("20_summary_ok")
		var keep := st.stores.duplicate()
		st.stores[&"oxygen_kg"] = 4.0
		st.stores[&"battery_kwh"] = 150.0
		st.rates = {"oxygen_kg": -0.1, "water_l": 0.0, "food_meals": -3.0 / GameConfig.SOL_HOURS, "battery_kwh": -34.0}
		st.solar_kw = 0.0
		st.load_kw = 34.0
		st.battery_kw = -34.0
		summary.refresh()
		await _shot("21_summary_low")
		if summary.has_method(&"set_details_open"):
			summary.call(&"set_details_open", true)
			await _shot("22_summary_details")
		st.stores = keep
		st.rates = {}

	if _wants("quiz"):
		_stand_at(COMPUTER)
		var quiz := await _open(QuizPanel.for_card(ProgressionSystem.card(&"ls_electrolysis"))) as QuizPanel
		await _shot("30_quiz")
		var qid: StringName = quiz.question_ids[0]
		var right := int(ProgressionSystem.current_variant(st, qid).get("correct", 0))
		quiz.answer(qid, (right + 1) % 3)
		await _shot("31_quiz_wrong")
		quiz.answer(qid, int(ProgressionSystem.current_variant(st, qid).get("correct", 0)))
		await _shot("32_quiz_right")
		st.knowledge.erase(String(qid))
		services.local_character().position = services.config.hub_position
		quiz.refresh()
		await _shot("33_quiz_away")

	if _wants("upgrades"):
		_stand_at(COMPUTER)
		var up := await _open(UpgradeCardsPanel.new()) as UpgradeCardsPanel
		await _shot("10_upgrades_locked")
		_evidence("energy_diagnose_output_loss")
		_evidence("energy_predict_net_power")
		for q in ["energy_q_dust_output", "energy_q_tracking", "energy_q_battery_night", "energy_q_net_power"]:
			_know(q)
		up.refresh()
		await _shot("11_upgrades_ready_at_computer")
		_stand_at(POWER)
		services.request(&"install_upgrade", StringName(POWER), {"upgrade_id": "energy_battery_reserve"})
		up.refresh()
		await _shot("12_upgrades_ready_and_done")
		if up.has_method(&"set_more_open"):
			up.call(&"set_more_open", &"energy_solar_tracking", true)
			up.call(&"set_more_open", &"energy_cleaner_automation", true)
			await _shot("13_upgrades_more")
		if up.has_method(&"set_help_open"):
			up.call(&"set_help_open", true)
			await _shot("14_upgrades_help")

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
