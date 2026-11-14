class_name SalvageStationPanel
extends StationPanel
## A damaged object that can give parts (Prompt 08, Part S). Lists the donor's parts with a clue for each. Anyone can
## choose the part that fits ("This one fits", `inspect_donor`); a wrong choice says why, with no penalty. The field
## engineering and geology specialist then takes a fitting part out ("Take it out", `recover_part`) as a salvaged part
## to carry to the workbench. Every donor part can be taken out once, ever.

## "This one fits" buttons by part id.
var fit_buttons: Dictionary = {}
## "Take it out" buttons by part id.
var take_buttons: Dictionary = {}
## "Look it over" (inspect without choosing).
var look_button: Button

var _parts_box: VBoxContainer
var _status: Dictionary = {}
var _reasons: Dictionary = {}
var _sig := ""


## The status words of a part as shown ("✓ Fits the cabin fans", "? Not checked yet"...).
func part_status_text(part_id: String) -> String:
	var l := _status.get(part_id) as Label
	return l.text if l != null else ""


## Why "Take it out" is disabled for a part ("" when it can be pressed).
func take_reason_text(part_id: String) -> String:
	var l := _reasons.get(part_id) as Label
	var b := take_buttons.get(part_id) as Button
	return l.text if l != null and b != null and b.disabled else ""


func _donor() -> Dictionary:
	return ScienceActions.donor_info(String(station_id))


func _title_text() -> String:
	var name := String(_donor().get("name", ""))
	return "Salvage: %s" % name if name != "" else "Salvage donor"


func _shows_room_power() -> bool:
	return station_zone() != ColonyZones.EXTERIOR


func _shows_later_note() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["Look over the parts of this damaged object and read the clue for each.",
		"Choose the part that fits the colony's own machines (anyone).",
		"Take a fitting part out to refurbish at the workbench (field engineering and geology specialist ⛏)."])


func _build_body() -> void:
	_add_reading(&"taken", "♻", "Parts taken out of this donor", "parts")
	_add_reading(&"pack", "▤", "Your pack", "cargo")
	_add_text(_body, String(_donor().get("story", "")))
	var look_row := HBoxContainer.new()
	_body.add_child(look_row)
	look_button = Button.new()
	look_button.name = "Look"
	look_button.text = "Look it over"
	look_button.pressed.connect(_on_look)
	look_row.add_child(look_button)
	look_row.add_child(ExplainButton.make("upgrades", "With the salvage inspection upgrade, looking it over marks every part that fits."))
	_add_heading_with_help(_body, "Parts", "parts")
	_parts_box = VBoxContainer.new()
	_parts_box.name = "Parts"
	_body.add_child(_parts_box)
	_station_help.extra_text += "\n\nWhich parts fit is made up for the game. Taking a part out uses nothing from colony stores."


func _refresh_body(st: ColonyState) -> void:
	var donor_id := String(station_id)
	var limit := ScienceActions.donor_limit(st)
	var taken := ScienceActions.recovered_count(st, donor_id)
	_show_reading(&"taken", "%d of %d" % [taken, limit], &"warn" if taken >= limit else &"ok")
	var me := services.local_character()
	var slots := services.balance.cargo_slots
	var used := me.cargo.size() if me != null else 0
	_show_reading(&"pack", "%d of %d slots used" % [used, slots], &"warn" if used >= slots else &"ok")
	look_button.disabled = me == null
	var rec: Dictionary = ScienceActions.read(st, "donors").get(donor_id, {})
	var sig := JSON.stringify(rec) + str(st.has_upgrade("res_salvage_inspection")) + str(limit)
	if sig != _sig:
		_sig = sig
		_build_parts(st)
	for p: Dictionary in _donor().get("parts", []):
		var pid := String(p.id)
		var reason := ""
		if me == null:
			reason = "Choose a crew member first."
		elif ScienceActions.is_recovered(st, donor_id, pid):
			reason = "Already taken out."
		elif not ScienceActions.is_identified(st, donor_id, pid):
			reason = "Choose the part that fits first."
		elif me.specialty != ScienceActions.FIELD_SPECIALTY:
			reason = "Only the field engineering and geology specialist ⛏ can take parts out."
		elif taken >= limit:
			reason = "Nothing more can be saved from this donor."
		elif used >= slots:
			reason = "Your pack is full."
		var b := take_buttons.get(pid) as Button
		if b != null:
			b.disabled = reason != ""
			b.tooltip_text = reason if reason != "" else "Take the part out and carry it."
		var l := _reasons.get(pid) as Label
		if l != null:
			l.text = reason if reason != "" else "You can take it out."
		var f := fit_buttons.get(pid) as Button
		if f != null:
			f.disabled = me == null


func _build_parts(st: ColonyState) -> void:
	for child in _parts_box.get_children():
		_parts_box.remove_child(child)
		child.queue_free()
	fit_buttons.clear()
	take_buttons.clear()
	_status.clear()
	_reasons.clear()
	var donor_id := String(station_id)
	var rec: Dictionary = ScienceActions.read(st, "donors").get(donor_id, {})
	var rejected: Dictionary = rec.get("rejected", {})
	for p: Dictionary in _donor().get("parts", []):
		var pid := String(p.id)
		var card := PanelContainer.new()
		card.name = "Part_%s" % pid
		card.theme_type_variation = UiTheme.CARD
		_parts_box.add_child(card)
		var col := VBoxContainer.new()
		card.add_child(col)
		_add_text(col, String(p.get("name", pid)), UiTheme.HEADING)
		_add_text(col, "Clue: %s" % String(p.get("clue", "")))
		var status := _add_text(col, "")
		_status[pid] = status
		if ScienceActions.is_recovered(st, donor_id, pid):
			status.text = "✓ Taken out already"
			status.theme_type_variation = UiTheme.MUTED
		elif ScienceActions.is_identified(st, donor_id, pid):
			status.text = "✓ Fits %s" % String(p.get("fits", "the colony"))
			status.theme_type_variation = UiTheme.GOOD
		elif bool(rejected.get(pid, false)):
			status.text = "✖ Does not fit"
			status.theme_type_variation = UiTheme.URGENT
		else:
			status.text = "? Not checked yet: read the clue"
			status.theme_type_variation = UiTheme.MUTED
		var row := HFlowContainer.new()
		col.add_child(row)
		if not ScienceActions.is_identified(st, donor_id, pid) and not bool(rejected.get(pid, false)):
			var fit := Button.new()
			fit.name = "Fits_%s" % pid
			fit.text = "This one fits"
			fit.pressed.connect(_on_fit.bind(pid))
			row.add_child(fit)
			fit_buttons[pid] = fit
		if ScienceActions.is_identified(st, donor_id, pid) and not ScienceActions.is_recovered(st, donor_id, pid):
			var take := Button.new()
			take.name = "Take_%s" % pid
			take.text = "Take it out"
			take.theme_type_variation = UiTheme.PRIMARY_BUTTON
			take.pressed.connect(_on_take.bind(pid))
			row.add_child(take)
			take_buttons[pid] = take
			var reason := _add_text(col, "", UiTheme.MUTED)
			_reasons[pid] = reason


func _on_look() -> void:
	_ask(&"inspect_donor", {}, _on_answer)


func _on_fit(part_id: String) -> void:
	_ask(&"inspect_donor", {"choice": part_id}, _on_answer)


func _on_take(part_id: String) -> void:
	_ask(&"recover_part", {"part": part_id}, _on_answer)


func _on_answer(result: ActionResult) -> void:
	if result.ok:
		_show_message("")
		_show_cause(answer_text(result))
	else:
		_show_refusal(result)
	refresh()
