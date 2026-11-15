class_name MainMenu
extends UiPanel
## The title screen (layout and flow from Uday's UI rebuild, drawn in the game's own theme): animated colony beauty
## shots, the ring emblem with the game's name, and the menu in a column on the left:
## continue, start a new colony, host or join on the local network, settings, sources, quit.
## It only emits signals; the game decides what each one does. show_notice() puts a plain message on the menu.

signal continue_pressed
signal new_game_pressed
signal host_pressed(port: int, continue_save: bool)
signal join_pressed(address: String, port: int)
signal quit_pressed

const BACKDROP_SCRIPT = preload("res://scripts/ui/menu_backdrop.gd")
const Kit = preload("res://scripts/ui/menu_kit.gd")
## Pictogram for each navigation entry, in the order of _nav_buttons.
const NAV_ICONS: Array[StringName] = [&"plus", &"play", &"host", &"join", &"gear", &"star", &"exit"]
var _emblem: MenuTitleEmblem
var _workspace: HBoxContainer
var _canvas: Control
var _footer: HBoxContainer
var _nav_buttons: Array[Button] = []
var _selected_nav: Button
var _suppress_preview := false
var _session_scroll: ScrollContainer
var _nav_scroll: ScrollContainer
var _backdrop: Control

const JOIN_HELP := "Use the host’s address. Both players must be on the same network."
## Width of the menu column on the left, in screen units.

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
## Open games found on the network (LanDiscovery), one Join button each.
var _server_list: VBoxContainer
var _server_status: Label
var _manual_toggle: Button
var _manual_box: VBoxContainer
var _games_tab: Button
var _games_box: VBoxContainer
var _browser := LanDiscovery.Browser.new()
var _browser_failed := false
const SEARCHING_TEXT := "Looking for games on your network… Ask a friend to choose Host a game."
var _settings_button: Button
var _sources_button: Button
var _quit_button: Button
var _replacement_confirmed := false
var _load_box: VBoxContainer
var _settings_box: VBoxContainer
var _credits_box: VBoxContainer
var _quit_box: VBoxContainer
var _load_summary: Label
var _new_confirm: VBoxContainer
var _notice: Label


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	name = "MainMenu"
	keeps_world_visible = false
	UiComposition.bare(self, 0)
	_backdrop = BACKDROP_SCRIPT.new()
	_backdrop.name = "BeautyBackdrop"
	add_child(_backdrop)
	_canvas = Control.new()
	_canvas.name = "TitleComposition"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_emblem = MenuTitleEmblem.new()
	_emblem.name = "TitleEmblem"
	_canvas.add_child(_emblem)
	_workspace = HBoxContainer.new()
	_workspace.name = "MenuWorkspace"
	_workspace.add_theme_constant_override(&"separation", UiLayoutMetrics.SECTION_GAP)
	_canvas.add_child(_workspace)
	_nav_scroll = ScrollContainer.new()
	_nav_scroll.name = "Navigation"
	_nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_nav_scroll.follow_focus = true
	_workspace.add_child(_nav_scroll)
	var nav := VBoxContainer.new()
	nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_theme_constant_override(&"separation", 8)
	nav.set_meta(&"layout_metrics_exempt", true)
	_nav_scroll.add_child(nav)
	_new_button = _nav_button(nav, "New colony", NAV_ICONS[0])
	_continue_button = _nav_button(nav, "Continue", NAV_ICONS[1])
	_host_button = _nav_button(nav, "Host a game", NAV_ICONS[2])
	_join_button = _nav_button(nav, "Join a game", NAV_ICONS[3])
	_settings_button = _nav_button(nav, "Settings", NAV_ICONS[4])
	_sources_button = _nav_button(nav, "Credits", NAV_ICONS[5])
	_quit_button = _nav_button(nav, "Quit", NAV_ICONS[6])
	_nav_buttons.assign([_new_button, _continue_button, _host_button, _join_button, _settings_button, _sources_button, _quit_button])
	for button in _nav_buttons:
		button.pressed.connect(_show_nav_fields.bind(button))
		button.focus_entered.connect(func() -> void: _selected_nav = button)
		button.gui_input.connect(_nav_input.bind(button))

	_session_scroll = ScrollContainer.new()
	_session_scroll.name = "SessionSetup"
	_session_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_session_scroll.follow_focus = true
	_workspace.add_child(_session_scroll)
	var session := VBoxContainer.new()
	session.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_session_scroll.add_child(session)
	_new_confirm = _sub_box(session)
	_new_confirm.add_child(_label("Begin a new colony?", UiTheme.HEADING))
	_new_confirm.add_child(_label("The next save will replace your current colony.", UiTheme.WARN))
	_button(_new_confirm, "Start new colony", UiTheme.DANGER_BUTTON).pressed.connect(func() -> void:
		_replacement_confirmed = true
		new_game_pressed.emit())
	_button(_new_confirm, "Keep current colony").pressed.connect(func() -> void:
		_close_form(_new_button))
	_host_box = _sub_box(session)
	_host_box.name = "HostSetup"
	_host_box.add_child(_label("Host a game on your network", UiTheme.HEADING))
	_host_box.add_child(_label("Players must share your local network.", UiTheme.MUTED))
	_host_box.add_child(_label("Port"))
	_host_port = _field(_host_box, str(NetSession.DEFAULT_PORT), "")
	_host_continue = CheckBox.new()
	_host_continue.text = "Continue saved colony"
	_host_box.add_child(_host_continue)
	_host_start = _button(_host_box, "Start hosting", UiTheme.PRIMARY_BUTTON)
	_host_start.pressed.connect(_on_host)
	_join_box = _sub_box(session)
	_join_box.name = "JoinSetup"
	_join_box.add_child(_label("Join a game on your network", UiTheme.HEADING))
	# Two tabs: "Open games" (default, found on the network) and "Type an address" (the original manual form).
	var tabs := HBoxContainer.new()
	tabs.name = "JoinTabs"
	tabs.add_theme_constant_override(&"separation", 8)
	_join_box.add_child(tabs)
	_games_tab = _button(tabs, "Open games")
	_games_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_games_tab.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_games_tab.pressed.connect(_set_manual_visible.bind(false))
	_manual_toggle = _button(tabs, "Type an address")
	_manual_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_manual_toggle.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_manual_toggle.pressed.connect(_set_manual_visible.bind(true))
	_games_box = VBoxContainer.new()
	_games_box.name = "OpenGamesTab"
	_join_box.add_child(_games_box)
	_server_list = VBoxContainer.new()
	_server_list.name = "OpenGames"
	_games_box.add_child(_server_list)
	_server_status = _label(SEARCHING_TEXT, UiTheme.MUTED)
	_games_box.add_child(_server_status)
	_manual_box = VBoxContainer.new()
	_manual_box.name = "ManualAddress"
	_manual_box.visible = false
	_join_box.add_child(_manual_box)
	_manual_box.add_child(_label(JOIN_HELP, UiTheme.MUTED))
	_manual_box.add_child(_label("Host address"))
	_join_address = _field(_manual_box, "", "192.168.1.20")
	_manual_box.add_child(_label("Port"))
	_join_port = _field(_manual_box, str(NetSession.DEFAULT_PORT), "")
	_join_start = _button(_manual_box, "Connect", UiTheme.PRIMARY_BUTTON)
	_set_manual_visible(false)
	_join_start.pressed.connect(_on_join)
	_join_address.text_submitted.connect(func(_t: String) -> void: _on_join())
	_join_port.text_submitted.connect(func(_t: String) -> void: _on_join())
	_load_box = _sub_box(session)
	_load_box.add_child(_label("Your saved colony", UiTheme.HEADING))
	_load_summary = _label("")
	_load_box.add_child(_load_summary)
	_button(_load_box, "Continue colony", UiTheme.PRIMARY_BUTTON).pressed.connect(func() -> void: continue_pressed.emit())
	_settings_box = _sub_box(session)
	_settings_box.add_child(_label("Settings", UiTheme.HEADING))
	for i in 4:
		_button(_settings_box, ["Display & accessibility", "Controls & key bindings", "Graphics", "Audio"][i]).pressed.connect(_open_settings_category.bind(i))
	_credits_box = _sub_box(session)
	_credits_box.add_child(_label("Credits and sources", UiTheme.HEADING))
	_button(_credits_box, "Scientific sources").pressed.connect(func() -> void: open_requested.emit(SourceRegisterPanel.new()))
	_button(_credits_box, "Credits").pressed.connect(func() -> void: open_requested.emit(CreditsPanel.new()))
	_quit_box = _sub_box(session)
	_quit_box.add_child(_label("Quit the game?", UiTheme.HEADING))
	_button(_quit_box, "Quit game", UiTheme.DANGER_BUTTON).pressed.connect(func() -> void: quit_pressed.emit())
	_continue_info = _label("", UiTheme.MUTED)
	_continue_info.name = "SaveSummary"
	_canvas.add_child(_continue_info)
	_notice = _label("", UiTheme.WARN)
	_notice.name = "Notice"
	_notice.visible = false
	_canvas.add_child(_notice)
	_footer = Kit.key_hint(["pic:up", "pic:down", "Choose", "key:Enter", "Select", "key:Esc", "Back"])
	_footer.name = "InputHints"
	_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	_canvas.add_child(_footer)
	refresh_save_info()
	_selected_nav = first_focus() as Button
	_process(0)


