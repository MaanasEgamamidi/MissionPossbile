class_name MissionHud
extends Control
## The mission-control HUD of the scout update, laid around GameHud's own corners (time and alerts top left, your crew
## member top right, the crosshair in the middle):
##   top centre     VitalsBar: electricity, oxygen, water, food, parts, science, ore. ⋯ (U) folds it, ? (F1) explains.
##   H              owner 2026-11-15: the gold sparkle line to what matters now (scripts/guide/help_key.gd) and, above
##                  the dock, the "Press H for help" pop-up of a timed emergency (scripts/ui/hud/help_prompt.gd).
##                  Under it the battery chip: sun or moon, battery %, and while it drains how fast and how long it lasts.
##   left           GoalsCard under the time. Owner 2026-11-14, J cycles three looks: the goal list (a new game starts
##                  here) -> the big goals screen with the base map (scripts/ui/hud/goals_big_panel.gd, a UiRoot panel)
##                  -> the compact card ("GOALS 3/12" and a bar) -> the list ... J, Esc or ✕ on the big screen = compact.
##   right          the pop-ups (ToastStack) under your crew member. Owner 2026-11-14: the MiniMap is hidden for now.
##   lower left     MissionControlCard: a picture, a title and ONE line (a dust storm on its way, a scout report with
##                  the mast camera's picture, a supply about to run out). K closes it; the whole message is in the
##                  Power drawer's message list (P).
##   lower right    the scout's mast camera, live, while it is out on a trip.
##   bottom centre  the dock of keys (Build B, Power P, Cargo I, Crew C, Science F1): a big pictogram, a key cap and
##                  one word each; Build is dimmed with a padlock away from the solar field. By a sun tracker,
##                  "B Build here".
## Everything here only reads the colony; the drawers it opens (PowerLifePanel, SolarBuildPanel, VitalsSciencePanel)
## go through UiRoot like every panel. Colony alerts become pop-ups here instead of GameHud's message line.

const SETTINGS_PATH := "user://mission_hud.json"
const EDGE := 24.0
## Metres from a sun tracker within which B opens the build drawer.
const BUILD_REACH_M := 7.0
## Real seconds before the same low supply is announced again.
const LOW_REPEAT_S := 180.0
## Alert ids of upgrade_area level ups start with this, then the track id (AreaLevelActions).
const LEVEL_ALERT_PREFIX := "area_level_"
## Upgrade update (2026-11-14): the battery chip under the vitals bar (sun or moon, battery %, night drain).
const EnergyChipScript := preload("res://scripts/ui/hud/energy_chip.gd")
## Owner 2026-11-14: the big goals screen (J), with the goals on a map of the base. It replaces the M blueprint map.
const GoalsBigPanelScript := preload("res://scripts/ui/hud/goals_big_panel.gd")
## UI overhaul (2026-11-15): the dock, the build chip, the mast camera card and Mission Control are drawn with the
## HUD kit (pictograms, key caps and words that follow the text size setting) and the mini-games' padlock.
const HudKit := preload("res://scripts/ui/hud/hud_kit.gd")
const PuzzleKit := preload("res://scripts/tasks/puzzles/kit.gd")
## The dock's keys, left to right: [name, pictogram (HudKit), action, fallback key].
const DOCK := [["Build", &"build", &"build", "B"], ["Power", &"power", &"power_view", "P"], ["Cargo", &"cargo", &"inventory", "I"],
	["Crew", &"crew", &"crew", "C"], ["Science", &"science", &"vitals_help", "F1"]]
## Owner 2026-11-15: H shows the gold sparkle line to what matters now; the "Press H for help" pop-up.
const HelpKeyScript := preload("res://scripts/guide/help_key.gd")
const HelpPromptScript := preload("res://scripts/ui/hud/help_prompt.gd")
## Upgrade paths plan phase 1 (2026-11-15): colony balance chip, build vote card, solar storm banner, COLONY OVER.
const BalanceChipScript := preload("res://scripts/ui/hud/balance_chip.gd")
const BuildVoteCardScript := preload("res://scripts/ui/hud/build_vote_card.gd")
const SolarStormBannerScript := preload("res://scripts/ui/hud/solar_storm_banner.gd")
const ColonyOverBannerScript := preload("res://scripts/ui/hud/colony_over_banner.gd")
const ColonyOverScreenScript := preload("res://scripts/ui/hud/colony_over_screen.gd")

