class_name RoverBody
extends RigidBody3D
## The drivable rover (Prompt 10): a RigidBody3D carried by one ray-cast spring/damper per wheel under Mars gravity.
##
## Frame: origin on the ground under the middle axle, -Z forward, +X right, +Y up (data/rover.json). Everything here
## is presentation physics on one machine: the machine of the driver simulates it (RoverPresenter), every other
## machine shows a kinematic copy that follows the driver's pose (set_remote / follow).
##
## Per wheel and physics step (in _integrate_forces, so the ray queries and the forces use the same body state):
##   suspension  spring k = m g / (wheels x sag) (so the static compression is `sag` whatever the mass) and a damper
##               at `damping_ratio`; a stiffer bump stop near full compression; an anti-roll pair per axle
##   drive       throttle x drive_force_n shared by all wheels, faded out at top_speed_mps (40 % of it in reverse);
##               no drive force at all with an empty battery (coasting and the brake still work)
##   grip        lateral force against sideways sliding and the longitudinal drive / brake / rolling force, together
##               limited to traction_mu x the wheel's normal load (friction circle): grip in tight turns, slip on
##               slopes steeper than atan(mu)
##   steering    front pair +angle, rear pair -angle (counter-steer), middle fixed; full lock up to steer_full_below
##               m/s, then the largest angle shrinks to steer_deg_at_top over the next steer_fade_over m/s
## Gravity is applied here (gravity_scale 0) as GameConfig.MARS_GRAVITY, 3.73 m/s² (NASA fact sheet, source N01).

const DATA_PATH := "res://data/rover.json"

## Driver inputs, set every physics frame by whoever drives (the presenter or a test). throttle and steer are -1..1
## (steer > 0 turns right); brake holds every wheel.
var throttle := 0.0
var steer := 0.0
var brake := false
## False when the battery is empty: no drive force, coasting and braking only.
var drive_enabled := true

## From RoverModel.stats(): see set_stats().
var top_speed_mps := 3.0
var drive_force_n := 1500.0
var traction_mu := 0.6
## Mass of the rover with its cargo, without crew (set_stats), and of the crew aboard (set_crew).
var vehicle_mass_kg := 900.0
var crew_kg := 0.0
## Extra payload put aboard directly (tests; the presenter puts cargo into vehicle_mass_kg).
var payload_kg := 0.0

# ---- geometry (data/rover.json)
var wheel_positions: Array[Vector3] = []
var wheel_steer: PackedFloat32Array = []
var wheel_radius := 0.525
var seat_positions: Array[Vector3] = []
var exit_positions: Array[Vector3] = []
var seat_eye_height := 1.29
var data: Dictionary = {}

# ---- tuning (data/rover.json "tuning", game values)
var sag := 0.06
var travel := 0.25
var bump_stop := 0.18
var damping_ratio := 0.55
var anti_roll_ratio := 0.6
var max_steer_deg := 30.0
var steer_deg_at_top := 9.0
var steer_full_below := 1.5
var steer_fade_over := 6.0
var steer_rate_deg_s := 110.0
var rolling_resistance := 0.05
var coast_drag := 0.25
var reverse_fraction := 0.4
var lateral_stiffness := 0.6
var crew_mass_each_kg := 160.0

# ---- telemetry (read by the presenter, the HUD and the driving checks)
## Wheels touching the ground in the last step, and the share of steps with each wheel grounded.
var wheels_grounded := 0
var steer_angle_deg := 0.0
## Signed speed along the rover's forward axis (m/s).
var forward_speed := 0.0
## Physics steps simulated, and the sum over them of wheels grounded (contact share = sum / (steps x wheels)).
var steps_simulated := 0
var grounded_sum := 0
var _compression: PackedFloat32Array = []
var _remote := false
var _target_pose := {}
var _target_age := 0.0
var _mesh: Node3D


func _init() -> void:
	gravity_scale = 0.0
	can_sleep = false
	continuous_cd = true
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0                     # the thin Martian air: no aerodynamic drag worth modelling
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.3
	collision_layer = Layers.WORLD        # solid for people, props and the player's aim ray
	collision_mask = Layers.WORLD | Layers.DOOR | Layers.ITEM   # not PLAYER: it never pushes a person (they step out of it)
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	var mat := PhysicsMaterial.new()
	mat.friction = 0.4
	mat.bounce = 0.0
	physics_material_override = mat
	set_meta(&"vehicle_id", &"rover")


