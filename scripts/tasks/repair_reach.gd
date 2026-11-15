extends RefCounted
## How far a crew member is from a repair spot (owner request, 2026-11-14): the whole broken object is the target, not
## only the small anchor on the floor, so a crew member standing within reach (GameConfig.interact_distance_m, 2.6 m)
## of ANY side of the object may work on it. Used by the host checks (ActionService, RepairRuntime), so it reads only
## data: the part's "model_bounds" box in data/broken_parts.json. Loaded by path (no class_name).

const DATA_PATH := "res://data/broken_parts.json"
## Extra metres on the host side, so a hit on the far edge of a mesh box (the client's aim) is never refused.
const SLACK_M := 0.3

static var _boxes := {}
static var _loaded := false


## The broken part's box (world AABB) of a task, or an empty AABB when the task has no part.
static func bounds_of(task_id: String) -> AABB:
	if not _loaded:
		_loaded = true
		_boxes.clear()
		if FileAccess.file_exists(DATA_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
			if parsed is Dictionary and (parsed as Dictionary).get("parts") is Array:
				for entry: Variant in parsed.parts:
					if not entry is Dictionary:
						continue
					var b: Variant = (entry as Dictionary).get("model_bounds", (entry as Dictionary).get("bounds", {}))
					if b is Dictionary and (b as Dictionary).has("center") and (b as Dictionary).has("size"):
						var c: Array = b.center
						var s: Array = b.size
						var size := Vector3(float(s[0]), float(s[1]), float(s[2]))
						_boxes[String(entry.get("task_id", ""))] = AABB(Vector3(float(c[0]), float(c[1]), float(c[2])) - size * 0.5, size)
	return _boxes.get(task_id, AABB())


## Distance used for reach: to the station's anchor, or (repair spots) to the nearest side of the broken object's box,
## measured flat on the floor, whichever is closer.
static func distance(station: Dictionary, pos: Vector3) -> float:
	var d := INF
	if station.get("position") is Array and (station.position as Array).size() >= 3:
		var q: Array = station.position
		d = pos.distance_to(Vector3(float(q[0]), float(q[1]), float(q[2])))
	if String(station.get("kind", "")) == "repair_task":
		var box := bounds_of(String(station.get("task_id", "")))
		if box.size != Vector3.ZERO:
			var dx := maxf(maxf(box.position.x - pos.x, 0.0), pos.x - box.end.x)
			var dz := maxf(maxf(box.position.z - pos.z, 0.0), pos.z - box.end.z)
			d = minf(d, maxf(0.0, Vector2(dx, dz).length() - SLACK_M))
	return d


## True when `pos` is within `reach` metres of the station (see distance()).
static func within(station: Dictionary, pos: Vector3, reach: float) -> bool:
	return distance(station, pos) <= reach
