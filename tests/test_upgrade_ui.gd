extends SceneTree
## Upgrade update UI (2026-11-14): the "Upgrades" strip on station panels, the Garden upgrade console, the death notice
## after a med bay respawn, the battery chip under the vitals bar and the level-up pop-up.
## Run: & '<godot console>' --headless --path . --script res://tests/test_upgrade_ui.gd


## Collects engine and script errors raised while the test runs.
class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR or error_type == ERROR_TYPE_SCRIPT:
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


## Stands in for game_main: MissionHud reads `hud` and `ui` from it.
class FakeGame extends Node:
	var hud: GameHud
	var ui: UiRoot


const CONSOLE_PANEL := "res://scripts/ui/stations/upgrade_console_station_panel.gd"
const ENERGY_CHIP := "res://scripts/ui/hud/energy_chip.gd"

var _passed := 0
var _total := 0
var _catcher := ErrorCatcher.new()
var _gs: GameServices
## Death records by crew id, used only when CharacterState has no `last_death` field yet (survival update).
var _records: Dictionary = {}


func _initialize() -> void:
	OS.add_logger(_catcher)
	PlayerInput.ensure_actions()
	AreaLevels.reload()
	_gs = GameServices.new()
	_gs.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/test_upgrade_ui"), "colony", 2)
	root.add_child(_gs)
	_gs.start_new_game(1)
	await process_frame
	_test_strip_everywhere()
	await _test_console()
	await _test_blocked_and_press()
	_test_rover()
	await _test_death_notice()
	_test_energy_chip()
	await _test_toast_and_layout()
	_check("no errors during the test", _catcher.errors.is_empty(), "\n".join(_catcher.errors))
	OS.remove_logger(_catcher)
	_gs.queue_free()
	await process_frame
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


