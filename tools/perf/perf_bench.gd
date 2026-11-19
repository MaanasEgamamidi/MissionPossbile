extends SceneTree
## Performance benchmark for Prompt 13. WINDOWED (needs the GPU): the owner allowed windowed runs for Prompt 13
## measurements and the Prompt 17 build launch only.
##
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/perf/perf_bench.gd -- \
##       --quality=2 --cap=0 --seconds=8 --out=G:/nasa app/_perf/high_uncapped.json [--views=a,b] [--host]
##
## --quality  GraphicsQuality level (1 = Medium, 2 = High)       --cap  0 = uncapped (vsync off), 60 = vsync + 60 FPS cap
## --seconds  sampled seconds per view (after 2 s warm-up)      --host host a LAN session (clients join separately)
## --shots=DIR  save one still per view (before the look sweep) for image comparison between runs (perf overhaul)
## --perf-off / --perf-on  every perf-overhaul switch off (baseline) / on; neither = the shipped defaults
## --switches=N  after the views, switch Medium <-> High N times and record process memory after each (growth check)
## The "rover_route" view boards the rover (built, charged, suited driver) and drives it out of the garage by holding
## the throttle with a slow steering sweep: real physics, no teleport.
##
## The game itself is started (no menu, a fresh colony in a temporary save folder, no weather refresh) at 1920x1080.
## Each view places the local player (first person) at a viewpoint inside the named room or outdoors and records every
## frame: frame time, CPU and GPU render time of the main viewport, draw calls, objects, primitives, video and static
## memory. Whole-process memory is read between views (Windows Get-Process, private bytes and working set).
## Results are written as JSON (one record per view) with the renderer, adapter, driver and build.

## --window=WxH overrides the 1920x1080 benchmark window (the owner's screen maximized is 2560x1369).
var WINDOW := Vector2i(1920, 1080)

var _args := {}
var _game: Node = null
var _views: Array = []
var _view_i := -1
var _phase := "boot"
var _t := 0.0
var _frames: Array = []
var _results: Array = []
var _last_us := 0
var _vp_rid: RID
var _boot_frames := 0
var _proc_mem_before := {}
var _shot_frames := 0


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _args.has("window"):
		var wh := String(_args.window).split("x")
		WINDOW = Vector2i(int(wh[0]), int(wh[1]))
	var cap := int(_args.get("cap", "0"))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if cap > 0 else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = cap
	_force_window()
	var save_dir := OS.get_user_data_dir().path_join("perf_bench_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	var game_script := load("res://scripts/game/game_main.gd") as Script
	_game = Node3D.new()
	_game.set_script(game_script)
	_game.set("show_menu", false)
	_game.set("check_weather_updates", false)
	_game.set("save_directory", save_dir)
	_game.name = "Game"
	root.add_child(_game)
	_last_us = Time.get_ticks_usec()


func _process(delta: float) -> bool:
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_us) / 1000.0
	_last_us = now
	match _phase:
		"boot":
			_boot_frames += 1
			if _boot_frames > 30 and _game.get("player") != null:
				_setup()
				_phase = "next"
		"next":
			for a: StringName in [&"move_forward", &"move_left", &"move_right"]:
				Input.action_release(a)
			_view_i += 1
			if _view_i >= _views.size():
				_quality_switches()
				_finish()
				return true
			_enter_view(_views[_view_i])
			_t = 0.0
			_frames = []
			_shot_frames = 0
			_phase = "shot" if _args.has("shots") else "warm"
		"shot":
			# Perf overhaul: --shots=DIR saves one still per view, 45 frames after arriving and before the slow look
			# starts, so runs with different perf switches can be compared image to image.
			_shot_frames += 1
			if _shot_frames >= 45:
				var dir: String = _args.shots
				DirAccess.make_dir_recursive_absolute(dir)
				root.get_texture().get_image().save_png(dir.path_join("%s.png" % _views[_view_i].name))
				_phase = "warm"
		"warm":
			_t += delta
			_update_view(_views[_view_i], delta)
			if _t >= 2.0:
				_t = 0.0
				_phase = "sample"
		"sample":
			_t += delta
			_update_view(_views[_view_i], delta)
			_frames.append(_sample(frame_ms))
			if _t >= float(_args.get("seconds", "8")):
				_results.append(_summarise(_views[_view_i], _frames))
				print("VIEW ", _views[_view_i].name, " ", JSON.stringify(_results[-1].summary))
				_phase = "next"
	return false


## project.godot starts the window maximized (window/size/mode=2), which on this desktop gave a 2560x1369 render.
## The benchmark needs 1920x1080: leave the maximized state first, then size and centre the window.
func _force_window() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(WINDOW)
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	DisplayServer.window_set_position(screen.position + (screen.size - WINDOW) / 2)
	root.size = WINDOW


