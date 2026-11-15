extends "res://scripts/upgrades/stages/room_parts.gd"
## Look of the "energy" upgrade path (data/area_levels.json): the Power Room's west wall and the sun trackers outside.
##   V1  today's room (nothing built).
##   V2  a new battery rack (glowing charge bars) and a bigger inverter cabinet with a stack light and status lights,
##       standing against the west wall north of the airlock door.
##   V3  + a third rack, a cable tray along the west and north walls into the room's existing trays, and solar wing
##       panels on the high edge of all 12 sun trackers.
##   V4  + a fourth rack and a chiller: a full battery wall with an upper battery tier, a blue/orange coolant loop, and
##       wide solar wings on both edges of every tracker.
## Places were measured on the map (tools/blender/room_stages/dump_rooms.py): the strip x 26.24..27.0, y -5.62..-2.28
## is clear of the airlock door (y -8..-6), the console's standing spot (28.3, -3.6) and the chair beside it.

const WALL_X := 26.24          # inner face of the west wall (airlock side walls end at x 26.2)
const RACK_D := 0.75           # depth of a battery rack
const RACK_H := 2.2
const TRACKER_DECK := Vector3(0.06, 0.0, 1.724)   # deck centre from a tracker's origin (plan x, y, z), measured
const DECK_HALF := 1.155       # half width of the deck along its slope (2.0 m seen from above, tilted 30 degrees)
const DECK_LEN := 11.56        # length of the deck along the row
const TILT := 0.5236           # 30 degrees, high edge to the west


func track_id() -> String:
	return "energy"


func build_stage(level: int) -> Node3D:
	if level <= 1:
		return null
	var s := new_stage()
	_battery_wall(s, level)
	if level >= 3:
		_cable_tray(s, level)
		_solar_wings(s, level, "SolarWingsWest", "sf_solar_tracker", [0, 1, 2, 3, 4, 5])
		_solar_wings(s, level, "SolarWingsEast", "sf_solar_tracker", [6, 7, 8, 9, 10, 11])
	return s


# ---------------------------------------------------------------- battery wall (west wall, units face east)

func _battery_wall(s: Node3D, level: int) -> void:
	var k := Kit.new("BatteryWall", 26.75, -4.1, 0.0, "wall")
	# south to north: inverter, rack 2, rack 3, rack 4, chiller
	_inverter(k, -5.17)
	_rack(k, -4.36, "BATTERY 2")
	if level >= 3:
		_rack(k, -3.70, "BATTERY 3")
	if level >= 4:
		_rack(k, -3.04, "BATTERY 4")
		_chiller(k, -2.50)
		_upper_tier(k)
		_coolant_loop(k)
	commit(k, s)


## Frame on the floor at the unit's footprint centre, front facing east (into the room).
func _face_east(k: Kit, y: float, depth: float) -> Kit:
	return k.at(WALL_X + depth * 0.5, y, 0.0, -PI * 0.5)


func _rack(k: Kit, y: float, text: String) -> void:
	_face_east(k, y, RACK_D)
	var f := RACK_D * 0.5
	k.named("battery rack").cabinet(Vector3.ZERO, 0.6, RACK_D, RACK_H, "panel", "frame", 1)
	# orange top band and a vent grille in the cap
	k.span(Vector3(-0.3, f - 0.01, RACK_H - 0.16), Vector3(0.3, f + 0.014, RACK_H - 0.06), "orange")
	for i in 5:
		k.span(Vector3(-0.22 + i * 0.11, -0.2, RACK_H), Vector3(-0.18 + i * 0.11, 0.2, RACK_H + 0.012), "vent")
	# battery modules: 2 columns x 9 rows, each with a charge bar that glows
	for row in 9:
		var z := 0.2 + row * 0.205
		for col in 2:
			var x := -0.14 + col * 0.28
			k.span(Vector3(x - 0.125, f, z), Vector3(x + 0.125, f + 0.018, z + 0.18), "panel_dark")
			k.span(Vector3(x - 0.1, f + 0.018, z + 0.13), Vector3(x + 0.1, f + 0.026, z + 0.155), "led_green" if row < 7 else "led_amber")
			k.span(Vector3(x + 0.085, f + 0.018, z + 0.03), Vector3(x + 0.105, f + 0.03, z + 0.05), "led_blue")
	k.label(text, Vector3(0, f + 0.03, RACK_H - 0.11), 0.0022)


