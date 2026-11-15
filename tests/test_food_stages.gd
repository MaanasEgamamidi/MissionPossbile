extends SceneTree
## Food and garden upgrade paths (2026-11-14): the looks (scripts/upgrades/stages/food_stages.gd and garden_stages.gd)
## and what they do (CropSystem: food.yield_factor / food.grow_layers, garden.meals_per_sol).
##   * each greenhouse level builds the right number of grow layers over every bed, inside the room, under the ceiling,
##     inside the beds' own footprints (aisles, walkway, doors and station reach spots stay clear), with no colliders
##   * the garden console exists at every level (V1 too) at its station, the plantings stay inside the dome glass and
##     out of the airlock, aisles and station reach spots
##   * more layers give more food per harvest; garden meals arrive over time, are deterministic, keep the food ledger
##     identity, and survive save and load
## Run: godot --headless --path . --script res://tests/test_food_stages.gd

const FOOD := preload("res://scripts/upgrades/stages/food_stages.gd")
const GARDEN := preload("res://scripts/upgrades/stages/garden_stages.gd")
const MANIFEST := "res://data/colony_manifest.json"
const BIO := &"crew_3"
const PLANTER := &"gd_planter"
## Head height: anything lower than this in a walkway or on a reach spot would be in a player's way.
const HEAD_Y := 2.0
## A player stands within this distance of a station's position to use it.
const REACH_R := 0.75
## Walkways of the Greenhouse (Godot x0, z0, x1, z1): main spine with the west and east doors, the two door paths north,
## the aisles between the bed rows, and the aisle between the shelf racks and the beds.
const GH_WALKS: Array[Rect2] = [
	Rect2(-10.0, 4.0, 24.0, 2.0), Rect2(-6.0, 0.0, 2.0, 4.0), Rect2(8.0, 0.0, 2.0, 4.0),
	Rect2(5.0, 7.85, 6.3, 1.05), Rect2(5.0, 9.7, 6.3, 1.05), Rect2(3.75, 6.0, 1.2, 6.0),
]
## Walkways of the Garden dome: the airlock mouth and central aisle, and the two aisles between the planter columns.
const GD_WALKS: Array[Rect2] = [
	Rect2(42.3, 25.4, 11.2, 3.2), Rect2(47.0, 21.8, 0.95, 10.4), Rect2(49.45, 21.8, 0.95, 10.4),
]

var _passed := 0
var _total := 0
var _zones: ColonyZones
var _catalog: Dictionary
var _event_nodes: Array[GameEvents] = []


func _initialize() -> void:
	_zones = ColonyZones.from_manifest(MANIFEST)
	_catalog = StationCatalog.from_manifest(MANIFEST, _zones)
	AreaLevels.reload()
	_data()
	_food_layers()
	_garden_look()
	_presenter_in_tree()
	_yield()
	_garden_meals()
	await _save_load()
	for e: GameEvents in _event_nodes:
		e.free()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


func _check(label: String, okay: bool, detail := "") -> void:
	_total += 1
	if okay:
		_passed += 1
		print("PASS " + label)
	else:
		print("FAIL " + label + (": " + detail if detail != "" else ""))


# ------------------------------------------------------------------ helpers

## One host session on the real map, `active` crew, plenty of power.
func _session() -> SessionService:
	var ev := GameEvents.new()
	_event_nodes.append(ev)
	var s := SessionService.new(GameConfig.new(), GameBalance.new(), ev)
	var st := ColonyState.new_game(s.balance, 991, _zones.names)
	st.stations = _catalog.duplicate(true)
	for c: CharacterState in st.characters.values():
		c.hub_spot = s.config.hub_position
		c.position = c.hub_spot
	var clock := SolClock.new()
	clock.phase = s.config.start_phase
	s.begin(st, clock)
	st.character(BIO).owner_peer = 1
	s.balance.battery_discharge_kw_max = 1.0e5
	st.capacities[&"battery_kwh"] = 1.0e7
	st.stores[&"battery_kwh"] = 5.0e6
	return s


func _hours(s: SessionService, hours: float, dt: float) -> void:
	var t := 0.0
	while t < hours - 1e-9:
		var h := minf(dt, hours - t)
		var phase := s.clock.phase
		var got := s.clock.advance(h / s.clock.hours_per_real_second())
		for id: StringName in s.sim.step(s.state, s.balance, phase, got):
			s.recover_character(id)
		t += h


