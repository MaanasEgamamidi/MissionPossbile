class_name RoverPresenter
extends Node
## Scene side of the shared four-seat rover (Prompt 10). GameMain adds it in _begin_play():
##     var rover := RoverPresenter.new(); rover.name = "Rover"; add_child(rover); rover.setup(world, services, self)
##
## It builds the drivable RoverBody from the map's rover object (data/rover.json "object", sf_rover): the map's mesh is
## hidden and a copy is drawn inside the body, the object's static collision boxes are switched off, and the rover's
## own fixture lights ride along. It never changes the colony itself except the two things the vehicle owns on the
## host: state.rover.pose (the live pose, for saves and late joiners) and the driving energy, charged through
## RoverSystem.note_driven (worker P10A) when that exists, else through RoverModel.energy_kwh_for_move.
##
## Who simulates (role, every physics frame):
##   DRIVE   this machine's character sits in seat 0: WASD steer and accelerate, Space brakes; the pose goes to the host
##           ~20 Hz (net.send_motion_extra("rover", pose)) or, on the host, straight into the broadcast and the state
##   PARK    host, nobody drives (or the driver left): the host simulates the parked body with the brake held, so it
##           settles and stops where it is; the pose stays authoritative
##   FOLLOW  everyone else: a kinematic copy eased toward the newest pose (motion extras ~20 Hz; state.rover.pose at
##           load or join). The 5 Hz state replication never moves the body while extras arrive.
## Seats come from state.rover.seats (host-validated rover_enter / rover_exit, worker P10A). E on the rover (the
## player's aimed_target() sees it as kind "vehicle") asks for the driver's seat if free, else the first free
## passenger seat; E while seated asks to get out by the first clear exit. Seated crew of other players are drawn
## at their seats with the rig's seated pose; the local player's own body sits in its seat (PlayerController.sit).

const POSE_KEY := "rover"
const ROVER_SYSTEM_PATH := "res://scripts/sim/rover_system.gd"
## Third-person chase distance behind the head while seated (metres; the rover is 5.7 m long).
const CHASE_LENGTH_M := 7.5
## state.rover.pose is rewritten at most this often on the host (Hz).
const STATE_POSE_HZ := 10.0
## Driving energy is charged on the host about once a second of driving.
const CHARGE_EVERY_S := 1.0
## Moves smaller than this between two poses are settling, not driving (metres).
const MIN_STEP_M := 0.02
## A driver's pose may land this far (plus speed x time) from the last one before the host refuses it.
const POSE_JUMP_M := 2.0
## Getting out is refused above this speed (m/s): stop first.
const EXIT_MAX_SPEED := 0.8
## Standing capsule used to check an exit (PlayerTuning body: 0.22 m radius, 1.8 m tall).
const EXIT_RADIUS_M := 0.22
const EXIT_HEIGHT_M := 1.8
## An exit is refused if the ground there is further than this above or below the exit point (a crate, a ledge).
const EXIT_STEP_M := 0.8

enum Role { DRIVE, PARK, FOLLOW }

var services: GameServices
var game: Node
var world: Node3D
var body: RoverBody
var hud_widget: RoverHud
var data: Dictionary = {}
## Host: charges driving energy. Callable(state, events, distance_m, climb_m) -> float (kWh used).
var note_driven: Callable = Callable()
## Which accounting is in use: "RoverSystem.note_driven" or "fallback: RoverModel.energy_kwh_for_move".
var accounting := ""
var role: int = Role.PARK
## What setup found (for NOTES and tests): map object found, static shapes switched off, lights moved.
var setup_report := {}
## Host counters: poses accepted / refused from drivers, energy charged and distance counted (this session).
var poses_accepted := 0
var poses_refused := 0
var energy_charged_kwh := 0.0
var distance_counted_m := 0.0

