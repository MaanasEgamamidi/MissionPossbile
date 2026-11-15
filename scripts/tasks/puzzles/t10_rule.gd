extends RefCounted
## T10 Equipment (Med Bay, any role): host rule. Owner's words (2026-11-14): plug in the equipment, drag each lead to
## the socket of its colour AND shape; the screens light up when right. Pack T10: matching labels / keying (never colour
## alone), then a short self-test; inserting alone does not finish it.
##
## Two leads: the heal station's GREEN ROUND plug and the CT scanner's BLUE SQUARE plug. The power unit has four
## sockets: the two right ones plus two look-alikes (green square, blue round), so both colour and shape matter. The
## socket order comes from task.puzzle_seed (deterministic).
##
## Moves {"move", "value"}: value = step * STEP_BASE + payload; step = puzzle_state.step (moves accepted so far), so a
## doubled, replayed or stale request is refused.
##   plug   payload = lead * 10 + socket   only the socket of the lead's colour and shape; a wrong one is refused
##   test   payload = 0                    the self-test: both leads seated -> repaired (complete)
##   reset  payload = 0                    pull both leads out again
## Pure and static: validate() never uses randomness or the clock.
##
## Two-player task (owner, 2026-11-15): one player plugs in the left machine (heal station), a DIFFERENT player plugs in
## the right one (CT scanner). state.by keeps the peer that seated each lead; a player who already seated one lead is
## refused the other. With both machines on, either player may run the self-test. RepairRuntime passes the mover's peer
## id as move.peer and lets several players hold this task at once (RepairRuntime.SHARED_TASKS). A move without a peer
## (headless tests) skips the two-player check.

const LEADS := 2
const SOCKETS := 4
const STEP_BASE := 1000
## Socket kinds: [colour word, shape word]. Kind 0 fits lead 0, kind 1 fits lead 1; kinds 2 and 3 are look-alikes.
const KINDS := [["green", "round"], ["blue", "square"], ["green", "square"], ["blue", "round"]]
## Lead -> [device, socket kind it needs].
const LEAD_INFO := [["Heal station", 0], ["CT scanner", 1]]
## Designer balance: each seated lead fills this much of the bar; the self-test finishes it.
const PLUG_SHARE := 0.4


static func supports_resume() -> bool:
	return true


## The seeded start: {seed, step, sockets: [kind at socket 0..3], plugged: [socket per lead or -1], tested}.
static func initial_state(puzzle_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = puzzle_seed
	var order := [0, 1, 2, 3]
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var keep: Variant = order[i]
		order[i] = order[j]
		order[j] = keep
	return {"seed": puzzle_seed, "step": 0, "sockets": order, "plugged": [-1, -1], "by": [-1, -1], "tested": false}


## The host's puzzle_state when it is a valid state of this seed, else the seeded start (plain ints, JSON-safe).
static func current_state(task: Dictionary) -> Dictionary:
	var puzzle_seed := int(task.get("puzzle_seed", 0))
	var start := initial_state(puzzle_seed)
	var raw: Variant = task.get("puzzle_state", {})
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return start
	var ps: Dictionary = raw
	if int(ps.get("seed", -1)) != puzzle_seed or int(ps.get("step", -1)) < 0 or not ps.get("plugged") is Array:
		return start
	var plugged: Array = []
	for p: Variant in ps.plugged:
		plugged.append(int(p))
	if plugged.size() != LEADS:
		return start
	for lead in LEADS:
		var socket: int = plugged[lead]
		if socket != -1 and (socket < 0 or socket >= SOCKETS or int(start.sockets[socket]) != int(LEAD_INFO[lead][1])):
			return start
	var by: Array = [-1, -1]
	var raw_by: Variant = ps.get("by", [])
	if raw_by is Array and (raw_by as Array).size() == LEADS:
		for lead in LEADS:
			by[lead] = int(raw_by[lead]) if int(plugged[lead]) != -1 else -1
	return {"seed": puzzle_seed, "step": int(ps.step), "sockets": start.sockets, "plugged": plugged, "by": by,
		"tested": bool(ps.get("tested", false))}


static func validate(task: Dictionary, move: Dictionary) -> Dictionary:
	var refused := {"accepted": false}
	var state := current_state(task)
	var value := int(move.get("value", -1))
	if value < 0 or value / STEP_BASE != int(state.step) or bool(state.tested):
		return refused
	var payload := value % STEP_BASE
	var plugged: Array = state.plugged
	match String(move.get("move", "")):
		"plug":
			var lead := payload / 10
			var socket := payload % 10
			if payload >= 100 or lead >= LEADS or socket >= SOCKETS or int(plugged[lead]) != -1 or plugged.has(socket):
				return refused
			if not fits(state, lead, socket):
				return refused
			var peer := int(move.get("peer", -1))
			if peer >= 0 and int(state.by[1 - lead]) == peer:
				return refused
			plugged[lead] = socket
			state.by[lead] = peer
		"test":
			if payload != 0 or plugged.has(-1):
				return refused
			state.tested = true
		"reset":
			if payload != 0 or plugged == [-1, -1]:
				return refused
			state.plugged = [-1, -1]
			state.by = [-1, -1]
		_:
			return refused
	state.step = int(state.step) + 1
	var done := bool(state.tested)
	return {"accepted": true, "puzzle_state": state, "progress": 1.0 if done else progress_of(state), "complete": done}


## True when the lead's plug matches the socket in colour and shape.
static func fits(state: Dictionary, lead: int, socket: int) -> bool:
	return lead >= 0 and lead < LEADS and socket >= 0 and socket < SOCKETS and int(state.sockets[socket]) == int(LEAD_INFO[lead][1])


static func progress_of(state: Dictionary) -> float:
	var seated := 0
	for p: Variant in state.plugged:
		seated += 1 if int(p) != -1 else 0
	return minf(0.99, PLUG_SHARE * float(seated))


## True when `peer` already seated the OTHER machine's lead, so this one is the partner's job.
static func partners_job(state: Dictionary, lead: int, peer: int) -> bool:
	var by: Array = state.get("by", [-1, -1])
	return peer >= 0 and lead >= 0 and lead < LEADS and by.size() == LEADS and int(by[1 - lead]) == peer


static func lead_kind(lead: int) -> int:
	return int(LEAD_INFO[lead][1])
