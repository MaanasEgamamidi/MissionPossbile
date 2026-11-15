class_name UiComposition
extends RefCounted
## Shared interaction primitives, not a shared screen layout. R01/R03/R07/R28 in the reference atlas.

static func label(parent: Node, text: String, role: StringName = &"") -> Label:
	var node := Label.new()
	node.text = text
	node.theme_type_variation = role
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


static func button(parent: Node, text: String, action: Callable, primary := false) -> Button:
	var node := Button.new()
	node.text = text
	node.alignment = HORIZONTAL_ALIGNMENT_LEFT
	node.custom_minimum_size = Vector2(96, UiLayoutMetrics.CONTROL_HEIGHT)
	node.autowrap_mode = TextServer.AUTOWRAP_OFF
	node.theme_type_variation = UiTheme.PRIMARY_BUTTON if primary else &""
	node.pressed.connect(action)
	parent.add_child(node)
	return node


static func scroll(parent: Node, title := "") -> VBoxContainer:
	var view := ScrollContainer.new()
	view.name = title.validate_node_name() if not title.is_empty() else "ContentScroll"
	view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	view.follow_focus = true
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(view)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", UiLayoutMetrics.GAP)
	view.add_child(column)
	if title in ["Navigation", "SessionSetup", "Milestones", "Topics", "QuestionIndex"]:
		view.set_meta(&"ui_region", "navigation")
	elif title == "ReferenceReading":
		view.set_meta(&"ui_region", "description")
	elif title == "SettingPreview":
		view.set_meta(&"ui_region", "preview")
	return column


static func section(parent: Node, title: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.set_meta(&"ui_region", "reading")
	column.add_theme_constant_override(&"separation", 16)
	parent.add_child(column)
	label(column, title, UiTheme.HEADING)
	column.add_child(HSeparator.new())
	return column


static func page(tabs: TabContainer, title: String) -> VBoxContainer:
	return scroll(tabs, title)


static func tabs(parent: Node) -> TabContainer:
	var node := TabContainer.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node


static func bare(panel: UiPanel, padding := 28) -> void:
	panel.accent_line = false
	var style := StyleBoxEmpty.new()
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	panel.add_theme_stylebox_override(&"panel", style)


static func header(parent: Node, category: String, title: String, close_action: Callable) -> void:
	label(parent, category, UiTheme.MUTED)
	var row := HBoxContainer.new()
	parent.add_child(row)
	var heading := label(row, title, UiTheme.TITLE)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(row, "Back", close_action)
	parent.add_child(HSeparator.new())


static func inset(parent: Node, content: Control, role: String) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.name = "SectionInset"
	frame.size_flags_horizontal = content.size_flags_horizontal
	frame.size_flags_vertical = content.size_flags_vertical if content.size_flags_vertical & Control.SIZE_EXPAND else Control.SIZE_SHRINK_BEGIN
	frame.size_flags_stretch_ratio = content.size_flags_stretch_ratio
	var padding := StyleBoxEmpty.new()
	padding.content_margin_left = UiLayoutMetrics.CONTENT_PADDING
	padding.content_margin_right = UiLayoutMetrics.CONTENT_PADDING
	padding.content_margin_top = UiLayoutMetrics.CONTENT_PADDING
	padding.content_margin_bottom = UiLayoutMetrics.CONTENT_PADDING
	frame.add_theme_stylebox_override(&"panel", padding)
	frame.set_meta(&"ui_region", role)
	content.remove_meta(&"ui_region")
	parent.add_child(frame)
	frame.add_child(content)
	return frame
