class_name PowerLifePanel
extends UiPanel
## "Power & life support": the drawer that opens on the right when you click a supply on the vitals bar or press P.
## Layout and behaviour from Uday's UI rebuild, drawn with the HUD's own pieces (HudKit pictograms, bars and text):
##   * Making, using and the battery as three bars on one scale, then one verdict sentence with a mark.
##   * Tabs: Supply (what makes power: the sun trackers, the battery when it covers a gap), Demand (every room and
##     machine that draws power, on or off), Life support (oxygen, water, food and the room air as states, then what
##     else is in store), Messages (the last pop-ups and Mission Control messages in full; hidden while empty).
##   * Live readings update persistent rows: a row only appears or disappears when its source does, so the open tab
##     and its scroll position stay put while the numbers change.
##   * The numbers with their units are behind the "123" button or key H (show_numbers), the same key that switches
##     the HUD strip to its numbers look. Without them the rows say states and words.
## It only shows: rooms and machines are switched at the power panel in the Power Room, by someone standing there.
## The ? opens the science. Text and pictures follow the text size setting (HudKit).

const Kit = preload("res://scripts/ui/menu_kit.gd")
const HudKit := preload("res://scripts/ui/hud/hud_kit.gd")
## Share of dust on the panels from which "Making" says "Dusty".
const DUSTY := 0.3
const MESSAGE_ICONS := {&"good": &"check", &"info": &"info", &"warn": &"warn", &"danger": &"danger"}
const TAB_SUPPLY := 0
const TAB_DEMAND := 1
const TAB_LIFE := 2
const TAB_MESSAGES := 3

## True: every row also shows its numbers with units. False: states and words.
var numbers := false

