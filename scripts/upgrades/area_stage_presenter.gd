class_name AreaStagePresenter
extends Node3D
## Base of the look of one upgrade path (AreaLevels). One subclass per track in scripts/upgrades/stages/, attached by
## AreaStages. It watches the track's level and shows the matching stage:
##   * V1 is today's map model: a subclass normally builds nothing for level 1 (build_stage returns null).
##   * V2..V4 add equipment around the area. A subclass builds each stage as its own Node3D in build_stage(level);
##     stages are cumulative or not, as the subclass likes (it builds the whole look of that level).
## The base handles: waiting for the game, polling the level, swapping stages with a short grow-in, putting every mesh
## on the render layers of the zone it stands in (rooms only light and draw their own layer), and the debug override.
## Subclasses only implement track_id() and build_stage(); anchor() helps them find map objects and stations.
##
## Visual-only. Never change state here: levels change only through the host action upgrade_area.

const POLL_SECONDS := 0.5
const GROW_SECONDS := 0.6

var world: Node3D
var services: GameServices
var game: Node

## Level shown now (0 = nothing built yet).
var shown_level := 0
## Tests and tools can force a level without touching the colony (-1 = follow the colony).
var force_level := -1

var _stage: Node3D
var _poll := 0.0
var _grow := 0.0


## Track id in data/area_levels.json. Subclasses override.
func track_id() -> String:
	return ""


## The look of `level` (2..4 usually), as a new Node3D in world coordinates, or null for "map model only".
## Subclasses override. Called again whenever the level changes.
func build_stage(_level: int) -> Node3D:
	return null


func setup(p_world: Node3D, p_services: GameServices, p_game: Node = null) -> void:
	world = p_world
	services = p_services
	game = p_game
	name = "Stages_%s" % track_id()
	add_to_group(&"area_stage_presenters")


## Level the colony is at now (or the forced one).
func current_level() -> int:
	if force_level >= 1:
		return force_level
	if services == null or not services.has_game():
		return 0
	return AreaLevels.level(services.state(), track_id())


## Rebuilds right away (tests call this after setting force_level).
func refresh() -> void:
	_poll = 0.0
	_apply(current_level())


func _process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = POLL_SECONDS
		var lvl := current_level()
		if lvl != shown_level:
			_apply(lvl)
	if _grow > 0.0 and _stage != null:
		_grow = maxf(0.0, _grow - delta)
		var t := 1.0 - _grow / GROW_SECONDS
		var s := 0.85 + 0.15 * (1.0 - pow(1.0 - t, 3.0))
		_stage.scale = Vector3.ONE * s


func _apply(lvl: int) -> void:
	if lvl == shown_level:
		return
	var had := shown_level > 0
	shown_level = lvl
	if _stage != null:
		_stage.queue_free()
		_stage = null
	if lvl <= 0:
		return
	var node := build_stage(lvl)
	if node == null:
		return
	node.name = "Stage_V%d" % lvl
	var parent: Node = stage_parent()
	parent.add_child(node)
	_stage = node
	put_on_zone_layers(node)
	if had:
		_grow = GROW_SECONDS
		node.scale = Vector3.ONE * 0.85


## Where a stage node is added. The world by default (stage nodes are then in world coordinates). A presenter whose
## look rides on something that moves (the rover, the drone) returns that body instead and builds in its local space.
func stage_parent() -> Node:
	return world if world != null else self


## The stage node now in the world, or null.
func stage_node() -> Node3D:
	return _stage


# ---------------------------------------------------------------- helpers for subclasses

## Render-layer mask for a world position: the zone it is in, plus the sun layer outdoors.
func layers_at(p: Vector3) -> int:
	if services == null or services.zones == null:
		return 1
	var z := services.zones
	var zone := z.zone_at_world(p)
	var mask := z.bit_of(zone)
	if zone == ColonyZones.PLAZA or zone == ColonyZones.GARDEN or zone == ColonyZones.EXTERIOR:
		mask |= z.sun_bit()
	return mask if mask != 0 else 1


## Puts every visual under `n` on the layers of the zone at its own world position.
func put_on_zone_layers(n: Node) -> void:
	if n is VisualInstance3D:
		var v := n as VisualInstance3D
		var p := (v as Node3D).global_position if v.is_inside_tree() else Vector3.ZERO
		v.layers = layers_at(p)
	for c in n.get_children():
		put_on_zone_layers(c)


## World position of a station (StationCatalog id), or `fallback`.
func station_position(station_id: String, fallback := Vector3.ZERO) -> Vector3:
	if services == null or not services.has_game():
		return fallback
	var st: Dictionary = services.state().stations.get(station_id, {})
	var p: Variant = st.get("position", null)
	if p is Array and (p as Array).size() >= 3:
		return Vector3(float(p[0]), float(p[1]), float(p[2]))
	return fallback


## First node in the world whose name is `node_name` (map objects keep their Blender names), or null.
func anchor(node_name: String) -> Node3D:
	if world == null:
		return null
	return world.find_child(node_name, true, false) as Node3D


## A plain material (cached per colour).
static var _mats: Dictionary = {}
static func mat(c: Color, metallic := 0.0, rough := 0.7, emission := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [c.to_html(), metallic, rough, emission]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = metallic
		m.roughness = rough
		if emission > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = emission
		_mats[key] = m
	return _mats[key]


## A box mesh instance (size in metres) at local position `at` under `parent`.
static func box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	mi.position = at
	parent.add_child(mi)
	return mi


## A cylinder mesh instance under `parent`.
static func cylinder(parent: Node3D, radius: float, height: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = material
	mi.position = at
	parent.add_child(mi)
	return mi
