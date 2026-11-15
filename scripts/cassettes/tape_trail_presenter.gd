extends Node3D
## Gold guide lines to the room tapes (owner 2026-11-14, like the guide lines in Marvel's Wolverine): one line of small
## twinkling gold sparkles per tape, at about chest height (owner 2026-11-15: they were a hand's width above the floor
## and too small to spot), all starting together just inside the base (the
## airlock side of the exit tunnel's inner door) and fanning out through the rooms and doorways to each tape, which
## sparkles gold too (cassette_presenter.gd). The sparkles drift slowly along the line toward the tape, so the way to go
## reads at a glance. Where several lines share a corridor they run side by side (the offsets are baked into the
## paths), so the player sees one line per tape and picks one. Paths: data/tape_trails.json, baked from the real
## walkable floor by tools/godot/bake_tape_trails.gd (run it again when the map or a tape's spot changes).
## Owner 2026-11-14: the flat gold ribbons were replaced by sparkle particles, built for no lag: ONE GPUParticles3D per
## line (directed-points emission from a baked points + tangents texture), about 1800 sparkles in total at most (half on
## the Low graphics preset), 30 fps fixed step with interpolation, no shadows, lights, collision or sub-emitters, and one
## shared star texture, draw mesh and draw material for every sparkle emitter (lines, tapes).
## Shown only in tutorial mode while not every tape is found (TutorialSystem.repairs_unlocked). A tape's line thins out
## when that tape is collected and its last sparkles fade; all lines go when every tape is found or the tutorial is not
## active. Loading a save or joining late shows the lines as the state says, without a fade.
## Presentation only: it reads the replicated colony state. Created by CassettePresenter.setup and refreshed with the
## tapes. Loaded by path (no class_name).

const DATA_PATH := "res://data/tape_trails.json"
## Rich gold, the same as the tapes' sparkles.
const GOLD := Color(1.0, 0.75, 0.2)
# Owner 2026-11-14: replaced by sparkle particles
# const WIDTH := 0.22
# ## Height above the floor point (the floor tiles are drawn a little above their collision).
# const LIFT := 0.03
const CORNER_RADIUS := 0.45
const CORNER_STEPS := 6
## Seconds a collected tape's line takes to thin out (its last sparkles then live out their LIFETIME).
const FADE_SECONDS := 0.7

## Sparkle height above the floor point, metres (random per emission point, in this range): about chest height of a
## 1.8 m crew member, so the line runs through the middle of the view and not along the floor.
const LIFT_MIN := 1.05
const LIFT_MAX := 1.35
## Sideways scatter of the emission points either side of the path, metres (lanes are 0.24 m apart or more).
const SCATTER := 0.06
## Distance between emission points along a line, metres (widened when the lines are long, see TOTAL_CAP).
const SPACING := 0.15
## Most sparkles across all lines together (one sparkle per emission point).
const TOTAL_CAP := 1800
## Seconds one sparkle lives; it drifts DRIFT_MIN..DRIFT_MAX m/s along the path toward the tape.
const LIFETIME := 1.2
const DRIFT_MIN := 0.35
const DRIFT_MAX := 0.6
## Sparkle sprite size, metres (was 0.06).
const SPARKLE_SIZE := 0.2
## The darker amber rim of each sparkle: it keeps the gold readable against the base's white walls.
const GOLD_RIM := Color(0.93, 0.47, 0.04)

