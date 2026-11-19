class_name ZoneManager
extends Node
## One instance per game (added by PerfRig). Decides which Zones are COLD / VIEW_ONLY / WARM / ACTIVE and applies the
## changes inside a small per-frame time budget so no frame ever does a big batch of work.
##
## Rules (inside the colony: a room, the dome plaza or the garden dome):
##   current room                                         -> ACTIVE
##   rooms within Perf.cfg().warm_hops doors            -> WARM
##   rooms seen through glass_view_hops glass doors/windows (or open doors) in a row -> VIEW_ONLY (still drawn)
##   near a door (prewarm_distance)                       -> also WARM / VIEW_ONLY what is behind that door
##   everything else                                      -> COLD, but only after cold_delay seconds (hysteresis)
## Rules (player outside on Mars):
##   the glass plaza and the garden dome within outside_dome_distance -> VIEW_ONLY
##   rooms with a view out within outside_interior_distance           -> VIEW_ONLY
##   rooms behind an exterior door the player is approaching          -> WARM
##   everything else -> COLD
##
## Every interior door leaf of this map has a glass vision panel (tools/perf/probe_glass.gd), so a closed door does not
## block sight: glass_view_hops (default 2) keeps everything visible through up to two glass panels in a row drawn.
## Drawing is switched with the gameplay camera's cull mask (Zone docs); other cameras (rover mast, portraits) are
## never touched.

signal graph_ready
signal current_zone_changed(zone: Zone)
signal player_outside_changed(outside: bool)

const POLL_INTERVAL := 0.1   # s between target recalculations (10 Hz is plenty)
const OUTSIDE_GRACE := 0.3   # s outside every zone's bounds before we call it "outside"
const DOOR_SIDE_M := 1.2     # how far either side of a door its two zones are sampled
const DOOR_SIDE_FAR_M := 3.5 # second try for an airlock door whose both near sides are the same zone

var game: Node               ## GameMain
var lighting: ZoneLighting
var colony_zones: ColonyZones

var zones: Array[Zone] = []
var doors: Array[ZoneDoor] = []
var current: Zone = null
var player_outside := false
var is_graph_ready := false

var _by_id := {}             # zone name -> Zone
var _wake_q: Array[Callable] = []
var _sleep_q: Array[Callable] = []
var _cold_since: Dictionary = {}
var _acc := 0.0
var _none_time := 0.0
var _was_enabled := true
var _last_frame_p := Vector3.INF
var _extra_hidden := {}      # owner -> bits hidden by other systems (ExteriorController)
var _camera: Camera3D
var _removed_bits := 0       # bits this manager cleared from _camera.cull_mask (given back exactly)


func setup(game_main: Node) -> void:
	game = game_main
	lighting = game.get("lighting")
	colony_zones = (game.get("services") as GameServices).zones
	add_to_group(&"zone_manager")
	_build_zones()
	_build_doors()
	_build_windows()
	_build_graph()
	_classify_all(get_tree().root)
	get_tree().node_added.connect(_on_node_added)
	is_graph_ready = true
	graph_ready.emit()
	snap()


func player() -> Node3D:
	return game.get("player") if game != null else null


## Where the rooms are decided from: the player, or a camera flown away from the player (the scout drone's chase / FPV
## camera, 2026-11-14). The player's own first- and third-person cameras sit under the player and count as the player.
func viewer_position() -> Vector3:
	var p := player()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and p != null and not p.is_ancestor_of(cam):
		return cam.global_position
	return p.global_position if p != null else Vector3.ZERO


func zone(id: String) -> Zone:
	return _by_id.get(id)


func _process(delta: float) -> void:
	if not is_graph_ready:
		return
	_props_tick(delta)
	if not Perf.cfg().zones_enabled:
		if _was_enabled:
			_was_enabled = false
			_wake_q.clear()
			_sleep_q.clear()
			_cold_since.clear()
			for z in zones:
				z.apply_immediately(Zone.State.ACTIVE)
			_apply_camera_mask()
			_update_light_view(delta)
			if lighting != null:
				lighting.flush_queue()
		return
	if not _was_enabled:
		_was_enabled = true
		snap()
		return
	if player() == null:
		return
	# Teleport, respawn, rover exit, drone take-off / hand-back, save load: a jump between two frames applies everything
	# at once, this frame.
	var pos := viewer_position()
	if _last_frame_p != Vector3.INF and pos.distance_to(_last_frame_p) > Perf.cfg().snap_distance:
		_last_frame_p = pos
		_acc = 0.0
		snap()
		return
	_last_frame_p = pos
	_acc += delta
	if _acc >= POLL_INTERVAL:
		_acc = 0.0
		_update_targets(false)
	_run_queue()
	_apply_camera_mask()
	_update_light_view(delta)


func queue_length() -> int:
	return _wake_q.size() + _sleep_q.size()


