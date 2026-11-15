extends RefCounted
## Colony balance (upgrade paths plan §1.3, 2026-11-15): how well each life system is doing, as a share 0..1
## (1 = full / safe, 0 = empty / at the limit), and which one is the weakest. Maxing one thing while another is weak
## shows up here at once. Pure and read-only: the HUD chip (scripts/ui/hud/balance_chip.gd) and the permanent-choice
## card of the section panels ("You will be strong at X and still weak at Y") use it.
## Loaded by path (no class_name): const ColonyBalance := preload("res://scripts/upgrades/colony_balance.gd")
##
## Systems: food, air, water, power (store / capacity), radiation (the crew's worst dose against the 600 mSv career
## limit, plus the trend when the radiation system records one: state.radiation.dose_rate_msv_per_sol, projected
## TREND_SOLS ahead), health (average crew health; a crewmate in isolation counts as 0).

## NASA career limit (plan §5.2, source 45).
const DOSE_LIMIT_MSV := 600.0
## Sols ahead the dose trend is projected.
const TREND_SOLS := 30.0
## Share below which a system is "warn" / "urgent".
const WARN_SHARE := 0.25
const URGENT_SHARE := 0.1

## Order and words of the systems.
const SYSTEMS: Array[Dictionary] = [
	{"id": "food", "word": "food", "symbol": "❀"},
	{"id": "air", "word": "air", "symbol": "O₂"},
	{"id": "water", "word": "water", "symbol": "≈"},
	{"id": "power", "word": "power", "symbol": "⚡"},
	{"id": "radiation", "word": "radiation", "symbol": "☢"},
	{"id": "health", "word": "health", "symbol": "✚"},
]

## Words for what a track helps that is not a life system (data/area_levels.json "helps").
const OTHER_WORDS := {"comms": "radio", "parts": "spare parts", "ores": "finding ores"}


static func _share(st: ColonyState, store: StringName) -> float:
	var cap := float(st.capacities.get(store, 0.0))
	if cap <= 0.0:
		return 1.0
	return clampf(st.store(store) / cap, 0.0, 1.0)


## Every system as [{"id", "word", "symbol", "share", "level"}], in SYSTEMS order.
static func systems(st: ColonyState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if st == null:
		return out
	var crew := st.active_characters()
	var worst_dose := 0.0
	var health_sum := 0.0
	for c: CharacterState in crew:
		worst_dose = maxf(worst_dose, c.dose_msv)
		health_sum += 0.0 if not c.isolation.is_empty() else clampf(c.health, 0.0, 100.0)
	var rate := float(st.radiation.get("dose_rate_msv_per_sol", 0.0))
	var dose_ahead := worst_dose + maxf(0.0, rate) * TREND_SOLS
	for s: Dictionary in SYSTEMS:
		var share := 1.0
		match String(s.id):
			"food": share = _share(st, &"food_meals")
			"air": share = _share(st, &"oxygen_kg")
			"water": share = _share(st, &"water_l")
			"power": share = _share(st, &"battery_kwh")
			"radiation": share = clampf(1.0 - dose_ahead / DOSE_LIMIT_MSV, 0.0, 1.0)
			"health": share = health_sum / (100.0 * float(crew.size())) if not crew.is_empty() else 1.0
		var row := s.duplicate()
		row["share"] = share
		row["level"] = level_of(share)
		out.append(row)
	return out


static func level_of(share: float) -> StringName:
	if share < URGENT_SHARE:
		return &"urgent"
	if share < WARN_SHARE:
		return &"warn"
	return &"ok"


## The weakest system, skipping the ids in `exclude` ({} when there is none).
static func weakest(st: ColonyState, exclude: PackedStringArray = PackedStringArray()) -> Dictionary:
	var best: Dictionary = {}
	for row: Dictionary in systems(st):
		if exclude.has(String(row.id)):
			continue
		if best.is_empty() or float(row.share) < float(best.share):
			best = row
	return best


## Word for a system or another "helps" id ("power", "radio").
static func word_of(id: String) -> String:
	for s: Dictionary in SYSTEMS:
		if String(s.id) == id:
			return String(s.word)
	return String(OTHER_WORDS.get(id, id.replace("_", " ")))


## The permanent-choice sentence for building a track: "You will be strong at power and still weak at water."
static func strong_weak_text(st: ColonyState, track_id: String) -> String:
	var helps := PackedStringArray()
	for h in AreaLevels.track(track_id).get("helps", []):
		helps.append(String(h))
	var strong := PackedStringArray()
	for h: String in helps:
		strong.append(word_of(h))
	var weak := weakest(st, helps)
	var strong_text := " and ".join(strong) if not strong.is_empty() else AreaLevels.track_name(track_id).to_lower()
	if weak.is_empty():
		return "You will be strong at %s." % strong_text
	return "You will be strong at %s and still weak at %s." % [strong_text, String(weak.word)]
