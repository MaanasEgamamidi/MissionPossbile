extends SceneTree
## Casts horizontal rays at body height through given points and prints what each hits (body / shape name), to check
## what collision lies in front of a visible object.
## Run: godot --headless --path . --script res://tools/godot/diag_ray_probe.gd -- name,x0,y,z0,x1,z1 ...   (y above the ground)

var main: GameMain


func _initialize() -> void:
	var save_dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/diag/probe_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	main.show_menu = false
	root.add_child(main)
	for i in 5:
		await physics_frame
	var space := main.get_world_3d().direct_space_state
	var height := load(GameMain.TERRAIN_HEIGHT_PATH) as TerrainHeight
	for arg: String in OS.get_cmdline_user_args():
		var s := arg.split(",")
		var a := Vector3(float(s[1]), 0, float(s[3]))
		var b := Vector3(float(s[4]), 0, float(s[5]))
		a.y = height.height_at(a.x, a.z) + float(s[2])
		b.y = a.y
		var q := PhysicsRayQueryParameters3D.create(a, b, Layers.WORLD | Layers.DOOR)
		q.hit_back_faces = true
		var hit := space.intersect_ray(q)
		var what := "nothing"
		if not hit.is_empty():
			var body := hit.collider as CollisionObject3D
			var owner := body.shape_owner_get_owner(body.shape_find_owner(int(hit.shape)))
			what = "%s/%s at %s" % [body.name, owner.name if owner != null else "?", hit.position]
		print("PROBE %s: %s" % [s[0], what])
	main.services.saves.delete_all()
	quit(0)
