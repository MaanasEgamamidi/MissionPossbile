class_name DynamicResolution
extends Node
## Adaptive 3D render resolution: draws the 3D world at fewer pixels (FSR upscaling, menus and HUD stay sharp) when
## the graphics card cannot hold the target frame rate, and goes back up when it has room again.
##
## Why: the game is GPU-bound in every view (docs/perf/baseline.md), and most of that cost is per pixel (417 fixture
## lights, SSAO / SSIL, MSAA). A laptop card such as the RTX 5050 is slower than the RTX 4060 Ti the colony was tuned
## on and often drives a 2560x1600 panel, so the same picture costs far more there. This measures the real GPU time
## of the main viewport on the machine itself, so it needs no per-card tuning.
##
## On only when all of these hold (wanted()):
##   - not a headless run, and PerfSettings.dynamic_resolution_mode is not 0
##   - mode 1 (forced on), or the player's "Fit to this computer" setting is on and HardwareProfile rates the card
##     MID or BASIC. On a STRONG card nothing changes: High stays the authored picture at the window's resolution.
##   - or the preset is a temporal one (Ultra, 2026-11-18): FSR 2 rebuilds the full picture from a smaller one, so the
##     scale moves between 77 % and min_scale() on every card to hold 60 FPS (changing it costs < 3 ms once, measured).
## When it turns off it puts the graphics preset's own render scale back.
##
## Rules, checked twice a second on the mean GPU time of that half second:
##   budget      = 90 % of a frame at the target rate (60 FPS: 15 ms)
##   step down   0.1 (0.2 when far over) after two checks in a row above budget x 1.08
##   step up     0.1 after six checks in a row where the cost predicted at the higher scale (cost x pixels) stays under
##               85 % of the budget, so a step up never causes the next step down
##   limits      top = the preset's scale, lowered so the 3D pixels stay under HardwareProfile max_pixels;
##               bottom = HardwareProfile min_scale
##   no gain     a step down that saves less than 4 % is undone and not tried again for 30 s (the view is limited by
##               geometry, not pixels, so a blurrier picture would buy nothing)
## After every change it waits one second (the render buffers are rebuilt) before measuring again.

const NODE_NAME := "DynamicResolution"
const GROUP := &"dynamic_resolution"
const EVAL_INTERVAL := 0.5
const MIN_SAMPLES := 5
const SETTLE_TIME := 1.0
const START_HOLD := 3.0
const STEP := 0.1
const BUDGET_SHARE := 0.9
## Ultra (temporal): more headroom, so the frame-to-frame swing of the GPU time stays under one refresh (2026-11-18).
const TEMPORAL_BUDGET_SHARE := 0.85
const OVER_FACTOR := 1.08
const FAR_OVER_FACTOR := 1.6
const UP_MARGIN := 0.85
const OVER_EVALS := 2
const UNDER_EVALS := 6
const MIN_GAIN := 0.04
const FLOOR_HOLD := 30.0

var settings: GameSettings
## True while this node is steering the render scale.
var active := false
## The render scale in effect (1.0 = every pixel of the window).
var render_scale := 1.0
## Mean GPU time of the last checked half second, in ms.
var gpu_ms := 0.0

var _window: Window
var _rid: RID
var _sum := 0.0
var _count := 0
var _eval_t := 0.0
var _hold_t := 0.0
var _over := 0
var _under := 0
var _probe_ms := -1.0
var _probe_from := 1.0
var _floor := 0.0
var _floor_t := 0.0


## Adds the node to `game_main` (once) and returns it.
static func attach(game_main: Node, p_settings: GameSettings) -> DynamicResolution:
	var existing := game_main.get_node_or_null(NODE_NAME) as DynamicResolution
	if existing != null:
		existing.settings = p_settings
		return existing
	var node := DynamicResolution.new()
	node.name = NODE_NAME
	node.settings = p_settings
	game_main.add_child(node)
	return node


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_window = get_tree().root
	_rid = _window.get_viewport_rid()


func _exit_tree() -> void:
	if active and is_instance_valid(_window):
		active = false
		_write(preset_scale())


func _process(delta: float) -> void:
	var want := wanted()
	if want != active:
		_set_active(want)
	if not active:
		return
	if _floor_t > 0.0:
		_floor_t -= delta
		if _floor_t <= 0.0:
			_floor = 0.0
	if _hold_t > 0.0:
		_hold_t -= delta
		return
	var ms := RenderingServer.viewport_get_measured_render_time_gpu(_rid)
	if ms > 0.0:
		_sum += ms
		_count += 1
	_eval_t += delta
	if _eval_t >= EVAL_INTERVAL:
		_eval_t = 0.0
		_evaluate()


## Whether the render scale should be steered right now (see the list at the top).
func wanted() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var mode := int(Perf.cfg().dynamic_resolution_mode)
	if mode == 0:
		return false
	if mode == 1:
		return true
	# Ultra (2026-11-18): a temporal preset adapts its render scale on every card, so it holds 60 FPS in the heavy rooms
	var level := GraphicsQuality.applied_level(get_tree())
	if level >= 0 and bool(GraphicsQuality.value("temporal", level)):
		return true
	return settings != null and settings.graphics_auto and bool(HardwareProfile.current().get("dynamic", false))


