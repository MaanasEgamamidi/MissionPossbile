class_name StationPanels
extends RefCounted
## STUB owned by worker D. Builds the panel ("station surface") for a station, by its kind.


## A panel for `station_id`, or null if that station has no surface (for example the suit rack, used directly with E).
static func for_station(_station_id: StringName, _services: GameServices) -> UiPanel:
	return null
