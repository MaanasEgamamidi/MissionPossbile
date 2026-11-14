class_name UiLayoutCheck
extends RefCounted
## Automated layout checks used by every UI test: nothing outside the screen, no clipped text or buttons,
## every interactive control reachable by keyboard and showing a visible focus.
## A check reports problems as plain lines; an empty list means it passed.


## Problems with `root` laid out in a viewport of `screen` pixels. Call after at least two process frames.
static func problems(root: Control, screen: Vector2) -> PackedStringArray:
	var out := PackedStringArray()
	var area := Rect2(Vector2.ZERO, screen).grow(1.0)
	for c: Control in _visible_controls(root):
		var r := c.get_global_rect()
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if not area.encloses(r) and not _inside_scroll(c):
			out.append("%s is outside the screen: %s" % [_path(root, c), r])
		var min_size := c.get_combined_minimum_size()
		if (c is Button or c is Label or c is LineEdit or c is OptionButton) and not _inside_scroll(c):
			if r.size.x + 0.5 < min_size.x or r.size.y + 0.5 < min_size.y:
				out.append("%s is smaller than its content (%s < %s)" % [_path(root, c), r.size, min_size])
		if c is Label and (c as Label).clip_text:
			out.append("%s clips its text" % _path(root, c))
		if c is Button and (c as Button).clip_text:
			out.append("%s clips its text" % _path(root, c))
	return out


## Interactive controls (buttons, sliders, fields...) that are visible and can take focus.
static func focusable(root: Control) -> Array[Control]:
	var list: Array[Control] = []
	for c: Control in _visible_controls(root):
		if c.focus_mode == Control.FOCUS_ALL and not (c is ScrollContainer) and (c is BaseButton or c is Range or c is LineEdit or c is TextEdit or c is ItemList or c is Tree or c is TabBar):
			list.append(c)
	return list


## Problems with keyboard use: an interactive control that cannot take focus, or a theme with no visible focus style.
static func focus_problems(root: Control) -> PackedStringArray:
	var out := PackedStringArray()
	for c: Control in _visible_controls(root):
		if c is BaseButton and not (c as BaseButton).disabled and c.focus_mode == Control.FOCUS_NONE:
			out.append("%s cannot take keyboard focus" % _path(root, c))
		if c is BaseButton and c.focus_mode != Control.FOCUS_NONE:
			var style := c.get_theme_stylebox(&"focus")
			if style == null or style is StyleBoxEmpty:
				out.append("%s has no visible focus style" % _path(root, c))
	return out


static func _visible_controls(root: Control) -> Array[Control]:
	var list: Array[Control] = []
	_collect(root, list)
	return list


static func _collect(node: Node, list: Array[Control]) -> void:
	if node is Control:
		var c := node as Control
		if not c.is_visible_in_tree():
			return
		list.append(c)
	elif node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	for child in node.get_children():
		_collect(child, list)


static func _inside_scroll(c: Control) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


static func _path(root: Node, c: Node) -> String:
	return String(root.get_path_to(c)) if root.is_ancestor_of(c) else String(c.name)
