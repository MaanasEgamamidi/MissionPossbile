class_name ScoutPresenter
extends Node
## Scene side of the scout update (presentation only: it reads state.scout and never changes the colony).
##   - puts the models in the world: the scout bay, the half-built scout (until it is finished), the scout rover
##     itself (smoothly following state.scout on every machine), the broken-down rover and the ore deposits (with a
##     survey flag once found);
##   - runs the scout's mast camera: a Camera3D in a SubViewport that sees what the scout sees. The scout bay panel and
##     the HUD show it live, and a still picture is kept of every site it surveyed (local to this machine);
##   - gives every new prop a simple collision box so nobody walks through it.
## Found by panels through the group GROUP.

const GROUP := &"scout_presenter"
const MAST_SIZE := Vector2i(640, 360)
## Seconds between still pictures while the scout looks around a site.
const SNAPSHOT_EVERY := 1.5

var services: GameServices
var world: Node3D
var height: TerrainHeight

var _root: Node3D
var _scout: Node3D
var _kit: Node3D
var _bay: Node3D
var _broken: Node3D
var _ores: Dictionary = {}          # station id -> Node3D
var _viewport: SubViewport
var _camera: Camera3D
var _screen_material: StandardMaterial3D
var _shown_pos := Vector3.ZERO
var _shown_yaw := 0.0
var _placed := false
var _snapshots: Dictionary = {}     # site id -> ImageTexture
var _snap_left := 0.0
var _wheel_turn := 0.0


func setup(p_world: Node3D, p_services: GameServices, _game: Node = null) -> void:
	world = p_world
	services = p_services
	name = "ScoutPresenter"
	add_to_group(GROUP)
	if ResourceLoader.exists("res://data/terrain_height.res"):
		height = load("res://data/terrain_height.res") as TerrainHeight
	_root = Node3D.new()
	_root.name = "ScoutWorld"
	if world != null:
		world.add_child(_root)
	else:
		add_child(_root)
	_build()


## The presenter in the tree, or null.
static func find(tree: SceneTree) -> ScoutPresenter:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as ScoutPresenter


## Live picture of the mast camera (null without a renderer).
func mast_texture() -> Texture2D:
	return _viewport.get_texture() if _viewport != null else null


## The still picture taken while the scout surveyed `site_id`, or null.
func snapshot(site_id: String) -> Texture2D:
	return _snapshots.get(site_id) as Texture2D


## Asks the mast camera to draw while something on screen shows it.
func want_live(on: bool) -> void:
	if _viewport != null and services != null and services.has_game() and not _surveying():
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_WHEN_VISIBLE


func _surveying() -> bool:
	return ScoutSystem.status(services.state()) == "surveying"


# ---------------------------------------------------------------- building

func _build() -> void:
	var st := services.state() if services != null and services.has_game() else null
	var mask := _exterior_layers()
	_bay = ScoutModels.bay()
	_kit = ScoutModels.scout(true)
	_scout = ScoutModels.scout(false)
	var bay_pos := _station_pos(st, "scout_bay", Vector3(18.0, 0.0, 17.0))
	_place(_bay, bay_pos, 0.0)
	_place(_kit, ScoutSystem.dock_position(), ScoutSystem.dock_yaw())
	# Visibility is set before the models enter the tree, and later only when it really changes: the renderer
	# asserts (softshadow_count) when a brand-new instance is hidden in the frame it was created.
	var built := st != null and ScoutSystem.is_built(st)
	_kit.visible = not built
	_scout.visible = built
	for n: Node3D in [_bay, _kit, _scout]:
		_root.add_child(n)
	_solid(_kit, Vector3(1.6, 1.4, 2.2), Vector3(0, 0.7, 0))
	_solid(_bay.get_node("Console") as Node3D, Vector3(0.6, 1.5, 0.4), Vector3(0, 0.75, 0))
	_screen_material = (_bay.get_node("Console/Screen") as MeshInstance3D).material_override as StandardMaterial3D
	# broken-down rover: a dusty copy of the map's own rover
	var source := world.find_child("sf_rover", true, false) as Node3D if world != null else null
	_broken = ScoutModels.broken_rover(source)
	_place(_broken, _station_pos(st, "broken_rover", Vector3(36.0, 0.0, 37.0)), 0.0)
	_root.add_child(_broken)
	_solid(_broken, Vector3(3.0, 2.0, 4.6), Vector3(0, 1.0, 0), deg_to_rad(28.0))
	# ore deposits
	if st != null:
		for id in ScoutSystem.ore_stations(st):
			var kind := ScoutSystem.ore_kind_of(st, id)
			var c: Array = ScoutSystem.ore_info(kind).get("color", [0.5, 0.5, 0.5])
			var n := ScoutModels.ore_deposit(Color(float(c[0]), float(c[1]), float(c[2])), id.hash())
			n.name = id.validate_node_name()
			_place(n, _station_pos(st, id, Vector3.ZERO), 0.0)
			_apply_ore(n, st, id)
			_root.add_child(n)
			_ores[id] = n
	_set_layers(_root, mask)
	_build_mast_camera()
	_placed = false


