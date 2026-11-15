extends SceneTree
## Bakes the gold tape trails (owner 2026-11-14, Wolverine-style guide lines): data/tape_trails.json.
## One walkable path per room tape, all starting together just inside the base (the hangar side of the exit tunnel's
## inner door 901) and fanning out through the rooms and doorways to each tape's floor anchor
## (data/stations_repairs.json "cassette_anchor" entries, "position").
##
## How (headless, no map visuals):
##   1. World collision from data (WorldCollision.build: manifest + colliders.json floors, walls, furniture), the
##      terrain height body (the plaza ground) and, when the local cache is there, the baked prop shapes
##      (data/prop_collision_cache.bin, written by PropCollision when the game loads the map: machines, racks, plants).
##      Door leaves are on the DOOR physics layer and are ignored: tutorial doors are held open.
##   2. A walk grid of CELL m cells inside the base (rooms, plaza, garden dome; not the open exterior): a cell is
##      walkable when a ray finds floor under it and a standing body capsule fits there.
##   3. One shortest-path tree from the start (Dijkstra, 8 neighbours, steps up to STEP_M), with extra cost close to
##      walls so the lines keep off them. The tapes' paths are branches of that tree, so where two paths share a
##      corridor they share it exactly.
##   4. Each branch between two fork points is string-pulled (straight runs that keep the clearance of the original
##      path, or CLEAR_WANT_M), then the lines are spread side by side where they share a corridor: lane order from a
##      left-to-right walk of the tree, so lines never cross, spacing from the corridor's width, eased in and out.
##   5. Points rounded to cm; heights from the floor under each point.
## Owner 2026-11-15 (first-week sparkle guide; gold + sparkles always mean "this works / go this way"): the walk grid of
## step 2 is also saved, as data/walk_grid.bin (WALK_OUT), so the game can draw a gold sparkle line from anywhere to
## anything on it (scripts/guide/walk_paths.gd + guide_sparkles.gd). Format: FileAccess.store_var of a Dictionary
##   {"version": 1, "origin": Vector2 (x, z of cell 0's corner), "cell": m, "cols", "rows",
##    "walk": bytes (1 = a standing body fits there), "height_cm": signed 16-bit little-endian per cell (the drawn floor,
##    0 where not walkable), "clear_cm": byte per cell (clearance to the nearest blocked cell, cm, capped at 255),
##    "sizes": {key: uncompressed byte count}}, each byte array ZSTD-compressed (PackedByteArray.compress).
## Run: godot --headless --path . --script res://tools/godot/bake_tape_trails.gd [-- --png <file.png>]

const MANIFEST := "res://data/colony_manifest.json"
const COLLIDERS := "res://data/colliders.json"
const TERRAIN := "res://data/terrain_height.res"
const PROP_CACHE := "res://data/prop_collision_cache.bin"
const OUT := "res://data/tape_trails.json"
## The walk grid for the runtime guide lines (owner 2026-11-15), see the header.
const WALK_OUT := "res://data/walk_grid.bin"
const WALK_VERSION := 1
## Just inside the base: the airlock side of the exit tunnel's inner door (EnvironmentCollision door 901, z 10.30-10.65).
const START := Vector3(22.0, 0.03, 9.0)
## Inside of the exit tunnel (EnvironmentCollision door leaves span x 20.2..23.8; the shell ends at z 15.16) and a
## little of the ground in front of it, walkable for the garden dome's line. The tunnel walls are scenery (not built here).
const TUNNEL_X := Vector2(20.5, 23.5)
const TUNNEL_Z := Vector2(9.9, 17.2)
const CELL := 0.2
const BOUNDS := Rect2(-16.0, -24.0, 80.0, 64.0)       # Godot x, z
const BODY_RADIUS := 0.26
const BODY_HEIGHT := 1.8
const BODY_LIFT := 0.14                                # capsule bottom above the floor (steps lower than this pass)
const STEP_M := 0.22
const RAY_TOP := 0.6
const RAY_BOTTOM := -0.6
## Clearance (distance to the nearest cell where the body does not fit) wanted around the lines.
const CLEAR_WANT_M := 0.7
const WALL_COST := 5.0
## Lanes: spacing between neighbouring lines and how close a line may come to a wall.
const LANE_MAX := 0.34
const LANE_MIN := 0.24
const RIBBON_HALF := 0.11
const WALL_KEEP := 0.12
const SAMPLE := 0.1
const EASE_M := 1.2
const SIMPLIFY_TOL := 0.02
## Spacing of the lines on the start bar, and how far they take to ease from it into their lanes.
const START_BAR := 0.3
const START_EASE_M := 1.8

