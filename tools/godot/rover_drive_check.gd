extends SceneTree
## Headless driving checks for the rover (Prompt 10, worker P10B).
##
## Loads the real game scene WITH the map, so the rover meets the game's own collision (map boxes, door leaves, the
## 996 rock hulls, the baked prop shapes, the terrain height field), adds RoverPresenter as GameMain would, boards the
## driver's seat with E and drives only by scripted input frames: the same Input actions a player presses (W/S as
## throttle and brake-against, A/D steering, Space brake, E in and out). Nothing moves the rover except its physics.
## A small "driver" turns waypoints into those key presses (a test harness, not a game feature).
## Physics runs at 60 Hz: physics_ticks_per_second = 60 x SPEEDUP with Engine.time_scale = SPEEDUP keeps every step
## 1/60 s of game time while the run goes SPEEDUP times faster than real time.
##
## Run: godot --headless --path . --script res://tools/godot/rover_drive_check.gd            (drive and print the table)
##      godot --headless --path . --script res://tools/godot/rover_drive_check.gd -- --inspect (map evidence only)
## tests/test_rover_drive.gd runs the same drive (run()) and checks the numbers.

const SPEEDUP := 4
const DT := 1.0 / 60.0
const SAVE_DIR := "_test_saves/rover_drive"
## The salvage donor the long route visits (Exterior, static; a candidate donor of worker P10A).
const DONOR := "sf_crash_shield"
const TEST_SCRIPT := "res://tests/test_rover_drive.gd"
## Garage interior footprint in world x / z (sf_print_garage walls' inner faces).
const GARAGE_X := Vector2(5.0, 11.5)
const GARAGE_Z := Vector2(20.0, 26.0)


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--inspect"):
		await inspect(self)
		quit(0)
		return
	var r: Dictionary = await run(self)
	print_table(r)
	quit(0)


# ---------------------------------------------------------------- the drive

