extends SceneTree
## T12 Seal (airlock exit-tunnel inner door) puzzle: seeded leak, host rule through a real SessionService with the field
## engineer at the repair_t12 station, specialty gate, fail-closed moves (wrong, forged, out-of-range, replayed), save
## projection (supports_resume), the panel solved by keyboard, and the S04 link: with the seal fault active an engineer
## standing on the safe side (no suit) solves it, the hazard keeps running for anyone in the vestibule, and completion
## clears T12.maintenance_fault so LocalPressure stops the leak and the vestibule repressurises.
## Run: godot --headless --path . --script res://tests/test_puzzle_t12.gd

const Rule := preload("res://scripts/tasks/puzzles/t12_rule.gd")
const TASK := "T12"
const STATION := &"repair_t12"

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
	var dir := ProjectSettings.globalize_path("res://_test_saves/puzzle_t12")
	DirAccess.make_dir_recursive_absolute(dir)
	services.saves = SaveService.new(dir, "colony", 1)
	root.add_child(services)
	services.start_new_game(91201, &"crew_4")
	await _frames()
	_session_checks()
	services.start_new_game(91203, &"crew_4")
	await _frames()
	_pressure_checks()
	await _panel_checks()
	services.saves.delete_all()
	if ui != null:
		ui.queue_free()
	services.queue_free()
	await _frames()
	UiTheme.release()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


## The full list of {move, payload} that solves a state (test only).
static func solution(state: Dictionary) -> Array:
	var moves: Array = [["find", int(state.leak)], ["fit", int(state.gap)]]
	var probe := state.duplicate(true)
	probe.fitted = true
	for i in Rule.POINTS:
		probe.pressed = i
		moves.append(["press", Rule.next_point(probe)])
	moves.append(["test", 0])
	return moves


func _rule_checks() -> void:
	_check("supports resume", Rule.supports_resume())
	_check("same seed, same leak", Rule.initial_state(31) == Rule.initial_state(31))
	var leaks := {}
	var gaps := {}
	var directions := {}
	for s in 60:
		var start := Rule.initial_state(3000 + s * 6151)
		leaks[int(start.leak)] = true
		gaps[int(start.gap)] = true
		directions[bool(start.reverse)] = true
	_check("seeds vary the leak, the gap and the press direction", leaks.size() == Rule.SECTIONS.size() and gaps.size() == Rule.SEALS.size() and directions.size() == 2)
	var task := {"puzzle_seed": 31, "puzzle_state": {}}
	var start := Rule.current_state(task)
	_check("rule: right section found", bool(Rule.validate(task, {"move": "find", "value": int(start.leak)}).accepted))
	_check("rule: wrong section refused", not bool(Rule.validate(task, {"move": "find", "value": (int(start.leak) + 1) % 6}).accepted))
	_check("rule: fitting before finding refused", not bool(Rule.validate(task, {"move": "fit", "value": int(start.gap)}).accepted))
	_check("rule: pressure check first refused", not bool(Rule.validate(task, {"move": "test", "value": 0}).accepted))
	_check("rule: section out of range refused", not bool(Rule.validate(task, {"move": "find", "value": 6}).accepted))
	var forged := {"puzzle_seed": 31, "puzzle_state": {"seed": 31, "step": 3, "found": false, "fitted": true, "pressed": 5, "tested": false}}
	var fixed := Rule.current_state(forged)
	_check("rule: forged skipped steps are not kept", not bool(fixed.fitted) and int(fixed.pressed) == 0)
	var moves := solution(start)
	var t := task.duplicate(true)
	var all_ok := true
	for k in moves.size():
		var r := Rule.validate(t, {"move": moves[k][0], "value": k * Rule.STEP_BASE + int(moves[k][1])})
		all_ok = all_ok and bool(r.accepted) and (bool(r.complete) == (k == moves.size() - 1))
		t.puzzle_state = r.get("puzzle_state", {})
	_check("rule: find, fit, 5 presses and the pressure check complete it", all_ok and moves.size() == 8)