var cols := 0
var rows := 0
var floor_y := PackedFloat32Array()
var walk := PackedByteArray()
var clear := PackedFloat32Array()
var zones: ColonyZones
var space: PhysicsDirectSpaceState3D
var terrain: TerrainHeight
var reached := PackedFloat32Array()


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	var png := ""
	for i in args.size():
		if args[i] == "--png" and i + 1 < args.size():
			png = args[i + 1]
	zones = ColonyZones.from_manifest(MANIFEST)
	var collision := WorldCollision.build(MANIFEST, COLLIDERS)
	root.add_child(collision)
	if ResourceLoader.exists(TERRAIN):
		terrain = load(TERRAIN) as TerrainHeight
		if terrain != null:
			collision.add_child(terrain.make_body())
	var props := _add_prop_cache(collision)
	print("collision: %s, prop shapes from the cache: %d" % [WorldCollision.stats(collision), props])
	await physics_frame
	await physics_frame
	space = root.world_3d.direct_space_state
	_sample_grid()
	_clearance()
	_write_walk_grid()
	var start := _nearest_walkable(START, 2.0)
	if start < 0:
		push_error("bake_tape_trails: no walkable cell near the start %s" % START)
		quit(1)
		return
	var tree := _dijkstra(start)
	var dist: PackedFloat32Array = tree.dist
	reached = dist
	var parent: PackedInt32Array = tree.parent
	# ---- raw paths (cell lists from the start) to each tape's floor anchor
	var anchors := _anchors()
	var ids: Array = anchors.keys()
	ids.sort()
	var raw := {}
	for id: String in ids:
		var goal := _nearest_reached(anchors[id], dist, 2.5)
		if goal < 0:
			push_error("bake_tape_trails: %s is not reachable from the start" % id)
			continue
		var cells: Array[int] = []
		var c := goal
		while c >= 0:
			cells.append(c)
			c = parent[c]
		cells.reverse()
		raw[id] = cells
	# ---- the shared tree: which trails pass each cell
	var users := {}
	for id: String in raw:
		for c: int in raw[id]:
			if not users.has(c):
				users[c] = []
			(users[c] as Array).append(id)
	# chains: runs of cells with the same set of trails
	var chain_pts := {}          # chain key -> simplified world points (shared by every trail on it)
	var trail_chains := {}       # id -> [chain keys in order]
	for id: String in raw:
		var cells: Array = raw[id]
		var keys: Array = []
		var run: Array[int] = [cells[0]]
		var run_key := _set_key(users[cells[0]])
		for i in range(1, cells.size()):
			var k := _set_key(users[cells[i]])
			if k != run_key:
				keys.append(_store_chain(chain_pts, run_key, run, cells[i]))
				run = [cells[i - 1]]
				run_key = k
			run.append(cells[i])
		keys.append(_store_chain(chain_pts, run_key, run, -1))
		trail_chains[id] = keys
	# ---- lane order: a left-to-right walk of the tree
	var order := _lane_order(raw, users)
	# ---- centre lines, lanes, offsets
	var out := {}
	var lengths := {}
	for id: String in raw:
		var centre: Array[Vector3] = []
		for key: String in trail_chains[id]:
			for p: Vector3 in chain_pts[key]:
				if centre.is_empty() or centre[-1].distance_to(p) > 0.01:
					centre.append(p)
		var anchor: Vector3 = anchors[id]
		if Vector2(centre[-1].x, centre[-1].z).distance_to(Vector2(anchor.x, anchor.z)) > 0.05:
			centre.append(Vector3(anchor.x, centre[-1].y, anchor.z))
		var line := _offset_line(id, centre, users, order)
		line = _simplify(line)
		var pts: Array = []
		var length := 0.0
		for i in line.size():
			var p := line[i]
			p.y = _floor_at(p, p.y)
			if i > 0:
				length += line[i - 1].distance_to(line[i])
			pts.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
		out[id] = pts
		lengths[id] = length
	_write(out, lengths, _cell_pos(start))
	for id: String in ids:
		if out.has(id):
			var last: Array = (out[id] as Array)[-1]
			var a: Vector3 = anchors[id]
			print("%-26s %6.1f m  %3d points  ends %.2f m from the anchor" % [id, lengths[id], (out[id] as Array).size(),
				Vector2(float(last[0]), float(last[2])).distance_to(Vector2(a.x, a.z))])
		else:
			print("%-26s NO PATH" % id)
	if png != "":
		_save_png(png, out, raw)
	print("baked %d of %d trails to %s in %d ms (grid %d x %d, %d walkable)" % [out.size(), ids.size(), OUT, Time.get_ticks_msec() - t0, cols, rows, _count_walkable()])
	quit(0 if out.size() == ids.size() else 1)


