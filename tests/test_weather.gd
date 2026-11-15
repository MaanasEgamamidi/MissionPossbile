extends SceneTree
## Prompt 09, weather worker: the bundle loader and validator, the background refresh (simulated HTTP, no network),
## the dust-event scheduler, the walking-route return margin, the weather screen and the sky presentation.
## Run: ..\godot.cmd --headless --path . --script res://tests/test_weather.gd
## Data: tests/fixtures/weather_bundle_w (a small synthetic bundle in the contract format; NOT observations).
## Every PASS is measured on the running code. INFO lines report numbers (seed spread, timings, margins).

const FIXTURE := "res://tests/fixtures/weather_bundle_w"
const MANIFEST := "res://data/colony_manifest.json"
const SOL := GameConfig.SOL_HOURS
## Outdoor test points (Godot x, y, z): east tracker field, beside the landing pad, the crash site.
const TEST_POINTS: Array[Vector3] = [Vector3(52.0, 0.0, 0.0), Vector3(-20.0, 0.0, 40.0), Vector3(2.0, 0.0, 62.0)]


## Simulated HTTP: answers from a list, records every request.
class FakeTransport extends RefCounted:
	var responses: Array = []
	var requests: Array = []

	func fetch(request: Dictionary, done: Callable) -> void:
		requests.append(request)
		var r: Dictionary = responses.pop_front() if not responses.is_empty() else {"status": 304, "error": "", "body": PackedByteArray(), "headers": {}}
		done.call(r)


## Collects engine and script errors raised while the test runs.
class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR or error_type == ERROR_TYPE_SCRIPT:
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _passed := 0
var _total := 0
var _zones: ColonyZones
var _catalog: Dictionary
var _event_nodes: Array[GameEvents] = []
var _tmp := ""
var _catcher := ErrorCatcher.new()
var _now := 1.8e9


func _initialize() -> void:
	OS.add_logger(_catcher)
	PlayerInput.ensure_actions()
	_tmp = ProjectSettings.globalize_path("res://").path_join("_test_weather")
	WeatherRefresh._remove_tree(_tmp)
	DirAccess.make_dir_recursive_absolute(_tmp)
	_zones = ColonyZones.from_manifest(MANIFEST)
	_catalog = StationCatalog.from_manifest(MANIFEST, _zones)
	_use(FIXTURE, "boot")

	_test_archive_boot()
	_test_validation()
	_test_cache_choice()
	_test_routes()
	_test_ls()
	_test_teaching()
	_test_replay()
	_test_save_reload_mid_storm()
	_test_events_and_late_join()
	_test_warning_margin()
	_test_seed_spread_and_recovery()
	_test_refresh()
	await _test_panel_and_presenter()

	_check("no script or engine errors during the test", _catcher.errors.is_empty(), "\n".join(_catcher.errors))
	OS.remove_logger(_catcher)
	for node: GameEvents in _event_nodes:
		node.free()
	WeatherArchive.shipped_dir_override = ""
	WeatherArchive.cache_root_override = ""
	WeatherArchive.invalidate()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


# ---------------------------------------------------------------- helpers

func _check(label: String, ok: bool, detail: String = "state mismatch") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS " + label)
	else:
		print("FAIL " + label + ": " + detail)


func _info(text: String) -> void:
	print("INFO " + text)


## Points the archive at a shipped folder and a fresh cache root for one case.
func _use(shipped: String, case_name: String) -> String:
	var root := _tmp.path_join("cache_" + case_name)
	WeatherRefresh._remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)
	WeatherArchive.shipped_dir_override = shipped
	WeatherArchive.cache_root_override = root
	WeatherArchive.invalidate()
	return root


## A host session on the real map with `active` crew (peers 1..active), as the game makes one.
func _session(seed_value: int, active: int = 1, balance: GameBalance = null) -> SessionService:
	var ev := GameEvents.new()
	_event_nodes.append(ev)
	var s := SessionService.new(GameConfig.new(), balance if balance != null else GameBalance.new(), ev)
	var st := ColonyState.new_game(s.balance, seed_value, _zones.names)
	st.stations = _catalog.duplicate(true)
	for c: CharacterState in st.characters.values():
		c.hub_spot = s.config.hub_position
		c.position = c.hub_spot
	var clock := SolClock.new()
	clock.phase = s.config.start_phase
	s.begin(st, clock)
	for i in active:
		st.character(StringName("crew_%d" % (i + 1))).owner_peer = i + 1
		if i > 0:
			s.peer_joined(i + 1)
	s.outside_test = func(p: Vector3) -> bool: return _zones.zone_at_world(p) == ColonyZones.EXTERIOR
	return s


## Advances by `hours` game hours in ticks of `dt`; returns the number of characters that reached zero health.
## `each(t)` is called after every tick.
func _hours(s: SessionService, hours: float, dt: float = 0.1, each: Callable = Callable()) -> int:
	# These long-horizon weather checks call the model directly. Reconcile fixture
	# teleports exactly as Session.advance does before ticking, so returning from
	# panel cleaning cannot leave an indoor astronaut classified as outside.
	s.survival.refresh_all()
	var downs := 0
	var t := 0.0
	while t < hours - 1e-9:
		var h := minf(dt, hours - t)
		var phase_before := s.clock.phase
		var got := s.clock.advance(h / s.clock.hours_per_real_second())
		for id: StringName in s.sim.step(s.state, s.balance, phase_before, got):
			s.recover_character(id)
			downs += 1
		t += h
		if each.is_valid():
			each.call(t)
	return downs


## Runs until `cond()` is true or `max_hours` pass. Returns true if the condition was met.
func _until(s: SessionService, cond: Callable, max_hours: float, dt: float = 0.1) -> bool:
	var t := 0.0
	while t < max_hours:
		_hours(s, dt, dt)
		t += dt
		if bool(cond.call()):
			return true
	return false


## crew_1 cleans every sun tracker once (the one player action of the escalation run), then goes back inside.
func _clean_all(s: SessionService) -> bool:
	var ok := true
	var c := s.state.character(&"crew_1")
	for id: String in s.state.stations:
		if String(s.state.stations[id].kind) == "solar":
			c.position = CharacterState._v3(s.state.stations[id].position)
			ok = s.request(&"clean_panel", StringName(id), {}, c.owner_peer).ok and ok
	c.position = c.hub_spot
	return ok


## JSON text after one JSON round trip (numbers all become floats, as in a save or a network snapshot).
func _json(v: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v, "", true, true)), "", true, true)


## Runs two sessions tick by tick together until `cond()` or `max_hours`.
func _until_pair(a: SessionService, b: SessionService, cond: Callable, max_hours: float, dt: float = 0.1) -> bool:
	var t := 0.0
	while t < max_hours:
		_hours(a, dt, dt)
		_hours(b, dt, dt)
		t += dt
		if bool(cond.call()):
			return true
	return false


func _ws(s: SessionService) -> WeatherSystem:
	return WeatherSystem.of_session(s)


func _copy_bundle(src: String, dst: String) -> void:
	WeatherRefresh._remove_tree(dst)
	DirAccess.make_dir_recursive_absolute(dst)
	for f in ["manifest.json", "meda_ps.csv", "meda_tau.csv", "meda_wind.csv", "episodes.json"]:
		var bytes := FileAccess.get_file_as_bytes(src.path_join(f))
		var fa := FileAccess.open(dst.path_join(f), FileAccess.WRITE)
		fa.store_buffer(bytes)
		fa.close()


func _manifest(dir: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("manifest.json")))


