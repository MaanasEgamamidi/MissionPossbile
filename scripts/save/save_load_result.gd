class_name SaveLoadResult
extends RefCounted
## Outcome of validating or finding a save.

## Load outcome; only ok and recovered_from_backup carry a payload.
var status: StringName = &"corrupt"
## Validated and, when needed, migrated game data.
var payload: Dictionary = {}
## File used or rejected.
var source_path: String = ""
## Schema stored in that file.
var schema: int = -1
## Original schema when migration ran, otherwise -1.
var migrated_from: int = -1
## One explanation per rejected file.
var problems: PackedStringArray = PackedStringArray()

## Whether game data can be loaded.
func is_usable() -> bool:
	return status == &"ok" or status == &"recovered_from_backup"
