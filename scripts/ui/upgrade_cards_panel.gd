class_name UpgradeCardsPanel
extends UiPanel
## Upgrade cards for the colony's equipment (Prompt 08). Cards are grouped by sector with the sector's level (tier).
## Every card shows what it does, its measurable effect, where its numbers come from, and each requirement with ✓ or ✖
## in words: the sector level, each question, each piece of practical evidence, the parts, the installer and the
## install station. Cards that are ready are listed together per sector, so the players can choose.
## "Questions" opens a QuizPanel for the card. "Install" asks the host (`install_upgrade`); it is enabled only when the
## colony has everything and the right specialist stands at the card's install station.
## Opened from the colony computer and from the install stations; it only reads state and asks with services.request().

const DATA_PATH := ProgressionSystem.UPGRADES_PATH
## Sector id -> [symbol, words].
const SECTORS := {
	"energy": ["⚡", "Energy"],
	"life_support": ["✚", "Life support"],
	"food": ["❀", "Food"],
	"resources": ["⚙", "Resources and making things"],
	"science": ["✦", "Science"],
}
## Narrowest a card column may get, in pixels at UI scale 1.
const CARD_MIN_WIDTH := 300.0

## Station this panel was opened at (empty: the nearest station within reach is used).
var station_id: StringName = &""
## The cards, in file order (grouped by sector on screen in the same order).
var definitions: Array[UpgradeDefinition] = []
## Card id -> {"sector", "effect", "function"}.
var extras: Dictionary = {}
## The data file's note.
var note := ""
## Install button of each card, in card order.
var install_buttons: Array[Button] = []
## Questions button of each card by id.
var question_buttons: Dictionary = {}

var _built := false
var _scroll: ScrollContainer
var _grids: Dictionary = {}
var _parts_label: Label
var _where_label: Label
var _message: Label
var _cost_labels: Dictionary = {}
var _reason_labels: Dictionary = {}
var _req_labels: Dictionary = {}
var _sector_labels: Dictionary = {}
var _next_labels: Dictionary = {}
var _ready_labels: Dictionary = {}
var _close_button: Button
var _waiting: Dictionary = {}


## Reads the card file. Returns {"definitions": Array[UpgradeDefinition], "extras": Dictionary, "note": String}.
static func load_catalogue(_path := DATA_PATH) -> Dictionary:
	var defs: Array[UpgradeDefinition] = []
	var side := {}
	for d in ProgressionSystem.cards():
		defs.append(d)
		side[d.id] = {"sector": d.sector, "effect": d.effect, "function": d.function_text}
	return {"definitions": defs, "extras": side, "note": String(ProgressionSystem.catalogue().get("note", ""))}


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
	return "Needs %d parts — the colony has %d" % [def.cost_parts, _state().parts if _state() != null else 0]


## Every reason, in words, why `def` cannot be installed here and now. Empty when it can.
func locked_reasons(def: UpgradeDefinition) -> PackedStringArray:
	var out := PackedStringArray()
	var st := _state()
	if st == null:
		return out
	if ProgressionSystem.is_installed(st, def.id):
		out.append("Already installed.")
		return out
	for r in ProgressionSystem.missing(st, def):
		out.append(String(r.text) + ".")
	var me := services.local_character()
	if def.specialty != &"" and (me == null or me.specialty != def.specialty):
		out.append("Installed by the %s." % ProgressionSystem.installer_words(def))
	if install_station_here(def) == &"":
		out.append("Go to the %s to install it." % ProgressionSystem.install_place_words(def))
	return out


## True when the Install button of `def` is usable now.
func can_install(def: UpgradeDefinition) -> bool:
	return locked_reasons(def).is_empty()


## The install station of `def` within reach of the local crew member, or &"".
func install_station_here(def: UpgradeDefinition) -> StringName:
	var st := _state()
	for id in stations_in_reach():
		if ProgressionSystem.at_install_station(st, def, id):
			return id
	return &""


