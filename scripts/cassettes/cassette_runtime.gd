class_name CassetteRuntime
extends RefCounted
## Nonexclusive playback authorizations, replicated for local interruption checks and never saved.

var readers: Dictionary = {}
var _session_ref: WeakRef

func _init(session: SessionService) -> void:
	_session_ref = weakref(session)

func clear_session() -> void:
	readers.clear()

func release_character(character_id: StringName) -> void:
	for peer: String in readers.keys():
		if String(readers[peer].actor_id) == String(character_id):
			readers.erase(peer)

func _player_valid(session: SessionService, actor: CharacterState, station_id: String) -> bool:
	if station_id != CassetteCatalog.PLAYER_ID or session.state == null or actor == null or actor.health <= 0.0 or actor.owner_peer <= 0:
		return false
	var station: Dictionary = session.state.stations.get(station_id, {})
	if String(station.get("kind", "")) != "cassette_player_anchor" or String(station.get("room_id", "")) != "command_center" or String(station.get("zone", "")) != "Command Room":
		return false
	if not station.has("position") or actor.position.distance_to(CharacterState._v3(station.position)) > session.config.interact_distance_m:
		return false
	return session.zone_at_position.is_valid() and String(session.zone_at_position.call(actor.position)) == "Command Room"

func is_authorized(peer: int, station_id: StringName = &"cassette_player_command_center") -> bool:
	var session := _session_ref.get_ref() as SessionService
	var reader: Dictionary = readers.get(str(peer), {})
	if session == null or session.state == null or reader.is_empty() or String(reader.get("station_id", "")) != String(station_id):
		return false
	var actor := session.state.character_of_peer(peer)
	return actor != null and String(actor.id) == String(reader.get("actor_id", "")) and _player_valid(session, actor, String(station_id))

func prune(session: SessionService) -> void:
	var changed := false
	for peer: String in readers.keys():
		if not is_authorized(int(peer)):
			readers.erase(peer)
			changed = true
	if changed:
		session.events.state_changed.emit(&"cassette_reader")

func check(ctx: ActionService.Context) -> ActionResult:
	if ctx.request.action == &"cassette_close":
		return null if String(ctx.request.target) == CassetteCatalog.PLAYER_ID else ActionResult.failure(ctx.request.request_id, &"wrong_target")
	if ctx.actor.health <= 0.0:
		return ActionResult.failure(ctx.request.request_id, &"no_actor", "This crew member cannot use a cassette now.")
	if ctx.request.action == &"cassette_collect":
		var id := String(ctx.request.target)
		if not CassetteCatalog.TAPES.has(id):
			return ActionResult.failure(ctx.request.request_id, &"wrong_target")
		var room_id := String(CassetteCatalog.TAPES[id].room_id)
		var zones: Array = RepairCatalog.ROOMS[room_id].zones
		if String(ctx.target.get("cassette_id", "")) != id or String(ctx.target.get("room_id", "")) != room_id or not zones.has(String(ctx.target.get("zone", ""))):
			return ActionResult.failure(ctx.request.request_id, &"wrong_target")
		if not ctx.session.zone_at_position.is_valid() or not zones.has(String(ctx.session.zone_at_position.call(ctx.actor.position))):
			return ActionResult.failure(ctx.request.request_id, &"wrong_room", "Stand beside the cassette in its room.")
		if CassetteCatalog.collected(ctx.state, id):
			return ActionResult.failure(ctx.request.request_id, &"already_collected", "Your colony already collected this cassette. " + CassetteCatalog.PLAY_INSTRUCTION)
		return null
	if not _player_valid(ctx.session, ctx.actor, String(ctx.request.target)):
		return ActionResult.failure(ctx.request.request_id, &"play_at_command", CassetteCatalog.PLAY_INSTRUCTION)
	if ctx.request.action == &"cassette_open":
		return null
	if not is_authorized(ctx.request.peer_id):
		return ActionResult.failure(ctx.request.request_id, &"play_at_command", "Use the Command Room cassette player first.")
	var cassette_id := String(ctx.request.params.cassette_id)
	if not CassetteCatalog.collected(ctx.state, cassette_id):
		return ActionResult.failure(ctx.request.request_id, &"cassette_missing", "Collect this room's cassette first.")
	var count := CassetteCatalog.page_count(cassette_id)
	if count <= 0:
		return ActionResult.failure(ctx.request.request_id, &"not_available_yet", "This cassette's local briefing or photograph is unavailable.")
	if ctx.request.action == &"cassette_read":
		var reader: Dictionary = readers.get(str(ctx.request.peer_id), {})
		if String(reader.get("cassette_id", "")) != cassette_id:
			return ActionResult.failure(ctx.request.request_id, &"wrong_target", "Select that cassette at the player first.")
		if int(ctx.request.params.page) >= count:
			return ActionResult.failure(ctx.request.request_id, &"bad_request", "That briefing page does not exist.")
	return null

func apply(ctx: ActionService.Context) -> Dictionary:
	var peer := str(ctx.request.peer_id)
	if ctx.request.action == &"cassette_collect":
		var id := String(ctx.request.target)
		(ctx.state.repair.collected_cassettes as Array).append(id)
		return {"cassette_id": id, "room_id": String(CassetteCatalog.TAPES[id].room_id), "title": String(CassetteCatalog.TAPES[id].title), "collected": true}
	if ctx.request.action == &"cassette_close":
		readers.erase(peer)
		return {"authorized": false, "station_id": CassetteCatalog.PLAYER_ID, "released": true}
	if ctx.request.action == &"cassette_open":
		readers[peer] = {"station_id": CassetteCatalog.PLAYER_ID, "actor_id": String(ctx.actor.id), "cassette_id": "", "page": 0}
	else:
		readers[peer].cassette_id = String(ctx.request.params.cassette_id)
		readers[peer].page = int(ctx.request.params.get("page", 0))
	var result: Dictionary = readers[peer].duplicate(true)
	result.authorized = true
	return result

func replica_dict() -> Dictionary:
	return {"readers": readers.duplicate(true)}

func apply_replica(data: Dictionary) -> void:
	readers = (data.get("readers", {}) as Dictionary).duplicate(true)
