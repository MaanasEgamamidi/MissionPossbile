class_name WeatherPresenter
extends Node
## Shows the dust in the world: the sun and the sky dim and a dusty fog thickens smoothly with state.dust_tau, all
## bounded (WeatherConfig: never darker than sun_min_share / sky_min_share, fog density at most fog_density_max), and a
## small bounded cloud of dust particles drifts around the local player while they are outside on a dusty day.
## No new art: plain fog, light energies and tiny untextured quads.
## Presentation only: it reads state and never changes it. The integrator adds it to the game scene and calls
## setup(world, services). It also gives the session's WeatherSystem the session, so warnings use the real sol length.
##
## ZoneLighting sets the sun energy and the sky brightness for the time of day every half second. This node scales
## whatever ZoneLighting last set (it remembers the value it wrote, and takes any other value as the new base), so
## the two never fight.

var config: WeatherConfig
var services: GameServices
var world: Node3D
## The opacity the sky shows now (follows state.dust_tau smoothly).
var shown_tau := 0.5
## Light and fog multipliers in use now (for tests and debugging).
var sun_share := 1.0
var sky_share := 1.0
var fog_density := 0.0
var particles: GPUParticles3D

var _sun: DirectionalLight3D
var _env: Environment
var _sun_base := -1.0
var _sun_written := -1.0
var _sky_base := -1.0
var _sky_written := -1.0
var _fog_was_enabled := false
var _fog_base_density := 0.0
var _fog_base_color := Color.WHITE
var _default_tau := 0.5


func _init(p_config: WeatherConfig = null) -> void:
	config = p_config if p_config != null else WeatherConfig.new()


## Connects to the world (may be null: then only the session wiring is done) and the game services.
func setup(p_world: Node3D, p_services: GameServices) -> void:
	world = p_world
	services = p_services
	if services != null:
		_default_tau = services.balance.dust_tau_default
		shown_tau = services.state().dust_tau if services.has_game() else _default_tau
		var system := WeatherSystem.of_session(services.session)
		if system != null:
			system.session = services.session
	if world == null:
		return
	for n in world.find_children("*", "DirectionalLight3D", true, false):
		_sun = n as DirectionalLight3D
		break
	var we := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null:
		for n in world.find_children("*", "WorldEnvironment", true, false):
			we = n as WorldEnvironment
			break
	if we != null and we.environment != null:
		_env = we.environment
		_fog_was_enabled = _env.fog_enabled
		_fog_base_density = _env.fog_density
		_fog_base_color = _env.fog_light_color
	_make_particles()


func _process(delta: float) -> void:
	if services == null or not services.has_game():
		return
	var tau := services.state().dust_tau
	# the shown sky follows the opacity smoothly (frame-rate independent)
	shown_tau = lerpf(shown_tau, tau, 1.0 - exp(-config.sky_follow_rate * maxf(delta, 0.0)))
	apply_sky(shown_tau)
	_update_particles(tau)


## Applies the light, sky and fog for an opacity (bounded). Public so tests can call it without waiting.
func apply_sky(tau: float) -> void:
	var balance := services.balance if services != null else GameBalance.new()
	var share := exp(-balance.dust_tau_factor * (tau - _default_tau))
	sun_share = clampf(share, config.sun_min_share, 1.0)
	sky_share = clampf(0.5 + 0.5 * share, config.sky_min_share, 1.0)
	fog_density = clampf(config.fog_density_per_tau * (tau - _default_tau), 0.0, config.fog_density_max)
	if _sun != null:
		if not is_equal_approx(_sun.light_energy, _sun_written) or _sun_base < 0.0:
			_sun_base = _sun.light_energy
		_sun_written = _sun_base * sun_share
		_sun.light_energy = _sun_written
	if _env != null:
		if not is_equal_approx(_env.background_energy_multiplier, _sky_written) or _sky_base < 0.0:
			_sky_base = _env.background_energy_multiplier
		_sky_written = _sky_base * sky_share
		_env.background_energy_multiplier = _sky_written
		if fog_density > 1e-5:
			_env.fog_enabled = true
			_env.fog_density = _fog_base_density + fog_density
			_env.fog_light_color = _fog_base_color.lerp(Color(0.62, 0.45, 0.32), clampf(fog_density / config.fog_density_max, 0.0, 1.0))
		else:
			_env.fog_enabled = _fog_was_enabled
			_env.fog_density = _fog_base_density
			_env.fog_light_color = _fog_base_color


func _make_particles() -> void:
	particles = GPUParticles3D.new()
	particles.name = "DustParticles"
	particles.amount = maxi(1, config.dust_particles_max)
	particles.lifetime = 3.0
	particles.emitting = false
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-12, -3, -12), Vector3(24, 8, 24))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(10, 2, 10)
	process.gravity = Vector3(0, -0.15, 0)
	process.direction = Vector3(1, 0, 0)
	process.spread = 25.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 2.0
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.04, 0.04)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.72, 0.52, 0.36, 0.55)
	quad.material = mat
	particles.draw_pass_1 = quad
	add_child(particles)


func _update_particles(tau: float) -> void:
	if particles == null:
		return
	var me := services.local_character()
	var dusty := tau - _default_tau > config.dust_particles_from_tau
	particles.emitting = me != null and me.outside and dusty
	if not particles.emitting:
		return
	particles.global_position = me.position + Vector3(0, 1.0, 0)
	particles.amount_ratio = clampf((tau - _default_tau - config.dust_particles_from_tau) / 1.5, 0.1, 1.0)
	var wind := float(services.state().weather.get("wind_ms", 3.0))
	var process := particles.process_material as ParticleProcessMaterial
	process.initial_velocity_min = clampf(0.2 * wind, 0.2, 3.0)
	process.initial_velocity_max = clampf(0.5 * wind, 0.5, 6.0)
