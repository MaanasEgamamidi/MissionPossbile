extends RefCounted
## Suit radio (owner 2026-11-15, docs/revisions/UPGRADE_PATHS_PLAN.md §7.1). Pure rules: no nodes, no audio, no network.
## Loaded by path (no class_name): const SuitRadio := preload("res://scripts/voice/suit_radio.gd")
##
## Who talks over the suit radio. Face to face inside the base is unchanged (VoiceRouter.proximity_gain, heard at
## once). The suit radio carries a voice when
##   * the speaker or the listener is outside (in a suit; seated in the rover counts as where the rover is), or
##   * both are inside but out of earshot of each other (proximity gain 0: too far, or a closed door) and at least one
##     of the two wears a suit (CharacterState.suit_on). Two people inside without suits who cannot hear each other
##     stay unheard, exactly as before.
##
## What the suit radio does, by the Communication level (AreaLevels track "command", 1..max):
##   * suit_radio_delay_s < 0 (level 1: only the tutorial's comms fix) -> NOT SENT. The speaker sees and hears
##     NO_SIGNAL_TEXT once per press of the talk key; the listener sees "is calling, no signal".
##   * otherwise, when either end is AWAY from the comms area -> delay = suit_radio_delay_s real seconds and
##     garble = suit_radio_garble (0..1). Away = outside, or inside farther than suit_radio_area_m from the centre of
##     the Command Room (floor distance). Near the Command Room and inside at both ends -> no delay, no garble.
##   * at the top level the table is 0 s and 0.0: instant and clear everywhere on the map.
## Level tables (data/area_levels.json "command" effects; the defaults below are used when a key is missing):
##   suit_radio_delay_s   [-1, 30, 10, 2, 0]          (-1 = no signal)
##   suit_radio_garble    [1.0, 0.6, 0.3, 0.05, 0.0]
##   suit_radio_area_m    [0, 20, 1000, 1000, 1000]    (level 2 "works near the Command Room", level 3+ the whole base)
## With a 4-level data file and no keys, the top level still gets the last column (instant and clear).
##
## The delay is applied on the LISTENER's machine: VoiceService asks decide() when an utterance starts and hands
## delay_s to VoiceScheduler, which releases each frame at start + delay (real seconds, monotonic clock, never
## shortened). The garble rides along in the utterance's info and is rendered by radio_fx.gd.
##
## ColonyState.comms (plain JSON, saved and replicated; owned by this file). The suit radio needs no stored state today:
## every rule above follows from state.levels.command and the crew's positions, so each machine decides the same way
## and nothing is written. The dictionary stays {} and is reserved for later radio features, with these keys taken:
##   "relay_down_until_hours": float   (reserved: a storm knocking the base relay out until this game hour)
##   "notes": Array of String          (reserved: last radio notices for the comms console)
## Readers must treat a missing key as "not set".
##
## Honest science (SCIENCE_NOTE, for the science panel and the voice settings): real suit-to-suit radio on Mars is
## near-instant; the game's delay stands for a weak signal through a busy base relay. Earth <-> Mars is 4-24 min.

const TRACK := "command"
const ROOM_ZONE := "Command Room"
## Centre of the Command Room in Godot coordinates when no zones are known (manifest room x 24..34, y 10..18).
const ROOM_CENTRE_FALLBACK := Vector3(29.0, 0.0, -14.0)
## Default level tables, index = level - 1 (see the header).
const DEFAULT_DELAY_S: PackedFloat32Array = [-1.0, 30.0, 10.0, 2.0, 0.0]
const DEFAULT_GARBLE: PackedFloat32Array = [1.0, 0.6, 0.3, 0.05, 0.0]
const DEFAULT_AREA_M: PackedFloat32Array = [0.0, 20.0, 1000.0, 1000.0, 1000.0]

