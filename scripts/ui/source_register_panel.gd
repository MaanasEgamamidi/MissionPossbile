class_name SourceRegisterPanel
extends UiPanel
## The in-game source register (Shift+Backspace): where every fact in the game comes from and how well it was checked.
## Left: a searchable list of facts (claims) and sources with a category filter. Right: the chosen entry in detail.
## Works offline. The only way out is the "Open in browser" button, which calls SourceLibrary.open_url() when pressed.

## Category filter: words shown -> source category ("" = all).
const CATEGORY_FILTERS: Array[Array] = [
	["All", ""],
	["Measured on Mars", "measured"],
	["Models", "modelled"],
	["ISS and Earth tests", "analog"],
	["Technology", "technology"],
	["Fiction", "fiction"],
	["Game balance", "tuning"],
	["Engine and tools", "engine"],
]
const BROWSER_NOTE := "Opens your web browser. The game works without it."

var _built := false
var _pending_id := ""
var _current_id := ""
var _current_url := ""
var _filter_edit: LineEdit
var _category: OptionButton
var _count_label: Label
var _list: ItemList
var _detail_scroll: ScrollContainer
var _detail: VBoxContainer
var _url_label: Label
var _open_button: Button


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	name = "SourceRegisterPanel"
	theme_type_variation = UiTheme.PANEL
	_build()
	_built = true
	_rebuild_list()
	if _pending_id != "":
		show_entry(_pending_id)
	else:
		_show_welcome()


func panel_title() -> String:
	return "Sources"


func first_focus() -> Control:
	if _list != null and _current_id != "":
		return _list
	return _filter_edit


## Opens the register at one source id ("S01") or one claim id ("gravity"). Works before and after setup().
## An empty id shows the start of the register.
func show_entry(id: String) -> void:
	_pending_id = id
	if not _built:
		return
	if id == "":
		_list.deselect_all()
		_show_welcome()
		return
	var index := _index_of(id)
	if index < 0:
		# Hidden by the search or the category filter: show everything again.
		_filter_edit.text = ""
		_category.select(0)
		_rebuild_list()
		index = _index_of(id)
	if index < 0:
		_show_missing(id)
		return
	_list.select(index)
	_list.ensure_current_is_visible()
	_show_detail(id)


## The id of the entry shown in the detail pane ("" for none).
func current_entry_id() -> String:
	return _current_id


## The web address shown for the current entry, exactly as displayed ("" if none).
func displayed_url() -> String:
	return _url_label.text if _url_label != null and is_instance_valid(_url_label) else ""


## The "Open in browser" button of the current entry (null when the entry has no address).
func open_button() -> Button:
	return _open_button if _open_button != null and is_instance_valid(_open_button) else null


## Ids of the entries the list shows now, in order.
func visible_entry_ids() -> PackedStringArray:
	var out := PackedStringArray()
	if _list == null:
		return out
	for i in _list.item_count:
		out.append(String(_list.get_item_metadata(i)))
	return out


## Sets the search text and the category filter (index into CATEGORY_FILTERS) and updates the list.
func set_filter(search: String, category_index: int = 0) -> void:
	_filter_edit.text = search
	_category.select(clampi(category_index, 0, CATEGORY_FILTERS.size() - 1))
	_rebuild_list()


## The search field.
func filter_field() -> LineEdit:
	return _filter_edit


## The category filter (OptionButton with CATEGORY_FILTERS words).
func category_filter() -> OptionButton:
	return _category


## The list of facts and sources.
func entry_list() -> ItemList:
	return _list


## The scrolling detail pane on the right.
func detail_pane() -> ScrollContainer:
	return _detail_scroll


# ---------------------------------------------------------------- building

