class_name PauseMenu
extends UiPanel
## The pause menu. Opening it asks the host to pause (vote_pause true); closing it takes the vote back.
## Solo: the game pauses at once. Co-op: everyone has to agree, and the menu shows how many do.
## The host also gets "Save now" and the sol length slider.

## "Quit to menu" was pressed (UiRoot passes it on as quit_to_menu_requested).
signal quit_to_menu_pressed

var _vote_label: Label
var _status: Label
## "Hosting on 192.168.1.20:24680, 2 players": the address others type to join. Hidden when playing alone.
var _net_label: Label
var _save_button: Button
var _sol_slider: HSlider
var _sol_label: Label
var _dragging := false
var _sol_dirty := false
var _voted := false


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	name = "PauseMenu"
	theme_type_variation = UiTheme.PANEL
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var outer := VBoxContainer.new()
	add_child(outer)
	var title := Label.new()
	title.text = "Paused"
	title.theme_type_variation = UiTheme.TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)
	_vote_label = _wrap_label("", UiTheme.MUTED)
	_vote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(_vote_label)
	_net_label = _wrap_label("", UiTheme.MUTED)
	_net_label.name = "Network"
	_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(_net_label)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	outer.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var grid := GridContainer.new()
	grid.columns = 2
	column.add_child(grid)
	_add(grid, "Resume", func() -> void: close_requested.emit(), UiTheme.PRIMARY_BUTTON)
	_add(grid, "Colony summary", func() -> void: open_requested.emit(ColonySummaryPanel.new()))
	_add(grid, "Crew", func() -> void: open_requested.emit(CrewSelectPanel.new()))
	_add(grid, "Settings", func() -> void: open_requested.emit(SettingsPanel.new()))
	_add(grid, "Sources", func() -> void: open_requested.emit(SourceRegisterPanel.new()))
	_add(grid, "Credits", func() -> void: open_requested.emit(CreditsPanel.new()))
	if _is_host():
		_save_button = _add(grid, "Save now", _on_save)
	_add(grid, "Quit to menu", func() -> void: quit_to_menu_pressed.emit())
	_add(grid, "Quit game", func() -> void: services.quit_game(), UiTheme.DANGER_BUTTON)
	_status = _wrap_label("", UiTheme.MUTED)
	_status.visible = false
	column.add_child(_status)
	if _is_host():
		_build_sol_setting(column)
	refresh()


func panel_title() -> String:
	return "Pause"


## Plain words for the pause state: solo, co-op host (with counts) or client.
func vote_text() -> String:
	if services == null or not services.has_game():
		return ""
	var session := services.session
	var players := session.peers.size()
	if players <= 1:
		return "The colony is paused. Take your time." if session.paused else "Pausing…"
	if session.paused:
		return "Paused: all %d players agreed." % players
	var yes := session.pause_votes()
	return "%d of %d players want to pause. Waiting for everyone to agree." % [yes, players]


## The sol length slider, or null when this machine is not the host.
func sol_slider() -> HSlider:
	return _sol_slider


func refresh() -> void:
	if _vote_label == null:
		return
	_vote_label.text = vote_text()
	var online := services != null and services.net != null and services.net.is_online()
	_net_label.visible = online
	if online:
		_net_label.text = services.net.status_text()
	if _sol_slider != null and not _dragging and not _sol_dirty and services.has_game():
		_sol_slider.set_value_no_signal(services.clock().sol_minutes)
		_update_sol_label(_sol_slider.value)


func _enter_tree() -> void:
	if not _voted and services != null and services.has_game():
		_voted = true
		services.request(&"vote_pause", &"", {"paused": true})


func _exit_tree() -> void:
	if _voted and services != null and services.has_game():
		_voted = false
		services.request(&"vote_pause", &"", {"paused": false})


func _process(_delta: float) -> void:
	# One request per change: a keyboard step sends at once; a drag sends once when it is let go.
	if _sol_dirty and not _dragging:
		_sol_dirty = false
		_send_sol(_sol_slider.value)


func _is_host() -> bool:
	return services != null and services.is_authority()


func _build_sol_setting(parent: Control) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = UiTheme.CARD
	parent.add_child(card)
	var box := VBoxContainer.new()
	card.add_child(box)
	var heading := Label.new()
	heading.text = "Length of a sol (host only)"
	heading.theme_type_variation = UiTheme.HEADING
	box.add_child(heading)
	_sol_label = _wrap_label("")
	box.add_child(_sol_label)
	_sol_slider = HSlider.new()
	_sol_slider.min_value = 5.0
	_sol_slider.max_value = 120.0
	_sol_slider.step = 1.0
	_sol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sol_slider.value = services.clock().sol_minutes if services.has_game() else 20.0
	_sol_slider.value_changed.connect(func(v: float) -> void:
		_update_sol_label(v)
		_sol_dirty = true)
	_sol_slider.drag_started.connect(func() -> void: _dragging = true)
	_sol_slider.drag_ended.connect(func(_changed: bool) -> void: _dragging = false)
	box.add_child(_sol_slider)
	box.add_child(_wrap_label("The time of day stays where it is when you change this. Only the speed of the day changes.", UiTheme.MUTED))
	_update_sol_label(_sol_slider.value)


func _update_sol_label(minutes: float) -> void:
	if _sol_label != null:
		_sol_label.text = "One sol (Mars day) lasts %d real minutes" % roundi(minutes)


func _send_sol(minutes: float) -> void:
	if not services.has_game() or is_equal_approx(minutes, services.clock().sol_minutes):
		return
	var r := services.request(&"set_sol_minutes", &"", {"minutes": minutes})
	if not r.ok and not r.pending:
		_show_status(r.message)


func _on_save() -> void:
	var err := services.save_now(&"manual")
	_show_status("Saved ✓" if err == OK else "! Could not save. Your last save is still there.")


func _show_status(text: String) -> void:
	_status.text = text
	_status.visible = text != ""


func _add(parent: Control, text: String, action: Callable, variation: StringName = &"") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	parent.add_child(b)
	return b


static func _wrap_label(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
