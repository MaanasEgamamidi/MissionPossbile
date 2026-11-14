class_name UpgradeDefinition
extends Resource
## One equipment upgrade in an existing facility (construction in this game means upgrading, never new buildings).
## INTERFACE ONLY: the progression milestone fills these in and decides the final fields. Nothing reads this yet.

@export var id: StringName = &""
@export var title := ""
## Zone (facility) the upgrade belongs to, as named by ColonyZones.
@export var zone := ""
## Tier this upgrade takes the facility to (ColonyState.zones[zone]["tier"]).
@export var tier := 1
## Parts spent when it is built. Designer balance, kept in GameBalance-style resources, never a NASA figure.
@export var cost_parts := 0
## Ids of knowledge, evidence or other upgrades that must exist first.
@export var prerequisites: Array[StringName] = []
## Specialty that can perform the specialist step, or empty if anyone can.
@export var specialty: StringName = &""
## Ids of SourceRecord entries that support what the upgrade teaches.
@export var source_ids: Array[StringName] = []
