extends PanelContainer
## The colony's build vote on the HUD (upgrade paths plan §1.3, 2026-11-15): one build a day for the whole colony, so
## every player crewmate in radio contact votes from wherever they are. While a vote is open the card shows what is
## proposed and who still has to vote; a crewmate who can vote presses Y (yes) or X (no), or the buttons when the mouse
## is free. Out of radio contact it says "You missed the vote: no radio contact." Hidden when no vote is open.
## Sends build_vote through services.request() (AreaLevelActions); reads state.build (ColonyBuilds). Polls itself, so
## attaching it is enough: new(), add_child, setup(services); the HUD places it.

const ColonyBuilds := preload("res://scripts/upgrades/colony_builds.gd")
const CrewDay := preload("res://scripts/schedule/crew_day.gd")
const POLL_SECONDS := 0.25

var services: GameServices

var _title: Label
var _text: Label
var _yes: Button
var _no: Button
var _buttons: HBoxContainer
var _poll := 0.0
var _busy := false
var _request_id := ""
var _style: StyleBoxFlat


func _init() -> void:
	name = "BuildVoteCard"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_PASS
	_style = AstraStyle.glass(AstraStyle.RADIUS_SM, 12, 8)
	add_theme_stylebox_override(&"panel", _style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 4)
	add_child(col)
	_title = AstraStyle.label("Colony vote", 15, AstraStyle.TEXT, "Title")
	col.add_child(_title)
	_text = AstraStyle.label("", 13, AstraStyle.TEXT_2, "Text")
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(300, 0)
	col.add_child(_text)
	_buttons = HBoxContainer.new()
	col.add_child(_buttons)
	_yes = Button.new()
	_yes.name = "VoteYes"
	_yes.text = "Yes (Y)"
	_yes.focus_mode = Control.FOCUS_NONE
	_yes.pressed.connect(_vote.bind(true))
	_buttons.add_child(_yes)
	_no = Button.new()
	_no.name = "VoteNo"
	_no.text = "No (X)"
	_no.focus_mode = Control.FOCUS_NONE
	_no.pressed.connect(_vote.bind(false))
	_buttons.add_child(_no)


func setup(p_services: GameServices) -> void:
	services = p_services
	refresh()


## The card's words as shown (tests).
func text() -> String:
	return "%s\n%s" % [_title.text, _text.text] if visible else ""


func _process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = POLL_SECONDS
		refresh()


func _can_vote() -> bool:
	if services == null or not services.has_game():
		return false
	return ColonyBuilds.waiting_for(services.state(), services.local_character())


func refresh() -> void:
	if services == null or not services.has_game():
		visible = false
		return
	var st := services.state()
	var me := services.local_character()
	var p := ColonyBuilds.proposal(st)
	if p.is_empty():
		# After the vote: tell a crewmate who was out of radio contact, until the Plan block ends.
		var lv := ColonyBuilds.last_vote(st)
		var missed := me != null and not lv.is_empty() and int(lv.get("sol", 0)) == CrewDay.sol_of(st) \
			and CrewDay.is_block(st, "plan") and (lv.get("missed", []) as Array).has(String(me.id))
		visible = missed
		if missed:
			_title.text = "Colony vote"
			_text.text = "%s %s" % [ColonyBuilds.MISSED_TEXT, String(lv.get("text", ""))]
			AstraStyle.set_color(_text, AstraStyle.WARN)
			_buttons.visible = false
		return
	visible = true
	_title.text = "Colony vote: %s" % ColonyBuilds.proposal_words(p)
	var can := _can_vote()
	_buttons.visible = can
	_yes.disabled = _busy
	_no.disabled = _busy
	if me != null and not ColonyBuilds.in_comms_reach(st, me):
		_text.text = ColonyBuilds.MISSED_TEXT
		AstraStyle.set_color(_text, AstraStyle.WARN)
		return
	AstraStyle.set_color(_text, AstraStyle.TEXT_2)
	var lines := PackedStringArray(["%s asked for it. Every build is permanent." % String(p.get("by_name", "A crewmate"))])
	var waiting := ColonyBuilds.waiting_names(st)
	if not waiting.is_empty():
		lines.append("Waiting for: %s." % ", ".join(waiting))
	if can:
		lines.append("Press Y for yes or X for no.")
	_text.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _busy or not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.physical_keycode != KEY_Y and k.physical_keycode != KEY_X:
		return
	if not _can_vote():
		return
	_vote(k.physical_keycode == KEY_Y)
	get_viewport().set_input_as_handled()


func _vote(yes: bool) -> void:
	if _busy or services == null:
		return
	_busy = true
	var result := services.request(&"build_vote", &"", {"yes": yes})
	if result.pending:
		_request_id = result.request_id
		if not services.events.action_resolved.is_connected(_on_resolved):
			services.events.action_resolved.connect(_on_resolved)
		_text.text = "Sent your vote…"
		return
	_busy = false
	if not result.ok:
		_text.text = "✖ " + result.message
	refresh()


func _on_resolved(result: ActionResult) -> void:
	if result.request_id != _request_id:
		return
	_request_id = ""
	_busy = false
	refresh()
