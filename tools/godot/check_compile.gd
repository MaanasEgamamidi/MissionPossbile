extends SceneTree
## Compile check: loads every GDScript file under res://scripts, res://tools, res://tests and res://perf and reports any that
## fail to parse or cannot be instantiated. Prints "COMPILE OK <n> scripts" or one "COMPILE FAIL <path>" per problem.
## Run: godot --headless --path . --script res://tools/godot/check_compile.gd


func _initialize() -> void:
	var files: PackedStringArray = []
	for root_dir in ["res://scripts", "res://tools", "res://tests", "res://perf"]:
		_collect(root_dir, files)
	var failed := 0
	for path in files:
		if path == (get_script() as Script).resource_path:
			continue        # reloading the running script itself hangs the engine
		if OS.get_cmdline_user_args().has("--verbose"):
			print("LOADING ", path)
		var script := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Script
		if script == null or not script.can_instantiate():
			print("COMPILE FAIL ", path)
			failed += 1
	if failed == 0:
		print("COMPILE OK %d scripts" % files.size())
	else:
		print("COMPILE FAILED %d of %d scripts" % [failed, files.size()])
	quit(0 if failed == 0 else 1)


func _collect(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		if d != "tmp" and not d.begins_with("."):
			_collect(dir_path.path_join(d), out)
