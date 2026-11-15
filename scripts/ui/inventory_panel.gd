class_name InventoryPanel
extends UiPanel
## Cargo (I key): what your crew member carries, the tapes the crew has found, and the cargo left behind outside.
## UI overhaul (2026-11-15): pictures and short words.
##   * One tile per cargo slot: a carried thing is a large tile with its pictogram, its short name and a "Put down"
##     button (it asks the host with a `drop` request); a free slot is an empty tile. "3 / 6" beside the title.
##   * The shared tape library is one row of six small tapes in their own colours: found = filled with the green tick,
##     not found yet = a dim outline. The room's name is under each; "Command center - Collected" is the tooltip.
##   * Cargo left behind (a cache) shows only when there is some: a crate, how many things, where and how far.
##   * The explanations are behind the "?" buttons and in tooltips.
## It only reads state.

const Kit = preload("res://scripts/ui/menu_kit.gd")
const HudKit := preload("res://scripts/ui/hud/hud_kit.gd")
const PuzzleKit := preload("res://scripts/tasks/puzzles/kit.gd")
const CACHE_HELP := "A cache is the cargo left behind when a crew member was brought back to the hub. Walk there to pick it up again."
## Tile width at text size 1.
const TILE_W := 190.0

var _slots: Label
var _items_box: HFlowContainer
var _empty_row: HBoxContainer
var _answer: Label
var _caches_box: VBoxContainer
var _caches_head: HBoxContainer
var _tapes_count: Label
var _close: Button
var _signature := ""
var _pending_request := ""
var _cassette_rows: Dictionary = {}     # tape id -> the Label under its picture
var _cassette_pics: Dictionary = {}     # tape id -> the drawn tape (Control; meta "found")


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	name = "InventoryPanel"
	theme_type_variation = UiTheme.PANEL
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override(&"separation", 10)
	add_child(box)
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override(&"separation", 12)
	box.add_child(header)
	header.add_child(HudKit.Icon.new(&"cargo", UiTheme.palette().heading, 40.0, "Symbol"))
	var title := Label.new()
	title.name = "Title"
	title.text = "Cargo"
	title.theme_type_variation = UiTheme.TITLE
	header.add_child(title)
	_slots = Label.new()
	_slots.name = "Slots"
	_slots.theme_type_variation = UiTheme.READING
	_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(_slots)
	header.add_child(ExplainButton.make("cargo"))
	_close = _close_button()
	_close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(_close)
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
	scroll.follow_focus = true
	box.add_child(scroll)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override(&"separation", 10)
	scroll.add_child(content)
	# one cue while nothing is carried: "Nothing carried.  [E] picks things up"
	_empty_row = HBoxContainer.new()
	_empty_row.name = "Empty"
	_empty_row.add_theme_constant_override(&"separation", 10)
	_empty_row.visible = false
	content.add_child(_empty_row)
	_items_box = HFlowContainer.new()
	_items_box.name = "Items"
	_items_box.add_theme_constant_override(&"h_separation", 10)
	_items_box.add_theme_constant_override(&"v_separation", 10)
	content.add_child(_items_box)

	# the shared tape library: one compact row
	var tapes_head := HBoxContainer.new()
	tapes_head.name = "CassetteHead"
	tapes_head.add_theme_constant_override(&"separation", 12)
	content.add_child(tapes_head)
	var cassette_heading := Label.new()
	cassette_heading.name = "CassetteHeading"
	cassette_heading.text = "Tapes"
	cassette_heading.tooltip_text = "The shared cassette library: every tape the crew has found."
	cassette_heading.mouse_filter = Control.MOUSE_FILTER_PASS
	cassette_heading.theme_type_variation = UiTheme.HEADING
	tapes_head.add_child(cassette_heading)
	_tapes_count = Label.new()
	_tapes_count.name = "CassetteCount"
	tapes_head.add_child(_tapes_count)
	var cassette_note := Label.new()
	cassette_note.name = "CassettePlaybackLocation"
	cassette_note.text = "Play at Command Room cassette player."
	cassette_note.theme_type_variation = UiTheme.MUTED
	cassette_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cassette_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cassette_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tapes_head.add_child(cassette_note)
	var tapes := HFlowContainer.new()
	tapes.name = "Cassettes"
	tapes.add_theme_constant_override(&"h_separation", 10)
	tapes.add_theme_constant_override(&"v_separation", 8)
	content.add_child(tapes)
	for entry: Dictionary in CassetteLibrary.metadata():
		var id := String(entry.id)
		var chip := VBoxContainer.new()
		chip.name = "Tape_" + id.validate_node_name()
		chip.add_theme_constant_override(&"separation", 2)
		tapes.add_child(chip)
		var pic := Control.new()
		pic.name = "Picture"
		pic.custom_minimum_size = Vector2(96, 60)
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.set_meta(&"found", false)
		pic.set_meta(&"color", Color(String((CassetteCatalog.TAPES[id] as Dictionary).get("color", "c0c8d8"))))
		pic.draw.connect(_draw_tape.bind(pic))
		chip.add_child(pic)
		var row := Label.new()
		row.name = id.validate_node_name()
		row.text = String(entry.title)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.add_child(row)
		_cassette_rows[id] = row
		_cassette_pics[id] = pic

	# cargo left behind: shown only when there is some
	_caches_head = HBoxContainer.new()
	_caches_head.name = "CacheExplain"
	_caches_head.add_theme_constant_override(&"separation", 12)
	var heading := Label.new()
	heading.name = "CachesHeading"
	heading.text = "Left behind"
	heading.tooltip_text = CACHE_HELP
	heading.mouse_filter = Control.MOUSE_FILTER_PASS
	heading.theme_type_variation = UiTheme.HEADING
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_caches_head.add_child(heading)
	_caches_head.add_child(ExplainButton.make("recovery"))
	content.add_child(_caches_head)
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


