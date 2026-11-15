extends Node3D
## Dead plants in the Garden dome (owner request, 2026-11-15): the dome is broken and shattered at the start of the game
## but its plants looked healthy; "let's make them look a bit dead at the start before we ... fix everything".
## Rule: while the dome glass is broken (task T08 "Repair the broken glass" not done: BrokenPartPresenter.is_task_broken,
## i.e. PuzzleRegistry.is_broken), every plant in the Garden dome looks a bit dead: browned/yellowed, desaturated,
## darker and matte, the crop rows drooped (scale Y about 0.75-0.85 from their soil line) with a small lean, and a few
## plants more dead than others (seeded per plant, so it is stable). Not black, not deleted: "these plants need help".
## When T08 is fixed while the game runs (the replicated state changes), the plants come back to healthy: after the
## glass swap (0.35 s) a gold sparkle burst (scripts/tasks/sparkle_burst.gd) and a 1.5 s ease of colour and shape.
## Loading a save, joining late or starting a new colony shows the right look at once, without the animation.
## Which plants:
##   - map objects (data/colony_manifest.json, area "Garden Dome"): the six crop rows (gd_crop_*), the three potted
##     sprouts, the seed tray's sprouts and the hydroponics unit's leaves. Only their plant surfaces (materials gd_leaf*,
##     gd_rib, gd_corn, gd_silk, gd_beet, gd_carrot, gd_fruit, gd_lettuce_red) get a dead copy of their own material as a
##     surface override; pots, soil, stakes and drip lines keep theirs. Only the crop rows droop (the pots, tray and rack
##     would squash with their sprouts). The harvest crate's produce is left alone.
##   - the garden upgrade stage's plants (scripts/upgrades/stages/garden_stages.gd, V2+): GroundCover, Flowers, Herbs,
##     Shrubs, Berries, TreeCrowns and Fruit get materials/withered_plant.gdshader as their material_override.
## The broken dome model (BP05) is glass only, so nothing here overlaps it. Presentation only: it reads the colony state
## and never changes it; render layers are never touched; no per-frame work except the state poll and the 1.5 s ease.
## Attached by GameMain next to the broken-part presenter; loaded by path (no class_name).

const BrokenParts := preload("res://scripts/tasks/broken_part_presenter.gd")
const SparkleBurst := preload("res://scripts/tasks/sparkle_burst.gd")
const WITHERED_SHADER := preload("res://materials/withered_plant.gdshader")
const GROUP := &"dome_plants_presenter"
const TASK_ID := "T08"
const PLANT_ASSETS: Array[String] = ["gd_crop_tomato", "gd_crop_carrot", "gd_crop_lettuce", "gd_crop_corn",
	"gd_crop_beet", "gd_crop_chard", "gd_pot_sprout", "gd_seed_tray_fill", "gd_hydro"]
## Map plants that also droop and lean (whole crop rows standing in a planter).
const DROOP_PREFIX := "gd_crop_"
const PLANT_MATERIALS: Array[String] = ["gd_leaf", "gd_leaf_dk", "gd_leaf_md", "gd_rib", "gd_corn", "gd_silk",
	"gd_beet", "gd_carrot", "gd_fruit", "gd_lettuce_red"]
## Upgrade-stage plant nodes (name prefixes).
const STAGE_PLANTS: Array[String] = ["GroundCover", "Flowers", "Herbs", "Shrubs", "Berries", "TreeCrowns", "Fruit"]
## How dead a plant is: a few plants get the strongest look.
const SEVERITIES: Array[float] = [0.6, 0.8, 1.0]
const SEED := 20261115
## Dry straw/olive brown the leaves turn towards.
const DRY := Color(0.55, 0.4, 0.18)
const SPARKLE_TINT := Color(1.0, 0.75, 0.2)
## Seconds after the fix before the plants start to recover (the dome glass swaps back at 0.35 s), and of the ease.
const DELAY := 0.35
const EASE_SECONDS := 1.5
## Seconds between reads of the colony state and of the garden's upgrade stage.
const POLL := 0.2
const STAGE_POLL := 0.5

