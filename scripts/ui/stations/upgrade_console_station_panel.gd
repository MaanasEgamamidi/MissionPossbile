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
	# Upgrade paths plan (2026-11-15): builds are chosen at the section's core spot, one a day in the Plan block.
	var spot := "its section's core spot"
	for track: String in upgrade_tracks():
		spot = AreaLevels.spot_words(track)
		break
	return PackedStringArray(["Each level adds more to this area, and it does more for the colony.",
		"The colony chooses one build a day at %s, in the Plan block at 20:00." % spot])


## The console's one short line ("Plant more of the Garden dome.") above its upgrade strip.
func _build_body() -> void:
	var record: Dictionary = services.state().stations.get(String(station_id), {}) if services != null else {}
	_add_text(_body, String(record.get("description", "Upgrade this area.")))
