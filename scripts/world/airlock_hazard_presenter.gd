class_name AirlockHazardPresenter
extends Node3D
## Connect actual door travel to host pressure facts; never subtracts global cabin gas.

var services: GameServices
var pressure_label: Label3D
var _elapsed := 0.0

func setup(p_services: GameServices, doors: Array[DoorController], show_sign := true) -> void:
	services = p_services
	for door: DoorController in doors:
		if door.door_id not in [901, 902]:
			continue
		if services.is_authority():
			services.session.survival.set_airlock_door_open(door.door_id, door.open_amount > 0.0)
		door.opening_started.connect(func(id: int) -> void: _door_state(id, true))
		door.closed_fully.connect(func(id: int) -> void: _door_state(id, false))
	if show_sign:
		pressure_label = Label3D.new()
		pressure_label.name = "AirlockPressureSign"
		pressure_label.position = Vector3(22.0, 2.55, 10.05)
		pressure_label.font_size = 38
		pressure_label.pixel_size = 0.006
		pressure_label.outline_size = 10
		pressure_label.no_depth_test = false
		add_child(pressure_label)
	_refresh()

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
