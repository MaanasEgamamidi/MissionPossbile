class_name PerfRig
extends Node
## Puts the perf overhaul systems into a running game (GameMain calls PerfRig.attach(self) at the start of play).
## Nothing here changes game state; every system is switchable at run time through PerfSettings (Ctrl keys: PerfHud).
##
##   Perf
##   ├─ ZoneManager         Phase 2: room sleep/wake (camera layer mask + fixture lights)
##   ├─ ExteriorController  Phase 3: Mars hidden only when it cannot be seen
##   ├─ ViewActivator       Phase 4: other crew's animation paused out of view
##   ├─ ColonyLod           Phase 5: colony HLOD proxies (needs res://lod/, built by tools/perf/build_colony_lod.gd)
##   ├─ VisibilityRanges    Phase 5: Mars scenery draw distances
##   ├─ EngineTweaks        Phase 1: sun shadow distance, fixture distance fade
##   ├─ ShaderWarmup        Phase 6: optional warm-up tour behind a black overlay
##   └─ BenchmarkRoute      debug builds: Ctrl+8 / 9 / 0

const NODE_NAME := "Perf"
const TAG_INTERVAL := 1.0

var game: Node
var zone_manager: ZoneManager
var exterior: ExteriorController
var view_activator: ViewActivator
var colony_lod: ColonyLod
var visibility_ranges: VisibilityRanges
var tweaks: EngineTweaks
var warmup: ShaderWarmup
var route: BenchmarkRoute
var _tag_t := 0.0


## Returns the rig (an existing one if play was started again in the same scene).
static func attach(game_main: Node) -> PerfRig:
	var existing := game_main.get_node_or_null(NODE_NAME) as PerfRig
	if existing != null:
		return existing
	if game_main.get_node_or_null("/root/PerfSettings") == null:
		return null   # the PerfSettings autoload is missing (a script that builds its own tree): stay out of the way
	var world: Node3D = game_main.get("world")
	if world == null or game_main.get("lighting") == null:
		return null   # tests without the map
	var rig := PerfRig.new()
	rig.name = NODE_NAME
	game_main.add_child(rig)
	rig._build(game_main, world)
	return rig


func _build(game_main: Node, world: Node3D) -> void:
	game = game_main
	var sun := world.get_node_or_null("GC_MarsSun") as DirectionalLight3D
	var mars: Array[Node3D] = []
	for n: String in ["Terrain", "Environment"]:
		var r := world.get_node_or_null(n) as Node3D
		if r != null:
			mars.append(r)

	zone_manager = ZoneManager.new()
	zone_manager.name = "ZoneManager"
	add_child(zone_manager)
	zone_manager.setup(game_main)

	exterior = ExteriorController.new()
	exterior.name = "ExteriorController"
	add_child(exterior)
	exterior.setup(zone_manager, mars, sun)

	view_activator = ViewActivator.new()
	view_activator.name = "ViewActivator"
	add_child(view_activator)

	colony_lod = ColonyLod.new()
	colony_lod.name = "ColonyLod"
	add_child(colony_lod)
	var colony := world.get_node_or_null("Colony") as Node3D
	if colony == null or not colony_lod.setup(colony):
		colony_lod.queue_free()
		colony_lod = null

	visibility_ranges = VisibilityRanges.new()
	visibility_ranges.name = "VisibilityRanges"
	add_child(visibility_ranges)
	var env := world.get_node_or_null("Environment") as Node3D
	visibility_ranges.setup([env] as Array[Node3D] if env != null else [] as Array[Node3D])

	tweaks = EngineTweaks.new()
	tweaks.name = "EngineTweaks"
	add_child(tweaks)
	tweaks.setup(sun)

	warmup = ShaderWarmup.new()
	warmup.name = "ShaderWarmup"
	add_child(warmup)
	warmup.zone_manager = zone_manager
	warmup.mars_roots = mars

	if OS.is_debug_build():
		route = BenchmarkRoute.new()
		route.name = "BenchmarkRoute"
		add_child(route)
		route.setup(game_main)

	_tag_crew()
	if Perf.cfg().shader_warmup_enabled and DisplayServer.get_name() != "headless":
		warmup.run(game_main)


func _process(delta: float) -> void:
	_tag_t += delta
	if _tag_t >= TAG_INTERVAL:
		_tag_t = 0.0
		_tag_crew()


## The other crew's animated model nodes are the expensive view-gated entities. Only the model is tagged: the crew
## body itself carries the door-sensing Presence body, which must keep working when nobody looks.
func _tag_crew() -> void:
	var visuals: Variant = game.get("_crew_visuals")
	if not (visuals is Dictionary):
		return
	for v: Variant in (visuals as Dictionary).values():
		if not is_instance_valid(v):
			continue
		var model: Variant = (v as Node).get("_model")
		if model is Node3D and is_instance_valid(model) and not (model as Node).is_in_group(&"view_gated"):
			(model as Node3D).add_to_group(&"view_gated")
			(model as Node3D).set_meta(ViewActivator.META_RADIUS, 1.0)
