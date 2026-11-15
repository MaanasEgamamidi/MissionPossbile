extends SceneTree
## Part D: station surfaces, power switches, computer navigation, upgrade cards and the blueprint map.
## Run: ..\godot.cmd --headless --path . --script res://tests/test_station_panels.gd


## Collects engine and script errors raised while the test runs.
class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR or error_type == ERROR_TYPE_SCRIPT:
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


const SIZES := [[Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 1.0], [Vector2i(1280, 720), 1.5]]

var _passed := 0
var _total := 0
var _catcher := ErrorCatcher.new()
var _gs: GameServices
var _noted_stub_scale := false


func _initialize() -> void:
	OS.add_logger(_catcher)
	PlayerInput.ensure_actions()
	_gs = GameServices.new()
	_gs.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/wD"), "colony", 2)
	root.add_child(_gs)
	_gs.start_new_game(1)
	await process_frame
	_test_for_station()
	await _test_power()
	await _test_computer()
	await _test_readings()
	await _test_upgrades()
	await _test_blueprint()
	await _test_layouts()
	_check("no errors during the test", _catcher.errors.is_empty(), "\n".join(_catcher.errors))
	OS.remove_logger(_catcher)
	_gs.queue_free()
	await process_frame
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


# ---------------------------------------------------------------- station surfaces

func _test_for_station() -> void:
	var st := _gs.state()
	var bad := PackedStringArray()
	var count := 0
	var base: Array = ["power", "computer", "comms", "food", "lifesupport", "heal", "board", "survivor", "suits", "solar"]
	for id: String in st.stations:
		var kind := String(st.stations[id].kind)
		if base.has(kind):
			count += 1
		var panel := StationPanels.for_station(StringName(id), _gs)
		# Prompt 07: the life-support console, the suit rack and the 12 sun trackers have their own panels.
		var ok := false
		match kind:
			"cassette_player_anchor", "cassette_player":
				ok = panel is CassettePlayerPanel and (panel as CassettePlayerPanel).station_id == CassetteLibrary.PLAYER_ID
			"suits":
				ok = panel is SuitRackPanel
			"power":
				ok = panel is PowerStationPanel
			"lifesupport":
				ok = panel is LifeSupportStationPanel
			"solar":
				ok = panel is SolarStationPanel
			"repair_task":
				# Broken parts (2026-11-14): while a task's spot is broken, E opens its mini-game; otherwise maintenance.
				ok = panel is TaskPanel if PuzzleRegistry.is_broken(st, String(st.stations[id].get("task_id", ""))) else panel is StationPanel
			_:
				ok = panel is StationPanel and not (panel is PowerStationPanel or panel is LifeSupportStationPanel
					or panel is SolarStationPanel or panel is SuitRackPanel)
		ok = ok and panel != null
		if panel is StationPanel:
			ok = ok and (panel as StationPanel).kind == kind
		if panel != null:
			ok = ok and bool(panel.get_meta(&"station_surface", false)) and StringName(panel.get_meta(&"station_id", &"")) == StringName(id)
			# Built-in kinds use their kind's name; data-file stations may name themselves (beds are numbered: "Planter 2").
			ok = ok and (panel.panel_title() == StationPanels.name_of(kind) if base.has(kind) else panel.panel_title() != "")
			panel.free()
		if not ok:
			bad.append("%s (%s)" % [id, kind])
	_check("for_station: right panel for every station (21 base + those added by data files), suit rack included", count == 21 and bad.is_empty(),
		"%d stations, wrong: %s" % [count, ", ".join(bad)])


