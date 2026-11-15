extends SceneTree
## T10 Equipment (Med Bay plug-in) puzzle: seeded sockets, host rule through a real SessionService with a crew member at
## the repair_t10 station, any role may operate, fail-closed moves (wrong socket, forged, out-of-range, replayed), the
## self-test is required, save projection (supports_resume), and the panel solved by keyboard and by drag and drop.
## Run: godot --headless --path . --script res://tests/test_puzzle_t10.gd

const Rule := preload("res://scripts/tasks/puzzles/t10_rule.gd")
const TASK := "T10"
const STATION := &"repair_t10"

var _passed := 0
var _total := 0
var services: GameServices
var ui: UiRoot


func _check(label: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
	print(("PASS " if ok else "FAIL ") + label + (": " + detail if not detail.is_empty() else ""))


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


func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	_rule_checks()
	services = GameServices.new()
	var dir := ProjectSettings.globalize_path("res://_test_saves/puzzle_t10")
	DirAccess.make_dir_recursive_absolute(dir)
	services.saves = SaveService.new(dir, "colony", 1)
	root.add_child(services)
	services.start_new_game(91001, &"crew_1")
	await _frames()
	_session_checks()
	await _panel_checks()
	services.saves.delete_all()
	if ui != null:
		ui.queue_free()
	services.queue_free()
	await _frames()
	UiTheme.release()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


static func _socket_of(state: Dictionary, kind: int) -> int:
	return (state.sockets as Array).find(kind)


func _rule_checks() -> void:
	_check("supports resume", Rule.supports_resume())
	_check("same seed, same sockets", Rule.initial_state(55) == Rule.initial_state(55))
	var orders := {}
	var valid := true
	for s in 40:
		var start := Rule.initial_state(2000 + s * 104729)
		orders[str(start.sockets)] = true
		var sorted: Array = (start.sockets as Array).duplicate()
		sorted.sort()
		valid = valid and sorted == [0, 1, 2, 3] and start.plugged == [-1, -1]
	_check("40 seeds: each has all four sockets, nothing plugged", valid)
	_check("seeds shuffle the sockets", orders.size() >= 10, "%d orders" % orders.size())
	_check("look-alike sockets share a colour or a shape with each plug", Rule.KINDS[2][0] == Rule.KINDS[0][0] and Rule.KINDS[2][1] == Rule.KINDS[1][1] and Rule.KINDS[3][0] == Rule.KINDS[1][0] and Rule.KINDS[3][1] == Rule.KINDS[0][1])
	var task := {"puzzle_seed": 9, "puzzle_state": {}}
	var start := Rule.current_state(task)
	var green := _socket_of(start, 0)
	_check("rule: green round plug into its socket", bool(Rule.validate(task, {"move": "plug", "value": green}).accepted))
	for kind in [1, 2, 3]:
		_check("rule: green round plug refused by socket kind %d" % kind, not bool(Rule.validate(task, {"move": "plug", "value": _socket_of(start, kind)}).accepted))
	_check("rule: self-test with nothing plugged refused", not bool(Rule.validate(task, {"move": "test", "value": 0}).accepted))
	_check("rule: lead out of range refused", not bool(Rule.validate(task, {"move": "plug", "value": 20 + green}).accepted))
	_check("rule: socket out of range refused", not bool(Rule.validate(task, {"move": "plug", "value": 4}).accepted))
	_check("rule: payload over 99 refused", not bool(Rule.validate(task, {"move": "plug", "value": 100 + green}).accepted))
	var forged := {"puzzle_seed": 9, "puzzle_state": {"seed": 9, "step": 2, "plugged": [_socket_of(start, 3), _socket_of(start, 2)], "tested": false}}
	_check("rule: forged wrong plugs fall back to the seeded start", Rule.current_state(forged) == start)


func _move(peer: int, move: String, payload: int, step := -1) -> ActionResult:
	var s := services.session
	var task: Dictionary = s.state.repair.tasks[TASK]
	var at := int(Rule.current_state(task).step) if step < 0 else step
	return s.request(&"task_move", STATION, {"generation": int(task.fault_generation), "move": move, "value": at * Rule.STEP_BASE + payload}, peer)


func _session_checks() -> void:
	var s := services.session
	var task: Dictionary = s.state.repair.tasks[TASK]
	var gen := int(task.fault_generation)
	_check("T10 puzzle installed and broken at start", PuzzleRegistry.has_puzzle(TASK) and PuzzleRegistry.is_broken(s.state, TASK))
	var station: Dictionary = s.state.stations.get(String(STATION), {})
	_check("repair_t10 station exists", not station.is_empty() and String(station.get("task_id", "")) == TASK)
	var pos := CharacterState._v3(station.get("position", [0, 0, 0]))
	s.peer_joined(2)
	var everyone := true
	var detail := ""
	for id: StringName in [&"crew_2", &"crew_3", &"crew_4"]:
		var crew := s.state.character(id)
		crew.owner_peer = 2
		crew.position = pos
		var r := s.request(&"task_claim", STATION, {"generation": gen}, 2)
		everyone = everyone and r.ok
		if not r.ok:
			detail += "%s: %s %s; " % [crew.specialty, r.reason, r.message]
		s.request(&"task_release", STATION, {"generation": gen}, 2)
		crew.owner_peer = 0
	var host := services.local_character()
	host.position = pos
	var claim := s.request(&"task_claim", STATION, {"generation": gen})
	_check("every specialty can operate T10", everyone and claim.ok and String(host.specialty) == "electrical_comms", detail + "host %s %s (zone %s)" % [claim.reason, claim.message, s.zone_at_position.call(pos) if s.zone_at_position.is_valid() else "-"])
	var start := Rule.current_state(task)
	var green := _socket_of(start, 0)
	var blue := _socket_of(start, 1)
	_check("forged completion flag rejected", s.request(&"task_move", STATION, {"generation": gen, "move": "test", "value": 0, "complete": true}).reason == &"bad_request")
	_check("unknown move fails closed", _move(1, "power_on", 0).reason == &"invalid_move")
	_check("negative value fails closed", s.request(&"task_move", STATION, {"generation": gen, "move": "plug", "value": -1}).reason == &"invalid_move")
	_check("out-of-range socket fails closed", _move(1, "plug", 9).reason == &"invalid_move")
	_check("self-test before plugging fails closed", _move(1, "test", 0).reason == &"invalid_move")
	_check("wrong colour, same shape fails closed", _move(1, "plug", _socket_of(start, 3)).reason == &"invalid_move")
	_check("same colour, wrong shape fails closed", _move(1, "plug", _socket_of(start, 2)).reason == &"invalid_move")
	_check("future step fails closed", _move(1, "plug", green, 4).reason == &"invalid_move")
	_check("rejections changed nothing", (task.puzzle_state as Dictionary).is_empty() and float(task.progress) == 0.0)
	_check("green plug seated, screen powered", _move(1, "plug", green).ok and int(Rule.current_state(task).plugged[0]) == green and is_equal_approx(float(task.progress), Rule.PLUG_SHARE))
	_check("replayed plug request fails closed", _move(1, "plug", green, 0).reason == &"invalid_move")
	_check("second plug into a used socket fails closed", _move(1, "plug", 10 + green).reason == &"invalid_move")
	_check("blue plug in a wrong socket fails closed", _move(1, "plug", 10 + _socket_of(start, 2)).reason == &"invalid_move")
	var before := Rule.current_state(task)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(RepairCatalog.for_save(s.state.repair)))
	var restored := RepairCatalog.restore(saved, s.state.rng_seed)
	_check("save keeps the seated plug (supports_resume)", Rule.current_state(restored.tasks[TASK]) == before and is_equal_approx(float(restored.tasks[TASK].progress), Rule.PLUG_SHARE))
	s.state.repair = restored
	task = s.state.repair.tasks[TASK]
	_check("blue plug seated after the reload", _move(1, "plug", 10 + blue).ok)
	_check("plugging in alone does not finish (self-test needed)", float(task.progress) < 1.0 and not bool(task.first_completed))
	_check("self-test completes T10", _move(1, "test", 0).ok and float(task.progress) >= 1.0 and bool(task.first_completed))
	_check("T10 no longer broken; condition restored", not PuzzleRegistry.is_broken(s.state, TASK) and float(task.condition) == 1.0 and not s.repair_runtime.locks.has(TASK))
	_check("moves after completion refused", _move(1, "reset", 0).reason in [&"task_unclaimed", &"task_complete"])


