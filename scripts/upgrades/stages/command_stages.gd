extends "res://scripts/upgrades/stages/room_parts.gd"
## Look of the "command" upgrade path (data/area_levels.json): the Command Room, plus a dish on its roof.
##   V1  today's room (nothing built).
##   V2  a wide colony map screen on the south wall above the operators' chairs: the rooms, the dome, the garden dome
##       and both solar fields, with blinking room lights and a "you are here" ping on this room.
##   V3  + a relay rack in the north-east corner (beside the room's racks) and a second row of screens on a bridge
##       behind the console row, facing the operators.
##   V4  + a full screen wall round the map with a news ticker on top, a holo table (the plot table gets emitters, a
##       glass top and a floating colony hologram), and a dish link on the roof.
## Places were measured on the map (tools/blender/room_stages/dump_rooms.py): screens stay above the chair backs
## (z 1.42) and beside the doors; the rack stays off the comms console's standing spot (32.55, 15.6).

const WALL_Y := 10.2           # inner face of the south wall
const ROOF_Z := 3.17           # top of the roof slabs over the room


func track_id() -> String:
	return "command"


func build_stage(level: int) -> Node3D:
	if level <= 1:
		return null
	var s := new_stage()
	_screen_wall(s, level)
	if level >= 3:
		_relay_rack(s)
		_monitor_bridge(s)
	if level >= 4:
		_holo_table(s)
		_roof_dish(s)
	return s


# ---------------------------------------------------------------- V2 / V4: the south wall

func _screen_wall(s: Node3D, level: int) -> void:
	var k := Kit.new("ScreenWall", 30.85, 10.6, 0.0, "wall")
	k.at(30.5, WALL_Y, 0.0, 0.0).named("colony map")              # front faces north
	k.span(Vector3(-1.62, 0.0, 1.81), Vector3(1.62, 0.02, 1.84), "orange")
	k.screen(Vector3(0, 0.0, 2.29), 3.0, 0.88, Screen.COLONY_MAP, 0.0, 0.06)
	if level < 4:
		for sx: float in [-1.0, 1.0]:
			k.span(Vector3(sx * 1.55 - 0.02, 0.0, 1.85), Vector3(sx * 1.55 + 0.02, 0.03, 2.74), "steel")
			k.led(Vector3(sx * 1.55, 0.035, 2.66), Vector3(0.02, 0.01, 0.02), "led_green")
	k.label("COLONY MAP", Vector3(-1.2, 0.025, 1.86), 0.0012, Color(1.0, 0.9, 0.8))
	if level >= 4:
		k.named("screen wall")
		# left column (x 28.1..28.95) and right block (x 32.05..33.62), two rows each
		var modes := [Screen.DATA, Screen.TEXT]
		k.at(28.525, WALL_Y, 0.0, 0.0)
		for r in 2:
			k.screen(Vector3(0, 0.0, 2.06 + r * 0.45), 0.78, 0.4, modes[r], 0.3 + r, 0.05)
		k.at(32.84, WALL_Y, 0.0, 0.0)
		var right := [Screen.RADAR, Screen.DATA, Screen.TEXT, Screen.POWER]
		for r in 2:
			for c in 2:
				k.screen(Vector3(-0.385 + c * 0.77, 0.0, 2.06 + r * 0.45), 0.72, 0.4, right[r * 2 + c], 0.6 + r + c * 0.3, 0.05)
		# ticker across the whole wall
		k.at(30.86, WALL_Y, 0.0, 0.0)
		k.screen(Vector3(0, 0.0, 2.85), 5.45, 0.11, Screen.TEXT, 0.9, 0.04)
		k.span(Vector3(-2.76, 0.0, 1.81), Vector3(2.76, 0.03, 1.84), "glow_strip")
	commit(k, s)


# ---------------------------------------------------------------- V3

