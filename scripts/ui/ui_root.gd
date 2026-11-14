class_name UiRoot
extends CanvasLayer
## Holds every open panel as a stack (menus, station surfaces, cargo, crew, sources...) and the game-wide UI keys.
##
## - Only the top panel is shown and takes input; panels underneath are hidden until it closes.
## - Esc closes the top panel; with nothing open it opens the pause menu.
## - M, I and C open their panels only while gameplay has focus (or close their own panel when it is on top).
## - E closes a station surface, but never in the frame it was opened (E opened it).
## - The first panel frees the mouse; closing the last one captures it again while a game is running.
## - Scroll positions are kept per panel class, and focus returns to where it was, so quick switching does not lose
##   your place in a list.

## The first panel opened (true) or the last one closed (false). The game stops steering the body while open.
signal menu_mode_changed(open: bool)
## The pause menu's "Quit to menu" was pressed.
signal quit_to_menu_requested

## How often the top panel re-reads state.
const REFRESH_PER_SECOND := 4.0
const OPENED_FRAME_META := &"_ui_opened_frame"
## Widest and tallest each kind of panel gets, in screen units; UiRoot centres the panel. 0 = the whole frame.
## A height of HUG means "as tall as what is inside its scrolling part, up to the frame", so a short panel is short.
## A panel can set its own max_width / max_height instead. Text never stretches across a whole wide screen.
const HUG := -1.0
const PANEL_SIZES := {
	"PauseMenu": Vector2(780, HUG), "SettingsPanel": Vector2(1240, 900), "InventoryPanel": Vector2(1240, HUG),
	"CrewSelectPanel": Vector2(1680, HUG), "ColonySummaryPanel": Vector2(1500, 0), "CreditsPanel": Vector2(1400, 0),
	"SourceRegisterPanel": Vector2(1700, 0), "StationPanel": Vector2(1240, HUG), "PowerStationPanel": Vector2(1400, HUG),
}
## Seconds a panel takes to fade in (none with the "reduce motion" setting).
const FADE_SECONDS := 0.12

var services: GameServices
var settings: GameSettings

var _screen: Control
var _backdrop: Panel
var _frame: MarginContainer
var _subtitle: SubtitleLine
var _stack: Array[UiPanel] = []
var _scroll_memory: Dictionary = {}       # panel class key -> Array[Vector2i] (one per ScrollContainer, tree order)
var _tab_memory: Dictionary = {}          # panel class key -> Array[int] (current tab of each TabContainer)
var _focus_memory: Dictionary = {}        # panel instance id -> Control that had focus when it was covered
var _pending_scroll: Array[Dictionary] = []
var _refresh_left := 0.0
var _mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _was_open := false
var _fit_frames := 0


func _init() -> void:
	name = "UiRoot"
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_screen = Control.new()
	_screen.name = "Screen"
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.theme = UiTheme.get_theme()
	add_child(_screen)
	_subtitle = SubtitleLine.new()
	_screen.add_child(_subtitle)
	_backdrop = Panel.new()
	_backdrop.name = "Backdrop"
	_backdrop.theme_type_variation = UiTheme.BACKDROP
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.visible = false
	_screen.add_child(_backdrop)
	_frame = MarginContainer.new()
	_frame.name = "Panels"
	_frame.theme_type_variation = UiTheme.SCREEN_MARGIN
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(_frame)


## Connects the UI to the game and the player's settings. Call once before opening panels.
func setup(p_services: GameServices, p_settings: GameSettings) -> void:
	services = p_services
	settings = p_settings if p_settings != null else GameSettings.new()
	_subtitle.settings = settings
	PlayerInput.ensure_actions()
	_update_mouse()


## Opens `panel` on top: sets it up if needed, hides the one below, shows it and gives keyboard focus to its first control.
func open(panel: UiPanel) -> void:
	if panel == null or _stack.has(panel):
		return
	if panel is SettingsPanel and (panel as SettingsPanel).settings == null:
		(panel as SettingsPanel).settings = settings
	if panel.services == null:
		panel.setup(services)
	var below := top()
	if below != null:
		_remember(below)
		below.visible = false
	_stack.append(panel)
	panel.set_meta(OPENED_FRAME_META, Engine.get_process_frames())
	panel.close_requested.connect(_on_close_requested.bind(panel))
	panel.open_requested.connect(_on_open_requested)
	if panel.get_parent() == null:
		_frame.add_child(panel)
	_fit(panel)
	panel.visible = true
	panel.refresh()
	_restore(panel)
	_focus(panel)
	_after_change()
	_fade_in(panel)