# Owner 2026-11-14: replaced by sparkle particles
# const SHADER_CODE := "
# shader_type spatial;
# // Gold tape trail (tape_trail_presenter.gd): a flat ribbon whose bright chevrons flow toward the tape and pulse
# // gently, with brighter edges. Soft and steady: no flicker (players aged 9-12). UV.x runs across the ribbon (0..1),
# // UV.y is metres along it, from the start toward the tape.
# render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#
# uniform vec4 gold : source_color = vec4(1.0, 0.75, 0.2, 1.0);
# uniform float fade = 1.0;
# uniform float flow_speed = 1.1;
# uniform float chevron_spacing = 0.9;
# uniform float pulse_speed = 1.7;
#
# void fragment() {
# 	float ax = abs(UV.x * 2.0 - 1.0);
# 	float s = UV.y;
# 	float ph = (s + ax * 0.24) / chevron_spacing - TIME * flow_speed / chevron_spacing;
# 	float f = fract(ph);
# 	float w = fwidth(ph);
# 	float aa = max(w, 0.001) * 1.5;
# 	float chev = smoothstep(0.0, 0.06 + aa, f) * (1.0 - smoothstep(0.30, 0.38 + aa, f));
# 	chev *= 1.0 - smoothstep(0.12, 0.35, w);
# 	float edge = smoothstep(0.6, 0.86, ax);
# 	float outer = 1.0 - smoothstep(0.88, 1.0, ax);
# 	float pulse = 0.86 + 0.14 * sin(TIME * pulse_speed - s * 0.4);
# 	vec3 deep = gold.rgb * vec3(0.95, 0.82, 0.55);
# 	vec3 bright = mix(gold.rgb, vec3(1.0, 0.9, 0.55), 0.3) * 1.25;
# 	vec3 col = mix(deep, bright, max(chev, edge * 0.7));
# 	float a = mix(0.88, 1.0, max(chev, edge)) * outer * smoothstep(0.0, 0.3, s);
# 	ALBEDO = col * pulse;
# 	ALPHA = clamp(a * fade, 0.0, 1.0);
# }
# "
#
# static var _shader: Shader

## Shared by every sparkle emitter (lines and tapes): made once.
static var _star_texture: Texture2D
static var _sparkle_material: StandardMaterial3D
static var _sparkle_mesh: QuadMesh
static var _scale_texture: CurveTexture
static var _color_texture: GradientTexture1D

var services: GameServices
## Where the lines start (data "start").
var start := Vector3.ZERO
## cassette id -> {"node": GPUParticles3D, "points": PackedVector3Array, "fade": float (0..1 now),
##                 "target": float (0 or 1), "drain": float (seconds left for the last sparkles after a fade-out)}
var trails := {}


## {"start": Vector3, "trails": {cassette_id: PackedVector3Array}} from the baked file ({} trails when missing).
static func load_data(path := DATA_PATH) -> Dictionary:
	var out := {"start": Vector3.ZERO, "trails": {}}
	if not FileAccess.file_exists(path):
		push_warning("TapeTrailPresenter: no %s (run tools/godot/bake_tape_trails.gd)" % path)
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return out
	var s: Variant = data.get("start")
	if s is Array and (s as Array).size() == 3:
		out.start = Vector3(float(s[0]), float(s[1]), float(s[2]))
	var lines: Variant = data.get("trails")
	if lines is Dictionary:
		for id: String in lines:
			var pts := PackedVector3Array()
			for p: Variant in lines[id]:
				if p is Array and (p as Array).size() == 3:
					pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
			if pts.size() >= 2:
				out.trails[id] = pts
	return out


# Owner 2026-11-14: replaced by sparkle particles
# static func shader() -> Shader:
# 	if _shader == null:
# 		_shader = Shader.new()
# 		_shader.code = SHADER_CODE
# 	return _shader