func _setup() -> void:
	_force_window()
	var quality := int(_args.get("quality", "2"))
	GraphicsQuality.apply(self, quality)
	_vp_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	var services: GameServices = _game.get("services")
	if _args.has("host"):
		services.net.host()
	# Four suited crew: everyone wears a suit, so the bodies seen are the suited ones.
	for c: CharacterState in services.state().characters.values():
		c.suit_on = true
	_game.call("_rebuild_crew")
	_views = _make_views(services)
	var wanted: String = _args.get("views", "")
	if wanted != "":
		var keep := wanted.split(",")
		_views = _views.filter(func(v: Dictionary) -> bool: return keep.has(v.name))
	_proc_mem_before = _process_memory()


## Viewpoints from the map: inside the named rooms (room centre, looking at a station there) and outdoors.
func _make_views(services: GameServices) -> Array:
	var views: Array = []
	var zones := services.zones
	var rooms := {}
	for r: Dictionary in zones.rooms:
		rooms[String(r.name)] = r
	var targets := {"Command Room": "cr_wall_display", "Power Room": "pw_panel", "Greenhouse": "", "Med Bay": "mb_glovebox",
		"Hangar": "hb_rover", "Rec Kitchen": "rk_treadmill", "Life Support": "", "Mess Hall": ""}
	for room_name: String in targets:
		if not rooms.has(room_name):
			continue
		var r: Dictionary = rooms[room_name]
		var centre := Vector3((float(r.x0) + float(r.x1)) / 2.0, 0.05, -(float(r.y0) + float(r.y1)) / 2.0)
		var look := _object_position(String(targets[room_name]))
		if look == Vector3.INF:
			look = centre + Vector3(float(r.x1) - float(r.x0), 0.0, 0.0) * 0.5
		views.append({"name": "room_" + ColonyZones.slug(room_name), "kind": "indoor", "at": centre, "look": look})
	var plaza: Dictionary = zones.dome
	if not plaza.is_empty() and plaza.has("cx"):
		var c := Vector3(float(plaza.cx), 0.05, -float(plaza.cy))
		views.append({"name": "plaza_through_glass", "kind": "glass", "at": c, "look": c + Vector3(30.0, 4.0, 10.0)})
	var garage := _object_position("sf_print_garage")
	if garage != Vector3.INF:
		var at := garage + Vector3(-14.0, 0.0, 10.0)
		at.y = _ground(services, at)
		views.append({"name": "exterior_garage", "kind": "exterior", "at": at, "look": garage})
		views.append({"name": "exterior_storm", "kind": "storm", "at": at, "look": _object_position("ex_lander") if _object_position("ex_lander") != Vector3.INF else garage + Vector3(-30, 0, 0)})
		views.append({"name": "four_suited_crew", "kind": "crew", "at": at, "look": at + Vector3(6.0, 0.0, -2.0)})
		views.append({"name": "rover_route", "kind": "rover", "at": at, "look": garage})
	return views


func _object_position(object_name: String) -> Vector3:
	if object_name == "":
		return Vector3.INF
	var m := _manifest()
	for o: Dictionary in m.get("objects", []):
		if String(o.name) == object_name:
			var mw: Array = o.matrix_world
			return Vector3(float(mw[0][3]), float(mw[2][3]), -float(mw[1][3]))
	return Vector3.INF


var _manifest_cache := {}
func _manifest() -> Dictionary:
	if _manifest_cache.is_empty():
		_manifest_cache = JSON.parse_string(FileAccess.get_file_as_string("res://data/colony_manifest.json"))
	return _manifest_cache


func _ground(_services: GameServices, p: Vector3) -> float:
	var h := load("res://data/terrain_height.res") as TerrainHeight
	return h.height_at(p.x, p.z) + 0.05 if h != null and h.has_method("height_at") else p.y


func _enter_view(v: Dictionary) -> void:
	var player: PlayerController = _game.get("player")
	player.input_enabled = false
	player.set_first_person(true)
	var at: Vector3 = v.at
	var look: Vector3 = v.look
	var flat := Vector2(look.x - at.x, look.z - at.z)
	var yaw := atan2(-flat.x, -flat.y)
	player.teleport(at + Vector3(0.0, 0.1, 0.0), yaw)
	var services: GameServices = _game.get("services")
	var st := services.state()
	if String(v.kind) == "crew":
		# Put the other three crew in front of the camera, suited and walking, so four suited bodies are in view.
		var visuals: Dictionary = _game.get("_crew_visuals")
		var i := 0
		for id: StringName in visuals:
			var body := visuals[id] as Node3D
			body.global_position = at + Vector3(4.0 + 1.2 * i, 0.0, -1.5 + 1.0 * i)
			body.global_position.y = _ground(services, body.global_position) - 0.05
			i += 1
	if String(v.kind) == "storm":
		st.dust_tau = 0.5
	if String(v.kind) == "rover":
		var rp: RoverPresenter = _game.get("rover")
		if rp != null and rp.body != null:
			RoverModel.ensure(st)
			st.rover["built"] = true
			st.rover["battery_kwh"] = float(RoverModel.stats(st.rover.levels, 0.0).get("battery_capacity_kwh", 10.0))
			services.local_character().suit_on = true
			var stand: Variant = rp.exit_ground(1)
			if stand != null:
				player.teleport((stand as Vector3) + Vector3.UP * 0.05, yaw)
			for i in 3:
				await physics_frame
			var r := services.request(&"rover_enter", &"", {"seat": 0})
			print("ROVER boarding: ", r.ok, " ", r.message)
	_proc_mem_before = _process_memory()


