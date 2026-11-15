class_name GameHud
extends CanvasLayer
## The in-game HUD: pictures first, very few words, at the edges only (UI overhaul 2026-11-15).
##   top-left      a sun or a moon and the sol number; a storm picture with its countdown only while a dust storm is
##                 coming or blowing; then one green "Colony OK" chip, or up to three small warning chips (the picture
##                 of what is low and a mark: triangle = low, octagon = very low)
##   top-right     your crew member: badge, specialist symbol and ONE role word, then three picture bars (heart =
##                 health, runner = body energy, helmet = suit air). A percentage shows only on a bar that is low; what
##                 you carry shows only while you carry something
##   centre        crosshair (a ring appears when E would do something), under it one large key cap and a short verb
##                 phrase ("Use power panel"), and the suit check bar
##   top-centre    "Paused" while the game is paused, and messages: at most two, one short line each (the mission
##                 HUD shows them as its pop-ups instead when it is there); after your own crew member died and the med
##                 bay brought them back, a card says why (scripts/ui/hud/death_notice.gd)
##   bottom        a key hint strip that fades after 30 s (hidden when the mission HUD's dock is there), network status
##                 on the left; subtitles show above the strip
## Every picture that stands in for words carries those words as its tooltip and accessible name (HudKit.say); the
## full sentences stay available to code and tests (cue_text(), shown_readings(), current_messages()).
## It only reads state and listens to events; it never changes anything. It refreshes 4 times a second.

## Most urgent readings shown at once.
const MAX_READINGS := 3
## Messages on screen at once; more wait their turn.
const MAX_MESSAGES := 2
## Seconds of play before the key hint strip fades away.
const HINT_SECONDS := 30.0
const REFRESH_SECONDS := 0.25
## Space between the HUD and the edge of the screen, in screen units.
const EDGE := 24
## Suit tank share (percent) below which the tank counts as low / very low while the suit is worn.
const SUIT_WARN := 30.0
const SUIT_URGENT := 10.0
## Health and body energy (percent) below which the bar counts as low / very low and shows its number.
const HEALTH_WARN := 60.0
const HEALTH_URGENT := 30.0
const BODY_ENERGY_WARN := 25.0

## Plain names of station kinds, as used in "[E] Use …". An empty name gives a plain "[E] Use" (owner 2026-11-14:
## nothing in the world says "fix" or "broken / damaged"; salvage donors just say "Use").
const STATION_NAMES := {
	"suits": "suit rack", "power": "power panel", "computer": "colony computer", "comms": "comms console",
	"food": "greenhouse console", "board": "transceiver board", "lifesupport": "life support console",
	"heal": "med station", "survivor": "patient", "solar": "sun tracker",
	"scout_bay": "scout bay", "ore_deposit": "ore deposit", "salvage": "", "sample_site": "sample site",
}
## The short phrase shown beside the key cap for a long cue (cue_text() keeps the full words).
const SHORT_CUES := {
	"Suit check: put the suit on": "Put suit on", "Suit check: take the suit off": "Take suit off",
	"Check on the patient": "Check patient", "Pick up the tape": "Pick up tape",
	"Hold ladder; W/S climb, E or Space release": "Grab ladder",
}
## The picture of each reading on the top-left warning chips, and the short word the cabin air ones need.
const READING_ICONS := {&"battery_kwh": &"power", &"oxygen_kg": &"air", &"water_l": &"water", &"food_meals": &"food",
	&"cabin_o2": &"air", &"cabin_co2": &"air", &"suit_tank": &"helmet"}
const READING_WORDS := {&"cabin_o2": "Room", &"cabin_co2": "CO₂"}
## Seconds a colony system alert stays in the message line.
const ALERT_SECONDS := 6.0
## Upgrade update (2026-11-14): the "why you were brought back" card, top centre after a respawn in the med bay.
const DeathNoticeScript := preload("res://scripts/ui/hud/death_notice.gd")
## Broken parts (2026-11-14): the prompts of the ten broken spots (scripts/tasks/broken_part_presenter.gd).
const BrokenParts := preload("res://scripts/tasks/broken_part_presenter.gd")
## Tutorial mode (2026-11-14): stations other than tapes and broken spots show no "[E]" prompt.
const TutorialLock := preload("res://scripts/session/tutorial_lock.gd")
## UI overhaul (2026-11-15): pictograms, level bars and self-sizing labels.
const HudKit := preload("res://scripts/ui/hud/hud_kit.gd")

var services: GameServices
## The death notice card (scripts/ui/hud/death_notice.gd).
var death_notice: PanelContainer

var _root: Control
## Sun or moon, then "Sol 1".
var _clock_icon: HudKit.Icon
var _time: Label
## The storm picture and its countdown ("in 6 h"), shown only while a dust storm is coming or blowing.
var _hazard_row: HBoxContainer
var _hazard_icon: HudKit.Icon
var _hazard: Label
## One warning chip per low reading: the picture, a short word where the picture is not enough, and a mark.
var _reading_rows: Array[PanelContainer] = []
## The full words of the chips now shown ("⚡ Colony electricity 12 % ! Low"): shown_readings() and the tooltips.
var _reading_texts := PackedStringArray()
var _ok_chip: PanelContainer
var _crew_badge: CrewPortrait
## ONE role word ("Electrical").
var _crew_name: Label
## The specialty symbol before the role word, in the crew member's accent colour (CrewLooks).
var _crew_specialty_icon: Label
var _who_row: HBoxContainer
## The three vitals, each {"row", "icon", "bar", "text", "mark"} (see _vital_row()).
var _health: Dictionary = {}
var _stamina: Dictionary = {}
var _suit: Dictionary = {}
var _held_row: HBoxContainer
var _held_line: Label
var _no_crew: HBoxContainer
var _no_crew_key: Label
var _crew_box: VBoxContainer
var _crosshair: Crosshair
var _cue: Label
var _cue_key: Label
var _cue_panel: PanelContainer
## Extra keys under the cue while looking at a ladder ("W S climb").
var _cue_extra: PanelContainer
var _cue_full := ""
var _corner_left: PanelContainer
var _corner_right: PanelContainer
var _centre_margin: MarginContainer
## The message lines: MAX_MESSAGES rows, one short line each, oldest first. [{"row", "label"}]
var _message_rows: Array[Dictionary] = []
var _message_panel: PanelContainer
var _progress_box: Control
var _progress: HudKit.Bar
var _hint_panel: PanelContainer
var _hint: Label
var _status_panel: PanelContainer
var _status: Label
var _banner_panel: PanelContainer
var _banner: Label

