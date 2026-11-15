class_name VoiceHud
extends PanelContainer
## The voice corner of the HUD (Prompt 11), bottom right, clear of the colony corner (top left), your crew card (top
## right), the messages and hints (bottom centre), the session status (bottom left) and the crosshair (centre).
## Line 1: what your voice does — "● Speaking nearby", "● Radio — heard after 15 s", "✖ No radio link outside…",
## "✖ No microphone — you can still listen", or the hint for holding V. Then, for a few seconds, what changed when you
## went outside or came in. Then who you hear ("♪ Ana — nearby", "♪ Ben — by radio, said 15 s ago"), radio messages
## still in the radio ("… heard in 12 s") and anyone talking whom you cannot hear (no radio link).
## VoiceService adds it under GameHud, so it hides with the HUD while a panel is open.

## Distance from the screen edges, pixels (the HUD's own margin).
const EDGE := 24
## Width of the corner, pixels at UI scale 1.
const WIDTH := 290.0
## Most "heard" lines shown at once.
const MAX_LINES := 4

var voice: VoiceService

var _own: Label
var _note: Label
var _heard: Label
var _timer := 0.0
var _last := ""
var _place_left := 0


func setup(p_voice: VoiceService) -> void:
	voice = p_voice
	name = "VoiceHud"
	theme = UiTheme.get_theme()
	theme_type_variation = UiTheme.HUD_PANEL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.name = "Box"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_own = _make_label(box, "Own", &"")
	_note = _make_label(box, "Transition", UiTheme.MUTED)
	_heard = _make_label(box, "Heard", &"")
	_place()
	refresh()


## The lines shown now (tests read them).
func own_text() -> String:
	return _own.text if _own != null else ""


func note_text() -> String:
	return _note.text if _note != null and _note.visible else ""


func heard_text() -> String:
	return _heard.text if _heard != null and _heard.visible else ""


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.1
	refresh()


func refresh() -> void:
	if voice == null or not is_instance_valid(voice) or _own == null:
		return
	var own := voice.own_line()
	_own.text = own
	if own.begins_with("✖"):
		_own.theme_type_variation = UiTheme.WARN
	elif voice.is_transmitting():
		_own.theme_type_variation = UiTheme.GOOD
	else:
		_own.theme_type_variation = UiTheme.MUTED
	var note := voice.transition_line()
	_note.text = note
	_note.visible = note != ""
	var lines := voice.heard_lines()
	if lines.size() > MAX_LINES:
		lines = lines.slice(0, MAX_LINES)
	_heard.text = "\n".join(lines)
	_heard.visible = not lines.is_empty()
	var sig := "%s|%s|%s|%s" % [_own.text, _note.text, _heard.text, get_viewport_rect().size if is_inside_tree() else Vector2.ZERO]
	_place_left -= 1
	if sig != _last or _place_left <= 0:
		_last = sig
		_place_left = 10         # once a second anyway: the hint strip below can change size
		_place()


## Keeps the box in the bottom-right corner at its content's size, above the HUD's bottom strip (hints, status)
## wherever that strip reaches across.
func _place() -> void:
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, EDGE)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	if not is_inside_tree():
		return
	var mine := get_global_rect()
	var limit := mine.end.y
	for strip: Control in _bottom_strip():
		if strip.is_visible_in_tree():
			var r := strip.get_global_rect()
			if r.position.x < mine.end.x and r.end.x > mine.position.x and r.end.y > mine.position.y:
				limit = minf(limit, r.position.y - 8.0)
	var shift := limit - mine.end.y
	if shift < 0.0:
		offset_top += shift
		offset_bottom += shift


var _strip: Array[Control] = []


## The HUD's bottom-edge boxes (GameHud names them "Hints" and "Status").
func _bottom_strip() -> Array[Control]:
	if _strip.is_empty() and get_parent() != null:
		for n: String in ["Hints", "Status"]:
			var c := get_parent().find_child(n, true, false) as Control
			if c != null and c != self:
				_strip.append(c)
	return _strip


func _make_label(parent: Control, label_name: String, variation: StringName) -> Label:
	var l := Label.new()
	l.name = label_name
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if variation != &"":
		l.theme_type_variation = variation
	parent.add_child(l)
	return l
