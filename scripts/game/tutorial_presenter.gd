class_name TutorialPresenter
extends Node
## Scene side of the whiteboard tutorial (2026-11-14): the Mission Control tracker on the HUD (owner 2026-11-14: hidden for
## now, the goals card and its big J screen show the same list; Mission Control's lines still arrive as pop-ups and in
## the journal, and a due hint shows as a HUD message), hints, the specialist
## cues, the colony journal (L) and the tutorial station lock on screen. It only reads state.campaign and sends
## ordinary requests; the host's TutorialSystem decides. Two host-side duties live here because they belong to the
## real game, not to simulation harnesses:
##   * tutorial mode: on the host, a colony whose mode is not decided yet gets it from GameConfig.tutorial_start_outside
##     (TutorialSystem.begin_tutorial_mode), once.
##   * a station panel opened while that station is locked (TutorialLock) is closed at once with a plain message; the
##     host refuses its actions anyway.
## Hints: one appears after `hint_after_s` real seconds (data/tutorial.json) without progress, another every
## `hint_repeat_s`, and one more each time the player asks (N). Progress resets the count. Pausing stops the clock.
## With four players the texts never ask anyone to switch crew.
## Wiring (GameMain._begin_play, after the HUD exists):
##   var tutorial := TutorialPresenter.new(); tutorial.name = "TutorialPresenter"; add_child(tutorial)
##   tutorial.setup(world, services, self)

const TutorialLock := preload("res://scripts/session/tutorial_lock.gd")
## Input actions used when PlayerInput has them; otherwise the N and L keys.
const HINT_ACTION := &"tutorial_hint"
const JOURNAL_ACTION := &"journal"
const REFRESH_SECONDS := 0.25

var services: GameServices
## The GameMain (or a stand-in with `hud` and `ui`), or null.
var game: Node
## Owner 2026-11-14: the tracker is hidden for now, so this stays null.
var hud_widget: TutorialHud
## Real seconds without tutorial progress (only while the game runs).
var idle_seconds := 0.0
## Hints asked for since the last progress.
var requested_hints := 0
## Station panels closed by the tutorial lock (for tests).
var closed_locked_panels := 0

var _progress_key := ""
var _refresh_left := 0.0
var _last_view := {}
var _ui: UiRoot
## Hints already shown as a HUD message for the current progress (while the tracker is hidden).
var _hints_said := 0


func setup(_world: Node3D, p_services: GameServices, p_game: Node) -> void:
	services = p_services
	game = p_game
	name = "TutorialPresenter"
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Owner 2026-11-14: hidden for now ("missions also fit into goals"): the goals card shows the tapes and broken spots.
	#hud_widget = TutorialHud.new()
	#hud_widget.name = "TutorialHud"
	#hud_widget.setup(services)
	#var hud: Variant = game.get("hud") if game != null else null
	#if hud is Node and is_instance_valid(hud):
	#	(hud as Node).add_child(hud_widget)
	#else:
	#	var layer := CanvasLayer.new()
	#	layer.name = "TutorialLayer"
	#	layer.layer = 10
	#	add_child(layer)
	#	layer.add_child(hud_widget)
	var ui: Variant = game.get("ui") if game != null else null
	if ui is UiRoot:
		_ui = ui as UiRoot
		_ui.menu_mode_changed.connect(_on_menu_mode_changed)
	decide_mode()
	refresh()


func _process(delta: float) -> void:
	if services == null or not services.has_game():
		return
	decide_mode()
	if not services.session.paused:
		idle_seconds += delta
	var key := progress_key(services.state())
	if key != _progress_key:
		_progress_key = key
		idle_seconds = 0.0
		requested_hints = 0
		_hints_said = 0
		_refresh_left = 0.0
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_SECONDS
		refresh()


## Host: switches tutorial mode on for this colony once (from the game's settings). Clients only read it.
func decide_mode() -> void:
	if services == null or not services.has_game() or not services.is_authority():
		return
	var t: Variant = services.state().campaign.get("tutorial", null)
	if t is Dictionary and (t as Dictionary).has("locks") and int((t as Dictionary).get("flow", 0)) == TutorialSystem.FLOW:
		return
	TutorialSystem.begin_tutorial_mode(services.state(), services.config.tutorial_start_outside)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	if _ui != null and not _ui.gameplay_has_focus():
		return
	if _pressed(event, HINT_ACTION, KEY_N):
		request_hint()
		get_viewport().set_input_as_handled()
	elif _pressed(event, JOURNAL_ACTION, KEY_L):
		open_journal()
		get_viewport().set_input_as_handled()


