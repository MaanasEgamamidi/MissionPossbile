shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Display (gc_mat class 'screen'): dark glass with a lit interface under it. Blender lays out a procedural UI in
// physical units on the screen's own plane: panels of 11 x 7 cm with a header bar, rows of "text" (7.5 mm pitch,
// 4.5 mm glyphs, random line lengths) and some bar-graph panels. This shader draws the same kind of layout, so a
// phone, a wall display and a console all show UI at a believable density instead of one flat colour.

#include "res://materials/colony_noise.gdshaderinc"

uniform vec3 emission : source_color = vec3(0.3, 0.8, 1.0);
uniform float emission_energy = 1.6;
uniform vec2 panel = vec2(0.11, 0.07);
uniform float row = 0.0075;
uniform float glyph = 0.0045;
instance uniform float dust = 0.0;
instance uniform float power = 1.0;

varying vec3 o_pos;
varying vec3 o_nrm;

void vertex() {
	o_pos = VERTEX;
	o_nrm = NORMAL;
}

void fragment() {
	// in-plane axes of the screen face, chosen from the object-space normal (Godot Y up: Blender z = y, Blender y = -z)
	vec3 an = abs(normalize(o_nrm));
	float u = (an.y > 0.7) ? o_pos.x : ((an.x > an.z) ? -o_pos.z : o_pos.x);
	float v = (an.y > 0.7) ? -o_pos.z : o_pos.y;

	vec2 g = vec2(u, v) / panel;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float pr = hash12(cell);
	float inside = step(0.05, f.x) * step(f.x, 0.95) * step(0.08, f.y) * step(f.y, 0.92);
	float header = step(0.80, f.y) * inside;
	float body = inside * step(f.y, 0.75);

	// rows of text: dashes of random length
	float ry = f.y * panel.y / row;
	float rid = floor(ry);
	float rf = fract(ry);
	float gx = f.x * panel.x / glyph;
	float gid = floor(gx);
	float gf = fract(gx);
	float line_len = 0.2 + 0.75 * hash12(cell * 7.3 + vec2(rid, 1.0));
	float ink = step(0.18, gf) * step(gf, 0.82) * step(0.28, rf) * step(rf, 0.72) * step(hash12(vec2(gid, rid) + cell * 3.1), 0.8);
	float text = ink * step((f.x - 0.05) / 0.9, line_len) * body * step(hash12(cell * 2.3 + vec2(rid, 5.0)), 0.85);

	// bar-graph panels
	float bx = floor(f.x * 14.0);
	float bh = 0.12 + 0.6 * hash12(cell * 1.7 + vec2(bx, 2.0));
	float bar = step(fract(f.x * 14.0), 0.68) * step(0.1, f.y) * step(f.y, 0.1 + bh * 0.62) * inside;

	float is_graph = step(0.74, pr);
	float content = mix(text, bar, is_graph);
	float ui = max(header * 0.5, content) + 0.025 * inside;

	// when a glyph is smaller than a pixel, show the layout's average brightness instead of shimmer
	float fade = detail_fade(vec3(u, v, 0.0), 0.5 / glyph);
	ui = mix(0.14 * inside + 0.02, ui, fade);
	content = mix(0.3, content, fade);

	vec3 whiter = emission * 0.45 + vec3(0.55);
	ALBEDO = vec3(0.01, 0.012, 0.014);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.03;
	EMISSION = mix(emission, whiter, content * 0.6) * ui * emission_energy * power + vec3(dust * 0.0);
}
