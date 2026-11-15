extends "res://scripts/tasks/puzzles/electric_ui.gd"
## T03 "Sync the Turbine" (Power Room, any crew; UI overhaul 2026-11-15): ONE turbine face with three concentric timing
## rings on a console plate. Each ring has a green target band and an arrow. Only the active ring's arrow moves and
## only that ring carries the bright cyan edge; rings not reached yet are dim and still; a secured ring shows its
## arrow resting in its band with a padlock. Under the face sits one big amber push button, the single control:
## click it (or Enter / Space) while the arrow is inside the green band. The host checks the stop time against the
## seeded spin (t03_rule.gd) and locks that ring; a miss only restarts the active ring.
## Ring 0 is the outer ring, ring 2 the inner one. Angles are the rule's: degrees, 0 = straight up, clockwise; the
## green band is drawn exactly Rule.window() degrees either side of the ring's mark (wider with the easier setting),
## and the arrow's tip is the angle the host tests.
## The stop time is taken from the input moment (Time.get_ticks_msec), not from a frame, so low frame rates and LAN
## latency do not change the result.

const Rule := preload("res://scripts/tasks/puzzles/t03_rule.gd")
## Kit (the shared mini-game kit, scripts/tasks/puzzles/kit.gd) comes from TaskPanel.
## Each ring's band is this much of the face radius wide; the fan hub fills what is left in the middle.
const BAND := 0.235
## The flat top of timing_track.png: fills each band inward of the sprite's own (thinner) rim.
const TRACK := Color(0.24, 0.235, 0.215)
## The pack's target green (target_arc.png). The sprite is a fixed quarter arc, so the band is drawn to the real
## window instead.
const TARGET := Color(0.59, 0.87, 0.56)
const TARGET_EDGE := Color(0.93, 1.0, 0.9)
const TARGET_MUTED := Color(0.36, 0.47, 0.38)
const CAP_SOCKET := Color(0.09, 0.08, 0.07)
## Layout numbers are for a 470 px tall face and scale with it.
const DESIGN_HEIGHT := 470.0
const DESIGN_WIDTH := 900.0
const MISS_SHOW_MS := 900
const SHAKE_MS := 350
const POP_MS := 320
const PRESS_SHOW_MS := 140

## The turbine face (one custom-drawn control; the two buttons lie over it).
var dials: DrawBox
var stop_button: Button
var assist_toggle: Button

var _layout: Dictionary = {"rings": []}
var _host: Dictionary = {"ring": 0, "assist": false}
var _shown_ring := -1
## When the active ring (re)started spinning, in Time.get_ticks_msec() units. Tests may set it.
var ring_start_ms := 0
var _last_stop_ms := 0
## True from the press until the host answers: the arrow waits where it was stopped.
var _awaiting := false
var _press_ms := -100000
var _miss_ms := -100000
var _miss_deg := 0.0
var _lock_ms := -100000
var _fan_angle := 0.0


func setup(p_services: GameServices) -> void:
	task_title = "Sync the Turbine"
	instructions = "Press the amber button (or Enter) when the moving arrow is inside the green band. That locks the ring. Lock all three rings. The small switch makes the green band wider."
	super.setup(p_services)
	if ui_ready:
		return
	name = "RingsPanel"
	dials = DrawBox.new()
	dials.name = "Dials"
	dials.custom_minimum_size = Vector2(DESIGN_WIDTH, 420)
	dials.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dials.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dials.mouse_filter = Control.MOUSE_FILTER_PASS
	dials.painter = _draw_face
	Kit.smooth(dials)
	play_area.add_child(dials)
	stop_button = _overlay_button("Stop", "Stop the ring (Enter)")
	stop_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	stop_button.pressed.connect(_on_stop)
	assist_toggle = _overlay_button("WideWindow", "Wider green band (easier)")
	assist_toggle.toggle_mode = true
	assist_toggle.toggled.connect(func(on: bool) -> void: send_move("assist", 1 if on else 0))
	dials.resized.connect(_place_controls)
	reset_requested.connect(func() -> void: send_move("reset", 0))
	set_cue("Stop it in the green [Enter]")
	ui_ready = true
	ring_start_ms = Time.get_ticks_msec()
	_place_controls()
	refresh_from_host()


