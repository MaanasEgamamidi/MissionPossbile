extends SceneTree
## Prompt 03 integration checks: new game, save, continue, when saves happen, and that nothing jumps or duplicates.
## Run: godot --headless --path . --script res://tests/test_game_services.gd

var _passed := 0
var _total := 0


func _check(name: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS ", name, ("  " + detail) if detail != "" else "")
	else:
		print("FAIL ", name, ": ", detail)


func _canon(d: Dictionary) -> String:
	return SaveService.canonical_text(d)


func _make(dir: String) -> GameServices:
	var g := GameServices.new()
	g.saves = SaveService.new(dir, "colony", 2)
	# Save/continue identity of the parked crew is checked from the Med Bay start: on load parked crew are put back on
	# their hub spots, so the tutorial start (everyone outside) is checked in tests/test_tutorial_start.gd instead.
	g.config.tutorial_start_outside = false
	root.add_child(g)
	return g


func _initialize() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/services")
	DirAccess.make_dir_recursive_absolute(dir)
	var g := _make(dir)
	g.saves.delete_all()

	# ---- fresh start
	var first := g.continue_game()
	_check("fresh start: no save is a defined result", first.status == &"no_save" and not g.has_game(), String(first.status))
	g.start_new_game(777)
	var st := g.state()
	_check("new game: four crew, host controls crew_1", st.characters.size() == 4 and st.character(&"crew_1").owner_peer == 1)
	var base_stations := 0
	for rec: Dictionary in st.stations.values():
		if (["power", "computer", "comms", "food", "lifesupport", "heal", "board", "survivor", "suits", "solar"] as Array).has(String(rec.kind)):
			base_stations += 1
	_check("new game: 21 base stations from the map (9 tagged + 12 sun trackers) plus those added by data files", base_stations == 21, "%d base, %d in all" % [base_stations, st.stations.size()])
	_check("new game: 18 zones, all powered", st.zones.size() == 18 and st.is_zone_powered("Power Room"), str(st.zones.size()))
	_check("new game: saved at once", g.saves.has_save())
	_check("new game: starts at the configured time of day", is_equal_approx(g.clock().phase, g.config.start_phase))

	# ---- play, act, save
	st.items["crate_1"] = {"kind": "supply_crate", "position": [st.character(&"crew_1").position.x, 0.0, st.character(&"crew_1").position.z], "holder": ""}
	var r := g.session.request(&"pick_up", &"crate_1")
	_check("action through the session works", r.ok and st.character(&"crew_1").cargo == [&"crate_1"], r.message)
	for i in 600:                       # 10 real seconds at 60 frames per second
		g.session.advance(1.0 / 60.0)
	_check("ten real seconds = 50 ticks", g.clock().ticks == 50, str(g.clock().ticks))
	var rng_next: Array = []
	g.session.sync_rng_to_state()
	var probe := RandomNumberGenerator.new()
	probe.seed = st.rng_seed
	probe.state = st.rng_state
	for i in 5:
		rng_next.append(probe.randi())
	_check("manual save", g.save_now(&"manual") == OK)
	var before := _canon(g.snapshot())
	var phase_before := g.clock().phase
	var ticks_before := g.clock().ticks

	# ---- continue in a "new process": a second services node reading the same folder
	var g2 := _make(dir)
	var loaded := g2.continue_game()
	_check("continue: status ok", loaded.status == &"ok", String(loaded.status))
	_check("continue: state identical to what was saved", _canon(g2.snapshot()) == before)
	_check("continue: no clock jump", g2.clock().phase == phase_before and g2.clock().ticks == ticks_before and g2.clock().sol_index == 0)
	_check("continue: host is the same crew member and still carries the crate",
		g2.state().character(&"crew_1").owner_peer == 1 and g2.state().character(&"crew_1").cargo == [&"crate_1"]
		and String(g2.state().items["crate_1"]["holder"]) == "crew_1")
	_check("continue: nothing duplicated or broken", g2.state().invariants_ok().is_empty(), str(g2.state().invariants_ok()))
	var same_rng := true
	for i in 5:
		same_rng = same_rng and g2.session.rng.randi() == rng_next[i]
	_check("continue: random sequence carries on where it stopped", same_rng)

	# ---- no offline penalty: wait in real time without ticking, then load again
	OS.delay_msec(1200)
	var g3 := _make(dir)
	g3.continue_game()
	_check("no offline deterioration: real time while closed changes nothing", _canon(g3.snapshot()) == before)

	# ---- when saves happen
	var saves_seen: Array = []
	g2.events.game_saved.connect(func(_path: String, reason: StringName) -> void: saves_seen.append(reason))
	g2.session.request(&"set_sol_minutes", &"", {"minutes": 40.0})
	g2._process(0.016)
	_check("important transaction saves right away", saves_seen.has(&"set_sol_minutes"), str(saves_seen))
	saves_seen.clear()
	g2.session.request(&"drop", &"crate_1")
	g2._process(0.016)
	_check("ordinary action does not force a save", saves_seen.is_empty(), str(saves_seen))
	g2._autosave_left = 0.05
	g2._process(0.1)
	_check("interval autosave", saves_seen.has(&"autosave"), str(saves_seen))
	saves_seen.clear()
	g2.session.set_pause_vote(1, true)
	g2._autosave_left = 0.05
	var ticks_paused := g2.clock().ticks
	for i in 60:
		g2._process(0.1)
	_check("paused: no ticks and no autosave", g2.clock().ticks == ticks_paused and saves_seen.is_empty(), "%d %s" % [g2.clock().ticks - ticks_paused, saves_seen])
	g2.session.set_pause_vote(1, false)

	# ---- repeated saves do not grow or drift
	var texts := {}
	for i in 5:
		g2.save_now(&"manual")
		texts[_canon(g2.snapshot())] = true
	_check("repeated save: state unchanged by saving", texts.size() == 1, str(texts.size()))
	var files := DirAccess.get_files_at(dir)
	_check("repeated save: one main file and two backups only", files.size() == 3, str(files))

	# ---- damaged newest save falls back
	var f := FileAccess.open(g2.saves.main_path(), FileAccess.WRITE)
	f.store_string("{ this is not a save")
	f.close()
	var g4 := _make(dir)
	var rec := g4.continue_game()
	_check("damaged newest save: recovered from backup", rec.status == &"recovered_from_backup" and g4.has_game(), "%s %s" % [rec.status, rec.problems])

	# ---- save written by a newer game
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(g2.saves.backup_path(1)))
	envelope["schema"] = 99
	envelope["checksum"] = SaveService.checksum(envelope["payload"])
	for p in [g2.saves.main_path(), g2.saves.backup_path(1), g2.saves.backup_path(2)]:
		var w := FileAccess.open(p, FileAccess.WRITE)
		w.store_string(JSON.stringify(envelope, "\t", true, true))      # full precision, or the checksum would not match
		w.close()
	var g5 := _make(dir)
	var newer := g5.continue_game()
	_check("save from a newer game: refused, no game started", newer.status == &"unsupported_schema" and not g5.has_game(), String(newer.status))

	# ---- orderly quit saves
	g5.saves.delete_all()
	g5.start_new_game(5)
	var quit_reasons: Array = []
	g5.events.game_saved.connect(func(_path: String, reason: StringName) -> void: quit_reasons.append(reason))
	g5.save_now(&"quit")                 # quit_game() = this + SceneTree.quit(); the save is what is checked here
	_check("orderly quit writes a save", quit_reasons == [&"quit"] and g5.saves.has_save(), str(quit_reasons))

	for n in [g, g2, g3, g4, g5]:
		n.saves.delete_all()
		n.queue_free()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)
