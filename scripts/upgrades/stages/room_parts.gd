extends AreaStagePresenter
## Shared base of the four room upgrade looks (energy, life_support, health, command; worker 4, 2026-11-14).
## The stage scripts extend this file by path (no class_name): `extends "res://scripts/upgrades/stages/room_parts.gd"`.
##
## What it adds to AreaStagePresenter:
##   * Map data straight from data/colony_manifest.json (room rectangles, object poses), so every stage builds the same
##     with or without a running game (tests build them with no world at all).
##   * Kit: a merged-mesh builder. Parts are authored in "plan" coordinates, the way the map was measured in Blender:
##     x east, y north, z up, metres (Godot x = x, Godot y = z, Godot z = -y). A kit frame puts a piece of equipment on
##     the floor at (x, y) turned to face `yaw` (0 = its front faces north, PI/2 = west, PI = south, -PI/2 = east).
##     Each kit becomes one cluster node with one mesh (one surface per material), plus its labels and lights.
##   * Every primitive records its world box in the cluster's meta "parts" ({tag, aabb}), and the cluster records what
##     holds it up ("support": floor, wall, ceiling, on:<map object>, outdoor), so tests can prove that nothing clips,
##     floats or blocks a door or a station without rendering anything.
##   * The grow-in plays per cluster (each piece grows on its own spot instead of the whole room sliding towards the
##     world origin), and clusters marked outdoor (a dish on a roof) get the outdoor layers instead of the room's.
## Visual only: no colliders, no state.

const MANIFEST_PATH := "res://data/colony_manifest.json"

## Lowest point of each room's ceiling (ceiling tiles and their lamps), measured on the map with
## tools/blender/room_stages/dump_rooms.py. Parts must stay below it.
const CEILING_CLEAR := {"Power Room": 3.05, "Life Support": 3.05, "Med Bay": 2.94, "Command Room": 2.94}
## Underside of the plain ceiling tiles of the two plant rooms (their lamp tiles hang lower, at 3.05). Thin hanger rods
## (parts named "hanger ...") may reach it where they stand under a plain tile.
const HANGER_TOP := {"Power Room": 3.12, "Life Support": 3.12}

## Material table: key -> [albedo, metallic, roughness, emission energy]. Screens use the screen shader instead.
const COLOURS := {
	"panel": [Color(0.80, 0.81, 0.80), 0.0, 0.55, 0.0],
	"panel_warm": [Color(0.86, 0.84, 0.79), 0.0, 0.6, 0.0],
	"panel_dark": [Color(0.30, 0.32, 0.35), 0.1, 0.5, 0.0],
	"frame": [Color(0.15, 0.16, 0.18), 0.3, 0.45, 0.0],
	"steel": [Color(0.62, 0.64, 0.66), 0.7, 0.32, 0.0],
	"chrome": [Color(0.85, 0.86, 0.88), 0.9, 0.15, 0.0],
	"orange": [Color(0.95, 0.47, 0.16), 0.0, 0.5, 0.0],
	"blue": [Color(0.18, 0.42, 0.78), 0.1, 0.45, 0.0],
	"teal": [Color(0.13, 0.58, 0.56), 0.1, 0.45, 0.0],
	"green": [Color(0.20, 0.62, 0.30), 0.0, 0.5, 0.0],
	"yellow": [Color(0.95, 0.78, 0.15), 0.0, 0.5, 0.0],
	"red": [Color(0.80, 0.16, 0.13), 0.0, 0.5, 0.0],
	"copper": [Color(0.75, 0.47, 0.27), 0.85, 0.3, 0.0],
	"rubber": [Color(0.07, 0.07, 0.08), 0.0, 0.85, 0.0],
	"white": [Color(0.93, 0.94, 0.95), 0.0, 0.4, 0.0],
	"vent": [Color(0.10, 0.11, 0.12), 0.2, 0.7, 0.0],
	"glass": [Color(0.55, 0.75, 0.85), 0.2, 0.08, 0.0],
	"solar_cell": [Color(0.06, 0.10, 0.24), 0.4, 0.22, 0.0],
	"fluid": [Color(0.55, 0.80, 0.95), 0.0, 0.15, 0.4],
	"led_green": [Color(0.25, 1.0, 0.35), 0.0, 0.5, 4.0],
	"led_amber": [Color(1.0, 0.65, 0.12), 0.0, 0.5, 4.0],
	"led_red": [Color(1.0, 0.18, 0.12), 0.0, 0.5, 4.0],
	"led_blue": [Color(0.25, 0.55, 1.0), 0.0, 0.5, 4.0],
	"led_cyan": [Color(0.2, 0.95, 1.0), 0.0, 0.5, 3.5],
	"led_white": [Color(0.95, 0.97, 1.0), 0.0, 0.5, 6.0],
	"glow_strip": [Color(0.55, 0.85, 1.0), 0.0, 0.5, 2.5],
}

## Screen modes of the screen shader.
enum Screen { VITALS, COLONY_MAP, DATA, TEXT, RADAR, SCAN, POWER, BEAM }

