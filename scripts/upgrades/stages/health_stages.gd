extends "res://scripts/upgrades/stages/room_parts.gd"
## Look of the "health" upgrade path (data/area_levels.json): the Med Bay. Each step is meant to be obvious at a glance
## (owner, 2026-11-14: health upgrades must show clear visual changes).
##   V1  today's room (nothing built).
##   V2  vitals monitors: a big wall monitor above the bed next to the heal station, with glowing heart, oxygen and
##       breathing traces, and an IV stand by that bed carrying a drip bag and a second, smaller vitals monitor.
##   V3  + a second treatment bed in the south-east corner (head to the east wall) and a body-scanner arch over it,
##       with a glowing ring and a scan screen.
##   V4  + a surgical light over the new bed, two wall screens at its head, and a treatment cabinet run (tall medicine
##       cabinet, drawers, a counter screen and supplies): a full treatment suite.
## Places were measured on the map (tools/blender/room_stages/dump_rooms.py). The new corner keeps clear of the door
## (x 0, y 12.5..13.5), the repair spot at (-2, 13.5), the respawn spot (-7.3, 14.5) and the desk chairs (y <= 10.12).

const BED_X := -1.395          # centre of the second bed (head at the east wall, x -0.2)
const BED_Y := 10.88


func track_id() -> String:
	return "health"


func build_stage(level: int) -> Node3D:
	if level <= 1:
		return null
	var s := new_stage()
	_wall_monitor(s)
	_iv_stand(s)
	if level >= 3:
		_second_bed(s)
		_scanner_arch(s)
	if level >= 4:
		_surgical_light(s)
		_wall_screens(s)
		_cabinets(s)
	return s


# ---------------------------------------------------------------- V2

## Big vitals monitor on an arm above the head of the bed beside the heal station (bed x -7.06..-6.04).
func _wall_monitor(s: Node3D) -> void:
	var k := Kit.new("VitalsMonitor", -6.55, 17.5, 0.0, "wall")
	k.at(-6.55, 17.8, 0.0, PI).named("vitals monitor")       # front faces south, local y from the wall face
	k.span(Vector3(-0.08, 0.005, 2.36), Vector3(0.08, 0.02, 2.56), "steel")          # wall plate
	k.span(Vector3(-0.025, 0.02, 2.44), Vector3(0.025, 0.13, 2.48), "steel")         # arm
	k.screen(Vector3(0, 0.13, 2.53), 0.6, 0.38, Screen.VITALS, 0.11, 0.05, "frame", -0.15)
	k.led(Vector3(0.27, 0.19, 2.315), Vector3(0.03, 0.01, 0.015), "led_green")
	commit(k, s)


## IV stand left of the bed: five-leg base on casters, pole, hooks, a drip bag with its line, and a small pole monitor.
func _iv_stand(s: Node3D) -> void:
	var x := -7.33
	var y := 15.95
	var k := Kit.new("IVStand", x, y, 0.0, "floor")
	k.at(x, y, 0.0, PI * 0.85).named("IV stand")
	for i in 5:
		var a := TAU * float(i) / 5.0
		var tip := Vector3(cos(a) * 0.19, sin(a) * 0.19, 0.07)
		k.tube(Vector3(0, 0, 0.1), tip, 0.012, "steel", 6)
		k.cyl(tip - Vector3(0, 0, 0.035), 0.025, 0.05, "rubber", "z", 8)
	k.cyl(Vector3(0, 0, 0.1), 0.035, 0.06, "steel")
	k.cyl(Vector3(0, 0, 1.08), 0.012, 1.95, "chrome", "z", 8)
	k.tube(Vector3(-0.14, 0, 2.02), Vector3(0.14, 0, 2.02), 0.008, "chrome", 6)
	k.tube(Vector3(0, -0.14, 2.02), Vector3(0, 0.14, 2.02), 0.008, "chrome", 6)
	# drip bag, drip chamber and line towards the bed
	k.named("drip bag").box(Vector3(0.12, 0.0, 1.86), Vector3(0.11, 0.035, 0.2), "fluid")
	k.cyl(Vector3(0.12, 0.0, 1.71), 0.012, 0.06, "glass", "z", 8)
	# the line runs from under the drip chamber to the edge of the bed (x -7.06)
	var yaw := PI * 0.85
	var dx := 0.12 * cos(yaw)
	var dy := 0.12 * sin(yaw)
	k.at(0.0, 0.0).named("IV line")
	k.tube(Vector3(x + dx, y + dy, 1.68), Vector3(-7.18, 16.2, 1.1), 0.004, "glass", 5)
	k.tube(Vector3(-7.18, 16.2, 1.1), Vector3(-7.09, 16.35, 0.82), 0.004, "glass", 5)
	# pole monitor, facing the room
	k.at(x, y, 0.0, PI * 0.85).named("pole monitor")
	k.span(Vector3(-0.03, -0.02, 1.28), Vector3(0.03, 0.03, 1.36), "steel")
	k.screen(Vector3(0, 0.03, 1.38), 0.3, 0.22, Screen.VITALS, 0.53, 0.04, "frame", 0.1)
	commit(k, s)


