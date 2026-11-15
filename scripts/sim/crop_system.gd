class_name CropSystem
extends RefCounted
## Grows the greenhouse crops every tick (Prompt 08, food part). Host only; pure state changes, no nodes.
## SessionService runs it after water, oxygen and cabin air (ColonySim.post_systems), so it sees this tick's delivered
## greenhouse water and this tick's power (load shedding).
##
## state.crops (plain JSON data, saved and replicated as is):
##   "beds": station id -> {
##       "crop": "" | crop id, "stage": "empty" | stage of data/crops.json | "wilted", "progress": 0..1,
##       "water_l": soil water in litres, "nutrients": 0..1, "valve": water on/off, "flow": drip line flow 0..1,
##       "dry_hours": game hours completely dry, "rate": growth per game hour (last tick), "light": 0 or 1,
##       "factors": {"light", "water", "nutrients"}, "symptoms": [ids], "planted_at": game hours,
##       "inspection": last measurement, "trial": one diagnosis in progress (see FoodActions) }
##   "seen_greenhouse_l": ledger greenhouse_water_l already handed out to the beds
##   "delivered_l_per_hour", "absorbed_l_per_hour": last tick, for panels
##   "totals": {"delivered_l", "absorbed_l"} since the game began
##   "alerts": [{"id", "level", "text", "since_hours"}] (announced once through events.system_alert)
##   "applied_results": lab result ids already applied to the beds (sci_evidence_settings)
##   "schedule": {"last": words} (food_scheduled_care)
##
## Growth per game hour = base rate x light factor x water factor x nutrient factor.
##   light: 1 when the grow lights (the Greenhouse lighting circuit) are switched on and not shed, else 0 (stops).
##   water: soil water share / FoodBalance.water_good, at most 1 (slows when low, stops when dry).
##   nutrients: 1 in the good band, down to FoodBalance.nutrient_floor_factor with none (slows).
## Water: the beds share only the greenhouse water LifeSupportModel actually delivered this tick (ledger
## greenhouse_water_l). That water is already booked to the wastewater tank (the plants give it back as condensate
## and drainage), so the beds create no water and the ledger identities are unchanged. A bed left completely dry for
## a sol wilts and must be replanted; an alert says so first.
##
## Upgrade paths (data/area_levels.json, owner request 2026-11-14). Both are read here and nowhere else:
##   food (Greenhouse grow racks): every harvest gives the crop's meals x food.yield_factor (harvest_meals). The
##     factor grows with the number of grow layers (food.grow_layers: 1, 2, 3, 4), a bit less than one extra crop per
##     layer because the upper trays get less light. Designer balance, not a NASA figure.
##   garden (Garden dome planting): the dome's plants add garden.meals_per_sol meals to the food store, a little every
##     tick (host only, rate x game hours, so it is deterministic and the same at any game speed). The meals are booked
##     as meals_harvested, so the food ledger identity holds, and their total is kept in crops.garden (saved and
##     replicated with the rest of state.crops). Designer balance.

## Words for each stage.
const STAGE_WORDS := {
	"empty": "Empty", "seed": "Seed", "sprout": "Sprout", "leafy": "Leafy", "flowering": "Flowering",
	"ready": "Ready to harvest", "wilted": "Wilted",
}
## Each symptom: what you see and its cause, in words.
const SYMPTOMS := {
	"wilting": {"see": "Wilting leaves", "cause": "the soil is too dry", "input": "water"},
	"yellow_leaves": {"see": "Yellow leaves", "cause": "too few nutrients", "input": "nutrients"},
	"leggy_pale": {"see": "Tall, thin and pale stems", "cause": "too little light", "input": "light"},
}
## Order symptoms are listed in (most urgent first).
const SYMPTOM_ORDER: Array[String] = ["wilting", "leggy_pale", "yellow_leaves"]

## Food numbers; null = FoodBalance.shared().
var food: FoodBalance


