class_name WeatherArchive
extends RefCounted
## One weather data bundle (format "mars_colony_weather_bundle", schema 1; see SPEC_P09 "The bundle format"):
## archive observations from one landing site, the dust episodes derived from them, and the seasonal background.
## load_dir() validates a bundle folder and never crashes on bad data: the result has `ok` and a list of `problems`.
##
## Where bundles come from:
##   shipped  res://data/weather/bundle (verified, ships with the game)
##   cache    user://weather_cache/current (a validated refresh, see WeatherRefresh)
##   builtin  no bundle at all: a clearly labelled default with no archive data and a constant background opacity
## active() picks the newest valid one. A running game never changes its data: WeatherSystem pins a snapshot.
##
## These are archive observations from a real place (Jezero crater). They are never live weather and never a forecast
## for the fictional colony.

const FORMAT := "mars_colony_weather_bundle"
const SCHEMA := 1
const SHIPPED_DIR := "res://data/weather/bundle"
const CACHE_ROOT := "user://weather_cache"
const BUILTIN_ID := "builtin-default"
## Units a product column may use (and its units_ok must be drawn from). Anything else is rejected.
const KNOWN_UNITS: Array[String] = ["Pa", "hPa", "K", "m/s", "deg", "1", "sol", "s", "h", "W/m2", "%"]
const MANIFEST_FIELDS: Array[String] = ["format", "schema", "bundle_id", "built_utc", "products", "episodes_file", "episodes_sha256", "refresh"]
const PRODUCT_FIELDS: Array[String] = ["id", "kind", "file", "sha256", "bytes", "source_id", "pds_lid", "version", "mission", "instrument",
	"site", "lat", "lon", "observation_start_utc", "observation_end_utc", "sol_start", "sol_end", "ls_start", "ls_end", "columns",
	"units_ok", "missing_value", "quality", "license", "source_url", "etag", "last_modified", "retrieved_utc", "transform"]
## Fields that must not be empty text.
const PRODUCT_TEXT_REQUIRED: Array[String] = ["id", "kind", "file", "sha256", "site"]
const EPISODE_FIELDS: Array[String] = ["id", "source_product_ids", "observed", "duration_sols", "peak_tau", "tau_curve", "wind_ms_mean", "solar_factor_at_peak", "notes"]
const REFRESH_FIELDS: Array[String] = ["product_id", "url", "max_bytes", "timeout_s"]
## Coarse plausibility limits per unit [low, high] for data columns (flag columns are checked separately).
const UNIT_RANGES := {"Pa": [0.0, 3000.0], "hPa": [0.0, 30.0], "K": [100.0, 400.0], "m/s": [-150.0, 150.0], "deg": [-360.0, 720.0],
	"1": [-0.001, 50.0], "sol": [-1.0, 100000.0], "s": [0.0, 1.0e10], "h": [0.0, 1.0e7], "W/m2": [0.0, 2000.0], "%": [0.0, 100.0]}
## Products further apart than this (degrees of latitude or longitude) are not one place.
const SAME_SITE_DEG := 5.0

## Test hooks: other folders for the shipped bundle and the cache root ("" = the defaults).
static var shipped_dir_override := ""
static var cache_root_override := ""
static var _active: WeatherArchive

## True if the bundle passed every check.
var ok := false
## Fatal problems, in plain words; empty when ok.
var problems := PackedStringArray()
## Things worth knowing that do not make the data unusable (for example a peak that does not match its curve).
var notes := PackedStringArray()
## "shipped", "cache" or "builtin".
var source := ""
## Folder the bundle was read from ("" for the built-in default).
var dir := ""
var manifest := {}
## Episode dictionaries as in episodes.json.
var episodes: Array = []
## [[ls, tau], ...] sorted by ls.
var tau_by_ls: Array = []
## Product id -> {"rows": int, "time_column": String, "time_first": float, "time_last": float, "means": {column: mean}}.
var product_stats := {}


# ---------------------------------------------------------------- where bundles are

