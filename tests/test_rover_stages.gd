extends SceneTree
## Rover upgrade look (worker ROVER, 2026-11-14): scripts/upgrades/stages/rover_stages.gd. Headless.
##   1. parts: every module level changes that module's parts (and only those), the stock rover adds nothing, one mesh
##      per build with few surfaces, no collision anywhere in a build
##   2. V level: AreaLevels.rover_level mapping, the presenter's level, rank bars, V3 and V4 gear
##   3. the game scene WITHOUT the map and WITH the map: parts ride on RoverBody, rebuild on a module change that keeps
##      the V level, follow the body when it moves, keep the rover mesh's render layers, add no collision and change
##      no mass
## Run: godot --headless --path . --script res://tests/test_rover_stages.gd [-- --no-map]

const RoverStages := preload("res://scripts/upgrades/stages/rover_stages.gd")
const SAVE_DIR := "_test_saves/test_rover_stages"


class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR or error_type == ERROR_TYPE_SCRIPT:
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _passed := 0
var _total := 0
var _catcher := ErrorCatcher.new()


func _check(label: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		print("FAIL %s: %s" % [label, detail])


func _initialize() -> void:
	OS.add_logger(_catcher)
	_run.call_deferred()


func _run() -> void:
	PlayerInput.ensure_actions()
	_parts_checks()
	_level_checks()
	await _game_checks(false)
	if not OS.get_cmdline_user_args().has("--no-map"):
		await _game_checks(true)
	_check("clean run: the engine error log stayed empty", _catcher.errors.is_empty(), "\n".join(_catcher.errors.slice(0, 10)))
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


static func _levels(speed := 1, torque := 1, range_level := 1, cargo := 1, traction := 1) -> Dictionary:
	return {"speed": speed, "torque": torque, "range": range_level, "cargo": cargo, "traction": traction}


static func _counts(n: Node3D) -> Dictionary:
	return n.get_meta(&"part_counts", {}) if n != null else {}


static func _colliders(n: Node) -> int:
	var c := 1 if (n is CollisionObject3D or n is CollisionShape3D or n is CollisionPolygon3D) else 0
	for child in n.get_children():
		c += _colliders(child)
	return c


static func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for child in n.get_children():
		out.append_array(_meshes(child))
	return out


# ---------------------------------------------------------------- 1. parts

func _parts_checks() -> void:
	_check("stock rover (every module 1, V1) adds no parts", RoverStages.build_parts(_levels(), 1) == null)
	for m: String in RoverStages.MODULES:
		var prev := 0
		var grows := true
		var only := true
		var lines := PackedStringArray()
		for lvl in range(1, 6):
			var lv := _levels()
			lv[m] = lvl
			var node := RoverStages.build_parts(lv, 1)       # V1: no rank or V gear, only the module itself
			var counts := _counts(node)
			var n := int(counts.get(m, 0))
			lines.append("L%d=%d" % [lvl, n])
			if lvl == 1 and n != 0 or lvl > 1 and n <= prev and m != "cargo":
				grows = false
			if m == "cargo" and lvl > 1 and n == prev:
				grows = false
			for g: String in counts:
				if g != m:
					only = false
			prev = n
			if node != null:
				node.free()
		_check("%s: every level 2..5 shows more/different %s parts" % [m, m], grows, " ".join(lines))
		_check("%s: its levels change only its own parts" % m, only)
	# cargo 5 is a different look (closed pods) from the racks of 4
	var rack := RoverStages.build_parts(_levels(1, 1, 1, 4), 1)
	var pod := RoverStages.build_parts(_levels(1, 1, 1, 5), 1)
	var rack_mats := _surface_names(rack)
	var pod_mats := _surface_names(pod)
	_check("cargo 4 is racks with crates, cargo 5 closed pods", rack_mats.has("rover_crate") and not pod_mats.has("rover_crate") and pod_mats.has("rover_paint"),
		"%s / %s" % [rack_mats, pod_mats])
	rack.free()
	pod.free()
	var full := RoverStages.build_parts(_levels(5, 5, 5, 5, 5), 4)
	var meshes := _meshes(full)
	var surfaces := (meshes[0].mesh as ArrayMesh).get_surface_count() if meshes.size() == 1 else -1
	_check("a full build is ONE mesh with few surfaces (draw calls)", meshes.size() == 1 and surfaces > 0 and surfaces <= 12, "%d meshes, %d surfaces" % [meshes.size(), surfaces])
	_check("a full build has no collision shape or body", _colliders(full) == 0)
	var aabb := meshes[0].get_aabb() if meshes.size() == 1 else AABB()
	_check("the parts stay close round the rover: under 1.8 m from the centre line (garage door is 1.9), lugs at most 12 cm into the ground", aabb.position.y > -0.12 and aabb.end.y < 4.6 and absf(aabb.position.x) < 1.8 and aabb.end.x < 1.8
		and aabb.position.z > -2.8 and aabb.end.z < 2.6, str(aabb))
	full.free()


static func _surface_names(n: Node3D) -> PackedStringArray:
	var out := PackedStringArray()
	for mi in _meshes(n):
		var am := mi.mesh as ArrayMesh
		for i in am.get_surface_count():
			out.append(am.surface_get_name(i))
	return out


# ---------------------------------------------------------------- 2. V level

func _level_checks() -> void:
	_check("V mapping: stock V1, one step V2, 4 steps V2, 5 steps V3, 11 steps V3, 12 steps V4, all 5 V4",
		AreaLevels.rover_level(_levels()) == 1 and AreaLevels.rover_level(_levels(2)) == 2 and AreaLevels.rover_level(_levels(2, 2, 2, 2)) == 2
		and AreaLevels.rover_level(_levels(2, 2, 2, 2, 2)) == 3 and AreaLevels.rover_level(_levels(3, 3, 3, 3, 2)) == 3
		and AreaLevels.rover_level(_levels(4, 4, 3, 3, 3)) == 4 and AreaLevels.rover_level(_levels(5, 5, 5, 5, 5)) == 4)
	var p := RoverStages.new() as AreaStagePresenter
	p.set("force_modules", _levels(3, 3, 3, 3, 2))
	_check("presenter level follows the modules (forced: V3)", p.current_level() == 3)
	p.free()
	var rank := []
	var v3 := []
	var v4 := []
	for v in range(1, 5):
		var node := RoverStages.build_parts(_levels(2), v)
		var c := _counts(node)
		rank.append(int(c.get("rank", 0)))
		v3.append(int(c.get("v3", 0)))
		v4.append(int(c.get("v4", 0)))
		node.free()
	_check("rank bars: none at V1, more at each V level", rank[0] == 0 and rank[1] > 0 and rank[2] > rank[1] and rank[3] > rank[2], str(rank))
	_check("V3 adds the light bar and antenna mast (from V3 on)", v3[0] == 0 and v3[1] == 0 and v3[2] > 0 and v3[3] > 0, str(v3))
	_check("V4 adds dust guards and the roll cage (V4 only)", v4[0] == 0 and v4[1] == 0 and v4[2] == 0 and v4[3] > 0, str(v4))
	var words := AreaLevels.stage_text("rover", 4)
	_check("the rover's stage words name the V4 look", words.begins_with("V4") and words.length() > 6, words)


# ---------------------------------------------------------------- 3. in the game scene

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _game_checks(with_map: bool) -> void:
	var tag := "with map" if with_map else "no map"
	var dir := ProjectSettings.globalize_path("res://").path_join(SAVE_DIR).path_join("map" if with_map else "nomap")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	var main := (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.load_world = with_map
	main.show_menu = false
	main.save_directory = dir
	root.add_child(main)
	for i in 5:
		await process_frame
	var p := main.area_stages.get("rover") as AreaStagePresenter
	var rover := main.rover
	_check("[%s] game built the rover look presenter and the rover" % tag, p != null and rover != null and rover.body != null)
	if p == null or rover == null or rover.body == null:
		main.queue_free()
		return
	var body := rover.body
	_check("[%s] the map rover mesh is drawn on the body (%s)" % [tag, "expected" if with_map else "not expected"], (body.visual() != null) == with_map)
	var st := main.services.state()
	await _wait(0.7)
	_check("[%s] stock rover: no parts on the body" % tag, p.stage_node() == null and p.shown_level == 1)
	var shapes0 := _colliders(body)
	st.rover["levels"] = _levels(2, 2, 2, 2, 2)                 # V3
	await _wait(0.7)
	var stage := p.stage_node()
	_check("[%s] parts appear on a module upgrade, at the derived V level" % tag, stage != null and p.shown_level == 3 and AreaLevels.level(st, "rover") == 3)
	_check("[%s] parts ride on the moving rover body" % tag, stage != null and stage.get_parent() == body and p.stage_parent() == body)
	var first := _counts(stage)
	var first_id := stage.get_instance_id() if stage != null else 0
	st.rover["levels"] = _levels(2, 2, 3, 2, 2)                 # one module up, still V3
	await _wait(0.7)
	var stage2 := p.stage_node()
	var second := _counts(stage2)
	_check("[%s] a module change that keeps V3 still rebuilds the parts" % tag, stage2 != null and stage2.get_instance_id() != first_id and p.shown_level == 3
		and int(second.get("range", 0)) > int(first.get("range", 0)) and int(second.get("speed", 0)) == int(first.get("speed", 0)), "%s -> %s" % [first, second])
	_check("[%s] no collision added to the rover body" % tag, _colliders(body) == shapes0 and _colliders(stage2) == 0, "%d -> %d" % [shapes0, _colliders(body)])
	# the presenter never changes mass: hold the colony state still and force bigger parts
	var mass0 := body.mass
	p.set("force_modules", _levels(5, 5, 5, 5, 5))
	p.refresh()
	await _wait(0.4)
	_check("[%s] bigger parts change no mass (mass lives in RoverBalance)" % tag, is_equal_approx(body.mass, mass0) and p.shown_level == 4, "%.1f -> %.1f kg" % [mass0, body.mass])
	# follow the body when it moves
	var to := body.global_transform.translated(Vector3(6.0, 0.0, -4.0)).rotated_local(Vector3.UP, 0.7)
	body.global_transform = to
	var parts := p.stage_node()
	_check("[%s] parts follow the body when it moves and turns" % tag, parts != null and parts.global_position.distance_to(body.global_position) < 1e-3
		and parts.global_basis.z.normalized().distance_to(body.global_basis.z.normalized()) < 1e-3)
	# render layers follow the rover's own mesh (the zone it is drawn in), checked at the next poll
	await _wait(0.7)
	parts = p.stage_node()
	var mesh_layers := p.call("body_layers") as int
	var ok := mesh_layers != 0
	for mi in _meshes(parts):
		ok = ok and mi.layers == mesh_layers
	_check("[%s] parts are on the rover mesh's render layers" % tag, ok, "mask %d" % mesh_layers)
	if with_map:
		var vis := body.visual() as VisualInstance3D
		if vis == null and body.visual() != null:
			vis = body.visual().find_children("*", "VisualInstance3D", true, false)[0] as VisualInstance3D
		var old := vis.layers
		var zones := main.services.zones
		var other := zones.bit_of(ColonyZones.PLAZA) | zones.sun_bit()
		vis.layers = other                      # as if the rover's own mesh had moved to another zone's layers
		await _wait(0.7)
		var follow := true
		for mi in _meshes(p.stage_node()):
			follow = follow and mi.layers == other
		_check("[with map] when the rover mesh changes layers (another zone) the parts follow", follow and other != old, "%d -> %d" % [old, other])
		vis.layers = old
	# back to stock: the parts go
	p.set("force_modules", {})
	st.rover["levels"] = _levels()
	await _wait(0.7)
	_check("[%s] back to stock modules removes the parts" % tag, p.stage_node() == null and p.shown_level == 1)
	main.queue_free()
	for i in 3:
		await process_frame
