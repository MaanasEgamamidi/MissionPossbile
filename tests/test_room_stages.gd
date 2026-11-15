extends SceneTree
## Room upgrade looks (worker 4, 2026-11-14): energy (Power Room + sun trackers), life_support, health (Med Bay) and
## command (Command Room + roof). Headless, no rendering: every stage records the world box of each part it builds
## (RoomParts meta "parts"), and those boxes are checked against the map's own collision boxes (WorldCollision),
## the room rectangles and ceilings, the doors, the stations' standing spots and the respawn spot.
##
## Run:  godot --headless --path . --script res://tests/test_room_stages.gd [-- --dump]
## --dump writes every stage's triangles, keep-out discs and door boxes to
## _test_saves/test_room_stages/parts.json for tools/blender/room_stages/render_rooms.py (the check images).

const TRACKS := {
	"energy": "Power Room",
	"life_support": "Life Support",
	"health": "Med Bay",
	"command": "Command Room",
}
const STAND_OUT := 0.85        # a player stands this far in front of a station object
const STAND_R := 0.9           # nothing below head height within this radius of a standing spot
const SPAWN_R := 1.0           # ... or of the respawn spot
const HEAD := 1.8              # parts higher than this never block a standing player (PlayerTuning.body_height_m)
const DOOR_SIDE := 0.15        # door keep-out: the opening plus this on each side
const DOOR_DEPTH := 1.4        # ... and this far into each room
const DOOR_HEAD := 2.3
const CLIP_TOL := 0.012        # parts may touch the map's collision boxes by this much
const DUMP_DIR := "res://_test_saves/test_room_stages"
const ROOF_TOP := 3.17         # top of the roof slabs over the Command Room

var _passed := 0
var _total := 0
var _zones: ColonyZones
var _stations: Dictionary
var _manifest: Dictionary
var _obstacles: Array = []     # {name, xf: Transform3D, half: Vector3, aabb: AABB}
var _doors: Array = []         # {id, room_a, aabb (plan keep-out as world AABB)}
var _discs: Array = []         # {id, p: Vector3 (world), r}
var _dump := {"levels": {}, "keepout_discs": [], "keepout_boxes": []}
var _RoomParts: Script


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, okay: bool) -> void:
	_total += 1
	if okay:
		_passed += 1
	print(("PASS " if okay else "FAIL ") + label)


func _run() -> void:
	_RoomParts = load("res://scripts/upgrades/stages/room_parts.gd") as Script
	_manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/colony_manifest.json"))
	_zones = ColonyZones.from_manifest("res://data/colony_manifest.json")
	_stations = StationCatalog.from_manifest("res://data/colony_manifest.json", _zones)
	_collect_obstacles()
	_collect_doors()
	_collect_discs()
	_check("the map gives obstacles, doors and standing spots in the four rooms", _obstacles.size() > 200 and _doors.size() >= 8 and _discs.size() >= 15)
	# the headless renderer still parses shaders: a shader that fails to compile lists no uniforms
	var compiled := true
	for key in ["screen:0", "holo:1"]:
		var m: ShaderMaterial = _RoomParts.screen_material(key)
		var names: Array = m.shader.get_shader_uniform_list().map(func(d: Dictionary) -> String: return String(d.name))
		compiled = compiled and names.has("mode") and names.has("tint") and names.has("energy")
	_check("the screen and hologram shaders compile", compiled)
	var services := GameServices.new()
	var world := Node3D.new()
	world.name = "World"
	get_root().add_child(world)
	for track: String in TRACKS:
		await _track(track, world, services)
	await _swaps(world, services)
	if OS.get_cmdline_user_args().has("--dump"):
		_write_dump()
	world.free()
	services.free()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


# ---------------------------------------------------------------- map data

func _collect_obstacles() -> void:
	var col := WorldCollision.build("res://data/colony_manifest.json", "res://data/colliders.json")
	for body in col.get_node("Static").get_children():
		for shape in body.get_children():
			_add_obstacle(shape as CollisionShape3D, Transform3D.IDENTITY)
	for door in col.get_node("Doors").get_children():
		for leaf in door.get_children():
			if leaf is AnimatableBody3D:
				for shape in leaf.get_children():
					if shape is CollisionShape3D:
						_add_obstacle(shape as CollisionShape3D, (leaf as Node3D).transform)
	col.free()


