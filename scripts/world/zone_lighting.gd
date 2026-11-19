class_name ZoneLighting
extends Node
## Switchable lighting state of the colony: per-zone fixture power, and day or night.
## Nothing here is baked. A powered-off zone loses its fixture lights AND the emission of its lamp surfaces, so no
## light energy is left behind; night removes the sun's direct light and dims the sky. The sol clock and the power
## simulation (Prompt 03, Prompt 07) drive this node through set_zone_powered() and set_sun_phase().

const Zones := preload("res://scripts/world/colony_zones.gd")

signal zone_power_changed(zone: String, powered: bool)

var _world: Node3D
var _zones: Zones
var _lights := {}            # zone -> Array[Light3D]
var _energy := {}            # Light3D -> authored energy
var _emissive := {}          # zone -> Array[MeshInstance3D] with a glowing surface (lamp lenses, screens)
var _powered := {}           # zone -> bool
var _awake := {}             # zone -> bool: false while the perf ZoneManager has put the zone to sleep (nobody can see it)
var _probes := {}            # zone -> ReflectionProbe carrying the room's ambient (bounce stand-in)
var _sun: DirectionalLight3D
var _sun_energy := 0.0
var _env: Environment
var _sky_energy := 1.0
var _sun_basis_noon: Basis


func setup(world: Node3D) -> void:
	_world = world
	_zones = Zones.from_manifest("res://data/colony_manifest.json")
	for n in world.get_node("Lights").get_children():
		var zone := String(n.get_meta("zone", ""))
		var arr: Array = []
		for l in n.get_children():
			if l is Light3D:
				arr.append(l)
				_energy[l] = (l as Light3D).light_energy
		_lights[zone] = arr
		_powered[zone] = true
	for n in world.get_children():
		if n is DirectionalLight3D:
			_sun = n
			_sun_energy = _sun.light_energy
			_sun_basis_noon = _sun.global_transform.basis
	var we := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we:
		_env = we.environment.duplicate()       # per-instance copy: runtime changes never touch the saved preset
		we.environment = _env
		_sky_energy = _env.background_energy_multiplier
	var probes := world.get_node_or_null("ReflectionProbes")
	if probes:
		for p in probes.get_children():
			_probes[String(p.get_meta("zone", ""))] = p
	_index_emissive(world.get_node("Colony"))


func zones() -> PackedStringArray:
	return PackedStringArray(_lights.keys())


func is_zone_powered(zone: String) -> bool:
	return bool(_powered.get(zone, true))


func set_zone_powered_by_slug(slug: String, powered: bool) -> void:
	for z in _lights.keys():
		if Zones.slug(String(z)) == slug:
			set_zone_powered(String(z), powered)
			return
	push_warning("ZoneLighting: no zone with slug '%s'" % slug)


func set_zone_powered(zone: String, powered: bool) -> void:
	if not _lights.has(zone):
		return
	_powered[zone] = powered
	_apply_lights(zone)
	for mi: MeshInstance3D in _emissive.get(zone, []):
		mi.set_instance_shader_parameter("power", 1.0 if powered else 0.0)
	if _probes.has(zone):
		# the room's ambient stands in for light bounced from its own fixtures: no fixtures, no bounce
		var probe: ReflectionProbe = _probes[zone]
		if probe.has_meta("ambient_full"):
			probe.ambient_color_energy = float(probe.get_meta("ambient_full")) if powered else 0.0
		_refresh_probe(probe)
	zone_power_changed.emit(zone, powered)


## Perf overhaul (res://perf/zone_manager.gd): a sleeping zone's fixtures are off whatever the power state, and waking
## it gives back exactly what the power simulation says. Emission and probes stay with the power state: a sleeping
## zone is not drawn, so its surfaces need no change.
func set_zone_awake(zone: String, awake: bool) -> void:
	if not _lights.has(zone) or bool(_awake.get(zone, true)) == awake:
		return
	_awake[zone] = awake
	_queue_lights(zone)