func _save_manifest(dir: String, m: Dictionary) -> void:
	var fa := FileAccess.open(dir.path_join("manifest.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify(m, "\t", false, true))
	fa.close()


## Replaces a product file and (if `fix_sha`) its sha256 and bytes in the manifest.
func _replace_file(dir: String, file: String, text: String, fix_sha: bool) -> void:
	var fa := FileAccess.open(dir.path_join(file), FileAccess.WRITE)
	fa.store_string(text)
	fa.close()
	if fix_sha:
		var m := _manifest(dir)
		for p: Dictionary in m.products:
			if String(p.file) == file:
				p.sha256 = FileAccess.get_sha256(dir.path_join(file))
				p.bytes = text.to_utf8_buffer().size()
		_save_manifest(dir, m)


func _tree_hash(dir: String) -> String:
	if not DirAccess.dir_exists_absolute(dir):
		return "(none)"
	var parts := PackedStringArray()
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for f in files:
		parts.append("%s=%s" % [f, FileAccess.get_sha256(dir.path_join(f))])
	return ",".join(parts)


func _stats(values: Array) -> String:
	if values.is_empty():
		return "none"
	var lo := INF
	var hi := -INF
	var sum := 0.0
	for v: Variant in values:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
		sum += float(v)
	return "min %.2f, mean %.2f, max %.2f (n %d)" % [lo, sum / values.size(), hi, values.size()]


func _distinct(values: Array, decimals: float = 0.01) -> int:
	var seen := {}
	for v: Variant in values:
		seen[snappedf(float(v), decimals)] = true
	return seen.size()


# ---------------------------------------------------------------- archive

func _test_archive_boot() -> void:
	_use(FIXTURE, "boot")
	var a := WeatherArchive.active()
	_check("offline boot: with no cache the shipped bundle is used (%s)" % a.snapshot_id(), a.ok and a.source == "shipped" and a.snapshot_id() == "fixture-weather-w-v1@1", "%s %s" % [a.source, a.problems])
	var s := _session(3)
	_hours(s, 1.0)
	var data: Dictionary = s.state.weather.get("data", {})
	_check("offline boot: a new game pins the snapshot id and saves the site and archive dates with the game",
		s.state.data_snapshot_id == a.snapshot_id() and String(data.get("site", "")) == "Jezero crater" and String(data.get("observation_start", "")).begins_with("2022-01-01"), str(data))
	_check("the default shipped folder is res://data/weather/bundle and the cache user://weather_cache/current",
		WeatherArchive.SHIPPED_DIR == "res://data/weather/bundle" and WeatherArchive.CACHE_ROOT.path_join("current") == "user://weather_cache/current")

	_use("res://tests/fixtures/no_such_bundle", "none")
	var d := WeatherArchive.active()
	var s2 := _session(3)
	var taus: Array = []
	_hours(s2, 3.0 * SOL, 0.25, func(_t: float) -> void: taus.append(s2.state.dust_tau))
	var constant := true
	for v: Variant in taus:
		constant = constant and absf(float(v) - s2.balance.dust_tau_default) < 1e-9
	_check("no bundle at all: a built-in default, clearly labelled (no archive data, constant sky, no events)",
		d.is_builtin() and d.describe().contains("no archive data") and constant and s2.state.weather_queue.is_empty()
		and String((s2.state.weather.data as Dictionary).source) == "builtin", "%s %s queue %d" % [d.describe(), taus.slice(0, 3), s2.state.weather_queue.size()])
	_use(FIXTURE, "boot")


func _test_validation() -> void:
	var base := WeatherArchive.load_dir(FIXTURE)
	_check("fixture validates: manifest fields, sha256, units, missing values, monotonic time (%d products, %d episodes)" % [base.products().size(), base.episodes.size()],
		base.ok and base.products().size() == 3 and base.episodes.size() == 3 and int(base.product_stats.fx_meda_tau.rows) == 61, "\n".join(base.problems))
	var tau_p := base.product("fx_meda_tau")
	_check("the bundle's conventions are accepted: a non-PDS research-archive product (pds_lid 'none (...)'), an Ls range wrapping through 0/360 (%.3f -> %.1f), a time column `sol` in unit \"1\"" % [float(tau_p.ls_start), float(tau_p.ls_end)],
		base.ok and String(tau_p.pds_lid).begins_with("none (") and float(tau_p.ls_start) > float(tau_p.ls_end) and String((tau_p.columns as Dictionary).sol) == "1"
		and String(base.product_stats.fx_meda_tau.time_column) == "sol" and absf(base.start_ls(-1.0) - 150.0) < 1e-9, str(base.observation_period()))
	_check("missing values are skipped, never used as numbers: wind -999.0 rows leave the measured mean (%.2f m/s)" % base.mean_of_kind("wind", -1.0, "m/s"),
		base.mean_of_kind("wind", -1.0, "m/s") > 3.0 and base.mean_of_kind("wind", -1.0, "m/s") < 9.0 and WeatherArchive.is_missing(float(base.episode("fx_minor").wind_ms_mean)))
	var cases := [
		["unit not allowed (degC)", func(dir: String) -> void:
			var m := _manifest(dir)
			m.products[1].columns["tau"] = "degC"
			_save_manifest(dir, m), "unit"],
		["unit not listed in units_ok", func(dir: String) -> void:
			var m := _manifest(dir)
			m.products[0].units_ok = ["1"]
			_save_manifest(dir, m), "not allowed"],
		["invalid flag value 1.5", func(dir: String) -> void:
			_replace_file(dir, "meda_tau.csv", "sol,tau,tau_flag\n300.0,0.56,0\n300.5,0.57,1.5\n", true), "flag"],
		["negative flag", func(dir: String) -> void:
			_replace_file(dir, "meda_tau.csv", "sol,tau,tau_flag\n300.0,0.56,0\n300.5,0.57,-1\n", true), "flag"],
		["sha256 mismatch", func(dir: String) -> void:
			_replace_file(dir, "meda_wind.csv", "sol,wind_ms\n300,4.0\n301,4.1\n", false), "sha256"],
		["time going backwards", func(dir: String) -> void:
			_replace_file(dir, "meda_ps.csv", "sol,ps_pa,ps_flag\n300,720.0,0\n302,721.0,0\n301,722.0,0\n", true), "backwards"],
		["a number that is not a number", func(dir: String) -> void:
			_replace_file(dir, "meda_ps.csv", "sol,ps_pa,ps_flag\n300,720.0,0\n301,abc,0\n", true), "not a number"],
		["implausible pressure", func(dir: String) -> void:
			_replace_file(dir, "meda_ps.csv", "sol,ps_pa,ps_flag\n300,720.0,0\n301,99000.0,0\n", true), "plausible"],
		["missing manifest field (license)", func(dir: String) -> void:
			var m := _manifest(dir)
			(m.products[2] as Dictionary).erase("license")
			_save_manifest(dir, m), "license"],
		["header does not match columns", func(dir: String) -> void:
			_replace_file(dir, "meda_wind.csv", "sol,wind_speed\n300,4.0\n301,4.1\n", true), "header"],
		["a product from a distant site (Gale crater)", func(dir: String) -> void:
			var m := _manifest(dir)
			m.products[2].lat = -4.59
			m.products[2].lon = 137.44
			_save_manifest(dir, m), "one site"],
		["episodes file changed", func(dir: String) -> void:
			var fa := FileAccess.open(dir.path_join("episodes.json"), FileAccess.READ_WRITE)
			fa.seek_end()
			fa.store_string(" ")
			fa.close(), "episodes file"],
		["broken manifest JSON", func(dir: String) -> void:
			var fa := FileAccess.open(dir.path_join("manifest.json"), FileAccess.WRITE)
			fa.store_string("{\"format\": ")
			fa.close(), "manifest"],
	]
	var all_ok := true
	var detail := ""
	for c: Array in cases:
		var dir := _tmp.path_join("bad_%d" % detail.length())
		_copy_bundle(FIXTURE, dir)
		(c[1] as Callable).call(dir)
		var a := WeatherArchive.load_dir(dir, "cache")
		var named := false
		for p in a.problems:
			if p.to_lower().contains(String(c[2]).to_lower()):
				named = true
		var picked := WeatherArchive.choose(base, a)
		if a.ok or not named or picked != base:
			all_ok = false
			detail += " [%s: ok=%s problems=%s]" % [c[0], a.ok, a.problems]
		else:
			detail += "."
	_check("invalid data is rejected with the problem named, and the shipped bundle stays in use (%d cases: units, flags, sha256, time, numbers, ranges, fields, header, sites, episodes, JSON)" % cases.size(), all_ok, detail)


func _test_cache_choice() -> void:
	var root := _use(FIXTURE, "choice")
	var current := root.path_join("current")
	_copy_bundle(FIXTURE, current)
	var m := _manifest(current)
	m.built_utc = "2025-01-01T00:00:00Z"
	m.version = "old"
	_save_manifest(current, m)
	WeatherArchive.invalidate()
	var a := WeatherArchive.active()
	_check("a stale cache older than the shipped bundle is ignored", a.source == "shipped" and WeatherArchive.load_dir(current, "cache").ok, a.source)
	m.built_utc = "2027-01-01T00:00:00Z"
	m.version = "newer"
	m.base_built_utc = "2026-11-13T00:00:00Z"
	_save_manifest(current, m)
	WeatherArchive.invalidate()
	a = WeatherArchive.active()
	_check("a newer valid cache built on the shipped bundle is used", a.source == "cache" and a.snapshot_id() == "fixture-weather-w-v1@newer", a.snapshot_id())
	m.base_built_utc = "2025-06-01T00:00:00Z"
	_save_manifest(current, m)
	WeatherArchive.invalidate()
	a = WeatherArchive.active()
	_check("a cache built on an older shipped bundle is ignored after a game update", a.source == "shipped", a.source)
	m.base_built_utc = "2026-11-13T00:00:00Z"
	m.products[1].sha256 = "00"
	_save_manifest(current, m)
	WeatherArchive.invalidate()
	a = WeatherArchive.active()
	_check("a damaged cache never crashes: the shipped bundle is used and the reason is noted", a.source == "shipped" and "\n".join(a.notes).contains("not valid"), str(a.notes))
	_use(FIXTURE, "boot")


# ---------------------------------------------------------------- routes and Ls

func _test_routes() -> void:
	var r := ReturnRoutes.shared()
	_check("route grid: baked grid loaded (%d x %d cells of %.0f m, %d reachable)" % [r.width, r.depth, r.cell, r.reachable_cells()],
		r.origin_kind == "baked" and r.cell == 2.0 and r.reachable_cells() > 20000 and r.entrance_cells.size() == 1, r.origin_kind)
	var agree := true
	var lines := PackedStringArray()
	for p: Vector3 in TEST_POINTS:
		var field := r.return_metres(p)
		var astar := r.astar_metres(p)
		var straight := Vector2(p.x, p.z).distance_to(Vector2(22.0, 15.7))
		lines.append("%s: walk %.1f m (A* %.1f m, straight line %.1f m), %.1f s at %.1f m/s" % [p, field, astar, straight, field / 2.4, 2.4])
		agree = agree and field > 0.0 and absf(field - astar) <= 0.005 * field and field >= straight - 1e-3
	_info("return routes: " + "; ".join(lines))
	_check("route grid: the walking cost home from the 3 outdoor test points is the same by the Dijkstra field and by A*, and never shorter than the straight line", agree, "; ".join(lines))
	var inside := r.return_metres(Vector3(10.0, 0.0, -5.0))
	var hall_blocked := r.is_blocked(r.cell_of(10.0, -5.0)) and r.is_blocked(r.cell_of(22.0, 12.0))
	# big rocks that stand out of the ground (scaled at least 1 across, centre not buried) must be obstacles;
	# pebbles and half-buried rocks lower than a step are walked over
	var rock_blocked := 0
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var terrain := load(ReturnRoutes.TERRAIN_PATH) as TerrainHeight
	var near := 0
	for o: Dictionary in data.environment_objects:
		if String(o.collection) == ReturnRoutes.ROCK_COLLECTION:
			var xf := WorldCollision.object_transform(o.matrix_world)
			var p := xf.origin
			var sc := xf.basis.get_scale()
			if Vector2(p.x, p.z).length() < 250.0 and minf(sc.x, sc.z) >= 1.0 and p.y + 0.4 * sc.y > terrain.height_at(p.x, p.z) + 0.5:
				near += 1
				if r.is_blocked(r.cell_of(p.x, p.z)):
					rock_blocked += 1
	var tracker := CharacterState._v3(_catalog["sf_solar_tracker.006"].position)
	_check("route grid: the glass hall and tunnel are not walkable from outside, big rocks and the sun trackers are obstacles (%d of %d big rocks near the base blocked)" % [rock_blocked, near],
		inside < 0.0 and hall_blocked and near >= 10 and float(rock_blocked) >= 0.9 * float(near) and r.is_blocked(r.cell_of(tracker.x, tracker.z)), "inside %.1f hall %s rocks %d/%d" % [inside, hall_blocked, rock_blocked, near])
	var path := r.route(TEST_POINTS[1])
	_check("route grid: an A* route home exists and ends at the tunnel's outer door", path.size() > 10 and Vector2(path[path.size() - 1].x, path[path.size() - 1].z).distance_to(Vector2(22.0, 15.7)) < 2.0, str(path.size()))


func _test_ls() -> void:
	var cfg := WeatherConfig.new()
	var a := WeatherSystem.ls_at(150.0, 0.0, cfg)
	var b := WeatherSystem.ls_at(150.0, cfg.mars_year_sols, cfg)
	var c := WeatherSystem.ls_at(150.0, 10.0, cfg)
	_check("game Ls from the sol count: Ls 150 at sol 0, back to 150 after one Mars year, rising %.2f deg in 10 sols" % fposmod(c - a, 360.0),
		absf(a - 150.0) < 1e-6 and absf(b - 150.0) < 1e-6 and fposmod(c - a, 360.0) > 4.0 and fposmod(c - a, 360.0) < 8.0, "%f %f %f" % [a, b, c])


# ---------------------------------------------------------------- teaching

func _test_teaching() -> void:
	_use(FIXTURE, "boot")
	# this colony is not left short of power by 5 sols of neglect (a big battery): the test is about teaching
	var s := _session(11)
	s.balance.battery_discharge_kw_max = 1.0e5
	s.state.capacities[&"battery_kwh"] = 1.0e6
	s.state.stores[&"battery_kwh"] = 5.0e5
	# the same colony with the normal battery, for the readiness hold
	var weak := _session(11)
	_hours(weak, 5.0 * SOL, 0.25)
	_hours(s, 5.0 * SOL, 0.25)
	var w := s.state.weather
	_check("teach first: with no panel cleaned, no dust event in 5 sols and the first event is not scheduled",
		(w.history as Array).is_empty() and (w.active as Dictionary).is_empty() and float(s.state.weather_queue[0].at_hours) < 0.0 and float(w.condition_at_hours) < 0.0,
		"history %d at %s" % [(w.history as Array).size(), s.state.weather_queue[0].at_hours])
	# one panel cleaned at sol 5: the first event comes after it, and it is minor
	var c := s.state.character(&"crew_1")
	c.position = CharacterState._v3(s.state.stations["sf_solar_tracker.002"].position)
	var cleaned := s.request(&"clean_panel", &"sf_solar_tracker.002", {}, 1).ok
	c.position = c.hub_spot
	var clean_at := s.state.sim_hours
	var warned_at := [-1.0]
	s.events.system_alert.connect(func(id: StringName, _l: StringName, _t: String) -> void:
		if id == WeatherSystem.ALERT_ID and float(warned_at[0]) < 0.0:
			warned_at[0] = s.state.sim_hours)
	_until(s, func() -> bool: return not (s.state.weather.history as Array).is_empty(), 6.0 * SOL, 0.25)
	var first: Dictionary = (s.state.weather.history as Array)[0] if not (s.state.weather.history as Array).is_empty() else {}
	_check("teach first: after a panel is cleaned (sol %.1f) the first event starts later (sol %.2f), with a warning before it" % [clean_at / SOL, float(first.get("at_hours", 0.0)) / SOL],
		cleaned and not first.is_empty() and float(first.at_hours) >= clean_at + 6.0 and float(warned_at[0]) >= clean_at and float(warned_at[0]) < float(first.at_hours), "%s warned %s" % [first, warned_at])
	_check("teach first: the first event is minor (the smallest archive episode, severity %.2f <= %.2f)" % [float(first.get("severity", 9.0)), WeatherConfig.new().minor_severity_max],
		String(first.get("episode_id", "")) == "fx_minor" and float(first.get("severity", 9.0)) <= WeatherConfig.new().minor_severity_max + 1e-9, str(first))
	# the neglected colony (battery low at night, loads shed): the taught event is held back until it is ready
	var wc := weak.state.character(&"crew_1")
	wc.position = CharacterState._v3(weak.state.stations["sf_solar_tracker.002"].position)
	weak.request(&"clean_panel", &"sf_solar_tracker.002", {}, 1)
	wc.position = wc.hub_spot
	_hours(weak, 2.0 * SOL, 0.25)
	var held: Dictionary = weak.state.weather_queue[0]
	var held_words := ""
	for mv: Dictionary in held.get("moves", []):
		held_words = String(mv.why)
	_check("readiness: a colony that is not ready (battery %.0f kWh, below %.0f) has its first event held back (moved %.0f h)" % [weak.state.store(&"battery_kwh"),
		WeatherConfig.new().battery_reserve_kwh * WeatherConfig.new().hold_battery_factor, float(held.get("shifted_hours", 0.0))],
		(weak.state.weather.history as Array).is_empty() and (weak.state.weather.active as Dictionary).is_empty() and not bool(held.warned)
		and float(held.shifted_hours) > 0.0 and held_words.contains("not ready"), str(held.get("moves", [])))
	# cleaning early: the 2-sol rule decides
	var s2 := _session(12)
	_hours(s2, 0.2 * SOL, 0.25)
	_clean_all(s2)
	_hours(s2, 0.1, 0.1)
	var cond := float(s2.state.weather.condition_at_hours)
	_until(s2, func() -> bool: return not (s2.state.weather.active as Dictionary).is_empty(), 5.0 * SOL, 0.25)
	var started := float((s2.state.weather.active as Dictionary).get("at_hours", -1.0))
	_check("teach first: panels cleaned at sol 0.2, the condition is the 2-sol mark (sol %.2f) and the first event starts after it (sol %.2f)" % [cond / SOL, started / SOL],
		absf(cond - 2.0 * SOL) < 1e-6 and started >= 2.0 * SOL + 6.0, "%f %f" % [cond, started])
	# the practical evidence counts as taught too
	var s3 := _session(13)
	_hours(s3, 0.5, 0.25)
	ProgressEvidence.record(s3.state, s3.events, &"energy_diagnose_output_loss", "energy", &"crew_1")
	_hours(s3, 0.5, 0.25)
	_check("teach first: the evidence energy_diagnose_output_loss also counts as taught", float(s3.state.weather.taught_at_hours) >= 0.0)


# ---------------------------------------------------------------- determinism

func _run_recording(seed_value: int, hours: float, dt: float) -> Dictionary:
	var s := _session(seed_value)
	_clean_all(s)
	var taus := PackedFloat64Array()
	_hours(s, hours, dt, func(_t: float) -> void: taus.append(s.state.dust_tau))
	return {"taus": taus, "queue": _json(s.state.weather_queue), "weather": _json(s.state.weather), "battery": s.state.store(&"battery_kwh"), "session": s}


func _first_event(w: Dictionary) -> Dictionary:
	var h: Array = w.get("history", [])
	return {} if h.is_empty() else h[0]


func _test_replay() -> void:
	_use(FIXTURE, "boot")
	var a := _run_recording(77, 12.0 * SOL, 0.1)
	var b := _run_recording(77, 12.0 * SOL, 0.1)
	var history: Array = (a.session as SessionService).state.weather.history
	_check("deterministic replay: the same seed gives the same queue, the same events and the same opacity curve (%d ticks, %d events), run twice" % [(a.taus as PackedFloat64Array).size(), history.size()],
		a.taus == b.taus and a.queue == b.queue and a.weather == b.weather and history.size() >= 2 and a.battery == b.battery, "events %d" % history.size())
	var ws := (a.session as SessionService).state.weather
	var sources := {}
	var lowest_wind := [INF]
	var rec := _session(77)
	_clean_all(rec)
	_hours(rec, 12.0 * SOL, 0.1, func(_t: float) -> void:
		lowest_wind[0] = minf(float(lowest_wind[0]), float(rec.state.weather.wind_ms))
		sources[String(rec.state.weather.get("wind_source", ""))] = true)
	_check("wind: an episode whose wind was not measured (-999.0) never shows a -999 wind; the source is labelled (%s)" % ", ".join(PackedStringArray(sources.keys())),
		float(lowest_wind[0]) > 0.0 and sources.has("archive background wind (not measured for this episode)") and String(_first_event(ws).get("episode_id", "")) == "fx_minor" and not bool(_first_event(ws).get("wind_measured", true)), "lowest %f" % float(lowest_wind[0]))
	var c := _run_recording(78, 12.0 * SOL, 0.1)
	_check("deterministic replay: another seed gives another sequence", c.queue != a.queue and c.taus != a.taus)
	var top := 0.0
	var jump := 0.0
	var taus: PackedFloat64Array = a.taus
	for i in taus.size():
		top = maxf(top, taus[i])
		if i > 0:
			jump = maxf(jump, absf(taus[i] - taus[i - 1]))
	_check("the opacity changes smoothly (largest step between 0.1 h ticks %.4f) and stays bounded (highest %.2f <= %.1f)" % [jump, top, WeatherConfig.new().max_tau],
		jump < 0.05 and top <= WeatherConfig.new().max_tau and top > 0.8, "%f %f" % [jump, top])


func _restore(d: Dictionary, clock_d: Dictionary) -> SessionService:
	var ev := GameEvents.new()
	_event_nodes.append(ev)
	var s := SessionService.new(GameConfig.new(), GameBalance.new(), ev)
	var st := ColonyState.from_dict(d)
	s.begin(st, SolClock.from_dict(clock_d))
	s.outside_test = func(p: Vector3) -> bool: return _zones.zone_at_world(p) == ColonyZones.EXTERIOR
	return s


## The save's own JSON round trip (SaveService writes full-precision JSON).
func _saved(s: SessionService) -> Array:
	s.sync_rng_to_state()
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.state.to_dict(), "", true, true))
	var c: Dictionary = JSON.parse_string(JSON.stringify(s.clock.to_dict(), "", true, true))
	return [d, c]


