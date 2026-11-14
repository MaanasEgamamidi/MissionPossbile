extends SceneTree
## Finds visible geometry the player can walk through: compares each map object's visible bounds with its collision boxes,
## lists visual nodes that have no manifest record, door-like visuals that do not move, and how stations are reached.
## Run: godot --headless --path . --script res://tools/godot/diag_collision.gd -- --out <file.json>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := ProjectSettings.globalize_path("res://").path_join("_test_saves/diag/diag_collision.json")
	for i in args.size():
		if args[i] == "--out":
			out = args[i + 1]
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/colony_manifest.json"))
	var by_name := {}
	for o: Dictionary in manifest.objects:
		by_name[o.name] = o
	var world := (load("res://scenes/world/colony_world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	var collision := WorldCollision.build("res://data/colony_manifest.json", "res://data/colliders.json")
	root.add_child(collision)
	await process_frame
	# collision AABB per object name
	var col_box := {}
	for s: Node in collision.find_children("*", "CollisionShape3D", true, false):
		var cs := s as CollisionShape3D
		if not cs.has_meta("object_name") or not (cs.shape is BoxShape3D):
			continue
		var b := (cs.shape as BoxShape3D).size
		var aabb := cs.global_transform * AABB(-b * 0.5, b)
		var n: String = cs.get_meta("object_name")
		col_box[n] = (col_box[n] as AABB).merge(aabb) if col_box.has(n) else aabb
	var report := {"uncovered": [], "unknown_visuals": [], "door_visuals": []}
	for child: Node in world.find_children("*", "Node3D", true, false):
		var n := String(child.name)
		if not (child is Node3D):
			continue
		var meshes := child.find_children("*", "MeshInstance3D", true, false)
		if child is MeshInstance3D:
			meshes.append(child)
		if meshes.is_empty():
			continue
		var vis := AABB()
		var first := true
		for m: Node in meshes:
			var mi := m as MeshInstance3D
			if mi.mesh == null:
				continue
			var a := mi.global_transform * mi.mesh.get_aabb()
			vis = a if first else vis.merge(a)
			first = false
		if first:
			continue
		var lower := n.to_lower()
		if "door" in lower or "hatch" in lower or "gate" in lower:
			report.door_visuals.append({"name": n, "path": str(world.get_path_to(child)), "in_manifest": by_name.has(n), "cls": by_name[n].cls if by_name.has(n) else "", "center": [vis.get_center().x, vis.get_center().y, vis.get_center().z], "size": [vis.size.x, vis.size.y, vis.size.z]})
		if not by_name.has(n):
			if child.get_parent() == world or (child.get_parent() != null and by_name.has(String(child.get_parent().name)) == false and child.get_parent().get_parent() == world):
				if vis.size.y > 1.2 and maxf(vis.size.x, vis.size.z) > 1.0:
					report.unknown_visuals.append({"name": n, "path": str(world.get_path_to(child)), "center": [vis.get_center().x, vis.get_center().y, vis.get_center().z], "size": [vis.size.x, vis.size.y, vis.size.z]})
			continue
		var o: Dictionary = by_name[n]
		if not (o.cls in ["static", "dynamic", "floor", "ladder"]):
			continue
		if vis.size.y < 1.2 or maxf(vis.size.x, vis.size.z) < 1.0:
			continue  # only tall, wide things matter for walking through
		var coverage := 0.0
		if col_box.has(n):
			var c: AABB = col_box[n]
			var inter := vis.intersection(c)
			coverage = (inter.size.x * inter.size.z) / maxf(vis.size.x * vis.size.z, 0.0001)
		if coverage < 0.5:
			report.uncovered.append({"name": n, "asset": o.gc_asset, "area": o.area, "coverage_xz": snappedf(coverage, 0.01), "center": [vis.get_center().x, vis.get_center().y, vis.get_center().z], "size": [vis.size.x, vis.size.y, vis.size.z]})
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	f.close()
	print("uncovered=%d unknown=%d doors=%d -> %s" % [report.uncovered.size(), report.unknown_visuals.size(), report.door_visuals.size(), out])
	quit(0)

