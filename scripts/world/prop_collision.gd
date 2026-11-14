class_name PropCollision
extends RefCounted
## Gives every solid visible mesh of the map that is not yet solid its own collision, so nothing rigid can be walked
## into: rovers, tanks, racks, machines, masts, plants, the glass hall's frames and curb, the garden dome shell, the
## lander, and so on. It runs once at load, after WorldCollision, EnvironmentCollision, RockCollision and SuitDisplays.
##
## Which meshes: every visible MeshInstance3D under the world, except
##  - floors and doors of the manifest (cls "floor" / "door"), door leaves moved by a DoorController, the terrain tiles,
##    the rocks and the hall pieces EnvironmentCollision already made solid;
##  - manifest objects whose collision boxes from colliders.json already fill at least COVERED_FRACTION of the part of
##    the object at body height (keeps the authored boxes of stairs, walls and furniture as they are);
##  - ground decals and sand drifts (all materials are decal / gouge / drift / terrain materials);
##  - skinned meshes (the display suits hang on racks that are solid already), cloth curtains, and stairs;
##  - anything smaller than MIN_SIZE_M or whose bottom is more than HEAD_CLEARANCE_M above the ground under it.
##
## How: a compact mesh (at most COMPACT_M across and COMPACT_HEIGHT_M tall) away from any doorway gets one convex hull
## (computed once per shared mesh). Anything bigger, anything near a doorway, or a PASSAGE_ASSETS object, gets a
## two-sided trimesh of its own triangles, so openings, arches and the space inside a dome or hall stay exactly as modelled.
## FLOOR_HULL_ASSETS (finely detailed floors) always get one hull, whatever their size.
## Every shape carries the manifest object's name as "object_name" metadata, so looking at a station's hull still
## counts as looking at the station (PlayerController.aimed_target).
##
## Cost: deciding and baking takes about 1.7 s, building the physics shapes about 1 s. GameMain therefore passes
## CACHE_PATH: the baked world-space shapes are stored there and reused while none of CACHE_INPUTS changed, which
## brings the load-time cost to about 1.1 s. Delete the file, or bump VERSION, to force a rebuild.

const HEAD_CLEARANCE_M := 2.2       # 1.8 m body plus most of a 0.5 m jump
const MIN_SIZE_M := 0.1
const FLAT_M := 0.03
const COMPACT_M := 4.5
const COMPACT_HEIGHT_M := 3.5
const COVERED_FRACTION := 0.8
## Trimeshes keep only triangles reaching below this height above the ground: above it nobody can touch them, and
## the 17 m hall frames, the 29 m lander and the dome would otherwise cost millions of triangles.
const TRIMESH_TOP_M := 3.0
const BAND_LOW_M := 0.05
const BAND_HIGH_M := 1.9
## How far around a closed door leaf a mesh counts as being in the doorway.
const DOORWAY_MARGIN_M := 0.8
## Manifest assets with a walk-through passage but no door leaf of their own, so no doorway is found for them: the
## garden dome's airlock vestibule (open 1.6 x 2.35 m doorway, shallow steps). A convex hull would fill the passage
## and seal the dome, so these always get a trimesh of their own triangles.
const PASSAGE_ASSETS: Array[String] = ["gd_airlock"]
## Floor assets drawn with millimetre detail (the garden dome floor: 1.2 mm tile seams, a 4 mm vinyl path, drain grates).
## As a trimesh a player placed exactly on a seam (a save reloaded there) is caught inside it and cannot move, so these
## always get one convex hull: a clean walking surface at most 8 mm above the drawn floor.
const FLOOR_HULL_ASSETS: Array[String] = ["gd_floor"]
const SKIP_CLS: Array[String] = ["floor", "door"]
const SKIP_PREFIXES: Array[String] = ["rock_", "Terrain_"]
const SKIP_WORDS: Array[String] = ["curtain", "stair"]
const SKIP_ANCESTORS: Array[String] = ["Terrain", "Exterior decals", "Exterior drifts"]
const DECAL_MATERIAL_PREFIXES: Array[String] = ["decal_", "sf_gouge", "sf_drift", "terrain_"]


