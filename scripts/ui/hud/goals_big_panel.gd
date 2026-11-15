extends UiPanel
## The big goals screen (owner 2026-11-14): step 2 of the J cycle (list card -> this screen -> compact card -> list...).
## J, Esc or ✕ here closes it and the goals card goes to its compact look (MissionHud). It replaces the M blueprint map. Left: every goal (ColonyGoals.all) in big text with its tick, count and who
## can do it. Right: a top-down map of the base (BlueprintView, the same drawing as the blueprint map, without the
## station symbols) with you (▲) and, for the goal you click:
##   tapes goal       a gold dot on every tape not collected yet (cassette_anchor stations),
##   play goal        the tape player in the Command Room (cassette_player_anchor),
##   a repair goal    a ring on that broken part (data/broken_parts.json model_bounds centre, else its repair station):
##                    orange while broken, green with ✓ once fixed, with the room's name.
## A UiRoot panel like the others: the mouse is free, the player stops moving, Esc closes it.
## Loaded with preload (no class_name): MissionHud.open_goals_big().

const BROKEN_PARTS_PATH := "res://data/broken_parts.json"
## Plan area (plan x = Godot x, plan y = -Godot z) always in view: the base, its dome and the garden dome.
const BASE_VIEW := Rect2(-14.0, -38.0, 78.0, 60.0)
const GOLD := Color(1.0, 0.8, 0.22)

## task id -> Vector3 (Godot) centre of the broken model, read once.
static var _part_spots: Dictionary = {}

var map: GoalMap
## The goal shown on the map ("" = the first unfinished one).
var selected_id := ""

var _built := false
var _list: VBoxContainer
var _rows: Dictionary = {}           # goal id -> PanelContainer
var _goals: Array[Dictionary] = []
var _count: Label
var _caption: Label
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
	_count = AstraStyle.label("0/0", 20, AstraStyle.ACCENT, "Count")
	head.add_child(_count)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	head.add_child(AstraStyle.keycap(GameHud._key(&"goals", "J"), 13))
	head.add_child(AstraStyle.label("compact", 14, AstraStyle.TEXT_2))
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
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 0.8
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 6)
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
	map.setup(services)
	map.room_selected.connect(_on_room_clicked)
	right.add_child(map)
	_caption = AstraStyle.label("", 17, AstraStyle.TEXT, "Caption")
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.custom_minimum_size.x = 200
	right.add_child(_caption)
	var legend := HFlowContainer.new()
	legend.name = "Legend"
	legend.add_theme_constant_override(&"h_separation", 16)
	right.add_child(legend)
	for k: Array in [["▲", AstraStyle.TEXT, "You"], ["●", GOLD, "Tape to find"], ["▶", GOLD, "Tape player"],
			["◯", AstraStyle.ACCENT, "Broken: fix it here"], ["✓", AstraStyle.GOOD, "Fixed"]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 5)
		h.add_child(AstraStyle.label(String(k[0]), 15, k[1], "", true))
		h.add_child(AstraStyle.label(String(k[2]), 13, AstraStyle.TEXT_2))
		legend.add_child(h)
	var hint := AstraStyle.label("Click a goal to see it on the map. Drag the map to move it, use the mouse wheel to zoom.", 12, AstraStyle.TEXT_3, "Hint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 200
	right.add_child(hint)


func _row(g: Dictionary) -> PanelContainer:
	var id := String(g.id)
	var done := bool(g.done)
	var row := PanelContainer.new()
	row.name = id
	row.focus_mode = Control.FOCUS_ALL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.add_theme_stylebox_override(&"panel", _row_style(false))
	row.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			select(id)
			row.grab_focus()
			row.accept_event())
	row.focus_entered.connect(func() -> void: select(id))
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var tick := AstraStyle.label("✓" if done else "○", 24, AstraStyle.GOOD if done else AstraStyle.TEXT_3, "Tick", true)
	tick.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(tick)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(col)
	var text := AstraStyle.label(String(g.text), 18, AstraStyle.TEXT_2 if done else AstraStyle.TEXT, "Text")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 160
	col.add_child(text)
	var sub := _sub_line(g)
	if sub != "":
		var s := AstraStyle.label(sub, 13, AstraStyle.TEXT_3, "Sub")
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size.x = 160
		col.add_child(s)
	if not done and String(g.get("label", "")) != "":
		var m := AstraStyle.Meter.new(AstraStyle.ACCENT, 4.0)
		m.share = float(g.fraction)
		col.add_child(m)
	var lab := AstraStyle.label("done" if done else String(g.get("label", "")), 16, AstraStyle.GOOD if done else AstraStyle.TEXT_2, "Label")
	lab.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(lab)
	return row


func _row_style(selected: bool) -> StyleBoxFlat:
	var s := AstraStyle.pill(Color(1, 1, 1, 0.09) if selected else Color(1, 1, 1, 0.03), AstraStyle.RADIUS_SM, 12, 8,
		AstraStyle.ACCENT if selected else AstraStyle.LINE)
	if selected:
		s.set_border_width_all(2)
	return s


static func _sub_line(g: Dictionary) -> String:
	match String(g.get("kind", "")):
		"tapes_found":
			return "Gold lines on the floor lead to them."
		"tapes_played":
			return "At the tape player in the Command Room."
		"fix":
			var role := String(g.get("role", ""))
			return "%s · %s" % [String(g.get("room", "")), "anyone can do it" if role == "anyone" or role == "" else "only the %s can do it" % role]
	return ""


# ---------------------------------------------------------------- refresh and selection

