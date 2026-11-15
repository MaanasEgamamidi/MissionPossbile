class_name SuitRackPanel
extends StationPanel
## The suit rack by the airlock: two big buttons, "Put suit on" / "Take suit off" (starts the one-second suit check,
## `begin_suit_check`) and "Fill tank" (`refill_suit`), then your suit, your tank and the colony's oxygen as bars.
## The help ("?") says how much oxygen a fill takes from the reserve. Filling here is the only way to fill a tank.

## Puts the suit on or takes it off (starts the suit check).
var suit_button: Button
## Fills your tank from the colony's oxygen reserve.
var fill_button: Button

var _fill_note: Label
var _check_label: Label


## The sentence under the fill button ("Filling takes 0.24 kg of oxygen from the colony reserve…").
func fill_note_text() -> String:
	return _fill_note.text if _fill_note != null else ""


func _shows_later_note() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["Put your suit on before you go outside, or take it off.",
		"Fill your suit tank from the colony's oxygen reserve."])


func _build_body() -> void:
	suit_button = _add_action("Put suit on", &"crew", _on_suit_pressed)
	suit_button.name = "SuitCheck"
	fill_button = _add_action("Fill tank", &"tank", _on_fill_pressed, false)
	fill_button.name = "Fill"
	# One short line under the buttons: the running suit check, or why the tank cannot be filled.
	_check_label = _add_text(_body, "", UiTheme.MUTED)
	_check_label.name = "SuitCheckStatus"
	_body.move_child(_check_label, _actions.get_index() + 1)

	_add_reading(&"suit", "◆", "Your suit", "suit_tank")
	_add_reading(&"tank", "⛑", "Your tank", "suit_tank")
	_add_reading(&"reserve", "O₂", "Colony oxygen", "oxygen")

	_fill_note = _add_note(_body, "")
	var help_row := HBoxContainer.new()
	_body.add_child(help_row)
	_help_only(help_row)
	var about := _add_text(help_row, "Fill your tank here before you go outside.", UiTheme.MUTED)
	about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help_row.add_child(ExplainButton.make("suit_refill"))


func _refresh_body(st: ColonyState) -> void:
	var bal := services.balance
	var me := services.local_character()
	var reserve := st.store(&"oxygen_kg")
	_show_reading(&"reserve", "%s kg" % num(reserve, 1), &"urgent" if reserve <= 0.0 else (&"warn" if reserve < bal.oxygen_reserve_warn_kg else &"ok"),
		reserve / maxf(float(st.capacities.get(&"oxygen_kg", 0.0)), 1.0))
	if me == null:
		_show_reading(&"suit", "No crew member", &"warn")
		_show_reading(&"tank", "—", &"ok")
		suit_button.text = "Put suit on"
		suit_button.disabled = true
		suit_button.tooltip_text = "Choose a crew member first."
		_check_label.text = "Choose a crew member first."
		fill_button.disabled = true
		fill_button.tooltip_text = "Choose a crew member first."
		_fill_note.text = "Choose a crew member first."
		_check_label.visible = true
		return
	_show_reading(&"suit", "On" if me.suit_on else "Off", &"ok")
	var tank_kg := LifeSupportModel.suit_kg(bal, me)
	var tank_level: StringName = &"ok"
	if me.suit_charge < 10.0:
		tank_level = &"urgent"
	elif me.suit_charge < bal.suit_warn_charge:
		tank_level = &"warn"
	_show_reading(&"tank", "%s %%" % num(me.suit_charge, 0), tank_level, me.suit_charge / 100.0)
	(readings[&"tank"] as Reading).value_label.tooltip_text = "%s kg of oxygen" % num(tank_kg, 3)

	var progress := services.session.suit_check_progress(me.id) if services.session != null else -1.0
	suit_button.text = "Take suit off" if me.suit_on else "Put suit on"
	suit_button.disabled = progress >= 0.0
	var line := ""
	if progress >= 0.0:
		line = "Suit check… %d %%" % roundi(progress * 100.0)
		suit_button.tooltip_text = "A suit check is already running."
	else:
		suit_button.tooltip_text = "Starts the suit check: about %s second. Stay at the rack until it is done." % num(services.config.suit_check_seconds)

	var need := (100.0 - me.suit_charge) / 100.0 * bal.suit_o2_capacity_kg
	var reason := ""
	if me.suit_charge >= 100.0:
		reason = "Your tank is already full."
	elif reserve <= 0.0:
		reason = "The colony's oxygen reserve is empty."
	fill_button.disabled = reason != ""
	fill_button.tooltip_text = reason if reason != "" else "Moves oxygen from the colony's tanks into your suit."
	# A full tank needs no sentence (the reading shows 100 % and a tick); an empty reserve does.
	if line == "" and reserve <= 0.0 and me.suit_charge < 100.0:
		line = "✖ No oxygen left to fill the tank."
	_check_label.text = line
	_check_label.visible = line != ""
	var take := minf(need, reserve)
	var how := "Filling takes %s kg of oxygen from the colony reserve, which has %s kg." % [num(take, 3), num(reserve, 2)]
	if reason != "":
		how = reason
	_fill_note.text = "%s This is the only way to fill a tank: putting the suit on again does not fill it." % how


func _on_suit_pressed() -> void:
	var me := services.local_character()
	if me == null:
		return
	_ask(&"begin_suit_check", {"on": not me.suit_on}, _on_suit_answer)


func _on_suit_answer(result: ActionResult) -> void:
	if result.ok:
		_show_message("")
		_show_cause("Suit check started. Wait a moment at the rack.")
	else:
		_show_refusal(result)
	refresh()


func _on_fill_pressed() -> void:
	_ask(&"refill_suit", {}, _on_fill_answer)


func _on_fill_answer(result: ActionResult) -> void:
	if result.ok:
		_show_message("")
		_show_cause(answer_text(result))
	else:
		_show_refusal(result)
	refresh()