# ---------------------------------------------------------------- V3

## Second treatment bed, head to the east wall.
func _second_bed(s: Node3D) -> void:
	var k := Kit.new("SecondBed", BED_X, BED_Y, 0.0, "floor")
	k.at(BED_X, BED_Y, 0.0, -PI * 0.5).named("second bed")    # local +y = head (east), local +x = south
	for sx: float in [-0.36, 0.36]:
		for sy: float in [-0.92, 0.92]:
			k.cyl(Vector3(sx, sy, 0.05), 0.05, 0.04, "rubber", "x", 10)
			k.span(Vector3(sx - 0.015, sy - 0.015, 0.08), Vector3(sx + 0.015, sy + 0.015, 0.18), "steel")
	k.span(Vector3(-0.42, -1.0, 0.18), Vector3(0.42, 1.0, 0.36), "frame")
	k.span(Vector3(-0.44, -1.0, 0.36), Vector3(0.44, 1.0, 0.42), "steel")
	k.span(Vector3(-0.45, -0.98, 0.42), Vector3(0.45, 0.5, 0.58), "white")
	k.box(Vector3(0, 0.74, 0.6), Vector3(0.9, 0.5, 0.15), "white", Basis(Vector3.RIGHT, 0.38))
	k.box(Vector3(0, 0.86, 0.72), Vector3(0.55, 0.26, 0.09), "panel_warm", Basis(Vector3.RIGHT, 0.38))
	k.span(Vector3(-0.46, -0.96, 0.58), Vector3(0.46, 0.3, 0.62), "teal")
	k.span(Vector3(-0.46, 0.995, 0.3), Vector3(0.46, 1.055, 1.02), "panel_warm")      # headboard
	k.span(Vector3(-0.47, 0.99, 0.98), Vector3(0.47, 1.06, 1.05), "frame")
	k.span(Vector3(-0.46, -1.055, 0.3), Vector3(0.46, -0.995, 0.82), "panel_warm")    # footboard
	k.span(Vector3(-0.47, -1.06, 0.8), Vector3(0.47, -0.99, 0.86), "frame")
	for sx: float in [-0.47, 0.47]:
		k.tube(Vector3(sx, -0.2, 0.78), Vector3(sx, 0.75, 0.78), 0.014, "chrome", 8)
		for sy: float in [-0.15, 0.7]:
			k.tube(Vector3(sx, sy, 0.6), Vector3(sx, sy, 0.78), 0.012, "chrome", 6)
	k.led(Vector3(0.3, -1.06, 0.6), Vector3(0.08, 0.012, 0.03), "led_green")
	commit(k, s)


