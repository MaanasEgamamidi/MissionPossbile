extends UiPanel
## The big goals screen (owner 2026-11-14): step 2 of the J cycle (goals card -> this screen -> compact card -> card...).
## J, Esc or ✕ here closes it and the goals card goes to its compact look (MissionHud). It replaces the M blueprint map.
## Left: every goal (ColonyGoals.ordered: open ones first, finished ones dimmed at the bottom), one large row each:
##   status mark (ring / green tick) + pictogram + short title + progress pips for a counted goal + a badge of WHO can
##   do it (the specialist's symbol on their crew colour, two people for everyone; a padlock on it when the job belongs
##   to another crew member than this machine's). No sentences: the room is shown by the map.
## Right: a top-down map of the base (BlueprintView, the same drawing as the blueprint map, without the
## station symbols) with you (▲) and, for the goal you pick (click, or Up / Down):
##   tapes goal       a gold dot on every tape not collected yet (cassette_anchor stations),
##   play goal        the tape player in the Command Room (cassette_player_anchor),
##   a repair goal    a ring on that broken part (data/broken_parts.json model_bounds centre, else its repair station):
##                    orange while broken, green with ✓ once fixed, with the room's name.
## Under the map: ONE short line about the picked goal (with its who badge) and a legend drawn with the map's own marks.
## A UiRoot panel like the others: the mouse is free, the player stops moving, Esc closes it.
## Loaded with preload (no class_name): MissionHud.open_goals_big(). Pictures: scripts/ui/hud/goal_art.gd.

const GoalArt := preload("res://scripts/ui/hud/goal_art.gd")
const BROKEN_PARTS_PATH := "res://data/broken_parts.json"
## Plan area (plan x = Godot x, plan y = -Godot z) always in view: the base, its dome and the garden dome.
const BASE_VIEW := Rect2(-14.0, -38.0, 78.0, 60.0)
const GOLD := Color(1.0, 0.8, 0.22)
## The legend: [map mark, shown as done, one word].
const LEGEND := [["you", false, "You"], ["tape", false, "Tape"], ["player", false, "Play"], ["fix", false, "Broken"], ["fix", true, "Fixed"]]

## task id -> Vector3 (Godot) centre of the broken model, read once.
static var _part_spots: Dictionary = {}

var map: GoalMap
## The goal shown on the map ("" = the goal the goals card shows, else the first unfinished one).
var selected_id := ""

var _built := false
var _list: VBoxContainer
var _rows: Dictionary = {}           # goal id -> PanelContainer
var _goals: Array[Dictionary] = []
var _count: Label
## The small green tick in front of the count.
var _tally: Control
## The thin bar beside the count: done / total.
var _total: AstraStyle.Meter
var _caption: Label
## The who badge in front of the line under the map (repair goals only).
var _caption_who: Control
var _sig := ""
var _fitted_for := "-"


func setup(p_services: GameServices) -> void:
	if _built:
		return
	super.setup(p_services)
	_built = true
	name = "GoalsBig"
	keeps_world_visible = true
	viewport_fraction = Vector2(0.95, 0.94)
	add_theme_stylebox_override(&"panel", AstraStyle.glass(AstraStyle.RADIUS, 22, 16, true))
	_build()
	refresh()


func panel_title() -> String:
	return "Goals"


func first_focus() -> Control:
	var row: Control = _rows.get(selected_id)
	return row if row != null else super.first_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not is_inside_tree():
		return
	# J again: on to the compact goals card (never in the frame J opened this screen). Closing takes this panel out of
	# the tree at once, so the key is marked handled first, on a viewport held from before the close.
	if event.is_action_pressed(&"goals") and int(get_meta(UiRoot.OPENED_FRAME_META, -1)) < Engine.get_process_frames():
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
		close_requested.emit()


# ---------------------------------------------------------------- building

