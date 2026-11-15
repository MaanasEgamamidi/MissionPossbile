extends RefCounted
## T09 Mixture (Med Bay, medical_life_support): host rule. Owner's words (2026-11-14): refill the rack and sort the
## coloured liquids into tubes, one colour per tube. The liquids are made-up practice reagents (no real chemistry).
##
## Layout from task.puzzle_seed (deterministic): 3 of the 4 reagents, 5 tubes that each hold 4 doses, 2 of them empty
## when sorted. The start is made by scrambling the sorted rack with legal reverse pours, so it is always solvable in at
## most the number of scramble steps. A few tubes have fallen out of the rack: they go back first ("rack").
##
## Moves {"move", "value"}: value = step * STEP_BASE + payload, where step is puzzle_state.step (the number of moves the
## host already accepted). A doubled, replayed or stale request carries an old step and is refused.
##   rack   payload = tube index           stand a fallen tube back in the rack
##   pour   payload = from * 10 + to       one dose from the top of `from` onto `to` (empty, or same reagent on top)
##   reset  payload = 0                    the liquids go back to the seeded start (fallen tubes stay racked)
## Pure and static: validate() never uses randomness or the clock.

const TUBES := 5
const CAPACITY := 4
const KINDS := 3
## Fictional reagents. Index = reagent id (the panel pairs each with a colour and a shape).
const REAGENTS := ["Zentra", "Morla", "Kivo", "Pluxa"]
## Designer balance: a short scramble keeps it at kid level (ages 9-12).
const SCRAMBLE_STEPS := 9
const MIN_MIXED_TUBES := 3
const FALLEN_TUBES := 3
const STEP_BASE := 1000
## Share of the progress bar for putting the fallen tubes back (designer balance).
const RACK_SHARE := 0.2


static func supports_resume() -> bool:
	return true