## Body-scanner arch over the foot half of the bed: two pillars, a rounded hood, a glowing ring and a scan screen.
func _scanner_arch(s: Node3D) -> void:
	var k := Kit.new("ScannerArch", -1.96, BED_Y, 0.0, "floor")
	k.at(-1.96, BED_Y, 0.0, PI * 0.5).named("scanner arch")     # local +y = west (towards the room), local +x = north
	var d := 0.28
	for sx: float in [-1.0, 1.0]:
		var xo := sx * 0.62
		k.span(Vector3(xo - 0.07, -d * 0.5 - 0.04, 0.0), Vector3(xo + 0.07, d * 0.5 + 0.04, 0.06), "frame")
		k.span(Vector3(xo - 0.06, -d * 0.5, 0.06), Vector3(xo + 0.06, d * 0.5, 1.52), "white")
		k.span(Vector3(xo - 0.065, -d * 0.5 - 0.005, 0.3), Vector3(xo + 0.065, d * 0.5 + 0.005, 0.34), "teal")
		k.span(Vector3(xo - sx * 0.062, -d * 0.5 + 0.03, 0.3), Vector3(xo - sx * 0.07, d * 0.5 - 0.03, 1.48), "glow_strip")
		k.box(Vector3(xo - sx * 0.05, 0.0, 1.56), Vector3(0.17, d, 0.17), "white", Basis(Vector3(0, 0, 1), sx * PI * 0.25))
	k.span(Vector3(-0.62, -d * 0.5, 1.56), Vector3(0.62, d * 0.5, 1.74), "white")
	k.span(Vector3(-0.56, -d * 0.5 + 0.03, 1.545), Vector3(0.56, d * 0.5 - 0.03, 1.56), "glow_strip")
	k.span(Vector3(-0.63, -d * 0.5 - 0.005, 1.66), Vector3(0.63, d * 0.5 + 0.005, 1.7), "teal")
	k.screen(Vector3(0.12, d * 0.5, 1.64), 0.42, 0.13, Screen.SCAN, 0.4, 0.02)
	for i in 3:
		k.led(Vector3(0.43 + i * 0.05, d * 0.5 + 0.005, 1.63), Vector3(0.025, 0.01, 0.025), "led_blue" if i < 2 else "led_green")
	k.label("BODY SCANNER", Vector3(-0.38, d * 0.5 + 0.012, 1.64), 0.0011)
	commit(k, s)


# ---------------------------------------------------------------- V4

## Surgical light on a ceiling arm over the middle of the new bed, with a real spotlight.
func _surgical_light(s: Node3D) -> void:
	var cx := -1.1
	var k := Kit.new("SurgicalLight", cx, BED_Y, 2.0, "ceiling")
	k.at(cx - 0.25, BED_Y + 0.2, 0.0).named("surgical light")
	k.cyl(Vector3(0, 0, 2.92), 0.14, 0.03, "white", "z", 20)
	k.cyl(Vector3(0, 0, 2.7), 0.045, 0.42, "white", "z", 12)
	k.cyl(Vector3(0, 0, 2.5), 0.06, 0.06, "steel", "z", 12)
	k.tube(Vector3(0, 0, 2.5), Vector3(0.25, -0.2, 2.36), 0.035, "white", 10)
	k.tube(Vector3(0.25, -0.2, 2.36), Vector3(0.25, -0.2, 2.24), 0.03, "steel", 10)
	k.at(cx, BED_Y, 0.0)
	k.lathe(Vector3(0, 0, 2.02), [Vector2(0.27, 0.0), Vector2(0.33, 0.05), Vector2(0.3, 0.13), Vector2(0.18, 0.2), Vector2(0.05, 0.22), Vector2(0.0, 0.22)], "white", "z", 28)
	k.cyl(Vector3(0, 0, 2.015), 0.27, 0.012, "led_white", "z", 28)
	for i in 6:
		var a := TAU * float(i) / 6.0
		k.cyl(Vector3(cos(a) * 0.15, sin(a) * 0.15, 2.006), 0.05, 0.008, "glow_strip", "z", 12)
	k.cyl(Vector3(0, 0, 2.0), 0.04, 0.03, "steel", "z", 10)
	k.light(Vector3(0, 0, 1.99), Vector3(0, 0, -1), Color(1.0, 0.97, 0.92), 2.2, 3.0, true)
	commit(k, s)


