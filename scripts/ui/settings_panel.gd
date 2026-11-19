class_name SettingsPanel
extends UiPanel
## Display, Controls, Graphics and Audio tabs share live settings and keyboard focus.
## Every option is a picture and one to three words; the sentence that explains it is its tooltip. "Pick one"
## settings (text size, graphics quality) are rows of large buttons, not drop-downs; the text size buttons show an "A"
## in the size they stand for. In the key list the box showing a key is the button that changes it.
## Audio has the warning mute and volume; voice and microphone open from Controls and from Audio.
## Changes apply at once and are saved when the panel closes (settings and key bindings).
## While it waits for a new key, the panel cannot close and the key it catches never reaches the game.

const Kit = preload("res://scripts/ui/menu_kit.gd")
## Names (tooltips) of the text sizes, in the order of GameSettings.TEXT_SCALES.
const TEXT_SIZE_NAMES: PackedStringArray = ["Normal", "Large", "Extra large"]
const KEY_HINT := "Pick a key to change it."
const NO_KEY := "(no key)"
const QUALITY_HINT := "Lower runs faster. Higher looks better."
## The narrator reads cassette pages and the opening story aloud.
const Narration := preload("res://scripts/voice/narration.gd")

## The settings being edited. UiRoot fills this in from its own settings when it is left empty.
var settings: GameSettings
## Where settings and key bindings are saved (tests point these elsewhere).
var settings_path := GameSettings.DEFAULT_PATH
var input_path := "user://input.json"

var _tabs: TabContainer
var _ui_scale: HSlider
var _ui_scale_label: Label
var _text_size: Kit.Segmented
var _high_contrast: CheckButton
var _subtitles: CheckButton
var _reduce_motion: CheckButton
var _reduce_flashes: CheckButton
var _warning_muted: CheckButton
var _warning_volume: HSlider
var _warning_volume_label: Label
var _narrator: CheckButton
var _narrator_volume: HSlider
var _narrator_volume_label: Label
var _mouse: HSlider
var _mouse_label: Label
var _invert_y: CheckButton
var _fov: HSlider
var _fov_label: Label
var _toggle_sprint: CheckButton
var _quality: Kit.Segmented
var _quality_info: Label
var _auto_quality: CheckButton
var _option_controls := {}    # graphics option key -> HSlider or Kit.Segmented
var _option_labels := {}      # graphics option key -> value Label
var _screen: Kit.Segmented
var _window_mode: Kit.Segmented
var _window_size: Kit.Segmented
var _aspect: Kit.Segmented
var _fps_limit: Kit.Segmented
var _vsync: Kit.Segmented
var _low_latency: CheckButton
var _hdr: CheckButton
var _hdr_nits: HSlider
var _hdr_nits_label: Label
var _brightness: HSlider
var _brightness_label: Label
var _contrast: HSlider
var _contrast_label: Label
var _sizes: Array[Vector2i] = []
var _change_buttons: Dictionary = {}     # action -> Button (shows the key; pressing it waits for a new one)
var _reset_buttons: Dictionary = {}      # action -> Button
var _reset_all: Button
var _keys_grid: GridContainer
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
	_build_display(_tab("Display", &"monitor"))
	_build_controls(_tab("Controls", &"keys"))
	_build_graphics(_tab("Graphics", &"image"))
	_build_audio(_tab("Audio", &"sound"))
	var done := Kit.button("Done", &"check", UiTheme.PRIMARY_BUTTON, 26.0, 1.2, 60.0)
	done.name = "Done"
	done.custom_minimum_size.x = 200.0
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


## The graphics preset picker: a row of four buttons with OptionButton's item_count, selected, select() and
## item_selected (tests choose presets with it).
func quality_button() -> Kit.Segmented:
	return _quality


## The text size picker: three "A" buttons, one per GameSettings.TEXT_SCALES.
func text_size_button() -> Kit.Segmented:
	return _text_size


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
	_note.text = "Press a key or mouse button. Esc cancels."


## Stops waiting; the old binding stays.
func cancel_capture() -> void:
	if _capturing == &"":
		return
	_capturing = &""
	_held_modifier = KEY_NONE
	_note.text = "Nothing changed. " + KEY_HINT
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


## The binding text shown for an action (on its key button).
func binding_text(action: StringName) -> String:
	return (_change_buttons[action] as Button).text


## The button that shows an action's key; pressing it waits for a new one.
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

