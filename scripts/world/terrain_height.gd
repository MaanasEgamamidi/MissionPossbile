class_name TerrainHeight
extends Resource
## A sampled outdoor height grid in world coordinates.

## World x and z of the first sample.
@export var origin: Vector2 = Vector2.ZERO
## Sample spacing in metres.
@export var cell: float = 1.0
## Number of samples along x.
@export var width: int = 0
## Number of samples along z.
@export var depth: int = 0
## Heights in z-major rows.
@export var heights: PackedFloat32Array = []

## Bilinear height, clamped to the grid edges.
func height_at(x: float, z: float) -> float:
	if width < 1 or depth < 1 or heights.size() != width * depth:
		return 0.0
	var u := clampf((x - origin.x) / cell, 0.0, width - 1.0)
	var v := clampf((z - origin.y) / cell, 0.0, depth - 1.0)
	var ix := int(floor(u))
	var iz := int(floor(v))
	var nx := mini(ix + 1, width - 1)
	var nz := mini(iz + 1, depth - 1)
	return lerpf(lerpf(heights[iz * width + ix], heights[iz * width + nx], u - ix), lerpf(heights[nz * width + ix], heights[nz * width + nx], u - ix), v - iz)

## Build a heightfield centred on its sample grid, with metre spacing.
func make_body() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var map := HeightMapShape3D.new()
	map.map_width = width
	map.map_depth = depth
	map.map_data = heights
	shape.shape = map
	shape.position = Vector3(origin.x + (width - 1) * cell * 0.5, 0, origin.y + (depth - 1) * cell * 0.5)
	shape.scale = Vector3(cell, 1, cell)
	body.add_child(shape)
	return body

## Bin world vertices to nearest samples, keep the highest, then fill holes from neighbours.
static func from_meshes(root: Node3D, cell: float, bounds: Rect2) -> TerrainHeight:
	var grid := TerrainHeight.new()
	grid.origin = bounds.position
	grid.cell = maxf(cell, 0.001)
	grid.width = maxi(2, ceili(bounds.size.x / grid.cell) + 1)
	grid.depth = maxi(2, ceili(bounds.size.y / grid.cell) + 1)
	grid.heights.resize(grid.width * grid.depth)
	grid.heights.fill(-INF)
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node: Node in nodes:
		var instance := node as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		var pose := _world_transform(instance)
		for surface: int in range(instance.mesh.get_surface_count()):
			var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var point := pose * vertex
				if point.x < bounds.position.x or point.x > bounds.end.x or point.z < bounds.position.y or point.z > bounds.end.y:
					continue
				var x := clampi(roundi((point.x - grid.origin.x) / grid.cell), 0, grid.width - 1)
				var z := clampi(roundi((point.z - grid.origin.y) / grid.cell), 0, grid.depth - 1)
				var index := z * grid.width + x
				grid.heights[index] = maxf(grid.heights[index], point.y)
	# Multi-source flood fill: each frontier averages the already filled neighbours.
	var frontier: Array[int] = []
	for index: int in range(grid.heights.size()):
		if is_finite(grid.heights[index]):
			frontier.append(index)
	if frontier.is_empty():
		grid.heights.fill(0.0)
	while not frontier.is_empty():
		var candidates: Dictionary = {}
		for index: int in frontier:
			for neighbour: int in grid._neighbours(index):
				if not is_finite(grid.heights[neighbour]):
					candidates[neighbour] = true
		frontier.clear()
		var values: Dictionary = {}
		for index: int in candidates:
			var sum: float = 0.0
			var count: int = 0
			for neighbour: int in grid._neighbours(index):
				if is_finite(grid.heights[neighbour]):
					sum += grid.heights[neighbour]
					count += 1
			values[index] = sum / count
		for index: int in values:
			grid.heights[index] = values[index]
			frontier.append(index)
	return grid

func _neighbours(index: int) -> Array[int]:
	var neighbours: Array[int] = []
	if index % width > 0:
		neighbours.append(index - 1)
	if index % width < width - 1:
		neighbours.append(index + 1)
	if index >= width:
		neighbours.append(index - width)
	if index + width < heights.size():
		neighbours.append(index + width)
	return neighbours

static func _world_transform(node: Node3D) -> Transform3D:
	if node.is_inside_tree():
		return node.global_transform
	var pose := node.transform
	var parent := node.get_parent_node_3d()
	while parent != null:
		pose = parent.transform * pose
		parent = parent.get_parent_node_3d()
	return pose
