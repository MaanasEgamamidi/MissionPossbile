class_name StationPanel
extends UiPanel
## The surface of a station: what it is, where it is, whether its room has power, what you can do here and its
## readings. It only reads state; anything it changes goes through services.request().
## StationPanels.for_station() makes these. The power panel, the life-support console, the sun trackers and the suit
## rack build on it (PowerStationPanel, LifeSupportStationPanel, SolarStationPanel, SuitRackPanel).


const StationKit = preload("res://scripts/ui/stations/station_kit.gd")
const HudKit = preload("res://scripts/ui/hud/hud_kit.gd")


## One reading on one compact line: a pictogram, a short name, a level bar when the reading is "how full", the value,
## a status mark (✓ fine, ! attention, ✖ urgent) and a "?" button (shown while the panel's help is on).
## Colour is never the only cue: the mark changes shape with the level.
class Reading extends HBoxContainer:
	## The glyph of the reading; hidden when `picture` draws it instead.
	var symbol_label: Label
	## The pictogram of the reading (null when its glyph has none).
	var picture: TextureRect
	var name_label: Label
	## How full the store is, as a bar; hidden until set_share() is given a share.
	var bar: Control
	var value_label: Label
	var mark_label: Label
	var explain: ExplainButton
	var level: StringName = &"ok"
	## The share last given to set_share(), or -1 when the reading has no bar.
	var share := -1.0

	## A new reading line. `explanation_id` is the id of the "?" button's explanation.
	static func make(symbol: String, label: String, explanation_id: String) -> Reading:
		var row := Reading.new()
		row.add_theme_constant_override(&"separation", 10)
		row.custom_minimum_size.y = 40.0
		var kind: StringName = StationKit.glyph_pic(symbol)
		row.symbol_label = Label.new()
		row.symbol_label.name = "Symbol"
		row.symbol_label.text = symbol
		row.symbol_label.theme_type_variation = UiTheme.HEADING
		row.symbol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.symbol_label.custom_minimum_size.x = 34.0
		row.symbol_label.visible = kind == &""
		row.add_child(row.symbol_label)
		if kind != &"":
			row.picture = StationKit.picture(kind, 26.0, &"heading")
			row.picture.name = "Picture"
			row.picture.custom_minimum_size.x = 34.0
			row.add_child(row.picture)
		row.name_label = Label.new()
		row.name_label.name = "Name"
		row.name_label.text = label
		row.name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(row.name_label)
		row.bar = HudKit.Bar.new(UiTheme.palette().good, Vector2(110, 12), "Level")
		row.bar.visible = false
		row.add_child(row.bar)
		row.value_label = Label.new()
		row.value_label.name = "Value"
		row.value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(row.value_label)
		row.mark_label = Label.new()
		row.mark_label.name = "Mark"
		row.mark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.mark_label.custom_minimum_size.x = 24.0
		row.add_child(row.mark_label)
		row.explain = ExplainButton.make(explanation_id)
		row.add_child(row.explain)
		row.set_value("…", &"ok")
		return row

	## Shows `text` (a number with its unit, or words) and the status `p_level`: &"ok", &"warn" or &"urgent".
	func set_value(text: String, p_level: StringName) -> void:
		level = p_level
		value_label.text = text
		var p := UiTheme.palette()
		var colour: Color = p.good
		match p_level:
			&"urgent":
				mark_label.text = "✖"
				mark_label.theme_type_variation = UiTheme.URGENT
				value_label.theme_type_variation = UiTheme.URGENT
				colour = p.urgent
			&"warn":
				mark_label.text = "!"
				mark_label.theme_type_variation = UiTheme.WARN
				value_label.theme_type_variation = UiTheme.WARN
				colour = p.warn
			_:
				mark_label.text = "✓"
				mark_label.theme_type_variation = UiTheme.GOOD
				value_label.theme_type_variation = &""
		bar.set(&"color", colour)

	## Shows how full the store is as a bar (0 = empty, 1 = full). A negative share hides the bar.
	func set_share(p_share: float) -> void:
		share = p_share
		bar.visible = p_share >= 0.0
		if p_share >= 0.0:
			bar.set(&"share", clampf(p_share, 0.0, 1.0))


## One upgrade path in the "Upgrades" part of a station panel (owner request 2026-11-14). UI overhaul (2026-11-15): one
## line per card. On screen: the track's name and V1..V4 pips, the next stage in words, its cost as a gear and a number,
## the upgrade button and why it is greyed out. The rest (the stage now, what the next level gives, the cost against
## the colony's parts, who can do it) is the card's tooltip (`details`). StationPanel builds and refreshes it; it
## only shows.
class UpgradeRow extends PanelContainer:
	var track := ""
	var name_label: Label
	var pips: Array[Label] = []
	## The one line: "Next: Two-layer rack with LED bars".
	var next_label: Label
	## The cost chip (a gear pictogram and this number).
	var cost_chip: Control
	var cost_label: Label
	var button: Button
	var reason_label: Label
	## True while an upgrade request waits for the host's answer.
	var pending := false

	## Every line shown now, top to bottom (for tests and the layout check). The cost chip reads "⚙ 2".
	func shown_lines() -> PackedStringArray:
		var out := PackedStringArray([name_label.text, pips_text()])
		if next_label.visible and next_label.text != "":
			out.append(next_label.text)
		if cost_chip.visible:
			out.append("⚙ " + cost_label.text)
		if reason_label.visible and reason_label.text != "":
			out.append(reason_label.text)
		if button.visible:
			out.append("[%s]%s" % [button.text, " (greyed out)" if button.disabled else ""])
		return out

	## The card's tooltip: the stage now, the next stage, what it gives, its cost and who can do it, one per line.
	func details() -> String:
		return tooltip_text

	## The pips as text: "● V1 ● V2 ○ V3 ○ V4".
	func pips_text() -> String:
		var parts := PackedStringArray()
		for p: Label in pips:
			parts.append(p.text)
		return " ".join(parts)


## Shown on stations that have parts not built yet.
const LATER_NOTE := "More controls arrive with the colony systems update."

