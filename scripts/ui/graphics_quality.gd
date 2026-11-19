class_name GraphicsQuality
extends RefCounted
## Graphics presets (Low, Medium, High = the authored look, Ultra) and the separate options they are made of.
##
## Owner 2026-11-18: every graphics feature is its own setting (Settings > Graphics), the way big PC games list them.
## A preset is a set of choices for those options; changing any option by hand makes the settings "Custom" (the preset
## stays the base, GameSettings.graphics_custom holds the changed options). No preset picks the best choice of every
## option: Ultra leaves the heaviest choices (100 % render resolution, Max shadows, Ultra ambient occlusion and
## reflections, global illumination, 16x filtering, depth of field, motion blur, film grain...) for players who turn
## them up themselves.
##
## apply() puts a preset and its options into effect on the main viewport, the RenderingServer shadow settings, every
## WorldEnvironment in the tree, the sun, the fixture lights (group "fixture_lights"), the screen pass (PostFX) and the
## materials' texture filtering. It can run again at any time: the authored values are kept in metadata the first time
## and every apply starts from them, so going back to High restores the scene exactly as it was made.

enum Level { LOW, MEDIUM, HIGH, ULTRA }

const NAMES: PackedStringArray = ["Low", "Medium", "High", "Ultra"]
## The settings panel's fifth preset button: the player changed options by hand.
const CUSTOM_NAME := "Custom"
const DEFAULT_LEVEL := Level.HIGH
## macOS first launch: Medium. Apple GPUs (M-series) have a fraction of the desktop GPU this look was tuned on.
const MAC_DEFAULT_LEVEL := Level.MEDIUM
## macOS: most 3D pixels each preset renders before MetalFX upscales to the window. A Retina window is 2-4x the
## pixels of 1080p, which is the single biggest cost on a Mac; the UI stays sharp at native resolution.
const MAC_PIXEL_BUDGET: Array[float] = [1280.0 * 720.0, 1600.0 * 900.0, 1920.0 * 1080.0, 2560.0 * 1440.0]
const MAC_MIN_SCALE := 0.5
## One line per preset for the settings panel.
const DESCRIPTIONS: PackedStringArray = [
	"Fastest. Room lights cast no shadows, render at 75 % with FSR upscaling, no reflections or ambient shading.",
	"Balanced. Nearby room lights cast shadows, lighter ambient shading, smaller shadow maps, FXAA.",
	"The look the colony was designed with: all shadows, ambient shading, reflections, 2x MSAA.",
	"Best looking. Volumetric dust haze, sharper and softer shadows, finer reflections, FSR 2 temporal anti-aliasing and upscaling that adapts to hold 60 FPS.",
]
const CUSTOM_DESCRIPTION := "Your own mix: the options below, changed by hand from a preset. Pick a preset to go back to it."

const _META := &"gq_authored"
## The options in effect (key -> value), written by apply().
const _OPTIONS_META := &"gq_options"
## The player's own changes (key -> value), kept on the tree root by GameSettings.apply so a later apply(tree, level)
## (GameMain after the world loads) keeps them.
const PLAYER_META := &"gq_player_options"
## Fixture shadow wanted by the preset (meta), and the perf light view's block on it (meta, see set_fixture_shadow_blocked).
const _FADE_BASE := &"perf_fade_base"
const _VIEW_OFF := &"perf_view_off"
const _SHADOW_BLOCKED := &"perf_shadow_blocked"
## Distance from the camera (m) at which shadowed area lights start to fade out on the presets without a fixture fade.
const ENCLOSED_AREA_FADE := 12.0

## Sections of the Graphics tab, in order.
const SECTIONS: PackedStringArray = ["Image", "Textures", "Lights and shadows", "Detail", "Camera effects"]