func _diff(ta: PackedFloat64Array, tb: PackedFloat64Array, wa: Dictionary, wb: Dictionary) -> String:
	var out := ""
	for i in mini(ta.size(), tb.size()):
		if ta[i] != tb[i]:
			out += "first tau difference at tick %d: %.12f vs %.12f; " % [i, ta[i], tb[i]]
			break
	var ja: Dictionary = JSON.parse_string(_json(wa))
	var jb: Dictionary = JSON.parse_string(_json(wb))
	for k: String in ja:
		if _json(ja[k]) != _json(jb.get(k)):
			out += "weather.%s: %s vs %s; " % [k, _json(ja[k]).left(300), _json(jb.get(k)).left(300)]
	return out


func _test_save_reload_mid_storm() -> void:
	_use(FIXTURE, "boot")
	var a := _session(91)
	_clean_all(a)
	var in_storm := _until(a, func() -> bool:
		var act: Dictionary = a.state.weather.active
		return not act.is_empty() and a.state.sim_hours > float(act.at_hours) + 3.0, 12.0 * SOL, 0.1)
	var saved := _saved(a)
	var b := _restore(saved[0], saved[1])
	var ta := PackedFloat64Array()
	var tb := PackedFloat64Array()
	_hours(a, 2.0 * SOL, 0.1, func(_t: float) -> void: ta.append(a.state.dust_tau))
	_hours(b, 2.0 * SOL, 0.1, func(_t: float) -> void: tb.append(b.state.dust_tau))
	# a second load of the same save must be bit-identical to the first (the restore itself is deterministic)
	var c := _restore(JSON.parse_string(JSON.stringify(saved[0], "", true, true)), saved[1])
	var tc := PackedFloat64Array()
	_hours(c, 2.0 * SOL, 0.1, func(_t: float) -> void: tc.append(c.state.dust_tau))
	var worst := 0.0
	for i in mini(ta.size(), tb.size()):
		worst = maxf(worst, absf(ta[i] - tb[i]))
	var discrete := ["active", "history", "rng_seed", "rng_state", "generated", "phase", "warning", "event_id", "episode_id", "taught_at_hours", "condition_at_hours", "last_end_hours"]
	var same := true
	for k: String in discrete:
		same = same and _json(a.state.weather.get(k)) == _json(b.state.weather.get(k))
	_info("save -> reload: largest opacity difference from the run that never saved %s over %d ticks (Godot's JSON reads a few numbers back to the last bit, see SaveService)" % [String.num_scientific(worst), ta.size()])
	_check("save -> reload mid-storm continues identically: the same storm, queue, events and random state; opacity on every tick for 2 sols equal to the unsaved run within 1e-9 and bit-identical between two loads",
		in_storm and ta.size() == tb.size() and worst < 1e-9 and same and _json(a.state.weather_queue) == _json(b.state.weather_queue) and tb == tc
		and absf(a.state.store(&"battery_kwh") - b.state.store(&"battery_kwh")) < 1e-6, "storm %s, %s" % [in_storm, _diff(ta, tb, a.state.weather, b.state.weather)])


