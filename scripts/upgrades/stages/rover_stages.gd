extends AreaStagePresenter
## Look of the "rover" upgrade path (data/area_levels.json). The rover's level is never bought: it follows the five
## garage modules (state.rover.levels, each 1..5, AreaLevels.rover_level() turns them into V1..V4). This presenter
## shows EVERY module's level on the rover body, plus the overall V level:
##   range (battery pack)       side battery packs on the fender ledge, one more per side for each level (1..4 packs),
##                              each with a glowing charge bar; an orange power cable joins them from level 3
##   speed (drive motor)        a motor housing on every wheel hub that grows with the level; cooling fins from level 3,
##                              a ring round the fins from 4, a glowing vent from 5
##   torque (wheel gearboxes)   an eight-sided axle cover behind each motor that grows and gets more bolts; a yellow
##                              heavy-duty ring from 4, a second, wider back plate with ribs at 5
##   cargo (cargo frame)        a side rack on the rear half of the cabin: left rack with one crate (2), racks on both
##                              sides with two crates each (3), taller racks with three crates and straps (4), then
##                              closed cargo pods on both sides (5)
##   traction (tyres)           a chunky tread band round each tyre: more and taller lugs per level, the tyre grows
##                              wider outward from 3, shoulder blocks from 4, steel studs and a yellow rim at 5
##   V level                    glowing rank bars on both front sides and the front bumper (V2 one bar, V3 two, V4
##                              three); V3 adds a roof light bar and an antenna mast with a red beacon; V4 adds dust
##                              guards (wheel flares and mud flaps) and a full roll cage
## Everything is built procedurally into ONE MeshInstance3D per build (one surface per material, about ten draw calls),
## parented to the moving RoverBody so it rides with the rover, and kept on the same render layers as the rover's own
## mesh as it drives between zones. Visual only: no collision shape, no physics body, no mass change (the module masses
## live in RoverBalance and RoverModel.rover_mass_kg). All sizes are designer choices fitted to the map mesh sf_rover
## (body frame of data/rover.json: origin on the ground under the middle axle, -Z forward, +X right, +Y up).

const MODULES: PackedStringArray = ["speed", "torque", "range", "cargo", "traction"]
const ROVER_META := &"vehicle_id"

## Tests: module levels to show instead of the colony's (empty = follow state.rover.levels).
var force_modules: Dictionary = {}
## Tests: the body to ride on instead of the game's rover (null = find it).
var rover_body_override: Node3D

## What is on screen now: module levels, V level and the body it rides on.
var built_modules: Dictionary = {}
var built_body: Node3D
var _built_sig := ""
var _body_cache: Node3D


func track_id() -> String:
	return "rover"


# ---------------------------------------------------------------- level, modules and body

## Module levels to show (1..5 each).
func modules() -> Dictionary:
	var out := {}
	var src: Dictionary = force_modules
	if src.is_empty() and services != null and services.has_game():
		src = services.state().rover.get("levels", {})
	for m: String in MODULES:
		out[m] = clampi(int(src.get(m, 1)), 1, 5)
	return out


func current_level() -> int:
	if force_level >= 1:
		return force_level
	if not force_modules.is_empty():
		return AreaLevels.rover_level(modules())
	return super.current_level()


## The moving rover body the parts ride on, or null (tests without a rover).
func rover_body() -> Node3D:
	if rover_body_override != null and is_instance_valid(rover_body_override):
		return rover_body_override
	if game != null:
		var rp: Variant = game.get("rover")
		if rp is RoverPresenter and (rp as RoverPresenter).body != null:
			return (rp as RoverPresenter).body
	if _body_cache != null and is_instance_valid(_body_cache) and _body_cache.is_inside_tree():
		return _body_cache
	_body_cache = null
	if is_inside_tree():
		for n in get_tree().root.find_children("*", "RigidBody3D", true, false):
			if n.get_meta(ROVER_META, &"") == &"rover":
				_body_cache = n as Node3D
				break
	return _body_cache


func stage_parent() -> Node:
	var b := rover_body()
	return b if b != null else super.stage_parent()


func build_stage(level: int) -> Node3D:
	return build_parts(modules(), level)


# ---------------------------------------------------------------- rebuild on any module change

func refresh() -> void:
	_poll = 0.0
	_rebuild()


func _process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = POLL_SECONDS
		if _signature() != _built_sig:
			_rebuild()
		else:
			sync_layers()
	if _grow > 0.0 and _stage != null:
		_grow = maxf(0.0, _grow - delta)
		var t := 1.0 - _grow / GROW_SECONDS
		_stage.scale = Vector3.ONE * (0.85 + 0.15 * (1.0 - pow(1.0 - t, 3.0)))


func _signature() -> String:
	var m := modules()
	var b := rover_body()
	return "%d|%d%d%d%d%d|%d" % [current_level(), m.speed, m.torque, m.range, m.cargo, m.traction, b.get_instance_id() if b != null else 0]


