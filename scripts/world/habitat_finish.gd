class_name HabitatFinish
extends RefCounted
## Scoped corrections from Game Functionality errors. Like SuitDisplays, modifies only instantiated derivatives.
## Source .blend/.glb files, palette generation, outdoor finishes and gameplay colliders remain authored inputs.
const REMOVE := ["ak_dust_trail", "ak_dust_drift", "qt_cable", "ls_drain"]
## Floor tiles whose drain grate goes: the tile is drawn as its plain twin. (Hiding the whole tile left 2 m holes down
## to the sand in the Greenhouse; owner 2026-11-14: "have floor be normal".)
const PLAIN_FLOOR := {"gr_floor_drain": "gr_floor"}
var _materials := {}
var stats := {"cleaned": 0, "removed": 0, "soil": 0, "chess": 0, "floors": 0}

func apply(world: Node) -> Dictionary:
	var plain_meshes := {}
	for node in world.find_children("*", "MeshInstance3D", true, false):
		var a := String(node.get_meta("gc_asset", ""))
		if a in PLAIN_FLOOR.values() and not plain_meshes.has(a):
			plain_meshes[a] = (node as MeshInstance3D).mesh
	for node in world.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var asset := String(mi.get_meta("gc_asset", ""))
		var area := String(mi.get_meta("area", ""))
		if asset in REMOVE:
			mi.visible = false
			stats.removed += 1
			continue
		if PLAIN_FLOOR.has(asset) and plain_meshes.has(PLAIN_FLOOR[asset]):
			mi.mesh = plain_meshes[PLAIN_FLOOR[asset]]
			stats.floors += 1
		var indoor := ColonyZones.AREA_ZONE.has(area) and area not in ["Dome plaza", "Garden Dome"]
		if asset.begins_with("rf_tile"):
			indoor = true  # underside ceiling tiles; roof slabs/exterior retain their dust
		if indoor:
			mi.set_instance_shader_parameter("dust", 0.0)
			for surface in mi.mesh.get_surface_count():
				var original := mi.get_active_material(surface)
				if original is ShaderMaterial and (original as ShaderMaterial).shader == load("res://materials/colony_surface.gdshader"):
					var cement := asset == "sc_floor" and original.resource_name == "kit_fl_rubber"
					cement = cement or (asset == "sc_e_panel" and original.resource_name in ["kit_panel", "kit_lower"])
					mi.set_surface_override_material(surface, _clean_material(original, cement, asset == "co_chair"))
					if asset == "sc_floor" and cement:
						_add_cement(mi, _clean_material(original, true, false))
			stats.cleaned += 1
		if asset == "rk_hood":
			mi.ignore_occlusion_culling = true
			mi.visibility_range_end = 0.0
		if asset == "co_planter":
			_add_soil(mi)
		if asset == "rk_chess":
			_fix_chess(mi)
	var green := world.find_child("gr_floor_drain", true, false) as Node3D
	if green != null:
		_add_cleaning_tools(world)
	return stats

func _clean_material(original: ShaderMaterial, cement: bool, chair: bool) -> ShaderMaterial:
	var key := "%d:%s:%s" % [original.get_instance_id(), cement, chair]
	if _materials.has(key):
		return _materials[key]
	var mat := original.duplicate() as ShaderMaterial
	for param in ["dust_gain", "grime_gain", "wear", "grime", "coat"]:
		mat.set_shader_parameter(param, 0.0)
	mat.set_shader_parameter("var", 0.0)
	mat.set_shader_parameter("roughness", 0.85)
	mat.set_shader_parameter("roughness_variation_gain", 0.0)
	mat.set_shader_parameter("specular", 0.0 if chair else 0.15)
	mat.set_shader_parameter("bump_gain", 0.0)
	if cement:
		mat.set_shader_parameter("albedo", Color(0.61, 0.61, 0.59))
		mat.set_shader_parameter("metallic", 0.0)
		mat.set_shader_parameter("class_id", 2)
	_materials[key] = mat
	return mat

func _add_soil(planter: MeshInstance3D) -> void:
	var soil := BoxMesh.new()
	soil.size = Vector3(1.44, 0.012, 0.35)
	var surface := MeshInstance3D.new()
	surface.name = "ExposedSoil"
	surface.mesh = soil
	surface.material_override = load("res://materials/colony/soil.tres")
	surface.layers = planter.layers
	planter.add_child(surface)
	surface.position = Vector3(0, 0.725, 0)
	stats.soil += 1

func _add_cement(floor_tile: MeshInstance3D, material: Material) -> void:
	var slab := BoxMesh.new()
	slab.size = Vector3(1.996, 0.004, 1.996)
	var face := _mesh(floor_tile, slab, material, Vector3(0, 0.0035, 0), floor_tile.layers)
	face.name = "SmoothCementFinish"