## Tint of each screen mode (the shader's `tint`).
const SCREEN_TINT := {
	Screen.VITALS: Color(0.3, 1.0, 0.55), Screen.COLONY_MAP: Color(0.35, 0.9, 1.0), Screen.DATA: Color(0.25, 0.85, 1.0),
	Screen.TEXT: Color(0.35, 1.0, 0.6), Screen.RADAR: Color(0.3, 1.0, 0.5), Screen.SCAN: Color(0.35, 0.7, 1.0),
	Screen.POWER: Color(0.35, 1.0, 0.45), Screen.BEAM: Color(0.3, 0.85, 1.0),
}

const _SHADER_OPAQUE := "shader_type spatial;\nrender_mode unshaded, cull_back, shadows_disabled;\n"
const _SHADER_HOLO := "shader_type spatial;\nrender_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;\n"
## Procedural screen pictures (no textures). UV (0,0) is the bottom left of a screen. Vertex colour r = a per-screen seed,
## g = screen width / height / 4.
const _SHADER_BODY := """
uniform int mode = 0;
uniform vec4 tint : source_color = vec4(0.3, 1.0, 0.6, 1.0);
uniform float energy = 1.5;

varying float v_seed;
varying float v_aspect;

void vertex() {
	v_seed = COLOR.r;
	v_aspect = max(COLOR.g * 4.0, 0.2);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float line(float d, float w) {
	return 1.0 - smoothstep(0.0, w, abs(d));
}

float grid_lines(vec2 p, float w) {
	vec2 d = 0.5 - abs(fract(p) - 0.5);
	return 1.0 - smoothstep(0.0, w, min(d.x, d.y));
}

float box2(vec2 p, vec2 lo, vec2 hi) {
	return step(lo.x, p.x) * step(p.x, hi.x) * step(lo.y, p.y) * step(p.y, hi.y);
}

float sq(float x) {
	return x * x;
}

float ecg(float x) {
	float p = fract(x);
	float y = 0.12 * exp(-sq((p - 0.18) / 0.035));
	y -= 0.10 * exp(-sq((p - 0.36) / 0.012));
	y += 0.85 * exp(-sq((p - 0.40) / 0.012));
	y -= 0.22 * exp(-sq((p - 0.44) / 0.014));
	y += 0.22 * exp(-sq((p - 0.65) / 0.05));
	return y;
}

float digits(vec2 uv, vec2 lo, vec2 hi, float seed) {
	vec2 q = (uv - lo) / (hi - lo);
	float inside = box2(uv, lo, hi);
	float cell = floor(q.x * 3.0);
	float fx = fract(q.x * 3.0);
	float on = step(0.25, hash(vec2(cell, seed)));
	float seg = max(step(0.82, q.y) + step(q.y, 0.18) + line(q.y - 0.5, 0.08), line(fx - 0.2, 0.08) + line(fx - 0.75, 0.08));
	return inside * on * clamp(seg, 0.0, 1.0) * step(0.1, fx) * step(fx, 0.85);
}

vec3 vitals(vec2 uv, float t, float seed, float aspect) {
	vec3 c = vec3(0.01, 0.025, 0.03);
	c += vec3(0.0, 0.06, 0.05) * grid_lines(uv * vec2(aspect * 6.0, 6.0), 0.05) * step(uv.x, 0.74);
	float x = uv.x * 1.8 - t * 1.2 + seed * 7.0;
	float left = step(uv.x, 0.73);
	float y1 = 0.70 + 0.2 * ecg(x);
	c += vec3(0.25, 1.0, 0.4) * (line(uv.y - y1, 0.014) + 0.3 * exp(-abs(uv.y - y1) * 45.0)) * left;
	float y2 = 0.40 + 0.07 * sin(6.2832 * x) + 0.03 * sin(12.566 * x + 1.0);
	c += vec3(0.2, 0.85, 1.0) * (line(uv.y - y2, 0.012) + 0.25 * exp(-abs(uv.y - y2) * 45.0)) * left;
	float y3 = 0.14 + 0.06 * sin(x * 1.3);
	c += vec3(1.0, 0.85, 0.25) * line(uv.y - y3, 0.012) * left;
	float beat = exp(-fract(t * 1.2 / 1.8 * 1.8 + seed * 7.0) * 5.0);
	c += vec3(0.25, 1.0, 0.4) * digits(uv, vec2(0.78, 0.62), vec2(0.97, 0.9), seed) * (0.7 + 0.3 * beat);
	c += vec3(0.2, 0.85, 1.0) * digits(uv, vec2(0.78, 0.33), vec2(0.97, 0.56), seed + 3.0);
	c += vec3(1.0, 0.85, 0.25) * digits(uv, vec2(0.78, 0.06), vec2(0.97, 0.27), seed + 6.0);
	c += vec3(1.0, 0.3, 0.3) * box2(uv, vec2(0.76, 0.86), vec2(0.775, 0.9)) * beat;
	return c;
}

vec3 colony_map(vec2 uv, float t, float aspect) {
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	vec2 w = vec2(16.0, -3.0) + p * 54.0;
	vec3 c = vec3(0.015, 0.04, 0.08);
	c += vec3(0.02, 0.09, 0.14) * grid_lines(w / 4.0, 0.05);
	float dd = max(abs(w.x - 15.0) / 27.3, abs(w.y - 4.0) / 16.3);
	c += vec3(0.25, 0.6, 0.9) * line(dd - 1.0, 0.012);
	float gd = length(w - vec2(50.0, -27.0));
	c += vec3(0.3, 0.9, 0.4) * line(gd - 11.0, 0.35) + vec3(0.03, 0.14, 0.05) * step(gd, 11.0);
	float sf = box2(w, vec2(-33.0, -5.0), vec2(-18.0, 19.7)) + box2(w, vec2(47.0, -12.2), vec2(62.0, 12.4));
	c += vec3(0.9, 0.7, 0.2) * sf * step(0.55, fract(w.x / 6.0 + 0.25)) * 0.4;
	vec4 rooms[15] = vec4[15](
		vec4(14.0, -2.0, 30.0, 8.0), vec4(0.0, 0.0, 14.0, 6.0), vec4(0.0, 6.0, 14.0, 18.0), vec4(14.0, 12.0, 24.0, 20.0),
		vec4(-12.0, 8.0, 0.0, 18.0), vec4(24.0, 10.0, 34.0, 18.0), vec4(24.0, 8.0, 28.0, 10.0), vec4(-10.0, 0.0, 0.0, 8.0),
		vec4(34.0, 10.0, 42.0, 20.0), vec4(30.0, -2.0, 34.0, 8.0), vec4(-10.0, -12.0, 14.0, 0.0), vec4(14.0, -10.0, 26.0, -2.0),
		vec4(26.0, -10.0, 42.0, -2.0), vec4(34.0, -2.0, 42.0, 10.0), vec4(14.0, 8.0, 24.0, 12.0));
	for (int i = 0; i < 15; i++) {
		vec4 r = rooms[i];
		vec2 dlo = w - r.xy;
		vec2 dhi = r.zw - w;
		float edge = min(min(dlo.x, dlo.y), min(dhi.x, dhi.y));
		float inside = step(0.0, edge);
		c += vec3(0.04, 0.15, 0.2) * inside;
		c += vec3(0.3, 0.85, 1.0) * inside * (1.0 - smoothstep(0.0, 0.35, edge));
		float blink = 0.5 + 0.5 * sin(t * 2.0 + float(i) * 1.3);
		c += vec3(0.4, 1.0, 0.5) * (1.0 - smoothstep(0.4, 0.6, length(w - (r.xy + r.zw) * 0.5))) * blink;
	}
	float ping = fract(t * 0.5);
	c += vec3(1.0, 0.55, 0.15) * line(length(w - vec2(29.0, 14.0)) - ping * 6.0, 0.4) * (1.0 - ping);
	c += vec3(1.0, 0.55, 0.15) * (1.0 - smoothstep(0.5, 0.8, length(w - vec2(29.0, 14.0))));
	c += vec3(0.1, 0.3, 0.4) * exp(-abs(uv.x - fract(t * 0.08)) * 60.0);
	return c;
}

vec3 data_view(vec2 uv, float t, float seed, float aspect) {
	vec3 c = vec3(0.015, 0.03, 0.05);
	c += vec3(0.0, 0.05, 0.08) * grid_lines(uv * vec2(aspect * 5.0, 5.0), 0.04);
	float n = 10.0;
	float i = floor(uv.x * n);
	float fx = fract(uv.x * n);
	float h = 0.12 + 0.32 * (0.5 + 0.5 * sin(t * (0.5 + hash(vec2(i, seed))) + i * 1.7 + seed * 5.0));
	float bar = step(0.18, fx) * step(fx, 0.82) * step(0.06, uv.y) * step(uv.y, 0.06 + h);
	c = mix(c, tint.rgb * (0.55 + 0.45 * uv.y / 0.5), bar);
	float gy = 0.74 + 0.1 * sin(uv.x * 9.0 + t * 0.8 + seed * 3.0) + 0.04 * sin(uv.x * 23.0 - t * 1.3);
	c += vec3(1.0, 0.72, 0.25) * (line(uv.y - gy, 0.012) + 0.25 * exp(-abs(uv.y - gy) * 40.0));
	return c;
}

vec3 text_view(vec2 uv, float t, float seed, float aspect) {
	vec3 c = vec3(0.01, 0.03, 0.02);
	float rows = 9.0;
	float scroll = floor(t * 0.7);
	float r = floor(uv.y * rows);
	float fy = fract(uv.y * rows);
	float len = 0.25 + 0.65 * hash(vec2(r - scroll, seed));
	float cols = 20.0 * aspect;
	float ci = floor(uv.x * cols);
	float fx = fract(uv.x * cols);
	float ch = step(0.3, hash(vec2(ci, r - scroll + seed * 13.0)));
	float glyph = ch * step(0.15, fx) * step(fx, 0.85) * step(0.25, fy) * step(fy, 0.75) * step(uv.x, len) * step(0.04, uv.x);
	c += tint.rgb * glyph * (0.6 + 0.4 * step(r, 0.5));
	float cursor = step(r, 0.5) * box2(vec2(uv.x, fy), vec2(len + 0.01, 0.2), vec2(len + 0.01 + 1.0 / cols, 0.8));
	c += tint.rgb * cursor * step(0.5, fract(t * 1.5));
	return c;
}

vec3 radar_view(vec2 uv, float t, float seed, float aspect) {
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.1;
	float r = length(p);
	vec3 c = vec3(0.01, 0.04, 0.03);
	float rings = line(fract(r * 3.0 + 0.5) - 0.5, 0.03) * step(r, 1.0);
	c += vec3(0.1, 0.45, 0.25) * rings;
	c += vec3(0.1, 0.45, 0.25) * (line(p.x, 0.008) + line(p.y, 0.008)) * step(r, 1.0);
	float a = atan(p.y, p.x) / 6.2832 + 0.5;
	float s = fract(a - t * 0.25 + seed);
	c += tint.rgb * exp(-s * 9.0) * step(r, 1.0) * 0.7;
	for (int i = 0; i < 5; i++) {
		vec2 b = vec2(hash(vec2(float(i), seed)), hash(vec2(seed, float(i) + 4.0))) * 1.2 - 0.6;
		float ba = fract(atan(b.y, b.x) / 6.2832 + 0.5 - t * 0.25 + seed);
		c += vec3(1.0, 0.8, 0.3) * (1.0 - smoothstep(0.02, 0.04, length(p - b))) * exp(-ba * 4.0);
	}
	return c;
}

vec3 scan_view(vec2 uv, float t, float aspect) {
	vec3 c = vec3(0.01, 0.03, 0.07);
	c += vec3(0.0, 0.05, 0.1) * grid_lines(uv * vec2(aspect * 8.0, 8.0), 0.04);
	vec2 p = (uv - vec2(0.5, 0.52)) * vec2(aspect, 1.0);
	float head = 1.0 - smoothstep(0.07, 0.08, length(p - vec2(0.0, 0.33)));
	float torso = 1.0 - smoothstep(0.9, 1.0, length((p - vec2(0.0, 0.06)) / vec2(0.13, 0.2)));
	float legs = step(abs(abs(p.x) - 0.055), 0.04) * step(-0.44, p.y) * step(p.y, -0.1);
	float arms = step(abs(abs(p.x) - 0.17), 0.03) * step(-0.14, p.y) * step(p.y, 0.2);
	float body = clamp(head + torso + legs + arms, 0.0, 1.0);
	float sl = fract(t * 0.25);
	float done = step(1.0 - uv.y, sl);
	c += vec3(0.1, 0.45, 0.95) * body * (0.35 + 0.45 * done);
	c += vec3(1.0, 0.4, 0.3) * (1.0 - smoothstep(0.02, 0.035, length(p - vec2(-0.03, 0.12)))) * done;
	c += vec3(0.6, 0.9, 1.0) * line(uv.y - (1.0 - sl), 0.006) * 1.5;
	return c;
}

vec3 power_view(vec2 uv, float t, float seed, float aspect) {
	vec3 c = vec3(0.01, 0.03, 0.02);
	float level = 0.55 + 0.35 * (0.5 + 0.5 * sin(t * 0.15 + seed * 4.0));
	vec2 lo = vec2(0.1, 0.12);
	vec2 hi = vec2(0.42, 0.88);
	float frame = box2(uv, lo - 0.02, hi + 0.02) - box2(uv, lo, hi);
	c += vec3(0.6, 0.65, 0.7) * frame;
	float fill = box2(uv, lo, vec2(hi.x, mix(lo.y, hi.y, level)));
	float cells = step(0.12, fract((uv.y - lo.y) / (hi.y - lo.y) * 6.0));
	c += mix(vec3(1.0, 0.6, 0.1), vec3(0.3, 1.0, 0.4), level) * fill * cells;
	c += vec3(0.6, 0.65, 0.7) * box2(uv, vec2(0.21, 0.9), vec2(0.31, 0.95));
	float flow = step(0.5, fract(uv.x * 6.0 - t * 1.5)) * box2(uv, vec2(0.5, 0.47), vec2(0.95, 0.53));
	c += tint.rgb * flow;
	c += vec3(1.0, 0.85, 0.3) * digits(uv, vec2(0.55, 0.65), vec2(0.92, 0.88), seed);
	c += tint.rgb * digits(uv, vec2(0.55, 0.12), vec2(0.92, 0.35), seed + 2.0);
	return c;
}

vec3 beam_view(vec2 uv, float t) {
	float bands = 0.55 + 0.45 * step(0.5, fract(uv.y * 14.0 - t * 1.2));
	return tint.rgb * bands * (1.0 - uv.y) * 0.35;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	vec3 c = vec3(0.0);
	if (mode == 0) {
		c = vitals(uv, t, v_seed, v_aspect);
	} else if (mode == 1) {
		c = colony_map(uv, t, v_aspect);
	} else if (mode == 2) {
		c = data_view(uv, t, v_seed, v_aspect);
	} else if (mode == 3) {
		c = text_view(uv, t, v_seed, v_aspect);
	} else if (mode == 4) {
		c = radar_view(uv, t, v_seed, v_aspect);
	} else if (mode == 5) {
		c = scan_view(uv, t, v_aspect);
	} else if (mode == 6) {
		c = power_view(uv, t, v_seed, v_aspect);
	} else {
		c = beam_view(uv, t);
	}
	ALBEDO = c * energy;
}
"""

