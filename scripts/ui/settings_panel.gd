class_name SettingsPanel
extends UiPanel
## Display, Controls, Graphics and Audio tabs share live settings and keyboard focus.
## Audio exposes warning mute/volume; voice and microphone keep their existing controls.
## Changes apply at once and are saved when the panel closes (settings and key bindings).
## While it waits for a new key, the panel cannot close and the key it catches never reaches the game.

## The settings being edited. UiRoot fills this in from its own settings when it is left empty.
var settings: GameSettings
## Where settings and key bindings are saved (tests point these elsewhere).
var settings_path := GameSettings.DEFAULT_PATH
var input_path := "user://input.json"

var _tabs: TabContainer
var _ui_scale: HSlider
var _ui_scale_label: Label
var _text_size: OptionButton
var _high_contrast: CheckButton
var _subtitles: CheckButton
var _reduce_motion: CheckButton
var _reduce_flashes: CheckButton
var _warning_muted: CheckButton
var _warning_volume: HSlider
var _warning_volume_label: Label
var _mouse: HSlider
var _mouse_label: Label
var _invert_y: CheckButton
var _fov: HSlider
var _fov_label: Label
var _toggle_sprint: CheckButton
var _quality: OptionButton
var _quality_info: Label
var _binding_labels: Dictionary = {}     # action -> Label
var _change_buttons: Dictionary = {}     # action -> Button
var _reset_buttons: Dictionary = {}      # action -> Button
var _reset_all: Button
var _note: Label
var _capturing: StringName = &""
var _held_modifier := KEY_NONE           # a modifier pressed alone while capturing; binds on release
var _swallow_release := KEY_NONE         # release of the key just caught, kept from the game


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	if settings == null:
		settings = GameSettings.new()
	PlayerInput.ensure_actions()
	name = "SettingsPanel"
	theme_type_variation = UiTheme.PANEL
	var outer := VBoxContainer.new()
	add_child(outer)
	var title := Label.new()
	title.text = "Settings"
	title.theme_type_variation = UiTheme.TITLE
	outer.add_child(title)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_tabs)
	_build_display(_tab("Display"))
	_build_controls(_tab("Controls"))
	_build_graphics(_tab("Graphics"))
	_build_audio(_tab("Audio"))
	var done := Button.new()
	done.text = "Done"
	done.theme_type_variation = UiTheme.PRIMARY_BUTTON
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	done.pressed.connect(func() -> void: close_requested.emit())
	outer.add_child(done)
	_read_settings()
	_update_bindings()


func panel_title() -> String:
	return "Settings"


func can_close() -> bool:
	return _capturing == &""


## The first control of the open tab.
func first_focus() -> Control:
	var page := _tabs.get_current_tab_control()
	var c := _first_focusable(page) if page != null else null
	return c if c != null else super.first_focus()


## The tab container (tests switch tabs with it).
func tabs() -> TabContainer:
	return _tabs


## The graphics preset picker (tests choose presets with it).
func quality_button() -> OptionButton:
	return _quality


## The action waiting for a new key, or &"".
func capturing() -> StringName:
	return _capturing


## Starts waiting for the next key or mouse button for `action` (what the "Change" button does).
func begin_capture(action: StringName) -> void:
	if _capturing != &"":
		cancel_capture()
	_capturing = action
	_held_modifier = KEY_NONE
	(_change_buttons[action] as Button).text = "Press a key…"
	(_binding_labels[action] as Label).text = "Press a key or mouse button. Esc cancels."
	_note.text = ""


## Stops waiting; the old binding stays.
func cancel_capture() -> void:
	if _capturing == &"":
		return
	_capturing = &""
	_held_modifier = KEY_NONE
	_note.text = "Nothing changed."
	_update_bindings()


## Restores the default key for every action.
func reset_all() -> void:
	cancel_capture()
	for action: StringName in PlayerInput.ACTION_NAMES:
		PlayerInput.reset(action)
	_note.text = "All keys are back to the defaults."
	_update_bindings()


## Saves the settings and the key bindings.
func save_all() -> void:
	if settings != null:
		settings.save(settings_path)
	PlayerInput.save(input_path)


## The binding text shown for an action.
func binding_text(action: StringName) -> String:
	return (_binding_labels[action] as Label).text


## The "Change" button for an action.
func change_button(action: StringName) -> Button:
	return _change_buttons[action]


## The "Reset" button for an action.
func reset_button(action: StringName) -> Button:
	return _reset_buttons[action]


func _exit_tree() -> void:
	_capturing = &""
	save_all()


