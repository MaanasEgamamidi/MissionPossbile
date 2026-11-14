shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Opaque colony surface: a run-time port of the Blender material builder gc_mat._surface.
//
// Blender builds every opaque material from one palette colour plus procedural layers: macro variation, roughness
// smudges, edge wear on the rounded edges, grime in crevices, settled Mars dust on upward faces, and micro relief.
// This shader computes the same layers with the same constants, so nothing has to be baked into textures.
// Inputs that Blender takes from the mesh travel as the vertex colour written by the exporter:
//     COLOR.r = cavity (0 flat .. 1 crease)     COLOR.g = 1 on rounded-edge faces (gc_edge)     COLOR.b = per-part random (gc_part)
// Differences from Blender: cavity is the mesh's own curvature, not ray-traced occlusion within 35 cm; value noise
// stands in for Perlin noise; relief finer than a pixel fades out instead of being supersampled.

#include "res://materials/colony_noise.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.8);
uniform float roughness : hint_range(0.0, 1.0) = 0.6;      // class baseline r0
uniform float roughness_variation_gain : hint_range(0.0, 1.0) = 1.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform int class_id = 0;        // 0 other, 1 paint, 2 plastic/floor/rubber/leather/ceramic, 3 metal, 4 fabric, 5 wood, 6 leaf, 7 soil/rock/foam, 8 solar
uniform float var = 0.05;
uniform float wear = 0.0;
uniform float grime = 0.0;
uniform float bump = 0.01;
uniform float bscale = 300.0;
uniform float coat = 0.0;
uniform vec3 edge_color : source_color = vec3(0.77, 0.77, 0.78);   // (0.55, 0.56, 0.57) linear
uniform float edge_metal = 1.0;
uniform float edge_rough = 0.35;
uniform float dust_k = 1.0;
uniform vec3 dust_color : source_color = vec3(0.6588, 0.4314, 0.2824);   // gc_mat.DUST_LIN (0.36, 0.165, 0.075) linear
uniform float dust_roughness = 0.93;
uniform float dust_gain = 1.0;
uniform float grime_gain = 1.0;
uniform float bump_gain = 1.0;
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
instance uniform float dust = 0.0;      // the object's 'dust' property (0.05 Med Bay .. 1.0 outdoors)
instance uniform float power = 1.0;     // 0 = fixture switched off

varying vec3 o_pos;
varying vec3 w_nrm;
varying float rnd;

void vertex() {
	rnd = hash13(MODEL_MATRIX[3].xyz * 3.17);
	o_pos = VERTEX + vec3(rnd * 37.0);          // per-copy offset, so copies of one asset do not share a pattern
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 bump_normal(vec3 n, vec3 pos, float h, float amount) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	return normalize(abs(det) * n - amount * grad);
}

