extends RefCounted
## T04 Circuits host rule (Power Room circuit board, electrical_comms only; RepairRuntime enforces the role).
## Owner: "Place and rotate pieces on a grid until the route reaches the target voltage." Pack T04: one small grid with
## a source, a load, fixed and blocked cells, limited straight / corner pieces and a few labelled +/- voltage parts;
## the route must be continuous and correctly turned AND reach the target voltage; host checks ports, connectivity,
## piece limits, fixed cells and the voltage sum.
##
## Board: GRID_W x GRID_H cells, index = y * GRID_W + x. Power enters the left edge of row source_row and must leave
## the right edge of row load_row (the lamp). Ports: 0 = up, 1 = right, 2 = down, 3 = left.
## Pieces: straight (rotation 0 = left-right, 1 = up-down), corner (rotation r joins port r and port r+1:
## 0 up-right, 1 right-down, 2 down-left, 3 left-up), voltage part (shaped like a straight, adds its volts).
## Voltage arithmetic (designer balance, kept simple for ages 9-12): the source gives BASE_VOLTS; every voltage part on
## the connected route adds its value (+1, +2, +3 or -1). Actual = BASE_VOLTS + sum of the parts on the route.
## Solvable by construction: layout() first builds a route from the source to the load (column by column, so it never
## crosses itself), turns two of its straight cells into voltage parts, bolts one or two route cells in as fixed
## pieces, blocks three cells off the route, and gives the inventory exactly the route's pieces plus one spare
## straight, one spare corner and one -1 V decoy. target = BASE_VOLTS + the route's parts. layout().solution lists
## the placements that solve it (the tests replay it for many seeds).
## Moves:
##   place   value = cell * 100 + slot * 10 + rotation. The cell must be on the board, empty, not fixed or blocked;
##           the inventory slot must exist and still have a piece; rotation 0..3.
##   rotate  value = cell: quarter-turn a piece the player placed (fixed pieces never turn).
##   remove  value = cell: take a placed piece back into the inventory.
##   reset   value 0: every placed piece goes back (fixed pieces stay).
## Every accepted move re-traces the route; it completes only when the route is connected AND actual == target.
## puzzle_state = {"board": [GRID_W * GRID_H entries: -1 empty, else slot * 4 + rotation]}. Resumes from disk.

const GRID_W := 5
const GRID_H := 4
const BASE_VOLTS := 2
const STRAIGHT := 0
const CORNER := 1
const VOLT := 2
const DX := [0, 1, 0, -1]
const DY := [-1, 0, 1, 0]
const BLOCKED_COUNT := 3


static func supports_resume() -> bool:
	return true


## Ports of a piece kind at a rotation.
static func ports(kind: int, rot: int) -> Array:
	if kind == CORNER:
		return [posmod(rot, 4), posmod(rot + 1, 4)]
	return [1, 3] if posmod(rot, 2) == 0 else [0, 2]


static func _piece_for(a: int, b: int) -> Array:
	if (a == 1 and b == 3) or (a == 3 and b == 1):
		return [STRAIGHT, 0]
	if (a == 0 and b == 2) or (a == 2 and b == 0):
		return [STRAIGHT, 1]
	for r in 4:
		var p := ports(CORNER, r)
		if p.has(a) and p.has(b):
			return [CORNER, r]
	return [STRAIGHT, 0]


