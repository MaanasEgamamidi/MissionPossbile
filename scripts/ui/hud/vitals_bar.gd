class_name VitalsBar
extends PanelContainer
## The colony's supplies along the top of the screen: electricity, oxygen, water and food, each with its amount, which
## way it is going ("▲ rising", "▼ 2.1 sols" until it runs out, "+2.4 kW") and a thin fill line; then spare parts,
## science score and ore. The ⋯ button (key H) folds it down to the bare numbers and opens it again; the ? button
## (key F1) opens the science behind the numbers. Clicking a supply opens the power and life-support drawer (key P).
## A supply that is running low turns red and says so in words. Read only: it never changes anything.

signal details_requested
signal help_requested
signal compact_changed(compact: bool)

const STOCKS := [
	{"key": &"battery_kwh", "symbol": "⚡", "name": "Electricity", "unit": "kWh", "color": AstraStyle.C_POWER},
	{"key": &"oxygen_kg", "symbol": "O₂", "name": "Oxygen", "unit": "kg", "color": AstraStyle.C_O2},
	{"key": &"water_l", "symbol": "≈", "name": "Water", "unit": "L", "color": AstraStyle.C_WATER},
	{"key": &"food_meals", "symbol": "✿", "name": "Food", "unit": "meals", "color": AstraStyle.C_FOOD},
]

var services: GameServices
var compact := false

var _row: HBoxContainer
var _items: Dictionary = {}      # key -> {"box", "value", "unit", "trend", "meter", "symbol"}
var _parts: Label
var _science: Label
var _ore: Label
var _stock_box: HBoxContainer
var _more: Button
var _help: Button
var _keys: Array[Control] = []


func setup(p_services: GameServices) -> void:
	services = p_services
	name = "VitalsBar"
	add_theme_stylebox_override(&"panel", AstraStyle.glass(AstraStyle.RADIUS, 10, 6))
	mouse_filter = Control.MOUSE_FILTER_PASS
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.add_theme_constant_override(&"separation", 6)
	add_child(_row)
	for s: Dictionary in STOCKS:
		_items[s.key] = _make_item(s)
	_row.add_child(_divider())
	_stock_box = HBoxContainer.new()
	_stock_box.name = "Stocks"
	_stock_box.add_theme_constant_override(&"separation", 10)
	_row.add_child(_stock_box)
	_parts = _stock(_stock_box, "⚙", AstraStyle.C_PARTS, "Parts", "Spare parts: upgrades and the scout rover use them.")
	_science = _stock(_stock_box, "✦", AstraStyle.C_SCIENCE, "Science", "Science score: ores studied at the workbench.")
	_ore = _stock(_stock_box, "◆", AstraStyle.C_ORE, "Ore", "Special ore collected outside, waiting at the workbench.")
	_row.add_child(_divider())
	_more = AstraStyle.flat_button("⋯", 22, AstraStyle.TEXT_2)
	_more.name = "More"
	_more.tooltip_text = "Fold the supplies down to the numbers, or open them again (H)"
	_more.pressed.connect(toggle_compact)
	_row.add_child(_more)
	_keys.append(_row_key("H"))
	_help = AstraStyle.flat_button("?", 18, AstraStyle.TEXT_2)
	_help.name = "Help"
	_help.tooltip_text = "The science behind these numbers (F1)"
	_help.pressed.connect(func() -> void: help_requested.emit())
	_row.add_child(_help)
	_keys.append(_row_key("F1"))
	refresh()


func _make_item(s: Dictionary) -> Dictionary:
	var box := PanelContainer.new()
	box.name = String(s.key)
	box.add_theme_stylebox_override(&"panel", AstraStyle.pill(Color(1, 1, 1, 0.0), AstraStyle.RADIUS_SM, 8, 3))
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	box.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			details_requested.emit())
	_row.add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(col)
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(line)
	var sym := AstraStyle.label(String(s.symbol), 20, s.color, "Symbol", true)
	line.add_child(sym)
	var nums := VBoxContainer.new()
	nums.add_theme_constant_override(&"separation", -3)
	line.add_child(nums)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 3)
	nums.add_child(top)
	var value := AstraStyle.label("0", 19, AstraStyle.TEXT, "Value")
	top.add_child(value)
	var unit := AstraStyle.label(String(s.unit), 12, AstraStyle.TEXT_3, "Unit")
	unit.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	top.add_child(unit)
	var trend := AstraStyle.label("steady", 12, AstraStyle.TEXT_3, "Trend", true)
	nums.add_child(trend)
	var meter := AstraStyle.Meter.new(s.color, 3.0)
	meter.name = "Fill"
	col.add_child(meter)
	return {"box": box, "value": value, "unit": unit, "trend": trend, "meter": meter, "symbol": sym, "spec": s}


