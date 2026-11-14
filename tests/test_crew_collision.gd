extends SceneTree
## Exercise the real player and crew presence capsule: parked crew must be solid without sensing doors.
var passed := 0
var total := 0

func _initialize() -> void:
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Layers.WORLD
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	var game := GameMain.new()
	var presence := game._presence_body()
	game.free()
	presence.position = Vector3(0, 0, -2)
	world.add_child(presence)
	_check("parked crew are solid without opening doors", presence.collision_layer == Layers.CREW_SOLID)
	var crew := CharacterState.new()
	var player := PlayerController.new()
	player.setup(GameConfig.new(), PlayerTuning.new(), crew, Callable(), Callable())
	world.add_child(player)
	for active in [false, true]:
		presence.collision_layer = Layers.CREW_SOLID | (Layers.PLAYER if active else 0)
		player.teleport(Vector3.ZERO, 0)
		await _frames(5)
		Input.action_press("move_forward")
		await _frames(90)
		Input.action_release("move_forward")
		_check("cannot walk through %s crew" % ("active" if active else "parked"), player.position.z > -1.58 and player.position.z < -0.5)
		player.teleport(Vector3(1.2, 0, 0), 0)
		Input.action_press("move_forward")
		await _frames(90)
		Input.action_release("move_forward")
		_check("can walk alongside crew", player.position.z < -3.0)
	world.queue_free()
	await process_frame
	print("RESULT %d/%d" % [passed, total])
	quit(0 if passed == total else 1)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		passed += 1
	else:
		print("FAIL " + label)
