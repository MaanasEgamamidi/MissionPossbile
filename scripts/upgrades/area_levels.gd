class_name AreaLevels
extends RefCounted
## Visible upgrade paths (owner request 2026-11-14): every interactable area, the scout drone and the rover have levels
## V1..V4 (data/area_levels.json). V1 is today's model. The level lives in state.levels[track_id] (plain int, saved
## and replicated with the colony); a missing entry means level 1.
##
## Two things read a level:
##   * the look: AreaStagePresenter subclasses in scripts/upgrades/stages/ show the stage of the current level;
##   * what it does: simulation code asks AreaLevels.effect(state, track, key, default), which returns the value of
##     the track's effect table at the current level (or `default` when the track or key is not listed).
## The rover is special: its level follows its existing module levels (state.rover.levels) and is never stored.
## Levels change only through the host action `upgrade_area` (AreaLevelActions).

const DATA_PATH := "res://data/area_levels.json"
const MIN_LEVEL := 1

static var _data: Dictionary = {}
static var _by_id: Dictionary = {}


## Re-reads the data file (tests and tools).
static func reload() -> void:
	_data = {}
	_by_id = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(DATA_PATH)
		var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
		if parsed is Dictionary:
			_data = parsed
		else:
			push_warning("Area levels could not be read from %s." % DATA_PATH)
			_data = {"max_level": 4, "tracks": []}
		_by_id = {}
		for t: Dictionary in _data.get("tracks", []):
			_by_id[String(t.get("id", ""))] = t
	return _data


static func max_level() -> int:
	return int(data().get("max_level", 4))


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


## True when the track's level is derived from other state (the rover) and cannot be bought with upgrade_area.
static func is_derived(id: String) -> bool:
	return String(track(id).get("follows", "")) != ""


## Current level of a track, 1..max_level.
static func level(state: ColonyState, id: String) -> int:
	if state == null:
		return MIN_LEVEL
	if String(track(id).get("follows", "")) == "rover_modules":
		return rover_level(state.rover.get("levels", {}))
	return clampi(int(state.levels.get(id, MIN_LEVEL)), MIN_LEVEL, max_level())


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
	var i := clampi(lvl, MIN_LEVEL, max_level()) - 1
	var words := String(stages[i]) if i < stages.size() else ""
	return "V%d: %s" % [lvl, words] if words != "" else "V%d" % lvl


## Spare parts the step from `lvl` to `lvl + 1` costs (cost_parts[lvl] in the file), or -1 when there is no next level.
static func cost_to_reach(id: String, next_level: int) -> int:
	if next_level <= MIN_LEVEL or next_level > max_level():
		return -1
	var costs: Array = track(id).get("cost_parts", [])
	var i := next_level - 1
	return int(costs[i]) if i < costs.size() else -1


## Value of an effect at a given level. Lists are indexed by level - 1 (clamped to the list).
static func effect_at(id: String, key: String, lvl: int, default: Variant = null) -> Variant:
	var effects: Dictionary = track(id).get("effects", {})
	if not effects.has(key):
		return default
	var v: Variant = effects[key]
	if v is Array:
		var a: Array = v
		if a.is_empty():
			return default
		return a[clampi(lvl, MIN_LEVEL, a.size()) - 1]
	return v


## Value of an effect at the track's current level.
static func effect(state: ColonyState, id: String, key: String, default: Variant = null) -> Variant:
	return effect_at(id, key, level(state, id), default)


## Float form of effect(); `default` when missing.
static func effectf(state: ColonyState, id: String, key: String, default := 1.0) -> float:
	return float(effect(state, id, key, default))


## True when a station record (StationCatalog) is one where this track is upgraded.
static func station_serves(id: String, station_id: String, station: Dictionary) -> bool:
	var t := track(id)
	if t.is_empty():
		return false
	var ids: Array = t.get("station_ids", [])
	if not ids.is_empty():
		return ids.has(station_id)
	var kinds: Array = t.get("station_kinds", [])
	return kinds.has(String(station.get("kind", "")))


## Track ids served at a station (usually one, or none).
static func tracks_at(station_id: String, station: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for t: Dictionary in tracks():
		var id := String(t.get("id", ""))
		if station_serves(id, station_id, station):
			out.append(id)
	return out


## What still stops the next level, as [{"kind", "text"}] (empty = can upgrade now). `actor` may be null (then the
## specialty is not checked).
static func blockers(state: ColonyState, id: String, actor: CharacterState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t := track(id)
	if t.is_empty():
		out.append({"kind": "unknown", "text": "That upgrade path does not exist."})
		return out
	if is_derived(id):
		out.append({"kind": "derived", "text": "The rover's look follows its modules: upgrade them in the garage."})
		return out
	var now := level(state, id)
	if now >= max_level():
		out.append({"kind": "max", "text": "%s is fully upgraded (V%d)." % [track_name(id), now]})
		return out
	var spec := StringName(String(t.get("specialty", "")))
	if actor != null and spec != &"" and actor.specialty != spec:
		out.append({"kind": "specialty", "text": "Only the %s specialist can upgrade this." % String(StationPanels.SPECIALTY_WORDS.get(spec, String(spec))).to_lower()})
	var cost := cost_to_reach(id, now + 1)
	if cost > state.parts:
		out.append({"kind": "parts", "text": "Needs %d spare parts (the colony has %d)." % [cost, state.parts]})
	return out