func _test_power() -> void:
	var st := _gs.state()
	var me := _gs.local_character()
	var station_pos := CharacterState._v3(st.stations["pw_panel"].position)
	me.position = station_pos
	var panel := StationPanels.for_station(&"pw_panel", _gs) as PowerStationPanel
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	_check("power panel has a switch for every zone", panel.switches.size() == st.zones.size() and panel.switches.size() > 0,
		"%d switches for %d zones" % [panel.switches.size(), st.zones.size()])

	var answers: Array[ActionResult] = []
	var flips: Array = []
	var on_answer := func(r: ActionResult) -> void: answers.append(r)
	var on_flip := func(zone: String, on: bool) -> void: flips.append([zone, on])
	_gs.events.action_resolved.connect(on_answer)
	_gs.events.zone_power_changed.connect(on_flip)

	for zone: String in ["Greenhouse", "Hangar bay"]:
		answers.clear()
		flips.clear()
		var load_before := StationPanel.colony_load_kw(st, _gs.balance)
		var text_before := panel.load_text()
		panel.switch_for(zone).button_pressed = false
		panel.refresh()
		var expected := load_before - _gs.balance.load_of_zone(zone)
		_check("switch %s off sends exactly one set_zone_power with the right zone and value" % zone,
			answers.size() == 1 and answers[0].ok and flips == [[zone, false]] and not st.is_zone_powered(zone),
			"%d answers, flips %s" % [answers.size(), str(flips)])
		_check("load text updates after %s off" % zone, panel.load_text() == "%s kW" % StationPanel.num(expected) and panel.load_text() != text_before,
			"before '%s', now '%s', expected %s kW" % [text_before, panel.load_text(), StationPanel.num(expected)])
		_check("cause and effect sentence for %s" % zone, panel.cause_text() == "%s off: the colony now uses %s kW." % [zone, StationPanel.num(expected)],
			panel.cause_text())

	# The host refuses when the player is too far from the panel: the switch flips back and says why.
	me.position = station_pos + Vector3(40.0, 0.0, 0.0)
	answers.clear()
	flips.clear()
	var sw := panel.switch_for("Med Bay")
	sw.button_pressed = false
	_check("refused switch: one request, host answers too_far", answers.size() == 1 and answers[0].reason == &"too_far" and flips.is_empty(),
		"%d answers %s, flips %s" % [answers.size(), answers.map(func(r: ActionResult) -> String: return String(r.reason)), str(flips)])
	_check("refused switch flips back and shows the reason", sw.button_pressed and st.is_zone_powered("Med Bay")
		and panel.message_text().contains(String(ActionResult.MESSAGES[&"too_far"])), "pressed %s, message '%s'" % [sw.button_pressed, panel.message_text()])

	# A change made elsewhere shows on refresh().
	me.position = station_pos
	_gs.request(&"set_zone_power", &"pw_panel", {"zone": "Greenhouse", "on": true})
	panel.refresh()
	_check("switch reflects the state on refresh", panel.switch_for("Greenhouse").button_pressed
		and panel.load_text() == "%s kW" % StationPanel.num(StationPanel.colony_load_kw(st, _gs.balance)), panel.load_text())
	_gs.request(&"set_zone_power", &"pw_panel", {"zone": "Hangar bay", "on": true})

	_gs.events.action_resolved.disconnect(on_answer)
	_gs.events.zone_power_changed.disconnect(on_flip)
	panel.queue_free()
	await process_frame


func _test_computer() -> void:
	var panel := StationPanels.for_station(&"cm_colony_computer", _gs) as StationPanel
	root.add_child(panel)
	await process_frame
	await process_frame
	var opened: Array[UiPanel] = []
	panel.open_requested.connect(func(p: UiPanel) -> void: opened.append(p))
	for key: String in ["summary", "upgrades"]:
		var b := panel.computer_buttons.get(key) as Button
		if b != null:
			b.pressed.emit()
	# the Blueprint map button is switched off since 301d499 (owner: the big goals screen, J, has the map)
	_check("computer buttons open Colony summary and Upgrades; no Blueprint button (off since 301d499)", opened.size() == 2 and opened[0] is ColonySummaryPanel
		and opened[1] is UpgradeCardsPanel and not panel.computer_buttons.has("blueprint"), str(opened))
	for p in opened:
		p.free()
	panel.queue_free()
	await process_frame


