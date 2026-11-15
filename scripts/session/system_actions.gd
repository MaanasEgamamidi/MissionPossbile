class_name SystemActions
extends RefCounted
## Host actions that operate the energy and life-support systems. Each is validated by ActionService like every other
## action; the effect is described in plain words in the result ("text") and announced through events.system_alert.

## What switching a piece of equipment does, in plain words: [when switched on, when switched off].
const SWITCH_TEXT := {
	"trackers": ["Sun trackers on: the panels turn to follow the sun.", "Sun trackers off: the panels stay fixed and make less power."],
	"cleaner": ["Panel cleaner on: it wipes the panels every sunrise while it works and has power.", "Panel cleaner off: dust will settle on the panels."],
	"recycler": ["Water recycler on: it cleans wastewater back into clean water.", "Water recycler off: wastewater will build up."],
	"scrubber": ["CO2 scrubber on: it removes carbon dioxide from the cabin air.", "CO2 scrubber off: carbon dioxide will build up in the cabin."],
	"electrolyser": ["Electrolyser on: it splits clean feed water into oxygen and hydrogen while it has power.", "Electrolyser off: it makes no oxygen."],
	"co2_unit": ["CO2-oxygen unit on: it makes oxygen from the carbon dioxide in the Mars air, using power but no water.", "CO2-oxygen unit off: it makes no oxygen."],
	"cabin_fans": ["Cabin fans on: air moves through the CO2 scrubber.", "Cabin fans off: the CO2 scrubber cleans the air more slowly."],
}


static func register(service: ActionService) -> void:
	for id: StringName in [&"set_equipment", &"set_water_allocation", &"clean_panel", &"repair_cleaner", &"refill_suit"]:
		var d := ActionService.Definition.new()
		d.id = id
		d.check = _check
		d.apply = _apply
		d.target_kind = &"station"
		match id:
			&"set_equipment":
				d.station_kinds = PackedStringArray(["lifesupport", "power"])
				d.params = {"equipment": {"type": TYPE_STRING}, "on": {"type": TYPE_BOOL}}
			&"set_water_allocation":
				d.station_kinds = PackedStringArray(["lifesupport"])
				d.params = {"greenhouse_l_per_hour": {"type": TYPE_FLOAT, "min": 0.0, "max": 20.0, "optional": true},
					"electrolysis_feed_l_per_hour": {"type": TYPE_FLOAT, "min": 0.0, "max": 20.0, "optional": true}}
			&"clean_panel":
				d.station_kinds = PackedStringArray(["solar"])
			&"repair_cleaner":
				d.station_kinds = PackedStringArray(["solar"])
				d.specialty = &"electrical_comms"
				d.important = true
			&"refill_suit":
				d.station_kinds = PackedStringArray(["suits"])
		service.register(d)


static func _check(ctx: ActionService.Context) -> ActionResult:
	var reason: StringName = &""
	match ctx.request.action:
		&"set_equipment":
			if not ctx.state.equipment.has(String(ctx.request.params.equipment)):
				reason = &"unknown_target"
		&"clean_panel":
			if _tracker_index(ctx) < 0:
				reason = &"unknown_target"
		&"repair_cleaner":
			if ctx.state.condition_of("cleaner") >= ctx.balance.equipment_min_condition:
				reason = &"missing_prerequisite"
		&"refill_suit":
			if ctx.actor.suit_charge >= 100.0:
				reason = &"missing_prerequisite"
			elif ctx.state.store(&"oxygen_kg") <= 0.0:
				reason = &"insufficient"
	return null if reason == &"" else ActionResult.failure(ctx.request.request_id, reason)


static func _apply(ctx: ActionService.Context) -> Dictionary:
	var changes := {"action": String(ctx.request.action), "target": String(ctx.request.target)}
	var text := ""
	match ctx.request.action:
		&"set_equipment":
			var id := String(ctx.request.params.equipment)
			var on := bool(ctx.request.params.on)
			ctx.state.equipment[id]["on"] = on
			text = String((SWITCH_TEXT.get(id, ["%s on." % id, "%s off." % id]) as Array)[0 if on else 1])
			changes["equipment"] = id
			changes["on"] = on
		&"set_water_allocation":
			for key: String in ["greenhouse_l_per_hour", "electrolysis_feed_l_per_hour"]:
				if ctx.request.params.has(key):
					ctx.state.water_allocation[key] = float(ctx.request.params[key])
			changes["water_allocation"] = ctx.state.water_allocation.duplicate()
			text = "Water allocation: %.1f L per hour to the greenhouse, %.1f L per hour to the electrolyser. Drinking water always comes first." % [
				float(ctx.state.water_allocation.greenhouse_l_per_hour), float(ctx.state.water_allocation.electrolysis_feed_l_per_hour)]
		&"clean_panel":
			var index := _tracker_index(ctx)
			ctx.state.panel_dust[index] = 0.0
			changes["tracker"] = index
			text = "Panel %d is clean: it makes its full power again." % (index + 1)
		&"repair_cleaner":
			ctx.state.equipment["cleaner"]["condition"] = 1.0
			ctx.session.wear_runtime.on_legacy_repaired(ctx.session, "cleaner")
			text = "Panel cleaner repaired: it will wipe every panel at sunrise while it has power."
		&"refill_suit":
			var cap := ctx.balance.suit_o2_capacity_kg
			var need := (100.0 - ctx.actor.suit_charge) / 100.0 * cap
			var short := ctx.state.store(&"oxygen_kg") < need
			var moved := -ctx.state.add_to_store(&"oxygen_kg", -need)
			if not short:
				ctx.actor.suit_charge = 100.0
				text = "Suit filled to 100 %% with %.3f kg of oxygen from the reserve." % moved
			else:
				ctx.actor.suit_charge = clampf(ctx.actor.suit_charge + moved / cap * 100.0, 0.0, 100.0)
				text = "The oxygen reserve was short: the suit is only at %.0f %%." % ctx.actor.suit_charge
			ctx.state.ledger["suit_refill_kg"] += moved
			changes["moved_kg"] = moved
			changes["short"] = short
	changes["text"] = text
	ctx.session.events.system_alert.emit(StringName(String(ctx.request.action)), &"info", text)
	return changes


## Index of the tracker a solar station belongs to, or -1.
static func _tracker_index(ctx: ActionService.Context) -> int:
	var index := int(ctx.target.get("tracker", -1))
	return index if index >= 0 and index < ctx.state.panel_dust.size() else -1
