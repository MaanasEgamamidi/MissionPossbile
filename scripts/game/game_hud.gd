class_name GameHud
extends CanvasLayer
## The in-game HUD: small and readable, at the edges only.
##   top-left      sol and time with a sun or moon, then at most three urgent readings (or "Colony OK ✓")
##   top-right     your crew member: name, specialty symbol and colour, health, body energy, suit and tank (bars)
##   centre        crosshair (a ring appears when E would do something), under it what E does and the suit check bar
##   top-centre    "PAUSED" while the game is paused, and messages (queued)
##   bottom        a key hint strip that fades after 30 s, network status on the left; subtitles show above the strip
## It only reads state and listens to events; it never changes anything. It refreshes 4 times a second.

## Most urgent readings shown at once.
const MAX_READINGS := 3
## Messages on screen at once; more wait their turn.
const MAX_MESSAGES := 3
## Seconds of play before the key hint strip fades away.
const HINT_SECONDS := 30.0
const REFRESH_SECONDS := 0.25
## Space between the HUD and the edge of the screen, in screen units.
const EDGE := 24
## Suit tank share (percent) below which the tank counts as low / very low while the suit is worn.
const SUIT_WARN := 30.0
const SUIT_URGENT := 10.0

## Plain names of station kinds, as used in "[E] Use …".
const STATION_NAMES := {
	"suits": "suit rack", "power": "power panel", "computer": "colony computer", "comms": "comms console",
	"food": "greenhouse console", "board": "transceiver board", "lifesupport": "life support console",
	"heal": "med station", "survivor": "patient", "solar": "sun tracker",
	"scout_bay": "scout bay", "ore_deposit": "ore deposit", "salvage": "damaged machine", "sample_site": "sample site",
}
## Seconds a colony system alert stays in the message line.
const ALERT_SECONDS := 6.0

var services: GameServices

var _root: Control
var _time: Label
var _reading_rows: Array[HBoxContainer] = []
var _ok_line: Label
var _crew_badge: CrewPortrait
var _crew_name: Label
var _crew_specialty: Label
## The specialty symbol before the specialty words, in the crew member's accent colour (CrewLooks).
var _crew_specialty_icon: Label
var _health_text: Label
var _health_bar: ProgressBar
var _stamina_text: Label
var _stamina_bar: ProgressBar
var _suit: Label
var _held_line: Label
var _no_crew: Label
var _crew_box: VBoxContainer
var _crosshair: Crosshair
var _cue: Label
var _cue_key: Label
var _cue_panel: PanelContainer
var _cue_full := ""
var _suit_bar: ProgressBar
var _corner_left: PanelContainer
var _corner_right: PanelContainer
var _centre_margin: MarginContainer
## The message line. Shows up to MAX_MESSAGES messages, one per line, oldest first.
var _message: Label
var _message_panel: PanelContainer
var _progress_box: Control
var _progress: ProgressBar
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
## Screen units at the top kept free for the vitals bar; messages then show just under it.
var top_reserved := 0.0
var _hazard: Label
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


## Shows a message at the bottom for `seconds`. Messages queue: up to three show at once, the rest wait.
## The same text twice in a row is shown once (its time is extended).
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
	_update_messages()


## Messages on screen now, oldest first.
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


## Shows or hides the whole HUD (for example for screenshots or full-screen menus).
func set_visible_hud(on: bool) -> void:
	visible = on
	if _root != null:
		_root.visible = on


## One line of network or session status ("Connected to the host"); empty hides it.
func set_status(text: String) -> void:
	_status.text = text
	_status_panel.visible = text != ""


## The interaction cue under the crosshair ("[E] Use power panel"), or "".
func cue_text() -> String:
	return _cue_full


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


## Texts of the readings now shown in the top-left (empty when "Colony OK" is shown).
func shown_readings() -> PackedStringArray:
	var out := PackedStringArray()
	for row in _reading_rows:
		if row.visible:
			var parts := PackedStringArray()
			for l in row.get_children():
				parts.append((l as Label).text)
			out.append(" ".join(parts))
	return out