# ---------------------------------------------------------------- collision

func _add_prop_cache(collision: Node3D) -> int:
	if not FileAccess.file_exists(PROP_CACHE):
		return 0
	var f := FileAccess.open(PROP_CACHE, FileAccess.READ)
	var data: Variant = f.get_var() if f != null else null
	if not data is Dictionary or not (data as Dictionary).get("entries") is Array:
		return 0
	var body := StaticBody3D.new()
	body.name = "Props"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	collision.add_child(body)
	var n := 0
	for e: Dictionary in data.entries:
		var cs := CollisionShape3D.new()
		var pts: PackedVector3Array = e.points
		if String(e.kind) == "hull":
			var convex := ConvexPolygonShape3D.new()
			convex.points = pts
			cs.shape = convex
		else:
			var concave := ConcavePolygonShape3D.new()
			concave.backface_collision = true
			concave.set_faces(pts)
			cs.shape = concave
		body.add_child(cs)
		n += 1
	return n


# ---------------------------------------------------------------- grid

func _idx(cx: int, cz: int) -> int:
	return cz * cols + cx


func _cell_pos(i: int) -> Vector3:
	var cx := i % cols
	var cz := i / cols
	return Vector3(BOUNDS.position.x + (cx + 0.5) * CELL, floor_y[i], BOUNDS.position.y + (cz + 0.5) * CELL)


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor((p.x - BOUNDS.position.x) / CELL)), int(floor((p.z - BOUNDS.position.y) / CELL)))


## True where a line may run: the rooms, the plaza, the garden dome, the exit tunnel, and the open ground between the
## tunnel and the garden dome's airlock (the garden dome stands outside the glass hall: its tape's line goes out through
## the exit tunnel; the crew wear their suits in the tutorial). Outdoors, rocks and objects come from the dust warning's
## route grid (ReturnRoutes, which blocks the hall, the tunnel and the dome themselves: those use the collision).
func _inside_base(x: float, z: float) -> bool:
	var zone := zones.zone_at_world(Vector3(x, 0, z))
	if zone == ColonyZones.EXTERIOR:
		if x > TUNNEL_X.x and x < TUNNEL_X.y and z > TUNNEL_Z.x and z < TUNNEL_Z.y:
			return true
		if x < TUNNEL_X.x - 6.0 or z < 12.0:
			return false          # only the ground south-east of the hall, towards the garden dome
		var garden := Vector2(ColonyZones.GARDEN_CENTRE.x, -ColonyZones.GARDEN_CENTRE.y)
		if Vector2(x, z).distance_to(garden) < ColonyZones.GARDEN_RADIUS + 2.5:
			return true
		var routes := ReturnRoutes.shared()
		return routes != null and not routes.is_blocked(routes.cell_of(x, z))
	if zone == ColonyZones.PLAZA:
		# keep off the glass hall's curb and frames
		var n := float(zones.dome.n)
		var e := pow(absf((x - float(zones.dome.cx)) / float(zones.dome.rx)), n) + pow(absf((-z - float(zones.dome.cy)) / float(zones.dome.ry)), n)
		return e < 0.93
	return true


func _sample_grid() -> void:
	cols = int(BOUNDS.size.x / CELL)
	rows = int(BOUNDS.size.y / CELL)
	floor_y.resize(cols * rows)
	walk.resize(cols * rows)
	walk.fill(0)
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = Layers.WORLD
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS
	capsule.height = BODY_HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.collision_mask = Layers.WORLD
	for cz in rows:
		for cx in cols:
			var i := _idx(cx, cz)
			var x := BOUNDS.position.x + (cx + 0.5) * CELL
			var z := BOUNDS.position.y + (cz + 0.5) * CELL
			floor_y[i] = 0.0
			if not _inside_base(x, z):
				continue
			var y := _ground(ray, x, z)
			if is_nan(y):
				continue
			floor_y[i] = y
			q.transform = Transform3D(Basis(), Vector3(x, y + BODY_LIFT + BODY_HEIGHT * 0.5, z))
			if space.intersect_shape(q, 1).is_empty():
				walk[i] = 1