func _move(peer: int, move: String, payload: int, step := -1) -> ActionResult:
	var s := services.session
	var task: Dictionary = s.state.repair.tasks[TASK]
	var at := int(Rule.current_state(task).step) if step < 0 else step
	return s.request(&"task_move", STATION, {"generation": int(task.fault_generation), "move": move, "value": at * Rule.STEP_BASE + payload}, peer)


func _session_checks() -> void:
	var s := services.session
	var task: Dictionary = s.state.repair.tasks[TASK]
	var gen := int(task.fault_generation)
	_check("T12 puzzle installed and broken at start", PuzzleRegistry.has_puzzle(TASK) and PuzzleRegistry.is_broken(s.state, TASK))
	var station: Dictionary = s.state.stations.get(String(STATION), {})
	_check("repair_t12 station exists", not station.is_empty() and String(station.get("task_id", "")) == TASK)
	var pos := CharacterState._v3(station.get("position", [0, 0, 0]))
	var engineer := services.local_character()
	_check("host plays the field engineer", String(engineer.specialty) == "field_engineering_geology")
	engineer.position = pos
	s.peer_joined(2)
	var medic := s.state.character(&"crew_2")
	medic.owner_peer = 2
	medic.position = pos
	_check("other specialty cannot claim T12", s.request(&"task_claim", STATION, {"generation": gen}, 2).reason == &"wrong_specialty")
	_check("other specialty cannot move T12", _move(2, "find", 0).reason == &"wrong_specialty")
	medic.owner_peer = 0
	var claim := s.request(&"task_claim", STATION, {"generation": gen})
	_check("engineer at the station claims T12", claim.ok, "%s %s (zone %s at %s)" % [claim.reason, claim.message, s.zone_at_position.call(pos) if s.zone_at_position.is_valid() else "-", pos])
	var start := Rule.current_state(task)
	var wrong_section := (int(start.leak) + 2) % Rule.SECTIONS.size()
	_check("forged completion flag rejected", s.request(&"task_move", STATION, {"generation": gen, "move": "test", "value": 0, "complete": true}).reason == &"bad_request")
	_check("unknown move fails closed", _move(1, "seal_all", 0).reason == &"invalid_move")
	_check("negative value fails closed", s.request(&"task_move", STATION, {"generation": gen, "move": "find", "value": -3}).reason == &"invalid_move")
	_check("out-of-range section fails closed", _move(1, "find", 17).reason == &"invalid_move")
	_check("wrong section fails closed", _move(1, "find", wrong_section).reason == &"invalid_move")
	_check("pressure check first fails closed", _move(1, "test", 0).reason == &"invalid_move")
	_check("future step fails closed", _move(1, "find", int(start.leak), 2).reason == &"invalid_move")
	_check("rejections changed nothing", (task.puzzle_state as Dictionary).is_empty() and float(task.progress) == 0.0)
	_check("leak found by the vapour", _move(1, "find", int(start.leak)).ok)
	_check("replayed find request fails closed", _move(1, "find", int(start.leak), 0).reason == &"invalid_move")
	_check("wrong seal fails closed", _move(1, "fit", (int(start.gap) + 1) % Rule.SEALS.size()).reason == &"invalid_move")
	_check("right seal fitted", _move(1, "fit", int(start.gap)).ok)
	var state := Rule.current_state(task)
	var out_of_order := Rule.POINTS - 1 - Rule.next_point(state)
	_check("pressing out of order fails closed", _move(1, "press", out_of_order).reason == &"invalid_move")
	_check("press point out of range fails closed", _move(1, "press", Rule.POINTS).reason == &"invalid_move")
	_check("first press", _move(1, "press", Rule.next_point(Rule.current_state(task))).ok)
	var before := Rule.current_state(task)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(RepairCatalog.for_save(s.state.repair)))
	var restored := RepairCatalog.restore(saved, s.state.rng_seed)
	_check("save keeps the half-done seal (supports_resume)", Rule.current_state(restored.tasks[TASK]) == before and is_equal_approx(float(restored.tasks[TASK].progress), float(task.progress)))
	s.state.repair = restored
	task = s.state.repair.tasks[TASK]
	var ok := true
	while int(Rule.current_state(task).pressed) < Rule.POINTS:
		ok = ok and _move(1, "press", Rule.next_point(Rule.current_state(task))).ok
	_check("whole edge pressed after the reload, not complete before the check", ok and float(task.progress) < 1.0 and not bool(task.first_completed))
	_check("pressure check completes T12", _move(1, "test", 0).ok and float(task.progress) >= 1.0 and bool(task.first_completed))
	_check("T12 no longer broken; seal fault clear", not PuzzleRegistry.is_broken(s.state, TASK) and float(task.condition) == 1.0 and not bool(task.maintenance_fault))
	_check("moves after completion refused", _move(1, "reset", 0).reason in [&"task_unclaimed", &"task_complete"])


