extends "res://tools/perf/perf_bench.gd"
## Names what happened in the frames that took long (diagnostic only). WINDOWED.
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/perf/probe_spikes.gd -- \
##       --quality=3 --cap=60 --window=2560x1369 --views=room_command_room,room_med_bay --seconds=20
## Each view: the camera turns slowly (as in perf_bench) for --seconds. Every frame over --over ms (default 25) is
## printed with what changed since the frame before: light view (zones lit / shadowed), render scale, current zone,
## zone states, GPU and CPU time.

var _sp_t := 0.0
var _sp_view := -1
var _sp_prev := {}
var _snap_t := 0.0
var _snap_dir := 1.0


func _process(delta: float) -> bool:
	if _phase == "next":
		_phase = "spikes"
		_sp_next()
		return false
	if _phase != "spikes":
		return super(delta)
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_us) / 1000.0
	_last_us = now
	if _args.has("snap"):
		# instant turns (a mouse flick): --snap=degrees every 1.5 s, alternating direction
		_snap_t += delta
		if _snap_t >= 1.5:
			_snap_t = 0.0
			_snap_dir = -_snap_dir
			(_game.get("player") as PlayerController).camera_rig().add_look(deg_to_rad(float(_args.snap)) * _snap_dir, 0.0)
	else:
		_update_view(_views[_sp_view], delta)
	var st := _state()
	if frame_ms > float(_args.get("over", "25")) and _sp_t > 1.0:
		var what: Array = []
		for k: String in st:
			if _sp_prev.has(k) and str(_sp_prev[k]) != str(st[k]):
				what.append("%s: %s -> %s" % [k, _sp_prev[k], st[k]])
		print("SPIKE %s t=%.2f %.1f ms gpu %.1f cpu %.1f | %s" % [_views[_sp_view].name, _sp_t, frame_ms,
			RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid),
			RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid), "; ".join(what) if not what.is_empty() else "nothing changed"])
	_sp_prev = st
	_sp_t += delta
	if _sp_t >= float(_args.get("seconds", "20")):
		if not _sp_next():
			quit(0)
			return true
	return false


func _sp_next() -> bool:
	if _sp_view < 0 and _args.has("noshadows"):
		for l: Node in get_nodes_in_group(&"fixture_lights"):
			(l as Light3D).shadow_enabled = false
	_sp_view += 1
	if _sp_view >= _views.size():
		return false
	_enter_view(_views[_sp_view])
	_sp_t = 0.0
	_sp_prev = {}
	return true


func _state() -> Dictionary:
	var zm: ZoneManager = (_game.get_node("Perf") as PerfRig).zone_manager
	var lit: Array = []
	var shad: Array = []
	var states: Array = []
	for z: Zone in zm.zones:
		if z.lights_awake and z.in_view:
			lit.append(ColonyZones.slug(String(z.zone_id)))
		if z.shadows_on:
			shad.append(ColonyZones.slug(String(z.zone_id)))
		states.append(z.state)
	return {"lit": ",".join(lit), "shadowed": ",".join(shad), "states": str(states),
		"scale": snappedf(root.scaling_3d_scale, 0.01), "current": String(zm.current.zone_id) if zm.current != null else "-"}
