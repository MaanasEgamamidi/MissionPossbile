class_name GameHud
extends CanvasLayer
## Minimal working HUD: time, stores, what you are looking at, messages, suit check progress, pause.
## It reads state for display and listens to events; it never changes anything. The designed HUD is a later milestone.

var services: GameServices

var _status: Label
var _prompt: Label
var _message: Label
var _banner: Label
var _progress: ProgressBar
var _crosshair: Label
var _message_left := 0.0
var _refresh_left := 0.0
var _target := {}
var _menu: PanelContainer
var _menu_station: StringName = &""


func setup(p_services: GameServices) -> void:
	services = p_services
	layer = 10
	_status = _label(Vector2(16, 12), 18, HORIZONTAL_ALIGNMENT_LEFT)
	_status.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_prompt = _label(Vector2.ZERO, 22, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -150
	_prompt.offset_left = -500
	_prompt.offset_right = 500
	_message = _label(Vector2.ZERO, 22, HORIZONTAL_ALIGNMENT_CENTER)
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_message.offset_top = -230
	_message.offset_left = -700
	_message.offset_right = 700
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner = _label(Vector2.ZERO, 40, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.offset_left = -500
	_banner.offset_right = 500
	_banner.offset_top = -160
	_crosshair = _label(Vector2.ZERO, 20, HORIZONTAL_ALIGNMENT_CENTER)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.offset_left = -10
	_crosshair.offset_right = 10
	_crosshair.offset_top = -14
	_crosshair.text = "+"
	_progress = ProgressBar.new()
	_progress.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_progress.offset_left = -160
	_progress.offset_right = 160
	_progress.offset_top = -110
	_progress.offset_bottom = -90
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.visible = false
	add_child(_progress)
	services.events.pause_changed.connect(func(_paused: bool) -> void: _refresh())
	services.events.action_resolved.connect(_on_action_resolved)
	_refresh()


func _label(pos: Vector2, size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.position = pos
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## What the player is looking at, as returned by PlayerController.aimed_target().
func set_target(target: Dictionary) -> void:
	_target = target
	var kind := String(target.get("kind", ""))
	if kind == "station":
		var rec: Dictionary = services.state().stations.get(String(target.get("id", "")), {})
		_prompt.text = "[%s]  %s" % [PlayerInput.describe(&"interact"), _station_name(String(rec.get("kind", "")))]
	elif kind == "item":
		_prompt.text = "[%s]  Pick up" % PlayerInput.describe(&"interact")
	else:
		_prompt.text = ""


func is_menu_open() -> bool:
	return _menu != null


func close_menu() -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null


## The power panel: one switch per lighting zone. Each switch sends its own `set_zone_power` request to the host.
func open_power_panel(station_id: StringName) -> void:
	close_menu()
	_menu_station = station_id
	_menu = PanelContainer.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_menu.offset_left = -380
	_menu.offset_right = 380
	_menu.offset_top = -300
	_menu.offset_bottom = 300
	add_child(_menu)
	var box := VBoxContainer.new()
	_menu.add_child(box)
	var title := Label.new()
	title.text = "POWER PANEL    switch rooms off to save the battery    [%s] close" % PlayerInput.describe(&"back")
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	var st := services.state()
	var names := st.zones.keys()
	names.sort()
	for zone: String in names:
		var button := CheckButton.new()
		button.text = "%s   %.1f kW" % [zone, services.balance.load_of_zone(zone)]
		button.button_pressed = st.is_zone_powered(zone)
		button.add_theme_font_size_override("font_size", 18)
		button.toggled.connect(_on_zone_toggled.bind(zone, button))
		grid.add_child(button)


func _on_zone_toggled(on: bool, zone: String, button: CheckButton) -> void:
	var result := services.session.request(&"set_zone_power", _menu_station, {"zone": zone, "on": on})
	if not result.ok:
		button.set_pressed_no_signal(not on)


func show_message(text: String, seconds := 3.0) -> void:
	_message.text = text
	_message_left = seconds


func _station_name(kind: String) -> String:
	match kind:
		"suits": return "Suit rack: suit check"
		"power": return "Power panel"
		"computer": return "Colony computer"
		"comms": return "Comms console"
		"food": return "Greenhouse console"
		"board": return "Transceiver board"
		"lifesupport": return "Life support console"
		"heal": return "Med station"
		"survivor": return "Patient"
	return "Station"


func _on_action_resolved(result: ActionResult) -> void:
	if not result.ok and not result.duplicate and result.reason != &"paused":
		show_message(result.message, 3.0)


func _process(delta: float) -> void:
	if services == null or not services.has_game():
		return
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			_message.text = ""
	var mine := services.state().character_of_peer(SessionService.HOST_PEER)
	var p := services.session.suit_check_progress(mine.id) if mine != null else -1.0
	_progress.visible = p >= 0.0
	if p >= 0.0:
		_progress.value = p
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.25
		_refresh()


func _refresh() -> void:
	if services == null or not services.has_game():
		return
	var st := services.state()
	var c := services.clock()
	var hour := c.hour_of_sol()
	var mine := st.character_of_peer(SessionService.HOST_PEER)
	var lines := PackedStringArray()
	lines.append("Sol %d   %02d:%02d   (one sol = %s real minutes)" % [c.sol_index + 1, int(hour), int(fmod(hour, 1.0) * 60.0), String.num(c.sol_minutes, 1)])
	lines.append("Battery %.0f / %.0f kWh   sun %.1f kW   load %.1f kW%s" % [st.store(&"battery_kwh"), float(st.capacities[&"battery_kwh"]), st.solar_kw, st.load_kw,
		"   POWER SHORT" if st.power_deficit else ""])
	lines.append("Oxygen %.1f kg   Water %.0f L   Food %.0f meals   Parts %d" % [st.store(&"oxygen_kg"), st.store(&"water_l"), st.store(&"food_meals"), st.parts])
	if mine != null:
		lines.append("%s   health %.0f   stamina %.0f   suit %s (tank %.0f %%)   carrying %d / %d" % [mine.display_name, mine.health, mine.stamina,
			"ON" if mine.suit_on else "off", mine.suit_charge, mine.cargo.size(), services.balance.cargo_slots])
	_status.text = "\n".join(lines)
	_banner.text = "PAUSED\n[%s] to continue" % PlayerInput.describe(&"back") if services.session.paused else ""
