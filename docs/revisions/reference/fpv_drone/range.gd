extends Node3D

const GATE_WIDTH := 5.4
const GATE_HEIGHT := 3.3
const GATE_ACTIVE := Color("#77f8db")
const GATE_INACTIVE := Color("#98623c")
const GATE_PASSED := Color("#466667")

@export_range(10.0, 1800.0, 1.0, "suffix:s") var battery_life_seconds := 360.0

@onready var drone = $Drone
@onready var hud = $HUD/FlightHUD

var _gates: Array[StandardMaterial3D] = []
var _next_gate := 0
var _flying := false
var _flight_seconds := 0.0


func _ready() -> void:
	_build_environment()
	_build_airfield()
	_gate(Vector3(0, 2.65, -12), 0.0)
	_gate(Vector3(0, 4.25, -32), 0.0)
	_gate(Vector3(12, 5.9, -49), -36.0)
	_gate(Vector3(32, 7.1, -56), -70.0)
	_gate(Vector3(49, 4.8, -43), -140.0)
	_gate(Vector3(49, 2.65, -21), 180.0)
	_update_gates()
	hud.fly_requested.connect(_start_flying)
	drone.camera_changed.connect(hud.show_camera)
	get_window().focus_exited.connect(_pause_flight)


func _process(delta: float) -> void:
	if _flying:
		_flight_seconds += delta
		_update_telemetry()


func _unhandled_input(event: InputEvent) -> void:
	if not _flying:
		return

	if event is InputEventMouseMotion:
		drone.steer_mouse(event.screen_relative.x)
	elif event.is_action_pressed(&"ui_cancel"):
		_pause_flight()
	elif event.is_action_pressed(&"toggle_camera"):
		drone.toggle_camera()
	elif event.is_action_pressed(&"reset_flight"):
		drone.respawn()
		_next_gate = 0
		_flight_seconds = 0.0
		_update_gates()
		_update_telemetry()


func _start_flying() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_flying = true
	hud.hide_menu()
	drone.set_controls_active(true)
	_update_telemetry()


func _pause_flight() -> void:
	if not _flying:
		return
	_flying = false
	drone.set_controls_active(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_pause()


func _update_telemetry() -> void:
	var pose: Transform3D = drone.get_global_transform_interpolated()
	var forward := -pose.basis.z
	var heading := rad_to_deg(atan2(forward.x, -forward.z))
	var offset: Vector3 = pose.origin - drone.spawn_transform.origin
	var motion: Vector3 = drone.velocity
	hud.show_telemetry(_flight_seconds, battery_life_seconds, heading,
		Vector2(motion.x, motion.z).length(), Vector2(offset.x, offset.z).length())


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#458aab")
	sky_material.sky_horizon_color = Color("#b1cbd0")
	sky_material.ground_horizon_color = Color("#b1cbd0")
	sky_material.ground_bottom_color = Color("#b08762")
	sky_material.sun_angle_max = 21.0
	sky_material.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c2dce7")
	environment.ambient_light_energy = 0.7
	environment.fog_enabled = true
	environment.fog_density = 0.0018
	environment.fog_light_color = Color("#c3c6b8")
	environment.fog_sky_affect = 0.0
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -42, 0)
	sun.light_color = Color("#ffdfab")
	sun.light_energy = 1.32
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 125.0
	add_child(sun)

	var ground := _box(self, Vector3(0, -0.3, 0), Vector3(1100, 0.6, 1100), null, true)
	var terrain := ShaderMaterial.new()
	terrain.shader = preload("res://desert.gdshader")
	ground.material_override = terrain

	var rng := RandomNumberGenerator.new()
	rng.seed = 8271
	var stone := _material(Color("#aa7b62"))
	var rimrock := _material(Color("#9c6c55"))
	for index in 24:
		var angle := TAU * float(index) / 24.0 + rng.randf_range(-0.09, 0.09)
		var distance := rng.randf_range(122.0, 204.0)
		var height := rng.randf_range(9.0, 26.0)
		var width := rng.randf_range(12.0, 32.0)
		var location := Vector3(cos(angle) * distance, 0, sin(angle) * distance)
		_mesa_part(location + Vector3.UP * height * 0.4, height * 0.8, width, width * 0.56, angle, stone)
		_mesa_part(location + Vector3.UP * height * 0.89, height * 0.18, width * 0.56, width * 0.48, angle, rimrock)


