extends RefCounted
## Building blocks shared by the menus (main menu, pause, settings, voice, crew): pictograms drawn in code, big picture
## buttons, switches with a pictogram and a short word, "pick one" rows of large buttons, and key hints.
## No class_name on purpose: load it with  const Kit = preload("res://scripts/ui/menu_kit.gd").
##
## Why: a nine-year-old should see what a button does before reading it. Every action gets a picture and at most a few
## words; the longer explanation goes in the tooltip.
## Colours come from UiTheme.palette() when a pictogram is drawn, so they follow high contrast without a rebuild.

## Design grid of every pictogram (units); it is scaled to the size asked for.
const GRID := 24.0


## A pictogram as a texture, for Button.icon, CheckButton.icon, TextureRect and TabContainer.set_tab_icon().
## `ink` is a UiTheme.palette() role (&"text", &"primary_text", &"heading"...) or a Color.
static func pic(kind: StringName, px := 28.0, ink: Variant = &"text") -> Texture2D:
	var p := Pic.new()
	p.kind = kind
	p.px = px
	p.ink = ink
	return p


## A pictogram on its own (not focusable, ignores the mouse).
static func picture(kind: StringName, px := 28.0, ink: Variant = &"text") -> TextureRect:
	var t := TextureRect.new()
	t.texture = pic(kind, px, ink)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


## A button with a pictogram on the left and a word. `font_scale` makes its text larger than the theme's button text
## and keeps following the player's text size. `variation` is a UiTheme button variation or &"".
static func button(text: String, kind: StringName, variation: StringName = &"", icon_px := 28.0, font_scale := 1.0, min_height := 56.0) -> Button:
	var b := ScaledButton.new()
	b.font_scale = font_scale
	b.text = text
	b.theme_type_variation = variation
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = min_height
	if kind != &"":
		b.icon = pic(kind, icon_px, &"primary_text" if variation == UiTheme.PRIMARY_BUTTON else &"text")
		b.add_theme_constant_override(&"h_separation", 14)
	return b


## A square-ish picture button: the pictogram on top, the word under it, centred.
static func tile(text: String, kind: StringName, icon_px := 44.0, min_size := Vector2(150, 104), variation: StringName = &"") -> Button:
	var b := ScaledButton.new()
	b.text = text
	b.theme_type_variation = variation
	b.icon = pic(kind, icon_px, &"primary_text" if variation == UiTheme.PRIMARY_BUTTON else &"text")
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = min_size
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


## An on/off switch with a pictogram and a one to three word label; the explanation is the tooltip.
static func toggle(text: String, kind: StringName, tip: String, on_toggle: Callable = Callable()) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.icon = pic(kind, 28.0)
	c.tooltip_text = tip
	c.custom_minimum_size = Vector2(300, 56)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_theme_constant_override(&"h_separation", 14)
	if on_toggle.is_valid():
		c.toggled.connect(on_toggle)
	return c


