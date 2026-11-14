// Shared procedural noise for the colony shaders. Value noise and a small fBm, in object or world space.
// Every material detail in this project is computed here at run time; no texture is baked.

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x), mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x), mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

// fBm with `oct` octaves; `gain` plays the part of Blender's noise "roughness".
float fbm(vec3 p, int oct, float gain) {
	float a = 1.0;
	float s = 0.0;
	float n = 0.0;
	for (int i = 0; i < oct; i++) {
		s += a * vnoise(p);
		n += a;
		p = p * 2.03 + vec3(17.1, 5.3, 9.7);
		a *= gain;
	}
	return s / n;
}

// Blender Map Range, linear, clamped.
float mapr(float v, float a, float b) {
	return clamp((v - a) / (b - a), 0.0, 1.0);
}

float mapr4(float v, float a, float b, float c, float d) {
	return mix(c, d, clamp((v - a) / (b - a), 0.0, 1.0));
}

// Distance to the nearest feature point of a jittered grid (Voronoi F1), range about 0..1.
float voronoi(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d = 8.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = vec3(hash13(i + g), hash13(i + g + 19.19), hash13(i + g + 47.47));
				vec3 r = g + o - f;
				d = min(d, dot(r, r));
			}
		}
	}
	return sqrt(d);
}

// Fade for detail of spatial frequency `freq` (cycles per metre) at this pixel: 1 when it is resolved, 0 when a pixel
// covers more than half a cycle. Stops fine noise from shimmering in the distance.
float detail_fade(vec3 p, float freq) {
	float px = max(length(dFdx(p)), length(dFdy(p))) * freq;
	return 1.0 - smoothstep(0.25, 0.6, px);
}
