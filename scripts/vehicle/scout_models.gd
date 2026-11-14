class_name ScoutModels
extends RefCounted
## Run-time models of the scout update, built from simple shapes so the map file stays unchanged:
##   scout(false)    the finished scout rover: six aluminium wheels on rocker-bogie arms, a white body, a mast with a
##                   camera head (node "MastHead", with a "Camera" marker) and a power unit with fins at the back.
##   scout(true)     the same rover half built on its stand: wheels on one side only, the mast without its head, open
##                   frame showing, a scaffold and a crate of parts beside it.
##   broken_rover()  a copy of the map's own rover (its meshes are shared, nothing is changed), tipped onto one side,
##                   sunk in the sand and dusty, with a wheel lying beside it. A simple stand-in when there is no map.
##   ore_deposit()   a cluster of rocks in the ore's colour, with a survey flag (node "Flag") shown once it is found.
##   bay()           the scout bay: a pad, a sign post and a console with a screen (node "Screen").
## Wheels are named "Wheel*" so the presenter can spin them.

const WHITE := Color(0.86, 0.85, 0.81)
const DARK := Color(0.16, 0.17, 0.19)
const METAL := Color(0.62, 0.63, 0.64)
const GOLD := Color(0.78, 0.6, 0.26)
const ORANGE := Color(0.95, 0.47, 0.16)
const SCAFFOLD := Color(0.95, 0.76, 0.12)
const PAD := Color(0.42, 0.40, 0.38)

static var _materials: Dictionary = {}


static func material(c: Color, metallic := 0.0, rough := 0.75) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [c.to_html(), metallic, rough]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = metallic
		m.roughness = rough
		_materials[key] = m
	return _materials[key]


