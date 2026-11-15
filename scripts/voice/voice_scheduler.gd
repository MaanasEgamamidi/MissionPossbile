class_name VoiceScheduler
extends RefCounted
## The voice packet format and the listener's timed buffer (Prompt 11). Pure: it never touches audio, nodes or the
## network, and time is always passed in (seconds on the listener's monotonic clock), so the tests can run a 30 s
## radio delay in no time.
##
## Packet (little-endian), the same small header on every packet:
##   0 u8 magic 'V'   1 u8 version   2 u8 kind (1 start, 2 frame, 3 end)   3 u8 flags (0)
##   4 u16 stream id (random per voice session of the speaker)   6 u16 utterance sequence   8 u16 frame number
##   (end: number of frames)   10 u32 utterance start, speaker's monotonic ms   14 u32 this packet's send time, same clock
##   18 u8 n = character id bytes, 19.. the speaker's character id (UTF-8, at most 32 bytes)
##   then  start: u32 sample rate, u16 samples per frame, u8 channels  |  frame: one Opus packet  |  end: nothing.
## NetSession sends every voice packet reliable and ordered (frames sent unreliable were dropped by ENet's throttle; see
## NetSession.send_voice). The scheduler still tolerates disorder and loss: any packet of an utterance can open it, so a frame that
## overtakes its start packet is not lost.
##
## Schedule. The intentional radio delay is equipment buffering, fixed per utterance from the stage when it starts:
##   due(i) = start_local + delay + JITTER_S + i * FRAME_S
## start_local is the listener's arrival time of the first packet seen, back-dated by the speaker's own elapsed time
## for that packet. Network jitter handling only runs after that schedule: a reorder window (JITTER_S), Opus FEC for a
## missing frame when the next one is there, and the playback buffer target (PLAYBACK_TARGET_S, in VoiceService).
## There is no catch-up: nothing is ever played faster or released earlier than its due time, so a 30 s delay is
## never shortened. When the stream stalls (no newer packet at all), the schedule waits and then restarts the reorder
## window from the next packet, which only ever adds delay.
##
## Lanes. A speaker has one lane per route (proximity, radio). Utterances in a lane are presented strictly in order: a
## later utterance never starts before the one before it has finished, so a stage upgrade (a shorter delay) applies to
## new utterances and never makes them overtake speech already in the radio. Proximity speech is not radio speech:
## it is heard at once, even while an older radio message from the same person is still in the radio.
##
## Bounds: per speaker at most MAX_QUEUE_FRAMES frames (MAX_QUEUE_S of audio) and MAX_UTTERANCES utterances waiting;
## all speakers together at most MAX_TOTAL_FRAMES. Over a bound, the oldest whole utterance is dropped with a note.

const MAGIC := 0x56
const VERSION := 1
const KIND_START := 1
const KIND_FRAME := 2
const KIND_END := 3
## Bytes of the header before the character id.
const FIXED_HEADER := 19
const MAX_ID_BYTES := 32

## Opus stream format (engineering): 48 kHz mono, 20 ms frames.
const SAMPLE_RATE := 48000
const FRAME_SAMPLES := 960
const FRAME_S := 0.02
const CHANNELS := 1

## Reorder window after the schedule, seconds (engineering).
const JITTER_S := 0.08
## Audio queued in the player before it starts, seconds (engineering; used by VoiceService).
const PLAYBACK_TARGET_S := 0.04
## Waiting audio per speaker, seconds and frames (40 s = 2000 frames of 20 ms; above the 30 s longest delay).
const MAX_QUEUE_S := 40.0
const MAX_QUEUE_FRAMES := 2000
## Waiting utterances per speaker.
const MAX_UTTERANCES := 16
## Waiting frames of all speakers together (three other players at the per-speaker bound).
const MAX_TOTAL_FRAMES := 6000
## An utterance with no packet for this long while it waits for one is ended ("timeout").
const STALL_S := 1.0
## Longest utterance in frames (60 s). The speaker ends and restarts an utterance held longer.
const MAX_UTTERANCE_FRAMES := 3000
## Notes kept for the HUD and the tests.
const MAX_NOTES := 32

## Counters since this scheduler was made.
var stats := {"opened": 0, "late": 0, "duplicate": 0, "fec": 0, "lost": 0, "stalls": 0, "timeouts": 0,
	"dropped_utterances": 0, "dropped_frames": 0, "unrouted": 0, "rejected": 0, "released": 0}
## Plain-language notes about dropped or cleared speech, newest last.
var notes: PackedStringArray = []