## "2 / 6": slots used of the slots there are ("" before a crew member is chosen).
func slots_text() -> String:
	return _slots.text


func refresh() -> void:
	if services == null or not services.has_game():
		return
	var me := services.local_character()
	var slots := services.balance.cargo_slots
	var cargo: Array[StringName] = []
	if me == null:
		_slots.text = ""
		_slots.tooltip_text = ""
	else:
		cargo = me.cargo
		_slots.text = "%d / %d" % [cargo.size(), slots]
		_slots.tooltip_text = "%s carries %d of %d slots." % [me.display_name, cargo.size(), slots]
	var parts := PackedStringArray()
	parts.append("%s|%d|%.2f" % [me != null, slots, UiTheme.text_scale()])
	for id: StringName in cargo:
		parts.append(String(id))
	parts.append("|")
	for c: Dictionary in services.state().caches:
		parts.append("%s:%d" % [c.get("id", ""), (c.get("items", []) as Array).size()])
	var collected: Array = services.state().repair.get("collected_cassettes", [])
	var found := 0
	for entry: Dictionary in CassetteLibrary.metadata():
		var id := String(entry.id)
		var has := collected.has(id)
		found += int(has)
		parts.append(id + (":collected" if has else ":missing"))
		var row := _cassette_rows[id] as Label
		row.tooltip_text = "%s - %s" % [entry.title, "Collected" if has else "Missing"]
		row.theme_type_variation = &"" if has else UiTheme.MUTED
		var pic := _cassette_pics[id] as Control
		if bool(pic.get_meta(&"found")) != has:
			pic.set_meta(&"found", has)
			pic.queue_redraw()
	_tapes_count.text = "%d / %d" % [found, _cassette_rows.size()]
	var signature := ",".join(parts)
	if signature != _signature:
		_signature = signature
		_rebuild(cargo, slots, me != null)
	_refresh_caches(me)


## Plain name of an item kind: "supply_crate" -> "Supply crate".
static func kind_name(kind: String) -> String:
	if kind == "":
		return "Something"
	var words := kind.replace("_", " ").strip_edges()
	return words.left(1).to_upper() + words.substr(1)


## The pictogram (HudKit) of an item kind: a crate, a spanner for parts and tools, a flask for samples and ore.
static func kind_icon(kind: String) -> StringName:
	if kind.begins_with("salvaged_") or kind.contains("part") or kind.contains("tool"):
		return &"build"
	if kind.contains("sample") or kind.contains("ore"):
		return &"science"
	return &"cargo"


## The "Put down" buttons now shown, in slot order. A button's parent carries the item's id (meta "item_id").
func put_down_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for tile in _items_box.get_children():
		var b := tile.find_child("PutDown", true, false) as Button
		if b != null:
			out.append(b)
	return out


func _rebuild(cargo: Array[StringName], slots: int, has_crew: bool) -> void:
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var had_focus := focus != null and _items_box.is_ancestor_of(focus)
	for child in _items_box.get_children():
		_items_box.remove_child(child)
		child.queue_free()
	var s := UiTheme.text_scale()
	var tile_size := Vector2(roundf(TILE_W * s), roundf(150.0 + 50.0 * s))
	for child in _empty_row.get_children():
		_empty_row.remove_child(child)
		child.queue_free()
	_empty_row.visible = not has_crew or cargo.is_empty()
	if _empty_row.visible:
		var words := Label.new()
		words.name = "EmptyText"
		words.text = "Nothing carried." if has_crew else "Pick a crew member first:"
		_empty_row.add_child(words)
		_empty_row.add_child(UiTheme.key_cap((_key(&"interact", "E") if has_crew else _key(&"crew", "C")).get_slice(" / ", 0)))
		if has_crew:
			var verb := Label.new()
			verb.text = "picks things up"
			verb.theme_type_variation = UiTheme.MUTED
			_empty_row.add_child(verb)
	for i in (maxi(slots, cargo.size()) if has_crew else 0):
		var tile := PanelContainer.new()
		tile.custom_minimum_size = tile_size
		_items_box.add_child(tile)
		if i >= cargo.size():
			tile.name = "Free_%d" % i
			tile.custom_minimum_size.y = roundf(96.0 * s)      # a row of free slots only is a low row
			tile.add_theme_stylebox_override(&"panel", _free_box())
			tile.tooltip_text = "A free slot."
			continue
		var id := cargo[i]
		var rec: Dictionary = services.state().items.get(id, {})
		var kind := String(rec.get("kind", ""))
		tile.name = "Item_" + String(id).validate_node_name()
		tile.theme_type_variation = UiTheme.CARD
		tile.set_meta("item_id", id)
		var col := VBoxContainer.new()
		col.name = "Col"
		col.set_meta("item_id", id)
		col.add_theme_constant_override(&"separation", 4)
		tile.add_child(col)
		var icon := HudKit.Icon.new(kind_icon(kind), UiTheme.palette().text, 64.0, "Symbol")
		col.add_child(icon)
		var l := Label.new()
		l.name = "Name"
		l.text = kind_name(kind)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(l)
		var b := Kit.button("Put down", &"down", &"", 22.0, 1.0, 48.0)
		b.name = "PutDown"
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.tooltip_text = "Put the %s down here." % kind_name(kind).to_lower()
		b.pressed.connect(_put_down.bind(id))
		col.add_child(b)
	if had_focus:
		var first := _first_put_down()
		(first if first != null else _close).grab_focus.call_deferred()