# ---------------------------------------------------------------- key capture

func _input(event: InputEvent) -> void:
	if _capturing == &"":
		if _swallow_release != KEY_NONE and event is InputEventKey and not event.pressed and _code(event as InputEventKey) == _swallow_release:
			_swallow_release = KEY_NONE
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
		var key := event as InputEventKey
		var code := _code(key)
		if key.echo:
			return
		if not key.pressed:
			if code == _held_modifier:
				var only := InputEventKey.new()
				only.physical_keycode = code
				_finish(only, KEY_NONE)
			return
		if code == KEY_ESCAPE:
			cancel_capture()
			_swallow_release = KEY_ESCAPE
			return
		if code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
			_held_modifier = code
			return
		var bound := InputEventKey.new()
		bound.physical_keycode = code
		bound.shift_pressed = key.shift_pressed
		bound.ctrl_pressed = key.ctrl_pressed
		bound.alt_pressed = key.alt_pressed
		_finish(bound, code)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
			get_viewport().set_input_as_handled()
			var bound := InputEventMouseButton.new()
			bound.button_index = mb.button_index
			_finish(bound, KEY_NONE)


func _finish(event: InputEvent, swallow: Key) -> void:
	var action := _capturing
	_capturing = &""
	_held_modifier = KEY_NONE
	_swallow_release = swallow
	PlayerInput.rebind(action, event)
	_note.text = "%s is now %s." % [PlayerInput.ACTION_NAMES[action], PlayerInput.describe(action)]
	_update_bindings()
	var b: Button = _change_buttons[action]
	if b.is_inside_tree():
		b.grab_focus()


static func _code(key: InputEventKey) -> Key:
	return key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode


# ---------------------------------------------------------------- building

func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


func _build_display(box: VBoxContainer) -> void:
	_ui_scale_label = _label(box, "")
	_ui_scale = _slider(box, 0.75, 2.0, 0.05)
	_ui_scale.value_changed.connect(func(v: float) -> void:
		settings.ui_scale = v
		_apply())
	_label(box, "Text size")
	_text_size = OptionButton.new()
	for item: String in ["Normal", "Large", "Extra large"]:
		_text_size.add_item(item)
	_text_size.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_text_size.item_selected.connect(func(i: int) -> void:
		settings.text_scale = GameSettings.TEXT_SCALES[i]
		_apply())
	box.add_child(_text_size)
	_high_contrast = _check(box, "High contrast (stronger colours and borders)", func(on: bool) -> void:
		settings.high_contrast = on
		_apply())
	_subtitles = _check(box, "Subtitles for messages and voices", func(on: bool) -> void:
		settings.subtitles = on
		_apply())
	_reduce_motion = _check(box, "Reduce motion (no camera bob, no fades)", func(on: bool) -> void:
		settings.reduce_motion = on
		_apply())
	_reduce_flashes = _check(box, "Static danger warnings (no border pulse)", func(on: bool) -> void:
		settings.reduce_flashes = on
		_apply())


func _build_audio(box: VBoxContainer) -> void:
	_warning_muted = _check(box, "Mute warning sounds", func(on: bool) -> void:
		settings.warning_sound_muted = on
		_apply())
	_warning_volume_label = _label(box, "")
	_warning_volume = _slider(box, 0.0, 1.0, 0.05)
	_warning_volume.value_changed.connect(func(value: float) -> void:
		settings.warning_sound_volume = value
		_apply())
	var note := _label(box, "Danger banners and countdowns remain visible with sound muted. Voice and microphone controls are in the Controls tab.")
	note.theme_type_variation = UiTheme.MUTED


