class_name GameSettings
extends Resource
## The player's own settings (not part of the colony save): screen, graphics, text, camera, controls and voice.
## Every value is clamped when set, and a new value emits Resource's own `changed` signal (emit_changed()).
## Gameplay code reads fov_degrees, mouse_sensitivity, invert_y and toggle_sprint from here.

const DEFAULT_PATH := "user://settings.json"
## The text sizes offered: normal, large, extra large.
const TEXT_SCALES: Array[float] = [1.0, 1.25, 1.5]
## Names of the stored values, in file order.
const KEYS: Array[StringName] = [&"ui_scale", &"text_scale", &"subtitles", &"fov_degrees", &"mouse_sensitivity",
	&"invert_y", &"toggle_sprint", &"reduce_motion", &"high_contrast", &"graphics_quality",
	&"voice_input_device", &"voice_mic_muted", &"voice_volume", &"reduce_flashes", &"warning_sound_muted", &"warning_sound_volume",
	&"narrator_voice", &"narrator_volume", &"graphics_auto", &"graphics_custom", &"brightness", &"contrast",
	&"window_mode", &"monitor", &"resolution", &"aspect_ratio", &"max_fps", &"vsync", &"low_latency", &"hdr", &"hdr_max_nits"]

## Size of all menus and the HUD (0.75 to 2.0).
@export var ui_scale := 1.0:
	set(v):
		v = clampf(v, 0.75, 2.0)
		if v != ui_scale:
			ui_scale = v
			emit_changed()
## Text size: 1.0, 1.25 or 1.5 (other values snap to the nearest).
@export var text_scale := 1.0:
	set(v):
		v = nearest_text_scale(v)
		if v != text_scale:
			text_scale = v
			emit_changed()
## Show subtitles for spoken and authored messages (essential messages always show).
@export var subtitles := true:
	set(v):
		if v != subtitles:
			subtitles = v
			emit_changed()
## Camera field of view in degrees (60 to 100).
@export var fov_degrees := 72.0:
	set(v):
		v = clampf(v, 60.0, 100.0)
		if v != fov_degrees:
			fov_degrees = v
			emit_changed()
## Radians of turn per pixel of mouse movement (0.0005 to 0.006).
@export var mouse_sensitivity := 0.002:
	set(v):
		v = clampf(v, 0.0005, 0.006)
		if v != mouse_sensitivity:
			mouse_sensitivity = v
			emit_changed()
## Mouse up looks down.
@export var invert_y := false:
	set(v):
		if v != invert_y:
			invert_y = v
			emit_changed()
## True: tap Shift to switch sprint on and off. False: hold Shift.
@export var toggle_sprint := false:
	set(v):
		if v != toggle_sprint:
			toggle_sprint = v
			emit_changed()
## Fewer moving effects (no camera bob, no fades).
@export var reduce_motion := false:
	set(v):
		if v != reduce_motion:
			reduce_motion = v
			emit_changed()
## Static urgent warnings by default. Turning this off permits only a gentle border pulse.
@export var reduce_flashes := true:
	set(v):
		if v != reduce_flashes:
			reduce_flashes = v
			emit_changed()
## Warning sounds are separate from multiplayer microphone and voice preferences.
@export var warning_sound_muted := false:
	set(v):
		if v != warning_sound_muted:
			warning_sound_muted = v
			emit_changed()
@export var warning_sound_volume := 0.65:
	set(v):
		v = clampf(v, 0.0, 1.0)
		if v != warning_sound_volume:
			warning_sound_volume = v
			emit_changed()
## Owner 2026-11-15: the narrator voice reads the cassette tapes and the opening story aloud (the computer's own
## text-to-speech voice, scripts/voice/narration.gd). On by default; the words always show on screen as well.
@export var narrator_voice := true:
	set(v):
		if v != narrator_voice:
			narrator_voice = v
			emit_changed()
## Loudness of the narrator voice (0 to 1; sent to the OS voice as 0 to 100).
@export var narrator_volume := 0.9:
	set(v):
		v = clampf(v, 0.0, 1.0)
		if v != narrator_volume:
			narrator_volume = v
			emit_changed()
## Stronger colours and borders.
@export var high_contrast := false:
	set(v):
		if v != high_contrast:
			high_contrast = v
			emit_changed()