## A pictogram, a short name and (optionally) a value on one line: the heading of a slider or of a "pick one" row.
## Returns the row; the value label is its child "Value".
static func caption(text: String, kind: StringName, tip := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.tooltip_text = tip
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override(&"separation", 12)
	if kind != &"":
		row.add_child(picture(kind, 28.0))
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = text
	row.add_child(name_label)
	var value := Label.new()
	value.name = "Value"
	value.theme_type_variation = UiTheme.READING
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return row


## A key cap with a pictogram in it (arrow keys), in the same look as UiTheme.key_cap.
static func key_pic(kind: StringName) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.theme_type_variation = UiTheme.KEYCAP
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.add_child(picture(kind, 20.0))
	return cap


## A one-line hint made of key caps and words: ["up", "down", "Choose", "Enter", "Select"]. An entry starting with
## "pic:" is a pictogram key cap ("pic:up"), "key:" a key cap with that text, anything else a word.
static func key_hint(parts: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part: String in parts:
		if part.begins_with("pic:"):
			row.add_child(key_pic(StringName(part.trim_prefix("pic:"))))
		elif part.begins_with("key:"):
			row.add_child(UiTheme.key_cap(part.trim_prefix("key:")))
		else:
			var word := Label.new()
			word.text = part + "  "
			word.theme_type_variation = UiTheme.MUTED
			row.add_child(word)
	return row


## A box in the card look with a coloured edge, for a selected card ("this is you").
static func card_box(edge: Color, width := 3) -> StyleBoxFlat:
	var p := UiTheme.palette()
	var s := StyleBoxFlat.new()
	s.bg_color = p.card
	s.set_corner_radius_all(12)
	s.border_color = edge
	s.set_border_width_all(width)
	s.set_content_margin_all(14)
	return s


## A Button whose text is `font_scale` times the theme's button text and keeps following the player's text size.
class ScaledButton extends Button:
	var font_scale := 1.0:
		set(value):
			font_scale = value
			_fit_font()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
			_fit_font()

	func _fit_font() -> void:
		if is_equal_approx(font_scale, 1.0):
			if has_theme_font_size_override(&"font_size"):
				remove_theme_font_size_override(&"font_size")
			return
		var want := roundi(UiTheme.BASE_FONT_SIZE * UiTheme.text_scale() * font_scale)
		if not has_theme_font_size_override(&"font_size") or get_theme_font_size(&"font_size") != want:
			add_theme_font_size_override(&"font_size", want)


## "Pick one" as a row of large buttons (instead of a drop-down): every choice is on screen, the chosen one is filled
## in the accent colour and carries a tick in its corner. Same small API as OptionButton: item_count, selected,
## select(), item_selected(index).
class Segmented extends HBoxContainer:
	signal item_selected(index: int)

	var item_count: int:
		get:
			return _buttons.size()
	## Index of the chosen item (-1 = none). Setting it does not emit item_selected (like OptionButton.select).
	var selected := -1:
		set(value):
			selected = clampi(value, -1, _buttons.size() - 1)
			_show_choice()

	var _buttons: Array[SegButton] = []
	var _kinds: Array[StringName] = []
	var _pic_px: Array[float] = []

	func _init() -> void:
		add_theme_constant_override(&"separation", 10)

	## Adds a choice. `font_scale` > 0 fixes the text at that multiple of the base size (a text-size preview);
	## 0 follows the player's text size like any button. Returns its button.
	func add_item(text: String, kind: StringName = &"", tip := "", font_scale := 0.0, icon_px := 40.0) -> Button:
		var b := SegButton.new()
		b.text = text
		b.tooltip_text = tip
		b.custom_minimum_size = Vector2(110, 76)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_FILL
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		if font_scale > 0.0:
			b.add_theme_font_size_override(&"font_size", roundi(UiTheme.BASE_FONT_SIZE * font_scale))
		var index := _buttons.size()
		b.pressed.connect(func() -> void:
			selected = index
			item_selected.emit(index))
		add_child(b)
		_buttons.append(b)
		_kinds.append(kind)
		_pic_px.append(icon_px)
		_show_choice()
		return b

	func select(index: int) -> void:
		selected = index

	## The button of a choice.
	func item_button(index: int) -> Button:
		return _buttons[index]

	func _show_choice() -> void:
		for i in _buttons.size():
			var on := i == selected
			var b := _buttons[i]
			b.chosen = on
			b.theme_type_variation = UiTheme.PRIMARY_BUTTON if on else &""
			if _kinds[i] != &"":
				b.icon = Pic.make(_kinds[i], _pic_px[i], &"primary_text" if on else &"text")


## One choice of a Segmented row: draws a tick in its top right corner while it is the chosen one (the fill colour is
## not the only cue).
class SegButton extends Button:
	var chosen := false:
		set(value):
			chosen = value
			queue_redraw()

	func _draw() -> void:
		if not chosen:
			return
		var pen := Pen.new()
		pen.ci = get_canvas_item()
		pen.s = 26.0 / GRID
		pen.o = Vector2(size.x - 26.0 - 8.0, 7.0)
		pen.c = UiTheme.palette().primary_text
		Pen.draw_kind(pen, &"check")


## A pictogram drawn with RenderingServer calls wherever a texture is drawn. One ink colour, round line ends.
class Pic extends Texture2D:
	var kind: StringName = &""
	var px := 28.0
	var ink: Variant = &"text"

	static func make(p_kind: StringName, p_px: float, p_ink: Variant) -> Pic:
		var p := Pic.new()
		p.kind = p_kind
		p.px = p_px
		p.ink = p_ink
		return p

	func _get_width() -> int:
		return roundi(px)

	func _get_height() -> int:
		return roundi(px)

	func _has_alpha() -> bool:
		return true

	func _draw(to_canvas_item: RID, pos: Vector2, modulate: Color, _transpose: bool) -> void:
		_paint(to_canvas_item, Rect2(pos, Vector2(px, px)), modulate)

	func _draw_rect(to_canvas_item: RID, rect: Rect2, _tile: bool, modulate: Color, _transpose: bool) -> void:
		_paint(to_canvas_item, rect, modulate)

	func _draw_rect_region(to_canvas_item: RID, rect: Rect2, _src_rect: Rect2, modulate: Color, _transpose: bool, _clip_uv: bool) -> void:
		_paint(to_canvas_item, rect, modulate)

	func _paint(ci: RID, rect: Rect2, modulate: Color) -> void:
		var colour: Color = ink if ink is Color else UiTheme.palette().get(String(ink), Color.WHITE)
		var side := minf(rect.size.x, rect.size.y)
		var pen := Pen.new()
		pen.ci = ci
		pen.s = side / GRID
		pen.o = rect.position + (rect.size - Vector2(side, side)) * 0.5
		pen.c = colour * modulate
		Pen.draw_kind(pen, kind)


## Draws lines and shapes on a canvas item in the 24-unit design grid.
class Pen:
	var ci: RID
	var o := Vector2.ZERO
	var s := 1.0
	var c := Color.WHITE
	## Line width in grid units.
	var w := 2.2

	func at(x: float, y: float) -> Vector2:
		return o + Vector2(x, y) * s

	## A line through the points [x0, y0, x1, y1, ...] with round ends and corners.
	func stroke(coords: Array, width := -1.0, closed := false) -> void:
		var pts := PackedVector2Array()
		for i in range(0, coords.size() - 1, 2):
			pts.append(at(float(coords[i]), float(coords[i + 1])))
		_stroke_points(pts, width, closed)

	func _stroke_points(pts: PackedVector2Array, width := -1.0, closed := false) -> void:
		if pts.size() < 2:
			return
		var thick := maxf(1.0, (width if width > 0.0 else w) * s)
		var caps := pts.duplicate()
		if closed:
			pts.append(pts[0])
		RenderingServer.canvas_item_add_polyline(ci, pts, PackedColorArray([c]), thick, true)
		for pt: Vector2 in caps:
			RenderingServer.canvas_item_add_circle(ci, pt, thick * 0.5, c, true)

	## A filled shape through the points [x0, y0, x1, y1, ...].
	func fill(coords: Array) -> void:
		var pts := PackedVector2Array()
		for i in range(0, coords.size() - 1, 2):
			pts.append(at(float(coords[i]), float(coords[i + 1])))
		_poly(pts)

	## Fills `pts` unless the shape is degenerate: doubled points (a full-circle pie, a tiny icon) and shapes with no
	## area are dropped, so the renderer never reports "triangulation failed".
	func _poly(pts: PackedVector2Array) -> void:
		var out := PackedVector2Array()
		for p in pts:
			if out.is_empty() or out[out.size() - 1].distance_squared_to(p) > 0.0025:
				out.append(p)
		while out.size() > 1 and out[0].distance_squared_to(out[out.size() - 1]) <= 0.0025:
			out.remove_at(out.size() - 1)
		if out.size() >= 3 and not Geometry2D.triangulate_polygon(out).is_empty():
			RenderingServer.canvas_item_add_polygon(ci, out, PackedColorArray([c]))

	func dot(x: float, y: float, r: float) -> void:
		RenderingServer.canvas_item_add_circle(ci, at(x, y), r * s, c, true)

	func box(x: float, y: float, bw: float, bh: float) -> void:
		RenderingServer.canvas_item_add_rect(ci, Rect2(at(x, y), Vector2(bw, bh) * s), c)

	## Part of a circle outline, from angle a0 to a1 (radians, clockwise on screen, 0 = right).
	func arc(x: float, y: float, r: float, a0: float, a1: float, width := -1.0) -> void:
		var steps := maxi(6, int(absf(a1 - a0) * 6.0))
		var pts := PackedVector2Array()
		for i in steps + 1:
			var a := lerpf(a0, a1, float(i) / float(steps))
			pts.append(at(x + cos(a) * r, y + sin(a) * r))
		var whole := absf(absf(a1 - a0) - TAU) < 0.001
		var thick := maxf(1.0, (width if width > 0.0 else w) * s)
		RenderingServer.canvas_item_add_polyline(ci, pts, PackedColorArray([c]), thick, true)
		if not whole:
			RenderingServer.canvas_item_add_circle(ci, pts[0], thick * 0.5, c, true)
			RenderingServer.canvas_item_add_circle(ci, pts[pts.size() - 1], thick * 0.5, c, true)

	func ring(x: float, y: float, r: float, width := -1.0) -> void:
		arc(x, y, r, 0.0, TAU, width)

	## A filled slice of a circle from angle a0 to a1.
	func pie(x: float, y: float, r: float, a0: float, a1: float) -> void:
		var steps := maxi(6, int(absf(a1 - a0) * 6.0))
		var pts := PackedVector2Array([at(x, y)])
		for i in steps + 1:
			var a := lerpf(a0, a1, float(i) / float(steps))
			pts.append(at(x + cos(a) * r, y + sin(a) * r))
		_poly(pts)

	static func draw_kind(p: Pen, kind: StringName) -> void:
		match kind:
			&"play":
				p.fill([8.0, 5.0, 19.5, 12.0, 8.0, 19.0])
				p.stroke([8.0, 5.0, 19.5, 12.0, 8.0, 19.0], 2.4, true)
			&"plus":
				p.stroke([12.0, 5.0, 12.0, 19.0], 3.2)
				p.stroke([5.0, 12.0, 19.0, 12.0], 3.2)
			&"friends":
				p.dot(8.5, 8.0, 3.4)
				p.pie(8.5, 20.5, 6.4, PI, TAU)
				p.dot(17.0, 9.5, 2.7)
				p.pie(17.5, 20.5, 4.6, PI, TAU)
			&"crew":
				p.ring(12.0, 10.5, 7.2, 2.4)
				p.fill([7.5, 8.2, 16.5, 8.2, 16.5, 12.6, 7.5, 12.6])
				p.stroke([7.5, 8.2, 16.5, 8.2, 16.5, 12.6, 7.5, 12.6], 1.4, true)
				p.stroke([6.0, 21.0, 18.0, 21.0], 2.8)
			&"host":
				p.arc(12.0, 21.5, 6.6, PI, TAU)
				p.stroke([3.5, 21.5, 20.5, 21.5])
				p.stroke([12.0, 14.9, 12.0, 8.0], 1.8)
				p.dot(12.0, 6.6, 1.7)
				for r: float in [3.8, 6.6]:
					p.arc(12.0, 6.6, r, -PI * 0.26, PI * 0.26, 1.7)
					p.arc(12.0, 6.6, r, PI * 0.74, PI * 1.26, 1.7)
			&"join":
				p.stroke([13.0, 4.0, 20.0, 4.0, 20.0, 20.0, 13.0, 20.0])
				p.stroke([3.0, 12.0, 14.0, 12.0], 2.6)
				p.stroke([10.0, 7.8, 14.2, 12.0, 10.0, 16.2], 2.6)
			&"exit":
				p.stroke([11.0, 4.0, 4.0, 4.0, 4.0, 20.0, 11.0, 20.0])
				p.stroke([9.5, 12.0, 20.5, 12.0], 2.6)
				p.stroke([16.5, 7.8, 20.7, 12.0, 16.5, 16.2], 2.6)
			&"gear":
				p.ring(12.0, 12.0, 6.2, 2.8)
				p.dot(12.0, 12.0, 2.0)
				for i in 8:
					var a := TAU * float(i) / 8.0
					p.stroke([12.0 + cos(a) * 7.6, 12.0 + sin(a) * 7.6, 12.0 + cos(a) * 9.6, 12.0 + sin(a) * 9.6], 3.2)
			&"star":
				var star: Array = []
				for i in 10:
					var a := -PI * 0.5 + TAU * float(i) / 10.0
					var r := 9.6 if i % 2 == 0 else 4.2
					star.append(12.0 + cos(a) * r)
					star.append(12.8 + sin(a) * r)
				p.fill(star)
				p.stroke(star, 1.6, true)
			&"book":
				p.stroke([12.0, 6.5, 12.0, 20.0], 1.8)
				p.stroke([12.0, 6.5, 8.0, 4.8, 3.0, 5.6, 3.0, 18.8, 8.0, 18.0, 12.0, 20.0])
				p.stroke([12.0, 6.5, 16.0, 4.8, 21.0, 5.6, 21.0, 18.8, 16.0, 18.0, 12.0, 20.0])
			&"home":
				p.stroke([3.0, 12.0, 12.0, 4.0, 21.0, 12.0], 2.4)
				p.stroke([6.0, 11.5, 6.0, 20.0, 18.0, 20.0, 18.0, 11.5])
				p.fill([10.5, 14.5, 13.5, 14.5, 13.5, 20.0, 10.5, 20.0])
			&"save":
				p.stroke([12.0, 3.5, 12.0, 14.0], 2.6)
				p.stroke([7.5, 9.8, 12.0, 14.4, 16.5, 9.8], 2.6)
				p.stroke([4.0, 15.5, 4.0, 20.0, 20.0, 20.0, 20.0, 15.5], 2.4)
			&"dome":
				p.arc(12.0, 18.5, 8.6, PI, TAU)
				p.stroke([2.5, 18.5, 21.5, 18.5])
				p.dot(7.8, 14.6, 1.3)
				p.dot(12.0, 13.2, 1.3)
				p.dot(16.2, 14.6, 1.3)
				p.stroke([4.5, 22.0, 19.5, 22.0], 1.4)
			&"back":
				p.stroke([5.0, 12.0, 19.0, 12.0], 2.6)
				p.stroke([10.0, 7.0, 5.0, 12.0, 10.0, 17.0], 2.6)
			&"up":
				p.stroke([12.0, 19.0, 12.0, 5.5], 2.6)
				p.stroke([6.5, 11.0, 12.0, 5.5, 17.5, 11.0], 2.6)
			&"down":
				p.stroke([12.0, 5.0, 12.0, 18.5], 2.6)
				p.stroke([6.5, 13.0, 12.0, 18.5, 17.5, 13.0], 2.6)
			&"flip":
				p.stroke([7.5, 19.0, 7.5, 5.5], 2.4)
				p.stroke([3.5, 9.5, 7.5, 5.5, 11.5, 9.5], 2.4)
				p.stroke([16.5, 5.0, 16.5, 18.5], 2.4)
				p.stroke([12.5, 14.5, 16.5, 18.5, 20.5, 14.5], 2.4)
			&"zoom":
				p.ring(10.5, 10.5, 6.4, 2.2)
				p.stroke([15.4, 15.4, 20.5, 20.5], 3.0)
				p.stroke([7.8, 10.5, 13.2, 10.5], 1.8)
				p.stroke([10.5, 7.8, 10.5, 13.2], 1.8)
			&"letter":
				p.stroke([5.5, 19.5, 12.0, 4.5, 18.5, 19.5], 2.6)
				p.stroke([8.3, 14.2, 15.7, 14.2], 2.4)
			&"check":
				p.stroke([5.0, 12.5, 10.0, 17.5, 19.5, 6.5], 3.2)
			&"lock":
				p.fill([6.0, 11.0, 18.0, 11.0, 18.0, 20.5, 6.0, 20.5])
				p.stroke([6.0, 11.0, 18.0, 11.0, 18.0, 20.5, 6.0, 20.5], 1.6, true)
				p.arc(12.0, 9.5, 4.0, PI, TAU, 2.2)
				p.stroke([8.0, 9.5, 8.0, 11.0], 2.2)
				p.stroke([16.0, 9.5, 16.0, 11.0], 2.2)
			&"reset":
				p.arc(12.0, 12.5, 7.2, -PI * 0.2, PI * 1.35, 2.4)
				p.fill([13.0, 2.2, 19.6, 6.4, 12.6, 9.6])
			&"pencil":
				p.stroke([8.0, 16.0, 17.5, 6.5], 3.6)
				p.fill([4.0, 20.0, 5.2, 15.2, 8.8, 18.8])
			&"monitor":
				p.stroke([3.0, 4.5, 21.0, 4.5, 21.0, 15.5, 3.0, 15.5], 2.2, true)
				p.stroke([12.0, 15.5, 12.0, 19.5], 2.2)
				p.stroke([7.5, 20.0, 16.5, 20.0], 2.4)
			&"keys":
				p.stroke([2.5, 6.5, 21.5, 6.5, 21.5, 17.5, 2.5, 17.5], 2.0, true)
				for x: float in [6.2, 10.1, 13.9, 17.8]:
					p.dot(x, 10.4, 1.15)
				p.stroke([8.0, 14.2, 16.0, 14.2], 2.0)
			&"image":
				p.stroke([3.0, 4.5, 21.0, 4.5, 21.0, 19.5, 3.0, 19.5], 2.0, true)
				p.stroke([5.5, 16.5, 10.0, 11.0, 13.0, 14.2, 15.8, 10.8, 18.8, 16.0], 2.0)
				p.dot(8.2, 8.6, 1.5)
			&"sound", &"mute":
				p.fill([3.0, 9.5, 7.0, 9.5, 12.0, 5.0, 12.0, 19.0, 7.0, 14.5, 3.0, 14.5])
				p.stroke([3.0, 9.5, 7.0, 9.5, 12.0, 5.0, 12.0, 19.0, 7.0, 14.5, 3.0, 14.5], 1.4, true)
				if kind == &"sound":
					p.arc(12.5, 12.0, 4.0, -PI * 0.3, PI * 0.3, 2.0)
					p.arc(12.5, 12.0, 7.6, -PI * 0.3, PI * 0.3, 2.0)
				else:
					p.stroke([15.5, 9.0, 21.0, 15.0], 2.4)
					p.stroke([21.0, 9.0, 15.5, 15.0], 2.4)
			&"mic":
				p.stroke([12.0, 5.5, 12.0, 11.0], 5.4)
				p.arc(12.0, 11.0, 6.0, PI * 0.08, PI * 0.92, 2.0)
				p.stroke([12.0, 17.0, 12.0, 20.0], 2.0)
				p.stroke([8.5, 20.5, 15.5, 20.5], 2.0)
			&"mouse":
				p.arc(12.0, 9.5, 5.6, PI, TAU, 2.0)
				p.arc(12.0, 14.5, 5.6, 0.0, PI, 2.0)
				p.stroke([6.4, 9.5, 6.4, 14.5], 2.0)
				p.stroke([17.6, 9.5, 17.6, 14.5], 2.0)
				p.stroke([12.0, 7.4, 12.0, 10.6], 2.2)
			&"eye":
				p.stroke([2.5, 12.0, 6.5, 8.0, 12.0, 6.2, 17.5, 8.0, 21.5, 12.0, 17.5, 16.0, 12.0, 17.8, 6.5, 16.0], 2.0, true)
				p.dot(12.0, 12.0, 3.1)
			&"fast":
				p.stroke([5.0, 6.0, 11.0, 12.0, 5.0, 18.0], 3.0)
				p.stroke([13.0, 6.0, 19.0, 12.0, 13.0, 18.0], 3.0)
			&"contrast":
				p.ring(12.0, 12.0, 8.6, 2.2)
				p.pie(12.0, 12.0, 8.6, -PI * 0.5, PI * 0.5)
			&"bubble":
				p.stroke([4.0, 4.5, 20.0, 4.5, 20.0, 15.5, 11.5, 15.5, 7.0, 20.0, 7.0, 15.5, 4.0, 15.5], 2.0, true)
				p.stroke([7.5, 8.6, 16.5, 8.6], 1.7)
				p.stroke([7.5, 11.8, 13.5, 11.8], 1.7)
			&"motion":
				p.dot(17.0, 12.0, 3.8)
				p.stroke([3.5, 7.5, 10.5, 7.5], 2.0)
				p.stroke([2.0, 12.0, 10.5, 12.0], 2.0)
				p.stroke([3.5, 16.5, 10.5, 16.5], 2.0)
			&"flash":
				p.dot(12.0, 12.0, 3.4)
				for i in 8:
					var a := TAU * float(i) / 8.0
					p.stroke([12.0 + cos(a) * 6.4, 12.0 + sin(a) * 6.4, 12.0 + cos(a) * 9.6, 12.0 + sin(a) * 9.6], 2.0)
			&"clock":
				p.ring(12.0, 12.0, 8.6, 2.2)
				p.stroke([12.0, 7.0, 12.0, 12.0, 15.6, 14.2], 2.2)
			&"bolt":
				p.fill([13.8, 2.5, 5.5, 13.4, 11.0, 13.4, 9.6, 21.5, 18.5, 9.6, 12.6, 9.6])
			&"cross":
				p.box(9.2, 3.5, 5.6, 17.0)
				p.box(3.5, 9.2, 17.0, 5.6)
			&"sprout":
				p.stroke([12.0, 21.0, 12.0, 11.5], 2.4)
				p.fill([12.0, 14.0, 5.0, 13.4, 3.4, 6.6, 9.6, 7.4])
				p.fill([12.0, 11.6, 19.0, 10.6, 20.6, 3.6, 14.4, 4.6])
			&"pick":
				p.stroke([5.5, 20.5, 16.5, 7.5], 2.8)
				p.stroke([7.5, 5.5, 12.5, 4.0, 17.5, 6.0, 20.5, 11.5], 3.0)
			&"bars1", &"bars2", &"bars3", &"bars4":
				var level := int(String(kind).right(1))
				var full := p.c
				for i in 4:
					p.c = full if i < level else Color(full, full.a * 0.28)
					var h := 5.0 + 4.0 * float(i)
					p.box(3.0 + 5.0 * float(i), 20.0 - h, 3.4, h)
				p.c = full
			_:
				pass
