extends StationPanel
## A record station (kind "record", data/stations_lore.json): an old console or box where the first crew left a short
## record (Prompt 12, optional story). "Read the record" sends `read_record`; the host finds it once for the colony.
## The text is fiction and says so; the science line names the real fact it touches. It never edits state.

var read_button: Button
var journal_button: Button
var _record_title: Label
var _record_text: Label
var _fiction: Label
var _science: Label


func _shows_later_note() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["Read a record the first crew left here. It is part of an optional story, never a task.",
		"Every record you find goes into the colony journal (J)."])


## The record kept at this station, or {}.
func record() -> Dictionary:
	var list := TutorialSystem.records_at(String(station_id), "read_record")
	return list[0] if not list.is_empty() else {}


func _build_body() -> void:
	_record_title = _add_heading(_body, "")
	_record_text = _add_text(_body, "")
	_fiction = _add_text(_body, "", UiTheme.MUTED)
	_science = _add_text(_body, "", UiTheme.MUTED)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	_body.add_child(row)
	read_button = Button.new()
	read_button.name = "Read"
	read_button.text = "Read the record"
	read_button.theme_type_variation = UiTheme.PRIMARY_BUTTON
	read_button.pressed.connect(_on_read)
	row.add_child(read_button)
	journal_button = Button.new()
	journal_button.name = "Journal"
	journal_button.text = "Open the colony journal"
	journal_button.pressed.connect(func() -> void: open_requested.emit(StoryLogPanel.new()))
	row.add_child(journal_button)


func _refresh_body(st: ColonyState) -> void:
	var r := record()
	if r.is_empty():
		_record_title.text = "Nothing readable is left here."
		_record_text.visible = false
		_fiction.visible = false
		_science.visible = false
		read_button.disabled = true
		return
	var found := TutorialSystem.is_found(st, String(r.id))
	_record_title.text = "✎ " + String(r.get("title", "Record"))
	_record_text.text = String(r.get("text", ""))
	_record_text.visible = found
	_fiction.text = String(TutorialSystem.lore().get("fiction_label", "Fiction."))
	_fiction.visible = found
	var ids: Array = r.get("source_ids", [])
	_science.text = "Science: %s%s" % [String(r.get("science", "")), "" if ids.is_empty() else " Sources: %s." % ", ".join(PackedStringArray(ids))]
	_science.visible = found
	read_button.disabled = false
	read_button.text = "Read it again" if found else "Read the record"


func _on_read() -> void:
	_ask(&"read_record", {}, func(result: ActionResult) -> void:
		if result.ok:
			var news: Array = result.changes.get("discoveries", [])
			_show_message("New record in the colony journal." if bool(result.changes.get("new", false)) else "", UiTheme.GOOD)
			if not news.is_empty():
				_show_cause("Discovery made! Open the colony journal to see how the clues fit together.")
		else:
			_show_refusal(result)
		refresh())