func _rebuild() -> void:
	var had := _stage != null
	if _stage != null:
		_stage.queue_free()
		_stage = null
	_grow = 0.0
	var lvl := current_level()
	shown_level = lvl
	built_modules = modules()
	built_body = rover_body()
	_built_sig = _signature()
	if lvl <= 0:
		return
	var node := build_stage(lvl)
	if node == null:
		return
	node.name = "Stage_V%d" % lvl
	var parent: Node = stage_parent()
	parent.add_child(node)
	if built_body == null and parent is Node3D:
		node.transform = _parked_transform()     # no body: stand where the rover is parked
	_stage = node
	put_on_zone_layers(node)
	if had:
		_grow = GROW_SECONDS
		node.scale = Vector3.ONE * 0.85


## Without a body (tests, tools): the parts stand at the rover's saved pose, else its garage park pose.
func _parked_transform() -> Transform3D:
	var pose := {}
	if services != null and services.has_game():
		pose = RoverBody.from_state_pose(services.state().rover.get("pose", {}))
	if pose.is_empty():
		pose = RoverBody.from_state_pose(RoverBody.load_data().get("garage_park_pose", {}))
	if pose.is_empty():
		return Transform3D.IDENTITY
	return Transform3D(Basis(pose.q as Quaternion), pose.p as Vector3)


# ---------------------------------------------------------------- render layers follow the rover's own mesh

## Render layers of the rover's drawn mesh (what the parts copy), or 0 when there is no drawn rover.
func body_layers() -> int:
	var b := rover_body()
	if b == null:
		return 0
	var vis: Node = (b as RoverBody).visual() if b is RoverBody else null
	if vis != null:
		if vis is VisualInstance3D:
			return (vis as VisualInstance3D).layers
		for n in vis.find_children("*", "VisualInstance3D", true, false):
			return (n as VisualInstance3D).layers
	return layers_at(b.global_position)


func put_on_zone_layers(n: Node) -> void:
	var mask := body_layers()
	if mask == 0:
		super.put_on_zone_layers(n)
		return
	_set_layers(n, mask)


## Copies the rover mesh's layers onto the parts again if they changed (called every poll).
func sync_layers() -> void:
	if _stage == null:
		return
	var mask := body_layers()
	if mask != 0:
		_set_layers(_stage, mask)


static func _set_layers(n: Node, mask: int) -> void:
	if n is VisualInstance3D and (n as VisualInstance3D).layers != mask:
		(n as VisualInstance3D).layers = mask
	for c in n.get_children():
		_set_layers(c, mask)


# ---------------------------------------------------------------- the parts (static: tools and tests use it too)

## Geometry of the map rover (data/rover.json and measured from sf_rover, body frame).
const TYRE_R := 0.525
const TYRE_IN := 1.1
const TYRE_OUT := 1.5
const LEDGE_Y := 1.1          # top of the white fender ledge that runs along both sides over the wheels
const WALL_X := 1.13          # cabin side wall
const ROOF_Y := 2.84          # roof (solar panels at 2.84..2.87)

# per level tables, index = level - 1 (designer choices)
const TRACTION_OUT := [0.0, 0.0, 0.02, 0.04, 0.06]       # tyre grows outward, m
const TRACTION_R := [0.0, 0.0, 0.008, 0.016, 0.024]      # tread band radius above TYRE_R - 0.015, m
const TRACTION_LUGS := [0, 14, 16, 18, 20]
const TRACTION_LUG_H := [0.0, 0.035, 0.04, 0.045, 0.05]
const GEAR_R := [0.0, 0.24, 0.28, 0.32, 0.35]
const GEAR_T := [0.0, 0.035, 0.04, 0.045, 0.05]
const GEAR_BOLTS := [0, 5, 6, 8, 8]
const MOTOR_R := [0.0, 0.12, 0.15, 0.18, 0.2]
const MOTOR_L := [0.0, 0.06, 0.08, 0.1, 0.11]
const MOTOR_FINS := [0, 0, 6, 8, 10]
const MOTOR_FIN_L := [0.0, 0.0, 0.07, 0.09, 0.1]
const CARGO_CRATES := [[0, 0], [1, 0], [2, 2], [3, 3], [0, 0]]   # [left, right] crates per cargo level
const CARGO_TOP := [0.0, 2.25, 2.4, 2.55, 2.5]
const CARGO_Z := Vector2(0.85, 2.25)

const COLOURS := {
	"paint": [Color(0.86, 0.86, 0.83), 0.0, 0.5, 0.0],
	"dark": [Color(0.16, 0.17, 0.19), 0.5, 0.45, 0.0],
	"steel": [Color(0.62, 0.64, 0.67), 0.85, 0.3, 0.0],
	"orange": [Color(0.92, 0.4, 0.08), 0.0, 0.5, 0.0],
	"rubber": [Color(0.05, 0.05, 0.055), 0.0, 0.95, 0.0],
	"yellow": [Color(0.95, 0.74, 0.1), 0.0, 0.5, 0.0],
	"battery": [Color(0.13, 0.2, 0.33), 0.3, 0.45, 0.0],
	"crate": [Color(0.78, 0.52, 0.22), 0.0, 0.7, 0.0],
	"glow_cyan": [Color(0.25, 0.9, 1.0), 0.0, 0.4, 2.5],
	"glow_amber": [Color(1.0, 0.6, 0.1), 0.0, 0.4, 3.0],
	"glow_red": [Color(1.0, 0.15, 0.08), 0.0, 0.4, 3.0],
	"lamp": [Color(1.0, 0.97, 0.88), 0.0, 0.3, 4.0],
}


