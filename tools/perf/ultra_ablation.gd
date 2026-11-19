extends "res://tools/perf/perf_bench.gd"
## Feature cost check at any preset (default Ultra), diagnostic only, nothing is saved. WINDOWED (needs the GPU).
##
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/perf/ultra_ablation.gd -- \
##       --quality=3 --window=2560x1369 --frames=60 --views=room_greenhouse,plaza_through_glass \
##       [--cases=base,no_vol_fog,...] --out=G:/nasa app/_perf/ultra_ablation.json
##
## For each view the camera is held still; the same frames are measured with the base preset, then with one change
## at a time. Every case starts again from the base preset and restores what it touched, so the difference to "base"
## is that change's cost in this view under the same GPU conditions.

const ALL_CASES := ["base", "no_vol_fog", "msaa_2x", "msaa_off", "ssao_half", "ssil_half", "ssil_off", "ssao_off",
	"ssr_off", "glow_off", "pos_atlas_4096", "soft_pos_low", "soft_dir_low", "dir_atlas_4096", "no_fixture_shadows",
	"no_area_lights", "no_fixture_lights", "no_sun_shadow", "lod_px_2", "scale_077_fsr2", "high", "base_again"]

var _cases: Array = []
var _ab_view := -1
var _ab_case := 0
var _ab_frames: Array = []
var _ab_wait := 0
var _ab_out: Array = []
var _saved := {}
var _base := 3


func _process(delta: float) -> bool:
	if _phase == "next":
		_base = int(_args.get("quality", "3"))
		_cases = ALL_CASES.duplicate() if not _args.has("cases") else Array(String(_args.cases).split(","))
		_phase = "ablate"
		_ab_view = -1
		_next_view()
		return false
	if _phase != "ablate":
		return super(delta)
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_us) / 1000.0
	_last_us = now
	if _ab_wait > 0:
		_ab_wait -= 1
		return false
	_ab_frames.append(_sample(frame_ms))
	if _ab_frames.size() < int(_args.get("frames", "60")):
		return false
	var s := _summarise(_views[_ab_view], _ab_frames)
	s["case"] = _cases[_ab_case]
	if _args.has("shots"):
		# one still per view and case, for comparing what a change does to the picture
		var dir: String = _args.shots
		DirAccess.make_dir_recursive_absolute(dir)
		root.get_texture().get_image().save_png(dir.path_join("%s__%s.png" % [_views[_ab_view].name, _cases[_ab_case]]))
	_ab_out.append(s)
	print("CASE ", _views[_ab_view].name, " ", _cases[_ab_case], " frame ", snappedf(s.summary.frame_ms.mean, 0.1),
		" gpu ", snappedf(s.summary.gpu_ms.mean, 0.1), " cpu ", snappedf(s.summary.cpu_ms.mean, 0.1),
		" draws ", int(s.summary.draw_calls.mean), " prims ", snappedf(s.summary.primitives.mean / 1e6, 0.01), "M")
	_ab_case += 1
	if _ab_case >= _cases.size():
		if not _next_view():
			_write()
			return true
	else:
		_start_case()
	return false


func _next_view() -> bool:
	_ab_view += 1
	if _ab_view >= _views.size():
		return false
	_enter_view(_views[_ab_view])
	if _args.has("yaw"):
		(_game.get("player") as PlayerController).camera_rig().add_look(deg_to_rad(float(_args.yaw)), 0.0)
	_ab_case = 0
	_start_case()
	_ab_wait = 60
	return true


func _envs() -> Array:
	return root.find_children("*", "WorldEnvironment", true, false).map(func(w: Node) -> Environment: return (w as WorldEnvironment).environment)


func _start_case() -> void:
	_restore()
	GraphicsQuality.apply(self, _base)
	var lights := get_nodes_in_group(&"fixture_lights")
	# "a+b" applies both changes
	for c: String in String(_cases[_ab_case]).split("+"):
		_apply_case(c, lights)
	_ab_frames = []
	_ab_wait = 30


