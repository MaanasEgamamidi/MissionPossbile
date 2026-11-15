extends Node3D
## The "it's fixed!" burst over a repaired broken part (2026-11-14, docs/revisions/BROKEN_PARTS_BRIEF.md, loop step 4).
## 60-120 small additive white-gold star sprites spread over the part's bounds, drifting up a little and fading out
## over about one second. Soft star sparkles only: no electric sparks, no fire look.
## GPUParticles3D normally; CPUParticles3D on the Low graphics preset (cheaper on weak GPUs, same look).
## The burst frees itself when its last star has faded. Loaded by path (no class_name).
## Optional tint (2026-11-14): spawn(..., tint) colours the stars warm white -> `tint` (the tapes pass rich gold); with
## no tint the stars keep the white-gold look above (broken-part fixes).
## Easier to spot (owner 2026-11-15, UI Overhaul Prompt "Particle visibility"): the stars are about 2.5 times larger,
## carry a soft halo, live a little longer, and a burst over something low is raised to about chest height of the crew
## member standing by it (`chest_y`), keeping the part's footprint. A part that is already higher stays where it is.

## Seconds one star lives.
const LIFETIME := 1.3
const MIN_STARS := 60
const MAX_STARS := 120
## Star sprite size in metres (was 0.09: too small to spot from the third-person camera).
const STAR_SIZE := 0.22
## Chest height of a standing crew member above their feet, metres (the body is 1.8 m tall, the eyes are at 1.65 m).
const CHEST_HEIGHT := 1.25
## Half height of the band around chest height that a raised burst's stars appear in, metres.
const CHEST_BAND := 0.3
## A crew member within this distance of the part (on the ground plane) sets the chest height, metres.
const CHEST_RANGE := 14.0
## Warm white to gold, then gone.
const COLORS: Array[Color] = [Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 0.93, 0.6, 1.0), Color(1.0, 0.78, 0.25, 0.95), Color(0.95, 0.6, 0.1, 0.0)]
const COLOR_STOPS: Array[float] = [0.0, 0.12, 0.6, 1.0]

static var _star_texture: Texture2D

## The particle node (GPUParticles3D or CPUParticles3D).
var particles: GeometryInstance3D
var star_count := 0
## Metres the stars were raised above the centre of the bounds to reach chest height (0 = not raised).
var lift := 0.0
var _age := 0.0


## Makes a burst over `bounds` (world space) on render layers `layers` under `parent` and starts it. `tint` (alpha > 0)
## colours the stars; the default (transparent) keeps the usual white-gold. `chest_y` (world height, see chest_y_near)
## raises a low burst to chest height; NAN leaves it at the bounds.
static func spawn(parent: Node, bounds: AABB, layers: int, use_cpu: bool, tint := Color(0.0, 0.0, 0.0, 0.0), chest_y := NAN) -> Node3D:
	var script: GDScript = load("res://scripts/tasks/sparkle_burst.gd")
	var burst: Node3D = script.new()
	burst.name = "SparkleBurst"
	parent.add_child(burst)
	burst.call(&"build", bounds, layers, use_cpu, tint, chest_y)
	return burst


## World height of the chest of the crew member who should see a burst over `bounds`: `prefer` (this machine's player)
## when they stand within CHEST_RANGE of it on the same level, otherwise the nearest crew member who does. NAN when
## nobody is near (the burst then stays at the bounds).
static func chest_y_near(state: ColonyState, bounds: AABB, prefer: CharacterState = null) -> float:
	if state == null:
		return NAN
	var centre := bounds.get_center()
	var best := CHEST_RANGE * CHEST_RANGE
	var feet := NAN
	for c: CharacterState in state.characters.values():
		# Someone on another level (a deck, the ground outside a raised room) does not set the height.
		if c.position.y < bounds.position.y - 3.0 or c.position.y > bounds.end.y + 1.0:
			continue
		var d := Vector2(c.position.x - centre.x, c.position.z - centre.z).length_squared()
		if d > CHEST_RANGE * CHEST_RANGE:
			continue
		if c == prefer:
			return c.position.y + CHEST_HEIGHT
		if d < best:
			best = d
			feet = c.position.y
	return feet + CHEST_HEIGHT


## The colour ramp for a tinted burst: in white, warm white, `tint`, then gone.
static func tinted_colors(tint: Color) -> PackedColorArray:
	var c := Color(tint, 1.0)
	return PackedColorArray([Color(1.0, 1.0, 1.0, 0.0), Color(c.lightened(0.45), 1.0), Color(c, 0.95), Color(c.darkened(0.15), 0.0)])


## Number of stars for a part of this size: more for big parts, always 60-120.
static func stars_for(size: Vector3) -> int:
	return clampi(MIN_STARS + int(size.x * size.z * 6.0 + size.y * 8.0), MIN_STARS, MAX_STARS)


func is_cpu() -> bool:
	return particles is CPUParticles3D


