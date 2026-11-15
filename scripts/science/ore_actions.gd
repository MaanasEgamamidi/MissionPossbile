extends RefCounted
## Host action of the ore survey (UPGRADE_PATHS_PLAN.md section 9). Loaded by path, no class_name:
##   load("res://scripts/science/ore_actions.gd").register(actions)        (SessionService, next to ScoutActions)
##
##   ore_collect   target = deposit id (dep_<ore>_<n>, data/ores.json); optional param units (1..6, default 1: one
##                 press; the presenter sends a few more for a short hold of E). Anyone in a suit, within reach of the
##                 deposit (GameConfig.interact_distance_m, 2.6 m, measured from the deposit's edge). The field
##                 engineer takes twice as much per press. Units go into state.ores.stock when the deposit is
##                 identified (the field engineer identifies it on the spot; anyone else only when the lab level is
##                 high enough for that ore, OreCatalog.can_identify); otherwise into state.ores.samples as an
##                 "unknown sample" the lab identifies later (OreCatalog.settle / identify).
## The deposit is not a station record, so the action has no target_kind and checks reach itself.

const OreCatalog := preload("res://scripts/science/ore_catalog.gd")
const ACTION := &"ore_collect"
const MAX_UNITS := 6
## The field engineer / geologist takes this many times the units per press.
const FIELD_MULTIPLIER := 2
## How far above or below the deposit's ground height the collector may stand (metres).
const REACH_UP_M := 3.0


static func register(service: ActionService) -> void:
	var d := ActionService.Definition.new()
	d.id = ACTION
	d.check = _check
	d.apply = _apply
	d.check_distance = false
	d.important = true
	d.params = {"units": {"type": TYPE_INT, "optional": true, "min": 1, "max": MAX_UNITS}}
	service.register(d)


static func _check(ctx: ActionService.Context) -> ActionResult:
	var rid := ctx.request.request_id
	var id := String(ctx.request.target)
	var dep := OreCatalog.deposit(id)
	if dep.is_empty():
		return ActionResult.failure(rid, &"unknown_target")
	if ctx.actor == null:
		return ActionResult.failure(rid, &"no_actor")
	if not ctx.actor.suit_on:
		return ActionResult.failure(rid, &"missing_prerequisite", "Ore is outside: put a suit on at the suit rack first.")
	var at := OreCatalog.position_of(dep)
	var flat := Vector2(ctx.actor.position.x - at.x, ctx.actor.position.z - at.z).length()
	if flat > ctx.config.interact_distance_m + float(dep.radius_m) or absf(ctx.actor.position.y - at.y) > REACH_UP_M:
		return ActionResult.failure(rid, &"too_far", "Walk up to the rocks to collect them.")
	if OreCatalog.units_left(ctx.state, id) <= 0:
		return ActionResult.failure(rid, &"insufficient", "There is no good ore left here. The drone and the rover can find more places.")
	return null


static func _apply(ctx: ActionService.Context) -> Dictionary:
	var st := ctx.state
	var id := String(ctx.request.target)
	var dep := OreCatalog.deposit(id)
	var ore := String(dep.ore)
	var t := OreCatalog.type_of(ore)
	OreCatalog.ensure(st)
	var field := ctx.actor.specialty == OreCatalog.FIELD_SPECIALTY
	var asked := clampi(int(ctx.request.params.get("units", 1)), 1, MAX_UNITS)
	var newly_identified := false
	if not OreCatalog.is_identified(st, id) and OreCatalog.can_identify(st, ore, ctx.actor):
		OreCatalog.identify(st, id)
		newly_identified = true
	var taken := OreCatalog.take(st, id, asked * (FIELD_MULTIPLIER if field else 1))
	# samples from other deposits the lab can now name join the store too
	OreCatalog.settle(st)
	var left := OreCatalog.units_left(st, id)
	var who := ctx.actor.display_name
	var text := ""
	if OreCatalog.is_identified(st, id):
		text = "%s collected %d piece%s of %s (%d left here). Makes %s." % [who, taken, "" if taken == 1 else "s",
			OreCatalog.label_in_sentence(ore), left, String(t.get("makes", ""))]
		if newly_identified:
			text += " Found by %s." % String(t.get("found_by", ""))
	else:
		text = "%s bagged %d unknown rock sample%s (%d left here). The lab needs a better instrument to tell what it is (lab V%d), or bring the field engineer." % [
			who, taken, "" if taken == 1 else "s", left, int(t.get("identify_lab_level", 1))]
	if bool(t.get("hazard", false)):
		text += " " + String(t.get("hazard_text", ""))
	if newly_identified:
		var sol := int(floor(st.sim_hours / GameConfig.SOL_HOURS)) + 1
		st.discoveries.append({"kind": "ore_identified", "id": id, "ore": ore, "sol": sol, "at_hours": st.sim_hours,
			"text": OreCatalog.report_text(st, [id])})
	ctx.session.events.system_alert.emit(ACTION, &"info", text)
	return {"action": String(ACTION), "deposit": id, "ore": ore, "units": taken, "left": left,
		"identified": OreCatalog.is_identified(st, id), "new_identification": newly_identified, "text": text}
