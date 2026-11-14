class_name NetSession
extends Node
## LAN session layer (Prompt 06). The host is network peer 1: it owns the colony, ticks the simulation, validates every
## request and writes the save. Up to three clients join over ENet and show a replica of the host's colony.
##
## Channels (EN-06):
##   0  reliable, ordered: requests, answers, colony snapshots and forwarded GameEvents. One channel, so a client always
##      has the new state before the event that tells the UI to read it.
##   1  unreliable, ordered: body positions, about 20 per second each way, and "motion extras" (the rover's pose).
##   2  voice (Prompt 11): encoded audio packets, reliable ordered (see send_voice). The host relays a client's
##      packets to the other clients; every machine decides itself how to play them (VoiceRouter).
##
## What travels:
##   client -> host   _rpc_request(request dict)  _rpc_position(character, position, yaw)
##   host -> client   _rpc_welcome(full)  _rpc_update(full, events)  _rpc_result(result dict)  _rpc_positions(poses)
## A "full" record is the colony (ColonyState.to_dict plus display flows), the clock and the session replica
## (peers, pause votes, suit checks). It is a few kilobytes; sent 5 times a second and at once after any action.

const DEFAULT_PORT := 24680
const MAX_PLAYERS := 4
## Bumped when the messages change shape. A client of another version is turned away with a plain reason.
const PROTOCOL := 2
const CHANNEL_STATE := 0
const CHANNEL_MOTION := 1
const CHANNEL_VOICE := 2
## Channels opened on the ENet connection (state, motion, voice).
const CHANNEL_COUNT := 3
## Largest voice packet accepted, in bytes (an Opus frame of 20 ms is far smaller).
const VOICE_PACKET_MAX := 4000
## Colony snapshots per second while nothing else happens (the simulation itself ticks at 5 Hz).
const STATE_HZ := 5.0
## Body positions per second, each way.
const MOTION_HZ := 20.0
## A join that has not received the colony after this long gives up.
const JOIN_TIMEOUT_S := 10.0

## Hosting started on `port`.
signal hosted(port: int)
## This client is connected and has received the colony.
signal joined(peer_id: int)
## Joining failed; `reason` is plain language for the menu.
signal join_failed(reason: String)
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
## The host went away; `reason` is plain language for the menu.
signal host_lost(reason: String)
## Prompt 11: a voice packet from another machine's player (`from_peer`), on every machine that receives it.
signal voice_packet_received(from_peer: int, packet: PackedByteArray)
## Prompt 10: host only. A client sent a motion extra (for example the rover pose from its driver). The receiver
## must check that `sender` may set it (the rover code checks the sender is the driver).
signal motion_extra_received(sender: int, key: String, value: Variant)
## Prompt 10: client only. The host's motion extras, about 20 times a second.
signal motion_extras_received(extras: Dictionary)

## GameEvents signals the host forwards to clients. action_resolved goes only to the peer that asked (as _rpc_result);
## game_saved and game_loaded describe the host's own files and stay there.
const FORWARDED := [&"state_changed", &"objective_changed", &"weather_changed", &"upgrade_eligibility_changed",
	&"crew_ownership_changed", &"zone_power_changed", &"sol_settings_changed", &"pause_changed", &"sol_started",
	&"system_alert", &"character_recovered", &"suit_check_started", &"suit_check_finished"]

var services: GameServices
## Address and port this client joined, for status_text().
var address := ""
var port := DEFAULT_PORT

var _peer: ENetMultiplayerPeer
var _role: StringName = &"offline"     # offline, host, joining, client
var _queue: Array = []                 # host: [signal name, args] waiting for the next update
var _dirty := false                    # host: send an update this frame
var _state_left := 0.0
var _motion_left := 0.0
var _send_left := 0.0                  # client: time until the next position may go out
var _same_pose_left := 0.0             # client: an unchanged pose is sent again when this runs out
## Client: an unchanged body pose is repeated this often (seconds), so one lost unreliable packet cannot leave the
## host and the other players with an old position of a player who stands still.
const SAME_POSE_REPEAT_S := 0.5
var _join_left := 0.0
var _counter := 0
var _forwarders := {}                  # signal name -> Callable, so leave() can disconnect them
var _last_sent_pose := {}              # client: character id -> [position, yaw] last sent
## Host: returns {key: value} sent to every client with the body positions (for example {"rover": pose}).
var motion_extras_provider: Callable = Callable()