## Stations within reach of the local crew member, nearest first (the station the panel was opened at comes first).
func stations_in_reach() -> Array[StringName]:
	var out: Array[StringName] = []
	var st := _state()
	var me := services.local_character() if services != null else null
	if st == null or me == null:
		return out
	var reach := services.config.interact_distance_m
	var found: Array = []
	for id: String in st.stations:
		var d := me.position.distance_to(CharacterState._v3((st.stations[id] as Dictionary).get("position", [0, 0, 0])))
		if d <= reach:
			found.append([d if StringName(id) != station_id else -1.0, StringName(id)])
	found.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for f: Array in found:
		out.append(f[1])
	return out


## The cost label of card `id` (for tests).
func cost_label(id: StringName) -> Label:
	return _cost_labels.get(id) as Label


## The locked-reason label of card `id` (for tests).
func reason_label(id: StringName) -> Label:
	return _reason_labels.get(id) as Label


## The requirement lines of card `id` as shown ("✓ …" / "✖ …").
func requirement_lines(id: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	for l: Label in _req_labels.get(id, []):
		if l.visible:
			out.append(l.text)
	return out


## The "ready to choose" line of a sector.
func ready_text(sector: String) -> String:
	var l := _ready_labels.get(sector) as Label
	return l.text if l != null else ""


## The level line of a sector ("⚡ Energy · level 1 of 3").
func sector_text(sector: String) -> String:
	var l := _sector_labels.get(sector) as Label
	return l.text if l != null else ""


## The install button of card `id`.
func install_button(id: StringName) -> Button:
	for i in definitions.size():
		if definitions[i].id == id:
			return install_buttons[i]
	return null


func message_text() -> String:
	return _message.text if _message != null else ""


func refresh() -> void:
	if not _built or services == null or not services.has_game():
		return
	var st := _state()
	_parts_label.text = "⚙ The colony has %d spare parts." % st.parts
	_where_label.text = _where_text()
	for sector: String in SECTORS:
		var level := ProgressionSystem.tier(st, sector)
		(_sector_labels[sector] as Label).text = "%s %s · level %d of %d" % [SECTORS[sector][0], SECTORS[sector][1], level, ProgressionSystem.MAX_TIER]
		var next_rule := ProgressionSystem.tier_rule(sector, level + 1)
		var next := _next_labels[sector] as Label
		if next_rule.is_empty():
			next.text = "✓ Highest level reached."
		else:
			var parts := PackedStringArray()
			for line in ProgressionSystem.tier_rule_lines(st, next_rule):
				parts.append(("✓ " if bool(line.ok) else "✖ ") + String(line.text))
			next.text = "Next level %d: %s.\n%s" % [level + 1, String(next_rule.get("words", "")), "\n".join(parts)]
		var ready := PackedStringArray()
		for def in ProgressionSystem.cards_of(sector):
			if ProgressionSystem.is_eligible(st, def):
				ready.append(def.title)
		var rl := _ready_labels[sector] as Label
		if ready.is_empty():
			rl.text = "No card is ready yet in this sector."
			rl.theme_type_variation = UiTheme.MUTED
		else:
			rl.text = "★ Ready to choose: %s." % ", ".join(ready)
			rl.theme_type_variation = UiTheme.GOOD
	for i in definitions.size():
		_refresh_card(st, definitions[i], install_buttons[i])


func _refresh_card(st: ColonyState, def: UpgradeDefinition, install: Button) -> void:
	var lines: Array = _req_labels[def.id]
	var reqs := ProgressionSystem.requirements(st, def)
	var me := services.local_character()
	var installer_ok := def.specialty == &"" or (me != null and me.specialty == def.specialty)
	var here := install_station_here(def)
	var all: Array = []
	for r in reqs:
		all.append([bool(r.ok), String(r.text), String(r.kind)])
	all.append([installer_ok, "Installed by: %s%s" % [ProgressionSystem.installer_words(def), "" if installer_ok else " (switch crew member at the hub)"], "installer"])
	all.append([here != &"", "Install at: the %s%s" % [ProgressionSystem.install_place_words(def), "" if here != &"" else " (you are not there)"], "station"])
	for j in lines.size():
		var l := lines[j] as Label
		l.visible = j < all.size()
		if not l.visible:
			continue
		var ok := bool(all[j][0])
		l.text = ("✓ " if ok else "✖ ") + String(all[j][1])
		l.theme_type_variation = UiTheme.GOOD if ok else UiTheme.WARN
		if String(all[j][2]) == "parts":
			_cost_labels[def.id] = l
	var installed := ProgressionSystem.is_installed(st, def.id)
	var reasons := locked_reasons(def)
	var reason := _reason_labels[def.id] as Label
	if installed:
		reason.text = "✓ Installed. " + def.effect
		reason.theme_type_variation = UiTheme.GOOD
	elif reasons.is_empty():
		reason.text = "★ Ready: press Install."
		reason.theme_type_variation = UiTheme.GOOD
	elif ProgressionSystem.is_eligible(st, def):
		reason.text = "★ The colony is ready for this card. " + " ".join(reasons)
		reason.theme_type_variation = UiTheme.GOOD
	else:
		reason.text = "Locked: " + " ".join(reasons)
		reason.theme_type_variation = UiTheme.MUTED
	install.disabled = installed or not reasons.is_empty()
	install.text = "✓ Installed" if installed else ("Install" if reasons.is_empty() else "Install (locked)")
	install.tooltip_text = " ".join(reasons) if not reasons.is_empty() else ("Installed." if installed else "Install %s now." % def.title)
	var known := 0
	for q in def.questions:
		if ProgressionSystem.is_known(st, q):
			known += 1
	(question_buttons[def.id] as Button).text = "Questions (%d of %d)" % [known, def.questions.size()]


func _where_text() -> String:
	var st := _state()
	var here := stations_in_reach()
	var at := "You are not at a station."
	if not here.is_empty():
		at = "You are at the %s." % StationPanels.name_of(String((st.stations[String(here[0])] as Dictionary).get("kind", ""))).to_lower()
	return "%s Answer questions at the colony computer; install each card at its own station." % at


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
	intro.text = "Upgrades improve equipment the colony already has. Costs and effect sizes are game balance, not NASA numbers."
	intro.theme_type_variation = UiTheme.MUTED
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(intro)
	_parts_label = Label.new()
	_parts_label.theme_type_variation = UiTheme.HEADING
	column.add_child(_parts_label)
	_where_label = Label.new()
	_where_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_where_label)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(body)
	var by_sector := {}
	for def in definitions:
		if not by_sector.has(def.sector):
			by_sector[def.sector] = []
		(by_sector[def.sector] as Array).append(def)
	var ordered: Array[UpgradeDefinition] = []
	for sector: String in SECTORS:
		var section := VBoxContainer.new()
		section.name = "Sector_%s" % sector
		body.add_child(section)
		var head := HBoxContainer.new()
		section.add_child(head)
		var sl := _wrap_label("", UiTheme.HEADING)
		head.add_child(sl)
		_sector_labels[sector] = sl
		head.add_child(ExplainButton.make("specialists"))
		_next_labels[sector] = _wrap_label("", UiTheme.MUTED)
		section.add_child(_next_labels[sector])
		_ready_labels[sector] = _wrap_label("", UiTheme.MUTED)
		section.add_child(_ready_labels[sector])
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section.add_child(grid)
		_grids[sector] = grid
		for def: UpgradeDefinition in by_sector.get(sector, []):
			grid.add_child(_make_card(def))
			ordered.append(def)
	definitions = ordered
	_message = _wrap_label("", &"")
	_message.visible = false
	column.add_child(_message)
	_scroll.resized.connect(_fit_columns)
	_link_focus()


