extends SceneTree
## Part D (Prompt 09) checks, all offline: the shipped weather bundle and the test fixture validate in GDScript
## (every manifest field, sha256 through FileAccess.get_sha256, byte sizes, units in the allowed set, CSV header =
## declared columns, numbers, missing values, time order, plausible ranges, episodes, refresh entries); a tampered
## manifest is rejected; the weather register entries and claims resolve in SourceLibrary.
## Run: godot --headless --path . --script res://tests/test_weather_data.gd

const BUNDLE_DIR := "res://data/weather/bundle"
const FIXTURE_DIR := "res://tests/fixtures/weather_bundle_min"
const SOURCES_WEATHER := "res://data/sources_weather.json"
const CLAIMS_WEATHER := "res://data/claims_weather.json"
const FORMAT := "mars_colony_weather_bundle"
const ALLOWED_UNITS: PackedStringArray = ["Pa", "K", "m/s", "deg", "1"]
const KINDS: PackedStringArray = ["pressure", "air_temperature", "wind", "dust_opacity", "humidity", "ground_temperature", "radiation"]
## Manifest product fields -> "s" string, "n" number, "d" dictionary, "a" array.
const PRODUCT_FIELDS := {
	"id": "s", "kind": "s", "file": "s", "sha256": "s", "bytes": "n", "source_id": "s", "pds_lid": "s", "version": "s",
	"mission": "s", "instrument": "s", "site": "s", "lat": "n", "lon": "n", "observation_start_utc": "s",
	"observation_end_utc": "s", "sol_start": "n", "sol_end": "n", "ls_start": "n", "ls_end": "n", "columns": "d",
	"units_ok": "a", "missing_value": "n", "quality": "s", "license": "s", "source_url": "s", "etag": "s",
	"last_modified": "s", "retrieved_utc": "s", "transform": "a",
}
const EPISODE_FIELDS := {
	"id": "s", "source_product_ids": "a", "observed": "s", "duration_sols": "n", "peak_tau": "n", "tau_curve": "a",
	"wind_ms_mean": "n", "solar_factor_at_peak": "n", "notes": "s",
}
## Plausible ranges by unit, and by column name for dimensionless columns.
const RANGES_BY_UNIT := {"Pa": [100.0, 1500.0], "K": [100.0, 350.0], "m/s": [0.0, 100.0], "deg": [-360.0, 360.0]}
const RANGES_BY_NAME := {
	"tau": [0.0, 20.0], "tau_vis": [0.0, 20.0], "cdod610": [0.0, 10.0], "cdodtot": [0.0, 10.0],
	"reliability": [0.0, 1.0], "samples": [0.0, 100000.0], "ls": [0.0, 360.0], "wind_dir": [0.0, 360.0],
}

var _passed := 0
var _total := 0