func _test_events_and_late_join() -> void:
	_use(FIXTURE, "boot")
	var s := _session(91)
	var log: Array = []
	s.events.weather_changed.connect(func(e: Dictionary) -> void: log.append([String(e.type), s.state.sim_hours, String(e.event_id)]))
	s.events.system_alert.connect(func(id: StringName, level: StringName, text: String) -> void:
		if id == WeatherSystem.ALERT_ID:
			log.append(["alert", s.state.sim_hours, String(level), text]))
	_clean_all(s)
	_until(s, func() -> bool:
		var act: Dictionary = s.state.weather.active
		return not act.is_empty() and s.state.sim_hours > float(act.at_hours) + 5.0, 12.0 * SOL, 0.1)
	var replica := ColonyState.from_dict(s.state.to_dict())
	var client := ColonyState.new_game(GameBalance.new(), 0)
	client.assign_from(JSON.parse_string(JSON.stringify(s.state.to_dict(), "", true, true)))
	_check("late join: a ColonyState.from_dict(to_dict()) replica (and a client's assign_from) has the same weather, queue, snapshot id and opacity",
		_json(replica.weather) == _json(s.state.weather) and _json(replica.weather_queue) == _json(s.state.weather_queue) and replica.data_snapshot_id == s.state.data_snapshot_id
		and replica.dust_tau == s.state.dust_tau and _json(client.weather) == _json(s.state.weather) and client.data_snapshot_id == s.state.data_snapshot_id)
	_until(s, func() -> bool: return (s.state.weather.history as Array).size() >= 2, 12.0 * SOL, 0.1)
	var kinds: Array = []
	for entry: Array in log:
		kinds.append(String(entry[0]))
	var order_ok := true
	for i in kinds.size():
		if kinds[i] == "start":
			# each start follows its own warning: the system_alert, then weather_changed "warning", same event id
			order_ok = order_ok and i >= 2 and kinds[i - 2] == "alert" and kinds[i - 1] == "warning" and String(log[i - 1][2]) == String(log[i][2])
	_check("events: a system_alert warning ahead of each event, then weather_changed start, peak and end (%s)" % ", ".join(kinds.slice(0, 10)),
		kinds.count("start") >= 2 and kinds.count("peak") >= 2 and kinds.count("end") >= 2 and kinds.count("alert") >= kinds.count("start") and kinds.count("warning") >= kinds.count("start")
		and kinds.find("alert") < kinds.find("start") and kinds.find("start") < kinds.find("peak") and kinds.find("peak") < kinds.find("end") and order_ok, str(kinds))
	var text := ""
	for entry: Array in log:
		if String(entry[0]) == "alert":
			text = String(entry[3])
			break
	_check("the warning says: archive observations from Jezero, played faster; not a forecast for this colony; walk back; clean the panels",
		text.contains("Archive observations from Jezero, played faster") and text.contains("Not a forecast for this colony") and text.contains("walk back") and text.contains("clean the panels"), text)