func _test_readings() -> void:
	var expect := {
		&"ls_console": {&"oxygen": " kg", &"water": " L", &"wastewater": " L", &"o2": " kPa"},
		&"gh_console": {&"food": " meals", &"food_use": " meals per sol", &"food_left": "sols"},
		&"md_heal_station": {&"health_crew_1": "% health"},
	}
	var bad := PackedStringArray()
	for id: StringName in expect:
		var panel := StationPanels.for_station(id, _gs) as StationPanel
		root.add_child(panel)
		await process_frame
		panel.refresh()
		var want: Dictionary = expect[id]
		for key: StringName in want:
			var row := panel.readings.get(key) as StationPanel.Reading
			if row == null or not row.value_label.text.contains(String(want[key])) or row.explain == null or row.mark_label.text.is_empty():
				bad.append("%s/%s '%s'" % [id, key, row.value_label.text if row != null else "missing"])
		panel.queue_free()
	await process_frame
	_check("station readings show values with units, a status mark and a ? button", bad.is_empty(), "; ".join(bad))


# ---------------------------------------------------------------- upgrade cards

func _test_upgrades() -> void:
	var st := _gs.state()
	var up := UpgradeCardsPanel.new()
	up.setup(_gs)
	root.add_child(up)
	up.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	var sectors := {}
	var fields_ok := true
	for d in up.definitions:
		var extra: Dictionary = up.extras.get(d.id, {})
		sectors[String(extra.get("sector", ""))] = true
		fields_ok = fields_ok and d is UpgradeDefinition and d.id != &"" and not d.title.is_empty() and not d.zone.is_empty() and d.cost_parts > 0 \
			and UpgradeCardsPanel.SECTORS.has(String(extra.get("sector", ""))) and not String(extra.get("effect", "")).is_empty() \
			and not d.questions.is_empty() and not d.evidence.is_empty() and d.install_station != &""
	# Prompt 08: the real catalogue (16 cards) replaced the 8 placeholder cards.
	# Prompt 11 added the four radio cards (energy sector).
	_check("upgrade cards load into UpgradeDefinition (16 + 4 radio cards, all five sectors)", up.definitions.size() == 16 + CommsStage.CARD_IDS.size()
		and fields_ok and sectors.size() == 5 and not up.note.is_empty(), "%d cards, sectors %s" % [up.definitions.size(), sectors.keys()])

	var bad := PackedStringArray()
	for i in up.definitions.size():
		var d := up.definitions[i]
		var cost := up.cost_label(d.id).text
		var reason := up.reason_label(d.id).text
		var b := up.install_buttons[i]
		if not cost.contains("Needs %d parts — the colony has %d" % [d.cost_parts, st.parts]):
			bad.append("%s cost '%s'" % [d.id, cost])
		if reason.is_empty() or reason.split(" ", false).size() > 6:           # UI overhaul: ONE short reason on the card
			bad.append("%s reason '%s'" % [d.id, reason])
		if not b.disabled or b.tooltip_text.is_empty() or not b.visible:
			bad.append("%s install button" % d.id)
	_check("cards show cost vs parts, the locked reason, and a disabled install button", bad.is_empty(), "; ".join(bad))
	var tracking := "\n".join(up.requirement_lines(&"energy_solar_tracking"))          # UI overhaul: the full list is under "More"
	var automation := "\n".join(up.requirement_lines(&"energy_cleaner_automation"))
	_check("locked reasons in words: sector level, questions to answer, things to do", up.cost_label(&"energy_solar_tracking").text.begins_with("✓")
		and tracking.contains("Energy level 1 needed") and tracking.contains("Answer: ") and automation.contains("Energy level 2 needed")
		and automation.contains("Do: "), "%s | %s" % [tracking, automation])

	# Keyboard: focus starts on the first card and arrow keys move between cards.
	var first := up.first_focus()
	first.grab_focus()
	await process_frame
	var started := first.has_focus()
	root.push_input(_key(KEY_RIGHT))
	await process_frame
	var moved_right := up.install_buttons[1].has_focus()
	root.push_input(_key(KEY_LEFT))
	await process_frame
	var moved_back := up.install_buttons[0].has_focus()
	_check("keyboard focus moves between the cards", first == up.install_buttons[0] and started and moved_right and moved_back,
		"started %s, right %s, back %s" % [started, moved_right, moved_back])
	up.queue_free()
	await process_frame


# ---------------------------------------------------------------- blueprint

