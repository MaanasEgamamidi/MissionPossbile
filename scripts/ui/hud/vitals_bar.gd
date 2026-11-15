class_name VitalsBar
extends PanelContainer
## The colony's four supplies along the top of the screen: electricity, air (oxygen), water and food.
## UI overhaul (2026-11-15): each supply is ONE picture and ONE small level bar, and nothing else while it is fine.
##   * A supply that needs attention grows a number with its unit and a mark (triangle = low, octagon = very low) and
##     turns amber or red: colour is never the only cue.
##   * Key H (hud_details) switches the numbers on for all four ("numbers look": amount, unit and which way it is
##     going: "▲ rising", "▼ 2.1 sols" until it runs out, "▲ +2.4 kW"), and off again. `compact` is the calm look.
##   * Clicking a supply (or key P) opens the Power & life support drawer; spare parts, the science score and the ore
##     (once counters on this strip) are listed there now: see extra_counts().
## Every picture has its words as tooltip and accessible name ("Electricity: 562 kWh. Charging at 6.9 kW. …").
## Read only: it never changes anything.

signal details_requested
signal help_requested
signal compact_changed(compact: bool)

const HudKit := preload("res://scripts/ui/hud/hud_kit.gd")
const STOCKS := [
	{"key": &"battery_kwh", "symbol": "⚡", "icon": &"power", "name": "Electricity", "unit": "kWh", "color": AstraStyle.C_POWER},
	{"key": &"oxygen_kg", "symbol": "O₂", "icon": &"air", "name": "Oxygen", "unit": "kg", "color": AstraStyle.C_O2},
	{"key": &"water_l", "symbol": "≈", "icon": &"water", "name": "Water", "unit": "L", "color": AstraStyle.C_WATER},
	{"key": &"food_meals", "symbol": "✿", "icon": &"food", "name": "Food", "unit": "meals", "color": AstraStyle.C_FOOD},
]

var services: GameServices
## True (the look a game starts with): pictures and level bars only. False: the numbers look (key H).
var compact := true

var _row: HBoxContainer
var _items: Dictionary = {}      # key -> {"box", "icon", "meter", "nums", "value", "unit", "trend", "mark", "spec"}


func setup(p_services: GameServices) -> void:
	services = p_services
	name = "VitalsBar"
	_restyle()
	mouse_filter = Control.MOUSE_FILTER_PASS
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.add_theme_constant_override(&"separation", 4)
	add_child(_row)
	for s: Dictionary in STOCKS:
		_items[s.key] = _make_item(s)
	refresh()


func _restyle() -> void:
	# noted first: the override below sends THEME_CHANGED, which must see the new value or it restyles forever
	set_meta(&"contrast", UiTheme.is_high_contrast())
	var s := AstraStyle.glass(AstraStyle.RADIUS, 8, 6)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	if UiTheme.is_high_contrast():
		s.set_border_width_all(2)
	add_theme_stylebox_override(&"panel", s)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and has_meta(&"contrast") and bool(get_meta(&"contrast")) != UiTheme.is_high_contrast():
		_restyle()