## Keep the authored board and mug. Only replace the two incomplete piece surfaces.
func _fix_chess(mi: MeshInstance3D) -> void:
	var mesh := ArrayMesh.new()
	for surface in mi.mesh.get_surface_count():
		var material := mi.mesh.surface_get_material(surface)
		if material.resource_name in ["hb_ceramic", "kit_frame"]:
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mi.mesh.surface_get_arrays(surface))
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	mi.mesh = mesh
	for side in 2:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.88, 0.85, 0.78) if side == 0 else Color(0.045, 0.04, 0.035)
		material.roughness = 0.85
		for file in 8:
			_piece(mi, material, side, file, true)
			_piece(mi, material, side, file, false)
	stats.chess += 1

func _piece(board: MeshInstance3D, material: Material, side: int, file: int, pawn: bool) -> void:
	var kinds := ["Rook", "Knight", "Bishop", "Queen", "King", "Bishop", "Knight", "Rook"]
	var kind := "Pawn" if pawn else String(kinds[file])
	var root := Node3D.new()
	root.name = "%s_%s_%d" % ["White" if side == 0 else "Black", kind, file]
	root.set_meta("chess_side", side)
	root.set_meta("chess_kind", kind)
	board.add_child(root)
	root.position = Vector3((float(file) - 3.5) * 0.034, 0.0125, (2.5 if pawn else 3.5) * 0.034 * (1 if side == 0 else -1))
	_cylinder(root, material, 0.012, 0.004, 0.002, board.layers)
	var height := 0.025 if pawn else (0.047 if kind in ["King", "Queen"] else 0.038)
	var stem := CylinderMesh.new()
	stem.bottom_radius = 0.007
	stem.top_radius = 0.004
	stem.height = height * 0.65
	_mesh(root, stem, material, Vector3(0, height * 0.4, 0), board.layers)
	if kind == "Knight":
		var head := BoxMesh.new()
		head.size = Vector3(0.009, 0.015, 0.016)
		var horse := _mesh(root, head, material, Vector3(0, height, -0.003), board.layers)
		horse.rotation.x = -0.35 if side == 0 else 0.35
	elif kind == "Rook":
		_cylinder(root, material, 0.009, 0.008, height, board.layers)
		for crenel in 4:
			var block := BoxMesh.new()
			block.size = Vector3(0.005, 0.005, 0.005)
			_mesh(root, block, material, Vector3(cos(crenel * PI / 2) * 0.006, height + 0.006, sin(crenel * PI / 2) * 0.006), board.layers)
	else:
		var sphere := SphereMesh.new()
		sphere.radius = 0.007 if pawn else 0.008
		sphere.height = sphere.radius * 2
		_mesh(root, sphere, material, Vector3(0, height, 0), board.layers)
		if kind == "King":
			for size in [Vector3(0.004, 0.017, 0.004), Vector3(0.012, 0.004, 0.004)]:
				var cross := BoxMesh.new()
				cross.size = size
				_mesh(root, cross, material, Vector3(0, height + 0.014, 0), board.layers)
		elif kind == "Bishop":
			var mitre := CylinderMesh.new()
			mitre.bottom_radius = 0.006
			mitre.top_radius = 0
			mitre.height = 0.013
			_mesh(root, mitre, material, Vector3(0, height + 0.008, 0), board.layers)

func _cylinder(parent: Node3D, material: Material, radius: float, height: float, y: float, layers: int) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	_mesh(parent, mesh, material, Vector3(0, y, 0), layers)

func _mesh(parent: Node3D, mesh: Mesh, material: Material, at: Vector3, layers: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.layers = layers
	parent.add_child(mi)
	mi.position = at
	return mi

func _add_cleaning_tools(world: Node) -> void:
	# Greenhouse west wall, beside the existing processing equipment; never in the walkway.
	var root := Node3D.new()
	root.name = "GreenhouseCleaningTools"
	world.add_child(root)
	var zones := ColonyZones.from_manifest("res://data/colony_manifest.json")
	var room: Dictionary = {}
	for r: Dictionary in zones.rooms:
		if r.name == "Greenhouse":
			room = r
	if room.is_empty():
		return
	root.global_position = Vector3(float(room.x0) + 0.16, 0, 6.15)
	var layers := zones.bit_of("Greenhouse")
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.38, 0.18)
	wood.roughness = 0.95
	var pole := CylinderMesh.new()
	pole.top_radius = 0.015
	pole.bottom_radius = 0.015
	pole.height = 1.25
	_mesh(root, pole, wood, Vector3(0, 1.05, 0), layers)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.75, 0.81, 0.83)
	cloth.roughness = 1
	for i in 12:
		var strand := CylinderMesh.new()
		strand.top_radius = 0.009
		strand.bottom_radius = 0.013
		strand.height = 0.22
		_mesh(root, strand, cloth, Vector3(sin(i * 2.4) * 0.065, 0.34, cos(i * 2.4) * 0.065), layers)
	var towel := BoxMesh.new()
	towel.size = Vector3(0.035, 0.46, 0.3)
	_mesh(root, towel, cloth, Vector3(0, 1.68, -0.28), layers)
	for hook_at in [Vector3(-0.06, 1.68, 0), Vector3(-0.06, 1.92, -0.28)]:
		var peg := CylinderMesh.new()
		peg.top_radius = 0.018
		peg.bottom_radius = 0.018
		peg.height = 0.14
		_mesh(root, peg, wood, hook_at, layers).rotation.z = PI / 2
