extends RefCounted
## Walkable paths at run time for the gold sparkle guide lines (owner 2026-11-15: "In the first week of the game, add
## glowing sparkles to guide the player across different areas during the tutorial round"). Owner's constant rule:
## gold + sparkles always mean "this works / go this way".
## Loads the walk grid baked by tools/godot/bake_tape_trails.gd (data/walk_grid.bin: 0.2 m cells inside the base, the
## exit tunnel and the ground out to the garden dome; a cell is free when a standing body fits there; doors count as
## open) once, puts it in an AStarGrid2D (8 neighbours, no corner cutting, extra cost close to walls like the bake) and
## answers path(from, to): a few straight runs on the floor, string-pulled like the bake tool, lifted LIFT above the
## drawn floor. Ends are snapped to the nearest free cell (within SNAP_RADIUS_M); no path = an empty array.
## Used by scripts/guide/guide_sparkles.gd; the later H key reuses the same shared instance. Loaded by path (no
## class_name): `const WalkPaths := preload("res://scripts/guide/walk_paths.gd")`, then `WalkPaths.shared()`.

const GRID_PATH := "res://data/walk_grid.bin"
const SELF_PATH := "res://scripts/guide/walk_paths.gd"
const VERSION := 1
## Height of the returned points above the drawn floor, metres.
const LIFT := 0.08
## How far an end may be snapped onto the grid, metres.
const SNAP_RADIUS_M := 4.0
## Clearance wanted around the lines and the extra cost close to walls (the same as the bake tool).
const CLEAR_WANT_M := 0.7
const WALL_COST := 5.0
## Highest floor step a straight run may cross, metres (the bake tool's STEP_M).
const STEP_M := 0.22
## Longest straight run the string pull tries, in cells (keeps it cheap).
const PULL_MAX_CELLS := 60

static var _shared: RefCounted

## True once the grid is loaded.
var ok := false
## World x, z of cell (0, 0)'s corner, cell size (m) and grid size.
var origin := Vector2.ZERO
var cell := 0.2
var cols := 0
var rows := 0
## 1 = free, per cell (index cz * cols + cx).
var walk := PackedByteArray()
## Drawn floor height per cell, cm, signed 16-bit.
var height_cm := PackedByteArray()
## Clearance to the nearest blocked cell per cell, cm (capped at 255).
var clear_cm := PackedByteArray()
var astar: AStarGrid2D


## The one shared, loaded instance (made on first use; `ok` is false when the grid file is missing).
static func shared() -> RefCounted:
	if _shared == null:
		_shared = (load(SELF_PATH) as GDScript).new()
		_shared.call(&"load_grid")
	return _shared


## Reads the baked grid and builds the A* grid. Returns `ok`.
func load_grid(path := GRID_PATH) -> bool:
	ok = false
	if not FileAccess.file_exists(path):
		push_warning("WalkPaths: no %s (run tools/godot/bake_tape_trails.gd)" % path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	var data: Variant = f.get_var() if f != null else null
	if not data is Dictionary:
		push_warning("WalkPaths: %s is not a walk grid" % path)
		return false
	var d: Dictionary = data
	if int(d.get("version", 0)) != VERSION:
		push_warning("WalkPaths: %s has version %s, want %d (bake it again)" % [path, d.get("version"), VERSION])
		return false
	var o: Variant = d.get("origin")
	if o is Vector2:
		origin = o
	cell = float(d.get("cell", 0.2))
	cols = int(d.get("cols", 0))
	rows = int(d.get("rows", 0))
	var n := cols * rows
	var sizes: Dictionary = d.get("sizes", {}) as Dictionary
	walk = _unpack(d, sizes, "walk")
	height_cm = _unpack(d, sizes, "height_cm")
	clear_cm = _unpack(d, sizes, "clear_cm")
	if n <= 0 or cell <= 0.0 or walk.size() != n or height_cm.size() != n * 2 or clear_cm.size() != n:
		push_warning("WalkPaths: %s does not match its own size" % path)
		return false
	_build_astar()
	ok = true
	return true


static func _unpack(d: Dictionary, sizes: Dictionary, key: String) -> PackedByteArray:
	var packed: Variant = d.get(key)
	if not packed is PackedByteArray:
		return PackedByteArray()
	return (packed as PackedByteArray).decompress(int(sizes.get(key, 0)), FileAccess.COMPRESSION_ZSTD)


func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, cols, rows)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.jumping_enabled = false
	astar.update()
	for cz in rows:
		var run := -1
		for cx in cols + 1:
			var free := cx < cols and walk[cz * cols + cx] == 1
			if not free and cx < cols:
				if run < 0:
					run = cx
				continue
			if run >= 0:
				astar.fill_solid_region(Rect2i(run, cz, cx - run, 1), true)
				run = -1
			if free:
				var c := float(clear_cm[cz * cols + cx]) * 0.01
				if c < CLEAR_WANT_M:
					astar.set_point_weight_scale(Vector2i(cx, cz), 1.0 + WALL_COST * pow((CLEAR_WANT_M - c) / CLEAR_WANT_M, 2.0))


