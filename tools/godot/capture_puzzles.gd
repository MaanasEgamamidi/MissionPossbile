extends SceneTree
## Screenshots of the ten repair mini-games (T01 T02 T03 T04 T06 T08 T09 T10 T11 T12) for the owner, plus T02 opened by
## the wrong specialist (the scrambled panel). Needs a real window (headless cannot draw):
##   godot --path . --script res://tools/godot/capture_puzzles.gd -- [--out <dir>] [--only T01,T03] [--size 1920x1080]
## (the window is 1280x720 unless --size is given)
## Each game is started the way tests/test_puzzle_tNN.gd start theirs (GameServices + UiRoot, no world): the right crew
## member stands at the station, E's panel (StationPanels.for_station) opens, a shot is taken, the puzzle is played to
## the end through the panel's own keyboard path (the same keys the tests press), and the solved panel is shot.
## Saves go to res://_test_saves/capture_puzzles and are deleted at the end; the player's settings are never written.
## Writes <out>/Tnn_start.png, <out>/Tnn_solved.png (just after the last move, before the shell's success mark),
## <out>/Tnn_stamp.png (a second later, with the success mark) and <out>/T02_wrong_specialist.png ("--only wrong").
## Mid-game shots taken by the solvers: T02_mid_held / T10_mid_held (a plug picked, not yet seated), T02_mid_wrong /
## T10_mid_wrong (a plug pushed into the wrong socket: amber cross), T04_mid_wrong_volts (the path joined to the lamp
## through the wrong voltage part), T09_mid_lifted (a tube lifted, its pour targets ringed) and T09_mid_half.

const R01 := preload("res://scripts/tasks/puzzles/t01_rule.gd")
const R02 := preload("res://scripts/tasks/puzzles/t02_rule.gd")
const R03 := preload("res://scripts/tasks/puzzles/t03_rule.gd")
const R04 := preload("res://scripts/tasks/puzzles/t04_rule.gd")
const R06 := preload("res://scripts/tasks/puzzles/t06_rule.gd")
const R08 := preload("res://scripts/tasks/puzzles/t08_rule.gd")
const R09 := preload("res://scripts/tasks/puzzles/t09_rule.gd")
const R10 := preload("res://scripts/tasks/puzzles/t10_rule.gd")
const R11 := preload("res://scripts/tasks/puzzles/t11_rule.gd")
const R12 := preload("res://scripts/tasks/puzzles/t12_rule.gd")
const SAVE_DIR := "res://_test_saves/capture_puzzles"
const SCREEN := Vector2i(1280, 720)
## The window size in use: SCREEN, or "--size 1920x1080".
var screen := SCREEN
## Task -> [crew member who plays it (their specialty fits the task), game seed used by the task's panel test].
const PLAN := {
	"T01": [&"crew_1", 4171], "T02": [&"crew_1", 4271], "T03": [&"crew_1", 4371], "T04": [&"crew_1", 4471],
	"T06": [&"crew_1", 5150], "T08": [&"crew_1", 5150], "T09": [&"crew_2", 90902], "T10": [&"crew_3", 91002],
	"T11": [&"crew_1", 5150], "T12": [&"crew_4", 91202],
}

var out_dir := ""
var services: GameServices
var ui: UiRoot
var panel: TaskPanel
var task_id := ""


func _arg(name: String, def: String) -> String:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == name and i + 1 < a.size():
			return a[i + 1]
	return def


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


func _press(button: Button) -> void:
	button.grab_focus()
	_key(KEY_ENTER)
	await _frames(2)


func _task() -> Dictionary:
	return services.state().repair.tasks[task_id]


func _shot(label: String) -> void:
	await _frames(12)
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(label + ".png")
	var error := root.get_texture().get_image().save_png(path)
	print("SHOT %s result=%d window=%s canvas=%s" % [label, error, root.size, root.get_visible_rect().size])
	if panel != null and is_instance_valid(panel):
		var issues := UiLayoutCheck.problems(panel, root.get_visible_rect().size)
		print("  panel rect %s layout issues: %s" % [panel.get_global_rect(), "none" if issues.is_empty() else " | ".join(issues)])
		print("  status: ", panel.status_label.text.replace("\n", " / ") if panel.status_label != null else "-")