func setup(p_services: GameServices, path := DATA_PATH) -> void:
	services = p_services
	name = "TapeTrails"
	top_level = true
	var data := load_data(path)
	start = data.start
	var layers := _layers()
	var low := is_inside_tree() and GraphicsQuality.applied_level(get_tree()) == GraphicsQuality.Level.LOW
	# One sparkle per emission point; long lines get wider spacing so all lines together stay under TOTAL_CAP.
	var total := 0.0
	for id: String in data.trails:
		if CassetteCatalog.TAPES.has(id):
			total += path_length(rounded(data.trails[id]))
	var spacing := maxf(SPACING, total / float(TOTAL_CAP))
	var index := 0
	for id: String in data.trails:
		if not CassetteCatalog.TAPES.has(id):
			continue
		var pts: PackedVector3Array = data.trails[id]
		# Owner 2026-11-14: replaced by sparkle particles
		# var mat := ShaderMaterial.new()
		# mat.shader = shader()
		# mat.set_shader_parameter(&"gold", GOLD)
		# mat.set_shader_parameter(&"fade", 0.0)
		# var mesh := MeshInstance3D.new()
		# mesh.name = "Trail_" + id
		# mesh.mesh = ribbon(pts, WIDTH, LIFT)
		# mesh.material_override = mat
		# mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# mesh.layers = layers
		# mesh.visible = false
		# add_child(mesh)
		# trails[id] = {"mesh": mesh, "material": mat, "points": pts, "fade": 0.0, "target": 0.0}
		var node := sparkle_line(pts, spacing, 7919 * (index + 1), low)
		node.name = "Trail_" + id
		node.layers = layers
		add_child(node)
		trails[id] = {"node": node, "points": pts, "fade": 0.0, "target": 0.0, "drain": 0.0}
		index += 1
	refresh(true)


## Render layers: every colony zone's bit plus the sun layer, since the lines cross rooms, the plaza, the open ground
## and the garden dome (ColonyZones); all 20 layers when the zones are not known.
func _layers() -> int:
	if services == null or services.zones == null:
		return (1 << 20) - 1
	var mask := services.zones.sun_bit()
	for zone: String in services.zones.names:
		mask |= services.zones.bit_of(zone)
	return mask


## True while the lines are wanted at all: tutorial mode, and not every tape found yet.
func lines_wanted() -> bool:
	if services == null or not services.has_game():
		return false
	var st := services.state()
	return TutorialSystem.tutorial_active(st) and not TutorialSystem.repairs_unlocked(st)


## Follows the state. `snap`: show it as it is at once (setup, a loaded or joined colony), no fade.
func refresh(snap := false) -> void:
	var wanted := lines_wanted()
	var st := services.state() if services != null and services.has_game() else null
	for id: String in trails:
		var t: Dictionary = trails[id]
		t.target = 1.0 if wanted and st != null and not CassetteCatalog.collected(st, id) else 0.0
		if snap:
			t.fade = t.target
		_apply(t, snap)


func _process(delta: float) -> void:
	step(delta)


## Advances the fades and the last sparkles of faded lines (tests call it directly).
func step(delta: float) -> void:
	for id: String in trails:
		var t: Dictionary = trails[id]
		var draining := float(t.drain) > 0.0
		if draining:
			t.drain = maxf(0.0, float(t.drain) - delta)
		if not is_equal_approx(float(t.fade), float(t.target)):
			t.fade = move_toward(float(t.fade), float(t.target), delta / FADE_SECONDS)
			_apply(t)
		elif draining and float(t.drain) <= 0.0:
			_apply(t)


## Fade 1 = the full line; lower thins it out (amount_ratio); 0 stops emitting, and the line is hidden once its last
## sparkles have faded (at once when `snap`).
func _apply(t: Dictionary, snap := false) -> void:
	var node := t.node as GPUParticles3D
	var fade := clampf(float(t.fade), 0.0, 1.0)
	var on := fade > 0.001
	node.amount_ratio = fade
	if on:
		t.drain = 0.0
		if not node.emitting:
			if snap:
				node.restart() # starts full (preprocess), not growing in
			else:
				node.emitting = true
	elif node.emitting:
		node.emitting = false
		t.drain = 0.0 if snap else LIFETIME
	elif snap:
		t.drain = 0.0
	node.visible = on or float(t.drain) > 0.0


## True while the tape's line is on show and not fading out.
func shown(cassette_id: String) -> bool:
	return trails.has(cassette_id) and float(trails[cassette_id].target) > 0.0 and (trails[cassette_id].node as Node3D).visible


## Number of lines drawn now (fading ones included).
func visible_count() -> int:
	var n := 0
	for id: String in trails:
		if (trails[id].node as Node3D).visible:
			n += 1
	return n