## Relay rack continuing the room's rack row in the north-east corner, front to the south.
func _relay_rack(s: Node3D) -> void:
	var k := Kit.new("RelayRack", 33.31, 17.0, 0.0, "floor")
	k.at(33.31, 17.38, 0.0, PI).named("relay rack")
	var d := 0.8
	var f := d * 0.5
	k.cabinet(Vector3.ZERO, 0.62, d, 2.6, "panel_dark", "frame", 1)
	k.span(Vector3(-0.31, f - 0.01, 2.44), Vector3(0.31, f + 0.014, 2.54), "orange")
	var leds := ["led_green", "led_blue", "led_green", "led_amber", "led_green", "led_cyan"]
	for u in 11:
		var z := 0.3 + u * 0.17
		k.span(Vector3(-0.26, f, z), Vector3(0.26, f + 0.02, z + 0.14), "frame")
		for i in 6:
			if (u * 7 + i * 3) % 5 != 0:
				k.led(Vector3(-0.2 + i * 0.05, f + 0.024, z + 0.1), Vector3(0.02, 0.008, 0.012), leds[(u + i) % leds.size()])
		k.span(Vector3(0.12, f + 0.02, z + 0.03), Vector3(0.24, f + 0.026, z + 0.06), "steel")
	# patch cables looping between units
	var cols := ["blue", "yellow", "orange", "teal"]
	for i in 4:
		var z0 := 0.45 + i * 0.42
		k.tube(Vector3(0.18, f + 0.03, z0), Vector3(0.28, f + 0.07, z0 + 0.1), 0.008, cols[i], 5)
		k.tube(Vector3(0.28, f + 0.07, z0 + 0.1), Vector3(0.18, f + 0.03, z0 + 0.24), 0.008, cols[i], 5)
	k.screen(Vector3(0, f, 2.25), 0.4, 0.22, Screen.RADAR, 0.5, 0.02)
	k.label("RELAY", Vector3(0, f + 0.016, 2.49), 0.0016)
	commit(k, s)


## A bridge along the back of the console row (x 28.2..32.1, back face y 12.1) carrying four screens that face the
## operators' chairs. Its posts stand inside the consoles' back panels, so nothing reaches into the space behind them.
func _monitor_bridge(s: Node3D) -> void:
	var k := Kit.new("MonitorBridge", 30.15, 11.9, 0.0, "on:cr_console")
	k.at(0.0, 0.0).named("monitor bridge")
	for x: float in [28.32, 29.5, 30.8, 32.0]:
		k.span(Vector3(x - 0.03, 12.02, 0.0), Vector3(x + 0.03, 12.08, 1.95), "frame")
	k.span(Vector3(28.26, 12.0, 1.88), Vector3(32.06, 12.1, 1.95), "frame")
	k.span(Vector3(28.26, 11.995, 1.9), Vector3(32.06, 12.0, 1.93), "glow_strip")
	k.at(30.15, 12.0, 0.0, PI)                   # front faces south (local x = west)
	var modes := [Screen.DATA, Screen.TEXT, Screen.RADAR, Screen.DATA]
	for i in 4:
		var wx := 28.74 + i * 0.94
		k.screen(Vector3(30.15 - wx, 0.0, 1.66), 0.86, 0.4, modes[i], 0.2 + i * 0.7, 0.04, "frame", 0.08)
	commit(k, s)


# ---------------------------------------------------------------- V4