## A see-through button laid over a part of the face (the face draws the part).
func _overlay_button(node_name: String, tip: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = tip
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	dials.add_child(b)
	return b


func first_focus() -> Control:
	return cancel_button if pending or stop_button == null else stop_button


func now_ms() -> int:
	return Time.get_ticks_msec()


## Time since the active ring started, in ms.
func ring_time_ms() -> int:
	return now_ms() - ring_start_ms


func _process(delta: float) -> void:
	super._process(delta)
	if not ui_ready:
		return
	if ring_time_ms() > Rule.MAX_STOP_MS - 5000:
		ring_start_ms = now_ms()
	if not wants_less_motion():
		# The fan in the hub runs faster with every ring that is locked.
		_fan_angle = fposmod(_fan_angle + delta * 1.7 * float(int(_host.ring)), TAU)
	dials.queue_redraw()


func _on_host_state(seed_value: int, _puzzle: Dictionary, record: Dictionary) -> void:
	_layout = Rule.layout(seed_value)
	_host = Rule.state_of(record)
	var ring := int(_host.ring)
	if ring != _shown_ring:
		if _shown_ring >= 0 and ring > _shown_ring:
			_lock_ms = now_ms()
		_shown_ring = ring
		ring_start_ms = now_ms()
	assist_toggle.set_pressed_no_signal(bool(_host.assist))
	stop_button.tooltip_text = "All rings locked" if succeeded or ring >= Rule.RINGS else "Stop ring %d (Enter)" % (ring + 1)
	dials.queue_redraw()


func accept_host_result(result: ActionResult, record := {}) -> void:
	var before := int(_host.ring)
	super.accept_host_result(result, record)
	if result == null or result.pending:
		return
	_awaiting = false
	if result.ok and not succeeded and int(_host.ring) > before:
		_say("Locked! Next ring.", UiTheme.GOOD)


func _on_solved() -> void:
	_say("All three rings locked!", UiTheme.GOOD)


func _on_stop() -> void:
	var ring := int(_host.ring)
	if pending or succeeded or ring >= Rule.RINGS:
		return
	var t := ring_time_ms()
	if t < Rule.MIN_STOP_MS:
		return
	_last_stop_ms = t
	_press_ms = now_ms()
	_awaiting = true
	send_move("stop", ring * Rule.RING_FACTOR + t)


func _explain_rejection(move: Dictionary) -> String:
	if String(move.get("move", "")) != "stop" or (_layout.rings as Array).is_empty():
		return ""
	var ring: Dictionary = _layout.rings[mini(int(_host.ring), Rule.RINGS - 1)]
	_miss_deg = Rule.angle_at(ring, _last_stop_ms)
	_miss_ms = now_ms()
	# How far past the mark the arrow was, along its own direction of travel (negative = not there yet).
	var past := (fposmod(_miss_deg - float(ring.mark) + 180.0, 360.0) - 180.0) * float(ring.dir)
	ring_start_ms = now_ms()
	var text := "Wait for the green. Try again."
	if absf(past) <= 75.0:
		text = "Too early. Try again." if past < 0.0 else "Too late. Try again."
	flash(text, &"warn")
	return text


## A feedback line: kept in status_label (tests, screen readers) and shown in the cue bar even when it repeats.
func _say(text: String, variation: StringName) -> void:
	status_label.text = text
	status_label.theme_type_variation = variation
	flash(text, &"good" if variation == UiTheme.GOOD else &"warn")


# ---------------------------------------------------------------- layout

## Where everything sits, from the face's own size: {u, centre, radius, plate, stop, toggle, lamps, housing}.
func face_geometry() -> Dictionary:
	var s := dials.size
	var u := maxf(0.2, minf(s.y / DESIGN_HEIGHT, s.x / DESIGN_WIDTH))
	var top := (s.y - 458.0 * u) * 0.5
	var mid := s.x * 0.5
	var radius := 172.0 * u
	var plate_side := radius * 2.0 / 0.92
	var plate := Rect2(mid - plate_side * 0.5, top, plate_side, plate_side)
	var centre := Vector2(mid, top + plate_side * 0.47)
	var flank := 156.0 * u
	var housing := Rect2(plate.position.x - flank, top - 3.0 * u, plate_side + flank * 2.0, 464.0 * u)
	var stop := Rect2(mid - 54.0 * u, top + 350.0 * u, 108.0 * u, 108.0 * u)
	var toggle := Rect2(plate.end.x + flank * 0.5 - 46.0 * u, centre.y - 56.0 * u, 92.0 * u, 112.0 * u)
	var lamps: Array = []
	for i in Rule.RINGS:
		lamps.append(Vector2(plate.position.x - flank * 0.5, centre.y + float(i - 1) * 78.0 * u))
	return {"u": u, "centre": centre, "radius": radius, "plate": plate, "stop": stop, "toggle": toggle, "lamps": lamps,
		"housing": housing}


## Outer radius of ring `index` (0 = outer ring); its inner edge is the next ring's outer edge (ring 3 = the hub).
func ring_radius(index: int, radius: float) -> float:
	return radius * (1.0 - BAND * float(index))


## Screen direction of a rule angle (degrees, 0 = up, clockwise).
static func dir_of(degrees: float) -> Vector2:
	return Vector2.from_angle(deg_to_rad(degrees - 90.0))


func _place_controls() -> void:
	if stop_button == null or assist_toggle == null:
		return
	var g := face_geometry()
	var stop: Rect2 = g.stop
	var toggle: Rect2 = g.toggle
	stop_button.position = stop.position
	stop_button.size = stop.size
	assist_toggle.position = toggle.position
	assist_toggle.size = toggle.size


# ---------------------------------------------------------------- drawing

func _draw_face(box: Control) -> void:
	var g := face_geometry()
	var u: float = g.u
	var plate: Rect2 = g.plate
	var housing: Rect2 = g.housing
	var radius: float = g.radius
	var less := wants_less_motion()
	var now := now_ms()
	Kit.bay(box, Rect2(Vector2.ZERO, box.size))
	# Feed pipes from the walls into the machine.
	for side: float in [-1.0, 1.0]:
		var x0 := housing.position.x if side < 0.0 else housing.end.x
		var x1 := 10.0 if side < 0.0 else box.size.x - 10.0
		var pipe := Rect2(minf(x0, x1), housing.position.y + housing.size.y * 0.66, absf(x1 - x0), 30.0 * u)
		if pipe.size.x > 12.0:
			box.draw_rect(pipe, Kit.METAL_DARK)
			box.draw_rect(Rect2(pipe.position + Vector2(0, pipe.size.y * 0.16), Vector2(pipe.size.x, pipe.size.y * 0.2)), Color(Kit.METAL, 0.55))
			var collar_x := x0 + side * 14.0 * u
			box.draw_rect(Rect2(collar_x - 8.0 * u, pipe.position.y - 4.0 * u, 16.0 * u, pipe.size.y + 8.0 * u), Kit.HAZARD)
	Kit.housing(box, housing, 26.0 * u)
	for side: float in [-1.0, 1.0]:
		var flank_mid := (plate.position.x + housing.position.x) * 0.5 if side < 0.0 else (plate.end.x + housing.end.x) * 0.5
		Kit.hazard_stripes(box, Rect2(flank_mid - 34.0 * u, housing.end.y - 52.0 * u, 68.0 * u, 16.0 * u), 3)
	Kit.draw_fill(box, Kit.tex("turbine/console_plate"), plate)

	var rings: Array = _layout.rings
	var active := int(_host.ring)
	var live := not succeeded and active < Rule.RINGS
	var half := Rule.window(bool(_host.assist))
	# A miss gives the face a small shake (never with less motion).
	var centre: Vector2 = g.centre
	var since_miss := now - _miss_ms
	if not less and since_miss < SHAKE_MS:
		centre.x += sin(float(since_miss) * 0.05) * 5.0 * u * (1.0 - float(since_miss) / SHAKE_MS)
	var track := Kit.tex("turbine/timing_track")
	var focus: Color = UiTheme.palette().focus
	for i in Rule.RINGS:
		var outer := ring_radius(i, radius)
		var inner := ring_radius(i + 1, radius)
		var band := outer - inner
		var mid_r := (outer + inner) * 0.5
		var is_active := live and i == active
		var locked := i < active or succeeded
		var shade := 1.35 if is_active else (1.0 if locked else 0.6)
		box.draw_arc(centre, mid_r, 0.0, TAU, 128, Color(TRACK.r * shade, TRACK.g * shade, TRACK.b * shade), band + 1.0, true)
		if track != null:
			# The sprite's ring is centred on (218, 219.5) of 436 x 439 px with an outer radius of 210 px.
			var k := outer / 210.0
			box.draw_texture_rect(track, Rect2(centre - Vector2(218.0, 219.5) * k, Vector2(436.0, 439.0) * k), false, Color(shade, shade, shade))
		box.draw_arc(centre, inner, 0.0, TAU, 128, Kit.INK, 2.0 * u, true)
		if rings.is_empty():
			continue
		var ring: Dictionary = rings[i]
		var mark := float(ring.mark)
		# The green target band: exactly the host's window either side of the mark.
		var from := deg_to_rad(mark - half - 90.0)
		var to := deg_to_rad(mark + half - 90.0)
		var steps := maxi(12, int(half))
		box.draw_arc(centre, mid_r, from, to, steps, TARGET if is_active or locked else TARGET_MUTED, band - 5.0 * u, true)
		if is_active or locked:
			box.draw_arc(centre, outer - 4.5 * u, from, to, steps, Color(TARGET_EDGE, 0.75), 2.0 * u, true)
			for edge: float in [mark - half, mark + half]:
				box.draw_line(centre + dir_of(edge) * (inner + 2.0 * u), centre + dir_of(edge) * (outer - 2.0 * u), TARGET_EDGE, 2.0 * u, true)
		if is_active:
			# The one bright ring: cyan along both edges of the band.
			box.draw_arc(centre, outer - 1.0 * u, 0.0, TAU, 128, Color(focus, 0.25), 8.0 * u, true)
			box.draw_arc(centre, outer - 1.0 * u, 0.0, TAU, 128, focus, 3.5 * u, true)
			box.draw_arc(centre, inner + 1.0 * u, 0.0, TAU, 128, Color(focus, 0.8), 2.0 * u, true)
		# The arrow: a locked ring rests on its mark, the active one spins, later ones wait at their start.
		var degrees := float(ring.start)
		if locked:
			degrees = mark
		elif is_active:
			degrees = Rule.angle_at(ring, _last_stop_ms if _awaiting else ring_time_ms())
		var at := centre + dir_of(degrees) * mid_r
		var length := band * 0.9
		if is_active:
			Kit.draw_turned(box, Kit.tex("turbine/timing_pointer"), at, Vector2(length * 139.0 / 210.0, length), deg_to_rad(degrees))
			if since_miss < MISS_SHOW_MS:
				Kit.cross(box, centre + dir_of(_miss_deg) * mid_r, band * 0.42)
		else:
			_draw_arrow(box, at, length, deg_to_rad(degrees), Color.WHITE if locked else Kit.DRY)
		if locked:
			var pop := 1.0
			if not less and i == active - 1 and now - _lock_ms < POP_MS:
				pop = 1.0 + 0.6 * sin(float(now - _lock_ms) / POP_MS * PI)
			var lock_size := band * 0.92 * pop
			var lock_at := centre + dir_of(mark + half * 0.6) * mid_r
			_draw_lock(box, lock_at, lock_size, true)
	_draw_hub(box, centre, ring_radius(Rule.RINGS, radius), u, active if not succeeded else Rule.RINGS)

	# Three lock lamps on the left flank: outer, middle and inner ring.
	var lamps: Array = g.lamps
	for i in Rule.RINGS:
		_draw_lock(box, lamps[i], 60.0 * u, i < active or succeeded)
		if live and i == active:
			box.draw_arc(lamps[i], 33.0 * u, 0.0, TAU, 48, focus, 3.0 * u, true)
	_draw_toggle(box, g.toggle, u)
	_draw_stop(box, g.stop, u, live, less)


## A plain arrow head with the pack pointer's outline (tip at the top when `angle` is 0), for the rings at rest.
func _draw_arrow(box: Control, at: Vector2, length: float, angle: float, color: Color) -> void:
	var shape := PackedVector2Array([Vector2(0.0, -0.46), Vector2(0.29, 0.44), Vector2(0.0, 0.32), Vector2(-0.29, 0.44)])
	var points := PackedVector2Array()
	for p: Vector2 in shape:
		points.append(at + (p * length).rotated(angle))
	box.draw_colored_polygon(points, color)
	points.append(points[0])
	box.draw_polyline(points, Kit.INK, maxf(1.5, length * 0.07), true)


## The pack's lock badge (dark disc, green padlock) when closed; the same disc with an open grey padlock otherwise.
func _draw_lock(box: Control, at: Vector2, side: float, closed: bool) -> void:
	var sprite := Kit.tex("turbine/lock_indicator")
	if closed and sprite != null:
		box.draw_texture_rect(sprite, Rect2(at - Vector2(side, side) * 0.5, Vector2(side, side)), false)
		return
	box.draw_circle(at, side * 0.47, Kit.METAL_DARK, true, -1.0, true)
	box.draw_circle(at, side * 0.37, Kit.INK, true, -1.0, true)
	Kit.lock(box, at + Vector2(0.0, side * 0.03), side * 0.26, closed, Color(0, 0, 0, 0) if closed else Kit.DRY)


## The turbine fan in the middle: still at first, faster with every locked ring; its lamp turns green when all are.
func _draw_hub(box: Control, centre: Vector2, r: float, u: float, locked: int) -> void:
	box.draw_circle(centre, r, Kit.INK, true, -1.0, true)
	box.draw_circle(centre, r * 0.95, Color(0.14, 0.15, 0.17), true, -1.0, true)
	const BLADES := 9
	var blade := Color(0.4, 0.42, 0.45)
	for b in BLADES:
		var base := _fan_angle + TAU * float(b) / BLADES
		var lead := PackedVector2Array()
		var trail := PackedVector2Array()
		for s in 7:
			var t := float(s) / 6.0
			var rr := lerpf(r * 0.2, r * 0.9, t)
			var a := base + 0.95 * t
			lead.append(centre + Vector2.from_angle(a) * rr)
			trail.append(centre + Vector2.from_angle(a + TAU / BLADES * lerpf(0.55, 0.8, t)) * rr)
		var points := lead.duplicate()
		for s in range(trail.size() - 1, -1, -1):
			points.append(trail[s])
		box.draw_colored_polygon(points, blade)
		box.draw_polyline(lead, Color(0.62, 0.64, 0.67), maxf(1.0, 1.6 * u), true)
	box.draw_arc(centre, r * 0.93, 0.0, TAU, 64, Kit.METAL, 3.0 * u, true)
	box.draw_circle(centre, r * 0.25, Kit.METAL_DARK, true, -1.0, true)
	box.draw_circle(centre, r * 0.19, Kit.METAL, true, -1.0, true)
	draw_lamp(box, centre, r * 0.09, LAMP_GOOD if locked >= Rule.RINGS else (LAMP_WAIT if locked > 0 else LAMP_OFF))


## The small "wider green band" switch on the right flank: a ring with a narrow or a wide green band, and a slide
## switch under it (knob to the right and a tick = on).
func _draw_toggle(box: Control, rect: Rect2, u: float) -> void:
	var on := assist_toggle != null and assist_toggle.button_pressed
	Kit.box(box, rect, Kit.METAL_DARK, 14.0 * u, Kit.INK, 2.0)
	var at := Vector2(rect.get_center().x, rect.position.y + 42.0 * u)
	var r := 24.0 * u
	box.draw_arc(at, r, 0.0, TAU, 48, Color(0.36, 0.38, 0.41), 9.0 * u, true)
	var spread := deg_to_rad(64.0 if on else 26.0)
	box.draw_arc(at, r, -PI * 0.5 - spread, -PI * 0.5 + spread, 24, TARGET, 9.0 * u, true)
	# Two little arrows pushing the band's ends apart.
	for side: float in [-1.0, 1.0]:
		var tip := at + Vector2.from_angle(-PI * 0.5 + side * (spread + 0.5)) * r
		var along := Vector2.from_angle(-PI * 0.5 + side * (spread + 0.5) + side * PI * 0.5)
		var out := Vector2.from_angle(-PI * 0.5 + side * (spread + 0.5))
		box.draw_colored_polygon(PackedVector2Array([tip + along * 6.0 * u, tip - along * 3.0 * u + out * 5.5 * u,
			tip - along * 3.0 * u - out * 5.5 * u]), Color.WHITE if on else Kit.DRY)
	var slot := Rect2(rect.get_center().x - 24.0 * u, rect.end.y - 32.0 * u, 48.0 * u, 20.0 * u)
	var good: Color = UiTheme.palette().good
	Kit.box(box, slot, good.darkened(0.35) if on else Kit.INK, 10.0 * u, Kit.METAL, 1.0)
	var knob := Vector2(slot.end.x - 10.0 * u if on else slot.position.x + 10.0 * u, slot.get_center().y)
	if on:
		Kit.tick(box, knob, 11.0 * u)
	else:
		box.draw_circle(knob, 9.0 * u, Kit.HOUSING, true, -1.0, true)
	if assist_toggle != null and assist_toggle.has_focus():
		Kit.focus_ring(box, rect, 14.0 * u, 4.0)


## The amber push button under the face (the pack sprite; its cap sinks while it is pressed).
func _draw_stop(box: Control, rect: Rect2, u: float, live: bool, less: bool) -> void:
	var sprite := Kit.tex("turbine/stop_button")
	var focused := stop_button != null and stop_button.has_focus()
	if live and not focused:
		Kit.target_ring(box, rect, 16.0 * u, less)
	var tint := Color.WHITE if live else Color(0.7, 0.7, 0.7)
	# The cap is centred on (162, 153) of the 325 x 319 px sprite, 91 px in radius.
	var cap := rect.position + rect.size * Vector2(162.0 / 325.0, 153.0 / 319.0)
	var cap_r := rect.size.x * 91.0 / 325.0
	var down := stop_button != null and (stop_button.button_pressed or now_ms() - _press_ms < PRESS_SHOW_MS)
	if sprite == null:
		Kit.box(box, rect, Kit.METAL_DARK, 12.0 * u)
		box.draw_circle(cap, cap_r * (0.9 if down else 1.0), Kit.HAZARD * tint, true, -1.0, true)
	else:
		box.draw_texture_rect(sprite, rect, false, tint)
		if down:
			box.draw_circle(cap, cap_r * 1.03, CAP_SOCKET, true, -1.0, true)
			var k := rect.size.x / 325.0 * 0.9
			var sunk := Rect2(cap + Vector2(0.0, 2.0 * u) - Vector2(88.0, 88.0) * k, Vector2(176.0, 176.0) * k)
			box.draw_texture_rect_region(sprite, sunk, Rect2(162.0 - 88.0, 153.0 - 88.0, 176.0, 176.0), tint * Color(0.9, 0.9, 0.9))
		elif live and stop_button != null and stop_button.is_hovered():
			box.draw_circle(cap, cap_r * 0.97, Color(1, 1, 1, 0.12), true, -1.0, true)
	if focused:
		Kit.focus_ring(box, rect, 16.0 * u, 4.0)
