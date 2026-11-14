class_name DoorController
extends Node3D
## Moves a door's collision leaves and matching visuals together.

## Emitted when the fully open threshold changes.
signal opened_changed(door_id: int, open: bool)
## Stable manifest door identifier.
var door_id: int
## Eased travel fraction, from closed to open.
var open_amount: float = 0.0
## Locked doors close and ignore nearby players.
var locked: bool = false
## Real seconds for a complete opening or closing.
var open_seconds: float = 0.6
## Player sensing distance from the average leaf origin.
var sense_radius: float = 2.2

## Emitted when this door starts waiting for an airlock pressure cycle before it may open.
signal cycle_started(door_id: int, seconds: float)
## Airlock pairing: when set, this door opens only after the partner has been fully shut for cycle_seconds
## (the pressure cycle), and never while the partner is open or opening.
var partner: DoorController
## Real seconds the chamber takes to equalise once the other door has shut.
var cycle_seconds: float = 2.5

var _leaves: Array[Dictionary] = []
var _sense: Area3D
var _progress: float = 0.0
var _shut_for: float = 1000.0   # shut since long before the game started: the first passage needs no wait
var _cycling: bool = false

## Add one manifest leaf before entering the tree.
func add_leaf(leaf_name: String, pose: Transform3D, slide: float, boxes: Array) -> void:
	var body := AnimatableBody3D.new()
	body.name = leaf_name
	body.collision_layer = Layers.DOOR
	body.collision_mask = 0
	body.sync_to_physics = true
	var closed := Transform3D(pose.basis.orthonormalized(), pose.origin)
	body.transform = closed
	WorldCollision.add_boxes(body, boxes, closed.affine_inverse() * pose, leaf_name)
	add_child(body)
	_leaves.append({"body": body, "closed": closed, "offset": pose.basis.x.normalized() * slide, "visual": null})

func _ready() -> void:
	_sense = Area3D.new()
	_sense.name = "Sense"
	_sense.collision_layer = 0
	_sense.collision_mask = Layers.PLAYER
	var centre := Vector3.ZERO
	for leaf: Dictionary in _leaves:
		centre += (leaf.closed as Transform3D).origin
	_sense.position = centre / maxi(_leaves.size(), 1)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = sense_radius
	shape.shape = sphere
	_sense.add_child(shape)
	add_child(_sense)

## Remember closed visual transforms and match subsequent collision travel.
func attach_visuals(scene_root: Node) -> int:
	var found: int = 0
	for leaf: Dictionary in _leaves:
		var body: AnimatableBody3D = leaf.body
		var visual := scene_root.find_child(String(body.name), true, false) as Node3D
		if visual == null:
			continue
		leaf.visual = visual
		leaf.visual_closed = visual.transform
		found += 1
	_move_leaves()
	return found

## Set whether this door must remain closed.
func set_locked(value: bool) -> void:
	locked = value

## True when travel has passed 95 percent.
func is_open() -> bool:
	return open_amount > 0.95

func _physics_process(delta: float) -> void:
	var sphere := _sense.get_child(0).shape as SphereShape3D
	if not is_equal_approx(sphere.radius, sense_radius):
		sphere.radius = sense_radius
	var wants_open := not locked and _sense.has_overlapping_bodies()
	_shut_for = _shut_for + delta if _progress <= 0.0 else 0.0
	if partner != null:
		if wants_open:
			wants_open = _may_open(delta)
		else:
			_cycling = false
	var was_open := is_open()
	_progress = move_toward(_progress, 1.0 if wants_open else 0.0, delta / maxf(open_seconds, 0.0001))
	open_amount = smoothstep(0.0, 1.0, _progress)
	_move_leaves()
	if was_open != is_open():
		opened_changed.emit(door_id, is_open())

## Airlock rule, asked only while someone is at this door. A door that is open or opening keeps going while the partner
## is shut. A shut door waits while the partner is open or moving, then for the pressure cycle. If someone stands where
## both doors sense them, the lower id (the inner door) has the right of way.
func _may_open(_delta: float) -> bool:
	if partner._progress > 0.0:
		_cycling = false
		return false
	if _progress > 0.0:
		return true
	if partner._cycling and partner.door_id < door_id:
		return false
	if partner._shut_for < cycle_seconds:
		if not _cycling:
			_cycling = true
			cycle_started.emit(door_id, cycle_seconds - partner._shut_for)
		return false
	_cycling = false
	return true

func _move_leaves() -> void:
	for leaf: Dictionary in _leaves:
		var pose: Transform3D = leaf.closed
		var offset: Vector3 = leaf.offset * open_amount
		pose.origin += offset
		var body: AnimatableBody3D = leaf.body
		body.transform = pose
		if is_instance_valid(leaf.visual):
			var visual: Node3D = leaf.visual
			var visual_pose: Transform3D = leaf.visual_closed
			# Convert controller-local travel to the visual parent's coordinates.
			if is_inside_tree() and visual.is_inside_tree():
				var parent := visual.get_parent_node_3d()
				var world_offset := global_basis * offset
				visual_pose.origin += parent.global_basis.inverse() * world_offset if parent != null else world_offset
			else:
				visual_pose.origin += offset
			visual.transform = visual_pose
