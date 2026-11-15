class_name AreaLevels
extends RefCounted
## Upgrade paths (owner request 2026-11-14; rebuilt 2026-11-15 for docs/revisions/UPGRADE_PATHS_PLAN.md §1-§7).
## data/area_levels.json lists five SECTIONS (Energy, Biology, Health, Science, Communication), each with its core spot
## (the station(s) where its upgrades are chosen) and its TRACKS. A track has its own number of levels (V1..Vn, 4 or 5;
## V1 is today's model). The level lives in state.levels[track_id] (plain int, saved and replicated with the colony); a
## missing entry means level 1.
##
## Two things read a level:
##   * the look: AreaStagePresenter subclasses in scripts/upgrades/stages/ show the stage of the current level;
##   * what it does: simulation code asks AreaLevels.effect(state, track, key, default), which returns the value of
##     the track's effect table at the current level (or `default` when the track or key is not listed). When the
##     track has a fork (night power: fuel_cell or reactor) and the colony chose a side, that side's effects win.
## The rover is special: its level follows its existing module levels (state.rover.levels) and is never stored.
## Levels change only through the colony's one build a day (scripts/upgrades/colony_builds.gd: the host actions
## build_propose / build_vote / upgrade_area in AreaLevelActions).
##
## Costs: costs[next - 1] = {"parts": int, "ores": {ore_id: int}}; parts come from state.parts, ores from
## state.ores.stock[ore_id] (int). Upkeep: upkeep_kw[level - 1] is the extra power a track draws at its level.

const DATA_PATH := "res://data/area_levels.json"
const MIN_LEVEL := 1

## Ore id -> word for a player of 9 to 12 (plan §9). Unknown ids fall back to the id in words.
const ORE_WORDS := {
	"regolith": "Mars dirt", "magnetite": "magnet rock", "hematite": "rust rock", "iron_meteorite": "space metal",
	"olivine": "green gem rock", "clay": "water clay", "gypsum": "water crystal salt", "sulfate": "yellow salts",
	"sulfur": "pure sulfur", "carbonate": "fizz rock", "silica": "glass stone", "ice": "frozen water",
	"perchlorate": "danger salt",
}

static var _data: Dictionary = {}
static var _by_id: Dictionary = {}
static var _sections_by_id: Dictionary = {}


## Re-reads the data file (tests and tools).
static func reload() -> void:
	_data = {}
	_by_id = {}
	_sections_by_id = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(DATA_PATH)
		var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
		if parsed is Dictionary:
			_data = parsed
		else:
			push_warning("Area levels could not be read from %s." % DATA_PATH)
			_data = {"max_level": 5, "tracks": [], "sections": [], "forks": {}}
		_by_id = {}
		for t: Dictionary in _data.get("tracks", []):
			_by_id[String(t.get("id", ""))] = t
		_sections_by_id = {}
		for s: Dictionary in _data.get("sections", []):
			_sections_by_id[String(s.get("id", ""))] = s
	return _data


## The highest level any track has (5). Each track's own top level is levels_of(id).
static func max_level() -> int:
	return int(data().get("max_level", 5))


## Every track definition, in file order.
static func tracks() -> Array:
	return data().get("tracks", [])


static func track_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for t: Dictionary in tracks():
		out.append(String(t.get("id", "")))
	return out


## One track definition, or {}.
static func track(id: String) -> Dictionary:
	data()
	return _by_id.get(id, {})


static func track_name(id: String) -> String:
	return String(track(id).get("name", id))


## Number of levels of a track (its top level): the "levels" field, else the number of stages, else max_level().
static func levels_of(id: String) -> int:
	var t := track(id)
	if t.has("levels"):
		return clampi(int(t.levels), MIN_LEVEL, max_level())
	var stages: Array = t.get("stages", [])
	return clampi(stages.size(), MIN_LEVEL, max_level()) if not stages.is_empty() else max_level()


## True when the track's level is derived from other state (the rover) and cannot be bought.
static func is_derived(id: String) -> bool:
	return String(track(id).get("follows", "")) != ""


## Current level of a track, 1..levels_of(id).
static func level(state: ColonyState, id: String) -> int:
	if state == null:
		return MIN_LEVEL
	if String(track(id).get("follows", "")) == "rover_modules":
		return rover_level(state.rover.get("levels", {}))
	return clampi(int(state.levels.get(id, MIN_LEVEL)), MIN_LEVEL, levels_of(id))


