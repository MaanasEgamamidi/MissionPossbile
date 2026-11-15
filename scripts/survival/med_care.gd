extends RefCounted
## Healing at the med station and the health a crew member wakes up with in the Med Bay. Host only.
## Load by path: const MedCare := preload("res://scripts/survival/med_care.gd").
##
## Before this there was no healing at all: the med station only showed each crew member's health. Now an active,
## safe crew member standing within reach of a station of kind "heal" (map object md_heal_station) gets health back
## every unpaused real second, while the station's room has power. The Med bay upgrade track (data/area_levels.json,
## track "health") scales it: heal_rate_factor multiplies the rate, recovery_health_bonus adds to the respawn health.

## Designer balance (not NASA data): health points per unpaused real second at Med bay V1, so 50 -> 100 takes 50 s.
const HEAL_PER_SECOND := 1.0
## Designer balance: the health bar runs 0..100.
const MAX_HEALTH := 100.0
const TRACK := "health"


## Health per real second at the colony's current Med bay level.
static func heal_rate(state: ColonyState) -> float:
	return HEAL_PER_SECOND * maxf(0.0, AreaLevels.effectf(state, TRACK, "heal_rate_factor", 1.0))


## Health after a Med Bay respawn: GameBalance.recovery_health plus the level's bonus, never above MAX_HEALTH.
static func recovery_health(session: SessionService) -> float:
	var bonus := AreaLevels.effectf(session.state, TRACK, "recovery_health_bonus", 0.0)
	return clampf(session.balance.recovery_health + bonus, 0.0, MAX_HEALTH)


## The heal station the actor can use now, or "" (needs reach and room power).
static func station_in_reach(session: SessionService, actor: CharacterState) -> String:
	for id: String in session.state.stations:
		var record: Dictionary = session.state.stations[id]
		if String(record.get("kind", "")) != "heal":
			continue
		if not ActionService.TutorialLock.station_usable(session.state, record) \
				or RepairCatalog.is_broken(session.state, RepairCatalog.task_for_station(session.state, id)):
			continue
		if actor.position.distance_to(CharacterState._v3(record.get("position", []))) > session.config.interact_distance_m:
			continue
		if not session.state.is_zone_powered(String(record.get("zone", "Med Bay"))):
			continue
		return id
	return ""


## True when healing can run for this actor: alive, hurt, controlled, and fully clear of any air danger.
static func can_heal(session: SessionService, actor: CharacterState) -> bool:
	return actor.is_active() and actor.health > 0.0 and actor.health < MAX_HEALTH and not actor.exposure_active \
		and actor.lethal_exposure_seconds <= 0.0 and station_in_reach(session, actor) != ""


## One host real-time step. Returns the health added.
static func advance_actor(session: SessionService, actor: CharacterState, seconds: float) -> float:
	if seconds <= 0.0 or not can_heal(session, actor):
		return 0.0
	var before := actor.health
	actor.health = minf(MAX_HEALTH, actor.health + heal_rate(session.state) * seconds)
	return actor.health - before
