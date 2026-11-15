class_name GoalsCard
extends PanelContainer
## The goals card on the left. Two looks of its own:
##   next     (open = true, the look a new game starts with) "NEXT GOAL 2/11 ⌃ [J] map" and under it the ONE goal to
##            do next, large: its pictogram, a short title and one line of detail: progress pips and a count for a
##            counted goal ("●●○○○○ 2/6"), or for a repair the badge of who can do it and the room. The goal is the
##            first open one this machine's crew member can do (ColonyGoals.next); when only other specialists' jobs
##            are left the badge carries a padlock and the line says who is needed. Every other goal is one key press
##            away (J: the big goals screen).
##   compact  (open = false) just "GOALS 3/12" and a thin progress bar for all the goals, "J: next".
## Owner 2026-11-14, J cycles three looks: next -> the big goals screen with the map (scripts/ui/hud/goals_big_panel.gd,
## opened by MissionHud) -> compact -> next ... Closing the big screen (J, Esc or ✕) always lands on compact. A click on
## the header (or anywhere on the compact card) swaps next and compact. Goals come from ColonyGoals, checked from the
## real colony state. Pictures are drawn in code (scripts/ui/hud/goal_art.gd).

signal toggled(open: bool)

const GoalArt := preload("res://scripts/ui/hud/goal_art.gd")
const LIST_WIDTH := 324.0
const COMPACT_WIDTH := 190.0
## Side of the next goal's pictogram tile, before the player's text size.
const ICON_SIDE := 56.0

var services: GameServices
## True: the next-goal look. False: the compact look.
var open := true

var _head: HBoxContainer
var _title: Label
var _count: Label
var _chev: Label
## The word after the J keycap in the header: what J does next ("map" from the next goal, "next" from compact).
var _key_hint: Label
## Holds the one row of the next goal (named after the goal's id).
var _list: VBoxContainer
## Compact look: one thin bar for all the goals (done / total).
var _bar: AstraStyle.Meter
var _sig := ""
## True while the colony has one counted goal only (tapes first), and once every goal is done.
var _single := false
var _all_done := false


func setup(p_services: GameServices) -> void:
	services = p_services
	name = "GoalsCard"
	add_theme_stylebox_override(&"panel", AstraStyle.glass(AstraStyle.RADIUS, 14, 10))
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Compact look: a click anywhere on the card opens the next goal (the header handles its own clicks).
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
	_title = AstraStyle.label("NEXT GOAL", 12, AstraStyle.TEXT_2, "Title")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.add_child(_title)
	_count = AstraStyle.label("0/0", 13, AstraStyle.TEXT, "Count")
	_head.add_child(_count)
	_chev = AstraStyle.label("⌃", 14, AstraStyle.TEXT_2, "Chevron", true)
	_head.add_child(_chev)
	_head.add_child(AstraStyle.keycap(GameHud._key(&"goals", "J"), 11))
	_key_hint = AstraStyle.label("map", 12, AstraStyle.TEXT_2, "KeyHint")
	_head.add_child(_key_hint)
	_bar = AstraStyle.Meter.new(AstraStyle.ACCENT, 3.0)
	_bar.name = "Progress"
	_bar.visible = false
	col.add_child(_bar)
	_list = VBoxContainer.new()
	_list.name = "List"
	col.add_child(_list)
	_show_look()
	refresh()


## Swaps the next-goal and compact looks (a click on the header).
func toggle() -> void:
	set_open(not open)


## True: the next-goal look. False: the compact look ("GOALS x/y" and a thin bar).
func set_open(on: bool) -> void:
	if on == open:
		return
	open = on
	_show_look()
	toggled.emit(open)
	reset_size()


func _show_look() -> void:
	_list.visible = open
	_bar.visible = not open
	_title.text = "NEXT GOAL" if open and not _all_done else "GOALS"
	# With a single goal (tapes first) the next look's own pips say it all: "0/1" beside "2/6" would only confuse.
	_count.visible = not (_single and open)
	_chev.text = "⌃" if open else "⌄"
	_key_hint.text = "map" if open else "next"
	custom_minimum_size.x = LIST_WIDTH if open else COMPACT_WIDTH
	mouse_default_cursor_shape = Control.CURSOR_ARROW if open else Control.CURSOR_POINTING_HAND


