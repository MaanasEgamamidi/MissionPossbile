extends SceneTree
## T04 Circuits puzzle: host rule (solvability over 300 seeds, route + voltage, piece limits), the real
## SessionService path (actor at the station, role gate), and the panel's keyboard path.
## Run: godot --headless --path . --script res://tests/test_puzzle_t04.gd

const Rule := preload("res://scripts/tasks/puzzles/t04_rule.gd")
const TASK := "T04"
const STATION := &"repair_t04"
const SAVE_DIR := "res://_test_saves/puzzle_t04"


class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR or error_type == ERROR_TYPE_SCRIPT:
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _passed := 0
var _total := 0
var _catcher := ErrorCatcher.new()
var services: GameServices


func _check(label: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
	print(("PASS " if ok else "FAIL ") + label + (": " + detail if not detail.is_empty() and not ok else ""))


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


func _task(seed_value: int, puzzle := {}) -> Dictionary:
	return {"task_id": TASK, "puzzle_seed": seed_value, "puzzle_state": puzzle, "progress": 0.0}


## Applies a move to a task copy like RepairRuntime does; returns the rule's answer.
func _apply(task: Dictionary, move_name: String, value: int) -> Dictionary:
	var result := Rule.validate(task.duplicate(true), {"move": move_name, "value": value})
	if bool(result.get("accepted", false)):
		task.puzzle_state = result.puzzle_state
		task.progress = result.progress
	return result


func _solution_moves(lay: Dictionary) -> Array:
	var moves: Array = []
	for step: Dictionary in lay.solution:
		moves.append(int(step.cell) * 100 + int(step.slot) * 10 + int(step.rot))
	return moves


func _initialize() -> void:
	OS.add_logger(_catcher)
	PlayerInput.ensure_actions()
	_rule_checks()
	await _host_checks()
	await _panel_checks()
	if services != null:
		services.saves.delete_all()
		services.queue_free()
	await _frames()
	UiTheme.release()
	_check("no script or engine errors", _catcher.errors.is_empty(), " | ".join(_catcher.errors))
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


func _rule_checks() -> void:
	_check("supports resume", Rule.supports_resume())
	var same := true
	var solvable := true
	var sound := true
	var varied := {}
	var detail := ""
	for n in 300:
		var seed_value := n * 104729 + 11
		var lay := Rule.layout(seed_value)
		same = same and lay == Rule.layout(seed_value)
		varied[str([lay.source_row, lay.load_row, lay.path])] = true
		# Every board is solvable: replaying the known solution through the rule completes it.
		var task := _task(seed_value)
		var result := {}
		for value: int in _solution_moves(lay):
			result = _apply(task, "place", value)
			if not bool(result.accepted):
				break
		if not bool(result.get("complete", false)):
			solvable = false
			detail = "seed %d" % seed_value
		# Fixed cells are on the route, blocked cells are not, and the target is base + the route's parts.
		for cell: int in (lay.fixed as Dictionary).keys():
			sound = sound and (lay.path as Array).has(cell)
		for cell: int in lay.blocked:
			sound = sound and not (lay.path as Array).has(cell)
		sound = sound and int(lay.target) > Rule.BASE_VOLTS
	_check("layout deterministic per seed", same)
	_check("layouts vary across seeds", varied.size() > 50, "%d" % varied.size())
	_check("300 seeded boards are all solvable by their known solution", solvable, detail)
	_check("fixed cells on the route, blocked cells off it", sound)
	var lay := Rule.layout(777)
	var moves := _solution_moves(lay)
	var task := _task(777)
	# Pick a voltage part of the solution and the -1 V decoy slot.
	var decoy := (lay.slots as Array).size() - 1
	var volt_index := -1
	for k in moves.size():
		if int(lay.slots[int(moves[k]) / 10 % 10].kind) == Rule.VOLT:
			volt_index = k
	# Connected route with the wrong voltage fails.
	for k in moves.size():
		var value := int(moves[k])
		if k == volt_index:
			value = (value / 100) * 100 + decoy * 10 + value % 10
		_apply(task, "place", value)
	var board := Rule.board_of(task, lay)
	var wrong_volts := Rule.trace(lay, board)
	_check("connected route with wrong voltage does not complete", bool(wrong_volts.connected) and int(wrong_volts.volts) != int(lay.target) and float(task.progress) < 1.0, str(wrong_volts))
	# Swap the decoy back for the right part: remove + place, inventory never duplicates.
	var cell := int(moves[volt_index]) / 100
	_check("remove takes the decoy back", bool(_apply(task, "remove", cell).accepted) and Rule.remaining(lay, Rule.board_of(task, lay), decoy) == 1)
	_check("remove of an empty cell rejected", not bool(_apply(task, "remove", cell).accepted))
	# Correct voltage without a connected route fails: leave out one plain route cell (turned the wrong way).
	var plain_index := 0 if volt_index != 0 else 1
	var plain_cell := int(moves[plain_index]) / 100
	_apply(task, "remove", plain_cell)
	var done := _apply(task, "place", int(moves[volt_index]))
	var open_route := Rule.trace(lay, Rule.board_of(task, lay))
	_check("right parts without a connected route do not complete", bool(done.accepted) and not bool(done.complete) and not bool(open_route.connected))
	# Pieces are limited: the slot of the removed piece has exactly the spare left.
	var slot := int(moves[plain_index]) / 10 % 10
	var left_before := Rule.remaining(lay, Rule.board_of(task, lay), slot)
	_check("inventory counts the removed piece once", left_before >= 1)
	_check("fixed cell cannot take a piece", (lay.fixed as Dictionary).is_empty() or not bool(_apply(task, "place", int((lay.fixed as Dictionary).keys()[0]) * 100 + slot * 10).accepted))
	_check("blocked cell cannot take a piece", not bool(_apply(task, "place", int(lay.blocked[0]) * 100 + slot * 10).accepted))
	_check("fixed piece cannot be turned or removed", (lay.fixed as Dictionary).is_empty() or (not bool(_apply(task, "rotate", int((lay.fixed as Dictionary).keys()[0])).accepted) and not bool(_apply(task, "remove", int((lay.fixed as Dictionary).keys()[0])).accepted)))
	for forged: int in [-1, 2000, 2004, 1990 + 9, 100 * 5 + 90, 7]:
		_check("forged place %d rejected" % forged, not bool(_apply(task, "place", forged).accepted))
	_check("rotate out of range rejected", not bool(_apply(task, "rotate", 20).accepted) and not bool(_apply(task, "rotate", -3).accepted))
	_check("unknown move rejected", not bool(_apply(task, "complete", 0).accepted))
	# Turned wrong, then turned right: rotate is a quarter turn.
	var rot_result := _apply(task, "place", (int(moves[plain_index]) / 10) * 10 + (int(moves[plain_index]) % 10 + 3) % 4)
	_check("wrongly turned piece leaves the route open", bool(rot_result.accepted) and not bool(rot_result.complete))
	var finish := _apply(task, "rotate", plain_cell)
	_check("quarter turn closes the route and completes", bool(finish.accepted) and bool(finish.complete) and float(finish.progress) == 1.0, str(Rule.trace(lay, Rule.board_of(task, lay))))
	_check("finished puzzle rejects further moves", not bool(_apply(task, "reset", 0).accepted))
	# Over-use: place every straight the inventory has, one more is rejected.
	var greedy := _task(777)
	var free_cells: Array = []
	for c in Rule.GRID_W * Rule.GRID_H:
		if not (lay.fixed as Dictionary).has(c) and not (lay.blocked as Array).has(c):
			free_cells.append(c)
	var placed := 0
	var over := false
	for c: int in free_cells:
		var r := _apply(greedy, "place", c * 100 + 0 * 10 + 0)
		if bool(r.accepted):
			placed += 1
		else:
			over = true
			break
	_check("piece limit enforced", over and placed == int(lay.slots[0].count), "%d of %d" % [placed, int(lay.slots[0].count)])
	_check("reset restores the full inventory", bool(_apply(greedy, "reset", 0).accepted) and Rule.remaining(lay, Rule.board_of(greedy, lay), 0) == int(lay.slots[0].count))
	var damaged := Rule.board_of({"puzzle_state": {"board": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]}}, lay)
	_check("damaged saved board cannot create pieces", Rule.remaining(lay, damaged, 0) >= 0)