## Builds the game with the map and the rover, drives every scenario in one continuous session and returns the numbers.
## `prepare` (optional) is called with the GameServices before boarding (the test registers stand-in actions there).
static func run(tree: SceneTree, prepare: Callable = Callable()) -> Dictionary:
	var out := {"ok": false}
	Engine.physics_ticks_per_second = 60 * SPEEDUP
	Engine.max_physics_steps_per_frame = 8 * SPEEDUP
	Engine.time_scale = SPEEDUP
	PlayerInput.ensure_actions()
	var dir := ProjectSettings.globalize_path("res://").path_join(SAVE_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	var main := (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.load_world = true
	main.show_menu = false
	main.save_directory = dir
	tree.root.add_child(main)
	await frames(tree, 10)
	var services := main.services
	# The game scene builds the rover itself (GameMain.rover); a second presenter would put a second body on the rover.
	var presenter: RoverPresenter = main.rover
	if presenter == null:
		presenter = RoverPresenter.new()
		presenter.name = "Rover"
		main.add_child(presenter)
		presenter.setup(main.world, services, main)
	if prepare.is_valid():
		prepare.call(services)
	else:
		var test_script := load(TEST_SCRIPT)
		test_script.install_stand_ins(services.session)
	var st := services.state()
	var body := presenter.body
	var ctx := {"tree": tree, "main": main, "presenter": presenter, "body": body, "services": services}
	out.setup = presenter.setup_report.duplicate()
	out.prop_cache = String(main.prop_collision_stats.get("cache", ""))
	out.accounting = presenter.accounting
	out.physics_hz = Engine.physics_ticks_per_second / Engine.time_scale
	st.rover["built"] = true
	presenter._refresh_stats(st, RoverPresenter.seats_of(st))
	var cap := float(RoverModel.stats(st.rover.levels, 0.0).get("battery_capacity_kwh", 10.0))
	st.rover["battery_kwh"] = cap
	out.stats = RoverModel.stats(st.rover.levels, 0.0)
	out.capacity_kwh = cap
	await frames(tree, 90)          # settle on the suspension
	out.settled = {"y": body.global_position.y, "speed": body.linear_velocity.length(), "wheels": body.wheels_grounded,
		"tilt_deg": tilt_deg(body)}

	# ---- board: stand by the left side, look at the rover, press E
	var player := main.player
	ctx.player = player
	var stand_at: Vector3 = presenter.exit_ground(1)
	# The garage is outside: the crew member is suited, as anyone standing there would be (rover_enter requires it).
	services.local_character().suit_on = true
	player.teleport(stand_at + Vector3.UP * 0.05, 0.0)
	await frames(tree, 5)
	await look_at_rover(tree, ctx)
	out.cue_before = presenter.hud_widget.cue_text()
	await press(tree, &"interact")
	await frames(tree, 10)
	out.boarded = player.is_seated() and RoverPresenter.seats_of(st)[0] == String(services.local_character().id)
	out.role_after_boarding = presenter.role
	out.hud_text = presenter.hud_widget.panel_text()
	out.eye_above_floor = player.camera_rig().global_position.y - (body.seat_anchor(0).global_position.y)
	if not out.boarded:
		return out
	body.reset_telemetry()
	var odo_start := odometer_start(body)
	var battery_start := float(st.rover.battery_kwh)

	# ---- straight run out of the garage (full throttle, wheel straight)
	out.straight = await accel_run(tree, ctx, body.top_speed_mps * 0.9, 12.0, 0.0, Vector3(22.0, 0.0, 23.0))
	# ---- turn onto the long straight and hold top speed, then brake
	await drive_to(tree, ctx, Vector3(23.0, 0.0, 31.0), {"radius": 3.0})
	out.straight.exit_x = body.global_position.x
	out.cruise = await cruise(tree, ctx, Vector3(23.0, 0.0, 70.0), 50.0, 10.0)
	out.brake = await brake_test(tree, ctx)
	# ---- tight turn at walking pace, full right lock
	out.turn = await turn_circle(tree, ctx, 1.5, 1.0)
	# ---- cargo: 0 -> 2 m/s with and without 800 kg aboard (RoverBody.set_payload: RoverModel.cargo_mass_kg is P10A's)
	await drive_to(tree, ctx, Vector3(14.0, 0.0, 46.0), {"radius": 2.0, "stop": true})
	var light := await accel_run(tree, ctx, 2.0, 10.0, 0.0, Vector3(0.0, 0.0, 46.0))
	await stop(tree, ctx)
	await drive_to(tree, ctx, Vector3(18.0, 0.0, 40.0), {"radius": 2.0, "stop": true})
	var mass_before := body.total_mass()
	body.set_payload(800.0)
	var heavy := await accel_run(tree, ctx, 2.0, 15.0, 0.0, Vector3(6.0, 0.0, 52.0))
	var mass_heavy := body.total_mass()
	body.set_payload(0.0)
	await stop(tree, ctx)
	out.cargo = {"light_s": light.t90, "heavy_s": heavy.t90, "mass_kg": mass_before, "heavy_mass_kg": mass_heavy}
	# ---- empty battery: throttle does nothing, the brake still holds
	var kept := float(st.rover.battery_kwh)
	st.rover["battery_kwh"] = 0.0
	var p0 := body.global_position
	set_inputs(1.0, 0.0, false)
	await frames(tree, 180)
	var crawl := body.linear_velocity.length()
	set_inputs(0.0, 0.0, false)
	out.empty_battery = {"moved_m": flat(body.global_position - p0).length(), "speed": crawl, "hud": presenter.hud_widget.panel_text()}
	st.rover["battery_kwh"] = kept

	# ---- the long route: garage -> salvage donor -> dunes -> rock field -> back into the garage
	var donor_pos := object_position(DONOR)
	var route := {"distance_m": 0.0, "time_s": 0.0, "min_y": INF, "max_y": -INF, "stuck": 0, "flips": 0, "max_tilt_deg": 0.0}
	var battery_route := float(st.rover.battery_kwh)
	presenter.flush_accounting()
	var charged_route := presenter.energy_charged_kwh
	var counted_route := presenter.distance_counted_m
	body.reset_telemetry()
	_merge(route, await drive_to(tree, ctx, Vector3(6.0, 0.0, 39.0), {"radius": 2.0}))
	_merge(route, await drive_to(tree, ctx, Vector3(-5.0, 0.0, 36.0), {"radius": 0.8, "speed": 1.0}))
	_merge(route, await stop(tree, ctx))
	route.at_donor_m = flat(body.global_position - body.global_basis.z * 2.6 - donor_pos).length()   # front bumper to the donor centre
	route.donor_gap_m = donor_gap(main, body.global_position - body.global_basis.z * 2.6 + Vector3.UP * 0.8)
	# back away from the donor (S held), as a driver would before turning round
	_merge(route, await reverse(tree, ctx, 8.0))
	var rough := {"distance_m": 0.0, "time_s": 0.0, "min_y": INF, "max_y": -INF, "stuck": 0, "flips": 0, "max_tilt_deg": 0.0}
	body.reset_telemetry()
	for wp: Vector3 in [Vector3(6.0, 0.0, 44.0), Vector3(15.0, 0.0, 50.0), Vector3(15.0, 0.0, 66.0), Vector3(-12.0, 0.0, 66.0),
			Vector3(-29.5, 0.0, 69.5), Vector3(-24.0, 0.0, 61.0), Vector3(-8.0, 0.0, 63.0), Vector3(15.0, 0.0, 66.0), Vector3(15.0, 0.0, 50.0), Vector3(23.0, 0.0, 41.0), Vector3(31.5, 0.0, 38.0), Vector3(31.5, 0.0, 25.5)]:
		_merge(rough, await drive_to(tree, ctx, wp, {"radius": 2.5}))
	rough.contact_share = body.contact_share()
	_merge(route, rough)
	for wp: Vector3 in [Vector3(24.0, 0.0, 23.1), Vector3(15.0, 0.0, 23.0)]:
		_merge(route, await drive_to(tree, ctx, wp, {"radius": 1.5, "speed": 2.0}))
	_merge(route, await drive_to(tree, ctx, Vector3(8.8, 0.0, 23.0), {"radius": 0.7, "speed": 1.2, "stop": true}))
	presenter.flush_accounting()
	route.energy_kwh = battery_route - float(st.rover.battery_kwh)
	route.charged_kwh = presenter.energy_charged_kwh - charged_route
	route.counted_m = presenter.distance_counted_m - counted_route
	var end := body.global_position
	route.end = end
	route.in_garage = end.x > GARAGE_X.x and end.x < GARAGE_X.y and end.z > GARAGE_Z.x and end.z < GARAGE_Z.y
	route.state_pose_error_m = (RoverBody.from_state_pose(st.rover.pose).p as Vector3).distance_to(end)
	out.route = route
	out.rough = rough
	out.trip_battery_used_kwh = battery_start - float(st.rover.battery_kwh)
	out.odometer_m = odometer_start(body).distance_to(odo_start)   # straight-line, for information

	# ---- getting out: every exit boxed in -> refused, one cleared -> out there
	out.exits = await exit_test(tree, ctx)
	# ---- four seats
	out.seats = await four_seats(tree, ctx)
	set_inputs(0.0, 0.0, false)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	out.ok = true
	out.ctx = ctx
	return out


# ---------------------------------------------------------------- scenarios

## From rest (or as it is), full throttle toward `aim` until `until_speed` m/s; t90 = time to reach it.
static func accel_run(tree: SceneTree, ctx: Dictionary, until_speed: float, timeout: float, _unused: float, aim: Vector3) -> Dictionary:
	var b: RoverBody = ctx.body
	var t := 0.0
	var start := b.global_position
	var vmax := 0.0
	var t90 := -1.0
	while t < timeout:
		var steer := _steer_to(b, aim)
		set_inputs(1.0, steer, false)
		await tree.physics_frame
		t += DT
		var v := b.forward_speed
		vmax = maxf(vmax, v)
		if t90 < 0.0 and v >= until_speed:
			t90 = t
			break
	set_inputs(0.0, 0.0, false)
	return {"t90": t90, "v_max": vmax, "distance_m": flat(b.global_position - start).length(), "time_s": t}


## Full throttle toward `aim` until the rover passes z = `until_z`; the speed is averaged over the last `measure_m`.
static func cruise(tree: SceneTree, ctx: Dictionary, aim: Vector3, until_z: float, measure_m: float) -> Dictionary:
	var b: RoverBody = ctx.body
	var t := 0.0
	var samples: Array = []          # [z, time]
	var vmax := 0.0
	while t < 60.0 and b.global_position.z < until_z:
		set_inputs(1.0, _steer_to(b, aim), false)
		await tree.physics_frame
		t += DT
		vmax = maxf(vmax, b.forward_speed)
		samples.append([b.global_position, t])
	var end: Vector3 = samples[-1][0]
	var t_end: float = samples[-1][1]
	var t_start := t_end
	var p_start := end
	for s: Array in samples:
		if (s[0] as Vector3).distance_to(end) <= measure_m:
			t_start = s[1]
			p_start = s[0]
			break
	var mean := p_start.distance_to(end) / maxf(t_end - t_start, 0.01)
	return {"mean_mps": mean, "v_max": vmax, "time_s": t, "top_speed": b.top_speed_mps}


## Drives toward `target` (x, z) with the waypoint driver. opts: radius (arrival, m), speed (cap, m/s), timeout (s),
## stop (brake to rest on arrival). Returns distance, time, min / max height, stuck count, flips, max tilt.
static func drive_to(tree: SceneTree, ctx: Dictionary, target: Vector3, opts := {}) -> Dictionary:
	var b: RoverBody = ctx.body
	var radius := float(opts.get("radius", 2.5))
	var cap := float(opts.get("speed", -1.0))
	var timeout := float(opts.get("timeout", 90.0))
	var r := {"distance_m": 0.0, "time_s": 0.0, "min_y": INF, "max_y": -INF, "stuck": 0, "flips": 0, "max_tilt_deg": 0.0, "arrived": false}
	var last := b.global_position
	var stuck_t := 0.0
	var reverse_left := 0.0
	var flipped := false
	while r.time_s < timeout:
		var p := b.global_position
		var to := flat(target - p)
		if to.length() < radius:
			r.arrived = true
			break
		var ang := _angle_to(b, target)
		var steer := clampf(-ang * 2.5, -1.0, 1.0)
		var want := cap if cap > 0.0 else b.top_speed_mps + 1.0
		if absf(ang) > 0.9:
			want = minf(want, 1.2)
		want = minf(want, maxf(1.0, to.length() * 0.5))
		var v := b.forward_speed
		var throttle := clampf((want - v) * 1.5, -1.0, 1.0)
		if reverse_left > 0.0:
			reverse_left -= DT
			throttle = -0.8
			steer = -steer
		elif throttle > 0.3 and absf(v) < 0.15:
			stuck_t += DT
			if stuck_t > 3.0:
				r.stuck += 1
				stuck_t = 0.0
				reverse_left = 2.0
		else:
			stuck_t = 0.0
		set_inputs(throttle, steer, false)
		await tree.physics_frame
		r.time_s += DT
		var now := b.global_position
		r.distance_m += now.distance_to(last)
		last = now
		r.min_y = minf(r.min_y, now.y)
		r.max_y = maxf(r.max_y, now.y)
		var tilt := tilt_deg(b)
		r.max_tilt_deg = maxf(r.max_tilt_deg, tilt)
		if tilt > 60.0 and not flipped:
			r.flips += 1
		flipped = tilt > 60.0
	set_inputs(0.0, 0.0, false)
	if bool(opts.get("stop", false)):
		_merge(r, await stop(tree, ctx))
	var e := b.global_position
	print("LEG to (%.1f, %.1f): at (%.1f, %.1f) y %.2f, arrived %s, %.1f m in %.1f s, stuck %d, max tilt %.1f deg" % [target.x, target.z, e.x, e.z, e.y,
		r.arrived, r.distance_m, r.time_s, r.stuck, r.max_tilt_deg])
	return r


## Backs straight up for `metres` (S held), then stops.
static func reverse(tree: SceneTree, ctx: Dictionary, metres: float) -> Dictionary:
	var b: RoverBody = ctx.body
	var start := b.global_position
	var r := {"distance_m": 0.0, "time_s": 0.0}
	while r.time_s < 20.0 and flat(b.global_position - start).length() < metres:
		set_inputs(-0.8, 0.0, false)
		await tree.physics_frame
		r.time_s += DT
	r.distance_m = flat(b.global_position - start).length()
	_merge(r, await stop(tree, ctx))
	return r


## Holds Space until the rover is at rest (or 15 s).
static func stop(tree: SceneTree, ctx: Dictionary) -> Dictionary:
	var b: RoverBody = ctx.body
	var r := {"distance_m": 0.0, "time_s": 0.0}
	var last := b.global_position
	while r.time_s < 15.0 and b.linear_velocity.length() > 0.05:
		set_inputs(0.0, 0.0, true)
		await tree.physics_frame
		r.time_s += DT
		r.distance_m += b.global_position.distance_to(last)
		last = b.global_position
	for i in 20:
		set_inputs(0.0, 0.0, true)
		await tree.physics_frame
	set_inputs(0.0, 0.0, false)
	return r


## From the cruise: Space held from the current speed; stopping distance and time.
static func brake_test(tree: SceneTree, ctx: Dictionary) -> Dictionary:
	var b: RoverBody = ctx.body
	var v0 := b.forward_speed
	var start := b.global_position
	var t := 0.0
	while t < 20.0 and b.linear_velocity.length() > 0.05:
		set_inputs(0.0, 0.0, true)
		await tree.physics_frame
		t += DT
	var d := flat(b.global_position - start).length()
	for i in 30:
		await tree.physics_frame
	set_inputs(0.0, 0.0, false)
	return {"v0": v0, "distance_m": d, "time_s": t, "mu": b.traction_mu, "ideal_m": v0 * v0 / (2.0 * b.traction_mu * GameConfig.MARS_GRAVITY)}


## Full right lock at about `speed` m/s for one and a quarter turns; the radius is the mean distance of the path from
## its centre over the last full turn (after `settle_s` of entry).
static func turn_circle(tree: SceneTree, ctx: Dictionary, speed: float, settle_s: float) -> Dictionary:
	var b: RoverBody = ctx.body
	var yaw_total := 0.0
	var last_fwd := flat(-b.global_basis.z).normalized()
	var t := 0.0
	var pts: Array[Vector3] = []
	var v_sum := 0.0
	while t < 60.0 and yaw_total < TAU + 0.6:
		var throttle := clampf((speed - b.forward_speed) * 2.0, -1.0, 1.0)
		set_inputs(throttle, 1.0, false)
		await tree.physics_frame
		t += DT
		var fwd := flat(-b.global_basis.z).normalized()
		var d_yaw := absf(last_fwd.signed_angle_to(fwd, Vector3.UP))
		last_fwd = fwd
		if t > settle_s:
			yaw_total += d_yaw
			pts.append(b.global_position)
			v_sum += b.forward_speed
	set_inputs(0.0, 0.0, false)
	await stop(tree, ctx)
	var centre := Vector3.ZERO
	for p in pts:
		centre += p
	centre /= maxf(1.0, pts.size())
	var rsum := 0.0
	for p in pts:
		rsum += flat(p - centre).length()
	var radius := rsum / maxf(1.0, pts.size())
	var geometric := 1.55 / tan(deg_to_rad(b.max_steer_deg))
	return {"radius_m": radius, "speed_mps": v_sum / maxf(1.0, pts.size()), "time_s": t, "yaw_deg": rad_to_deg(yaw_total),
		"geometric_m": geometric}


## Parked: boxes at every exit -> E is refused and the driver stays seated; one box removed -> E gets out there.
static func exit_test(tree: SceneTree, ctx: Dictionary) -> Dictionary:
	var b: RoverBody = ctx.body
	var presenter: RoverPresenter = ctx.presenter
	var player: PlayerController = ctx.player
	var main: GameMain = ctx.main
	var r := {}
	r.clear_before = []
	for i in b.exit_positions.size():
		r.clear_before.append(presenter.exit_clear(i))
	var boxes: Array[StaticBody3D] = []
	for i in b.exit_positions.size():
		var box := StaticBody3D.new()
		box.name = "ExitBlock%d" % i
		box.collision_layer = Layers.WORLD
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.6, 2.4, 0.6)
		cs.shape = shape
		box.add_child(cs)
		main.add_child(box)
		var g: Variant = presenter.exit_ground(i)
		box.global_position = (g as Vector3 if g != null else b.exit_world(i)) + Vector3.UP * 1.2
		boxes.append(box)
	await frames(tree, 3)
	r.first_clear_all_boxed = presenter.first_clear_exit()
	await press(tree, &"interact")
	await frames(tree, 10)
	r.still_seated_when_boxed = player.is_seated()
	r.message_when_boxed = PackedStringArray(main.hud.current_messages())
	var open_index := 2
	boxes[open_index].queue_free()
	await frames(tree, 3)
	r.first_clear_one_open = presenter.first_clear_exit()
	await press(tree, &"interact")
	await frames(tree, 10)
	r.out_after_clear = not player.is_seated()
	r.message_after_clear = PackedStringArray(main.hud.current_messages())
	var g2: Variant = presenter.exit_ground(open_index)
	r.exit_error_m = flat(player.global_position - (g2 as Vector3)).length() if g2 != null else INF
	r.standing_upright = absf(player.global_basis.y.dot(Vector3.UP) - 1.0) < 1e-3
	r.collider_back = player.collision_layer == Layers.PLAYER
	await frames(tree, 30)
	r.on_floor = player.is_on_floor()
	for box in boxes:
		if is_instance_valid(box):
			box.queue_free()
	r.open_index = open_index
	return r


## Four people aboard: three other crew (claimed by stand-in peers 2..4) take the passenger seats; a request for a
## taken seat is refused; the seated crew are drawn at their seats; the rover carries their mass.
static func four_seats(tree: SceneTree, ctx: Dictionary) -> Dictionary:
	var services: GameServices = ctx.services
	var presenter: RoverPresenter = ctx.presenter
	var b: RoverBody = ctx.body
	var main: GameMain = ctx.main
	var session := services.session
	var st := services.state()
	var r := {}
	var mass_empty := b.total_mass()
	# the local player gets back into the driver's seat
	await look_at_rover(tree, ctx)
	await press(tree, &"interact")
	await frames(tree, 10)
	r.driver_back = (ctx.player as PlayerController).is_seated()
	var ids := []
	for peer in [2, 3, 4]:
		session.peer_joined(peer)
		for crew_id: StringName in st.characters:
			if st.characters[crew_id].owner_peer == 0:
				session.request(&"claim_character", crew_id, {}, peer)
				break
		var c := st.character_of_peer(peer)
		ids.append(String(c.id) if c != null else "")
		if c != null:
			c.suit_on = true          # outside at the rover: suited, as rover_enter requires
			session.report_position(peer, c.id, b.exit_world(1), 0.0)
	r.claimed = ids
	r.answers = []
	for i in 3:
		var res := session.request(&"rover_enter", &"", {"seat": i + 1}, i + 2)
		r.answers.append(res.ok)
	var taken := session.request(&"rover_enter", &"", {"seat": 0}, 2)
	r.taken_refused = not taken.ok
	r.taken_reason = String(taken.reason)
	await frames(tree, 15)
	main._rebuild_crew()
	await frames(tree, 5)
	r.seats = RoverPresenter.seats_of(st)
	r.choose_when_full = RoverPresenter.choose_seat(r.seats)
	r.mass_added_kg = b.total_mass() - mass_empty
	var visuals := presenter.seated_visuals()
	r.seated_visuals = visuals.size()
	var worst := 0.0
	var states_ok := true
	for i in range(1, 4):
		var id := String(r.seats[i])
		var v := visuals.get(id) as PlayerVisual
		if v == null:
			worst = INF
			continue
		worst = maxf(worst, v.global_position.distance_to(b.seat_anchor(i).global_position))
		states_ok = states_ok and v._state == &"seated"
		var walking := main._crew_visuals.get(StringName(id)) as Node3D
		states_ok = states_ok and walking != null and not walking.visible
	r.visual_seat_error_m = worst
	r.visual_states_ok = states_ok
	r.hud = presenter.hud_widget.panel_text()
	# riders get out again (host-validated exits), the driver last
	r.exit_answers = []
	for i in 3:
		var ans := session.request(&"rover_exit", &"", {"exit_index": 1 + i}, i + 2)
		r.exit_answers.append(String(ans.reason))
	await frames(tree, 10)
	r.visuals_after_exit = presenter.seated_visuals().size()
	r.seats_after_exit = RoverPresenter.seats_of(st)
	var shown := true
	for id in ids:
		var walking := main._crew_visuals.get(StringName(String(id))) as Node3D
		shown = shown and walking != null and walking.visible
	r.walking_shown_again = shown
	return r


# ---------------------------------------------------------------- map evidence (--inspect)

## Prints what data/rover.json was measured from: both rovers' bounds and tyres, the cabin's inside, the garage door.
static func inspect(tree: SceneTree) -> void:
	var world := (load("res://scenes/world/colony_world.tscn") as PackedScene).instantiate() as Node3D
	tree.root.add_child(world)
	await tree.process_frame
	for object_name: String in ["sf_rover", "hb_rover"]:
		var mi := world.find_child(object_name, true, false) as MeshInstance3D
		if mi == null:
			print("INSPECT %s: not found" % object_name)
			continue
		print("INSPECT %s at %s, mesh bounds %s (mesh frame), %d surfaces" % [object_name, mi.global_position, mi.mesh.get_aabb(), mi.mesh.get_surface_count()])
		for t: Dictionary in tyre_clusters(mi.mesh):
			print("INSPECT   tyre side %+d: centre (%.2f, %.2f, %.2f) radius %.3f width %.2f" % [t.side, t.centre.x, t.centre.y, t.centre.z, t.radius, t.width])
	var rover := world.find_child("sf_rover", true, false) as MeshInstance3D
	if rover != null:
		var body := StaticBody3D.new()
		tree.root.add_child(body)
		var cs := CollisionShape3D.new()
		var tri := rover.mesh.create_trimesh_shape() as ConcavePolygonShape3D
		tri.backface_collision = true
		cs.shape = tri
		body.add_child(cs)
		await tree.physics_frame
		await tree.physics_frame
		var space := body.get_world_3d().direct_space_state
		for z: float in [1.6, 0.8, 0.0, -0.8, -1.6]:
			var p := Vector3(0.0, 1.6, z)
			var line := "INSPECT   cabin probe (mesh frame) %s:" % p
			for pair: Array in [["floor", Vector3.DOWN], ["ceiling", Vector3.UP], ["left", Vector3.LEFT], ["right", Vector3.RIGHT], ["front", Vector3.BACK], ["rear", Vector3.FORWARD]]:
				var q := PhysicsRayQueryParameters3D.create(p, p + (pair[1] as Vector3) * 6.0)
				q.hit_back_faces = true
				var h := space.intersect_ray(q)
				line += " %s %s" % [pair[0], ("%.2f" % p.distance_to(h.position)) if not h.is_empty() else "-"]
			print(line)
		body.queue_free()
	var assets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/colliders.json"))["assets"]
	print("INSPECT sf_print_garage boxes (local): ", JSON.stringify(assets.get("sf_print_garage", {}).get("cols", [])))
	print("INSPECT sf_rover boxes (mesh frame): ", JSON.stringify(assets.get("sf_rover", {}).get("cols", [])))
	world.queue_free()


## Tyres of a mesh: vertices of its "rubber" surfaces split by side and by gaps along z. Each: side, centre, radius, width.
static func tyre_clusters(mesh: Mesh) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m == null or not m.resource_name.contains("rubber"):
			continue
		var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for side: int in [-1, 1]:
			var pts: Array[Vector3] = []
			for v in verts:
				if signf(v.x) == side:
					pts.append(v)
			pts.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z < b.z)
			var group: Array[Vector3] = []
			for i in pts.size():
				if not group.is_empty() and pts[i].z - group[-1].z > 0.15:
					out.append(_tyre(group, side))
					group = []
				group.append(pts[i])
			if not group.is_empty():
				out.append(_tyre(group, side))
	return out


