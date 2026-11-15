extends SceneTree

var ui: UiRoot
var services: GameServices
var out_dir: String

func frames(n := 12) -> void:
	for i in n:
		await process_frame

func shot(label: String, panel: UiPanel) -> void:
	ui.close_all()
	await frames(3)
	ui.open(panel)
	await frames(24)
	panel.refresh()
	await frames(24)
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(out_dir.path_join(label + ".png"))
	print("SHOT %s result=%d" % [label, err])

func _initialize() -> void:
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.size = Vector2i(1920, 1080)
	out_dir = ProjectSettings.globalize_path("res://output/menu_sheet/extra")
	DirAccess.make_dir_recursive_absolute(out_dir)
	PlayerInput.ensure_actions()
	services = GameServices.new()
	var saves_dir := ProjectSettings.globalize_path("res://_test_saves/menu_sheet_extra")
	DirAccess.make_dir_recursive_absolute(saves_dir)
	services.saves = SaveService.new(saves_dir, "colony", 1)
	root.add_child(services)
	services.start_new_game(4171)
	services.set_process(false)
	var settings := GameSettings.new()
	settings.reduce_motion = true
	ui = UiRoot.new()
	root.add_child(ui)
	ui.setup(services, settings)
	await frames()
	await shot("01_blueprint", BlueprintPanel.new())
	await shot("02_sources", SourceRegisterPanel.new())
	await shot("03_vitals_science", VitalsSciencePanel.new())
	await shot("04_power_life", PowerLifePanel.new())
	var numbers := PowerLifePanel.new()
	await shot("05_power_life_numbers", numbers)
	numbers.show_numbers(true)
	await frames(30)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join("05_power_life_numbers.png"))
	var solar := SolarBuildPanel.new()
	solar.tracker_id = &"sf_solar_tracker"
	services.local_character().position = CharacterState._v3(services.state().stations["sf_solar_tracker"].position)
	await shot("06_solar_build", solar)
	var goals := load("res://scripts/ui/hud/goals_big_panel.gd").new() as UiPanel
	await shot("07_goals", goals)
	var sections := {"energy":"pw_panel", "biology":"gh_console", "health":"md_heal_station", "science":"hg_control_board", "communication":"cm_comms_console"}
	for id: String in sections:
		var station := String(sections[id])
		services.local_character().position = CharacterState._v3(services.state().stations[station].position)
		await shot("08_section_" + id, StationPanels.section_panel(StringName(id), StringName(station), services))
	services.state().colony_over = {"reason":"oxygen", "text":"The colony ran out of oxygen.", "sol":1, "hint":"Keep life support running and protect the oxygen reserve."}
	await shot("09_colony_over", load("res://scripts/ui/hud/colony_over_screen.gd").new() as UiPanel)
	ui.close_all()
	services.saves.delete_all()
	quit(0)
