class_name GraphicsQuality
extends RefCounted
## Graphics presets: Low, Medium, High (the authored look) and Ultra.
## apply() puts a preset into effect on the main viewport, the RenderingServer shadow settings, every WorldEnvironment
## in the tree, the sun and the fixture lights (group "fixture_lights"). It can run again at any time: the authored
## values of environments and lights are kept in metadata the first time and every preset starts from them, so going
## back to High restores the scene exactly as it was made.

enum Level { LOW, MEDIUM, HIGH, ULTRA }

const NAMES: PackedStringArray = ["Low", "Medium", "High", "Ultra"]
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
	"Best looking. Volumetric dust haze, sharper and softer shadows, finer reflections, 4x MSAA. Needs a strong GPU.",
]

const _META := &"gq_authored"

## Settings per preset, LOW .. ULTRA.
const _P := {
	# viewport
	"msaa": [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X],
	"fxaa": [false, true, false, false],
	"scale": [0.75, 1.0, 1.0, 1.0],
	"lod_px": [4.0, 2.0, 2.0, 1.0],
	"pos_atlas": [1024, 2048, 4096, 8192],
	# rendering server
	"dir_atlas": [2048, 2048, 4096, 8192],
	"soft_dir": [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_HIGH],
	"soft_pos": [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_HIGH],
	"ssao_q": [RenderingServer.ENV_SSAO_QUALITY_VERY_LOW, RenderingServer.ENV_SSAO_QUALITY_LOW,
		RenderingServer.ENV_SSAO_QUALITY_MEDIUM, RenderingServer.ENV_SSAO_QUALITY_HIGH],
	"ssil_q": [RenderingServer.ENV_SSIL_QUALITY_VERY_LOW, RenderingServer.ENV_SSIL_QUALITY_LOW,
		RenderingServer.ENV_SSIL_QUALITY_MEDIUM, RenderingServer.ENV_SSIL_QUALITY_HIGH],
	"vol_size": [64, 64, 64, 64],
	"vol_depth": [32, 32, 64, 64],
	# environment (multiplies or replaces the authored value)
	"ssao": [false, true, true, true],
	"ssil": [false, false, true, true],
	"ssr": [false, false, true, true],
	"ssr_steps": [0, 0, 48, 96],
	"glow": [false, true, true, true],
	"vol_fog": [false, false, false, true],
	# lights
	"sun_dist": [60.0, 100.0, 160.0, 220.0],
	"sun_mode": [DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS],
	"fixture_shadows": [false, true, true, true],
	## fixture lights fade out past this distance (0 = never); their shadows stop at 60 % of it
	"fixture_fade": [25.0, 40.0, 0.0, 0.0],
}


## The preset a fresh install starts on for this computer.
static func default_level() -> int:
	return MAC_DEFAULT_LEVEL if OS.has_feature("macos") else DEFAULT_LEVEL


## The 3D render scale for `level` on a viewport of `pixels` (width x height). Off macOS this is the preset value.
static func render_scale(level: int, pixels: float, macos := OS.has_feature("macos")) -> float:
	var scale: float = value("scale", level)
	if macos and pixels > 0.0:
		var budget: float = MAC_PIXEL_BUDGET[clampi(level, 0, Level.ULTRA)]
		scale = clampf(minf(scale, sqrt(budget / pixels)), MAC_MIN_SCALE, 1.0)
	return snappedf(scale, 0.01)


static func level_name(level: int) -> String:
	return NAMES[clampi(level, 0, NAMES.size() - 1)]


## The value of one preset setting (tests and the panel read these).
static func value(key: String, level: int) -> Variant:
	return (_P[key] as Array)[clampi(level, 0, Level.ULTRA)]


## The preset last applied to `tree`, or -1.
static func applied_level(tree: SceneTree) -> int:
	return int(tree.root.get_meta(_META, -1)) if tree != null and tree.root != null else -1


## Puts `level` into effect on everything in `tree`. The viewport settings go to `viewport` (default: the window).
static func apply(tree: SceneTree, level: int, viewport: Viewport = null) -> void:
	level = clampi(level, 0, Level.ULTRA)
	if tree == null or tree.root == null:
		return
	tree.root.set_meta(_META, level)
	_apply_viewport(viewport if viewport != null else tree.root, level)
	_apply_server(level)
	for we: Node in tree.root.find_children("*", "WorldEnvironment", true, false):
		var env := (we as WorldEnvironment).environment
		if env != null:
			_apply_environment(env, level)
	for sun: Node in tree.get_nodes_in_group(&"sun"):
		if sun is DirectionalLight3D:
			_apply_sun(sun as DirectionalLight3D, level)
	for light: Node in tree.get_nodes_in_group(&"fixture_lights"):
		if light is Light3D:
			_apply_fixture(light as Light3D, level)


