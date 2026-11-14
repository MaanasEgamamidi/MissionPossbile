class_name ActionRequest
extends RefCounted
## Something a player wants to do. A client only ever sends one of these; the host decides.
## `peer_id` is filled in by the host from the network sender and is never read from the message itself.

const MAX_ID_LENGTH := 64
const MAX_PARAMS := 8
const MAX_STRING_LENGTH := 64

var request_id := ""
var peer_id := 0
## Character doing the action ("crew_2"). Empty for session requests such as a pause vote.
var actor: StringName = &""
var action: StringName = &""
## Stable id of the station, item, cache or character acted on. Empty if the action has no target.
var target: StringName = &""
var params := {}


static func make(p_request_id: String, p_peer: int, p_actor: StringName, p_action: StringName, p_target: StringName = &"", p_params := {}) -> ActionRequest:
	var r := ActionRequest.new()
	r.request_id = p_request_id
	r.peer_id = p_peer
	r.actor = p_actor
	r.action = p_action
	r.target = p_target
	r.params = p_params
	return r


## Returns "" if the request is well formed, else what is wrong with it. Checks size limits only, not meaning.
func shape_problem() -> String:
	if request_id.is_empty() or request_id.length() > MAX_ID_LENGTH:
		return "request id missing or too long"
	if String(action).is_empty() or String(action).length() > MAX_STRING_LENGTH:
		return "action missing or too long"
	if String(actor).length() > MAX_STRING_LENGTH or String(target).length() > MAX_STRING_LENGTH:
		return "actor or target too long"
	if params.size() > MAX_PARAMS:
		return "too many parameters"
	for k in params:
		if not (k is String or k is StringName) or String(k).length() > MAX_STRING_LENGTH:
			return "bad parameter name"
		var v: Variant = params[k]
		match typeof(v):
			TYPE_BOOL, TYPE_INT:
				pass
			TYPE_FLOAT:
				if is_nan(v) or is_inf(v):
					return "parameter %s is not a finite number" % k
			TYPE_STRING, TYPE_STRING_NAME:
				if String(v).length() > MAX_STRING_LENGTH:
					return "parameter %s too long" % k
			_:
				return "parameter %s has an unsupported type" % k
	return ""


func to_dict() -> Dictionary:
	return {"request_id": request_id, "actor": String(actor), "action": String(action), "target": String(target), "params": params.duplicate()}


## Builds a request from a network message. The sender id comes from the transport, not from `d`.
static func from_dict(d: Dictionary, sender_peer: int) -> ActionRequest:
	var p: Variant = d.get("params", {})
	return make(String(d.get("request_id", "")), sender_peer, StringName(String(d.get("actor", ""))), StringName(String(d.get("action", ""))),
		StringName(String(d.get("target", ""))), p if p is Dictionary else {})