## All add-on parts for these module levels and this V level, as one Node3D holding one merged MeshInstance3D in the
## rover body frame, or null when there is nothing to add (the stock rover). Its meta "part_counts" gives the
## triangles per group (speed, torque, range, cargo, traction, rank, v3, v4) for tests.
static func build_parts(levels: Dictionary, v_level: int) -> Node3D:
	var lv := {}
	for m: String in MODULES:
		lv[m] = clampi(int(levels.get(m, 1)), 1, 5)
	var k := Kit.new()
	for w: Vector3 in wheel_centres():
		_tyre(k, w, lv.traction)
		var face := _hub_face(w, lv.traction)
		face = _gearbox(k, w, face, lv.torque, lv.speed)
		_motor(k, w, face, lv.speed)
	_batteries(k, lv.range)
	_cargo(k, lv.cargo)
	_rank(k, v_level)
	if v_level >= 3:
		_light_bar(k, v_level)
		_mast(k)
	if v_level >= 4:
		for w: Vector3 in wheel_centres():
			_dust_guard(k, w, lv.traction)
		_roll_cage(k)
	if k.triangles() == 0:
		return null
	var root := Node3D.new()
	root.name = "RoverParts"
	var mi := MeshInstance3D.new()
	mi.name = "Parts"
	mi.mesh = k.commit()
	root.add_child(mi)
	root.set_meta(&"part_counts", k.groups.duplicate())
	root.set_meta(&"modules", lv)
	root.set_meta(&"v_level", v_level)
	return root


static func wheel_centres() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for w: Dictionary in RoverBody.load_data().get("wheels", []):
		out.append(RoverBody._v3(w.position))
	if out.is_empty():
		for z: float in [-1.55, 0.0, 1.55]:
			out.append(Vector3(-1.3, TYRE_R - 0.025, z))
			out.append(Vector3(1.3, TYRE_R - 0.025, z))
	return out


static func _side(w: Vector3) -> float:
	return 1.0 if w.x >= 0.0 else -1.0


## |x| of the outer tyre face for this traction level.
static func _hub_face(_w: Vector3, traction: int) -> float:
	return TYRE_OUT + float(TRACTION_OUT[traction - 1]) + (0.01 if traction >= 2 else 0.0)


## Basis that turns local +Y into the wheel axle (outward along X on side `s`).
static func _axle(s: float) -> Basis:
	return Basis(Vector3.BACK, -PI * 0.5 * s)


static func _tyre(k: Kit, w: Vector3, t: int) -> void:
	if t < 2:
		return
	k.group = "traction"
	var s := _side(w)
	var inner := TYRE_IN - 0.02
	var outer := _hub_face(w, t)
	var width := outer - inner
	var r0 := TYRE_R - 0.015 + float(TRACTION_R[t - 1])
	var mid := Vector3(s * (inner + outer) * 0.5, w.y, w.z)
	var ax := _axle(s)
	# band over the old tread, and new sidewalls (the old rim stays visible inside 0.34 m)
	k.cylinder("rubber", Transform3D(ax, mid), r0, r0, width, 28, false, true)
	k.ring("rubber", Transform3D(ax, Vector3(s * (outer - 0.01), w.y, w.z)), 0.34, r0, 0.02, 28)
	k.ring("rubber", Transform3D(ax, Vector3(s * (inner + 0.01), w.y, w.z)), 0.34, r0, 0.02, 28)
	var n: int = TRACTION_LUGS[t - 1]
	var h: float = TRACTION_LUG_H[t - 1]
	var half := width * 0.5
	for i in n:
		for j in 2:
			# chevron tread: two staggered half-width lugs
			var a := TAU * (float(i) + 0.5 * float(j)) / float(n)
			var lug_w := half + 0.05
			var cx := (inner + lug_w * 0.5) if j == 0 else (outer - lug_w * 0.5)
			var rot := Basis(Vector3.RIGHT, a)
			var p := Vector3(s * cx, w.y, w.z) + rot * Vector3(0.0, r0 + h * 0.5, 0.0)
			k.box("rubber", Transform3D(rot, p), Vector3(lug_w, h, 0.1 + 0.01 * t))
			if t >= 4 and j == 1:
				# shoulder block running down the outer sidewall
				var q := Vector3(s * (outer + 0.012), w.y, w.z) + rot * Vector3(0.0, r0 - 0.06, 0.0)
				k.box("rubber", Transform3D(rot, q), Vector3(0.025, 0.11, 0.09))
			if t >= 5 and j == 0:
				var stud := Vector3(s * cx, w.y, w.z) + rot * Vector3(0.0, r0 + h + 0.007, 0.0)
				k.box("steel", Transform3D(rot, stud), Vector3(0.05, 0.015, 0.05))
	if t >= 5:
		k.ring("yellow", Transform3D(ax, Vector3(s * (outer + 0.005), w.y, w.z)), 0.34, 0.38, 0.02, 28)


