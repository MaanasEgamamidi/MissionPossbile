class_name ReturnRoutes
extends RefCounted
## Walking routes from the open ground back to an airlock entrance, for the dust warning's return margin.
## A coarse grid (about 2 m) over the outdoor height map (data/terrain_height.res): a cell is blocked where the ground
## is steeper than the player can walk, where a rock or an outdoor object stands, and inside the glass hall, its exit
## tunnel and the garden dome. Moving costs distance x (1 + slope grade), so slopes take longer.
## A Dijkstra pass from the entrances gives every cell its walking cost home; astar_metres() runs a real A* search
## (AStarGrid2D) on the same grid with the same costs, and both agree.
##
## Entrances: the habitat is closed by the glass hall; its only way out to the open ground is the exit tunnel, whose
## outer airlock door is EnvironmentCollision door 902 (inner door 901). The hangar and airlock doors of the map
## manifest (hgw_door*, Airlock room) all open between rooms inside the hall, so none of them is an outdoor entrance.
##
## The baked grid lives in data/weather/route_grid.res (tools/godot/bake_route_grid.gd, which reads the exact rock
## shapes from the environment scene). Without it the grid is built from the manifest (rocks as boxes from their
## placement matrices), which is slower and a little less exact.

const GRID_PATH := "res://data/weather/route_grid.res"
const TERRAIN_PATH := "res://data/terrain_height.res"
const MANIFEST_PATH := "res://data/colony_manifest.json"
const COLLIDERS_PATH := "res://data/colliders.json"
const ROCK_COLLECTION := "Terrain rocks (realised)"
## Ways in from outside. Position: on the open ground just past the tunnel's outer door (door 902, z 14.55..14.85;
## the tunnel shell ends at z 15.16), Godot coordinates.
const ENTRANCES: Array[Dictionary] = [
	{"id": "tunnel_outer_door", "door_id": 902, "name": "outer door of the exit tunnel", "position": Vector3(22.0, 0.0, 15.7)},
]
## Footprint of the exit tunnel shell (SFX_tunnel_shell, Godot x and z): part of the habitat, not walkable outside.
const TUNNEL_X := Vector2(17.9, 26.1)
const TUNNEL_Z := Vector2(10.0, 15.16)
## The hall's curb reaches this far beyond the glass (SFX_hall_curb vs SFX_hall_glass bounds), metres.
const CURB_PAD := 0.47
## Height of the player's body (PlayerTuning.body_height_m): anything lower than this above the ground blocks a cell.
const BODY_HEIGHT_M := 1.8
## Neighbour offsets (dx, dz): 4 straight, then 4 diagonal.
const STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

static var _shared: ReturnRoutes

## World x and z of the centre of cell (0, 0).
var origin := Vector2.ZERO
var cell := 2.0
var width := 0
var depth := 0
## Cost factor of each cell (>= 1); 0 = blocked.
var weight := PackedFloat32Array()
## Walking cost home from each cell, metres of level walking; -1 = cannot reach an entrance.
var dist := PackedFloat32Array()
## Cell index of each entrance.
var entrance_cells := PackedInt32Array()
## "baked" (from route_grid.res) or "built" (from the manifest at run time).
var origin_kind := ""
var _astar: AStarGrid2D


## The grid every caller shares: the baked one if present, else built once from the data files.
static func shared() -> ReturnRoutes:
	if _shared == null:
		_shared = load_baked()
		if _shared == null:
			_shared = build(WeatherConfig.new())
	return _shared


## The baked grid, or null if it is missing or unreadable.
static func load_baked(path: String = GRID_PATH) -> ReturnRoutes:
	if not ResourceLoader.exists(path):
		return null
	var img := load(path) as Image
	if img == null or not img.has_meta("cell"):
		return null
	var r := ReturnRoutes.new()
	r.origin = img.get_meta("origin")
	r.cell = float(img.get_meta("cell"))
	r.width = img.get_width()
	r.depth = img.get_height()
	r.entrance_cells = img.get_meta("entrance_cells")
	var floats := img.get_data().to_float32_array()
	r.dist.resize(r.width * r.depth)
	r.weight.resize(r.width * r.depth)
	for i in r.width * r.depth:
		r.dist[i] = floats[i * 2]
		r.weight[i] = floats[i * 2 + 1]
	r.origin_kind = "baked"
	return r


