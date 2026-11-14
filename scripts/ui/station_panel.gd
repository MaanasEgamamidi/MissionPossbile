class_name StationPanel
extends UiPanel
## The surface of a station: what it is, where it is, whether its room has power, what you can do here and its
## readings. It only reads state; anything it changes goes through services.request().
## StationPanels.for_station() makes these. The power panel, the life-support console, the sun trackers and the suit
## rack build on it (PowerStationPanel, LifeSupportStationPanel, SolarStationPanel, SuitRackPanel).


## One reading line: symbol, name, value with its unit, a status mark (✓ fine, ! attention, ✖ urgent) and a "?" button.
class Reading extends HBoxContainer:
	var symbol_label: Label
	var name_label: Label
	var value_label: Label
	var mark_label: Label
	var explain: ExplainButton
	var level: StringName = &"ok"

	## A new reading line. `explanation_id` is the id of the "?" button's explanation.
	static func make(symbol: String, label: String, explanation_id: String) -> Reading:
		var row := Reading.new()
		row.symbol_label = Label.new()
		row.symbol_label.text = symbol
		row.symbol_label.theme_type_variation = UiTheme.HEADING
		row.add_child(row.symbol_label)
		row.name_label = Label.new()
		row.name_label.text = label
		row.name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(row.name_label)
		row.value_label = Label.new()
		row.value_label.theme_type_variation = UiTheme.READING
		row.value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(row.value_label)
		row.mark_label = Label.new()
		row.add_child(row.mark_label)
		row.explain = ExplainButton.make(explanation_id)
		row.add_child(row.explain)
		row.set_value("…", &"ok")
		return row

	## Shows `text` (a number with its unit, or words) and the status `p_level`: &"ok", &"warn" or &"urgent".
	func set_value(text: String, p_level: StringName) -> void:
		level = p_level
		value_label.text = text
		match p_level:
			&"urgent":
				mark_label.text = "✖"
				mark_label.theme_type_variation = UiTheme.URGENT
			&"warn":
				mark_label.text = "!"
				mark_label.theme_type_variation = UiTheme.WARN
			_:
				mark_label.text = "✓"
				mark_label.theme_type_variation = UiTheme.GOOD


## Shown on stations that have parts not built yet.
const LATER_NOTE := "More controls arrive with the colony systems update."

## Station id in ColonyState.stations.
var station_id: StringName = &""
## Station kind ("power", "computer", ...).
var kind := ""
## Reading lines by key, for refresh() and tests.
var readings: Dictionary = {}
## Buttons of the colony computer by key ("summary", "upgrades", "blueprint").
var computer_buttons: Dictionary = {}
## Equipment switches by equipment id (power panel and life-support console).
var equipment_switches: Dictionary = {}

var _built := false
var _title: Label
var _zone_label: Label
var _power_label: Label
var _power_explain: ExplainButton
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
	_build_frame()
	_build_body()
	if _shows_later_note():
		var later := Label.new()
		later.text = LATER_NOTE
		later.theme_type_variation = UiTheme.MUTED
		later.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(later)
	(_readings_box.get_parent() as Control).visible = _readings_box.get_child_count() > 0
	refresh()


func panel_title() -> String:
	return StationPanels.name_of(kind)


func first_focus() -> Control:
	var inner := _first_focusable(_body) if _body != null else null
	return inner if inner != null else _close_button


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
	if zone == ColonyZones.EXTERIOR:
		_zone_label.text = "Outside the base"
	else:
		_zone_label.text = "In the %s" % zone if not zone.is_empty() else "Somewhere in the colony"
	var show_power := _shows_room_power() and st.zones.has(zone)
	_power_label.visible = show_power
	_power_explain.visible = show_power
	if st.is_zone_powered(zone):
		_power_label.text = "✓ This room has power"
		_power_label.theme_type_variation = UiTheme.GOOD
	else:
		_power_label.text = "✖ This room has no power"
		_power_label.theme_type_variation = UiTheme.URGENT
	_refresh_equipment_switches(st)
	_refresh_body(st)


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
		return ["✖ No power: shed", &"urgent"]
	if id == "electrolyser" or id == "co2_unit":
		var status := String(st.oxygen_process.get(id, "off"))
		if status != "running" and status != "feed_short":
			return ["! Waiting: %s" % String(LifeSupportModel.STATUS_TEXT.get(status, status)), &"warn"]
	var kw := PowerModel.equipment_kw(st, balance, id, process_kw(st))
	return ["✓ On · uses %s kW" % num(kw, 2), &"ok"]


