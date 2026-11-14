extends SceneTree
## Stands the four crew side by side in the real game and photographs them, for judging the crew looks
## (CrewLooks: hair, skin, feminine/masculine body, accent colour, height, name tags).
## Needs a window (no --headless).
## Run: godot --path . --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/capture_crew.gd -- --out <folder> [--spot x,y,z]
## Files (in --out):
##   unsuited_front, unsuited_back, unsuited_threequarter, suited_front, suited_back   the four in a row (name tags on)
##   gameplay_<n>      third person from about 8 m behind the four walking together (name tags on)
##   head_unsuited_<i>, head_suited_<i>   head close-ups of crew i (0..3, CrewLooks order), the suited ones through the visor
##   capture_log.txt   model file, its hair meshes, and what each crew member was given

const SPOT := Vector3(-18.0, 0.3, 33.0)  # open ground outside the habitat (as in capture_anim.gd)
const SPACING := 1.1                      # metres between crew members in the row
var out_dir := ""
var main: GameMain
var spot := SPOT
var crew: Array[PlayerVisual] = []
var cam: Camera3D
var log_file: FileAccess


func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame


func _shot(file: String) -> void:
	# a stray Esc (or focus change) can open the pause menu mid-run: close any panel so every shot shows the game
	while main.ui.is_open():
		main.ui.close_top()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(file + ".png"))
	log_file.store_line("saved %s.png" % file)


func _ground_y(at: Vector3) -> float:
	var space := main.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 6.0))
	return (hit.position as Vector3).y if not hit.is_empty() else at.y


func _aim(from: Vector3, at: Vector3, fov: float) -> void:
	cam.fov = fov
	cam.global_position = from
	cam.look_at(at, Vector3.UP)


func _layers(at: Vector3) -> int:
	if main.services.zones == null:
		return 1
	return main._layers_for(main.services.zones.zone_at_world(at))


## Hides the HUD and other 2D layers for the model shots; the gameplay shots keep them.
func _set_ui(on: bool) -> void:
	for layer: Node in main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = on


func _set_suits(on: bool) -> void:
	for v: PlayerVisual in crew:
		v.set_suit(on)


func _set_tags(on: bool) -> void:
	for i: int in crew.size():
		crew[i].set_name_tag(CrewLooks.tag_text(_display_name(i), i) if on else "")


func _display_name(i: int) -> String:
	for c: CharacterState in main.services.state().characters.values():
		if c.specialty == CrewLooks.look(i).specialty:
			return c.display_name
	return ""


