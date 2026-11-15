extends RefCounted
## Mini-game kit (UI overhaul, 2026-11-15, docs/revisions/ui_overhaul/): the shared look of the ten repair mini-games.
## Loaded by path (no class_name): const Kit := preload("res://scripts/tasks/puzzles/kit.gd"). Static helpers only,
## all called from a Control's _draw() (they take the CanvasItem to draw on as their first argument).
##
## The conventions every mini-game repeats, so a child learns them once:
##   - The equipment is the interface: draw the real apparatus (sprites from res://assets/ui/minigames/<set>/) large,
##     in a recessed bay(); no rows of labelled buttons.
##   - focus_ring(): the ONE outline for "this is selected / the keyboard is here" (the theme's focus colour).
##   - target_ring(): the ONE pulsing halo for "this is what to use next / a valid place to put it".
##   - tick(): the ONE mark for "this part is done"; lock() for "locked in / cannot move".
##   - turn_arrows(), arrow(), key_cap(): small pictograms in place of words.
##   - shape(): a shape on every colour, so colour is never the only cue.
## Words live in the shell's cue bar (TaskPanel.set_cue), not on the equipment.
## Animated marks read the wall clock (pulse()); a control that shows one calls queue_redraw() in _process().

const DIR := "res://assets/ui/minigames/"
## Shape kinds for shape().
enum { CIRCLE, TRIANGLE, SQUARE, DIAMOND, STAR, HEX }

## Equipment colours (the sprite pack's muted industrial Mars-colony look).
const BAY := Color(0.105, 0.13, 0.165)
const BAY_EDGE := Color(0.05, 0.065, 0.085)
const BAY_LIP := Color(0.27, 0.32, 0.38)
const HOUSING := Color(0.80, 0.77, 0.70)
const HOUSING_DARK := Color(0.52, 0.50, 0.46)
const HOUSING_LIGHT := Color(0.93, 0.91, 0.86)
const METAL := Color(0.47, 0.50, 0.54)
const METAL_DARK := Color(0.2, 0.22, 0.25)
const HAZARD := Color(0.96, 0.62, 0.16)
const WATER := Color(0.25, 0.82, 0.95)
const DRY := Color(0.56, 0.58, 0.6)
const INK := Color(0.07, 0.09, 0.12)

static var _textures := {}
static var _boxes := {}


# ---------------------------------------------------------------- sprites

## A sprite of the pack by its path under res://assets/ui/minigames/ without ".png" ("irrigation/pipe_elbow").
## Cached; null (with one warning) when the file is missing.
static func tex(rel: String) -> Texture2D:
	if _textures.has(rel):
		return _textures[rel]
	var path := DIR + rel + ".png"
	var t: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	if t == null:
		push_warning("Mini-game kit: missing sprite " + path)
	_textures[rel] = t
	return t


## Sprites are drawn far smaller than their source size: call once on the control that draws them.
static func smooth(control: CanvasItem) -> void:
	control.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## The largest rectangle of `aspect` (width / height) centred inside `rect`.
static func fit(aspect: float, rect: Rect2) -> Rect2:
	var size := rect.size
	if size.x / maxf(size.y, 0.001) > aspect:
		size.x = size.y * aspect
	else:
		size.y = size.x / maxf(aspect, 0.001)
	return Rect2(rect.position + (rect.size - size) * 0.5, size)


## Draws a sprite as large as fits inside `rect`, keeping its shape. Returns the rectangle it covered.
static func draw_fit(c: CanvasItem, t: Texture2D, rect: Rect2, modulate := Color.WHITE) -> Rect2:
	if t == null:
		return rect
	var at := fit(t.get_size().x / t.get_size().y, rect)
	c.draw_texture_rect(t, at, false, modulate)
	return at


## Draws a sprite stretched over `rect` (tiles, plates).
static func draw_fill(c: CanvasItem, t: Texture2D, rect: Rect2, modulate := Color.WHITE) -> void:
	if t != null:
		c.draw_texture_rect(t, rect, false, modulate)


