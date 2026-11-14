extends SceneTree
## Renders reference-camera views of the world to PNG files with no UI and no debug overlay.
##   godot --path . --script res://tools/godot/capture_views.gd -- --out <dir> [--cams a,b|beauty|all] [--size 1920x1080]
##         [--frames 90] [--off zone_slug,...] [--night]
## The world is drawn in an off-screen SubViewport of exactly --size, so the desktop window size does not matter.
## --off switches the named zones' fixtures off (lights and emission); --night removes the sun and dims the sky.

const WORLD := "res://scenes/world/colony_world.tscn"
const ZoneLightingScript := preload("res://scripts/world/zone_lighting.gd")


func _initialize() -> void:
	_run()


func _arg(name: String, def: String) -> String:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == name and i + 1 < a.size():
			return a[i + 1]
	return def


func _run() -> void:
	var out_dir := _arg("--out", "user://captures")
	var size_s := _arg("--size", "1920x1080").split("x")
	var size := Vector2i(int(size_s[0]), int(size_s[1]))
	var frames := int(_arg("--frames", "90"))
	var cams_arg := _arg("--cams", "beauty")
	var off := _arg("--off", "")
	var night := OS.get_cmdline_user_args().has("--night")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.positional_shadow_atlas_size = 4096
	vp.use_occlusion_culling = bool(ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false))
	vp.mesh_lod_threshold = float(ProjectSettings.get_setting("rendering/mesh_lod/lod_change/threshold_pixels", 1.0))
	root.add_child(vp)
	var world: Node3D = (load(_arg("--world", WORLD)) as PackedScene).instantiate()
	vp.add_child(world)
	await process_frame          # the tree must be running before world transforms can be read
	var lighting := ZoneLightingScript.new()
	lighting.name = "ZoneLighting"
	world.add_child(lighting)
	lighting.setup(world)
	for z in off.split(",", false):
		lighting.set_zone_powered_by_slug(z, false)
	if night:
		lighting.set_night(true)

	var cams: Array = []
	var holder := world.get_node("ReferenceCameras")
	for c in holder.get_children():
		var n := String(c.name)
		if cams_arg == "all" or (cams_arg == "beauty" and n.begins_with("Shot_")) or n in cams_arg.split(","):
			cams.append(c)
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	var report := {"size": [size.x, size.y], "frames_per_view": frames, "off": off, "night": night, "views": [],
		"preset": world.get_meta("lighting_preset", ""), "pass": world.get_meta("lighting_pass", -1),
		"adapter": RenderingServer.get_video_adapter_name(), "godot": Engine.get_version_info().string}
	for cam in cams:
		(cam as Camera3D).make_current()
		var cpu := 0.0
		var gpu := 0.0
		var samples := 0
		for i in frames:
			await process_frame
			if i >= frames - 30:
				cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid())
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
				samples += 1
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var path := out_dir.path_join(String(cam.name) + ".png")
		img.save_png(path)
		report.views.append({"camera": String(cam.name), "file": path, "render_cpu_ms": snappedf(cpu / maxf(samples, 1), 0.01),
			"render_gpu_ms": snappedf(gpu / maxf(samples, 1), 0.01),
			"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)})
		print("captured ", cam.name, " gpu_ms=", snappedf(gpu / maxf(samples, 1), 0.01))
	var f := FileAccess.open(out_dir.path_join("capture_report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	f.close()
	quit(0)