## The seeded board. Keys: source_row, load_row, target, path (route cells in order), fixed {cell: [kind, rot]},
## blocked [cells], slots [{kind, volts, count}], solution [{cell, slot, rot}].
static func layout(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var source_row := rng.randi_range(0, GRID_H - 1)
	var load_row := rng.randi_range(0, GRID_H - 1)
	var route: Array = []          # [cell, kind, rot, volts]
	var row := source_row
	route.append(_route_cell(0, row, 3, 1))
	for c in range(1, GRID_W - 1):
		var next_row := load_row if c == GRID_W - 2 else rng.randi_range(0, GRID_H - 1)
		if next_row == row:
			route.append(_route_cell(c, row, 3, 1))
			continue
		var step := 1 if next_row > row else -1
		var out_dir := 2 if step > 0 else 0
		route.append(_route_cell(c, row, 3, out_dir))
		var y := row + step
		while y != next_row:
			route.append(_route_cell(c, y, (out_dir + 2) % 4, out_dir))
			y += step
		route.append(_route_cell(c, next_row, (out_dir + 2) % 4, 1))
		row = next_row
	route.append(_route_cell(GRID_W - 1, row, 3, 1))
	# Two straight route cells become voltage parts.
	var straights: Array = []
	for i in route.size():
		if int(route[i][1]) == STRAIGHT:
			straights.append(i)
	_shuffle(straights, rng)
	var volt_values: Array = []
	for k in 2:
		var v := rng.randi_range(1, 3)
		route[straights[k]][1] = VOLT
		route[straights[k]][3] = v
		volt_values.append(v)
	var target := BASE_VOLTS
	for v: int in volt_values:
		target += v
	# One or two plain route cells are bolted in already.
	var plain: Array = []
	for i in route.size():
		if int(route[i][1]) != VOLT:
			plain.append(i)
	_shuffle(plain, rng)
	var fixed := {}
	for k in (2 if route.size() >= 7 else 1):
		var cell_info: Array = route[plain[k]]
		fixed[int(cell_info[0])] = [int(cell_info[1]), int(cell_info[2])]
	# Three blocked cells off the route.
	var on_route := {}
	for cell_info: Array in route:
		on_route[int(cell_info[0])] = true
	var free: Array = []
	for cell in GRID_W * GRID_H:
		if not on_route.has(cell):
			free.append(cell)
	_shuffle(free, rng)
	var blocked: Array = free.slice(0, mini(BLOCKED_COUNT, free.size()))
	blocked.sort()
	# Inventory: route pieces + a spare straight, a spare corner and a -1 V decoy.
	var slots: Array = [{"kind": STRAIGHT, "volts": 0, "count": 1}, {"kind": CORNER, "volts": 0, "count": 1}]
	var volt_slot := {}
	var sorted_values := volt_values.duplicate()
	sorted_values.sort()
	for v: int in sorted_values:
		if not volt_slot.has(v):
			volt_slot[v] = slots.size()
			slots.append({"kind": VOLT, "volts": v, "count": 0})
		slots[volt_slot[v]].count = int(slots[volt_slot[v]].count) + 1
	slots.append({"kind": VOLT, "volts": -1, "count": 1})
	var solution: Array = []
	for cell_info: Array in route:
		var cell := int(cell_info[0])
		if fixed.has(cell):
			continue
		var kind := int(cell_info[1])
		var slot := 0 if kind == STRAIGHT else (1 if kind == CORNER else int(volt_slot[int(cell_info[3])]))
		if kind != VOLT:
			slots[slot].count = int(slots[slot].count) + 1
		solution.append({"cell": cell, "slot": slot, "rot": int(cell_info[2])})
	var path: Array = []
	for cell_info: Array in route:
		path.append(int(cell_info[0]))
	return {"source_row": source_row, "load_row": load_row, "target": target, "path": path, "fixed": fixed,
		"blocked": blocked, "slots": slots, "solution": solution}


static func _route_cell(x: int, y: int, a: int, b: int) -> Array:
	var piece := _piece_for(a, b)
	return [y * GRID_W + x, piece[0], piece[1], 0]


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = list[i]
		list[i] = list[j]
		list[j] = tmp


static func empty_board() -> Array:
	var board: Array = []
	board.resize(GRID_W * GRID_H)
	board.fill(-1)
	return board


## The cleaned board: wrong sizes, fixed or blocked cells, unknown slots or more pieces than the inventory holds
## are dropped (a damaged save cannot create pieces).
static func board_of(task: Dictionary, lay: Dictionary) -> Array:
	var board := empty_board()
	var raw: Variant = task.get("puzzle_state", {})
	if not raw is Dictionary:
		return board
	var stored: Variant = (raw as Dictionary).get("board", [])
	if not stored is Array or (stored as Array).size() != GRID_W * GRID_H:
		return board
	var used := {}
	for cell in GRID_W * GRID_H:
		var code := int((stored as Array)[cell])
		if code < 0 or (lay.fixed as Dictionary).has(cell) or (lay.blocked as Array).has(cell):
			continue
		var slot := code / 4
		if slot >= (lay.slots as Array).size() or int(used.get(slot, 0)) >= int(lay.slots[slot].count):
			continue
		used[slot] = int(used.get(slot, 0)) + 1
		board[cell] = code
	return board


## Pieces of a slot still in the inventory.
static func remaining(lay: Dictionary, board: Array, slot: int) -> int:
	var used := 0
	for code: int in board:
		if code >= 0 and code / 4 == slot:
			used += 1
	return int(lay.slots[slot].count) - used


## The piece on a cell: {kind, rot, volts, fixed} or {} when empty (blocked cells are empty too).
static func piece_at(lay: Dictionary, board: Array, cell: int) -> Dictionary:
	if (lay.fixed as Dictionary).has(cell):
		var f: Array = lay.fixed[cell]
		return {"kind": int(f[0]), "rot": int(f[1]), "volts": 0, "fixed": true}
	var code := int(board[cell])
	if code < 0:
		return {}
	var slot: Dictionary = lay.slots[code / 4]
	return {"kind": int(slot.kind), "rot": code % 4, "volts": int(slot.volts), "fixed": false}


## Follows the current from the source: {connected, volts, cells}. volts counts only the parts on the route.
static func trace(lay: Dictionary, board: Array) -> Dictionary:
	var x := 0
	var y := int(lay.source_row)
	var enter := 3
	var volts := BASE_VOLTS
	var cells: Array = []
	var connected := false
	for _guard in GRID_W * GRID_H + 1:
		var cell := y * GRID_W + x
		var piece := piece_at(lay, board, cell)
		if piece.is_empty():
			break
		var p := ports(int(piece.kind), int(piece.rot))
		if not p.has(enter):
			break
		var exit_dir: int = p[0] if int(p[1]) == enter else p[1]
		cells.append(cell)
		volts += int(piece.volts)
		if x == GRID_W - 1 and y == int(lay.load_row) and exit_dir == 1:
			connected = true
			break
		x += int(DX[exit_dir])
		y += int(DY[exit_dir])
		if x < 0 or y < 0 or x >= GRID_W or y >= GRID_H:
			break
		enter = (exit_dir + 2) % 4
	return {"connected": connected, "volts": volts, "cells": cells}


static func validate(task: Dictionary, move: Dictionary) -> Dictionary:
	var rejected := {"accepted": false}
	if float(task.get("progress", 0.0)) >= 1.0:
		return rejected
	var lay := layout(int(task.get("puzzle_seed", 0)))
	var board := board_of(task, lay)
	var value := int(move.get("value", -1))
	var cells := GRID_W * GRID_H
	match String(move.get("move", "")):
		"place":
			if value < 0:
				return rejected
			var cell := value / 100
			var slot := (value / 10) % 10
			var rot := value % 10
			if cell >= cells or rot > 3 or slot >= (lay.slots as Array).size():
				return rejected
			if (lay.fixed as Dictionary).has(cell) or (lay.blocked as Array).has(cell) or int(board[cell]) >= 0:
				return rejected
			if remaining(lay, board, slot) <= 0:
				return rejected
			board[cell] = slot * 4 + rot
		"rotate", "remove":
			if value < 0 or value >= cells or int(board[value]) < 0:
				return rejected
			if String(move.move) == "rotate":
				var code := int(board[value])
				board[value] = (code / 4) * 4 + (code % 4 + 1) % 4
			else:
				board[value] = -1
		"reset":
			if value != 0:
				return rejected
			board = empty_board()
		_:
			return rejected
	var t := trace(lay, board)
	var complete := bool(t.connected) and int(t.volts) == int(lay.target)
	var reach := minf(1.0, float((t.cells as Array).size()) / maxf(1.0, float((lay.path as Array).size())))
	var progress := 1.0 if complete else 0.8 * reach + (0.1 if bool(t.connected) else 0.0)
	return {"accepted": true, "puzzle_state": {"board": board}, "progress": progress, "complete": complete}
