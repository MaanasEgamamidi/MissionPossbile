extends SceneTree
## S01–S04 integration over real ENet: host, two clients, late join and authority boundaries.

const PORT := 24794
var passed := 0
var total := 0
var hazards: Array = []
var recoveries := 0
var answers: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, truth: bool) -> void:
	total += 1
	if truth:
		passed += 1
	print("PASS " if truth else "FAIL ", label)

func machine(id: String) -> GameServices:
	var holder := Node.new()
	holder.name = id
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + id))
	var service := GameServices.new()
	service.name = "Services"
	service.saves = SaveService.new(ProjectSettings.globalize_path("res://_test_saves/survival_net/" + id), "colony", 2)
	holder.add_child(service)
	# Deterministic manual host time; networking continues on its independent child.
	service.set_process(false)
	return service

func until(condition: Callable, seconds := 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return bool(condition.call())

func answer(pending: ActionResult) -> ActionResult:
	if not pending.pending:
		return pending
	await until(func() -> bool: return answers.has(pending.request_id))
	return answers.get(pending.request_id, ActionResult.failure(pending.request_id, &"timeout"))

func _run() -> void:
	var host := machine("SurvivalHost")
	# S01-S04 exposure needs unsuited crew from the Med Bay, not the tutorial start (suited, outside).
	host.config.tutorial_start_outside = false
	host.config.tutorial_start_suited = false
	host.start_new_game(1842)
	host.set_process(false)
	# The door-cycle checks below are about a sealed airlock: the broken T12 seal of a new game would keep it leaking.
	host.state().repair.tasks.T12.first_completed = true
	host.state().repair.tasks.T12.broken = false
	var inner := DoorController.new()
	inner.door_id = 901
	var outer := DoorController.new()
	outer.door_id = 902
	var bridge := AirlockHazardPresenter.new()
	host.add_child(bridge)
	var doors: Array[DoorController] = [inner, outer]
	bridge.setup(host, doors, false)
	outer.opening_started.emit(902)
	check("actual door opening signal immediately vents local chamber", bool(host.session.survival.pressure_info().outer_open) and not bool(host.session.survival.pressure_info().breathable))
	outer.opened_changed.emit(902, false)
	check("threshold event cannot falsely close pressure boundary", bool(host.session.survival.pressure_info().outer_open))
	outer.closed_fully.emit(902)
	host.session.advance(5)
	check("fully closed door allows recovery without locking inner egress", bool(host.session.survival.pressure_info().breathable) and not inner.locked and not bool(host.session.survival.pressure_info().outer_open))
	check("world pressure bridge never double bills colony gas", float(host.state().ledger.airlock_cycles) == 0.0 and float(host.state().ledger.airlock_o2_lost_kg) == 0.0)
	inner.free()
	outer.free()
	check("host starts ENet", host.net.host(PORT) == OK)
	var client := machine("SurvivalClient")
	client.events.hazard_changed.connect(func(id: StringName, facts: Dictionary) -> void: hazards.append([id, facts]))
	client.events.action_resolved.connect(func(result: ActionResult) -> void: answers[result.request_id] = result)
	host.events.character_recovered.connect(func(_id: StringName, _info: Dictionary) -> void: recoveries += 1)
	check("first client joins", client.net.join("127.0.0.1", PORT) == OK and await until(func() -> bool: return client.has_game() and client.net.is_client()))
	var actor_id := client.local_character().id
	var actor := host.state().character(actor_id)
	var outside := Vector3(80, 0, 80)
	host.session.report_position(client.local_peer(), actor_id, outside, 0)
	host.session.advance(1.25)
	check("client receives active host exposure", await until(func() -> bool: return client.state().character(actor_id).exposure_active and is_equal_approx(client.state().character(actor_id).lethal_exposure_seconds, 1.25)))
	check("hazard event forwards exact actor and cause", hazards.any(func(event: Array) -> bool: return event[0] == actor_id and bool(event[1].active) and String(event[1].cause).contains("NO BREATHABLE AIR")))
	var task_condition := float(host.state().repair.tasks.T01.condition)
	var client_elapsed := client.state().character(actor_id).lethal_exposure_seconds
	client.session.advance(200)
	check("replica cannot tick exposure or wear", is_equal_approx(client.state().character(actor_id).lethal_exposure_seconds, client_elapsed) and is_equal_approx(float(client.state().repair.tasks.T01.condition), task_condition))
	var third := machine("SurvivalLateClient")
	check("second client late joins", third.net.join("127.0.0.1", PORT) == OK and await until(func() -> bool: return third.has_game() and third.net.is_client()))
	check("late join receives elapsed exposure and wear", is_equal_approx(third.state().character(actor_id).lethal_exposure_seconds, 1.25) and is_equal_approx(float(third.state().repair.tasks.T01.condition), task_condition))
	host.session.paused = true
	host.session.advance(100)
	check("global pause preserves timer and condition", is_equal_approx(actor.lethal_exposure_seconds, 1.25) and is_equal_approx(float(host.state().repair.tasks.T01.condition), task_condition))
	host.session.paused = false
	host.session.advance(2.75)
	check("host resolves once at four seconds", recoveries == 1 and actor.health == 50.0 and actor.lethal_exposure_seconds == 0.0)
	check("both peers receive recovered state", await until(func() -> bool: return client.state().character(actor_id).health == 50.0 and third.state().character(actor_id).health == 50.0 and not client.state().character(actor_id).exposure_active))
	host.session.advance(0.3)
	check("safe continuation does not duplicate recovery", recoveries == 1)
	host.session.survival.debug_trigger_airlock_fault()
	host.session.advance(0.1)
	check("two clients receive local pressure fault", await until(func() -> bool: return not bool(client.session.survival.pressure_info().breathable) and not bool(third.session.survival.pressure_info().breathable)))
	check("local fault preserves healthy cabin", host.session.survival.breathable_at(host.config.hub_position))
	check("client has no debug fault authority", not client.session.survival.debug_trigger_airlock_fault())
	host.session.survival.set_airlock_door_open(902, true)
	check("door facts replicate", await until(func() -> bool: return bool(client.session.survival.pressure_info().outer_open) and bool(third.session.survival.pressure_info().outer_open)))
	# A general task permits either client to work; the host owns all elapsed time and exclusive access.
	# This scenario tests ordinary service wear, not an unsolved repair mini-game.
	host.state().repair.tasks.T03.broken = false
	var station := CharacterState._v3(host.state().stations.repair_t03.position)
	host.session.report_position(client.local_peer(), actor_id, station, 0)
	var gen := int(host.state().repair.tasks.T03.fault_generation)
	var started := await answer(client.request(&"maintenance_start", &"repair_t03", {"generation": gen}))
	check("client starts host timed maintenance", started.ok and host.session.wear_runtime.status("T03").active)
	host.session.advance(7)
	check("both peers see one maintenance clock", await until(func() -> bool: return is_equal_approx(float(client.session.wear_runtime.status("T03").get("elapsed_seconds", -1.0)), 7.0) and is_equal_approx(float(third.session.wear_runtime.status("T03").get("elapsed_seconds", -1.0)), 7.0)))
	var third_actor := third.local_character()
	host.session.report_position(third.local_peer(), third_actor.id, station, 0)
	third.events.action_resolved.connect(func(result: ActionResult) -> void: answers[result.request_id] = result)
	var competing := await answer(third.request(&"maintenance_start", &"repair_t03", {"generation": gen}))
	check("second peer cannot double maintenance", not competing.ok and competing.reason == &"task_busy")
	host.session.advance(13)
	check("single completion restores mapped system", float(host.state().repair.tasks.T03.condition) == 1.0 and not host.session.wear_runtime.status("T03").active and not host.state().repair.tasks.T03.first_completed and float(host.state().repair.tasks.T04.condition) < 1.0)
	check("repair result converges across two clients", await until(func() -> bool: return float(client.state().repair.tasks.T03.condition) == 1.0 and float(third.state().repair.tasks.T03.condition) == 1.0 and not third.session.wear_runtime.status("T03").active))
	# Close while the start is still pending: the ordered cancel must reach the host
	# even before the panel has received any replicated job or acknowledgement.
	host.state().repair.tasks.T03.condition = 0.8
	# T03 is a broken part at the start, so E would open its puzzle; this check is about the maintenance panel.
	host.state().repair.tasks.T03.first_completed = true
	host.state().repair.tasks.T03.broken = false
	host.events.state_changed.emit(&"maintenance_fixture")
	await until(func() -> bool: return is_equal_approx(float(client.state().repair.tasks.T03.condition), 0.8))
	var pending_panel := StationPanels.for_station(&"repair_t03", client) as MaintenanceStationPanel
	client.add_child(pending_panel)
	var answers_before := answers.size()
	pending_panel._send(&"maintenance_start")
	pending_panel.queue_free()
	check("closing pending LAN maintenance releases host job", await until(func() -> bool: return answers.size() >= answers_before + 2 and not host.session.wear_runtime.status("T03").active))
	client.net.leave()
	check("disconnected replica has no local host identity or save authority", not client.is_authority() and client.local_character() == null and client.save_now() == ERR_UNCONFIGURED and client.net.host(PORT + 1) == ERR_UNCONFIGURED)
	check("disconnected replica cannot issue local mutations", client.request(&"vote_pause", &"", {"paused": true}).reason == &"offline")
	var disconnected_elapsed := client.state().character(actor_id).lethal_exposure_seconds
	client.session.advance(99)
	check("disconnect preserves replica without offline ticking", is_equal_approx(client.state().character(actor_id).lethal_exposure_seconds, disconnected_elapsed))
	third.net.leave()
	host.net.leave()
	print("RESULT %d/%d" % [passed, total])
	quit(0 if passed == total else 1)