func panel_title() -> String:
	return "Main menu"


## Reads the save file again for the Continue button ("Sol N, saved <date>").
func refresh_save_info() -> void:
	var has_save := services != null and services.saves != null and services.saves.has_save()
	_continue_button.disabled = not has_save
	(_new_confirm.get_child(1) as Control).visible = has_save
	_host_continue.disabled = not has_save
	_host_continue.button_pressed = has_save
	if _load_summary != null: _load_summary.text = save_summary() if has_save else "No saved colony."
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
	_show_nav_fields(_join_button)
	_set_manual_visible(true)
	return _join_address


## The Join buttons for the open games on show (tests use it).
func open_game_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c in _server_list.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _exit_tree() -> void:
	_browser.stop()


## Switches the Join form between its tabs: the typed-address form (`on`) or the open games list.
func _set_manual_visible(on: bool) -> void:
	_manual_box.visible = on
	_games_box.visible = not on
	_manual_toggle.theme_type_variation = UiTheme.PRIMARY_BUTTON if on else &""
	_games_tab.theme_type_variation = &"" if on else UiTheme.PRIMARY_BUTTON


## Listens for hosts while the Join form is on show, and rebuilds the list when it changes.
func _update_browser() -> void:
	var showing := is_visible_in_tree() and _join_box != null and (_join_box.get_parent() as Control).visible \
		and not (services != null and services.has_game())
	if not showing:
		if _browser.is_running():
			_browser.stop()
			_rebuild_server_list()
		_browser_failed = false
		return
	if not _browser.is_running():
		if _browser_failed:
			return
		if not _browser.start():
			_browser_failed = true
			_server_status.text = "Could not look for games (another copy of the game may be open on this computer). Use the Type an address tab instead."
			return
		_rebuild_server_list()
	if _browser.poll():
		_rebuild_server_list()