func step(state: ColonyState, _balance: GameBalance, phase: float, dt_hours: float, events: GameEvents) -> void:
	if dt_hours <= 0.0:
		return
	var fb := food if food != null else FoodBalance.shared()
	var crops := ensure(state)
	var beds: Dictionary = crops.beds
	var lit := lights_working(state, fb)
	var delivered := _take_delivered(state, crops)
	if state.has_upgrade("food_scheduled_care"):
		_run_schedule(state, fb, crops, phase, dt_hours, events)
	var reliable := state.has_upgrade("food_irrigation_reliability")
	var metered := state.has_upgrade("food_nutrient_metering")
	var cap := fb.bed_water_capacity_l
	var ids: Array = beds.keys()
	ids.sort()

	# ---- drip lines: what each bed can take this tick
	var want := {}
	for id: String in ids:
		var b: Dictionary = beds[id]
		var alive := is_alive(b)
		if reliable and alive:
			b["valve"] = true
			b["flow"] = 1.0
		elif bool(b.valve) and alive:
			b["flow"] = clampf(float(b.flow) - fb.drip_clog_per_sol * dt_hours / GameConfig.SOL_HOURS, 0.0, 1.0)
		if bool(b.valve) and alive:
			want[id] = minf(maxf(0.0, cap - float(b.water_l)), float(b.flow) * fb.drip_max_l_per_hour * dt_hours)
	var given := share_out(delivered, want)
	var absorbed := 0.0

	# ---- every bed
	for id: String in ids:
		var b: Dictionary = beds[id]
		var got := float(given.get(id, 0.0))
		b["water_l"] = minf(cap, float(b.water_l) + got)
		absorbed += got
		_grow(state, fb, b, id, lit, metered, dt_hours, events)

	crops["delivered_l_per_hour"] = delivered / dt_hours
	crops["absorbed_l_per_hour"] = absorbed / dt_hours
	var totals: Dictionary = crops.totals
	totals["delivered_l"] = float(totals.get("delivered_l", 0.0)) + delivered
	totals["absorbed_l"] = float(totals.get("absorbed_l", 0.0)) + absorbed
	_grow_garden(state, crops, dt_hours)
	_update_alerts(state, fb, crops, lit, events)


# ---------------------------------------------------------------- upgrade paths (food and garden tracks)

## Harvest multiplier of the greenhouse grow racks at their current level (food.yield_factor, 1 at V1).
static func yield_factor(state: ColonyState) -> float:
	return maxf(0.0, AreaLevels.effectf(state, "food", "yield_factor", 1.0))


## Grow layers in the greenhouse racks at their current level (food.grow_layers, 1 at V1).
static func grow_layers(state: ColonyState) -> int:
	return maxi(1, int(AreaLevels.effect(state, "food", "grow_layers", 1)))


## THE place where the grow layers make more food: meals one harvest of `crop_id` gives now. FoodActions.harvest and
## the panels both use it, so what a panel promises is what a harvest adds.
static func harvest_meals(state: ColonyState, crop_id: String) -> float:
	return float(FoodBalance.crop(crop_id).get("meals", 0.0)) * yield_factor(state)


## Plain words about the racks for panels and harvest answers ("" at V1, where nothing is extra).
static func yield_words(state: ColonyState) -> String:
	var layers := grow_layers(state)
	if layers <= 1:
		return ""
	return "The greenhouse racks have %d grow layers, so every harvest gives %s times the food." % [layers, _num(yield_factor(state), 1)]


## Meals a sol the Garden dome's plants add now (garden.meals_per_sol, 0 at V1).
static func garden_meals_per_sol(state: ColonyState) -> float:
	return maxf(0.0, AreaLevels.effectf(state, "garden", "meals_per_sol", 0.0))


## Meals the Garden dome has added to the food store since the game began.
static func garden_meals_total(state: ColonyState) -> float:
	var g: Variant = state.crops.get("garden", null)
	return float((g as Dictionary).get("meals_total", 0.0)) if g is Dictionary else 0.0


## The Garden dome's produce for this tick: rate x game hours into the food store (only what fits).
static func _grow_garden(state: ColonyState, crops: Dictionary, dt_hours: float) -> void:
	var per_sol := garden_meals_per_sol(state)
	if per_sol <= 0.0 or dt_hours <= 0.0:
		return
	var added := state.add_to_store(&"food_meals", per_sol * dt_hours / GameConfig.SOL_HOURS)
	state.ledger["meals_harvested"] = float(state.ledger.get("meals_harvested", 0.0)) + added
	if not (crops.get("garden", null) is Dictionary):
		crops["garden"] = {"meals_total": 0.0}
	var g: Dictionary = crops.garden
	g["meals_total"] = float(g.get("meals_total", 0.0)) + added
	g["meals_per_sol"] = per_sol