## Call after any teleport, respawn, fast travel or save-game load. Applies the correct state to every zone at once
## instead of time-slicing. A jump of more than snap_distance between two frames does this by itself.
func snap() -> void:
	_wake_q.clear()
	_sleep_q.clear()
	_cold_since.clear()
	if is_graph_ready and player() != null and Perf.cfg().zones_enabled:
		_update_targets(true)
	_apply_camera_mask()
	# teleport, fast travel, load: the light view and every queued light change apply in this frame
	_update_light_view(0.0)
	if lighting != null:
		lighting.flush_queue()


# ---------------------------------------------------------------- building

func _build_zones() -> void:
	var z := colony_zones
	for r: Dictionary in z.rooms:
		var zn := _new_zone(String(r.name), Zone.KIND_ROOM)
		zn.rect = Rect2(float(r.x0), -float(r.y1), float(r.x1) - float(r.x0), float(r.y1) - float(r.y0))
		zn.ceiling_y = float(r.get("ceiling", 3.0))
		zn.centre = Vector3(zn.rect.get_center().x, 1.5, zn.rect.get_center().y)
	var d: Dictionary = z.dome
	var plaza := _new_zone(ColonyZones.PLAZA, Zone.KIND_PLAZA)
	plaza.rect = Rect2(float(d.cx) - float(d.rx), -float(d.cy) - float(d.ry), 2.0 * float(d.rx), 2.0 * float(d.ry))
	plaza.ceiling_y = float(d.get("h", 18.0))
	plaza.centre = Vector3(float(d.cx), 1.5, -float(d.cy))
	plaza.has_exterior_view = true
	var garden := _new_zone(ColonyZones.GARDEN, Zone.KIND_GARDEN)
	garden.centre = Vector3(ColonyZones.GARDEN_CENTRE.x, 1.5, -ColonyZones.GARDEN_CENTRE.y)
	garden.radius = ColonyZones.GARDEN_RADIUS
	garden.rect = Rect2(garden.centre.x - garden.radius, garden.centre.z - garden.radius, 2.0 * garden.radius, 2.0 * garden.radius)
	garden.ceiling_y = 12.0
	garden.has_exterior_view = true


func _new_zone(id: String, kind: StringName) -> Zone:
	var zn := Zone.new()
	zn.name = "Zone_" + ColonyZones.slug(id)
	zn.zone_id = StringName(id)
	zn.kind = kind
	zn.render_bit = colony_zones.bit_of(id)
	add_child(zn)
	zn.setup(self)
	zones.append(zn)
	_by_id[id] = zn
	return zn


## Every DoorController in the game: the 24 manifest doors, the exit tunnel pair and the garden dome pair.
func _build_doors() -> void:
	var collision: Node = game.get("collision")
	if collision == null:
		return
	for dc in collision.find_children("*", "DoorController", true, false):
		var door := dc as DoorController
		var at := _door_centre(door)
		var normal := _door_axis(door).cross(Vector3.UP).normalized()
		var za := _zone_name_at(at + normal * DOOR_SIDE_M)
		var zb := _zone_name_at(at - normal * DOOR_SIDE_M)
		if za == zb and door.partner != null:
			# an airlock door inside a vestibule (the garden dome's): look past the vestibule
			za = _zone_name_at(at + normal * DOOR_SIDE_FAR_M)
			zb = _zone_name_at(at - normal * DOOR_SIDE_FAR_M)
		var zd := ZoneDoor.new()
		zd.name = "Door_%d" % door.door_id
		add_child(zd)
		zd.global_position = at
		zd.transparent = _has_glass(door)
		if za == ColonyZones.EXTERIOR or zb == ColonyZones.EXTERIOR:
			# a door with Mars on one side (the garden's outer door, the tunnel's outer door)
			zd.leads_outside = true
			zd.zone_a = zone(zb if za == ColonyZones.EXTERIOR else za)
			if zd.zone_a == null:
				zd.zone_a = _zone_of_partner(door)
		elif za == zb:
			# an inner airlock door with the same zone on both sides (garden dome vestibule): no link in the graph
			zd.zone_a = zone(za)
		else:
			zd.zone_a = zone(za)
			zd.zone_b = zone(zb)
		zd.setup(door)
		doors.append(zd)


## The outer door of an airlock pair whose both sides sample as Mars: it belongs to the zone of its partner's inner side.
func _zone_of_partner(door: DoorController) -> Zone:
	if door.partner == null:
		return null
	var at := _door_centre(door.partner)
	var normal := _door_axis(door.partner).cross(Vector3.UP).normalized()
	for s: float in [1.0, -1.0]:
		var n := _zone_name_at(at + normal * DOOR_SIDE_M * s)
		if n != ColonyZones.EXTERIOR and zone(n) != null:
			return zone(n)
	return null


