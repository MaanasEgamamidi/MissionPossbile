class_name MenuTitleEmblem
extends Control
## Native title text with the reference's interrupted circular orbit, in the game's title font and accent colour.
var configuring := false
var text_scale := 1.0
var _title: Label

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = Label.new()
	_title.name = "Title"
	_title.text = "MISSION POSSIBLE"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The game's own heavy title font (the theme's DisplayLabel), with a little extra letter spacing.
	var font := FontVariation.new()
	font.base_font = UiTheme.get_theme().get_font(&"font", UiTheme.DISPLAY)
	font.spacing_glyph = 8
	_title.add_theme_font_override(&"font", font)
	_title.add_theme_color_override(&"font_color", UiTheme.palette().text)
	_title.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.55))
	_title.add_theme_constant_override(&"shadow_offset_y", 3)
	add_child(_title)

func _draw() -> void:
	var radius := minf(size.y * (0.485 if configuring else 0.46), size.x * 0.31)
	var center := size * 0.5
	var fs := minf(size.x / 13.0, size.y * (0.15 if configuring else 0.13)) * text_scale
	_title.add_theme_font_size_override(&"font_size", roundi(fs))
	_title.position = Vector2(0, center.y - fs * 0.8)
	_title.size = Vector2(size.x, fs * 1.6)
	var gap := 0.19
	var width := maxf(3, radius * 0.045)
	var ring: Color = UiTheme.palette().accent
	draw_arc(center, radius, PI + gap, TAU - gap, 160, ring, width, true)
	draw_arc(center, radius, gap, PI - gap, 160, ring, width, true)