var _target := {}
var _held: StringName = &""
var _showing: Array[Dictionary] = []          # [{"text", "left"}]
var _waiting: Array[Dictionary] = []          # [{"text", "seconds"}]
var _refresh_left := 0.0
var _played := 0.0
var _hint_fading := false
var _badge_for: StringName = &""
## The newest colony system alert shown (events.system_alert), or "".
var last_alert_text := ""
## Scout update: when set (by the mission-control HUD), colony alerts go to its pop-ups instead of the message line:
## func(alert_id: StringName, level: StringName, text: String).
var alert_sink := Callable()
## UI overhaul: when set (by the mission-control HUD), messages show as its pop-ups, so there is one place to look.
## The queue here still runs (current_messages(), waiting_messages()); only the top-centre lines stay hidden.
## func(text: String, seconds: float).
var message_sink := Callable()
## Screen units at the top kept free for the vitals bar; messages then show just under it.
var top_reserved := 0.0
# interim power menu, kept so game_main works until UiRoot hosts station surfaces
var _menu: Control
var _menu_station: StringName = &""


func setup(p_services: GameServices) -> void:
	services = p_services
	layer = 10
	if not InputMap.has_action(&"interact"):
		PlayerInput.ensure_actions()
	_build()
	services.events.pause_changed.connect(func(_paused: bool) -> void: refresh())
	services.events.action_resolved.connect(_on_action_resolved)
	services.events.system_alert.connect(_on_system_alert)
	death_notice.setup(services)
	refresh()


## The full-screen Control that holds the whole HUD (for layout checks).
func root_control() -> Control:
	return _root


## What the player is looking at, as returned by PlayerController.aimed_target():
## {"kind": "station" / "item" / "", "id", "node"}.
func set_target(target: Dictionary) -> void:
	var same := String(target.get("kind", "")) == String(_target.get("kind", "")) and String(target.get("id", "")) == String(_target.get("id", ""))
	_target = target
	if not same:
		_update_cue()


## What is in the hands now, or &"" for nothing.
func set_held(item_id: StringName) -> void:
	_held = item_id
	_update_cue()
	_refresh_crew()


## Shows a message for `seconds`. Messages queue: up to MAX_MESSAGES show at once, the rest wait.
## The same text twice in a row is shown once (its time is extended). The screen shows one short line of it
## (HudKit.short_line); current_messages() and the Power drawer's message list keep the full text.
func show_message(text: String, seconds := 3.0) -> void:
	if text.strip_edges() == "":
		return
	for m: Dictionary in _showing:
		if m.text == text:
			m.left = maxf(float(m.left), seconds)
			return
	for m: Dictionary in _waiting:
		if m.text == text:
			m.seconds = maxf(float(m.seconds), seconds)
			return
	if _showing.size() < MAX_MESSAGES:
		_showing.append({"text": text, "left": seconds})
	else:
		_waiting.append({"text": text, "seconds": seconds})
	_note_message(text, seconds)
	_update_messages()


## Shows the newest colony system alert at once: if the message line is full, the oldest message on screen makes room.
func show_alert(text: String, seconds := ALERT_SECONDS) -> void:
	var t := text.strip_edges().replace("CO2", "CO₂")
	if t == "":
		return
	last_alert_text = t
	for m: Dictionary in _showing:
		if m.text == t:
			m.left = maxf(float(m.left), seconds)
			return
	for i in range(_waiting.size() - 1, -1, -1):
		if _waiting[i].text == t:
			_waiting.remove_at(i)
	if _showing.size() >= MAX_MESSAGES:
		_showing.pop_front()
	_showing.append({"text": t, "left": seconds})
	_note_message(t, seconds)
	_update_messages()


## A new message: it goes to the mission HUD's pop-ups when that is there, else into the message list the Power
## drawer shows in full (ToastStack.recent()).
func _note_message(text: String, seconds: float) -> void:
	if message_sink.is_valid():
		message_sink.call(text, seconds)
	else:
		ToastStack.remember(text, &"info")


## Messages on screen now, oldest first (full text).
func current_messages() -> PackedStringArray:
	var out := PackedStringArray()
	for m: Dictionary in _showing:
		out.append(String(m.text))
	return out


## Messages waiting for a free line.
func waiting_messages() -> PackedStringArray:
	var out := PackedStringArray()
	for m: Dictionary in _waiting:
		out.append(String(m.text))
	return out


## The short lines the top-centre message box shows now (empty while the mission HUD shows messages as pop-ups).
func shown_message_lines() -> PackedStringArray:
	var out := PackedStringArray()
	if _message_panel.visible:
		for r: Dictionary in _message_rows:
			if (r.row as Control).visible:
				out.append((r.label as Label).text)
	return out


## Shows or hides the whole HUD (for example for screenshots or full-screen menus).
func set_visible_hud(on: bool) -> void:
	visible = on
	if _root != null:
		_root.visible = on


## One line of network or session status ("Connected to the host"); empty hides it.
func set_status(text: String) -> void:
	_status.text = text
	_status_panel.visible = text != ""


## The interaction cue under the crosshair in full words ("[E] Use power panel"), or "". The screen shows the key
## cap and shown_cue().
func cue_text() -> String:
	return _cue_full


## The short phrase now shown beside the key cap ("Use power panel", "Put suit on"), or "".
func shown_cue() -> String:
	return _cue.text if _cue_panel.visible else ""