## Windows: glazed colony meshes that are not door leaves and touch two zones get a permanent transparent link.
## The glass dome of the hall links the plaza and the garden dome (each can be seen from the other).
func _build_windows() -> void:
	var world: Node3D = game.get("world")
	if world == null:
		return
	var pairs := {}
	var colony := world.get_node_or_null("Colony")
	if colony != null:
		for mi in colony.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			if String(m3.name).contains("door") or not _mesh_has_glass(m3):
				continue
			var ids := _zone_ids_of_layers(m3.layers)
			var box := m3.global_transform * m3.mesh.get_aabb()
			for i in ids.size():
				for j in range(i + 1, ids.size()):
					var key := "%s|%s" % [ids[i], ids[j]]
					# every glazed mesh between the same two zones counts: the link's box covers all of them
					var all: AABB = (pairs[key][3] as AABB).merge(box) if pairs.has(key) else box
					pairs[key] = [ids[i], ids[j], all.get_center(), all]
	var gc := Vector3(ColonyZones.GARDEN_CENTRE.x, 1.5, -ColonyZones.GARDEN_CENTRE.y)
	var gr := float(ColonyZones.GARDEN_RADIUS)
	pairs["%s|%s" % [ColonyZones.PLAZA, ColonyZones.GARDEN]] = [ColonyZones.PLAZA, ColonyZones.GARDEN, gc,
		AABB(gc - Vector3(gr, 1.5, gr), Vector3(2.0 * gr, 12.0, 2.0 * gr))]
	for k: String in pairs:
		var pr: Array = pairs[k]
		var za := zone(pr[0])
		var zb := zone(pr[1])
		if za == null or zb == null:
			continue
		var zd := ZoneDoor.new()
		zd.name = "Window_%s_%s" % [ColonyZones.slug(pr[0]), ColonyZones.slug(pr[1])]
		add_child(zd)
		zd.global_position = pr[2]
		zd.radius = maxf(1.0, (pr[3] as AABB).size.length() * 0.5)
		zd.is_window = true
		zd.transparent = true
		zd.zone_a = za
		zd.zone_b = zb
		zd.setup(null)
		doors.append(zd)


func _build_graph() -> void:
	for z in zones:
		z.neighbors.clear()
	for d in doors:
		if d.zone_a != null and d.zone_b != null and d.zone_a != d.zone_b:
			if not d.zone_a.neighbors.has(d.zone_b):
				d.zone_a.neighbors.append(d.zone_b)
			if not d.zone_b.neighbors.has(d.zone_a):
				d.zone_b.neighbors.append(d.zone_a)
	# A room with a glass link to the plaza can be looked into from outside, through the dome and that glass.
	var plaza := zone(ColonyZones.PLAZA)
	for d in doors:
		if d.transparent and d.joins(plaza) and d.other(plaza) != null:
			d.other(plaza).has_exterior_view = true
		if d.leads_outside and d.zone_a != null:
			d.zone_a.has_exterior_view = true


# ---------------------------------------------------------------- always-drawn layer
# The camera's cull mask also culls LIGHTS, reflection probes and decals by their own `layers`, and every node starts
# on layer 1, which is the Hangar bay's zone layer: putting the Hangar to sleep switched off the sun and every lamp
# (benchmark of 2026-11-14, Med Bay and outdoor views went dark). So every light, probe and decal, and every drawn
# object that is not zone-layered map content but still sits on the default layer 1 (runtime props, rover parts,
# labels...), also gets layer 20, which no zone ever hides. Which surfaces a light lights is set by its
# light_cull_mask, not by `layers`, so this changes nothing on screen. The added bit is taken off again on exit.

const META_PINNED := &"perf_pinned_layer"


func _classify_all(n: Node) -> void:
	_classify(n)
	for c in n.get_children():
		_classify_all(c)


## node_added: lights and other effects are pinned at once. Everything else is decided at the end of the frame, after
## the code that added it has set its layers and position (broken_part_presenter.gd sets a model's zone layer right
## after add_child, and treats layers == 1 as "not set yet").
func _on_node_added(n: Node) -> void:
	if not (n is VisualInstance3D):
		return
	if _is_effect(n):
		_pin(n)
		return
	if _pending.is_empty():
		_flush_pending.call_deferred()
	_pending.append(n)


func _flush_pending() -> void:
	var list := _pending
	_pending = []
	for n in list:
		if is_instance_valid(n) and n.is_inside_tree():
			_classify(n)


## Effects -> always-drawn layer. Map content -> left alone. Other content on layer 1 -> tied to its room if it is a
## static prop standing in one (room_props_enabled), else pinned to the always-drawn layer as before.
func _classify(n: Node) -> void:
	var vi := n as VisualInstance3D
	if vi == null or vi.has_meta(META_PINNED) or vi.has_meta(META_ROOM):
		return
	if not _is_effect(vi) and vi.layers & 1 and not _is_map_content(vi):
		if Perf.cfg().room_props_enabled and _tie_to_room(vi):
			return
	_pin(vi)