# ---------------------------------------------------------------- warning margin

func _test_warning_margin() -> void:
	_use(FIXTURE, "boot")
	var cfg := WeatherConfig.new()
	var routes := ReturnRoutes.shared()
	var all_ok := true
	var lines := PackedStringArray()
	for k in 2 * TEST_POINTS.size():
		var i := k % TEST_POINTS.size()
		var p := TEST_POINTS[i]
		var s := _session(200 + k)
		var system := _ws(s)
		system.session = s                     # the real sol length: 20 real minutes, then the fastest, 5
		s.clock.sol_minutes = 20.0 if k < TEST_POINTS.size() else 5.0
		_clean_all(s)
		var c := s.state.character(&"crew_1")
		c.suit_on = true
		_until(s, func() -> bool: return float(s.state.weather_queue[0].at_hours) >= 0.0, 3.0 * SOL, 0.25)
		# walk out to the test point (the host learns it from the player's position report)
		s.report_position(1, &"crew_1", p, 0.0)
		var warned := _until(s, func() -> bool:
			c.suit_charge = 100.0
			return not (s.state.weather.warning as Dictionary).is_empty(), 3.0 * SOL, 0.1)
		var wn: Dictionary = s.state.weather.warning
		var hps := s.clock.hours_per_real_second()
		var walk_s := routes.return_seconds(p, system.walk_speed_mps)
		var needed_h := cfg.return_margin * walk_s * hps
		var lead_h := float(wn.get("lead_hours", 0.0))
		var lead_s := lead_h / hps
		lines.append("sol %d min, point %s: outside %s, walk home %.0f m = %.1f s, needed %.1f x %.1f s = %.1f s (%.2f game h), warning lead %.2f game h = %.0f real s (margin %.1f x)" % [
			roundi(s.clock.sol_minutes), p, c.outside, routes.return_metres(p), walk_s, cfg.return_margin, walk_s, cfg.return_margin * walk_s, needed_h, lead_h, lead_s, lead_s / maxf(walk_s, 1e-6)])
		all_ok = all_ok and warned and c.outside and walk_s > 5.0 and lead_h >= needed_h - 1e-9 and lead_h >= cfg.min_warning_hours - 1e-9 \
			and float(wn.return_seconds) >= walk_s - 1e-6
	for line in lines:
		_info("warning margin: " + line)
	_check("warning lead >= margin x walking time home along a real route, at 3 outdoor test points (20-minute and 5-minute sols)", all_ok, "\n  ".join(lines))
	# a far walker makes the warning come earlier (the lead follows the longest current return); no session wired =
	# the fastest allowed sol is assumed
	var s := _session(210)
	var system := _ws(s)
	_hours(s, 0.1, 0.1)
	var near := system.lead_hours_for(system.longest_return_seconds(s.state))
	s.report_position(1, &"crew_1", Vector3(-90.0, 0.0, 90.0), 0.0)
	var far := system.lead_hours_for(system.longest_return_seconds(s.state))
	_info("lead with nobody outside (the farthest sun tracker counts): %.2f game h; with crew_1 at (-90, 0, 90): %.2f game h" % [near, far])
	_check("warning lead follows the longest current outdoor return (a far walker needs a longer warning)", far > near and near >= cfg.min_warning_hours, "%f %f" % [near, far])


# ---------------------------------------------------------------- seeds and recovery

