extends "res://scripts/upgrades/stages/room_parts.gd"
## Look of the "life_support" upgrade path (data/area_levels.json): the Life Support room.
##   V1  today's room (nothing built).
##   V2  a second CO2 scrubber bed (two adsorber columns on a blower cabinet) east of the console, and an O2 buffer
##       tank (green band) against the north wall.
##   V3  + twin electrolyser stacks (water in, oxygen and hydrogen out) on the west wall, in a blue water loop with a
##       pump.
##   V4  + a full redundant plant: the buffer tank becomes a bank of three tanks (O2, N2, H2O) on a header, a filter
##       bank behind the scrubber, and labelled pipes linking the electrolysers, the filters and the tanks overhead.
## Places were measured on the map (tools/blender/room_stages/dump_rooms.py): the console's standing spot (38.1, 3.0),
## the north door (x 36.5..37.5) and the west door (y 2.5..3.5) stay clear; overhead pipes added here run at z 2.3..2.45,
## below the room's own overhead pipes (z 2.67 and up).


func track_id() -> String:
	return "life_support"


func build_stage(level: int) -> Node3D:
	if level <= 1:
		return null
	var s := new_stage()
	_scrubber(s)
	if level >= 4:
		_tank_bank(s)
	else:
		_buffer_tank(s)
	if level >= 3:
		_electrolysers(s)
	if level >= 4:
		_filter_bank(s)
		_plant_pipes(s)
	return s


# ---------------------------------------------------------------- V2

## Second scrubber bed: blower cabinet (x 38.95..40.25, y 4.45..5.25) with two adsorber columns, front to the south.
func _scrubber(s: Node3D) -> void:
	var k := Kit.new("ScrubberBed2", 39.6, 4.85, 0.0, "floor")
	k.at(39.6, 4.85, 0.0, PI).named("scrubber bed")            # local x = west
	var d := 0.8
	var f := d * 0.5
	k.cabinet(Vector3.ZERO, 1.3, d, 0.9, "panel", "frame", 3)
	for i in 5:
		k.span(Vector3(-0.58, f, 0.2 + i * 0.07), Vector3(-0.1, f + 0.02, 0.235 + i * 0.07), "vent")
	k.screen(Vector3(0.32, f, 0.6), 0.36, 0.22, Screen.DATA, 0.15, 0.025)
	var leds := ["led_green", "led_green", "led_blue"]
	for i in 3:
		k.led(Vector3(0.2 + i * 0.08, f + 0.01, 0.3), Vector3(0.04, 0.02, 0.03), leds[i])
	for sx: float in [-0.33, 0.33]:
		k.lathe(Vector3(sx, 0.0, 0.9), [Vector2(0.2, 0.0), Vector2(0.21, 0.04), Vector2(0.21, 0.78), Vector2(0.16, 0.88), Vector2(0.07, 0.93), Vector2(0.0, 0.94)], "white", "z", 20)
		k.band(Vector3(sx, 0.0, 1.45), 0.21, "teal", "z", 0.1)
		k.cyl(Vector3(sx, 0.0, 0.92), 0.23, 0.04, "steel", "z", 20)
		k.tube(Vector3(sx, 0.0, 1.82), Vector3(sx, 0.0, 1.92), 0.04, "steel", 10)
	k.pipe([Vector3(-0.33, 0.0, 1.92), Vector3(0.33, 0.0, 1.92)], 0.04, "steel")
	k.span(Vector3(-0.09, -0.07, 1.86), Vector3(0.09, 0.07, 1.98), "frame")
	k.cyl(Vector3(0.0, 0.0, 2.0), 0.05, 0.02, "red", "z", 12)
	k.label("CO2 SCRUBBER 2", Vector3(0.0, f + 0.022, 0.8), 0.0018)
	commit(k, s)