## Closes the top panel unless it says it cannot close now (for example while waiting for a key).
func close_top() -> void:
	var panel := top()
	if panel == null or not panel.can_close():
		return
	_remove(panel)
	_reveal_top()
	_after_change()


## Closes every panel (the game uses this when it switches screens, for example after New colony).
func close_all() -> void:
	while not _stack.is_empty():
		_remove(_stack.back())
	_after_change()


func is_open() -> bool:
	return not _stack.is_empty()


## The panel on top, or null.
func top() -> UiPanel:
	return null if _stack.is_empty() else _stack.back()


## Number of open panels.
func depth() -> int:
	return _stack.size()


## True when keys should go to the player body: no panel is open and no text field has focus.
func gameplay_has_focus() -> bool:
	if is_open():
		return false
	var vp := get_viewport()
	var owner_control := vp.gui_get_focus_owner() if vp != null else null
	return not (owner_control is LineEdit or owner_control is TextEdit or owner_control is SpinBox)


## Opens the pause menu on top (it asks the host to pause while it is open).
func open_pause_menu() -> void:
	if pause_menu() != null:
		return
	var menu := PauseMenu.new()
	menu.quit_to_menu_pressed.connect(func() -> void: quit_to_menu_requested.emit())
	open(menu)


## The open pause menu, or null.
func pause_menu() -> PauseMenu:
	for p: UiPanel in _stack:
		if p is PauseMenu:
			return p as PauseMenu
	return null


## Shows an authored message as a subtitle (queued behind any on screen).
func show_subtitle(text: String, seconds := 4.0, speaker := "", essential := false) -> void:
	_subtitle.show_line(text, seconds, speaker, essential)


## The subtitle line (for tests and the integrator).
func subtitle_line() -> SubtitleLine:
	return _subtitle


## The mouse mode UiRoot asked for last (VISIBLE or CAPTURED).
func wanted_mouse_mode() -> Input.MouseMode:
	return _mouse_mode


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton):
		return
	if event.is_action_pressed(&"back"):
		if is_open():
			close_top()
		elif services != null and services.has_game():
			open_pause_menu()
		_handled()
	elif event.is_action_pressed(&"source_register"):
		if top() is SourceRegisterPanel:
			close_top()
		else:
			open(SourceRegisterPanel.new())
		_handled()
	elif event.is_action_pressed(&"map"):
		_toggle(BlueprintPanel)
	elif event.is_action_pressed(&"inventory"):
		_toggle(InventoryPanel)
	elif event.is_action_pressed(&"crew"):
		_toggle(CrewSelectPanel)
	elif event.is_action_pressed(&"interact"):
		var panel := top()
		if panel != null and bool(panel.get_meta(&"station_surface", false)):
			if int(panel.get_meta(OPENED_FRAME_META, -1)) < Engine.get_process_frames():
				close_top()
			_handled()
	elif event.is_action_pressed(&"toggle_view") and not gameplay_has_focus():
		_handled()        # the view never switches while a panel is open or text is being typed


## M / I / C: open the panel from gameplay, or close it when it is the top panel; otherwise do nothing.
func _toggle(panel_class: Script) -> void:
	var panel := top()
	if panel != null and panel.get_script() == panel_class:
		close_top()
		_handled()
	elif gameplay_has_focus():
		open(panel_class.new() as UiPanel)
		_handled()


func _handled() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()


# ---------------------------------------------------------------- refresh, scroll and focus memory