func _add_obstacle(shape: CollisionShape3D, parent: Transform3D) -> void:
	if shape == null or not (shape.shape is BoxShape3D):
		return
	var xf := parent * shape.transform
	var half := (shape.shape as BoxShape3D).size * 0.5
	var bb := _obb_aabb(xf, half)
	# only what is near the four rooms, the trackers and the command roof
	var near := false
	for room_name: String in TRACKS.values():
		var r: Dictionary = _RoomParts.room(room_name)
		var area := AABB(Vector3(float(r.x0) - 1.0, -1.0, -float(r.y1) - 1.0), Vector3(float(r.x1) - float(r.x0) + 2.0, 6.0, float(r.y1) - float(r.y0) + 2.0))
		if area.intersects(bb):
			near = true
	if absf(bb.get_center().x) > 15.0 and absf(bb.get_center().x) < 65.0 and absf(bb.get_center().z) < 22.0 and bb.position.y < 4.0:
		near = true
	if near:
		_obstacles.append({"name": String(shape.get_meta("object_name", shape.name)), "xf": xf, "half": half, "aabb": bb})


static func _obb_aabb(xf: Transform3D, half: Vector3) -> AABB:
	var bb := AABB(xf.origin, Vector3.ZERO)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				bb = bb.expand(xf * Vector3(half.x * sx, half.y * sy, half.z * sz))
	return bb


## Keep-out box of every door of the four rooms: the opening (both leaves) plus DOOR_SIDE, DOOR_DEPTH into each side.
func _collect_doors() -> void:
	var leaves: Dictionary = {}
	for o: Dictionary in _manifest.objects:
		if String(o.cls) == "door" and o.has("door_id"):
			var id := int(o.door_id)
			if not leaves.has(id):
				leaves[id] = []
			(leaves[id] as Array).append(WorldCollision.object_transform(o.matrix_world).origin)
	for id: int in leaves:
		var pts: Array = leaves[id]
		var c := Vector3.ZERO
		for p: Vector3 in pts:
			c += p
		c /= float(pts.size())
		var in_room := ""
		for room_name: String in TRACKS.values():
			var r: Dictionary = _RoomParts.room(room_name)
			if c.x > float(r.x0) - 0.3 and c.x < float(r.x1) + 0.3 and -c.z > float(r.y0) - 0.3 and -c.z < float(r.y1) + 0.3:
				in_room = room_name
		if in_room == "":
			continue
		var along := Vector3.RIGHT
		var half_w := 0.5
		if pts.size() >= 2:
			var d: Vector3 = (pts[1] as Vector3) - (pts[0] as Vector3)
			d.y = 0.0
			along = d.normalized()
			half_w = d.length() * 0.5 + 0.25
		half_w += DOOR_SIDE
		var across := Vector3(-along.z, 0.0, along.x)
		var bb := AABB(c, Vector3.ZERO)
		for p: Vector3 in [c + along * half_w + across * DOOR_DEPTH, c - along * half_w + across * DOOR_DEPTH, c + along * half_w - across * DOOR_DEPTH, c - along * half_w - across * DOOR_DEPTH]:
			bb = bb.expand(p)
		bb.position.y = 0.0
		bb.size.y = DOOR_HEAD
		_doors.append({"id": id, "room": in_room, "aabb": bb})
		_dump.keepout_boxes.append({"id": str(id), "min": [bb.position.x, 0.0, bb.position.z], "max": [bb.end.x, DOOR_HEAD, bb.end.z]})


