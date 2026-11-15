extends RefCounted
## Camera rail shared by the new-game intro and the "base operational" tour (2026-11-14, owner whiteboard; Prompt Pack
## V01-V07). Pure path maths and safety checks; it creates no nodes, so tests can check every authored path headless.
##
## Paths are data (res://data/cinematics.json). A sequence is a list of segments; a segment is one continuous camera
## move (a cut separates segments):
##   {"id", "seconds", "keys": [{"t", "pos": [x, y, z], "look": [x, y, z]}...] (Godot world metres),
##    "inside": [zone names the camera must stay in], "wake": [zones to draw], "focus": [x, y, z] (must be in clear
##    view from "focus_from" seconds on, default the last 40 % of the shot),
##    "caption" or "captions": [{"t", "until", "speaker", "text"}], "fov"}
## The camera position and the point it looks at both follow a Catmull-Rom curve through the keys; time is eased in and
## out over the whole segment so every shot starts and ends gently.

const DATA_PATH := "res://data/cinematics.json"
## Design balance: the camera is treated as a ball this big when the path is checked against collision.
const DEFAULT_RADIUS_M := 0.3
## Design balance: samples per second of path checked (a 6 s shot is 180 sphere casts).
const DEFAULT_SAMPLE_HZ := 30.0
## The camera stays this far below a room's ceiling and above its floor (metres, design balance).
const CEILING_CLEAR_M := 0.35
const FLOOR_CLEAR_M := 0.5
## The camera stays this far inside the walls of the zone it is in (metres, design balance; thicker than the ball,
## because a wall's drawn mesh is thicker than its collider).
const WALL_CLEAR_M := 0.45
## The garden dome's glass shell is a sphere around its pad (ColonyZones.GARDEN_CENTRE, radius 11 m).
const GARDEN_SHELL_CLEAR_M := 1.2

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
		_data = parsed if parsed is Dictionary else {}
		if _data.is_empty():
			push_warning("Cinematics could not be read from %s." % DATA_PATH)
	return _data


static func reload() -> void:
	_data = {}


## The sequence named `id` ("intro" or "tour"), or {}.
static func sequence(id: String) -> Dictionary:
	var v: Variant = data().get(id, {})
	return v if v is Dictionary else {}


static func segments(seq: Dictionary) -> Array:
	return seq.get("segments", []) as Array


static func radius() -> float:
	return float((data().get("camera", {}) as Dictionary).get("radius_m", DEFAULT_RADIUS_M))


static func sample_hz() -> float:
	return float((data().get("camera", {}) as Dictionary).get("sample_hz", DEFAULT_SAMPLE_HZ))


static func seg_seconds(seg: Dictionary) -> float:
	var keys := seg.get("keys", []) as Array
	return float(seg.get("seconds", float((keys.back() as Dictionary).get("t", 0.0)) if not keys.is_empty() else 0.0))


## Total length of a sequence, end card included.
static func seq_seconds(seq: Dictionary) -> float:
	var total := 0.0
	for seg: Dictionary in segments(seq):
		total += seg_seconds(seg)
	return total + float((seq.get("end_card", {}) as Dictionary).get("seconds", 0.0))


static func v3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


## Gentle ease in and out (cosine), 0..1 -> 0..1.
static func ease_io(x: float) -> float:
	return 0.5 - 0.5 * cos(PI * clampf(x, 0.0, 1.0))


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (p2 - p0) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * u3)


## Position and look-at point of a segment at time t (seconds from its start): [pos, look].
static func sample(seg: Dictionary, t: float) -> Array[Vector3]:
	var keys := seg.get("keys", []) as Array
	if keys.is_empty():
		return [Vector3.ZERO, Vector3.FORWARD]
	if keys.size() == 1:
		return [v3(keys[0].pos), v3(keys[0].look)]
	var total := seg_seconds(seg)
	var tw := ease_io(t / maxf(total, 1e-4)) * float((keys.back() as Dictionary).t)
	var i := 0
	while i < keys.size() - 2 and tw > float(keys[i + 1].t):
		i += 1
	var t0 := float(keys[i].t)
	var t1 := float(keys[i + 1].t)
	var u := clampf((tw - t0) / maxf(t1 - t0, 1e-4), 0.0, 1.0)
	var a := keys[maxi(i - 1, 0)] as Dictionary
	var b := keys[i] as Dictionary
	var c := keys[i + 1] as Dictionary
	var d := keys[mini(i + 2, keys.size() - 1)] as Dictionary
	return [_catmull(v3(a.pos), v3(b.pos), v3(c.pos), v3(d.pos), u), _catmull(v3(a.look), v3(b.look), v3(c.look), v3(d.look), u)]


## Camera transform of a segment at time t. `still` (reduced motion) holds the segment's last key.
static func pose(seg: Dictionary, t: float, still := false) -> Transform3D:
	var s := sample(seg, seg_seconds(seg) if still else t)
	var pos: Vector3 = s[0]
	var look: Vector3 = s[1]
	if pos.distance_to(look) < 0.01:
		look = pos + Vector3.FORWARD
	return Transform3D(Basis.IDENTITY, pos).looking_at(look, Vector3.UP)


