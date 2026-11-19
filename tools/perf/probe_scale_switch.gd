extends "res://tools/perf/perf_bench.gd"
## Cost of changing the 3D render scale while FSR 2 runs (diagnostic only). WINDOWED.
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/perf/probe_scale_switch.gd -- \
##       --quality=3 --window=2560x1369 --views=room_greenhouse
## Holds the view, switches the scale between two values every second for 8 s and prints the frame times around
## each switch (the frame of the switch and the next two) next to the median frame.

var _sw_t := 0.0
var _sw_n := 0
var _sw_frames: Array = []
var _sw_mark: Array = []
var _sw_wait := 60


func _process(delta: float) -> bool:
	if _phase == "next":
		_enter_view(_views[0])
		root.msaa_3d = Viewport.MSAA_DISABLED
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		root.scaling_3d_scale = 0.67
		_phase = "switch"
		return false
	if _phase != "switch":
		return super(delta)
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_us) / 1000.0
	_last_us = now
	if _sw_wait > 0:
		_sw_wait -= 1
		return false
	_sw_frames.append(frame_ms)
	_sw_t += delta
	if _sw_t >= 1.0:
		_sw_t = 0.0
		_sw_n += 1
		_sw_mark.append(_sw_frames.size())
		root.scaling_3d_scale = 0.72 if is_equal_approx(root.scaling_3d_scale, 0.67) else 0.67
		if _sw_n > 8:
			var sorted := _sw_frames.duplicate()
			sorted.sort()
			var around: Array = []
			for m: int in _sw_mark.slice(0, -1):
				around.append("%.1f/%.1f/%.1f" % [_sw_frames[m], _sw_frames[mini(m + 1, _sw_frames.size() - 1)], _sw_frames[mini(m + 2, _sw_frames.size() - 1)]])
			print("SCALESWITCH median %.1f ms, around switches: %s" % [sorted[sorted.size() / 2], ", ".join(around)])
			quit(0)
			return true
	return false