func refresh() -> void:
	if services == null or not services.has_game():
		return
	var st := services.state()
	var n := ColonyGoals.done_count(st)
	_count.text = "%d/%d" % [n.x, n.y]
	_bar.share = float(n.x) / float(n.y) if n.y > 0 else 0.0
	var spec := local_specialty()
	var goal := ColonyGoals.next(st, spec)
	_all_done = n.y > 0 and n.x >= n.y
	# A single counted goal (tapes first: "Find the tapes"): the compact look counts its tapes, not "0/1" goals.
	_single = n.y == 1 and int(goal.get("need", 0)) > 0
	if _single:
		_count.text = "%d/%d" % [int(goal.have), int(goal.need)]
		_bar.share = float(goal.fraction)
	_show_look()
	# The row is rebuilt only when what it shows changes: the goal, who is looking, or the player's text settings.
	var sig := JSON.stringify([goal, spec, UiTheme.text_scale(), UiTheme.is_high_contrast()])
	if sig == _sig:
		return
	_sig = sig
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if not goal.is_empty():
		_list.add_child(_next_row(goal, spec))
	reset_size()


## Specialty of the crew member this machine's player controls, or "".
func local_specialty() -> String:
	if services == null or not services.has_game():
		return ""
	var me := services.local_character()
	return String(me.specialty) if me != null else ""


## The goal shown large, or {} (tests and tools).
func next_goal() -> Dictionary:
	if services == null or not services.has_game():
		return {}
	return ColonyGoals.next(services.state(), local_specialty())


## The one row of the next look: pictogram, short title and one detail line.
func _next_row(g: Dictionary, spec: String) -> Control:
	# Only a finished goal when nothing is left to do: then the card says so with a star.
	var done := bool(g.done)
	var k := UiTheme.text_scale()
	var kind := String(g.get("kind", ""))
	var tint: Color = AstraStyle.GOOD if done else (GoalArt.GOLD if kind in ["tapes_found", "tapes_played"] else AstraStyle.ACCENT)
	var row := HBoxContainer.new()
	row.name = String(g.id)
	row.add_theme_constant_override(&"separation", 12)
	var icon := GoalArt.Icon.new("star" if done else GoalArt.icon_of(g), ICON_SIDE * k, tint)
	icon.name = "Icon"
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 5)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	var text := AstraStyle.label("All goals done!" if done else String(g.text), 19, AstraStyle.TEXT, "Text")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 170
	col.add_child(text)
	var detail := HBoxContainer.new()
	detail.name = "Detail"
	detail.add_theme_constant_override(&"separation", 8)
	col.add_child(detail)
	if done:
		detail.add_child(GoalArt.Status.new(true, 20.0 * k))
		detail.add_child(AstraStyle.label("Great work!", 14, AstraStyle.GOOD, "Label"))
	elif int(g.get("need", 0)) > 0:
		var pips := GoalArt.Pips.new(int(g.have), int(g.need), 12.0 * k, tint)
		pips.name = "Pips"
		detail.add_child(pips)
		detail.add_child(AstraStyle.label(String(g.label), 14, AstraStyle.TEXT_2, "Label"))
	elif kind == "fix":
		var mine := ColonyGoals.can_do(g, spec)
		var who := GoalArt.Who.new(String(g.get("spec", "")), 28.0 * k, not mine)
		who.name = "Who"
		detail.add_child(who)
		# Where to go; or, for a job of another specialist, who is needed (the padlock's meaning in words).
		var words := String(g.get("room", "")) if mine else "Needs the %s" % String(g.get("role", "specialist"))
		var place := AstraStyle.label(words, 14 if mine else 13, AstraStyle.TEXT_2, "Label")
		place.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		place.custom_minimum_size.x = 150
		place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.add_child(place)
	elif String(g.get("label", "")) != "":
		detail.add_child(AstraStyle.label(String(g.label), 14, AstraStyle.TEXT_2, "Label"))
	else:
		detail.visible = false
	return row