## Rover look level from its module levels (each 1..5, five modules): no upgrades = 1, a few = 2, several = 3,
## most modules high = 4.
static func rover_level(modules: Dictionary) -> int:
	var extra := 0
	for k in modules:
		extra += maxi(0, int(modules[k]) - 1)
	if extra <= 0:
		return 1
	if extra < 5:
		return 2
	if extra < 12:
		return 3
	return 4


## Words for a stage ("V2: Two-layer rack with LED bars").
static func stage_text(id: String, lvl: int) -> String:
	var stages: Array = track(id).get("stages", [])
	var i := clampi(lvl, MIN_LEVEL, levels_of(id)) - 1
	var words := String(stages[i]) if i < stages.size() else ""
	return "V%d: %s" % [lvl, words] if words != "" else "V%d" % lvl


## Stage words with the colony's fork choice ("V3: 10 kW fission reactor behind a dirt wall").
static func stage_text_for(state: ColonyState, id: String, lvl: int) -> String:
	var choice := fork_choice_of_track(state, id)
	if choice != "":
		var c := fork_choice_def(String(track(id).get("fork", "")), choice)
		var stages: Dictionary = c.get("stages", {})
		if stages.has(str(lvl)):
			return "V%d: %s" % [lvl, String(stages[str(lvl)])]
	return stage_text(id, lvl)


# ---------------------------------------------------------------- sections

static func sections() -> Array:
	return data().get("sections", [])


static func section(section_id: String) -> Dictionary:
	data()
	return _sections_by_id.get(section_id, {})


## Section id of a track ("" when the track has none).
static func section_of(track_id: String) -> String:
	return String(track(track_id).get("section", ""))