static var _shaders: Dictionary = {}
static var _screen_mats: Dictionary = {}
static var _rooms: Dictionary = {}
static var _poses: Dictionary = {}


# ---------------------------------------------------------------- map data

static func _load_map() -> void:
	if not _rooms.is_empty():
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not (data is Dictionary):
		return
	for r: Dictionary in (data as Dictionary).get("rooms", []):
		_rooms[String(r.name)] = r
	for o: Dictionary in (data as Dictionary).get("objects", []):
		_poses[String(o.name)] = WorldCollision.object_transform(o.matrix_world)


## Room rectangle in plan coordinates {name, x0, y0, x1, y1, ceiling}, or {}.
static func room(room_name: String) -> Dictionary:
	_load_map()
	return _rooms.get(room_name, {})


## World pose (Godot) of a map object by its Blender name, or null when it is not on the map.
static func object_pose(object_name: String) -> Variant:
	_load_map()
	return _poses.get(object_name, null)


## Names of every map object that starts with `prefix`, sorted.
static func objects_named(prefix: String) -> PackedStringArray:
	_load_map()
	var out: PackedStringArray = []
	for n: String in _poses:
		if n.begins_with(prefix):
			out.append(n)
	out.sort()
	return out


## Plan point (x east, y north, z up) to Godot world.
static func plan(x: float, y: float, z := 0.0) -> Vector3:
	return Vector3(x, z, -y)


