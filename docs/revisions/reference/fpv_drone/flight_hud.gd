extends Control

signal fly_requested

const INK := Color("#0e1d20")
const PAPER := Color("#f4ebd8")
const MUTED := Color("#b9c7c2")
const MINT := Color("#85f7dc")
const KEY_COLOR := Color("#30484a")
const HEADER_HEIGHT := 62.0
const FOOTER_HEIGHT := 52.0

const OSD_FONT := preload("res://assets/IBM_Plex_Mono-Medium.ttf")
const OSD_WHITE := Color("#f5fbff")
const OSD_SECONDARY := Color("#d8e8eb")
const OSD_OUTLINE := Color("#10191c")
const BATTERY_LOW := Color("#ffd08a")
const BATTERY_CRITICAL := Color("#ff6663")
const LOW_PERCENT := 20
const CRITICAL_PERCENT := 10
const COMPASS_POINTS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

@onready var _font: Font = get_theme_default_font()

var _display_font := FontVariation.new()
var _fly_button: Button
var _passed := 0
var _total := 0
var _chase := false
var _menu_open := true
var _paused := false
var _flight_seconds := 0.0
var _seconds_left := 0.0
var _battery_percent := 100
var _heading := 0.0
var _ground_speed := 0.0
var _home_distance := 0.0


func _ready() -> void:
	_display_font.base_font = _font
	_display_font.variation_embolden = 0.8
	_fly_button = Button.new()
	_fly_button.text = "Click to fly"
	_fly_button.focus_mode = Control.FOCUS_NONE
	_fly_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_fly_button.size = Vector2(222, 48)
	_fly_button.add_theme_font_size_override("font_size", 17)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color"]:
		_fly_button.add_theme_color_override(color_name, INK)
	_fly_button.add_theme_stylebox_override("normal", _button_style(MINT))
	_fly_button.add_theme_stylebox_override("hover", _button_style(Color("#c3fff1")))
	_fly_button.add_theme_stylebox_override("pressed", _button_style(Color("#61d4b8")))
	_fly_button.pressed.connect(fly_requested.emit)
	add_child(_fly_button)
	resized.connect(_layout_menu)
	_layout_menu()


func hide_menu() -> void:
	_menu_open = false
	_fly_button.hide()
	queue_redraw()


func show_pause() -> void:
	_menu_open = true
	_paused = true
	_fly_button.text = "Resume flight"
	_fly_button.show()
	queue_redraw()


func show_camera(chase: bool) -> void:
	_chase = chase
	queue_redraw()


func show_progress(passed: int, total: int) -> void:
	_passed = passed
	_total = total
	queue_redraw()


func show_telemetry(elapsed: float, pack_duration: float, heading: float,
		ground_speed: float, home_distance: float) -> void:
	_flight_seconds = elapsed
	_seconds_left = maxf(pack_duration - elapsed, 0.0)
	_battery_percent = clampi(ceili(100.0 * _seconds_left / pack_duration), 0, 100)
	_heading = fposmod(heading, 360.0)
	_ground_speed = ground_speed
	_home_distance = home_distance
	queue_redraw()


func _layout_menu() -> void:
	_fly_button.position = Vector2(54, size.y * 0.5 + 83)
	queue_redraw()


func _draw() -> void:
	if not _menu_open:
		_draw_osd()
		return

	draw_rect(Rect2(0, 0, size.x, HEADER_HEIGHT), Color(INK, 0.91))
	draw_line(Vector2(0, HEADER_HEIGHT), Vector2(size.x, HEADER_HEIGHT), Color(MINT, 0.32))
	_text(_display_font, Vector2(30, 40), "DRYLINE", 25, PAPER)
	_text(_font, Vector2(155, 38), "FPV PRACTICE RANGE", 14, MUTED)

	var camera := "CHASE" if _chase else "FPV"
	var status := "COURSE COMPLETE" if _passed == _total else "GATES  %02d / %02d" % [_passed, _total]
	var status_width := _font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	_text(_display_font, Vector2(size.x - 94, 38), camera, 15, MINT)
	_text(_font, Vector2(size.x - 122 - status_width, 38), status, 15, PAPER)

	var footer_y := size.y - FOOTER_HEIGHT
	draw_rect(Rect2(0, footer_y, size.x, FOOTER_HEIGHT), Color(INK, 0.93))
	draw_line(Vector2(0, footer_y), Vector2(size.x, footer_y), Color(MINT, 0.24))
	_draw_controls(footer_y + 33)

	var center_y := size.y * 0.5
	draw_rect(Rect2(0, HEADER_HEIGHT, size.x, size.y - HEADER_HEIGHT - FOOTER_HEIGHT), Color(INK, 0.13))
	draw_rect(Rect2(30, center_y - 146, 433, 302), Color(INK, 0.94))
	draw_rect(Rect2(30, center_y - 146, 3, 302), MINT)
	_text(_font, Vector2(54, center_y - 101), "FREE FLIGHT / GATE COURSE", 15, MINT)
	_text(_display_font, Vector2(52, center_y - 32), "Flight paused" if _paused else "Take flight", 48, PAPER)
	_text(_font, Vector2(54, center_y + 16), "Fly through each lit gate in order.", 17, PAPER)
	_text(_font, Vector2(54, center_y + 45), "Explore the range at your own pace.", 16, MUTED)