static func shipped_dir() -> String:
	return shipped_dir_override if shipped_dir_override != "" else SHIPPED_DIR


static func cache_root() -> String:
	return cache_root_override if cache_root_override != "" else CACHE_ROOT


static func current_dir() -> String:
	return cache_root().path_join("current")


static func previous_dir() -> String:
	return cache_root().path_join("previous")


static func incoming_dir() -> String:
	return cache_root().path_join("incoming")


## The data a new game or a load should use: the newest valid bundle (cached until invalidate()).
static func active() -> WeatherArchive:
	if _active == null:
		_active = best_on_disk()
	return _active


## Forgets the cached choice; the next active() looks at the disk again (after a refresh swapped the cache).
static func invalidate() -> void:
	_active = null


## Loads the shipped bundle and the cache and returns the newest valid one (never null).
static func best_on_disk() -> WeatherArchive:
	var shipped := load_dir(shipped_dir(), "shipped") if _dir_exists(shipped_dir()) else null
	var cache := load_dir(current_dir(), "cache") if _dir_exists(current_dir()) else null
	return choose(shipped, cache)


## The newer valid bundle of the two. A cache older than the shipped data (or built on an older shipped bundle) is
## ignored. Neither valid: the built-in default.
static func choose(shipped: WeatherArchive, cache: WeatherArchive) -> WeatherArchive:
	var s_ok := shipped != null and shipped.ok
	var c_ok := cache != null and cache.ok
	if c_ok and s_ok:
		var base := String(cache.manifest.get("base_built_utc", cache.built_utc()))
		if cache.built_utc() > shipped.built_utc() and base >= shipped.built_utc():
			return cache
		shipped.notes.append("A cached refresh (%s) is older than the shipped data and is not used." % cache.snapshot_id())
		return shipped
	if s_ok:
		if cache != null and not cache.ok:
			shipped.notes.append("The cached refresh is not valid and is not used: %s" % "; ".join(cache.problems))
		return shipped
	if c_ok:
		return cache
	var d := builtin_default()
	if shipped != null:
		d.notes.append("The shipped bundle is not valid: %s" % "; ".join(shipped.problems))
	return d


## No archive data at all: no episodes, a constant background opacity (the game's default sky). Clearly labelled.
static func builtin_default(tau: float = -1.0) -> WeatherArchive:
	var a := WeatherArchive.new()
	if tau < 0.0:
		tau = GameBalance.new().dust_tau_default
	a.ok = true
	a.source = "builtin"
	a.manifest = {"format": FORMAT, "schema": SCHEMA, "bundle_id": BUILTIN_ID, "built_utc": "", "version": "0", "products": [], "refresh": [],
		"label": "Built-in default: no archive data, constant background opacity (game default, not a NASA value)."}
	a.tau_by_ls = [[0.0, tau], [360.0, tau]]
	a.notes.append("No weather bundle was found: the game uses a constant sky and no dust events.")
	return a


# ---------------------------------------------------------------- facts about this bundle

func bundle_id() -> String:
	return String(manifest.get("bundle_id", ""))


func built_utc() -> String:
	return String(manifest.get("built_utc", ""))


func version() -> String:
	return String(manifest.get("version", built_utc()))


## The id saved with a game: bundle id + version.
func snapshot_id() -> String:
	return "%s@%s" % [bundle_id(), version()]


func is_builtin() -> bool:
	return source == "builtin"


func products() -> Array:
	return manifest.get("products", []) as Array


func product(id: String) -> Dictionary:
	for p: Dictionary in products():
		if String(p.get("id", "")) == id:
			return p
	return {}


func refresh_entries() -> Array:
	return manifest.get("refresh", []) as Array


## Site of the first product, or "" for the built-in default.
func site() -> String:
	var list := products()
	return String((list[0] as Dictionary).get("site", "")) if not list.is_empty() else ""


