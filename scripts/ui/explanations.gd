class_name Explanations
extends RefCounted
## STUB owned by worker B. Plain-language explanations of readings and ideas, loaded from res://data/explanations.json.


## {"title": String, "short": String, "long": String, "source_ids": PackedStringArray, "category": String}; empty if unknown.
static func get_entry(_id: String) -> Dictionary:
	return {}


static func ids() -> PackedStringArray:
	return PackedStringArray()
