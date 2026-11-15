class_name MissionControlCard
extends PanelContainer
## "Mission Control" speaks up: a card in the lower left for the few things worth stopping for: a dust storm on its
## way, a scout report with the mast camera's picture, a supply about to run out.
## UI overhaul (2026-11-15): every card is ONE picture, a title of at most five words, ONE line of at most nine words
## saying what to do, and the OK key cap. Nothing else is on the HUD. The whole message (say()'s `text`) is the card's
## tooltip and accessible name and is kept in the message list of the Power & life support drawer (ToastStack.recent());
## a small "P More" hint shows when there is more to read than the line.
## One message at a time; others wait their turn (a warning goes ahead of waiting news). A message closes itself after
## a while (longer for long text), or with OK / the K key. Text and pictures follow the text size setting (HudKit).

signal shown(text: String)

const HudKit := preload("res://scripts/ui/hud/hud_kit.gd")
## Most words in a card's title and in its one line.
const MAX_TITLE_WORDS := 5
const MAX_LINE_WORDS := 9
## The picture of a card by kind, when say() names none.
const ICONS := {&"good": &"check", &"warn": &"warn", &"danger": &"danger"}
## Widest the words may be before they wrap, at text size 1 (MissionHud narrows it to the room beside the dock).
const TEXT_WIDTH := 420.0

var _queue: Array[Dictionary] = []      # {"title", "text", "kind", "image", "sub", "line", "icon"}
var _current: Dictionary = {}
var _left := 0.0
var _icon: HudKit.Icon
var _title: HudKit.Txt
var _text: HudKit.Txt
var _image: TextureRect
var _ok: Button
var _more: Control
var _room := 0.0
var _style_key := ""


func _init() -> void:
	name = "MissionControl"
	mouse_filter = Control.MOUSE_FILTER_PASS
	_restyle()
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon = HudKit.Icon.new(&"radio", AstraStyle.ACCENT, 52.0, "Symbol")
	_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_title = HudKit.Txt.new("", 24.0, AstraStyle.TEXT, "Title", true)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)
	_image = TextureRect.new()
	_image.name = "Picture"
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_image.custom_minimum_size = Vector2(340, 160)
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.visible = false
	col.add_child(_image)
	_text = HudKit.Txt.new("", 20.0, AstraStyle.TEXT_2, "Text")
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_text)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override(&"separation", 8)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(actions)
	actions.add_child(HudKit.key_cap(_key(&"advisor_ok", "K"), 18.0, "OkKey"))
	_ok = Button.new()
	_ok.name = "Ok"
	_ok.text = "OK"
	_ok.focus_mode = Control.FOCUS_NONE          # the HUD is not a menu: K is the key, the button is for the mouse
	_ok.add_theme_color_override(&"font_color", AstraStyle.TEXT)
	_ok.add_theme_color_override(&"font_hover_color", AstraStyle.TEXT)
	_ok.add_theme_stylebox_override(&"normal", AstraStyle.pill(Color(1, 1, 1, 0.1), AstraStyle.RADIUS_SM, 16, 3, AstraStyle.LINE_STRONG))
	_ok.add_theme_stylebox_override(&"hover", AstraStyle.pill(Color(1, 1, 1, 0.2), AstraStyle.RADIUS_SM, 16, 3, AstraStyle.TEXT_2))
	_ok.add_theme_stylebox_override(&"pressed", AstraStyle.pill(Color(1, 1, 1, 0.26), AstraStyle.RADIUS_SM, 16, 3, AstraStyle.TEXT))
	_ok.pressed.connect(dismiss)
	actions.add_child(_ok)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_child(gap)
	var more := HBoxContainer.new()
	more.name = "More"
	more.add_theme_constant_override(&"separation", 6)
	more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	more.modulate.a = 0.75
	more.add_child(HudKit.key_cap(_key(&"power_view", "O"), 14.0, "MoreKey"))
	more.add_child(HudKit.Txt.new("More", 16.0, AstraStyle.TEXT_3, "MoreWord"))
	actions.add_child(more)
	_more = more
	_fit_fonts()
	visible = false


## Queues a message. kind: &"info", &"warn", &"danger", &"good". `text` is the whole message (kept for the tooltip and
## the Power drawer's message list); the card shows `line` (default: the first short sentence of `text`) under the
## title, and the pictogram `icon` (a HudKit kind; default by kind).
func say(title: String, text: String, kind: StringName = &"info", image: Texture2D = null, subtitle := "Colony radio",
		line := "", icon: StringName = &"") -> void:
	for m: Dictionary in _queue:
		if String(m.text) == text:
			return
	if not _current.is_empty() and String(_current.text) == text:
		return
	var message := {"title": title, "text": text, "kind": kind, "image": image, "sub": subtitle, "line": line, "icon": icon}
	# a warning does not wait behind news
	var at := _queue.size()
	if kind == &"warn" or kind == &"danger":
		for i in _queue.size():
			if not (_queue[i].kind in [&"warn", &"danger"]):
				at = i
				break
	_queue.insert(at, message)
	ToastStack.remember(text, kind)
	if _current.is_empty():
		_next()


