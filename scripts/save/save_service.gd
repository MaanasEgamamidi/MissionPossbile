class_name SaveService
extends RefCounted
## Checksummed saves with a temporary file and rotating backups.

## Envelope identifier.
const FORMAT: String = "mars_colony_save"
## Directory containing this save family.
var directory: String = "user://saves"
## Filename stem.
var save_name: String = "colony"
## Number of older saves retained.
var backup_count: int = 2
## Supported schema and upgrade steps.
var migrations: SaveMigrations
## Game version for display.
var game_version: String = "0.3.0"
## Test hook: interrupt a write after this many bytes; -1 disables it.
var fail_after_bytes: int = -1

func _init(p_directory: String = "user://saves", p_save_name: String = "colony", p_backup_count: int = 2, p_migrations: SaveMigrations = null) -> void:
	directory = p_directory
	save_name = p_save_name
	backup_count = maxi(0, p_backup_count)
	migrations = p_migrations if p_migrations != null else SaveMigrations.new()

## Main save filename.
func main_path() -> String:
	return directory.path_join(save_name + ".json")

## In-progress save filename.
func temp_path() -> String:
	return main_path() + ".tmp"

## Backup filename, starting at 1 for the newest backup.
func backup_path(index: int) -> String:
	return directory.path_join("%s.bak%d.json" % [save_name, index])

## Text of a payload as a reader will see it: written once, parsed once (so ints and floats print alike), written again.
static func canonical_text(payload: Dictionary) -> String:
	return parsed_text(JSON.parse_string(JSON.stringify(payload, "", true, true)))

## Text of a payload that has ALREADY been parsed from JSON. No further round trip:
## Godot's JSON parser does not read every number back exactly (seen for magnitudes around 1e-25: each
## parse-and-print moves the last digits), so a second round trip would not reproduce the writer's text.
static func parsed_text(parsed_payload: Dictionary) -> String:
	return JSON.stringify(parsed_payload, "", true, true)

## Checksum to store with a payload that is about to be written: SHA-256 of what a reader will reconstruct.
## Writer: checksum(payload) = hash(print(parse(print(payload)))). Reader: hash(print(parse(file))). Same text by construction.
static func checksum(payload: Dictionary) -> String:
	return canonical_text(payload).sha256_text()

## Write and verify a temporary save before rotating backups and replacing main.
func write(payload: Dictionary, reason: StringName = &"manual") -> Error:
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error
	var envelope: Dictionary = {
		"format": FORMAT, "schema": migrations.current_version, "game_version": game_version,
		# Display only; never used to advance the simulation offline.
		"saved_at_unix": int(Time.get_unix_time_from_system()), "reason": String(reason),
		"checksum": checksum(payload), "payload": payload,
	}
	var bytes: PackedByteArray = JSON.stringify(envelope, "\t", true, true).to_utf8_buffer()
	var file: FileAccess = FileAccess.open(temp_path(), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	if fail_after_bytes >= 0:
		file.store_buffer(bytes.slice(0, mini(fail_after_bytes, bytes.size())))
		file.close()
		return ERR_FILE_CANT_WRITE
	file.store_buffer(bytes)
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK or not _read_file(temp_path()).is_usable():
		DirAccess.remove_absolute(temp_path())
		return error if error != OK else ERR_FILE_CORRUPT
	if backup_count > 0:
		if FileAccess.file_exists(backup_path(backup_count)):
			error = DirAccess.remove_absolute(backup_path(backup_count))
			if error != OK:
				return error
		for index: int in range(backup_count - 1, 0, -1):
			if FileAccess.file_exists(backup_path(index)):
				error = DirAccess.rename_absolute(backup_path(index), backup_path(index + 1))
				if error != OK:
					return error
		if FileAccess.file_exists(main_path()):
			error = DirAccess.copy_absolute(main_path(), backup_path(1))
			if error != OK:
				return error
	# On Windows rename removes the destination first, briefly leaving no main.
	# Reads therefore also try the complete temporary file and the backups.
	return DirAccess.rename_absolute(temp_path(), main_path())

## Find the first usable main, temporary, or backup file without changing disk.
func read() -> SaveLoadResult:
	var result: SaveLoadResult = SaveLoadResult.new()
	result.status = &"no_save"
	var unsupported: bool = false
	for path: String in _paths():
		if not FileAccess.file_exists(path):
			continue
		var candidate: SaveLoadResult = _read_file(path)
		if candidate.is_usable():
			candidate.status = &"ok" if path == main_path() else &"recovered_from_backup"
			candidate.problems = result.problems
			return candidate
		result.problems.append("%s: %s" % [path, "; ".join(candidate.problems)])
		if candidate.status == &"unsupported_schema":
			unsupported = true
		if not unsupported or candidate.status == &"unsupported_schema":
			result.schema = candidate.schema
			result.source_path = path
		result.status = &"unsupported_schema" if unsupported else &"corrupt"
	return result

## Whether any save candidate exists, even if damaged.
func has_save() -> bool:
	for path: String in _paths():
		if FileAccess.file_exists(path):
			return true
	return false

## Delete this save's main, temporary file and configured backups.
func delete_all() -> void:
	for path: String in _paths():
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

## Validate the stored checksum before applying any schema upgrades.
func validate_text(text: String) -> SaveLoadResult:
	var result: SaveLoadResult = SaveLoadResult.new()
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _reject(result, "Invalid JSON: " + json.get_error_message())
	if not json.data is Dictionary:
		return _reject(result, "Envelope is not a dictionary")
	var envelope: Dictionary = json.data
	for field: String in ["format", "schema", "game_version", "saved_at_unix", "reason", "checksum", "payload"]:
		if not envelope.has(field):
			return _reject(result, "Missing field: " + field)
	if not _is_integer(envelope.schema):
		return _reject(result, "Schema is not an integer")
	result.schema = int(envelope.schema)
	if envelope.format != FORMAT:
		return _reject(result, "Wrong format")
	if not envelope.game_version is String or not envelope.reason is String or not _is_integer(envelope.saved_at_unix):
		return _reject(result, "Invalid metadata")
	if not envelope.payload is Dictionary:
		return _reject(result, "Payload is not a dictionary")
	if not envelope.checksum is String or envelope.checksum != parsed_text(envelope.payload).sha256_text():
		return _reject(result, "Checksum mismatch")
	if not migrations.can_migrate(result.schema):
		result.status = &"unsupported_schema"
		return _reject(result, "Unsupported schema: %d" % result.schema)
	result.payload = envelope.payload
	if result.schema < migrations.current_version:
		result.payload = migrations.migrate(result.payload, result.schema)
		result.migrated_from = result.schema
	result.status = &"ok"
	return result

func _paths() -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray([main_path(), temp_path()])
	for index: int in range(1, backup_count + 1):
		paths.append(backup_path(index))
	return paths

func _read_file(path: String) -> SaveLoadResult:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var result: SaveLoadResult
	if file == null:
		result = _reject(SaveLoadResult.new(), "Cannot open file: %s" % FileAccess.get_open_error())
	else:
		result = validate_text(file.get_as_text())
		file.close()
	result.source_path = path
	return result

func _reject(result: SaveLoadResult, problem: String) -> SaveLoadResult:
	result.problems.append(problem)
	return result

func _is_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))
