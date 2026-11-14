shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Mars terrain: a run-time port of the Blender terrain material (gc_terrain.terrain_material).
// The source mesh carries four colour attributes; the exporter packs the ones this shader uses:
//     COLOR.rgb = base albedo (gc_alb, linear)      COLOR.a = bare-rock mask (gc_ma.b)
//     UV.x  = pebble factor (1 - dune) * (0.35 + 0.65 * gravel)        UV.y  = hollow (+) / ridge (-)  (gc_mb.r)
//     UV2.x = distance from the rut centre line in metres, 99 where there is no track       UV2.y = metres along the track
// Ported layers: tone variation, dark basalt-sand patches, pale dust drifts in hollows, bare rock on steep ground,
// pebble specks, grain, rover ruts with tread and dust berms, roughness, micro relief.
// Not ported: strata beds on the mesa walls, wind streaks, talus streaks, dune ripples, rock fractures.

#include "res://materials/colony_noise.gdshaderinc"

uniform float detail_gain = 1.0;      // 0 turns the close-up layers off
uniform float bump_gain = 1.0;
uniform float specular = 0.3;
instance uniform float dust = 0.0;
instance uniform float power = 1.0;

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
	vec3 p = w_pos;
	vec3 alb = COLOR.rgb;
	float rockm = COLOR.a;
	float pebf = UV.x;
	float hol = UV.y;
	float off = UV2.x;
	float tal = UV2.y;
	float ny = normalize(w_nrm).y;

	// large-scale tone variation, darker basalt-sand patches, pale dust drifts
	vec3 color = alb * mapr4(fbm(p * 0.025, 4, 0.55), 0.3, 0.7, 0.9, 1.08);
	float basalt = mapr(fbm(p * 0.07, 5, 0.6), 0.56, 0.66) * (1.0 - step(0.25, hol));
	color = mix(color, vec3(0.11, 0.075, 0.06), basalt * 0.55);
	float drift = clamp(mapr(hol, 0.06, 0.45) * mapr4(fbm(p * 0.18, 3, 0.5), 0.35, 0.6, 0.55, 1.0) * (1.0 - rockm), 0.0, 1.0);
	color = mix(color, vec3(0.62, 0.36, 0.22), drift * 0.75);

	// bare rock: darker, greyer basalt where the slopes are steep
	vec3 rcol = mix(vec3(0.085, 0.06, 0.05), vec3(0.16, 0.095, 0.065), mapr(fbm(p * 0.9, 4, 0.5), 0.3, 0.7));
	color = mix(color, rcol, rockm * mapr4(ny, 0.95, 0.6, 0.15, 0.55));

	// fine regolith: pebble specks and grain, only where a pixel resolves them
	float near9 = detail_fade(p, 9.0) * detail_gain;
	float near18 = detail_fade(p, 18.0) * detail_gain;
	float peb = 0.0;
	if (near9 > 0.01) {
		peb = mapr4(voronoi(p * 9.0), 0.0, 0.16, 1.0, 0.0) * pebf * near9;
		vec3 pc = (vnoise(p * 40.0) > 0.82) ? vec3(0.42, 0.3, 0.22) : vec3(0.07, 0.05, 0.045);
		color = mix(color, pc, peb * 0.55);
	}
	color *= mix(1.0, mapr4(fbm(p * 18.0, 3, 0.5), 0.3, 0.7, 0.93, 1.05), near18);

	// rover tracks: twin ruts, tread chevrons, berms of pale dust
	float on = step(off, 50.0);
	float rut = mapr4(off, 0.26, 0.18, 0.0, 1.0) * on;
	float berm = mapr(off, 0.2, 0.3) * mapr4(off, 0.5, 0.36, 0.0, 1.0) * on;
	float tread = mapr(sin(tal * 18.0 + off * 9.0), -0.2, 0.6);
	color = mix(color, color * vec3(0.6, 0.62, 0.66), rut * 0.6);
	color = mix(color, vec3(0.6, 0.36, 0.22), berm * 0.35);

	float rough = mapr4(fbm(p * 3.0, 3, 0.5), 0.3, 0.7, 0.88, 0.95);
	rough = mix(rough, 0.85, rockm);
	rough = mix(rough, 0.82, rut);
	rough = mix(rough, 0.96, drift);

	// micro relief: mid-scale undulation everywhere; pebbles, grain and tread up close
	float h = fbm(p * 1.2, 5, 0.62) * 1.4 + rut * -1.2 + rut * tread * 0.5 + berm * 0.6;
	if (near9 > 0.01) {
		h += mapr4(voronoi(p * 7.0), 0.0, 0.35, 1.0, 0.0) * pebf * near9 + fbm(p * 60.0, 2, 0.5) * 0.25 * detail_fade(p, 60.0);
	}
	NORMAL = bump_normal(NORMAL, VERTEX, h, 0.6 * 0.02 * bump_gain);

	ALBEDO = color + vec3((dust + power) * 0.0);
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = specular;
}
