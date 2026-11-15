extends SceneTree
## T03 Rings puzzle: host rule (stop time checked against the seeded spin, misses, wide window), the real
## SessionService path (any role, actor at the station), and the panel's keyboard path (STOP with Enter).
## Run: godot --headless --path . --script res://tests/test_puzzle_t03.gd

const Rule := preload("res://scripts/tasks/puzzles/t03_rule.gd")
const TASK := "T03"
const STATION := &"repair_t03"
const SAVE_DIR := "res://_test_saves/puzzle_t03"


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


## The stop value that hits ring `ring` exactly on its mark (its first pass), plus extra ms.
func _hit(lay: Dictionary, ring: int, extra_ms := 0) -> int:
	return ring * Rule.RING_FACTOR + int(lay.rings[ring].first_ms) + extra_ms


## Milliseconds the pointer needs to turn `degrees` on this ring.
func _ms_for(lay: Dictionary, ring: int, degrees: float) -> int:
	return int(ceil(degrees / float(lay.rings[ring].speed) * 1000.0))


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
	var on_mark := true
	var varied := {}
	for n in 200:
		var lay := Rule.layout(n * 15485863 + 9)
		same = same and lay == Rule.layout(n * 15485863 + 9)
		for ring in Rule.RINGS:
			on_mark = on_mark and Rule.offset_deg(lay.rings[ring], int(lay.rings[ring].first_ms)) < 0.01
		varied[str(lay.rings[0].mark)] = true
	_check("layout deterministic per seed", same)
	_check("pointer angle is a pure function: first pass lands on the mark", on_mark)
	_check("marks vary across seeds", varied.size() > 50, "%d" % varied.size())
	var lay := Rule.layout(99)
	var task := _task(99)
	var miss_ms := _ms_for(lay, 0, Rule.WINDOW_DEG + 6.0)
	_check("a miss is rejected and locks nothing", not bool(_apply(task, "stop", _hit(lay, 0, miss_ms)).accepted) and float(task.progress) == 0.0)
	_check("too early stop rejected", not bool(_apply(task, "stop", Rule.MIN_STOP_MS - 1).accepted))
	_check("over-long stop rejected", not bool(_apply(task, "stop", Rule.MAX_STOP_MS + 1).accepted))
	_check("negative value rejected", not bool(_apply(task, "stop", -5).accepted))
	_check("stop for a later ring rejected", not bool(_apply(task, "stop", _hit(lay, 1)).accepted))
	_check("ring index out of range rejected", not bool(_apply(task, "stop", 7 * Rule.RING_FACTOR + 1500).accepted))
	_check("unknown move rejected", not bool(_apply(task, "hit", 1).accepted))
	_check("assist value must be 0 or 1", not bool(_apply(task, "assist", 2).accepted))
	_check("wide window setting accepted", bool(_apply(task, "assist", 1).accepted) and bool(task.puzzle_state.assist))
	var wide_ms := _ms_for(lay, 0, Rule.WINDOW_DEG + 6.0)
	var wide := _apply(task, "stop", _hit(lay, 0, wide_ms))
	_check("wide window accepts a stop just outside the normal window", bool(wide.accepted) and int(task.puzzle_state.ring) == 1 and is_equal_approx(float(task.progress), 1.0 / 3.0))
	_check("replayed stop for a locked ring rejected", not bool(_apply(task, "stop", _hit(lay, 0, wide_ms)).accepted))
	_apply(task, "assist", 0)
	var period_ms := int(round(360.0 / float(lay.rings[1].speed) * 1000.0))
	_check("a later pass over the mark also hits", bool(_apply(task, "stop", _hit(lay, 1, period_ms)).accepted) and int(task.puzzle_state.ring) == 2)
	var last := _apply(task, "stop", _hit(lay, 2))
	_check("third ring completes", bool(last.accepted) and bool(last.complete) and float(last.progress) == 1.0)
	_check("finished puzzle rejects further moves", not bool(_apply(task, "reset", 0).accepted))
	var again := _task(99)
	_apply(again, "stop", _hit(lay, 0))
	_check("reset unlocks all rings", bool(_apply(again, "reset", 0).accepted) and int(again.puzzle_state.ring) == 0)


