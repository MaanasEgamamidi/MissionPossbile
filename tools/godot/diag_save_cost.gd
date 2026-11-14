extends SceneTree
## Diagnostic: how big is a save and how long does writing one take? Writes into a folder inside the project.
## Run: godot --headless --path . --script res://tools/godot/diag_save_cost.gd


func _initialize() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/cost")
	DirAccess.make_dir_recursive_absolute(dir)
	var g := GameServices.new()
	g.saves = SaveService.new(dir, "colony", 2)
	root.add_child(g)
	g.saves.delete_all()
	g.start_new_game(1)
	for i in 3000:
		g.session.advance(0.2)
	var times: Array[float] = []
	for i in 50:
		var t0 := Time.get_ticks_usec()
		g.save_now(&"manual")
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	times.sort()
	var size := FileAccess.get_file_as_bytes(g.saves.main_path()).size()
	var t1 := Time.get_ticks_usec()
	var loaded := g.saves.read()
	print("SAVE size %d bytes; write+verify+rotate ms: median %.2f, slowest %.2f; read+verify %.2f ms (%s)" % [
		size, times[25], times[49], float(Time.get_ticks_usec() - t1) / 1000.0, loaded.status])
	g.saves.delete_all()
	quit(0)