## Reads data/rover.json (or `d`) and builds the collision boxes and seat / exit anchors. Call once, before adding
## to the tree or right after.
func configure(d: Dictionary = {}) -> void:
	data = d if not d.is_empty() else load_data()
	wheel_positions.clear()
	wheel_steer.clear()
	for w: Dictionary in data.get("wheels", []):
		wheel_positions.append(_v3(w.position))
		wheel_steer.append(float(w.get("steer", 0.0)))
	wheel_radius = float(data.get("wheel_radius_m", wheel_radius))
	seat_positions.clear()
	for s: Dictionary in data.get("seats", []):
		seat_positions.append(_v3(s.position))
	exit_positions.clear()
	for e: Dictionary in data.get("exits", []):
		exit_positions.append(_v3(e.position))
	seat_eye_height = float(data.get("seat_eye_height_m", seat_eye_height))
	var t: Dictionary = data.get("tuning", {})
	sag = float(t.get("sag_m", sag))
	travel = float(t.get("travel_m", travel))
	bump_stop = float(t.get("bump_stop_m", bump_stop))
	damping_ratio = float(t.get("damping_ratio", damping_ratio))
	anti_roll_ratio = float(t.get("anti_roll_ratio", anti_roll_ratio))
	max_steer_deg = float(t.get("max_steer_deg", max_steer_deg))
	steer_deg_at_top = float(t.get("steer_deg_at_top_speed", steer_deg_at_top))
	steer_full_below = float(t.get("steer_full_below_mps", steer_full_below))
	steer_fade_over = float(t.get("steer_fade_over_mps", steer_fade_over))
	steer_rate_deg_s = float(t.get("steer_rate_deg_s", steer_rate_deg_s))
	rolling_resistance = float(t.get("rolling_resistance", rolling_resistance))
	coast_drag = float(t.get("coast_drag_mps2", coast_drag))
	reverse_fraction = float(t.get("reverse_speed_fraction", reverse_fraction))
	lateral_stiffness = float(t.get("lateral_stiffness", lateral_stiffness))
	crew_mass_each_kg = float(t.get("crew_mass_kg", crew_mass_each_kg))
	center_of_mass = _v3(t.get("centre_of_mass", [0.0, 0.55, 0.0]))
	_compression.resize(wheel_positions.size())
	_compression.fill(0.0)
	for child in get_children():
		if child is CollisionShape3D or child.name.begins_with("Seat") or child.name.begins_with("Exit"):
			remove_child(child)
			child.queue_free()
	for b: Dictionary in data.get("collision_boxes", []):
		var cs := CollisionShape3D.new()
		cs.name = "Box_" + String(b.get("name", "part"))
		var box := BoxShape3D.new()
		box.size = _v3(b.half) * 2.0
		cs.shape = box
		cs.position = _v3(b.center)
		add_child(cs)
	for i in seat_positions.size():
		var anchor := Node3D.new()
		anchor.name = "Seat%d" % i
		anchor.position = seat_positions[i]
		add_child(anchor)
	for i in exit_positions.size():
		var marker := Marker3D.new()
		marker.name = "Exit%d" % i
		marker.position = exit_positions[i]
		add_child(marker)
	_apply_mass()


static func load_data() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
	return parsed if parsed is Dictionary else {}


## Takes the driving numbers from RoverModel.stats(levels, cargo_kg): top_speed_mps, drive_force_n, traction_mu and
## mass_kg (the rover with its cargo).
func set_stats(stats: Dictionary) -> void:
	top_speed_mps = maxf(0.1, float(stats.get("top_speed_mps", top_speed_mps)))
	drive_force_n = maxf(0.0, float(stats.get("drive_force_n", drive_force_n)))
	traction_mu = clampf(float(stats.get("traction_mu", traction_mu)), 0.05, 2.0)
	var m := maxf(50.0, float(stats.get("mass_kg", vehicle_mass_kg)))
	if not is_equal_approx(m, vehicle_mass_kg):
		vehicle_mass_kg = m
		_apply_mass()


## Number of crew aboard (each adds crew_mass_kg).
func set_crew(count: int) -> void:
	var kg := crew_mass_each_kg * clampi(count, 0, 4)
	if not is_equal_approx(kg, crew_kg):
		crew_kg = kg
		_apply_mass()


