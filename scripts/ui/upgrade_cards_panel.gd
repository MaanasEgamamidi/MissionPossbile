class_name UpgradeCardsPanel
extends UiPanel
## Upgrade cards for the colony's equipment (Prompt 08; simplified in the UI overhaul, 2026-11-15).
## Cards are grouped by sector; a sector shows its picture, its name and its level as pips.
## A card shows at a glance: the sector's picture, the upgrade's name, ONE line of what it gives, its cost in parts
## against what the colony has, the badge of the specialist who installs it, and ONE state:
##   ready    "Ready!" over a big primary "Upgrade" button (the only filled button on the screen),
##   not yet  the single most important missing thing (a picture and at most six words) over a locked button,
##   done     a ticked "Installed" button.
## Everything else is one press away and off by default: "More" on a card (what it does, the effect with its numbers,
## where the numbers come from, every requirement with ✓ or ✖), "Next level" on a sector (what the next level needs,
## which cards are ready) and "?" in the header (what upgrades are, where you stand).
## "Questions" opens a QuizPanel for the card. "Upgrade" asks the host (`install_upgrade`); it is enabled only when the
## colony has everything and the right specialist stands at the card's install station.
## Opened from the colony computer and from the install stations; it only reads state and asks with services.request().

const MenuKit := preload("res://scripts/ui/menu_kit.gd")
const HudKit := preload("res://scripts/ui/hud/hud_kit.gd")
const GoalArt := preload("res://scripts/ui/hud/goal_art.gd")

