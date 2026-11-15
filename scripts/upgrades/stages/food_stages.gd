extends AreaStagePresenter
## Look of the "food" upgrade path (Greenhouse grow racks, data/area_levels.json). Procedural meshes, no textures.
##   V1  the map as it is: four grow beds (wheat, potatoes, strawberry gutter, peppers), one growing layer each with a
##       single LED bar on its frame
##   V2  a rack over each bed: aluminium posts and one more tray of leafy greens above the bed, lit by its own LED bar
##   V3  a third layer, and drip lines on every tray fed by a white supply riser with a blue valve
##   V4  a fourth layer and a full LED canopy panel over each rack, under the ceiling
## The bed on the floor is layer 1; each level adds one tray above it (food.grow_layers = 1..4).
##
## Where the layers go (measured from data/colony_manifest.json, data/colliders.json and the beds' meshes, 2026-11-14):
## each bed's frame and LED bar reach `top`; the ceiling of the bed area is at 2.94 m (lamp tiles) to 2.95 m, so the
## added trays fill the space between top + 0.06 m and CEILING_CLEAR in equal steps (shallow trays of leafy greens and
## microgreens, as in real vertical farms). The fifth bed (gr_straw_gutter.001) stands under the hanging ceiling grow
## lights (2.52 m) and has no room above it, so it stays as it is.
## The racks stand inside each bed's own footprint (its collider), so the aisles between the beds, the main walkway,
## the doors and the greenhouse console stay clear. Visual only: no colliders (the bed's own collider already keeps
## players out of the footprint). Every kind of part is one MultiMesh, so a stage costs about a dozen draw calls.

## Each bed: map object, footprint centre (x, z) and half size (x along the bed, z across), top of its frame (y).
const BEDS: Array[Dictionary] = [
	{"object": "gr_wheat_bed", "centre": Vector2(6.6, 11.256), "half": Vector2(1.3, 0.4), "top": 1.69},
	{"object": "gr_potato_bed", "centre": Vector2(9.6, 11.25), "half": Vector2(1.3, 0.4), "top": 2.0},
	{"object": "gr_straw_gutter", "centre": Vector2(6.575, 9.313), "half": Vector2(1.55, 0.2), "top": 2.06},
	{"object": "gr_pepper_row", "centre": Vector2(9.912, 9.285), "half": Vector2(1.4, 0.21), "top": 2.16},
]
## Greenhouse room (manifest rooms: x -10..14, Blender y -12..0 = Godot z 0..12, ceiling 3.0; tiles hang to 2.94).
const ROOM_MIN := Vector3(-10.0, 0.0, 0.0)
const ROOM_MAX := Vector3(14.0, 2.94, 12.0)
## Nothing goes higher than this (5 cm under the lowest ceiling tile above the beds).
const CEILING_CLEAR := 2.88
## The stage root stands here (the middle of the bed area), so the grow-in scales about it and every mesh is in the
## Greenhouse zone's render layer.
const AREA_CENTRE := Vector3(8.2, 0.0, 10.2)
const MAX_LAYERS := 4
const CANOPY_THICK := 0.06
const TRAY_THICK := 0.045
const POST := 0.04

## Small or glowing parts cast no shadow (cheaper; their shadows would be specks).
const NO_SHADOW: Array[String] = ["Greens", "LedStrips", "LedCanopy", "DripEmitters", "DripLines"]

static var _vc_mats: Dictionary = {}


func track_id() -> String:
	return "food"


## Grow layers at `level` (the effect table, so the look and the yield always agree).
static func layers_at_level(level: int) -> int:
	return clampi(int(AreaLevels.effect_at("food", "grow_layers", level, level)), 1, MAX_LAYERS)


## Height of the bottom of added layer `n` (2..4) over a bed, and the step between layers.
static func layer_base(bed: Dictionary, n: int) -> float:
	return float(bed.top) + 0.06 + float(n - 2) * layer_pitch(bed)


static func layer_pitch(bed: Dictionary) -> float:
	return (CEILING_CLEAR - CANOPY_THICK - (float(bed.top) + 0.06)) / float(MAX_LAYERS - 1)


