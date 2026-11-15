extends AreaStagePresenter
## Look of the "scout_drone" upgrade path (data/area_levels.json): the drone model of the current level, V1..V4
## (assets/drone/drone_v<n>.glb, built in Blender by tools/blender/drone/build_drone.py):
##   V1 basic frame, four short rotors, a small nose camera
##   V2 longer rotors and a bigger battery pod
##   V3 gimbal survey camera, whip antenna and the autopilot puck (programmable autopilot)
##   V4 rear sensor pod, landing lights and a long-range dish antenna
## The drone moves, so the stage rides on it: stage_parent() is the DronePresenter's body and build_stage() returns the
## model in the body's local space. Docked, the body stands on the pad, so this is the docked drone on the pad; in the
## air it is the flying drone, so both always show the level. Without a DronePresenter (tests, tools) the model is put
## on the pad in world coordinates instead. V1 is built too: the drone is not part of the map.

const DroneModels := preload("res://scripts/drone/drone_models.gd")
const DroneSystem := preload("res://scripts/drone/drone_system.gd")


func track_id() -> String:
	return "scout_drone"


## The DronePresenter's flying body, or null.
func drone_body() -> Node3D:
	if not is_inside_tree():
		return null
	for p in get_tree().get_nodes_in_group(&"drone_presenter"):
		if not p.is_queued_for_deletion():
			return p.get("body") as Node3D
	return null


func stage_parent() -> Node:
	var b := drone_body()
	return b if b != null else super.stage_parent()


func build_stage(level: int) -> Node3D:
	var n := DroneModels.drone(level)
	if drone_body() == null:
		var st := services.state() if services != null and services.has_game() else null
		n.position = DroneSystem.dock_position(st)
		n.rotation.y = DroneSystem.pad_yaw()
	return n