func _host_checks() -> void:
	services = GameServices.new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	services.saves = SaveService.new(ProjectSettings.globalize_path(SAVE_DIR), "colony", 1)
	root.add_child(services)
	services.start_new_game(4303)
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
	var lay := Rule.layout(int(state.repair.tasks[TASK].puzzle_seed))
	var forged := services.request(&"task_move", STATION, {"generation": gen, "move": "stop", "value": _hit(lay, 0), "hit": true})
	_check("hit flag parameter rejected", forged.reason == &"bad_request", String(forged.reason))
	var miss := services.request(&"task_move", STATION, {"generation": gen, "move": "stop", "value": _hit(lay, 0, _ms_for(lay, 0, 90.0))})
	_check("miss fails closed on host", miss.reason == &"invalid_move" and float(state.repair.tasks[TASK].progress) == 0.0)
	_check("hit locks ring 1 on host", services.request(&"task_move", STATION, {"generation": gen, "move": "stop", "value": _hit(lay, 0)}).ok)
	var saved := RepairCatalog.for_save(state.to_dict().repair)
	_check("locked ring kept in save projection (resume)", is_equal_approx(float(saved.tasks[TASK].progress), 1.0 / 3.0) and int(saved.tasks[TASK].puzzle_state.ring) == 1)
	_check("replayed ring-1 stop fails on host", services.request(&"task_move", STATION, {"generation": gen, "move": "stop", "value": _hit(lay, 0)}).reason == &"invalid_move")
	services.request(&"task_move", STATION, {"generation": gen, "move": "stop", "value": _hit(lay, 1)})
	var request := ActionRequest.make("t03_last", 1, actor.id, &"task_move", STATION, {"generation": gen, "move": "stop", "value": _hit(lay, 2)})
	var last := services.session.submit(request)
	_check("duplicate request id applies once", services.session.submit(request).duplicate)
	_check("solve completes through SessionService", last.ok and bool(last.changes.get("first_completion", false)))
	_check("first_completed set and spot no longer broken", bool(state.repair.tasks[TASK].first_completed) and not PuzzleRegistry.is_broken(state, TASK))
	_check("only the rings are repaired (circuits untouched)", not bool(state.repair.tasks.T04.first_completed))


func _panel_checks() -> void:
	services.start_new_game(4371)
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
	_check("E opens the T03 mini-game while broken", panel != null and (panel.get_script() as Script).resource_path.ends_with("t03_panel.gd"))
	if panel == null:
		return
	ui.open(panel)
	await _frames(8)
	var rings := panel as TaskPanel
	var stop := rings.get("stop_button") as Button
	_check("panel builds headless with a STOP button", stop != null and rings.get("dials") is Control)
	_check("panel claimed the task on open", services.session.repair_runtime.locks.has(TASK))
	var issues := UiLayoutCheck.problems(panel, root.get_visible_rect().size)
	_check("layout fits 1280x720", issues.is_empty(), " | ".join(issues))
	_check("first focus is STOP", root.gui_get_focus_owner() == stop)
	var lay := Rule.layout(int(state.repair.tasks[TASK].puzzle_seed))
	# A miss by keyboard: explained, ring restarts, nothing locks.
	rings.set("ring_start_ms", Time.get_ticks_msec() - int(lay.rings[0].first_ms) - _ms_for(lay, 0, 120.0))
	_key(KEY_ENTER)
	await _frames()
	_check("keyboard miss is explained and locks nothing", rings.status_label.text.contains("Missed") and int(Rule.state_of(state.repair.tasks[TASK]).ring) == 0, rings.status_label.text)
	_check("a miss restarts the active ring", int(rings.call("ring_time_ms")) < 1000)
	for ring in Rule.RINGS:
		# Start the ring's clock so the pointer reaches the mark now, then press Enter on STOP.
		rings.set("ring_start_ms", Time.get_ticks_msec() - int(lay.rings[ring].first_ms))
		_key(KEY_ENTER)
		await _frames()
	_check("keyboard path stops all three rings through SessionService", bool(state.repair.tasks[TASK].first_completed) and rings.succeeded, rings.status_label.text)
	ui.close_all()
	await _frames()
	ui.queue_free()