## The options, in the order the Graphics tab lists them. Each has:
##   key, section, name, icon (MenuKit pictogram), tip (the tooltip sentence)
##   choices  the names of a "pick one" option, worst to best  - or -  slider [min, max, step] (+ unit) for a number
##   presets  the choice (index, or the number for a slider) of Low, Medium, High, Ultra
## The last choice (or the slider's max) is the option's best.
const OPTIONS: Array[Dictionary] = [
	# ---- Image
	{"key": "aa", "section": "Image", "name": "Anti-aliasing", "icon": &"image",
		"tip": "Smooths jagged edges. FSR 2 rebuilds a sharp picture from a smaller one and smooths it over time (the fastest good-looking choice); MSAA is the classic, heavier kind.",
		"choices": ["Off", "FXAA", "TAA", "MSAA 2x", "MSAA 4x", "MSAA 8x", "FSR 2"], "presets": [0, 1, 3, 6]},
	{"key": "render_scale", "section": "Image", "name": "Render resolution", "icon": &"zoom",
		"tip": "How many pixels the 3D world is drawn with before it is scaled to the screen. Menus and text always stay sharp.",
		"slider": [50, 100, 1], "unit": "%", "presets": [75, 100, 100, 77]},
	{"key": "dynamic_res", "section": "Image", "name": "Adaptive resolution", "icon": &"fast",
		"tip": "Lowers the render resolution a little in heavy rooms to keep the frame rate steady, and raises it again when there is room.",
		"choices": ["Off", "On"], "presets": [0, 0, 0, 1]},
	{"key": "sharpness", "section": "Image", "name": "Sharpness", "icon": &"eye",
		"tip": "Sharpens the finished picture. Too much shows bright edges.",
		"slider": [0, 10, 1], "presets": [0, 0, 0, 0]},
	# ---- Textures
	{"key": "texture", "section": "Textures", "name": "Texture quality", "icon": &"image",
		"tip": "Lower makes surfaces slightly softer and saves a little graphics memory bandwidth.",
		"choices": ["Low", "Medium", "High"], "presets": [1, 2, 2, 2]},
	{"key": "aniso", "section": "Textures", "name": "Texture filtering", "icon": &"eye",
		"tip": "Keeps floors and the ground sharp when you look along them (anisotropic filtering).",
		"choices": ["Off", "2x", "4x", "8x", "16x"], "presets": [1, 2, 3, 3]},
	# ---- Lights and shadows
	{"key": "shadows", "section": "Lights and shadows", "name": "Shadow quality", "icon": &"contrast",
		"tip": "Size and softness of shadows and how far the sun's shadows reach. Low: room lights cast no shadows.",
		"choices": ["Low", "Medium", "High", "Ultra", "Max"], "presets": [0, 1, 2, 3]},
	{"key": "light_range", "section": "Lights and shadows", "name": "Room light distance", "icon": &"bolt",
		"tip": "How far away the colony's room lights are still drawn. Nearer is faster.",
		"choices": ["Near", "Medium", "Full"], "presets": [0, 1, 2, 2]},
	{"key": "ao", "section": "Lights and shadows", "name": "Ambient occlusion", "icon": &"contrast",
		"tip": "Soft shading in corners and where objects meet (SSAO).",
		"choices": ["Off", "Low", "Medium", "High", "Ultra"], "presets": [0, 1, 2, 3]},
	{"key": "ssil", "section": "Lights and shadows", "name": "Indirect light", "icon": &"star",
		"tip": "Light and colour bouncing off nearby surfaces (SSIL).",
		"choices": ["Off", "Low", "Medium", "High", "Ultra"], "presets": [0, 0, 2, 3]},
	{"key": "ssr", "section": "Lights and shadows", "name": "Reflections", "icon": &"image",
		"tip": "Screen-space reflections on floors, glass and metal.",
		"choices": ["Off", "Low", "Medium", "High", "Ultra"], "presets": [0, 0, 2, 3]},
	{"key": "gi", "section": "Lights and shadows", "name": "Global illumination", "icon": &"star",
		"tip": "Real-time bounced light through the whole scene (SDFGI, Godot's stand-in for ray-traced lighting). Very heavy; changes the look of rooms.",
		"choices": ["Off", "On"], "presets": [0, 0, 0, 0]},
	{"key": "fog", "section": "Lights and shadows", "name": "Dust haze", "icon": &"dome",
		"tip": "Volumetric dust in the air that light shines through.",
		"choices": ["Off", "Low", "High", "Ultra"], "presets": [0, 0, 0, 2]},
	# ---- Detail
	{"key": "lod", "section": "Detail", "name": "Level of detail", "icon": &"zoom",
		"tip": "How long distant objects keep their full shape before simpler versions are drawn.",
		"choices": ["Low", "Medium", "High", "Max"], "presets": [0, 1, 1, 2]},
	{"key": "particles", "section": "Detail", "name": "Weather particles", "icon": &"dome",
		"tip": "How many dust particles blow past you in a dust storm.",
		"choices": ["Low", "Medium", "High"], "presets": [0, 1, 2, 2]},
	# ---- Camera effects
	{"key": "post", "section": "Camera effects", "name": "Fullscreen effects", "icon": &"monitor",
		"tip": "The finishing pass over the whole picture: colour grade, chromatic aberration, vignette, film grain and sharpening. Off turns all of them off.",
		"choices": ["Off", "On"], "presets": [1, 1, 1, 1]},
	{"key": "aberration", "section": "Camera effects", "name": "Chromatic aberration", "icon": &"eye",
		"tip": "Faint colour fringes towards the corners, like a real camera lens.",
		"choices": ["Off", "On"], "presets": [1, 1, 1, 1]},
	{"key": "vignette", "section": "Camera effects", "name": "Vignette", "icon": &"eye",
		"tip": "Slightly darker corners.",
		"choices": ["Off", "On"], "presets": [1, 1, 1, 1]},
	{"key": "bloom", "section": "Camera effects", "name": "Bloom", "icon": &"star",
		"tip": "Glow around bright lights and screens.",
		"choices": ["Off", "On", "High"], "presets": [0, 1, 1, 1]},
	{"key": "dof", "section": "Camera effects", "name": "Depth of field", "icon": &"eye",
		"tip": "Blurs things far away, like a camera focused near.",
		"choices": ["Off", "Low", "High"], "presets": [0, 0, 0, 0]},
	{"key": "motion_blur", "section": "Camera effects", "name": "Motion blur", "icon": &"motion",
		"tip": "Blurs the picture while the camera turns or moves. Off whenever Less motion is on.",
		"slider": [0, 10, 1], "presets": [0, 0, 0, 0]},
	{"key": "film_grain", "section": "Camera effects", "name": "Film grain", "icon": &"image",
		"tip": "Fine moving noise over the picture, like film.",
		"slider": [0, 10, 1], "presets": [0, 0, 0, 0]},
]