## Floor height at x, z (NAN when there is none). A ray that lands on the edge of a door sill or a step (a steep
## face) is tried again a few cm to each side, so thresholds stay walkable.
func _ground(ray: PhysicsRayQueryParameters3D, x: float, z: float) -> float:
	var base := _base_y(x, z)
	for o: Vector2 in [Vector2.ZERO, Vector2(0.07, 0), Vector2(-0.07, 0), Vector2(0, 0.07), Vector2(0, -0.07)]:
		ray.from = Vector3(x + o.x, base + RAY_TOP, z + o.y)
		ray.to = Vector3(x + o.x, base + RAY_BOTTOM, z + o.y)
		var hit := space.intersect_ray(ray)
		if not hit.is_empty() and (hit.normal as Vector3).y >= 0.7:
			return (hit.position as Vector3).y
	return NAN


## Distance (m) from each walkable cell to the nearest cell where the body does not fit (two-pass chamfer).
func _clearance() -> void:
	clear.resize(cols * rows)
	var big := 1e6
	for i in walk.size():
		clear[i] = big if walk[i] == 1 else 0.0
	var d1 := CELL
	var d2 := CELL * sqrt(2.0)
	for cz in rows:
		for cx in cols:
			var i := _idx(cx, cz)
			if clear[i] == 0.0:
				continue
			var v := clear[i]
			if cx > 0: v = minf(v, clear[i - 1] + d1)
			else: v = minf(v, d1)
			if cz > 0:
				v = minf(v, clear[i - cols] + d1)
				if cx > 0: v = minf(v, clear[i - cols - 1] + d2)
				if cx < cols - 1: v = minf(v, clear[i - cols + 1] + d2)
			else: v = minf(v, d1)
			clear[i] = v
	for cz in range(rows - 1, -1, -1):
		for cx in range(cols - 1, -1, -1):
			var i := _idx(cx, cz)
			if clear[i] == 0.0:
				continue
			var v := clear[i]
			if cx < cols - 1: v = minf(v, clear[i + 1] + d1)
			else: v = minf(v, d1)
			if cz < rows - 1:
				v = minf(v, clear[i + cols] + d1)
				if cx < cols - 1: v = minf(v, clear[i + cols + 1] + d2)
				if cx > 0: v = minf(v, clear[i + cols - 1] + d2)
			else: v = minf(v, d1)
			clear[i] = v


func _count_walkable() -> int:
	var n := 0
	for w in walk:
		n += w
	return n


func _nearest_walkable(p: Vector3, radius: float) -> int:
	var best := -1
	var best_d := INF
	var c := _cell_of(p)
	var r := int(ceil(radius / CELL))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cx := c.x + dx
			var cz := c.y + dz
			if cx < 0 or cz < 0 or cx >= cols or cz >= rows:
				continue
			var i := _idx(cx, cz)
			if walk[i] != 1:
				continue
			var d := Vector2(_cell_pos(i).x, _cell_pos(i).z).distance_to(Vector2(p.x, p.z))
			if d < best_d:
				best_d = d
				best = i
	return best


## The reached cell nearest to `p` (within `radius`), preferring roomy cells a little.
func _nearest_reached(p: Vector3, dist: PackedFloat32Array, radius: float) -> int:
	var best := -1
	var best_score := INF
	var c := _cell_of(p)
	var r := int(ceil(radius / CELL))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cx := c.x + dx
			var cz := c.y + dz
			if cx < 0 or cz < 0 or cx >= cols or cz >= rows:
				continue
			var i := _idx(cx, cz)
			if walk[i] != 1 or dist[i] >= INF:
				continue
			var d := Vector2(_cell_pos(i).x, _cell_pos(i).z).distance_to(Vector2(p.x, p.z))
			if d > radius:
				continue
			var score := d - minf(clear[i], 0.4) * 0.5
			if score < best_score:
				best_score = score
				best = i
	return best


## Expected floor height: 0 in the base, the outdoor ground outside (the garden dome floor sits on it).
func _base_y(x: float, z: float) -> float:
	var zone := zones.zone_at_world(Vector3(x, 0, z))
	if terrain == null or not (zone == ColonyZones.EXTERIOR or zone == ColonyZones.GARDEN):
		return 0.0
	return terrain.height_at(x, z)