## Where the game keeps the baked shapes between runs (inside the project, next to the other map data).
const CACHE_PATH := "res://data/prop_collision_cache.bin"
## Bump when the rules above change, so an old cache is rebuilt.
const VERSION := 3   # 2: PASSAGE_ASSETS (garden dome airlock no longer sealed by a hull); 3: FLOOR_HULL_ASSETS
## Files whose change makes the cache stale (besides this script and the manifest and colliders passed in).
const CACHE_INPUTS: Array[String] = ["res://assets/colony/colony.glb", "res://assets/colony/environment.glb",
	"res://assets/colony/terrain.glb", "res://data/terrain_height.res", "res://scripts/world/prop_collision.gd",
	"res://scripts/world/environment_collision.gd", "res://scripts/world/suit_displays.gd", "res://scripts/world/world_collision.gd",
	"res://scripts/world/door_controller.gd", "res://scenes/world/colony_world.tscn"]


## Adds a StaticBody3D "Props" under `collision`. `manifest_path`/`colliders_path` are the WorldCollision inputs;
## `height` is the outdoor ground (null: ground at y = 0). With `cache_path`, the baked shapes are read from that file
## when it matches the current inputs, and written to it otherwise. Returns counts and the build time in milliseconds.
static func build(world: Node3D, collision: Node3D, manifest_path: String, colliders_path: String, height: TerrainHeight = null, cache_path := "") -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var body := StaticBody3D.new()
	body.name = "Props"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	collision.add_child(body)
	var key := _cache_key([manifest_path, colliders_path]) if cache_path != "" else ""
	var stats := {}
	var entries: Array = []
	if key != "" and FileAccess.file_exists(cache_path):
		var f := FileAccess.open(cache_path, FileAccess.READ)
		var data: Variant = f.get_var() if f != null else null
		if data is Dictionary and (data as Dictionary).get("key", "") == key:
			entries = data.entries
			stats = (data.stats as Dictionary).duplicate()
			stats.cache = "read"
	if stats.is_empty():
		var scanned := _scan(world, collision, manifest_path, colliders_path, height)
		entries = scanned.entries
		stats = scanned.stats
		stats.cache = "off"
		if key != "":
			var f := FileAccess.open(cache_path, FileAccess.WRITE)
			if f != null:
				f.store_var({"key": key, "entries": entries, "stats": stats})
				f.close()
				stats.cache = "written"
	var to_body := body.global_transform.affine_inverse()
	var t_shapes := Time.get_ticks_usec()
	for e: Dictionary in entries:
		var cs := CollisionShape3D.new()
		cs.name = String(e.name)
		var pts: PackedVector3Array = e.points
		if not to_body.is_equal_approx(Transform3D.IDENTITY):
			pts = to_body * pts
		if e.kind == "hull":
			var convex := ConvexPolygonShape3D.new()
			convex.points = pts
			cs.shape = convex
		else:
			var concave := ConcavePolygonShape3D.new()
			concave.backface_collision = true
			concave.set_faces(pts)
			cs.shape = concave
		cs.set_meta("object_name", String(e.object_name))
		cs.set_meta("prop_collision", String(e.kind))
		body.add_child(cs)
	stats.shapes_ms = (Time.get_ticks_usec() - t_shapes) / 1000.0
	stats.ms = (Time.get_ticks_usec() - t0) / 1000.0
	return stats


## Size and modification time of every input, plus VERSION: equal keys mean the same shapes.
static func _cache_key(extra: Array) -> String:
	var parts := PackedStringArray(["v%d" % VERSION])
	for path: String in CACHE_INPUTS + extra:
		if not FileAccess.file_exists(path):
			parts.append(path + ":-")
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		parts.append("%s:%d:%d" % [path, f.get_length() if f != null else -1, FileAccess.get_modified_time(path)])
	return "|".join(parts)


