class_name ColonyGoals
extends RefCounted
## The goals the HUD's goal card (small mode) and the big goals screen (J) show, each checked from the real colony
## state (never from button presses):
## {"id", "text", "done": bool, "fraction": 0..1, "label": short progress words, "kind", "task", "room", "role",
##  "spec": the crew specialty that must do it ("" = everyone), "have" / "need": the count of a counted goal (need 0 =
##  not counted)}.
## Owner 2026-11-14: one list, in this order:
##   1  "Find the tapes"   n/6  (TutorialSystem.tapes_found)
##   2  "Play the tapes"   n/6  (TutorialSystem.tapes_played; the tutorial ends only after)
##   3+ one goal per broken spot, in the tutorial's list order (TutorialSystem.fix_rows): "Patch the Relay",
##      "Lock the Relay". Ticked by TutorialSystem.is_fixed.
## UI overhaul: `text` is a short title (at most about five words). Who can do a repair is no longer in the words:
## `spec` (a specialty id, for the badge) and `role` (kids' words, for the one line under the map) carry it.
## Then anything else the campaign publishes in state.campaign.objectives (for example "Base operational" after the
## tutorial). The tutorial's own published goals (walk in, tapes, rooms) are left out there: this list is the only one.

const MAX_SHOWN := 6
## Role words for kids, by specialty id (RepairCatalog.TASKS[task][2]).
const ROLE_WORDS := {
	"electrical_comms": "Electrical engineer",
	"medical_life_support": "Medic",
	"biology_food": "Biologist",
	"field_engineering_geology": "Field engineer",
	"general": "anyone",
}
## Objectives TutorialSystem publishes that this list already shows in its own words.
const TUTORIAL_PUBLISHED := ["tutorial_arrival", "tapes_found", "tapes_played"]
const TUTORIAL_PUBLISHED_PREFIX := "room_"


