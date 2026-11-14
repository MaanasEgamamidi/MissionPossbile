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
		var extra: Dictionary = extra_for_object(name)
		if not extra.is_empty():
			# A data entry may move the station off the object's origin (for example a garage whose origin is under the
			# parked rover), so the reach and distance checks use a point a player can actually stand near.
			if (extra.get("position", null) is Array) and (extra.position as Array).size() >= 3:
				var q0: Array = extra.position
				p = Vector3(float(q0[0]), float(q0[1]), float(q0[2]))
			stations[name] = _record(extra, zones.zone_of(String(object.area), p), p)
			continue
		if not object.has("inter"):
			continue
		stations[name] = {"kind": String(object.inter), "zone": zones.zone_of(String(object.area), p), "position": [p.x, p.y, p.z], "specialty": ""}
	# stations with no map object (for example a field sample site): id + position given in the data file
	for entry: Dictionary in extra_entries():
		if entry.has("id") and entry.has("position"):
			var q: Array = entry.position
			var pos := Vector3(float(q[0]), float(q[1]), float(q[2]))
			stations[String(entry.id)] = _record(entry, zones.zone_at_world(pos), pos)
	return stations


## Extra station definitions added by later milestones, one file per part: res://data/stations_<part>.json with
## {"stations": [{"object": "<map object name>" | "prefix": "<name prefix>" | "id": "<new id>", "position": [x, y, z],
##   "kind": "...", "name": "words", "symbol": "?", "specialty": "" }]}.
static func extra_entries() -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://data")
	if dir == null:
		return out
	for f in dir.get_files():
		if f.begins_with("stations_") and f.ends_with(".json"):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + f))
			if data is Dictionary and (data as Dictionary).get("stations", null) is Array:
				out.append_array(data.stations)
	return out


## The extra definition that matches a map object by exact name or prefix, or {}.
static func extra_for_object(object_name: String) -> Dictionary:
	for entry: Dictionary in extra_entries():
		if String(entry.get("object", "")) == object_name:
			return entry
		var prefix := String(entry.get("prefix", ""))
		if prefix != "" and object_name.begins_with(prefix):
			return entry
	return {}


static func _record(entry: Dictionary, zone: String, p: Vector3) -> Dictionary:
	var r := {"kind": String(entry.kind), "zone": zone, "position": [p.x, p.y, p.z], "specialty": String(entry.get("specialty", ""))}
	for key in ["name", "symbol"]:
		if entry.has(key):
			r[key] = String(entry[key])
	return r


## 0 for "sf_solar_tracker", N for "sf_solar_tracker.00N".
static func tracker_index(object_name: String) -> int:
	var dot := object_name.rfind(".")
	return 0 if dot < 0 else int(object_name.substr(dot + 1))