var _player: PlayerController
var _send_left := 0.0
var _state_pose_left := 0.0
var _stats_left := 0.0
var _stats := {}
var _now_stats := {}                # RoverModel.current_stats: real battery, fuel cell, crew and cargo (for the HUD)
var _cargo_kg := 0.0
var _live_pose := {}
var _last_accept_ms := 0
var _acc_last := Vector3.INF
var _acc_start_y := 0.0
var _acc_distance := 0.0
var _acc_left := CHARGE_EVERY_S
var _exit_requested := -1
var _pending := {}                  # request id -> "enter" / "exit"
var _seated_visuals := {}           # character id (String) -> PlayerVisual drawn in a seat
var _mesh_layers := 1
var _last_extras_ms := -100000


## Builds the body, the HUD widget and the network hooks. `world` may be null (tests without the map): the body then
## has collision only.
func setup(p_world: Node3D, p_services: GameServices, p_game: Node) -> void:
	world = p_world
	services = p_services
	game = p_game
	data = RoverBody.load_data()
	body = RoverBody.new()
	body.name = "RoverBody"
	body.configure(data)
	add_child(body)
	var object_name := String(data.get("object", "sf_rover"))
	var park := RoverBody.from_state_pose(data.get("garage_park_pose", {}))
	setup_report = {"object": object_name, "mesh_found": false, "static_shapes_off": 0, "lights_moved": 0}
	if world != null:
		var src := world.find_child(object_name, true, false) as Node3D
		if src != null:
			setup_report.mesh_found = true
			var park_xf := Transform3D(Basis(park.q as Quaternion), park.p as Vector3) if not park.is_empty() else src.global_transform
			var copy := src.duplicate() as Node3D
			copy.visible = true
			body.set_visual(copy)
			src.visible = false
			if src is GeometryInstance3D:
				_mesh_layers = (src as VisualInstance3D).layers
			# the rover's own lamps (FX_sf_rover*) move with it, placed relative to the map placement
			for light in world.find_children("FX_" + object_name + "*", "Light3D", true, false):
				var l := light as Light3D
				var rel := park_xf.affine_inverse() * l.global_transform
				l.get_parent().remove_child(l)
				body.add_child(l)
				l.transform = rel
				setup_report.lights_moved += 1
	var collision := game.get("collision") as Node if game != null else null
	setup_report.garage_triangles_dropped = 0
	if collision != null:
		var garage := String(data.get("garage_object", ""))
		var clear: Dictionary = data.get("garage_clear_box", {})
		for shape in collision.find_children("*", "CollisionShape3D", true, false):
			if not shape.has_meta("object_name"):
				continue
			var owner_name := String(shape.get_meta("object_name"))
			if owner_name == object_name:
				(shape as CollisionShape3D).disabled = true
				setup_report.static_shapes_off += 1
			elif owner_name == garage and not clear.is_empty() and not park.is_empty() and (shape as CollisionShape3D).shape is ConcavePolygonShape3D:
				setup_report.garage_triangles_dropped += _clear_parking(shape as CollisionShape3D, park, clear)
	var st := services.state() if services.has_game() else null
	if st != null and services.is_authority():
		RoverModel.ensure(st)
	var saved := RoverBody.from_state_pose(st.rover.get("pose", {}) if st != null else {})
	body.place(RoverBody.to_state_pose(saved) if not saved.is_empty() else data.get("garage_park_pose", {}), 0.05)
	_live_pose = body.live_pose()
	_acc_last = body.global_position
	_acc_start_y = _acc_last.y

	var hud := game.get("hud") as Node if game != null else null
	hud_widget = RoverHud.new()
	if hud != null:
		hud.add_child(hud_widget)
	else:
		add_child(hud_widget)

	var net := services.net
	if net != null:
		if not net.motion_extra_received.is_connected(_on_motion_extra):
			net.motion_extra_received.connect(_on_motion_extra)
		if not net.motion_extras_received.is_connected(_on_motion_extras):
			net.motion_extras_received.connect(_on_motion_extras)
		net.motion_extras_provider = motion_extras
	services.events.action_resolved.connect(_on_action_resolved)
	services.events.character_recovered.connect(_on_character_recovered)
	note_driven = find_accounting(services.session)
	process_physics_priority = -1      # read the inputs and steer the body before the physics step of this frame


