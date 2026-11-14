extends SceneTree
## Assembles res://scenes/world/colony_world.tscn from the imported GLBs, data/colony_manifest.json and
## data/lighting_preset.json. Reproducible: delete the scene and run again.
##   godot --headless --path . --script res://tools/godot/build_world.gd
## Nothing here is gameplay. It places the map, the lights of the Blender render rig, reflection probes, the sky and
## one Camera3D per source camera.

const Zones := preload("res://scripts/world/colony_zones.gd")
const MANIFEST := "res://data/colony_manifest.json"
const PRESET := "res://data/lighting_preset.json"
const OUT_SCENE := "res://scenes/world/colony_world.tscn"
const OUT_ENV := "res://scenes/world/lighting/env_reference_day.tres"
const REPORT := "res://data/build_world_report.json"

var C := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))   # Blender (x, y, z) -> Godot (x, z, -y)
var report := {}


func _initialize() -> void:
	var code := _build()
	quit(code)


func _mat(m: Array) -> Array:
	var b := Basis(Vector3(m[0][0], m[1][0], m[2][0]), Vector3(m[0][1], m[1][1], m[2][1]), Vector3(m[0][2], m[1][2], m[2][2]))
	return [b, Vector3(m[0][3], m[1][3], m[2][3])]


## Cameras and lights keep their own local axes (both look along -Z): T_godot = C * T_blender.
func xf_oriented(m: Array) -> Transform3D:
	var bt := _mat(m)
	return Transform3D(C * (bt[0] as Basis), C * (bt[1] as Vector3))


func lin_color(c: Array, e := 1.0) -> Color:
	return Color(float(c[0]) * e, float(c[1]) * e, float(c[2]) * e).linear_to_srgb()


func own(n: Node, root: Node) -> void:
	n.owner = root


func _arg(name: String, def: String) -> String:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == name and i + 1 < a.size():
			return a[i + 1]
	return def


