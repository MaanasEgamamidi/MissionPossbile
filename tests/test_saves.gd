extends SceneTree
## Disk-based checks for save integrity, recovery and migration.

var _passed: int = 0
var _total: int = 0
var _service: SaveService
var _payload: Dictionary

func _initialize() -> void:
	# Other verification tools also write under _test_saves; exact-file assertions own this subdirectory only.
	_service = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/save_integrity"))
	_payload = _make_payload()
	_fresh()
	_check("fresh start", _service.read().status == &"no_save" and not _service.has_save())
	_round_trip()
	_rotation()
	_interrupted()
	_truncated()
	_temporary()
	_bit_rot()
	_damaged()
	_schema()
	_migration()
	_offline()
	_validation()
	_awkward_numbers()
	_service.delete_all()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)

func _check(label: String, condition: bool, detail: String = "unexpected result") -> void:
	_total += 1
	if condition:
		_passed += 1
		print("PASS " + label)
	else:
		print("FAIL %s: %s" % [label, detail])

func _fresh() -> void:
	_service.delete_all()
	_service.fail_after_bytes = -1
	_service.migrations = SaveMigrations.new()

func _make_payload() -> Dictionary:
	var colony: ColonyState = ColonyState.new_game(GameBalance.new(), 12345, PackedStringArray(["Power Room", "Life Support"]))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = colony.rng_seed
	for index: int in range(17):
		rng.randi()
	colony.rng_state = rng.state
	colony.stores[&"battery_kwh"] = 173.1234567890123
	colony.ledger["water_used_l"] = 0.000123456789
	colony.character(&"crew_1").owner_peer = 1
	colony.character(&"crew_1").health = 71.23456789
	colony.character(&"crew_1").position = Vector3(1.25, -2.5, 3.75)
	colony.character(&"crew_1").equipment = [&"scanner"]
	colony.character(&"crew_1").cargo = [&"tool"]
	colony.items = {
		"tool": {"kind": "tool", "position": [1.25, -2.5, 3.75], "holder": "crew_1"},
		"ore": {"kind": "ore", "position": [11.125, 0.25, -19.75], "holder": "cache:cache_0"},
		"crate": {"kind": "crate", "position": [-5.125, 0.125, 9.75], "holder": ""},
	}
	colony.caches = [{"id": "cache_0", "position": [11.125, 0.25, -19.75], "items": ["ore"]}]
	colony.counters["cache"] = 1
	colony.character(&"crew_1").display_name = "Engineer — 火星"
	var clock_value: SolClock = SolClock.new()
	clock_value.advance(123.456789)
	return {"clock": clock_value.to_dict(), "colony": colony.to_dict(), "session": {"host_character": "crew_1"}}

func _round_trip() -> void:
	_fresh()
	_check("round trip write", _service.write(_payload) == OK and _service.has_save())
	var result: SaveLoadResult = _service.read()
	_check("round trip status", result.status == &"ok" and result.source_path == _service.main_path() and result.schema == 1 and result.migrated_from == -1 and result.problems.is_empty())
	if not result.is_usable():
		return
	var restored: ColonyState = ColonyState.from_dict(result.payload.colony)
	var normalized_original: Variant = JSON.parse_string(JSON.stringify(_payload.colony, "", true, true))
	var normalized_restored: Variant = JSON.parse_string(JSON.stringify(restored.to_dict(), "", true, true))
	_check("colony deep round trip", normalized_original == normalized_restored)
	_check("whole payload round trip", SaveService.canonical_text(result.payload) == SaveService.canonical_text(_payload))
	_check("64-bit RNG state string", result.payload.colony.rng_state is String and result.payload.colony.rng_state == _payload.colony.rng_state and absi(restored.rng_state) > 9007199254740992)
	var original_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	original_rng.seed = int(_payload.colony.rng_seed)
	original_rng.state = int(_payload.colony.rng_state)
	var restored_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	restored_rng.seed = restored.rng_seed
	restored_rng.state = restored.rng_state
	var same: bool = true
	for index: int in range(20):
		if original_rng.randi() != restored_rng.randi():
			same = false
	_check("RNG next 20 numbers", same)

func _versioned(number: int) -> Dictionary:
	var payload: Dictionary = _payload.duplicate(true)
	payload["revision"] = number
	return payload

func _rotation() -> void:
	_fresh()
	var writes_ok: bool = true
	for number: int in range(1, 6):
		if _service.write(_versioned(number)) != OK:
			writes_ok = false
	_check("five writes", writes_ok)
	_check("rotation main fifth", _service.read().payload.get("revision") == 5)
	_check("rotation bak1 fourth", _service.validate_text(FileAccess.get_file_as_string(_service.backup_path(1))).payload.get("revision") == 4)
	_check("rotation bak2 third", _service.validate_text(FileAccess.get_file_as_string(_service.backup_path(2))).payload.get("revision") == 3)
	var files: PackedStringArray = DirAccess.get_files_at(_service.directory)
	files.sort()
	_check("rotation exact files", files == PackedStringArray(["colony.bak1.json", "colony.bak2.json", "colony.json"]))

