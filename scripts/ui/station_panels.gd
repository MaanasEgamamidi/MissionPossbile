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
	if kind in ["cassette_player_anchor", "cassette_player"]:
		var reader := CassettePlayerPanel.new()
		reader.station_id = station_id
		reader.set_meta(&"station_surface", true)
		reader.set_meta(&"station_id", station_id)
		reader.setup(services)
		return reader
	# Broken parts: while a repair task's spot is still broken, E opens its mini-game (PuzzleRegistry), not maintenance.
	if kind == "repair_task":
		var task_id := String(record.get("task_id", ""))
		if PuzzleRegistry.is_broken(services.state(), task_id):
			var game := PuzzleRegistry.make_panel(task_id, station_id, services)
			if game != null:
				return game
	var panel: StationPanel
	# A later milestone adds a panel for a kind by creating res://scripts/ui/stations/<kind>_station_panel.gd
	# (a script extending StationPanel). It takes precedence over the built-in panels below.
	var custom_path := "res://scripts/ui/stations/%s_station_panel.gd" % kind
	if ResourceLoader.exists(custom_path):
		panel = (load(custom_path) as Script).new() as StationPanel
	if panel == null:
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


## Path of the section choices panel (upgrade paths plan §2: each section's upgrades are chosen at its core spot).
const SECTION_PANEL_PATH := "res://scripts/ui/section_panel.gd"


## The section id whose core spot `station_id` is ("" = not a core spot): the power panel (Energy), the Greenhouse
## console (Biology), the med station (Health), the workbench and the lab glovebox (Science), the comms console
## (Communication). The list is data/area_levels.json "sections".
static func section_of_station(station_id: StringName, services: GameServices) -> String:
	if services == null or not services.has_game():
		return ""
	var record: Dictionary = services.state().stations.get(String(station_id), {})
	return AreaLevels.section_at(String(station_id), record) if not record.is_empty() else ""


## The choices panel of a section, opened from its core spot `station_id` (the core station's own panel has the
## "Choose … upgrades" button that calls this). Null when the section or the station is unknown.
static func section_panel(section_id: StringName, station_id: StringName, services: GameServices) -> UiPanel:
	if services == null or not services.has_game() or AreaLevels.section(String(section_id)).is_empty():
		return null
	var record: Dictionary = services.state().stations.get(String(station_id), {})
	if record.is_empty():
		return null
	var script := load(SECTION_PANEL_PATH) as Script
	if script == null:
		return null
	var panel := script.new() as StationPanel
	if panel == null:
		return null
	panel.set(&"section_id", String(section_id))
	panel.station_id = station_id
	panel.kind = String(record.get("kind", ""))
	panel.setup(services)
	return panel


## The station's name in words ("Life support console").
static func name_of(kind: String) -> String:
	return String(NAMES.get(kind, String(_extra_field(kind, "name", "Station"))))


## Every station kind with a name: the built-in ones and those added by data/stations_*.json files.
static func all_kinds() -> PackedStringArray:
	var out := PackedStringArray(NAMES.keys())
	for entry: Dictionary in StationCatalog.extra_entries():
		var k := String(entry.get("kind", ""))
		if k != "" and not out.has(k):
			out.append(k)
	return out


## A field of the first data/stations_*.json entry of this kind (later milestones name their own stations).
static func _extra_field(kind: String, field: String, fallback: String) -> String:
	for entry: Dictionary in StationCatalog.extra_entries():
		if String(entry.get("kind", "")) == kind and entry.has(field):
			return String(entry[field])
	return fallback


## The station's short name for the map ("Life support").
static func short_name_of(kind: String) -> String:
	return String(SHORT_NAMES.get(kind, _extra_field(kind, "short", _extra_field(kind, "name", "Station"))))


## The station's symbol.
static func symbol_of(kind: String) -> String:
	return String(SYMBOLS.get(kind, _extra_field(kind, "symbol", "●")))