func _inverter(k: Kit, y: float) -> void:
	var d := 0.7
	_face_east(k, y, d)
	var f := d * 0.5
	k.named("inverter cabinet").cabinet(Vector3.ZERO, 0.9, d, 2.15, "panel_warm", "frame", 2)
	# louvred vents low, a data screen and a row of status lights high
	for i in 6:
		k.span(Vector3(-0.38, f, 0.2 + i * 0.07), Vector3(-0.06, f + 0.02, 0.23 + i * 0.07), "vent")
		k.span(Vector3(0.06, f, 0.2 + i * 0.07), Vector3(0.38, f + 0.02, 0.23 + i * 0.07), "vent")
	k.screen(Vector3(0, f, 1.55), 0.5, 0.3, Screen.POWER, 0.2, 0.03)
	var lights := ["led_green", "led_green", "led_amber", "led_blue", "led_green"]
	for i in lights.size():
		k.led(Vector3(-0.2 + i * 0.1, f + 0.01, 1.2), Vector3(0.05, 0.02, 0.05), lights[i])
	k.span(Vector3(-0.36, f, 0.95), Vector3(0.36, f + 0.015, 1.05), "yellow")
	k.label("INVERTER", Vector3(0, f + 0.02, 1.0), 0.0022, Color(0.1, 0.1, 0.1))
	# stack light on top: green, amber, red
	k.cyl(Vector3(0.3, 0.1, 2.2), 0.03, 0.1, "steel")
	var stack := ["led_green", "led_amber", "led_red"]
	for i in 3:
		k.cyl(Vector3(0.3, 0.1, 2.28 + i * 0.075), 0.045, 0.07, stack[i])
	k.cyl(Vector3(0.3, 0.1, 2.5), 0.05, 0.02, "frame")
	# conduits from the top into the wall
	for x in [-0.25, -0.1]:
		k.tube(Vector3(x, -0.1, 2.15), Vector3(x, -0.1, 2.3), 0.025, "frame")
		k.tube(Vector3(x, -0.1, 2.3), Vector3(x, -d * 0.5 + 0.02, 2.3), 0.025, "frame")


## Narrow chiller cabinet with a fan, at the north end of the battery wall.
func _chiller(k: Kit, y: float) -> void:
	var d := 0.7
	_face_east(k, y, d)
	var f := d * 0.5
	k.named("chiller").cabinet(Vector3.ZERO, 0.42, d, 2.0, "white", "frame", 1)
	k.lathe(Vector3(0, f, 1.35), [Vector2(0.0, 0.0), Vector2(0.17, 0.0), Vector2(0.17, 0.02)], "frame", "y", 20)
	for i in 3:
		k.box(Vector3(0, f + 0.025, 1.35), Vector3(0.3, 0.01, 0.03), "steel", Basis(Vector3(0, 0, 1), i * PI / 3.0))
	k.cyl(Vector3(0, f + 0.03, 1.35), 0.04, 0.02, "steel", "y")
	k.led(Vector3(0, f + 0.01, 0.9), Vector3(0.12, 0.02, 0.04), "led_cyan")
	k.label("COOLANT", Vector3(0, f + 0.02, 1.7), 0.0018)


## V4: battery modules above racks 2 to 4 (y -4.66..-2.74), a cap and a glowing charge strip.
func _upper_tier(k: Kit) -> void:
	var d := 0.6
	k.at(WALL_X + d * 0.5, -4.08, 0.0, -PI * 0.5)
	var f := d * 0.5
	# local x runs south: world y -4.66 is local x 0.58, world y -2.74 is local x -1.34
	k.named("upper battery tier").span(Vector3(-1.34, -f, 2.26), Vector3(0.58, f, 2.78), "panel_dark")
	k.span(Vector3(-1.36, -f, 2.78), Vector3(0.6, f + 0.01, 2.81), "frame")
	for i in 8:
		var x := -1.3 + i * 0.235
		k.span(Vector3(x, f, 2.3), Vector3(x + 0.215, f + 0.015, 2.74), "panel")
		k.span(Vector3(x + 0.03, f + 0.015, 2.62), Vector3(x + 0.185, f + 0.022, 2.65), "led_green")
	k.span(Vector3(-1.34, f, 2.26), Vector3(0.58, f + 0.02, 2.28), "glow_strip")


