class_name MainMenu
extends UiPanel
## The title screen: a drawn Mars horizon with the game's name and the menu in a column on the left:
## continue, start a new colony, host or join on the local network, settings, sources, quit.
## It only emits signals; the game decides what each one does. show_notice() puts a plain message on the menu.

signal continue_pressed
signal new_game_pressed
signal host_pressed(port: int, continue_save: bool)
signal join_pressed(address: String, port: int)
signal quit_pressed

const JOIN_HELP := "Ask the host for the address shown on their screen. You must be on the same network."
## Width of the menu column on the left, in screen units.
const SIDE_WIDTH := 560.0

var _continue_button: Button
var _continue_info: Label
var _new_button: Button
var _host_button: Button
var _host_box: VBoxContainer
var _host_port: LineEdit
var _host_continue: CheckBox
var _host_start: Button
var _join_button: Button
var _join_box: VBoxContainer
var _join_address: LineEdit
var _join_port: LineEdit
var _join_start: Button
var _settings_button: Button
var _sources_button: Button
var _quit_button: Button
var _notice: Label


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	name = "MainMenu"
	keeps_world_visible = false
	accent_line = false
	# No box of its own: the title screen is a drawn Mars horizon (see _draw) with the menu in a column on the left.
	var bare := StyleBoxEmpty.new()
	bare.content_margin_left = 56.0
	bare.content_margin_right = 56.0
	bare.content_margin_top = 28.0
	bare.content_margin_bottom = 28.0
	add_theme_stylebox_override(&"panel", bare)
	var layout := HBoxContainer.new()
	layout.name = "Layout"
	add_child(layout)
	var outer := VBoxContainer.new()
	outer.name = "Side"
	outer.custom_minimum_size.x = SIDE_WIDTH
	layout.add_child(outer)
	var art_space := Control.new()
	art_space.name = "ArtSpace"
	art_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(art_space)

	var title := _label("MARS\nCOLONY", UiTheme.DISPLAY)
	title.name = "Title"
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.add_theme_constant_override(&"line_spacing", -10)
	outer.add_child(title)
	var tagline := _label("Keep a base on Mars alive together: power, oxygen, water and food.", UiTheme.MUTED)
	tagline.name = "Tagline"
	outer.add_child(tagline)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	outer.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# room for the focus ring, which is drawn just outside a button
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 6)
	scroll.add_child(pad)
	var column := VBoxContainer.new()
	column.name = "Buttons"
	column.add_theme_constant_override(&"separation", 12)
	pad.add_child(column)

	_continue_button = _button(column, "Continue", UiTheme.PRIMARY_BUTTON)
	_continue_button.pressed.connect(func() -> void: continue_pressed.emit())
	_continue_info = _label("", UiTheme.MUTED)
	column.add_child(_continue_info)
	_new_button = _button(column, "New colony")
	_new_button.pressed.connect(func() -> void: new_game_pressed.emit())

	_host_button = _button(column, "Host on this network")
	_host_button.toggle_mode = true
	_host_box = _sub_box(column)
	_host_box.add_child(_label("Other players on the same network can join your colony.", UiTheme.MUTED))
	_host_box.add_child(_label("Port (a number the other players also type)"))
	_host_port = _field(_host_box, str(NetSession.DEFAULT_PORT), "")
	_host_continue = CheckBox.new()
	_host_continue.text = "Continue my saved colony"
	_host_box.add_child(_host_continue)
	_host_start = _button(_host_box, "Start hosting", UiTheme.PRIMARY_BUTTON)
	_host_start.pressed.connect(_on_host)
	_host_button.toggled.connect(func(on: bool) -> void: (_host_box.get_parent() as Control).visible = on)

	_join_button = _button(column, "Join a colony")
	_join_button.toggle_mode = true
	_join_box = _sub_box(column)
	_join_box.add_child(_label(JOIN_HELP, UiTheme.MUTED))
	_join_box.add_child(_label("Host address"))
	_join_address = _field(_join_box, "", "for example 192.168.1.20")
	_join_box.add_child(_label("Port"))
	_join_port = _field(_join_box, str(NetSession.DEFAULT_PORT), "")
	_join_start = _button(_join_box, "Join", UiTheme.PRIMARY_BUTTON)
	_join_start.pressed.connect(_on_join)
	_join_address.text_submitted.connect(func(_t: String) -> void: _on_join())
	_join_port.text_submitted.connect(func(_t: String) -> void: _on_join())
	_join_button.toggled.connect(func(on: bool) -> void: (_join_box.get_parent() as Control).visible = on)

	_settings_button = _button(column, "Settings")
	_settings_button.pressed.connect(func() -> void: open_requested.emit(SettingsPanel.new()))
	_sources_button = _button(column, "Sources and credits")
	_sources_button.pressed.connect(func() -> void: open_requested.emit(CreditsPanel.new()))
	_quit_button = _button(column, "Quit")
	_quit_button.pressed.connect(func() -> void: quit_pressed.emit())
	_notice = _label("", UiTheme.WARN)
	_notice.visible = false
	column.add_child(_notice)
	var keys := _label("Arrow keys or mouse to choose. Enter to select.", UiTheme.MUTED)
	keys.name = "KeyHelp"
	outer.add_child(keys)
	refresh_save_info()


