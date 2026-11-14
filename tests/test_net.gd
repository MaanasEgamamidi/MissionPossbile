extends SceneTree
## Prompt 06 checks: LAN co-op over real ENet on 127.0.0.1, host and clients in one process.
## Each machine is a branch of the tree with its own SceneMultiplayer (SceneTree.set_multiplayer), so the RPC path
## Services/Net is the same on both, exactly as between two computers.
## Run: godot --headless --path . --script res://tests/test_net.gd

const PORT := 24791

var _passed := 0
var _total := 0
var _client_events: Array = []
var _client_results: Array[ActionResult] = []
var _lost := ""
var _failed_join := ""


func _check(name: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS ", name, ("  " + detail) if detail != "" else "")
	else:
		print("FAIL ", name, ": ", detail)


## One "machine": a branch with its own multiplayer API and a GameServices node named Services.
func _machine(branch: String, save_dir: String) -> GameServices:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var g := GameServices.new()
	g.name = "Services"
	g.saves = SaveService.new(save_dir, "colony", 2)
	holder.add_child(g)
	return g


## Waits up to `seconds` (real frames) for `cond` to hold. Returns whether it did.
func _until(cond: Callable, seconds := 5.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return bool(cond.call())


func _initialize() -> void:
	_run.call_deferred()


## Synthetic host-only repair validator. No production room puzzle is installed by this test.
func _repair_rule(task: Dictionary, move: Dictionary) -> Dictionary:
	var expected := int((task.puzzle_state as Dictionary).get("step", 0)) + 1
	if String(move.move) != "step" or int(move.value) != expected or expected > 2:
		return {"accepted": false}
	return {"accepted": true, "puzzle_state": {"step": expected}, "progress": float(expected) / 2.0, "complete": expected == 2}


func _run() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/net")
	DirAccess.make_dir_recursive_absolute(dir)
	var host := _machine("HostMachine", dir)
	host.saves.delete_all()
	var client := _machine("ClientMachine", dir.path_join("client"))
	client.events.state_changed.connect(func(r: StringName) -> void: if r != &"tick": _client_events.append(r))
	client.events.crew_ownership_changed.connect(func(id: StringName, p: int) -> void: _client_events.append("own:%s:%d" % [id, p]))
	client.events.action_resolved.connect(func(r: ActionResult) -> void: _client_results.append(r))
	client.net.host_lost.connect(func(reason: String) -> void: _lost = reason)
	client.net.join_failed.connect(func(reason: String) -> void: _failed_join = reason)

	# ---- offline defaults
	_check("offline: status says alone", host.net.status_text() == "Playing alone" and not host.net.is_online())
	_check("offline: send_request is refused", host.net.send_request(&"vote_pause", &"", {}).reason == &"offline")

	# ---- host
	host.start_new_game(4242)
	_check("host: listening", host.net.host(PORT) == OK and host.net.is_host() and host.mode == &"host")
	_check("host: status names a port", host.net.status_text().contains(str(PORT)), host.net.status_text())
	var second := ENetMultiplayerPeer.new()
	_check("host: the port is really taken", second.create_server(PORT) != OK)
	second.close()
	# F04: join a real ENet colony while the host is midway through a resumable puzzle.
	var repair_actor := host.local_character()
	var comms_at := CharacterState._v3(host.state().stations["repair_t01"].position)
	host.session.report_position(1, repair_actor.id, comms_at, 0.0)
	host.session.repair_runtime.register_rule("T01", _repair_rule, true)
	var claimed := host.request(&"task_claim", &"repair_t01", {"generation": 1})
	var partial := host.request(&"task_move", &"repair_t01", {"generation": 1, "move": "step", "value": 1})
	_check("repair fixture: host validates partial puzzle", claimed.ok and partial.ok and host.state().repair.tasks.T01.progress == 0.5)
	var disk_snapshot := host.snapshot()
	_check("repair save: partial retained without operator lock", disk_snapshot.colony.repair.tasks.T01.progress == 0.5 and not disk_snapshot.colony.repair.has("locks") and not disk_snapshot.session.has("repair") and host.session.repair_runtime.locks.has("T01"))

	# ---- join
	_check("join: started", client.net.join("127.0.0.1", PORT) == OK and client.net.is_joining() and client.mode == &"client")
	_check("join: colony received", await _until(func() -> bool: return client.net.is_client() and client.has_game()), _failed_join)
	var cpeer := client.local_peer()
	_check("join: client has its own peer id", cpeer > 1, str(cpeer))
	_check("join: host counts two players", host.session.peers.size() == 2 and client.session.peers.size() == 2, str(host.session.peers))
	var mine := client.local_character()
	var hosts := host.local_character()
	_check("join: client got a free crew member", mine != null and hosts != null and mine.id != hosts.id and host.state().character(mine.id).owner_peer == cpeer)
	_check("join: same colony seed and stations", client.state().rng_seed == host.state().rng_seed and client.state().stations.size() == host.state().stations.size())
	_check("join: client never ticks or saves", client.save_now() == ERR_UNCONFIGURED and not client.is_authority())
	_check("repair late join: current puzzle and seed arrive", client.state().repair.tasks.T01.progress == 0.5 and client.state().repair.tasks.T01.puzzle_state == {"step": 1} and client.state().repair.tasks.T01.puzzle_seed == host.state().repair.tasks.T01.puzzle_seed)
	_check("repair late join: live operator lease arrives", client.session.repair_runtime.locks.has("T01") and int(client.session.repair_runtime.locks.T01.peer) == 1)
	# Both room milestones then travel as ordinary authoritative updates, including seen-shot history.
	host.request(&"task_move", &"repair_t01", {"generation": 1, "move": "step", "value": 2})
	host.session.report_position(1, hosts.id, CharacterState._v3(host.state().stations["repair_t02"].position), 0.0)
	host.session.repair_runtime.register_rule("T02", _repair_rule, true)
	host.request(&"task_claim", &"repair_t02", {"generation": 1})
	host.request(&"task_move", &"repair_t02", {"generation": 1, "move": "step", "value": 1})
	var completed := host.request(&"task_move", &"repair_t02", {"generation": 1, "move": "step", "value": 2})
	host.state().repair.seen_beauty_shots.append("command_center")
	host.events.state_changed.emit(&"repair_fixture")
	_check("repair updates: room milestone and shot history arrive", completed.ok and await _until(func() -> bool: return client.state().repair.rooms.command_center.first_completed and client.state().repair.seen_beauty_shots == ["command_center"] and not client.session.repair_runtime.locks.has("T01") and not client.session.repair_runtime.locks.has("T02")))

	# ---- client body -> host
	var spot := host.state().items["crate_1"].position as Array
	var crate_at := Vector3(float(spot[0]), float(spot[1]), float(spot[2]))
	client.report_position(mine.id, crate_at + Vector3(0.5, 0, 0), 1.0)
	_check("motion: host sees the client's body", await _until(func() -> bool: return host.state().character(mine.id).position.distance_to(crate_at + Vector3(0.5, 0, 0)) < 0.01))
	_check("motion: client keeps its own pose through updates", await _until(func() -> bool: return false, 0.5) or client.state().character(mine.id).position.distance_to(crate_at + Vector3(0.5, 0, 0)) < 0.01)
	host.session.report_position(1, hosts.id, Vector3(3, 0, 4), 0.5)
	_check("motion: client sees the host's body", await _until(func() -> bool: return client.state().character(hosts.id).position.distance_to(Vector3(3, 0, 4)) < 0.01))
	# A client may not move someone else's character.
	client.net._rpc_position.rpc_id(1, String(hosts.id), Vector3(99, 0, 99), 0.0)
	await _until(func() -> bool: return false, 0.3)
	_check("motion: moving another player's crew is ignored", host.state().character(hosts.id).position.distance_to(Vector3(3, 0, 4)) < 0.01)

	# ---- client request -> host -> replicated answer
	var pending := client.request(&"pick_up", &"crate_1")
	_check("request: client gets a pending answer at once", pending.pending and pending.request_id.begins_with("c%d-" % cpeer), pending.request_id)
	_check("request: answer arrives", await _until(func() -> bool: return _client_results.any(func(r: ActionResult) -> bool: return r.request_id == pending.request_id)))
	var answer: ActionResult = _client_results.filter(func(r: ActionResult) -> bool: return r.request_id == pending.request_id)[0]
	_check("request: host said yes", answer.ok and answer.peer == cpeer, answer.message)
	_check("request: host state changed", String(host.state().items["crate_1"].holder) == String(mine.id))
	_check("request: client state changed before the answer", String(client.state().items["crate_1"].holder) == String(mine.id) and client.state().character(mine.id).cargo == [&"crate_1"])
	_check("request: client heard state_changed(pick_up)", _client_events.has(&"pick_up"), str(_client_events))
	var bad := client.request(&"set_sol_minutes", &"", {"minutes": 30})
	_check("request: host-only action refused for a client", await _until(func() -> bool: return _client_results.any(func(r: ActionResult) -> bool: return r.request_id == bad.request_id and r.reason == &"host_only")))

	# ---- pause needs everyone
	host.request(&"vote_pause", &"", {"paused": true})
	await _until(func() -> bool: return false, 0.4)
	_check("pause: one vote of two does not pause", not host.session.paused and client.session.pause_votes() == 1, str(client.session.pause_votes()))
	client.request(&"vote_pause", &"", {"paused": true})
	_check("pause: both votes pause, client sees it", await _until(func() -> bool: return host.session.paused and client.session.paused))
	client.request(&"vote_pause", &"", {"paused": false})
	host.request(&"vote_pause", &"", {"paused": false})
	_check("pause: unpaused again", await _until(func() -> bool: return not host.session.paused and not client.session.paused))

	# ---- the clock follows the host
	await _until(func() -> bool: return false, 1.0)
	_check("clock: client clock follows the host", absf(client.clock().phase - host.clock().phase) < 0.01 and client.clock().ticks > 0, "%f vs %f" % [client.clock().phase, host.clock().phase])

	# ---- client leaves: its crew member is parked, cargo stays with the character
	var rings_at := CharacterState._v3(host.state().stations["repair_t03"].position)
	await _until(func() -> bool:
		client.report_position(mine.id, rings_at, 0.0)
		return host.state().character(mine.id).position.distance_to(rings_at) < 0.01)
	var operator_claim := client.request(&"task_claim", &"repair_t03", {"generation": 1})
	var lease_arrived := await _until(func() -> bool: return host.session.repair_runtime.locks.has("T03") and client.session.repair_runtime.locks.has("T03"))
	var lease_answers := _client_results.filter(func(result: ActionResult) -> bool: return result.request_id == operator_claim.request_id)
	_check("repair client: host grants an operator lease", operator_claim.pending and lease_arrived, str(lease_answers.map(func(result: ActionResult) -> Dictionary: return result.to_dict())))
	client.net.leave()
	_check("leave: host parks the client's crew", await _until(func() -> bool: return host.session.peers.size() == 1 and host.state().character(mine.id).owner_peer == 0))
	_check("leave: client is offline", client.mode == &"offline" and not client.net.is_online())
	_check("repair disconnect: operator lease released", not host.session.repair_runtime.locks.has("T03"))

	# ---- rejoin, then the host quits
	_client_events.clear()
	_check("rejoin: works on the same port", client.net.join("127.0.0.1", PORT) == OK and await _until(func() -> bool: return client.net.is_client()))
	_check("rejoin: gets a crew member again", client.local_character() != null)
	_check("repair rejoin: milestone retained without stuck lease", client.state().repair.rooms.command_center.first_completed and client.state().repair.seen_beauty_shots == ["command_center"] and not client.session.repair_runtime.locks.has("T03"))
	var rejoined_actor := client.local_character()
	await _until(func() -> bool:
		client.report_position(rejoined_actor.id, rings_at, 0.0)
		return host.state().character(rejoined_actor.id).position.distance_to(rings_at) < 0.01)
	client.request(&"task_claim", &"repair_t03", {"generation": 1})
	_check("host leave fixture: rejoined client owns a lease", await _until(func() -> bool: return host.session.repair_runtime.locks.has("T03")))
	host.net.leave()
	_check("host leave: offline continuation clears remote ownership and leases", host.session.peers == [1] and host.state().character(rejoined_actor.id).owner_peer == 0 and not host.session.repair_runtime.locks.has("T03"))
	_check("host quit: client is told", await _until(func() -> bool: return _lost != ""), _lost)
	_check("host quit: client back offline", client.mode == &"offline")

	# ---- nobody there
	_failed_join = ""
	client.net.join("127.0.0.1", PORT + 1)
	_check("join: nobody hosting gives a plain reason", await _until(func() -> bool: return _failed_join != "", 15.0), _failed_join)

	host.saves.delete_all()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)