func _rebuild_server_list() -> void:
	var had_focus := _server_list.get_viewport() != null and _server_list.is_ancestor_of(_server_list.get_viewport().gui_get_focus_owner())
	for c in _server_list.get_children():
		_server_list.remove_child(c)
		c.queue_free()
	var games := _browser.servers()
	for g: Dictionary in games:
		var full := int(g.players) >= int(g.max)
		var b := _button(_server_list, "Join %s   (%d/%d players)" % [g.name, int(g.players), int(g.max)],
			UiTheme.PRIMARY_BUTTON)
		b.name = "JoinGame"
		b.tooltip_text = "%s, port %d" % [g.address, int(g.port)]
		if not g.same_version:
			b.disabled = true
			b.text = "%s has a different version of the game" % g.name
		elif full:
			b.disabled = true
			b.text = "%s is full (%d/%d players)" % [g.name, int(g.players), int(g.max)]
		var address := String(g.address)
		var port := int(g.port)
		b.pressed.connect(func() -> void:
			show_notice("")
			join_pressed.emit(address, port))
	if not _browser_failed:
		_server_status.text = SEARCHING_TEXT if games.is_empty() else "Click a game to join it."
	if had_focus and _server_list.get_child_count() > 0:
		(_server_list.get_child(0) as Control).grab_focus()


