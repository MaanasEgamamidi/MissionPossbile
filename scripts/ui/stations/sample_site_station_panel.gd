class_name SampleSiteStationPanel
extends StationPanel
## A field sample site outside the base (Prompt 08, Part S). Shows the ground here, how many samples the site can
## still give, the sky and the time that would go on the sample label, and "Take a sample" (`take_sample`). Only the
## field engineering and geology specialist can take one; for anyone else the button says why in words.

## "Take a sample".
var take_button: Button

var _take_reason: Label
var _label_box: VBoxContainer
var _label_lines: Label
var _ground: Label


## Why the take button is disabled, in words ("" when it can be pressed).
func take_reason_text() -> String:
	return _take_reason.text if _take_reason != null and take_button != null and take_button.disabled else ""


## The label of the last sample taken here, as shown ("" if none yet).
func label_text() -> String:
	return _label_lines.text if _label_lines != null and _label_box.visible else ""


func _site() -> Dictionary:
	return ScienceActions.site_info(String(station_id))


func _title_text() -> String:
	var name := String(_site().get("name", ""))
	return "Sample site: %s" % name if name != "" else "Sample site"


func _shows_room_power() -> bool:
	return false


func _shows_later_note() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["Take a sample of the ground here (field engineering and geology specialist ⛏).",
		"The sample label records the site, the time and the sky, so others know where it came from.",
		"Carry the sample to the lab glovebox in the Med Bay and compare it there."])


func _build_body() -> void:
	_ground = _add_text(_body, "")
	_ground.name = "Ground"
	_add_reading(&"taken", "#", "Samples taken here", "cargo")
	_add_reading(&"sky", "◌", "Dust in the air", "panel_dust")
	_add_reading(&"time", "⧗", "Time for the label", "sol_clock")
	_add_reading(&"pack", "♻", "Your pack", "cargo")

	take_button = _add_action("Take sample", &"pick", _on_take)
	take_button.name = "TakeSample"
	# Why the button is greyed out, right under it.
	var row := HBoxContainer.new()
	_body.add_child(row)
	_body.move_child(row, _actions.get_index() + 1)
	_take_reason = Label.new()
	_take_reason.name = "TakeReason"
	_take_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_take_reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_take_reason.theme_type_variation = UiTheme.MUTED
	row.add_child(_take_reason)
	row.add_child(_help_only(ExplainButton.make("specialists")))

	_label_box = VBoxContainer.new()
	_label_box.name = "LastLabel"
	_body.add_child(_label_box)
	_add_heading_with_help(_label_box, "Label of the last sample from here", "sources")
	var card := PanelContainer.new()
	card.theme_type_variation = UiTheme.CARD
	_label_box.add_child(card)
	_label_lines = Label.new()
	_label_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(_label_lines)
	_add_note(_body, "Which rock lies at which site is made up for the game. The lab compares it with a real kind of reference.")


func _refresh_body(st: ColonyState) -> void:
	var site := _site()
	var limit := ScienceBalance.get_current().samples_per_site
	var taken := int(ScienceActions.read(st, "site_counts").get(String(station_id), 0))
	_ground.text = "Ground here: %s" % String(site.get("ground", "Mars ground"))
	_show_reading(&"taken", "%d of %d" % [taken, limit], &"warn" if taken >= limit else &"ok")
	_show_reading(&"sky", "%s · %s" % [num(st.dust_tau, 2), ScienceActions.sky_text(st.dust_tau)], &"ok")
	var clock := services.clock()
	_show_reading(&"time", ScienceActions.time_text(clock.sol_index, clock.phase), &"ok")
	var me := services.local_character()
	var slots := services.balance.cargo_slots
	var used := me.cargo.size() if me != null else 0
	_show_reading(&"pack", "%d of %d slots used" % [used, slots], &"warn" if used >= slots else &"ok")

	var reason := ""
	if me == null:
		reason = "Choose a crew member first."
	elif me.specialty != ScienceActions.FIELD_SPECIALTY:
		reason = "Only the field engineering and geology specialist ⛏ can take a sample. Change crew member in the Med Bay."
	elif taken >= limit:
		reason = "This site has given all the samples it can. Try another site."
	elif used >= slots:
		reason = "Your pack is full. Put something down first."
	take_button.disabled = reason != ""
	take_button.tooltip_text = reason if reason != "" else "Take a sample of the ground here."
	_take_reason.text = reason if reason != "" else "You can take a sample: you are the field engineering and geology specialist."

	var last := {}
	var samples := ScienceActions.read(st, "samples")
	for id: String in samples:
		var s: Dictionary = samples[id]
		if String(s.get("site", "")) == String(station_id) and float(s.get("at_hours", -1.0)) >= float(last.get("at_hours", -1.0)):
			last = s.duplicate(true)
			last["id"] = id
	_label_box.visible = not last.is_empty()
	if not last.is_empty():
		var cond: Dictionary = last.get("conditions", {})
		_label_lines.text = "\n".join(PackedStringArray([
			"Sample: %s" % String(last.id),
			"Site: %s" % String(last.get("site_name", "")),
			"Time: %s" % String(last.get("time_text", "")),
			"Conditions: %s, %s, dust in the air %s" % ["daylight" if bool(cond.get("daylight", true)) else "night", String(cond.get("sky", "")), num(float(cond.get("dust_tau", 0.0)), 2)],
			"Taken by: %s" % _crew_name(st, String(last.get("taken_by", ""))),
		]))


static func _crew_name(st: ColonyState, id: String) -> String:
	var c := st.character(StringName(id))
	return c.display_name if c != null else id


func _on_take() -> void:
	_ask(&"take_sample", {}, _on_answer)


func _on_answer(result: ActionResult) -> void:
	if result.ok:
		_show_message("")
		_show_cause(answer_text(result))
	else:
		_show_refusal(result)
	refresh()
