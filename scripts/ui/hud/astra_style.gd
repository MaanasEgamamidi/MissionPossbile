class_name AstraStyle
extends RefCounted
## The look of the mission-control HUD (vitals bar, goals, map, pop-ups, dock, power and build drawers): dark navy
## glass cards with a faint blue outline, round corners, an orange accent and one colour per supply, always paired with
## a symbol and a word. Design study of ASTRA, the Junior Astronaut Mission Trainer (MIT licence, credited in
## data/credits.json); rebuilt here with native Godot controls. Sizes follow the player's text size (UiTheme).

const GLASS := Color(0.07, 0.10, 0.23, 0.88)
const GLASS_SOLID := Color(0.067, 0.102, 0.227, 0.97)
const LINE := Color(0.59, 0.69, 1.0, 0.16)
const LINE_STRONG := Color(0.67, 0.76, 1.0, 0.3)
const TEXT := Color(0.953, 0.965, 1.0)
const TEXT_2 := Color(0.761, 0.796, 0.925)
const TEXT_3 := Color(0.545, 0.588, 0.753)
const ACCENT := Color(1.0, 0.541, 0.239)
const ACCENT_INK := Color(0.165, 0.067, 0.0)
const GOOD := Color(0.243, 0.89, 0.604)
const WARN := Color(1.0, 0.761, 0.239)
const DANGER := Color(1.0, 0.329, 0.439)
const C_POWER := Color(1.0, 0.788, 0.29)
const C_O2 := Color(0.369, 0.878, 1.0)
const C_WATER := Color(0.31, 0.584, 1.0)
const C_FOOD := Color(0.388, 0.831, 0.443)
const C_PARTS := Color(0.906, 0.647, 0.396)
const C_SCIENCE := Color(0.494, 0.941, 0.784)
const C_ORE := Color(0.78, 0.55, 0.95)
const RADIUS := 16
const RADIUS_SM := 10

static var _symbols: Font


## Font size in screen units for a base size, following the player's text size.
static func fs(base: float) -> int:
	return roundi(base * UiTheme.text_scale())


## A monochrome symbol font (⚡ ✿ ⛭ draw as colour emoji in the default fallback and ignore the text colour).
static func symbol_font() -> Font:
	if _symbols == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI Symbol", "Noto Sans Symbols 2", "Noto Sans Symbols", "DejaVu Sans"])
		f.allow_system_fallback = false
		f.fallbacks = [ThemeDB.fallback_font]
		_symbols = f
	return _symbols


static func glass(radius := RADIUS, pad_h := 14, pad_v := 10, solid := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = GLASS_SOLID if solid or UiTheme.is_high_contrast() else GLASS
	s.border_color = LINE_STRONG if UiTheme.is_high_contrast() else LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 6)
	s.anti_aliasing = true
	return s


## A small filled pill (status chips, key caps, cost tags).
static func pill(bg: Color, radius := 999, pad_h := 8, pad_v := 3, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(1)
	s.anti_aliasing = true
	return s


static func panel(style: StyleBox, node_name := "") -> PanelContainer:
	var p := PanelContainer.new()
	if node_name != "":
		p.name = node_name
	p.add_theme_stylebox_override(&"panel", style)
	return p


static func label(text: String, size := 15.0, color := TEXT, node_name := "", symbol := false) -> Label:
	var l := Label.new()
	if node_name != "":
		l.name = node_name
	l.text = text
	l.add_theme_font_size_override(&"font_size", fs(size))
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override(&"outline_size", 0)
	if symbol:
		l.add_theme_font_override(&"font", symbol_font())
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func set_size(l: Label, size: float) -> void:
	l.add_theme_font_size_override(&"font_size", fs(size))


static func set_color(l: Label, c: Color) -> void:
	l.add_theme_color_override(&"font_color", c)


## A key cap like "P" in a rounded box, for the dock and the vitals buttons.
static func keycap(key_text: String, size := 11.0) -> PanelContainer:
	var p := panel(pill(Color(1, 1, 1, 0.08), 6, 5, 1, LINE_STRONG), "Key")
	p.add_child(label(key_text, size, TEXT_2, "KeyText"))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## A flat button in the HUD look: text and colour of its own, glass when hovered.
static func flat_button(text: String, size := 15.0, color := TEXT_2) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override(&"font_size", fs(size))
	b.add_theme_color_override(&"font_color", color)
	b.add_theme_color_override(&"font_hover_color", TEXT)
	b.add_theme_font_override(&"font", symbol_font())
	var hover := pill(Color(1, 1, 1, 0.08), RADIUS_SM, 6, 2)
	b.add_theme_stylebox_override(&"hover", hover)
	b.add_theme_stylebox_override(&"pressed", hover)
	var none := StyleBoxEmpty.new()
	none.content_margin_left = 6
	none.content_margin_right = 6
	b.add_theme_stylebox_override(&"normal", none)
	b.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	return b


## The primary orange button of the drawers ("Build").
static func primary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override(&"font_size", fs(15))
	b.add_theme_color_override(&"font_color", ACCENT_INK)
	b.add_theme_color_override(&"font_hover_color", ACCENT_INK)
	b.add_theme_color_override(&"font_pressed_color", ACCENT_INK)
	b.add_theme_color_override(&"font_disabled_color", Color(TEXT_3, 0.8))
	b.add_theme_stylebox_override(&"normal", pill(ACCENT, RADIUS_SM, 14, 6))
	b.add_theme_stylebox_override(&"hover", pill(ACCENT.lightened(0.15), RADIUS_SM, 14, 6))
	b.add_theme_stylebox_override(&"pressed", pill(ACCENT.darkened(0.1), RADIUS_SM, 14, 6))
	b.add_theme_stylebox_override(&"disabled", pill(Color(1, 1, 1, 0.06), RADIUS_SM, 14, 6, LINE))
	b.add_theme_stylebox_override(&"focus", pill(Color(0, 0, 0, 0), RADIUS_SM, 14, 6, TEXT))
	return b


## A thin horizontal meter (fill share 0..1) drawn in `color` on a faint track.
class Meter extends Control:
	var share := 0.0:
		set(v):
			share = clampf(v, 0.0, 1.0)
			queue_redraw()
	var color := Color.WHITE:
		set(v):
			color = v
			queue_redraw()
	var thickness := 4.0

	func _init(p_color := Color.WHITE, p_thickness := 4.0) -> void:
		color = p_color
		thickness = p_thickness
		custom_minimum_size = Vector2(40, p_thickness)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(0, (size.y - thickness) * 0.5), Vector2(size.x, thickness))
		draw_rect(r, Color(1, 1, 1, 0.1))
		if share > 0.0:
			draw_rect(Rect2(r.position, Vector2(r.size.x * share, r.size.y)), color)