## When the panel's content is taller than the screen (TaskPanel's TaskScroll), also shoots it scrolled to the bottom
## so the part below the fold (status line, progress bar, parts tray) can be seen; then scrolls back.
func _scroll_shot(label: String) -> void:
	var scroll := panel.find_child("TaskScroll", true, false) as ScrollContainer
	if scroll == null:
		return
	var bar := scroll.get_v_scroll_bar()
	if bar.max_value - bar.page <= 1.0:
		return
	print("  %s: content %d px taller than the visible %d px" % [label, int(bar.max_value - bar.page), int(bar.page)])
	var keep := scroll.scroll_vertical
	scroll.scroll_vertical = int(bar.max_value)
	await _shot(label)
	scroll.scroll_vertical = keep
	await _frames(4)


func _initialize() -> void:
	root.mode = Window.MODE_WINDOWED
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var wanted := _arg("--size", "").split("x", false)
	if wanted.size() == 2 and int(wanted[0]) >= 640 and int(wanted[1]) >= 360:
		screen = Vector2i(int(wanted[0]), int(wanted[1]))
	root.size = screen
	PlayerInput.ensure_actions()
	out_dir = _arg("--out", ProjectSettings.globalize_path("res://docs/revisions/evidence/minigames"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var only := _arg("--only", "").split(",", false)
	print("ADAPTER %s / %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method()])
	services = GameServices.new()
	# One save folder per --only list, so several captures can run at the same time.
	var dir := ProjectSettings.globalize_path(SAVE_DIR + ("" if only.is_empty() else "_" + "_".join(only)))
	# The shell closes itself after a repair; the captures keep it open to shoot it.
	TaskPanel.auto_close_seconds = 0.0
	DirAccess.make_dir_recursive_absolute(dir)
	services.saves = SaveService.new(dir, "colony", 1)
	root.add_child(services)
	for id: String in PLAN:
		if not only.is_empty() and not only.has(id):
			continue
		var ok := await _open(id, PLAN[id][0], int(PLAN[id][1]))
		if not ok:
			continue
		await _shot("%s_start" % id)
		await _scroll_shot("%s_start_scrolled" % id)
		await _solve(id)
		await _frames(20)
		print("%s solved=%s first_completed=%s progress=%s" % [id, panel.succeeded, _task().first_completed, _task().progress])
		await _shot("%s_solved" % id)
		await _scroll_shot("%s_solved_scrolled" % id)
		# About a second later: the end of the puzzle's own animation, under the shell's success mark.
		await _frames(70)
		await _shot("%s_stamp" % id)
	if only.is_empty() or only.has("wrong"):
		# A biologist (crew_3) at the wires station: T02 needs the electrical specialist.
		if await _open("T02", &"crew_3", 4271, false):
			await _shot("T02_wrong_specialist")
			await _scroll_shot("T02_wrong_specialist_scrolled")
	_close()
	services.saves.delete_all()
	services.queue_free()
	await _frames()
	UiTheme.release()
	quit(0)


func _close() -> void:
	if ui != null:
		ui.close_all()
		ui.queue_free()
		ui = null
	panel = null


## Starts a fresh game as `crew`, puts them at the task's station and opens what E opens there.
func _open(id: String, crew: StringName, seed_value: int, right_specialist := true) -> bool:
	_close()
	await _frames()
	task_id = id
	services.start_new_game(seed_value, crew)
	await _frames()
	var station_id := StringName("repair_" + id.to_lower())
	var station: Dictionary = services.state().stations.get(String(station_id), {})
	if station.is_empty():
		push_error("no station " + String(station_id))
		return false
	var actor := services.local_character()
	var pos := CharacterState._v3(station.position)
	if id == "T12":
		var safe := _safe_point(pos)
		pos = safe if safe != Vector3.INF else pos
	actor.position = pos
	var need := String(_task().required_specialty)
	if right_specialist and need != "general" and String(actor.specialty) != need:
		print("NOTE %s: %s is %s, task needs %s; setting it like the test does" % [id, crew, actor.specialty, need])
		actor.specialty = StringName(need)
	print("OPEN %s as %s (%s), task needs %s" % [id, crew, actor.specialty, need])
	ui = UiRoot.new()
	root.add_child(ui)
	var settings := GameSettings.new()
	settings.reduce_motion = true
	ui.setup(services, settings)
	root.size = screen
	await _frames()
	panel = StationPanels.for_station(station_id, services) as TaskPanel
	if panel == null:
		push_error("no mini-game panel for " + id)
		return false
	ui.open(panel)
	await _frames(10)
	return true


# ---------------------------------------------------------------- solves (the keys each panel test presses)

func _solve(id: String) -> void:
	match id:
		"T01": await _solve_t01()
		"T02": await _solve_t02()
		"T03": await _solve_t03()
		"T04": await _solve_t04()
		"T06": await _solve_t06()
		"T08": await _solve_t08()
		"T09": await _solve_t09()
		"T10": await _solve_t10()
		"T11": await _solve_t11()
		"T12": await _solve_t12()


func _solve_t01() -> void:
	var slider := panel.get("slider") as HSlider
	var target := int(R01.layout(int(_task().puzzle_seed)).target)
	slider.grab_focus()
	var steps := target - int(slider.value)
	for i in absi(steps):
		_key(KEY_RIGHT if steps > 0 else KEY_LEFT)
	await _frames()
	var waited := 0.0
	while not bool(_task().first_completed) and waited < 15.0:
		await create_timer(0.1).timeout
		waited += 0.1


func _solve_t02() -> void:
	var lay := R02.layout(int(_task().puzzle_seed))
	var left_buttons: Array = panel.get("left_buttons")
	var right_buttons: Array = panel.get("right_buttons")
	# A plug held, then pushed into the wrong socket (the host refuses it and the plug goes back).
	var right := (lay.right as Array).find(lay.left[0])
	await _press(left_buttons[0])
	await _shot("T02_mid_held")
	await _press(right_buttons[(right + 1) % R02.PAIRS])
	await _shot("T02_mid_wrong")
	for i in R02.PAIRS:
		await _press(left_buttons[i])
		await _press(right_buttons[(lay.right as Array).find(lay.left[i])])
	# On a fast display the 90 frames before the stamp shot can be shorter than the shell's STAMP_DELAY.
	await create_timer(0.3).timeout


func _solve_t03() -> void:
	var lay := R03.layout(int(_task().puzzle_seed))
	var stop := panel.get("stop_button") as Button
	for ring in R03.RINGS:
		stop.grab_focus()
		panel.set("ring_start_ms", Time.get_ticks_msec() - int(lay.rings[ring].first_ms))
		_key(KEY_ENTER)
		await _frames()
	# A light panel runs at a high frame rate: wait in time, so the stamp shot really comes after the success mark.
	await create_timer(0.4).timeout


func _solve_t04() -> void:
	var lay := R04.layout(int(_task().puzzle_seed))
	var cells: Array = panel.get("cells")
	# First the whole path with the -1 V decoy (the last tray slot) in place of the last voltage part: joined to the
	# lamp at the wrong voltage. Then the decoy comes out (Delete) and the right part goes in.
	var decoy := (lay.slots as Array).size() - 1
	var volt_step := -1
	for k in (lay.solution as Array).size():
		if int(lay.slots[int(lay.solution[k].slot)].kind) == R04.VOLT:
			volt_step = k
	for k in (lay.solution as Array).size():
		var step: Dictionary = lay.solution[k]
		await _place_t04(cells, int(step.cell), decoy if k == volt_step else int(step.slot), int(step.rot))
	await _shot("T04_mid_wrong_volts")
	if volt_step >= 0:
		var step: Dictionary = lay.solution[volt_step]
		(cells[int(step.cell)] as Button).grab_focus()
		await _frames(1)
		_key(KEY_DELETE)
		await _frames(2)
		await _place_t04(cells, int(step.cell), int(step.slot), int(step.rot))
	# On a fast display the 90 frames before the stamp shot can be shorter than the shell's STAMP_DELAY.
	await create_timer(0.3).timeout


func _place_t04(cells: Array, cell: int, slot: int, rot: int) -> void:
	(cells[cell] as Button).grab_focus()
	await _frames(1)
	if int(panel.get("_hand_slot")) != slot:
		_key(KEY_1 + slot)
	var guard := 0
	while int(panel.get("_hand_rot")) != rot and guard < 4:
		_key(KEY_R)
		guard += 1
	_key(KEY_ENTER)
	await _frames(2)


func _next_turn_t06(task: Dictionary) -> Array:
	var st := R06.state_of(task)
	var lay := R06.layout(int(st.seed))
	for cell: int in lay.route:
		var kind := int(lay.kinds[cell])
		var rot := int(st.rot[cell])
		if R06.mask_of(kind, rot) == R06.mask_of(kind, int(lay.solution[cell])):
			continue
		var need := posmod(int(lay.solution[cell]) - rot, 4)
		if kind == R06.STRAIGHT:
			need = 1
		return [cell, -1 if need == 3 else 1]
	return []


func _solve_t06() -> void:
	var tiles: Array = panel.get("tiles")
	var presses := 0
	while presses < 120:
		var next: Array = _next_turn_t06(_task())
		if next.is_empty() or float(_task().progress) >= 1.0:
			break
		(tiles[int(next[0])] as Control).grab_focus()
		await _frames(1)
		_key(KEY_Q if int(next[1]) < 0 else KEY_ENTER)
		await _frames(2)
		presses += 1


func _solve_t08() -> void:
	var frame: Array = panel.get("frame_tiles")
	var tray: Array = panel.get("piece_tiles")
	var lay := R08.layout(int(_task().puzzle_seed))
	for piece in R08.PIECES:
		var solution: Array = lay.pieces[piece].solution
		(tray[piece] as Control).grab_focus()
		await _frames(1)
		_key(KEY_ENTER)
		await _frames(2)
		var turns := posmod(int(solution[2]) - int((panel.get("ui_turns") as Array)[piece]), 4)
		for i in turns:
			_key(KEY_R)
			await _frames(1)
		var target := Vector2i(int(solution[0]), int(solution[1]))
		for i in 12:
			var at := frame.find(root.gui_get_focus_owner())
			if at < 0:
				break
			var here := Vector2i(at % R08.SIZE, at / R08.SIZE)
			if here == target:
				break
			_key(KEY_RIGHT if here.x < target.x else (KEY_LEFT if here.x > target.x else (KEY_DOWN if here.y < target.y else KEY_UP)))
			await _frames(1)
		_key(KEY_ENTER)
		await _frames(2)
	# A light panel runs at a high frame rate: wait in time, so the stamp shot really comes after the success mark.
	await create_timer(0.4).timeout


## Shortest list of [from, to] pours that sorts the tubes (copied from tests/test_puzzle_t09.gd).
static func _solve_tubes(start: Array) -> Array:
	var key0 := str(start)
	var parent := {key0: null}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var tubes: Array = queue[head]
		head += 1
		if R09.is_sorted(tubes):
			var path: Array = []
			var k := str(tubes)
			while parent[k] != null:
				var link: Array = parent[k]
				path.push_front(link[1])
				k = link[0]
			return path
		for a in tubes.size():
			for b in tubes.size():
				if a == b or not R09.can_pour(tubes, a, b):
					continue
				var next: Array = tubes.duplicate(true)
				(next[b] as Array).append((next[a] as Array).pop_back())
				var nk := str(next)
				if parent.has(nk):
					continue
				parent[nk] = [str(tubes), [a, b]]
				queue.append(next)
	return []


func _solve_t09() -> void:
	var buttons: Array = panel.get("tube_buttons")
	var state := R09.current_state(_task())
	for i in R09.TUBES:
		if not bool(state.racked[i]):
			await _press(buttons[i])
	var path := _solve_tubes(R09.current_state(_task()).tubes)
	for k in path.size():
		var p: Array = path[k]
		await _press(buttons[int(p[0])])
		if k == 0:
			await _shot("T09_mid_lifted")
		await _press(buttons[int(p[1])])
		if k == path.size() / 2:
			await _shot("T09_mid_half")


func _solve_t10() -> void:
	var start := R10.current_state(_task())
	var leads: Array = panel.get("lead_buttons")
	var sockets: Array = panel.get("socket_buttons")
	# A plug held, then pushed into a socket that is not its own (the host refuses it and the plug goes back).
	await _press(leads[0])
	await _shot("T10_mid_held")
	for j in (start.sockets as Array).size():
		if int(start.sockets[j]) != 0:
			await _press(sockets[j])
			break
	await _shot("T10_mid_wrong")
	for kind in 2:
		await _press(leads[kind])
		await _press(sockets[(start.sockets as Array).find(kind)])
	await _press(panel.get("test_button"))
	# On a fast display the 90 frames before the stamp shot can be shorter than the shell's STAMP_DELAY.
	await create_timer(0.3).timeout


static func _next_stroke(task: Dictionary) -> Array:
	var areas: Dictionary = R11.state_of(task).areas
	for i in R11.AREAS.size():
		var level := float(areas[R11.AREAS[i].id])
		if level > 0.5:
			return ["brush", i]
		if level > 0.0:
			return ["vacuum", i]
	return []


func _solve_t11() -> void:
	var tiles: Array = panel.get("area_tiles")
	var presses := 0
	while presses < 40:
		var s := _next_stroke(_task())
		if s.is_empty() or float(_task().progress) >= 1.0:
			break
		(tiles[int(s[1])] as Control).grab_focus()
		await _frames(1)
		if String(panel.get("current_tool")) != String(s[0]):
			_key(KEY_B if s[0] == "brush" else KEY_V)
			await _frames(1)
		_key(KEY_SPACE)
		await _frames(2)
		presses += 1


func _solve_t12() -> void:
	# Find the leaking seam, fit the new seal, then press the points in their order.
	await _press(panel.get("seam_buttons")[int(R12.current_state(_task()).leak)])
	await _press(panel.get("gasket_button"))
	await _frames(4)
	for i in R12.POINTS:
		await _press(panel.get("press_buttons")[R12.next_point(R12.current_state(_task()))])


## A spot within reach of the T12 station, on the hangar side, outside the leaking vestibule (from test_puzzle_t12.gd).
func _safe_point(station_pos: Vector3) -> Vector3:
	var s := services.session
	var reach := s.config.interact_distance_m - 0.15
	var zones: Array = RepairCatalog.ROOMS["hangar"].zones
	var best := Vector3.INF
	var best_margin := -1.0
	var box := LocalPressure.VOLUME.grow(LocalPressure.BOUNDARY_HYSTERESIS_M + 0.2)
	for ix in range(-10, 11):
		for iz in range(-10, 11):
			var p := station_pos + Vector3(ix * 0.25, 0.0, iz * 0.25)
			if p.distance_to(station_pos) > reach or box.has_point(p):
				continue
			if s.zone_at_position.is_valid() and not zones.has(String(s.zone_at_position.call(p))):
				continue
			if not s.survival.breathable_at(p):
				continue
			var margin := LocalPressure.VOLUME.position.z - p.z
			if margin > best_margin:
				best_margin = margin
				best = p
	return best
