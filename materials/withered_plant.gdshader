shader_type spatial;
// Withered look for the Garden dome's upgrade-stage plants (owner request 2026-11-15: the plants look a bit dead while
// the dome glass is broken, task T08). scripts/world/dome_plants_presenter.gd puts it on GroundCover, Herbs, Shrubs,
// TreeCrowns, ... (MultiMesh clumps of a unit sphere, coloured per instance; scripts/upgrades/stages/garden_stages.gd)
// as their material_override and eases `amount` from 1 (dead) to 0 (healthy) when the glass is fixed, then gives the
// plants their own StandardMaterial3D back. At amount 0 it draws like that material (base colour x instance colour).
// The dead look: desaturated, browned towards a dry straw/olive, darker and matte; each clump squashed towards its
// base and bent over a little to a side picked per instance (some clumps more dead than others).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// The plant's own material (StandardMaterial3D albedo_color, vertex_color_use_as_albedo, roughness, emission).
uniform vec3 base_color : source_color = vec3(1.0);
uniform bool use_vertex_color = true;
uniform float roughness_healthy : hint_range(0.0, 1.0) = 0.8;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
// 1 = the full dead look, 0 = healthy.
uniform float amount : hint_range(0.0, 1.0) = 1.0;
// How dead on average; each instance varies around it.
uniform float severity : hint_range(0.0, 1.0) = 0.8;
uniform vec3 dry_color : source_color = vec3(0.55, 0.4, 0.18);
// Share of its height a fully dead clump loses, and how far its top bends over (mesh units: the sphere's radius is 1).
uniform float droop : hint_range(0.0, 0.5) = 0.2;
uniform float lean : hint_range(0.0, 1.0) = 0.3;

varying float v_dead;

float hash11(float n) {
	return fract(sin(n * 12.9898 + 78.233) * 43758.5453);
}

void vertex() {
	float id = float(INSTANCE_ID);
	v_dead = clamp(severity * (0.65 + 0.7 * hash11(id + 1.0)), 0.0, 1.0) * amount;
	// Unit-sphere clump: up = 0 at its bottom, 1 at its top. The bottom stays on the soil.
	float up = clamp((VERTEX.y + 1.0) * 0.5, 0.0, 1.0);
	VERTEX.y = -1.0 + (VERTEX.y + 1.0) * (1.0 - droop * v_dead);
	float a = hash11(id + 17.0) * 6.2831853;
	VERTEX.xz += vec2(cos(a), sin(a)) * lean * v_dead * up * up;
}

void fragment() {
	vec3 c = base_color;
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 dry = dry_color * (0.55 + l * 1.6);
	vec3 dead = mix(mix(c, vec3(l), 0.45), dry, 0.6) * 0.8;
	ALBEDO = mix(c, dead, v_dead);
	ROUGHNESS = mix(roughness_healthy, 0.92, v_dead);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	EMISSION = emission_color * emission_energy * (1.0 - v_dead);
}
