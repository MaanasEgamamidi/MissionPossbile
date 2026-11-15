extends RefCounted
## T03 Rings host rule (Power Room distributor cabinets, any crew). Owner: "Stop each spinning ring when its marker
## lines up." Pack T03: three numbered rings, each with a pointer and a marked sector; a hit locks that channel and
## moves on; a miss resets only the active ring; success is decided by the host, never by a client "hit" flag.
##
## Timing the host can verify: every ring's pointer angle is a pure function of the seed and the time since that
## ring (re)started spinning:  angle(t) = start + dir * speed * t  (degrees, t in seconds).
## The panel starts the ring's clock when the ring starts, measures t at the moment of the key/click (input time, so
## low frame rates and LAN latency do not matter), and sends it. The host recomputes the angle from the seeded
## start/speed/direction and accepts the stop only if the pointer is inside the marked sector. A false stop (a time
## whose angle misses the sector) is rejected; it cannot lock a channel.
## Numbers (designer balance): speed 60..100 deg/s (one turn every 3.6..6 s), sector WINDOW_DEG either side of the
## mark (ASSIST_WINDOW_DEG with the "wide window" help on), the first pass over the mark 1.2..2.5 s after the start.
## Moves:
##   stop    value = ring * RING_FACTOR + t_ms. ring must be the active ring (0..2), t_ms in MIN_STOP_MS..MAX_STOP_MS.
##           A hit locks the ring and makes the next ring active. A miss / replay / wrong ring is rejected.
##   assist  value 0 or 1: the accessibility "wide window" setting (pack T03 point 3). Stored in the puzzle state.
##   reset   value 0: all three rings unlock (the assist setting stays).
## puzzle_state = {"ring": rings locked so far 0..3, "assist": bool}. progress = ring / 3; complete at 3.
## Resumes from disk (locked rings stay locked).

const RINGS := 3
const WINDOW_DEG := 20.0
const ASSIST_WINDOW_DEG := 32.0
const RING_FACTOR := 1000000
const MIN_STOP_MS := 300
const MAX_STOP_MS := 600000


static func supports_resume() -> bool:
	return true


## {"rings": [{start, speed, dir, mark, first_ms}] x3}. first_ms = the first time the pointer is exactly on the mark.
static func layout(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rings: Array = []
	for i in RINGS:
		var speed := float(60 + 10 * i + rng.randi_range(0, 10))
		var dir := 1 if rng.randi() % 2 == 0 else -1
		var mark := float(rng.randi_range(0, 359))
		var first_ms := rng.randi_range(1200, 2500)
		var start := fposmod(mark - dir * speed * first_ms / 1000.0, 360.0)
		rings.append({"start": start, "speed": speed, "dir": dir, "mark": mark, "first_ms": first_ms})
	return {"rings": rings}


## Pointer angle (degrees 0..360) of a ring t_ms after it started.
static func angle_at(ring: Dictionary, t_ms: int) -> float:
	return fposmod(float(ring.start) + float(ring.dir) * float(ring.speed) * float(t_ms) / 1000.0, 360.0)


## Smallest angle between the pointer and the mark (0..180).
static func offset_deg(ring: Dictionary, t_ms: int) -> float:
	return absf(fposmod(angle_at(ring, t_ms) - float(ring.mark) + 180.0, 360.0) - 180.0)


static func window(assist: bool) -> float:
	return ASSIST_WINDOW_DEG if assist else WINDOW_DEG


static func state_of(task: Dictionary) -> Dictionary:
	var raw: Variant = task.get("puzzle_state", {})
	var s := {"ring": 0, "assist": false}
	if raw is Dictionary:
		s.ring = clampi(int((raw as Dictionary).get("ring", 0)), 0, RINGS)
		s.assist = bool((raw as Dictionary).get("assist", false))
	return s


static func validate(task: Dictionary, move: Dictionary) -> Dictionary:
	var rejected := {"accepted": false}
	if float(task.get("progress", 0.0)) >= 1.0:
		return rejected
	var s := state_of(task)
	var value := int(move.get("value", -1))
	match String(move.get("move", "")):
		"stop":
			if value < 0 or int(s.ring) >= RINGS:
				return rejected
			var ring_index := value / RING_FACTOR
			var t_ms := value % RING_FACTOR
			if ring_index != int(s.ring) or t_ms < MIN_STOP_MS or t_ms > MAX_STOP_MS:
				return rejected
			var ring: Dictionary = layout(int(task.get("puzzle_seed", 0))).rings[ring_index]
			if offset_deg(ring, t_ms) > window(bool(s.assist)):
				return rejected
			s.ring = ring_index + 1
		"assist":
			if value != 0 and value != 1:
				return rejected
			s.assist = value == 1
		"reset":
			if value != 0:
				return rejected
			s.ring = 0
		_:
			return rejected
	var complete := int(s.ring) >= RINGS
	return {"accepted": true, "puzzle_state": s, "progress": 1.0 if complete else float(s.ring) / RINGS, "complete": complete}
