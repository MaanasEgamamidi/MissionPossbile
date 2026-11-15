extends StationPanel
## The scout drone's pad outside (2026-11-14 upgrade paths). No class_name (loaded by StationPanels by path).
## Shows the drone's level and what it can do, its battery, the command room's radio range and the places it surveyed.
##   * Take control (any level): E again on this panel, or the button. The drone lifts off and the player flies it
##     (DronePresenter); E while flying hands it back and it flies home by itself.
##   * Autopilot (V3+): tick places and press Send. V3 flies to one place, V4 to a route of up to max_waypoints places.
##     Below V3 the list is shown greyed out with a plain note saying what the upgrade gives.
## The upgrade strip for the scout_drone track is added by the base StationPanel (UI worker).

const DroneSystem := preload("res://scripts/drone/drone_system.gd")

## Site check boxes by site id, and the buttons (tests).
var site_checks: Dictionary = {}
var fly_button: Button
var hand_back_button: Button
var send_button: Button
var recall_button: Button

var _status: Label
var _route_label: Label
var _autopilot_note: Label
var _sites: VBoxContainer
var _report: Label
var _sig := ""
var _opened_frame := -1
var _picked: Array = []


func _shows_later_note() -> bool:
	return false


func _shows_room_power() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["Fly the scout drone yourself: press E here (or Take control). W A S D fly, the mouse turns, Space climbs, Shift or Ctrl goes down, E hands it back.",
		"Fly it near a place the scout could visit: its camera surveys the place and marks the ore there on the map.",
		"Stay inside the command room's radio range. Upgrade the command room to fly further.",
		"From V3 the drone has an autopilot: pick places here and it flies there, films them and comes back by itself."])


func first_focus() -> Control:
	if fly_button != null and fly_button.visible and not fly_button.disabled:
		return fly_button
	return super.first_focus()


func _enter_tree() -> void:
	_opened_frame = Engine.get_process_frames()


func _build_body() -> void:
	_add_reading(&"level", "✈", "Drone level", "upgrades")
	_add_reading(&"battery", "⚡", "Battery", "battery")
	_add_reading(&"range", "◎", "Radio range (command room)", "upgrades")
	_add_reading(&"surveyed", "◉", "Places surveyed by the drone", "sources")
	_status = _add_text(_body, "", UiTheme.HEADING)
	_status.name = "DroneStatus"
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	_body.add_child(row)
	fly_button = Button.new()
	fly_button.name = "TakeControl"
	fly_button.text = "✈ Take control (E)"
	fly_button.theme_type_variation = UiTheme.PRIMARY_BUTTON
	fly_button.pressed.connect(take_control)
	row.add_child(fly_button)
	hand_back_button = Button.new()
	hand_back_button.name = "HandBack"
	hand_back_button.text = "Hand it back"
	hand_back_button.pressed.connect(func() -> void: _ask_free(&"drone_land"))
	row.add_child(hand_back_button)
	recall_button = Button.new()
	recall_button.name = "Recall"
	recall_button.text = "Call it home"
	recall_button.pressed.connect(func() -> void: _ask(&"drone_recall", {}, _on_answer))
	row.add_child(recall_button)
	_add_heading(_body, "Autopilot")
	_autopilot_note = _add_text(_body, "", UiTheme.MUTED)
	_sites = VBoxContainer.new()
	_sites.name = "Sites"
	_body.add_child(_sites)
	var send_row := HBoxContainer.new()
	send_row.add_theme_constant_override(&"separation", 10)
	_body.add_child(send_row)
	send_button = Button.new()
	send_button.name = "Send"
	send_button.text = "Send on this route"
	send_button.pressed.connect(send_route)
	send_row.add_child(send_button)
	_route_label = _add_text(send_row, "", UiTheme.MUTED)
	_route_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_heading(_body, "Last drone report")
	_report = _add_text(_body, "", UiTheme.MUTED)