## Station id in ColonyState.stations.
var station_id: StringName = &""
## Station kind ("power", "computer", ...).
var kind := ""
## Reading lines by key, for refresh() and tests.
var readings: Dictionary = {}
## Buttons of the colony computer by key ("summary", "upgrades", "scout"; "blueprint" is off for now, owner 2026-11-14).
var computer_buttons: Dictionary = {}
## Equipment switches by equipment id (power panel and life-support console).
var equipment_switches: Dictionary = {}
## The "Upgrades" rows by track id (AreaLevels), one per upgrade path this station serves.
var upgrade_rows: Dictionary = {}

## The "?" switch in the header: shows the help sentences, the notes and the "?" buttons of the readings.
var help_button: Button

var _built := false
var _title: Label
var _zone_label: Label
var _zone_chip: PanelContainer
var _power_label: Label
var _power_chip: PanelContainer
var _power_explain: ExplainButton
## True while the help is shown (the "?" switch in the header).
var _help_on := false
## Controls shown only while the help is on (notes, "?" buttons).
var _help_nodes: Array[Control] = []
## The "what you can do here" sentences (inside the help).
var _help_box: VBoxContainer
## The big action buttons at the top of the panel.
var _actions: HFlowContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _readings_box: VBoxContainer
var _cause: Label
var _message: Label
var _close_button: Button
var _crew_rows: Dictionary = {}
## Status label next to each equipment switch, by equipment id.
var _equipment_status: Dictionary = {}
## Equipment switches waiting for the host's answer: equipment id -> true.
var _equipment_pending: Dictionary = {}
## Requests sent from a networked client that still wait for the host: request id -> Callable(result).
var _waiting: Dictionary = {}


## Builds the panel once; calling it again does nothing.
func setup(p_services: GameServices) -> void:
	if _built:
		return
	super.setup(p_services)
	_built = true
	name = "Station_%s" % String(station_id).validate_node_name().replace(".", "_")
	theme_type_variation = UiTheme.PANEL
	# A station surface is a card in the middle of the view, as tall as what it shows (UiRoot.HUG), never the whole
	# screen: the room stays visible around it.
	if max_width == 0.0:
		max_width = 1040.0
	if max_height == 0.0:
		max_height = -1.0
	_build_frame()
	_build_body()
	_build_upgrades()
	if _shows_later_note():
		var later := Label.new()
		later.text = LATER_NOTE
		later.theme_type_variation = UiTheme.MUTED
		later.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(later)
	(_readings_box.get_parent() as Control).visible = _readings_box.get_child_count() > 0
	_actions.visible = _actions.get_child_count() > 0
	_apply_help()
	refresh()


## True while the help (what you can do here, the notes, the "?" buttons) is shown.
func is_help_shown() -> bool:
	return _help_on


## Shows or hides the help, as the "?" switch in the header does.
func set_help_shown(on: bool) -> void:
	_help_on = on
	if help_button != null:
		help_button.set_pressed_no_signal(on)
	_apply_help()
	refresh()


## The sentences of "what you can do here", as the help shows them.
func help_lines() -> PackedStringArray:
	return _what_you_can_do()


func panel_title() -> String:
	return _title_text() if kind in ["repair_task", "cassette_anchor", "cassette_player_anchor"] else StationPanels.name_of(kind)


func first_focus() -> Control:
	if _body == null:
		return _close_button
	# The first control that can be used; if every one is greyed out, the first of those (its tooltip says why).
	var inner := _first_shown_focusable(_body, true)
	if inner == null:
		inner = _first_shown_focusable(_body, false)
	return inner if inner != null else _close_button


## The first control in `node` that is shown and can take focus. `usable_only` skips greyed-out buttons.
static func _first_shown_focusable(node: Node, usable_only: bool) -> Control:
	for child in node.get_children():
		if not child is Control:
			continue
		var c := child as Control
		if not c.visible:
			continue
		if c.focus_mode != Control.FOCUS_NONE and not (usable_only and c is BaseButton and (c as BaseButton).disabled):
			return c
		var inner := _first_shown_focusable(c, usable_only)
		if inner != null:
			return inner
	return null


## The zone (room) the station stands in.
func station_zone() -> String:
	if services == null or not services.has_game():
		return ""
	return String((services.state().stations.get(String(station_id), {}) as Dictionary).get("zone", ""))


## The text of the last answer or note shown at the bottom of the panel.
func message_text() -> String:
	return _message.text if _message != null else ""


## The cause-and-effect line shown after the last change ("Greenhouse off: the colony now uses 44 kW.").
func cause_text() -> String:
	return _cause.text if _cause != null else ""


## The status words next to an equipment switch ("✓ On · uses 1 kW").
func equipment_status_text(id: String) -> String:
	var l := _equipment_status.get(id) as Label
	return l.text if l != null else ""


func refresh() -> void:
	if not _built or services == null or not services.has_game():
		return
	var st := services.state()
	var zone := station_zone()
	_zone_label.text = "Outside" if zone == ColonyZones.EXTERIOR else zone
	_zone_chip.visible = not zone.is_empty()
	var show_power := _shows_room_power() and st.zones.has(zone)
	_power_chip.visible = show_power
	_power_explain.set_meta(&"help_off", not show_power)
	_power_explain.visible = show_power and _help_on
	if st.is_zone_powered(zone):
		_power_label.text = "✓ Power on"
		_power_label.theme_type_variation = UiTheme.GOOD
	else:
		_power_label.text = "✖ No power"
		_power_label.theme_type_variation = UiTheme.URGENT
	_refresh_equipment_switches(st)
	_refresh_body(st)
	_refresh_upgrades(st)


# ---------------------------------------------------------------- shared helpers

## A number in plain form: at most `decimals` decimals, no trailing zeros.
static func num(value: float, decimals := 1) -> String:
	var t := String.num(value, decimals)
	if t.contains("."):
		t = t.rstrip("0").rstrip(".")
	return "0" if t == "-0" else t


## A signed power ("+12.5 kW", "−3 kW", "0 kW").
static func signed_kw(value: float) -> String:
	if value > 0.05:
		return "+%s kW" % num(value)
	if value < -0.05:
		return "−%s kW" % num(-value)
	return "0 kW"


## Text from the model with nicer chemistry: "CO2" becomes "CO₂".
static func words(text: String) -> String:
	return text.replace("CO2", "CO₂")


