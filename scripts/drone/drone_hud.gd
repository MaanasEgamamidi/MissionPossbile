extends Control
## The scout drone's on-screen display (upgrade paths plan §6.2), drawn like the owner's FPV example
## (docs/revisions/reference/fpv_drone/flight_hud.gd). No class_name. Added by DronePresenter under the GameHud layer so
## it hides with the HUD; it covers the screen while the player looks through the drone:
##   top left    mode tag MANUAL / AUTO, then FPV / CHASE and the drone's level
##   top centre  compass tape with the heading (0 = north)
##   top right   AIRCRAFT BATTERY: icon, %, time left; LOW at 20 %, CRITICAL at 10 % (pulsing banner, "R  FLY HOME");
##               "FLYING HOME" while it returns by itself
##   centre      the FPV reticle (FPV camera only)
##   bottom      GROUND SPEED, HOME DIST, ALTITUDE, FLIGHT TIME, the pip row of this flight's survey targets, the keys
##   left        the mineral report card when a new report arrives (show_report)
## Font IBM Plex Mono Medium (assets/fonts/, SIL OFL 1.1: assets/fonts/IBM_Plex_Mono-OFL.txt).
## It only shows what it is given (show_flight / show_report / hide_flight); it never changes anything.

const FONT_PATH := "res://assets/fonts/IBM_Plex_Mono-Medium.ttf"
const OSD_WHITE := Color("#f5fbff")
const OSD_SECONDARY := Color("#d8e8eb")
const OSD_OUTLINE := Color("#10191c")
const MINT := Color("#85f7dc")
const BATTERY_LOW := Color("#ffd08a")
const BATTERY_CRITICAL := Color("#ff6663")
const LOW_PERCENT := 20
const CRITICAL_PERCENT := 10
const COMPASS_POINTS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const REPORT_SECONDS := 9.0
const REPORT_WIDTH := 380.0

var _font: Font
var _showing := false
var _mode := "MANUAL"
var _returning := false
var _chase := true
var _level := 1
var _heading := 0.0
var _battery_percent := 100
var _seconds_left := 0.0
var _ground_speed := 0.0
var _home_distance := 0.0
var _altitude := 0.0
var _flight_seconds := 0.0
var _targets_total := 0
var _targets_done := 0
var _targets_label := ""
var _warning := ""
var _keys := ""
var _report_title := ""
var _report_text := ""
var _report_left := 0.0


func _init() -> void:
	name = "DroneHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = _load_font()
	visible = false


static func _load_font() -> Font:
	if ResourceLoader.exists(FONT_PATH):
		var f := load(FONT_PATH) as Font
		if f != null:
			return f
	if FileAccess.file_exists(FONT_PATH):
		var file := FontFile.new()
		if file.load_dynamic_font(FONT_PATH) == OK:
			return file
	return ThemeDB.fallback_font


func _process(delta: float) -> void:
	if not _showing:
		return
	if _report_left > 0.0:
		_report_left = maxf(0.0, _report_left - delta)
	queue_redraw()


## info: level, mode ("MANUAL"/"AUTO"), returning, chase, heading (deg), battery (0..1), seconds_left, ground_speed,
## home_m, alt_m, flight_s, targets_total, targets_done, targets_label, warning, keys.
func show_flight(info: Dictionary) -> void:
	_showing = true
	visible = true
	_level = int(info.get("level", 1))
	_mode = String(info.get("mode", "MANUAL"))
	_returning = bool(info.get("returning", false))
	_chase = bool(info.get("chase", true))
	_heading = fposmod(float(info.get("heading", 0.0)), 360.0)
	_battery_percent = clampi(ceili(100.0 * clampf(float(info.get("battery", 0.0)), 0.0, 1.0) - 0.0001), 0, 100)
	_seconds_left = maxf(0.0, float(info.get("seconds_left", 0.0)))
	_ground_speed = float(info.get("ground_speed", 0.0))
	_home_distance = float(info.get("home_m", 0.0))
	_altitude = float(info.get("alt_m", 0.0))
	_flight_seconds = float(info.get("flight_s", 0.0))
	_targets_total = int(info.get("targets_total", 0))
	_targets_done = int(info.get("targets_done", 0))
	_targets_label = String(info.get("targets_label", ""))
	_warning = String(info.get("warning", ""))
	_keys = String(info.get("keys", ""))
	queue_redraw()