## The beds' dictionary, created if missing: one bed for every station of kind "bed". Host only (it writes state).
static func ensure(state: ColonyState) -> Dictionary:
	var crops := state.crops
	if not (crops.get("beds", null) is Dictionary):
		crops["beds"] = {}
	if not crops.has("seen_greenhouse_l"):
		# a new game starts at 0; an older save already delivered water nobody grew anything with
		crops["seen_greenhouse_l"] = 0.0 if state.sim_hours <= 0.0 else float(state.ledger.get("greenhouse_water_l", 0.0))
	for key: String in ["totals", "schedule"]:
		if not (crops.get(key, null) is Dictionary):
			crops[key] = {}
	for key: String in ["alerts", "applied_results"]:
		if not (crops.get(key, null) is Array):
			crops[key] = []
	for key: String in ["delivered_l_per_hour", "absorbed_l_per_hour"]:
		if not crops.has(key):
			crops[key] = 0.0
	var beds: Dictionary = crops.beds
	for id: String in state.stations:
		if String((state.stations[id] as Dictionary).get("kind", "")) == "bed" and not beds.has(id):
			beds[id] = new_bed()
	return crops


## A bed as it is at arrival: empty, moist soil, water line open and clean.
## Puts a nutrient setting (0..1) from a lab result into living beds: one bed by id, or every bed for "all_beds"
## or the greenhouse console. Returns how many beds changed. Used by both ScienceActions.apply_result and
## FoodActions.apply_nutrient_result, so a lab result changes the beds the same way whichever action applies it.
static func apply_nutrient_setting(state: ColonyState, where: String, value: float) -> int:
	var crops := ensure(state)
	var targets: Array = []
	if (crops.beds as Dictionary).has(where):
		targets = [where]
	else:
		targets = bed_ids(state)
	var count := 0
	for id in targets:
		var b: Dictionary = (crops.beds as Dictionary).get(String(id), {})
		if is_alive(b):
			b["nutrients"] = clampf(value, 0.0, 1.0)
			count += 1
	return count


static func new_bed() -> Dictionary:
	var fb := FoodBalance.shared()
	return {"crop": "", "stage": "empty", "progress": 0.0, "water_l": 0.6 * fb.bed_water_capacity_l, "nutrients": 0.0,
		"valve": true, "flow": 1.0, "dry_hours": 0.0, "rate": 0.0, "light": 0.0,
		"factors": {"light": 0.0, "water": 0.0, "nutrients": 0.0}, "symptoms": [], "planted_at": -1.0, "inspection": {}, "trial": {}}


## Read-only access for panels: the bed record, or {} (never creates anything).
static func bed(state: ColonyState, id: String) -> Dictionary:
	var beds: Variant = state.crops.get("beds", {})
	return (beds as Dictionary).get(id, {}) as Dictionary if beds is Dictionary else {}


## Station ids of every bed, sorted.
static func bed_ids(state: ColonyState) -> Array:
	var out: Array = []
	for id: String in state.stations:
		if String((state.stations[id] as Dictionary).get("kind", "")) == "bed":
			out.append(id)
	out.sort()
	return out


## The bed's name in words ("Planter 3").
static func bed_name(state: ColonyState, id: String) -> String:
	return String((state.stations.get(id, {}) as Dictionary).get("name", id))


## True if a crop grows (or waits for harvest) in the bed and it has not wilted.
static func is_alive(b: Dictionary) -> bool:
	return String(b.get("crop", "")) != "" and String(b.get("stage", "empty")) != "wilted"


## True if the bed has a living crop that is still growing.
static func is_growing(b: Dictionary) -> bool:
	return is_alive(b) and String(b.get("stage", "")) != "ready"


## True if the grow lights shine this tick: the light zone is switched on and its load was not shed.
static func lights_working(state: ColonyState, fb: FoodBalance = null) -> bool:
	var zone := (fb if fb != null else FoodBalance.shared()).light_zone
	return state.is_zone_powered(zone) and not state.shed.has("greenhouse")


## True if the grow-light switch (the light zone's power switch) is on.
static func lights_switched_on(state: ColonyState) -> bool:
	return state.is_zone_powered(FoodBalance.shared().light_zone)


