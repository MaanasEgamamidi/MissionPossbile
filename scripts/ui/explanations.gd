class_name Explanations
extends RefCounted
## Plain-language explanations of readings and ideas, read from res://data/explanations.json through SourceLibrary.
## Other panels show them with an ExplainButton ("?").


## {"title": String, "short": String, "long": String, "source_ids": PackedStringArray,
##  "claim_ids": PackedStringArray, "category": String}; empty if the id is unknown.
## "category" is the category of the first linked claim (archive, game_time, fiction, balance), or "" if none.
static func get_entry(id: String) -> Dictionary:
	var all := SourceLibrary.explanations()
	if not all.has(id) or not (all[id] is Dictionary):
		return {}
	var raw: Dictionary = all[id]
	var claim_ids := _strings(raw.get("claim_ids", []))
	var category := ""
	if not claim_ids.is_empty():
		category = String(SourceLibrary.claim(claim_ids[0]).get("category", ""))
	return {
		"id": id,
		"title": String(raw.get("title", "")),
		"short": String(raw.get("short", "")),
		"long": String(raw.get("long", "")),
		"source_ids": _strings(raw.get("source_ids", [])),
		"claim_ids": claim_ids,
		"category": category,
	}


## Every explanation id, sorted.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for key: Variant in SourceLibrary.explanations().keys():
		out.append(String(key))
	out.sort()
	return out


static func _strings(list: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if list is Array:
		for item: Variant in list:
			out.append(String(item))
	return out