func _host_checks() -> void:
	services = GameServices.new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	services.saves = SaveService.new(ProjectSettings.globalize_path(SAVE_DIR), "colony", 1)
	root.add_child(services)
	services.start_new_game(4404)
	await _frames()
	var state := services.state()
	var station: Dictionary = state.stations.get(String(STATION), {})
	_check("station exists in state", not station.is_empty() and String(station.get("task_id", "")) == TASK)
	_check("puzzle installed and spot broken", PuzzleRegistry.has_puzzle(TASK) and PuzzleRegistry.is_broken(state, TASK))
	var at := CharacterState._v3(station.get("position", [0, 0, 0]))
	var actor := services.local_character()
	actor.position = at
	var gen := int(state.repair.tasks[TASK].fault_generation)
	for role: StringName in [&"medical_life_support", &"biology_food", &"field_engineering_geology"]:
		actor.specialty = role
		var r := services.request(&"task_claim", STATION, {"generation": gen})
		_check("%s blocked" % role, r.reason == &"wrong_specialty", String(r.reason))
	services.session.peer_joined(2)
	var helper := state.character(&"crew_2")
	helper.owner_peer = 2
	helper.position = at
	helper.specialty = &"biology_food"
	_check("biologist blocked in co-op", services.session.request(&"task_claim", STATION, {"generation": gen}, 2).reason == &"wrong_specialty")
	services.session.peer_left(2)
	actor.specialty = &"electrical_comms"
	var claim := services.request(&"task_claim", STATION, {"generation": gen})
	_check("electrical specialist at the station claims", claim.ok, "%s %s" % [claim.reason, claim.message])
	var lay := Rule.layout(int(state.repair.tasks[TASK].puzzle_seed))
	var moves := _solution_moves(lay)
	var forged := services.request(&"task_move", STATION, {"generation": gen, "move": "place", "value": int(moves[0]), "complete": true})
	_check("completion flag parameter rejected", forged.reason == &"bad_request", String(forged.reason))
	var bad := services.request(&"task_move", STATION, {"generation": gen, "move": "place", "value": int(lay.blocked[0]) * 100})
	_check("blocked cell fails closed on host", bad.reason == &"invalid_move")
	var first := services.request(&"task_move", STATION, {"generation": gen, "move": "place", "value": int(moves[0])})
	_check("first piece accepted on host", first.ok and float(state.repair.tasks[TASK].progress) > 0.0 and float(state.repair.tasks[TASK].progress) < 1.0)
	var saved := RepairCatalog.for_save(state.to_dict().repair)
	_check("partial board kept in save projection (resume)", float(saved.tasks[TASK].progress) > 0.0 and int(Rule.board_of(saved.tasks[TASK], lay)[int(moves[0]) / 100]) >= 0)
	var replay := services.request(&"task_move", STATION, {"generation": gen, "move": "place", "value": int(moves[0])})
	_check("fresh replay of a placement fails (cell taken)", replay.reason == &"invalid_move")
	var last: ActionResult = null
	for k in range(1, moves.size()):
		last = services.session.submit(ActionRequest.make("t04_finish_%d" % k, 1, actor.id, &"task_move", STATION, {"generation": gen, "move": "place", "value": int(moves[k])}))
	_check("solve completes through SessionService", last != null and last.ok and bool(last.changes.get("first_completion", false)))
	_check("first_completed set and spot no longer broken", bool(state.repair.tasks[TASK].first_completed) and not PuzzleRegistry.is_broken(state, TASK))
	var dup := services.session.submit(ActionRequest.make("t04_finish_%d" % (moves.size() - 1), 1, actor.id, &"task_move", STATION, {"generation": gen, "move": "place", "value": int(moves[moves.size() - 1])}))
	_check("duplicate request id applies once", dup.duplicate)


