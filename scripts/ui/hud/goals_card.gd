class_name GoalsCard
extends PanelContainer
## The goals card on the left: "GOALS 2/7 ⌃". Open, it lists the goals with a ring (○) or a tick (✓), a thin progress
## line and a short count ("1 / 3"). Folded (key J or a click on the header) it is just the header. Goals come from
## ColonyGoals, checked from the real colony state.

signal toggled(open: bool)

var services: GameServices
var open := true

var _head: HBoxContainer
var _count: Label
var _chev: Label
var _list: VBoxContainer
var _sig := ""


func setup(p_services: GameServices) -> void:
	services = p_services
	name = "GoalsCard"
	add_theme_stylebox_override(&"panel", AstraStyle.glass(AstraStyle.RADIUS, 14, 10))
	mouse_filter = Control.MOUSE_FILTER_PASS
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
	_head.add_child(AstraStyle.keycap("J", 10))
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.add_theme_constant_override(&"separation", 10)
	col.add_child(_list)
	custom_minimum_size.x = 300
	refresh()


func toggle() -> void:
	set_open(not open)


func set_open(on: bool) -> void:
	if on == open:
		return
	open = on
	_list.visible = open
	_chev.text = "⌃" if open else "⌄"
	toggled.emit(open)
	reset_size()


func refresh() -> void:
	if services == null or not services.has_game():
		return
	var st := services.state()
	var n := ColonyGoals.done_count(st)
	_count.text = "%d/%d" % [n.x, n.y]
	_list.visible = open
	_chev.text = "⌃" if open else "⌄"
	var goals := ColonyGoals.shown(st)
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