const DATA_PATH := ProgressionSystem.UPGRADES_PATH
## Sector id -> [symbol, words].
const SECTORS := {
	"energy": ["⚡", "Energy"],
	"life_support": ["✚", "Life support"],
	"food": ["❀", "Food"],
	"resources": ["⚙", "Resources and making things"],
	"science": ["✦", "Science"],
}
## Card id -> the ONE line of what it gives (six words or fewer). A card without a line here shows the first sentence
## of its effect, cut short.
const GIVES := {
	&"energy_battery_reserve": "Bigger battery for long nights",
	&"energy_solar_tracking": "Panels make 10 % more power",
	&"energy_cleaner_automation": "The panel cleaner fixes itself",
	&"ls_water_reliability": "Cleans more water every hour",
	&"ls_electrolysis": "Up to 50 % more oxygen",
	&"ls_co2_processing": "More oxygen, needs no water",
	&"ls_oxygen_monitoring": "Earlier warnings about the air",
	&"food_irrigation_reliability": "Plant beds never dry out",
	&"food_nutrient_metering": "Plant food stays just right",
	&"food_scheduled_care": "Lights and water run themselves",
	&"res_salvage_inspection": "Shows every part that fits",
	&"res_component_refurbishment": "Faster fixing, one more part",
	&"res_repeat_assembly": "No second test for known parts",
	&"sci_instrument_calibration": "Lab results are more exact",
	&"sci_sample_comparison": "A second sample to compare",
	&"sci_evidence_settings": "Use lab results on the settings",
	&"comms_radio_1": "Radio works again: 30 s wait",
	&"comms_radio_2": "Radio wait drops to 15 s",
	&"comms_radio_3": "Radio wait drops to 5 s",
	&"comms_radio_4": "The radio talks almost at once",
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
## Upgrade button of each card, in card order.
var install_buttons: Array[Button] = []
## Questions button of each card by id.
var question_buttons: Dictionary = {}
## "More" switch of each card by id.
var more_buttons: Dictionary = {}

var _built := false
var _scroll: ScrollContainer
var _grids: Dictionary = {}
var _parts_label: Label
var _where_label: Label
var _message: Label
var _help_button: Button
var _help_box: Control
var _cost_labels: Dictionary = {}
var _reason_labels: Dictionary = {}
var _req_labels: Dictionary = {}
var _sector_texts: Dictionary = {}
var _sector_ui: Dictionary = {}          # sector -> {"level": Label, "pips": Control, "chip": Label, "toggle": Button, "box": Control}
var _next_labels: Dictionary = {}
var _ready_labels: Dictionary = {}
var _cards: Dictionary = {}              # card id -> {"cost_row", "cost", "have", "state_row", "state_icon", "more", "look"}
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


## The ONE line of what a card gives ("Bigger battery for long nights").
static func gives_text(def: UpgradeDefinition) -> String:
	if GIVES.has(def.id):
		return String(GIVES[def.id])
	return HudKit.short_line(def.effect, 7)


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


## The single most important thing `def` still waits for, as a picture and at most six words:
## {"kind": "question" | "tier" | "evidence" | "prerequisite" | "parts" | "who" | "where", "icon": MenuKit picture,
## "text": String}. Empty when nothing is missing (or the card is installed). The order is what a player can act on
## first: the card's own questions, the sector level, things to do, parts, then who installs it and where.
func short_reason(def: UpgradeDefinition) -> Dictionary:
	var st := _state()
	if st == null or ProgressionSystem.is_installed(st, def.id):
		return {}
	var open_questions := 0
	for q in def.questions:
		if not ProgressionSystem.is_known(st, q):
			open_questions += 1
	if open_questions > 0:
		return {"kind": "question", "icon": &"bubble", "text": "Answer 1 question" if open_questions == 1 else "Answer %d questions" % open_questions}
	var tasks := 0
	var first := {}
	for r in ProgressionSystem.missing(st, def):
		var kind := String(r.kind)
		if kind == "evidence":
			tasks += 1
		if first.is_empty():
			first = r
	if not first.is_empty():
		match String(first.kind):
			"tier":
				return {"kind": "tier", "icon": &"up", "text": "Reach %s level %d" % [_short_sector(def.sector), def.tier]}
			"evidence":
				return {"kind": "evidence", "icon": &"pick", "text": "Do 1 task first" if tasks == 1 else "Do %d tasks first" % tasks}
			"prerequisite":
				var other := ProgressionSystem.card(StringName(String(first.id)))
				return {"kind": "prerequisite", "icon": &"lock", "text": "First: %s" % (other.title if other != null else String(first.id))}
			"parts":
				var short := def.cost_parts - st.parts
				return {"kind": "parts", "icon": &"gear", "text": "Need 1 more part" if short == 1 else "Need %d more parts" % short}
			_:
				return {"kind": String(first.kind), "icon": &"lock", "text": HudKit.short_line(String(first.text), 6)}
	var me := services.local_character()
	if def.specialty != &"" and (me == null or me.specialty != def.specialty):
		return {"kind": "who", "icon": &"crew", "text": "Needs the %s specialist" % String(StationPanels.SPECIALTY_WORDS.get(def.specialty, String(def.specialty)))}
	if install_station_here(def) == &"":
		return {"kind": "where", "icon": &"join", "text": "Go to the %s" % _short_place(def)}
	return {}


## True when the Upgrade button of `def` is usable now.
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


## The parts line of card `id` in its requirement list ("✓ Needs 2 parts — the colony has 10"), for tests.
func cost_label(id: StringName) -> Label:
	return _cost_labels.get(id) as Label


## The state line of card `id`: the one thing it waits for ("Answer 2 questions"), "Ready!", or empty once installed.
func reason_label(id: StringName) -> Label:
	return _reason_labels.get(id) as Label


## The ONE state of card `id`: &"done", &"ready", &"go" (the colony has everything; the right specialist has to stand
## at its station) or &"wait" (the colony still misses something).
func card_state(id: StringName) -> StringName:
	return StringName(String((_cards.get(id, {}) as Dictionary).get("look", "")).get_slice("|", 0))


## The cost shown on the face of card `id` ("3 parts · ✓ have 7").
func cost_chip_text(id: StringName) -> String:
	var ui: Dictionary = _cards.get(id, {})
	if ui.is_empty():
		return ""
	return "%s · %s" % [(ui.cost as Label).text, (ui.have as Label).text]


## The requirement lines of card `id` as listed under "More" ("✓ …" / "✖ …").
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


## The level of a sector in words ("⚡ Energy · level 1 of 3"); on screen it is the sector's name and its pips.
func sector_text(sector: String) -> String:
	return String(_sector_texts.get(sector, ""))


## The Upgrade button of card `id`.
func install_button(id: StringName) -> Button:
	for i in definitions.size():
		if definitions[i].id == id:
			return install_buttons[i]
	return null


func message_text() -> String:
	return _message.text if _message != null else ""


## Opens or closes the "More" part of card `id` (as its switch does).
func set_more_open(id: StringName, open: bool) -> void:
	var b := more_buttons.get(id) as Button
	if b != null:
		b.button_pressed = open


func is_more_open(id: StringName) -> bool:
	var ui: Dictionary = _cards.get(id, {})
	return not ui.is_empty() and (ui.more as Control).visible


## Opens or closes the "Next level" part of a sector (as its switch does).
func set_sector_open(sector: String, open: bool) -> void:
	var ui: Dictionary = _sector_ui.get(sector, {})
	if not ui.is_empty():
		(ui.toggle as Button).button_pressed = open


## Opens or closes the "?" box under the header (as the "?" switch does).
func set_help_open(open: bool) -> void:
	if _help_button != null:
		_help_button.button_pressed = open


func refresh() -> void:
	if not _built or services == null or not services.has_game():
		return
	var st := _state()
	_parts_label.text = "1 part" if st.parts == 1 else "%d parts" % st.parts
	_where_label.text = _where_text()
	for sector: String in SECTORS:
		var level := ProgressionSystem.tier(st, sector)
		_sector_texts[sector] = "%s %s · level %d of %d" % [SECTORS[sector][0], SECTORS[sector][1], level, ProgressionSystem.MAX_TIER]
		var ui: Dictionary = _sector_ui[sector]
		(ui.level as Label).text = "Level %d" % level
		var pips := ui.pips as Control
		if int(pips.get(&"have")) != level:
			pips.set(&"have", level)
			pips.queue_redraw()
		HudKit.say(pips, "Level %d of %d" % [level, ProgressionSystem.MAX_TIER])
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
		var chip := ui.chip as Label
		chip.visible = not ready.is_empty()
		chip.text = "★ %d ready" % ready.size()
		if ready.is_empty():
			rl.text = "No card is ready yet in this sector."
			rl.theme_type_variation = UiTheme.MUTED
		else:
			rl.text = "★ Ready to choose: %s." % ", ".join(ready)
			rl.theme_type_variation = UiTheme.GOOD
	for i in definitions.size():
		_refresh_card(st, definitions[i], install_buttons[i])


func _refresh_card(st: ColonyState, def: UpgradeDefinition, install: Button) -> void:
	# ---- the full list, under "More"
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

	# ---- the face of the card: cost, one state, one obvious button
	var ui: Dictionary = _cards[def.id]
	var installed := ProgressionSystem.is_installed(st, def.id)
	var reasons := locked_reasons(def)
	var why := short_reason(def)
	var eligible := ProgressionSystem.is_eligible(st, def)
	var state := "done" if installed else ("ready" if reasons.is_empty() else ("go" if eligible else "wait"))
	var enough := st.parts >= def.cost_parts
	(ui.cost_row as Control).visible = not installed
	(ui.cost as Label).text = "1 part" if def.cost_parts == 1 else "%d parts" % def.cost_parts
	var have := ui.have as Label
	have.text = ("✓ have %d" if enough else "! have %d") % st.parts
	have.theme_type_variation = UiTheme.GOOD if enough else UiTheme.WARN
	var reason := _reason_labels[def.id] as Label
	reason.text = "Ready!" if state == "ready" else String(why.get("text", ""))
	reason.theme_type_variation = UiTheme.GOOD if state in ["go", "ready"] else &""
	(ui.state_row as Control).visible = not reason.text.is_empty()
	var known := 0
	for q in def.questions:
		if ProgressionSystem.is_known(st, q):
			known += 1
	var questions := question_buttons[def.id] as Button
	questions.text = "Questions %d/%d" % [known, def.questions.size()]
	questions.tooltip_text = "Answer this card's questions (%d of %d answered)." % [known, def.questions.size()]
	install.disabled = installed or not reasons.is_empty()
	install.text = "Installed" if installed else "Upgrade"
	install.tooltip_text = " ".join(reasons) if not reasons.is_empty() else ("Installed." if installed else "Install %s now." % def.title)
	# pictures and button looks change only when the state does (refresh runs four times a second)
	var look := "%s|%s|%s" % [state, String(why.get("kind", "")), known == def.questions.size()]
	if String(ui.get("look", "")) == look:
		return
	ui["look"] = look
	var px := 22.0 * UiTheme.text_scale()
	if state == "ready":
		(ui.state_icon as TextureRect).texture = MenuKit.pic(&"star", px, &"good")
	elif not why.is_empty():
		(ui.state_icon as TextureRect).texture = MenuKit.pic(why.icon, px, &"good" if state == "go" else &"text")
	install.theme_type_variation = UiTheme.PRIMARY_BUTTON if state == "ready" else &""
	match state:
		"done":
			install.icon = MenuKit.pic(&"check", px, &"good")
		"ready":
			install.icon = MenuKit.pic(&"up", px, &"primary_text")
		_:
			install.icon = MenuKit.pic(&"lock", px, &"text_disabled")
	# the filled button is kept for "Upgrade"; the questions button carries the same picture as its state line
	questions.icon = MenuKit.pic(&"check" if known == def.questions.size() else &"bubble", px, &"good" if known == def.questions.size() else &"text")


func _where_text() -> String:
	var st := _state()
	var here := stations_in_reach()
	var at := "You are not at a station."
	if not here.is_empty():
		at = "You are at the %s." % StationPanels.name_of(String((st.stations[String(here[0])] as Dictionary).get("kind", ""))).to_lower()
	return "%s Answer questions at the colony computer; install each card at its own station." % at


## The sector's name for a short line ("Resources" for "Resources and making things").
static func _short_sector(sector: String) -> String:
	return ProgressionSystem.sector_name(sector).get_slice(" and ", 0)


## The install station in two or three words ("power panel").
static func _short_place(def: UpgradeDefinition) -> String:
	if def.install_kind != "":
		return StationPanels.name_of(def.install_kind).to_lower()
	return def.zone if def.zone != "" else String(def.install_station)


## The picture and colour of a sector (the HUD's own pictures and colours); `id` picks the radio for the radio cards.
static func _art(sector: String, id: StringName = &"") -> Array:
	if String(id).begins_with("comms_"):
		return [&"radio", AstraStyle.ACCENT]
	match sector:
		"energy":
			return [&"power", AstraStyle.C_POWER]
		"life_support":
			return [&"air", AstraStyle.C_O2]
		"food":
			return [&"food", AstraStyle.C_FOOD]
		"resources":
			return [&"build", AstraStyle.C_PARTS]
		"science":
			return [&"science", AstraStyle.C_SCIENCE]
	return [&"dot", AstraStyle.TEXT_2]


# ---------------------------------------------------------------- building

func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override(&"separation", 12)
	column.add_child(header)
	var title := Label.new()
	title.text = "Upgrades"
	title.theme_type_variation = UiTheme.TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var chip := PanelContainer.new()
	chip.name = "Parts"
	chip.theme_type_variation = UiTheme.CHIP
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	HudKit.say(chip, "Spare parts the colony has. Upgrades cost parts.")
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override(&"separation", 8)
	chip.add_child(chip_row)
	chip_row.add_child(MenuKit.picture(&"gear", 24.0 * UiTheme.text_scale(), &"heading"))
	_parts_label = Label.new()
	_parts_label.theme_type_variation = UiTheme.HEADING
	chip_row.add_child(_parts_label)
	header.add_child(chip)
	_help_button = Button.new()
	_help_button.name = "Help"
	_help_button.text = "?"
	_help_button.toggle_mode = true
	_help_button.tooltip_text = "What are upgrades?"
	_help_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_help_button.toggled.connect(_on_help_toggled)
	header.add_child(_help_button)
	_close_button = Button.new()
	_close_button.name = "Close"
	_close_button.text = "Close"
	_close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close_button.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(_close_button)

	var help := PanelContainer.new()
	help.name = "HelpBox"
	help.theme_type_variation = UiTheme.CARD
	help.visible = false
	_help_box = help
	var help_col := VBoxContainer.new()
	help.add_child(help_col)
	help_col.add_child(_wrap_label("Upgrades improve equipment the colony already has. Costs and effect sizes are game balance, not NASA numbers.", &""))
	_where_label = _wrap_label("", UiTheme.MUTED)
	help_col.add_child(_where_label)
	var help_row := HFlowContainer.new()
	help_col.add_child(help_row)
	for pair: Array in [["upgrades", "About upgrades"], ["specialists", "About specialists"]]:
		var explain := ExplainButton.make(pair[0])
		explain.text = pair[1]
		help_row.add_child(explain)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	column.add_child(_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 14)
	_scroll.add_child(body)
	body.add_child(help)                 # first in the scrolling part, so the panel never grows taller than the screen
	var by_sector := {}
	for def in definitions:
		if not by_sector.has(def.sector):
			by_sector[def.sector] = []
		(by_sector[def.sector] as Array).append(def)
	var ordered: Array[UpgradeDefinition] = []
	for sector: String in SECTORS:
		var section := VBoxContainer.new()
		section.name = "Sector_%s" % sector
		section.add_theme_constant_override(&"separation", 8)
		body.add_child(section)
		section.add_child(_make_sector_head(sector))
		section.add_child((_sector_ui[sector] as Dictionary).box)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override(&"h_separation", 10)
		grid.add_theme_constant_override(&"v_separation", 10)
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


## A sector's heading: picture, name, level pips, "n ready" and the "Next level" switch. The box that switch opens is
## kept in _sector_ui[sector].box; the caller adds it under the heading.
func _make_sector_head(sector: String) -> Control:
	var art := _art(sector)
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override(&"separation", 10)
	head.add_child(Tile.new(art[0], art[1], 34.0))
	var sl := Label.new()
	sl.text = String(SECTORS[sector][1])
	sl.theme_type_variation = UiTheme.HEADING
	head.add_child(sl)
	var pips := GoalArt.Pips.new(0, ProgressionSystem.MAX_TIER, 13.0 * UiTheme.text_scale(), art[1])
	pips.name = "Level"
	pips.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(pips)
	var level := Label.new()
	level.theme_type_variation = UiTheme.MUTED
	head.add_child(level)
	var chip := Label.new()
	chip.name = "Ready"
	chip.theme_type_variation = UiTheme.GOOD
	chip.visible = false
	head.add_child(chip)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	var toggle := Button.new()
	toggle.name = "NextLevel"
	toggle.text = "Next level"
	toggle.icon = MenuKit.pic(&"up", 20.0 * UiTheme.text_scale())
	toggle.toggle_mode = true
	toggle.tooltip_text = "What the next %s level needs." % String(SECTORS[sector][1]).to_lower()
	head.add_child(toggle)
	var box := PanelContainer.new()
	box.name = "NextLevelBox"
	box.theme_type_variation = UiTheme.CARD
	box.visible = false
	var box_col := VBoxContainer.new()
	box.add_child(box_col)
	_next_labels[sector] = _wrap_label("", UiTheme.MUTED)
	box_col.add_child(_next_labels[sector])
	_ready_labels[sector] = _wrap_label("", UiTheme.MUTED)
	box_col.add_child(_ready_labels[sector])
	toggle.toggled.connect(func(on: bool) -> void: box.visible = on)
	_sector_ui[sector] = {"level": level, "pips": pips, "chip": chip, "toggle": toggle, "box": box}
	return head


func _make_card(def: UpgradeDefinition) -> Control:
	var sector: Array = SECTORS.get(def.sector, ["●", "Other"])
	var art := _art(def.sector, def.id)
	var ts := UiTheme.text_scale()
	var card := PanelContainer.new()
	card.name = "Card_%s" % def.id
	card.theme_type_variation = UiTheme.CARD
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	card.add_child(box)

	# ---- picture, name, what it gives, who installs it
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 10)
	box.add_child(top)
	var tile := Tile.new(art[0], art[1], 46.0)
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(tile)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override(&"separation", 2)
	top.add_child(words)
	words.add_child(_wrap_label(def.title, UiTheme.HEADING))
	var gives := _wrap_label(gives_text(def), &"")
	gives.name = "Gives"
	words.add_child(gives)
	var me := services.local_character() if services != null else null
	var who := GoalArt.Who.new(String(def.specialty), 36.0 * ts, def.specialty != &"" and (me == null or me.specialty != def.specialty))
	who.name = "Who"
	who.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	who.mouse_filter = Control.MOUSE_FILTER_PASS
	HudKit.say(who, "Installed by: %s" % ProgressionSystem.installer_words(def))
	top.add_child(who)

	# ---- cost against what the colony has
	var cost_row := HBoxContainer.new()
	cost_row.name = "Cost"
	cost_row.add_theme_constant_override(&"separation", 8)
	box.add_child(cost_row)
	cost_row.add_child(MenuKit.picture(&"gear", 20.0 * ts, &"muted"))
	var cost := Label.new()
	cost_row.add_child(cost)
	var have := Label.new()
	cost_row.add_child(have)

	# ---- the one thing it waits for
	var state_row := HBoxContainer.new()
	state_row.name = "State"
	state_row.add_theme_constant_override(&"separation", 8)
	box.add_child(state_row)
	var state_icon := MenuKit.picture(&"lock", 22.0 * ts)
	state_row.add_child(state_icon)
	var reason := _wrap_label("", &"")
	state_row.add_child(reason)
	_reason_labels[def.id] = reason

	# ---- the buttons: Upgrade large on its own line, Questions and More under it
	var install := MenuKit.ScaledButton.new()
	install.font_scale = 1.15
	install.name = "Install"
	install.text = "Upgrade"
	install.disabled = true
	install.focus_mode = Control.FOCUS_ALL
	install.custom_minimum_size.y = 50.0
	install.add_theme_constant_override(&"h_separation", 10)
	install.pressed.connect(_on_install_pressed.bind(def))
	box.add_child(install)
	install_buttons.append(install)
	var row := HFlowContainer.new()          # wraps on a narrow card, so a card is never wider than its column
	row.add_theme_constant_override(&"h_separation", 8)
	row.add_theme_constant_override(&"v_separation", 6)
	box.add_child(row)
	var questions := Button.new()
	questions.name = "Questions"
	questions.text = "Questions"
	questions.focus_mode = Control.FOCUS_ALL
	questions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	questions.pressed.connect(_open_quiz.bind(def))
	row.add_child(questions)
	question_buttons[def.id] = questions
	var more_button := Button.new()
	more_button.name = "MoreButton"
	more_button.text = "More"
	more_button.icon = MenuKit.pic(&"down", 18.0 * ts)
	more_button.toggle_mode = true
	more_button.focus_mode = Control.FOCUS_ALL
	more_button.tooltip_text = "What it does, the numbers, and everything it needs."
	row.add_child(more_button)
	more_buttons[def.id] = more_button

	# ---- everything else, off by default
	var more := VBoxContainer.new()
	more.name = "More"
	more.visible = false
	box.add_child(more)
	more.add_child(_wrap_label("%s · level %d card · %s" % [String(sector[1]), def.tier, def.zone], UiTheme.MUTED))
	more.add_child(_wrap_label("What it does: " + def.function_text, &""))
	more.add_child(_wrap_label("Effect: " + def.effect, &""))
	if not def.source_labels.is_empty():
		more.add_child(_wrap_label("Where the numbers come from: " + " ".join(def.source_labels), UiTheme.MUTED))
	more.add_child(_wrap_label("Needs:", UiTheme.HEADING))
	var lines: Array = []
	# tier + questions + evidence + prerequisites + parts + installer + station
	for i in 1 + def.questions.size() + def.evidence.size() + def.prerequisites.size() + 3:
		var l := _wrap_label("", UiTheme.MUTED)
		more.add_child(l)
		lines.append(l)
	_req_labels[def.id] = lines
	_cost_labels[def.id] = lines[1 + def.questions.size() + def.evidence.size() + def.prerequisites.size()]
	more_button.toggled.connect(func(on: bool) -> void:
		more.visible = on
		more_button.text = "Less" if on else "More"
		more_button.icon = MenuKit.pic(&"up" if on else &"down", 18.0 * UiTheme.text_scale()))
	_cards[def.id] = {"cost_row": cost_row, "cost": cost, "have": have, "state_row": state_row, "state_icon": state_icon, "more": more, "look": ""}
	return card


