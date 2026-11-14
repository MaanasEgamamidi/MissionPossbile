class_name ScoutBayStationPanel
extends StationPanel
## The scout bay outside the airlock (scout update). While the scout rover is half built, the field engineering and
## geology specialist finishes it here ("Finish the scout", scout_assemble). Then anyone sends it to a place it has
## not seen ("Send", scout_send), watches its mast camera live, or calls it back (scout_recall). Every report it
## radioed home is listed with the picture its camera took there. The colony computer can send it too.

## "Send" buttons by site id.
var send_buttons: Dictionary = {}
var assemble_button: Button
var recall_button: Button

var _status: Label
var _feed: TextureRect
var _feed_note: Label
var _sites: VBoxContainer
var _reports: VBoxContainer
var _rover_note: Label
var _sig := ""


func _shows_later_note() -> bool:
	return false


func _shows_room_power() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["Finish the half-built scout rover (field engineering and geology specialist, %d spare parts)." % ScoutSystem.ASSEMBLE_PARTS,
		"Send the scout to look at a place before anyone walks or drives there: it radios home what it finds.",
		"Ore it spots is marked on the map. Walk out and collect it yourself."])


func _build_body() -> void:
	_add_reading(&"parts", "⚙", "Spare parts", "parts")
	_add_reading(&"trips", "◉", "Places surveyed", "sources")
	_status = _add_text(_body, "", UiTheme.HEADING)
	_status.name = "ScoutStatus"
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	_body.add_child(row)
	assemble_button = Button.new()
	assemble_button.name = "Assemble"
	assemble_button.text = "⛏ Finish the scout (%d parts)" % ScoutSystem.ASSEMBLE_PARTS
	assemble_button.theme_type_variation = UiTheme.PRIMARY_BUTTON
	assemble_button.pressed.connect(func() -> void: _ask(&"scout_assemble", {}, _on_answer))
	row.add_child(assemble_button)
	recall_button = Button.new()
	recall_button.name = "Recall"
	recall_button.text = "Call it back"
	recall_button.pressed.connect(func() -> void: _ask(&"scout_recall", {}, _on_answer))
	row.add_child(recall_button)
	_add_heading(_body, "Mast camera")
	_feed = TextureRect.new()
	_feed.name = "MastCamera"
	_feed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_feed.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_feed.custom_minimum_size = Vector2(480, 270)
	_body.add_child(_feed)
	_feed_note = _add_text(_body, "", UiTheme.MUTED)
	_add_heading(_body, "Where to send it")
	_sites = VBoxContainer.new()
	_sites.name = "Sites"
	_body.add_child(_sites)
	_add_heading(_body, "Reports")
	_reports = VBoxContainer.new()
	_reports.name = "Reports"
	_body.add_child(_reports)
	_rover_note = _add_text(_body, "", UiTheme.MUTED)


func _refresh_body(st: ColonyState) -> void:
	var s := st.scout
	var built := ScoutSystem.is_built(st)
	_show_reading(&"parts", "%d parts" % st.parts, &"ok" if st.parts >= ScoutSystem.ASSEMBLE_PARTS or built else &"warn")
	_show_reading(&"trips", "%d of %d" % [(s.get("surveyed", {}) as Dictionary).size(), ScoutSystem.sites().size()], &"ok")
	_status.text = ("● " if built else "◌ ") + ScoutSystem.status_text(st)
	assemble_button.visible = not built and kind == "scout_bay"
	var me := services.local_character()
	assemble_button.disabled = me == null or me.specialty != ScoutActions.FIELD_SPECIALTY or st.parts < ScoutSystem.ASSEMBLE_PARTS
	assemble_button.tooltip_text = "Only the ⛏ field engineering and geology specialist can finish it." if me == null or me.specialty != ScoutActions.FIELD_SPECIALTY else (
		"Needs %d spare parts." % ScoutSystem.ASSEMBLE_PARTS if st.parts < ScoutSystem.ASSEMBLE_PARTS else "Fit the wheels, the mast camera and the power unit.")
	recall_button.visible = built
	recall_button.disabled = not ScoutSystem.is_out(st) or ScoutSystem.status(st) == "returning"
	var presenter := ScoutPresenter.find(get_tree()) if is_inside_tree() else null
	var tex: Texture2D = null
	if presenter != null:
		if ScoutSystem.is_out(st):
			presenter.want_live(true)
			tex = presenter.mast_texture()
		else:
			tex = presenter.snapshot(String((s.get("last_report", {}) as Dictionary).get("site", "")))
	_feed.texture = tex
	_feed.visible = built
	_feed_note.text = "Live from the scout's mast camera." if ScoutSystem.is_out(st) else ("The last picture it took." if tex != null else "The camera shows a picture while the scout is out.")
	_feed_note.visible = built
	var sig := "%s|%s|%s" % [built, ScoutSystem.status(st), JSON.stringify(s.get("surveyed", {}))]
	if sig != _sig:
		_sig = sig
		_build_lists(st)
	_rover_note.text = "Crew rover trips: science score %d of %d (study ores at the workbench) and Resources level %d of 1." % [
		ScoutSystem.science_points(st), ScoutSystem.CREW_ROVER_SCIENCE, ProgressionSystem.tier(st, "resources")]