func setup(p_services: GameServices) -> void:
	services = p_services


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	leave()


# ---------------------------------------------------------------- public interface

## Starts hosting the colony already loaded in `services`. Returns OK or an engine error.
func host(p_port := DEFAULT_PORT) -> Error:
	leave()
	if services == null:
		return ERR_UNCONFIGURED
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(p_port, MAX_PLAYERS - 1, CHANNEL_COUNT)
	if err != OK:
		return err
	_peer = peer
	port = p_port
	_role = &"host"
	services.mode = &"host"
	multiplayer.multiplayer_peer = peer
	_connect_api()
	_connect_forwarders()
	_state_left = 0.0
	_motion_left = 0.0
	hosted.emit(p_port)
	return OK


## Connects to a host. The result arrives as `joined` or `join_failed`.
func join(p_address: String, p_port := DEFAULT_PORT) -> Error:
	leave()
	if services == null:
		return ERR_UNCONFIGURED
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(p_address, p_port, CHANNEL_COUNT)
	if err != OK:
		return err
	_peer = peer
	address = p_address
	port = p_port
	_role = &"joining"
	# A client never ticks or saves: set before anything else so GameServices._process stays quiet.
	services.mode = &"client"
	multiplayer.multiplayer_peer = peer
	_connect_api()
	_join_left = JOIN_TIMEOUT_S
	return OK


## Leaves the session (a host closes it for everyone).
func leave() -> void:
	# A host may stop LAN and keep playing this colony offline. Release remote operators while
	# the session is still authoritative; closing ENet after detaching callbacks cannot do this for us.
	if _role == &"host" and services != null and services.has_game():
		for peer: int in services.session.peers.duplicate():
			if peer != SessionService.HOST_PEER:
				services.session.peer_left(peer)
	_disconnect_forwarders()
	_disconnect_api()
	if _peer != null:
		_peer.close()
		_peer = null
	if is_inside_tree() and multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer = null
	_role = &"offline"
	_queue.clear()
	_dirty = false
	_last_sent_pose.clear()
	if services != null:
		services.mode = &"offline"


func is_online() -> bool:
	return _role == &"host" or _role == &"client"


func is_host() -> bool:
	return _role == &"host"


func is_client() -> bool:
	return _role == &"client"


## True between join() and the first colony snapshot.
func is_joining() -> bool:
	return _role == &"joining"


## This machine's peer id (1 when hosting or offline).
func local_peer() -> int:
	if (_role == &"client" or _role == &"joining") and _peer != null:
		return multiplayer.get_unique_id()
	return 1


## Connected peer ids, host first (just [1] when offline).
func peers() -> PackedInt32Array:
	if services != null and services.has_game() and is_online():
		return PackedInt32Array(services.session.peers)
	return PackedInt32Array([1])


## Client only: sends a request to the host and returns ActionResult.pending_answer().
func send_request(action: StringName, target: StringName, params: Dictionary) -> ActionResult:
	if _role != &"client":
		return ActionResult.failure("", &"offline")
	_counter += 1
	var id := "c%d-%d" % [local_peer(), _counter]
	var me := services.local_character()
	var req := ActionRequest.make(id, local_peer(), me.id if me != null else &"", action, target, params)
	if req.shape_problem() != "":
		return ActionResult.failure(id, &"bad_request")
	_rpc_request.rpc_id(1, req.to_dict())
	return ActionResult.pending_answer(id)


## Client only: sends this player's body position to the host (unreliable, about 20 per second).
func send_position(character_id: StringName, position: Vector3, yaw: float) -> void:
	if _role != &"client" or not services.has_game():
		return
	# The client is the authority for its own body: keep the replica's copy current for local checks and the HUD.
	var me := services.state().character(character_id)
	if me != null:
		me.position = position
		me.yaw = yaw
	if _send_left > 0.0:
		return
	var last: Array = _last_sent_pose.get(character_id, [])
	if not last.is_empty() and (last[0] as Vector3).distance_squared_to(position) < 1e-6 and absf(float(last[1]) - yaw) < 1e-3 and _same_pose_left > 0.0:
		return
	_send_left = 1.0 / MOTION_HZ
	_same_pose_left = SAME_POSE_REPEAT_S
	_last_sent_pose[character_id] = [position, yaw]
	_rpc_position.rpc_id(1, String(character_id), position, yaw)


