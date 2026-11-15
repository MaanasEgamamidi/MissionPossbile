extends SceneTree
## End-to-end checks of the assembled game scene (services + collision + player + HUD), run without the heavy map
## visuals. Input is injected with Input.action_press; physics is the real engine at 60 Hz, sped up with time_scale.
## Run: godot --headless --path . --script res://tests/test_game_scene.gd [-- --suit-only]

var _passed := 0
var _total := 0
var main: GameMain


func _check(name: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS ", name, ("  " + detail) if detail != "" else "")
	else:
		print("FAIL ", name, ": ", detail)


## Waits until  physics steps have really run. (Several steps can run between two resumptions of an awaiting
## script when the engine is sped up, so counting awaits would undercount time.)
func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame


func _release_all() -> void:
	for a in [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"jump", &"interact", &"grab", &"toggle_view"]:
		Input.action_release(a)


func _place(pos: Vector3, yaw: float) -> void:
	main.player.teleport(pos + Vector3(0, 0.05, 0), yaw)
	await _frames(3)


func _suit_checks() -> void:
	var services := main.services
	var me := services.local_character()
	var player := main.player
	var rack: Dictionary = services.state().stations["al_suit_rack"]
	var rack_pos := CharacterState._v3(rack.position)
	# Probe the actual headless collision assembly with the full player capsule.
	# Its rack clearance differs from the rendered map's prop-collision assembly.
	var spot := _free_spot_near(rack_pos, 1.6)
	await _place(spot, 0.0)
	await _frames(20)
	var contacts: Array[String] = []
	for index in player.get_slide_collision_count():
		var contact := player.get_slide_collision(index)
		contacts.append(str(contact.get_collider().get_path()))
	_check("suit approach is grounded, reported and within real reach", player.is_on_floor() and absf(player.global_position.y) < 0.1 and me.position.distance_to(player.global_position) < 0.05 and me.position.distance_to(rack_pos) <= services.config.interact_distance_m,
		"body=%s host=%s rack=%s distance=%.2f contacts=%s" % [player.global_position, me.position, rack_pos, me.position.distance_to(rack_pos), contacts])
	var tank := me.suit_charge
	var result := main._submit(&"begin_suit_check", &"al_suit_rack", {"on": true})
	_check("suit check starts at the rack", result.ok, "%s (planned %.2f m; body %s; host %s; rack %s; actual %.2f m)" % [result.message, spot.distance_to(rack_pos), player.global_position, me.position, rack_pos, me.position.distance_to(rack_pos)])
	await _frames(30)
	_check("after 0.5 s the suit is not on yet", not me.suit_on and services.session.suit_check_progress(me.id) > 0.3)
	await _frames(45)
	_check("after 1.25 s the suit is on and the tank is unchanged", me.suit_on and me.suit_charge == tank)
	result = main._submit(&"begin_suit_check", &"al_suit_rack", {"on": false})
	await _frames(20)
	await _place(services.config.hub_position, 0.0)
	await _frames(90)
	_check("leaving the rack cancels the check: suit still on", result.ok and me.suit_on and services.session.suit_check_progress(me.id) < 0.0,
		"%.2f m from rack" % me.position.distance_to(rack_pos))


func _initialize() -> void:
	# Real speed for everything timed in real seconds; the long walking checks further down are sped up.
	var dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/scene")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))

	# These checks walk, jump, suit up and use doors from the Med Bay hub, so the tutorial start (suited, outside, every
	# door held open) is switched off on the shared config the scene's GameServices loads; tests/test_tutorial_start.gd
	# checks the tutorial start in this same scene.
	var cfg := load(GameServices.CONFIG_PATH) as GameConfig
	cfg.tutorial_start_outside = false
	cfg.tutorial_start_suited = false
	cfg.tutorial_doors_open = false
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.load_world = false
	main.show_menu = false
	main.save_directory = dir
	root.add_child(main)
	await _frames(30)
	var services := main.services
	var st := services.state()
	var me := st.character_of_peer(1)
	var player := main.player

	# ---- start state
	_check("game starts: new colony, host plays crew_1", me != null and me.id == &"crew_1" and player != null)
	_check("starts in first person, FOV 72", player.is_first_person() and is_equal_approx(player.camera_rig().camera().fov, 72.0))
	_check("standing on the hub floor", player.is_on_floor() and absf(player.global_position.y) < 0.03, "y=%.3f" % player.global_position.y)
	_check("host position follows the body", me.position.distance_to(player.global_position) < 0.05)
	_check("three parked crew are shown, none of them is a second local body", main._crew_visuals.size() == 3)
	if OS.get_cmdline_user_args().has("--suit-only"):
		await _suit_checks()
		_release_all()
		services.saves.delete_all()
		print("RESULT %d/%d" % [_passed, _total])
		quit(0 if _passed == _total else 1)
		return

	# ---- walking under Mars gravity, reported to the host
	var start := player.global_position
	Input.action_press(&"move_forward")
	await _frames(120)
	Input.action_release(&"move_forward")
	await _frames(20)
	var walked := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	_check("walks from the hub spot (the rehearsal hub is a furnished room, so a short way)", walked > 0.5, "%.2f m in 2 s; start=%s end=%s input=%s yaw=%.2f" % [walked, start, player.global_position, player.input_enabled, player.camera_rig().yaw()])
	_check("host has the new position", me.position.distance_to(player.global_position) < 0.05)

	# ---- jump: apex and air time under 3.73 m/s²
	await _place(services.config.hub_position, 0.0)
	var y0 := player.global_position.y
	var apex := 0.0
	var air := 0
	Input.action_press(&"jump")
	await _frames(2)
	Input.action_release(&"jump")
	for i in 240:
		await physics_frame
		var h := player.global_position.y - y0
		apex = maxf(apex, h)
		if h > 0.003:
			air += 1
		elif air > 5:
			break
	var expect_air := 2.0 * sqrt(2.0 * player.tuning.jump_height_m / GameConfig.MARS_GRAVITY)
	_check("jump apex matches tuning under Mars gravity", absf(apex - player.tuning.jump_height_m) < 0.04, "apex %.3f m (tuned %.2f)" % [apex, player.tuning.jump_height_m])
	_check("jump air time matches 3.73 m/s²", absf(air / 60.0 - expect_air) < 0.12, "%.2f s (expected %.2f)" % [air / 60.0, expect_air])

	# ---- view toggle changes nothing the host owns
	var cargo_before := me.cargo.duplicate()
	for i in 6:
		Input.action_press(&"toggle_view")
		await _frames(2)
		Input.action_release(&"toggle_view")
		await _frames(2)
	_check("six Tab presses: back in first person, owner and cargo unchanged", player.is_first_person() and me.owner_peer == 1 and me.cargo == cargo_before)
	Input.action_press(&"toggle_view")
	await _frames(2)
	Input.action_release(&"toggle_view")
	await _frames(20)
	var cam := player.camera_rig().camera()
	var eye := player.global_position + Vector3.UP * player.tuning.eye_height_m
	var cam_dist := cam.global_position.distance_to(eye)
	var ray := PhysicsRayQueryParameters3D.create(eye, cam.global_position, Layers.WORLD | Layers.DOOR)
	var blocked := not root.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
	_check("third person: camera at most 2.5 m behind and nothing solid between it and the head", cam_dist <= 2.55 and not blocked, "%.2f m" % cam_dist)
	Input.action_press(&"toggle_view")
	await _frames(2)
	Input.action_release(&"toggle_view")
	await _frames(2)

	# ---- carrying through the host
	var crate := main._item_nodes["crate_1"] as CarryItem
	await _place(crate.global_position + Vector3(0, 0, 1.2), 0.0)
	var r := main._submit(&"pick_up", &"crate_1", {})
	await _frames(5)
	_check("pick up: host agrees and the crate is in the hand", r.ok and me.cargo == [&"crate_1"] and crate.is_held(), r.message)
	var anchor := player.visual().hand_anchor(true)
	Input.action_press(&"move_forward")
	await _frames(40)
	_check("held crate follows the hand while walking", crate.global_position.distance_to(anchor.global_position) < 0.02)
	Input.action_release(&"move_forward")
	r = main._submit(&"drop", &"crate_1", {})
	await _frames(40)
	_check("drop: host agrees, crate is a free body again and in nobody's cargo", r.ok and me.cargo.is_empty() and not crate.is_held() and String(st.items["crate_1"]["holder"]) == "")
	_check("no duplicate or lost item", st.invariants_ok().is_empty() and st.items.size() == 3)

	# ---- suit check at the suit rack: one real second, then 20 % slower, tank untouched
	await _suit_checks()

	# ---- suit slowdown measured on open ground outdoors
	var run := _open_run(Vector3(-27.0, 0.0, 33.0), 14.0)                 # a clear straight line near the landing pad
	var open: Vector3 = run[0]
	var speeds := {}
	for suited: bool in [true, false]:
		me.suit_on = suited
		await _place(open + Vector3(0, 0.3, 0), float(run[1]))
		await _frames(40)
		Input.action_press(&"move_forward")
		await _frames(60)
		var a := player.global_position
		var f0 := Engine.get_physics_frames()
		await _frames(120)
		var b := player.global_position
		var seconds := float(Engine.get_physics_frames() - f0) / 60.0
		Input.action_release(&"move_forward")
		await _frames(10)
		speeds[suited] = Vector2(b.x - a.x, b.z - a.z).length() / seconds
	var ratio: float = speeds[true] / maxf(0.001, speeds[false])
	_check("outdoors on terrain: walks, and the suit is 20 % slower", absf(ratio - 0.8) < 0.03 and speeds[false] > 2.0,
		"suit %.2f m/s, no suit %.2f m/s, ratio %.3f; run from %s yaw %.2f clear=%s; ended at %s on_floor=%s" % [speeds[true], speeds[false], ratio, run[0], float(run[1]), run[2], player.global_position, player.is_on_floor()])
	me.suit_on = true

	# ---- power panel: menu opens, a switch is a validated request, load drops
	var panel: Dictionary = st.stations["pw_panel"]
	var panel_pos := Vector3(float(panel.position[0]), 0.0, float(panel.position[2]))
	await _place(_free_spot_near(panel_pos, 1.5), 0.0)
	main._submit(&"use_station", &"pw_panel", {})
	await _frames(2)
	_check("power panel opens as a station surface and steering stops", main.ui.top() is PowerStationPanel and not player.input_enabled)
	await _frames(15)
	var load_before := st.load_kw
	r = services.session.request(&"set_zone_power", &"pw_panel", {"zone": "Greenhouse", "on": false})
	await _frames(15)
	_check("switching the Greenhouse off lowers the load by its 9 kW", r.ok and absf((load_before - st.load_kw) - 9.0) < 0.01, "%.1f -> %.1f kW; %s; actor=%s" % [load_before, st.load_kw, r.message, me.position])
	main.ui.close_all()
	await _place(services.config.hub_position, 0.0)
	r = services.session.request(&"set_zone_power", &"pw_panel", {"zone": "Greenhouse", "on": true})
	_check("the same switch from across the base is refused", not r.ok and r.reason == &"too_far", String(r.reason))

	# ---- pause: solo pauses at once, the clock stops
	services.session.request(&"vote_pause", &"", {"paused": true})
	var ticks := services.clock().ticks
	await _frames(60)
	_check("paused: colony clock does not move", services.session.paused and services.clock().ticks == ticks)
	services.session.request(&"vote_pause", &"", {"paused": false})
	await _frames(60)
	_check("resumed: clock moves again", services.clock().ticks > ticks)

	# ---- zero condition: recovery at the hub with cost and cache shown
	await _place(open + Vector3(0, 0.3, 0), 0.0)
	await _frames(30)
	services.session.request(&"pick_up", &"crate_2")            # too far: stays where it is
	st.items["probe_item"] = {"kind": "sample", "position": [me.position.x, 0.0, me.position.z], "holder": ""}
	services.session.request(&"pick_up", &"probe_item")
	var incident := me.position
	var food := st.store(&"food_meals")
	var seen := {"health": -1.0}
	var tank_before_recovery := me.suit_charge
	services.events.character_recovered.connect(func(_id: StringName, _info: Dictionary) -> void:
		seen["health"] = me.health)
	# Production exposure is four real seconds, independent of the previous tiny health value.
	me.suit_charge = 0.0
	me.health = 0.01
	await _frames(180)
	_check("empty suit does not trigger the legacy one-tick recovery", float(seen["health"]) < 0.0 and me.lethal_exposure_seconds < services.config.exposure_lethal_seconds)
	await _frames(90)
	_check("recovered to the hub with health 50, suit kept", me.position.distance_to(me.hub_spot) < 0.6 and float(seen["health"]) == services.balance.recovery_health and me.suit_on,
		"health at recovery %.1f" % float(seen["health"]))
	_check("body moved to the hub too", player.global_position.distance_to(me.hub_spot) < 1.0)
	_check("cargo left in one cache where it happened", st.caches.size() == 1 and Vector3(float(st.caches[0].position[0]), float(st.caches[0].position[1]),
		float(st.caches[0].position[2])).distance_to(incident) < 0.5 and st.caches[0].items == ["probe_item"])
	_check("cost charged once: 0.3 meals", absf((food - st.store(&"food_meals")) - 0.3) < 0.02, "%.3f meals" % (food - st.store(&"food_meals")))
	var told := main.ui.subtitle_line().current_text()
	_check("the player is told the cost and where the cache is", told.contains("meals") and told.contains("cache"), told)
	_check("recovery does not refill the suit tank", me.suit_charge == 0.0)
	me.suit_charge = tank_before_recovery
	me.suit_on = false

	# ---- every door: walk through from both sides (engine sped up; the checks are positions, not timings)
	Engine.time_scale = 6.0
	Engine.max_physics_steps_per_frame = 60
	await _door_walks()

	_release_all()
	services.saves.delete_all()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


## A free standing spot near `around` with `length` metres of clear straight ground ahead. Returns [position, yaw].
func _open_run(around: Vector3, length: float) -> Array:
	var space := root.get_world_3d().direct_space_state
	for ring: float in [8.0, 12.0, 16.0, 22.0, 30.0]:
		for i in 12:
			var a := TAU * float(i) / 12.0
			var p := _free_spot_near(around + Vector3(cos(a), 0.0, sin(a)) * ring, 1.0)
			for j in 8:
				var yaw := TAU * float(j) / 8.0
				var dirv := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
				var clear := true
				for h: float in [0.3, 0.9, 1.6]:
					var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, h, 0), p + Vector3(0, h, 0) + dirv * length, Layers.WORLD | Layers.DOOR)
					if not space.intersect_ray(q).is_empty():
						clear = false
						break
				if clear:
					return [p, yaw, true]
	return [around, 0.0, false]


