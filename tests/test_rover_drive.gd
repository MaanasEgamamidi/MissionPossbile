extends SceneTree
## Prompt 10, worker P10B: the drivable rover. Headless; every PASS is measured on the running code.
##   1. pure checks: data/rover.json against the map, seat choice, pose conversions, energy-accounting lookup
##   2. the drive (tools/godot/rover_drive_check.gd run()): the real game scene WITH the map and its full collision,
##      the rover boarded with E and driven only by scripted key presses at 60 Hz physics: straight run, cruise,
##      braking, tight turn, cargo mass, empty battery, a long route garage -> salvage donor -> dunes -> rock field ->
##      back into the garage, blocked exits, four seats
##   3. network: two game scenes (no map) in one process, the client in its own physics world (a SubViewport, so the
##      two rover bodies never touch), over ENet on 127.0.0.1:
##      the client drives, the host follows and stores the pose, spoofed poses are refused, the driver's seat is freed
##      and the host brakes the rover where it is
## STAND-IN UNTIL P10A MERGES: rover_enter / rover_exit below (install_stand_ins) are minimal test-only definitions
## with the fixed ids and params. They are registered only when the session has no definition of that id, so once
## worker P10A's RoverActions are in, these checks run against the real host actions.
## Run: godot --headless --path . --script res://tests/test_rover_drive.gd [-- --net-only]

const DriveCheck := preload("res://tools/godot/rover_drive_check.gd")
const PORT := 24793


## Collects engine and script errors raised while the test runs.
class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR or error_type == ERROR_TYPE_SCRIPT:
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _passed := 0
var _total := 0
var _catcher := ErrorCatcher.new()


