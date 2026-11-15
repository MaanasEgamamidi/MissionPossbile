extends SceneTree
## T02 Wires puzzle: host rule, the real SessionService path (actor at the station, role gate), and the panel's
## keyboard path. Run: godot --headless --path . --script res://tests/test_puzzle_t02.gd

const Rule := preload("res://scripts/tasks/puzzles/t02_rule.gd")
const TASK := "T02"
const STATION := &"repair_t02"
const SAVE_DIR := "res://_test_saves/puzzle_t02"


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
	root.push_input(event, true)
	var released := event.duplicate() as InputEventKey
	released.pressed = false
	root.push_input(released)


func _mouse(button: MouseButton, at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = at
	event.global_position = at
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)


func _motion(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


func _task(seed_value: int, puzzle := {}) -> Dictionary:
	return {"task_id": TASK, "puzzle_seed": seed_value, "puzzle_state": puzzle, "progress": 0.0}


## Applies a move to a task copy like RepairRuntime does; returns the rule's answer.
func _apply(task: Dictionary, move_name: String, value: int) -> Dictionary:
	var result := Rule.validate(task.duplicate(true), {"move": move_name, "value": value})
	if bool(result.get("accepted", false)):
		task.puzzle_state = result.puzzle_state
		task.progress = result.progress
	return result


func _pairs(lay: Dictionary) -> Array:
	var moves: Array = []
	for i in Rule.PAIRS:
		moves.append(i * 10 + (lay.right as Array).find(lay.left[i]))
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
	var varied := {}
	var shuffled := true
	for seed_value in 60:
		var a := Rule.layout(seed_value * 7919 + 3)
		same = same and a == Rule.layout(seed_value * 7919 + 3)
		varied[str(a)] = true
		var left_sorted: Array = (a.left as Array).duplicate()
		left_sorted.sort()
		shuffled = shuffled and a.left != a.right and left_sorted == [0, 1, 2, 3]
	_check("layout deterministic per seed", same)
	_check("layouts vary across seeds", varied.size() > 10, "%d" % varied.size())
	_check("right side is a real shuffle of the left", shuffled)
	var task := _task(1234)
	var lay := Rule.layout(1234)
	var correct := _pairs(lay)
	var wrong_right := (int(correct[0]) % 10 + 1) % Rule.PAIRS
	_check("wrong pair rejected", not bool(_apply(task, "connect", wrong_right).accepted) and task.progress == 0.0)
	for forged: int in [-1, 34, 40, 4, 99, 1000, -10]:
		_check("forged terminal id %d rejected" % forged, not bool(_apply(task, "connect", forged).accepted))
	_check("unknown move rejected", not bool(_apply(task, "complete", 1).accepted))
	_check("reset needs value 0", not bool(_apply(task, "reset", 5).accepted))
	var first := _apply(task, "connect", int(correct[0]))
	_check("correct pair accepted with partial progress", bool(first.accepted) and is_equal_approx(float(first.progress), 0.25) and not bool(first.complete))
	_check("replayed connection rejected", not bool(_apply(task, "connect", int(correct[0])).accepted))
	# Same right plug from a different left cable: uniqueness.
	_check("plug used twice rejected", not bool(_apply(task, "connect", 10 + int(correct[0]) % 10).accepted))
	_check("damaged saved links are cleaned", Rule.links_of({"puzzle_seed": 1234, "puzzle_state": {"links": [0, 0, 0, 0]}}).count(-1) >= 3)
	for k in range(1, Rule.PAIRS):
		var r := _apply(task, "connect", int(correct[k]))
		if k < Rule.PAIRS - 1:
			_check("pair %d keeps puzzle open" % k, bool(r.accepted) and not bool(r.complete) and float(r.progress) < 1.0)
		else:
			_check("all four pairs complete", bool(r.accepted) and bool(r.complete) and float(r.progress) == 1.0)
	_check("finished puzzle rejects further moves", not bool(_apply(task, "reset", 0).accepted))
	var again := _task(1234)
	_apply(again, "connect", int(correct[1]))
	_check("reset releases every cable", bool(_apply(again, "reset", 0).accepted) and Rule.links_of(again).count(-1) == Rule.PAIRS)


func _host_checks() -> void:
	services = GameServices.new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	services.saves = SaveService.new(ProjectSettings.globalize_path(SAVE_DIR), "colony", 1)
	root.add_child(services)
	services.start_new_game(4202)
	await _frames()
	var state := services.state()
	var station: Dictionary = state.stations.get(String(STATION), {})
	_check("station exists in state", not station.is_empty() and String(station.get("task_id", "")) == TASK)
	_check("puzzle installed and spot broken", PuzzleRegistry.has_puzzle(TASK) and PuzzleRegistry.is_broken(state, TASK))
	var at := CharacterState._v3(station.get("position", [0, 0, 0]))
	var actor := services.local_character()
	actor.position = at
	actor.specialty = &"medical_life_support"
	var gen := int(state.repair.tasks[TASK].fault_generation)
	var blocked := services.request(&"task_claim", STATION, {"generation": gen})
	_check("medical specialist blocked (solo)", blocked.reason == &"wrong_specialty", String(blocked.reason))
	services.session.peer_joined(2)
	var helper := state.character(&"crew_2")
	helper.owner_peer = 2
	helper.position = at
	for role: StringName in [&"biology_food", &"field_engineering_geology"]:
		helper.specialty = role
		var r := services.session.request(&"task_claim", STATION, {"generation": gen}, 2)
		_check("%s blocked (co-op peer)" % role, r.reason == &"wrong_specialty", String(r.reason))
	actor.specialty = &"electrical_comms"
	var claim := services.request(&"task_claim", STATION, {"generation": gen})
	_check("electrical specialist at the station claims", claim.ok, "%s %s" % [claim.reason, claim.message])
	var lay := Rule.layout(int(state.repair.tasks[TASK].puzzle_seed))
	var correct := _pairs(lay)
	var forged := services.request(&"task_move", STATION, {"generation": gen, "move": "connect", "value": int(correct[0]), "complete": true})
	_check("completion flag parameter rejected", forged.reason == &"bad_request", String(forged.reason))
	var wrong := services.request(&"task_move", STATION, {"generation": gen, "move": "connect", "value": (int(correct[0]) % 10 + 1) % 4})
	_check("wrong pair fails closed on host", wrong.reason == &"invalid_move" and float(state.repair.tasks[TASK].progress) == 0.0)
	var out := services.request(&"task_move", STATION, {"generation": gen, "move": "connect", "value": 77})
	_check("out-of-range terminal fails closed on host", out.reason == &"invalid_move")
	var first := services.request(&"task_move", STATION, {"generation": gen, "move": "connect", "value": int(correct[0])})
	_check("correct pair accepted on host", first.ok and is_equal_approx(float(state.repair.tasks[TASK].progress), 0.25))
	var saved := RepairCatalog.for_save(state.to_dict().repair)
	_check("partial wiring kept in save projection (resume)", float(saved.tasks[TASK].progress) == 0.25 and Rule.links_of(saved.tasks[TASK]).count(-1) == 3)
	var replay := services.request(&"task_move", STATION, {"generation": gen, "move": "connect", "value": int(correct[0])})
	_check("fresh replay of a used move fails", replay.reason == &"invalid_move")
	var last: ActionResult = null
	for k in range(1, Rule.PAIRS):
		var request := ActionRequest.make("t02_finish_%d" % k, 1, actor.id, &"task_move", STATION, {"generation": gen, "move": "connect", "value": int(correct[k])})
		last = services.session.submit(request)
		if k == Rule.PAIRS - 1:
			_check("duplicate request id applies once", services.session.submit(request).duplicate)
	_check("solve completes through SessionService", last != null and last.ok and bool(last.changes.get("first_completion", false)))
	_check("first_completed set and spot no longer broken", bool(state.repair.tasks[TASK].first_completed) and not PuzzleRegistry.is_broken(state, TASK))
	services.request(&"task_claim", STATION, {"generation": gen})
	var after := services.request(&"task_move", STATION, {"generation": gen, "move": "connect", "value": int(correct[0])})
	_check("moves after completion rejected", not after.ok and after.reason == &"task_complete", String(after.reason))
	services.session.peer_left(2)


func _panel_checks() -> void:
	services.start_new_game(4271)
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
	_check("E opens the T02 mini-game while broken", panel != null and (panel.get_script() as Script).resource_path.ends_with("t02_panel.gd"))
	if panel == null:
		return
	ui.open(panel)
	await _frames(8)
	var wires := panel as TaskPanel
	_check("panel builds headless with four cables and plugs", wires.get("left_buttons").size() == 4 and wires.get("right_buttons").size() == 4)
	_check("panel claimed the task on open", services.session.repair_runtime.locks.has(TASK))
	var issues := UiLayoutCheck.problems(panel, root.get_visible_rect().size)
	_check("layout fits 1280x720", issues.is_empty(), " | ".join(issues))
	_check("first focus is a cable", root.gui_get_focus_owner() == wires.get("left_buttons")[0])
	var lay := Rule.layout(int(state.repair.tasks[TASK].puzzle_seed))
	var left_buttons: Array = wires.get("left_buttons")
	var right_buttons: Array = wires.get("right_buttons")
	# A wrong plug by keyboard: explained and released.
	var wrong_j := ((lay.right as Array).find(lay.left[0]) + 1) % 4
	(left_buttons[0] as Button).grab_focus()
	_key(KEY_ENTER)
	await _frames()
	(right_buttons[wrong_j] as Button).grab_focus()
	_key(KEY_ENTER)
	await _frames()
	_check("wrong plug explained and released", wires.status_label.text.contains("Not that one") and Rule.links_of(state.repair.tasks[TASK]).count(-1) == 4, wires.status_label.text)
	# Mouse drag: press on cable 0, move onto its plug, release there.
	var plug0 := right_buttons[(lay.right as Array).find(lay.left[0])] as Button
	_mouse(MOUSE_BUTTON_LEFT, (left_buttons[0] as Button).get_global_rect().get_center(), true)
	await _frames(1)
	_motion((left_buttons[0] as Button).get_global_rect().get_center() + Vector2(40, 0))
	_motion(plug0.get_global_rect().get_center())
	await _frames(1)
	_mouse(MOUSE_BUTTON_LEFT, plug0.get_global_rect().get_center(), false)
	await _frames()
	_check("dragging a cable onto its plug connects it", Rule.links_of(state.repair.tasks[TASK]).count(-1) == 3, wires.status_label.text)
	for i in range(1, Rule.PAIRS):
		(left_buttons[i] as Button).grab_focus()
		_key(KEY_ENTER)
		await _frames()
		(right_buttons[(lay.right as Array).find(lay.left[i])] as Button).grab_focus()
		_key(KEY_ENTER)
		await _frames()
	_check("keyboard path solves T02 through SessionService", bool(state.repair.tasks[TASK].first_completed) and wires.succeeded, wires.status_label.text)
	ui.close_all()
	await _frames()
	ui.queue_free()
