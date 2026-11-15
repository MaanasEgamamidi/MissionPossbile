extends SceneTree
## T09 Mixture (Med Bay test-tube rack) puzzle: seeded layout, host rule through a real SessionService with the medic
## at the repair_t09 station, fail-closed moves (wrong, forged, out-of-range, replayed), specialty gate, save
## projection (supports_resume) and the panel built headless and solved with the keyboard.
## Run: godot --headless --path . --script res://tests/test_puzzle_t09.gd

const Rule := preload("res://scripts/tasks/puzzles/t09_rule.gd")
const TASK := "T09"
const STATION := &"repair_t09"

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
	var dir := ProjectSettings.globalize_path("res://_test_saves/puzzle_t09")
	DirAccess.make_dir_recursive_absolute(dir)
	services.saves = SaveService.new(dir, "colony", 1)
	root.add_child(services)
	services.start_new_game(90901, &"crew_2")
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


# ---------------------------------------------------------------- solver (test only)

## Shortest list of [from, to] pours that sorts the tubes (breadth-first; the state space is small).
static func solve(start: Array) -> Array:
	var key0 := str(start)
	var parent := {key0: null}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var tubes: Array = queue[head]
		head += 1
		if Rule.is_sorted(tubes):
			var path: Array = []
			var k := str(tubes)
			while parent[k] != null:
				var link: Array = parent[k]
				path.push_front(link[1])
				k = link[0]
			return path
		for a in tubes.size():
			for b in tubes.size():
				if a == b or not Rule.can_pour(tubes, a, b):
					continue
				var next: Array = tubes.duplicate(true)
				(next[b] as Array).append((next[a] as Array).pop_back())
				var nk := str(next)
				if parent.has(nk):
					continue
				parent[nk] = [str(tubes), [a, b]]
				queue.append(next)
	return [-1]


static func _wrong_pour(tubes: Array) -> Vector2i:
	for a in tubes.size():
		for b in tubes.size():
			if a != b and not (tubes[a] as Array).is_empty() and not Rule.can_pour(tubes, a, b):
				return Vector2i(a, b)
	return Vector2i(-1, -1)


# ---------------------------------------------------------------- pure rule

func _rule_checks() -> void:
	_check("supports resume", Rule.supports_resume())
	_check("same seed, same layout", Rule.initial_state(4242) == Rule.initial_state(4242))
	var layouts := {}
	var worst := 0
	var all_good := true
	var detail := ""
	for s in 60:
		var start := Rule.initial_state(1000 + s * 7919)
		layouts[str(start.tubes)] = true
		var path := solve(start.tubes)
		var mixed := 0
		for t: Array in start.tubes:
			if t.any(func(d: int) -> bool: return d != int(t[0])):
				mixed += 1
		var fallen := (start.racked as Array).count(false)
		if Rule.is_sorted(start.tubes) or path == [-1] or mixed < Rule.MIN_MIXED_TUBES or fallen != Rule.FALLEN_TUBES:
			all_good = false
			detail = "seed %d sorted=%s path=%s mixed=%d fallen=%d" % [s, Rule.is_sorted(start.tubes), path, mixed, fallen]
		worst = maxi(worst, path.size())
	_check("60 seeds: scrambled, always solvable, %d tube(s) fallen" % Rule.FALLEN_TUBES, all_good, detail)
	_check("kid-sized: every seed solves in at most 12 pours", worst <= 12, "longest shortest solution %d" % worst)
	_check("seeds give different layouts", layouts.size() >= 40, "%d distinct of 60" % layouts.size())
	var task := {"puzzle_seed": 77, "puzzle_state": {}}
	var start := Rule.current_state(task)
	var fallen := (start.racked as Array).find(false)
	var standing := (start.racked as Array).find(true)
	_check("rule: rack a fallen tube", bool(Rule.validate(task, {"move": "rack", "value": fallen}).accepted))
	_check("rule: standing tube refused", not bool(Rule.validate(task, {"move": "rack", "value": standing}).accepted))
	_check("rule: pour before racking refused", not bool(Rule.validate(task, {"move": "pour", "value": 1}).accepted))
	_check("rule: out-of-range tube refused", not bool(Rule.validate(task, {"move": "rack", "value": Rule.TUBES}).accepted))
	_check("rule: negative value refused", not bool(Rule.validate(task, {"move": "rack", "value": -1}).accepted))
	_check("rule: unknown move refused", not bool(Rule.validate(task, {"move": "complete", "value": 0}).accepted))
	_check("rule: wrong step refused", not bool(Rule.validate(task, {"move": "rack", "value": Rule.STEP_BASE + fallen}).accepted))
	var bad := {"puzzle_seed": 77, "puzzle_state": {"seed": 77, "step": 0, "racked": [true, true, true, true, true],
		"tubes": [[0, 0, 0, 0, 0], [1, 1, 1], [9, 9, 9, 9], [], []]}}
	_check("rule: malformed state falls back to the seeded start", Rule.current_state(bad) == start)
	var other := {"puzzle_seed": 77, "puzzle_state": (Rule.initial_state(78) as Dictionary)}
	_check("rule: state of another seed falls back to the seeded start", Rule.current_state(other) == start)


