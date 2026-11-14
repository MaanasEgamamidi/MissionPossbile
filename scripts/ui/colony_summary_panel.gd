class_name ColonySummaryPanel
extends UiPanel
## The colony at a glance and in depth: what is in store (stocks), how fast it changes right now (flows), how long
## each stock lasts at this rate, and which rooms have power. It only reads state; switching rooms is done at the
## power panel. The static functions below are also used by the HUD, so both always agree.
##
## Flows come from the model: `state.rates` (net change of each store per game hour in the last tick),
## `state.solar_kw`, `state.load_kw` and `state.battery_kw`. Time left comes from ReserveForecast.compute(), which
## follows the real sun curve for the battery.

## Stocks shown, in order: key, symbol, name, unit, explanation id.
const STOCKS := [
	{"key": &"battery_kwh", "symbol": "⚡", "name": "Battery (colony electricity)", "unit": "kWh", "explain": "battery"},
	{"key": &"oxygen_kg", "symbol": "O₂", "name": "Oxygen (reserve in the tanks)", "unit": "kg", "explain": "oxygen"},
	{"key": &"water_l", "symbol": "≈", "name": "Water", "unit": "L", "explain": "water"},
	{"key": &"food_meals", "symbol": "✿", "name": "Food", "unit": "meals", "explain": "food"},
]
## Forecast key (ReserveForecast.compute) of each stock.
const FORECAST_KEYS := {&"battery_kwh": "battery_hours", &"oxygen_kg": "oxygen_hours", &"water_l": "water_hours", &"food_meals": "food_hours"}
## A stock is "low" below this share of its capacity or below this many sols of use; "very low" below the second pair.
const WARN_SHARE := 0.15
const URGENT_SHARE := 0.05
const WARN_SOLS := 3.0
const URGENT_SOLS := 1.0
## The battery uses its own shares (it empties and fills every sol).
const BATTERY_WARN_SHARE := 0.25
const BATTERY_URGENT_SHARE := 0.10

var _glance: Label
var _stock_rows := {}           # key -> ReadingRow
var _stock_bars := {}           # key -> ProgressBar
var _parts_row: ReadingRow
var _flow_rows := {}            # name -> ReadingRow
var _cause_labels := {}         # name -> Label
var _time_rows := {}            # key -> ReadingRow
var _rooms_grid: GridContainer
var _room_labels := {}          # zone -> [status Label, name Label, kW Label]
var _close: Button


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	name = "ColonySummaryPanel"
	theme_type_variation = UiTheme.PANEL
	var box := VBoxContainer.new()
	box.name = "Box"
	add_child(box)
	var header := HBoxContainer.new()
	header.name = "Header"
	box.add_child(header)
	var title := Label.new()
	title.name = "Title"
	title.text = "Colony summary"
	title.theme_type_variation = UiTheme.TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(ExplainButton.make("stamina_vs_electricity"))
	_close = Button.new()
	_close.name = "Close"
	_close.text = "Close"
	_close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(_close)
	_glance = Label.new()
	_glance.name = "Glance"
	_glance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_glance)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	# ---- stocks
	_heading(content, "In store (stocks)")
	for s: Dictionary in STOCKS:
		var row := ReadingRow.make(s.symbol, s.name, s.explain)
		content.add_child(row)
		_stock_rows[s.key] = row
		var bar := ProgressBar.new()
		bar.name = "Bar_" + String(s.key)
		bar.show_percentage = false
		bar.min_value = 0.0
		bar.max_value = 1.0
		content.add_child(bar)
		_stock_bars[s.key] = bar
	_parts_row = ReadingRow.make("⚙", "Spare parts", "parts")
	content.add_child(_parts_row)

	# ---- flows
	_heading(content, "Changing right now (flows)")
	for f: Array in [["solar", "☀", "Sun gives (solar power)", "solar_power"], ["load", "⌁", "Colony uses (load)", "load"],
			["net", "⇅", "Battery change", "power_deficit"], ["oxygen", "O₂", "Oxygen reserve per sol", "oxygen"],
			["water", "≈", "Water per sol", "water"], ["food", "✿", "Food per sol", "food"],
			["cabin", "◎", "Cabin air", "cabin_air"]]:
		var row := ReadingRow.make(f[1], f[2], f[3])
		content.add_child(row)
		_flow_rows[f[0]] = row
		if String(f[0]) in ["net", "oxygen", "water", "food", "cabin"]:
			var cause := Label.new()
			cause.name = "Cause_" + String(f[0])
			cause.theme_type_variation = UiTheme.MUTED
			cause.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			content.add_child(cause)
			if String(f[0]) == "cabin":
				cause.hide()
			_cause_labels[f[0]] = cause
		if String(f[0]) == "oxygen":
			var made := Label.new()
			made.name = "OxygenMade"
			made.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			content.add_child(made)
			_cause_labels["oxygen_made"] = made

	# ---- time left
	_heading(content, "How long it lasts at this rate")
	for s: Dictionary in STOCKS:
		var row := ReadingRow.make(s.symbol, short_name(s), "stock_vs_flow")
		row.name = "TimeLeft_" + String(s.key)
		content.add_child(row)
		_time_rows[s.key] = row

	# ---- rooms
	_heading(content, "Rooms with power")
	var note_row := HBoxContainer.new()
	note_row.name = "RoomsNoteRow"
	var note := Label.new()
	note.name = "RoomsNote"
	note.text = "Manage rooms at the Power Room panel."
	note.theme_type_variation = UiTheme.MUTED
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_row.add_child(note)
	note_row.add_child(ExplainButton.make("zones_power"))
	content.add_child(note_row)
	_rooms_grid = GridContainer.new()
	_rooms_grid.name = "Rooms"
	_rooms_grid.columns = 3
	content.add_child(_rooms_grid)
	refresh()


