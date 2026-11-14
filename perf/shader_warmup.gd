class_name ShaderWarmup
extends Node
## Phase 6: draws every zone once behind a full-screen black overlay, so every material, light and shadow variant has
## been drawn at least once before the player sees anything (Perf.cfg().shader_warmup_enabled, OFF by default:
## Godot 4.7 Forward+ already precompiles pipelines with ubershaders, and at this game's current frame rate the
## 4 x 17 stops take several seconds; enable it only if the pipeline-compilation monitors show compiles during play).
## Runs once, when PerfRig starts it at the start of play. Player input is off while it runs.

signal finished

var zone_manager: ZoneManager
var mars_roots: Array[Node3D] = []
var mars_viewpoints: Array[Transform3D] = []
var frames_per_stop := 2
var eye_height := 1.6
var running := false


func run(game: Node) -> void:
	var player: PlayerController = game.get("player")
	if player == null or zone_manager == null:
		finished.emit()
		return
	running = true
	var cam := player.camera_rig().camera()
	var overlay := CanvasLayer.new()
	overlay.layer = 127
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(black)
	add_child(overlay)
	var was_input := player.input_enabled
	player.input_enabled = false
	var saved_top_level := cam.top_level
	var saved := cam.global_transform
	cam.top_level = true          # move the camera alone; the player body stays where it is
	# the zone and exterior systems must not put anything back to sleep while the tour runs
	var paused: Array[Node] = [zone_manager]
	var ec := get_tree().get_first_node_in_group(&"exterior_controller")
	if ec != null:
		paused.append(ec)
	for n in paused:
		n.set_process(false)
	var shown := {}
	for r in mars_roots:
		shown[r] = r.visible
		r.visible = true
	for z in zone_manager.zones:
		z.apply_immediately(Zone.State.WARM)
	await get_tree().process_frame
	for z in zone_manager.zones:
		for yaw in [0.0, 90.0, 180.0, 270.0]:
			cam.global_transform = Transform3D(Basis.from_euler(Vector3(0.0, deg_to_rad(yaw), 0.0)), z.centre + Vector3.UP * (eye_height - 1.5))
			for _i in frames_per_stop:
				await get_tree().process_frame
	for m in mars_viewpoints:
		cam.global_transform = m
		for _i in frames_per_stop:
			await get_tree().process_frame
	cam.top_level = saved_top_level
	cam.global_transform = saved
	for r: Node3D in shown:
		r.visible = shown[r]
	for n in paused:
		n.set_process(true)
	zone_manager.snap()
	player.input_enabled = was_input
	overlay.queue_free()
	running = false
	finished.emit()
