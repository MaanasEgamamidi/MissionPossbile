class_name StationCatalog
extends RefCounted
## Builds stable station records from the map.

## Returns every interactive object in Godot coordinates.
static func from_manifest(manifest_path: String, zones: ColonyZones) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var stations: Dictionary = {}
	for object: Dictionary in data.objects:
		if not object.has("inter"):
			continue
		var m: Array = object.matrix_world
		var p := Vector3(float(m[0][3]), float(m[2][3]), -float(m[1][3]))
		stations[object.name] = {"kind": String(object.inter), "zone": zones.zone_of(String(object.area), p), "position": [p.x, p.y, p.z], "specialty": ""}
	return stations
