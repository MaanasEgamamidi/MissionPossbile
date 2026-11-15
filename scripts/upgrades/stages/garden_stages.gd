extends AreaStagePresenter
## Look of the "garden" upgrade path (Garden dome planting, data/area_levels.json). Procedural meshes, no textures.
##   V1  bare planters (the map as it is) plus the garden upgrade console just inside the west airlock
##   V2  ground cover all round the dome's edge and pots of herbs
##   V3  a raised bed ring along the dome wall, planted with herbs, ground cover and shrubs
##   V4  the ring with dwarf fruit trees between the shrubs: a full green canopy round the dome
## Every level builds the console (station upgrade_garden, data/stations_upgrades.json), so build_stage(1) is not null.
## Visual only: no colliders. Everything stays out of the airlock opening (the ring has a gap there), the central aisle,
## the walkways round the six planters and the east-side equipment (hydroponics unit, tank, bench, gantry posts).
## Plants are MultiMeshes (one draw call per kind), coloured per instance.
##
## Layout (Godot world metres, measured from data/colony_manifest.json and the map's bounding boxes, 2026-11-14):
##   dome centre (50, 0, 27); the base ring's inner face is about 7.6 m from it; the glass rises like a sphere of
##   radius 7.9 m centred 0.85 m above the floor, so at distance r from the centre the glass is GLASS_Y0 +
##   sqrt(GLASS_R^2 - r^2) high. The west airlock opens at x 43.56, z 26.2..27.8 (angle 180 degrees).

const CENTRE := Vector3(50.0, 0.0, 27.0)
const CONSOLE_ID := "upgrade_garden"
## Same as data/stations_upgrades.json (used when there is no game, for tests and tools).
const CONSOLE_FALLBACK := Vector3(44.15, 0.0, 24.35)
## Planting band along the dome wall: inner and outer distance from the centre (metres).
const RING_R := Vector2(6.75, 7.35)
## The ring runs from -RING_END_DEG to +RING_END_DEG (0 = east, +90 = south, Godot +z); the west stays open for the
## airlock and the console.
const RING_END_DEG := 145.0
const RING_SEGMENTS := 34
const RING_HEIGHT := 0.42
const GLASS_R := 7.9
const GLASS_Y0 := 0.85
## Dwarf fruit trees (V4): angles chosen clear of the gantry posts (+-37, +-71 degrees), the bench and the tank.
const TREE_ANGLES: Array[float] = [-135.0, -118.0, -100.0, -82.0, -55.0, -20.0, 20.0, 55.0, 82.0, 100.0, 118.0, 135.0]
## Crowns start above head height (about 1.8 m), so the walkway round the planter ends stays clear.
const TREE_R := 6.95
const TREE_CROWN_R := 0.55
const TREE_CROWN_Y := 2.25

## Small or glowing parts cast no shadow (cheaper; their shadows would be specks).
const NO_SHADOW: Array[String] = ["GroundCover", "Flowers", "Herbs", "Berries", "Fruit", "RingDripLine"]

static var _vc_mats: Dictionary = {}


func track_id() -> String:
	return "garden"


func build_stage(level: int) -> Node3D:
	# The stage root stands at the dome centre (the grow-in scales about it); everything else is placed from there.
	var root := Node3D.new()
	root.position = CENTRE
	root.set_meta("garden_level", level)
	_build_console(root, level)
	if level >= 2:
		var plants := Node3D.new()
		plants.name = "Plants"
		root.add_child(plants)
		if level == 2:
			_ground_cover(plants, 0.0, 380)
			_herb_pots(plants)
		else:
			_ring(plants)
			_ground_cover(plants, RING_HEIGHT + 0.02, 420)
			_herbs_in_ring(plants)
			_shrubs(plants, level)
			if level >= 4:
				_trees(plants)
	return root


## World position of the garden console (the station's position when a game runs).
func console_position() -> Vector3:
	return station_position(CONSOLE_ID, CONSOLE_FALLBACK)


# ---------------------------------------------------------------- the upgrade console (every level)