## Sends this machine's voice packet to the other players. A client sends it to the host, which relays it; the host
## sends it to every client. Offline it does nothing.
## Every voice packet goes reliable and ordered on the voice channel (`reliable` is kept for callers). Measured in
## tests/test_voice.gd: sent unreliable, 14-17 of a client's 30 frames reached the host, because ENet's packet throttle
## (read at 1 of 32 on that link) drops unreliable packets while the 5 Hz reliable colony snapshots make round-trip
## times vary. On a LAN a resent packet costs about one round trip; the voice channel is separate, so voice never
## holds up the colony state or body poses. The listener's reorder window, FEC and timed buffer stay in place.
func send_voice(packet: PackedByteArray, reliable := false) -> void:
	if packet.is_empty() or packet.size() > VOICE_PACKET_MAX:
		return
	reliable = true
	match _role:
		&"client":
			if reliable:
				_rpc_voice_up_reliable.rpc_id(1, packet)
			else:
				_rpc_voice_up.rpc_id(1, packet)
		&"host":
			if multiplayer.get_peers().is_empty():
				return
			if reliable:
				_rpc_voice_down_reliable.rpc(1, packet)
			else:
				_rpc_voice_down.rpc(1, packet)


## Client only: sends a motion extra (for example the rover pose while this player drives) to the host.
func send_motion_extra(key: String, value: Variant) -> void:
	if _role != &"client" or key.length() > 32:
		return
	_rpc_motion_extra.rpc_id(1, key, value)


## One line for the HUD or menu: "Hosting on 192.168.1.20:24680, 2 players" and the like.
func status_text() -> String:
	match _role:
		&"host":
			var addrs := lan_addresses()
			var where := ", ".join(Array(addrs).map(func(a: String) -> String: return "%s:%d" % [a, port])) if not addrs.is_empty() else "port %d" % port
			return "Hosting on %s, %s" % [where, _players_text()]
		&"joining":
			return "Connecting to %s:%d…" % [address, port]
		&"client":
			return "Connected to %s:%d, %s" % [address, port, _players_text()]
	return "Playing alone"


## This machine's private IPv4 addresses (what other players type to join), most likely first.
static func lan_addresses() -> PackedStringArray:
	# Home routers almost always hand out 192.168.x.x; 172.16-31.x.x is often a virtual adapter (Hyper-V, WSL,
	# Docker), so it goes last among the private ranges.
	var ranked: Array = [[], [], [], []]
	for a: String in IP.get_local_addresses():
		if a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		var rank := 3
		if a.begins_with("192.168."):
			rank = 0
		elif a.begins_with("10."):
			rank = 1
		elif _is_172_private(a):
			rank = 2
		ranked[rank].append(a)
	var out := PackedStringArray()
	for group: Array in ranked:
		group.sort()
		out.append_array(PackedStringArray(group))
	return out


static func _is_172_private(a: String) -> bool:
	if not a.begins_with("172."):
		return false
	var second := int(a.split(".")[1])
	return second >= 16 and second <= 31


func _players_text() -> String:
	var n := services.session.peers.size() if services != null and services.has_game() else 1
	return "1 player" if n == 1 else "%d players" % n


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	match _role:
		&"host":
			if not services.has_game():
				return
			_state_left -= delta
			if _dirty or _state_left <= 0.0:
				_flush()
			_motion_left -= delta
			if _motion_left <= 0.0:
				_motion_left = 1.0 / MOTION_HZ
				_broadcast_positions()
		&"client":
			_send_left -= delta
			_same_pose_left -= delta
		&"joining":
			_join_left -= delta
			if _join_left <= 0.0:
				_fail_join("The host did not answer. Check the address and port, that the host is still hosting, and that you are on the same network.")


## Host: sends the colony and every event queued since the last update to all clients.
func _flush() -> void:
	_state_left = 1.0 / STATE_HZ
	_dirty = false
	var events := _queue
	_queue = []
	if multiplayer.get_peers().is_empty():
		return
	_rpc_update.rpc(_full_record(), events)


func _full_record() -> Dictionary:
	var session := services.session
	var colony := session.state.to_dict()
	colony["flows"] = session.state.flows_dict()
	return {"colony": colony, "clock": session.clock.to_dict(), "session": session.replica_dict()}


func _broadcast_positions() -> void:
	if multiplayer.get_peers().is_empty():
		return
	if motion_extras_provider.is_valid():
		var extras: Dictionary = motion_extras_provider.call()
		if not extras.is_empty():
			_rpc_extras.rpc(extras)
	var poses := {}
	for c: CharacterState in services.state().active_characters():
		poses[String(c.id)] = [c.position, c.yaw]
	_rpc_positions.rpc(poses)


