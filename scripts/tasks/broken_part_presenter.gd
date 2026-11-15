extends Node3D
## Broken parts in the world (2026-11-14, docs/revisions/BROKEN_PARTS_BRIEF.md). Presentation only: it reads the
## replicated colony state and never changes it.
##   - Every part of data/broken_parts.json whose task is broken (PuzzleRegistry.is_broken: a puzzle is installed and
##     state.repair.tasks[id].first_completed is false) shows its broken model (a glb already in world coordinates,
##     added at the origin on the room's render layers) and hides the intact map objects' visuals. Collision and the
##     station stay as they are, so E aims at the same thing.
##   - When a task turns first_completed while the game runs (on the host by the puzzle rule, on clients by the
##     replicated state, never by local input), the part plays its transition: a soft star sparkle burst over its
##     bounds (scripts/tasks/sparkle_burst.gd), a warm glow for 0.4 s, and at 0.35 s the broken model shrinks out,
##     its effects (vapour, spray, puddles, dust) stop and the intact visuals come back.
##   - Loading a save, joining late or starting a new colony shows each part as it is, without sparkles.
##   - T12 (special "door_901"): the broken door leaves slide with the exit tunnel's inner door (door 901).
##   - T11 (special "dust"): the hangar objects are dusty while broken; the T11 puzzle state cleans them area by area
##     (scripts/tasks/hangar_dust.gd).
## A part whose glb is not there yet is skipped. Attached by GameMain next to AreaStages; loaded by path.

signal transition_started(task_id: String)
signal transition_finished(task_id: String)

const DATA_PATH := "res://data/broken_parts.json"
const SparkleBurst := preload("res://scripts/tasks/sparkle_burst.gd")
const HangarDust := preload("res://scripts/tasks/hangar_dust.gd")
## Role glow (owner request, 2026-11-14, replaces the gold specialist rim): every broken part glows for the player on
## this machine, GREEN when that player's crew member can do the repair (a general task, or their own specialty) and
## RED when it is another specialist's job. A pulsing rim drawn as material_overlay on the broken model (effects such as
## vapour and spray stay plain), recoloured when the player swaps crew member, gone with the model when it is fixed.
const GLOW_SHADER := preload("res://materials/specialist_gold.gdshader")
const GLOW_META := &"role_glow"
const GLOW_CAN := Color(0.3, 1.0, 0.42)
const GLOW_CANNOT := Color(1.0, 0.22, 0.18)
## Seconds between checks of which crew member this machine's player is.
const ROLE_POLL := 0.25
static var _glow_materials := {}
## The broken model's meshes become the repair spot's aim target (owner 2026-11-14: the whole object, reachable from
## 2-3 m): collision shapes on the station's sensing Area3D, on only while the part is broken.
const REACH_META := &"part_reach"
## Meshes larger than this (metres, longest side) get their exact triangles instead of a box (the dome glass, so its
## inside stays open).
const REACH_BOX_MAX := 4.0
const AirLeakVfx := preload("res://scripts/tasks/air_leak_vfx.gd")
const GROUP := &"broken_part_presenter"
## Seconds of the whole transition, when the broken model starts shrinking, when the intact one is back, and how
## long the warm glow lasts.
const SECONDS := 1.0
## Longest the fix waits for this machine's player to close the mini-game before it plays anyway, seconds.
const HOLD_MAX := 5.0
const SHRINK_FROM := 0.15
const SWAP_AT := 0.35
const GLOW_SECONDS := 0.4
const GLOW_COLOR := Color(1.0, 0.7, 0.36)
const GLOW_ALPHA := 0.5
## The exit tunnel's inner door (EnvironmentCollision), used by T12.
const DOOR_ID := 901
const TUNNEL_MESH := "SFX_tunnel_inside"
const INTACT_LEAVES: Array[String] = ["TunnelDoorInner_L", "TunnelDoorInner_R"]
## Seconds between reads of the T11 cleaning state.
const DUST_POLL := 0.2
## Prompts while broken when the data file has none (the brief's table). Only these ten may say fix / repair.
const FALLBACK_PROMPTS := {
	"T01": "[E] Lock the relay", "T02": "[E] Patch the relay", "T03": "[E] Sync the turbine",
	"T04": "[E] Light the power bench", "T06": "[E] Water the kale", "T08": "[E] Glaze the dome",
	"T09": "[E] Sort the lab samples", "T10": "[E] Revive the Med Bay", "T11": "[E] Clear the landing lines",
	"T12": "[E] Seal the airlock",
}