## True while the one quiet "Colony OK ✓" line is shown.
func colony_ok_shown() -> bool:
	return _ok_line.visible


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

	# ---- top row: colony corner, then pause banner and messages in the middle, then your crew member
	var top := HBoxContainer.new()
	top.name = "Top"
	top.add_theme_constant_override(&"separation", 20)
	column.add_child(top)
	var left := _hud_box(top, "TopLeft")
	_corner_left = left
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override(&"separation", 6)
	left.add_child(left_box)
	_time = Label.new()
	_time.name = "Time"
	_time.theme_type_variation = UiTheme.HEADING
	left_box.add_child(_time)
	# Scout update: a dust storm on its way or running ("⚠ Dust storm in 6 h").
	_hazard = Label.new()
	_hazard.name = "Hazard"
	_hazard.theme_type_variation = UiTheme.WARN
	_hazard.visible = false
	left_box.add_child(_hazard)
	for i in MAX_READINGS:
		var row := HBoxContainer.new()
		row.name = "Reading%d" % i
		for part in ["Symbol", "Value", "Word"]:
			var l := Label.new()
			l.name = part
			row.add_child(l)
		row.visible = false
		left_box.add_child(row)
		_reading_rows.append(row)
	_ok_line = Label.new()
	_ok_line.name = "ColonyOk"
	_ok_line.text = "Colony OK ✓"
	_ok_line.theme_type_variation = UiTheme.GOOD
	left_box.add_child(_ok_line)

	var top_space := Control.new()
	top_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(top_space)

	var right := _hud_box(top, "TopRight")
	_corner_right = right
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var right_box := VBoxContainer.new()
	right.add_child(right_box)
	_crew_box = VBoxContainer.new()
	_crew_box.name = "Crew"
	_crew_box.add_theme_constant_override(&"separation", 8)
	right_box.add_child(_crew_box)
	var who := HBoxContainer.new()
	who.name = "Who"
	who.add_theme_constant_override(&"separation", 12)
	_crew_box.add_child(who)
	_crew_badge = CrewPortrait.new()
	_crew_badge.name = "Badge"
	_crew_badge.prefer_rig = false
	_crew_badge.custom_minimum_size = Vector2(56, 56)
	_crew_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(_crew_badge)
	var who_text := VBoxContainer.new()
	who_text.add_theme_constant_override(&"separation", 0)
	who.add_child(who_text)
	_crew_name = Label.new()
	_crew_name.name = "Name"
	_crew_name.theme_type_variation = UiTheme.HEADING
	who_text.add_child(_crew_name)
	var specialty_row := HBoxContainer.new()
	specialty_row.name = "SpecialtyRow"
	specialty_row.add_theme_constant_override(&"separation", 6)
	who_text.add_child(specialty_row)
	_crew_specialty_icon = Label.new()
	_crew_specialty_icon.name = "SpecialtyIcon"
	_crew_specialty_icon.theme_type_variation = UiTheme.MUTED
	# A monochrome symbol font: the default fallback draws ⚡ and ⛏ as colour emoji, which ignore the accent colour.
	var symbols := SystemFont.new()
	symbols.font_names = PackedStringArray(["Segoe UI Symbol", "Noto Sans Symbols 2", "Noto Sans Symbols", "DejaVu Sans"])
	symbols.allow_system_fallback = false   # otherwise the text server still picks Segoe UI Emoji for ⚡
	symbols.fallbacks = [ThemeDB.fallback_font]
	_crew_specialty_icon.add_theme_font_override(&"font", symbols)
	specialty_row.add_child(_crew_specialty_icon)
	_crew_specialty = Label.new()
	_crew_specialty.name = "Specialty"
	_crew_specialty.theme_type_variation = UiTheme.MUTED
	specialty_row.add_child(_crew_specialty)
	var bars := GridContainer.new()
	bars.name = "Bars"
	bars.columns = 2
	bars.add_theme_constant_override(&"v_separation", 6)
	_crew_box.add_child(bars)
	_health_text = Label.new()
	_health_text.name = "HealthText"
	bars.add_child(_health_text)
	_health_bar = _bar(bars, "HealthBar")
	_stamina_text = Label.new()
	_stamina_text.name = "BodyEnergyText"
	bars.add_child(_stamina_text)
	_stamina_bar = _bar(bars, "BodyEnergyBar")
	_suit = Label.new()
	_suit.name = "Suit"
	bars.add_child(_suit)
	_suit_bar = _bar(bars, "SuitTankBar")
	_suit_bar.theme_type_variation = UiTheme.BAR_COOL
	_held_line = Label.new()
	_held_line.name = "Held"
	_held_line.theme_type_variation = UiTheme.MUTED
	_crew_box.add_child(_held_line)
	_no_crew = Label.new()
	_no_crew.name = "NoCrew"
	right_box.add_child(_no_crew)

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
	_banner_panel = _hud_box(centre_column, "Paused")
	_banner_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var banner_box := VBoxContainer.new()
	banner_box.add_theme_constant_override(&"separation", 2)
	_banner_panel.add_child(banner_box)
	_banner = Label.new()
	_banner.name = "Banner"
	_banner.text = "⏸ PAUSED"
	_banner.theme_type_variation = UiTheme.TITLE
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(_banner)
	var banner_note := Label.new()
	banner_note.name = "BannerNote"
	banner_note.text = "The colony clock is stopped."
	banner_note.theme_type_variation = UiTheme.MUTED
	banner_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(banner_note)
	_banner_panel.visible = false
	_message_panel = PanelContainer.new()
	_message_panel.name = "Messages"
	_message_panel.theme_type_variation = UiTheme.TOAST
	_message_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	centre_column.add_child(_message_panel)
	_message = Label.new()
	_message.name = "Message"
	_message_panel.add_child(_message)
	_message_panel.visible = false

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
	below.offset_top = 36.0
	below.add_theme_constant_override(&"separation", 14)
	_root.add_child(below)
	_cue_panel = PanelContainer.new()
	_cue_panel.name = "CuePanel"
	_cue_panel.theme_type_variation = UiTheme.CHIP
	_cue_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	below.add_child(_cue_panel)
	var cue_row := HBoxContainer.new()
	_cue_panel.add_child(cue_row)
	var cap := UiTheme.key_cap("E")
	cap.name = "CueKey"
	_cue_key = cap.get_node("Key") as Label
	cue_row.add_child(cap)
	_cue = Label.new()
	_cue.name = "Cue"
	cue_row.add_child(_cue)
	_cue_panel.visible = false
	var progress_panel := _hud_box(below, "SuitCheck")
	progress_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var progress_inner := VBoxContainer.new()
	progress_inner.custom_minimum_size.x = 360.0
	progress_panel.add_child(progress_inner)
	var progress_label := Label.new()
	progress_label.text = "Suit check…"
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_inner.add_child(progress_label)
	_progress = _bar(progress_inner, "Progress")
	_progress.theme_type_variation = UiTheme.BAR_COOL
	_progress_box = progress_panel          # the whole box shows and hides with the check
	_progress_box.visible = false

	_ignore_mouse(_root)
	_root.theme_changed.connect(_fit_all)
	_fit_all()