func _apply_case(c: String, lights: Array[Node]) -> void:
	match c:
		"no_vol_fog":
			for e: Environment in _envs():
				_ab_set(e, "volumetric_fog_enabled", false)
		"msaa_2x":
			root.msaa_3d = Viewport.MSAA_2X
		"msaa_off":
			root.msaa_3d = Viewport.MSAA_DISABLED
		"ssao_half":
			RenderingServer.environment_set_ssao_quality(GraphicsQuality.value("ssao_q", _base), true, 0.5, 2, 50.0, 300.0)
		"ssil_half":
			RenderingServer.environment_set_ssil_quality(GraphicsQuality.value("ssil_q", _base), true, 0.5, 4, 50.0, 300.0)
		"ssil_off", "ssao_off", "ssr_off", "glow_off":
			var prop: String = {"ssil_off": "ssil_enabled", "ssao_off": "ssao_enabled", "ssr_off": "ssr_enabled", "glow_off": "glow_enabled"}[c]
			for e: Environment in _envs():
				_ab_set(e, prop, false)
		"pos_atlas_4096":
			root.positional_shadow_atlas_size = 4096
		"soft_pos_low":
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		"soft_dir_low":
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		"dir_atlas_4096":
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
		"no_fixture_shadows":
			for l: Node in lights:
				_ab_set(l, "shadow_enabled", false)
		"no_area_lights":
			for l: Node in lights:
				if l.get_class() == "AreaLight3D":
					_ab_set(l, "visible", false)
		"no_fixture_lights":
			for l: Node in lights:
				_ab_set(l, "visible", false)
		"no_sun_shadow":
			for l: Node in get_nodes_in_group(&"sun"):
				_ab_set(l, "shadow_enabled", false)
		"lod_px_2":
			root.mesh_lod_threshold = 2.0
		"scale_077_fsr2":
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			root.scaling_3d_scale = 0.77
		"high":
			GraphicsQuality.apply(self, GraphicsQuality.Level.HIGH)
		# light experiments (not in the default list; pick them with --cases)
		"cur_zone_lights_only":
			var zm: ZoneManager = (_game.get_node("Perf") as PerfRig).zone_manager
			var cur := ColonyZones.slug(String(zm.current.zone_id)) if zm.current != null else ""
			for l: Node in lights:
				if ColonyZones.slug(String(l.get_meta("zone", ""))) != cur and l.get_parent().name != cur:
					_ab_set(l, "visible", false)
		"sun_160", "sun_2splits", "sun_80", "sun_60":
			for s: Node in get_nodes_in_group(&"sun"):
				if c in ["sun_160", "sun_80", "sun_60"]:
					_ab_set(s, "directional_shadow_max_distance", {"sun_160": 160.0, "sun_80": 80.0, "sun_60": 60.0}[c])
				else:
					_ab_set(s, "directional_shadow_mode", DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
		"other_zone_noshadow":
			var zm3: ZoneManager = (_game.get_node("Perf") as PerfRig).zone_manager
			var cur3 := ColonyZones.slug(String(zm3.current.zone_id)) if zm3.current != null else ""
			for l: Node in lights:
				if ColonyZones.slug(String(l.get_meta("zone", ""))) != cur3:
					_ab_set(l, "shadow_enabled", false)
		"gh_area_x07", "gh_area_x05":
			for l: Node in lights:
				if l.get_class() == "AreaLight3D" and not bool(l.get("shadow_enabled")):
					_ab_set(l, "area_range", float(l.get("area_range")) * (0.7 if c == "gh_area_x07" else 0.5))
		"fade_15":
			for l: Node in lights:
				if bool(l.get("distance_fade_enabled")):
					_ab_set(l, "distance_fade_begin", 15.0)
					_ab_set(l, "distance_fade_shadow", 9.0)
		"scale_050":
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			root.scaling_3d_scale = 0.5
		"lod_px_4":
			root.mesh_lod_threshold = 4.0
		"tunnel_fade":
			for l: Node in lights:
				if l.get_class() == "AreaLight3D" and String(l.name).begins_with("FX_SFX_tunnel"):
					_ab_set(l, "distance_fade_enabled", true)
					_ab_set(l, "distance_fade_begin", 20.0)
					_ab_set(l, "distance_fade_length", 10.0)
					_ab_set(l, "distance_fade_shadow", 20.0)
		"tunnel_range_15", "tunnel_noshadow", "tunnel_both", "tunnel_off":
			for l: Node in lights:
				if l.get_class() != "AreaLight3D" or not String(l.name).begins_with("FX_SFX_tunnel"):
					continue
				if c == "tunnel_off":
					_ab_set(l, "visible", false)
				if c == "tunnel_range_15" or c == "tunnel_both":
					_ab_set(l, "area_range", 15.0)
				if c == "tunnel_noshadow" or c == "tunnel_both":
					_ab_set(l, "shadow_enabled", false)
		"other_mask_zero":
			var zm2: ZoneManager = (_game.get_node("Perf") as PerfRig).zone_manager
			var cur2 := ColonyZones.slug(String(zm2.current.zone_id)) if zm2.current != null else ""
			for l: Node in lights:
				if ColonyZones.slug(String(l.get_meta("zone", ""))) != cur2:
					_ab_set(l, "light_cull_mask", 0)
		"range_x07":
			for l: Node in lights:
				if l is SpotLight3D:
					_ab_set(l, "spot_range", (l as SpotLight3D).spot_range * 0.7)
				elif l.get_class() == "AreaLight3D":
					_ab_set(l, "area_range", float(l.get("area_range")) * 0.7)
		"spot_angle_x08", "spot_angle_x09":
			for l: Node in lights:
				if l is SpotLight3D:
					_ab_set(l, "spot_angle", (l as SpotLight3D).spot_angle * (0.8 if c == "spot_angle_x08" else 0.9))
		"no_light_size":
			for l: Node in lights:
				_ab_set(l, "light_size", 0.0)
		"no_specular":
			for l: Node in lights:
				_ab_set(l, "light_specular", 0.0)
		"fsr2_067":
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			root.scaling_3d_scale = 0.67
		"fsr2_067_nomsaa", "fsr2_077_nomsaa", "fsr2_059_nomsaa":
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			root.scaling_3d_scale = {"fsr2_067_nomsaa": 0.67, "fsr2_077_nomsaa": 0.77, "fsr2_059_nomsaa": 0.59}[c]
			root.msaa_3d = Viewport.MSAA_DISABLED
		"fsr1_077":
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			root.scaling_3d_scale = 0.77
		"lv_hops1":
			_ab_set(root.get_node("PerfSettings"), "light_view_hops", 1)
		"light_view_off":
			_ab_set(root.get_node("PerfSettings"), "light_view_enabled", false)
		"postfx_off":
			for n: Node in root.find_children("PostFX", "", true, false):
				_ab_set(n, "visible", false)
		"taa_nomsaa":
			root.msaa_3d = Viewport.MSAA_DISABLED
			root.use_taa = true


func _ab_set(o: Object, prop: String, v: Variant) -> void:
	var key := [o, prop]
	if not _saved.has(key):
		_saved[key] = o.get(prop)
	o.set(prop, v)


func _restore() -> void:
	for key: Array in _saved:
		(key[0] as Object).set(key[1], _saved[key])
	_saved.clear()
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = 1.0
	root.use_taa = false


func _write() -> void:
	_restore()
	_results = _ab_out
	_finish()