func build_stage(level: int) -> Node3D:
	var layers := layers_at_level(level)
	if layers <= 1:
		return null
	var root := Node3D.new()
	root.position = AREA_CENTRE
	root.set_meta("grow_layers", layers)
	var parts := _Parts.new()
	for bed: Dictionary in BEDS:
		_rack(root, parts, bed, layers)
	var unit := BoxMesh.new()
	_multi(root, "RackPosts", unit, parts.posts, [], 0.0, Color(0.74, 0.76, 0.79), 0.7)
	_multi(root, "ShelfBars", unit, parts.bars, [], 0.0, Color(0.6, 0.62, 0.65), 0.7)
	_multi(root, "Trays", unit, parts.trays, [], 0.0, Color(0.9, 0.9, 0.88))
	_multi(root, "TrayRails", unit, parts.rails, [], 0.0, Color(0.55, 0.57, 0.6), 0.6)
	_multi(root, "LedHousings", unit, parts.housings, [], 0.0, Color(0.32, 0.33, 0.35), 0.6)
	_multi(root, "LedStrips", unit, parts.leds, [], 2.6, Color(1.0, 0.36, 0.86))
	_multi(root, "Greens", _sphere(9, 5), parts.plants, parts.plant_colours)
	if not parts.drips.is_empty():
		_multi(root, "DripLines", unit, parts.drips, [], 0.0, Color(0.08, 0.08, 0.09))
		_multi(root, "DripEmitters", unit, parts.emitters, [], 0.0, Color(0.15, 0.45, 0.85))
		var riser := CylinderMesh.new()
		riser.top_radius = 1.0
		riser.bottom_radius = 1.0
		riser.height = 1.0
		riser.radial_segments = 10
		riser.rings = 1
		_multi(root, "SupplyRisers", riser, parts.risers, [], 0.0, Color(0.93, 0.93, 0.92))
		_multi(root, "Valves", unit, parts.valves, [], 0.0, Color(0.16, 0.4, 0.85))
	if not parts.canopy.is_empty():
		_multi(root, "CanopyFrames", unit, parts.canopy_frames, [], 0.0, Color(0.3, 0.31, 0.33), 0.6)
		_multi(root, "LedCanopy", unit, parts.canopy, [], 1.8, Color(1.0, 0.5, 0.9))
	return root


## Collected transforms of every part kind (one MultiMesh each), relative to AREA_CENTRE.
class _Parts:
	var posts: Array[Transform3D] = []
	var bars: Array[Transform3D] = []
	var trays: Array[Transform3D] = []
	var rails: Array[Transform3D] = []
	var housings: Array[Transform3D] = []
	var leds: Array[Transform3D] = []
	var plants: Array[Transform3D] = []
	var plant_colours: Array = []
	var drips: Array[Transform3D] = []
	var emitters: Array[Transform3D] = []
	var risers: Array[Transform3D] = []
	var valves: Array[Transform3D] = []
	var canopy: Array[Transform3D] = []
	var canopy_frames: Array[Transform3D] = []


## One rack over `bed` with layers 2..`layers`. Adds a marker node "Rack_<object>" with a "Layer_<n>" child per added
## layer (tests count them) and fills `parts`.
func _rack(root: Node3D, parts: _Parts, bed: Dictionary, layers: int) -> void:
	var c: Vector2 = bed.centre
	var h: Vector2 = bed.half
	var o := Vector3(c.x, 0.0, c.y) - AREA_CENTRE
	var pitch := layer_pitch(bed)
	var marker := Node3D.new()
	marker.name = "Rack_%s" % String(bed.object).validate_node_name()
	marker.position = o
	marker.set_meta("bed", bed.object)
	marker.set_meta("layers", layers)
	root.add_child(marker)
	var top_y := layer_base(bed, layers) + pitch
	if layers >= MAX_LAYERS:
		top_y = CEILING_CLEAR
	var len_x := 2.0 * h.x
	var dep_z := 2.0 * h.y
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(bed.object))
	# four posts at the footprint's corners and a top tie bar at each end
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			parts.posts.append(_xf(o + Vector3(sx * (h.x - POST * 0.5), top_y * 0.5, sz * (h.y - POST * 0.5)), Vector3(POST, top_y, POST)))
		parts.bars.append(_xf(o + Vector3(sx * (h.x - POST * 0.5), top_y - 0.015, 0.0), Vector3(POST, 0.03, dep_z)))
	# one crop per tray, as in a real farm: green lettuce, red lettuce, kale, basil
	var crops := [Color(0.42, 0.72, 0.28), Color(0.55, 0.18, 0.22), Color(0.17, 0.4, 0.2), Color(0.3, 0.62, 0.2)]
	var bed_index := BEDS.find(bed)
	for n in range(2, layers + 1):
		var y := layer_base(bed, n)
		var layer := Node3D.new()
		layer.name = "Layer_%d" % n
		layer.position = Vector3(0.0, y, 0.0)
		marker.add_child(layer)
		# shelf: cross bars at both ends, the tray, a rail along each long edge
		for sx: int in [-1, 1]:
			parts.bars.append(_xf(o + Vector3(sx * (h.x - POST * 0.5), y - 0.012, 0.0), Vector3(POST, 0.025, dep_z)))
		parts.trays.append(_xf(o + Vector3(0.0, y + TRAY_THICK * 0.5, 0.0), Vector3(len_x - 2.0 * POST, TRAY_THICK, dep_z - 0.02)))
		for sz: int in [-1, 1]:
			parts.rails.append(_xf(o + Vector3(0.0, y + TRAY_THICK + 0.012, sz * (h.y - 0.012)), Vector3(len_x - 2.0 * POST, 0.025, 0.018)))
		# the greens: rows of leafy rosettes every 0.17 m, wide enough that leaves spill over the tray's edges
		var plant_h := clampf(pitch - TRAY_THICK - 0.07, 0.07, 0.16)
		var rows := maxi(2, int(round(dep_z / 0.2)))
		var cols := int(floor((len_x - 0.14) / 0.17))
		var crop: Color = crops[(bed_index + n) % crops.size()]
		for i in cols:
			for j in rows:
				var px := -len_x * 0.5 + 0.07 + 0.085 + float(i) * 0.17 + rng.randf_range(-0.02, 0.02)
				var pz := -h.y + dep_z * (float(j) + 0.5) / float(rows) + rng.randf_range(-0.02, 0.02)
				var tint := crop.lerp(Color(0.55, 0.8, 0.35), rng.randf() * 0.18)
				_rosette(parts, o + Vector3(px, y + TRAY_THICK, pz), rng.randf_range(0.075, 0.095), plant_h * rng.randf_range(0.8, 1.0), tint, rng)
		# its LED bar(s) just under the layer above (or under the canopy): a dark housing with a glowing strip
		var led_y := y + pitch - 0.03
		var bars := 2 if dep_z > 0.5 else 1
		for k in bars:
			var bz := 0.0 if bars == 1 else (-h.y * 0.5 if k == 0 else h.y * 0.5)
			parts.housings.append(_xf(o + Vector3(0.0, led_y + 0.012, bz), Vector3(len_x - 0.25, 0.018, 0.09)))
			parts.leds.append(_xf(o + Vector3(0.0, led_y - 0.002, bz), Vector3(len_x - 0.3, 0.012, 0.06)))
		# V3+: a drip line along the back of every tray, with emitters
		if layers >= 3:
			var dz := h.y - 0.05
			parts.drips.append(_xf(o + Vector3(0.0, y + TRAY_THICK + 0.03, dz), Vector3(len_x - 0.12, 0.014, 0.014)))
			for e in int((len_x - 0.2) / 0.34):
				parts.emitters.append(_xf(o + Vector3(-len_x * 0.5 + 0.2 + float(e) * 0.34, y + TRAY_THICK + 0.022, dz - 0.012), Vector3(0.022, 0.016, 0.022)))
	if layers >= 3:
		# supply riser up the far post, with a valve at hand height
		var rx := h.x - POST - 0.03
		var rz := h.y - 0.05
		parts.risers.append(_xf(o + Vector3(rx, top_y * 0.5, rz), Vector3(0.018, top_y, 0.018)))
		parts.valves.append(_xf(o + Vector3(rx, 1.25, rz), Vector3(0.07, 0.05, 0.05)))
	if layers >= MAX_LAYERS:
		# full LED canopy: a lit panel over the whole rack, in a dark frame, right under the ceiling
		parts.canopy_frames.append(_xf(o + Vector3(0.0, CEILING_CLEAR - 0.02, 0.0), Vector3(len_x, 0.04, dep_z)))
		parts.canopy.append(_xf(o + Vector3(0.0, CEILING_CLEAR - CANOPY_THICK + 0.01, 0.0), Vector3(len_x - 0.08, 0.02, dep_z - 0.06)))