func _process(delta: float) -> void:
	for i in range(_pending_scroll.size() - 1, -1, -1):
		var job: Dictionary = _pending_scroll[i]
		if not is_instance_valid(job.panel):
			_pending_scroll.remove_at(i)
			continue
		_apply_scroll(job.panel, job.values)
		job.frames -= 1
		if job.frames <= 0:
			_pending_scroll.remove_at(i)
			if job.panel == top():
				_keep_focus_in_view(job.panel)
	# A panel's text wraps once it has its width, which changes how tall it wants to be: fit again for a few frames
	# after it opens, and then whenever it refreshes.
	if _fit_frames > 0 and top() != null:
		_fit_frames -= 1
		_fit(top())
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 1.0 / REFRESH_PER_SECOND
		var panel := top()
		if panel != null:
			panel.refresh()
			_fit(panel)


## Remembers the scroll positions of a panel (by class) and which control had focus.
func _remember(panel: UiPanel) -> void:
	var values: Array[Vector2i] = []
	for s: ScrollContainer in _scrolls(panel):
		values.append(Vector2i(s.scroll_horizontal, s.scroll_vertical))
	_scroll_memory[_class_key(panel)] = values
	var tabs: Array[int] = []
	for t: Node in panel.find_children("*", "TabContainer", true, false):
		tabs.append((t as TabContainer).current_tab)
	_tab_memory[_class_key(panel)] = tabs
	var vp := get_viewport()
	var f := vp.gui_get_focus_owner() if vp != null else null
	if f != null and panel.is_ancestor_of(f):
		_focus_memory[panel.get_instance_id()] = f


## Puts back the remembered tabs and scroll positions. Containers lay out over the next frames, so scrolling is
## applied for a few frames.
func _restore(panel: UiPanel) -> void:
	var key := _class_key(panel)
	var tabs: Array[int] = _tab_memory.get(key, [] as Array[int])
	var containers := panel.find_children("*", "TabContainer", true, false)
	for i in mini(tabs.size(), containers.size()):
		var tc := containers[i] as TabContainer
		if tabs[i] >= 0 and tabs[i] < tc.get_tab_count():
			tc.current_tab = tabs[i]
	if not _scroll_memory.has(key):
		return
	var values: Array[Vector2i] = _scroll_memory[key]
	_apply_scroll(panel, values)
	_pending_scroll.append({"panel": panel, "values": values, "frames": 3})


func _apply_scroll(panel: UiPanel, values: Array[Vector2i]) -> void:
	var scrolls := _scrolls(panel)
	for i in mini(scrolls.size(), values.size()):
		scrolls[i].scroll_horizontal = values[i].x
		scrolls[i].scroll_vertical = values[i].y


func _scrolls(panel: Node) -> Array[ScrollContainer]:
	var list: Array[ScrollContainer] = []
	for n in panel.find_children("*", "ScrollContainer", true, false):
		list.append(n as ScrollContainer)
	return list


func _class_key(panel: UiPanel) -> String:
	var s: Script = panel.get_script()
	return s.resource_path if s != null else panel.get_class()


func _focus(panel: UiPanel) -> void:
	var target: Control = _focus_memory.get(panel.get_instance_id())
	if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
		target = panel.first_focus()
	if target != null and target.is_visible_in_tree():
		target.grab_focus()


## After a scroll position was put back, focus must sit on a control you can see: if the focused control is
## scrolled out of view, focus moves to the first interactive control that is in view.
func _keep_focus_in_view(panel: UiPanel) -> void:
	var vp := get_viewport()
	var f := vp.gui_get_focus_owner() if vp != null else null
	if f != null and panel.is_ancestor_of(f) and _in_view(f):
		return
	for c: Control in UiLayoutCheck.focusable(panel):
		if _in_view(c):
			c.grab_focus()
			return


func _in_view(c: Control) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return (p as ScrollContainer).get_global_rect().grow(1.0).encloses(c.get_global_rect())
		p = p.get_parent()
	return true


# ---------------------------------------------------------------- size and fade

func _ready() -> void:
	get_viewport().size_changed.connect(_fit_all)


func _fit_all() -> void:
	for p: UiPanel in _stack:
		_fit(p)


