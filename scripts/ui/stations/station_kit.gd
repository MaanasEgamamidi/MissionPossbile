extends RefCounted
## Building blocks of the station surfaces (the panel E opens at a station) and the cassette player: pictograms drawn
## in code, big action buttons with a picture and one to three words, small picture-only buttons, and chips.
## No class_name on purpose: load it with  const StationKit = preload("res://scripts/ui/stations/station_kit.gd").
##
## Why: a nine-year-old should see what a station is and what its button does before reading anything.
## The drawing pen and the menu pictograms come from menu_kit.gd; this file adds the ones the stations need.
## Colours come from UiTheme.palette() when a pictogram is drawn, so they follow high contrast without a rebuild.

const MenuKit = preload("res://scripts/ui/menu_kit.gd")

## Station kind -> pictogram for the panel header.
const KIND_PICS := {
	"power": &"bolt", "computer": &"monitor", "comms": &"host", "food": &"sprout", "lifesupport": &"air",
	"heal": &"cross", "board": &"chip", "survivor": &"heart", "suits": &"crew", "solar": &"flash",
	"bed": &"sprout", "gym": &"dumbbell", "weather": &"cloud", "workbench": &"wrench", "garage": &"rover",
	"lab": &"flask", "ore_deposit": &"pick", "record": &"book", "repair_task": &"wrench", "rover_charger": &"battery",
	"salvage": &"crate", "sample_site": &"pick", "scout_bay": &"rover", "drone_pad": &"drone",
	"upgrade_console": &"up", "cassette_anchor": &"tape", "cassette_player_anchor": &"tape",
}

## Symbol of a reading (the glyph the panels pass) -> pictogram. A glyph that is not listed stays a glyph.
const GLYPH_PICS := {
	"⚡": &"bolt", "❀": &"sprout", "✿": &"sprout", "≈": &"water", "≋": &"waste", "⇣": &"water", "O₂": &"air",
	"CO₂": &"air", "⧗": &"clock", "☀": &"flash", "⚙": &"gear", "▮": &"battery", "♥": &"heart", "◆": &"crew",
	"⛑": &"tank", "✚": &"cross", "♻": &"crate", "⛏": &"pick", "✧": &"sparkle", "↑": &"up", "↓": &"bowl",
}


## The pictogram of a station kind, or &"" when it has none.
static func kind_pic(kind: String) -> StringName:
	return KIND_PICS.get(kind, &"")


## The pictogram for a reading's symbol, or &"" when the glyph has none.
static func glyph_pic(symbol: String) -> StringName:
	return GLYPH_PICS.get(symbol, &"")


## A pictogram as a texture, for Button.icon and TextureRect. `ink` is a UiTheme.palette() role or a Color.
static func pic(kind: StringName, px := 28.0, ink: Variant = &"text") -> Texture2D:
	var p := Pic.new()
	p.kind = kind
	p.px = px
	p.ink = ink
	return p


## Gives button `b` the pictogram `kind` as its icon. The ink follows the button: dark on a filled (primary) button,
## light on a plain one, and the "greyed out" colour while the button is disabled, so it never vanishes into the fill.
static func button_pic(b: BaseButton, kind: StringName, px := 28.0) -> void:
	var p := Pic.new()
	p.kind = kind
	p.px = px
	p.host = weakref(b)
	b.set(&"icon", p)


## A pictogram on its own (not focusable, ignores the mouse).
static func picture(kind: StringName, px := 28.0, ink: Variant = &"text") -> TextureRect:
	var t := TextureRect.new()
	t.texture = pic(kind, px, ink)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


## A big action button: a picture and one to three words. `primary` fills it in the accent colour (the one obvious
## thing to do here); a second action is drawn plain.
static func action(text: String, kind: StringName, primary := true) -> Button:
	var b: Button = MenuKit.ScaledButton.new()
	b.set(&"font_scale", 1.15)
	b.text = text
	b.custom_minimum_size = Vector2(0, 60)
	b.add_theme_constant_override(&"h_separation", 12)
	style_action(b, kind, primary)
	return b


## Gives an action button its picture and its look (also used when a button changes from primary to plain).
static func style_action(b: Button, kind: StringName, primary := true) -> void:
	b.theme_type_variation = UiTheme.PRIMARY_BUTTON if primary else &""
	if kind != &"":
		button_pic(b, kind, 32.0)


## A small square button that is only a picture; its words are the tooltip. Focusable like any button.
static func icon_button(kind: StringName, tip: String, px := 26.0) -> Button:
	var b := Button.new()
	button_pic(b, kind, px)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(46, 46)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## A rounded pill with an optional pictogram and a short label (the child "Text").
