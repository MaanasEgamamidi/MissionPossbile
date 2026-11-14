class_name ColonyZones
extends RefCounted
## Lighting zones of the colony: one per room rectangle of the source map, plus the dome plaza, the garden dome and
## the open exterior. Each zone owns one render layer (1..20). Meshes carry the layers of every zone they touch and
## each fixture light is limited to its own zone, so a light without a shadow map cannot shine through a wall.
## Room rectangles come from the source scene (gc_place.ROOMS_META) through data/colony_manifest.json and are in
## Blender coordinates: x = Godot x, y = -Godot z.

const PLAZA := "Dome plaza"
const GARDEN := "Garden dome"
const EXTERIOR := "Exterior"
const SUN_LAYER := 20          # render layer of everything that can shadow the sun: roofs, outer walls, outdoor objects
const OVERLAP := 0.03          # metres a mesh must reach into a room rectangle to be lit by that room
const THIN_MAX := 0.35         # a mesh thinner than this in plan and taller than 0.5 m is a panel
const THIN_PAD := 0.25         # how far a panel may sit outside a room line and still be lit from that room
const GARDEN_CENTRE := Vector2(50.0, -27.0)   # Blender x, y of the garden dome pad (colony.json pads)
const GARDEN_RADIUS := 11.0

## Source collection (area module) -> zone. A wall-mounted fixture sits on a room line, so its position alone cannot say
## which room it serves; the area that built it can. "Exterior" and "Roofs" span several zones and go by position.
const AREA_ZONE := {
	"Hangar": "Hangar bay", "Crew Corridor": "Crew corridor", "Mess Hall": "Mess hall", "Rec Kitchen": "Rec kitchen", "Med Bay": "Med Bay",
	"Command Room": "Command Room", "Blast-door Passage": "Blast-door passage", "West Bunk Room": "West bunk room", "East Quarters": "East quarters",
	"Service Corridor": "Service corridor", "Greenhouse": "Greenhouse", "Airlock": "Airlock", "Power Room": "Power Room", "Life Support": "Life Support",
	"Pipe gallery": "Pipe gallery", "Dome plaza": "Dome plaza", "Garden Dome": "Garden dome",
}

var rooms: Array = []          # {name, x0, y0, x1, y1, ceiling}
var dome := {}
var names: PackedStringArray = []


static func from_manifest(path: String) -> ColonyZones:
	var z := ColonyZones.new()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	z.rooms = data.rooms
	z.dome = data.dome
	for r in z.rooms:
		z.names.append(String(r.name))
	z.names.append(PLAZA)
	z.names.append(GARDEN)
	z.names.append(EXTERIOR)
	return z


func layer_of(zone: String) -> int:
	return names.find(zone) + 1          # render layer number, 1-based; 0 if unknown


func bit_of(zone: String) -> int:
	var l := layer_of(zone)
	return 0 if l <= 0 else 1 << (l - 1)


func outdoor_mask() -> int:
	return bit_of(PLAZA) | bit_of(GARDEN) | bit_of(EXTERIOR)


func sun_bit() -> int:
	return 1 << (SUN_LAYER - 1)


func in_dome(x: float, y: float) -> bool:
	var n := float(dome.n)
	return pow(absf((x - float(dome.cx)) / float(dome.rx)), n) + pow(absf((y - float(dome.cy)) / float(dome.ry)), n) < 1.0


## Zone of a point given in Blender x, y.
func zone_at(x: float, y: float, pad := 0.0) -> String:
	for r in rooms:
		if x > float(r.x0) - pad and x < float(r.x1) + pad and y > float(r.y0) - pad and y < float(r.y1) + pad:
			return String(r.name)
	return outside_zone_at(x, y)


func outside_zone_at(x: float, y: float) -> String:
	if Vector2(x, y).distance_to(GARDEN_CENTRE) < GARDEN_RADIUS:
		return GARDEN
	if in_dome(x, y):
		return PLAZA
	return EXTERIOR


## Zone an object belongs to: the zone of the area that built it, else the zone its position falls in.
func zone_of(area: String, world_pos: Vector3) -> String:
	if AREA_ZONE.has(area) and names.has(String(AREA_ZONE[area])):
		return String(AREA_ZONE[area])
	return zone_at_world(world_pos)


## Zone of a point given in Godot world space.
func zone_at_world(p: Vector3) -> String:
	return zone_at(p.x, -p.z, 0.05)


## Render-layer mask for a mesh whose world-space bounding box is `box` (Godot coordinates).
## A mesh belongs to a room only where it really overlaps that room's rectangle by OVERLAP in both directions, and to
## an outside zone only where it sticks out of every room. A floor tile or a cabinet that merely touches a wall line
## therefore stays out of the neighbouring room's lights, while a wall that straddles the line is lit from both sides.
func mask_for_aabb(box: AABB, area := "") -> int:
	var x0 := box.position.x
	var x1 := box.end.x
	var y0 := -box.end.z
	var y1 := -box.position.z
	var mask := 0
	var covered := 0.0
	# A thin upright panel on a room line (door leaf, partition, glazing) is seen from both rooms, whichever side of
	# the line its few centimetres happen to fall on: let it reach THIN_PAD across. Floor tiles are never thin.
	var pad := THIN_PAD if minf(x1 - x0, y1 - y0) < THIN_MAX and box.size.y > 0.5 else 0.0
	for r in rooms:
		var ox := minf(x1, float(r.x1) + pad) - maxf(x0, float(r.x0) - pad)
		var oy := minf(y1, float(r.y1) + pad) - maxf(y0, float(r.y0) - pad)
		# thin meshes (a wall panel 6 cm thick) still count if they lie inside the room
		var need_x := minf(OVERLAP, (x1 - x0) * 0.5)
		var need_y := minf(OVERLAP, (y1 - y0) * 0.5)
		if ox >= need_x and oy >= need_y:
			mask |= bit_of(String(r.name))
			covered += maxf(ox, 0.0) * maxf(oy, 0.0)
	var cx := (x0 + x1) * 0.5
	var cy := (y0 + y1) * 0.5
	var box_area := maxf((x1 - x0) * (y1 - y0), 1e-6)
	if mask == 0:
		mask = bit_of(outside_zone_at(cx, cy))
	elif covered < box_area * 0.98:
		# part of the mesh lies outside every room: light that part from the zone it stands in
		for p in [Vector2(x0 + 0.01, y0 + 0.01), Vector2(x1 - 0.01, y0 + 0.01), Vector2(x0 + 0.01, y1 - 0.01), Vector2(x1 - 0.01, y1 - 0.01), Vector2(cx, cy)]:
			if not _room_names().has(zone_at(p.x, p.y)):
				mask |= bit_of(outside_zone_at(p.x, p.y))
	if area == "Dome plaza":
		mask |= bit_of(PLAZA)
	elif area == "Garden Dome":
		mask |= bit_of(GARDEN)
	elif area == "Exterior":
		mask |= bit_of(outside_zone_at(cx, cy))
	return mask


var _room_name_cache: Dictionary = {}


func _room_names() -> Dictionary:
	if _room_name_cache.is_empty():
		for r in rooms:
			_room_name_cache[String(r.name)] = true
	return _room_name_cache


static func slug(zone: String) -> String:
	return zone.to_lower().replace(" ", "_").replace("-", "_")
