class_name UiTheme
extends RefCounted
## The one shared Theme, built in code: a restrained mission-console look. Charcoal surfaces, warm-white text,
## thin borders and a small rust accent keep the controls readable over the Mars landscape. Panels refer to the type
## variation names below (Control.theme_type_variation) instead of styling themselves. Colours, fonts, font sizes and
## the small drawn icons (switches, tick boxes, slider handles) are set here and nowhere else.

const PANEL := &"GamePanel"            # PanelContainer: in-game panel over the 3D view
const HUD_PANEL := &"HudPanel"         # PanelContainer: small translucent HUD box
const CARD := &"CardPanel"             # PanelContainer: crew card, upgrade card, station reading
const TITLE := &"TitleLabel"           # Label: panel title
const HEADING := &"HeadingLabel"       # Label: section heading
const MUTED := &"MutedLabel"           # Label: secondary text
const READING := &"ReadingLabel"       # Label: a big number on a gauge
const GOOD := &"GoodLabel"             # Label: status that is fine (paired with a symbol)
const WARN := &"WarnLabel"             # Label: status that needs attention soon
const URGENT := &"UrgentLabel"         # Label: status that needs action now
const PRIMARY_BUTTON := &"PrimaryButton"
const DANGER_BUTTON := &"DangerButton"
## PanelContainer: dark box behind subtitles, readable on any background.
const SUBTITLE := &"SubtitlePanel"
## Panel: dimmed full-screen backdrop behind full-screen menus.
const BACKDROP := &"Backdrop"
## Panel: lighter dim behind an in-game panel, so the HUD and the world do not fight with the panel's text.
const BACKDROP_LIGHT := &"BackdropLight"
## MarginContainer: the margin around panels on the screen.
const SCREEN_MARGIN := &"ScreenMargin"
## Label: the game's name on the title screen.
const DISPLAY := &"DisplayLabel"
## PanelContainer: a key cap around a key name ("E", "Esc").
const KEYCAP := &"KeyCapPanel"
## PanelContainer: a rounded pill around a short status ("Colony OK ✓", "This room has power").
const CHIP := &"ChipPanel"
## PanelContainer: a HUD message, with an accent bar on its left edge.
const TOAST := &"ToastPanel"
## ProgressBar fills by meaning: fine, attention soon, act now, and a cool one for air and suit tanks.
const BAR_GOOD := &"GoodBar"
const BAR_WARN := &"WarnBar"
const BAR_URGENT := &"UrgentBar"
const BAR_COOL := &"CoolBar"

## Base font size in pixels at text scale 1.0 and UI scale 1.0.
const BASE_FONT_SIZE := 18

## Every label variation (base Label first). Tests check the contrast of each against every panel style.
const LABEL_VARIATIONS: Array[StringName] = [&"Label", TITLE, HEADING, MUTED, READING, GOOD, WARN, URGENT, DISPLAY]
## Every panel style text is drawn on.
const PANEL_VARIATIONS: Array[StringName] = [&"PanelContainer", PANEL, HUD_PANEL, CARD, SUBTITLE, KEYCAP, CHIP, TOAST]
## Focusable control types and the stylebox each one draws when it has keyboard focus.
const FOCUS_STYLES: Dictionary = {
	&"Button": &"focus", &"CheckBox": &"focus", &"CheckButton": &"focus", &"OptionButton": &"focus",
	&"LinkButton": &"focus", &"MenuButton": &"focus", &"LineEdit": &"focus", &"TextEdit": &"focus",
	&"HSlider": &"grabber_area_highlight", &"VSlider": &"grabber_area_highlight",
	&"ItemList": &"focus", &"Tree": &"focus", &"TabBar": &"tab_focus", &"TabContainer": &"tab_focus",
	&"HScrollBar": &"scroll_focus", &"VScrollBar": &"scroll_focus", &"ScrollContainer": &"focus",
}
## Font size multipliers per label variation (others use the base size).
const SIZE_SCALE: Dictionary = {TITLE: 1.8, HEADING: 1.25, READING: 1.5, DISPLAY: 4.0}
## Control types whose text size follows the text scale.
const TEXT_TYPES: Array[StringName] = [&"Label", &"Button", &"CheckBox", &"CheckButton", &"OptionButton",
	&"LinkButton", &"MenuButton", &"LineEdit", &"TextEdit", &"ItemList", &"Tree", &"TabBar", &"TabContainer",
	&"PopupMenu", &"TooltipLabel", &"ProgressBar"]

