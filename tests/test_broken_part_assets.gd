extends SceneTree
## Broken-part assets (docs/revisions/BROKEN_PARTS_BRIEF.md, assets worker): every glb of data/broken_parts.json loads,
## stands at its spot inside its room's zone (ColonyZones), carries the effect / model nodes the data names with the
## shared colony materials, and every map object it replaces exists in the map. The axis conversion is checked
## against where Godot puts the intact object (colony.glb). Also: the repair station of each part stands next to it,
## in the right zone. Headless; reads only.

const DATA := "res://data/broken_parts.json"
const COLONY_GLB := "res://assets/colony/colony.glb"
const STATIONS := "res://data/stations_repairs.json"
const TASKS: Array[String] = ["T01", "T02", "T03", "T04", "T06", "T08", "T09", "T10", "T11", "T12"]
## How far (metres, plan view) the brief's spot may lie outside the part's model AABB. Designer tolerance.
const SPOT_PAD := 0.6
## Zone check pad: wall racks, consoles and door 901 stand on a room line.
const ZONE_PAD := 0.6

var passed := 0
var total := 0


func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var parts: Array = data.get("parts", [])
	_check("ten parts", parts.size() == 10, str(parts.size()))
	var ids: Array[String] = []
	for p: Dictionary in parts:
		ids.append(String(p.task_id))
	ids.sort()
	_check("the ten tasks of the brief", ids == TASKS, str(ids))
	var zones := ColonyZones.from_manifest("res://data/colony_manifest.json")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/colony_manifest.json"))
	var map_names := {}
	for o: Dictionary in manifest.objects:
		map_names[String(o.name)] = o
	var colony := (load(COLONY_GLB) as PackedScene).instantiate()
	var stations := {}
	for s: Dictionary in (JSON.parse_string(FileAccess.get_file_as_string(STATIONS)) as Dictionary).stations:
		stations[String(s.id)] = s
	var surface_src := (load("res://materials/colony_surface.gdshader") as Shader).code
	for p: Dictionary in parts:
		var tid := String(p.task_id)
		_check(tid + " glb exists", ResourceLoader.exists(String(p.glb)), String(p.glb))
		var scene := load(String(p.glb)) as PackedScene
		_check(tid + " glb loads", scene != null)
		if scene == null:
			continue
		var root := scene.instantiate() as Node3D
		var boxes := _boxes(root, Transform3D.IDENTITY, {})
		var all := _union(boxes.values())
		var b: Dictionary = p.bounds
		_check(tid + " AABB centre matches data", all.get_center().distance_to(_v3(b.center)) < 0.05, "%s vs %s" % [all.get_center(), b.center])
		_check(tid + " AABB size matches data", all.size.distance_to(_v3(b.size)) < 0.05, str(all.size))
		# every node the data names is in the glb
		var names_ok := true
		for key: String in ["effect_nodes", "model_nodes"]:
			for n: Variant in p.get(key, []):
				names_ok = names_ok and root.find_child(String(n), true, false) != null
		for n: Dictionary in p.get("nodes", []):
			names_ok = names_ok and root.find_child(String(n.name), true, false) != null
		_check(tid + " named nodes exist", names_ok)
		var model_boxes: Array = []
		for n: Variant in p.model_nodes:
			if boxes.has(String(n)):
				model_boxes.append(boxes[String(n)])
		if model_boxes.is_empty():
			model_boxes = boxes.values()          # T11: the dust patches are the whole part
		var model := _union(model_boxes)
		var spot := _v3(p.spot)
		var grown := model.grow(SPOT_PAD)
		_check(tid + " spot inside the model (plan)", spot.x >= grown.position.x and spot.x <= grown.end.x and spot.z >= grown.position.z and spot.z <= grown.end.z,
			"spot %s model %s..%s" % [spot, model.position, model.end])
		var c := model.get_center()
		_check(tid + " model in its room zone", zones.zone_at(c.x, -c.z, ZONE_PAD) == String(p.zone), "%s at %s" % [zones.zone_at(c.x, -c.z, ZONE_PAD), c])
		_check(tid + " shared colony materials + layers + dust", _materials_ok(root), "")
		# replaced map objects exist (manifest + Godot node), and the broken model stands where Godot puts them
		var intact: Array = []
		var hide_ok := true
		for i in (p.hide_objects as Array).size():
			var mname := String(p.hide_objects[i])
			var node := colony.find_child(String(p.hide_nodes[i]), true, false) as Node3D
			hide_ok = hide_ok and map_names.has(mname) and node != null
			if node != null:
				intact.append_array(_boxes(node, _global(node), {}).values())
		_check(tid + " hide_objects exist in the map", hide_ok, str(p.hide_objects))
		if not intact.is_empty():
			var ib := _union(intact)
			var d := Vector2(ib.get_center().x - c.x, ib.get_center().z - c.z).length()
			_check(tid + " broken model where Godot puts the intact one", d < 1.2 and absf(ib.position.y - model.position.y) < 0.15, "%.2f m (intact %s)" % [d, ib.get_center()])
		# special records
		if String(p.special) == "door_901":
			var door: Dictionary = p.door
			var ok := true
			for side: String in ["left", "right"]:
				var leaf := root.find_child(String(door[side].node), true, false) as Node3D
				var seal := root.find_child(String(door[side].seal_node), true, false)
				ok = ok and leaf != null and seal != null and seal.get_parent() == leaf
				if leaf != null:
					var lb: AABB = boxes[String(door[side].node)]
					var zr: Vector2 = EnvironmentCollision.DOORS[0].z
					ok = ok and absf(leaf.position.x - float(door[side].intact_rest_x)) < 0.35 and lb.position.z > zr.x - 0.1 and lb.end.z < zr.y + 0.1
			_check(tid + " door 901 leaves, seals, slab", ok)
			_check(tid + " door_leaves names", (p.door_leaves.L as Array).has(String(door.left.node)) and (p.door_leaves.R as Array).has(String(door.right.node)))
		elif String(p.special) == "dust":
			var dust: Dictionary = p.dust
			_check(tid + " dust uniform exists in the surface shader", surface_src.contains("instance uniform float " + String(dust.instance_uniform)))
			_check(tid + " dust patches", (p.dust_nodes as Array).size() >= 2 and (p.dust_nodes as Array).all(func(n: Variant) -> bool: return root.find_child(String(n), true, false) != null))
			var hz := zones.zone_at(c.x, -c.z) == "Hangar bay"
			_check(tid + " dust over the hangar floor", hz and model.size.x > 12.0 and model.size.z > 8.0, str(model))
		# the repair station that opens this part
		var st: Dictionary = stations.get(String(p.station_id), {})
		var at := _v3(st.get("position", [0, -100, 0]))
		var flat := Vector2(at.x, at.z)
		var near := flat.distance_to(Vector2(clampf(at.x, model.position.x, model.end.x), clampf(at.z, model.position.z, model.end.z)))
		if String(p.special) == "dust":
			near = 0.0 if model.has_point(Vector3(at.x, model.get_center().y, at.z)) else 99.0
		_check(tid + " station next to the part", near < 1.6 and RepairCatalog.ROOMS[String(p.room_id)].zones.has(zones.zone_at_world(at)), "%s %.2f m, %s" % [at, near, zones.zone_at_world(at)])
		root.free()
	colony.free()
	print("RESULT %d/%d" % [passed, total])
	quit(0 if passed == total else 1)