var world: Node3D
var services: GameServices
var game: Node
## Use CPU particles: -1 = follow the graphics preset (Low = CPU), 0 = GPU, 1 = CPU.
var force_cpu := -1
## Recoveries started since setup (tests).
var recoveries_started := 0

## Map plants: {"mi", "surfaces": [int], "saved": [Material], "dead": [Material], "on", "droop", "rest", "pivot",
## "axis", "angle", "sy", "sev"}.
var _map: Array[Dictionary] = []
## Dead copies of map materials by "<source id>:<severity index>": {"dup", "albedo", "vec3", "rough", "grime", "sev"}.
var _dead_mats := {}
## Upgrade-stage plants: {"node", "saved", "mat"}.
var _stage_plants: Array[Dictionary] = []
var _stage_mats := {}
var _stage_id := 0
## How dead the plants look now: 1 = dead, 0 = healthy.
var _dead := 0.0
## Seconds into the recovery, or -1.
var _anim := -1.0
var _sparkled := false
var _state_id := 0
var _broken_now := false
var _poll_left := 0.0
var _stage_left := 0.0


## Creates the presenter under `parent` and sets it up. Returns it.
static func attach(parent: Node, p_world: Node3D, p_services: GameServices, p_game: Node = null) -> Node:
	var script: GDScript = load("res://scripts/world/dome_plants_presenter.gd")
	var presenter: Node3D = script.new()
	presenter.name = "DomePlantsPresenter"
	parent.add_child(presenter)
	presenter.call(&"setup", p_world, p_services, p_game)
	return presenter


func setup(p_world: Node3D, p_services: GameServices, p_game: Node = null) -> void:
	world = p_world
	services = p_services
	game = p_game
	add_to_group(GROUP)
	top_level = true
	_collect_map()
	_follow_stage()
	snap()


## The dead look of colour `c` at severity `s` (0..1): desaturated, browned towards DRY, darker. Alpha stays.
static func wither(c: Color, s: float) -> Color:
	var l := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	var dry := DRY * (0.55 + l)
	var out := c.lerp(Color(l, l, l), 0.45 * s).lerp(dry, 0.6 * s)
	var dark := 1.0 - 0.22 * s
	return Color(out.r * dark, out.g * dark, out.b * dark, c.a)


## True while the plants show their dead look (also during the recovery).
func looks_dead() -> bool:
	return _dead > 0.0


## True while the recovery runs.
func in_recovery() -> bool:
	return _anim >= 0.0


## Number of map plant meshes and of upgrade-stage plant nodes found (checks and tools).
func plant_counts() -> Vector2i:
	return Vector2i(_map.size(), _stage_plants.size())


# ---------------------------------------------------------------- finding the plants

static func _asset_of(mi: Node) -> String:
	var a := String(mi.get_meta("gc_asset", ""))
	return a if a != "" else String(mi.name)


static func _is_plant_asset(asset: String) -> bool:
	for p: String in PLANT_ASSETS:
		if asset == p or asset.begins_with(p + "_") or asset.begins_with(p + "."):
			return true
	return false


