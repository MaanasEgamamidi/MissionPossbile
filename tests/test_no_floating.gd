extends SceneTree
## Owner request 2026-11-14: "I want no floating objects in game ... It shouldn't say T over it like before."
## In a new game's world: no text floating in the air (only the Label3Ds listed in ALLOWED, each mounted on something),
## no marker plates on the repair / cassette stations, and every room cassette and the Command Room tape deck rests on
## a real surface (downward rays from its underside hit collision within a few cm).

var passed := 0
var total := 0
var main: GameMain

## Every Label3D a new game may show, and why it is not floating.
const ALLOWED := {
	"AirlockHazardPresenter/AirlockPressureSign": "pressure sign printed on a board flat on the hangar wall",
	"CassetteModel/RoomLabel": "room name printed flat on each cassette's colour band",
	"NameTag/Symbol": "crew name tag carried with a crew member (scripts/player/player_visual.gd, not a world prop)",
	"NameTag/Word": "crew name tag carried with a crew member (scripts/player/player_visual.gd, not a world prop)",
}
## How far (m) the underside of a prop may be from the collision top under it (designer balance).
const SUPPORT_TOLERANCE_M := 0.035

func _initialize() -> void:
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.show_menu = false
	main.check_weather_updates = false
	main.save_directory = "res://_test_saves/test_no_floating"
	root.add_child(main)
	await _frames(5)
	main.services.start_new_game(90210)
	main._rebuild_crew()
	await _frames(20)
	_labels()
	_markers()
	_supports()
	_wall_sign()
	main.services.saves.delete_all()
	main.queue_free()
	await process_frame
	print("RESULT %d/%d" % [passed, total])
	quit(0 if passed == total else 1)

func _labels() -> void:
	var stray: Array[String] = []
	var billboards: Array[String] = []
	var seen := {}
	for node: Node in main.find_children("*", "Label3D", true, false):
		var label := node as Label3D
		var path := String(main.get_path_to(label))
		var key := ""
		for allowed: String in ALLOWED:
			if path.ends_with(allowed):
				key = allowed
		if key.is_empty():
			stray.append("%s \"%s\"" % [path, label.text.left(30)])
			continue
		seen[key] = true
		if label.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
			billboards.append(path)
	_check("no Label3D outside the mounted list (%d kinds seen)" % seen.size(), stray.is_empty(), str(stray))
	_check("no billboard text anywhere", billboards.is_empty(), str(billboards))
	var tape_labels := main.find_children("RoomLabel", "Label3D", true, false)
	_check("six room names lie flat on their cassettes", tape_labels.size() == 6 and tape_labels.all(func(l: Label3D) -> bool:
		return l.global_basis.z.normalized().dot(Vector3.UP) > 0.99 and l.get_parent().name == "CassetteModel"), str(tape_labels.size()))

func _markers() -> void:
	var stations := main.collision.get_node("Stations")
	var plates: Array[String] = []
	for entry: Dictionary in StationCatalog.extra_entries():
		if not entry.has("room_id"):
			continue
		var station := stations.get_node_or_null(NodePath(String(entry.id).validate_node_name()))
		if station == null:
			plates.append(String(entry.id) + " missing")
			continue
		if station.has_node("Marker") or station.has_node("LocationLabel"):
			plates.append(String(entry.id))
		if String(entry.kind) == "repair_task" and not station.find_children("*", "VisualInstance3D", true, false).is_empty():
			plates.append(String(entry.id) + " draws something")
	_check("no marker plates or floating names on repair, tape and player stations", plates.is_empty(), str(plates))
	var t01 := stations.get_node_or_null("repair_t01") as Area3D
	_check("repair stations keep their sensing volume", t01 != null and t01.collision_layer == Layers.STATION and t01.get_child_count() > 0)

