class_name ScoutActions
extends RefCounted
## Host actions of the scout update. Each is validated by ActionService like every other action; the effect is
## written in plain words in the result ("text") and announced through events.system_alert.
##   scout_assemble  at the scout bay, field engineering and geology specialist: finishes the half-built scout rover
##                   with ASSEMBLE_PARTS spare parts (ledger parts_used_scout). Once.
##   scout_send      at the scout bay or the colony computer, anyone: params site. The scout drives there on its own,
##                   looks around and radios a report home (ScoutSystem). Only while it is parked or on its way back.
##   scout_recall    same places: the scout turns round and drives back to its bay.
##   collect_ore     at an ore deposit, anyone: one piece of ore goes into the colony store (state.scout.ores). A
##                   deposit gives ORE_PER_DEPOSIT pieces. Finding a deposit marks it on the map.
##   process_ore     at the workbench, anyone: params kind. Hematite: HEMATITE_PER_PART pieces make one spare part
##                   (state.parts, ledger parts_from_ore). Science ores: one piece studied gives one science point.

const ACTIONS: Array[StringName] = [&"scout_assemble", &"scout_send", &"scout_recall", &"collect_ore", &"process_ore"]
const FIELD_SPECIALTY := &"field_engineering_geology"
## Places the scout can be sent from: the bay outside, and the colony computer inside the base.
const CONTROL_KINDS := ["scout_bay", "computer"]


static func register(service: ActionService) -> void:
	for id: StringName in ACTIONS:
		var d := ActionService.Definition.new()
		d.id = id
		d.check = _check
		d.apply = _apply
		d.target_kind = &"station"
		d.important = true
		match id:
			&"scout_assemble":
				d.station_kinds = PackedStringArray(["scout_bay"])
				d.specialty = FIELD_SPECIALTY
			&"scout_send":
				d.station_kinds = PackedStringArray(CONTROL_KINDS)
				d.params = {"site": {"type": TYPE_STRING}}
			&"scout_recall":
				d.station_kinds = PackedStringArray(CONTROL_KINDS)
				d.important = false
			&"collect_ore":
				d.station_kinds = PackedStringArray(["ore_deposit"])
			&"process_ore":
				d.station_kinds = PackedStringArray(["workbench"])
				d.params = {"kind": {"type": TYPE_STRING}}
		service.register(d)


static func _check(ctx: ActionService.Context) -> ActionResult:
	var st := ctx.state
	ScoutSystem.ensure(st)
	var rid := ctx.request.request_id
	match ctx.request.action:
		&"scout_assemble":
			if ScoutSystem.is_built(st):
				return ActionResult.failure(rid, &"missing_prerequisite", "The scout rover is already finished.")
			if st.parts < ScoutSystem.ASSEMBLE_PARTS:
				return ActionResult.failure(rid, &"insufficient", "Finishing the scout needs %d spare parts; the colony has %d. Salvage parts from the broken-down rover." % [ScoutSystem.ASSEMBLE_PARTS, st.parts])
		&"scout_send":
			if not ScoutSystem.is_built(st):
				return ActionResult.failure(rid, &"missing_prerequisite", "The scout rover is not finished yet. The field engineer can finish it at the scout bay.")
			var site_id := String(ctx.request.params.get("site", ""))
			if ScoutSystem.site(site_id).is_empty():
				return ActionResult.failure(rid, &"unknown_target", "The scout does not know that place.")
			if ScoutSystem.status(st) in ["driving", "surveying"]:
				return ActionResult.failure(rid, &"busy", "The scout is already on a trip. Call it back first, or wait for its report.")
		&"scout_recall":
			if not ScoutSystem.is_out(st) or ScoutSystem.status(st) == "returning":
				return ActionResult.failure(rid, &"missing_prerequisite", "The scout is not out on a trip.")
		&"collect_ore":
			var station := String(ctx.request.target)
			if ScoutSystem.ore_info(ScoutSystem.ore_kind_of(st, station)).is_empty():
				return ActionResult.failure(rid, &"unknown_target")
			if ScoutSystem.ore_left(st, station) <= 0:
				return ActionResult.failure(rid, &"insufficient", "There is no good ore left here. The scout can find more places.")
		&"process_ore":
			var kind := String(ctx.request.params.get("kind", ""))
			var info := ScoutSystem.ore_info(kind)
			if info.is_empty():
				return ActionResult.failure(rid, &"unknown_target")
			var need := ScoutSystem.HEMATITE_PER_PART if String(info.get("use", "")) == "parts" else 1
			if ScoutSystem.ore_count(st, kind) < need:
				return ActionResult.failure(rid, &"insufficient", "This needs %d %s; the colony has %d. Collect more at the ore deposits outside." % [need, String(info.get("name", kind)).to_lower(), ScoutSystem.ore_count(st, kind)])
	return null