static func all(state: ColonyState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null:
		return out
	var tapes := TutorialSystem.tape_count()
	var found := TutorialSystem.tapes_found(state)
	var played := TutorialSystem.tapes_played(state)
	# Collection remains a goal while individual tapes unlock playback and their room's repairs.
	out.append(_with(_count("tapes_found", "Find the tapes", found, tapes), "tapes_found", "", "", ""))
	if not TutorialSystem.repairs_unlocked(state):
		return out
	out.append(_with(_count("tapes_played", "Play the tapes", played, tapes), "tapes_played", "", "Command Room", ""))
	for r: Dictionary in TutorialSystem.fix_rows(state):
		var task := String(r.task)
		if not TutorialSystem.task_unlocked(state, task):
			continue
		var role := role_words(task)
		var done := TutorialSystem.is_fixed(state, task)
		var g := _with(_goal("fix_" + task, String(r.text), done, 1.0 if done else 0.0, ""), "fix", task, String(r.room), role)
		g["spec"] = String(r.get("specialty", ""))
		out.append(g)
	# Whatever else the campaign publishes (after the tutorial: "Base operational"), without the tutorial's own goals.
	var objectives: Variant = state.campaign.get("objectives", null)
	if objectives is Array:
		for o: Variant in objectives:
			if o is Dictionary and (o as Dictionary).has("text"):
				var d := o as Dictionary
				var id := String(d.get("id", d.text))
				if TUTORIAL_PUBLISHED.has(id) or id.begins_with(TUTORIAL_PUBLISHED_PREFIX):
					continue
				out.append(_with(_goal(id, String(d.text), bool(d.get("done", false)),
					float(d.get("fraction", 1.0 if bool(d.get("done", false)) else 0.0)), String(d.get("label", ""))),
					"campaign", "", "", ""))
	# Owner 2026-11-14: hidden for now (we might use them later). The scout, salvage, ore, science, energy and storm goals.
	#var s := state.scout
	#out.append(_goal("scout_built", "Finish the scout rover at the scout bay", ScoutSystem.is_built(state),
	#	1.0 if ScoutSystem.is_built(state) else clampf(float(state.parts) / ScoutSystem.ASSEMBLE_PARTS, 0.0, 0.99),
	#	"" if ScoutSystem.is_built(state) else "%d / %d parts" % [mini(state.parts, ScoutSystem.ASSEMBLE_PARTS), ScoutSystem.ASSEMBLE_PARTS]))
	#var surveyed := (s.get("surveyed", {}) as Dictionary).size()
	#out.append(_count("scout_survey", "Send the scout to look at 3 new places", surveyed, 3))
	#var donor: Dictionary = ScienceActions.read(state, "donors").get("broken_rover", {})
	#var salvaged := (donor.get("recovered", {}) as Dictionary).size()
	#out.append(_count("salvage_rover", "Take tools and parts from the broken-down rover", salvaged, 1))
	#var collected := 0
	#for k: String in (s.get("ore_taken", {}) as Dictionary):
	#	collected += int(s.ore_taken[k])
	#out.append(_count("collect_ore", "Collect 4 pieces of special ore outside", collected, 4))
	#out.append(_count("science", "Study ores to raise the science score to %d (crew rover trips)" % ScoutSystem.CREW_ROVER_SCIENCE,
	#	ScoutSystem.science_points(state), ScoutSystem.CREW_ROVER_SCIENCE))
	#var energy := 0
	#for c: UpgradeDefinition in ProgressionSystem.cards_of("energy"):
	#	if ProgressionSystem.is_installed(state, c.id):
	#		energy += 1
	#out.append(_count("energy_upgrade", "Build an energy upgrade at the solar field", energy, 1))
	#var storms := (state.weather.get("history", []) as Array).size()
	#out.append(_count("dust_storm", "Get the colony through a dust storm", storms, 1))
	return out


## Who can fix a broken spot, in kids' words: "Electrical engineer", "Medic", ... or "anyone".
static func role_words(task_id: String) -> String:
	var spec := "general"
	if RepairCatalog.TASKS.has(task_id):
		spec = String((RepairCatalog.TASKS[task_id] as Array)[2])
	return String(ROLE_WORDS.get(spec, spec.replace("_", " ")))


## True when a crew member of `specialty` may do goal `g`: any goal that is not a specialist's repair, or their own.
static func can_do(g: Dictionary, specialty: String) -> bool:
	var spec := String(g.get("spec", ""))
	return spec == "" or spec == "general" or spec == specialty


## The ONE goal the goals card shows: the first unfinished goal the crew member of `specialty` can do; when every
## open goal belongs to another specialist, the first open one; {} when there are no goals. Once every goal is done,
## the last goal (ticked).
static func next(state: ColonyState, specialty := "") -> Dictionary:
	var list := all(state)
	var first_open := {}
	for g in list:
		if bool(g.done):
			continue
		if can_do(g, specialty):
			return g
		if first_open.is_empty():
			first_open = g
	if not first_open.is_empty():
		return first_open
	return list[list.size() - 1] if not list.is_empty() else {}


## Every goal, unfinished ones first (in order), then the finished ones: the order of the big goals screen.
static func ordered(state: ColonyState) -> Array[Dictionary]:
	var list := all(state)
	var open: Array[Dictionary] = []
	var done: Array[Dictionary] = []
	for g in list:
		if bool(g.done):
			done.append(g)
		else:
			open.append(g)
	return open + done


## The first goals of ordered(): at most MAX_SHOWN.
static func shown(state: ColonyState) -> Array[Dictionary]:
	var out := ordered(state)
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
	return {"id": id, "text": text, "done": done, "fraction": fraction, "label": label, "spec": "", "have": 0, "need": 0}


static func _count(id: String, text: String, have: int, need: int) -> Dictionary:
	var done := have >= need
	var g := _goal(id, text, done, clampf(float(have) / float(maxi(1, need)), 0.0, 1.0), "" if done else "%d/%d" % [mini(have, need), need])
	g["have"] = mini(have, need)
	g["need"] = need
	return g


static func _with(g: Dictionary, kind: String, task: String, room: String, role: String) -> Dictionary:
	g["kind"] = kind
	g["task"] = task
	g["room"] = room
	g["role"] = role
	return g