## Splits `amount` between claims {id: wanted} fairly: everyone gets the same share until their claim is met.
## Returns {id: given}; the sum never exceeds `amount` or the claims.
static func share_out(amount: float, claims: Dictionary) -> Dictionary:
	var given := {}
	var open: Array = []
	for id: Variant in claims:
		given[id] = 0.0
		if float(claims[id]) > 0.0:
			open.append(id)
	var left := maxf(0.0, amount)
	while left > 1e-12 and not open.is_empty():
		var each := left / float(open.size())
		var still: Array = []
		for id: Variant in open:
			var need := float(claims[id]) - float(given[id])
			var take := minf(each, need)
			given[id] = float(given[id]) + take
			left -= take
			if float(claims[id]) - float(given[id]) > 1e-12:
				still.append(id)
		if still.size() == open.size() and each <= 1e-15:
			break
		open = still
	return given


## The stage a crop is at for `progress` 0..1.
static func stage_for(crop_id: String, progress: float) -> String:
	var c := FoodBalance.crop(crop_id)
	var stages: Array = c.get("stages", ["seed", "sprout", "leafy", "ready"])
	var starts: Array = c.get("stage_starts", [0.0, 0.15, 0.45, 1.0])
	var out := String(stages[0])
	for i in stages.size():
		if progress >= float(starts[i]) - 1e-9:
			out = String(stages[i])
	return out


## Game hours until harvest at the current rate, or -1 when the crop is not growing now.
static func hours_to_harvest(b: Dictionary) -> float:
	if String(b.get("stage", "")) == "ready":
		return 0.0
	var rate := float(b.get("rate", 0.0))
	if not is_growing(b) or rate <= 1e-12:
		return -1.0
	return (1.0 - float(b.progress)) / rate


## Game hours a whole cycle takes at full speed.
static func cycle_hours(crop_id: String) -> float:
	return float(FoodBalance.crop(crop_id).get("cycle_sols", 0.0)) * GameConfig.SOL_HOURS


## Symptoms a bed shows now, most urgent first (empty for an empty, wilted or healthy bed).
static func symptoms_of(state: ColonyState, b: Dictionary, fb: FoodBalance = null) -> Array:
	var f := fb if fb != null else FoodBalance.shared()
	var out: Array = []
	if not is_alive(b):
		return out
	var share := float(b.get("water_l", 0.0)) / maxf(f.bed_water_capacity_l, 1e-9)
	if share < f.water_good:
		out.append("wilting")
	if not lights_working(state, f):
		out.append("leggy_pale")
	if float(b.get("nutrients", 0.0)) < f.nutrient_good_low:
		out.append("yellow_leaves")
	return out


## The measurement that proves a symptom, in words with units.
static func measurement_text(state: ColonyState, b: Dictionary, symptom: String, fb: FoodBalance = null) -> String:
	var f := fb if fb != null else FoodBalance.shared()
	match symptom:
		"wilting":
			var share := float(b.get("water_l", 0.0)) / maxf(f.bed_water_capacity_l, 1e-9)
			return "Soil water %d %% (%s of %s L); plants grow at full speed from %d %%." % [roundi(share * 100.0),
				_num(float(b.get("water_l", 0.0))), _num(f.bed_water_capacity_l), roundi(f.water_good * 100.0)]
		"yellow_leaves":
			return "Nutrients %d %%; the good band is %d to %d %%." % [roundi(float(b.get("nutrients", 0.0)) * 100.0),
				roundi(f.nutrient_good_low * 100.0), roundi(f.nutrient_good_high * 100.0)]
		"leggy_pale":
			var why := "switched off" if not lights_switched_on(state) else "without power (shed)"
			return "Light 0 %%: the grow lights are %s." % why
	return ""


## "Yellow leaves: too few nutrients. Nutrients 25 %; …" for one symptom.
static func symptom_sentence(state: ColonyState, b: Dictionary, symptom: String) -> String:
	var s: Dictionary = SYMPTOMS.get(symptom, {})
	return "%s: %s. %s" % [String(s.get("see", symptom)), String(s.get("cause", "")), measurement_text(state, b, symptom)]


## Food alerts as [id, level, text] (the same list the HUD hears through events.system_alert).
static func alerts(state: ColonyState) -> Array:
	var out: Array = []
	for a: Dictionary in state.crops.get("alerts", []):
		out.append([String(a.id), String(a.level), String(a.text)])
	return out


# ---------------------------------------------------------------- inside the tick