## Graphics preset: GraphicsQuality.Level (0 Low, 1 Medium, 2 High, 3 Ultra). Medium on a Mac's first launch.
@export var graphics_quality: int = GraphicsQuality.default_level():
	set(v):
		v = clampi(v, GraphicsQuality.Level.LOW, GraphicsQuality.Level.ULTRA)
		if v != graphics_quality:
			graphics_quality = v
			emit_changed()
## "Fit to this computer" (owner 2026-11-15): the preset is picked for this computer's graphics card and, on slower
## cards, the 3D render resolution adapts to hold 60 FPS (HardwareProfile, perf/dynamic_resolution.gd). Choosing a
## preset by hand in Settings turns it off.
@export var graphics_auto := true:
	set(v):
		if v != graphics_auto:
			graphics_auto = v
			emit_changed()
## Owner 2026-11-18: graphics options changed by hand on top of the preset (GraphicsQuality.OPTIONS key -> choice index
## or slider number). Not empty = the "Custom" preset. Change it with set_graphics_option / choose_preset.
@export var graphics_custom := {}:
	set(v):
		v = _clean_custom(v)
		if v != graphics_custom:
			graphics_custom = v
			emit_changed()
## Settings > Display: picture brightness and contrast, 0..100 (50 = as the colony was lit).
@export var brightness := 50:
	set(v):
		v = clampi(v, 0, 100)
		if v != brightness:
			brightness = v
			emit_changed()
@export var contrast := 50:
	set(v):
		v = clampi(v, 0, 100)
		if v != contrast:
			contrast = v
			emit_changed()
## Settings > Display (DisplaySettings): window mode (0 windowed, 1 maximized, 2 fullscreen, 3 exclusive fullscreen),
## monitor (-1 = where the window opens), windowed size ("" = three quarters of the screen, else "1920x1080"), aspect
## ratio (DisplaySettings.ASPECTS), frame rate limit (0 = none, -1 = the monitor's refresh rate), VSync
## (DisplaySettings.VSYNC_NAMES), low latency, HDR output and its peak brightness in nits.
@export var window_mode := 1:
	set(v):
		v = clampi(v, 0, 3)
		if v != window_mode:
			window_mode = v
			emit_changed()
@export var monitor := -1:
	set(v):
		v = clampi(v, -1, 15)
		if v != monitor:
			monitor = v
			emit_changed()
@export var resolution := "":
	set(v):
		v = v.strip_edges() if v.is_empty() or v.split("x").size() == 2 else ""
		if v != resolution:
			resolution = v
			emit_changed()
@export var aspect_ratio := 0:
	set(v):
		v = clampi(v, 0, 4)
		if v != aspect_ratio:
			aspect_ratio = v
			emit_changed()
@export var max_fps := 0:
	set(v):
		v = clampi(v, -1, 1000)
		if v != max_fps:
			max_fps = v
			emit_changed()
@export var vsync := 1:
	set(v):
		v = clampi(v, 0, 3)
		if v != vsync:
			vsync = v
			emit_changed()
@export var low_latency := false:
	set(v):
		if v != low_latency:
			low_latency = v
			emit_changed()
@export var hdr := false:
	set(v):
		if v != hdr:
			hdr = v
			emit_changed()
@export var hdr_max_nits := 600:
	set(v):
		v = clampi(v, 100, 2000)
		if v != hdr_max_nits:
			hdr_max_nits = v
			emit_changed()


## True when options were changed by hand (the "Custom" preset).
func is_custom_graphics() -> bool:
	return not graphics_custom.is_empty()


## The value of a graphics option in effect: the hand-changed one, or the preset's.
func graphics_option(key: String) -> int:
	return int(graphics_custom.get(key, GraphicsQuality.preset_value(key, graphics_quality)))


## Changes one graphics option by hand: the settings become Custom ("Fit to this computer" goes off). Setting it back
## to the preset's own value removes it from the custom list.
func set_graphics_option(key: String, value: int) -> void:
	var o := GraphicsQuality.option(key)
	if o.is_empty():
		return
	value = GraphicsQuality.clamp_value(o, value)
	var c := graphics_custom.duplicate()
	if value == GraphicsQuality.preset_value(key, graphics_quality):
		c.erase(key)
	else:
		c[key] = value
	graphics_auto = false
	graphics_custom = c