func build(bounds: AABB, layers: int, use_cpu: bool, tint := Color(0.0, 0.0, 0.0, 0.0), chest_y := NAN) -> void:
	global_position = bounds.get_center()
	var half := (bounds.size * 0.5).max(Vector3(0.15, 0.15, 0.15))
	# Something low (a floor pipe, dust, a tape on a crate): the stars keep its footprint and appear in a band around
	# chest height, where the player is looking. The burst node itself stays at the centre of the bounds.
	lift = 0.0
	if not is_nan(chest_y) and chest_y > global_position.y:
		lift = chest_y - global_position.y
		half.y = clampf(half.y, 0.15, CHEST_BAND)
	star_count = stars_for(bounds.size)
	var quad := QuadMesh.new()
	quad.size = Vector2(STAR_SIZE, STAR_SIZE)
	quad.material = _star_material()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(COLOR_STOPS)
	gradient.colors = tinted_colors(tint) if tint.a > 0.0 else PackedColorArray(COLORS)
	var size_curve := Curve.new()
	size_curve.add_point(Vector2(0.0, 0.35))
	size_curve.add_point(Vector2(0.2, 1.0))
	size_curve.add_point(Vector2(1.0, 0.2))
	if use_cpu:
		var cpu := CPUParticles3D.new()
		cpu.name = "Stars"
		cpu.mesh = quad
		cpu.amount = star_count
		cpu.lifetime = LIFETIME
		cpu.one_shot = true
		cpu.explosiveness = 0.55
		cpu.randomness = 0.3
		cpu.local_coords = false
		cpu.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		cpu.emission_box_extents = half
		cpu.direction = Vector3.UP
		cpu.spread = 45.0
		cpu.initial_velocity_min = 0.25
		cpu.initial_velocity_max = 0.7
		cpu.gravity = Vector3(0.0, 0.25, 0.0)
		cpu.damping_min = 0.2
		cpu.damping_max = 0.4
		cpu.angular_velocity_min = -90.0
		cpu.angular_velocity_max = 90.0
		cpu.scale_amount_min = 0.75
		cpu.scale_amount_max = 1.4
		cpu.scale_amount_curve = size_curve
		cpu.color_ramp = gradient
		particles = cpu
	else:
		var gpu := GPUParticles3D.new()
		gpu.name = "Stars"
		gpu.draw_pass_1 = quad
		gpu.amount = star_count
		gpu.lifetime = LIFETIME
		gpu.one_shot = true
		gpu.explosiveness = 0.55
		gpu.randomness = 0.3
		gpu.local_coords = false
		gpu.visibility_aabb = AABB(-half - Vector3(1.2, 1.2, 1.2), half * 2.0 + Vector3(2.4, 3.4, 2.4))
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = half
		process.direction = Vector3.UP
		process.spread = 45.0
		process.initial_velocity_min = 0.25
		process.initial_velocity_max = 0.7
		process.gravity = Vector3(0.0, 0.25, 0.0)
		process.damping_min = 0.2
		process.damping_max = 0.4
		process.angular_velocity_min = -90.0
		process.angular_velocity_max = 90.0
		process.scale_min = 0.75
		process.scale_max = 1.4
		var size_texture := CurveTexture.new()
		size_texture.curve = size_curve
		process.scale_curve = size_texture
		var color_texture := GradientTexture1D.new()
		color_texture.gradient = gradient
		process.color_ramp = color_texture
		gpu.process_material = process
		particles = gpu
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The room camera only draws the layers of the rooms it can see: the stars carry the part's room layers.
	particles.layers = layers if layers != 0 else 1
	particles.position = Vector3(0.0, lift, 0.0)
	add_child(particles)
	particles.set(&"emitting", true)


func _process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME * 1.6:
		queue_free()


## Unshaded star sprite that faces the camera and takes the particle colour. Alpha blended, not additive: added light
## disappears against the base's bright walls, a gold star with a darker rim reads on light and dark alike.
static func _star_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = star_texture()
	mat.disable_receive_shadows = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## A soft four-pointed star in a faint round halo, drawn once in code (no texture file), with mipmaps.
static func star_texture() -> Texture2D:
	if _star_texture != null:
		return _star_texture
	const N := 64
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var dx := (float(x) + 0.5) / N * 2.0 - 1.0
			var dy := (float(y) + 0.5) / N * 2.0 - 1.0
			var r := sqrt(dx * dx + dy * dy)
			var core := exp(-r * r * 22.0)
			var halo := exp(-r * r * 5.0) * 0.55
			var rays := exp(-absf(dx) * 20.0) * exp(-absf(dy) * 2.8) + exp(-absf(dy) * 20.0) * exp(-absf(dx) * 2.8)
			var a := clampf(core * 1.2 + rays + halo, 0.0, 1.0) * clampf((1.0 - r) * 1.6, 0.0, 1.0)
			# Bright centre, darker rim (multiplied by the particle's gold), so a star has its own contrast.
			var v := lerpf(1.0, 0.62, clampf(r * 2.2 - 0.25, 0.0, 1.0))
			v = lerpf(v, 1.0, clampf(core * 1.4, 0.0, 1.0))
			img.set_pixel(x, y, Color(v, v * 0.92, v * 0.8, a))
	img.generate_mipmaps()
	_star_texture = ImageTexture.create_from_image(img)
	return _star_texture