## The short phrase the screen shows for a cue's full words (without the key).
static func short_cue(body: String) -> String:
	return String(SHORT_CUES.get(body, body))


## Up to MAX_READINGS readings that are low right now, most urgent first.
## Each: {"key", "symbol", "name", "value" (with unit), "word" ("Low"), "level" (&"warn"/&"urgent"), "share"}.
static func low_readings(p_services: GameServices) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if p_services == null or not p_services.has_game():
		return out
	var st := p_services.state()
	for s: Dictionary in ColonySummaryPanel.STOCKS:
		var key: StringName = s.key
		var lvl := ColonySummaryPanel.level_of(p_services, key)
		if lvl == &"ok":
			continue
		var cap := float(st.capacities.get(key, 0.0))
		var share := st.store(key) / cap if cap > 0.0 else 0.0
		var value := ""
		var label := ColonySummaryPanel.short_name(s)
		if key == &"battery_kwh":
			label = "Colony electricity"
			value = "%d %%" % roundi(share * 100.0)
		else:
			value = ColonySummaryPanel.amount_with_unit(key, st.store(key))
		var word := ColonySummaryPanel.level_word(lvl)
		if key == &"battery_kwh" and st.power_deficit and st.store(key) <= 1e-6:
			word = "Power short"
		out.append({"key": key, "symbol": s.symbol, "name": label, "value": value, "word": word, "level": lvl, "share": share})
	# cabin air: low oxygen or high carbon dioxide in the rooms (not the oxygen reserve in the tanks)
	var b := p_services.balance
	var kpa := StationPanel.cabin_kpa(st, b)
	var o2_lvl := StationPanel.o2_level(float(kpa.o2), b)
	if o2_lvl != &"ok":
		out.append({"key": &"cabin_o2", "symbol": "◎", "name": "Cabin oxygen", "value": "%s kPa" % StationPanel.num(float(kpa.o2), 1),
			"word": StationPanel.o2_word(o2_lvl), "level": o2_lvl, "share": float(kpa.o2) / maxf(b.o2_setpoint_kpa, 1e-6)})
	var co2_lvl := StationPanel.co2_level(float(kpa.co2), b)
	if co2_lvl != &"ok":
		out.append({"key": &"cabin_co2", "symbol": "◎", "name": "Cabin CO₂", "value": "%s kPa" % StationPanel.num(float(kpa.co2), 2),
			"word": StationPanel.co2_word(co2_lvl), "level": co2_lvl, "share": clampf(b.co2_warn_kpa / maxf(float(kpa.co2), 1e-6) * 0.5, 0.0, 1.0)})
	var me := p_services.local_character()
	if me != null and me.suit_on and me.suit_charge < SUIT_WARN:
		var lvl: StringName = &"urgent" if me.suit_charge < SUIT_URGENT else &"warn"
		out.append({"key": &"suit_tank", "symbol": "⛑", "name": "Suit tank", "value": "%d %%" % roundi(me.suit_charge),
			"word": ColonySummaryPanel.level_word(lvl), "level": lvl, "share": me.suit_charge / 100.0})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.level != b.level:
			return a.level == &"urgent"
		return float(a.share) < float(b.share))
	if out.size() > MAX_READINGS:
		out.resize(MAX_READINGS)
	return out


## The full words of one low reading: "⚡ Colony electricity 12 % ! Low".
static func reading_words(r: Dictionary) -> String:
	return "%s %s %s %s %s" % [String(r.symbol), String(r.name), String(r.value), "✖" if r.level == &"urgent" else "!", String(r.word)]


## The readings now shown as warning chips in the top-left, in full words: "⚡ Colony electricity 12 % ! Low"
## (empty when "Colony OK" is shown). Each chip shows the picture and a mark; these words are its tooltip.
func shown_readings() -> PackedStringArray:
	return _reading_texts.duplicate()


## True while the one quiet "Colony OK" chip is shown.
func colony_ok_shown() -> bool:
	return _ok_chip.visible


# ------------------------------------------------------------------ interim power menu (game_main uses these)

## True while the interim station menu is open.
func is_menu_open() -> bool:
	return _menu != null


## Closes the interim station menu.
func close_menu() -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null


## INTERIM: opens the power panel inside the HUD until UiRoot hosts station surfaces. Uses the station panel from
## StationPanels when it exists, otherwise a plain list of switches; every switch is its own `set_zone_power` request.
func open_power_panel(station_id: StringName) -> void:
	close_menu()
	_menu_station = station_id
	var holder := CenterContainer.new()
	holder.name = "StationMenu"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)
	_menu = holder
	var panel := StationPanels.for_station(station_id, services)
	if panel != null:
		if panel.services == null:
			panel.setup(services)
		panel.close_requested.connect(close_menu)
		holder.add_child(panel)
		return
	var fallback := UiPanel.new()
	fallback.name = "PowerPanel"
	holder.add_child(fallback)
	fallback.setup(services)
	fallback.theme_type_variation = UiTheme.PANEL
	var box := VBoxContainer.new()
	fallback.add_child(box)
	var title := Label.new()
	title.text = "Power panel"
	title.theme_type_variation = UiTheme.TITLE
	box.add_child(title)
	var note := Label.new()
	note.text = "Switch rooms off to save the battery. Press %s to close." % _key(&"back", "Esc")
	note.theme_type_variation = UiTheme.MUTED
	box.add_child(note)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	var st := services.state()
	var names: Array = st.zones.keys()
	names.sort()
	for zone: String in names:
		var button := CheckButton.new()
		button.text = "%s   %s kW" % [zone, ColonySummaryPanel.num(services.balance.load_of_zone(zone))]
		button.button_pressed = st.is_zone_powered(zone)
		button.toggled.connect(_on_zone_toggled.bind(zone, button))
		grid.add_child(button)


func _on_zone_toggled(on: bool, zone: String, button: CheckButton) -> void:
	var result := services.request(&"set_zone_power", _menu_station, {"zone": zone, "on": on})
	if not result.ok and not result.pending:
		button.set_pressed_no_signal(not on)
		show_message(result.message)


