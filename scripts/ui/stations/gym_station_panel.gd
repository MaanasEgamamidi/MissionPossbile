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
	_add_reading(&"body_energy", "♥", "Your body energy (stamina)", "stamina")
	_add_reading(&"fitness", "↑", "Your fitness (conditioning)", "stamina_vs_electricity")
	_add_reading(&"battery", "⚡", "Colony battery (electricity, not changed here)", "battery")
	var row := HBoxContainer.new()
	_body.add_child(row)
	exercise_button = Button.new()
	exercise_button.name = "Exercise"
	exercise_button.text = "Exercise (uses %d %% body energy)" % roundi(ProgressionBalance.shared().exercise_stamina_cost)
	exercise_button.theme_type_variation = UiTheme.PRIMARY_BUTTON
	exercise_button.pressed.connect(_on_exercise)
	row.add_child(exercise_button)


func _refresh_body(st: ColonyState) -> void:
	var me := services.local_character()
	if me == null:
		_show_reading(&"body_energy", "—", &"ok")
		_show_reading(&"fitness", "—", &"ok")
	else:
		var low := me.stamina < ProgressionBalance.shared().exercise_stamina_cost
		_show_reading(&"body_energy", "%d %%" % roundi(me.stamina), &"warn" if low else &"ok")
		_show_reading(&"fitness", "%d %%" % roundi(ProgressionSystem.conditioning(st, me.id) * 100.0), &"ok")
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
