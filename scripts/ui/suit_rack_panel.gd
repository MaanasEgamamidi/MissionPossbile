class_name SuitRackPanel
extends StationPanel
## The suit rack by the airlock: your suit (on or off) with a button that starts the one-second suit check
## (`begin_suit_check`), your suit tank and the colony's oxygen reserve, and "Fill tank from colony oxygen"
## (`refill_suit`), which says how much oxygen it takes from the reserve. Filling here is the only way to fill a tank.

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
	_add_reading(&"suit", "◆", "Your suit", "suit_tank")
	_add_reading(&"tank", "⛑", "Your suit tank", "suit_tank")
	_add_reading(&"reserve", "O₂", "Colony oxygen reserve", "oxygen")

	_add_heading(_body, "Suit")
	var suit_row := HBoxContainer.new()
	_body.add_child(suit_row)
	suit_button = Button.new()
	suit_button.name = "SuitCheck"
	suit_button.theme_type_variation = UiTheme.PRIMARY_BUTTON
	suit_button.pressed.connect(_on_suit_pressed)
	suit_row.add_child(suit_button)
	_check_label = Label.new()
	_check_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_check_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_check_label.theme_type_variation = UiTheme.MUTED
	suit_row.add_child(_check_label)

	_add_heading_with_help(_body, "Suit tank", "suit_refill")
	fill_button = Button.new()
	fill_button.name = "Fill"
	fill_button.text = "Fill tank from colony oxygen"
	fill_button.pressed.connect(_on_fill_pressed)
	_body.add_child(fill_button)
	_fill_note = _add_text(_body, "")


func _refresh_body(st: ColonyState) -> void:
	var bal := services.balance
	var me := services.local_character()
	var reserve := st.store(&"oxygen_kg")
	_show_reading(&"reserve", "%s kg" % num(reserve, 2), &"urgent" if reserve <= 0.0 else (&"warn" if reserve < bal.oxygen_reserve_warn_kg else &"ok"))
	if me == null:
		_show_reading(&"suit", "No crew member", &"warn")
		_show_reading(&"tank", "—", &"ok")
		suit_button.text = "Put the suit on"
		suit_button.disabled = true
		suit_button.tooltip_text = "Choose a crew member first."
		_check_label.text = "Choose a crew member first."
		fill_button.disabled = true
		fill_button.tooltip_text = "Choose a crew member first."
		_fill_note.text = "Choose a crew member first."
		return
	_show_reading(&"suit", "On" if me.suit_on else "Off", &"ok")
	var tank_kg := LifeSupportModel.suit_kg(bal, me)
	var tank_level: StringName = &"ok"
	if me.suit_charge < 10.0:
		tank_level = &"urgent"
	elif me.suit_charge < bal.suit_warn_charge:
		tank_level = &"warn"
	_show_reading(&"tank", "%s %% · %s kg of oxygen" % [num(me.suit_charge, 0), num(tank_kg, 3)], tank_level)

	var progress := services.session.suit_check_progress(me.id) if services.session != null else -1.0
	suit_button.text = "Take the suit off" if me.suit_on else "Put the suit on"
	suit_button.disabled = progress >= 0.0
	if progress >= 0.0:
		_check_label.text = "Suit check running… %d %%" % roundi(progress * 100.0)
		suit_button.tooltip_text = "A suit check is already running."
	else:
		_check_label.text = "The suit check takes about %s second. Stay at the rack until it is done." % num(services.config.suit_check_seconds)
		suit_button.tooltip_text = "Starts the suit check."

	var need := (100.0 - me.suit_charge) / 100.0 * bal.suit_o2_capacity_kg
	var reason := ""
	if me.suit_charge >= 100.0:
		reason = "Your tank is already full."
	elif reserve <= 0.0:
		reason = "The colony's oxygen reserve is empty."
	fill_button.disabled = reason != ""
	fill_button.tooltip_text = reason if reason != "" else "Moves oxygen from the colony's tanks into your suit."
	var take := minf(need, reserve)
	var how := "Filling takes %s kg of oxygen from the colony reserve, which has %s kg." % [num(take, 3), num(reserve, 2)]
	if reason != "":
		how = reason
	_fill_note.text = how


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
