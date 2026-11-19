class_name DisplaySettings
extends RefCounted
## Settings > Display, screen part (owner 2026-11-18): monitor, window mode, windowed size, aspect ratio, frame rate
## limit, VSync, low latency and HDR output, read from GameSettings and put into effect on the game window.
##
## Only what changed is touched: on the first apply a value still at its default leaves the window as the project and
## the command line set it up (so the perf benches keep their own VSync and frame cap). Nothing happens headless.
## Brightness and contrast are applied by GraphicsQuality (they live on the WorldEnvironment).

const WINDOW_MODES: PackedStringArray = ["Windowed", "Maximized", "Fullscreen", "Exclusive"]
const WINDOW_TIPS: PackedStringArray = [
	"A window you can move and resize.",
	"A window filling the screen, with the taskbar.",
	"Borderless, covering the whole screen. Switching to other programs is instant.",
	"Exclusive fullscreen: the game owns the screen. Can lower latency a little; switching away is slower.",
]
const ASPECTS: PackedStringArray = ["Auto", "16:9", "16:10", "21:9", "4:3"]
const ASPECT_RATIOS: Array[float] = [0.0, 16.0 / 9.0, 16.0 / 10.0, 64.0 / 27.0, 4.0 / 3.0]
## Frame rate limit choices (0 = none, -1 = the monitor's refresh rate).
const FPS_LIMITS: Array[int] = [0, 30, 60, 120, 144, -1]
const VSYNC_NAMES: PackedStringArray = ["Off", "On", "Adaptive", "Fast"]
const VSYNC_TIPS: PackedStringArray = [
	"No waiting for the screen: the most frames, but the picture can tear.",
	"Waits for the screen: no tearing.",
	"Waits for the screen while the game keeps up, and stops waiting when it falls behind (less stutter).",
	"Triple buffering: no tearing, less waiting (mailbox).",
]
const _VSYNC_MODES: Array[int] = [DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_ADAPTIVE,
	DisplayServer.VSYNC_MAILBOX]
## Windowed sizes offered (only those that fit the screen), plus the screen's own size.
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440),
	Vector2i(3840, 2160)]
## Low latency: with VSync on, frames are capped this many below the refresh rate, so finished frames never queue up
## waiting for the screen (the input-to-screen delay drops by up to two frames).
const LOW_LATENCY_MARGIN := 3
const _META := &"ds_applied"
const DEFAULTS := {"window_mode": 1, "monitor": -1, "resolution": "", "aspect_ratio": 0, "max_fps": 0, "vsync": 1,
	"low_latency": false, "hdr": false, "hdr_max_nits": 600}


## Puts the display settings into effect on `tree`'s window (only what changed since the last apply).
static func apply(s: GameSettings, tree: SceneTree) -> void:
	if s == null or tree == null or tree.root == null or DisplayServer.get_name() == "headless":
		return
	var now := {}
	for key: String in DEFAULTS:
		now[key] = s.get(key)
	var last: Dictionary = tree.root.get_meta(_META, DEFAULTS)
	if now == last:
		return
	tree.root.set_meta(_META, now)
	var changed := func(keys: Array) -> bool:
		return keys.any(func(k: String) -> bool: return now[k] != last[k])
	if changed.call(["monitor"]) and s.monitor >= 0 and s.monitor < DisplayServer.get_screen_count():
		DisplayServer.window_set_current_screen(s.monitor)
	if changed.call(["window_mode", "resolution", "monitor"]):
		_apply_window(s)
	if changed.call(["aspect_ratio"]):
		_apply_aspect(tree.root, s.aspect_ratio)
	if changed.call(["vsync"]):
		DisplayServer.window_set_vsync_mode(_VSYNC_MODES[s.vsync] as DisplayServer.VSyncMode)
	if changed.call(["max_fps", "low_latency", "vsync"]):
		Engine.max_fps = fps_cap(s)
	if changed.call(["hdr", "hdr_max_nits"]) and hdr_supported():
		tree.root.hdr_output_requested = s.hdr
		DisplayServer.window_set_hdr_output_max_luminance(float(s.hdr_max_nits))


## Whether this screen and graphics driver can show HDR.
static func hdr_supported() -> bool:
	return DisplayServer.get_name() != "headless" and DisplayServer.window_is_hdr_output_supported()


## The monitor's refresh rate (60 when the system does not say).
static func refresh_rate() -> int:
	var r := DisplayServer.screen_get_refresh_rate()
	return roundi(r) if r > 1.0 else 60


## The frame cap (Engine.max_fps) for these settings: the limit, or with Low latency and VSync on a little under the
## refresh rate.
static func fps_cap(s: GameSettings) -> int:
	var cap := refresh_rate() if s.max_fps < 0 else s.max_fps
	if s.low_latency and s.vsync in [1, 2]:
		var under := maxi(30, refresh_rate() - LOW_LATENCY_MARGIN)
		cap = under if cap <= 0 else mini(cap, under)
	return cap


## The windowed sizes that fit the current screen (and the screen's own size).
static func sizes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen()) \
		if DisplayServer.get_name() != "headless" else Vector2i(1920, 1080)
	for sz: Vector2i in SIZES:
		if sz.x <= screen.x and sz.y <= screen.y and sz != screen:
			out.append(sz)
	out.append(screen)
	return out


static func size_text(sz: Vector2i) -> String:
	return "%dx%d" % [sz.x, sz.y]


## A readable name of screen `i` ("1: 2560x1440, 120 Hz").
static func screen_name(i: int) -> String:
	var sz := DisplayServer.screen_get_size(i)
	return "%d: %dx%d, %d Hz" % [i + 1, sz.x, sz.y, roundi(DisplayServer.screen_get_refresh_rate(i))]


static func _apply_window(s: GameSettings) -> void:
	match s.window_mode:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			var want := Vector2i(roundi(screen.size.x * 0.75), roundi(screen.size.y * 0.75))
			var parts := s.resolution.split("x")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				want = Vector2i(int(parts[0]), int(parts[1]))
			want = want.min(screen.size)
			DisplayServer.window_set_size(want)
			DisplayServer.window_set_position(screen.position + (screen.size - want) / 2)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		3:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


## Auto fills the window (the project's "expand"); a fixed ratio keeps that shape with black bars around it.
static func _apply_aspect(root: Window, aspect: int) -> void:
	var r := ASPECT_RATIOS[clampi(aspect, 0, ASPECT_RATIOS.size() - 1)]
	var base_h := int(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	var base_w := int(ProjectSettings.get_setting("display/window/size/viewport_width", 1920))
	if r <= 0.0:
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		root.content_scale_size = Vector2i(base_w, base_h)
	else:
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		root.content_scale_size = Vector2i(roundi(base_h * r), base_h)
