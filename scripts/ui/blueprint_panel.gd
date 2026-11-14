class_name BlueprintPanel
extends UiPanel
## The blueprint map (M key): a top-down plan of the colony with live markers, a legend that explains every symbol in
## words, zoom buttons, "Centre on me", and the name, power and load of the room you click.
## The 3D view stays visible around it.

## The drawn plan.
var view: BlueprintView
## Where the clicked room's name, power and load are shown.
var info_label: Label

var _built := false
var _legend_box: VBoxContainer
var _zoom_in: Button
var _zoom_out: Button
var _centre_button: Button
var _close_button: Button


func setup(p_services: GameServices) -> void:
	if _built:
		return
	super.setup(p_services)
	_built = true
	name = "Blueprint"
	keeps_world_visible = true
	theme_type_variation = UiTheme.PANEL
	_build()
	refresh()


func panel_title() -> String:
	return "Blueprint"


func first_focus() -> Control:
	return _centre_button


## Every legend line, joined by new lines (for tests and screen readers).
func legend_text() -> String:
	var lines := PackedStringArray()
	for child in _legend_box.get_children():
		if child is Label:
			lines.append((child as Label).text)
	return "\n".join(lines)


func refresh() -> void:
	if not _built:
		return
	view.queue_redraw()
	if not view.selected_zone.is_empty():
		info_label.text = zone_info(view.selected_zone)


## A plain description of a zone: its name, whether it has power, and how much it uses when on.
func zone_info(zone: String) -> String:
	if services == null or not services.has_game():
		return zone
	var st := services.state()
	var power_line := "✓ It has power." if st.is_zone_powered(zone) else "✖ It has no power."
	var title := zone if zone != ColonyZones.EXTERIOR else "Outside the base"
	var load_line := "It uses %s kW when it is on." % StationPanel.num(services.balance.load_of_zone(zone))
	if not st.zones.has(zone):
		return "%s\nNo power switch here." % title
	if zone == ColonyZones.EXTERIOR:
		load_line += " The 12 sun trackers out here make the colony's power (☀ on the map)."
	return "%s\n%s\n%s" % [title, power_line, load_line]


func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "Blueprint map"
	title.theme_type_variation = UiTheme.TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(ExplainButton.make("blueprint"))
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(_close_button)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	view = BlueprintView.new()
	view.name = "Plan"
	view.size_flags_stretch_ratio = 3.0
	view.setup(services)
	view.room_selected.connect(_on_room_selected)
	body.add_child(view)

	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_stretch_ratio = 1.2
	body.add_child(side)
	var zoom_row := HBoxContainer.new()
	side.add_child(zoom_row)
	_zoom_in = _button(zoom_row, "+ Zoom in", func() -> void: view.zoom_by(1.25))
	_zoom_out = _button(zoom_row, "− Zoom out", func() -> void: view.zoom_by(0.8))
	_centre_button = _button(side, "Centre on me", func() -> void: view.centre_on_me())

	var card := PanelContainer.new()
	card.theme_type_variation = UiTheme.CARD
	side.add_child(card)
	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.text = "Click a room to see its name, its power and how much it uses."
	card.add_child(info_label)

	var legend_title := Label.new()
	legend_title.text = "What the symbols mean"
	legend_title.theme_type_variation = UiTheme.HEADING
	side.add_child(legend_title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(scroll)
	_legend_box = VBoxContainer.new()
	_legend_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_legend_box)
	for entry: Array in BlueprintView.legend():
		var line := Label.new()
		line.text = "%s   %s" % [String(entry[0]), String(entry[1])]
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_legend_box.add_child(line)

	var hint := Label.new()
	hint.theme_type_variation = UiTheme.MUTED
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "Drag to move the map. Use the mouse wheel or the + and − keys to zoom. Press %s or %s to close." % [
		StationPanel._key_name(&"map", "M"), StationPanel._key_name(&"back", "Esc")]
	column.add_child(hint)


func _button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _on_room_selected(zone: String) -> void:
	info_label.text = zone_info(zone)


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		var vp := get_viewport()
		if vp != null and not vp.size_changed.is_connected(_fit_to_screen):
			vp.size_changed.connect(_fit_to_screen)
		_fit_to_screen()
	elif what == NOTIFICATION_EXIT_TREE:
		var vp := get_viewport()
		if vp != null and vp.size_changed.is_connected(_fit_to_screen):
			vp.size_changed.disconnect(_fit_to_screen)


## Gives the map a size that suits the screen, so the panel is never tiny and never too big.
func _fit_to_screen() -> void:
	if view == null or not is_inside_tree():
		return
	var screen := get_viewport_rect().size
	view.custom_minimum_size = Vector2(minf(820.0, screen.x * 0.5), minf(520.0, screen.y * 0.55))