func panel_title() -> String:
	return "Colony"


func first_focus() -> Control:
	return _close


func refresh() -> void:
	if services == null or not services.has_game():
		return
	var st := services.state()
	var f := flows_of(services)
	var forecast := ReserveForecast.compute(st, services.balance, services.clock())
	# stocks
	for s: Dictionary in STOCKS:
		var key: StringName = s.key
		var cap := float(st.capacities.get(key, 0.0))
		var lvl := level_of(services, key)
		(_stock_rows[key] as ReadingRow).set_value("%s of %s" % [amount_with_unit(key, st.store(key)), amount_with_unit(key, cap)], lvl, level_word(lvl))
		var bar := _stock_bars[key] as ProgressBar
		bar.value = st.store(key) / cap if cap > 0.0 else 0.0
		bar.theme_type_variation = UiTheme.bar_of(lvl)          # the bar's colour follows the word beside it
	_parts_row.set_value("%d parts" % st.parts, &"ok", "OK")

	# flows
	var battery_kw: float = f.battery_kw
	(_flow_rows["solar"] as ReadingRow).set_value("%s kW" % num(f.solar_kw), &"ok", "Now")
	(_flow_rows["load"] as ReadingRow).set_value("%s kW" % num(f.load_kw), &"ok", "Now")
	(_flow_rows["net"] as ReadingRow).set_value(signed_kw(battery_kw), &"warn" if battery_kw < -0.05 else &"ok",
		"Draining" if battery_kw < -0.05 else ("Charging" if battery_kw > 0.05 else "Steady"))
	(_cause_labels["net"] as Label).text = power_cause(f)
	var crew := int(f.crew)
	var o_net: float = f.oxygen_per_sol
	(_flow_rows["oxygen"] as ReadingRow).set_value(signed_amount(o_net, "kg per sol", 2), &"warn" if o_net < -1e-6 else &"ok", trend_word(o_net))
	(_cause_labels["oxygen"] as Label).text = oxygen_cause(f)
	(_cause_labels["oxygen_made"] as Label).text = "Oxygen made by each process: electrolyser %s kg per sol (uses water), CO₂-oxygen unit %s kg per sol (uses Mars air)." % [
		num(f.electrolyser_kg_per_sol), num(f.co2_unit_kg_per_sol)]
	var w_net: float = f.water_per_sol
	(_flow_rows["water"] as ReadingRow).set_value(signed_amount(w_net, "L per sol", 1), &"warn" if w_net < -1e-6 else &"ok", trend_word(w_net))
	(_cause_labels["water"] as Label).text = water_cause(f)
	var food: float = f.food_per_sol
	(_flow_rows["food"] as ReadingRow).set_value(signed_amount(food, "meals per sol", 1), &"warn" if food < -1e-6 else &"ok", trend_word(food))
	if crew > 0:
		(_cause_labels["food"] as Label).text = "%s eats %s meals per sol." % [crew_words(crew), num(services.balance.meals_per_sol)]
	else:
		(_cause_labels["food"] as Label).text = "Nobody is playing a crew member, so nobody eats."
	var cabin_lvl: StringName = f.cabin_level
	(_flow_rows["cabin"] as ReadingRow).set_value("O₂ %s kPa · CO₂ %s kPa · total %s kPa" % [num(f.cabin_o2_kpa), "%.2f" % float(f.cabin_co2_kpa), num(f.cabin_kpa)],
		cabin_lvl, "Safe" if cabin_lvl == &"ok" else ("Check" if cabin_lvl == &"warn" else "Danger"))
	(_cause_labels["cabin"] as Label).text = "The air in the rooms is not the oxygen reserve: a regulator tops it up from the tanks."

	# time left
	for s: Dictionary in STOCKS:
		var key: StringName = s.key
		var hours := float(forecast.get(FORECAST_KEYS[key], -1.0))
		var sols := hours / GameConfig.SOL_HOURS if hours >= 0.0 else -1.0
		var row := _time_rows[key] as ReadingRow
		if sols < 0.0:
			row.set_value("—", &"ok", "Not going down")
		else:
			var lvl: StringName = &"urgent" if sols < URGENT_SOLS else (&"warn" if sols < WARN_SOLS else &"ok")
			row.set_value(time_left_text(short_name(s), sols), lvl, "Soon empty" if sols < WARN_SOLS else "Going down")

	# glance
	var low := PackedStringArray()
	for s: Dictionary in STOCKS:
		if level_of(services, s.key) != &"ok":
			low.append(short_name(s).to_lower())
	if cabin_lvl != &"ok":
		low.append("cabin air")
	if low.is_empty():
		_glance.text = "✓ Colony OK. Everything in store is fine right now."
		_glance.theme_type_variation = UiTheme.GOOD
	else:
		_glance.text = "! Needs attention: %s." % ", ".join(low)
		_glance.theme_type_variation = UiTheme.WARN

	_refresh_rooms()


