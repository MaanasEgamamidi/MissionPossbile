extends SceneTree
## T06 Water (broken pipe BP09): host rule, a real SessionService round trip with the actor at the station, forged /
## replayed / out-of-range moves, determinism per seed, the panel's keyboard solve and the save projection.
## Run: godot --headless --path . --script res://tests/test_puzzle_t06.gd

const RULE := preload("res://scripts/tasks/puzzles/t06_rule.gd")
const TASK := "T06"
const STATION := &"repair_t06"
const SAVE_DIR := "res://_test_saves/test_puzzle_t06"
const SHIFT := 1024

var _passed := 0
var _total := 0
var services: GameServices
var ui: UiRoot


func _check(label: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
	print(("PASS " if ok else "FAIL ") + label + (": " + detail if not detail.is_empty() else ""))


func _frames(count := 2) -> void:
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
	root.size = Vector2i(1280, 720)
	_rule_checks()
	services = GameServices.new()
	var dir := ProjectSettings.globalize_path(SAVE_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	services.saves = SaveService.new(dir, "colony", 1)
	root.add_child(services)
	_new_game(4242)
	_session_checks()
	_new_game(777)
	_save_checks()
	_new_game(5150)
	await _panel_checks()
	services.saves.delete_all()
	if ui != null:
		ui.queue_free()
	services.queue_free()
	await _frames()
	UiTheme.release()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


func _new_game(seed_value: int) -> void:
	services.start_new_game(seed_value)
	var station: Dictionary = services.state().stations.get(String(STATION), {})
	_check("station %s exists (seed %d)" % [STATION, seed_value], not station.is_empty())
	services.local_character().position = CharacterState._v3(station.get("position", [0, 0, 0]))


func _task() -> Dictionary:
	return services.state().repair.tasks[TASK]


func _move(move_name: String, value: int, extra := {}) -> ActionResult:
	var params := {"generation": int(_task().fault_generation), "move": move_name, "value": value}
	params.merge(extra)
	return services.request(&"task_move", STATION, params)


## The next turn that brings a route pipe toward its solution (direction +1 or -1), or [] when none is needed.
func _next_turn(task: Dictionary) -> Array:
	var st := RULE.state_of(task)
	var lay := RULE.layout(int(st.seed))
	for cell: int in lay.route:
		var kind := int(lay.kinds[cell])
		var rot := int(st.rot[cell])
		if RULE.mask_of(kind, rot) == RULE.mask_of(kind, int(lay.solution[cell])):
			continue
		var need := posmod(int(lay.solution[cell]) - rot, 4)
		if kind == RULE.STRAIGHT:
			need = 1
		return [cell, -1 if need == 3 else 1]
	return []


func _rule_checks() -> void:
	_check("layout is deterministic per seed", JSON.stringify(RULE.layout(123)) == JSON.stringify(RULE.layout(123)))
	var shapes := {}
	for s in [1, 2, 3, 4, 5, 6]:
		shapes[JSON.stringify(RULE.layout(s).start) + JSON.stringify(RULE.layout(s).kinds)] = true
	_check("different seeds give different boards", shapes.size() >= 5, str(shapes.size()))
	var all_ok := true
	var detail := ""
	for s in 60:
		var seed_value := s * 7919 + 13
		var lay := RULE.layout(seed_value)
		var route: Array = lay.route
		var starts_ok := int(route[0]) == int(lay.supply_row) * RULE.COLS and int(route[-1]) == int(lay.rack_row) * RULE.COLS + RULE.COLS - 1
		var solved := RULE.is_complete(lay.kinds, lay.solution, lay.supply_row, lay.rack_row)
		var unsolved_start := not RULE.is_complete(lay.kinds, lay.start, lay.supply_row, lay.rack_row)
		if not (starts_ok and solved and unsolved_start):
			all_ok = false
			detail = "seed %d starts %s solved %s scrambled %s" % [seed_value, starts_ok, solved, unsolved_start]
	_check("60 seeds: route joins supply to rack, solution flows, start does not", all_ok, detail)
	var task := {"puzzle_seed": 99, "puzzle_state": {}, "progress": 0.0}
	var st := RULE.state_of(task)
	_check("empty state is the seeded start", int(st.step) == 0 and st.rot == RULE.layout(99).start)
	var cell := int(RULE.layout(99).route[0])
	var rot := int(st.rot[cell])
	_check("turn by two is refused", not RULE.validate(task, {"move": "turn", "value": SHIFT + cell * 4 + (rot + 2) % 4}).accepted)
	_check("wrong step is refused", not RULE.validate(task, {"move": "turn", "value": 2 * SHIFT + cell * 4 + (rot + 1) % 4}).accepted)
	_check("cell out of range is refused", not RULE.validate(task, {"move": "turn", "value": SHIFT + RULE.COLS * RULE.ROWS * 4}).accepted)
	_check("negative value is refused", not RULE.validate(task, {"move": "turn", "value": -5}).accepted)
	_check("unknown move is refused", not RULE.validate(task, {"move": "fill", "value": SHIFT}).accepted)
	_check("forged reset payload is refused", not RULE.validate(task, {"move": "reset", "value": SHIFT + 1}).accepted)
	var good := RULE.validate(task, {"move": "turn", "value": SHIFT + cell * 4 + (rot + 1) % 4})
	_check("one quarter turn is accepted", good.accepted and int(good.puzzle_state.step) == 1 and not good.complete)
	var after := {"puzzle_seed": 99, "puzzle_state": good.puzzle_state, "progress": good.progress}
	_check("replayed turn is refused", not RULE.validate(after, {"move": "turn", "value": SHIFT + cell * 4 + (rot + 1) % 4}).accepted)
	var json_copy := {"puzzle_seed": 99, "puzzle_state": JSON.parse_string(JSON.stringify(good.puzzle_state))}
	_check("state survives JSON numbers", RULE.state_of(json_copy).rot == good.puzzle_state.rot and int(RULE.state_of(json_copy).step) == 1)
	var forged := {"puzzle_seed": 99, "puzzle_state": {"seed": 98, "step": 4, "rot": good.puzzle_state.rot}}
	_check("state of another seed is ignored", int(RULE.state_of(forged).step) == 0)
	var broken_rot: Array = (good.puzzle_state.rot as Array).duplicate()
	broken_rot[0] = 7
	_check("out-of-range saved rotation is ignored", int(RULE.state_of({"puzzle_seed": 99, "puzzle_state": {"seed": 99, "step": 1, "rot": broken_rot}}).step) == 0)
	var reset := RULE.validate(after, {"move": "reset", "value": 2 * SHIFT})
	_check("reset returns to the seeded start", reset.accepted and reset.puzzle_state.rot == RULE.layout(99).start and reset.progress < 1.0)
	_check("no-supply edge case blocks water", RULE.water([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 0).is_empty())


func _session_checks() -> void:
	_check("puzzle installed and spot broken", PuzzleRegistry.has_puzzle(TASK) and PuzzleRegistry.is_broken(services.state(), TASK))
	var actor := services.local_character()
	var at := actor.position
	actor.position = at + Vector3(40, 0, 40)
	var away := services.request(&"task_claim", STATION, {"generation": 1})
	_check("claim refused away from the station", not away.ok and away.reason in [&"wrong_room", &"too_far"], String(away.reason))
	actor.position = at
	var claim := services.request(&"task_claim", STATION, {"generation": int(_task().fault_generation)})
	_check("claim at the station", claim.ok, claim.message)
	var st := RULE.state_of(_task())
	var turn: Array = _next_turn(_task())
	var value := SHIFT + int(turn[0]) * 4 + posmod(int(st.rot[turn[0]]) + 1, 4)
	_check("forged completion flag is a bad request", _move("turn", value, {"complete": true}).reason == &"bad_request")
	_check("unknown move fails closed", _move("open_valve", value).reason == &"invalid_move")
	_check("out-of-range cell fails closed", _move("turn", SHIFT + 999).reason == &"invalid_move")
	_check("skipped step fails closed", _move("turn", value + SHIFT).reason == &"invalid_move")
	var first := _move("turn", value)
	_check("valid turn accepted", first.ok and int(_task().puzzle_state.step) == 1, first.message)
	_check("replayed turn fails closed", _move("turn", value).reason == &"invalid_move")
	var req := ActionRequest.make("t06_dup", 1, actor.id, &"task_move", STATION,
		{"generation": int(_task().fault_generation), "move": "turn", "value": 2 * SHIFT + int(turn[0]) * 4 + posmod(int(_task().puzzle_state.rot[turn[0]]) + 1, 4)})
	var once := services.session.submit(req)
	_check("duplicate request id applies once", once.ok and services.session.submit(req).duplicate and int(_task().puzzle_state.step) == 2)
	var moves := 0
	var failures := 0
	while moves < 120:
		var next: Array = _next_turn(_task())
		if next.is_empty() or float(_task().progress) >= 1.0:
			break
		var now := RULE.state_of(_task())
		var result := _move("turn", (int(now.step) + 1) * SHIFT + int(next[0]) * 4 + posmod(int(now.rot[next[0]]) + int(next[1]), 4))
		if not result.ok:
			failures += 1
		moves += 1
	_check("solve path completes", float(_task().progress) >= 1.0 and failures == 0, "moves %d failures %d progress %s" % [moves, failures, _task().progress])
	_check("first_completed set", bool(_task().first_completed) and not PuzzleRegistry.is_broken(services.state(), TASK))
	_check("water reaches the rack", (_task().puzzle_state.water as Array).has(int(_task().puzzle_state.rack_row) * RULE.COLS + RULE.COLS - 1))
	services.request(&"task_claim", STATION, {"generation": int(_task().fault_generation)})
	_check("moves after completion are refused", _move("reset", (int(_task().puzzle_state.step) + 1) * SHIFT).reason == &"task_complete")


func _save_checks() -> void:
	services.request(&"task_claim", STATION, {"generation": int(_task().fault_generation)})
	var st := RULE.state_of(_task())
	var next: Array = _next_turn(_task())
	var result := _move("turn", SHIFT + int(next[0]) * 4 + posmod(int(st.rot[next[0]]) + 1, 4))
	_check("partial move accepted", result.ok and not (_task().puzzle_state as Dictionary).is_empty())
	_check("rule does not resume", not RULE.supports_resume() and not bool(_task().resume_supported))
	var saved: Dictionary = services.snapshot().colony.repair.tasks[TASK]
	_check("save projection drops the unfinished board", float(saved.progress) == 0.0 and (saved.puzzle_state as Dictionary).is_empty())
	services.restore(services.snapshot())
	_check("reloaded board is the seeded start", RULE.state_of(_task()).rot == RULE.layout(int(_task().puzzle_seed)).start)


func _panel_checks() -> void:
	root.size = Vector2i(1280, 720)
	ui = UiRoot.new()
	root.add_child(ui)
	var settings := GameSettings.new()
	settings.reduce_motion = true
	ui.setup(services, settings)
	await _frames()
	root.size = Vector2i(1280, 720)
	await _frames()
	var panel := PuzzleRegistry.make_panel(TASK, STATION, services)
	_check("panel builds headless", panel != null and panel.get("tiles") is Array and (panel.get("tiles") as Array).size() == RULE.COLS * RULE.ROWS)
	_check("panel claims the task on open", services.session.repair_runtime.locks.has(TASK))
	ui.open(panel)
	await _frames(6)
	var issues := UiLayoutCheck.problems(panel, root.get_visible_rect().size)
	print("INFO canvas %s panel %s" % [root.get_visible_rect().size, panel.get_global_rect()])
	_check("panel fits 1280x720", issues.is_empty(), " | ".join(issues))
	_check("panel focus styles", UiLayoutCheck.focus_problems(panel).is_empty())
	var tiles: Array = panel.get("tiles")
	(tiles[0] as Control).grab_focus()
	await _frames()
	_key(KEY_RIGHT)
	await _frames()
	_check("arrow keys move between pipes", root.gui_get_focus_owner() == tiles[1], str(root.gui_get_focus_owner()))
	var presses := 0
	var used_q := false
	while presses < 120:
		var next: Array = _next_turn(_task())
		if next.is_empty() or float(_task().progress) >= 1.0:
			break
		(tiles[int(next[0])] as Control).grab_focus()
		await _frames(1)
		used_q = used_q or int(next[1]) < 0
		_key(KEY_Q if int(next[1]) < 0 else KEY_ENTER)
		await _frames(2)
		presses += 1
	_check("keyboard solves the board through the host", float(_task().progress) >= 1.0 and bool(_task().first_completed), "presses %d progress %s" % [presses, _task().progress])
	_check("panel shows the host's completion", bool(panel.get("succeeded")) and "Complete" in panel.status_label.text)
	_check("hint names the water", "flowing" in (panel.get("hint_label") as Label).text, (panel.get("hint_label") as Label).text)
	print("INFO keyboard presses %d, used Q %s" % [presses, used_q])
	ui.close_all()
	await _frames()
