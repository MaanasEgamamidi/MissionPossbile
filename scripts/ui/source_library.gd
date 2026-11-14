class_name SourceLibrary
extends RefCounted
## The game's source register, claims, explanations and credits, read once from res://data/*.json.
## Works fully offline: nothing here goes to the network. The only way out of the game is open_url(), and only
## when the player presses "Open in browser".
##
## Status words (from docs/source_register.md, "How to read it"):
## VERIFIED and PARTIAL pages were opened and may be cited; SEARCH-ONLY and FAILED pages were not opened and are
## shown as "not yet checked", never as a citation.

const SOURCES_PATH := "res://data/sources.json"
const CLAIMS_PATH := "res://data/claims.json"
const EXPLANATIONS_PATH := "res://data/explanations.json"
const CREDITS_PATH := "res://data/credits.json"

const MONTHS: PackedStringArray = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

## Source category -> words for the player (also the register's category filter names).
const CATEGORY_WORDS := {
	"measured": "Measured on Mars",
	"modelled": "Models",
	"analog": "ISS and Earth tests",
	"technology": "Technology",
	"fiction": "Fiction",
	"tuning": "Game balance",
	"engine": "Engine and tools",
}

## When set, open_url() calls this instead of OS.shell_open (tests replace it so no browser opens).
static var open_url_hook: Callable = Callable()

static var _loaded := false
static var _sources: Array[Dictionary] = []
static var _sources_by_id: Dictionary = {}
static var _claims: Array[Dictionary] = []
static var _claims_by_id: Dictionary = {}
static var _credits: Array[Dictionary] = []
static var _explanations: Dictionary = {}


## Every entry of the register (S, T, M and L ids), in register order.
static func sources() -> Array[Dictionary]:
	_ensure_loaded()
	return _sources


## One register entry by id ("S01"); empty if unknown.
static func source(id: String) -> Dictionary:
	_ensure_loaded()
	return _sources_by_id.get(id, {})


## Every factual statement the game shows.
static func claims() -> Array[Dictionary]:
	_ensure_loaded()
	return _claims


## One claim by id ("gravity"); empty if unknown.
static func claim(id: String) -> Dictionary:
	_ensure_loaded()
	return _claims_by_id.get(id, {})


## Credits: engine, tools, assets and science sources.
static func credits() -> Array[Dictionary]:
	_ensure_loaded()
	return _credits


## All plain-language explanations, keyed by explanation id.
static func explanations() -> Dictionary:
	_ensure_loaded()
	return _explanations


## True for a source that may be shown as a citation (its page was opened: VERIFIED or PARTIAL).
static func is_citable(src: Dictionary) -> bool:
	var status := String(src.get("status", ""))
	return status == "VERIFIED" or status == "PARTIAL"


## How well a source was checked, in plain words.
static func status_text(src: Dictionary) -> String:
	match String(src.get("status", "")):
		"VERIFIED":
			var date := date_text(String(src.get("checked_on", "")))
			return "Checked on " + date if date != "" else "Checked"
		"PARTIAL":
			return "Partly checked"
		"SEARCH-ONLY":
			return "Not yet checked"
		"FAILED":
			return "Could not be opened"
	return "Not yet checked"


## "2026-11-11" -> "11 Nov 2026"; empty if the text is not a date.
static func date_text(iso: String) -> String:
	var parts := iso.split("-")
	if parts.size() != 3 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return ""
	var month := parts[1].to_int()
	if month < 1 or month > 12:
		return ""
	return "%d %s %s" % [parts[2].to_int(), MONTHS[month - 1], parts[0]]


## Words for a source category ("measured" -> "Measured on Mars").
static func category_text(category: String) -> String:
	return String(CATEGORY_WORDS.get(category, "Not known"))


## Sources of a claim that may be shown as citations.
static func citable_sources_of(c: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sid: Variant in c.get("source_ids", []):
		var src := source(String(sid))
		if not src.is_empty() and is_citable(src):
			out.append(src)
	return out


## True when a claim about the real world has no checked source yet (shown as "source not yet checked").
static func is_unsourced(c: Dictionary) -> bool:
	return String(c.get("category", "")) == "archive" and citable_sources_of(c).is_empty()


## What kind of fact a claim is, in words: "measured on Mars", "ISS or Earth test", "game time",
## "made up for the game", "game balance" or "source not yet checked".
static func claim_category_text(c: Dictionary) -> String:
	match String(c.get("category", "")):
		"game_time":
			return "game time"
		"fiction":
			return "made up for the game"
		"balance":
			return "game balance"
		"archive":
			var cited := citable_sources_of(c)
			if cited.is_empty():
				return "source not yet checked"
			match String(cited[0].get("category", "")):
				"measured":
					return "measured on Mars"
				"modelled":
					return "worked out from Mars data"
				"analog":
					return "ISS or Earth test"
				"technology":
					return "technology test"
				"engine":
					return "engine test"
			return "from a NASA page"
	return "not known"


## Register filter categories a claim belongs to (the categories of its sources and leads, or its own kind).
static func claim_filter_categories(c: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	match String(c.get("category", "")):
		"game_time", "balance":
			out.append("tuning")
		"fiction":
			out.append("fiction")
		"archive":
			for sid: Variant in c.get("source_ids", []) + c.get("lead_ids", []):
				var cat := String(source(String(sid)).get("category", ""))
				if cat != "" and not out.has(cat):
					out.append(cat)
	return out


## Claims that cite a source or name it as a lead.
static func claims_using(source_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Dictionary in claims():
		if (c.get("source_ids", []) as Array).has(source_id) or (c.get("lead_ids", []) as Array).has(source_id):
			out.append(c)
	return out


## True for a well-formed https:// address with a host name and no spaces.
static func is_safe_url(url: String) -> bool:
	var re := RegEx.create_from_string("^https://[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+(/[^\\s<>\"]*)?$")
	return re.search(url) != null


## Opens an https:// address in the player's web browser. Call only when the player pressed a button.
## Returns false (and does nothing) for anything that is not a safe https:// address.
static func open_url(url: String) -> bool:
	if not is_safe_url(url):
		return false
	if open_url_hook.is_valid():
		open_url_hook.call(url)
	else:
		OS.shell_open(url)
	return true


## Forgets the loaded data so the next call reads the files again.
static func reload() -> void:
	_loaded = false
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_sources.clear()
	_sources_by_id.clear()
	_claims.clear()
	_claims_by_id.clear()
	_credits.clear()
	var src_data := _read_json(SOURCES_PATH)
	for item: Variant in src_data.get("sources", []):
		if item is Dictionary:
			_sources.append(item)
			_sources_by_id[String(item.get("id", ""))] = item
	var claim_data := _read_json(CLAIMS_PATH)
	for item: Variant in claim_data.get("claims", []):
		if item is Dictionary:
			_claims.append(item)
			_claims_by_id[String(item.get("id", ""))] = item
	var credit_data := _read_json(CREDITS_PATH)
	for item: Variant in credit_data.get("credits", []):
		if item is Dictionary:
			_credits.append(item)
	_explanations = _read_json(EXPLANATIONS_PATH)


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("SourceLibrary: missing " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_warning("SourceLibrary: could not read " + path)
	return {}