static func _tyre(pts: Array[Vector3], side: int) -> Dictionary:
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	return {"side": side, "centre": box.get_center(), "radius": box.size.y * 0.5, "width": box.size.x}


# ---------------------------------------------------------------- helpers

## Turns the player's view toward the rover body's centre (look only), so aimed_target() sees it.
static func look_at_rover(tree: SceneTree, ctx: Dictionary) -> void:
	var player: PlayerController = ctx.player
	var b: RoverBody = ctx.body
	var rig := player.camera_rig()
	for i in 3:
		var eye := rig.camera().global_position
		var to := (b.global_position + Vector3.UP * 1.4) - eye
		var yaw := atan2(-to.x, -to.z)
		var pitch := atan2(to.y, Vector2(to.x, to.z).length())
		rig.add_look(yaw - rig.yaw(), pitch - rig.pitch())
		await frames(tree, 2)


static func press(tree: SceneTree, action: StringName) -> void:
	Input.action_press(action)
	await frames(tree, 3)
	Input.action_release(action)
	await frames(tree, 2)


static func set_inputs(throttle: float, steer: float, brake: bool) -> void:
	_axis(&"move_forward", &"move_back", throttle)
	_axis(&"move_right", &"move_left", steer)
	if brake:
		Input.action_press(&"jump")
	else:
		Input.action_release(&"jump")