## One plant head: five leaves round a small heart, the leaf tips raised, no taller than `height`.
static func _rosette(parts: _Parts, at: Vector3, radius: float, height: float, tint: Color, rng: RandomNumberGenerator) -> void:
	var tilt := clampf(asin(clampf((height - 0.02) / radius, 0.0, 1.0)), 0.2, 0.75)
	var spin := rng.randf() * TAU
	for k in 5:
		var b := Basis(Vector3.UP, spin + float(k) * TAU / 5.0 + rng.randf_range(-0.2, 0.2)) * Basis(Vector3.BACK, tilt)
		var leaf_len := radius * rng.randf_range(0.9, 1.1)
		parts.plants.append(Transform3D(b * Basis.from_scale(Vector3(leaf_len * 0.5, 0.012, leaf_len * 0.3)), at + Vector3(0, 0.015, 0) + b * Vector3(leaf_len * 0.45, 0, 0)))
		parts.plant_colours.append(tint.darkened(rng.randf() * 0.15))
	parts.plants.append(_xf(at + Vector3(0, height * 0.35, 0), Vector3(radius * 0.4, height * 0.35, radius * 0.4)))
	parts.plant_colours.append(tint.lightened(0.12))


## A box/sphere transform: scale `size`, at `at` (both relative to AREA_CENTRE).
static func _xf(at: Vector3, size: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(size), at)


static func _sphere(segments: int, rings: int) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = segments
	s.rings = rings
	return s


## One MultiMeshInstance3D under `parent`. `colours` (one per instance) tint it; empty = one `flat` colour.
static func _multi(parent: Node3D, node_name: String, mesh: Mesh, xs: Array[Transform3D], colours: Array = [], glow := 0.0, flat := Color.WHITE, metal := 0.0) -> MultiMeshInstance3D:
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
	mi.material_override = _vc_mat(flat, mm.use_colors, glow, metal)
	if NO_SHADOW.has(node_name):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _vc_mat(flat: Color, per_instance: bool, glow: float, metal: float) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [flat.to_html(), per_instance, glow, metal]
	if not _vc_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = flat
		m.vertex_color_use_as_albedo = per_instance
		m.metallic = metal
		m.roughness = 0.4 if metal > 0.0 else 0.75
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = flat
			m.emission_energy_multiplier = glow
		_vc_mats[key] = m
	return _vc_mats[key]