func _floor_at(p: Vector3, fallback: float) -> float:
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = Layers.WORLD
	var y := _ground(ray, p.x, p.z)
	# no floor, or a low box top the line runs under: keep the height of the walk cell
	if is_nan(y) or absf(y - fallback) > STEP_M:
		y = fallback
	# The plaza deck (DomeDeck) is drawn 2 cm above the ground there.
	if zones.zone_at_world(p) == ColonyZones.PLAZA:
		y = maxf(y, DomeDeck.Y)
	return y


# ---------------------------------------------------------------- shortest-path tree

func _cost(i: int) -> float:
	var c := clear[i]
	return 1.0 + (WALL_COST * pow((CLEAR_WANT_M - c) / CLEAR_WANT_M, 2.0) if c < CLEAR_WANT_M else 0.0)


func _dijkstra(start: int) -> Dictionary:
	var dist := PackedFloat32Array()
	dist.resize(cols * rows)
	dist.fill(INF)
	var parent := PackedInt32Array()
	parent.resize(cols * rows)
	parent.fill(-1)
	var done := PackedByteArray()
	done.resize(cols * rows)
	done.fill(0)
	dist[start] = 0.0
	var heap_k: Array[float] = [0.0]
	var heap_v: Array[int] = [start]
	var steps := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(1, 1, 1), Vector3i(-1, 1, 1), Vector3i(1, -1, 1), Vector3i(-1, -1, 1)]
	while not heap_v.is_empty():
		var i := heap_v[0]
		_pop(heap_k, heap_v)
		if done[i] == 1:
			continue
		done[i] = 1
		var cx := i % cols
		var cz := i / cols
		for s: Vector3i in steps:
			var nx := cx + s.x
			var nz := cz + s.y
			if nx < 0 or nz < 0 or nx >= cols or nz >= rows:
				continue
			var j := _idx(nx, nz)
			if walk[j] != 1 or done[j] == 1 or absf(floor_y[j] - floor_y[i]) > STEP_M:
				continue
			if s.z == 1 and (walk[_idx(nx, cz)] != 1 or walk[_idx(cx, nz)] != 1):
				continue
			var len := CELL * (1.41421356 if s.z == 1 else 1.0)
			var nd := dist[i] + len * 0.5 * (_cost(i) + _cost(j))
			if nd < dist[j]:
				dist[j] = nd
				parent[j] = i
				_push(heap_k, heap_v, nd, j)
	return {"dist": dist, "parent": parent}


static func _push(k: Array[float], v: Array[int], key: float, val: int) -> void:
	k.append(key)
	v.append(val)
	var i := k.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if k[p] <= k[i]:
			break
		var tk := k[p]; k[p] = k[i]; k[i] = tk
		var tv := v[p]; v[p] = v[i]; v[i] = tv
		i = p


static func _pop(k: Array[float], v: Array[int]) -> void:
	var last := k.size() - 1
	k[0] = k[last]
	v[0] = v[last]
	k.resize(last)
	v.resize(last)
	var i := 0
	var n := last
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var m := i
		if l < n and k[l] < k[m]: m = l
		if r < n and k[r] < k[m]: m = r
		if m == i:
			break
		var tk := k[m]; k[m] = k[i]; k[i] = tk
		var tv := v[m]; v[m] = v[i]; v[i] = tv
		i = m


# ---------------------------------------------------------------- chains and string pulling

static func _set_key(ids: Array) -> String:
	var s := ids.duplicate()
	s.sort()
	return "|".join(PackedStringArray(s))


## Simplifies one run of cells once (shared by every trail on it) and returns its key. `next` is the first cell of the
## following run (the run's end point joins it), or -1.
func _store_chain(store: Dictionary, set_key: String, run: Array[int], _next: int) -> String:
	var key := "%s@%d" % [set_key, run[0]]
	if store.has(key):
		return key
	var cells := run.duplicate()
	var pts: Array[Vector3] = []
	var i := 0
	pts.append(_cell_pos(cells[0]))
	while i < cells.size() - 1:
		var min_clear: float = clear[cells[i]]
		var best := i + 1
		for j in range(i + 1, cells.size()):
			min_clear = minf(min_clear, clear[cells[j]])
			if _line_clear(_cell_pos(cells[i]), _cell_pos(cells[j]), minf(min_clear, CLEAR_WANT_M) - 0.05):
				best = j
		pts.append(_cell_pos(cells[best]))
		i = best
	store[key] = pts
	return key


