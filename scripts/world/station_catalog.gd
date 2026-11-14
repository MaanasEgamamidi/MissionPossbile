class_name StationCatalog
extends RefCounted
## Builds stable station records from the map.

## Map objects that are sun trackers: sf_solar_tracker, sf_solar_tracker.001 ... .011.
const TRACKER_PREFIX := "sf_solar_tracker"


## Returns every interactive object in Godot coordinates, plus the 12 sun trackers as stations of kind "solar" in the
## Exterior zone. A tracker record also holds "tracker": its index 0..11 in ColonyState.panel_dust.
static func from_manifest(manifest_path: String, zones: ColonyZones) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var stations: Dictionary = {}
	for object: Dictionary in data.objects:
		var m: Array = object.matrix_world
		var p := Vector3(float(m[0][3]), float(m[2][3]), -float(m[1][3]))
		var name := String(object.name)
		if name.begins_with(TRACKER_PREFIX):
			stations[name] = {"kind": "solar", "zone": ColonyZones.EXTERIOR, "position": [p.x, p.y, p.z], "specialty": "", "tracker": tracker_index(name)}
			continue
		if not object.has("inter"):
			continue
		stations[name] = {"kind": String(object.inter), "zone": zones.zone_of(String(object.area), p), "position": [p.x, p.y, p.z], "specialty": ""}
	return stations


## 0 for "sf_solar_tracker", N for "sf_solar_tracker.00N".
static func tracker_index(object_name: String) -> int:
	var dot := object_name.rfind(".")
	return 0 if dot < 0 else int(object_name.substr(dot + 1))
