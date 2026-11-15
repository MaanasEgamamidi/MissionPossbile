class_name ToastStack
extends VBoxContainer
## Pop-up messages: small one-line chips that appear, stay a few seconds and go (longer for warnings and dangers).
## UI overhaul (2026-11-15): at most MAX (two) on screen, and each is ONE short line: a picture by kind (good = tick,
## info = round "i", warn = triangle "!", danger = octagon "!") and at most HudKit.MAX_WORDS words (HudKit.short_line).
## The whole sentence is the chip's tooltip, and the last messages stay readable in full in the Power drawer (P):
## recent(). The oldest chip makes room for a new one. The same text twice resets its timer instead of showing twice.

const HudKit := preload("res://scripts/ui/hud/hud_kit.gd")
const MAX := 2
const SECONDS := {&"good": 5.0, &"info": 6.0, &"warn": 9.0, &"danger": 12.0}
const ICONS := {&"good": &"check", &"info": &"info", &"warn": &"warn", &"danger": &"danger"}
## Words for a kind, for the accessible name ("Warning: ...").
const KIND_WORDS := {&"good": "Good news", &"info": "Note", &"warn": "Warning", &"danger": "Act now"}
## Widest a chip's line may be, in screen units at text size 1 (longer lines end in "…").
const MAX_LINE_WIDTH := 620.0
## Messages kept for the Power drawer's list.
const KEEP := 8

## The newest messages in full, newest last: [{"text", "kind"}]. Shared by every pop-up stack and GameHud's messages.
static var _recent: Array[Dictionary] = []

var _toasts: Array[Dictionary] = []     # {"node", "text", "left"}
var reduce_motion := false


func _init() -> void:
	name = "Toasts"
	add_theme_constant_override(&"separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Shows a pop-up. kind: &"good", &"info", &"warn" or &"danger".
func push(text: String, kind: StringName = &"info") -> void:
	var t := text.strip_edges()
	if t == "":
		return
	for e: Dictionary in _toasts:
		if String(e.text) == t:
			e.left = float(SECONDS.get(kind, 6.0))
			return
	remember(t, kind)
	while _toasts.size() >= MAX:
		_drop(_toasts[0])
	var card := _card(t, kind)
	add_child(card)
	_toasts.append({"node": card, "text": t, "left": float(SECONDS.get(kind, 6.0) + t.length() * 0.02)})
	if not reduce_motion:
		card.modulate.a = 0.0
		var tw := card.create_tween()
		tw.tween_property(card, "modulate:a", 1.0, 0.18)


## The full texts of the pop-ups on screen, oldest first.
func texts() -> PackedStringArray:
	var out := PackedStringArray()
	for e: Dictionary in _toasts:
		out.append(String(e.text))
	return out


## The short lines the pop-ups show, oldest first.
func shown_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for e: Dictionary in _toasts:
		var l := (e.node as Node).find_child("Text", true, false) as Label
		out.append(l.text if l != null else "")
	return out


## Keeps a message for the Power drawer's list (the same text again moves to the end instead of repeating).
static func remember(text: String, kind: StringName = &"info") -> void:
	var t := text.strip_edges()
	if t == "":
		return
	for i in range(_recent.size() - 1, -1, -1):
		if String(_recent[i].text) == t:
			_recent.remove_at(i)
	_recent.append({"text": t, "kind": kind})
	while _recent.size() > KEEP:
		_recent.pop_front()


## The newest messages in full, newest last: [{"text", "kind"}].
static func recent() -> Array[Dictionary]:
	return _recent.duplicate(true)


## Empties the message list (a new game starts clean).
static func forget_all() -> void:
	_recent.clear()


func _process(delta: float) -> void:
	for e: Dictionary in _toasts.duplicate():
		e.left = float(e.left) - delta
		if float(e.left) <= 0.0:
			_drop(e)


func _drop(e: Dictionary) -> void:
	_toasts.erase(e)
	var n := e.node as Control
	if is_instance_valid(n):
		# out of the box at once, so the stack's size is right in the same frame
		if n.get_parent() == self:
			remove_child(n)
		n.queue_free()


func _card(text: String, kind: StringName) -> PanelContainer:
	var color := HudKit.level_color(kind, AstraStyle.GOOD if kind == &"good" else AstraStyle.C_O2)
	var p := HudKit.Card.new("Toast", 14, 14, 8, true)
	if kind == &"warn" or kind == &"danger":
		p.tone = kind
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	row.add_child(HudKit.Icon.new(StringName(ICONS.get(kind, &"info")), color, 24.0, "Symbol"))
	var l := HudKit.Txt.new(HudKit.short_line(text), 20.0, AstraStyle.TEXT, "Text")
	# one line: a line wider than the room it has ends in "…"
	var font := l.get_theme_font(&"font")
	var wide := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size(&"font_size")).x if font != null else 0.0
	var room := MAX_LINE_WIDTH * UiTheme.text_scale()
	if wide > room:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size.x = room
	row.add_child(l)
	HudKit.say(p, "%s: %s" % [String(KIND_WORDS.get(kind, "Note")), text])
	return p
