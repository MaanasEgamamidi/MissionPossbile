class_name CassettePlayerPanel
extends UiPanel
## Content stays blank until the current host authorizes this actor at the physical player.
## Every tape/page change is independently authorized. Local validation closes stale readers immediately.

var station_id: StringName = CassetteLibrary.PLAYER_ID
var selected_cassette := ""
var page_index := 0
var pending := false
var photo: TextureRect
var briefing_text: Label
var caption: Label
var credit: Label
var page_label: Label
var close_button: Button
var _title: Label
var _status: Label
var _tapes: MenuButton
var _previous: Button
var _next: Button
var _source: LinkButton
var _photo_hint: Label
var _record := {}
var _pending_id := ""
var _pending_action: StringName = &""
var _pending_tape := ""
var _pending_page := 0
var _pending_seconds := 0.0
var _actor_id: StringName = &""
var _authorized := false
var _closing := false
var _built := false
var _opened := false
var _library_signature := ""


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	if _built:
		return
	_built = true
	name = "CassettePlayerPanel"
	theme_type_variation = UiTheme.PANEL
	viewport_fraction = Vector2(0.82, 0.76)
	interrupt_on_critical = true
	var frame := VBoxContainer.new()
	frame.name = "Frame"
	add_child(frame)
	_tapes = MenuButton.new()
	_tapes.name = "TapeLibrary"
	_tapes.text = "Choose a collected tape"
	_tapes.focus_mode = Control.FOCUS_ALL
	_tapes.flat = false
	_tapes.theme_type_variation = UiTheme.PRIMARY_BUTTON
	_tapes.get_popup().id_pressed.connect(_on_tape_selected)
	frame.add_child(_tapes)
	var columns := HBoxContainer.new()
	columns.name = "PhotoAndBriefing"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(columns)
	var left := _scroll_column(columns, "PhotoColumn")
	_photo_hint = _label("PhotoHint", "Choose a collected tape at this player.")
	left.add_child(_photo_hint)
	photo = TextureRect.new()
	photo.name = "NASAImage"
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	photo.custom_minimum_size.y = 170.0
	photo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(photo)
	caption = _label("Caption", "")
	left.add_child(caption)
	credit = _label("Credit", "")
	credit.theme_type_variation = UiTheme.MUTED
	left.add_child(credit)
	_source = LinkButton.new()
	_source.name = "NASASource"
	_source.text = "NASA source"
	_source.pressed.connect(_open_source)
	left.add_child(_source)
	var right := _scroll_column(columns, "BriefingColumn")
	_title = _label("RoomTitle", "Command Room cassette player")
	_title.theme_type_variation = UiTheme.HEADING
	right.add_child(_title)
	briefing_text = _label("Instructions", "")
	right.add_child(briefing_text)
	page_label = _label("Page", "")
	page_label.theme_type_variation = UiTheme.MUTED
	right.add_child(page_label)
	_previous = Button.new()
	_previous.name = "PreviousPage"
	_previous.text = "Previous"
	_previous.pressed.connect(func() -> void: read_page(page_index - 1))
	right.add_child(_previous)
	_next = Button.new()
	_next.name = "NextPage"
	_next.text = "Next"
	_next.pressed.connect(func() -> void: read_page(page_index + 1))
	right.add_child(_next)
	_status = _label("AuthorizationStatus", "Waiting for the player...")
	right.add_child(_status)
	close_button = Button.new()
	close_button.name = "Close"
	close_button.text = "Close (Esc)"
	close_button.pressed.connect(func() -> void: close_requested.emit())
	frame.add_child(close_button)
	_clear_content()
	if services != null:
		var actor := services.local_character()
		_actor_id = actor.id if actor != null else &""
		services.events.action_resolved.connect(_on_action_resolved)
		services.events.character_recovered.connect(_on_recovered)
		services.net.host_lost.connect(_on_host_lost)


func panel_title() -> String:
	return "Command Room cassette player"


func first_focus() -> Control:
	return close_button if pending or not _authorized else _tapes


func refresh() -> void:
	if _closing:
		return
	if not _local_eligible():
		interrupt("Return to the Command Room cassette player.")
		return
	if not _opened:
		_opened = true
		_send(&"cassette_open")
		return
	if _authorized and not _reader_authorized():
		interrupt("Playback authorization ended.")
		return
	_rebuild_library()


func select_tape(cassette_id: String) -> void:
	if pending or not _authorized or not _local_eligible() or not _reader_authorized():
		if not _local_eligible():
			interrupt("Move closer to the Command Room cassette player.")
		return
	_send(&"cassette_select", cassette_id, 0)


