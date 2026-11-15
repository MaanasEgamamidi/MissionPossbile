extends RefCounted
## Host actions of the scout drone (upgrade paths plan §6.2). No class_name: SessionService loads this by path and
## calls register(). Each is validated by ActionService like every other action; the effect is written in plain words
## in the result ("text") and announced through events.system_alert.
##   drone_fly     at the drone pad, anyone: take the controls (V1+). The drone lifts off; the player's inputs fly it
##                 (DronePresenter -> DroneSystem.set_input). Only while it is docked, FULLY charged and with a flight
##                 left today (flights_per_sol).
##   drone_home    the pilot (no target), R while flying: the drone flies home by itself now; the pilot keeps watching
##                 through its camera until it lands.
##   drone_land    the pilot or the player watching (no target), E while flying: hand the drone back. It flies home and
##                 lands on its pad by itself; the player's own camera comes back.
##   drone_send    at the drone pad or the colony computer, anyone: params mode = "revisit" | "find" | "scan",
##                 target = a revisit place id (DroneSystem.revisit_places) or an ore id. revisit V2+, find V3+,
##                 scan V4. Same launch rules as drone_fly, every waypoint inside the radio range, and the whole flight
##                 must fit one battery with the trip-home margin (DroneSystem.plan).
##   drone_recall  same places: the autopilot turns home.

const DroneSystem := preload("res://scripts/drone/drone_system.gd")
const ACTIONS: Array[StringName] = [&"drone_fly", &"drone_home", &"drone_land", &"drone_send", &"drone_recall"]
const PAD_KIND := "drone_pad"
const CONTROL_KINDS := ["drone_pad", "computer"]


static func register(service: ActionService) -> void:
	for id: StringName in ACTIONS:
		var d := ActionService.Definition.new()
		d.id = id
		d.check = _check
		d.apply = _apply
		match id:
			&"drone_fly":
				d.target_kind = &"station"
				d.station_kinds = PackedStringArray([PAD_KIND])
				d.important = true
			&"drone_home", &"drone_land":
				d.important = true
			&"drone_send":
				d.target_kind = &"station"
				d.station_kinds = PackedStringArray(CONTROL_KINDS)
				d.params = {"mode": {"type": TYPE_STRING}, "target": {"type": TYPE_STRING}}
				d.important = true
			&"drone_recall":
				d.target_kind = &"station"
				d.station_kinds = PackedStringArray(CONTROL_KINDS)
		service.register(d)


static func _check(ctx: ActionService.Context) -> ActionResult:
	var st := ctx.state
	DroneSystem.ensure(st)
	var rid := ctx.request.request_id
	match ctx.request.action:
		&"drone_fly":
			var why := DroneSystem.launch_refusal(st)
			if why != "":
				return ActionResult.failure(rid, &"busy" if DroneSystem.is_flying(st) else &"insufficient", why)
		&"drone_home":
			if DroneSystem.pilot(st) != String(ctx.actor.id):
				return ActionResult.failure(rid, &"missing_prerequisite", "You are not flying the drone.")
		&"drone_land":
			if DroneSystem.watcher(st) != String(ctx.actor.id):
				return ActionResult.failure(rid, &"missing_prerequisite", "You are not flying the drone.")
		&"drone_send":
			var why := DroneSystem.launch_refusal(st)
			if why != "":
				return ActionResult.failure(rid, &"busy" if DroneSystem.is_flying(st) else &"insufficient", why)
			var plan := DroneSystem.plan(st, String(ctx.request.params.get("mode", "")), String(ctx.request.params.get("target", "")))
			if not bool(plan.get("ok", false)):
				return ActionResult.failure(rid, &"insufficient", String(plan.get("text", "The drone cannot fly that.")))
		&"drone_recall":
			if DroneSystem.status(st) != "auto":
				return ActionResult.failure(rid, &"missing_prerequisite", "The autopilot is not flying now.")
	return null


static func _apply(ctx: ActionService.Context) -> Dictionary:
	var st := ctx.state
	var changes := {"action": String(ctx.request.action)}
	match ctx.request.action:
		&"drone_fly":
			DroneSystem.take_control(st, String(ctx.actor.id))
			changes["pilot"] = String(ctx.actor.id)
			changes["text"] = "%s is flying the scout drone (about %d s of flight; flights left today: %d). W A S D fly, the mouse turns, Space climbs, Ctrl or Shift goes down, Tab switches the camera, R flies it home, E hands it back. It turns home by itself before the battery runs low." % [
				ctx.actor.display_name, roundi(DroneSystem.seconds_left(st)), DroneSystem.flights_left_today(st)]
		&"drone_home":
			DroneSystem.fly_home(st, "r")
			changes["text"] = "The drone is flying home to its pad by itself."
		&"drone_land":
			DroneSystem.release(st)
			changes["text"] = "You handed the drone back. It is flying home to its pad by itself."
		&"drone_send":
			var plan := DroneSystem.plan(st, String(ctx.request.params.mode), String(ctx.request.params.target))
			DroneSystem.send_mission(st, plan.get("route", []) as Array, plan.get("mission", {}) as Dictionary, String(ctx.actor.id))
			changes["mission"] = (plan.get("mission", {}) as Dictionary).duplicate()
			changes["text"] = String(plan.get("text", ""))
		&"drone_recall":
			DroneSystem.recall(st)
			changes["text"] = "The drone turned round and is flying home to its pad."
	ctx.session.events.system_alert.emit(StringName(String(ctx.request.action)), &"info", String(changes.get("text", "")))
	return changes
