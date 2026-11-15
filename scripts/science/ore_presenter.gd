extends Node3D
## Ore deposits in the world (UPGRADE_PATHS_PLAN.md section 9). Presentation only on every machine: it reads
## state.ores and the crew positions and never changes the colony; collecting goes to the host as ore_collect.
## Attached by GameMain, loaded by path (no class_name):
##   load("res://scripts/science/ore_presenter.gd").call(&"attach", self, world, services, self)
##
## What it shows: every REVEALED deposit, and any deposit within SHOW_NEAR_M of a crewmate (so walking finds them;
## OreWalkSystem then reveals it for good on the host). Each deposit is a small cluster of faceted rocks tinted by its
## ore colour (data/ores.json), one MultiMeshInstance3D per deposit (one draw call, culled by its own box): 1 + 2 rocks
## per unit, biggest first, and one rock pair disappears for each unit collected. Unidentified deposits look muted
## (their colour mixed with dust). The danger-salt patch gets a small yellow warning post. Render layers: Exterior
## lighting zone plus the sun-shadow layer, like the scout presenter's outdoor props.
##
## E on a deposit: each deposit has an Area3D (physics layer STATION, a flat cylinder over the rocks) with meta
## "station_id" = deposit id and "ore_deposit" = deposit id, so PlayerController.aimed_target() returns
## {"kind": "station", "id": deposit id}. GameMain._submit turns that use_station into ore_collect (hook line in the
## report). Holding E for HOLD_S asks for HOLD_UNITS more in one go (this presenter sends it). The area is switched off
## (collision layer 0) while the deposit is hidden or empty.

const OreCatalog := preload("res://scripts/science/ore_catalog.gd")
const GROUP := &"ore_presenter"
const VOLUME_GROUP := &"ore_deposit_volume"
const SHOW_NEAR_M := 25.0
const POLL := 0.25
const HOLD_S := 0.8
const HOLD_UNITS := 2
## How much of the dust colour an unidentified deposit's rocks get.
const UNKNOWN_DUST := 0.45
const DUST := Color(0.58, 0.40, 0.28)
const AREA_HEIGHT := 1.8
const HAZARD_YELLOW := Color(0.95, 0.78, 0.12)

var world: Node3D
var services: GameServices
var game: Node
var height: TerrainHeight

## deposit id -> {"node": Node3D, "mm": MultiMeshInstance3D, "area": Area3D, "rocks": int, "shown": bool,
##                "left": int, "known": bool}
var _views: Dictionary = {}
var _rock_mesh: ArrayMesh
var _materials: Dictionary = {}
var _poll_left := 0.0
var _state_id := 0
var _hold_t := 0.0
var _hold_sent := false
var _hold_target := ""


## Creates the presenter under `parent` and sets it up. Returns it.
static func attach(parent: Node, p_world: Node3D, p_services: GameServices, p_game: Node = null) -> Node:
	var script: GDScript = load("res://scripts/science/ore_presenter.gd")
	var presenter: Node3D = script.new()
	presenter.name = "OrePresenter"
	parent.add_child(presenter)
	presenter.call(&"setup", p_world, p_services, p_game)
	return presenter


func setup(p_world: Node3D, p_services: GameServices, p_game: Node = null) -> void:
	world = p_world
	services = p_services
	game = p_game
	add_to_group(GROUP)
	if ResourceLoader.exists("res://data/terrain_height.res"):
		height = load("res://data/terrain_height.res") as TerrainHeight
	_rock_mesh = _make_rock_mesh()
	var root: Node3D = Node3D.new()
	root.name = "OreDeposits"
	if world != null:
		world.add_child(root)
	else:
		add_child(root)
	var mask := _exterior_layers()
	for d: Dictionary in OreCatalog.deposits():
		_views[String(d.id)] = _build_deposit(root, d, mask)
	_refresh()


# ---------------------------------------------------------------- building