func _on_help_toggled(on: bool) -> void:
	_help_box.visible = on
	if on:
		_scroll.scroll_vertical = 0


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


## Arrow keys: left / right move between the Upgrade buttons along a row of cards; down goes to the card's own
## Questions and More, and on to the card below; up comes back the same way. Tab goes through every button in order.
func _link_focus() -> void:
	var start := 0
	for sector: String in SECTORS:
		var grid := _grids.get(sector) as GridContainer
		var count := ProgressionSystem.cards_of(sector).size()
		var cols := maxi(1, grid.columns if grid != null else 1)
		for k in count:
			var i := start + k
			var b := install_buttons[i]
			var q := question_buttons[definitions[i].id] as Button
			var m := more_buttons[definitions[i].id] as Button
			var col := k % cols
			var has_left := col > 0
			var has_right := col < cols - 1 and k + 1 < count
			var none := NodePath("")
			b.focus_neighbor_left = b.get_path_to(install_buttons[i - 1]) if has_left else none
			b.focus_neighbor_right = b.get_path_to(install_buttons[i + 1]) if has_right else none
			b.focus_neighbor_top = b.get_path_to(question_buttons[definitions[i - cols].id]) if k - cols >= 0 else none
			b.focus_neighbor_bottom = b.get_path_to(q)
			q.focus_neighbor_top = q.get_path_to(b)
			m.focus_neighbor_top = m.get_path_to(b)
			q.focus_neighbor_right = q.get_path_to(m)
			m.focus_neighbor_left = m.get_path_to(q)
			q.focus_neighbor_left = q.get_path_to(more_buttons[definitions[i - 1].id]) if has_left else none
			m.focus_neighbor_right = m.get_path_to(question_buttons[definitions[i + 1].id]) if has_right else none
			var below := none
			if k + cols < count:
				below = q.get_path_to(install_buttons[i + cols])
			q.focus_neighbor_bottom = below
			m.focus_neighbor_bottom = m.get_path_to(install_buttons[i + cols]) if k + cols < count else none
		start += count


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
		_show_message("One moment…", UiTheme.MUTED)
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


