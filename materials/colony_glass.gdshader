shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Glazing and water (gc_mat classes 'glass' and 'water'). Blender uses real transmission; here the pane is alpha
// blended and gets more opaque and mirror-like toward grazing angles, which is what reads as glass in real time.
// A dust film settles on upward-facing glass, scaled by the object's dust value, as in gc_mat._glass.

#include "res://materials/colony_noise.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.6, 0.7, 0.75);
uniform float opacity : hint_range(0.0, 1.0) = 0.2;        // looking straight through
uniform float roughness : hint_range(0.0, 1.0) = 0.03;
uniform float fresnel_power = 4.0;
uniform float edge_opacity = 0.85;                           // at grazing angles
uniform float dust_k = 0.6;
uniform vec3 dust_color : source_color = vec3(0.6588, 0.4314, 0.2824);
instance uniform float dust = 0.0;
instance uniform float power = 1.0;

varying vec3 o_pos;
varying vec3 w_nrm;

void vertex() {
	o_pos = VERTEX;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float ndv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fres = pow(1.0 - ndv, fresnel_power);
	float ny = abs(normalize(w_nrm).y);
	float film = clamp(mapr(ny, 0.1, 0.9) * mapr(fbm(o_pos * 1.5, 4, 0.5), 0.4, 0.7) * dust * dust_k, 0.0, 1.0);
	ALBEDO = mix(albedo, dust_color, film);
	ROUGHNESS = mix(roughness + (fbm(o_pos * 4.0, 3, 0.5) - 0.5) * 0.03, 0.6, film);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = clamp(mix(mix(opacity, edge_opacity, fres), 0.9, film) + power * 0.0, 0.0, 1.0);
}