func _build() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 12)
	add_child(col)
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override(&"separation", 10)
	col.add_child(head)
	head.add_child(AstraStyle.label("GOALS", 24, AstraStyle.TEXT, "Title"))
	_tally = GoalArt.Status.new(true, 22.0 * UiTheme.text_scale())
	head.add_child(_tally)
	_count = AstraStyle.label("0/0", 20, AstraStyle.GOOD, "Count")
	head.add_child(_count)
	_total = AstraStyle.Meter.new(AstraStyle.GOOD, 6.0)
	_total.name = "Total"
	_total.custom_minimum_size = Vector2(120, 6)
	_total.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_total)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	head.add_child(AstraStyle.keycap(GameHud._key(&"goals", "J"), 13))
	head.add_child(AstraStyle.keycap(GameHud._key(&"back", "Esc"), 13))
	head.add_child(AstraStyle.label("close", 14, AstraStyle.TEXT_2))
	var close := AstraStyle.flat_button("✕", 20, AstraStyle.TEXT_2)
	close.name = "Close"
	close.tooltip_text = "Close"
	close.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close)

	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 18)
	col.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.name = "GoalList"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 0.8
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 4)
	scroll.add_child(_list)

	var right := VBoxContainer.new()
	right.name = "MapSide"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.2
	right.add_theme_constant_override(&"separation", 8)
	body.add_child(right)
	map = GoalMap.new()
	map.name = "Map"
	map.show_stations = false
	map.show_items = false
	map.custom_minimum_size = Vector2(320, 240)
	map.tooltip_text = "Drag to move. Mouse wheel to zoom."
	map.setup(services)
	map.room_selected.connect(_on_room_clicked)
	right.add_child(map)
	# ONE short line about the picked goal, with its who badge in front.
	var foot := HBoxContainer.new()
	foot.name = "Foot"
	foot.add_theme_constant_override(&"separation", 10)
	right.add_child(foot)
	_caption_who = GoalArt.Who.new("", 28.0 * UiTheme.text_scale())
	_caption_who.name = "CaptionWho"
	_caption_who.visible = false
	foot.add_child(_caption_who)
	_caption = AstraStyle.label("", 18, AstraStyle.TEXT, "Caption")
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.custom_minimum_size.x = 200
	_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_caption)
	# The legend: the map's own marks (the same drawing code), one word each.
	var legend := HFlowContainer.new()
	legend.name = "Legend"
	legend.add_theme_constant_override(&"h_separation", 18)
	right.add_child(legend)
	for entry: Array in LEGEND:
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 6)
		h.add_child(GoalArt.Mark.new(String(entry[0]), bool(entry[1]), 22.0 * UiTheme.text_scale()))
		h.add_child(AstraStyle.label(String(entry[2]), 14, AstraStyle.TEXT_2))
		legend.add_child(h)


## Sizes of the rows follow the height of the screen: readable from a couch on a big screen, still eleven rows without
## scrolling on a small one. 1.0 at 720 units of height, up to 1.4.
func layout_scale() -> float:
	var vp := get_viewport() if is_inside_tree() else null
	var h := vp.get_visible_rect().size.y if vp != null else 720.0
	return clampf(h / 720.0, 1.0, 1.4)


## Specialty of the crew member this machine's player controls, or "".
func local_specialty() -> String:
	if services == null or not services.has_game():
		return ""
	var me := services.local_character()
	return String(me.specialty) if me != null else ""