## Builds a stage with no game running; returns it under a holder at the origin (caller frees the holder).
func _build(script: Script, level: int) -> Dictionary:
	var p: AreaStagePresenter = script.new()
	var holder := Node3D.new()
	var stage := p.build_stage(level)
	if stage != null:
		holder.add_child(stage)
	p.free()
	return {"holder": holder, "stage": stage}


## World transform from the local ones (works outside the tree).
static func _world(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


static func _local_aabb(mesh: Mesh) -> AABB:
	if mesh is BoxMesh:
		var s := (mesh as BoxMesh).size
		return AABB(-s * 0.5, s)
	if mesh is SphereMesh:
		var sp := mesh as SphereMesh
		return AABB(Vector3(-sp.radius, -sp.height * 0.5, -sp.radius), Vector3(2.0 * sp.radius, sp.height, 2.0 * sp.radius))
	if mesh is CylinderMesh:
		var c := mesh as CylinderMesh
		var r := maxf(c.top_radius, c.bottom_radius)
		return AABB(Vector3(-r, -c.height * 0.5, -r), Vector3(2.0 * r, c.height, 2.0 * r))
	return mesh.get_aabb()


## Every drawn piece under `n`: {"name", "owner", "box" (world AABB), "points" (points on its surface, world)}, one per
## mesh or per MultiMesh instance. The points follow rotated and curved shapes, where an AABB would be too big.
func _pieces(n: Node, out: Array) -> Array:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		out.append({"name": String(mi.name), "owner": _owner_name(mi), "box": _world(mi) * _local_aabb(mi.mesh), "points": _points(mi.mesh, _world(mi))})
	elif n is MultiMeshInstance3D:
		var mmi := n as MultiMeshInstance3D
		var local := _local_aabb(mmi.multimesh.mesh)
		var w := _world(mmi)
		for t: Transform3D in mmi.get_meta("xforms", []):
			out.append({"name": String(mmi.name), "owner": "", "box": (w * t) * local, "points": _points(mmi.multimesh.mesh, w * t)})
	for c in n.get_children():
		_pieces(c, out)
	return out


## Points on a primitive's surface in world space: a 5 x 2 x 5 grid on a box, rings on a sphere, rims of a cylinder.
static func _points(mesh: Mesh, xf: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var steps := [-0.5, -0.25, 0.0, 0.25, 0.5]
	if mesh is SphereMesh:
		var sp := mesh as SphereMesh
		for lat: float in [-90.0, -50.0, -20.0, 0.0, 20.0, 50.0, 90.0]:
			for k in 12:
				var a := float(k) * TAU / 12.0
				var c := cos(deg_to_rad(lat))
				out.append(xf * Vector3(cos(a) * c * sp.radius, sin(deg_to_rad(lat)) * sp.height * 0.5, sin(a) * c * sp.radius))
	elif mesh is CylinderMesh:
		var cy := mesh as CylinderMesh
		for end: float in [-0.5, 0.5]:
			var r := cy.bottom_radius if end < 0.0 else cy.top_radius
			for k in 12:
				var a := float(k) * TAU / 12.0
				out.append(xf * Vector3(cos(a) * r, end * cy.height, sin(a) * r))
	else:
		var b := _local_aabb(mesh)
		for i: float in steps:
			for k: float in steps:
				for j: float in [0.0, 1.0]:
					out.append(xf * (b.get_center() + Vector3(i * b.size.x, (j - 0.5) * b.size.y, k * b.size.z)))
	return out


func _owner_name(n: Node) -> String:
	var p := n.get_parent()
	while p != null:
		if p.has_meta("station_id"):
			return String(p.get_meta("station_id"))
		p = p.get_parent()
	return ""


static func _hits_rect(box: AABB, r: Rect2) -> bool:
	return box.position.y < HEAD_Y and Rect2(box.position.x, box.position.z, box.size.x, box.size.z).intersects(r)


static func _hits_disc(box: AABB, centre: Vector2, radius: float) -> bool:
	if box.position.y >= HEAD_Y:
		return false
	var nx := clampf(centre.x, box.position.x, box.end.x)
	var nz := clampf(centre.y, box.position.z, box.end.z)
	return Vector2(nx, nz).distance_to(centre) < radius


static func _points_in_rect(points: PackedVector3Array, r: Rect2) -> bool:
	for p in points:
		if p.y < HEAD_Y and r.has_point(Vector2(p.x, p.z)):
			return true
	return false


static func _points_in_disc(points: PackedVector3Array, centre: Vector2, radius: float) -> bool:
	for p in points:
		if p.y < HEAD_Y and Vector2(p.x, p.z).distance_to(centre) < radius:
			return true
	return false


func _stations_in(zone: String) -> Array:
	var out: Array = []
	for id: String in _catalog:
		if String(_catalog[id].zone) == zone:
			out.append(id)
	return out


static func _has_collision(n: Node) -> bool:
	if n is CollisionObject3D or n is CollisionShape3D:
		return true
	for c in n.get_children():
		if _has_collision(c):
			return true
	return false


# ------------------------------------------------------------------ data

func _data() -> void:
	var layers: Array = []
	var factors: Array = []
	var garden: Array = []
	for lvl in range(1, 5):
		layers.append(int(AreaLevels.effect_at("food", "grow_layers", lvl, 0)))
		factors.append(float(AreaLevels.effect_at("food", "yield_factor", lvl, 0.0)))
		garden.append(float(AreaLevels.effect_at("garden", "meals_per_sol", lvl, -1.0)))
	_check("data: the greenhouse has 1, 2, 3, 4 grow layers at V1..V4", layers == [1, 2, 3, 4], str(layers))
	_check("data: the yield factor is 1 at V1 and rises with every level", is_equal_approx(factors[0], 1.0) and factors[1] > factors[0] and factors[2] > factors[1] and factors[3] > factors[2], str(factors))
	_check("data: the garden adds no meals at V1 and more at every level", garden[0] == 0.0 and garden[1] > 0.0 and garden[2] > garden[1] and garden[3] > garden[2], str(garden))
	var st: Dictionary = _catalog.get("upgrade_garden", {})
	var p: Array = st.get("position", [0, 0, 0])
	_check("data: the garden upgrade console is a station in the Garden dome and serves the garden track",
		String(st.get("kind", "")) == "upgrade_console" and String(st.get("zone", "")) == ColonyZones.GARDEN
		and AreaLevels.station_serves("garden", "upgrade_garden", st), str(st))
	_check("data: the console is inside the dome, beside the west airlock (x %.2f, z %.2f) and out of its opening" % [float(p[0]), float(p[2])],
		Vector2(float(p[0]) - 50.0, float(p[2]) - 27.0).length() < 7.0 and float(p[0]) < 45.0 and (float(p[2]) < 25.3 or float(p[2]) > 28.7))


# ------------------------------------------------------------------ greenhouse look

func _food_layers() -> void:
	var v1 := _build(FOOD, 1)
	_check("greenhouse V1 is the map as it is (no extra build)", v1.stage == null)
	(v1.holder as Node).free()
	var room := AABB(FOOD.ROOM_MIN - Vector3(0, 0.001, 0), FOOD.ROOM_MAX - FOOD.ROOM_MIN + Vector3(0, 0.001, 0))
	for lvl in range(2, 5):
		var b := _build(FOOD, lvl)
		var stage: Node3D = b.stage
		var want := lvl - 1
		var racks := stage.get_children().filter(func(c: Node) -> bool: return String(c.name).begins_with("Rack_"))
		var counts: Array = []
		for r: Node in racks:
			counts.append(r.get_children().filter(func(c: Node) -> bool: return String(c.name).begins_with("Layer_")).size())
		var trays: Array = (stage.get_node("Trays") as Node).get_meta("xforms", [])
		_check("greenhouse V%d: %d racks, each with %d added layer(s) over its bed (%d layers in all), %d trays" % [lvl, FOOD.BEDS.size(), want, lvl, trays.size()],
			racks.size() == FOOD.BEDS.size() and counts.all(func(c: int) -> bool: return c == want) and trays.size() == FOOD.BEDS.size() * want
			and int(stage.get_meta("grow_layers", 0)) == lvl, "%s" % [counts])
		var pieces := _pieces(stage, [])
		var outside: Array = []
		var high := 0.0
		var in_walk: Array = []
		var off_bed: Array = []
		for piece: Dictionary in pieces:
			var box: AABB = piece.box
			high = maxf(high, box.end.y)
			if not room.encloses(box) or box.end.y > FOOD.CEILING_CLEAR + 1e-6:
				outside.append(piece.name)
			for w: Rect2 in GH_WALKS:
				if _hits_rect(box, w):
					in_walk.append(piece.name)
			var on_a_bed := false
			for bed: Dictionary in FOOD.BEDS:
				var c: Vector2 = bed.centre
				var h: Vector2 = bed.half
				if Rect2(c - h - Vector2(0.06, 0.06), 2.0 * h + Vector2(0.12, 0.12)).encloses(Rect2(box.position.x, box.position.z, box.size.x, box.size.z)):
					on_a_bed = true
			if not on_a_bed:
				off_bed.append(piece.name)
		_check("greenhouse V%d: all %d pieces inside the room and under the ceiling (top %.2f m, ceiling tiles at 2.94 m)" % [lvl, pieces.size(), high], outside.is_empty(), str(outside.slice(0, 5)))
		_check("greenhouse V%d: every piece stands inside a bed's own footprint (6 cm margin)" % lvl, off_bed.is_empty(), str(off_bed.slice(0, 5)))
		_check("greenhouse V%d: walkway, door paths and aisles stay clear below head height" % lvl, in_walk.is_empty(), str(in_walk.slice(0, 5)))
		var blocked: Array = []
		for id: String in _stations_in("Greenhouse"):
			var q: Array = _catalog[id].position
			for piece: Dictionary in pieces:
				if _hits_disc(piece.box, Vector2(float(q[0]), float(q[2])), REACH_R):
					blocked.append(id)
					break
		_check("greenhouse V%d: no station's reach spot is touched (%d stations in the room)" % [lvl, _stations_in("Greenhouse").size()], blocked.is_empty(), str(blocked))
		_check("greenhouse V%d: no colliders (visual only)" % lvl, not _has_collision(stage))
		var draws := stage.find_children("*", "GeometryInstance3D", true, false).size()
		_check("greenhouse V%d: %d draw nodes (plants are MultiMeshes)" % [lvl, draws], draws <= 20)
		(b.holder as Node).free()
	# the added layers really are above each bed's own frame and LED bar, and their light bars glow
	var b4 := _build(FOOD, 4)
	var leds: MultiMeshInstance3D = (b4.stage as Node3D).get_node("LedStrips")
	var ok := true
	for bed: Dictionary in FOOD.BEDS:
		if FOOD.layer_base(bed, 2) < float(bed.top) + 0.05:
			ok = false
	_check("greenhouse: the first added layer sits above every bed's own frame and LED bar", ok)
	_check("greenhouse: the LED strips glow", (leds.material_override as StandardMaterial3D).emission_enabled)
	_check("greenhouse V4: the full LED canopy covers every rack", ((b4.stage as Node3D).get_node("LedCanopy") as Node).get_meta("xforms", []).size() == FOOD.BEDS.size())
	(b4.holder as Node).free()


# ------------------------------------------------------------------ garden look

func _garden_look() -> void:
	var counts: Array = []
	for lvl in range(1, 5):
		var b := _build(GARDEN, lvl)
		var stage: Node3D = b.stage
		var console := stage.find_child("GardenConsole", true, false) as Node3D if stage != null else null
		var st: Array = _catalog["upgrade_garden"].position
		var at := _world(console).origin if console != null else Vector3.INF
		_check("garden V%d: the upgrade console is built at its station (%.2f, %.2f)" % [lvl, at.x, at.z],
			console != null and at.distance_to(Vector3(float(st[0]), float(st[1]), float(st[2]))) < 1e-4)
		if console == null:
			(b.holder as Node).free()
			continue
		var lit := console.find_children("LevelLight*", "", true, false).filter(func(n: Node) -> bool: return bool(n.get_meta("lit", false))).size()
		_check("garden V%d: the console shows %d level light(s) lit" % [lvl, lit], lit == lvl)
		var pieces := _pieces(stage, [])
		counts.append(pieces.size())
		var through: Array = []
		var in_walk: Array = []
		for piece: Dictionary in pieces:
			for p: Vector3 in piece.points:
				var r := Vector2(p.x - GARDEN.CENTRE.x, p.z - GARDEN.CENTRE.z).length()
				if r > 7.6 or p.y > GARDEN.glass_height(r) - 0.05:
					through.append(piece.name)
					break
			if piece.owner == "upgrade_garden":
				continue
			for w: Rect2 in GD_WALKS:
				if _points_in_rect(piece.points, w):
					in_walk.append(piece.name)
		_check("garden V%d: all %d pieces stay inside the base ring and under the dome glass" % [lvl, pieces.size()], through.is_empty(), str(through.slice(0, 5)))
		_check("garden V%d: the airlock mouth, the central aisle and the planter aisles stay clear" % lvl, in_walk.is_empty(), str(in_walk.slice(0, 5)))
		var blocked: Array = []
		for id: String in _stations_in(ColonyZones.GARDEN):
			var q: Array = _catalog[id].position
			for piece: Dictionary in pieces:
				if piece.owner == id:
					continue
				if _points_in_disc(piece.points, Vector2(float(q[0]), float(q[2])), REACH_R):
					blocked.append(id)
					break
		_check("garden V%d: no station's reach spot is touched (%d stations in the dome)" % [lvl, _stations_in(ColonyZones.GARDEN).size()], blocked.is_empty(), str(blocked))
		_check("garden V%d: no colliders (visual only)" % lvl, not _has_collision(stage))
		var draws := stage.find_children("*", "GeometryInstance3D", true, false).size()
		_check("garden V%d: %d draw nodes (plants are MultiMeshes)" % [lvl, draws], draws <= 40)
		var names := stage.find_children("*", "MultiMeshInstance3D", true, false).map(func(n: Node) -> String: return String(n.name))
		var want: Array = [[], ["GroundCover", "Herbs", "HerbPots"], ["RingWalls", "RingSoil", "Herbs", "Shrubs"], ["RingWalls", "Shrubs", "TreeCrowns", "TreeWood", "Fruit"]][lvl - 1]
		_check("garden V%d: has %s" % [lvl, ", ".join(want) if not want.is_empty() else "only the console"], want.all(func(w: String) -> bool: return names.has(w)) and (lvl > 1 or names.is_empty()), str(names))
		(b.holder as Node).free()
	_check("garden: every level shows more than the one before (%s pieces)" % str(counts), counts.size() == 4 and counts[1] > counts[0] and counts[2] > counts[1] and counts[3] > counts[2])


## Through the shared presenter base (as the game attaches it): forced levels swap the stage in the world.
func _presenter_in_tree() -> void:
	var world := Node3D.new()
	get_root().add_child(world)
	var made := AreaStages.attach_all(world, world, null, null)
	var food: AreaStagePresenter = made.get("food")
	var garden: AreaStagePresenter = made.get("garden")
	var ok := food != null and garden != null
	var seen: Array = []
	if ok:
		for lvl in range(1, 5):
			food.force_level = lvl
			garden.force_level = lvl
			food.refresh()
			garden.refresh()
			seen.append([food.stage_node() != null, garden.stage_node() != null])
	_check("presenters: the food look appears from V2, the garden console from V1 (%s)" % str(seen),
		ok and seen == [[false, true], [true, true], [true, true], [true, true]])
	world.free()


# ------------------------------------------------------------------ what the levels do

func _ready_bed(s: SessionService, crop: String) -> void:
	CropSystem.ensure(s.state)
	var b := CropSystem.new_bed()
	b["crop"] = crop
	b["progress"] = 1.0
	b["stage"] = "ready"
	(s.state.crops.beds as Dictionary)[String(PLANTER)] = b


func _harvest(s: SessionService) -> ActionResult:
	var c := s.state.character(BIO)
	c.position = CharacterState._v3(s.state.stations[String(PLANTER)].position)
	return s.request(&"harvest", PLANTER, {}, c.owner_peer)


func _yield() -> void:
	var meals: Array = []
	var texts: Array = []
	for lvl in range(1, 5):
		var s := _session()
		s.state.levels["food"] = lvl
		_ready_bed(s, "tomato")
		var before := s.state.store(&"food_meals")
		var r := _harvest(s)
		meals.append(snappedf(s.state.store(&"food_meals") - before, 1e-6))
		texts.append(String(r.changes.get("text", "")) if r.ok else "refused")
	var base := float(FoodBalance.crop("tomato").meals)
	var ok := true
	for i in 4:
		if absf(float(meals[i]) - base * float(AreaLevels.effect_at("food", "yield_factor", i + 1, 1.0))) > 1e-6:
			ok = false
	_check("yield: one tomato harvest gives %s meals at V1..V4 (crop meals x the racks' yield factor)" % str(meals), ok and meals[3] > meals[0])
	_check("yield: CropSystem.harvest_meals is what a harvest adds", is_equal_approx(CropSystem.harvest_meals(_session().state, "tomato"), base))
	_check("yield: V1 says nothing extra, a higher level tells the player about the layers in plain words",
		not String(texts[0]).contains("grow layers") and String(texts[2]).contains("3 grow layers") and String(texts[2]).contains("times the food"), "%s | %s" % [texts[0], texts[2]])


func _garden_meals() -> void:
	# V1: nothing, and no new data in the crops record
	var s1 := _session()
	var food0 := s1.state.store(&"food_meals")
	_hours(s1, GameConfig.SOL_HOURS, 0.25)
	var eaten1 := float(s1.state.ledger.get("meals_eaten", 0.0))
	_check("garden V1: no meals from the dome and nothing written to the crops record",
		not s1.state.crops.has("garden") and absf(s1.state.store(&"food_meals") - (food0 - eaten1)) < 1e-6)
	# V3 for one sol, in two different tick sizes
	var totals: Array = []
	var ident: Array = []
	for dt: float in [0.1, 0.5]:
		var s := _session()
		s.state.levels["garden"] = 3
		var start_food := s.state.store(&"food_meals")
		var start_ledger := s.state.ledger.duplicate()
		_hours(s, GameConfig.SOL_HOURS, dt)
		totals.append(CropSystem.garden_meals_total(s.state))
		var l := s.state.ledger
		var harvested := float(l.get("meals_harvested", 0.0)) - float(start_ledger.get("meals_harvested", 0.0))
		var eaten := float(l.get("meals_eaten", 0.0)) - float(start_ledger.get("meals_eaten", 0.0))
		var recovery := float(l.get("recovery_meals", 0.0)) - float(start_ledger.get("recovery_meals", 0.0))
		ident.append(absf((s.state.store(&"food_meals") - start_food) - (harvested - eaten - recovery)))
	var per_sol := float(AreaLevels.effect_at("garden", "meals_per_sol", 3, 0.0))
	_check("garden V3: one sol adds %.4f meals (garden.meals_per_sol = %s)" % [float(totals[0]), per_sol], absf(float(totals[0]) - per_sol) < 1e-6)
	_check("garden: the meals do not depend on the tick size (%.9f vs %.9f)" % [float(totals[0]), float(totals[1])], absf(float(totals[0]) - float(totals[1])) < 1e-9)
	_check("garden: food ledger identity holds (store change = harvested - eaten - recovery)", ident.all(func(e: float) -> bool: return e < 1e-6), str(ident))
	# a full store takes only what fits
	var s2 := _session()
	s2.state.levels["garden"] = 4
	s2.state.stores[&"food_meals"] = float(s2.state.capacities[&"food_meals"])
	for c: CharacterState in s2.state.characters.values():
		c.owner_peer = 0   # nobody eats: the store stays full
	_hours(s2, 2.0, 0.5)
	_check("garden: a full food store takes nothing more and books nothing", s2.state.store(&"food_meals") == float(s2.state.capacities[&"food_meals"]) and CropSystem.garden_meals_total(s2.state) == 0.0)


func _save_load() -> void:
	var services := GameServices.new()
	services.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/food_stages"), "colony", 2)
	get_root().add_child(services)
	services.start_new_game(1, BIO)
	await process_frame
	services.set_process(false)
	var s := services.session
	s.state.levels["garden"] = 4
	s.state.levels["food"] = 3
	var tick := 1.0 / services.config.sim_tick_hz
	for i in 900:
		s.advance(tick)
	var made := CropSystem.garden_meals_total(s.state)
	var err := services.save_now(&"manual")
	for i in 600:
		s.advance(tick)
	var after_a := CropSystem.garden_meals_total(s.state)
	var food_a := s.state.store(&"food_meals")
	var load := services.continue_game()
	var loaded := CropSystem.garden_meals_total(services.session.state)
	s = services.session
	var lv := [AreaLevels.level(s.state, "garden"), AreaLevels.level(s.state, "food")]
	for i in 600:
		s.advance(tick)
	_check("save/load: the garden's meals so far (%.5f) and both levels come back from the file" % made,
		err == OK and load.is_usable() and made > 0.0 and absf(loaded - made) < 1e-12 and lv == [4, 3], "%s %s %s" % [loaded, made, lv])
	_check("save/load: after loading the garden keeps adding exactly as without the save (%.6f)" % after_a,
		absf(CropSystem.garden_meals_total(s.state) - after_a) < 1e-9 and absf(s.state.store(&"food_meals") - food_a) < 1e-9 and after_a > made,
		"%s vs %s, food %s vs %s" % [CropSystem.garden_meals_total(s.state), after_a, s.state.store(&"food_meals"), food_a])
	services.queue_free()
	await process_frame
