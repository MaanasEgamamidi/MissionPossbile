extends RefCounted
## Why a crew member died, in plain words for the player (ages 9 to 12). Host only: SessionService.recover_character
## fills CharacterState.last_death from these records at the moment of death, before the Med Bay respawn.
## Load by path: const DeathReasons := preload("res://scripts/survival/death_reasons.gd").
##
## Contract (docs/revisions/UPGRADES_BRIEF.md, "Death record"):
##   {"cause": id, "title": short words, "text": one or two sentences, "area": where, "at_hours": game hours, "count": n}
##
## Cause ids and the code paths that produce them:
##   no_suit_outside   SurvivalRuntime 4 s deadline, no suit, Mars air (exterior zone, or outside the garden dome glass)
##   suit_oxygen_out   SurvivalRuntime 4 s deadline, suit on but its tank is empty (or the colony has no suit tanks)
##   suit_damaged      SurvivalRuntime 4 s deadline, suit on but its seal is broken (integrity below the minimum)
##   airlock_pressure  SurvivalRuntime 4 s deadline inside the exit vestibule after it lost its air (seal leak/outer door)
##   cabin_air         SurvivalRuntime 4 s deadline in the base with total cabin pressure too low
##   low_oxygen        SurvivalRuntime 4 s deadline in the base with cabin oxygen below the safe level
##   co2               SurvivalRuntime 4 s deadline in the base with too much carbon dioxide
##   dehydration       ColonySim health loss with no clean water (the bigger health loss when water and food both run out)
##   starvation        ColonySim health loss with no food
##   cold, injury      no code path produces these yet; the records are ready for later systems
##   unknown           last resort (for example a direct recover_character call with nothing wrong)

const CAUSES := {
	"no_suit_outside": {"title": "No suit outside",
		"text": "You went outside without a sealed suit. Mars air is too thin to breathe. Put on a suit at the suit rack before you open the outer door."},
	"suit_oxygen_out": {"title": "Suit ran out of air",
		"text": "Your suit's oxygen tank was empty. Watch the tank bar and head back to the airlock when it gets low. The suit rack refills the tank."},
	"suit_damaged": {"title": "Suit seal broken",
		"text": "Your suit had a broken seal, so it could not hold air. Take a working suit from the suit rack before you go outside."},
	"airlock_pressure": {"title": "Airlock lost its air",
		"text": "The air leaked out of the exit tunnel while you were in it without a suit. Wear a suit in the airlock, and step back through the inner door when the sign says SUIT REQUIRED."},
	"cabin_air": {"title": "Base air too thin",
		"text": "The air pressure inside the base fell too low to breathe. Keep the oxygen and nitrogen tanks filled, and put on a suit when the air warning shows."},
	"low_oxygen": {"title": "Not enough oxygen",
		"text": "The air in the base ran low on oxygen. Keep the electrolyser or the CO2-oxygen unit running so the oxygen tanks stay full."},
	"co2": {"title": "Too much carbon dioxide",
		"text": "The air filled up with carbon dioxide, the gas we breathe out. Keep the CO2 scrubber and the cabin fans switched on and powered."},
	"starvation": {"title": "Out of food",
		"text": "The colony ran out of food and your body grew too weak. Grow and harvest crops so there are always meals in store."},
	"dehydration": {"title": "Out of water",
		"text": "The colony ran out of clean water. Keep the water recycler on and powered so used water is cleaned again."},
	"cold": {"title": "Too cold",
		"text": "Your body got too cold. Stay in heated, powered rooms and do not stay outside too long at night."},
	"injury": {"title": "Badly hurt",
		"text": "You were badly hurt. Rest at the med station in the Med Bay to heal before you go out again."},
	"unknown": {"title": "Brought back to the Med Bay",
		"text": "Something went wrong and the crew brought you back to the Med Bay. Check your health, air and suit before you head out."},
}

## Area words for zones whose map name is not a place a player would say.
const AREA_WORDS := {"Exterior": "Outside the base", "": "Somewhere in the colony"}