func _build_controls(box: VBoxContainer) -> void:
	_mouse_label = _label(box, "")
	_mouse = _slider(box, 0.0005, 0.006, 0.0001)
	_mouse.value_changed.connect(func(v: float) -> void:
		settings.mouse_sensitivity = v
		_apply())
	_invert_y = _check(box, "Invert mouse up and down", func(on: bool) -> void:
		settings.invert_y = on
		_apply())
	_fov_label = _label(box, "")
	_fov = _slider(box, 60.0, 100.0, 1.0)
	_fov.value_changed.connect(func(v: float) -> void:
		settings.fov_degrees = v
		_apply())
	_toggle_sprint = _check(box, "Tap Shift to sprint (instead of holding it)", func(on: bool) -> void:
		settings.toggle_sprint = on
		_apply())
	# Prompt 11: microphone, voice volume and per-player mute live in their own panel.
	var voice := Button.new()
	voice.name = "VoiceSettingsButton"
	voice.text = "Voice and microphone…"
	voice.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	voice.pressed.connect(func() -> void:
		var p := VoiceSettingsPanel.new()
		p.settings = settings
		p.settings_path = settings_path
		open_requested.emit(p))
	box.add_child(voice)
	var heading := _label(box, "Keys")
	heading.theme_type_variation = UiTheme.HEADING
	var help := _label(box, "Press Change, then the new key or mouse button. Esc cancels.")
	help.theme_type_variation = UiTheme.MUTED
	var grid := GridContainer.new()
	grid.columns = 4
	box.add_child(grid)
	for action: StringName in PlayerInput.ACTION_NAMES:
		var name_label := Label.new()
		name_label.text = PlayerInput.ACTION_NAMES[action]
		grid.add_child(name_label)
		var binding := Label.new()
		binding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		binding.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(binding)
		_binding_labels[action] = binding
		var change := Button.new()
		change.text = "Change"
		change.pressed.connect(begin_capture.bind(action))
		grid.add_child(change)
		_change_buttons[action] = change
		var reset := Button.new()
		reset.text = "Reset"
		reset.pressed.connect(func() -> void:
			cancel_capture()
			PlayerInput.reset(action)
			_note.text = "%s is back to %s." % [PlayerInput.ACTION_NAMES[action], PlayerInput.describe(action)]
			_update_bindings())
		grid.add_child(reset)
		_reset_buttons[action] = reset
	_reset_all = Button.new()
	_reset_all.text = "Reset all keys"
	_reset_all.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_reset_all.pressed.connect(reset_all)
	box.add_child(_reset_all)
	_note = _label(box, "")
	_note.theme_type_variation = UiTheme.MUTED


func _build_graphics(box: VBoxContainer) -> void:
	_label(box, "Graphics quality")
	_quality = OptionButton.new()
	for item: String in GraphicsQuality.NAMES:
		_quality.add_item(item)
	_quality.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_quality.item_selected.connect(func(i: int) -> void:
		settings.graphics_quality = i
		_apply())
	box.add_child(_quality)
	_quality_info = _label(box, "")
	_quality_info.theme_type_variation = UiTheme.MUTED
	var help := _label(box, "Lower presets run faster on slower computers. High is how the colony was designed to look.")
	help.theme_type_variation = UiTheme.MUTED


func _read_settings() -> void:
	_quality.select(settings.graphics_quality)
	_ui_scale.set_value_no_signal(settings.ui_scale)
	_text_size.select(maxi(0, GameSettings.TEXT_SCALES.find(settings.text_scale)))
	_high_contrast.set_pressed_no_signal(settings.high_contrast)
	_subtitles.set_pressed_no_signal(settings.subtitles)
	_reduce_motion.set_pressed_no_signal(settings.reduce_motion)
	_reduce_flashes.set_pressed_no_signal(settings.reduce_flashes)
	_warning_muted.set_pressed_no_signal(settings.warning_sound_muted)
	_warning_volume.set_value_no_signal(settings.warning_sound_volume)
	_mouse.set_value_no_signal(settings.mouse_sensitivity)
	_invert_y.set_pressed_no_signal(settings.invert_y)
	_fov.set_value_no_signal(settings.fov_degrees)
	_toggle_sprint.set_pressed_no_signal(settings.toggle_sprint)
	_update_value_labels()


func _apply() -> void:
	_update_value_labels()
	if is_inside_tree():
		settings.apply(get_tree())


func _update_value_labels() -> void:
	_ui_scale_label.text = "Menu and HUD size: %d %%" % roundi(settings.ui_scale * 100.0)
	_mouse_label.text = "Mouse speed: %.1f (normal 2.0)" % (settings.mouse_sensitivity * 1000.0)
	_fov_label.text = "Field of view: %d°" % roundi(settings.fov_degrees)
	_quality_info.text = GraphicsQuality.DESCRIPTIONS[settings.graphics_quality]
	_warning_volume_label.text = "Warning sound volume: %d %%" % roundi(settings.warning_sound_volume * 100.0)


func _update_bindings() -> void:
	for action: StringName in _binding_labels:
		var text := PlayerInput.describe(action)
		(_binding_labels[action] as Label).text = text if text != "" else "(no key)"
		(_change_buttons[action] as Button).text = "Change"


func _label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _slider(parent: Control, lo: float, hi: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(s)
	return s


func _check(parent: Control, text: String, on_toggle: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	c.toggled.connect(on_toggle)
	parent.add_child(c)
	return c
