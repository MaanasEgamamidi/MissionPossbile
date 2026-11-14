class_name WorldCollision
extends RefCounted
## Builds map collision without loading the visual scene.

## Build static geometry, sliding doors and station volumes from JSON.
static func build(manifest_path: String, colliders_path: String) -> Node3D:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var assets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(colliders_path))["assets"]
	var result := Node3D.new()
	result.name = "Collision"
	for label: String in ["Static", "Doors", "Stations"]:
		var group := Node3D.new()
		group.name = label
		result.add_child(group)
	var areas: Dictionary = {}
	var doors: Dictionary = {}
	for object: Dictionary in manifest.objects:
		var area: String = object.area
		if not areas.has(area):
			var body := StaticBody3D.new()
			body.name = area.replace(" ", "_")
			body.collision_layer = Layers.WORLD
			body.collision_mask = 0
			result.get_node("Static").add_child(body)
			areas[area] = body
		var pose := object_transform(object.matrix_world)
		if object.cls == "ladder" and object.gc_asset == "hgw_ladder":
			var ladder := ClimbableLadder.new()
			ladder.name = object.name
			ladder.transform = pose
			result.add_child(ladder)
			# Solid side rails, open rungs: a convex hull around the whole ladder seals its climb/exit path.
			for side in [-1.0, 1.0]:
				add_boxes(areas[area], [{"c": [side * 0.26, 1.6, 0.0], "h": [0.02, 1.6, 0.035], "q": [0, 0, 0, 1]}], pose, object.name + "_rail")
		var boxes: Array = assets.get(object.gc_asset, {}).get("cols", [])
		if object.cls in ["floor", "static", "deco", "dynamic", "ladder"]:
			add_boxes(areas[area], boxes, pose, object.name)
		elif object.cls == "door" and object.has("door_id"):
			var id := int(object.door_id)
			if not doors.has(id):
				var door := DoorController.new()
				door.name = "Door_%d" % id
				door.door_id = id
				result.get_node("Doors").add_child(door)
				doors[id] = door
			var controller: DoorController = doors[id]
			controller.add_leaf(object.name, pose, float(object.door_slide), boxes)
		# Stations: map objects tagged with `inter`, plus the 12 sun trackers (kind "solar", Prompt 07), matching StationCatalog.
		var station_kind := String(object.get("inter", ""))
		if station_kind == "" and String(object.name).begins_with("sf_solar_tracker"):
			station_kind = "solar"
		var extra := StationCatalog.extra_for_object(String(object.name))
		if not extra.is_empty():
			station_kind = String(extra.kind)
		if station_kind != "":
			var station := Area3D.new()
			station.name = object.name
			station.position = pose.origin
			station.collision_layer = Layers.STATION
			station.collision_mask = 0
			station.set_meta("station_id", object.name)
			station.set_meta("kind", station_kind)
			station.add_to_group(&"station_volume")
			station.position.y += 1.0  # centred at hand height, not on the floor (origins sit at the object's base)
			var shape := CollisionShape3D.new()
			var sphere := SphereShape3D.new()
			sphere.radius = 1.2
			shape.shape = sphere
			station.add_child(shape)
			result.get_node("Stations").add_child(station)
	# stations with no map object (data/stations_*.json entries with an id and a position)
	for entry: Dictionary in StationCatalog.extra_entries():
		if entry.has("id") and entry.has("position"):
			var q: Array = entry.position
			result.get_node("Stations").add_child(_station_volume(String(entry.id), String(entry.kind), Vector3(float(q[0]), float(q[1]), float(q[2]))))
	return result


static func _station_volume(id: String, kind: String, at: Vector3) -> Area3D:
	var station := Area3D.new()
	station.name = id.validate_node_name()
	station.position = at + Vector3(0, 1.0, 0)
	station.collision_layer = Layers.STATION
	station.collision_mask = 0
	station.set_meta("station_id", id)
	station.set_meta("kind", kind)
	station.add_to_group(&"station_volume")
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.2
	shape.shape = sphere
	station.add_child(shape)
	return station

## Convert a Blender row matrix to Godot's Y-up coordinates.
static func object_transform(m: Array) -> Transform3D:
	var conversion := Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3.UP)
	var basis := Basis(Vector3(m[0][0], m[1][0], m[2][0]), Vector3(m[0][1], m[1][1], m[2][1]), Vector3(m[0][2], m[1][2], m[2][2]))
	return Transform3D(conversion * basis * conversion.transposed(), conversion * Vector3(m[0][3], m[1][3], m[2][3]))

## Add boxes with scale baked into dimensions, keeping physics nodes unscaled.
static func add_boxes(body: CollisionObject3D, boxes: Array, pose: Transform3D, object_name: String) -> void:
	for index: int in range(boxes.size()):
		var box: Dictionary = boxes[index]
		var q: Array = box.q
		var local := Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3]).normalized()), Vector3(box.c[0], box.c[1], box.c[2]))
		var combined := pose * local
		var shape := CollisionShape3D.new()
		shape.name = "%s_box_%d" % [object_name, index]
		shape.set_meta("object_name", object_name)
		shape.set_meta("box_index", index)
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(box.h[0], box.h[1], box.h[2]) * 2.0 * combined.basis.get_scale().abs()
		shape.shape = box_shape
		shape.transform = Transform3D(combined.basis.orthonormalized(), combined.origin)
		body.add_child(shape)

## Count static bodies, all boxes, doors, leaves and stations.
static func stats(collision: Node3D) -> Dictionary:
	var counts := {"bodies": collision.get_node("Static").get_child_count(), "boxes": 0, "doors": collision.get_node("Doors").get_child_count(), "leaves": 0, "stations": collision.get_node("Stations").get_child_count()}
	for node: Node in collision.find_children("*", "CollisionShape3D", true, false):
		if (node as CollisionShape3D).shape is BoxShape3D:
			counts.boxes += 1
	for door: Node in collision.get_node("Doors").get_children():
		for leaf: Node in door.get_children():
			if leaf is AnimatableBody3D:
				counts.leaves += 1
	return counts