static var _data: Array = []
static var _data_loaded := false
## Tests: replaces PuzzleRegistry.is_broken(state, task_id) for this presenter and the HUD prompt
## (func(state: ColonyState, task_id: String) -> bool).
static var broken_override := Callable()

var world: Node3D
var services: GameServices
var game: Node
## Set before setup() to use these part records instead of data/broken_parts.json (tests). A record may carry
## "node": a ready-made broken model (Node3D) instead of "glb".
var parts_override: Array = []
## The exit tunnel's inner door; found on the game (airlock_doors) when not set before setup().
var door_901: DoorController
## Use CPU particles: -1 = follow the graphics preset (Low = CPU), 0 = GPU, 1 = CPU.
var force_cpu := -1
## Parts by task id (only parts that could be shown: a glb or node exists).
var parts := {}
## Transitions started since setup (tests).
var transitions_started := 0
## The last sparkle burst made (tests).
var last_burst: Node3D

var _holder: Node3D
## task id -> seconds its fix has waited for the mini-game to close (see _panel_holds).
var _hold := {}
var _state_id := 0
var _completed := {}
var _dust_left := 0.0
var _role_left := 0.0
## Specialty of this machine's crew member the glows were coloured for ("?" = not read yet).
var _local_spec := "?"
## Whether the glows were on (tapes first: no glow until every tape is found in tutorial mode); -1 = not read yet.
var _glow_on := -1


## Creates the presenter under `parent` and sets it up. Returns it.
static func attach(parent: Node, p_world: Node3D, p_services: GameServices, p_game: Node = null) -> Node:
	var script: GDScript = load("res://scripts/tasks/broken_part_presenter.gd")
	var presenter: Node3D = script.new()
	presenter.name = "BrokenPartPresenter"
	parent.add_child(presenter)
	presenter.call(&"setup", p_world, p_services, p_game)
	return presenter


# ---------------------------------------------------------------- data and prompts (also used by GameHud)