static func _is_effect(n: Node) -> bool:
	return n is Light3D or n is ReflectionProbe or n is Decal or n is FogVolume or n is VoxelGI or n is LightmapGI


func _pin(n: Node) -> void:
	var vi := n as VisualInstance3D
	if vi == null or vi.has_meta(META_PINNED) or vi.has_meta(META_ROOM):
		return
	var always := colony_zones.sun_bit()
	var effect := _is_effect(n)
	if effect or (vi.layers & 1 and not _is_map_content(n)):
		if vi.layers & always == 0:
			vi.set_meta(META_PINNED, true)
			vi.layers |= always


func _is_map_content(n: Node) -> bool:
	var world: Node = game.get("world")
	if world == null:
		return false
	for top: String in ["Colony", "Environment", "Terrain"]:
		var t := world.get_node_or_null(top)
		if t != null and t.is_ancestor_of(n):
			return true
	return false


func _unpin_all(n: Node) -> void:
	var vi := n as VisualInstance3D
	if vi != null and vi.has_meta(META_PINNED):
		vi.layers &= ~colony_zones.sun_bit()
		vi.remove_meta(META_PINNED)
	for c in n.get_children():
		_unpin_all(c)


# ---------------------------------------------------------------- runtime room props
# Props the presenters add while the game runs (cassettes and their sparkles, broken parts, task effects, labels...)
# that are still on the default layer 1 used to be pinned to the always-drawn layer, so they were drawn and their
# particles simulated even while their room slept. Layer 1 is also the Hangar bay's zone layer, which made every
# runtime Hangar prop always drawn. Now a static prop standing in a room gets that room's layer instead and sleeps
# with it. Anything that moves is never tied to a room: the MOVERS below, any non-static physics body, and any prop
# found outside its room on the 0.5 s check (it goes back to the always-drawn layer).

const META_ROOM := &"perf_room_prop"
const META_ROOM_LAYERS := &"perf_room_prop_layers"
const PROP_CHECK_INTERVAL := 0.5
const PROP_LEAVE_MARGIN := 0.5
## GameMain fields that hold things which move or are carried through the rooms: [field, sub-field or ""]. The field
## may be a Node or a Dictionary of Nodes; a sub-field names the moving node inside it (the drone's body and the scout
## presenter's root live under the world, not under their presenter). A new moving feature gets a line here.
const MOVERS: Array = [
	["player", ""],
	["_crew_visuals", ""],
	["_item_nodes", ""],
	["rover", ""],
	["rover", "body"],
	["drone", "body"],
	["scout_presenter", "_root"],
]

var _pending: Array[Node] = []
var _room_props := {}        # VisualInstance3D -> Zone
var _props_acc := 0.0
var _props_were_enabled := true


func room_prop_count() -> int:
	return _room_props.size()


## Only a prop on the default layer alone: a presenter that chose other layers has already said where it belongs.
func _tie_to_room(vi: VisualInstance3D) -> bool:
	if vi.layers != 1 or _is_mover(vi):
		return false
	var room := room_at(vi.global_position)
	if room == null or room.render_bit == 0:
		return false
	vi.set_meta(META_ROOM, room)
	vi.set_meta(META_ROOM_LAYERS, vi.layers)
	vi.layers = room.render_bit
	_room_props[vi] = room
	return true


func _is_mover(n: Node) -> bool:
	var a := n
	while a != null:
		if a is PhysicsBody3D and not (a is StaticBody3D):
			return true
		a = a.get_parent()
	if game == null:
		return false
	for m: Array in MOVERS:
		var v: Variant = game.get(String(m[0]))
		if v is Object and is_instance_valid(v) and String(m[1]) != "":
			v = (v as Object).get(String(m[1]))
		if v is Node and is_instance_valid(v) and ((v as Node) == n or (v as Node).is_ancestor_of(n)):
			return true
		if v is Dictionary:
			for d: Variant in (v as Dictionary).values():
				if d is Node and is_instance_valid(d) and ((d as Node) == n or (d as Node).is_ancestor_of(n)):
					return true
	return false


func _props_tick(delta: float) -> void:
	var on: bool = Perf.cfg().room_props_enabled
	if on != _props_were_enabled:
		_props_were_enabled = on
		if on:
			_reclassify_all(get_tree().root)
		else:
			_release_all_props(true)
		return
	_props_acc += delta
	if _props_acc < PROP_CHECK_INTERVAL:
		return
	_props_acc = 0.0
	for k: Variant in _room_props.keys():
		if not is_instance_valid(k):
			_room_props.erase(k)
			continue
		var vi := k as VisualInstance3D
		var room := _room_props[k] as Zone
		if not vi.is_inside_tree() or not room.contains_point(vi.global_position, PROP_LEAVE_MARGIN):
			_release_prop(vi)
			if vi.is_inside_tree():
				_pin(vi)


