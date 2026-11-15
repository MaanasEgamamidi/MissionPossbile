extends RefCounted
## Tutorial station lock (owner 2026-11-14): while the colony is in tutorial mode (TutorialSystem.tutorial_active),
## only a few stations respond to E, in two steps:
##   1. Tapes first: until the crew has found every room tape (TutorialSystem.repairs_unlocked), only the room cassette
##      pickups and the suit rack work. Gold lines lead to the tapes (scripts/cassettes/tape_trail_presenter.gd); every
##      other station, the broken spots and the Command Room cassette player included, says "Find all 6 tapes first:
##      follow the gold lines."
##   2. Once every tape is found: the tapes, the suit rack, the Command Room cassette player and every repair_task
##      station whose spot is still broken (its mini-game).
## Still working all along: doors (not stations), the crew screen (C, not a station) and everything those need.
## A locked station shows no "[E]" prompt (GameHud), its panel closes at once with a plain message
## (TutorialPresenter), and its actions are refused on the host (ActionService) with the same message. After the
## tutorial everything works as before.
## Loaded by path (no class_name): const TutorialLock := preload("res://scripts/session/tutorial_lock.gd")

## Station kinds that always work during the tutorial.
const OPEN_KINDS: PackedStringArray = ["suits", "cassette_anchor"]
## Station kinds that work once every tape is found (repair_task: only while its spot is broken).
const AFTER_TAPES_KINDS: PackedStringArray = ["cassette_player_anchor"]
## Actions that only end or release something; they never do work, so they are never refused.
const RELEASE_ACTIONS: Array[StringName] = [&"task_release", &"cassette_close", &"maintenance_cancel"]
const REASON := &"tutorial_locked"
const MESSAGE := "Not yet: Mission Control needs the base fixed first. For now only the tapes and the broken spots work."
const FIXED_MESSAGE := "This spot is fixed. The other machines work again when the whole base is fixed."
## Before every tape is found (%d = the number of tapes).
const TAPES_MESSAGE := "Find all %d tapes first: follow the gold lines."


## True while stations are locked in this colony.
static func active(state: ColonyState) -> bool:
	return state != null and TutorialSystem.tutorial_active(state)


## True when E may use the station `record` (a state.stations entry) now.
static func station_usable(state: ColonyState, record: Dictionary) -> bool:
	if not active(state) or record.is_empty():
		return true
	var kind := String(record.get("kind", ""))
	if OPEN_KINDS.has(kind):
		return true
	if not TutorialSystem.repairs_unlocked(state):
		return false
	if AFTER_TAPES_KINDS.has(kind):
		return true
	if kind == "repair_task":
		return PuzzleRegistry.is_broken(state, String(record.get("task_id", "")))
	return false


## The plain message for a locked station.
static func message_for(state: ColonyState, record: Dictionary) -> String:
	if active(state) and not TutorialSystem.repairs_unlocked(state):
		return TAPES_MESSAGE % TutorialSystem.tape_count()
	if String(record.get("kind", "")) == "repair_task" and TutorialSystem.is_fixed(state, String(record.get("task_id", ""))):
		return FIXED_MESSAGE
	return MESSAGE


## Host: the refusal for a resolved request (an ActionService.Context), or null when the lock lets it through.
static func refusal(ctx: RefCounted) -> ActionResult:
	var state: ColonyState = ctx.get(&"state")
	if not active(state):
		return null
	var d: RefCounted = ctx.get(&"definition")
	var request: ActionRequest = ctx.get(&"request")
	if d == null or request == null or StringName(d.get(&"target_kind")) != &"station" or RELEASE_ACTIONS.has(request.action):
		return null
	var target: Dictionary = ctx.get(&"target")
	if target.is_empty() or station_usable(state, target):
		return null
	return ActionResult.failure(request.request_id, REASON, message_for(state, target))
