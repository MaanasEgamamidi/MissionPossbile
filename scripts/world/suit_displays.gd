class_name SuitDisplays
extends RefCounted
## Swaps the old white display suits for the crew's own orange suit. The map's suit rack and suit stands have the old
## suit modelled into the same mesh as the rack, so the suit's triangles are cut out of that mesh when the game loads
## and a copy of the crew model, suit on and empty (no head), is hung in each place.

## Material that marks an old suit's shell; every display suit has some.
const SUIT_MARK := "pp_suit"
## Rack and stand materials that are never cut, even inside a suit's space (frames, rails, signs, hoses).
const KEEP: Array[String] = ["kit_frame", "kit_fl_plate", "kit_hazard_k", "kit_hazard_y", "kit_sign", "kit_ink",
	"kit_alu", "gunmetal"]
## Two suit shells closer than this (metres, across the floor) are the same suit.
const CLUSTER_M := 0.45

## Replaces every display suit under `world`. Returns how many suits were swapped.
static func build(world: Node) -> int:
	var scene := PlayerVisual.rigged_scene()
	if scene == null:
		return 0
	var count := 0
	for node: Node in world.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not _has_material(mi.mesh, SUIT_MARK):
			continue
		var suits := _find_suits(mi)
		if suits.is_empty():
			continue
		# suits on one rack all face the same way, square to the rack (one odd visor must not turn a suit sideways)
		var sum := Vector3.ZERO
		for suit: Dictionary in suits:
			sum += suit.facing
		var axis_x := mi.global_basis.x.normalized()
		var axis_z := mi.global_basis.z.normalized()
		var snapped: Vector3 = axis_x * signf(sum.dot(axis_x)) if absf(sum.dot(axis_x)) > absf(sum.dot(axis_z)) else axis_z * signf(sum.dot(axis_z))
		snapped.y = 0
		for suit: Dictionary in suits:
			suit.facing = snapped.normalized()
		mi.mesh = _cut(mi, suits)
		if String(mi.get_meta("inter", "")) == "suits":
			# Four crew need four separate rack positions; retain the rack's authored footprint.
			var template: Dictionary = suits[0]
			var centre := Vector3.ZERO
			for suit: Dictionary in suits:
				centre += (suit.box as AABB).get_center()
			centre /= suits.size()
			suits.clear()
			for slot in SessionService.SUITS_PER_RACK:
				var box: AABB = template.box
				var wanted := centre + mi.global_basis.x.normalized() * ((float(slot) - 1.5) * 0.7)
				box.position += wanted - box.get_center()
				suits.append({"box": box, "facing": snapped.normalized()})
		for i in suits.size():
			var display := _hang(mi, suits[i], i)
			if String(mi.get_meta("inter", "")) == "suits":
				display.set_meta("suit_rack", String(mi.name))
				display.set_meta("suit_slot", i)
				display.add_to_group(&"rack_suit_display")
			count += 1
	return count


static func _has_material(mesh: Mesh, material_name: String) -> bool:
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m != null and m.resource_name == material_name:
			return true
	return false


