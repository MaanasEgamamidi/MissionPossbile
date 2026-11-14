extends SceneTree
## Logic check of the switchable lighting (no GPU needed):
##   godot --headless --path . --script res://tools/godot/test_zone_lighting.gd -- --out <file.json>
## For every zone: power off -> every fixture light hidden, lamp surfaces not glowing, room ambient zero;
## power on -> authored values back. Night -> no sun, dim sky; day -> authored values back.
## Nothing is baked, so a state change cannot leave light behind.

const ZoneLightingScript := preload("res://scripts/world/zone_lighting.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var out := "res://data/test_zone_lighting.json"
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size():
			out = a[i + 1]
	var world: Node3D = (load("res://scenes/world/colony_world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var zl := ZoneLightingScript.new()
	world.add_child(zl)
	zl.setup(world)
	var fails: Array = []
	var rows: Array = []
	var sun: DirectionalLight3D = null
	for n in world.get_children():
		if n is DirectionalLight3D:
			sun = n
	var we := world.get_node("WorldEnvironment") as WorldEnvironment
	var probes := {}
	for p in world.get_node("ReflectionProbes").get_children():
		probes[String(p.get_meta("zone", ""))] = p
	for holder in world.get_node("Lights").get_children():
		var zone := String(holder.get_meta("zone", ""))
		var lights: Array = holder.get_children()
		var energy_on := {}
		for l in lights:
			energy_on[l] = (l as Light3D).light_energy
		var probe: ReflectionProbe = probes.get(zone)
		var amb_on := probe.ambient_color_energy if probe else -1.0
		var emissive: Array = zl._emissive.get(zone, [])
		zl.set_zone_powered(zone, false)
		var lit_off := 0
		for l in lights:
			if (l as Light3D).visible:
				lit_off += 1
		var glow_off := 0
		for mi: MeshInstance3D in emissive:
			if float(mi.get_instance_shader_parameter("power")) > 0.0:
				glow_off += 1
		var amb_off := probe.ambient_color_energy if probe else -1.0
		zl.set_zone_powered(zone, true)
		var lit_on := 0
		var energy_same := true
		for l in lights:
			if (l as Light3D).visible:
				lit_on += 1
			if not is_equal_approx((l as Light3D).light_energy, float(energy_on[l])):
				energy_same = false
		var glow_on := 0
		for mi: MeshInstance3D in emissive:
			if float(mi.get_instance_shader_parameter("power")) > 0.0:
				glow_on += 1
		var amb_back := probe.ambient_color_energy if probe else -1.0
		var ok := lit_off == 0 and glow_off == 0 and lit_on == lights.size() and glow_on == emissive.size() and energy_same
		if probe:
			ok = ok and is_zero_approx(amb_off) and is_equal_approx(amb_back, amb_on)
		if not ok:
			fails.append(zone)
		rows.append({"zone": zone, "fixtures": lights.size(), "glowing_meshes": emissive.size(), "lights_visible_when_off": lit_off,
			"glowing_when_off": glow_off, "ambient_on": snappedf(amb_on, 0.0001), "ambient_off": snappedf(amb_off, 0.0001), "restored": lit_on == lights.size() and energy_same, "ok": ok})
	# day / night
	var sun_e := sun.light_energy
	var sky_e := we.environment.background_energy_multiplier
	zl.set_night(true)
	var night := {"sun_visible": sun.visible, "sun_energy": sun.light_energy, "sky_energy": snappedf(we.environment.background_energy_multiplier, 0.0001)}
	zl.set_night(false)
	var day := {"sun_visible": sun.visible, "sun_energy": snappedf(sun.light_energy, 0.0001), "sky_energy": snappedf(we.environment.background_energy_multiplier, 0.0001)}
	var dn_ok: bool = (not bool(night.sun_visible)) and is_zero_approx(float(night.sun_energy)) and float(night.sky_energy) < sky_e * 0.05 and bool(day.sun_visible) \
		and is_equal_approx(sun.light_energy, sun_e) and is_equal_approx(we.environment.background_energy_multiplier, sky_e)
	if not dn_ok:
		fails.append("day/night")
	# the saved preset resource must be untouched by run-time switching
	var saved := load("res://scenes/world/lighting/env_reference_day.tres") as Environment
	var preset_untouched := is_equal_approx(saved.background_energy_multiplier, sky_e)
	if not preset_untouched:
		fails.append("saved environment modified")
	var lightmaps := 0
	for n in world.find_children("*", "LightmapGI", true, false):
		lightmaps += 1
	if lightmaps > 0:
		fails.append("LightmapGI present")
	var rep := {"ok": fails.is_empty(), "failed": fails, "zones": rows, "night": night, "day": day, "authored": {"sun_energy": snappedf(sun_e, 0.0001), "sky_energy": snappedf(sky_e, 0.0001)},
		"saved_environment_untouched": preset_untouched, "lightmap_nodes": lightmaps}
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(rep, " "))
	f.close()
	print("test_zone_lighting: ok=", rep.ok, " zones=", rows.size(), " failed=", fails)
	quit(0 if rep.ok else 1)