## Draws a sprite `size` large, turned by `angle` (radians, clockwise) about `centre`. `pivot` is the point of the
## sprite that sits on `centre`, as a fraction of its size ((0.5, 0.5) = its middle; (0.5, 0.9) = near its foot, for a
## gauge needle).
static func draw_turned(c: CanvasItem, t: Texture2D, centre: Vector2, size: Vector2, angle: float,
		modulate := Color.WHITE, pivot := Vector2(0.5, 0.5)) -> void:
	if t == null:
		return
	c.draw_set_transform(centre, angle, Vector2.ONE)
	c.draw_texture_rect(t, Rect2(-size * pivot, size), false, modulate)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- plates

## A rounded rectangle (optionally with a border).
static func box(c: CanvasItem, rect: Rect2, fill: Color, radius := 12.0, border := Color(0, 0, 0, 0), border_width := 0.0) -> void:
	var key := [fill, radius, border, border_width]
	var style: StyleBoxFlat = _boxes.get(key)
	if style == null:
		style = StyleBoxFlat.new()
		style.bg_color = fill
		style.draw_center = fill.a > 0.0
		style.set_corner_radius_all(int(radius))
		style.set_border_width_all(int(round(border_width)))
		style.border_color = border
		style.anti_aliasing = true
		if _boxes.size() > 400:
			_boxes.clear()
		_boxes[key] = style
	c.draw_style_box(style, rect)


## The recessed dark bay the equipment sits in (the play surface of every mini-game).
static func bay(c: CanvasItem, rect: Rect2, radius := 18.0) -> void:
	box(c, rect, BAY_LIP, radius)
	box(c, rect.grow(-3.0), BAY_EDGE, radius - 2.0)
	box(c, rect.grow(-6.0), BAY, radius - 4.0)


## A light metal housing plate with a screw in each corner (the body of a machine).
static func housing(c: CanvasItem, rect: Rect2, radius := 20.0, screws := true) -> void:
	box(c, rect, HOUSING_DARK, radius)
	box(c, Rect2(rect.position, rect.size - Vector2(0, 5)), HOUSING, radius)
	box(c, Rect2(rect.position + Vector2(4, 3), Vector2(rect.size.x - 8, 5)), Color(HOUSING_LIGHT, 0.7), 3.0)
	if not screws:
		return
	var inset := minf(22.0, minf(rect.size.x, rect.size.y) * 0.12)
	for corner: Vector2 in [Vector2(inset, inset), Vector2(rect.size.x - inset, inset),
			Vector2(inset, rect.size.y - inset - 4.0), Vector2(rect.size.x - inset, rect.size.y - inset - 4.0)]:
		screw(c, rect.position + corner, clampf(inset * 0.32, 3.0, 7.0))


static func screw(c: CanvasItem, centre: Vector2, r: float) -> void:
	c.draw_circle(centre, r, HOUSING_DARK)
	c.draw_circle(centre, r * 0.72, METAL)
	c.draw_line(centre - Vector2(r * 0.55, r * 0.55), centre + Vector2(r * 0.55, r * 0.55), METAL_DARK, maxf(1.0, r * 0.3), true)


## Diagonal orange hazard stripes inside `rect` (a restrained accent, as on the sprite pack).
static func hazard_stripes(c: CanvasItem, rect: Rect2, count := 4) -> void:
	var w := rect.size.x / float(count * 2)
	for i in count:
		var x := rect.position.x + w * (0.5 + float(i) * 2.0)
		c.draw_colored_polygon(PackedVector2Array([Vector2(x + w * 0.5, rect.position.y), Vector2(x + w * 1.5, rect.position.y),
			Vector2(x + w, rect.end.y), Vector2(x, rect.end.y)]), HAZARD)


# ---------------------------------------------------------------- the shared marks

## 0..1..0, about `speed` times a second, from the wall clock (redraw every frame while it shows).
static func pulse(speed := 1.0) -> float:
	return 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.001 * TAU * speed)