## Drops the triangles of a garage trimesh whose centre lies inside the parked rover's box (data/rover.json
## garage_clear_box, body frame at the park pose): the floor object under the parked rover would otherwise hold it.
## Returns how many were dropped.
static func _clear_parking(cs: CollisionShape3D, park: Dictionary, clear: Dictionary) -> int:
	var shape := cs.shape as ConcavePolygonShape3D
	var to_body := (Transform3D(Basis(park.q as Quaternion), park.p as Vector3)).affine_inverse() * cs.global_transform
	var centre := RoverBody._v3(clear.center)
	var half := RoverBody._v3(clear.half)
	var faces := shape.get_faces()
	var kept := PackedVector3Array()
	var dropped := 0
	for i in range(0, faces.size() - 2, 3):
		var mid := to_body * ((faces[i] + faces[i + 1] + faces[i + 2]) / 3.0) - centre
		if absf(mid.x) < half.x and absf(mid.y) < half.y and absf(mid.z) < half.z:
			dropped += 1
			continue
		kept.append(faces[i])
		kept.append(faces[i + 1])
		kept.append(faces[i + 2])
	if dropped > 0:
		var fresh := ConcavePolygonShape3D.new()
		fresh.backface_collision = shape.backface_collision
		fresh.set_faces(kept)
		cs.shape = fresh
	return dropped


# ---------------------------------------------------------------- energy accounting (host)

## The host's driving-energy charge: RoverSystem.note_driven (static, or on the RoverSystem in the simulation's
## post_systems) when that script exists, otherwise a local fallback that takes RoverModel.energy_kwh_for_move from
## the rover battery. Looked up at run time, so this file works before or without worker P10A's code.
func find_accounting(session: SessionService, script_path := ROVER_SYSTEM_PATH) -> Callable:
	var script: Script = load(script_path) as Script if ResourceLoader.exists(script_path) else null
	var found := accounting_from_script(script, session)
	if found.is_valid():
		accounting = "RoverSystem.note_driven"
		return found
	accounting = "fallback: RoverModel.energy_kwh_for_move"
	return RoverPresenter.fallback_note_driven


## A note_driven Callable from `script` (static function, or method of an instance in session.sim.post_systems), or
## an invalid Callable.
static func accounting_from_script(script: Script, session: SessionService) -> Callable:
	if script == null:
		return Callable()
	for m: Dictionary in script.get_script_method_list():
		if String(m.name) != "note_driven":
			continue
		if int(m.get("flags", 0)) & METHOD_FLAG_STATIC:
			return func(st: ColonyState, ev: GameEvents, d: float, c: float) -> float:
				return float(script.call("note_driven", st, ev, d, c))
		if session != null and session.sim != null:
			for system: Object in session.sim.post_systems + session.sim.pre_systems:
				if system != null and system.get_script() == script:
					return Callable(system, "note_driven")
	return Callable()


## Without RoverSystem: the energy RoverModel says this move costs, taken from the rover battery (never below 0).
static func fallback_note_driven(st: ColonyState, _events: GameEvents, distance_m: float, climb_m: float) -> float:
	var levels: Dictionary = st.rover.get("levels", {})
	var kwh := RoverModel.energy_kwh_for_move(levels, RoverModel.cargo_mass_kg(st), distance_m, climb_m)
	var have := float(st.rover.get("battery_kwh", 0.0))
	var used := clampf(kwh, 0.0, have)
	st.rover["battery_kwh"] = have - used
	return used


# ---------------------------------------------------------------- frame