# ------------------------------------------------------------------ building

func _build() -> void:
	_root = Control.new()
	_root.name = "HudRoot"
	_root.theme = UiTheme.get_theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, EDGE)
	_root.add_child(margin)
	var column := VBoxContainer.new()
	column.name = "Column"
	margin.add_child(column)

	# ---- top row: the colony corner on the left, your crew member on the right
	var top := HBoxContainer.new()
	top.name = "Top"
	top.add_theme_constant_override(&"separation", 20)
	column.add_child(top)
	_build_colony_corner(top)
	var top_space := Control.new()
	top_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(top_space)
	_build_crew_corner(top)

	# ---- top centre, on its own layer so it can never push the corners apart: the pause banner, then messages.
	# Messages sit here, away from the subtitles and key hints at the bottom, so nothing ever overlaps.
	_centre_margin = MarginContainer.new()
	_centre_margin.name = "TopCentreMargin"
	_centre_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_centre_margin.add_theme_constant_override(side, EDGE)
	_root.add_child(_centre_margin)
	var centre_column := VBoxContainer.new()
	centre_column.name = "TopCentre"
	_centre_margin.add_child(centre_column)
	_banner_panel = HudKit.Card.new("Paused", 16, 22, 8, true)
	_banner_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	centre_column.add_child(_banner_panel)
	_banner = HudKit.Txt.new("⏸ Paused", 30.0, AstraStyle.TEXT, "Banner", true)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_panel.add_child(_banner)
	HudKit.say(_banner_panel, "Paused. The colony clock is stopped.")
	_banner_panel.visible = false
	_message_panel = HudKit.Card.new("Messages", 14, 14, 8, true)
	_message_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	centre_column.add_child(_message_panel)
	var message_box := VBoxContainer.new()
	message_box.name = "Lines"
	message_box.add_theme_constant_override(&"separation", 6)
	_message_panel.add_child(message_box)
	for i in MAX_MESSAGES:
		var row := HBoxContainer.new()
		row.name = "Line%d" % i
		row.add_theme_constant_override(&"separation", 10)
		message_box.add_child(row)
		var icon := HudKit.Icon.new(&"info", AstraStyle.C_O2, 22.0, "Symbol")
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(icon)
		var line := HudKit.Txt.new("", 20.0, AstraStyle.TEXT, "Message")
		row.add_child(line)
		row.visible = false
		_message_rows.append({"row": row, "label": line})
	_message_panel.visible = false
	# Upgrade update: why you died, after the med bay brought you back. Its own place at the top centre; messages
	# move under it while it shows.
	death_notice = DeathNoticeScript.new()
	_root.add_child(death_notice)
	death_notice.connect(&"shown", func(_record: Dictionary) -> void: _place_messages())
	death_notice.connect(&"dismissed", _place_messages)

	# ---- bottom edge: session status on the left, the key hint strip in the middle. Subtitles (UiRoot) show above it.
	var bottom_margin := MarginContainer.new()
	bottom_margin.name = "BottomMargin"
	bottom_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bottom_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		bottom_margin.add_theme_constant_override(side, EDGE)
	_root.add_child(bottom_margin)
	var bottom_column := VBoxContainer.new()
	bottom_column.name = "BottomColumn"
	bottom_column.alignment = BoxContainer.ALIGNMENT_END
	bottom_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_margin.add_child(bottom_column)
	var bottom := HBoxContainer.new()
	bottom.name = "Bottom"
	bottom_column.add_child(bottom)
	var status_holder := HBoxContainer.new()
	status_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(status_holder)
	_status_panel = _hud_box(status_holder, "Status")
	_status_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	_status = Label.new()
	_status.name = "StatusText"
	_status_panel.add_child(_status)
	_status_panel.visible = false
	var hint_holder := HBoxContainer.new()
	hint_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	hint_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_holder.size_flags_stretch_ratio = 2.0
	bottom.add_child(hint_holder)
	_hint_panel = _hud_box(hint_holder, "Hints")
	_hint_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	_hint = Label.new()
	_hint.name = "HintText"
	_hint.theme_type_variation = UiTheme.MUTED
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.text = _hint_line()
	_hint_panel.add_child(_hint)
	var right_space := Control.new()
	right_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(right_space)

	# ---- crosshair on the exact centre of the screen; what E does and the suit check hang just below it
	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)
	_crosshair = Crosshair.new()
	_crosshair.name = "Crosshair"
	centre.add_child(_crosshair)
	var below := VBoxContainer.new()
	below.name = "Aim"
	below.anchor_left = 0.0
	below.anchor_right = 1.0
	below.anchor_top = 0.5
	below.anchor_bottom = 1.0
	below.offset_top = 40.0
	below.add_theme_constant_override(&"separation", 10)
	_root.add_child(below)
	# One large key cap and a short verb phrase: readable from the couch.
	_cue_panel = HudKit.Card.new("CuePanel", 18, 14, 8, true)
	_cue_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	below.add_child(_cue_panel)
	var cue_row := HBoxContainer.new()
	cue_row.add_theme_constant_override(&"separation", 14)
	_cue_panel.add_child(cue_row)
	var cap := HudKit.key_cap("E", 30.0, "CueKey")
	_cue_key = cap.get_node("KeyText") as Label
	cue_row.add_child(cap)
	_cue = HudKit.Txt.new("", 30.0, AstraStyle.TEXT, "Cue", true)
	cue_row.add_child(_cue)
	_cue_panel.visible = false
	_cue_extra = HudKit.Card.new("CueExtra", 12, 12, 5, true)
	_cue_extra.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	below.add_child(_cue_extra)
	var extra_row := HBoxContainer.new()
	extra_row.add_theme_constant_override(&"separation", 8)
	_cue_extra.add_child(extra_row)
	extra_row.add_child(HudKit.key_cap("W", 18.0, "Up"))
	extra_row.add_child(HudKit.key_cap("S", 18.0, "Down"))
	extra_row.add_child(HudKit.Txt.new("climb", 20.0, AstraStyle.TEXT_2, "Word"))
	HudKit.say(_cue_extra, "W and S climb the ladder. E or Space lets go.")
	_cue_extra.visible = false
	var progress_panel := HudKit.Card.new("SuitCheck", 16, 16, 10, true)
	progress_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	below.add_child(progress_panel)
	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override(&"separation", 12)
	progress_panel.add_child(progress_row)
	progress_row.add_child(HudKit.Icon.new(&"helmet", AstraStyle.C_O2, 30.0, "Symbol"))
	var progress_inner := VBoxContainer.new()
	progress_inner.add_theme_constant_override(&"separation", 4)
	progress_row.add_child(progress_inner)
	progress_inner.add_child(HudKit.Txt.new("Suit check", 20.0, AstraStyle.TEXT, "Word"))
	_progress = HudKit.Bar.new(AstraStyle.C_O2, Vector2(300, 16), "Progress")
	progress_inner.add_child(_progress)
	_progress_box = progress_panel          # the whole box shows and hides with the check
	_progress_box.visible = false

	_ignore_mouse(_root)
	_root.theme_changed.connect(_fit_all)
	_fit_all()