func _build_lists(st: ColonyState) -> void:
	for box: VBoxContainer in [_sites, _reports]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	send_buttons.clear()
	var built := ScoutSystem.is_built(st)
	var busy := ScoutSystem.status(st) in ["driving", "surveying"]
	for site: Dictionary in ScoutSystem.sites():
		var id := String(site.id)
		var row := HBoxContainer.new()
		row.name = id
		row.add_theme_constant_override(&"separation", 10)
		_sites.add_child(row)
		var done := ScoutSystem.is_surveyed(st, id)
		var l := _add_text(row, "%s %s · %s · about %s away" % ["✓" if done else "?", String(site.name), String(site.terrain),
			ScoutSystem._hours_words(ScoutSystem.hours_to(st, id))])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := Button.new()
		b.name = "Send_%s" % id
		b.text = "Send again" if done else "Send"
		b.disabled = not built or busy
		b.tooltip_text = "Finish the scout first." if not built else ("The scout is on a trip." if busy else "Send the scout to the %s." % String(site.name).to_lower())
		b.pressed.connect(func() -> void: _ask(&"scout_send", {"site": id}, _on_answer))
		row.add_child(b)
		send_buttons[id] = b
	var surveyed: Dictionary = st.scout.get("surveyed", {})
	if surveyed.is_empty():
		_add_text(_reports, "No reports yet.", UiTheme.MUTED)
		return
	var presenter := ScoutPresenter.find(get_tree()) if is_inside_tree() else null
	for site2: Dictionary in ScoutSystem.sites():
		var id2 := String(site2.id)
		if not surveyed.has(id2):
			continue
		var card := PanelContainer.new()
		card.theme_type_variation = UiTheme.CARD
		_reports.add_child(card)
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 12)
		card.add_child(h)
		var pic := presenter.snapshot(id2) if presenter != null else null
		if pic != null:
			var t := TextureRect.new()
			t.texture = pic
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			t.custom_minimum_size = Vector2(192, 108)
			h.add_child(t)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(col)
		_add_text(col, "%s · sol %d" % [String(site2.name), int((surveyed[id2] as Dictionary).get("sol", 1))], UiTheme.HEADING)
		_add_text(col, String(site2.report))
		if String(site2.get("hazard", "")) != "":
			_add_text(col, "⚠ " + String(site2.hazard), UiTheme.WARN)
		_add_text(col, "Crew rover: " + String(site2.get("rover_note", "")), UiTheme.MUTED)


func _on_answer(result: ActionResult) -> void:
	if result.ok:
		_show_message("")
		_show_cause(answer_text(result))
	else:
		_show_refusal(result)
	_sig = ""
	refresh()


func _exit_tree() -> void:
	var presenter := ScoutPresenter.find(get_tree()) if is_inside_tree() else null
	if presenter != null:
		presenter.want_live(false)
