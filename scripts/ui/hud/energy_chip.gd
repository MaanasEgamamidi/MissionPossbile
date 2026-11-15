extends PanelContainer
## The battery chip under the vitals bar (owner request 2026-11-14: when the sun goes down the solar panels stop and
## the battery drains fast). It shows a sun or a moon, how full the battery is, and while the battery goes down how
## fast and for how long it lasts: "☾ Battery 64 % · falling 4.2 kW, ~9 h left". It turns amber below WARN_PCT and red
## below URGENT_PCT. The numbers come from PowerModel.outlook() (the energy model's own forecast) when the game has
## it, else from the colony state. Read only.

## Battery share (percent) below which the chip turns amber / red.
const WARN_PCT := 30.0
const URGENT_PCT := 15.0
const POWER_MODEL_PATH := "res://scripts/sim/power_model.gd"

## 1 = PowerModel.outlook() exists, 0 = it does not, -1 = not looked yet.
static var _outlook := -1

var services: GameServices
## What the chip shows now (see reading()).
var current: Dictionary = {}

var _symbol: Label
var _text: Label
var _style: StyleBoxFlat


func _init() -> void:
	name = "EnergyChip"
	mouse_filter = Control.MOUSE_FILTER_PASS
	_style = AstraStyle.pill(Color(AstraStyle.GLASS, 0.82), AstraStyle.RADIUS_SM, 12, 4, AstraStyle.LINE)
	add_theme_stylebox_override(&"panel", _style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_symbol = AstraStyle.label("☀", 17, AstraStyle.C_POWER, "Symbol", true)
	_symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_symbol)
	_text = AstraStyle.label("", 14, AstraStyle.TEXT, "Text")
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_text)


func setup(p_services: GameServices) -> void:
	services = p_services
	refresh()


## The whole line as shown ("☾ Battery 64 % · falling 4.2 kW, ~9 h left").
func text() -> String:
	return "%s %s" % [_symbol.text, _text.text]


## &"ok", &"warn" (below WARN_PCT) or &"urgent" (below URGENT_PCT).
func level() -> StringName:
	return StringName(current.get("level", &"ok"))


## The colour the text has now.
func text_color() -> Color:
	return _text.get_theme_color(&"font_color")


func refresh() -> void:
	if services == null or not services.has_game():
		return
	current = reading(services)
	_symbol.text = "☀" if bool(current.sun_up) else "☾"
	AstraStyle.set_color(_symbol, AstraStyle.C_POWER if bool(current.sun_up) else AstraStyle.TEXT_2)
	_text.text = String(current.text)
	var c := AstraStyle.TEXT
	match level():
		&"urgent": c = AstraStyle.DANGER
		&"warn": c = AstraStyle.WARN
	AstraStyle.set_color(_text, c)
	_style.border_color = AstraStyle.LINE if level() == &"ok" else Color(c, 0.7)
	_style.bg_color = Color(AstraStyle.GLASS, 0.82) if level() == &"ok" else Color(c.r * 0.2 + 0.05, c.g * 0.12 + 0.06, c.b * 0.12 + 0.12, 0.9)
	tooltip_text = String(current.get("tip", ""))


## True when the energy model has PowerModel.outlook(state, balance, phase).
static func has_outlook() -> bool:
	if _outlook < 0:
		_outlook = 0
		var s := load(POWER_MODEL_PATH) as Script
		if s != null:
			for m: Dictionary in s.get_script_method_list():
				if String(m.get("name", "")) == "outlook":
					_outlook = 1
	return _outlook == 1


## What the chip shows: {"sun_up", "percent", "net_kw", "hours_left" (INF while not draining), "level", "text", "tip",
## "from_outlook"}.
static func reading(p_services: GameServices) -> Dictionary:
	var st := p_services.state()
	var clock := p_services.clock()
	var o: Dictionary = {}
	if has_outlook():
		var v: Variant = (load(POWER_MODEL_PATH) as Script).call("outlook", st, p_services.balance, clock.phase)
		if v is Dictionary:
			o = v
	var battery := float(o.get("battery_kwh", st.store(&"battery_kwh")))
	var cap := float(o.get("battery_capacity_kwh", st.capacities.get(&"battery_kwh", 0.0)))
	var net := float(o.get("net_kw", st.battery_kw))
	var sun_up := bool(o.get("sun_up", clock.is_daylight()))
	var hours := INF
	if o.has("hours_left"):
		hours = float(o.hours_left)
	elif net < -0.05:
		hours = battery / -net
	var pct := clampf(battery / cap * 100.0, 0.0, 100.0) if cap > 0.0 else 0.0
	var lvl: StringName = &"ok"
	if pct < URGENT_PCT:
		lvl = &"urgent"
	elif pct < WARN_PCT:
		lvl = &"warn"
	var line := "Battery %d %%" % roundi(pct)
	var tip := "Colony battery: %s of %s kWh." % [StationPanel.num(battery, 0), StationPanel.num(cap, 0)]
	if net < -0.05:
		line += " · falling %s kW, %s left" % [StationPanel.num(-net, 1), hours_words(hours)]
		tip += " It is going down by %s kW%s." % [StationPanel.num(-net, 1), "" if sun_up else ": it is night, so the solar panels make nothing"]
	elif net > 0.05:
		line += " · charging %s kW" % StationPanel.num(net, 1)
		tip += " The solar panels make more than the colony uses."
	else:
		line += " · steady"
	if o.has("hours_to_sunrise") and not sun_up:
		tip += " Sunrise in about %s." % hours_words(float(o.hours_to_sunrise)).trim_prefix("~")
	return {"sun_up": sun_up, "percent": pct, "net_kw": net, "hours_left": hours, "level": lvl, "text": line, "tip": tip,
		"from_outlook": not o.is_empty()}


## "~9 h", "<1 h", "~2 sols" for a number of game hours.
static func hours_words(hours: float) -> String:
	if is_inf(hours) or is_nan(hours):
		return "—"
	if hours < 1.0:
		return "<1 h"
	if hours >= 2.0 * GameConfig.SOL_HOURS:
		return "~%s sols" % StationPanel.num(hours / GameConfig.SOL_HOURS, 1)
	return "~%d h" % roundi(hours)
