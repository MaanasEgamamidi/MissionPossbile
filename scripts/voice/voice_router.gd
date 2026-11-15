class_name VoiceRouter
extends RefCounted
## Who hears whom, and how (Prompt 11). Pure rules, decided on the listener's machine: nothing here touches nodes,
## audio or the network, so the tests can check every case.
##
## Rule (one route per speaker-listener pair, chosen when an utterance starts and kept until it ends):
##   * Either of the two is outside (CharacterState outside, or seated in the rover while the rover is outside) ->
##     RADIO: not spatial, heard anywhere on the map, indoor listeners included, after the radio stage's delay
##     (CommsStage). Stage 0 has no exterior link: the route is NONE and the HUD says why. Suit to suit outside is
##     radio too: there is almost no air on Mars to carry a voice.
##   * Both inside -> PROXIMITY: immediate. Same zone: full level up to 5 m, a smooth fade to silence at 25 m (distance
##     across the floor). Different zones: only through an open door that joins exactly those two zones (one door, not
##     a chain of doors), along speaker -> door -> listener, at half the level, scaled by how far the door is open; a
##     closed door (or no door between the zones) means silence. The gain is re-read every frame while the utterance
##     plays (people move), but the route itself does not change mid-utterance.
## Zones are ColonyZones zones (rooms, the dome plaza, the garden dome, the exterior). Door portals come from the
## colony manifest (24 room doors) plus any other DoorController the game builds (airlock doors).

## Full level up to this distance, metres (contract).
const FULL_M := 5.0
## Silent from this distance, metres (contract).
const SILENT_M := 25.0
## Level through one open door, relative to the same distance in one room (game balance).
const DOOR_FACTOR := 0.5
## A door less open than this is treated as closed (engineering: the eased door travel, 0..1).
const DOOR_OPEN_MIN := 0.05
## Gains below this are silence (engineering, about -60 dB).
const SILENT_GAIN := 0.001
## How far either side of a door line its two zones are sampled, metres (engineering).
const PORTAL_PROBE_M := 0.6

const ROUTE_NONE := &"none"
const ROUTE_PROXIMITY := &"proximity"
const ROUTE_RADIO := &"radio"


## Level for a distance inside one zone: 1 up to FULL_M, smoothly down to 0 at SILENT_M.
static func fade(distance_m: float) -> float:
	if distance_m <= FULL_M:
		return 1.0
	if distance_m >= SILENT_M:
		return 0.0
	return 1.0 - smoothstep(FULL_M, SILENT_M, distance_m)


## Distance across the floor (x, z), metres. The colony has one floor level.
static func floor_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------- participants

## Seat index (0 = driver) of a character in the rover, or -1.
static func seat_of(state: ColonyState, character_id: StringName) -> int:
	if state == null or String(character_id) == "":
		return -1
	var seats: Variant = state.rover.get("seats", [])
	if not seats is Array:
		return -1
	return (seats as Array).find(String(character_id))


## True when the rover has a stored pose.
static func has_rover_pose(state: ColonyState) -> bool:
	if state == null:
		return false
	var pose: Variant = state.rover.get("pose", {})
	if not pose is Dictionary:
		return false
	var p: Variant = (pose as Dictionary).get("position", [])
	return p is Array and (p as Array).size() >= 3


static func rover_position(state: ColonyState) -> Vector3:
	if not has_rover_pose(state):
		return Vector3.ZERO
	var p: Array = (state.rover.pose as Dictionary).position
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


## What the router needs about one crew member: {"id", "position", "outside", "zone", "seated"}.
## A seated character is where the rover is, and is outside when the rover is outside. With zones the outside test is
## the host's own rule (the Exterior zone) applied to the current position; without zones the replicated flag is used.
static func participant(state: ColonyState, c: CharacterState, zones: ColonyZones) -> Dictionary:
	var pos := c.position
	var seated := seat_of(state, c.id) >= 0
	if seated and has_rover_pose(state):
		pos = rover_position(state)
	var zone := ""
	var outside := c.outside
	if zones != null:
		zone = zones.zone_at_world(pos)
		outside = zone == ColonyZones.EXTERIOR
	return {"id": c.id, "position": pos, "outside": outside, "zone": zone, "seated": seated}


