extends StationPanel
## The scout drone's pad outside (upgrade paths plan §6.2). No class_name (loaded by StationPanels by path).
## Shows the drone's level and ability, its battery and charging time, the flights left today, the command room's
## radio range and how far one battery reaches, and the last mineral report.
##   * Take control (any level): E again on this panel, or the button. Only with a full battery and a flight left
##     today. The player flies it (DronePresenter): R flies it home, E hands it back.
##   * V2 revisit: pick an explored spot (DroneSystem.revisit_places) and it flies there, scans it and comes back.
##   * V3 find: pick an ore; it flies to the nearest KNOWN deposit with units left and confirms it is still there.
##   * V4 scan: pick an ore; it flies a search pattern to the nearest UNREVEALED deposit and reveals it.
##   Locked controls are shown with a plain note saying which upgrade gives them.
## The upgrade strip for the scout_drone track is added by the base StationPanel (UI worker).

const DroneSystem := preload("res://scripts/drone/drone_system.gd")
const ABILITY_NAMES := {"manual": "fly it yourself", "prescout": "pre-scouts ore, revisits spots",
	"find_known": "finds known ore", "scan_anywhere": "scans anywhere for ore"}

var fly_button: Button
var hand_back_button: Button
var recall_button: Button
var revisit_button: Button
var find_button: Button
var scan_button: Button
## Pickers: explored spots (metadata = place id) and ores (metadata = ore id).
var spot_pick: OptionButton
var find_pick: OptionButton
var scan_pick: OptionButton

var _status: Label
var _launch_note: Label
var _revisit_note: Label
var _find_note: Label
var _scan_note: Label
var _report: Label
var _sig := ""
var _opened_frame := -1


func _shows_later_note() -> bool:
	return false


func _shows_room_power() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["Fly the scout drone yourself: press E here (or Take control). W A S D fly the way it faces, the mouse turns, Space climbs, Ctrl or Shift goes down, Tab switches the camera, R flies it home, E hands it back.",
		"It takes off only with a full battery, and only so many times per sol. After every flight it charges here on the pad.",
		"It always keeps enough battery to come home: when the battery holds only the trip back, it turns home by itself.",
		"V2 spots ore while it flies and can fly back to explored spots by itself; V3 finds an ore you already know; V4 scans anywhere for the ore you ask for."])


func first_focus() -> Control:
	if fly_button != null and fly_button.visible and not fly_button.disabled:
		return fly_button
	return super.first_focus()


func _enter_tree() -> void:
	_opened_frame = Engine.get_process_frames()


func _build_body() -> void:
	_add_reading(&"level", "✈", "Drone level", "upgrades")
	# Merged 2026-11-15: the drone helper's controls (flights per sol, V2-V4 abilities) in the UI overhaul's style
	# (action buttons with pictures, notes, readings with a bar).
	_add_reading(&"battery", "▮", "Battery", "battery")
	_add_reading(&"flights", "◷", "Flights left today", "upgrades")
	_add_reading(&"range", "◎", "Reach on one battery (radio range)", "upgrades")
	_status = _add_text(_body, "", UiTheme.HEADING)
	_status.name = "DroneStatus"
	_launch_note = _add_note(_body, "")
	fly_button = _add_action("Take control (E)", &"drone", take_control)
	fly_button.name = "TakeControl"
	hand_back_button = _add_action("Hand it back", &"back", func() -> void: _ask_free(&"drone_land"), false)
	hand_back_button.name = "HandBack"
	recall_button = _add_action("Call it home", &"home", func() -> void: _ask(&"drone_recall", {}, _on_answer), false)
	recall_button.name = "Recall"

	_add_heading(_body, "Revisit an explored spot (V2)")
	_revisit_note = _add_note(_body, "")
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override(&"separation", 10)
	_body.add_child(r1)
	spot_pick = _picker(r1, "SpotPick")
	revisit_button = _button(r1, "Revisit", "Fly there", func() -> void: send(&"revisit", _picked(spot_pick)))

	_add_heading(_body, "Find a known ore (V3)")
	_find_note = _add_note(_body, "")
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override(&"separation", 10)
	_body.add_child(r2)
	find_pick = _picker(r2, "FindPick")
	find_button = _button(r2, "Find", "Find it", func() -> void: send(&"find", _picked(find_pick)))

	_add_heading(_body, "Scan anywhere for an ore (V4)")
	_scan_note = _add_note(_body, "")
	var r3 := HBoxContainer.new()
	r3.add_theme_constant_override(&"separation", 10)
	_body.add_child(r3)
	scan_pick = _picker(r3, "ScanPick")
	scan_button = _button(r3, "Scan", "Scan for it", func() -> void: send(&"scan", _picked(scan_pick)))

	_add_heading(_body, "Last mineral report")
	_report = _add_text(_body, "", UiTheme.MUTED)


