extends PanelContainer
## The crew-day chip under the colony clock, top left (owner 2026-11-15, the strict day; plan §1.7):
##     08:00–12:30 · Work block: Greenhouse
##     ▬▬▬▬▬▬▬▬▭▭▭▭  (how far the block has run)
##     Late! Go to the Greenhouse — press H          (only while late, red)
##     Next 12:30 · Exercise (Rec kitchen)           (small)
## plus one small note when it matters: the crew day starts after the tutorial / hungry / weekly vitals due.
## Read only: everything comes from the colony state through scripts/schedule/ (CrewDay, ScheduleSystem). Refreshes
## itself 4 times a second. setup(services) is optional: without it the chip finds GameServices in the tree.

const CrewDay := preload("res://scripts/schedule/crew_day.gd")
const ScheduleSystem := preload("res://scripts/schedule/schedule_system.gd")
const ScheduleGate := preload("res://scripts/schedule/schedule_gate.gd")

const REFRESH_SECONDS := 0.25
const WIDTH := 300.0

var services: GameServices

var _line: Label
var _bar: ProgressBar
var _late: Label
var _next: Label
var _note: Label
var _style: StyleBoxFlat
var _left := 0.0


func _init() -> void:
	name = "ScheduleChip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_style = AstraStyle.pill(Color(AstraStyle.GLASS, 0.82), AstraStyle.RADIUS_SM, 12, 6, AstraStyle.LINE)
	add_theme_stylebox_override(&"panel", _style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_line = AstraStyle.label("", 14, AstraStyle.TEXT, "Block")
	col.add_child(_line)
	_bar = ProgressBar.new()
	_bar.name = "Progress"
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.custom_minimum_size = Vector2(WIDTH, 4)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.10)
	back.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = AstraStyle.C_SCIENCE
	fill.set_corner_radius_all(2)
	_bar.add_theme_stylebox_override(&"background", back)
	_bar.add_theme_stylebox_override(&"fill", fill)
	col.add_child(_bar)
	_late = AstraStyle.label("", 14, AstraStyle.DANGER, "Late")
	_late.visible = false
	col.add_child(_late)
	_next = AstraStyle.label("", 11, AstraStyle.TEXT_3, "Next")
	col.add_child(_next)
	_note = AstraStyle.label("", 11, AstraStyle.TEXT_2, "Note")
	_note.visible = false
	col.add_child(_note)
	for l: Label in [_line, _late, _next, _note]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(p_services: GameServices) -> void:
	services = p_services
	if services != null:
		ScheduleSystem.use_zones(services.zones)
	refresh()


func _ready() -> void:
	if services == null:
		setup(GameServices.find(get_tree()))


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		_left = REFRESH_SECONDS
		refresh()


## True while the chip says "Late!".
func is_late() -> bool:
	return _late.visible


## The words shown, top to bottom (for tests and the HUD's own checks).
func lines() -> PackedStringArray:
	var out := PackedStringArray([_line.text])
	for l: Label in [_late, _next, _note]:
		if l.visible and l.text != "":
			out.append(l.text)
	return out


func refresh() -> void:
	if services == null and is_inside_tree():
		services = GameServices.find(get_tree())
		if services != null:
			ScheduleSystem.use_zones(services.zones)
	if services == null or not services.has_game():
		visible = false
		return
	var state := services.state()
	var block := CrewDay.current_block(state)
	if block.is_empty():
		visible = false
		return
	visible = true
	var me := services.local_character()
	var id := String(block.id)
	var span := _span(state, id)
	var place := ScheduleSystem.place_words(state, me, id) if me != null else ""
	var title := String(block.name)
	if place != "":
		title += ": " + place
	_line.text = "%s–%s · %s" % [ScheduleGate.clock_words(span.x), ScheduleGate.clock_words(fmod(span.y, GameConfig.SOL_HOURS)), title]
	_bar.value = clampf(span.z, 0.0, 1.0)
	var late := me != null and ScheduleSystem.is_late(state, me)
	_late.visible = late
	if late:
		var where := place if place == "outside" else "the " + place
		_late.text = "Late! Go to %s — press H" % where
	var nb := ScheduleSystem.next_block(state)
	if nb.is_empty():
		_next.text = ""
	else:
		var nid := String(nb.id)
		var nplace := ScheduleSystem.place_words(state, me, nid) if me != null else ""
		_next.text = "Next %s · %s%s" % [ScheduleGate.clock_words(float(nb.start)), String(nb.name), " (%s)" % nplace if nplace != "" else ""]
	var note := ""
	if not ScheduleSystem.day_on(state):
		note = "The crew day starts when the tutorial is done."
	elif ScheduleSystem.emergency(state):
		note = "Emergency first: every station is open."
	elif me != null and ScheduleSystem.is_hungry(state, String(me.id)):
		note = "Hungry: you missed the meal. Body energy drops faster."
	elif me != null and ScheduleSystem.vitals_due(state, me):
		note = "Weekly vitals check due: visit the Med Bay in the morning."
	_note.text = note
	_note.visible = note != ""
	var c := AstraStyle.DANGER if late else AstraStyle.LINE
	_style.border_color = Color(c, 0.7) if late else c
	_style.bg_color = Color(0.25, 0.06, 0.12, 0.9) if late else Color(AstraStyle.GLASS, 0.82)


## (start hour, end hour, share done) of the block on screen. The evening sleep and the night sleep are one span.
static func _span(state: ColonyState, id: String) -> Vector3:
	var hour := CrewDay.hour_of(state)
	if id == "sleep" or id == "sleep_evening":
		var start := ScheduleSystem.block_bounds("sleep_evening").x
		var wake := ScheduleSystem.block_bounds("sleep").y
		var length := GameConfig.SOL_HOURS - start + wake
		var done := hour - start if id == "sleep_evening" else GameConfig.SOL_HOURS - start + hour
		return Vector3(start, wake, done / maxf(length, 0.01))
	var b := ScheduleSystem.block_bounds(id)
	return Vector3(b.x, b.y, (hour - b.x) / maxf(b.y - b.x, 0.01))
