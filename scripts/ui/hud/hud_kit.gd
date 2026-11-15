extends RefCounted
## The small parts of the simple HUD (UI overhaul, 2026-11-15): pictograms drawn in code, a chunky level bar, a text
## label and a glass card that follow the player's text size and high contrast setting by themselves, a key cap, and
## the rule that turns a long message into one short line. No class_name: load it with
##   const HudKit := preload("res://scripts/ui/hud/hud_kit.gd")
## Every pictogram stands in for a word, so each one is given that word (say()) as its tooltip and accessible name.
## Colour is never the only cue: a low level also gets a mark with its own shape (triangle = low, octagon = very low).

## Most words a one-line HUD message shows; the full text stays in the Power drawer's message list.
const MAX_WORDS := 9
## Level -> colour (AstraStyle), and the mark drawn beside a low value.
const LEVEL_MARK := {&"warn": &"warn", &"urgent": &"danger", &"danger": &"danger"}


## The player's text size (1.0, 1.25 or 1.5): icons and bars grow with the words.
static func scale() -> float:
	return UiTheme.text_scale()


static func level_color(level: StringName, ok := AstraStyle.GOOD) -> Color:
	match level:
		&"warn":
			return AstraStyle.WARN
		&"urgent", &"danger":
			return AstraStyle.DANGER
	return ok


## Gives a control the word(s) its picture stands for: tooltip and accessible name.
static func say(c: Control, words: String) -> void:
	c.tooltip_text = words
	c.accessibility_name = words


## One short line for the HUD from a longer message: its first sentence, cut at a colon or after MAX_WORDS words when
## that is still too long. "Solar panels are dusty: they make about 45 % less power. Clean them." -> "Solar panels are dusty".
static func short_line(text: String, max_words := MAX_WORDS) -> String:
	var t := text.strip_edges().replace("\n", " ")
	# first sentence: up to a . ! or ? followed by a space (so "4.2 kW" stays whole)
	var end := -1
	for i in t.length() - 1:
		if t[i] in [".", "!", "?"] and t[i + 1] == " ":
			end = i
			break
	if end >= 0:
		t = t.substr(0, end + 1)
	var out := t
	while _word_count(out) > max_words and out.rfind(": ") > 0:
		out = out.substr(0, out.rfind(": "))
	if _word_count(out) > max_words:
		var words := out.split(" ", false)
		words.resize(max_words)
		out = " ".join(words).trim_suffix(",").trim_suffix(":").trim_suffix(".") + "…"
	elif out.ends_with(".") and not out.ends_with("..."):
		out = out.trim_suffix(".")
	return out


static func _word_count(t: String) -> int:
	return t.split(" ", false).size()


# ---------------------------------------------------------------- text

## A label whose size follows the text size setting while it is on screen.
class Txt extends Label:
	var base := 18.0
	var _seen := -1.0

	func _init(p_text := "", p_base := 18.0, color := AstraStyle.TEXT, node_name := "", heavy := false) -> void:
		if node_name != "":
			name = node_name
		text = p_text
		base = p_base
		add_theme_color_override(&"font_color", color)
		if heavy:
			var f := UiTheme.get_theme().get_font(&"font", UiTheme.HEADING)
			if f != null:
				add_theme_font_override(&"font", f)
		vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fit()

	func set_base(p_base: float) -> void:
		base = p_base
		_seen = -1.0
		_fit()

	func tint(color: Color) -> void:
		if get_theme_color(&"font_color") != color:
			add_theme_color_override(&"font_color", color)

	func _fit() -> void:
		var s := UiTheme.text_scale()
		if is_equal_approx(s, _seen):
			return
		_seen = s
		add_theme_font_size_override(&"font_size", roundi(base * s))

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			_fit()


# ---------------------------------------------------------------- glass card