## One goal: status mark, pictogram, short title, pips for a counted goal, who badge.
func _row(g: Dictionary, k: float, spec: String) -> PanelContainer:
	var id := String(g.id)
	var done := bool(g.done)
	var kind := String(g.get("kind", ""))
	var ks := k * UiTheme.text_scale()
	var row := PanelContainer.new()
	row.name = id
	row.focus_mode = Control.FOCUS_ALL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.add_theme_stylebox_override(&"panel", _row_style(false, false, k))
	row.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			select(id)
			row.grab_focus()
			row.accept_event())
	row.focus_entered.connect(func() -> void:
		select(id)
		_style_rows())
	row.focus_exited.connect(_style_rows)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", roundi(10.0 * k))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var tick := GoalArt.Status.new(done, 26.0 * ks)
	tick.name = "Tick"
	h.add_child(tick)
	var tint: Color = AstraStyle.GOOD if done else (GOLD if kind in ["tapes_found", "tapes_played"] else AstraStyle.ACCENT)
	var icon := GoalArt.Icon.new(GoalArt.icon_of(g), 38.0 * ks, tint)
	icon.name = "Icon"
	h.add_child(icon)
	var text := AstraStyle.label(String(g.text), 20.0 * k, AstraStyle.TEXT, "Text")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 120
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(text)
	if not done and int(g.get("need", 0)) > 0:
		var pips := GoalArt.Pips.new(int(g.have), int(g.need), 11.0 * ks, tint)
		pips.name = "Pips"
		h.add_child(pips)
		h.add_child(AstraStyle.label(String(g.get("label", "")), 16.0 * k, AstraStyle.TEXT_2, "Label"))
	elif not done and String(g.get("label", "")) != "":
		h.add_child(AstraStyle.label(String(g.get("label", "")), 16.0 * k, AstraStyle.TEXT_2, "Label"))
	var who := GoalArt.Who.new(String(g.get("spec", "")), 34.0 * ks, not done and not ColonyGoals.can_do(g, spec))
	who.name = "Who"
	h.add_child(who)
	if done:
		# finished: ticked, dimmed and at the bottom of the list
		h.modulate = Color(1, 1, 1, 0.7 if UiTheme.is_high_contrast() else 0.5)
	return row


## A row's box: plain, picked (orange outline) or holding the keyboard focus (thick outline in the focus colour).
func _row_style(selected: bool, focused: bool, k := 1.0) -> StyleBoxFlat:
	var strong := UiTheme.is_high_contrast()
	var bg := Color(1, 1, 1, 0.12 if selected else 0.035)
	if strong:
		bg = Color(0.2, 0.2, 0.2, 1.0) if selected else Color(0.05, 0.05, 0.05, 1.0)
	var s := AstraStyle.pill(bg, AstraStyle.RADIUS_SM, roundi(12.0 * k), roundi(4.0 * k),
		AstraStyle.ACCENT if selected else (AstraStyle.LINE_STRONG if strong else AstraStyle.LINE))
	if focused:
		s.border_color = UiTheme.palette().focus
		s.set_border_width_all(3)
	elif selected:
		s.set_border_width_all(2)
	return s


func _style_rows() -> void:
	var k := layout_scale()
	for id: String in _rows:
		var row := _rows[id] as PanelContainer
		if is_instance_valid(row):
			row.add_theme_stylebox_override(&"panel", _row_style(id == selected_id, row.has_focus(), k))


# ---------------------------------------------------------------- refresh and selection

func refresh() -> void:
	if not _built or services == null or not services.has_game():
		return
	var st := services.state()
	_goals = ColonyGoals.ordered(st)
	var n := ColonyGoals.done_count(st)
	_count.text = "%d/%d" % [n.x, n.y]
	# With a single goal (tapes first) its own pips say it all.
	_count.visible = n.y > 1
	_total.visible = n.y > 1
	_tally.visible = n.y > 1
	_total.share = float(n.x) / float(n.y) if n.y > 0 else 0.0
	var k := layout_scale()
	var spec := local_specialty()
	# Rows are rebuilt only when what they show changes: the goals, who is looking, the screen or the text settings.
	var sig := JSON.stringify([_goals, spec, k, UiTheme.text_scale(), UiTheme.is_high_contrast()])
	if sig != _sig:
		_sig = sig
		var vp := get_viewport()
		var had_focus := vp != null and vp.gui_get_focus_owner() != null and _list.is_ancestor_of(vp.gui_get_focus_owner())
		for c in _list.get_children():
			_list.remove_child(c)
			c.queue_free()
		_rows.clear()
		for g: Dictionary in _goals:
			var row := _row(g, k, spec)
			_list.add_child(row)
			_rows[String(g.id)] = row
		if _goal(selected_id).is_empty():
			selected_id = _first_open_id()
		if had_focus and _rows.has(selected_id):
			(_rows[selected_id] as Control).grab_focus.call_deferred()
	if _goal(selected_id).is_empty():
		selected_id = _first_open_id()
	_show_selected(st)