## {"start": UTC text, "end": UTC text, "sol_start", "sol_end", "ls_start", "ls_end"} over all products; empty without data.
## Ls is a season angle and may wrap through 0/360 (ls_start > ls_end): the period's ls_start is that of the product
## that starts first, its ls_end that of the product that ends last. Missing values (<= -900) are skipped.
func observation_period() -> Dictionary:
	var list := products()
	if list.is_empty():
		return {}
	var out := {"start": "", "end": "", "sol_start": INF, "sol_end": -INF, "ls_start": INF, "ls_end": -INF}
	for p: Dictionary in list:
		var s := String(p.get("observation_start_utc", ""))
		var e := String(p.get("observation_end_utc", ""))
		var ls0 := float(p.get("ls_start", -999.0))
		var ls1 := float(p.get("ls_end", -999.0))
		if s != "" and (out.start == "" or s < String(out.start)):
			out.start = s
			if not is_missing(ls0):
				out.ls_start = fposmod(ls0, 360.0)
		if e != "" and e > String(out.end):
			out.end = e
			if not is_missing(ls1):
				out.ls_end = fposmod(ls1, 360.0)
		if not is_missing(float(p.get("sol_start", -999.0))):
			out.sol_start = minf(float(out.sol_start), float(p.sol_start))
		if not is_missing(float(p.get("sol_end", -999.0))):
			out.sol_end = maxf(float(out.sol_end), float(p.sol_end))
	for k: String in ["sol_start", "sol_end", "ls_start", "ls_end"]:
		if not is_finite(float(out[k])):
			out[k] = -999.0
	return out


## True for the bundle's "not measured" marker (missing_value, -999.0) or anything below -900.
static func is_missing(v: float) -> bool:
	return v <= -900.0 or is_nan(v)


## "validated", "validated (refreshed)", "built-in default" or "not valid".
func validation_words() -> String:
	if not ok:
		return "not valid"
	match source:
		"builtin": return "built-in default (no archive data)"
		"cache": return "validated (refreshed copy)"
	return "validated (shipped with the game)"


## Seasonal background opacity at solar longitude `ls` (degrees), linear between the listed points, wrapping at 360.
func background_tau(ls: float) -> float:
	if tau_by_ls.is_empty():
		return GameBalance.new().dust_tau_default
	var x := fposmod(ls, 360.0)
	var n := tau_by_ls.size()
	if n == 1:
		return float(tau_by_ls[0][1])
	for i in n:
		var a: Array = tau_by_ls[i]
		var b: Array = tau_by_ls[(i + 1) % n]
		var la := float(a[0])
		var lb := float(b[0]) if i + 1 < n else float(b[0]) + 360.0
		var xx := x if x >= la else x + 360.0
		if xx >= la and xx <= lb:
			var t := 0.0 if lb - la < 1e-9 else (xx - la) / (lb - la)
			return lerpf(float(a[1]), float(b[1]), t)
	return float(tau_by_ls[0][1])


func episode(id: String) -> Dictionary:
	for e: Dictionary in episodes:
		if String(e.get("id", "")) == id:
			return e
	return {}


## Mean of the measured values (missing values skipped) of every column in `unit` of every product whose kind
## contains `kind` (for example "wind" and "m/s"), or `fallback` when nothing was measured.
func mean_of_kind(kind: String, fallback: float, unit: String = "") -> float:
	var total := 0.0
	var count := 0
	for p: Dictionary in products():
		if not String(p.get("kind", "")).contains(kind):
			continue
		var stats: Dictionary = product_stats.get(String(p.id), {})
		var columns: Dictionary = p.get("columns", {})
		for column: String in (stats.get("means", {}) as Dictionary):
			if unit != "" and String(columns.get(column, "")) != unit:
				continue
			total += float(stats.means[column])
			count += 1
	return total / float(count) if count > 0 else fallback


## Earliest Ls the products cover, or `fallback`.
func start_ls(fallback: float) -> float:
	var period := observation_period()
	if period.is_empty() or is_missing(float(period.ls_start)):
		return fallback
	return fposmod(float(period.ls_start), 360.0)


# ---------------------------------------------------------------- loading and validation