func _check(name: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS ", name, ("  " + detail) if detail != "" else "")
	else:
		print("FAIL ", name, ": ", detail)


func _initialize() -> void:
	_check_shipped_bundle()
	_check_fixture()
	_check_tampering_is_caught()
	_check_import_settings()
	_check_register_entries()
	_check_claims()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


# ---------------------------------------------------------------- bundle validation (same rules as validate_bundle.py)

static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _is_kind(v: Variant, k: String) -> bool:
	match k:
		"s":
			return v is String
		"n":
			return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
		"d":
			return v is Dictionary
		"a":
			return v is Array
	return false


## Problems found in the bundle at dir with this manifest (empty = valid). info gets counts and kinds.
static func validate(dir: String, m: Dictionary, info: Dictionary) -> PackedStringArray:
	var bad := PackedStringArray()
	if String(m.get("format", "")) != FORMAT:
		bad.append("format is " + str(m.get("format")))
	if int(m.get("schema", 0)) != 1:
		bad.append("schema is " + str(m.get("schema")))
	for f: String in ["bundle_id", "built_utc", "episodes_file", "episodes_sha256"]:
		if not (m.get(f) is String) or String(m[f]) == "":
			bad.append("manifest field %s missing" % f)
	if not (m.get("products") is Array) or not (m.get("refresh") is Array):
		bad.append("products or refresh is not a list")
		return bad
	var ids: Dictionary = {}
	var kinds: Dictionary = {}
	for p_var: Variant in m.products:
		if not (p_var is Dictionary):
			bad.append("a product is not an object")
			continue
		var p: Dictionary = p_var
		var pid := String(p.get("id", "?"))
		var wrong: PackedStringArray = []
		for f: String in PRODUCT_FIELDS:
			if not _is_kind(p.get(f), String(PRODUCT_FIELDS[f])):
				wrong.append(f)
		if not wrong.is_empty():
			bad.append("%s: fields missing or of the wrong type: %s" % [pid, ", ".join(wrong)])
			continue
		if ids.has(pid):
			bad.append("duplicate product " + pid)
		ids[pid] = true
		kinds[String(p.kind)] = true
		if not KINDS.has(String(p.kind)):
			bad.append("%s: unknown kind %s" % [pid, p.kind])
		for u: Variant in p.units_ok:
			if not ALLOWED_UNITS.has(String(u)):
				bad.append("%s: units_ok has %s" % [pid, u])
		for c: String in p.columns:
			var unit := String(p.columns[c])
			if not ALLOWED_UNITS.has(unit) or not (p.units_ok as Array).has(unit):
				bad.append("%s: column %s has unit '%s'" % [pid, c, unit])
		if not String(p.source_url).begins_with("https://"):
			bad.append("%s: source_url is not https" % pid)
		if (p.transform as Array).is_empty():
			bad.append("%s: no transform steps" % pid)
		if float(p.ls_start) < 0.0 or float(p.ls_start) >= 360.0 or float(p.ls_end) < 0.0 or float(p.ls_end) >= 360.0:
			bad.append("%s: Ls out of range" % pid)
		if int(p.sol_start) > int(p.sol_end):
			bad.append("%s: sol_start after sol_end" % pid)
		if String(p.observation_start_utc) > String(p.observation_end_utc):
			bad.append("%s: observation times reversed" % pid)
		var path := dir.path_join(String(p.file))
		if String(p.file).contains("/") or not FileAccess.file_exists(path):
			bad.append("%s: file %s missing" % [pid, p.file])
			continue
		var fa := FileAccess.open(path, FileAccess.READ)
		var length := fa.get_length()
		fa.close()
		if length != int(p.bytes):
			bad.append("%s: %d bytes, manifest says %d" % [pid, length, int(p.bytes)])
		if FileAccess.get_sha256(path) != String(p.sha256):
			bad.append("%s: sha256 differs" % pid)
		bad.append_array(_validate_csv(path, p, info))
	info["product_ids"] = ids.keys()
	info["kinds"] = kinds.keys()
	var epath := dir.path_join(String(m.get("episodes_file", "")))
	if not FileAccess.file_exists(epath):
		bad.append("episodes file missing")
		return bad
	if FileAccess.get_sha256(epath) != String(m.get("episodes_sha256", "")):
		bad.append("episodes sha256 differs")
	var e: Variant = _read_json(epath)
	if not (e is Dictionary) or not ((e as Dictionary).get("episodes") is Array):
		bad.append("episodes.json unreadable")
		return bad
	var step := float((e as Dictionary).get("curve_step_sol", 0.25))
	var missing_values: Array = []
	for p_var: Variant in m.products:
		if p_var is Dictionary and (p_var as Dictionary).has("missing_value"):
			missing_values.append(float(p_var.missing_value))
	var eps: Array = e.episodes
	info["episodes"] = eps.size()
	var measured_wind := 0
	for ep_var: Variant in eps:
		var ep: Dictionary = ep_var
		var eid := String(ep.get("id", "?"))
		var wrong: PackedStringArray = []
		for f: String in EPISODE_FIELDS:
			if not _is_kind(ep.get(f), String(EPISODE_FIELDS[f])):
				wrong.append(f)
		if not wrong.is_empty():
			bad.append("episode %s: fields missing or of the wrong type: %s" % [eid, ", ".join(wrong)])
			continue
		if (ep.source_product_ids as Array).is_empty():
			bad.append("episode %s names no products" % eid)
		for sid: Variant in ep.source_product_ids:
			if not ids.has(String(sid)):
				bad.append("episode %s names unknown product %s" % [eid, sid])
		var curve: Array = ep.tau_curve
		var want := int(round(float(ep.duration_sols) / step)) + 1
		if curve.size() != want:
			bad.append("episode %s: %d curve points, expected %d" % [eid, curve.size(), want])
		var top := -1.0
		for v: Variant in curve:
			if not _is_kind(v, "n") or float(v) < 0.0 or float(v) > 20.0:
				bad.append("episode %s: curve value %s out of range" % [eid, v])
				break
			top = maxf(top, float(v))
		if absf(top - float(ep.peak_tau)) > 0.001:
			bad.append("episode %s: peak_tau %s is not the curve maximum %s" % [eid, ep.peak_tau, top])
		var wind := float(ep.wind_ms_mean)
		if missing_values.has(wind):
			pass
		elif wind < 0.0 or wind > 60.0:
			bad.append("episode %s: wind %s implausible" % [eid, wind])
		else:
			measured_wind += 1
		if float(ep.solar_factor_at_peak) <= 0.0 or float(ep.solar_factor_at_peak) > 1.5:
			bad.append("episode %s: solar factor %s implausible" % [eid, ep.solar_factor_at_peak])
	info["episodes_with_wind"] = measured_wind
	var bg: Variant = (e as Dictionary).get("background", {}).get("tau_by_ls")
	if not (bg is Array) or (bg as Array).size() < 2:
		bad.append("background.tau_by_ls missing")
	else:
		var last := -1.0
		for pair: Variant in bg:
			if not (pair is Array) or (pair as Array).size() != 2 or float(pair[0]) <= last or float(pair[0]) > 360.0 or float(pair[1]) < 0.0:
				bad.append("background pair %s out of order or range" % str(pair))
				break
			last = float(pair[0])
		info["background_points"] = (bg as Array).size()
	for r_var: Variant in m.refresh:
		var r: Dictionary = r_var
		if not ids.has(String(r.get("product_id", ""))):
			bad.append("refresh entry for unknown product " + str(r.get("product_id")))
		if not String(r.get("url", "")).begins_with("https://"):
			bad.append("refresh url is not https")
		if not _is_kind(r.get("max_bytes"), "n") or int(r.max_bytes) <= 0 or not _is_kind(r.get("timeout_s"), "n") or float(r.timeout_s) <= 0.0:
			bad.append("refresh limits missing for " + str(r.get("product_id")))
	return bad


static func _validate_csv(path: String, p: Dictionary, info: Dictionary) -> PackedStringArray:
	var bad := PackedStringArray()
	var pid := String(p.id)
	var lines := FileAccess.get_file_as_string(path).split("\n")
	if lines.size() > 0 and lines[lines.size() - 1] == "":
		lines.remove_at(lines.size() - 1)
	var header := lines[0].split(",")
	var columns: Dictionary = p.columns
	if Array(header) != columns.keys():
		bad.append("%s: header %s differs from columns %s" % [pid, header, columns.keys()])
		return bad
	var tcol := String(p.get("time_column", header[0]))
	var ti := header.find(tcol)
	if ti < 0:
		bad.append("%s: no time column" % pid)
		return bad
	var missing := float(p.missing_value)
	var last_t := -INF
	var missing_cells := 0
	for n in range(1, lines.size()):
		var cells := lines[n].split(",")
		if cells.size() != header.size():
			bad.append("%s line %d: %d cells" % [pid, n + 1, cells.size()])
			continue
		for i in cells.size():
			if not cells[i].is_valid_float():
				bad.append("%s line %d: '%s' is not a number" % [pid, n + 1, cells[i]])
				continue
			var v := cells[i].to_float()
			if v == missing:
				missing_cells += 1
				if i == ti:
					bad.append("%s line %d: time missing" % [pid, n + 1])
				continue
			var name := header[i]
			var rng: Variant = RANGES_BY_NAME.get(name, RANGES_BY_UNIT.get(String(columns[name])))
			if rng is Array and (v < float(rng[0]) or v > float(rng[1])):
				bad.append("%s line %d: %s = %s outside %s" % [pid, n + 1, name, v, str(rng)])
		var t := cells[ti].to_float()
		if t <= last_t:
			bad.append("%s line %d: time does not increase" % [pid, n + 1])
		last_t = t
	if lines.size() < 3:
		bad.append("%s: fewer than 2 rows" % pid)
	info["rows"] = int(info.get("rows", 0)) + lines.size() - 1
	info["missing_cells"] = int(info.get("missing_cells", 0)) + missing_cells
	return bad


func _load_and_validate(dir: String, info: Dictionary) -> PackedStringArray:
	var m: Variant = _read_json(dir.path_join("manifest.json"))
	if not (m is Dictionary):
		return PackedStringArray(["manifest.json unreadable"])
	info["manifest"] = m
	return validate(dir, m, info)


# ---------------------------------------------------------------- checks

func _check_shipped_bundle() -> void:
	var info := {}
	var bad := _load_and_validate(BUNDLE_DIR, info)
	_check("shipped bundle validates (fields, sha256, sizes, units, columns, time order, ranges, episodes, refresh)",
		bad.is_empty(), "%d products, %d rows, %d missing cells, %d episodes; %s" % [
			(info.get("product_ids", []) as Array).size(), int(info.get("rows", 0)), int(info.get("missing_cells", 0)),
			int(info.get("episodes", 0)), "; ".join(bad.slice(0, 8))])
	var kinds: Array = info.get("kinds", [])
	_check("shipped bundle has pressure, air temperature, wind and dust opacity products",
		kinds.has("pressure") and kinds.has("air_temperature") and kinds.has("wind") and kinds.has("dust_opacity"), str(kinds))
	_check("shipped bundle has observation-derived episodes and a seasonal background",
		int(info.get("episodes", 0)) >= 3 and int(info.get("background_points", 0)) >= 13,
		"%d episodes (%d with measured wind), %d background points" % [int(info.get("episodes", 0)),
			int(info.get("episodes_with_wind", 0)), int(info.get("background_points", 0))])
	var m: Dictionary = info.get("manifest", {})
	var site_ok := true
	var ids_ok := true
	for p: Dictionary in m.get("products", []):
		if String(p.get("site", "")) != "Jezero crater":
			site_ok = false
		var pid := String(p.get("id", ""))
		if pid.begins_with("meda_") and not String(p.get("pds_lid", "")).begins_with("urn:nasa:pds:mars2020_meda:"):
			ids_ok = false
	_check("every product is from one site, Jezero crater, and MEDA products keep their PDS ids", site_ok and ids_ok)
	var notice := String(m.get("notice", "")).to_lower()
	_check("manifest says archive observations, not live weather or a forecast",
		notice.contains("not live weather") and notice.contains("not a forecast"), String(m.get("notice", "")))


func _check_fixture() -> void:
	var info := {}
	var bad := _load_and_validate(FIXTURE_DIR, info)
	_check("fixture bundle validates with 2 products and 2 episodes",
		bad.is_empty() and (info.get("product_ids", []) as Array).size() == 2 and int(info.get("episodes", 0)) == 2,
		"; ".join(bad.slice(0, 8)))


func _check_tampering_is_caught() -> void:
	var m: Dictionary = _read_json(BUNDLE_DIR.path_join("manifest.json"))
	var sha_bad := m.duplicate(true)
	(sha_bad.products[0] as Dictionary)["sha256"] = "0".repeat(64)
	var unit_bad := m.duplicate(true)
	var cols: Dictionary = (unit_bad.products[0] as Dictionary).columns
	cols[cols.keys()[1]] = "mbar"
	var field_bad := m.duplicate(true)
	(field_bad.products[1] as Dictionary).erase("license")
	var ep_bad := m.duplicate(true)
	ep_bad["episodes_sha256"] = "f".repeat(64)
	var caught: PackedStringArray = []
	for pair: Array in [["sha256", sha_bad], ["unit", unit_bad], ["field", field_bad], ["episodes", ep_bad]]:
		if not validate(BUNDLE_DIR, pair[1], {}).is_empty():
			caught.append(String(pair[0]))
	_check("a wrong sha256, a unit outside the set, a missing field and a changed episodes file are each rejected",
		caught.size() == 4, "caught: %s" % caught)


func _check_import_settings() -> void:
	var problems: PackedStringArray = []
	for dir: String in [BUNDLE_DIR, FIXTURE_DIR]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".translation"):
				problems.append(dir.path_join(f))
			if f.ends_with(".csv"):
				var imp := FileAccess.get_file_as_string(dir.path_join(f + ".import"))
				if not imp.contains("importer=\"keep\""):
					problems.append(f + " is not kept as a plain file")
	_check("bundle CSVs are kept as plain files (no translation import)", problems.is_empty(), "; ".join(problems))


