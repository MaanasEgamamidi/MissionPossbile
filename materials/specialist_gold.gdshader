shader_type spatial;
// Pulsing rim glow drawn as a material_overlay (owner requests, 2026-11-14). The colour comes from "gold" per material:
// broken parts glow green (this player can do the repair) or red (another specialist's job), see
// broken_part_presenter.gd; cassette tapes glow warm yellow (cassette_presenter.gd). It brightens toward the silhouette
// and pulses slowly, so it reads at a glance from across the room. Soft and steady: no flicker (ages 9-12).
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 gold : source_color = vec4(1.0, 0.76, 0.22, 1.0);
uniform float strength = 1.6;
uniform float rim_power = 2.6;
uniform float pulse_speed = 1.6;
uniform float pulse_depth = 0.35;
uniform float base_glow = 0.08;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	float pulse = 1.0 - pulse_depth + pulse_depth * (0.5 + 0.5 * sin(TIME * pulse_speed));
	float glow = (rim + base_glow) * pulse * strength;
	ALBEDO = gold.rgb * glow;
	ALPHA = clamp(glow, 0.0, 1.0);
}