func panel_title() -> String:
	return "Main menu"


## Reads the save file again for the Continue button ("Sol N, saved <date>").
func refresh_save_info() -> void:
	var has_save := services != null and services.saves != null and services.saves.has_save()
	_continue_button.disabled = not has_save
	_host_continue.disabled = not has_save
	_host_continue.button_pressed = has_save
	_continue_info.text = save_summary() if has_save else "No saved colony yet."


## "Sol N, saved 12 Nov 2026 at 14:05" for the newest usable save, or a plain line when it cannot be read.
func save_summary() -> String:
	var result := services.saves.read()
	if not result.is_usable():
		return "The saved colony could not be read."
	var clock: Dictionary = result.payload.get("clock", {})
	var sol := int(clock.get("sol_index", 0)) + 1
	var saved_at := -1
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(result.source_path))
	if data is Dictionary:
		saved_at = int((data as Dictionary).get("saved_at_unix", -1))
	if saved_at < 0:
		return "Sol %d" % sol
	return "Sol %d, saved %s" % [sol, _date_text(saved_at)]


## Shows a plain message on the menu (for example "Playing together arrives in a later update.").
func show_notice(text: String) -> void:
	_notice.text = text
	_notice.visible = text != ""


## The notice on show, or "".
func notice_text() -> String:
	return _notice.text if _notice.visible else ""


## Opens the join section and returns its address field (tests and the integrator use it).
func open_join_section() -> LineEdit:
	_join_button.button_pressed = true
	return _join_address


## Opens the host section.
func open_host_section() -> void:
	_host_button.button_pressed = true


func first_focus() -> Control:
	return _new_button if _continue_button.disabled else _continue_button


## The title screen stays until a game is running.
func can_close() -> bool:
	return services != null and services.has_game()


func _on_host() -> void:
	var port := _port_of(_host_port)
	if port < 0:
		return
	show_notice("")
	host_pressed.emit(port, _host_continue.button_pressed and not _host_continue.disabled)


func _on_join() -> void:
	var address := _join_address.text.strip_edges()
	if address == "":
		show_notice("Type the host's address first.")
		_join_address.grab_focus()
		return
	var port := _port_of(_join_port)
	if port < 0:
		return
	show_notice("")
	join_pressed.emit(address, port)


func _port_of(edit: LineEdit) -> int:
	var text := edit.text.strip_edges()
	if text.is_valid_int() and int(text) >= 1024 and int(text) <= 65535:
		return int(text)
	show_notice("The port is a number from 1024 to 65535.")
	edit.grab_focus()
	return -1