func _check_register_entries() -> void:
	SourceLibrary.reload()
	var m: Dictionary = _read_json(BUNDLE_DIR.path_join("manifest.json"))
	var problems: PackedStringArray = []
	for p: Dictionary in m.products:
		var src := SourceLibrary.source(String(p.source_id))
		if src.is_empty():
			problems.append("%s: source %s not found" % [p.id, p.source_id])
			continue
		if String(src.get("status", "")) != "VERIFIED" or not SourceLibrary.is_citable(src):
			problems.append("%s: %s is not VERIFIED" % [p.id, p.source_id])
		if String(src.get("url", "")) != String(p.source_url):
			problems.append("%s: register url differs from the product's source_url" % p.id)
		if not SourceLibrary.is_safe_url(String(src.get("url", ""))):
			problems.append("%s: unsafe url" % p.source_id)
	_check("every product's source id resolves to a VERIFIED weather entry with the same address", problems.is_empty(),
		"; ".join(problems))
	var file_data: Dictionary = _read_json(SOURCES_WEATHER)
	var file_ids: Array = []
	for s: Dictionary in file_data.get("sources", []):
		file_ids.append(String(s.get("id", "")))
	var extra_ids: Array = []
	for s: Dictionary in SourceLibrary.extra_sources():
		extra_ids.append(String(s.get("id", "")))
	var in_register := false
	for s: Dictionary in SourceLibrary.sources():
		if file_ids.has(String(s.get("id", ""))):
			in_register = true
	_check("SourceLibrary loads data/sources_weather.json beside the register",
		file_ids.size() >= 10 and extra_ids == file_ids and not in_register \
		and SourceLibrary.all_sources().size() == SourceLibrary.sources().size() + extra_ids.size(),
		"%d weather entries; register %d" % [extra_ids.size(), SourceLibrary.sources().size()])
	var fields_bad: PackedStringArray = []
	for s: Dictionary in SourceLibrary.extra_sources():
		for f: String in ["title", "publisher", "url", "status", "checked_on", "kind", "category", "values_read", "supports", "mission_site", "observation_dates", "units"]:
			if not s.has(f):
				fields_bad.append("%s lacks %s" % [s.get("id", "?"), f])
		if String(s.get("status", "")) == "VERIFIED" and SourceLibrary.date_text(String(s.get("checked_on", ""))) == "":
			fields_bad.append("%s has no check date" % s.get("id", "?"))
	_check("weather register entries have the register fields and a check date", fields_bad.is_empty(), "; ".join(fields_bad))