## O2 buffer tank on the north wall (x 39.22..39.98).
func _buffer_tank(s: Node3D) -> void:
	var k := Kit.new("O2BufferTank", 39.6, 9.3, 0.0, "floor")
	_tank(k, 39.6, 9.32, 0.38, 1.85, "green", "O2")
	k.label("BUFFER", Vector3(0.0, 0.39, 0.82), 0.0016)
	commit(k, s)


## A vertical tank with domed ends on a skirt, a colour band, a gauge, a top valve and a big label. Leaves the frame at
## the tank, front to the south.
func _tank(k: Kit, x: float, y: float, r: float, h: float, band_key: String, text: String) -> void:
	k.at(x, y, 0.0, PI).named("%s tank" % text)
	k.lathe(Vector3.ZERO, [Vector2(r * 0.8, 0.0), Vector2(r * 0.8, 0.22)], "frame", "z", 20)
	var body := [Vector2(0.0, 0.18), Vector2(r * 0.66, 0.21), Vector2(r * 0.95, 0.3), Vector2(r, 0.42), Vector2(r, h - 0.3), Vector2(r * 0.95, h - 0.18), Vector2(r * 0.66, h - 0.09), Vector2(0.0, h - 0.06)]
	k.lathe(Vector3.ZERO, body, "white", "z", 24)
	k.band(Vector3(0, 0, h * 0.62), r, band_key, "z", 0.12)
	k.band(Vector3(0, 0, 0.5), r, "frame", "z", 0.03)
	k.cyl(Vector3(0, r + 0.02, h * 0.62 - 0.22), 0.07, 0.04, "steel", "y", 16)
	k.cyl(Vector3(0, r + 0.042, h * 0.62 - 0.22), 0.055, 0.006, "white", "y", 16)
	k.span(Vector3(-0.004, r + 0.046, h * 0.62 - 0.24), Vector3(0.004, r + 0.05, h * 0.62 - 0.18), "red")
	k.cyl(Vector3(0, 0, h - 0.02), 0.035, 0.1, "steel", "z", 10)
	k.cyl(Vector3(0, 0, h + 0.05), 0.07, 0.02, "red", "z", 12)
	k.label(text, Vector3(0, r * 1.12 + 0.012, h * 0.62), 0.006 if r > 0.3 else 0.0045, Color(0.97, 0.98, 1.0))


# ---------------------------------------------------------------- V3

