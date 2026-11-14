class_name UiPanel
extends PanelContainer
## Base of every screen or panel that UiRoot opens (menus, station surfaces, cargo, crew, sources...).
## A panel only reads state for display and asks for changes with services.request(); it never edits state.
##
## Rules every panel follows:
## - Build its controls in setup(); use containers, never fixed pixel positions, so it scales.
## - Use the shared theme (UiTheme) and its type variations instead of local colours and font sizes.
## - Every interactive control is reachable with Tab / arrow keys and shows a visible focus.
## - Colour is never the only cue: pair it with a symbol or a word.

## Ask UiRoot to close this panel.
signal close_requested
## Ask UiRoot to open another panel on top of this one (navigation between screens).
signal open_requested(panel: UiPanel)

var services: GameServices
## True: the mouse is freed and the player body stops steering while this panel is open.
var captures_mouse := true
## True: the 3D view stays visible around the panel (most in-game panels); false: full-screen menus.
var keeps_world_visible := true
## Widest and tallest the panel wants to be, in screen units; UiRoot centres it. 0 = UiRoot's size for this kind of
## panel (UiRoot.PANEL_SIZES), and the whole frame when it has none.
var max_width := 0.0
var max_height := 0.0
## True: an accent line is drawn along the panel's top edge, so every panel reads as part of one console.
var accent_line := true
## True: UiRoot puts the panel against the right edge (a drawer, like the power and build drawers) instead of centring it.
var align_right := false


## Builds the panel. Subclasses call super.setup(p_services) first.
func setup(p_services: GameServices) -> void:
	services = p_services
	theme = UiTheme.get_theme()


## Short title for headers and the window list.
func panel_title() -> String:
	return name


## Re-reads state; UiRoot calls it when opened and about four times a second while open.
func refresh() -> void:
	pass


## The control that gets keyboard focus when the panel opens.
func first_focus() -> Control:
	return _first_focusable(self)


## A panel can veto closing (for example while capturing a key for remapping).
func can_close() -> bool:
	return true


func _draw() -> void:
	if not accent_line or size.x < 80.0:
		return
	# The panel style has round corners: the line starts and ends where the top edge is straight.
	draw_rect(Rect2(18.0, 0.0, size.x - 36.0, 4.0), UiTheme.palette().accent)


static func _first_focusable(node: Node) -> Control:
	for child in node.get_children():
		if child is Control:
			var c := child as Control
			if c.visible and c.focus_mode != Control.FOCUS_NONE:
				return c
			var inner := _first_focusable(c)
			if inner != null:
				return inner
	return null
