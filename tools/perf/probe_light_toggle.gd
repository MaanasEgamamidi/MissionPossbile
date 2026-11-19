extends "res://tools/perf/perf_bench.gd"
## Cost of switching fixture lights on/off (diagnostic only). WINDOWED.
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/perf/probe_light_toggle.gd -- \
##       --quality=3 --window=2560x1369 --views=room_command_room
## Holds the view; every 10th frame flips N fixture lights (that are lit now) off, and back 5 frames later, either
## through `visible` or through distance fade (begin 0, length 0.001: culled, the light stays in the scene).
## Prints the mean frame time of the flip frames next to the others.

var _lt_mode := 0
var _lt_n := 0
var _lt_frames: Array = []
var _lt_flip: Array = []
var _lights: Array = []
var _saved := {}


func _process(delta: float) -> bool:
	if _phase == "next":
		_enter_view(_views[0])
		_phase = "toggle"
		_lt_frames = []
		return false
	if _phase != "toggle":
		return super(delta)
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_us) / 1000.0
	_last_us = now
	_lt_n += 1
	if _lt_n < 60:
		return false
	if _lights.is_empty():
		for l: Node in get_nodes_in_group(&"fixture_lights"):
			if (l as Light3D).is_visible_in_tree() and not (l as Light3D).shadow_enabled:
				_lights.append(l)
		_lights = _lights.slice(0, int(_args.get("n", "20")))
		for l: Light3D in _lights:
			_saved[l] = [l.distance_fade_enabled, l.distance_fade_begin, l.distance_fade_length]
	var k := _lt_n % 10
	_lt_frames.append(frame_ms)
	_lt_flip.append(k == 1 or k == 6)   # the frame after a flip
	if k == 0 or k == 5:
		var off := k == 0
		for l: Light3D in _lights:
			if _lt_mode == 0:
				l.visible = not off
			else:
				var s: Array = _saved[l]
				l.distance_fade_enabled = true if off else bool(s[0])
				l.distance_fade_begin = 0.0 if off else float(s[1])
				l.distance_fade_length = 0.001 if off else float(s[2])
	if _lt_frames.size() >= 300:
		var a := 0.0
		var na := 0
		var b := 0.0
		var nb := 0
		for i in _lt_frames.size():
			if _lt_flip[i]:
				a += _lt_frames[i]
				na += 1
			else:
				b += _lt_frames[i]
				nb += 1
		print("TOGGLE mode=%s lights=%d  frame after flip %.1f ms  other frames %.1f ms" % [["visible", "fade"][_lt_mode], _lights.size(), a / na, b / nb])
		_lt_mode += 1
		_lt_frames = []
		_lt_flip = []
		if _lt_mode > 1:
			quit(0)
			return true
	return false
