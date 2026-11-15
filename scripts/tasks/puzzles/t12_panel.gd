extends "res://scripts/tasks/puzzles/med_ui.gd"
## T12 "Seal the Airlock" mini-game (exit-tunnel inner door, field engineer). UI overhaul 2026-11-15: the airlock is
## the interface, one picture, no words or numbers on it.
##   Left    the closed double hatch on the wall. A pale vapor plume escapes at the seeded leak spot of one of its six
##           seams (top, left, middle upper, middle lower, right, bottom): the plume is the only clue.
##   Middle  the replacement gasket waiting in its holder (its imprint stays in view once it is taken).
##   Right   the pressure gauge: needle low while the door leaks, a green target band to reach.
## Three steps, each with one obvious control:
##   1 Find  click the seam where the vapor comes out (a wrong seam gets an amber cross and "Not here. Follow the vapor.").
##   2 Fit   click the gasket (target ring): it slides onto the damaged seam.
##   3 Press five press tabs appear along the gasket; the one to press next carries the target ring, pressed ones a
##           tick. Each right press is one host move ("press", the rule's numbers 1..5 in their seeded order); the
##           needle climbs, the vapor thins, and after the fifth the needle swings into the green band.
## Steps 1 and 2 are the panel's own (they change nothing in the colony); a half-pressed seal found on opening starts
## at step 3. The owner's time limit (2026-11-14) stays: TIME_LIMIT_S seconds from the first press, drawn as a bar
## draining in the empty gasket holder; when it runs out the gasket springs back to the holder (host move "reset")
## and step 2 starts again. The shell's "start again" button goes back to step 1.
## The host rule (t12_rule.gd) decides every press and the completion, which clears the T12 seal fault S04 reads.
## Keyboard: Tab / arrows move between the seams, the gasket and the tabs; Enter / Space acts; the keyboard follows
## the job (after a step the focus moves to the part to use next).

const Rule := preload("res://scripts/tasks/puzzles/t12_rule.gd")
## Designer balance: seconds to press all five tabs once the first one is down (0 = no time limit).
const TIME_LIMIT_S := 10.0
enum Stage { FIND, FIT, PRESS, DONE }

const HATCH_TEX := Vector2(478, 458)
const GASKET_TEX := Vector2(98, 456)
const GAUGE_TEX := Vector2(440, 444)
const NEEDLE_TEX := Vector2(126, 364)
const VAPOR_TEX := Vector2(389, 245)
## The pin of the gauge face and the hub of the needle sprite (pixels of their textures).
const GAUGE_PIN := Vector2(219.6, 221.9)
const NEEDLE_PIVOT := Vector2(0.497, 0.821)
## The thin tail of the vapor sprite (fraction of the texture): it sits on the leak.
const VAPOR_TAIL := Vector2(0.144, 0.54)
## The six seams of the hatch sprite, by the rule's section (fractions of the sprite): [from, to], from = the top or
## left end. The two middle sections are the upper and lower half of the centre seam.
const SEAMS := [
	[Vector2(0.17, 0.117), Vector2(0.83, 0.117)],
	[Vector2(0.127, 0.15), Vector2(0.127, 0.80)],
	[Vector2(0.504, 0.19), Vector2(0.504, 0.54)],
	[Vector2(0.504, 0.54), Vector2(0.504, 0.955)],
	[Vector2(0.873, 0.15), Vector2(0.873, 0.80)],
	[Vector2(0.20, 0.965), Vector2(0.80, 0.965)],
]
## The stretch one gasket covers, by section: the whole seam (the centre seam takes one full-length gasket whichever
## half leaks).
const RUNS := [
	[Vector2(0.17, 0.117), Vector2(0.83, 0.117)],
	[Vector2(0.127, 0.15), Vector2(0.127, 0.80)],
	[Vector2(0.504, 0.13), Vector2(0.504, 0.955)],
	[Vector2(0.504, 0.13), Vector2(0.504, 0.955)],
	[Vector2(0.873, 0.15), Vector2(0.873, 0.80)],
	[Vector2(0.20, 0.965), Vector2(0.80, 0.965)],
]
## Where on its section the vapor escapes (0..1 along it), and which way the plume drifts.
const LEAK_AT := [0.66, 0.4, 0.4, 0.55, 0.58, 0.32]
const DRIFT := [Vector2(0.86, -0.5), Vector2(-0.8, -0.6), Vector2(0.82, -0.57), Vector2(0.82, -0.57),
	Vector2(0.8, -0.6), Vector2(0.8, -0.6)]