func _build_mast_camera() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_viewport = SubViewport.new()
	_viewport.name = "MastCamera"
	_viewport.size = MAST_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.near = 0.05
	_camera.far = 600.0
	_camera.current = true
	_viewport.add_child(_camera)


func _place(n: Node3D, at: Vector3, yaw: float) -> void:
	n.position = Vector3(at.x, _ground(at.x, at.z), at.z)
	n.rotation.y = yaw


func _ground(x: float, z: float) -> float:
	return height.height_at(x, z) if height != null else 0.0


func _station_pos(st: ColonyState, id: String, fallback: Vector3) -> Vector3:
	if st != null and st.stations.has(id):
		return CharacterState._v3((st.stations[id] as Dictionary).get("position", [fallback.x, fallback.y, fallback.z]))
	return fallback


## One solid box under `n` (layer WORLD), turned by `yaw` around its centre.
func _solid(n: Node3D, size: Vector3, centre: Vector3, yaw := 0.0) -> void:
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	shape.shape = b
	shape.position = centre
	shape.rotation.y = yaw
	body.add_child(shape)
	n.add_child(body)


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


# ---------------------------------------------------------------- every frame

func _process(delta: float) -> void:
	if services == null or not services.has_game():
		return
	refresh(false, delta)


func refresh(snap := false, delta := 0.0) -> void:
	var st := services.state()
	var built := ScoutSystem.is_built(st)
	_show(_kit, not built)
	_show(_scout, built)
	var target := ScoutSystem.position(st)
	var yaw := float(st.scout.get("yaw", ScoutSystem.dock_yaw()))
	if snap or not _placed:
		_shown_pos = target
		_shown_yaw = yaw
		_placed = true
	else:
		var before := _shown_pos
		# the colony state arrives a few times a second: glide between the updates
		_shown_pos = _shown_pos.lerp(target, clampf(delta * 4.0, 0.0, 1.0))
		_shown_yaw = lerp_angle(_shown_yaw, yaw, clampf(delta * 3.0, 0.0, 1.0))
		_wheel_turn += Vector2(_shown_pos.x - before.x, _shown_pos.z - before.z).length() / 0.25
	_scout.position = Vector3(_shown_pos.x, _ground(_shown_pos.x, _shown_pos.z), _shown_pos.z)
	_scout.rotation.y = _shown_yaw
	for w in _scout.find_children("Wheel_*", "MeshInstance3D", true, false):
		(w as Node3D).rotation.x = -_wheel_turn
	var surveying := ScoutSystem.status(st) == "surveying"
	var head := _scout.get_node_or_null("Body/MastHead") as Node3D
	if head != null:
		head.rotation.y = sin(Time.get_ticks_msec() / 1000.0 * 0.6) * 0.9 if surveying else lerp_angle(head.rotation.y, 0.0, clampf(delta * 2.0, 0.0, 1.0))
	for id: String in _ores:
		_apply_ore(_ores[id] as Node3D, st, id)
	_update_camera(st, surveying, delta)


## Flag once found; one ore-coloured rock fewer for each piece collected.
func _apply_ore(n: Node3D, st: ColonyState, id: String) -> void:
	_show(n.get_node("Flag") as Node3D, ScoutSystem.is_revealed(st, id))
	var left := ScoutSystem.ore_left(st, id)
	for c in n.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("Ore_"):
			_show(c as Node3D, int(String(c.name).trim_prefix("Ore_")) < left * 2)


static func _show(n: Node3D, on: bool) -> void:
	if n.visible != on:
		n.visible = on


func _update_camera(st: ColonyState, surveying: bool, delta: float) -> void:
	if _camera == null:
		return
	var marker := _scout.get_node_or_null("Body/MastHead/Camera") as Node3D
	if marker != null and marker.is_inside_tree():
		_camera.global_transform = marker.global_transform
	var out := ScoutSystem.is_out(st)
	if _screen_material != null:
		_screen_material.albedo_texture = _viewport.get_texture() if out else null
		_screen_material.emission_texture = _viewport.get_texture() if out else null
	if surveying:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_snap_left -= delta
		if _snap_left <= 0.0:
			_snap_left = SNAPSHOT_EVERY
			var img := _viewport.get_texture().get_image()
			if img != null and not img.is_empty():
				_snapshots[String(st.scout.get("target", ""))] = ImageTexture.create_from_image(img)
	elif _viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and not out:
		_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
