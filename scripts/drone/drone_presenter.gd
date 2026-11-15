extends Node
## Scene side of the scout drone (upgrade paths plan §6.2). No class_name: GameMain loads it by path and adds it in
## _begin_play(), before AreaStages.attach_all:
##     drone = load("res://scripts/drone/drone_presenter.gd").new(); add_child(drone); drone.setup(world, services, self)
## Found by others through the group GROUP.
##
## What it does (presentation and local input only; the colony changes through host actions and DroneSystem):
##   - puts the landing pad (assets/drone/drone_pad.glb) on its station with a solid box for the charger cabinet;
##   - owns `body`, the flying drone. The scout_drone stage presenter (scripts/upgrades/stages/scout_drone_stages.gd)
##     puts the model of the current level in it (stage_parent), so the drone on the pad and in the air always shows
##     its level. Without that presenter it builds the level's model itself. The body follows state.drone on every
##     machine, gliding between the host updates with the replicated velocity; the rotor hubs (RotorHub_*) spin while
##     it flies;
##   - flight feel of the owner's FPV example (docs/revisions/reference/fpv_drone/flight_controller.gd): the model and
##     the onboard camera tilt with the stick (forward 7°, back 5°, pitch response 8); for other players the tilt
##     follows the drone's forward speed;
##   - manual control: when state.drone.pilot is this machine's character, the drone camera takes over, W A S D fly
##     the way it faces, the mouse turns, Space climbs, Ctrl or Shift goes down, Tab switches chase / FPV camera, R flies
##     it home (host action drone_home; the camera stays on it, AUTO on the screen, until it lands) and E hands it back
##     (drone_land; the player's own camera comes back). Esc pauses as everywhere in the game. The inputs reach the host
##     like the rover's driving: on the host straight into DroneSystem.set_input, on a client as the motion extra
##     "drone" (~20 Hz), which the host accepts only from the peer that owns the pilot character;
##   - the drone's on-screen display (scripts/drone/drone_hud.gd) while its camera is on, with the mineral report popping
##     up when a new one arrives.
## GameMain keeps the walking body still while blocks_player_input() is true.

const DroneSystem := preload("res://scripts/drone/drone_system.gd")
const DroneModels := preload("res://scripts/drone/drone_models.gd")
const DroneHudScript := preload("res://scripts/drone/drone_hud.gd")

const GROUP := &"drone_presenter"
const MOTION_KEY := "drone"
const SEND_HZ := 20.0
const CHASE_DISTANCE_M := 3.4
const CHASE_LIFT_M := 0.6
const ROTOR_SPEED := 55.0          # rad/s while flying (looks right at 60 fps; not a real rotor speed)
const DEFAULT_MOUSE := 0.0025      # rad per pixel (the example's 0.15 ° per pixel)
const YAW_RESPONSE := 28.0
const PITCH_RESPONSE := 8.0
const FPV_LOOK_DOWN := -0.12       # the onboard camera looks a little down by default (rad)

var services: GameServices
var world: Node3D
var game: Node
## The flying drone. The level's model is a child of it (Stage_V<n> from the stage presenter, or DroneFallback).
var body: Node3D
var pad_model: Node3D
var camera: Camera3D
var hud_widget: Control
## True while this machine's player looks through the drone (flying it, or watching it fly home after R).
var piloting := false
## True while this machine's player has the sticks (status "manual").
var controls_active := false
## Tab: onboard (FPV) camera instead of the chase camera.
var onboard_view := false
## Host counters: inputs taken from a client pilot, and refused ones (wrong sender or bad values).
var inputs_accepted := 0
var inputs_refused := 0
## Client: inputs sent to the host.
var inputs_sent := 0

var _root: Node3D
var _shown_pos := Vector3.ZERO
var _shown_yaw := 0.0
var _placed := false
var _last_key := ""
var _since_update := 0.0
var _pilot_yaw := 0.0
var _cam_pitch := -0.3
var _send_left := 0.0
var _e_down := false
var _tab_down := false
var _r_down := false
var _stick := Vector2.ZERO
var _tilt := 0.0
var _hold_after_release := false
var _rotors: Array[Node3D] = []
var _rotor_sig := ""
var _spin := 0.0
var _fallback: Node3D
var _fallback_level := 0
var _staged_check := 0.0
var _staged := false
var _report_seen := -1


