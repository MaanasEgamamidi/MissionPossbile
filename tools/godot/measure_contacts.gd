extends SceneTree
## Prints the heel-strike phases of the rig's locomotion clips, for PlayerVisual.CONTACT_PHASE.
## A heel strike is taken where a foot bone is furthest forward (the rig faces +Z in skeleton space).
## Run: godot --headless --path . --script res://tools/godot/measure_contacts.gd [-- walk,sprint]

func _initialize() -> void:
	var clips: PackedStringArray = ["walk", "sprint"]
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		clips = args[0].split(",")
	var vis := PlayerVisual.new()
	root.add_child(vis)
	if not vis.use_rig_if_available():
		print("no rigged astronaut found")
		quit(1)
		return
	await process_frame   # the skeleton only takes poses once it is ready in the tree
	await process_frame
	var anim := vis.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var sk := vis.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var feet: Array[int] = []
	for b: int in sk.get_bone_count():
		var bone := sk.get_bone_name(b).to_lower()
		if bone.contains("foot") and not bone.contains("toe") and not bone.contains("ik") and not bone.contains("pole"):
			feet.append(b)
	for clip: String in clips:
		if not anim.has_animation(clip):
			print("%s: MISSING" % clip)
			continue
		anim.play(clip)
		var length := anim.get_animation(clip).length
		var samples := 128
		for b: int in feet:
			var best_phase := 0.0
			var best_z := -INF
			for k: int in samples:
				anim.seek(length * k / samples, true)
				anim.advance(0.0)
				sk.force_update_all_bone_transforms()
				var z := sk.get_bone_global_pose(b).origin.z
				if z > best_z:
					best_z = z
					best_phase = float(k) / samples
			print("%s (%.3f s) %s heel strike at phase %.3f" % [clip, length, sk.get_bone_name(b), best_phase])
	quit(0)
