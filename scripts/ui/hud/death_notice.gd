extends PanelContainer
## "Why you were brought back" (owner request 2026-11-14): after your own crew member dies and wakes up in the med
## bay, a card at the top centre of the screen says what happened and how to avoid it next time, from the host's
## death record CharacterState.last_death {"cause", "title", "text", "area", "at_hours", "count"}.
##   * Only your own crew member: other astronauts' deaths never show here.
##   * Once per death: it shows when `count` goes up, never twice for the same death.
##   * It shows after the respawn (events.character_recovered), or when a game loads right after a death.
##   * It stays until you press E or for SECONDS, never takes the mouse and never blocks a key.
## Read only: GameHud builds it and lays it out.

## Real seconds the card stays when E is not pressed.
const SECONDS := 12.0
## Real seconds to wait for the death record after the respawn event (on a networked client the record comes with
## the next state snapshot, which can arrive just after the event).
const WAIT_FOR_RECORD_SECONDS := 5.0
## A game loaded this many game hours or less after the death still shows the card.
const RECENT_HOURS := 0.5

signal shown(record: Dictionary)
signal dismissed

var services: GameServices
## The death record on screen now (empty when hidden).
var record: Dictionary = {}
## Seconds before the card goes by itself.
var time_left := 0.0
## Optional func(c: CharacterState) -> Dictionary that reads a death record (tests). Unset: c.last_death.
var record_of := Callable()

var _kicker: Label
var _title: Label
var _text: Label
var _area: Label
var _count: Label
var _hint: Label
## Crew member id -> the death count already shown (or already known when it was first seen).
var _seen: Dictionary = {}
## The crew member this machine plays, last time it was checked.
var _me: StringName = &""
## Seconds left to wait for a death record after the respawn event; 0 = not waiting.
var _waiting := 0.0
var _poll := 0.0


func _init() -> void:
	name = "DeathNotice"
	theme_type_variation = UiTheme.PANEL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	visible = false
	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override(&"separation", 6)
	add_child(col)
	_kicker = _line(col, "Kicker", UiTheme.MUTED)
	_kicker.text = "✚ You woke up in the med bay. This is what happened:"
	_title = _line(col, "Title", UiTheme.TITLE)
	_title.add_theme_color_override(&"font_color", UiTheme.palette().urgent)
	_text = _line(col, "Text", &"")
	_area = _line(col, "Area", UiTheme.MUTED)
	_count = _line(col, "Count", UiTheme.MUTED)
	_hint = _line(col, "Hint", UiTheme.MUTED)
	for c in find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(c as Control).focus_mode = Control.FOCUS_NONE


func setup(p_services: GameServices) -> void:
	services = p_services
	if services == null:
		return
	if not services.events.character_recovered.is_connected(_on_recovered):
		services.events.character_recovered.connect(_on_recovered)
		services.events.game_loaded.connect(_on_loaded)
	_on_loaded("")


func is_showing() -> bool:
	return visible and not record.is_empty()


func title_text() -> String:
	return _title.text if is_showing() else ""


## Every line of the card as shown, top to bottom ("" when hidden).
func shown_text() -> String:
	if not is_showing():
		return ""
	var lines := PackedStringArray()
	for l: Label in [_kicker, _title, _text, _area, _count, _hint]:
		if l.visible and l.text != "":
			lines.append(l.text)
	return "\n".join(lines)


## Hides the card (E, or its time ran out).
func dismiss() -> void:
	if not visible:
		return
	visible = false
	record = {}
	time_left = 0.0
	dismissed.emit()


## The local crew member's death record, or {} (also when the save has no death record yet).
func local_record() -> Dictionary:
	if services == null or not services.has_game():
		return {}
	var me := services.local_character()
	if me == null:
		return {}
	var rec: Variant = record_of.call(me) if record_of.is_valid() else me.get("last_death")
	return (rec as Dictionary) if rec is Dictionary else {}


## Shows the local crew member's death record if it is a death not shown yet. Returns true when it showed.
func check() -> bool:
	if services == null or not services.has_game():
		return false
	var me := services.local_character()
	if me == null:
		return false
	_me = me.id
	var rec := local_record()
	var n := int(rec.get("count", 0))
	if rec.is_empty() or n <= int(_seen.get(me.id, 0)):
		return false
	_seen[me.id] = n
	_show(rec)
	return true


func _show(rec: Dictionary) -> void:
	record = rec.duplicate(true)
	var title := String(rec.get("title", "")).strip_edges()
	_title.text = title if title != "" else "You were hurt too badly"
	_text.text = StationPanel.words(String(rec.get("text", "")).strip_edges())
	_text.visible = _text.text != ""
	var area := String(rec.get("area", "")).strip_edges()
	_area.text = "Where: %s" % area
	_area.visible = area != ""
	var n := int(rec.get("count", 1))
	_count.text = "This has happened %d times." % n
	_count.visible = n > 1
	_hint.text = "Press %s to close." % _key()
	time_left = SECONDS
	visible = true
	shown.emit(record)


func _key() -> String:
	if not InputMap.has_action(&"interact"):
		return "E"
	var k := PlayerInput.describe(&"interact")
	return k if k != "" else "E"


func _line(parent: Control, node_name: String, variation: StringName) -> Label:
	var l := Label.new()
	l.name = node_name
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if variation != &"":
		l.theme_type_variation = variation
	parent.add_child(l)
	return l


func _on_recovered(id: StringName, _info: Dictionary) -> void:
	var me := services.local_character() if services != null and services.has_game() else null
	if me == null or me.id != id:
		return          # another astronaut came back: not this player's notice
	if not check():
		_waiting = WAIT_FOR_RECORD_SECONDS


## A game was loaded (or the HUD was just built): deaths already in the save count as seen, except one from just
## before the save (then the player has not read it yet).
func _on_loaded(_source: String) -> void:
	_seen.clear()
	_me = &""
	_remember_local(true)


## Notes the local crew member's death count as seen; with `show_recent` a death from the last RECENT_HOURS shows.
func _remember_local(show_recent: bool) -> void:
	if services == null or not services.has_game():
		return
	var me := services.local_character()
	if me == null:
		_me = &""
		return
	_me = me.id
	var rec := local_record()
	if rec.is_empty():
		_seen[me.id] = 0
		return
	var recent := services.state().sim_hours - float(rec.get("at_hours", -1e9)) <= RECENT_HOURS
	if show_recent and recent:
		_seen[me.id] = 0
		check()
	else:
		_seen[me.id] = int(rec.get("count", 0))


func _process(delta: float) -> void:
	if services == null or not services.has_game():
		return
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.25
		var me := services.local_character()
		var now: StringName = me.id if me != null else &""
		if now != _me:
			# A different crew member (crew select, or a new game): their old deaths are not news.
			if visible:
				dismiss()
			_remember_local(false)
		if _waiting > 0.0 and check():
			_waiting = 0.0
	if _waiting > 0.0:
		_waiting = maxf(0.0, _waiting - delta)
	if visible:
		time_left -= delta
		if time_left <= 0.0:
			dismiss()


## E closes the card. The key is not used up, so E still works for whatever you look at.
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"interact") and not event.is_echo():
		dismiss()