func _build_airfield() -> void:
	var tarmac := _material(Color("#343f42"))
	var shoulder := _material(Color("#655449"))
	var chalk := _material(Color("#ddd4b6"))
	var ochre := _material(Color("#ecac51"))
	var dark := _material(Color("#26373b"))
	var steel := _material(Color("#587477"))
	var roof := _material(Color("#32484b"))
	var rust := _material(Color("#9c533e"))
	var concrete := _material(Color("#9a8974"))

	_box(self, Vector3(0, 0.018, -16), Vector3(14.0, 0.036, 91), shoulder)
	_box(self, Vector3(0, 0.028, -16), Vector3(11.8, 0.054, 90), tarmac, true)
	for side in [-1, 1]:
		_box(self, Vector3(side * 5.3, 0.059, -16), Vector3(0.12, 0.012, 87), chalk)
		for index in 12:
			_box(self, Vector3(side * 6.4, 0.055, 25 - index * 7.5), Vector3(0.24, 0.08, 0.5), ochre)
	for index in 9:
		_box(self, Vector3(0, 0.062, 9 - index * 7.5), Vector3(0.15, 0.012, 2.8), chalk)
	for line in [-1.35, 1.35]:
		_box(self, Vector3(line, 0.062, 16), Vector3(0.13, 0.014, 2.7), ochre)
		_box(self, Vector3(0, 0.062, 16 + line), Vector3(2.7, 0.014, 0.13), ochre)
	_box(self, Vector3(-0.43, 0.064, 16), Vector3(0.13, 0.015, 1.15), ochre)
	_box(self, Vector3(0.43, 0.064, 16), Vector3(0.13, 0.015, 1.15), ochre)
	_box(self, Vector3(0, 0.064, 16), Vector3(0.86, 0.015, 0.12), ochre)

	for index in 3:
		var z := -5.0 - index * 12.0
		_box(self, Vector3(-14, 0.09, z + 2), Vector3(12, 0.18, 10.4), concrete, true)
		_box(self, Vector3(-14, 1.85, z), Vector3(8.4, 3.7, 6.6), steel, true)
		_box(self, Vector3(-14, 3.8, z), Vector3(8.9, 0.32, 7.0), roof)
		_box(self, Vector3(-14, 1.37, z + 3.32), Vector3(4.9, 2.44, 0.1), dark)
		for slat in 7:
			_box(self, Vector3(-14, 0.49 + slat * 0.32, z + 3.39), Vector3(4.8, 0.036, 0.04), steel)
		_box(self, Vector3(-14, 3.21, z + 3.36), Vector3(1.8, 0.24, 0.05), ochre)

	for location in [Vector3(12, 0, 1), Vector3(16, 0, -6), Vector3(13, 0, -16),
			Vector3(21, 0, -26), Vector3(39, 0, -30), Vector3(57, 0, -39),
			Vector3(59, 0, -16), Vector3(38, 0, -63)]:
		var container_color := rust if int(location.x) % 2 == 0 else steel
		_box(self, location + Vector3.UP * 1.08, Vector3(3.0, 2.16, 5.4), container_color, true)
		_box(self, location + Vector3.UP * 2.15, Vector3(3.08, 0.16, 5.48), dark)
		for rib in 8:
			_box(self, location + Vector3(1.52, 1.08, -2.32 + rib * 0.66),
				Vector3(0.085, 1.94, 0.075), dark)

	for index in 18:
		var z := 16.0 - index * 4.0
		_box(self, Vector3(-22.5, 0.7, z), Vector3(0.16, 1.4, 0.16), dark)
	_box(self, Vector3(-22.5, 1.02, -18), Vector3(0.095, 0.07, 68), steel)
	_box(self, Vector3(-22.5, 0.57, -18), Vector3(0.095, 0.07, 68), steel)

	_box(self, Vector3(8.5, 1.05, 3.5), Vector3(0.18, 2.1, 0.18), dark, true)
	_box(self, Vector3(8.5, 2.28, 3.5), Vector3(3.4, 0.95, 0.25), dark, true)
	var sign_text := Label3D.new()
	sign_text.text = "DRYLINE"
	sign_text.position = Vector3(8.5, 2.27, 3.64)
	sign_text.pixel_size = 0.015
	sign_text.font_size = 36
	sign_text.outline_size = 0
	sign_text.modulate = chalk.albedo_color
	add_child(sign_text)