func read_page(index: int) -> void:
	if pending or selected_cassette.is_empty() or not _authorized:
		return
	var pages: Array = _record.get("pages", [])
	if index < 0 or index >= pages.size():
		return
	if not _local_eligible() or not _reader_authorized():
		interrupt("Playback authorization ended.")
		return
	_send(&"cassette_read", selected_cassette, index)


func interrupt(_reason := "") -> void:
	if _closing:
		return
	_closing = true
	_authorized = false
	_clear_content()
	close_requested.emit()


func _send(action: StringName, cassette_id := "", index := 0) -> void:
	pending = true
	_pending_seconds = 0.0
	_pending_action = action
	_pending_tape = cassette_id
	_pending_page = index
	_pending_id = ""
	_clear_content()
	_status.text = "One moment…"
	var params := {}
	if action != &"cassette_open":
		params["cassette_id"] = cassette_id
	if action == &"cassette_read":
		params["page"] = index
	var result := services.request(action, station_id, params)
	if result.pending:
		_pending_id = result.request_id
	else:
		_accept_result(result)


func _accept_result(result: ActionResult) -> void:
	pending = false
	_pending_id = ""
	if not result.ok or not bool(result.changes.get("authorized", false)) or not _local_eligible() or not _reader_authorized():
		interrupt(result.message)
		return
	if String(result.changes.get("station_id", "")) != String(CassetteLibrary.PLAYER_ID) or String(result.changes.get("actor_id", "")) != String(_actor_id):
		interrupt("The tape player is busy. Try again.")
		return
	_authorized = true
	_rebuild_library(true)
	_status.text = "The world keeps running. Use this Command Room player."
	if _pending_action == &"cassette_open":
		return
	if String(result.changes.get("cassette_id", "")) != _pending_tape:
		interrupt("The tape authorization changed.")
		return
	var returned_page := int(result.changes.get("page", 0))
	if returned_page != _pending_page:
		interrupt("The page authorization changed.")
		return
	if not _reader_matches(_pending_tape, returned_page):
		interrupt("The host's current playback record changed.")
		return
	selected_cassette = _pending_tape
	page_index = returned_page
	_show_briefing()


