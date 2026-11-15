class_name PowerLifePanel
extends UiPanel
## "Power & life support": the drawer that opens on the right when you click a supply on the vitals bar or press P.
## UI overhaul (2026-11-15): it leads with states, like the HUD strip.
##   * One sentence of at most nine words with a mark: is the colony making enough power right now?
##   * One row per supply (battery, oxygen, water, food, room air): picture, name, level bar and a word (OK / Low /
##     Very low) with the low mark (triangle = low, octagon = very low). Then making against using as two bars.
##   * "Switched off": only the rooms and machines that are off or without power (nothing to read while all is well).
##   * The numbers with their units (kWh, kW, kg per sol, kPa, the kW of every room and machine) are behind the "123"
##     button or key H (show_numbers), the same key that switches the HUD strip to its numbers look.
##   * "Also in store": spare parts, science score and ore (once counters on the strip).
##   * "Messages": the last pop-ups and Mission Control messages in full (the HUD shows one short line of each).
## It only shows: rooms and machines are switched at the power panel in the Power Room, by someone standing there.
## The ? opens the science. Text and pictures follow the text size setting (HudKit).

const Kit = preload("res://scripts/ui/menu_kit.gd")
const HudKit := preload("res://scripts/ui/hud/hud_kit.gd")
## Share of dust on the panels from which "Making" says "Dusty".
const DUSTY := 0.3
const MESSAGE_ICONS := {&"good": &"check", &"info": &"info", &"warn": &"warn", &"danger": &"danger"}

## True: every row also shows its numbers with units, and every room and machine is listed with its kW.
var numbers := false