func _stock(parent: Control, symbol: String, color: Color, word: String, tip: String) -> Label:
	var h := HBoxContainer.new()
	h.name = word
	h.add_theme_constant_override(&"separation", 4)
	h.tooltip_text = tip
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(h)
	h.add_child(AstraStyle.label(symbol, 15, color, "Symbol", true))
	var v := AstraStyle.label("0", 15, AstraStyle.TEXT, "Value")
	h.add_child(v)
	return v


func _divider() -> Control:
	var d := ColorRect.new()
	d.color = AstraStyle.LINE
	d.custom_minimum_size = Vector2(1, 26)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _row_key(k: String) -> Control:
	var cap := AstraStyle.keycap(k, 10)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(cap)
	return cap


func toggle_compact() -> void:
	set_compact(not compact)


func set_compact(on: bool) -> void:
	if on == compact:
		return
	compact = on
	refresh()
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
		var value := it.value as Label
		var trend := it.trend as Label
		value.text = _amount(key, amount)
		(it.unit as Label).text = ("/%d %s" % [roundi(cap), s.unit]) if key == &"battery_kwh" else String(s.unit)
		(it.unit as Label).visible = not compact
		trend.visible = not compact
		(it.meter as Control).visible = not compact
		(it.meter as AstraStyle.Meter).share = share
		(it.meter as AstraStyle.Meter).color = AstraStyle.DANGER if level != &"ok" else s.color
		var t := _trend(st, key, forecast)
		trend.text = t[0]
		AstraStyle.set_color(trend, t[1])
		AstraStyle.set_color(value, AstraStyle.DANGER if level == &"urgent" else (AstraStyle.WARN if level == &"warn" else AstraStyle.TEXT))
		(it.box as PanelContainer).add_theme_stylebox_override(&"panel", AstraStyle.pill(Color(AstraStyle.DANGER, 0.16) if level != &"ok" else Color(0, 0, 0, 0),
			AstraStyle.RADIUS_SM, 8, 3, Color(AstraStyle.DANGER, 0.5) if level != &"ok" else Color(0, 0, 0, 0)))
		(it.box as Control).tooltip_text = "%s: %s %s. %s Click or press P for details." % [s.name, value.text, s.unit, t[2]]
	_parts.text = str(st.parts)
	_science.text = str(ScoutSystem.science_points(st))
	var ore := 0
	for k: String in (st.scout.get("ores", {}) as Dictionary):
		ore += int(st.scout.ores[k])
	_ore.text = str(ore)
	_more.text = "⋯"
	_more.tooltip_text = ("Open the supplies again" if compact else "Fold the supplies down to the numbers") + " (H)"
	for k in _keys:
		k.visible = not compact
	_stock_box.visible = true


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
		return ["steady", AstraStyle.TEXT_3, "Neither charging nor draining."]
	var rate := float(st.rates.get(String(key), 0.0))
	var fkey := String(ColonySummaryPanel.FORECAST_KEYS.get(key, ""))
	if rate > 1e-4:
		return ["▲ rising", AstraStyle.GOOD, "Production keeps up."]
	if rate < -1e-4:
		var hours := float(forecast.get(fkey, -1.0))
		if hours >= 0.0 and hours < 1e6:
			return ["▼ %s" % _left_words(hours), AstraStyle.DANGER, "At this rate it runs out in %s." % _left_words(hours)]
		return ["▼ falling", AstraStyle.WARN, "Going down slowly."]
	return ["steady", AstraStyle.TEXT_3, "Not changing right now."]


static func _left_words(hours: float) -> String:
	var sols := hours / GameConfig.SOL_HOURS
	if sols >= 1.0:
		return "%.1f sols" % sols
	return "%d h" % maxi(1, roundi(hours))