func _physics_process(delta: float) -> void:
	if body == null or services == null or not services.has_game():
		return
	var st := services.state()
	var seats := seats_of(st)
	var me := services.local_character()
	var driver_id := String(seats[0])
	var driver := st.character(StringName(driver_id)) if driver_id != "" else null
	var i_drive := me != null and driver_id == String(me.id)
	if i_drive:
		role = Role.DRIVE
	elif services.is_authority() and (driver == null or driver.owner_peer == 0):
		role = Role.PARK
	else:
		role = Role.FOLLOW
	body.set_remote(role == Role.FOLLOW)

	_stats_left -= delta
	if _stats_left <= 0.0 or _stats.is_empty():
		_stats_left = 0.25
		_refresh_stats(st, seats)
	var battery := float(st.rover.get("battery_kwh", 0.0))
	body.drive_enabled = battery > 1e-6
	match role:
		Role.DRIVE:
			var player_ok := _player != null and _player.input_enabled
			if player_ok:
				body.throttle = Input.get_axis(&"move_back", &"move_forward")
				body.steer = Input.get_axis(&"move_left", &"move_right")
				body.brake = Input.is_action_pressed(&"jump")
			else:
				# a menu or panel took the keyboard: hold the brake rather than roll on
				body.throttle = 0.0
				body.steer = 0.0
				body.brake = true
		Role.PARK:
			body.throttle = 0.0
			body.steer = 0.0
			body.brake = true
		Role.FOLLOW:
			if Time.get_ticks_msec() - _last_extras_ms > 1500 and not services.is_authority():
				# no live poses (just joined, or nobody drives yet): the replicated saved pose
				var saved := RoverBody.from_state_pose(st.rover.get("pose", {}))
				if not saved.is_empty():
					body.follow(saved)

	if role == Role.DRIVE and not services.is_authority():
		_send_left -= delta
		if _send_left <= 0.0:
			_send_left = 1.0 / float((data.get("tuning", {}) as Dictionary).get("pose_hz", 20.0))
			services.net.send_motion_extra(POSE_KEY, body.live_pose())
	if services.is_authority() and role != Role.FOLLOW:
		_live_pose = body.live_pose()
		_host_pose_update(st, body.global_position, delta)


func _process(_delta: float) -> void:
	if body == null or services == null or not services.has_game():
		return
	var p := game.get("player") as PlayerController if game != null else null
	if p != _player:
		if _player != null and is_instance_valid(_player) and _player.vehicle_interact.is_connected(_on_vehicle_interact):
			_player.vehicle_interact.disconnect(_on_vehicle_interact)
		_player = p
		if _player != null:
			_player.vehicle_interact.connect(_on_vehicle_interact)
	var st := services.state()
	var seats := seats_of(st)
	var me := services.local_character()
	_sync_local_seat(st, seats, me)
	_sync_seated_visuals(st, seats, me)
	_update_hud(st, seats, me)


## The four seat entries (character ids, "" free) of `st`, always four.
static func seats_of(st: ColonyState) -> Array:
	var seats: Array = st.rover.get("seats", []) if st != null else []
	var out: Array = []
	for i in RoverModel.SEATS:
		out.append(String(seats[i]) if i < seats.size() and seats[i] != null else "")
	return out


## Seat to ask for: the driver's seat if free, else the first free passenger seat, else -1.
static func choose_seat(seats: Array) -> int:
	for i in seats.size():
		if String(seats[i]) == "":
			return i
	return -1


func _refresh_stats(st: ColonyState, seats: Array) -> void:
	var levels: Dictionary = st.rover.get("levels", {})
	_cargo_kg = RoverModel.cargo_mass_kg(st)
	_stats = RoverModel.stats(levels, _cargo_kg)
	_now_stats = RoverModel.current_stats(st)
	var with_cargo := _stats.duplicate()
	# RoverModel.stats(levels, cargo).mass_kg may or may not include the cargo: add it only if it does not.
	var empty_mass := float(RoverModel.stats(levels, 0.0).get("mass_kg", 0.0))
	if _cargo_kg > 0.0 and absf(float(_stats.get("mass_kg", 0.0)) - empty_mass) < 0.5 * _cargo_kg:
		with_cargo["mass_kg"] = float(_stats.get("mass_kg", 0.0)) + _cargo_kg
	body.set_stats(with_cargo)
	var crew := 0
	for id: String in seats:
		if id != "":
			crew += 1
	body.set_crew(crew)


# ---------------------------------------------------------------- host: pose, saves, energy

func _host_pose_update(st: ColonyState, pos: Vector3, delta: float) -> void:
	_state_pose_left -= delta
	if _state_pose_left <= 0.0:
		_state_pose_left = 1.0 / STATE_POSE_HZ
		RoverSystem.note_pose(st, RoverBody.to_state_pose(_live_pose))   # cargo and seated crew follow the pose
	_accumulate(st, pos, delta)