## Status of a store from how full it is.
static func stock_level(amount: float, capacity: float) -> StringName:
	if capacity <= 0.0:
		return &"ok"
	var share := amount / capacity
	if share < 0.1:
		return &"urgent"
	if share < 0.25:
		return &"warn"
	return &"ok"


## How long `amount` lasts when it goes down by `drain_per_hour` each game hour; "—" when it is not going down.
static func time_left_text(amount: float, drain_per_hour: float) -> String:
	if drain_per_hour <= 1e-6:
		return "—"
	var hours := amount / drain_per_hour
	if hours >= GameConfig.SOL_HOURS:
		return "about %s sols" % num(hours / GameConfig.SOL_HOURS, 1)
	if hours >= 1.0:
		return "about %d hours" % roundi(hours)
	return "less than 1 hour"


## Power the colony asks for with everything switched as it is now, in kW (the same rule as the simulation:
## base load, the lights of every switched-on room and every switched-on machine).
static func colony_load_kw(st: ColonyState, balance: GameBalance) -> float:
	var total := 0.0
	for g in PowerModel.demand_groups(st, balance, process_kw(st)):
		total += float(g.kw)
	return total


## The power the two oxygen processes asked for in the last tick, for PowerModel.demand_groups().
static func process_kw(st: ColonyState) -> Dictionary:
	return {"electrolyser": float(st.unit("electrolyser").get("kw", 0.0)), "co2_unit": float(st.unit("co2_unit").get("kw", 0.0))}


## Partial pressures of the cabin air in kPa, worked out from the gas masses (ideal gas law, as in the model):
## {"o2", "n2", "co2", "total"}.
static func cabin_kpa(st: ColonyState, balance: GameBalance) -> Dictionary:
	var o2 := balance.gas_kpa(st.cabin_o2_kg, GameBalance.MOLAR_O2)
	var n2 := balance.gas_kpa(st.cabin_n2_kg, GameBalance.MOLAR_N2)
	var co2 := balance.gas_kpa(st.cabin_co2_kg, GameBalance.MOLAR_CO2)
	return {"o2": o2, "n2": n2, "co2": co2, "total": o2 + n2 + co2}


## Level of the cabin oxygen: below the warning level "warn", below the harm level "urgent".
static func o2_level(kpa: float, balance: GameBalance) -> StringName:
	if kpa < balance.o2_low_kpa:
		return &"urgent"
	if kpa < balance.o2_warn_kpa:
		return &"warn"
	return &"ok"


## Level of the cabin carbon dioxide.
static func co2_level(kpa: float, balance: GameBalance) -> StringName:
	if kpa >= balance.co2_danger_kpa:
		return &"urgent"
	if kpa >= balance.co2_warn_kpa:
		return &"warn"
	return &"ok"


## Words for a cabin oxygen level.
static func o2_word(level: StringName) -> String:
	match level:
		&"urgent": return "Too low"
		&"warn": return "Low"
	return "Safe"


## Words for a cabin carbon dioxide level.
static func co2_word(level: StringName) -> String:
	match level:
		&"urgent": return "Dangerous"
		&"warn": return "High"
	return "Safe"


## Oxygen one process makes right now, kg per game hour (0 unless it runs and has power).
## The model asks each process for the power its output needs, so kg per hour = kW / kWh per kg.
static func process_o2_kg_per_hour(st: ColonyState, balance: GameBalance, id: String) -> float:
	var status := String(st.oxygen_process.get(id, "off"))
	if status != "running" and status != "feed_short":
		return 0.0
	if not st.is_powered(id):
		return 0.0
	var per_kg := balance.electrolysis_kwh_per_kg_o2 if id == "electrolyser" else balance.co2_unit_kwh_per_kg_o2
	if per_kg <= 0.0:
		return 0.0
	return float(st.unit(id).get("kw", 0.0)) / per_kg


## Status of an equipment switch as [words, level]: off, broken, no power (shed), waiting, or on with its kW.
static func equipment_status(st: ColonyState, balance: GameBalance, id: String) -> Array:
	if not st.is_on(id):
		return ["○ Off", &"off"]
	if st.condition_of(id) < balance.equipment_min_condition:
		return ["! Broken", &"warn"]
	if not st.is_powered(id):
		return ["✖ No power", &"urgent"]
	if id == "electrolyser" or id == "co2_unit":
		var status := String(st.oxygen_process.get(id, "off"))
		if status != "running" and status != "feed_short":
			return ["! Waiting: %s" % String(LifeSupportModel.STATUS_TEXT.get(status, status)), &"warn"]
	var kw := PowerModel.equipment_kw(st, balance, id, process_kw(st))
	return ["✓ On · uses %s kW" % num(kw, 2), &"ok"]


## The name of a piece of equipment in words ("Water recycler").
static func equipment_name(id: String) -> String:
	return words(String(PowerModel.LABELS.get(id, id)))


## The tooltip of a machine's control with its science name ("Water splitter (electrolyser): ..."), or "".
static func equipment_tip(id: String) -> String:
	return words(String(PowerModel.SCIENCE_TIPS.get(id, "")))


# ---------------------------------------------------------------- building

