class_name ActionResult
extends RefCounted
## The host's answer to an ActionRequest: it worked, or exactly why it did not.

## Plain-language text for each failure reason (reading age 9 to 12). Presentation may replace these.
const MESSAGES := {
	&"bad_request": "That request did not make sense.",
	&"unknown_action": "Nobody knows how to do that yet.",
	&"host_only": "Only the host can change that.",
	&"no_actor": "Choose a crew member first.",
	&"not_owner": "That crew member is not yours to control.",
	&"unknown_target": "That thing is not here.",
	&"wrong_target": "That does not work on this.",
	&"too_far": "Move closer to use this.",
	&"wrong_specialty": "This job needs a different specialist.",
	&"missing_prerequisite": "Something else has to be done first.",
	&"insufficient": "There is not enough to do that.",
	&"cargo_full": "Your hands and pack are full.",
	&"already_held": "Someone is already carrying that.",
	&"not_held": "You are not carrying that.",
	&"character_taken": "Another player is already that crew member.",
	&"already_yours": "You are already that crew member.",
	&"switch_disabled": "With four players, everyone keeps their own crew member.",
	&"not_at_hub": "Go to the hub to change crew member.",
	&"not_available_yet": "This station is not working yet.",
	&"paused": "The game is paused.",
	&"pending": "Asked the host. Waiting for the answer.",
	&"offline": "Not connected to the host.",
}

var request_id := ""
var ok := false
var reason: StringName = &"ok"
var message := ""
## What changed, in plain data, for presentation and logs.
var changes := {}
## True if this is the stored answer to a request id the host had already handled. Nothing was done twice.
var duplicate := false
## True on a client while the request is on its way to the host. The real answer arrives later as
## GameEvents.action_resolved with the same request_id; act on the replicated state, not on this placeholder.
var pending := false


## Placeholder answer a client gets at once for a request it has sent to the host.
static func pending_answer(p_request_id: String) -> ActionResult:
	var r := ActionResult.new()
	r.request_id = p_request_id
	r.ok = false
	r.pending = true
	r.reason = &"pending"
	r.message = String(MESSAGES[&"pending"])
	return r


static func success(p_request_id: String, p_changes := {}, p_message := "") -> ActionResult:
	var r := ActionResult.new()
	r.request_id = p_request_id
	r.ok = true
	r.changes = p_changes
	r.message = p_message
	return r


static func failure(p_request_id: String, p_reason: StringName, p_message := "") -> ActionResult:
	var r := ActionResult.new()
	r.request_id = p_request_id
	r.ok = false
	r.reason = p_reason
	r.message = p_message if not p_message.is_empty() else String(MESSAGES.get(p_reason, "That did not work."))
	return r


func as_duplicate() -> ActionResult:
	var r := ActionResult.new()
	r.request_id = request_id
	r.ok = ok
	r.reason = reason
	r.message = message
	r.changes = changes.duplicate(true)
	r.duplicate = true
	return r


func to_dict() -> Dictionary:
	return {"request_id": request_id, "ok": ok, "reason": String(reason), "message": message, "changes": changes.duplicate(true), "duplicate": duplicate, "pending": pending}


static func from_dict(d: Dictionary) -> ActionResult:
	var r := ActionResult.new()
	r.request_id = String(d.get("request_id", ""))
	r.ok = bool(d.get("ok", false))
	r.reason = StringName(String(d.get("reason", "ok")))
	r.message = String(d.get("message", ""))
	r.changes = (d.get("changes", {}) as Dictionary).duplicate(true)
	r.duplicate = bool(d.get("duplicate", false))
	r.pending = bool(d.get("pending", false))
	return r