const SEAM_NAMES := ["Top seam", "Left seam", "Middle seam, upper half", "Middle seam, lower half", "Right seam", "Bottom seam"]
## Needle angles in degrees from straight up (the green band of the gauge face spans -57.5 .. 57.5).
const NEEDLE_LOW := -128.0
const NEEDLE_STEP := 14.5
const BAND_DEG := 57.5
const CUE_FIND := "Find the leak [Enter]"
const CUE_FIT := "Fit the new seal [Enter]"
const CUE_PRESS := "Press the glowing spot [Enter]"
const MISS_TEXT := "Not here. Follow the vapor."
const EARLY_TEXT := "Find the leak first."
const WRONG_TEXT := "Not yet. Press the glowing spot."
const DONE_TEXT := "That one is done."
const TIMEOUT_TEXT := "Too slow! Fit the seal again."
const MARK_S := 0.9

## The one piece of equipment: wall, hatch, gasket holder and gauge, drawn by _paint().
var airlock: Control
## One flat button over each seam of the hatch, by the rule's section index (step 1).
var seam_buttons: Array[Button] = []
## The gasket in its holder (step 2).
var gasket_button: Button
## The five press tabs, by spot (0 = top or left end of the gasket) (step 3).
var press_buttons: Array[Button] = []
## Steps 1 and 2 are local: the leak has been pointed at; the gasket lies on the seam.
var leak_found := false
var gasket_fitted := false
## The client-side clock: running from the first right press until the fifth, or until the time is up.
var timer_running := false
var time_left := TIME_LIMIT_S
var timed_out := false
## The seam that got the amber cross after a wrong guess, and the tab after a press out of turn (-1 = none).
var miss_seam := -1
var flash_spot := -1
var _miss_left := 0.0
var _wrong_left := 0.0
var _seat := 0.0
var _needle := NEEDLE_LOW
var _vapor := 1.0
var _clock := 0.0
var _calm := false
var _primed := false
var _was_pressed := 0
var _seed_seen := -1
var _follow_focus := false
var _restart_find := false
var _timed_reset := false
var _retry_left := 0.0


func rule_script() -> Script:
	return Rule


func setup(p_services: GameServices) -> void:
	task_title = "Seal the Airlock"
	instructions = ("Air is leaking out of the airlock door. Follow the vapor to the leak, fit the new seal, then "
		+ "press the glowing spots before the seal lifts off. Stay on the hangar side of the door, or wear a suit.")
	super.setup(p_services)
	name = "T12SealPanel"


func build_game() -> void:
	airlock = make_box("Airlock", Vector2(900, 420), _paint)
	airlock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Kit.smooth(airlock)
	airlock.resized.connect(_layout)
	play_area.add_child(airlock)
	for i in Rule.SECTIONS.size():
		var b := _part("Seam%d" % (i + 1), SEAM_NAMES[i])
		b.pressed.connect(_on_seam.bind(i))
		seam_buttons.append(b)
	gasket_button = _part("Gasket", "New seal")
	gasket_button.pressed.connect(_on_gasket)
	for spot in Rule.POINTS:
		var b := _part("Point%d" % (spot + 1), "Seal point")
		b.pressed.connect(_on_point.bind(spot))
		press_buttons.append(b)
	# Step 1: arrows walk the hatch the way it is drawn (top, left / middle / right, bottom), then on to the gasket.
	var seam_links := [
		{"l": 1, "r": 4, "b": 2}, {"t": 0, "r": 2, "b": 5}, {"t": 0, "l": 1, "r": 4, "b": 3},
		{"t": 2, "l": 1, "r": 4, "b": 5}, {"t": 0, "l": 2, "b": 5}, {"t": 3, "l": 1, "r": 4}]
	for i in seam_buttons.size():
		var b := seam_buttons[i]
		var link: Dictionary = seam_links[i]
		if link.has("l"):
			b.focus_neighbor_left = NodePath("../Seam%d" % (int(link.l) + 1))
		if link.has("r"):
			b.focus_neighbor_right = NodePath("../Seam%d" % (int(link.r) + 1))
		if link.has("t"):
			b.focus_neighbor_top = NodePath("../Seam%d" % (int(link.t) + 1))
		if link.has("b"):
			b.focus_neighbor_bottom = NodePath("../Seam%d" % (int(link.b) + 1))
		b.focus_next = NodePath("../Seam%d" % (i + 2)) if i < seam_buttons.size() - 1 else NodePath("../Gasket")
		if i > 0:
			b.focus_previous = NodePath("../Seam%d" % i)
	seam_buttons[4].focus_neighbor_right = NodePath("../Gasket")
	gasket_button.focus_neighbor_left = NodePath("../Seam5")
	gasket_button.focus_previous = NodePath("../Seam6")
	# Step 3: arrows step along the gasket in spot order (left / up = back, right / down = on).
	for spot in Rule.POINTS:
		var b := press_buttons[spot]
		if spot > 0:
			b.focus_neighbor_left = NodePath("../Point%d" % spot)
			b.focus_neighbor_top = NodePath("../Point%d" % spot)
			b.focus_previous = NodePath("../Point%d" % spot)
		if spot < Rule.POINTS - 1:
			b.focus_neighbor_right = NodePath("../Point%d" % (spot + 2))
			b.focus_neighbor_bottom = NodePath("../Point%d" % (spot + 2))
			b.focus_next = NodePath("../Point%d" % (spot + 2))
	reset_requested.connect(_on_start_again)
	set_cue(CUE_FIND)