## The time-left line of a stock ("Oxygen lasts about 4.9 sols at this rate"), or "—" when `sols` < 0.
static func time_left_text(stock_name: String, sols: float) -> String:
	if sols < 0.0:
		return "—"
	if sols >= 1.0:
		var n := num(sols)
		return "%s lasts about %s %s at this rate" % [stock_name, n, "sol" if n == "1" else "sols"]
	var hours := sols * GameConfig.SOL_HOURS
	if hours < 1.0:
		return "%s lasts less than 1 hour at this rate" % stock_name
	var h := num(hours)
	return "%s lasts about %s %s at this rate" % [stock_name, h, "hour" if h == "1" else "hours"]


## Everything that flows right now, from the model's last tick:
## solar_kw, load_kw, battery_kw (+ charging, − draining), net_kw (solar − load), crew (active),
## oxygen_per_sol, water_per_sol, food_per_sol (net change of each store per sol, from state.rates),
## electrolyser_kg_per_sol, co2_unit_kg_per_sol (oxygen made by each process),
## cabin_o2_kpa, cabin_co2_kpa, cabin_kpa (total), cabin_level.
static func flows_of(p_services: GameServices) -> Dictionary:
	var st := p_services.state()
	var b := p_services.balance
	var hours := GameConfig.SOL_HOURS
	var kpa := StationPanel.cabin_kpa(st, b)
	var o2_lvl := StationPanel.o2_level(float(kpa.o2), b)
	var co2_lvl := StationPanel.co2_level(float(kpa.co2), b)
	var cabin_lvl: StringName = &"ok"
	if o2_lvl == &"urgent" or co2_lvl == &"urgent":
		cabin_lvl = &"urgent"
	elif o2_lvl == &"warn" or co2_lvl == &"warn" or float(kpa.total) < b.pressure_warn_kpa:
		cabin_lvl = &"warn"
	return {
		"solar_kw": st.solar_kw, "load_kw": st.load_kw, "battery_kw": st.battery_kw, "net_kw": st.solar_kw - st.load_kw,
		"crew": st.active_characters().size(), "shed": st.shed.size(),
		"oxygen_per_sol": float(st.rates.get("oxygen_kg", 0.0)) * hours,
		"water_per_sol": float(st.rates.get("water_l", 0.0)) * hours,
		"food_per_sol": float(st.rates.get("food_meals", 0.0)) * hours,
		"electrolyser_kg_per_sol": StationPanel.process_o2_kg_per_hour(st, b, "electrolyser") * hours,
		"co2_unit_kg_per_sol": StationPanel.process_o2_kg_per_hour(st, b, "co2_unit") * hours,
		"recycler_on": LifeSupportModel.recycler_working(st, b),
		"cabin_o2_kpa": float(kpa.o2), "cabin_co2_kpa": float(kpa.co2), "cabin_kpa": float(kpa.total), "cabin_level": cabin_lvl,
	}