## The seeded start: {seed, step, racked: [bool x TUBES], tubes: [[reagent ids, bottom first] x TUBES]}.
static func initial_state(puzzle_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = puzzle_seed
	var pool := [0, 1, 2, 3]
	_shuffle(pool, rng)
	# Each attempt scrambles the sorted rack with SCRAMBLE_STEPS reverse pours; the first well-mixed result is kept
	# (the same rng sequence every time, so the seed alone decides the layout).
	var tubes: Array = _scramble(pool, rng)
	for attempt in 40:
		if _mixed(tubes) >= MIN_MIXED_TUBES and not is_sorted(tubes):
			break
		tubes = _scramble(pool, rng)
	var order := range(TUBES)
	_shuffle(order, rng)
	var placed: Array = []
	for i in TUBES:
		placed.append(tubes[order[i]])
	var racked: Array = []
	for i in TUBES:
		racked.append(true)
	var fallen := range(TUBES)
	_shuffle(fallen, rng)
	for i in FALLEN_TUBES:
		racked[fallen[i]] = false
	return {"seed": puzzle_seed, "step": 0, "racked": racked, "tubes": placed}


## The host's puzzle_state when it is a valid state of this seed, else the seeded start. Always plain ints and bools
## (a JSON save turns numbers into floats).
static func current_state(task: Dictionary) -> Dictionary:
	var puzzle_seed := int(task.get("puzzle_seed", 0))
	var start := initial_state(puzzle_seed)
	var raw: Variant = task.get("puzzle_state", {})
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return start
	var ps: Dictionary = raw
	if int(ps.get("seed", -1)) != puzzle_seed or not ps.get("racked") is Array or not ps.get("tubes") is Array:
		return start
	var racked_in: Array = ps.racked
	var tubes_in: Array = ps.tubes
	if racked_in.size() != TUBES or tubes_in.size() != TUBES or int(ps.get("step", -1)) < 0:
		return start
	var racked: Array = []
	for r: Variant in racked_in:
		racked.append(bool(r))
	var tubes: Array = []
	var counts := {}
	for t: Variant in tubes_in:
		if not t is Array or (t as Array).size() > CAPACITY:
			return start
		var tube: Array = []
		for d: Variant in t:
			tube.append(int(d))
			counts[int(d)] = int(counts.get(int(d), 0)) + 1
		tubes.append(tube)
	# The same reagents in the same amounts as the seeded start.
	if counts != _counts(start.tubes):
		return start
	return {"seed": puzzle_seed, "step": int(ps.step), "racked": racked, "tubes": tubes}


static func validate(task: Dictionary, move: Dictionary) -> Dictionary:
	var refused := {"accepted": false}
	var state := current_state(task)
	var value := int(move.get("value", -1))
	if value < 0 or value / STEP_BASE != int(state.step):
		return refused
	var payload := value % STEP_BASE
	var tubes: Array = state.tubes
	var racked: Array = state.racked
	match String(move.get("move", "")):
		"rack":
			if payload >= TUBES or bool(racked[payload]):
				return refused
			racked[payload] = true
		"pour":
			var from := payload / 10
			var to := payload % 10
			if payload >= 100 or from >= TUBES or to >= TUBES or from == to or not racked.all(func(r: bool) -> bool: return r):
				return refused
			if not can_pour(tubes, from, to):
				return refused
			(tubes[to] as Array).append((tubes[from] as Array).pop_back())
		"reset":
			var start: Array = initial_state(int(state.seed)).tubes
			if payload != 0 or tubes == start:
				return refused
			state.tubes = start
		_:
			return refused
	state.step = int(state.step) + 1
	var done := is_complete(state)
	return {"accepted": true, "puzzle_state": state, "progress": 1.0 if done else progress_of(state), "complete": done}


## True when one dose may go from the top of tube `from` onto tube `to`.
static func can_pour(tubes: Array, from: int, to: int) -> bool:
	var a: Array = tubes[from]
	var b: Array = tubes[to]
	return not a.is_empty() and b.size() < CAPACITY and (b.is_empty() or int(b.back()) == int(a.back()))


## Every tube is empty or full of one reagent.
static func is_sorted(tubes: Array) -> bool:
	for t: Array in tubes:
		if t.is_empty():
			continue
		if t.size() != CAPACITY:
			return false
		for d: Variant in t:
			if int(d) != int(t[0]):
				return false
	return true


static func is_complete(state: Dictionary) -> bool:
	return (state.racked as Array).all(func(r: bool) -> bool: return r) and is_sorted(state.tubes)


## 0..<1 while unsolved: racked tubes, then tubes that are already full of one reagent.
static func progress_of(state: Dictionary) -> float:
	var racked := 0
	for r: bool in state.racked:
		racked += 1 if r else 0
	var full := 0
	for t: Array in state.tubes:
		if t.size() == CAPACITY and t.all(func(d: int) -> bool: return d == int(t[0])):
			full += 1
	return minf(0.99, RACK_SHARE * float(racked) / float(TUBES) + (1.0 - RACK_SHARE) * float(full) / float(KINDS))


static func reagent_name(id: int) -> String:
	return REAGENTS[id] if id >= 0 and id < REAGENTS.size() else "?"


## The sorted rack (first KINDS reagents of `pool`, then empty tubes) after SCRAMBLE_STEPS legal reverse pours.
static func _scramble(pool: Array, rng: RandomNumberGenerator) -> Array:
	var tubes: Array = []
	for i in TUBES:
		var tube: Array = []
		if i < KINDS:
			for d in CAPACITY:
				tube.append(int(pool[i]))
		tubes.append(tube)
	var last := Vector2i(-1, -1)
	for step in SCRAMBLE_STEPS:
		var options: Array[Vector2i] = []
		for x in TUBES:
			for y in TUBES:
				if x == y or (tubes[x] as Array).is_empty() or (tubes[y] as Array).size() >= CAPACITY:
					continue
				if x == last.y and y == last.x:
					continue
				var from: Array = tubes[x]
				# Reverse of a forward pour y -> x: what stays on top of x must be empty or the same reagent.
				if from.size() > 1 and int(from[from.size() - 2]) != int(from.back()):
					continue
				options.append(Vector2i(x, y))
		if options.is_empty():
			break
		var pick := options[rng.randi_range(0, options.size() - 1)]
		(tubes[pick.y] as Array).append((tubes[pick.x] as Array).pop_back())
		last = pick
	return tubes


static func _mixed(tubes: Array) -> int:
	var count := 0
	for t: Array in tubes:
		for d: Variant in t:
			if int(d) != int(t[0]):
				count += 1
				break
	return count


static func _counts(tubes: Array) -> Dictionary:
	var counts := {}
	for t: Array in tubes:
		for d: Variant in t:
			counts[int(d)] = int(counts.get(int(d), 0)) + 1
	return counts


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var keep: Variant = list[i]
		list[i] = list[j]
		list[j] = keep