func _show_briefing() -> void:
	# This is the only method that reads image/instruction metadata.
	if not _authorized or not _local_eligible() or not _reader_authorized() or not _reader_matches(selected_cassette, page_index):
		_clear_content()
		return
	_record = CassetteLibrary.details(selected_cassette)
	if _record.is_empty():
		_status.text = "This tape's offline briefing is unavailable."
		return
	var pages: Array = _record.get("pages", [])
	if page_index < 0 or page_index >= pages.size():
		_status.text = "This briefing page is unavailable."
		return
	_title.text = String(_record.get("title", selected_cassette))
	briefing_text.text = ("Preview - room puzzles are planned.\n\n" if String(_record.get("briefing_status", "preview")) == "preview" else "") + String(pages[page_index])
	caption.text = String(_record.get("caption", "Caption unavailable offline."))
	credit.text = "Credit: " + String(_record.get("credit", "NASA; see source record."))
	var path := String(_record.get("image_path", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		photo.texture = load(path) as Texture2D
	_photo_hint.text = "Photo unavailable offline; caption and credit shown." if photo.texture == null else ""
	_photo_hint.visible = photo.texture == null
	photo.visible = photo.texture != null
	_source.visible = _valid_source_url(String(_record.get("source_url", "")))
	page_label.text = "Page %d / %d" % [page_index + 1, pages.size()]
	_previous.disabled = page_index <= 0
	_next.disabled = page_index + 1 >= pages.size()


func _clear_content() -> void:
	if not _built:
		return
	photo.texture = null
	photo.visible = false
	briefing_text.text = ""
	caption.text = ""
	credit.text = ""
	page_label.text = ""
	_title.text = "Command Room cassette player"
	_record = {}
	_photo_hint.text = "Choose a collected tape at this player."
	_photo_hint.visible = true
	_source.visible = false
	_previous.disabled = true
	_next.disabled = true
	_tapes.disabled = pending or not _authorized


func _local_eligible() -> bool:
	if services == null or not services.has_game() or station_id != CassetteLibrary.PLAYER_ID:
		return false
	var actor := services.local_character()
	if actor == null or actor.id != _actor_id or actor.owner_peer != services.local_peer() or actor.health <= 0.0:
		return false
	var station: Dictionary = services.state().stations.get(String(station_id), {})
	if station.is_empty() or String(station.get("room_id", "")) != "command_center":
		return false
	if String(station.get("kind", "")) not in ["cassette_player_anchor", "cassette_player"]:
		return false
	if actor.position.distance_to(CharacterState._v3(station.get("position", []))) > services.config.interact_distance_m:
		return false
	return services.zones != null and services.zones.zone_at_world(actor.position) == "Command Room"


func _reader_authorized() -> bool:
	return services != null and services.session.cassette_runtime.is_authorized(services.local_peer(), station_id)


func _reader_matches(cassette_id: String, index: int) -> bool:
	var reader: Dictionary = services.session.cassette_runtime.readers.get(str(services.local_peer()), {})
	return String(reader.get("cassette_id", "")) == cassette_id and int(reader.get("page", -1)) == index and CassetteCatalog.collected(services.state(), cassette_id)


func _rebuild_library(force := false) -> void:
	var collected: Array = services.state().repair.get("collected_cassettes", [])
	var signature := JSON.stringify(collected)
	if not force and signature == _library_signature:
		return
	_library_signature = signature
	var popup := _tapes.get_popup()
	popup.clear()
	var records := CassetteLibrary.metadata()
	for i in records.size():
		var record: Dictionary = records[i]
		var available := collected.has(String(record.id))
		popup.add_item("%s - %s" % [record.title, "Collected" if available else "Missing / locked"], i)
		popup.set_item_disabled(i, not available)
	_tapes.disabled = pending or not _authorized


func _on_tape_selected(index: int) -> void:
	var records := CassetteLibrary.metadata()
	if index >= 0 and index < records.size():
		select_tape(String(records[index].id))


func _on_action_resolved(result: ActionResult) -> void:
	if pending and not _pending_id.is_empty() and result.request_id == _pending_id:
		_accept_result(result)


func _process(delta: float) -> void:
	if photo != null and photo.visible and photo.texture != null:
		var scroll := find_child("PhotoColumn", true, false) as ScrollContainer
		if scroll != null:
			var aspect := float(photo.texture.get_width()) / maxf(float(photo.texture.get_height()), 1.0)
			photo.custom_minimum_size.y = maxf(100.0, minf(minf(photo.size.x / aspect, 380.0), scroll.size.y * 0.75))
	if pending:
		_pending_seconds += delta
		if _pending_seconds >= 8.0:
			interrupt("The host did not answer. Use the player again when connected.")
	if _authorized and not _local_eligible():
		interrupt("Playback ended: return to the player.")
	elif _authorized and not pending and not selected_cassette.is_empty() and not _reader_matches(selected_cassette, page_index):
		interrupt("The host ended this tape's playback.")


func _on_recovered(id: StringName, _info: Dictionary) -> void:
	if id == _actor_id:
		interrupt("Crew recovered")


func _on_host_lost(_reason: String) -> void:
	interrupt("Host disconnected")


func _exit_tree() -> void:
	_clear_content()
	if services == null or not is_instance_valid(services):
		return
	# Reliable ordering releases an earlier claim even if its response was still pending.
	if _opened:
		services.request(&"cassette_close", station_id)
	for connection in [[services.events.action_resolved, _on_action_resolved],
		[services.events.character_recovered, _on_recovered], [services.net.host_lost, _on_host_lost]]:
		var sig: Signal = connection[0]
		var callback: Callable = connection[1]
		if sig.is_connected(callback):
			sig.disconnect(callback)


func _open_source() -> void:
	if _authorized and _local_eligible() and _reader_authorized():
		var url := String(_record.get("source_url", ""))
		if _valid_source_url(url):
			OS.shell_open(url)


func _valid_source_url(url: String) -> bool:
	return url.begins_with("https://www.nasa.gov/") or url.begins_with("https://www.jpl.nasa.gov/") or url.begins_with("https://images.nasa.gov/") or url.begins_with("https://science.nasa.gov/") or url.begins_with("https://earthobservatory.nasa.gov/")


func _scroll_column(parent: HBoxContainer, node_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.0
	scroll.follow_focus = true
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.tooltip_text = "Tab to this pane. Arrow keys or Page Up / Page Down scroll its content."
	scroll.gui_input.connect(_on_column_input.bind(scroll))
	parent.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return column


func _on_column_input(event: InputEvent, scroll: ScrollContainer) -> void:
	if not event is InputEventKey or not event.pressed or not scroll.has_focus():
		return
	var step := maxi(24, get_theme_default_font_size())
	var page := maxi(step, int(scroll.size.y * 0.85))
	match event.keycode:
		KEY_DOWN: scroll.scroll_vertical += step
		KEY_UP: scroll.scroll_vertical -= step
		KEY_PAGEDOWN: scroll.scroll_vertical += page
		KEY_PAGEUP: scroll.scroll_vertical -= page
		KEY_HOME: scroll.scroll_vertical = 0
		KEY_END: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		_: return
	scroll.accept_event()


func _label(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
