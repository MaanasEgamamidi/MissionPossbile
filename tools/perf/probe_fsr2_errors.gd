extends "res://tools/perf/perf_bench.gd"
## Which kind of node makes FSR 2 print 'Parameter "uniform_set" is null' (diagnostic only). WINDOWED.
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/perf/probe_fsr2_errors.gd -- \
##       --quality=3 --window=2560x1369 --views=room_command_room
## Holds the view with FSR 2 at 0.77 and DynamicResolution stopped; every 1.5 s hides one kind of node (and shows the
## previous kind again), printing a FSR2STEP marker first, so the errors can be counted per step.

const STEPS := ["none", "GPUParticles3D", "CPUParticles3D", "Decal", "FogVolume", "ReflectionProbe", "ShadowProxy",
	"MultiMeshInstance3D", "Label3D", "SpriteBase3D", "shader:MeshInstance3D", "plain:MeshInstance3D", "none"]

var _fe_i := -1
var _fe_t := 0.0
var _fe_hidden: Array = []


func _process(delta: float) -> bool:
	if _phase == "next":
		_enter_view(_views[0])
		var drs := _game.get_node_or_null("DynamicResolution")
		if drs != null:
			drs.set_process(false)
			drs.set_physics_process(false)
		root.msaa_3d = Viewport.MSAA_DISABLED
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		root.scaling_3d_scale = 0.77
		_phase = "steps"
		_fe_t = 99.0
		return false
	if _phase != "steps":
		return super(delta)
	_fe_t += delta
	if _fe_t >= 1.5:
		_fe_t = 0.0
		for n: Node3D in _fe_hidden:
			if is_instance_valid(n):
				n.visible = true
		_fe_hidden = []
		_fe_i += 1
		if _fe_i >= STEPS.size():
			print("FSR2STEP end")
			quit(0)
			return true
		if _fe_i == 0 and _args.has("dump"):
			_find_parts(root)
			_dump_parts()
		if _mode_steps():
			return false
		if _seq_steps():
			return false
		if _only_steps():
			return false
		var step: String = STEPS[_fe_i]
		if _args.has("each") and step == "GPUParticles3D":
			_each_particles()
			return false
		if step != "none":
			_collect(root, step)
		print("FSR2STEP %s (hid %d)" % [step, _fe_hidden.size()])
	return false


func _collect(n: Node, step: String) -> void:
	if n is Node3D and (n as Node3D).visible and _matches(n, step):
		(n as Node3D).visible = false
		_fe_hidden.append(n)
	for c: Node in n.get_children():
		_collect(c, step)


func _matches(n: Node, step: String) -> bool:
	if step == "ShadowProxy":
		return n.name == &"ShadowProxy"
	if step.begins_with("shader:") or step.begins_with("plain:"):
		if not (n is MeshInstance3D) or n.name == &"ShadowProxy":
			return false
		var has_shader := false
		var mi := n as MeshInstance3D
		if mi.material_override is ShaderMaterial:
			has_shader = true
		elif mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s)
				if m is ShaderMaterial:
					has_shader = true
					break
		return has_shader == step.begins_with("shader:")
	return n.is_class(step)


## --each: hides the particle systems one at a time instead (the step where the errors stop names the one).
var _fe_parts: Array = []
var _fe_pi := -1


func _each_particles() -> void:
	if _fe_parts.is_empty():
		_find_parts(root)
	_fe_pi += 1
	if _fe_pi >= _fe_parts.size():
		print("FSR2STEP particles done")
		return
	_fe_i -= 1
	var p: GPUParticles3D = _fe_parts[_fe_pi]
	p.visible = false
	_fe_hidden.append(p)
	var pm := p.process_material
	print("FSR2STEP particle %s emitting=%s trail=%s amount=%d local=%s mat=%s draw_passes=%d path=%s" % [p.name, p.emitting,
		p.trail_enabled, p.amount, p.local_coords, pm.get_class() if pm != null else "null", p.draw_passes,
		root.get_path_to(p)])