## How a stock changes per sol at the current flow (negative = going down), from state.rates.
static func change_per_sol(p_services: GameServices, key: StringName) -> float:
	return float(p_services.state().rates.get(String(key), 0.0)) * GameConfig.SOL_HOURS


## Sols until the stock is empty at the current flow (ReserveForecast), or -1 when it is not going down.
static func time_left_sols(p_services: GameServices, key: StringName) -> float:
	var forecast := ReserveForecast.compute(p_services.state(), p_services.balance, p_services.clock())
	var hours := float(forecast.get(FORECAST_KEYS.get(key, ""), -1.0))
	return hours / GameConfig.SOL_HOURS if hours >= 0.0 else -1.0


## &"ok", &"warn" (low) or &"urgent" (very low) for a stock, judged by its share of capacity and, for supplies,
## by how many sols it lasts for the crew playing now (at least one).
static func level_of(p_services: GameServices, key: StringName) -> StringName:
	var st := p_services.state()
	var cap := float(st.capacities.get(key, 0.0))
	var share := st.store(key) / cap if cap > 0.0 else 0.0
	if key == &"battery_kwh":
		if share < BATTERY_URGENT_SHARE or (st.power_deficit and st.store(key) <= 1e-6):
			return &"urgent"
		return &"warn" if share < BATTERY_WARN_SHARE else &"ok"
	var b := p_services.balance
	var crew := float(maxi(1, st.active_characters().size()))
	var use_per_sol := 0.0
	match key:
		&"oxygen_kg":
			use_per_sol = crew * b.oxygen_kg_per_hour * GameConfig.SOL_HOURS
		&"water_l":
			use_per_sol = crew * b.water_l_per_hour * GameConfig.SOL_HOURS
		&"food_meals":
			use_per_sol = crew * b.meals_per_sol
	var sols := st.store(key) / use_per_sol if use_per_sol > 0.0 else INF
	if share < URGENT_SHARE or sols < URGENT_SOLS:
		return &"urgent"
	if share < WARN_SHARE or sols < WARN_SOLS:
		return &"warn"
	return &"ok"


## The word for a stock level: "OK", "Low" or "Very low".
static func level_word(lvl: StringName) -> String:
	match lvl:
		&"warn":
			return "Low"
		&"urgent":
			return "Very low"
	return "OK"


## "Falling", "Rising" or "Steady".
static func trend_word(change: float) -> String:
	if change < -1e-6:
		return "Falling"
	if change > 1e-6:
		return "Rising"
	return "Steady"


## The stock name without its note in brackets ("Battery").
static func short_name(stock: Dictionary) -> String:
	return String(stock.name).get_slice(" (", 0)


## One plain sentence of cause and effect for the battery.
static func power_cause(f: Dictionary) -> String:
	var solar: float = f.solar_kw
	var used: float = f.load_kw
	var text := ""
	if solar - used < -0.05:
		text = "Battery draining: the colony uses %s kW and the sun gives %s kW." % [num(used), num(solar)]
	elif solar - used > 0.05:
		text = "Battery charging: the sun gives %s kW and the colony uses %s kW." % [num(solar), num(used)]
	else:
		text = "Battery steady: the sun gives as much as the colony uses, %s kW." % num(used)
	if int(f.get("shed", 0)) > 0:
		text += " Power is short, so some loads have no power."
	return text