## Display values that apply() also takes in its options (Settings > Display), with their defaults.
const DISPLAY_DEFAULTS := {"brightness": 50, "contrast": 50, "reduce_motion": false}

# ---- what each choice means

const _AA_MSAA: Array[int] = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X,
	Viewport.MSAA_4X, Viewport.MSAA_8X, Viewport.MSAA_DISABLED]
const AA_FSR2 := 6
const AA_FXAA := 1
const AA_TAA := 2
const _MIP_BIAS: Array[float] = [1.0, 0.5, 0.0]
const _ANISO: Array[int] = [Viewport.ANISOTROPY_DISABLED, Viewport.ANISOTROPY_2X, Viewport.ANISOTROPY_4X,
	Viewport.ANISOTROPY_8X, Viewport.ANISOTROPY_16X]
## Shadow quality Low .. Max. "High" keeps the sun's authored distance and splits.
const _SHADOW := {
	"dir_atlas": [2048, 2048, 4096, 8192, 8192],
	"pos_atlas": [1024, 2048, 4096, 8192, 8192],
	"soft_dir": [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_HIGH, RenderingServer.SHADOW_QUALITY_SOFT_ULTRA],
	"soft_pos": [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_HIGH, RenderingServer.SHADOW_QUALITY_SOFT_ULTRA],
	"sun_dist": [60.0, 100.0, -1.0, 220.0, 300.0],
	"sun_mode": [DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, -1,
		DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS],
	"fixture_shadows": [false, true, true, true, true],
}
## Room light distance Near / Medium / Full: fixture fade begin (0 = never; shadows stop at 60 % of it) and the share of
## their authored range unshadowed area lights (greenhouse grow panels) keep (Low, 2026-11-18: -18 % of the Greenhouse frame).
const _LIGHT_FADE: Array[float] = [15.0, 40.0, 0.0]
const _AREA_RANGE: Array[float] = [0.5, 1.0, 1.0]
## Ambient occlusion and indirect light Off .. Ultra: engine quality and half-size buffers.
const _SSAO_Q: Array[int] = [RenderingServer.ENV_SSAO_QUALITY_VERY_LOW, RenderingServer.ENV_SSAO_QUALITY_LOW,
	RenderingServer.ENV_SSAO_QUALITY_MEDIUM, RenderingServer.ENV_SSAO_QUALITY_HIGH, RenderingServer.ENV_SSAO_QUALITY_ULTRA]
const _SSIL_Q: Array[int] = [RenderingServer.ENV_SSIL_QUALITY_VERY_LOW, RenderingServer.ENV_SSIL_QUALITY_LOW,
	RenderingServer.ENV_SSIL_QUALITY_MEDIUM, RenderingServer.ENV_SSIL_QUALITY_HIGH, RenderingServer.ENV_SSIL_QUALITY_ULTRA]
const _HALF: Array[bool] = [true, true, true, false, false]
## Reflections Off .. Ultra: ray steps (0 = the environment's authored steps; Medium is the authored look).
const _SSR_STEPS: Array[int] = [0, 24, 0, 96, 192]
## Dust haze Off .. Ultra: froxel size and depth.
const _FOG_SIZE: Array[int] = [64, 64, 64, 128]
const _FOG_DEPTH: Array[int] = [32, 32, 64, 96]
const _LOD_PX: Array[float] = [4.0, 2.0, 1.0, 0.5]
const _PARTICLE_SHARE: Array[float] = [0.4, 0.7, 1.0]


