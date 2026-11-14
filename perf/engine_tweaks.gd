class_name EngineTweaks
extends Node
## Phase 1 switches that change the authored look, so both are OFF by default (docs/perf/phase_1.md):
##   sun_shadow_tuning_enabled    sun: directional_shadow_max_distance 150 m (authored 160), fade start 0.8
##   light_distance_fade_enabled  every fixture OmniLight3D / SpotLight3D: distance fade 30 m + 10 m, shadow fade 25 m
##                                (only on lights that are not faded already: the Medium / Low presets fade their own)
## The authored values are captured when a switch turns on and written back exactly when it turns off. A graphics
## preset change while a switch is on re-applies the preset's own values; toggle the switch again after it.

var sun: DirectionalLight3D
var _sun_applied := false
var _fade_applied := false
var _sun_saved := {}
var _fade_saved := {}         # Light3D -> [enabled, begin, length, shadow]


func setup(sun_light: DirectionalLight3D) -> void:
	sun = sun_light


func _process(_delta: float) -> void:
	if Perf.cfg().sun_shadow_tuning_enabled != _sun_applied:
		_apply_sun(Perf.cfg().sun_shadow_tuning_enabled)
	if Perf.cfg().light_distance_fade_enabled != _fade_applied:
		_apply_fade(Perf.cfg().light_distance_fade_enabled)


func _apply_sun(on: bool) -> void:
	_sun_applied = on
	if sun == null:
		return
	if on:
		_sun_saved = {"dist": sun.directional_shadow_max_distance, "fade": sun.directional_shadow_fade_start}
		sun.directional_shadow_max_distance = Perf.cfg().sun_shadow_max_distance
		sun.directional_shadow_fade_start = Perf.cfg().sun_shadow_fade_start
	elif not _sun_saved.is_empty():
		sun.directional_shadow_max_distance = float(_sun_saved.dist)
		sun.directional_shadow_fade_start = float(_sun_saved.fade)


func _apply_fade(on: bool) -> void:
	_fade_applied = on
	if on:
		_fade_saved.clear()
		for n in get_tree().get_nodes_in_group(&"fixture_lights"):
			var l := n as Light3D
			if l == null or not (l is OmniLight3D or l is SpotLight3D) or l.distance_fade_enabled:
				continue
			_fade_saved[l] = [l.distance_fade_enabled, l.distance_fade_begin, l.distance_fade_length, l.distance_fade_shadow]
			l.distance_fade_enabled = true
			l.distance_fade_begin = Perf.cfg().light_fade_begin
			l.distance_fade_length = Perf.cfg().light_fade_length
			l.distance_fade_shadow = Perf.cfg().light_fade_shadow
	else:
		for l: Light3D in _fade_saved:
			if is_instance_valid(l):
				var s: Array = _fade_saved[l]
				l.distance_fade_enabled = s[0]
				l.distance_fade_begin = s[1]
				l.distance_fade_length = s[2]
				l.distance_fade_shadow = s[3]
		_fade_saved.clear()


func _exit_tree() -> void:
	if _sun_applied:
		_apply_sun(false)
	if _fade_applied:
		_apply_fade(false)