func _line_clear(a: Vector3, b: Vector3, need: float) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var n := int(ceil(d.length() / (CELL * 0.4)))
	for s in range(1, n):
		var t := float(s) / float(n)
		var p := a.lerp(b, t)
		var c := _cell_of(p)
		if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
			return false
		var i := _idx(c.x, c.y)
		if walk[i] != 1 or clear[i] < need or absf(floor_y[i] - lerpf(a.y, b.y, t)) > STEP_M:
			return false
	return true


# ---------------------------------------------------------------- lanes

## Trail id -> global lane rank (0 = leftmost), from a depth-first walk of the path tree with children taken right to
## left... ordered so that a branch turning toward the lines' +normal side gets the higher ranks.
func _lane_order(raw: Dictionary, _users: Dictionary) -> Dictionary:
	var children := {}           # cell -> [child cells on some trail]
	var root := -1
	for id: String in raw:
		var cells: Array = raw[id]
		root = cells[0]
		for i in range(cells.size() - 1):
			var a: int = cells[i]
			var b: int = cells[i + 1]
			if not children.has(a):
				children[a] = []
			if not (children[a] as Array).has(b):
				(children[a] as Array).append(b)
	var ends := {}
	for id: String in raw:
		ends[(raw[id] as Array)[-1]] = id
	var ranks := {}
	var stack: Array = [[root, -1]]
	# iterative DFS; children pushed in reverse order of their side angle
	while not stack.is_empty():
		var top: Array = stack.pop_back()
		var c: int = top[0]
		var prev: int = top[1]
		if ends.has(c) and not ranks.has(ends[c]):
			ranks[ends[c]] = ranks.size()
		var kids: Array = children.get(c, [])
		if kids.is_empty():
			continue
		var here := _cell_pos(c)
		var d_in := Vector2(0, -1)
		if prev >= 0:
			d_in = Vector2(here.x - _cell_pos(prev).x, here.z - _cell_pos(prev).z).normalized()
		var scored: Array = []
		for k: int in kids:
			var ahead := _ahead(k, children, 8)
			var d := Vector2(ahead.x - here.x, ahead.z - here.z).normalized()
			var cross := d_in.x * d.y - d_in.y * d.x
			scored.append([atan2(cross, d_in.dot(d)), k])
		scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		for s: Array in scored:          # pushed largest angle first, so the smallest is visited first
			stack.append([s[1], c])
	return ranks


## A point `n` cells further down the tree from `c` (follows the first child).
func _ahead(c: int, children: Dictionary, n: int) -> Vector3:
	var cur := c
	for i in n:
		var kids: Array = children.get(cur, [])
		if kids.is_empty():
			break
		cur = kids[0]
	return _cell_pos(cur)


## The trail's centre line resampled, pushed sideways into its lane where it shares a corridor, eased in and out.
func _offset_line(id: String, centre: Array[Vector3], users: Dictionary, ranks: Dictionary) -> Array[Vector3]:
	var samples: Array[Vector3] = []
	for i in range(centre.size() - 1):
		var a := centre[i]
		var b := centre[i + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / SAMPLE)))
		for s in n:
			samples.append(a.lerp(b, float(s) / float(n)))
	samples.append(centre[-1])
	var raw_off := PackedFloat32Array()
	raw_off.resize(samples.size())
	for i in samples.size():
		var c := _cell_of(samples[i])
		var on: Array = []
		var room := CLEAR_WANT_M
		if c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows:
			var cell := _idx(c.x, c.y)
			room = clear[cell]
			on = _users_near(cell, users)
		if on.size() <= 1 or not on.has(id):
			raw_off[i] = 0.0
			continue
		var lo := 1 << 30
		for other: String in on:
			lo = mini(lo, int(ranks[other]))
		var lane := int(ranks[id]) - lo
		var k := on.size()
		var half := room + BODY_RADIUS - CELL * 0.5 - WALL_KEEP - RIBBON_HALF
		var spacing := clampf(2.0 * half / float(k - 1), LANE_MIN, LANE_MAX)
		raw_off[i] = (float(lane) - float(k - 1) * 0.5) * spacing
	# ease: moving average over EASE_M, then never more than the raw spread at the very ends
	var w := int(EASE_M / SAMPLE * 0.5)
	var off := PackedFloat32Array()
	off.resize(samples.size())
	for i in samples.size():
		var sum := 0.0
		var cnt := 0
		for j in range(maxi(0, i - w), mini(samples.size(), i + w + 1)):
			sum += raw_off[j]
			cnt += 1
		off[i] = sum / float(cnt)
	off[samples.size() - 1] = 0.0
	# the start: every line begins on a short bar across the way in (east-west, lane order west to east), then eases
	# into its own lane over START_EASE_M
	var bar := (float(ranks[id]) - float(ranks.size() - 1) * 0.5) * START_BAR
	var walked := 0.0
	var out: Array[Vector3] = []
	for i in samples.size():
		if i > 0:
			walked += samples[i - 1].distance_to(samples[i])
		var ease := smoothstep(0.0, START_EASE_M, walked)
		var a := samples[maxi(0, i - 4)]
		var b := samples[mini(samples.size() - 1, i + 4)]
		var t := Vector2(b.x - a.x, b.z - a.z)
		t = t.normalized() if t.length() > 0.001 else Vector2.ZERO
		var on_bar := samples[i] + Vector3(bar, 0, 0)
		var in_lane := samples[i] + Vector3(-t.y, 0, t.x) * off[i]
		out.append(on_bar.lerp(in_lane, ease))
	return out


