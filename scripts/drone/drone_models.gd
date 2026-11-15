extends RefCounted
## Models of the scout drone (2026-11-14 upgrade paths), loaded by path (no class_name).
## The glbs are built in Blender by tools/blender/drone/build_drone.py (real mesh detail, run-time materials, no baked
## textures): Y-up, metres, origin at the landing-gear base centre, facing -Z.
##   drone(level)   assets/drone/drone_v<level>.glb (V1..V4). Rotor hubs are nodes named RotorHub_FL/FR/BL/BR.
##   pad()          assets/drone/drone_pad.glb: landing pad with its charging plate (top at DOCK_HEIGHT) and a charger
##                  cabinet on its local +Z side.
## When a glb cannot be loaded (an unimported checkout), a simple stand-in of boxes is built instead, with the same
## node names, so the game and the tests still work.

const DRONE_PATH := "res://assets/drone/drone_v%d.glb"
const PAD_PATH := "res://assets/drone/drone_pad.glb"
const ROTOR_PREFIX := "RotorHub_"
## Charger cabinet of the pad, in pad space (for its collision box).
const CABINET_CENTRE := Vector3(0.0, 0.31, 1.48)
const CABINET_SIZE := Vector3(0.48, 0.66, 0.34)


static func drone_path(level: int) -> String:
	return DRONE_PATH % clampi(level, 1, 4)


## A new drone model of `level` (1..4).
static func drone(level: int) -> Node3D:
	var path := drone_path(level)
	var scene := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if scene != null:
		var n := scene.instantiate() as Node3D
		if n != null:
			n.name = "DroneV%d" % clampi(level, 1, 4)
			return n
	return _stand_in(level)


## A new landing pad model.
static func pad() -> Node3D:
	var scene := load(PAD_PATH) as PackedScene if ResourceLoader.exists(PAD_PATH) else null
	if scene != null:
		var n := scene.instantiate() as Node3D
		if n != null:
			n.name = "DronePadModel"
			return n
	var root := Node3D.new()
	root.name = "DronePadModel"
	_box(root, Vector3(2.4, 0.06, 2.4), Vector3(0, 0.03, 0), Color(0.36, 0.34, 0.33))
	_box(root, CABINET_SIZE, CABINET_CENTRE, Color(0.86, 0.85, 0.81))
	return root


## Every rotor hub node under `root`.
static func rotors(root: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if root == null:
		return out
	for n in root.find_children(ROTOR_PREFIX + "*", "Node3D", true, false):
		out.append(n as Node3D)
	return out


static func _stand_in(level: int) -> Node3D:
	var root := Node3D.new()
	root.name = "DroneV%d" % clampi(level, 1, 4)
	_box(root, Vector3(0.3, 0.18, 0.26), Vector3(0, 0.36, 0), Color(0.83, 0.62, 0.24))
	var arm := 0.335 if level < 2 else 0.355
	for id: String in ["FL", "FR", "BL", "BR"]:
		var sx := -1.0 if id.ends_with("L") else 1.0
		var sz := -1.0 if id.begins_with("F") else 1.0
		var at := Vector3(sx, 0, sz).normalized() * arm + Vector3(0, 0.45, 0)
		var hub := Node3D.new()
		hub.name = ROTOR_PREFIX + id
		hub.position = at
		root.add_child(hub)
		_box(hub, Vector3(0.3 if level < 2 else 0.4, 0.006, 0.03), Vector3.ZERO, Color(0.12, 0.12, 0.13))
		_box(root, Vector3(0.02, 0.27, 0.02), Vector3(sx * 0.2, 0.13, sz * 0.2), Color(0.07, 0.07, 0.08))
	return root


static func _box(parent: Node3D, size: Vector3, at: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mi.material_override = mat
	parent.add_child(mi)
	return mi