func _refresh_body(st: ColonyState) -> void:
	var lvl := DroneSystem.level(st)
	var d := st.drone
	_show_reading(&"level", "V%d" % lvl, &"ok")
	var b := DroneSystem.battery(st)
	_show_reading(&"battery", "%d %% · %d s of flight" % [roundi(b * 100.0), roundi(DroneSystem.seconds_left(st))],
		&"urgent" if b < DroneSystem.num("launch_min_battery", 0.2) else (&"warn" if b < 0.5 else &"ok"))
	_show_reading(&"range", "%d m" % roundi(DroneSystem.range_m(st)), &"ok")
	_show_reading(&"surveyed", "%d of %d" % [(d.get("surveyed", {}) as Dictionary).size(), ScoutSystem.sites().size()], &"ok")
	_status.text = "● " + DroneSystem.status_text(st)
	var me := services.local_character()
	var docked := DroneSystem.status(st) == "docked"
	fly_button.disabled = not docked or b < DroneSystem.num("launch_min_battery", 0.2)
	fly_button.tooltip_text = "Fly the drone yourself." if not fly_button.disabled else ("Let it charge first." if docked else "The drone is out flying.")
	hand_back_button.visible = me != null and DroneSystem.pilot(st) == String(me.id)
	recall_button.visible = DroneSystem.status(st) == "auto"
	var auto := DroneSystem.has_autopilot(st)
	var most := DroneSystem.max_waypoints(st)
	if not auto:
		_autopilot_note.text = "Needs the V3 upgrade (programmable autopilot). Then pick a place below and the drone flies there, films it and comes back by itself. V4 flies a route of up to %d places." % int(AreaLevels.effect_at(DroneSystem.TRACK, "max_waypoints", 4, 4))
	elif most <= 1:
		_autopilot_note.text = "Pick one place. The drone flies there by itself, films it and comes back. V4 can fly a route of several places."
	else:
		_autopilot_note.text = "Pick up to %d places, in the order to visit them. The drone flies the route by itself and comes back." % most
	var sig := "%d|%s|%s|%s" % [lvl, DroneSystem.status(st), JSON.stringify(d.get("surveyed", {})), DroneSystem.range_m(st)]
	if sig != _sig:
		_sig = sig
		_build_sites(st)
	_update_route(st)
	var rep: Dictionary = d.get("last_report", {})
	_report.text = "No reports yet: fly the drone near one of the places." if rep.is_empty() else "%s (sol %d): %s" % [String(rep.get("name", "")), int(rep.get("sol", 1)), String(rep.get("text", ""))]


func _build_sites(st: ColonyState) -> void:
	for c in _sites.get_children():
		_sites.remove_child(c)
		c.queue_free()
	site_checks.clear()
	var auto := DroneSystem.has_autopilot(st)
	var pad := DroneSystem.pad_position(st)
	var r := DroneSystem.range_m(st)
	for site: Dictionary in ScoutSystem.sites():
		var id := String(site.id)
		var p := ScoutSystem.site_position(id)
		var far := Vector2(p.x - pad.x, p.z - pad.z).length()
		var cb := CheckBox.new()
		cb.name = "Site_%s" % id
		var mark := "✓ " if DroneSystem.is_surveyed(st, id) or ScoutSystem.is_surveyed(st, id) else ""
		cb.text = "%s%s · %d m away%s" % [mark, String(site.name), roundi(far), " (out of radio range)" if far > r else ""]
		cb.disabled = not auto or far > r or DroneSystem.status(st) != "docked"
		cb.button_pressed = _picked.has(id) and not cb.disabled
		cb.toggled.connect(_on_pick.bind(id))
		_sites.add_child(cb)
		site_checks[id] = cb
	var keep: Array = []
	for id: Variant in _picked:
		if site_checks.has(id) and not (site_checks[id] as CheckBox).disabled:
			keep.append(id)
	_picked = keep


func _on_pick(on: bool, id: String) -> void:
	if not services.has_game():
		return
	var st := services.state()
	if on:
		if not _picked.has(id):
			_picked.append(id)
		var most := maxi(1, DroneSystem.max_waypoints(st))
		while _picked.size() > most:
			var drop := String(_picked.pop_front())
			var cb := site_checks.get(drop) as CheckBox
			if cb != null:
				cb.set_pressed_no_signal(false)
	else:
		_picked.erase(id)
	_update_route(st)


## Ticks exactly these places (tests and keyboard users), in this order.
func pick(ids: Array) -> void:
	_picked.clear()
	for id: Variant in ids:
		var cb := site_checks.get(String(id)) as CheckBox
		if cb != null and not cb.disabled:
			cb.set_pressed_no_signal(true)
			_picked.append(String(id))
	_update_route(services.state())


func _update_route(st: ColonyState) -> void:
	var names := PackedStringArray()
	for id: Variant in _picked:
		names.append(String(ScoutSystem.site(String(id)).get("name", id)))
	var auto := DroneSystem.has_autopilot(st)
	send_button.disabled = not auto or _picked.is_empty() or DroneSystem.status(st) != "docked"
	if names.is_empty():
		_route_label.text = "" if auto else "Locked until V3."
	else:
		_route_label.text = "Route: pad → %s → pad · about %d s" % [" → ".join(names), roundi(DroneSystem.route_seconds(st, _picked))]


## Sends the drone on the ticked route (drone_send).
func send_route() -> ActionResult:
	return _ask(&"drone_send", {"route": ",".join(PackedStringArray(_picked))}, _on_answer)


## Takes the controls (drone_fly). On success the panel closes so the flight can start.
func take_control() -> ActionResult:
	return _ask(&"drone_fly", {}, _on_fly_answer)


## A request without a station target (drone_land).
func _ask_free(action: StringName) -> void:
	var r := services.request(action)
	if r.pending:
		_show_message("Asked the host…", UiTheme.MUTED)
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
		if String(result.changes.get("action", "")) == "drone_send":
			_picked.clear()
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