func _find_parts(n: Node) -> void:
	if n is GPUParticles3D and (n as GPUParticles3D).visible:
		_fe_parts.append(n)
	for c: Node in n.get_children():
		_find_parts(c)


## --only=<node path under root>: STEPS become "hide it" then "show it again" (two steps of 1.5 s each).
func _only_steps() -> bool:
	if not _args.has("only"):
		return false
	var n := root.get_node_or_null(NodePath(String(_args.only))) as Node3D
	if n == null:
		print("FSR2STEP no node ", _args.only)
		return true
	match _fe_i:
		0:
			print("FSR2STEP before (shown)")
		1:
			n.visible = false
			print("FSR2STEP hidden %s" % _args.only)
		2:
			n.visible = true
			print("FSR2STEP shown again")
		3:
			print("FSR2STEP still shown")
		_:
			print("FSR2STEP end")
			quit(0)
	return true


func _dump_parts() -> void:
	var cam := root.get_camera_3d()
	for p: GPUParticles3D in _fe_parts:
		print("FSR2DUMP %s in_tree_visible=%s layers=%d vis_range=[%.1f..%.1f mode %d] cast=%d gpos=%s dist=%.1f aabb=%s fixed_fps=%d interp=%s preprocess=%.1f lifetime=%.1f speed=%.2f transform_align=%d mesh=%s mat_override=%s parent_visible=%s" % [
			root.get_path_to(p), p.is_visible_in_tree(), p.layers, p.visibility_range_begin, p.visibility_range_end,
			p.visibility_range_fade_mode, p.cast_shadow, p.global_position, cam.global_position.distance_to(p.global_position),
			p.visibility_aabb, p.fixed_fps, p.interpolate, p.preprocess, p.lifetime, p.speed_scale, p.transform_align,
			p.draw_pass_1, p.material_override, (p.get_parent() as Node3D).visible])


## --seq: with the green-dome tape sparkles: as loaded, restart(), camera turned away, turned back, hide+show, restart().
func _seq_steps() -> bool:
	if not _args.has("seq"):
		return false
	var p := root.get_node_or_null(^"Game/Collision/Stations/cassette_green_dome/TapeSparkles") as GPUParticles3D
	var player: PlayerController = _game.get("player")
	match _fe_i:
		0:
			print("FSR2STEP as loaded")
		1:
			p.restart()
			print("FSR2STEP after restart()")
		2:
			player.camera_rig().add_look(PI, 0.0)
			print("FSR2STEP camera turned away")
		3:
			player.camera_rig().add_look(-PI, 0.0)
			print("FSR2STEP camera turned back")
		4:
			p.visible = false
			print("FSR2STEP hidden")
		5:
			p.visible = true
			print("FSR2STEP shown")
		6:
			p.restart()
			print("FSR2STEP restart() again")
		7:
			p.emitting = false
			print("FSR2STEP emitting off")
		8:
			p.restart()
			print("FSR2STEP restart() after off")
		_:
			print("FSR2STEP end")
			quit(0)
	return true


## --modes: fix the green-dome sparkles by hide+show, then switch the upscaler off and on again.
func _mode_steps() -> bool:
	if not _args.has("modes"):
		return false
	var p := root.get_node_or_null(^"Game/Collision/Stations/cassette_green_dome/TapeSparkles") as GPUParticles3D
	match _fe_i:
		0:
			print("FSR2STEP as loaded")
		1:
			p.visible = false
			print("FSR2STEP hidden")
		2:
			p.visible = true
			print("FSR2STEP shown (fixed)")
		3:
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			print("FSR2STEP bilinear")
		4:
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			print("FSR2STEP fsr2 again")
		5:
			print("FSR2STEP fsr2 still")
		_:
			print("FSR2STEP end")
			quit(0)
	return true
