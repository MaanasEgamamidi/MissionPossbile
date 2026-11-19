shader_type spatial;
// Camera motion blur (Settings > Graphics > Motion blur, scripts/ui/motion_blur.gd). A full-screen quad: each pixel's
// world position is rebuilt from the depth buffer, projected with the camera of the previous frame, and the picture is
// sampled along the line between the two. Only the camera's own motion blurs (walking, turning); moving objects do not.
// It draws first among transparent things (render priority -127), so glass, particles and the HUD stay sharp on top.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
// the previous frame's view matrix (world -> camera); the projection is this frame's
uniform mat4 prev_view;
// 0..1 (the setting / 10); 0 = no blur
uniform float strength = 0.5;
// longest smear as a share of the screen
uniform float max_length = 0.05;

const int SAMPLES = 10;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec4 world = INV_VIEW_MATRIX * vec4(view.xyz, 1.0);
	vec4 prev = PROJECTION_MATRIX * (prev_view * vec4(world.xyz, 1.0));
	vec2 prev_uv = prev.xy / prev.w * 0.5 + 0.5;
	vec2 v = (SCREEN_UV - prev_uv) * strength;
	float len = length(v);
	if (len > max_length) {
		v *= max_length / len;
	}
	vec3 col = vec3(0.0);
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) / float(SAMPLES - 1) - 0.5;
		col += texture(screen_tex, clamp(SCREEN_UV - v * t, vec2(0.0), vec2(1.0))).rgb;
	}
	ALBEDO = col / float(SAMPLES);
}
