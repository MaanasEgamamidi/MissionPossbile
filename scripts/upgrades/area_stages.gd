class_name AreaStages
extends RefCounted
## Attaches one AreaStagePresenter per upgrade path (data/area_levels.json) to the game. Each presenter script lives at
## res://scripts/upgrades/stages/<track>_stages.gd and is loaded by path (no class_name, so adding one needs no import).
## A track without a script, or whose script fails to load, is skipped with a warning: the rest still work.

const STAGES_DIR := "res://scripts/upgrades/stages/"


static func script_path(track_id: String) -> String:
	return STAGES_DIR + track_id + "_stages.gd"


## Creates and sets up every presenter under `parent`. Returns them by track id.
static func attach_all(parent: Node, world: Node3D, services: GameServices, game: Node = null) -> Dictionary:
	var out := {}
	for id: String in AreaLevels.track_ids():
		var path := script_path(id)
		if not ResourceLoader.exists(path):
			continue
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			push_warning("Upgrade stages for %s could not be loaded from %s." % [id, path])
			continue
		var node: Variant = script.new()
		if not (node is AreaStagePresenter):
			push_warning("%s is not an AreaStagePresenter." % path)
			if node is Node:
				(node as Node).free()
			continue
		var p := node as AreaStagePresenter
		parent.add_child(p)
		p.setup(world, services, game)
		out[id] = p
	return out


## Every presenter in the tree.
static func all(tree: SceneTree) -> Array[AreaStagePresenter]:
	var out: Array[AreaStagePresenter] = []
	if tree == null:
		return out
	for n in tree.get_nodes_in_group(&"area_stage_presenters"):
		if n is AreaStagePresenter:
			out.append(n as AreaStagePresenter)
	return out