## The name of a piece of equipment in words ("Water recycler").
static func equipment_name(id: String) -> String:
	return words(String(PowerModel.LABELS.get(id, id)))


# ---------------------------------------------------------------- building

func _build_frame() -> void:
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	_title = Label.new()
	_title.text = "%s  %s" % [StationPanels.symbol_of(kind), _title_text()]
	_title.theme_type_variation = UiTheme.TITLE
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_title)
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(_close_button)

	var info := HBoxContainer.new()
	column.add_child(info)
	_zone_label = Label.new()
	_zone_label.theme_type_variation = UiTheme.MUTED
	_zone_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_zone_label)
	_power_label = Label.new()
	info.add_child(_power_label)
	_power_explain = ExplainButton.make("zones_power")
	info.add_child(_power_explain)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)

	_add_heading(_body, "What you can do here")
	for line in _what_you_can_do():
		_add_text(_body, "•  " + line)

	var readings_section := VBoxContainer.new()
	_body.add_child(readings_section)
	_add_heading(readings_section, "Readings")
	_readings_box = VBoxContainer.new()
	readings_section.add_child(_readings_box)

	_cause = Label.new()
	_cause.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cause.visible = false
	column.add_child(_cause)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.visible = false
	column.add_child(_message)
	var hint := Label.new()
	hint.theme_type_variation = UiTheme.MUTED
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "Press %s or %s to close." % [_key_name(&"interact", "E"), _key_name(&"back", "Esc")]
	column.add_child(hint)


## The words after the symbol in the header. Sun trackers add their number.
func _title_text() -> String:
	return StationPanels.name_of(kind)


## True: the header says whether the station's room has power. Stations outside have no room switch.
func _shows_room_power() -> bool:
	return true


## True: the "more controls later" note is shown (stations whose controls are not built yet).
func _shows_later_note() -> bool:
	return true


func _what_you_can_do() -> PackedStringArray:
	match kind:
		"computer":
			return PackedStringArray(["See the colony summary: stores, power and how long they last.",
				"Look at the upgrade cards for the facilities.", "Open the blueprint map of the base."])
		"comms":
			return PackedStringArray(["Read messages from Earth.", "Learn why a radio message to Earth takes minutes."])
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
			_add_reading(&"battery", "⚡", "Battery (colony electricity)", "battery")
			_add_reading(&"parts", "⚙", "Spare parts", "parts")
			_add_heading(_body, "Open")
			var buttons := HBoxContainer.new()
			_body.add_child(buttons)
			computer_buttons["summary"] = _add_open_button(buttons, "Colony summary", func() -> UiPanel: return ColonySummaryPanel.new())
			computer_buttons["upgrades"] = _add_open_button(buttons, "Upgrades", func() -> UiPanel: return UpgradeCardsPanel.new())
			computer_buttons["blueprint"] = _add_open_button(buttons, "Blueprint map", func() -> UiPanel: return BlueprintPanel.new())
		"comms":
			_add_heading(_body, "Messages from Earth")
			var card := PanelContainer.new()
			card.theme_type_variation = UiTheme.CARD
			_body.add_child(card)
			var list := VBoxContainer.new()
			card.add_child(list)
			_add_text(list, "Mission control: \"Welcome to Mars! Keep the lights on and the air fresh.\" (example message)")
			_add_text(list, "No new messages yet. Real messages arrive with the colony systems update.", UiTheme.MUTED)
			var why := HBoxContainer.new()
			_body.add_child(why)
			var why_text := _add_text(why, "Earth is very far away. A radio message travels as fast as light, but it still takes "
				+ "minutes to reach Earth, and the answer takes minutes to come back.")
			why_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			why.add_child(ExplainButton.make("sources"))
		"food":
			_add_reading(&"food", "❀", "Food in store", "food")
			_add_reading(&"food_use", "↓", "The crew eats", "stock_vs_flow")
			_add_reading(&"food_left", "⧗", "Food lasts", "food")
		"heal":
			var ids: Array = services.state().characters.keys()
			ids.sort()
			for id: StringName in ids:
				var c := services.state().character(id)
				var row := _add_reading(StringName("health_%s" % id), String(StationPanels.SPECIALTY_SYMBOLS.get(c.specialty, "●")), c.display_name, "health")
				_crew_rows[id] = row
		"board":
			_add_text(_body, "This is the transceiver board, the main part of the colony's long-range radio. "
				+ "It is damaged. Fixing it comes with a later update.")
		"survivor":
			_add_text(_body, "A patient is resting here. Keeping the Med Bay powered keeps them warm and the machines running.")
			_add_reading(&"med_bay_power", "⚡", "Med Bay power", "zones_power")


