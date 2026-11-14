extends SceneTree
## Checks rock collision: builds it from environment.glb the way the game does, then for 200 rocks casts a ray
## straight down through the rock's centre and reports how high above the drawn rock the solid top is
## (a convex hull is a little fuller than the rock), and whether a body walking at chest height is stopped.
## Run: godot --headless --path . --script res://tools/godot/diag_rocks.gd


func _initialize() -> void:
	var env := (load("res://assets/colony/environment.glb") as PackedScene).instantiate() as Node3D
	root.add_child(env)
	await process_frame
	var collision := Node3D.new()
	root.add_child(collision)
	var t0 := Time.get_ticks_msec()
	var n := RockCollision.build(env, collision)
	var build_ms := Time.get_ticks_msec() - t0
	# the drawn rocks, as trimesh, on another layer, to compare against
	var drawn := StaticBody3D.new()
	drawn.collision_layer = 1 << 29
	root.add_child(drawn)
	var rocks := env.find_children(RockCollision.NAME_PREFIX + "*", "MeshInstance3D", true, false)
	var sample: Array[MeshInstance3D] = []
	for i in rocks.size():
		if i % maxi(1, rocks.size() / 200) == 0:
			sample.append(rocks[i] as MeshInstance3D)
	for mi: MeshInstance3D in sample:
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		drawn.add_child(cs)
		cs.global_transform = mi.global_transform
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	var gaps: Array[float] = []
	var blocked := 0
	var tall := 0
	for mi: MeshInstance3D in sample:
		var c := (mi.global_transform * mi.get_aabb()).get_center()
		var top := Vector3(c.x, c.y + 50.0, c.z)
		var bottom := Vector3(c.x, c.y - 50.0, c.z)
		var solid := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, bottom, Layers.WORLD))
		var visual := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, bottom, 1 << 29))
		if not solid.is_empty() and not visual.is_empty():
			gaps.append(float(solid.position.y) - float(visual.position.y))
		var box := mi.global_transform * mi.get_aabb()
		if box.size.y > 1.0:
			tall += 1
			var chest := box.position.y + 0.9
			var from := Vector3(box.position.x - 3.0, chest, c.z)
			var to := Vector3(box.end.x + 3.0, chest, c.z)
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD)).is_empty():
				blocked += 1
	gaps.sort()
	var m := gaps.size()
	print("ROCKS with collision: %d (built in %d ms)" % [n, build_ms])
	if m > 0:
		print("solid top minus drawn top at the centre, %d rocks: median %+.3f m, 95th %+.3f, max %+.3f, min %+.3f" % [m, gaps[m / 2], gaps[int(m * 0.95)], gaps[m - 1], gaps[0]])
	print("rocks taller than 1 m in the sample: %d; stopped a horizontal ray at chest height: %d" % [tall, blocked])
	quit(0)