func _build_deposit(root: Node3D, d: Dictionary, mask: int) -> Dictionary:
	var id := String(d.id)
	var ore := String(d.ore)
	var at := OreCatalog.position_of(d)
	var ground := _ground(at.x, at.z)
	var node := Node3D.new()
	node.name = id.validate_node_name()
	node.position = Vector3(at.x, ground, at.z)
	node.visible = false
	root.add_child(node)
	var units := int(d.units)
	var rocks := 1 + units * 2
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var ring := String(d.ring)
	var size_k := 1.0 if ring == "near" else (1.2 if ring == "middle" else 1.45)
	var radius := float(d.radius_m)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _rock_mesh
	mm.instance_count = rocks
	var base := OreCatalog.color_of(ore)
	for i: int in range(rocks):
		# biggest first: the last rocks are the first to go as units are collected
		var big := lerpf(0.5, 0.2, float(i) / maxf(1.0, float(rocks - 1))) * size_k
		if ore == "iron_meteorite" and i == 0:
			big = 0.95
		var s := big * rng.randf_range(0.8, 1.2)
		var off := Vector2.ZERO
		if i > 0:
			var a := rng.randf() * TAU
			off = Vector2(cos(a), sin(a)) * radius * sqrt(rng.randf_range(0.05, 1.0))
		var y := _ground(at.x + off.x, at.z + off.y) - ground - s * 0.3
		var rb := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.4, 0.4))
		rb = rb * Basis.from_scale(Vector3(s * rng.randf_range(0.9, 1.4), s * rng.randf_range(0.55, 0.9), s * rng.randf_range(0.9, 1.3)))
		mm.set_instance_transform(i, Transform3D(rb, Vector3(off.x, y, off.y)))
		var shade := rng.randf_range(0.85, 1.1)
		mm.set_instance_color(i, Color(base.r * shade, base.g * shade, base.b * shade, 1.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Rocks"
	mmi.multimesh = mm
	mmi.material_override = _material_for(ore)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mmi.layers = mask
	node.add_child(mmi)
	if OreCatalog.is_hazard(ore):
		_add_warning_post(node, radius, mask)
	var area := Area3D.new()
	area.name = "Pick"
	area.collision_layer = 0
	area.collision_mask = 0
	area.set_meta("station_id", id)
	area.set_meta("ore_deposit", id)
	area.add_to_group(VOLUME_GROUP)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius + 0.3
	cyl.height = AREA_HEIGHT
	shape.shape = cyl
	area.add_child(shape)
	node.add_child(area)
	# built in full colour, so "known" starts true: the first refresh mutes an unidentified deposit
	return {"id": id, "node": node, "mm": mmi, "area": area, "rocks": rocks, "shown": false, "left": -1, "known": true, "ore": ore}


func _add_warning_post(node: Node3D, radius: float, mask: int) -> void:
	var post := MeshInstance3D.new()
	post.name = "WarningPost"
	var pole := CylinderMesh.new()
	pole.top_radius = 0.025
	pole.bottom_radius = 0.025
	pole.height = 1.2
	post.mesh = pole
	var at := Vector2(radius + 0.5, 0.0)
	post.position = Vector3(at.x, _ground(node.position.x + at.x, node.position.z) - node.position.y + 0.6, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.2)
	mat.roughness = 0.7
	post.material_override = mat
	post.layers = mask
	node.add_child(post)
	var plate := MeshInstance3D.new()
	plate.name = "Sign"
	var box := BoxMesh.new()
	box.size = Vector3(0.36, 0.26, 0.02)
	plate.mesh = box
	plate.position = Vector3(0.0, 0.5, 0.0)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = HAZARD_YELLOW
	sm.roughness = 0.5
	plate.material_override = sm
	plate.layers = mask
	post.add_child(plate)


func _material_for(ore: String) -> StandardMaterial3D:
	if _materials.has(ore):
		return _materials[ore] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color.WHITE
	m.roughness = 0.9
	match ore:
		"iron_meteorite":
			m.metallic = 0.75
			m.roughness = 0.45
		"ice":
			m.roughness = 0.2
			m.metallic_specular = 0.7
		"silica", "gypsum":
			m.roughness = 0.45
		"sulfur":
			m.roughness = 0.6
	_materials[ore] = m
	return m


## A faceted low-poly rock about 1 m across (each instance scales it), the same jitter for every copy of a vertex so
## the surface has no cracks; flat shading.
static func _make_rock_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 5
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for i: int in indices:
		var v := verts[i]
		var key := v.snapped(Vector3(0.001, 0.001, 0.001))
		var n := fposmod(sin(key.dot(Vector3(12.9898, 78.233, 37.719))) * 43758.5453, 1.0) - 0.5
		st.add_vertex(v * (1.0 + 0.32 * n))
	st.generate_normals()
	return st.commit()


func _exterior_layers() -> int:
	if services == null or services.zones == null:
		return 1
	var z := services.zones
	var mask := z.bit_of(ColonyZones.EXTERIOR) | z.sun_bit()
	return mask if mask != 0 else 1


func _ground(x: float, z: float) -> float:
	return height.height_at(x, z) if height != null else 0.0


# ---------------------------------------------------------------- every frame

func _process(delta: float) -> void:
	if services == null or not services.has_game():
		return
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = POLL
		_refresh()
	_update_hold(delta)


func _refresh() -> void:
	if services == null or not services.has_game():
		return
	var st := services.state()
	var crew: Array[Vector2] = []
	for key: Variant in st.characters:
		var c := st.characters[key] as CharacterState
		if c != null:
			crew.append(Vector2(c.position.x, c.position.z))
	for id: String in _views:
		var v: Dictionary = _views[id]
		var d := OreCatalog.deposit(id)
		var left := OreCatalog.units_left(st, id)
		var on := left > 0 and OreCatalog.is_revealed(st, id)
		if not on and left > 0:
			var at := OreCatalog.position_of(d)
			var p := Vector2(at.x, at.z)
			for c2: Vector2 in crew:
				if c2.distance_to(p) <= SHOW_NEAR_M + float(d.radius_m):
					on = true
					break
		var known := OreCatalog.is_identified(st, id)
		if on != bool(v.shown):
			v.shown = on
			(v.node as Node3D).visible = on
			(v.area as Area3D).collision_layer = Layers.STATION if on else 0
		if left != int(v.left):
			v.left = left
			((v.mm as MultiMeshInstance3D).multimesh as MultiMesh).visible_instance_count = clampi(1 + left * 2, 0, int(v.rocks)) if left > 0 else 0
		if known != bool(v.known):
			v.known = known
			_tint(v, known)


## Identified deposits show their full ore colour; unknown ones are muted by dust.
func _tint(v: Dictionary, known: bool) -> void:
	var mm := (v.mm as MultiMeshInstance3D).multimesh as MultiMesh
	var base := OreCatalog.color_of(String(v.ore))
	var c := base if known else base.lerp(DUST, UNKNOWN_DUST)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(v.id)) ^ 0x5eed
	for i: int in range(mm.instance_count):
		var shade := rng.randf_range(0.85, 1.1)
		mm.set_instance_color(i, Color(c.r * shade, c.g * shade, c.b * shade, 1.0))


## Holding E on a deposit for HOLD_S asks the host for HOLD_UNITS more (the press itself already took one).
func _update_hold(delta: float) -> void:
	var player: Node = game.get("player") as Node if game != null else null
	if player == null or not player.has_method(&"aimed_target"):
		return
	if not Input.is_action_pressed(&"interact") or not bool(player.get("input_enabled")):
		_hold_t = 0.0
		_hold_sent = false
		_hold_target = ""
		return
	var target: Dictionary = player.call(&"aimed_target")
	var id := String(target.get("id", ""))
	if String(target.get("kind", "")) != "station" or not _views.has(id):
		_hold_t = 0.0
		_hold_target = ""
		return
	if id != _hold_target:
		_hold_target = id
		_hold_t = 0.0
		_hold_sent = false
	_hold_t += delta
	if _hold_t >= HOLD_S and not _hold_sent:
		_hold_sent = true
		services.request(&"ore_collect", StringName(id), {"units": HOLD_UNITS})