## An invisible, focusable hit area over one part of the picture (the picture itself is drawn by _paint()).
func _part(node_name: String, tip: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = tip
	airlock.add_child(b)
	return b


func stage() -> int:
	if puzzle.is_empty():
		return Stage.FIND
	if succeeded or int(puzzle.pressed) >= Rule.POINTS:
		return Stage.DONE
	if not leak_found:
		return Stage.FIND
	if not gasket_fitted:
		return Stage.FIT
	return Stage.PRESS


func _process(delta: float) -> void:
	super._process(delta)
	if airlock == null or puzzle.is_empty():
		return
	_calm = wants_less_motion()
	_clock += delta
	_miss_left = maxf(0.0, _miss_left - delta)
	if _miss_left <= 0.0:
		miss_seam = -1
	_wrong_left = maxf(0.0, _wrong_left - delta)
	if _wrong_left <= 0.0:
		flash_spot = -1
	var seat_to := 1.0 if gasket_fitted else 0.0
	_seat = seat_to if _calm else move_toward(_seat, seat_to, delta / 0.4)
	_needle = _needle_target() if _calm else move_toward(_needle, _needle_target(), delta * 120.0)
	_vapor = _vapor_target() if _calm else move_toward(_vapor, _vapor_target(), delta * 1.3)
	if timer_running and not succeeded and TIME_LIMIT_S > 0.0:
		time_left = maxf(0.0, time_left - delta)
		if time_left <= 0.0 and not pending and int(puzzle.pressed) < Rule.POINTS:
			_time_up()
	elif timed_out and not pending and not succeeded and int(puzzle.pressed) > 0:
		# The host did not take the reset (the lease ran out, the line dropped): ask again.
		_retry_left -= delta
		if _retry_left <= 0.0:
			_retry_left = 1.5
			_timed_reset = true
			send("reset", 0)
	if is_visible_in_tree():
		airlock.queue_redraw()


func _needle_target() -> float:
	if stage() == Stage.DONE:
		return 0.0
	return NEEDLE_LOW + NEEDLE_STEP * float(int(puzzle.pressed))


func _vapor_target() -> float:
	if stage() == Stage.DONE:
		return 0.0
	return 1.0 - float(int(puzzle.pressed)) / float(Rule.POINTS)


# ---------------------------------------------------------------- play

func _say(text: String, kind: StringName) -> void:
	status_label.text = text
	status_label.theme_type_variation = UiTheme.WARN if kind == &"warn" else (UiTheme.GOOD if kind == &"good" else UiTheme.MUTED)
	flash(text, kind)


func _on_seam(section: int) -> void:
	if puzzle.is_empty() or pending or succeeded or stage() != Stage.FIND:
		return
	if section != int(puzzle.leak):
		# Not the leaking seam: an amber cross for a moment, nothing else.
		miss_seam = section
		_miss_left = MARK_S
		_say(MISS_TEXT, &"warn")
		return
	leak_found = true
	miss_seam = -1
	_follow_focus = true
	_sync_view()


func _on_gasket() -> void:
	if puzzle.is_empty() or pending or succeeded:
		return
	match stage():
		Stage.FIND:
			_say(EARLY_TEXT, &"warn")
		Stage.FIT:
			gasket_fitted = true
			_follow_focus = true
			_sync_view()


func _on_point(spot: int) -> void:
	if puzzle.is_empty() or pending or succeeded or timed_out or stage() != Stage.PRESS:
		return
	var pressed := int(puzzle.pressed)
	var n := Rule.order_number(puzzle, spot)
	if n <= pressed:
		_say(DONE_TEXT, &"")
		return
	if n != pressed + 1:
		# Out of turn: a short shake and an amber cross, nothing goes to the host, no penalty.
		flash_spot = spot
		_wrong_left = MARK_S
		_say(WRONG_TEXT, &"warn")
		return
	_follow_focus = true
	send("press", n)


## The shell's "start again" button (the base script has already asked the host for "reset"): back to step 1.
func _on_start_again() -> void:
	if puzzle.is_empty() or succeeded:
		return
	_timed_reset = false
	if int(puzzle.pressed) > 0:
		# The host's answer is still on its way: go back to step 1 when it arrives.
		_restart_find = true
		return
	leak_found = false
	gasket_fitted = false
	_follow_focus = true
	_sync_view()


## Time is up: the gasket springs back to its holder. The host peels the half-pressed seal off ("reset").
func _time_up() -> void:
	timer_running = false
	timed_out = true
	time_left = 0.0
	_timed_reset = true
	_retry_left = 1.5
	_follow_focus = _follow_focus or _game_has_focus()
	_update_enabled()
	send("reset", 0)


func _update_enabled() -> void:
	super._update_enabled()
	for b in press_buttons:
		b.disabled = b.disabled or timed_out


func _game_has_focus() -> bool:
	var vp := get_viewport()
	var at := vp.gui_get_focus_owner() if vp != null else null
	return at != null and airlock != null and airlock.is_ancestor_of(at)


func redraw() -> void:
	if puzzle.is_empty():
		return
	var pressed := int(puzzle.pressed)
	if int(puzzle.seed) != _seed_seen:
		# A new fault (or the first look): start at step 1 unless a half-pressed seal is already on the door.
		_seed_seen = int(puzzle.seed)
		leak_found = false
		gasket_fitted = false
		_was_pressed = 0
	if pressed > 0 or succeeded:
		leak_found = true
		gasket_fitted = true
	elif _was_pressed > 0:
		# The seal was peeled off (too slow, or start again): the gasket is back in its holder.
		gasket_fitted = false
		if _restart_find:
			leak_found = false
	if pressed == 0 or succeeded or not pending:
		_restart_find = false
	_was_pressed = pressed
	if pressed == 0:
		timer_running = false
		timed_out = false
		time_left = TIME_LIMIT_S
	elif pressed >= Rule.POINTS or succeeded:
		timer_running = false
		timed_out = false
	elif not timer_running and not timed_out:
		# The first right press (or a half-done seal picked up again) starts the clock.
		timer_running = true
		time_left = TIME_LIMIT_S
	if not _primed:
		_primed = true
		_seat = 1.0 if gasket_fitted else 0.0
		_needle = _needle_target()
		_vapor = _vapor_target()
	_sync_view()


## Shows the parts of the current step, names them, sets the cue and keeps the keyboard on the part to use next.
func _sync_view() -> void:
	if airlock == null or puzzle.is_empty():
		return
	var had_focus := _game_has_focus()
	var now := stage()
	var pressed := int(puzzle.pressed)
	for b in seam_buttons:
		b.visible = now == Stage.FIND
	gasket_button.visible = now == Stage.FIND or now == Stage.FIT
	gasket_button.tooltip_text = "New seal: use it now" if now == Stage.FIT else "New seal"
	for spot in press_buttons.size():
		var b := press_buttons[spot]
		b.visible = now == Stage.PRESS or now == Stage.DONE
		var n := Rule.order_number(puzzle, spot)
		b.tooltip_text = "Seal point: pressed down" if (n <= pressed or now == Stage.DONE) else ("Seal point: press this next" if n == pressed + 1 else "Seal point: wait for the glow")
	_layout()
	_update_enabled()
	match now:
		Stage.FIND: set_cue(CUE_FIND)
		Stage.FIT: set_cue(CUE_FIT)
		Stage.PRESS: set_cue(CUE_PRESS)
		_: set_cue("")
	airlock.queue_redraw()
	# The keyboard follows the job: when the focused part left the picture or a step was just done, move on.
	if (had_focus or _follow_focus) and not pending and not succeeded and is_inside_tree():
		var at := get_viewport().gui_get_focus_owner()
		var next := first_focus()
		if next != null and next.is_visible_in_tree() and (_follow_focus or at == null or not at.is_visible_in_tree()):
			next.grab_focus()
	if not pending:
		_follow_focus = false


func first_focus() -> Control:
	if pending or puzzle.is_empty() or succeeded or press_buttons.is_empty():
		return super.first_focus()
	match stage():
		Stage.FIND:
			return seam_buttons[0]
		Stage.FIT:
			return gasket_button
		Stage.PRESS:
			var spot := Rule.next_point(puzzle)
			if spot >= 0 and not timed_out:
				return press_buttons[spot]
	return super.first_focus()


func explain(move: Dictionary) -> String:
	match String(move.get("move", "")):
		"press":
			return WRONG_TEXT
		"reset":
			return ""
	return "That doesn't work here. Try something else."


## A move that worked needs no words: the tab ticks, the needle climbs.
func praise(move: Dictionary) -> String:
	if String(move.get("move", "")) == "reset" and _timed_reset:
		_timed_reset = false
		status_label.theme_type_variation = UiTheme.WARN
		return TIMEOUT_TEXT
	return ""


func solved_text() -> String:
	return "The airlock holds its air!"


# ---------------------------------------------------------------- layout (all relative to the picture's size)

func _hatch_rect() -> Rect2:
	var s := airlock.size
	return Kit.fit(HATCH_TEX.x / HATCH_TEX.y, Rect2(s.x * 0.035, s.y * 0.085, s.x * 0.50, s.y * 0.83))


func _holder_rect() -> Rect2:
	var s := airlock.size
	return Kit.fit(GASKET_TEX.x / GASKET_TEX.y, Rect2(s.x * 0.575, s.y * 0.13, s.x * 0.10, s.y * 0.72))


func _gauge_rect() -> Rect2:
	var s := airlock.size
	return Kit.fit(GAUGE_TEX.x / GAUGE_TEX.y, Rect2(s.x * 0.70, s.y * 0.06, s.x * 0.275, s.y * 0.66))


## A [from, to] pair of hatch-sprite fractions as picture coordinates.
func _span(pair: Array) -> Array:
	var hatch := _hatch_rect()
	return [hatch.position + (pair[0] as Vector2) * hatch.size, hatch.position + (pair[1] as Vector2) * hatch.size]


func _upright() -> bool:
	return bool(Rule.VERTICAL[int(puzzle.leak)])


## Width of the clickable strip over a seam.
func _strip() -> float:
	return clampf(_hatch_rect().size.x * 0.125, 44.0, 70.0)


func _seam_rect(section: int) -> Rect2:
	var seg := _span(SEAMS[section])
	var half := _strip() * 0.5
	var rect := Rect2(seg[0], (seg[1] as Vector2) - (seg[0] as Vector2))
	return rect.grow_individual(half, 0.0, half, 0.0) if bool(Rule.VERTICAL[section]) else rect.grow_individual(0.0, half, 0.0, half)


## The point of the seam the vapor comes out of.
func _leak_point() -> Vector2:
	var leak := int(puzzle.leak)
	var seg := _span(SEAMS[leak])
	return (seg[0] as Vector2).lerp(seg[1], float(LEAK_AT[leak]))


## A press tab: (across the seam, along the seam).
func _tab_size() -> Vector2:
	var run := _span(RUNS[int(puzzle.leak)])
	var along := clampf((run[0] as Vector2).distance_to(run[1]) / float(Rule.POINTS) - 4.0, 30.0, 72.0)
	return Vector2(along * 1.43, along)


func _tab_rect(spot: int) -> Rect2:
	var run := _span(RUNS[int(puzzle.leak)])
	var centre := (run[0] as Vector2).lerp(run[1], (float(spot) + 0.5) / float(Rule.POINTS))
	var tab := _tab_size()
	var box := tab if _upright() else Vector2(tab.y, tab.x)
	return Rect2(centre - box * 0.5, box)


## The gasket lying on the seam: [centre, size (thin, long), angle].
func _seated() -> Array:
	var run := _span(RUNS[int(puzzle.leak)])
	var length := (run[0] as Vector2).distance_to(run[1]) * 1.05
	return [((run[0] as Vector2) + (run[1] as Vector2)) * 0.5, Vector2(length * 0.13, length), 0.0 if _upright() else PI * 0.5]


func _layout() -> void:
	if airlock == null or puzzle.is_empty() or airlock.size.x < 8.0:
		return
	for i in seam_buttons.size():
		_place(seam_buttons[i], _seam_rect(i))
	_place(gasket_button, _holder_rect().grow(8.0))
	for spot in press_buttons.size():
		_place(press_buttons[spot], _tab_rect(spot))


func _place(b: Button, rect: Rect2) -> void:
	b.position = rect.position
	b.size = rect.size


# ---------------------------------------------------------------- drawing

func _shake(left: float) -> Vector2:
	return Vector2.ZERO if _calm or left <= 0.0 else Vector2(sin(left * 42.0) * 4.0 * (left / MARK_S), 0.0)


func _paint(c: Control) -> void:
	if puzzle.is_empty():
		return
	var area := Rect2(Vector2.ZERO, c.size)
	Kit.bay(c, area)
	Kit.housing(c, area.grow(-9.0), 14.0)
	var now := stage()
	_paint_pipe(c)
	_paint_hatch(c, now)
	_paint_holder(c, now)
	_paint_seal(c, now)
	_paint_vapor(c)
	_paint_gauge(c, now)


## The pressure line from the gauge down and along the wall to the hatch.
func _paint_pipe(c: Control) -> void:
	var hatch := _hatch_rect()
	var gauge := _gauge_rect()
	var w := maxf(10.0, c.size.y * 0.03)
	var x := gauge.get_center().x
	var y := c.size.y * 0.915
	for pass_i in 2:
		var grow := 2.5 if pass_i == 0 else 0.0
		var col: Color = Kit.METAL_DARK if pass_i == 0 else Kit.METAL
		Kit.box(c, Rect2(x - w * 0.5, gauge.end.y - 6.0, w, y - gauge.end.y + 6.0 + w * 0.5).grow(grow), col, w * 0.5)
		Kit.box(c, Rect2(hatch.end.x + 4.0, y - w * 0.5, x - hatch.end.x - 4.0 + w * 0.5, w).grow(grow), col, w * 0.5)
	c.draw_line(Vector2(hatch.end.x + 12.0, y - w * 0.2), Vector2(x - w * 0.2, y - w * 0.2), Color(1, 1, 1, 0.22), 2.0)
	Kit.box(c, Rect2(hatch.end.x + 2.0, y - w * 0.9, w * 0.9, w * 1.8), Kit.METAL_DARK, 3.0)


func _paint_hatch(c: Control, now: int) -> void:
	var hatch := _hatch_rect()
	# The frame the hatch sits in, with a hazard strip above and below it.
	Kit.box(c, hatch.grow(11.0), Kit.HOUSING_DARK, 18.0)
	Kit.box(c, hatch.grow(6.0), Kit.METAL_DARK, 12.0)
	var strip := Vector2(hatch.size.x * 0.34, maxf(7.0, c.size.y * 0.02))
	for y: float in [hatch.position.y - 15.0 - strip.y, hatch.end.y + 15.0]:
		var at := Rect2(hatch.get_center().x - strip.x * 0.5, y, strip.x, strip.y)
		Kit.box(c, at.grow(2.0), Kit.HOUSING_LIGHT, 3.0)
		Kit.hazard_stripes(c, at, 5)
	Kit.draw_fill(c, Kit.tex("airlock/double_hatch"), hatch)
	if now == Stage.FIND:
		# Six seams to check: a stud on each; the vapor says which one.
		var r := _strip() * 0.2
		for i in seam_buttons.size():
			var b := seam_buttons[i]
			var rect := _seam_rect(i)
			var mid := rect.get_center()
			if b.is_hovered() and not b.disabled:
				Kit.box(c, rect, Color(1, 1, 1, 0.13), _strip() * 0.5)
			c.draw_circle(mid, r + 2.5, Kit.INK)
			c.draw_circle(mid, r, Kit.HOUSING_LIGHT if b.is_hovered() else Kit.HOUSING)
			c.draw_circle(mid, r * 0.42, Kit.METAL_DARK)
			if b.has_focus():
				Kit.focus_ring(c, rect, _strip() * 0.5)
			if i == miss_seam:
				Kit.cross(c, mid + _shake(_miss_left), r * 1.7)
		return
	if now == Stage.DONE:
		return
	# The break in the seam, and (until the gasket lies on it) the place the gasket goes.
	if _seat < 1.0:
		var seated := _seated()
		var thin: Vector2 = seated[1]
		var slot := Rect2((seated[0] as Vector2) - thin * 0.5, thin) if _upright() else Rect2((seated[0] as Vector2) - Vector2(thin.y, thin.x) * 0.5, Vector2(thin.y, thin.x))
		Kit.box(c, slot.grow(3.0), Color(1, 1, 1, 0.1), 8.0, Color(1, 1, 1, 0.6), 2.0)
		Kit.shape(c, Kit.STAR, _leak_point(), _strip() * 0.26, Kit.INK, Kit.HAZARD)


## The gasket holder on the wall: the imprint stays in view when the gasket is on the door, and holds the clock.
func _paint_holder(c: Control, now: int) -> void:
	var holder := _holder_rect()
	var tex := Kit.tex("airlock/replacement_gasket")
	Kit.box(c, holder.grow(10.0), Kit.HOUSING_DARK, 14.0)
	Kit.box(c, holder.grow(7.0), Kit.HOUSING_LIGHT, 12.0)
	Kit.draw_fill(c, tex, holder, Color(0, 0, 0, 0.2))
	if timer_running and TIME_LIMIT_S > 0.0 and now == Stage.PRESS:
		# The clock: a bar draining in the empty holder, with a small hourglass above it.
		var left := clampf(time_left / TIME_LIMIT_S, 0.0, 1.0)
		var tube := Rect2(holder.position.x + holder.size.x * 0.3, holder.position.y + holder.size.y * 0.1, holder.size.x * 0.4, holder.size.y * 0.8)
		Kit.box(c, tube, Color(0, 0, 0, 0.32), 6.0)
		var p := UiTheme.palette()
		var fill: Color = (p.good as Color).darkened(0.15) if left > 0.4 else (p.warn as Color).darkened(0.1)
		var level := tube.size.y * left
		if level > 3.0:
			Kit.box(c, Rect2(tube.position.x + 3.0, tube.end.y - level + 2.0, tube.size.x - 6.0, level - 4.0), fill, 4.0)
		_hourglass(c, Vector2(holder.get_center().x, holder.position.y - 8.0 - c.size.y * 0.035), c.size.y * 0.03)
	if gasket_button != null and gasket_button.visible:
		var rect := holder.grow(8.0)
		if now == Stage.FIT:
			Kit.target_ring(c, rect, 14.0, _calm)
		if gasket_button.is_hovered() and not gasket_button.disabled:
			Kit.box(c, rect, Color(1, 1, 1, 0.16), 14.0)
		if gasket_button.has_focus():
			Kit.focus_ring(c, rect, 14.0)


func _hourglass(c: Control, at: Vector2, r: float) -> void:
	var ink: Color = Kit.METAL_DARK
	c.draw_colored_polygon(PackedVector2Array([at + Vector2(-r, -r), at + Vector2(r, -r), at]), ink)
	c.draw_colored_polygon(PackedVector2Array([at + Vector2(-r, r), at + Vector2(r, r), at]), ink)
	c.draw_line(at + Vector2(-r * 1.2, -r), at + Vector2(r * 1.2, -r), ink, 3.0)
	c.draw_line(at + Vector2(-r * 1.2, r), at + Vector2(r * 1.2, r), ink, 3.0)


## The gasket (in its holder, sliding, or on the seam) and the five press tabs along it.
func _paint_seal(c: Control, now: int) -> void:
	var holder := _holder_rect()
	var seated := _seated()
	var t := smoothstep(0.0, 1.0, _seat)
	var centre := holder.get_center().lerp(seated[0], t)
	var size := holder.size.lerp(seated[1], t)
	if t >= 1.0:
		# A pale rim so the dark gasket reads on the dark door.
		var lying := Rect2(centre - size * 0.5, size) if _upright() else Rect2(centre - Vector2(size.y, size.x) * 0.5, Vector2(size.y, size.x))
		Kit.box(c, lying.grow(2.0), Color(0, 0, 0, 0), 9.0, Color(Kit.HOUSING_LIGHT, 0.75), 2.0)
	Kit.draw_turned(c, Kit.tex("airlock/replacement_gasket"), centre, size, float(seated[2]) * t)
	if t < 1.0 or (now != Stage.PRESS and now != Stage.DONE):
		return
	var tab_tex := Kit.tex("airlock/seam_press_tab")
	var tab := _tab_size()
	var turn := 0.0 if _upright() else PI * 0.5
	var pressed := int(puzzle.pressed)
	var next := Rule.next_point(puzzle) if now == Stage.PRESS and not timed_out else -1
	for spot in press_buttons.size():
		var b := press_buttons[spot]
		var rect := _tab_rect(spot)
		var mid := rect.get_center()
		var down := now == Stage.DONE or Rule.order_number(puzzle, spot) <= pressed
		var radius := tab.y * 0.5
		if spot == next:
			Kit.target_ring(c, rect, radius, _calm)
		var tint := Color(0.72, 0.72, 0.72) if down else (Color(0.6, 0.6, 0.6) if timed_out else Color.WHITE)
		Kit.draw_turned(c, tab_tex, mid + (_shake(_wrong_left) if spot == flash_spot else Vector2.ZERO), tab, turn, tint)
		if down:
			Kit.tick(c, mid, tab.y * 0.3)
		elif spot == flash_spot:
			Kit.cross(c, mid + _shake(_wrong_left), tab.y * 0.27)
		elif b.is_hovered() and not b.disabled:
			c.draw_circle(mid, tab.y * 0.2, Color(1, 1, 1, 0.35))
		if b.has_focus():
			Kit.focus_ring(c, rect, radius)


## The pale plume at the leak: a soft dark copy under it (so it reads on the light wall too), a gentle sway, and
## small puffs drifting off. It thins with every pressed tab and stops when the seal holds.
func _paint_vapor(c: Control) -> void:
	if _vapor <= 0.02:
		return
	var tex := Kit.tex("airlock/vapor_puff")
	if tex == null:
		return
	var leak := int(puzzle.leak)
	var origin := _leak_point()
	var dir: Vector2 = (DRIFT[leak] as Vector2).normalized()
	var width := _hatch_rect().size.x * 0.36 * (0.55 + 0.45 * _vapor)
	var size := Vector2(width, width * VAPOR_TEX.y / VAPOR_TEX.x)
	var sway := 0.0 if _calm else sin(_clock * 1.7) * 0.07
	var breathe := 1.0 if _calm else 1.0 + 0.05 * sin(_clock * 2.3)
	var flip := Vector2(breathe, -breathe if dir.x < 0.0 else breathe)
	var dest := Rect2(-VAPOR_TAIL * size, size)
	c.draw_set_transform(origin + Vector2(3, 5), dir.angle() + sway, flip)
	c.draw_texture_rect(tex, dest, false, Color(0.04, 0.08, 0.12, 0.3 * _vapor))
	c.draw_set_transform(origin, dir.angle() + sway, flip)
	c.draw_texture_rect(tex, dest, false, Color(1, 1, 1, minf(1.0, 0.45 + 0.6 * _vapor)))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _calm:
		return
	# The cloud end of the sprite, drifting on and fading.
	var cloud := Rect2(VAPOR_TEX.x * 0.5, 0.0, VAPOR_TEX.x * 0.5, VAPOR_TEX.y)
	for k in 2:
		var t := fmod(_clock * 0.42 + float(k) * 0.5, 1.0)
		var at := origin + dir * width * (0.55 + 0.6 * t) + Vector2(0.0, -10.0 * t)
		var puff := Vector2(width, width * 1.1) * (0.28 + 0.22 * t)
		c.draw_texture_rect_region(tex, Rect2(at - puff * 0.5, puff), cloud, Color(1, 1, 1, 0.55 * sin(PI * t) * _vapor))


## The gauge: the sprite face, a clear green target band over its own, a dashed amber low range, the needle turning
## about the gauge pin, and a lamp under it (amber triangle = low, green tick = in range).
func _paint_gauge(c: Control, _now: int) -> void:
	var gauge := _gauge_rect()
	var k := gauge.size.x / GAUGE_TEX.x
	var pin := gauge.position + GAUGE_PIN * k
	var p := UiTheme.palette()
	var in_range := absf(_needle) < BAND_DEG - 4.0
	# The lamp plate under the gauge (the pipe runs behind it).
	var plate := Rect2(pin.x - 30.0 * k * 1.6, gauge.end.y + 2.0, 60.0 * k * 1.6, 54.0 * k * 1.6)
	Kit.box(c, plate, Kit.METAL_DARK, 10.0, Kit.INK, 2.0)
	if in_range:
		Kit.tick(c, plate.get_center(), plate.size.y * 0.36)
	else:
		Kit.shape(c, Kit.TRIANGLE, plate.get_center(), plate.size.y * 0.3, (p.warn as Color).darkened(0.1))
	Kit.draw_fill(c, Kit.tex("airlock/pressure_gauge_face"), gauge)
	var r := 138.0 * k
	var band := 30.0 * k
	var green: Color = (p.good as Color).darkened(0.28)
	c.draw_arc(pin, r, deg_to_rad(-BAND_DEG - 90.0), deg_to_rad(BAND_DEG - 90.0), 40, Color(green, 0.86), band, true)
	c.draw_arc(pin, r + band * 0.5, deg_to_rad(-BAND_DEG - 90.0), deg_to_rad(BAND_DEG - 90.0), 40, Kit.INK, 2.0, true)
	c.draw_arc(pin, r - band * 0.5, deg_to_rad(-BAND_DEG - 90.0), deg_to_rad(BAND_DEG - 90.0), 40, Kit.INK, 2.0, true)
	# The low range: short amber dashes from the needle's rest up to the band.
	var amber: Color = (p.warn as Color).darkened(0.22)
	var from := NEEDLE_LOW - 8.0
	var dashes := 6
	var sweep := (-BAND_DEG - 6.0 - from) / float(dashes)
	for i in dashes:
		var a := from + sweep * float(i)
		c.draw_arc(pin, r, deg_to_rad(a - 90.0), deg_to_rad(a + sweep * 0.62 - 90.0), 8, amber, band * 0.5, true)
	var flutter := 0.0 if _calm or in_range else sin(_clock * 9.0) * 1.6 * _vapor
	Kit.draw_turned(c, Kit.tex("airlock/pressure_needle"), pin, NEEDLE_TEX * 0.483 * k, deg_to_rad(_needle + flutter), Color.WHITE, NEEDLE_PIVOT)
	if in_range:
		Kit.tick(c, pin + Vector2(0.0, -r), band * 0.62)