## Standing spots: in front of every station object (its local -y in Blender), on every marker-only station, and the
## respawn spot.
func _collect_discs() -> void:
	var poses: Dictionary = {}
	for o: Dictionary in _manifest.objects:
		poses[String(o.name)] = WorldCollision.object_transform(o.matrix_world)
	for id: String in _stations:
		var st: Dictionary = _stations[id]
		var p := Vector3(float(st.position[0]), float(st.position[1]), float(st.position[2]))
		var room := _zones.zone_at_world(p)
		var near_trackers := false
		if room == ColonyZones.EXTERIOR and String(st.kind) != "solar":
			for n: String in _RoomParts.objects_named("sf_solar_tracker"):
				if ((poses[n] as Transform3D).origin - p).length() < 8.0:
					near_trackers = true
		if not TRACKS.values().has(room) and not near_trackers:
			continue
		if poses.has(id) and ((poses[id] as Transform3D).origin - p).length() < 0.05:
			var xf: Transform3D = poses[id]
			var front := xf.basis * Vector3(0, 0, 1)
			front.y = 0.0
			front = front.normalized()
			_add_disc(id, xf.origin + front * STAND_OUT, STAND_R)
		else:
			_add_disc(id, p, STAND_R)
	_add_disc("respawn", GameConfig.new().hub_position, SPAWN_R)


func _add_disc(id: String, p: Vector3, r: float) -> void:
	_discs.append({"id": id, "p": p, "r": r})
	_dump.keepout_discs.append({"id": id, "x": p.x, "z": p.z, "r": r})


# ---------------------------------------------------------------- one track

func _track(track: String, world: Node3D, services: GameServices) -> void:
	var room_name: String = TRACKS[track]
	var room: Dictionary = _RoomParts.room(room_name)
	var script := load("res://scripts/upgrades/stages/%s_stages.gd" % track) as Script
	var p := script.new() as AreaStagePresenter
	world.add_child(p)
	p.setup(world, services, null)
	_check("%s: presenter names its track" % track, p.track_id() == track)
	var prev_tags := 0
	for lvl in range(1, AreaLevels.max_level() + 1):
		p.force_level = lvl
		p.refresh()
		await process_frame
		var stage := p.stage_node()
		var label := "%s V%d" % [track, lvl]
		if lvl == 1:
			_check(label + " builds nothing (today's room)", stage == null and _stage_children(world).is_empty())
			continue
		_check(label + " builds a stage", stage != null and stage.get_child_count() > 0)
		if stage == null:
			continue
		var parts: Array = _RoomParts.stage_parts(stage)
		var tags := {}
		for part: Dictionary in parts:
			tags[part.tag] = true
		_check(label + " adds visible equipment over the level below (%d kinds of part, %d parts)" % [tags.size(), parts.size()], tags.size() > prev_tags)
		prev_tags = tags.size()
		_check_bounds(label, room_name, room, parts)
		_check_clips(label, stage, parts)
		_check_keepouts(label, parts)
		_check_support(label, stage, room_name)
		_check_outdoor(label, track, parts)
		_check_draws(label, stage)
		_check_layers(label, stage, services, room_name)
		if OS.get_cmdline_user_args().has("--dump"):
			_dump_stage(track, lvl, stage)
	# the grow-in is per cluster: the stage node stays at scale 1 and each cluster grows on its own spot
	p.force_level = 3
	p.refresh()
	p.force_level = 4
	p.refresh()
	p._process(0.2)
	var st4 := p.stage_node()
	var mid_ok := st4 != null and st4.scale.is_equal_approx(Vector3.ONE) and (st4.get_child(0) as Node3D).scale.x < 0.999
	p._process(1.0)
	var end_ok := st4 != null and (st4.get_child(0) as Node3D).scale.is_equal_approx(Vector3.ONE)
	_check("%s: the grow-in plays per cluster and ends at full size" % track, mid_ok and end_ok)
	p.force_level = 1
	p.refresh()
	await process_frame
	p.queue_free()
	await process_frame


func _stage_children(world: Node3D) -> Array:
	var out: Array = []
	for c in world.get_children():
		if String(c.name).begins_with("Stage_V"):
			out.append(c)
	return out