var _verdict: HudKit.Txt
var _verdict_icon: HudKit.Icon
var _verdict_box: PanelContainer
var _rows: Dictionary = {}          # state row id -> {"row", "icon", "name_col", "nums", "bar", "word", "mark", "color"}
var _lines: Dictionary = {}         # list line key -> {"row", "icon", "title", "sub", "value", "seen"}
var _pages: TabContainer
var _sources: VBoxContainer
var _loads: VBoxContainer
var _life: VBoxContainer
var _counts: HFlowContainer
var _messages: VBoxContainer
var _numbers_button: Button
var _close: Button
var _counts_sig := ""
var _messages_sig := ""
var _verdict_tone := ""


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	name = "PowerLifePanel"
	align_right = true
	max_width = 700
	accent_line = false
	add_theme_stylebox_override(&"panel", AstraStyle.glass(AstraStyle.RADIUS, 18, 16, true))
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	add_child(box)
	var head := HBoxContainer.new()
	head.name = "Header"
	head.add_theme_constant_override(&"separation", 10)
	box.add_child(head)
	head.add_child(HudKit.Icon.new(&"power", AstraStyle.C_POWER, 34.0, "Symbol"))
	var title := HudKit.Txt.new("Power & life support", 26.0, AstraStyle.TEXT, "Title", true)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = 180
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_numbers_button = Button.new()
	_numbers_button.name = "Numbers"
	_numbers_button.text = "123"
	_numbers_button.toggle_mode = true
	_numbers_button.tooltip_text = "Show the numbers (%s)" % _key(&"hud_details", "U")
	_numbers_button.accessibility_name = "Show the numbers"
	_numbers_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_numbers_button.toggled.connect(show_numbers)
	head.add_child(_numbers_button)
	var help := Button.new()
	help.name = "Help"
	help.text = "?"
	help.tooltip_text = "The science behind these numbers"
	help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	help.pressed.connect(func() -> void:
		var p := VitalsSciencePanel.new()
		open_requested.emit(p))
	head.add_child(help)
	_close = Button.new()
	_close.name = "Close"
	_close.custom_minimum_size = Vector2(48, 44)
	_close.draw.connect(func() -> void:
		var s := minf(_close.size.x, _close.size.y) * 0.4
		HudKit.draw_icon(_close, &"close", Rect2((_close.size - Vector2(s, s)) * 0.5, Vector2(s, s)), UiTheme.palette().text))
	_close.tooltip_text = "Close (Esc or %s)" % _key(&"power_view", "P")
	_close.accessibility_name = "Close"
	_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(_close)

	# making, using and the battery on one card
	var meters := AstraStyle.panel(AstraStyle.pill(Color(1, 1, 1, 0.04), AstraStyle.RADIUS_SM + 2, 14, 12, AstraStyle.LINE), "Balance")
	box.add_child(meters)
	var meter_list := VBoxContainer.new()
	meter_list.add_theme_constant_override(&"separation", 10)
	meters.add_child(meter_list)
	_state_row(meter_list, "making", &"sun", "Making", AstraStyle.C_POWER)
	_state_row(meter_list, "using", &"power", "Using", AstraStyle.ACCENT)
	_state_row(meter_list, "battery_kwh", &"battery", "Battery", AstraStyle.GOOD)

	# the verdict: one mark and one short sentence
	_verdict_box = AstraStyle.panel(AstraStyle.pill(Color(AstraStyle.GOOD, 0.12), AstraStyle.RADIUS_SM, 12, 8), "Verdict")
	_verdict_box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_verdict_box)
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override(&"separation", 12)
	vrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_verdict_box.add_child(vrow)
	_verdict_icon = HudKit.Icon.new(&"check", AstraStyle.GOOD, 32.0, "Mark")
	vrow.add_child(_verdict_icon)
	_verdict = HudKit.Txt.new("", 20.0, AstraStyle.TEXT, "Text")
	_verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_verdict.custom_minimum_size.x = 200
	_verdict.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vrow.add_child(_verdict)

	# the tabs
	_pages = UiComposition.tabs(box)
	_pages.name = "Pages"
	var supply := UiComposition.page(_pages, "Supply")
	var demand := UiComposition.page(_pages, "Demand")
	var life := UiComposition.page(_pages, "Life support")
	var messages := UiComposition.page(_pages, "Messages")
	supply.add_child(_section("Making power"))
	_sources = _list(supply, "Sources")
	demand.add_child(_section("Using power"))
	_loads = _list(demand, "Loads")
	var note := HudKit.Txt.new("Switch things at the Power Room panel.", 16.0, AstraStyle.TEXT_2, "Note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudKit.say(note, "Rooms and machines are switched at the power panel in the Power Room, by someone standing there.")
	note.mouse_filter = Control.MOUSE_FILTER_PASS
	demand.add_child(note)
	life.add_child(_section("Life support today"))
	_life = _list(life, "Supplies")
	for s: Dictionary in VitalsBar.STOCKS:
		if s.key != &"battery_kwh":
			_state_row(_life, String(s.key), s.icon, String(s.name), s.color)
	_state_row(_life, "cabin", &"home", "Room air", AstraStyle.C_O2)
	life.add_child(_section("Also in store"))
	_counts = HFlowContainer.new()
	_counts.name = "Counts"
	_counts.add_theme_constant_override(&"h_separation", 10)
	_counts.add_theme_constant_override(&"v_separation", 6)
	life.add_child(_counts)
	messages.add_child(_section("Latest messages"))
	_messages = _list(messages, "MessageList")
	_pages.set_tab_hidden(TAB_MESSAGES, true)


func panel_title() -> String:
	return "Power & life support"


func first_focus() -> Control:
	return _close


## True: the numbers look (amounts with units, kW of every room and machine). False: states only.
func show_numbers(on: bool) -> void:
	numbers = on
	if _numbers_button.button_pressed != on:
		_numbers_button.set_pressed_no_signal(on)
	refresh()


## The state word a row shows now ("OK", "Low", "Very low", "Dusty"...). Row ids: "battery_kwh", the three life
## support stock keys, "cabin", "making", "using".
func state_word(row_id: String) -> String:
	return (_rows[row_id].word as Label).text if _rows.has(row_id) else ""


## The verdict sentence now shown (nine words at most).
func verdict_text() -> String:
	return _verdict.text


## The tabs (Supply, Demand, Life support, Messages), for tests and tools.
func pages() -> TabContainer:
	return _pages


func _list(parent: Control, node_name: String) -> VBoxContainer:
	var l := VBoxContainer.new()
	l.name = node_name
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_constant_override(&"separation", 10)
	parent.add_child(l)
	return l


## One state row: picture, name (numbers under it in the numbers look), level bar, state word, low mark.
func _state_row(parent: Control, id: String, icon_kind: StringName, title: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.name = "Row_" + id
	row.add_theme_constant_override(&"separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(row)
	# "home" is a menu-kit pictogram (the rooms of the base); the others are the HUD strip's own
	var icon: Control = Kit.picture(icon_kind, 30.0, color) if icon_kind == &"home" else HudKit.Icon.new(icon_kind, color, 30.0, "Symbol")
	row.add_child(icon)
	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override(&"separation", -2)
	name_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_col)
	name_col.add_child(HudKit.Txt.new(title, 20.0, AstraStyle.TEXT, "Name"))
	var nums := HudKit.Txt.new("", 16.0, AstraStyle.TEXT_2, "Numbers")
	nums.visible = false
	name_col.add_child(nums)
	var bar := HudKit.Bar.new(color, Vector2(90, 16), "Fill")
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	var word := HudKit.Txt.new("", 20.0, AstraStyle.TEXT, "Word", true)
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(word)
	var mark := HudKit.Icon.new(&"warn", AstraStyle.WARN, 24.0, "Mark")
	row.add_child(mark)
	_rows[id] = {"row": row, "icon": icon, "name_col": name_col, "nums": nums, "bar": bar, "word": word, "mark": mark, "color": color}


## Fills a state row. `level`: &"ok", &"warn" or &"urgent".
func _set_row(id: String, share: float, level: StringName, word: String, nums: String, words := "") -> void:
	var r: Dictionary = _rows[id]
	var s := HudKit.scale()
	var col: Color = HudKit.level_color(level, r.color)
	var attention := level != &"ok"
	(r.bar as HudKit.Bar).share = share
	(r.bar as HudKit.Bar).color = col
	if r.icon is HudKit.Icon:
		(r.icon as HudKit.Icon).color = col
	else:
		var look := "%s|%s" % [col, s]
		if String((r.icon as Control).get_meta(&"look", "")) != look:
			(r.icon as Control).set_meta(&"look", look)
			(r.icon as TextureRect).texture = Kit.pic(&"home", roundf(30.0 * s), col)
	(r.name_col as Control).custom_minimum_size.x = roundf((204.0 if numbers else 118.0) * s)      # the bars line up
	var w := r.word as HudKit.Txt
	w.text = word
	w.custom_minimum_size.x = roundf(92.0 * s)
	w.tint(col if attention else AstraStyle.TEXT_2)
	var mark := r.mark as HudKit.Icon
	mark.kind = StringName(HudKit.LEVEL_MARK.get(level, &"warn"))
	mark.color = col
	mark.modulate.a = 1.0 if attention else 0.0          # keeps its place, so the columns line up
	var n := r.nums as HudKit.Txt
	n.text = nums
	n.visible = numbers and nums != ""
	HudKit.say(r.row as Control, words if words != "" else "%s: %s. %s" % [(r.name_col.get_node("Name") as Label).text, word, nums])


func _section(text: String) -> HudKit.Txt:
	return HudKit.Txt.new(text, 16.0, AstraStyle.TEXT_3, "", true)


## A persistent line of the lists: mark, name with a description under it (both wrapping), and a value on the right.
## The same `parent` and `title` reuse the same row, so live updates only change its words and colours.
func _line(parent: Control, icon_kind: StringName, color: Color, title: String, sub: String, value: String, value_color: Color) -> Control:
	var key := "%s/%s" % [parent.get_instance_id(), title]
	var e: Dictionary = _lines.get(key, {})
	if e.is_empty():
		var row := HBoxContainer.new()
		row.name = title.validate_node_name()
		row.add_theme_constant_override(&"separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		parent.add_child(row)
		var icon := HudKit.Icon.new(icon_kind, color, 24.0, "Symbol")
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(icon)
		var col := VBoxContainer.new()
		col.add_theme_constant_override(&"separation", 2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		var t := HudKit.Txt.new(title, 18.0, AstraStyle.TEXT, "Name")
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size.x = 120
		col.add_child(t)
		var d := HudKit.Txt.new(sub, 16.0, AstraStyle.TEXT_2, "Description")
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(d)
		var v := HudKit.Txt.new(value, 18.0, value_color, "Amount", true)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(v)
		e = {"row": row, "icon": icon, "title": t, "sub": d, "value": v}
		_lines[key] = e
	e["seen"] = true
	(e.row as Control).show()
	(e.icon as HudKit.Icon).kind = icon_kind
	(e.icon as HudKit.Icon).color = color
	(e.title as Label).text = title
	(e.sub as Label).text = sub
	(e.sub as Label).visible = sub != ""
	(e.value as Label).text = value
	(e.value as Label).visible = value != ""
	(e.value as Label).custom_minimum_size.x = roundf(96.0 * HudKit.scale()) if value != "" else 0.0
	(e.value as HudKit.Txt).tint(value_color)
	return e.row


func refresh() -> void:
	if services == null or not services.has_game() or _verdict == null:
		return
	var st := services.state()
	var b := services.balance
	var forecast := ReserveForecast.compute(st, b, services.clock())
	var day := services.clock().is_daylight()

	# making, using and the battery, on one scale
	var dust := 0.0
	for d: Variant in st.panel_dust:
		dust += float(d)
	dust = dust / maxf(1.0, st.panel_dust.size())
	var top := maxf(maxf(st.solar_kw, st.load_kw), 0.1)
	var dusty := day and dust >= DUSTY
	_set_row("making", st.solar_kw / top, &"warn" if dusty else &"ok", "Night" if not day else ("Dusty" if dusty else "Sun"),
		"+%s kW · dust %d %%" % [ColonySummaryPanel.num(st.solar_kw), roundi(dust * 100.0)] if day else "0 kW · no sunlight",
		"Making %s kW. %s" % [ColonySummaryPanel.num(st.solar_kw), ("Dust on the panels: %d %%." % roundi(dust * 100.0)) if day else "Night: no sunlight, no power."])
	_set_row("using", st.load_kw / top, &"urgent" if st.power_deficit else &"ok", "Too much" if st.power_deficit else "",
		"%s kW" % ColonySummaryPanel.num(st.load_kw) + (" · battery +%s kW" % ColonySummaryPanel.num(-st.battery_kw) if st.battery_kw < -0.05 else ""),
		"Using %s kW." % ColonySummaryPanel.num(st.load_kw))
	var cap := float(st.capacities.get(&"battery_kwh", 0.0))
	var stored := st.store(&"battery_kwh")
	var bat_level := ColonySummaryPanel.level_of(services, &"battery_kwh")
	_set_row("battery_kwh", stored / cap if cap > 0.0 else 0.0, bat_level, ColonySummaryPanel.level_word(bat_level),
		"%d/%d kWh" % [roundi(stored), roundi(cap)])

	# the verdict
	var verdict := "Making exactly what you use."
	var full := verdict
	var tone := &"good"
	if st.power_deficit:
		verdict = "Not enough power! Switch something off."
		full = "Not enough power! Some rooms or machines are going without. Switch off what you do not need at the power panel."
		tone = &"danger"
	elif st.battery_kw > 0.05:
		verdict = "The battery is charging."
		full = "Making more than you use: the battery is charging."
	elif st.battery_kw < -0.05:
		var h := float(forecast.get("battery_hours", -1.0))
		var left := VitalsBar._left_words(h) if h >= 0.0 and h < 1000.0 else ""
		verdict = "The battery is draining." if day else "Night: the battery is draining."
		full = "Using more than you make: the battery is draining%s." % (" and lasts about %s at this rate" % left if left != "" else "")
		if not day:
			full += " It is night: the panels make nothing until sunrise."
		if left != "" and (numbers or bat_level != &"ok"):
			verdict += " About %s left." % left
		tone = &"warn"
	_verdict.text = verdict
	HudKit.say(_verdict_box, full)
	if String(tone) != _verdict_tone:
		_verdict_tone = String(tone)
		var vc: Color = HudKit.level_color(tone)
		_verdict_icon.kind = &"check" if tone == &"good" else tone
		_verdict_icon.color = vc
		_verdict_box.add_theme_stylebox_override(&"panel", AstraStyle.pill(Color(vc, 0.14), AstraStyle.RADIUS_SM, 12, 8, Color(vc, 0.6)))

	# the life support supplies as states
	for s: Dictionary in VitalsBar.STOCKS:
		var key: StringName = s.key
		if key == &"battery_kwh":
			continue
		var amount := st.store(key)
		var scap := float(st.capacities.get(key, 0.0))
		var level := ColonySummaryPanel.level_of(services, key)
		var per_sol := float(st.rates.get(String(key), 0.0)) * GameConfig.SOL_HOURS
		var nums := "%s %s · %s%s %s/sol" % [VitalsBar._amount(key, amount), s.unit, "+" if per_sol >= 0.0 else "", ColonySummaryPanel.num(per_sol), s.unit]
		_set_row(String(key), amount / scap if scap > 0.0 else 0.0, level, ColonySummaryPanel.level_word(level), nums)
	var kpa := StationPanel.cabin_kpa(st, b)
	var o2_level := StationPanel.o2_level(float(kpa.o2), b)
	var co2_level := StationPanel.co2_level(float(kpa.co2), b)
	var air_level := o2_level
	var air_word := ColonySummaryPanel.level_word(o2_level)
	if co2_level != &"ok" and (o2_level == &"ok" or co2_level == &"urgent"):
		air_level = co2_level
		air_word = "CO₂ high"
	var air_nums := "O₂ %s kPa · CO₂ %s kPa" % [StationPanel.num(float(kpa.o2), 1), StationPanel.num(float(kpa.co2), 2)]
	_set_row("cabin", clampf(float(kpa.o2) / maxf(b.o2_setpoint_kpa, 1e-6), 0.0, 1.0), air_level, air_word, air_nums,
		"Room air: oxygen %s kPa (%s), carbon dioxide %s kPa (%s)." % [StationPanel.num(float(kpa.o2), 1),
		StationPanel.o2_word(o2_level).to_lower(), StationPanel.num(float(kpa.co2), 2), StationPanel.co2_word(co2_level).to_lower()])

	# Supply and Demand: persistent rows (live telemetry must not reset the open tab or its scroll position)
	for e: Dictionary in _lines.values():
		e["seen"] = false
	_line(_sources, &"sun", AstraStyle.C_POWER, "Sun trackers (%d)" % ColonyState.TRACKER_COUNT,
		("Electricity while the Sun shines · dust on the panels %d %%" % roundi(dust * 100.0)) if day else "Night: no sunlight, no power",
		"+%s kW" % ColonySummaryPanel.num(st.solar_kw) if numbers else ("Dusty" if dusty else ("Making" if day else "Night")),
		AstraStyle.WARN if dusty else AstraStyle.C_POWER)
	if st.battery_kw < -0.05:
		_line(_sources, &"battery", AstraStyle.GOOD, "Battery", "Covering the gap",
			"+%s kW" % ColonySummaryPanel.num(-st.battery_kw) if numbers else "Draining", AstraStyle.GOOD)
	var zones: Array = st.zones.keys()
	zones.sort()
	for zone: String in zones:
		var on := st.is_zone_powered(zone)
		var kw := b.load_of_zone(zone)
		if kw <= 0.0:
			continue
		_line(_loads, &"dot" if on else &"close", AstraStyle.ACCENT if on else AstraStyle.TEXT_3, zone,
			"Lights and room systems" if on else "Switched off",
			("%s kW" % ColonySummaryPanel.num(kw) if numbers else "On") if on else "Off", AstraStyle.TEXT if on else AstraStyle.TEXT_2)
	for id: String in ColonyState.EQUIPMENT_IDS:
		var e: Dictionary = st.equipment.get(id, {})
		if e.is_empty():
			continue
		var on2 := bool(e.get("on", false))
		var powered := bool(e.get("powered", false))
		var row: Control
		if on2 and not powered:
			row = _line(_loads, &"danger", AstraStyle.DANGER, StationPanel.equipment_name(id), "Switched on but getting no power", "No power!", AstraStyle.DANGER)
		else:
			row = _line(_loads, &"dot" if on2 else &"close", AstraStyle.C_O2 if on2 else AstraStyle.TEXT_3, StationPanel.equipment_name(id),
				"Running" if on2 else "Switched off",
				("%s kW" % ColonySummaryPanel.num(float(e.get("kw", 0.0))) if numbers else "On") if on2 else "Off",
				AstraStyle.TEXT if on2 else AstraStyle.TEXT_2)
		# the science name of the oxygen machines is the line's tooltip
		row.tooltip_text = StationPanel.equipment_tip(id)
	for e: Dictionary in _lines.values():
		if not bool(e.get("seen", false)):
			(e.row as Control).hide()

	# store chips and messages: rebuilt only when they changed (they are not live telemetry)
	var counts := VitalsBar.extra_counts(st)
	var counts_sig := JSON.stringify(counts)
	if counts_sig != _counts_sig:
		_counts_sig = counts_sig
		_clear(_counts)
		for c: Dictionary in counts:
			var chip := AstraStyle.panel(AstraStyle.pill(Color(c.color, 0.14), AstraStyle.RADIUS_SM, 10, 4, Color(c.color, 0.4)), "")
			chip.mouse_filter = Control.MOUSE_FILTER_PASS
			HudKit.say(chip, "%s: %s. %s" % [c.name, c.value, c.note])
			var h := HBoxContainer.new()
			h.add_theme_constant_override(&"separation", 8)
			h.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(h)
			var sym := HudKit.Txt.new(String(c.symbol), 20.0, c.color)
			sym.add_theme_font_override(&"font", AstraStyle.symbol_font())
			h.add_child(sym)
			h.add_child(HudKit.Txt.new(String(c.value), 20.0, AstraStyle.TEXT, "", true))
			h.add_child(HudKit.Txt.new(String(c.name), 18.0, AstraStyle.TEXT_2))
			_counts.add_child(chip)
	var recent := ToastStack.recent()
	var messages_sig := JSON.stringify(recent)
	if messages_sig != _messages_sig:
		_messages_sig = messages_sig
		_clear(_messages)
		for i in range(recent.size() - 1, -1, -1):          # newest first
			var m: Dictionary = recent[i]
			var kind := StringName(m.get("kind", &"info"))
			_message_line(_messages, StringName(MESSAGE_ICONS.get(kind, &"info")),
				HudKit.level_color(kind, AstraStyle.GOOD if kind == &"good" else AstraStyle.C_O2), String(m.text))
		_pages.set_tab_hidden(TAB_MESSAGES, recent.is_empty())


func _message_line(parent: Control, icon_kind: StringName, color: Color, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	parent.add_child(row)
	var icon := HudKit.Icon.new(icon_kind, color, 22.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var t := HudKit.Txt.new(text, 18.0, AstraStyle.TEXT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 120
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)


static func _clear(holder: Control) -> void:
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"power_view"):
		# Closing takes this panel out of the tree at once: mark the key handled first.
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
		close_requested.emit()
	elif event.is_action_pressed(&"hud_details"):
		get_viewport().set_input_as_handled()
		show_numbers(not numbers)


static func _key(action: StringName, fallback: String) -> String:
	var k := PlayerInput.describe(action)
	return k if k != "" and not k.contains("/") else fallback