func _build() -> void:
	var box := VBoxContainer.new()
	box.name = "Box"
	add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "Sources"
	title.theme_type_variation = UiTheme.TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "Close"
	close.tooltip_text = "Close the source register (Esc)."
	close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close)

	var intro := Label.new()
	intro.name = "Intro"
	intro.text = "This register lists where the facts in the game come from. For each one it says how well it was checked, and which numbers are game balance or made up for the game."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(intro)

	var filters := HBoxContainer.new()
	box.add_child(filters)
	var search_label := Label.new()
	search_label.text = "Search"
	filters.add_child(search_label)
	_filter_edit = LineEdit.new()
	_filter_edit.name = "Search"
	_filter_edit.placeholder_text = "Type a word, like oxygen"
	_filter_edit.clear_button_enabled = true
	_filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_edit.text_changed.connect(func(_t: String) -> void: _rebuild_list())
	filters.add_child(_filter_edit)
	var show_label := Label.new()
	show_label.text = "Show"
	filters.add_child(show_label)
	_category = OptionButton.new()
	_category.name = "Category"
	for pair: Array in CATEGORY_FILTERS:
		_category.add_item(String(pair[0]))
	_category.select(0)
	_category.item_selected.connect(func(_i: int) -> void: _rebuild_list())
	filters.add_child(_category)

	var panes := HBoxContainer.new()
	panes.name = "Panes"
	panes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(panes)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	panes.add_child(left)
	_count_label = Label.new()
	_count_label.theme_type_variation = UiTheme.MUTED
	_count_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_count_label)
	_list = ItemList.new()
	_list.name = "EntryList"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(160, 120)
	_list.select_mode = ItemList.SELECT_SINGLE
	_list.item_selected.connect(func(i: int) -> void: _show_detail(String(_list.get_item_metadata(i))))
	left.add_child(_list)

	_detail_scroll = ScrollContainer.new()
	_detail_scroll.name = "Detail"
	_detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_scroll.size_flags_stretch_ratio = 1.5
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panes.add_child(_detail_scroll)
	_detail = VBoxContainer.new()
	_detail.name = "DetailBox"
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll.add_child(_detail)


# ---------------------------------------------------------------- list

func _rebuild_list() -> void:
	var keep := _current_id
	_list.clear()
	var words := _filter_edit.text.strip_edges().to_lower()
	var cat := String(CATEGORY_FILTERS[maxi(_category.selected, 0)][1])
	var facts := 0
	var srcs := 0
	for c: Dictionary in SourceLibrary.claims():
		if cat != "" and not SourceLibrary.claim_filter_categories(c).has(cat):
			continue
		if not _matches(words, [c.get("id", ""), c.get("title", ""), c.get("text", ""), c.get("note", "")]):
			continue
		var mark := "! " if SourceLibrary.is_unsourced(c) else ""
		var i := _list.add_item("%sFact: %s" % [mark, String(c.get("title", ""))])
		_list.set_item_metadata(i, String(c.get("id", "")))
		_list.set_item_tooltip(i, String(c.get("text", "")))
		facts += 1
	for s: Dictionary in SourceLibrary.sources():
		if cat != "" and String(s.get("category", "")) != cat:
			continue
		if not _matches(words, [s.get("id", ""), s.get("title", ""), s.get("publisher", ""), s.get("values_read", ""), s.get("supports", ""), s.get("mission_site", ""), s.get("note", "")]):
			continue
		var tail := "" if SourceLibrary.is_citable(s) else " (not yet checked)"
		var i := _list.add_item("%s · %s%s" % [String(s.get("id", "")), String(s.get("title", "")), tail])
		_list.set_item_metadata(i, String(s.get("id", "")))
		_list.set_item_tooltip(i, SourceLibrary.status_text(s))
		srcs += 1
	_count_label.text = "Showing %d facts and %d sources." % [facts, srcs] if facts + srcs > 0 else "Nothing matches. Try another word or choose All."
	if keep != "":
		var index := _index_of(keep)
		if index >= 0:
			_list.select(index)


func _matches(words: String, fields: Array) -> bool:
	if words == "":
		return true
	for f: Variant in fields:
		if String(f).to_lower().contains(words):
			return true
	return false


func _index_of(id: String) -> int:
	for i in _list.item_count:
		if String(_list.get_item_metadata(i)) == id:
			return i
	return -1


# ---------------------------------------------------------------- detail

func _clear_detail() -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	_url_label = null
	_open_button = null
	_current_url = ""
	_detail_scroll.scroll_vertical = 0


func _show_welcome() -> void:
	_clear_detail()
	_current_id = ""
	_text("How to use the register", UiTheme.HEADING)
	_text("Choose a fact or a source in the list to see where it comes from.")
	_text("✓ Checked: the page was opened and the numbers were read from it.")
	_text("! Not yet checked: the page was found but not opened yet. It is a lead, not a source the game relies on.")
	_text("Game balance and made-up parts are marked too, so you can tell real Mars facts from game rules.")


func _show_missing(id: String) -> void:
	_clear_detail()
	_current_id = ""
	_text("Not in the register", UiTheme.HEADING)
	_text("There is no entry called \"%s\" yet." % id)


func _show_detail(id: String) -> void:
	_pending_id = id
	var c := SourceLibrary.claim(id)
	if not c.is_empty():
		_show_claim(c)
		return
	var s := SourceLibrary.source(id)
	if not s.is_empty():
		_show_source(s)
		return
	_show_missing(id)


