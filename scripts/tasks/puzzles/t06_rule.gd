extends RefCounted
## T06 Water (Greenhouse, any role) host rule: the broken water pipe BP09 (owner, 2026-11-14: "connect straight and
## elbow pipe pieces from the supply to the rack until water flows"; pipe-board details from the Prompt Pack's T07
## page, adapted). Contract: scripts/tasks/puzzle_registry.gd.
##
## Board: COLS x ROWS squares, read left to right, top to bottom (cell = row * COLS + col). Water enters the left
## edge at supply_row and must leave the right edge at rack_row. Every square holds a straight or an elbow pipe.
## The seed draws a route from the supply to the rack first (so a solution always exists), fills the other squares
## with harmless spare pipes, then turns pipes out of line. The player turns pipes a quarter turn at a time.
##
## Moves ({"move", "value"}, value = step * STEP_SHIFT + payload, step = puzzle_state.step + 1):
##   "turn"   payload = cell * 4 + new_rotation; new_rotation must be one quarter turn from the current one.
##   "reset"  payload 0; the seeded start position again.
## Anything else (unknown move, wrong step, replay, cell or rotation out of range) is refused.
##
## puzzle_state: {"seed", "step", "rot": [COLS*ROWS rotations 0..3], "kinds": [0 straight | 1 elbow],
##   "water": [cells water reaches, in flow order], "supply_row", "rack_row", "cols", "rows"}
## Completion: the water reaches the rack square and flows out of its right side.

const COLS := 5
const ROWS := 4
const STEP_SHIFT := 1024
const STRAIGHT := 0
const ELBOW := 1
## Directions: 0 up (north), 1 right (east), 2 down (south), 3 left (west). A pipe is a 4-bit mask of open sides.
const OFFSETS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## Rotation 0 shapes: straight = up + down, elbow = up + right. Each turn moves every opening one side clockwise.
const BASE_MASK := [5, 3]


static func supports_resume() -> bool:
	return false


## The open sides of a pipe kind at a rotation.
static func mask_of(kind: int, rotation: int) -> int:
	var mask: int = BASE_MASK[kind]
	var r := posmod(rotation, 4)
	return ((mask << r) | (mask >> (4 - r))) & 15


## The seeded board: kinds, solution rotations, start rotations, route and the two ends. Pure and deterministic.
static func layout(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "T06 water pipe"])
	var count := COLS * ROWS
	var kinds: Array[int] = []
	var solution: Array[int] = []
	kinds.resize(count)
	solution.resize(count)
	var route: Array[int] = []
	var row := rng.randi_range(0, ROWS - 1)
	var supply_row := row
	var entry := 3
	for col in COLS:
		var target := clampi(row + rng.randi_range(-2, 2), 0, ROWS - 1)
		var dir := signi(target - row)
		var r := row
		while true:
			var exit := 1 if r == target else (2 if dir > 0 else 0)
			var cell := r * COLS + col
			var kind := STRAIGHT if (entry + 2) % 4 == exit else ELBOW
			kinds[cell] = kind
			var want := (1 << entry) | (1 << exit)
			for rot in 4:
				if mask_of(kind, rot) == want:
					solution[cell] = rot
					break
			route.append(cell)
			if r == target:
				break
			r += dir
			entry = 0 if dir > 0 else 2
		row = target
		entry = 3
	var start: Array[int] = []
	start.resize(count)
	for cell in count:
		if not route.has(cell):
			kinds[cell] = STRAIGHT if rng.randf() < 0.4 else ELBOW
			solution[cell] = rng.randi_range(0, 3)
			start[cell] = solution[cell]
	# Turn route pipes out of line (a straight turned twice looks the same, so it gets an odd turn).
	var scrambled := 0
	for cell: int in route:
		start[cell] = solution[cell]
		if rng.randf() < 0.8:
			start[cell] = _out_of_line(kinds[cell], solution[cell], rng)
			scrambled += 1
	for cell: int in route:
		if scrambled >= 3:
			break
		if start[cell] == solution[cell]:
			start[cell] = _out_of_line(kinds[cell], solution[cell], rng)
			scrambled += 1
	var rack_row := row
	# Spare pipes must not already carry the water to the rack.
	if is_complete(kinds, start, supply_row, rack_row):
		var first := supply_row * COLS
		for rot in 4:
			if mask_of(kinds[first], rot) & 8 == 0:
				start[first] = rot
				break
	return {"kinds": kinds, "solution": solution, "start": start, "route": route,
		"supply_row": supply_row, "rack_row": rack_row}


