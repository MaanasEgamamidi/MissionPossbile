extends RefCounted
## T01 Comms host rule (Command Room, any crew). Owner: "Turn the dial until the signal wave matches, then hold it
## briefly." Pack T01: seeded target, tolerant match window, holding a valid match locks the link, then a data
## transfer bar reaches a validated completion.
##
## Rules (all numbers are designer balance, not NASA data):
## - The tuning dial runs 0..DIAL_MAX and starts at START_DIAL. The seeded target is 15..35 steps away from the start.
## - A dial within TOLERANCE of the target is a match (the received wave sits on the target wave).
## - Moves (one per real player action; the panel paces the automatic ones):
##     tune     value = dial 0..DIAL_MAX. Not after the link is locked. Any tune starts the hold count again.
##     hold     value = next hold step (1..HOLD_STEPS). Accepted only while the HOST's dial is a match, and only in
##              order, so a false match, a skipped or a replayed step is rejected. The panel sends one step every
##              HOLD_SECONDS while the player keeps the dial still on the match; HOLD_STEPS steps lock the link.
##              (The rule has no clock: the hold is a sequence of host-checked steps, not a measured duration.)
##     transfer value = next transfer block (1..TRANSFER_STEPS). Only after the lock, in order. The last block completes.
##     reset    value 0. Back to the start (dial, holds, lock, transfer).
## - progress = half for the hold steps + half for the transfer blocks; 1.0 only when the transfer is complete.
## Does not resume from disk: a reload restarts this small puzzle (pack T01 point 3).

const DIAL_MAX := 100
const START_DIAL := 50
const TOLERANCE := 4
const MIN_GAP := 15
const MAX_GAP := 35
const HOLD_STEPS := 3
## Panel pacing (seconds between hold steps / transfer blocks). Client-side only; documented for the owner.
const HOLD_SECONDS := 0.5
const TRANSFER_STEPS := 4
const TRANSFER_SECONDS := 0.35


static func supports_resume() -> bool:
	return false


## The seeded layout: {target, phase}. Same seed, same layout, on every machine.
static func layout(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var gap := rng.randi_range(MIN_GAP, MAX_GAP)
	var target := START_DIAL + gap if rng.randi() % 2 == 0 else START_DIAL - gap
	return {"target": target, "phase": rng.randf() * TAU}


static func initial_state() -> Dictionary:
	return {"dial": START_DIAL, "holds": 0, "locked": false, "sent": 0}


## The task's puzzle state, cleaned (missing or damaged values fall back to the start).
static func state_of(task: Dictionary) -> Dictionary:
	var raw: Variant = task.get("puzzle_state", {})
	var s := initial_state()
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return s
	var p: Dictionary = raw
	s.dial = clampi(int(p.get("dial", START_DIAL)), 0, DIAL_MAX)
	s.holds = clampi(int(p.get("holds", 0)), 0, HOLD_STEPS)
	s.locked = bool(p.get("locked", false)) and int(s.holds) >= HOLD_STEPS
	s.sent = clampi(int(p.get("sent", 0)), 0, TRANSFER_STEPS) if s.locked else 0
	return s


static func is_match(dial: int, target: int) -> bool:
	return absi(dial - target) <= TOLERANCE


static func validate(task: Dictionary, move: Dictionary) -> Dictionary:
	var rejected := {"accepted": false}
	if float(task.get("progress", 0.0)) >= 1.0:
		return rejected
	var lay := layout(int(task.get("puzzle_seed", 0)))
	var s := state_of(task)
	var value := int(move.get("value", -1))
	match String(move.get("move", "")):
		"tune":
			if bool(s.locked) or value < 0 or value > DIAL_MAX:
				return rejected
			s.dial = value
			s.holds = 0
		"hold":
			if bool(s.locked) or value != int(s.holds) + 1 or not is_match(int(s.dial), int(lay.target)):
				return rejected
			s.holds = value
			s.locked = value >= HOLD_STEPS
		"transfer":
			if not bool(s.locked) or value != int(s.sent) + 1 or value > TRANSFER_STEPS:
				return rejected
			s.sent = value
		"reset":
			if value != 0:
				return rejected
			s = initial_state()
		_:
			return rejected
	var complete := int(s.sent) >= TRANSFER_STEPS
	var progress := 1.0 if complete else minf(0.99, 0.5 * float(s.holds) / HOLD_STEPS + 0.5 * float(s.sent) / TRANSFER_STEPS)
	return {"accepted": true, "puzzle_state": s, "progress": progress, "complete": complete}
