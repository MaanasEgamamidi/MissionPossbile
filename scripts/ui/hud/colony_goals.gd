class_name ColonyGoals
extends RefCounted
## The goals the HUD's goal card shows, each checked from the real colony state (never from button presses):
## {"id", "text", "done": bool, "fraction": 0..1, "label": short progress words}.
## When the tutorial and campaign (Prompt 12, state.campaign) publish an "objectives" list of {"text", "done"}, those
## come first, so this card can show them without knowing how they are made.

const MAX_SHOWN := 6


static func all(state: ColonyState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null:
		return out
	var objectives: Variant = state.campaign.get("objectives", null)
	if objectives is Array:
		for o: Variant in objectives:
			if o is Dictionary and (o as Dictionary).has("text"):
				var d := o as Dictionary
				out.append({"id": String(d.get("id", d.text)), "text": String(d.text), "done": bool(d.get("done", false)),
					"fraction": float(d.get("fraction", 1.0 if bool(d.get("done", false)) else 0.0)), "label": String(d.get("label", ""))})
	var s := state.scout
	out.append(_goal("scout_built", "Finish the scout rover at the scout bay", ScoutSystem.is_built(state),
		1.0 if ScoutSystem.is_built(state) else clampf(float(state.parts) / ScoutSystem.ASSEMBLE_PARTS, 0.0, 0.99),
		"" if ScoutSystem.is_built(state) else "%d / %d parts" % [mini(state.parts, ScoutSystem.ASSEMBLE_PARTS), ScoutSystem.ASSEMBLE_PARTS]))
	var surveyed := (s.get("surveyed", {}) as Dictionary).size()
	out.append(_count("scout_survey", "Send the scout to look at 3 new places", surveyed, 3))
	var donor: Dictionary = ScienceActions.read(state, "donors").get("broken_rover", {})
	var salvaged := (donor.get("recovered", {}) as Dictionary).size()
	out.append(_count("salvage_rover", "Take tools and parts from the broken-down rover", salvaged, 1))
	var collected := 0
	for k: String in (s.get("ore_taken", {}) as Dictionary):
		collected += int(s.ore_taken[k])
	out.append(_count("collect_ore", "Collect 4 pieces of special ore outside", collected, 4))
	out.append(_count("science", "Study ores to raise the science score to %d (crew rover trips)" % ScoutSystem.CREW_ROVER_SCIENCE,
		ScoutSystem.science_points(state), ScoutSystem.CREW_ROVER_SCIENCE))
	var energy := 0
	for c: UpgradeDefinition in ProgressionSystem.cards_of("energy"):
		if ProgressionSystem.is_installed(state, c.id):
			energy += 1
	out.append(_count("energy_upgrade", "Build an energy upgrade at the solar field", energy, 1))
	var storms := (state.weather.get("history", []) as Array).size()
	out.append(_count("dust_storm", "Get the colony through a dust storm", storms, 1))
	return out


## The goals to show: every unfinished goal first (in order), then finished ones, at most MAX_SHOWN.
static func shown(state: ColonyState) -> Array[Dictionary]:
	var list := all(state)
	var open: Array[Dictionary] = []
	var done: Array[Dictionary] = []
	for g in list:
		if bool(g.done):
			done.append(g)
		else:
			open.append(g)
	var out := open + done
	if out.size() > MAX_SHOWN:
		out.resize(MAX_SHOWN)
	return out


static func done_count(state: ColonyState) -> Vector2i:
	var list := all(state)
	var n := 0
	for g in list:
		if bool(g.done):
			n += 1
	return Vector2i(n, list.size())


static func _goal(id: String, text: String, done: bool, fraction: float, label: String) -> Dictionary:
	return {"id": id, "text": text, "done": done, "fraction": fraction, "label": label}


static func _count(id: String, text: String, have: int, need: int) -> Dictionary:
	var done := have >= need
	return _goal(id, text, done, clampf(float(have) / float(need), 0.0, 1.0), "" if done else "%d / %d" % [mini(have, need), need])