func _collect_map() -> void:
	_map.clear()
	if world == null:
		return
	for node in world.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.material_override != null:
			continue
		var asset := _asset_of(mi)
		if not _is_plant_asset(asset):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(mi.name)) ^ SEED
		var roll := rng.randf()
		var sev_index := 2 if roll < 0.3 else (1 if roll < 0.75 else 0)
		var sev: float = SEVERITIES[sev_index]
		var surfaces: Array[int] = []
		var saved: Array = []
		var dead: Array = []
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m == null or not PLANT_MATERIALS.has(String(m.resource_name)):
				continue
			var rec := _dead_material(m, sev_index)
			if rec.is_empty():
				continue
			surfaces.append(i)
			saved.append(mi.get_surface_override_material(i))
			dead.append(rec.dup)
		if surfaces.is_empty():
			continue
		var e := {"mi": mi, "surfaces": surfaces, "saved": saved, "dead": dead, "on": false, "sev": sev,
			"droop": asset.begins_with(DROOP_PREFIX), "rest": mi.transform}
		if bool(e.droop):
			var box := mi.get_aabb()
			var c := box.get_center()
			e.pivot = Vector3(c.x, _plant_base_y(mi.mesh, surfaces), c.z)
			# Rows tip over sideways: about their long horizontal axis.
			e.axis = Vector3.RIGHT if box.size.x >= box.size.z else Vector3.BACK
			e.angle = deg_to_rad(rng.randf_range(2.0, 4.5)) * sev * (1.0 if rng.randf() < 0.5 else -1.0)
			e.sy = clampf(0.87 - 0.12 * sev + rng.randf_range(-0.02, 0.02), 0.74, 0.86)
		_map.append(e)


## Lowest point of the plant surfaces (the soil line the row droops from), in the mesh's space.
static func _plant_base_y(mesh: Mesh, surfaces: Array[int]) -> float:
	var low := INF
	for i: int in surfaces:
		var arrays := mesh.surface_get_arrays(i)
		if arrays.size() <= Mesh.ARRAY_VERTEX or not (arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array):
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var stride := maxi(1, verts.size() / 4000)
		var j := 0
		while j < verts.size():
			low = minf(low, verts[j].y)
			j += stride
	return mesh.get_aabb().position.y if is_inf(low) else low


## The shared dead copy of a map plant material for one severity, or {} when it has no colour to change.
func _dead_material(src: Material, sev_index: int) -> Dictionary:
	var key := "%d:%d" % [src.get_instance_id(), sev_index]
	if _dead_mats.has(key):
		return _dead_mats[key]
	var rec := {}
	if src is ShaderMaterial:
		var sm := src as ShaderMaterial
		var a: Variant = sm.get_shader_parameter(&"albedo")
		if not (a is Color or a is Vector3):
			return {}
		var col: Color = a if a is Color else Color((a as Vector3).x, (a as Vector3).y, (a as Vector3).z)
		var r: Variant = sm.get_shader_parameter(&"roughness")
		var g: Variant = sm.get_shader_parameter(&"grime")
		rec = {"albedo": col, "vec3": a is Vector3, "rough": float(r) if (r is float or r is int) else -1.0,
			"grime": float(g) if (g is float or g is int) else -1.0}
	elif src is BaseMaterial3D:
		var bm := src as BaseMaterial3D
		rec = {"albedo": bm.albedo_color, "vec3": false, "rough": bm.roughness, "grime": -1.0}
	else:
		return {}
	rec.dup = src.duplicate()
	rec.sev = SEVERITIES[sev_index]
	_dead_mats[key] = rec
	return rec


func _garden_stages() -> AreaStagePresenter:
	if game != null:
		var d: Variant = game.get(&"area_stages")
		if d is Dictionary and (d as Dictionary).get("garden") is AreaStagePresenter:
			return (d as Dictionary).get("garden") as AreaStagePresenter
	if is_inside_tree():
		for p in AreaStages.all(get_tree()):
			if p.track_id() == "garden":
				return p
	return null


## Picks up the plants of the garden's upgrade stage whenever the stage is rebuilt, and gives them the current look.
func _follow_stage() -> void:
	var presenter := _garden_stages()
	var node: Node3D = presenter.stage_node() if presenter != null else null
	var nid := node.get_instance_id() if node != null and is_instance_valid(node) else 0
	if nid == _stage_id:
		return
	_stage_id = nid
	_stage_plants.clear()          # the old stage was freed by its presenter: nothing to give back
	if nid == 0:
		return
	for n in node.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not _is_stage_plant(String(g.name)) or not (g.material_override is BaseMaterial3D):
			continue
		var src := g.material_override as BaseMaterial3D
		_stage_plants.append({"node": g, "saved": src, "mat": _stage_material(src)})
	for e: Dictionary in _stage_plants:
		_apply_stage(e, _dead)


