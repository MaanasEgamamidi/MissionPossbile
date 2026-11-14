class_name CrewSelectPanel
extends UiPanel
## Crew (C key, also opened from the menus): one card per crew member with a portrait, the specialty, who plays
## them, health, suit tank and where they are. "Play as …" asks the host with `claim_character`; it is disabled,
## with the reason in words, whenever the host would refuse.

var _cards := {}                # character id -> {"card", "portrait", "status", "health", "suit", "where", "button", "reason"}
var _answer: Label
var _close: Button
var _pending_request := ""


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	name = "CrewSelectPanel"
	theme_type_variation = UiTheme.PANEL
	var box := VBoxContainer.new()
	box.name = "Box"
	add_child(box)
	var header := HBoxContainer.new()
	header.name = "Header"
	box.add_child(header)
	var title := Label.new()
	title.name = "Title"
	title.text = "Crew"
	title.theme_type_variation = UiTheme.TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_close = Button.new()
	_close.name = "Close"
	_close.text = "Close"
	_close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(_close)
	var rule_row := HBoxContainer.new()
	rule_row.name = "Rule"
	var rule := Label.new()
	rule.name = "RuleText"
	rule.text = "You can change crew member at the hub. Crew nobody plays wait there and use no supplies."
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule_row.add_child(rule)
	rule_row.add_child(ExplainButton.make("crew_switching"))
	box.add_child(rule_row)
	_answer = Label.new()
	_answer.name = "Answer"
	_answer.theme_type_variation = UiTheme.MUTED
	_answer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_answer.visible = false
	box.add_child(_answer)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "Cards"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var ids: Array[StringName] = []
	if services.has_game():
		ids = CrewPortrait.sorted_crew_ids(services.state())
	for i in ids.size():
		_build_card(grid, ids[i], i)
	services.events.action_resolved.connect(_on_action_resolved)
	refresh()


func panel_title() -> String:
	return "Crew"


## The first enabled "Play as" button, else Close.
func first_focus() -> Control:
	for id: StringName in sorted_ids():
		var b := _cards[id].button as Button
		if not b.disabled:
			return b
	return _close


## Character ids of the cards, in order.
func sorted_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _cards:
		out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a).naturalnocasecmp_to(String(b)) < 0)
	return out


## The "Play as" button of a card.
func play_button(id: StringName) -> Button:
	return _cards[id].button as Button if _cards.has(id) else null


## The words shown under a card's button: why it is disabled, or "".
func reason_text(id: StringName) -> String:
	return (_cards[id].reason as Label).text if _cards.has(id) else ""


## The status words of a card ("You", "Free — waiting at the hub", "Played by player 2").
func status_text(id: StringName) -> String:
	return (_cards[id].status as Label).text if _cards.has(id) else ""


## Why the host would refuse `claim_character` for `id` right now, in words; "" when it would allow it.
func refusal_reason(id: StringName) -> String:
	var st := services.state()
	var target := st.character(id)
	if target == null:
		return "This crew member is not here."
	var me := services.local_peer()
	var mine := st.character_of_peer(me)
	if target.owner_peer == me:
		return "You are already this crew member."
	if target.owner_peer != 0:
		return "Another player is already this crew member."
	if mine != null:
		if player_count() >= 4:
			return "With four players everyone keeps their own crew member."
		if not services.session.is_at_hub(mine.position):
			return "Walk to the hub to change crew member."
	return ""


## Players in the game: the host's peer list, or the crew being played when that is larger (on a client).
func player_count() -> int:
	return maxi(services.session.peers.size(), services.state().active_characters().size())


func refresh() -> void:
	if services == null or not services.has_game():
		return
	var st := services.state()
	var me := services.local_peer()
	for id: StringName in _cards:
		var c := st.character(id)
		if c == null:
			continue
		var parts: Dictionary = _cards[id]
		var status := parts.status as Label
		if c.owner_peer == me:
			status.text = "You"
			status.theme_type_variation = UiTheme.GOOD
		elif c.owner_peer == 0:
			status.text = "Free — waiting at the hub"
			status.theme_type_variation = UiTheme.MUTED
		else:
			status.text = "Played by player %d" % c.owner_peer
			status.theme_type_variation = UiTheme.WARN
		(parts.health as Label).text = "Health %d %%" % roundi(c.health)
		(parts.suit as Label).text = "Suit %s · tank %d %%" % ["on" if c.suit_on else "off", roundi(c.suit_charge)]
		var where := services.zones.zone_at_world(c.position) if services.zones != null else ""
		(parts.where as Label).text = "Where: %s" % (where if where != "" else "unknown")
		var reason := refusal_reason(id)
		var button := parts.button as Button
		button.disabled = reason != ""
		var label := parts.reason as Label
		label.text = reason
		label.visible = reason != ""
		(parts.portrait as CrewPortrait).set_suit(c.suit_on)


func _build_card(grid: GridContainer, id: StringName, index: int) -> void:
	var c := services.state().character(id)
	var card := PanelContainer.new()
	card.name = "Card_" + String(id)
	card.theme_type_variation = UiTheme.CARD
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(card)
	var row := HBoxContainer.new()
	card.add_child(row)
	var portrait := CrewPortrait.new()
	portrait.name = "Portrait"
	row.add_child(portrait)
	portrait.setup(c, index)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var title := Label.new()
	title.name = "Name"
	title.text = c.display_name
	title.theme_type_variation = UiTheme.HEADING
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(title)
	var specialty := Label.new()
	specialty.name = "Specialty"
	specialty.text = "%s %s specialist" % [CrewPortrait.specialty_symbol(c.specialty), CrewPortrait.specialty_words(c.specialty)]
	specialty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(specialty)
	var parts := {"card": card, "portrait": portrait}
	for key: String in ["status", "health", "suit", "where"]:
		var l := Label.new()
		l.name = key.capitalize()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(l)
		parts[key] = l
	var button := Button.new()
	button.name = "PlayAs"
	button.text = "Play as %s" % c.display_name
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(_claim.bind(id))
	info.add_child(button)
	parts["button"] = button
	var reason := Label.new()
	reason.name = "Reason"
	reason.theme_type_variation = UiTheme.MUTED
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(reason)
	parts["reason"] = reason
	_cards[id] = parts


func _claim(id: StringName) -> void:
	var reason := refusal_reason(id)
	if reason != "":
		_show_answer(reason)
		return
	var result := services.request(&"claim_character", id)
	if result.pending:
		_pending_request = result.request_id
		_show_answer("Asked the host…")
	elif result.ok:
		_show_answer("You are now %s." % services.state().character(id).display_name)
	else:
		_show_answer(result.message)
	refresh()


func _on_action_resolved(result: ActionResult) -> void:
	if _pending_request != "" and result.request_id == _pending_request:
		_pending_request = ""
		_show_answer("The host said yes. You changed crew member." if result.ok else result.message)


func _show_answer(text: String) -> void:
	_answer.text = text
	_answer.visible = text != ""
