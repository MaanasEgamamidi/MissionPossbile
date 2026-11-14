extends SceneTree
## Replays the PDF scenarios in the rendered game using isolated test saves. Does not touch the player's saves.
var main: GameMain
var out_dir := ""
var failures := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://_test_saves/pdf_views")
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = ProjectSettings.globalize_path("res://_test_saves/pdf_walkthrough")
	main.show_menu = false
	main.check_weather_updates = false
	root.add_child(main)
	await _frames(60)
	# Fresh colony in this isolated directory, regardless of earlier verification runs.
	main.services.start_new_game()
	main._rebuild_crew()
	await _frames(10)
	await _shot("corridor", Vector3(32, 0.04, -3), -PI / 2, -0.2)
	await _shot("kitchen_hood", Vector3(15.72, 0.04, -17.3), 0, 0.15)
	# Move and turn around the reported kitchen rectangle; inspect every view for pop-in/reflection artifacts.
	for i in 3:
		await _shot("hood_angle_%d" % i, Vector3(15.72 + (i - 1) * 0.55, 0.04, -17.3), (i - 1) * 0.2, 0.15)
	await _shot("chess", Vector3(17.88, 0.04, -15.8), 0, -0.95)
	await _shot("planter", Vector3(2.1, 0.04, -17.0), PI / 2, -0.5)
	await _shot("greenhouse_tools", Vector3(-7.8, 0.04, 6.3), PI / 2, -0.2)
	await _shot("greenhouse_floor", Vector3(-4, 0.04, 8.5), PI / 2, -0.65)
	await _shot("command_chairs", Vector3(29, 0.04, -13), -PI / 2, -0.2)
	await _shot("airlock_clean", Vector3(20, 0.04, 6), PI / 2, -0.35)
	await _shot("rack_full", Vector3(16.4, 0.04, 7.5), PI, 0)
	var c := main.services.local_character()
	var rack: StringName = &"al_suit_rack"
	var answer := main.services.session.request(&"begin_suit_check", rack, {"on": true})
	_check("suit request accepted in rendered game", answer.ok)
	await _frames(85)
	_check("suit check completes in rendered game", c.suit_on and c.suit_slot >= 0)
	await _capture("rack_taken")
	main.player.teleport(Vector3(20, 0.05, 6), PI / 2)
	main.player.camera_rig().rotation.x = 0
	await _frames(8)
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	await _capture("suited_jump_rising")
	await _frames(12)
	await _capture("suited_jump_apex")
	await _frames(40)
	main.player.camera_rig().rotation.x = -1.2
	await _frames(5)
	await _capture("suited_look_down")
	main.player.set_first_person(false)
	await _frames(5)
	await _capture("suited_third_person")
	main.player.set_first_person(true)
	main.player.teleport(Vector3(16.4, 0.05, 7.5), PI)
	main.player.camera_rig().rotation.x = 0
	await _frames(5)
	answer = main.services.session.request(&"begin_suit_check", rack, {"on": false})
	_check("return request accepted", answer.ok)
	await _frames(85)
	_check("returned suit is no longer worn", not c.suit_on and c.suit_slot == -1)
	await _capture("rack_returned")
	# The same actual imported hangar used in the game, including prop collision and railing.
	main.player.teleport(Vector3(27.66, 0.04, -0.33), -PI / 2)
	main.player.camera_rig().rotation.x = 0
	await _frames(8)
	main.player._interact()
	Input.action_press("move_forward")
	await _frames(130)
	Input.action_release("move_forward")
	_check("rendered ladder reaches mezzanine", main.player.global_position.y > 2.65 and main.player.global_position.x > 28.2)
	await _capture("ladder_top")
	main.player._ladder = main.collision.get_node("hgw_ladder") as ClimbableLadder
	Input.action_press("move_back")
	await _frames(155)
	Input.action_release("move_back")
	_check("rendered ladder returns to floor", main.player.global_position.y < 0.2)
	await _capture("ladder_bottom")
	print("PDF WALKTHROUGH failures=", failures)
	quit(0 if failures == 0 else 1)

func _shot(label: String, pos: Vector3, yaw: float, pitch: float) -> void:
	main.player.set_first_person(true)
	main.player.teleport(pos, yaw)
	main.player.camera_rig().rotation.x = pitch
	await _frames(18)
	await _capture(label)

func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(label + ".png"))
	print("CAPTURE ", label, " player=", main.player.global_position)

func _frames(n: int) -> void:
	var target := Engine.get_physics_frames() + n
	while Engine.get_physics_frames() < target:
		await physics_frame

func _check(label: String, ok: bool) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