# ---------------------------------------------------------------- presenter behaviour

## Grow-in per cluster: the base scales the stage node; hand that scale to each cluster around its own origin.
func _process(delta: float) -> void:
	super(delta)
	var s := stage_node()
	if s == null or not is_instance_valid(s) or s.get_child_count() == 0:
		return
	var k := s.scale
	var first := s.get_child(0) as Node3D
	if k.is_equal_approx(Vector3.ONE) and (first == null or first.scale.is_equal_approx(Vector3.ONE)):
		return
	s.scale = Vector3.ONE
	for c in s.get_children():
		if c is Node3D:
			(c as Node3D).scale = k


## Room layers from the base, then: outdoor clusters on the outdoor zone and the sun layer, and every light limited to
## the zone it stands in (a light's cull mask is not set by the base).
func put_on_zone_layers(n: Node) -> void:
	super(n)
	if n.get_meta("outdoor", false) and services != null and services.zones != null and n is Node3D and (n as Node3D).is_inside_tree():
		var p := (n as Node3D).global_position
		var mask := services.zones.bit_of(services.zones.outside_zone_at(p.x, -p.z)) | services.zones.sun_bit()
		_set_layers(n, mask)
	if n is Light3D:
		var l := n as Light3D
		l.light_cull_mask = l.layers