## A HUD box in the mission-control glass look. `tone`: &"" (plain), &"good", &"warn", &"danger", &"accent".
class Card extends PanelContainer:
	var tone: StringName = &"":
		set(v):
			if v != tone:
				tone = v
				_apply()
	var radius := 16
	var pad_h := 14
	var pad_v := 10
	var solid := false
	var _contrast := false

	func _init(node_name := "", p_radius := 16, p_pad_h := 14, p_pad_v := 10, p_solid := false) -> void:
		if node_name != "":
			name = node_name
		radius = p_radius
		pad_h = p_pad_h
		pad_v = p_pad_v
		solid = p_solid
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply()

	func _apply() -> void:
		_contrast = UiTheme.is_high_contrast()
		var s := AstraStyle.glass(radius, pad_h, pad_v, solid)
		s.shadow_size = 6
		s.shadow_offset = Vector2(0, 3)
		if tone != &"":
			var c: Color = AstraStyle.ACCENT if tone == &"accent" else _tone_color(tone)
			s.border_color = Color(c, 0.95 if _contrast else 0.7)
			s.set_border_width_all(2)
			if not _contrast:
				s.bg_color = Color(c.r * 0.2 + 0.04, c.g * 0.16 + 0.05, c.b * 0.14 + 0.1, 0.93)
		elif _contrast:
			s.set_border_width_all(2)
		add_theme_stylebox_override(&"panel", s)

	static func _tone_color(t: StringName) -> Color:
		match t:
			&"warn":
				return AstraStyle.WARN
			&"urgent", &"danger":
				return AstraStyle.DANGER
		return AstraStyle.GOOD

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED and UiTheme.is_high_contrast() != _contrast:
			_apply()


# ---------------------------------------------------------------- key cap

## A key cap ("E") in the theme's key look. `base` is its letter size at text size 1.
static func key_cap(key_text: String, base := 18.0, node_name := "Key") -> PanelContainer:
	var cap := PanelContainer.new()
	cap.name = node_name
	cap.theme_type_variation = UiTheme.KEYCAP
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := Txt.new(key_text, base, UiTheme.palette().text, "KeyText", true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = base * 0.9
	cap.add_child(l)
	return cap


# ---------------------------------------------------------------- level bar

## A chunky rounded level bar: `share` 0..1 in `color` on a dark track with a light edge.
class Bar extends Control:
	var share := 0.0:
		set(v):
			v = clampf(v, 0.0, 1.0)
			if not is_equal_approx(v, share):
				share = v
				queue_redraw()
	var color := Color.WHITE:
		set(v):
			if v != color:
				color = v
				queue_redraw()
	## Base size at text size 1.
	var base := Vector2(120, 14)
	var _seen := -1.0

	func _init(p_color := Color.WHITE, p_base := Vector2(120, 14), node_name := "") -> void:
		if node_name != "":
			name = node_name
		color = p_color
		base = p_base
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_fit()

	func _fit() -> void:
		var s := UiTheme.text_scale()
		if is_equal_approx(s, _seen):
			return
		_seen = s
		custom_minimum_size = Vector2(base.x, roundf(base.y * s))

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			_fit()
			queue_redraw()

	func _draw() -> void:
		var contrast := UiTheme.is_high_contrast()
		var r := Rect2(Vector2.ZERO, size)
		var rad := size.y * 0.5
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0, 0, 0, 0.85 if contrast else 0.5)
		track.border_color = Color(1, 1, 1, 0.9) if contrast else AstraStyle.LINE_STRONG
		track.set_border_width_all(2 if contrast else 1)
		track.set_corner_radius_all(int(rad))
		track.anti_aliasing = true
		draw_style_box(track, r)
		if share <= 0.0:
			return
		var inset := 3.0 if contrast else 2.0
		var inner := r.grow(-inset)
		var w := maxf(inner.size.y, inner.size.x * share)
		var fill := StyleBoxFlat.new()
		fill.bg_color = color
		fill.set_corner_radius_all(int(inner.size.y * 0.5))
		fill.anti_aliasing = true
		draw_style_box(fill, Rect2(inner.position, Vector2(w, inner.size.y)))


# ---------------------------------------------------------------- pictograms