func setup(p_world: Node3D, p_services: GameServices, p_game: Node = null) -> void:
	world = p_world
	services = p_services
	game = p_game
	name = "DronePresenter"
	add_to_group(GROUP)
	var st := services.state() if services != null and services.has_game() else null
	if st != null and (services.is_authority() or st.drone.is_empty()):
		DroneSystem.ensure(st)
	_root = Node3D.new()
	_root.name = "DroneWorld"
	if world != null:
		world.add_child(_root)
	else:
		add_child(_root)
	# the pad, with a solid charger cabinet
	pad_model = DroneModels.pad()
	pad_model.position = DroneSystem.pad_position(st)
	pad_model.rotation.y = DroneSystem.pad_yaw()
	_root.add_child(pad_model)
	var solid := StaticBody3D.new()
	solid.name = "ChargerSolid"
	solid.collision_layer = Layers.WORLD
	solid.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = DroneModels.CABINET_SIZE
	shape.shape = box
	shape.position = DroneModels.CABINET_CENTRE
	solid.add_child(shape)
	pad_model.add_child(solid)
	# the flying drone (its model is added by the stage presenter, or by _ensure_model)
	body = Node3D.new()
	body.name = "DroneBody"
	_root.add_child(body)
	if st != null:
		_shown_pos = DroneSystem.position(st)
		_shown_yaw = float(st.drone.get("yaw", DroneSystem.pad_yaw()))
		body.position = _shown_pos
		body.rotation.y = _shown_yaw
		_placed = true
		_report_seen = int(st.drone.get("report_n", 0))
	_set_layers(pad_model, _exterior_layers())
	# drone camera (made current only while looking through the drone)
	camera = Camera3D.new()
	camera.name = "DroneCamera"
	camera.near = 0.05
	camera.far = 3000.0
	camera.current = false
	_root.add_child(camera)
	# HUD under GameHud (hides with the HUD), else under this node
	hud_widget = DroneHudScript.new()
	var hud := game.get("hud") as Node if game != null else null
	if hud != null:
		hud.add_child(hud_widget)
	else:
		add_child(hud_widget)
	if services.net != null and not services.net.motion_extra_received.is_connected(_on_motion_extra):
		services.net.motion_extra_received.connect(_on_motion_extra)
	process_physics_priority = -1


## The presenter in the tree, or null.
static func find(tree: SceneTree) -> Node:
	return tree.get_first_node_in_group(GROUP) if tree != null else null


## True while the walking body must ignore the keys: while looking through the drone, and after E handed the drone
## back until E is let go (so the same key press does not also open the pad panel).
func blocks_player_input() -> bool:
	if piloting:
		return true
	if _hold_after_release:
		if Input.is_action_pressed(&"interact"):
			return true
		_hold_after_release = false
	return false


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if services == null or not services.has_game() or body == null:
		return
	var st := services.state()
	if st.drone.is_empty():
		DroneSystem.ensure(st)
	_ensure_model(st, delta)
	_update_pilot(st)
	_place_body(st, delta)
	_spin_rotors(st, delta)
	_update_camera()
	_update_hud(st)


func _physics_process(delta: float) -> void:
	if not piloting or services == null or not services.has_game():
		return
	var me := services.local_character()
	if me == null:
		return
	var focus := _gameplay_focus()
	var move := Vector2.ZERO
	var climb := 0.0
	if focus and controls_active:
		move = Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")
		if Input.is_action_pressed(&"jump"):
			climb += 1.0
		if Input.is_action_pressed(&"sprint") or Input.is_physical_key_pressed(KEY_CTRL):
			climb -= 1.0
	_stick = move
	var e := focus and Input.is_action_pressed(&"interact")
	if e and not _e_down:
		hand_back()
	_e_down = e
	var r := focus and Input.is_physical_key_pressed(KEY_R)
	if r and not _r_down and controls_active:
		fly_home()
	_r_down = r
	var tab := focus and Input.is_action_pressed(&"toggle_view")
	if tab and not _tab_down:
		onboard_view = not onboard_view
	_tab_down = tab
	if not piloting or not controls_active:
		return
	send_input(String(me.id), move, climb, _pilot_yaw, delta)


## Delivers the pilot's input: on the host straight to the drone system, on a client as a motion extra (~20 Hz).
func send_input(pilot_id: String, move: Vector2, climb: float, yaw: float, delta := 0.0) -> void:
	if services.is_authority():
		var system := DroneSystem.find(services.session)
		if system != null:
			system.call(&"set_input", pilot_id, move, climb, yaw)
		return
	_send_left -= delta
	if _send_left > 0.0 or services.net == null:
		return
	_send_left = 1.0 / SEND_HZ
	services.net.send_motion_extra(MOTION_KEY, {"pilot": pilot_id, "move": move, "climb": climb, "yaw": yaw})
	inputs_sent += 1


