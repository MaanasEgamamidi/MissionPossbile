extends Node3D
## The gold sparkle guide line (owner 2026-11-15: "In the first week of the game, add glowing sparkles to guide the
## player across different areas during the tutorial round; eventually they'll understand the game mechanics").
## Owner's constant rule: gold + sparkles always mean "this works / go this way".
## ONE line of the tape trails' gold sparkles (tape_trail_presenter.gd: the same star texture, draw mesh, material,
## twinkle and drift) from this machine's player, along the walkable floor (walk_paths.gd, the baked walk grid), to a
## target. It follows the player: a new path about once a second when they have moved, or at once after REPATH_MOVE_M;
## the sparkles of the old line live out their short life while the new line fills in, so one fades into the other.
## The line hides within ARRIVE_M of the target, while a mini-game panel is open, and while seated (rover) or flying
## the drone.
## First-week tutorial guidance (automatic, while no line was asked for by hand): while the tutorial is active and the
## colony is in its first FIRST_WEEK_SOLS sols, the line points to the next thing in the tutorial flow:
##   - tapes not all found: nothing (the six tape trails already lead to them);
##   - all found, not all played: the Command Room cassette player;
##   - the repairs: the nearest still-broken part this player's crew member can fix (a general job or their own
##     specialty); when none is left for them, the Med Bay crew hub, where C changes crew member.
## After that week or once the tutorial is done it is off.
## By hand (the H key, scripts/guide/help_key.gd): show_line_to(target, seated_ok) follows the player to a target (with
## seated_ok also from the rover seat: a walk path, or off the walk grid a short straight run toward the target),
## show_line(a, b) draws a fixed line
## from a to b, clear() ends either (the tutorial guidance then comes back if it applies). Find the node with
## get_tree().get_first_node_in_group(&"guide_sparkles").
## Cheap: one GPUParticles3D, one emission point every SPACING m (wider on long lines), MAX_SPARKLES at most (half on
## the Low preset), 30 fps fixed step, no shadows, lights or collision, a visibility box around the line only.
## Presentation only, on every machine for its own player. Made by CassettePresenter.setup. Loaded by path (no
## class_name).

const TapeTrails := preload("res://scripts/cassettes/tape_trail_presenter.gd")
const WalkPaths := preload("res://scripts/guide/walk_paths.gd")
const GROUP := &"guide_sparkles"

## Distance between emission points along the line, metres (widened so a long line stays under MAX_SPARKLES).
const SPACING := 0.15
const MAX_SPARKLES := 400
## Re-path at most this often while the player moves a little (seconds, metres), at once after REPATH_MOVE_M.
const REPATH_S := 1.0
const REPATH_MIN_MOVE_M := 0.25
const REPATH_MOVE_M := 1.5
## A target that moves more than this gets a new line at once, metres.
const RETARGET_M := 0.3
## The line hides this close to its target, metres (plan distance).
const ARRIVE_M := 2.0
## The line starts this far ahead of the player's feet, metres.
const SKIP_START_M := 0.5
## Shortest line worth drawing, metres.
const MIN_LINE_M := 0.4
## Small up / down and sideways scatter of the emission points around the path, metres (the path is already lifted
## WalkPaths.LIFT above the floor).
const JITTER_Y := 0.03
const SCATTER := 0.03
## Tutorial guidance runs in the colony's first week.
const FIRST_WEEK_SOLS := 7.0
## Seconds between looks at the tutorial state, and between choosing the nearest repair again by walking distance.
const LOOK_S := 0.5
const CHOOSE_S := 4.0
## Repairs compared by walking distance (the nearest ones in a straight line).
const CHOOSE_BY_WALK := 3
## H key in the rover (show_line_to(at, true)): off the walk grid the line is a straight run toward the target, starting
## this far ahead of the seat (clear of the rover's body) and at most this long, metres. While seated the line is
## re-pathed on the REPATH_S clock only (a driven rover moves REPATH_MOVE_M in a fraction of a second).
const STRAIGHT_SKIP_M := 2.5
const STRAIGHT_MAX_M := 30.0

enum Mode { AUTO, FOLLOW, FIXED }

var services: GameServices
## game_main (for its `player` and `ui`); found from the parents when not given.
var game: Node
var paths: WalkPaths
var particles: GPUParticles3D
var _process_mat: ParticleProcessMaterial

var mode := Mode.AUTO
## True when the line asked for by hand also shows while seated (the H key in the rover, scripts/guide/help_key.gd).
var allow_seated := false
var _manual_target := Vector3.ZERO
var _fixed_from := Vector3.ZERO

## What the line points at now, and why ("tape_player", "repair:T03", "crew_hub", "manual", "" = nothing).
var target := Vector3.ZERO
var has_target := false
var reason := ""
## Emission points of the current line (checks).
var point_count := 0

