class_name LanDiscovery
extends RefCounted
## Finds games on the local network without typing addresses. A host sends a small "beacon" once a second as a UDP
## broadcast on DISCOVERY_PORT; the Join screen listens on that port and lists every host it hears as a button.
##
## Beacon (JSON text): {"game": MAGIC, "v": NetSession.PROTOCOL, "id": random, "name": "Sam", "port": 24680,
## "players": 2, "max": 4}. The address to join is the address the beacon came from.

const DISCOVERY_PORT := 24681
const MAGIC := "MissionPossible-LAN"
## A beacon goes out this often (seconds).
const BEACON_INTERVAL_S := 1.0
## A host not heard for this long is taken off the list (seconds).
const FORGET_AFTER_S := 4.0


## The name other players see: this computer's name, or the person signed in if it has none.
static func local_name() -> String:
	for key: String in ["COMPUTERNAME", "HOSTNAME", "USERNAME", "USER"]:
		var v := OS.get_environment(key).strip_edges()
		if v != "":
			return v.left(24)
	return "A player"


## Broadcast addresses to send to: the general one plus each private /24 network of this machine (Windows sends the
## general broadcast out of one adapter only, so a computer with several adapters needs the per-network ones).
static func broadcast_addresses() -> PackedStringArray:
	var out := PackedStringArray(["255.255.255.255"])
	for a: String in NetSession.lan_addresses():
		var parts := a.split(".")
		if parts.size() == 4:
			var b := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
			if not out.has(b):
				out.append(b)
	return out


## Host side: sends the beacon while hosting. Call poll() every frame.
class Beacon:
	extends RefCounted
	var game_port := NetSession.DEFAULT_PORT
	var host_name := ""
	var _udp: PacketPeerUDP
	var _left := 0.0
	var _id := ""
	var _targets := PackedStringArray()

	func start(p_game_port: int) -> void:
		stop()
		game_port = p_game_port
		host_name = LanDiscovery.local_name()
		_id = "%x" % (randi() ^ Time.get_ticks_usec())
		_targets = LanDiscovery.broadcast_addresses()
		_udp = PacketPeerUDP.new()
		_udp.set_broadcast_enabled(true)
		if _udp.bind(0) != OK:
			_udp = null
			return
		_left = 0.0

	func stop() -> void:
		if _udp != null:
			_udp.close()
			_udp = null

	func is_running() -> bool:
		return _udp != null

	func poll(delta: float, players: int, max_players: int) -> void:
		if _udp == null:
			return
		_left -= delta
		if _left > 0.0:
			return
		_left = BEACON_INTERVAL_S
		var msg := JSON.stringify({"game": MAGIC, "v": NetSession.PROTOCOL, "id": _id, "name": host_name,
			"port": game_port, "players": players, "max": max_players}).to_utf8_buffer()
		for target: String in _targets:
			_udp.set_dest_address(target, DISCOVERY_PORT)
			_udp.put_packet(msg)


## Join side: listens for beacons. Call poll() every frame; it returns true when the list changed.
class Browser:
	extends RefCounted
	var _udp: PacketPeerUDP
	var _found := {}          # id -> {name, address, port, players, max, same_version, seen}

	## Returns false when the discovery port could not be opened (another copy of the game is already listening).
	func start() -> bool:
		if _udp != null:
			return true
		_found.clear()
		_udp = PacketPeerUDP.new()
		_udp.set_broadcast_enabled(true)
		if _udp.bind(LanDiscovery.DISCOVERY_PORT, "*") != OK:
			_udp = null
			return false
		return true

	func stop() -> void:
		if _udp != null:
			_udp.close()
			_udp = null
		_found.clear()

	func is_running() -> bool:
		return _udp != null

	func poll() -> bool:
		if _udp == null:
			return false
		var changed := false
		var now := Time.get_ticks_msec() / 1000.0
		while _udp.get_available_packet_count() > 0:
			var bytes := _udp.get_packet()
			var from := _udp.get_packet_ip()
			if bytes.size() > 1024 or from == "":
				continue
			var d: Variant = JSON.parse_string(bytes.get_string_from_utf8())
			if not d is Dictionary or (d as Dictionary).get("game", "") != LanDiscovery.MAGIC:
				continue
			var id := str(d.get("id", from))
			var port := int(d.get("port", 0))
			if port < 1 or port > 65535:
				continue
			var entry := {
				"name": str(d.get("name", "A player")).left(24),
				"address": from,
				"port": port,
				"players": int(d.get("players", 1)),
				"max": int(d.get("max", NetSession.MAX_PLAYERS)),
				"same_version": int(d.get("v", -1)) == NetSession.PROTOCOL,
				"seen": now,
			}
			var old: Dictionary = _found.get(id, {})
			# A host with several network adapters is heard more than once: keep the first address it was heard on.
			if not old.is_empty():
				entry.address = old.address
			if old.is_empty() or old.name != entry.name or old.players != entry.players or old.port != entry.port:
				changed = true
			_found[id] = entry
		for id: String in _found.keys():
			if now - float(_found[id].seen) > LanDiscovery.FORGET_AFTER_S:
				_found.erase(id)
				changed = true
		return changed

	## Hosts heard recently, sorted by name.
	func servers() -> Array:
		var list := _found.values()
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name).naturalnocasecmp_to(b.name) < 0)
		return list