func _supports() -> void:
	var stations := main.collision.get_node("Stations")
	var ids: Array = CassetteCatalog.TAPES.keys()
	ids.append(CassetteCatalog.PLAYER_ID)
	for id: String in ids:
		var station := stations.get_node_or_null(NodePath(id)) as Area3D
		var model_name := "CassettePlayerModel" if id == CassetteCatalog.PLAYER_ID else "CassetteModel"
		var model := station.get_node_or_null(model_name) as Node3D if station != null else null
		if model == null:
			_check("model present " + id, false)
			continue
		var box := _bounds(model)
		_check("model has meshes and is visible " + id, box.size.length() > 0.05 and model.is_visible_in_tree(), str(box))
		var bottom := box.position.y
		var c := box.get_center()
		var misses: Array[String] = []
		for f: Vector2 in [Vector2.ZERO, Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(-0.3, 0.3), Vector2(0.3, 0.3)]:
			var p := Vector3(c.x + f.x * box.size.x, bottom, c.z + f.y * box.size.z)
			var hit := _ray_down(p + Vector3.UP * 0.06, 0.3)
			if hit.is_empty() or absf(float((hit.position as Vector3).y) - bottom) > SUPPORT_TOLERANCE_M:
				misses.append("%s -> %s" % [p.snappedf(0.01), "nothing" if hit.is_empty() else str((hit.position as Vector3).y)])
		_check("rests on a surface " + id, misses.is_empty() and bottom > 0.3, "bottom %.3f %s" % [bottom, misses])
	# anything else drawn under a station: it must have something under it too
	var loose: Array[String] = []
	for node: Node in stations.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree():
			continue
		var b := mesh.global_transform * mesh.get_aabb()
		var hit := _ray_down(Vector3(b.get_center().x, b.position.y + 0.06, b.get_center().z), 2.5)
		if hit.is_empty() or b.position.y - float((hit.position as Vector3).y) > 0.25:
			loose.append(String(stations.get_path_to(mesh)))
	_check("no station mesh hangs in the air", loose.is_empty(), str(loose.slice(0, 6)))

func _wall_sign() -> void:
	var sign := main.get_node_or_null("AirlockHazardPresenter/AirlockPressureSign") as Label3D
	var board := main.get_node_or_null("AirlockHazardPresenter/AirlockPressureSignBoard") as MeshInstance3D
	_check("airlock pressure sign exists on its board", sign != null and board != null and not sign.text.is_empty())
	if sign == null or board == null:
		return
	var b := board.global_transform * board.get_aabb()
	# The board's back is on the measured face of the hangar wall (visual mesh ak_ws_5, z 9.828), and the wall is solid
	# there: the wall's collision box (it starts 0.25 m in front of the visual face) reaches the board from the hangar.
	var from := Vector3(b.get_center().x, b.get_center().y, b.position.z - 1.0)
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(from.x, from.y, b.end.z + 0.05), Layers.WORLD)
	var hit := root.get_world_3d().direct_space_state.intersect_ray(query)
	_check("airlock sign board is flat on the wall", b.size.z < 0.05 and absf(b.end.z - AirlockHazardPresenter.SIGN_WALL_Z) < 0.002 and not hit.is_empty(),
		"board z %.3f..%.3f wall collision %s" % [b.position.z, b.end.z, "none" if hit.is_empty() else str((hit.position as Vector3).z)])
	_check("airlock sign text sits on the board face and faces the hangar", sign.global_position.distance_to(Vector3(b.get_center().x, b.get_center().y, b.position.z)) < 0.01
		and sign.global_basis.z.normalized().dot(Vector3.BACK) < -0.99 and sign.billboard == BaseMaterial3D.BILLBOARD_DISABLED)

func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var b := mesh.global_transform * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

func _ray_down(from: Vector3, length: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * length, Layers.WORLD | Layers.DOOR)
	return root.get_world_3d().direct_space_state.intersect_ray(query)

func _frames(count: int) -> void:
	for i in count: await physics_frame

func _check(label: String, ok: bool, detail := "") -> void:
	total += 1
	if ok: passed += 1
	print("PASS " if ok else "FAIL ", label, " ", detail)
