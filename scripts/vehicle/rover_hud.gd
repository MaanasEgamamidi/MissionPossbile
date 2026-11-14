class_name RoverHud
extends Control
## The rover's HUD widget (Prompt 10), added by RoverPresenter under the GameHud layer (so it hides with the HUD).
##   bottom-right   while seated: speed (m/s and km/h), battery (kWh and %), honest range, cargo (kg of capacity),
##                  who sits where, and the keys (WASD drive, Space brake, E get out, Tab view)
##   centre, below the crosshair   while standing and looking at the rover: what E would do ("[E] Get in: driver's seat")
## The existing HUD keeps top-left (colony), top-right (your crew member), top-centre (messages), bottom-left
## (network status) and bottom-centre (key hints); the bottom-right corner is free, so nothing overlaps.
## It only shows what it is given (show_seated / show_cue); it never changes anything.

const EDGE := 24
const WIDTH := 360.0
const SEAT_NAMES: Array[String] = ["Driver", "Front", "Rear left", "Rear right"]

var _panel: PanelContainer
var _title: Label
var _speed: Label
var _battery: Label
var _battery_bar: ProgressBar
var _range: Label
var _cargo: Label
var _seats: Label
var _keys: Label
var _warning: Label
var _cue_panel: PanelContainer
var _cue: Label


func _init() -> void:
	name = "RoverHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_panel = PanelContainer.new()
	_panel.name = "RoverPanel"
	_panel.theme_type_variation = UiTheme.HUD_PANEL
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_right = -EDGE
	_panel.offset_bottom = -EDGE
	_panel.offset_left = -EDGE - WIDTH
	_panel.offset_top = -EDGE
	_panel.custom_minimum_size.x = WIDTH
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	_panel.add_child(box)
	_title = _label(box, "Title", UiTheme.HEADING)
	_title.text = "Rover"
	_speed = _label(box, "Speed", &"")
	_battery = _label(box, "Battery", &"")
	_battery_bar = ProgressBar.new()
	_battery_bar.name = "BatteryBar"
	_battery_bar.show_percentage = false
	_battery_bar.custom_minimum_size = Vector2(WIDTH - 40.0, 14.0)
	_battery_bar.theme_type_variation = UiTheme.BAR_GOOD
	box.add_child(_battery_bar)
	_range = _label(box, "Range", UiTheme.MUTED)
	_cargo = _label(box, "Cargo", &"")
	_seats = _label(box, "Seats", UiTheme.MUTED)
	_warning = _label(box, "Warning", UiTheme.URGENT)
	_keys = _label(box, "Keys", UiTheme.MUTED)
	_panel.visible = false

	_cue_panel = PanelContainer.new()
	_cue_panel.name = "RoverCue"
	_cue_panel.theme_type_variation = UiTheme.CHIP
	_cue_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cue_panel.anchor_left = 0.5
	_cue_panel.anchor_right = 0.5
	_cue_panel.anchor_top = 0.5
	_cue_panel.anchor_bottom = 0.5
	_cue_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_cue_panel.offset_top = 36.0          # where GameHud's own cue sits (it is empty while the rover is aimed at)
	add_child(_cue_panel)
	_cue = Label.new()
	_cue.name = "Cue"
	_cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cue_panel.add_child(_cue)
	_cue_panel.visible = false


func _label(parent: Control, label_name: String, variation: StringName) -> Label:
	var l := Label.new()
	l.name = label_name
	if variation != &"":
		l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 40.0
	parent.add_child(l)
	return l


## Shows the seated panel with `info`: speed_mps, battery_kwh, capacity_kwh, range_km, cargo_kg, cargo_capacity_kg,
## seats (4 names, "" for free), seat (this player's seat index), driver (bool), battery_empty (bool), keys (text).
func show_seated(info: Dictionary) -> void:
	_panel.visible = true
	var v := absf(float(info.get("speed_mps", 0.0)))
	_speed.text = "Speed  %.1f m/s  (%.0f km/h)" % [v, v * 3.6]
	var kwh := float(info.get("battery_kwh", 0.0))
	var cap := maxf(0.001, float(info.get("capacity_kwh", 1.0)))
	var pct := clampf(kwh / cap * 100.0, 0.0, 100.0)
	_battery.text = "Battery  %.2f kWh  (%.0f %%)" % [kwh, pct]
	_battery_bar.value = pct
	_battery_bar.theme_type_variation = UiTheme.BAR_URGENT if pct < 10.0 else (UiTheme.BAR_WARN if pct < 25.0 else UiTheme.BAR_GOOD)
	_range.text = "Range about %.1f km with this load" % float(info.get("range_km", 0.0))
	_cargo.text = "Cargo  %.0f of %.0f kg" % [float(info.get("cargo_kg", 0.0)), float(info.get("cargo_capacity_kg", 0.0))]
	var names: Array = info.get("seats", ["", "", "", ""])
	var lines := PackedStringArray()
	var mine := int(info.get("seat", -1))
	for i in mini(names.size(), SEAT_NAMES.size()):
		var who := String(names[i]) if String(names[i]) != "" else "free"
		lines.append("%s: %s%s" % [SEAT_NAMES[i], who, "  (you)" if i == mine else ""])
	_seats.text = "\n".join(lines)
	_title.text = "Rover: you are driving" if bool(info.get("driver", false)) else "Rover: you are riding"
	_warning.text = "Battery empty: the rover can only coast and brake." if bool(info.get("battery_empty", false)) else ""
	_warning.visible = _warning.text != ""
	_keys.text = String(info.get("keys", ""))


func hide_seated() -> void:
	_panel.visible = false


## The line under the crosshair while the rover is aimed at ("" hides it).
func show_cue(text: String) -> void:
	_cue.text = text
	_cue_panel.visible = text != ""


func seated_visible() -> bool:
	return _panel.visible


func cue_text() -> String:
	return _cue.text if _cue_panel.visible else ""


func panel() -> Control:
	return _panel


## Every text on the seated panel, for tests.
func panel_text() -> String:
	return "\n".join([_title.text, _speed.text, _battery.text, _range.text, _cargo.text, _seats.text, _warning.text, _keys.text])