func _gate(center: Vector3, heading_degrees: float) -> void:
	var index := _gates.size()
	var gate := Node3D.new()
	gate.position = center
	gate.rotation_degrees.y = heading_degrees
	add_child(gate)

	var frame := _material(Color("#293c3e"))
	var paint := _material(Color("#d89143"))
	var light := _material(GATE_INACTIVE)
	light.emission_enabled = true
	_gates.append(light)

	for side in [-1, 1]:
		var x: float = side * (GATE_WIDTH * 0.5 + 0.15)
		var support_height := center.y + GATE_HEIGHT * 0.5 + 0.15
		_box(gate, Vector3(x, support_height * 0.5 - center.y, 0),
			Vector3(0.3, support_height, 0.38), frame, true)
		_box(gate, Vector3(x, 0, 0.2), Vector3(0.14, GATE_HEIGHT, 0.05), light)
		_box(gate, Vector3(x, 0, -0.2), Vector3(0.14, GATE_HEIGHT, 0.05), light)
		_box(gate, Vector3(x, 0.18 - center.y, 0), Vector3(0.72, 0.36, 0.9), paint, true)

	var top := GATE_HEIGHT * 0.5 + 0.15
	_box(gate, Vector3(0, top, 0), Vector3(GATE_WIDTH, 0.3, 0.38), frame, true)
	_box(gate, Vector3(0, top, 0.2), Vector3(GATE_WIDTH, 0.13, 0.05), light)
	_box(gate, Vector3(0, top, -0.2), Vector3(GATE_WIDTH, 0.13, 0.05), light)
	_box(gate, Vector3(0, top + 0.29, 0), Vector3(0.92, 0.52, 0.24), frame)
	var number := Label3D.new()
	number.text = "%02d" % (index + 1)
	number.position = Vector3(0, top + 0.29, 0.13)
	number.font_size = 32
	number.pixel_size = 0.011
	number.outline_size = 0
	number.modulate = Color("#f7ede0")
	gate.add_child(number)

	var trigger := Area3D.new()
	trigger.collision_layer = 0
	trigger.collision_mask = 2
	trigger.monitorable = false
	var sensor := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(GATE_WIDTH - 0.12, GATE_HEIGHT - 0.12, 0.38)
	sensor.shape = shape
	trigger.add_child(sensor)
	gate.add_child(trigger)
	trigger.body_entered.connect(_gate_entered.bind(index))


func _gate_entered(body: Node3D, index: int) -> void:
	if body == drone and index == _next_gate:
		_next_gate += 1
		_update_gates()


func _update_gates() -> void:
	for index in _gates.size():
		var material := _gates[index]
		var color := GATE_INACTIVE
		if index < _next_gate:
			color = GATE_PASSED
		elif index == _next_gate:
			color = GATE_ACTIVE
		material.albedo_color = color
		material.emission = color
		material.emission_energy_multiplier = 0.75 if index == _next_gate else 0.18
	hud.show_progress(_next_gate, _gates.size())


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.87
	return material


func _box(parent: Node3D, center: Vector3, size: Vector3, material: Material,
		solid := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	if solid:
		var body := StaticBody3D.new()
		body.position = center
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		body.add_child(instance)
		parent.add_child(body)
	else:
		instance.position = center
		parent.add_child(instance)
	return instance


func _mesa_part(center: Vector3, height: float, bottom: float, top: float,
		heading: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = 6
	mesh.rings = 0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	instance.rotation.y = heading
	instance.scale.z = 0.72
	add_child(instance)