## A pedestal console facing the aisle (+z): plinth, cream body with the colony's orange band, a tilted screen with a
## leaf mark and four level lights (lit up to the current level), a status beacon and side handles.
func _build_console(root: Node3D, level: int) -> void:
	var c := Node3D.new()
	c.name = "GardenConsole"
	c.position = console_position() - CENTRE
	c.set_meta("station_id", CONSOLE_ID)
	root.add_child(c)
	var dark := mat(Color(0.2, 0.22, 0.24), 0.5, 0.5)
	var cream := mat(Color(0.86, 0.84, 0.78), 0.0, 0.6)
	var orange := mat(Color(0.93, 0.45, 0.12), 0.0, 0.5)
	var alu := mat(Color(0.72, 0.74, 0.76), 0.8, 0.35)
	box(c, Vector3(0.62, 0.06, 0.46), Vector3(0, 0.03, 0), dark)
	box(c, Vector3(0.32, 0.86, 0.26), Vector3(0, 0.49, 0), cream)
	box(c, Vector3(0.325, 0.06, 0.265), Vector3(0, 0.78, 0), orange)
	for i in 4:   # vent slats on the front
		box(c, Vector3(0.22, 0.015, 0.01), Vector3(0, 0.22 + i * 0.05, 0.132), dark)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.08, 0.02)
	head.rotation.x = -0.5
	c.add_child(head)
	box(head, Vector3(0.66, 0.44, 0.1), Vector3.ZERO, cream)
	box(head, Vector3(0.68, 0.46, 0.04), Vector3(0, 0, -0.05), dark)
	box(head, Vector3(0.56, 0.3, 0.012), Vector3(0, 0.04, 0.054), mat(Color(0.25, 0.85, 0.5), 0.0, 0.3, 1.6))
	# leaf mark on the screen
	var leaf := cylinder(head, 0.05, 0.004, Vector3(-0.2, 0.1, 0.062), mat(Color(0.85, 1.0, 0.85), 0.0, 0.4, 2.0))
	leaf.rotation.x = PI / 2.0
	leaf.scale = Vector3(1.0, 1.0, 0.55)
	# level lights V1..V4 under the screen
	for i in 4:
		var lit := i < level
		var lamp := box(head, Vector3(0.09, 0.03, 0.012), Vector3(-0.165 + i * 0.11, -0.16, 0.054),
			mat(Color(0.35, 1.0, 0.45), 0.0, 0.3, 2.5) if lit else mat(Color(0.12, 0.16, 0.13), 0.0, 0.6))
		lamp.name = "LevelLight%d" % (i + 1)
		lamp.set_meta("lit", lit)
	for side: int in [-1, 1]:
		var handle := cylinder(c, 0.015, 0.36, Vector3(0.19 * side, 0.6, 0.0), alu)
		handle.name = "Handle"
	cylinder(c, 0.035, 0.08, Vector3(0.22, 1.36, -0.08), mat(Color(0.3, 1.0, 0.5), 0.0, 0.3, 3.0))


# ---------------------------------------------------------------- planting

## Point on the dome floor at `deg` degrees and `r` metres from the centre, in the Plants node's space.
static func polar(deg: float, r: float, y := 0.0) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(cos(a) * r, y, sin(a) * r)


## Height of the dome glass at distance `r` from the centre.
static func glass_height(r: float) -> float:
	return GLASS_Y0 + sqrt(maxf(0.0, GLASS_R * GLASS_R - r * r))


## True when an angle (degrees) is in the planted arc (not the open west side).
static func in_arc(deg: float) -> bool:
	return absf(wrapf(deg, -180.0, 180.0)) <= RING_END_DEG


## Low clumps of ground cover (moss, clover, creeping thyme) in the band along the wall, at height `y`.
func _ground_cover(parent: Node3D, y: float, count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	var greens := [Color(0.24, 0.5, 0.2), Color(0.32, 0.58, 0.22), Color(0.2, 0.42, 0.18), Color(0.4, 0.6, 0.25)]
	for i in count:
		var deg := lerpf(-RING_END_DEG + 2.0, RING_END_DEG - 2.0, (float(i) + rng.randf()) / float(count))
		var r := rng.randf_range(RING_R.x + 0.12, RING_R.y - 0.12)
		var s := rng.randf_range(0.07, 0.13)
		var b := Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)) * Basis.from_scale(Vector3(s * 1.3, rng.randf_range(0.025, 0.05), s))
		xs.append(Transform3D(b, polar(deg, r, y + 0.01)))
		cs.append(greens[i % greens.size()].lerp(Color(0.5, 0.7, 0.3), rng.randf() * 0.25))
	_multi(parent, "GroundCover", _sphere(8, 4), xs, cs)
	# tiny flowers in the clover
	var fx: Array[Transform3D] = []
	var fc: Array[Color] = []
	var petals := [Color(0.95, 0.9, 0.95), Color(0.85, 0.55, 0.9), Color(1.0, 0.85, 0.3)]
	for i in count / 2:
		var deg := lerpf(-RING_END_DEG + 3.0, RING_END_DEG - 3.0, (float(i) + rng.randf()) / float(count / 2))
		fx.append(Transform3D(Basis().scaled(Vector3.ONE * 0.025), polar(deg, rng.randf_range(RING_R.x + 0.15, RING_R.y - 0.15), y + 0.075)))
		fc.append(petals[i % petals.size()])
	_multi(parent, "Flowers", _sphere(6, 3), fx, fc, 0.6)