## Updates the station's own readings. The special station panels replace it.
func _refresh_body(st: ColonyState) -> void:
	var bal := services.balance
	var crew := float(st.active_characters().size())
	match kind:
		"computer":
			var battery := st.store(&"battery_kwh")
			var cap := float(st.capacities.get(&"battery_kwh", 0.0))
			_show_reading(&"battery", "%s of %s kWh" % [num(battery, 0), num(cap, 0)], stock_level(battery, cap))
			_show_reading(&"parts", "%d parts" % st.parts, &"ok" if st.parts > 0 else &"warn")
		"food":
			var food := st.store(&"food_meals")
			var cap := float(st.capacities.get(&"food_meals", 0.0))
			var per_sol := crew * bal.meals_per_sol
			_show_reading(&"food", "%s meals" % num(food, 0), stock_level(food, cap))
			_show_reading(&"food_use", "%s meals per sol" % num(per_sol, 1), &"ok")
			var left := time_left_text(food, per_sol / GameConfig.SOL_HOURS)
			_show_reading(&"food_left", left, _left_level(food, per_sol / GameConfig.SOL_HOURS))
		"heal":
			for id: StringName in _crew_rows:
				var c := st.character(id)
				if c == null:
					continue
				var row := _crew_rows[id] as Reading
				var who := "resting at the hub"
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
	readings[key] = row
	return row


func _show_reading(key: StringName, text: String, level: StringName) -> void:
	if readings.has(key):
		(readings[key] as Reading).set_value(text, level)


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
	var l := _add_heading(row, text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ExplainButton.make(explanation_id))
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


func _add_open_button(parent: Control, text: String, make_panel: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = UiTheme.PRIMARY_BUTTON
	b.pressed.connect(func() -> void: open_requested.emit(make_panel.call() as UiPanel))
	parent.add_child(b)
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
		_show_message("Asked the host…", UiTheme.MUTED)
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
	button.text = text if text != "" else equipment_switch_text(services.balance, id)
	button.set_pressed_no_signal(services.state().is_on(id))
	button.toggled.connect(_on_equipment_toggled.bind(id))
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
static func equipment_switch_text(balance: GameBalance, id: String) -> String:
	match id:
		"electrolyser":
			return "%s · up to %s kW" % [equipment_name(id), num(balance.electrolysis_o2_kg_per_hour * balance.electrolysis_kwh_per_kg_o2, 2)]
		"co2_unit":
			return "%s · up to %s kW" % [equipment_name(id), num(balance.co2_unit_o2_kg_per_hour * balance.co2_unit_kwh_per_kg_o2, 2)]
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


## Fills `box` with one line per alert ("✖ …", "! …", "• …"), or `none_text` when there are none.
func _fill_alerts(box: VBoxContainer, alerts: Array, none_text: String) -> void:
	var lines: Array = []
	if alerts.is_empty():
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
	_scroll.custom_minimum_size = Vector2(minf(760.0, screen.x * 0.55), minf(440.0, screen.y * 0.4))
