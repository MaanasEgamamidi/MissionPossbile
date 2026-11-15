extends SceneTree
## T11 Dust (dusty hangar BP10): host rule (per-area dust, brush / vacuum strokes), a real SessionService round trip
## with the actor at the station, forged / replayed / out-of-range moves, determinism per seed, the panel's keyboard
## solve, the puzzle_state format the hangar presenter reads, and resume across a save and reload.
## Run: godot --headless --path . --script res://tests/test_puzzle_t11.gd

const RULE := preload("res://scripts/tasks/puzzles/t11_rule.gd")
const TASK := "T11"
const STATION := &"repair_t11"
const SAVE_DIR := "res://_test_saves/test_puzzle_t11"
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


## The next stroke of the short plan: brush thick dust, vacuum loose dust. [] when the hangar is clean.
static func _next_stroke(task: Dictionary) -> Array:
	var areas: Dictionary = RULE.state_of(task).areas
	for i in RULE.AREAS.size():
		var level := float(areas[RULE.AREAS[i].id])
		if level > 0.5:
			return ["brush", i]
		if level > 0.0:
			return ["vacuum", i]
	return []


func _rule_checks() -> void:
	_check("start dust is deterministic per seed", RULE.start_dust(123) == RULE.start_dust(123))
	var looks := {}
	var levels_ok := true
	for s in 40:
		var dust := RULE.start_dust(s * 31 + 7)
		looks[JSON.stringify(dust)] = true
		for id: String in dust:
			levels_ok = levels_ok and float(dust[id]) in [0.5, 0.75, 1.0]
		levels_ok = levels_ok and dust.size() == RULE.AREAS.size()
	_check("start dust is 0.5, 0.75 or 1.0 in all six areas", levels_ok)
	_check("different seeds give different hangars", looks.size() >= 30, str(looks.size()))
	var plan_ok := true
	var longest := 0
	for s in 40:
		var task := {"puzzle_seed": s * 31 + 7, "puzzle_state": {}, "progress": 0.0}
		var strokes := 0
		while strokes < 40:
			var next := _next_stroke(task)
			if next.is_empty():
				break
			var r := RULE.validate(task, {"move": next[0], "value": (strokes + 1) * SHIFT + int(next[1])})
			if not r.accepted:
				plan_ok = false
				break
			task.puzzle_state = r.puzzle_state
			task.progress = r.progress
			strokes += 1
		plan_ok = plan_ok and float(task.progress) == 1.0
		longest = maxi(longest, strokes)
	_check("40 seeds: brushing then vacuuming cleans the hangar", plan_ok)
	_check("short: at most 18 strokes", longest <= 18, str(longest))
	var task := {"puzzle_seed": 99, "puzzle_state": {}, "progress": 0.0}
	var st := RULE.state_of(task)
	var thick := -1
	var loose := -1
	for i in RULE.AREAS.size():
		var level := float(st.areas[RULE.AREAS[i].id])
		if level > 0.5 and thick < 0:
			thick = i
		if level <= 0.5 and loose < 0:
			loose = i
	_check("seed 99 has thick and loose areas", thick >= 0 and loose >= 0)
	_check("vacuum on thick dust is refused", not RULE.validate(task, {"move": "vacuum", "value": SHIFT + thick}).accepted)
	var brushed := RULE.validate(task, {"move": "brush", "value": SHIFT + thick})
	var thick_id := String(RULE.AREAS[thick].id)
	_check("brush removes one quarter", brushed.accepted and float(brushed.puzzle_state.areas[thick_id]) == float(st.areas[thick_id]) - 0.25 and not brushed.complete)
	var vac := RULE.validate(task, {"move": "vacuum", "value": SHIFT + loose})
	_check("vacuum clears loose dust", vac.accepted and float(vac.puzzle_state.areas[RULE.AREAS[loose].id]) == 0.0)
	var after := {"puzzle_seed": 99, "puzzle_state": vac.puzzle_state, "progress": vac.progress}
	_check("brushing a clean area is refused", not RULE.validate(after, {"move": "brush", "value": 2 * SHIFT + loose}).accepted)
	_check("replayed stroke is refused", not RULE.validate(after, {"move": "vacuum", "value": SHIFT + loose}).accepted)
	_check("area out of range is refused", not RULE.validate(after, {"move": "brush", "value": 2 * SHIFT + RULE.AREAS.size()}).accepted)
	_check("wrong step is refused", not RULE.validate(after, {"move": "brush", "value": 5 * SHIFT + thick}).accepted)
	_check("unknown move is refused", not RULE.validate(after, {"move": "mop", "value": 2 * SHIFT + thick}).accepted)
	_check("negative value is refused", not RULE.validate(after, {"move": "brush", "value": -2}).accepted)
	_check("forged reset payload is refused", not RULE.validate(after, {"move": "reset", "value": 2 * SHIFT + 1}).accepted)
	var reset := RULE.validate(after, {"move": "reset", "value": 2 * SHIFT})
	_check("reset brings the seeded dust back", reset.accepted and reset.puzzle_state.areas == RULE.start_dust(99) and reset.progress == 0.0)
	var json_copy := {"puzzle_seed": 99, "puzzle_state": JSON.parse_string(JSON.stringify(vac.puzzle_state)), "progress": vac.progress}
	_check("state survives JSON numbers", RULE.state_of(json_copy).areas == vac.puzzle_state.areas and int(RULE.state_of(json_copy).step) == 1)
	var more := (vac.puzzle_state.areas as Dictionary).duplicate()
	more[thick_id] = 1.25
	_check("dust above the seeded start is ignored", int(RULE.state_of({"puzzle_seed": 99, "puzzle_state": {"seed": 99, "step": 1, "areas": more}}).step) == 0)
	var odd := (vac.puzzle_state.areas as Dictionary).duplicate()
	odd[thick_id] = 0.3
	_check("dust off the stroke grid is ignored", int(RULE.state_of({"puzzle_seed": 99, "puzzle_state": {"seed": 99, "step": 1, "areas": odd}}).step) == 0)
	var zero := {}
	for area: Dictionary in RULE.AREAS:
		zero[area.id] = 0.0
	_check("an all-clean unfinished board is ignored (no dead end)", int(RULE.state_of({"puzzle_seed": 99, "puzzle_state": {"seed": 99, "step": 4, "areas": zero}, "progress": 0.5}).step) == 0)
	_check("area_dust gives the seeded dust on a new game", RULE.area_dust({"puzzle_seed": 99, "puzzle_state": {}}) == RULE.start_dust(99))
	_check("area_dust is all clean once completed", RULE.area_dust({"puzzle_seed": 99, "puzzle_state": {}, "first_completed": true}) == zero)


