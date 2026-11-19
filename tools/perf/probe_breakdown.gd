extends "res://tools/perf/perf_bench.gd"
## Where the main thread's frame goes (diagnostic only). WINDOWED.
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/perf/probe_breakdown.gd -- \
##       --quality=3 --window=2560x1369 --views=tutorial_start,room_command_room --seconds=5
## Godot's main loop per frame: physics steps, then process (this script first, then every node), then the
## RenderingServer draw (frame_pre_draw .. frame_post_draw: culling, shadows, draw-list building, submit), then the
## swap / wait for the GPU. This times process = start of _process .. frame_pre_draw, draw = pre .. post draw, and
## rest = frame_post_draw .. next _process (swap, vsync / GPU wait, physics). Means over --seconds per view.

var _bd_view := -1
var _bd_t := 0.0
var _t_proc := 0
var _t_pre := 0
var _t_post := 0
var _acc := {}
var _n := 0
var _connected := false


func _process(delta: float) -> bool:
	if _phase == "next":
		if not _connected:
			RenderingServer.frame_pre_draw.connect(func() -> void: _t_pre = Time.get_ticks_usec())
			RenderingServer.frame_post_draw.connect(func() -> void: _t_post = Time.get_ticks_usec())
			_connected = true
		_phase = "breakdown"
		_bd_next()
		return false
	if _phase != "breakdown":
		return super(delta)
	var now := Time.get_ticks_usec()
	if _bd_t >= 0.0 and _t_proc > 0 and _t_pre > _t_proc and _t_post >= _t_pre and now > _t_post:
		_add("frame", now - _t_proc)
		_add("process", _t_pre - _t_proc)
		_add("draw", _t_post - _t_pre)
		_add("rest", now - _t_post)
		_add("gpu", int(RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid) * 1000.0))
		_n += 1
	_t_proc = now
	_bd_t += delta
	if _bd_t >= float(_args.get("seconds", "5")):
		var parts: Array = []
		for k: String in ["frame", "process", "draw", "rest", "gpu"]:
			parts.append("%s %.1f" % [k, float(_acc.get(k, 0)) / maxf(1.0, _n) / 1000.0])
		print("BREAKDOWN %-20s %s ms (%d frames)" % [_views[_bd_view].name, "  ".join(parts), _n])
		if not _bd_next():
			quit(0)
			return true
	return false


func _add(k: String, usec: int) -> void:
	_acc[k] = int(_acc.get(k, 0)) + usec


func _bd_next() -> bool:
	_bd_view += 1
	if _bd_view >= _views.size():
		return false
	_enter_view(_views[_bd_view])
	_bd_t = -1.5    # settle
	_acc = {}
	_n = 0
	_t_proc = 0
	return true