## Axle cover (gearbox) on the hub. Returns the |x| where the motor housing starts.
static func _gearbox(k: Kit, w: Vector3, face: float, g: int, speed: int) -> float:
	if g < 2:
		return face
	k.group = "torque"
	var s := _side(w)
	var ax := _axle(s)
	var r: float = GEAR_R[g - 1]
	var t: float = GEAR_T[g - 1]
	var x := face
	if g >= 5:
		# a wider, thin back plate with ribs: the heavy-duty gearbox
		k.cylinder("dark", Transform3D(ax, Vector3(s * (x + 0.01), w.y, w.z)), r + 0.06, r + 0.06, 0.02, 8, true, false)
		for i in 8:
			var a := TAU * (float(i) + 0.5) / 8.0
			var rot := Basis(Vector3.RIGHT, a)
			var p := Vector3(s * (x + 0.04 + t * 0.5), w.y, w.z) + rot * Vector3(0.0, r * 0.62, 0.0)
			k.box("dark", Transform3D(rot, p), Vector3(t + 0.02, r * 0.75, 0.03))
		x += 0.02
	k.cylinder("dark", Transform3D(ax, Vector3(s * (x + t * 0.5), w.y, w.z)), r, r, t, 8, true, false)
	var bolts: int = GEAR_BOLTS[g - 1]
	for i in bolts:
		var a := TAU * float(i) / float(bolts)
		var rot := Basis(Vector3.RIGHT, a)
		var p := Vector3(s * (x + t + 0.012), w.y, w.z) + rot * Vector3(0.0, r - 0.05, 0.0)
		k.cylinder("steel", Transform3D(ax, p), 0.024, 0.024, 0.025, 6, true, false)
	if g >= 4:
		k.ring("yellow", Transform3D(ax, Vector3(s * (x + t + 0.008), w.y, w.z)), r * 0.58, r * 0.72, 0.016, 24)
	if speed < 2:
		# no motor housing: a nut cap closes the axle end
		k.cylinder("steel", Transform3D(ax, Vector3(s * (x + t + 0.025), w.y, w.z)), 0.08, 0.08, 0.05, 6, true, false)
	return x + t


static func _motor(k: Kit, w: Vector3, face: float, m: int) -> void:
	if m < 2:
		return
	k.group = "speed"
	var s := _side(w)
	var ax := _axle(s)
	var r: float = MOTOR_R[m - 1]
	var l: float = MOTOR_L[m - 1]
	k.cylinder("orange", Transform3D(ax, Vector3(s * (face + l * 0.5), w.y, w.z)), r, r * 0.92, l, 20, true, true)
	k.cylinder("steel", Transform3D(ax, Vector3(s * (face + l + 0.01), w.y, w.z)), r * 0.7, r * 0.7, 0.02, 20, true, true)
	k.cylinder("dark", Transform3D(ax, Vector3(s * (face + l + 0.03), w.y, w.z)), r * 0.25, r * 0.25, 0.03, 6, true, false)
	var fins: int = MOTOR_FINS[m - 1]
	var fl: float = MOTOR_FIN_L[m - 1]
	for i in fins:
		var a := TAU * float(i) / float(fins)
		var rot := Basis(Vector3.RIGHT, a)
		var p := Vector3(s * (face + l * 0.45), w.y, w.z) + rot * Vector3(0.0, r + fl * 0.5 - 0.01, 0.0)
		k.box("dark", Transform3D(rot, p), Vector3(l * 0.85, fl, 0.02))
	if m >= 4:
		k.ring("steel", Transform3D(ax, Vector3(s * (face + l * 0.45), w.y, w.z)), r + fl - 0.02, r + fl + 0.005, l * 0.5, 24)
	if m >= 5:
		k.ring("glow_amber", Transform3D(ax, Vector3(s * (face + l + 0.022), w.y, w.z)), r * 0.38, r * 0.6, 0.012, 20)


## Battery packs on the fender ledge: (range level - 1) per side.
static func _batteries(k: Kit, r: int) -> void:
	var n := r - 1
	if n < 1:
		return
	k.group = "range"
	var length := 0.8
	for s: float in [-1.0, 1.0]:
		var zs: Array[float] = []
		for i in n:
			zs.append(0.25 + (float(i) - float(n - 1) * 0.5) * 0.9)
		for z: float in zs:
			var c := Vector3(s * 1.3, LEDGE_Y + 0.11, z)
			k.box("battery", Transform3D(Basis(), c), Vector3(0.3, 0.22, length))
			k.box("dark", Transform3D(Basis(), c + Vector3(0.0, 0.125, 0.0)), Vector3(0.26, 0.03, length - 0.06))
			for e: float in [-1.0, 1.0]:
				k.box("steel", Transform3D(Basis(), c + Vector3(0.0, 0.0, e * (length * 0.5 + 0.01))), Vector3(0.32, 0.24, 0.03))
			for rib in 3:
				k.box("dark", Transform3D(Basis(), c + Vector3(s * 0.151, 0.0, (float(rib) - 1.0) * 0.22)), Vector3(0.012, 0.18, 0.04))
			# charge bar on the outer face
			k.box("glow_cyan", Transform3D(Basis(), c + Vector3(s * 0.155, 0.045, 0.0)), Vector3(0.012, 0.045, length * 0.72))
			# terminal on top
			k.cylinder("orange", Transform3D(Basis(), c + Vector3(-s * 0.07, 0.16, length * 0.3)), 0.03, 0.03, 0.05, 8, true, true)
		if n >= 2:
			var a := Vector3(s * 1.23, LEDGE_Y + 0.27, zs[0] + length * 0.3)
			var b := Vector3(s * 1.23, LEDGE_Y + 0.27, zs[n - 1] + length * 0.3)
			k.tube("orange", a, b, 0.022, 8)


