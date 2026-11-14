class_name MainMenu
extends UiPanel
## The title screen: animated colony beauty shots with the game's name and the menu in a column on the left:
## continue, start a new colony, host or join on the local network, settings, sources, quit.
## It only emits signals; the game decides what each one does. show_notice() puts a plain message on the menu.

signal continue_pressed
signal new_game_pressed
signal host_pressed(port: int, continue_save: bool)
signal join_pressed(address: String, port: int)
signal quit_pressed

const BACKDROP_SCRIPT = preload("res://scripts/ui/menu_backdrop.gd")
var _backdrop: Control

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
	_backdrop = BACKDROP_SCRIPT.new()
	_backdrop.name = "BeautyBackdrop"
	add_child(_backdrop)
	# No box of its own: the cinematic backdrop fills the screen behind the menu.
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


## High contrast keeps the existing static black title screen.
func _process(_delta: float) -> void:
	var ui := find_parent("UiRoot") as UiRoot
	if ui != null and ui.settings != null:
		_backdrop.set("motion_enabled", not ui.settings.reduce_motion)
	var high_contrast := UiTheme.is_high_contrast()
	if _backdrop.visible == high_contrast:
		_backdrop.visible = not high_contrast
		queue_redraw()


func _draw() -> void:
	if UiTheme.is_high_contrast():
		draw_rect(Rect2(-global_position, get_viewport_rect().size), Color.BLACK)