static func oxygen_cause(f: Dictionary) -> String:
	var made: float = float(f.electrolyser_kg_per_sol) + float(f.co2_unit_kg_per_sol)
	var change: float = f.oxygen_per_sol
	if change > 1e-6:
		return "Oxygen reserve rising: the oxygen makers fill the tanks faster than the cabin takes from them."
	if change < -1e-6:
		if made <= 1e-9:
			return "Oxygen reserve falling: the cabin takes oxygen from the tanks and no oxygen maker is running."
		return "Oxygen reserve falling: the cabin takes more oxygen from the tanks than the oxygen makers make."
	return "Oxygen reserve steady."


static func water_cause(f: Dictionary) -> String:
	if int(f.crew) <= 0:
		return "Nobody is playing a crew member, so no water is used."
	if not bool(f.recycler_on):
		return "The water recycler is not running, so used water is not cleaned again."
	return "The recycler cleans most used water so it can be used again; the rest is lost."


## A number for display: whole numbers from 10 up, one decimal below 10.
static func num(v: float) -> String:
	if absf(v) >= 10.0:
		return "%d" % roundi(v)
	var t := "%.1f" % v
	if t == "-0.0":
		t = "0.0"
	return t.trim_suffix(".0")


## A change with its sign and unit ("+1.5 kg per sol", "−3.5 kg per sol", "0 kg per sol").
static func signed_amount(v: float, unit: String, decimals: int) -> String:
	var limit := 0.5 * pow(10.0, -decimals)
	var text := String.num(absf(v), decimals)
	if v > limit:
		return "+%s %s" % [text, unit]
	if v < -limit:
		return "−%s %s" % [text, unit]
	return "0 %s" % unit


## A power change with its sign and unit ("+12 kW", "−34 kW", "0 kW").
static func signed_kw(v: float) -> String:
	if v > 0.05:
		return "+%s kW" % num(v)
	if v < -0.05:
		return "−%s kW" % num(-v)
	return "0 kW"


## A stock amount without its unit (oxygen keeps one decimal).
static func amount_text(key: StringName, v: float) -> String:
	if key == &"oxygen_kg":
		return "%.1f" % v
	return "%d" % roundi(v)


## A stock amount with its unit ("12.0 kg", "1 meal", "96 meals").
static func amount_with_unit(key: StringName, v: float) -> String:
	var unit := ""
	for s: Dictionary in STOCKS:
		if s.key == key:
			unit = s.unit
	var n := amount_text(key, v)
	if unit == "meals" and n == "1":
		unit = "meal"
	return "%s %s" % [n, unit]


static func crew_words(n: int) -> String:
	return "1 crew member" if n == 1 else "%d crew members" % n


func _refresh_rooms() -> void:
	var st := services.state()
	var names: Array = st.zones.keys()
	names.sort()
	if names.size() != _room_labels.size():
		for child in _rooms_grid.get_children():
			_rooms_grid.remove_child(child)
			child.queue_free()
		_room_labels.clear()
		for zone: String in names:
			var cells: Array[Label] = []
			for column in 3:
				var l := Label.new()
				l.name = "%s_%d" % [zone.validate_node_name().replace(" ", "_"), column]
				_rooms_grid.add_child(l)
				cells.append(l)
			cells[1].size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_room_labels[zone] = cells
	for zone: String in names:
		var cells: Array = _room_labels[zone]
		var on := st.is_zone_powered(zone)
		var kw := services.balance.load_of_zone(zone)
		(cells[0] as Label).text = "✓ On" if on else "✖ Off"
		(cells[0] as Label).theme_type_variation = UiTheme.GOOD if on else UiTheme.MUTED
		(cells[1] as Label).text = zone
		(cells[2] as Label).text = ("uses %s kW" % num(kw)) if on else ("0 kW (%s kW when on)" % num(kw))


func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.name = "Heading_" + text.validate_node_name().replace(" ", "_")
	l.text = text
	l.theme_type_variation = UiTheme.HEADING
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)


func _idea_box(parent: Control, text: String, explanation_id: String) -> void:
	var card := PanelContainer.new()
	card.name = "Idea_" + explanation_id
	card.theme_type_variation = UiTheme.CARD
	var row := HBoxContainer.new()
	card.add_child(row)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(ExplainButton.make(explanation_id))
	parent.add_child(card)
