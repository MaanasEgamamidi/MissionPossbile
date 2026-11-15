class_name CrewSelectPanel
extends UiPanel
## Crew (C key, also opened from the menus): one card per crew member.
## UI overhaul (2026-11-15): a card is a portrait, the specialist symbol with ONE role word (the HUD's crew corner
## uses the same: "Electrical", "Medical", "Biology", "Geology") and ONE thing at the bottom:
##   * a big "Play" button on a crew member nobody plays (it asks the host with `claim_character`);
##   * a green plate with the tick and "You" on your own card (its edge is green too, and the portrait has the tick);
##   * an amber plate with a padlock and "Player 2" on a card another player has (padlock on the portrait, dimmed).
## "Play" is disabled, with a padlock, whenever the host would refuse; why is ONE short line above the cards ("Walk to
## the hub to swap.") and the whole sentence is the button's tooltip. Everything else (the full specialty, health, suit
## tank, where they are, the rule sentence) is behind "More" (show_details); the science is behind "?".

const Kit = preload("res://scripts/ui/menu_kit.gd")
const PuzzleKit := preload("res://scripts/tasks/puzzles/kit.gd")
const HudKit := preload("res://scripts/ui/hud/hud_kit.gd")
const RULE := "You can change crew member at the hub. Crew nobody plays wait there and use no supplies."
## The one short line above the cards for each reason "Play" is switched off for everybody.
const SHORT_REASONS := {
	"With four players everyone keeps their own crew member.": "Four players: no swapping.",
	"Return to a safe atmosphere before changing crew member.": "Get to safe air first.",
	"Walk to the hub to change crew member.": "Walk to the hub to swap.",
}
const PORTRAIT_PX := Vector2(184, 230)

var _cards := {}                # character id -> {"card", "portrait", "status", "plate", "mark", "details", "health", "suit", "where", "button", "reason"}
var _answer: Label
var _close: Button
var _more: Button
var _hint_row: HBoxContainer
var _hint: Label
var _rule: Label
var _details := false
var _pending_request := ""


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	name = "CrewSelectPanel"
	theme_type_variation = UiTheme.PANEL
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override(&"separation", 10)
	add_child(box)
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override(&"separation", 10)
	box.add_child(header)
	header.add_child(Kit.picture(&"crew", 40.0, &"heading"))
	var title := Label.new()
	title.name = "Title"
	title.text = "Crew"
	title.theme_type_variation = UiTheme.TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_more = Kit.button("More", &"zoom", &"", 24.0, 1.0, 48.0)
	_more.name = "More"
	_more.toggle_mode = true
	_more.tooltip_text = "Health, suit and where everyone is."
	_more.toggled.connect(show_details)
	header.add_child(_more)
	header.add_child(ExplainButton.make("crew_switching"))
	_close = _close_button()
	_close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(_close)
	# why "Play" is off for everybody, in one short line (hidden while you can swap)
	_hint_row = HBoxContainer.new()
	_hint_row.name = "Hint"
	_hint_row.add_theme_constant_override(&"separation", 10)
	_hint_row.add_child(Kit.picture(&"lock", 28.0, &"warn"))
	_hint = Label.new()
	_hint.name = "HintText"
	_hint.theme_type_variation = UiTheme.WARN
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_row.add_child(_hint)
	_hint_row.visible = false
	box.add_child(_hint_row)
	_rule = Label.new()
	_rule.name = "RuleText"
	_rule.text = RULE
	_rule.theme_type_variation = UiTheme.MUTED
	_rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rule.visible = false
	box.add_child(_rule)
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
	scroll.follow_focus = true
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "Cards"
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 12)
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


## The first enabled "Play" button, else Close.
func first_focus() -> Control:
	for id: StringName in sorted_ids():
		var b := _cards[id].button as Button
		if b.visible and not b.disabled:
			return b
	return _close


## Character ids of the cards, in order.
func sorted_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _cards:
		out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a).naturalnocasecmp_to(String(b)) < 0)
	return out


## The "Play" button of a card (hidden and disabled on your own card and on one another player has).
func play_button(id: StringName) -> Button:
	return _cards[id].button as Button if _cards.has(id) else null


## Why a card's button is disabled, in a whole sentence (the button's tooltip; shown under it with "More"), or "".
func reason_text(id: StringName) -> String:
	return (_cards[id].reason as Label).text if _cards.has(id) else ""


## Who has a card, in one or two words: "You", "Free", "Player 2".
func status_text(id: StringName) -> String:
	return (_cards[id].status as Label).text if _cards.has(id) else ""


## The one short line above the cards now (why nobody can be picked), or "".
func hint_text() -> String:
	return _hint.text if _hint_row.visible else ""