const NO_SIGNAL_TEXT := "No signal: the suit radio needs a comms upgrade"
const SCIENCE_NOTE := ("Suit radio: in real life, radio between two spacesuits on Mars is almost instant, because radio "
	+ "waves cross a few kilometres in a few millionths of a second. In the game the delay and the crackle stand for a "
	+ "weak signal squeezed through a busy, half-repaired base relay: each Communication upgrade makes it shorter and "
	+ "clearer (30 s, 10 s, 2 s, then instant). The real delay between Earth and Mars is 4 to 24 minutes, one way, "
	+ "depending on where the two planets are; that is why Mission Control's messages arrive late, and no upgrade "
	+ "of the colony can change it.")

const ROUTE_NONE := &"none"
const ROUTE_PROXIMITY := &"proximity"
const ROUTE_RADIO := &"radio"


# ---------------------------------------------------------------- level values

static func level(state: ColonyState) -> int:
	return AreaLevels.level(state, TRACK)


## The value of one suit radio effect at the current level: the data file's value, else the default table (at the
## top level the table's last column).
static func _value(state: ColonyState, key: String, defaults: PackedFloat32Array) -> float:
	var lvl := level(state)
	var fallback := defaults[clampi(lvl, 1, defaults.size()) - 1]
	if lvl >= AreaLevels.max_level():
		fallback = defaults[defaults.size() - 1]
	return float(AreaLevels.effect(state, TRACK, key, fallback))


## Suit radio delay, real seconds; -1 when the suit radio cannot send.
static func delay_s(state: ColonyState) -> float:
	return _value(state, "suit_radio_delay_s", DEFAULT_DELAY_S)


## Garble away from the comms area, 0 (clear) .. 1 (barely understandable).
static func garble(state: ColonyState) -> float:
	return clampf(_value(state, "suit_radio_garble", DEFAULT_GARBLE), 0.0, 1.0)


## Radius of the comms area around the Command Room, metres.
static func area_m(state: ColonyState) -> float:
	return maxf(0.0, _value(state, "suit_radio_area_m", DEFAULT_AREA_M))


## True when the suit radio sends at all (Communication upgraded past the tutorial fix).
static func has_signal(state: ColonyState) -> bool:
	return delay_s(state) >= 0.0


## Is `actor` within reach of the colony's comms (the build vote's rule): inside the base always; outside only when the
## suit radio has a signal (Communication level >= 2 with the default tables). `zones` may be null (then the
## replicated outside flag is used). This is the authoritative version; colony_builds.gd should call it.
static func in_comms_reach(state: ColonyState, actor: CharacterState, zones: ColonyZones = null) -> bool:
	if state == null or actor == null:
		return false
	if not bool(VoiceRouter.participant(state, actor, zones).outside):
		return true
	return has_signal(state)


# ---------------------------------------------------------------- places

## VoiceRouter.participant plus "suit": whether the character wears a suit.
static func participant(state: ColonyState, c: CharacterState, zones: ColonyZones) -> Dictionary:
	var p := VoiceRouter.participant(state, c, zones)
	p["suit"] = c.suit_on
	return p


## Centre of the Command Room on the floor, Godot coordinates.
static func room_centre(zones: ColonyZones) -> Vector3:
	if zones != null:
		for r: Variant in zones.rooms:
			if r is Dictionary and String((r as Dictionary).get("name", "")) == ROOM_ZONE:
				var d: Dictionary = r
				return Vector3((float(d.x0) + float(d.x1)) * 0.5, 0.0, -(float(d.y0) + float(d.y1)) * 0.5)
	return ROOM_CENTRE_FALLBACK


## True when a participant is inside and within the comms area.
static func near_comms(state: ColonyState, part: Dictionary, zones: ColonyZones) -> bool:
	if bool(part.get("outside", false)):
		return false
	var pos: Vector3 = part.get("position", Vector3(1e6, 0.0, 1e6))
	return VoiceRouter.floor_distance(pos, room_centre(zones)) <= area_m(state)


# ---------------------------------------------------------------- the decision

