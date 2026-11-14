class_name UiTheme
extends RefCounted
## The one shared Theme. STUB: names are fixed; worker A builds the real look.
## Panels refer to these type variation names (Control.theme_type_variation) instead of styling themselves.

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

## Base font size in pixels at text scale 1.0 and UI scale 1.0.
const BASE_FONT_SIZE := 18

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.default_font_size = BASE_FONT_SIZE
	return _theme


## Rebuilds font sizes for a text scale (1.0 normal, up to 1.6). STUB.
static func apply_text_scale(_text_scale: float) -> void:
	pass
