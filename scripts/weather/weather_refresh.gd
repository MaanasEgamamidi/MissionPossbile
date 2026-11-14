class_name WeatherRefresh
extends Node
## Checks the archive for published updates of the weather data, in the background: at start and every
## WeatherConfig.refresh_hours (1 h) while online. Each `refresh` entry of the bundle is asked for with a conditional
## GET (If-None-Match / If-Modified-Since from the manifest), a timeout and a size cap.
##   304              up to date (a source that publishes nothing new is not a failure)
##   200, original    the refresh entry points at the archive's ORIGINAL file (its transform to a bundle CSV runs in
##                    the Python build tool): the answer only means "an update was published". It is marked in the
##                    status (product, ETag, date, size), the player is told, the validated bundle stays in use, and
##                    its ETag is sent next time so the same file is not fetched again. Not a failure.
##   200, bundle CSV  the new file goes into a complete new bundle in a temporary folder (copy of the current bundle,
##                    the changed product replaced, its sha256 recomputed). The episodes are derived by the Python build
##                    tool, not by GDScript, so they are kept and the product is marked as updated. The new bundle is
##                    validated as a whole, then swapped in atomically: incoming -> current, the old current kept
##                    as previous.
##   anything else    timeout, too big, HTTP error, interrupted download, invalid data: the cache is left untouched
##                    and the next try waits 1, 2, 4 ... minutes (at most 60).
## The game that is running keeps its pinned data (state.data_snapshot_id); a newer validated bundle is used from the
## next new game or load, and the status says so.
##
## The HTTP layer is injectable: `transport` is any object with
##   func fetch(request: Dictionary, done: Callable) -> void
## request = {"url", "headers": PackedStringArray, "max_bytes": int, "timeout_s": float}; done is called once with
## {"status": int HTTP code (0 if none), "error": "" | "timeout" | "oversize" | "connection" | "interrupted",
##  "body": PackedByteArray, "headers": {lower-case name: value}}.
## The default transport uses HTTPRequest children of this node. Tests use a fake one: no real network.

signal status_changed(status: Dictionary)

const GROUP := &"weather_refresh"
const STATUS_FILE := "status.json"

## Default transport: one HTTPRequest child per download, threaded, with timeout and body size limit.
class HttpTransport extends RefCounted:
	var host: Node

	func _init(p_host: Node) -> void:
		host = p_host

	func fetch(request: Dictionary, done: Callable) -> void:
		var http := HTTPRequest.new()
		http.use_threads = true
		http.timeout = float(request.get("timeout_s", 20.0))
		http.body_size_limit = int(request.get("max_bytes", 2000000))
		host.add_child(http)
		http.request_completed.connect(func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
			var h := {}
			for line in headers:
				var colon := line.find(":")
				if colon > 0:
					h[line.left(colon).strip_edges().to_lower()] = line.substr(colon + 1).strip_edges()
			var error := ""
			match result:
				HTTPRequest.RESULT_SUCCESS: error = ""
				HTTPRequest.RESULT_TIMEOUT: error = "timeout"
				HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: error = "oversize"
				HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CONNECTION_ERROR, \
				HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, HTTPRequest.RESULT_NO_RESPONSE: error = "connection"
				_: error = "interrupted"
			done.call({"status": code, "error": error, "body": body, "headers": h})
			http.queue_free())
		var err := http.request(String(request.url), request.get("headers", PackedStringArray()))
		if err != OK:
			http.queue_free()
			done.call({"status": 0, "error": "connection", "body": PackedByteArray(), "headers": {}})


var config: WeatherConfig
## The HTTP layer (see the class description). Null = HttpTransport.
var transport: Object
## Current time in Unix seconds. Tests replace it to step through retries without waiting.
var now_func: Callable = func() -> float: return Time.get_unix_time_from_system()
## True: the first check starts on the first frame.
var auto_start := true
## Checks in a row that failed (resets on success).
var failures := 0
## Unix time of the next check.
var next_check_at := 0.0
## True while a check is running.
var busy := false