# ---------------------------------------------------------------- host side

func _on_peer_connected(id: int) -> void:
	if _role != &"host":
		return
	var session := services.session
	if session.peers.size() >= MAX_PLAYERS:
		_rpc_refused.rpc_id(id, "This colony already has %d players." % MAX_PLAYERS)
		_peer.disconnect_peer(id, false)
		return
	session.peer_joined(id)
	# Everyone starts as a crew member nobody is playing; the Crew screen can switch at the hub later.
	for crew_id: StringName in _sorted_ids(session.state.characters):
		if session.state.characters[crew_id].owner_peer == 0:
			session.request(&"claim_character", crew_id, {}, id)
			break
	_rpc_welcome.rpc_id(id, PROTOCOL, _full_record())
	_dirty = true
	peer_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if _role != &"host":
		return
	if services.has_game() and services.session.peers.has(id):
		services.session.peer_left(id)
		_dirty = true
	peer_disconnected.emit(id)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_request(d: Dictionary) -> void:
	if _role != &"host" or not services.has_game():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not services.session.peers.has(sender):
		return
	var req := ActionRequest.from_dict(d, sender)
	var result := services.session.submit(req)
	result.peer = sender
	# The answer must not overtake the state it describes: send the update first, on the same reliable channel.
	_flush()
	_rpc_result.rpc_id(sender, result.to_dict())


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_position(character_id: String, position: Vector3, yaw: float) -> void:
	if _role != &"host" or not services.has_game():
		return
	if not position.is_finite() or not is_finite(yaw):
		return
	# SessionService checks that the sender owns this character.
	services.session.report_position(multiplayer.get_remote_sender_id(), StringName(character_id), position, yaw)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_motion_extra(key: String, value: Variant) -> void:
	if _role != &"host" or not services.has_game():
		return
	var sender := multiplayer.get_remote_sender_id()
	if services.session.peers.has(sender):
		motion_extra_received.emit(sender, key, value)


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _rpc_voice_up(packet: PackedByteArray) -> void:
	_voice_from_client(packet, false)


@rpc("any_peer", "call_remote", "reliable", 2)
func _rpc_voice_up_reliable(packet: PackedByteArray) -> void:
	_voice_from_client(packet, true)


## Host: plays a client's packet here and relays it to the other clients, unchanged and in arrival order.
func _voice_from_client(packet: PackedByteArray, reliable: bool) -> void:
	if _role != &"host" or packet.is_empty() or packet.size() > VOICE_PACKET_MAX:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not services.has_game() or not services.session.peers.has(sender):
		return
	voice_packet_received.emit(sender, packet)
	for p: int in multiplayer.get_peers():
		if p == sender:
			continue
		if reliable:
			_rpc_voice_down_reliable.rpc_id(p, sender, packet)
		else:
			_rpc_voice_down.rpc_id(p, sender, packet)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _rpc_voice_down(from_peer: int, packet: PackedByteArray) -> void:
	if _role == &"client" and packet.size() <= VOICE_PACKET_MAX and from_peer != local_peer():
		voice_packet_received.emit(from_peer, packet)


@rpc("authority", "call_remote", "reliable", 2)
func _rpc_voice_down_reliable(from_peer: int, packet: PackedByteArray) -> void:
	if _role == &"client" and packet.size() <= VOICE_PACKET_MAX and from_peer != local_peer():
		voice_packet_received.emit(from_peer, packet)


func _connect_forwarders() -> void:
	var arity := {}
	for s: Dictionary in services.events.get_signal_list():
		arity[StringName(s.name)] = (s.args as Array).size()
	for sig: StringName in FORWARDED:
		var name := sig
		var cb: Callable
		match int(arity.get(sig, 0)):
			0: cb = func() -> void: _on_event(name, [])
			1: cb = func(a: Variant) -> void: _on_event(name, [a])
			2: cb = func(a: Variant, b: Variant) -> void: _on_event(name, [a, b])
			_: cb = func(a: Variant, b: Variant, c: Variant) -> void: _on_event(name, [a, b, c])
		_forwarders[sig] = cb
		services.events.connect(sig, cb)


