class_name SubtitleLine
extends Control
## One subtitle line at the bottom centre of the screen: a dark box (readable on any background), the speaker's name
## if given, and the text, which wraps. Messages wait in a queue and show one after another.
## When `settings.subtitles` is off, only messages marked essential are shown.

## Widest the box gets, as a share of the screen width; longer text wraps.
const MAX_WIDTH_SHARE := 0.6
## Space kept free under the subtitle box (screen units): the HUD's key hint strip lives there.
const CLEAR_BELOW := 56.0

var settings: GameSettings

var _box: PanelContainer
var _speaker: Label
var _text: Label
var _queue: Array[Dictionary] = []
var _left := 0.0


func _init() -> void:
	name = "SubtitleLine"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.theme_type_variation = UiTheme.SCREEN_MARGIN
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_END
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	_box = PanelContainer.new()
	_box.theme_type_variation = UiTheme.SUBTITLE
	_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.visible = false
	column.add_child(_box)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(lines)
	_speaker = Label.new()
	_speaker.theme_type_variation = UiTheme.HEADING
	_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.add_child(_speaker)
	_text = Label.new()
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.add_child(_text)
	# Room under the subtitle for the HUD's key hint strip, so the two never cover each other.
	var clear_hints := Control.new()
	clear_hints.name = "ClearHints"
	clear_hints.custom_minimum_size.y = CLEAR_BELOW
	clear_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(clear_hints)


func _ready() -> void:
	if theme == null:
		theme = UiTheme.get_theme()


## Queues a message for `seconds`. `speaker` is shown above the text when given. Non-essential messages are dropped
## while subtitles are switched off.
func show_line(text: String, seconds := 4.0, speaker := "", essential := false) -> void:
	if text.strip_edges() == "":
		return
	if settings != null and not settings.subtitles and not essential:
		return
	_queue.append({"text": text, "seconds": maxf(0.5, seconds), "speaker": speaker})
	if not _box.visible:
		_next()


## The text on screen now, or "" when nothing shows.
func current_text() -> String:
	return _text.text if _box.visible else ""


## The speaker shown now, or "".
func current_speaker() -> String:
	return _speaker.text if _box.visible and _speaker.visible else ""


## How many messages wait after the current one.
func queued_count() -> int:
	return _queue.size()


## Removes everything, including the line on screen.
func clear() -> void:
	_queue.clear()
	_box.visible = false
	_left = 0.0


func _process(delta: float) -> void:
	if not _box.visible:
		return
	_left -= delta
	if _left <= 0.0:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_box.visible = false
		return
	var line: Dictionary = _queue.pop_front()
	var speaker: String = line.speaker
	_speaker.text = speaker
	_speaker.visible = speaker != ""
	_text.text = String(line.text)
	_left = float(line.seconds)
	_fit_width()
	_box.visible = true


## Short text keeps its own width; long text wraps at a share of the screen width.
func _fit_width() -> void:
	var max_w := 800.0
	if is_inside_tree():
		max_w = get_viewport_rect().size.x * MAX_WIDTH_SHARE
	var font := _text.get_theme_font(&"font")
	var font_size := _text.get_theme_font_size(&"font_size")
	var w := font.get_string_size(_text.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x if font != null else max_w
	if w > max_w:
		_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_text.custom_minimum_size.x = max_w
	else:
		_text.autowrap_mode = TextServer.AUTOWRAP_OFF
		_text.custom_minimum_size.x = 0.0