func set_payload(kg: float) -> void:
	payload_kg = maxf(0.0, kg)
	_apply_mass()


## Total simulated mass in kg.
func total_mass() -> float:
	return vehicle_mass_kg + crew_kg + payload_kg


func _apply_mass() -> void:
	mass = total_mass()
	var dims := _v3((data.get("tuning", {}) as Dictionary).get("inertia_box", [2.6, 1.6, 5.0]))
	inertia = Vector3(mass / 12.0 * (dims.y * dims.y + dims.z * dims.z), mass / 12.0 * (dims.x * dims.x + dims.z * dims.z),
		mass / 12.0 * (dims.x * dims.x + dims.y * dims.y))


## The drawn rover: a copy of the map's mesh, turned into the body frame (the static map copy is hidden by the presenter).
func set_visual(mesh_copy: Node3D) -> void:
	if _mesh != null:
		_mesh.queue_free()
	_mesh = mesh_copy
	if _mesh == null:
		return
	_mesh.name = "Visual"
	add_child(_mesh)
	_mesh.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(data.get("mesh_yaw_deg", 180.0)))), Vector3.ZERO)


func visual() -> Node3D:
	return _mesh


func seat_anchor(index: int) -> Node3D:
	return get_node_or_null("Seat%d" % index) as Node3D


## World position of exit `index` (feet), not yet dropped onto the ground.
func exit_world(index: int) -> Vector3:
	return global_transform * exit_positions[index]


## Steps of physics in which every wheel touched the ground, as a share of all wheel-steps (1 = always).
func contact_share() -> float:
	if steps_simulated == 0 or wheel_positions.is_empty():
		return 1.0
	return float(grounded_sum) / float(steps_simulated * wheel_positions.size())


func reset_telemetry() -> void:
	steps_simulated = 0
	grounded_sum = 0


