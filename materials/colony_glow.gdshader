shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Lamp diffuser panel (gc_mat class 'glow'): grey lens, visible glow. The room is lit by the fixture light placed on
// the panel, not by this emission, so light is not counted twice. `power` is per instance: 0 = switched off.

uniform vec3 emission : source_color = vec3(1.0);
uniform float emission_energy = 15.0;
uniform float lens_albedo = 0.8;
uniform float roughness = 0.35;
instance uniform float dust = 0.0;      // unused; present so every colony material accepts the same instance values
instance uniform float power = 1.0;

void fragment() {
	ALBEDO = vec3(lens_albedo) * mix(0.35, 1.0, power);      // an unlit lens reads as dark frosted plastic
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	EMISSION = emission * emission_energy * power + vec3(dust * 0.0);
}