## Saves the grid as an Image (R = walking cost home, G = cost factor) with its geometry in the metadata.
func save(path: String = GRID_PATH) -> Error:
	var floats := PackedFloat32Array()
	floats.resize(width * depth * 2)
	for i in width * depth:
		floats[i * 2] = dist[i]
		floats[i * 2 + 1] = weight[i]
	var img := Image.create_from_data(width, depth, false, Image.FORMAT_RGF, floats.to_byte_array())
	img.set_meta("origin", origin)
	img.set_meta("cell", cell)
	img.set_meta("entrance_cells", entrance_cells)
	img.set_meta("about", "Walking cost home (R, metres) and cost factor (G, 0 = blocked) per 2 m cell; see scripts/weather/return_routes.gd")
	return ResourceSaver.save(img, path, ResourceSaver.FLAG_COMPRESS)


# ---------------------------------------------------------------- building

## Builds the grid. `rocks`: [{"xf": Transform3D, "aabb": AABB}] in world space (mesh-local box and its transform);
## empty = rocks as boxes from the manifest's placement matrices.
static func build(config: WeatherConfig, rocks: Array = []) -> ReturnRoutes:
	var r := ReturnRoutes.new()
	r.origin_kind = "built"
	r.cell = config.route_cell_m
	var terrain := load(TERRAIN_PATH) as TerrainHeight if ResourceLoader.exists(TERRAIN_PATH) else null
	var span := Rect2(-150.0, -150.0, 300.0, 300.0)
	if terrain != null and terrain.width > 1:
		span = Rect2(terrain.origin, Vector2(float(terrain.width - 1), float(terrain.depth - 1)) * terrain.cell)
	r.width = maxi(2, int(floor(span.size.x / r.cell)))
	r.depth = maxi(2, int(floor(span.size.y / r.cell)))
	r.origin = span.position + Vector2(r.cell, r.cell) * 0.5
	var n := r.width * r.depth
	var ground := PackedFloat32Array()
	ground.resize(n)
	for j in r.depth:
		for i in r.width:
			var c := r.centre2(i, j)
			ground[j * r.width + i] = terrain.height_at(c.x, c.y) if terrain != null else 0.0
	r.weight.resize(n)
	var max_grade := tan(deg_to_rad(config.route_max_slope_deg))
	for j in r.depth:
		for i in r.width:
			var k := j * r.width + i
			var g := 0.0
			for s in 4:
				var ni := i + STEPS[s].x
				var nj := j + STEPS[s].y
				if ni >= 0 and nj >= 0 and ni < r.width and nj < r.depth:
					g = maxf(g, absf(ground[nj * r.width + ni] - ground[k]) / r.cell)
			r.weight[k] = 0.0 if g > max_grade else 1.0 + config.route_slope_penalty * g
	var manifest: Dictionary = {}
	if FileAccess.file_exists(MANIFEST_PATH):
		manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	r._block_habitat(manifest, config)
	r._block_objects(manifest, ground, config)
	if rocks.is_empty():
		rocks = manifest_rocks(manifest)
	r._block_rocks(rocks, ground, config)
	r._solve()
	return r


## Rocks from the manifest: placement matrix and a mesh-sized box (the rock meshes are about 1.1 m across before scaling).
static func manifest_rocks(manifest: Dictionary) -> Array:
	var out: Array = []
	for o: Dictionary in manifest.get("environment_objects", []):
		if String(o.get("collection", "")) != ROCK_COLLECTION:
			continue
		out.append({"xf": WorldCollision.object_transform(o.matrix_world), "aabb": AABB(Vector3(-0.55, -0.42, -0.55), Vector3(1.1, 1.1, 1.1))})
	return out


