class_name GoalsCard
extends PanelContainer
## The goals card on the left: "GOALS 2/12 ⌃". Two looks of its own:
##   list     (open = true, the look a new game starts with) the goals with a ring (○) or a tick (✓), a thin progress
##            line and a short count ("1/6"), at most ColonyGoals.MAX_SHOWN of them and then "+N more · J: map".
##   compact  (open = false) just "GOALS 3/12" and a thin progress bar for all the goals, "J: list".
## Owner 2026-11-14, J cycles three looks: list -> the big goals screen with the map (scripts/ui/hud/goals_big_panel.gd,
## opened by MissionHud) -> compact -> list ... Closing the big screen (J, Esc or ✕) always lands on compact. A click on
## the header (or anywhere on the compact card) swaps list and compact. Goals come from ColonyGoals, checked from the
## real colony state.

signal toggled(open: bool)

const LIST_WIDTH := 300.0
const COMPACT_WIDTH := 190.0

var services: GameServices
## True: the list look. False: the compact look.
var open := true

var _head: HBoxContainer
var _count: Label
var _chev: Label
## The word after the J keycap in the header: what J does next ("map" from the list, "list" from compact).
var _key_hint: Label
var _list: VBoxContainer
## "+3 more · J: map" under the list when the list cannot show every goal.
var _more: Label
## Compact look: one thin bar for all the goals (done / total).
var _bar: AstraStyle.Meter
var _sig := ""


func setup(p_services: GameServices) -> void:
	services = p_services
	name = "GoalsCard"
	add_theme_stylebox_override(&"panel", AstraStyle.glass(AstraStyle.RADIUS, 14, 10))
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Compact look: a click anywhere on the card opens the list (the header handles its own clicks).
	gui_input.connect(func(e: InputEvent) -> void:
		if not open and e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			set_open(true)
			accept_event())
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	add_child(col)
	_head = HBoxContainer.new()
	_head.name = "Head"
	_head.mouse_filter = Control.MOUSE_FILTER_STOP
	_head.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_head.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			toggle())
	col.add_child(_head)
	var title := AstraStyle.label("GOALS", 12, AstraStyle.TEXT_2, "Title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.add_child(title)
	_count = AstraStyle.label("0/0", 13, AstraStyle.TEXT, "Count")
	_head.add_child(_count)
	_chev = AstraStyle.label("⌃", 14, AstraStyle.TEXT_2, "Chevron", true)
	_head.add_child(_chev)
	_head.add_child(AstraStyle.keycap(GameHud._key(&"goals", "J"), 10))
	_key_hint = AstraStyle.label("map", 11, AstraStyle.TEXT_3, "KeyHint")
	_head.add_child(_key_hint)
	_bar = AstraStyle.Meter.new(AstraStyle.ACCENT, 3.0)
	_bar.name = "Progress"
	_bar.visible = false
	col.add_child(_bar)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.add_theme_constant_override(&"separation", 10)
	col.add_child(_list)
	_more = AstraStyle.label("", 12, AstraStyle.TEXT_3, "More")
	_more.visible = false
	col.add_child(_more)
	_show_look()
	refresh()


## Swaps the list and compact looks (a click on the header).
func toggle() -> void:
	set_open(not open)


## True: the list look. False: the compact look ("GOALS x/y" and a thin bar).
func set_open(on: bool) -> void:
	if on == open:
		return
	open = on
	_show_look()
	toggled.emit(open)
	reset_size()


func _show_look() -> void:
	_list.visible = open
	_more.visible = open and _more.text != ""
	_bar.visible = not open
	_chev.text = "⌃" if open else "⌄"
	_key_hint.text = "map" if open else "list"
	custom_minimum_size.x = LIST_WIDTH if open else COMPACT_WIDTH
	mouse_default_cursor_shape = Control.CURSOR_ARROW if open else Control.CURSOR_POINTING_HAND


func refresh() -> void:
	if services == null or not services.has_game():
		return
	var st := services.state()
	var n := ColonyGoals.done_count(st)
	_count.text = "%d/%d" % [n.x, n.y]
	_bar.share = float(n.x) / float(n.y) if n.y > 0 else 0.0
	var goals := ColonyGoals.shown(st)
	var hidden := n.y - goals.size()
	# Owner 2026-11-14: J goes on to the map (was "J shows all").
	_more.text = "+%d more · %s: map" % [hidden, GameHud._key(&"goals", "J")] if hidden > 0 else ""
	_show_look()
	var sig := JSON.stringify(goals)
	if sig == _sig:
		return
	_sig = sig
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for g: Dictionary in goals:
		_list.add_child(_row(g))
	reset_size()


func _row(g: Dictionary) -> Control:
	var done := bool(g.done)
	var row := HBoxContainer.new()
	row.name = String(g.id)
	row.add_theme_constant_override(&"separation", 10)
	var tick := AstraStyle.label("✓" if done else "○", 17, AstraStyle.GOOD if done else AstraStyle.TEXT_3, "Tick", true)
	tick.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	tick.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(tick)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var text := AstraStyle.label(String(g.text), 14, AstraStyle.TEXT_3 if done else AstraStyle.TEXT, "Text")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 190
	col.add_child(text)
	if not done:
		var m := AstraStyle.Meter.new(AstraStyle.ACCENT, 3.0)
		m.share = float(g.fraction)
		col.add_child(m)
	var lab := AstraStyle.label(String(g.label) if not done else "done", 11, AstraStyle.GOOD if done else AstraStyle.TEXT_3, "Label")
	lab.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(lab)
	return row