## A pictogram drawn in code. `kind` is one of the names in Draw.icon(); `base` its size at text size 1.
class Icon extends Control:
	var kind: StringName = &"":
		set(v):
			if v != kind:
				kind = v
				queue_redraw()
	var color := Color.WHITE:
		set(v):
			if v != color:
				color = v
				queue_redraw()
	var base := 24.0
	var _seen := -1.0

	func _init(p_kind: StringName = &"", p_color := Color.WHITE, p_base := 24.0, node_name := "") -> void:
		if node_name != "":
			name = node_name
		kind = p_kind
		color = p_color
		base = p_base
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_fit()

	func _fit() -> void:
		var s := UiTheme.text_scale()
		if is_equal_approx(s, _seen):
			return
		_seen = s
		var px := roundf(base * s)
		custom_minimum_size = Vector2(px, px)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			_fit()
			queue_redraw()

	func _draw() -> void:
		Draw.icon(self, kind, Rect2(Vector2.ZERO, size), color)


## Draws pictogram `kind` inside `rect` on `ci` in `col` (see Draw.icon for the kinds).
static func draw_icon(ci: CanvasItem, kind: StringName, rect: Rect2, col: Color) -> void:
	Draw.icon(ci, kind, rect, col)


## The drawing itself (an inner class so the Icon control can reach it).
class Draw:
	## Draws pictogram `kind` inside `rect` on `ci` in `col`. Kinds: power, air, water, food, heart, run, helmet,
	## helmet_off, sun, moon, storm, check, warn, danger, info, close, build, cargo, crew, science, camera, scout, radio,
	## drone, battery, range, height, up, down, dot.
	static func icon(ci: CanvasItem, kind: StringName, rect: Rect2, col: Color) -> void:
		var s := minf(rect.size.x, rect.size.y)
		if s <= 0.0:
			return
		var o := rect.position + (rect.size - Vector2(s, s)) * 0.5
		var w := maxf(2.0, s * 0.1)
		var ink := Color(0.05, 0.06, 0.1, 0.95)
		match kind:
			&"power":
				_poly(ci, o, s, [[0.60, 0.02], [0.16, 0.56], [0.45, 0.56], [0.36, 0.98], [0.84, 0.40], [0.55, 0.40], [0.70, 0.02]], col)
			&"air":
				# two bubbles: air you can breathe
				ci.draw_arc(o + Vector2(0.40, 0.56) * s, 0.30 * s, 0.0, TAU, 32, col, w, true)
				ci.draw_arc(o + Vector2(0.30, 0.46) * s, 0.09 * s, PI, PI * 1.5, 8, col, w * 0.7, true)
				ci.draw_circle(o + Vector2(0.80, 0.24) * s, 0.14 * s, col, true, -1.0, true)
			&"water":
				var pts: Array = [[0.5, 0.03]]
				for i in 17:
					var a := deg_to_rad(-35.0 + 250.0 * i / 16.0)
					pts.append([0.5 + cos(a) * 0.33, 0.63 + sin(a) * 0.33])
				_poly(ci, o, s, pts, col)
			&"food":
				# a sprout: two leaves on a stem
				ci.draw_line(o + Vector2(0.5, 0.97) * s, o + Vector2(0.5, 0.50) * s, col, w, true)
				_leaf(ci, o + Vector2(0.5, 0.60) * s, o + Vector2(0.06, 0.20) * s, 0.20 * s, col)
				_leaf(ci, o + Vector2(0.5, 0.52) * s, o + Vector2(0.96, 0.06) * s, 0.22 * s, col)
			&"heart":
				var pts: Array = []
				for i in 32:
					var t := TAU * i / 32.0
					var x := 16.0 * pow(sin(t), 3.0)
					var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
					pts.append([0.5 + x / 34.0, 0.47 + y / 34.0])
				_poly(ci, o, s, pts, col)
			&"run":
				# a running figure: body energy (sprint), never electricity
				ci.draw_circle(o + Vector2(0.62, 0.14) * s, 0.12 * s, col, true, -1.0, true)
				_line(ci, o, s, [[0.56, 0.32], [0.42, 0.60]], col, w * 1.25)                      # body
				_line(ci, o, s, [[0.42, 0.60], [0.64, 0.72], [0.60, 0.96]], col, w * 1.1)          # front leg
				_line(ci, o, s, [[0.42, 0.60], [0.26, 0.76], [0.06, 0.74]], col, w * 1.1)          # back leg
				_line(ci, o, s, [[0.54, 0.36], [0.76, 0.46], [0.90, 0.36]], col, w)                # front arm
				_line(ci, o, s, [[0.54, 0.36], [0.30, 0.34], [0.20, 0.48]], col, w)                # back arm
			&"helmet", &"helmet_off":
				var c := o + Vector2(0.5, 0.46) * s
				if kind == &"helmet":
					ci.draw_circle(c, 0.40 * s, col, true, -1.0, true)
					_round_rect(ci, Rect2(o + Vector2(0.24, 0.30) * s, Vector2(0.52, 0.30) * s), 0.12 * s, ink)
					ci.draw_line(o + Vector2(0.32, 0.38) * s, o + Vector2(0.44, 0.38) * s, Color(col, 0.9), w * 0.6, true)
					_round_rect(ci, Rect2(o + Vector2(0.26, 0.84) * s, Vector2(0.48, 0.13) * s), 0.05 * s, col)
				else:
					ci.draw_arc(c, 0.36 * s, 0.0, TAU, 32, col, w, true)
					ci.draw_line(o + Vector2(0.30, 0.90) * s, o + Vector2(0.70, 0.90) * s, col, w, true)
					ci.draw_line(o + Vector2(0.12, 0.88) * s, o + Vector2(0.88, 0.06) * s, col, w, true)
			&"sun":
				var c := o + Vector2(0.5, 0.5) * s
				ci.draw_circle(c, 0.24 * s, col, true, -1.0, true)
				for i in 8:
					var d := Vector2.from_angle(TAU * i / 8.0)
					ci.draw_line(c + d * 0.34 * s, c + d * 0.48 * s, col, w, true)
			&"moon":
				var pts: Array = []
				for i in 21:
					var a := deg_to_rad(60.0 + 240.0 * i / 20.0)
					pts.append([0.52 + cos(a) * 0.42, 0.5 + sin(a) * 0.42])
				for i in 21:
					var a := deg_to_rad(245.0 - 130.0 * i / 20.0)
					pts.append([0.90 + cos(a) * 0.402, 0.5 + sin(a) * 0.402])
				_poly(ci, o, s, pts, col)
			&"storm":
				# wind lines with a curl: a dust storm
				_line(ci, o, s, [[0.04, 0.34], [0.62, 0.34]], col, w)
				ci.draw_arc(o + Vector2(0.62, 0.22) * s, 0.12 * s, -PI * 0.9, PI * 0.5, 12, col, w, true)
				_line(ci, o, s, [[0.14, 0.56], [0.80, 0.56]], col, w)
				ci.draw_arc(o + Vector2(0.80, 0.70) * s, 0.14 * s, -PI * 0.5, PI * 0.85, 12, col, w, true)
				_line(ci, o, s, [[0.04, 0.78], [0.44, 0.78]], col, w)
				ci.draw_circle(o + Vector2(0.24, 0.14) * s, w * 0.6, col)
				ci.draw_circle(o + Vector2(0.60, 0.92) * s, w * 0.6, col)
			&"check":
				_line(ci, o, s, [[0.12, 0.54], [0.40, 0.82], [0.90, 0.20]], col, w * 1.5)
			&"warn":
				_poly(ci, o, s, [[0.5, 0.04], [0.98, 0.92], [0.02, 0.92]], col)
				ci.draw_line(o + Vector2(0.5, 0.36) * s, o + Vector2(0.5, 0.64) * s, ink, w * 1.1, true)
				ci.draw_circle(o + Vector2(0.5, 0.79) * s, w * 0.65, ink)
			&"danger":
				var pts: Array = []
				for i in 8:
					var a := TAU * (i + 0.5) / 8.0
					pts.append([0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5])
				_poly(ci, o, s, pts, col)
				ci.draw_line(o + Vector2(0.5, 0.22) * s, o + Vector2(0.5, 0.58) * s, ink, w * 1.2, true)
				ci.draw_circle(o + Vector2(0.5, 0.76) * s, w * 0.7, ink)
			&"info":
				ci.draw_circle(o + Vector2(0.5, 0.5) * s, 0.46 * s, col, true, -1.0, true)
				ci.draw_line(o + Vector2(0.5, 0.44) * s, o + Vector2(0.5, 0.76) * s, ink, w * 1.1, true)
				ci.draw_circle(o + Vector2(0.5, 0.26) * s, w * 0.65, ink)
			&"close":
				_line(ci, o, s, [[0.18, 0.18], [0.82, 0.82]], col, w)
				_line(ci, o, s, [[0.82, 0.18], [0.18, 0.82]], col, w)
			&"build":
				# a spanner
				_line(ci, o, s, [[0.22, 0.90], [0.62, 0.42]], col, w * 1.9)
				ci.draw_arc(o + Vector2(0.72, 0.28) * s, 0.19 * s, deg_to_rad(-10.0), deg_to_rad(250.0), 20, col, w * 1.5, true)
				ci.draw_circle(o + Vector2(0.20, 0.90) * s, w * 0.95, col)
			&"cargo":
				# a crate
				_round_rect(ci, Rect2(o + Vector2(0.08, 0.20) * s, Vector2(0.84, 0.70) * s), 0.08 * s, col)
				ci.draw_line(o + Vector2(0.08, 0.44) * s, o + Vector2(0.92, 0.44) * s, ink, w * 0.8, true)
				ci.draw_rect(Rect2(o + Vector2(0.42, 0.20) * s, Vector2(0.16, 0.38) * s), ink)
			&"crew":
				_person(ci, o + Vector2(0.70, 0.52) * s, s * 0.80, Color(col, 0.6))
				_person(ci, o + Vector2(0.36, 0.56) * s, s * 0.92, col)
			&"science":
				# a flask with something in it
				_poly(ci, o, s, [[0.36, 0.42], [0.10, 0.90], [0.16, 0.98], [0.84, 0.98], [0.90, 0.90], [0.64, 0.42]], col)
				_line(ci, o, s, [[0.40, 0.06], [0.40, 0.46]], col, w)
				_line(ci, o, s, [[0.60, 0.06], [0.60, 0.46]], col, w)
				_line(ci, o, s, [[0.30, 0.06], [0.70, 0.06]], col, w)
				ci.draw_circle(o + Vector2(0.44, 0.78) * s, w * 0.6, ink)
				ci.draw_circle(o + Vector2(0.60, 0.66) * s, w * 0.45, ink)
			&"camera":
				_round_rect(ci, Rect2(o + Vector2(0.04, 0.26) * s, Vector2(0.92, 0.62) * s), 0.10 * s, col)
				ci.draw_rect(Rect2(o + Vector2(0.30, 0.14) * s, Vector2(0.30, 0.14) * s), col)
				ci.draw_circle(o + Vector2(0.5, 0.57) * s, 0.20 * s, ink, true, -1.0, true)
				ci.draw_circle(o + Vector2(0.5, 0.57) * s, 0.09 * s, col, true, -1.0, true)
			&"scout":
				# a little rover with a mast camera
				_round_rect(ci, Rect2(o + Vector2(0.06, 0.46) * s, Vector2(0.80, 0.24) * s), 0.07 * s, col)
				ci.draw_circle(o + Vector2(0.24, 0.80) * s, 0.14 * s, col, true, -1.0, true)
				ci.draw_circle(o + Vector2(0.70, 0.80) * s, 0.14 * s, col, true, -1.0, true)
				_line(ci, o, s, [[0.66, 0.46], [0.66, 0.16]], col, w)
				ci.draw_rect(Rect2(o + Vector2(0.54, 0.06) * s, Vector2(0.34, 0.16) * s), col)
			&"radio":
				# Mission Control: a dish sending waves
				ci.draw_circle(o + Vector2(0.30, 0.70) * s, 0.13 * s, col, true, -1.0, true)
				ci.draw_arc(o + Vector2(0.30, 0.70) * s, 0.36 * s, -PI * 0.5, 0.0, 12, col, w, true)
				ci.draw_arc(o + Vector2(0.30, 0.70) * s, 0.60 * s, -PI * 0.5, 0.0, 16, col, w, true)
			&"drone":
				_line(ci, o, s, [[0.22, 0.26], [0.78, 0.74]], col, w)
				_line(ci, o, s, [[0.78, 0.26], [0.22, 0.74]], col, w)
				for p: Array in [[0.20, 0.24], [0.80, 0.24], [0.20, 0.76], [0.80, 0.76]]:
					ci.draw_arc(o + Vector2(p[0], p[1]) * s, 0.15 * s, 0.0, TAU, 16, col, w * 0.8, true)
				ci.draw_circle(o + Vector2(0.5, 0.5) * s, 0.13 * s, col, true, -1.0, true)
			&"battery":
				_round_rect(ci, Rect2(o + Vector2(0.04, 0.26) * s, Vector2(0.80, 0.48) * s), 0.08 * s, col)
				ci.draw_rect(Rect2(o + Vector2(0.86, 0.40) * s, Vector2(0.10, 0.20) * s), col)
				ci.draw_rect(Rect2(o + Vector2(0.14, 0.36) * s, Vector2(0.26, 0.28) * s), ink)
			&"range":
				ci.draw_circle(o + Vector2(0.5, 0.80) * s, 0.10 * s, col, true, -1.0, true)
				for r: float in [0.30, 0.52, 0.74]:
					ci.draw_arc(o + Vector2(0.5, 0.80) * s, r * s, -PI * 0.78, -PI * 0.22, 12, col, w, true)
			&"height":
				_line(ci, o, s, [[0.10, 0.94], [0.90, 0.94]], col, w)
				_line(ci, o, s, [[0.5, 0.80], [0.5, 0.20]], col, w)
				_poly(ci, o, s, [[0.5, 0.02], [0.78, 0.36], [0.22, 0.36]], col)
			&"up":
				_poly(ci, o, s, [[0.5, 0.12], [0.94, 0.84], [0.06, 0.84]], col)
			&"down":
				_poly(ci, o, s, [[0.5, 0.88], [0.94, 0.16], [0.06, 0.16]], col)
			_:
				ci.draw_circle(o + Vector2(0.5, 0.5) * s, 0.30 * s, col, true, -1.0, true)


	static func _poly(ci: CanvasItem, o: Vector2, s: float, pts: Array, col: Color) -> void:
		var out := PackedVector2Array()
		for p: Array in pts:
			out.append(o + Vector2(float(p[0]), float(p[1])) * s)
		ci.draw_colored_polygon(out, col)
		out.append(out[0])
		ci.draw_polyline(out, col, 1.0, true)


	static func _line(ci: CanvasItem, o: Vector2, s: float, pts: Array, col: Color, width: float) -> void:
		var out := PackedVector2Array()
		for p: Array in pts:
			out.append(o + Vector2(float(p[0]), float(p[1])) * s)
		if out.size() == 2:
			ci.draw_line(out[0], out[1], col, width, true)
		else:
			ci.draw_polyline(out, col, width, true)
		for p in out:
			ci.draw_circle(p, width * 0.5, col)          # round caps and joints


	static func _round_rect(ci: CanvasItem, r: Rect2, radius: float, col: Color) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(maxi(1, int(radius)))
		sb.anti_aliasing = true
		ci.draw_style_box(sb, r)


	## A leaf from `a` (stem end) to `b` (tip), `bulge` wide on each side.
	static func _leaf(ci: CanvasItem, a: Vector2, b: Vector2, bulge: float, col: Color) -> void:
		var mid := (a + b) * 0.5
		var n := (b - a).orthogonal().normalized() * bulge * 1.6
		var pts := PackedVector2Array()
		for i in 9:
			var t := i / 8.0
			pts.append(a.lerp(mid + n, t).lerp((mid + n).lerp(b, t), t))
		for i in range(7, 0, -1):
			var t := i / 8.0
			pts.append(a.lerp(mid - n, t).lerp((mid - n).lerp(b, t), t))
		ci.draw_colored_polygon(pts, col)


	## Head and shoulders, `size` tall, centred on `c`.
	static func _person(ci: CanvasItem, c: Vector2, size: float, col: Color) -> void:
		ci.draw_circle(c + Vector2(0, -0.22) * size, 0.19 * size, col, true, -1.0, true)
		var pts := PackedVector2Array()
		for i in 13:
			var a := PI + PI * i / 12.0
			pts.append(c + Vector2(cos(a) * 0.34, 0.44 + sin(a) * 0.40) * size)
		ci.draw_colored_polygon(pts, col)
