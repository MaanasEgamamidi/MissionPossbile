extends SceneTree
## Screenshots of the goals card (HUD, top left) and the big goals screen (J) for the owner. Needs a real window
## (headless cannot draw):
##   godot --path . --script res://tools/godot/capture_goals.gd -- [--out <dir>] [--size 1920x1080] [--tag hd]
## Modelled on tools/godot/capture_puzzles.gd: GameServices + UiRoot, no world. The colony's goal state is set straight
## in the state (tapes found / played, spots fixed) and the host is not ticked, so every shot shows exactly that state.
## The card is shot on a dusty-orange backdrop (the HUD sits over the 3D view) in each of its states; the big screen is
## opened the way MissionHud.open_goals_big() does it. Also one shot with high contrast and large text.
## Saves go to res://_test_saves/capture_goals and are deleted at the end; the player's settings are never written.
## Writes <out>/<tag>_card_*.png (the card, cut out and doubled), <tag>_hud.png and <tag>_big_*.png.

const GoalsBig := preload("res://scripts/ui/hud/goals_big_panel.gd")
const SAVE_DIR := "res://_test_saves/capture_goals"
const GENERAL_TASKS: Array[String] = ["T01", "T03", "T06", "T08", "T10", "T11"]

var out_dir := ""
var tag := "sd"
var screen := Vector2i(1280, 720)
var services: GameServices
var ui: UiRoot
var holder: Control
var card: GoalsCard
var panel: UiPanel


func _arg(name: String, def: String) -> String:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == name and i + 1 < a.size():
			return a[i + 1]
	return def


func _frames(count := 3) -> void:
	for i in count:
		await process_frame


func _st() -> ColonyState:
	return services.state()


## Sets the goal state: tapes found, tapes played, the fixed spots and who this machine's crew member is.
func _goal_state(found: int, played: int, fixed: Array, specialty := "electrical_comms") -> void:
	var st := _st()
	var ids: Array = CassetteCatalog.TAPES.keys()
	ids.sort()
	st.repair["collected_cassettes"] = ids.slice(0, found)
	TutorialSystem.ensure(st).tutorial["played"] = ids.slice(0, played)
	for task_id: String in st.repair.tasks:
		st.repair.tasks[task_id].first_completed = fixed.has(task_id)
	services.local_character().specialty = StringName(specialty)


func _image() -> Image:
	await _frames(10)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _save(img: Image, label: String) -> void:
	var path := out_dir.path_join("%s_%s.png" % [tag, label])
	var error := img.save_png(path)
	print("SHOT %s result=%d size=%s" % [path, error, img.get_size()])


## The card alone: cut out of the frame and doubled, so its drawing can be judged.
func _card_shot(label: String) -> void:
	card.refresh()
	card.size = card.get_combined_minimum_size()
	var img := await _image()
	card.size = card.get_combined_minimum_size()
	var r := Rect2i(Vector2i(card.position) - Vector2i(12, 12), Vector2i(card.size) + Vector2i(24, 24))
	var cut := img.get_region(r)
	cut.resize(cut.get_width() * 2, cut.get_height() * 2, Image.INTERPOLATE_NEAREST)
	_save(cut, "card_" + label)
	var goal := card.next_goal()
	print("  card %s: size %s, next goal '%s' (%s)" % [label, card.size, goal.get("text", ""), goal.get("id", "")])


func _big_shot(label: String, select := "") -> void:
	if select != "":
		panel.call(&"select", select)
		var row := panel.find_child(select, true, false) as Control
		if row != null:
			row.grab_focus()
	panel.refresh()
	_save(await _image(), "big_" + label)
	var issues := UiLayoutCheck.problems(panel, root.get_visible_rect().size)
	var list := panel.find_child("List", true, false) as Control
	var scroll := panel.find_child("GoalList", true, false) as ScrollContainer
	var caption := panel.find_child("Caption", true, false) as Label
	print("  big %s: panel %s, %d rows, list %d px in %d px, caption '%s', layout issues: %s" % [label, panel.get_global_rect(), list.get_child_count(),
		int(list.size.y), int(scroll.size.y), caption.text, "none" if issues.is_empty() else " | ".join(issues)])


