extends SceneTree
## Measures hovering outdoors: a player sprints and walks across the dunes in several directions on the game's real
## ground collision (the height grid), while the drawn terrain (terrain.glb as trimesh, on a separate layer) is
## probed under the feet every physics frame. Reports feet height above the drawn ground, split into frames on the
## floor and frames in the air, and how often the player leaves the ground while running.
## Run: godot --headless --path . --script res://tools/godot/diag_dune_run.gd


func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame


func _initialize() -> void:
	var terrain := (load("res://assets/colony/terrain.glb") as PackedScene).instantiate() as Node3D
	terrain.visible = false
	root.add_child(terrain)
	await process_frame
	var drawn := StaticBody3D.new()
	drawn.collision_layer = 1 << 29
	drawn.collision_mask = 0
	root.add_child(drawn)
	for m in terrain.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		drawn.add_child(cs)
		cs.global_transform = mi.global_transform
	var grid := load("res://data/terrain_height.res") as TerrainHeight
	root.add_child(grid.make_body())
	var env := (load("res://assets/colony/environment.glb") as PackedScene).instantiate() as Node3D
	env.visible = false
	root.add_child(env)
	await process_frame
	var rocks := Node3D.new()
	root.add_child(rocks)
	RockCollision.build(env, rocks)

	var config := GameConfig.new()
	var c := CharacterState.new()
	c.id = &"crew_1"
	c.owner_peer = 1
	c.suit_on = true
	c.stamina = 100.0
	var player := PlayerController.new()
	root.add_child(player)
	player.setup(config, PlayerTuning.new(), c, Callable(), Callable())
	await _frames(2)
	var space := root.get_world_3d().direct_space_state
	# open dune country south of the base (Godot +z), well away from buildings
	var starts: Array[Vector3] = [Vector3(-40, 0, 60), Vector3(20, 0, 70), Vector3(60, 0, 60), Vector3(-70, 0, 20), Vector3(0, 0, 90)]
	var on_floor: Array[float] = []
	var in_air: Array[float] = []
	var air_frames := 0
	var total := 0
	var worst_floor := Vector3.ZERO
	for s: Vector3 in starts:
		for yaw: float in [0.0, PI * 0.5, PI, PI * 1.5]:
			var top := space.intersect_ray(PhysicsRayQueryParameters3D.create(s + Vector3(0, 200, 0), s + Vector3(0, -200, 0), Layers.WORLD))
			if top.is_empty():
				continue
			player.teleport((top.position as Vector3) + Vector3(0, 0.05, 0), yaw)
			c.stamina = 100.0
			await _frames(20)
			Input.action_press(&"move_forward")
			Input.action_press(&"sprint")
			for i in 240:
				await physics_frame
				if i == 150:
					Input.action_release(&"sprint")       # walk for the last part
				var p := player.global_position
				var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 3, 0), p + Vector3(0, -6, 0), 1 << 29))
				if ground.is_empty():
					continue
				var gap := p.y - float((ground.position as Vector3).y)
				total += 1
				if player.is_on_floor():
					on_floor.append(gap)
					if absf(gap) > absf(worst_floor.y):
						worst_floor = Vector3(p.x, gap, p.z)
				else:
					in_air.append(gap)
					air_frames += 1
			Input.action_release(&"move_forward")
			Input.action_release(&"sprint")
	on_floor.sort()
	in_air.sort()
	var n := on_floor.size()
	print("FRAMES %d, on the floor %d, in the air %d (%.1f %%)" % [total, n, air_frames, 100.0 * air_frames / maxf(1.0, total)])
	if n > 0:
		print("ON FLOOR feet minus drawn ground: median %+.3f m, 5th %+.3f, 95th %+.3f, 99th %+.3f, max %+.3f at (%.1f, %.1f)" % [
			on_floor[n / 2], on_floor[int(n * 0.05)], on_floor[int(n * 0.95)], on_floor[int(n * 0.99)], on_floor[n - 1], worst_floor.x, worst_floor.z])
	if not in_air.is_empty():
		var m := in_air.size()
		print("IN AIR feet minus drawn ground: median %+.3f m, 95th %+.3f, max %+.3f" % [in_air[m / 2], in_air[int(m * 0.95)], in_air[m - 1]])
	quit(0)
