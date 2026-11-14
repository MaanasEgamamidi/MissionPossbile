class_name TestCollision
extends SceneTree
## Headless checks against the shipped map and synthetic terrain.

var _passed: int = 0
var _total: int = 0
var _world: Node3D

func _initialize() -> void:
	await process_frame
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/colony_manifest.json"))
	var assets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/colliders.json"))["assets"]
	_world = WorldCollision.build("res://data/colony_manifest.json", "res://data/colliders.json")
	root.add_child(_world)
	var stats := WorldCollision.stats(_world)
	print("STATS ", JSON.stringify(stats))
	_check(stats.doors == 24 and stats.leaves == 52 and stats.stations == 9, "24 doors, 52 leaves, 9 stations")
	var shapes: Dictionary = {}
	var counts: Dictionary = {}
	for node: Node in _world.find_children("*", "CollisionShape3D", true, false):
		if node.has_meta("object_name"):
			var object_name: String = node.get_meta("object_name")
			counts[object_name] = int(counts.get(object_name, 0)) + 1
			if node.get_meta("box_index") == 0:
				shapes[object_name] = node
	var correct: bool = true
	var eligible: Array[Dictionary] = []
	var area_names: Dictionary = {}
	for object: Dictionary in manifest.objects:
		area_names[object.area] = true
		if object.cls not in ["floor", "static", "deco", "dynamic", "ladder", "door"]:
			continue
		var boxes: Array = assets.get(object.gc_asset, {}).get("cols", [])
		correct = correct and int(counts.get(object.name, 0)) == boxes.size()
		if not boxes.is_empty():
			eligible.append(object)
	_check(correct, "exact collider count for every eligible manifest object")
	_check(stats.bodies == area_names.size(), "one static body per manifest area")
	var max_error: float = 0.0
	var rotated: int = 0
	var scaled: int = 0
	# Check every object as well as printing 20 evenly distributed samples.
	for object: Dictionary in eligible:
		var box: Dictionary = assets[object.gc_asset].cols[0]
		var m: Array = object.matrix_world
		var local := Vector3(box.c[0], -float(box.c[2]), box.c[1])
		var blender := Vector3.ZERO
		for row: int in range(3):
			blender[row] = float(m[row][3]) + float(m[row][0]) * local.x + float(m[row][1]) * local.y + float(m[row][2]) * local.z
		var expected := Vector3(blender.x, blender.z, -blender.y)
		var shape: CollisionShape3D = shapes[object.name]
		max_error = maxf(max_error, shape.global_position.distance_to(expected))
		if absf(float(m[0][1])) + absf(float(m[1][0])) + absf(float(m[2][0])) > 0.01:
			rotated += 1
		for column: int in range(3):
			if absf(Vector3(m[0][column], m[1][column], m[2][column]).length() - 1.0) > 0.01:
				scaled += 1
				break
	_check(max_error < 0.001, "all %d first-box centres (rotated=%d scaled=%d max_error=%.6fm)" % [eligible.size(), rotated, scaled, max_error])
	for sample: int in range(20):
		var object: Dictionary = eligible[int(sample * (eligible.size() - 1) / 19.0)]
		var shape: CollisionShape3D = shapes[object.name]
		print("TRANSFORM ", object.name, " ", shape.global_position)
	var layers_ok: bool = true
	for body: Node in _world.get_node("Static").get_children():
		layers_ok = layers_ok and body.collision_layer == Layers.WORLD and body.collision_mask == 0
	for station: Node in _world.get_node("Stations").get_children():
		layers_ok = layers_ok and station.collision_layer == Layers.STATION and station.collision_mask == 0 and station.get_meta("station_id") == String(station.name) and station.has_meta("kind") and is_equal_approx(station.get_child(0).shape.radius, 1.2)
	_check(layers_ok, "static and station layers, metadata and radius")
	await _frames(3)
	for room: Dictionary in (manifest.rooms as Array).slice(0, 3):
		var point := Vector3((room.x0 + room.x1) * 0.5, 0.3, -(room.y0 + room.y1) * 0.5)
		var hit := _ray(point, point - Vector3.UP, Layers.WORLD)
		var y: float = hit.get("position", Vector3(0, INF, 0)).y
		_check(not hit.is_empty() and absf(y) < 0.1, "floor %s y=%.4f" % [room.name, y])
	var wall := _ray(Vector3(20, 1.5, 1), Vector3(20, 1.5, 3), Layers.WORLD)
	_check(not wall.is_empty(), "ray across hangar wall blocked")
	await _doors()
	await _terrain()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)