# ---------------------------------------------------------------- doors

## Door portals from the colony manifest: [{"door_id", "zones": [a, b], "point": Vector3 (Godot, floor)}].
## A door's leaves are averaged; the zones are sampled PORTAL_PROBE_M either side of the door line. Doors with the
## same zone on both sides are left out (they change nothing for sound).
static func portals_from_manifest(manifest: Dictionary, zones: ColonyZones) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if zones == null:
		return out
	var leaves := {}
	var order: Array[int] = []
	for o: Variant in manifest.get("objects", []):
		if not o is Dictionary:
			continue
		var obj: Dictionary = o
		if String(obj.get("cls", "")) != "door" or not obj.has("door_id"):
			continue
		var id := int(obj.door_id)
		if not leaves.has(id):
			leaves[id] = []
			order.append(id)
		(leaves[id] as Array).append(obj)
	for id: int in order:
		var sum := Vector2.ZERO
		var list: Array = leaves[id]
		for obj: Dictionary in list:
			var m: Array = obj.get("matrix_world", [])
			sum += Vector2(float(m[0][3]), float(m[1][3]))
		var c := sum / float(list.size())
		var m0: Array = (list[0] as Dictionary).matrix_world
		# Blender local y of the leaf points through the doorway (the leaf slides along its local x).
		var through_bl := Vector2(float(m0[0][1]), float(m0[1][1]))
		# Blender (x, y) -> Godot (x, -y) on the floor
		var p := portal_from_door(id, Vector3(c.x, 0.0, -c.y), Vector3(through_bl.x, 0.0, -through_bl.y), zones)
		if not p.is_empty():
			out.append(p)
	return out


## One portal from a door centre and its through-direction (Godot space), or {} when both sides are one zone.
static func portal_from_door(door_id: int, centre: Vector3, through: Vector3, zones: ColonyZones) -> Dictionary:
	if zones == null:
		return {}
	var dir := Vector3(through.x, 0.0, through.z)
	if dir.length() < 1e-6:
		return {}
	dir = dir.normalized() * PORTAL_PROBE_M
	var a := zones.zone_at_world(centre + dir)
	var b := zones.zone_at_world(centre - dir)
	if a == b:
		return {}
	return {"door_id": door_id, "zones": [a, b], "point": Vector3(centre.x, 0.0, centre.z)}


# ---------------------------------------------------------------- the decision

## The route for one speaker and one listener:
## {"route": ROUTE_*, "gain": 0..1, "delay_s": seconds, "reason": String, "via_door": door id or -1}.
## `door_open` maps door id -> how far it is open (0..1).
static func decide(speaker: Dictionary, listener: Dictionary, p_stage: int, portals: Array, door_open: Dictionary) -> Dictionary:
	var out := {"route": ROUTE_NONE, "gain": 0.0, "delay_s": 0.0, "reason": "", "via_door": -1}
	var s_out := bool(speaker.get("outside", false))
	var l_out := bool(listener.get("outside", false))
	if s_out or l_out:
		if CommsStage.has_link(p_stage):
			out.route = ROUTE_RADIO
			out.gain = 1.0
			out.delay_s = CommsStage.delay_seconds(p_stage)
			out.reason = "speaker_outside" if s_out else "listener_outside"
		else:
			out.reason = "no_radio_link"
		return out
	var g := proximity_gain(speaker, listener, portals, door_open)
	out.route = ROUTE_PROXIMITY
	out.gain = g.gain
	out.reason = g.reason
	out.via_door = g.via_door
	return out


