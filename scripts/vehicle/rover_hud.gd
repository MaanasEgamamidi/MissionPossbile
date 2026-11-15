class_name RoverHud
extends Control
## The rover's HUD widget (Prompt 10; restyled 2026-11-15 after the owner's FPV drone OSD,
## docs/revisions/reference/fpv_drone/flight_hud.gd), added by RoverPresenter under the GameHud layer (so it hides with
## the HUD).
##   bottom-right   while seated: an on-screen display drawn as outlined monospace text straight over the view, like
##                  the drone's: a low / critical battery banner (20 % / 10 %), a compass tape with the heading, ground
##                  speed (m/s and km/h), battery % with a battery icon and the time left at the current draw, home
##                  distance (to the garage charger), cabin status (sealed / open), cargo, range, who sits where and
##                  the keys
##   centre, below the crosshair   while standing and looking at the rover: what E would do ("[E] Get in: driver's seat")
## The OSD stays in the bottom-right corner: the vitals bar (top centre), the goals card (left), the network status
## (bottom-left) and the key hints (bottom-centre) keep their places, so nothing overlaps.
## It only shows what it is given (show_seated / show_cue); it never changes anything.

const EDGE := 24
const WIDTH := 400.0
const SEAT_NAMES: Array[String] = ["Driver", "Front", "Rear left", "Rear right"]

## The drone OSD's font (copied by the drone helper); the theme font until it is there.
const OSD_FONT_PATH := "res://assets/fonts/IBM_Plex_Mono-Medium.ttf"
const OSD_WHITE := Color("#f5fbff")
const OSD_SECONDARY := Color("#d8e8eb")
const OSD_OUTLINE := Color("#10191c")
const MINT := Color("#85f7dc")
const BATTERY_LOW := Color("#ffd08a")
const BATTERY_CRITICAL := Color("#ff6663")
const LOW_PERCENT := 20
const CRITICAL_PERCENT := 10
const COMPASS_POINTS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

## Heights of the OSD rows, px (the panel's height is their sum).
const BANNER_H := 40.0
const COMPASS_H := 66.0
const ROWS_H := 214.0

var _panel: Control
var _cue_panel: PanelContainer
var _cue: Label
var _font: Font

# what is shown (show_seated)
var _title := "Rover"
var _speed_text := ""
var _battery_text := ""
var _range_text := ""
var _cargo_text := ""
var _seats_text := ""
var _seats_osd := ""
var _keys_text := ""
var _warning_text := ""
var _cabin_text := ""
var _home_text := ""
var _time_text := ""
var _fuel_text := ""
var _speed := 0.0
var _percent := 100
var _heading := 0.0
var _driver := false
var _sealed := false


func _init() -> void:
	name = "RoverHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_panel = Control.new()
	_panel.name = "RoverPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var height := BANNER_H + COMPASS_H + ROWS_H
	_panel.offset_right = -EDGE
	_panel.offset_bottom = -EDGE
	_panel.offset_left = -EDGE - WIDTH
	_panel.offset_top = -EDGE - height
	_panel.custom_minimum_size = Vector2(WIDTH, height)
	_panel.draw.connect(_draw_osd)
	add_child(_panel)
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


## The OSD font: IBM Plex Mono when the drone helper has copied it, else the theme's default font.
func osd_font() -> Font:
	if _font != null:
		return _font
	if ResourceLoader.exists(OSD_FONT_PATH):
		_font = load(OSD_FONT_PATH) as Font
	if _font == null:
		_font = get_theme_default_font()
	if _font == null:
		_font = ThemeDB.fallback_font
	return _font


