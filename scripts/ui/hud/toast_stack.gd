class_name ToastStack
extends VBoxContainer
## Pop-up notifications: small cards that slide in, stay a few seconds and go (longer for warnings and dangers).
## Each has a symbol and a colour by kind (good ✓, info ⓘ, warn ⚠, danger ✖) and a × to close it early.
## At most MAX on screen; the oldest makes room. The same text twice resets its timer instead of showing twice.

const MAX := 4
const SECONDS := {&"good": 5.0, &"info": 6.0, &"warn": 9.0, &"danger": 12.0}
const SYMBOLS := {&"good": "✓", &"info": "ⓘ", &"warn": "⚠", &"danger": "✖"}

var _toasts: Array[Dictionary] = []     # {"node", "text", "left"}
var reduce_motion := false


func _init() -> void:
	name = "Toasts"
	add_theme_constant_override(&"separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = 360


## Shows a pop-up. kind: &"good", &"info", &"warn" or &"danger".
func push(text: String, kind: StringName = &"info") -> void:
	var t := text.strip_edges()
	if t == "":
		return
	for e: Dictionary in _toasts:
		if String(e.text) == t:
			e.left = float(SECONDS.get(kind, 6.0))
			return
	while _toasts.size() >= MAX:
		_drop(_toasts[0])
	var card := _card(t, kind)
	add_child(card)
	_toasts.append({"node": card, "text": t, "left": float(SECONDS.get(kind, 6.0) + t.length() * 0.02)})
	if not reduce_motion:
		card.modulate.a = 0.0
		var tw := card.create_tween()
		tw.tween_property(card, "modulate:a", 1.0, 0.18)


func texts() -> PackedStringArray:
	var out := PackedStringArray()
	for e: Dictionary in _toasts:
		out.append(String(e.text))
	return out


func _process(delta: float) -> void:
	for e: Dictionary in _toasts.duplicate():
		e.left = float(e.left) - delta
		if float(e.left) <= 0.0:
			_drop(e)


func _drop(e: Dictionary) -> void:
	_toasts.erase(e)
	var n := e.node as Control
	if is_instance_valid(n):
		n.queue_free()


func _card(text: String, kind: StringName) -> PanelContainer:
	var color: Color = {&"good": AstraStyle.GOOD, &"warn": AstraStyle.WARN, &"danger": AstraStyle.DANGER}.get(kind, AstraStyle.C_O2)
	var style := AstraStyle.glass(AstraStyle.RADIUS_SM + 2, 12, 9, true)
	if kind == &"warn" or kind == &"danger":
		style.border_color = Color(color, 0.55)
		style.bg_color = Color(color.r * 0.18 + 0.05, color.g * 0.12 + 0.06, color.b * 0.12 + 0.14, 0.95)
	var p := AstraStyle.panel(style, "Toast")
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	p.add_child(row)
	var sym := AstraStyle.label(String(SYMBOLS.get(kind, "ⓘ")), 17, color, "Symbol", true)
	sym.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(sym)
	var l := AstraStyle.label(text, 14, AstraStyle.TEXT, "Text")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 260
	row.add_child(l)
	var x := AstraStyle.flat_button("×", 15, AstraStyle.TEXT_3)
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	x.tooltip_text = "Close"
	x.pressed.connect(func() -> void:
		for e: Dictionary in _toasts:
			if e.node == p:
				_drop(e)
				return)
	row.add_child(x)
	return p