## Opens the host section.
func open_host_section() -> void:
	_show_nav_fields(_host_button)


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
	var card := MenuFormFrame.new()
	card.theme_type_variation = UiTheme.PANEL
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


## Composition follows the supplied 1920×1080 reference; native controls scroll when text grows.
func _process(_delta: float) -> void:
	if _canvas == null: return
	_update_browser()
	var viewport := get_viewport_rect().size if is_inside_tree() else Vector2(1920, 1080)
	var available := size if size.x > 100 and size.y > 100 else viewport
	var scale := clampf(viewport.y / 1080.0, 0.75, 1.35)
	var text_scale := UiTheme.text_scale()
	var configuring := _has_form()
	var nav_width := minf(available.x * 0.3, maxf(300 * scale, 300 * text_scale))
	_workspace.position = Vector2(available.x * 0.01, available.y * 0.33)
	_workspace.size = Vector2(available.x * 0.97, available.y * 0.50)
	_nav_scroll.custom_minimum_size.x = nav_width
	# One navigation rail and one active form. The emblem has a separate, non-overlapping region.
	if configuring:
		_emblem.position = Vector2(available.x * 0.37, 0)
		_emblem.size = Vector2(available.x * 0.60, available.y * 0.29)
	else:
		_emblem.position = Vector2(0, available.y * 0.30)
		_emblem.size = Vector2(available.x * 0.60, available.y * 0.40)
	var form_left := _workspace.position.x + nav_width + UiLayoutMetrics.SECTION_GAP
	var form_width := minf(820 * text_scale, available.x - form_left - 24)
	_session_scroll.custom_minimum_size.x = form_width
	if configuring:
		_emblem.position.x = form_left
		_emblem.size.x = form_width
	# The brand always stays on the screen’s horizontal centreline.
	_emblem.position.x = (available.x - _emblem.size.x) * 0.5
	_emblem.configuring = false
	_emblem.text_scale = minf(text_scale, 1.25)
	_emblem.queue_redraw()
	for button in _nav_buttons:
		button.add_theme_font_size_override(&"font_size", roundi(24 * text_scale))
		button.custom_minimum_size.y = 52 * text_scale
		var selected := button == _selected_nav
		var style: StyleBox = button.get_meta(&"menu_selected_style" if selected else &"menu_normal_style")
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			button.add_theme_stylebox_override(state, style)
		var ink: Color = UiTheme.palette().primary_text if selected else UiTheme.palette().text
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, ink)
		var icon_ink: StringName = &"primary_text" if selected else &"text"
		if button.get_meta(&"icon_ink", &"") != icon_ink:
			button.set_meta(&"icon_ink", icon_ink)
			button.icon = Kit.pic(button.get_meta(&"icon_kind"), 26.0, icon_ink)
	_footer.position = Vector2(0, maxf(0, available.y - _footer.get_combined_minimum_size().y - 12))
	_footer.size = Vector2(available.x, 40)
	_continue_info.add_theme_font_size_override(&"font_size", roundi(18 * text_scale))
	_continue_info.visible = not _continue_button.disabled
	var save_left := available.x * 0.01
	var footer_left := (available.x - _footer.get_combined_minimum_size().x) * 0.5
	_continue_info.size = Vector2(minf(available.x * 0.29, maxf(140, footer_left - save_left - 24)), 0)
	_continue_info.position = Vector2(save_left, maxf(0, available.y - _continue_info.get_combined_minimum_size().y - 12))
	_notice.position = Vector2(available.x * 0.36, _footer.position.y - _notice.get_combined_minimum_size().y - 14)
	_notice.size = Vector2(available.x * 0.61, available.y * 0.05)
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