# ---------------------------------------------------------------- cells

func in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - origin.x) / cell), floori((p.z - origin.y) / cell))


func is_free(c: Vector2i) -> bool:
	return in_grid(c) and walk[c.y * cols + c.x] == 1


## Drawn floor height of a cell, metres.
func floor_height(c: Vector2i) -> float:
	return float(height_cm.decode_s16((c.y * cols + c.x) * 2)) * 0.01


func clearance(c: Vector2i) -> float:
	return float(clear_cm[c.y * cols + c.x]) * 0.01


## The cell's centre on the drawn floor.
func _point(c: Vector2i) -> Vector3:
	return Vector3(origin.x + (float(c.x) + 0.5) * cell, floor_height(c), origin.y + (float(c.y) + 0.5) * cell)


## True when `p` stands on a free cell.
func is_walkable(p: Vector3) -> bool:
	return ok and is_free(cell_of(p))


## The free cell nearest to `p` (in plan) within SNAP_RADIUS_M, or (-1, -1). Searches rings outward and stops after
## the first ring that has one (plus one more ring, since a corner of ring k can be farther than ring k + 1).
func nearest_free(p: Vector3) -> Vector2i:
	if not ok:
		return Vector2i(-1, -1)
	var c := cell_of(p)
	if is_free(c):
		return c
	var best := Vector2i(-1, -1)
	var best_d := INF
	var stop_at := -1
	var r_max := int(ceil(SNAP_RADIUS_M / cell))
	var q := Vector2(p.x, p.z)
	for r in range(1, r_max + 1):
		if stop_at >= 0 and r > stop_at:
			break
		for dz in range(-r, r + 1):
			var step := 1 if absi(dz) == r else 2 * r
			var dx := -r
			while dx <= r:
				var k := Vector2i(c.x + dx, c.y + dz)
				if is_free(k):
					var w := _point(k)
					var dist := Vector2(w.x, w.z).distance_to(q)
					if dist < best_d:
						best_d = dist
						best = k
				dx += step
		if best.x >= 0 and stop_at < 0:
			stop_at = r + 1
	return best


# ---------------------------------------------------------------- paths

## A walkable line from `from` to `to`: straight runs on the floor (corners only where the way turns), each point
## LIFT above the drawn floor. Empty when either end is off the grid or there is no way at all; when the goal can not
## be reached the line goes as close as the grid allows.
func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var ids := _cells(from, to)
	if ids.size() < 2:
		return out
	for c: Vector2i in _pull(ids):
		out.append(_point(c) + Vector3(0.0, LIFT, 0.0))
	return out


## Length of the walk from `from` to `to` along the grid (before string pulling), metres; INF when there is none.
func walk_length(from: Vector3, to: Vector3) -> float:
	var ids := _cells(from, to)
	if ids.is_empty():
		return INF
	var total := 0.0
	for i in range(1, ids.size()):
		total += Vector2(ids[i - 1]).distance_to(Vector2(ids[i])) * cell
	return total


func _cells(from: Vector3, to: Vector3) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	if not ok:
		return none
	var a := nearest_free(from)
	var b := nearest_free(to)
	if a.x < 0 or b.x < 0:
		return none
	if a == b:
		var one: Array[Vector2i] = [a]
		return one
	return astar.get_id_path(a, b, true)


## String pulling (as the bake tool does it): from each kept cell, the farthest later cell along the path that a
## straight run reaches while keeping the clearance the path itself had there (or CLEAR_WANT_M), without crossing a
## step higher than STEP_M. Stops looking at the first run that fails, and at PULL_MAX_CELLS.
func _pull(ids: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = [ids[0]]
	var n := ids.size()
	var i := 0
	while i < n - 1:
		var best := i + 1
		var min_clear := clearance(ids[i])
		var last := mini(n - 1, i + PULL_MAX_CELLS)
		for j in range(i + 1, last + 1):
			min_clear = minf(min_clear, clearance(ids[j]))
			if j == i + 1:
				continue
			if _line_clear(ids[i], ids[j], minf(min_clear, CLEAR_WANT_M) - 0.05):
				best = j
			else:
				break
		out.append(ids[best])
		i = best
	return out


## True when the straight run between two cells stays on free cells with at least `need` m clearance and no step
## higher than STEP_M from the straight height line.
func _line_clear(a: Vector2i, b: Vector2i, need: float) -> bool:
	var pa := Vector2(a)
	var pb := Vector2(b)
	var ha := floor_height(a)
	var hb := floor_height(b)
	var steps := int(ceil(pa.distance_to(pb) / 0.4))
	for s in range(1, steps):
		var t := float(s) / float(steps)
		var q := pa.lerp(pb, t)
		var c := Vector2i(floori(q.x + 0.5), floori(q.y + 0.5))
		if not is_free(c) or clearance(c) < need or absf(floor_height(c) - lerpf(ha, hb, t)) > STEP_M:
			return false
	return true