func _check_claims() -> void:
	var data: Dictionary = _read_json(CLAIMS_WEATHER)
	var problems: PackedStringArray = []
	var cats: Dictionary = {}
	for c_file: Dictionary in data.get("claims", []):
		var id := String(c_file.get("id", ""))
		var c := SourceLibrary.claim(id)
		if c.is_empty():
			problems.append(id + " not loaded")
			continue
		var cat := String(c.get("category", ""))
		cats[cat] = true
		if not ["archive", "game_time", "fiction", "balance"].has(cat):
			problems.append("%s has category %s" % [id, cat])
		for sid: Variant in c.get("source_ids", []):
			if SourceLibrary.source(String(sid)).is_empty():
				problems.append("%s names unknown source %s" % [id, sid])
		if cat == "archive" and (SourceLibrary.is_unsourced(c) or SourceLibrary.claim_category_text(c) == "source not yet checked"):
			problems.append(id + " is an archive claim without a checked source")
		if cat != "archive" and not (c.get("source_ids", []) as Array).is_empty():
			problems.append(id + " is game time or balance but cites a source")
	_check("weather claims resolve in SourceLibrary with checked sources", problems.is_empty() and (data.get("claims", []) as Array).size() >= 8,
		"; ".join(problems))
	_check("weather claims cover archive, game time and balance",
		cats.has("archive") and cats.has("game_time") and cats.has("balance"), str(cats.keys()))
	var nf := SourceLibrary.claim("weather_not_forecast")
	_check("the 'not a forecast' claim says archive observations played faster",
		String(nf.get("text", "")).contains("not a forecast") and String(nf.get("text", "")).contains("played faster"),
		String(nf.get("text", "")))
