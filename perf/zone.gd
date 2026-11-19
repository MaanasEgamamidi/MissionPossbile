class_name Zone
extends Node3D
## One room of the colony (or the dome plaza, or the garden dome), for the perf overhaul's sleep/wake system.
##
## Adapted to this project (docs/perf/phase_2.md): the colony is one imported map whose meshes are merged across rooms
## and already carry one render layer per lighting zone (ColonyZones, layers 1..18). Rooms therefore cannot be split
## into Static/Dynamic child nodes without rebuilding the map. Instead a Zone is a small runtime node that owns:
##   drawn   its render layer bit in the gameplay camera's cull mask (ZoneManager clears the bit of a COLD zone, so
##           nothing of that room is drawn; walls shared with a drawn room carry both bits and stay)
##   lights  its fixture lights (ZoneLighting.set_zone_awake), composed with the power simulation's on/off
##   hooks   optional nodes with _zone_state_changed(new_state: int), in extra_dynamic
## Hidden meshes still cast sun shadows (light masks are untouched) and all collision is separate (WorldCollision), so
## nothing about physics or shadows on visible rooms changes.
##
## States (ordered, so comparisons like state >= State.WARM work):
##   COLD      not drawn, fixture lights off
##   VIEW_ONLY drawn, lights on (seen through glass, or from outside the colony)
##   WARM      drawn, lights on, hooks told it is awake (rooms next to the player)
##   ACTIVE    as WARM (room the player is in)

enum State { COLD, VIEW_ONLY, WARM, ACTIVE }

const HOOK_CHUNK := 16
const KIND_ROOM := &"room"
const KIND_PLAZA := &"plaza"
const KIND_GARDEN := &"garden"

var zone_id: StringName
var kind: StringName = KIND_ROOM
var has_exterior_view := false   ## a window, glass door or open dome onto Mars (or onto the plaza under the glass dome)
var render_bit := 0              ## ColonyZones.bit_of(zone_id)
var rect := Rect2()              ## Godot x / z extent of the room (z = -Blender y)
var floor_y := -1.0
var ceiling_y := 3.5
var centre := Vector3.ZERO
var radius := 0.0                ## garden dome only
var extra_dynamic: Array[Node] = []  ## optional: nodes that throttle themselves through _zone_state_changed

var state: int = State.ACTIVE
var drawn := true                ## what is applied right now (the target may differ while steps are queued)
var lights_awake := true
## Light view (ZoneManager, 2026-11-18): false while the camera cannot see into this zone, so its fixture lights are
## switched off even though the zone is drawn. True whenever the light view switch is off.
var in_view := true
## Light view shadows: false while the camera is neither in this zone nor next to a door into it, so its fixture
## lights draw no shadow maps (seen through glass the difference is within run-to-run noise). True when switched off.
var shadows_on := true
var neighbors: Array[Zone] = []

var _tid := 0
var _manager: Node               ## ZoneManager
var _hooks: Array[Node] = []


func setup(manager: Node) -> void:
	_manager = manager
	add_to_group(&"zone")
	refresh_hooks()


func refresh_hooks() -> void:
	_hooks.clear()
	for n in extra_dynamic:
		if is_instance_valid(n) and n.has_method(&"_zone_state_changed"):
			_hooks.append(n)


## Is the point inside this zone? `margin` grows the bounds (sticky lookup, doorway overlap).
func contains_point(p: Vector3, margin := 0.0) -> bool:
	match kind:
		KIND_ROOM:
			return p.y > floor_y - margin and p.y < ceiling_y + 0.3 + margin and rect.grow(margin).has_point(Vector2(p.x, p.z))
		_:
			return _manager.outside_kind_at(p) == kind and _manager.room_at(p, -margin) == null


## Distance from a point to this zone's bounds (0 when inside).
func distance_to_bounds(p: Vector3) -> float:
	if kind == KIND_GARDEN:
		return maxf(Vector2(p.x - centre.x, p.z - centre.z).length() - radius, 0.0)
	var q := Vector2(maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), 0.0), maxf(maxf(rect.position.y - p.z, p.z - rect.end.y), 0.0))
	var dy := maxf(maxf(floor_y - p.y, p.y - ceiling_y), 0.0)
	return Vector3(q.x, dy, q.y).length()


## Runs every step immediately (load, teleport, switch toggles).
func apply_immediately(target: int) -> void:
	for step in plan_transition(target):
		step.call()


## Returns small steps that the ZoneManager runs inside a per-frame time budget.
## Starting a new transition invalidates the unfinished steps of the previous one.
func plan_transition(target: int) -> Array[Callable]:
	_tid += 1
	var id := _tid
	var waking := target > state
	state = target
	var vis := target != State.COLD
	var steps: Array[Callable] = []
	if waking:
		# draw first, then light it
		steps.append(func(): _apply_drawn(id, vis))
		steps.append(func(): _apply_lights(id, vis))
	else:
		# switch the lights off first, then stop drawing
		steps.append(func(): _apply_lights(id, vis))
		steps.append(func(): _apply_drawn(id, vis))
	var i := 0
	while i < _hooks.size():
		var start := i
		steps.append(func(): _apply_hooks(id, target, start))
		i += HOOK_CHUNK
	return steps


func _apply_drawn(id: int, v: bool) -> void:
	if id != _tid:
		return
	drawn = v
	_manager.zone_drawn_changed(self)


func _apply_lights(id: int, v: bool) -> void:
	if id != _tid:
		return
	lights_awake = v
	_manager.zone_lights_changed(self)


func _apply_hooks(id: int, target: int, start: int) -> void:
	if id != _tid:
		return
	var end := mini(start + HOOK_CHUNK, _hooks.size())
	for k in range(start, end):
		var h := _hooks[k]
		if is_instance_valid(h):
			h.call(&"_zone_state_changed", int(target))
