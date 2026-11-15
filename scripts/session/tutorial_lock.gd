extends RefCounted
## Tutorial station access: suit racks and pickups always work. A pickup unlocks
## its room's broken spots and playback at the Command Room deck. Playing the first
## collected tape restores the other station features. Uncollected rooms stay locked.
## Still working all along: doors (not stations), the crew screen (C, not a station) and everything those need.
## A locked station shows no "[E]" prompt (GameHud), its panel closes at once with a plain message
## (TutorialPresenter), and its actions are refused on the host (ActionService) with the same message. After the
## tutorial everything works as before.
## Loaded by path (no class_name): const TutorialLock := preload("res://scripts/session/tutorial_lock.gd")

## Station kinds that always work during the tutorial.
const OPEN_KINDS: PackedStringArray = ["suits", "cassette_anchor"]
## Playback works with the first pickup.
const AFTER_TAPES_KINDS: PackedStringArray = ["cassette_player_anchor"]
## Actions that only end or release something; they never do work, so they are never refused.
const RELEASE_ACTIONS: Array[StringName] = [&"task_release", &"cassette_close", &"maintenance_cancel"]
const REASON := &"tutorial_locked"
const MESSAGE := "Play a collected tape at the Command Room cassette player to unlock the other station features."
const FIXED_MESSAGE := "This spot is fixed. Play a collected tape in the Command Room to unlock the other station features."
## Before the first tape is found (%d = the number of tapes).
const TAPES_MESSAGE := "Find a room tape first: follow the gold lines (%d tapes to find)."


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
	if AFTER_TAPES_KINDS.has(kind):
		return TutorialSystem.repairs_unlocked(state)
	if kind == "repair_task":
		var task_id := String(record.get("task_id", ""))
		return TutorialSystem.task_unlocked(state, task_id) and (PuzzleRegistry.is_broken(state, task_id) or TutorialSystem.specialty_features_unlocked(state))
	return TutorialSystem.specialty_features_unlocked(state)


## The plain message for a locked station.
static func message_for(state: ColonyState, record: Dictionary) -> String:
	if active(state) and String(record.get("kind", "")) == "repair_task" and not TutorialSystem.task_unlocked(state, String(record.get("task_id", ""))):
		return "Find the %s cassette to unlock this room's minigames." % TutorialSystem.room_words(String(record.get("room_id", "")))
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