func _build_frame() -> void:
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	margin.add_child(column)

	# ---- header: picture, name, the "?" switch, the keys that close the panel, the close button
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override(&"separation", 10)
	column.add_child(header)
	var kind_pic: StringName = StationKit.kind_pic(kind)
	if kind_pic != &"":
		var picture: TextureRect = StationKit.picture(kind_pic, 40.0, &"heading")
		picture.name = "Picture"
		header.add_child(picture)
	_title = Label.new()
	_title.name = "Title"
	_title.text = _title_text() if kind_pic != &"" else "%s  %s" % [StationPanels.symbol_of(kind), _title_text()]
	_title.theme_type_variation = UiTheme.TITLE
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_title)
	help_button = StationKit.icon_button(&"help", "Help: what you can do here")
	help_button.name = "Help"
	help_button.toggle_mode = true
	help_button.toggled.connect(set_help_shown)
	header.add_child(help_button)
	for key_text: String in [_key_name(&"interact", "E"), _key_name(&"back", "Esc")]:
		header.add_child(UiTheme.key_cap(StationKit.cap_text(key_text)))
	_close_button = StationKit.icon_button(&"close", "Close")
	_close_button.name = "Close"
	_close_button.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(_close_button)

	# ---- chips: the room, and whether it has power
	var info := HBoxContainer.new()
	info.name = "Chips"
	info.add_theme_constant_override(&"separation", 8)
	column.add_child(info)
	_zone_chip = StationKit.chip(&"home", "")
	_zone_chip.name = "Room"
	_zone_label = _zone_chip.find_child("Text", true, false) as Label
	_zone_label.theme_type_variation = UiTheme.MUTED
	info.add_child(_zone_chip)
	_power_chip = StationKit.chip(&"bolt", "")
	_power_chip.name = "RoomPower"
	_power_chip.tooltip_text = "Rooms can be switched off at the power panel."
	_power_label = _power_chip.find_child("Text", true, false) as Label
	info.add_child(_power_chip)
	_power_explain = ExplainButton.make("zones_power")
	_help_only(_power_explain)
	info.add_child(_power_explain)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override(&"separation", 6)
	_scroll.add_child(_body)

	# ---- help (off until the "?" switch): what you can do here, in sentences
	var help_card := PanelContainer.new()
	help_card.name = "Help"
	help_card.theme_type_variation = UiTheme.CARD
	_body.add_child(help_card)
	_help_only(help_card)
	_help_box = VBoxContainer.new()
	help_card.add_child(_help_box)
	for line in _what_you_can_do():
		_add_text(_help_box, "•  " + line)

	# ---- the big buttons: what you do here
	_actions = HFlowContainer.new()
	_actions.name = "Actions"
	_actions.add_theme_constant_override(&"h_separation", 10)
	_actions.add_theme_constant_override(&"v_separation", 8)
	_body.add_child(_actions)

	var readings_section := VBoxContainer.new()
	readings_section.name = "Readings"
	_body.add_child(readings_section)
	_readings_box = VBoxContainer.new()
	_readings_box.add_theme_constant_override(&"separation", 2)
	readings_section.add_child(_readings_box)

	_cause = Label.new()
	_cause.name = "Cause"
	_cause.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cause.visible = false
	column.add_child(_cause)
	_message = Label.new()
	_message.name = "Message"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.visible = false
	column.add_child(_message)


## Marks `node` as part of the help: it is shown only while the "?" switch in the header is on.
func _help_only(node: Control) -> Control:
	_help_nodes.append(node)
	node.visible = _help_on and not bool(node.get_meta(&"help_off", false))
	return node


func _apply_help() -> void:
	var keep: Array[Control] = []
	for node: Control in _help_nodes:
		if is_instance_valid(node):
			keep.append(node)
			node.visible = _help_on and not bool(node.get_meta(&"help_off", false))
	_help_nodes = keep


## A sentence that explains (why, how it works): part of the help, hidden until the "?" switch is on.
func _add_note(parent: Control, text: String, variation: StringName = UiTheme.MUTED) -> Label:
	var l := _add_text(parent, text, variation)
	_help_only(l)
	return l


## The box for the station's warnings, placed above the readings (problems first). Fill it with _fill_alerts().
func _add_alerts_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Alerts"
	_body.add_child(box)
	_body.move_child(box, _actions.get_index() + 1)
	return box


## A big action button at the top of the panel: a picture and one to three words. The first one is the station's
## main action (`primary`); others are drawn plain.
func _add_action(text: String, pic_kind: StringName, on_pressed := Callable(), primary := true) -> Button:
	var b: Button = StationKit.action(text, pic_kind, primary)
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	_actions.add_child(b)
	_actions.visible = true
	return b


## The words after the symbol in the header. Sun trackers add their number.
func _title_text() -> String:
	if kind in ["repair_task", "cassette_anchor", "cassette_player_anchor"] and services != null:
		return String((services.state().stations.get(String(station_id), {}) as Dictionary).get("name", "Reserved interaction"))
	return StationPanels.name_of(kind)


## True: the header says whether the station's room has power. Stations outside have no room switch.
func _shows_room_power() -> bool:
	return true


## True: the "more controls later" note is shown (stations whose controls are not built yet).
func _shows_later_note() -> bool:
	# UI overhaul: a note about future updates is for developers, not players; it is no longer shown.
	return false


func _what_you_can_do() -> PackedStringArray:
	match kind:
		"repair_task":
			var record: Dictionary = services.state().stations.get(String(station_id), {})
			var role := String(record.get("specialty", ""))
			var words := String(StationPanels.SPECIALTY_WORDS.get(StringName(role), "All crew members"))
			return PackedStringArray(["A repair spot for %s." % words.to_lower()])
		"cassette_anchor":
			var record: Dictionary = services.state().stations.get(String(station_id), {})
			var id := String(record.get("cassette_id", station_id))
			var title := String(CassetteCatalog.TAPES.get(id, {}).get("title", "Room"))
			return PackedStringArray(["%s cassette - %s." % [title, "Collected" if CassetteCatalog.collected(services.state(), id) else "Missing"], CassetteCatalog.PLAY_INSTRUCTION])
		"cassette_player_anchor":
			return PackedStringArray([CassetteCatalog.PLAY_INSTRUCTION, "Pick a tape you have found."])
		"computer":
			return PackedStringArray(["See the colony summary: stores, power and how long they last.",
				"Look at the upgrade cards for the facilities."])
			# Owner 2026-11-14: map off for now (goals big view replaces it)
			#	"Look at the upgrade cards for the facilities.", "Open the blueprint map of the base."])
		"comms":
			return PackedStringArray(["Read messages from Earth.", "Learn why a radio message to Earth takes minutes.", "Repair the colony radio (radio repairs)."])
		"food":
			return PackedStringArray(["See how much food is in store.", "See how much the crew eats each sol."])
		"heal":
			return PackedStringArray(["See how healthy each crew member is."])
		"board":
			return PackedStringArray(["Look at the radio's main circuit board."])
		"survivor":
			return PackedStringArray(["Check on the patient."])
	return PackedStringArray(["Look at this station."])