## Decides which meshes need collision and bakes their shapes in world space.
## Returns {"entries": [{name, object_name, kind ("hull"/"trimesh"), points}], "stats": {...}}.
static func _scan(world: Node3D, collision: Node3D, manifest_path: String, colliders_path: String, height: TerrainHeight) -> Dictionary:
	var stats := {"hulls": 0, "trimeshes": 0, "trimesh_triangles": 0, "skipped_covered": 0, "skipped_doorway": 0, "skipped_other": 0, "scan_ms": 0.0}
	var t0 := Time.get_ticks_usec()
	var entries: Array = []
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var assets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(colliders_path))["assets"]
	var objects := {}
	for o: Dictionary in manifest.objects:
		objects[o.name] = o
		objects[String(o.name).replace(".", "_")] = o   # the glTF import turns "a.001" into "a_001"
	# solid already: names EnvironmentCollision handled, door leaves (their visuals move with the door)
	var handled := {}
	for n: String in EnvironmentCollision.SOLID:
		handled[n] = true
	handled[EnvironmentCollision.TUNNEL] = true
	# Doorway passages: the opening each closed door fills, stretched DOORWAY_MARGIN_M to both sides of the door and
	# trimmed 5 cm at the jambs. A hull reaching into one would seal the door, so such meshes get a trimesh instead.
	var doorways: Array[AABB] = []
	for door: Node in collision.find_children("*", "Node3D", true, false):
		if not (door is DoorController):
			continue
		var opening := AABB()
		var first := true
		for leaf: Node in door.get_children():
			if leaf is AnimatableBody3D:
				handled[String(leaf.name)] = true
				for cs: Node in leaf.get_children():
					if cs is CollisionShape3D and (cs as CollisionShape3D).shape is BoxShape3D:
						var size := ((cs as CollisionShape3D).shape as BoxShape3D).size
						var b := (cs as CollisionShape3D).global_transform * AABB(-size * 0.5, size)
						opening = b if first else opening.merge(b)
						first = false
		if first:
			continue
		var thin_x := opening.size.x < opening.size.z
		var grow := Vector3(DOORWAY_MARGIN_M, 0.0, -0.05) if thin_x else Vector3(-0.05, 0.0, DOORWAY_MARGIN_M)
		doorways.append(AABB(opening.position - grow, opening.size + grow * 2.0))
	var hulls := {}          # Mesh -> PackedVector3Array (mesh-local hull points)
	var faces_of := {}       # Mesh -> PackedVector3Array (mesh-local triangles)

	for node: Node in world.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.skin != null or mi.get_parent() is Skeleton3D:
			stats.skipped_other += 1
			continue
		var owner_name := _owner_object(mi, world, objects)
		if _skip_reason(mi, world, handled, objects, owner_name) != "":
			stats.skipped_other += 1
			continue
		var xf := mi.global_transform
		var aabb := xf * mi.mesh.get_aabb()
		var ground := _ground_under(aabb, height)
		if maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) < MIN_SIZE_M or aabb.position.y > ground + HEAD_CLEARANCE_M or aabb.size.y < FLAT_M:
			stats.skipped_other += 1   # tiny, overhead, or flat floor markings nobody can walk into
			continue
		if owner_name != "":
			if _box_coverage(objects[owner_name], assets, aabb, ground) >= COVERED_FRACTION:
				stats.skipped_covered += 1
				continue
			if _boxes_in_doorway(objects[owner_name], assets, doorways):
				stats.skipped_doorway += 1   # door frames and walls with an opening: their authored boxes shape the doorway
				continue
		var compact := maxf(aabb.size.x, aabb.size.z) <= COMPACT_M and aabb.size.y <= COMPACT_HEIGHT_M
		var asset := String(objects[owner_name].get("gc_asset", "")) if owner_name != "" else ""
		if asset in PASSAGE_ASSETS:
			compact = false
		elif asset in FLOOR_HULL_ASSETS:
			compact = true
		if compact and not (asset in FLOOR_HULL_ASSETS):
			for d: AABB in doorways:
				if d.intersects(aabb):
					compact = false
					break
		var points: PackedVector3Array
		if compact:
			var local: PackedVector3Array = hulls.get(mi.mesh, PackedVector3Array())
			if local.is_empty():
				var hull := mi.mesh.create_convex_shape(true, false) as ConvexPolygonShape3D
				if hull == null or hull.points.size() < 4:
					stats.skipped_other += 1
					continue
				local = hull.points
				hulls[mi.mesh] = local
			points = xf * local
			stats.hulls += 1
		else:
			var faces: PackedVector3Array = faces_of.get(mi.mesh, PackedVector3Array())
			if faces.is_empty():
				faces = mi.mesh.get_faces()
				faces_of[mi.mesh] = faces
			points = xf * faces
			if aabb.end.y > ground + TRIMESH_TOP_M:
				points = _below(points, ground + TRIMESH_TOP_M)
			if points.is_empty():
				stats.skipped_other += 1
				continue
			stats.trimeshes += 1
			stats.trimesh_triangles += points.size() / 3
		entries.append({"name": String(mi.name), "object_name": owner_name if owner_name != "" else String(mi.name),
			"kind": "hull" if compact else "trimesh", "points": points})
	stats.scan_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return {"entries": entries, "stats": stats}