func _disconnect_forwarders() -> void:
	if services == null or services.events == null:
		_forwarders.clear()
		return
	for sig: StringName in _forwarders:
		var cb: Callable = _forwarders[sig]
		if services.events.is_connected(sig, cb):
			services.events.disconnect(sig, cb)
	_forwarders.clear()


func _on_event(sig: StringName, args: Array) -> void:
	if _role != &"host":
		return
	if sig == &"state_changed" and args[0] == &"tick":
		return                     # ticks travel as the regular snapshot; the client emits its own "tick"
	_queue.append([String(sig), args])
	_dirty = true


# ---------------------------------------------------------------- client side

@rpc("authority", "call_remote", "reliable", 0)
func _rpc_welcome(protocol: int, full: Dictionary) -> void:
	if _role != &"joining":
		return
	if protocol != PROTOCOL:
		_fail_join("The host is running a different version of the game. Both players need the same version.")
		return
	var st := ColonyState.from_dict(full.get("colony", {}))
	st.assign_from(full.get("colony", {}))          # also copies the display flows
	var c := SolClock.from_dict(full.get("clock", {}))
	services.session.begin(st, c)
	services.session.apply_replica(full.get("session", {}))
	_role = &"client"
	joined.emit(local_peer())


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_update(full: Dictionary, events: Array) -> void:
	if _role != &"client" or not services.has_game():
		return
	var me := services.local_character()
	var keep := me.id if me != null else &""
	# Events that move this client's own body on the host: take the host's pose once instead of keeping ours.
	for e: Array in events:
		if String(e[0]) == "character_recovered" and StringName(e[1][0]) == keep:
			keep = &""
	services.state().assign_from(full.get("colony", {}), keep)
	var clock_d: Dictionary = full.get("clock", {})
	var fresh := SolClock.from_dict(clock_d)
	var clock := services.clock()
	clock.sol_minutes = fresh.sol_minutes
	clock.sol_index = fresh.sol_index
	clock.phase = fresh.phase
	clock.ticks = fresh.ticks
	clock.real_seconds = fresh.real_seconds
	services.session.apply_replica(full.get("session", {}))
	for e: Array in events:
		var sig := StringName(String(e[0]))
		if FORWARDED.has(sig):
			services.events.callv(&"emit_signal", [sig] + (e[1] as Array))
	services.events.state_changed.emit(&"tick")


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_result(d: Dictionary) -> void:
	if _role != &"client":
		return
	services.events.action_resolved.emit(ActionResult.from_dict(d))


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_positions(poses: Dictionary) -> void:
	if _role != &"client" or not services.has_game():
		return
	var me := services.local_character()
	for id: String in poses:
		if me != null and StringName(id) == me.id:
			continue
		var c := services.state().character(StringName(id))
		var pose: Array = poses[id]
		if c != null and pose.size() == 2 and pose[0] is Vector3:
			c.position = pose[0]
			c.yaw = float(pose[1])


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_extras(extras: Dictionary) -> void:
	if _role == &"client" and services.has_game():
		motion_extras_received.emit(extras)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_refused(reason: String) -> void:
	if _role == &"joining":
		_fail_join(reason)


func _on_connection_failed() -> void:
	if _role == &"joining":
		_fail_join("Could not reach the host. Check the address and port, and that you are on the same network.")


func _on_server_disconnected() -> void:
	if _role == &"joining":
		_fail_join("The host closed the connection.")
	elif _role == &"client":
		leave()
		host_lost.emit("The connection to the host was lost, or the host closed the colony.")


func _fail_join(reason: String) -> void:
	leave()
	join_failed.emit(reason)


# ---------------------------------------------------------------- plumbing

func _connect_api() -> void:
	var api := multiplayer
	if not api.peer_connected.is_connected(_on_peer_connected):
		api.peer_connected.connect(_on_peer_connected)
		api.peer_disconnected.connect(_on_peer_disconnected)
		api.connection_failed.connect(_on_connection_failed)
		api.server_disconnected.connect(_on_server_disconnected)


func _disconnect_api() -> void:
	if not is_inside_tree():
		return
	var api := multiplayer
	if api.peer_connected.is_connected(_on_peer_connected):
		api.peer_connected.disconnect(_on_peer_connected)
		api.peer_disconnected.disconnect(_on_peer_disconnected)
		api.connection_failed.disconnect(_on_connection_failed)
		api.server_disconnected.disconnect(_on_server_disconnected)


static func _sorted_ids(d: Dictionary) -> Array:
	var ids := d.keys()
	ids.sort()
	return ids
