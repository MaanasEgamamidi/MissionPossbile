class_name ExteriorController
extends Node
## Hides the Mars environment only when the player cannot possibly see it: the current room has no view out, and no
## chain of open or glazed doors / windows (Perf.cfg().exterior_check_hops long) leads to a zone that has one.
## It never frees or reloads anything: it flips `visible` on the Mars roots (terrain, rocks, scenery, the glass hall),
## puts the Exterior fixture lights to sleep and clears the Exterior render layer from the gameplay camera, so showing
## it again is instant. Collision is built separately at load (WorldCollision, RockCollision), so hidden Mars still
## collides and no physics body is ever added or removed.
##
## Safety rules:
##   - When unsure (player outside, no current zone) the exterior is SHOWN.
##   - Showing is immediate. Hiding waits exterior_hide_delay seconds of "not needed".
##   - A door that starts opening forces an immediate re-check, and a door within exterior_door_prewarm metres that
##     leads toward a view or outside keeps Mars shown, so Mars is already on screen before the door has moved.

const CHECK_INTERVAL := 0.1

var zone_manager: ZoneManager
var mars_roots: Array[Node3D] = []    ## terrain, rocks, props. NOT the WorldEnvironment, NOT the player, NOT the colony.
var mars_dynamic_root: Node3D         ## optional: only scripted Mars things. Never terrain colliders.
var sun: DirectionalLight3D           ## optional, see Perf.cfg().sun_off_when_exterior_hidden

var shown := true

var _acc := 0.0
var _unneeded_for := 0.0
var _lighting: ZoneLighting


func setup(zm: ZoneManager, roots: Array[Node3D], sun_light: DirectionalLight3D) -> void:
	zone_manager = zm
	mars_roots = roots
	sun = sun_light
	_lighting = zm.lighting
	add_to_group(&"exterior_controller")
	for d in zone_manager.doors:
		d.opening_started.connect(_on_door_opening)


func _on_door_opening() -> void:
	_evaluate(0.0)


func _process(delta: float) -> void:
	if not Perf.cfg().exterior_cull_enabled or zone_manager == null:
		if not shown:
			_set_shown(true)
		return
	_acc += delta
	if _acc < CHECK_INTERVAL:
		return
	var dt := _acc
	_acc = 0.0
	_evaluate(dt)


func _evaluate(dt: float) -> void:
	if zone_manager == null or not zone_manager.is_graph_ready or not Perf.cfg().exterior_cull_enabled:
		return
	if exterior_needed():
		_unneeded_for = 0.0
		if not shown:
			_set_shown(true)
	else:
		_unneeded_for += dt
		if shown and _unneeded_for >= Perf.cfg().exterior_hide_delay:
			_set_shown(false)


func exterior_needed() -> bool:
	var zm := zone_manager
	if zm.player_outside or zm.current == null or zm.player() == null or not Perf.cfg().zones_enabled:
		return true  # fail-safe (and without zones there is no reliable "current room")

	# 1. Can a sight line through open/glass doors and windows reach a zone with a view out?
	var seen := zm.zones_visible_through_open_doors(zm.current, Perf.cfg().exterior_check_hops)
	for z in seen:
		if z.has_exterior_view:
			return true
	for d in zm.doors:
		if d.leads_outside and d.lets_sight_through() and seen.has(d.zone_a):
			return true

	# 2. Is the player about to open a door that leads toward the outside?
	var p := zm.viewer_position()
	for d in zm.doors:
		if d.is_window or not d.joins(zm.current):
			continue
		if d.global_position.distance_to(p) > Perf.cfg().exterior_door_prewarm:
			continue
		if d.leads_outside:
			return true
		var o := d.other(zm.current)
		if o != null and o.has_exterior_view:
			return true
	return false


func _set_shown(v: bool) -> void:
	shown = v
	for r in mars_roots:
		if is_instance_valid(r):
			r.visible = v
	if _lighting != null:
		_lighting.set_zone_awake(ColonyZones.EXTERIOR, v)
	if zone_manager != null:
		zone_manager.set_extra_hidden_bits(self, 0 if v else zone_manager.colony_zones.bit_of(ColonyZones.EXTERIOR))
	if mars_dynamic_root != null:
		mars_dynamic_root.process_mode = Node.PROCESS_MODE_INHERIT if v else Node.PROCESS_MODE_DISABLED
	if sun != null and Perf.cfg().sun_off_when_exterior_hidden:
		sun.visible = v


func _exit_tree() -> void:
	if not shown:
		_set_shown(true)