func centre2(i: int, j: int) -> Vector2:
	return origin + Vector2(float(i), float(j)) * cell


## Cell (i, j) holding world point x, z (may be outside the grid).
func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(roundi((x - origin.x) / cell), roundi((z - origin.y) / cell))


func in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < depth


func index(c: Vector2i) -> int:
	return c.y * width + c.x


func is_blocked(c: Vector2i) -> bool:
	return not in_grid(c) or weight[index(c)] <= 0.0


## The glass hall (the manifest's dome super-ellipse plus its curb), the exit tunnel and the garden dome.
func _block_habitat(manifest: Dictionary, config: WeatherConfig) -> void:
	var dome: Dictionary = manifest.get("dome", {"cx": 15.0, "cy": 4.0, "rx": 27.3, "ry": 16.3, "n": 60.0})
	var pad := CURB_PAD + config.route_body_radius_m
	var rx := float(dome.rx) + pad
	var ry := float(dome.ry) + pad
	var ex := float(dome.n)
	var garden := Vector2(ColonyZones.GARDEN_CENTRE.x, -ColonyZones.GARDEN_CENTRE.y)
	for j in depth:
		for i in width:
			var c := centre2(i, j)
			var bx := c.x
			var by := -c.y               # Blender y
			var inside_hall := pow(absf((bx - float(dome.cx)) / rx), ex) + pow(absf((by - float(dome.cy)) / ry), ex) < 1.0
			var inside_tunnel := c.x > TUNNEL_X.x - config.route_body_radius_m and c.x < TUNNEL_X.y + config.route_body_radius_m \
				and c.y > TUNNEL_Z.x and c.y < TUNNEL_Z.y + config.route_body_radius_m
			var inside_garden := c.distance_to(garden) < ColonyZones.GARDEN_RADIUS + pad
			if inside_hall or inside_tunnel or inside_garden:
				weight[j * width + i] = 0.0


## Outdoor map objects with collision boxes (trackers, tanks, walls, lander, rovers...) that stand higher than a step.
func _block_objects(manifest: Dictionary, ground: PackedFloat32Array, config: WeatherConfig) -> void:
	if not FileAccess.file_exists(COLLIDERS_PATH):
		return
	var assets: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(COLLIDERS_PATH)) as Dictionary).get("assets", {})
	for o: Dictionary in manifest.get("objects", []):
		if String(o.get("area", "")) != "Exterior" or not (String(o.get("cls", "")) in ["floor", "static", "deco", "dynamic", "ladder"]):
			continue
		var pose := WorldCollision.object_transform(o.matrix_world)
		for box: Dictionary in (assets.get(String(o.get("gc_asset", "")), {}) as Dictionary).get("cols", []):
			var q: Array = box.q
			var combined := pose * Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3]).normalized()), Vector3(box.c[0], box.c[1], box.c[2]))
			var half := Vector3(box.h[0], box.h[1], box.h[2]) * combined.basis.get_scale().abs()
			_block_box(Transform3D(combined.basis.orthonormalized(), combined.origin), AABB(-half, half * 2.0), ground, config, config.route_body_radius_m)


func _block_rocks(rocks: Array, ground: PackedFloat32Array, config: WeatherConfig) -> void:
	for rock: Dictionary in rocks:
		_block_box(rock.xf, rock.aabb, ground, config, 0.0)