## Loads and validates the bundle in `path`. Never crashes; check `ok` and `problems`.
static func load_dir(path: String, p_source: String = "shipped") -> WeatherArchive:
	var a := WeatherArchive.new()
	a.source = p_source
	a.dir = path
	a._load()
	a.ok = a.problems.is_empty()
	return a


func _load() -> void:
	var manifest_path := dir.path_join("manifest.json")
	if not FileAccess.file_exists(manifest_path):
		problems.append("manifest.json is missing in %s" % dir)
		return
	var parsed: Variant = parse_json(FileAccess.get_file_as_string(manifest_path))
	if not (parsed is Dictionary):
		problems.append("manifest.json is not a JSON object")
		return
	manifest = parsed
	for f: String in MANIFEST_FIELDS:
		if not manifest.has(f):
			problems.append("manifest field '%s' is missing" % f)
	if not problems.is_empty():
		return
	if String(manifest.format) != FORMAT:
		problems.append("manifest format is '%s', expected '%s'" % [manifest.format, FORMAT])
	if not _is_number(manifest.schema) or int(manifest.schema) != SCHEMA:
		problems.append("manifest schema is %s, expected %d" % [manifest.schema, SCHEMA])
	if String(manifest.bundle_id).strip_edges() == "":
		problems.append("bundle_id is empty")
	if not (manifest.products is Array) or (manifest.products as Array).is_empty():
		problems.append("manifest lists no products")
		return
	var ids := {}
	for p: Variant in manifest.products:
		if not (p is Dictionary):
			problems.append("a product entry is not an object")
			continue
		_check_product(p, ids)
	_check_sites()
	_check_episodes(ids)
	_check_refresh(ids)


func _check_product(p: Dictionary, ids: Dictionary) -> void:
	var label := String(p.get("id", "?"))
	var missing := PackedStringArray()
	for f: String in PRODUCT_FIELDS:
		if not p.has(f):
			missing.append(f)
	if not missing.is_empty():
		problems.append("product %s: fields missing: %s" % [label, ", ".join(missing)])
		return
	for f: String in PRODUCT_TEXT_REQUIRED:
		if String(p[f]).strip_edges() == "":
			problems.append("product %s: field '%s' is empty" % [label, f])
	if ids.has(label):
		problems.append("product id %s is listed twice" % label)
	ids[label] = true
	for f: String in ["lat", "lon", "bytes", "missing_value", "sol_start", "sol_end", "ls_start", "ls_end"]:
		if not _is_number(p[f]):
			problems.append("product %s: '%s' is not a number" % [label, f])
	if not (p.columns is Dictionary) or (p.columns as Dictionary).is_empty():
		problems.append("product %s: 'columns' must name each column and its unit" % label)
		return
	if not (p.units_ok is Array):
		problems.append("product %s: 'units_ok' must be a list" % label)
		return
	if not (p.transform is Array):
		problems.append("product %s: 'transform' must be a list of steps" % label)
	for u: Variant in p.units_ok:
		if not KNOWN_UNITS.has(String(u)):
			problems.append("product %s: unit '%s' in units_ok is not an allowed unit" % [label, u])
	for column: String in (p.columns as Dictionary):
		var unit := String(p.columns[column])
		# a time column in sols, seconds or hours is always allowed; every other unit must be listed in units_ok
		var time_unit := unit == "sol" or unit == "s" or unit == "h"
		if not KNOWN_UNITS.has(unit) or not (time_unit or (p.units_ok as Array).has(unit)):
			problems.append("product %s: column '%s' has unit '%s', which is not allowed" % [label, column, unit])
	var file := dir.path_join(String(p.file))
	if String(p.file).contains("..") or String(p.file).contains("/") or String(p.file).contains("\\"):
		problems.append("product %s: file name '%s' must be a plain name inside the bundle" % [label, p.file])
		return
	if not FileAccess.file_exists(file):
		problems.append("product %s: file %s is missing" % [label, p.file])
		return
	var sha := FileAccess.get_sha256(file)
	if sha.to_lower() != String(p.sha256).to_lower():
		problems.append("product %s: sha256 does not match the file (damaged or changed)" % label)
	var length := -1
	var fa := FileAccess.open(file, FileAccess.READ)
	if fa != null:
		length = fa.get_length()
		fa.close()
	if _is_number(p.bytes) and length != int(p.bytes):
		problems.append("product %s: file has %d bytes, manifest says %d" % [label, length, int(p.bytes)])
	_check_csv(p, file)