func _hud_box(parent: Control, box_name: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = box_name
	p.theme_type_variation = UiTheme.HUD_PANEL
	parent.add_child(p)
	return p


func _bar(parent: Control, bar_name: String) -> ProgressBar:
	var b := ProgressBar.new()
	b.name = bar_name
	b.min_value = 0.0
	b.max_value = 100.0
	b.show_percentage = false
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.custom_minimum_size = Vector2(170.0, 16.0)
	parent.add_child(b)
	return b


func _side_spacer(parent: Control) -> void:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(s)


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
	_message.text = "\n".join(current_messages())
	_message_panel.visible = not _showing.is_empty()
	_place_messages()


## Re-reads state and updates everything shown. Runs 4 times a second by itself.
func refresh() -> void:
	if services == null or not services.has_game():
		return
	var c := services.clock()
	var hour := c.hour_of_sol()
	var day := c.is_daylight()
	_time.text = "%s Sol %d · %02d:%02d · %s" % ["☀" if day else "☾", c.sol_index + 1, int(hour), int(fmod(hour, 1.0) * 60.0), "day" if day else "night"]
	var low := low_readings(services)
	for i in _reading_rows.size():
		var row := _reading_rows[i]
		row.visible = i < low.size()
		if not row.visible:
			continue
		var r: Dictionary = low[i]
		var variation := ReadingRow.variation_of(r.level)
		(row.get_node("Symbol") as Label).text = String(r.symbol)
		(row.get_node("Value") as Label).text = "%s %s" % [r.name, r.value]
		var word := row.get_node("Word") as Label
		word.text = "%s %s" % ["✖" if r.level == &"urgent" else "!", r.word]
		for l in row.get_children():
			(l as Label).theme_type_variation = variation
	_ok_line.visible = low.is_empty()
	var storm := StormOutlook.now(services.state())
	_hazard.visible = String(storm.phase) != "calm"
	_hazard.text = ("⚠ " if String(storm.phase) == "warned" else "✖ ") + String(storm.text)
	_hazard.theme_type_variation = UiTheme.WARN if String(storm.phase) == "warned" else UiTheme.URGENT
	_refresh_crew()
	_banner_panel.visible = services.session.paused
	var me := services.local_character()
	var p := services.session.suit_check_progress(me.id) if me != null else -1.0
	_progress_box.visible = p >= 0.0
	if p >= 0.0:
		_progress.value = p * 100.0
	_update_cue()


func _refresh_crew() -> void:
	if services == null or not services.has_game():
		return
	var me := services.local_character()
	_crew_box.visible = me != null
	_no_crew.visible = me == null
	if me == null:
		_no_crew.text = "No crew member. Press %s to choose one." % _key(&"crew", "C")
		return
	if _badge_for != me.id:
		_badge_for = me.id
		_crew_badge.setup(me, CrewPortrait.crew_index(services.state(), me.id))
	_crew_name.text = me.display_name
	_crew_specialty_icon.text = CrewPortrait.specialty_symbol(me.specialty)
	_crew_specialty_icon.add_theme_color_override(&"font_color", CrewPortrait.specialty_color(me.specialty))
	_crew_specialty.text = CrewPortrait.specialty_words(me.specialty)
	_health_text.text = "Health %d %%" % roundi(me.health)
	_health_bar.value = me.health
	_health_bar.theme_type_variation = UiTheme.bar_of(&"urgent" if me.health < 30.0 else (&"warn" if me.health < 60.0 else &"ok"))
	_stamina_text.text = "Body energy %d %%" % roundi(me.stamina)
	_stamina_bar.value = me.stamina
	_suit.text = "Suit %s · tank %d %%" % ["on" if me.suit_on else "off", roundi(me.suit_charge)]
	_suit_bar.value = me.suit_charge
	# The tank only matters while the suit is worn: then a low tank turns the bar to the warning colours.
	var tank: StringName = &"ok"
	if me.suit_on and me.suit_charge < SUIT_URGENT:
		tank = &"urgent"
	elif me.suit_on and me.suit_charge < SUIT_WARN:
		tank = &"warn"
	_suit_bar.theme_type_variation = UiTheme.BAR_COOL if tank == &"ok" else UiTheme.bar_of(tank)
	if _held != &"":
		_held_line.text = "In your hands: %s" % _item_name(_held).to_lower()
	else:
		_held_line.text = "Hands empty"
	_place_messages()          # the corner boxes may have changed size


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
		else:
			body = "Use %s" % String(STATION_NAMES.get(station_kind, "station"))
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
	_cue.text = body
	_cue_panel.visible = text != ""
	# the crosshair grows a ring when E would do something with what you are looking at
	_crosshair.active = kind in ["station", "item", "ladder"]


func _hint_line() -> String:
	return "%s map · %s cargo · %s crew · %s pause · %s sources" % [_key(&"map", "M"), _key(&"inventory", "I"), _key(&"crew", "C"),
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
	if not result.ok and not result.duplicate and not result.pending and result.reason != &"paused":
		show_message(result.message, 3.0)


func _on_system_alert(alert_id: StringName, level: StringName, text: String) -> void:
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
	if _centre_margin == null or _message == null:
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
	_centre_margin.add_theme_constant_override(&"margin_top", roundi(top))
	_fit_text(_message, max_w - 46.0)
