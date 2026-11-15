extends RefCounted
## T08 Glass (Garden dome, any role) host rule: the broken dome pane BP05. Prompt Pack T08: about five loose pieces
## that make a square pane; the host checks piece identity, allowed turns, bounds, no overlap and full cover.
## Contract: scripts/tasks/puzzle_registry.gd.
##
## The frame is SIZE x SIZE squares (cell = y * SIZE + x). The seed picks one of the authored tilings below (so a
## solution always exists), shuffles the five pieces in the tray and turns each one, so they start out of place.
## Pieces have different shapes and names, and the tray letters A-E label them. Pieces may be turned, never flipped.
##
## Moves ({"move", "value"}, value = step * STEP_SHIFT + payload, step = puzzle_state.step + 1):
##   "place"  payload = piece * 64 + turn * 16 + y * 4 + x: put a tray piece turned `turn` quarter turns clockwise
##            with its top-left corner at (x, y). It must lie inside the frame and on empty squares only.
##   "lift"   payload = piece: take a placed piece back to the tray (a wrong placement never loses a piece).
##   "reset"  payload 0: every piece back to the tray.
## Anything else (unknown move, wrong step, replay, piece or square out of range, overlap, sticking out) is refused.
##
## puzzle_state: {"seed", "step", "size", "placed": [5 x ([x, y, turn] | [])], "board": [SIZE*SIZE piece or -1],
##   "pieces": [{"letter", "name", "label", "cells": [[x, y], ...]}]}
## Completion: all five pieces are in the frame (their squares then cover it exactly, with no overlap).

const SIZE := 4
const PIECES := 5
const STEP_SHIFT := 1024
## Authored five-piece tilings of the 4 x 4 pane. Each letter is one piece; names say its shape.
const TILINGS := [
	{"rows": ["AAAA", "CCBB", "CCBE", "DDDE"],
		"names": {"A": "Long bar", "B": "Corner", "C": "Big square", "D": "Short bar", "E": "Small bar"}},
	{"rows": ["ABBB", "ADBC", "ADDC", "AEEC"],
		"names": {"A": "Long bar", "B": "T piece", "C": "Short bar", "D": "Corner", "E": "Small bar"}},
	{"rows": ["AABB", "AABC", "DDDC", "EEDC"],
		"names": {"A": "Big square", "B": "Corner", "C": "Short bar", "D": "L piece", "E": "Small bar"}},
	{"rows": ["ABBC", "ABBC", "ADDC", "AEDD"],
		"names": {"A": "Long bar", "B": "Big square", "C": "Short bar", "D": "Zigzag", "E": "Tiny square"}},
]
const LETTERS := "ABCDE"


static func supports_resume() -> bool:
	return false


## Cells turned `turns` quarter turns clockwise, moved so the smallest x and y are 0.
static func turned(cells: Array, turns: int) -> Array:
	var out: Array = []
	for c: Variant in cells:
		var v := Vector2i(int(c[0]), int(c[1]))
		for i in posmod(turns, 4):
			v = Vector2i(-v.y, v.x)
		out.append(v)
	var low := Vector2i(1 << 20, 1 << 20)
	for v: Vector2i in out:
		low = Vector2i(mini(low.x, v.x), mini(low.y, v.y))
	var result: Array = []
	for v: Vector2i in out:
		result.append([v.x - low.x, v.y - low.y])
	result.sort()
	return result


## Width and height of a cell list.
static func extent(cells: Array) -> Vector2i:
	var size := Vector2i.ZERO
	for c: Variant in cells:
		size = Vector2i(maxi(size.x, int(c[0]) + 1), maxi(size.y, int(c[1]) + 1))
	return size


## Frame squares a piece covers at (x, y) with a turn; squares outside the frame come back as -1.
static func covered(cells: Array, x: int, y: int, turns: int) -> Array[int]:
	var out: Array[int] = []
	for c: Variant in turned(cells, turns):
		var at := Vector2i(int(c[0]) + x, int(c[1]) + y)
		out.append(at.y * SIZE + at.x if at.x >= 0 and at.y >= 0 and at.x < SIZE and at.y < SIZE else -1)
	return out