static func _pressed(event: InputEvent, action: StringName, fallback: Key) -> bool:
	if InputMap.has_action(action):
		return event.is_action_pressed(action)
	var k := event as InputEventKey
	return k.keycode == fallback or k.physical_keycode == fallback


## Shows one more hint now (N, or the journal's hint button).
func request_hint() -> void:
	requested_hints += 1
	refresh()


## Opens the colony journal (Mission Control's log, the tutorial, the colony goal and the optional story).
func open_journal() -> void:
	if _ui != null:
		var panel := StoryLogPanel.new()
		panel.presenter = self
		_ui.open(panel)


## A station panel just opened: while that station is locked, close it again and say why.
func _on_menu_mode_changed(open: bool) -> void:
	if not open or _ui == null or services == null or not services.has_game():
		return
	var panel := _ui.top()
	if panel == null or not panel.has_meta(&"station_surface") or not panel.has_meta(&"station_id"):
		return
	var record: Dictionary = services.state().stations.get(String(panel.get_meta(&"station_id")), {})
	if TutorialLock.station_usable(services.state(), record):
		return
	closed_locked_panels += 1
	_close_locked.call_deferred(panel, TutorialLock.message_for(services.state(), record))


func _close_locked(panel: UiPanel, text: String) -> void:
	if _ui != null and is_instance_valid(panel) and _ui.top() == panel:
		_ui.close_top()
	var hud: Variant = game.get("hud") if game != null else null
	if hud is GameHud:
		(hud as GameHud).show_message(text, 4.0)


func refresh() -> void:
	#if hud_widget == null or services == null or not services.has_game():
	if services == null or not services.has_game():
		return
	_last_view = view(services, idle_seconds, requested_hints)
	if hud_widget != null:
		hud_widget.show_view(_last_view)
		hud_widget.place_below(_hud_corner_bottom())
		return
	# The tracker is hidden: a hint that just became due (time or N) shows as a HUD message instead.
	var hints: PackedStringArray = _last_view.get("hints", PackedStringArray())
	if hints.size() > _hints_said:
		_hints_said = hints.size()
		var hud: Variant = game.get("hud") if game != null else null
		if hud is GameHud:
			(hud as GameHud).show_message("Hint: " + hints[hints.size() - 1], 8.0)


## The last view shown (for tests).
func current_view() -> Dictionary:
	return _last_view


func _hud_corner_bottom() -> float:
	var hud: Variant = game.get("hud") if game != null else null
	if hud is GameHud and (hud as GameHud).root_control() != null:
		var corner := (hud as GameHud).root_control().find_child("TopRight", true, false) as Control
		if corner != null and corner.is_visible_in_tree():
			return corner.get_global_rect().end.y
	return -1.0


# ---------------------------------------------------------------- pure views (also used by StoryLogPanel and tests)

## A string that changes whenever the tutorial moves on (stage, open objective, tapes, fixes, done).
static func progress_key(state: ColonyState) -> String:
	if state == null:
		return ""
	var t := TutorialSystem.tutorial_of(state)
	return "%d|%s|%d|%d|%d|%d|%s" % [TutorialSystem.current_stage(state), String(t.get("current", "")),
		(t.get("objectives", {}) as Dictionary).size(), TutorialSystem.tapes_found(state), TutorialSystem.tapes_played(state),
		TutorialSystem.fixed_count(state), str(TutorialSystem.is_tutorial_done(state))]


## True when switching crew is disabled (four players).
static func switching_disabled(p_services: GameServices) -> bool:
	return p_services != null and p_services.session.peers.size() >= 4


## Words for who does a broken spot: "" for anyone, else "⚡ Electrical and comms specialist".
static func specialist_words(specialty: String) -> String:
	if specialty == "":
		return ""
	return "%s %s specialist" % [String(StationPanels.SPECIALTY_SYMBOLS.get(StringName(specialty), "●")),
		String(StationPanels.SPECIALTY_WORDS.get(StringName(specialty), specialty.replace("_", " ")))]