func _press(button: Button) -> void:
	button.grab_focus()
	_key(KEY_ENTER)
	await _frames(2)


func _panel_checks() -> void:
	services.start_new_game(91002, &"crew_3")
	await _frames()
	var s := services.session
	var station: Dictionary = s.state.stations[String(STATION)]
	services.local_character().position = CharacterState._v3(station.position)
	ui = UiRoot.new()
	root.add_child(ui)
	var settings := GameSettings.new()
	settings.reduce_motion = true
	ui.setup(services, settings)
	await _frames()
	var panel := StationPanels.for_station(STATION, services)
	_check("E at the broken spot opens the T10 mini-game", panel != null and panel.name == "T10EquipmentPanel")
	root.size = Vector2i(1280, 720)
	ui.open(panel)
	await _frames(6)
	_check("panel claimed the task on open (biology crew)", s.repair_runtime.locks.has(TASK) and String(s.repair_runtime.locks[TASK].actor) == "crew_3")
	var issues := UiLayoutCheck.problems(panel, root.get_visible_rect().size)
	_check("panel layout fits 1280x720", issues.is_empty(), " | ".join(issues))
	var targets: Array = []
	targets.append_array(panel.lead_buttons)
	targets.append_array(panel.socket_buttons)
	targets.append(panel.test_button)
	var visited := {}
	targets[0].grab_focus()
	for i in 40:
		var focused := root.gui_get_focus_owner()
		if focused != null:
			visited[focused] = true
		_key(KEY_TAB)
	_check("Tab reaches every plug, socket and the self-test", targets.all(func(b: Button) -> bool: return visited.has(b)))
	var task: Dictionary = s.state.repair.tasks[TASK]
	var start := Rule.current_state(task)
	await _press(panel.lead_buttons[0])
	_check("keyboard picks up the green plug", panel.held == 0)
	await _press(panel.socket_buttons[_socket_of(start, 3)])
	var text: String = panel.status_label.text
	_check("wrong socket explained and the plug released", "wrong colour" in text.to_lower() and panel.held == -1 and int(Rule.current_state(task).plugged[0]) == -1, text)
	await _press(panel.test_button)
	_check("early self-test explained", "both machines" in panel.status_label.text, panel.status_label.text)
	await _press(panel.lead_buttons[0])
	await _press(panel.socket_buttons[_socket_of(start, 0)])
	_check("keyboard seats the green plug; heal station screen on", int(Rule.current_state(task).plugged[0]) == _socket_of(start, 0) and panel.device_state(0) == "on" and panel.device_state(1) == "off", panel.device_state(0))
	_check("drop refuses foreign drag data", not panel._can_drop(Vector2.ZERO, {"wire": 1}, 0))
	panel._drop(Vector2.ZERO, {"t10_lead": 1}, _socket_of(start, 1))
	await _frames(2)
	_check("drag and drop seats the blue plug", int(Rule.current_state(task).plugged[1]) == _socket_of(start, 1) and not bool(task.first_completed))
	await _press(panel.test_button)
	_check("keyboard self-test completes T10 through the session", bool(task.first_completed) and float(task.progress) >= 1.0, panel.status_label.text)
	_check("panel shows the host's success", panel.succeeded and "Fixed" in panel.status_label.text and panel.device_state(1) == "ok")
	ui.close_all()
	await _frames()
