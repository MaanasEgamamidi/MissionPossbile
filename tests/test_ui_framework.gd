extends SceneTree
## Prompt 05 part A checks: theme contrast and focus styles, layout of the main menu, pause menu and settings at three
## screen sizes, keyboard focus order, UiRoot's panel stack and keys, key remapping, settings files, the sol slider.
## Run: godot --headless --path . --script res://tests/test_ui_framework.gd

## Stands in for gameplay: records the gameplay actions that got past the UI.
class GameplayProbe:
	extends Node
	var seen: Array[StringName] = []

	func _unhandled_input(event: InputEvent) -> void:
		for a: StringName in [&"toggle_view", &"map", &"interact", &"jump"]:
			if event.is_action_pressed(a):
				seen.append(a)


const SIZES := [[Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 1.0], [Vector2i(1280, 720), 1.5]]

var _passed := 0
var _total := 0
var _dir := ""
var services: GameServices


func _check(name: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS ", name, ("  " + detail) if detail != "" else "")
	else:
		print("FAIL ", name, ": ", detail)


func _frames(n := 2) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	# Real pixels: the project stretches canvas items from 1920x1080; for the checks the panels lay out in the window
	# size itself, the harder case for 1280x720.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	PlayerInput.ensure_actions()
	_dir = ProjectSettings.globalize_path("res://").path_join("_test_saves/ui_a")
	DirAccess.make_dir_recursive_absolute(_dir)
	services = GameServices.new()
	services.saves = SaveService.new(_dir, "colony", 2)
	root.add_child(services)
	services.saves.delete_all()
	services.start_new_game(1)
	await _frames()

	await _test_contrast()
	await _test_focus_styles()
	await _test_layouts()
	await _test_focus_cycles()
	await _test_ui_root()
	await _test_remapping()
	_test_settings_file()
	await _test_sol_slider()
	await _test_subtitles()

	UiTheme.apply_text_scale(1.0)
	for action: StringName in PlayerInput.ACTIONS:
		PlayerInput.reset(action)
	services.saves.delete_all()
	services.queue_free()
	services = null
	await _frames(1)
	UiTheme.release()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


# ---------------------------------------------------------------- theme

func _test_contrast() -> void:
	var theme := UiTheme.get_theme()
	for hc: bool in [false, true]:
		UiTheme.set_high_contrast(hc)
		var palette_name := "high contrast" if hc else "normal"
		# Real controls in the tree, so the colours come through the normal theme lookup.
		var holder := VBoxContainer.new()
		holder.theme = theme
		root.add_child(holder)
		var panels: Array[PanelContainer] = []
		for panel_var: StringName in UiTheme.PANEL_VARIATIONS:
			var pc := PanelContainer.new()
			pc.theme_type_variation = panel_var if panel_var != &"PanelContainer" else &""
			holder.add_child(pc)
			var column := VBoxContainer.new()
			pc.add_child(column)
			for label_var: StringName in UiTheme.LABEL_VARIATIONS:
				var l := Label.new()
				l.text = "Oxygen 12 kg"
				l.theme_type_variation = label_var if label_var != &"Label" else &""
				column.add_child(l)
			panels.append(pc)
		var buttons: Array[Button] = []
		for button_var: StringName in [&"Button", UiTheme.PRIMARY_BUTTON, UiTheme.DANGER_BUTTON]:
			var b := Button.new()
			b.text = "Resume"
			b.theme_type_variation = button_var if button_var != &"Button" else &""
			holder.add_child(b)
			buttons.append(b)
		await _frames(1)
		for li in UiTheme.LABEL_VARIATIONS.size():
			var worst := 99.0
			var worst_on := ""
			for pc: PanelContainer in panels:
				var sb := pc.get_theme_stylebox(&"panel") as StyleBoxFlat
				var fc := (pc.get_child(0).get_child(li) as Label).get_theme_color(&"font_color")
				# Panels are translucent: judge them over a white, a black and a Mars-orange world behind.
				for under: Color in [Color.WHITE, Color.BLACK, Color(0.85, 0.5, 0.3)]:
					var bg := under.lerp(Color(sb.bg_color, 1.0), sb.bg_color.a)
					var ratio := UiTheme.contrast(fc, bg)
					if ratio < worst:
						worst = ratio
						worst_on = "%s over %s" % [pc.theme_type_variation, under.to_html(false)]
			_check("contrast %s %s >= 4.5:1" % [palette_name, UiTheme.LABEL_VARIATIONS[li]], worst >= 4.5, "worst %.2f on %s" % [worst, worst_on])
		for b: Button in buttons:
			var sb := b.get_theme_stylebox(&"normal") as StyleBoxFlat
			var ratio := UiTheme.contrast(b.get_theme_color(&"font_color"), sb.bg_color)
			_check("contrast %s %s text >= 4.5:1" % [palette_name, b.theme_type_variation if b.theme_type_variation != &"" else &"Button"], ratio >= 4.5, "%.2f" % ratio)
		holder.queue_free()
		await _frames(1)
	UiTheme.set_high_contrast(false)


func _test_focus_styles() -> void:
	var holder := VBoxContainer.new()
	holder.theme = UiTheme.get_theme()
	root.add_child(holder)
	var missing := PackedStringArray()
	for type: StringName in UiTheme.FOCUS_STYLES:
		var c := ClassDB.instantiate(type) as Control
		holder.add_child(c)
		var item: StringName = UiTheme.FOCUS_STYLES[type]
		var sb := c.get_theme_stylebox(item) as StyleBoxFlat
		var visible_ring := sb != null and ((sb.border_width_left >= 2 and sb.border_color.a > 0.9) or (sb.draw_center and sb.bg_color.a > 0.9))
		if type == &"HSlider" or type == &"VSlider":
			var normal := c.get_theme_stylebox(&"grabber_area") as StyleBoxFlat
			visible_ring = visible_ring and normal != null and not normal.bg_color.is_equal_approx(sb.bg_color)
		if not visible_ring:
			missing.append(String(type))
	_check("focus style on Button, CheckBox, CheckButton, OptionButton, LineEdit, Slider, ItemList, TabBar, ScrollBar and more",
		missing.is_empty(), "missing: " + ", ".join(missing))
	var spin := SpinBox.new()
	holder.add_child(spin)
	var spin_focus := spin.get_line_edit().get_theme_stylebox(&"focus") as StyleBoxFlat
	_check("focus style on SpinBox (its text field)", spin_focus != null and spin_focus.border_width_left >= 2)
	var b := Button.new()
	holder.add_child(b)
	var states_ok := true
	for state: StringName in [&"hover", &"pressed", &"disabled"]:
		var s := b.get_theme_stylebox(state) as StyleBoxFlat
		var n := b.get_theme_stylebox(&"normal") as StyleBoxFlat
		states_ok = states_ok and s != null and not s.bg_color.is_equal_approx(n.bg_color)
	_check("buttons have hover, pressed and disabled looks", states_ok)
	var before := b.get_theme_font_size(&"font_size")
	UiTheme.apply_text_scale(1.5)
	var title := Label.new()
	title.theme_type_variation = UiTheme.TITLE
	holder.add_child(title)
	await _frames(1)
	var after := b.get_theme_font_size(&"font_size")
	_check("text scale 1.5 resizes fonts on the same theme (open controls update)", before == UiTheme.BASE_FONT_SIZE and after == 27 and title.get_theme_font_size(&"font_size") > after, "%d -> %d, title %d" % [before, after, title.get_theme_font_size(&"font_size")])
	UiTheme.apply_text_scale(1.0)
	holder.queue_free()
	await _frames(1)


# ---------------------------------------------------------------- layout and focus order

func _make_main_menu() -> UiPanel:
	var m := MainMenu.new()
	m.setup(services)
	m.open_join_section()
	m.open_host_section()
	m.show_notice("Playing together arrives in a later update.")
	return m


func _make_pause_menu() -> UiPanel:
	var p := PauseMenu.new()
	p.setup(services)
	return p


func _make_settings(tab: int) -> UiPanel:
	var s := SettingsPanel.new()
	s.settings = GameSettings.new()
	s.settings_path = _dir.path_join("settings_layout.json")
	s.input_path = _dir.path_join("input_layout.json")
	s.setup(services)
	s.tabs().current_tab = tab
	return s


func _panels() -> Array:
	return [["MainMenu", _make_main_menu], ["PauseMenu", _make_pause_menu],
		["SettingsPanel Display", _make_settings.bind(0)], ["SettingsPanel Controls", _make_settings.bind(1)]]


func _test_layouts() -> void:
	for entry: Array in _panels():
		for sz: Array in SIZES:
			var screen: Vector2i = sz[0]
			var scale: float = sz[1]
			root.size = screen
			UiTheme.apply_text_scale(scale)
			var panel: UiPanel = (entry[1] as Callable).call()
			root.add_child(panel)
			panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			await _frames()
			var probs := UiLayoutCheck.problems(panel, Vector2(screen))
			var fprobs := UiLayoutCheck.focus_problems(panel)
			var label := "%s at %dx%d text %.1f" % [entry[0], screen.x, screen.y, scale]
			_check("layout " + label, probs.is_empty(), " | ".join(probs))
			_check("focus styles " + label, fprobs.is_empty(), " | ".join(fprobs))
			root.remove_child(panel)
			panel.queue_free()
			await _frames(1)
	UiTheme.apply_text_scale(1.0)
	root.size = Vector2i(1280, 720)


func _tab_key(shift := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.physical_keycode = KEY_TAB
	ev.shift_pressed = shift
	ev.pressed = true
	root.push_input(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	root.push_input(up)


func _test_focus_cycles() -> void:
	root.size = Vector2i(1280, 720)
	for entry: Array in _panels():
		var panel: UiPanel = (entry[1] as Callable).call()
		root.add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await _frames()
		var wanted := UiLayoutCheck.focusable(panel)
		var visited := {}
		if not wanted.is_empty():
			wanted[0].grab_focus()
			for i in wanted.size() * 2 + 4:
				var f := root.gui_get_focus_owner()
				if f != null:
					visited[f] = true
				_tab_key()
		var missed := PackedStringArray()
		for c: Control in wanted:
			if not visited.has(c):
				missed.append("%s '%s'" % [c.get_class(), c.get("text") if c is Button else c.name])
		_check("Tab cycles through every control of %s (%d controls)" % [entry[0], wanted.size()], not wanted.is_empty() and missed.is_empty(), "missed: " + ", ".join(missed))
		root.remove_child(panel)
		panel.queue_free()
		await _frames(1)


# ---------------------------------------------------------------- UiRoot

func _key(code: Key, unicode := 0, shift := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.unicode = unicode
	ev.shift_pressed = shift
	ev.pressed = true
	root.push_input(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	root.push_input(up)


func _type(text: String) -> void:
	for ch in text:
		var code: Key = KEY_SPACE if ch == " " else OS.find_keycode_from_string(ch.to_upper())
		_key(code, ch.unicode_at(0))


func _test_ui_root() -> void:
	var probe := GameplayProbe.new()
	root.add_child(probe)                     # added before UiRoot: UiRoot sees unhandled input first
	var ui := UiRoot.new()
	root.add_child(ui)
	var settings := GameSettings.new()
	ui.setup(services, settings)
	var modes: Array[bool] = []
	ui.menu_mode_changed.connect(func(open: bool) -> void: modes.append(open))
	await _frames()
	_check("UiRoot is a CanvasLayer on layer 20", ui.layer == 20)
	_check("nothing open: gameplay has focus, mouse captured", ui.gameplay_has_focus() and ui.wanted_mouse_mode() == Input.MOUSE_MODE_CAPTURED)

	# ---- stack
	var a := CreditsPanel.new()
	ui.open(a)
	var b := ColonySummaryPanel.new()
	ui.open(b)
	await _frames()
	_check("open: stack of two, top is the last, the one below is hidden", ui.depth() == 2 and ui.top() == b and b.visible and not a.visible)
	_check("open: setup() was called, mouse freed, menu mode on once", a.services == services and ui.wanted_mouse_mode() == Input.MOUSE_MODE_VISIBLE and modes == [true], str(modes))
	_check("open: keyboard focus is inside the top panel", root.gui_get_focus_owner() == null or b.is_ancestor_of(root.gui_get_focus_owner()))
	ui.close_top()
	await _frames(1)
	_check("close_top: the panel below shows again", ui.depth() == 1 and ui.top() == a and a.visible)
	ui.close_top()
	await _frames(1)
	_check("close last: mouse captured again, menu mode off", ui.depth() == 0 and ui.wanted_mouse_mode() == Input.MOUSE_MODE_CAPTURED and modes == [true, false], str(modes))
	var free_panel := CreditsPanel.new()
	free_panel.captures_mouse = false
	ui.open(free_panel)
	_check("a panel that does not capture the mouse leaves it captured", ui.wanted_mouse_mode() == Input.MOUSE_MODE_CAPTURED)
	var full := MainMenu.new()
	ui.open(full)
	await _frames(1)
	_check("full-screen menu gets the dimmed backdrop", (ui.get_node("Screen/Backdrop") as Control).visible)
	ui.close_all()
	await _frames(1)
	_check("close_all empties the stack", ui.depth() == 0 and not (ui.get_node("Screen/Backdrop") as Control).visible)
	var no_game := GameServices.new()
	root.add_child(no_game)
	var ui2 := UiRoot.new()
	root.add_child(ui2)
	ui2.setup(no_game, settings)
	ui2.open(CreditsPanel.new())
	ui2.close_top()
	_check("no game running: closing the last panel keeps the mouse free", ui2.wanted_mouse_mode() == Input.MOUSE_MODE_VISIBLE)
	ui2.queue_free()
	no_game.queue_free()
	await _frames(1)

	# ---- Esc
	ui.open(CreditsPanel.new())
	await _frames(1)
	_key(KEY_ESCAPE)
	await _frames(1)
	_check("Esc closes the top panel", ui.depth() == 0)
	_key(KEY_ESCAPE)
	await _frames(1)
	_check("Esc with nothing open opens the pause menu, which pauses the solo game", ui.top() is PauseMenu and services.session.paused and ui.wanted_mouse_mode() == Input.MOUSE_MODE_VISIBLE)
	_key(KEY_ESCAPE)
	await _frames(1)
	_check("Esc closes the pause menu, which unpauses; mouse captured again", ui.depth() == 0 and not services.session.paused and ui.wanted_mouse_mode() == Input.MOUSE_MODE_CAPTURED)
	await _frames(1)
	ui.open(SettingsPanel.new())
	await _frames(1)
	_check("Shift+Backspace opens the source register over another panel", _source_register_opens(ui))
	ui.close_all()
	await _frames(1)

	# ---- text fields keep gameplay keys away
	probe.seen.clear()
	var field := LineEdit.new()
	root.add_child(field)
	field.grab_focus()
	_check("gameplay_has_focus() is false while a LineEdit has focus (no panel open)", not ui.gameplay_has_focus())
	_type("m")
	await _frames(1)
	_check("typing m in a field opens no blueprint and reaches no gameplay", ui.depth() == 0 and probe.seen.is_empty() and field.text == "m", "seen %s, text '%s'" % [probe.seen, field.text])
	field.release_focus()
	await _frames(1)
	_check("gameplay_has_focus() true again once the field lets go", ui.gameplay_has_focus())
	_key(KEY_M, "m".unicode_at(0))
	await _frames(1)
	_check("M from gameplay opens the blueprint", ui.top() is BlueprintPanel)
	_key(KEY_M, "m".unicode_at(0))
	await _frames(1)
	_check("M again closes the blueprint", ui.depth() == 0 and probe.seen.is_empty(), str(probe.seen))
	field.queue_free()
	var menu := MainMenu.new()
	ui.open(menu)
	await _frames()
	var address := menu.open_join_section()
	await _frames(1)
	address.grab_focus()
	address.text = ""
	probe.seen.clear()
	_type("tab m")
	await _frames(1)
	_check("typing 'tab m' into the join address: the text is typed", address.text == "tab m", "'%s'" % address.text)
	_check("typing 'tab m': view and map actions do not fire, no blueprint opens", probe.seen.is_empty() and ui.depth() == 1 and ui.top() == menu, "seen %s, top %s" % [probe.seen, ui.top()])
	_key(KEY_TAB)
	_key(KEY_M, "m".unicode_at(0))
	await _frames(1)
	_check("Tab and M while a menu is open: no view switch, no blueprint", probe.seen.is_empty() and ui.top() == menu, str(probe.seen))
	_key(KEY_I, "i".unicode_at(0))
	_key(KEY_C, "c".unicode_at(0))
	await _frames(1)
	_check("I and C do nothing while another panel is on top", ui.top() == menu)
	ui.close_all()
	await _frames(1)

	# ---- E and station surfaces
	var station := CreditsPanel.new()
	station.set_meta(&"station_surface", true)
	ui.open(station)
	_key(KEY_E, "e".unicode_at(0))
	_check("E does not close a station surface in the frame it opened", ui.top() == station)
	await _frames(1)
	_key(KEY_E, "e".unicode_at(0))
	await _frames(1)
	_check("E closes the station surface in a later frame, without reaching gameplay", ui.depth() == 0 and not probe.seen.has(&"interact"), str(probe.seen))
	var not_station := CreditsPanel.new()
	ui.open(not_station)
	await _frames(1)
	_key(KEY_E, "e".unicode_at(0))
	await _frames(1)
	_check("E leaves other panels open", ui.top() == not_station)
	ui.close_all()
	await _frames(1)

	# ---- scroll and focus memory
	root.size = Vector2i(1280, 720)
	UiTheme.apply_text_scale(1.5)
	var s1 := SettingsPanel.new()
	s1.settings_path = _dir.path_join("settings_scroll.json")
	s1.input_path = _dir.path_join("input_scroll.json")
	ui.open(s1)
	s1.tabs().current_tab = 1
	await _frames(3)
	var scroll1 := s1.tabs().get_current_tab_control() as ScrollContainer
	scroll1.scroll_vertical = 260
	await _frames(1)
	var kept := scroll1.scroll_vertical
	var focus_target := s1.change_button(&"inventory")
	scroll1.ensure_control_visible(focus_target)
	await _frames(1)
	kept = scroll1.scroll_vertical
	focus_target.grab_focus()
	await _frames(1)
	ui.open(CreditsPanel.new())
	await _frames(2)
	ui.open(ColonySummaryPanel.new())
	await _frames(1)
	ui.close_top()
	ui.close_top()
	await _frames(4)
	_check("after quick switching, the list keeps its scroll position", kept > 0 and scroll1.scroll_vertical == kept, "%d vs %d" % [scroll1.scroll_vertical, kept])
	_check("after quick switching, focus is back on the control it was on", root.gui_get_focus_owner() == focus_target, str(root.gui_get_focus_owner()))
	ui.close_top()
	await _frames(1)
	var s2 := SettingsPanel.new()
	s2.settings_path = _dir.path_join("settings_scroll.json")
	s2.input_path = _dir.path_join("input_scroll.json")
	ui.open(s2)
	await _frames(5)
	var scroll2 := s2.tabs().get_current_tab_control() as ScrollContainer
	var f2 := root.gui_get_focus_owner()
	_check("reopened panel: same tab and scroll position restored", s2.tabs().current_tab == 1 and scroll2.scroll_vertical == kept, "tab %d, %d vs %d" % [s2.tabs().current_tab, scroll2.scroll_vertical, kept])
	_check("reopened panel: focus on a control that is in view", f2 != null and s2.is_ancestor_of(f2) and scroll2.get_global_rect().grow(1.0).encloses(f2.get_global_rect()), str(f2))
	ui.close_all()
	UiTheme.apply_text_scale(1.0)
	await _frames(1)
	probe.queue_free()
	ui.queue_free()
	await _frames(1)


func _source_register_opens(ui: UiRoot) -> bool:
	_key(KEY_BACKSPACE, 0, true)
	return ui.top() is SourceRegisterPanel and ui.depth() == 2


# ---------------------------------------------------------------- remapping

func _test_remapping() -> void:
	var probe := GameplayProbe.new()
	root.add_child(probe)
	var ui := UiRoot.new()
	root.add_child(ui)
	ui.setup(services, GameSettings.new())
	var panel := SettingsPanel.new()
	panel.settings_path = _dir.path_join("settings_remap.json")
	panel.input_path = _dir.path_join("input.json")
	DirAccess.remove_absolute(panel.input_path)
	ui.open(panel)
	panel.tabs().current_tab = 1
	await _frames()
	_check("key list shows every action in order", panel.binding_text(&"map") == "M" and panel.binding_text(&"source_register") == "Shift+Backspace", "%s / %s" % [panel.binding_text(&"map"), panel.binding_text(&"source_register")])
	panel.change_button(&"map").pressed.emit()
	_check("Change waits for a key and the panel cannot close meanwhile", panel.capturing() == &"map" and not panel.can_close())
	ui.close_top()
	_check("close while waiting is refused", ui.top() == panel)
	_key(KEY_K, "k".unicode_at(0))
	await _frames(1)
	_check("capture: the next key becomes the binding", PlayerInput.describe(&"map") == "K" and panel.binding_text(&"map") == "K" and panel.capturing() == &"", PlayerInput.describe(&"map"))
	panel.change_button(&"map").pressed.emit()
	_key(KEY_ESCAPE)
	await _frames(1)
	_check("Esc cancels: binding unchanged, panel still open, no pause menu", PlayerInput.describe(&"map") == "K" and panel.capturing() == &"" and ui.top() == panel and ui.depth() == 1)
	probe.seen.clear()
	panel.change_button(&"jump").pressed.emit()
	_key(KEY_K, "k".unicode_at(0))
	await _frames(1)
	_check("the caught key is used up: it does not reach the game", probe.seen.is_empty() and PlayerInput.describe(&"jump") == "K" and ui.top() == panel, str(probe.seen))
	panel.change_button(&"grab").pressed.emit()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	root.push_input(click)
	await _frames(1)
	_check("capture also takes a mouse button", PlayerInput.describe(&"grab") == "Right Mouse Button" or PlayerInput.describe(&"grab").contains("Right"), PlayerInput.describe(&"grab"))
	panel.reset_button(&"jump").pressed.emit()
	_check("Reset restores one action's default", PlayerInput.describe(&"jump") == "Space" and PlayerInput.describe(&"map") == "K", PlayerInput.describe(&"jump"))
	panel.reset_all()
	_check("Reset all restores every default", PlayerInput.describe(&"map") == "M" and PlayerInput.describe(&"grab") == "G / Left mouse", PlayerInput.describe(&"grab"))
	panel.change_button(&"map").pressed.emit()
	_key(KEY_K, "k".unicode_at(0))
	await _frames(1)
	ui.close_top()
	await _frames(1)
	_check("closing saves the key file", FileAccess.file_exists(_dir.path_join("input.json")) and ui.depth() == 0)
	PlayerInput.reset(&"map")
	var before := PlayerInput.describe(&"map")
	var err := PlayerInput.load(_dir.path_join("input.json"))
	_check("saved key file reloads", before == "M" and err == OK and PlayerInput.describe(&"map") == "K", "%s, %s" % [error_string(err), PlayerInput.describe(&"map")])
	for action: StringName in PlayerInput.ACTIONS:
		PlayerInput.reset(action)
	probe.queue_free()
	ui.queue_free()
	await _frames(1)


# ---------------------------------------------------------------- settings file

func _test_settings_file() -> void:
	var path := _dir.path_join("settings.json")
	DirAccess.remove_absolute(path)
	var fresh := GameSettings.load_or_default(path)
	_check("no file: defaults", fresh.ui_scale == 1.0 and fresh.text_scale == 1.0 and fresh.subtitles and fresh.fov_degrees == 72.0 and is_equal_approx(fresh.mouse_sensitivity, 0.002) and not fresh.invert_y and not fresh.toggle_sprint and not fresh.reduce_motion and not fresh.high_contrast)
	var s := GameSettings.new()
	var changes := [0]
	s.changed.connect(func() -> void: changes[0] += 1)
	s.ui_scale = 1.4
	s.text_scale = 1.3
	s.subtitles = false
	s.fov_degrees = 90.0
	s.mouse_sensitivity = 0.004
	s.invert_y = true
	s.toggle_sprint = true
	s.reduce_motion = true
	s.high_contrast = true
	_check("each change emits changed; text scale snaps to 1.25", changes[0] == 9 and s.text_scale == 1.25, "%d, %.2f" % [changes[0], s.text_scale])
	var clamped := GameSettings.new()
	clamped.ui_scale = 9.0
	clamped.fov_degrees = 10.0
	clamped.mouse_sensitivity = 1.0
	_check("values are clamped to their ranges", clamped.ui_scale == 2.0 and clamped.fov_degrees == 60.0 and clamped.mouse_sensitivity == 0.006)
	var err := s.save(path)
	var back := GameSettings.load_or_default(path)
	_check("settings save and load round trip", err == OK and back.to_dict() == s.to_dict(), "%s vs %s" % [back.to_dict(), s.to_dict()])
	s.apply(self)
	_check("apply sets the UI scale and the theme", is_equal_approx(root.content_scale_factor, 1.4) and UiTheme.is_high_contrast() and UiTheme.get_theme().default_font_size == roundi(UiTheme.BASE_FONT_SIZE * 1.25))
	GameSettings.new().apply(self)


# ---------------------------------------------------------------- pause menu, sol length

func _test_sol_slider() -> void:
	var ui := UiRoot.new()
	root.add_child(ui)
	ui.setup(services, GameSettings.new())
	var sends := [0]
	var on_sol := func(_m: float) -> void: sends[0] += 1
	services.events.sol_settings_changed.connect(on_sol)
	ui.open_pause_menu()
	await _frames()
	var menu := ui.pause_menu()
	var slider := menu.sol_slider()
	_check("pause menu on the host has the sol length slider", slider != null and slider.min_value == 5.0 and slider.max_value == 120.0)
	_check("pause menu says it is paused", menu.vote_text() != "" and services.session.paused, menu.vote_text())
	slider.drag_started.emit()
	slider.value = 30.0
	slider.value = 35.0
	slider.value = 40.0
	await _frames()
	_check("dragging sends nothing until release", sends[0] == 0, str(sends[0]))
	slider.drag_ended.emit(true)
	await _frames()
	_check("release sends exactly one set_sol_minutes", sends[0] == 1 and is_equal_approx(services.clock().sol_minutes, 40.0), "%d, %.1f" % [sends[0], services.clock().sol_minutes])
	slider.grab_focus()
	_key(KEY_RIGHT)
	await _frames()
	_check("one keyboard step sends exactly one more", sends[0] == 2 and is_equal_approx(services.clock().sol_minutes, 41.0), "%d, %.1f" % [sends[0], services.clock().sol_minutes])
	var labels := menu.find_children("*", "Label", true, false)
	var has_label := false
	for l: Node in labels:
		if (l as Label).text == "One sol (Mars day) lasts 41 real minutes":
			has_label = true
	_check("label reads 'One sol (Mars day) lasts 41 real minutes'", has_label)
	await _frames(3)
	_check("refreshing does not send again", sends[0] == 2, str(sends[0]))
	ui.close_top()
	await _frames(1)
	_check("closing the pause menu takes the pause vote back", not services.session.paused)
	services.events.sol_settings_changed.disconnect(on_sol)

	services.mode = &"client"
	var client_menu := PauseMenu.new()
	client_menu.setup(services)
	_check("non-host: no sol length slider and no Save now", client_menu.sol_slider() == null and client_menu.find_children("*", "HSlider", true, false).is_empty() and not _has_button(client_menu, "Save now"))
	_check("non-host: shows 'Waiting for everyone to agree'", client_menu.vote_text().begins_with("Waiting for everyone to agree"), client_menu.vote_text())
	client_menu.free()
	services.mode = &"offline"
	ui.queue_free()
	await _frames(1)

	var mm := MainMenu.new()
	mm.setup(services)
	_check("main menu Continue shows the save's sol and date", mm.save_summary().begins_with("Sol 1, saved ") and not mm.first_focus().is_queued_for_deletion(), mm.save_summary())
	var hosted := []
	mm.host_pressed.connect(func(port: int, cont: bool) -> void: hosted.append([port, cont]))
	mm.open_host_section()
	for b: Node in mm.find_children("*", "Button", true, false):
		if (b as Button).text == "Start hosting":
			(b as Button).pressed.emit()
	_check("Host emits host_pressed with the default port", hosted.size() == 1 and int(hosted[0][0]) == NetSession.DEFAULT_PORT, str(hosted))
	mm.free()


func _has_button(node: Node, text: String) -> bool:
	for b: Node in node.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return true
	return false


# ---------------------------------------------------------------- subtitles

func _test_subtitles() -> void:
	var settings := GameSettings.new()
	var ui := UiRoot.new()
	root.add_child(ui)
	ui.setup(services, settings)
	await _frames(1)
	var line := ui.subtitle_line()
	ui.show_subtitle("The dust storm is coming.", 0.5, "Mission control")
	ui.show_subtitle("Check the batteries.", 3.0)
	_check("subtitle shows the first line with its speaker; the second waits", line.current_text() == "The dust storm is coming." and line.current_speaker() == "Mission control" and line.queued_count() == 1)
	await create_timer(0.7).timeout
	_check("subtitle moves on to the queued line", line.current_text() == "Check the batteries." and line.current_speaker() == "", line.current_text())
	settings.subtitles = false
	ui.show_subtitle("Optional chatter.")
	ui.show_subtitle("Oxygen is low.", 2.0, "", true)
	_check("subtitles off: only essential messages are kept", line.queued_count() == 1)
	ui.queue_free()
	await _frames(1)