## A sector's picture on a tinted tile. Its size follows the text size setting.
class Tile extends Control:
	const Kit := preload("res://scripts/ui/hud/hud_kit.gd")
	var kind: StringName = &""
	var tint := Color.WHITE
	var base := 44.0

	func _init(p_kind: StringName = &"", p_tint := Color.WHITE, p_base := 44.0) -> void:
		kind = p_kind
		tint = p_tint
		base = p_base
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_fit()

	func _fit() -> void:
		var px := roundf(base * UiTheme.text_scale())
		if not is_equal_approx(custom_minimum_size.x, px):
			custom_minimum_size = Vector2(px, px)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			_fit()
			queue_redraw()

	func _draw() -> void:
		var contrast := UiTheme.is_high_contrast()
		var plate := StyleBoxFlat.new()
		plate.bg_color = Color(tint, 0.22 if contrast else 0.14)
		plate.border_color = Color(tint, 0.95 if contrast else 0.5)
		plate.set_border_width_all(2)
		plate.set_corner_radius_all(roundi(size.x * 0.24))
		plate.anti_aliasing = true
		draw_style_box(plate, Rect2(Vector2.ZERO, size))
		Kit.draw_icon(self, kind, Rect2(Vector2.ZERO, size).grow(-size.x * 0.2), tint)