# peer -> {"stream": int, "last_seq": int, "lanes": {lane: Array of utterance dictionaries}}
var _speakers := {}
var _events: Array[Dictionary] = []


# ================================================================ packets

## A packet header (start packets get their format appended by make_start).
static func make_header(kind: int, stream_id: int, seq: int, index: int, start_ms: int, send_ms: int, character_id: String) -> PackedByteArray:
	var id_bytes := character_id.to_utf8_buffer()
	if id_bytes.size() > MAX_ID_BYTES:
		id_bytes = id_bytes.slice(0, MAX_ID_BYTES)
	var p := PackedByteArray()
	p.resize(FIXED_HEADER + id_bytes.size())
	p[0] = MAGIC
	p[1] = VERSION
	p[2] = kind
	p[3] = 0
	p.encode_u16(4, stream_id & 0xffff)
	p.encode_u16(6, seq & 0xffff)
	p.encode_u16(8, index & 0xffff)
	p.encode_u32(10, start_ms & 0xffffffff)
	p.encode_u32(14, send_ms & 0xffffffff)
	p[18] = id_bytes.size()
	for i in id_bytes.size():
		p[FIXED_HEADER + i] = id_bytes[i]
	return p


## The start packet of an utterance.
static func make_start(stream_id: int, seq: int, start_ms: int, send_ms: int, character_id: String) -> PackedByteArray:
	var p := make_header(KIND_START, stream_id, seq, 0, start_ms, send_ms, character_id)
	var at := p.size()
	p.resize(at + 7)
	p.encode_u32(at, SAMPLE_RATE)
	p.encode_u16(at + 4, FRAME_SAMPLES)
	p[at + 6] = CHANNELS
	return p


## The end packet: `frames` frames were sent.
static func make_end(stream_id: int, seq: int, frames: int, start_ms: int, send_ms: int, character_id: String) -> PackedByteArray:
	return make_header(KIND_END, stream_id, seq, frames, start_ms, send_ms, character_id)


## A frame packet: header then the Opus bytes (VoiceService gives the header to the encoder as its prefix instead).
static func make_frame(stream_id: int, seq: int, index: int, start_ms: int, send_ms: int, character_id: String, opus: PackedByteArray) -> PackedByteArray:
	var p := make_header(KIND_FRAME, stream_id, seq, index, start_ms, send_ms, character_id)
	p.append_array(opus)
	return p


## The parsed header: {"kind", "stream", "seq", "index", "start_ms", "send_ms", "character", "header_len"} plus
## "sample_rate", "frame_samples", "channels" for a start packet. {} for anything that is not a valid packet.
static func parse(p: PackedByteArray) -> Dictionary:
	if p.size() < FIXED_HEADER or p[0] != MAGIC or p[1] != VERSION:
		return {}
	var kind := int(p[2])
	if kind < KIND_START or kind > KIND_END:
		return {}
	var n := int(p[18])
	if n > MAX_ID_BYTES or p.size() < FIXED_HEADER + n:
		return {}
	var hl := FIXED_HEADER + n
	var d := {"kind": kind, "stream": p.decode_u16(4), "seq": p.decode_u16(6), "index": p.decode_u16(8),
		"start_ms": p.decode_u32(10), "send_ms": p.decode_u32(14), "character": p.slice(FIXED_HEADER, hl).get_string_from_utf8(),
		"header_len": hl}
	if kind == KIND_START:
		if p.size() < hl + 7:
			return {}
		d["sample_rate"] = p.decode_u32(hl)
		d["frame_samples"] = p.decode_u16(hl + 4)
		d["channels"] = int(p[hl + 6])
	elif kind == KIND_FRAME and p.size() <= hl:
		return {}
	return d


## Seconds the speaker had been talking when it sent this packet (0 when the clock values make no sense).
static func elapsed_s(header: Dictionary) -> float:
	var ms := (int(header.get("send_ms", 0)) - int(header.get("start_ms", 0))) & 0xffffffff
	if ms > 0x7fffffff:
		return 0.0
	return float(ms) / 1000.0


## True when 16-bit sequence `a` is newer than `b` (wraps around).
static func seq_newer(a: int, b: int) -> bool:
	var d := (a - b) & 0xffff
	return d >= 1 and d <= 32767


# ================================================================ receiving