func _test_blueprint() -> void:
	var st := _gs.state()
	var me := _gs.local_character()
	var hub := _gs.config.hub_position
	st.caches.append({"id": "cache_test", "position": [hub.x + 3.0, 0.0, hub.z + 2.0], "items": []})
	var bp := BlueprintPanel.new()
	bp.setup(_gs)
	root.add_child(bp)
	bp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	var view := bp.view
	var errors_before := _catcher.errors.size()
	var draws := view.draw_count
	view.queue_redraw()
	await process_frame
	_check("blueprint draws without errors", view.draw_count > draws and _catcher.errors.size() == errors_before and view.drawn_rooms.size() == view.rooms().size(),
		"draws %d -> %d, rooms %d of %d" % [draws, view.draw_count, view.drawn_rooms.size(), view.rooms().size()])

	# A room's centre maps to the drawn rectangle's centre; the plan keeps its shape and north is up.
	var details := PackedStringArray()
	var ok := true
	for room_name: String in ["Greenhouse", "Command Room"]:
		var r := _room(view, room_name)
		var centre := Vector2((float(r.x0) + float(r.x1)) * 0.5, (float(r.y0) + float(r.y1)) * 0.5)
		var rect: Rect2 = view.drawn_rooms[room_name]["rect"]
		var d := view.world_to_view(centre).distance_to(rect.get_center())
		var k := view.plan_scale()
		var size_ok := absf(rect.size.x - (float(r.x1) - float(r.x0)) * k) < 1.0 and absf(rect.size.y - (float(r.y1) - float(r.y0)) * k) < 1.0
		var back := view.view_to_world(rect.get_center()).distance_to(centre)
		ok = ok and d <= 1.0 and size_ok and back < 0.05 and view.get_rect().has_point(view.position + rect.get_center())
		details.append("%s: %.2f px, size %s, back %.3f m" % [room_name, d, size_ok, back])
	var gh: Rect2 = view.drawn_rooms["Greenhouse"]["rect"]
	var cm: Rect2 = view.drawn_rooms["Command Room"]["rect"]
	ok = ok and gh.get_center().x < cm.get_center().x and gh.get_center().y > cm.get_center().y
	_check("blueprint converts coordinates (room centre within 1 px, west left, north up)", ok, "; ".join(details))

	# Unpowered rooms are drawn dim with ✖.
	me.position = CharacterState._v3(st.stations["pw_panel"].position)
	var res := _gs.request(&"set_zone_power", &"pw_panel", {"zone": "Greenhouse", "on": false})
	bp.refresh()
	await process_frame
	_check("blueprint shows an unpowered room dimmed with ✖", res.ok and bool(view.drawn_rooms["Greenhouse"]["dim"])
		and not bool(view.drawn_rooms["Mess hall"]["dim"]) and view.symbols_used.has("✖"), "%s %s" % [res.reason, view.drawn_rooms["Greenhouse"]])

	# Click a room: its name, power and load.
	var target := view.room_rect("Greenhouse").get_center()
	view._gui_input(_click(target, true))
	view._gui_input(_click(target, false))
	_check("clicking a room shows its name, power state and load", view.selected_zone == "Greenhouse" and bp.info_label.text.contains("Greenhouse")
		and bp.info_label.text.contains("no power") and bp.info_label.text.contains("%s kW" % StationPanel.num(_gs.balance.load_of_zone("Greenhouse"))), bp.info_label.text)
	await process_frame

	# The legend explains every symbol that was drawn.
	var keys := {}
	for entry: Array in BlueprintView.legend():
		keys[String(entry[0])] = true
	var lines := bp.legend_text().split("\n")
	var missing := PackedStringArray()
	for sym: String in view.symbols_used:
		var listed := false
		for line in lines:
			if line.begins_with(sym + " "):
				listed = true
		if not keys.has(sym) or not listed:
			missing.append(sym)
	var expected_used := ["▭", "✖", "▢", "◯", "◌", "▲", "■", "!", "↑", "⚡", "B"]
	for sym: String in expected_used:
		if not view.symbols_used.has(sym):
			missing.append("(not drawn) " + sym)
	_check("legend lists every symbol used", missing.is_empty() and view.symbols_used.size() >= expected_used.size(), "missing: %s; used %s" % [", ".join(missing), view.symbols_used.keys()])

	# Zoom and centre on me.
	var w_before := view.room_rect("Command Room").size.x
	view.zoom_by(2.0)
	var w_after := view.room_rect("Command Room").size.x
	view.centre_on_me()
	var me_at := view.world_to_view(BlueprintView.godot_to_plan(me.position))
	_check("zoom doubles the plan and Centre on me puts you in the middle", absf(w_after - 2.0 * w_before) < 0.5 and me_at.distance_to(view.size * 0.5) < 1.0,
		"width %.1f -> %.1f, you at %s of %s" % [w_before, w_after, me_at, view.size])

	_gs.request(&"set_zone_power", &"pw_panel", {"zone": "Greenhouse", "on": true})
	st.caches.clear()
	bp.queue_free()
	await process_frame


