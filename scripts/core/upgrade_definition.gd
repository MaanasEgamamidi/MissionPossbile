class_name UpgradeDefinition
extends Resource
## One equipment upgrade card in an existing facility (construction in this game means upgrading, never new buildings).
## Cards come from res://data/upgrades.json (ProgressionSystem.cards() loads them with from_dict). A card can be
## installed when the colony has reached its sector `tier`, has answered every question in `questions`, has recorded
## every practical evidence id in `evidence`, has `cost_parts` spare parts, and the right specialist (`specialty`,
## empty = anyone) stands at the install station.

@export var id: StringName = &""
@export var title := ""
## Zone (facility) the upgrade belongs to, as named by ColonyZones: the zone of the install station.
@export var zone := ""
## Sector tier the colony needs before this card can be installed (state.progress.tiers[sector], 0..3).
@export var tier := 1
## Parts spent when it is installed. Designer balance (ProgressionBalance.card_parts), never a NASA figure.
@export var cost_parts := 0
## Ids of other upgrades that must be installed first (none of the Prompt 08 cards uses this).
@export var prerequisites: Array[StringName] = []
## Specialty that installs it, or empty if anyone can.
@export var specialty: StringName = &""
## Ids of docs/source_register.md entries that support what the upgrade teaches.
@export var source_ids: Array[StringName] = []

# ---- Prompt 08 contract fields
## Sector: "energy", "life_support", "food", "resources" or "science".
@export var sector := ""
## What the upgrade does, in words.
@export var function_text := ""
## The measurable effect on the colony model, in words with numbers.
@export var effect := ""
## Knowledge question ids (data/questions.json) that must be answered right.
@export var questions: Array[StringName] = []
## Practical evidence ids (ProgressEvidence) that must be recorded.
@export var evidence: Array[StringName] = []
## Station id where it is installed (the installer stands there).
@export var install_station: StringName = &""
## Station kind that also counts as the install station (for a station another part names, such as the workbench).
@export var install_kind := ""
## Other station kinds where the card may also be installed (scout update: the energy cards at a sun tracker).
@export var also_install_kinds := PackedStringArray()
## Which part of the game applies the effect: "G" (progression, energy and life support), "F" (food), "S" (science).
@export var effect_owner := ""
## True when the upgrade automates a chore (the chore then never comes back on a schedule).
@export var automation := false
## Where the numbers and ideas come from, and what is simplified, in words (source and abstraction labels).
@export var source_labels: Array[String] = []


## A card from one entry of data/upgrades.json. `cost_override` >= 0 replaces the file's parts cost.
static func from_dict(card: Dictionary, cost_override := -1) -> UpgradeDefinition:
	var d := UpgradeDefinition.new()
	d.id = StringName(String(card.get("id", "")))
	d.title = String(card.get("title", ""))
	d.zone = String(card.get("zone", ""))
	d.tier = int(card.get("tier", 1))
	d.cost_parts = cost_override if cost_override >= 0 else int(card.get("cost_parts", 0))
	for p in card.get("prerequisites", []):
		d.prerequisites.append(StringName(String(p)))
	d.specialty = StringName(String(card.get("specialty", "")))
	for s in card.get("source_ids", []):
		d.source_ids.append(StringName(String(s)))
	d.sector = String(card.get("sector", ""))
	d.function_text = String(card.get("function", ""))
	d.effect = String(card.get("effect", ""))
	for q in card.get("questions", []):
		d.questions.append(StringName(String(q)))
	for e in card.get("evidence", []):
		d.evidence.append(StringName(String(e)))
	d.install_station = StringName(String(card.get("install_station", "")))
	d.install_kind = String(card.get("install_kind", ""))
	for k in card.get("also_install_kinds", []):
		d.also_install_kinds.append(String(k))
	d.effect_owner = String(card.get("effect_owner", ""))
	d.automation = bool(card.get("automation", false))
	for l in card.get("source_labels", []):
		d.source_labels.append(String(l))
	return d
