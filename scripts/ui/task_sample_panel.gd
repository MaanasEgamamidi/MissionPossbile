class_name TaskSamplePanel
extends TaskPanel
## UI-only demonstration. It grants no repairs or rewards and never writes colony state.
## All pointer controls have the same keyboard-reachable buttons and labeled shapes.

var sample_moves := 0
var _piece_label: Label
var _sample_position := 0
var _sample_rotation := 0
var _controls: GridContainer


func setup(p_services: GameServices) -> void:
	configure_task({}, "Repair panel sample", "Training preview", "Sample only: no colony progress. Tab selects; Enter / Space activates. Move, Rotate and Activate are keyboard alternatives to dragging, rotation and timed clicks.")
	super.setup(p_services)
	name = "TaskSamplePanel"
	_piece_label = _label("LabeledPiece", UiTheme.HEADING)
	play_area.add_child(_piece_label)
	_controls = GridContainer.new()
	_controls.name = "SampleControls"
	_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_area.add_child(_controls)
	for entry: Array in [["MoveLeft", "< Move square left", "move", -1], ["MoveRight", "Move square right >", "move", 1],
		["Rotate", "Rotate square 90 degrees", "rotate", 1], ["Activate", "Activate square (Enter / Space)", "activate", 1]]:
		var button := Button.new()
		button.name = entry[0]
		button.text = entry[1]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if String(entry[2]) == "activate":
			button.theme_type_variation = UiTheme.PRIMARY_BUTTON
		var move := {"move": String(entry[2]), "value": int(entry[3])}
		button.pressed.connect(func() -> void: submit_move(move))
		_controls.add_child(button)
	move_requested.connect(_sample_move)
	reset_requested.connect(_reset_sample)
	_update_piece()


func _process(delta: float) -> void:
	super._process(delta)
	if _controls != null:
		_controls.columns = 2 if play_area.size.x >= 850.0 and UiTheme.text_scale() <= 1.0 else 1


func _sample_move(move: Dictionary) -> void:
	# A deferred demo answer exercises the same pending/result path as a host response.
	_complete_sample_move.call_deferred(move)


func _complete_sample_move(move: Dictionary) -> void:
	if not is_inside_tree():
		return
	match String(move.get("move", "")):
		"move": _sample_position = clampi(_sample_position + int(move.get("value", 0)), -2, 2)
		"rotate": _sample_rotation = (_sample_rotation + 90) % 360
		"activate": sample_moves += 1
		_:
			accept_host_result(ActionResult.failure("sample", &"bad_request", "Try a labeled sample control."))
			return
	_update_piece()
	accept_host_result(ActionResult.success("sample", {}, "Preview accepted; no saved progress."), {"progress": minf(sample_moves / 3.0, 1.0)})


func _reset_sample() -> void:
	sample_moves = 0
	_sample_position = 0
	_sample_rotation = 0
	succeeded = false
	apply_host_state({"progress": 0.0})
	status_label.text = "Sample reset. No colony state changed."
	_update_piece()


func _update_piece() -> void:
	_piece_label.text = "[Square A] Position %d | Rotation %d degrees" % [_sample_position, _sample_rotation]