func _tab(title: String, kind: StringName) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_tabs.add_child(scroll)
	_tabs.set_tab_icon(_tabs.get_tab_count() - 1, Kit.pic(kind, 30.0))
	# Room for the focus ring on the left and for the scroll bar on the right.
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override(&"margin_left", 4)
	pad.add_theme_constant_override(&"margin_top", 4)
	pad.add_theme_constant_override(&"margin_right", 18)
	pad.add_theme_constant_override(&"margin_bottom", 4)
	scroll.add_child(pad)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 12)
	pad.add_child(box)
	return box


func _build_display(box: VBoxContainer) -> void:
	# Owner 2026-11-18: the screen settings of a PC game (DisplaySettings puts them into effect).
	_heading(box, "Screen")
	var screens := DisplayServer.get_screen_count() if DisplayServer.get_name() != "headless" else 1
	if screens > 1:
		_caption(box, "Monitor", &"monitor", "Which screen the game shows on.")
		var names: Array = []
		for i in screens:
			names.append(DisplaySettings.screen_name(i))
		_screen = _compact_choices(names, [])
		_screen.name = "Monitor"
		_screen.item_selected.connect(func(i: int) -> void:
			settings.monitor = i
			_apply())
		box.add_child(_screen)
	_caption(box, "Window mode", &"monitor", "Windowed, a maximized window, or fullscreen.")
	_window_mode = _compact_choices(Array(DisplaySettings.WINDOW_MODES), Array(DisplaySettings.WINDOW_TIPS))
	_window_mode.name = "WindowMode"
	_window_mode.item_selected.connect(func(i: int) -> void:
		settings.window_mode = i
		_apply())
	box.add_child(_window_mode)
	_caption(box, "Window size", &"zoom", "The size of the game window in Windowed mode. Fullscreen always uses the screen's own resolution; set the 3D resolution under Graphics > Render resolution.")
	_sizes = DisplaySettings.sizes()
	var size_names: Array = []
	for sz: Vector2i in _sizes:
		size_names.append(DisplaySettings.size_text(sz))
	_window_size = _compact_choices(size_names, [])
	_window_size.name = "WindowSize"
	_window_size.item_selected.connect(func(i: int) -> void:
		settings.resolution = DisplaySettings.size_text(_sizes[i])
		_apply())
	box.add_child(_window_size)
	_caption(box, "Aspect ratio", &"monitor", "Auto fills the screen. A fixed shape adds black bars around the picture.")
	_aspect = _compact_choices(Array(DisplaySettings.ASPECTS), [])
	_aspect.name = "AspectRatio"
	_aspect.item_selected.connect(func(i: int) -> void:
		settings.aspect_ratio = i
		_apply())
	box.add_child(_aspect)
	_caption(box, "Frame rate limit", &"clock", "The most frames per second the game draws. Lower saves power and heat.")
	var fps_names: Array = []
	for f: int in DisplaySettings.FPS_LIMITS:
		fps_names.append("Unlimited" if f == 0 else ("Monitor (%d Hz)" % DisplaySettings.refresh_rate()) if f < 0 else str(f))
	_fps_limit = _compact_choices(fps_names, [])
	_fps_limit.name = "FrameRateLimit"
	_fps_limit.item_selected.connect(func(i: int) -> void:
		settings.max_fps = DisplaySettings.FPS_LIMITS[i]
		_apply())
	box.add_child(_fps_limit)
	_caption(box, "VSync", &"monitor", "Waits for the screen before showing a frame, so the picture never tears.")
	_vsync = _compact_choices(Array(DisplaySettings.VSYNC_NAMES), Array(DisplaySettings.VSYNC_TIPS))
	_vsync.name = "VSync"
	_vsync.item_selected.connect(func(i: int) -> void:
		settings.vsync = i
		_apply())
	box.add_child(_vsync)
	var screen_grid := _switch_grid(box)
	_low_latency = _check(screen_grid, "Low latency", &"fast", "With VSync on, keeps the game a few frames per second under the refresh rate so frames never wait in a queue: the mouse feels more direct.", func(on: bool) -> void:
		settings.low_latency = on
		_apply())
	_low_latency.name = "LowLatency"
	var hdr_ok := DisplaySettings.hdr_supported()
	_hdr = _check(screen_grid, "HDR", &"star", "High dynamic range output for HDR screens: brighter highlights." if hdr_ok
		else "This screen or graphics driver does not offer HDR (turn on HDR in Windows display settings first).", func(on: bool) -> void:
		settings.hdr = on
		_apply())
	_hdr.name = "HDR"
	_hdr.disabled = not hdr_ok
	_hdr_nits_label = _caption(box, "HDR peak brightness", &"star", "The brightest highlights in HDR, in nits. Match your screen's peak brightness.")
	_hdr_nits = _slider(box, 100.0, 2000.0, 10.0)
	_hdr_nits.name = "HDRPeak"
	_hdr_nits.editable = hdr_ok
	_hdr_nits.value_changed.connect(func(v: float) -> void:
		settings.hdr_max_nits = roundi(v)
		_apply())
	_brightness_label = _caption(box, "Brightness", &"star", "Makes the whole picture brighter or darker. 50 is how the colony was lit.")
	_brightness = _slider(box, 0.0, 100.0, 1.0)
	_brightness.name = "Brightness"
	_brightness.value_changed.connect(func(v: float) -> void:
		settings.brightness = roundi(v)
		_apply())
	_contrast_label = _caption(box, "Contrast", &"contrast", "Difference between dark and bright. 50 is how the colony was lit.")
	_contrast = _slider(box, 0.0, 100.0, 1.0)
	_contrast.name = "Contrast"
	_contrast.value_changed.connect(func(v: float) -> void:
		settings.contrast = roundi(v)
		_apply())
	_heading(box, "Menus and text")
	_ui_scale_label = _caption(box, "Menu size", &"zoom", "Makes every menu and the HUD bigger or smaller.")
	_ui_scale = _slider(box, 0.75, 2.0, 0.05)
	_ui_scale.value_changed.connect(func(v: float) -> void:
		settings.ui_scale = v
		_apply())
	_caption(box, "Text size", &"letter", "How big the words are.")
	_text_size = Kit.Segmented.new()
	_text_size.name = "TextSize"
	for i in GameSettings.TEXT_SCALES.size():
		# Each "A" is drawn in the size it stands for, whatever the text size is now.
		_text_size.add_item("A", &"", TEXT_SIZE_NAMES[i], GameSettings.TEXT_SCALES[i] * 1.5)
	_text_size.item_selected.connect(func(i: int) -> void:
		settings.text_scale = GameSettings.TEXT_SCALES[i]
		_apply())
	box.add_child(_text_size)
	var grid := _switch_grid(box)
	_high_contrast = _check(grid, "High contrast", &"contrast", "Stronger colours and borders.", func(on: bool) -> void:
		settings.high_contrast = on
		_apply())
	_subtitles = _check(grid, "Subtitles", &"bubble", "Shows messages and voices as words on the screen.", func(on: bool) -> void:
		settings.subtitles = on
		_apply())
	_reduce_motion = _check(grid, "Less motion", &"motion", "No camera bob and no fades.", func(on: bool) -> void:
		settings.reduce_motion = on
		_apply())
	_reduce_flashes = _check(grid, "No flashing", &"flash", "Danger warnings stay still instead of pulsing at the screen edge.", func(on: bool) -> void:
		settings.reduce_flashes = on
		_apply())


