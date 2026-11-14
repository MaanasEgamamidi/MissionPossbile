class_name ExplainButton
extends Button
## A small "?" button next to a reading. Its tooltip is the one-sentence explanation. Pressing it opens a small
## popup with the longer explanation, what kind of fact each linked claim is ("measured on Mars", "game balance"...)
## and a "Sources" button that opens the source register at the right entry.
## Keyboard: the button takes focus like any button; in the popup Esc closes the popup first.

## Asks for the source register to be opened at an entry id (a claim id, a source id, or "" for the start).
signal sources_requested(id: String)

## Which entry of data/explanations.json this button explains.
var explanation_id := "":
	set(value):
		explanation_id = value
		_update_tooltip()

## The source register this button last asked to open (kept so tests and callers can check it).
var last_register: SourceRegisterPanel

## Additional guidance specific to the control or screen.
var extra_text := ""
var custom_title := ""

var _popup: PopupPanel
var _scroll: ScrollContainer
var _content: VBoxContainer
var _sources_button: Button
var _close_button: Button


## A "?" button for one explanation id.
static func make(id: String, extra: String = "", title: String = "") -> ExplainButton:
	var b := ExplainButton.new()
	b.explanation_id = id
	b.extra_text = extra
	b.custom_title = title
	return b


func _init() -> void:
	text = "?"
	focus_mode = Control.FOCUS_ALL
	pressed.connect(open_popup)


func _ready() -> void:
	_update_tooltip()


## The explanation shown by this button (see Explanations.get_entry).
func entry() -> Dictionary:
	return Explanations.get_entry(explanation_id)


## The register entry the "Sources" button opens: the first linked claim, else the first source, else "".
func sources_target() -> String:
	var e := entry()
	var claim_ids: PackedStringArray = e.get("claim_ids", PackedStringArray())
	if not claim_ids.is_empty():
		return claim_ids[0]
	var source_ids: PackedStringArray = e.get("source_ids", PackedStringArray())
	if not source_ids.is_empty():
		return source_ids[0]
	return ""


## The popup (null until first opened).
func popup_window() -> PopupPanel:
	return _popup


## True while the popup is showing.
func is_popup_open() -> bool:
	return _popup != null and _popup.visible


## The popup's "Sources" button (null until first opened).
func sources_button() -> Button:
	return _sources_button


## Opens the explanation popup and moves keyboard focus into it.
func open_popup() -> void:
	if _popup == null:
		_build_popup()
	_fill_popup()
	_popup.popup_centered(Vector2i(_popup_width(), 0))
	_fit_popup.call_deferred()
	(_sources_button if _sources_button.visible else _close_button).grab_focus.call_deferred()


## Closes the popup and gives focus back to the "?" button.
func close_popup() -> void:
	if _popup != null and _popup.visible:
		_popup.hide()


## Same as pressing "Sources" in the popup: emits sources_requested and, if this button sits inside a UiPanel,
## asks that panel to open a SourceRegisterPanel at the right entry.
func request_sources() -> void:
	var target := sources_target()
	close_popup()
	sources_requested.emit(target)
	var owner_panel := _owning_panel()
	if owner_panel != null:
		var register := SourceRegisterPanel.new()
		register.show_entry(target)
		last_register = register
		owner_panel.open_requested.emit(register)


func _update_tooltip() -> void:
	var e := Explanations.get_entry(explanation_id)
	tooltip_text = String(e.get("short", "")) if not e.is_empty() else ""


func _owning_panel() -> UiPanel:
	var node := get_parent()
	while node != null:
		if node is UiPanel:
			return node as UiPanel
		node = node.get_parent()
	return null


func _popup_width() -> int:
	var font_size := get_theme_font_size(&"font_size", &"Label")
	var wanted := float(maxi(font_size, 12) * 26)
	var screen := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	return int(clampf(wanted, 280.0, screen.x * 0.9))


func _build_popup() -> void:
	_popup = PopupPanel.new()
	_popup.name = "ExplainPopup"
	_popup.theme = UiTheme.get_theme()
	_popup.popup_hide.connect(_on_popup_hide)
	_popup.window_input.connect(_on_popup_input)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_popup.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.minimum_size_changed.connect(_fit_popup)
	_scroll.add_child(_content)
	add_child(_popup)


func _fill_popup() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var e := entry()
	if e.is_empty():
		_add_label(custom_title if custom_title != "" else "Help", UiTheme.HEADING)
		if extra_text == "":
			_add_label("This help text has not been written yet.", &"")
	else:
		_add_label(String(e.title), UiTheme.HEADING)
		_add_label(String(e.long), &"")
		var claim_ids: PackedStringArray = e.claim_ids
		if not claim_ids.is_empty():
			_add_label("What kind of facts these are:", UiTheme.MUTED)
			for cid in claim_ids:
				var c := SourceLibrary.claim(cid)
				if c.is_empty():
					continue
				var mark := "!" if SourceLibrary.is_unsourced(c) else "•"
				_add_label("%s %s: %s" % [mark, String(c.get("title", cid)), SourceLibrary.claim_category_text(c)], &"")
	if extra_text != "":
		_add_label(extra_text, &"")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	_sources_button = Button.new()
	_sources_button.name = "SourcesButton"
	_sources_button.text = "Sources"
	_sources_button.tooltip_text = "Open the source register at this topic."
	_sources_button.pressed.connect(request_sources)
	row.add_child(_sources_button)
	_sources_button.visible = not e.is_empty()
	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "Close"
	_close_button.pressed.connect(close_popup)
	row.add_child(_close_button)
	_content.add_child(row)


func _add_label(words: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = words
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != &"":
		label.theme_type_variation = variation
	_content.add_child(label)
	return label


func _fit_popup() -> void:
	if _popup == null or not _popup.visible:
		return
	var style := _popup.get_theme_stylebox(&"panel", &"PopupPanel")
	var margins := style.get_minimum_size() if style != null else Vector2.ZERO
	var screen := get_viewport().get_visible_rect().size
	var width := _popup_width()
	var height := int(ceilf(_content.get_combined_minimum_size().y + margins.y))
	height = mini(height, int(screen.y * 0.9))
	var new_size := Vector2i(width, height)
	if new_size == _popup.size:
		return
	var centre := _popup.position + _popup.size / 2
	_popup.size = new_size
	_popup.position = centre - new_size / 2


func _on_popup_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_popup.set_input_as_handled()
		close_popup()


func _on_popup_hide() -> void:
	if is_inside_tree() and is_visible_in_tree():
		grab_focus.call_deferred()
