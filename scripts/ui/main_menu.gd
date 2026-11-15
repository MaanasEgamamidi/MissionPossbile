class_name MainMenu
extends UiPanel
## The title screen: animated colony beauty shots with the game's name and the menu in a column on the left.
## One big "Play" (continues the saved colony when there is one, otherwise starts a new colony; with a save there is
## also a smaller "New colony"), "Play with friends" (a second page with two picture buttons: start a game for
## friends, or join a friend's game), and a small row of Settings, Credits and Quit. Nothing is shown disabled:
## what cannot be used is hidden.
## It only emits signals; the game decides what each one does. show_notice() puts a plain message on the menu.

signal continue_pressed
signal new_game_pressed
signal host_pressed(port: int, continue_save: bool)
signal join_pressed(address: String, port: int)
signal quit_pressed

const BACKDROP_SCRIPT = preload("res://scripts/ui/menu_backdrop.gd")
const Kit = preload("res://scripts/ui/menu_kit.gd")
var _backdrop: Control

const HOST_HELP := "Other players on the same Wi-Fi or network can join your colony."
const JOIN_HELP := "Ask the host for the address shown on their screen. You must be on the same network."
const PORT_HELP := "A number the other players also type. Leave it as it is unless joining does not work."
## Width of the menu column on the left, in screen units.
const SIDE_WIDTH := 560.0

var _home: VBoxContainer
var _play_button: Button
var _continue_info: Label
var _new_button: Button
var _friends_button: Button
var _friends_page: VBoxContainer
var _back_button: Button
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
var _has_save := false


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
	var tagline := _label("Keep your Mars base alive, together.", UiTheme.MUTED)
	tagline.name = "Tagline"
	outer.add_child(tagline)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	outer.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# room for the focus ring, which is drawn just outside a button
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 6)
	scroll.add_child(pad)
	var column := VBoxContainer.new()
	column.name = "Buttons"
	column.add_theme_constant_override(&"separation", 12)
	pad.add_child(column)

	_build_home(column)
	_build_friends(column)
	_notice = _label("", UiTheme.WARN)
	_notice.name = "Notice"
	_notice.visible = false
	column.add_child(_notice)
	# The small row sits at the bottom of the column when there is room, and scrolls with it when there is not.
	var spring := Control.new()
	spring.name = "Spring"
	spring.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spring)
	var small := HBoxContainer.new()
	small.name = "Small"
	small.add_theme_constant_override(&"separation", 10)
	column.add_child(small)
	_settings_button = _small(small, "Settings", &"gear", "Text size, keys, sound and graphics.")
	_settings_button.pressed.connect(func() -> void: open_requested.emit(SettingsPanel.new()))
	_sources_button = _small(small, "Credits", &"star", "Who made the game, and its science sources.")
	_sources_button.pressed.connect(func() -> void: open_requested.emit(CreditsPanel.new()))
	_quit_button = _small(small, "Quit", &"exit", "Close the game.")
	_quit_button.pressed.connect(func() -> void: quit_pressed.emit())
	var keys := Kit.key_hint(["pic:up", "pic:down", "Choose", "key:Enter", "Select"])
	keys.name = "KeyHelp"
	outer.add_child(keys)
	refresh_save_info()


func panel_title() -> String:
	return "Main menu"


## Reads the save file again: with a save, Play continues it (its sol and date are under the button) and
## "New colony" appears; without one, Play starts a new colony and nothing else is offered.
func refresh_save_info() -> void:
	_has_save = services != null and services.saves != null and services.saves.has_save()
	_play_button.tooltip_text = "Carry on with your colony." if _has_save else "Start a new colony."
	_continue_info.visible = _has_save
	_continue_info.text = save_summary() if _has_save else ""
	_new_button.visible = _has_save
	_host_continue.visible = _has_save
	_host_continue.button_pressed = _has_save


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


## Opens "Play with friends" at "Join a friend's game" and returns its address field (tests and the integrator use it).
func open_join_section() -> LineEdit:
	_show_friends(true)
	_join_button.button_pressed = true
	return _join_address