func _format_ok(state: Dictionary) -> bool:
	var areas: Variant = state.get("areas")
	if not areas is Dictionary or (areas as Dictionary).size() != RULE.AREAS.size():
		return false
	for area: Dictionary in RULE.AREAS:
		var level: Variant = (areas as Dictionary).get(area.id)
		if not level is float or float(level) < 0.0 or float(level) > 1.0:
			return false
	return state.has("seed") and state.has("step")


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
	var next := _next_stroke(_task())
	var value := SHIFT + int(next[1])
	_check("forged completion flag is a bad request", _move(next[0], value, {"complete": true}).reason == &"bad_request")
	_check("unknown move fails closed", _move("sweep_all", value).reason == &"invalid_move")
	_check("out-of-range area fails closed", _move("brush", SHIFT + 99).reason == &"invalid_move")
	_check("skipped step fails closed", _move(next[0], value + SHIFT).reason == &"invalid_move")
	var first := _move(next[0], value)
	_check("valid stroke accepted", first.ok and int(_task().puzzle_state.step) == 1, first.message)
	_check("puzzle_state has the documented per-area format", _format_ok(_task().puzzle_state), str(_task().puzzle_state))
	_check("replayed stroke fails closed", _move(next[0], value).reason == &"invalid_move")
	var second := _next_stroke(_task())
	var req := ActionRequest.make("t11_dup", 1, actor.id, &"task_move", STATION,
		{"generation": int(_task().fault_generation), "move": second[0], "value": 2 * SHIFT + int(second[1])})
	var once := services.session.submit(req)
	_check("duplicate request id applies once", once.ok and services.session.submit(req).duplicate and int(_task().puzzle_state.step) == 2)
	var failures := 0
	var strokes := 0
	while strokes < 40:
		var s := _next_stroke(_task())
		if s.is_empty() or float(_task().progress) >= 1.0:
			break
		if not _move(s[0], (int(_task().puzzle_state.step) + 1) * SHIFT + int(s[1])).ok:
			failures += 1
		strokes += 1
	_check("solve path completes", float(_task().progress) >= 1.0 and failures == 0, "strokes %d failures %d progress %s" % [strokes, failures, _task().progress])
	_check("first_completed set", bool(_task().first_completed) and not PuzzleRegistry.is_broken(services.state(), TASK))
	_check("every area reads clean", RULE.area_dust(_task()).values().all(func(v: Variant) -> bool: return float(v) == 0.0) and (_task().puzzle_state.areas as Dictionary).values().all(func(v: Variant) -> bool: return float(v) == 0.0))
	services.request(&"task_claim", STATION, {"generation": int(_task().fault_generation)})
	_check("moves after completion are refused", _move("reset", (int(_task().puzzle_state.step) + 1) * SHIFT).reason == &"task_complete")