## One entry per old suit: its world bounds and the way it faces.
static func _find_suits(mi: MeshInstance3D) -> Array[Dictionary]:
	var xf := mi.global_transform
	var centres: Array[Vector3] = []
	var boxes: Array[AABB] = []
	var facing: Array[Vector3] = []
	var visor_sum: Array[Vector4] = []
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		var mat_name := m.resource_name if m != null else ""
		if not (mat_name in [SUIT_MARK, "pp_boot", "glass_pp_bubble", "visor", "pp_bearing", "fabric_bl"]):
			continue
		var arr := mi.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var tri_count := (idx.size() if idx.size() > 0 else v.size()) / 3
		for t in tri_count:
			var a := xf * v[idx[t * 3] if idx.size() > 0 else t * 3]
			var b := xf * v[idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1]
			var c := xf * v[idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2]
			var centre := (a + b + c) / 3.0
			var k := -1
			for j in centres.size():
				if Vector2(centres[j].x - centre.x, centres[j].z - centre.z).length() < CLUSTER_M:
					k = j
					break
			if k < 0:
				if mat_name != SUIT_MARK:
					continue  # clusters are started only by the suit shell
				centres.append(centre)
				boxes.append(AABB(a, Vector3.ZERO))
				facing.append(Vector3.ZERO)
				visor_sum.append(Vector4.ZERO)
				k = centres.size() - 1
			boxes[k] = boxes[k].expand(a).expand(b).expand(c)
			if mat_name == "visor":
				visor_sum[k] += Vector4(centre.x, centre.y, centre.z, 1.0)
	var out: Array[Dictionary] = []
	for j in boxes.size():
		if boxes[j].size.y < 1.0:
			continue  # loose helmets and gloves stay as they are
		# the suit faces the way its visor sits from the middle of the suit
		var f := Vector3(0, 0, -1)
		if visor_sum[j].w > 0.0:
			var visor := Vector3(visor_sum[j].x, visor_sum[j].y, visor_sum[j].z) / visor_sum[j].w
			var d := Vector3(visor.x - boxes[j].get_center().x, 0, visor.z - boxes[j].get_center().z)
			if d.length() > 0.01:
				f = d.normalized()
		out.append({"box": boxes[j].grow(0.04), "facing": f})
	return out


## The same mesh without the old suits' triangles.
static func _cut(mi: MeshInstance3D, suits: Array[Dictionary]) -> ArrayMesh:
	var xf := mi.global_transform
	var src := mi.mesh
	var result := ArrayMesh.new()
	for s in src.get_surface_count():
		var material := src.surface_get_material(s)
		var arr := src.surface_get_arrays(s)
		var mat_name := material.resource_name if material != null else ""
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var keep := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var cut := false
			if not (mat_name in KEEP):
				var centre := xf * ((verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0)
				for suit: Dictionary in suits:
					if (suit.box as AABB).has_point(centre):
						cut = true
						break
			if not cut:
				keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
		if keep.is_empty():
			continue
		var copy := arr.duplicate()
		copy[Mesh.ARRAY_INDEX] = keep
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, copy)
		result.surface_set_material(result.get_surface_count() - 1, material)
	return result


## Hangs one empty crew suit where an old one was, the same height, feet at the old boots, facing the same way.
static func _hang(mi: MeshInstance3D, suit: Dictionary, index: int) -> PlayerVisual:
	var box: AABB = suit.box
	var visual := PlayerVisual.new()
	visual.name = "DisplaySuit_%s_%d" % [mi.name, index]
	visual.use_rig_if_available()
	visual.set_first_person(false)
	visual.set_suit(true)
	visual.set_crew_identity(index % 4)
	mi.get_parent().add_child(visual)
	visual.set_zone_layers(mi.layers)
	# an empty suit: no face behind the visor, no idle breathing
	for pattern: String in ["Body_*", "Hair*"]:
		for part: Node in visual.find_children(pattern, "MeshInstance3D", true, false):
			(part as Node3D).visible = false
	for player: Node in visual.find_children("*", "AnimationPlayer", true, false):
		(player as AnimationPlayer).stop()
	visual.set_process(false)
	var height := 1.86   # the crew model with helmet on
	var s := clampf(box.size.y / height, 0.85, 1.1)
	var f: Vector3 = suit.facing
	visual.global_transform = Transform3D(Basis(Vector3.UP, atan2(-f.x, -f.z)).scaled(Vector3.ONE * s),
		Vector3(box.get_center().x, box.position.y + 0.04, box.get_center().z))
	return visual

## Derive display visibility from replicated/saved state, rather than a local interaction animation.
static func sync(tree: SceneTree, state: ColonyState) -> void:
	# runs every frame: build the worn slots once, then one lookup per display
	var worn := {}
	for c: CharacterState in state.characters.values():
		if c.suit_on:
			worn["%s#%d" % [c.suit_rack, c.suit_slot]] = true
	for display: Node in tree.get_nodes_in_group(&"rack_suit_display"):
		var shown := not worn.has("%s#%d" % [display.get_meta("suit_rack"), int(display.get_meta("suit_slot"))])
		if display.visible != shown:
			display.visible = shown