## Header names must match `columns`; every cell a number in range or the missing value; flags whole numbers >= 0;
## the time column never missing and never going backwards.
func _check_csv(p: Dictionary, file: String) -> void:
	var label := String(p.id)
	var text := FileAccess.get_file_as_string(file)
	var lines := PackedStringArray()
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line != "" and not line.begins_with("#"):
			lines.append(line)
	if lines.size() < 2:
		problems.append("product %s: the file has no data rows" % label)
		return
	var header := PackedStringArray()
	for h in lines[0].split(","):
		header.append(h.strip_edges())
	var columns: Dictionary = p.columns
	var header_set := {}
	for h in header:
		header_set[h] = true
	for c: String in columns:
		if not header_set.has(c):
			problems.append("product %s: column '%s' is not in the file header" % [label, c])
	for h in header:
		if not columns.has(h):
			problems.append("product %s: file column '%s' is not described in the manifest" % [label, h])
	if not problems.is_empty() and problems[problems.size() - 1].begins_with("product %s:" % label):
		return
	var missing := float(p.missing_value)
	var time_index := _time_column(header, columns)
	var sums := {}
	var counts := {}
	var last_time := -INF
	var first_time := INF
	var bad := 0
	var bad_first := ""
	for r in range(1, lines.size()):
		var cells := lines[r].split(",")
		if cells.size() != header.size():
			bad += 1
			if bad_first == "":
				bad_first = "row %d has %d cells, header has %d" % [r, cells.size(), header.size()]
			continue
		for i in header.size():
			var cell := cells[i].strip_edges()
			var name := header[i]
			var unit := String(columns.get(name, ""))
			if not cell.is_valid_float():
				bad += 1
				if bad_first == "":
					bad_first = "row %d column %s is not a number ('%s')" % [r, name, cell]
				continue
			var v := cell.to_float()
			if is_nan(v) or is_inf(v):
				bad += 1
				if bad_first == "":
					bad_first = "row %d column %s is not finite" % [r, name]
				continue
			var is_missing := absf(v - missing) < 1e-9
			if i == time_index:
				if is_missing:
					bad += 1
					if bad_first == "":
						bad_first = "row %d has no time" % r
					continue
				if v < last_time:
					problems.append("product %s: time column '%s' goes backwards at row %d" % [label, name, r])
					return
				last_time = v
				first_time = minf(first_time, v)
				continue                       # the time column (often `sol` in unit "1") has no value range
			if is_missing:
				continue
			if _is_flag(name):
				if v < 0.0 or v > 255.0 or absf(v - roundf(v)) > 1e-9:
					bad += 1
					if bad_first == "":
						bad_first = "row %d flag %s is %s (flags are whole numbers 0..255)" % [r, name, cell]
				continue
			var range_: Array = UNIT_RANGES.get(unit, [-INF, INF])
			if v < float(range_[0]) or v > float(range_[1]):
				bad += 1
				if bad_first == "":
					bad_first = "row %d column %s = %s %s is outside the plausible range" % [r, name, cell, unit]
				continue
			if i != time_index:
				sums[name] = float(sums.get(name, 0.0)) + v
				counts[name] = int(counts.get(name, 0)) + 1
	if bad > 0:
		problems.append("product %s: %d bad cells (first: %s)" % [label, bad, bad_first])
	var means := {}
	for name: String in sums:
		means[name] = float(sums[name]) / float(counts[name])
	product_stats[label] = {"rows": lines.size() - 1, "time_column": header[time_index] if time_index >= 0 else "",
		"time_first": first_time, "time_last": last_time, "means": means}


