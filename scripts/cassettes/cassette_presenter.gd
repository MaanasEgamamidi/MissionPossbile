class_name CassettePresenter
extends Node3D
## Six original native cassette props. Presentation follows shared authoritative collection state.
## The existing sensing Areas remain the only interaction shape; these props add no solid collision.

var services: GameServices
var cassette_nodes: Dictionary = {}
var _refresh_left := 0.0

func setup(p_services: GameServices, collision: Node3D) -> void:
	services = p_services
	var stations := collision.get_node_or_null("Stations")
	if stations == null:
		return
	for cassette_id: String in CassetteCatalog.TAPES:
		var station := stations.get_node_or_null(NodePath(cassette_id)) as Area3D
		if station == null:
			continue
		_hide_reserved_marker(station)
		var model := _cassette(cassette_id)
		station.add_child(model)
		cassette_nodes[cassette_id] = station
	var player := stations.get_node_or_null(NodePath(CassetteCatalog.PLAYER_ID)) as Area3D
	if player != null:
		_hide_reserved_marker(player)
		player.add_child(_player_model())
	services.events.state_changed.connect(func(_reason: StringName) -> void: refresh())
	services.events.game_loaded.connect(func(_source: String) -> void: refresh())
	refresh()

func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.25
		refresh()

func refresh() -> void:
	if services == null or not services.has_game():
		return
	for cassette_id: String in cassette_nodes:
		var station := cassette_nodes[cassette_id] as Area3D
		var available := not CassetteCatalog.collected(services.state(), cassette_id)
		station.visible = available
		station.collision_layer = Layers.STATION if available else 0
		station.set_meta("cassette_collected", not available)

static func _hide_reserved_marker(station: Area3D) -> void:
	for child_name: String in ["Marker", "LocationLabel"]:
		var old := station.get_node_or_null(NodePath(child_name)) as Node3D
		if old != null:
			old.visible = false

static func _box(parent: Node3D, label: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	instance.material_override = material
	parent.add_child(instance)
	return instance

static func _sign(parent: Node3D, label: String, text: String, at: Vector3, pixels := 32) -> void:
	var sign := Label3D.new()
	sign.name = label
	sign.text = text
	sign.position = at
	sign.font_size = pixels
	sign.pixel_size = 0.0016
	sign.outline_size = 6
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.no_depth_test = false
	parent.add_child(sign)

static func _cassette(cassette_id: String) -> Node3D:
	var info: Dictionary = CassetteCatalog.TAPES[cassette_id]
	var model := Node3D.new()
	model.name = "CassetteModel"
	var color := Color(String(info.color))
	_box(model, "DisplayStand", Vector3(0.18, 0.75, 0.16), Vector3(0, -0.49, 0), Color("1a2935"))
	_box(model, "CassetteShell", Vector3(0.36, 0.23, 0.07), Vector3.ZERO, color)
	_box(model, "TapeWindow", Vector3(0.27, 0.105, 0.012), Vector3(0, 0.018, 0.042), Color("15212c"))
	for side: float in [-1.0, 1.0]:
		var reel := MeshInstance3D.new()
		reel.name = "ReelLeft" if side < 0.0 else "ReelRight"
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.037
		mesh.bottom_radius = 0.037
		mesh.height = 0.014
		reel.mesh = mesh
		reel.rotation.x = PI * 0.5
		reel.position = Vector3(side * 0.075, 0.02, 0.055)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("efece0")
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		reel.material_override = material
		model.add_child(reel)
	_box(model, "LabelStrip", Vector3(0.29, 0.042, 0.014), Vector3(0, -0.075, 0.045), Color("efece0"))
	_sign(model, "RoomLabel", "%s\n%s CASSETTE" % [info.title, info.code], Vector3(0, 0.28, 0), 34)
	_sign(model, "PickupLabel", "E  Collect tape", Vector3(0, -0.24, 0), 24)
	return model

static func _player_model() -> Node3D:
	var model := Node3D.new()
	model.name = "CassettePlayerModel"
	_box(model, "PlayerStand", Vector3(0.32, 0.7, 0.28), Vector3(0, -0.48, 0), Color("1a2935"))
	_box(model, "PlayerShell", Vector3(0.58, 0.25, 0.25), Vector3.ZERO, Color("334956"))
	_box(model, "CassetteDoor", Vector3(0.29, 0.14, 0.02), Vector3(-0.07, 0.02, 0.14), Color("43b8b1"))
	for index in 3:
		_box(model, "Control%d" % index, Vector3(0.04, 0.04, 0.02), Vector3(0.2, 0.07 - index * 0.06, 0.14), Color("f1a35e"))
	_sign(model, "PlayerLabel", "COMMAND ROOM\nCASSETTE PLAYER", Vector3(0, 0.34, 0), 34)
	return model