var _status := {}
var _updates: Array = []
var _published: Array = []
var _failed: Array = []
var _base: WeatherArchive
var _entries: Array = []


func _init(p_config: WeatherConfig = null) -> void:
	config = p_config if p_config != null else WeatherConfig.new()
	_status = read_status()


func _ready() -> void:
	add_to_group(GROUP)
	if transport == null:
		transport = HttpTransport.new(self)
	if auto_start:
		next_check_at = 0.0


func _process(_delta: float) -> void:
	tick(float(now_func.call()))


## The refresh node of a scene tree, or null.
static func find(tree: SceneTree) -> WeatherRefresh:
	return tree.get_first_node_in_group(GROUP) as WeatherRefresh if tree != null else null


## Starts a check when one is due.
func tick(now: float) -> void:
	if busy or now < next_check_at:
		return
	check_now()


## What the screens show: active data, last check, last result in words, whether newer data waits for the next game.
func status() -> Dictionary:
	var s := _status.duplicate(true)
	var active := WeatherArchive.active()
	s["active_snapshot"] = active.snapshot_id()
	s["active_described"] = active.describe()
	s["active_validation"] = active.validation_words()
	return s


## The last saved status (or {} if there is none), for screens on machines without a refresh node.
static func read_status() -> Dictionary:
	var path := WeatherArchive.cache_root().path_join(STATUS_FILE)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = WeatherArchive.parse_json(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Checks every refresh entry of the newest valid bundle now.
func check_now() -> void:
	if busy:
		return
	if transport == null:
		transport = HttpTransport.new(self)
	busy = true
	_updates = []
	_failed = []
	_published = []
	_base = WeatherArchive.best_on_disk()
	_entries = _base.refresh_entries().duplicate()
	if _base.is_builtin() or _entries.is_empty():
		_finish("No update sources are listed for the active data; nothing to check.", true)
		return
	_next_entry(0)


func _next_entry(i: int) -> void:
	if i >= _entries.size():
		_conclude()
		return
	var entry: Dictionary = _entries[i]
	var product := _base.product(String(entry.product_id))
	var headers := PackedStringArray()
	var etag := String(product.get("etag", ""))
	var modified := String(product.get("last_modified", ""))
	# a published update already seen for this same bundle product: ask with its ETag, so it is not fetched again
	var seen: Dictionary = (_status.get("published_updates", {}) as Dictionary).get(String(entry.product_id), {})
	if not seen.is_empty() and String(seen.get("base_sha256", "")) == String(product.get("sha256", "")):
		etag = String(seen.get("etag", etag)) if String(seen.get("etag", "")) != "" else etag
		modified = String(seen.get("last_modified", modified)) if String(seen.get("last_modified", "")) != "" else modified
	if etag != "":
		headers.append("If-None-Match: %s" % etag)
	if modified != "":
		headers.append("If-Modified-Since: %s" % modified)
	var max_bytes := int(entry.get("max_bytes", config.default_max_bytes))
	var request := {"url": String(entry.url), "headers": headers, "max_bytes": max_bytes,
		"timeout_s": float(entry.get("timeout_s", config.default_timeout_s))}
	transport.call("fetch", request, func(response: Dictionary) -> void:
		_on_response(entry, product, max_bytes, response)
		_next_entry(i + 1))


func _on_response(entry: Dictionary, product: Dictionary, max_bytes: int, response: Dictionary) -> void:
	var pid := String(entry.product_id)
	var error := String(response.get("error", ""))
	var code := int(response.get("status", 0))
	var body: PackedByteArray = response.get("body", PackedByteArray())
	var headers: Dictionary = response.get("headers", {})
	if error != "":
		_failed.append("%s: %s" % [pid, _error_words(error)])
		return
	if code == 304:
		return
	if code != 200:
		_failed.append("%s: the archive answered HTTP %d" % [pid, code])
		return
	if body.size() > max_bytes:
		_failed.append("%s: %s" % [pid, _error_words("oversize")])
		return
	if headers.has("content-length") and String(headers["content-length"]).is_valid_int() and int(headers["content-length"]) != body.size():
		_failed.append("%s: %s (%d of %s bytes)" % [pid, _error_words("interrupted"), body.size(), headers["content-length"]])
		return
	var sha := _sha256(body)
	if sha == String(product.get("sha256", "")).to_lower():
		return            # same file as before: nothing new
	if String(entry.get("format", "")) == "original" or not _looks_like_bundle_csv(product, body):
		_published.append({"product_id": pid, "etag": String(headers.get("etag", "")), "last_modified": String(headers.get("last-modified", "")),
			"bytes": body.size(), "sha256": sha, "base_sha256": String(product.get("sha256", "")), "url": String(entry.url)})
		return
	_updates.append({"product_id": pid, "body": body, "etag": String(headers.get("etag", "")), "last_modified": String(headers.get("last-modified", ""))})


## True if `body` is a bundle CSV for `product`: its header names exactly the product's columns.
static func _looks_like_bundle_csv(product: Dictionary, body: PackedByteArray) -> bool:
	var text := body.get_string_from_utf8()
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var names := {}
		for h in line.split(","):
			names[h.strip_edges()] = true
		var columns: Dictionary = product.get("columns", {})
		if names.size() != columns.size():
			return false
		for c: String in columns:
			if not names.has(c):
				return false
		return true
	return false


func _conclude() -> void:
	var marked := _mark_published()
	if _updates.is_empty():
		if _failed.is_empty() and marked != "":
			_finish(marked, true)
		elif _failed.is_empty():
			_finish("Up to date: the archive has published nothing new.", true)
		elif marked != "":
			_finish(marked + " Check failed for: %s." % "; ".join(_failed), false)
		else:
			_finish("Check failed: %s. The last valid data is kept." % "; ".join(_failed), false)
		return
	var result := _build_and_swap()
	if result != "":
		_failed.append(result)
		_finish("New data was rejected: %s. The last valid data is kept." % result, false)
		return
	var words := "New data validated and ready (%s). This game keeps its data; the new data is used from the next new game or load." % WeatherArchive.active().snapshot_id()
	if not _failed.is_empty():
		_finish(words + " Some sources failed: %s." % "; ".join(_failed), false)
	else:
		_finish(words, true)


## Records published original-file updates in the status; returns the words for the player ("" if none).
func _mark_published() -> String:
	if _published.is_empty():
		return ""
	var all: Dictionary = (_status.get("published_updates", {}) as Dictionary).duplicate(true)
	var stamp := Time.get_datetime_string_from_unix_time(int(float(now_func.call())), false) + "Z"
	var names := PackedStringArray()
	for p: Dictionary in _published:
		var entry := p.duplicate()
		entry["seen_utc"] = stamp
		all[String(p.product_id)] = entry
		names.append(String(p.product_id))
	_status["published_updates"] = all
	return ("The archive has published an update of %s. It must go through the bundle build tool before the game can use it, " +
		"so the game keeps using its validated data.") % ", ".join(names)


## Builds the new bundle in `incoming`, validates it and swaps it in. Returns "" or the reason it was rejected.
func _build_and_swap() -> String:
	var incoming := WeatherArchive.incoming_dir()
	_remove_tree(incoming)
	if DirAccess.make_dir_recursive_absolute(incoming) != OK:
		return "the temporary folder could not be made"
	for f in _base.file_names():
		if f == "manifest.json":
			continue
		var bytes := FileAccess.get_file_as_bytes(_base.dir.path_join(f))
		if not _write(incoming.path_join(f), bytes):
			_remove_tree(incoming)
			return "could not copy %s" % f
	var m: Dictionary = _base.manifest.duplicate(true)
	var stamp := Time.get_datetime_string_from_unix_time(int(float(now_func.call())), false) + "Z"
	var names := PackedStringArray()
	for u: Dictionary in _updates:
		for p: Dictionary in m.products:
			if String(p.id) != String(u.product_id):
				continue
			var path := incoming.path_join(String(p.file))
			if not _write(path, u.body):
				_remove_tree(incoming)
				return "could not write %s" % p.file
			p.sha256 = FileAccess.get_sha256(path)
			p.bytes = (u.body as PackedByteArray).size()
			if String(u.etag) != "":
				p.etag = String(u.etag)
			if String(u.last_modified) != "":
				p.last_modified = String(u.last_modified)
			p.retrieved_utc = stamp
			p.updated_by_refresh = stamp
			(p.transform as Array).append("refresh %s: file replaced by the archive's newer copy from source_url; episodes were not recomputed (their steps run in the Python build tool, not in the game) and were kept" % stamp)
			names.append(String(p.id))
	m.built_utc = stamp
	m.version = "r" + stamp.replace("-", "").replace(":", "")
	m.base_built_utc = String(_base.manifest.get("base_built_utc", _base.built_utc()))
	m.refreshed_products = names
	var text := JSON.stringify(m, "\t", false, true)
	if not _write(incoming.path_join("manifest.json.part"), text.to_utf8_buffer()):
		_remove_tree(incoming)
		return "could not write the manifest"
	DirAccess.rename_absolute(incoming.path_join("manifest.json.part"), incoming.path_join("manifest.json"))
	var check := WeatherArchive.load_dir(incoming, "cache")
	if not check.ok:
		_remove_tree(incoming)
		return "; ".join(check.problems)
	var current := WeatherArchive.current_dir()
	var previous := WeatherArchive.previous_dir()
	_remove_tree(previous)
	if DirAccess.dir_exists_absolute(current) and DirAccess.rename_absolute(current, previous) != OK:
		_remove_tree(incoming)
		return "the current cache could not be moved aside"
	if DirAccess.rename_absolute(incoming, current) != OK:
		if DirAccess.dir_exists_absolute(previous):
			DirAccess.rename_absolute(previous, current)
		_remove_tree(incoming)
		return "the new data could not be put in place"
	WeatherArchive.invalidate()
	return ""


func _finish(words: String, ok: bool) -> void:
	var now := float(now_func.call())
	if ok:
		failures = 0
		next_check_at = now + config.refresh_hours * 3600.0
	else:
		failures += 1
		next_check_at = now + retry_minutes(failures) * 60.0
	busy = false
	var active := WeatherArchive.active()
	var published: Dictionary = _status.get("published_updates", {})
	_status = {"published_updates": published, "last_check_unix": now, "last_check_utc": Time.get_datetime_string_from_unix_time(int(now), false) + "Z", "last_result": words,
		"last_ok": ok, "failures": failures, "next_check_unix": next_check_at, "next_check_in_minutes": (next_check_at - now) / 60.0,
		"cache_snapshot": active.snapshot_id(), "cache_source": active.source, "observation_period": active.observation_period()}
	DirAccess.make_dir_recursive_absolute(WeatherArchive.cache_root())
	_write(WeatherArchive.cache_root().path_join(STATUS_FILE), JSON.stringify(_status, "\t", false, true).to_utf8_buffer())
	status_changed.emit(status())


## Real minutes to wait after `n` failures in a row: 1, 2, 4 ... at most retry_cap_minutes.
func retry_minutes(n: int) -> float:
	return minf(config.retry_cap_minutes, config.retry_first_minutes * pow(2.0, float(maxi(0, n - 1))))


static func _error_words(error: String) -> String:
	match error:
		"timeout": return "no answer in time (timeout)"
		"oversize": return "the file is larger than allowed, the download was stopped"
		"connection": return "no connection to the archive (offline?)"
		"interrupted": return "the download was interrupted and is incomplete"
	return error


static func _sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


static func _write(path: String, bytes: PackedByteArray) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	return true


## Deletes a folder and everything in it (no-op if it does not exist).
static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