## Index of the time column: the first one named like a time (sol, msd, time, ls), else the first column.
static func _time_column(header: PackedStringArray, columns: Dictionary) -> int:
	for i in header.size():
		var n := header[i].to_lower()
		var unit := String(columns.get(header[i], ""))
		if unit == "sol" or unit == "s" or unit == "h" or n == "sol" or n.begins_with("sol_") or n.contains("time") or n == "msd" or n == "ls":
			return i
	return 0


static func _is_flag(column: String) -> bool:
	var n := column.to_lower()
	return n.contains("flag") or n.ends_with("_qf") or n == "quality" or n == "qf"


## Every product must describe the same place (do not combine distant landing sites as if one).
func _check_sites() -> void:
	var first := {}
	for p: Variant in manifest.products:
		if not (p is Dictionary) or not _is_number((p as Dictionary).get("lat")) or not _is_number((p as Dictionary).get("lon")):
			continue
		if first.is_empty():
			first = p
			continue
		var dlat := absf(float(p.lat) - float(first.lat))
		var dlon := absf(fposmod(float(p.lon) - float(first.lon) + 180.0, 360.0) - 180.0)
		if dlat > SAME_SITE_DEG or dlon > SAME_SITE_DEG:
			problems.append("products %s (%s) and %s (%s) come from places %.0f and %.0f degrees apart: one bundle must describe one site" % [
				first.id, first.site, p.id, p.site, dlat, dlon])


func _check_episodes(ids: Dictionary) -> void:
	var file := dir.path_join(String(manifest.episodes_file))
	if String(manifest.episodes_file).contains("/") or String(manifest.episodes_file).contains("\\") or not FileAccess.file_exists(file):
		problems.append("episodes file %s is missing" % manifest.episodes_file)
		return
	if FileAccess.get_sha256(file).to_lower() != String(manifest.episodes_sha256).to_lower():
		problems.append("episodes file: sha256 does not match")
	var parsed: Variant = parse_json(FileAccess.get_file_as_string(file))
	if not (parsed is Dictionary):
		problems.append("episodes file is not a JSON object")
		return
	var data: Dictionary = parsed
	if not (data.get("episodes") is Array):
		problems.append("episodes file has no 'episodes' list")
		return
	var seen := {}
	for e: Variant in data.episodes:
		if not (e is Dictionary):
			problems.append("an episode is not an object")
			continue
		var ep: Dictionary = e
		var label := String(ep.get("id", "?"))
		var missing := PackedStringArray()
		for f: String in EPISODE_FIELDS:
			if not ep.has(f):
				missing.append(f)
		if not missing.is_empty():
			problems.append("episode %s: fields missing: %s" % [label, ", ".join(missing)])
			continue
		if seen.has(label):
			problems.append("episode id %s is listed twice" % label)
		seen[label] = true
		if not _is_number(ep.duration_sols) or float(ep.duration_sols) <= 0.0:
			problems.append("episode %s: duration_sols must be a positive number" % label)
		if not _is_number(ep.peak_tau) or float(ep.peak_tau) < 0.0:
			problems.append("episode %s: peak_tau must be a number >= 0" % label)
		for f: String in ["wind_ms_mean", "solar_factor_at_peak"]:
			if not _is_number(ep[f]):
				problems.append("episode %s: %s must be a number" % [label, f])
		if not (ep.tau_curve is Array) or (ep.tau_curve as Array).size() < 2:
			problems.append("episode %s: tau_curve needs at least two values" % label)
			continue
		var top := 0.0
		var curve_ok := true
		for v: Variant in ep.tau_curve:
			if not _is_number(v) or float(v) < 0.0 or float(v) > 50.0:
				curve_ok = false
			else:
				top = maxf(top, float(v))
		if not curve_ok:
			problems.append("episode %s: tau_curve values must be numbers between 0 and 50" % label)
			continue
		if _is_number(ep.peak_tau) and absf(top - float(ep.peak_tau)) > maxf(0.05, 0.1 * float(ep.peak_tau)):
			notes.append("episode %s: peak_tau %.2f differs from the curve's highest value %.2f" % [label, float(ep.peak_tau), top])
		if _is_number(ep.duration_sols):
			var expected := float(ep.duration_sols) * 4.0 + 1.0
			if absf(float((ep.tau_curve as Array).size()) - expected) > 2.0:
				notes.append("episode %s: %d curve values for %.2f sols (one per 0.25 sol expected)" % [label, (ep.tau_curve as Array).size(), float(ep.duration_sols)])
		if ep.source_product_ids is Array:
			for pid: Variant in ep.source_product_ids:
				if not ids.has(String(pid)):
					notes.append("episode %s: source product %s is not in this bundle" % [label, pid])
		episodes.append(ep)
	var bg: Variant = (data.get("background", {}) as Dictionary).get("tau_by_ls") if data.get("background") is Dictionary else null
	if not (bg is Array) or (bg as Array).is_empty():
		problems.append("episodes file has no background.tau_by_ls")
		return
	var last := -INF
	for pair: Variant in bg:
		if not (pair is Array) or (pair as Array).size() < 2 or not _is_number(pair[0]) or not _is_number(pair[1]):
			problems.append("background.tau_by_ls must be a list of [ls, tau] pairs")
			return
		var ls := float(pair[0])
		var tau := float(pair[1])
		if ls < 0.0 or ls > 360.0 or ls < last or tau < 0.0 or tau > 50.0:
			problems.append("background.tau_by_ls: Ls must rise from 0 to 360 and tau must be >= 0 (at Ls %s)" % pair[0])
			return
		last = ls
		tau_by_ls.append([ls, tau])