## Top left: sun or moon and the sol, a storm countdown when one is coming, then "Colony OK" or the warning chips.
func _build_colony_corner(top: HBoxContainer) -> void:
	var left := HudKit.Card.new("TopLeft", 16, 14, 10)
	top.add_child(left)
	_corner_left = left
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override(&"separation", 8)
	left.add_child(left_box)
	var clock := HBoxContainer.new()
	clock.name = "Clock"
	clock.add_theme_constant_override(&"separation", 10)
	left_box.add_child(clock)
	_clock_icon = HudKit.Icon.new(&"sun", AstraStyle.C_POWER, 30.0, "DayNight")
	clock.add_child(_clock_icon)
	_time = HudKit.Txt.new("Sol 1", 26.0, AstraStyle.TEXT, "Time", true)
	clock.add_child(_time)
	# Scout update: a dust storm on its way or blowing: the storm picture and "in 6 h" / "6 h left".
	_hazard_row = HBoxContainer.new()
	_hazard_row.name = "Hazard"
	_hazard_row.add_theme_constant_override(&"separation", 6)
	clock.add_child(_hazard_row)
	var gap := Control.new()
	gap.custom_minimum_size.x = 8
	_hazard_row.add_child(gap)
	_hazard_icon = HudKit.Icon.new(&"storm", AstraStyle.WARN, 28.0, "Symbol")
	_hazard_row.add_child(_hazard_icon)
	_hazard = HudKit.Txt.new("", 22.0, AstraStyle.WARN, "Countdown", true)
	_hazard_row.add_child(_hazard)
	_hazard_row.visible = false
	var chips := HBoxContainer.new()
	chips.name = "Readings"
	chips.add_theme_constant_override(&"separation", 6)
	left_box.add_child(chips)
	for i in MAX_READINGS:
		var chip := HudKit.Card.new("Reading%d" % i, 12, 8, 4, true)
		chip.tone = &"warn"
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 5)
		chip.add_child(row)
		row.add_child(HudKit.Icon.new(&"power", AstraStyle.TEXT, 24.0, "Symbol"))
		row.add_child(HudKit.Txt.new("", 18.0, AstraStyle.TEXT, "Value"))
		row.add_child(HudKit.Icon.new(&"warn", AstraStyle.WARN, 20.0, "Mark"))
		chip.visible = false
		chips.add_child(chip)
		_reading_rows.append(chip)
	_ok_chip = HudKit.Card.new("ColonyOk", 12, 10, 4, true)
	_ok_chip.tone = &"good"
	_ok_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var ok_row := HBoxContainer.new()
	ok_row.add_theme_constant_override(&"separation", 6)
	_ok_chip.add_child(ok_row)
	ok_row.add_child(HudKit.Icon.new(&"check", AstraStyle.GOOD, 20.0, "Symbol"))
	ok_row.add_child(HudKit.Txt.new("Colony OK", 20.0, AstraStyle.GOOD, "Word"))
	HudKit.say(_ok_chip, "Colony OK: nothing is low.")
	chips.add_child(_ok_chip)


## Top right: who you are (badge, specialist symbol, one role word) and three picture bars.
func _build_crew_corner(top: HBoxContainer) -> void:
	var right := HudKit.Card.new("TopRight", 16, 14, 10)
	top.add_child(right)
	_corner_right = right
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var right_box := VBoxContainer.new()
	right.add_child(right_box)
	_crew_box = VBoxContainer.new()
	_crew_box.name = "Crew"
	_crew_box.add_theme_constant_override(&"separation", 7)
	right_box.add_child(_crew_box)
	_who_row = HBoxContainer.new()
	_who_row.name = "Who"
	_who_row.add_theme_constant_override(&"separation", 10)
	_crew_box.add_child(_who_row)
	_crew_badge = CrewPortrait.new()
	_crew_badge.name = "Badge"
	_crew_badge.prefer_rig = false
	_crew_badge.custom_minimum_size = Vector2(44, 44)
	_crew_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_who_row.add_child(_crew_badge)
	_crew_specialty_icon = HudKit.Txt.new("", 26.0, AstraStyle.TEXT, "SpecialtyIcon")
	# A monochrome symbol font: the default fallback draws ⚡ and ⛏ as colour emoji, which ignore the accent colour.
	_crew_specialty_icon.add_theme_font_override(&"font", AstraStyle.symbol_font())
	_who_row.add_child(_crew_specialty_icon)
	_crew_name = HudKit.Txt.new("", 24.0, AstraStyle.TEXT, "Name", true)
	_who_row.add_child(_crew_name)
	_health = _vital_row(_crew_box, "Health", &"heart", AstraStyle.GOOD)
	_stamina = _vital_row(_crew_box, "BodyEnergy", &"run", AstraStyle.ACCENT)
	_suit = _vital_row(_crew_box, "SuitTank", &"helmet", AstraStyle.C_O2)
	_held_row = HBoxContainer.new()
	_held_row.name = "Held"
	_held_row.add_theme_constant_override(&"separation", 8)
	_crew_box.add_child(_held_row)
	_held_row.add_child(HudKit.Icon.new(&"cargo", AstraStyle.C_PARTS, 26.0, "Symbol"))
	_held_line = HudKit.Txt.new("", 20.0, AstraStyle.TEXT, "HeldText")
	_held_row.add_child(_held_line)
	_held_row.visible = false
	_no_crew = HBoxContainer.new()
	_no_crew.name = "NoCrew"
	_no_crew.add_theme_constant_override(&"separation", 10)
	right_box.add_child(_no_crew)
	_no_crew.add_child(HudKit.Icon.new(&"crew", AstraStyle.TEXT_2, 30.0, "Symbol"))
	var crew_cap := HudKit.key_cap("C", 22.0, "CrewKey")
	_no_crew_key = crew_cap.get_node("KeyText") as Label
	_no_crew.add_child(crew_cap)
	_no_crew.add_child(HudKit.Txt.new("Pick crew", 22.0, AstraStyle.TEXT, "Word"))


