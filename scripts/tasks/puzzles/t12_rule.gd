extends RefCounted
## T12 Seal (Hangar / airlock, field_engineering_geology): host rule. Owner's words (2026-11-14): air is escaping at the
## exit-tunnel inner door (door 901); find the gap by the vapour, then fit and press the new seal along the edge in
## steps; done when the full edge is sealed. Pack T12 adds: the right gasket for the gap, pressing in the displayed
## order, and a final pressure check before the fault clears.
##
## Completion runs the usual RepairRuntime path: first_completed, condition 1 and WearRuntime.on_task_repaired, which
## clears T12.maintenance_fault. LocalPressure (S04) reads exactly that flag, so the leak stops and the exit vestibule
## repressurises on its own clock. Nothing here changes S04's rules.
##
## Seeded from task.puzzle_seed: which of the 6 door-edge sections leaks, how wide the gap is (which of 3 seals fits)
## and from which end the seal is pressed.
## Moves {"move", "value"}: value = step * STEP_BASE + payload; step = puzzle_state.step (moves accepted so far), so a
## doubled, replayed or stale request is refused.
##   find   payload = section 0..5     the section the vapour comes out of
##   fit    payload = seal 0..2        the seal as wide as the gap
##   press  payload = point 0..4       the next press point along the edge (points counted from the first end)
##   test   payload = 0                pressure check once the whole edge is pressed -> repaired (complete)
##   reset  payload = 0                peel the seal off and start again
## Pure and static: validate() never uses randomness or the clock.

const SECTIONS := ["Top edge", "Left side", "Centre seam, high", "Centre seam, low", "Right side", "Floor edge"]
## Vertical sections are pressed top-to-bottom or bottom-to-top; the others left-to-right or right-to-left.
const VERTICAL := [false, true, true, true, true, false]
const SEALS := ["Thin seal (4 mm)", "Medium seal (8 mm)", "Thick seal (12 mm)"]
const GAP_MM := [4, 8, 12]
const POINTS := 5
const STEP_BASE := 1000
## Designer balance for the progress bar.
const FIND_SHARE := 0.15
const FIT_SHARE := 0.3
const PRESS_SHARE := 0.1


static func supports_resume() -> bool:
	return true


## The seeded start: {seed, step, leak, gap, reverse, found, fitted, pressed, tested}.
static func initial_state(puzzle_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = puzzle_seed
	var leak := rng.randi_range(0, SECTIONS.size() - 1)
	var gap := rng.randi_range(0, SEALS.size() - 1)
	var reverse := rng.randi_range(0, 1) == 1
	return {"seed": puzzle_seed, "step": 0, "leak": leak, "gap": gap, "reverse": reverse,
		"found": false, "fitted": false, "pressed": 0, "tested": false}


## The host's puzzle_state when it is a valid state of this seed, else the seeded start (plain ints, JSON-safe).
static func current_state(task: Dictionary) -> Dictionary:
	var puzzle_seed := int(task.get("puzzle_seed", 0))
	var start := initial_state(puzzle_seed)
	var raw: Variant = task.get("puzzle_state", {})
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return start
	var ps: Dictionary = raw
	if int(ps.get("seed", -1)) != puzzle_seed or int(ps.get("step", -1)) < 0:
		return start
	var state := start.duplicate(true)
	state.step = int(ps.step)
	state.found = bool(ps.get("found", false))
	state.fitted = state.found and bool(ps.get("fitted", false))
	state.pressed = clampi(int(ps.get("pressed", 0)), 0, POINTS) if state.fitted else 0
	state.tested = state.pressed == POINTS and bool(ps.get("tested", false))
	return state


static func validate(task: Dictionary, move: Dictionary) -> Dictionary:
	var refused := {"accepted": false}
	var state := current_state(task)
	var value := int(move.get("value", -1))
	if value < 0 or value / STEP_BASE != int(state.step) or bool(state.tested):
		return refused
	var payload := value % STEP_BASE
	match String(move.get("move", "")):
		"find":
			if bool(state.found) or payload != int(state.leak):
				return refused
			state.found = true
		"fit":
			if not bool(state.found) or bool(state.fitted) or payload != int(state.gap):
				return refused
			state.fitted = true
		"press":
			if not bool(state.fitted) or int(state.pressed) >= POINTS or payload != next_point(state):
				return refused
			state.pressed = int(state.pressed) + 1
		"test":
			if payload != 0 or int(state.pressed) < POINTS:
				return refused
			state.tested = true
		"reset":
			if payload != 0 or not bool(state.found):
				return refused
			var start := initial_state(int(state.seed))
			start.step = state.step
			state = start
		_:
			return refused
	state.step = int(state.step) + 1
	var done := bool(state.tested)
	return {"accepted": true, "puzzle_state": state, "progress": 1.0 if done else progress_of(state), "complete": done}


## The position (0 = top or left end) of the next point to press, or -1 when the whole edge is pressed.
static func next_point(state: Dictionary) -> int:
	var n := int(state.pressed)
	if n >= POINTS:
		return -1
	return POINTS - 1 - n if bool(state.reverse) else n


## The press-order number (1..POINTS) shown on the point at `position`.
static func order_number(state: Dictionary, position: int) -> int:
	return POINTS - position if bool(state.reverse) else position + 1


static func progress_of(state: Dictionary) -> float:
	var p := 0.0
	if bool(state.found):
		p += FIND_SHARE
	if bool(state.fitted):
		p += FIT_SHARE
	p += PRESS_SHARE * float(state.pressed)
	return minf(0.99, p)
