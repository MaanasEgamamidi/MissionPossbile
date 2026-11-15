class_name InventoryPanel
extends UiPanel
## Cargo (I key): what your crew member carries, with a "Put down" button for each thing, and the caches you know
## of. It only reads state; "Put down" asks the host with a `drop` request.

var _slots: Label
var _items_box: VBoxContainer
var _answer: Label
var _caches_box: VBoxContainer
var _close: Button
var _signature := ""
var _pending_request := ""
var _cassette_rows: Dictionary = {}


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	name = "InventoryPanel"
	theme_type_variation = UiTheme.PANEL
	var box := VBoxContainer.new()
	box.name = "Box"
	add_child(box)
	var header := HBoxContainer.new()
	header.name = "Header"
	box.add_child(header)
	var title := Label.new()
	title.name = "Title"
	title.text = "Cargo"
	title.theme_type_variation = UiTheme.TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(ExplainButton.make("cargo"))
	_close = Button.new()
	_close.name = "Close"
	_close.text = "Close"
	_close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(_close)
	_slots = Label.new()
	_slots.name = "Slots"
	_slots.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_slots)
	_answer = Label.new()
	_answer.name = "Answer"
	_answer.theme_type_variation = UiTheme.MUTED
	_answer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_answer.visible = false
	box.add_child(_answer)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	_items_box = VBoxContainer.new()
	_items_box.name = "Items"
	content.add_child(_items_box)
	var cassette_heading := Label.new()
	cassette_heading.name = "CassetteHeading"
	cassette_heading.text = "Shared cassette library"
	cassette_heading.theme_type_variation = UiTheme.HEADING
	content.add_child(cassette_heading)
	var cassette_note := Label.new()
	cassette_note.name = "CassettePlaybackLocation"
	cassette_note.text = "Play at Command Room cassette player."
	cassette_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(cassette_note)
	for entry: Dictionary in CassetteLibrary.metadata():
		var row := Label.new()
		row.name = String(entry.id).validate_node_name()
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(row)
		_cassette_rows[String(entry.id)] = row

	var heading := Label.new()
	heading.name = "CachesHeading"
	heading.text = "Caches you know of"
	heading.theme_type_variation = UiTheme.HEADING
	content.add_child(heading)
	var explain_row := HBoxContainer.new()
	explain_row.name = "CacheExplain"
	var explain := Label.new()
	explain.text = "A cache is the cargo left behind when a crew member was brought back to the Med Bay. Walk there to pick it up again."
	explain.theme_type_variation = UiTheme.MUTED
	explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	explain_row.add_child(explain)
	explain_row.add_child(ExplainButton.make("recovery"))
	content.add_child(explain_row)
	_caches_box = VBoxContainer.new()
	_caches_box.name = "Caches"
	content.add_child(_caches_box)
	services.events.action_resolved.connect(_on_action_resolved)
	refresh()


func panel_title() -> String:
	return "Cargo"


func first_focus() -> Control:
	var first := _first_put_down()
	return first if first != null else _close


func refresh() -> void:
	if services == null or not services.has_game():
		return
	var me := services.local_character()
	var slots := services.balance.cargo_slots
	var cargo: Array[StringName] = []
	if me == null:
		_slots.text = "Choose a crew member first: press %s for the crew screen." % _key(&"crew", "C")
	else:
		cargo = me.cargo
		_slots.text = "%s carries %d of %d slots." % [me.display_name, cargo.size(), slots]
	var parts := PackedStringArray()
	for id: StringName in cargo:
		parts.append(String(id))
	parts.append("|")
	for c: Dictionary in services.state().caches:
		parts.append("%s:%d" % [c.get("id", ""), (c.get("items", []) as Array).size()])
	var collected: Array = services.state().repair.get("collected_cassettes", [])
	for entry: Dictionary in CassetteLibrary.metadata():
		var id := String(entry.id)
		parts.append(id + (":collected" if collected.has(id) else ":missing"))
		(_cassette_rows[id] as Label).text = "%s - %s" % [entry.title, "Collected" if collected.has(id) else "Missing"]
	var signature := ",".join(parts)
	if signature != _signature:
		_signature = signature
		_rebuild(cargo)
	_refresh_caches(me)