func _check_bounds(label: String, room_name: String, room: Dictionary, parts: Array) -> void:
	var bad: Array = []
	var ceiling := float(_RoomParts.CEILING_CLEAR[room_name])
	for part: Dictionary in parts:
		if part.outdoor:
			continue
		var bb: AABB = part.aabb
		var x0 := bb.position.x
		var x1 := bb.end.x
		var y0 := -bb.end.z
		var y1 := -bb.position.z
		if x0 < float(room.x0) + 0.15 or x1 > float(room.x1) - 0.15 or y0 < float(room.y0) + 0.15 or y1 > float(room.y1) - 0.15:
			bad.append("%s outside the walls (x %.2f..%.2f y %.2f..%.2f)" % [part.tag, x0, x1, y0, y1])
		elif bb.end.y > (float(_RoomParts.HANGER_TOP.get(room_name, ceiling)) if String(part.tag).begins_with("hanger") else ceiling) + 0.001:
			bad.append("%s above the ceiling (top %.3f > %.2f)" % [part.tag, bb.end.y, ceiling])
		elif bb.position.y < -0.005:
			bad.append("%s below the floor (%.3f)" % [part.tag, bb.position.y])
	_report(label + " stays inside its room and under the ceiling", bad)


func _check_clips(label: String, stage: Node3D, parts: Array) -> void:
	var bad: Array = []
	for part: Dictionary in parts:
		var bb: AABB = part.aabb
		var support := String(part.support)
		var allowed := support.substr(3) if support.begins_with("on:") else ""
		var grown := bb.grow(-CLIP_TOL)
		if grown.size.x <= 0.0 or grown.size.y <= 0.0 or grown.size.z <= 0.0:
			continue
		for o: Dictionary in _obstacles:
			if not (o.aabb as AABB).intersects(grown):
				continue
			if allowed != "" and String(o.name).begins_with(allowed):
				continue
			if _obb_vs_aabb(o.xf, o.half, grown):
				bad.append("%s clips %s" % [part.tag, o.name])
				break
	_report(label + " clips no wall, prop or door", bad)


## Separating-axis test of an oriented box against an axis-aligned box.
static func _obb_vs_aabb(xf: Transform3D, half: Vector3, bb: AABB) -> bool:
	var ca := bb.get_center()
	var ha := bb.size * 0.5
	var ax: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var bx: Array[Vector3] = [xf.basis.x.normalized(), xf.basis.y.normalized(), xf.basis.z.normalized()]
	var hb := [half.x * xf.basis.x.length(), half.y * xf.basis.y.length(), half.z * xf.basis.z.length()]
	var t := xf.origin - ca
	var axes: Array[Vector3] = []
	axes.append_array(ax)
	axes.append_array(bx)
	for a in ax:
		for b in bx:
			var c := a.cross(b)
			if c.length_squared() > 1e-8:
				axes.append(c.normalized())
	for l in axes:
		var ra := ha.x * absf(l.x) + ha.y * absf(l.y) + ha.z * absf(l.z)
		var rb := float(hb[0]) * absf(bx[0].dot(l)) + float(hb[1]) * absf(bx[1].dot(l)) + float(hb[2]) * absf(bx[2].dot(l))
		if absf(t.dot(l)) > ra + rb:
			return false
	return true


func _check_keepouts(label: String, parts: Array) -> void:
	var bad: Array = []
	for part: Dictionary in parts:
		var bb: AABB = part.aabb
		if bb.position.y < DOOR_HEAD:
			for d: Dictionary in _doors:
				var k: AABB = d.aabb
				if bb.position.x < k.end.x and bb.end.x > k.position.x and bb.position.z < k.end.z and bb.end.z > k.position.z:
					bad.append("%s blocks door %d (%s)" % [part.tag, d.id, d.room])
		if bb.position.y < HEAD and not _on_its_support(part):
			for disc: Dictionary in _discs:
				var c: Vector3 = disc.p
				var qx := clampf(c.x, bb.position.x, bb.end.x)
				var qz := clampf(c.z, bb.position.z, bb.end.z)
				if Vector2(qx - c.x, qz - c.z).length() < float(disc.r):
					bad.append("%s is within reach of %s's standing spot" % [part.tag, disc.id])
	_report(label + " keeps doors, standing spots and the respawn spot clear", bad)


## A part of an "on:<object>" cluster that stays within that object's footprint takes no floor space of its own.
func _on_its_support(part: Dictionary) -> bool:
	var support := String(part.support)
	if not support.begins_with("on:"):
		return false
	var obj := support.substr(3)
	var bb: AABB = part.aabb
	for o: Dictionary in _obstacles:
		if not String(o.name).begins_with(obj):
			continue
		var ob: AABB = (o.aabb as AABB).grow(0.05)
		if bb.position.x >= ob.position.x and bb.end.x <= ob.end.x and bb.position.z >= ob.position.z and bb.end.z <= ob.end.z:
			return true
	return false


