extends SceneTree
## T08 Glass (broken dome pane BP05): host rule (five distinct pieces, turns, bounds, overlap, full cover), a real
## SessionService round trip with the actor at the station, forged / replayed / out-of-range moves, determinism per
## seed, the panel's keyboard solve and the save projection.
## Run: godot --headless --path . --script res://tests/test_puzzle_t08.gd

const RULE := preload("res://scripts/tasks/puzzles/t08_rule.gd")
const TASK := "T08"
const STATION := &"repair_t08"
const SAVE_DIR := "res://_test_saves/test_puzzle_t08"
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


static func _place_payload(piece: int, at: Array) -> int:
	return piece * 64 + int(at[2]) * 16 + int(at[1]) * 4 + int(at[0])


## A placement of `piece` that is refused for the given reason: "overlap" or "outside".
static func _bad_placement(state: Dictionary, piece: int, kind: String) -> Array:
	for turns in 4:
		for y in RULE.SIZE:
			for x in RULE.SIZE:
				var cells := RULE.covered(state.pieces[piece].cells, x, y, turns)
				var outside := cells.has(-1)
				var overlap := false
				for c: int in cells:
					if c >= 0 and int(state.board[c]) >= 0:
						overlap = true
				if (kind == "outside" and outside and not overlap) or (kind == "overlap" and overlap and not outside):
					return [x, y, turns]
	return []