## Track ids of a section, in the section's order.
static func section_tracks(section_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id in section(section_id).get("tracks", []):
		if not track(String(id)).is_empty():
			out.append(String(id))
	return out


## The section whose core spot is this station ("" = not a core spot). `station` is a state.stations record.
static func section_at(station_id: String, station: Dictionary) -> String:
	for s: Dictionary in sections():
		var ids: Array = s.get("core_station_ids", [])
		if ids.has(station_id):
			return String(s.get("id", ""))
	# Fallback by kind, for maps whose object names differ.
	var kind := String(station.get("kind", ""))
	if kind == "":
		return ""
	for s: Dictionary in sections():
		var kinds: Array = s.get("core_kinds", [])
		if kinds.has(kind) and (s.get("core_station_ids", []) as Array).is_empty():
			return String(s.get("id", ""))
	return ""


## True when a track's upgrades are chosen (built) at this station: the core spot of its section.
static func core_serves(track_id: String, station_id: String, station: Dictionary) -> bool:
	var sec := section_of(track_id)
	return sec != "" and section_at(station_id, station) == sec


## Words for where a track is chosen ("the power panel in the Power Room").
static func spot_words(track_id: String) -> String:
	return String(section(section_of(track_id)).get("spot", "its section's core spot"))


# ---------------------------------------------------------------- costs, upkeep, requirements

## What reaching `next_level` costs: {"parts": int, "ores": {ore_id: int}}; {} when there is no such level.
static func cost_of(id: String, next_level: int) -> Dictionary:
	if next_level <= MIN_LEVEL or next_level > levels_of(id):
		return {}
	var t := track(id)
	var costs: Array = t.get("costs", [])
	var i := next_level - 1
	var out := {"parts": 0, "ores": {}}
	if i < costs.size() and costs[i] is Dictionary:
		var c: Dictionary = costs[i]
		out.parts = int(c.get("parts", 0))
		var ores: Dictionary = {}
		var raw: Variant = c.get("ores", {})
		if raw is Dictionary:
			for k in (raw as Dictionary):
				var n := int((raw as Dictionary)[k])
				if n > 0:
					ores[String(k)] = n
		out.ores = ores
		return out
	# Older data: cost_parts only.
	var legacy: Array = t.get("cost_parts", [])
	if i < legacy.size():
		out.parts = int(legacy[i])
	return out


## Spare parts the step to `next_level` costs, or -1 when there is no such level.
static func cost_to_reach(id: String, next_level: int) -> int:
	var c := cost_of(id, next_level)
	return int(c.get("parts", 0)) if not c.is_empty() else -1


## Ores in the colony's stock (state.ores.stock[ore_id], int).
static func ore_stock(state: ColonyState, ore_id: String) -> int:
	if state == null:
		return 0
	var stock: Variant = state.ores.get("stock", {})
	return int((stock as Dictionary).get(ore_id, 0)) if stock is Dictionary else 0


static func ore_word(ore_id: String) -> String:
	return String(ORE_WORDS.get(ore_id, ore_id.replace("_", " ")))


## What is still missing to pay for `next_level`: {"parts": int missing, "ores": {ore_id: int missing}}.
static func missing_for(state: ColonyState, id: String, next_level: int) -> Dictionary:
	var c := cost_of(id, next_level)
	var out := {"parts": 0, "ores": {}}
	if c.is_empty() or state == null:
		return out
	out.parts = maxi(0, int(c.parts) - state.parts)
	var ores: Dictionary = {}
	for ore: String in (c.ores as Dictionary):
		var short := int(c.ores[ore]) - ore_stock(state, ore)
		if short > 0:
			ores[ore] = short
	out.ores = ores
	return out


static func can_afford(state: ColonyState, id: String, next_level: int) -> bool:
	var m := missing_for(state, id, next_level)
	return int(m.parts) <= 0 and (m.ores as Dictionary).is_empty()


## Extra power the track draws at `lvl`, kW.
static func upkeep_kw_at(id: String, lvl: int) -> float:
	var list: Array = track(id).get("upkeep_kw", [])
	if list.is_empty():
		return 0.0
	return float(list[clampi(lvl, MIN_LEVEL, list.size()) - 1])


## Extra power the track draws now, kW.
static func upkeep_kw(state: ColonyState, id: String) -> float:
	return upkeep_kw_at(id, level(state, id))


## Extra power every upgrade together draws now, kW (for the power model's demand).
static func total_upkeep_kw(state: ColonyState) -> float:
	var total := 0.0
	for id: String in track_ids():
		total += upkeep_kw(state, id)
	return total


## Other tracks that must be at a level before `next_level` can be built: {track_id: level}.
static func requirements(id: String, next_level: int) -> Dictionary:
	var req: Variant = (track(id).get("requires", {}) as Dictionary).get(str(next_level), {})
	return (req as Dictionary) if req is Dictionary else {}


## "Small step + new ability" for later levels, "Big jump" for the first step (plan §1.2).
static func step_tag(id: String, next_level: int) -> String:
	if next_level <= MIN_LEVEL:
		return ""
	if next_level == MIN_LEVEL + 1:
		return "Big jump"
	return "Small step + new ability" if levels_of(id) >= next_level else ""


# ---------------------------------------------------------------- forks

static func forks() -> Dictionary:
	return data().get("forks", {})


static func fork(fork_id: String) -> Dictionary:
	return forks().get(fork_id, {})


## The fork that is decided by building `next_level` of a track, with its id: {"id", "track", "level", "choices", ...}
## or {} when that level has no fork.
static func fork_at(track_id: String, next_level: int) -> Dictionary:
	var fid := String(track(track_id).get("fork", ""))
	if fid == "":
		return {}
	var f := fork(fid)
	if f.is_empty() or int(f.get("level", 0)) != next_level:
		return {}
	var out := f.duplicate(true)
	out["id"] = fid
	return out


## One choice of a fork ({} when unknown).
static func fork_choice_def(fork_id: String, choice: String) -> Dictionary:
	for c: Dictionary in fork(fork_id).get("choices", []):
		if String(c.get("id", "")) == choice:
			return c
	return {}


## The colony's permanent choice for a fork ("" = not chosen yet). Lives in state.build.forks.
static func fork_choice(state: ColonyState, fork_id: String) -> String:
	if state == null:
		return ""
	var f: Variant = state.build.get("forks", {})
	return String((f as Dictionary).get(fork_id, "")) if f is Dictionary else ""


## The fork choice that applies to a track now ("" when the track has no fork or nothing is chosen).
static func fork_choice_of_track(state: ColonyState, track_id: String) -> String:
	var fid := String(track(track_id).get("fork", ""))
	return fork_choice(state, fid) if fid != "" else ""


static func _value_at(v: Variant, lvl: int, default: Variant) -> Variant:
	if v is Array:
		var a: Array = v
		if a.is_empty():
			return default
		return a[clampi(lvl, MIN_LEVEL, a.size()) - 1]
	return v


## Value of a fork choice's effect at a level (`default` when the choice does not list the key).
static func choice_effect_at(track_id: String, choice: String, key: String, lvl: int, default: Variant = null) -> Variant:
	var c := fork_choice_def(String(track(track_id).get("fork", "")), choice)
	var effects: Dictionary = c.get("effects", {})
	if not effects.has(key):
		return default
	return _value_at(effects[key], lvl, default)


# ---------------------------------------------------------------- effects

## Value of an effect at a given level (no fork choice). Lists are indexed by level - 1 (clamped to the list).
static func effect_at(id: String, key: String, lvl: int, default: Variant = null) -> Variant:
	var effects: Dictionary = track(id).get("effects", {})
	if not effects.has(key):
		return default
	return _value_at(effects[key], lvl, default)


## Value of an effect at the track's current level; the colony's fork choice wins over the track's own table.
static func effect(state: ColonyState, id: String, key: String, default: Variant = null) -> Variant:
	var lvl := level(state, id)
	var choice := fork_choice_of_track(state, id)
	if choice != "":
		var v: Variant = choice_effect_at(id, choice, key, lvl, null)
		if v != null:
			return v
	return effect_at(id, key, lvl, default)


## Float form of effect(); `default` when missing.
static func effectf(state: ColonyState, id: String, key: String, default := 1.0) -> float:
	return float(effect(state, id, key, default))


# ---------------------------------------------------------------- stations

## True when a station record (StationCatalog) belongs to this track: its core spot or one of the stations where the
## track's look stands (station_ids / station_kinds). Only the core spot can build (core_serves).
static func station_serves(id: String, station_id: String, station: Dictionary) -> bool:
	var t := track(id)
	if t.is_empty():
		return false
	if core_serves(id, station_id, station):
		return true
	var ids: Array = t.get("station_ids", [])
	if not ids.is_empty():
		return ids.has(station_id)
	var kinds: Array = t.get("station_kinds", [])
	return kinds.has(String(station.get("kind", "")))


## Track ids that belong to a station (its section's tracks at a core spot, else the tracks whose look stands there).
static func tracks_at(station_id: String, station: Dictionary) -> PackedStringArray:
	var sec := section_at(station_id, station)
	if sec != "":
		return section_tracks(sec)
	var out := PackedStringArray()
	for t: Dictionary in tracks():
		var id := String(t.get("id", ""))
		if station_serves(id, station_id, station):
			out.append(id)
	return out


## What stops the next level for material reasons, as [{"kind", "text"}] (empty = it can be built, as far as this
## track goes). The day's rules (Plan block, one build a day, the vote, the tutorial) are ColonyBuilds.blockers().
## `actor` is unused now (the colony votes instead of a specialist building); kept for older callers.
static func blockers(state: ColonyState, id: String, _actor: CharacterState = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t := track(id)
	if t.is_empty():
		out.append({"kind": "unknown", "text": "That upgrade path does not exist."})
		return out
	if is_derived(id):
		out.append({"kind": "derived", "text": "The rover's look follows its modules: upgrade them in the garage."})
		return out
	var now := level(state, id)
	if now >= levels_of(id):
		out.append({"kind": "max", "text": "%s is fully upgraded (V%d)." % [track_name(id), now]})
		return out
	var next := now + 1
	var req := requirements(id, next)
	for other: String in req:
		if level(state, other) < int(req[other]):
			out.append({"kind": "requires", "text": "First build %s to V%d." % [track_name(other).to_lower(), int(req[other])]})
	var m := missing_for(state, id, next)
	if int(m.parts) > 0:
		out.append({"kind": "parts", "text": "Needs %d more spare part%s." % [int(m.parts), "" if int(m.parts) == 1 else "s"]})
	var ores: Dictionary = m.ores
	if not ores.is_empty():
		var bits := PackedStringArray()
		for ore: String in ores:
			bits.append("%d %s" % [int(ores[ore]), ore_word(ore)])
		out.append({"kind": "ores", "text": "Needs more ore: %s." % ", ".join(bits)})
	return out
