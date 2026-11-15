extends SceneTree
## T12 Seal (airlock exit-tunnel inner door) puzzle: seeded leak and shuffled numbers 1-5 along it, host rule through a
## real SessionService with the field engineer at the repair_t12 station, specialty gate, fail-closed moves (wrong number,
## forged, out-of-range, replayed), reset, save projection (supports_resume), the panel's numbered seal points and its
## 10 s clock (time up -> Restart -> reset), the panel solved by keyboard, and the S04 link: with the seal fault active an engineer
## standing on the safe side (no suit) solves it, the hazard keeps running for anyone in the vestibule, and completion
## clears T12.maintenance_fault so LocalPressure stops the leak and the vestibule repressurises.
## Run: godot --headless --path . --script res://tests/test_puzzle_t12.gd

const Rule := preload("res://scripts/tasks/puzzles/t12_rule.gd")
const SealPanel := preload("res://scripts/tasks/puzzles/t12_panel.gd")
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


## The full list of {move, payload} that solves a state (test only): press 1, 2, 3, 4, 5.
static func solution(_state: Dictionary) -> Array:
	var moves: Array = []
	for n in Rule.POINTS:
		moves.append(["press", n + 1])
	return moves


func _rule_checks() -> void:
	_check("supports resume", Rule.supports_resume())
	_check("same seed, same leak and numbers", Rule.initial_state(31) == Rule.initial_state(31))
	var leaks := {}
	var orders := {}
	var shuffled_ok := true
	for s in 60:
		var seeded := Rule.initial_state(3000 + s * 6151)
		leaks[int(seeded.leak)] = true
		var order: Array = seeded.order
		orders[str(order)] = true
		var sorted := order.duplicate()
		sorted.sort()
		shuffled_ok = shuffled_ok and sorted == [1, 2, 3, 4, 5] and order != [1, 2, 3, 4, 5] and order != [5, 4, 3, 2, 1]
	_check("seeds vary the leaking section and the number order", leaks.size() == Rule.SECTIONS.size() and orders.size() >= 12, "%d sections, %d orders" % [leaks.size(), orders.size()])
	_check("numbers are 1-5 once each, never in plain left-to-right (or right-to-left) order", shuffled_ok)
	var task := {"puzzle_seed": 31, "puzzle_state": {}}
	var start := Rule.current_state(task)
	_check("spot_of / order_number / next_point agree", Rule.order_number(start, Rule.spot_of(start, 3)) == 3 and Rule.next_point(start) == Rule.spot_of(start, 1))
	_check("rule: number 1 first accepted", bool(Rule.validate(task, {"move": "press", "value": 1}).accepted))
	_check("rule: wrong number refused", not bool(Rule.validate(task, {"move": "press", "value": 2}).accepted))
	_check("rule: number 0 and 6 refused", not bool(Rule.validate(task, {"move": "press", "value": 0}).accepted) and not bool(Rule.validate(task, {"move": "press", "value": 6}).accepted))
	_check("rule: reset with nothing pressed refused", not bool(Rule.validate(task, {"move": "reset", "value": 0}).accepted))
	_check("rule: the old step moves are gone", not bool(Rule.validate(task, {"move": "find", "value": int(start.leak)}).accepted) and not bool(Rule.validate(task, {"move": "test", "value": 0}).accepted))
	var forged := {"puzzle_seed": 31, "puzzle_state": {"seed": 31, "step": 2, "leak": (int(start.leak) + 1) % 6, "order": [1, 2, 3, 4, 5], "pressed": 5}}
	var fixed := Rule.current_state(forged)
	_check("rule: forged leak / order / pressed are not kept", int(fixed.leak) == int(start.leak) and fixed.order == start.order and int(fixed.pressed) == 2)
	var moves := solution(start)
	var t := task.duplicate(true)
	var all_ok := true
	for k in moves.size():
		var r := Rule.validate(t, {"move": moves[k][0], "value": k * Rule.STEP_BASE + int(moves[k][1])})
		all_ok = all_ok and bool(r.accepted) and (bool(r.complete) == (k == moves.size() - 1))
		if all_ok and k < moves.size() - 1:
			all_ok = is_equal_approx(float(r.progress), 0.18 * float(k + 1))
		t.puzzle_state = r.get("puzzle_state", {})
	_check("rule: pressing 1, 2, 3, 4, 5 completes it (0.18 progress each before that)", all_ok and moves.size() == 5)
	_check("rule: nothing accepted after completion", not bool(Rule.validate(t, {"move": "reset", "value": 5 * Rule.STEP_BASE}).accepted))
	# Reset half way: back to 0 pressed, same leak and numbers, the step keeps counting.
	t = task.duplicate(true)
	for k in 2:
		t.puzzle_state = Rule.validate(t, {"move": "press", "value": k * Rule.STEP_BASE + k + 1}).puzzle_state
	var reset := Rule.validate(t, {"move": "reset", "value": 2 * Rule.STEP_BASE})
	var after: Dictionary = reset.get("puzzle_state", {})
	_check("rule: reset after two presses", bool(reset.accepted) and int(after.pressed) == 0 and int(after.step) == 3 and after.order == start.order and int(after.leak) == int(start.leak) and float(reset.progress) == 0.0)
	t.puzzle_state = after
	_check("rule: a replayed press after the reset is refused", not bool(Rule.validate(t, {"move": "press", "value": 1 * Rule.STEP_BASE + 2}).accepted))
	_check("rule: after the reset it starts again at 1", bool(Rule.validate(t, {"move": "press", "value": 3 * Rule.STEP_BASE + 1}).accepted) and not bool(Rule.validate(t, {"move": "press", "value": 3 * Rule.STEP_BASE + 3}).accepted))


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
	_check("other specialty cannot move T12", _move(2, "press", 1).reason == &"wrong_specialty")
	medic.owner_peer = 0
	var claim := s.request(&"task_claim", STATION, {"generation": gen})
	_check("engineer at the station claims T12", claim.ok, "%s %s (zone %s at %s)" % [claim.reason, claim.message, s.zone_at_position.call(pos) if s.zone_at_position.is_valid() else "-", pos])
	var start := Rule.current_state(task)
	_check("forged completion flag rejected", s.request(&"task_move", STATION, {"generation": gen, "move": "press", "value": 1, "complete": true}).reason == &"bad_request")
	_check("unknown move fails closed", _move(1, "seal_all", 0).reason == &"invalid_move")
	_check("negative value fails closed", s.request(&"task_move", STATION, {"generation": gen, "move": "press", "value": -3}).reason == &"invalid_move")
	_check("out-of-range number fails closed", _move(1, "press", 17).reason == &"invalid_move")
	_check("wrong number fails closed", _move(1, "press", 2).reason == &"invalid_move")
	_check("restart with nothing pressed fails closed", _move(1, "reset", 0).reason == &"invalid_move")
	_check("future step fails closed", _move(1, "press", 1, 2).reason == &"invalid_move")
	_check("rejections changed nothing", (task.puzzle_state as Dictionary).is_empty() and float(task.progress) == 0.0)
	_check("number 1 pressed", _move(1, "press", 1).ok)
	_check("replayed press request fails closed", _move(1, "press", 1, 0).reason == &"invalid_move")
	_check("pressing 3 before 2 fails closed", _move(1, "press", 3).reason == &"invalid_move")
	_check("number 2 pressed", _move(1, "press", 2).ok and int(Rule.current_state(task).pressed) == 2)
	var before := Rule.current_state(task)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(RepairCatalog.for_save(s.state.repair)))
	var restored := RepairCatalog.restore(saved, s.state.rng_seed)
	_check("save keeps the half-done seal (supports_resume)", Rule.current_state(restored.tasks[TASK]) == before and is_equal_approx(float(restored.tasks[TASK].progress), float(task.progress)))
	s.state.repair = restored
	task = s.state.repair.tasks[TASK]
	_check("restart (too slow) peels the seal off", _move(1, "reset", 0).ok and int(Rule.current_state(task).pressed) == 0 and Rule.current_state(task).order == start.order and float(task.progress) == 0.0)
	var ok := true
	for n in Rule.POINTS - 1:
		ok = ok and _move(1, "press", n + 1).ok
	_check("1 to 4 pressed after the reload and restart, not complete before 5", ok and float(task.progress) < 1.0 and not bool(task.first_completed))
	_check("pressing 5 completes T12", _move(1, "press", Rule.POINTS).ok and float(task.progress) >= 1.0 and bool(task.first_completed))
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
	_check("still leaking until number 5 is pressed", ok and bool(s.survival.pressure_info().leaking) and not bool(task.first_completed))
	_check("pressing 5 completes T12 during the fault", _move(1, "press", Rule.POINTS).ok and bool(task.first_completed))
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
	_check("the old step buttons are gone", panel.get("section_buttons") == null and panel.get("seal_buttons") == null and panel.get("test_button") == null)
	var points: Array = panel.press_buttons
	_check("five numbered seal points on the door picture", points.size() == Rule.POINTS and points.all(func(b: Button) -> bool: return b.is_visible_in_tree() and b.size.x >= 40.0 and b.size.y >= 40.0 and panel.door_box.is_ancestor_of(b)))
	var door_size: Vector2 = panel.door_box.size
	_check("door picture at most 420x300 and the play area within 540 px", door_size.x <= 420.5 and door_size.y <= 300.5 and panel.play_area.size.y <= 540.0, "door %s, play area %s" % [door_size, panel.play_area.size])
	var inside := true
	var apart := true
	for a in Rule.POINTS:
		var ra := Rect2((points[a] as Button).position, (points[a] as Button).size)
		inside = inside and Rect2(Vector2.ZERO, door_size).encloses(ra)
		for b in range(a + 1, Rule.POINTS):
			apart = apart and ra.get_center().distance_to(Rect2((points[b] as Button).position, (points[b] as Button).size).get_center()) >= SealPanel.POINT_SIZE - 0.5
	_check("the points sit inside the picture and do not overlap", inside and apart)
	_check("the clock waits for number 1", not panel.timer_running and is_equal_approx(panel.time_left, SealPanel.TIME_LIMIT_S) and SealPanel.TIME_LIMIT_S == 10.0, panel.time_label.text)
	var visited := {}
	(points[0] as Button).grab_focus()
	for i in 12:
		var focused := root.gui_get_focus_owner()
		if focused != null:
			visited[focused] = true
		_key(KEY_TAB)
	_check("Tab reaches every seal point", points.all(func(b: Button) -> bool: return visited.has(b)))
	(points[0] as Button).grab_focus()
	_key(KEY_RIGHT)
	await _frames()
	_check("arrow keys step along the points", root.gui_get_focus_owner() == points[1])
	var wrong_spot := Rule.spot_of(start, 3)
	await _press(points[wrong_spot])
	_check("a wrong number flashes red and sends nothing", panel.flash_spot == wrong_spot and (task.puzzle_state as Dictionary).is_empty() and "number 1" in panel.status_label.text, panel.status_label.text)
	await _press(points[Rule.spot_of(start, 1)])
	_check("number 1 goes to the host and starts the clock", int(Rule.current_state(task).pressed) == 1 and panel.timer_running and panel.time_left <= SealPanel.TIME_LIMIT_S and panel.time_left > SealPanel.TIME_LIMIT_S - 3.0, "%s s" % panel.time_left)
	_check("the time left is shown", panel.time_label.is_visible_in_tree() and "Time left" in panel.time_label.text, panel.time_label.text)
	# Run the clock out (no 10 s wait in the test).
	panel.time_left = 0.0
	await _frames(3)
	_check("too slow: the panel asks for a restart", panel.timed_out and panel.restart_button.is_visible_in_tree() and "Too slow" in panel.timeout_label.text and "Restart" in panel.status_label.text, panel.status_label.text)
	_check("the points take no clicks while the time is up", points.all(func(b: Button) -> bool: return b.disabled))
	await _press(points[Rule.spot_of(start, 2)])
	_check("pressing 2 after the time ran out sends nothing", int(Rule.current_state(task).pressed) == 1 and int(Rule.current_state(task).step) == 1)
	issues = UiLayoutCheck.problems(panel, root.get_visible_rect().size)
	_check("panel layout with the Restart row fits 1280x720", issues.is_empty(), " | ".join(issues))
	await _press(panel.restart_button)
	_check("Restart sends reset: 0 pressed, clock stopped, Restart gone", int(Rule.current_state(task).pressed) == 0 and not panel.timed_out and not panel.timer_running and not panel.restart_button.is_visible_in_tree(), panel.status_label.text)
	_check("keyboard focus comes back to the points", points.has(root.gui_get_focus_owner()))
	for n in Rule.POINTS:
		await _press(points[Rule.spot_of(start, n + 1)])
	_check("keyboard path 1-5 solves T12 through the session", bool(task.first_completed) and float(task.progress) >= 1.0, panel.status_label.text)
	_check("panel shows the host's success; the clock stopped", panel.succeeded and "Fixed" in panel.status_label.text and not panel.timer_running and not panel.timed_out)
	ui.close_all()
	await _frames()
