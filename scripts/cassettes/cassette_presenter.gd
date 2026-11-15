class_name CassettePresenter
extends Node3D
## Six room cassettes and the Command Room tape deck as real models (assets/props/*.glb, built by
## tools/blender/props/build_props.py). Each rests ON a real surface (a desk, crate, bench or table top): the spot is
## "prop_position" / "prop_yaw_deg" of its entry in data/stations_repairs.json, measured in the intact map so the visual
## top and the collision top agree within 2 cm. Nothing floats and no sign hangs in the air (owner 2026-11-14): the HUD
## prompt "[E] ..." says what to do. Presentation follows shared authoritative collection state.
## The station's sensing Area3D stays the only interaction shape: its sphere, plus a small reach box around the prop so
## that aiming at the prop itself works. The props add no solid collision.

const TAPE_SCENE := "res://assets/props/cassette_tape.glb"
const PLAYER_SCENE := "res://assets/props/cassette_player.glb"
## Top of the tape's room colour band, in the tape model (glb) frame: the room name is printed flat on it.
const TAPE_STRIP_TOP := Vector3(0.0, 0.0198, -0.032)
## Reach boxes (designer balance): a little larger than the props, so E aims easily at a small tape.
const TAPE_REACH := Vector3(0.30, 0.14, 0.24)
const PLAYER_REACH := Vector3(0.62, 0.34, 0.42)

var services: GameServices
var cassette_nodes: Dictionary = {}
var _refresh_left := 0.0

func setup(p_services: GameServices, collision: Node3D) -> void:
	services = p_services
	var stations := collision.get_node_or_null("Stations")
	if stations == null:
		return
	var entries := {}
	for entry: Dictionary in StationCatalog.extra_entries():
		if entry.has("id"):
			entries[String(entry.id)] = entry
	for cassette_id: String in CassetteCatalog.TAPES:
		var station := stations.get_node_or_null(NodePath(cassette_id)) as Area3D
		if station == null:
			continue
		var model := _cassette(cassette_id)
		_place(station, model, entries.get(cassette_id, {}), TAPE_REACH, 0.06)
		cassette_nodes[cassette_id] = station
	var player := stations.get_node_or_null(NodePath(CassetteCatalog.PLAYER_ID)) as Area3D
	if player != null:
		_place(player, _player_model(), entries.get(CassetteCatalog.PLAYER_ID, {}), PLAYER_REACH, 0.16)
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

## World position (on its support surface) and yaw of a prop, from its station entry. Without "prop_position" the prop
## sits on the floor under the station.
static func prop_pose(entry: Dictionary, station_position: Vector3) -> Transform3D:
	var at := station_position - Vector3(0, 1.0, 0)
	if entry.has("position"):
		var q: Array = entry.position
		at = Vector3(float(q[0]), float(q[1]), float(q[2]))
	if entry.has("prop_position"):
		var p: Array = entry.prop_position
		at = Vector3(float(p[0]), float(p[1]), float(p[2]))
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(entry.get("prop_yaw_deg", 0.0)))), at)

## Puts the model at its surface spot (stations sit under the identity "Stations" node, so local = world offsets) and
## adds the reach box, `lift` metres high, around it.
static func _place(station: Area3D, model: Node3D, entry: Dictionary, reach: Vector3, lift: float) -> void:
	var pose := prop_pose(entry, station.position)
	model.transform = Transform3D(pose.basis, pose.origin - station.position)
	station.add_child(model)
	var shape := CollisionShape3D.new()
	shape.name = "PropReach"
	var box := BoxShape3D.new()
	box.size = reach
	shape.shape = box
	shape.transform = Transform3D(pose.basis, pose.origin - station.position + Vector3(0, lift, 0))
	station.add_child(shape)

static func _instance(path: String, label: String) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("CassettePresenter: missing model " + path)
		var empty := Node3D.new()
		empty.name = label
		return empty
	var node := scene.instantiate() as Node3D
	node.name = label
	return node

static func _cassette(cassette_id: String) -> Node3D:
	var info: Dictionary = CassetteCatalog.TAPES[cassette_id]
	var model := Node3D.new()
	model.name = "CassetteModel"
	var tape := _instance(TAPE_SCENE, "Tape")
	model.add_child(tape)
	var strip := StandardMaterial3D.new()
	strip.albedo_color = Color(String(info.color))
	strip.roughness = 0.55
	for part: String in ["RoomStrip", "LabelLine"]:
		var mesh := tape.find_child(part, true, false) as MeshInstance3D
		if mesh != null:
			mesh.material_override = strip
	# The room name printed flat on the colour band (not a floating sign): it lies on the tape and reads from +Z.
	var label := Label3D.new()
	label.name = "RoomLabel"
	label.text = "%s  %s" % [info.code, info.title]
	label.position = TAPE_STRIP_TOP + Vector3(0, 0.0004, 0)
	label.rotation.x = -PI * 0.5
	label.font_size = 40
	label.pixel_size = 0.00025
	label.outline_size = 0
	label.modulate = Color("1b1d20")
	label.double_sided = false
	label.no_depth_test = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(label)
	return model

static func _player_model() -> Node3D:
	var model := Node3D.new()
	model.name = "CassettePlayerModel"
	model.add_child(_instance(PLAYER_SCENE, "Deck"))
	return model
