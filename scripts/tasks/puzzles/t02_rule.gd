extends RefCounted
## T02 Wires host rule (Command Room wiring rack, electrical_comms only; RepairRuntime enforces the role).
## Owner: "Connect 4 coloured wires (with symbols for colour-blind players)." Pack T02: four left terminals, four
## shuffled right terminals, a unique label/symbol per pair, wrong connections are explained and released, correct
## ones lock; the host validates terminal ids, uniqueness and the seeded mapping; complete only with all four.
##
## Pairs: 0 = A red triangle, 1 = B blue circle, 2 = C yellow square, 3 = D pink diamond (the BP03 cable colours).
## Layout (seeded): left[i] = the pair on left terminal i, right[j] = the pair on right terminal j. Both are seeded
## shuffles and the right side never repeats the left order.
## Moves:
##   connect  value = left_terminal * 10 + right_terminal (each 0..3). Accepted only when both ids are real, the left
##            terminal has no cable yet, the right terminal is free, and both carry the same pair. A correct cable
##            locks (it cannot be pulled out again except by reset). Anything else is rejected and nothing changes.
##   reset    value 0: every cable comes out.
## puzzle_state = {"links": [right terminal for left 0..3, or -1]}. progress = cables / 4; complete at 4.
## Resumes from disk (a locked cable stays locked).

const PAIRS := 4
const NAMES := ["red", "blue", "yellow", "pink"]
const LETTERS := ["A", "B", "C", "D"]
## Cable colours from the BP03 rack (coral, sky blue, warm yellow, pink). Designer art values.
const COLORS := [Color(0.95, 0.42, 0.36), Color(0.42, 0.64, 0.98), Color(0.98, 0.8, 0.32), Color(0.96, 0.58, 0.8)]
## Shapes in electric_ui.gd's Shape order: triangle, circle, square, diamond.
const SHAPES := [0, 1, 2, 3]
const SHAPE_NAMES := ["triangle", "circle", "square", "diamond"]


static func supports_resume() -> bool:
	return true


## {left: [pair per left terminal], right: [pair per right terminal]}.
static func layout(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var left := _shuffled(rng)
	var right := _shuffled(rng)
	if right == left:
		right.push_back(right.pop_front())
	return {"left": left, "right": right}


static func _shuffled(rng: RandomNumberGenerator) -> Array:
	var order := [0, 1, 2, 3]
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	return order


static func initial_state() -> Dictionary:
	return {"links": [-1, -1, -1, -1]}


## Cleaned links: each entry a right terminal 0..3 or -1, no right terminal used twice, and only correct pairs
## (a damaged save cannot smuggle in a wrong cable).
static func links_of(task: Dictionary) -> Array:
	var links := [-1, -1, -1, -1]
	var raw: Variant = task.get("puzzle_state", {})
	if not raw is Dictionary:
		return links
	var stored: Variant = (raw as Dictionary).get("links", [])
	if not stored is Array or (stored as Array).size() != PAIRS:
		return links
	var lay := layout(int(task.get("puzzle_seed", 0)))
	var used := {}
	for i in PAIRS:
		var j := int((stored as Array)[i])
		if j >= 0 and j < PAIRS and not used.has(j) and int(lay.left[i]) == int(lay.right[j]):
			links[i] = j
			used[j] = true
	return links


static func validate(task: Dictionary, move: Dictionary) -> Dictionary:
	var rejected := {"accepted": false}
	if float(task.get("progress", 0.0)) >= 1.0:
		return rejected
	var lay := layout(int(task.get("puzzle_seed", 0)))
	var links := links_of(task)
	var value := int(move.get("value", -1))
	match String(move.get("move", "")):
		"connect":
			if value < 0 or value > 33:
				return rejected
			var left := value / 10
			var right := value % 10
			if left >= PAIRS or right >= PAIRS or int(links[left]) != -1 or links.has(right):
				return rejected
			if int(lay.left[left]) != int(lay.right[right]):
				return rejected
			links[left] = right
		"reset":
			if value != 0:
				return rejected
			links = [-1, -1, -1, -1]
		_:
			return rejected
	var done := 0
	for j: int in links:
		if j >= 0:
			done += 1
	var complete := done == PAIRS
	return {"accepted": true, "puzzle_state": {"links": links}, "progress": 1.0 if complete else float(done) / PAIRS, "complete": complete}