## A standing point within reach of the station on the hangar side of the inner door: outside the vestibule volume (with
## its hysteresis), in a hangar/airlock zone, breathable while the vestibule is vented. Vector3.INF when none.
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


func _pressure_checks() -> void:
	var s := services.session
	var station: Dictionary = s.state.stations[String(STATION)]
	var station_pos := CharacterState._v3(station.position)
	var engineer := services.local_character()
	engineer.suit_on = false
	var safe := _safe_point(station_pos)
	_check("a safe-side spot within reach of repair_t12 exists", safe != Vector3.INF, "station %s, spot %s" % [station_pos, safe])
	# The brief moves repair_t12 onto the broken door (BP08) at (22.0, 0, 10.45), just inside the vestibule volume.
	var door_spot := Vector3(22.0, 0.04, 10.45)
	var door_safe := _safe_point(door_spot)
	_check("the BP08 door spot is reachable from the safe side too", door_safe != Vector3.INF, "door spot %s, spot %s, in vestibule %s" % [door_spot, door_safe, LocalPressure.VOLUME.has_point(door_spot)])
	if safe == Vector3.INF:
		return
	engineer.position = safe
	_check("S04 fault switch is the T12 seal fault", s.wear_runtime.force_fault(s, TASK, 0.4) and bool(s.state.repair.tasks[TASK].maintenance_fault))
	s.advance(1.5)
	var info := s.survival.pressure_info()
	_check("seal fault vents the vestibule", bool(info.leaking) and not bool(info.breathable), str(info))
	_check("unsuited engineer on the safe side is not exposed", not bool(s.survival.status(engineer.id).active) and s.survival.breathable_at(safe))
	# Someone without a suit inside the vestibule still gets the normal hazard: the puzzle grants no immunity.
	s.peer_joined(2)
	var visitor := s.state.character(&"crew_3")
	visitor.owner_peer = 2
	visitor.suit_on = false
	visitor.position = LocalPressure.VOLUME.get_center() * Vector3(1, 0, 1)
	var task: Dictionary = s.state.repair.tasks[TASK]
	var gen := int(task.fault_generation)
	var claim := s.request(&"task_claim", STATION, {"generation": gen})
	_check("engineer claims T12 from the safe side during the leak", claim.ok, "%s %s" % [claim.reason, claim.message])
	var start := Rule.current_state(task)
	var moves := solution(start)
	var ok := true
	for k in moves.size() - 1:
		ok = ok and _move(1, String(moves[k][0]), int(moves[k][1])).ok
		s.advance(0.1)
	_check("visitor in the vestibule is exposed while the seal is open", bool(s.survival.status(visitor.id).active))
	visitor.position = safe
	s.advance(0.1)
	_check("still leaking until the pressure check", ok and bool(s.survival.pressure_info().leaking) and not bool(task.first_completed))
	_check("pressure check completes T12 during the fault", _move(1, "test", 0).ok and bool(task.first_completed))
	_check("completion clears the seal fault S04 reads", not bool(task.maintenance_fault) and float(task.condition) == 1.0)
	s.advance(0.2)
	info = s.survival.pressure_info()
	_check("leak stopped; vestibule repressurising", not bool(info.leaking) and bool(info.repressurizing), str(info))
	s.advance(6.0)
	info = s.survival.pressure_info()
	_check("vestibule back to safe pressure", bool(info.breathable) and float(info.pressure_kpa) >= s.config.airlock_pressure_safe_kpa and String(info.status) == "Pressurized", str(info))
	_check("engineer never exposed", engineer.health > 0.0 and not bool(s.survival.status(engineer.id).active))
	visitor.owner_peer = 0
	s.peer_left(2)