func _make_item(s: Dictionary) -> Dictionary:
	var box := PanelContainer.new()
	box.name = String(s.key)
	box.add_theme_stylebox_override(&"panel", AstraStyle.pill(Color(1, 1, 1, 0.0), AstraStyle.RADIUS_SM, 8, 4))
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	box.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			details_requested.emit())
	_row.add_child(box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	var icon := HudKit.Icon.new(s.icon, s.color, 30.0, "Symbol")
	line.add_child(icon)
	var meter := HudKit.Bar.new(s.color, Vector2(92, 16), "Fill")
	line.add_child(meter)
	var nums := VBoxContainer.new()
	nums.name = "Numbers"
	nums.add_theme_constant_override(&"separation", -4)
	nums.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nums.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(nums)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nums.add_child(top)
	var value := HudKit.Txt.new("0", 22.0, AstraStyle.TEXT, "Value", true)
	top.add_child(value)
	var unit := HudKit.Txt.new(String(s.unit), 16.0, AstraStyle.TEXT_2, "Unit")
	unit.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	top.add_child(unit)
	var trend := HudKit.Txt.new("steady", 15.0, AstraStyle.TEXT_2, "Trend")
	trend.add_theme_font_override(&"font", AstraStyle.symbol_font())
	nums.add_child(trend)
	var mark := HudKit.Icon.new(&"warn", AstraStyle.WARN, 22.0, "Mark")
	line.add_child(mark)
	return {"box": box, "icon": icon, "meter": meter, "nums": nums, "value": value, "unit": unit, "trend": trend, "mark": mark, "spec": s}


func toggle_compact() -> void:
	set_compact(not compact)


## True: pictures and bars only. False: the numbers look.
func set_compact(on: bool) -> void:
	if on == compact:
		return
	compact = on
	refresh()
	reset_size()
	compact_changed.emit(compact)


## Re-reads the colony. The HUD calls it a few times a second.
func refresh() -> void:
	if services == null or not services.has_game():
		return
	var st := services.state()
	var forecast := ReserveForecast.compute(st, services.balance, services.clock())
	for s: Dictionary in STOCKS:
		var it: Dictionary = _items[s.key]
		var key: StringName = s.key
		var amount := st.store(key)
		var cap := float(st.capacities.get(key, 0.0))
		var share := amount / cap if cap > 0.0 else 0.0
		var level := ColonySummaryPanel.level_of(services, key)
		var attention := level != &"ok"
		var col: Color = HudKit.level_color(level, s.color)
		var value := it.value as Label
		var unit := it.unit as Label
		var trend := it.trend as Label
		var t := _trend(st, key, forecast)
		if compact and key == &"battery_kwh":
			# a low battery reads best as a share
			value.text = "%d" % roundi(share * 100.0)
			unit.text = "%"
		else:
			value.text = _amount(key, amount)
			unit.text = ("/%d %s" % [roundi(cap), s.unit]) if key == &"battery_kwh" else String(s.unit)
		# numbers: always in the numbers look; in the calm look only for a supply that needs attention
		(it.nums as Control).visible = attention or not compact
		trend.visible = not compact
		trend.text = t[0]
		(trend as HudKit.Txt).tint(t[1])
		(value as HudKit.Txt).tint(col if attention else AstraStyle.TEXT)
		(it.meter as HudKit.Bar).share = share
		(it.meter as HudKit.Bar).color = col
		(it.icon as HudKit.Icon).color = col
		var mark := it.mark as HudKit.Icon
		mark.visible = attention
		mark.kind = StringName(HudKit.LEVEL_MARK.get(level, &"warn"))
		mark.color = col
		(it.box as PanelContainer).add_theme_stylebox_override(&"panel", AstraStyle.pill(Color(col, 0.16) if attention else Color(0, 0, 0, 0),
			AstraStyle.RADIUS_SM, 8, 4, Color(col, 0.8) if attention else Color(0, 0, 0, 0)))
		var words := "%s: %s %s. %s" % [s.name, _amount(key, amount), s.unit, t[2]]
		if attention:
			words = "%s! %s" % [ColonySummaryPanel.level_word(level), words]
		HudKit.say(it.box as Control, words + " Click or press P for details.")


## What the strip no longer shows, for the Power drawer: [{"symbol", "name", "value", "color", "note"}] for spare
## parts, the science score and the ore waiting at the workbench.
static func extra_counts(st: ColonyState) -> Array[Dictionary]:
	var ore := 0
	for k: String in (st.scout.get("ores", {}) as Dictionary):
		ore += int(st.scout.ores[k])
	return [
		{"symbol": "⚙", "name": "Spare parts", "value": str(st.parts), "color": AstraStyle.C_PARTS, "note": "Upgrades and the scout rover use them."},
		{"symbol": "✦", "name": "Science score", "value": str(ScoutSystem.science_points(st)), "color": AstraStyle.C_SCIENCE, "note": "Ores studied at the workbench."},
		{"symbol": "◆", "name": "Ore", "value": str(ore), "color": AstraStyle.C_ORE, "note": "Collected outside, waiting at the workbench."},
	]


static func _amount(key: StringName, amount: float) -> String:
	if key == &"oxygen_kg":
		return "%.1f" % amount
	return str(roundi(amount))


## [text, colour, sentence] of where a supply is going.
func _trend(st: ColonyState, key: StringName, forecast: Dictionary) -> Array:
	if key == &"battery_kwh":
		var kw := st.battery_kw
		if kw > 0.05:
			return ["▲ +%s kW" % ColonySummaryPanel.num(kw), AstraStyle.GOOD, "Charging at %s kW." % ColonySummaryPanel.num(kw)]
		if kw < -0.05:
			var h := float(forecast.get("battery_hours", -1.0))
			var tail := " · %s" % _left_words(h) if h >= 0.0 and h < 200.0 else ""
			return ["▼ %s kW%s" % [ColonySummaryPanel.num(kw), tail], AstraStyle.DANGER, "Draining at %s kW." % ColonySummaryPanel.num(-kw)]
		return ["steady", AstraStyle.TEXT_2, "Neither charging nor draining."]
	var rate := float(st.rates.get(String(key), 0.0))
	var fkey := String(ColonySummaryPanel.FORECAST_KEYS.get(key, ""))
	if rate > 1e-4:
		return ["▲ rising", AstraStyle.GOOD, "Production keeps up."]
	if rate < -1e-4:
		var hours := float(forecast.get(fkey, -1.0))
		if hours >= 0.0 and hours < 1e6:
			return ["▼ %s" % _left_words(hours), AstraStyle.DANGER, "At this rate it runs out in %s." % _left_words(hours)]
		return ["▼ falling", AstraStyle.WARN, "Going down slowly."]
	return ["steady", AstraStyle.TEXT_2, "Not changing right now."]


static func _left_words(hours: float) -> String:
	var sols := hours / GameConfig.SOL_HOURS
	if sols >= 1.0:
		return "%.1f sols" % sols
	return "%d h" % maxi(1, roundi(hours))