## Centres a panel at its preferred size, never larger than the frame. A panel with no preferred size fills the frame.
func _fit(panel: UiPanel) -> void:
	var want := Vector2(panel.max_width, panel.max_height)
	var script := panel.get_script() as Script
	var key := String(script.get_global_name()) if script != null else ""
	if PANEL_SIZES.has(key):
		var listed: Vector2 = PANEL_SIZES[key]
		if want.x == 0.0:
			want.x = listed.x
		if want.y == 0.0:
			want.y = listed.y
	if want.y < 0.0:
		want.y = _hug_height(panel)
	var room := _screen.size
	if room.x <= 0.0 or room.y <= 0.0:
		room = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1920, 1080)
	room -= Vector2(_frame.get_theme_constant(&"margin_left") + _frame.get_theme_constant(&"margin_right"),
		_frame.get_theme_constant(&"margin_top") + _frame.get_theme_constant(&"margin_bottom"))
	var min_size := panel.custom_minimum_size
	if want.x > 0.0:
		panel.size_flags_horizontal = Control.SIZE_SHRINK_END if panel.align_right else Control.SIZE_SHRINK_CENTER
		min_size.x = maxf(0.0, minf(want.x, room.x))
	if want.y > 0.0:
		panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		min_size.y = maxf(0.0, minf(want.y, room.y))
	if not min_size.is_equal_approx(panel.custom_minimum_size):
		panel.custom_minimum_size = min_size


## Height the panel needs to show everything in its first scrolling part without scrolling (0 when it has none).
func _hug_height(panel: UiPanel) -> float:
	var scroll: ScrollContainer = null
	for s: ScrollContainer in _scrolls(panel):
		# not the scrolling part of a "?" popup, which is a window of its own inside the panel
		var in_popup := false
		var p := s.get_parent()
		while p != null and p != panel:
			if p is Window:
				in_popup = true
				break
			p = p.get_parent()
		if not in_popup:
			scroll = s
			break
	if scroll == null or scroll.get_child_count() == 0:
		return 0.0
	var content := scroll.get_child(0) as Control
	if content == null:
		return 0.0
	var chrome := panel.get_minimum_size().y - scroll.get_combined_minimum_size().y
	return ceilf(chrome + content.get_combined_minimum_size().y + 4.0)


func _fade_in(panel: UiPanel) -> void:
	if not panel.is_inside_tree() or (settings != null and settings.reduce_motion):
		panel.modulate.a = 1.0
		return
	panel.modulate.a = 0.0
	panel.create_tween().tween_property(panel, ^"modulate:a", 1.0, FADE_SECONDS)


# ---------------------------------------------------------------- stack bookkeeping

func _remove(panel: UiPanel) -> void:
	_remember(panel)
	_focus_memory.erase(panel.get_instance_id())
	_stack.erase(panel)
	if panel.close_requested.is_connected(_on_close_requested):
		panel.close_requested.disconnect(_on_close_requested)
	if panel.open_requested.is_connected(_on_open_requested):
		panel.open_requested.disconnect(_on_open_requested)
	if panel.get_parent() != null:
		panel.get_parent().remove_child(panel)
	panel.queue_free()


func _reveal_top() -> void:
	var panel := top()
	if panel == null:
		return
	_fit(panel)
	panel.visible = true
	panel.refresh()
	_restore(panel)
	_focus(panel)


func _after_change() -> void:
	var panel := top()
	_fit_frames = 4
	# Every open panel gets a dim behind it: strong for full-screen menus, lighter when the world stays in view.
	_backdrop.visible = panel != null
	if panel != null:
		_backdrop.theme_type_variation = UiTheme.BACKDROP_LIGHT if panel.keeps_world_visible else UiTheme.BACKDROP
	_update_mouse()
	var open_now := is_open()
	if open_now != _was_open:
		_was_open = open_now
		menu_mode_changed.emit(open_now)


func _update_mouse() -> void:
	var wants_cursor := false
	for p: UiPanel in _stack:
		if p.captures_mouse:
			wants_cursor = true
	var running := services != null and services.has_game() and pause_menu() == null
	if wants_cursor or not running:
		_mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = _mouse_mode


func _on_close_requested(panel: UiPanel) -> void:
	if panel == top():
		close_top()
	elif _stack.has(panel) and panel.can_close():
		_remove(panel)
		_after_change()


func _on_open_requested(panel: UiPanel) -> void:
	open(panel)
