class_name MissionHud
extends Control
## The mission-control HUD of the scout update, laid around GameHud's own corners (time and alerts top left, your crew
## member top right, the crosshair in the middle):
##   top centre     VitalsBar: electricity, oxygen, water, food, parts, science, ore. ⋯ (H) folds it, ? (F1) explains.
##                  Under it the battery chip: sun or moon, battery %, and while it drains how fast and how long it lasts.
##   left           GoalsCard under the time. Owner 2026-11-14, J cycles three looks: the goal list (a new game starts
##                  here) -> the big goals screen with the base map (scripts/ui/hud/goals_big_panel.gd, a UiRoot panel)
##                  -> the compact card ("GOALS 3/12" and a bar) -> the list ... J, Esc or ✕ on the big screen = compact.
##   right          the pop-ups (ToastStack) under your crew member. Owner 2026-11-14: the MiniMap is hidden for now.
##   lower left     MissionControlCard: storm warnings with how many more storms are lined up, scout reports with the
##                  mast camera's picture, a supply about to run out (K closes a message).
##   lower right    the scout's mast camera, live, while it is out on a trip.
##   bottom centre  the dock of keys (Build B, Power P, Cargo I, Crew C) and, by a sun tracker, "B Build here".
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

var _feed_tex: TextureRect
var _feed_status: Label
var _dock_build: Control
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
	_build_feed()
	_build_dock()
	_load()
	services.events.weather_changed.connect(_on_weather)
	PlayerInput.ensure_actions()
	refresh()


# ---------------------------------------------------------------- building

func _build_feed() -> void:
	feed = AstraStyle.panel(AstraStyle.glass(AstraStyle.RADIUS, 10, 8, true), "MastFeed")
	add_child(feed)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	feed.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	head.add_child(AstraStyle.label("●", 11, AstraStyle.DANGER, "Rec", true))
	var t := AstraStyle.label("MAST CAMERA · SCOUT-1", 11, AstraStyle.TEXT_2, "Title")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_feed_tex = TextureRect.new()
	_feed_tex.name = "Picture"
	_feed_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_feed_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_feed_tex.custom_minimum_size = Vector2(320, 180)
	col.add_child(_feed_tex)
	_feed_status = AstraStyle.label("", 12, AstraStyle.TEXT_2, "Status")
	_feed_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feed_status.custom_minimum_size.x = 320
	col.add_child(_feed_status)
	feed.visible = false


func _build_dock() -> void:
	dock = AstraStyle.panel(AstraStyle.glass(AstraStyle.RADIUS, 10, 6), "Dock")
	add_child(dock)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	dock.add_child(row)
	_dock_build = _dock_button(row, "⚒", "Build", &"build", "B", func() -> void: open_build())
	_dock_button(row, "⚡", "Power", &"power_view", "P", func() -> void: open_power())
	# Owner 2026-11-14: hidden for now (the big goals screen, J, has the map).
	#_dock_button(row, "▦", "Map", &"map", "M", func() -> void: _press(&"map"))
	_dock_button(row, "▤", "Cargo", &"inventory", "I", func() -> void: _press(&"inventory"))
	_dock_button(row, "☺", "Crew", &"crew", "C", func() -> void: _press(&"crew"))
	_dock_button(row, "?", "Science", &"vitals_help", "F1", func() -> void: open_science())
	build_chip = AstraStyle.panel(AstraStyle.pill(Color(AstraStyle.ACCENT, 0.92), AstraStyle.RADIUS_SM + 2, 14, 7), "BuildChip")
	add_child(build_chip)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 8)
	build_chip.add_child(h)
	h.add_child(AstraStyle.keycap("B", 12))
	h.add_child(AstraStyle.label("Build here · solar field", 15, AstraStyle.ACCENT_INK, "Text"))
	build_chip.visible = false


func _dock_button(row: HBoxContainer, symbol: String, word: String, action: StringName, key: String, run: Callable) -> Control:
	var b := PanelContainer.new()
	b.name = word
	b.add_theme_stylebox_override(&"panel", AstraStyle.pill(Color(0, 0, 0, 0), 12, 12, 4))
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.tooltip_text = "%s (%s)" % [PlayerInput.ACTION_NAMES.get(action, word), key]
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
	top.add_theme_constant_override(&"separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	top.add_child(AstraStyle.label(symbol, 19, AstraStyle.TEXT, "Symbol", true))
	top.add_child(AstraStyle.keycap(key, 9))
	var w := AstraStyle.label(word, 12, AstraStyle.TEXT_2, "Word")
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(w)
	return b


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
		vitals.toggle_compact()
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
		toasts.push("Dust storm warning: get ready! Mission Control has the details.", &"warn")
		mission_control.say("Dust storm coming", StormOutlook.warning_advice(services.state()), &"warn", null, "Weather · Jezero archive")
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
	mission_control.say("Scout report · %s" % String(rep.get("name", "")), body, &"good", pic, "Scout rover · mast camera")
	toasts.push("New scout report: the %s." % String(rep.get("name", "site")).to_lower(), &"good")


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
		mission_control.say("%s is very low" % String(r.name), "Down to %s. Press %s to see why." % [String(r.value), GameHud._key(&"power_view", "P")], &"danger")


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
		_feed_status.text = ScoutSystem.status_text(st)
	# by a sun tracker outside: B builds here
	_near_tracker = _tracker_near()
	build_chip.visible = _near_tracker != &""
	_dock_build.modulate.a = 1.0 if _near_tracker != &"" else 0.45
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
	var top_band := energy.position.y + es.y
	hud.top_reserved = top_band
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
	var bs := build_chip.get_combined_minimum_size()
	build_chip.size = bs
	build_chip.position = Vector2((screen.x - bs.x) * 0.5, dock.position.y - bs.y - 10.0)
	if feed.visible:
		var fs := feed.get_combined_minimum_size()
		feed.size = fs
		feed.position = Vector2(screen.x - EDGE - fs.x, screen.y - EDGE - fs.y)
		var toast_room := feed.position.y - 12.0 - toasts.position.y
		toasts.visible = toast_room > 60.0
	else:
		toasts.visible = true
	if mission_control.visible:
		var cs := mission_control.get_combined_minimum_size()
		cs.x = minf(cs.x, maxf(320.0, dock.position.x - EDGE - 16.0))
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
		# pressed H for the numbers look); the old "compact" key is ignored, since older builds wrote false for everyone.
		_user_compact = not bool((d as Dictionary).get("numbers", false))
		vitals.set_compact(_user_compact)
		# Owner 2026-11-14: the goals card always starts in small mode (open).
		#goals.set_open(bool((d as Dictionary).get("goals_open", true)))


func _save() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"numbers": not _user_compact, "goals_open": goals.open if not _goals_folded_for_mc else true}))