# ---------------------------------------------------------------- layout at three sizes

func _test_layouts() -> void:
	var st := _gs.state()
	var panels: Array[UiPanel] = []
	for id: String in st.stations:
		var p := StationPanels.for_station(StringName(id), _gs)
		if p != null:
			panels.append(p)
	var up := UpgradeCardsPanel.new()
	up.setup(_gs)
	panels.append(up)
	var bp := BlueprintPanel.new()
	bp.setup(_gs)
	panels.append(bp)
	# The project stretches a 1920x1080 canvas to any window, so 2D units would never be 1280x720. Lay out in real
	# pixels instead: that is the stricter check (a 1280x720 screen really has only 1280x720 pixels of room).
	var stretch := root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	for panel in panels:
		root.add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var layout := PackedStringArray()
		var focus := PackedStringArray()
		for s: Array in SIZES:
			root.size = s[0]
			_apply_text_scale(float(s[1]))
			await process_frame
			await process_frame
			panel.refresh()
			await process_frame
			for line in UiLayoutCheck.problems(panel, Vector2(s[0])):
				layout.append("%s at %s text %s: %s" % [panel.name, s[0], s[1], line])
			# UiRoot centres a panel at its minimum size, so that size must fit the screen too.
			var min_size := panel.get_combined_minimum_size()
			if min_size.x > float(s[0].x) or min_size.y > float(s[0].y):
				layout.append("%s at %s text %s: minimum size %s is bigger than the screen" % [panel.name, s[0], s[1], min_size])
			for line in UiLayoutCheck.focus_problems(panel):
				focus.append("%s at %s text %s: %s" % [panel.name, s[0], s[1], line])
		_apply_text_scale(1.0)
		_check("layout %s (%s) at 1280x720, 1920x1080 and text 1.5" % [panel.name, panel.panel_title()], layout.is_empty(), "\n  ".join(layout))
		_check("focus %s (%s)" % [panel.name, panel.panel_title()], focus.is_empty() and not UiLayoutCheck.focusable(panel).is_empty(), "\n  ".join(focus))
		panel.queue_free()
		await process_frame
	root.content_scale_mode = stretch


# ---------------------------------------------------------------- helpers

## Applies a text scale. While UiTheme is still the stub (its apply_text_scale changes nothing), the test sets the
## shared theme's default font size itself so the 1.5 check really uses bigger text.
func _apply_text_scale(s: float) -> void:
	UiTheme.apply_text_scale(s)
	var t := UiTheme.get_theme()
	var wanted := roundi(UiTheme.BASE_FONT_SIZE * s)
	if s != 1.0 and t.default_font_size == UiTheme.BASE_FONT_SIZE:
		if not _noted_stub_scale:
			print("NOTE UiTheme.apply_text_scale is the stub: the test sets the theme's default font size to %d itself" % wanted)
			_noted_stub_scale = true
		t.default_font_size = wanted
	elif s == 1.0 and _noted_stub_scale:
		t.default_font_size = UiTheme.BASE_FONT_SIZE


func _room(view: BlueprintView, room_name: String) -> Dictionary:
	for r: Dictionary in view.rooms():
		if String(r.name) == room_name:
			return r
	return {}


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e


func _click(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = at
	e.pressed = pressed
	return e


func _check(test_name: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS %s" % test_name)
	else:
		print("FAIL %s: %s" % [test_name, detail])