## E while flying or watching: ask the host to take the drone back. It flies home by itself.
func hand_back() -> ActionResult:
	var r := services.request(&"drone_land")
	if not r.ok and not r.pending:
		_say(r.message)
	return r


## R while flying: the drone flies home by itself now; the camera stays on it until it lands.
func fly_home() -> ActionResult:
	var r := services.request(&"drone_home")
	if not r.ok and not r.pending:
		_say(r.message)
	return r


func _unhandled_input(event: InputEvent) -> void:
	if not piloting or not (event is InputEventMouseMotion) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not _gameplay_focus():
		return
	var sens := DEFAULT_MOUSE
	var invert := false
	var p := _player()
	if p != null:
		sens = p.tuning.mouse_sensitivity
		invert = p.invert_y
	var rel := (event as InputEventMouseMotion).relative
	if controls_active:
		_pilot_yaw = wrapf(_pilot_yaw - rel.x * sens, -PI, PI)
	_cam_pitch = clampf(_cam_pitch + (1.0 if invert else -1.0) * rel.y * sens, -1.2, 0.6)


# ---------------------------------------------------------------- host: inputs from a client pilot

func _on_motion_extra(sender: int, key: String, value: Variant) -> void:
	if key != MOTION_KEY or services == null or not services.has_game():
		return
	var st := services.state()
	var id := DroneSystem.pilot(st)
	var c := st.character(StringName(id)) if id != "" else null
	if c == null or c.owner_peer != sender or not (value is Dictionary) or String((value as Dictionary).get("pilot", "")) != id:
		inputs_refused += 1
		return
	var v := value as Dictionary
	var move: Variant = v.get("move", Vector2.ZERO)
	var climb := float(v.get("climb", 0.0))
	var yaw := float(v.get("yaw", 0.0))
	if not (move is Vector2) or not (move as Vector2).is_finite() or not is_finite(climb) or not is_finite(yaw):
		inputs_refused += 1
		return
	var system := DroneSystem.find(services.session)
	if system == null:
		inputs_refused += 1
		return
	system.call(&"set_input", id, move as Vector2, climb, yaw)
	inputs_accepted += 1


# ---------------------------------------------------------------- piloting on this machine

func _update_pilot(st: ColonyState) -> void:
	var me := services.local_character()
	var mine := me != null and DroneSystem.watcher(st) == String(me.id)
	if mine and not piloting:
		_start_piloting(st)
	elif not mine and piloting:
		_stop_piloting()
	var sticks := mine and DroneSystem.pilot(st) == String(me.id)
	if sticks and not controls_active:
		_pilot_yaw = float(st.drone.get("yaw", 0.0))
	controls_active = sticks
	if not controls_active:
		_stick = Vector2.ZERO


func _start_piloting(st: ColonyState) -> void:
	piloting = true
	onboard_view = String(DroneSystem.data().get("start_view", "chase")) == "fpv"
	_pilot_yaw = float(st.drone.get("yaw", 0.0))
	_shown_yaw = _pilot_yaw
	_cam_pitch = -0.3
	_e_down = Input.is_action_pressed(&"interact")      # the press that started it does not hand it back
	_tab_down = Input.is_action_pressed(&"toggle_view")
	_r_down = Input.is_physical_key_pressed(KEY_R)
	_report_seen = int(st.drone.get("report_n", 0))
	var p := _player()
	if p != null:
		var cam := p.camera_rig().camera()
		camera.fov = cam.fov
		camera.cull_mask = cam.cull_mask | Layers.render_bit(Layers.RENDER_FIRST_PERSON_HIDDEN)
		camera.environment = cam.environment
		camera.attributes = cam.attributes
	camera.current = true
	_update_camera()


func _stop_piloting() -> void:
	piloting = false
	controls_active = false
	camera.current = false
	_hold_after_release = Input.is_action_pressed(&"interact")
	var p := _player()
	if p != null:
		p.set_first_person(p.is_first_person())     # gives the player's own camera back
	if hud_widget != null:
		hud_widget.call(&"hide_flight")