var _on := false
var _drain := 0.0
var _has_line := false
var _line_from := Vector3.ZERO
var _line_to := Vector3.ZERO
var _since_path := 0.0
var _aabb_prev := AABB()
var _look_left := 0.0
var _choose_left := 0.0
## The tutorial guidance's last answer ({"at", "why"} or {}).
var _auto := {}
## Station floor anchors: station id -> Vector3 (repair stations and the cassette player).
var _anchors := {}


func setup(p_services: GameServices, p_game: Node = null) -> void:
	services = p_services
	if p_game != null:
		game = p_game
	name = "GuideSparkles"
	top_level = true
	add_to_group(GROUP)
	for entry: Dictionary in StationCatalog.extra_entries():
		var kind := String(entry.get("kind", ""))
		if (kind == "repair_task" or kind == "cassette_player_anchor") and entry.has("position") and entry.has("id"):
			var q: Array = entry.position
			_anchors[String(entry.id)] = Vector3(float(q[0]), float(q[1]), float(q[2]))
	_build_particles()


func _ready() -> void:
	if game == null:
		var n := get_parent()
		while n != null and not ("player" in n and "ui" in n):
			n = n.get_parent()
		game = n


# ---------------------------------------------------------------- public (the H key later)

## A line from the player to `at`, following them, until clear(). seated_ok: it also shows while seated (the rover),
## from the seat (the H key).
func show_line_to(at: Vector3, seated_ok := false) -> void:
	mode = Mode.FOLLOW
	allow_seated = seated_ok
	_manual_target = at
	_has_line = false


## A fixed line from `from` to `to` (it does not follow the player), until clear().
func show_line(from: Vector3, to: Vector3) -> void:
	mode = Mode.FIXED
	allow_seated = false
	_fixed_from = from
	_manual_target = to
	_has_line = false
	if _draw_path(from, to):
		_set_on(true)
	else:
		_set_on(false)


## Ends a line asked for by hand; the first-week tutorial guidance comes back when it applies.
func clear() -> void:
	mode = Mode.AUTO
	allow_seated = false
	_has_line = false
	_look_left = 0.0
	_set_on(false)


## True while sparkles are being drawn (fading ones not counted).
func is_showing() -> bool:
	return _on


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	step(delta)


## One frame of the guide (tests call it directly).
func step(delta: float) -> void:
	if _drain > 0.0:
		_drain = maxf(0.0, _drain - delta)
		if _drain <= 0.0 and not _on:
			particles.visible = false
	if services == null or not services.has_game():
		_set_on(false)
		return
	if mode == Mode.FIXED:
		return
	_since_path += delta
	var want := _want(delta)
	has_target = not want.is_empty()
	reason = String(want.get("why", ""))
	if has_target:
		target = want.at
	var from := _player_position()
	if not has_target or not from.is_finite() or _blocked() or \
			(Vector2(from.x, from.z).distance_to(Vector2(target.x, target.z)) <= ARRIVE_M and absf(from.y - target.y) < 2.0):
		# Hidden: the next time it shows it starts from a fresh path.
		_has_line = false
		_set_on(false)
		return
	var moved := from.distance_to(_line_from) if _has_line else INF
	var retarget := not _has_line or target.distance_to(_line_to) > RETARGET_M
	var seated := _seated_line()
	if retarget or (moved > REPATH_MOVE_M and not seated) or (_since_path >= REPATH_S and moved > REPATH_MIN_MOVE_M):
		# A failed path is tried again only after the player moved (or the target did), not every frame.
		_since_path = 0.0
		_line_from = from
		_line_to = target
		_has_line = true
		_set_on(_draw_path(from, target) or (seated and _draw_straight(from, target)))


## {"at": Vector3, "why": String} the line should point at now, or {}. The tutorial state is looked at every LOOK_S.
func _want(delta: float) -> Dictionary:
	if mode == Mode.FOLLOW:
		return {"at": _manual_target, "why": "manual"}
	_look_left -= delta
	_choose_left -= delta
	if _look_left <= 0.0:
		_look_left = LOOK_S
		_auto = tutorial_target()
	return _auto


# ---------------------------------------------------------------- the first-week tutorial guidance

## True while the automatic guidance applies: tutorial mode, and the colony's first FIRST_WEEK_SOLS sols.
func tutorial_week(st: ColonyState) -> bool:
	return st != null and TutorialSystem.tutorial_active(st) and st.sim_hours / GameConfig.SOL_HOURS < FIRST_WEEK_SOLS


