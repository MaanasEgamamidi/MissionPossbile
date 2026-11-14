class_name SaveMigrations
extends RefCounted
## Sequential, in-memory upgrades of saved payloads.

## Schema written by this game.
var current_version: int = 1
## Source version mapped to a callable that advances one version.
var steps: Dictionary = {}

## Register one version upgrade.
func register(from_version: int, step: Callable) -> void:
	steps[from_version] = step

## Whether all upgrades to the current version exist.
func can_migrate(from_version: int) -> bool:
	if from_version > current_version:
		return false
	for version: int in range(from_version, current_version):
		if not steps.has(version) or not steps[version] is Callable:
			return false
		var step: Callable = steps[version]
		if not step.is_valid():
			return false
	return true

## Upgrade a deep copy; return an empty dictionary if no path exists.
func migrate(payload: Dictionary, from_version: int) -> Dictionary:
	if not can_migrate(from_version):
		return {}
	var migrated: Dictionary = payload.duplicate(true)
	for version: int in range(from_version, current_version):
		var step: Callable = steps[version]
		migrated = step.call(migrated)
	return migrated