func _check(test_name: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS %s%s" % [test_name, ("  " + detail) if detail != "" else ""])
	else:
		print("FAIL %s: %s" % [test_name, detail])


func _initialize() -> void:
	OS.add_logger(_catcher)
	_run.call_deferred()


func _run() -> void:
	PlayerInput.ensure_actions()
	_pure_checks()
	if not OS.get_cmdline_user_args().has("--net-only"):
		await _drive_checks()
	await _network_checks()
	_check("clean run: the engine error log stayed empty", _catcher.errors.is_empty(), "\n".join(_catcher.errors.slice(0, 10)))
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


# ---------------------------------------------------------------- stand-ins (test only)

## STAND-IN UNTIL P10A MERGES. Minimal host actions with the fixed ids and params (SPEC "Fixed ids"):
##   rover_enter {"seat": 0..3}: a built rover, a free seat, the actor not seated already and within
##                               data/rover.json enter_distance_m of the pose; puts the actor's id in that seat
##   rover_exit {"exit_index": i}: the actor is seated, i is an exit of data/rover.json; frees the seat and puts the
##                               actor at pose + quat x exit offset
## Returns the ids it registered (none when the session already has them).
static func install_stand_ins(session: SessionService) -> PackedStringArray:
	var added := PackedStringArray()
	var data := RoverBody.load_data()
	var exits: Array = data.get("exits", [])
	if session.actions.definition(&"rover_enter") == null:
		var d := ActionService.Definition.new()
		d.id = &"rover_enter"
		d.check_distance = false
		d.params = {"seat": {"type": TYPE_INT, "min": 0, "max": RoverModel.SEATS - 1}}
		d.check = func(ctx: ActionService.Context) -> ActionResult:
			RoverModel.ensure(ctx.state)
			var seats: Array = ctx.state.rover.seats
			var reason: StringName = &""
			var pose := RoverBody.from_state_pose(ctx.state.rover.get("pose", {}))
			if not bool(ctx.state.rover.get("built", false)):
				reason = &"missing_prerequisite"
			elif String(seats[int(ctx.request.params.seat)]) != "" or seats.has(String(ctx.actor.id)):
				reason = &"already_held"
			elif pose.is_empty() or ctx.actor.position.distance_to(pose.p as Vector3) > float(data.get("enter_distance_m", 6.0)):
				reason = &"too_far"
			return null if reason == &"" else ActionResult.failure(ctx.request.request_id, reason)
		d.apply = func(ctx: ActionService.Context) -> Dictionary:
			ctx.state.rover.seats[int(ctx.request.params.seat)] = String(ctx.actor.id)
			return {"seat": int(ctx.request.params.seat)}
		session.actions.register(d)
		added.append("rover_enter")
	if session.actions.definition(&"rover_exit") == null:
		var d := ActionService.Definition.new()
		d.id = &"rover_exit"
		d.check_distance = false
		d.params = {"exit_index": {"type": TYPE_INT, "min": 0, "max": maxi(0, exits.size() - 1)}}
		d.check = func(ctx: ActionService.Context) -> ActionResult:
			RoverModel.ensure(ctx.state)
			if not (ctx.state.rover.seats as Array).has(String(ctx.actor.id)):
				return ActionResult.failure(ctx.request.request_id, &"missing_prerequisite")
			return null
		d.apply = func(ctx: ActionService.Context) -> Dictionary:
			var seats: Array = ctx.state.rover.seats
			seats[seats.find(String(ctx.actor.id))] = ""
			var pose := RoverBody.from_state_pose(ctx.state.rover.get("pose", {}))
			if not pose.is_empty():
				var offset := RoverBody._v3((exits[int(ctx.request.params.exit_index)] as Dictionary).position)
				ctx.actor.position = (pose.p as Vector3) + (pose.q as Quaternion) * offset
			return {"exit_index": int(ctx.request.params.exit_index)}
		session.actions.register(d)
		added.append("rover_exit")
	return added


# ---------------------------------------------------------------- 1. pure checks

func _pure_checks() -> void:
	var data := RoverBody.load_data()
	_check("rover.json names the map rover and its garage", String(data.get("object", "")) == "sf_rover" and String(data.get("garage_object", "")) == "sf_print_garage")
	_check("six wheels, four seats, at least four exits", (data.wheels as Array).size() == 6 and (data.seats as Array).size() == RoverModel.SEATS and (data.exits as Array).size() >= 4)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/colony_manifest.json"))
	var rover_obj := {}
	for o: Dictionary in manifest.objects:
		if String(o.name) == "sf_rover":
			rover_obj = o
	var map_xf := WorldCollision.object_transform(rover_obj.matrix_world)
	var park := RoverBody.from_state_pose(data.garage_park_pose)
	var park_xf := Transform3D(Basis(park.q as Quaternion), park.p as Vector3)
	var mesh_xf := park_xf * Transform3D(Basis(Vector3.UP, deg_to_rad(float(data.mesh_yaw_deg))), Vector3.ZERO)
	_check("garage park pose is the map placement turned to face -Z forward", mesh_xf.origin.distance_to(map_xf.origin) < 1e-4 and mesh_xf.basis.is_equal_approx(map_xf.basis),
		"%s vs %s" % [mesh_xf, map_xf])
	_check("parked rover faces out of the garage door (world +x)", (-park_xf.basis.z).distance_to(Vector3(1, 0, 0)) < 1e-4)
	var cab: Dictionary = data.cabin
	var seats_inside := true
	for s: Dictionary in data.seats:
		var p := RoverBody._v3(s.position)
		seats_inside = seats_inside and absf(p.x) + 0.55 <= float(cab.half_width) + 0.05 and p.z - 0.45 > float(cab.front_z) and p.z + 0.35 < float(cab.rear_z) \
			and is_equal_approx(p.y, float(cab.floor_y)) and p.y + float(data.seat_eye_height_m) + 0.25 < float(cab.ceiling_y)
	_check("every seat fits in the measured cabin (feet, head and backpack clear)", seats_inside)
	_check("choose_seat: driver first, then the first free passenger seat, -1 when full",
		RoverPresenter.choose_seat(["", "", "", ""]) == 0 and RoverPresenter.choose_seat(["a", "", "", ""]) == 1 and RoverPresenter.choose_seat(["a", "b", "", "d"]) == 2
		and RoverPresenter.choose_seat(["a", "b", "c", "d"]) == -1)
	var pose := {"p": Vector3(1.5, 0.2, -3.0), "q": Quaternion(Vector3.UP, 0.7), "lv": Vector3.ZERO, "av": Vector3.ZERO}
	var back := RoverBody.from_state_pose(JSON.parse_string(JSON.stringify(RoverBody.to_state_pose(pose))))
	_check("pose survives the JSON save form", (back.p as Vector3).distance_to(pose.p) < 1e-5 and (back.q as Quaternion).is_equal_approx(pose.q))
	_check("malformed poses are refused", RoverBody.from_state_pose({"position": [0, 0], "quat": [0, 0, 0, 1]}).is_empty()
		and not RoverBody.pose_valid({"p": Vector3(INF, 0, 0), "q": Quaternion.IDENTITY}) and not RoverBody.pose_valid({"p": Vector3.ZERO, "q": Quaternion(0, 0, 0, 2)})
		and not RoverBody.pose_valid({"p": Vector3.ZERO, "q": Quaternion.IDENTITY, "lv": Vector3(500, 0, 0)}))
	# energy accounting lookup: a runtime script with a static note_driven is found and called
	var fake := GDScript.new()
	fake.source_code = "extends RefCounted\nstatic func note_driven(state, events, d: float, c: float) -> float:\n\treturn d * 0.5 + c * 10.0\n"
	fake.reload()
	var call := RoverPresenter.accounting_from_script(fake, null)
	var kwh := float(call.call(null, null, 4.0, 1.0)) if call.is_valid() else -1.0
	_check("RoverSystem.note_driven is found at run time (static) and called with distance and climb", call.is_valid() and is_equal_approx(kwh, 12.0), "%.2f" % kwh)
	var inst := GDScript.new()
	inst.source_code = "extends RefCounted\nvar total := 0.0\nfunc step(_s, _b, _p, _d, _e) -> void:\n\tpass\nfunc note_driven(state, events, d: float, c: float) -> float:\n\ttotal += d\n\treturn 0.25\n"
	inst.reload()
	var services := GameServices.new()
	var system: Object = inst.new()
	services.session.sim.post_systems.append(system)
	var call2 := RoverPresenter.accounting_from_script(inst, services.session)
	_check("... or as a method of the RoverSystem in the simulation's post_systems", call2.is_valid() and is_equal_approx(float(call2.call(null, null, 3.0, 0.0)), 0.25) and is_equal_approx(float(system.get("total")), 3.0))
	services.session.sim.post_systems.erase(system)
	var st := ColonyState.new()
	RoverModel.ensure(st)
	st.rover.battery_kwh = 1.0
	var used := RoverPresenter.fallback_note_driven(st, null, 10.0, 0.0)
	var expect := RoverModel.energy_kwh_for_move(st.rover.levels, 0.0, 10.0, 0.0)
	_check("fallback charge takes RoverModel.energy_kwh_for_move from the rover battery", is_equal_approx(used, expect) and is_equal_approx(float(st.rover.battery_kwh), 1.0 - expect), "%.5f kWh" % used)
	st.rover.battery_kwh = 0.0001
	var used2 := RoverPresenter.fallback_note_driven(st, null, 1000.0, 0.0)
	_check("fallback never takes more than is stored", is_equal_approx(used2, 0.0001) and float(st.rover.battery_kwh) == 0.0)
	services.free()


# ---------------------------------------------------------------- 2. the drive

func _drive_checks() -> void:
	var t0 := Time.get_ticks_msec()
	var r: Dictionary = await DriveCheck.run(self, func(s: GameServices) -> void: print("INFO stand-ins registered: ", install_stand_ins(s.session)))
	DriveCheck.print_table(r)
	print("INFO drive took %.1f s of real time" % ((Time.get_ticks_msec() - t0) / 1000.0))
	_check("drive completed", bool(r.get("ok", false)), str(r.keys()))
	if not bool(r.get("ok", false)):
		return
	var ctx: Dictionary = r.ctx
	var stats: Dictionary = r.stats
	var top := float(stats.top_speed_mps)
	var g := GameConfig.MARS_GRAVITY
	var mu := float(stats.traction_mu)
	_check("map rover found, its static boxes switched off, its lamps moved onto the body", bool(r.setup.mesh_found) and int(r.setup.static_shapes_off) >= 3 and int(r.setup.lights_moved) >= 6, str(r.setup))
	_check("physics at 60 Hz", is_equal_approx(float(r.physics_hz), 60.0))
	_check("settles on six wheels, level, at rest in the garage", int(r.settled.wheels) == 6 and float(r.settled.tilt_deg) < 3.0 and float(r.settled.speed) < 0.05, str(r.settled))
	_check("cue under the crosshair offers the driver's seat", String(r.cue_before).contains("driver"), String(r.cue_before))
	_check("E boards the driver's seat (host action), the body stops colliding", bool(r.boarded) and (ctx.player as PlayerController).collision_layer == 0)
	_check("seated eye at the seat's head height", absf(float(r.eye_above_floor) - 1.29) < 0.05, "%.2f m" % r.eye_above_floor)
	_check("HUD shows speed, battery, range, cargo, seats and the keys", String(r.hud_text).contains("km/h") and String(r.hud_text).contains("kWh") and String(r.hud_text).contains("Range")
		and String(r.hud_text).contains("Cargo") and String(r.hud_text).contains("Driver:") and String(r.hud_text).contains("brake"), String(r.hud_text))
	# straight: the force law is a = F/m - rolling; 90 % of top speed can be reached no sooner than (0.9 v)/(F/m) and,
	# with the fade over the last 15 % of top speed and rolling resistance, well within 2.5 times that
	var a_max := float(stats.drive_force_n) / (float(stats.mass_kg) + 160.0)
	var t_ideal := 0.9 * top / a_max
	_check("straight run reaches 90 % of top speed in a time the drive force allows", float(r.straight.t90) > 0.95 * t_ideal and float(r.straight.t90) < 2.5 * t_ideal,
		"%.2f s (ideal %.2f s)" % [r.straight.t90, t_ideal])
	_check("drives out of the garage (its rear past the door at x 11.5)", float(r.straight.exit_x) - 3.1 > 11.5, "x %.1f" % r.straight.exit_x)
	_check("cruise holds top speed and never exceeds it by more than 5 %", float(r.cruise.mean_mps) > 0.9 * top and float(r.cruise.v_max) < 1.05 * top, "%.2f m/s, peak %.2f" % [r.cruise.mean_mps, r.cruise.v_max])
	# braking: tyre friction limits the deceleration to mu g, so the distance is at least v0^2 / (2 mu g) (10 % margin
	# for the speed read one step early) and the brake uses most of it (within 1.6 times the limit)
	var b: Dictionary = r.brake
	_check("braking distance is friction-limited under Mars gravity", float(b.distance_m) > 0.9 * float(b.ideal_m) and float(b.distance_m) < 1.6 * float(b.ideal_m) + 0.3,
		"%.2f m from %.2f m/s (limit %.2f m)" % [b.distance_m, b.v0, b.ideal_m])
	# tight turn: full lock gives 1.55 m / tan(30 deg) = 2.7 m; at 1.5 m/s the needed side force (v^2/R = 0.8 m/s2) is
	# well inside mu g (2.2 m/s2), so the path should be close to the geometry: between 0.8 and 1.6 times it
	var t: Dictionary = r.turn
	_check("tight turn radius close to the steering geometry", float(t.radius_m) > 0.8 * float(t.geometric_m) and float(t.radius_m) < 1.6 * float(t.geometric_m),
		"%.2f m (geometry %.2f m) at %.2f m/s" % [t.radius_m, t.geometric_m, t.speed_mps])
	var c: Dictionary = r.cargo
	var mass_ratio := float(c.heavy_mass_kg) / float(c.mass_kg)
	_check("800 kg of cargo slows acceleration about in proportion to mass", float(c.heavy_s) > float(c.light_s) * (1.0 + 0.7 * (mass_ratio - 1.0)),
		"%.2f s -> %.2f s (mass x %.2f)" % [c.light_s, c.heavy_s, mass_ratio])
	_check("empty battery: full throttle does not move the rover", float(r.empty_battery.moved_m) < 0.05 and float(r.empty_battery.speed) < 0.05, str(r.empty_battery))
	_check("empty battery is shown on the HUD", String(r.empty_battery.hud).contains("Battery empty"))
	var o: Dictionary = r.route
	_check("long route: stopped beside the salvage donor (front within 4 m of it)", float(o.donor_gap_m) < 4.0, "%.1f m from its side, %.1f m from its centre" % [o.donor_gap_m, o.at_donor_m])
	_check("long route: drove back into the garage", bool(o.in_garage), str(o.end))
	_check("long route: never stuck, never flipped", int(o.stuck) == 0 and int(o.flips) == 0, "stuck %d flips %d" % [o.stuck, o.flips])
	_check("long route is long (over 150 m)", float(o.distance_m) > 150.0, "%.1f m" % o.distance_m)
	_check("host counted the driven distance (within 5 %)", absf(float(o.counted_m) - float(o.distance_m)) < 0.05 * float(o.distance_m), "%.1f of %.1f m" % [o.counted_m, o.distance_m])
	_check("driving energy charged equals the battery drop", float(o.charged_kwh) > 0.0 and absf(float(o.charged_kwh) - float(o.energy_kwh)) < 1e-6, "%.5f kWh, accounting %s" % [o.charged_kwh, r.accounting])
	_check("driving energy goes through the host's RoverSystem.note_driven (ledger, trip, odometer, empty-battery alert)", String(r.accounting) == "RoverSystem.note_driven", String(r.accounting))
	_check("saved pose follows the live body", float(o.state_pose_error_m) < 0.2, "%.3f m" % o.state_pose_error_m)
	var h: Dictionary = r.rough
	_check("rough ground: climbed the dune (over 2.5 m up)", float(h.max_y) > 2.5, "max height %.2f m" % h.max_y)
	_check("rough ground: no flip, tilt under 30 degrees", int(h.flips) == 0 and float(h.max_tilt_deg) < 30.0, "%.1f deg" % h.max_tilt_deg)
	_check("rough ground: wheels on the ground at least 90 % of the time", float(h.contact_share) >= 0.9, "%.1f %%" % (float(h.contact_share) * 100.0))
	var x: Dictionary = r.exits
	_check("parked in the garage at least one exit is clear", (x.clear_before as Array).has(true), str(x.clear_before))
	_check("every exit boxed in: getting out is refused, still seated, and the HUD says why", int(x.first_clear_all_boxed) == -1 and bool(x.still_seated_when_boxed)
		and " ".join(x.message_when_boxed).contains("blocked"), str(x.message_when_boxed))
	_check("one exit cleared: out through that exit, standing, colliding again", int(x.first_clear_one_open) == int(x.open_index) and bool(x.out_after_clear) and float(x.exit_error_m) < 0.3
		and bool(x.standing_upright) and bool(x.collider_back), "%.2f m" % x.exit_error_m)
	_check("standing on the ground after getting out", bool(x.on_floor))
	var q: Dictionary = r.seats
	_check("four crew aboard: driver and three passengers", bool(q.driver_back) and (q.answers as Array) == [true, true, true] and not (q.seats as Array).has(""), str(q.seats))
	_check("a taken seat is refused and no fifth seat exists", bool(q.taken_refused) and int(q.choose_when_full) == -1)
	_check("the rover carries the crew's mass", is_equal_approx(float(q.mass_added_kg), 4.0 * 160.0) or is_equal_approx(float(q.mass_added_kg), 3.0 * 160.0), "+%.0f kg" % q.mass_added_kg)
	_check("other crew are drawn seated at their seats; their walking copies are hidden", int(q.seated_visuals) == 3 and float(q.visual_seat_error_m) < 0.01 and bool(q.visual_states_ok))
	_check("riders out again: seated copies gone, walking copies back", int(q.visuals_after_exit) == 0 and bool(q.walking_shown_again), "%s, %d left, seats %s" % [str(q.exit_answers), q.visuals_after_exit, str(q.seats_after_exit)])
	(ctx.main as Node).queue_free()
	await process_frame
	await process_frame


# ---------------------------------------------------------------- 3. network

func _machine(branch: String, save_dir: String, own_world: bool) -> GameMain:
	var holder: Node
	if own_world:
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.size = Vector2i(64, 64)
		holder = vp
	else:
		holder = Node.new()
	holder.name = branch
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + branch))
	var main := (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.load_world = false
	main.show_menu = true
	main.save_directory = save_dir
	holder.add_child(main)
	return main


func _until(cond: Callable, seconds := 5.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return bool(cond.call())


func _network_checks() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/rover_net")
	DirAccess.make_dir_recursive_absolute(dir)
	var host := _machine("RoverHost", dir.path_join("host"), false)
	var client := _machine("RoverClient", dir.path_join("client"), true)
	host.services.saves.delete_all()
	await _until(func() -> bool: return false, 0.3)
	host._on_menu_host(PORT, false)
	client._on_menu_join("127.0.0.1", PORT)
	var joined := await _until(func() -> bool: return client._playing and client.player != null, 8.0)
	_check("client joined the host", joined)
	if not joined:
		return
	install_stand_ins(host.services.session)
	# Each game scene builds its own rover presenter (GameMain.rover); the test uses those.
	var hp: RoverPresenter = host.rover
	var cp: RoverPresenter = client.rover
	_check("host and client game scenes each built their rover", hp != null and cp != null)
	if hp == null or cp == null:
		return
	var hst := host.services.state()
	hst.rover["built"] = true
	hst.rover["battery_kwh"] = 10.0
	await _until(func() -> bool: return bool(client.services.state().rover.get("built", false)), 3.0)
	_check("host provides the rover pose with the body positions", host.services.net.motion_extras_provider.is_valid() and hp.motion_extras().has("rover"))
	# the client walks to the rover's left side, looks at it and presses E
	await _until(func() -> bool: return false, 1.0)
	var start: Vector3 = cp.body.global_position
	_check("client shows the rover where the host has it", start.distance_to(hp.body.global_position) < 0.2, "%.3f m" % start.distance_to(hp.body.global_position))
	client.player.teleport((cp.exit_ground(1) as Vector3) + Vector3.UP * 0.05, 0.0)
	var cid := client.services.local_character().id
	# The garage is outside: the client's crew member is suited (on the host, which owns the state), as rover_enter requires.
	hst.character(cid).suit_on = true
	# NetSession sends a body position only when it changes; one lost unreliable packet leaves the host with an old
	# position while the player stands still (seen here: 15 s without an update after a teleport). Turning the view a
	# little sends a fresh one, as any real player does. Reported in NOTES.md.
	var reported := false
	for i in 20:
		client.player.camera_rig().add_look(0.01 if i % 2 == 0 else -0.01, 0.0)
		if await _until(func() -> bool: return host.services.state().character(cid).position.distance_to(client.player.global_position) < 0.5, 0.3):
			reported = true
			break
	_check("host has the client's body beside the rover", reported)
	var cctx := {"player": client.player, "body": cp.body}
	await DriveCheck.look_at_rover(self, cctx)
	await DriveCheck.press(self, &"interact")
	print("INFO client after E: messages %s, host seats %s" % [client.hud.current_messages(), hst.rover.seats])
	var seated := await _until(func() -> bool: return client.player.is_seated(), 4.0)
	var cme := client.services.local_character()
	_check("client boards the driver's seat through the host", seated and String(hst.rover.seats[0]) == String(cme.id))
	await _until(func() -> bool: return false, 0.3)
	_check("roles: client drives, host follows (kinematic copy)", cp.role == RoverPresenter.Role.DRIVE and hp.role == RoverPresenter.Role.FOLLOW and hp.body.freeze and not cp.body.freeze)
	# drive forward for 3 s (only the client's rover reacts: the host's standing player walks, which is harmless)
	var accepted0 := hp.poses_accepted
	DriveCheck.set_inputs(1.0, 0.0, false)
	await _until(func() -> bool: return false, 3.0)
	DriveCheck.set_inputs(0.0, 0.0, true)
	await _until(func() -> bool: return cp.body.linear_velocity.length() < 0.05, 6.0)
	await _until(func() -> bool: return false, 0.6)
	DriveCheck.set_inputs(0.0, 0.0, false)
	var moved := DriveCheck.flat(cp.body.global_position - start).length()
	var saved := RoverBody.from_state_pose(hst.rover.pose)
	var gap := (saved.p as Vector3).distance_to(cp.body.global_position) if not saved.is_empty() else INF
	_check("client drove the rover out", moved > 3.0, "%.1f m" % moved)
	_check("host accepted the driver's poses (~20 Hz) and none were refused", hp.poses_accepted - accepted0 > 40 and hp.poses_refused == 0, "%d accepted, %d refused" % [hp.poses_accepted - accepted0, hp.poses_refused])
	_check("host's saved pose and kinematic copy match the driver's body", gap < 0.15 and hp.body.global_position.distance_to(cp.body.global_position) < 0.15, "%.3f m / %.3f m" % [gap, hp.body.global_position.distance_to(cp.body.global_position)])
	hp.flush_accounting()
	_check("host charged the client's driving to the rover battery", hp.energy_charged_kwh > 0.0 and float(hst.rover.battery_kwh) < 10.0 and absf(hp.distance_counted_m - moved) < 0.5,
		"%.5f kWh for %.2f m" % [hp.energy_charged_kwh, hp.distance_counted_m])
	# spoofed poses: from a peer that is not the driver, and a 50 m jump from the driver
	var refused0 := hp.poses_refused
	var far := cp.body.live_pose()
	far.p = (far.p as Vector3) + Vector3(50, 0, 0)
	hp._on_motion_extra(1, "rover", cp.body.live_pose())
	hp._on_motion_extra(77, "rover", cp.body.live_pose())
	hp._on_motion_extra(cme.owner_peer, "rover", far)
	hp._on_motion_extra(cme.owner_peer, "rover", {"p": "nonsense"})
	_check("poses from a non-driver, an impossible jump or garbage are refused", hp.poses_refused - refused0 == 4 and (RoverBody.from_state_pose(hst.rover.pose).p as Vector3).distance_to(cp.body.global_position) < 0.15)
	# driver gone (what P10A's peer_left does: frees seat 0): the host brakes the rover where it is
	var before: Vector3 = hp.body.global_position
	hst.rover.seats[0] = ""
	var parked := await _until(func() -> bool: return hp.role == RoverPresenter.Role.PARK and not hp.body.freeze, 2.0)
	await _until(func() -> bool: return false, 2.0)
	_check("driver's seat freed: host simulates the parked rover with the brake on", parked and hp.body.linear_velocity.length() < 0.05 and hp.body.global_position.distance_to(before) < 0.3,
		"moved %.2f m" % hp.body.global_position.distance_to(before))
	var stood := await _until(func() -> bool: return not client.player.is_seated(), 3.0)
	_check("client's character stands again when its seat is freed", stood and client.player.collision_layer == Layers.PLAYER)
	await _until(func() -> bool: return cp.body.global_position.distance_to(hp.body.global_position) < 0.1, 3.0)
	_check("client now follows the host's parked rover", cp.role == RoverPresenter.Role.FOLLOW and cp.body.freeze and cp.body.global_position.distance_to(hp.body.global_position) < 0.1)
	client.services.net.leave()
	host.services.net.leave()
	await _until(func() -> bool: return false, 0.3)
	host.get_parent().queue_free()
	client.get_parent().queue_free()
	await process_frame