func _draw_osd() -> void:
	var margin := clampf(size.x * 0.038, 34.0, 64.0)
	var right := size.x - margin
	var center_x := size.x * 0.5
	var top := 33.0
	var bottom := size.y - 36.0

	draw_rect(Rect2(margin, top, 53, 25), Color(OSD_OUTLINE, 0.86))
	draw_rect(Rect2(margin, top, 53, 25), Color(MINT, 0.84), false, 1.0)
	_osd_text(Vector2(margin + 26.5, top + 18), "STAB", 15, MINT, HORIZONTAL_ALIGNMENT_CENTER)
	_osd_text(Vector2(margin + 65, top + 18), "CHASE" if _chase else "FPV", 15, OSD_WHITE)
	_draw_compass(center_x, top)
	_draw_battery(right, top)

	if not _chase:
		var center := size * 0.5
		draw_arc(center, 10.0, 0.0, TAU, 32, OSD_OUTLINE, 3.5, true)
		draw_arc(center, 10.0, 0.0, TAU, 32, OSD_WHITE, 1.5, true)
		draw_circle(center, 1.3, OSD_WHITE, true, -1.0, true)
		for direction in [Vector2.LEFT, Vector2.RIGHT]:
			_osd_line(center + direction * 15.0, center + direction * 26.0, OSD_WHITE, 1.4)

	_osd_text(Vector2(margin, bottom - 27), "GROUND SPEED", 13, OSD_SECONDARY)
	_osd_text(Vector2(margin, bottom), "%04.1f m/s" % _ground_speed, 23, OSD_WHITE)
	_osd_text(Vector2(margin + 157, bottom - 27), "HOME DIST", 13, OSD_SECONDARY)
	_osd_text(Vector2(margin + 157, bottom), "%d m" % roundi(_home_distance), 23, OSD_WHITE)
	_osd_text(Vector2(right, bottom - 27), "FLIGHT TIME", 13, OSD_SECONDARY, HORIZONTAL_ALIGNMENT_RIGHT)
	_osd_text(Vector2(right, bottom), _clock(floori(_flight_seconds)),
		23, OSD_WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_draw_course_progress(center_x, bottom)


func _draw_compass(center_x: float, top: float) -> void:
	const PIXELS_PER_DEGREE := 3.25
	const TICK_RANGE := 45.0
	var tick_start := floori((_heading - TICK_RANGE) / 5.0) * 5
	for tick in range(tick_start, tick_start + 100, 5):
		var delta := tick - _heading
		var opacity := clampf((TICK_RANGE - absf(delta)) / 8.0, 0.0, 1.0)
		if opacity <= 0.0:
			continue
		var x := center_x + delta * PIXELS_PER_DEGREE
		var major := tick % 15 == 0
		var tick_height := 10.0 if major else 5.0
		_osd_line(Vector2(x, top + 29.0 - tick_height), Vector2(x, top + 29.0),
			Color(OSD_WHITE, opacity), 1.2)
		if major:
			var bearing := posmod(tick, 360)
			var label: String = COMPASS_POINTS[roundi(bearing / 45.0)] if bearing % 45 == 0 else str(bearing)
			_osd_text(Vector2(x, top + 12), label, 13,
				Color(OSD_WHITE, opacity), HORIZONTAL_ALIGNMENT_CENTER)
	_osd_line(Vector2(center_x, top + 32), Vector2(center_x, top + 39), MINT, 2.0)
	_osd_text(Vector2(center_x, top + 57), "%03d°" % posmod(roundi(_heading), 360),
		17, OSD_WHITE, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_battery(right: float, top: float) -> void:
	var color := OSD_WHITE
	if _battery_percent <= CRITICAL_PERCENT:
		color = BATTERY_CRITICAL
	elif _battery_percent <= LOW_PERCENT:
		color = BATTERY_LOW

	_osd_text(Vector2(right, top + 11), "AIRCRAFT BATTERY", 13, OSD_SECONDARY, HORIZONTAL_ALIGNMENT_RIGHT)
	var percent := "%d%%" % _battery_percent
	var percent_width := OSD_FONT.get_string_size(percent, HORIZONTAL_ALIGNMENT_LEFT, -1, 23).x
	var battery := Rect2(right - percent_width - 50, top + 24, 37, 17)
	var fill_width := (battery.size.x - 6.0) * _battery_percent * 0.01
	draw_rect(battery.grow(2.0), OSD_OUTLINE, false, 4.0)
	draw_rect(battery, color, false, 1.5)
	draw_rect(Rect2(battery.end.x + 1, battery.position.y + 5, 4, 7), color)
	draw_rect(Rect2(battery.position + Vector2(3, 3), Vector2(fill_width, 11)), color)
	_osd_text(Vector2(right, top + 41), percent, 23, color, HORIZONTAL_ALIGNMENT_RIGHT)
	_osd_text(Vector2(right, top + 63), "%s LEFT" % _clock(ceili(_seconds_left)),
		14, OSD_SECONDARY, HORIZONTAL_ALIGNMENT_RIGHT)

	if _battery_percent <= LOW_PERCENT:
		_draw_battery_warning(top + 78, color)


func _draw_battery_warning(y: float, color: Color) -> void:
	var message := "LOW BATTERY"
	if _battery_percent == 0:
		message = "BATTERY DEPLETED"
	elif _battery_percent <= CRITICAL_PERCENT:
		message = "CRITICAL BATTERY"
	var hint := "R  REPLACE PACK"
	var width := OSD_FONT.get_string_size(message + hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 68.0
	var banner := Rect2((size.x - width) * 0.5, y, width, 33)
	var pulse := 1.0
	if _battery_percent <= CRITICAL_PERCENT:
		pulse = 0.36 + 0.64 * (0.5 + 0.5 * cos(_flight_seconds * TAU))
	draw_rect(banner, Color(OSD_OUTLINE, 0.87))
	draw_rect(Rect2(banner.position, Vector2(3, banner.size.y)), Color(color, pulse))
	draw_circle(banner.position + Vector2(18, 16.5), 3.5, Color(color, pulse), true, -1.0, true)
	_osd_text(banner.position + Vector2(33, 22), message, 15, color)
	_osd_text(Vector2(banner.end.x - 13, y + 22), hint, 13, OSD_SECONDARY, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_course_progress(center_x: float, bottom: float) -> void:
	var label := "COURSE COMPLETE" if _passed == _total else "GATES %02d / %02d" % [_passed, _total]
	_osd_text(Vector2(center_x, bottom - 18), label, 14, OSD_WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var x := center_x - (_total * 18.0 - 4.0) * 0.5
	for gate in _total:
		var pip := Rect2(x + gate * 18.0, bottom - 5.0, 14.0, 4.0)
		draw_rect(pip.grow(1.0), OSD_OUTLINE)
		if gate <= _passed:
			draw_rect(pip, MINT if gate == _passed else OSD_WHITE)
		else:
			draw_rect(pip, Color(OSD_WHITE, 0.40))


func _clock(seconds: int) -> String:
	return "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]


func _osd_text(point: Vector2, value: String, font_size: int, color: Color,
		alignment := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	if alignment != HORIZONTAL_ALIGNMENT_LEFT:
		var width := OSD_FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		point.x -= width * (0.5 if alignment == HORIZONTAL_ALIGNMENT_CENTER else 1.0)
	draw_string_outline(OSD_FONT, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, 4, Color(OSD_OUTLINE, color.a * 0.92))
	draw_string(OSD_FONT, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _osd_line(start: Vector2, finish: Vector2, color: Color, width: float) -> void:
	draw_line(start, finish, Color(OSD_OUTLINE, color.a * 0.85), width + 2.0, true)
	draw_line(start, finish, color, width, true)


func _draw_controls(baseline: float) -> void:
	var controls := [
		["WASD", "Move"],
		["Mouse", "Turn"],
		["Space", "Ascend"],
		["Ctrl", "Descend"],
		["C", "Camera"],
		["R", "Reset"],
		["Esc", "Pause"],
	]
	var x := 30.0
	for control in controls:
		var key: String = control[0]
		var action: String = control[1]
		var key_width := _display_font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 16.0
		draw_rect(Rect2(x, baseline - 20, key_width, 25), KEY_COLOR)
		_text(_display_font, Vector2(x + 8, baseline - 2), key, 14, PAPER)
		_text(_font, Vector2(x + key_width + 8, baseline - 2), action, 15, MUTED)
		x += key_width + _font.get_string_size(action, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 25.0


func _text(font: Font, point: Vector2, value: String, font_size: int, color: Color) -> void:
	draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(2)
	return style