func _rule_checks() -> void:
	_check("layout is deterministic per seed", JSON.stringify(RULE.layout(123)) == JSON.stringify(RULE.layout(123)))
	var looks := {}
	for s in [1, 2, 3, 4, 5, 6, 7, 8]:
		looks[JSON.stringify(RULE.layout(s))] = true
	_check("different seeds give different trays", looks.size() >= 6, str(looks.size()))
	var tilings_ok := true
	for tiling: Dictionary in RULE.TILINGS:
		var counts := {}
		for row: String in tiling.rows:
			for letter in row:
				counts[letter] = int(counts.get(letter, 0)) + 1
		var names := {}
		for letter: String in tiling.names:
			names[tiling.names[letter]] = true
		tilings_ok = tilings_ok and counts.size() == 5 and names.size() == 5 and (tiling.rows as Array).size() == 4
	_check("every authored tiling has five differently named pieces", tilings_ok)
	var solved_all := true
	var used_tilings := {}
	var detail := ""
	for s in 60:
		var seed_value := s * 104729 + 3
		var lay := RULE.layout(seed_value)
		used_tilings[int(lay.tiling)] = true
		var task := {"puzzle_seed": seed_value, "puzzle_state": {}, "progress": 0.0}
		var labels := {}
		for i in RULE.PIECES:
			labels[lay.pieces[i].label] = true
			var result := RULE.validate(task, {"move": "place", "value": (i + 1) * SHIFT + _place_payload(i, lay.pieces[i].solution)})
			if not result.accepted or bool(result.complete) != (i == RULE.PIECES - 1):
				solved_all = false
				detail = "seed %d piece %d" % [seed_value, i]
				break
			task.puzzle_state = result.puzzle_state
			task.progress = result.progress
		solved_all = solved_all and labels.size() == RULE.PIECES and float(task.progress) == 1.0
	_check("60 seeds: the known solution fills the pane exactly", solved_all, detail)
	_check("seeds use every authored tiling", used_tilings.size() == RULE.TILINGS.size(), str(used_tilings.keys()))
	var lay := RULE.layout(99)
	var task := {"puzzle_seed": 99, "puzzle_state": {}, "progress": 0.0}
	var st := RULE.state_of(task)
	_check("empty state has every piece in the tray", int(st.step) == 0 and (st.board as Array).count(-1) == 16)
	var first := RULE.validate(task, {"move": "place", "value": SHIFT + _place_payload(0, lay.pieces[0].solution)})
	_check("a fitting placement is accepted", first.accepted and not first.complete and first.progress > 0.0)
	var after := {"puzzle_seed": 99, "puzzle_state": first.puzzle_state, "progress": first.progress}
	var st1 := RULE.state_of(after)
	_check("replayed placement is refused", not RULE.validate(after, {"move": "place", "value": SHIFT + _place_payload(0, lay.pieces[0].solution)}).accepted)
	_check("placing the same piece twice is refused", not RULE.validate(after, {"move": "place", "value": 2 * SHIFT + _place_payload(0, lay.pieces[0].solution)}).accepted)
	var overlap := _bad_placement(st1, 1, "overlap")
	_check("overlapping placement is refused", not overlap.is_empty() and not RULE.validate(after, {"move": "place", "value": 2 * SHIFT + _place_payload(1, overlap)}).accepted)
	var outside := _bad_placement(st1, 1, "outside")
	_check("placement sticking out of the frame is refused", not outside.is_empty() and not RULE.validate(after, {"move": "place", "value": 2 * SHIFT + _place_payload(1, outside)}).accepted)
	_check("piece out of range is refused", not RULE.validate(after, {"move": "place", "value": 2 * SHIFT + 5 * 64}).accepted)
	_check("lifting a tray piece is refused", not RULE.validate(after, {"move": "lift", "value": 2 * SHIFT + 1}).accepted)
	_check("wrong step is refused", not RULE.validate(after, {"move": "lift", "value": 3 * SHIFT}).accepted)
	_check("unknown move is refused", not RULE.validate(after, {"move": "glue", "value": 2 * SHIFT}).accepted)
	_check("negative value is refused", not RULE.validate(after, {"move": "lift", "value": -1}).accepted)
	_check("forged reset payload is refused", not RULE.validate(after, {"move": "reset", "value": 2 * SHIFT + 3}).accepted)
	var lifted := RULE.validate(after, {"move": "lift", "value": 2 * SHIFT})
	_check("lifting a placed piece returns it to the tray", lifted.accepted and (lifted.puzzle_state.placed[0] as Array).is_empty() and lifted.progress == 0.0)
	var json_copy := {"puzzle_seed": 99, "puzzle_state": JSON.parse_string(JSON.stringify(first.puzzle_state))}
	_check("state survives JSON numbers", JSON.stringify(RULE.state_of(json_copy).board) == JSON.stringify(first.puzzle_state.board) and int(RULE.state_of(json_copy).step) == 1)
	var forged_overlap := {"puzzle_seed": 99, "puzzle_state": {"seed": 99, "step": 3, "placed": [lay.pieces[0].solution, lay.pieces[0].solution, [], [], []]}}
	_check("saved state with overlapping pieces is ignored", int(RULE.state_of(forged_overlap).step) == 0)
	_check("state of another seed is ignored", int(RULE.state_of({"puzzle_seed": 99, "puzzle_state": {"seed": 98, "step": 1, "placed": first.puzzle_state.placed}}).step) == 0)
	var four := after.duplicate(true)
	for i in range(1, RULE.PIECES - 1):
		var r := RULE.validate(four, {"move": "place", "value": (i + 1) * SHIFT + _place_payload(i, lay.pieces[i].solution)})
		four.puzzle_state = r.puzzle_state
		four.progress = r.progress
	_check("a pane with a hole is not complete", float(four.progress) < 1.0 and (four.puzzle_state.board as Array).count(-1) > 0)


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
	var lay := RULE.layout(int(_task().puzzle_seed))
	var value := SHIFT + _place_payload(0, lay.pieces[0].solution)
	_check("forged completion flag is a bad request", _move("place", value, {"complete": true}).reason == &"bad_request")
	_check("unknown move fails closed", _move("finish", value).reason == &"invalid_move")
	_check("out-of-range piece fails closed", _move("place", SHIFT + 7 * 64).reason == &"invalid_move")
	_check("skipped step fails closed", _move("place", value + SHIFT).reason == &"invalid_move")
	var first := _move("place", value)
	_check("fitting placement accepted", first.ok and int(_task().puzzle_state.step) == 1, first.message)
	_check("replayed placement fails closed", _move("place", value).reason == &"invalid_move")
	var overlap := _bad_placement(RULE.state_of(_task()), 1, "overlap")
	_check("overlap fails closed on the host", _move("place", 2 * SHIFT + _place_payload(1, overlap)).reason == &"invalid_move" and int(_task().puzzle_state.step) == 1)
	var req := ActionRequest.make("t08_dup", 1, actor.id, &"task_move", STATION,
		{"generation": int(_task().fault_generation), "move": "place", "value": 2 * SHIFT + _place_payload(1, lay.pieces[1].solution)})
	var once := services.session.submit(req)
	_check("duplicate request id applies once", once.ok and services.session.submit(req).duplicate and int(_task().puzzle_state.step) == 2)
	var failures := 0
	for i in range(2, RULE.PIECES):
		if not _move("place", (int(_task().puzzle_state.step) + 1) * SHIFT + _place_payload(i, lay.pieces[i].solution)).ok:
			failures += 1
	_check("solve path completes", float(_task().progress) >= 1.0 and failures == 0, "failures %d progress %s" % [failures, _task().progress])
	_check("first_completed set", bool(_task().first_completed) and not PuzzleRegistry.is_broken(services.state(), TASK))
	_check("finished pane is fully covered", (_task().puzzle_state.board as Array).count(-1) == 0)
	services.request(&"task_claim", STATION, {"generation": int(_task().fault_generation)})
	_check("moves after completion are refused", _move("lift", (int(_task().puzzle_state.step) + 1) * SHIFT).reason == &"task_complete")