func _check(label: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS " + label)
	else:
		print("FAIL " + label + ("  -- " + detail if detail != "" else ""))


func _frames(n := 2) -> void:
	for i in n:
		await process_frame


## Makes the crew member with `specialty` the local player's and stands them at `station_id`.
func _play_as(specialty: StringName, station_id: String) -> CharacterState:
	var st := _gs.state()
	var who: CharacterState = null
	for c: CharacterState in st.characters.values():
		c.owner_peer = 0
	for c: CharacterState in st.characters.values():
		if c.specialty == specialty:
			who = c
			break
	who.owner_peer = _gs.local_peer()
	who.position = CharacterState._v3(st.stations[station_id].position)
	return who


func _station_of(kind: String) -> String:
	var st := _gs.state()
	var ids: Array = st.stations.keys()
	ids.sort()
	for id: String in ids:
		if String(st.stations[id].get("kind", "")) == kind:
			return id
	return ""


# ---------------------------------------------------------------- strip on the right stations

func _test_strip_everywhere() -> void:
	var st := _gs.state()
	var wrong := PackedStringArray()
	var served: Dictionary = {}
	var with_strip := 0
	var without := 0
	for id: String in st.stations:
		var panel := StationPanels.for_station(StringName(id), _gs)
		if panel == null:
			continue
		var want := AreaLevels.tracks_at(id, st.stations[id])
		if panel is StationPanel:
			var sp := panel as StationPanel
			var have := PackedStringArray(sp.upgrade_rows.keys())
			have.sort()
			var expect := want.duplicate()
			expect.sort()
			var section := sp.find_child("Upgrades", true, false)
			if have != expect or (want.is_empty() != (section == null)):
				wrong.append("%s (%s): rows %s, tracks %s" % [id, st.stations[id].kind, have, want])
			for t: String in want:
				served[t] = true
			if want.is_empty():
				without += 1
			else:
				with_strip += 1
		elif not want.is_empty():
			wrong.append("%s serves %s but its panel is not a station panel" % [id, want])
		panel.free()
	_check("every station that serves an upgrade path has its Upgrades strip, and no other station has one", wrong.is_empty(),
		"; ".join(wrong))
	_check("strips found on %d stations, none on %d others" % [with_strip, without], with_strip >= 7 and without > 5)
	var missing := PackedStringArray()
	for t: String in AreaLevels.track_ids():
		if not served.has(t) and t != "scout_drone":
			missing.append(t)
	if not served.has("scout_drone"):
		print("  note: no drone pad station on the map yet (the drone worker adds it), so the drone strip is not shown")
	_check("every upgrade path (the drone pad aside, until it exists) shows on a station", missing.is_empty(), ", ".join(missing))


# ---------------------------------------------------------------- the Garden upgrade console

func _test_console() -> void:
	var id := _station_of("upgrade_console")
	_check("the Garden upgrade console is on the map", id != "")
	if id == "":
		return
	var panel := StationPanels.for_station(StringName(id), _gs) as StationPanel
	_check("the console gets its own panel script", panel != null and (panel.get_script() as Script).resource_path == CONSOLE_PANEL)
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames()
	panel.refresh()
	_check("the console panel is titled by its station", panel.panel_title() == "Garden upgrade console", panel.panel_title())
	_check("the console shows only the garden strip", panel.upgrade_rows.keys() == ["garden"], str(panel.upgrade_rows.keys()))
	var all := _all_text(panel)
	_check("the console has a short description and no 'more controls later' note",
		all.contains("Plant more of the Garden dome.") and not all.contains(StationPanel.LATER_NOTE), all)
	var lines := panel.upgrade_lines("garden")
	_check("garden strip: name, pips and stage", lines.size() > 2 and lines[0] == "Garden dome planting"
		and lines[1] == "● V1 ○ V2 ○ V3 ○ V4" and lines[2] == "Now: V1: Bare planters", str(lines))
	_check("garden strip: next level words and its effect in plain words", "\n".join(lines).contains("Next: V2: Ground cover and herbs")
		and "\n".join(lines).contains("plants add 0.01 kg of oxygen an hour") and "\n".join(lines).contains("0.5 extra meals each sol"), "\n".join(lines))
	_check("the console's first focus is its upgrade button", panel.first_focus() == panel.upgrade_button("garden"))
	# lay out in real pixels at a small screen, as test_station_panels does (the stricter check)
	var stretch := root.content_scale_mode
	var size0 := root.size
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	await _frames(2)
	panel.refresh()
	await _frames(1)
	var problems := UiLayoutCheck.problems(panel, Vector2(1280, 720))
	problems.append_array(UiLayoutCheck.focus_problems(panel))
	var min_size := panel.get_combined_minimum_size()
	if min_size.x > 1280.0 or min_size.y > 720.0:
		problems.append("minimum size %s is bigger than the screen" % min_size)
	_check("the console panel has no layout or focus problems at 1280x720", problems.is_empty(), "
".join(problems))
	root.content_scale_mode = stretch
	root.size = size0
	panel.queue_free()
	await _frames(1)


# ---------------------------------------------------------------- blocked, then upgraded

func _test_blocked_and_press() -> void:
	var st := _gs.state()
	var console := _station_of("food")
	var me := _play_as(&"biology_food", console)
	st.levels.erase("food")
	st.parts = 0
	var panel := StationPanels.for_station(StringName(console), _gs) as StationPanel
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames()
	panel.refresh()
	var b := panel.upgrade_button("food")
	var text := "\n".join(panel.upgrade_lines("food"))
	_check("greenhouse console: strip with the grow racks", b != null and text.contains("Greenhouse grow racks") and text.contains("Now: V1: One layer of grow beds"), text)
	_check("too few parts: button greyed out and says why", b != null and b.disabled and b.text == "Upgrade to V2"
		and text.contains("✖ Needs 2 spare parts (the colony has 0).") and text.contains("Costs 2 spare parts · the colony has 0"), text)
	_check("the right specialist is told it is them", text.contains("Who can do it: the biology and food specialist (you)"), text)
	_check("the next level's effect in plain words", text.contains("It gives: 2 grow layers · 1.9× the food of the first rack"), text)
	_check("upgrade button takes keyboard focus like the other panel buttons", b != null and b.focus_mode == Control.FOCUS_ALL
		and UiLayoutCheck.focus_problems(panel).is_empty(), "\n".join(UiLayoutCheck.focus_problems(panel)))

	# the wrong specialist, with parts enough
	_play_as(&"electrical_comms", console)
	st.parts = 10
	panel.refresh()
	text = "\n".join(panel.upgrade_lines("food"))
	_check("wrong specialist: greyed out with the specialist reason", b.disabled
		and text.contains("✖ Only the biology and food specialist can upgrade this.") and not text.contains("(you)"), text)

	# the right one presses it: one upgrade_area request through the panel, the level rises
	me = _play_as(&"biology_food", console)
	panel.refresh()
	_check("the right specialist with parts: button ready", not b.disabled and not text.contains("Needs"), "\n".join(panel.upgrade_lines("food")))
	var answers: Array[ActionResult] = []
	var on_answer := func(r: ActionResult) -> void: answers.append(r)
	_gs.events.action_resolved.connect(on_answer)
	b.pressed.emit()
	await _frames(1)
	_gs.events.action_resolved.disconnect(on_answer)
	var ups := answers.filter(func(r: ActionResult) -> bool: return String(r.changes.get("action", "")) == "upgrade_area" or r.reason != &"")
	_check("pressing sends exactly one upgrade_area for the greenhouse console", ups.size() == 1 and ups[0].ok
		and String(ups[0].changes.get("track", "")) == "food" and String(ups[0].changes.get("target", "")) == console,
		"%d answers %s" % [ups.size(), ups.map(func(r: ActionResult) -> String: return "%s %s %s" % [r.ok, r.reason, r.changes])])
	_check("the level rose to V2 and the parts were spent", AreaLevels.level(st, "food") == 2 and st.parts == 8, "level %d, parts %d" % [AreaLevels.level(st, "food"), st.parts])
	_check("the panel shows the host's answer", panel.message_text() == "✓ Greenhouse grow racks upgraded to V2: Two-layer rack with LED bars.", panel.message_text())
	var lines := panel.upgrade_lines("food")
	_check("after the upgrade: V2 pips, the new stage and the next button", lines[1] == "● V1 ● V2 ○ V3 ○ V4"
		and lines[2] == "Now: V2: Two-layer rack with LED bars" and b.text == "Upgrade to V3"
		and "\n".join(lines).contains("Costs 3 spare parts · the colony has 8"), str(lines))

	# refused by the host (moved away): the reason shows, nothing changes
	me.position += Vector3(60.0, 0.0, 0.0)
	b.pressed.emit()
	await _frames(1)
	_check("a refused upgrade shows the host's reason and keeps the level", panel.message_text().begins_with("✖ ") and AreaLevels.level(st, "food") == 2,
		panel.message_text())
	me.position -= Vector3(60.0, 0.0, 0.0)

	# fully upgraded: no button, a plain note
	st.levels["food"] = AreaLevels.max_level()
	panel.refresh()
	text = "\n".join(panel.upgrade_lines("food"))
	_check("at V4 the button goes and the strip says it is fully upgraded", panel.upgrade_button("food") == null
		and text.contains("✓ Fully upgraded (V4).") and text.contains("● V4"), text)
	st.levels.erase("food")
	panel.queue_free()
	await _frames(1)


# ---------------------------------------------------------------- the rover

func _test_rover() -> void:
	var st := _gs.state()
	var garage := _station_of("garage")
	_check("the garage is on the map", garage != "")
	if garage == "":
		return
	var panel := StationPanels.for_station(StringName(garage), _gs) as StationPanel
	var before: Dictionary = (st.rover.levels as Dictionary).duplicate()
	st.rover.levels = {"speed": 4, "torque": 3, "range": 2, "cargo": 1, "traction": 1}
	panel.refresh()
	var text := "\n".join(panel.upgrade_lines("rover"))
	_check("garage: the rover's V level follows its modules", text.contains("Now: " + AreaLevels.stage_text("rover", 3)) and text.contains("● V3 ○ V4"), text)
	_check("garage: no upgrade button for the rover, a garage hint instead", panel.upgrade_button("rover") == null
		and text.contains("Upgrade modules in the garage"), text)
	st.rover.levels = before
	panel.free()


# ---------------------------------------------------------------- the death notice

func _record_of(c: CharacterState) -> Dictionary:
	if "last_death" in c:
		return c.get("last_death")
	return _records.get(c.id, {})


func _set_record(c: CharacterState, rec: Dictionary) -> void:
	if "last_death" in c:
		c.set("last_death", rec)
	else:
		_records[c.id] = rec


func _test_death_notice() -> void:
	var st := _gs.state()
	var hud := GameHud.new()
	root.add_child(hud)
	hud.setup(_gs)
	var notice := hud.death_notice
	var real_field := "last_death" in _gs.local_character()
	if not real_field:
		print("  note: CharacterState has no last_death yet (survival update); the test feeds records itself")
		notice.set(&"record_of", _record_of)
	await _frames()
	_check("the death notice is part of the HUD and hidden at the start", notice != null and hud.root_control().is_ancestor_of(notice) and not notice.visible)
	var me := _gs.local_character()
	var other: CharacterState = null
	for c: CharacterState in st.characters.values():
		if c.id != me.id:
			other = c
			break
	var rec := {"cause": "no_suit_outside", "title": "No suit outside", "text": "You went outside without a suit. Put one on at the suit rack before the airlock.",
		"area": "Outside the base", "at_hours": st.sim_hours, "count": 1}
	_set_record(other, rec.duplicate())
	_gs.events.character_recovered.emit(other.id, {})
	await _frames(1)
	_check("another astronaut's death never shows", not notice.visible)
	_set_record(me, rec.duplicate())
	_gs.events.character_recovered.emit(me.id, {})
	await _frames(1)
	var shown := String(notice.call(&"shown_text"))
	_check("after my respawn the card shows why I died", notice.visible and notice.call(&"title_text") == "No suit outside"
		and shown.contains("You went outside without a suit.") and shown.contains("Where: Outside the base") and shown.contains("Press E to close."), shown)
	_check("first death: no count line", not shown.contains("This has happened"), shown)
	var all_ignore := notice.mouse_filter == Control.MOUSE_FILTER_IGNORE
	for c in notice.find_children("*", "Control", true, false):
		all_ignore = all_ignore and (c as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE and (c as Control).focus_mode == Control.FOCUS_NONE
	_check("the card never takes the mouse or focus", all_ignore)
	hud._place_messages()
	var screen := hud.root_control().get_viewport_rect().size
	var r := notice.get_global_rect()
	_check("the card sits at the top centre", absf(r.get_center().x - screen.x * 0.5) < 2.0 and r.position.y < screen.y * 0.4 and r.size.x > 300.0, str(r))
	var e := InputEventAction.new()
	e.action = &"interact"
	e.pressed = true
	notice.call(&"_input", e)
	_check("E closes it", not notice.visible)
	_gs.events.character_recovered.emit(me.id, {})
	await _frames(1)
	_check("the same death never shows twice", not notice.visible)
	rec.count = 2
	rec.title = "Suit oxygen ran out"
	_set_record(me, rec.duplicate())
	_gs.events.character_recovered.emit(me.id, {})
	await _frames(1)
	shown = String(notice.call(&"shown_text"))
	_check("a new death shows again with how often it happened", notice.visible and shown.contains("Suit oxygen ran out") and shown.contains("This has happened 2 times."), shown)
	notice.call(&"_process", 12.5)
	_check("it goes by itself after about 12 s", not notice.visible)
	# the respawn event can come before the record (networked client): it waits a little for it
	_gs.events.character_recovered.emit(me.id, {})
	await _frames(1)
	_check("no new record yet: nothing shows", not notice.visible)
	rec.count = 3
	_set_record(me, rec.duplicate())
	notice.call(&"_process", 0.3)
	_check("the record arriving just after the respawn still shows", notice.visible and String(notice.call(&"shown_text")).contains("3 times"))
	notice.call(&"dismiss")
	# load: a death from just before the save shows; an old one does not
	rec.count = 4
	rec.at_hours = st.sim_hours - 0.1
	_set_record(me, rec.duplicate())
	notice.call(&"_on_loaded", "test")
	_check("loading a game right after a death shows it", notice.visible and String(notice.call(&"shown_text")).contains("4 times"))
	notice.call(&"dismiss")
	rec.count = 5
	rec.at_hours = st.sim_hours - 30.0
	_set_record(me, rec.duplicate())
	notice.call(&"_on_loaded", "test")
	_check("loading a game long after a death does not show it", not notice.visible)
	_gs.events.character_recovered.emit(me.id, {})
	await _frames(1)
	_check("... and that old death stays seen after the next respawn event", not notice.visible)
	if real_field:
		_set_record(me, {})
		_set_record(other, {})
	_records.clear()
	hud.queue_free()
	await _frames(1)


# ---------------------------------------------------------------- the battery chip

func _test_energy_chip() -> void:
	var st := _gs.state()
	var clock := _gs.clock()
	var chip_script := load(ENERGY_CHIP) as Script
	var chip: Control = chip_script.new()
	root.add_child(chip)
	chip.setup(_gs)
	var outlook := bool(chip_script.call(&"has_outlook"))
	print("  note: PowerModel.outlook %s" % ("found: the chip uses it" if outlook else "not there yet: the chip uses the colony state"))
	var cap := float(st.capacities.get(&"battery_kwh", 0.0))
	var phase0 := clock.phase
	var batt0 := st.store(&"battery_kwh")
	var kw0 := st.battery_kw
	var solar0 := st.solar_kw
	# day, charging
	clock.phase = 0.5
	st.stores[&"battery_kwh"] = cap * 0.8
	st.battery_kw = 3.0
	st.solar_kw = 10.0
	chip.refresh()
	var day := String(chip.call(&"text"))
	var reading: Dictionary = chip.get(&"current")
	_check("day: sun symbol and battery share", day.begins_with("☀ Battery 80 %"), day)
	if not outlook:
		_check("day: charging with its rate", day == "☀ Battery 80 % · charging 3 kW", day)
	else:
		_check("day: words follow the energy model's outlook", bool(reading.from_outlook) and (float(reading.net_kw) > 0.05) == day.contains("charging"), day)
	_check("80 %: normal colour", chip.call(&"level") == &"ok" and chip.call(&"text_color") == AstraStyle.TEXT)
	# night, draining
	clock.phase = 0.9
	st.battery_kw = -4.2
	st.solar_kw = 0.0
	st.stores[&"battery_kwh"] = cap * 0.64
	chip.refresh()
	var night := String(chip.call(&"text"))
	reading = chip.get(&"current")
	var re := RegEx.create_from_string("^☾ Battery 64 % · falling [0-9.]+ kW, (~[0-9]+ h|<1 h|~[0-9.]+ sols) left$")
	_check("night: moon, battery share, how fast it falls and how long it lasts", re.search(night) != null, night)
	if not outlook:
		_check("night: the numbers from the colony state", night.contains("falling 4.2 kW, ~%d h left" % roundi(cap * 0.64 / 4.2)) or night.contains("sols left"), night)
	else:
		_check("night: the numbers from the outlook", night.contains("falling %s kW" % StationPanel.num(-float(reading.net_kw), 1)), night)
	# colours
	st.stores[&"battery_kwh"] = cap * 0.25
	chip.refresh()
	_check("below 30 %: amber", chip.call(&"level") == &"warn" and chip.call(&"text_color") == AstraStyle.WARN, String(chip.call(&"text")))
	st.stores[&"battery_kwh"] = cap * 0.10
	chip.refresh()
	_check("below 15 %: red", chip.call(&"level") == &"urgent" and chip.call(&"text_color") == AstraStyle.DANGER, String(chip.call(&"text")))
	_check("hours in words", chip_script.call(&"hours_words", 0.4) == "<1 h" and chip_script.call(&"hours_words", 9.2) == "~9 h"
		and chip_script.call(&"hours_words", INF) == "—")
	clock.phase = phase0
	st.stores[&"battery_kwh"] = batt0
	st.battery_kw = kw0
	st.solar_kw = solar0
	chip.queue_free()


# ---------------------------------------------------------------- the level-up pop-up and the HUD layout

func _test_toast_and_layout() -> void:
	var st := _gs.state()
	var game := FakeGame.new()
	root.add_child(game)
	game.hud = GameHud.new()
	game.add_child(game.hud)
	game.hud.setup(_gs)
	var mh := MissionHud.new()
	mh.setup(null, _gs, game)
	await _frames(3)
	_check("level-up words from the alert", MissionHud.level_up_text(&"area_level_food", "Greenhouse grow racks upgraded to V3: Three-layer rack with drip lines.", st)
		== "Greenhouse grow racks: V3: Three-layer rack with drip lines")
	var console := _station_of("food")
	_play_as(&"biology_food", console)
	st.parts = 10
	st.levels["food"] = 2
	var r := _gs.request(&"upgrade_area", StringName(console), {"track": "food"})
	await _frames(1)
	_check("a real upgrade raises the level", r.ok and AreaLevels.level(st, "food") == 3, String(r.message))
	_check("a level up pops up: 'Greenhouse grow racks: V3: Three-layer rack with drip lines'",
		mh.toasts.texts().has("Greenhouse grow racks: V3: Three-layer rack with drip lines"), str(mh.toasts.texts()))
	_check("the HUD's last alert uses the same words", game.hud.last_alert_text == "Greenhouse grow racks: V3: Three-layer rack with drip lines", game.hud.last_alert_text)
	# a level up made by someone else (another track, another station) pops up too
	var med := _station_of("heal")
	_play_as(&"medical_life_support", med)
	r = _gs.request(&"upgrade_area", StringName(med), {"track": "health"})
	await _frames(1)
	_check("any track's level up pops up", r.ok and mh.toasts.texts().has("Med bay: V2: Vitals monitors and an IV stand"), str(mh.toasts.texts()))
	# the battery chip hangs under the vitals bar and the messages move below it
	mh._layout()
	var chip := mh.energy
	var vr := mh.vitals.get_global_rect()
	var cr := chip.get_global_rect()
	_check("the battery chip sits just under the vitals bar", chip.visible and cr.position.y >= vr.end.y and cr.position.y - vr.end.y < 20.0
		and absf(cr.get_center().x - vr.get_center().x) < 2.0, "vitals %s chip %s" % [vr, cr])
	_check("HUD messages start below the chip", game.hud.top_reserved >= cr.end.y - 0.5, "%s < %s" % [game.hud.top_reserved, cr.end.y])
	_check("the chip has text", String(chip.call(&"text")).contains("Battery"), String(chip.call(&"text")))
	st.levels.erase("food")
	st.levels.erase("health")
	game.queue_free()
	await _frames(1)


func _all_text(node: Node) -> String:
	var parts := PackedStringArray()
	for l in node.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree():
			parts.append((l as Label).text)
	return "\n".join(parts)