func _set_layers(n: Node, mask: int) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = mask
	for c in n.get_children():
		_set_layers(c, mask)


## A new, empty stage node. Clusters are its direct children.
func new_stage() -> Node3D:
	var s := Node3D.new()
	s.set_meta("room_stage", true)
	return s


## Every recorded part of a stage: [{tag, aabb (world), cluster, support, outdoor}].
static func stage_parts(stage: Node3D) -> Array:
	var out: Array = []
	if stage == null:
		return out
	for c in stage.get_children():
		for p: Dictionary in c.get_meta("parts", []):
			var q := p.duplicate()
			q["cluster"] = String(c.name)
			q["support"] = String(c.get_meta("support", "floor"))
			q["outdoor"] = bool(c.get_meta("outdoor", false))
			out.append(q)
	return out


## The material of a colour key (cached).
static func material(key: String) -> Material:
	if key.begins_with("screen:") or key.begins_with("holo:"):
		return screen_material(key)
	var c: Array = COLOURS.get(key, [Color.MAGENTA, 0.0, 0.7, 0.0])
	var m := AreaStagePresenter.mat(c[0], c[1], c[2], c[3])
	if key == "glass" or key == "fluid":
		if m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = 0.35 if key == "glass" else 0.6
	return m


## "screen:<mode>" (opaque picture) or "holo:<mode>" (additive hologram).
static func screen_material(key: String) -> Material:
	if _screen_mats.has(key):
		return _screen_mats[key]
	var holo := key.begins_with("holo:")
	var mode := int(key.get_slice(":", 1))
	var kind := "holo" if holo else "opaque"
	if not _shaders.has(kind):
		var sh := Shader.new()
		sh.code = (_SHADER_HOLO if holo else _SHADER_OPAQUE) + _SHADER_BODY
		_shaders[kind] = sh
	var m := ShaderMaterial.new()
	m.shader = _shaders[kind]
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("tint", SCREEN_TINT.get(mode, Color(0.3, 1.0, 0.6)))
	m.set_shader_parameter("energy", 0.9 if holo else 1.5)
	_screen_mats[key] = m
	return m


## Builds a kit's cluster node under `stage`: one mesh (one surface per material), then its labels and lights.
static func commit(kit: Kit, stage: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = kit.name
	root.position = kit.origin
	root.set_meta("parts", kit.parts)
	root.set_meta("support", kit.support)
	root.set_meta("outdoor", kit.outdoor)
	var mesh := ArrayMesh.new()
	var keys := kit.tools.keys()
	keys.sort()
	for key: String in keys:
		var st: SurfaceTool = kit.tools[key]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material(key))
		mesh.surface_set_name(mesh.get_surface_count() - 1, key)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	root.add_child(mi)
	for e in kit.extras:
		var p: Vector3 = e.get_meta("world_position")
		e.transform.origin = p - kit.origin
		root.add_child(e)
	stage.add_child(root)
	return root