## V2: terracotta pots of herbs (basil, mint, chives) standing in the band.
func _herb_pots(parent: Node3D) -> void:
	var px: Array[Transform3D] = []
	var hx: Array[Transform3D] = []
	var hc: Array[Color] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var n := 22
	for i in n:
		var deg := lerpf(-RING_END_DEG + 5.0, RING_END_DEG - 5.0, float(i) / float(n - 1))
		var p := polar(deg, (RING_R.x + RING_R.y) * 0.5)
		px.append(Transform3D(Basis(), p + Vector3(0, 0.12, 0)))
		for k in 3:
			var off := Vector3(rng.randf_range(-0.07, 0.07), 0, rng.randf_range(-0.07, 0.07))
			var s := rng.randf_range(0.07, 0.1)
			hx.append(Transform3D(Basis().scaled(Vector3(s, s * 1.4, s)), p + off + Vector3(0, 0.27 + s * 0.6, 0)))
			hc.append([Color(0.22, 0.55, 0.2), Color(0.35, 0.65, 0.3), Color(0.3, 0.5, 0.22)][(i + k) % 3])
	var pot := CylinderMesh.new()
	pot.top_radius = 0.17
	pot.bottom_radius = 0.12
	pot.height = 0.24
	pot.radial_segments = 12
	pot.rings = 1
	_multi(parent, "HerbPots", pot, px, [], 0.0, Color(0.72, 0.36, 0.2))
	_multi(parent, "Herbs", _sphere(8, 5), hx, hc)


## V3+: the raised bed ring: composite walls, an aluminium rim, soil, and orange corner posts like the planters'.
func _ring(parent: Node3D) -> void:
	var walls: Array[Transform3D] = []
	var rims: Array[Transform3D] = []
	var soil: Array[Transform3D] = []
	var posts: Array[Transform3D] = []
	var mid := (RING_R.x + RING_R.y) * 0.5
	var depth := RING_R.y - RING_R.x
	var step := 2.0 * RING_END_DEG / float(RING_SEGMENTS)
	var chord := 2.0 * RING_R.y * sin(deg_to_rad(step) * 0.5) + 0.02
	for i in RING_SEGMENTS:
		var deg := -RING_END_DEG + (float(i) + 0.5) * step
		var yaw := -deg_to_rad(deg)   # local x along the radius, local z along the ring
		var b := Basis(Vector3.UP, yaw)
		var p := polar(deg, mid)
		walls.append(Transform3D(b * Basis.from_scale(Vector3(depth, RING_HEIGHT, chord)), p + Vector3(0, RING_HEIGHT * 0.5, 0)))
		soil.append(Transform3D(b * Basis.from_scale(Vector3(depth - 0.1, 0.03, chord)), p + Vector3(0, RING_HEIGHT + 0.005, 0)))
		for edge: float in [RING_R.x + 0.025, RING_R.y - 0.025]:
			rims.append(Transform3D(b * Basis.from_scale(Vector3(0.07, 0.04, chord)), polar(deg, edge, RING_HEIGHT + 0.02)))
		if i % 4 == 0 or i == RING_SEGMENTS - 1:
			var edge_deg := -RING_END_DEG + float(i + (1 if i == RING_SEGMENTS - 1 else 0)) * step
			posts.append(Transform3D(Basis(Vector3.UP, -deg_to_rad(edge_deg)) * Basis.from_scale(Vector3(0.1, RING_HEIGHT + 0.06, 0.1)), polar(edge_deg, RING_R.x + 0.05, (RING_HEIGHT + 0.06) * 0.5)))
	var unit := BoxMesh.new()
	_multi(parent, "RingWalls", unit, walls, [], 0.0, Color(0.42, 0.45, 0.44))
	_multi(parent, "RingSoil", unit, soil, [], 0.0, Color(0.23, 0.15, 0.1))
	_multi(parent, "RingRims", unit, rims, [], 0.0, Color(0.76, 0.78, 0.8))
	_multi(parent, "RingPosts", unit, posts, [], 0.0, Color(0.93, 0.45, 0.12))
	# drip line along the soil, on short stakes
	var drip: Array[Transform3D] = []
	for i in RING_SEGMENTS:
		var deg := -RING_END_DEG + (float(i) + 0.5) * step
		drip.append(Transform3D(Basis(Vector3.UP, -deg_to_rad(deg)) * Basis.from_scale(Vector3(0.018, 0.018, chord)), polar(deg, mid - 0.12, RING_HEIGHT + 0.06)))
	_multi(parent, "RingDripLine", unit, drip, [], 0.0, Color(0.1, 0.1, 0.11))