## What holds each cluster up: the floor, a wall, the ceiling, the roof or the map object it stands on.
func _check_support(label: String, stage: Node3D, room_name: String) -> void:
	var bad: Array = []
	var ceiling := float(_RoomParts.CEILING_CLEAR.get(room_name, 3.0))
	for c in stage.get_children():
		var parts: Array = c.get_meta("parts", [])
		if parts.is_empty():
			continue
		var bb: AABB = parts[0].aabb
		for part: Dictionary in parts:
			bb = bb.merge(part.aabb)
		var support := String(c.get_meta("support", "floor"))
		var ok := true
		if support == "floor":
			ok = bb.position.y >= -0.005 and bb.position.y <= 0.03
		elif support == "ceiling":
			ok = bb.end.y >= ceiling - 0.03
		elif support == "roof":
			ok = absf(bb.position.y - ROOF_TOP) <= 0.03 and _touches(parts, "rf_", 0.03)
		elif support == "wall":
			ok = _touches(parts, "", 0.04)
		elif support.begins_with("on:"):
			ok = _touches(parts, support.substr(3), 0.04)
		if not ok:
			bad.append("%s (%s) floats: lowest %.3f, highest %.3f" % [c.name, support, bb.position.y, bb.end.y])
	_report(label + " has nothing floating (each piece stands on the floor or hangs from a wall, the ceiling or a map object)", bad)


## True when some part, grown by `gap`, meets an obstacle whose name starts with `prefix` ("" = any).
func _touches(parts: Array, prefix: String, gap: float) -> bool:
	for part: Dictionary in parts:
		var bb: AABB = (part.aabb as AABB).grow(gap)
		for o: Dictionary in _obstacles:
			if prefix != "" and not String(o.name).begins_with(prefix):
				continue
			if (o.aabb as AABB).intersects(bb) and _obb_vs_aabb(o.xf, o.half, bb):
				return true
	return false


## Outdoor parts: the solar wings leave every tracker reachable from its low (east) side, and the dish sits on the roof.
func _check_outdoor(label: String, track: String, parts: Array) -> void:
	var bad: Array = []
	var any_outdoor := false
	for part: Dictionary in parts:
		if part.outdoor:
			any_outdoor = true
	if not any_outdoor:
		return
	if track == "energy":
		for n: String in _RoomParts.objects_named("sf_solar_tracker"):
			var xf: Variant = _RoomParts.object_pose(n)
			var o: Vector3 = (xf as Transform3D).origin
			var spot := o + Vector3(2.3, 0.0, 0.0)        # 2.3 m east of the row: within the 2.6 m reach
			for part: Dictionary in parts:
				var bb: AABB = part.aabb
				if bb.position.y < HEAD - 0.3 and spot.x > bb.position.x - 0.3 and spot.x < bb.end.x + 0.3 and spot.z > bb.position.z - 0.3 and spot.z < bb.end.z + 0.3:
					bad.append("%s stands where a player cleans %s" % [part.tag, n])
					break
	if track == "command":
		var r: Dictionary = _RoomParts.room("Command Room")
		for part: Dictionary in parts:
			if not part.outdoor:
				continue
			var bb: AABB = part.aabb
			if bb.position.x < float(r.x0) or bb.end.x > float(r.x1) or -bb.end.z < float(r.y0) or -bb.position.z > float(r.y1) or bb.position.y < 3.1:
				bad.append("%s leaves the roof" % part.tag)
	_report(label + " outdoor parts stay on their trackers or roof and out of the way", bad)


## Draw calls: one per material surface, label and light. Keep a stage of a room well under a hundred.
func _check_draws(label: String, stage: Node3D) -> void:
	var surfaces := 0
	var extras := 0
	for n in stage.find_children("*", "", true, false):
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			surfaces += (n as MeshInstance3D).mesh.get_surface_count()
		elif n is Label3D or n is Light3D:
			extras += 1
	print("  %s: %d surfaces, %d labels/lights, %d clusters" % [label, surfaces, extras, stage.get_child_count()])
	_check(label + " keeps draw calls sensible (%d)" % (surfaces + extras), surfaces + extras <= 90)


