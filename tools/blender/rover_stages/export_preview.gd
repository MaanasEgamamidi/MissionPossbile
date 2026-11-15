extends SceneTree
## Rover upgrade look, preview export (worker ROVER, 2026-11-14). Headless: loads the map's rover mesh (sf_rover) in
## the rover body frame (-Z forward, as RoverBody draws it), adds the add-on parts that
## scripts/upgrades/stages/rover_stages.gd builds for a set of module levels, and writes one .glb per build to
## assets_src/rover_stages/preview/ (ignored by Godot). tools/blender/rover_stages/render_preview.py renders them.
## Run: godot --headless --path . --script res://tools/blender/rover_stages/export_preview.gd [-- --bare]

const RoverStages := preload("res://scripts/upgrades/stages/rover_stages.gd")
const OUT_DIR := "res://assets_src/rover_stages/preview"

## name -> module levels (speed, torque, range, cargo, traction). The V level follows AreaLevels.rover_level().
const BUILDS := {
	"00_stock": {"speed": 1, "torque": 1, "range": 1, "cargo": 1, "traction": 1},
	"01_v2_battery": {"speed": 1, "torque": 1, "range": 3, "cargo": 1, "traction": 1},
	"02_v2_mixed": {"speed": 2, "torque": 2, "range": 1, "cargo": 2, "traction": 2},
	"03_v3": {"speed": 3, "torque": 3, "range": 3, "cargo": 3, "traction": 3},
	"04_v4_mid": {"speed": 4, "torque": 4, "range": 4, "cargo": 4, "traction": 4},
	"05_v4_max": {"speed": 5, "torque": 5, "range": 5, "cargo": 5, "traction": 5},
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var world := (load("res://scenes/world/colony_world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	await process_frame
	var src := world.find_child("sf_rover", true, false) as MeshInstance3D
	if src == null:
		print("EXPORT FAIL sf_rover not found")
		quit(1)
		return
	print("EXPORT map loaded in %d ms; sf_rover mesh aabb %s, %d surfaces" % [Time.get_ticks_msec() - t0, src.mesh.get_aabb(), src.mesh.get_surface_count()])
	for i in src.mesh.get_surface_count():
		var m := src.get_active_material(i)
		print("EXPORT   surface %d material %s" % [i, m.resource_name if m != null else "-"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var only_bare := OS.get_cmdline_user_args().has("--bare")
	for build_name: String in BUILDS:
		if only_bare and build_name != "00_stock":
			continue
		var levels: Dictionary = BUILDS[build_name]
		var scene := Node3D.new()
		scene.name = "Rover_" + build_name
		root.add_child(scene)
		var rover := MeshInstance3D.new()
		rover.name = "sf_rover"
		rover.mesh = src.mesh
		rover.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)   # data/rover.json mesh_yaw_deg 180
		scene.add_child(rover)
		var lvl := AreaLevels.rover_level(levels)
		var parts: Node3D = RoverStages.build_parts(levels, lvl)
		if parts != null:
			scene.add_child(parts)
		var doc := GLTFDocument.new()
		var gstate := GLTFState.new()
		var err := doc.append_from_scene(scene, gstate)
		if err == OK:
			err = doc.write_to_filesystem(gstate, ProjectSettings.globalize_path(OUT_DIR.path_join(build_name + ".glb")))
		print("EXPORT %s V%d %s -> %s" % [build_name, lvl, levels, "ok" if err == OK else "error %d" % err])
		scene.free()
	world.queue_free()
	await process_frame
	quit(0)