## The last point of a tape's line (world), or Vector3.INF.
func end_point(cassette_id: String) -> Vector3:
	if not trails.has(cassette_id):
		return Vector3.INF
	var pts: PackedVector3Array = trails[cassette_id].points
	return pts[pts.size() - 1]


# ---------------------------------------------------------------- the sparkle line

## One GPUParticles3D for a whole line: one emission point every `spacing` metres along the rounded path (a little
## scatter up and sideways, from a fixed seed), each with the path direction as its normal, so every sparkle drifts
## along the path toward the tape. Amount = number of points (half on Low). Starts hidden and not emitting.
static func sparkle_line(pts: PackedVector3Array, spacing: float, seed_value: int, low: bool) -> GPUParticles3D:
	var line := rounded(pts)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var points := PackedVector3Array()
	var dirs := PackedVector3Array()
	var carry := 0.0
	for i in range(1, line.size()):
		var a := line[i - 1]
		var b := line[i]
		var seg := a.distance_to(b)
		if seg < 0.0001:
			continue
		var dir := (b - a) / seg
		var side := Vector3(-dir.z, 0.0, dir.x).normalized()
		var s := carry
		while s < seg:
			points.append(a + dir * s + Vector3(0.0, rng.randf_range(LIFT_MIN, LIFT_MAX), 0.0) + side * rng.randf_range(-SCATTER, SCATTER))
			dirs.append(dir)
			s += spacing
		carry = s - seg
	if points.is_empty():
		var d := (line[line.size() - 1] - line[0]).normalized()
		points.append(line[0] + Vector3(0.0, LIFT_MIN, 0.0))
		dirs.append(d if d != Vector3.ZERO else Vector3.FORWARD)
	var lo := points[0]
	var hi := points[0]
	for p: Vector3 in points:
		lo = lo.min(p)
		hi = hi.max(p)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS
	process.emission_point_texture = _vector_texture(points)
	process.emission_normal_texture = _vector_texture(dirs)
	process.emission_point_count = points.size()
	# Directed points turn local +Z onto each point's normal (the path direction).
	process.direction = Vector3(0.0, 0.0, 1.0)
	process.spread = 6.0
	process.initial_velocity_min = DRIFT_MIN
	process.initial_velocity_max = DRIFT_MAX
	process.gravity = Vector3.ZERO
	process.lifetime_randomness = 0.35
	_style(process)
	var node := GPUParticles3D.new()
	node.amount = maxi(4, int(float(points.size()) * 0.5) if low else points.size())
	node.lifetime = LIFETIME
	node.preprocess = LIFETIME
	node.process_material = process
	node.local_coords = false
	# Drift, scatter and sprite size around the points' bounds (the node sits at the world origin).
	var grow := Vector3.ONE * (DRIFT_MAX * LIFETIME + SPARKLE_SIZE)
	node.visibility_aabb = AABB(lo - grow, hi - lo + grow * 2.0)
	_tune(node)
	node.emitting = false
	node.visible = false
	return node


## Length of a polyline, metres.
static func path_length(pts: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total


## A float RGB texture of `values`, one per texel, rows of up to 2048 (padded with the last value): the format
## ParticleProcessMaterial reads its emission points and normals from.
static func _vector_texture(values: PackedVector3Array) -> ImageTexture:
	var count := values.size()
	var w := mini(count, 2048)
	var h := ceili(float(count) / float(w))
	var data := PackedFloat32Array()
	data.resize(w * h * 3)
	for i in w * h:
		var v := values[mini(i, count - 1)]
		data[i * 3] = v.x
		data[i * 3 + 1] = v.y
		data[i * 3 + 2] = v.z
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBF, data.to_byte_array())
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- shared sparkle look (lines and tapes)

## The cheap per-emitter settings every gold sparkle emitter uses: the shared draw mesh, 30 fps fixed step with
## interpolation, no shadows or GI, drawn in index order.
static func _tune(node: GPUParticles3D) -> void:
	node.draw_pass_1 = sparkle_mesh()
	node.fixed_fps = 30
	node.interpolate = true
	node.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## The twinkle every gold sparkle shares: random spin and size, and the shared size curve and colour ramp (each