func _build_audio(box: VBoxContainer) -> void:
	var grid := _switch_grid(box)
	_warning_muted = _check(grid, "Mute alarms", &"mute", "Turns the warning sounds off. Danger banners and countdowns stay on the screen.", func(on: bool) -> void:
		settings.warning_sound_muted = on
		_apply())
	_warning_volume_label = _caption(box, "Alarm volume", &"sound", "How loud the warning sounds are.")
	_warning_volume = _slider(box, 0.0, 1.0, 0.05)
	_warning_volume.value_changed.connect(func(value: float) -> void:
		settings.warning_sound_volume = value
		_apply())
	_narrator = _check(grid, "Narrator", &"sound", "Reads the tapes and the opening story aloud.", func(on: bool) -> void:
		settings.narrator_voice = on
		_apply())
	_narrator.name = "NarratorVoice"
	_narrator_volume_label = _caption(box, "Narrator volume", &"sound", "How loud the narrator is.")
	_narrator_volume = _slider(box, 0.0, 1.0, 0.05)
	_narrator_volume.name = "NarratorVolume"
	_narrator_volume.value_changed.connect(func(value: float) -> void:
		settings.narrator_volume = value
		_apply())
	var narrator := Narration.shared() as Narration
	var narrator_note := _label(box, "The words always show on screen too." if narrator.available()
		else "This computer has no text-to-speech voice, so the narrator stays silent. The words always show on screen.")
	narrator_note.theme_type_variation = UiTheme.MUTED
	box.add_child(_voice_button("VoiceSettingsButtonAudio"))


