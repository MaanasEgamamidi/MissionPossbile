class_name BlueprintPanel
extends UiPanel
## The blueprint map (the colony computer's "Blueprint map" button; owner 2026-11-14: the M key no longer opens it, the
## big goals screen (J) has the map now): a top-down plan of the colony with live markers, a legend that explains every symbol in
## words, zoom buttons, "Centre on me", and the name, power and load of the room you click.
## The 3D view stays visible around it.

## The drawn plan.
var view: BlueprintView
## Where the clicked room's name, power and load are shown.
var info_label: Label

var _built := false
var _search: LineEdit
var _locations: ItemList
var _location_records: Array[Dictionary] = []
var _location_signature := ""
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
	keeps_world_visible = false
	max_width = 2200
	max_height = 1200
	accent_line = false
	theme_type_variation = UiTheme.PANEL
	_build()
	refresh()


func panel_title() -> String:
	return "Surface navigation"


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
	_refresh_locations()
	if view.selected_location.is_empty() and not view.selected_zone.is_empty():
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
	view.size_flags_stretch_ratio = 3.5
	view.setup(services)
	view.room_selected.connect(_on_room_selected)
	view.location_selected.connect(_on_location_selected)
	body.add_child(view)

	var side := UiComposition.scroll(body, "Navigation")
	(side.get_parent() as Control).size_flags_stretch_ratio = 1.05
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 20)
	var zoom_row := HBoxContainer.new()
	side.add_child(zoom_row)
	_zoom_in = _button(zoom_row, "+", func() -> void: view.zoom_by(1.25))
	_zoom_in.tooltip_text = "Zoom in at map centre"
	_zoom_out = _button(zoom_row, "−", func() -> void: view.zoom_by(0.8))
	_zoom_out.tooltip_text = "Zoom out at map centre"
	_centre_button = _button(zoom_row, "Locate me", func() -> void: view.centre_on_me())
	var layers := MenuButton.new()
	layers.text = "Layers"
	side.add_child(layers)
	var popup := layers.get_popup()
	for entry: Array in [["Locations", true], ["Crew", true], ["Structure outlines", false], ["Height contours · 1 m", false]]:
		popup.add_check_item(String(entry[0]))
		popup.set_item_checked(popup.item_count - 1, bool(entry[1]))
	popup.hide_on_checkable_item_selection = false
	popup.id_pressed.connect(func(id: int) -> void:
		popup.set_item_checked(id, not popup.is_item_checked(id))
		view.show_locations = popup.is_item_checked(0)
		view.show_crew = popup.is_item_checked(1)
		view.show_structures = popup.is_item_checked(2)
		view.show_contours = popup.is_item_checked(3)
		view.queue_redraw())
	var card := PanelContainer.new()
	card.theme_type_variation = UiTheme.CARD
	side.add_child(card)
	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.text = "Colony · local grid\nSelect a station or room to inspect.\nNorth up · distances in metres"
	card.add_child(info_label)

	var pages := TabContainer.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.custom_minimum_size.y = 280
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(pages)
	var index := VBoxContainer.new()
	index.name = "Locations"
	pages.add_child(index)
	_search = LineEdit.new()
	_search.placeholder_text = "Find a station or room…"
	_search.text_changed.connect(func(_text: String) -> void: _refresh_locations(true))
	index.add_child(_search)
	_locations = ItemList.new()
	_locations.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_locations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_locations.clip_contents = true
	_locations.custom_minimum_size = Vector2(0, 150)
	_locations.item_selected.connect(func(i: int) -> void: view.focus_location(_location_records[i]))
	index.add_child(_locations)
	var scroll := ScrollContainer.new()
	scroll.name = "Map key"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pages.add_child(scroll)
	_legend_box = VBoxContainer.new()
	_legend_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_legend_box)
	for entry: Array in BlueprintView.legend():
		var line := Label.new()
		line.text = "%s   %s" % [String(entry[0]), String(entry[1])]
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_legend_box.add_child(line)
	UiComposition.label(_legend_box, "Select a numbered group to zoom in. Contours show local navigation heights, not planetary elevations.", UiTheme.MUTED)
	var hint := Label.new()
	hint.theme_type_variation = UiTheme.MUTED
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Owner 2026-11-14: M no longer opens or closes this map.
	hint.text = "Drag to move the map. Use the mouse wheel or the + and − keys to zoom. Press %s to close." % StationPanel._key_name(&"back", "Esc")
	column.add_child(hint)


func _button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(44, 44)
	b.text = text
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _on_room_selected(zone: String) -> void:
	if _locations != null: _locations.deselect_all()
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
	view.custom_minimum_size = Vector2(minf(820.0, screen.x * 0.5), minf(520.0, screen.y * 0.48))


func _refresh_locations(force := false) -> void:
	if _locations == null: return
	var all := view.locations()
	var signature := str(all)
	if not force and signature == _location_signature: return
	_location_signature = signature
	var selected := view.selected_location
	_locations.clear()
	_location_records.clear()
	var query := _search.text.strip_edges().to_lower()
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name) + String(a.id) < String(b.name) + String(b.id))
	for location: Dictionary in all:
		var text := "%s · %s" % [location.name, location.zone]
		if not query.is_empty() and not (text + String(location.id)).to_lower().contains(query): continue
		_location_records.append(location)
		_locations.add_item(text)
		_locations.set_item_tooltip(_locations.item_count - 1, "%s\n%s" % [text, location.id])
		if String(location.id) == selected: _locations.select(_locations.item_count - 1)

func _on_location_selected(location: Dictionary) -> void:
	for i in _location_records.size():
		if String(_location_records[i].id) == String(location.id): _locations.select(i)
	var p: Vector2 = location.position
	var distance := ""
	var me := services.local_character()
	if me != null:
		distance = "\n%.1f m · straight-line distance" % snappedf(BlueprintView.godot_to_plan(me.position).distance_to(p), 0.1)
	info_label.text = "%s\n%s\nLOCAL X %0.1f / Z %0.1f m%s\n%s" % [String(location.name).to_upper(), location.id, p.x, -p.y, distance, zone_info(String(location.zone))]