## sparkle swells in, dips, flares again and fades out).
static func _style(process: ParticleProcessMaterial) -> void:
	process.angle_min = 0.0
	process.angle_max = 360.0
	process.scale_min = 0.8
	process.scale_max = 1.4
	process.scale_curve = _scale_curve_texture()
	process.color_ramp = _color_ramp_texture()


## A gold sparkle emitter for something small, e.g. an idle tape: `amount` sparkles twinkling in a box of half size
## `extents` around the node and drifting slowly up. Its ParticleProcessMaterial is new each call (they are few).
static func idle_sparkles(amount: int, extents: Vector3, lifetime: float) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = Vector3.UP
	process.spread = 30.0
	process.initial_velocity_min = 0.03
	process.initial_velocity_max = 0.09
	process.gravity = Vector3(0.0, 0.03, 0.0)
	process.lifetime_randomness = 0.4
	_style(process)
	var node := GPUParticles3D.new()
	node.amount = maxi(1, amount)
	node.lifetime = lifetime
	node.preprocess = lifetime
	node.process_material = process
	node.local_coords = false
	var grow := Vector3(0.3, 0.5, 0.3)
	node.visibility_aabb = AABB(-extents - grow, (extents + grow) * 2.0)
	_tune(node)
	return node


## The tiny camera-facing quad all gold sparkles draw, with the shared material.
static func sparkle_mesh() -> QuadMesh:
	if _sparkle_mesh == null:
		_sparkle_mesh = QuadMesh.new()
		_sparkle_mesh.size = Vector2(SPARKLE_SIZE, SPARKLE_SIZE)
		_sparkle_mesh.material = sparkle_material()
	return _sparkle_mesh


## Unshaded, billboarded (per particle), no shadows, no depth write; takes the particle colour. Alpha blended, not
## additive (owner 2026-11-15, "more visible"): added light disappears on the base's bright walls, a gold sprite with
## an amber rim reads on light and dark alike.
static func sparkle_material() -> StandardMaterial3D:
	if _sparkle_material == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = star_texture()
		mat.disable_receive_shadows = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_sparkle_material = mat
	return _sparkle_material


## A soft four-pointed gold star with a warm white core, drawn once in code (no texture file), with mipmaps so far
## sparkles do not shimmer.
static func star_texture() -> Texture2D:
	if _star_texture != null:
		return _star_texture
	const N := 64
	var white := Color(1.0, 0.97, 0.86)
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var dx := (float(x) + 0.5) / N * 2.0 - 1.0
			var dy := (float(y) + 0.5) / N * 2.0 - 1.0
			var r := sqrt(dx * dx + dy * dy)
			var core := exp(-r * r * 22.0)
			var halo := exp(-r * r * 5.0) * 0.55
			var rays := exp(-absf(dx) * 20.0) * exp(-absf(dy) * 2.8) + exp(-absf(dy) * 20.0) * exp(-absf(dx) * 2.8)
			var a := clampf(core * 1.2 + rays + halo, 0.0, 1.0) * clampf((1.0 - r) * 1.6, 0.0, 1.0)
			# White-hot centre, gold body, amber rim.
			var c := GOLD.lerp(GOLD_RIM, clampf(r * 2.2 - 0.25, 0.0, 1.0)).lerp(white, clampf(core * 1.4, 0.0, 1.0))
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	img.generate_mipmaps()
	_star_texture = ImageTexture.create_from_image(img)
	return _star_texture


## Size over a sparkle's life: in, a small dip, a second flare, out (the twinkle).
static func _scale_curve_texture() -> CurveTexture:
	if _scale_texture == null:
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.1))
		curve.add_point(Vector2(0.2, 1.0))
		curve.add_point(Vector2(0.45, 0.7))
		curve.add_point(Vector2(0.7, 1.0))
		curve.add_point(Vector2(1.0, 0.0))
		_scale_texture = CurveTexture.new()
		_scale_texture.curve = curve
	return _scale_texture


