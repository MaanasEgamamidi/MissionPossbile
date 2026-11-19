extends "res://tools/perf/perf_bench.gd"
## Room crossings (diagnostic only). WINDOWED.
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/perf/probe_crossings.gd -- \
##       --quality=3 --cap=60 --window=2560x1369 [--over=20] [--laps=2]
## Moves the player at walking speed (4 m/s) through a chain of rooms, door by door (positions from the ZoneManager's
## doors; no collision on the way), facing the way it goes. Prints every frame over --over ms with what changed in it
## (current zone, zones lit / shadowed, render scale), and a summary per lap.

const SPEED := 4.0
const ROUTE := ["Command Room", "Dome plaza", "Power Room", "Airlock", "Greenhouse", "Crew corridor", "Mess hall",
	"Med Bay", "Dome plaza", "Command Room"]

var _pts: Array[Vector3] = []
var _seg := 0
var _seg_t := 0.0
var _lap := 0
var _cr_frames: Array = []
var _cr_prev := {}
var _cr_wait := 120
var _t_proc := 0
var _t_pre := 0
var _t_post := 0
var _hooked := false


func _process(delta: float) -> bool:
	if _phase == "next":
		if not _hooked:
			_hooked = true
			RenderingServer.frame_pre_draw.connect(func() -> void: _t_pre = Time.get_ticks_usec())
			RenderingServer.frame_post_draw.connect(func() -> void: _t_post = Time.get_ticks_usec())
		_build_route()
		var player: PlayerController = _game.get("player")
		player.input_enabled = false
		player.set_first_person(true)
		player.teleport(_pts[0], 0.0)
		_phase = "cross"
		return false
	if _phase != "cross":
		return super(delta)
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_us) / 1000.0
	_last_us = now
	if _cr_wait > 0:
		_cr_wait -= 1
		return false
	var player: PlayerController = _game.get("player")
	var a := _pts[_seg]
	var b := _pts[_seg + 1]
	var length := maxf(0.01, a.distance_to(b))
	_seg_t += delta * SPEED / length
	if _seg_t >= 1.0:
		_seg_t = 0.0
		_seg += 1
		if _seg >= _pts.size() - 1:
			_report()
			_lap += 1
			_seg = 0
			if _lap >= int(_args.get("laps", "2")):
				quit(0)
				return true
			player.teleport(_pts[0], 0.0)
			return false
		a = _pts[_seg]
		b = _pts[_seg + 1]
	var p := a.lerp(b, _seg_t)
	var dir := (b - a)
	player.global_position = p
	player.camera_rig().add_look(atan2(-dir.x, -dir.z) - player.camera_rig().yaw(), 0.0)
	_cr_frames.append(frame_ms)
	var st := _state()
	if frame_ms > float(_args.get("over", "20")):
		var what: Array = []
		for k: String in st:
			if _cr_prev.has(k) and str(_cr_prev[k]) != str(st[k]):
				what.append("%s: %s -> %s" % [k, _cr_prev[k], st[k]])
		var proc_ms := float(_t_pre - _t_proc) / 1000.0 if _t_pre > _t_proc else -1.0
		var draw_ms := float(_t_post - _t_pre) / 1000.0 if _t_post >= _t_pre else -1.0
		print("CROSS lap %d seg %d %.1f ms (process %.1f draw %.1f) gpu %.1f | %s" % [_lap, _seg, frame_ms, proc_ms, draw_ms,
			RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid), "; ".join(what) if not what.is_empty() else "nothing changed"])
	_cr_prev = st
	_t_proc = Time.get_ticks_usec()
	return false


func _build_route() -> void:
	var zm: ZoneManager = (_game.get_node("Perf") as PerfRig).zone_manager
	for i in ROUTE.size():
		var z := zm.zone(ROUTE[i])
		if z == null:
			continue
		if i > 0:
			var prev := zm.zone(ROUTE[i - 1])
			for d: ZoneDoor in zm.doors:
				if not d.is_window and d.joins(z) and d.joins(prev):
					_pts.append(Vector3(d.global_position.x, 0.05, d.global_position.z))
					break
		_pts.append(Vector3(z.centre.x, 0.05, z.centre.z))
	for i in _pts.size():
		print("ROUTE %d %s zone=%s" % [i, _pts[i], zm.room_at(_pts[i]).zone_id if zm.room_at(_pts[i]) != null else "-"])


func _report() -> void:
	var s := _cr_frames.duplicate()
	s.sort()
	var n := s.size()
	var over20 := s.filter(func(f: float) -> bool: return f > 20.0).size()
	var over25 := s.filter(func(f: float) -> bool: return f > 25.0).size()
	var tot := 0.0
	for f: float in s:
		tot += f
	print("CROSSLAP %d frames %d avg %.1f p99 %.1f worst %.1f >20ms %d >25ms %d" % [_lap, n, tot / n, s[int(n * 0.99)], s[n - 1], over20, over25])
	_cr_frames = []


func _state() -> Dictionary:
	var zm: ZoneManager = (_game.get_node("Perf") as PerfRig).zone_manager
	var lit: Array = []
	var shad: Array = []
	var drawn: Array = []
	for z: Zone in zm.zones:
		var slug := ColonyZones.slug(String(z.zone_id))
		if z.lights_awake and z.in_view:
			lit.append(slug)
		if z.shadows_on:
			shad.append(slug)
		if z.drawn:
			drawn.append(slug)
	var ext: ExteriorController = (_game.get_node("Perf") as PerfRig).exterior
	return {"mars_shown": ext.shown if ext != null else true, "outside": zm.player_outside,
		"current": String(zm.current.zone_id) if zm.current != null else "-", "drawn": ",".join(drawn),
		"lit": ",".join(lit), "shadowed": ",".join(shad), "scale": snappedf(root.scaling_3d_scale, 0.01)}