## What a packet of utterance `seq` is to this scheduler: &"new" (open it), &"queued" (it is waiting or playing) or
## &"old" (finished, unrouted, cleared or older than the newest one: drop it).
func classify(peer: int, stream: int, seq: int) -> StringName:
	if not _speakers.has(peer):
		return &"new"
	var sp: Dictionary = _speakers[peer]
	if int(sp.stream) != stream:
		return &"new"
	var last := int(sp.last_seq)
	if last < 0 or seq_newer(seq, last):
		return &"new"
	# the newest one, or an older one still waiting in its lane
	return &"queued" if not _find(peer, seq).is_empty() else &"old"


## Opens utterance `seq` of `peer` in `lane` ("proximity" or "radio"); `lane` empty = no route for this listener (the
## utterance is remembered so its packets are dropped, nothing is queued). start_local: listener seconds when the
## speaker started; delay_s: the intentional delay, fixed for this utterance. Returns true when queued.
func open(peer: int, stream: int, seq: int, lane: StringName, start_local: float, delay_s: float, info := {}, now := -1.0) -> bool:
	var sp: Dictionary = _speakers.get(peer, {})
	if sp.is_empty() or int(sp.stream) != stream:
		if not sp.is_empty():
			_drop_speaker_utterances(peer, &"restarted")
			_note("Voice from player %d restarted; their old speech was cleared." % peer)
		sp = {"stream": stream, "last_seq": -1, "lanes": {}}
		_speakers[peer] = sp
	if int(sp.last_seq) >= 0 and not seq_newer(seq, int(sp.last_seq)):
		return false
	sp.last_seq = seq
	if lane == &"":
		stats.unrouted += 1
		return false
	var u := {"peer": peer, "lane": lane, "seq": seq, "start_local": start_local, "delay_s": maxf(0.0, delay_s),
		"base": start_local + maxf(0.0, delay_s), "info": info.duplicate(), "frames": {}, "next": 0, "max_index": -1,
		"ended": false, "total": -1, "started": false, "held": false, "shift": false,
		"last_rx": now if now >= 0.0 else start_local}
	var lanes: Dictionary = sp.lanes
	if not lanes.has(lane):
		lanes[lane] = []
	(lanes[lane] as Array).append(u)
	stats.opened += 1
	_enforce(peer)
	return true


## Queues one frame. Returns &"queued", &"late" (its time has passed), &"duplicate", &"unknown" (no such utterance
## waiting) or &"rejected" (a frame number that cannot be right).
func push_frame(peer: int, stream: int, seq: int, index: int, packet: PackedByteArray, prefix_len: int, now: float) -> StringName:
	var u := _find_stream(peer, stream, seq)
	if u.is_empty():
		return &"unknown"
	if index < 0 or index >= MAX_UTTERANCE_FRAMES or (int(u.total) >= 0 and index >= int(u.total)):
		stats.rejected += 1
		return &"rejected"
	if index < int(u.next):
		stats.late += 1
		return &"late"
	var frames: Dictionary = u.frames
	if frames.has(index):
		stats.duplicate += 1
		return &"duplicate"
	frames[index] = [packet, prefix_len]
	u.max_index = maxi(int(u.max_index), index)
	u.last_rx = now
	_enforce(peer)
	return &"queued"


## The speaker says utterance `seq` had `total` frames.
func end(peer: int, stream: int, seq: int, total: int, now: float) -> void:
	var u := _find_stream(peer, stream, seq)
	if u.is_empty():
		return
	u.ended = true
	u.total = clampi(total, 0, MAX_UTTERANCE_FRAMES)
	u.last_rx = now
	# frames numbered past the end cannot be part of it
	for i: int in (u.frames as Dictionary).keys():
		if i >= int(u.total):
			(u.frames as Dictionary).erase(i)