## Plain name of an item kind: "supply_crate" -> "Supply crate".
static func kind_name(kind: String) -> String:
	if kind == "":
		return "Something"
	var words := kind.replace("_", " ").strip_edges()
	return words.left(1).to_upper() + words.substr(1)


## The "Put down" buttons now shown, in list order.
func put_down_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for row in _items_box.get_children():
		var b := row.get_node_or_null("PutDown") as Button
		if b != null:
			out.append(b)
	return out


func _rebuild(cargo: Array[StringName]) -> void:
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var had_focus := focus != null and _items_box.is_ancestor_of(focus)
	for child in _items_box.get_children():
		_items_box.remove_child(child)
		child.queue_free()
	if cargo.is_empty():
		var empty := Label.new()
		empty.name = "Empty"
		empty.text = "Your hands and pack are empty. Look at something and press %s to pick it up." % _key(&"interact", "E")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_items_box.add_child(empty)
	for id: StringName in cargo:
		var rec: Dictionary = services.state().items.get(id, {})
		var row := HBoxContainer.new()
		row.name = "Item_" + String(id).validate_node_name()
		row.set_meta("item_id", id)
		var l := Label.new()
		l.name = "Name"
		l.text = kind_name(String(rec.get("kind", "")))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		var b := Button.new()
		b.name = "PutDown"
		b.text = "Put down"
		b.pressed.connect(_put_down.bind(id))
		row.add_child(b)
		_items_box.add_child(row)
	if had_focus:
		var first := _first_put_down()
		(first if first != null else _close).grab_focus.call_deferred()


func _refresh_caches(me: CharacterState) -> void:
	var caches: Array = services.state().caches
	if _caches_box.get_child_count() != maxi(1, caches.size()):
		for child in _caches_box.get_children():
			_caches_box.remove_child(child)
			child.queue_free()
		for i in maxi(1, caches.size()):
			var l := Label.new()
			l.name = "Cache_%d" % i
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_caches_box.add_child(l)
	if caches.is_empty():
		(_caches_box.get_child(0) as Label).text = "No caches. Nothing has been left behind."
		return
	for i in caches.size():
		var c: Dictionary = caches[i]
		var p := CharacterState._v3(c.get("position", []))
		var where := services.zones.zone_at_world(p) if services.zones != null else "somewhere outside"
		var count := (c.get("items", []) as Array).size()
		var text := "! Cache with %d %s in %s" % [count, "thing" if count == 1 else "things", where]
		if me != null:
			text += ", %d m from you" % roundi(Vector2(p.x, p.z).distance_to(Vector2(me.position.x, me.position.z)))
		(_caches_box.get_child(i) as Label).text = text + "."


func _put_down(id: StringName) -> void:
	var rec: Dictionary = services.state().items.get(id, {})
	var thing := kind_name(String(rec.get("kind", ""))).to_lower()
	var result := services.request(&"drop", id)
	if result.pending:
		_pending_request = result.request_id
		_show_answer("Asked the host to put down the %s…" % thing)
	elif result.ok:
		_show_answer("You put down the %s." % thing)
	else:
		_show_answer(result.message)
	refresh()


func _on_action_resolved(result: ActionResult) -> void:
	if _pending_request != "" and result.request_id == _pending_request:
		_pending_request = ""
		_show_answer("Done." if result.ok else result.message)


func _show_answer(text: String) -> void:
	_answer.text = text
	_answer.visible = text != ""


func _first_put_down() -> Button:
	var list := put_down_buttons()
	for b in list:
		if not b.is_queued_for_deletion():
			return b
	return null


static func _key(action: StringName, fallback: String) -> String:
	var k := PlayerInput.describe(action)
	return k if k != "" else fallback