## Picks a preset by hand: every option goes back to that preset's ("Fit to this computer" goes off).
func choose_preset(level: int) -> void:
	graphics_auto = false
	graphics_custom = {}
	graphics_quality = level


## What GraphicsQuality.apply takes: the hand-changed options plus the display values it applies.
func graphics_options() -> Dictionary:
	var d := graphics_custom.duplicate()
	d["brightness"] = brightness
	d["contrast"] = contrast
	d["reduce_motion"] = reduce_motion
	return d


## Only known options, each made valid; numbers from JSON become whole numbers.
static func _clean_custom(v: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in v:
		var o := GraphicsQuality.option(String(key))
		var value: Variant = v[key]
		if not o.is_empty() and (value is int or value is float):
			out[String(key)] = GraphicsQuality.clamp_value(o, value)
	return out


## VoiceService resolves this computer's built-in microphone when capture starts.
@export var voice_input_device := "":
	set(v):
		v = v.strip_edges().substr(0, 200)
		if v != voice_input_device:
			voice_input_device = v
			emit_changed()
## Prompt 11 voice: your own microphone is muted (nothing is sent; you still hear the others).
@export var voice_mic_muted := true:
	set(v):
		if v != voice_mic_muted:
			voice_mic_muted = v
			emit_changed()
## Prompt 11 voice: loudness of everyone's voices (0 to 5; 1 = normal, 5 = 500 %).
@export var voice_volume := 1.0:
	set(v):
		v = clampf(v, 0.0, 5.0)
		if v != voice_volume:
			voice_volume = v
			emit_changed()


## Reads the settings file; anything missing or broken keeps its default.
static func load_or_default(path := DEFAULT_PATH) -> GameSettings:
	var s := GameSettings.new()
	if not FileAccess.file_exists(path):
		s.fit_to_hardware()
		return s
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		s.fit_to_hardware()
		return s
	var d: Dictionary = data
	for key: StringName in KEYS:
		var v: Variant = d.get(String(key))
		var current: Variant = s.get(key)
		if current is bool and v is bool:
			s.set(key, v)
		elif current is float and (v is float or v is int):
			s.set(key, float(v))
		elif current is int and (v is float or v is int):
			s.set(key, int(v))
		elif current is String and v is String:
			s.set(key, v)
		elif current is Dictionary and v is Dictionary:
			s.set(key, v)
	# A file written before graphics_auto existed: a preset other than the default was chosen by hand, so keep it.
	if not d.has("graphics_auto"):
		s.graphics_auto = s.graphics_quality == GraphicsQuality.default_level()
	s.fit_to_hardware()
	return s


## With graphics_auto on, takes the preset this computer's graphics card is rated for. Nothing changes when the card
## is not recognised (and in headless runs, which have no graphics card).
func fit_to_hardware() -> void:
	if not graphics_auto:
		return
	var level := HardwareProfile.recommended_level()
	if level >= 0:
		graphics_quality = level
		graphics_custom = {}


## Writes the settings as JSON.
func save(path := DEFAULT_PATH) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	return file.get_error()


## Puts the screen settings into effect: UI scale, text size, high contrast colours, the graphics preset and options
## (only when they changed; after loading a world call GraphicsQuality.apply() so its lights get them too - it keeps
## these options) and the display settings (window, frame rate, VSync, HDR: DisplaySettings).
func apply(tree: SceneTree) -> void:
	if tree != null and tree.root != null:
		tree.root.content_scale_factor = ui_scale
		var options := graphics_options()
		tree.root.set_meta(GraphicsQuality.PLAYER_META, options)
		if GraphicsQuality.applied_level(tree) != graphics_quality or tree.root.get_meta(&"gq_settings_applied", {}) != options:
			GraphicsQuality.apply(tree, graphics_quality, null, options)
			tree.root.set_meta(&"gq_settings_applied", options)
		DisplaySettings.apply(self, tree)
	UiTheme.set_high_contrast(high_contrast)
	UiTheme.apply_text_scale(text_scale)


## All values by name.
func to_dict() -> Dictionary:
	var d := {}
	for key: StringName in KEYS:
		d[String(key)] = get(key)
	return d


## The offered text scale closest to `v`.
static func nearest_text_scale(v: float) -> float:
	var best := TEXT_SCALES[0]
	for s: float in TEXT_SCALES:
		if absf(s - v) < absf(best - v):
			best = s
	return best