## The next thing in the tutorial flow for this machine's player: {"at", "why"} or {} (see the header).
func tutorial_target() -> Dictionary:
	var st := services.state()
	if not tutorial_week(st):
		return {}
	# Tapes not all found: the six tape trails lead the way.
	if not TutorialSystem.repairs_unlocked(st):
		return {}
	if TutorialSystem.tapes_played(st) < TutorialSystem.tapes_found(st):
		var deck: Variant = _anchors.get(CassetteCatalog.PLAYER_ID)
		return {"at": deck, "why": "tape_player"} if deck is Vector3 else {}
	var me := services.local_character()
	if me == null:
		return {}
	var mine := String(me.specialty)
	var open: Array[Dictionary] = []
	var any_open := false
	for row: Dictionary in TutorialSystem.fix_rows(st):
		if bool(row.get("done", false)) or not TutorialSystem.task_unlocked(st, String(row.task)):
			continue
		any_open = true
		var spec := String(row.get("specialty", ""))
		if spec != "" and spec != mine:
			continue
		var at: Variant = _anchors.get(RepairCatalog.anchor_id(String(row.task)))
		if at is Vector3:
			open.append({"at": at, "why": "repair:" + String(row.task)})
	if not open.is_empty():
		return _nearest(open)
	if any_open:
		# Nothing left that this crew member can do: C changes crew member at the Med Bay hub.
		return {"at": services.config.hub_position, "why": "crew_hub"}
	return {}


## The nearest choice by walking distance (the CHOOSE_BY_WALK nearest in a straight line are compared), kept for
## CHOOSE_S seconds while it stays on the list so the line does not flip between two parts.
func _nearest(choices: Array[Dictionary]) -> Dictionary:
	var current := String(_auto.get("why", ""))
	if current != "" and _choose_left > 0.0:
		for c: Dictionary in choices:
			if String(c.why) == current:
				return c
	_choose_left = CHOOSE_S
	var from := _player_position()
	if not from.is_finite():
		return choices[0]
	choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Vector3 = a.at
		var pb: Vector3 = b.at
		return from.distance_squared_to(pa) < from.distance_squared_to(pb))
	var walk := _paths()
	if walk == null or not walk.ok:
		return choices[0]
	var best := choices[0]
	var best_len := INF
	for i in mini(CHOOSE_BY_WALK, choices.size()):
		var at: Vector3 = choices[i].at
		var length := walk.walk_length(from, at)
		if length < best_len:
			best_len = length
			best = choices[i]
	return best


# ---------------------------------------------------------------- the player

func _player() -> PlayerController:
	if game == null or not is_instance_valid(game):
		return null
	var p: Variant = game.get("player")
	return p as PlayerController if p is PlayerController and is_instance_valid(p) else null


## Where this machine's player stands (the body, else the replicated record), or Vector3.INF.
func _player_position() -> Vector3:
	var p := _player()
	if p != null and p.is_inside_tree():
		return p.global_position
	var me := services.local_character() if services != null and services.has_game() else null
	return me.position if me != null else Vector3.INF


## True while the line must not show: a mini-game panel is open, the player is seated (rover) or flies the drone.
func _blocked() -> bool:
	var p := _player()
	if p != null and p.is_seated() and not _seated_line():
		return true
	if is_inside_tree():
		var drone := get_tree().get_first_node_in_group(&"drone_presenter")
		if drone != null and bool(drone.get("piloting")):
			return true
	var ui := game.get("ui") as UiRoot if game != null and is_instance_valid(game) else null
	if ui != null:
		var top := ui.top()
		if top != null and bool(top.get_meta(&"station_surface", false)):
			return true
	return false


## True while a line asked for by hand with seated_ok is shown from a seat (the H key in the rover).
func _seated_line() -> bool:
	if not allow_seated or mode != Mode.FOLLOW:
		return false
	var p := _player()
	return p != null and p.is_seated()


# ---------------------------------------------------------------- the sparkle line

func _paths() -> WalkPaths:
	if paths == null:
		paths = WalkPaths.shared() as WalkPaths
	return paths


## The one emitter: the tape trails' sparkle look, a fixed amount (half on Low) of which amount_ratio uses as many
## as the line has points. Starts hidden and not emitting.
func _build_particles() -> void:
	_process_mat = ParticleProcessMaterial.new()
	_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS
	_process_mat.emission_point_texture = TapeTrails._vector_texture(PackedVector3Array([Vector3.ZERO]))
	_process_mat.emission_normal_texture = TapeTrails._vector_texture(PackedVector3Array([Vector3.FORWARD]))
	_process_mat.emission_point_count = 1
	# Directed points turn local +Z onto each point's normal (the path direction): the sparkles drift toward the target.
	_process_mat.direction = Vector3(0.0, 0.0, 1.0)
	_process_mat.spread = 6.0
	_process_mat.initial_velocity_min = TapeTrails.DRIFT_MIN
	_process_mat.initial_velocity_max = TapeTrails.DRIFT_MAX
	_process_mat.gravity = Vector3.ZERO
	_process_mat.lifetime_randomness = 0.35
	TapeTrails._style(_process_mat)
	particles = GPUParticles3D.new()
	particles.name = "GuideLine"
	var low := is_inside_tree() and GraphicsQuality.applied_level(get_tree()) == GraphicsQuality.Level.LOW
	particles.amount = int(MAX_SPARKLES * 0.5) if low else MAX_SPARKLES
	particles.amount_ratio = 0.0
	particles.lifetime = TapeTrails.LIFETIME
	particles.process_material = _process_mat
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3.ZERO, Vector3.ONE)
	TapeTrails._tune(particles)
	particles.layers = _layers()
	particles.emitting = false
	particles.visible = false
	add_child(particles)