## One vital: a picture, a level bar, and a percentage with a mark that show only while it is low.
func _vital_row(parent: Control, row_name: String, kind: StringName, color: Color) -> Dictionary:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override(&"separation", 8)
	parent.add_child(row)
	var icon := HudKit.Icon.new(kind, color, 26.0, "Symbol")
	row.add_child(icon)
	var bar := HudKit.Bar.new(color, Vector2(150, 16), row_name + "Bar")
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	var text := HudKit.Txt.new("", 20.0, AstraStyle.TEXT, row_name + "Text", true)
	text.visible = false
	row.add_child(text)
	var mark := HudKit.Icon.new(&"warn", AstraStyle.WARN, 20.0, "Mark")
	mark.visible = false
	row.add_child(mark)
	return {"row": row, "icon": icon, "bar": bar, "text": text, "mark": mark, "color": color}


## Fills one vital row: the bar always, the number and the mark only while `level` is not &"ok".
func _show_vital(v: Dictionary, percent: float, level: StringName, words: String) -> void:
	var c: Color = v.color if level == &"ok" else HudKit.level_color(level)
	(v.bar as HudKit.Bar).share = percent / 100.0
	(v.bar as HudKit.Bar).color = c
	(v.icon as HudKit.Icon).color = c
	var text := v.text as Label
	text.visible = level != &"ok"
	text.text = "%d %%" % roundi(percent)
	(text as HudKit.Txt).tint(c)
	var mark := v.mark as HudKit.Icon
	mark.visible = level != &"ok"
	mark.kind = StringName(HudKit.LEVEL_MARK.get(level, &"warn"))
	mark.color = c
	HudKit.say(v.row as Control, words)