func _notification(what: int) -> void:
	# The rows' size follows the screen's height (layout_scale): build them again when the screen changes.
	if what == NOTIFICATION_RESIZED and _built and is_inside_tree():
		refresh.call_deferred()


## Shows goal `id` on the map.
func select(id: String) -> void:
	if id == selected_id or _goal(id).is_empty():
		return
	selected_id = id
	if services != null and services.has_game():
		_show_selected(services.state())


func _show_selected(st: ColonyState) -> void:
	_style_rows()
	var g := _goal(selected_id)
	map.goal_markers = markers_for(st, g)
	_caption.text = caption_for(st, g)
	_caption_who.visible = String(g.get("kind", "")) == "fix"
	_caption_who.set(&"spec", String(g.get("spec", "")))
	_caption_who.set(&"locked", not bool(g.get("done", false)) and not ColonyGoals.can_do(g, local_specialty()))
	_caption_who.queue_redraw()
	if _fitted_for != selected_id:
		_fitted_for = selected_id
		map.selected_zone = _zone_of(g)
		map.fit_plan(_fit_rect(map.goal_markers))
	map.queue_redraw()


func _goal(id: String) -> Dictionary:
	for g: Dictionary in _goals:
		if String(g.id) == id:
			return g
	return {}


## The goal picked when the screen opens: the one the goals card shows (the first open goal this crew member can
## do), else the first open one.
func _first_open_id() -> String:
	if services != null and services.has_game():
		var next := ColonyGoals.next(services.state(), local_specialty())
		if not next.is_empty() and not bool(next.done) and not _goal(String(next.id)).is_empty():
			return String(next.id)
	for g: Dictionary in _goals:
		if not bool(g.done):
			return String(g.id)
	return String(_goals[0].id) if not _goals.is_empty() else ""


func _on_room_clicked(zone: String) -> void:
	_caption_who.visible = false
	if zone == "" or zone == ColonyZones.EXTERIOR:
		_caption.text = "Outside the base"
	else:
		_caption.text = zone


## The room outlined on the map for a goal.
static func _zone_of(g: Dictionary) -> String:
	match String(g.get("kind", "")):
		"tapes_played":
			return "Command Room"
		"fix":
			var task := String(g.get("task", ""))
			if RepairCatalog.TASKS.has(task):
				var room: Dictionary = RepairCatalog.ROOMS.get(String((RepairCatalog.TASKS[task] as Array)[0]), {})
				var zones: Array = room.get("zones", [])
				if not zones.is_empty():
					return String(zones[0])
	return ""


## The ONE short line under the map for a goal.
func caption_for(st: ColonyState, g: Dictionary) -> String:
	if g.is_empty():
		return ""
	var done := bool(g.done)
	match String(g.get("kind", "")):
		"tapes_found":
			var left := TutorialSystem.tape_count() - TutorialSystem.tapes_found(st)
			if done or left <= 0:
				return "You found every tape!"
			return "%d tape%s to find. Follow the gold lines." % [left, "" if left == 1 else "s"]
		"tapes_played":
			if done:
				return "Every tape is played!"
			return "Use the tape player in the Command Room."
		"fix":
			var room := String(g.get("room", ""))
			if done:
				return "%s · fixed!" % room
			var role := String(g.get("role", ""))
			if role == "anyone" or role == "":
				return "%s · everyone can do it" % room
			if ColonyGoals.can_do(g, local_specialty()):
				return "%s · a job for you, %s" % [room, role]
			return "%s · needs the %s" % [room, role]
	return ("Done! " if done else "") + String(g.text)


