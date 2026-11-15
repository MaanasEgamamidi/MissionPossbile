shader_type spatial;

varying vec2 ground_position;

void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 blend = smoothstep(vec2(0.0), vec2(1.0), fract(p));
	vec4 offset = vec4(0.0, 1.0, 57.0, 58.0);
	vec4 values = fract(sin(dot(cell, vec2(1.0, 57.0)) + offset) * 43758.54);
	return mix(mix(values.x, values.y, blend.x), mix(values.z, values.w, blend.x), blend.y);
}

void fragment() {
	float broad = noise(ground_position * 0.085) * 0.6;
	float fine = noise(ground_position * 0.95) * 0.27;
	float grain = noise(ground_position * 7.0) * 0.13;
	vec3 sand = mix(vec3(0.29, 0.174, 0.101), vec3(0.50, 0.35, 0.21), broad + fine + grain);
	ALBEDO = sand;
	ROUGHNESS = 1.0;
}