## The preset a fresh install starts on for this computer.
static func default_level() -> int:
	return MAC_DEFAULT_LEVEL if OS.has_feature("macos") else DEFAULT_LEVEL


static func level_name(level: int) -> String:
	return NAMES[clampi(level, 0, NAMES.size() - 1)]


## The option with this key, or {}.
static func option(key: String) -> Dictionary:
	for o: Dictionary in OPTIONS:
		if String(o.key) == key:
			return o
	return {}


static func is_slider(o: Dictionary) -> bool:
	return o.has("slider")


## The best choice (index) or the highest number of an option.
static func best(o: Dictionary) -> int:
	return int((o.slider as Array)[1]) if is_slider(o) else (o.choices as Array).size() - 1


## A value made valid for an option: a choice index in range, or a number on the slider.
static func clamp_value(o: Dictionary, v: Variant) -> int:
	if is_slider(o):
		var s: Array = o.slider
		return clampi(int(v), int(s[0]), int(s[1]))
	return clampi(int(v), 0, (o.choices as Array).size() - 1)


## What `level` picks for the option `key`.
static func preset_value(key: String, level: int) -> int:
	var o := option(key)
	return int((o.presets as Array)[clampi(level, 0, Level.ULTRA)]) if not o.is_empty() else 0


## Every option's value for `level` with the player's changes (`custom`, key -> value) on top, plus the display values.
static func options_for(level: int, custom: Dictionary = {}) -> Dictionary:
	var d := {}
	for o: Dictionary in OPTIONS:
		var key := String(o.key)
		d[key] = clamp_value(o, custom[key]) if custom.has(key) else preset_value(key, level)
	for key: String in DISPLAY_DEFAULTS:
		d[key] = custom.get(key, DISPLAY_DEFAULTS[key])
	return d


## The value in effect for `key` (after the last apply), or the High preset's when nothing was applied.
static func current(tree: SceneTree, key: String) -> Variant:
	if tree != null and tree.root != null and tree.root.has_meta(_OPTIONS_META):
		var d: Dictionary = tree.root.get_meta(_OPTIONS_META)
		if d.has(key):
			return d[key]
	return options_for(applied_level(tree) if applied_level(tree) >= 0 else DEFAULT_LEVEL).get(key, 0)


## The engine quality of an Ambient occlusion / Indirect light choice (perf tools).
static func ssao_quality(choice: int) -> RenderingServer.EnvironmentSSAOQuality:
	return _SSAO_Q[clampi(choice, 0, 4)] as RenderingServer.EnvironmentSSAOQuality


static func ssil_quality(choice: int) -> RenderingServer.EnvironmentSSILQuality:
	return _SSIL_Q[clampi(choice, 0, 4)] as RenderingServer.EnvironmentSSILQuality


## Whether the 3D picture uses the temporal upscaler (FSR 2; MetalFX temporal on macOS) right now.
static func is_temporal(tree: SceneTree) -> bool:
	return applied_level(tree) >= 0 and int(current(tree, "aa")) == AA_FSR2


## Whether the player (or the preset) asked for adaptive resolution.
static func is_adaptive(tree: SceneTree) -> bool:
	return applied_level(tree) >= 0 and int(current(tree, "dynamic_res")) == 1


## Share of the weather dust particles to draw (Weather particles option).
static func particle_share(tree: SceneTree) -> float:
	return _PARTICLE_SHARE[clampi(int(current(tree, "particles")), 0, 2)]


## The 3D render scale for `level` on a viewport of `pixels` (width x height). Off macOS this is the preset value.
static func render_scale(level: int, pixels: float, macos := OS.has_feature("macos")) -> float:
	return _scale(float(preset_value("render_scale", level)) / 100.0, level, pixels, macos)


## The 3D render scale in effect on `tree` (the Render resolution option) for a viewport of `pixels`.
static func scale_for(tree: SceneTree, pixels: float) -> float:
	var level := maxi(0, applied_level(tree))
	return _scale(float(current(tree, "render_scale")) / 100.0, level, pixels, OS.has_feature("macos"))


static func _scale(scale: float, level: int, pixels: float, macos: bool) -> float:
	if macos and pixels > 0.0:
		var budget: float = MAC_PIXEL_BUDGET[clampi(level, 0, Level.ULTRA)]
		scale = clampf(minf(scale, sqrt(budget / pixels)), MAC_MIN_SCALE, 1.0)
	return snappedf(clampf(scale, 0.25, 1.0), 0.01)


## The preset last applied to `tree`, or -1. With Custom settings this is the preset they were changed from.
static func applied_level(tree: SceneTree) -> int:
	return int(tree.root.get_meta(_META, -1)) if tree != null and tree.root != null else -1


