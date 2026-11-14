class_name CassetteCatalog
extends RefCounted
## Public inventory metadata. Instructional text is presented only after host playback authorization.

const PLAYER_ID := "cassette_player_command_center"
const DATA_PATH := "res://data/cassette_briefings.json"
const PLAY_INSTRUCTION := "Play at Command Room cassette player."
const TAPES := {
	"cassette_command_center": {"room_id": "command_center", "title": "Command center", "code": "CMD", "color": "f1a35e"},
	"cassette_power_supply": {"room_id": "power_supply", "title": "Power supply", "code": "PWR", "color": "e6c85e"},
	"cassette_greenhouse": {"room_id": "greenhouse", "title": "Greenhouse", "code": "GRH", "color": "79c788"},
	"cassette_green_dome": {"room_id": "green_dome", "title": "Green dome", "code": "DOME", "color": "54c9c3"},
	"cassette_med_bay": {"room_id": "med_bay", "title": "Med Bay", "code": "MED", "color": "e997aa"},
	"cassette_hangar": {"room_id": "hangar", "title": "Hangar / airlock", "code": "AIR", "color": "8faaf0"},
}

static func metadata(cassette_id: String) -> Dictionary:
	if not TAPES.has(cassette_id) or not FileAccess.file_exists(DATA_PATH):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not data is Dictionary or not data.get("cassettes", null) is Array:
		return {}
	for candidate: Variant in data.cassettes:
		if not candidate is Dictionary or String(candidate.get("id", "")) != cassette_id:
			continue
		if String(candidate.get("room_id", "")) != String(TAPES[cassette_id].room_id):
			return {}
		var pages: Variant = candidate.get("pages", null)
		if not pages is Array or pages.is_empty():
			return {}
		for page: Variant in pages:
			if not page is String or String(page).strip_edges().is_empty():
				return {}
		var image_path := String(candidate.get("image_path", ""))
		if not image_path.begins_with("res://assets/cassettes/") or not (ResourceLoader.exists(image_path) or FileAccess.file_exists(image_path)):
			return {}
		return candidate.duplicate(true)
	return {}

static func page_count(cassette_id: String) -> int:
	var record := metadata(cassette_id)
	return (record.get("pages", []) as Array).size()

static func collected(state: ColonyState, cassette_id: String) -> bool:
	return TAPES.has(cassette_id) and (state.repair.get("collected_cassettes", []) as Array).has(cassette_id)
