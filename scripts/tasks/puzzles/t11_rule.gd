extends RefCounted
## T11 Dust (Hangar, any role) host rule: the dusty hangar BP10. Owner (2026-11-14): "Brush/vacuum dust patches area
## by area until clean; floor markings show again." Prompt Pack T11: bounded cleaning increments validated on the host.
## Contract: scripts/tasks/puzzle_registry.gd.
##
## The hangar floor is six areas (AREAS, a 3 x 2 grid over the Hangar bay, x 14..30, z -8..2 in Godot world
## coordinates). Each area starts with seeded dust 0.5, 0.75 or 1.0. One stroke cleans one area:
##   brush   removes 0.25 dust (works on any dust)
##   vacuum  removes 0.5 dust, but only loose dust: the area must be at 0.5 or less (brush thick dust first)
## About a dozen strokes clean the whole hangar.
##
## Moves ({"move", "value"}, value = step * STEP_SHIFT + payload, step = puzzle_state.step + 1):
##   "brush" / "vacuum"  payload = area index (AREAS order); refused on a clean area or (vacuum) on thick dust.
##   "reset"             payload 0: the seeded dust again.
## Anything else (unknown move, wrong step, replay, area out of range) is refused.
##
## puzzle_state (the integration worker lowers the visible hangar dust from it, area by area):
##   {"seed": int, "step": int, "areas": {"back_left": 0.75, "back_middle": 1.0, "back_right": 0.5,
##    "front_left": 0.5, "front_middle": 0.75, "front_right": 1.0}}
## Each level is dust left in that area, 0.0 (clean) .. 1.0 (thickest), always a multiple of 0.25. An empty
## puzzle_state means the seeded start; read levels with area_dust(task), which also handles that case.
## Completion: every area at 0.0. This rule supports resume: a half-cleaned hangar stays half cleaned after loading.

const STEP_SHIFT := 1024
const STROKE := 0.25
## Area ids in move order, with player names and their floor rectangle [x0, z0, x1, z1] (Godot world, metres).
## Back = the north half (z -8..-3), front = the south half (z -3..2), left = west (low x).
const AREAS := [
	{"id": "back_left", "name": "Back left", "rect": [14.0, -8.0, 19.33, -3.0]},
	{"id": "back_middle", "name": "Back middle", "rect": [19.33, -8.0, 24.67, -3.0]},
	{"id": "back_right", "name": "Back right", "rect": [24.67, -8.0, 30.0, -3.0]},
	{"id": "front_left", "name": "Front left", "rect": [14.0, -3.0, 19.33, 2.0]},
	{"id": "front_middle", "name": "Front middle", "rect": [19.33, -3.0, 24.67, 2.0]},
	{"id": "front_right", "name": "Front right", "rect": [24.67, -3.0, 30.0, 2.0]},
]


static func supports_resume() -> bool:
	return true


## Seeded starting dust per area id.
static func start_dust(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "T11 hangar dust"])
	var out := {}
	for area: Dictionary in AREAS:
		out[area.id] = float(rng.randi_range(2, 4)) * STROKE
	return out


## The dust the hangar should show now, per area id (0.0 clean .. 1.0): the puzzle's levels while the spot is
## broken, and all clean once the task has been completed for the first time.
static func area_dust(task: Dictionary) -> Dictionary:
	if bool(task.get("first_completed", false)) or float(task.get("progress", 0.0)) >= 1.0:
		var clean := {}
		for area: Dictionary in AREAS:
			clean[area.id] = 0.0
		return clean
	return (state_of(task).areas as Dictionary).duplicate()


## The host's puzzle state for a task record: its saved state when valid for this seed, else the seeded dust.
static func state_of(task: Dictionary) -> Dictionary:
	var seed_value := int(task.get("puzzle_seed", 0))
	var start := start_dust(seed_value)
	var saved: Variant = task.get("puzzle_state", {})
	if saved is Dictionary and _whole((saved as Dictionary).get("seed")) == seed_value:
		var step := _whole((saved as Dictionary).get("step"))
		var areas: Variant = (saved as Dictionary).get("areas")
		if step >= 0 and areas is Dictionary and (areas as Dictionary).size() == AREAS.size():
			var clean := {}
			var total := 0.0
			for area: Dictionary in AREAS:
				var level: Variant = (areas as Dictionary).get(area.id)
				if not (level is float or level is int):
					break
				var quarters := float(level) / STROKE
				# Dust only goes down from the seeded start, in whole strokes.
				if quarters != floorf(quarters) or float(level) < 0.0 or float(level) > float(start[area.id]):
					break
				clean[area.id] = float(level)
				total += float(level)
			# All clean only exists once the task is complete (an all-clean unfinished board would be a dead end).
			if clean.size() == AREAS.size() and (total > 0.0 or float(task.get("progress", 0.0)) >= 1.0):
				return {"seed": seed_value, "step": step, "areas": clean}
	return {"seed": seed_value, "step": 0, "areas": start}


## Why a stroke cannot work, in plain words for the panel, or "" when it can.
static func why_not(state: Dictionary, tool_id: String, area: int) -> String:
	if tool_id != "brush" and tool_id != "vacuum":
		return "Pick the brush or the vacuum."
	if area < 0 or area >= AREAS.size():
		return "Pick an area of the hangar floor."
	var level := float(state.areas[AREAS[area].id])
	if level <= 0.0:
		return "%s is already clean. Try a dusty area." % String(AREAS[area].name)
	if tool_id == "vacuum" and level > 0.5:
		return "The dust in %s is too thick for the vacuum. Brush it first." % String(AREAS[area].name).to_lower()
	return ""


static func validate(task: Dictionary, move: Dictionary) -> Dictionary:
	var refused := {"accepted": false}
	var current := state_of(task)
	var value := _whole(move.get("value"))
	if value < 0 or value / STEP_SHIFT != int(current.step) + 1:
		return refused
	var payload := value % STEP_SHIFT
	var areas: Dictionary = (current.areas as Dictionary).duplicate()
	var name := String(move.get("move", ""))
	match name:
		"brush", "vacuum":
			if not why_not(current, name, payload).is_empty():
				return refused
			var id := String(AREAS[payload].id)
			areas[id] = maxf(0.0, float(areas[id]) - (STROKE if name == "brush" else 2.0 * STROKE))
		"reset":
			if payload != 0:
				return refused
			areas = start_dust(int(current.seed))
		_:
			return refused
	var start_total := 0.0
	var left := 0.0
	var start := start_dust(int(current.seed))
	for area: Dictionary in AREAS:
		start_total += float(start[area.id])
		left += float(areas[area.id])
	var complete := left <= 0.0
	var progress := 1.0 if complete else minf(0.99, 1.0 - left / start_total)
	return {"accepted": true, "puzzle_state": {"seed": int(current.seed), "step": int(current.step) + 1, "areas": areas},
		"progress": progress, "complete": complete}


## A whole number from a saved or networked value (JSON turns ints into floats), or -1.
static func _whole(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_finite(value) and float(value) == floorf(value) and absf(value) < 9.0e15:
		return int(value)
	return -1