## The route for one speaker and one listener (both from participant()):
## {"route", "gain", "delay_s", "garble", "reason", "via_door", "away"}.
## reason: proximity reasons ("same_zone", "too_far", "open_door", "door_closed", "other_zone"), or for the radio
## "speaker_outside", "listener_outside", "out_of_earshot", or "no_signal" (route none).
static func decide(state: ColonyState, speaker: Dictionary, listener: Dictionary, zones: ColonyZones, portals: Array, door_open: Dictionary) -> Dictionary:
	var out := {"route": ROUTE_NONE, "gain": 0.0, "delay_s": 0.0, "garble": 0.0, "reason": "", "via_door": -1, "away": false}
	var s_out := bool(speaker.get("outside", false))
	var l_out := bool(listener.get("outside", false))
	if not s_out and not l_out:
		var g := VoiceRouter.proximity_gain(speaker, listener, portals, door_open)
		var suited := bool(speaker.get("suit", false)) or bool(listener.get("suit", false))
		if float(g.gain) > 0.0 or not suited:
			# face to face inside: exactly as before (a silent proximity route when out of earshot without suits)
			out.route = ROUTE_PROXIMITY
			out.gain = g.gain
			out.reason = g.reason
			out.via_door = g.via_door
			return out
	if not has_signal(state):
		out.reason = "no_signal"
		return out
	out.route = ROUTE_RADIO
	out.gain = 1.0
	out.reason = "speaker_outside" if s_out else ("listener_outside" if l_out else "out_of_earshot")
	var away := not near_comms(state, speaker, zones) or not near_comms(state, listener, zones)
	out.away = away
	if away:
		out.delay_s = maxf(0.0, delay_s(state))
		out.garble = garble(state)
	return out


## What the local speaker's voice does now, over every other crew member (participants):
## {"radio": bool (someone is reached, or not reached, by suit radio), "no_signal": bool, "delay_s": longest,
##  "garble": strongest, "nearby": number reached face to face}.
## Alone (no others): the speaker's own place decides (outside = suit radio).
static func speaker_status(state: ColonyState, me: Dictionary, others: Array, zones: ColonyZones, portals: Array, door_open: Dictionary) -> Dictionary:
	var st := {"radio": false, "no_signal": false, "delay_s": 0.0, "garble": 0.0, "nearby": 0}
	if others.is_empty():
		if bool(me.get("outside", false)):
			st.radio = true
			if not has_signal(state):
				st.no_signal = true
			elif not near_comms(state, me, zones):
				st.delay_s = maxf(0.0, delay_s(state))
				st.garble = garble(state)
		return st
	for o: Variant in others:
		if not o is Dictionary:
			continue
		var r := decide(state, me, o as Dictionary, zones, portals, door_open)
		match r.route:
			ROUTE_RADIO:
				st.radio = true
				st.delay_s = maxf(float(st.delay_s), float(r.delay_s))
				st.garble = maxf(float(st.garble), float(r.garble))
			ROUTE_PROXIMITY:
				if float(r.gain) > 0.0:
					st.nearby = int(st.nearby) + 1
			_:
				if String(r.reason) == "no_signal":
					st.radio = true
					st.no_signal = true
	return st


# ---------------------------------------------------------------- words

## "crackly", "some crackle", "a little crackle" or "" for a garble amount.
static func garble_words(g: float) -> String:
	if g >= 0.5:
		return "crackly, words drop out"
	if g >= 0.15:
		return "some crackle"
	if g > 0.0:
		return "a little crackle"
	return ""


## The talking indicator: "📡 Radio: delay 30 s (crackly, words drop out)" or "📡 Radio: clear, no delay".
static func radio_indicator(p_delay_s: float, p_garble: float) -> String:
	var words := garble_words(p_garble)
	if p_delay_s >= 0.5:
		return "📡 Radio: delay %d s%s" % [roundi(p_delay_s), " (%s)" % words if words != "" else ""]
	if words != "":
		return "📡 Radio: no delay (%s)" % words
	return "📡 Radio: clear, no delay"