func _build_controls(box: VBoxContainer) -> void:
	_mouse_label = _caption(box, "Mouse speed", &"mouse", "How fast the view turns. Normal is 2.0.")
	_mouse = _slider(box, 0.0005, 0.006, 0.0001)
	_mouse.value_changed.connect(func(v: float) -> void:
		settings.mouse_sensitivity = v
		_apply())
	_fov_label = _caption(box, "View width", &"eye", "Field of view: how much you see at once.")
	_fov = _slider(box, 60.0, 100.0, 1.0)
	_fov.value_changed.connect(func(v: float) -> void:
		settings.fov_degrees = v
		_apply())
	var grid := _switch_grid(box)
	_invert_y = _check(grid, "Invert mouse", &"flip", "Moving the mouse up looks down.", func(on: bool) -> void:
		settings.invert_y = on
		_apply())
	_toggle_sprint = _check(grid, "Tap to sprint", &"fast", "Tap Shift once to sprint, instead of holding it.", func(on: bool) -> void:
		settings.toggle_sprint = on
		_apply())
	# Prompt 11: microphone, voice volume and per-player mute live in their own panel.
	box.add_child(_voice_button("VoiceSettingsButton"))

	var keys_row := HBoxContainer.new()
	keys_row.name = "KeysHeader"
	keys_row.add_theme_constant_override(&"separation", 12)
	box.add_child(keys_row)
	keys_row.add_child(Kit.picture(&"keys", 30.0, &"heading"))
	var heading := Label.new()
	heading.text = "Keys"
	heading.theme_type_variation = UiTheme.HEADING
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys_row.add_child(heading)
	_reset_all = Kit.button("Reset all keys", &"reset", &"", 24.0, 1.0, 48.0)
	_reset_all.tooltip_text = "Puts every key back to the one the game started with."
	_reset_all.pressed.connect(reset_all)
	keys_row.add_child(_reset_all)
	_note = _label(box, KEY_HINT)
	_note.theme_type_variation = UiTheme.MUTED
	var grid_keys := GridContainer.new()
	grid_keys.name = "Keys"
	grid_keys.add_theme_constant_override(&"h_separation", 12)
	box.add_child(grid_keys)
	_keys_grid = grid_keys
	_fit_keys_grid()
	for action: StringName in PlayerInput.ACTION_NAMES:
		var action_name := String(PlayerInput.ACTION_NAMES[action])
		var name_label := Label.new()
		name_label.text = action_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.custom_minimum_size.x = 150.0
		grid_keys.add_child(name_label)
		var change := Button.new()
		change.icon = Kit.pic(&"pencil", 20.0)
		change.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		change.custom_minimum_size = Vector2(210, 48)
		change.tooltip_text = "Change the key for: %s" % action_name
		change.pressed.connect(begin_capture.bind(action))
		grid_keys.add_child(change)
		_change_buttons[action] = change
		var reset := Button.new()
		reset.icon = Kit.pic(&"reset", 24.0)
		reset.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reset.custom_minimum_size = Vector2(56, 48)
		reset.tooltip_text = "Back to the usual key for: %s" % action_name
		reset.pressed.connect(func() -> void:
			cancel_capture()
			PlayerInput.reset(action)
			_note.text = "%s is back to %s." % [PlayerInput.ACTION_NAMES[action], PlayerInput.describe(action)]
			_update_bindings())
		grid_keys.add_child(reset)
		_reset_buttons[action] = reset