func _test_seed_spread_and_recovery() -> void:
	_use(FIXTURE, "boot")
	var cfg := WeatherConfig.new()
	var gaps: Array = []
	var first_gaps: Array = []
	var durations: Array = []
	var severities: Array = []
	var peaks: Array = []
	var first_starts: Array = []
	var counts: Array = []
	var first_minor := true
	var recover_ok := true
	var downs_total := 0
	var control_downs := 0
	var lowest := INF
	var below_detail := PackedStringArray()
	var recovery_seen: Array = []
	var reserve := cfg.battery_reserve_kwh
	var control_lowest := [INF]
	var hours_outside_events := 0.0
	var hours_control := 0.0
	for seed_value in range(1, 21):
		# control: the same colony and the same one cleaning round with the weather switched off (constant default sky)
		var control := _session(seed_value)
		_ws(control).enabled = false
		_clean_all(control)
		var control_below := {}
		control_downs += _hours(control, 20.0 * SOL, 0.2, func(_t: float) -> void:
			control_lowest[0] = minf(float(control_lowest[0]), control.state.store(&"battery_kwh"))
			if control.state.store(&"battery_kwh") < reserve:
				control_below[roundi(control.state.sim_hours * 5.0)] = true)
		hours_control += 0.2 * float(control_below.size())
		var s := _session(seed_value)
		_clean_all(s)
		var below_start := [-1.0]
		var stretches: Array = []
		var low := [INF]
		var downs := _hours(s, 20.0 * SOL, 0.2, func(_t: float) -> void:
			var b := s.state.store(&"battery_kwh")
			low[0] = minf(float(low[0]), b)
			if b < reserve and float(below_start[0]) < 0.0:
				below_start[0] = s.state.sim_hours
			elif b >= reserve and float(below_start[0]) >= 0.0:
				stretches.append([float(below_start[0]), s.state.sim_hours])
				below_start[0] = -1.0)
		if float(below_start[0]) >= 0.0:
			stretches.append([float(below_start[0]), s.state.sim_hours])
		downs_total += downs
		lowest = minf(lowest, float(low[0]))
		var w := s.state.weather
		var history: Array = w.history
		counts.append(history.size())
		var prev_end := float(w.condition_at_hours)
		for i in history.size():
			var h: Dictionary = history[i]
			var gap := float(h.at_hours) - prev_end
			if i == 0:
				first_gaps.append(gap)
				first_starts.append(float(h.at_hours) / SOL)
				first_minor = first_minor and String(h.episode_id) == "fx_minor" and float(h.severity) <= cfg.minor_severity_max + 1e-9 and float(h.at_hours) >= cfg.teach_min_sols * SOL
			else:
				gaps.append(gap / SOL)
				recover_ok = recover_ok and gap >= cfg.recovery_hours_min - 1e-6
			durations.append(float(h.duration_hours) / SOL)
			severities.append(float(h.severity))
			peaks.append(float(h.peak_tau))
			recovery_seen.append(float(h.recovery_hours))
			prev_end = float(h.at_hours) + float(h.duration_hours)
		# every stretch below the life-support reserve that the weather caused lies inside an event and is not longer
		# than it. A stretch outside every event is the colony's own (uncleaned panels, broken cleaner): the control
		# without weather must be below the reserve then too.
		var windows: Array = history.duplicate()
		if not (w.active as Dictionary).is_empty():
			windows.append(w.active)            # the event still running when the 20 sols end
		for st: Array in stretches:
			var inside := false
			for h: Dictionary in windows:
				var a := float(h.at_hours)
				var e := a + float(h.duration_hours)
				if float(st[0]) >= a and float(st[1]) - float(st[0]) <= float(h.duration_hours) and float(st[0]) <= e:
					inside = true
			if inside:
				continue
			hours_outside_events += float(st[1]) - float(st[0])
			var baseline := false
			for k in range(roundi(float(st[0]) * 5.0) - 5, roundi(float(st[1]) * 5.0) + 6):
				baseline = baseline or control_below.has(k)
			if not baseline:
				recover_ok = false
				below_detail.append("seed %d below reserve %.1f..%.1f h outside any event, control above it" % [seed_value, st[0], st[1]])
	_info("seed spread over 20 seeds, 20 sols each, one cleaning round at the start: events per run %s" % _stats(counts))
	_info("  first event start (sol): %s; first gap after the teaching condition (game h): %s" % [_stats(first_starts), _stats(first_gaps)])
	_info("  later gaps (sols, end to next start): %s" % _stats(gaps))
	_info("  durations (sols): %s" % _stats(durations))
	_info("  severities (share of the observed opacity rise): %s" % _stats(severities))
	_info("  darkest sky (tau): %s" % _stats(peaks))
	_info("  recovery intervals after events (game h): %s" % _stats(recovery_seen))
	_info("  lowest battery in any run: %.1f kWh with weather, %.1f kWh in the controls without weather (life-support reserve %.0f kWh)" % [lowest, float(control_lowest[0]), cfg.battery_reserve_kwh])
	_info("  hours below the reserve outside any event, all 20 seeds: %.1f h with weather; %.1f h in the controls without weather" % [hours_outside_events, hours_control])
	_check("different seeds give different gaps (%d distinct), durations (%d), severities (%d) and first gaps (%d) over 20 seeds" % [_distinct(gaps), _distinct(durations), _distinct(severities), _distinct(first_gaps)],
		_distinct(gaps) >= 15 and _distinct(durations) >= 15 and _distinct(severities) >= 15 and _distinct(first_gaps) >= 15)
	_check("no fixed interval: later gaps span at least 1.5 sols across seeds", gaps.max() - gaps.min() >= 1.5 if not gaps.is_empty() else false, _stats(gaps))
	_check("first event in every seed: minor, the smallest episode, after the teaching condition and the 2-sol mark", first_minor and first_starts.size() == 20, _stats(first_starts))
	_check("escalation: later events get stronger on average than the first (mean severity of 3rd+ events above the first's)", _later_stronger(), "")
	_check("escalation stays recoverable over 20 sols with only one cleaning round: nobody reaches zero health (weather runs %d, control runs %d), events are spaced by the recovery interval, and the battery is below the %.0f kWh reserve because of the weather only inside an event and never longer than it" % [downs_total, control_downs, cfg.battery_reserve_kwh],
		downs_total == 0 and control_downs == 0 and recover_ok, "\n  ".join(below_detail))
	_check("recovery intervals vary with readiness (%s)" % _stats(recovery_seen), _distinct(recovery_seen, 0.1) >= 5)
	# the same 20 seeds in a maintained colony (panels cleaned, the electrical specialist repairs the cleaner at once)
	var m_counts: Array = []
	var m_gaps: Array = []
	var m_sev: Array = []
	var m_peak: Array = []
	var m_dur: Array = []
	var m_low := [INF]
	var m_downs := 0
	for seed_value in range(1, 21):
		var s := _session(seed_value)
		_clean_all(s)
		var c := s.state.character(&"crew_1")
		c.position = CharacterState._v3(s.state.stations["sf_solar_tracker"].position)
		s.request(&"repair_cleaner", &"sf_solar_tracker", {}, 1)
		c.position = c.hub_spot
		m_downs += _hours(s, 20.0 * SOL, 0.2, func(_t: float) -> void: m_low[0] = minf(float(m_low[0]), s.state.store(&"battery_kwh")))
		var history: Array = s.state.weather.history
		m_counts.append(history.size())
		for i in history.size():
			var h: Dictionary = history[i]
			if i > 0:
				var p: Dictionary = history[i - 1]
				m_gaps.append((float(h.at_hours) - float(p.at_hours) - float(p.duration_hours)) / SOL)
			m_sev.append(float(h.severity))
			m_peak.append(float(h.peak_tau))
			m_dur.append(float(h.duration_hours) / SOL)
	_info("maintained colony (cleaner repaired), 20 seeds x 20 sols: events per run %s; gaps (sols) %s; durations (sols) %s; severities %s; darkest sky (tau) %s; lowest battery %.0f kWh" % [
		_stats(m_counts), _stats(m_gaps), _stats(m_dur), _stats(m_sev), _stats(m_peak), float(m_low[0])])
	_check("a maintained colony gets the full escalation without harm (more events, stronger later ones, nobody down, battery above the reserve)",
		m_downs == 0 and float(m_low[0]) >= cfg.battery_reserve_kwh and (m_sev.max() if not m_sev.is_empty() else 0.0) > 0.8 and _distinct(m_gaps) >= 15, "downs %d low %.0f" % [m_downs, float(m_low[0])])



func _later_stronger() -> bool:
	# re-run a few seeds and compare the mean planned severity by event index
	var first := 0.0
	var later := 0.0
	var n_first := 0
	var n_later := 0
	for seed_value in range(1, 21):
		var s := _session(seed_value)
		var system := _ws(s)
		system._bind(s.state, s.balance)
		system._fill_queue(s.state.weather, s.state)
		for k in 6:
			if s.state.weather_queue.is_empty():
				break
			var e: Dictionary = s.state.weather_queue.pop_front()
			if int(e.index) == 0:
				first += float(e.severity_planned)
				n_first += 1
			elif int(e.index) >= 2:
				later += float(e.severity_planned)
				n_later += 1
			system._fill_queue(s.state.weather, s.state)
	return n_first > 0 and n_later > 0 and later / n_later > first / n_first + 0.2


# ---------------------------------------------------------------- refresh

func _ok_csv(scale: float) -> String:
	var text := "sol,tau,tau_flag\n"
	for i in 70:
		text += "%.1f,%.3f,0\n" % [300.0 + 0.5 * i, 0.56 + scale * 0.001 * i]
	return text


func _resp(status: int, body: String = "", headers: Dictionary = {}, error: String = "") -> Dictionary:
	return {"status": status, "error": error, "body": body.to_utf8_buffer(), "headers": headers}