## Colour over a sparkle's life: fades in, bright, warmer, fades out. The gold itself is in the star texture (gold rays,
## warm white core), so the ramp stays near white.
static func _color_ramp_texture() -> GradientTexture1D:
	if _color_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.2, 0.65, 1.0])
		gradient.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 1.0, 1.0, 1.0),
			Color(1.0, 0.95, 0.85, 0.85), Color(1.0, 0.9, 0.7, 0.0)])
		_color_texture = GradientTexture1D.new()
		_color_texture.gradient = gradient
	return _color_texture


# ---------------------------------------------------------------- the path

## The polyline with each corner replaced by a short curve (radius up to CORNER_RADIUS).
static func rounded(pts: PackedVector3Array) -> PackedVector3Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector3Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var a := pts[i - 1]
		var b := pts[i]
		var c := pts[i + 1]
		var ab := a.distance_to(b)
		var bc := b.distance_to(c)
		if ab < 0.001 or bc < 0.001:
			continue
		var r := minf(CORNER_RADIUS, minf(ab, bc) * 0.45)
		var p1 := b + (a - b) / ab * r
		var p2 := b + (c - b) / bc * r
		for k in CORNER_STEPS + 1:
			var t := float(k) / float(CORNER_STEPS)
			out.append(p1.lerp(b, t).lerp(b.lerp(p2, t), t))
	out.append(pts[pts.size() - 1])
	return out


# Owner 2026-11-14: replaced by sparkle particles
# ## A flat ribbon `width` wide along `pts`, `lift` above them, facing up. UV.x across (0..1), UV.y metres along.
# static func ribbon(pts: PackedVector3Array, width: float, lift: float) -> ArrayMesh:
# 	var line := rounded(pts)
# 	var verts := PackedVector3Array()
# 	var normals := PackedVector3Array()
# 	var uvs := PackedVector2Array()
# 	var indices := PackedInt32Array()
# 	var along := 0.0
# 	var n := line.size()
# 	for i in n:
# 		if i > 0:
# 			along += line[i - 1].distance_to(line[i])
# 		var d_in := Vector3.ZERO
# 		var d_out := Vector3.ZERO
# 		if i > 0:
# 			d_in = Vector3(line[i].x - line[i - 1].x, 0, line[i].z - line[i - 1].z).normalized()
# 		if i < n - 1:
# 			d_out = Vector3(line[i + 1].x - line[i].x, 0, line[i + 1].z - line[i].z).normalized()
# 		var tangent := (d_in + d_out).normalized()
# 		if tangent == Vector3.ZERO:
# 			tangent = d_out if d_out != Vector3.ZERO else (d_in if d_in != Vector3.ZERO else Vector3.FORWARD)
# 		var side := Vector3(-tangent.z, 0, tangent.x)
# 		# keep the width through a bend (miter), limited for sharp ones
# 		var ref := d_out if d_out != Vector3.ZERO else d_in
# 		var cos_half := absf(side.dot(Vector3(-ref.z, 0, ref.x))) if ref != Vector3.ZERO else 1.0
# 		var half := width * 0.5 / maxf(cos_half, 0.5)
# 		var p := line[i] + Vector3(0, lift, 0)
# 		verts.append(p - side * half)
# 		verts.append(p + side * half)
# 		normals.append(Vector3.UP)
# 		normals.append(Vector3.UP)
# 		uvs.append(Vector2(0.0, along))
# 		uvs.append(Vector2(1.0, along))
# 		if i > 0:
# 			var b := (i - 1) * 2
# 			indices.append_array(PackedInt32Array([b, b + 1, b + 2, b + 1, b + 3, b + 2]))
# 	var arrays := []
# 	arrays.resize(Mesh.ARRAY_MAX)
# 	arrays[Mesh.ARRAY_VERTEX] = verts
# 	arrays[Mesh.ARRAY_NORMAL] = normals
# 	arrays[Mesh.ARRAY_TEX_UV] = uvs
# 	arrays[Mesh.ARRAY_INDEX] = indices
# 	var mesh := ArrayMesh.new()
# 	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
# 	return mesh