## The step's checklist lines: the six tapes (step 2) or the broken spots by room with who can fix them (step 3).
static func list_lines(state: ColonyState, n: int) -> PackedStringArray:
	var out := PackedStringArray()
	if n == 2:
		for id: String in CassetteCatalog.TAPES:
			var title := String(CassetteCatalog.TAPES[id].title)
			var played := TutorialSystem.is_tape_played(state, id)
			var found := CassetteCatalog.collected(state, id)
			out.append("%s %s tape%s" % ["✓" if played else ("◆" if found else "·"), title, " · played" if played else (" · found" if found else "")])
	elif n == 3:
		for r: Dictionary in TutorialSystem.fix_rows(state):
			var who := specialist_words(String(r.specialty))
			out.append("%s %s: %s%s" % ["✓" if bool(r.done) else "·", String(r.room), String(r.text), "" if who == "" else " (" + who + ")"])
	return out


## Everything the tracker shows, as plain data: "title", "mission" (Mission Control's newest line), "progress",
## "objective", "cue", "explain", "hints" (shown now), "hints_total", "list" (checklist lines), "footer", "reminder"
## (unused, kept for older readers), "goal" (colony-goal lines after the tutorial), "stage".
static func view(p_services: GameServices, idle: float, requested: int) -> Dictionary:
	var out := {"title": "", "mission": "", "progress": "", "objective": "", "cue": "", "explain": "", "hints": PackedStringArray(),
		"hints_total": 0, "list": PackedStringArray(), "footer": "N: hint · L: colony journal", "reminder": "", "goal": PackedStringArray(), "stage": 0}
	if p_services == null or not p_services.has_game():
		return out
	var st := p_services.state()
	var team := switching_disabled(p_services)
	var me := p_services.local_character()
	var my_id: StringName = me.id if me != null else &""
	if not TutorialSystem.is_tutorial_done(st):
		var n := TutorialSystem.current_stage(st)
		var sdef := TutorialSystem.stage_def(n)
		var o := TutorialSystem.current_objective(st)
		out["stage"] = n
		out["title"] = "%s · step %d of %d: %s" % [TutorialSystem.speaker(), n, TutorialSystem.STAGE_COUNT, String(sdef.get("title", ""))]
		var last := TutorialSystem.last_message(st)
		out["mission"] = "“%s”" % last if last != "" else ""
		match n:
			2:
				out["progress"] = "Tapes found %d/%d · Tapes played %d/%d" % [TutorialSystem.tapes_found(st), TutorialSystem.tape_count(),
					TutorialSystem.tapes_played(st), TutorialSystem.tape_count()]
			3:
				out["progress"] = "Fixed %d of %d broken spots" % [TutorialSystem.fixed_count(st), TutorialSystem.required_fixes().size()]
				if me != null and StationPanels.SPECIALTY_WORDS.has(me.specialty):
					out["cue"] = "You are the %s: jobs marked %s are yours; jobs without a symbol are for anyone." % [specialist_words(String(me.specialty)),
						String(StationPanels.SPECIALTY_SYMBOLS.get(me.specialty, "●"))]
		out["list"] = list_lines(st, n)
		if not o.is_empty():
			out["objective"] = "▶ " + TutorialSystem.objective_text(o, team)
			var spec := String(o.get("specialty", ""))
			if spec != "":
				out["cue"] = TutorialSystem.specialist_cue(st, spec, my_id, team)
			out["explain"] = TutorialSystem.explanation_for(st, o)
			var all := TutorialSystem.hints_for(st, o, team)
			out["hints_total"] = all.size()
			out["hints"] = all.slice(0, TutorialSystem.hint_count(idle, requested, all.size()))
		return out
	out["title"] = "✓ Base operational" if TutorialSystem.is_base_operational(st) else "Colony goal: a sustainable colony"
	var cert := TutorialSystem.certification_of(st)
	var lines := PackedStringArray()
	match String(cert.get("status", "")):
		"complete":
			out["progress"] = "✓ First milestone complete. The colony keeps running."
		"running":
			out["progress"] = "Certification sol: %d %% (keep battery, water, oxygen and food above zero)" % roundi(100.0 * TutorialSystem.certification_share(st))
		"paused_reserve":
			out["progress"] = "Certification sol waits: a store is empty. Refill it first."
		_:
			out["progress"] = "Next goal: get every sector and the radio working:"
	for m: Dictionary in TutorialSystem.requirements_missing(st):
		lines.append("· " + String(m.text))
	var per_sol := float(st.active_characters().size()) * p_services.balance.meals_per_sol
	if String(cert.get("status", "")) != "complete" and per_sol > 0.0 and st.store(&"food_meals") < 3.0 * per_sol:
		var tips: Dictionary = TutorialSystem.data().get("campaign_tips", {})
		lines.append("· " + String(tips.get("food_stock", "Grow more food.")))
	out["goal"] = lines
	return out
