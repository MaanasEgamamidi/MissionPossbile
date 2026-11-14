extends CanvasLayer
## Autoload name: PerfHud. Debug builds only (frees itself in a release export).
##   Ctrl+1  show/hide HUD            Ctrl+2  zones on/off
##   Ctrl+3  exterior cull on/off     Ctrl+4  view activation on/off
##   Ctrl+5  occlusion culling on/off Ctrl+6  mesh LOD threshold 2 -> 3 -> 4 -> 1 -> 2 (project default 2)
##   Ctrl+7  start/stop CSV logging to user://perf_*.csv
##   Ctrl+8  record a benchmark waypoint   Ctrl+9  play the recorded route   Ctrl+0  spin test (BenchmarkRoute)
##   Ctrl+Shift+1  colony LOD on/off           Ctrl+Shift+2  Mars visibility ranges on/off
##   Ctrl+Shift+3  sun shadow tuning on/off    Ctrl+Shift+4  fixture distance fade on/off
##   Ctrl+Shift+0  every perf switch off (baseline) / on
## The HUD keeps collecting frame times even while hidden.

const HISTORY := 600

var _label := Label.new()
var _frames := PackedFloat32Array()
var _since_update := 0.0
var _log: FileAccess = null
var _log_t0 := 0.0
var _all_on := true


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label.position = Vector2(12, 12)
	_label.add_theme_color_override(&"font_color", Color.WHITE)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed):
		return
	var root := get_tree().root
	var k := event as InputEventKey
	var handled := true
	if k.shift_pressed:
		match k.keycode:
			KEY_1:
				Perf.cfg().toggle(&"colony_lod_enabled")
			KEY_2:
				Perf.cfg().toggle(&"visibility_ranges_enabled")
			KEY_3:
				Perf.cfg().toggle(&"sun_shadow_tuning_enabled")
			KEY_4:
				Perf.cfg().toggle(&"light_distance_fade_enabled")
			KEY_0:
				_all_on = not _all_on
				Perf.cfg().set_all(_all_on)
			_:
				handled = false
	else:
		match k.keycode:
			KEY_1:
				visible = not visible
				if visible:
					_label.text = _build_text()
			KEY_2:
				Perf.cfg().toggle(&"zones_enabled")
			KEY_3:
				Perf.cfg().toggle(&"exterior_cull_enabled")
			KEY_4:
				Perf.cfg().toggle(&"view_activation_enabled")
			KEY_5:
				root.use_occlusion_culling = not root.use_occlusion_culling
			KEY_6:
				var t := root.mesh_lod_threshold
				root.mesh_lod_threshold = 3.0 if t < 2.5 and t >= 1.5 else (4.0 if t < 3.5 and t >= 2.5 else (1.0 if t >= 3.5 else 2.0))
			KEY_7:
				_toggle_log()
			KEY_8, KEY_9, KEY_0:
				var br := get_tree().get_first_node_in_group(&"benchmark_route")
				if br != null:
					br.call(&"on_key", k.keycode)
			_:
				handled = false
	if handled:
		get_viewport().set_input_as_handled()
		if visible:
			_label.text = _build_text()


func _process(delta: float) -> void:
	var ms := delta * 1000.0
	_frames.append(ms)
	if _frames.size() > HISTORY:
		_frames.remove_at(0)
	if _log != null:
		_write_log_row(ms)
	_since_update += delta
	if _since_update < 0.5:
		return
	_since_update = 0.0
	if visible:
		_label.text = _build_text()


func stats() -> Dictionary:
	var sorted := _frames.duplicate()
	sorted.sort()
	var n := sorted.size()
	var sum := 0.0
	for f in _frames:
		sum += f
	return {
		"avg": sum / maxf(float(n), 1.0),
		"p99": sorted[mini(int(n * 0.99), n - 1)] if n > 0 else 0.0,
		"worst": sorted[n - 1] if n > 0 else 0.0,
	}


func _build_text() -> String:
	var s := stats()
	var root := get_tree().root
	var zm := get_tree().get_first_node_in_group(&"zone_manager") as ZoneManager
	var ec := get_tree().get_first_node_in_group(&"exterior_controller") as ExteriorController
	var va := get_tree().get_first_node_in_group(&"view_activator") as ViewActivator
	var t := "FPS %d | avg %.2f ms | p99 %.2f ms | worst %.2f ms\n" % [
		Engine.get_frames_per_second(), s["avg"], s["p99"], s["worst"]]
	t += "draw calls %d | objects %d | primitives %d\n" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))]
	t += "nodes %d | active 3D physics objects %d | video mem %.0f MB\n" % [
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0]
	t += "[2]zones %s  [3]exterior %s  [4]view %s  [5]occlusion %s  [6]mesh LOD thr %.1f\n" % [
		_onoff(Perf.cfg().zones_enabled), _onoff(Perf.cfg().exterior_cull_enabled),
		_onoff(Perf.cfg().view_activation_enabled), _onoff(root.use_occlusion_culling),
		root.mesh_lod_threshold]
	t += "[S1]colony LOD %s  [S2]mars ranges %s  [S3]sun tuning %s  [S4]light fade %s\n" % [
		_onoff(Perf.cfg().colony_lod_enabled), _onoff(Perf.cfg().visibility_ranges_enabled),
		_onoff(Perf.cfg().sun_shadow_tuning_enabled), _onoff(Perf.cfg().light_distance_fade_enabled)]
	if zm != null and zm.is_graph_ready:
		var cur := String(zm.current.zone_id) if zm.current != null else "-"
		var counts := [0, 0, 0, 0]
		for z in zm.zones:
			counts[z.state] += 1
		t += "zone %s | outside %s | queue %d | COLD %d VIEW %d WARM %d ACTIVE %d\n" % [
			cur, str(zm.player_outside), zm.queue_length(), counts[0], counts[1], counts[2], counts[3]]
	if ec != null:
		t += "Mars visible: %s\n" % str(ec.shown)
	if va != null:
		t += "view-gated asleep: %d\n" % va.asleep_count()
	if _log != null:
		t += "[7] LOGGING\n"
	return t


func _onoff(v: bool) -> String:
	return "ON" if v else "off"


func _toggle_log() -> void:
	if _log != null:
		_log.close()
		_log = null
		return
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	_log = FileAccess.open("user://perf_%s.csv" % stamp, FileAccess.WRITE)
	if _log != null:
		_log_t0 = Time.get_ticks_msec() * 0.001
		_log.store_line("t_s,frame_ms,draw_calls,objects,primitives,video_mb,nodes,zone,outside,mars_visible,switches")
		print("PerfHud logging to ", _log.get_path_absolute())


func _write_log_row(ms: float) -> void:
	var zm := get_tree().get_first_node_in_group(&"zone_manager") as ZoneManager
	var ec := get_tree().get_first_node_in_group(&"exterior_controller") as ExteriorController
	var zone_name := "-"
	var outside := false
	if zm != null and zm.is_graph_ready:
		outside = zm.player_outside
		if zm.current != null:
			zone_name = String(zm.current.zone_id)
	var sw := ""
	for k: StringName in Perf.cfg().snapshot().keys():
		sw += "1" if bool(Perf.cfg().get(k)) else "0"
	_log.store_line("%.3f,%.3f,%d,%d,%d,%.0f,%d,%s,%s,%s,%s" % [
		Time.get_ticks_msec() * 0.001 - _log_t0, ms,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		zone_name.replace(",", " "), str(outside), str(ec.shown) if ec != null else "-", sw])