## Water LifeSupportModel delivered to the greenhouse since the last tick (litres).
static func _take_delivered(state: ColonyState, crops: Dictionary) -> float:
	var now := float(state.ledger.get("greenhouse_water_l", 0.0))
	var delivered := maxf(0.0, now - float(crops.get("seen_greenhouse_l", now)))
	crops["seen_greenhouse_l"] = now
	return delivered


func _grow(state: ColonyState, fb: FoodBalance, b: Dictionary, id: String, lit: bool, metered: bool, dt: float, events: GameEvents) -> void:
	var cap := fb.bed_water_capacity_l
	b["light"] = 1.0 if lit else 0.0
	if not is_alive(b):
		b["rate"] = 0.0
		b["symptoms"] = []
		b["factors"] = {"light": float(b.light), "water": 0.0, "nutrients": 0.0}
		return
	var crop := FoodBalance.crop(String(b.crop))
	# Metering holds the lab's nutrient setting for this bed when one was applied (Prompt 08: a lab result becomes a
	# real equipment setting), otherwise the default target.
	var lab_target := ScienceActions.nutrient_target(state, id)
	var hold := lab_target if lab_target >= 0.0 else fb.metering_target
	if metered and float(b.nutrients) < hold:
		b["nutrients"] = hold
	var share := float(b.water_l) / maxf(cap, 1e-9)
	var f_light := 1.0 if lit else 0.0
	var f_water := fb.water_factor(share)
	var f_nut := fb.nutrient_factor(float(b.nutrients))
	b["factors"] = {"light": f_light, "water": f_water, "nutrients": f_nut}
	var rate := 0.0
	if String(b.stage) != "ready":
		rate = FoodBalance.base_rate(String(b.crop)) * f_light * f_water * f_nut
		var grown := minf(rate * dt, 1.0 - float(b.progress))
		b["progress"] = clampf(float(b.progress) + grown, 0.0, 1.0)
		if 1.0 - float(b.progress) < 1e-9:
			b["progress"] = 1.0
		b["nutrients"] = maxf(0.0, float(b.nutrients) - float(crop.get("nutrient_use_per_cycle", 0.0)) * grown)
		b["stage"] = stage_for(String(b.crop), float(b.progress))
	b["rate"] = rate
	# the plants drink from the soil
	var used := minf(float(b.water_l), float(crop.get("water_l_per_hour", 0.0)) * dt)
	b["water_l"] = maxf(0.0, float(b.water_l) - used)
	if float(b.water_l) <= 1e-9:
		b["water_l"] = 0.0
		b["dry_hours"] = float(b.dry_hours) + dt
	else:
		b["dry_hours"] = 0.0
	if float(b.dry_hours) >= fb.wilt_after_dry_hours - 1e-9:
		b["stage"] = "wilted"
		b["rate"] = 0.0
		b["trial"] = {}
	b["symptoms"] = symptoms_of(state, b, fb)
	_observe_trial(state, fb, b, id, events)


## A diagnosis in progress: after exactly one input was changed, a rise of the growth rate is the response.
func _observe_trial(state: ColonyState, fb: FoodBalance, b: Dictionary, id: String, events: GameEvents) -> void:
	var t: Dictionary = b.get("trial", {})
	if String(t.get("status", "")) != "one_change":
		return
	var before := float(t.get("rate_before", 0.0))
	var rate := float(b.rate)
	if rate > before * (1.0 + fb.response_rise) + 1e-12:
		t["status"] = "improved"
		t["rate_after"] = rate
		t["observed_at"] = state.sim_hours
		ProgressEvidence.record(state, events, &"food_observe_response", "food", StringName(String(t.get("by", ""))),
			{"bed": id, "input": String((t.get("changed", [""]) as Array)[0]), "rate_before": before, "rate_after": rate})
	elif state.sim_hours - float(t.get("changed_at", state.sim_hours)) > fb.trial_window_hours:
		t["status"] = "no_change"