## Indoor clusters on their room's layer only, outdoor clusters on an outdoor zone plus the sun layer, lights limited to
## the zone they light.
func _check_layers(label: String, stage: Node3D, services: GameServices, room_name: String) -> void:
	var z := services.zones
	var room_bit := z.bit_of(room_name)
	var ok := true
	for c in stage.get_children():
		var outdoor := bool(c.get_meta("outdoor", false))
		for n in (c as Node).find_children("*", "VisualInstance3D", true, false):
			var v := n as VisualInstance3D
			if outdoor:
				if (v.layers & room_bit) != 0 or (v.layers & z.sun_bit()) == 0:
					ok = false
			elif v.layers != room_bit:
				ok = false
			if v is Light3D and (v as Light3D).light_cull_mask != v.layers:
				ok = false
	_check(label + " draws on its own zone's layers", ok)


# ---------------------------------------------------------------- swapping

func _swaps(world: Node3D, services: GameServices) -> void:
	for track: String in TRACKS:
		var p := (load("res://scripts/upgrades/stages/%s_stages.gd" % track) as Script).new() as AreaStagePresenter
		world.add_child(p)
		p.setup(world, services, null)
		var ok := true
		for lvl in [2, 4, 3, 1, 4, 2, 1]:
			p.force_level = lvl
			p.refresh()
			await process_frame
			var stages := _stage_children(world)
			if lvl == 1:
				ok = ok and stages.is_empty() and p.stage_node() == null
			else:
				ok = ok and stages.size() == 1 and String(stages[0].name) == "Stage_V%d" % lvl
		_check("%s: levels swap cleanly (one stage at a time, none at V1)" % track, ok)
		p.queue_free()
		await process_frame


func _report(label: String, bad: Array) -> void:
	var unique: Array = []
	for b in bad:
		if not unique.has(b):
			unique.append(b)
	for i in mini(unique.size(), 12):
		print("    ", unique[i])
	if unique.size() > 12:
		print("    ... %d more" % (unique.size() - 12))
	_check(label, unique.is_empty())


# ---------------------------------------------------------------- dump for the check images

func _dump_stage(track: String, lvl: int, stage: Node3D) -> void:
	var out: Array = []
	for n in stage.find_children("*", "", true, false):
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var xf := mi.global_transform
			for i in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(i)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var tris: Array = []
				for v in verts:
					var w := xf * v
					tris.append([snappedf(w.x, 0.0001), snappedf(w.y, 0.0001), snappedf(w.z, 0.0001)])
				out.append({"color": _colour_of(mi.mesh.surface_get_material(i)), "tris": tris})
		elif n is Label3D:
			var l := n as Label3D
			var xf := l.global_transform
			var hw := float(l.text.length()) * float(l.font_size) * l.pixel_size * 0.3
			var hh := float(l.font_size) * l.pixel_size * 0.5
			var q := [xf * Vector3(-hw, -hh, 0.002), xf * Vector3(hw, -hh, 0.002), xf * Vector3(hw, hh, 0.002), xf * Vector3(-hw, hh, 0.002)]
			var tris2: Array = []
			for idx in [0, 1, 2, 0, 2, 3]:
				var w2: Vector3 = q[idx]
				tris2.append([w2.x, w2.y, w2.z])
			out.append({"color": [1.0, 1.0, 1.0], "tris": tris2})
	_dump.levels["%s:%d" % [track, lvl]] = out


func _colour_of(m: Material) -> Array:
	if m is StandardMaterial3D:
		var c := (m as StandardMaterial3D).albedo_color
		if (m as StandardMaterial3D).emission_enabled:
			c = c.lightened(0.2)
		return [c.r, c.g, c.b]
	if m is ShaderMaterial:
		var t: Color = (m as ShaderMaterial).get_shader_parameter("tint")
		return [t.r * 0.8, t.g * 0.8, t.b * 0.8]
	return [1.0, 0.0, 1.0]


func _write_dump() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DUMP_DIR))
	var f := FileAccess.open(DUMP_DIR + "/parts.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(_dump))
	f.close()
	print("  wrote ", ProjectSettings.globalize_path(DUMP_DIR + "/parts.json"))
