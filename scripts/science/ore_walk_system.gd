extends RefCounted
## Finding ore by walking (UPGRADE_PATHS_PLAN.md section 9). A post-system of the colony simulation, HOST ONLY:
##   sim.post_systems.append(load("res://scripts/science/ore_walk_system.gd").new())     (SessionService)
## Every step it looks for crew who are outside in a suit; a deposit within WALK_REVEAL_M of its edge is revealed
## (state.ores.revealed, replicated), so it stays on the map and in the world, and one alert names what was found.
## It never collects or identifies anything. Cheap: 26 deposits times the crew, once every CHECK_EVERY_H game hours.

const OreCatalog := preload("res://scripts/science/ore_catalog.gd")
const ALERT_ID := &"ore_found"
## Metres from a deposit's edge at which a walker notices it.
const WALK_REVEAL_M := 8.0
## Game hours between checks (about every 20 game seconds).
const CHECK_EVERY_H := 0.006

var _wait_h := 0.0


func step(state: ColonyState, _balance: GameBalance, _phase: float, dt_hours: float, events: GameEvents) -> void:
	if state == null:
		return
	_wait_h -= dt_hours
	if _wait_h > 0.0:
		return
	_wait_h = CHECK_EVERY_H
	OreCatalog.ensure(state)
	var found: Array = []
	for key: Variant in state.characters:
		var c := state.characters[key] as CharacterState
		if c == null or not c.suit_on:
			continue
		for d: Dictionary in OreCatalog.deposits():
			var id := String(d.id)
			if found.has(id) or OreCatalog.is_revealed(state, id):
				continue
			var p := OreCatalog.position_of(d)
			if Vector2(c.position.x - p.x, c.position.z - p.z).length() <= float(d.radius_m) + WALK_REVEAL_M:
				found.append(id)
	if found.is_empty():
		return
	var fresh := OreCatalog.reveal(state, found)
	if fresh.is_empty() or events == null:
		return
	events.system_alert.emit(ALERT_ID, &"info", "Ore found on the walk! " + OreCatalog.report_text(state, fresh))