## Adds the station's own readings and controls. The special station panels replace it.
func _build_body() -> void:
	match kind:
		"computer":
			_add_reading(&"battery", "▮", "Battery", "battery")
			_add_reading(&"parts", "⚙", "Spare parts", "parts")
			computer_buttons["summary"] = _add_open_button(_actions, "Colony summary", func() -> UiPanel: return ColonySummaryPanel.new(), &"chart")
			computer_buttons["upgrades"] = _add_open_button(_actions, "Upgrades", func() -> UiPanel: return UpgradeCardsPanel.new(), &"up", false)
			# Owner 2026-11-14: map off for now (goals big view replaces it)
			#computer_buttons["blueprint"] = _add_open_button(_actions, "Blueprint map", func() -> UiPanel: return BlueprintPanel.new())
			# Scout update: the scout rover can be sent from the colony computer as well as from its bay outside.
			var make_scout := func() -> UiPanel:
				var p := ScoutBayStationPanel.new()
				p.station_id = station_id
				p.kind = kind
				return p
			computer_buttons["scout"] = _add_open_button(_actions, "Scout rover", make_scout, &"rover", false)
		"comms":
			_add_heading(_body, "Messages from Earth")
			var card := PanelContainer.new()
			card.theme_type_variation = UiTheme.CARD
			_body.add_child(card)
			var list := VBoxContainer.new()
			card.add_child(list)
			_add_text(list, "Mission control: \"Welcome to Mars! Keep the lights on and the air fresh.\"")
			_add_text(list, "No new messages.", UiTheme.MUTED)
			var why := HBoxContainer.new()
			_body.add_child(why)
			_help_only(why)
			var why_text := _add_text(why, "Earth is very far away. A radio message travels as fast as light, but it still takes "
				+ "minutes to reach Earth, and the answer takes minutes to come back.", UiTheme.MUTED)
			why_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			why.add_child(ExplainButton.make("sources"))
			# Prompt 11: the colony radio's stage and its repair cards (installed at this console).
			_add_text(_body, CommsStage.stage_text(CommsStage.stage(services.state())))
			_add_open_button(_actions, "Radio repairs", func() -> UiPanel: return UpgradeCardsPanel.new(), &"wrench")
		"food":
			_add_reading(&"food", "❀", "Food", "food")
			_add_reading(&"food_use", "↓", "Crew eats", "stock_vs_flow")
			_add_reading(&"food_left", "⧗", "Lasts", "food")
		"heal":
			var ids: Array = services.state().characters.keys()
			ids.sort()
			for id: StringName in ids:
				var c := services.state().character(id)
				var row := _add_reading(StringName("health_%s" % id), String(StationPanels.SPECIALTY_SYMBOLS.get(c.specialty, "●")), c.display_name, "health")
				_crew_rows[id] = row
		"board":
			_add_text(_body, "The main part of the colony's long-range radio. It is damaged.")
		"survivor":
			_add_reading(&"med_bay_power", "⚡", "Med Bay power", "zones_power")
			_add_note(_body, "A patient is resting here. Keeping the Med Bay powered keeps them warm and the machines running.")


## Updates the station's own readings. The special station panels replace it.
func _refresh_body(st: ColonyState) -> void:
	var bal := services.balance
	var crew := float(st.active_characters().size())
	match kind:
		"computer":
			var battery := st.store(&"battery_kwh")
			var cap := float(st.capacities.get(&"battery_kwh", 0.0))
			_show_reading(&"battery", "%d %%" % roundi(100.0 * battery / maxf(cap, 1.0)), stock_level(battery, cap), battery / maxf(cap, 1.0))
			_show_reading(&"parts", "%d" % st.parts, &"ok" if st.parts > 0 else &"warn")
		"food":
			var food := st.store(&"food_meals")
			var cap := float(st.capacities.get(&"food_meals", 0.0))
			var per_sol := crew * bal.meals_per_sol
			_show_reading(&"food", "%s meals" % num(food, 0), stock_level(food, cap), food / maxf(cap, 1.0))
			_show_reading(&"food_use", "%s meals per sol" % num(per_sol, 1), &"ok")
			var left := time_left_text(food, per_sol / GameConfig.SOL_HOURS)
			_show_reading(&"food_left", left, _left_level(food, per_sol / GameConfig.SOL_HOURS))
		"heal":
			for id: StringName in _crew_rows:
				var c := st.character(id)
				if c == null:
					continue
				var row := _crew_rows[id] as Reading
				var who := "resting in the Med Bay"
				if c.owner_peer == services.local_peer():
					who = "you"
				elif c.owner_peer != 0:
					who = "player %d" % c.owner_peer
				row.name_label.text = "%s (%s)" % [c.display_name, who]
				var lvl: StringName = &"ok"
				var word := "Well"
				if c.health < 30.0:
					lvl = &"urgent"
					word = "Needs care"
				elif c.health < 60.0:
					lvl = &"warn"
					word = "Hurt"
				row.set_value("%d %% health · %s" % [roundi(c.health), word], lvl)
				row.set_share(c.health / 100.0)
		"survivor":
			var on := st.is_zone_powered("Med Bay")
			_show_reading(&"med_bay_power", "On" if on else "Off", &"ok" if on else &"urgent")


static func _left_level(amount: float, drain_per_hour: float) -> StringName:
	if drain_per_hour <= 1e-6:
		return &"ok"
	var hours := amount / drain_per_hour
	if hours < GameConfig.SOL_HOURS:
		return &"urgent"
	if hours < 3.0 * GameConfig.SOL_HOURS:
		return &"warn"
	return &"ok"


## Adds a reading line to the "Readings" section, or to `parent` if given.
func _add_reading(key: StringName, symbol: String, label: String, explanation_id: String, parent: Control = null) -> Reading:
	var row := Reading.make(symbol, label, explanation_id)
	row.name = "Reading_%s" % String(key)
	(parent if parent != null else _readings_box).add_child(row)
	_help_only(row.explain)
	readings[key] = row
	return row


## Shows a reading's value and level. `share` (0..1) also draws it as a level bar: how full the store is.
func _show_reading(key: StringName, text: String, level: StringName, share := -1.0) -> void:
	if readings.has(key):
		var row := readings[key] as Reading
		row.set_value(text, level)
		if share >= 0.0 or row.share >= 0.0:
			row.set_share(share)


## The value text of a reading ("12 kW"), or "" if there is no such reading.
func reading_text(key: StringName) -> String:
	var row := readings.get(key) as Reading
	return row.value_label.text if row != null else ""