## A standing spot within `radius` of `around` where the player's capsule does not overlap anything.
func _free_spot_near(around: Vector3, radius: float) -> Vector3:
	var space := root.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = main.player.tuning.body_radius_m + 0.02
	shape.height = main.player.tuning.body_height_m + 0.04
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = main.player.collision_mask
	q.exclude = [main.player.get_rid()]
	for ring: float in [radius, radius * 0.8, radius * 1.2, radius * 0.6]:
		for i in 16:
			var a := TAU * float(i) / 16.0
			var p := around + Vector3(cos(a), 0.0, sin(a)) * ring
			q.transform = Transform3D(Basis(), p + Vector3.UP * (0.05 + main.player.tuning.body_height_m * 0.5))
			if space.intersect_shape(q, 1).is_empty():
				var down := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, -1.0, 0), Layers.WORLD)
				var hit := space.intersect_ray(down)
				if not hit.is_empty() and absf(float(hit.position.y)) < 0.1:
					return p
	return around + Vector3(radius, 0, 0)


func _door_walks() -> void:
	var player := main.player
	var doors := main.collision.get_node("Doors").get_children()
	var through := 0
	var failed := PackedStringArray()
	for d in doors:
		var door := d as DoorController
		var centre := (door.get_node("Sense") as Node3D).global_position
		centre.y = 0.0
		var leaf: Node3D = null
		for c in door.get_children():
			if c is AnimatableBody3D:
				leaf = c
				break
		var normal := leaf.global_basis.z
		normal.y = 0.0
		normal = normal.normalized()
		var ok_both := true
		for side: float in [1.0, -1.0]:
			var from := centre + normal * side * 1.9
			var to := centre - normal * side * 1.9
			var dirv := (to - from).normalized()
			await _place(from, atan2(-dirv.x, -dirv.z))
			Input.action_press(&"move_forward")
			var arrived := false
			var deadline := Engine.get_physics_frames() + 300
			while Engine.get_physics_frames() < deadline:
				await physics_frame
				var p := player.global_position
				if (Vector3(p.x, 0, p.z) - from).dot(dirv) > 3.2:
					arrived = true
					break
			Input.action_release(&"move_forward")
			await _frames(4)
			if not arrived:
				ok_both = false
				var p2 := player.global_position
				var space := root.get_world_3d().direct_space_state
				var rq := PhysicsRayQueryParameters3D.create(p2 + Vector3(0, 0.9, 0), p2 + Vector3(0, 0.9, 0) + dirv * 1.5, Layers.WORLD | Layers.DOOR)
				rq.exclude = [player.get_rid()]
				var hit := space.intersect_ray(rq)
				var what := "nothing ahead at chest height"
				if not hit.is_empty():
					var shape_owner := (hit.collider as CollisionObject3D).shape_owner_get_owner((hit.collider as CollisionObject3D).shape_find_owner(int(hit.shape))) as Node
					what = "%s/%s at %.2f m" % [(hit.collider as Node).name, shape_owner.name if shape_owner != null else "?", (hit.position as Vector3).distance_to(p2 + Vector3(0, 0.9, 0))]
				failed.append("door %d at (%.1f, %.1f) side %+d stopped %.2f m along, open=%s, blocked by %s" % [door.door_id, centre.x, centre.z, int(side),
					(Vector3(p2.x, 0, p2.z) - from).dot(dirv), door.is_open(), what])
		if ok_both:
			through += 1
	_check("doors open for the player and can be walked through both ways", through == doors.size(), "%d of %d; %s" % [through, doors.size(), "; ".join(failed)])