func _save_checks() -> void:
	services.request(&"task_claim", STATION, {"generation": int(_task().fault_generation)})
	var lay := RULE.layout(int(_task().puzzle_seed))
	var result := _move("place", SHIFT + _place_payload(2, lay.pieces[2].solution))
	_check("partial move accepted", result.ok and float(_task().progress) > 0.0)
	_check("rule does not resume", not RULE.supports_resume() and not bool(_task().resume_supported))
	var saved: Dictionary = services.snapshot().colony.repair.tasks[TASK]
	_check("save projection drops the unfinished pane", float(saved.progress) == 0.0 and (saved.puzzle_state as Dictionary).is_empty())
	services.restore(services.snapshot())
	_check("reloaded pane has every piece in the tray", (RULE.state_of(_task()).board as Array).count(-1) == 16)


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
	_check("panel builds headless", panel != null and (panel.get("frame_tiles") as Array).size() == 16 and (panel.get("piece_tiles") as Array).size() == RULE.PIECES)
	_check("panel claims the task on open", services.session.repair_runtime.locks.has(TASK))
	ui.open(panel)
	await _frames(6)
	var issues := UiLayoutCheck.problems(panel, root.get_visible_rect().size)
	_check("panel fits 1280x720", issues.is_empty(), " | ".join(issues))
	_check("panel focus styles", UiLayoutCheck.focus_problems(panel).is_empty())
	var frame: Array = panel.get("frame_tiles")
	var tray: Array = panel.get("piece_tiles")
	var lay := RULE.layout(int(_task().puzzle_seed))
	(frame[0] as Control).grab_focus()
	await _frames()
	_key(KEY_ENTER)
	await _frames()
	_check("hint asks to pick a piece first", "Pick" in (panel.get("hint_label") as Label).text and int(_task().puzzle_state.get("step", 0)) == 0)
	var lifted_once := false
	for piece in RULE.PIECES:
		await _keyboard_place(panel, frame, tray, piece, lay.pieces[piece].solution)
		if piece == 0 and not lifted_once:
			lifted_once = true
			_check("keyboard placed the first piece", not (RULE.state_of(_task()).placed[0] as Array).is_empty())
			(tray[0] as Control).grab_focus()
			await _frames()
			_key(KEY_ENTER)
			await _frames(2)
			_check("pressing a placed piece takes it back out", (RULE.state_of(_task()).placed[0] as Array).is_empty())
			await _keyboard_place(panel, frame, tray, 0, lay.pieces[0].solution)
	_check("keyboard solves the pane through the host", float(_task().progress) >= 1.0 and bool(_task().first_completed), "progress %s placed %s" % [_task().progress, RULE.state_of(_task()).placed])
	_check("panel shows the host's completion", bool(panel.get("succeeded")) and "Complete" in panel.status_label.text)
	_check("hint says the pane is whole", "whole" in (panel.get("hint_label") as Label).text, (panel.get("hint_label") as Label).text)
	ui.close_all()
	await _frames()


## Picks a piece in the tray with Enter, turns it with R, walks the frame with the arrow keys and places it with Enter.
func _keyboard_place(panel: Control, frame: Array, tray: Array, piece: int, solution: Array) -> void:
	(tray[piece] as Control).grab_focus()
	await _frames(1)
	_key(KEY_ENTER)
	await _frames(2)
	var turns := posmod(int(solution[2]) - int((panel.get("ui_turns") as Array)[piece]), 4)
	for i in turns:
		_key(KEY_R)
		await _frames(1)
	var target := Vector2i(int(solution[0]), int(solution[1]))
	for i in 12:
		var owner := root.gui_get_focus_owner()
		var at := frame.find(owner)
		if at < 0:
			break
		var here := Vector2i(at % RULE.SIZE, at / RULE.SIZE)
		if here == target:
			break
		_key(KEY_RIGHT if here.x < target.x else (KEY_LEFT if here.x > target.x else (KEY_DOWN if here.y < target.y else KEY_UP)))
		await _frames(1)
	_key(KEY_ENTER)
	await _frames(2)