func _update_camera() -> void:
	if not piloting or camera == null or not camera.is_inside_tree():
		return
	var yaw_basis := Basis(Vector3.UP, _shown_yaw)
	if onboard_view:
		# FPV: the camera rides the nose and tilts with the model (the example's PitchPivot/FPV)
		var marker := body.find_child("Camera", true, false) as Node3D
		var at := marker.global_position if marker != null else body.global_position + yaw_basis * Vector3(0, 0.25, -0.2)
		camera.global_transform = Transform3D(yaw_basis * Basis(Vector3.RIGHT, clampf(FPV_LOOK_DOWN + _cam_pitch + 0.3 + _tilt, -1.3, 0.8)), at)
		return
	# chase: behind and above, not tilted by the stick (the example's ChaseArm)
	var offset := yaw_basis * (Basis(Vector3.RIGHT, _cam_pitch) * Vector3(0.0, 0.0, CHASE_DISTANCE_M)) + Vector3(0.0, CHASE_LIFT_M, 0.0)
	var pos := body.global_position + offset
	pos.y = maxf(pos.y, DroneSystem.ground(pos.x, pos.z) + 0.4)
	var look := body.global_position + Vector3(0.0, 0.35, 0.0)
	if pos.distance_to(look) > 0.05:
		camera.global_transform = Transform3D(Basis.IDENTITY, pos).looking_at(look, Vector3.UP)


func _update_hud(st: ColonyState) -> void:
	if hud_widget == null:
		return
	if not piloting:
		if bool(hud_widget.call(&"is_showing")):
			hud_widget.call(&"hide_flight")
		_report_seen = int(st.drone.get("report_n", 0))
		return
	var d := st.drone
	var warning := ""
	match DroneSystem.range_state(st):
		"edge":
			warning = "EDGE OF RADIO RANGE"
		"warn":
			warning = "NEAR RADIO RANGE EDGE"
	var mission: Dictionary = d.get("mission", {})
	var total := int(d.get("targets_total", 0))
	var done := int(d.get("targets_done", 0))
	var label := ""
	if total > 0:
		label = "%s %02d / %02d" % [String(mission.get("mode", "route")).to_upper(), mini(done, total), total]
	else:
		var found := (d.get("found", []) as Array).size()
		label = "FOUND %02d" % found if DroneSystem.has_ability(st, "prescout") else ""
		total = found
		done = found
	var status := DroneSystem.status(st)
	var info := {
		"level": DroneSystem.level(st),
		"mode": "MANUAL" if status == "manual" else "AUTO",
		"returning": status == "returning",
		"chase": not onboard_view,
		"heading": DroneSystem.heading_deg(_shown_yaw),
		"battery": DroneSystem.battery(st),
		"seconds_left": DroneSystem.seconds_left(st),
		"ground_speed": DroneSystem.ground_speed(st),
		"home_m": DroneSystem.distance_from_pad(st),
		"alt_m": DroneSystem.altitude(st),
		"flight_s": float(d.get("flight_s", 0.0)),
		"targets_total": total,
		"targets_done": done,
		"targets_label": label,
		"warning": warning,
		"keys": keys_text() if status == "manual" else "%s  CAMERA    %s  HAND BACK" % [_key(&"toggle_view", "Tab").to_upper(), _key(&"interact", "E").to_upper()],
	}
	hud_widget.call(&"show_flight", info)
	var n := int(d.get("report_n", 0))
	if n != _report_seen:
		_report_seen = n
		var rep: Dictionary = d.get("last_report", {})
		if not rep.is_empty():
			hud_widget.call(&"show_report", String(rep.get("name", "Report")), String(rep.get("text", "")))


## The keys while flying, from the player's own bindings (OSD style).
static func keys_text() -> String:
	return "%s  MOVE    MOUSE  TURN    %s  UP    CTRL  DOWN    %s  CAMERA    R  FLY HOME    %s  HAND BACK" % [
		_keys_of([&"move_forward", &"move_left", &"move_back", &"move_right"]).to_upper(), _key(&"jump", "Space").to_upper(),
		_key(&"toggle_view", "Tab").to_upper(), _key(&"interact", "E").to_upper()]


static func _key(action: StringName, fallback: String) -> String:
	var t := PlayerInput.describe(action)
	return t if t != "" else fallback


static func _keys_of(actions: Array) -> String:
	var parts := PackedStringArray()
	for a: StringName in actions:
		parts.append(_key(a, "?"))
	return "".join(parts)


# ---------------------------------------------------------------- the model

## The level's model rides on `body`: put there by the scout_drone stage presenter when it exists, else built here.
func _ensure_model(st: ColonyState, delta: float) -> void:
	_staged_check -= delta
	if _staged_check <= 0.0:
		_staged_check = 1.0
		_staged = _stage_presenter_present()
	if _staged:
		if _fallback != null:
			_fallback.queue_free()
			_fallback = null
			_fallback_level = 0
		return
	var lvl := DroneSystem.level(st)
	if _fallback != null and _fallback_level == lvl:
		return
	if _fallback != null:
		_fallback.queue_free()
	_fallback = DroneModels.drone(lvl)
	_fallback.name = "DroneFallback"
	_fallback_level = lvl
	body.add_child(_fallback)
	_set_layers(_fallback, _exterior_layers())