func _hud_box(parent: Control, box_name: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = box_name
	p.theme_type_variation = UiTheme.HUD_PANEL
	parent.add_child(p)
	return p


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(node as Control).focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_ignore_mouse(child)


# ------------------------------------------------------------------ updating

func _process(delta: float) -> void:
	if services == null or not services.has_game():
		return
	_tick_messages(delta)
	if not services.session.paused:
		_played += delta
	if _played >= HINT_SECONDS and _hint_panel.visible and not _hint_fading:
		_hint_fading = true
		var tween := create_tween()
		tween.tween_property(_hint_panel, "modulate:a", 0.0, 1.5)
		tween.tween_callback(func() -> void: _hint_panel.visible = false)
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_SECONDS
		refresh()


func _tick_messages(delta: float) -> void:
	if _showing.is_empty():
		return
	var changed := false
	for m: Dictionary in _showing:
		m.left = float(m.left) - delta
	for i in range(_showing.size() - 1, -1, -1):
		if float(_showing[i].left) <= 0.0:
			_showing.remove_at(i)
			changed = true
	while _showing.size() < MAX_MESSAGES and not _waiting.is_empty():
		var next: Dictionary = _waiting.pop_front()
		_showing.append({"text": next.text, "left": next.seconds})
		changed = true
	if changed:
		_update_messages()


func _update_messages() -> void:
	for i in _message_rows.size():
		var r: Dictionary = _message_rows[i]
		var on := i < _showing.size()
		(r.row as Control).visible = on
		if on:
			var full := String(_showing[i].text)
			(r.label as Label).text = HudKit.short_line(full)
			HudKit.say(r.row as Control, full)
	# With the mission HUD the same messages are its pop-ups: one place to look.
	_message_panel.visible = not _showing.is_empty() and not message_sink.is_valid()
	_place_messages()


## Re-reads state and updates everything shown. Runs 4 times a second by itself.
func refresh() -> void:
	if services == null or not services.has_game():
		return
	var c := services.clock()
	var hour := c.hour_of_sol()
	var day := c.is_daylight()
	_clock_icon.kind = &"sun" if day else &"moon"
	_clock_icon.color = AstraStyle.C_POWER if day else AstraStyle.TEXT_2
	_time.text = "Sol %d" % (c.sol_index + 1)
	HudKit.say(_time.get_parent() as Control, "Sol %d · %02d:%02d · %s" % [c.sol_index + 1, int(hour), int(fmod(hour, 1.0) * 60.0), "day" if day else "night"])
	var low := low_readings(services)
	_reading_texts = PackedStringArray()
	for i in _reading_rows.size():
		var chip := _reading_rows[i]
		chip.visible = i < low.size()
		if not chip.visible:
			continue
		var r: Dictionary = low[i]
		var urgent: bool = r.level == &"urgent"
		var col := HudKit.level_color(r.level)
		(chip as HudKit.Card).tone = &"danger" if urgent else &"warn"
		var row := chip.get_child(0)
		var symbol := row.get_node("Symbol") as HudKit.Icon
		symbol.kind = StringName(READING_ICONS.get(r.key, &"dot"))
		symbol.color = col
		var value := row.get_node("Value") as Label
		value.text = String(READING_WORDS.get(r.key, ""))
		value.visible = value.text != ""
		var mark := row.get_node("Mark") as HudKit.Icon
		mark.kind = &"danger" if urgent else &"warn"
		mark.color = col
		var words := reading_words(r)
		_reading_texts.append(words)
		HudKit.say(chip, words)
	_ok_chip.visible = low.is_empty()
	var storm := StormOutlook.now(services.state())
	var warned := String(storm.phase) == "warned"
	_hazard_row.visible = String(storm.phase) != "calm"
	if _hazard_row.visible:
		var hc := AstraStyle.WARN if warned else AstraStyle.DANGER
		_hazard_icon.color = hc
		_hazard.text = storm_words(storm)
		(_hazard as HudKit.Txt).tint(hc)
		HudKit.say(_hazard_row, String(storm.text))
	_refresh_crew()
	_banner_panel.visible = services.session.paused
	var me := services.local_character()
	var p := services.session.suit_check_progress(me.id) if me != null else -1.0
	_progress_box.visible = p >= 0.0
	if p >= 0.0:
		_progress.share = p
	_update_cue()


## The countdown beside the storm picture: "in 6 h" while it is on its way, "6 h left" while it blows, "now" else.
static func storm_words(storm: Dictionary) -> String:
	var text := String(storm.get("text", ""))
	match String(storm.get("phase", "calm")):
		"warned":
			return text.trim_prefix("Dust storm ")
		"storm":
			var tail := text.trim_prefix("Dust storm").trim_prefix(" · ")
			return tail if tail != "" else "now"
	return ""


func _refresh_crew() -> void:
	if services == null or not services.has_game():
		return
	var me := services.local_character()
	_crew_box.visible = me != null
	_no_crew.visible = me == null
	if me == null:
		_no_crew_key.text = _key(&"crew", "C")
		HudKit.say(_no_crew, "No crew member. Press %s to choose one." % _key(&"crew", "C"))
		return
	if _badge_for != me.id:
		_badge_for = me.id
		_crew_badge.setup(me, CrewPortrait.crew_index(services.state(), me.id))
	_crew_name.text = role_word(me)
	_crew_specialty_icon.text = CrewPortrait.specialty_symbol(me.specialty)
	(_crew_specialty_icon as HudKit.Txt).tint(CrewPortrait.specialty_color(me.specialty))
	HudKit.say(_who_row, "%s · %s" % [me.display_name, CrewPortrait.specialty_words(me.specialty)])
	var health: StringName = &"urgent" if me.health < HEALTH_URGENT else (&"warn" if me.health < HEALTH_WARN else &"ok")
	_show_vital(_health, me.health, health, "Health %d %%" % roundi(me.health))
	_show_vital(_stamina, me.stamina, &"warn" if me.stamina < BODY_ENERGY_WARN else &"ok", "Body energy %d %%" % roundi(me.stamina))
	# The tank only matters while the suit is worn: then a low tank turns the bar to the warning colours.
	var tank: StringName = &"ok"
	if me.suit_on and me.suit_charge < SUIT_URGENT:
		tank = &"urgent"
	elif me.suit_on and me.suit_charge < SUIT_WARN:
		tank = &"warn"
	_show_vital(_suit, me.suit_charge, tank, "Suit %s · tank %d %%" % ["on" if me.suit_on else "off", roundi(me.suit_charge)])
	# Suit off: an open helmet with a line through it, and the bar steps back (the tank is not in use).
	(_suit.icon as HudKit.Icon).kind = &"helmet" if me.suit_on else &"helmet_off"
	(_suit.bar as Control).modulate.a = 1.0 if me.suit_on else 0.45
	_held_row.visible = _held != &""
	if _held != &"":
		_held_line.text = _item_name(_held)
		HudKit.say(_held_row, "In your hands: %s" % _item_name(_held).to_lower())
	_place_messages()          # the corner boxes may have changed size


## ONE short word for a crew member's job: "Electrical", "Medical", "Biology", "Geology" (the name tag's word).
static func role_word(c: CharacterState) -> String:
	var i := CrewLooks.index_of(c.specialty)
	if i >= 0:
		return String(CrewLooks.look(i).get("tag", "Crew"))
	var words := c.display_name.strip_edges().split(" ", false)
	return words[0] if words.size() > 0 else "Crew"


func _update_cue() -> void:
	if _cue == null:
		return
	var key := _key(&"interact", "E")
	var kind := String(_target.get("kind", ""))
	var text := ""
	var body := ""
	if kind == "station" and services != null and services.has_game():
		var rec: Dictionary = services.state().stations.get(String(_target.get("id", "")), {})
		var station_kind := String(rec.get("kind", ""))
		if station_kind == "suits":
			var me := services.local_character()
			body = "Suit check: %s" % ("take the suit off" if me != null and me.suit_on else "put the suit on")
		elif station_kind == "survivor":
			body = "Check on the patient"
		elif station_kind == "repair_task":
			body = repair_cue(services.state(), rec)
		elif station_kind == "cassette_anchor":
			body = "Pick up the tape"
		elif station_kind in ["cassette_player_anchor", "cassette_player"]:
			body = "Play tapes"
		else:
			var nm := String(STATION_NAMES.get(station_kind, "station"))
			body = "Use" if nm == "" else "Use %s" % nm
		if not TutorialLock.station_usable(services.state(), rec):
			body = ""
	elif kind == "ladder":
		body = "Hold ladder; W/S climb, E or Space release"
	elif _held != &"":
		body = "Put down"
	elif kind == "item":
		body = "Pick up %s" % _item_name(StringName(String(_target.get("id", "")))).to_lower()
	if body != "":
		text = "[%s] %s" % [key, body]
	_cue_full = text
	_cue_key.text = key
	_cue.text = short_cue(body)
	_cue_panel.visible = text != ""
	_cue_extra.visible = text != "" and kind == "ladder"
	HudKit.say(_cue_panel, text)
	# the crosshair grows a ring when E would do something with what you are looking at
	_crosshair.active = kind in ["station", "item", "ladder"] and body != ""


## Broken parts (2026-11-14): what E does at a repair task's spot, without the key. While the spot is broken, the
## part's own words from data/broken_parts.json ("Fix the wires"); otherwise a plain "Use comms station", named after
## the station ("T01 - Comms").
static func repair_cue(state: ColonyState, rec: Dictionary) -> String:
	var task_id := String(rec.get("task_id", ""))
	if BrokenParts.is_task_broken(state, task_id):
		var prompt := BrokenParts.prompt_for(task_id)
		if prompt != "":
			return BrokenParts.prompt_body(prompt)
	return "Use %s" % repair_station_name(rec)


## A repair task station's plain name in words: "T01 - Comms" -> "comms station".
static func repair_station_name(rec: Dictionary) -> String:
	var words := String(rec.get("name", ""))
	var dash := words.find(" - ")
	if dash >= 0:
		words = words.substr(dash + 3)
	words = words.strip_edges().to_lower()
	return "station" if words == "" else "%s station" % words


func _hint_line() -> String:
	# Owner 2026-11-14: the M map is hidden for now; J shows the goals (and the map in big mode).
	return "%s goals · %s cargo · %s crew · %s pause · %s sources" % [_key(&"goals", "J"), _key(&"inventory", "I"), _key(&"crew", "C"),
		_key(&"back", "Esc"), _key(&"source_register", "Shift+Backspace")]


func _item_name(item_id: StringName) -> String:
	if services == null or not services.has_game():
		return "thing"
	var rec: Dictionary = services.state().items.get(item_id, services.state().items.get(String(item_id), {}))
	return InventoryPanel.kind_name(String(rec.get("kind", "")))


func _on_action_resolved(result: ActionResult) -> void:
	# On the host every player's answers pass through here; show only this player's own.
	if result.peer != 0 and result.peer != services.local_peer():
		return
	if result.ok and not result.duplicate and bool(result.changes.get("collected", false)) and result.changes.has("cassette_id"):
		show_message("Collected: %s. %s" % [String(result.changes.get("title", "Room cassette")), CassetteCatalog.PLAY_INSTRUCTION], 5.0)
	if not result.ok and not result.duplicate and not result.pending and result.reason != &"paused":
		show_message(result.message, 3.0)


func _on_system_alert(alert_id: StringName, level: StringName, text: String) -> void:
	# Upgrade update: a level up reads "Greenhouse grow racks: V3: Three-layer rack with drip lines".
	if String(alert_id).begins_with(MissionHud.LEVEL_ALERT_PREFIX) and services != null and services.has_game():
		text = MissionHud.level_up_text(alert_id, text, services.state())
	if alert_sink.is_valid():
		last_alert_text = text.strip_edges().replace("CO2", "CO₂")
		alert_sink.call(alert_id, level, text)
		return
	show_alert(text)


## Scout update: the mission-control HUD has its own dock of keys, so the fading key strip is not needed.
func use_dock(on: bool) -> void:
	_hint_panel.visible = not on and not _hint_fading


static func _key(action: StringName, fallback: String) -> String:
	var k := PlayerInput.describe(action)
	if k == "":
		return fallback
	return k.replace("Escape", "Esc")


## Short text keeps its own width; text wider than `max_w` (screen units) wraps at that width.
func _fit_text(label: Label, max_w: float) -> void:
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	var widest := 0.0
	if font != null:
		for line in label.text.split("\n"):
			widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	if widest > max_w:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = max_w
	else:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.custom_minimum_size.x = 0.0


## Fits the texts whose width depends on the screen and the text size (key hints, messages).
func _fit_all() -> void:
	if _hint != null:
		_fit_text(_hint, _screen_size().x * 0.44)
	_place_messages()


## The aiming mark: a small dot that always shows, and a ring around it while E would do something.
class Crosshair extends Control:
	var active := false:
		set(v):
			if v != active:
				active = v
				queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(44, 44)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var pal := UiTheme.palette()
		# a dark halo under each mark keeps it readable on bright sand and on dark rooms alike
		draw_circle(c, 6.0, Color(0, 0, 0, 0.55), true, -1.0, true)
		draw_circle(c, 3.6, pal.text, true, -1.0, true)
		if active:
			draw_arc(c, 16.0, 0.0, TAU, 48, Color(0, 0, 0, 0.55), 6.0, true)
			draw_arc(c, 16.0, 0.0, TAU, 48, pal.accent, 3.0, true)


func _screen_size() -> Vector2:
	return _root.get_viewport_rect().size if _root != null and _root.is_inside_tree() else Vector2(1920, 1080)


## Messages go in the gap between the two top corners. When the corners leave no real gap (small screen, large
## text), the messages move to just under them instead and may be wider.
func _place_messages() -> void:
	if _centre_margin == null or _message_panel == null:
		return
	var screen := _screen_size()
	var left := _corner_left.get_combined_minimum_size()
	var right := _corner_right.get_combined_minimum_size()
	var gap := screen.x - 2.0 * (maxf(left.x, right.x) + EDGE + 20.0)
	var top := float(EDGE)
	var max_w := minf(gap, screen.x * 0.36)
	if top_reserved > 0.0:
		top = top_reserved + 10.0
	if gap < 360.0:
		top = maxf(top, EDGE + maxf(left.y, right.y) + 12.0)
		max_w = screen.x * 0.6
	if death_notice != null and death_notice.visible:
		var w := minf(maxf(max_w, 420.0), minf(760.0, screen.x - 2.0 * EDGE))
		death_notice.custom_minimum_size.x = w
		death_notice.size = Vector2(w, death_notice.get_combined_minimum_size().y)
		death_notice.position = Vector2(roundf((screen.x - w) * 0.5), roundf(top))
		top += death_notice.size.y + 10.0
	_centre_margin.add_theme_constant_override(&"margin_top", roundi(top))
	# One short line each; a line still wider than the room it has (large text on a small screen) wraps.
	for r: Dictionary in _message_rows:
		_fit_text(r.label as Label, max_w - 70.0)