## Map markers for a goal: [{"at": plan Vector2, "kind": "tape" | "player" | "fix", "done": bool, "text": String}].
func markers_for(st: ColonyState, g: Dictionary) -> Array:
	var out: Array = []
	if st == null or g.is_empty():
		return out
	match String(g.get("kind", "")):
		"tapes_found":
			for id: String in st.stations:
				var rec: Dictionary = st.stations[id]
				if String(rec.get("kind", "")) != "cassette_anchor":
					continue
				var cid := String(rec.get("cassette_id", id))
				if CassetteCatalog.collected(st, cid):
					continue
				var title := String((CassetteCatalog.TAPES.get(cid, {}) as Dictionary).get("title", ""))
				out.append({"at": _plan(rec.get("prop_position", rec.get("position", [0, 0, 0]))), "kind": "tape", "done": false, "text": title})
		"tapes_played":
			var spot: Variant = player_spot()
			if spot is Vector3:
				out.append({"at": BlueprintView.godot_to_plan(spot as Vector3), "kind": "player", "done": bool(g.done), "text": "Tape player"})
		"fix":
			var task := String(g.get("task", ""))
			var spot: Variant = part_spot(task)
			if spot == null:
				for id: String in st.stations:
					var rec: Dictionary = st.stations[id]
					if String(rec.get("kind", "")) == "repair_task" and String(rec.get("task_id", "")) == task:
						spot = CharacterState._v3(rec.get("position", [0, 0, 0]))
						break
			if spot is Vector3:
				out.append({"at": BlueprintView.godot_to_plan(spot as Vector3), "kind": "fix", "done": bool(g.done), "text": String(g.get("room", ""))})
	# Owner 2026-11-14: the tape player is always on the map (a landmark in the Command Room), whatever goal is picked.
	# As a landmark it carries no words (the legend names its mark), so it never covers the picked goal's own name.
	if not out.any(func(m: Dictionary) -> bool: return String(m.kind) == "player"):
		var at: Variant = player_spot()
		if at is Vector3:
			out.append({"at": BlueprintView.godot_to_plan(at as Vector3), "kind": "player", "done": false, "text": ""})
	return out


## Where the Command Room tape player stands (data/stations_repairs.json, its prop spot), Godot metres, or null.
static func player_spot() -> Variant:
	for entry: Dictionary in StationCatalog.extra_entries():
		if String(entry.get("kind", "")) == "cassette_player_anchor" or String(entry.get("id", "")) == CassetteCatalog.PLAYER_ID:
			return CharacterState._v3(entry.get("prop_position", entry.get("position", [0, 0, 0])))
	return null


## The middle of a broken part (data/broken_parts.json model_bounds centre, Godot metres), or null.
static func part_spot(task_id: String) -> Variant:
	if _part_spots.is_empty() and FileAccess.file_exists(BROKEN_PARTS_PATH):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(BROKEN_PARTS_PATH))
		if data is Dictionary:
			for p: Variant in (data as Dictionary).get("parts", []):
				if not p is Dictionary:
					continue
				var d := p as Dictionary
				var b: Dictionary = d.get("model_bounds", d.get("bounds", {}))
				var c: Variant = b.get("center", d.get("spot", null))
				if c is Array and (c as Array).size() >= 3:
					_part_spots[String(d.get("task_id", ""))] = Vector3(float(c[0]), float(c[1]), float(c[2]))
	return _part_spots.get(task_id, null)


func _fit_rect(markers: Array) -> Rect2:
	var r := BASE_VIEW
	for m: Dictionary in markers:
		r = r.expand(m.at as Vector2)
	var me := services.local_character() if services != null else null
	if me != null:
		r = r.expand(BlueprintView.godot_to_plan(me.position))
	return r.grow(4.0)


static func _plan(a: Variant) -> Vector2:
	return BlueprintView.godot_to_plan(CharacterState._v3(a))


# ---------------------------------------------------------------- the map