## V4: supply (blue) and return (orange) coolant pipes along the front of the upper tier, down into the chiller.
func _coolant_loop(k: Kit) -> void:
	var x := WALL_X + 0.67
	k.at(0.0, 0.0).named("coolant loop")
	k.pipe([Vector3(x, -4.6, 2.36), Vector3(x, -2.62, 2.36), Vector3(x, -2.62, 2.01)], 0.028, "blue")
	k.pipe([Vector3(x, -4.5, 2.7), Vector3(x, -2.33, 2.7), Vector3(x, -2.33, 2.01)], 0.028, "orange")
	for i in 5:
		k.band(Vector3(x, -4.3 + i * 0.36, 2.36), 0.028, "led_cyan", "y", 0.03)
	# labels face east like everything on this wall
	k.at(x + 0.04, -3.5, 0.0, -PI * 0.5)
	k.label("COOLANT IN", Vector3(0, 0, 2.44), 0.0016, Color(0.5, 0.8, 1.0))
	k.label("COOLANT OUT", Vector3(0, 0, 2.6), 0.0016, Color(1.0, 0.7, 0.4))


# ---------------------------------------------------------------- cable tray

## V3: a ladder tray on wall brackets high on the west wall, dropping at the corner to a tray along the north wall that
## meets the room's own trays at x 34.45.
func _cable_tray(s: Node3D, level: int) -> void:
	var k := Kit.new("CableTray", 27.0, -2.9, 0.0, "ceiling")
	k.at(0.0, 0.0).named("cable tray")
	# west wall run (x 26.24..26.6), z 2.84..2.94
	_tray(k, Vector3(WALL_X + 0.01, -5.55, 2.84), Vector3(WALL_X + 0.36, -2.72, 2.94), "y")
	for y: float in [-5.2, -4.0, -2.9]:
		if level >= 4 and y > -4.7:
			continue          # the upper battery tier carries the tray there
		k.span(Vector3(WALL_X + 0.005, y - 0.02, 2.62), Vector3(WALL_X + 0.03, y + 0.02, 2.84), "steel")
		k.tube(Vector3(WALL_X + 0.02, y, 2.66), Vector3(WALL_X + 0.32, y, 2.835), 0.012, "steel")
	# corner drop
	k.span(Vector3(WALL_X + 0.01, -2.72, 2.55), Vector3(WALL_X + 0.36, -2.4, 2.94), "frame")
	# north wall run (y -2.72..-2.40), z 2.55..2.65
	_tray(k, Vector3(WALL_X + 0.36, -2.72, 2.55), Vector3(34.4, -2.40, 2.65), "x")
	# hanger rods up to the plain ceiling tiles (y -3.77..-2.32, underside 3.12)
	k.named("hanger rod")
	for x in [27.5, 29.0, 31.2, 33.0]:
		k.tube(Vector3(x, -2.56, 2.655), Vector3(x, -2.56, 3.12), 0.01, "steel")
	k.named("cable tray")
	if level >= 4:
		k.span(Vector3(WALL_X + 0.4, -2.70, 2.53), Vector3(34.35, -2.68, 2.55), "glow_strip")
	commit(k, s)