func _save_checks() -> void:
	services.request(&"task_claim", STATION, {"generation": int(_task().fault_generation)})
	for i in 3:
		var s := _next_stroke(_task())
		_move(s[0], (int(RULE.state_of(_task()).step) + 1) * SHIFT + int(s[1]))
	var live: Dictionary = (_task().puzzle_state as Dictionary).duplicate(true)
	var live_progress := float(_task().progress)
	_check("partial cleaning accepted", int(live.get("step", 0)) == 3 and live_progress > 0.0 and live_progress < 1.0)
	_check("rule resumes", RULE.supports_resume() and bool(_task().resume_supported))
	var payload := services.snapshot()
	var saved: Dictionary = payload.colony.repair.tasks[TASK]
	_check("save projection keeps the half-cleaned hangar", float(saved.progress) == live_progress and JSON.stringify(saved.puzzle_state) == JSON.stringify(live))
	_check("saved hangar still broken", PuzzleRegistry.is_broken(services.state(), TASK))
	services.restore(JSON.parse_string(JSON.stringify(payload)))
	var station: Dictionary = services.state().stations[String(STATION)]
	services.local_character().position = CharacterState._v3(station.position)
	_check("reload resumes the same dust", RULE.state_of(_task()).areas == live.areas and int(RULE.state_of(_task()).step) == 3 and is_equal_approx(float(_task().progress), live_progress),
		"%s step %d progress %s vs %s" % [RULE.state_of(_task()).areas, int(RULE.state_of(_task()).step), _task().progress, live_progress])
	_check("reloaded dust reads through area_dust", RULE.area_dust(_task()) == live.areas)
	var claim := services.request(&"task_claim", STATION, {"generation": int(_task().fault_generation)})
	var failures := 0
	while float(_task().progress) < 1.0 and claim.ok:
		var s := _next_stroke(_task())
		if s.is_empty():
			break
		if not _move(s[0], (int(RULE.state_of(_task()).step) + 1) * SHIFT + int(s[1])).ok:
			failures += 1
			break
	_check("cleaning finishes after reload", claim.ok and failures == 0 and bool(_task().first_completed))


func _panel_checks() -> void:
	ui = UiRoot.new()
	root.add_child(ui)
	var settings := GameSettings.new()
	settings.reduce_motion = true
	ui.setup(services, settings)
	await _frames()
	root.size = Vector2i(1280, 720)
	await _frames()
	var panel := PuzzleRegistry.make_panel(TASK, STATION, services)
	_check("panel builds headless", panel != null and (panel.get("area_tiles") as Array).size() == RULE.AREAS.size())
	_check("panel claims the task on open", services.session.repair_runtime.locks.has(TASK))
	ui.open(panel)
	await _frames(6)
	var issues := UiLayoutCheck.problems(panel, root.get_visible_rect().size)
	_check("panel fits 1280x720", issues.is_empty(), " | ".join(issues))
	_check("panel focus styles", UiLayoutCheck.focus_problems(panel).is_empty())
	var tiles: Array = panel.get("area_tiles")
	var st := RULE.state_of(_task())
	var thick := -1
	for i in RULE.AREAS.size():
		if float(st.areas[RULE.AREAS[i].id]) > 0.5:
			thick = i
			break
	(tiles[thick] as Control).grab_focus()
	await _frames()
	_key(KEY_V)
	await _frames()
	_key(KEY_ENTER)
	await _frames(2)
	_check("V picks the vacuum and thick dust gets a friendly hint", String(panel.get("current_tool")) == "vacuum" and "too thick" in (panel.get("hint_label") as Label).text and int(RULE.state_of(_task()).step) == 0, (panel.get("hint_label") as Label).text)
	(tiles[0] as Control).grab_focus()
	await _frames()
	_key(KEY_RIGHT)
	await _frames()
	_check("arrow keys move between areas", root.gui_get_focus_owner() == tiles[1])
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
	_check("keyboard cleans the hangar through the host", float(_task().progress) >= 1.0 and bool(_task().first_completed), "presses %d progress %s" % [presses, _task().progress])
	_check("panel shows the host's completion", bool(panel.get("succeeded")) and "Complete" in panel.status_label.text)
	_check("hint says the floor lines show again", "floor lines" in (panel.get("hint_label") as Label).text, (panel.get("hint_label") as Label).text)
	print("INFO keyboard strokes %d" % presses)
	ui.close_all()
	await _frames()