void fragment() {
	vec3 p = o_pos;
	float cav = COLOR.r;
	float edge = COLOR.g;
	float part = COLOR.b;

	// macro variation: per copy + per part + broad noise
	float n_macro = fbm(p * 1.3, 3, 0.5);
	float jit = rnd * 0.6 + part * 0.4;
	float v = (n_macro - 0.5) * 1.4 + (jit - 0.5) * 0.8;
	vec3 color = albedo * mix(1.0 - var, 1.0 + var, v * 0.5 + 0.5);
	if (class_id == 5) {            // wood: grain bands along local X, bent by noise
		float w = sin((p.x * 3.5 + 6.0 * (fbm(p * 1.5, 3, 0.5) - 0.5)) * 6.2832) * 0.5 + 0.5;
		color = mix(color, albedo * 0.55, mapr(w, 0.2, 0.9));
	} else if (class_id == 6) {     // leaf: value varies leaf to leaf
		color *= mapr4(n_macro, 0.3, 0.7, 0.85, 1.15);
	} else if (class_id == 8) {     // solar: silver cell lines every 156 mm
		vec3 s = fract(p * 6.4);
		float line = max(mapr4(s.x, 0.0, 0.03, 1.0, 0.0), mapr4(s.z, 0.0, 0.03, 1.0, 0.0));
		color = mix(color, vec3(0.5, 0.52, 0.55), line * detail_fade(p, 6.4));
	}

	// roughness variation: smudges, fingerprints, polish
	float rough = roughness + (fbm(p * 5.0, 4, 0.6) - 0.5) * (class_id == 3 ? 0.16 : 0.22) * roughness_variation_gain;
	float metal = metallic;

	// edge wear: sparse chips on the rounded edges
	if (wear > 0.0 && edge > 0.01) {
		float n_w = fbm(p * 7.0, 4, 0.75);
		float n_f = fbm(p * 60.0, 2, 0.5);
		float spot = mapr(n_w + 0.25 * n_f, 0.86 - 0.16 * wear, 0.9 - 0.16 * wear);
		float wmask = edge * spot;
		if (class_id == 1) {
			color = mix(color, edge_color, wmask);
			metal = mix(metal, edge_metal, wmask);
			rough = mix(rough, edge_rough, wmask);
		} else if (class_id == 2 || class_id == 5) {
			vec3 lighter = mix(vec3(dot(color, vec3(0.2126, 0.7152, 0.0722))), color, 0.8) * 1.35;
			color = mix(color, lighter, wmask * 0.7);
			rough = mix(rough, 0.7, wmask);
		} else if (class_id == 3) {
			rough = mix(rough, 0.18, wmask);
		}
	}

	// grime in crevices
	float gmask = mapr(cav, 0.1, 0.7) * grime * grime_gain;
	color = mix(color, color * vec3(0.45, 0.42, 0.4), gmask);
	rough = mix(rough, 0.85, gmask * 0.6);

	// dust: upward faces + corners, scaled by the object's dust value
	float ny = normalize(w_nrm).y;
	float up = mapr(ny, 0.25, 0.85);
	float patchy = mapr(fbm(p * 2.2, 5, 0.65), 0.35, 0.65) * mapr4(fbm(p * 30.0, 3, 0.5), 0.2, 0.8, 0.6, 1.0);
	float not_down = mapr(ny, -0.55, 0.05);
	float crev = mapr(cav, 0.2, 0.8) * 0.45 * not_down;
	float d = clamp((up * patchy + crev) * dust * dust_k * dust_gain, 0.0, 1.0);
	color = mix(color, dust_color, d);
	rough = mix(rough, dust_roughness, d);
	metal = mix(metal, 0.0, d);

	// micro relief
	if (bump > 0.0 && bump_gain > 0.0) {
		float fade = detail_fade(p, bscale);
		if (fade > 0.01) {
			float h;
			if (class_id == 3) {
				h = fbm(vec3(p.x * bscale * 3.0, p.y * bscale * 0.05, p.z * bscale * 3.0), 3, 0.5);      // brushed streaks
			} else if (class_id == 4) {
				h = (sin(p.x * bscale * 6.2832) * 0.5 + 0.5) * (sin(p.z * bscale * 6.2832) * 0.5 + 0.5);   // weave
			} else if (class_id == 7) {
				h = voronoi(p * bscale) + 0.5 * fbm(p * bscale * 3.0, 2, 0.5);
			} else {
				h = fbm(p * bscale, 3, 0.5);
			}
			NORMAL = bump_normal(NORMAL, VERTEX, h, min(1.0, bump * 10.0) * (0.6 / bscale) * fade * bump_gain);
		}
	}

	ALBEDO = color;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = clamp(metal, 0.0, 1.0);
	SPECULAR = specular;
	if (coat > 0.0) {
		CLEARCOAT = coat;
		CLEARCOAT_ROUGHNESS = 0.08;
	}
	if (class_id == 6) {
		BACKLIGHT = color * 0.3;      // thin leaves pass some light
	}
	EMISSION = emission * emission_energy * power;
}