var services: GameServices
var game: Node
var hud: GameHud
var ui: UiRoot

var vitals: VitalsBar
## The battery chip under the vitals bar (scripts/ui/hud/energy_chip.gd).
var energy: PanelContainer
var goals: GoalsCard
## Owner 2026-11-14: hidden for now (the big goals screen has the map). Stays null.
var map: MiniMap
var toasts: ToastStack
var mission_control: MissionControlCard
var dock: PanelContainer
var build_chip: PanelContainer
var feed: PanelContainer
## The H key (scripts/guide/help_key.gd) and its "Press H for help" pop-up (scripts/ui/hud/help_prompt.gd).
var help_key: Node
var help_prompt: Control
var balance_chip: PanelContainer
var vote_card: PanelContainer
var storm_banner: Control
var over_banner: Control
var _over_screen_open := false

var _feed_tex: TextureRect
var _feed_status: Label
var _dock_build: Control
var _dock_buttons: Dictionary = {}   # action -> the dock button
var _refresh_left := 0.0
var _auto_compact := false
## The player's own choice: true = the calm look (pictures and bars, the default), false = the numbers look (key H).
var _user_compact := true
var _goals_folded_for_mc := false
## The player chose the goal list with J: Mission Control's card no longer folds it away (it would look like J did nothing).
var _list_by_user := false
var _near_tracker: StringName = &""
var _low_said: Dictionary = {}       # key -> Time seconds
var _last_report_at := -1.0


func setup(_world: Node3D, p_services: GameServices, p_game: Node) -> void:
	services = p_services
	game = p_game
	hud = p_game.get("hud") as GameHud
	ui = p_game.get("ui") as UiRoot
	name = "MissionHud"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()
	if hud != null:
		hud.add_child(self)
		hud.alert_sink = _on_alert
		hud.supplies_on_strip = true
		hud.use_dock(true)
	vitals = VitalsBar.new()
	add_child(vitals)
	vitals.setup(services)
	vitals.details_requested.connect(open_power)
	vitals.help_requested.connect(open_science)
	vitals.compact_changed.connect(func(on: bool) -> void:
		if not _auto_compact:
			_user_compact = on
			_save())
	energy = EnergyChipScript.new()
	add_child(energy)
	energy.setup(services)
	balance_chip = BalanceChipScript.new()
	add_child(balance_chip)
	balance_chip.call(&"setup", services)
	vote_card = BuildVoteCardScript.new()
	add_child(vote_card)
	vote_card.call(&"setup", services)
	storm_banner = SolarStormBannerScript.new()
	storm_banner.set(&"services", services)
	add_child(storm_banner)
	over_banner = ColonyOverBannerScript.new()
	over_banner.set(&"services", services)
	add_child(over_banner)
	over_banner.connect(&"colony_over_reached", func(_record: Dictionary) -> void: _open_colony_over())
	goals = GoalsCard.new()
	add_child(goals)
	goals.setup(services)
	goals.toggled.connect(func(_open: bool) -> void:
		if not _goals_folded_for_mc:
			_save())
	# Owner 2026-11-14: hidden for now (the big goals screen, J, has the map).
	#map = MiniMap.new()
	#add_child(map)
	#map.setup(services)
	toasts = ToastStack.new()
	add_child(toasts)
	mission_control = MissionControlCard.new()
	add_child(mission_control)
	help_key = HelpKeyScript.new()
	add_child(help_key)
	help_key.call(&"setup", services, self)
	help_prompt = HelpPromptScript.new()
	add_child(help_prompt)
	help_prompt.call(&"setup", services, self, help_key)
	_build_feed()
	_build_dock()
	_load()
	services.events.weather_changed.connect(_on_weather)
	PlayerInput.ensure_actions()
	refresh()