func _add_heading(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = UiTheme.HEADING
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


## A heading with a "?" button at its end.
func _add_heading_with_help(parent: Control, text: String, explanation_id: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	row.custom_minimum_size.y = 40.0
	var l := _add_heading(row, text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_help_only(ExplainButton.make(explanation_id)))
	return l


func _add_text(parent: Control, text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != &"":
		l.theme_type_variation = variation
	parent.add_child(l)
	return l


## A big button that opens another panel. `pic_kind` is its pictogram; the first one of a station is `primary`.
func _add_open_button(parent: Control, text: String, make_panel: Callable, pic_kind: StringName = &"", primary := true) -> Button:
	var b: Button = StationKit.action(text, pic_kind, primary)
	b.pressed.connect(func() -> void: open_requested.emit(make_panel.call() as UiPanel))
	parent.add_child(b)
	if parent == _actions:
		_actions.visible = true
	return b


func _show_message(text: String, variation: StringName = &"") -> void:
	_message.text = text
	_message.theme_type_variation = variation
	_message.visible = not text.is_empty()


func _show_cause(text: String) -> void:
	_cause.text = text
	_cause.visible = not text.is_empty()


## Sends `action` for this station and calls `on_answer(result)` with the host's answer. On a networked client the
## answer arrives later (events.action_resolved); until then the panel says it asked the host.
func _ask(action: StringName, params: Dictionary, on_answer: Callable) -> ActionResult:
	var result := services.request(action, station_id, params)
	if result.pending:
		_waiting[result.request_id] = on_answer
		if not services.events.action_resolved.is_connected(_on_action_resolved):
			services.events.action_resolved.connect(_on_action_resolved)
		_show_message("One moment…", UiTheme.MUTED)
		return result
	on_answer.call(result)
	return result


func _on_action_resolved(result: ActionResult) -> void:
	if not _waiting.has(result.request_id):
		return
	var on_answer: Callable = _waiting[result.request_id]
	_waiting.erase(result.request_id)
	if is_inside_tree() or _built:
		on_answer.call(result)


## The plain sentence the host sent back with an answer, or "".
static func answer_text(result: ActionResult) -> String:
	return words(String(result.changes.get("text", "")))


## Shows a refused answer at the bottom of the panel.
func _show_refusal(result: ActionResult) -> void:
	_show_message("✖ %s" % result.message, UiTheme.URGENT)


# ---------------------------------------------------------------- equipment switches

## Adds an on/off switch for one piece of equipment, with its power and a status line. Sends `set_equipment`.
func _add_equipment_switch(parent: Control, id: String, text := "") -> CheckButton:
	var row := HBoxContainer.new()
	row.name = "Equipment_%s" % id
	parent.add_child(row)
	var button := CheckButton.new()
	button.name = "Switch_%s" % id
	button.text = text if text != "" else equipment_switch_text(services.balance, id, services.state())
	button.set_pressed_no_signal(services.state().is_on(id))
	button.toggled.connect(_on_equipment_toggled.bind(id))
	if equipment_tip(id) != "":
		button.tooltip_text = equipment_tip(id)
	row.add_child(button)
	var status := Label.new()
	status.name = "Status_%s" % id
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(status)
	equipment_switches[id] = button
	_equipment_status[id] = status
	return button


## The text on an equipment switch: its name and the power it needs ("Water recycler · 1 kW").
## With `state`, the oxygen machines show their output at the life-support level (life_support.o2_production_factor).
static func equipment_switch_text(balance: GameBalance, id: String, state: ColonyState = null) -> String:
	match id:
		"electrolyser":
			var e_kg := LifeSupportModel.electrolysis_o2_kg_per_hour(state, balance) if state != null else balance.electrolysis_o2_kg_per_hour
			return "%s · up to %s kW" % [equipment_name(id), num(e_kg * balance.electrolysis_kwh_per_kg_o2, 2)]
		"co2_unit":
			var c_kg := LifeSupportModel.co2_unit_o2_kg_per_hour(state, balance) if state != null else balance.co2_unit_o2_kg_per_hour
			return "%s · up to %s kW" % [equipment_name(id), num(c_kg * balance.co2_unit_kwh_per_kg_o2, 2)]
		"trackers": return "%s · %s kW" % [equipment_name(id), num(balance.tracker_drive_kw, 2)]
		"cleaner": return "%s · %s kW" % [equipment_name(id), num(balance.cleaner_kw, 2)]
		"recycler": return "%s · %s kW" % [equipment_name(id), num(balance.recycler_kw, 2)]
		"scrubber": return "%s · %s kW" % [equipment_name(id), num(balance.scrubber_kw, 2)]
		"cabin_fans": return "%s · %s kW" % [equipment_name(id), num(balance.cabin_fans_kw, 2)]
	return equipment_name(id)


func _refresh_equipment_switches(st: ColonyState) -> void:
	for id: String in equipment_switches:
		if not _equipment_pending.has(id):
			(equipment_switches[id] as CheckButton).set_pressed_no_signal(st.is_on(id))
		var status := equipment_status(st, services.balance, id)
		var l := _equipment_status[id] as Label
		l.text = String(status[0])
		match StringName(status[1]):
			&"ok": l.theme_type_variation = UiTheme.GOOD
			&"warn": l.theme_type_variation = UiTheme.WARN
			&"urgent": l.theme_type_variation = UiTheme.URGENT
			_: l.theme_type_variation = UiTheme.MUTED


func _on_equipment_toggled(on: bool, id: String) -> void:
	_equipment_pending[id] = true
	_ask(&"set_equipment", {"equipment": id, "on": on}, _on_equipment_answer.bind(id, on))


func _on_equipment_answer(result: ActionResult, id: String, on: bool) -> void:
	_equipment_pending.erase(id)
	if result.ok:
		_show_message("")
		_show_cause(_equipment_cause(result, id, on))
	else:
		var button := equipment_switches.get(id) as CheckButton
		if button != null:
			button.set_pressed_no_signal(not on)
		_show_refusal(result)
	refresh()


## The cause-and-effect sentence after an equipment switch. The power panel adds the new load.
func _equipment_cause(result: ActionResult, _id: String, _on: bool) -> String:
	return answer_text(result)


## Alerts of the colony whose id starts with one of `prefixes`, as [{"text", "level"}].
func _alerts_matching(st: ColonyState, prefixes: Array[String]) -> Array:
	var out: Array = []
	for a: Dictionary in st.alerts:
		var id := String(a.get("id", ""))
		for p: String in prefixes:
			if id.begins_with(p):
				out.append({"text": words(String(a.get("text", ""))), "level": String(a.get("level", "info"))})
				break
	return out


## Fills `box` with one line per alert ("✖ …", "! …", "• …"), or `none_text` when there are none ("" = no line).
func _fill_alerts(box: VBoxContainer, alerts: Array, none_text: String) -> void:
	var lines: Array = []
	if alerts.is_empty() and none_text != "":
		lines.append(["✓ " + none_text, UiTheme.GOOD])
	for a: Dictionary in alerts:
		match String(a.level):
			"urgent": lines.append(["✖ " + String(a.text), UiTheme.URGENT])
			"warn": lines.append(["! " + String(a.text), UiTheme.WARN])
			_: lines.append(["• " + String(a.text), &""])
	while box.get_child_count() < lines.size():
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(l)
	for i in box.get_child_count():
		var l := box.get_child(i) as Label
		l.visible = i < lines.size()
		if l.visible:
			l.text = String(lines[i][0])
			l.theme_type_variation = StringName(lines[i][1])


## The visible lines of an alert box, for tests.
static func _box_lines(box: VBoxContainer) -> PackedStringArray:
	var out := PackedStringArray()
	for child in box.get_children():
		if child is Label and (child as Label).visible:
			out.append((child as Label).text)
	return out


static func _key_name(action: StringName, fallback: String) -> String:
	if not InputMap.has_action(action):
		return fallback
	var text := PlayerInput.describe(action)
	return text if not text.is_empty() else fallback


# ---------------------------------------------------------------- upgrades (visible upgrade paths, 2026-11-14)

## Upgrade paths (AreaLevels track ids) served at this station, in data file order. Empty for most stations.
func upgrade_tracks() -> PackedStringArray:
	if services == null or not services.has_game():
		return PackedStringArray()
	var record: Dictionary = services.state().stations.get(String(station_id), {})
	if record.is_empty():
		return PackedStringArray()
	return AreaLevels.tracks_at(String(station_id), record)


## The upgrade button of a track, or null when this station has none for it (the rover has a garage hint instead).
func upgrade_button(track: String) -> Button:
	var row := upgrade_rows.get(track) as UpgradeRow
	return row.button if row != null and row.button.visible else null


## Every line the upgrade row of `track` shows now (empty when the station has no such row).
func upgrade_lines(track: String) -> PackedStringArray:
	var row := upgrade_rows.get(track) as UpgradeRow
	return row.shown_lines() if row != null else PackedStringArray()


## The tooltip of the upgrade row of `track` (the details that are not on screen), or "".
func upgrade_details(track: String) -> String:
	var row := upgrade_rows.get(track) as UpgradeRow
	return row.details() if row != null else ""


## What the next level of a track gives, in plain words: only the effects that change ("3 grow layers · 2.8× the
## food of the first rack"). "" when nothing listed changes.
static func upgrade_gives_text(track: String, next_level: int) -> String:
	var effects: Dictionary = AreaLevels.track(track).get("effects", {})
	var parts := PackedStringArray()
	for key: String in effects:
		var now: Variant = AreaLevels.effect_at(track, key, next_level - 1)
		var then: Variant = AreaLevels.effect_at(track, key, next_level)
		if then == null or (now != null and is_equal_approx(float(now), float(then))):
			continue
		parts.append(effect_words(track, key, then))
	return " · ".join(parts)


## One effect of an upgrade path in plain words, for a player of 9 to 12 ("solar panels make 1.5× the power").
## Keys added later by other parts of the game fall back to their key in words.
static func effect_words(track: String, key: String, value: Variant) -> String:
	var f := float(value) if (value is float or value is int) else 0.0
	match "%s.%s" % [track, key]:
		"food.grow_layers": return "%d grow layers" % int(f)
		"food.yield_factor": return "%s× the food of the first rack" % num(f, 2)
		"garden.plant_o2_kg_per_hour": return "plants add %s kg of oxygen an hour" % num(f, 3)
		"garden.meals_per_sol": return "%s extra meals each sol" % num(f, 1)
		"energy.solar_factor": return "solar panels make %s× the power" % num(f, 2)
		"energy.battery_capacity_factor": return "the battery holds %s× as much" % num(f, 2)
		"life_support.scrubber_factor": return "the CO₂ scrubber cleans %s× as fast" % num(f, 2)
		"life_support.o2_production_factor": return "oxygen is made %s× as fast" % num(f, 2)
		"life_support.recycler_factor": return "the water recycler works %s× as well" % num(f, 2)
		"health.heal_rate_factor": return "the crew heals %s× as fast" % num(f, 2)
		"health.recovery_health_bonus": return "+%d health when the med bay brings you back" % int(f)
		"command.drone_range_m": return "the scout drone can fly %d m from the base" % int(f)
		"scout_drone.speed_mps": return "flies at %s m per second" % num(f, 1)
		"scout_drone.flight_seconds": return "flies %s minutes on one charge" % num(f / 60.0, 1)
		"scout_drone.survey_radius_m": return "scans %d m around it" % int(f)
		"scout_drone.autopilot": return "flies to chosen places by itself" if f >= 1.0 else "you fly it by hand"
		"scout_drone.max_waypoints": return "remembers %d stop%s on a route" % [int(f), "" if int(f) == 1 else "s"]
	var shown := num(f, 2) if (value is float or value is int) else str(value)
	return "%s: %s" % [key.replace("_", " "), shown]


## Who may upgrade a track, in words ("the biology and food specialist", "anyone in the crew").
static func upgrade_who_text(track: String) -> String:
	var spec := StringName(String(AreaLevels.track(track).get("specialty", "")))
	if spec == &"":
		return "anyone in the crew"
	return "the %s specialist" % String(StationPanels.SPECIALTY_WORDS.get(spec, String(spec))).to_lower()


func _build_upgrades() -> void:
	var tracks := upgrade_tracks()
	# Only the station's own surface (StationPanels.for_station) has the strip, not a panel opened from it (the colony
	# computer's "Scout rover" button opens the scout bay panel for the computer's id).
	if tracks.is_empty() or not bool(get_meta(&"station_surface", false)):
		return
	var section := VBoxContainer.new()
	section.name = "Upgrades"
	_body.add_child(section)
	_add_heading(section, "Upgrades")
	for track: String in tracks:
		var row := UpgradeRow.new()
		row.name = "Upgrade_%s" % track
		row.track = track
		row.theme_type_variation = UiTheme.CARD
		section.add_child(row)
		var col := VBoxContainer.new()
		row.add_child(col)
		var top := HBoxContainer.new()
		col.add_child(top)
		row.name_label = Label.new()
		row.name_label.name = "Track"
		row.name_label.text = AreaLevels.track_name(track)
		row.name_label.theme_type_variation = UiTheme.HEADING
		row.name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(row.name_label)
		var pip_row := HBoxContainer.new()
		pip_row.name = "Pips"
		top.add_child(pip_row)
		for lvl in range(1, AreaLevels.max_level() + 1):
			var pip := Label.new()
			pip.name = "V%d" % lvl
			pip_row.add_child(pip)
			row.pips.append(pip)
		# the one line: the next stage in words, the cost as a gear and a number, the button
		var line := HBoxContainer.new()
		line.name = "Line"
		line.add_theme_constant_override(&"separation", 10)
		col.add_child(line)
		row.next_label = _add_text(line, "")
		row.next_label.name = "Next"
		row.cost_chip = StationKit.chip(&"gear", "")
		row.cost_chip.name = "Cost"
		row.cost_label = row.cost_chip.find_child("Text", true, false) as Label
		line.add_child(row.cost_chip)
		var buttons := line
		row.button = Button.new()
		row.button.name = "UpgradeButton"
		row.button.theme_type_variation = UiTheme.PRIMARY_BUTTON
		StationKit.button_pic(row.button, &"up", 22.0)
		row.button.pressed.connect(_on_upgrade_pressed.bind(track))
		buttons.add_child(row.button)
		row.reason_label = _add_text(col, "", UiTheme.WARN)
		row.reason_label.name = "Reason"
		upgrade_rows[track] = row


func _refresh_upgrades(st: ColonyState) -> void:
	if upgrade_rows.is_empty():
		return
	var me := services.local_character()
	for track: String in upgrade_rows:
		var row := upgrade_rows[track] as UpgradeRow
		var lvl := AreaLevels.level(st, track)
		var top_level := AreaLevels.max_level()
		for i in row.pips.size():
			var reached := i + 1 <= lvl
			row.pips[i].text = "%s V%d" % ["●" if reached else "○", i + 1]
			row.pips[i].theme_type_variation = UiTheme.GOOD if reached else UiTheme.MUTED
		var details := PackedStringArray(["Now: %s" % AreaLevels.stage_text(track, lvl)])
		var derived := AreaLevels.is_derived(track)
		var at_top := lvl >= top_level
		var has_next := not derived and not at_top
		row.next_label.visible = has_next
		row.cost_chip.visible = has_next
		row.button.visible = has_next
		if derived:
			row.reason_label.text = "Upgrade modules in the garage"
			row.reason_label.theme_type_variation = UiTheme.MUTED
			row.reason_label.visible = true
			row.tooltip_text = "\n".join(details)
			continue
		if at_top:
			row.reason_label.text = "✓ Fully upgraded (V%d)." % lvl
			row.reason_label.theme_type_variation = UiTheme.GOOD
			row.reason_label.visible = true
			row.tooltip_text = "\n".join(details)
			continue
		var next := lvl + 1
		var stages: Array = AreaLevels.track(track).get("stages", [])
		row.next_label.text = "Next: %s" % (String(stages[next - 1]) if next - 1 < stages.size() else "V%d" % next)
		details.append("Next: %s" % AreaLevels.stage_text(track, next))
		var gives := upgrade_gives_text(track, next)
		if gives != "":
			details.append("It gives: %s" % gives)
		var cost := AreaLevels.cost_to_reach(track, next)
		var cost_words := "Costs %d spare part%s · the colony has %d" % [cost, "" if cost == 1 else "s", st.parts]
		details.append(cost_words)
		row.cost_label.text = "%d" % cost
		row.cost_label.theme_type_variation = UiTheme.GOOD if st.parts >= cost else UiTheme.WARN
		row.cost_chip.tooltip_text = cost_words
		var spec := StringName(String(AreaLevels.track(track).get("specialty", "")))
		var mine := me != null and spec != &"" and me.specialty == spec
		details.append("Who can do it: %s%s" % [upgrade_who_text(track), " (you)" if mine else ""])
		row.tooltip_text = "\n".join(details)
		row.button.tooltip_text = row.tooltip_text
		row.button.text = "Upgrade to V%d" % next
		var blockers := AreaLevels.blockers(st, track, me)
		row.button.disabled = row.pending or not blockers.is_empty()
		var reasons := PackedStringArray()
		for b: Dictionary in blockers:
			reasons.append("✖ " + String(b.get("text", "")))
		row.reason_label.text = "\n".join(reasons)
		row.reason_label.theme_type_variation = UiTheme.WARN
		row.reason_label.visible = not reasons.is_empty()


func _on_upgrade_pressed(track: String) -> void:
	var row := upgrade_rows.get(track) as UpgradeRow
	if row == null or row.pending:
		return
	row.pending = true
	row.button.disabled = true
	_ask(&"upgrade_area", {"track": track}, _on_upgrade_answer.bind(track))


func _on_upgrade_answer(result: ActionResult, track: String) -> void:
	var row := upgrade_rows.get(track) as UpgradeRow
	if row != null:
		row.pending = false
	if result.ok:
		var text := answer_text(result)
		_show_message("✓ " + (text if text != "" else "%s upgraded." % AreaLevels.track_name(track)), UiTheme.GOOD)
	else:
		_show_refusal(result)
	refresh()


# ---------------------------------------------------------------- size

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


## Keeps the scrolling part a comfortable size for the screen, so the panel is never tiny and never too big.
func _fit_to_screen() -> void:
	if _scroll == null or not is_inside_tree():
		return
	var screen := get_viewport_rect().size
	_scroll.custom_minimum_size = Vector2(minf(760.0, screen.x * 0.55), minf(120.0, screen.y * 0.2))