static var _theme: Theme
static var _text_scale := 1.0
static var _high_contrast := false


## The shared Theme (built on first use). The same object is kept for the whole run, so changes reach open panels.
static func get_theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_build()
	return _theme


## Sets every font size from BASE_FONT_SIZE * text_scale (titles larger), on the same Theme object.
static func apply_text_scale(text_scale: float) -> void:
	_text_scale = clampf(text_scale, 0.75, 2.0)
	_apply_sizes(get_theme())


## The text scale in use.
static func text_scale() -> float:
	return _text_scale


## Switches between the normal and the high contrast colours (same Theme object).
static func set_high_contrast(on: bool) -> void:
	if on == _high_contrast and _theme != null:
		return
	_high_contrast = on
	if _theme != null:
		_build()


static func is_high_contrast() -> bool:
	return _high_contrast


## Colours of the active palette by role: text, muted, heading, good, warn, urgent, focus, accent, panel, hud,
## card, subtitle, backdrop, backdrop_light, button, button_hover, button_pressed, button_disabled, text_disabled,
## primary, primary_text, danger, border, border_soft, field, track, keycap, cool.
static func palette() -> Dictionary:
	if _high_contrast:
		return {
			"text": Color(1, 1, 1), "muted": Color(0.9, 0.9, 0.9), "heading": Color(1.0, 0.78, 0.45),
			"good": Color(0.6, 1.0, 0.6), "warn": Color(1.0, 0.92, 0.3), "urgent": Color(1.0, 0.68, 0.62),
			"focus": Color(1.0, 1.0, 0.2), "accent": Color(1.0, 0.6, 0.2),
			"panel": Color(0, 0, 0, 0.98), "hud": Color(0, 0, 0, 0.95), "card": Color(0.06, 0.06, 0.06, 1.0),
			"subtitle": Color(0, 0, 0, 0.97), "backdrop": Color(0, 0, 0, 0.85), "backdrop_light": Color(0, 0, 0, 0.6),
			"button": Color(0.1, 0.1, 0.1, 1), "button_hover": Color(0.22, 0.22, 0.22, 1),
			"button_pressed": Color(0.4, 0.22, 0.05, 1), "button_disabled": Color(0.08, 0.08, 0.08, 1),
			"text_disabled": Color(0.7, 0.7, 0.7), "primary": Color(1.0, 0.62, 0.2, 1), "primary_text": Color(0, 0, 0),
			"danger": Color(0.5, 0.05, 0.05, 1), "border": Color(1, 1, 1), "border_soft": Color(1, 1, 1),
			"field": Color(0, 0, 0, 1), "track": Color(0, 0, 0, 1), "keycap": Color(0.12, 0.12, 0.12, 1),
			"cool": Color(0.5, 0.9, 1.0),
		}
	return {
		"text": Color(0.95, 0.95, 0.92), "muted": Color(0.76, 0.79, 0.79), "heading": Color(0.91, 0.89, 0.82),
		"good": Color(0.62, 0.90, 0.72), "warn": Color(1.0, 0.84, 0.48), "urgent": Color(1.0, 0.66, 0.60),
		"focus": Color(0.69, 0.91, 0.96), "accent": Color(0.86, 0.42, 0.28),
		"panel": Color(0.045, 0.055, 0.065, 0.97), "hud": Color(0.035, 0.045, 0.055, 0.92), "card": Color(0.075, 0.09, 0.10, 0.98),
		"subtitle": Color(0.02, 0.025, 0.03, 0.95), "backdrop": Color(0.015, 0.02, 0.025, 0.80),
		"backdrop_light": Color(0.015, 0.02, 0.025, 0.55),
		"button": Color(0.12, 0.14, 0.15, 1), "button_hover": Color(0.22, 0.25, 0.26, 1),
		"button_pressed": Color(0.32, 0.21, 0.18, 1), "button_disabled": Color(0.09, 0.10, 0.11, 1),
		"text_disabled": Color(0.60, 0.63, 0.63), "primary": Color(0.82, 0.80, 0.73, 1), "primary_text": Color(0.06, 0.07, 0.07),
		"danger": Color(0.48, 0.12, 0.11, 1), "border": Color(0.40, 0.44, 0.44), "border_soft": Color(0.25, 0.29, 0.30),
		"field": Color(0.025, 0.035, 0.04, 0.97), "track": Color(0.025, 0.035, 0.04, 0.97), "keycap": Color(0.14, 0.16, 0.17, 1),
		"cool": Color(0.60, 0.84, 0.88),
	}