static func _apply_viewport(vp: Viewport, level: int) -> void:
	vp.msaa_3d = value("msaa", level)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if value("fxaa", level) else Viewport.SCREEN_SPACE_AA_DISABLED
	_apply_scale(vp, level)
	if OS.has_feature("macos") and not vp.has_meta(&"gq_resize_hook"):
		# a Retina window that is resized or moved to another screen gets its render scale recomputed
		vp.set_meta(&"gq_resize_hook", true)
		vp.size_changed.connect(func() -> void: _apply_scale(vp, int(vp.get_meta(_META, level))))
	vp.set_meta(_META, level)
	vp.mesh_lod_threshold = value("lod_px", level)
	vp.positional_shadow_atlas_size = value("pos_atlas", level)


static func _apply_scale(vp: Viewport, level: int) -> void:
	var size: Vector2i = (vp as Window).size if vp is Window else (vp as SubViewport).size if vp is SubViewport else Vector2i.ZERO
	var scale := render_scale(level, float(size.x) * float(size.y))
	vp.scaling_3d_mode = upscaler(scale)
	vp.scaling_3d_scale = scale


## The upscaler for a render scale: MetalFX on macOS (Apple's own, sharper than FSR 1 on Apple GPUs), FSR elsewhere,
## plain bilinear at full resolution. DynamicResolution uses this too.
static func upscaler(scale: float) -> Viewport.Scaling3DMode:
	if scale >= 0.999:
		return Viewport.SCALING_3D_MODE_BILINEAR
	return Viewport.SCALING_3D_MODE_METALFX_SPATIAL if OS.has_feature("macos") else Viewport.SCALING_3D_MODE_FSR


static func _apply_server(level: int) -> void:
	RenderingServer.directional_shadow_atlas_set_size(value("dir_atlas", level), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(value("soft_dir", level))
	RenderingServer.positional_soft_shadow_filter_set_quality(value("soft_pos", level))
	# half-size buffers (the engine default) everywhere but Ultra
	RenderingServer.environment_set_ssao_quality(value("ssao_q", level), level < Level.ULTRA, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(value("ssil_q", level), level < Level.ULTRA, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_set_volumetric_fog_volume_size(value("vol_size", level), value("vol_depth", level))
	RenderingServer.environment_set_volumetric_fog_filter_active(level >= Level.HIGH)


static func _apply_environment(env: Environment, level: int) -> void:
	if not env.has_meta(_META):
		env.set_meta(_META, {"ssao": env.ssao_enabled, "ssil": env.ssil_enabled, "ssr": env.ssr_enabled,
			"ssr_steps": env.ssr_max_steps, "glow": env.glow_enabled, "vol_fog": env.volumetric_fog_enabled})
	var a: Dictionary = env.get_meta(_META)
	env.ssao_enabled = bool(a.ssao) and value("ssao", level)
	env.ssil_enabled = bool(a.ssil) and value("ssil", level)
	env.ssr_enabled = bool(a.ssr) and value("ssr", level)
	env.ssr_max_steps = maxi(int(a.ssr_steps), int(value("ssr_steps", level))) if level == Level.ULTRA else int(a.ssr_steps)
	env.glow_enabled = bool(a.glow) and value("glow", level)
	# Ultra turns on the dust haze the environment already carries settings for (density, albedo, length).
	env.volumetric_fog_enabled = (bool(a.vol_fog) and level >= Level.HIGH) or (value("vol_fog", level) and env.volumetric_fog_density > 0.0)


static func _apply_sun(sun: DirectionalLight3D, level: int) -> void:
	if not sun.has_meta(_META):
		sun.set_meta(_META, {"dist": sun.directional_shadow_max_distance, "mode": sun.directional_shadow_mode})
	var a: Dictionary = sun.get_meta(_META)
	sun.directional_shadow_max_distance = float(a.dist) if level == Level.HIGH else float(value("sun_dist", level))
	sun.directional_shadow_mode = int(a.mode) if level == Level.HIGH else int(value("sun_mode", level))


static func _apply_fixture(light: Light3D, level: int) -> void:
	if not light.has_meta(_META):
		light.set_meta(_META, {"shadow": light.shadow_enabled, "fade": light.distance_fade_enabled,
			"begin": light.distance_fade_begin, "shadow_fade": light.distance_fade_shadow, "length": light.distance_fade_length})
	var a: Dictionary = light.get_meta(_META)
	light.shadow_enabled = bool(a.shadow) and value("fixture_shadows", level)
	var fade: float = value("fixture_fade", level)
	if fade > 0.0:
		light.distance_fade_enabled = true
		light.distance_fade_begin = fade
		light.distance_fade_length = 8.0
		light.distance_fade_shadow = fade * 0.6
	else:
		light.distance_fade_enabled = bool(a.fade)
		light.distance_fade_begin = float(a.begin)
		light.distance_fade_shadow = float(a.shadow_fade)
		light.distance_fade_length = float(a.length)
