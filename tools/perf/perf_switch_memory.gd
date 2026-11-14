extends "res://tools/perf/perf_bench.gd"
## Quality-switch memory check with frames rendered between switches. WINDOWED (Prompt 13 measurements only).
##
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/perf/perf_switch_memory.gd -- \
##       --quality=2 --switches=12 --settle=60 --views=none --out=G:/nasa app/_work/p13/perf/switch_memory.json
##
## perf_bench.gd switches Medium <-> High N times inside one frame and reads process memory straight after each
## switch. The renderer frees replaced buffers (shadow atlases, MSAA / SSAO / SSIL buffers) only after the frames
## in flight have finished, so that reading cannot tell a leak from memory that is about to be released. Here every
## switch is followed by --settle rendered frames (default 60) before memory is read, plus a baseline before the
## first switch and a final reading back on the starting preset.

var _sw_i := -1
var _sw_wait := 0


func _process(delta: float) -> bool:
	if _phase == "next" and _view_i + 1 >= _views.size():
		_phase = "switching"
		_sw_i = -1
		_sw_wait = 0
	if _phase != "switching":
		return super(delta)
	_sw_wait -= 1
	if _sw_wait > 0:
		return false
	var n := int(_args.get("switches", "12"))
	var quality := int(_args.get("quality", "2"))
	if _sw_i >= 0:
		var mem := _process_memory()
		mem["switch"] = _sw_i if _sw_i <= n else -1
		mem["level"] = GraphicsQuality.level_name(GraphicsQuality.applied_level(self))
		mem["static_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		mem["video_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
		mem["texture_mb"] = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
		mem["buffer_mb"] = Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0
		_switch_memory.append(mem)
		print("SWITCH ", JSON.stringify(mem))
	_sw_i += 1
	if _sw_i > n + 1:
		_finish()
		return true
	if _sw_i == 0:
		pass # baseline reading follows after the settle frames, on the starting preset
	elif _sw_i <= n:
		GraphicsQuality.apply(self, GraphicsQuality.Level.MEDIUM if _sw_i % 2 == 1 else GraphicsQuality.Level.HIGH)
	else:
		GraphicsQuality.apply(self, quality)
	_sw_wait = int(_args.get("settle", "60"))
	return false