func _interrupted() -> void:
	_fresh()
	_check("interrupted setup", _service.write(_payload) == OK)
	var old_bytes: PackedByteArray = FileAccess.get_file_as_bytes(_service.main_path())
	_service.fail_after_bytes = 100
	_check("interrupted write error and 100 bytes", _service.write(_versioned(2)) == ERR_FILE_CANT_WRITE and FileAccess.get_file_as_bytes(_service.temp_path()).size() == 100)
	var result: SaveLoadResult = _service.read()
	_check("interrupted preserves old main", result.status == &"ok" and SaveService.canonical_text(result.payload) == SaveService.canonical_text(_payload) and old_bytes == FileAccess.get_file_as_bytes(_service.main_path()))
	_service.fail_after_bytes = -1
	_check("normal write after interruption", _service.write(_versioned(3)) == OK and _service.read().payload.get("revision") == 3 and not FileAccess.file_exists(_service.temp_path()))

func _two_saves() -> void:
	_fresh()
	var first: Error = _service.write(_versioned(1))
	var second: Error = _service.write(_versioned(2))
	_check("recovery setup", first == OK and second == OK)

func _truncated() -> void:
	_two_saves()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(_service.main_path())
	_put_bytes(_service.main_path(), bytes.slice(0, bytes.size() / 2))
	var result: SaveLoadResult = _service.read()
	_check("truncated main recovers bak1", result.status == &"recovered_from_backup" and result.source_path == _service.backup_path(1) and SaveService.canonical_text(result.payload) == SaveService.canonical_text(_versioned(1)))
	_check("truncated main problem named", result.problems.size() == 1 and result.problems[0].contains(_service.main_path()))

func _temporary() -> void:
	_two_saves()
	_check("move main to temp", DirAccess.rename_absolute(_service.main_path(), _service.temp_path()) == OK)
	var before: Dictionary = _snapshot()
	var result: SaveLoadResult = _service.read()
	_check("complete temp beats backup", result.status == &"recovered_from_backup" and result.source_path == _service.temp_path() and result.payload.get("revision") == 2 and _snapshot() == before)

func _bit_rot() -> void:
	_two_saves()
	var text: String = FileAccess.get_file_as_string(_service.main_path())
	var damaged: String = text.replace('"revision": 2', '"revision": 9')
	_check("bit rot changes one digit in valid JSON", damaged != text and damaged.length() == text.length() and JSON.parse_string(damaged) is Dictionary)
	_put_text(_service.main_path(), damaged)
	var result: SaveLoadResult = _service.read()
	_check("bit rot falls back", result.status == &"recovered_from_backup" and result.source_path == _service.backup_path(1) and result.payload.get("revision") == 1 and result.problems.size() == 1 and result.problems[0].contains("Checksum mismatch"))

func _damaged() -> void:
	_fresh()
	for path: String in [_service.main_path(), _service.temp_path(), _service.backup_path(1), _service.backup_path(2)]:
		_put_text(path, "{broken")
	var before: Dictionary = _snapshot()
	var result: SaveLoadResult = _service.read()
	_check("all damaged corrupt", result.status == &"corrupt" and result.payload.is_empty() and result.problems.size() == 4 and not result.is_usable())
	_check("damaged files untouched", before == _snapshot())

func _envelope(schema: int) -> Dictionary:
	return {"format": SaveService.FORMAT, "schema": schema, "game_version": "0.3.0", "saved_at_unix": int(Time.get_unix_time_from_system()), "reason": "test", "checksum": SaveService.checksum(_payload), "payload": _payload.duplicate(true)}

func _schema() -> void:
	_fresh()
	_put_text(_service.main_path(), JSON.stringify(_envelope(99), "\t", true, true))
	var before: Dictionary = _snapshot()
	var result: SaveLoadResult = _service.read()
	_check("newer schema refused untouched", result.status == &"unsupported_schema" and result.schema == 99 and result.payload.is_empty() and _snapshot() == before)
	_put_text(_service.temp_path(), "bad")
	_check("unsupported wins over corruption", _service.read().status == &"unsupported_schema" and _service.read().schema == 99)
	_fresh()
	_put_text(_service.main_path(), JSON.stringify(_envelope(0), "\t", true, true))
	result = _service.read()
	_check("older schema without path", result.status == &"unsupported_schema" and result.schema == 0 and result.payload.is_empty())