func _build_graphics(box: VBoxContainer) -> void:
	_caption(box, "Preset", &"image", "Lower runs faster on slower computers. High is how the colony was designed to look. Change any option below and it becomes Custom.")
	_quality = Kit.Segmented.new()
	_quality.name = "Quality"
	for i in GraphicsQuality.NAMES.size():
		_quality.add_item(GraphicsQuality.NAMES[i], StringName("bars%d" % (i + 1)), GraphicsQuality.DESCRIPTIONS[i], 0.0, 44.0)
	_quality.add_item(GraphicsQuality.CUSTOM_NAME, &"gear", GraphicsQuality.CUSTOM_DESCRIPTION, 0.0, 44.0)
	_quality.item_selected.connect(func(i: int) -> void:
		if i >= GraphicsQuality.NAMES.size():
			# "Custom" is where the options below lead; pressing it changes nothing
			_refresh_graphics()
			return
		# A preset picked by hand stays exactly as picked: "Fit to this computer" goes off, hand changes are dropped.
		settings.choose_preset(i)
		_apply()
		_refresh_graphics())
	box.add_child(_quality)
	_quality_info = _label(box, QUALITY_HINT)
	_quality_info.theme_type_variation = UiTheme.MUTED
	var auto_tip := "Picks the quality for this computer's graphics card. On slower cards the 3D picture gets a little softer when needed to stay smooth."
	_auto_quality = _check(_switch_grid(box), "Fit to this computer", &"image", auto_tip, func(on: bool) -> void:
		settings.graphics_auto = on
		settings.fit_to_hardware()
		_apply()
		_refresh_graphics())
	_auto_quality.name = "AutoQuality"
	# Owner 2026-11-18: every feature as its own option, in sections like a PC game's graphics menu.
	for section: String in GraphicsQuality.SECTIONS:
		_heading(box, section)
		for o: Dictionary in GraphicsQuality.OPTIONS:
			if String(o.section) == section:
				_option_row(box, o)


## One graphics option: its name and value (a * marks a value changed from the preset) over a row of choices or a slider.
func _option_row(box: VBoxContainer, o: Dictionary) -> void:
	var key := String(o.key)
	_option_labels[key] = _caption(box, String(o.name), StringName(o.icon), String(o.tip))
	if GraphicsQuality.is_slider(o):
		var r: Array = o.slider
		var s := _slider(box, float(r[0]), float(r[1]), float(r[2]))
		s.name = "Option_" + key
		s.value_changed.connect(func(v: float) -> void:
			settings.set_graphics_option(key, roundi(v))
			_apply()
			_refresh_graphics())
		_option_controls[key] = s
	else:
		var seg := _compact_choices(o.choices as Array, [])
		seg.name = "Option_" + key
		seg.item_selected.connect(func(i: int) -> void:
			settings.set_graphics_option(key, i)
			_apply()
			_refresh_graphics())
		box.add_child(seg)
		_option_controls[key] = seg


## A row of small "pick one" buttons (the settings list is long; full-size buttons would make it twice as tall).
func _compact_choices(names: Array, tips: Array) -> Kit.Segmented:
	var seg := Kit.Segmented.new()
	for i in names.size():
		var b := seg.add_item(String(names[i]), &"", String(tips[i]) if i < tips.size() else "")
		b.custom_minimum_size = Vector2(64, 46)
	return seg