static func _is_stage_plant(node_name: String) -> bool:
	for p: String in STAGE_PLANTS:
		if node_name.begins_with(p):
			return true
	return false


func _stage_material(src: BaseMaterial3D) -> ShaderMaterial:
	var key := src.get_instance_id()
	if _stage_mats.has(key):
		return _stage_mats[key]
	var m := ShaderMaterial.new()
	m.shader = WITHERED_SHADER
	m.set_shader_parameter(&"base_color", src.albedo_color)
	m.set_shader_parameter(&"use_vertex_color", src.vertex_color_use_as_albedo)
	m.set_shader_parameter(&"roughness_healthy", src.roughness)
	if src.emission_enabled:
		m.set_shader_parameter(&"emission_color", src.emission)
		m.set_shader_parameter(&"emission_energy", src.emission_energy_multiplier)
	m.set_shader_parameter(&"amount", 1.0)
	_stage_mats[key] = m
	return m


# ---------------------------------------------------------------- state

func _state() -> ColonyState:
	return services.state() if services != null and services.has_game() else null


func _is_broken(st: ColonyState) -> bool:
	return st != null and BrokenParts.is_task_broken(st, TASK_ID)


## Shows the plants as the colony state says, with no animation (load, late join, new colony).
func snap() -> void:
	var st := _state()
	_state_id = st.get_instance_id() if st != null else 0
	_broken_now = _is_broken(st)
	_anim = -1.0
	_apply(1.0 if _broken_now else 0.0)


func _process(delta: float) -> void:
	step(delta)


## One update: follow the state and the garden stage, run the recovery. Tests call it directly.
func step(delta: float) -> void:
	if _anim >= 0.0:
		_advance(delta)
	_stage_left -= delta
	if _stage_left <= 0.0:
		_stage_left = STAGE_POLL
		_follow_stage()
	_poll_left -= delta
	if _poll_left > 0.0:
		return
	_poll_left = POLL
	var st := _state()
	if (st.get_instance_id() if st != null else 0) != _state_id:
		snap()          # another colony was loaded or joined: show it as it is
		return
	var broken := _is_broken(st)
	if broken == _broken_now:
		return
	_broken_now = broken
	if not broken and _dead > 0.0 and TutorialSystem.is_fixed(st, TASK_ID):
		if _anim < 0.0:
			_anim = 0.0
			_sparkled = false
			recoveries_started += 1
	else:
		_anim = -1.0
		_apply(1.0 if broken else 0.0)


func _advance(delta: float) -> void:
	_anim += delta
	if _anim < DELAY:
		return
	if not _sparkled:
		_sparkled = true
		_sparkle()
	if _anim >= DELAY + EASE_SECONDS:
		_anim = -1.0
		_apply(0.0)
	else:
		_apply(1.0 - smoothstep(DELAY, DELAY + EASE_SECONDS, _anim))


## Puts every plant at deadness `k` (1 = dead, 0 = healthy: their own materials and transforms back).
func _apply(k: float) -> void:
	_dead = clampf(k, 0.0, 1.0)
	for rec: Dictionary in _dead_mats.values():
		_set_dead_params(rec, _dead)
	for e: Dictionary in _map:
		_apply_map(e, _dead)
	for e: Dictionary in _stage_plants:
		_apply_stage(e, _dead)


func _set_dead_params(rec: Dictionary, k: float) -> void:
	var sev: float = rec.sev
	var healthy: Color = rec.albedo
	var col := healthy.lerp(wither(healthy, sev), k)
	var r: float = rec.rough
	var g: float = rec.grime
	var dup: Variant = rec.dup
	if dup is ShaderMaterial:
		var sm := dup as ShaderMaterial
		sm.set_shader_parameter(&"albedo", Vector3(col.r, col.g, col.b) if bool(rec.vec3) else col)
		if r >= 0.0:
			sm.set_shader_parameter(&"roughness", lerpf(r, lerpf(r, 0.9, 0.6 * sev), k))
		if g >= 0.0:
			sm.set_shader_parameter(&"grime", lerpf(g, minf(1.0, g + 0.25 * sev), k))
	elif dup is BaseMaterial3D:
		var bm := dup as BaseMaterial3D
		bm.albedo_color = col
		bm.roughness = lerpf(r, lerpf(r, 0.9, 0.6 * sev), k)