## Pops the mineral (or mission) report up for REPORT_SECONDS.
func show_report(title: String, body: String) -> void:
	_report_title = title.to_upper()
	_report_text = body
	_report_left = REPORT_SECONDS
	queue_redraw()


func hide_flight() -> void:
	_showing = false
	visible = false
	_report_left = 0.0


func is_showing() -> bool:
	return _showing


## The display as text (tests).
func text() -> String:
	return "\n".join(PackedStringArray([
		"%s %s V%d" % [_mode, "CHASE" if _chase else "FPV", _level],
		"HDG %03d" % posmod(roundi(_heading), 360),
		"BATTERY %d%% %s LEFT%s" % [_battery_percent, _clock(ceili(_seconds_left)), (" " + _battery_message()) if _battery_message() != "" else ""],
		"GROUND SPEED %04.1f m/s · HOME DIST %d m · ALT %d m · FLIGHT TIME %s" % [_ground_speed, roundi(_home_distance), roundi(_altitude), _clock(floori(_flight_seconds))],
		_targets_label, _warning, _report_title, _report_text if _report_left > 0.0 else "", _keys]))


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if not _showing:
		return
	var margin := clampf(size.x * 0.038, 34.0, 64.0)
	var right := size.x - margin
	var center_x := size.x * 0.5
	var top := 33.0
	var bottom := size.y - 46.0

	# mode tag + camera
	var tag_w := _width(_mode, 15) + 18.0
	var tag_color := MINT if _mode == "MANUAL" else BATTERY_LOW
	draw_rect(Rect2(margin, top, tag_w, 25), Color(OSD_OUTLINE, 0.86))
	draw_rect(Rect2(margin, top, tag_w, 25), Color(tag_color, 0.84), false, 1.0)
	_osd_text(Vector2(margin + tag_w * 0.5, top + 18), _mode, 15, tag_color, HORIZONTAL_ALIGNMENT_CENTER)
	_osd_text(Vector2(margin + tag_w + 12, top + 18), "CHASE" if _chase else "FPV", 15, OSD_WHITE)
	_osd_text(Vector2(margin, top + 46), "SCOUT DRONE V%d" % _level, 13, OSD_SECONDARY)

	_draw_compass(center_x, top)
	_draw_battery(right, top)

	if not _chase:
		var center := size * 0.5
		draw_arc(center, 10.0, 0.0, TAU, 32, OSD_OUTLINE, 3.5, true)
		draw_arc(center, 10.0, 0.0, TAU, 32, OSD_WHITE, 1.5, true)
		draw_circle(center, 1.3, OSD_WHITE, true, -1.0, true)
		for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT]:
			_osd_line(center + direction * 15.0, center + direction * 26.0, OSD_WHITE, 1.4)

	if _warning != "":
		_osd_text(Vector2(center_x, top + 150), _warning, 14, BATTERY_LOW, HORIZONTAL_ALIGNMENT_CENTER)

	_osd_text(Vector2(margin, bottom - 27), "GROUND SPEED", 13, OSD_SECONDARY)
	_osd_text(Vector2(margin, bottom), "%04.1f m/s" % _ground_speed, 23, OSD_WHITE)
	_osd_text(Vector2(margin + 157, bottom - 27), "HOME DIST", 13, OSD_SECONDARY)
	_osd_text(Vector2(margin + 157, bottom), "%d m" % roundi(_home_distance), 23, OSD_WHITE)
	_osd_text(Vector2(margin + 290, bottom - 27), "ALTITUDE", 13, OSD_SECONDARY)
	_osd_text(Vector2(margin + 290, bottom), "%d m" % roundi(_altitude), 23, OSD_WHITE)
	_osd_text(Vector2(right, bottom - 27), "FLIGHT TIME", 13, OSD_SECONDARY, HORIZONTAL_ALIGNMENT_RIGHT)
	_osd_text(Vector2(right, bottom), _clock(floori(_flight_seconds)), 23, OSD_WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_draw_targets(center_x, bottom)
	if _keys != "":
		_osd_text(Vector2(center_x, size.y - 12.0), _keys, 11, Color(OSD_SECONDARY, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	if _report_left > 0.0:
		_draw_report(margin, top + 96.0)


func _draw_compass(center_x: float, top: float) -> void:
	const PIXELS_PER_DEGREE := 3.25
	const TICK_RANGE := 45.0
	var tick_start := floori((_heading - TICK_RANGE) / 5.0) * 5
	for tick in range(tick_start, tick_start + 100, 5):
		var delta := float(tick) - _heading
		var opacity := clampf((TICK_RANGE - absf(delta)) / 8.0, 0.0, 1.0)
		if opacity <= 0.0:
			continue
		var x := center_x + delta * PIXELS_PER_DEGREE
		var major := posmod(tick, 15) == 0
		var tick_height := 10.0 if major else 5.0
		_osd_line(Vector2(x, top + 29.0 - tick_height), Vector2(x, top + 29.0), Color(OSD_WHITE, opacity), 1.2)
		if major:
			var bearing := posmod(tick, 360)
			var label: String = COMPASS_POINTS[roundi(bearing / 45.0) % 8] if bearing % 45 == 0 else str(bearing)
			_osd_text(Vector2(x, top + 12), label, 13, Color(OSD_WHITE, opacity), HORIZONTAL_ALIGNMENT_CENTER)
	_osd_line(Vector2(center_x, top + 32), Vector2(center_x, top + 39), MINT, 2.0)
	_osd_text(Vector2(center_x, top + 57), "%03d°" % posmod(roundi(_heading), 360), 17, OSD_WHITE, HORIZONTAL_ALIGNMENT_CENTER)


func _battery_color() -> Color:
	if _battery_percent <= CRITICAL_PERCENT:
		return BATTERY_CRITICAL
	if _battery_percent <= LOW_PERCENT:
		return BATTERY_LOW
	return OSD_WHITE


func _battery_message() -> String:
	if _battery_percent == 0:
		return "BATTERY DEPLETED"
	if _battery_percent <= CRITICAL_PERCENT:
		return "CRITICAL BATTERY"
	if _battery_percent <= LOW_PERCENT:
		return "LOW BATTERY"
	return ""


func _draw_battery(right: float, top: float) -> void:
	var color := _battery_color()
	_osd_text(Vector2(right, top + 11), "AIRCRAFT BATTERY", 13, OSD_SECONDARY, HORIZONTAL_ALIGNMENT_RIGHT)
	var percent := "%d%%" % _battery_percent
	var battery := Rect2(right - _width(percent, 23) - 50, top + 24, 37, 17)
	var fill_width := (battery.size.x - 6.0) * _battery_percent * 0.01
	draw_rect(battery.grow(2.0), OSD_OUTLINE, false, 4.0)
	draw_rect(battery, color, false, 1.5)
	draw_rect(Rect2(battery.end.x + 1, battery.position.y + 5, 4, 7), color)
	draw_rect(Rect2(battery.position + Vector2(3, 3), Vector2(fill_width, 11)), color)
	_osd_text(Vector2(right, top + 41), percent, 23, color, HORIZONTAL_ALIGNMENT_RIGHT)
	_osd_text(Vector2(right, top + 63), "%s LEFT" % _clock(ceili(_seconds_left)), 14, OSD_SECONDARY, HORIZONTAL_ALIGNMENT_RIGHT)
	if _battery_percent <= LOW_PERCENT:
		_draw_banner(top + 78, _battery_message(), "FLYING HOME" if _returning else "R  FLY HOME", color, _battery_percent <= CRITICAL_PERCENT)
	elif _returning:
		_draw_banner(top + 78, "FLYING HOME", "AUTO RETURN", MINT, false)


func _draw_banner(y: float, message: String, hint: String, color: Color, pulsing: bool) -> void:
	var width := _width(message + hint, 15) + 68.0
	var banner := Rect2((size.x - width) * 0.5, y, width, 33)
	var pulse := 1.0
	if pulsing:
		pulse = 0.36 + 0.64 * (0.5 + 0.5 * cos(_flight_seconds * TAU))
	draw_rect(banner, Color(OSD_OUTLINE, 0.87))
	draw_rect(Rect2(banner.position, Vector2(3, banner.size.y)), Color(color, pulse))
	draw_circle(banner.position + Vector2(18, 16.5), 3.5, Color(color, pulse), true, -1.0, true)
	_osd_text(banner.position + Vector2(33, 22), message, 15, color)
	_osd_text(Vector2(banner.end.x - 13, y + 22), hint, 13, OSD_SECONDARY, HORIZONTAL_ALIGNMENT_RIGHT)


## The pip row of this flight's survey targets (mission waypoints, or deposits found in manual flight).
func _draw_targets(center_x: float, bottom: float) -> void:
	if _targets_label == "":
		return
	var total := mini(_targets_total, 12)
	var label := _targets_label
	if _targets_total > 0 and _targets_done >= _targets_total and _mode == "AUTO" and _returning:
		label += "  DONE"
	_osd_text(Vector2(center_x, bottom - 18), label, 14, OSD_WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	if total <= 0:
		return
	var x := center_x - (total * 18.0 - 4.0) * 0.5
	for i in total:
		var pip := Rect2(x + i * 18.0, bottom - 5.0, 14.0, 4.0)
		draw_rect(pip.grow(1.0), OSD_OUTLINE)
		if i < _targets_done:
			draw_rect(pip, OSD_WHITE)
		elif i == _targets_done:
			draw_rect(pip, MINT)
		else:
			draw_rect(pip, Color(OSD_WHITE, 0.40))


func _draw_report(x: float, y: float) -> void:
	var fade := clampf(_report_left / 0.6, 0.0, 1.0)
	var body_h := _font.get_multiline_string_size(_report_text, HORIZONTAL_ALIGNMENT_LEFT, REPORT_WIDTH - 28.0, 14).y
	var box := Rect2(x, y, REPORT_WIDTH, 44.0 + body_h)
	draw_rect(box, Color(OSD_OUTLINE, 0.88 * fade))
	draw_rect(Rect2(box.position, Vector2(3, box.size.y)), Color(MINT, fade))
	_osd_text(box.position + Vector2(16, 22), _report_title, 14, Color(MINT, fade))
	draw_multiline_string(_font, box.position + Vector2(16, 44), _report_text, HORIZONTAL_ALIGNMENT_LEFT,
		REPORT_WIDTH - 28.0, 14, -1, Color(OSD_WHITE, fade))


func _clock(seconds: int) -> String:
	return "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]


func _width(value: String, font_size: int) -> float:
	return _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _osd_text(point: Vector2, value: String, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	if alignment != HORIZONTAL_ALIGNMENT_LEFT:
		point.x -= _width(value, font_size) * (0.5 if alignment == HORIZONTAL_ALIGNMENT_CENTER else 1.0)
	draw_string_outline(_font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(OSD_OUTLINE, color.a * 0.92))
	draw_string(_font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _osd_line(start: Vector2, finish: Vector2, color: Color, width: float) -> void:
	draw_line(start, finish, Color(OSD_OUTLINE, color.a * 0.85), width + 2.0, true)
	draw_line(start, finish, color, width, true)