## The blueprint plan with bigger room names and the selected goal's markers on top.
class GoalMap extends BlueprintView:
	const Art := preload("res://scripts/ui/hud/goal_art.gd")
	var goal_markers: Array = []
	var _fit := Rect2()

	func _ready() -> void:
		set_process(true)

	func _process(_delta: float) -> void:
		if not goal_markers.is_empty() and is_visible_in_tree() and not reduce_motion():
			queue_redraw()

	## True when the player asked for less motion (UiRoot's settings): the rings around the marks stand still.
	func reduce_motion() -> bool:
		var node: Node = get_parent()
		while node != null:
			var settings: Variant = node.get(&"settings") if &"settings" in node else null
			if settings is GameSettings:
				return (settings as GameSettings).reduce_motion
			node = node.get_parent()
		return false

	## Zooms and moves the plan so plan rect `r` fills the view.
	func fit_plan(r: Rect2) -> void:
		_fit = r
		_apply_fit()

	func _apply_fit() -> void:
		if size.x <= 1.0 or size.y <= 1.0 or _fit.size.x <= 0.0 or _fit.size.y <= 0.0:
			return
		zoom = 1.0
		pan = Vector2.ZERO
		var base := plan_scale()
		var want := minf(size.x / _fit.size.x, size.y / _fit.size.y) * 0.97
		zoom = clampf(want / maxf(base, 1e-6), ZOOM_MIN, ZOOM_MAX)
		centre_on(_fit.get_center())

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_apply_fit()

	func _draw() -> void:
		super()
		var font := get_theme_default_font()
		var fs := get_theme_default_font_size()
		_room_names(font, fs)
		var pulse := -1.0 if reduce_motion() else 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
		var r_dot := maxf(7.0, fs * 0.45)
		# The marks are GoalArt's: the legend under the map draws the very same ones.
		for m: Dictionary in goal_markers:
			var at := world_to_view(m.at as Vector2)
			var done := bool(m.done)
			match String(m.kind):
				"tape":
					Art.draw_marker(self, "tape", at, r_dot, false, pulse)
				"player":
					var r := r_dot + 5.0
					Art.draw_marker(self, "player", at, r, done, pulse if String(m.text) != "" else -1.0)
					if String(m.text) != "":
						_text(font, at + Vector2(0, -r - fs * 0.7), String(m.text), fs, AstraStyle.GOOD if done else GOLD)
				"fix":
					var r2 := r_dot + 7.0
					Art.draw_marker(self, "fix", at, r2, done, pulse)
					if String(m.text) != "":
						_text(font, at + Vector2(0, -r2 - fs * 0.75), String(m.text), fs, AstraStyle.GOOD if done else AstraStyle.ACCENT)

	## Room names the blueprint left out because they did not fit: smaller, or on two lines.
	func _room_names(font: Font, fs: int) -> void:
		var colour := get_theme_color(&"font_color", &"Label")
		var small := maxi(10, int(fs * 0.72))
		for room: Dictionary in rooms():
			var room_name := String(room.name)
			var rect := room_rect(room_name)
			var full := font.get_string_size(room_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			if full.x < rect.size.x - 4.0 and full.y * 2.2 < rect.size.y:
				continue        # BlueprintView wrote it already
			var one := font.get_string_size(room_name, HORIZONTAL_ALIGNMENT_LEFT, -1, small)
			if one.x < rect.size.x - 4.0 and one.y * 1.2 < rect.size.y:
				_text(font, rect.get_center(), room_name, small, colour)
				continue
			var words := room_name.split(" ", false, 1)
			if words.size() == 2:
				var w0 := font.get_string_size(words[0], HORIZONTAL_ALIGNMENT_LEFT, -1, small)
				var w1 := font.get_string_size(words[1], HORIZONTAL_ALIGNMENT_LEFT, -1, small)
				if maxf(w0.x, w1.x) < rect.size.x - 4.0 and one.y * 2.3 < rect.size.y:
					_text(font, rect.get_center() - Vector2(0, one.y * 0.55), words[0], small, colour)
					_text(font, rect.get_center() + Vector2(0, one.y * 0.55), words[1], small, colour)
