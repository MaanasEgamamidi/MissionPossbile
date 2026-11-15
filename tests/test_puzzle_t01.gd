extends SceneTree
## T01 Comms puzzle: host rule (false matches, ordered hold steps, transfer), the real SessionService path
## (any role, actor at the station), and the panel's keyboard path (slider + automatic hold/transfer).
## Run: godot --headless --path . --script res://tests/test_puzzle_t01.gd

const Rule := preload("res://scripts/tasks/puzzles/t01_rule.gd")
const TASK := "T01"
const STATION := &"repair_t01"
const SAVE_DIR := "res://_test_saves/puzzle_t01"


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
	_check("does not resume from disk (small puzzle restarts)", not Rule.supports_resume())
	var same := true
	var in_range := true
	var targets := {}
	for n in 200:
		var lay := Rule.layout(n * 6007 + 5)
		same = same and lay == Rule.layout(n * 6007 + 5)
		var gap := absi(int(lay.target) - Rule.START_DIAL)
		in_range = in_range and gap >= Rule.MIN_GAP and gap <= Rule.MAX_GAP and int(lay.target) >= 0 and int(lay.target) <= Rule.DIAL_MAX
		targets[int(lay.target)] = true
	_check("layout deterministic per seed", same)
	_check("target always reachable and away from the start", in_range)
	_check("targets vary across seeds", targets.size() > 20, "%d" % targets.size())
	var lay := Rule.layout(31)
	var target := int(lay.target)
	var task := _task(31)
	_check("hold without a match rejected (start dial is never a match)", not bool(_apply(task, "hold", 1).accepted))
	_check("tune out of range rejected", not bool(_apply(task, "tune", -1).accepted) and not bool(_apply(task, "tune", Rule.DIAL_MAX + 1).accepted))
	_check("unknown move rejected", not bool(_apply(task, "lock", 1).accepted))
	var near_miss := target + Rule.TOLERANCE + 1 if target + Rule.TOLERANCE + 1 <= Rule.DIAL_MAX else target - Rule.TOLERANCE - 1
	_check("tune just outside the window accepted", bool(_apply(task, "tune", near_miss).accepted))
	_check("false match cannot hold", not bool(_apply(task, "hold", 1).accepted))
	_check("transfer before lock rejected", not bool(_apply(task, "transfer", 1).accepted))
	_check("tune at the edge of the window", bool(_apply(task, "tune", target + Rule.TOLERANCE if target + Rule.TOLERANCE <= Rule.DIAL_MAX else target - Rule.TOLERANCE).accepted))
	_check("hold step 2 before step 1 rejected", not bool(_apply(task, "hold", 2).accepted))
	_check("hold step 1 on a real match accepted", bool(_apply(task, "hold", 1).accepted) and float(task.progress) > 0.0)
	_check("replayed hold step rejected", not bool(_apply(task, "hold", 1).accepted))
	_check("retune restarts the hold", bool(_apply(task, "tune", target).accepted) and int(task.puzzle_state.holds) == 0)
	for step in range(1, Rule.HOLD_STEPS + 1):
		_apply(task, "hold", step)
	_check("hold steps lock the link at half progress", bool(task.puzzle_state.locked) and is_equal_approx(float(task.progress), 0.5))
	_check("no tuning after the lock", not bool(_apply(task, "tune", target).accepted))
	_check("transfer block out of order rejected", not bool(_apply(task, "transfer", 2).accepted))
	var result := {}
	for step in range(1, Rule.TRANSFER_STEPS + 1):
		result = _apply(task, "transfer", step)
		if step < Rule.TRANSFER_STEPS:
			_check("transfer block %d keeps going" % step, bool(result.accepted) and not bool(result.complete))
	_check("last transfer block completes", bool(result.accepted) and bool(result.complete) and float(result.progress) == 1.0)
	_check("finished puzzle rejects further moves", not bool(_apply(task, "transfer", Rule.TRANSFER_STEPS + 1).accepted) and not bool(_apply(task, "reset", 0).accepted))
	var again := _task(31)
	_apply(again, "tune", target)
	_apply(again, "hold", 1)
	_check("reset returns to the start", bool(_apply(again, "reset", 0).accepted) and again.puzzle_state == Rule.initial_state())
	_check("damaged state cannot skip the lock", not bool(Rule.state_of({"puzzle_state": {"locked": true, "holds": 0, "sent": 3}}).locked))


