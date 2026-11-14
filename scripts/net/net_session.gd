class_name NetSession
extends Node
## LAN session layer (Prompt 06). STUB: the interface is fixed; worker E replaces the bodies.
## The host is network peer 1 and owns the colony and the save; up to three clients join over ENet.

const DEFAULT_PORT := 24680
const MAX_PLAYERS := 4

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

var services: GameServices


func setup(p_services: GameServices) -> void:
	services = p_services


## Starts hosting the colony already loaded in `services`. Returns OK or an engine error.
func host(_port := DEFAULT_PORT) -> Error:
	return ERR_UNAVAILABLE


## Connects to a host. The result arrives as `joined` or `join_failed`.
func join(_address: String, _port := DEFAULT_PORT) -> Error:
	return ERR_UNAVAILABLE


## Leaves the session (a host closes it for everyone).
func leave() -> void:
	pass


func is_online() -> bool:
	return false


func is_host() -> bool:
	return false


func is_client() -> bool:
	return false


## This machine's peer id (1 when hosting or offline).
func local_peer() -> int:
	return 1


## Connected peer ids, host first (just [1] when offline).
func peers() -> PackedInt32Array:
	return PackedInt32Array([1])


## Client only: sends a request to the host and returns ActionResult.pending_answer().
func send_request(_action: StringName, _target: StringName, _params: Dictionary) -> ActionResult:
	return ActionResult.failure("", &"offline")


## Client only: sends this player's body position to the host (unreliable, about 20 per second).
func send_position(_character_id: StringName, _position: Vector3, _yaw: float) -> void:
	pass


## One line for the HUD or menu: "Hosting on 192.168.1.20:24680, 2 players" and the like.
func status_text() -> String:
	return "Playing alone"
