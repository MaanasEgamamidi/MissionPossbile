class_name BenchmarkRoute
extends Node
## Debug-only benchmark route (added by PerfRig in debug builds; keys come through PerfHud):
##   Ctrl+8  record a waypoint (player position + camera yaw + pitch) and save the route
##   Ctrl+9  play the route back: 4 m/s, turning at most 90 degrees/s, player input off while it plays
##   Ctrl+0  spin test: camera yaw at 720 degrees/s for 5 s, then back, without moving
## The route is saved to res://perf/route.json when the project folder is writable (editor runs), else user://.
## A waypoint may carry an optional "open_door" door id: when reached, that door's ZoneDoor is told it is opening.
## Playback moves the body with PlayerController.teleport (no physics walk), so it measures rendering and the zone
## system, not the character controller.

signal finished(what: String)

const RES_PATH := "res://perf/route.json"
const USER_PATH := "user://perf_route.json"
const SPEED := 4.0
const TURN_DEG_S := 90.0
const SPIN_DEG_S := 720.0
const SPIN_S := 5.0

var game: Node
var waypoints: Array = []     # {p: [x,y,z], yaw, pitch, open_door?}
var mode := &"idle"           # idle | play | spin

var _i := 0
var _pos := Vector3.ZERO
var _yaw := 0.0
var _spin_t := 0.0
var _was_input := true


func setup(game_main: Node) -> void:
	game = game_main
	add_to_group(&"benchmark_route")
	load_route()


func _player() -> PlayerController:
	return game.get("player") if game != null else null


func on_key(keycode: int) -> void:
	match keycode:
		KEY_8:
			record()
		KEY_9:
			if mode == &"play":
				stop()
			else:
				play()
		KEY_0:
			if mode == &"spin":
				stop()
			else:
				spin()


func record() -> void:
	var p := _player()
	if p == null:
		return
	var rig := p.camera_rig()
	var pos := p.global_position
	waypoints.append({"p": [pos.x, pos.y, pos.z], "yaw": rig.yaw(), "pitch": rig.pitch()})
	save_route()
	print("BenchmarkRoute: waypoint %d at %s" % [waypoints.size(), pos])


func save_route() -> void:
	var text := JSON.stringify({"waypoints": waypoints}, "  ")
	var f := FileAccess.open(RES_PATH, FileAccess.WRITE)
	if f == null:
		f = FileAccess.open(USER_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func load_route() -> void:
	for path in [RES_PATH, USER_PATH]:
		if FileAccess.file_exists(path):
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Dictionary and (d as Dictionary).has("waypoints"):
				waypoints = d.waypoints
				return


func play() -> void:
	var p := _player()
	if p == null or waypoints.is_empty():
		return
	_was_input = p.input_enabled
	p.input_enabled = false
	_i = 0
	_pos = _wp_pos(0)
	_yaw = p.camera_rig().yaw()
	p.teleport(_pos, _yaw)
	mode = &"play"


func spin() -> void:
	var p := _player()
	if p == null:
		return
	_was_input = p.input_enabled
	p.input_enabled = false
	_spin_t = 0.0
	mode = &"spin"


func stop() -> void:
	var p := _player()
	if p != null:
		p.input_enabled = _was_input
	var was := String(mode)
	mode = &"idle"
	finished.emit(was)


func _wp_pos(i: int) -> Vector3:
	var a: Array = waypoints[i].p
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _process(delta: float) -> void:
	var p := _player()
	if p == null or mode == &"idle":
		return
	p.input_enabled = false
	var rig := p.camera_rig()
	if mode == &"spin":
		_spin_t += delta
		var dir := 1.0 if _spin_t <= SPIN_S else -1.0
		rig.add_look(deg_to_rad(SPIN_DEG_S) * delta * dir, 0.0)
		if _spin_t >= 2.0 * SPIN_S:
			stop()
		return
	# play
	var target := _wp_pos(_i)
	var to := target - _pos
	var step := SPEED * delta
	if to.length() <= step:
		_pos = target
		var wp: Dictionary = waypoints[_i]
		if wp.has("open_door"):
			for d in get_tree().get_nodes_in_group(&"zone_door"):
				var zd := d as ZoneDoor
				if zd.controller != null and zd.controller.door_id == int(wp.open_door):
					zd.set_open(true)
		_i += 1
		if _i >= waypoints.size():
			stop()
			return
	else:
		_pos += to.normalized() * step
	# turn toward the next waypoint's yaw at a capped rate
	var want := float(waypoints[mini(_i, waypoints.size() - 1)].yaw)
	_yaw = rig.yaw()
	var dyaw := wrapf(want - _yaw, -PI, PI)
	var max_turn := deg_to_rad(TURN_DEG_S) * delta
	p.teleport(_pos, _yaw + clampf(dyaw, -max_turn, max_turn))