static func _axis(positive: StringName, negative: StringName, value: float) -> void:
	if value > 0.001:
		Input.action_press(positive, minf(value, 1.0))
		Input.action_release(negative)
	elif value < -0.001:
		Input.action_press(negative, minf(-value, 1.0))
		Input.action_release(positive)
	else:
		Input.action_release(positive)
		Input.action_release(negative)


## Waits until n physics steps have run, then two drawn frames: with the run sped up, many physics steps can fall in
## one drawn frame, and the presenter syncs seats and visuals in _process.
static func frames(tree: SceneTree, n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await tree.physics_frame
	await tree.process_frame
	await tree.process_frame


static func _angle_to(b: RoverBody, target: Vector3) -> float:
	var fwd := flat(-b.global_basis.z).normalized()
	var to := flat(target - b.global_position).normalized()
	if fwd.length_squared() < 1e-6 or to.length_squared() < 1e-6:
		return 0.0
	return fwd.signed_angle_to(to, Vector3.UP)        # > 0: the target is to the left


static func _steer_to(b: RoverBody, target: Vector3) -> float:
	return clampf(-_angle_to(b, target) * 2.5, -1.0, 1.0)


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func tilt_deg(b: Node3D) -> float:
	return rad_to_deg(acos(clampf(b.global_basis.y.normalized().dot(Vector3.UP), -1.0, 1.0)))


static func odometer_start(b: Node3D) -> Vector3:
	return b.global_position


## Distance from `point` to the nearest collision box of the donor object (its surface; 0 inside).
static func donor_gap(main: GameMain, point: Vector3) -> float:
	var best := INF
	for cs in main.collision.find_children("*", "CollisionShape3D", true, false):
		if String(cs.get_meta("object_name", "")) != DONOR or not (cs as CollisionShape3D).shape is BoxShape3D:
			continue
		var half := ((cs as CollisionShape3D).shape as BoxShape3D).size * 0.5
		var local := (cs as Node3D).global_transform.affine_inverse() * point
		var clamped := local.clamp(-half, half)
		best = minf(best, local.distance_to(clamped))
	return best


static func object_position(object_name: String) -> Vector3:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/colony_manifest.json"))
	for o: Dictionary in manifest.objects:
		if String(o.name) == object_name:
			return WorldCollision.object_transform(o.matrix_world).origin
	return Vector3.ZERO


static func _merge(into: Dictionary, part: Dictionary) -> void:
	for k: String in ["distance_m", "time_s", "stuck", "flips"]:
		if part.has(k):
			into[k] = into.get(k, 0) + part[k]
	if part.has("min_y"):
		into.min_y = minf(float(into.get("min_y", INF)), float(part.min_y))
		into.max_y = maxf(float(into.get("max_y", -INF)), float(part.max_y))
	if part.has("max_tilt_deg"):
		into.max_tilt_deg = maxf(float(into.get("max_tilt_deg", 0.0)), float(part.max_tilt_deg))


## The driving table (TABLE lines), for the tool's output, the test log and NOTES.md.
static func print_table(r: Dictionary) -> void:
	if not bool(r.get("ok", false)):
		print("TABLE drive did not complete: ", r)
		return
	var s: Dictionary = r.stats
	print("TABLE physics %.0f Hz, Mars gravity %.2f m/s2; stats (RoverModel) top %.2f m/s, drive %.0f N, mu %.2f, mass %.0f kg (+%.0f kg crew aboard); accounting: %s" % [
		r.physics_hz, GameConfig.MARS_GRAVITY, s.top_speed_mps, s.drive_force_n, s.traction_mu, s.mass_kg, 160.0, r.accounting])
	print("TABLE settle      origin y %.3f m, %d/6 wheels down, tilt %.1f deg" % [r.settled.y, r.settled.wheels, r.settled.tilt_deg])
	var a: Dictionary = r.straight
	print("TABLE straight    0 -> %.2f m/s in %.2f s over %.1f m (left the garage at x %.1f)" % [r.stats.top_speed_mps * 0.9, a.t90, a.distance_m, a.exit_x])
	var c: Dictionary = r.cruise
	print("TABLE cruise      full throttle on the open straight: %.2f m/s over the last 10 m, peak %.2f m/s (top %.2f m/s)" % [c.mean_mps, c.v_max, c.top_speed])
	var b: Dictionary = r.brake
	print("TABLE braking     from %.2f m/s: %.2f m in %.2f s (friction limit %.2f m at mu %.2f)" % [b.v0, b.distance_m, b.time_s, b.ideal_m, b.mu])
	var t: Dictionary = r.turn
	print("TABLE tight turn  radius %.2f m at %.2f m/s, full lock (steering geometry %.2f m), %.0f deg in %.1f s" % [t.radius_m, t.speed_mps, t.geometric_m, t.yaw_deg, t.time_s])
	var g: Dictionary = r.cargo
	print("TABLE cargo       0 -> 2 m/s: %.2f s at %.0f kg, %.2f s with 800 kg more (%.0f kg)" % [g.light_s, g.mass_kg, g.heavy_s, g.heavy_mass_kg])
	var e: Dictionary = r.empty_battery
	print("TABLE no battery  full throttle 3 s: moved %.3f m, speed %.3f m/s" % [e.moved_m, e.speed])
	var o: Dictionary = r.route
	print("TABLE long route  garage -> %s (front %.1f m from its centre, %.1f m from its side) -> dunes -> rocks -> garage: %.1f m in %.1f s, energy %.4f kWh (charged %.4f, counted %.1f m), height %.2f..%.2f m, stuck %d, flips %d, back in garage: %s" % [
		DONOR, o.at_donor_m, o.donor_gap_m, o.distance_m, o.time_s, o.energy_kwh, o.charged_kwh, o.counted_m, o.min_y, o.max_y, o.stuck, o.flips, o.in_garage])
	var h: Dictionary = r.rough
	print("TABLE rough       dunes and rock field: %.1f m, height %.2f..%.2f m, max tilt %.1f deg, wheel contact %.1f %%, stuck %d, flips %d" % [h.distance_m, h.min_y, h.max_y, h.max_tilt_deg, h.contact_share * 100.0, h.stuck, h.flips])
	var x: Dictionary = r.exits
	print("TABLE exits       clear when parked %s; all boxed -> first clear %d, still seated %s; box %d removed -> first clear %d, out %s (%.2f m from the exit) %s" % [
		str(x.clear_before), x.first_clear_all_boxed, x.still_seated_when_boxed, x.open_index, x.first_clear_one_open, x.out_after_clear, x.exit_error_m, str(x.message_after_clear)])
	var q: Dictionary = r.seats
	print("TABLE four seats  %s, taken seat refused %s (%s), seated bodies %d at seats (worst %.3f m), crew mass +%.0f kg" % [
		str(q.seats), q.taken_refused, q.taken_reason, q.seated_visuals, q.visual_seat_error_m, q.mass_added_kg])