static func _crate(k: Kit, c: Vector3) -> void:
	k.box("crate", Transform3D(Basis(), c), Vector3(0.3, 0.34, 0.4))
	k.box("dark", Transform3D(Basis(), c + Vector3(0.0, 0.08, 0.0)), Vector3(0.31, 0.04, 0.41))
	k.box("dark", Transform3D(Basis(), c + Vector3(0.0, 0.0, 0.0)), Vector3(0.305, 0.345, 0.04))


static func _cargo(k: Kit, c: int) -> void:
	if c < 2:
		return
	k.group = "cargo"
	var z0 := CARGO_Z.x
	var z1 := CARGO_Z.y
	var zc := (z0 + z1) * 0.5
	var length := z1 - z0
	var shelf_y := LEDGE_Y + 0.37
	for s: float in [-1.0, 1.0]:
		if c == 2 and s > 0.0:
			continue
		if c >= 5:
			_pod(k, s, z0, z1, shelf_y)
			continue
		var top: float = CARGO_TOP[c - 1]
		# shelf and its brackets to the wall
		k.box("dark", Transform3D(Basis(), Vector3(s * 1.32, shelf_y, zc)), Vector3(0.36, 0.03, length))
		for z: float in [z0 + 0.08, z1 - 0.08]:
			k.tube("dark", Vector3(s * WALL_X, shelf_y - 0.18, z), Vector3(s * 1.47, shelf_y - 0.01, z), 0.018, 6)
		# posts and rails
		var posts: Array[float] = [z0 + 0.03, zc, z1 - 0.03]
		for z: float in posts:
			k.tube("steel", Vector3(s * 1.48, shelf_y, z), Vector3(s * 1.48, top, z), 0.02, 8)
			k.tube("steel", Vector3(s * 1.48, top, z), Vector3(s * WALL_X, top + 0.02, z), 0.016, 6)
		k.tube("steel", Vector3(s * 1.48, top, z0 + 0.03), Vector3(s * 1.48, top, z1 - 0.03), 0.02, 8)
		if c >= 3:
			var mid_y := (shelf_y + top) * 0.5
			k.tube("steel", Vector3(s * 1.48, mid_y, z0 + 0.03), Vector3(s * 1.48, mid_y, z1 - 0.03), 0.016, 8)
		var crates: int = (CARGO_CRATES[c - 1] as Array)[0 if s < 0.0 else 1]
		var slots: Array[Vector3] = [Vector3(s * 1.3, shelf_y + 0.185, z0 + 0.32), Vector3(s * 1.3, shelf_y + 0.185, z1 - 0.32),
			Vector3(s * 1.3, shelf_y + 0.535, z0 + 0.32)]
		for i in mini(crates, slots.size()):
			_crate(k, slots[i])
		if c >= 4:
			# yellow straps holding the load
			for z: float in [z0 + 0.32, z1 - 0.32]:
				k.box("yellow", Transform3D(Basis(), Vector3(s * 1.462, (shelf_y + top) * 0.5, z)), Vector3(0.012, top - shelf_y - 0.04, 0.05))