static func box(parent: Node3D, size: Vector3, at: Vector3, color: Color, node_name := "", metallic := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = at
	mi.material_override = material(color, metallic)
	if node_name != "":
		mi.name = node_name
	parent.add_child(mi)
	return mi


static func cylinder(parent: Node3D, radius: float, height: float, at: Vector3, color: Color, rot := Vector3.ZERO, node_name := "", sides := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	mi.mesh = m
	mi.position = at
	mi.rotation = rot
	mi.material_override = material(color, 0.4 if color == METAL else 0.0)
	if node_name != "":
		mi.name = node_name
	parent.add_child(mi)
	return mi


# ================================================================ scout rover

## The scout rover, about 2.2 m long. Faces -z (Godot forward).
static func scout(in_progress := false) -> Node3D:
	var root := Node3D.new()
	root.name = "ScoutKit" if in_progress else "Scout"
	var lift := 0.35 if in_progress else 0.0          # on its stand while being built
	var body := Node3D.new()
	body.name = "Body"
	body.position.y = lift
	root.add_child(body)
	# chassis and deck
	box(body, Vector3(1.25, 0.42, 1.9), Vector3(0, 0.78, 0), DARK if in_progress else WHITE, "Chassis")
	if not in_progress:
		box(body, Vector3(1.32, 0.05, 1.98), Vector3(0, 1.01, 0), WHITE)
		box(body, Vector3(0.9, 0.04, 0.7), Vector3(0, 1.05, 0.3), GOLD)             # instrument deck foil
		cylinder(body, 0.28, 0.04, Vector3(0.35, 1.12, -0.35), METAL, Vector3(deg_to_rad(20), 0, 0))   # high-gain antenna
	else:
		# open frame: the side panels are not on yet
		for x in [-0.6, 0.6]:
			for z in [-0.9, 0.9]:
				box(body, Vector3(0.05, 0.45, 0.05), Vector3(x, 0.8, z), METAL)
		box(body, Vector3(1.25, 0.04, 0.05), Vector3(0, 1.02, -0.9), METAL)
		box(body, Vector3(1.25, 0.04, 0.05), Vector3(0, 1.02, 0.9), METAL)
		box(body, Vector3(0.5, 0.25, 0.35), Vector3(-0.2, 0.75, 0.1), Color(0.2, 0.45, 0.25))   # bare electronics board
	# power unit with fins at the back (radioisotope power, never needs charging; illustrative)
	var rtg := cylinder(body, 0.17, 0.62, Vector3(0, 0.95, 1.12), DARK, Vector3(deg_to_rad(65), 0, 0), "PowerUnit")
	for i in 6:
		var a := TAU * i / 6.0
		box(rtg, Vector3(0.03, 0.55, 0.16), Vector3(cos(a) * 0.2, 0, sin(a) * 0.2), DARK).rotation.y = -a
	# mast and camera head
	var mast_h := 0.55 if in_progress else 1.05
	cylinder(body, 0.045, mast_h, Vector3(-0.42, 1.03 + mast_h * 0.5, -0.72), METAL, Vector3.ZERO, "Mast")
	if not in_progress:
		var head := Node3D.new()
		head.name = "MastHead"
		head.position = Vector3(-0.42, 1.03 + mast_h + 0.1, -0.72)
		body.add_child(head)
		box(head, Vector3(0.42, 0.2, 0.2), Vector3.ZERO, WHITE)
		for x in [-0.11, 0.11]:
			cylinder(head, 0.045, 0.06, Vector3(x, 0.0, -0.12), Color(0.05, 0.05, 0.06), Vector3(deg_to_rad(90), 0, 0))
		var cam := Marker3D.new()
		cam.name = "Camera"
		cam.position = Vector3(0, 0.02, -0.16)
		head.add_child(cam)
		# robotic arm folded at the front
		box(body, Vector3(0.08, 0.08, 0.5), Vector3(0.35, 0.68, -1.1), METAL)
		box(body, Vector3(0.18, 0.14, 0.14), Vector3(0.35, 0.68, -1.38), DARK)
	# rocker-bogie arms and six wheels
	var sides: Array[float] = [-0.78, 0.78]
	for side: float in sides:
		var missing := in_progress and side > 0.0
		box(body, Vector3(0.06, 0.06, 1.6), Vector3(side * 0.95, 0.55, 0.05), METAL)
		for i in 3:
			var z := -0.8 + 0.8 * i
			box(body, Vector3(0.05, 0.32, 0.05), Vector3(side * 0.95, 0.42, z), METAL)
			if missing:
				continue
			var w := cylinder(body, 0.25, 0.2, Vector3(side, 0.25 - lift, z), METAL, Vector3(0, 0, deg_to_rad(90)), "Wheel_%d_%d" % [int(side > 0), i], 14)
			cylinder(w, 0.12, 0.22, Vector3.ZERO, DARK, Vector3.ZERO, "", 10)
	if in_progress:
		# the stand, the scaffold, the wheels still to fit and a crate of parts
		for z in [-0.6, 0.6]:
			box(root, Vector3(1.0, 0.35, 0.3), Vector3(0, 0.175 + 0.2, z), DARK)
		for x in [-1.5, 1.5]:
			for z in [-1.4, 1.4]:
				box(root, Vector3(0.07, 2.4, 0.07), Vector3(x, 1.2, z), SCAFFOLD)
		for z in [-1.4, 1.4]:
			box(root, Vector3(3.07, 0.07, 0.07), Vector3(0, 2.4, z), SCAFFOLD)
		for x in [-1.5, 1.5]:
			box(root, Vector3(0.07, 0.07, 2.87), Vector3(x, 2.4, 0), SCAFFOLD)
		for i in 3:
			cylinder(root, 0.25, 0.2, Vector3(2.1, 0.11, -0.7 + 0.55 * i), METAL, Vector3(0, 0, 0), "", 14)
		box(root, Vector3(0.7, 0.45, 0.5), Vector3(-2.1, 0.23, 0.5), ORANGE)
		box(root, Vector3(0.42, 0.2, 0.2), Vector3(-2.1, 0.56, 0.5), WHITE)       # the camera head waiting to go on
	return root


# ================================================================ broken-down rover

## A dusty, tipped copy of the map's rover (`source`, may be null: then a simple stand-in is built).
static func broken_rover(source: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "BrokenRover"
	var tilt := Node3D.new()
	tilt.name = "Tilt"
	tilt.rotation = Vector3(deg_to_rad(4.0), deg_to_rad(28.0), deg_to_rad(13.0))
	tilt.position.y = -0.22
	root.add_child(tilt)
	var dust := StandardMaterial3D.new()
	dust.albedo_color = Color(0.55, 0.33, 0.2, 0.5)
	dust.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust.roughness = 1.0
	if source != null:
		var copy := source.duplicate(0) as Node3D
		copy.transform = Transform3D(source.global_basis, Vector3.ZERO) if source.is_inside_tree() else Transform3D(source.basis, Vector3.ZERO)
		tilt.add_child(copy)
		for mi: MeshInstance3D in _meshes(copy):
			mi.material_overlay = dust
	else:
		box(tilt, Vector3(2.2, 1.1, 3.8), Vector3(0, 1.2, 0), WHITE)
		box(tilt, Vector3(2.0, 0.6, 1.4), Vector3(0, 1.9, -0.9), Color(0.25, 0.3, 0.35))
		for x in [-1.2, 1.2]:
			for z in [-1.3, 0.0, 1.3]:
				if x > 0 and z > 1.0:
					continue
				cylinder(tilt, 0.45, 0.35, Vector3(x, 0.45, z), DARK, Vector3(0, 0, deg_to_rad(90)))
		for mi: MeshInstance3D in _meshes(tilt):
			mi.material_overlay = dust
	# the lost wheel, lying in the sand, and a few bits around
	var lost := cylinder(root, 0.45, 0.35, Vector3(2.6, 0.18, 1.6), DARK, Vector3(deg_to_rad(90), deg_to_rad(30), 0), "LostWheel")
	lost.material_overlay = dust
	box(root, Vector3(0.6, 0.06, 0.4), Vector3(-1.9, 0.03, 2.2), METAL).rotation.y = 0.6
	box(root, Vector3(0.25, 0.25, 0.4), Vector3(1.7, 0.12, -2.1), ORANGE).rotation.y = -0.3    # the tool locker door
	return root


static func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


# ================================================================ ore deposit

static func ore_deposit(color: Color, seed_value: int) -> Node3D:
	var root := Node3D.new()
	root.name = "OreDeposit"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rock := material(Color(0.47, 0.3, 0.21))
	var ore := material(color, 0.15, 0.55)
	for i in 7:
		var mi := MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radial_segments = 7
		m.rings = 4
		var r := rng.randf_range(0.18, 0.42)
		m.radius = r
		m.height = r * rng.randf_range(1.1, 1.6)
		mi.mesh = m
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.9)
		mi.position = Vector3(cos(a) * d, r * 0.35, sin(a) * d)
		mi.rotation = Vector3(rng.randf() * 0.6, rng.randf() * TAU, rng.randf() * 0.6)
		mi.scale = Vector3(1.0, rng.randf_range(0.6, 0.9), rng.randf_range(0.8, 1.3))
		mi.material_override = ore if i % 2 == 0 else rock
		mi.name = "Ore_%d" % i if i % 2 == 0 else "Rock_%d" % i
		root.add_child(mi)
	var flag := Node3D.new()
	flag.name = "Flag"
	flag.position = Vector3(1.0, 0, -0.4)
	root.add_child(flag)
	cylinder(flag, 0.02, 1.4, Vector3(0, 0.7, 0), METAL)
	box(flag, Vector3(0.36, 0.22, 0.01), Vector3(0.19, 1.27, 0), ORANGE)
	return root


# ================================================================ scout bay

static func bay() -> Node3D:
	var root := Node3D.new()
	root.name = "ScoutBay"
	box(root, Vector3(4.2, 0.08, 6.2), Vector3(0, 0.02, 1.6), PAD, "Pad")
	for z in [-1.5, 4.7]:
		box(root, Vector3(4.2, 0.09, 0.12), Vector3(0, 0.03, z), SCAFFOLD)
	# the console: a post with a tilted screen facing the pad
	var console := Node3D.new()
	console.name = "Console"
	console.position = Vector3(-2.6, 0, -0.6)
	console.rotation.y = deg_to_rad(-60)
	root.add_child(console)
	box(console, Vector3(0.18, 1.1, 0.18), Vector3(0, 0.55, 0), METAL)
	box(console, Vector3(0.72, 0.48, 0.1), Vector3(0, 1.25, 0), DARK).rotation.x = deg_to_rad(-20)
	var screen := MeshInstance3D.new()
	screen.name = "Screen"
	var q := QuadMesh.new()
	q.size = Vector2(0.62, 0.38)
	screen.mesh = q
	screen.position = Vector3(0, 1.255, 0.056)
	screen.rotation.x = deg_to_rad(-20)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.1, 0.25, 0.32)
	sm.emission_enabled = true
	sm.emission = Color(0.15, 0.45, 0.55)
	sm.emission_energy_multiplier = 0.6
	screen.material_override = sm
	console.add_child(screen)
	# sign post
	box(root, Vector3(0.08, 1.8, 0.08), Vector3(2.4, 0.9, -1.3), METAL)
	box(root, Vector3(1.0, 0.36, 0.04), Vector3(2.4, 1.75, -1.3), ORANGE)
	return root
