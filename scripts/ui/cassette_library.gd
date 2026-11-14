class_name CassetteLibrary
extends RefCounted
## Inventory uses canonical titles only. Briefings/photos are loaded by the player after host approval.

const PATH := "res://data/cassette_briefings.json"
const PLAYER_ID := &"cassette_player_command_center"


static func metadata() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for id: String in CassetteCatalog.TAPES:
		var tape: Dictionary = CassetteCatalog.TAPES[id]
		records.append({"id": id, "room_id": String(tape.room_id), "title": String(tape.title)})
	return records


static func details(cassette_id: String) -> Dictionary:
	return CassetteCatalog.metadata(cassette_id)