func _stage_presenter_present() -> bool:
	if not is_inside_tree():
		return false
	for n in get_tree().get_nodes_in_group(&"area_stage_presenters"):
		if n is AreaStagePresenter and (n as AreaStagePresenter).track_id() == DroneSystem.TRACK:
			return true
	return false


## The model of the level now riding on the body (a Stage_V<n> or the fallback), or null.
func model() -> Node3D:
	for c in body.get_children():
		if c is Node3D and not (c as Node).is_queued_for_deletion():
			return c as Node3D
	return null


## Rotor hub nodes of the model now shown.
func rotors() -> Array[Node3D]:
	var m := model()
	var sig := str(m.get_instance_id()) if m != null else ""
	if sig != _rotor_sig:
		_rotor_sig = sig
		_rotors = DroneModels.rotors(m)
	return _rotors


func _place_body(st: ColonyState, delta: float) -> void:
	var target := DroneSystem.position(st)
	var vel := DroneSystem._v3(st.drone.get("vel", []))
	var key := str(st.drone.get("position", []))
	if key != _last_key:
		_last_key = key
		_since_update = 0.0
	else:
		_since_update += delta
	var docked := DroneSystem.status(st) == "docked"
	var predicted := target + vel * minf(_since_update, 0.3)
	if not _placed or predicted.distance_to(_shown_pos) > 25.0 or docked:
		_shown_pos = predicted if not docked else target
		_placed = true
	else:
		_shown_pos = _shown_pos.lerp(predicted, 1.0 - exp(-delta * 10.0))
	var yaw := float(st.drone.get("yaw", 0.0))
	var yaw_goal := _pilot_yaw if controls_active else yaw
	_shown_yaw = lerp_angle(_shown_yaw, yaw_goal, 1.0 - exp(-delta * (YAW_RESPONSE if controls_active else 6.0)))
	body.position = _shown_pos
	# the example's tilt: nose down 7° pushing forward, up 5° pulling back, eased with the pitch response
	var forward := _stick.y
	if not controls_active:
		var local := Basis(Vector3.UP, _shown_yaw).inverse() * vel
		forward = clampf(-local.z / maxf(0.5, DroneSystem.speed_mps(st)), -1.0, 1.0)
	if docked:
		forward = 0.0
	var limit := DroneSystem.num("forward_pitch_deg", 7.0) if forward > 0.0 else DroneSystem.num("reverse_pitch_deg", 5.0)
	_tilt = lerpf(_tilt, -deg_to_rad(limit) * forward, 1.0 - exp(-PITCH_RESPONSE * delta))
	body.rotation = Vector3(_tilt, _shown_yaw, 0.0)


func _spin_rotors(st: ColonyState, delta: float) -> void:
	var want := ROTOR_SPEED if DroneSystem.is_flying(st) else 0.0
	_spin = move_toward(_spin, want, delta * 40.0)
	if _spin <= 0.0:
		return
	for r in rotors():
		if not is_instance_valid(r):
			continue
		var n := String(r.name)
		var dir := 1.0 if (n.ends_with("FR") or n.ends_with("BL")) else -1.0
		r.rotate_object_local(Vector3.UP, dir * _spin * delta)


## Rotor speed now (rad/s; tests).
func rotor_speed() -> float:
	return _spin


## Model tilt now (rad, negative = nose down; tests).
func tilt() -> float:
	return _tilt


# ---------------------------------------------------------------- helpers

func _player() -> PlayerController:
	return game.get("player") as PlayerController if game != null else null


func _gameplay_focus() -> bool:
	var ui := game.get("ui") as UiRoot if game != null else null
	return ui == null or ui.gameplay_has_focus()


func _say(text: String) -> void:
	var hud := game.get("hud") as GameHud if game != null else null
	if hud != null and text != "":
		hud.show_message(text, 3.5)


func _exterior_layers() -> int:
	if services == null or services.zones == null:
		return 1
	var z := services.zones
	var mask := z.bit_of(ColonyZones.EXTERIOR) | z.sun_bit()
	return mask if mask != 0 else 1


static func _set_layers(n: Node, mask: int) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = mask
	for c in n.get_children():
		_set_layers(c, mask)
