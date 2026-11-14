class_name DataSnapshot
extends Resource
## A dated copy of outside data (for example a weather product) that the game runs on, so play never depends on a
## live connection and a save can say exactly which data it was using (ColonyState.data_snapshot_id).
## INTERFACE ONLY: the data-refresh milestone fills these in and decides the final fields.

@export var id := ""
## SourceRecord id the data came from.
@export var source_id: StringName = &""
## When the data was fetched and what period it covers, ISO 8601.
@export var fetched_on := ""
@export var covers_from := ""
@export var covers_to := ""
## True if this is the copy shipped with the game rather than a refreshed one.
@export var bundled := true
## The data itself, in plain JSON types.
@export var values := {}