## World AABB of every MeshInstance3D under `node` (keyed by node name), `xf` = node's world transform.
func _boxes(node: Node, xf: Transform3D, out: Dictionary) -> Dictionary:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out[String(node.name)] = xf * (node as MeshInstance3D).mesh.get_aabb()
	for ch in node.get_children():
		var cxf := xf
		if ch is Node3D:
			cxf = xf * (ch as Node3D).transform
		_boxes(ch, cxf, out)
	return out


func _global(node: Node3D) -> Transform3D:
	var xf := node.transform
	var p := node.get_parent()
	while p != null:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _union(boxes: Array) -> AABB:
	var out := AABB()
	var first := true
	for b: AABB in boxes:
		out = b if first else out.merge(b)
		first = false
	return out


## Every surface uses a res://materials/colony/ material, every mesh has render layers and a dust value.
func _materials_ok(root: Node) -> bool:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.layers == 0 or not mi.has_meta("dust"):
			return false
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m == null or not m.resource_path.begins_with("res://materials/colony/"):
				print("  material ", mi.name, " ", m.resource_name if m else "null")
				return false
	return true


func _v3(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _check(label: String, ok: bool, detail := "") -> void:
	total += 1
	if ok:
		passed += 1
	print("PASS " if ok else "FAIL ", label, " ", detail)