## Shows the seated OSD with `info`: speed_mps, battery_kwh, capacity_kwh, range_km, cargo_kg, cargo_capacity_kg,
## seats (4 names, "" for free), seat (this player's seat index), driver (bool), battery_empty (bool), keys (text).
## Optional (rover upgrade path): heading_deg (0 = north, clockwise), home_m (< 0 unknown), time_left_s (< 0: no draw
## now), cabin (bool, sealed cabin), sheltered (bool), fuel_cell_kwh, fuel_cell_capacity_kwh, rtg_kw, track_level,
## charging (bool).
func show_seated(info: Dictionary) -> void:
	_panel.visible = true
	_speed = absf(float(info.get("speed_mps", 0.0)))
	_speed_text = "Speed  %.1f m/s  (%.0f km/h)" % [_speed, _speed * 3.6]
	var kwh := float(info.get("battery_kwh", 0.0))
	var cap := maxf(0.001, float(info.get("capacity_kwh", 1.0)))
	_percent = clampi(ceili(kwh / cap * 100.0 - 1e-6), 0, 100) if kwh > 1e-6 else 0
	_battery_text = "Battery  %.2f kWh  (%d %%)" % [kwh, _percent]
	var fc_cap := float(info.get("fuel_cell_capacity_kwh", 0.0))
	_fuel_text = "Fuel cell  %.1f of %.0f kWh" % [float(info.get("fuel_cell_kwh", 0.0)), fc_cap] if fc_cap > 0.0 else ""
	if float(info.get("rtg_kw", 0.0)) > 0.0:
		_fuel_text = ("%s  ·  " % _fuel_text if _fuel_text != "" else "") + "RTG +%.1f kW" % float(info.get("rtg_kw", 0.0))
	_range_text = "Range about %.1f km with this load" % float(info.get("range_km", 0.0))
	_cargo_text = "Cargo  %.0f of %.0f kg" % [float(info.get("cargo_kg", 0.0)), float(info.get("cargo_capacity_kg", 0.0))]
	var names: Array = info.get("seats", ["", "", "", ""])
	var lines := PackedStringArray()
	var short := PackedStringArray()
	var mine := int(info.get("seat", -1))
	for i in mini(names.size(), SEAT_NAMES.size()):
		var who := String(names[i]) if String(names[i]) != "" else "free"
		lines.append("%s: %s%s" % [SEAT_NAMES[i], who, " (you)" if i == mine else ""])
		short.append("YOU" if i == mine else (who.left(10) if who != "free" else "-"))
	_seats_text = "  ".join(lines)
	_seats_osd = "SEATS  " + " · ".join(short)
	_driver = bool(info.get("driver", false))
	_title = "Rover: you are driving" if _driver else "Rover: you are riding"
	_heading = fposmod(float(info.get("heading_deg", 0.0)), 360.0)
	var home := float(info.get("home_m", -1.0))
	_home_text = "%d m" % roundi(home) if home >= 0.0 else "--"
	var left := float(info.get("time_left_s", -1.0))
	if bool(info.get("charging", false)):
		_time_text = "CHARGING"
	elif left < 0.0:
		_time_text = "PARKED"
	else:
		_time_text = "%s LEFT" % _clock(ceili(left))
	_sealed = bool(info.get("cabin", false))
	_cabin_text = ("SEALED" if _sealed else "OPEN")
	_cabin_text += (" · cabin air" if _sealed else " · suit air")
	if bool(info.get("battery_empty", false)):
		_warning_text = "Battery empty: the rover can only coast and brake."
	elif _percent <= CRITICAL_PERCENT:
		_warning_text = "Critical battery: drive back to the garage charger now."
	elif _percent <= LOW_PERCENT:
		_warning_text = "Low battery: head back to the garage charger."
	else:
		_warning_text = ""
	_keys_text = String(info.get("keys", ""))
	_panel.queue_redraw()


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


## Every text on the seated OSD, for tests.
func panel_text() -> String:
	return "\n".join([_title, _speed_text, _battery_text, _time_text, _fuel_text, _range_text, "Home %s" % _home_text,
		"Cabin %s" % _cabin_text, _cargo_text, _seats_text, _warning_text, _keys_text])


