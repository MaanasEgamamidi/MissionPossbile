extends "res://tools/perf/perf_bench.gd"
## Cost of each Settings > Graphics option at its best, on top of a preset (diagnostic only). WINDOWED.
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/perf/probe_graphics_options.gd -- \
##       --quality=3 --cap=0 --window=2560x1369 --views=room_command_room [--hold=2.5] [--keys=shadows,gi]
## Holds the view; for the preset alone, then every option turned to its best one at a time, then all options at their
## best, prints the mean frame and GPU time (after 1 s of settling). Adaptive resolution is held off so the numbers
## compare. Each step prints a GOPT marker first, so engine errors in the log can be matched to the option.

var _go_steps: Array = []
var _go_i := -1
var _go_t := 0.0
var _go_frames: Array = []
var _go_gpu: Array = []
var _go_base := 3


func _process(delta: float) -> bool:
	if _phase == "next":
		_enter_view(_views[0])
		_go_base = int(_args.get("quality", "3"))
		# measure even when the window is not in front (the 10 FPS background cap would hide every difference)
		if root.has_node("PerfSettings"):
			root.get_node("PerfSettings").set("background_throttle_enabled", false)
		Engine.max_fps = 0
		var only: PackedStringArray = String(_args.get("keys", "")).split(",", false)
		var drs := _game.get_node_or_null("DynamicResolution")
		if drs != null:
			drs.set_process(false)
		_go_steps.append({"name": "preset %s" % GraphicsQuality.level_name(_go_base), "opts": {"dynamic_res": 0}})
		var all := {}
		for o: Dictionary in GraphicsQuality.OPTIONS:
			var key := String(o.key)
			var b := GraphicsQuality.best(o)
			all[key] = b
			if not only.is_empty() and not only.has(key):
				continue
			if b != GraphicsQuality.preset_value(key, _go_base) and key != "dynamic_res":
				_go_steps.append({"name": "%s -> %s" % [key, str(b) if GraphicsQuality.is_slider(o) else String((o.choices as Array)[b])],
					"opts": {key: b, "dynamic_res": 0}})
		all["dynamic_res"] = 0
		if only.is_empty():
			_go_steps.append({"name": "ALL at best", "opts": all})
		_go_steps.append({"name": "preset %s again" % GraphicsQuality.level_name(_go_base), "opts": {"dynamic_res": 0}})
		_phase = "opts"
		_go_t = 99.0
		return false
	if _phase != "opts":
		return super(delta)
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_us) / 1000.0
	_last_us = now
	_go_t += delta
	if _go_t > 1.0:
		_go_frames.append(frame_ms)
		_go_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid))
	if _go_t >= float(_args.get("hold", "2.5")) + 1.0:
		if _go_i >= 0:
			print("GOPT %-34s frame %6.2f ms  gpu %6.2f ms  (%d frames)" % [_go_steps[_go_i].name, _mean(_go_frames), _mean(_go_gpu), _go_frames.size()])
		_go_i += 1
		if _go_i >= _go_steps.size():
			print("GOPTEND")
			quit(0)
			return true
		print("GOPTSTEP ", _go_steps[_go_i].name)
		GraphicsQuality.apply(self, _go_base, null, _go_steps[_go_i].opts)
		_go_t = 0.0
		_go_frames = []
		_go_gpu = []
	return false


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v: float in a:
		t += v
	return t / a.size()