## Blocks every cell where the player's body (a vertical line from just above a step to head height, at the cell
## centre) meets the box `local` placed by `xf` (grown sideways by `grow` metres). Tilted panels count too.
func _block_box(xf: Transform3D, local: AABB, ground: PackedFloat32Array, config: WeatherConfig, grow: float) -> void:
	var inv := xf.affine_inverse()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k in 8:
		var p := xf * local.get_endpoint(k)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	lo -= Vector2(grow, grow)
	hi += Vector2(grow, grow)
	var c0 := cell_of(lo.x, lo.y)
	var c1 := cell_of(hi.x, hi.y)
	var scale := xf.basis.get_scale().abs()
	var grown := local.grow(0.0)
	if grow > 0.0:
		grown = AABB(local.position - Vector3(grow / maxf(scale.x, 1e-3), 0.0, grow / maxf(scale.z, 1e-3)),
			local.size + Vector3(2.0 * grow / maxf(scale.x, 1e-3), 0.0, 2.0 * grow / maxf(scale.z, 1e-3)))
	for j in range(maxi(0, c0.y - 1), mini(depth - 1, c1.y + 1) + 1):
		for i in range(maxi(0, c0.x - 1), mini(width - 1, c1.x + 1) + 1):
			var k := j * width + i
			if weight[k] <= 0.0:
				continue
			var c := centre2(i, j)
			var foot := inv * Vector3(c.x, ground[k] + config.route_step_m + 0.05, c.y)
			var head := inv * Vector3(c.x, ground[k] + BODY_HEIGHT_M, c.y)
			if grown.has_point(foot) or grown.has_point(head) or grown.intersects_segment(foot, head) != null:
				weight[k] = 0.0


## Dijkstra from the entrances. Step a -> b costs (cell distance) x weight(b), diagonals only between two free cells:
## exactly the cost model of AStarGrid2D with DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES and weight scales.
func _solve() -> void:
	var n := width * depth
	dist.resize(n)
	dist.fill(-1.0)
	var best := PackedFloat32Array()
	best.resize(n)
	best.fill(INF)
	var done := PackedByteArray()
	done.resize(n)
	var heap_k := PackedFloat32Array()
	var heap_v := PackedInt32Array()
	entrance_cells = PackedInt32Array()
	for e: Dictionary in ENTRANCES:
		var p: Vector3 = e.position
		var c := nearest_free(p, 3)
		if c.x < 0:
			continue
		var k := index(c)
		entrance_cells.append(k)
		var d0 := Vector2(p.x, p.z).distance_to(centre2(c.x, c.y))
		if d0 < best[k]:
			best[k] = d0
			_push(heap_k, heap_v, d0, k)
	while not heap_v.is_empty():
		var top := _pop(heap_k, heap_v)
		var k: int = top[1]
		var d: float = top[0]
		if done[k] == 1 or d > best[k]:
			continue
		done[k] = 1
		dist[k] = d
		var i := k % width
		var j := k / width
		var wk := weight[k]
		for s in 8:
			var ni := i + STEPS[s].x
			var nj := j + STEPS[s].y
			if ni < 0 or nj < 0 or ni >= width or nj >= depth:
				continue
			var nk := nj * width + ni
			if weight[nk] <= 0.0 or done[nk] == 1:
				continue
			var step := cell
			if s >= 4:
				# a diagonal needs both straight neighbours free
				if weight[j * width + ni] <= 0.0 or weight[nj * width + i] <= 0.0:
					continue
				step = cell * sqrt(2.0)
			# walking from nk towards k (homewards) enters k: the cost uses k's weight
			var nd := d + step * wk
			if nd < best[nk]:
				best[nk] = nd
				_push(heap_k, heap_v, nd, nk)


static func _push(keys: PackedFloat32Array, vals: PackedInt32Array, key: float, val: int) -> void:
	keys.append(key)
	vals.append(val)
	var i := keys.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if keys[parent] <= keys[i]:
			break
		var tk := keys[parent]
		keys[parent] = keys[i]
		keys[i] = tk
		var tv := vals[parent]
		vals[parent] = vals[i]
		vals[i] = tv
		i = parent


static func _pop(keys: PackedFloat32Array, vals: PackedInt32Array) -> Array:
	var out := [keys[0], vals[0]]
	var last := keys.size() - 1
	keys[0] = keys[last]
	vals[0] = vals[last]
	keys.resize(last)
	vals.resize(last)
	var i := 0
	var size := last
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var m := i
		if l < size and keys[l] < keys[m]:
			m = l
		if r < size and keys[r] < keys[m]:
			m = r
		if m == i:
			break
		var tk := keys[m]
		keys[m] = keys[i]
		keys[i] = tk
		var tv := vals[m]
		vals[m] = vals[i]
		vals[i] = tv
		i = m
	return out