## How many options `options` (from options_for) has at their best - a preset never has all of them there.
static func count_at_best(options: Dictionary) -> int:
	var n := 0
	for o: Dictionary in OPTIONS:
		if int(options.get(String(o.key), -1)) == best(o):
			n += 1
	return n


## Puts `level` and the options into effect on everything in `tree`. The viewport settings go to `viewport` (default:
## the window). `options` = the player's changes (key -> value, see options_for); null keeps the ones GameSettings.apply
## put on the tree (PLAYER_META), {} is the plain preset.
static func apply(tree: SceneTree, level: int, viewport: Viewport = null, options: Variant = null) -> void:
	level = clampi(level, 0, Level.ULTRA)
	if tree == null or tree.root == null:
		return
	var custom: Dictionary = options if options is Dictionary else tree.root.get_meta(PLAYER_META, {})
	var o := options_for(level, custom)
	var had_level := tree.root.has_meta(_META)
	var was_temporal := is_temporal(tree)
	tree.root.set_meta(_META, level)
	tree.root.set_meta(_OPTIONS_META, o)
	if had_level and not was_temporal and int(o.aa) == AA_FSR2:
		_refresh_particles(tree)
	_apply_viewport(viewport if viewport != null else tree.root, level, o)
	_apply_server(o)
	for we: Node in tree.root.find_children("*", "WorldEnvironment", true, false):
		var w := we as WorldEnvironment
		if w.environment != null:
			_apply_environment(w.environment, o)
		_apply_camera_attributes(w, o)
	for sun: Node in tree.get_nodes_in_group(&"sun"):
		if sun is DirectionalLight3D:
			_apply_sun(sun as DirectionalLight3D, o)
	for light: Node in tree.get_nodes_in_group(&"fixture_lights"):
		if light is Light3D:
			_apply_fixture(light as Light3D, level, o)
	_apply_post(tree, o)
	_apply_texture_filter(tree, int(o.aniso) > 0)
	MotionBlur.set_strength(tree, 0 if bool(o.reduce_motion) else int(o.motion_blur))


## Godot 4.7.2: a GPU particle system that already ran before the game switched from a non-temporal preset to FSR 2
## (Low -> Ultra in Settings, with tapes still out) can be left without its motion-vector buffers: every frame the
## engine then prints 'Parameter "uniform_set" is null' (one tape's sparkles did, measured). Starting a colony on
## Ultra never does. Hiding the particle systems for one drawn frame and showing them again rebuilds them; nothing is
## restarted, so they look the same a frame later.
static func _refresh_particles(tree: SceneTree) -> void:
	if DisplayServer.get_name() == "headless":
		return   # nothing is drawn (and frame_post_draw, which shows them again, may never come)
	var hidden: Array[GPUParticles3D] = []
	for n: Node in tree.root.find_children("*", "GPUParticles3D", true, false):
		var p := n as GPUParticles3D
		if p.visible:
			p.visible = false
			hidden.append(p)
	if hidden.is_empty():
		return
	RenderingServer.frame_post_draw.connect(func() -> void:
		for p: GPUParticles3D in hidden:
			if is_instance_valid(p):
				p.visible = true, CONNECT_ONE_SHOT)


static func _apply_viewport(vp: Viewport, level: int, o: Dictionary) -> void:
	var aa := int(o.aa)
	vp.msaa_3d = _AA_MSAA[aa] as Viewport.MSAA
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == AA_FXAA else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = aa == AA_TAA
	_apply_scale(vp, level, o)
	if OS.has_feature("macos") and not vp.has_meta(&"gq_resize_hook"):
		# a Retina window that is resized or moved to another screen gets its render scale recomputed
		vp.set_meta(&"gq_resize_hook", true)
		vp.size_changed.connect(func() -> void:
			_apply_scale(vp, int(vp.get_meta(_META, level)), vp.get_meta(_OPTIONS_META, o)))
	vp.set_meta(_META, level)
	vp.set_meta(_OPTIONS_META, o)
	vp.mesh_lod_threshold = _LOD_PX[clampi(int(o.lod), 0, 3)]
	vp.positional_shadow_atlas_size = int(_SHADOW.pos_atlas[int(o.shadows)])
	vp.texture_mipmap_bias = _MIP_BIAS[clampi(int(o.texture), 0, 2)]
	vp.anisotropic_filtering_level = _ANISO[clampi(int(o.aniso), 0, 4)] as Viewport.AnisotropicFiltering


static func _apply_scale(vp: Viewport, level: int, o: Dictionary) -> void:
	var size: Vector2i = (vp as Window).size if vp is Window else (vp as SubViewport).size if vp is SubViewport else Vector2i.ZERO
	var scale := _scale(float(o.render_scale) / 100.0, level, float(size.x) * float(size.y), OS.has_feature("macos"))
	vp.scaling_3d_mode = upscaler(scale, int(o.aa) == AA_FSR2)
	vp.scaling_3d_scale = scale