var _verdict: HudKit.Txt
var _verdict_icon: HudKit.Icon
var _verdict_box: PanelContainer
var _rows: Dictionary = {}          # row id -> {"icon", "name_col", "nums", "bar", "word", "mark"}
var _loads_title: HudKit.Txt
var _loads: VBoxContainer
var _counts: HFlowContainer
var _messages_title: HudKit.Txt
var _messages: VBoxContainer
var _numbers_button: Button
var _close: Button
var _sig := ""
var _verdict_tone := ""


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	name = "PowerLifePanel"
	align_right = true
	max_width = 640
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
	_numbers_button.tooltip_text = "Show the numbers (%s)" % _key(&"hud_details", "H")
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

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	box.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override(&"separation", 10)
	scroll.add_child(content)

	# the verdict: one mark and one short sentence
	_verdict_box = AstraStyle.panel(AstraStyle.pill(Color(AstraStyle.GOOD, 0.12), AstraStyle.RADIUS_SM, 12, 8), "Verdict")
	_verdict_box.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(_verdict_box)
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override(&"separation", 12)
	vrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_verdict_box.add_child(vrow)
	_verdict_icon = HudKit.Icon.new(&"check", AstraStyle.GOOD, 36.0, "Mark")
	vrow.add_child(_verdict_icon)
	_verdict = HudKit.Txt.new("", 22.0, AstraStyle.TEXT, "Text")
	_verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_verdict.custom_minimum_size.x = 200
	_verdict.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vrow.add_child(_verdict)

	# the supplies as states
	var states := AstraStyle.panel(AstraStyle.pill(Color(1, 1, 1, 0.04), AstraStyle.RADIUS_SM + 2, 14, 12, AstraStyle.LINE), "Supplies")
	content.add_child(states)
	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 10)
	states.add_child(list)
	for s: Dictionary in VitalsBar.STOCKS:
		_state_row(list, String(s.key), s.icon, "Battery" if s.key == &"battery_kwh" else String(s.name), s.color)
	_state_row(list, "cabin", &"home", "Room air", AstraStyle.C_O2)
	content.add_child(_section("Power right now"))
	var flow := AstraStyle.panel(AstraStyle.pill(Color(1, 1, 1, 0.04), AstraStyle.RADIUS_SM + 2, 14, 12, AstraStyle.LINE), "Balance")
	content.add_child(flow)
	var flow_list := VBoxContainer.new()
	flow_list.add_theme_constant_override(&"separation", 10)
	flow.add_child(flow_list)
	_state_row(flow_list, "making", &"sun", "Making", AstraStyle.C_POWER)
	_state_row(flow_list, "using", &"power", "Using", AstraStyle.ACCENT)

	_loads_title = _section("Switched off")
	content.add_child(_loads_title)
	_loads = VBoxContainer.new()
	_loads.name = "Loads"
	_loads.add_theme_constant_override(&"separation", 6)
	content.add_child(_loads)
	var note := HudKit.Txt.new("Switch things at the Power Room panel.", 16.0, AstraStyle.TEXT_2, "Note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudKit.say(note, "Rooms and machines are switched at the power panel in the Power Room, by someone standing there.")
	note.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(note)
	content.add_child(_section("Also in store"))
	_counts = HFlowContainer.new()
	_counts.name = "Counts"
	_counts.add_theme_constant_override(&"h_separation", 10)
	_counts.add_theme_constant_override(&"v_separation", 6)
	content.add_child(_counts)
	_messages_title = _section("Messages")
	content.add_child(_messages_title)
	_messages = VBoxContainer.new()
	_messages.name = "Messages"
	_messages.add_theme_constant_override(&"separation", 8)
	content.add_child(_messages)


func panel_title() -> String:
	return "Power & life support"


func first_focus() -> Control:
	return _close


## True: the numbers look (amounts with units, kW of every room and machine). False: states only.
func show_numbers(on: bool) -> void:
	numbers = on
	if _numbers_button.button_pressed != on:
		_numbers_button.set_pressed_no_signal(on)
	_sig = ""
	refresh()


## The state word a row shows now ("OK", "Low", "Very low", "Dusty"...). Row ids: the four stock keys, "cabin",
## "making", "using".
func state_word(row_id: String) -> String:
	return (_rows[row_id].word as Label).text if _rows.has(row_id) else ""


## The verdict sentence now shown (nine words at most).
func verdict_text() -> String:
	return _verdict.text


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


## A line of the lists: mark, words (wrapping), and a value on the right.
func _line(parent: Control, icon_kind: StringName, color: Color, title: String, value: String, value_color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	parent.add_child(row)
	var icon := HudKit.Icon.new(icon_kind, color, 22.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var t := HudKit.Txt.new(title, 18.0, AstraStyle.TEXT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 120
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	if value != "":
		row.add_child(HudKit.Txt.new(value, 18.0, value_color, "", true))


func refresh() -> void:
	if services == null or not services.has_game() or _verdict == null:
		return
	var st := services.state()
	var b := services.balance
	var forecast := ReserveForecast.compute(st, b, services.clock())
	var day := services.clock().is_daylight()

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
		if left != "" and (numbers or ColonySummaryPanel.level_of(services, &"battery_kwh") != &"ok"):
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

	# the supplies
	for s: Dictionary in VitalsBar.STOCKS:
		var key: StringName = s.key
		var amount := st.store(key)
		var cap := float(st.capacities.get(key, 0.0))
		var level := ColonySummaryPanel.level_of(services, key)
		var nums := ""
		if key == &"battery_kwh":
			nums = "%d/%d kWh" % [roundi(amount), roundi(cap)]
		else:
			var per_sol := float(st.rates.get(String(key), 0.0)) * GameConfig.SOL_HOURS
			nums = "%s %s · %s%s %s/sol" % [VitalsBar._amount(key, amount), s.unit, "+" if per_sol >= 0.0 else "", ColonySummaryPanel.num(per_sol), s.unit]
		_set_row(String(key), amount / cap if cap > 0.0 else 0.0, level, ColonySummaryPanel.level_word(level), nums)
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

	# making against using, on one scale
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

	# the lists: rebuilt only when something in them changed
	var recent := ToastStack.recent()
	var sig := "%s|%s|%s|%s|%s|%s|%s" % [numbers, JSON.stringify(st.zones), JSON.stringify(st.equipment), st.parts,
		JSON.stringify(st.scout.get("ores", {})), ScoutSystem.science_points(st), JSON.stringify(recent)]
	if sig == _sig:
		return
	_sig = sig
	for holder: Control in [_loads, _counts, _messages]:
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
	_loads_title.text = "Using power" if numbers else "Switched off"
	var zones: Array = st.zones.keys()
	zones.sort()
	for zone: String in zones:
		var on := st.is_zone_powered(zone)
		var kw := b.load_of_zone(zone)
		if kw <= 0.0 or (on and not numbers):
			continue
		_line(_loads, &"dot" if on else &"close", AstraStyle.ACCENT if on else AstraStyle.TEXT_3, zone,
			("%s kW" % ColonySummaryPanel.num(kw) if on else "Off") if numbers else "Off", AstraStyle.TEXT if on else AstraStyle.TEXT_2)
	for id: String in ColonyState.EQUIPMENT_IDS:
		var e: Dictionary = st.equipment.get(id, {})
		if e.is_empty():
			continue
		var on2 := bool(e.get("on", false))
		var powered := bool(e.get("powered", false))
		if on2 and powered and not numbers:
			continue
		if on2 and not powered:
			_line(_loads, &"danger", AstraStyle.DANGER, StationPanel.equipment_name(id), "No power!", AstraStyle.DANGER)
		else:
			_line(_loads, &"dot" if on2 else &"close", AstraStyle.C_O2 if on2 else AstraStyle.TEXT_3, StationPanel.equipment_name(id),
				"%s kW" % ColonySummaryPanel.num(float(e.get("kw", 0.0))) if on2 else "Off", AstraStyle.TEXT if on2 else AstraStyle.TEXT_2)
		# the science name of the oxygen machines is the line's tooltip
		if StationPanel.equipment_tip(id) != "":
			(_loads.get_child(_loads.get_child_count() - 1) as Control).tooltip_text = StationPanel.equipment_tip(id)
	if _loads.get_child_count() == 0:
		_line(_loads, &"check", AstraStyle.GOOD, "Everything is switched on.", "", AstraStyle.TEXT)
	for c: Dictionary in VitalsBar.extra_counts(st):
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
	_messages_title.visible = not recent.is_empty()
	for i in range(recent.size() - 1, -1, -1):          # newest first
		var m: Dictionary = recent[i]
		var kind := StringName(m.get("kind", &"info"))
		_line(_messages, StringName(MESSAGE_ICONS.get(kind, &"info")),
			HudKit.level_color(kind, AstraStyle.GOOD if kind == &"good" else AstraStyle.C_O2), String(m.text), "", AstraStyle.TEXT)


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