## "This is selected / the keyboard is here": a bold outline in the theme's focus colour around `rect`.
static func focus_ring(c: CanvasItem, rect: Rect2, radius := 14.0, width := 5.0) -> void:
	var focus: Color = UiTheme.palette().focus
	box(c, rect.grow(width + 3.0), Color(0, 0, 0, 0), radius + 6.0, Color(focus, 0.22), width + 2.0)
	box(c, rect.grow(2.0), Color(0, 0, 0, 0), radius, focus, width)


## "Use this next / you can put it here": a soft halo around `rect` that breathes (the theme's focus colour, paler).
static func target_ring(c: CanvasItem, rect: Rect2, radius := 14.0, reduce_motion := false) -> void:
	var focus: Color = UiTheme.palette().focus
	var beat := 0.5 if reduce_motion else pulse(0.9)
	box(c, rect.grow(3.0 + beat * 5.0), Color(0, 0, 0, 0), radius + 6.0, Color(focus, 0.28 + 0.3 * beat), 3.0)
	box(c, rect.grow(1.0), Color(focus, 0.10 + 0.08 * beat), radius, Color(focus, 0.75), 2.0)


## "Done": a green disc with a white tick.
static func tick(c: CanvasItem, centre: Vector2, r: float) -> void:
	var good: Color = UiTheme.palette().good
	c.draw_circle(centre, r, INK)
	c.draw_circle(centre, r * 0.88, good.darkened(0.25))
	var w := maxf(2.0, r * 0.26)
	c.draw_polyline(PackedVector2Array([centre + Vector2(-r * 0.45, r * 0.02), centre + Vector2(-r * 0.12, r * 0.36),
		centre + Vector2(r * 0.48, r * -0.32)]), Color.WHITE, w, true)


## "Not this one": a soft amber disc with a white cross (never red, never scary).
static func cross(c: CanvasItem, centre: Vector2, r: float) -> void:
	var warn: Color = UiTheme.palette().warn
	c.draw_circle(centre, r, INK)
	c.draw_circle(centre, r * 0.88, warn.darkened(0.3))
	var w := maxf(2.0, r * 0.24)
	c.draw_line(centre + Vector2(-r, -r) * 0.36, centre + Vector2(r, r) * 0.36, Color.WHITE, w, true)
	c.draw_line(centre + Vector2(r, -r) * 0.36, centre + Vector2(-r, r) * 0.36, Color.WHITE, w, true)


## A padlock (closed = locked in place). `color` defaults to the theme's "good" green.
static func lock(c: CanvasItem, centre: Vector2, r: float, closed := true, color := Color(0, 0, 0, 0)) -> void:
	var fill: Color = color if color.a > 0.0 else UiTheme.palette().good
	var body := Rect2(centre + Vector2(-r * 0.62, -r * 0.1), Vector2(r * 1.24, r * 0.95))
	var top := centre + Vector2(0.0 if closed else r * 0.5, -r * 0.12)
	c.draw_arc(top, r * 0.36, PI, TAU, 16, fill, maxf(2.0, r * 0.2), true)
	box(c, body, fill, r * 0.2, INK, 1.0)
	c.draw_circle(body.get_center() + Vector2(0, -r * 0.05), r * 0.12, INK)


## "Turn this": two curved arrows chasing each other round `centre`.
static func turn_arrows(c: CanvasItem, centre: Vector2, r: float, color := Color.WHITE) -> void:
	var w := maxf(2.0, r * 0.22)
	for half in 2:
		var from := PI * float(half) + 0.5
		var to := from + PI - 1.0
		c.draw_arc(centre, r, from, to, 14, color, w, true)
		var tip := centre + Vector2.from_angle(to) * r
		var along := Vector2.from_angle(to + PI * 0.5)
		var out := Vector2.from_angle(to)
		c.draw_colored_polygon(PackedVector2Array([tip + along * r * 0.5, tip + out * r * 0.36 - along * r * 0.08,
			tip - out * r * 0.36 - along * r * 0.08]), color)