static func ids() -> PackedStringArray:
	return PackedStringArray(CAUSES.keys())


## Cause id of the hazard an unprotected actor is in now. `air` is a LocalPressure.query result for the actor.
static func hazard_id(session: SessionService, actor: CharacterState, air: Dictionary) -> String:
	if actor.suit_on and actor.suit_integrity < session.config.suit_min_integrity:
		return "suit_damaged"
	if actor.suit_on and (actor.suit_charge <= 0.0 or session.balance.suit_o2_capacity_kg <= 0.0):
		return "suit_oxygen_out"
	match String(air.get("kind", "")):
		"airlock":
			return "airlock_pressure"
		"exterior":
			return "no_suit_outside"
		"cabin":
			return String(air.get("reason", "cabin_air"))
	return "unknown"


## Cause id of a health-loss death from the colony simulation (water and food; pure-model air as a fallback).
static func health_id(session: SessionService, actor: CharacterState) -> String:
	var st := session.state
	var b := session.balance
	var unmet: Dictionary = st.unmet
	var thirsty := float(unmet.get("water_l", 0.0)) > 1e-9 or st.store(&"water_l") <= 0.0
	var hungry := float(unmet.get("food_meals", 0.0)) > 1e-9 or st.store(&"food_meals") <= 0.0
	if thirsty and hungry:
		return "dehydration" if b.health_loss_per_hour_no_water >= b.health_loss_per_hour_no_food else "starvation"
	if thirsty:
		return "dehydration"
	if hungry:
		return "starvation"
	if not session.sim.exposure_managed:
		# Standalone ColonySim keeps the old game-hour atmosphere damage; name it the same way.
		if actor.outside:
			return "suit_oxygen_out" if actor.suit_on else "no_suit_outside"
		if st.cabin_o2_kpa < b.o2_low_kpa:
			return "low_oxygen"
		if st.cabin_co2_kpa > b.co2_danger_kpa:
			return "co2"
	return "unknown"


## Best cause when the caller does not say (disconnect resolution, direct calls). Unknown only as a last resort.
static func classify(session: SessionService, actor: CharacterState) -> String:
	if actor.hazard_cause != "" and (actor.exposure_active or actor.lethal_exposure_seconds > 0.0):
		return actor.hazard_cause
	if actor.health <= 0.0:
		var from_health := health_id(session, actor)
		if from_health != "unknown":
			return from_health
	var air := session.survival.pressure.query(session, actor.position, actor.in_airlock_pressure_volume)
	if not bool(air.breathable) and not session.survival.functional_suit(actor):
		return hazard_id(session, actor, air)
	if actor.hazard_cause != "":
		return actor.hazard_cause
	return "unknown"


## Where the actor is now, in player words.
static func area_of(session: SessionService, actor: CharacterState, cause: String) -> String:
	var area := ""
	if actor.exposure_area != "" and cause in ["no_suit_outside", "suit_oxygen_out", "suit_damaged", "airlock_pressure", "cabin_air", "low_oxygen", "co2"]:
		area = actor.exposure_area
	elif session.zone_at_position.is_valid():
		area = String(session.zone_at_position.call(actor.position))
	return String(AREA_WORDS.get(area, area))


## The full record for `cause` (unknown ids fall back to "unknown"). `previous` is the actor's last record.
static func make_record(cause: String, area: String, at_hours: float, previous: Dictionary) -> Dictionary:
	var id := cause if CAUSES.has(cause) else "unknown"
	var words: Dictionary = CAUSES[id]
	return {"cause": id, "title": String(words.title), "text": String(words.text), "area": area,
		"at_hours": at_hours, "count": int(previous.get("count", 0)) + 1}


## Host: writes CharacterState.last_death for a death happening now, before the respawn moves the actor.
static func record(session: SessionService, actor: CharacterState, cause: String) -> Dictionary:
	var id := cause if cause != "" else classify(session, actor)
	actor.last_death = make_record(id, area_of(session, actor, id), session.state.sim_hours, actor.last_death)
	return actor.last_death