## Trails passing this cell (or, when none share it exactly, a neighbouring cell of the tree).
func _users_near(cell: int, users: Dictionary) -> Array:
	if users.has(cell):
		return users[cell]
	var cx := cell % cols
	var cz := cell / cols
	var best: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var j := _idx(clampi(cx + dx, 0, cols - 1), clampi(cz + dz, 0, rows - 1))
			if users.has(j) and (users[j] as Array).size() > best.size():
				best = users[j]
	return best


## Douglas-Peucker in plan view.
func _simplify(line: Array[Vector3]) -> Array[Vector3]:
	if line.size() < 3:
		return line
	var keep := PackedByteArray()
	keep.resize(line.size())
	keep.fill(0)
	keep[0] = 1
	keep[line.size() - 1] = 1
	var stack: Array = [[0, line.size() - 1]]
	while not stack.is_empty():
		var seg: Array = stack.pop_back()
		var a: int = seg[0]
		var b: int = seg[1]
		var pa := Vector2(line[a].x, line[a].z)
		var pb := Vector2(line[b].x, line[b].z)
		var worst := -1
		var worst_d := SIMPLIFY_TOL
		for i in range(a + 1, b):
			var p := Vector2(line[i].x, line[i].z)
			var q := Geometry2D.get_closest_point_to_segment(p, pa, pb)
			var d := p.distance_to(q)
			if d > worst_d or absf(line[i].y - lerpf(line[a].y, line[b].y, float(i - a) / float(b - a))) > 0.02:
				if d > worst_d:
					worst_d = d
				worst = i
		if worst >= 0:
			keep[worst] = 1
			stack.append([a, worst])
			stack.append([worst, b])
	var out: Array[Vector3] = []
	for i in line.size():
		if keep[i] == 1:
			out.append(line[i])
	return out


# ---------------------------------------------------------------- data in and out

func _anchors() -> Dictionary:
	var out := {}
	for entry: Dictionary in StationCatalog.extra_entries():
		if String(entry.get("kind", "")) == "cassette_anchor" and entry.has("position") and CassetteCatalog.TAPES.has(String(entry.get("cassette_id", ""))):
			var q: Array = entry.position
			out[String(entry.cassette_id)] = Vector3(float(q[0]), float(q[1]), float(q[2]))
	return out


func _write(trails: Dictionary, lengths: Dictionary, start: Vector3) -> void:
	var ids: Array = trails.keys()
	ids.sort()
	var lines := PackedStringArray()
	lines.append("{")
	lines.append("\t\"note\": \"Gold tape trails (owner 2026-11-14): one walkable line per room tape from just inside the exit tunnel's inner door (door 901) to the tape's floor anchor, side by side where they share a corridor. Baked by tools/godot/bake_tape_trails.gd from the world collision; drawn by scripts/cassettes/tape_trail_presenter.gd. Points are Godot world metres, rounded to cm.\",")
	lines.append("\t\"start\": [%s, %s, %s]," % [_n(start.x), _n(start.y), _n(start.z)])
	var len_parts := PackedStringArray()
	for id: String in ids:
		len_parts.append("\"%s\": %s" % [id, _n(snappedf(float(lengths[id]), 0.1))])
	lines.append("\t\"length_m\": {%s}," % ", ".join(len_parts))
	lines.append("\t\"trails\": {")
	for k in ids.size():
		var id: String = ids[k]
		var pts := PackedStringArray()
		for p: Array in trails[id]:
			pts.append("[%s, %s, %s]" % [_n(float(p[0])), _n(float(p[1])), _n(float(p[2]))])
		lines.append("\t\t\"%s\": [%s]%s" % [id, ", ".join(pts), "," if k < ids.size() - 1 else ""])
	lines.append("\t}")
	lines.append("}")
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()