static func _pod(k: Kit, s: float, z0: float, z1: float, y0: float) -> void:
	var zc := (z0 + z1) * 0.5
	var length := z1 - z0
	var y1 := 2.5
	var yc := (y0 + y1) * 0.5
	var r := 0.08
	k.box("paint", Transform3D(Basis(), Vector3(s * (WALL_X + 1.55 - r) * 0.5, yc, zc)), Vector3(1.55 - r - WALL_X, y1 - y0, length))
	k.box("paint", Transform3D(Basis(), Vector3(s * (WALL_X + 1.55) * 0.5, yc, zc)), Vector3(1.55 - WALL_X, y1 - y0 - 2.0 * r, length))
	var along := Basis(Vector3.RIGHT, PI * 0.5)
	for y: float in [y0 + r, y1 - r]:
		k.cylinder("paint", Transform3D(along, Vector3(s * (1.55 - r), y, zc)), r, r, length, 12, true, true)
	# end caps a little inset, stripe, lid seam, latches, hinge and a marker lamp
	for e: float in [-1.0, 1.0]:
		k.box("dark", Transform3D(Basis(), Vector3(s * (WALL_X + 1.55) * 0.5, yc, zc + e * (length * 0.5 + 0.01))), Vector3(1.55 - WALL_X - 0.04, y1 - y0 - 0.04, 0.02))
	k.box("orange", Transform3D(Basis(), Vector3(s * 1.553, yc - 0.05, zc)), Vector3(0.012, 0.12, length - 0.02))
	k.box("dark", Transform3D(Basis(), Vector3(s * 1.553, y1 - 0.24, zc)), Vector3(0.01, 0.015, length - 0.02))
	for z: float in [z0 + 0.3, z1 - 0.3]:
		k.box("steel", Transform3D(Basis(), Vector3(s * 1.565, y1 - 0.3, z)), Vector3(0.03, 0.08, 0.12))
	k.tube("steel", Vector3(s * 1.44, y1 + 0.005, z0 + 0.1), Vector3(s * 1.44, y1 + 0.005, z1 - 0.1), 0.015, 6)
	k.box("glow_amber", Transform3D(Basis(), Vector3(s * 1.45, y1 - 0.12, z1 + 0.02)), Vector3(0.08, 0.06, 0.02))
	k.box("dark", Transform3D(Basis(), Vector3(s * 1.32, y0 - 0.02, zc)), Vector3(0.38, 0.04, length))


## Rank bars: V level - 1 glowing bars on both front sides and on the front bumper.
static func _rank(k: Kit, v: int) -> void:
	var bars := clampi(v - 1, 0, 3)
	if bars < 1:
		return
	k.group = "rank"
	for s: float in [-1.0, 1.0]:
		k.box("dark", Transform3D(Basis(), Vector3(s * 1.118, 1.45, -1.77)), Vector3(0.02, 0.2, 0.46))
		for i in bars:
			k.box("glow_amber", Transform3D(Basis(), Vector3(s * 1.13, 1.45, -1.92 + 0.14 * float(i))), Vector3(0.012, 0.14, 0.08))
	k.box("dark", Transform3D(Basis(), Vector3(0.0, 0.58, -2.615)), Vector3(0.62, 0.16, 0.02))
	for i in bars:
		k.box("glow_amber", Transform3D(Basis(), Vector3(-0.2 + 0.2 * float(i), 0.58, -2.628)), Vector3(0.14, 0.1, 0.012))


## V3: a roof light bar over the cab (raised further at V4 to sit on the roll cage).
static func _light_bar(k: Kit, v: int) -> void:
	k.group = "v3"
	var y := 3.08 if v < 4 else 3.16
	var z := -1.62
	for s: float in [-1.0, 1.0]:
		k.tube("dark", Vector3(s * 0.85, ROOF_Y - 0.04, -1.5), Vector3(s * 0.85, y - 0.05, z), 0.025, 8)
	k.box("dark", Transform3D(Basis(), Vector3(0.0, y, z)), Vector3(1.94, 0.14, 0.16))
	for i in 6:
		k.box("lamp", Transform3D(Basis(), Vector3(-0.75 + 0.3 * float(i), y, z - 0.085)), Vector3(0.22, 0.09, 0.012))
	for s: float in [-1.0, 1.0]:
		k.box("glow_amber", Transform3D(Basis(), Vector3(s * 0.95, y, z - 0.03)), Vector3(0.05, 0.1, 0.1))


## V3: antenna mast with a red beacon at the rear left of the roof.
static func _mast(k: Kit) -> void:
	k.group = "v3"
	var base := Vector3(-0.92, ROOF_Y - 0.05, 1.35)
	k.box("dark", Transform3D(Basis(), base + Vector3(0.0, 0.04, 0.0)), Vector3(0.2, 0.06, 0.2))
	k.tube("steel", base + Vector3(0.0, 0.06, 0.0), base + Vector3(0.0, 1.5, 0.0), 0.03, 8)
	k.box("dark", Transform3D(Basis(), base + Vector3(0.0, 1.05, 0.0)), Vector3(0.42, 0.025, 0.025))
	for s: float in [-1.0, 1.0]:
		k.tube("steel", base + Vector3(s * 0.2, 1.05, 0.0), base + Vector3(s * 0.2, 1.35, 0.0), 0.008, 5)
	k.tube("steel", base + Vector3(0.0, 0.5, 0.0), base + Vector3(0.0, 0.5, 0.0) + Vector3(0.0, 0.0, 0.22), 0.01, 5)
	k.cylinder("glow_red", Transform3D(Basis(), base + Vector3(0.0, 1.56, 0.0)), 0.05, 0.05, 0.11, 12, true, true)
	k.cylinder("dark", Transform3D(Basis(), base + Vector3(0.0, 1.63, 0.0)), 0.035, 0.06, 0.03, 12, true, true)