# ---------------------------------------------------------------- drawing (drone OSD style)

func _draw_osd() -> void:
	var w := _panel.size.x
	var y := 0.0
	if _percent <= LOW_PERCENT:
		_draw_banner(Rect2(0.0, y, w, 33.0))
	y += BANNER_H
	_draw_compass(w * 0.5, y)
	y += COMPASS_H

	# mode chip, like the drone's STAB / FPV
	var chip := "DRIVE" if _driver else "RIDE"
	var chip_w := _text_width(chip, 15) + 16.0
	_panel.draw_rect(Rect2(0.0, y, chip_w, 25.0), Color(OSD_OUTLINE, 0.86))
	_panel.draw_rect(Rect2(0.0, y, chip_w, 25.0), Color(MINT, 0.84), false, 1.0)
	_osd_text(Vector2(chip_w * 0.5, y + 18.0), chip, 15, MINT, HORIZONTAL_ALIGNMENT_CENTER)
	_osd_text(Vector2(chip_w + 12.0, y + 18.0), "ROVER", 15, OSD_WHITE)
	_draw_battery(w, y)
	y += 34.0

	# speed (left) under the chip
	_osd_text(Vector2(0.0, y + 13.0), "GROUND SPEED", 13, OSD_SECONDARY)
	_osd_text(Vector2(0.0, y + 39.0), "%04.1f m/s" % _speed, 23, OSD_WHITE)
	_osd_text(Vector2(0.0, y + 58.0), "%.0f km/h" % (_speed * 3.6), 14, OSD_SECONDARY)
	y += 72.0

	# home distance, cabin, cargo
	var col := w * 0.36
	var col2 := w
	_osd_text(Vector2(0.0, y + 13.0), "HOME DIST", 13, OSD_SECONDARY)
	_osd_text(Vector2(0.0, y + 36.0), _home_text, 20, OSD_WHITE)
	_osd_text(Vector2(col, y + 13.0), "CABIN", 13, OSD_SECONDARY)
	_osd_text(Vector2(col, y + 36.0), "SEALED" if _sealed else "OPEN", 20, MINT if _sealed else OSD_WHITE)
	_osd_text(Vector2(col2, y + 13.0), "CARGO", 13, OSD_SECONDARY, HORIZONTAL_ALIGNMENT_RIGHT)
	_osd_text(Vector2(col2, y + 36.0), _cargo_text.trim_prefix("Cargo  "), 20, OSD_WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	y += 46.0

	# range and the upgrade extras, seats, keys: right-aligned, so a long line grows into the view, never off screen
	var extra := _range_text.trim_suffix(" with this load").to_upper()
	if _fuel_text != "":
		extra += "  ·  " + _fuel_text.to_upper()
	_osd_text(Vector2(w, y + 14.0), extra, 13, OSD_SECONDARY, HORIZONTAL_ALIGNMENT_RIGHT)
	_osd_text(Vector2(w, y + 32.0), _seats_osd, 13, OSD_SECONDARY, HORIZONTAL_ALIGNMENT_RIGHT)
	_osd_text(Vector2(w, y + 52.0), _keys_text, 13, OSD_WHITE, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_compass(center_x: float, top: float) -> void:
	const PIXELS_PER_DEGREE := 3.25
	const TICK_RANGE := 55.0
	var tick_start := floori((_heading - TICK_RANGE) / 5.0) * 5
	for tick in range(tick_start, tick_start + 120, 5):
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
			var label: String = String(COMPASS_POINTS[posmod(roundi(bearing / 45.0), 8)]) if bearing % 45 == 0 else str(bearing)
			_osd_text(Vector2(x, top + 12.0), label, 13, Color(OSD_WHITE, opacity), HORIZONTAL_ALIGNMENT_CENTER)
	_osd_line(Vector2(center_x, top + 32.0), Vector2(center_x, top + 39.0), MINT, 2.0)
	_osd_text(Vector2(center_x, top + 57.0), "%03d°" % posmod(roundi(_heading), 360), 17, OSD_WHITE, HORIZONTAL_ALIGNMENT_CENTER)


func _battery_color() -> Color:
	if _percent <= CRITICAL_PERCENT:
		return BATTERY_CRITICAL
	if _percent <= LOW_PERCENT:
		return BATTERY_LOW
	return OSD_WHITE


func _draw_battery(right: float, top: float) -> void:
	var color := _battery_color()
	_osd_text(Vector2(right, top + 11.0), "ROVER BATTERY", 13, OSD_SECONDARY, HORIZONTAL_ALIGNMENT_RIGHT)
	var percent := "%d%%" % _percent
	var percent_width := _text_width(percent, 23)
	var battery := Rect2(right - percent_width - 50.0, top + 24.0, 37.0, 17.0)
	var fill_width := (battery.size.x - 6.0) * float(_percent) * 0.01
	_panel.draw_rect(battery.grow(2.0), OSD_OUTLINE, false, 4.0)
	_panel.draw_rect(battery, color, false, 1.5)
	_panel.draw_rect(Rect2(battery.end.x + 1.0, battery.position.y + 5.0, 4.0, 7.0), color)
	_panel.draw_rect(Rect2(battery.position + Vector2(3.0, 3.0), Vector2(fill_width, 11.0)), color)
	_osd_text(Vector2(right, top + 41.0), percent, 23, color, HORIZONTAL_ALIGNMENT_RIGHT)
	_osd_text(Vector2(right, top + 63.0), _time_text, 14, OSD_SECONDARY, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_banner(banner: Rect2) -> void:
	var color := _battery_color()
	var message := "LOW BATTERY"
	if _percent == 0:
		message = "BATTERY DEPLETED"
	elif _percent <= CRITICAL_PERCENT:
		message = "CRITICAL BATTERY"
	var hint := "RETURN TO CHARGER"
	var pulse := 1.0
	if _percent <= CRITICAL_PERCENT:
		pulse = 0.36 + 0.64 * (0.5 + 0.5 * cos(float(Time.get_ticks_msec()) / 1000.0 * TAU))
	_panel.draw_rect(banner, Color(OSD_OUTLINE, 0.87))
	_panel.draw_rect(Rect2(banner.position, Vector2(3.0, banner.size.y)), Color(color, pulse))
	_panel.draw_circle(banner.position + Vector2(18.0, 16.5), 3.5, Color(color, pulse))
	_osd_text(banner.position + Vector2(33.0, 22.0), message, 15, color)
	_osd_text(Vector2(banner.end.x - 13.0, banner.position.y + 22.0), hint, 13, OSD_SECONDARY, HORIZONTAL_ALIGNMENT_RIGHT)


func _clock(seconds: int) -> String:
	var s := maxi(0, seconds)
	if s >= 3600:
		return "%d:%02d:%02d" % [floori(s / 3600.0), floori(s / 60.0) % 60, s % 60]
	return "%02d:%02d" % [floori(s / 60.0), s % 60]


func _text_width(value: String, font_size: int) -> float:
	return osd_font().get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _osd_text(point: Vector2, value: String, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	if value == "":
		return
	var font := osd_font()
	if alignment != HORIZONTAL_ALIGNMENT_LEFT:
		var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		point.x -= width * (0.5 if alignment == HORIZONTAL_ALIGNMENT_CENTER else 1.0)
	_panel.draw_string_outline(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(OSD_OUTLINE, color.a * 0.92))
	_panel.draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _osd_line(start: Vector2, finish: Vector2, color: Color, width: float) -> void:
	_panel.draw_line(start, finish, Color(OSD_OUTLINE, color.a * 0.85), width + 2.0, true)
	_panel.draw_line(start, finish, color, width, true)
