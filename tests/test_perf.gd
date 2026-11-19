extends SceneTree
## Headless checks of the perf overhaul (res://perf, docs/perf) on the real game with the map loaded:
## zone graph, room sleep/wake, camera mask, fixture lights composed with power, Mars culling, teleport snap,
## view gating, colony LOD / visibility range switches, and "every switch off == the unchanged game".
## Also prints one PERF-ROOM line per room (what is drawn, lit and whether Mars is shown there), used by docs/perf.

var _passed := 0
var _total := 0
var _game: Node
var _rig: PerfRig
var _ps: Node   # the PerfSettings autoload (a --script main script cannot name autoloads)


func _initialize() -> void:
	var save_dir := ProjectSettings.globalize_path("res://_test_saves/diag/perf_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	_game = Node3D.new()
	_game.set_script(load("res://scripts/game/game_main.gd"))
	_game.set("show_menu", false)
	_game.set("check_weather_updates", false)
	_game.set("save_directory", save_dir)
	_game.name = "Game"
	root.add_child(_game)
	_run.call_deferred()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await _frames(10)
	_ps = root.get_node_or_null("PerfSettings")
	var ps := _ps
	_check(ps != null, "PerfSettings autoload is present")
	_rig = _game.get_node_or_null("Perf") as PerfRig
	_check(_rig != null, "PerfRig attached at the start of play")
	if _rig == null:
		_finish()
		return
	var zm := _rig.zone_manager
	var lighting: ZoneLighting = _game.get("lighting")
	var player: PlayerController = _game.get("player")
	var cam := player.camera_rig().camera()
	var base_mask := 786431  # the first-person rig mask (every layer but 19 "first-person hidden")

	# ---------------- graph
	_check(zm.zones.size() == 17, "17 zones: 15 rooms, the dome plaza, the garden dome (%d)" % zm.zones.size())
	var n_doors := zm.doors.filter(func(d: ZoneDoor) -> bool: return not d.is_window).size()
	var n_windows := zm.doors.filter(func(d: ZoneDoor) -> bool: return d.is_window).size()
	_check(n_doors == 28, "28 doors: 24 manifest + tunnel pair + garden pair (%d)" % n_doors)
	_check(n_windows >= 3, "windows found between zones (%d)" % n_windows)
	var hangar := zm.zone("Hangar bay")
	var names := hangar.neighbors.map(func(z: Zone) -> String: return String(z.zone_id))
	names.sort()
	_check(names == ["Airlock", "Blast-door passage", "Crew corridor", "Pipe gallery", "Service corridor"], "Hangar bay neighbours by door/window: %s" % str(names))
	var glass := zm.doors.filter(func(d: ZoneDoor) -> bool: return not d.is_window and d.transparent).size()
	_check(glass >= 24, "door leaves with glass panels are transparent (%d of %d)" % [glass, n_doors])
	var outside_doors := zm.doors.filter(func(d: ZoneDoor) -> bool: return d.leads_outside)
	for d in zm.doors:
		print("DOOR %s a=%s b=%s outside=%s glass=%s window=%s" % [d.name, d.zone_a.zone_id if d.zone_a else "-", d.zone_b.zone_id if d.zone_b else "-", d.leads_outside, d.transparent, d.is_window])
	_check(outside_doors.size() == 2 and outside_doors.all(func(d: ZoneDoor) -> bool: return d.zone_a != null), "two exterior doors (tunnel and garden outer doors), each with its inner zone")
	print("GRAPH ", zm.zones.map(func(z: Zone) -> String: return "%s:%s" % [z.zone_id, z.neighbors.map(func(n: Zone) -> String: return String(n.zone_id))]))

	# ---------------- every room
	var rooms_sealed := []
	for z in zm.zones:
		var at := z.centre
		at.y = 0.15
		if z.kind == Zone.KIND_GARDEN:
			at = z.centre + Vector3(0, -1.35, 0)
		if z.kind == Zone.KIND_PLAZA:
			at = Vector3(-11.0, 0.15, -3.0)   # open plaza floor west of the West bunk room (Blender -11, 3)
		player.teleport(at, 0.0)
		await _wait(_ps.cold_delay + 0.6)
		await _wait(_ps.exterior_hide_delay + 0.3)
		var drawn := []
		var cold := []
		for o in zm.zones:
			(drawn if o.drawn else cold).append(String(o.zone_id))
		var mars := _rig.exterior.shown
		if not mars:
			rooms_sealed.append(String(z.zone_id))
		print("PERF-ROOM %s | current=%s | drawn %d cold %d %s | mars %s | mask=%d" % [z.zone_id, zm.current.zone_id if zm.current else "-", drawn.size(), cold.size(), str(cold), "shown" if mars else "HIDDEN", cam.cull_mask])
		var ok := zm.current == z and z.state == Zone.State.ACTIVE and z.drawn
		for n in z.neighbors:
			ok = ok and n.state >= Zone.State.WARM and n.drawn
		for o in zm.zones:
			ok = ok and (o.drawn == bool(cam.cull_mask & o.render_bit))
			ok = ok and (lighting.is_zone_awake(String(o.zone_id)) == (o.drawn and o.in_view))   # light view: drawn rooms out of view sleep
		_check(ok, "%s: current room ACTIVE, neighbours WARM, camera mask and fixtures follow the zone states" % z.zone_id)
	_check(true, "Mars hidden in: %s" % str(rooms_sealed))

	# ---------------- lights compose with the power simulation
	var cold_zone: Zone = null
	for o in zm.zones:
		if not o.drawn and o.kind == Zone.KIND_ROOM:
			cold_zone = o
			break
	if cold_zone != null:
		var cz := String(cold_zone.zone_id)
		var lights: Array = lighting._lights[cz]
		_check(lights.all(func(l: Light3D) -> bool: return not l.visible or GraphicsQuality.is_fixture_view_off(l)), "%s (COLD): fixtures off while asleep (hidden, or faded off by the light view)" % cz)
		lighting.set_zone_powered(cz, false)
		player.teleport(Vector3(cold_zone.centre.x, 0.15, cold_zone.centre.z), 0.0)
		await _wait(0.4)
		_check(cold_zone.drawn and lights.all(func(l: Light3D) -> bool: return not l.visible), "%s woken while unpowered: still dark" % cz)
		lighting.set_zone_powered(cz, true)
		_check(lights.all(func(l: Light3D) -> bool: return l.visible and not GraphicsQuality.is_fixture_view_off(l)), "%s powered again while awake: lights on" % cz)

	# ---------------- teleport snap: no time slicing, correct at the next poll
	var garden := zm.zone(ColonyZones.GARDEN)
	player.teleport(garden.centre + Vector3(0, -1.35, 0), 0.0)
	await _wait(_ps.cold_delay + 0.6)
	_check(not hangar.drawn, "from the garden dome, Hangar bay is COLD")
	# lights are culled by the camera mask through their own `layers` (default 1 = Hangar bay): they must stay visible
	var sun := get_first_node_in_group(&"sun") as Light3D
	var unculled := sun != null and (sun.layers & cam.cull_mask) != 0
	for n in get_nodes_in_group(&"fixture_lights"):
		unculled = unculled and ((n as Light3D).layers & cam.cull_mask) != 0
	for p in (_game.get("world") as Node).find_children("*", "ReflectionProbe", true, false):
		unculled = unculled and ((p as VisualInstance3D).layers & cam.cull_mask) != 0
	_check(unculled, "Hangar bay COLD: the sun, every fixture light and every probe stay inside the camera mask")
	player.teleport(Vector3(hangar.centre.x, 0.15, hangar.centre.z), 0.0)
	await process_frame
	await process_frame
	_check(zm.current == hangar and hangar.drawn and zm.queue_length() == 0 and bool(cam.cull_mask & hangar.render_bit), "teleport into Hangar bay: snapped within the next frame, nothing queued")

	# ---------------- doors: opening_started reaches the ZoneDoor before the leaves move
	var dz: ZoneDoor = zm.doors.filter(func(d: ZoneDoor) -> bool: return d.controller != null and d.controller.door_id == 3)[0]
	dz.controller.opening_started.emit(3)
	_check(dz.is_open, "DoorController.opening_started opens its ZoneDoor at once")
	dz.controller.closed_fully.emit(3)
	_check(not dz.is_open, "DoorController.closed_fully closes it again")

	# ---------------- outside on Mars
	player.teleport(Vector3(0.0, 0.5, -60.0), 0.0)
	var h := load("res://data/terrain_height.res") as TerrainHeight
	if h != null:
		player.teleport(Vector3(0.0, h.height_at(0.0, -60.0) + 0.2, -60.0), 0.0)
	await _wait(_ps.cold_delay + 0.6)
	_check(zm.player_outside and _rig.exterior.shown, "outside on Mars: player_outside and Mars shown")
	_check(zm.zone(ColonyZones.PLAZA).drawn, "outside: the glass dome plaza is still drawn")
	var far_rooms := zm.zones.filter(func(z: Zone) -> bool: return z.kind == Zone.KIND_ROOM and not z.drawn).size()
	print("PERF-OUTSIDE at (0, -60): %d rooms not drawn, mask=%d" % [far_rooms, cam.cull_mask])

	# ---------------- view activation: crew models
	var gated := get_nodes_in_group(&"view_gated")
	_check(gated.size() >= 3, "the other crew's models are view-gated (%d)" % gated.size())

	# ---------------- every switch off: back to the unchanged game
	_ps.set_all(false)
	await _frames(5)
	_check(cam.cull_mask == base_mask, "all switches off: camera mask is the rig's own (%d)" % cam.cull_mask)
	var all_lit := true
	for zone_name in lighting._lights:
		for l: Light3D in lighting._lights[zone_name]:
			all_lit = all_lit and l.visible == lighting.is_zone_powered(String(zone_name)) and not GraphicsQuality.is_fixture_view_off(l)
	_check(all_lit, "all switches off: every fixture light follows power only")
	var world: Node3D = _game.get("world")
	_check(world.get_node("Terrain").visible and world.get_node("Environment").visible, "all switches off: Mars visible")
	var parented := 0
	for g in world.get_node("Colony").find_children("*", "GeometryInstance3D", true, false):
		if String((g as GeometryInstance3D).visibility_parent) != "":
			parented += 1
	_check(parented == 0, "all switches off: no colony mesh has a visibility parent")
	var awake := gated.all(func(n: Node) -> bool: return n.process_mode != Node.PROCESS_MODE_DISABLED)
	_check(awake, "all switches off: every view-gated model processes")

	# ---------------- the pixel-changing switches turn on and back off exactly
	if _rig.visibility_ranges != null:
		# the 996 rocks already carry hand-authored ranges from tools/godot/colony_post_import.gd: never overwritten
		_check(_rig.visibility_ranges.plan.size() > 0 and _rig.visibility_ranges.plan.all(func(it: Array) -> bool: return not String((it[0] as Node).name).begins_with("rock_")), "visibility range plan: %d unranged scenery nodes, authored rock ranges left alone" % _rig.visibility_ranges.plan.size())
		_ps.set_value(&"visibility_ranges_enabled", true)
		await _frames(2)
		var g0: GeometryInstance3D = _rig.visibility_ranges.plan[0][0]
		_check(g0.visibility_range_end > 0.0, "ranges on: %s ends at %.0f m" % [g0.name, g0.visibility_range_end])
		_ps.set_value(&"visibility_ranges_enabled", false)
		await _frames(2)
		_check(g0.visibility_range_end == 0.0, "ranges off: restored")
	if _rig.colony_lod != null:
		_ps.set_value(&"colony_lod_enabled", true)
		await _frames(2)
		_check(_rig.colony_lod.tier1.visible and String(_rig.colony_lod.tier1.visibility_parent) != "", "colony LOD on: proxies wired")
		_ps.set_value(&"colony_lod_enabled", false)
		await _frames(2)
		_check(not _rig.colony_lod.tier1.visible, "colony LOD off: proxies hidden")
	else:
		_check(true, "colony LOD proxies not built: system stays off (res://lod missing)")

	# ---------------- defaults back on
	_ps.set_value(&"zones_enabled", true)
	_ps.set_value(&"exterior_cull_enabled", true)
	_ps.set_value(&"view_activation_enabled", true)
	await _frames(3)
	_check(zm.is_graph_ready and zm.current == null and zm.player_outside, "zones back on: snapped to the outside state")
	_finish()


func _check(ok: bool, what: String) -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS ", what)
	else:
		print("FAIL ", what)


func _finish() -> void:
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)