# ---------------------------------------------------------------- simulation

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	if dt <= 0.0 or wheel_positions.is_empty():
		return
	var m := mass
	var g := GameConfig.MARS_GRAVITY
	state.apply_central_force(Vector3.DOWN * g * m)
	var xf := state.transform
	var up := xf.basis.y.normalized()
	var fwd := -xf.basis.z.normalized()
	var lin := state.linear_velocity
	var ang := state.angular_velocity
	var com := state.center_of_mass          # relative to the body origin, global orientation
	forward_speed = lin.dot(fwd)
	var n := wheel_positions.size()
	var m_w := m / float(n)
	var k := m * g / (float(n) * sag)
	var c := 2.0 * damping_ratio * sqrt(k * m_w)
	var rest := wheel_radius + sag
	var reach := rest + travel

	# steering: the largest angle shrinks with speed; the wheel angle follows the input at a limited rate
	var speed_share := clampf((absf(forward_speed) - steer_full_below) / maxf(steer_fade_over, 0.1), 0.0, 1.0)
	var limit := lerpf(max_steer_deg, steer_deg_at_top, speed_share)
	steer_angle_deg = move_toward(steer_angle_deg, clampf(steer, -1.0, 1.0) * limit, steer_rate_deg_s * dt)

	var space := state.get_space_state()
	var hits: Array = []
	var comp := PackedFloat32Array()
	comp.resize(n)
	hits.resize(n)
	for i in n:
		var centre := xf * wheel_positions[i]
		var q := PhysicsRayQueryParameters3D.create(centre + up * wheel_radius, centre - up * reach, Layers.WORLD | Layers.DOOR, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			comp[i] = 0.0
			hits[i] = null
			continue
		var d := ((hit.position as Vector3) - centre).dot(-up)
		comp[i] = maxf(0.0, rest - d)
		hits[i] = hit
	# spring + damper + bump stop, then the anti-roll pairs (wheels at the same z, opposite sides)
	var load := PackedFloat32Array()
	load.resize(n)
	for i in n:
		if hits[i] == null:
			load[i] = 0.0
			continue
		var v_comp := (comp[i] - _compression[i]) / dt
		var f := k * comp[i] + c * v_comp
		if comp[i] > bump_stop:
			f += 8.0 * k * (comp[i] - bump_stop)
		load[i] = maxf(0.0, f)
	for i in n:
		for j in range(i + 1, n):
			if absf(wheel_positions[i].z - wheel_positions[j].z) < 0.05 and signf(wheel_positions[i].x) != signf(wheel_positions[j].x):
				if hits[i] != null and hits[j] != null:
					var anti := anti_roll_ratio * k * (comp[i] - comp[j])
					load[i] = maxf(0.0, load[i] + anti)
					load[j] = maxf(0.0, load[j] - anti)
	_compression = comp

	var grounded := 0
	var top := top_speed_mps
	var reverse_top := top_speed_mps * reverse_fraction
	var drive_each := drive_force_n / float(n)
	for i in n:
		if hits[i] == null:
			continue
		grounded += 1
		var hit: Dictionary = hits[i]
		var p: Vector3 = hit.position
		var normal: Vector3 = (hit.normal as Vector3).normalized()
		var r := p - xf.origin
		state.apply_force(up * load[i], xf * wheel_positions[i] - xf.origin)
		var wheel_fwd := fwd.rotated(up, -wheel_angle(i))
		var f_g := (wheel_fwd - normal * wheel_fwd.dot(normal))
		if f_g.length_squared() < 1e-6:
			continue
		f_g = f_g.normalized()
		var s_g := normal.cross(f_g).normalized()
		var v_p := lin + ang.cross(r - com)
		var v_long := v_p.dot(f_g)
		var v_lat := v_p.dot(s_g)
		var normal_load := load[i] * maxf(0.0, up.dot(normal))
		var grip := traction_mu * normal_load
		var stop_force := absf(v_long) * m_w / dt          # force that would stop this wheel's share in one step
		# The share of gravity pulling this wheel's part of the rover along the ground: a held brake and the tyre's
		# side grip cancel it in the same step, so a braked rover stands still on a slope instead of creeping.
		var pull_long := m_w * g * Vector3.DOWN.dot(f_g)
		var pull_lat := m_w * g * Vector3.DOWN.dot(s_g)
		var f_long := 0.0
		var pedal := clampf(throttle, -1.0, 1.0)
		var against := (pedal > 0.0 and v_long < -0.2) or (pedal < 0.0 and v_long > 0.2)
		if brake or against:
			# a brake stops the wheel (mechanical: works with an empty battery too), within the tyre's grip
			f_long = -v_long * m_w / dt - pull_long
		elif drive_enabled and pedal != 0.0:
			var fade := clampf((top - v_long) / (0.15 * top), 0.0, 1.0) if pedal > 0.0 else clampf((reverse_top + v_long) / (0.15 * reverse_top), 0.0, 1.0)
			f_long = pedal * drive_each * fade - signf(v_long) * minf(stop_force, rolling_resistance * normal_load)
			# the motor controller holds the top speed downhill too (regenerative braking, no energy credited)
			var over := (v_long - top) if pedal > 0.0 else (-v_long - reverse_top)
			if over > 0.0:
				f_long -= signf(v_long) * minf(stop_force, over * m_w * 2.0)
		else:
			# coasting: rolling resistance and drivetrain drag, never reversing the wheel
			f_long = -signf(v_long) * minf(stop_force, coast_drag * m_w + rolling_resistance * normal_load)
		var f_lat := -v_lat * m_w / dt * lateral_stiffness - pull_lat
		var tangent := f_g * f_long + s_g * f_lat
		var t_len := tangent.length()
		if t_len > grip and t_len > 0.0:
			tangent *= grip / t_len
		state.apply_force(tangent, r)
	wheels_grounded = grounded
	steps_simulated += 1
	grounded_sum += grounded



## Steering angle of wheel i in radians (> 0 turns right). The steered wheels point at one turn centre on the middle
## axle line (Ackermann): steer_angle_deg is the angle of an imaginary wheel on the centre line, so the centre lies
## half_wheelbase / tan(angle) to the side; each steered wheel takes atan(-z / (centre_x - x)). Middle wheels: 0.
func wheel_angle(i: int) -> float:
	if wheel_steer[i] == 0.0 or absf(steer_angle_deg) < 0.05:
		return 0.0
	var half_base := 0.0
	for j in wheel_positions.size():
		if wheel_steer[j] != 0.0:
			half_base = maxf(half_base, absf(wheel_positions[j].z))
	var centre_x := half_base / tan(deg_to_rad(steer_angle_deg))
	var w := wheel_positions[i]
	return atan(-w.z / (centre_x - w.x))

# ---------------------------------------------------------------- network copies

## True: this machine only shows the rover; it follows poses given to follow() (kinematic). False: it simulates.
func set_remote(on: bool) -> void:
	if on == _remote:
		return
	_remote = on
	if on:
		freeze = true
	else:
		if not _target_pose.is_empty():
			_apply_pose_now(_target_pose)
			linear_velocity = _target_pose.get("lv", Vector3.ZERO)
			angular_velocity = _target_pose.get("av", Vector3.ZERO)
		freeze = false
		_compression.fill(0.0)


func is_remote() -> bool:
	return _remote


## The newest pose received for a remote copy ({"p": Vector3, "q": Quaternion, "lv": Vector3, "av": Vector3}).
func follow(pose: Dictionary) -> void:
	if not RoverBody.pose_valid(pose):
		return
	_target_pose = pose
	_target_age = 0.0


func _physics_process(delta: float) -> void:
	if not _remote or _target_pose.is_empty():
		return
	# Extrapolate the last pose by its velocity (at most 0.25 s), then ease toward it; snap after a long gap.
	_target_age += delta
	var age := minf(_target_age, 0.25)
	var p: Vector3 = (_target_pose.p as Vector3) + (_target_pose.get("lv", Vector3.ZERO) as Vector3) * age
	var q: Quaternion = _target_pose.q
	var av: Vector3 = _target_pose.get("av", Vector3.ZERO)
	if av.length() > 1e-4:
		q = (Quaternion(av.normalized(), av.length() * age) * q).normalized()
	var xf := global_transform
	if xf.origin.distance_to(p) > 5.0:
		global_transform = Transform3D(Basis(q), p)
		return
	var follow_k := 1.0 - exp(-delta * 15.0)
	var now_q := xf.basis.get_rotation_quaternion()
	global_transform = Transform3D(Basis(now_q.slerp(q, follow_k)), xf.origin.lerp(p, follow_k))


func _apply_pose_now(pose: Dictionary) -> void:
	global_transform = Transform3D(Basis(pose.q as Quaternion), pose.p as Vector3)


## The pose to send to other machines.
func live_pose() -> Dictionary:
	var xf := global_transform
	return {"p": xf.origin, "q": xf.basis.get_rotation_quaternion(), "lv": linear_velocity, "av": angular_velocity}


## Places the body at a saved pose ({"position": [x, y, z], "quat": [x, y, z, w]}) at rest.
func place(state_pose: Dictionary, lift := 0.0) -> void:
	var pose := RoverBody.from_state_pose(state_pose)
	if pose.is_empty():
		return
	global_transform = Transform3D(Basis(pose.q as Quaternion), (pose.p as Vector3) + Vector3.UP * lift)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_target_pose = pose
	_compression.fill(0.0)


static func pose_valid(pose: Dictionary) -> bool:
	if not (pose.get("p") is Vector3 and pose.get("q") is Quaternion):
		return false
	var p: Vector3 = pose.p
	var q: Quaternion = pose.q
	if not p.is_finite() or not q.is_finite() or absf(q.length() - 1.0) > 0.01:
		return false
	for key: String in ["lv", "av"]:
		if pose.has(key) and not (pose[key] is Vector3 and (pose[key] as Vector3).is_finite() and (pose[key] as Vector3).length() < 100.0):
			return false
	return absf(p.x) < 5000.0 and absf(p.y) < 1000.0 and absf(p.z) < 5000.0


## Saved form (plain JSON) of a live pose.
static func to_state_pose(pose: Dictionary) -> Dictionary:
	var p: Vector3 = pose.p
	var q: Quaternion = pose.q
	return {"position": [p.x, p.y, p.z], "quat": [q.x, q.y, q.z, q.w]}


## Live form of a saved pose, or {} if it is missing or malformed.
static func from_state_pose(d: Variant) -> Dictionary:
	if not d is Dictionary:
		return {}
	var a: Variant = (d as Dictionary).get("position")
	var b: Variant = (d as Dictionary).get("quat")
	if not (a is Array and b is Array and (a as Array).size() == 3 and (b as Array).size() == 4):
		return {}
	var q := Quaternion(float(b[0]), float(b[1]), float(b[2]), float(b[3]))
	if q.length() < 0.5:
		return {}
	var pose := {"p": Vector3(float(a[0]), float(a[1]), float(a[2])), "q": q.normalized(), "lv": Vector3.ZERO, "av": Vector3.ZERO}
	return pose if RoverBody.pose_valid(pose) else {}


static func _v3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
