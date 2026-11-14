class_name UpgradeCardsPanel
extends UiPanel
## Upgrade cards for the colony's facilities. Upgrades are built in a later milestone, so this panel only shows the
## cards: what each one changes, what it costs in parts against the parts the colony has, who installs it, and why it
## is locked. The install button is there but disabled, with the reason.
## Cards come from res://data/upgrades.json (placeholder cards) and load into UpgradeDefinition resources; fields that
## UpgradeDefinition does not have (sector, effect, question) are kept in `extras`.

const DATA_PATH := "res://data/upgrades.json"
## Sector id -> [symbol, words].
const SECTORS := {
	"health_life_support": ["✚", "Health and life support"],
	"food_production": ["❀", "Food production"],
	"resources_manufacturing": ["⚙", "Resources and making things"],
	"energy": ["⚡", "Energy"],
	"science_research": ["✦", "Science and research"],
}
## Why every card is locked in this milestone.
const LATER_REASON := "Upgrades are installed in a later update."
## Narrowest a card column may get, in pixels at UI scale 1.
const CARD_MIN_WIDTH := 300.0

## The cards, in file order.
var definitions: Array[UpgradeDefinition] = []
## Card id -> {"sector", "effect", "question", "placeholder"}: the fields UpgradeDefinition does not hold.
var extras: Dictionary = {}
## The data file's note (says the cards are placeholders).
var note := ""
## Install button of each card, in card order.
var install_buttons: Array[Button] = []

var _built := false
var _scroll: ScrollContainer
var _grid: GridContainer
var _parts_label: Label
var _cost_labels: Dictionary = {}
var _reason_labels: Dictionary = {}
var _close_button: Button


## Reads the card file. Returns {"definitions": Array[UpgradeDefinition], "extras": Dictionary, "note": String}.
static func load_catalogue(path := DATA_PATH) -> Dictionary:
	var defs: Array[UpgradeDefinition] = []
	var side := {}
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not data is Dictionary:
		push_warning("Upgrade cards could not be read from %s." % path)
		return {"definitions": defs, "extras": side, "note": ""}
	for card: Dictionary in (data as Dictionary).get("cards", []):
		var d := UpgradeDefinition.new()
		d.id = StringName(String(card.get("id", "")))
		d.title = String(card.get("title", ""))
		d.zone = String(card.get("zone", ""))
		d.tier = int(card.get("tier", 1))
		d.cost_parts = int(card.get("cost_parts", 0))
		for p in card.get("prerequisites", []):
			d.prerequisites.append(StringName(String(p)))
		d.specialty = StringName(String(card.get("specialty", "")))
		defs.append(d)
		side[d.id] = {"sector": String(card.get("sector", "")), "effect": String(card.get("effect", "")),
			"question": String(card.get("question", "")), "placeholder": bool(card.get("placeholder", true))}
	return {"definitions": defs, "extras": side, "note": String((data as Dictionary).get("note", ""))}


func setup(p_services: GameServices) -> void:
	if _built:
		return
	super.setup(p_services)
	_built = true
	name = "UpgradeCards"
	theme_type_variation = UiTheme.PANEL
	var cat := load_catalogue()
	definitions = cat["definitions"]
	extras = cat["extras"]
	note = cat["note"]
	_build()
	refresh()


func panel_title() -> String:
	return "Upgrades"


func first_focus() -> Control:
	return install_buttons[0] if not install_buttons.is_empty() else _close_button


## "Needs 4 parts — the colony has 10".
func cost_text(def: UpgradeDefinition) -> String:
	return "Needs %d parts — the colony has %d" % [def.cost_parts, _parts()]


## Every reason, in words, why `def` cannot be installed now. The last one is always LATER_REASON.
func locked_reasons(def: UpgradeDefinition) -> PackedStringArray:
	var out := PackedStringArray()
	if def.cost_parts > _parts():
		out.append("Not enough parts yet.")
	var missing := PackedStringArray()
	for p in def.prerequisites:
		if not _is_built(p):
			missing.append(_title_of(p))
	if not missing.is_empty():
		out.append("First needs: %s." % ", ".join(missing))
	out.append(LATER_REASON)
	return out


## The cost label of card `id` (for tests).
func cost_label(id: StringName) -> Label:
	return _cost_labels.get(id) as Label


## The locked-reason label of card `id` (for tests).
func reason_label(id: StringName) -> Label:
	return _reason_labels.get(id) as Label


func refresh() -> void:
	if not _built or services == null or not services.has_game():
		return
	_parts_label.text = "⚙ The colony has %d spare parts." % _parts()
	for i in definitions.size():
		var def := definitions[i]
		var cost := _cost_labels[def.id] as Label
		if def.cost_parts <= _parts():
			cost.text = "✓ " + cost_text(def)
			cost.theme_type_variation = UiTheme.GOOD
		else:
			cost.text = "! " + cost_text(def)
			cost.theme_type_variation = UiTheme.WARN
		var reasons := locked_reasons(def)
		(_reason_labels[def.id] as Label).text = "Locked: " + " ".join(reasons)
		install_buttons[i].tooltip_text = " ".join(reasons)


