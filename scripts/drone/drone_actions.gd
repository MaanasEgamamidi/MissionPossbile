extends RefCounted
## Host actions of the scout drone (2026-11-14 upgrade paths). No class_name: SessionService loads this by path and
## calls register(). Each is validated by ActionService like every other action; the effect is written in plain words
## in the result ("text") and announced through events.system_alert.
##   drone_fly     at the drone pad, anyone: take the controls (V1+). The drone lifts off; the player's inputs fly it
##                 (DronePresenter -> DroneSystem.set_input). Only while it is docked with at least launch_min_battery.
##   drone_land    the pilot (no target): hand the controls back. The drone flies home and lands on its pad by itself.
##   drone_send    at the drone pad or the colony computer, anyone: params route = "site,site" (site ids from
##                 data/scout_sites.json). V3+ only (autopilot); at most max_waypoints places (V3: 1, V4: 4), each
##                 within the command room's radio range, and the battery must hold the whole trip.
##   drone_recall  same places: the autopilot turns home.

const DroneSystem := preload("res://scripts/drone/drone_system.gd")
const ACTIONS: Array[StringName] = [&"drone_fly", &"drone_land", &"drone_send", &"drone_recall"]
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
			&"drone_land":
				d.important = true
			&"drone_send":
				d.target_kind = &"station"
				d.station_kinds = PackedStringArray(CONTROL_KINDS)
				d.params = {"route": {"type": TYPE_STRING}}
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
			if DroneSystem.status(st) != "docked":
				if DroneSystem.status(st) == "manual":
					return ActionResult.failure(rid, &"busy", "Someone is already flying the drone.")
				return ActionResult.failure(rid, &"busy", "The drone is out flying. Wait until it lands on its pad.")
			var need := DroneSystem.num("launch_min_battery", 0.2)
			if DroneSystem.battery(st) < need:
				return ActionResult.failure(rid, &"insufficient", "The drone's battery is at %d %%. Let it charge on the pad to at least %d %% first." % [
					roundi(DroneSystem.battery(st) * 100.0), roundi(need * 100.0)])
		&"drone_land":
			if DroneSystem.pilot(st) != String(ctx.actor.id):
				return ActionResult.failure(rid, &"missing_prerequisite", "You are not flying the drone.")
		&"drone_send":
			if not DroneSystem.has_autopilot(st):
				return ActionResult.failure(rid, &"missing_prerequisite", "This drone has no autopilot yet, so it cannot fly anywhere by itself. Upgrade it to V3 at the drone pad. Until then, fly it yourself: press E at the pad.")
			if DroneSystem.status(st) != "docked":
				return ActionResult.failure(rid, &"busy", "The drone is already flying. Wait until it is back on its pad.")
			var route := DroneSystem.parse_route(String(ctx.request.params.get("route", "")))
			if route.is_empty():
				return ActionResult.failure(rid, &"missing_prerequisite", "Pick a place for the drone to fly to first.")
			var most := DroneSystem.max_waypoints(st)
			if route.size() > most:
				return ActionResult.failure(rid, &"insufficient", "At this level the autopilot can fly to %d place%s per trip. Upgrade the drone to plan longer routes." % [most, "" if most == 1 else "s"])
			var pad := DroneSystem.pad_position(st)
			var r := DroneSystem.range_m(st)
			for id: Variant in route:
				var site := ScoutSystem.site(String(id))
				if site.is_empty():
					return ActionResult.failure(rid, &"unknown_target", "The drone does not know that place.")
				var p := ScoutSystem.site_position(String(id))
				var far := Vector2(p.x - pad.x, p.z - pad.z).length()
				if far > r:
					return ActionResult.failure(rid, &"too_far", "The %s is %d m away, but the command room's radio reaches only %d m. Upgrade the command room for more range." % [
						String(site.get("name", id)).to_lower(), roundi(far), roundi(r)])
			var need_s := DroneSystem.route_seconds(st, route)
			var have_s := DroneSystem.seconds_left(st) - DroneSystem.num("battery_reserve", 0.05) * DroneSystem.flight_seconds(st)
			if need_s > have_s:
				return ActionResult.failure(rid, &"insufficient", "That trip needs about %d s of flying, but the battery holds %d s now. Let it charge, or pick fewer or closer places." % [
					ceili(need_s), maxi(0, floori(have_s))])
		&"drone_recall":
			if DroneSystem.status(st) != "auto":
				return ActionResult.failure(rid, &"missing_prerequisite", "The autopilot is not flying a route now.")
	return null


static func _apply(ctx: ActionService.Context) -> Dictionary:
	var st := ctx.state
	var changes := {"action": String(ctx.request.action)}
	match ctx.request.action:
		&"drone_fly":
			DroneSystem.take_control(st, String(ctx.actor.id))
			changes["pilot"] = String(ctx.actor.id)
			changes["text"] = "%s is flying the scout drone (battery %d %%, about %d s of flight). W A S D fly, the mouse turns, Space climbs, Shift or Ctrl goes down, E hands it back. Stay within %d m of the pad: that is the command room's radio range." % [
				ctx.actor.display_name, roundi(DroneSystem.battery(st) * 100.0), roundi(DroneSystem.seconds_left(st)), roundi(DroneSystem.range_m(st))]
		&"drone_land":
			DroneSystem.release(st)
			changes["text"] = "You handed the drone back. It is flying home to its pad by itself."
		&"drone_send":
			var route := DroneSystem.parse_route(String(ctx.request.params.route))
			DroneSystem.send(st, route, String(ctx.actor.id))
			var names := PackedStringArray()
			for id: Variant in route:
				names.append(String(ScoutSystem.site(String(id)).get("name", id)).to_lower())
			changes["route"] = route.duplicate()
			changes["text"] = "The autopilot is flying the drone to the %s. It films each place, radios a report home and comes back by itself (about %d s)." % [
				" then the ".join(names), roundi(DroneSystem.route_seconds(st, route))]
		&"drone_recall":
			DroneSystem.recall(st)
			changes["text"] = "The drone turned round and is flying home to its pad."
	ctx.session.events.system_alert.emit(StringName(String(ctx.request.action)), &"info", String(changes.get("text", "")))
	return changes