func _check_refresh(ids: Dictionary) -> void:
	if not (manifest.refresh is Array):
		problems.append("'refresh' must be a list")
		return
	for r: Variant in manifest.refresh:
		if not (r is Dictionary):
			problems.append("a refresh entry is not an object")
			continue
		for f: String in REFRESH_FIELDS:
			if not (r as Dictionary).has(f):
				problems.append("refresh entry: field '%s' is missing" % f)
				return
		if not ids.has(String(r.product_id)):
			problems.append("refresh entry names product %s, which is not in the bundle" % r.product_id)
		if not String(r.url).begins_with("https://"):
			problems.append("refresh entry for %s: the address must start with https://" % r.product_id)
		if not _is_number(r.max_bytes) or float(r.max_bytes) <= 0.0 or not _is_number(r.timeout_s) or float(r.timeout_s) <= 0.0:
			problems.append("refresh entry for %s: max_bytes and timeout_s must be positive numbers" % r.product_id)


## Parses JSON text without printing engine errors for bad text; null if it is not valid JSON.
static func parse_json(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


static func _dir_exists(path: String) -> bool:
	return DirAccess.dir_exists_absolute(path)


# ---------------------------------------------------------------- small helpers for the refresh

## Every file of the bundle by name (manifest, products, episodes).
func file_names() -> PackedStringArray:
	var out := PackedStringArray(["manifest.json"])
	for p: Dictionary in products():
		out.append(String(p.file))
	if manifest.has("episodes_file"):
		out.append(String(manifest.episodes_file))
	return out


## Text for the screens: "Jezero crater, archive 2022-01-01 to 2022-01-31 (sols 300 to 330)".
func describe() -> String:
	if is_builtin():
		return String(manifest.get("label", "Built-in default: no archive data."))
	var period := observation_period()
	var dates := "%s to %s" % [String(period.get("start", "?")).left(10), String(period.get("end", "?")).left(10)]
	if is_missing(float(period.get("sol_start", -999.0))) or is_missing(float(period.get("sol_end", -999.0))):
		return "%s, archive observations %s" % [site(), dates]
	return "%s, archive observations %s (sols %d to %d)" % [site(), dates, int(period.sol_start), int(period.sol_end)]