func _show_claim(c: Dictionary) -> void:
	_clear_detail()
	_current_id = String(c.get("id", ""))
	_text(String(c.get("title", "")), UiTheme.HEADING)
	_text(String(c.get("text", "")))
	var unsourced := SourceLibrary.is_unsourced(c)
	if unsourced:
		_text("! Source not yet checked.", UiTheme.WARN)
	_row("Kind of fact", SourceLibrary.claim_category_text(c))
	var cited := SourceLibrary.citable_sources_of(c)
	if not cited.is_empty():
		_text("Sources", UiTheme.HEADING)
		for s: Dictionary in cited:
			_link_button("✓ %s · %s (%s)" % [String(s.id), String(s.title), SourceLibrary.status_text(s)], String(s.id))
	var leads: Array = []
	for sid: Variant in (c.get("source_ids", []) as Array) + (c.get("lead_ids", []) as Array):
		var s := SourceLibrary.source(String(sid))
		if not s.is_empty() and not SourceLibrary.is_citable(s):
			leads.append(s)
	if not leads.is_empty():
		_text("Leads, not yet checked", UiTheme.HEADING)
		for s: Dictionary in leads:
			_link_button("! %s · %s (%s)" % [String(s.id), String(s.title), SourceLibrary.status_text(s)], String(s.id))
	var cat := String(c.get("category", ""))
	if cited.is_empty() and leads.is_empty():
		match cat:
			"balance":
				_text("No source: this is a game balance number, chosen to make the game fun.", UiTheme.MUTED)
			"fiction":
				_text("No source: this part is made up for the game.", UiTheme.MUTED)
			"game_time":
				_text("No source: this is how the game handles time.", UiTheme.MUTED)
	_row("Note", String(c.get("note", "")))


func _show_source(s: Dictionary) -> void:
	_clear_detail()
	_current_id = String(s.get("id", ""))
	var citable := SourceLibrary.is_citable(s)
	_text("%s · %s" % [_current_id, String(s.get("title", ""))], UiTheme.HEADING)
	var status_symbol := "✓" if citable else "!"
	_text("%s %s" % [status_symbol, SourceLibrary.status_text(s)], UiTheme.GOOD if citable else UiTheme.WARN)
	if not citable:
		_text("This page was not opened and checked, so the game does not use it as a source. What is written below is a lead only.", UiTheme.MUTED)
	_row("Published by", String(s.get("publisher", "")))
	_row("Kind", String(s.get("kind", "")))
	_row("Kind of evidence", SourceLibrary.category_text(String(s.get("category", ""))))
	_row("Mission and site", String(s.get("mission_site", "")))
	_row("Observation dates", String(s.get("observation_dates", "")))
	_row("Units", String(s.get("units", "")))
	_row("What was read" if citable else "Leads (not checked)", String(s.get("values_read", "")))
	_row("What it supports", String(s.get("supports", "")))
	var users: PackedStringArray = []
	for c: Dictionary in SourceLibrary.claims_using(_current_id):
		users.append(String(c.get("title", "")))
	_row("Facts in the game that use it", ", ".join(users) if not users.is_empty() else "None yet")
	_row("Note", String(s.get("note", "")))

	var url := String(s.get("url", ""))
	_text("Web address", UiTheme.HEADING)
	if url == "":
		_text("No web address in the register.", UiTheme.MUTED)
		return
	_current_url = url
	_url_label = _text(url)
	_url_label.name = "UrlLabel"
	_url_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	var row := HBoxContainer.new()
	_detail.add_child(row)
	_open_button = Button.new()
	_open_button.name = "OpenInBrowser"
	_open_button.text = "Open in browser"
	_open_button.tooltip_text = BROWSER_NOTE
	_open_button.disabled = not SourceLibrary.is_safe_url(url)
	_open_button.pressed.connect(_on_open_pressed)
	row.add_child(_open_button)
	_text(BROWSER_NOTE, UiTheme.MUTED)


func _on_open_pressed() -> void:
	SourceLibrary.open_url(_current_url)


func _text(words: String, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.text = words
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != &"":
		label.theme_type_variation = variation
	_detail.add_child(label)
	return label


func _row(heading: String, value: String) -> void:
	if value.strip_edges() == "":
		return
	_text("%s: %s" % [heading, value])


func _link_button(words: String, id: String) -> void:
	var b := Button.new()
	b.text = words
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = "Show this source."
	b.pressed.connect(func() -> void: _go_to.call_deferred(id))
	_detail.add_child(b)


func _go_to(id: String) -> void:
	show_entry(id)
	_list.grab_focus()