## Opens "Play with friends" at "Start a game for friends".
func open_host_section() -> void:
	_show_friends(true)
	_host_button.button_pressed = true


## True while the "Play with friends" page is showing.
func friends_page_open() -> bool:
	return _friends_page.visible


func first_focus() -> Control:
	return _back_button if _friends_page.visible else _play_button


## The title screen stays until a game is running.
func can_close() -> bool:
	return services != null and services.has_game()


func _on_play() -> void:
	if _has_save:
		continue_pressed.emit()
	else:
		new_game_pressed.emit()


func _on_host() -> void:
	var port := _port_of(_host_port)
	if port < 0:
		return
	show_notice("")
	host_pressed.emit(port, _host_continue.button_pressed and _has_save)


func _on_join() -> void:
	var address := _join_address.text.strip_edges()
	if address == "":
		show_notice("Type your friend's address first.")
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


## Switches between the first page (Play) and the "Play with friends" page, and moves keyboard focus with it.
func _show_friends(on: bool) -> void:
	if _friends_page.visible == on:
		return
	_home.visible = not on
	_friends_page.visible = on
	var target: Control = _back_button if on else _friends_button
	if target.is_visible_in_tree():
		target.grab_focus()


## Esc on the "Play with friends" page goes back to the first page.
func _unhandled_input(event: InputEvent) -> void:
	if _friends_page != null and _friends_page.is_visible_in_tree() and event.is_action_pressed(&"back"):
		_show_friends(false)
		get_viewport().set_input_as_handled()


