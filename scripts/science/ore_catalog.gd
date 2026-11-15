extends RefCounted
## Ores across the map (docs/revisions/UPGRADE_PATHS_PLAN.md section 9, owner 2026-11-15). Loaded by path, no
## class_name: `const OreCatalog := preload("res://scripts/science/ore_catalog.gd")`.
##
## Data: data/ores.json. 13 ore types (real Mars minerals from docs/revisions/research/mars_ores.md, each with a kid name,
## the real name, formula, marker colour, rarity, what it makes and the mission/instrument that found it) and 26 deposits
## placed by geology on our map in three rings around the base (near 0-80 m, middle 80-170 m, far 170-270 m), 76 units
## in all (near 12, middle 29, far 35). Each ore's units are about 60 % of what all upgrade levels in
## data/area_levels.json ask for that ore (120 units in all), so the map pays for about 60 % of all upgrade levels.
## Ore ids: regolith, magnetite, hematite, iron_meteorite, olivine, clay, gypsum, sulfate, sulfur, carbonate, silica,
## ice, perchlorate. Deposit ids: dep_<ore id>_<n> (for example dep_hematite_2).
##
## state.ores (plain JSON, saved and replicated with the colony; owned by this file):
##   revealed:   {deposit_id: true}     shown on the map and in the world (drone/rover reports, walking past, collecting)
##   identified: {deposit_id: true}     the colony knows what the ore is (field engineer on the spot, or the lab)
##   left:       {deposit_id: int}      units still in the ground; a missing entry means the deposit is untouched
##   stock:      {ore_id: int}          identified ore in the colony store: what upgrades spend (spend / can_afford)
##   samples:    {deposit_id: int}      collected but not identified yet ("unknown sample"); identify() moves them into
##                                      stock. Not spendable.
## Identification rule (simple): a deposit is identified when the field engineer collects from it, or when it is
## collected (or settle() runs) while the lab's level (AreaLevels track "lab", missing = 1) is at least the ore type's
## identify_lab_level (1 for most ores; 2 for silica, sulfate and sulfur; 3 for carbonate).
##
## Readers (any machine): types, type_of, deposits, deposit, deposits_of, known_deposits, near, stock, can_afford,
## report_text, cue_text and the small helpers below. Mutators (HOST ONLY, inside an action or a simulation step):
## reveal, identify, take, spend, settle, ensure.
##
## The old scout-rover ore flow (state.scout.ores, ore_* stations in data/stations_scout.json, actions collect_ore and
## process_ore) is separate and still works unchanged; see the note at the end of this file for how it could map here.

const DATA_PATH := "res://data/ores.json"
const FIELD_SPECIALTY := &"field_engineering_geology"
const LAB_TRACK := "lab"
const DEPOSIT_PREFIX := "dep_"
const STATE_KEYS: Array[String] = ["revealed", "identified", "left", "stock", "samples"]

static var _data: Dictionary = {}
static var _types: Array[Dictionary] = []
static var _type_by_id: Dictionary = {}
static var _deposits: Array[Dictionary] = []
static var _deposit_by_id: Dictionary = {}


# ================================================================ data

## Re-reads data/ores.json (tools).
static func reload() -> void:
	_data = {}
	_types.clear()
	_type_by_id.clear()
	_deposits.clear()
	_deposit_by_id.clear()


static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(DATA_PATH)
		var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
		_data = parsed if parsed is Dictionary else {"types": [], "deposits": []}
		for t: Variant in _data.get("types", []):
			if t is Dictionary and String((t as Dictionary).get("id", "")) != "":
				var rec := t as Dictionary
				rec["identify_lab_level"] = int(rec.get("identify_lab_level", 1))
				_types.append(rec)
				_type_by_id[String(rec.id)] = rec
		for d: Variant in _data.get("deposits", []):
			if d is Dictionary and String((d as Dictionary).get("id", "")) != "":
				var dep := d as Dictionary
				var p: Variant = dep.get("position", [0.0, 0.0, 0.0])
				var pa: Array = p if p is Array and (p as Array).size() >= 3 else [0.0, 0.0, 0.0]
				dep["position"] = [float(pa[0]), float(pa[1]), float(pa[2])]
				dep["units"] = int(dep.get("units", 1))
				dep["radius_m"] = float(dep.get("radius_m", 2.0))
				dep["ring"] = String(dep.get("ring", "near"))
				_deposits.append(dep)
				_deposit_by_id[String(dep.id)] = dep
	return _data


