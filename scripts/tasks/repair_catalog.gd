class_name RepairCatalog
extends RefCounted
## Stable foundation contract. These records do not implement any room puzzle or cassette behavior.

const VERSION := 1
const ROOMS := {
	"command_center": {"title": "Command center", "zones": ["Command Room"], "tasks": ["T01", "T02"]},
	"power_supply": {"title": "Power supply", "zones": ["Power Room"], "tasks": ["T03", "T04"]},
	"greenhouse": {"title": "Greenhouse", "zones": ["Greenhouse"], "tasks": ["T05", "T06"]},
	"green_dome": {"title": "Green dome", "zones": ["Garden dome"], "tasks": ["T07", "T08"]},
	"med_bay": {"title": "Med Bay", "zones": ["Med Bay"], "tasks": ["T09", "T10"]},
	"hangar": {"title": "Hangar / airlock", "zones": ["Hangar bay", "Airlock"], "tasks": ["T11", "T12"]},
}
const TASKS := {
	"T01": ["command_center", "Comms", "general"],
	"T02": ["command_center", "Wires", "electrical_comms"],
	"T03": ["power_supply", "Rings", "general"],
	"T04": ["power_supply", "Circuits", "electrical_comms"],
	"T05": ["greenhouse", "Elements", "biology_food"],
	"T06": ["greenhouse", "Water", "general"],
	"T07": ["green_dome", "Pipes", "field_engineering_geology"],
	"T08": ["green_dome", "Glass", "general"],
	"T09": ["med_bay", "Mixture", "medical_life_support"],
	"T10": ["med_bay", "Equipment", "general"],
	"T11": ["hangar", "Dust", "general"],
	"T12": ["hangar", "Seal", "field_engineering_geology"],
}

static func anchor_id(task_id: String) -> String:
	return "repair_" + task_id.to_lower()

static func fresh(seed_value: int) -> Dictionary:
	var result := {"version": VERSION, "rooms": {}, "tasks": {}, "collected_cassettes": [], "seen_beauty_shots": []}
	for room_id: String in ROOMS:
		result.rooms[room_id] = {"first_completed": false, "condition": 0.0, "wear_hours": 0.0}
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	for task_id: String in TASKS:
		var info: Array = TASKS[task_id]
		result.tasks[task_id] = {"task_id": task_id, "room_id": info[0], "title": info[1],
			"required_specialty": info[2], "anchor_id": anchor_id(task_id), "puzzle_seed": random.randi(),
			"fault_generation": 1, "progress": 0.0, "condition": 0.0, "first_completed": false,
			"puzzle_state": {}, "resume_supported": false}
	return result

## Save-only projection. LAN snapshots keep all live moves; disk resumes only explicitly supported puzzles.
static func for_save(records: Dictionary) -> Dictionary:
	var saved := records.duplicate(true)
	for task: Dictionary in (saved.get("tasks", {}) as Dictionary).values():
		if float(task.get("progress", 0.0)) < 1.0 and not bool(task.get("resume_supported", false)):
			task.progress = 0.0
			task.puzzle_state = {}
	return saved

## Nested v0 (absent in existing saves) -> v1 migration; the surrounding save envelope stays compatible.
## Catalog identity and role fields always come from this host build.
static func restore(saved: Dictionary, seed_value: int) -> Dictionary:
	var result := fresh(seed_value)
	var saved_tasks: Dictionary = saved.get("tasks", {})
	for task_id: String in TASKS:
		var task: Dictionary = result.tasks[task_id]
		var incoming: Dictionary = saved_tasks.get(task_id, {})
		for key: String in ["puzzle_seed", "fault_generation"]:
			task[key] = int(incoming.get(key, task[key]))
		task.fault_generation = maxi(1, int(task.fault_generation))
		for key: String in ["progress", "condition"]:
			task[key] = clampf(float(incoming.get(key, task[key])), 0.0, 1.0)
		task.first_completed = bool(incoming.get("first_completed", false))
		task.puzzle_state = (incoming.get("puzzle_state", {}) as Dictionary).duplicate(true)
		task.resume_supported = bool(incoming.get("resume_supported", false))
	var saved_rooms: Dictionary = saved.get("rooms", {})
	for room_id: String in ROOMS:
		var room: Dictionary = result.rooms[room_id]
		var incoming: Dictionary = saved_rooms.get(room_id, {})
		room.first_completed = bool(incoming.get("first_completed", false))
		room.condition = clampf(float(incoming.get("condition", 0.0)), 0.0, 1.0)
		room.wear_hours = maxf(0.0, float(incoming.get("wear_hours", 0.0)))
	for key: String in ["collected_cassettes", "seen_beauty_shots"]:
		for id: Variant in saved.get(key, []):
			var known := ROOMS.has(String(id)) if key == "seen_beauty_shots" else String(id).begins_with("cassette_") and ROOMS.has(String(id).trim_prefix("cassette_"))
			if known and not (result[key] as Array).has(String(id)):
				(result[key] as Array).append(String(id))
	return result
