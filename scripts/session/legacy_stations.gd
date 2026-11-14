class_name LegacyStations
extends RefCounted
## Routes old station interactions to explicit actions.

## Supported legacy station kinds.
const KIND_ACTION: Dictionary = {"power": &"set_zone_power", "suits": &"begin_suit_check"}

## Uses a supported station or returns its availability failure.
static func interact(session: SessionService, peer: int, station_id: StringName, params: Dictionary = {}) -> ActionResult:
	if session.state == null or not session.state.stations.has(station_id):
		return ActionResult.failure("", &"unknown_target")
	var kind: String = session.state.stations[station_id].kind
	if not KIND_ACTION.has(kind):
		return ActionResult.failure("", &"not_available_yet")
	return session.request(KIND_ACTION[kind], station_id, params, peer)

## Returns stable ids matching a station kind.
static func stations_of_kind(state: ColonyState, kind: String) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: String in state.stations:
		if String(state.stations[id].kind) == kind:
			ids.append(StringName(id))
	return ids