## True: every card also shows the full specialty, health, suit tank, the place and why its button is off, and the
## rule sentence shows above the cards. False (how the panel opens): pictures and one word only.
func show_details(on: bool) -> void:
	_details = on
	if _more.button_pressed != on:
		_more.set_pressed_no_signal(on)
	_rule.visible = on
	for id: StringName in _cards:
		(_cards[id].details as Control).visible = on
	refresh()


func details_shown() -> bool:
	return _details


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
		if not services.session.safe_to_switch(mine):
			return "Return to a safe atmosphere before changing crew member."
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
	var p := UiTheme.palette()
	var hint := ""
	var big := roundi(UiTheme.BASE_FONT_SIZE * UiTheme.text_scale() * 1.3)
	for id: StringName in _cards:
		var c := st.character(id)
		if c == null:
			continue
		var parts: Dictionary = _cards[id]
		var status := parts.status as Label
		if status.get_theme_font_size(&"font_size") != big:
			status.add_theme_font_size_override(&"font_size", big)
			(parts.symbol as Label).add_theme_font_size_override(&"font_size", roundi(big * 1.25))
		var mine := c.owner_peer == me
		var taken := c.owner_peer != 0 and not mine
		if mine:
			status.text = "You"
			status.theme_type_variation = UiTheme.GOOD
		elif taken:
			status.text = "Player %d" % c.owner_peer
			status.theme_type_variation = UiTheme.WARN
		else:
			status.text = "Free"
			status.theme_type_variation = UiTheme.MUTED
		(parts.health as Label).text = "Health %d %%" % roundi(c.health)
		(parts.suit as Label).text = "Suit %s · tank %d %%" % ["on" if c.suit_on else "off", roundi(c.suit_charge)]
		var where := services.zones.zone_at_world(c.position) if services.zones != null else ""
		(parts.where as Label).text = "Where: %s" % (where if where != "" else "unknown")
		var reason := refusal_reason(id)
		var button := parts.button as Button
		button.disabled = reason != ""
		button.visible = not mine and not taken
		button.tooltip_text = reason if reason != "" else "Play as %s." % c.display_name
		if button.visible and reason != "" and hint == "":
			hint = String(SHORT_REASONS.get(reason, reason))
		var label := parts.reason as Label
		label.text = reason
		label.visible = reason != "" and button.visible
		var plate := parts.plate as PanelContainer
		plate.visible = mine or taken
		plate.tooltip_text = reason
		var portrait := parts.portrait as CrewPortrait
		portrait.set_suit(c.suit_on)
		# the looks below change only when who has the card (or the contrast setting) changes
		var look := "%s|%s|%s" % ["you" if mine else ("taken" if taken else "free"), reason != "", UiTheme.is_high_contrast()]
		var card := parts.card as PanelContainer
		if String(card.get_meta(&"look", "")) == look:
			continue
		card.set_meta(&"look", look)
		button.icon = Kit.pic(&"lock" if reason != "" else &"play", 30.0, &"text_disabled" if reason != "" else &"primary_text")
		plate.set_meta(&"kind", &"you" if mine else &"taken")
		plate.add_theme_stylebox_override(&"panel", _plate_box(p.good if mine else p.warn))
		(parts.mark as Control).queue_redraw()
		portrait.set_mark(&"you" if mine else (&"taken" if taken else &""))
		portrait.modulate = Color(1, 1, 1, 0.55) if taken else Color.WHITE
		if mine:
			card.add_theme_stylebox_override(&"panel", Kit.card_box(p.good, 3))
		elif card.has_theme_stylebox_override(&"panel"):
			card.remove_theme_stylebox_override(&"panel")
	_hint.text = hint
	_hint_row.visible = hint != ""


