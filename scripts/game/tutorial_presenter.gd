class_name TutorialPresenter
extends Node
## Scene side of the tutorial (Prompt 12): the objective tracker on the HUD, hints, specialist cues and the colony
## journal (L). It only reads state.campaign and sends ordinary requests; the host's TutorialSystem decides.
##
## Hints: one appears after `hint_after_s` real seconds (data/tutorial.json) without progress, another every
## `hint_repeat_s`, and one more each time the player asks (N). Progress resets the count. Pausing stops the clock.
## Explanations the colony has already mastered are not shown. With four players the texts never ask anyone to switch
## crew; the cue names who should act.
## Wiring (GameMain._begin_play, after the HUD exists):
##   var tutorial := TutorialPresenter.new(); tutorial.name = "TutorialPresenter"; add_child(tutorial)
##   tutorial.setup(world, services, self)

## Input actions used when PlayerInput has them; otherwise the H and J keys.
const HINT_ACTION := &"tutorial_hint"
const JOURNAL_ACTION := &"journal"
const REFRESH_SECONDS := 0.25

var services: GameServices
## The GameMain (or a stand-in with `hud` and `ui`), or null.
var game: Node
var hud_widget: TutorialHud
## Real seconds without tutorial progress (only while the game runs).
var idle_seconds := 0.0
## Hints asked for since the last progress.
var requested_hints := 0

var _progress_key := ""
var _refresh_left := 0.0
var _last_view := {}


func setup(_world: Node3D, p_services: GameServices, p_game: Node) -> void:
	services = p_services
	game = p_game
	name = "TutorialPresenter"
	process_mode = Node.PROCESS_MODE_ALWAYS
	hud_widget = TutorialHud.new()
	hud_widget.name = "TutorialHud"
	hud_widget.setup(services)
	var hud: Variant = game.get("hud") if game != null else null
	if hud is Node and is_instance_valid(hud):
		(hud as Node).add_child(hud_widget)
	else:
		var layer := CanvasLayer.new()
		layer.name = "TutorialLayer"
		layer.layer = 10
		add_child(layer)
		layer.add_child(hud_widget)
	refresh()


func _process(delta: float) -> void:
	if services == null or not services.has_game():
		return
	if not services.session.paused:
		idle_seconds += delta
	var key := progress_key(services.state())
	if key != _progress_key:
		_progress_key = key
		idle_seconds = 0.0
		requested_hints = 0
		_refresh_left = 0.0
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_SECONDS
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var ui: Variant = game.get("ui") if game != null else null
	if ui is UiRoot and not (ui as UiRoot).gameplay_has_focus():
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


## Shows one more hint now (H, or the journal's hint button).
func request_hint() -> void:
	requested_hints += 1
	refresh()


## Opens the colony journal (tutorial, campaign goal and the optional story).
func open_journal() -> void:
	var ui: Variant = game.get("ui") if game != null else null
	if ui is UiRoot:
		var panel := StoryLogPanel.new()
		panel.presenter = self
		(ui as UiRoot).open(panel)


func refresh() -> void:
	if hud_widget == null or services == null or not services.has_game():
		return
	_last_view = view(services, idle_seconds, requested_hints)
	hud_widget.show_view(_last_view)
	hud_widget.place_below(_hud_corner_bottom())


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

## A string that changes whenever the tutorial moves on (stage, open objective, objectives done, reminder).
static func progress_key(state: ColonyState) -> String:
	if state == null:
		return ""
	var t := TutorialSystem.tutorial_of(state)
	var r := TutorialSystem.replay_of(state)
	return "%d|%s|%d|%s|%s|%d" % [TutorialSystem.current_stage(state), String(t.get("current", "")),
		(t.get("objectives", {}) as Dictionary).size(), str(t.get("done", false)), String(r.get("current", "")),
		(r.get("objectives", {}) as Dictionary).size()]


## True when switching crew is disabled (four players).
static func switching_disabled(p_services: GameServices) -> bool:
	return p_services != null and p_services.session.peers.size() >= 4


## Everything the tracker shows, as plain data: "title", "progress", "objective", "cue", "explain", "hints" (shown
## now), "hints_total", "footer", "reminder" (a reminder run's line or ""), "goal" (campaign lines after the tutorial).
static func view(p_services: GameServices, idle: float, requested: int) -> Dictionary:
	var out := {"title": "", "progress": "", "objective": "", "cue": "", "explain": "", "hints": PackedStringArray(),
		"hints_total": 0, "footer": "N: hint · L: colony journal", "reminder": "", "goal": PackedStringArray(), "stage": 0}
	if p_services == null or not p_services.has_game():
		return out
	var st := p_services.state()
	var team := switching_disabled(p_services)
	var me := p_services.local_character()
	var my_id: StringName = me.id if me != null else &""
	var r := TutorialSystem.replay_of(st)
	if not r.is_empty():
		var ro := TutorialSystem.replay_objective(st)
		if not ro.is_empty():
			out["reminder"] = "Reminder: %s — %s" % [String(TutorialSystem.stage_def(int(r.stage)).get("title", "")), TutorialSystem.objective_text(ro, team)]
	if not TutorialSystem.is_tutorial_done(st):
		var n := TutorialSystem.current_stage(st)
		var sdef := TutorialSystem.stage_def(n)
		var o := TutorialSystem.current_objective(st)
		var pr := TutorialSystem.stage_progress(st, n)
		out["stage"] = n
		out["title"] = "Tutorial %d of %d · %s" % [n, TutorialSystem.STAGE_COUNT, String(sdef.get("title", ""))]
		out["progress"] = "%d of %d steps done" % [pr.x, pr.y]
		if not o.is_empty():
			out["objective"] = "▶ " + TutorialSystem.objective_text(o, team)
			var spec := String(o.get("specialty", ""))
			var soft := false
			if spec == "":
				spec = String(o.get("specialty_hint", ""))
				soft = spec != ""
			out["cue"] = TutorialSystem.specialist_cue(st, spec, my_id, team, soft)
			out["explain"] = TutorialSystem.explanation_for(st, o)
			var all := TutorialSystem.hints_for(st, o, team)
			out["hints_total"] = all.size()
			var count := TutorialSystem.hint_count(idle, requested, all.size())
			out["hints"] = all.slice(0, count)
			if n == 9 and String(o.get("kind", "")) == "stage9_fixed":
				var v := String(TutorialSystem.stage9_of(st).get("variant", ""))
				out["explain"] = String(TutorialSystem.variant_data(v).get("problem", "")) + " " + String(out.explain)
		return out
	out["title"] = "Colony goal: a sustainable colony"
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
			out["progress"] = "Get every sector and the radio working:"
	for m: Dictionary in TutorialSystem.requirements_missing(st):
		lines.append("· " + String(m.text))
	var per_sol := float(st.active_characters().size()) * p_services.balance.meals_per_sol
	if String(cert.get("status", "")) != "complete" and per_sol > 0.0 and st.store(&"food_meals") < 3.0 * per_sol:
		var tips: Dictionary = TutorialSystem.data().get("campaign_tips", {})
		lines.append("· " + String(tips.get("food_stock", "Grow more food.")))
	out["goal"] = lines
	return out