static func chip(kind: StringName, text: String) -> PanelContainer:
	var c := PanelContainer.new()
	c.theme_type_variation = UiTheme.CHIP
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	c.add_child(row)
	if kind != &"":
		row.add_child(picture(kind, 20.0, &"muted"))
	var l := Label.new()
	l.name = "Text"
	l.text = text
	row.add_child(l)
	return c


## The words on a key cap for a key name ("Escape" is too long for a cap).
static func cap_text(key_name: String) -> String:
	match key_name:
		"Escape": return "Esc"
		"Enter", "Return": return "Enter"
		"Space": return "Space"
	return key_name


## A pictogram drawn wherever a texture is drawn. One ink colour, round line ends.
class Pic extends Texture2D:
	var kind: StringName = &""
	var px := 28.0
	var ink: Variant = &"text"
	## The button this pictogram is the icon of (see button_pic); null for a pictogram on its own.
	var host: WeakRef

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
		var button := host.get_ref() as BaseButton if host != null else null
		if button != null:
			var p := UiTheme.palette()
			if button.disabled:
				colour = p.text_disabled
				modulate = Color.WHITE          # the theme's own dimming on top would make it too faint
			else:
				colour = p.primary_text if button.theme_type_variation == UiTheme.PRIMARY_BUTTON else p.text
		var side := minf(rect.size.x, rect.size.y)
		var pen := MenuKit.Pen.new()
		pen.ci = ci
		pen.s = side / MenuKit.GRID
		pen.o = rect.position + (rect.size - Vector2(side, side)) * 0.5
		pen.c = colour * modulate
		draw_kind(pen, kind)

	## The station pictograms on the 24-unit grid; any other kind is one of menu_kit.gd's.
	static func draw_kind(p: Variant, k: StringName) -> void:
		match k:
			&"close":
				p.stroke([6.5, 6.5, 17.5, 17.5], 3.2)
				p.stroke([17.5, 6.5, 6.5, 17.5], 3.2)
			&"help":
				p.arc(12.0, 9.0, 4.3, PI, TAU + PI * 0.42, 2.8)
				p.stroke([13.1, 13.2, 12.0, 15.6], 2.8)
				p.dot(12.0, 19.6, 1.7)
			&"water", &"waste":
				var drop := [12.0, 3.0, 16.4, 9.8, 17.8, 13.6, 17.2, 17.0, 15.0, 19.6, 12.0, 20.6, 9.0, 19.6, 6.8, 17.0, 6.2, 13.6, 7.6, 9.8]
				if k == &"water":
					p.fill(drop)
				p.stroke(drop, 2.0, true)
				if k == &"waste":
					p.stroke([9.6, 14.2, 14.4, 14.2], 1.8)
			&"air":
				p.ring(9.2, 13.4, 5.6, 2.4)
				p.ring(17.6, 7.4, 3.0, 2.0)
				p.dot(18.6, 17.4, 1.5)
			&"battery":
				p.stroke([3.0, 7.5, 19.0, 7.5, 19.0, 16.5, 3.0, 16.5], 2.2, true)
				p.box(19.8, 10.0, 2.0, 4.0)
				p.box(5.2, 9.7, 8.4, 4.6)
			&"tank":
				p.stroke([8.0, 8.5, 8.0, 21.0, 16.0, 21.0, 16.0, 8.5], 2.2)
				p.arc(12.0, 8.5, 4.0, PI, TAU, 2.2)
				p.stroke([12.0, 4.5, 12.0, 2.8], 2.0)
				p.stroke([9.4, 2.8, 14.6, 2.8], 2.0)
				p.box(9.8, 13.0, 4.4, 6.4)
			&"heart":
				p.fill([12.0, 20.5, 4.2, 12.5, 3.4, 9.0, 4.8, 6.0, 7.6, 4.8, 10.4, 5.6, 12.0, 8.0, 13.6, 5.6, 16.4, 4.8, 19.2, 6.0, 20.6, 9.0, 19.8, 12.5])
			&"wrench":
				p.stroke([6.5, 17.5, 14.6, 9.4], 3.6)
				p.arc(17.0, 7.0, 3.8, PI * 0.25, PI * 1.5, 2.8)
				p.dot(5.8, 18.2, 1.2)
			&"sparkle":
				p.fill([12.0, 2.5, 13.9, 10.1, 21.5, 12.0, 13.9, 13.9, 12.0, 21.5, 10.1, 13.9, 2.5, 12.0, 10.1, 10.1])
				p.dot(19.2, 5.0, 1.4)
			&"dumbbell":
				p.stroke([7.0, 12.0, 17.0, 12.0], 2.8)
				p.box(3.4, 7.0, 3.4, 10.0)
				p.box(17.2, 7.0, 3.4, 10.0)
				p.box(1.4, 9.6, 1.8, 4.8)
				p.box(20.8, 9.6, 1.8, 4.8)
			&"rover":
				p.box(3.0, 9.5, 12.5, 5.5)
				p.stroke([15.5, 10.5, 19.0, 10.5, 21.0, 14.0, 15.5, 14.0], 2.0, true)
				p.dot(7.0, 17.8, 2.7)
				p.dot(17.0, 17.8, 2.7)
				p.stroke([6.0, 9.5, 6.0, 5.0], 1.8)
				p.dot(6.0, 4.4, 1.3)
			&"drone":
				p.stroke([6.0, 7.0, 18.0, 17.0], 2.0)
				p.stroke([18.0, 7.0, 6.0, 17.0], 2.0)
				for at: Array in [[6.0, 7.0], [18.0, 7.0], [6.0, 17.0], [18.0, 17.0]]:
					p.ring(float(at[0]), float(at[1]), 2.8, 1.8)
				p.dot(12.0, 12.0, 2.6)
			&"flask":
				p.stroke([10.0, 3.5, 10.0, 9.5, 4.6, 19.0, 5.8, 20.8, 18.2, 20.8, 19.4, 19.0, 14.0, 9.5, 14.0, 3.5], 2.2)
				p.stroke([8.4, 3.5, 15.6, 3.5], 2.2)
				p.fill([7.4, 15.4, 16.6, 15.4, 18.0, 19.2, 6.0, 19.2])
			&"crate":
				p.stroke([4.0, 8.0, 12.0, 4.0, 20.0, 8.0, 20.0, 17.0, 12.0, 21.0, 4.0, 17.0], 2.0, true)
				p.stroke([4.0, 8.0, 12.0, 12.0, 20.0, 8.0], 2.0)
				p.stroke([12.0, 12.0, 12.0, 21.0], 2.0)
			&"tape":
				p.stroke([2.5, 6.0, 21.5, 6.0, 21.5, 18.0, 2.5, 18.0], 2.2, true)
				p.ring(8.0, 11.2, 2.3, 1.8)
				p.ring(16.0, 11.2, 2.3, 1.8)
				p.stroke([6.4, 18.0, 8.0, 15.2, 16.0, 15.2, 17.6, 18.0], 1.8)
			&"next":
				p.stroke([5.0, 12.0, 19.0, 12.0], 2.6)
				p.stroke([14.0, 7.0, 19.0, 12.0, 14.0, 17.0], 2.6)
			&"list":
				for y: float in [6.5, 12.0, 17.5]:
					p.dot(4.8, y, 1.5)
					p.stroke([9.0, y, 20.0, y], 2.2)
			&"cloud":
				p.arc(8.0, 14.0, 3.6, PI * 0.5, PI * 1.5, 2.2)
				p.arc(12.2, 10.6, 4.6, PI * 1.05, PI * 1.95, 2.2)
				p.arc(16.4, 14.0, 3.6, -PI * 0.5, PI * 0.5, 2.2)
				p.stroke([8.0, 17.6, 16.4, 17.6], 2.2)
			&"mail":
				p.stroke([3.0, 6.0, 21.0, 6.0, 21.0, 18.0, 3.0, 18.0], 2.0, true)
				p.stroke([3.4, 6.6, 12.0, 13.0, 20.6, 6.6], 2.0)
			&"chip":
				p.stroke([7.0, 7.0, 17.0, 7.0, 17.0, 17.0, 7.0, 17.0], 2.2, true)
				for v: float in [9.5, 12.0, 14.5]:
					p.stroke([v, 3.6, v, 7.0], 1.6)
					p.stroke([v, 17.0, v, 20.4], 1.6)
					p.stroke([3.6, v, 7.0, v], 1.6)
					p.stroke([17.0, v, 20.4, v], 1.6)
			&"bowl":
				p.pie(12.0, 12.5, 8.2, 0.0, PI)
				p.stroke([3.0, 12.5, 21.0, 12.5], 2.0)
				p.stroke([9.0, 9.0, 9.0, 6.0], 1.6)
				p.stroke([12.0, 9.4, 12.0, 4.6], 1.6)
				p.stroke([15.0, 9.0, 15.0, 6.0], 1.6)
			&"person":
				p.dot(12.0, 7.2, 3.6)
				p.pie(12.0, 21.0, 7.2, PI, TAU)
			&"chart":
				p.box(4.0, 13.0, 3.6, 7.0)
				p.box(10.2, 8.0, 3.6, 12.0)
				p.box(16.4, 4.0, 3.6, 16.0)
			_:
				MenuKit.Pen.draw_kind(p, k)
