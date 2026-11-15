class_name PuzzleRegistry
extends RefCounted
## The repair puzzles of the broken parts (2026-11-14, owner handoff "Broken Parts -> Godot", tasks T01-T12 of the
## Implementation Prompt Pack). One task's puzzle is two files, loaded by path (no class_name, no import needed):
##   res://scripts/tasks/puzzles/tNN_rule.gd   host rule. Static functions:
##       supports_resume() -> bool
##       validate(task: Dictionary, move: Dictionary) -> Dictionary
##           task = a copy of state.repair.tasks[tNN] (puzzle_seed, puzzle_state, progress, ...);
##           move = {"move": String, "value": int}. Returns {accepted, puzzle_state, progress 0..1, complete}.
##           Pure and deterministic: the seeded layout comes from task.puzzle_seed, never from randomness here.
##           Wrong, forged or replayed moves return accepted = false (RepairRuntime then fails closed).
##   res://scripts/tasks/puzzles/tNN_panel.gd  the mini-game (extends TaskPanel). It only sends task_move requests
##       and draws task.puzzle_state from the host; it never decides completion.
## A task with both files is a "broken part" task: until its first completion (task.first_completed) the spot shows
## the broken model, the prompt names the fault, and E opens the mini-game instead of the maintenance panel.

const DIR := "res://scripts/tasks/puzzles/"


static func rule_path(task_id: String) -> String:
	return DIR + task_id.to_lower() + "_rule.gd"


static func panel_path(task_id: String) -> String:
	return DIR + task_id.to_lower() + "_panel.gd"


## True when the task has a rule and a panel installed.
static func has_puzzle(task_id: String) -> bool:
	return ResourceLoader.exists(rule_path(task_id)) and ResourceLoader.exists(panel_path(task_id))


## True while the task's spot is broken: it has a puzzle and has never been solved.
static func is_broken(state: ColonyState, task_id: String) -> bool:
	if state == null or not has_puzzle(task_id):
		return false
	var task: Dictionary = state.repair.get("tasks", {}).get(task_id, {})
	return not task.is_empty() and not bool(task.get("first_completed", false))


## Registers every installed rule on the host's RepairRuntime. Called once per session.
static func register_all(runtime: RepairRuntime) -> int:
	var count := 0
	for task_id: String in RepairCatalog.TASKS:
		if not ResourceLoader.exists(rule_path(task_id)):
			continue
		var script := load(rule_path(task_id)) as Script
		if script == null:
			push_warning("Repair rule %s could not be loaded." % rule_path(task_id))
			continue
		var resume := bool(script.call(&"supports_resume"))
		runtime.register_rule(task_id, Callable(script, &"validate"), resume)
		count += 1
	return count


## The mini-game panel for a task's station, set up and ready to open, or null.
## Wrong specialist (owner 2026-11-14): a specialised task opened by anyone else shows the same frame with scrambled
## symbols in place of the controls and one clear line naming who can read it (unreadable_line); no move can be sent.
## General tasks open for anyone. The host still refuses every move of a wrong specialist (RepairRuntime).
static func make_panel(task_id: String, station_id: StringName, services: GameServices) -> UiPanel:
	if services == null or not services.has_game() or not ResourceLoader.exists(panel_path(task_id)):
		return null
	var record: Dictionary = services.state().repair.get("tasks", {}).get(task_id, {})
	if record.is_empty():
		return null
	var panel: TaskPanel
	var specialty := String(record.get("required_specialty", "general"))
	var me := services.local_character()
	var readable := specialty == "general" or (me != null and String(me.specialty) == specialty)
	if readable:
		var script := load(panel_path(task_id)) as Script
		panel = script.new() as TaskPanel if script != null else null
	else:
		panel = TaskPanel.new()
	if panel == null:
		return null
	var room: Dictionary = RepairCatalog.ROOMS.get(String(record.get("room_id", "")), {})
	panel.configure_task(record, String(record.get("title", "Repair task")), String(room.get("title", "")))
	panel.set_meta(&"station_surface", true)
	panel.set_meta(&"station_id", station_id)
	panel.setup(services)
	if not readable:
		panel.show_unreadable(unreadable_line(services, specialty), int(record.get("puzzle_seed", 0)))
	return panel


## The one clear line of the scrambled panel, following the real crew-switching rules (CrewSelectPanel / the host's
## claim_character): the specialist is played by someone else, switching is off with four players, or press C at the
## Med Bay hub to swap to them.
static func unreadable_line(services: GameServices, specialty: String) -> String:
	var sym := String(StationPanels.SPECIALTY_SYMBOLS.get(StringName(specialty), "●"))
	var words := String(StationPanels.SPECIALTY_WORDS.get(StringName(specialty), specialty.replace("_", " ")))
	var head := "Only the %s %s specialist can read this." % [sym, words]
	if services == null or not services.has_game():
		return head
	var st := services.state()
	var mine := services.local_peer()
	for c: CharacterState in st.active_characters():
		if String(c.specialty) == specialty and c.owner_peer != mine:
			return head + " Another player plays them: ask them to come and fix it."
	var players := maxi(services.session.peers.size(), st.active_characters().size())
	if players >= 4:
		return head + " Ask the player of that crew member to come here."
	return head + " Press %s to swap to them in the Med Bay." % _key_name(&"crew", "C")


static func _key_name(action: StringName, fallback: String) -> String:
	if InputMap.has_action(action):
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				var k := e as InputEventKey
				var code := k.keycode if k.keycode != KEY_NONE else k.physical_keycode
				if code != KEY_NONE:
					return OS.get_keycode_string(code)
	return fallback