# ---------------------------------------------------------------- queries

## The free cell nearest to `p` within `radius` cells, or (-1, -1).
func nearest_free(p: Vector3, radius: int) -> Vector2i:
	var c := cell_of(p.x, p.z)
	var best := Vector2i(-1, -1)
	var best_d := INF
	for dj in range(-radius, radius + 1):
		for di in range(-radius, radius + 1):
			var q := c + Vector2i(di, dj)
			if is_blocked(q):
				continue
			var d := Vector2(p.x, p.z).distance_to(centre2(q.x, q.y))
			if d < best_d:
				best_d = d
				best = q
	return best


## The reachable cell to start walking home from `p`: the one within 2 cells (4 m) with the smallest
## (distance to it + its cost home). (-1, -1) if none.
func start_cell(p: Vector3) -> Vector2i:
	var c := cell_of(p.x, p.z)
	var best := Vector2i(-1, -1)
	var best_v := INF
	for dj in range(-2, 3):
		for di in range(-2, 3):
			var q := c + Vector2i(di, dj)
			if is_blocked(q) or dist[index(q)] < 0.0:
				continue
			var v := Vector2(p.x, p.z).distance_to(centre2(q.x, q.y)) + dist[index(q)]
			if v < best_v:
				best_v = v
				best = q
	return best


## Walking cost home from world point `p`, in metres of level walking; -1 if no route is known from there.
func return_metres(p: Vector3) -> float:
	var q := start_cell(p)
	if q.x < 0:
		return -1.0
	return Vector2(p.x, p.z).distance_to(centre2(q.x, q.y)) + dist[index(q)]


## Real seconds to walk home from `p` at `speed_mps`; -1 if unknown.
func return_seconds(p: Vector3, speed_mps: float) -> float:
	var m := return_metres(p)
	return -1.0 if m < 0.0 or speed_mps <= 0.0 else m / speed_mps


## The same walk found by an A* search (AStarGrid2D, same costs). -1 if no path.
func astar_metres(p: Vector3) -> float:
	var q := start_cell(p)
	if q.x < 0 or entrance_cells.is_empty():
		return -1.0
	_ensure_astar()
	var best := INF
	for ek in entrance_cells:
		var goal := Vector2i(ek % width, ek / width)
		var path := _astar.get_id_path(q, goal)
		if path.is_empty():
			continue
		var cost := 0.0
		for s in range(1, path.size()):
			cost += Vector2(path[s - 1]).distance_to(Vector2(path[s])) * cell * weight[index(path[s])]
		var e: Vector3 = ENTRANCES[0].position
		cost += Vector2(e.x, e.z).distance_to(centre2(goal.x, goal.y))
		best = minf(best, cost)
	if not is_finite(best):
		return -1.0
	return best + Vector2(p.x, p.z).distance_to(centre2(q.x, q.y))


## The A* route home from `p` as world points (for maps and debugging); empty if none.
func route(p: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var q := start_cell(p)
	if q.x < 0 or entrance_cells.is_empty():
		return out
	_ensure_astar()
	var ek := entrance_cells[0]
	for id in _astar.get_id_path(q, Vector2i(ek % width, ek / width)):
		var c := centre2(id.x, id.y)
		out.append(Vector3(c.x, 0.0, c.y))
	return out


## Cells that are free and can reach home, for tests and reports.
func reachable_cells() -> int:
	var count := 0
	for d in dist:
		if d >= 0.0:
			count += 1
	return count


func _ensure_astar() -> void:
	if _astar != null:
		return
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, width, depth)
	_astar.cell_size = Vector2(1, 1)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_astar.update()
	for j in depth:
		for i in width:
			var w := weight[j * width + i]
			if w <= 0.0:
				_astar.set_point_solid(Vector2i(i, j), true)
			else:
				_astar.set_point_weight_scale(Vector2i(i, j), w)
