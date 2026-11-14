extends SceneTree
## Captures animation clips on the real crew model inside the real game, for judging.
## Needs a window (no --headless).
## Run: godot --path . --resolution 960x720 --fixed-fps 60 --script res://tools/godot/capture_anim.gd -- --out <folder> [--clips walk,sprint,...] [--play] [--suit]
##   --fixed-fps 60 is needed for an honest --play log (see the timing note in the play section).
##   --clips  each clip is posed on a stand-alone crew model at 8 evenly spaced times, seen from the side and from the
##            front three-quarter (files <clip>_side_<i>.png, <clip>_front_<i>.png)
##   --play   real gameplay in third person: walk, sprint, standing jump, running jump (files play_<n>.png + play_log.txt)

const SPOT := Vector3(-18.0, 0.3, 33.0)  # open ground outside the habitat
var out_dir := ""
var main: GameMain


func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame


func _shot(file: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(file + ".png"))


func _ground_y(at: Vector3) -> float:
	var space := main.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 6.0))
	return (hit.position as Vector3).y if not hit.is_empty() else at.y


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = ProjectSettings.globalize_path("res://").path_join("_test_saves/diag/capture_anim")
	var clips: PackedStringArray = []
	var play := false
	var suit := false
	var i := 0
	while i < args.size():
		match args[i]:
			"--out":
				out_dir = args[i + 1]; i += 1
			"--clips":
				clips = args[i + 1].split(","); i += 1
			"--play":
				play = true
			"--suit":
				suit = true
		i += 1
	DirAccess.make_dir_recursive_absolute(out_dir)
	var save_dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/diag/capture_anim_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir.path_join(f))
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	main.show_menu = false   # straight into the game, no main menu
	root.add_child(main)
	await _frames(90)
	var player := main.player
	main.services.state().character_of_peer(SessionService.HOST_PEER).suit_on = suit
	var log := FileAccess.open(out_dir.path_join("capture_log.txt"), FileAccess.WRITE)

	if not clips.is_empty():
		# park the player out of view, pose a stand-alone model at the spot
		player.teleport(SPOT + Vector3(0, 0, 40), 0.0)
		await _frames(10)
		var floor_y := _ground_y(SPOT)
		var model := PlayerVisual.new()
		main.add_child(model)
		model.use_rig_if_available()
		model.set_first_person(false)
		model.set_suit(suit)
		model.global_position = Vector3(SPOT.x, floor_y, SPOT.z)
		var anim := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var cam := Camera3D.new()
		cam.fov = 40.0
		main.add_child(cam)
		var light := OmniLight3D.new()
		light.omni_range = 12.0
		light.light_energy = 2.5
		main.add_child(light)
		light.global_position = model.global_position + Vector3(2.5, 3.0, -2.5)
		cam.make_current()
		var target := model.global_position + Vector3.UP * 0.95
		for clip: String in clips:
			if not anim.has_animation(clip):
				log.store_line("%s: MISSING" % clip)
				continue
			var a := anim.get_animation(clip)
			log.store_line("%s: length=%.3f loop=%d" % [clip, a.length, a.loop_mode])
			anim.play(clip)
			anim.pause()
			for view: String in ["side", "front"]:
				# the model faces -Z (game forward); side camera on +X, front three-quarter ahead and to the side
				var offset := Vector3(3.6, 0.3, 0.0) if view == "side" else Vector3(2.2, 0.5, -2.8)
				cam.global_position = target + offset
				cam.look_at(target, Vector3.UP)
				for k in 8:
					anim.seek(a.length * k / 8.0, true)
					await _frames(2)
					await _shot("%s_%s_%d" % [clip, view, k])
		model.queue_free()
		cam.queue_free()
		light.queue_free()
		await _frames(2)

	if play:
		player.set_first_person(false)
		player.teleport(SPOT, 0.79)
		await _frames(40)
		var vis_anim := player.visual().find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var n := 0
		var steps := [
			["walk", [&"move_forward"], 60, -1],
			["sprint", [&"move_forward", &"sprint"], 60, -1],
			["stop", [], 40, -1],
			["standing_jump", [], 80, 0],
			["running_jump", [&"move_forward", &"sprint"], 90, 20],
		]
		# Honest timing. Rendering a 960x720 shot takes far longer than 1/60 s, so normally Godot runs several physics
		# steps per drawn frame while process (and so the AnimationPlayer) advances by the real frame time: physics,
		# animation and the log drift apart (round 2: idle advanced 0.13 s per 5-step sample, the run went 1.6x
		# further than the input script says, and a fresh clip read t=0.00 for two samples). With --fixed-fps 60 every
		# frame is exactly one 1/60 s physics step and one 1/60 s process step.
		var fixed := "--fixed-fps" in OS.get_cmdline_args()
		Engine.max_physics_steps_per_frame = 1
		log.store_line("timing: %s" % ("fixed 60 fps, one physics step per drawn frame" if fixed else
			"WARNING not run with --fixed-fps 60: animation time and physics time drift apart in this log"))
		for step: Array in steps:
			for act: StringName in step[1]:
				Input.action_press(act)
			# Step frames, jump timing and samples count physics steps (Engine.get_physics_frames), not loop turns:
			# a screenshot can let physics steps pass while this loop waits.
			var start := Engine.get_physics_frames()
			var jump_down := false
			var next_sample := 0
			while Engine.get_physics_frames() - start < int(step[2]):
				var f := Engine.get_physics_frames() - start
				if int(step[3]) >= 0 and f >= int(step[3]) and not jump_down:
					Input.action_press(&"jump")
					jump_down = true
				if jump_down and f >= int(step[3]) + 3:
					Input.action_release(&"jump")
				if f >= next_sample:
					next_sample = f + 5
					await _shot("play_%03d" % n)
					# Logged after the frame was drawn: the clip time is that of the pose in the picture.
					var v := Vector3(player.velocity.x, 0, player.velocity.z).length()
					log.store_line("play_%03d %s step_frame=%d anim=%s t=%.3f scale=%.2f ground=%.2f y=%.2f floor=%s" % [n, step[0], f, vis_anim.current_animation, vis_anim.current_animation_position, vis_anim.speed_scale, v, player.global_position.y, player.is_on_floor()])
					n += 1
				else:
					await physics_frame
			Input.action_release(&"jump")
			for act: StringName in step[1]:
				Input.action_release(act)
	log.close()
	main.services.saves.delete_all()
	quit(0)