## The part records of data/broken_parts.json ({"parts": [...]}), read once.
static func load_data() -> Array:
	if not _data_loaded:
		_data_loaded = true
		_data = []
		if FileAccess.file_exists(DATA_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
			if parsed is Dictionary and (parsed as Dictionary).get("parts") is Array:
				for entry: Variant in parsed.parts:
					if entry is Dictionary:
						_data.append(entry)
			else:
				push_warning("%s has no parts list." % DATA_PATH)
	return _data


## Reads the data file again on the next load_data().
static func reload_data() -> void:
	_data_loaded = false


## The data record of a task's broken part, or {}.
static func part_of(task_id: String) -> Dictionary:
	for entry: Dictionary in load_data():
		if String(entry.get("task_id", "")) == task_id:
			return entry
	return {}


## What looking at a broken task's spot says ("[E] Fix the wires"), or "" for a task without a broken part.
static func prompt_for(task_id: String) -> String:
	var prompt := String(part_of(task_id).get("prompt", ""))
	return prompt if prompt != "" else String(FALLBACK_PROMPTS.get(task_id, ""))


## The words after the key ("[E] Fix the wires" -> "Fix the wires"), so a rebound key still shows its own name.
static func prompt_body(prompt: String) -> String:
	var p := prompt.strip_edges()
	if p.begins_with("["):
		var close := p.find("]")
		if close > 0:
			return p.substr(close + 1).strip_edges()
	return p


## True while the task's spot is broken (PuzzleRegistry.is_broken, or the test override).
static func is_task_broken(state: ColonyState, task_id: String) -> bool:
	if broken_override.is_valid():
		return state != null and bool(broken_override.call(state, task_id))
	return PuzzleRegistry.is_broken(state, task_id)


static func _first_completed(state: ColonyState, task_id: String) -> bool:
	if state == null:
		return false
	return bool(((state.repair.get("tasks", {}) as Dictionary).get(task_id, {}) as Dictionary).get("first_completed", false))


# ---------------------------------------------------------------- setup

func setup(p_world: Node3D, p_services: GameServices, p_game: Node = null) -> void:
	world = p_world
	services = p_services
	game = p_game
	add_to_group(GROUP)
	top_level = true
	_holder = Node3D.new()
	_holder.name = "Models"
	add_child(_holder)
	if door_901 == null and game != null:
		var doors: Variant = game.get(&"airlock_doors")
		if doors is Array:
			for d: Variant in doors:
				if d is DoorController and (d as DoorController).door_id == DOOR_ID:
					door_901 = d
	var list: Array = parts_override if not parts_override.is_empty() else load_data()
	for entry: Variant in list:
		if entry is Dictionary:
			_add_part(entry)
	snap()


func _add_part(entry: Dictionary) -> void:
	var task_id := String(entry.get("task_id", ""))
	if not RepairCatalog.TASKS.has(task_id) or parts.has(task_id):
		return
	var node: Variant = entry.get("node")
	var glb := String(entry.get("glb", ""))
	if not (node is Node3D) and (glb == "" or not ResourceLoader.exists(glb)):
		return          # the assets worker has not made this part yet: leave the intact object as it is
	var special := String(entry.get("special", ""))
	var p := {"task_id": task_id, "entry": entry, "special": special, "glb": glb, "model": node if node is Node3D else null,
		"intact": [] as Array[Node3D], "effects": [] as Array[Node], "leaves": [] as Array, "door_static": [] as Array[Node3D],
		"mask": 0, "bounds": AABB(), "shows_broken": false, "anim": -1.0, "swapped": false, "glow": null,
		"overlays": {}, "dust": null, "dust_levels": [] as Array[float], "reach": [] as Array[CollisionShape3D]}
	# Godot node names ("gr_rack_002") and the map's object names ("gr_rack.002"); _find tries both spellings.
	var names: Array = []
	var door_spec: Dictionary = entry.get("door", {}) if entry.get("door") is Dictionary else {}
	for list: Variant in [entry.get("hide_nodes", []), entry.get("hide_objects", []), door_spec.get("hide_env_nodes", [])]:
		if list is Array:
			for n: Variant in list:
				if not names.has(String(n)):
					names.append(String(n))
	if special == "door_901":
		# Never hide the whole tunnel lining: only the inner door's two leaves stand for the door.
		names = names.filter(func(n: Variant) -> bool: return String(n) != TUNNEL_MESH)
		for leaf: String in INTACT_LEAVES:
			if not names.has(leaf):
				names.append(leaf)
	for n: Variant in names:
		for found: Node3D in _find(String(n)):
			if not (p.intact as Array).has(found):
				(p.intact as Array).append(found)
	p.mask = _mask_for(String(entry.get("zone", "")), p.intact)
	# The sparkle covers the broken object itself (model_bounds), not its vapour or puddles.
	var b: Dictionary = entry.get("model_bounds", entry.get("bounds", {}))
	if b.has("center") and b.has("size"):
		var size := HangarDust._v3(b.size)
		p.bounds = AABB(HangarDust._v3(b.center) - size * 0.5, size)
	else:
		p.bounds = _bounds_of(p.intact)
	parts[task_id] = p


## Map nodes called `object_name` (Godot turns "pr_swgr.003" into "pr_swgr_003"). Outermost matches only.
func _find(object_name: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if world == null or object_name == "":
		return out
	for candidate: String in [object_name, object_name.replace(".", "_")]:
		for n in world.find_children(candidate, "Node3D", true, false):
			var inside := false
			for o in out:
				if o == n or o.is_ancestor_of(n):
					inside = true
			if not inside:
				out.append(n as Node3D)
		if not out.is_empty():
			break
	return out


## Render layers of a part: the layers its intact objects carry, plus its zone's own layer.
func _mask_for(zone: String, intact: Array) -> int:
	var mask := 0
	for n: Node3D in intact:
		for g in _geometry(n):
			mask |= g.layers
	if services != null and services.zones != null and zone != "":
		mask |= services.zones.bit_of(zone)
		if zone in [ColonyZones.PLAZA, ColonyZones.GARDEN, ColonyZones.EXTERIOR]:
			mask |= services.zones.sun_bit()
	return mask if mask != 0 else 1


static func _geometry(n: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	if n is GeometryInstance3D:
		out.append(n as GeometryInstance3D)
	for c in n.find_children("*", "GeometryInstance3D", true, false):
		out.append(c as GeometryInstance3D)
	return out


static func _bounds_of(nodes: Array) -> AABB:
	var box := AABB()
	var first := true
	for n: Node3D in nodes:
		for g in _geometry(n):
			if not (g is VisualInstance3D):
				continue
			var xf := g.global_transform if g.is_inside_tree() else g.transform
			var b := xf * (g as VisualInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
	return box


# ---------------------------------------------------------------- state

## Shows every part as the colony state says, with no transition (load, late join, new colony).
func snap() -> void:
	var st := services.state() if services != null and services.has_game() else null
	_state_id = st.get_instance_id() if st != null else 0
	_completed.clear()
	for task_id: String in parts:
		var p: Dictionary = parts[task_id]
		_completed[task_id] = _first_completed(st, task_id)
		_end_transition(p)
		_show(p, st != null and is_task_broken(st, task_id))


## True while the part's broken model is on show (also during the first 0.35 s of its transition).
func shows_broken(task_id: String) -> bool:
	return parts.has(task_id) and bool(parts[task_id].shows_broken)


## True while the part's transition runs.
func in_transition(task_id: String) -> bool:
	return parts.has(task_id) and float(parts[task_id].anim) >= 0.0


func _process(delta: float) -> void:
	step(delta)


## One update: follow the state, run transitions, slide the T12 leaves, read the T11 cleaning. Tests call it directly.
func step(delta: float) -> void:
	if services == null or not services.has_game():
		return
	var st := services.state()
	if st.get_instance_id() != _state_id:
		snap()          # another colony was loaded or joined: show it as it is, no sparkles
		return
	_dust_left -= delta
	var read_dust := _dust_left <= 0.0
	if read_dust:
		_dust_left = DUST_POLL
	_role_left -= delta
	if _role_left <= 0.0:
		_role_left = ROLE_POLL
		_follow_local_role()
	for task_id: String in parts:
		var p: Dictionary = parts[task_id]
		var done := _first_completed(st, task_id)
		# The fix plays when this machine's player can see it: while their mini-game for this part is still open
		# (its own success mark is showing), the sparkle burst and the swap wait for it to close.
		if done != bool(_completed.get(task_id, false)) and not (done and bool(p.shows_broken) and float(p.anim) < 0.0
				and _panel_holds(task_id, delta)):
			_completed[task_id] = done
			_hold.erase(task_id)
			if done and bool(p.shows_broken) and float(p.anim) < 0.0:
				_start_transition(p)
			elif float(p.anim) < 0.0:
				_show(p, is_task_broken(st, task_id))
		if float(p.anim) >= 0.0:
			_advance(p, delta)
		if bool(p.shows_broken) and String(p.special) == "door_901":
			_follow_door(p)
		if bool(p.shows_broken) and p.dust != null and read_dust and float(p.anim) < 0.0:
			_update_dust(p, st)


## True while this machine's player still has the mini-game of `task_id` open on top (at most HOLD_MAX seconds):
## the world waits to show the fix until they are looking at it again.
func _panel_holds(task_id: String, delta: float) -> bool:
	var ui: Variant = game.get(&"ui") if game != null and is_instance_valid(game) else null
	var top: Variant = (ui as Object).call(&"top") if ui is Object and (ui as Object).has_method(&"top") else null
	if not (top is TaskPanel) or (top as TaskPanel).task_id != task_id:
		return false
	_hold[task_id] = float(_hold.get(task_id, 0.0)) + delta
	return float(_hold[task_id]) < HOLD_MAX


## Puts a part in its broken or intact look at once.
func _show(p: Dictionary, broken: bool) -> void:
	if broken:
		var model := _ensure_model(p)
		if model == null:
			broken = false
		else:
			model.visible = true
			model.transform = Transform3D.IDENTITY
			for e: Node in p.effects:
				_set_effect(e, true)
	if not broken and p.model != null and is_instance_valid(p.model) and p.model.get_parent() == _holder:
		(p.model as Node3D).visible = false
	for n: Node3D in p.intact:
		if is_instance_valid(n):
			n.visible = not broken
	if broken and String(p.special) == "door_901":
		_follow_door(p)
	_set_reach(p, broken)
	if p.dust != null:
		if broken:
			_update_dust(p, services.state() if services != null and services.has_game() else null, true)
		else:
			(p.dust as RefCounted).call(&"clean")
			p.dust_levels = [] as Array[float]
	p.shows_broken = broken


## The broken model, made from its glb the first time it is needed.
func _ensure_model(p: Dictionary) -> Node3D:
	if p.model != null and is_instance_valid(p.model):
		if (p.model as Node3D).get_parent() == null:
			_holder.add_child(p.model)
			_prepare_model(p)
		return p.model
	var glb := String(p.glb)
	if glb == "" or not ResourceLoader.exists(glb):
		return null
	var scene := load(glb) as PackedScene
	if scene == null:
		push_warning("Broken part %s could not be loaded from %s." % [p.task_id, glb])
		p.glb = ""          # do not try again: the intact object stays
		return null
	var model := scene.instantiate() as Node3D
	if model == null:
		return null
	model.name = "Broken_" + String(p.task_id)
	p.model = model
	_holder.add_child(model)
	_prepare_model(p)
	return model


## Layers, effects, door leaves and dust patches of a freshly added model.
func _prepare_model(p: Dictionary) -> void:
	var model: Node3D = p.model
	model.transform = Transform3D.IDENTITY
	# The glb's meshes carry ColonyZones layers from their import; a mesh still on the default layer gets the part's.
	var zone_bit := int(p.mask)
	if services != null and services.zones != null:
		zone_bit = maxi(services.zones.bit_of(String((p.entry as Dictionary).get("zone", ""))), 0)
	for g in _geometry(model):
		g.layers = int(p.mask) if g.layers == 1 else (g.layers | zone_bit)
	var effect_names: Array = (p.entry as Dictionary).get("effect_nodes", [])
	var effects: Array[Node] = []
	for n: Variant in effect_names:
		var e := model.find_child(String(n), true, false)
		if e != null:
			effects.append(e)
	p.effects = effects
	if String(p.special) == "door_901":
		var leak := model.find_child("air_leak_vfx__broken", true, false)
		if leak != null:
			AirLeakVfx.replace(leak, p.entry as Dictionary)
	_apply_role_glow(p)
	_build_reach(p)
	if (p.bounds as AABB).size == Vector3.ZERO:
		p.bounds = _bounds_of([model])
	if String(p.special) == "door_901":
		_find_leaves(p)
	if String(p.special) == "dust" and p.dust == null:
		var dust: RefCounted = HangarDust.new()
		dust.call(&"setup", world, p.entry, model)
		p.dust = dust


## True when the task's repair needs a specialist (RepairCatalog role other than "general").
static func is_specialist_task(task_id: String) -> bool:
	var info: Array = RepairCatalog.TASKS.get(task_id, [])
	return info.size() >= 3 and String(info[2]) != "general"


## True when a crew member of `specialty` may do the task's repair: a general task, or their own specialty.
static func can_do(task_id: String, specialty: String) -> bool:
	var info: Array = RepairCatalog.TASKS.get(task_id, [])
	var role := String(info[2]) if info.size() >= 3 else "general"
	return role == "general" or role == "" or role == specialty


## The glow overlay: green (can do) or red (another specialist's job).
static func glow_material(can: bool) -> ShaderMaterial:
	if not _glow_materials.has(can):
		var m := ShaderMaterial.new()
		m.shader = GLOW_SHADER
		m.set_shader_parameter(&"gold", GLOW_CAN if can else GLOW_CANNOT)
		_glow_materials[can] = m
	return _glow_materials[can]


## Specialty of the crew member this machine's player controls, or "" when there is none.
func local_specialty() -> String:
	if services == null or not services.has_game():
		return ""
	var me := services.local_character()
	return String(me.specialty) if me != null else ""


static func _is_effect(p: Dictionary, n: Node) -> bool:
	for e: Node in p.effects:
		if is_instance_valid(e) and (e == n or e.is_ancestor_of(n)):
			return true
	return false


## Puts the green or red rim on the broken model's meshes. Effects (vapour, spray, puddles) stay plain, unless the part
## is nothing but effects (the hangar dust), which then glows itself.
func _apply_role_glow(p: Dictionary) -> void:
	var model := p.model as Node3D
	if model == null or not is_instance_valid(model):
		return
	if _local_spec == "?":
		_local_spec = local_specialty()
	if _glow_on < 0:
		_glow_on = 1 if glows_allowed() else 0
	var can := can_do(String(p.task_id), _local_spec)
	var mat: Material = glow_material(can) if _glow_on == 1 else null
	var plain: Array[GeometryInstance3D] = []
	var fx: Array[GeometryInstance3D] = []
	for g in _geometry(model):
		if g is GPUParticles3D or g is CPUParticles3D or g.has_meta(AirLeakVfx.META):
			continue
		if _is_effect(p, g):
			fx.append(g)
		else:
			plain.append(g)
	var saved: Dictionary = p.overlays
	for g in (plain if not plain.is_empty() else fx):
		if saved.has(g):
			saved[g] = mat          # mid-transition flash: the glow comes back when the flash ends
		else:
			g.material_overlay = mat
		g.set_meta(GLOW_META, mat != null)
	model.set_meta(GLOW_META, ("green" if can else "red") if mat != null else "")


## Tapes first (owner 2026-11-14): in tutorial mode the broken parts show no colour until every tape is found
## (TutorialSystem.repairs_unlocked); the broken models still look broken.
func glows_allowed() -> bool:
	if services == null or not services.has_game():
		return true
	return TutorialSystem.repairs_unlocked(services.state())


## "green", "red" or "" (no glow): the part's glow while its broken model is on show (checks and tools).
func glow_of(task_id: String) -> String:
	var p: Dictionary = parts.get(task_id, {})
	if p.is_empty() or not bool(p.shows_broken) or p.model == null or not is_instance_valid(p.model) or not (p.model as Node3D).visible:
		return ""
	return String((p.model as Node3D).get_meta(GLOW_META, ""))


## True while the part shows its broken model with a glow (the older name, from the gold highlight).
func shows_gold(task_id: String) -> bool:
	return glow_of(task_id) != ""


## Recolours every broken part when this machine's player becomes another crew member, and switches the glows on or
## off when the tapes-first gate changes.
func _follow_local_role() -> void:
	var spec := local_specialty()
	var on := 1 if glows_allowed() else 0
	if spec == _local_spec and on == _glow_on:
		return
	_local_spec = spec
	_glow_on = on
	for task_id: String in parts:
		var p: Dictionary = parts[task_id]
		if p.model != null and is_instance_valid(p.model):
			_apply_role_glow(p)


# ---------------------------------------------------------------- the whole model is the repair target

## The repair station's sensing Area3D of a task (world collision "Stations"), or null.
func _station_area(task_id: String) -> Area3D:
	if not is_inside_tree():
		return null
	var station_id := ""
	for entry: Dictionary in StationCatalog.extra_entries():
		if String(entry.get("kind", "")) == "repair_task" and String(entry.get("task_id", "")) == task_id:
			station_id = String(entry.get("id", ""))
			break
	if station_id == "":
		return null
	for n: Node in get_tree().get_nodes_in_group(&"station_volume"):
		if n is Area3D and String(n.get_meta("station_id", "")) == station_id:
			return n as Area3D
	return null


## Adds one collision shape per mesh of the broken model to the task's station Area3D: a box around a small mesh, or
## the mesh's own triangles (hit from both sides) when it is bigger than REACH_BOX_MAX.
func _build_reach(p: Dictionary) -> void:
	var model := p.model as Node3D
	var station := _station_area(String(p.task_id))
	if model == null or station == null or not station.is_inside_tree() or not model.is_inside_tree():
		return
	var shapes: Array[CollisionShape3D] = []
	var to_local := station.global_transform.affine_inverse()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.has_meta(AirLeakVfx.META):
			continue
		var box := m.get_aabb()
		if box.size.length() < 0.02:
			continue
		var shape := CollisionShape3D.new()
		shape.name = "PartReach_%d" % shapes.size()
		if maxf(box.size.x, maxf(box.size.y, box.size.z)) > REACH_BOX_MAX:
			var tri := m.mesh.create_trimesh_shape()
			if tri == null:
				continue
			tri.backface_collision = true
			shape.shape = tri
			shape.transform = to_local * m.global_transform
		else:
			var b := BoxShape3D.new()
			b.size = box.size.max(Vector3.ONE * 0.08)
			shape.shape = b
			shape.transform = to_local * m.global_transform * Transform3D(Basis.IDENTITY, box.get_center())
		station.add_child(shape)
		shapes.append(shape)
	p.reach = shapes
	if not shapes.is_empty():
		station.set_meta(REACH_META, true)
	_set_reach(p, bool(p.shows_broken) or model.visible)


## Turns the part's model-shaped target on (while broken) or off (fixed: the floor anchor stays the target).
func _set_reach(p: Dictionary, on: bool) -> void:
	for s: CollisionShape3D in p.get("reach", []):
		if is_instance_valid(s):
			s.set_deferred(&"disabled", not on)


## True while the part's model-shaped aim target is on (checks and tools).
func reach_on(task_id: String) -> bool:
	var p: Dictionary = parts.get(task_id, {})
	for s: CollisionShape3D in p.get("reach", []):
		if is_instance_valid(s) and not s.disabled:
			return true
	return false


## Splits the broken door model into the parts that slide with each leaf of door 901. The data file may name them
## ("door_leaves": {"L": [...], "R": [...]}); otherwise every mesh inside one leaf's slab goes with that leaf. A mesh
## across both leaves cannot slide: it shows only while the door is shut, and the intact leaves stand in while it opens.
func _find_leaves(p: Dictionary) -> void:
	var model: Node3D = p.model
	var leaves: Array = []
	var fixed: Array[Node3D] = []
	var entry: Dictionary = p.entry
	var door_spec: Dictionary = entry.get("door", {}) if entry.get("door") is Dictionary else {}
	var named: Dictionary = entry.get("door_leaves", {})
	var slab_x := EnvironmentCollision.DOOR_X
	var slab_z: Vector2 = EnvironmentCollision.DOORS[0].z
	var half_w := (slab_x.y - slab_x.x) * 0.5
	var slide := EnvironmentCollision.SLIDE_M
	for side: int in [-1, 1]:
		# data/broken_parts.json door.left / door.right: {"node", "slide_axis", "slide_m"} (seal nodes are children)
		var spec: Variant = door_spec.get("left" if side < 0 else "right")
		if spec is Dictionary and model.find_child(String(spec.get("node", "")), true, false) != null:
			var leaf := model.find_child(String(spec.node), true, false) as Node3D
			var axis := HangarDust._v3(spec.get("slide_axis", [1, 0, 0]))
			leaves.append({"node": leaf, "slide": axis.normalized() * float(spec.get("slide_m", slide * side)), "rest": leaf.position})
		for n: Variant in named.get("L" if side < 0 else "R", []):
			var leaf := model.find_child(String(n), true, false) as Node3D
			if leaf != null and not leaves.any(func(l: Dictionary) -> bool: return l.node == leaf):
				leaves.append({"node": leaf, "slide": Vector3(slide * side, 0, 0), "rest": leaf.position})
	if leaves.is_empty():
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if (p.effects as Array).has(m):
				continue
			var box := m.global_transform * m.get_aabb() if m.is_inside_tree() else m.transform * m.get_aabb()
			var c := box.get_center()
			var in_slab := c.x > slab_x.x - 0.1 and c.x < slab_x.y + 0.1 and c.z > slab_z.x - 0.2 and c.z < slab_z.y + 0.2 and c.y < 3.2
			if not in_slab:
				continue
			if box.size.x <= half_w + 0.15:
				var side := -1.0 if c.x < EnvironmentCollision.DOOR_CENTRE_X else 1.0
				leaves.append({"node": m, "slide": Vector3(slide * side, 0, 0), "rest": m.position})
			else:
				fixed.append(m)
	p.leaves = leaves
	p.door_static = fixed


## Slides the broken leaves exactly as far as door 901's own leaves have slid.
func _follow_door(p: Dictionary) -> void:
	if door_901 == null or not is_instance_valid(door_901):
		return
	var amount := door_901.open_amount
	for leaf: Dictionary in p.leaves:
		var n: Node3D = leaf.node
		if not is_instance_valid(n):
			continue
		var world_offset: Vector3 = (leaf.slide as Vector3) * amount
		if door_901.is_inside_tree():
			world_offset = door_901.global_basis * world_offset
		var parent := n.get_parent_node_3d()
		var local := parent.global_basis.inverse() * world_offset if parent != null and parent.is_inside_tree() else world_offset
		n.position = (leaf.rest as Vector3) + local
	if not (p.door_static as Array).is_empty():
		var shut := amount < 0.02
		for n: Node3D in p.door_static:
			if is_instance_valid(n):
				n.visible = shut
		for n: Node3D in p.intact:
			if is_instance_valid(n) and String(n.name) in INTACT_LEAVES:
				n.visible = not shut


func _update_dust(p: Dictionary, st: ColonyState, force := false) -> void:
	if p.dust == null:
		return
	var task: Dictionary = (st.repair.get("tasks", {}) as Dictionary).get(String(p.task_id), {}) if st != null else {}
	var levels: Array[float] = HangarDust.levels_from_task(task)
	if force or levels != (p.dust_levels as Array[float]):
		p.dust_levels = levels
		(p.dust as RefCounted).call(&"apply_levels", levels)


func _set_effect(e: Node, on: bool) -> void:
	if e is GPUParticles3D:
		(e as GPUParticles3D).emitting = on
	elif e is CPUParticles3D:
		(e as CPUParticles3D).emitting = on
	if e is Node3D:
		(e as Node3D).visible = on
	var players: Array[Node] = e.find_children("*", "AnimationPlayer", true, false)
	for a: Node in players:
		if on:
			(a as AnimationPlayer).play()
		else:
			(a as AnimationPlayer).stop()


# ---------------------------------------------------------------- the transition

func _use_cpu() -> bool:
	if force_cpu >= 0:
		return force_cpu == 1
	var level := GraphicsQuality.applied_level(get_tree())
	if level < 0 and game != null and game.get(&"settings") != null:
		level = int(game.get(&"settings").get(&"graphics_quality"))
	return level == GraphicsQuality.Level.LOW


func _start_transition(p: Dictionary) -> void:
	p.anim = 0.0
	p.swapped = false
	transitions_started += 1
	var bounds: AABB = p.bounds
	if bounds.size == Vector3.ZERO and p.model != null:
		bounds = _bounds_of([p.model])
	# Raised to chest height of the player by the part when it is lower than that, so the burst is easy to see.
	var chest_y := NAN
	if services != null and services.has_game():
		chest_y = SparkleBurst.chest_y_near(services.state(), bounds, services.local_character())
	last_burst = SparkleBurst.spawn(_holder, bounds, int(p.mask), _use_cpu(), Color(0.0, 0.0, 0.0, 0.0), chest_y)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.albedo_color = Color(GLOW_COLOR, 0.0)
	p.glow = glow
	if p.model != null and is_instance_valid(p.model):
		_overlay(p, [p.model], true)
	transition_started.emit(String(p.task_id))


func _advance(p: Dictionary, delta: float) -> void:
	p.anim = float(p.anim) + delta
	var t := float(p.anim)
	var glow := p.glow as StandardMaterial3D
	if glow != null:
		glow.albedo_color.a = GLOW_ALPHA * sin(PI * clampf(t / GLOW_SECONDS, 0.0, 1.0))
	var model := p.model as Node3D
	if not bool(p.swapped) and model != null and is_instance_valid(model) and t >= SHRINK_FROM:
		var s := maxf(0.001, 1.0 - smoothstep(SHRINK_FROM, SWAP_AT, t))
		var c := (p.bounds as AABB).get_center()
		model.transform = Transform3D(Basis.from_scale(Vector3.ONE * s), c - c * s)
	if not bool(p.swapped) and t >= SWAP_AT:
		p.swapped = true
		for e: Node in p.effects:
			if is_instance_valid(e):
				_set_effect(e, false)
		if model != null and is_instance_valid(model):
			model.visible = false
		for n: Node3D in p.intact:
			if is_instance_valid(n):
				n.visible = true
		_overlay(p, p.intact, true)
		if p.dust != null:
			(p.dust as RefCounted).call(&"clean")
			p.dust_levels = [] as Array[float]
		p.shows_broken = false
		_set_reach(p, false)
	if t >= GLOW_SECONDS:
		_overlay(p, [], false)
	if t >= SECONDS:
		_end_transition(p)
		transition_finished.emit(String(p.task_id))


func _end_transition(p: Dictionary) -> void:
	if float(p.anim) < 0.0:
		return
	p.anim = -1.0
	_overlay(p, [], false)
	p.glow = null
	var model := p.model as Node3D
	if model != null and is_instance_valid(model):
		model.transform = Transform3D.IDENTITY
		model.visible = bool(p.shows_broken)


## Puts the glow material over `nodes` (on) or takes every glow this part put on away again (off).
func _overlay(p: Dictionary, nodes: Array, on: bool) -> void:
	var saved: Dictionary = p.overlays
	if not on:
		for g: GeometryInstance3D in saved:
			if is_instance_valid(g):
				g.material_overlay = saved[g]
		saved.clear()
		return
	if p.glow == null:
		return
	for n: Node3D in nodes:
		if not is_instance_valid(n):
			continue
		for g in _geometry(n):
			if not saved.has(g):
				saved[g] = g.material_overlay
			g.material_overlay = p.glow