## Stands the crew in a row along +X facing -Z (the game's forward), feet on the ground.
func _line_up(centre: Vector3) -> void:
	for i: int in crew.size():
		var at := centre + Vector3((i - 1.5) * SPACING, 0.0, 0.0)
		at.y = _ground_y(at)
		crew[i].global_position = at
		crew[i].rotation.y = 0.0
		crew[i].clear_hold()
		crew[i].play(&"idle")
		crew[i].set_zone_layers(_layers(at))


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = ProjectSettings.globalize_path("res://").path_join("_test_saves/diag/capture_crew")
	var i := 0
	while i < args.size():
		match args[i]:
			"--out":
				out_dir = args[i + 1]; i += 1
			"--spot":
				var p := args[i + 1].split(",")
				spot = Vector3(float(p[0]), float(p[1]), float(p[2])); i += 1
		i += 1
	DirAccess.make_dir_recursive_absolute(out_dir)
	log_file = FileAccess.open(out_dir.path_join("capture_log.txt"), FileAccess.WRITE)
	var save_dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/diag/capture_crew_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir.path_join(f))
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	main.show_menu = false   # straight into the game, no main menu
	root.add_child(main)
	await _frames(90)
	for path: String in PlayerVisual.RIG_PATHS:
		if ResourceLoader.exists(path):
			var file := ProjectSettings.globalize_path(path)
			log_file.store_line("model %s modified %s" % [path, Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(file))])
			break
	# the local player is parked out of view; its own body is not one of the four photographed
	main.player.teleport(spot + Vector3(0, 0, 60), 0.0)
	await _frames(10)
	var floor_y := _ground_y(spot)
	var centre := Vector3(spot.x, floor_y, spot.z)
	for k: int in 4:
		var v := PlayerVisual.new()
		v.name = "CaptureCrew_%d" % k
		main.add_child(v)
		v.use_rig_if_available()
		v.set_first_person(false)
		v.set_crew_identity(k)
		crew.append(v)
		var look := CrewLooks.look(k)
		var hair: Array[String] = []
		for h: Node in v.find_children("Hair_*", "MeshInstance3D", true, false):
			hair.append(String(h.name))
		log_file.store_line("crew %d %s: hair %s (model has %s) feminine %.1f height %.2f accent %s skin %s hair colour %s tag \"%s\"" % [
			k, look.specialty, look.hair, hair, look.feminine, look.height, (look.accent as Color).to_html(false),
			(look.skin_color as Color).to_html(false), (look.hair_color as Color).to_html(false), CrewLooks.tag_text(_display_name(k), k)])
	_line_up(centre)
	cam = Camera3D.new()
	main.add_child(cam)
	cam.make_current()
	# a soft key from the front-left and a fill from behind, so faces and backs both read
	var key := OmniLight3D.new()
	key.omni_range = 14.0
	key.light_energy = 2.2
	main.add_child(key)
	var back := OmniLight3D.new()
	back.omni_range = 12.0
	back.light_energy = 1.2
	main.add_child(back)
	key.global_position = centre + Vector3(-2.5, 3.2, -3.5)
	back.global_position = centre + Vector3(2.0, 3.0, 3.5)
	var mid := centre + Vector3.UP * 1.0

	_set_ui(false)
	_set_tags(true)
	for suited: bool in [false, true]:
		_set_suits(suited)
		var prefix := "suited" if suited else "unsuited"
		await _frames(20)
		# the crew face -Z: the front camera stands on -Z, the back camera on +Z
		_aim(mid + Vector3(0.0, 0.25, -6.2), mid, 40.0)
		await _frames(2)
		await _shot(prefix + "_front")
		_aim(mid + Vector3(0.0, 0.25, 6.2), mid, 40.0)
		await _frames(2)
		await _shot(prefix + "_back")
		if not suited:
			_aim(mid + Vector3(-4.2, 0.6, -4.6), mid, 40.0)
			await _frames(2)
			await _shot(prefix + "_threequarter")

	# head close-ups, one crew member at a time
	_set_tags(false)
	for suited: bool in [false, true]:
		_set_suits(suited)
		await _frames(10)
		for k: int in crew.size():
			var tall := float(CrewLooks.look(k).height)
			var head := crew[k].global_position + Vector3(0.0, 1.66 * tall, 0.0)
			_aim(head + Vector3(-0.4, 0.05, -1.6), head, 30.0)
			await _frames(2)
			await _shot("head_%s_%d" % ["suited" if suited else "unsuited", k])

	# gameplay view: the four walk together away from a third-person-style camera about 8 m behind
	_set_suits(true)
	_set_tags(true)
	_set_ui(true)
	await _frames(5)
	var heading := Vector3(0, 0, -1)   # walking toward -Z, the way they face
	var offsets: Array[Vector3] = [Vector3(-1.4, 0, 0.3), Vector3(-0.45, 0, -0.4), Vector3(0.5, 0, 0.2), Vector3(1.4, 0, -0.3)]
	for k: int in crew.size():
		crew[k].play(&"walk", 1.0)
	var group := centre
	var n := 0
	for f: int in 150:
		group += heading * PlayerVisual.WALK_CLIP_SPEED / 60.0
		for k: int in crew.size():
			var at := group + offsets[k]
			at.y = _ground_y(at)
			crew[k].global_position = at
		var look_at := group + Vector3.UP * 1.1
		_aim(group - heading * 8.0 + Vector3.UP * 3.0, look_at, 72.0)
		if f >= 30 and f % 30 == 0:
			await _shot("gameplay_%d" % n)
			n += 1
		else:
			await physics_frame
	log_file.close()
	main.services.saves.delete_all()
	quit(0)
