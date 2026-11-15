class_name PauseMenu
extends UiPanel
## The pause menu. Opening it asks the host to pause (vote_pause true); closing it takes the vote back.
## Solo: the game pauses at once. Co-op: everyone has to agree, and the menu shows how many do.
## One big "Resume"; everything else is a smaller picture button under it. The host also gets "Save now" and the
## sol length slider.

## "Main menu" was pressed (UiRoot passes it on as quit_to_menu_requested).
signal quit_to_menu_pressed

const Kit = preload("res://scripts/ui/menu_kit.gd")
const SOL_HELP := "Host only. The time of day stays where it is when you change this. Only the speed of the day changes."

var _vote_label: Label
var _status: Label
## "Hosting on 192.168.1.20:24680, 2 players": the address others type to join. Hidden when playing alone.
var _net_label: Label
var _resume_button: Button
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
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 4)
	scroll.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	pad.add_child(column)
	_resume_button = Kit.button("Resume", &"play", UiTheme.PRIMARY_BUTTON, 40.0, 1.6, 88.0)
	_resume_button.name = "Resume"
	_resume_button.add_theme_constant_override(&"h_separation", 18)
	_resume_button.tooltip_text = "Back to the colony (Esc)."
	_resume_button.pressed.connect(func() -> void: close_requested.emit())
	column.add_child(_resume_button)
	var grid := GridContainer.new()
	grid.name = "More"
	grid.columns = 4
	column.add_child(grid)
	_add(grid, "Crew", &"crew", "See the crew and change who you play.", func() -> void: open_requested.emit(CrewSelectPanel.new()))
	_add(grid, "Colony", &"dome", "Colony summary: how the base is doing.", func() -> void: open_requested.emit(ColonySummaryPanel.new()))
	_add(grid, "Settings", &"gear", "Text size, keys, sound and graphics.", func() -> void: open_requested.emit(SettingsPanel.new()))
	if _is_host():
		_save_button = _add(grid, "Save now", &"save", "Save the colony right now.", _on_save)
	_add(grid, "Sources", &"book", "The science pages behind the game.", func() -> void: open_requested.emit(SourceRegisterPanel.new()))
	_add(grid, "Credits", &"star", "Who made the game.", func() -> void: open_requested.emit(CreditsPanel.new()))
	_add(grid, "Main menu", &"home", "Leave this colony and go to the title screen.", func() -> void: quit_to_menu_pressed.emit())
	_add(grid, "Quit", &"exit", "Close the game.", func() -> void: services.quit_game(), UiTheme.DANGER_BUTTON)
	_status = _wrap_label("", UiTheme.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	# Alone and paused, the title already says it; the line is for "Pausing…" and for the co-op vote count.
	var alone := services == null or not services.has_game() or services.session.peers.size() <= 1
	_vote_label.visible = _vote_label.text != "" and not (alone and services != null and services.has_game() and services.session.paused)
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
	card.name = "SolLength"
	card.theme_type_variation = UiTheme.CARD
	card.tooltip_text = SOL_HELP
	parent.add_child(card)
	var box := VBoxContainer.new()
	card.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	box.add_child(row)
	row.add_child(Kit.picture(&"clock", 28.0))
	_sol_label = _wrap_label("")
	_sol_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_sol_label)
	_sol_slider = HSlider.new()
	_sol_slider.min_value = 5.0
	_sol_slider.max_value = 120.0
	_sol_slider.step = 1.0
	_sol_slider.custom_minimum_size.y = 36.0
	_sol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sol_slider.tooltip_text = SOL_HELP
	_sol_slider.value = services.clock().sol_minutes if services.has_game() else 20.0
	_sol_slider.value_changed.connect(func(v: float) -> void:
		_update_sol_label(v)
		_sol_dirty = true)
	_sol_slider.drag_started.connect(func() -> void: _dragging = true)
	_sol_slider.drag_ended.connect(func(_changed: bool) -> void: _dragging = false)
	box.add_child(_sol_slider)
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


## A smaller picture button under Resume: pictogram on top, one or two words, the rest in the tooltip.
func _add(parent: Control, text: String, kind: StringName, tip: String, action: Callable, variation: StringName = &"") -> Button:
	var b := Kit.tile(text, kind, 40.0, Vector2(150, 104), variation)
	b.tooltip_text = tip
	b.pressed.connect(action)
	parent.add_child(b)
	return b


static func _wrap_label(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
