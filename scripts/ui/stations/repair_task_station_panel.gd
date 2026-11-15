class_name MaintenanceStationPanel
extends StationPanel
## S03 operational upkeep. Puzzle completion remains the separate T-section contract.

var _task_id := ""
var _condition: Label
var _condition_row: StationPanel.Reading
var _job: Label
var _progress: ProgressBar
var _start: Button
var _cancel: Button
var _requested := false

func _build_body() -> void:
	interrupt_on_critical = true
	var record: Dictionary = services.state().stations.get(String(station_id), {})
	_task_id = String(record.get("task_id", ""))
	# The header says what this is in plain words ("Comms tune-up"), not the station's internal name ("T01 - Comms");
	# panel_title() keeps that name.
	var plain := String(record.get("name", ""))
	if plain.contains(" - "):
		_title.text = "%s tune-up" % plain.get_slice(" - ", 1)
	_start = _add_action("Tune up", &"wrench", func() -> void: _send(&"maintenance_start"))
	_start.name = "BeginMaintenance"
	_start.tooltip_text = "Takes %.0f seconds. Stay here until it is done." % services.balance.maintenance_repair_seconds
	_cancel = _add_action("Stop", &"close", func() -> void: _send(&"maintenance_cancel"), false)
	_cancel.name = "CancelMaintenance"
	_condition_row = _add_reading(&"condition", "⚙", "Condition", "parts")
	_condition = _condition_row.value_label
	_progress = ProgressBar.new()
	_progress.name = "MaintenanceProgress"
	_progress.max_value = 100.0
	_progress.show_percentage = true
	_body.add_child(_progress)
	_job = _add_text(_body, "", UiTheme.MUTED)
	# UI overhaul: short, and nothing written for developers ("previews until the T section", "the host completes").
	_add_note(_body, "Stay here until it is done. Walking away stops it.")

func _what_you_can_do() -> PackedStringArray:
	var record: Dictionary = services.state().stations.get(String(station_id), {})
	var role := String(record.get("specialty", ""))
	return PackedStringArray(["Keep this equipment in good shape (%s)." % String(StationPanels.SPECIALTY_WORDS.get(StringName(role), "all crew members")).to_lower(),
		"A tune-up takes a little while. The colony keeps running while you work."])

func _shows_later_note() -> bool:
	return false

func _refresh_body(st: ColonyState) -> void:
	var task: Dictionary = st.repair.get("tasks", {}).get(_task_id, {})
	var condition := float(task.get("condition", 1.0))
	var fault := bool(task.get("maintenance_fault", false))
	var worn := condition <= services.balance.maintenance_warning_condition
	_show_reading(&"condition", "%s · %.0f %%" % ["Needs a tune-up" if fault else ("Worn" if worn else "Good"), condition * 100.0],
		&"urgent" if fault else (&"warn" if worn else &"ok"), condition)
	var job: Dictionary = services.session.wear_runtime.status(_task_id)
	var actor := services.local_character()
	var active := bool(job.get("active", false))
	var mine := active and actor != null and String(job.get("actor", "")) == String(actor.id)
	_progress.value = float(job.get("progress", 0.0)) * 100.0
	_job.text = "Working… %.0f of %.0f seconds" % [float(job.get("elapsed_seconds", 0.0)), float(job.get("duration_seconds", 20.0))] if active else ""
	_progress.visible = active
	var role := String(task.get("required_specialty", "general"))
	_start.disabled = active or actor == null or (condition >= 1.0 and not fault) or (actor != null and role != "general" and String(actor.specialty) != role)
	_cancel.disabled = not mine
	_cancel.visible = mine
	if active and not mine:
		_job.text = "Another crew member is working on it."
	_job.visible = _job.text != ""

func _send(action: StringName) -> void:
	var task: Dictionary = services.state().repair.get("tasks", {}).get(_task_id, {})
	if action == &"maintenance_start":
		_requested = true
	_ask(action, {"generation": int(task.get("fault_generation", 1))}, func(result: ActionResult) -> void:
		if not result.ok or action == &"maintenance_cancel":
			_requested = false
		if result.ok:
			_show_message(result.message if not result.message.is_empty() else "✓ Tune-up started.", UiTheme.GOOD)
		else:
			_show_refusal(result)
		refresh())

func _exit_tree() -> void:
	if services == null or not services.has_game():
		return
	var job: Dictionary = services.session.wear_runtime.status(_task_id)
	var actor := services.local_character()
	# Cancel an in-flight LAN start too: ordered host requests then release it even if
	# the start acknowledgement arrived after this panel was interrupted.
	if _requested or (actor != null and bool(job.get("active", false)) and String(job.get("actor", "")) == String(actor.id)):
		var task: Dictionary = services.state().repair.get("tasks", {}).get(_task_id, {})
		services.request(&"maintenance_cancel", station_id, {"generation": int(task.get("fault_generation", 1))})
