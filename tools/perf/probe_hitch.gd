extends "res://tools/perf/perf_bench.gd"
## Finds what costs main-thread time (diagnostic only). WINDOWED.
##
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/perf/probe_hitch.gd -- \
##       --quality=3 --window=2560x1369 --views=room_command_room --seconds=4 [--targets=auto]
##
## Holds the camera still in the first view, then measures --seconds of frames with nothing changed, then with each
## candidate node's processing switched off in turn (process_mode DISABLED, restored after). Prints per case: mean
## frame ms, frames over 25 / 50 ms, worst frame, mean GPU ms. The candidate whose case loses the spikes owns them.

var _cands: Array = []
var _ci := -1
var _cf: Array = []
var _cwait := 0
var _saved_mode := -1


func _process(delta: float) -> bool:
	if _phase == "next":
		_enter_view(_views[0])
		_cands = [null]
		if _args.has("parent"):
			for n: Node in root.get_node(String(_args.parent)).find_children("*", "", true, false):
				if n.has_method("_process") or n.has_method("_physics_process") or n.get_child_count() > 0:
					_cands.append(n)
		elif _args.has("special"):
			_cands.append_array(["probes_hidden", "subviewports_off", "physics_off", "probes_hidden"])
		else:
			for n: Node in _game.get_children():
				_cands.append(n)
			for n: Node in root.get_children():
				if n != _game:
					_cands.append(n)
		_phase = "hitch"
		_next_cand()
		return false
	if _phase != "hitch":
		return super(delta)
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_us) / 1000.0
	_last_us = now
	if _cwait > 0:
		_cwait -= 1
		return false
	_cf.append([frame_ms, RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid),
		RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) + RenderingServer.get_frame_setup_time_cpu()])
	_t += delta
	if _t < float(_args.get("seconds", "4")):
		return false
	var tot := 0.0
	var gpu := 0.0
	var cpu := 0.0
	var over25 := 0
	var over50 := 0
	var worst := 0.0
	for f: Array in _cf:
		tot += f[0]
		gpu += f[1]
		cpu += f[2]
		over25 += 1 if f[0] > 25.0 else 0
		over50 += 1 if f[0] > 50.0 else 0
		worst = maxf(worst, f[0])
	var n := float(_cf.size())
	var label: String = "NONE" if _cands[_ci] == null else _cands[_ci] if _cands[_ci] is String else String((_cands[_ci] as Node).get_path())
	print("HITCH %-60s frames %4d mean %6.1f gpu %6.1f cpu %5.1f >25ms %4d >50ms %4d worst %6.1f" % [label, _cf.size(),
		tot / n, gpu / n, cpu / n, over25, over50, worst])
	if _args.has("dump") and _ci == 0:
		var s := ""
		for f: Array in _cf:
			s += "%.1f/%.1f " % [f[0], f[1]]
		print("DUMP ", s)
	if not _next_cand():
		quit(0)
		return true
	return false


var _special_saved: Array = []

func _special(c: String, on: bool) -> void:
	if on:
		_special_saved = []
		match c:
			"probes_hidden":
				for p: Node in root.find_children("*", "ReflectionProbe", true, false):
					_special_saved.append([p, "visible", p.get("visible")])
					p.set("visible", false)
			"subviewports_off":
				for v: Node in root.find_children("*", "SubViewport", true, false):
					_special_saved.append([v, "render_target_update_mode", v.get("render_target_update_mode")])
					v.set("render_target_update_mode", SubViewport.UPDATE_DISABLED)
				print("SUBVIEWPORTS ", _special_saved.size(), " ", _special_saved.map(func(s: Array) -> String: return "%s:%d" % [(s[0] as Node).get_path(), int(s[2])]))
			"physics_off":
				PhysicsServer3D.set_active(false)
	else:
		for s: Array in _special_saved:
			(s[0] as Object).set(s[1], s[2])
		_special_saved = []
		if c == "physics_off":
			PhysicsServer3D.set_active(true)


func _next_cand() -> bool:
	if _ci >= 0 and _cands[_ci] is String:
		_special(_cands[_ci], false)
	elif _ci >= 0 and _cands[_ci] != null and is_instance_valid(_cands[_ci]):
		(_cands[_ci] as Node).process_mode = _saved_mode
	_ci += 1
	if _ci >= _cands.size():
		return false
	if _cands[_ci] is String:
		_special(_cands[_ci], true)
	elif _cands[_ci] != null:
		var nd := _cands[_ci] as Node
		_saved_mode = nd.process_mode
		nd.process_mode = Node.PROCESS_MODE_DISABLED
	_cf = []
	_t = 0.0
	_cwait = 20
	return true
