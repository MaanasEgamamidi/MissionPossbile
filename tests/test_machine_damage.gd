extends SceneTree
## Broken machines must route every physical interaction through the same repair boolean.

const BrokenParts := preload("res://scripts/tasks/broken_part_presenter.gd")
const Rule := preload("res://scripts/tasks/puzzles/t01_rule.gd")
var services: GameServices
var passed := 0
var total := 0

func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		passed += 1
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void:
	PlayerInput.ensure_actions()
	services = GameServices.new()
	var save_dir := ProjectSettings.globalize_path("res://_test_saves/machine_damage")
	DirAccess.make_dir_recursive_absolute(save_dir)
	services.saves = SaveService.new(save_dir, "colony", 1)
	root.add_child(services)
	services.start_new_game(4101)
	services.set_process(false)
	var st := services.state()
	TutorialSystem.ensure(st).tutorial["locks"] = false
	await process_frame
	for task_id: String in RepairCatalog.TASKS:
		check("explicit boolean for " + task_id, typeof(st.repair.tasks[task_id].broken) == TYPE_BOOL)
		if RepairCatalog.has_puzzle(task_id):
			var panel := StationPanels.for_station(StringName(RepairCatalog.anchor_id(task_id)), services)
			check("broken anchor opens mini-game " + task_id, panel is TaskPanel and panel.task_id == task_id)
			panel.free()
	for station_id: String in ["cr_console_alarm", "pw_panel", "md_heal_station"]:
		var task_id := RepairCatalog.task_for_station(st, station_id)
		var panel := StationPanels.for_station(StringName(station_id), services)
		check("machine target cannot bypass repair " + station_id, panel is TaskPanel and panel.task_id == task_id)
		panel.free()
	check("nearby cassette remains its own interaction", RepairCatalog.interaction_station_id(st, "cassette_command_center") == "cassette_command_center")
	check("another machine in the same room stays independent", RepairCatalog.interaction_station_id(st, "cm_colony_computer") == "cm_colony_computer")
	var actor := services.local_character()
	actor.position = CharacterState._v3(st.stations.cr_console_alarm.position)
	check("host rejects operational controls while damaged", services.request(&"inspect_donor", &"cr_console_alarm").reason == &"machine_broken")
	actor.position = CharacterState._v3(st.stations.repair_t01.position)
	check("timed maintenance cannot bypass the mini-game", services.request(&"maintenance_start", &"repair_t01", {"generation": 1}).reason == &"repair_required")
	check("maintenance hook cannot clear an unsolved machine", not services.session.wear_runtime.restore_task(services.session, "T01", 1) and st.repair.tasks.T01.broken)
	var hud := GameHud.new()
	root.add_child(hud)
	hud.setup(services)
	hud.set_target({"kind":"station", "id":&"cr_console_alarm", "node":null})
	check("original machine target gets repair prompt", hud.cue_text().contains("Lock the relay"))
	var main := GameMain.new()
	main.services = services
	main.hud = hud
	main.ui = UiRoot.new()
	root.add_child(main.ui)
	main.ui.setup(services, GameSettings.new())
	var opened := main._submit(&"use_station", &"cr_console_alarm", {})
	check("E on original machine actually opens mini-game", opened.ok and main.ui.top() is TaskPanel and main.ui.top().task_id == "T01")
	main.ui.close_all()
	await process_frame
	# A lightweight world verifies that the same boolean swaps broken/intact visuals.
	var world := Node3D.new()
	root.add_child(world)
	var intact := Node3D.new()
	intact.name = "cr_console_alarm"
	world.add_child(intact)
	var damaged := Node3D.new()
	var presenter := BrokenParts.new()
	presenter.force_cpu = 1
	presenter.parts_override = [{"task_id":"T01", "node":damaged, "hide_nodes":["cr_console_alarm"], "zone":"Command Room"}]
	root.add_child(presenter)
	presenter.setup(world, services)
	presenter.set_process(false)
	check("broken boolean shows damaged machine", presenter.shows_broken("T01") and not intact.visible)
	check("real mini-game claim succeeds", services.request(&"task_claim", &"repair_t01", {"generation":1}).ok)
	var target := int(Rule.layout(int(st.repair.tasks.T01.puzzle_seed)).target)
	services.request(&"task_move", &"repair_t01", {"generation":1, "move":"tune", "value":target})
	for step in range(1, Rule.HOLD_STEPS + 1):
		services.request(&"task_move", &"repair_t01", {"generation":1, "move":"hold", "value":step})
	for step in range(1, Rule.TRANSFER_STEPS + 1):
		services.request(&"task_move", &"repair_t01", {"generation":1, "move":"transfer", "value":step})
	check("only the completed puzzle clears broken", not st.repair.tasks.T01.broken and st.repair.tasks.T01.first_completed and st.repair.tasks.T01.progress == 1.0)
	presenter.step(0.0)
	presenter.step(1.2)
	check("repair removes damaged model and restores intact machine", not presenter.shows_broken("T01") and intact.visible)
	var normal := StationPanels.for_station(&"cr_console_alarm", services)
	check("fixed machine opens normal menu", normal is SalvageStationPanel and not normal is TaskPanel)
	check("fixed menu stops calling machine damaged", not normal.panel_title().to_lower().contains("damaged") and not normal._donor().story.to_lower().contains("damaged"))
	normal.free()
	hud.set_target({"kind":"station", "id":&"cr_console_alarm", "node":null})
	hud.refresh()
	check("fixed machine prompt stops offering repair", not hud.cue_text().contains("Lock the relay"))
	actor.position = CharacterState._v3(st.stations.cr_console_alarm.position)
	check("host allows normal operation after fixing", services.request(&"inspect_donor", &"cr_console_alarm").ok)
	check("save fixed machine", services.save_now(&"manual") == OK)
	var saved := services.saves.read().payload.colony as Dictionary
	check("broken false survives disk load", not ColonyState.from_dict(saved).repair.tasks.T01.broken)
	check("new fault restores broken true", services.session.wear_runtime.force_fault(services.session, "T01") and st.repair.tasks.T01.broken and st.repair.tasks.T01.first_completed)
	presenter.step(0.0)
	check("recurring fault restores damaged appearance", presenter.shows_broken("T01") and not intact.visible)
	var again := StationPanels.for_station(&"cr_console_alarm", services)
	check("recurring fault reopens mini-game despite past completion", again is TaskPanel and again.task_id == "T01" and not again.succeeded)
	again.free()
	var replica := ColonyState.from_dict(st.to_dict())
	check("late join receives broken boolean", replica.repair.tasks.T01.broken and RepairCatalog.interaction_station_id(replica, "cr_console_alarm") == "repair_t01")
	var legacy := st.repair.duplicate(true)
	for task: Dictionary in legacy.tasks.values():
		task.erase("broken")
	legacy.tasks.T01.maintenance_fault = false
	legacy.tasks.T01.first_completed = true
	legacy.tasks.T04.first_completed = false
	var migrated := RepairCatalog.restore(legacy, 4101)
	check("old saves infer fixed and unsolved booleans", not migrated.tasks.T01.broken and migrated.tasks.T04.broken)
	legacy.tasks.T01.maintenance_fault = true
	check("old saves retain recurring damage", RepairCatalog.restore(legacy, 4101).tasks.T01.broken)
	# The explicit boolean, rather than completion history, controls every route.
	st.repair.tasks.T04.broken = false
	var power := StationPanels.for_station(&"pw_panel", services)
	check("broken false is authoritative even before first milestone", power is PowerStationPanel)
	power.free()
	st.repair.tasks.T04.broken = true
	services.saves.delete_all()
	main.ui.queue_free()
	main.free()
	presenter.queue_free()
	world.queue_free()
	hud.queue_free()
	services.queue_free()
	await process_frame
	UiTheme.release()
	print("RESULT %d/%d" % [passed, total])
	quit(0 if passed == total else 1)