func _host_checks() -> void:
	services = GameServices.new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	services.saves = SaveService.new(ProjectSettings.globalize_path(SAVE_DIR), "colony", 1)
	root.add_child(services)
	services.start_new_game(4101)
	await _frames()
	var state := services.state()
	var station: Dictionary = state.stations.get(String(STATION), {})
	_check("station exists in state", not station.is_empty() and String(station.get("task_id", "")) == TASK)
	_check("puzzle installed and spot broken", PuzzleRegistry.has_puzzle(TASK) and PuzzleRegistry.is_broken(state, TASK))
	var actor := services.local_character()
	actor.position = CharacterState._v3(station.get("position", [0, 0, 0]))
	actor.specialty = &"biology_food"
	var gen := int(state.repair.tasks[TASK].fault_generation)
	var claim := services.request(&"task_claim", STATION, {"generation": gen})
	_check("general task: a biologist at the station claims", claim.ok, "%s %s" % [claim.reason, claim.message])
	var far := actor.position
	actor.position = far + Vector3(20, 0, 0)
	var away := services.request(&"task_move", STATION, {"generation": gen, "move": "tune", "value": 10})
	_check("moves from far away fail", not away.ok)
	actor.position = far
	services.request(&"task_claim", STATION, {"generation": gen})
	var target := int(Rule.layout(int(state.repair.tasks[TASK].puzzle_seed)).target)
	var forged := services.request(&"task_move", STATION, {"generation": gen, "move": "transfer", "value": 1, "complete": true})
	_check("completion flag parameter rejected", forged.reason == &"bad_request", String(forged.reason))
	var off := clampi(target + 20, 0, Rule.DIAL_MAX) if target < 60 else target - 20
	services.request(&"task_move", STATION, {"generation": gen, "move": "tune", "value": off})
	var false_hold := services.request(&"task_move", STATION, {"generation": gen, "move": "hold", "value": 1})
	_check("false match hold fails closed on host", false_hold.reason == &"invalid_move" and float(state.repair.tasks[TASK].progress) == 0.0)
	_check("tune accepted on host", services.request(&"task_move", STATION, {"generation": gen, "move": "tune", "value": target}).ok)
	_check("hold 1 accepted on host", services.request(&"task_move", STATION, {"generation": gen, "move": "hold", "value": 1}).ok)
	var saved := RepairCatalog.for_save(state.to_dict().repair)
	_check("partial comms puzzle restarts in save projection", float(saved.tasks[TASK].progress) == 0.0 and (saved.tasks[TASK].puzzle_state as Dictionary).is_empty() and float(state.repair.tasks[TASK].progress) > 0.0)
	_check("replayed hold fails on host", services.request(&"task_move", STATION, {"generation": gen, "move": "hold", "value": 1}).reason == &"invalid_move")
	for step in range(2, Rule.HOLD_STEPS + 1):
		services.request(&"task_move", STATION, {"generation": gen, "move": "hold", "value": step})
	var last: ActionResult = null
	for step in range(1, Rule.TRANSFER_STEPS + 1):
		var request := ActionRequest.make("t01_transfer_%d" % step, 1, actor.id, &"task_move", STATION, {"generation": gen, "move": "transfer", "value": step})
		last = services.session.submit(request)
		if step == Rule.TRANSFER_STEPS:
			_check("duplicate request id applies once", services.session.submit(request).duplicate)
	_check("solve completes through SessionService", last != null and last.ok and bool(last.changes.get("first_completion", false)))
	_check("first_completed set and spot no longer broken", bool(state.repair.tasks[TASK].first_completed) and not PuzzleRegistry.is_broken(state, TASK))
	_check("only comms is repaired (wires untouched)", not bool(state.repair.tasks.T02.first_completed))


func _panel_checks() -> void:
	services.start_new_game(4171)
	await _frames()
	var state := services.state()
	var station: Dictionary = state.stations[String(STATION)]
	var actor := services.local_character()
	actor.position = CharacterState._v3(station.position)
	var ui := UiRoot.new()
	root.add_child(ui)
	ui.setup(services, GameSettings.new())
	root.size = Vector2i(1280, 720)
	await _frames()
	var panel := StationPanels.for_station(STATION, services)
	_check("E opens the T01 mini-game while broken", panel != null and (panel.get_script() as Script).resource_path.ends_with("t01_panel.gd"))
	if panel == null:
		return
	ui.open(panel)
	await _frames(8)
	var comms := panel as TaskPanel
	var slider := comms.get("slider") as HSlider
	_check("panel builds headless with a dial and a slider", slider != null and comms.get("dial") is Control)
	_check("panel claimed the task on open", services.session.repair_runtime.locks.has(TASK))
	var issues := UiLayoutCheck.problems(panel, root.get_visible_rect().size)
	_check("layout fits 1280x720", issues.is_empty(), " | ".join(issues))
	_check("first focus is the tuning slider", root.gui_get_focus_owner() == slider)
	var target := int(Rule.layout(int(state.repair.tasks[TASK].puzzle_seed)).target)
	var dial := comms.get("dial") as Control
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.position = dial.get_global_rect().get_center()
	wheel.global_position = wheel.position
	wheel.pressed = true
	root.push_input(wheel, true)
	await _frames()
	_check("mouse wheel on the dial turns it", int(slider.value) == Rule.START_DIAL + 1, "%d" % int(slider.value))
	slider.grab_focus()
	var steps := target - (Rule.START_DIAL + 1)
	for i in absi(steps):
		_key(KEY_RIGHT if steps > 0 else KEY_LEFT)
	await _frames()
	_check("arrow keys move the dial", int(slider.value) == target, "%d vs %d" % [int(slider.value), target])
	var waited := 0.0
	while not bool(state.repair.tasks[TASK].first_completed) and waited < 12.0:
		await create_timer(0.1).timeout
		waited += 0.1
	_check("keyboard path tunes, holds, locks and transfers through SessionService", bool(state.repair.tasks[TASK].first_completed) and comms.succeeded, "%s waited %.1f" % [comms.status_label.text, waited])
	ui.close_all()
	await _frames()
	ui.queue_free()
