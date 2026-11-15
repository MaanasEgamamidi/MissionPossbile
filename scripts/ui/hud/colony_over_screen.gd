extends UiPanel
## The COLONY OVER screen (upgrade paths plan §1.5): full screen, the world hidden. It says why in plain words ("The
## colony ran out of oxygen."), the sol, and what would have helped, with two buttons:
##   * "Load last save"  (host only, and only when a save exists): emits load_last_save_pressed.
##   * "Main menu":        emits main_menu_pressed.
## The game has no in-game "load" yet: GameMain decides what the buttons do (see the hook lines in the report:
## Main menu = reload the scene WITHOUT saving the dead colony; Load last save = the same reload, then continue the
## newest save). It cannot be closed with Esc and a critical alert does not close it. Read only: state.colony_over
## (scripts/survival/colony_over.gd). Opened with UiRoot.open(), which frees the mouse:
##     var screen := preload("res://scripts/ui/hud/colony_over_screen.gd").new()
##     ui.open(screen)

const ColonyOver := preload("res://scripts/survival/colony_over.gd")

signal main_menu_pressed
signal load_last_save_pressed

const REASON_SYMBOLS := {"oxygen": "O₂", "water": "💧", "food": "✿", "power": "⚡", "crew": "✚"}

var _reason: Label
var _sol: Label
var _hint: Label
var _load: Button
var _menu: Button


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	name = "ColonyOverScreen"
	theme_type_variation = UiTheme.PANEL
	keeps_world_visible = false
	captures_mouse = true
	max_width = 900.0
	max_height = -1.0
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 14)
	add_child(col)
	var title := Label.new()
	title.text = "COLONY OVER"
	title.theme_type_variation = UiTheme.DISPLAY
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override(&"font_color", UiTheme.palette().urgent)
	col.add_child(title)
	_reason = _text(col, "Reason", UiTheme.TITLE)
	_sol = _text(col, "Sol", UiTheme.MUTED)
	var head := _text(col, "HintHeading", UiTheme.HEADING)
	head.text = "What would have helped"
	_hint = _text(col, "Hint", &"")
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 16)
	col.add_child(buttons)
	_load = Button.new()
	_load.name = "LoadLastSave"
	_load.text = "Load last save"
	_load.theme_type_variation = UiTheme.PRIMARY_BUTTON
	_load.pressed.connect(func() -> void: load_last_save_pressed.emit())
	buttons.add_child(_load)
	_menu = Button.new()
	_menu.name = "MainMenu"
	_menu.text = "Main menu"
	_menu.pressed.connect(func() -> void: main_menu_pressed.emit())
	buttons.add_child(_menu)
	refresh()


func panel_title() -> String:
	return "Colony over"


func refresh() -> void:
	if services == null or not services.has_game():
		return
	var o: Dictionary = services.state().colony_over
	var reason := String(o.get("reason", ""))
	var sym := String(REASON_SYMBOLS.get(reason, "☢"))
	_reason.text = "%s  %s" % [sym, String(o.get("text", "The colony could not go on."))]
	_sol.text = "Sol %d" % int(o.get("sol", 1))
	_hint.text = String(o.get("hint", ""))
	_load.visible = can_load_save()


## True when this machine can load a save: the host (or solo player) with a save on disk.
func can_load_save() -> bool:
	return services != null and services.is_authority() and services.saves != null and services.saves.has_save()


func first_focus() -> Control:
	return _load if _load != null and _load.visible else _menu


## The player must choose a button: Esc does not close it.
func can_close() -> bool:
	return false


## A critical alert never closes it.
func interrupt(_reason_text := "") -> void:
	pass


func _text(parent: Control, node_name: String, variation: StringName) -> Label:
	var l := Label.new()
	l.name = node_name
	if variation != &"":
		l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 600
	parent.add_child(l)
	return l