func refresh() -> void:
	if not _built or services == null or not services.has_game():
		return
	var st := services.state()
	_goals = ColonyGoals.all(st)
	var n := ColonyGoals.done_count(st)
	_count.text = "%d/%d done" % [n.x, n.y]
	var sig := JSON.stringify(_goals)
	if sig != _sig:
		_sig = sig
		var vp := get_viewport()
		var had_focus := vp != null and vp.gui_get_focus_owner() != null and _list.is_ancestor_of(vp.gui_get_focus_owner())
		for c in _list.get_children():
			_list.remove_child(c)
			c.queue_free()
		_rows.clear()
		for g: Dictionary in _goals:
			var row := _row(g)
			_list.add_child(row)
			_rows[String(g.id)] = row
		if _goal(selected_id).is_empty():
			selected_id = _first_open_id()
		if had_focus and _rows.has(selected_id):
			(_rows[selected_id] as Control).grab_focus.call_deferred()
	if _goal(selected_id).is_empty():
		selected_id = _first_open_id()
	_show_selected(st)


## Shows goal `id` on the map.
func select(id: String) -> void:
	if id == selected_id or _goal(id).is_empty():
		return
	selected_id = id
	if services != null and services.has_game():
		_show_selected(services.state())


func _show_selected(st: ColonyState) -> void:
	for id: String in _rows:
		(_rows[id] as PanelContainer).add_theme_stylebox_override(&"panel", _row_style(id == selected_id))
	var g := _goal(selected_id)
	map.markers = markers_for(st, g)
	_caption.text = caption_for(st, g)
	if _fitted_for != selected_id:
		_fitted_for = selected_id
		map.selected_zone = _zone_of(g)
		map.fit_plan(_fit_rect(map.markers))
	map.queue_redraw()


func _goal(id: String) -> Dictionary:
	for g: Dictionary in _goals:
		if String(g.id) == id:
			return g
	return {}


func _first_open_id() -> String:
	for g: Dictionary in _goals:
		if not bool(g.done):
			return String(g.id)
	return String(_goals[0].id) if not _goals.is_empty() else ""


func _on_room_clicked(zone: String) -> void:
	if zone == "" or zone == ColonyZones.EXTERIOR:
		_caption.text = "That is outside the base."
	else:
		_caption.text = "That is the %s." % zone


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


## The words under the map for a goal.
func caption_for(st: ColonyState, g: Dictionary) -> String:
	if g.is_empty():
		return ""
	var done := bool(g.done)
	match String(g.get("kind", "")):
		"tapes_found":
			var left := TutorialSystem.tape_count() - TutorialSystem.tapes_found(st)
			if done or left <= 0:
				return "✓ You found every tape!"
			return "%d tape%s still to find. The gold dots show where. Follow the gold lines on the floor." % [left, "" if left == 1 else "s"]
		"tapes_played":
			if done:
				return "✓ Every tape is played."
			return "Take your tapes to the tape player (▶) in the Command Room and play them: %d/%d played." % [
				TutorialSystem.tapes_played(st), TutorialSystem.tape_count()]
		"fix":
			if done:
				return "✓ Fixed! %s." % String(g.get("room", ""))
			var role := String(g.get("role", ""))
			var who := "Anyone can do it." if role == "anyone" or role == "" else "Only the %s can do it." % role
			return "Go to the orange ring in the %s. %s" % [String(g.get("room", "")), who]
	return ("✓ " if done else "") + String(g.text)


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
	if not out.any(func(m: Dictionary) -> bool: return String(m.kind) == "player"):
		var at: Variant = player_spot()
		if at is Vector3:
			out.append({"at": BlueprintView.godot_to_plan(at as Vector3), "kind": "player", "done": false, "text": "Tape player"})
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
	var markers: Array = []
	var _fit := Rect2()

	func _ready() -> void:
		set_process(true)

	func _process(_delta: float) -> void:
		if not markers.is_empty() and is_visible_in_tree():
			queue_redraw()

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
		var sym := AstraStyle.symbol_font()
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
		var r_dot := maxf(7.0, fs * 0.45)
		for m: Dictionary in markers:
			var at := world_to_view(m.at as Vector2)
			match String(m.kind):
				"tape":
					draw_circle(at, r_dot + 4.0 * pulse, Color(GOLD, 0.25))
					draw_circle(at, r_dot, GOLD)
					draw_arc(at, r_dot, 0.0, TAU, 24, PLAN_COLOURS["outline"], 2.0, true)
				"player":
					var col: Color = AstraStyle.GOOD if bool(m.done) else GOLD
					var r := r_dot + 5.0
					draw_circle(at, r, Color(0, 0, 0, 0.55))
					draw_arc(at, r, 0.0, TAU, 32, col, 3.0, true)
					if not bool(m.done):
						draw_arc(at, r + 4.0 + 6.0 * pulse, 0.0, TAU, 40, Color(col, 0.6 * (1.0 - pulse)), 2.0, true)
					_text(sym, at, "✓" if bool(m.done) else "▶", fs, col)
					_text(font, at + Vector2(0, -r - fs * 0.7), String(m.text), fs, col)
				"fix":
					var col2: Color = AstraStyle.GOOD if bool(m.done) else AstraStyle.ACCENT
					var r2 := r_dot + 7.0
					draw_circle(at, r2, Color(0, 0, 0, 0.5))
					draw_arc(at, r2, 0.0, TAU, 40, col2, 4.0, true)
					if not bool(m.done):
						draw_arc(at, r2 + 4.0 + 8.0 * pulse, 0.0, TAU, 48, Color(col2, 0.7 * (1.0 - pulse)), 2.5, true)
					_text(sym, at, "✓" if bool(m.done) else "!", fs, col2)
					if String(m.text) != "":
						_text(font, at + Vector2(0, -r2 - fs * 0.75), String(m.text), fs, col2)

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