## Twin electrolyser stacks against the west wall (x 34.3..35.0, y 6.35..8.1), in a blue water loop with a pump.
func _electrolysers(s: Node3D) -> void:
	var k := Kit.new("Water splitters", 34.7, 7.22, 0.0, "floor")
	for i in 2:
		var cy := 6.72 + i * 1.01
		k.at(34.65, cy, 0.0, -PI * 0.5).named("water splitter stack")      # front east, local x = south
		k.span(Vector3(-0.375, -0.35, 0.0), Vector3(0.375, 0.35, 0.1), "frame")
		for sx: float in [-1.0, 1.0]:
			k.span(Vector3(sx * 0.26, -0.3, 0.12), Vector3(sx * 0.33, 0.3, 1.22), "steel")
		for j in 13:
			var x := -0.24 + j * 0.04
			k.span(Vector3(x - 0.012, -0.27, 0.16), Vector3(x + 0.012, 0.27, 1.16), "panel_dark" if j % 2 == 0 else "copper")
		for ty: float in [-0.24, 0.24]:
			for tz: float in [0.2, 1.1]:
				k.tube(Vector3(-0.35, ty, tz), Vector3(0.35, ty, tz), 0.012, "chrome", 6)
		# oxygen (green) and hydrogen (red) outlets
		k.tube(Vector3(-0.12, 0.0, 1.22), Vector3(-0.12, 0.0, 1.55), 0.03, "steel", 10)
		k.band(Vector3(-0.12, 0.0, 1.42), 0.03, "green", "z", 0.06)
		k.tube(Vector3(0.12, 0.0, 1.22), Vector3(0.12, 0.0, 1.55), 0.03, "steel", 10)
		k.band(Vector3(0.12, 0.0, 1.42), 0.03, "red", "z", 0.06)
		k.cyl(Vector3(-0.12, 0.0, 1.6), 0.07, 0.12, "white", "z", 14)
		k.cyl(Vector3(0.12, 0.0, 1.6), 0.07, 0.12, "white", "z", 14)
		k.span(Vector3(-0.17, 0.33, 1.25), Vector3(0.17, 0.37, 1.45), "panel")
		k.screen(Vector3(0.0, 0.37, 1.35), 0.24, 0.13, Screen.POWER, 0.4 + i, 0.012)
		k.label("WATER SPLITTER %d" % (i + 1), Vector3(0.0, 0.352, 1.08), 0.0014)
	# water loop: in front at the bottom, up both ends, back over the stacks
	k.at(0.0, 0.0).named("water loop")
	var loop := [Vector3(34.9, 6.28, 1.8), Vector3(34.9, 6.28, 0.3), Vector3(35.1, 6.28, 0.3), Vector3(35.1, 8.17, 0.3), Vector3(34.9, 8.17, 0.3), Vector3(34.9, 8.17, 1.8), Vector3(34.9, 6.28, 1.8)]
	k.pipe(loop, 0.035, "blue")
	for i in 4:
		k.band(Vector3(35.1, 6.6 + i * 0.45, 0.3), 0.035, "led_cyan", "y", 0.03)
	# circulation pump between the stacks, fed from the front run
	k.at(34.65, 7.22, 0.0, -PI * 0.5).named("water pump")
	k.span(Vector3(-0.1, -0.25, 0.0), Vector3(0.1, 0.25, 0.08), "frame")
	k.cyl(Vector3(0.0, 0.0, 0.25), 0.09, 0.3, "blue", "y", 16)
	k.cyl(Vector3(0.0, -0.17, 0.25), 0.07, 0.06, "steel", "y", 16)
	k.tube(Vector3(0.0, 0.15, 0.25), Vector3(0.0, 0.45, 0.3), 0.03, "blue", 10)
	k.at(35.17, 7.22, 0.0, -PI * 0.5)
	k.label("WATER LOOP", Vector3(0.0, 0.0, 0.42), 0.0016, Color(0.6, 0.85, 1.0))
	commit(k, s)


# ---------------------------------------------------------------- V4

## Three tanks on the north wall (x 38.57..40.43) on a header with valves.
func _tank_bank(s: Node3D) -> void:
	var k := Kit.new("TankBank", 39.5, 9.3, 0.0, "floor")
	var tanks := [["green", "O2"], ["frame", "N2"], ["blue", "H2O"]]
	for i in 3:
		_tank(k, 38.86 + i * 0.64, 9.47, 0.29, 1.75, tanks[i][0], tanks[i][1])
	k.at(0.0, 0.0).named("tank header")
	k.pipe([Vector3(38.6, 9.08, 1.25), Vector3(40.42, 9.08, 1.25)], 0.03, "steel")
	for i in 3:
		var x := 38.86 + i * 0.64
		k.tube(Vector3(x, 9.08, 1.25), Vector3(x, 9.19, 1.25), 0.025, "steel", 8)
		k.cyl(Vector3(x, 9.08, 1.31), 0.022, 0.08, "steel", "z", 8)
		k.span(Vector3(x - 0.07, 9.07, 1.35), Vector3(x + 0.07, 9.09, 1.37), "red")
	commit(k, s)