func _button(parent: Control, n: String, label: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.name = n
	b.text = label
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _picker(parent: Control, n: String) -> OptionButton:
	var o := OptionButton.new()
	o.name = n
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.fit_to_longest_item = false
	parent.add_child(o)
	return o


func _picked(o: OptionButton) -> String:
	if o == null or o.selected < 0 or o.item_count == 0:
		return ""
	return String(o.get_item_metadata(o.selected))


func _refresh_body(st: ColonyState) -> void:
	DroneSystem.ensure(st)
	var lvl := DroneSystem.level(st)
	var d := st.drone
	var ab := DroneSystem.ability(st)
	_show_reading(&"level", "V%d · %s" % [lvl, String(ABILITY_NAMES.get(ab, ab))], &"ok")
	var b := DroneSystem.battery(st)
	var docked := DroneSystem.status(st) == "docked"
	var charge := ""
	if docked and b < 0.999:
		charge = " · charging, %s to full" % _time_words(DroneSystem.seconds_to_full(st))
	_show_reading(&"battery", "%d %% · %d s of flight%s" % [floori(b * 100.0), roundi(DroneSystem.seconds_left(st)), charge],
		&"ok" if b >= 0.999 else (&"warn" if b >= 0.5 else &"urgent"), b)
	var left := DroneSystem.flights_left_today(st)
	_show_reading(&"flights", "%d of %d" % [left, DroneSystem.flights_per_sol(st)], &"ok" if left > 0 else &"warn")
	_show_reading(&"range", "about %d m out and back · radio %d m" % [roundi(DroneSystem.reach_m(st)), roundi(DroneSystem.range_m(st))], &"ok")
	_status.text = "● " + DroneSystem.status_text(st)
	var why := DroneSystem.launch_refusal(st)
	var me := services.local_character()
	fly_button.disabled = why != ""
	fly_button.tooltip_text = "Fly the drone yourself." if why == "" else why
	_launch_note.text = why if docked and why != "" else ""
	_launch_note.visible = _launch_note.text != ""
	hand_back_button.visible = me != null and DroneSystem.watcher(st) == String(me.id)
	recall_button.visible = DroneSystem.status(st) == "auto"
	var sig := "%d|%s|%s|%s" % [lvl, DroneSystem.status(st), JSON.stringify(d.get("spots", [])), JSON.stringify(d.get("surveyed", {}))]
	if sig != _sig:
		_sig = sig
		_build_pickers(st)
	var can_launch := why == ""
	# V2 revisit
	var has_revisit := DroneSystem.has_ability(st, "prescout")
	spot_pick.disabled = not has_revisit or spot_pick.item_count == 0
	revisit_button.disabled = not has_revisit or not can_launch or _picked(spot_pick) == ""
	if not has_revisit:
		_revisit_note.text = "Needs the V2 upgrade (multispectral camera): the drone then spots ore while it flies, radios a mineral report, and can fly back to an explored spot by itself."
	elif spot_pick.item_count == 0:
		_revisit_note.text = "No explored spots yet: fly the drone yourself first. The farthest point of each flight and every place it finds ore are remembered here."
	else:
		_revisit_note.text = "Pick a spot. The drone flies there by itself, scans it again and comes back."
	# V3 find
	var has_find := DroneSystem.has_ability(st, "find_known")
	find_pick.disabled = not has_find
	find_button.disabled = not has_find or not can_launch or _picked(find_pick) == ""
	_find_note.text = "Pick an ore. The drone flies to the nearest place where the colony already found it (with some left to mine) and checks it is still there." if has_find \
		else "Needs the V3 upgrade (neutron and gamma spectrometer): the drone then finds an ore you already know about."
	# V4 scan
	var has_scan := DroneSystem.has_ability(st, "scan_anywhere")
	scan_pick.disabled = not has_scan
	scan_button.disabled = not has_scan or not can_launch or _picked(scan_pick) == ""
	_scan_note.text = "Pick an ore. The drone flies a search pattern with its ground radar toward the nearest place nobody has mapped yet, and marks it on the map." if has_scan \
		else "Needs the V4 upgrade (ground radar): the drone then scans anywhere in reach for the ore you ask for."
	var rep: Dictionary = d.get("last_report", {})
	_report.text = "No reports yet." if rep.is_empty() else "%s (sol %d): %s" % [String(rep.get("name", "")), int(rep.get("sol", 1)), String(rep.get("text", ""))]


func _build_pickers(st: ColonyState) -> void:
	var keep_spot := _picked(spot_pick)
	var keep_find := _picked(find_pick)
	var keep_scan := _picked(scan_pick)
	spot_pick.clear()
	for p: Dictionary in DroneSystem.revisit_places(st):
		spot_pick.add_item("%s · %d m" % [String(p.name), roundi(float(p.far_m))])
		spot_pick.set_item_metadata(spot_pick.item_count - 1, String(p.id))
	for o: OptionButton in [find_pick, scan_pick]:
		o.clear()
		for ore_id: String in DroneSystem.ore_ids():
			o.add_item(DroneSystem.ore_name(ore_id))
			o.set_item_metadata(o.item_count - 1, ore_id)
	_select(spot_pick, keep_spot)
	_select(find_pick, keep_find)
	_select(scan_pick, keep_scan)


func _select(o: OptionButton, value: String) -> void:
	for i in o.item_count:
		if String(o.get_item_metadata(i)) == value:
			o.select(i)
			return
	if o.item_count > 0:
		o.select(0)


func _time_words(seconds: float) -> String:
	var s := ceili(seconds)
	if s < 60:
		return "%d s" % s
	return "%d min %02d s" % [floori(s / 60.0), s % 60]


## Sends the drone by itself (drone_send): mode "revisit" (target = place id), "find" or "scan" (target = ore id).
func send(mode: StringName, target: String) -> ActionResult:
	return _ask(&"drone_send", {"mode": String(mode), "target": target}, _on_answer)


## Takes the controls (drone_fly). On success the panel closes so the flight can start.
func take_control() -> ActionResult:
	return _ask(&"drone_fly", {}, _on_fly_answer)


## A request without a station target (drone_land).
func _ask_free(action: StringName) -> void:
	var r := services.request(action)
	if r.pending:
		_show_message("One moment…", UiTheme.MUTED)
	elif r.ok:
		_on_answer(r)
	else:
		_show_refusal(r)


func _on_fly_answer(result: ActionResult) -> void:
	_on_answer(result)
	if result.ok:
		close_requested.emit()


func _on_answer(result: ActionResult) -> void:
	if result.ok:
		_show_message("")
		_show_cause(answer_text(result))
	else:
		_show_refusal(result)
	_sig = ""
	refresh()


## E on this panel takes the controls when the drone is ready (the press that opened the panel does not count).
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed(&"interact") or Engine.get_process_frames() <= _opened_frame:
		return
	if fly_button == null or fly_button.disabled or not services.has_game():
		return
	get_viewport().set_input_as_handled()
	take_control()