## Gives a room prop its own layers back (unless the game has changed them since).
func _release_prop(vi: VisualInstance3D) -> void:
	var room := _room_props.get(vi) as Zone
	_room_props.erase(vi)
	if room != null and vi.layers == room.render_bit:
		vi.layers = int(vi.get_meta(META_ROOM_LAYERS, 1))
	vi.remove_meta(META_ROOM)
	vi.remove_meta(META_ROOM_LAYERS)


func _release_all_props(pin_again: bool) -> void:
	for k: Variant in _room_props.keys():
		if not is_instance_valid(k):
			continue
		var vi := k as VisualInstance3D
		_release_prop(vi)
		if pin_again and vi.is_inside_tree():
			_pin(vi)
	_room_props.clear()


## room_props_enabled switched back on: pinned props are looked at again.
func _reclassify_all(n: Node) -> void:
	var vi := n as VisualInstance3D
	if vi != null and vi.has_meta(META_PINNED) and not _is_effect(vi):
		vi.layers &= ~colony_zones.sun_bit()
		vi.remove_meta(META_PINNED)
		_classify(vi)
	for c in n.get_children():
		_reclassify_all(c)


func _door_centre(door: DoorController) -> Vector3:
	var sense := door.get_node_or_null("Sense") as Node3D
	return sense.global_position if sense != null else door.global_position


func _door_axis(door: DoorController) -> Vector3:
	for c in door.get_children():
		if c is AnimatableBody3D:
			return (c as Node3D).global_basis.x.normalized()
	return Vector3.RIGHT


func _has_glass(door: DoorController) -> bool:
	for leaf: Dictionary in door._leaves:
		var v: Variant = leaf.get("visual")
		if v is MeshInstance3D and _mesh_has_glass(v as MeshInstance3D):
			return true
		if v is Node:
			for mi in (v as Node).find_children("*", "MeshInstance3D", true, false):
				if _mesh_has_glass(mi as MeshInstance3D):
					return true
	return false


static func _mesh_has_glass(mi: MeshInstance3D) -> bool:
	if mi.mesh == null:
		return false
	for i in mi.mesh.get_surface_count():
		if _mesh_has_glass_material(mi.get_active_material(i)):
			return true
	return false


static func _mesh_has_glass_material(m: Material) -> bool:
	var sm := m as ShaderMaterial
	if sm != null and sm.shader != null and sm.shader.resource_path.ends_with("colony_glass.gdshader"):
		return true
	var bm := m as BaseMaterial3D
	return bm != null and bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED


func _zone_ids_of_layers(layers: int) -> Array[String]:
	var out: Array[String] = []
	for z in zones:
		if z.render_bit != 0 and layers & z.render_bit:
			out.append(String(z.zone_id))
	return out


func _zone_name_at(p: Vector3) -> String:
	return colony_zones.zone_at_world(p)


# ---------------------------------------------------------------- locating the player

## The room (not plaza / garden) containing p, with bounds grown by `margin` (negative shrinks).
func room_at(p: Vector3, margin := 0.0) -> Zone:
	for z in zones:
		if z.kind == Zone.KIND_ROOM and z.contains_point(p, margin):
			return z
	return null


## Which outdoor kind the point is in: plaza (under the glass dome), garden (the garden dome) or &"" (Mars).
func outside_kind_at(p: Vector3) -> StringName:
	match colony_zones.outside_zone_at(p.x, -p.z):
		ColonyZones.PLAZA:
			return Zone.KIND_PLAZA if p.y < float(colony_zones.dome.get("h", 18.0)) else &""
		ColonyZones.GARDEN:
			return Zone.KIND_GARDEN
	return &""


## Sticky lookup: stay in the current zone while the player is still inside its bounds (grown by 0.15 m, so the
## rooms overlap by 0.3 m at every doorway and there is never a gap).
func _locate(p: Vector3) -> Zone:
	if current != null and current.contains_point(p, 0.15):
		return current
	if current != null:
		for z in current.neighbors:
			if z.contains_point(p):
				return z
	var room := room_at(p)
	if room != null:
		return room
	for z in zones:
		if z.kind != Zone.KIND_ROOM and z.contains_point(p):
			return z
	return null


# ---------------------------------------------------------------- graph queries

## Zones reachable within `hops` doors (closed or open). Includes `start`.
func zones_within_hops(start: Zone, hops: int) -> Array[Zone]:
	var out: Array[Zone] = []
	if start == null:
		return out
	var seen: Dictionary = {start: true}
	var frontier: Array[Zone] = [start]
	for _h in hops:
		var nxt: Array[Zone] = []
		for z in frontier:
			for n in z.neighbors:
				if not seen.has(n):
					seen[n] = true
					nxt.append(n)
		frontier = nxt
	for k in seen.keys():
		out.append(k as Zone)
	return out


