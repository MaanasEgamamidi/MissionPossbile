shader_type canvas_item;
// Screen pass that stands in for the Blender compositor of the reference renders (gc_render.setup_post):
// chromatic dispersion 0.006, lift / gamma / gain grade (cool shadows, warm highlights) and a 0.22 vignette.
// Bloom is done by the Environment's glow. It sits on its own CanvasLayer below every UI layer.
// Settings > Graphics (GraphicsQuality._apply_post): Chromatic aberration and Vignette off set dispersion / vignette
// to 0; Sharpness and Film grain (0..1) are added here and are 0 (no change, no extra samples) by default.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float vignette = 0.22;
uniform float dispersion = 0.006;
uniform vec3 lift = vec3(0.985, 1.0, 1.02);
uniform vec3 gamma = vec3(1.0, 1.0, 0.99);
uniform vec3 gain = vec3(1.02, 1.0, 0.975);
uniform float sharpen = 0.0;
uniform float grain = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	vec2 d = c * dot(c, c) * dispersion * 4.0;      // radial, strongest in the corners
	vec3 col = vec3(texture(screen_tex, uv + d).r, texture(screen_tex, uv).g, texture(screen_tex, uv - d).b);
	if (sharpen > 0.0) {
		// unsharp mask on the four neighbours, limited so edges do not ring
		vec2 px = SCREEN_PIXEL_SIZE;
		vec3 n = texture(screen_tex, uv + vec2(px.x, 0.0)).rgb + texture(screen_tex, uv - vec2(px.x, 0.0)).rgb
			+ texture(screen_tex, uv + vec2(0.0, px.y)).rgb + texture(screen_tex, uv - vec2(0.0, px.y)).rgb;
		vec3 detail = col - n * 0.25;
		col = max(col + clamp(detail * sharpen * 1.5, vec3(-0.08), vec3(0.08)), vec3(0.0));
	}
	col = col + (lift - vec3(1.0)) * (vec3(1.0) - col);
	col = pow(max(col * gain, vec3(0.0)), vec3(1.0) / gamma);
	col *= 1.0 - vignette * smoothstep(0.42, 1.02, length(c) * 1.45);
	if (grain > 0.0) {
		// fine moving noise, a little stronger in the mid-tones (like film)
		float t = fract(TIME * 7.13);
		float r = fract(sin(dot(FRAGCOORD.xy + t * 113.0, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		col += r * grain * 0.12 * (1.0 - abs(luma * 2.0 - 1.0) * 0.6);
	}
	COLOR = vec4(col, 1.0);
}