func _test_refresh() -> void:
	var root := _use(FIXTURE, "refresh")
	var current := root.path_join("current")
	var fake := FakeTransport.new()
	var refresh := WeatherRefresh.new()
	refresh.transport = fake
	refresh.now_func = func() -> float: return _now
	# a game running before any refresh
	var g1 := _session(91)
	var g1_twin := _session(91)
	_clean_all(g1)
	_clean_all(g1_twin)
	var storm := _until_pair(g1, g1_twin, func() -> bool:
		var act: Dictionary = g1.state.weather.active
		return not act.is_empty() and g1.state.sim_hours > float(act.at_hours) + 3.0, 12.0 * SOL, 0.1)
	var pinned := g1.state.data_snapshot_id

	# 304: up to date, conditional headers sent
	fake.responses = [_resp(304)]
	refresh.check_now()
	var req: Dictionary = fake.requests[0]
	var hdrs: PackedStringArray = req.headers
	_check("refresh: a conditional GET with If-None-Match and If-Modified-Since from the manifest, a timeout and a size cap",
		String(req.url) == "https://example.invalid/fixture/meda_tau.csv" and "\n".join(hdrs).contains("If-None-Match: \"fx-fx_meda_tau-1\"")
		and "\n".join(hdrs).contains("If-Modified-Since: Sat, 01 Jan 2022") and int(req.max_bytes) == 200000 and float(req.timeout_s) == 20.0, str(req))
	var st := refresh.status()
	_check("refresh: 304 = up to date, not a failure; the next check is in 1 hour", bool(st.last_ok) and String(st.last_result).begins_with("Up to date")
		and refresh.failures == 0 and absf(refresh.next_check_at - (_now + 3600.0)) < 1e-6 and not DirAccess.dir_exists_absolute(current), str(st))
	fake.requests.clear()
	refresh.tick(_now + 1800.0)
	_check("refresh: no check before it is due", fake.requests.is_empty())

	# 200 with a new product file: complete new bundle, validated, swapped in atomically
	_now += 3600.0
	fake.responses = [_resp(200, _ok_csv(2.0), {"etag": "\"fx-tau-2\"", "last-modified": "Mon, 01 Jan 2024 00:00:00 GMT"})]
	refresh.tick(_now)
	var cache := WeatherArchive.load_dir(current, "cache")
	var tau_p := cache.product("fx_meda_tau")
	_check("refresh: 200 with a new product -> a complete validated bundle swapped in as the cache (product replaced, sha256 recomputed, episodes kept, product marked updated)",
		cache.ok and String(tau_p.etag) == "\"fx-tau-2\"" and tau_p.has("updated_by_refresh") and int(cache.product_stats.fx_meda_tau.rows) == 70
		and String(cache.manifest.episodes_sha256) == String(WeatherArchive.load_dir(FIXTURE).manifest.episodes_sha256)
		and WeatherArchive.active().source == "cache" and not DirAccess.dir_exists_absolute(WeatherArchive.incoming_dir()), "%s %s" % [cache.problems, refresh.status().last_result])
	_check("refresh: the status says the new data is used from the next new game or load", String(refresh.status().last_result).contains("next new game or load"), String(refresh.status().last_result))

	# the running game keeps its data and its storm: same as a twin that never saw the refresh
	var t1 := PackedFloat64Array()
	var t2 := PackedFloat64Array()
	var active_before := _json(g1.state.weather.active)
	_hours(g1, 1.0 * SOL, 0.1, func(_t: float) -> void: t1.append(g1.state.dust_tau))
	_hours(g1_twin, 1.0 * SOL, 0.1, func(_t: float) -> void: t2.append(g1_twin.state.dust_tau))
	_check("a refresh mid-storm does not change the running storm: the game keeps its pinned snapshot and runs exactly like a twin without the refresh",
		storm and active_before != "{}" and t1 == t2 and g1.state.data_snapshot_id == pinned and _json(g1.state.weather) == _json(g1_twin.state.weather)
		and _ws(g1).archive.snapshot_id() == pinned, "storm %s" % storm)
	var g2 := _session(91)
	_hours(g2, 0.5, 0.25)
	_check("a new game after the refresh uses the new data (%s)" % g2.state.data_snapshot_id, g2.state.data_snapshot_id == WeatherArchive.active().snapshot_id() and g2.state.data_snapshot_id != pinned)
	var saved := _saved(g1)
	var loaded := _restore(saved[0], saved[1])
	var queue_before := _json(saved[0].weather_queue)
	_hours(loaded, 0.1, 0.1)
	var adopted: Dictionary = loaded.state.weather.get("adopted", {})
	_check("a load after the refresh adopts the new data for new events, and keeps every issued event and the running storm",
		loaded.state.data_snapshot_id == WeatherArchive.active().snapshot_id() and String(adopted.get("from", "")) == pinned
		and _json(loaded.state.weather.active) == _json(saved[0].weather.active) and queue_before == _json(saved[0].weather_queue), str(adopted))

	# a second update: the first refresh becomes the backup
	_now += 3600.0
	fake.responses = [_resp(200, _ok_csv(3.0), {"etag": "\"fx-tau-3\""})]
	refresh.tick(_now)
	var prev := WeatherArchive.load_dir(WeatherArchive.previous_dir(), "cache")
	_check("refresh: the previous cache is kept as a backup when a newer one is swapped in",
		prev.ok and String(prev.product("fx_meda_tau").etag) == "\"fx-tau-2\"" and String(WeatherArchive.load_dir(current, "cache").product("fx_meda_tau").etag) == "\"fx-tau-3\"")

	# the refresh entry points at the archive's ORIGINAL file (its transform is in Python): a 200 only means
	# "an update was published": marked, the player told, the validated bundle kept, its ETag asked for next time
	_now += 3600.0
	var before_original := _tree_hash(current)
	var snapshot_before := WeatherArchive.active().snapshot_id()
	fake.requests.clear()
	fake.responses = [_resp(200, "PDS4 label of the original archive file\n<Product_Observational> ... </Product_Observational>\n",
		{"etag": "\"orig-7\"", "last-modified": "Tue, 02 Jan 2024 00:00:00 GMT"})]
	refresh.tick(_now)
	var stp := refresh.status()
	var marked: Dictionary = (stp.get("published_updates", {}) as Dictionary).get("fx_meda_tau", {})
	_check("refresh: a 200 with the archive's original file (not a bundle CSV) is marked as 'update published', not a failure; the validated bundle stays in use",
		bool(stp.last_ok) and refresh.failures == 0 and String(stp.last_result).contains("published an update") and String(marked.get("etag", "")) == "\"orig-7\""
		and _tree_hash(current) == before_original and WeatherArchive.active().snapshot_id() == snapshot_before, "%s %s" % [stp.last_result, marked])
	_now = refresh.next_check_at
	fake.requests.clear()
	fake.responses = [_resp(304)]
	refresh.tick(_now)
	_check("refresh: the next check asks with the published file's ETag, so the same file is not downloaded again",
		not fake.requests.is_empty() and "\n".join(fake.requests[0].headers as PackedStringArray).contains("If-None-Match: \"orig-7\""), str(fake.requests))

	# failures keep the cache and back off 1, 2, 4 ... minutes
	var keep := _tree_hash(current)
	var failures := [
		["HTTP 500", _resp(500)],
		["timeout", _resp(0, "", {}, "timeout")],
		["oversize", _resp(200, "x".repeat(200001))],
		["interrupted download (partial file)", _resp(200, _ok_csv(4.0).left(300), {"content-length": "2000"})],
		["invalid flags", _resp(200, "sol,tau,tau_flag\n300.0,0.56,0\n300.5,0.57,2.5\n")],
		["invalid value (opacity 75, outside the plausible range for unit 1)", _resp(200, "sol,tau,tau_flag\n300.0,0.56,0\n300.5,75.0,0\n")],
		["time going backwards", _resp(200, "sol,tau,tau_flag\n301.0,0.56,0\n300.5,0.57,0\n")],
		["no connection", _resp(0, "", {}, "connection")],
	]
	var waits: Array = []
	var untouched := true
	var words := PackedStringArray()
	for f: Array in failures:
		_now = refresh.next_check_at
		fake.responses = [f[1]]
		refresh.tick(_now)
		waits.append(roundi((refresh.next_check_at - _now) / 60.0))
		untouched = untouched and _tree_hash(current) == keep and not DirAccess.dir_exists_absolute(WeatherArchive.incoming_dir())
		words.append("%s -> %s" % [f[0], refresh.status().last_result])
	_info("refresh failures: " + " | ".join(words))
	_check("refresh: HTTP 500, timeout, oversize, interrupted download, invalid flags/values/time and no connection all leave the cache untouched (an unrecognised file is an original archive file: marked as published, tested above)", untouched and refresh.failures == failures.size(), "\n  ".join(words))
	_check("refresh: retries back off 1, 2, 4, 8, 16, 32, 60, 60 minutes (%s)" % str(waits), waits == [1, 2, 4, 8, 16, 32, 60, 60], str(waits))
	_check("refresh: a rejected download names the reason and keeps the last valid data", String(words[4]).contains("flag") and String(words[4]).contains("last valid data is kept"), words[4])
	_now = refresh.next_check_at
	fake.responses = [_resp(304)]
	refresh.tick(_now)
	_check("refresh: the next good answer resets the backoff", refresh.failures == 0 and bool(refresh.status().last_ok))
	var on_disk := WeatherRefresh.read_status()
	_check("refresh: the status (observation period, last check, last result) is saved for the screens", on_disk.has("last_check_utc") and on_disk.has("observation_period") and String(on_disk.last_result).begins_with("Up to date"), str(on_disk))
	refresh.free()
	_use(FIXTURE, "boot")


