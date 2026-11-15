extends Control
## The scout drone's own HUD widget (2026-11-14), added by DronePresenter under the GameHud layer so it hides with the
## HUD. No class_name. Bottom-right, the same corner as the rover's widget (nobody drives and flies at once):
##   while piloting: level and mode, battery (bar and seconds of flight), distance from the pad of the radio range,
##   height, speed, the keys, and a warning line (near the range edge, at the edge, battery low).
## It only shows what it is given (show_flight / hide_flight); it never changes anything.

const EDGE := 24
const WIDTH := 380.0

var _panel: PanelContainer
var _title: Label
var _battery: Label
var _battery_bar: ProgressBar
var _range: Label
var _height: Label
var _keys: Label
var _warning: Label


func _init() -> void:
	name = "DroneHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_panel = PanelContainer.new()
	_panel.name = "DronePanel"
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
	_battery = _label(box, "Battery", &"")
	_battery_bar = ProgressBar.new()
	_battery_bar.name = "BatteryBar"
	_battery_bar.show_percentage = false
	_battery_bar.custom_minimum_size = Vector2(WIDTH - 40.0, 14.0)
	_battery_bar.max_value = 1.0
	_battery_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_battery_bar)
	_range = _label(box, "Range", &"")
	_height = _label(box, "Height", &"")
	_warning = _label(box, "Warning", UiTheme.WARN)
	_keys = _label(box, "Keys", UiTheme.MUTED)
	_panel.visible = false


func _label(parent: Control, n: String, variation: StringName) -> Label:
	var l := Label.new()
	l.name = n
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 40.0
	if variation != &"":
		l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## info: level, mode, battery (0..1), seconds_left, distance_m, range_m, range_state ("ok"/"warn"/"edge"), height_m,
## speed_mps, keys, warning (text or "").
func show_flight(info: Dictionary) -> void:
	_panel.visible = true
	_title.text = "✈ Scout drone V%d · %s" % [int(info.get("level", 1)), String(info.get("mode", ""))]
	var b := clampf(float(info.get("battery", 0.0)), 0.0, 1.0)
	_battery.text = "Battery %d %% · about %d s of flight" % [roundi(b * 100.0), roundi(float(info.get("seconds_left", 0.0)))]
	_battery_bar.value = b
	_battery_bar.theme_type_variation = UiTheme.BAR_URGENT if b < 0.2 else (UiTheme.BAR_WARN if b < 0.4 else UiTheme.BAR_GOOD)
	_range.text = "Radio range: %d of %d m from the pad" % [roundi(float(info.get("distance_m", 0.0))), roundi(float(info.get("range_m", 0.0)))]
	_range.theme_type_variation = UiTheme.URGENT if String(info.get("range_state", "ok")) == "edge" else (UiTheme.WARN if String(info.get("range_state", "ok")) == "warn" else &"")
	_height.text = "Height %d m · speed %.1f m/s" % [roundi(float(info.get("height_m", 0.0))), float(info.get("speed_mps", 0.0))]
	_keys.text = String(info.get("keys", ""))
	var w := String(info.get("warning", ""))
	_warning.text = w
	_warning.visible = w != ""


func hide_flight() -> void:
	_panel.visible = false


func is_showing() -> bool:
	return _panel.visible


## The text of the panel (tests).
func text() -> String:
	return "\n".join([_title.text, _battery.text, _range.text, _height.text, _warning.text, _keys.text])
