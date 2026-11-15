extends PanelContainer
## The battery chip under the vitals bar (owner request 2026-11-14: when the sun goes down the solar panels stop and
## the battery drains fast).
## UI overhaul (2026-11-15): pictures instead of a sentence. It shows a sun or a moon, a battery, an arrow (up while
## it charges, down while it drains) and, only while it drains, how long it lasts ("~9 h"). Below WARN_PCT it turns
## amber and adds the battery share and a triangle mark; below URGENT_PCT red with an octagon mark.
## The whole sentence ("☾ Battery 64 % · falling 4.2 kW, ~9 h left") is still what text() returns, and it is the
## chip's tooltip and accessible name. The numbers come from PowerModel.outlook() (the energy model's own forecast)
## when the game has it, else from the colony state. Read only.

const HudKit := preload("res://scripts/ui/hud/hud_kit.gd")
## Battery share (percent) below which the chip turns amber / red.
const WARN_PCT := 30.0
const URGENT_PCT := 15.0
const POWER_MODEL_PATH := "res://scripts/sim/power_model.gd"

## 1 = PowerModel.outlook() exists, 0 = it does not, -1 = not looked yet.
static var _outlook := -1

var services: GameServices
## What the chip shows now (see reading()).
var current: Dictionary = {}

var _sky: HudKit.Icon
var _battery: HudKit.Icon
var _arrow: HudKit.Icon
var _text: HudKit.Txt
var _mark: HudKit.Icon
var _color := AstraStyle.TEXT
var _tone := "-"


func _init() -> void:
	name = "EnergyChip"
	mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_sky = HudKit.Icon.new(&"sun", AstraStyle.C_POWER, 22.0, "Symbol")
	row.add_child(_sky)
	_battery = HudKit.Icon.new(&"battery", AstraStyle.TEXT, 24.0, "Battery")
	row.add_child(_battery)
	_arrow = HudKit.Icon.new(&"up", AstraStyle.GOOD, 14.0, "Arrow")
	row.add_child(_arrow)
	_text = HudKit.Txt.new("", 18.0, AstraStyle.TEXT, "Text", true)
	row.add_child(_text)
	_mark = HudKit.Icon.new(&"warn", AstraStyle.WARN, 18.0, "Mark")
	row.add_child(_mark)
	_restyle()


func setup(p_services: GameServices) -> void:
	services = p_services
	refresh()


## The whole line in words ("☾ Battery 64 % · falling 4.2 kW, ~9 h left"): the chip's tooltip and accessible name.
func text() -> String:
	return "%s %s" % ["☀" if bool(current.get("sun_up", true)) else "☾", String(current.get("text", ""))]


## The few words the chip itself shows beside its pictures ("~9 h", "25 % · ~3 h"), or "".
func shown_words() -> String:
	return _text.text if _text.visible else ""


## &"ok", &"warn" (below WARN_PCT) or &"urgent" (below URGENT_PCT).
func level() -> StringName:
	return StringName(current.get("level", &"ok"))


## The colour the chip's words and battery have now.
func text_color() -> Color:
	return _color


func refresh() -> void:
	if services == null or not services.has_game():
		return
	current = reading(services)
	var sun_up := bool(current.sun_up)
	_sky.kind = &"sun" if sun_up else &"moon"
	_sky.color = AstraStyle.C_POWER if sun_up else AstraStyle.TEXT_2
	_color = AstraStyle.TEXT
	match level():
		&"urgent": _color = AstraStyle.DANGER
		&"warn": _color = AstraStyle.WARN
	var net := float(current.net_kw)
	var draining := net < -0.05
	_arrow.visible = absf(net) > 0.05
	_arrow.kind = &"down" if draining else &"up"
	_arrow.color = (AstraStyle.DANGER if level() == &"urgent" else AstraStyle.WARN) if draining else AstraStyle.GOOD
	_battery.color = _color
	var words := PackedStringArray()
	if level() != &"ok":
		words.append("%d %%" % roundi(float(current.percent)))
	if draining:
		words.append(hours_words(float(current.hours_left)))
	_text.text = " · ".join(words)
	_text.visible = _text.text != ""
	_text.tint(_color)
	_mark.visible = level() != &"ok"
	_mark.kind = StringName(HudKit.LEVEL_MARK.get(level(), &"warn"))
	_mark.color = _color
	_restyle()
	HudKit.say(self, "%s. %s" % [text(), String(current.get("tip", ""))])


func _restyle() -> void:
	var tone := "%s|%s" % [level(), UiTheme.is_high_contrast()]
	if tone == _tone:
		return
	_tone = tone
	var c := _color
	var plain := level() == &"ok"
	var style := AstraStyle.pill(Color(AstraStyle.GLASS_SOLID if UiTheme.is_high_contrast() else AstraStyle.GLASS, 0.9) if plain
		else Color(c.r * 0.2 + 0.05, c.g * 0.12 + 0.06, c.b * 0.12 + 0.12, 0.93), AstraStyle.RADIUS_SM, 12, 4,
		(AstraStyle.LINE_STRONG if UiTheme.is_high_contrast() else AstraStyle.LINE) if plain else Color(c, 0.8))
	add_theme_stylebox_override(&"panel", style)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_restyle()


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
