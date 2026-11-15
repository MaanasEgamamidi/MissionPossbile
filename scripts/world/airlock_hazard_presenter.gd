class_name AirlockHazardPresenter
extends Node3D
## Connect actual door travel to host pressure facts; never subtracts global cabin gas.

var services: GameServices
var pressure_label: Label3D
var _elapsed := 0.0

func setup(p_services: GameServices, doors: Array[DoorController], show_sign := true) -> void:
	services = p_services
	for door: DoorController in doors:
		# 901/902: base airlock inner/outer; 912: garden dome airlock outer door (its vestibule loses air when open).
		if door.door_id not in [901, 902, 912]:
			continue
		if services.is_authority():
			services.session.survival.set_airlock_door_open(door.door_id, door.open_amount > 0.0)
		door.opening_started.connect(func(id: int) -> void: _door_state(id, true))
		door.closed_fully.connect(func(id: int) -> void: _door_state(id, false))
	if show_sign:
		_build_wall_sign()
	_refresh()

## Hangar south wall face beside the exit tunnel's inner door (map wall ak_ws_5, flat from x 23.8 to 25.85 m, measured
## in the intact map with tools/blender/props/probe_surfaces.py). The sign hangs flat on it, facing the hangar.
const SIGN_WALL_Z := 9.828
const SIGN_CENTRE := Vector3(24.85, 1.75, SIGN_WALL_Z)
const SIGN_SIZE := Vector2(1.5, 0.72)

## A sign mounted flat on the wall (owner 2026-11-14: no text floating in the air): a dark board with an orange rim,
## the live pressure text printed on its face.
func _build_wall_sign() -> void:
	var board := MeshInstance3D.new()
	board.name = "AirlockPressureSignBoard"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(SIGN_SIZE.x, SIGN_SIZE.y, 0.03)
	board.mesh = mesh
	board.position = SIGN_CENTRE - Vector3(0, 0, 0.015)
	var face := StandardMaterial3D.new()
	face.albedo_color = Color("1b232b")
	face.roughness = 0.6
	board.material_override = face
	add_child(board)
	var rim := MeshInstance3D.new()
	rim.name = "AirlockPressureSignRim"
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(SIGN_SIZE.x + 0.06, SIGN_SIZE.y + 0.06, 0.02)
	rim.mesh = rim_mesh
	rim.position = SIGN_CENTRE - Vector3(0, 0, 0.01)
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color("e8743a")
	orange.roughness = 0.5
	rim.material_override = orange
	add_child(rim)
	pressure_label = Label3D.new()
	pressure_label.name = "AirlockPressureSign"
	pressure_label.position = SIGN_CENTRE - Vector3(0, 0, 0.032)
	pressure_label.rotation.y = PI          # Label3D reads from +Z; this one faces the hangar (-Z)
	pressure_label.font_size = 64
	pressure_label.pixel_size = 0.0015
	pressure_label.outline_size = 8
	pressure_label.outline_modulate = Color(0.03, 0.04, 0.05)
	pressure_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pressure_label.width = (SIGN_SIZE.x - 0.14) / pressure_label.pixel_size
	pressure_label.double_sided = false
	pressure_label.no_depth_test = false
	add_child(pressure_label)

func _door_state(id: int, opened: bool) -> void:
	if services != null and services.is_authority() and services.has_game():
		services.session.survival.set_airlock_door_open(id, opened)
		_refresh()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.1:
		_elapsed = 0.0
		_refresh()

func _refresh() -> void:
	if pressure_label == null or services == null or not services.has_game():
		return
	var info: Dictionary = services.session.survival.pressure_info()
	var safe := bool(info.get("breathable", true))
	pressure_label.text = "EXIT VESTIBULE · %.0f kPa\n%s\n%s" % [float(info.get("pressure_kpa", 0.0)), String(info.get("status", "")), "Breathable · suit recommended beyond outer door" if safe else "SUIT REQUIRED · safe retreat through inner door"]
	pressure_label.modulate = Color("b9f4e1") if safe else Color("ffb047")
