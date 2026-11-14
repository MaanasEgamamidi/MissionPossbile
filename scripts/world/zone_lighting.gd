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
	for l in _lights[zone]:
		(l as Light3D).visible = powered
	for mi: MeshInstance3D in _emissive.get(zone, []):
		mi.set_instance_shader_parameter("power", 1.0 if powered else 0.0)
	if _probes.has(zone):
		# the room's ambient stands in for light bounced from its own fixtures: no fixtures, no bounce
		var probe: ReflectionProbe = _probes[zone]
		if probe.has_meta("ambient_full"):
			probe.ambient_color_energy = float(probe.get_meta("ambient_full")) if powered else 0.0
		_refresh_probe(probe)
	zone_power_changed.emit(zone, powered)


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
