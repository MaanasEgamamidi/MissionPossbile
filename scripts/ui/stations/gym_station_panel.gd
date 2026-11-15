extends StationPanel
## The exercise corner (station kind "gym", data/stations_progression.json). Exercise uses body energy (stamina) now and
## raises fitness (conditioning), so body energy comes back a little faster afterwards. It is never colony electricity:
## the battery does not change. Sends `exercise`; it never edits state.

var exercise_button: Button


func _shows_later_note() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["Exercise: it uses body energy now and makes your crew member fitter.",
		"Fitter crew members get their body energy back a little faster.",
		"Body energy is not electricity: exercise never charges or drains the battery."])


func _build_body() -> void:
	exercise_button = _add_action("Exercise", &"dumbbell", _on_exercise)
	exercise_button.name = "Exercise"
	exercise_button.tooltip_text = "Uses %d %% body energy" % roundi(ProgressionBalance.shared().exercise_stamina_cost)
	_add_reading(&"body_energy", "♥", "Body energy", "stamina")
	_add_reading(&"fitness", "↑", "Fitness", "stamina_vs_electricity")
	# The battery is here only to show that exercise does not change it: part of the help.
	_help_only(_add_reading(&"battery", "▮", "Colony battery (not changed here)", "battery"))


func _refresh_body(st: ColonyState) -> void:
	var me := services.local_character()
	if me == null:
		_show_reading(&"body_energy", "—", &"ok")
		_show_reading(&"fitness", "—", &"ok")
	else:
		var low := me.stamina < ProgressionBalance.shared().exercise_stamina_cost
		_show_reading(&"body_energy", "%d %%" % roundi(me.stamina), &"warn" if low else &"ok", me.stamina / 100.0)
		var fit := ProgressionSystem.conditioning(st, me.id)
		_show_reading(&"fitness", "%d %%" % roundi(fit * 100.0), &"ok", fit)
	var battery := st.store(&"battery_kwh")
	_show_reading(&"battery", "%s kWh" % num(battery, 0), StationPanel.stock_level(battery, float(st.capacities.get(&"battery_kwh", 0.0))))


func _on_exercise() -> void:
	_ask(&"exercise", {}, func(result: ActionResult) -> void:
		if result.ok:
			_show_message("")
			_show_cause(answer_text(result))
		else:
			_show_refusal(result)
		refresh())
