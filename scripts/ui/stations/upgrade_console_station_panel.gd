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
	var record: Dictionary = services.state().stations.get(String(station_id), {}) if services != null else {}
	var line := String(record.get("description", "Upgrade this area."))
	return PackedStringArray([line, "Each level adds more to this area, and it does more for the colony."])
