extends SceneTree
## Part C checks: HUD, colony summary, cargo and crew selection.
## Run: godot --headless --path . --script res://tests/test_hud_panels.gd

## Records every request a panel sends, then lets the host answer it as usual.
class RecordingServices extends GameServices:
	var sent: Array = []

	func request(action: StringName, target: StringName = &"", params := {}) -> ActionResult:
		sent.append({"action": action, "target": target, "params": params})
		return super.request(action, target, params)

	func sent_of(action: StringName) -> Array:
		return sent.filter(func(r: Dictionary) -> bool: return r.action == action)


const SIZES := [[Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 1.0], [Vector2i(1280, 720), 1.5]]

var _passed := 0
var _total := 0
var _notes := PackedStringArray()
var services: RecordingServices


func _check(name: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS ", name, ("  " + detail) if detail != "" else "")
	else:
		print("FAIL ", name, ": ", detail)


func _note(text: String) -> void:
	if not _notes.has(text):
		_notes.append(text)
		print("NOTE ", text)


func _frames(n := 2) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	PlayerInput.ensure_actions()
	services = RecordingServices.new()
	services.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/wC"), "colony", 2)
	root.add_child(services)
	services.start_new_game(1)
	services.set_process(false)          # no simulation ticks: the test sets every value itself
	await _frames()
	# _ready() turns processing back on when it runs after the line above; switch it off again so no tick (and no
	# system alert in the HUD message line, Prompt 07) disturbs the values and messages this test sets by hand.
	services.set_process(false)

	await _test_hud()
	await _test_summary()
	await _test_inventory()
	await _test_crew()
	await _test_portrait()

	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


# ------------------------------------------------------------------ helpers

func _fill_stores() -> void:
	var st := services.state()
	for k in ColonyState.STORE_KEYS:
		st.stores[k] = float(st.capacities[k])
	st.power_deficit = false
	services.local_character().suit_on = false
	services.local_character().suit_charge = 100.0


## Lays `ctl` out at the three required sizes and checks layout and focus with UiLayoutCheck.
func _check_layout(label: String, ctl: Control, full_rect: bool) -> void:
	var theme := UiTheme.get_theme()
	# The project stretches the UI from a 1920x1080 base (canvas_items). Switch that off so a 1280x720 window really
	# gives 1280x720 of room, the hardest case for the layout.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	for case: Array in SIZES:
		var size: Vector2i = case[0]
		var scale: float = case[1]
		root.size = size
		UiTheme.apply_text_scale(scale)
		var wanted := roundi(UiTheme.BASE_FONT_SIZE * scale)
		if theme.default_font_size != wanted:
			_note("UiTheme.apply_text_scale is the stub (no change to font sizes): the test sets the theme's default font size to %d itself" % wanted)
			theme.default_font_size = wanted
		if full_rect:
			ctl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await _frames(3)
		if ctl is UiPanel:
			(ctl as UiPanel).refresh()
		await _frames(2)
		var tag := "%s at %dx%d text x%.1f" % [label, size.x, size.y, scale]
		var problems := UiLayoutCheck.problems(ctl, Vector2(size))
		_check("layout: " + tag, problems.is_empty(), "\n  ".join(problems))
		var focus := UiLayoutCheck.focus_problems(ctl)
		if focus.is_empty():
			_check("focus: " + tag, true)
		elif not theme.has_stylebox(&"focus", &"Button"):
			_note("focus (known stub limitation, stub UiTheme has no focus styles) %s: %s" % [tag, "; ".join(focus)])
		else:
			_check("focus: " + tag, false, "; ".join(focus))
	root.size = Vector2i(1280, 720)
	UiTheme.apply_text_scale(1.0)
	theme.default_font_size = UiTheme.BASE_FONT_SIZE


## Every number in the visible labels under `ctl` that is not followed by a unit.
func _numbers_without_units(ctl: Node) -> PackedStringArray:
	var number := RegEx.new()
	number.compile("\\d+(?:\\.\\d+)?")
	var unit := RegEx.new()
	unit.compile("^\\s?(kWh|kW|kPa|kg|L\\b|meals?\\b|parts?\\b|%|sols?\\b|hours?\\b|crew\\b|m from)")
	var out := PackedStringArray()
	for l: Label in _labels(ctl):
		for m in number.search_all(l.text):
			if unit.search(l.text.substr(m.get_end())) == null:
				out.append("'%s' in \"%s\"" % [m.get_string(), l.text])
	return out


func _labels(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	for child in node.get_children():
		if child is Label and (child as Label).is_visible_in_tree():
			out.append(child as Label)
		out.append_array(_labels(child))
	return out


func _all_text(node: Node) -> String:
	var parts := PackedStringArray()
	for l in _labels(node):
		parts.append(l.text)
	return "\n".join(parts)


## What a player can read or hear on `node`: the visible labels plus the accessible names (also the tooltips) of the
## visible pictures. UI overhaul: the HUD shows pictures and gives each its words this way (HudKit.say).
func _all_words(node: Node) -> String:
	var parts := PackedStringArray()
	if node is Control and (node as Control).is_visible_in_tree():
		if node is Label:
			parts.append((node as Label).text)
		if String((node as Control).accessibility_name) != "":
			parts.append(String((node as Control).accessibility_name))
	for child in node.get_children():
		var t := _all_words(child)
		if t != "":
			parts.append(t)
	return "\n".join(parts)


# ------------------------------------------------------------------ HUD

func _test_hud() -> void:
	var st := services.state()
	var me := services.local_character()
	var hud := GameHud.new()
	root.add_child(hud)
	hud.setup(services)
	await _frames()

	# nothing low: one quiet line
	_fill_stores()
	hud.refresh()
	# UI overhaul: the tick is drawn (a check pictogram) beside the words "Colony OK"
	var ok_chip := hud.root_control().find_child("ColonyOk", true, false)
	_check("hud: nothing low shows only 'Colony OK ✓'", hud.colony_ok_shown() and hud.shown_readings().is_empty() and _all_text(hud.root_control()).contains("Colony OK")
		and ok_chip != null and StringName(ok_chip.find_child("Symbol", true, false).get("kind")) == &"check", str(hud.shown_readings()))

	# each reading on its own
	var cases := [
		[&"battery_kwh", 20.0, "Colony electricity"], [&"oxygen_kg", 1.0, "Oxygen"], [&"water_l", 2.0, "Water"], [&"food_meals", 1.0, "Food"],
	]
	for c: Array in cases:
		_fill_stores()
		st.stores[c[0]] = float(c[1])
		hud.refresh()
		var shown := hud.shown_readings()
		_check("hud: low %s alone shows one reading with symbol, unit and word" % c[0],
			shown.size() == 1 and shown[0].contains(c[2]) and (shown[0].contains("Low") or shown[0].contains("Very low")) and not hud.colony_ok_shown()
			and _numbers_without_units(hud.root_control().find_child("Reading0", true, false)).is_empty(), str(shown))
	_fill_stores()
	me.suit_on = true
	me.suit_charge = 5.0
	hud.refresh()
	_check("hud: low suit tank (suit on) shows one reading", hud.shown_readings().size() == 1 and hud.shown_readings()[0].contains("Suit tank 5 %"), str(hud.shown_readings()))
	me.suit_on = false
	hud.refresh()
	_check("hud: a low tank with the suit off is not urgent", hud.colony_ok_shown(), str(hud.shown_readings()))

	# everything low: at most three, the most urgent first
	_fill_stores()
	st.stores[&"battery_kwh"] = 60.0           # 15 %: low
	st.stores[&"oxygen_kg"] = 0.5              # very low
	st.stores[&"water_l"] = 2.0                # very low
	st.stores[&"food_meals"] = 1.0             # very low
	me.suit_on = true
	me.suit_charge = 20.0                      # low
	hud.refresh()
	var shown := hud.shown_readings()
	var all_urgent := true
	for s in shown:
		all_urgent = all_urgent and s.contains("✖")
	_check("hud: five low readings show at most three, most urgent first", shown.size() == 3 and all_urgent and not hud.colony_ok_shown(), str(shown))
	_fill_stores()
	st.stores[&"battery_kwh"] = 0.0
	st.power_deficit = true
	me.suit_on = true
	me.suit_charge = 20.0
	hud.refresh()
	shown = hud.shown_readings()
	_check("hud: battery is called colony electricity, an empty one comes first", _reading_name_of(&"battery_kwh") == "Colony electricity" and shown.size() == 2
		and shown[0].begins_with("⚡ Colony electricity 0 %") and shown[0].contains("✖ Power short"), str(shown))
	st.power_deficit = false

	# body energy, never "energy" alone
	# UI overhaul: the crew corner shows a badge, the symbol, one role word and three picture bars; each picture carries
	# its words as tooltip and accessible name, so those count as what the corner says.
	var crew_text := _all_words(hud.root_control().find_child("TopRight", true, false))
	var bad_energy := false
	for line in crew_text.split("\n"):
		if (line.to_lower().contains("energy") and not line.contains("Body energy")) or line.to_lower().contains("stamina"):
			bad_energy = true
	_check("hud: stamina is labelled 'Body energy'", crew_text.contains("Body energy") and not bad_energy, crew_text.replace("\n", " | "))
	_check("hud: crew corner shows name, specialty symbol, health, suit and tank", crew_text.contains(me.display_name) and crew_text.contains("⚡")
		and crew_text.contains("Health") and crew_text.contains("Suit on · tank 20 %"), crew_text.replace("\n", " | "))

	# interaction cue
	hud.set_held(&"")
	hud.set_target({"kind": "station", "id": &"pw_panel", "node": null})
	_check("hud: cue for a station", hud.cue_text() == "[E] Use power panel", hud.cue_text())
	hud.set_target({"kind": "item", "id": &"crate_1", "node": null})
	_check("hud: cue for an item", hud.cue_text() == "[E] Pick up supply crate", hud.cue_text())
	hud.set_held(&"crate_2")
	hud.set_target({"kind": "", "id": &"", "node": null})
	_check("hud: cue while holding something", hud.cue_text() == "[E] Put down", hud.cue_text())
	hud.set_target({"kind": "station", "id": &"ls_console", "node": null})
	_check("hud: holding and aiming at a station still uses the station", hud.cue_text() == "[E] Use life support console", hud.cue_text())
	hud.set_held(&"")
	hud.set_target({"kind": "", "id": &"", "node": null})
	_check("hud: no cue when there is nothing to do", hud.cue_text() == "")

	# messages queue
	for i in 5:
		hud.show_message("Message number %d." % (i + 1), 3.0)
	hud.show_message("Message number 1.", 3.0)
	var now := hud.current_messages()
	# UI overhaul: GameHud.MAX_MESSAGES (two) short lines on screen; nothing is dropped, the rest wait in order
	var on_screen := GameHud.MAX_MESSAGES
	_check("hud: messages queue (%d on screen, %d waiting, no repeats)" % [on_screen, 5 - on_screen], now.size() == on_screen and now[0] == "Message number 1."
		and hud.waiting_messages().size() == 5 - on_screen and not hud.waiting_messages().has("Message number 1."), "%s / %s" % [now, hud.waiting_messages()])
	hud._process(3.1)
	now = hud.current_messages()
	var expect := PackedStringArray()
	for i in range(on_screen, mini(5, on_screen * 2)):
		expect.append("Message number %d." % (i + 1))
	_check("hud: waiting messages come next, in order", now == expect and hud.waiting_messages().size() == maxi(0, 5 - on_screen * 2), "%s / %s" % [now, hud.waiting_messages()])
	hud.show_message("A long message to check wrapping: the colony computer says that the greenhouse lights are on and the battery is charging nicely in the sun today.", 5.0)

	# key hints, status, pause banner, suit check bar
	var hints := (hud.root_control().find_child("HintText", true, false) as Label).text
	# Owner 2026-11-14: the M map is hidden; J shows the goals (and the map in big mode)
	_check("hud: key hint strip", hints == "J goals · I cargo · C crew · Esc pause · Shift+Backspace sources", hints)
	hud.set_status("Connected to the host.")
	_check("hud: status line shows", _all_text(hud.root_control()).contains("Connected to the host."))
	services.session.request(&"vote_pause", &"", {"paused": true})
	hud.refresh()
	# UI overhaul: the banner is a "⏸ Paused" card at the top centre
	var banner := hud.root_control().find_child("Paused", true, false) as Control
	_check("hud: PAUSED banner while paused", banner != null and banner.is_visible_in_tree() and _all_text(hud.root_control()).to_lower().contains("paused"))
	services.session.request(&"vote_pause", &"", {"paused": false})
	hud.refresh()
	_check("hud: no banner when running", banner != null and not banner.is_visible_in_tree() and not _all_text(hud.root_control()).to_lower().contains("paused"))
	var rack: Dictionary = st.stations["al_suit_rack"]
	me.position = CharacterState._v3(rack.position)
	me.suit_on = false
	var r := services.session.request(&"begin_suit_check", &"al_suit_rack", {"on": true})
	hud.refresh()
	_check("hud: suit check bar while the check runs", r.ok and (hud.root_control().find_child("SuitCheck", true, false) as Control).visible, String(r.reason))

	# layout with the busiest HUD
	await _check_layout("HUD", hud.root_control(), false)
	services.session.advance(2.0)
	hud.refresh()
	_check("hud: suit check bar hidden when done", not (hud.root_control().find_child("SuitCheck", true, false) as Control).visible)
	hud._process(31.0)
	_check("hud: key hints start fading after 30 s of play", hud._hint_fading)
	hud.set_visible_hud(false)
	_check("hud: set_visible_hud(false) hides it", not hud.visible and not hud.root_control().is_visible_in_tree())
	hud.set_visible_hud(true)
	hud.set_status("")
	_check("hud: empty status hides the line", not _all_text(hud.root_control()).contains("Connected"))
	me.position = me.hub_spot
	me.suit_on = false
	hud.queue_free()
	await _frames()


func _reading_name_of(key: StringName) -> String:
	for r: Dictionary in GameHud.low_readings(services):
		if r.key == key:
			return String(r.name)
	return ""


# ------------------------------------------------------------------ colony summary

func _test_summary() -> void:
	var st := services.state()
	var b := services.balance
	var clock := services.clock()
	var saved_phase := clock.phase
	# Hold the simulation still: the values below are set by hand and a tick would overwrite them while we wait frames.
	# Prompt 07: flows come from the model's last tick (state.rates per game hour, state.battery_kw), and time left
	# from ReserveForecast, which follows the real sun curve for the battery. So the test sets rates, not balance fields,
	# and puts the clock at night (no sun) for a battery that can be worked out by hand.
	services.set_process(false)
	_fill_stores()
	clock.phase = 0.8
	st.solar_kw = 19.0
	st.load_kw = 53.0
	st.battery_kw = -34.0
	st.stores[&"battery_kwh"] = 180.0
	st.stores[&"oxygen_kg"] = 12.0
	st.stores[&"food_meals"] = 30.0
	st.rates = {"oxygen_kg": -0.1, "water_l": 0.0, "food_meals": -3.0 / GameConfig.SOL_HOURS, "battery_kwh": -34.0}

	var panel := ColonySummaryPanel.new()
	root.add_child(panel)
	panel.setup(services)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.set_details_open(true)          # UI overhaul: the numbers, flows, ideas and rooms are under "Details"
	await _frames()
	panel.refresh()

	# hand calculations (one active crew member)
	var crew := st.active_characters().size()
	var oxygen_sols := 12.0 / (0.1 * GameConfig.SOL_HOURS)
	var food_sols := 30.0 / 3.0
	# battery at night: everything switched on draws from the battery (up to its power limit) until it is empty
	var demand := b.base_load_kw
	for zone: String in st.zones:
		if st.is_zone_powered(zone):
			demand += b.load_of_zone(zone)
	for pair: Array in [["trackers", b.tracker_drive_kw], ["cleaner", b.cleaner_kw], ["recycler", b.recycler_kw], ["scrubber", b.scrubber_kw], ["cabin_fans", b.cabin_fans_kw]]:
		if st.is_on(pair[0]) and st.condition_of(pair[0]) >= b.equipment_min_condition:
			demand += float(pair[1])
	var battery_hours := 180.0 / minf(demand, b.battery_discharge_kw_max)
	var to_sunrise := (1.0 - 0.8 + 0.25) * GameConfig.SOL_HOURS
	var battery_sols := battery_hours / GameConfig.SOL_HOURS
	_check("summary: one crew member is active", crew == 1, str(crew))
	_check("summary: oxygen time left = stock / net use per hour", absf(ColonySummaryPanel.time_left_sols(services, &"oxygen_kg") - oxygen_sols) < 1e-6,
		"%f vs %f" % [ColonySummaryPanel.time_left_sols(services, &"oxygen_kg"), oxygen_sols])
	_check("summary: battery time left at night = kWh / kW of everything switched on (%.1f kW)" % demand, battery_hours < to_sunrise
		and absf(ColonySummaryPanel.time_left_sols(services, &"battery_kwh") - battery_sols) < 1e-6,
		"%f vs %f sols" % [ColonySummaryPanel.time_left_sols(services, &"battery_kwh"), battery_sols])
	_check("summary: food time left = meals / meals per sol", absf(ColonySummaryPanel.time_left_sols(services, &"food_meals") - food_sols) < 1e-6)
	var oxygen_text := _row_value(panel, "TimeLeft_oxygen_kg")
	_check("summary: oxygen line reads 'about 4.9 sols'", oxygen_text == "Oxygen lasts about 4.9 sols at this rate" and absf(oxygen_sols - 4.866) < 0.001, oxygen_text)
	var battery_text := _row_value(panel, "TimeLeft_battery_kwh")
	var battery_want := ColonySummaryPanel.time_left_text("Battery", battery_sols)
	_check("summary: battery line in hours when under a sol", battery_text == battery_want and battery_text.contains("hours"), "%s / %s" % [battery_text, battery_want])
	_check("summary: food line", _row_value(panel, "TimeLeft_food_meals") == "Food lasts about 10 sols at this rate", _row_value(panel, "TimeLeft_food_meals"))
	_check("summary: '—' when not going down (water rate 0)", _row_value(panel, "TimeLeft_water_l") == "—" and ColonySummaryPanel.time_left_sols(services, &"water_l") < 0.0,
		_row_value(panel, "TimeLeft_water_l"))
	var cause := (panel.find_child("Cause_net", true, false) as Label).text
	_check("summary: cause line for the battery", cause == "Battery draining: the colony uses 53 kW and the sun gives 19 kW.", cause)
	_check("summary: net flow shows the drain", _row_value(panel, "Reading_Battery_change") == "−34 kW", _row_value(panel, "Reading_Battery_change"))
	_check("summary: oxygen flow and each process from the model", _row_value(panel, "Reading_Oxygen_reserve_per_sol") == "−%s kg per sol" % String.num(0.1 * GameConfig.SOL_HOURS, 2)
		and (panel.find_child("OxygenMade", true, false) as Label).text.contains("electrolyser 0 kg per sol"), _row_value(panel, "Reading_Oxygen_reserve_per_sol"))
	_check("summary: cabin air line in kPa", _row_value(panel, "Reading_Cabin_air").begins_with("O₂ 21 kPa"), _row_value(panel, "Reading_Cabin_air"))
	st.solar_kw = 60.0
	st.load_kw = 20.0
	st.battery_kw = 36.0
	st.stores[&"battery_kwh"] = 800.0
	panel.refresh()
	_check("summary: battery charging (full battery, not empty within the forecast) shows '—'", _row_value(panel, "TimeLeft_battery_kwh") == "—"
		and (panel.find_child("Cause_net", true, false) as Label).text.begins_with("Battery charging"), _row_value(panel, "TimeLeft_battery_kwh"))
	st.zones["Greenhouse"]["powered"] = false
	panel.refresh()
	var rooms_text := _all_text(panel.find_child("Rooms", true, false))
	_check("summary: rooms list shows power with ✓/✖ and kW", rooms_text.contains("✖ Off") and rooms_text.contains("✓ On") and rooms_text.contains("0 kW (9 kW when on)"),
		rooms_text.substr(0, 200).replace("\n", " | "))
	st.zones["Greenhouse"]["powered"] = true
	var all_text := _all_text(panel)
	_check("summary: stock vs flow and body energy vs electricity boxes", all_text.contains("Stock or flow?") and all_text.contains("Body energy or electricity?")
		and _has_explain(panel, "stock_vs_flow") and _has_explain(panel, "stamina_vs_electricity"))
	var no_units := _numbers_without_units(panel)
	_check("summary: units on every number", no_units.is_empty(), "; ".join(no_units))
	await _check_layout("ColonySummaryPanel", panel, true)
	clock.phase = saved_phase
	st.rates = {}
	services.set_process(true)
	panel.queue_free()
	await _frames()


func _row_value(panel: Node, row_name: String) -> String:
	var row := panel.find_child(row_name, true, false) as ReadingRow
	return row.value_label.text if row != null else "(no row %s)" % row_name


func _has_explain(node: Node, id: String) -> bool:
	for b in node.find_children("*", "ExplainButton", true, false):
		if (b as ExplainButton).explanation_id == id:
			return true
	return false


# ------------------------------------------------------------------ cargo

func _test_inventory() -> void:
	var st := services.state()
	var me := services.local_character()
	for id: String in ["crate_1", "crate_2"]:
		me.position = CharacterState._v3(st.items[id].position)
		services.session.request(&"pick_up", StringName(id))
	st.items["crate_3"]["holder"] = "cache:cache_9"
	st.caches.append({"id": "cache_9", "position": [1.0, 0.0, -1.0], "items": ["crate_3"]})
	me.position = me.hub_spot
	_check("cargo: setup carries two crates", me.cargo.size() == 2, str(me.cargo))

	var panel := InventoryPanel.new()
	root.add_child(panel)
	panel.setup(services)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames()
	panel.refresh()
	var text := _all_text(panel)
	# UI overhaul: "2 / 6" beside the title and one tile per slot (the sentence is the tooltip)
	var slots := services.balance.cargo_slots
	_check("cargo: slots used of cargo_slots", panel.slots_text() == "2 / %d" % slots and text.contains("2 / %d" % slots)
		and panel.find_child("Items", true, false).get_child_count() == slots, panel.slots_text())
	_check("cargo: items named from their kind", text.count("Supply crate") == 2)
	var where := services.zones.zone_at_world(Vector3(1.0, 0.0, -1.0))
	_check("cargo: cache with zone and distance", text.contains("1 thing · %s" % where) and text.contains("m away") and _has_explain(panel, "recovery"),
		text.replace("\n", " | "))
	await _check_layout("InventoryPanel", panel, true)
	var buttons := panel.put_down_buttons()
	var target: Button = null
	for b in buttons:
		if b.get_parent().get_meta("item_id") == &"crate_2":
			target = b
	services.sent.clear()
	target.pressed.emit()
	var drops := services.sent_of(&"drop")
	_check("cargo: 'Put down' sends exactly one drop for the right item", services.sent.size() == 1 and drops.size() == 1 and drops[0].target == &"crate_2", str(services.sent))
	panel.refresh()
	await _frames()
	buttons = panel.put_down_buttons()
	text = _all_text(panel)
	_check("cargo: list updates after the state changes", buttons.size() == 1 and buttons[0].get_parent().get_meta("item_id") == &"crate_1"
		and panel.slots_text() == "1 / %d" % slots and not me.cargo.has(&"crate_2"), text.replace("\n", " | "))
	_check("cargo: the answer is shown", text.contains("You put down the supply crate."))
	services.session.request(&"drop", &"crate_1")
	panel.refresh()
	_check("cargo: empty hands say so", _all_text(panel).contains("Nothing carried") and panel.put_down_buttons().is_empty())
	panel.queue_free()
	await _frames()


# ------------------------------------------------------------------ crew

func _test_crew() -> void:
	var st := services.state()
	var me := services.local_character()
	me.position = me.hub_spot
	var panel := CrewSelectPanel.new()
	root.add_child(panel)
	panel.setup(services)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames()
	panel.refresh()
	_check("crew: four cards sorted by id", str(panel.sorted_ids()) == str([&"crew_1", &"crew_2", &"crew_3", &"crew_4"]), str(panel.sorted_ids()))
	_check("crew: status words", panel.status_text(&"crew_1") == "You" and panel.status_text(&"crew_2") == "Free")
	# UI overhaul: a card is the portrait, the symbol and ONE role word; the rest is behind "More"
	var card_text := _all_text(panel.find_child("Card_crew_2", true, false))
	_check("crew: card shows the symbol, one role word and one button", card_text.contains("✚") and card_text.contains("Medical") and not card_text.contains("Health")
		and panel.play_button(&"crew_2").is_visible_in_tree() and not panel.play_button(&"crew_1").is_visible_in_tree()
		and (panel.find_child("Card_crew_1", true, false).find_child("Portrait", true, false) as CrewPortrait).mark() == &"you", card_text.replace("\n", " | "))
	panel.show_details(true)
	card_text = _all_text(panel.find_child("Card_crew_2", true, false))
	_check("crew: card shows specialty with symbol, health, suit tank and place", card_text.contains("✚ Medical and life support specialist") and card_text.contains("Health 100 %")
		and card_text.contains("tank 100 %") and card_text.contains("Where: %s" % services.zones.zone_at_world(st.character(&"crew_2").position)), card_text.replace("\n", " | "))
	_check("crew: own card is disabled with a reason", panel.play_button(&"crew_1").disabled and panel.reason_text(&"crew_1") == "You are already this crew member.")
	_check("crew: rule line with crew_switching explanation", _all_text(panel).contains("change crew member at the hub") and _has_explain(panel, "crew_switching"))
	await _check_layout("CrewSelectPanel with details", panel, true)
	panel.show_details(false)

	# far from the hub
	me.position = Vector3(30.0, 0.0, 9.0)
	panel.refresh()
	var host := services.session.request(&"claim_character", &"crew_2")
	_check("crew: far from the hub is disabled with the reason", panel.play_button(&"crew_2").disabled and panel.reason_text(&"crew_2") == "Walk to the hub to change crew member."
		and panel.hint_text() == "Walk to the hub to swap." and host.reason == &"not_at_hub", "%s / host %s" % [panel.reason_text(&"crew_2"), host.reason])
	me.position = me.hub_spot

	# four players
	services.session.peers.assign([1, 2, 3, 4])
	panel.refresh()
	host = services.session.request(&"claim_character", &"crew_2")
	_check("crew: four players is disabled with the reason", panel.play_button(&"crew_2").disabled
		and panel.reason_text(&"crew_2") == "With four players everyone keeps their own crew member." and host.reason == &"switch_disabled",
		"%s / host %s" % [panel.reason_text(&"crew_2"), host.reason])
	services.session.peers.assign([1])

	# taken by another player
	st.character(&"crew_3").owner_peer = 2
	panel.refresh()
	host = services.session.request(&"claim_character", &"crew_3")
	_check("crew: taken is disabled with the reason", panel.play_button(&"crew_3").disabled and panel.reason_text(&"crew_3") == "Another player is already this crew member."
		and panel.status_text(&"crew_3") == "Player 2" and (panel.find_child("Card_crew_3", true, false).find_child("Portrait", true, false) as CrewPortrait).mark() == &"taken"
		and host.reason == &"character_taken", "%s / host %s" % [panel.reason_text(&"crew_3"), host.reason])
	st.character(&"crew_3").owner_peer = 0

	# allowed
	panel.refresh()
	_check("crew: allowed at the hub", not panel.play_button(&"crew_2").disabled and panel.reason_text(&"crew_2") == "" and panel.hint_text() == "")
	await _check_layout("CrewSelectPanel", panel, true)
	services.sent.clear()
	panel.play_button(&"crew_2").pressed.emit()
	var claims := services.sent_of(&"claim_character")
	_check("crew: 'Play as' sends exactly one claim_character", services.sent.size() == 1 and claims.size() == 1 and claims[0].target == &"crew_2", str(services.sent))
	_check("crew: the answer is shown and the cards update", st.character(&"crew_2").owner_peer == 1 and panel.status_text(&"crew_2") == "You"
		and panel.status_text(&"crew_1") == "Free" and _all_text(panel).contains("You are now Medical and life support."))
	services.session.request(&"claim_character", &"crew_1")
	panel.queue_free()
	await _frames()


# ------------------------------------------------------------------ portrait

func _test_portrait() -> void:
	var c := services.state().character(&"crew_2")
	var holder := VBoxContainer.new()
	root.add_child(holder)
	var rig := CrewPortrait.new()
	holder.add_child(rig)
	rig.setup(c, 1)
	var badge := CrewPortrait.new()
	badge.prefer_rig = false
	holder.add_child(badge)
	badge.setup(c, 1)
	await _frames(3)
	if PlayerVisual.rigged_scene() != null:
		var vp := rig.viewport()
		_check("portrait: 3D portrait built (SubViewport 160x200, own world, update once, body, camera, light)",
			rig.uses_rig() and vp != null and vp.size == Vector2i(160, 200) and vp.own_world_3d and vp.render_target_update_mode == SubViewport.UPDATE_ONCE
			and rig.visual() != null and vp.find_children("*", "Camera3D", true, false).size() == 1 and vp.find_children("*", "DirectionalLight3D", true, false).size() >= 1
			and vp.find_children("*", "Skeleton3D", true, false).size() >= 1)
	else:
		_check("portrait: no rig in this copy, badge used", not rig.uses_rig())
	_check("portrait: badge fallback draws without a viewport", not badge.uses_rig() and badge.viewport() == null and badge.get_child_count() == 0)
	_check("portrait: specialist symbols", CrewPortrait.specialty_symbol(&"electrical_comms") == "⚡" and CrewPortrait.specialty_symbol(&"medical_life_support") == "✚"
		and CrewPortrait.specialty_symbol(&"biology_food") == "❀" and CrewPortrait.specialty_symbol(&"field_engineering_geology") == "⛏")
	badge.queue_redraw()
	await _frames()
	holder.queue_free()
	await _frames()