## Zones you could see into through doors that are open or glazed, and windows. Includes `start`.
func zones_visible_through_open_doors(start: Zone, hops: int) -> Array[Zone]:
	var out: Array[Zone] = []
	if start == null:
		return out
	var seen: Dictionary = {start: true}
	var frontier: Array[Zone] = [start]
	for _h in hops:
		var nxt: Array[Zone] = []
		for z in frontier:
			for d in doors:
				if d.zone_a == null or d.zone_b == null or not d.joins(z) or not d.lets_sight_through():
					continue
				var o := d.other(z)
				if not seen.has(o):
					seen[o] = true
					nxt.append(o)
		frontier = nxt
	for k in seen.keys():
		out.append(k as Zone)
	return out


# ---------------------------------------------------------------- targets

func _update_targets(initial: bool) -> void:
	var p := viewer_position()
	var found := _locate(p)
	if found != null:
		_none_time = 0.0
		if found != current:
			current = found
			current_zone_changed.emit(current)
	else:
		_none_time += POLL_INTERVAL
		if initial:
			_none_time = OUTSIDE_GRACE
	var outside := found == null and (current == null or _none_time >= OUTSIDE_GRACE)
	if outside and current != null:
		current = null
		current_zone_changed.emit(null)
	if outside != player_outside:
		player_outside = outside
		player_outside_changed.emit(outside)

	var targets: Dictionary = {}
	for z in zones:
		targets[z] = Zone.State.COLD
	if current == null:
		_targets_outside(p, targets)
	else:
		_targets_inside(p, targets)
	_apply_targets(targets, p, initial)


func _raise(targets: Dictionary, z: Zone, s: int) -> void:
	if z == null:
		return
	targets[z] = maxi(int(targets[z]), s)


func _targets_outside(p: Vector3, targets: Dictionary) -> void:
	for z in zones:
		var d := z.distance_to_bounds(p)
		if z.kind != Zone.KIND_ROOM and d <= Perf.cfg().outside_dome_distance:
			_raise(targets, z, Zone.State.VIEW_ONLY)
		elif z.has_exterior_view and d <= Perf.cfg().outside_interior_distance:
			_raise(targets, z, Zone.State.VIEW_ONLY)
	for d in doors:
		if not d.leads_outside or d.zone_a == null:
			continue
		if d.global_position.distance_to(p) <= Perf.cfg().entrance_prewarm_distance:
			for z in zones_within_hops(d.zone_a, Perf.cfg().warm_hops):
				_raise(targets, z, Zone.State.WARM)
			for z in zones_visible_through_open_doors(d.zone_a, Perf.cfg().glass_view_hops):
				_raise(targets, z, Zone.State.VIEW_ONLY)


func _targets_inside(p: Vector3, targets: Dictionary) -> void:
	_raise(targets, current, Zone.State.ACTIVE)
	for z in zones_visible_through_open_doors(current, Perf.cfg().glass_view_hops):
		_raise(targets, z, Zone.State.VIEW_ONLY)
	for z in zones_within_hops(current, Perf.cfg().warm_hops):
		_raise(targets, z, Zone.State.WARM)
	# Close to a door: also wake everything around the room behind it, so walking through never has to wake rooms at
	# the moment of crossing (the time-sliced queue has done it before the player arrives).
	for d in doors:
		if d.is_window or not d.joins(current) or d.global_position.distance_to(p) > Perf.cfg().prewarm_distance:
			continue
		if d.leads_outside:
			continue   # the outside is the ExteriorController's job
		var behind := d.other(current)
		if behind == null:
			continue
		for z in zones_within_hops(behind, Perf.cfg().warm_hops):
			_raise(targets, z, Zone.State.WARM)
		for z in zones_visible_through_open_doors(behind, Perf.cfg().glass_view_hops):
			_raise(targets, z, Zone.State.VIEW_ONLY)
	# In the plaza or a room with a view out, the garden dome and the plaza stay drawn (seen through the dome glass).
	if current.has_exterior_view:
		_raise(targets, zone(ColonyZones.PLAZA), Zone.State.VIEW_ONLY)
		_raise(targets, zone(ColonyZones.GARDEN), Zone.State.VIEW_ONLY)