## The whole message now shown (not only the line on the card), or "".
func current_text() -> String:
	return String(_current.get("text", ""))


## The title on the card now (five words at most).
func shown_title() -> String:
	return _title.text if not _current.is_empty() else ""


## The one line on the card now (nine words at most).
func shown_line() -> String:
	return _text.text if not _current.is_empty() else ""


func dismiss() -> void:
	_current = {}
	_next()


## The room the card may take, in screen units (MissionHud: from the screen edge to the dock). Long words wrap in it.
func fit(room: float) -> void:
	if not is_equal_approx(room, _room):
		_room = room
		_fit_width()


## At most `max_words` words of `text` ("…" after a cut).
static func clip_words(text: String, max_words: int) -> String:
	var words := text.strip_edges().split(" ", false)
	if words.size() <= max_words:
		return " ".join(words)
	words.resize(max_words)
	return " ".join(words).trim_suffix(",").trim_suffix(":").trim_suffix(".") + "…"


func _next() -> void:
	if _queue.is_empty():
		visible = false
		return
	_current = _queue.pop_front()
	var kind: StringName = _current.kind
	var color: Color = HudKit.level_color(kind, AstraStyle.GOOD if kind == &"good" else AstraStyle.ACCENT)
	var icon := StringName(_current.get("icon", &""))
	_icon.kind = icon if icon != &"" else StringName(ICONS.get(kind, &"radio"))
	_icon.color = color
	_title.text = clip_words(String(_current.title), MAX_TITLE_WORDS)
	var full := String(_current.text)
	var line := String(_current.get("line", ""))
	_text.text = clip_words(line, MAX_LINE_WORDS) if line != "" else HudKit.short_line(full, MAX_LINE_WORDS)
	_text.visible = _text.text != ""
	_more.visible = full.strip_edges().trim_suffix(".") != _text.text.trim_suffix(".")
	var img := _current.image as Texture2D
	_image.texture = img
	_image.visible = img != null
	HudKit.say(self, "%s. %s (%s)" % [String(_current.title), full, String(_current.sub)])
	_left = maxf(10.0, full.length() * 0.085)
	_restyle()
	_fit_width()
	visible = true
	reset_size()
	shown.emit(full)


func _process(delta: float) -> void:
	if _current.is_empty():
		return
	_left -= delta
	if _left <= 0.0:
		dismiss()


## Short words keep their own width; words wider than the room wrap at it.
func _fit_width() -> void:
	if _title == null:
		return
	var s := UiTheme.text_scale()
	var widest := TEXT_WIDTH * s
	if _room > 0.0:
		# the card's own frame, the picture and the gap beside it
		widest = clampf(_room - (52.0 * s + 14.0 + 2.0 * 16.0 + 4.0), 220.0, widest)
	for l: Label in [_title, _text]:
		var font := l.get_theme_font(&"font")
		var w := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size(&"font_size")).x if font != null else widest
		l.custom_minimum_size.x = ceilf(minf(w + 2.0, widest))
	_image.custom_minimum_size = Vector2(minf(340.0, widest), 160.0)


func _fit_fonts() -> void:
	var want := roundi(20.0 * UiTheme.text_scale())
	if _ok != null and (not _ok.has_theme_font_size_override(&"font_size") or _ok.get_theme_font_size(&"font_size") != want):
		_ok.add_theme_font_size_override(&"font_size", want)


## The glass card look, with a coloured edge for a warning (amber) or a danger (red): the picture carries the shape.
func _restyle() -> void:
	var kind := StringName(_current.get("kind", &"info"))
	var contrast := UiTheme.is_high_contrast()
	var key := "%s|%s" % [kind, contrast]
	if key == _style_key:
		return
	_style_key = key                 # noted first: the override below sends THEME_CHANGED
	var s := AstraStyle.glass(AstraStyle.RADIUS, 16, 12, true)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	if kind == &"warn" or kind == &"danger":
		var c := HudKit.level_color(kind)
		s.border_color = Color(c, 0.95 if contrast else 0.7)
		s.set_border_width_all(2)
	elif contrast:
		s.set_border_width_all(2)
	add_theme_stylebox_override(&"panel", s)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _title != null:
		_restyle()
		_fit_fonts()
		_fit_width.call_deferred()       # after the labels took their new size


static func _key(action: StringName, fallback: String) -> String:
	var k := PlayerInput.describe(action)
	return k if k != "" and not k.contains("/") else fallback