## The speaker's own line while holding the talk key.
static func speaking_text(status: Dictionary) -> String:
	if bool(status.get("no_signal", false)):
		return "✖ " + NO_SIGNAL_TEXT
	var nearby := int(status.get("nearby", 0)) > 0
	if bool(status.get("radio", false)):
		var radio := radio_indicator(float(status.get("delay_s", 0.0)), float(status.get("garble", 0.0)))
		return "● Speaking nearby · " + radio if nearby else "● " + radio
	return "● Speaking nearby"


## The idle hint before talking.
static func idle_text(state: ColonyState, me: Dictionary, zones: ColonyZones) -> String:
	if bool(me.get("outside", false)):
		if not has_signal(state):
			return "You are outside and the suit radio has no signal: nobody can hear you. Upgrade Communication in the Command Room."
		if near_comms(state, me, zones):
			return "Hold V to talk: your suit radio carries your voice, clear and at once."
		var words := garble_words(garble(state))
		return "Hold V to talk: your suit radio carries your voice (delay %d s%s)." % [roundi(maxf(0.0, delay_s(state))),
			", " + words if words != "" else ""]
	return "Hold V to talk to people near you."


## Shown for a few seconds after going outside or coming in.
static func transition_text(state: ColonyState, now_outside: bool) -> String:
	if now_outside:
		if not has_signal(state):
			return "You are outside now. " + NO_SIGNAL_TEXT + ": nobody can hear you."
		var d := delay_s(state)
		if d <= 0.0 and garble(state) <= 0.0:
			return "You are outside now: your suit radio is instant and clear."
		return "You are outside now: your voice goes over the suit radio, heard after %d s%s." % [roundi(d),
			", " + garble_words(garble(state)) if garble_words(garble(state)) != "" else ""]
	return "You are inside now: people near you hear you at once."


## A line about someone the local player hears now.
static func heard_text(speaker_name: String, route: StringName, said_ago_s: float, p_garble: float) -> String:
	match route:
		ROUTE_PROXIMITY:
			return "♪ %s — nearby" % speaker_name
		ROUTE_RADIO:
			var words := garble_words(p_garble)
			var tail := " (%s)" % words if words != "" else ""
			if said_ago_s >= 1.0:
				return "📡 %s — suit radio, said %d s ago%s" % [speaker_name, roundi(said_ago_s), tail]
			return "📡 %s — suit radio%s" % [speaker_name, tail]
	return ""


## A suit radio message still travelling (delayed) to this listener.
static func pending_text(speaker_name: String, seconds_left: float) -> String:
	return "📡 Incoming (delayed) from %s: heard in %d s" % [speaker_name, maxi(1, ceili(seconds_left))]


## Someone is talking but nothing reaches this listener.
static func unheard_text(speaker_name: String, reason: String) -> String:
	if reason == "no_signal":
		return "✖ %s is calling on the suit radio, but there is no signal (Communication upgrade needed)" % speaker_name
	return ""


## One line for the comms panels: "Suit radio V2: delay 30 s away from the Command Room, crackly."
static func status_text(state: ColonyState) -> String:
	var lvl := level(state)
	if not has_signal(state):
		return "Suit radio (Communication V%d): no signal outside or out of earshot. Upgrade Communication to use it." % lvl
	var d := delay_s(state)
	var g := garble(state)
	if d <= 0.0 and g <= 0.0:
		return "Suit radio (Communication V%d): instant and clear everywhere on the map." % lvl
	var words := garble_words(g)
	return "Suit radio (Communication V%d): delay %d s%s away from the comms area; clear and instant near the Command Room." % [
		lvl, roundi(d), ", " + words if words != "" else ""]


## The explanation for the voice settings and the science panel.
static func explanation() -> String:
	return SCIENCE_NOTE