## All 13 ore types (shared records: read only).
static func types() -> Array[Dictionary]:
	data()
	return _types


## One ore type, or {} for an unknown id.
static func type_of(ore_id: String) -> Dictionary:
	data()
	return _type_by_id.get(ore_id, {})


## Every deposit on the map: {"id", "ore", "position": [x, y, z], "units", "ring", "radius_m", "distance_m", "where"}
## (shared records: read only).
static func deposits() -> Array[Dictionary]:
	data()
	return _deposits


## One deposit, or {} for an unknown id.
static func deposit(id: String) -> Dictionary:
	data()
	return _deposit_by_id.get(id, {})


static func is_deposit(id: String) -> bool:
	return id.begins_with(DEPOSIT_PREFIX) and not deposit(id).is_empty()


static func deposits_of(ore_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in deposits():
		if String(d.ore) == ore_id:
			out.append(d)
	return out


## Deposits of `ore_id` the colony has revealed that still have units left. ore_id "" means every ore.
static func known_deposits(state: ColonyState, ore_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in deposits():
		if (ore_id == "" or String(d.ore) == ore_id) and is_revealed(state, String(d.id)) and units_left(state, String(d.id)) > 0:
			out.append(d)
	return out


## Deposits whose centre is within `radius_m` of `position` (flat distance on the ground), nearest first.
static func near(position: Vector3, radius_m: float) -> Array[Dictionary]:
	var found: Array = []
	var at := Vector2(position.x, position.z)
	for d: Dictionary in deposits():
		var p := position_of(d)
		var dist := at.distance_to(Vector2(p.x, p.z))
		if dist <= radius_m:
			found.append([dist, d])
	found.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Array[Dictionary] = []
	for f: Array in found:
		out.append(f[1] as Dictionary)
	return out


static func position_of(d: Dictionary) -> Vector3:
	var p: Array = d.get("position", [0.0, 0.0, 0.0])
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


static func base_centre() -> Vector3:
	var p: Variant = data().get("base_centre", [16.0, 0.0, 4.0])
	if p is Array and (p as Array).size() >= 3:
		return Vector3(float(p[0]), float(p[1]), float(p[2]))
	return Vector3(16.0, 0.0, 4.0)


## Ring name of a world position: "near", "middle" or "far".
static func ring_at(position: Vector3) -> String:
	var c := base_centre()
	var dist := Vector2(position.x - c.x, position.z - c.z).length()
	if dist < 80.0:
		return "near"
	return "middle" if dist < 170.0 else "far"


static func color_of(ore_id: String) -> Color:
	var c: Variant = type_of(ore_id).get("color", [0.6, 0.6, 0.6])
	if c is Array and (c as Array).size() >= 3:
		return Color(float(c[0]), float(c[1]), float(c[2]))
	return Color(0.6, 0.6, 0.6)


## "Rust rock (hematite)".
static func label(ore_id: String) -> String:
	var t := type_of(ore_id)
	if t.is_empty():
		return ore_id
	return "%s (%s)" % [_cap(String(t.get("kid_name", ore_id))), _plain_name(String(t.get("name", ore_id)))]


## The same inside a sentence: "rust rock (hematite)", "Mars dirt (basaltic regolith)".
static func label_in_sentence(ore_id: String) -> String:
	var t := type_of(ore_id)
	if t.is_empty():
		return ore_id
	return "%s (%s)" % [String(t.get("kid_name", ore_id)), _plain_name(String(t.get("name", ore_id)))]


static func is_hazard(ore_id: String) -> bool:
	return bool(type_of(ore_id).get("hazard", false))


# ================================================================ state readers

static func is_revealed(state: ColonyState, deposit_id: String) -> bool:
	return state != null and (state.ores.get("revealed", {}) as Dictionary).has(deposit_id)


static func is_identified(state: ColonyState, deposit_id: String) -> bool:
	return state != null and (state.ores.get("identified", {}) as Dictionary).has(deposit_id)


static func units_left(state: ColonyState, deposit_id: String) -> int:
	var d := deposit(deposit_id)
	if d.is_empty():
		return 0
	if state == null:
		return int(d.units)
	return maxi(0, int((state.ores.get("left", {}) as Dictionary).get(deposit_id, int(d.units))))


## Identified units of `ore_id` in the colony store.
static func stock(state: ColonyState, ore_id: String) -> int:
	if state == null:
		return 0
	return maxi(0, int((state.ores.get("stock", {}) as Dictionary).get(ore_id, 0)))


## Every identified unit in the store, all ores together.
static func total_stock(state: ColonyState) -> int:
	var n := 0
	if state == null:
		return 0
	var s: Dictionary = state.ores.get("stock", {})
	for k: Variant in s:
		n += maxi(0, int(s[k]))
	return n


## Unknown samples waiting for the lab, all deposits together.
static func total_samples(state: ColonyState) -> int:
	var n := 0
	if state == null:
		return 0
	var s: Dictionary = state.ores.get("samples", {})
	for k: Variant in s:
		n += maxi(0, int(s[k]))
	return n


## True when the store holds every ore in `cost` ({ore_id: units}).
static func can_afford(state: ColonyState, cost: Dictionary) -> bool:
	for k: Variant in cost:
		var need := int(cost[k])
		if need > 0 and stock(state, String(k)) < need:
			return false
	return true


## Lab level for identification (AreaLevels track "lab"; missing = 1).
static func lab_level(state: ColonyState) -> int:
	return AreaLevels.level(state, LAB_TRACK)


## True when collecting this ore now would identify it: the field engineer always can; otherwise the lab level must be
## at least the ore's identify_lab_level.
static func can_identify(state: ColonyState, ore_id: String, actor: CharacterState = null) -> bool:
	if actor != null and actor.specialty == FIELD_SPECIALTY:
		return true
	return lab_level(state) >= int(type_of(ore_id).get("identify_lab_level", 1))


# ================================================================ host-side mutators

## Fills the missing state.ores fields (new games and older saves). Host, or any machine on its own copy.
static func ensure(state: ColonyState) -> void:
	if state == null:
		return
	for key: String in STATE_KEYS:
		if not (state.ores.get(key) is Dictionary):
			state.ores[key] = {}


## Marks deposits as found. Returns the ids that were not revealed before (unknown ids are skipped).
static func reveal(state: ColonyState, deposit_ids: Array) -> Array:
	ensure(state)
	var fresh: Array = []
	var revealed: Dictionary = state.ores.revealed
	for id: Variant in deposit_ids:
		var sid := String(id)
		if deposit(sid).is_empty() or revealed.has(sid):
			continue
		revealed[sid] = true
		fresh.append(sid)
	return fresh


## Marks a deposit as identified and moves its unknown samples into the store. Returns the units moved.
static func identify(state: ColonyState, deposit_id: String) -> int:
	var d := deposit(deposit_id)
	if d.is_empty():
		return 0
	ensure(state)
	(state.ores.identified as Dictionary)[deposit_id] = true
	(state.ores.revealed as Dictionary)[deposit_id] = true
	var samples: Dictionary = state.ores.samples
	var moved := maxi(0, int(samples.get(deposit_id, 0)))
	samples.erase(deposit_id)
	if moved > 0:
		_add_stock(state, String(d.ore), moved)
	return moved


## Takes up to `units` from a deposit. Identified deposits go into the store (stock); unidentified ones into
## samples (call identify later). Reveals the deposit. Returns the units actually taken.
static func take(state: ColonyState, deposit_id: String, units: int) -> int:
	var d := deposit(deposit_id)
	if d.is_empty() or units <= 0:
		return 0
	ensure(state)
	var n := mini(units, units_left(state, deposit_id))
	if n <= 0:
		return 0
	(state.ores.left as Dictionary)[deposit_id] = units_left(state, deposit_id) - n
	(state.ores.revealed as Dictionary)[deposit_id] = true
	if is_identified(state, deposit_id):
		_add_stock(state, String(d.ore), n)
	else:
		var samples: Dictionary = state.ores.samples
		samples[deposit_id] = int(samples.get(deposit_id, 0)) + n
	return n


## Pays `cost` ({ore_id: units}) from the store, all or nothing. Returns false (and changes nothing) if short.
static func spend(state: ColonyState, cost: Dictionary) -> bool:
	if state == null or not can_afford(state, cost):
		return false
	ensure(state)
	var s: Dictionary = state.ores.stock
	for k: Variant in cost:
		var need := int(cost[k])
		if need > 0:
			s[String(k)] = stock(state, String(k)) - need
	return true


## Identifies every deposit with waiting samples that the lab can now recognise (call after a lab upgrade, or when a
## sample reaches the lab). Returns the deposit ids identified.
static func settle(state: ColonyState) -> Array:
	ensure(state)
	var done: Array = []
	for id: Variant in (state.ores.samples as Dictionary).keys():
		var sid := String(id)
		var d := deposit(sid)
		if not d.is_empty() and can_identify(state, String(d.ore)):
			identify(state, sid)
			done.append(sid)
	return done


static func _add_stock(state: ColonyState, ore_id: String, n: int) -> void:
	var s: Dictionary = state.ores.stock
	s[ore_id] = stock(state, ore_id) + n


# ================================================================ words

## Kid-friendly lines for a report, one per deposit:
## "Rust rock (hematite) — found by Mars Global Surveyor's TES and the Opportunity rover. Makes iron for metal parts."
## A deposit the colony has not identified yet is described by what it looks like.
static func report_text(state: ColonyState, deposit_ids: Array) -> String:
	var lines := PackedStringArray()
	for id: Variant in deposit_ids:
		var d := deposit(String(id))
		if d.is_empty():
			continue
		var ore := String(d.ore)
		var t := type_of(ore)
		var line := ""
		if is_identified(state, String(id)):
			line = "%s — found by %s. Makes %s." % [label(ore), String(t.get("found_by", "")), String(t.get("makes", ""))]
		else:
			line = "Something that looks like %s — collect a sample: the field engineer or the lab can tell for sure." % String(t.get("kid_name", ore))
		if bool(t.get("hazard", false)):
			line += " " + String(t.get("hazard_text", ""))
		lines.append(line)
	return "\n".join(lines)


## What E does at a deposit, without the key: "Collect rust rock (hematite) · 3 left (hold for more)".
static func cue_text(state: ColonyState, deposit_id: String) -> String:
	var d := deposit(deposit_id)
	if d.is_empty():
		return ""
	var left := units_left(state, deposit_id)
	if left <= 0:
		return "Nothing left to collect here"
	var what := label_in_sentence(String(d.ore)) if is_identified(state, deposit_id) else "a rock sample"
	return "Collect %s · %d left (hold for more)" % [what, left]


## One line per ore in the store, for tooltips: "Rust rock (hematite): 4".
static func stock_lines(state: ColonyState) -> PackedStringArray:
	var out := PackedStringArray()
	for t: Dictionary in types():
		var n := stock(state, String(t.id))
		if n > 0:
			out.append("%s: %d" % [label(String(t.id)), n])
	var unknown := total_samples(state)
	if unknown > 0:
		out.append("Unknown samples for the lab: %d" % unknown)
	return out


static func _cap(s: String) -> String:
	return s if s.is_empty() else s.substr(0, 1).to_upper() + s.substr(1)


## "Hematite" -> "hematite"; names that start with a symbol word ("Fe/Mg smectite clay") stay as they are.
static func _plain_name(s: String) -> String:
	var first := s.get_slice(" ", 0)
	if first.length() > 1 and first.substr(1) == first.substr(1).to_lower() and not first.contains("/"):
		return s.substr(0, 1).to_lower() + s.substr(1)
	return s


# ================================================================ note: the old scout-rover ore flow
## ScoutSystem / ScoutActions keep their own ore: five ore_* stations (data/stations_scout.json), three pieces each,
## collected with collect_ore into state.scout.ores and used at the workbench by process_ore (hematite -> parts,
## others -> science points). Nothing here touches it. A later merge could: (1) give each ore_* station a deposit
## record here (same position, ore id, units = ScoutSystem.ORE_PER_DEPOSIT) so collect_ore calls take();
## (2) in ScoutSystem._finish_survey also call reveal(state, ids of near(site position, reveal_radius_m)) so a scout
## survey marks these deposits too; (3) move state.scout.ores into state.ores.stock once on load.