func _build_card(grid: GridContainer, id: StringName, index: int) -> void:
	var c := services.state().character(id)
	var card := PanelContainer.new()
	card.name = "Card_" + String(id)
	card.theme_type_variation = UiTheme.CARD
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.tooltip_text = "%s · %s specialist" % [c.display_name, CrewPortrait.specialty_words(c.specialty)]
	grid.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	card.add_child(col)
	var portrait := CrewPortrait.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = PORTRAIT_PX
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(portrait)
	portrait.setup(c, index)
	# the specialist symbol and ONE role word
	var parts_symbol: Label
	var role := HBoxContainer.new()
	role.name = "Role"
	role.alignment = BoxContainer.ALIGNMENT_CENTER
	role.add_theme_constant_override(&"separation", 8)
	col.add_child(role)
	var symbol := Label.new()
	symbol.name = "Symbol"
	symbol.text = CrewPortrait.specialty_symbol(c.specialty)
	symbol.theme_type_variation = UiTheme.HEADING
	symbol.add_theme_font_override(&"font", AstraStyle.symbol_font())
	symbol.add_theme_color_override(&"font_color", CrewPortrait.specialty_color(c.specialty).lightened(0.25))
	role.add_child(symbol)
	parts_symbol = symbol
	var title := Label.new()
	title.name = "Name"
	title.text = GameHud.role_word(c)
	title.theme_type_variation = UiTheme.HEADING
	role.add_child(title)
	var parts := {"card": card, "portrait": portrait, "symbol": parts_symbol}
	# behind "More": the long words and the numbers
	var details := VBoxContainer.new()
	details.name = "Details"
	details.visible = false
	col.add_child(details)
	parts["details"] = details
	var specialty := Label.new()
	specialty.name = "Specialty"
	specialty.text = "%s %s specialist" % [CrewPortrait.specialty_symbol(c.specialty), CrewPortrait.specialty_words(c.specialty)]
	specialty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(specialty)
	for key: String in ["health", "suit", "where"]:
		var l := Label.new()
		l.name = key.capitalize()
		l.theme_type_variation = UiTheme.MUTED
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(l)
		parts[key] = l
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	# ONE thing at the bottom: the "Play" button, or the plate saying who has this crew member
	var button := Kit.button("Play", &"play", UiTheme.PRIMARY_BUTTON, 30.0, 1.3, 64.0)
	button.name = "PlayAs"
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.accessibility_name = "Play as %s" % c.display_name
	button.pressed.connect(_claim.bind(id))
	col.add_child(button)
	parts["button"] = button
	var plate := PanelContainer.new()
	plate.name = "Plate"
	plate.custom_minimum_size.y = 64.0
	plate.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(plate)
	parts["plate"] = plate
	var plate_row := HBoxContainer.new()
	plate_row.alignment = BoxContainer.ALIGNMENT_CENTER
	plate_row.add_theme_constant_override(&"separation", 10)
	plate.add_child(plate_row)
	var mark := Control.new()
	mark.name = "Mark"
	mark.custom_minimum_size = Vector2(36, 36)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.draw.connect(_draw_plate_mark.bind(mark, plate))
	plate_row.add_child(mark)
	parts["mark"] = mark
	var status := Label.new()
	status.name = "Status"
	status.theme_type_variation = UiTheme.GOOD
	plate_row.add_child(status)
	parts["status"] = status
	var reason := Label.new()
	reason.name = "Reason"
	reason.theme_type_variation = UiTheme.MUTED
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(reason)
	parts["reason"] = reason
	_cards[id] = parts


## The tick ("you") or the padlock ("taken") on a card's plate: the same marks as on the portrait.
func _draw_plate_mark(mark: Control, plate: Control) -> void:
	var r := minf(mark.size.x, mark.size.y) * 0.5
	if plate.get_meta(&"kind", &"you") == &"you":
		PuzzleKit.tick(mark, mark.size * 0.5, r)
	else:
		PuzzleKit.lock(mark, mark.size * 0.5 + Vector2(0.0, -r * 0.17), r, true, UiTheme.palette().warn)


## A square close button with a drawn X (Esc closes too).
static func _close_button() -> Button:
	var b := Button.new()
	b.name = "Close"
	b.custom_minimum_size = Vector2(52, 48)
	b.tooltip_text = "Close (Esc)"
	b.accessibility_name = "Close"
	b.draw.connect(func() -> void:
		var s := minf(b.size.x, b.size.y) * 0.4
		HudKit.draw_icon(b, &"close", Rect2((b.size - Vector2(s, s)) * 0.5, Vector2(s, s)), UiTheme.palette().text))
	return b


static func _plate_box(edge: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(edge, 0.14)
	s.border_color = edge
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	s.set_content_margin_all(8)
	return s


func _claim(id: StringName) -> void:
	var reason := refusal_reason(id)
	if reason != "":
		_show_answer(reason)
		return
	var result := services.request(&"claim_character", id)
	if result.pending:
		_pending_request = result.request_id
		_show_answer("One moment…")
	elif result.ok:
		_show_answer("You are now %s." % services.state().character(id).display_name)
	else:
		_show_answer(result.message)
	refresh()
	# the button that was pressed is a plate now: keep the keyboard somewhere visible
	if is_inside_tree() and get_viewport().gui_get_focus_owner() == null:
		first_focus().grab_focus.call_deferred()


func _on_action_resolved(result: ActionResult) -> void:
	if _pending_request != "" and result.request_id == _pending_request:
		_pending_request = ""
		_show_answer("The host said yes. You changed crew member." if result.ok else result.message)
		refresh()


func _show_answer(text: String) -> void:
	_answer.text = text
	_answer.visible = text != ""