## V4: wheel flare over the tyre and a mud flap behind it.
static func _dust_guard(k: Kit, w: Vector3, t: int) -> void:
	k.group = "v4"
	var s := _side(w)
	var rr := TYRE_R - 0.015 + float(TRACTION_R[t - 1]) + float(TRACTION_LUG_H[t - 1]) + 0.05
	var x_in := 1.4
	var x_out := _hub_face(w, t) + 0.07
	var steps := 9
	var a0 := deg_to_rad(-78.0)
	var a1 := deg_to_rad(78.0)
	for i in steps:
		var a := lerpf(a0, a1, (float(i) + 0.5) / float(steps))
		var rot := Basis(Vector3.RIGHT, a)
		var seg := 2.0 * rr * sin((a1 - a0) / float(steps) * 0.5) + 0.01
		var p := Vector3(s * (x_in + x_out) * 0.5, w.y, w.z) + rot * Vector3(0.0, rr + 0.02, 0.0)
		k.box("dark", Transform3D(rot, p), Vector3(x_out - x_in, 0.04, seg))
		var lip := Vector3(s * (x_out - 0.01), w.y, w.z) + rot * Vector3(0.0, rr + 0.0, 0.0)
		k.box("orange", Transform3D(rot, lip), Vector3(0.025, 0.03, seg))
	# mud flap behind the wheel (+Z is the rear)
	var fz := w.z + rr + 0.03
	var fx := (TYRE_IN + x_out - 0.05) * 0.5
	k.box("rubber", Transform3D(Basis(), Vector3(s * fx, 0.43, fz)), Vector3(x_out - 0.05 - TYRE_IN, 0.62, 0.025))
	k.box("orange", Transform3D(Basis(), Vector3(s * fx, 0.2, fz + 0.015)), Vector3(x_out - 0.12 - TYRE_IN, 0.06, 0.01))


## V4: a tubular roll cage round the cabin: three hoops, roof rails and corner posts down to the fender ledge.
static func _roll_cage(k: Kit) -> void:
	k.group = "v4"
	var y := 3.05
	var r := 0.04
	var hoops: Array[float] = [-1.45, 0.72, 2.15]
	for z: float in hoops:
		k.tube("dark", Vector3(-1.02, y, z), Vector3(1.02, y, z), r, 10)
	for s: float in [-1.0, 1.0]:
		k.tube("dark", Vector3(s * 1.02, y, -1.62), Vector3(s * 1.02, y, 2.15), r, 10)
		# front posts follow the windscreen pillar
		var f: Array[Vector3] = [Vector3(s * 1.02, y, -1.62), Vector3(s * 1.17, 2.55, -2.02), Vector3(s * 1.17, LEDGE_Y + 0.3, -2.1)]
		k.tube("dark", f[0], f[1], r, 10)
		k.tube("dark", f[1], f[2], r, 10)
		var m: Array[Vector3] = [Vector3(s * 1.02, y, 0.72), Vector3(s * 1.19, 2.65, 0.72), Vector3(s * 1.19, LEDGE_Y + 0.3, 0.72)]
		k.tube("dark", m[0], m[1], r, 10)
		k.tube("dark", m[1], m[2], r, 10)
		var b: Array[Vector3] = [Vector3(s * 1.02, y, 2.15), Vector3(s * 1.17, 2.6, 2.33), Vector3(s * 1.17, LEDGE_Y + 0.3, 2.38)]
		k.tube("dark", b[0], b[1], r, 10)
		k.tube("dark", b[1], b[2], r, 10)
		# feet on the ledge and a knee brace between the mid and rear posts
		for p: Vector3 in [f[2], m[2], b[2]]:
			k.box("dark", Transform3D(Basis(), p + Vector3(0.0, -0.02, 0.0)), Vector3(0.12, 0.03, 0.12))
		k.tube("dark", Vector3(s * 1.19, 2.65, 0.72), Vector3(s * 1.17, LEDGE_Y + 0.3, 2.38), r * 0.8, 8)
	for z: float in hoops:
		for s: float in [-1.0, 1.0]:
			k.tube("dark", Vector3(s * 1.02, y, z), Vector3(s * 0.98, ROOF_Y - 0.02, z), r * 0.7, 8)


# ---------------------------------------------------------------- merged mesh builder