static func _date_text(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%d %s %d at %02d:%02d" % [int(d.day), months[clampi(int(d.month) - 1, 0, 11)], int(d.year), int(d.hour), int(d.minute)]


# ---------------------------------------------------------------- building helpers

static func _label(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func _button(parent: Control, text: String, variation: StringName = &"") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 52.0
	parent.add_child(b)
	return b


static func _sub_box(parent: Control) -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = UiTheme.CARD
	parent.add_child(card)
	var box := VBoxContainer.new()
	card.add_child(box)
	card.visible = false
	return box


static func _field(parent: Control, text: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	parent.add_child(e)
	return e


## The title picture, drawn with plain shapes (no image file to ship or credit): a night sky going to dusty orange at
## the horizon, a small pale sun, far ridges, the ground, and the colony's domes with lit windows. It covers the whole
## screen, also outside this panel's own box, and is darker on the left so the menu text stays easy to read.
func _draw() -> void:
	var screen := Rect2(-global_position, get_viewport_rect().size)
	var o := screen.position
	var w := screen.size.x
	var h := screen.size.y
	var horizon := o.y + h * 0.7
	var sky_h := horizon - o.y
	var hc := UiTheme.is_high_contrast()
	if hc:
		draw_rect(screen, Color(0, 0, 0))
		draw_line(Vector2(o.x, horizon), Vector2(o.x + w, horizon), Color(1, 1, 1), 2.0)
		return
	_fade_v(Rect2(o.x, o.y, w, sky_h * 0.55), Color(0.025, 0.035, 0.08), Color(0.13, 0.1, 0.14))
	_fade_v(Rect2(o.x, o.y + sky_h * 0.55, w, sky_h * 0.45), Color(0.13, 0.1, 0.14), Color(0.66, 0.38, 0.2))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2031
	for i in 150:
		var at := Vector2(o.x + rng.randf() * w, o.y + rng.randf() * sky_h * 0.8)
		var high := 1.0 - (at.y - o.y) / (sky_h * 0.8)
		draw_circle(at, rng.randf_range(0.8, 2.1), Color(1, 1, 1, (0.12 + 0.6 * rng.randf()) * high))
	# the sun looks small from Mars; its glow at dusk is pale and cool
	var sun := Vector2(o.x + w * 0.74, horizon - h * 0.085)
	for i in 40:
		var t := float(i) / 39.0          # many thin layers, so the glow has no visible rings
		draw_circle(sun, h * lerpf(0.24, 0.022, sqrt(t)), Color(0.6, 0.74, 0.96, 0.012))
	draw_circle(sun, h * 0.019, Color(0.94, 0.97, 1.0))
	# far ridges, then the ground
	_ridge(o, w, horizon, h * 0.06, 0.0045, Color(0.36, 0.2, 0.13))
	_ridge(o, w, horizon, h * 0.03, 0.011, Color(0.25, 0.135, 0.09))
	_fade_v(Rect2(o.x, horizon, w, o.y + h - horizon), Color(0.21, 0.115, 0.075), Color(0.07, 0.04, 0.035))
	draw_line(Vector2(o.x, horizon), Vector2(o.x + w, horizon), Color(0.95, 0.6, 0.35, 0.25), 2.0)
	# the colony on the horizon: domes, a hall between them, a mast
	var base := horizon + h * 0.012
	var dark := Color(0.05, 0.045, 0.055)
	var lit := Color(1.0, 0.78, 0.45)
	var unit := h * 0.01
	_dome(Vector2(o.x + w * 0.6, base), unit * 9.0, dark, lit, 5)
	_dome(Vector2(o.x + w * 0.69, base), unit * 5.5, dark, lit, 3)
	_dome(Vector2(o.x + w * 0.86, base), unit * 7.0, dark, lit, 4)
	draw_rect(Rect2(o.x + w * 0.6, base - unit * 3.0, w * 0.26, unit * 3.0), dark)
	for i in 9:
		draw_rect(Rect2(o.x + w * 0.635 + i * w * 0.024, base - unit * 2.0, unit * 1.4, unit * 0.7), Color(lit, 0.85))
	var mast := Vector2(o.x + w * 0.785, base - unit * 3.0)
	draw_line(mast, mast - Vector2(0, unit * 9.0), dark, maxf(2.0, unit * 0.35))
	draw_circle(mast - Vector2(0, unit * 9.0), maxf(2.0, unit * 0.45), Color(1.0, 0.35, 0.3))
	# shade behind the menu column
	var shade := Color(0.015, 0.02, 0.035)
	draw_rect(Rect2(o.x, o.y, w * 0.22, h), Color(shade, 0.8))
	draw_polygon(PackedVector2Array([Vector2(o.x + w * 0.22, o.y), Vector2(o.x + w * 0.56, o.y), Vector2(o.x + w * 0.56, o.y + h), Vector2(o.x + w * 0.22, o.y + h)]),
		PackedColorArray([Color(shade, 0.8), Color(shade, 0.0), Color(shade, 0.0), Color(shade, 0.8)]))
	# accent rule under the title screen's left edge, like the line on every other panel
	draw_rect(Rect2(o.x, o.y, w, 4.0), UiTheme.palette().accent)


## A rectangle that fades from `top` to `bottom`.
func _fade_v(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]),
		PackedColorArray([top, top, bottom, bottom]))


## A line of low hills along the horizon. `height` is the tallest hill, `wave` how tightly they are packed.
func _ridge(o: Vector2, w: float, horizon: float, height: float, wave: float, color: Color) -> void:
	var pts := PackedVector2Array([Vector2(o.x, horizon + 2.0)])
	var steps := 96
	for i in steps + 1:
		var x := w * float(i) / float(steps)
		var n := 0.5 + 0.28 * sin(x * wave) + 0.16 * sin(x * wave * 2.7 + 1.3) + 0.06 * sin(x * wave * 6.1 + 4.0)
		pts.append(Vector2(o.x + x, horizon - height * clampf(n, 0.0, 1.0)))
	pts.append(Vector2(o.x + w, horizon + 2.0))
	draw_colored_polygon(pts, color)


## Half a ball standing on `foot` (its middle on the ground), with a row of lit windows.
func _dome(foot: Vector2, radius: float, color: Color, lit: Color, windows: int) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := PI + PI * float(i) / 32.0
		pts.append(foot + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(pts, color)
	for i in windows:
		var x := (float(i) - float(windows - 1) * 0.5) * radius * 1.3 / float(maxi(windows, 1))
		draw_circle(foot + Vector2(x, -radius * 0.32), maxf(1.5, radius * 0.06), Color(lit, 0.9))