func _accumulate(st: ColonyState, pos: Vector3, delta: float) -> void:
	if _acc_last == Vector3.INF:
		_acc_last = pos
		_acc_start_y = pos.y
	var step := pos.distance_to(_acc_last)
	if step >= MIN_STEP_M:
		if step < 25.0:            # a reload or a recovery is not driving
			_acc_distance += step
		_acc_last = pos
	_acc_left -= delta
	if _acc_left > 0.0:
		return
	_acc_left = CHARGE_EVERY_S
	if _acc_distance <= 0.0:
		_acc_start_y = pos.y
		return
	var climb := pos.y - _acc_start_y
	var used := 0.0
	if note_driven.is_valid():
		used = float(note_driven.call(st, services.events, _acc_distance, climb))
	energy_charged_kwh += used
	distance_counted_m += _acc_distance
	_acc_distance = 0.0
	_acc_start_y = pos.y


## Host: everything still counted but not yet charged is charged now (tests, before a save).
func flush_accounting() -> void:
	if services != null and services.is_authority() and services.has_game():
		_acc_left = 0.0
		_accumulate(services.state(), _acc_last if _acc_last != Vector3.INF else body.global_position, 0.0)


## Host: a client sent a motion extra. Only the peer whose character sits in seat 0 may move the rover, and only by a
## plausible step from the last pose.
func _on_motion_extra(sender: int, key: String, value: Variant) -> void:
	if key != POSE_KEY or body == null or not services.has_game():
		return
	var st := services.state()
	var driver_id := String(seats_of(st)[0])
	var driver := st.character(StringName(driver_id)) if driver_id != "" else null
	if driver == null or driver.owner_peer != sender or sender == services.local_peer() or not value is Dictionary:
		poses_refused += 1
		return
	var pose := value as Dictionary
	if not RoverBody.pose_valid(pose):
		poses_refused += 1
		return
	var now := Time.get_ticks_msec()
	var dt := clampf((now - _last_accept_ms) / 1000.0, 0.0, 5.0) if _last_accept_ms > 0 else 5.0
	if not _live_pose.is_empty() and (pose.p as Vector3).distance_to(_live_pose.p as Vector3) > POSE_JUMP_M + (body.top_speed_mps * 2.0 + 2.0) * dt:
		poses_refused += 1
		return
	_last_accept_ms = now
	poses_accepted += 1
	_live_pose = {"p": pose.p, "q": (pose.q as Quaternion).normalized(), "lv": pose.get("lv", Vector3.ZERO), "av": pose.get("av", Vector3.ZERO)}
	body.follow(_live_pose)
	RoverSystem.note_pose(st, RoverBody.to_state_pose(_live_pose))   # cargo and seated crew follow the pose
	_accumulate(st, pose.p as Vector3, dt if dt < 5.0 else 0.0)


## Host: what NetSession broadcasts with the body positions (~20 Hz).
func motion_extras() -> Dictionary:
	return {POSE_KEY: _live_pose} if not _live_pose.is_empty() else {}


## Client: the host's motion extras arrived.
func _on_motion_extras(extras: Dictionary) -> void:
	if body == null or not extras.has(POSE_KEY) or not extras[POSE_KEY] is Dictionary:
		return
	_last_extras_ms = Time.get_ticks_msec()
	if role == Role.DRIVE:
		return                     # this machine's body is the authority while it drives
	body.follow(extras[POSE_KEY] as Dictionary)


# ---------------------------------------------------------------- seats

func _on_vehicle_interact(_vehicle: Node) -> void:
	if _player == null or not services.has_game():
		return
	if _player.is_seated():
		try_exit()
	else:
		try_enter()


## E on the rover while standing: ask the host for the driver's seat if free, else the first free passenger seat.
func try_enter() -> ActionResult:
	var st := services.state()
	if not bool(st.rover.get("built", false)):
		return _say_failure("The rover is not assembled yet. The field engineer builds it at the garage.")
	if _player != null and _player.held_item() != null:
		return _say_failure("Your hands are full. Put it down first, or load it into the rover's cargo bay.")
	var seat := RoverPresenter.choose_seat(seats_of(st))
	if seat < 0:
		return _say_failure("All four seats are taken.")
	var r := services.request(&"rover_enter", &"", {"seat": seat})
	_track(r, "enter")
	return r