## Perf (2026-11-18): switching a zone's 15-50 lights in one frame made that frame 6-8 ms longer (the engine re-pairs
## every light with the geometry it reaches). Sleep / wake changes therefore go through a queue: up to
## VIEW_ON_PER_FRAME lights come on and VIEW_OFF_PER_FRAME go off per frame. Power changes stay immediate, and
## flush_queue() applies everything at once (ZoneManager.snap: teleport, fast travel, load).
const VIEW_ON_PER_FRAME := 8
const VIEW_OFF_PER_FRAME := 4
var _view_q: Dictionary = {}     # Light3D -> wanted visible


func _queue_lights(zone: String) -> void:
	var on := bool(_powered.get(zone, true)) and bool(_awake.get(zone, true))
	for l in _lights[zone]:
		var light := l as Light3D
		if light.visible == on:
			_view_q.erase(light)
		else:
			_view_q[light] = on


func flush_queue() -> void:
	for l: Variant in _view_q:
		if is_instance_valid(l):
			(l as Light3D).visible = bool(_view_q[l])
	_view_q.clear()


func _process(_delta: float) -> void:
	if _view_q.is_empty():
		return
	var ons := 0
	var offs := 0
	for l: Variant in _view_q.keys():
		if not is_instance_valid(l):
			_view_q.erase(l)
			continue
		var on := bool(_view_q[l])
		if on and ons < VIEW_ON_PER_FRAME:
			ons += 1
		elif not on and offs < VIEW_OFF_PER_FRAME:
			offs += 1
		else:
			continue
		(l as Light3D).visible = on
		_view_q.erase(l)


func is_zone_awake(zone: String) -> bool:
	return bool(_awake.get(zone, true))


## Perf light view (res://perf/zone_manager.gd, 2026-11-18): a zone the camera is not in draws its fixture lights
## without shadow maps. Composed with the graphics preset through GraphicsQuality.set_fixture_shadow_blocked, so a
## preset change keeps the block and lifting the block gives back exactly what the preset wants.
func set_zone_shadows(zone: String, allowed: bool) -> void:
	for l in _lights.get(zone, []):
		GraphicsQuality.set_fixture_shadow_blocked(l as Light3D, not allowed)


func _apply_lights(zone: String) -> void:
	var on := bool(_powered.get(zone, true)) and bool(_awake.get(zone, true))
	for l in _lights[zone]:
		_view_q.erase(l)
		(l as Light3D).visible = on


## 0.0 = midnight, 0.5 = local noon, 1.0 = next midnight. The authored reference sun is the noon state.
func set_sun_phase(phase: float) -> void:
	if _sun == null:
		return
	var elevation := sin((phase - 0.25) * TAU)                 # -1 at midnight, +1 at noon
	var day := clampf(elevation * 4.0, 0.0, 1.0)                # short twilight
	_sun.visible = day > 0.0
	_sun.light_energy = _sun_energy * day
	_sun.global_transform.basis = Basis(Vector3(0, 0, 1), (phase - 0.5) * TAU) * _sun_basis_noon
	if _env:
		_env.background_energy_multiplier = _sky_energy * lerpf(0.02, 1.0, day)


func set_night(night: bool) -> void:
	set_sun_phase(0.0 if night else 0.5)


## Re-render a probe's reflection once, so a powered-off room is not reflected as lit.
func _refresh_probe(probe: ReflectionProbe) -> void:
	probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	if is_inside_tree():
		await get_tree().create_timer(0.25).timeout
	probe.update_mode = ReflectionProbe.UPDATE_ONCE


func _index_emissive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as ShaderMaterial
			var e: Variant = m.get_shader_parameter("emission_energy") if m != null else null
			if e != null and float(e) > 0.0:
				var zone := _zones.zone_of(String(mi.get_meta("area", "")), mi.global_transform * mi.mesh.get_aabb().get_center())
				if not _emissive.has(zone):
					_emissive[zone] = []
				(_emissive[zone] as Array).append(mi)
				break
	for c in node.get_children():
		_index_emissive(c)