static func _date_text(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%d %s %d at %02d:%02d" % [int(d.day), months[clampi(int(d.month) - 1, 0, 11)], int(d.year), int(d.hour), int(d.minute)]


# ---------------------------------------------------------------- building

func _build_home(column: VBoxContainer) -> void:
	_home = VBoxContainer.new()
	_home.name = "Home"
	_home.add_theme_constant_override(&"separation", 12)
	column.add_child(_home)
	_play_button = Kit.button("Play", &"play", UiTheme.PRIMARY_BUTTON, 44.0, 1.8, 96.0)
	_play_button.name = "Play"
	_play_button.add_theme_constant_override(&"h_separation", 20)
	_play_button.pressed.connect(_on_play)
	_home.add_child(_play_button)
	_continue_info = _label("", UiTheme.MUTED)
	_continue_info.name = "SaveInfo"
	_home.add_child(_continue_info)
	_new_button = Kit.button("New colony", &"plus", &"", 24.0, 1.0, 52.0)
	_new_button.name = "NewColony"
	_new_button.tooltip_text = "Start again from the first day. Your saved colony is kept as a backup."
	_new_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_new_button.pressed.connect(func() -> void: new_game_pressed.emit())
	_home.add_child(_new_button)
	_friends_button = Kit.button("Play with friends", &"friends", &"", 34.0, 1.2, 68.0)
	_friends_button.name = "Friends"
	_friends_button.tooltip_text = "Start a game your friends can join, or join theirs."
	_friends_button.pressed.connect(_show_friends.bind(true))
	_home.add_child(_friends_button)


func _build_friends(column: VBoxContainer) -> void:
	_friends_page = VBoxContainer.new()
	_friends_page.name = "FriendsPage"
	_friends_page.add_theme_constant_override(&"separation", 12)
	_friends_page.visible = false
	column.add_child(_friends_page)
	var top := HBoxContainer.new()
	_friends_page.add_child(top)
	_back_button = Kit.button("Back", &"back", &"", 24.0, 1.0, 52.0)
	_back_button.name = "Back"
	_back_button.pressed.connect(_show_friends.bind(false))
	top.add_child(_back_button)
	var heading := _label("Play with friends", UiTheme.HEADING)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)

	var choice := HBoxContainer.new()
	choice.name = "Choice"
	choice.add_theme_constant_override(&"separation", 12)
	_friends_page.add_child(choice)
	var group := ButtonGroup.new()
	_host_button = _choice_tile(choice, "Start a game for friends", &"host", HOST_HELP, group)
	_host_button.name = "Host"
	_join_button = _choice_tile(choice, "Join a friend's game", &"join", JOIN_HELP, group)
	_join_button.name = "Join"

	_host_box = _sub_box(_friends_page)
	var host_row := HBoxContainer.new()
	_host_box.add_child(host_row)
	var host_port_label := _label("Port")
	host_port_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	host_port_label.tooltip_text = PORT_HELP
	host_port_label.mouse_filter = Control.MOUSE_FILTER_PASS
	host_row.add_child(host_port_label)
	_host_port = _field(host_row, str(NetSession.DEFAULT_PORT), "")
	_host_port.tooltip_text = PORT_HELP
	_host_continue = CheckBox.new()
	_host_continue.text = "Continue my saved colony"
	_host_continue.custom_minimum_size.y = 48.0
	_host_box.add_child(_host_continue)
	_host_start = Kit.button("Start hosting", &"play", UiTheme.PRIMARY_BUTTON, 28.0, 1.2, 64.0)
	_host_start.pressed.connect(_on_host)
	_host_box.add_child(_host_start)
	_host_button.toggled.connect(func(on: bool) -> void: (_host_box.get_parent() as Control).visible = on)

	_join_box = _sub_box(_friends_page)
	var join_grid := GridContainer.new()
	join_grid.columns = 2
	_join_box.add_child(join_grid)
	var address_label := _label("Address")
	address_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	address_label.tooltip_text = JOIN_HELP
	address_label.mouse_filter = Control.MOUSE_FILTER_PASS
	join_grid.add_child(address_label)
	_join_address = _field(join_grid, "", "for example 192.168.1.20")
	_join_address.tooltip_text = JOIN_HELP
	var join_port_label := _label("Port")
	join_port_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	join_port_label.tooltip_text = PORT_HELP
	join_port_label.mouse_filter = Control.MOUSE_FILTER_PASS
	join_grid.add_child(join_port_label)
	_join_port = _field(join_grid, str(NetSession.DEFAULT_PORT), "")
	_join_port.tooltip_text = PORT_HELP
	_join_box.add_child(_label("Your friend's screen shows the address.", UiTheme.MUTED))
	_join_start = Kit.button("Join", &"join", UiTheme.PRIMARY_BUTTON, 28.0, 1.2, 64.0)
	_join_start.pressed.connect(_on_join)
	_join_box.add_child(_join_start)
	_join_address.text_submitted.connect(func(_t: String) -> void: _on_join())
	_join_port.text_submitted.connect(func(_t: String) -> void: _on_join())
	_join_button.toggled.connect(func(on: bool) -> void: (_join_box.get_parent() as Control).visible = on)


static func _label(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## One of the two picture buttons of "Play with friends": picture on top, a few words under it; stays pressed while
## its form is open below.
static func _choice_tile(parent: Control, text: String, kind: StringName, tip: String, group: ButtonGroup) -> Button:
	var b := Kit.tile(text, kind, 64.0, Vector2(200, 150))
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.tooltip_text = tip
	b.toggle_mode = true
	b.button_group = group
	parent.add_child(b)
	return b


## A small icon + word button of the bottom row.
static func _small(parent: Control, text: String, kind: StringName, tip: String) -> Button:
	var b := Kit.button(text, kind, &"", 24.0, 1.0, 52.0)
	b.tooltip_text = tip
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	e.custom_minimum_size.y = 48.0
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(e)
	return e


## High contrast keeps the existing static black title screen.
func _process(_delta: float) -> void:
	var node := get_parent()
	while node != null and not (node is UiRoot):
		node = node.get_parent()
	var ui := node as UiRoot
	if ui != null and ui.settings != null:
		_backdrop.set("motion_enabled", not ui.settings.reduce_motion)
	var high_contrast := UiTheme.is_high_contrast()
	if _backdrop.visible == high_contrast:
		_backdrop.visible = not high_contrast
		queue_redraw()


func _draw() -> void:
	if UiTheme.is_high_contrast():
		draw_rect(Rect2(-global_position, get_viewport_rect().size), Color.BLACK)
