extends RefCounted
## T12 Seal (Hangar / airlock, field_engineering_geology): host rule. Owner's words (2026-11-14): air is escaping at the
## exit-tunnel inner door (door 901); "instead of clicking buttons, you actually click on the 1, 2, 3, 4, 5 to seal it
## down. But there's also a time limit on it. So if you don't do it fast enough, then it will ask you to restart it."
##
## Completion runs the usual RepairRuntime path: first_completed, condition 1 and WearRuntime.on_task_repaired, which
## clears T12.maintenance_fault. LocalPressure (S04) reads exactly that flag, so the leak stops and the exit vestibule
## repressurises on its own clock. Nothing here changes S04's rules.
##
## UI overhaul (2026-11-15, concept "Seal the Airlock"): three press points instead of five. The order rule is unchanged.
##
## Seeded from task.puzzle_seed: which of the 6 door-edge sections leaks, and which number (1..POINTS) sits on each of
## the seal points along that edge (a shuffle, never plain 1-2-3 or 3-2-1, so the order has to be shown).
## The time limit is the panel's (a client-side clock); when it runs out the panel asks for `reset`.
## Moves {"move", "value"}: value = step * STEP_BASE + payload; step = puzzle_state.step (moves accepted so far), so a
## doubled, replayed or stale request is refused.
##   press  payload = number 1..POINTS the number clicked; must be pressed + 1 -> complete when POINTS is pressed
##   reset  payload = 0                peel the half-pressed seal off (pressed > 0, not complete): back to 0 pressed
## Pure and static: validate() never uses randomness or the clock.

const SECTIONS := ["Top edge", "Left side", "Centre seam, high", "Centre seam, low", "Right side", "Floor edge"]
## Vertical sections run top-to-bottom; the others left-to-right (spot 0 = top or left end).
const VERTICAL := [false, true, true, true, true, false]
const POINTS := 3
const STEP_BASE := 1000
## Designer balance for the progress bar: each pressed point.
const PRESS_SHARE := 0.3


static func supports_resume() -> bool:
	return true


## The seeded start: {seed, step, leak, order, pressed}. order[spot] = the number (1..POINTS) shown on that spot.
static func initial_state(puzzle_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = puzzle_seed
	var leak := rng.randi_range(0, SECTIONS.size() - 1)
	var order: Array = []
	for n in POINTS:
		order.append(n + 1)
	for i in range(POINTS - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var keep: int = order[i]
		order[i] = order[j]
		order[j] = keep
	if _is_plain(order):
		var first: int = order[0]
		order[0] = order[1]
		order[1] = first
	return {"seed": puzzle_seed, "step": 0, "leak": leak, "order": order, "pressed": 0}


## True for 1-2-3 or 3-2-1 (no looking needed).
static func _is_plain(order: Array) -> bool:
	var up := true
	var down := true
	for i in order.size():
		up = up and int(order[i]) == i + 1
		down = down and int(order[i]) == order.size() - i
	return up or down


## The host's puzzle_state when it is a valid state of this seed, else the seeded start (plain ints, JSON-safe).
## The leak and the number order always come from the seed; pressed can never exceed the moves accepted.
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
	state.pressed = clampi(int(ps.get("pressed", 0)), 0, mini(POINTS, int(state.step)))
	# A seal saved half-pressed when the door had five points (before 2026-11-15) can read as all pressed without the
	# repair being complete: peel it off, so the player fits it again instead of being stuck.
	if int(state.pressed) >= POINTS and float(task.get("progress", 0.0)) < 1.0:
		state.pressed = 0
	return state


static func validate(task: Dictionary, move: Dictionary) -> Dictionary:
	var refused := {"accepted": false}
	if float(task.get("progress", 0.0)) >= 1.0:
		return refused
	var state := current_state(task)
	var value := int(move.get("value", -1))
	if value < 0 or value / STEP_BASE != int(state.step) or int(state.pressed) >= POINTS:
		return refused
	var payload := value % STEP_BASE
	match String(move.get("move", "")):
		"press":
			if payload != int(state.pressed) + 1:
				return refused
			state.pressed = payload
		"reset":
			if payload != 0 or int(state.pressed) <= 0:
				return refused
			state.pressed = 0
		_:
			return refused
	state.step = int(state.step) + 1
	var done := int(state.pressed) >= POINTS
	return {"accepted": true, "puzzle_state": state, "progress": 1.0 if done else progress_of(state), "complete": done}


## The spot (0 = top or left end) that carries `number`, or -1.
static func spot_of(state: Dictionary, number: int) -> int:
	var order: Array = state.get("order", [])
	for spot in order.size():
		if int(order[spot]) == number:
			return spot
	return -1


## The spot of the next number to press, or -1 when all are pressed.
static func next_point(state: Dictionary) -> int:
	var n := int(state.pressed)
	return -1 if n >= POINTS else spot_of(state, n + 1)


## The number (1..POINTS) shown on the point at `spot`.
static func order_number(state: Dictionary, spot: int) -> int:
	var order: Array = state.get("order", [])
	return int(order[spot]) if spot >= 0 and spot < order.size() else 0


static func progress_of(state: Dictionary) -> float:
	return minf(0.99, PRESS_SHARE * float(state.get("pressed", 0)))