## E while seated: get out through the first clear exit, or say why not.
func try_exit() -> ActionResult:
	if body.linear_velocity.length() > EXIT_MAX_SPEED:
		var me := services.local_character()
		var driving := me != null and String(seats_of(services.state())[0]) == String(me.id)
		return _say_failure("Stop the rover before getting out: hold Space." if driving else "Wait until the rover stops before getting out.")
	var index := first_clear_exit()
	if index < 0:
		return _say_failure("Every way out is blocked. Drive a little way into the open, then press E again.")
	_exit_requested = index
	var r := services.request(&"rover_exit", &"", {"exit_index": index})
	_track(r, "exit")
	return r


func _track(r: ActionResult, what: String) -> void:
	if r.pending:
		_pending[r.request_id] = what
	elif not r.ok:
		if what == "exit":
			_exit_requested = -1
		_say(r.message)


func _on_action_resolved(r: ActionResult) -> void:
	if not _pending.has(r.request_id):
		return
	var what := String(_pending[r.request_id])
	_pending.erase(r.request_id)
	if not r.ok:
		if what == "exit":
			_exit_requested = -1
		_say(r.message)


func _say_failure(text: String) -> ActionResult:
	_say(text)
	return ActionResult.failure("", &"missing_prerequisite", text)


func _say(text: String) -> void:
	var hud := game.get("hud") as GameHud if game != null else null
	if hud != null:
		hud.show_message(text, 3.5)


## Index of the first exit whose standing space is clear and has ground under it, or -1 if all are blocked.
func first_clear_exit() -> int:
	for i in body.exit_positions.size():
		if exit_clear(i):
			return i
	return -1


## True if a standing person fits at exit `index`: ground within EXIT_STEP_M of the exit point and nothing solid
## (map, doors, props, people) in the capsule standing there. The rover itself is ignored.
func exit_clear(index: int) -> bool:
	var ground: Variant = exit_ground(index)
	if ground == null:
		return false
	var space := body.get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = EXIT_RADIUS_M
	capsule.height = EXIT_HEIGHT_M
	params.shape = capsule
	params.transform = Transform3D(Basis.IDENTITY, (ground as Vector3) + Vector3.UP * (EXIT_HEIGHT_M * 0.5 + 0.08))
	params.collision_mask = Layers.WORLD | Layers.DOOR | Layers.ITEM | Layers.PLAYER
	var exclude: Array[RID] = [body.get_rid()]
	if _player != null:
		exclude.append(_player.get_rid())
	params.exclude = exclude
	return space.intersect_shape(params, 1).is_empty()


