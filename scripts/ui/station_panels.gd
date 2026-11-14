class_name StationPanels
extends RefCounted
## Builds the panel ("station surface") for a station, by its kind, and names stations in words.
## Every panel it returns carries the meta `station_surface = true` and `station_id`, so UiRoot can close it with E.

## Station kind -> name in words, for headers.
const NAMES := {
	"power": "Power panel",
	"computer": "Colony computer",
	"comms": "Comms console",
	"food": "Greenhouse console",
	"lifesupport": "Life support console",
	"heal": "Med station",
	"board": "Transceiver board",
	"survivor": "Patient",
	"suits": "Suit rack",
	"solar": "Sun tracker",
}

## Station kind -> short name for the blueprint map.
const SHORT_NAMES := {
	"power": "Power",
	"computer": "Computer",
	"comms": "Comms",
	"food": "Greenhouse",
	"lifesupport": "Life support",
	"heal": "Med station",
	"board": "Radio board",
	"survivor": "Patient",
	"suits": "Suits",
	"solar": "Tracker",
}

## Station kind -> symbol used on the map and in headers.
const SYMBOLS := {
	"power": "⚡",
	"computer": "▣",
	"comms": "✉",
	"food": "❀",
	"lifesupport": "O₂",
	"heal": "✚",
	"board": "⚙",
	"survivor": "♥",
	"suits": "◆",
	"solar": "☀",
}


## Crew specialty -> words.
const SPECIALTY_WORDS := {
	&"electrical_comms": "Electrical and comms",
	&"medical_life_support": "Medical and life support",
	&"biology_food": "Biology and food",
	&"field_engineering_geology": "Field engineering and geology",
}

## Crew specialty -> symbol.
const SPECIALTY_SYMBOLS := {
	&"electrical_comms": "⚡",
	&"medical_life_support": "✚",
	&"biology_food": "❀",
	&"field_engineering_geology": "⛏",
}


## A panel for `station_id`, or null if the station is unknown.
## The panel is already set up with `services`; setting it up again does nothing.
static func for_station(station_id: StringName, services: GameServices) -> UiPanel:
	if services == null or not services.has_game():
		return null
	var record: Dictionary = services.state().stations.get(String(station_id), {})
	if record.is_empty():
		return null
	var kind := String(record.get("kind", ""))
	var panel: StationPanel
	match kind:
		"power":
			panel = PowerStationPanel.new()
		"lifesupport":
			panel = LifeSupportStationPanel.new()
		"solar":
			panel = SolarStationPanel.new()
		"suits":
			panel = SuitRackPanel.new()
		_:
			panel = StationPanel.new()
	panel.station_id = station_id
	panel.kind = kind
	panel.set_meta(&"station_surface", true)
	panel.set_meta(&"station_id", station_id)
	panel.setup(services)
	return panel


## The station's name in words ("Life support console").
static func name_of(kind: String) -> String:
	return String(NAMES.get(kind, "Station"))


## The station's short name for the map ("Life support").
static func short_name_of(kind: String) -> String:
	return String(SHORT_NAMES.get(kind, "Station"))


## The station's symbol.
static func symbol_of(kind: String) -> String:
	return String(SYMBOLS.get(kind, "●"))
