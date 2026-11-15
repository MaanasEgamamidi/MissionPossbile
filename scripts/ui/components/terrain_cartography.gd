class_name TerrainCartography
extends RefCounted
## Georeferenced orthographic imagery of the unchanged source world. Coordinates are Godot X/Z metres.
const ROOT := "res://assets/ui/cartography/"
static var _meta: Dictionary = {}
static var _textures: Dictionary = {}
static var _contours: Array = []

static func metadata() -> Dictionary:
	if _meta.is_empty():
		_meta = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "provenance.json"))
	return _meta

static func bounds(layer: String) -> Rect2:
	var a: Array = metadata()[layer]
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))

static func texture(layer: String) -> Texture2D:
	if not _textures.has(layer):
		_textures[layer] = load(ROOT + "surface-" + layer + ".png")
	return _textures[layer] as Texture2D

static func draw_surface(canvas: CanvasItem, project: Callable, detail := true) -> void:
	for layer: String in (["overview", "detail"] if detail else ["overview"]):
		var b := bounds(layer)
		var start: Vector2 = project.call(b.position)
		var end: Vector2 = project.call(b.end)
		canvas.draw_texture_rect(texture(layer), Rect2(start, end - start), false, Color(0.82, 0.86, 0.9))

static func draw_contours(canvas: CanvasItem, project: Callable, visible_world: Rect2, scale: float) -> void:
	if _contours.is_empty():
		var records: Array = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "contours.json"))
		for rec: Dictionary in records:
			var points := PackedVector2Array()
			var extent := Rect2()
			for a: Array in rec.points:
				var point := Vector2(float(a[0]), float(a[1]))
				extent = Rect2(point, Vector2.ZERO) if points.is_empty() else extent.expand(point)
				points.append(point)
			_contours.append({"points": points, "bounds": extent, "major": bool(rec.major), "height": float(rec.height)})
	# Drawing in georeferenced world units avoids reprojecting every contour vertex while panning.
	var origin: Vector2 = project.call(Vector2.ZERO)
	canvas.draw_set_transform(origin, 0, Vector2.ONE * scale)
	for rec: Dictionary in _contours:
		if not visible_world.intersects(rec.bounds): continue
		if scale < 3.0 and not bool(rec.major): continue
		canvas.draw_polyline(rec.points, Color(0.95, 0.88, 0.71, 0.43 if bool(rec.major) else 0.18), 1.0 / scale, true)
	canvas.draw_set_transform(Vector2.ZERO)