## Everything whose time has come, in order per lane:
##   {"type": &"start", ...}  first frame of an utterance is due: prepare its player (paused until the buffer target)
##   {"type": &"frame", "index", "packet", "prefix", "fec": false}   decode this frame
##   {"type": &"frame", "index", "packet" (of the NEXT frame), "fec": true}   rebuild a missing frame from the next one
##   {"type": &"lost", "index"}   a frame that never came (later ones did)
##   {"type": &"end", "reason": &"footer" | &"timeout" | &"dropped" | &"cleared" | &"restarted"}
## Every event also has "peer", "lane", "seq", "delay_s", "start_local" and "info".
func pop_due(now: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = _events
	_events = []
	for peer: int in _speakers.keys():
		var lanes: Dictionary = (_speakers[peer] as Dictionary).lanes
		for lane: StringName in lanes.keys():
			var list: Array = lanes[lane]
			while not list.is_empty():
				var u: Dictionary = list[0]
				if bool(u.shift):
					# it waited for the one before it: its whole schedule moves so it starts now, never earlier
					u.shift = false
					u.base = maxf(float(u.base), now - JITTER_S)
				if not _advance(u, now, out):
					break
				list.pop_front()
				if not list.is_empty():
					(list[0] as Dictionary).shift = true
	return out


## Releases what is due in one utterance. Returns true when it has finished.
func _advance(u: Dictionary, now: float, out: Array[Dictionary]) -> bool:
	var frames: Dictionary = u.frames
	while true:
		var n := int(u.next)
		if bool(u.ended) and n >= int(u.total):
			if bool(u.started):
				out.append(_event(u, &"end", {"reason": &"footer"}))
			return true
		var due := float(u.base) + JITTER_S + float(n) * FRAME_S
		if bool(u.held):
			# the stream stalled: go on from the first packet that came after the stall; the rest of the schedule
			# moves later by the stall (never earlier)
			if frames.has(n) or frames.has(n + 1) or int(u.max_index) > n:
				u.held = false
				u.base = maxf(float(u.base), now - JITTER_S - float(n) * FRAME_S)
				due = float(u.base) + JITTER_S + float(n) * FRAME_S
			elif now - float(u.last_rx) > STALL_S:
				stats.timeouts += 1
				if bool(u.started):
					out.append(_event(u, &"end", {"reason": &"timeout"}))
				return true
			else:
				return false
		if now < due:
			if not bool(u.ended) and now - float(u.last_rx) > STALL_S and int(u.max_index) < n:
				stats.timeouts += 1
				if bool(u.started):
					out.append(_event(u, &"end", {"reason": &"timeout"}))
				return true
			return false
		if frames.has(n):
			_start_if_needed(u, out)
			var f: Array = frames[n]
			frames.erase(n)
			out.append(_event(u, &"frame", {"index": n, "packet": f[0], "prefix": f[1], "fec": false}))
			stats.released += 1
			u.next = n + 1
		elif frames.has(n + 1):
			_start_if_needed(u, out)
			var g: Array = frames[n + 1]
			out.append(_event(u, &"frame", {"index": n, "packet": g[0], "prefix": g[1], "fec": true}))
			stats.fec += 1
			u.next = n + 1
		elif bool(u.ended) or int(u.max_index) > n:
			if bool(u.started):
				out.append(_event(u, &"lost", {"index": n}))
			stats.lost += 1
			u.next = n + 1
		else:
			# nothing at or after this frame yet: wait for it (never skip ahead of the speaker)
			u.held = true
			stats.stalls += 1
			return false
	return false


func _start_if_needed(u: Dictionary, out: Array[Dictionary]) -> void:
	if not bool(u.started):
		u.started = true
		out.append(_event(u, &"start", {}))


func _event(u: Dictionary, type: StringName, extra: Dictionary) -> Dictionary:
	var e := {"type": type, "peer": u.peer, "lane": u.lane, "seq": u.seq, "delay_s": u.delay_s, "start_local": u.start_local, "info": u.info}
	e.merge(extra, true)
	return e


# ================================================================ clearing and bounds

## Clears one speaker's waiting and playing speech (mute). Packets of those utterances that still arrive are dropped;
## the speaker's next utterance is heard normally. Started utterances get an "end" event (reason &"cleared").
func clear_speaker(peer: int, reason := "muted") -> int:
	if not _speakers.has(peer):
		return 0
	var n := _drop_speaker_utterances(peer, &"cleared")
	if n > 0:
		_note("Cleared %d waiting voice message(s) from player %d (%s)." % [n, peer, reason])
	return n


## Forgets a speaker completely (they left the session).
func forget_speaker(peer: int, reason := "left") -> int:
	var n := clear_speaker(peer, reason)
	_speakers.erase(peer)
	return n


## Clears everything (leaving the session). Returns the number of utterances cleared.
func clear_all(reason := "session ended") -> int:
	var n := 0
	for peer: int in _speakers.keys():
		n += _drop_speaker_utterances(peer, &"cleared")
	_speakers.clear()
	if n > 0:
		_note("Cleared %d waiting voice message(s): %s." % [n, reason])
	return n


func _drop_speaker_utterances(peer: int, reason: StringName) -> int:
	var sp: Dictionary = _speakers.get(peer, {})
	if sp.is_empty():
		return 0
	var n := 0
	for lane: StringName in (sp.lanes as Dictionary).keys():
		for u: Dictionary in (sp.lanes[lane] as Array):
			if bool(u.started):
				_events.append(_event(u, &"end", {"reason": reason}))
			n += 1
		(sp.lanes[lane] as Array).clear()
	return n


## Applies the per-speaker and global bounds by dropping the oldest whole utterances.
func _enforce(peer: int) -> void:
	while queued_frames(peer) > MAX_QUEUE_FRAMES or utterance_count(peer) > MAX_UTTERANCES:
		if not _drop_oldest(peer, "player %d had more than %d s or %d messages waiting" % [peer, roundi(MAX_QUEUE_S), MAX_UTTERANCES]):
			break
	while queued_frames() > MAX_TOTAL_FRAMES:
		if not _drop_oldest(-1, "more than %d frames waiting in all" % MAX_TOTAL_FRAMES):
			break


func _drop_oldest(peer: int, why: String) -> bool:
	var best: Dictionary = {}
	var best_list: Array = []
	for p: int in _speakers:
		if peer >= 0 and p != peer:
			continue
		for lane: StringName in ((_speakers[p] as Dictionary).lanes as Dictionary):
			var list: Array = (_speakers[p] as Dictionary).lanes[lane]
			if list.is_empty():
				continue
			var u: Dictionary = list[0]
			if best.is_empty() or float(u.start_local) < float(best.start_local):
				best = u
				best_list = list
	if best.is_empty():
		return false
	best_list.pop_front()
	if bool(best.started):
		_events.append(_event(best, &"end", {"reason": &"dropped"}))
	stats.dropped_utterances += 1
	stats.dropped_frames += (best.frames as Dictionary).size()
	_note("Dropped the oldest voice message from player %d (%d frames): %s." % [int(best.peer), (best.frames as Dictionary).size(), why])
	if not best_list.is_empty():
		(best_list[0] as Dictionary).shift = true
	return true


func _note(text: String) -> void:
	notes.append(text)
	while notes.size() > MAX_NOTES:
		notes.remove_at(0)


# ================================================================ reading

## Frames waiting (not yet released) for one speaker, or for everyone when `peer` < 0.
func queued_frames(peer := -1) -> int:
	var n := 0
	for p: int in _speakers:
		if peer >= 0 and p != peer:
			continue
		for lane: StringName in ((_speakers[p] as Dictionary).lanes as Dictionary):
			for u: Dictionary in ((_speakers[p] as Dictionary).lanes[lane] as Array):
				n += (u.frames as Dictionary).size()
	return n


## Seconds of audio waiting for one speaker (or everyone).
func queued_seconds(peer := -1) -> float:
	return float(queued_frames(peer)) * FRAME_S


## Utterances waiting or playing for one speaker (or everyone).
func utterance_count(peer := -1) -> int:
	var n := 0
	for p: int in _speakers:
		if peer >= 0 and p != peer:
			continue
		for lane: StringName in ((_speakers[p] as Dictionary).lanes as Dictionary):
			n += ((_speakers[p] as Dictionary).lanes[lane] as Array).size()
	return n


## Speakers this scheduler knows (including cleared ones it still remembers).
func speakers() -> Array[int]:
	var out: Array[int] = []
	for p: int in _speakers:
		out.append(p)
	return out


## Every utterance waiting or playing: [{"peer", "lane", "seq", "started", "delay_s", "start_local", "due0", "info"}],
## in lane order.
func utterances() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: int in _speakers:
		for lane: StringName in ((_speakers[p] as Dictionary).lanes as Dictionary):
			for u: Dictionary in ((_speakers[p] as Dictionary).lanes[lane] as Array):
				out.append({"peer": p, "lane": lane, "seq": u.seq, "started": u.started, "delay_s": u.delay_s,
					"start_local": u.start_local, "due0": float(u.base) + JITTER_S, "info": u.info})
	return out


## The waiting utterance record (internal dictionary) or {}.
func _find(peer: int, seq: int) -> Dictionary:
	var sp: Dictionary = _speakers.get(peer, {})
	if sp.is_empty():
		return {}
	for lane: StringName in (sp.lanes as Dictionary):
		for u: Dictionary in (sp.lanes[lane] as Array):
			if int(u.seq) == seq:
				return u
	return {}


func _find_stream(peer: int, stream: int, seq: int) -> Dictionary:
	var sp: Dictionary = _speakers.get(peer, {})
	if sp.is_empty() or int(sp.stream) != stream:
		return {}
	return _find(peer, seq)