## Collects triangles per material and commits them into one ArrayMesh (one surface per material). Godot's front
## faces wind clockwise; every triangle is wound from its intended outward normal, so back-face culling stays on.
class Kit:
	var tools: Dictionary = {}       # material key -> SurfaceTool
	var counts: Dictionary = {}      # material key -> triangles
	var groups: Dictionary = {}      # part group -> triangles
	var group := "misc"

	func triangles() -> int:
		var n := 0
		for key: String in counts:
			n += int(counts[key])
		return n

	func _st(key: String) -> SurfaceTool:
		if not tools.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[key] = st
			counts[key] = 0
		return tools[key]

	func tri(key: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
		var st := _st(key)
		var face := (b - a).cross(c - a)
		var n := na + nb + nc
		if face.dot(n) > 0.0:
			# counter-clockwise seen from outside: swap to Godot's clockwise front face
			var t := b
			b = c
			c = t
			var tn := nb
			nb = nc
			nc = tn
		st.set_normal(na)
		st.add_vertex(a)
		st.set_normal(nb)
		st.add_vertex(b)
		st.set_normal(nc)
		st.add_vertex(c)
		counts[key] = int(counts[key]) + 1
		groups[group] = int(groups.get(group, 0)) + 1

	func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
		tri(key, a, b, c, n, n, n)
		tri(key, a, c, d, n, n, n)

	## Box of `size` centred on xf.origin.
	func box(key: String, xf: Transform3D, size: Vector3) -> void:
		var h := size * 0.5
		var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
		for i in 3:
			var n: Vector3 = axes[i]
			var u: Vector3 = axes[(i + 1) % 3]
			var v: Vector3 = axes[(i + 2) % 3]
			for sgn: float in [-1.0, 1.0]:
				var c := n * sgn * h[i]
				var hu := u * h[(i + 1) % 3]
				var hv := v * h[(i + 2) % 3]
				var nn := (xf.basis * (n * sgn)).normalized()
				quad(key, xf * (c - hu - hv), xf * (c + hu - hv), xf * (c + hu + hv), xf * (c - hu + hv), nn)

	## Cylinder along the local Y axis, centred on xf.origin. `smooth` shades the side round.
	func cylinder(key: String, xf: Transform3D, r_top: float, r_bottom: float, height: float, seg: int, caps: bool, smooth: bool) -> void:
		var hh := height * 0.5
		var top: Array[Vector3] = []
		var bot: Array[Vector3] = []
		for i in seg + 1:
			var a := TAU * float(i) / float(seg)
			var d := Vector3(cos(a), 0.0, sin(a))
			top.append(d * r_top + Vector3(0.0, hh, 0.0))
			bot.append(d * r_bottom - Vector3(0.0, hh, 0.0))
		var slope := (r_bottom - r_top) / maxf(height, 1e-4)
		for i in seg:
			var a0 := TAU * float(i) / float(seg)
			var a1 := TAU * float(i + 1) / float(seg)
			var n0 := xf.basis * Vector3(cos(a0), slope, sin(a0)).normalized()
			var n1 := xf.basis * Vector3(cos(a1), slope, sin(a1)).normalized()
			if not smooth:
				var am := (a0 + a1) * 0.5
				n0 = xf.basis * Vector3(cos(am), slope, sin(am)).normalized()
				n1 = n0
			tri(key, xf * bot[i], xf * bot[i + 1], xf * top[i + 1], n0, n1, n1)
			tri(key, xf * bot[i], xf * top[i + 1], xf * top[i], n0, n1, n0)
			if caps:
				var up := (xf.basis * Vector3.UP).normalized()
				tri(key, xf * Vector3(0.0, hh, 0.0), xf * top[i], xf * top[i + 1], up, up, up)
				tri(key, xf * Vector3(0.0, -hh, 0.0), xf * bot[i + 1], xf * bot[i], -up, -up, -up)

	## Flat ring (annulus with thickness) round the local Y axis.
	func ring(key: String, xf: Transform3D, r_in: float, r_out: float, thick: float, seg: int) -> void:
		var hh := thick * 0.5
		var up := (xf.basis * Vector3.UP).normalized()
		for i in seg:
			var a0 := TAU * float(i) / float(seg)
			var a1 := TAU * float(i + 1) / float(seg)
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			for sgn: float in [-1.0, 1.0]:
				var y := Vector3(0.0, hh * sgn, 0.0)
				quad(key, xf * (d0 * r_in + y), xf * (d0 * r_out + y), xf * (d1 * r_out + y), xf * (d1 * r_in + y), up * sgn)
			var no0 := xf.basis * d0
			var no1 := xf.basis * d1
			var yy := Vector3(0.0, hh, 0.0)
			tri(key, xf * (d0 * r_out - yy), xf * (d1 * r_out - yy), xf * (d1 * r_out + yy), no0, no1, no1)
			tri(key, xf * (d0 * r_out - yy), xf * (d1 * r_out + yy), xf * (d0 * r_out + yy), no0, no1, no0)
			tri(key, xf * (d0 * r_in - yy), xf * (d1 * r_in + yy), xf * (d1 * r_in - yy), -no0, -no1, -no1)
			tri(key, xf * (d0 * r_in - yy), xf * (d0 * r_in + yy), xf * (d1 * r_in + yy), -no0, -no0, -no1)

	## Round tube from a to b.
	func tube(key: String, a: Vector3, b: Vector3, r: float, seg: int) -> void:
		var d := b - a
		var length := d.length()
		if length < 1e-4:
			return
		var y := d / length
		var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		cylinder(key, Transform3D(Basis(x, y, z), (a + b) * 0.5), r, r, length, seg, true, true)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		var keys := tools.keys()
		keys.sort()
		for key: String in keys:
			var st: SurfaceTool = tools[key]
			st.commit(mesh)
			var c: Array = COLOURS.get(key, [Color.WHITE, 0.0, 0.7, 0.0])
			var m := AreaStagePresenter.mat(c[0], c[1], c[2], c[3])
			mesh.surface_set_material(mesh.get_surface_count() - 1, m)
			mesh.surface_set_name(mesh.get_surface_count() - 1, "rover_" + key)
		return mesh