func _migration() -> void:
	_fresh()
	_check("migration setup", _service.write(_payload) == OK)
	var before: PackedByteArray = FileAccess.get_file_as_bytes(_service.main_path())
	var upgrades: SaveMigrations = SaveMigrations.new()
	upgrades.current_version = 2
	upgrades.register(1, func(payload: Dictionary) -> Dictionary:
		payload["new_field"] = true
		payload.session["upgraded"] = true
		return payload)
	_service.migrations = upgrades
	_check("migration paths", upgrades.can_migrate(1) and upgrades.can_migrate(2) and not upgrades.can_migrate(0) and not upgrades.can_migrate(3))
	var copy: Dictionary = upgrades.migrate(_payload, 1)
	_check("migration deep copy", copy.has("new_field") and not _payload.has("new_field") and not _payload.session.has("upgraded"))
	var result: SaveLoadResult = _service.read()
	_check("migration in memory", result.status == &"ok" and result.schema == 1 and result.migrated_from == 1 and result.payload.get("new_field") == true and before == FileAccess.get_file_as_bytes(_service.main_path()))
	_check("migration next write", _service.write(result.payload) == OK)
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_service.main_path()))
	_check("migration schema 2 and original backup", envelope.schema == 2 and before == FileAccess.get_file_as_bytes(_service.backup_path(1)) and _service.read().migrated_from == -1)

func _offline() -> void:
	_fresh()
	_check("offline setup", _service.write(_payload) == OK)
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_service.main_path()))
	envelope.saved_at_unix = int(Time.get_unix_time_from_system()) - 10 * 24 * 60 * 60
	envelope.checksum = SaveService.checksum(envelope.payload)
	_put_text(_service.main_path(), JSON.stringify(envelope, "\t", true, true))
	var result: SaveLoadResult = _service.read()
	_check("no offline effect", result.status == &"ok" and SaveService.canonical_text(result.payload).to_utf8_buffer() == SaveService.canonical_text(_payload).to_utf8_buffer())

func _validation() -> void:
	_fresh()
	_check("invalid JSON rejected", _service.validate_text("{").status == &"corrupt")
	_check("non-dictionary rejected", _service.validate_text("[]").status == &"corrupt")
	for field: String in ["format", "schema", "game_version", "saved_at_unix", "reason", "checksum", "payload"]:
		var envelope: Dictionary = _envelope(1)
		envelope.erase(field)
		_check("missing " + field, _service.validate_text(JSON.stringify(envelope)).status == &"corrupt")
	var wrong: Dictionary = _envelope(1)
	wrong.format = "other"
	_check("wrong format rejected", _service.validate_text(JSON.stringify(wrong)).status == &"corrupt")
	wrong = _envelope(1)
	wrong.payload = []
	_check("non-dictionary payload rejected", _service.validate_text(JSON.stringify(wrong)).status == &"corrupt")
	wrong = _envelope(99)
	wrong.checksum = "wrong"
	_check("checksum checked before schema", _service.validate_text(JSON.stringify(wrong)).status == &"corrupt")
	_check("canonical numeric and key normalization", SaveService.canonical_text({"b": 2, "a": 1.0}) == SaveService.canonical_text({"a": 1, "b": 2.0}))
	_service.backup_count = 0
	var first: Error = _service.write(_versioned(1))
	var second: Error = _service.write(_versioned(2))
	_check("zero backups", first == OK and second == OK and _service.read().payload.get("revision") == 2 and DirAccess.get_files_at(_service.directory).size() == 1)
	_service.delete_all()
	_service.backup_count = 2
	_check("delete all", not _service.has_save() and DirAccess.get_files_at(_service.directory).is_empty())

## Regression: numbers Godot's JSON parser does not carry exactly must not make a save reject itself.
func _awkward_numbers() -> void:
	_fresh()
	var payload := _make_payload()
	payload["awkward"] = [-7.99588829278946e-25, 6.985346078872681e-25, 9.546275e-25, 5e-324, 1e-300, 1e300, -0.0,
		float(Vector3(0.1, 0, 0).x), 3.6e-17, 123456789012345680.0, 1.0 / 3.0]
	var first := _service.write(payload)
	var loaded := _service.read()
	_check("awkward numbers: save accepted and loads", first == OK and loaded.status == &"ok", "%s %s %s" % [error_string(first), loaded.status, loaded.problems])
	var again := _service.write(loaded.payload)
	var reloaded := _service.read()
	_check("awkward numbers: a loaded game saves and loads again", again == OK and reloaded.status == &"ok", "%s %s" % [error_string(again), reloaded.status])
	var worst := 0.0
	for i: int in (payload["awkward"] as Array).size():
		var a: float = payload["awkward"][i]
		var b: float = reloaded.payload["awkward"][i]
		if a != 0.0:
			worst = maxf(worst, absf(b - a) / absf(a))
	_check("awkward numbers: values within 1e-12 relative after two save/load cycles", worst < 1e-12, "worst relative error %s" % worst)

func _put_text(path: String, text: String) -> void:
	_put_bytes(path, text.to_utf8_buffer())

func _put_bytes(path: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check("test fixture write", false, path)
		return
	file.store_buffer(bytes)
	file.close()

func _snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for name: String in DirAccess.get_files_at(_service.directory):
		snapshot[name] = FileAccess.get_file_as_bytes(_service.directory.path_join(name))
	return snapshot