## The cells water reaches from the supply, in flow order (breadth first).
static func water(kinds: Array, rots: Array, supply_row: int) -> Array[int]:
	var reached: Array[int] = []
	var first := supply_row * COLS
	if mask_of(int(kinds[first]), int(rots[first])) & 8 == 0:
		return reached
	reached.append(first)
	var i := 0
	while i < reached.size():
		var cell := reached[i]
		i += 1
		var mask := mask_of(int(kinds[cell]), int(rots[cell]))
		for d in 4:
			if mask & (1 << d) == 0:
				continue
			var at := Vector2i(cell % COLS, cell / COLS) + (OFFSETS[d] as Vector2i)
			if at.x < 0 or at.y < 0 or at.x >= COLS or at.y >= ROWS:
				continue
			var next := at.y * COLS + at.x
			if reached.has(next):
				continue
			if mask_of(int(kinds[next]), int(rots[next])) & (1 << ((d + 2) % 4)) != 0:
				reached.append(next)
	return reached


## True when water from the supply leaves the rack square through its right side.
static func is_complete(kinds: Array, rots: Array, supply_row: int, rack_row: int) -> bool:
	var rack := rack_row * COLS + COLS - 1
	return water(kinds, rots, supply_row).has(rack) and mask_of(int(kinds[rack]), int(rots[rack])) & 2 != 0


## The host's puzzle state for a task record: its saved state when it is valid for this seed, else the seeded start.
static func state_of(task: Dictionary) -> Dictionary:
	var seed_value := int(task.get("puzzle_seed", 0))
	var lay := layout(seed_value)
	var rots: Array = lay.start
	var step := 0
	var saved: Variant = task.get("puzzle_state", {})
	if saved is Dictionary and _whole((saved as Dictionary).get("seed")) == seed_value:
		var saved_step := _whole((saved as Dictionary).get("step"))
		var saved_rots: Variant = (saved as Dictionary).get("rot")
		if saved_step >= 0 and saved_rots is Array and (saved_rots as Array).size() == COLS * ROWS:
			var clean: Array[int] = []
			for value: Variant in saved_rots:
				var r := _whole(value)
				if r < 0 or r > 3:
					clean.clear()
					break
				clean.append(r)
			if clean.size() == COLS * ROWS:
				rots = clean
				step = saved_step
	return _pack(seed_value, step, rots, lay)


static func validate(task: Dictionary, move: Dictionary) -> Dictionary:
	var refused := {"accepted": false}
	var current := state_of(task)
	var lay := layout(int(current.seed))
	var value := _whole(move.get("value"))
	if value < 0:
		return refused
	if value / STEP_SHIFT != int(current.step) + 1:
		return refused
	var payload := value % STEP_SHIFT
	var rots: Array = (current.rot as Array).duplicate()
	match String(move.get("move", "")):
		"turn":
			var cell := payload / 4
			var rot := payload % 4
			if cell >= COLS * ROWS:
				return refused
			if rot != (int(rots[cell]) + 1) % 4 and rot != (int(rots[cell]) + 3) % 4:
				return refused
			rots[cell] = rot
		"reset":
			if payload != 0:
				return refused
			rots = (lay.start as Array).duplicate()
		_:
			return refused
	var next := _pack(int(current.seed), int(current.step) + 1, rots, lay)
	var complete := is_complete(lay.kinds, rots, int(lay.supply_row), int(lay.rack_row))
	var on_route := 0
	for cell: int in next.water:
		if (lay.route as Array).has(cell):
			on_route += 1
	var progress := 1.0 if complete else minf(0.95, float(on_route) / float((lay.route as Array).size()))
	return {"accepted": true, "puzzle_state": next, "progress": progress, "complete": complete}


static func _pack(seed_value: int, step: int, rots: Array, lay: Dictionary) -> Dictionary:
	var kinds: Array = (lay.kinds as Array).duplicate()
	var plain_rots: Array = []
	for r: Variant in rots:
		plain_rots.append(int(r))
	return {"seed": seed_value, "step": step, "rot": plain_rots, "kinds": kinds,
		"water": Array(water(kinds, plain_rots, int(lay.supply_row))), "supply_row": int(lay.supply_row),
		"rack_row": int(lay.rack_row), "cols": COLS, "rows": ROWS}


static func _out_of_line(kind: int, solved: int, rng: RandomNumberGenerator) -> int:
	if kind == STRAIGHT:
		return (solved + (1 if rng.randf() < 0.5 else 3)) % 4
	return (solved + rng.randi_range(1, 3)) % 4


## A whole number from a saved or networked value (JSON turns ints into floats), or -1.
static func _whole(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_finite(value) and float(value) == floorf(value) and absf(value) < 9.0e15:
		return int(value)
	return -1
