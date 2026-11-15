extends RefCounted
## T12 air leak look (owner feedback 2026-11-14: the leak at the exit-tunnel inner door showed as a cloud of big
## see-through balls). The broken door glb's "air_leak_vfx__broken" node keeps its place in the scene (so the presenter
## still turns it on and off as an effect), but its ball meshes are hidden and a soft vapour jet takes over: small
## white puffs that blow out of the door gap, grow, drift and fade, like air escaping through a bad seal.
## Presentation only. Loaded by path (no class_name).

## Set on the hidden ball meshes and on the jet, so the role glow and the aim target leave them alone.
const META := &"air_leak_vfx"
const PUFFS := 70
const LIFETIME := 1.3
## Soft white with a little blue, never pure white (it sits over a grey door).
const VAPOUR := Color(0.92, 0.95, 1.0)


## Hides `leak`'s ball meshes and adds the vapour jet in their place. `entry` is the part's data record (its
## model_bounds give the door plane).
static func replace(leak: Node, entry: Dictionary) -> void:
	if leak == null or leak.has_meta(META):
		return
	leak.set_meta(META, true)
	var box := AABB()
	var first := true
	var layers := 1
	for mi in ([leak] if leak is MeshInstance3D else []) + leak.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := m.global_transform if m.is_inside_tree() else m.transform
		var b := xf * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
		layers = m.layers
		m.set_meta(META, true)
		# Drop the balls but keep the node: the presenter shows and hides it (and so the jet under it) as an effect.
		m.mesh = null
	if first or not (leak is Node3D):
		return
	var door_z := box.get_center().z
	var b: Variant = entry.get("model_bounds", {})
	if b is Dictionary and (b as Dictionary).get("center") is Array:
		door_z = float((b.center as Array)[2])
	var out := signf(box.get_center().z - door_z)
	if out == 0.0:
		out = -1.0          # toward the hangar, where the crew stands
	var jet := CPUParticles3D.new()
	jet.name = "VapourJet"
	jet.set_meta(META, true)
	jet.layers = layers
	jet.amount = PUFFS
	jet.lifetime = LIFETIME
	jet.local_coords = false
	jet.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	# A tall thin slot along the door gap.
	jet.emission_box_extents = Vector3(maxf(0.04, box.size.x * 0.12), maxf(0.2, box.size.y * 0.38), 0.03)
	jet.direction = Vector3(0, 0.15, out)
	jet.spread = 28.0
	jet.initial_velocity_min = 1.1
	jet.initial_velocity_max = 2.4
	jet.gravity = Vector3(0, 0.25, 0)
	jet.damping_min = 1.2
	jet.damping_max = 2.0
	jet.scale_amount_min = 0.22
	jet.scale_amount_max = 0.45
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.6))
	jet.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(VAPOUR, 0.0))
	fade.set_color(1, Color(VAPOUR, 0.0))
	fade.add_point(0.12, Color(VAPOUR, 0.55))
	fade.add_point(0.55, Color(VAPOUR, 0.3))
	jet.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	jet.mesh = quad
	jet.material_override = puff_material()
	var host := leak as Node3D
	jet.transform = Transform3D(Basis.IDENTITY, host.global_transform.affine_inverse() * Vector3(box.get_center().x, box.get_center().y, door_z + out * 0.05) if host.is_inside_tree() else Vector3(box.get_center().x, box.get_center().y, door_z + out * 0.05))
	host.add_child(jet)
	jet.emitting = true


## A soft round puff: camera-facing, unlit, edges fade to nothing.
static func puff_material() -> StandardMaterial3D:
	var tex := GradientTexture2D.new()
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	tex.gradient = g
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m