# ---------------------------------------------------------------- host session

func _move(peer: int, move: String, payload: int, step := -1) -> ActionResult:
	var s := services.session
	var task: Dictionary = s.state.repair.tasks[TASK]
	var at := int(Rule.current_state(task).step) if step < 0 else step
	return s.request(&"task_move", STATION, {"generation": int(task.fault_generation), "move": move, "value": at * Rule.STEP_BASE + payload}, peer)


func _session_checks() -> void:
	var s := services.session
	var task: Dictionary = s.state.repair.tasks[TASK]
	var gen := int(task.fault_generation)
	_check("T09 puzzle installed and broken at start", PuzzleRegistry.has_puzzle(TASK) and PuzzleRegistry.is_broken(s.state, TASK))
	var station: Dictionary = s.state.stations.get(String(STATION), {})
	_check("repair_t09 station exists", not station.is_empty() and String(station.get("task_id", "")) == TASK)
	var pos := CharacterState._v3(station.get("position", [0, 0, 0]))
	var medic := s.state.character(&"crew_2")
	_check("host plays the medic", services.local_character() == medic and String(medic.specialty) == "medical_life_support")
	medic.position = pos
	s.peer_joined(2)
	var electric := s.state.character(&"crew_1")
	electric.owner_peer = 2
	electric.position = pos
	_check("other specialty cannot claim T09", s.request(&"task_claim", STATION, {"generation": gen}, 2).reason == &"wrong_specialty")
	_check("other specialty cannot move T09", _move(2, "rack", 0).reason == &"wrong_specialty")
	_check("move without a claim refused", _move(1, "rack", 0).reason == &"task_unclaimed")
	var claim := s.request(&"task_claim", STATION, {"generation": gen})
	_check("medic at the station claims T09", claim.ok, "%s %s (zone %s)" % [claim.reason, claim.message, s.zone_at_position.call(pos) if s.zone_at_position.is_valid() else "-"])
	var start := Rule.current_state(task)
	var fallen: Array = []
	for i in Rule.TUBES:
		if not bool(start.racked[i]):
			fallen.append(i)
	_check("forged completion flag rejected", s.request(&"task_move", STATION, {"generation": gen, "move": "rack", "value": int(fallen[0]), "complete": true}).reason == &"bad_request")
	_check("unknown move fails closed", _move(1, "solve", 0).reason == &"invalid_move")
	_check("out-of-range tube fails closed", _move(1, "rack", 9).reason == &"invalid_move")
	_check("negative value fails closed", s.request(&"task_move", STATION, {"generation": gen, "move": "rack", "value": -5}).reason == &"invalid_move")
	_check("future step fails closed", _move(1, "rack", int(fallen[0]), 3).reason == &"invalid_move")
	_check("pour before the rack is refilled fails closed", _move(1, "pour", 1).reason == &"invalid_move")
	_check("stale generation refused", s.request(&"task_move", STATION, {"generation": gen + 1, "move": "rack", "value": int(fallen[0])}).reason == &"stale_fault")
	_check("rejections changed nothing", (task.puzzle_state as Dictionary).is_empty() and float(task.progress) == 0.0)
	var first := _move(1, "rack", int(fallen[0]))
	_check("rack a fallen tube", first.ok and float(task.progress) > 0.0 and float(task.progress) < 1.0)
	_check("replayed rack request fails closed", _move(1, "rack", int(fallen[0]), 0).reason == &"invalid_move")
	_check("racking a standing tube fails closed", _move(1, "rack", int(fallen[0])).reason == &"invalid_move")
	for k in range(1, fallen.size()):
		_move(1, "rack", int(fallen[k]))
	var racked := Rule.current_state(task)
	_check("all tubes back in the rack", (racked.racked as Array).all(func(r: bool) -> bool: return r))
	var wrong := _wrong_pour(racked.tubes)
	_check("wrong pour fails closed", wrong.x >= 0 and _move(1, "pour", wrong.x * 10 + wrong.y).reason == &"invalid_move")
	_check("pour to itself fails closed", _move(1, "pour", 11).reason == &"invalid_move")
	var path := solve(racked.tubes)
	_check("solvable from the racked start", path != [-1] and path.size() > 0, str(path))
	# Partial progress, then a save / JSON / restore round trip: T09 supports resume, so it must survive.
	var pour0: Array = path[0]
	var r0 := _move(1, "pour", int(pour0[0]) * 10 + int(pour0[1]))
	_check("first pour accepted", r0.ok and bool(task.resume_supported))
	var replay := s.request(&"task_move", STATION, {"generation": gen, "move": "pour", "value": (int(Rule.current_state(task).step) - 1) * Rule.STEP_BASE + int(pour0[0]) * 10 + int(pour0[1])})
	_check("replayed pour request fails closed", replay.reason == &"invalid_move")
	var before := Rule.current_state(task)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(RepairCatalog.for_save(s.state.repair)))
	var restored := RepairCatalog.restore(saved, s.state.rng_seed)
	var back: Dictionary = restored.tasks[TASK]
	_check("save keeps partial T09 (supports_resume)", not (back.puzzle_state as Dictionary).is_empty() and is_equal_approx(float(back.progress), float(task.progress)))
	_check("restored state equals the live state", Rule.current_state(back) == before)
	s.state.repair = restored
	task = s.state.repair.tasks[TASK]
	var ok := true
	var why := ""
	for k in range(1, path.size()):
		var p: Array = path[k]
		var r := _move(1, "pour", int(p[0]) * 10 + int(p[1]))
		if not r.ok and why.is_empty():
			why = "pour %d %s %s" % [k, r.reason, r.message]
		ok = ok and r.ok
		if k < path.size() - 1:
			ok = ok and float(task.progress) < 1.0 and not bool(task.first_completed)
	_check("solved through the session after the reload", ok and float(task.progress) >= 1.0 and bool(task.first_completed), "%s progress %s" % [why, task.progress])
	_check("T09 no longer broken; condition restored", not PuzzleRegistry.is_broken(s.state, TASK) and float(task.condition) == 1.0 and not s.repair_runtime.locks.has(TASK))
	_check("moves after completion refused", _move(1, "reset", 0).reason in [&"task_unclaimed", &"task_complete"])