func _open_big() -> void:
	if ui != null:
		ui.close_all()
		ui.queue_free()
		await _frames()
	ui = UiRoot.new()
	root.add_child(ui)
	var settings := GameSettings.new()
	settings.reduce_motion = true
	ui.setup(services, settings)
	root.size = screen
	await _frames()
	panel = GoalsBig.new() as UiPanel
	ui.open(panel)
	await _frames(10)


func _initialize() -> void:
	var size_arg := _arg("--size", "1280x720").split("x")
	if size_arg.size() == 2:
		screen = Vector2i(int(size_arg[0]), int(size_arg[1]))
	tag = _arg("--tag", "%dp" % screen.y)
	root.mode = Window.MODE_WINDOWED
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = screen
	PlayerInput.ensure_actions()
	out_dir = _arg("--out", ProjectSettings.globalize_path("res://docs/revisions/evidence/goals"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("ADAPTER %s / %s, screen %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(), screen])
	services = GameServices.new()
	var dir := ProjectSettings.globalize_path(SAVE_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	services.saves = SaveService.new(dir, "colony", 1)
	root.add_child(services)
	services.set_process(false)
	services.start_new_game(5150, &"crew_1")
	TutorialSystem.begin_tutorial_mode(_st(), true)
	await _frames()

	# ---- the card on a backdrop like the game's 3D view
	holder = Control.new()
	holder.name = "Hud"
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.theme = UiTheme.get_theme()
	root.add_child(holder)
	var back := ColorRect.new()
	back.color = Color(0.36, 0.17, 0.10)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(back)
	card = GoalsCard.new()
	holder.add_child(card)
	card.setup(services)
	card.position = Vector2(16, 100)
	root.size = screen
	await _frames()
	_goal_state(2, 0, [])
	await _card_shot("1_find_tapes")
	_goal_state(6, 1, [])
	await _card_shot("2_play_tapes")
	_goal_state(6, 6, [])
	await _card_shot("3_fix_everyone")
	_goal_state(6, 6, ["T01"])
	await _card_shot("4_fix_mine")
	_goal_state(6, 6, GENERAL_TASKS, "biology_food")
	await _card_shot("5_fix_other_specialist")
	_save(await _image(), "hud")
	card.set_open(false)
	await _card_shot("6_compact")
	card.set_open(true)
	_goal_state(6, 6, RepairCatalog.TASKS.keys())
	await _card_shot("7_all_done")
	holder.visible = false

	# ---- the big goals screen
	_goal_state(2, 0, [])
	await _open_big()
	await _big_shot("1_find_tapes")
	_goal_state(6, 3, ["T01", "T03"])
	await _open_big()
	await _big_shot("2_play_tapes")
	await _big_shot("3_fix_mine", "fix_T02")
	await _big_shot("4_fix_other_specialist", "fix_T09")
	await _big_shot("5_fix_everyone", "fix_T08")
	await _big_shot("6_fixed", "fix_T01")
	# keyboard: Down moves the focus (and the map) to the next goal
	var before := String(panel.get(&"selected_id"))
	var down := InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = true
	root.push_input(down)
	await _frames(3)
	print("  keyboard: Down moved the pick from %s to %s" % [before, panel.get(&"selected_id")])
	_goal_state(6, 6, ["T01", "T02", "T03", "T04", "T06", "T08", "T10", "T11"], "medical_life_support")
	await _open_big()
	await _big_shot("7_medic_late")

	# ---- high contrast and large text
	UiTheme.set_high_contrast(true)
	UiTheme.apply_text_scale(1.3)
	_goal_state(6, 3, ["T01", "T03"])
	await _open_big()
	await _big_shot("8_high_contrast_large_text", "fix_T04")
	ui.close_all()
	await _frames()
	holder.visible = true
	card.queue_free()
	card = GoalsCard.new()
	holder.add_child(card)
	card.setup(services)
	card.position = Vector2(16, 100)
	await _card_shot("8_high_contrast_large_text")
	UiTheme.set_high_contrast(false)
	UiTheme.apply_text_scale(1.0)

	ui.queue_free()
	services.saves.delete_all()
	services.queue_free()
	await _frames()
	UiTheme.release()
	quit(0)