func _make_card(def: UpgradeDefinition) -> Control:
	var sector: Array = SECTORS.get(def.sector, ["●", "Other"])
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
	top.add_child(_wrap_label(def.title, UiTheme.HEADING))

	box.add_child(_wrap_label("%s · level %d card · %s" % [String(sector[1]), def.tier, def.zone], UiTheme.MUTED))
	box.add_child(_wrap_label("What it does: " + def.function_text, &""))
	box.add_child(_wrap_label("Effect: " + def.effect, &""))
	if not def.source_labels.is_empty():
		box.add_child(_wrap_label("Where the numbers come from: " + " ".join(def.source_labels), UiTheme.MUTED))
	box.add_child(_wrap_label("Needs:", UiTheme.HEADING))
	var lines: Array = []
	# tier + questions + evidence + prerequisites + parts + installer + station
	for i in 1 + def.questions.size() + def.evidence.size() + def.prerequisites.size() + 3:
		var l := _wrap_label("", UiTheme.MUTED)
		box.add_child(l)
		lines.append(l)
	_req_labels[def.id] = lines
	_cost_labels[def.id] = lines[1 + def.questions.size() + def.evidence.size() + def.prerequisites.size()]
	var reason := _wrap_label("", UiTheme.MUTED)
	box.add_child(reason)
	_reason_labels[def.id] = reason

	var row := HFlowContainer.new()
	box.add_child(row)
	var questions := Button.new()
	questions.name = "Questions"
	questions.text = "Questions"
	questions.focus_mode = Control.FOCUS_ALL
	questions.pressed.connect(_open_quiz.bind(def))
	row.add_child(questions)
	question_buttons[def.id] = questions
	var install := Button.new()
	install.name = "Install"
	install.text = "Install (locked)"
	install.disabled = true
	install.focus_mode = Control.FOCUS_ALL
	install.theme_type_variation = UiTheme.PRIMARY_BUTTON
	install.pressed.connect(_on_install_pressed.bind(def))
	row.add_child(install)
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
	var changed := false
	for grid: GridContainer in _grids.values():
		if grid.columns != cols:
			grid.columns = cols
			changed = true
	if changed:
		_link_focus()