## The walk grid for the game's guide lines (owner 2026-11-15): data/walk_grid.bin, format in the header. Heights are
## the drawn floor (the plaza deck sits at DomeDeck.Y), as _floor_at gives them for the trails.
func _write_walk_grid() -> void:
	var n := cols * rows
	var heights := PackedByteArray()
	heights.resize(n * 2)
	var clear_cm := PackedByteArray()
	clear_cm.resize(n)
	for i in n:
		var h := 0.0
		var c := 0
		if walk[i] == 1:
			h = floor_y[i]
			var p := _cell_pos(i)
			if zones.zone_at_world(p) == ColonyZones.PLAZA:
				h = maxf(h, DomeDeck.Y)
			c = clampi(int(round(clear[i] * 100.0)), 0, 255)
		heights.encode_s16(i * 2, clampi(int(round(h * 100.0)), -32768, 32767))
		clear_cm[i] = c
	var data := {
		"version": WALK_VERSION,
		"origin": Vector2(BOUNDS.position.x, BOUNDS.position.y),
		"cell": CELL,
		"cols": cols,
		"rows": rows,
		"walk": walk.compress(FileAccess.COMPRESSION_ZSTD),
		"height_cm": heights.compress(FileAccess.COMPRESSION_ZSTD),
		"clear_cm": clear_cm.compress(FileAccess.COMPRESSION_ZSTD),
		"sizes": {"walk": walk.size(), "height_cm": heights.size(), "clear_cm": clear_cm.size()},
	}
	var f := FileAccess.open(WALK_OUT, FileAccess.WRITE)
	if f == null:
		push_error("bake_tape_trails: cannot write %s" % WALK_OUT)
		return
	f.store_var(data)
	var bytes := f.get_length()
	f.close()
	print("walk grid: %s, %d x %d cells of %.2f m, %d bytes" % [WALK_OUT, cols, rows, CELL, bytes])


static func _n(v: float) -> String:
	var s := "%.2f" % snappedf(v, 0.01)
	if s == "-0.00":
		s = "0.00"
	return s


func _save_png(path: String, trails: Dictionary, raw: Dictionary) -> void:
	var img := Image.create(cols, rows, false, Image.FORMAT_RGB8)
	for cz in rows:
		for cx in cols:
			var i := _idx(cx, cz)
			var x := BOUNDS.position.x + (cx + 0.5) * CELL
			var z := BOUNDS.position.y + (cz + 0.5) * CELL
			var col := Color(0.08, 0.08, 0.1)
			if _inside_base(x, z):
				col = Color(0.25, 0.12, 0.12)
			if walk[i] == 1:
				var g := clampf(clear[i] / 1.5, 0.0, 1.0)
				col = Color(0.3 + 0.4 * g, 0.3 + 0.4 * g, 0.3 + 0.4 * g)
				if reached.size() == walk.size() and reached[i] >= INF:
					col = Color(0.2, 0.25, 0.6)
			img.set_pixel(cx, cz, col)
	var palette := [Color.ORANGE, Color.YELLOW, Color.GREEN, Color.CYAN, Color.MAGENTA, Color.CORNFLOWER_BLUE]
	var ids: Array = trails.keys()
	ids.sort()
	for k in ids.size():
		var pts: Array = trails[ids[k]]
		for i in range(pts.size() - 1):
			var a := Vector2(float(pts[i][0]), float(pts[i][2]))
			var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][2]))
			var n := int(ceil(a.distance_to(b) / (CELL * 0.3)))
			for s in n + 1:
				var p := a.lerp(b, float(s) / float(maxi(n, 1)))
				var c := _cell_of(Vector3(p.x, 0, p.y))
				if c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows:
					img.set_pixel(c.x, c.y, palette[k % palette.size()])
	# a close-up of the start and the airlock / hangar fan-out
	var c0 := _cell_of(Vector3(15.0, 0, -4.0))
	var crop := img.get_region(Rect2i(c0.x, c0.y, int(16.0 / CELL), int(16.0 / CELL)))
	crop.resize(crop.get_width() * 8, crop.get_height() * 8, Image.INTERPOLATE_NEAREST)
	crop.save_png(path.get_basename() + "_start.png")
	img.resize(cols * 3, rows * 3, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
	print("debug image: %s (1 px = %.2f m before the 3x scale; x right, z down)" % [path, CELL])