## Filter bank north of the scrubber (x 38.95..40.25, y 5.35..5.85), gauges to the north.
func _filter_bank(s: Node3D) -> void:
	var k := Kit.new("FilterBank", 39.6, 5.6, 0.0, "floor")
	k.at(39.6, 5.6, 0.0, 0.0).named("filter bank")             # front north, local x = east
	k.span(Vector3(-0.65, -0.25, 0.0), Vector3(0.65, 0.25, 0.1), "frame")
	k.pipe([Vector3(-0.62, 0.0, 0.22), Vector3(0.62, 0.0, 0.22)], 0.035, "steel")
	k.pipe([Vector3(-0.62, 0.0, 1.32), Vector3(0.62, 0.0, 1.32)], 0.035, "steel")
	for i in 4:
		var x := -0.45 + i * 0.3
		k.lathe(Vector3(x, 0.0, 0.1), [Vector2(0.1, 0.0), Vector2(0.11, 0.05), Vector2(0.11, 1.0), Vector2(0.13, 1.02), Vector2(0.13, 1.12), Vector2(0.0, 1.14)], "white", "z", 16)
		k.cyl(Vector3(x, 0.0, 1.17), 0.135, 0.06, "blue", "z", 16)
		k.cyl(Vector3(x, 0.12, 0.85), 0.04, 0.02, "steel", "y", 12)
		k.cyl(Vector3(x, 0.132, 0.85), 0.03, 0.004, "white", "y", 12)
		k.led(Vector3(x, 0.112, 0.62), Vector3(0.03, 0.01, 0.03), "led_green")
	k.label("FILTER BANK", Vector3(0.0, 0.14, 1.45), 0.0016)
	commit(k, s)


## Labelled overhead pipes: oxygen from the electrolysers (outlets at y 6.84 / 7.85) and air from the filter bank to the tank header.
func _plant_pipes(s: Node3D) -> void:
	var k := Kit.new("PlantPipes", 38.0, 8.4, 2.0, "ceiling")
	k.at(0.0, 0.0).named("labelled pipes")
	# electrolyser O2 outlets up to z 2.4, along y 8.4 east, down into the header at x 38.6
	k.pipe([Vector3(34.65, 6.84, 1.66), Vector3(34.65, 6.84, 2.4), Vector3(34.65, 8.4, 2.4), Vector3(38.6, 8.4, 2.4), Vector3(38.6, 9.08, 2.4), Vector3(38.6, 9.08, 1.28)], 0.03, "white")
	k.tube(Vector3(34.65, 7.85, 1.66), Vector3(34.65, 7.85, 2.4), 0.03, "white")
	for x: float in [35.6, 36.6, 37.6]:
		k.band(Vector3(x, 8.4, 2.4), 0.03, "green", "x", 0.1)
	# filter bank top manifold up and north along x 40.45 into the header's east end
	k.pipe([Vector3(39.6, 5.6, 1.36), Vector3(39.6, 5.6, 2.3), Vector3(40.45, 5.6, 2.3), Vector3(40.45, 9.08, 2.3), Vector3(40.45, 9.08, 1.28)], 0.03, "white")
	for y: float in [6.4, 7.4, 8.4]:
		k.band(Vector3(40.45, y, 2.3), 0.03, "blue", "y", 0.1)
	# hanger rods to the plain ceiling tiles (underside 3.12) at x 36.32..37.77 and 40.32..41.77
	k.named("hanger rod")
	for p: Vector3 in [Vector3(36.6, 8.4, 2.43), Vector3(37.6, 8.4, 2.43), Vector3(40.45, 6.8, 2.33), Vector3(40.45, 8.2, 2.33)]:
		k.tube(p, Vector3(p.x, p.y, 3.12), 0.008, "steel", 6)
	# labels facing south (into the room)
	k.at(36.6, 8.36, 0.0, PI)
	k.label("OXYGEN TO TANKS", Vector3(0.0, 0.0, 2.3), 0.0016, Color(0.6, 1.0, 0.65))
	k.at(40.45, 7.0, 0.0, PI * 0.5)
	k.label("CLEAN AIR", Vector3(0.0, 0.04, 2.2), 0.0016, Color(0.6, 0.85, 1.0))
	commit(k, s)