func _apply_targets(targets: Dictionary, p: Vector3, initial: bool) -> void:
	if initial:
		for z in zones:
			z.apply_immediately(int(targets[z]))
		return

	var now := Time.get_ticks_msec() * 0.001
	var wakes: Array[Zone] = []
	var sleeps: Array[Zone] = []
	for z in zones:
		var want: int = targets[z]
		var have: int = z.state
		if want == have:
			_cold_since.erase(z)
		elif want > have:
			_cold_since.erase(z)
			wakes.append(z)
		elif want >= Zone.State.VIEW_ONLY:
			# ACTIVE -> WARM -> VIEW_ONLY keeps the room drawn and lit: no need to delay it
			sleeps.append(z)
		else:
			# Losing visibility: wait cold_delay seconds first (hysteresis)
			if not _cold_since.has(z):
				_cold_since[z] = now
			if now - float(_cold_since[z]) >= Perf.cfg().cold_delay:
				_cold_since.erase(z)
				sleeps.append(z)

	# Wake the rooms closest to the player first.
	wakes.sort_custom(func(a: Zone, b: Zone) -> bool:
		return a.distance_to_bounds(p) < b.distance_to_bounds(p))
	for z in wakes:
		_wake_q.append_array(z.plan_transition(int(targets[z])))
	for z in sleeps:
		_sleep_q.append_array(z.plan_transition(int(targets[z])))


## Runs queued steps until the per-frame time budget is used up (always at least one step).
## Wake steps always run before sleep steps.
func _run_queue() -> void:
	var start := Time.get_ticks_usec()
	while not (_wake_q.is_empty() and _sleep_q.is_empty()):
		var step: Callable
		if not _wake_q.is_empty():
			step = _wake_q.pop_front()
		else:
			step = _sleep_q.pop_front()
		step.call()
		if Time.get_ticks_usec() - start >= Perf.cfg().step_budget_usec:
			break


# ---------------------------------------------------------------- applying (called by Zone steps)

func zone_drawn_changed(_z: Zone) -> void:
	_apply_camera_mask()


func zone_lights_changed(z: Zone) -> void:
	if lighting != null:
		lighting.set_zone_awake(String(z.zone_id), z.lights_awake and z.in_view)


# ---------------------------------------------------------------- light view (2026-11-18)
# A drawn zone's fixture lights only matter for the part of that zone the camera can see. The colony's meshes are
# merged across rooms, so the lights of a neighbouring room overlap the room you stand in and are shaded on every
# pixel there (measured at Ultra, 1440p: 14-28 ms of a 32-44 ms frame), while what they add to the picture is the
# neighbour seen through a door or window. So a zone other than the one the camera is in keeps its lights only while
# a door or window leading to it is near the camera's view: directly from the camera's zone, or through more glass
# links (glass_view_hops), each of them near the view. "Near the view": the opening's sphere is within the camera's
# diagonal field of view plus light_view_margin_deg, or the camera is within light_view_near of it. Lights come on in
# the frame the opening comes near the view and go off light_view_hold seconds after it left. Outside on Mars: the
# domes are lit while their bounds are near the view, and a room while a door or window between it and a dome or
# Mars is. Fixture lights are visual only (ZoneLighting, nothing in the game reads them).

var _lv_unseen: Dictionary = {}    # Zone -> seconds since it was last in view