## Two screens on the east wall above the head of the new bed, and a gas outlet panel between them.
func _wall_screens(s: Node3D) -> void:
	var k := Kit.new("TreatmentScreens", -0.5, BED_Y, 0.0, "wall")
	k.at(-0.2, BED_Y, 0.0, PI * 0.5).named("treatment screens")   # front faces west, local +x = north
	k.screen(Vector3(-0.36, 0.0, 1.47), 0.6, 0.4, Screen.VITALS, 0.71, 0.04)
	k.screen(Vector3(0.36, 0.0, 1.47), 0.6, 0.4, Screen.SCAN, 0.29, 0.04)
	k.span(Vector3(-0.2, 0.0, 1.08), Vector3(0.2, 0.035, 1.2), "panel_warm")
	k.cyl(Vector3(-0.1, 0.045, 1.14), 0.025, 0.02, "green", "y", 10)
	k.cyl(Vector3(0.0, 0.045, 1.14), 0.025, 0.02, "yellow", "y", 10)
	k.cyl(Vector3(0.1, 0.045, 1.14), 0.025, 0.02, "blue", "y", 10)
	k.span(Vector3(-0.68, 0.0, 1.72), Vector3(0.68, 0.025, 1.745), "glow_strip")
	commit(k, s)


## Cabinet run north of the new bed, facing the room (its back to the bed): a tall glass-door medicine cabinet and low drawers with a counter screen.
func _cabinets(s: Node3D) -> void:
	var k := Kit.new("TreatmentCabinets", -2.65, 11.93, 0.0, "floor")
	k.at(-2.65, 11.93, 0.0, 0.0).named("treatment cabinets")     # front faces north (the room), local +x = east
	var d := 0.44
	var f := d * 0.5
	# tall medicine cabinet at the west end (x -3.55..-3.0)
	k.at(-2.65 - 0.625, 11.93, 0.0, 0.0)
	k.cabinet(Vector3.ZERO, 0.55, d, 1.85, "white", "frame", 2)
	k.span(Vector3(-0.24, f, 0.95), Vector3(0.24, f + 0.012, 1.75), "glass")
	for zz: float in [1.15, 1.45]:
		k.span(Vector3(-0.24, -f + 0.02, zz), Vector3(0.24, f - 0.02, zz + 0.015), "steel")
		for i in 4:
			k.cyl(Vector3(-0.18 + i * 0.12, 0.0, zz + 0.07), 0.03, 0.11, ["white", "orange", "blue", "green"][i], "z", 10)
	k.span(Vector3(-0.05, f + 0.01, 1.55), Vector3(0.05, f + 0.02, 1.6), "red")
	k.span(Vector3(-0.02, f + 0.01, 1.53), Vector3(0.02, f + 0.02, 1.62), "red")
	# low drawer run (x -3.0..-1.75)
	k.at(-2.65 + 0.275, 11.93, 0.0, 0.0)
	k.cabinet(Vector3.ZERO, 1.25, d, 0.9, "panel", "frame", 3)
	k.span(Vector3(-0.64, -f - 0.01, 0.9), Vector3(0.64, f + 0.02, 0.94), "panel_warm")
	for col in 3:
		for row in 3:
			var x := -0.42 + col * 0.42
			k.span(Vector3(x - 0.07, f + 0.012, 0.72 - row * 0.24), Vector3(x + 0.07, f + 0.03, 0.74 - row * 0.24), "steel")
	k.span(Vector3(-0.15, -0.1, 0.94), Vector3(0.15, 0.0, 0.96), "frame")
	k.span(Vector3(-0.02, -0.07, 0.96), Vector3(0.02, -0.03, 1.08), "frame")
	k.screen(Vector3(0.0, -0.05, 1.22), 0.5, 0.3, Screen.VITALS, 0.91, 0.03, "frame", 0.15)
	k.span(Vector3(0.3, -0.12, 0.94), Vector3(0.52, 0.08, 1.06), "white")
	k.span(Vector3(0.33, -0.09, 1.06), Vector3(0.49, 0.05, 1.12), "blue")
	k.span(Vector3(-0.55, -0.1, 0.94), Vector3(-0.35, 0.06, 1.02), "orange")
	k.label("TREATMENT", Vector3(0.0, f + 0.032, 0.83), 0.0016, Color(0.15, 0.2, 0.25))
	commit(k, s)
