extends PanelContainer
## The COLONY OVER countdown banner (upgrade paths plan §1.5): big and centred while a life store is empty, e.g.
## "Oxygen is empty!  4:32 left — make oxygen now". It counts down in real time between host updates (paused time
## does not count) and goes away when the countdown stops. When the colony is over it hides and emits
## `colony_over_reached(record)` once, so the HUD can open the full COLONY OVER screen (colony_over_screen.gd).
## Read only: state.colony_over (scripts/survival/colony_over.gd). Never takes the mouse. Loaded by path:
##     var banner := preload("res://scripts/ui/hud/colony_over_banner.gd").new()
##     banner.services = services
##     add_child(banner)

const ColonyOver := preload("res://scripts/survival/colony_over.gd")

signal colony_over_reached(record: Dictionary)

var services: GameServices
## True: the banner centres itself on the screen, CENTRE_SHARE of the height down.
var auto_place := true
const CENTRE_SHARE := 0.30

var _head: Label
var _clock: Label
var _todo: Label
var _reported := false
## The host's last "left_s", and real seconds counted locally since it changed (smooth on clients).
var _host_left := -1.0
var _since := 0.0
var _blink := 0.0


func _init() -> void:
	name = "ColonyOverBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	visible = false
	var style := AstraStyle.glass(AstraStyle.RADIUS, 28, 16, true)
	style.border_color = AstraStyle.DANGER
	style.set_border_width_all(2)
	add_theme_stylebox_override(&"panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	_head = AstraStyle.label("", 28, AstraStyle.DANGER, "Head")
	row.add_child(_head)
	_clock = AstraStyle.label("5:00", 40, AstraStyle.TEXT, "Clock")
	row.add_child(_clock)
	_todo = AstraStyle.label("", 18, AstraStyle.WARN, "Todo")
	_todo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_todo)


func _process(delta: float) -> void:
	if services == null or not services.has_game():
		visible = false
		return
	var st := services.state()
	if ColonyOver.is_over(st):
		visible = false
		if not _reported:
			_reported = true
			colony_over_reached.emit(st.colony_over.duplicate(true))
		return
	_reported = false
	var cd := ColonyOver.countdown_now(st)
	if cd.is_empty():
		visible = false
		_host_left = -1.0
		return
	var host_left := float(cd.get("left_s", ColonyOver.COUNTDOWN_SECONDS))
	if not is_equal_approx(host_left, _host_left):
		_host_left = host_left
		_since = 0.0
	elif not services.session.paused:
		_since += delta
	var left := maxf(0.0, _host_left - _since)
	visible = true
	var reason := String(cd.get("reason", ""))
	_head.text = ColonyOver.empty_words(reason) + "!"
	_clock.text = "%s left" % ColonyOver.clock_text(left)
	_todo.text = "— %s" % String(cd.get("action", ""))
	_blink += delta
	var hot := left <= ColonyOver.LAST_MINUTE_SECONDS and fmod(_blink, 1.0) < 0.5
	AstraStyle.set_color(_clock, AstraStyle.DANGER if hot else AstraStyle.TEXT)
	if auto_place:
		var screen := get_viewport_rect().size
		size = get_combined_minimum_size()
		position = Vector2(roundf((screen.x - size.x) * 0.5), roundf(screen.y * CENTRE_SHARE))
