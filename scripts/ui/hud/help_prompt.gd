extends PanelContainer
## "Press H for help" (owner 2026-11-15, docs/revisions/UPGRADE_PATHS_PLAN.md §1.6): a small gold-edged prompt near the
## bottom centre, just above the dock, when a timed emergency has run past PROMPT_FRACTION of its time: the airlock
## leak's lethal exposure timer, a dust storm's arrival countdown while outside, the COLONY OVER countdown, a solar
## storm's warning (the list comes from help_key.gd timed_emergencies()). It shows for SHOW_S seconds, and again every
## REPEAT_S while that emergency is still not solved. Not while the H line is already showing, nor while a panel or
## mini-game is open. Gold edge: gold means "this way" (the help line), never a warning colour.
## Made by MissionHud next to the help key. Loaded by path (no class_name).

const PROMPT_FRACTION := 0.6
## Seconds the prompt stays, and between two prompts for the same emergency.
const SHOW_S := 4.0
const REPEAT_S := 30.0
const FADE_S := 0.3
const LOOK_S := 0.25
const GOLD := Color(1.0, 0.8, 0.22)
## Space above the dock (and the build chip), pixels.
const GAP := 14.0

var services: GameServices
## MissionHud (for its `ui`, `dock` and `build_chip`).
var hud: Node
## scripts/guide/help_key.gd
var help_key: Node

var _key: Label
var _text: Label
var _left := 0.0
var _look_left := 0.0
## emergency id -> Time seconds it was last prompted.
var _prompted := {}


func setup(p_services: GameServices, p_hud: Node, p_help_key: Node) -> void:
	services = p_services
	hud = p_hud
	help_key = p_help_key
	name = "HelpPrompt"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := AstraStyle.pill(Color(AstraStyle.GLASS_SOLID, 0.94), AstraStyle.RADIUS_SM + 2, 16, 8, GOLD)
	style.set_border_width_all(2)
	style.shadow_color = Color(GOLD, 0.25)
	style.shadow_size = 12
	add_theme_stylebox_override(&"panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var cap := AstraStyle.panel(AstraStyle.pill(Color(GOLD, 0.18), 6, 8, 2, GOLD), "Key")
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cap)
	_key = AstraStyle.label("H", 16, GOLD, "KeyText")
	cap.add_child(_key)
	_text = AstraStyle.label("Press H for help", 17, AstraStyle.TEXT, "Text")
	row.add_child(_text)
	visible = false
	modulate.a = 0.0


## Shows the prompt now (SHOW_S seconds).
func pop() -> void:
	var key := _key_name()
	_key.text = key
	_text.text = "Press %s for help" % key
	_left = SHOW_S
	visible = true
	reset_size()


func _process(delta: float) -> void:
	if services == null or not services.has_game():
		visible = false
		return
	if _left > 0.0:
		_left -= delta
		var a := clampf(minf(SHOW_S - _left, _left) / FADE_S, 0.0, 1.0)
		modulate.a = a
		if _left <= 0.0 or _blocked():
			_left = 0.0
			visible = false
			modulate.a = 0.0
	if visible:
		_place()
	_look_left -= delta
	if _look_left > 0.0:
		return
	_look_left = LOOK_S
	_look()


## Pops the prompt for a timed emergency past PROMPT_FRACTION, once and then every REPEAT_S while it lasts.
func _look() -> void:
	if help_key == null or not is_instance_valid(help_key):
		return
	var list: Variant = help_key.call(&"timed_emergencies")
	if not list is Array:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var live := {}
	var due := false
	for e: Variant in list:
		if not e is Dictionary:
			continue
		var id := String((e as Dictionary).get("id", ""))
		live[id] = true
		if float((e as Dictionary).get("fraction", 0.0)) < PROMPT_FRACTION:
			continue
		if now - float(_prompted.get(id, -1e9)) >= REPEAT_S:
			_prompted[id] = now
			due = true
	# An emergency that is over may prompt again when it comes back.
	for id: Variant in _prompted.keys():
		if not live.has(id):
			_prompted.erase(id)
	if due and not bool(help_key.get("active")) and not _blocked():
		pop()


## True while a panel or mini-game is open (H does nothing then).
func _blocked() -> bool:
	var ui: Variant = hud.get("ui") if hud != null and is_instance_valid(hud) else null
	return ui is UiRoot and (ui as UiRoot).is_open()


## Bottom centre, just above the dock and the build chip.
func _place() -> void:
	var screen := get_viewport_rect().size
	var s := get_combined_minimum_size()
	size = s
	var bottom := screen.y - 24.0
	if hud != null and is_instance_valid(hud):
		for member: StringName in [&"dock", &"build_chip"]:
			var c: Variant = hud.get(member)
			if c is Control and (c as Control).visible:
				bottom = minf(bottom, (c as Control).position.y)
	position = Vector2(roundf((screen.x - s.x) * 0.5), roundf(bottom - GAP - s.y))


func _key_name() -> String:
	if not InputMap.has_action(&"help"):
		return "H"
	var words := PlayerInput.describe(&"help")
	return words if words != "" else "H"