func _refresh_caches(me: CharacterState) -> void:
	var caches: Array = services.state().caches
	_caches_head.visible = not caches.is_empty()
	_caches_box.visible = not caches.is_empty()
	if _caches_box.get_child_count() != caches.size():
		for child in _caches_box.get_children():
			_caches_box.remove_child(child)
			child.queue_free()
		for i in caches.size():
			var row := HBoxContainer.new()
			row.name = "CacheRow_%d" % i
			row.add_theme_constant_override(&"separation", 10)
			row.add_child(HudKit.Icon.new(&"cargo", UiTheme.palette().warn, 32.0, "Symbol"))
			var l := Label.new()
			l.name = "Cache_%d" % i
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			_caches_box.add_child(row)
	for i in caches.size():
		var c: Dictionary = caches[i]
		var p := CharacterState._v3(c.get("position", []))
		var where := services.zones.zone_at_world(p) if services.zones != null else "somewhere outside"
		var count := (c.get("items", []) as Array).size()
		var text := "%d %s · %s" % [count, "thing" if count == 1 else "things", where]
		if me != null:
			text += " · %d m away" % roundi(Vector2(p.x, p.z).distance_to(Vector2(me.position.x, me.position.z)))
		(_caches_box.get_child(i).get_node("Cache_%d" % i) as Label).text = text


## A small cassette: filled in its own colour with the green tick when found, a dim outline when not.
func _draw_tape(pic: Control) -> void:
	var found := bool(pic.get_meta(&"found"))
	var color: Color = pic.get_meta(&"color")
	var r := Rect2(Vector2(4, 4), pic.size - Vector2(8, 8))
	var edge: Color = UiTheme.palette().border
	if found:
		PuzzleKit.box(pic, r, color, 8.0, PuzzleKit.INK, 2.0)
		PuzzleKit.box(pic, Rect2(r.position + Vector2(r.size.x * 0.14, r.size.y * 0.2), Vector2(r.size.x * 0.72, r.size.y * 0.42)),
			Color(1, 1, 1, 0.85), 4.0)
	else:
		PuzzleKit.box(pic, r, Color(edge, 0.12), 8.0, Color(edge, 0.9), 2.0)
	var ink: Color = PuzzleKit.INK if found else Color(edge, 0.9)
	for x: float in [0.34, 0.66]:
		pic.draw_arc(r.position + Vector2(r.size.x * x, r.size.y * 0.41), r.size.y * 0.13, 0.0, TAU, 20, ink, 2.0, true)
	if found:
		PuzzleKit.tick(pic, Vector2(r.end.x - 9.0, r.end.y - 9.0), 13.0)


## A square close button with a drawn X (Esc closes too).
static func _close_button() -> Button:
	var b := Button.new()
	b.name = "Close"
	b.custom_minimum_size = Vector2(52, 48)
	b.tooltip_text = "Close (Esc)"
	b.accessibility_name = "Close"
	b.draw.connect(func() -> void:
		var s := minf(b.size.x, b.size.y) * 0.4
		HudKit.draw_icon(b, &"close", Rect2((b.size - Vector2(s, s)) * 0.5, Vector2(s, s)), UiTheme.palette().text))
	return b


static func _free_box() -> StyleBoxFlat:
	var edge: Color = UiTheme.palette().border
	var s := StyleBoxFlat.new()
	s.bg_color = Color(edge, 0.08)
	s.border_color = Color(edge, 0.9 if UiTheme.is_high_contrast() else 0.55)
	s.set_border_width_all(2)
	s.set_corner_radius_all(12)
	return s


func _put_down(id: StringName) -> void:
	var rec: Dictionary = services.state().items.get(id, {})
	var thing := kind_name(String(rec.get("kind", ""))).to_lower()
	var result := services.request(&"drop", id)
	if result.pending:
		_pending_request = result.request_id
		_show_answer("Putting down the %s…" % thing)
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