## Level between two people inside: {"gain", "reason", "via_door", "distance_m"}.
## reason: "same_zone", "too_far", "open_door", "door_closed" (a door joins the zones but is shut) or "other_zone".
static func proximity_gain(speaker: Dictionary, listener: Dictionary, portals: Array, door_open: Dictionary) -> Dictionary:
	var a: Vector3 = speaker.get("position", Vector3.ZERO)
	var b: Vector3 = listener.get("position", Vector3.ZERO)
	var za := String(speaker.get("zone", ""))
	var zb := String(listener.get("zone", ""))
	if za == zb:
		var d := floor_distance(a, b)
		var g := _clean(fade(d))
		return {"gain": g, "reason": "same_zone" if g > 0.0 else "too_far", "via_door": -1, "distance_m": d}
	var best := 0.0
	var via := -1
	var best_d := INF
	var joined := false
	for p: Dictionary in portals:
		var pz: Array = p.get("zones", [])
		if pz.size() != 2 or not ((String(pz[0]) == za and String(pz[1]) == zb) or (String(pz[0]) == zb and String(pz[1]) == za)):
			continue
		joined = true
		var open := clampf(float(door_open.get(int(p.door_id), 0.0)), 0.0, 1.0)
		if open < DOOR_OPEN_MIN:
			continue
		var pt: Vector3 = p.point
		var d := floor_distance(a, pt) + floor_distance(pt, b)
		var g := fade(d) * DOOR_FACTOR * open
		if g > best:
			best = g
			via = int(p.door_id)
			best_d = d
	best = _clean(best)
	if best > 0.0:
		return {"gain": best, "reason": "open_door", "via_door": via, "distance_m": best_d}
	return {"gain": 0.0, "reason": "door_closed" if joined else "other_zone", "via_door": -1, "distance_m": INF}


static func _clean(g: float) -> float:
	return g if g >= SILENT_GAIN else 0.0


# ---------------------------------------------------------------- words for the HUD

## What the local player's own transmission does, in words, while voice chat is on (toggled with V).
## `crew_outside`: other players outside right now (only matters when the speaker is inside).
static func speaking_text(me_outside: bool, p_stage: int, crew_outside: int) -> String:
	if me_outside:
		if CommsStage.has_link(p_stage):
			return "● Radio — heard %s" % CommsStage.delay_words(p_stage)
		return "✖ No radio link outside — nobody can hear you yet"
	var text := "● Speaking nearby"
	if crew_outside > 0:
		if CommsStage.has_link(p_stage):
			text += " · crew outside hear you by radio %s" % CommsStage.delay_words(p_stage)
		else:
			text += " · crew outside cannot hear you (no radio link)"
	return text


## The route the local player would use now, before they talk (the idle hint line).
static func idle_text(me_outside: bool, p_stage: int) -> String:
	if me_outside:
		if CommsStage.has_link(p_stage):
			return "Voice chat is off. Press V to turn it on: you are outside, so the radio carries your voice (heard %s)." % CommsStage.delay_words(p_stage)
		return "You are outside and the radio is broken: nobody can hear you. Repair it at the comms console."
	return "Voice chat is off. Press V to turn it on and talk to people near you."


## A line about someone the local player hears (or would hear).
static func heard_text(speaker_name: String, route: StringName, delay_s: float) -> String:
	match route:
		ROUTE_PROXIMITY:
			return "♪ %s — nearby" % speaker_name
		ROUTE_RADIO:
			if delay_s >= 1.0:
				return "♪ %s — by radio, said %d s ago" % [speaker_name, roundi(delay_s)]
			return "♪ %s — by radio" % speaker_name
	return ""


## A radio message that is still inside the radio's buffer.
static func pending_text(speaker_name: String, seconds_left: float) -> String:
	return "… Radio message from %s, heard in %d s" % [speaker_name, maxi(1, ceili(seconds_left))]


## Someone is talking but there is no route to this listener.
static func unheard_text(speaker_name: String, reason: String, listener_outside: bool) -> String:
	if reason == "no_radio_link":
		if listener_outside:
			return "✖ %s is talking, but you are outside and there is no radio link yet" % speaker_name
		return "✖ %s is talking outside, but there is no radio link yet" % speaker_name
	return ""


## Shown for a few seconds when the local player goes outside or comes back in.
static func transition_text(now_outside: bool, p_stage: int) -> String:
	if now_outside:
		if CommsStage.has_link(p_stage):
			return "You are outside now: your voice goes over the radio and is heard %s." % CommsStage.delay_words(p_stage)
		return "You are outside now. The radio is broken, so nobody can hear you until it is repaired."
	return "You are inside now: people near you hear you at once."