## The frame rate to hold: PerfSettings.dynamic_resolution_target_fps, or the screen's refresh rate when that is lower.
func target_fps() -> float:
	var fps := maxf(float(Perf.cfg().dynamic_resolution_target_fps), 20.0)
	var refresh := DisplayServer.screen_get_refresh_rate()
	return minf(fps, refresh) if refresh > 20.0 else fps


## The render scale of the graphics preset in effect.
func preset_scale() -> float:
	var level := GraphicsQuality.applied_level(get_tree())
	if level < 0:
		return 1.0
	# on macOS this already includes the Retina pixel budget of that preset
	var pixels := float(_window.size.x) * float(_window.size.y) if _window != null else 0.0
	return GraphicsQuality.render_scale(level, pixels)


## Ultra's temporal upscaler rebuilds a full picture from half the pixels each way, so it may go down to TEMPORAL_MIN_SCALE
## (only in the views that need it: the Greenhouse and the Power Room looking over the plaza, measured 2026-11-18).
const TEMPORAL_MIN_SCALE := 0.5


func budget_share() -> float:
	var level := GraphicsQuality.applied_level(get_tree()) if is_inside_tree() else -1
	return TEMPORAL_BUDGET_SHARE if level >= 0 and bool(GraphicsQuality.value("temporal", level)) else BUDGET_SHARE


func min_scale() -> float:
	var s := float(HardwareProfile.current().get("min_scale", 0.6))
	var level := GraphicsQuality.applied_level(get_tree()) if is_inside_tree() else -1
	if level >= 0 and bool(GraphicsQuality.value("temporal", level)):
		s = minf(s, TEMPORAL_MIN_SCALE)
	return s


## The highest scale allowed: the preset's own, lowered so the 3D pixels stay under the profile's max_pixels.
func max_scale() -> float:
	var top := preset_scale()
	var cap := float(HardwareProfile.current().get("max_pixels", 0))
	var pixels := float(_window.size.x) * float(_window.size.y)
	if cap > 0.0 and pixels > cap:
		top = minf(top, sqrt(cap / pixels))
	return clampf(floorf(top * 20.0 + 0.001) / 20.0, min_scale(), 1.0)


func _set_active(on: bool) -> void:
	active = on
	_over = 0
	_under = 0
	_sum = 0.0
	_count = 0
	_eval_t = 0.0
	_probe_ms = -1.0
	_floor = 0.0
	_floor_t = 0.0
	if on:
		RenderingServer.viewport_set_measure_render_time(_rid, true)
		render_scale = max_scale()
		_write(render_scale)
		_hold_t = START_HOLD
	else:
		_hold_t = 0.0
		render_scale = preset_scale()
		_write(render_scale)


func _evaluate() -> void:
	var top := max_scale()
	var low := minf(maxf(min_scale(), _floor), top)
	var wanted_scale := clampf(render_scale, low, top)
	# A preset change (GraphicsQuality.apply writes its own scale) or a resized window: back inside the limits.
	if not is_equal_approx(wanted_scale, render_scale) or not is_equal_approx(_window.scaling_3d_scale, render_scale):
		_change(wanted_scale, false)
		return
	if _count < MIN_SAMPLES:
		return
	gpu_ms = _sum / float(_count)
	_sum = 0.0
	_count = 0
	if _probe_ms > 0.0:
		var before := _probe_ms
		_probe_ms = -1.0
		if gpu_ms > before * (1.0 - MIN_GAIN) and _probe_from <= top:
			_floor = _probe_from
			_floor_t = FLOOR_HOLD
			_change(_probe_from, false)
			return
	var budget := 1000.0 / target_fps() * budget_share()
	if gpu_ms > budget * OVER_FACTOR:
		_under = 0
		_over += 1
		if _over >= OVER_EVALS and render_scale > low + 0.001:
			var step := STEP * 2.0 if gpu_ms > budget * FAR_OVER_FACTOR else STEP
			_change(maxf(low, render_scale - step), true)
		return
	_over = 0
	var up := minf(top, render_scale + STEP)
	if up > render_scale + 0.001 and gpu_ms * (up * up) / (render_scale * render_scale) < budget * UP_MARGIN:
		_under += 1
		if _under >= UNDER_EVALS:
			_change(up, false)
	else:
		_under = 0


## Puts a new scale into effect. `probe` = a step down whose gain is checked at the next evaluation.
func _change(to: float, probe: bool) -> void:
	if probe:
		_probe_ms = gpu_ms
		_probe_from = render_scale
	else:
		_probe_ms = -1.0
	render_scale = snappedf(to, 0.05)
	_write(render_scale)
	_over = 0
	_under = 0
	_sum = 0.0
	_count = 0
	_eval_t = 0.0
	_hold_t = SETTLE_TIME


func _write(scale: float) -> void:
	_window.scaling_3d_mode = GraphicsQuality.upscaler(scale, GraphicsQuality.applied_level(get_tree()))
	_window.scaling_3d_scale = scale