## Ladder tray between lo and hi running along "x" or "y", with three cables inside.
func _tray(k: Kit, lo: Vector3, hi: Vector3, along: String) -> void:
	var t := 0.02
	k.span(lo, Vector3(hi.x, hi.y, lo.z + t), "steel")
	if along == "y":
		k.span(lo, Vector3(lo.x + t, hi.y, hi.z), "steel")
		k.span(Vector3(hi.x - t, lo.y, lo.z), hi, "steel")
		var cx := [lo.x + 0.08, lo.x + 0.17, lo.x + 0.26]
		var cols := ["frame", "orange", "frame"]
		for i in 3:
			k.tube(Vector3(cx[i], lo.y + 0.02, lo.z + 0.045), Vector3(cx[i], hi.y - 0.02, lo.z + 0.045), 0.025, cols[i], 8)
	else:
		k.span(lo, Vector3(hi.x, lo.y + t, hi.z), "steel")
		k.span(Vector3(lo.x, hi.y - t, lo.z), hi, "steel")
		var cy := [lo.y + 0.08, lo.y + 0.16, lo.y + 0.24]
		var cols2 := ["frame", "orange", "frame"]
		for i in 3:
			k.tube(Vector3(lo.x + 0.02, cy[i], lo.z + 0.045), Vector3(hi.x - 0.02, cy[i], lo.z + 0.045), 0.025, cols2[i], 8)


# ---------------------------------------------------------------- solar wings (outdoors)

## Wing panels continuing each tracker's deck: V3 0.9 m on the high (west) edge, V4 1.6 m there and 0.55 m on the low
## edge. Panels are dark blue cells in an aluminium frame on rails under the deck.
func _solar_wings(s: Node3D, level: int, node_name: String, prefix: String, indices: Array) -> void:
	var trackers: Array[Transform3D] = []
	var centre := Vector3.ZERO
	for i: int in indices:
		var n := prefix if i == 0 else "%s.%03d" % [prefix, i]
		var pose: Variant = object_pose(n)
		if pose is Transform3D:
			trackers.append(pose)
			centre += (pose as Transform3D).origin
	if trackers.is_empty():
		return
	centre /= float(trackers.size())
	var k := Kit.new(node_name, centre.x, -centre.z, 0.0, "on:" + prefix)
	k.outdoor = true
	var high := 0.9 if level == 3 else 1.6
	var low := 0.0 if level == 3 else 0.55
	for pose in trackers:
		var o := pose.origin
		k.at(o.x + TRACKER_DECK.x, -o.z + TRACKER_DECK.y, o.y + TRACKER_DECK.z).named("solar wing")
		_wing(k, -1.0, high)
		if low > 0.0:
			_wing(k, 1.0, low)
	commit(k, s)


## One wing on the side `side` (-1 high edge, +1 low edge) of the deck at the current frame (deck centre).
func _wing(k: Kit, side: float, width: float) -> void:
	var d := Vector3(cos(TILT), 0.0, -sin(TILT))         # down the slope (east)
	var nrm := Vector3(sin(TILT), 0.0, cos(TILT))         # deck normal
	var turn := Basis(Vector3(0, 0, 1), -TILT)
	var s0 := DECK_HALF + 0.05
	var mid := side * (s0 + width * 0.5)
	var segs := 8
	var seg_len := DECK_LEN / float(segs)
	for i in segs:
		var y := -DECK_LEN * 0.5 + seg_len * (float(i) + 0.5)
		var c := d * mid + Vector3(0, y, 0)
		k.box(c, Vector3(width, seg_len - 0.05, 0.035), "steel", turn)
		k.box(c + nrm * 0.02, Vector3(width - 0.05, seg_len - 0.1, 0.006), "solar_cell", turn)
		var strips := maxi(1, int(width / 0.5))
		for j in range(1, strips + 1):
			var off := -width * 0.5 + width * float(j) / float(strips + 1)
			k.box(c + nrm * 0.024 + d * off, Vector3(0.012, seg_len - 0.1, 0.004), "steel", turn)
	# rails under the wing, reaching back under the deck edge
	for y in [-DECK_LEN * 0.36, 0.0, DECK_LEN * 0.36]:
		var a := d * side * (DECK_HALF - 0.25) - nrm * 0.07 + Vector3(0, y, 0)
		var b := d * side * (s0 + width - 0.05) - nrm * 0.07 + Vector3(0, y, 0)
		k.tube(a, b, 0.025, "steel", 8)