# ---------------------------------------------------------------- building

func _build_feed() -> void:
	feed = HudKit.Card.new("MastFeed", AstraStyle.RADIUS, 10, 8, true)
	add_child(feed)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	head.add_child(HudKit.Icon.new(&"dot", AstraStyle.DANGER, 14.0, "Rec"))
	head.add_child(HudKit.Icon.new(&"scout", AstraStyle.TEXT_2, 24.0, "Symbol"))
	var t := HudKit.Txt.new("Scout camera", 18.0, AstraStyle.TEXT_2, "Title")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_feed_tex = TextureRect.new()
	_feed_tex.name = "Picture"
	_feed_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_feed_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_feed_tex.custom_minimum_size = Vector2(320, 180)
	_feed_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_feed_tex)
	_feed_status = HudKit.Txt.new("", 18.0, AstraStyle.TEXT, "Status")
	_feed_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feed_status.custom_minimum_size.x = 320
	col.add_child(_feed_status)
	feed.visible = false


## The dock: one big pictogram per key with its key cap and one word. A key that does nothing right now (Build away
## from the solar field) is dimmed and shows a padlock where its key cap was.
func _build_dock() -> void:
	dock = HudKit.Card.new("Dock", AstraStyle.RADIUS, 12, 8)
	add_child(dock)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override(&"separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_child(row)
	var runs := {&"build": open_build, &"power_view": open_power, &"inventory": _press.bind(&"inventory"),
		&"crew": _press.bind(&"crew"), &"vitals_help": open_science}
	# Owner 2026-11-14: the M map key is hidden for now (the big goals screen, J, has the map).
	for d: Array in DOCK:
		_dock_buttons[d[2]] = _dock_button(row, d[1], String(d[0]), d[2], String(d[3]), runs[d[2]])
	_dock_build = _dock_buttons[&"build"]
	build_chip = AstraStyle.panel(AstraStyle.pill(Color(AstraStyle.ACCENT, 0.95), AstraStyle.RADIUS_SM + 4, 16, 8), "BuildChip")
	build_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(build_chip)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_chip.add_child(h)
	h.add_child(HudKit.key_cap(GameHud._key(&"build", "B"), 22.0))
	h.add_child(HudKit.Icon.new(&"build", AstraStyle.ACCENT_INK, 30.0, "Symbol"))
	h.add_child(HudKit.Txt.new("Build here", 24.0, AstraStyle.ACCENT_INK, "Text", true))
	HudKit.say(build_chip, "Build here: this is the solar field")
	build_chip.visible = false


func _dock_button(row: HBoxContainer, icon: StringName, word: String, action: StringName, key: String, run: Callable) -> Control:
	var b := PanelContainer.new()
	b.name = word
	b.add_theme_stylebox_override(&"panel", AstraStyle.pill(Color(0, 0, 0, 0), 12, 12, 4))
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var key_text := GameHud._key(action, key)
	if key_text.contains("/"):
		key_text = key
	b.set_meta(&"words", "%s (%s)" % [PlayerInput.ACTION_NAMES.get(action, word), key_text])
	HudKit.say(b, String(b.get_meta(&"words")))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			run.call())
	row.add_child(b)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override(&"separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	top.add_child(HudKit.Icon.new(icon, AstraStyle.TEXT, 42.0, "Symbol"))
	top.add_child(HudKit.key_cap(key_text, 20.0, "Key"))
	var lock := Control.new()
	lock.name = "Lock"
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lock.visible = false
	lock.draw.connect(func() -> void:
		var r := minf(lock.size.x, lock.size.y) * 0.5
		PuzzleKit.lock(lock, lock.size * 0.5 + Vector2(0.0, -r * 0.17), r, true, AstraStyle.TEXT_2))
	top.add_child(lock)
	var w := HudKit.Txt.new(word, 20.0, AstraStyle.TEXT_2, "Word")
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(w)
	return b


## Shows a dock key as usable, or dimmed with a padlock in place of its key cap (`why` joins its tooltip).
func _set_dock_usable(b: Control, on: bool, why := "") -> void:
	if b == null:
		return
	var lock := b.find_child("Lock", true, false) as Control
	var px := roundf(34.0 * HudKit.scale())
	if lock.custom_minimum_size.x != px:
		lock.custom_minimum_size = Vector2(px, px)
	if b.has_meta(&"usable") and bool(b.get_meta(&"usable")) == on:
		return
	b.set_meta(&"usable", on)
	b.modulate.a = 1.0 if on else 0.5
	(b.find_child("Symbol", true, false) as HudKit.Icon).color = AstraStyle.TEXT if on else AstraStyle.TEXT_3
	(b.find_child("Word", true, false) as HudKit.Txt).tint(AstraStyle.TEXT_2 if on else AstraStyle.TEXT_3)
	(b.find_child("Key", true, false) as Control).visible = on
	lock.visible = not on
	lock.queue_redraw()
	HudKit.say(b, String(b.get_meta(&"words")) if on else "%s. %s" % [String(b.get_meta(&"words")), why])


## True while the dock shows `action`'s key as usable (Build is not, away from the solar field).
func dock_usable(action: StringName) -> bool:
	var b := _dock_buttons.get(action) as Control
	return b != null and bool(b.get_meta(&"usable", true))


# ---------------------------------------------------------------- actions

func open_power() -> void:
	if ui == null or _top_is(PowerLifePanel):
		return
	ui.open(PowerLifePanel.new())


func open_science() -> void:
	if ui == null or _top_is(VitalsSciencePanel):
		return
	ui.open(VitalsSciencePanel.new())


## J from the goal list: the big goals screen with the map (step 2 of the J cycle). However it closes (J, Esc, ✕),
## the goals card then shows its compact look (step 3).
func open_goals_big() -> void:
	if ui == null or _top_is(GoalsBigPanelScript):
		return
	var panel := GoalsBigPanelScript.new() as UiPanel
	panel.tree_exiting.connect(_on_goals_big_closed)
	ui.open(panel)


## The big goals screen left the screen (UiRoot took it out): on to the compact goals card. UiRoot's own close path
## captures the mouse again.
func _on_goals_big_closed() -> void:
	if goals == null or not is_instance_valid(goals):
		return
	_goals_folded_for_mc = false        # compact by choice now, not only for Mission Control
	_list_by_user = false
	goals.set_open(false)


func open_build() -> void:
	if ui == null:
		return
	if _near_tracker == &"":
		toasts.push("Build works at the solar field: walk up to a sun tracker outside, then press B.", &"info")
		return
	var p := SolarBuildPanel.new()
	p.tracker_id = _near_tracker
	ui.open(p)


func _top_is(script_class: Script) -> bool:
	var top := ui.top()
	return top != null and top.get_script() == script_class


func _press(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or services == null or not services.has_game():
		return
	if ui != null and ui.is_open():
		return
	# Held before any key's action runs, so marking the key handled never depends on what that action did.
	var vp := get_viewport()
	if event.is_action_pressed(&"power_view"):
		open_power()
	elif event.is_action_pressed(&"build"):
		open_build()
	elif event.is_action_pressed(&"hud_details"):
		# Owner 2026-11-15: U (it was H) folds the supplies bar.
		vitals.toggle_compact()
	elif event.is_action_pressed(&"help"):
		# Owner 2026-11-15: H shows the gold sparkle line to what matters now (H again ends it).
		help_key.call(&"toggle")
	elif event.is_action_pressed(&"goals"):
		# Owner 2026-11-14: J cycles list -> big screen with the map -> compact -> list ... The big screen handles its
		# own J (and Esc / ✕); closing it lands on compact (_on_goals_big_closed). Here: list -> map, compact -> list.
		#goals.toggle()
		if ui == null:
			goals.toggle()
		elif goals.open or _goals_folded_for_mc:
			open_goals_big()
		else:
			_list_by_user = true
			goals.set_open(true)
	elif event.is_action_pressed(&"advisor_ok"):
		mission_control.dismiss()
	elif event.is_action_pressed(&"vitals_help"):
		open_science()
	else:
		return
	if vp != null:
		vp.set_input_as_handled()


# ---------------------------------------------------------------- events

func _on_alert(alert_id: StringName, level: StringName, text: String) -> void:
	var kind: StringName = &"info"
	match level:
		&"warn":
			kind = &"warn"
		&"urgent", &"danger", &"critical":
			kind = &"danger"
		&"good", &"ok":
			kind = &"good"
	if alert_id == WeatherSystem.ALERT_ID:
		# UI overhaul: the card is the warning (no pop-up saying the same). It shows when, and the one thing to do; the
		# whole advice is in the Power drawer's message list (P).
		var st := services.state()
		mission_control.say(StormOutlook.warning_title(st), StormOutlook.warning_advice(st), &"warn", null, "Weather · Jezero archive",
			StormOutlook.warning_line(st), &"storm")
		return
	if alert_id == ScoutSystem.ALERT_ID and text.begins_with("Scout report"):
		_scout_report.call_deferred(text)
		return
	if String(alert_id).begins_with(LEVEL_ALERT_PREFIX):
		toasts.push(level_up_text(alert_id, text, services.state()), &"good")
		return
	toasts.push(text, kind)


## The pop-up for a level up of an upgrade path (the `area_level_<track>` alert of upgrade_area):
## "Greenhouse grow racks: V3: Three-layer rack with drip lines". The level comes from the alert's own words when they
## name it (on a networked client the alert can arrive before the new level does), else from the colony.
static func level_up_text(alert_id: StringName, text: String, st: ColonyState) -> String:
	var track := String(alert_id).trim_prefix(LEVEL_ALERT_PREFIX)
	if AreaLevels.track(track).is_empty():
		return text
	var lvl := AreaLevels.level(st, track)
	var re := RegEx.create_from_string("\\bV(\\d+)\\b")
	var m := re.search(text)
	if m != null:
		lvl = clampi(int(m.get_string(1)), AreaLevels.MIN_LEVEL, AreaLevels.max_level())
	return "%s: %s" % [AreaLevels.track_name(track), AreaLevels.stage_text(track, lvl)]


func _scout_report(text: String) -> void:
	var st := services.state()
	var rep: Dictionary = st.scout.get("last_report", {})
	var presenter := ScoutPresenter.find(get_tree())
	var pic := presenter.snapshot(String(rep.get("site", ""))) if presenter != null else null
	var body := String(rep.get("text", text))
	if String(rep.get("hazard", "")) != "":
		body += " ⚠ " + String(rep.hazard)
	var revealed: Array = rep.get("revealed", [])
	if not revealed.is_empty():
		body += " %d ore deposit%s marked on the map (◆)." % [revealed.size(), "" if revealed.size() == 1 else "s"]
	# UI overhaul: the picture and ONE line (what it found for you: ore first, else a danger, else the first sentence).
	var line := HudKit.short_line(String(rep.get("text", text)), MissionControlCard.MAX_LINE_WORDS)
	if not revealed.is_empty():
		line = "%d ore deposit%s on the map" % [revealed.size(), "" if revealed.size() == 1 else "s"]
	elif String(rep.get("hazard", "")) != "":
		line = HudKit.short_line(String(rep.hazard), MissionControlCard.MAX_LINE_WORDS)
	mission_control.say("Scout: %s" % String(rep.get("name", "report")), body, &"good", pic, "Scout rover · mast camera", line, &"scout")


func _on_weather(e: Dictionary) -> void:
	match String(e.get("type", "")):
		"start":
			toasts.push("The dust storm has started: the solar panels make less power now. Save electricity.", &"danger")
		"end":
			toasts.push("The dust storm is over. Clean the solar panels to get full power back!", &"good")


func _check_low() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for r: Dictionary in GameHud.low_readings(services):
		if r.level != &"urgent":
			continue
		var key := String(r.key)
		if now - float(_low_said.get(key, -1e9)) < LOW_REPEAT_S:
			continue
		_low_said[key] = now
		# UI overhaul: two short sentences; the Power drawer (P) has the why and the station to fix it at.
		var words := "Down to %s. Press %s to see why." % [String(r.value), GameHud._key(&"power_view", "P")]
		mission_control.say("%s is very low" % String(r.name), words, &"danger", null, "Colony radio", words,
			StringName(GameHud.READING_ICONS.get(r.key, &"danger")))


# ---------------------------------------------------------------- refresh and layout

func _process(delta: float) -> void:
	if services == null or not services.has_game():
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.25
		refresh()
	_layout()


func refresh() -> void:
	if services == null or not services.has_game():
		return
	vitals.refresh()
	energy.call(&"refresh")
	balance_chip.call(&"refresh")
	goals.refresh()
	# Owner 2026-11-14: hidden for now.
	#map.refresh()
	var st := services.state()
	# the scout's camera while it is out
	var out := ScoutSystem.is_out(st)
	feed.visible = out
	if out:
		var presenter := ScoutPresenter.find(get_tree())
		if presenter != null:
			presenter.want_live(true)
			_feed_tex.texture = presenter.mast_texture()
		_feed_tex.visible = _feed_tex.texture != null
		var status := ScoutSystem.status_text(st)
		_feed_status.text = HudKit.short_line(status.get_slice(" · ", 0))      # where it is going; the tooltip has the rest
		HudKit.say(feed, "Scout camera. %s" % status)
	# by a sun tracker outside: B builds here
	_near_tracker = _tracker_near()
	build_chip.visible = _near_tracker != &""
	_set_dock_usable(_dock_build, _near_tracker != &"", "Walk to a sun tracker outside first.")
	_check_low()


func _tracker_near() -> StringName:
	var me := services.local_character()
	if me == null:
		return &""
	var best := &""
	var best_d := BUILD_REACH_M
	var st := services.state()
	for id: String in st.stations:
		var rec: Dictionary = st.stations[id]
		if String(rec.get("kind", "")) != "solar":
			continue
		var p := CharacterState._v3(rec.get("position", [0, 0, 0]))
		var d := Vector2(p.x, p.z).distance_to(Vector2(me.position.x, me.position.z))
		if d < best_d:
			best_d = d
			best = StringName(id)
	return best


func _layout() -> void:
	if hud == null or not is_inside_tree():
		return
	var screen := get_viewport_rect().size
	var root := hud.root_control()
	var left_box := root.find_child("TopLeft", true, false) as Control if root != null else null
	var right_box := root.find_child("TopRight", true, false) as Control if root != null else null
	var left := left_box.get_global_rect() if left_box != null and left_box.is_visible_in_tree() else Rect2(EDGE, EDGE, 0, 0)
	var right := right_box.get_global_rect() if right_box != null and right_box.is_visible_in_tree() else Rect2(screen.x - EDGE, EDGE, 0, 0)
	# vitals: between the corners if it fits, else folded, else on a second row
	var free_l := left.end.x + 16.0
	var free_r := right.position.x - 16.0
	var vs := vitals.get_combined_minimum_size()
	if not _user_compact:
		if vs.x > free_r - free_l and not vitals.compact:
			_auto_compact = true
			vitals.set_compact(true)
			vs = vitals.get_combined_minimum_size()
		elif _auto_compact and vitals.compact:
			vitals.set_compact(false)
			var full := vitals.get_combined_minimum_size()
			if full.x > free_r - free_l:
				vitals.set_compact(true)
			else:
				_auto_compact = false
			vs = vitals.get_combined_minimum_size()
	vitals.size = vs
	if vs.x <= free_r - free_l:
		vitals.position = Vector2(clampf((screen.x - vs.x) * 0.5, free_l, free_r - vs.x), EDGE)
	else:
		vitals.position = Vector2((screen.x - vs.x) * 0.5, maxf(left.end.y, right.end.y) + 10.0)
	# the battery chip hangs just under the vitals bar, centred on it
	var es := energy.get_combined_minimum_size()
	energy.size = es
	energy.position = Vector2(roundf(vitals.position.x + (vs.x - es.x) * 0.5), vitals.position.y + vs.y + 6.0)
	# the colony balance chip under the battery chip, then the build vote card at the top right under the crew box
	var bs := balance_chip.get_combined_minimum_size()
	balance_chip.size = bs
	balance_chip.position = Vector2(roundf(vitals.position.x + (vs.x - bs.x) * 0.5), energy.position.y + es.y + 6.0)
	var top_band := balance_chip.position.y + bs.y
	hud.top_reserved = top_band
	if vote_card.visible:
		var cs := vote_card.get_combined_minimum_size()
		vote_card.size = cs
		vote_card.position = Vector2(screen.x - EDGE - cs.x, right.end.y + 12.0)
	# left column: goals under the time
	goals.size = goals.get_combined_minimum_size()
	goals.position = Vector2(EDGE, maxf(left.end.y + 12.0, top_band + 12.0 if vitals.position.x < goals.size.x + EDGE else 0.0))
	# right column: pop-ups. Owner 2026-11-14: the mini map above them is hidden for now.
	#var ms := map.get_combined_minimum_size()
	#map.size = ms
	#map.position = Vector2(screen.x - EDGE - ms.x, right.end.y + 12.0)
	toasts.size = Vector2(maxf(360.0, toasts.get_combined_minimum_size().x), toasts.get_combined_minimum_size().y)
	#toasts.position = Vector2(screen.x - EDGE - toasts.size.x, map.position.y + ms.y + 12.0)
	toasts.position = Vector2(screen.x - EDGE - toasts.size.x, right.end.y + 12.0)
	# bottom: dock in the middle, build chip above it, the mast camera bottom right, Mission Control bottom left
	var ds := dock.get_combined_minimum_size()
	dock.size = ds
	dock.position = Vector2((screen.x - ds.x) * 0.5, screen.y - EDGE - ds.y)
	var bcs := build_chip.get_combined_minimum_size()
	build_chip.size = bcs
	build_chip.position = Vector2((screen.x - bcs.x) * 0.5, dock.position.y - bcs.y - 10.0)
	if feed.visible:
		var fs := feed.get_combined_minimum_size()
		feed.size = fs
		feed.position = Vector2(screen.x - EDGE - fs.x, screen.y - EDGE - fs.y)
		var toast_room := feed.position.y - 12.0 - toasts.position.y
		toasts.visible = toast_room > 60.0
	else:
		toasts.visible = true
	if mission_control.visible:
		mission_control.fit(maxf(320.0, dock.position.x - EDGE - 16.0))
		var cs := mission_control.get_combined_minimum_size()
		mission_control.size = cs
		mission_control.position = Vector2(EDGE, screen.y - EDGE - cs.y)
		var clash := goals.position.y + goals.size.y > mission_control.position.y - 10.0
		if clash and goals.open and not _list_by_user:
			_goals_folded_for_mc = true
			goals.set_open(false)
	elif _goals_folded_for_mc:
		_goals_folded_for_mc = false
		goals.set_open(true)


# ---------------------------------------------------------------- the player's own choices (this machine only)

func _load() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if d is Dictionary:
		# UI overhaul: the calm look is the default. The choice is kept under "numbers" (true only after the player
		# pressed U for the numbers look; H is the help key since 2026-11-15); the old "compact" key is ignored, since older builds wrote false for everyone.
		_user_compact = not bool((d as Dictionary).get("numbers", false))
		vitals.set_compact(_user_compact)
		# Owner 2026-11-14: the goals card always starts in small mode (open).
		#goals.set_open(bool((d as Dictionary).get("goals_open", true)))


func _save() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"numbers": not _user_compact, "goals_open": goals.open if not _goals_folded_for_mc else true}))


## COLONY OVER (2026-11-15): the full screen with the reason; its buttons go to GameMain (main menu / load last save).
func _open_colony_over() -> void:
	if _over_screen_open or ui == null:
		return
	_over_screen_open = true
	var screen: UiPanel = ColonyOverScreenScript.new()
	ui.open(screen)
	screen.connect(&"main_menu_pressed", func() -> void: game.call(&"colony_over_main_menu"))
	screen.connect(&"load_last_save_pressed", func() -> void: game.call(&"colony_over_load_last_save"))