static func _apply(ctx: ActionService.Context) -> Dictionary:
	var st := ctx.state
	var s := st.scout
	var changes := {"action": String(ctx.request.action)}
	match ctx.request.action:
		&"scout_assemble":
			st.parts -= ScoutSystem.ASSEMBLE_PARTS
			st.ledger[ScoutSystem.LEDGER_PARTS_USED] = float(st.ledger.get(ScoutSystem.LEDGER_PARTS_USED, 0.0)) + float(ScoutSystem.ASSEMBLE_PARTS)
			s.built = true
			s.status = "docked"
			var dock := ScoutSystem.dock_position()
			s.position = [dock.x, 0.0, dock.z]
			s.yaw = ScoutSystem.dock_yaw()
			changes["parts_used"] = ScoutSystem.ASSEMBLE_PARTS
			changes["text"] = "%s finished the scout rover: wheels on, mast camera fitted, power unit connected. Send it out from the scout bay or the colony computer." % ctx.actor.display_name
		&"scout_send":
			var site_id := String(ctx.request.params.site)
			var hours := ScoutSystem.hours_to(st, site_id)
			ScoutSystem.send(st, site_id, String(ctx.actor.id))
			changes["site"] = site_id
			changes["text"] = "The scout rover is driving to the %s. It will get there in about %s and radio a report home." % [
				String(ScoutSystem.site(site_id).get("name", site_id)).to_lower(), ScoutSystem._hours_words(hours)]
		&"scout_recall":
			ScoutSystem.recall(st)
			changes["text"] = "The scout rover turned round and is driving back to its bay."
		&"collect_ore":
			var station := String(ctx.request.target)
			var kind := ScoutSystem.ore_kind_of(st, station)
			(s.ore_taken as Dictionary)[station] = int((s.ore_taken as Dictionary).get(station, 0)) + 1
			(s.ores as Dictionary)[kind] = ScoutSystem.ore_count(st, kind) + 1
			(s.revealed as Dictionary)[station] = true
			var info := ScoutSystem.ore_info(kind)
			changes["kind"] = kind
			changes["left"] = ScoutSystem.ore_left(st, station)
			changes["text"] = "%s collected a piece of %s (%d left here). %s" % [ctx.actor.display_name, String(info.get("name", kind)).to_lower(),
				ScoutSystem.ore_left(st, station), String(info.get("why", ""))]
		&"process_ore":
			var kind2 := String(ctx.request.params.kind)
			var info2 := ScoutSystem.ore_info(kind2)
			if String(info2.get("use", "")) == "parts":
				(s.ores as Dictionary)[kind2] = ScoutSystem.ore_count(st, kind2) - ScoutSystem.HEMATITE_PER_PART
				st.parts += 1
				st.ledger[ScoutSystem.LEDGER_PARTS_FROM_ORE] = float(st.ledger.get(ScoutSystem.LEDGER_PARTS_FROM_ORE, 0.0)) + 1.0
				changes["parts_made"] = 1
				changes["text"] = "%d hematite became one spare part: simple iron brackets and frames, cast at the workbench. The colony now has %d parts." % [ScoutSystem.HEMATITE_PER_PART, st.parts]
			else:
				(s.ores as Dictionary)[kind2] = ScoutSystem.ore_count(st, kind2) - 1
				s.science_points = ScoutSystem.science_points(st) + 1
				(s.studied as Dictionary)[kind2] = int((s.studied as Dictionary).get(kind2, 0)) + 1
				changes["science_points"] = int(s.science_points)
				changes["text"] = "You studied the %s under the bench magnifier: %s Science score: %d." % [
					String(info2.get("name", kind2)).to_lower(), String(info2.get("what", "")), int(s.science_points)]
	ctx.session.events.system_alert.emit(StringName(String(ctx.request.action)), &"info", String(changes.get("text", "")))
	return changes