## V3+: herbs in rows inside the ring.
func _herbs_in_ring(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	var n := 70
	for i in n:
		var deg := lerpf(-RING_END_DEG + 2.5, RING_END_DEG - 2.5, (float(i) + 0.5) / float(n))
		var r := RING_R.x + 0.16 if i % 2 == 0 else RING_R.y - 0.16
		var col: Color = [Color(0.22, 0.55, 0.2), Color(0.38, 0.66, 0.3), Color(0.3, 0.48, 0.22), Color(0.45, 0.55, 0.35)][i % 4]
		var p := polar(deg, r, RING_HEIGHT)
		for k in 3:   # a bushy tuft of three small lobes
			var a := float(k) * TAU / 3.0 + rng.randf()
			var s := rng.randf_range(0.05, 0.075)
			xs.append(Transform3D(Basis().scaled(Vector3(s, s * 1.15, s)), p + Vector3(cos(a) * 0.045, s * 0.9 + 0.01 * float(k), sin(a) * 0.045)))
			cs.append(col.lerp(Color(0.5, 0.72, 0.35), rng.randf() * 0.3))
	_multi(parent, "Herbs", _sphere(8, 5), xs, cs)


## V3+: shrubs (blueberry, currant) in the middle of the ring, each a cluster of leafy lobes wider than tall, with
## berries; fewer where V4 puts a tree.
func _shrubs(parent: Node3D, level: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	var berries: Array[Transform3D] = []
	var bc: Array[Color] = []
	var n := 26
	for i in n:
		var deg := lerpf(-RING_END_DEG + 6.0, RING_END_DEG - 6.0, (float(i) + 0.5) / float(n))
		if level >= 4 and _near_tree(deg, 7.0):
			continue
		var s := rng.randf_range(0.26, 0.34)
		var centre := polar(deg, (RING_R.x + RING_R.y) * 0.5, RING_HEIGHT + s * 0.55)
		var base_col := Color(0.13, 0.36, 0.15) if i % 2 == 0 else Color(0.2, 0.42, 0.14)
		for k in 6:
			var a := float(k) * TAU / 5.0 + rng.randf() * 0.5
			var off := Vector3(cos(a) * s * 0.45, rng.randf_range(0.0, 0.12), sin(a) * s * 0.45) if k < 5 else Vector3(0, s * 0.3, 0)
			var sk := s * rng.randf_range(0.5, 0.65)
			xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sk, sk * 0.75, sk * 0.85)), centre + off))
			cs.append(base_col.lerp(Color(0.3, 0.52, 0.2), rng.randf() * 0.4))
		for k in 8:
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.1, 0.7), rng.randf_range(-1, 1)).normalized()
			berries.append(Transform3D(Basis().scaled(Vector3.ONE * 0.022), centre + Vector3(dir.x * s * 0.85, dir.y * s * 0.6, dir.z * s * 0.85)))
			bc.append(Color(0.2, 0.25, 0.65) if i % 2 == 0 else Color(0.75, 0.1, 0.15))
	_multi(parent, "Shrubs", _sphere(10, 6), xs, cs)
	_multi(parent, "Berries", _sphere(6, 3), berries, bc, 0.3)


static func _near_tree(deg: float, within: float) -> bool:
	for t: float in TREE_ANGLES:
		if absf(wrapf(deg - t, -180.0, 180.0)) < within:
			return true
	return false