## The plot table (x 29.29..31.01, y 13.49..14.61, top 0.94) becomes a holo table: an emitter rim, a glass top,
## four emitter posts and a floating colony map in three layers, below the pendant lamp (z 2.2).
func _holo_table(s: Node3D) -> void:
	var cx := 30.15
	var cy := 14.05
	var top := 0.94
	var k := Kit.new("HoloTable", cx, cy, top, "on:cr_plot_table")
	k.at(cx, cy, 0.0).named("holo table")
	var hx := 0.82
	var hy := 0.52
	k.span(Vector3(-hx, -hy, top), Vector3(hx, -hy + 0.04, top + 0.035), "frame")
	k.span(Vector3(-hx, hy - 0.04, top), Vector3(hx, hy, top + 0.035), "frame")
	k.span(Vector3(-hx, -hy + 0.04, top), Vector3(-hx + 0.04, hy - 0.04, top + 0.035), "frame")
	k.span(Vector3(hx - 0.04, -hy + 0.04, top), Vector3(hx, hy - 0.04, top + 0.035), "frame")
	k.span(Vector3(-hx + 0.005, -hy + 0.04, top + 0.03), Vector3(hx - 0.005, -hy + 0.05, top + 0.04), "led_cyan")
	k.span(Vector3(-hx + 0.005, hy - 0.05, top + 0.03), Vector3(hx - 0.005, hy - 0.04, top + 0.04), "led_cyan")
	k.span(Vector3(-hx + 0.04, -hy + 0.04, top + 0.005), Vector3(hx - 0.04, hy - 0.04, top + 0.015), "glass")
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			k.cyl(Vector3(sx * (hx - 0.08), sy * (hy - 0.08), top + 0.06), 0.035, 0.05, "steel", "z", 12)
			k.cyl(Vector3(sx * (hx - 0.08), sy * (hy - 0.08), top + 0.09), 0.025, 0.012, "led_cyan", "z", 12)
	k.named("hologram")
	k.lathe(Vector3(0, 0, top + 0.04), [Vector2(0.1, 0.0), Vector2(0.5, 0.62)], "holo:%d" % Screen.BEAM, "z", 24)
	k.holo_plane(Vector3(0, 0, top + 0.22), 1.5, 0.92, Screen.COLONY_MAP, 0.1)
	k.holo_plane(Vector3(0, 0, top + 0.42), 1.2, 0.74, Screen.COLONY_MAP, 0.4)
	k.holo_plane(Vector3(0, 0, top + 0.62), 0.9, 0.55, Screen.COLONY_MAP, 0.7)
	k.light(Vector3(0, 0, top + 0.5), Vector3(0, 0, -1), Color(0.35, 0.85, 1.0), 0.6, 2.5, false)
	commit(k, s)


## Dish link on the roof (outdoors), north-east of the roof vents, aimed up to the south-west.
func _roof_dish(s: Node3D) -> void:
	var x := 32.4
	var y := 16.4
	var k := Kit.new("RoofDish", x, y, ROOF_Z, "roof")
	k.outdoor = true
	k.at(x, y, ROOF_Z, PI * 0.75).named("roof dish")
	k.span(Vector3(-0.38, -0.38, 0.0), Vector3(0.38, 0.38, 0.06), "steel")
	for sx: float in [-0.3, 0.3]:
		for sy: float in [-0.3, 0.3]:
			k.cyl(Vector3(sx, sy, 0.075), 0.022, 0.03, "frame", "z", 8)
	k.lathe(Vector3(0, 0, 0.06), [Vector2(0.16, 0.0), Vector2(0.11, 0.12), Vector2(0.08, 0.95), Vector2(0.11, 1.0), Vector2(0.11, 1.06)], "white", "z", 16)
	k.cyl(Vector3(0, 0, 1.12), 0.16, 0.08, "frame", "z", 18)
	for sx: float in [-1.0, 1.0]:
		k.span(Vector3(sx * 0.2 - 0.03, -0.06, 1.12), Vector3(sx * 0.2 + 0.03, 0.06, 1.5), "steel")
	k.cyl(Vector3(0, 0, 1.45), 0.05, 0.46, "steel", "x", 12)
	# dish: a shallow bowl tilted 50 degrees towards the front
	var tb := Basis(Vector3(1, 0, 0), deg_to_rad(-50.0))
	var c := Vector3(0, 0.05, 1.45)
	var prof: Array = []
	for i in 7:
		var r := 0.8 * float(i) / 6.0
		prof.append(Vector2(r, r * r / 1.8))
	k.lathe(c, prof, "white", "z", 28, tb)
	k.lathe(c - tb * Vector3(0, 0, 0.03), [Vector2(0.0, 0.0), Vector2(0.2, 0.0), Vector2(0.2, 0.03)], "frame", "z", 16, tb)
	var focus := c + tb * Vector3(0, 0, 0.45)
	for i in 3:
		var a := TAU * float(i) / 3.0
		k.tube(c + tb * Vector3(cos(a) * 0.7, sin(a) * 0.7, 0.27), focus, 0.012, "steel", 6)
	k.lathe(focus - tb * Vector3(0, 0, 0.06), [Vector2(0.05, 0.0), Vector2(0.035, 0.12)], "frame", "z", 12, tb)
	k.lathe(focus + tb * Vector3(0, 0, 0.06), [Vector2(0.0, 0.0), Vector2(0.025, 0.0), Vector2(0.025, 0.04), Vector2(0.0, 0.05)], "led_red", "z", 10, tb)
	commit(k, s)
