class_name SourceRecord
extends Resource
## One entry of the in-game source register (Shift + Backspace): where a fact shown to the player comes from.
## INTERFACE ONLY: the data and register milestones fill these in. Ids match docs/source_register.md (S01, S02, ...).

@export var id: StringName = &""
@export var title := ""
@export var publisher := ""
@export var url := ""
## Date the page or product was last opened and checked, ISO 8601 (YYYY-MM-DD).
@export var checked_on := ""
## What kind of statement this supports: "measurement", "mission_fact", "model", "analog_study", "game_fiction".
@export var kind := ""
## Plain-language note of exactly what was taken from the source, and any limit on its use.
@export_multiline var note := ""