## Drops the shared Theme (call only when the game or a test is shutting down; the next get_theme() builds a new one).
static func release() -> void:
	_theme = null


## WCAG relative luminance of a colour (alpha ignored).
static func luminance(c: Color) -> float:
	var ch := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * ch.call(c.r) + 0.7152 * ch.call(c.g) + 0.0722 * ch.call(c.b)


## WCAG contrast ratio of two opaque colours (1 to 21).
static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## The ProgressBar variation for a level: &"ok", &"warn" or &"urgent".
static func bar_of(level: StringName) -> StringName:
	match level:
		&"warn":
			return BAR_WARN
		&"urgent":
			return BAR_URGENT
	return BAR_GOOD


## A key cap with the key's name in it, for hints such as [E] Use. Not focusable, ignores the mouse.
static func key_cap(key_text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.theme_type_variation = KEYCAP
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.name = "Key"
	l.text = key_text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_child(l)
	return cap


# ---------------------------------------------------------------- building

static func _build() -> void:
	var t := _theme
	var p := palette()
	t.default_font_size = roundi(BASE_FONT_SIZE * _text_scale)
	for v: StringName in [PANEL, HUD_PANEL, CARD, SUBTITLE, KEYCAP, CHIP, TOAST]:
		t.set_type_variation(v, &"PanelContainer")
	for v: StringName in [TITLE, HEADING, MUTED, READING, GOOD, WARN, URGENT, DISPLAY]:
		t.set_type_variation(v, &"Label")
	for v: StringName in [BAR_GOOD, BAR_WARN, BAR_URGENT, BAR_COOL]:
		t.set_type_variation(v, &"ProgressBar")
	t.set_type_variation(PRIMARY_BUTTON, &"Button")
	t.set_type_variation(DANGER_BUTTON, &"Button")
	t.set_type_variation(BACKDROP, &"Panel")
	t.set_type_variation(BACKDROP_LIGHT, &"Panel")
	t.set_type_variation(SCREEN_MARGIN, &"MarginContainer")

	# Fonts: the engine's own font, made heavier for titles, headings and buttons (no font file to ship or credit).
	var base_font := ThemeDB.fallback_font
	if base_font != null:
		t.set_font(&"font", TITLE, _weighted(base_font, 0.8, 1))
		t.set_font(&"font", DISPLAY, _weighted(base_font, 0.6, 4))
		t.set_font(&"font", HEADING, _weighted(base_font, 0.6, 0))
		t.set_font(&"font", READING, _weighted(base_font, 0.6, 0))
		var button_font := _weighted(base_font, 0.4, 0)
		for type: StringName in [&"Button", &"OptionButton", &"MenuButton", &"TabBar", &"TabContainer"]:
			t.set_font(&"font", type, button_font)

	# Panels
	var panel := _box(p.panel, 24, 2, p.border, 2 if _high_contrast else 1)
	_shadow(panel, 8)
	t.set_stylebox(&"panel", &"PanelContainer", panel)
	t.set_stylebox(&"panel", PANEL, panel)
	t.set_stylebox(&"panel", HUD_PANEL, _box(p.hud, 12, 10, Color(p.border, 1.0 if _high_contrast else 0.55), 1, 14, 10))
	t.set_stylebox(&"panel", CARD, _box(p.card, 16, 10, p.border_soft, 1))
	t.set_stylebox(&"panel", SUBTITLE, _box(p.subtitle, 12, 10, Color(p.border, 1.0 if _high_contrast else 0.4), 1, 22, 12))
	var keycap := _box(p.keycap, 0, 6, p.muted, 1, 9, 1)
	keycap.border_width_bottom = 3
	t.set_stylebox(&"panel", KEYCAP, keycap)
	t.set_stylebox(&"panel", CHIP, _box(p.card, 0, 16, p.border, 1, 14, 5))
	var toast := _box(p.hud, 0, 8, p.accent, 0, 18, 10)
	toast.border_width_left = 5
	t.set_stylebox(&"panel", TOAST, toast)
	t.set_stylebox(&"panel", &"Panel", _box(p.panel, 0, 6))
	t.set_stylebox(&"panel", BACKDROP, _box(p.backdrop, 0, 0))
	t.set_stylebox(&"panel", BACKDROP_LIGHT, _box(p.backdrop_light, 0, 0))
	t.set_stylebox(&"panel", &"PopupPanel", _box(Color(p.panel, 1.0), 18, 10, p.muted, 1))
	t.set_stylebox(&"panel", &"PopupMenu", _box(Color(p.panel, 1.0), 8, 8, p.border, 1))
	t.set_stylebox(&"hover", &"PopupMenu", _box(p.button_hover, 4, 5))
	t.set_stylebox(&"panel", &"TooltipPanel", _box(p.subtitle, 10, 6, p.border, 1))
	var tab_panel := _box(p.card, 18, 10, p.border_soft, 1)
	tab_panel.corner_radius_top_left = 0
	t.set_stylebox(&"panel", &"TabContainer", tab_panel)
	var line := StyleBoxLine.new()
	line.color = p.border_soft
	line.thickness = 2 if _high_contrast else 1
	t.set_stylebox(&"separator", &"HSeparator", line)
	var vline := line.duplicate() as StyleBoxLine
	vline.vertical = true
	t.set_stylebox(&"separator", &"VSeparator", vline)

	# Labels
	t.set_color(&"font_color", &"Label", p.text)
	for v: StringName in [TITLE, READING, DISPLAY]:
		t.set_color(&"font_color", v, p.text)
	t.set_color(&"font_color", HEADING, p.heading)
	t.set_color(&"font_color", MUTED, p.muted)
	t.set_color(&"font_color", GOOD, p.good)
	t.set_color(&"font_color", WARN, p.warn)
	t.set_color(&"font_color", URGENT, p.urgent)
	t.set_color(&"font_color", &"TooltipLabel", p.text)
	t.set_color(&"font_outline_color", &"Label", Color(0, 0, 0, 0.0))
	t.set_constant(&"line_spacing", &"Label", 4)

	# Buttons (and the button-like types)
	var focus := _focus_box(p.focus)
	for type: StringName in [&"Button", &"CheckBox", &"CheckButton", &"OptionButton", &"MenuButton", &"LinkButton"]:
		t.set_stylebox(&"focus", type, focus)
		t.set_color(&"font_color", type, p.text)
		t.set_color(&"font_hover_color", type, p.text)
		t.set_color(&"font_pressed_color", type, p.text)
		t.set_color(&"font_hover_pressed_color", type, p.text)
		t.set_color(&"font_focus_color", type, p.text)
		t.set_color(&"font_disabled_color", type, p.text_disabled)
		if type == &"LinkButton":
			continue
		if type == &"CheckBox" or type == &"CheckButton":
			# A switch shows its state with its own drawn icon; the row only lights up under the pointer.
			var clear := Color(0, 0, 0, 0)
			t.set_stylebox(&"normal", type, _box(clear, 8, 8, clear, 0, 12, 8))
			t.set_stylebox(&"pressed", type, _box(clear, 8, 8, clear, 0, 12, 8))
			t.set_stylebox(&"hover", type, _box(Color(p.button_hover, 0.6), 8, 8, clear, 0, 12, 8))
			t.set_stylebox(&"hover_pressed", type, _box(Color(p.button_hover, 0.6), 8, 8, clear, 0, 12, 8))
			t.set_stylebox(&"disabled", type, _box(clear, 8, 8, clear, 0, 12, 8))
			t.set_constant(&"h_separation", type, 12)
			continue
		t.set_stylebox(&"normal", type, _box(p.button, 8, 8, p.border, 1, 18, 9))
		t.set_stylebox(&"hover", type, _box(p.button_hover, 8, 8, p.muted, 1, 18, 9))
		t.set_stylebox(&"pressed", type, _box(p.button_pressed, 8, 8, p.accent, 2, 18, 9))
		t.set_stylebox(&"hover_pressed", type, _box(p.button_pressed.lightened(0.08), 8, 8, p.accent, 2, 18, 9))
		t.set_stylebox(&"disabled", type, _box(p.button_disabled, 8, 8, p.border_soft, 1, 18, 9))
	t.set_stylebox(&"normal", PRIMARY_BUTTON, _box(p.primary, 8, 8, p.primary.lightened(0.25), 1, 22, 10))
	t.set_stylebox(&"hover", PRIMARY_BUTTON, _box(p.primary.lightened(0.14), 8, 8, p.primary.lightened(0.4), 1, 22, 10))
	t.set_stylebox(&"pressed", PRIMARY_BUTTON, _box(p.primary.darkened(0.15), 8, 8, p.primary.lightened(0.4), 2, 22, 10))
	t.set_stylebox(&"hover_pressed", PRIMARY_BUTTON, _box(p.primary.darkened(0.15), 8, 8, p.primary.lightened(0.4), 2, 22, 10))
	for c: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		t.set_color(c, PRIMARY_BUTTON, p.primary_text)
	t.set_stylebox(&"normal", DANGER_BUTTON, _box(p.danger, 8, 8, p.urgent, 1, 18, 9))
	t.set_stylebox(&"hover", DANGER_BUTTON, _box(p.danger.lightened(0.15), 8, 8, p.urgent, 1, 18, 9))
	t.set_stylebox(&"pressed", DANGER_BUTTON, _box(p.danger.darkened(0.15), 8, 8, p.urgent, 2, 18, 9))

	# Switches, tick boxes and radio dots: drawn here so they are big, clear and match the palette.
	var switch_on := _switch_icon(true, p, false)
	var switch_off := _switch_icon(false, p, false)
	for icon_name: StringName in [&"checked", &"checked_mirrored"]:
		t.set_icon(icon_name, &"CheckButton", switch_on)
	for icon_name: StringName in [&"unchecked", &"unchecked_mirrored"]:
		t.set_icon(icon_name, &"CheckButton", switch_off)
	for icon_name: StringName in [&"checked_disabled", &"checked_disabled_mirrored"]:
		t.set_icon(icon_name, &"CheckButton", _switch_icon(true, p, true))
	for icon_name: StringName in [&"unchecked_disabled", &"unchecked_disabled_mirrored"]:
		t.set_icon(icon_name, &"CheckButton", _switch_icon(false, p, true))
	t.set_icon(&"checked", &"CheckBox", _tick_icon(true, p, false, false))
	t.set_icon(&"unchecked", &"CheckBox", _tick_icon(false, p, false, false))
	t.set_icon(&"checked_disabled", &"CheckBox", _tick_icon(true, p, true, false))
	t.set_icon(&"unchecked_disabled", &"CheckBox", _tick_icon(false, p, true, false))
	t.set_icon(&"radio_checked", &"CheckBox", _tick_icon(true, p, false, true))
	t.set_icon(&"radio_unchecked", &"CheckBox", _tick_icon(false, p, false, true))
	t.set_icon(&"radio_checked_disabled", &"CheckBox", _tick_icon(true, p, true, true))
	t.set_icon(&"radio_unchecked_disabled", &"CheckBox", _tick_icon(false, p, true, true))

	# Text fields
	for type: StringName in [&"LineEdit", &"TextEdit"]:
		t.set_stylebox(&"normal", type, _box(p.field, 8, 8, p.border, 1, 12, 9))
		t.set_stylebox(&"read_only", type, _box(p.button_disabled, 8, 8, p.border_soft, 1, 12, 9))
		t.set_stylebox(&"focus", type, focus)
		t.set_color(&"font_color", type, p.text)
		t.set_color(&"font_placeholder_color", type, p.text_disabled)
		t.set_color(&"caret_color", type, p.focus)
		t.set_color(&"selection_color", type, Color(p.focus, 0.35))

	# Sliders: no separate focus box in Godot; the highlighted grabber area is drawn on focus and hover.
	for type: StringName in [&"HSlider", &"VSlider"]:
		t.set_stylebox(&"slider", type, _box(p.track, 0, 5, p.border, 1, 0, 5))
		t.set_stylebox(&"grabber_area", type, _box(p.accent, 0, 5, p.accent, 0, 0, 5))
		var hl := _box(p.focus, 0, 5, p.focus, 0, 0, 5)
		hl.expand_margin_top = 3
		hl.expand_margin_bottom = 3
		t.set_stylebox(&"grabber_area_highlight", type, hl)
		t.set_icon(&"grabber", type, _dot_icon(p.text, p.accent, 26))
		t.set_icon(&"grabber_highlight", type, _dot_icon(p.text, p.focus, 30))
		t.set_icon(&"grabber_disabled", type, _dot_icon(p.text_disabled, p.border, 26))

	# Lists, tabs, scrolling
	for type: StringName in [&"ItemList", &"Tree"]:
		t.set_stylebox(&"panel", type, _box(p.field, 8, 8, p.border_soft, 1))
		t.set_stylebox(&"focus", type, focus)
		t.set_stylebox(&"selected", type, _box(p.button_pressed, 4, 5))
		t.set_stylebox(&"selected_focus", type, _box(p.button_pressed, 4, 5, p.focus, 2))
		t.set_stylebox(&"hovered", type, _box(Color(p.button_hover, 0.6), 4, 5))
		t.set_color(&"font_color", type, p.text)
		t.set_color(&"font_selected_color", type, p.text)
		t.set_color(&"font_hovered_color", type, p.text)
	t.set_constant(&"v_separation", &"ItemList", 8)
	t.set_constant(&"v_separation", &"Tree", 8)
	for type: StringName in [&"TabBar", &"TabContainer"]:
		var selected := _box(p.card, 8, 8, p.accent, 0, 22, 10)
		selected.border_width_top = 4
		selected.corner_radius_bottom_left = 0
		selected.corner_radius_bottom_right = 0
		t.set_stylebox(&"tab_selected", type, selected)
		for state: StringName in [&"tab_unselected", &"tab_hovered", &"tab_disabled"]:
			var bg: Color = p.button_hover if state == &"tab_hovered" else (p.button_disabled if state == &"tab_disabled" else p.button)
			var tab := _box(bg, 8, 8, p.border_soft, 1, 22, 10)
			tab.corner_radius_bottom_left = 0
			tab.corner_radius_bottom_right = 0
			t.set_stylebox(state, type, tab)
		t.set_stylebox(&"tab_focus", type, focus)
		t.set_color(&"font_selected_color", type, p.heading)
		t.set_color(&"font_unselected_color", type, p.text)
		t.set_color(&"font_hovered_color", type, p.text)
		t.set_color(&"font_disabled_color", type, p.text_disabled)
	t.set_stylebox(&"focus", &"ScrollContainer", focus)
	for type: StringName in [&"HScrollBar", &"VScrollBar"]:
		t.set_stylebox(&"scroll", type, _box(Color(p.track, 0.7), 5, 5))
		t.set_stylebox(&"scroll_focus", type, _box(Color(p.track, 0.7), 5, 5, p.focus, 2))
		t.set_stylebox(&"grabber", type, _box(p.border, 5, 5))
		t.set_stylebox(&"grabber_highlight", type, _box(p.muted, 5, 5))
		t.set_stylebox(&"grabber_pressed", type, _box(p.focus, 5, 5))

	# Gauges: a real bar with a rounded track; the fill colour says how things are (always with a word beside it).
	t.set_stylebox(&"background", &"ProgressBar", _box(p.track, 0, 7, p.border, 1, 0, 8))
	t.set_stylebox(&"fill", &"ProgressBar", _box(p.accent, 0, 7))
	t.set_color(&"font_color", &"ProgressBar", p.text)
	var fills := {BAR_GOOD: p.good, BAR_WARN: p.warn, BAR_URGENT: p.urgent, BAR_COOL: p.cool}
	for v: StringName in fills:
		t.set_stylebox(&"background", v, _box(p.track, 0, 7, p.border, 1, 0, 8))
		t.set_stylebox(&"fill", v, _box((fills[v] as Color).darkened(0.12), 0, 7))
	t.set_color(&"font_color", &"PopupMenu", p.text)
	t.set_color(&"font_hover_color", &"PopupMenu", p.text)
	t.set_constant(&"v_separation", &"PopupMenu", 10)

	# Spacing
	t.set_constant(&"separation", &"VBoxContainer", 10)
	t.set_constant(&"separation", &"HBoxContainer", 10)
	t.set_constant(&"h_separation", &"GridContainer", 14)
	t.set_constant(&"v_separation", &"GridContainer", 10)
	for side: String in ["left", "right", "top", "bottom"]:
		t.set_constant(StringName("margin_" + side), SCREEN_MARGIN, 40)
	_apply_sizes(t)


static func _apply_sizes(t: Theme) -> void:
	var base := roundi(BASE_FONT_SIZE * _text_scale)
	t.default_font_size = base
	for type: StringName in TEXT_TYPES:
		t.set_font_size(&"font_size", type, base)
	for v: StringName in SIZE_SCALE:
		t.set_font_size(&"font_size", v, roundi(BASE_FONT_SIZE * _text_scale * float(SIZE_SCALE[v])))
	t.set_font_size(&"normal_font_size", &"RichTextLabel", base)
	t.set_font_size(&"bold_font_size", &"RichTextLabel", base)


## A flat box with rounded corners. `h_margin` / `v_margin` override the content margins when not negative.
static func _box(bg: Color, margin: int, radius: int, border := Color(0, 0, 0, 0), border_w := 0, h_margin := -1, v_margin := -1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(mini(radius, 2))
	s.corner_detail = 6
	s.border_color = border
	s.set_border_width_all(border_w)
	s.content_margin_left = h_margin if h_margin >= 0 else margin
	s.content_margin_right = h_margin if h_margin >= 0 else margin
	s.content_margin_top = v_margin if v_margin >= 0 else margin
	s.content_margin_bottom = v_margin if v_margin >= 0 else margin
	return s


## A soft drop shadow under a box (not in high contrast, where edges stay crisp).
static func _shadow(s: StyleBoxFlat, size: int) -> void:
	if _high_contrast:
		return
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = size
	s.shadow_offset = Vector2(0, 4)


## The engine font made heavier (`embolden`) with extra space between letters (`spacing`, pixels).
static func _weighted(base_font: Font, embolden: float, spacing: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base_font
	f.variation_embolden = embolden
	f.spacing_glyph = spacing
	return f


## The keyboard focus ring: a bright outline along the control's own edge. It stays inside the control, so a
## scrolling list never cuts part of it off.
static func _focus_box(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = color
	s.set_border_width_all(4 if _high_contrast else 3)
	s.set_corner_radius_all(2)
	return s


# ---------------------------------------------------------------- drawn icons

## Paints `color` into `img` wherever `distance` (a signed distance in pixels, negative inside) says so, smooth-edged.
static func _paint(img: Image, color: Color, distance: Callable) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var cover := clampf(0.5 - float(distance.call(Vector2(x + 0.5, y + 0.5))), 0.0, 1.0) * color.a
			if cover > 0.0:
				img.set_pixel(x, y, img.get_pixel(x, y).blend(Color(color, cover)))


static func _sd_round_box(pt: Vector2, centre: Vector2, half: Vector2, radius: float) -> float:
	var q := (pt - centre).abs() - half + Vector2(radius, radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


static func _sd_segment(pt: Vector2, a: Vector2, b: Vector2, half_width: float) -> float:
	var ab := b - a
	var h := clampf((pt - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (pt - a - ab * h).length() - half_width


static func _new_image(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


## An on/off switch: a pill with a round knob. On = knob right, bright fill and a tick; off = knob left, dark and empty.
static func _switch_icon(on: bool, p: Dictionary, disabled: bool) -> ImageTexture:
	var w := 56
	var h := 30
	var img := _new_image(w, h)
	var centre := Vector2(w, h) * 0.5
	var half := Vector2(w, h) * 0.5 - Vector2(1, 1)
	var edge: Color = p.good if on else p.muted
	var fill: Color = (p.good as Color).darkened(0.45) if on else p.track
	var knob: Color = p.text
	if disabled:
		edge = p.border
		fill = p.button_disabled
		knob = p.text_disabled
	_paint(img, edge, func(pt: Vector2) -> float: return _sd_round_box(pt, centre, half, half.y))
	_paint(img, fill, func(pt: Vector2) -> float: return _sd_round_box(pt, centre, half - Vector2(2, 2), half.y - 2.0))
	var knob_at := Vector2(w - h * 0.5, h * 0.5) if on else Vector2(h * 0.5, h * 0.5)
	_paint(img, knob, func(pt: Vector2) -> float: return (pt - knob_at).length() - (h * 0.5 - 5.0))
	if on:
		# a tick on the dark side of the pill, so the state does not depend on colour
		var a := Vector2(10, 15)
		var b := Vector2(14.5, 19.5)
		var c := Vector2(22, 10.5)
		_paint(img, knob, func(pt: Vector2) -> float: return minf(_sd_segment(pt, a, b, 1.4), _sd_segment(pt, b, c, 1.4)))
	return ImageTexture.create_from_image(img)


## A tick box (or a radio dot when `radio`).
static func _tick_icon(on: bool, p: Dictionary, disabled: bool, radio: bool) -> ImageTexture:
	var s := 28
	var img := _new_image(s, s)
	var centre := Vector2(s, s) * 0.5
	var half := Vector2(s, s) * 0.5 - Vector2(1, 1)
	var radius := half.x if radio else 6.0
	var edge: Color = p.border if disabled else (p.accent if on else p.muted)
	var fill: Color = p.button_disabled if disabled else (p.accent if on else p.track)
	var mark: Color = p.text_disabled if disabled else p.primary_text
	_paint(img, edge, func(pt: Vector2) -> float: return _sd_round_box(pt, centre, half, radius))
	_paint(img, fill, func(pt: Vector2) -> float: return _sd_round_box(pt, centre, half - Vector2(2, 2), maxf(radius - 2.0, 1.0)))
	if on and radio:
		_paint(img, mark, func(pt: Vector2) -> float: return (pt - centre).length() - 5.0)
	elif on:
		var a := Vector2(7, 14.5)
		var b := Vector2(12, 19.5)
		var c := Vector2(21, 8.5)
		_paint(img, mark, func(pt: Vector2) -> float: return minf(_sd_segment(pt, a, b, 1.7), _sd_segment(pt, b, c, 1.7)))
	return ImageTexture.create_from_image(img)


## A round slider handle: a ring of `ring` around a `fill` dot.
static func _dot_icon(fill: Color, ring: Color, size: int) -> ImageTexture:
	var img := _new_image(size, size)
	var centre := Vector2(size, size) * 0.5
	_paint(img, ring, func(pt: Vector2) -> float: return (pt - centre).length() - (size * 0.5 - 1.0))
	_paint(img, fill, func(pt: Vector2) -> float: return (pt - centre).length() - (size * 0.5 - 5.0))
	return ImageTexture.create_from_image(img)