func _update_view(v: Dictionary, delta: float) -> void:
	var services: GameServices = _game.get("services")
	if String(v.kind) == "storm":
		# A changing storm: optical depth sweeps from 0.5 to 2.5 and back over the view, through the real presenter.
		var st := services.state()
		var span := float(_args.get("seconds", "8")) + 2.0
		var x := fmod(_t + (0.0 if _phase == "warm" else 2.0), span) / span
		st.dust_tau = 0.5 + 2.0 * sin(PI * x)
	if String(v.kind) == "rover":
		Input.action_press(&"move_forward")
		var steer := sin(_t * 0.6)
		if steer > 0.35:
			Input.action_press(&"move_right")
			Input.action_release(&"move_left")
		elif steer < -0.35:
			Input.action_press(&"move_left")
			Input.action_release(&"move_right")
		else:
			Input.action_release(&"move_left")
			Input.action_release(&"move_right")
	var player: PlayerController = _game.get("player")
	if String(v.kind) != "rover":
		# Slow look around (fast turns are a separate check): 20 degrees per second.
		player.camera_rig().add_look(deg_to_rad(20.0) * delta, 0.0)


var _switch_memory: Array = []
## Medium <-> High repeatedly; process memory after each switch (a steady value means no growth).
func _quality_switches() -> void:
	var n := int(_args.get("switches", "0"))
	var quality := int(_args.get("quality", "2"))
	for i in n:
		GraphicsQuality.apply(self, GraphicsQuality.Level.MEDIUM if i % 2 == 0 else GraphicsQuality.Level.HIGH)
		var mem := _process_memory()
		mem["switch"] = i + 1
		mem["static_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		mem["video_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
		_switch_memory.append(mem)
	GraphicsQuality.apply(self, quality)


func _sample(frame_ms: float) -> Dictionary:
	return {
		"frame_ms": frame_ms,
		"cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) + RenderingServer.get_frame_setup_time_cpu(),
		"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"static_mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	}


func _summarise(v: Dictionary, frames: Array) -> Dictionary:
	var out := {"view": v.name, "kind": v.kind, "frames": frames.size(), "render_size": [root.size.x, root.size.y],
		"window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]}
	var summary := {}
	for key: String in ["frame_ms", "cpu_ms", "gpu_ms", "process_ms", "physics_ms", "draw_calls", "objects", "primitives", "video_mem_mb", "static_mem_mb"]:
		var values: Array = frames.map(func(f: Dictionary) -> float: return float(f[key]))
		values.sort()
		var n := values.size()
		if n == 0:
			continue
		var total := 0.0
		for x: float in values:
			total += x
		summary[key] = {"mean": total / n, "p50": values[int(n * 0.50)], "p95": values[mini(n - 1, int(n * 0.95))],
			"p99": values[mini(n - 1, int(n * 0.99))], "max": values[n - 1]}
	summary["fps_mean"] = 1000.0 / maxf(0.001, float(summary.frame_ms.mean)) if summary.has("frame_ms") else 0.0
	out["summary"] = summary
	out["process_memory_before"] = _proc_mem_before
	out["process_memory_after"] = _process_memory()
	return out


func _process_memory() -> Dictionary:
	var out: Array = []
	var cmd := "$p = Get-Process -Id %d; '{0} {1}' -f $p.PrivateMemorySize64, $p.WorkingSet64" % OS.get_process_id()
	OS.execute("powershell", ["-NoProfile", "-Command", cmd], out)
	var parts := (String(out[0]) if not out.is_empty() else "").strip_edges().split(" ")
	if parts.size() == 2:
		return {"private_mb": float(parts[0]) / 1048576.0, "working_set_mb": float(parts[1]) / 1048576.0}
	return {}


func _finish() -> void:
	var info := {
		"engine": Engine.get_version_info().string,
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", ""),
		"driver": RenderingServer.get_current_rendering_driver_name() if RenderingServer.has_method("get_current_rendering_driver_name") else "",
		"adapter": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"api": RenderingServer.get_video_adapter_api_version(),
		"driver_info": OS.get_video_adapter_driver_info(),
		"cpu": OS.get_processor_name(), "cores": OS.get_processor_count(),
		"window": [root.size.x, root.size.y], "quality": GraphicsQuality.level_name(int(_args.get("quality", "2"))),
		"cap_fps": int(_args.get("cap", "0")), "vsync": int(_args.get("cap", "0")) > 0,
		"host_session": _args.has("host"), "debug_build": OS.is_debug_build(),
		"date": Time.get_datetime_string_from_system(),
		"perf_switches": root.get_node("PerfSettings").call("snapshot") if root.has_node("PerfSettings") else {},
	}
	var report := {"info": info, "views": _results, "quality_switch_memory": _switch_memory}
	var path: String = _args.get("out", OS.get_user_data_dir().path_join("perf_bench.json"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
	print("PERF REPORT ", path)
	quit(0)