func _doors() -> void:
	var door := _world.get_node("Doors/Door_1") as DoorController
	var visuals := Node3D.new()
	root.add_child(visuals)
	var starts: Dictionary = {}
	for leaf: Node in door.get_children():
		if leaf is AnimatableBody3D:
			var visual := Node3D.new()
			visual.name = leaf.name
			visual.transform = leaf.transform
			visuals.add_child(visual)
			starts[String(leaf.name)] = visual.position
	_check(door.attach_visuals(visuals) == starts.size(), "attach all synthetic door visuals")
	var start := Vector3(16.85, 1.0, -7)
	var end := Vector3(16.85, 1.0, -9)
	_check(not _ray(start, end, Layers.WORLD | Layers.DOOR).is_empty(), "closed door blocks ray")
	var player := CharacterBody3D.new()
	player.collision_layer = Layers.PLAYER
	player.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.8
	shape.shape = capsule
	player.add_child(shape)
	player.position = Vector3(17, 0.9, -7)
	root.add_child(player)
	await _frames(60)
	_check(door.is_open(), "player opens door within 1.0 physics second")
	_check(_ray(start, end, Layers.WORLD | Layers.DOOR).is_empty(), "open door ray passes")
	var moved: bool = true
	for visual: Node3D in visuals.get_children():
		var expected := -0.5 if String(visual.name) == "hgw_door_small_leaf" else 0.5
		moved = moved and visual.position.distance_to(starts[String(visual.name)] + Vector3(expected, 0, 0)) < 0.001
	_check(moved, "visual leaves move by signed door_slide")
	player.queue_free()
	await _frames(60)
	_check(not door.is_open() and door.open_amount < 0.001 and not _ray(start, end, Layers.DOOR).is_empty(), "door closes after player leaves")
	door.set_locked(true)
	var visitor := StaticBody3D.new()
	visitor.collision_layer = Layers.PLAYER
	visitor.collision_mask = 0
	var visitor_shape := CollisionShape3D.new()
	visitor_shape.shape = capsule
	visitor.add_child(visitor_shape)
	visitor.position = Vector3(17, 0.9, -7)
	root.add_child(visitor)
	await _frames(60)
	_check(door.open_amount == 0.0 and not _ray(start, end, Layers.DOOR).is_empty(), "locked door stays shut beside player")
	visitor.queue_free()
	visuals.queue_free()

func _terrain() -> void:
	var scene := Node3D.new()
	scene.name = "TestTerrain"
	scene.position = Vector3(200, 2, 100)
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Surface"
	scene.add_child(mesh_node)
	mesh_node.owner = scene
	var vertices := PackedVector3Array()
	for z: int in range(9):
		for x: int in range(9):
			vertices.append(Vector3(x * 0.5, _height(x * 0.5, z * 0.5), z * 0.5))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	mesh_node.mesh = mesh
	root.add_child(scene)
	var grid := TerrainHeight.from_meshes(scene, 0.5, Rect2(200, 100, 4, 4))
	var error: float = 0.0
	for vertex: Vector3 in vertices:
		error = maxf(error, absf(grid.height_at(200 + vertex.x, 100 + vertex.z) - (2 + vertex.y)))
	_check(error < 0.001, "sloped bumpy world-space mesh samples max_error=%.6f" % error)
	_check(is_equal_approx(grid.height_at(190, 90), grid.heights[0]) and is_equal_approx(grid.height_at(210, 110), grid.heights[-1]), "height sampling clamps edges")
	var u: float = 0.3
	var v: float = 0.6
	var expected := lerpf(lerpf(grid.heights[0], grid.heights[1], u), lerpf(grid.heights[9], grid.heights[10], u), v)
	_check(absf(grid.height_at(200 + 0.5 * u, 100 + 0.5 * v) - expected) < 0.0001, "bilinear interpolation")
	var sparse := TerrainHeight.from_meshes(scene, 0.25, Rect2(200, 100, 4, 4))
	var finite: bool = true
	for value: float in sparse.heights:
		finite = finite and is_finite(value)
	_check(finite and sparse.heights.size() == 289, "empty sample cells filled from neighbours")
	var body := grid.make_body()
	root.add_child(body)
	await _frames(3)
	for index: int in range(10):
		var x := 200.15 + float(index % 5) * 0.79
		var z := 100.23 + float(index) * 0.34
		var hit := _ray(Vector3(x, 10, z), Vector3(x, -10, z), Layers.WORLD)
		var y: float = hit.get("position", Vector3(0, INF, 0)).y
		_check(not hit.is_empty() and absf(y - grid.height_at(x, z)) < 0.05, "heightfield ray %d error=%.5f" % [index, absf(y - grid.height_at(x, z))])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/tmp"))
	var packed := PackedScene.new()
	var packed_ok := packed.pack(scene)
	var saved := ResourceSaver.save(packed, "res://tests/tmp/terrain.tscn")
	_check(packed_ok == OK and saved == OK, "save tool input scene")
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/godot/build_heightmap.gd", "--", "--scene", "res://tests/tmp/terrain.tscn", "--cell", "0.5", "--out", "res://tests/tmp/terrain_height.res"]), output, true)
	for line: String in output:
		print(line.strip_edges())
	var loaded := load("res://tests/tmp/terrain_height.res") as TerrainHeight if FileAccess.file_exists("res://tests/tmp/terrain_height.res") else null
	_check(exit_code == 0 and loaded != null and loaded.width == 9 and loaded.depth == 9 and loaded.heights == grid.heights, "tool writes loadable matching resource")
	scene.queue_free()
	body.queue_free()

func _height(x: float, z: float) -> float:
	return x * 0.15 + z * 0.08 + 0.12 * sin(x) * cos(z)

func _ray(start: Vector3, end: Vector3, mask: int) -> Dictionary:
	return _world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, end, mask))

func _frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame

func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		_passed += 1
		print("PASS ", label)
	else:
		print("FAIL ", label, ": condition was false")
