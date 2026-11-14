extends "res://tools/perf/perf_bench.gd"
## Feature cost check for Prompt 13 (diagnostic only, nothing is saved to the scene). WINDOWED.
##
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/perf/perf_ablation.gd -- \
##       --views=room_greenhouse,plaza_through_glass --frames=120 --out=G:/nasa app/_work/p13/perf/ablation.json
##
## For each named view the camera is held still and the same frames are measured with High, then with one feature
## turned off at a time (fixture shadows, area lights, all fixture lights, sun shadow, SSIL, SSR, SSAO, glow, MSAA),
## then with the Medium preset. Every case starts again from High, and the lights' own settings are restored.
## The difference to the High baseline is that feature's cost in this view, under the same GPU conditions.

const CASES := ["high", "no_fixture_shadows", "no_area_lights", "no_fixture_lights", "no_sun_shadow", "no_ssil",
	"no_ssr", "no_ssao", "no_glow", "msaa_off", "medium", "high_again"]

var _ab_view := -1
var _ab_case := 0
var _ab_frames: Array = []
var _ab_wait := 0
var _ab_out: Array = []
var _saved := {}


func _process(delta: float) -> bool:
	if _phase == "next":
		_phase = "ablate"
		_ab_view = -1
		_next_view()
		return false
	if _phase != "ablate":
		return super(delta)
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_us) / 1000.0
	_last_us = now
	if _ab_wait > 0:
		_ab_wait -= 1
		return false
	_ab_frames.append(_sample(frame_ms))
	if _ab_frames.size() < int(_args.get("frames", "120")):
		return false
	var s := _summarise(_views[_ab_view], _ab_frames)
	s["case"] = CASES[_ab_case]
	_ab_out.append(s)
	print("CASE ", _views[_ab_view].name, " ", CASES[_ab_case], " frame ", snappedf(s.summary.frame_ms.mean, 0.1),
		" gpu ", snappedf(s.summary.gpu_ms.mean, 0.1), " cpu ", snappedf(s.summary.cpu_ms.mean, 0.1),
		" draws ", int(s.summary.draw_calls.mean))
	_ab_case += 1
	if _ab_case >= CASES.size():
		if not _next_view():
			_write()
			return true
	else:
		_start_case()
	return false


func _next_view() -> bool:
	_ab_view += 1
	if _ab_view >= _views.size():
		return false
	_enter_view(_views[_ab_view])
	_ab_case = 0
	_start_case()
	_ab_wait = 40
	return true


func _start_case() -> void:
	_restore()
	GraphicsQuality.apply(self, GraphicsQuality.Level.HIGH)
	var c: String = CASES[_ab_case]
	var lights := get_nodes_in_group(&"fixture_lights")
	match c:
		"no_fixture_shadows":
			for l: Node in lights:
				_ab_set(l, "shadow_enabled", false)
		"no_area_lights":
			for l: Node in lights:
				if l.get_class() == "AreaLight3D":
					_ab_set(l, "visible", false)
		"no_fixture_lights":
			for l: Node in lights:
				_ab_set(l, "visible", false)
		"no_sun_shadow":
			for l: Node in get_nodes_in_group(&"sun"):
				_ab_set(l, "shadow_enabled", false)
		"no_ssil", "no_ssr", "no_ssao", "no_glow":
			var prop: String = {"no_ssil": "ssil_enabled", "no_ssr": "ssr_enabled", "no_ssao": "ssao_enabled", "no_glow": "glow_enabled"}[c]
			for we: Node in root.find_children("*", "WorldEnvironment", true, false):
				_ab_set((we as WorldEnvironment).environment, prop, false)
		"msaa_off":
			root.msaa_3d = Viewport.MSAA_DISABLED
		"medium":
			GraphicsQuality.apply(self, GraphicsQuality.Level.MEDIUM)
	_ab_frames = []
	_ab_wait = 20


func _ab_set(o: Object, prop: String, v: Variant) -> void:
	var key := [o, prop]
	if not _saved.has(key):
		_saved[key] = o.get(prop)
	o.set(prop, v)


func _restore() -> void:
	for key: Array in _saved:
		(key[0] as Object).set(key[1], _saved[key])
	_saved.clear()


func _write() -> void:
	_restore()
	GraphicsQuality.apply(self, GraphicsQuality.Level.HIGH)
	_results = _ab_out
	_finish()
