extends SceneTree
## Headless checks of the graphics presets on the shipped world: each preset changes what it says, High is the
## authored scene, switching back and forth restores it exactly, and the choice survives a settings save.

var _passed := 0
var _total := 0


func _initialize() -> void:
	await process_frame
	var world := (load("res://scenes/world/colony_world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	var lighting := ZoneLighting.new()
	root.add_child(lighting)
	lighting.setup(world)
	await process_frame

	var env := (world.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sun := get_first_node_in_group(&"sun") as DirectionalLight3D
	var fixtures: Array[Node] = get_nodes_in_group(&"fixture_lights")
	var authored := _snapshot(env, sun, fixtures)
	_check(fixtures.size() > 300 and authored.shadows > 40, "world has its fixture lights with shadows (%d / %d)" % [authored.shadows, fixtures.size()])

	GraphicsQuality.apply(self, GraphicsQuality.Level.HIGH)
	_check(_snapshot(env, sun, fixtures) == authored, "High leaves the authored scene unchanged")
	_check(root.msaa_3d == Viewport.MSAA_2X and is_equal_approx(root.scaling_3d_scale, 1.0), "High: 2x MSAA at full resolution")

	GraphicsQuality.apply(self, GraphicsQuality.Level.LOW)
	var low := _snapshot(env, sun, fixtures)
	_check(low.shadows == 0, "Low: no fixture shadows")
	_check(low.faded == fixtures.size(), "Low: every fixture fades out with distance")
	_check(not env.ssao_enabled and not env.ssil_enabled and not env.ssr_enabled and not env.glow_enabled, "Low: SSAO, SSIL, SSR and glow off")
	_check(root.msaa_3d == Viewport.MSAA_DISABLED and root.scaling_3d_scale < 1.0 and root.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR, "Low: no MSAA, FSR at 75 %")
	_check(sun.directional_shadow_max_distance < authored.sun_dist, "Low: shorter sun shadow distance")

	GraphicsQuality.apply(self, GraphicsQuality.Level.MEDIUM)
	var med := _snapshot(env, sun, fixtures)
	_check(med.shadows == authored.shadows and med.faded == fixtures.size(), "Medium: fixture shadows on, faded with distance")
	_check(env.ssao_enabled and not env.ssil_enabled and not env.ssr_enabled and env.glow_enabled, "Medium: SSAO and glow only")
	_check(root.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA and root.msaa_3d == Viewport.MSAA_DISABLED, "Medium: FXAA instead of MSAA")

	GraphicsQuality.apply(self, GraphicsQuality.Level.ULTRA)
	_check(env.volumetric_fog_enabled and env.ssr_max_steps >= 96, "Ultra: volumetric haze and finer reflections")
	_check(root.msaa_3d == Viewport.MSAA_4X and root.positional_shadow_atlas_size == 8192, "Ultra: 4x MSAA and 8K shadow atlas")
	_check(sun.directional_shadow_max_distance > authored.sun_dist, "Ultra: longer sun shadow distance")

	GraphicsQuality.apply(self, GraphicsQuality.Level.LOW)
	GraphicsQuality.apply(self, GraphicsQuality.Level.HIGH)
	_check(_snapshot(env, sun, fixtures) == authored, "Low then High restores the authored scene exactly")
	_check(GraphicsQuality.applied_level(self) == GraphicsQuality.Level.HIGH, "applied level is remembered")

	# settings: stored, clamped, loaded
	var dir := ProjectSettings.globalize_path("res://_test_saves/diag")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("graphics_settings.json")
	var s := GameSettings.new()
	_check(s.graphics_quality == GraphicsQuality.Level.HIGH, "default preset is High")
	s.graphics_quality = 9
	_check(s.graphics_quality == GraphicsQuality.Level.ULTRA, "out of range clamps to Ultra")
	s.graphics_quality = GraphicsQuality.Level.MEDIUM
	s.save(path)
	_check(GameSettings.load_or_default(path).graphics_quality == GraphicsQuality.Level.MEDIUM, "preset survives save and load")
	s.apply(self)
	_check(GraphicsQuality.applied_level(self) == GraphicsQuality.Level.MEDIUM and not env.ssil_enabled, "GameSettings.apply puts the preset into effect")
	DirAccess.remove_absolute(path)

	# settings panel
	var panel := SettingsPanel.new()
	panel.settings = GameSettings.new()
	panel.settings_path = dir.path_join("graphics_panel.json")
	panel.input_path = dir.path_join("graphics_input.json")
	panel.setup(null)
	root.add_child(panel)
	await process_frame
	_check(panel.tabs().get_tab_title(2) == "Graphics" and panel.quality_button().item_count == 4, "Graphics tab offers four presets")
	_check(panel.quality_button().selected == GraphicsQuality.Level.HIGH, "panel shows the current preset")
	panel.quality_button().select(GraphicsQuality.Level.LOW)
	panel.quality_button().item_selected.emit(GraphicsQuality.Level.LOW)
	_check(panel.settings.graphics_quality == GraphicsQuality.Level.LOW and GraphicsQuality.applied_level(self) == GraphicsQuality.Level.LOW, "choosing Low in the panel applies it at once")
	panel.queue_free()
	await process_frame
	DirAccess.remove_absolute(dir.path_join("graphics_panel.json"))
	DirAccess.remove_absolute(dir.path_join("graphics_input.json"))

	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


func _snapshot(env: Environment, sun: DirectionalLight3D, fixtures: Array[Node]) -> Dictionary:
	var shadows := 0
	var faded := 0
	var fade_sum := 0.0
	for n: Node in fixtures:
		var l := n as Light3D
		shadows += int(l.shadow_enabled)
		faded += int(l.distance_fade_enabled)
		fade_sum += l.distance_fade_begin + l.distance_fade_shadow + l.distance_fade_length
	return {"shadows": shadows, "faded": faded, "fade_sum": fade_sum, "ssao": env.ssao_enabled, "ssil": env.ssil_enabled,
		"ssr": env.ssr_enabled, "ssr_steps": env.ssr_max_steps, "glow": env.glow_enabled, "vol": env.volumetric_fog_enabled,
		"sun_dist": sun.directional_shadow_max_distance, "sun_mode": sun.directional_shadow_mode}


func _check(ok: bool, what: String) -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS ", what)
	else:
		print("FAIL ", what)
