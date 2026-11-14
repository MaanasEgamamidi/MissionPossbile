class_name TutorialHud
extends PanelContainer
## The tutorial tracker on the HUD (Prompt 12): the stage, the open step, the specialist cue, the explanation (unless
## already mastered), hints when they are due, a reminder line, and the campaign goal after the tutorial.
## It sits on the right edge below the crew box, so it never covers the colony corner (top left), the crew box (top
## right), the messages (top centre) or the crosshair. It only shows what TutorialPresenter.view() gives it.

## Width in screen units (the text wraps inside it).
const WIDTH := 360.0
## Gap to the screen edge and to the crew box above it.
const EDGE := 16.0
## Lowest share of the screen height it may reach (the key hints and subtitles live below).
const BOTTOM_SHARE := 0.78

var services: GameServices
var title_label: Label
var progress_label: Label
var objective_label: Label
var cue_label: Label
var explain_label: Label
var hint_label: Label
var reminder_label: Label
var goal_label: Label
var footer_label: Label
var _scroll: ScrollContainer
var _top := -1.0


func setup(p_services: GameServices) -> void:
	services = p_services
	theme = UiTheme.get_theme()
	theme_type_variation = UiTheme.HUD_PANEL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scroll)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 4)
	_scroll.add_child(box)
	title_label = _label(box, "Title", UiTheme.HEADING)
	progress_label = _label(box, "Progress", UiTheme.MUTED)
	objective_label = _label(box, "Objective", &"")
	cue_label = _label(box, "Cue", UiTheme.GOOD)
	explain_label = _label(box, "Explain", UiTheme.MUTED)
	hint_label = _label(box, "Hint", UiTheme.WARN)
	reminder_label = _label(box, "Reminder", UiTheme.MUTED)
	goal_label = _label(box, "Goal", &"")
	footer_label = _label(box, "Footer", UiTheme.MUTED)
	_layout()


func _label(parent: Control, n: String, variation: StringName) -> Label:
	var l := Label.new()
	l.name = n
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != &"":
		l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Shows a view from TutorialPresenter.view().
func show_view(v: Dictionary) -> void:
	_put(title_label, String(v.get("title", "")))
	_put(progress_label, String(v.get("progress", "")))
	_put(objective_label, String(v.get("objective", "")))
	_put(cue_label, String(v.get("cue", "")))
	var hints: PackedStringArray = v.get("hints", PackedStringArray())
	# A due hint takes the explanation's place, so the tracker stays short.
	_put(explain_label, String(v.get("explain", "")) if hints.is_empty() else "")
	var hint_lines := PackedStringArray()
	for h in hints:
		hint_lines.append("Hint: " + h)
	_put(hint_label, "\n".join(hint_lines))
	_put(reminder_label, String(v.get("reminder", "")))
	_put(goal_label, "\n".join(v.get("goal", PackedStringArray()) as PackedStringArray))
	_put(footer_label, String(v.get("footer", "")))
	visible = title_label.text != "" or reminder_label.text != ""
	_layout()


func _put(l: Label, text: String) -> void:
	l.text = text
	l.visible = text != ""


## Puts the tracker below `top_y` (the bottom of the HUD's crew box), or at 36 % of the screen height without one.
func place_below(top_y: float) -> void:
	_top = top_y
	_layout()


func _layout() -> void:
	var screen := get_viewport_rect_safe()
	var top := _top + 12.0 if _top >= 0.0 else screen.y * 0.36
	var bottom := screen.y * BOTTOM_SHARE
	offset_left = -WIDTH - EDGE
	offset_right = -EDGE
	offset_top = top
	var style := get_theme_stylebox(&"panel")
	var pad := style.get_minimum_size() if style != null else Vector2.ZERO
	var wanted: float = (_scroll.get_child(0) as Control).get_combined_minimum_size().y if _scroll.get_child_count() > 0 else 0.0
	var room := maxf(80.0, bottom - top - pad.y)
	var inner := minf(wanted, room)
	_scroll.custom_minimum_size = Vector2(WIDTH - pad.x, inner)
	offset_bottom = top + inner + pad.y


func get_viewport_rect_safe() -> Vector2:
	if is_inside_tree():
		return get_viewport_rect().size
	return Vector2(1920, 1080)


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		var vp := get_viewport()
		if vp != null and not vp.size_changed.is_connected(_layout):
			vp.size_changed.connect(_layout)
		_layout()
	elif what == NOTIFICATION_EXIT_TREE:
		var vp := get_viewport()
		if vp != null and vp.size_changed.is_connected(_layout):
			vp.size_changed.disconnect(_layout)


## Every visible line of text, top to bottom (for tests).
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for l: Label in [title_label, progress_label, objective_label, cue_label, explain_label, hint_label, reminder_label, goal_label, footer_label]:
		if l.visible and l.text != "":
			out.append(l.text)
	return out