# ---------------------------------------------------------------- merged-mesh builder

## Builds one cluster: triangles per material, wound from their intended outward normal (Godot front faces are
## clockwise), every primitive's world box recorded for the tests. Coordinates are plan coordinates in the current
## frame: x right, y front (out of the wall, into the room), z up.
class Kit:
	var name := "Part"
	var origin := Vector3.ZERO           # Godot world position of the cluster node
	var support := "floor"
	var outdoor := false
	var parts: Array = []
	var tools: Dictionary = {}
	var extras: Array[Node3D] = []
	var frame := Transform3D.IDENTITY    # plan-local -> Godot world
	var tag := ""
	var screens := 0

	func _init(p_name: String, at_x: float, at_y: float, at_z := 0.0, p_support := "floor") -> void:
		name = p_name
		origin = Vector3(at_x, at_z, -at_y)
		support = p_support
		at(at_x, at_y, at_z, 0.0)

	## Moves the frame to plan point (x, y, z), front turned to `yaw` (0 north, PI/2 west, PI south, -PI/2 east).
	func at(x: float, y: float, z := 0.0, yaw := 0.0) -> Kit:
		frame = Transform3D(Basis(Vector3.UP, yaw), Vector3(x, z, -y))
		return self

	## Names the next primitives (for the test report).
	func named(t: String) -> Kit:
		tag = t
		return self

	## Plan-local point -> Godot world.
	func w(p: Vector3) -> Vector3:
		return frame * Vector3(p.x, p.z, -p.y)

	## Plan-local direction -> Godot world.
	func wd(d: Vector3) -> Vector3:
		return frame.basis * Vector3(d.x, d.z, -d.y)

	func _st(key: String) -> SurfaceTool:
		if not tools.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[key] = st
		return tools[key]

	func _record(points: Array) -> void:
		var bb := AABB(points[0], Vector3.ZERO)
		for p: Vector3 in points:
			bb = bb.expand(p)
		parts.append({"tag": tag if tag != "" else name, "aabb": bb})

	## One triangle in world space, wound from the normal; uv and colour feed the screen shader.
	func tri(key: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3, uv := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], col := Color.WHITE, na := Vector3.ZERO, nb := Vector3.ZERO, nc := Vector3.ZERO) -> void:
		var st := _st(key)
		var p := [a, b, c]
		var ns := [na if na != Vector3.ZERO else n, nb if nb != Vector3.ZERO else n, nc if nc != Vector3.ZERO else n]
		var u: Array = uv.duplicate()
		if (b - a).cross(c - a).dot(n) > 0.0:
			p = [a, c, b]
			ns = [ns[0], ns[2], ns[1]]
			u = [u[0], u[2], u[1]]
		for i in 3:
			st.set_color(col)
			st.set_uv(u[i])
			st.set_normal((ns[i] as Vector3).normalized())
			st.add_vertex((p[i] as Vector3) - origin)

	func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col := Color.WHITE) -> void:
		tri(key, a, b, c, n, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)], col)
		tri(key, a, c, d, n, [Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)], col)

	## Box centred on plan-local `c`, size (x, y, z) in plan-local axes; `turn` rotates it in place (Godot-local basis).
	func box(c: Vector3, s: Vector3, key: String, turn := Basis.IDENTITY) -> Kit:
		var h := Vector3(s.x, s.z, s.y) * 0.5          # Godot-local half extents
		var cg := Vector3(c.x, c.z, -c.y)
		var xf := frame * Transform3D(turn, cg)
		var corners: Array = []
		var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
		for i in 3:
			var n: Vector3 = axes[i]
			var uu: Vector3 = axes[(i + 1) % 3]
			var vv: Vector3 = axes[(i + 2) % 3]
			for sgn: float in [-1.0, 1.0]:
				var fc := n * sgn * h[i]
				var hu := uu * h[(i + 1) % 3]
				var hv := vv * h[(i + 2) % 3]
				var nn := (xf.basis * (n * sgn)).normalized()
				var q := [xf * (fc - hu - hv), xf * (fc + hu - hv), xf * (fc + hu + hv), xf * (fc - hu + hv)]
				quad(key, q[0], q[1], q[2], q[3], nn)
				corners.append_array(q)
		_record(corners)
		return self

	## Box from plan-local corner `lo` to `hi`.
	func span(lo: Vector3, hi: Vector3, key: String) -> Kit:
		return box((lo + hi) * 0.5, (hi - lo).abs(), key)

	## Solid of revolution round a plan-local axis ("z" up, "x" or "y"): profile = [Vector2(radius, height)] bottom up,
	## starting at `c`. A first or last point with radius > 0 is closed with a flat cap. `tb` turns it round `c`
	## (a plan-local basis: x right, y front, z up).
	func lathe(c: Vector3, profile: Array, key: String, axis := "z", seg := 18, tb := Basis.IDENTITY) -> Kit:
		var ax := Vector3(0, 0, 1)
		var ux := Vector3(1, 0, 0)
		if axis == "x":
			ax = Vector3(1, 0, 0)
			ux = Vector3(0, 1, 0)
		elif axis == "y":
			ax = Vector3(0, 1, 0)
			ux = Vector3(0, 0, 1)
		ax = tb * ax
		ux = tb * ux
		var vx := ax.cross(ux)
		var pts: Array = []
		for i in profile.size() - 1:
			var p0: Vector2 = profile[i]
			var p1: Vector2 = profile[i + 1]
			var dr := p1.x - p0.x
			var dh := p1.y - p0.y
			for j in seg:
				var a0 := TAU * float(j) / float(seg)
				var a1 := TAU * float(j + 1) / float(seg)
				var r0 := ux * cos(a0) + vx * sin(a0)
				var r1 := ux * cos(a1) + vx * sin(a1)
				var n0 := wd((r0 * dh - ax * dr).normalized())
				var n1 := wd((r1 * dh - ax * dr).normalized())
				var a := w(c + r0 * p0.x + ax * p0.y)
				var b := w(c + r1 * p0.x + ax * p0.y)
				var cc := w(c + r1 * p1.x + ax * p1.y)
				var d := w(c + r0 * p1.x + ax * p1.y)
				var nf := (n0 + n1).normalized()
				if nf == Vector3.ZERO:
					continue
				tri(key, a, b, cc, nf, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Color.WHITE, n0, n1, n1)
				tri(key, a, cc, d, nf, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Color.WHITE, n0, n1, n0)
				pts.append(a)
				pts.append(cc)
		for end in [0, profile.size() - 1]:
			var pe: Vector2 = profile[end]
			if pe.x <= 0.0001:
				continue
			var nrm := wd(-ax if end == 0 else ax)
			var ctr := w(c + ax * pe.y)
			for j in seg:
				var a0 := TAU * float(j) / float(seg)
				var a1 := TAU * float(j + 1) / float(seg)
				tri(key, ctr, w(c + (ux * cos(a0) + vx * sin(a0)) * pe.x + ax * pe.y), w(c + (ux * cos(a1) + vx * sin(a1)) * pe.x + ax * pe.y), nrm)
		if not pts.is_empty():
			_record(pts)
		return self

	## Straight cylinder of radius r and length h, centred on plan-local c, along "z", "x" or "y".
	func cyl(c: Vector3, r: float, h: float, key: String, axis := "z", seg := 16) -> Kit:
		var a := Vector3(0, 0, 1) if axis == "z" else (Vector3(1, 0, 0) if axis == "x" else Vector3(0, 1, 0))
		return lathe(c - a * h * 0.5, [Vector2(r, 0.0), Vector2(r, h)], key, axis, seg)

	## Round tube between two plan-local points.
	func tube(a: Vector3, b: Vector3, r: float, key: String, seg := 10) -> Kit:
		var wa := w(a)
		var wb := w(b)
		var d := wb - wa
		var length := d.length()
		if length < 0.001:
			return self
		var y := d / length
		var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		var pts: Array = []
		for j in seg:
			var a0 := TAU * float(j) / float(seg)
			var a1 := TAU * float(j + 1) / float(seg)
			var r0 := x * cos(a0) + z * sin(a0)
			var r1 := x * cos(a1) + z * sin(a1)
			var p0 := wa + r0 * r
			var p1 := wa + r1 * r
			var p2 := wb + r1 * r
			var p3 := wb + r0 * r
			tri(key, p0, p1, p2, (r0 + r1).normalized(), [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Color.WHITE, r0, r1, r1)
			tri(key, p0, p2, p3, (r0 + r1).normalized(), [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Color.WHITE, r0, r1, r0)
			pts.append(p0)
			pts.append(p2)
		_record(pts)
		return self

	## Pipe through plan-local points with a ball joint at each bend and a flange at both ends.
	func pipe(points: Array, r: float, key: String, flange_key := "steel") -> Kit:
		for i in points.size() - 1:
			tube(points[i], points[i + 1], r, key)
		for i in range(1, points.size() - 1):
			lathe(points[i] - Vector3(0, 0, r * 1.15), [Vector2(0.0, 0.0), Vector2(r * 0.8, r * 0.3), Vector2(r * 1.15, r * 1.15), Vector2(r * 0.8, r * 2.0), Vector2(0.0, r * 2.3)], key, "z", 10)
		for i in [0, points.size() - 1]:
			var nb: Vector3 = points[1] if i == 0 else points[points.size() - 2]
			var d: Vector3 = ((points[i] as Vector3) - nb).normalized()
			var ax := "z" if absf(d.z) > 0.7 else ("x" if absf(d.x) > 0.7 else "y")
			cyl((points[i] as Vector3) - d * 0.03, r * 1.6, 0.03, flange_key, ax, 12)
		return self

	## Coloured band round a straight pipe (pipe colour code), at plan-local c along `axis`.
	func band(c: Vector3, r: float, key: String, axis := "z", width := 0.08) -> Kit:
		return cyl(c, r * 1.12, width, key, axis, 12)

	## A screen facing the frame's front (+y): a dark bezel `depth` deep standing in front of c.y, and the picture.
	## `tilt` leans the top back (radians). Mode is a Screen value; the picture is drawn by the screen shader.
	func screen(c: Vector3, sw: float, sh: float, mode: int, seed := 0.0, depth := 0.05, bezel_key := "frame", tilt := 0.0) -> Kit:
		var turn := Basis(Vector3.RIGHT, tilt)
		var centre := c + Vector3(0, depth * 0.5, 0)
		box(centre, Vector3(sw + 0.05, depth, sh + 0.05), bezel_key, turn)
		var xf := frame * Transform3D(turn, Vector3(centre.x, centre.z, -centre.y))
		var hw := sw * 0.5
		var hh := sh * 0.5
		var f := -(depth * 0.5 + 0.004)
		var a := xf * Vector3(-hw, -hh, f)
		var b := xf * Vector3(hw, -hh, f)
		var cc := xf * Vector3(hw, hh, f)
		var d := xf * Vector3(-hw, hh, f)
		var nrm := (xf.basis * Vector3(0, 0, -1)).normalized()
		var col := Color(fmod(seed + float(screens) * 0.37, 1.0), clampf(sw / sh / 4.0, 0.0, 1.0), 0.0)
		screens += 1
		var key := "screen:%d" % mode
		tri(key, a, b, cc, nrm, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)], col)
		tri(key, a, cc, d, nrm, [Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)], col)
		return self

	## Horizontal picture (hologram layer) at plan-local c, sw by sh, additive.
	func holo_plane(c: Vector3, sw: float, sh: float, mode: int, seed := 0.0) -> Kit:
		var a := w(c + Vector3(-sw * 0.5, -sh * 0.5, 0))
		var b := w(c + Vector3(sw * 0.5, -sh * 0.5, 0))
		var cc := w(c + Vector3(sw * 0.5, sh * 0.5, 0))
		var d := w(c + Vector3(-sw * 0.5, sh * 0.5, 0))
		var col := Color(seed, clampf(sw / sh / 4.0, 0.0, 1.0), 0.0)
		var key := "holo:%d" % mode
		tri(key, a, b, cc, Vector3.UP, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)], col)
		tri(key, a, cc, d, Vector3.UP, [Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)], col)
		_record([a, b, cc, d])
		return self

	## Small glowing light (status LED, lamp lens).
	func led(c: Vector3, s: Vector3, colour_key: String) -> Kit:
		return box(c, s, colour_key)

	## Cabinet with a recessed plinth, a top cap, corner posts and door seams; front faces +y. `c` is the centre of its
	## footprint on the floor (z = base height). Returns self; add faces with face_y = c.y + d / 2.
	func cabinet(c: Vector3, cw: float, cd: float, ch: float, body := "panel", trim := "frame", doors := 2) -> Kit:
		span(c + Vector3(-cw * 0.5 + 0.03, -cd * 0.5 + 0.03, 0.0), c + Vector3(cw * 0.5 - 0.03, cd * 0.5 - 0.03, 0.08), trim)
		span(c + Vector3(-cw * 0.5, -cd * 0.5, 0.08), c + Vector3(cw * 0.5, cd * 0.5, ch - 0.04), body)
		span(c + Vector3(-cw * 0.5 - 0.01, -cd * 0.5 - 0.01, ch - 0.04), c + Vector3(cw * 0.5 + 0.01, cd * 0.5 + 0.01, ch), trim)
		for sx: float in [-1.0, 1.0]:
			span(c + Vector3(sx * cw * 0.5, cd * 0.5 - 0.02, 0.08), c + Vector3(sx * (cw * 0.5 - 0.035), cd * 0.5 + 0.012, ch - 0.04), trim)
		for i in range(1, doors):
			var x := -cw * 0.5 + cw * float(i) / float(doors)
			span(c + Vector3(x - 0.006, cd * 0.5, 0.12), c + Vector3(x + 0.006, cd * 0.5 + 0.008, ch - 0.08), trim)
		return self

	## Text label facing the frame's front at plan-local c (a Label3D; one draw call each, so use few).
	func label(text: String, c: Vector3, px := 0.0035, colour := Color(0.95, 0.96, 0.97)) -> Kit:
		var l := Label3D.new()
		l.text = text
		l.font_size = 48
		l.pixel_size = px
		l.outline_size = 8
		l.modulate = colour
		l.outline_modulate = Color(0.05, 0.06, 0.07)
		l.double_sided = false
		l.shaded = false
		var p := w(c)
		l.transform = Transform3D(frame.basis * Basis(Vector3.UP, PI), p)
		l.set_meta("world_position", p)
		extras.append(l)
		return self

	## A light (spot by default) at plan-local c pointing along plan-local `dir`.
	func light(c: Vector3, dir: Vector3, colour: Color, energy: float, reach: float, spot := true) -> Kit:
		var l: Light3D
		if spot:
			var s := SpotLight3D.new()
			s.spot_range = reach
			s.spot_angle = 38.0
			s.spot_attenuation = 0.8
			l = s
		else:
			var o := OmniLight3D.new()
			o.omni_range = reach
			l = o
		l.light_color = colour
		l.light_energy = energy
		l.shadow_enabled = false
		var p := w(c)
		var fwd := wd(dir).normalized()
		var up := Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.95 else Vector3.BACK
		l.transform = Transform3D(Basis.looking_at(fwd, up), p)
		l.set_meta("world_position", p)
		extras.append(l)
		return self