# ---------------------------------------------------------------- panel and presenter

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _test_panel_and_presenter() -> void:
	_use(FIXTURE, "panel")
	var services := GameServices.new()
	services.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/weather"), "colony", 2)
	root.add_child(services)
	services.start_new_game(1)
	await _frames()
	services.set_process(false)
	services.session.advance(1.0 / services.config.sim_tick_hz)
	var st := services.state()
	var at := CharacterState._v3(st.stations["cm_comms_console"].position) + Vector3(1.5, 0.0, 0.0)
	st.stations["weather_screen_test"] = {"kind": "weather", "zone": "Command Room", "position": [at.x, at.y, at.z], "specialty": ""}
	services.local_character().position = at
	# a real warning in the state, as the host would have issued it
	st.weather.warning = {"event_id": "wx_1", "issued_at_hours": st.sim_hours, "starts_at_hours": st.sim_hours + 6.0, "lead_hours": 6.0, "return_seconds": 31.0,
		"margin": 2.0, "severity": 0.3, "text": WeatherSystem.warning_text({"lead_hours": 6.0}, 31.0, services.clock().hours_per_real_second()), "acknowledged_by": []}
	var via_catalog := StationPanels.for_station(&"weather_screen_test", services) as StationPanel
	var catalog_script := String(via_catalog.get_script().resource_path)
	via_catalog.free()
	if not catalog_script.ends_with("weather_station_panel.gd"):
		_info("StationPanels.for_station returned %s for kind 'weather': its `match kind if panel == null else \"\"` falls into the `_:` branch and replaces every custom panel with a plain StationPanel (not a weather-worker file; integrator fix). The panel below is built exactly as for_station intends." % catalog_script)
	# built as StationPanels.for_station intends (custom script for the kind, ids and meta set, then setup)
	var panel := (load("res://scripts/ui/stations/weather_station_panel.gd") as Script).new() as StationPanel
	panel.station_id = &"weather_screen_test"
	panel.kind = "weather"
	panel.set_meta(&"station_surface", true)
	panel.set_meta(&"station_id", &"weather_screen_test")
	panel.setup(services)
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames()
	panel.refresh()
	var labels := "\n".join(panel.call("label_texts") as PackedStringArray)
	_check("weather screen: the panel for stations of kind weather (scripts/ui/stations/weather_station_panel.gd) shows both labels ('archive observations from Jezero, played faster', 'not a forecast for this colony')",
		panel.get_script().resource_path.ends_with("weather_station_panel.gd") and labels.contains("Archive observations from Jezero, played faster") and labels.contains("Not a forecast for this colony"), labels)
	_check("weather screen: active data (site, archive dates, status, data id), opacity and solar effect in words, and the warning",
		panel.reading_text(&"site") == "Jezero crater" and panel.reading_text(&"dates").begins_with("2022-01-01 to 2022-01-31") and panel.reading_text(&"status").begins_with("validated")
		and panel.reading_text(&"snapshot") == "fixture-weather-w-v1@1" and panel.reading_text(&"opacity").begins_with("τ ") and panel.reading_text(&"sunlight").contains("% of usual")
		and String(panel.call("warning_text")).contains("Dust warning"),
		"%s | %s | %s | %s | %s" % [panel.reading_text(&"site"), panel.reading_text(&"dates"), panel.reading_text(&"status"), panel.reading_text(&"opacity"), panel.call("warning_text")])
	var button := panel.call("acknowledge_button") as Button
	button.pressed.emit()
	await _frames()
	_check("weather screen: 'I heard the warning' asks the host and every screen shows who heard it",
		(st.weather.warning.acknowledged_by as Array).has("crew_1") and not button.visible, str(st.weather.warning))
	var refused := services.session.request(&"acknowledge_weather_warning", &"", {}, 1)
	st.weather.warning = {}
	refused = services.session.request(&"acknowledge_weather_warning", &"", {}, 1)
	_check("acknowledge_weather_warning is refused when there is no warning", not refused.ok and refused.reason == &"missing_prerequisite", str(refused.reason))
	st.weather.warning = {"event_id": "wx_1", "starts_at_hours": st.sim_hours + 6.0, "lead_hours": 6.0,
		"text": WeatherSystem.warning_text({"lead_hours": 6.0}, 31.0, services.clock().hours_per_real_second()), "acknowledged_by": ["crew_1"]}
	# layout at the three sizes (as test_p07_panels)
	var stretch := root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var layout := PackedStringArray()
	var focus := PackedStringArray()
	for s: Array in [[Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 1.0], [Vector2i(1280, 720), 1.5]]:
		root.size = s[0]
		UiTheme.apply_text_scale(float(s[1]))
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await _frames(2)
		panel.refresh()
		await _frames(2)
		for line in UiLayoutCheck.problems(panel, Vector2(s[0])):
			layout.append("%s text %s: %s" % [s[0], s[1], line])
		var min_size := panel.get_combined_minimum_size()
		if min_size.x > float(s[0].x) or min_size.y > float(s[0].y):
			layout.append("%s text %s: minimum size %s is bigger than the screen" % [s[0], s[1], min_size])
		for line in UiLayoutCheck.focus_problems(panel):
			focus.append("%s text %s: %s" % [s[0], s[1], line])
	UiTheme.apply_text_scale(1.0)
	root.size = Vector2i(1280, 720)
	root.content_scale_mode = stretch
	_check("weather screen passes layout at 1280x720, 1920x1080 and 1280x720 text 1.5", layout.is_empty(), "\n  ".join(layout))
	_check("weather screen: keyboard focus on every control", focus.is_empty() and not UiLayoutCheck.focusable(panel).is_empty(), "\n  ".join(focus))
	panel.queue_free()
	await process_frame

	# presenter on a small stand-in world: sun, sky and fog follow the opacity, bounded
	var world := Node3D.new()
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = Environment.new()
	we.environment.background_energy_multiplier = 1.0
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.0
	world.add_child(sun)
	root.add_child(world)
	var presenter := WeatherPresenter.new()
	root.add_child(presenter)
	presenter.setup(world, services)
	presenter.apply_sky(0.5)
	var clear_sun := sun.light_energy
	presenter.apply_sky(2.0)
	var dusty_sun := sun.light_energy
	var dusty_fog := we.environment.fog_enabled and we.environment.fog_density > 0.0
	sun.light_energy = 0.5               # ZoneLighting dims the sun for the evening
	presenter.apply_sky(2.0)
	var evening := sun.light_energy
	presenter.apply_sky(50.0)
	var darkest := sun.light_energy
	var cfg := WeatherConfig.new()
	presenter.apply_sky(0.5)
	_check("presenter: sun and sky dim with the opacity (sun %.2f -> %.2f at tau 2), fog thickens, all bounded (never below %.0f %%, fog <= %.3f), and it scales whatever ZoneLighting set" % [clear_sun, dusty_sun, cfg.sun_min_share * 100.0, cfg.fog_density_max],
		absf(clear_sun - 1.0) < 1e-6 and absf(dusty_sun - exp(-0.6 * 1.5)) < 1e-6 and dusty_fog and absf(evening - 0.5 * exp(-0.6 * 1.5)) < 1e-6
		and absf(darkest - 0.5 * cfg.sun_min_share) < 1e-6 and presenter.fog_density <= cfg.fog_density_max and absf(sun.light_energy - 0.5) < 1e-6 and not we.environment.fog_enabled,
		"%f %f %f %f %f" % [clear_sun, dusty_sun, evening, darkest, sun.light_energy])
	var me := services.local_character()
	me.outside = true
	st.dust_tau = 2.0
	await _frames(3)
	var emitting := presenter.particles.emitting
	me.outside = false
	await _frames(2)
	_check("presenter: a bounded cloud of dust particles (%d at most) only around an outdoor player on a dusty day" % presenter.particles.amount,
		emitting and not presenter.particles.emitting and presenter.particles.amount <= cfg.dust_particles_max)
	_check("presenter: setup gives the session's WeatherSystem the session (warnings use the real sol length)", WeatherSystem.of_session(services.session).session == services.session)
	presenter.queue_free()
	world.queue_free()
	services.queue_free()
	await process_frame