## A straight arrow from `from` to `to`.
static func arrow(c: CanvasItem, from: Vector2, to: Vector2, color := Color.WHITE, width := 4.0) -> void:
	var dir := (to - from).normalized()
	var side := Vector2(-dir.y, dir.x)
	var head := width * 2.6
	c.draw_line(from, to - dir * head * 0.8, color, width, true)
	c.draw_colored_polygon(PackedVector2Array([to, to - dir * head + side * head * 0.6, to - dir * head - side * head * 0.6]), color)


## A key cap drawn on the equipment ("Enter", "Q"), centred on `centre`. Returns its rectangle.
static func key_cap(c: Control, centre: Vector2, key_text: String, scale := 1.0) -> Rect2:
	var p := UiTheme.palette()
	var font := c.get_theme_font(&"font", &"Label")
	var font_size := int(round(c.get_theme_font_size(&"font_size", &"Label") * scale))
	var w := maxf(font.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + font_size * 0.9, font_size * 1.7)
	var rect := Rect2(centre - Vector2(w, font_size * 1.6) * 0.5, Vector2(w, font_size * 1.6))
	box(c, Rect2(rect.position + Vector2(0, 3), rect.size), INK, 7.0)
	box(c, rect, p.keycap, 7.0, p.border, 2.0)
	text(c, rect, key_text, p.text, scale)
	return rect


## A filled shape with a dark outline, so a colour always has a shape too. kind: CIRCLE, TRIANGLE, SQUARE, DIAMOND,
## STAR or HEX.
static func shape(c: CanvasItem, kind: int, centre: Vector2, r: float, fill: Color, outline := INK) -> void:
	if kind == CIRCLE:
		c.draw_circle(centre, r, outline)
		c.draw_circle(centre, r - maxf(1.5, r * 0.14), fill)
		return
	var pts := shape_points(kind, centre, r)
	var inner := shape_points(kind, centre, r - maxf(1.5, r * 0.16))
	c.draw_colored_polygon(pts, outline)
	c.draw_colored_polygon(inner, fill)


static func shape_points(kind: int, centre: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match kind:
		TRIANGLE:
			for i in 3:
				pts.append(centre + Vector2.from_angle(-PI * 0.5 + TAU * float(i) / 3.0) * r * 1.12 + Vector2(0, r * 0.14))
		SQUARE:
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				pts.append(centre + corner * r * 0.86)
		DIAMOND:
			for i in 4:
				pts.append(centre + Vector2.from_angle(-PI * 0.5 + TAU * float(i) / 4.0) * r * 1.1)
		STAR:
			for i in 10:
				pts.append(centre + Vector2.from_angle(-PI * 0.5 + TAU * float(i) / 10.0) * r * (1.15 if i % 2 == 0 else 0.52))
		HEX:
			for i in 6:
				pts.append(centre + Vector2.from_angle(TAU * float(i) / 6.0) * r * 1.05)
		_:
			for i in 20:
				pts.append(centre + Vector2.from_angle(TAU * float(i) / 20.0) * r)
	return pts


## Centred text inside `rect` with the theme font (for the few labels that sit on equipment: a meter value, a count).
static func text(c: Control, rect: Rect2, value: String, color: Color, scale := 1.0) -> void:
	var font := c.get_theme_font(&"font", &"Label")
	var font_size := int(round(c.get_theme_font_size(&"font_size", &"Label") * scale))
	var height := font.get_height(font_size)
	var baseline := rect.position.y + (rect.size.y - height) * 0.5 + font.get_ascent(font_size)
	c.draw_string(font, Vector2(rect.position.x, baseline), value, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, color)


## A row of `count` progress pips centred on `centre`, the first `filled` of them lit (how many parts are done).
static func pips(c: CanvasItem, centre: Vector2, count: int, filled: int, r := 7.0) -> void:
	var good: Color = UiTheme.palette().good
	var gap := r * 3.0
	var x := centre.x - gap * float(count - 1) * 0.5
	for i in count:
		var at := Vector2(x + gap * float(i), centre.y)
		c.draw_circle(at, r, INK)
		c.draw_circle(at, r - 2.0, good if i < filled else METAL_DARK)
