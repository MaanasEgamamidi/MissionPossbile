extends SceneTree
## Tutorial mode start (owner rule, 2026-11-14): a new game puts every crew member in a full suit right outside the exit
## tunnel's outer door, every door is held open until the tutorial is done (then doors auto-close and the airlock pair
## interlocks again), the broken T12 seal leaks from the start, the Med Bay stays the hub and the respawn point, and
## save/continue keeps all of it.
## Run: godot --headless --path . --script res://tests/test_tutorial_start.gd

const OUTER_DOOR_Z := Vector2(14.55, 14.85)   # EnvironmentCollision.DOORS, door 902
const DOOR_X := Vector2(20.2, 23.8)
const VESTIBULE := Vector3(22.0, 0.04, 12.5)  # inside LocalPressure.VOLUME
const SAVE_ROOT := "res://_test_saves/test_tutorial_start"

var _passed := 0
var _total := 0
var _recoveries := 0


func _check(name: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS ", name, ("  " + detail) if detail != "" else "")
	else:
		print("FAIL ", name, ": ", detail)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _services_checks()
	await _world_checks()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


func _make(dir: String) -> GameServices:
	var g := GameServices.new()
	g.saves = SaveService.new(ProjectSettings.globalize_path(SAVE_ROOT).path_join(dir), "colony", 2)
	root.add_child(g)
	g.set_process(false)          # the test drives host time itself
	return g


func _sorted_ids(st: ColonyState) -> Array:
	var ids := st.characters.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	return ids


func _run_for(g: GameServices, seconds: float, frame := 0.05) -> void:
	var left := seconds
	while left > 1e-6:
		var step := minf(frame, left)
		g.session.advance(step)
		left -= step


## Ends the tutorial on the host (the whiteboard flow itself is tested in tests/test_tutorial.gd; here only the
## doors' answer to "tutorial done" matters, so the tutorial is skipped).
func _finish_tutorial(g: GameServices) -> void:
	TutorialSystem.skip_tutorial(g.state(), g.events)


# ================================================================ services: start, T12 leak, save/continue, respawn

func _services_checks() -> void:
	var g := _make("services")
	g.saves.delete_all()
	var cfg := g.config
	_check("config: the shipped game starts in tutorial mode (outside, suited, doors held open)",
		cfg.tutorial_start_outside and cfg.tutorial_start_suited and cfg.tutorial_doors_open)
	g.start_new_game(4711)
	g.session.events.character_recovered.connect(func(_id: StringName, _info: Dictionary) -> void: _recoveries += 1)
	var st := g.state()
	var ids := _sorted_ids(st)

	# ---- everyone suited with full tanks
	var suits := PackedStringArray()
	for id: StringName in ids:
		var c := st.character(id)
		if not (c.suit_on and c.suit_charge == 100.0 and c.suit_integrity == 1.0 and g.session.survival.functional_suit(c)):
			suits.append("%s on=%s tank=%.1f seal=%.2f" % [id, c.suit_on, c.suit_charge, c.suit_integrity])
	_check("new game: all four crew wear a working suit with a full tank", ids.size() == 4 and suits.is_empty(), ", ".join(suits))

	# ---- at the spawn, right outside the outer door, in the Exterior zone, apart from each other
	var where := PackedStringArray()
	var placed := true
	for i in ids.size():
		var c := st.character(ids[i])
		var want := cfg.tutorial_spawn_position + cfg.tutorial_spawn_offsets[i]
		where.append("%s %s %s outside=%s" % [ids[i], c.position, g.zones.zone_at_world(c.position), c.outside])
		placed = placed and c.position.is_equal_approx(want) and is_equal_approx(c.yaw, cfg.tutorial_spawn_yaw)
	_check("new game: every crew member stands on their tutorial spawn spot", placed, "; ".join(where))
	_check("new game: the spawn is in the Exterior zone and every crew member counts as outside",
		ids.all(func(id: StringName) -> bool: return g.zones.zone_at_world(st.character(id).position) == ColonyZones.EXTERIOR and st.character(id).outside), "; ".join(where))
	_check("new game: the spawn is right outside the exit tunnel's outer door (Mars side, within 4 m, in front of the doorway)",
		ids.all(func(id: StringName) -> bool:
			var p := st.character(id).position
			return p.z > OUTER_DOOR_Z.y and p.z - OUTER_DOOR_Z.y < 4.0 and p.x > DOOR_X.x and p.x < DOOR_X.y), "; ".join(where))
	var closest := INF
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			closest = minf(closest, st.character(ids[i]).position.distance_to(st.character(ids[j]).position))
	_check("new game: crew stand at least 1 m apart (two body widths with room to spare)", closest >= 1.0, "%.2f m" % closest)
	_check("new game: the host plays crew_1 and the tutorial is at stage 1, not done",
		st.character(&"crew_1").owner_peer == 1 and TutorialSystem.current_stage(st) == 1 and not TutorialSystem.is_tutorial_done(st))
	_check("new game: every hub spot (parking and respawn) is still in the Med Bay",
		ids.all(func(id: StringName) -> bool: return g.zones.zone_at_world(st.character(id).hub_spot) == "Med Bay"))
	_run_for(g, 1.0)
	_check("new game: suited crew outside are not in danger", ids.all(func(id: StringName) -> bool:
		return not st.character(id).exposure_active and st.character(id).lethal_exposure_seconds == 0.0) and _recoveries == 0)

	# ---- the broken T12 seal leaks from the start
	var info := g.session.survival.pressure_info()
	_check("T12: the seal is a broken part at the start", PuzzleRegistry.is_broken(st, "T12") and not bool(st.repair.tasks.T12.get("maintenance_fault", false)))
	_check("T12: the exit vestibule leaks and is unbreathable from the start", bool(info.leaking) and not bool(info.breathable) and String(info.status) == "Seal leaking", str(info))
	var me := g.local_character()
	g.report_position(me.id, VESTIBULE, 0.0)
	_run_for(g, 5.0)
	_check("T12: a suited crew member in the leaking vestibule is protected (no countdown, no recovery)",
		me.in_airlock_pressure_volume and me.outside and me.exposure_protected and not me.exposure_active and _recoveries == 0 and me.health == 100.0,
		"in=%s outside=%s protected=%s active=%s t=%.2f" % [me.in_airlock_pressure_volume, me.outside, me.exposure_protected, me.exposure_active, me.lethal_exposure_seconds])
	g.report_position(me.id, cfg.tutorial_spawn_position, cfg.tutorial_spawn_yaw)
	_run_for(g, 0.5)

	# ---- save and continue keep the tutorial start
	_check("save: written", g.save_now(&"tutorial_start") == OK)
	var saved := {}
	for id: StringName in ids:
		saved[id] = st.character(id).to_dict()
	var saved_kpa := float(st.pressure.airlock_kpa)
	var g2 := _make("services")
	var loaded := g2.continue_game()
	var st2 := g2.state()
	_check("continue: status ok", loaded.status == &"ok", String(loaded.status))
	var host2 := st2.character(&"crew_1")
	var host_saved: Dictionary = saved[&"crew_1"]
	_check("continue: the host is back where they were saved, suited, same tank, still outside",
		host2.owner_peer == 1 and host2.position.is_equal_approx(CharacterState._v3(host_saved.position)) and host2.suit_on and is_equal_approx(host2.suit_charge, float(host_saved.suit_charge)) and host2.outside,
		"%s tank %.3f" % [host2.position, host2.suit_charge])
	var kept := PackedStringArray()
	var parked := PackedStringArray()
	for id: StringName in ids:
		var c := st2.character(id)
		var was: Dictionary = saved[id]
		if not (c.suit_on and is_equal_approx(c.suit_charge, float(was.suit_charge)) and is_equal_approx(c.suit_integrity, float(was.suit_integrity))):
			kept.append("%s on=%s tank=%.2f" % [id, c.suit_on, c.suit_charge])
		var at_saved := c.position.is_equal_approx(CharacterState._v3(was.position))
		if not at_saved and not c.position.is_equal_approx(c.hub_spot):
			parked.append("%s at %s" % [id, c.position])
	_check("continue: every crew member still wears the same suit with the same tank", kept.is_empty(), ", ".join(kept))
	# Crew nobody controls after a load are parked on their Med Bay hub spot (GameServices._place_crew_at_hub).
	_check("continue: every crew member is at their saved spot or parked on their Med Bay hub spot", parked.is_empty(), ", ".join(parked))
	var info2 := g2.session.survival.pressure_info()
	_check("continue: T12 is still broken and the vestibule still leaks at the saved pressure",
		PuzzleRegistry.is_broken(st2, "T12") and bool(info2.leaking) and not bool(info2.breathable) and is_equal_approx(float(st2.pressure.airlock_kpa), saved_kpa), str(info2))
	_check("continue: the tutorial is still running (so doors stay held open) and at the same stage",
		not TutorialSystem.is_tutorial_done(st2) and TutorialSystem.current_stage(st2) == TutorialSystem.current_stage(st))
	_check("continue: hub spots are still in the Med Bay", _sorted_ids(st2).all(func(id: StringName) -> bool: return g2.zones.zone_at_world(st2.character(id).hub_spot) == "Med Bay"))

	# ---- respawn: the Med Bay, also for a death in the leaking vestibule
	var recovered := [0]          # an array: a lambda cannot assign an outer local
	g2.session.events.character_recovered.connect(func(_id: StringName, _info: Dictionary) -> void: recovered[0] += 1)
	var me2 := g2.local_character()
	var heal := CharacterState._v3(st2.stations.md_heal_station.position)
	me2.suit_on = false
	g2.report_position(me2.id, VESTIBULE, 0.0)
	_check("T12: without a suit the leaking vestibule is deadly at once", me2.exposure_active and "AIRLOCK" in String(g2.session.survival.status(me2.id).cause), String(g2.session.survival.status(me2.id).cause))
	_run_for(g2, 3.9)
	var alive_at_39: bool = recovered[0] == 0
	_run_for(g2, 0.2)
	_check("respawn: an unsuited crew member in the vestibule is recovered once at 4 s", alive_at_39 and recovered[0] == 1 and String(me2.last_death.get("cause", "")) == "airlock_pressure", str(me2.last_death.get("cause", "")))
	_check("respawn: back in the Med Bay on the hub spot near the med station",
		g2.zones.zone_at_world(me2.position) == "Med Bay" and me2.position == me2.hub_spot and me2.position.distance_to(heal) < 6.0, str(me2.position))

	# ---- solving the T12 puzzle stops the leak
	st2.repair.tasks.T12.first_completed = true
	_run_for(g2, g2.config.airlock_pressure_recovery_seconds + 1.0)
	var info3 := g2.session.survival.pressure_info()
	_check("T12: once the seal puzzle is solved the vestibule stops leaking and repressurizes", not PuzzleRegistry.is_broken(st2, "T12") and not bool(info3.leaking) and bool(info3.breathable), str(info3))
	g2.saves.delete_all()
	g.queue_free()
	g2.queue_free()
	await process_frame


# ================================================================ the real game scene: ground, collision and doors

func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame


func _all_doors(main: GameMain) -> Array[DoorController]:
	var out: Array[DoorController] = []
	for n in main.find_children("*", "DoorController", true, false):
		out.append(n as DoorController)
	return out


func _door(main: GameMain, id: int) -> DoorController:
	for d in _all_doors(main):
		if d.door_id == id:
			return d
	return null


func _world_checks() -> void:
	var main := (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.load_world = true
	main.show_menu = true
	main.check_weather_updates = false
	main.save_directory = ProjectSettings.globalize_path(SAVE_ROOT).path_join("world")
	root.add_child(main)
	main.services.saves.delete_all()
	main._on_menu_new()
	var services := main.services
	var st := services.state()
	var ids := _sorted_ids(st)
	await _frames(150)        # 2.5 s: the 0.5 s door sync, then 0.6 s of door travel

	# ---- on the ground, clear of collision and of each other
	var player := main.player
	var space := player.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = player.tuning.body_radius_m
	capsule.height = player.tuning.body_height_m
	var problems := PackedStringArray()
	for id: StringName in ids:
		var p := st.character(id).position
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis(), p + Vector3(0.0, capsule.height * 0.5 + 0.03, 0.0))
		query.collision_mask = Layers.WORLD | Layers.DOOR
		for hit: Dictionary in space.intersect_shape(query, 8):
			problems.append("%s overlaps %s" % [id, (hit.collider as Node).name])
		var ray := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p - Vector3(0, 1.0, 0), Layers.WORLD))
		if ray.is_empty() or absf(float((ray.position as Vector3).y) - p.y) > 0.15:
			problems.append("%s at %s has no ground within 15 cm (%s)" % [id, p, ray.get("position", "none")])
	_check("world: every crew member's body fits at the spawn (no wall, rock, prop or door leaf) with ground under the feet", problems.is_empty(), "; ".join(problems))
	var closest := INF
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			closest = minf(closest, st.character(ids[i]).position.distance_to(st.character(ids[j]).position))
	_check("world: crew bodies do not overlap each other", closest > 2.0 * capsule.radius + 0.1, "%.2f m apart, radius %.2f" % [closest, capsule.radius])
	_check("world: the host's body stands on the ground outside", player.is_on_floor() and services.zones.zone_at_world(player.global_position) == ColonyZones.EXTERIOR
		and player.global_position.distance_to(st.character(&"crew_1").position) < 0.3, str(player.global_position))

	# ---- every door held open while the tutorial runs, both airlock doors at once
	var doors := _all_doors(main)
	var shut := PackedStringArray()
	for d in doors:
		if not (d.held_open and d.is_open()):
			shut.append("%d held=%s open=%.2f locked=%s" % [d.door_id, d.held_open, d.open_amount, d.locked])
	var inner := _door(main, 901)
	var outer := _door(main, 902)
	_check("doors: the map's doors, the exit tunnel pair and the garden dome pair are all there", doors.size() >= 28 and inner != null and outer != null and inner.partner == outer and outer.partner == inner, "%d doors" % doors.size())
	_check("doors: while the tutorial runs every door is held fully open", main.tutorial_doors_open() and shut.is_empty(), ", ".join(shut))
	_check("doors: both exit tunnel doors stand open together during the tutorial (interlock paused)", inner.is_open() and outer.is_open())

	# ---- after the tutorial: doors auto-close, open for a player, and the airlock interlocks again
	_finish_tutorial(services)
	_check("tutorial: finished", TutorialSystem.is_tutorial_done(st) and not main.tutorial_doors_open())
	var hub := st.character(&"crew_1").hub_spot
	player.teleport(hub + Vector3(0, 0.05, 0), 0.0)
	await _frames(150)
	var still := PackedStringArray()
	for d in doors:
		if d.held_open or d.open_amount > 0.0:
			still.append("%d held=%s open=%.2f" % [d.door_id, d.held_open, d.open_amount])
	_check("after tutorial: no door is held and every door has closed by itself", still.is_empty(), ", ".join(still))
	var plain := _door(main, 1)
	player.teleport((plain.get_node("Sense") as Node3D).global_position, 0.0)   # as tests/test_net_game.gd does
	var opened := false
	for i in 120:
		await _frames(1)
		if plain.is_open():
			opened = true
			break
	player.teleport(hub + Vector3(0, 0.05, 0), 0.0)
	var closed := false
	for i in 150:
		await _frames(1)
		if plain.open_amount == 0.0:
			closed = true
			break
	_check("after tutorial: a door opens for a player and shuts again when they walk away", opened and closed, "opened=%s closed=%s" % [opened, closed])
	# Airlock: this player opens the inner door; a second astronaut (any PLAYER-layer body, like a LAN client's presence)
	# then waits outside the outer door. The outer door stays shut while the inner one is open, and opens only after the
	# inner door has been shut for the pressure cycle.
	var outer_cycles := [0]       # an array: a lambda cannot assign an outer local
	outer.cycle_started.connect(func(_id: int, _s: float) -> void: outer_cycles[0] += 1)
	var both := false
	player.teleport(Vector3(22.0, 0.05, 9.6), PI)
	var inner_opened := false
	for i in 480:                                  # up to 8 s (the inner door may first wait for its own cycle)
		await _frames(1)
		both = both or (inner.open_amount > 0.0 and outer.open_amount > 0.0)
		if inner.is_open():
			inner_opened = true
			break
	var other := AnimatableBody3D.new()           # the same kind of body as a LAN client's door presence
	other.sync_to_physics = false
	other.collision_layer = Layers.PLAYER
	other.collision_mask = 0
	other.position = Vector3(22.0, 0.9, OUTER_DOOR_Z.y + 0.8)
	var shape := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 0.3
	shape.shape = ball
	other.add_child(shape)
	main.add_child(other)
	var outer_waited := true
	for i in 120:                                  # 2 s with both doors wanted
		await _frames(1)
		both = both or (inner.open_amount > 0.0 and outer.open_amount > 0.0)
		outer_waited = outer_waited and outer.open_amount == 0.0
	player.teleport(hub + Vector3(0, 0.05, 0), 0.0)
	var inner_shut_frame := -1
	var outer_open_frame := -1
	for i in 600:                                  # up to 10 s
		await _frames(1)
		both = both or (inner.open_amount > 0.0 and outer.open_amount > 0.0)
		if inner_shut_frame < 0 and inner.open_amount == 0.0:
			inner_shut_frame = Engine.get_physics_frames()
		if outer_open_frame < 0 and outer.open_amount > 0.0:
			outer_open_frame = Engine.get_physics_frames()
		if outer.is_open():
			break
	var gap := float(outer_open_frame - inner_shut_frame) / float(Engine.physics_ticks_per_second)
	_check("after tutorial: the inner tunnel door opens for a player", inner_opened, "inner %.2f outer %.2f" % [inner.open_amount, outer.open_amount])
	_check("after tutorial: the outer door stays shut while the inner door is open (airlock interlock back)", inner_opened and outer_waited)
	_check("after tutorial: the outer door opens only after the inner door has been shut for the pressure cycle, never both open",
		outer.is_open() and inner_shut_frame >= 0 and outer_open_frame > inner_shut_frame and gap >= outer.cycle_seconds - 0.1 and outer_cycles[0] >= 1 and not both,
		"gap %.2f s (cycle %.1f s), cycles %d, both %s" % [gap, outer.cycle_seconds, outer_cycles[0], both])
	other.queue_free()
	services.saves.delete_all()
	main.queue_free()
	await process_frame