## Optional: -- --preset <res path> --scene <res path> --env <res path>  (used for lighting experiments)
func _build() -> int:
	var preset_path := _arg("--preset", PRESET)
	var out_scene := _arg("--scene", OUT_SCENE)
	var out_env := _arg("--env", OUT_ENV)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var preset: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(preset_path))
	var zones := Zones.from_manifest(MANIFEST)
	var root := Node3D.new()
	root.name = "ColonyWorld"
	root.set_meta("source_blend_sha256", manifest.source.sha256)
	root.set_meta("lighting_preset", String(preset.name))
	root.set_meta("lighting_pass", int(preset["pass"]))

	for pair in [["Colony", "res://assets/colony/colony.glb"], ["Environment", "res://assets/colony/environment.glb"], ["Terrain", "res://assets/colony/terrain.glb"]]:
		var ps: PackedScene = load(pair[1])
		if ps == null:
			push_error("not imported: " + pair[1])
			return 2
		var inst := ps.instantiate()
		inst.name = pair[0]
		root.add_child(inst)
		own(inst, root)

	# ---------------------------------------------------------------- environment
	var env := Environment.new()
	var sky_p: Dictionary = preset.sky
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = lin_color(sky_p.top)
	sm.sky_horizon_color = lin_color(sky_p.horizon)
	sm.ground_horizon_color = lin_color(sky_p.horizon)
	sm.ground_bottom_color = lin_color(sky_p.ground)
	sm.sky_curve = 0.12
	sm.ground_curve = 0.04
	sm.sun_angle_max = 12.0
	sm.sun_curve = 0.2
	var sky := Sky.new()
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = float(sky_p.energy)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var tm: Dictionary = preset.tonemap
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = pow(2.0, float(tm.exposure_ev)) * float(tm.exposure_trim)
	env.tonemap_agx_contrast = float(tm.agx_contrast)
	env.tonemap_agx_white = float(tm.agx_white)
	var adj: Dictionary = preset.adjustment
	env.adjustment_enabled = bool(adj.enabled)
	env.adjustment_brightness = float(adj.brightness)
	env.adjustment_contrast = float(adj.contrast)
	env.adjustment_saturation = float(adj.saturation)
	var gi: Dictionary = preset.gi
	env.sdfgi_enabled = bool(gi.sdfgi)
	env.sdfgi_use_occlusion = bool(gi.sdfgi_use_occlusion)
	env.sdfgi_energy = float(gi.sdfgi_energy)
	env.sdfgi_cascades = int(gi.sdfgi_cascades)
	env.sdfgi_min_cell_size = float(gi.sdfgi_min_cell_size)
	env.sdfgi_read_sky_light = bool(gi.sdfgi_read_sky)
	env.sdfgi_bounce_feedback = float(gi.sdfgi_bounce_feedback)
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	env.ssao_enabled = bool(gi.ssao)
	env.ssao_radius = float(gi.ssao_radius)
	env.ssao_intensity = float(gi.ssao_intensity)
	env.ssil_enabled = bool(gi.ssil)
	var fog: Dictionary = preset.fog
	env.fog_enabled = bool(fog.enabled)
	env.fog_density = float(fog.density)
	env.fog_light_color = lin_color(fog.light_color)
	env.fog_sky_affect = float(fog.sky_affect)
	var glow: Dictionary = preset.glow
	env.glow_enabled = bool(glow.enabled)
	env.glow_intensity = float(glow.intensity)
	env.glow_strength = float(glow.strength)
	env.glow_bloom = float(glow.bloom)
	env.glow_hdr_threshold = float(glow.get("hdr_threshold", 1.0))
	var ssr: Dictionary = preset.get("ssr", {})
	env.ssr_enabled = bool(ssr.get("enabled", false))
	env.ssr_max_steps = int(ssr.get("max_steps", 64))
	env.ssr_fade_in = float(ssr.get("fade_in", 0.15))
	env.ssr_fade_out = float(ssr.get("fade_out", 2.0))
	env.ssr_depth_tolerance = float(ssr.get("depth_tolerance", 0.5))
	var vf: Dictionary = preset.get("volumetric_fog", {})
	env.volumetric_fog_enabled = bool(vf.get("enabled", false))
	env.volumetric_fog_density = float(vf.get("density", 0.001))
	env.volumetric_fog_albedo = lin_color(vf.get("albedo", [0.6, 0.4, 0.25]))
	env.volumetric_fog_anisotropy = float(vf.get("anisotropy", 0.6))
	env.volumetric_fog_length = float(vf.get("length", 300.0))
	env.volumetric_fog_ambient_inject = float(vf.get("ambient_inject", 0.0))
	env.volumetric_fog_sky_affect = float(vf.get("sky_affect", 0.0))
	env.volumetric_fog_gi_inject = float(vf.get("gi_inject", 0.0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_env.get_base_dir()))
	ResourceSaver.save(env, out_env)
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = load(out_env)
	root.add_child(we)
	own(we, root)

	# ---------------------------------------------------------------- lights of the Blender render rig
	var lights_root := Node3D.new()
	lights_root.name = "Lights"
	root.add_child(lights_root)
	own(lights_root, root)
	var zone_nodes := {}
	var fx: Dictionary = preset.fixtures
	var sun_p: Dictionary = preset.sun
	var counts := {"sun": 0, "area": 0, "omni": 0, "skipped_not_in_render": 0, "shadowed": 0}
	var per_zone := {}
	var zone_watts := {}
	var zone_colour := {}
	var shadow_used := {}
	var all_layers := (1 << 20) - 1
	# largest fixtures first, so a per-zone shadow budget goes to the biggest panels
	var lights: Array = manifest.lights
	var objects_by_asset := {}
	for o in manifest.objects:
		var m: Array = o.matrix_world
		if not objects_by_asset.has(o.gc_asset):
			objects_by_asset[o.gc_asset] = []
		(objects_by_asset[o.gc_asset] as Array).append([C * Vector3(m[0][3], m[1][3], m[2][3]), String(o.area)])
	lights.sort_custom(func(a, b): return float(a.get("size", 0.0)) * float(a.get("size_y", a.get("size", 0.0))) > float(b.get("size", 0.0)) * float(b.get("size_y", b.get("size", 0.0))))
	for l in lights:
		if not bool(l.in_blender_render):
			counts.skipped_not_in_render += 1
			continue
		var xf := xf_oriented(l.matrix_world)
		var sx := xf.basis.x.length()
		var sy := xf.basis.y.length()
		xf.basis = xf.basis.orthonormalized()
		var energy := float(l.energy)
		if String(l.type) == "SUN":
			var d := DirectionalLight3D.new()
			d.name = String(l.name)
			d.transform = xf
			d.light_color = lin_color(l.color)
			d.light_energy = energy * float(sun_p.energy_scale)
			d.light_angular_distance = float(sun_p.angular_distance_deg)
			d.shadow_enabled = bool(sun_p.shadow)
			d.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			d.directional_shadow_max_distance = float(sun_p.shadow_max_distance)
			d.light_cull_mask = all_layers
			d.shadow_caster_mask = zones.sun_bit()
			d.set_meta("blender_strength", energy)
			d.add_to_group("sun", true)
			root.add_child(d)
			own(d, root)
			counts.sun += 1
			continue
		# Blender made one light per glowing panel and named it FX_<asset>. Find that asset's nearest placed object and
		# take the room that built it; a wall light on a room line then follows its own room's power, not the neighbour's.
		var zone := zones.zone_at_world(xf.origin)
		var asset := String(l.name).trim_prefix("FX_")
		var dot := asset.rfind(".")
		if dot > 0 and asset.substr(dot + 1).is_valid_int():
			asset = asset.substr(0, dot)
		if objects_by_asset.has(asset):
			var best := 1e9
			var best_area := ""
			for o in objects_by_asset[asset]:
				var dd: float = (o[0] as Vector3).distance_squared_to(xf.origin)
				if dd < best:
					best = dd
					best_area = o[1]
			if best < 36.0:
				zone = zones.zone_of(best_area, xf.origin)
				counts.zone_from_owner = int(counts.get("zone_from_owner", 0)) + 1
		if not zone_nodes.has(zone):
			var zn := Node3D.new()
			zn.name = Zones.slug(zone)
			zn.set_meta("zone", zone)
			lights_root.add_child(zn)
			own(zn, root)
			zone_nodes[zone] = zn
		var node: Light3D
		if String(l.type) == "AREA":
			var w := float(l.size) * sx
			var h := float(l.get("size_y", l.size)) * sy
			if String(l.get("shape", "RECTANGLE")) in ["SQUARE", "DISK"]:
				h = float(l.size) * sy
			var area := w * h
			var outdoor := zone in [Zones.EXTERIOR, Zones.PLAZA, Zones.GARDEN]
			var rng := float(fx.area_range_outdoor_m) if outdoor else float(fx.area_range_m)
			var mode := String(fx.get("mode", "area"))
			var as_area := mode == "area" or (mode == "mixed" and area >= float(fx.get("area_min_m2", 0.0)))
			var want_shadow := area >= float(fx.shadow_min_area_m2) and int(shadow_used.get(zone, 0)) < int(fx.shadow_max_per_zone)
			if as_area:
				# AreaLight3D: correct rectangular highlight and falloff, higher GPU cost, and (measured in Prompt 02)
				# no contribution to SDFGI. Used only where the panel shape is visible in the lighting.
				var a := AreaLight3D.new()
				a.area_size = Vector2(w, h)
				a.area_normalize_energy = bool(fx.normalize_energy)
				a.area_attenuation = float(fx.area_attenuation)
				a.area_range = rng
				a.light_energy = energy * float(fx.area_energy_scale)
				node = a
				counts.area += 1
			else:
				# SpotLight3D with the Blender light's 140 degree spread: cheaper, and it does feed SDFGI.
				var s := SpotLight3D.new()
				s.spot_range = rng
				s.spot_angle = float(fx.get("spot_angle_deg", 70.0))
				s.spot_angle_attenuation = float(fx.get("spot_angle_attenuation", 1.0))
				s.spot_attenuation = float(fx.get("spot_attenuation", 2.0))
				s.light_energy = energy * float(fx.get("spot_energy_scale", 0.03))
				s.light_size = sqrt(area) * 0.5
				node = s
				counts.spot = int(counts.get("spot", 0)) + 1
			if want_shadow:
				node.shadow_enabled = true
				shadow_used[zone] = int(shadow_used.get(zone, 0)) + 1
				counts.shadowed += 1
			node.set_meta("area_m2", area)
			node.set_meta("panel_size", Vector2(w, h))
		else:
			var o := OmniLight3D.new()
			o.omni_range = float(fx.omni_range_m)
			o.omni_attenuation = 2.0
			o.light_energy = energy * float(fx.omni_energy_scale)
			o.light_size = float(l.get("shadow_soft_size", 0.0))
			node = o
			counts.omni += 1
		node.name = String(l.name).replace(".", "_")
		node.transform = xf
		node.light_color = lin_color(l.color)
		node.light_specular = float(fx.specular)
		node.light_indirect_energy = float(fx.indirect_energy)
		node.light_bake_mode = Light3D.BAKE_DYNAMIC
		node.light_cull_mask = zones.bit_of(zone)
		node.shadow_caster_mask = zones.bit_of(zone)
		node.set_meta("blender_energy_w", energy)
		node.set_meta("blender_name", String(l.name))
		node.set_meta("zone", zone)
		node.add_to_group("fixture_lights", true)
		node.add_to_group("zone_" + Zones.slug(zone), true)
		(zone_nodes[zone] as Node3D).add_child(node)
		own(node, root)
		per_zone[zone] = int(per_zone.get(zone, 0)) + 1
		zone_watts[zone] = float(zone_watts.get(zone, 0.0)) + energy
		zone_colour[zone] = (zone_colour.get(zone, Vector3.ZERO) as Vector3) + Vector3(float(l.color[0]), float(l.color[1]), float(l.color[2])) * energy

	# ---------------------------------------------------------------- reflection probes, one per room
	var probes_root := Node3D.new()
	probes_root.name = "ReflectionProbes"
	root.add_child(probes_root)
	own(probes_root, root)
	var pp: Dictionary = preset.probes
	var probe_count := 0
	var probe_ambient := {}
	if bool(pp.enabled):
		for r in zones.rooms:
			var p := ReflectionProbe.new()
			var w := float(r.x1) - float(r.x0)
			var d := float(r.y1) - float(r.y0)
			var h := float(r.ceiling)
			p.name = "Probe_" + Zones.slug(String(r.name))
			# the box must contain the room's own wall, floor and ceiling surfaces, and the blend band must be thin,
			# or those surfaces sit in the fade-out and receive almost none of the room's ambient light
			var mg := float(pp.get("margin_m", 0.5))
			p.position = Vector3((float(r.x0) + float(r.x1)) * 0.5, h * 0.5, -(float(r.y0) + float(r.y1)) * 0.5)
			p.size = Vector3(w + mg, h + mg * 1.4, d + mg)
			p.blend_distance = float(pp.get("blend_distance_m", 0.05))
			p.interior = bool(pp.interior)
			p.box_projection = bool(pp.box_projection)
			p.intensity = float(pp.intensity)
			p.update_mode = ReflectionProbe.UPDATE_ONCE
			var watts := float(zone_watts.get(String(r.name), 0.0))
			var surface := 2.0 * w * d + 2.0 * (w + d) * h
			p.set_meta("fixture_watts", watts)
			p.set_meta("surface_m2", surface)
			match String(pp.ambient_mode):
				"per_room":
					# Stand-in for bounced light: a uniform ambient proportional to the room's own fixture power per
					# square metre of room surface, tinted by the power-weighted colour of those fixtures. It follows the
					# room's power state at run time (ZoneLighting) and cannot leak between rooms. Fitted, not physical.
					var tint := Vector3(1, 1, 1)
					if watts > 0.0:
						tint = (zone_colour[String(r.name)] as Vector3) / watts
					p.ambient_mode = ReflectionProbe.AMBIENT_COLOR
					p.ambient_color = lin_color([tint.x, tint.y, tint.z])
					# integrating-sphere estimate: bounced irradiance = flux * rho / (surface * (1 - rho))
					var rho := clampf(float(r.get("mean_albedo", 0.4)) if r.get("mean_albedo") != null else 0.4, 0.05, 0.8)
					p.set_meta("mean_albedo", rho)
					p.ambient_color_energy = float(pp.ambient_per_w_m2) * watts / surface * rho / (1.0 - rho)
					p.set_meta("ambient_full", p.ambient_color_energy)
					probe_ambient[String(r.name)] = snappedf(p.ambient_color_energy, 0.0001)
				"color":
					p.ambient_mode = ReflectionProbe.AMBIENT_COLOR
					p.ambient_color = lin_color(pp.ambient_color)
					p.ambient_color_energy = float(pp.ambient_energy)
				"environment":
					p.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
				_:
					p.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
			p.set_meta("zone", String(r.name))
			p.add_to_group("room_probes", true)
			probes_root.add_child(p)
			own(p, root)
			probe_count += 1

	# ---------------------------------------------------------------- roof occluders
	# One box per roof rectangle of the source map. Roofs are opaque and never open, so they are safe occluders: from
	# outside they hide the rooms below, from inside they hide the hall frame above. Walls are not used: several have
	# windows and every door is glazed.
	var occ_root := Node3D.new()
	occ_root.name = "Occluders"
	root.add_child(occ_root)
	own(occ_root, root)
	var occ_count := 0
	if bool(preset.get("occlusion", {}).get("roofs", true)) and manifest.get("roofs_y_up") != null:
		for rf in manifest.roofs_y_up:
			var oc := OccluderInstance3D.new()
			var bx := BoxOccluder3D.new()
			var rw := float(rf[2]) - float(rf[0])
			var rd := float(rf[3]) - float(rf[1])
			bx.size = Vector3(maxf(rw - 0.3, 0.1), 0.12, maxf(rd - 0.3, 0.1))
			oc.occluder = bx
			oc.name = "Roof_%02d" % occ_count
			oc.position = Vector3((float(rf[0]) + float(rf[2])) * 0.5, float(rf[4]) + 0.12, (float(rf[1]) + float(rf[3])) * 0.5)
			occ_root.add_child(oc)
			own(oc, root)
			occ_count += 1

	# ---------------------------------------------------------------- screen pass standing in for the Blender compositor
	var post: Dictionary = preset.get("post", {})
	if bool(post.get("enabled", false)):
		var layer := CanvasLayer.new()
		layer.name = "PostFX"
		layer.layer = -10                       # below every UI layer
		root.add_child(layer)
		own(layer, root)
		var rect := ColorRect.new()
		rect.name = "Grade"
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pm := ShaderMaterial.new()
		pm.shader = load("res://materials/post_fx.gdshader")
		pm.set_shader_parameter("vignette", float(post.get("vignette", 0.22)))
		pm.set_shader_parameter("dispersion", float(post.get("dispersion", 0.006)))
		rect.material = pm
		layer.add_child(rect)
		own(rect, root)

	# ---------------------------------------------------------------- source cameras
	var cams_root := Node3D.new()
	cams_root.name = "ReferenceCameras"
	root.add_child(cams_root)
	own(cams_root, root)
	var res: Array = manifest.render_reference.resolution
	var aspect := float(res[0]) / float(res[1])
	var cam_count := 0
	for c in manifest.cameras:
		var cam := Camera3D.new()
		cam.name = String(c.name)
		var xf := xf_oriented(c.matrix_world)
		xf.basis = xf.basis.orthonormalized()
		cam.transform = xf
		# sensor fit AUTO at a landscape aspect is a horizontal fit: derive the vertical angle Godot wants
		cam.fov = rad_to_deg(2.0 * atan(tan(float(c.angle_x) * 0.5) / aspect))
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.near = float(c.clip_start)
		cam.far = float(c.clip_end)
		cam.set_meta("lens_mm", float(c.lens))
		cam.set_meta("source_collection", String(c.collection))
		cams_root.add_child(cam)
		own(cam, root)
		cam_count += 1

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed %d" % err)
		return 3
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_scene.get_base_dir()))
	err = ResourceSaver.save(packed, out_scene)
	report = {"ok": err == OK, "scene": out_scene, "environment": out_env, "preset": preset.name, "pass": preset["pass"], "lights": counts,
		"lights_per_zone": per_zone, "probe_ambient_energy": probe_ambient, "probes": probe_count, "roof_occluders": occ_count, "cameras": cam_count, "zones": Array(zones.names)}
	var f := FileAccess.open(REPORT if out_scene == OUT_SCENE else out_scene.get_basename() + "_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	f.close()
	print("build_world: ", JSON.stringify(report.lights), " probes=", probe_count, " cameras=", cam_count, " err=", err)
	root.free()
	return 0 if err == OK else 4