## True if one of the object's authored collision boxes reaches into a doorway passage.
static func _boxes_in_doorway(object: Dictionary, assets: Dictionary, doorways: Array[AABB]) -> bool:
	var boxes: Array = assets.get(object.gc_asset, {}).get("cols", [])
	if boxes.is_empty():
		return false
	var pose := WorldCollision.object_transform(object.matrix_world)
	for box: Dictionary in boxes:
		var q: Array = box.q
		var local := Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3]).normalized()), Vector3(box.c[0], box.c[1], box.c[2]))
		var h := Vector3(box.h[0], box.h[1], box.h[2])
		var world_box := (pose * local) * AABB(-h, h * 2.0)
		for d: AABB in doorways:
			if d.intersects(world_box):
				return true
	return false


## Triangles of `faces` with at least one corner below `top_y`.
static func _below(faces: PackedVector3Array, top_y: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(faces.size())
	var n := 0
	for i in range(0, faces.size(), 3):
		if faces[i].y < top_y or faces[i + 1].y < top_y or faces[i + 2].y < top_y:
			out[n] = faces[i]
			out[n + 1] = faces[i + 1]
			out[n + 2] = faces[i + 2]
			n += 3
	out.resize(n)
	return out


## Name of the manifest object this mesh belongs to (itself or the nearest ancestor), or "".
static func _owner_object(mi: Node, world: Node, objects: Dictionary) -> String:
	var n := mi
	while n != null and n != world:
		if objects.has(String(n.name)):
			return String(objects[String(n.name)].name)
		n = n.get_parent()
	return ""


static func _skip_reason(mi: MeshInstance3D, world: Node, handled: Dictionary, objects: Dictionary, owner_name: String) -> String:
	if owner_name != "" and String(objects[owner_name].cls) in SKIP_CLS:
		return "class"
	var n: Node = mi
	while n != null and n != world:
		var nm := String(n.name)
		if handled.has(nm):
			return "handled"
		if nm in SKIP_ANCESTORS:
			return "ancestor"
		for p: String in SKIP_PREFIXES:
			if nm.begins_with(p):
				return "prefix"
		var lower := nm.to_lower()
		for w: String in SKIP_WORDS:
			if w in lower:
				return "word"
		n = n.get_parent()
	var decal := mi.mesh.get_surface_count() > 0
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s)
		var mat_name := m.resource_path.get_file().get_basename() if m != null else ""
		var is_decal := false
		for p: String in DECAL_MATERIAL_PREFIXES:
			if mat_name.begins_with(p):
				is_decal = true
				break
		if not is_decal:
			decal = false
			break
	return "decal" if decal else ""


## Lowest ground height under the centre and corners of the box.
static func _ground_under(aabb: AABB, height: TerrainHeight) -> float:
	if height == null:
		return 0.0
	var lo := INF
	var c := aabb.get_center()
	for p: Vector2 in [Vector2(c.x, c.z), Vector2(aabb.position.x, aabb.position.z), Vector2(aabb.end.x, aabb.position.z),
			Vector2(aabb.position.x, aabb.end.z), Vector2(aabb.end.x, aabb.end.z)]:
		lo = minf(lo, height.height_at(p.x, p.y))
	return lo


## Fraction of the object's body-height band (its visual box clipped to BAND_LOW..BAND_HIGH above the ground) that
## its authored collision boxes fill. Overlapping boxes may count twice; the result is capped at 1.
static func _box_coverage(object: Dictionary, assets: Dictionary, vis: AABB, ground: float) -> float:
	var boxes: Array = assets.get(object.gc_asset, {}).get("cols", [])
	if boxes.is_empty():
		return 0.0
	var lo := maxf(vis.position.y, ground + BAND_LOW_M)
	var hi := minf(vis.end.y, ground + BAND_HIGH_M)
	if hi <= lo:
		return 1.0
	var band := AABB(Vector3(vis.position.x, lo, vis.position.z), Vector3(vis.size.x, hi - lo, vis.size.z))
	var vol := maxf(band.get_volume(), 1e-6)
	var pose := WorldCollision.object_transform(object.matrix_world)
	var filled := 0.0
	for box: Dictionary in boxes:
		var q: Array = box.q
		var local := Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3]).normalized()), Vector3(box.c[0], box.c[1], box.c[2]))
		var h := Vector3(box.h[0], box.h[1], box.h[2])
		var world_box := (pose * local) * AABB(-h, h * 2.0)
		filled += band.intersection(world_box).get_volume()
	return minf(filled / vol, 1.0)