func _heading(box: VBoxContainer, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = UiTheme.HEADING
	box.add_child(l)
	return l


## The preset row (a preset, or Custom), every option's control and value, and the auto switch, from the settings.
func _refresh_graphics() -> void:
	if _quality == null:
		return
	_quality.select(GraphicsQuality.NAMES.size() if settings.is_custom_graphics() else settings.graphics_quality)
	for o: Dictionary in GraphicsQuality.OPTIONS:
		var key := String(o.key)
		var v := settings.graphics_option(key)
		var c: Control = _option_controls.get(key)
		if c is HSlider:
			(c as HSlider).set_value_no_signal(v)
		elif c is Kit.Segmented:
			(c as Kit.Segmented).select(v)
		var text := (str(v) + String(o.get("unit", ""))) if GraphicsQuality.is_slider(o) else String((o.choices as Array)[v])
		(_option_labels[key] as Label).text = text + ("  *" if settings.graphics_custom.has(key) else "")
	_update_quality_info()


## The button that opens the voice and microphone panel with these settings.
func _voice_button(node_name: String) -> Button:
	var voice := Kit.button("Voice and mic", &"mic", &"", 28.0, 1.0, 56.0)
	voice.name = node_name
	voice.tooltip_text = "Toggle your built-in microphone and set how loud other players are."
	voice.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	voice.pressed.connect(func() -> void:
		var p := VoiceSettingsPanel.new()
		p.settings = settings
		p.settings_path = settings_path
		open_requested.emit(p))
	return voice


func _read_settings() -> void:
	if _screen != null:
		_screen.select(settings.monitor if settings.monitor >= 0 else DisplayServer.window_get_current_screen())
	_window_mode.select(settings.window_mode)
	var size_i := -1
	for i in _sizes.size():
		if DisplaySettings.size_text(_sizes[i]) == settings.resolution:
			size_i = i
	_window_size.select(size_i)
	_aspect.select(settings.aspect_ratio)
	_fps_limit.select(maxi(0, DisplaySettings.FPS_LIMITS.find(settings.max_fps)))
	_vsync.select(settings.vsync)
	_low_latency.set_pressed_no_signal(settings.low_latency)
	_hdr.set_pressed_no_signal(settings.hdr)
	_hdr_nits.set_value_no_signal(settings.hdr_max_nits)
	_brightness.set_value_no_signal(settings.brightness)
	_contrast.set_value_no_signal(settings.contrast)
	_ui_scale.set_value_no_signal(settings.ui_scale)
	_text_size.select(maxi(0, GameSettings.TEXT_SCALES.find(settings.text_scale)))
	_high_contrast.set_pressed_no_signal(settings.high_contrast)
	_subtitles.set_pressed_no_signal(settings.subtitles)
	_reduce_motion.set_pressed_no_signal(settings.reduce_motion)
	_reduce_flashes.set_pressed_no_signal(settings.reduce_flashes)
	_warning_muted.set_pressed_no_signal(settings.warning_sound_muted)
	_warning_volume.set_value_no_signal(settings.warning_sound_volume)
	_narrator.set_pressed_no_signal(settings.narrator_voice)
	_narrator_volume.set_value_no_signal(settings.narrator_volume)
	_mouse.set_value_no_signal(settings.mouse_sensitivity)
	_invert_y.set_pressed_no_signal(settings.invert_y)
	_fov.set_value_no_signal(settings.fov_degrees)
	_toggle_sprint.set_pressed_no_signal(settings.toggle_sprint)
	_update_value_labels()
	_refresh_graphics()


func _apply() -> void:
	_update_value_labels()
	if is_inside_tree():
		settings.apply(get_tree())
	_fit_keys_grid()


## The key list is two rows wide (name, key, reset twice) while the text is normal size, one row wide when it is
## large, so long action names keep enough room.
func _fit_keys_grid() -> void:
	if _keys_grid != null:
		_keys_grid.columns = 6 if UiTheme.text_scale() < 1.2 else 3


func _update_value_labels() -> void:
	_ui_scale_label.text = "%d %%" % roundi(settings.ui_scale * 100.0)
	_mouse_label.text = "%.1f" % (settings.mouse_sensitivity * 1000.0)
	_fov_label.text = "%d°" % roundi(settings.fov_degrees)
	_warning_volume_label.text = "%d %%" % roundi(settings.warning_sound_volume * 100.0)
	_narrator_volume_label.text = "%d %%" % roundi(settings.narrator_volume * 100.0)
	_brightness_label.text = str(settings.brightness)
	_contrast_label.text = str(settings.contrast)
	_hdr_nits_label.text = "%d nits" % settings.hdr_max_nits
	_update_quality_info()


## The line under the presets: which graphics card the game runs on and what was picked for it.
func _update_quality_info() -> void:
	if _quality_info == null or _auto_quality == null:
		return
	_auto_quality.set_pressed_no_signal(settings.graphics_auto)
	var card := HardwareProfile.summary()
	if settings.is_custom_graphics():
		var n := settings.graphics_custom.size()
		_quality_info.text = "Custom: %d option%s changed from %s (marked *). Pick a preset to go back to it." % [n,
			"" if n == 1 else "s", GraphicsQuality.level_name(settings.graphics_quality)]
	elif settings.graphics_auto and card != "":
		_quality_info.text = "This computer: %s. Picked %s to keep the game smooth." % [card, GraphicsQuality.level_name(settings.graphics_quality)]
	elif card != "":
		_quality_info.text = "%s This computer: %s." % [QUALITY_HINT, card]
	else:
		_quality_info.text = QUALITY_HINT


func _update_bindings() -> void:
	for action: StringName in _change_buttons:
		var text := PlayerInput.describe(action)
		(_change_buttons[action] as Button).text = text if text != "" else NO_KEY


func _label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


## A pictogram and a short name above a slider or a row of choices; returns the label that shows the value.
func _caption(parent: Control, text: String, kind: StringName, tip: String) -> Label:
	var row := Kit.caption(text, kind, tip)
	parent.add_child(row)
	return row.get_node("Value") as Label


func _slider(parent: Control, lo: float, hi: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size.y = 40.0
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(s)
	return s


## Two columns of switches, so each one is a wide target.
func _switch_grid(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 24)
	parent.add_child(grid)
	return grid


func _check(parent: Control, text: String, kind: StringName, tip: String, on_toggle: Callable) -> CheckButton:
	var c := Kit.toggle(text, kind, tip, on_toggle)
	parent.add_child(c)
	return c