## The upscaler for a render scale: MetalFX on macOS (Apple's own, sharper than FSR 1 on Apple GPUs), FSR elsewhere,
## plain bilinear at full resolution. `temporal` (Anti-aliasing: FSR 2) always uses the temporal upscaler (FSR 2,
## MetalFX temporal on macOS), which is also the anti-aliasing. DynamicResolution uses this too.
static func upscaler(scale: float, temporal := false) -> Viewport.Scaling3DMode:
	if temporal:
		return Viewport.SCALING_3D_MODE_METALFX_TEMPORAL if OS.has_feature("macos") else Viewport.SCALING_3D_MODE_FSR2
	if scale >= 0.999:
		return Viewport.SCALING_3D_MODE_BILINEAR
	return Viewport.SCALING_3D_MODE_METALFX_SPATIAL if OS.has_feature("macos") else Viewport.SCALING_3D_MODE_FSR


static func _apply_server(o: Dictionary) -> void:
	var s := int(o.shadows)
	RenderingServer.directional_shadow_atlas_set_size(int(_SHADOW.dir_atlas[s]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(_SHADOW.soft_dir[s]) as RenderingServer.ShadowQuality)
	RenderingServer.positional_soft_shadow_filter_set_quality(int(_SHADOW.soft_pos[s]) as RenderingServer.ShadowQuality)
	var ao := int(o.ao)
	var ssil := int(o.ssil)
	RenderingServer.environment_set_ssao_quality(_SSAO_Q[ao] as RenderingServer.EnvironmentSSAOQuality, _HALF[ao], 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(_SSIL_Q[ssil] as RenderingServer.EnvironmentSSILQuality, _HALF[ssil], 0.5, 4, 50.0, 300.0)
	var fog := int(o.fog)
	RenderingServer.environment_set_volumetric_fog_volume_size(_FOG_SIZE[fog], _FOG_DEPTH[fog])
	RenderingServer.environment_set_volumetric_fog_filter_active(fog >= 2)
	var dof := int(o.dof)
	RenderingServer.camera_attributes_set_dof_blur_quality(
		RenderingServer.DOF_BLUR_QUALITY_HIGH if dof >= 2 else RenderingServer.DOF_BLUR_QUALITY_LOW, dof >= 2)


static func _apply_environment(env: Environment, o: Dictionary) -> void:
	if not env.has_meta(_META):
		env.set_meta(_META, {"ssao": env.ssao_enabled, "ssil": env.ssil_enabled, "ssr": env.ssr_enabled,
			"ssr_steps": env.ssr_max_steps, "glow": env.glow_enabled, "vol_fog": env.volumetric_fog_enabled,
			"glow_intensity": env.glow_intensity, "glow_bloom": env.glow_bloom, "sdfgi": env.sdfgi_enabled,
			"adjust": env.adjustment_enabled, "brightness": env.adjustment_brightness, "contrast": env.adjustment_contrast})
	var a: Dictionary = env.get_meta(_META)
	env.ssao_enabled = bool(a.ssao) and int(o.ao) > 0
	env.ssil_enabled = bool(a.ssil) and int(o.ssil) > 0
	var ssr := int(o.ssr)
	env.ssr_enabled = bool(a.ssr) and ssr > 0
	env.ssr_max_steps = maxi(int(a.ssr_steps), _SSR_STEPS[ssr]) if ssr >= 3 else (_SSR_STEPS[ssr] if ssr == 1 else int(a.ssr_steps))
	var bloom := int(o.bloom)
	env.glow_enabled = bool(a.glow) and bloom > 0
	env.glow_intensity = float(a.glow_intensity) * (1.4 if bloom >= 2 else 1.0)
	env.glow_bloom = float(a.glow_bloom) * (2.0 if bloom >= 2 else 1.0)
	# Dust haze: the environment already carries its settings (density, albedo, length); off where it has none.
	env.volumetric_fog_enabled = int(o.fog) > 0 and (env.volumetric_fog_density > 0.0 or bool(a.vol_fog))
	env.sdfgi_enabled = bool(a.sdfgi) or int(o.gi) > 0
	# Settings > Display brightness and contrast: 50 = as authored, 0..100 = 60 % .. 140 % (contrast 70 % .. 130 %).
	var b := float(o.get("brightness", 50)) / 50.0 - 1.0
	var c := float(o.get("contrast", 50)) / 50.0 - 1.0
	env.adjustment_enabled = bool(a.adjust) or not is_zero_approx(b) or not is_zero_approx(c)
	env.adjustment_brightness = float(a.brightness) * (1.0 + 0.4 * b)
	env.adjustment_contrast = float(a.contrast) * (1.0 + 0.3 * c)


## Depth of field (far blur) through the WorldEnvironment's camera attributes. The authored attributes (none in this
## world) are kept and put back when it is off.
static func _apply_camera_attributes(w: WorldEnvironment, o: Dictionary) -> void:
	var dof := int(o.dof)
	if not w.has_meta(_META):
		w.set_meta(_META, {"attributes": w.camera_attributes})
	var authored: CameraAttributes = w.get_meta(_META).get("attributes")
	if dof == 0:
		if w.camera_attributes != authored:
			w.camera_attributes = authored
		return
	var ca := w.camera_attributes as CameraAttributesPractical
	if ca == null or ca == authored:
		ca = (authored.duplicate() as CameraAttributesPractical) if authored is CameraAttributesPractical else CameraAttributesPractical.new()
		w.camera_attributes = ca
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = 45.0 if dof == 1 else 28.0
	ca.dof_blur_far_transition = 25.0 if dof == 1 else 15.0
	ca.dof_blur_amount = 0.06 if dof == 1 else 0.1


static func _apply_sun(sun: DirectionalLight3D, o: Dictionary) -> void:
	if not sun.has_meta(_META):
		sun.set_meta(_META, {"dist": sun.directional_shadow_max_distance, "mode": sun.directional_shadow_mode})
	var a: Dictionary = sun.get_meta(_META)
	var s := int(o.shadows)
	var dist := float(_SHADOW.sun_dist[s])
	var mode := int(_SHADOW.sun_mode[s])
	sun.directional_shadow_max_distance = float(a.dist) if dist < 0.0 else dist
	sun.directional_shadow_mode = (int(a.mode) if mode < 0 else mode) as DirectionalLight3D.ShadowMode


## The world's screen pass (CanvasLayer "PostFX" with a post_fx.gdshader rect): Fullscreen effects off hides it (one
## full-screen pass less); chromatic aberration and vignette go to 0 when off; film grain and sharpness are added.
static func _apply_post(tree: SceneTree, o: Dictionary) -> void:
	for layer: Node in tree.root.find_children("PostFX", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = int(o.post) == 1
		for rect: Node in layer.get_children():
			var mat := (rect as CanvasItem).material as ShaderMaterial if rect is CanvasItem else null
			if mat == null:
				continue
			if not mat.has_meta(_META):
				mat.set_meta(_META, {"vignette": mat.get_shader_parameter("vignette"), "dispersion": mat.get_shader_parameter("dispersion")})
			var a: Dictionary = mat.get_meta(_META)
			mat.set_shader_parameter("vignette", float(a.vignette if a.vignette != null else 0.22) if int(o.vignette) == 1 else 0.0)
			mat.set_shader_parameter("dispersion", float(a.dispersion if a.dispersion != null else 0.006) if int(o.aberration) == 1 else 0.0)
			mat.set_shader_parameter("grain", float(o.film_grain) / 10.0)
			mat.set_shader_parameter("sharpen", float(o.sharpness) / 10.0)


## Texture filtering: anisotropic filtering only works on materials that ask for it, so with it on every standard
## material that uses plain mipmapped filtering is switched to the anisotropic kind (and back when it is off). Shader
## materials (the colony's own) choose their filtering in the shader.
static func _apply_texture_filter(tree: SceneTree, on: bool) -> void:
	if bool(tree.root.get_meta(&"gq_aniso_materials", false)) == on and not on:
		return
	tree.root.set_meta(&"gq_aniso_materials", on)
	var seen := {}
	for n: Node in tree.root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		_filter_material(g.material_override, on, seen)
		var mi := g as MeshInstance3D
		if mi != null and mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				_filter_material(mi.get_surface_override_material(s), on, seen)
				_filter_material(mi.mesh.surface_get_material(s), on, seen)


static func _filter_material(m: Material, on: bool, seen: Dictionary) -> void:
	var bm := m as BaseMaterial3D
	if bm == null or seen.has(bm):
		return
	seen[bm] = true
	if on and bm.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
		bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		bm.set_meta(&"gq_aniso", true)
	elif not on and bm.has_meta(&"gq_aniso"):
		bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		bm.remove_meta(&"gq_aniso")


## Perf light view: blocks (or lifts the block on) a fixture light's shadow map. The block never touches
## shadow_enabled: in Godot 4.7, switching shadow_enabled on a light paired with meshes (soft shadows, light_size > 0)
## leaves the engine's per-mesh soft-shadow count wrong, and later switches of that light print
## "geom->softshadow_count==0 - BUG!" with a script backtrace (2026-11-18 snap-turn probe). It sets the light's shadow
## fade distance to 0 m instead (no shadow map is drawn; the light keeps its full reach). Lifting the block puts the
## preset's fade back (_FADE_BASE, written by _apply_fixture).
static func set_fixture_shadow_blocked(light: Light3D, blocked: bool) -> void:
	if light == null or bool(light.get_meta(_SHADOW_BLOCKED, false)) == blocked:
		return
	light.set_meta(_SHADOW_BLOCKED, blocked)
	_apply_light_fade(light)


## Perf light view: switches a fixture light off (or back on) through its distance fade instead of `visible`. A light
## made visible again is re-paired by Godot with every mesh in its reach (~1-1.5 ms of CPU per light here: a snap turn
## that lit 5 rooms cost a 28-33 ms frame); a light past its fade is skipped at draw time and stays paired.
static func set_fixture_view_off(light: Light3D, off: bool) -> void:
	if light == null or bool(light.get_meta(_VIEW_OFF, false)) == off:
		return
	light.set_meta(_VIEW_OFF, off)
	_apply_light_fade(light)


static func is_fixture_view_off(light: Light3D) -> bool:
	return bool(light.get_meta(_VIEW_OFF, false))


## The light's distance fade = the preset's (saved in _FADE_BASE) with the light view's overrides on top.
static func _apply_light_fade(light: Light3D) -> void:
	if not light.has_meta(_FADE_BASE):
		light.set_meta(_FADE_BASE, [light.distance_fade_enabled, light.distance_fade_begin, light.distance_fade_shadow,
			light.distance_fade_length])
	var b: Array = light.get_meta(_FADE_BASE)
	var enabled := bool(b[0])
	var begin := float(b[1])
	var shadow := float(b[2])
	var length := float(b[3])
	if bool(light.get_meta(_SHADOW_BLOCKED, false)):
		if not enabled:
			begin = 100000.0   # the light keeps its full reach
			length = 1.0
		enabled = true
		shadow = 0.0
	if bool(light.get_meta(_VIEW_OFF, false)):
		# off: past its fade at any distance, so the renderer skips it; it stays paired with the meshes
		enabled = true
		begin = 0.0
		length = 0.001
		shadow = 0.0
	light.distance_fade_enabled = enabled
	light.distance_fade_begin = begin
	light.distance_fade_shadow = shadow
	light.distance_fade_length = length



static func _apply_fixture(light: Light3D, level: int, o: Dictionary) -> void:
	if not light.has_meta(_META):
		light.set_meta(_META, {"shadow": light.shadow_enabled, "fade": light.distance_fade_enabled,
			"begin": light.distance_fade_begin, "shadow_fade": light.distance_fade_shadow, "length": light.distance_fade_length,
			"area_range": float(light.get("area_range")) if light.get_class() == "AreaLight3D" else 0.0})
	var a: Dictionary = light.get_meta(_META)
	var reach := clampi(int(o.light_range), 0, 2)
	if light.get_class() == "AreaLight3D" and float(a.get("area_range", 0.0)) > 0.0:
		light.set("area_range", float(a.area_range) * (1.0 if bool(a.shadow) else _AREA_RANGE[reach]))
	light.shadow_enabled = bool(a.shadow) and bool(_SHADOW.fixture_shadows[int(o.shadows)])
	var fade: float = _LIGHT_FADE[reach]
	if fade > 0.0:
		light.distance_fade_enabled = true
		light.distance_fade_begin = fade
		light.distance_fade_length = 8.0
		light.distance_fade_shadow = fade * 0.6
	elif level == Level.ULTRA and bool(a.shadow) and light.get_class() == "AreaLight3D" and not bool(a.fade):
		# Shadowed area lights (the four exit tunnel panels, 30 m range) light only the inside of the tunnel, their own
		# shadows keep the light in, yet their 30 m reach made every view near the tunnel pay for them: 15 ms of a 44 ms
		# frame outdoors at Ultra, 1440p, with no visible change when they are off (docs/perf/ultra_60fps.md). Full
		# strength within 12 m of the camera (the whole tunnel), faded out by 18 m (2026-11-18). Ultra only: High stays the authored scene,
		# Medium and Low fade every fixture already.
		light.distance_fade_enabled = true
		light.distance_fade_begin = ENCLOSED_AREA_FADE
		light.distance_fade_length = 6.0
		light.distance_fade_shadow = ENCLOSED_AREA_FADE
	else:
		light.distance_fade_enabled = bool(a.fade)
		light.distance_fade_begin = float(a.begin)
		light.distance_fade_shadow = float(a.shadow_fade)
		light.distance_fade_length = float(a.length)
	# the preset's fade is the base; the light view's shadow block (if any) goes back on top
	light.set_meta(_FADE_BASE, [light.distance_fade_enabled, light.distance_fade_begin, light.distance_fade_shadow,
		light.distance_fade_length])
	_apply_light_fade(light)
