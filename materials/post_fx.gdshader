shader_type canvas_item;
// Screen pass that stands in for the Blender compositor of the reference renders (gc_render.setup_post):
// chromatic dispersion 0.006, lift / gamma / gain grade (cool shadows, warm highlights) and a 0.22 vignette.
// Bloom is done by the Environment's glow. It sits on its own CanvasLayer below every UI layer.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float vignette = 0.22;
uniform float dispersion = 0.006;
uniform vec3 lift = vec3(0.985, 1.0, 1.02);
uniform vec3 gamma = vec3(1.0, 1.0, 0.99);
uniform vec3 gain = vec3(1.02, 1.0, 0.975);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	vec2 d = c * dot(c, c) * dispersion * 4.0;      // radial, strongest in the corners
	vec3 col = vec3(texture(screen_tex, uv + d).r, texture(screen_tex, uv).g, texture(screen_tex, uv - d).b);
	col = col + (lift - vec3(1.0)) * (vec3(1.0) - col);
	col = pow(max(col * gain, vec3(0.0)), vec3(1.0) / gamma);
	col *= 1.0 - vignette * smoothstep(0.42, 1.02, length(c) * 1.45);
	COLOR = vec4(col, 1.0);
}