func _update_light_view(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var on: bool = Perf.cfg().light_view_enabled and Perf.cfg().zones_enabled and cam != null and is_graph_ready
	var seen: Dictionary = zones_in_view(cam) if on else {}
	var shadow_on: bool = on and Perf.cfg().light_view_shadows_enabled
	var shadowed: Dictionary = zones_with_shadows(cam.global_position) if shadow_on else {}
	# Switching on is done at once (it shows). Switching off waits its turn: one zone per frame, because switching the
	# lights of several zones off in one frame made that frame 2x long (measured 33-39 ms at Ultra).
	var offs := 0
	for z in zones:
		var want := true
		if on:
			_lv_unseen[z] = 0.0 if seen.has(z) else float(_lv_unseen.get(z, 1e9)) + delta
			want = float(_lv_unseen[z]) <= Perf.cfg().light_view_hold
		if want != z.in_view and (want or offs == 0):
			offs += 0 if want else 1
			z.in_view = want
			zone_lights_changed(z)
		var shadows: bool = shadowed.has(z) if shadow_on else true
		if shadows != z.shadows_on and (shadows or offs == 0):
			offs += 0 if shadows else 1
			z.shadows_on = shadows
			if lighting != null:
				lighting.set_zone_shadows(String(z.zone_id), shadows)


## The zones whose fixture lights keep their shadow maps: the camera's zone, the player's, and every zone behind a
## door or window within light_view_shadow_near of the camera (so they are ready before the camera crosses).
func zones_with_shadows(eye: Vector3) -> Dictionary:
	var out := {}
	for z in zones:
		if z == current or z.contains_point(eye, 0.2):
			out[z] = true
	var near := float(Perf.cfg().light_view_shadow_near)
	for d in doors:
		if d.global_position.distance_to(eye) > d.radius + near:
			continue
		for z: Zone in [d.zone_a, d.zone_b]:
			if z != null:
				out[z] = true
	return out


## The zones the camera can see into right now (see the light view notes above), as a set.
func zones_in_view(cam: Camera3D) -> Dictionary:
	var out := {}
	var eye := cam.global_position
	var fwd := -cam.global_basis.z
	var half: float = _half_view_angle(cam) + deg_to_rad(float(Perf.cfg().light_view_margin_deg))
	var near := float(Perf.cfg().light_view_near)
	var frontier: Array[Zone] = []
	for z in zones:
		if z == current or z.contains_point(eye, 0.2):
			out[z] = true
			frontier.append(z)
	if frontier.is_empty():
		# outside on Mars (or a camera flown away): domes by their bounds, rooms by their openings to a dome or Mars
		for z in zones:
			if z.kind != Zone.KIND_ROOM and _sphere_near_view(eye, fwd, half, near, z.centre, _dome_radius(z)):
				out[z] = true
		for d in doors:
			if not d.lets_sight_through() or not _sphere_near_view(eye, fwd, half, near, d.global_position, d.radius):
				continue
			for z: Zone in [d.zone_a, d.zone_b]:
				if z == null or z.kind != Zone.KIND_ROOM:
					continue
				var o := d.other(z)
				if d.leads_outside or (o != null and o.kind != Zone.KIND_ROOM):
					out[z] = true
					frontier.append(z)
	var hops := maxi(1, int(Perf.cfg().light_view_hops))
	if GraphicsQuality.applied_level(get_tree()) == GraphicsQuality.Level.LOW:
		hops = 1   # Low (chips in the processor): rooms two glass panes away stay dark
	for _h in hops:
		var nxt: Array[Zone] = []
		for z in frontier:
			for d in doors:
				if d.zone_a == null or d.zone_b == null or not d.joins(z) or not d.lets_sight_through():
					continue
				var o := d.other(z)
				if o == null or out.has(o) or not _sphere_near_view(eye, fwd, half, near, d.global_position, d.radius):
					continue
				out[o] = true
				nxt.append(o)
		frontier = nxt
	return out


func _dome_radius(z: Zone) -> float:
	if z.kind == Zone.KIND_GARDEN:
		return z.radius + 2.0
	return z.rect.size.length() * 0.5 + 2.0


## Half the camera's diagonal field of view, radians.
static func _half_view_angle(cam: Camera3D) -> float:
	var vp := cam.get_viewport()
	var size := vp.get_visible_rect().size if vp != null else Vector2(16, 9)
	var aspect := size.x / maxf(1.0, size.y)
	var t := tan(deg_to_rad(cam.fov) * 0.5)
	var tv := t if cam.keep_aspect == Camera3D.KEEP_HEIGHT else t / aspect
	var th := t if cam.keep_aspect == Camera3D.KEEP_WIDTH else t * aspect
	return atan(sqrt(tv * tv + th * th))


## Is a sphere within `half` radians of the view direction (or within `near` metres of the eye)?
static func _sphere_near_view(eye: Vector3, fwd: Vector3, half: float, near: float, c: Vector3, r: float) -> bool:
	var v := c - eye
	var dist := v.length()
	if dist <= r + near:
		return true
	var angle := acos(clampf(v.dot(fwd) / dist, -1.0, 1.0))
	return angle - asin(clampf(r / dist, 0.0, 1.0)) <= half


## Other systems hide render layers through the same camera (ExteriorController: the Exterior layer).
func set_extra_hidden_bits(owner: Object, bits: int) -> void:
	if bits == 0:
		_extra_hidden.erase(owner)
	else:
		_extra_hidden[owner] = bits
	_apply_camera_mask()


func hidden_bits() -> int:
	var bits := 0
	for z in zones:
		if not z.drawn:
			bits |= z.render_bit
	for b: int in _extra_hidden.values():
		bits |= b
	return bits


## Clears the hidden bits from the main viewport's camera. Only bits this manager cleared are ever given back, so the
## camera rig's own mask (the first-person hidden layer) is never disturbed. A camera change gives the old one its
## bits back first.
func _apply_camera_mask() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != _camera:
		var inherited := _removed_bits
		if is_instance_valid(_camera):
			_camera.cull_mask |= _removed_bits
		_removed_bits = 0
		_camera = cam
		# A camera made current with a copy of the old one's mask (the scout drone copies the player camera's) copied the
		# bits this manager had cleared too: give those back, then hide what is hidden now.
		if _camera != null:
			_camera.cull_mask |= inherited
	if _camera == null:
		return
	var want := hidden_bits()
	var mask := _camera.cull_mask | _removed_bits
	_removed_bits = mask & want
	var new_mask := mask & ~want
	if _camera.cull_mask != new_mask:
		_camera.cull_mask = new_mask


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	_release_all_props(false)
	_unpin_all(get_tree().root)
	if is_instance_valid(_camera):
		_camera.cull_mask |= _removed_bits
	_removed_bits = 0
	if lighting != null:
		for z in zones:
			lighting.set_zone_awake(String(z.zone_id), true)