func _apply_map(e: Dictionary, k: float) -> void:
	var obj: Variant = e.mi
	if not is_instance_valid(obj):
		return
	var mi := obj as MeshInstance3D
	var on := k > 0.0
	if on != bool(e.on):
		e.on = on
		var surfaces: Array = e.surfaces
		var mats: Array = e.dead if on else e.saved
		for n in surfaces.size():
			mi.set_surface_override_material(int(surfaces[n]), mats[n] as Material)
	if bool(e.droop):
		mi.transform = (e.rest as Transform3D) * _droop_transform(e, k)


## The crop row's droop at deadness `k`, in its own mesh space: squashed towards its soil line and tipped a little
## about its long axis.
static func _droop_transform(e: Dictionary, k: float) -> Transform3D:
	if k <= 0.0:
		return Transform3D.IDENTITY
	var pivot: Vector3 = e.pivot
	var axis: Vector3 = e.axis
	var b := Basis(axis, float(e.angle) * k) * Basis.from_scale(Vector3(1.0, lerpf(1.0, float(e.sy), k), 1.0))
	return Transform3D(Basis.IDENTITY, pivot) * Transform3D(b, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)


func _apply_stage(e: Dictionary, k: float) -> void:
	var obj: Variant = e.node
	if not is_instance_valid(obj):
		return
	var g := obj as GeometryInstance3D
	var mat := e.mat as ShaderMaterial
	if k > 0.0:
		mat.set_shader_parameter(&"amount", k)
		if g.material_override != mat:
			g.material_override = mat
	elif g.material_override == mat:
		g.material_override = e.saved as Material


# ---------------------------------------------------------------- the gold sparkle

func _use_cpu() -> bool:
	if force_cpu >= 0:
		return force_cpu == 1
	var level := GraphicsQuality.applied_level(get_tree())
	if level < 0 and game != null and game.get(&"settings") != null:
		level = int(game.get(&"settings").get(&"graphics_quality"))
	return level == GraphicsQuality.Level.LOW


## One burst over each crop row, one over the other map plants (bench and rack) and one over the stage plants.
func _sparkle() -> void:
	if not is_inside_tree():
		return
	var cpu := _use_cpu()
	var rest := AABB()
	var rest_mask := 0
	var have_rest := false
	for e: Dictionary in _map:
		var obj: Variant = e.mi
		if not is_instance_valid(obj):
			continue
		var mi := obj as MeshInstance3D
		if not mi.is_visible_in_tree():
			continue
		var box := mi.global_transform * mi.get_aabb()
		if bool(e.droop):
			SparkleBurst.spawn(self, box, mi.layers, cpu, SPARKLE_TINT)
		else:
			rest = rest.merge(box) if have_rest else box
			rest_mask |= mi.layers
			have_rest = true
	if have_rest:
		SparkleBurst.spawn(self, rest, rest_mask, cpu, SPARKLE_TINT)
	var plants := AABB()
	var plants_mask := 0
	var have_plants := false
	for e: Dictionary in _stage_plants:
		var obj: Variant = e.node
		if not is_instance_valid(obj):
			continue
		var g := obj as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var box := g.global_transform * g.get_aabb()
		if box.size == Vector3.ZERO:
			continue
		plants = plants.merge(box) if have_plants else box
		plants_mask |= g.layers
		have_plants = true
	if have_plants:
		SparkleBurst.spawn(self, plants, plants_mask, cpu, SPARKLE_TINT)
