class_name RepairCatalog
extends RefCounted
## Stable foundation contract. These records do not implement any room puzzle or cassette behavior.

const VERSION := 2
const MAINTENANCE_SCHEMA := 1
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
	var result := {"version": VERSION, "maintenance_schema": MAINTENANCE_SCHEMA, "rooms": {}, "tasks": {}, "collected_cassettes": [], "seen_beauty_shots": [],
		"legacy_maintenance": {"cleaner": {"last_condition": -1.0, "wear_elapsed_seconds": 0.0, "maintenance_cooldown_seconds": 0.0, "warning_active": false}}}
	for room_id: String in ROOMS:
		result.rooms[room_id] = {"first_completed": false, "condition": 1.0, "wear_hours": 0.0}
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	for task_id: String in TASKS:
		var info: Array = TASKS[task_id]
		result.tasks[task_id] = {"task_id": task_id, "room_id": info[0], "title": info[1],
			"required_specialty": info[2], "anchor_id": anchor_id(task_id), "puzzle_seed": random.randi(),
			"fault_generation": 1, "progress": 0.0, "condition": 1.0, "first_completed": false,
			"puzzle_state": {}, "resume_supported": false, "maintenance_schema": MAINTENANCE_SCHEMA,
			"maintenance_fault": false, "wear_elapsed_seconds": 0.0, "maintenance_cooldown_seconds": 0.0, "warning_active": false}
	return result

## Save-only projection. LAN snapshots keep all live moves; disk resumes only explicitly supported puzzles.
static func for_save(records: Dictionary) -> Dictionary:
	var saved := records.duplicate(true)
	for task: Dictionary in (saved.get("tasks", {}) as Dictionary).values():
		if float(task.get("progress", 0.0)) < 1.0 and not bool(task.get("resume_supported", false)):
			task.progress = 0.0
			task.puzzle_state = {}
	return saved

## Nested v0/v1 -> v2 maintenance migration; the surrounding save envelope stays compatible.
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
		var old_placeholder: bool = not incoming.has("maintenance_schema") and int(task.fault_generation) == 1 and not bool(task.first_completed) and float(task.progress) <= 0.0 and task.puzzle_state.is_empty() and float(task.condition) <= 0.0
		# F/C zeroes were unimplemented-puzzle placeholders, not failed operational hardware.
		if old_placeholder:
			task.condition = 1.0
		task.maintenance_fault = bool(incoming.get("maintenance_fault", int(task.fault_generation) > 1 and float(task.condition) < 1.0 and float(task.progress) < 1.0))
		for key: String in ["wear_elapsed_seconds", "maintenance_cooldown_seconds"]:
			task[key] = maxf(0.0, float(incoming.get(key, 0.0)))
		task.warning_active = bool(incoming.get("warning_active", false))
	var saved_rooms: Dictionary = saved.get("rooms", {})
	for room_id: String in ROOMS:
		var room: Dictionary = result.rooms[room_id]
		var incoming: Dictionary = saved_rooms.get(room_id, {})
		room.first_completed = bool(incoming.get("first_completed", false))
		room.condition = clampf(float(incoming.get("condition", 0.0)), 0.0, 1.0)
		room.wear_hours = maxf(0.0, float(incoming.get("wear_hours", 0.0)))
		room.condition = 0.0
		for task_id: String in ROOMS[room_id].tasks:
			room.condition += float(result.tasks[task_id].condition) / float((ROOMS[room_id].tasks as Array).size())
	var old_cleaner: Dictionary = (saved.get("legacy_maintenance", {}) as Dictionary).get("cleaner", {})
	var cleaner: Dictionary = result.legacy_maintenance.cleaner
	cleaner.last_condition = float(old_cleaner.get("last_condition", -1.0))
	for key: String in ["wear_elapsed_seconds", "maintenance_cooldown_seconds"]:
		cleaner[key] = maxf(0.0, float(old_cleaner.get(key, 0.0)))
	cleaner.warning_active = bool(old_cleaner.get("warning_active", false))
	for key: String in ["collected_cassettes", "seen_beauty_shots"]:
		for id: Variant in saved.get(key, []):
			var known := ROOMS.has(String(id)) if key == "seen_beauty_shots" else String(id).begins_with("cassette_") and ROOMS.has(String(id).trim_prefix("cassette_"))
			if known and not (result[key] as Array).has(String(id)):
				(result[key] as Array).append(String(id))
	return result