## Ground point under exit `index` (Vector3), or null if there is none close enough.
func exit_ground(index: int) -> Variant:
	if index < 0 or index >= body.exit_positions.size():
		return null
	var feet := body.exit_world(index)
	var space := body.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * EXIT_STEP_M, feet + Vector3.DOWN * EXIT_STEP_M, Layers.WORLD | Layers.DOOR, [body.get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	return hit.position


func _sync_local_seat(st: ColonyState, seats: Array, me: CharacterState) -> void:
	if _player == null or me == null:
		return
	var mine := seats.find(String(me.id))
	if mine >= 0:
		var anchor := body.seat_anchor(mine)
		if _player.seat_anchor() != anchor:
			_player.sit(anchor, body, body.seat_eye_height, CHASE_LENGTH_M)
		return
	if not _player.is_seated():
		return
	# Out of the seat: by the exit this player asked for, or (freed by the host for another reason: a recovery, a
	# reload) where the host put the character if that is away from the rover, else by the first clear exit.
	var at: Variant = null
	if _exit_requested >= 0:
		at = exit_ground(_exit_requested)
		if at == null:
			at = body.exit_world(_exit_requested)
	elif me.position.distance_to(body.global_position) > float(data.get("enter_distance_m", 6.0)):
		at = me.position
	else:
		var e := first_clear_exit()
		at = exit_ground(e) if e >= 0 else me.position
	_exit_requested = -1
	_player.stand((at as Vector3) + Vector3.UP * 0.05, body.global_basis.get_euler().y)


func _on_character_recovered(character_id: StringName, _info: Dictionary) -> void:
	var me := services.local_character()
	if me != null and me.id == character_id and _player != null and _player.is_seated():
		_exit_requested = -1
		_player.stand(me.position + Vector3.UP * 0.05, me.yaw)


## Other players' crew in a seat: drawn in the seat with the seated pose; GameMain's walking copy of them is hidden
## (and its door-sensing body switched off) until they get out.
func _sync_seated_visuals(st: ColonyState, seats: Array, me: CharacterState) -> void:
	var crew_visuals: Dictionary = game.get("_crew_visuals") if game != null and game.get("_crew_visuals") is Dictionary else {}
	var wanted := {}
	for i in seats.size():
		var id := String(seats[i])
		if id == "" or (me != null and id == String(me.id)):
			continue
		var c := st.character(StringName(id))
		if c == null:
			continue
		wanted[id] = true
		var v := _seated_visuals.get(id) as PlayerVisual
		if v == null:
			v = PlayerVisual.new()
			v.name = "Seated_" + id
			v.use_rig_if_available()
			v.set_first_person(false)
			var identity := maxi(0, CharacterState.SPECIALTIES.find(c.specialty))
			v.set_crew_identity(identity)
			v.set_name_tag(CrewLooks.tag_text(c.display_name, identity))
			_seated_visuals[id] = v
		var anchor := body.seat_anchor(i)
		if v.get_parent() != anchor:
			if v.get_parent() != null:
				v.get_parent().remove_child(v)
			anchor.add_child(v)
			v.transform = Transform3D.IDENTITY
		v.set_suit(c.suit_on)
		v.set_zone_layers(_mesh_layers)
		v.play(&"seated")
		var walking := crew_visuals.get(StringName(id)) as Node3D
		if walking != null:
			walking.visible = false
			var presence := walking.get_node_or_null("Presence") as CollisionObject3D
			if presence != null:
				presence.collision_layer = 0
	for id: String in _seated_visuals.keys():
		if wanted.has(id):
			continue
		(_seated_visuals[id] as Node).queue_free()
		_seated_visuals.erase(id)
		var walking := crew_visuals.get(StringName(id)) as Node3D
		if walking != null:
			walking.visible = true
			var c := st.character(StringName(id))
			var presence := walking.get_node_or_null("Presence") as CollisionObject3D
			if presence != null and c != null:
				presence.collision_layer = Layers.CREW_SOLID | (Layers.PLAYER if c.is_active() else 0)


## Seated bodies of other players' crew, by character id (tests).
func seated_visuals() -> Dictionary:
	return _seated_visuals


# ---------------------------------------------------------------- HUD

func _update_hud(st: ColonyState, seats: Array, me: CharacterState) -> void:
	if hud_widget == null:
		return
	var mine := seats.find(String(me.id)) if me != null else -1
	if mine >= 0 and _player != null and _player.is_seated():
		var names: Array = []
		for id: String in seats:
			var c := st.character(StringName(id)) if id != "" else null
			names.append(c.display_name if c != null else "")
		var battery := float(st.rover.get("battery_kwh", 0.0))
		var driver := mine == 0
		var keys := "%s drive · %s brake · %s get out · %s view" % [_keys_of([&"move_forward", &"move_left", &"move_back", &"move_right"]),
			_key(&"jump", "Space"), _key(&"interact", "E"), _key(&"toggle_view", "Tab")] if driver else \
			"%s get out · %s view" % [_key(&"interact", "E"), _key(&"toggle_view", "Tab")]
		var speed := body.linear_velocity.length()
		var fc := float(_now_stats.get("fuel_cell_kwh", 0.0))
		var charging := bool(st.rover.get("charging", false)) and String(st.rover.get("charge_status", "")) == "charging"
		hud_widget.show_seated({"speed_mps": speed, "battery_kwh": battery,
			"capacity_kwh": float(_stats.get("battery_capacity_kwh", 1.0)),
			"range_km": float(_now_stats.get("range_km", _stats.get("range_km", 0.0))),
			"cargo_kg": _cargo_kg, "cargo_capacity_kg": float(_stats.get("cargo_capacity_kg", 0.0)), "seats": names,
			"seat": mine, "driver": driver, "battery_empty": battery <= 1e-6 and fc <= 1e-6, "keys": keys,
			"heading_deg": heading_deg(), "home_m": home_distance_m(st), "time_left_s": time_left_s(st, speed, battery + fc),
			"cabin": bool(_now_stats.get("cabin", false)), "sheltered": RoverModel.cabin_sheltered(st, me),
			"fuel_cell_kwh": fc, "fuel_cell_capacity_kwh": float(_now_stats.get("fuel_cell_capacity_kwh", 0.0)),
			"rtg_kw": float(_now_stats.get("rtg_kw", 0.0)), "track_level": int(_now_stats.get("track_level", 1)),
			"charging": charging})
		hud_widget.show_cue("")
		return
	hud_widget.hide_seated()
	hud_widget.show_cue(cue_for(st, seats))


## The rover's heading in degrees, clockwise from north (the map's north is Godot -Z, east +X; the body faces -Z).
func heading_deg() -> float:
	var f := -body.global_basis.z
	if Vector2(f.x, f.z).length_squared() < 1e-8:
		return 0.0
	return fposmod(rad_to_deg(atan2(f.x, -f.z)), 360.0)


## Horizontal distance from the rover to its home, the garage charger (the garage station if there is no charger), m;
## -1 when neither is known.
func home_distance_m(st: ColonyState) -> float:
	var id := RoverSystem.charger_id(st)
	if id == "":
		id = RoverSystem.garage_id(st)
	var rec: Dictionary = st.stations.get(id, {}) if id != "" else {}
	if rec.is_empty() or not rec.has("position"):
		return -1.0
	var home := CharacterState._v3(rec.position)
	var p := body.global_position
	return Vector2(home.x - p.x, home.z - p.z).length()


## Real seconds the stored energy (`stored_kwh`: battery plus fuel cell) lasts at the current draw: driving at `speed`
## m/s with the energy per metre of RoverModel.current_stats (this crew and cargo, the range's terrain allowance),
## less the RTG trickle. -1 when the rover is (nearly) standing still or the RTG covers the draw.
func time_left_s(st: ColonyState, speed: float, stored_kwh: float) -> float:
	if speed < 0.3:
		return -1.0
	var b := RoverBalance.get_current()
	var per_m := float(_now_stats.get("kwh_per_km", 0.0)) * b.range_terrain_factor / 1000.0
	var draw := speed * per_m                                 # kWh per real second
	var real_s_per_hour := 3600.0
	if services != null and services.has_game() and services.clock() != null:
		real_s_per_hour = maxf(1.0, float(services.clock().sol_minutes) * 60.0 / GameConfig.SOL_HOURS)
	draw -= RoverModel.rtg_kw(st) / real_s_per_hour
	if draw <= 1e-9:
		return -1.0
	return maxf(0.0, stored_kwh) / draw


## What E would do now, for the line under the crosshair ("" when the rover is not aimed at).
func cue_for(st: ColonyState, seats: Array) -> String:
	if _player == null or not _player.is_inside_tree():
		return ""
	var target := _player.aimed_target()
	if String(target.get("kind", "")) != "vehicle" or target.get("node") != body:
		return ""
	var key := _key(&"interact", "E")
	if not bool(st.rover.get("built", false)):
		return "Rover: not assembled yet (the field engineer builds it at the garage)"
	if _player.held_item() != null:
		return "[%s] Put down (hands full: put it down before getting in)" % key
	var seat := RoverPresenter.choose_seat(seats)
	if seat < 0:
		return "Rover: all four seats are taken"
	return "[%s] Get in: %s" % [key, "driver's seat" if seat == 0 else "passenger seat"]


static func _key(action: StringName, fallback: String) -> String:
	var text := PlayerInput.describe(action)
	return text if text != "" else fallback


static func _keys_of(actions: Array) -> String:
	var parts := PackedStringArray()
	for a: StringName in actions:
		parts.append(_key(a, "?"))
	return "".join(parts)
