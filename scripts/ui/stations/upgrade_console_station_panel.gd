extends StationPanel
## The upgrade console of an area that has no station of its own (the Garden dome, data/stations_upgrades.json):
## the header, one short description and the "Upgrades" strip that StationPanel adds for the track it serves.


func _shows_later_note() -> bool:
	return false


func _title_text() -> String:
	if services != null and services.has_game():
		var record: Dictionary = services.state().stations.get(String(station_id), {})
		if record.has("name"):
			return String(record.name)
	return super._title_text()


func panel_title() -> String:
	return _title_text()


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["Each level adds more to this area, and it does more for the colony."])


## The console's one short line ("Plant more of the Garden dome.") above its upgrade strip.
func _build_body() -> void:
	var record: Dictionary = services.state().stations.get(String(station_id), {}) if services != null else {}
	_add_text(_body, String(record.get("description", "Upgrade this area.")))
