class_name DomeDeck
extends RefCounted
## The floor of the dome plaza (the walkway band between the room block and the glass hall). The source map has no
## object for it: the browser game (Grand Colony artifact, colony_outpost.template.html "dome deck") draws it in code,
## so the Godot map showed bare crater sand there. This rebuilds it the same way (owner 2026-11-14: "if you have a
## problem on how the map should look on the inside always refer back to the artifact"):
##   1 m cells over the glass-hall footprint (superellipse of manifest.dome, cells with edge distance > 0.99 left out),
##   a 2 m checker of two dark brown-greys (#3e332e / #473a33, roughness 0.8, metallic 0.15), 3 cm below the room floors.
## The terrain under the plaza is flat at -0.05 m, so the deck needs no collision of its own. Cells wholly inside a room
## rectangle are skipped: the room's own floor tiles cover them.

const Y := -0.03
const COLOUR_A := Color("3e332e")
const COLOUR_B := Color("473a33")


static func build(world: Node3D, manifest_path: String) -> MeshInstance3D:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var d: Dictionary = data.dome
	var cx := float(d.cx)
	var cy := float(d.cy)
	var rx := float(d.rx)
	var ry := float(d.ry)
	var n := float(d.get("n", 2.0))
	var rooms: Array = data.rooms
	var verts := PackedVector3Array()
	var colours := PackedColorArray()
	var normals := PackedVector3Array()
	var x := floorf(cx - rx)
	while x < cx + rx:
		var y := floorf(cy - ry)          # Blender y = -Godot z
		while y < cy + ry:
			var e := pow(pow(absf((x + 0.5 - cx) / rx), n) + pow(absf((y + 0.5 - cy) / ry), n), 1.0 / n)
			if e <= 0.99 and not _inside_room(rooms, x, y):
				var gz := -y                 # Godot z of the cell's y edge
				var c := COLOUR_A if (int(floorf(x / 2.0)) + int(floorf(gz / 2.0))) & 1 else COLOUR_B
				# clockwise seen from above = Godot's front face
				for p in [Vector3(x, Y, gz), Vector3(x, Y, gz - 1), Vector3(x + 1, Y, gz),
						Vector3(x + 1, Y, gz), Vector3(x, Y, gz - 1), Vector3(x + 1, Y, gz - 1)]:
					verts.append(p)
					colours.append(c)
					normals.append(Vector3.UP)
			y += 1.0
		x += 1.0
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.8
	mat.metallic = 0.15
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "DomeDeck"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = ColonyZones.from_manifest(manifest_path).bit_of(ColonyZones.PLAZA)
	mi.set_meta("area", ColonyZones.PLAZA)
	world.add_child(mi)
	return mi


## True when the 1 m cell [x, x+1] x [y, y+1] (Blender coordinates) lies wholly inside one room rectangle.
static func _inside_room(rooms: Array, x: float, y: float) -> bool:
	for r: Dictionary in rooms:
		if x >= float(r.x0) and x + 1.0 <= float(r.x1) and y >= float(r.y0) and y + 1.0 <= float(r.y1):
			return true
	return false