## V4: dwarf fruit trees (apple, lemon, fig) standing in the ring: a trunk that forks into three branches, a crown
## of leafy lobes (kept on the inner side, away from the glass), fruit, and a support stake.
func _trees(parent: Node3D) -> void:
	var wood: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	var cc: Array[Color] = []
	var fruit: Array[Transform3D] = []
	var fc: Array[Color] = []
	var stakes: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 31415
	var fruit_colours := [Color(0.85, 0.15, 0.1), Color(0.98, 0.85, 0.15), Color(0.45, 0.2, 0.35)]
	for i in TREE_ANGLES.size():
		var deg: float = TREE_ANGLES[i]
		var base := polar(deg, TREE_R, RING_HEIGHT)
		var inward := -polar(deg, 1.0)          # towards the dome centre
		var along := polar(deg + 90.0, 1.0)     # along the ring
		var fork := base + Vector3(0, TREE_CROWN_Y - RING_HEIGHT - 0.55, 0) + inward * 0.05
		wood.append(_segment(base, fork, 0.065))
		stakes.append(Transform3D(Basis().scaled(Vector3(0.025, 1.1, 0.025)), base + along * 0.12 + Vector3(0, 0.55, 0)))
		var crown := polar(deg, TREE_R, TREE_CROWN_Y) + inward * 0.12
		var tips: Array[Vector3] = []
		for k in 3:
			var side := float(k - 1)
			var tip := crown + along * side * 0.28 + inward * (0.1 if k == 1 else 0.0) + Vector3(0, -0.05 + 0.1 * float(k % 2), 0)
			tips.append(tip)
			wood.append(_segment(fork, tip, 0.035))
		# crown: lobes round the branch tips, plus one on top
		for k in 7:
			var t: Vector3 = tips[k % 3]
			var off := along * rng.randf_range(-0.15, 0.15) + inward * rng.randf_range(0.0, 0.18) + Vector3(0, rng.randf_range(-0.05, 0.2), 0)
			if k == 6:
				off = Vector3(0, 0.28, 0) + inward * 0.08
			var sk := TREE_CROWN_R * rng.randf_range(0.5, 0.68)
			crowns.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sk, sk * 0.82, sk * 0.9)), t + off))
			cc.append(Color(0.12, 0.38, 0.14).lerp(Color(0.26, 0.5, 0.18), rng.randf()))
		for k in 16:
			var t: Vector3 = tips[k % 3]
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 0.3), rng.randf_range(-1, 1)).normalized()
			if dir.dot(inward) < -0.3:
				dir = (dir + inward).normalized()   # no fruit pressed against the glass
			fruit.append(Transform3D(Basis().scaled(Vector3.ONE * 0.04), t + dir * TREE_CROWN_R * 0.62))
			fc.append(fruit_colours[i % fruit_colours.size()])
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.75
	trunk.bottom_radius = 1.0
	trunk.height = 1.0
	trunk.radial_segments = 8
	trunk.rings = 1
	_multi(parent, "TreeWood", trunk, wood, [], 0.0, Color(0.42, 0.28, 0.16))
	_multi(parent, "TreeStakes", BoxMesh.new(), stakes, [], 0.0, Color(0.62, 0.5, 0.32))
	_multi(parent, "TreeCrowns", _sphere(12, 8), crowns, cc)
	_multi(parent, "Fruit", _sphere(6, 4), fruit, fc, 0.25)


## A unit cylinder placed from `a` to `b` with radius `radius` (for trunks and branches).
static func _segment(a: Vector3, b: Vector3, radius: float) -> Transform3D:
	var d := b - a
	var y := d.normalized()
	var helper := Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT
	var x := y.cross(helper).normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x * radius, d, z * radius), (a + b) * 0.5)


# ---------------------------------------------------------------- mesh helpers

## A unit sphere (radius 1) with few faces, for plant clumps.
static func _sphere(segments: int, rings: int) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = segments
	s.rings = rings
	return s


## One MultiMeshInstance3D under `parent`: `mesh` at every transform. `colours` (one per instance) tint it; empty =
## one `flat` colour. `glow` > 0 makes it shine a little (flowers, fruit).
static func _multi(parent: Node3D, node_name: String, mesh: Mesh, xs: Array[Transform3D], colours: Array = [], glow := 0.0, flat := Color.WHITE) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colours.is_empty()
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		if mm.use_colors:
			mm.set_instance_color(i, colours[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	# A copy of the placements for tests and tools: a headless (dummy) renderer does not keep MultiMesh data.
	mi.set_meta("xforms", xs)
	mi.set_meta("colours", colours)
	mi.material_override = _vc_mat(flat, mm.use_colors, glow)
	if NO_SHADOW.has(node_name):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _vc_mat(flat: Color, per_instance: bool, glow: float) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [flat.to_html(), per_instance, glow]
	if not _vc_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = flat
		m.vertex_color_use_as_albedo = per_instance
		m.roughness = 0.8
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = flat if not per_instance else Color(0.15, 0.15, 0.15)
			m.emission_energy_multiplier = glow
		_vc_mats[key] = m
	return _vc_mats[key]