func _panel_checks() -> void:
	services.start_new_game(4471)
	await _frames()
	var state := services.state()
	var station: Dictionary = state.stations[String(STATION)]
	var actor := services.local_character()
	actor.position = CharacterState._v3(station.position)
	actor.specialty = &"electrical_comms"
	var ui := UiRoot.new()
	root.add_child(ui)
	ui.setup(services, GameSettings.new())
	root.size = Vector2i(1280, 720)
	await _frames()
	var panel := StationPanels.for_station(STATION, services)
	_check("E opens the T04 mini-game while broken", panel != null and (panel.get_script() as Script).resource_path.ends_with("t04_panel.gd"))
	if panel == null:
		return
	ui.open(panel)
	await _frames(8)
	var board := panel as TaskPanel
	var cells: Array = board.get("cells")
	_check("panel builds headless with a 5 x 4 grid", cells.size() == Rule.GRID_W * Rule.GRID_H)
	_check("panel claimed the task on open", services.session.repair_runtime.locks.has(TASK))
	var issues := UiLayoutCheck.problems(panel, root.get_visible_rect().size)
	_check("layout fits 1280x720", issues.is_empty(), " | ".join(issues))
	var lay := Rule.layout(int(state.repair.tasks[TASK].puzzle_seed))
	_check("the meter shows the target voltage", int((board.call("meter") as Dictionary).target) == int(lay.target))
	for step: Dictionary in lay.solution:
		(cells[int(step.cell)] as Button).grab_focus()
		await _frames(1)
		if int(board.get("_hand_slot")) != int(step.slot):
			_key(KEY_1 + int(step.slot))
		var guard := 0
		while int(board.get("_hand_rot")) != int(step.rot) and guard < 4:
			_key(KEY_R)
			guard += 1
		_key(KEY_ENTER)
		await _frames(2)
	var record: Dictionary = state.repair.tasks[TASK]
	_check("keyboard path solves T04 through SessionService", bool(record.first_completed) and board.succeeded, "%s progress %s" % [board.status_label.text, record.progress])
	ui.close_all()
	await _frames()
	ui.queue_free()
