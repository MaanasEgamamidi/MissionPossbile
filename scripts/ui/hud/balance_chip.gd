extends PanelContainer
## Colony balance chip (upgrade paths plan §1.3, 2026-11-15): a small chip with the weakest life system in words,
## "◐ Weakest: power · 24 %". It turns amber / red when that system is low. The numbers come from
## scripts/upgrades/colony_balance.gd (food, air, water, power, radiation dose trend, health). Read only.
## Attach like the energy chip (MissionHud): new(), add_child, setup(services), refresh() with the HUD's refresh.

const ColonyBalance := preload("res://scripts/upgrades/colony_balance.gd")

var services: GameServices
## What the chip shows now: the weakest system row of ColonyBalance.systems() ({} before the game).
var current: Dictionary = {}

var _symbol: Label
var _text: Label
var _style: StyleBoxFlat


func _init() -> void:
	name = "BalanceChip"
	mouse_filter = Control.MOUSE_FILTER_PASS
	_style = AstraStyle.pill(Color(AstraStyle.GLASS, 0.82), AstraStyle.RADIUS_SM, 12, 4, AstraStyle.LINE)
	add_theme_stylebox_override(&"panel", _style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_symbol = AstraStyle.label("◐", 17, AstraStyle.TEXT_2, "Symbol", true)
	_symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_symbol)
	_text = AstraStyle.label("", 14, AstraStyle.TEXT, "Text")
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_text)


func setup(p_services: GameServices) -> void:
	services = p_services
	refresh()


## The whole line as shown ("◐ Weakest: power · 24 %").
func text() -> String:
	return "%s %s" % [_symbol.text, _text.text]


## &"ok", &"warn" or &"urgent".
func level() -> StringName:
	return StringName(current.get("level", &"ok"))


func refresh() -> void:
	if services == null or not services.has_game():
		visible = false
		return
	visible = true
	var st := services.state()
	current = ColonyBalance.weakest(st)
	if current.is_empty():
		_text.text = "Colony balance: —"
		return
	_text.text = "Weakest: %s · %d %%" % [String(current.word), roundi(float(current.share) * 100.0)]
	var c := AstraStyle.TEXT
	match level():
		&"urgent": c = AstraStyle.DANGER
		&"warn": c = AstraStyle.WARN
	AstraStyle.set_color(_text, c)
	_style.border_color = AstraStyle.LINE if level() == &"ok" else Color(c, 0.7)
	var tip := PackedStringArray(["Colony balance: the weakest system shows first. Upgrades that help it matter most."])
	for row: Dictionary in ColonyBalance.systems(st):
		tip.append("%s %s: %d %%" % [String(row.symbol), String(row.word).capitalize(), roundi(float(row.share) * 100.0)])
	tooltip_text = "\n".join(tip)
