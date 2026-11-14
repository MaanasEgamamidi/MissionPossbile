class_name MissionControlCard
extends PanelContainer
## "Mission Control" speaks up: a card in the lower left with a round badge, a title, a message and an OK. It is for
## the things worth stopping to read: a dust storm on its way (and how many more are expected), a scout report with
## the mast camera's picture, a supply about to run out. One message at a time; others wait their turn. A message
## closes itself after a while (longer for long text), or with OK / the K key.

signal shown(text: String)

var _queue: Array[Dictionary] = []      # {"title", "text", "kind", "image"}
var _current: Dictionary = {}
var _left := 0.0
var _badge: Label
var _title: Label
var _sub: Label
var _text: Label
var _image: TextureRect
var _ok: Button


func _init() -> void:
	name = "MissionControl"
	add_theme_stylebox_override(&"panel", AstraStyle.glass(AstraStyle.RADIUS, 14, 12, true))
	custom_minimum_size.x = 400
	mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	add_child(row)
	var badge_box := AstraStyle.panel(AstraStyle.pill(Color(AstraStyle.ACCENT, 0.2), 999, 9, 6, Color(AstraStyle.ACCENT, 0.6)), "Badge")
	badge_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(badge_box)
	_badge = AstraStyle.label("◎", 20, AstraStyle.ACCENT, "Symbol", true)
	badge_box.add_child(_badge)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	col.add_child(head)
	_title = AstraStyle.label("Mission Control", 15, AstraStyle.TEXT, "Title")
	head.add_child(_title)
	_sub = AstraStyle.label("Colony radio", 11, AstraStyle.TEXT_3, "Sub")
	_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_sub)
	_image = TextureRect.new()
	_image.name = "Picture"
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_image.custom_minimum_size = Vector2(320, 150)
	_image.visible = false
	col.add_child(_image)
	_text = AstraStyle.label("", 14, AstraStyle.TEXT_2, "Text")
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 300
	col.add_child(_text)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 8)
	col.add_child(actions)
	_ok = AstraStyle.flat_button("OK", 14, AstraStyle.TEXT)
	_ok.pressed.connect(dismiss)
	actions.add_child(_ok)
	actions.add_child(AstraStyle.keycap("K", 10))
	visible = false


## Queues a message. kind: &"info", &"warn", &"danger", &"good".
func say(title: String, text: String, kind: StringName = &"info", image: Texture2D = null, subtitle := "Colony radio") -> void:
	for m: Dictionary in _queue:
		if String(m.text) == text:
			return
	if not _current.is_empty() and String(_current.text) == text:
		return
	_queue.append({"title": title, "text": text, "kind": kind, "image": image, "sub": subtitle})
	if _current.is_empty():
		_next()


func current_text() -> String:
	return String(_current.get("text", ""))


func dismiss() -> void:
	_current = {}
	_next()


func _next() -> void:
	if _queue.is_empty():
		visible = false
		return
	_current = _queue.pop_front()
	var kind: StringName = _current.kind
	var color: Color = {&"good": AstraStyle.GOOD, &"warn": AstraStyle.WARN, &"danger": AstraStyle.DANGER}.get(kind, AstraStyle.ACCENT)
	_badge.text = {&"good": "✓", &"warn": "⚠", &"danger": "✖"}.get(kind, "◎")
	AstraStyle.set_color(_badge, color)
	_title.text = String(_current.title)
	_sub.text = String(_current.sub)
	_text.text = String(_current.text)
	var img := _current.image as Texture2D
	_image.texture = img
	_image.visible = img != null
	_left = maxf(10.0, String(_current.text).length() * 0.085)
	visible = true
	reset_size()
	shown.emit(String(_current.text))


func _process(delta: float) -> void:
	if _current.is_empty():
		return
	_left -= delta
	if _left <= 0.0:
		dismiss()