# ---------------------------------------------------------------- panel

func _press(button: Button) -> void:
	button.grab_focus()
	_key(KEY_ENTER)
	await _frames(2)


func _panel_checks() -> void:
	services.start_new_game(90902, &"crew_2")
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
	_check("E at the broken spot opens the T09 mini-game", panel != null and panel.name == "T09MixturePanel")
	root.size = Vector2i(1280, 720)
	ui.open(panel)
	await _frames(6)
	_check("panel claimed the task on open", s.repair_runtime.locks.has(TASK) and String(s.repair_runtime.locks[TASK].actor) == "crew_2")
	var issues := UiLayoutCheck.problems(panel, root.get_visible_rect().size)
	_check("panel layout fits 1280x720", issues.is_empty(), "screen %s: %s" % [root.get_visible_rect().size, " | ".join(issues)])
	var buttons: Array = panel.tube_buttons
	var visited := {}
	buttons[0].grab_focus()
	for i in 40:
		var focused := root.gui_get_focus_owner()
		if focused != null:
			visited[focused] = true
		_key(KEY_TAB)
	_check("Tab reaches every tube", buttons.all(func(b: Button) -> bool: return visited.has(b)))
	var task: Dictionary = s.state.repair.tasks[TASK]
	var state := Rule.current_state(task)
	for i in Rule.TUBES:
		if not bool(state.racked[i]):
			await _press(buttons[i])
	state = Rule.current_state(task)
	_check("keyboard racks the fallen tubes", (state.racked as Array).all(func(r: bool) -> bool: return r), panel.status_label.text)
	var wrong := _wrong_pour(state.tubes)
	await _press(buttons[wrong.x])
	await _press(buttons[wrong.y])
	var text: String = panel.status_label.text
	_check("wrong pour explained in words", "full" in text or "can only go onto" in text, text)
	var path := solve(Rule.current_state(task).tubes)
	for p: Array in path:
		await _press(buttons[int(p[0])])
		await _press(buttons[int(p[1])])
	_check("keyboard path solves T09 through the session", bool(task.first_completed) and float(task.progress) >= 1.0, panel.status_label.text)
	_check("panel shows the host's success", panel.succeeded and panel.status_label.text == panel.solved_text() and "sorted" in panel.status_label.text, panel.status_label.text)
	ui.close_all()
	await _frames()