## Render layers: every colony zone's bit plus the sun layer (the line crosses rooms, the plaza and the open ground),
## all 20 layers when the zones are not known. The same mask as the tape trails.
func _layers() -> int:
	if services == null or services.zones == null:
		return (1 << 20) - 1
	var mask := services.zones.sun_bit()
	for zone: String in services.zones.names:
		mask |= services.zones.bit_of(zone)
	return mask


## Paths from `from` to `to` and puts the line's points into the emitter. False when there is no line worth drawing.
func _draw_path(from: Vector3, to: Vector3) -> bool:
	var walk := _paths()
	if walk == null or not walk.ok:
		return false
	var pts := walk.path(from, to)
	if pts.size() < 2:
		point_count = 0
		return false
	return _set_points(TapeTrails.rounded(pts))


## Off the walk grid while seated (the rover out on the open ground): a straight run at seat height toward `to`, from
## STRAIGHT_SKIP_M ahead, at most STRAIGHT_MAX_M long. It shows the way to head, not a path.
func _draw_straight(from: Vector3, to: Vector3) -> bool:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var d := flat.length()
	if d < STRAIGHT_SKIP_M + SKIP_START_M + MIN_LINE_M:
		point_count = 0
		return false
	var dir := flat / d
	var a := from + dir * STRAIGHT_SKIP_M
	var b := from + dir * minf(d, STRAIGHT_SKIP_M + STRAIGHT_MAX_M)
	b.y = a.y
	return _set_points(PackedVector3Array([a, b]))


## One emission point every SPACING m along the line from SKIP_START_M on (a little scatter, from a fixed seed), each
## with the line's direction as its normal. The old line's sparkles keep living out their life where they are (world
## coordinates), so the visibility box covers the old line and the new one.
func _set_points(line: PackedVector3Array) -> bool:
	var total := TapeTrails.path_length(line)
	if total - SKIP_START_M < MIN_LINE_M:
		point_count = 0
		return false
	var spacing := maxf(SPACING, (total - SKIP_START_M) / float(MAX_SPARKLES))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	var points := PackedVector3Array()
	var dirs := PackedVector3Array()
	var carry := SKIP_START_M
	for i in range(1, line.size()):
		var a := line[i - 1]
		var b := line[i]
		var seg := a.distance_to(b)
		if seg < 0.0001:
			continue
		var dir := (b - a) / seg
		var side := Vector3(-dir.z, 0.0, dir.x).normalized()
		var s := carry
		while s < seg and points.size() < MAX_SPARKLES:
			points.append(a + dir * s + Vector3(0.0, rng.randf_range(-JITTER_Y, JITTER_Y), 0.0) + side * rng.randf_range(-SCATTER, SCATTER))
			dirs.append(dir)
			s += spacing
		carry = s - seg
	if points.size() < 2:
		point_count = 0
		return false
	_process_mat.emission_point_texture = TapeTrails._vector_texture(points)
	_process_mat.emission_normal_texture = TapeTrails._vector_texture(dirs)
	_process_mat.emission_point_count = points.size()
	particles.amount_ratio = clampf(float(points.size()) / float(MAX_SPARKLES), 0.01, 1.0)
	point_count = points.size()
	var lo := points[0]
	var hi := points[0]
	for p: Vector3 in points:
		lo = lo.min(p)
		hi = hi.max(p)
	var grow := Vector3.ONE * (TapeTrails.DRIFT_MAX * TapeTrails.LIFETIME + TapeTrails.SPARKLE_SIZE)
	var box := AABB(lo - grow, hi - lo + grow * 2.0)
	particles.visibility_aabb = box.merge(_aabb_prev) if particles.visible else box
	_aabb_prev = box
	return true


## Starts or stops the sparkles. Stopping lets the last ones live out their life, then hides the emitter.
func _set_on(on: bool) -> void:
	if on == _on:
		return
	_on = on
	if on:
		_drain = 0.0
		particles.visible = true
		particles.emitting = true
	else:
		particles.emitting = false
		_drain = TapeTrails.LIFETIME if particles.visible else 0.0
		if _drain <= 0.0:
			particles.visible = false