func _press(button: Button) -> void:
	button.grab_focus()
	_key(KEY_ENTER)
	await _frames(2)


func _panel_checks() -> void:
	services.start_new_game(91202, &"crew_4")
	await _frames()
	var s := services.session
	var station: Dictionary = s.state.stations[String(STATION)]
	var station_pos := CharacterState._v3(station.position)
	var safe := _safe_point(station_pos)
	services.local_character().position = safe if safe != Vector3.INF else station_pos
	ui = UiRoot.new()
	root.add_child(ui)
	var settings := GameSettings.new()
	settings.reduce_motion = true
	ui.setup(services, settings)
	await _frames()
	var panel := StationPanels.for_station(STATION, services)
	_check("E at the broken spot opens the T12 mini-game", panel != null and panel.name == "T12SealPanel")
	root.size = Vector2i(1280, 720)
	ui.open(panel)
	await _frames(6)
	_check("panel claimed the task on open", s.repair_runtime.locks.has(TASK) and String(s.repair_runtime.locks[TASK].actor) == "crew_4")
	var issues := UiLayoutCheck.problems(panel, root.get_visible_rect().size)
	_check("panel layout fits 1280x720", issues.is_empty(), " | ".join(issues))
	_check("panel names the safe side and the suit", "hangar side" in panel.safety_label.text and "suit" in panel.safety_label.text, panel.safety_label.text)
	var task: Dictionary = s.state.repair.tasks[TASK]
	var start := Rule.current_state(task)
	var visited := {}
	panel.section_buttons[0].grab_focus()
	for i in 30:
		var focused := root.gui_get_focus_owner()
		if focused != null:
			visited[focused] = true
		_key(KEY_TAB)
	_check("Tab reaches every door section", panel.section_buttons.all(func(b: Button) -> bool: return visited.has(b)))
	panel.section_buttons[int(start.leak)].grab_focus()
	await _frames()
	_check("focusing the leaking part tells it in words", "vapour here" in panel.feel_label.text, panel.feel_label.text)
	var wrong := (int(start.leak) + 1) % Rule.SECTIONS.size()
	await _press(panel.section_buttons[wrong])
	_check("wrong section explained", "No vapour" in panel.status_label.text, panel.status_label.text)
	await _press(panel.section_buttons[int(start.leak)])
	_check("found: step 2 shown, focus follows", panel.seal_buttons[0].is_visible_in_tree() and not panel.section_buttons[0].is_visible_in_tree() and panel.seal_buttons.has(root.gui_get_focus_owner()))
	await _press(panel.seal_buttons[(int(start.gap) + 1) % Rule.SEALS.size()])
	_check("wrong seal explained", "too" in panel.status_label.text and "mm gap" in panel.status_label.text, panel.status_label.text)
	await _press(panel.seal_buttons[int(start.gap)])
	var state := Rule.current_state(task)
	await _press(panel.press_buttons[Rule.POINTS - 1 - Rule.next_point(state)])
	_check("press out of order explained", "Press point 1 next" in panel.status_label.text, panel.status_label.text)
	for i in Rule.POINTS:
		await _press(panel.press_buttons[Rule.next_point(Rule.current_state(task))])
	_check("whole edge pressed by keyboard; pressure check shown", int(Rule.current_state(task).pressed) == Rule.POINTS and panel.test_button.is_visible_in_tree())
	await _press(panel.test_button)
	_check("keyboard path solves T12 through the session", bool(task.first_completed) and float(task.progress) >= 1.0, panel.status_label.text)
	_check("panel shows the host's success", panel.succeeded and "Fixed" in panel.status_label.text)
	ui.close_all()
	await _frames()