## Arrow keys move between the Install buttons: left/right along a row, up/down along a column of a sector; Tab
## goes through every card in order.
func _link_focus() -> void:
	var n := install_buttons.size()
	var start := 0
	for sector: String in SECTORS:
		var grid := _grids.get(sector) as GridContainer
		var count := ProgressionSystem.cards_of(sector).size()
		var cols := maxi(1, grid.columns if grid != null else 1)
		for k in count:
			var i := start + k
			var b := install_buttons[i]
			var col := k % cols
			b.focus_neighbor_left = b.get_path_to(install_buttons[i - 1]) if col > 0 else NodePath("")
			b.focus_neighbor_right = b.get_path_to(install_buttons[i + 1]) if col < cols - 1 and k + 1 < count else NodePath("")
			b.focus_neighbor_top = b.get_path_to(install_buttons[i - cols]) if k - cols >= 0 else NodePath("")
			b.focus_neighbor_bottom = b.get_path_to(install_buttons[i + cols]) if k + cols < count else NodePath("")
		start += count
	for i in n:
		var b := install_buttons[i]
		b.focus_next = b.get_path_to(install_buttons[i + 1]) if i + 1 < n else NodePath("")
		b.focus_previous = b.get_path_to(install_buttons[i - 1]) if i > 0 else NodePath("")


# ---------------------------------------------------------------- actions

func _open_quiz(def: UpgradeDefinition) -> void:
	var quiz := QuizPanel.new()
	quiz.question_ids = def.questions.duplicate()
	quiz.heading = "Questions for “%s”" % def.title
	quiz.station_id = station_id
	if services != null:
		quiz.setup(services)
	open_requested.emit(quiz)


## Asks the host to install `def` at the install station the local crew member stands at.
func request_install(def: UpgradeDefinition) -> ActionResult:
	var target := install_station_here(def)
	var result := services.request(&"install_upgrade", target if target != &"" else def.install_station, {"upgrade_id": String(def.id)})
	if result.pending:
		_waiting[result.request_id] = true
		if not services.events.action_resolved.is_connected(_on_action_resolved):
			services.events.action_resolved.connect(_on_action_resolved)
		_show_message("Asked the host…", UiTheme.MUTED)
	else:
		_show_answer(result)
	return result


func _on_install_pressed(def: UpgradeDefinition) -> void:
	request_install(def)


func _on_action_resolved(result: ActionResult) -> void:
	if _waiting.has(result.request_id):
		_waiting.erase(result.request_id)
		_show_answer(result)


func _show_answer(result: ActionResult) -> void:
	if result.ok:
		_show_message("✓ " + StationPanel.answer_text(result), UiTheme.GOOD)
	else:
		_show_message("✖ " + result.message, UiTheme.URGENT)
	refresh()


func _show_message(text: String, variation: StringName) -> void:
	_message.text = text
	_message.theme_type_variation = variation
	_message.visible = not text.is_empty()


func _state() -> ColonyState:
	return services.state() if services != null and services.has_game() else null


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
	_scroll.custom_minimum_size = Vector2(minf(1100.0, screen.x * 0.7), minf(520.0, screen.y * 0.4))