## food_scheduled_care: lights on while something grows (off when nothing does), every planted bed watered, the
## drip lines flushed once a sol, and enough greenhouse water allocated. It never stops by itself.
func _run_schedule(state: ColonyState, fb: FoodBalance, crops: Dictionary, phase: float, dt: float, events: GameEvents) -> void:
	var growing := 0
	var planted := 0
	for id: String in crops.beds:
		var b: Dictionary = crops.beds[id]
		if is_alive(b):
			planted += 1
			b["valve"] = true
		if is_growing(b):
			growing += 1
	var zone := fb.light_zone
	var schedule: Dictionary = crops.schedule
	if state.zones.has(zone):
		var on := growing > 0
		if state.is_zone_powered(zone) != on:
			(state.zones[zone] as Dictionary)["powered"] = on
			schedule["last"] = "Schedule: grow lights %s (%d beds growing)." % ["on" if on else "off", growing]
			if events != null:
				events.zone_power_changed.emit(zone, on)
	var need := float(planted) * fb.schedule_l_per_bed_hour
	if planted > 0 and float(state.water_allocation.get("greenhouse_l_per_hour", 0.0)) < need - 1e-9:
		state.water_allocation["greenhouse_l_per_hour"] = need
		schedule["last"] = "Schedule: greenhouse water set to %s L per hour." % _num(need, 2)
	var end := phase + dt / GameConfig.SOL_HOURS
	if floorf(end - fb.schedule_flush_phase) > floorf(phase - fb.schedule_flush_phase):
		for id: String in crops.beds:
			(crops.beds[id] as Dictionary)["flow"] = 1.0
		schedule["last_flush_hours"] = state.sim_hours
		schedule["last"] = "Schedule: every drip line was flushed."


func _update_alerts(state: ColonyState, fb: FoodBalance, crops: Dictionary, lit: bool, events: GameEvents) -> void:
	var entries: Array = []
	var growing := 0
	for id: String in bed_ids(state):
		var b: Dictionary = bed(state, id)
		if b.is_empty():
			continue
		var name := bed_name(state, id)
		var what := String(FoodBalance.crop(String(b.crop)).get("name", "plant")).to_lower()
		if String(b.stage) == "wilted":
			entries.append(["bed_wilted_" + id, "warn", "%s: the %s wilted after a sol without water. Clear the bed by planting again." % [name, what]])
			continue
		if not is_alive(b):
			continue
		if is_growing(b):
			growing += 1
		if float(b.water_l) <= 0.0:
			var left := maxf(0.0, fb.wilt_after_dry_hours - float(b.dry_hours))
			entries.append(["bed_dry_" + id, "urgent", "%s is dry: the %s has stopped growing and will wilt in about %d hours unless it gets water. Open its water and send water to the greenhouse." % [name, what, ceili(left)]])
		elif float(b.water_l) / maxf(fb.bed_water_capacity_l, 1e-9) < fb.water_low:
			entries.append(["bed_water_low_" + id, "warn", "%s: the soil is drying out (%d %% water). The %s is wilting." % [name, roundi(100.0 * float(b.water_l) / fb.bed_water_capacity_l), what]])
		if float(b.nutrients) < fb.nutrient_good_low:
			entries.append(["bed_nutrients_low_" + id, "info", "%s: yellow leaves. Nutrients are at %d %%; add nutrients." % [name, roundi(float(b.nutrients) * 100.0)]])
		if bool(b.valve) and float(b.flow) < 0.5 and not state.has_upgrade("food_irrigation_reliability"):
			entries.append(["bed_clogged_" + id, "info", "%s: its drip line is clogging (%d %% flow). Switch its water on again to flush it." % [name, roundi(float(b.flow) * 100.0)]])
		if String(b.stage) == "ready":
			entries.append(["bed_ready_" + id, "info", "%s: the %s is ready to harvest." % [name, what]])
	if growing > 0 and not lit:
		entries.append(["grow_lights_off", "warn", "Grow lights are off or have no power: %d beds have stopped growing." % growing])
	var previous := {}
	for a: Dictionary in crops.alerts:
		previous[String(a.id)] = a
	var fresh: Array = []
	for e: Array in entries:
		var id := String(e[0])
		var since := state.sim_hours
		if previous.has(id):
			since = float((previous[id] as Dictionary).since_hours)
		fresh.append({"id": id, "level": String(e[1]), "text": String(e[2]), "since_hours": since})
		if not previous.has(id) and events != null:
			events.system_alert.emit(StringName(id), StringName(e[1]), String(e[2]))
	crops["alerts"] = fresh


static func _num(value: float, decimals := 1) -> String:
	var t := String.num(value, decimals)
	if t.contains("."):
		t = t.rstrip("0").rstrip(".")
	return "0" if t == "-0" else t
