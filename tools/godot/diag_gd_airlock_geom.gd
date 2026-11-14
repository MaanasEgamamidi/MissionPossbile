extends SceneTree
## Dumps the garden dome airlock vestibule geometry (world coordinates) by ray casting its own triangles: rays along +x
## on a (z, y) grid show the doorway openings and the planes they pass; rays along z show the inner width.
## Run: godot --headless --path . --script res://tools/godot/diag_gd_airlock_geom.gd


func _initialize() -> void:
	var world := (load("res://scenes/world/colony_world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var node := world.find_child("gd_airlock", true, false) as MeshInstance3D
	var faces := PackedVector3Array()
	var xf := node.global_transform
	for v: Vector3 in node.mesh.get_faces():
		faces.append(xf * v)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	for i in 3:
		await physics_frame
	var space := body.get_world_3d().direct_space_state
	# 1. rays along +x from x 39 to 45: first hit x per (z, y)
	print("first hit x along +x (letter = hit x bucket: a=40.5..40.75, b, c ... per 0.25 m; '.' = straight through)")
	var y := 3.2
	while y > -0.05:
		var s := "y=%4.2f " % y
		var z := 25.3
		while z < 28.7:
			var q := PhysicsRayQueryParameters3D.create(Vector3(39, y, z), Vector3(45, y, z))
			var r := space.intersect_ray(q)
			if r.is_empty():
				s += "."
			else:
				s += char(97 + clampi(int(((r.position as Vector3).x - 40.5) / 0.25), 0, 25))
			z += 0.1
		print(s)
		y -= 0.1
	# 2. along the centre line z 27, y 1.2: all hits along x
	for yy: float in [0.3, 1.2, 2.0, 2.3, 2.5]:
		var hits := []
		var from := Vector3(39, yy, 27.0)
		for k in 20:
			var q := PhysicsRayQueryParameters3D.create(from, Vector3(45, yy, 27.0))
			var r := space.intersect_ray(q)
			if r.is_empty():
				break
			hits.append(snappedf((r.position as Vector3).x, 0.01))
			from = (r.position as Vector3) + Vector3(0.002, 0, 0)
		print("centre y=%.1f hits x: %s" % [yy, hits])
	# 3. inner width: rays from centre outwards along +-z at several x
	var x := 40.6
	while x < 43.6:
		var w := []
		for dir: float in [-1.0, 1.0]:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 1.2, 27.0), Vector3(x, 1.2, 27.0 + dir * 3.0))
			var r := space.intersect_ray(q)
			w.append(snappedf((r.position as Vector3).z, 0.01) if not r.is_empty() else null)
		var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 1.2, 27.0), Vector3(x, 5, 27.0)))
		var dn := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 1.2, 27.0), Vector3(x, -1, 27.0)))
		print("x=%.2f  z walls %s  ceiling %s floor %s" % [x, w, snappedf((up.position as Vector3).y, 0.01) if not up.is_empty() else null, snappedf((dn.position as Vector3).y, 0.01) if not dn.is_empty() else null])
		x += 0.1
	# 4. outer wall faces at the door planes (rays from outside inwards along z)
	for xx: float in [41.2, 41.45, 41.6, 43.0, 43.22, 43.4]:
		var a := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(xx, 1.2, 24.0), Vector3(xx, 1.2, 27.0)))
		var b := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(xx, 1.2, 30.0), Vector3(xx, 1.2, 27.0)))
		print("x=%.2f outer faces z %s / %s" % [xx, snappedf((a.position as Vector3).z, 0.01) if not a.is_empty() else null, snappedf((b.position as Vector3).z, 0.01) if not b.is_empty() else null])
	for s in node.mesh.get_surface_count():
		var m := node.get_active_material(s)
		print("surface %d material %s" % [s, m.resource_name if m != null else "none"])
	quit(0)