func _request_new_colony() -> void:
	_show_nav_fields(_new_button)


## The explicit replacement action already showed the saved-colony consequence.
func new_colony_confirmed() -> bool:
	return _replacement_confirmed


## A navigation entry: our menu-kit button (pictogram and word). _process() swaps its look between the plain
## button and the orange primary button as the selection moves.
static func _nav_button(parent: Control, text: String, kind: StringName) -> Button:
	var button := Kit.button(text, kind, &"", 26.0, 1.0, 52.0)
	button.set_meta(&"layout_metrics_exempt", true)
	button.set_meta(&"icon_kind", kind)
	var theme := UiTheme.get_theme()
	var normal := theme.get_stylebox(&"normal", &"Button")
	var selected := theme.get_stylebox(&"normal", UiTheme.PRIMARY_BUTTON)
	for state in ["normal", "disabled"]:
		button.add_theme_stylebox_override(state, normal)
	button.set_meta(&"menu_normal_style", normal)
	button.set_meta(&"menu_selected_style", selected)
	button.add_theme_color_override(&"font_disabled_color", UiTheme.palette().text_disabled)
	parent.add_child(button)
	return button


func _nav_input(event: InputEvent, button: Button) -> void:
	if not event is InputEventKey or not event.pressed: return
	var key := event as InputEventKey
	if key.keycode in [KEY_UP, KEY_DOWN]:
		var direction := -1 if key.keycode == KEY_UP else 1
		var index := _nav_buttons.find(button)
		for step in range(1, _nav_buttons.size() + 1):
			var next := _nav_buttons[posmod(index + direction * step, _nav_buttons.size())]
			if not next.disabled:
				next.grab_focus()
				_show_nav_fields(next)
				break
		button.accept_event()
	elif key.keycode in [KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER]:
		_show_nav_fields(button)
		var focus := _active_form_focus()
		if focus != null: focus.grab_focus()
		button.accept_event()

func _forms() -> Array:
	return [_new_confirm, _load_box, _host_box, _join_box, _settings_box, _credits_box, _quit_box]

func _has_form() -> bool:
	for box in _forms():
		if is_instance_valid(box) and (box.get_parent() as Control).visible: return true
	return false

func _active_form_focus() -> Control:
	for box in _forms():
		if (box.get_parent() as Control).visible: return _first_focusable(box)
	return null

func _show_nav_fields(button: Button) -> void:
	if _suppress_preview: return
	_selected_nav = button
	if _quit_box == null: return
	for box in _forms(): (box.get_parent() as Control).hide()
	var index := _nav_buttons.find(button)
	if index >= 0:
		(_forms()[index].get_parent() as Control).show()
	_session_scroll.scroll_vertical = 0
	_replacement_confirmed = false
	_process(0)

func _open_settings_category(index: int) -> void:
	var settings := SettingsPanel.new()
	open_requested.emit(settings)
	if settings.tabs() != null:
		settings.tabs().set_deferred("current_tab", index)

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not _has_form(): return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_form(_selected_nav)
		get_viewport().set_input_as_handled()

func _close_form(return_to: Button) -> void:
	for box in _forms(): (box.get_parent() as Control).hide()
	_suppress_preview = true
	if is_instance_valid(return_to): return_to.grab_focus()
	_suppress_preview = false


func _input(event: InputEvent) -> void:
	# Escape returns from a form even while a text field owns GUI focus.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_unhandled_key_input(event)
