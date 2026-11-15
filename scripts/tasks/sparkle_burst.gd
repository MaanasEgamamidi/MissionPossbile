extends Node3D
## The "it's fixed!" burst over a repaired broken part (2026-11-14, docs/revisions/BROKEN_PARTS_BRIEF.md, loop step 4).
## 60-120 small additive white-gold star sprites spread over the part's bounds, drifting up a little and fading out
## over about one second. Soft star sparkles only: no electric sparks, no fire look.
## GPUParticles3D normally; CPUParticles3D on the Low graphics preset (cheaper on weak GPUs, same look).
## The burst frees itself when its last star has faded. Loaded by path (no class_name).

## Seconds one star lives.
const LIFETIME := 1.0
const MIN_STARS := 60
const MAX_STARS := 120
## Star sprite size in metres.
const STAR_SIZE := 0.09
## Warm white to gold, then gone.
const COLORS: Array[Color] = [Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 0.98, 0.88, 1.0), Color(1.0, 0.86, 0.5, 0.9), Color(1.0, 0.76, 0.36, 0.0)]
const COLOR_STOPS: Array[float] = [0.0, 0.12, 0.6, 1.0]

static var _star_texture: Texture2D

## The particle node (GPUParticles3D or CPUParticles3D).
var particles: GeometryInstance3D
var star_count := 0
var _age := 0.0


## Makes a burst over `bounds` (world space) on render layers `layers` under `parent` and starts it.
static func spawn(parent: Node, bounds: AABB, layers: int, use_cpu: bool) -> Node3D:
	var script: GDScript = load("res://scripts/tasks/sparkle_burst.gd")
	var burst: Node3D = script.new()
	burst.name = "SparkleBurst"
	parent.add_child(burst)
	burst.call(&"build", bounds, layers, use_cpu)
	return burst


## Number of stars for a part of this size: more for big parts, always 60-120.
static func stars_for(size: Vector3) -> int:
	return clampi(MIN_STARS + int(size.x * size.z * 6.0 + size.y * 8.0), MIN_STARS, MAX_STARS)


func is_cpu() -> bool:
	return particles is CPUParticles3D


func build(bounds: AABB, layers: int, use_cpu: bool) -> void:
	global_position = bounds.get_center()
	var half := (bounds.size * 0.5).max(Vector3(0.15, 0.15, 0.15))
	star_count = stars_for(bounds.size)
	var quad := QuadMesh.new()
	quad.size = Vector2(STAR_SIZE, STAR_SIZE)
	quad.material = _star_material()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(COLOR_STOPS)
	gradient.colors = PackedColorArray(COLORS)
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
		cpu.spread = 35.0
		cpu.initial_velocity_min = 0.15
		cpu.initial_velocity_max = 0.45
		cpu.gravity = Vector3(0.0, 0.25, 0.0)
		cpu.damping_min = 0.2
		cpu.damping_max = 0.4
		cpu.angular_velocity_min = -90.0
		cpu.angular_velocity_max = 90.0
		cpu.scale_amount_min = 0.6
		cpu.scale_amount_max = 1.2
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
		gpu.visibility_aabb = AABB(-half - Vector3(1, 1, 1), half * 2.0 + Vector3(2, 2.5, 2))
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = half
		process.direction = Vector3.UP
		process.spread = 35.0
		process.initial_velocity_min = 0.15
		process.initial_velocity_max = 0.45
		process.gravity = Vector3(0.0, 0.25, 0.0)
		process.damping_min = 0.2
		process.damping_max = 0.4
		process.angular_velocity_min = -90.0
		process.angular_velocity_max = 90.0
		process.scale_min = 0.6
		process.scale_max = 1.2
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
	add_child(particles)
	particles.set(&"emitting", true)


func _process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME * 1.6:
		queue_free()


## Unshaded additive star sprite that faces the camera and takes the particle colour.
static func _star_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = star_texture()
	mat.disable_receive_shadows = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## A soft four-pointed star, drawn once in code (no texture file).
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
			var rays := exp(-absf(dx) * 26.0) * exp(-absf(dy) * 3.2) + exp(-absf(dy) * 26.0) * exp(-absf(dx) * 3.2)
			var a := clampf(core + rays * 0.85, 0.0, 1.0) * clampf(1.0 - r, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_star_texture = ImageTexture.create_from_image(img)
	return _star_texture