## The seeded pieces: tiling, tray order, starting turn and the known solution of each piece.
static func layout(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "T08 glass pane"])
	var tiling: Dictionary = TILINGS[rng.randi_range(0, TILINGS.size() - 1)]
	var letters: Array = []
	for letter in "ABCDE":
		letters.append(letter)
	for i in range(letters.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = letters[i]
		letters[i] = letters[j]
		letters[j] = swap
	var pieces: Array = []
	for i in PIECES:
		var source := String(letters[i])
		var cells: Array = []
		for y in SIZE:
			for x in SIZE:
				if (tiling.rows[y] as String)[x] == source:
					cells.append([x, y])
		var low := Vector2i(SIZE, SIZE)
		for c: Array in cells:
			low = Vector2i(mini(low.x, c[0]), mini(low.y, c[1]))
		var start_turn := rng.randi_range(1, 3)
		var name := String(tiling.names[source])
		pieces.append({"letter": LETTERS[i], "name": name, "label": "%s - %s" % [LETTERS[i], name],
			"cells": turned(cells, start_turn), "solution": [low.x, low.y, (4 - start_turn) % 4]})
	return {"tiling": TILINGS.find(tiling), "pieces": pieces}


## The host's puzzle state for a task record: its saved state when valid for this seed, else every piece in the tray.
static func state_of(task: Dictionary) -> Dictionary:
	var seed_value := int(task.get("puzzle_seed", 0))
	var lay := layout(seed_value)
	var empty: Array = []
	for i in PIECES:
		empty.append([])
	var saved: Variant = task.get("puzzle_state", {})
	if saved is Dictionary and _whole((saved as Dictionary).get("seed")) == seed_value:
		var step := _whole((saved as Dictionary).get("step"))
		var placed: Variant = (saved as Dictionary).get("placed")
		if step >= 0 and placed is Array and (placed as Array).size() == PIECES:
			var clean: Array = []
			for entry: Variant in placed:
				if entry is Array and (entry as Array).is_empty():
					clean.append([])
				elif entry is Array and (entry as Array).size() == 3:
					clean.append([_whole(entry[0]), _whole(entry[1]), _whole(entry[2])])
				else:
					break
			if clean.size() == PIECES and not _board(lay, clean).is_empty():
				return _pack(seed_value, step, clean, lay)
	return _pack(seed_value, 0, empty, lay)


## Why a placement cannot work, in plain words for the panel, or "" when it fits.
static func why_not(state: Dictionary, piece: int, x: int, y: int, turns: int) -> String:
	if piece < 0 or piece >= PIECES:
		return "Pick a piece first."
	if not (state.placed[piece] as Array).is_empty():
		return "That piece is already in the frame."
	var board: Array = state.board
	for cell: int in covered(state.pieces[piece].cells, x, y, turns):
		if cell < 0:
			return "That would stick out of the frame. Try another spot or turn the piece."
		if int(board[cell]) >= 0:
			return "Those squares are already filled. Try another spot or turn the piece."
	return ""


static func validate(task: Dictionary, move: Dictionary) -> Dictionary:
	var refused := {"accepted": false}
	var current := state_of(task)
	var lay := layout(int(current.seed))
	var value := _whole(move.get("value"))
	if value < 0 or value / STEP_SHIFT != int(current.step) + 1:
		return refused
	var payload := value % STEP_SHIFT
	var placed: Array = (current.placed as Array).duplicate(true)
	match String(move.get("move", "")):
		"place":
			var piece := payload / 64
			var turns := (payload / 16) % 4
			var x := payload % 4
			var y := (payload / 4) % 4
			if piece >= PIECES or not why_not(current, piece, x, y, turns).is_empty():
				return refused
			placed[piece] = [x, y, turns]
		"lift":
			if payload >= PIECES or (placed[payload] as Array).is_empty():
				return refused
			placed[payload] = []
		"reset":
			if payload != 0:
				return refused
			for i in PIECES:
				placed[i] = []
		_:
			return refused
	var next := _pack(int(current.seed), int(current.step) + 1, placed, lay)
	var filled := 0
	for owner: int in next.board:
		if owner >= 0:
			filled += 1
	var complete := filled == SIZE * SIZE
	return {"accepted": true, "puzzle_state": next, "progress": float(filled) / float(SIZE * SIZE), "complete": complete}


## Board owners for the placements, or [] when a placement is out of range, outside the frame or overlapping.
static func _board(lay: Dictionary, placed: Array) -> Array:
	var board: Array = []
	board.resize(SIZE * SIZE)
	board.fill(-1)
	for piece in PIECES:
		var at: Array = placed[piece]
		if at.is_empty():
			continue
		if int(at[0]) < 0 or int(at[1]) < 0 or int(at[2]) < 0 or int(at[2]) > 3:
			return []
		for cell: int in covered(lay.pieces[piece].cells, int(at[0]), int(at[1]), int(at[2])):
			if cell < 0 or int(board[cell]) >= 0:
				return []
			board[cell] = piece
	return board


static func _pack(seed_value: int, step: int, placed: Array, lay: Dictionary) -> Dictionary:
	var pieces: Array = []
	for p: Dictionary in lay.pieces:
		pieces.append({"letter": p.letter, "name": p.name, "label": p.label, "cells": (p.cells as Array).duplicate(true)})
	return {"seed": seed_value, "step": step, "size": SIZE, "placed": placed.duplicate(true),
		"board": _board(lay, placed), "pieces": pieces}


## A whole number from a saved or networked value (JSON turns ints into floats), or -1.
static func _whole(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_finite(value) and float(value) == floorf(value) and absf(value) < 9.0e15:
		return int(value)
	return -1