## Evenly spaced points along a segment (both ends included).
static func sample_points(seg: Dictionary, hz := -1.0) -> Array[Vector3]:
	var rate := sample_hz() if hz <= 0.0 else hz
	var total := seg_seconds(seg)
	var n := maxi(2, ceili(total * rate) + 1)
	var out: Array[Vector3] = []
	for k in n:
		out.append(sample(seg, total * float(k) / float(n - 1))[0])
	return out


## Every zone the camera passes through or looks at (ColonyZones names).
static func zones_on_path(seg: Dictionary, zones: ColonyZones) -> PackedStringArray:
	var out := PackedStringArray()
	var total := seg_seconds(seg)
	var n := maxi(2, ceili(total * sample_hz()) + 1)
	for k in n:
		var s := sample(seg, total * float(k) / float(n - 1))
		for p: Vector3 in s:
			var z := zones.zone_at_world(p)
			if not out.has(z):
				out.append(z)
	return out


## Zones a segment needs drawn: its "wake" list, its "inside" list and every zone on its path.
static func wake_zones(seg: Dictionary, zones: ColonyZones) -> PackedStringArray:
	var out := PackedStringArray()
	for list: Variant in [seg.get("wake", []), seg.get("inside", [])]:
		for z: Variant in list:
			if not out.has(String(z)):
				out.append(String(z))
	for z in zones_on_path(seg, zones):
		if not out.has(z):
			out.append(z)
	return out


## Problems with a segment's path, checked against the real collision of the running world: [] means safe.
## - the camera ball (radius()) never touches world collision or a door leaf (sphere casts between samples),
## - it stays in its "inside" zones, WALL_CLEAR_M inside their walls, under the ceiling and over the floor,
## - outdoors it stays clear of the garden dome's glass shell,
## - the shot's focus point is never hidden behind collision.
static func check_segment(seg: Dictionary, space: PhysicsDirectSpaceState3D, zones: ColonyZones, mask := Layers.WORLD | Layers.DOOR) -> PackedStringArray:
	var problems := PackedStringArray()
	var id := String(seg.get("id", "?"))
	var pts := sample_points(seg)
	var ball := SphereShape3D.new()
	ball.radius = radius()
	var inside: Array = seg.get("inside", [])
	var rooms := {}
	for r: Dictionary in zones.rooms:
		rooms[String(r.name)] = r
	var focus: Variant = seg.get("focus", null)
	# the focus must be in clear view once the shot has settled on it ("focus_from" seconds, default: the last 40 %)
	var total := seg_seconds(seg)
	var focus_from := float(seg.get("focus_from", total * 0.6))
	for k in pts.size():
		var t_k := total * float(k) / float(maxi(pts.size() - 1, 1))
		var p := pts[k]
		if space != null:
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = ball
			q.collision_mask = mask
			q.transform = Transform3D(Basis.IDENTITY, p)
			var hits := space.intersect_shape(q, 4)
			if not hits.is_empty():
				problems.append("%s: camera at %s is inside %s" % [id, _fmt(p), (hits[0].collider as Node).name if hits[0].collider is Node else "collision"])
			elif k + 1 < pts.size():
				q.motion = pts[k + 1] - p
				var frac := space.cast_motion(q)
				if frac.size() == 2 and frac[0] < 1.0:
					problems.append("%s: camera hits collision between %s and %s" % [id, _fmt(p), _fmt(pts[k + 1])])
			if focus != null and t_k >= focus_from - 1e-4:
				var f := v3(focus)
				var ray := PhysicsRayQueryParameters3D.create(p, f, mask)
				var hit := space.intersect_ray(ray)
				if not hit.is_empty() and (hit.position as Vector3).distance_to(f) > 0.6:
					problems.append("%s: the focus %s is hidden from %s by %s" % [id, _fmt(f), _fmt(p), (hit.collider as Node).name if hit.collider is Node else "collision"])
		var zone := zones.zone_at_world(p)
		if not inside.is_empty() and not inside.has(zone):
			problems.append("%s: camera at %s leaves its zones %s (in %s)" % [id, _fmt(p), str(inside), zone])
		if rooms.has(zone):
			var r: Dictionary = rooms[zone]
			var bx := p.x
			var by := -p.z
			var margin := minf(minf(bx - float(r.x0), float(r.x1) - bx), minf(by - float(r.y0), float(r.y1) - by))
			if margin < WALL_CLEAR_M:
				problems.append("%s: camera at %s is %.2f m from the walls of %s" % [id, _fmt(p), margin, zone])
			if p.y > float(r.get("ceiling", 3.0)) - CEILING_CLEAR_M or p.y < FLOOR_CLEAR_M:
				problems.append("%s: camera at %s is too near the floor or ceiling of %s" % [id, _fmt(p), zone])
		var g := Vector3(ColonyZones.GARDEN_CENTRE.x, 0.0, -ColonyZones.GARDEN_CENTRE.y)
		var dist := (p - g).length()
		if absf(dist - ColonyZones.GARDEN_RADIUS) < GARDEN_SHELL_CLEAR_M:
			problems.append("%s: camera at %s is too near the garden dome's glass (%.2f m from its centre)" % [id, _fmt(p), dist])
		if zone == ColonyZones.PLAZA and zones.in_dome(p.x, -p.z) and not inside.has(ColonyZones.PLAZA):
			problems.append("%s: camera at %s is under the glass hall" % [id, _fmt(p)])
	return problems


static func _fmt(p: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]