# ---------------------------------------------------------------- building

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
	title.text = "Upgrade cards"
	title.theme_type_variation = UiTheme.TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(ExplainButton.make("upgrades"))
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(_close_button)

	var intro := Label.new()
	intro.text = "An upgrade improves a room's equipment. These are example cards: the real upgrades come in a later update. Costs are game balance, not real numbers."
	intro.theme_type_variation = UiTheme.MUTED
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(intro)
	_parts_label = Label.new()
	_parts_label.theme_type_variation = UiTheme.HEADING
	column.add_child(_parts_label)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)
	for def in definitions:
		_grid.add_child(_make_card(def))
	_scroll.resized.connect(_fit_columns)
	_link_focus()


func _make_card(def: UpgradeDefinition) -> Control:
	var extra: Dictionary = extras.get(def.id, {})
	var sector: Array = SECTORS.get(String(extra.get("sector", "")), ["●", "Other"])
	var card := PanelContainer.new()
	card.name = "Card_%s" % def.id
	card.theme_type_variation = UiTheme.CARD
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	card.add_child(box)

	var top := HBoxContainer.new()
	box.add_child(top)
	var symbol := Label.new()
	symbol.text = String(sector[0])
	symbol.theme_type_variation = UiTheme.HEADING
	top.add_child(symbol)
	var title := _wrap_label(def.title, UiTheme.HEADING)
	top.add_child(title)

	box.add_child(_wrap_label("%s · %s · level %d" % [String(sector[1]), def.zone, def.tier], UiTheme.MUTED))
	box.add_child(_wrap_label("What it changes: " + String(extra.get("effect", "")), &""))
	if not String(extra.get("question", "")).is_empty():
		box.add_child(_wrap_label("Question to explore: " + String(extra.get("question", "")), UiTheme.MUTED))
	var installer := "Anyone can install it."
	if def.specialty != &"":
		installer = "Installed by: %s %s specialist" % [String(StationPanels.SPECIALTY_SYMBOLS.get(def.specialty, "●")),
			String(StationPanels.SPECIALTY_WORDS.get(def.specialty, String(def.specialty)))]
	box.add_child(_wrap_label(installer, &""))
	var cost := _wrap_label("", UiTheme.GOOD)
	box.add_child(cost)
	_cost_labels[def.id] = cost
	var reason := _wrap_label("", UiTheme.MUTED)
	box.add_child(reason)
	_reason_labels[def.id] = reason
	if bool(extra.get("placeholder", true)):
		box.add_child(_wrap_label("Example card (placeholder)", UiTheme.MUTED))

	var install := Button.new()
	install.name = "Install"
	install.text = "Install (locked)"
	install.disabled = true
	install.focus_mode = Control.FOCUS_ALL
	install.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(install)
	install_buttons.append(install)
	return card


func _wrap_label(text: String, variation: StringName) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != &"":
		l.theme_type_variation = variation
	return l


## Picks how many card columns fit the space, then links arrow-key focus between the cards.
func _fit_columns() -> void:
	var text_scale := maxf(1.0, float(get_theme_default_font_size()) / float(UiTheme.BASE_FONT_SIZE))
	var cols := clampi(int(_scroll.size.x / (CARD_MIN_WIDTH * text_scale)), 1, 4)
	if cols != _grid.columns:
		_grid.columns = cols
		_link_focus()


## Arrow keys move between cards in grid order: left/right along a row, up/down along a column.
func _link_focus() -> void:
	var n := install_buttons.size()
	var cols := maxi(1, _grid.columns)
	for i in n:
		var b := install_buttons[i]
		var col := i % cols
		b.focus_neighbor_left = b.get_path_to(install_buttons[i - 1]) if col > 0 else NodePath("")
		b.focus_neighbor_right = b.get_path_to(install_buttons[i + 1]) if col < cols - 1 and i + 1 < n else NodePath("")
		b.focus_neighbor_top = b.get_path_to(install_buttons[i - cols]) if i - cols >= 0 else NodePath("")
		b.focus_neighbor_bottom = b.get_path_to(install_buttons[i + cols]) if i + cols < n else NodePath("")
		b.focus_next = b.get_path_to(install_buttons[i + 1]) if i + 1 < n else NodePath("")
		b.focus_previous = b.get_path_to(install_buttons[i - 1]) if i > 0 else NodePath("")


func _parts() -> int:
	return services.state().parts if services != null and services.has_game() else 0


func _is_built(id: StringName) -> bool:
	if services == null or not services.has_game():
		return false
	var u: Variant = services.state().upgrades.get(String(id), services.state().upgrades.get(id, null))
	return u != null and not (u is bool and not bool(u))


func _title_of(id: StringName) -> String:
	for d in definitions:
		if d.id == id:
			return d.title
	return String(id)


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


func _fit_to_screen() -> void:
	if _scroll == null or not is_inside_tree():
		return
	var screen := get_viewport_rect().size
	_scroll.custom_minimum_size = Vector2(minf(1100.0, screen.x * 0.7), minf(520.0, screen.y * 0.5))
