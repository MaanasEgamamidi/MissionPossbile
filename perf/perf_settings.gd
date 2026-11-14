extends Node
## Autoload name: PerfSettings (res://perf/perf_settings.gd).
## Master switches and tunables for every performance system (docs/perf, perf-overhaul branch).
## Each system reads its values from here, so it can be toggled live (perf_hud.gd, Ctrl+1..9) and A/B tested.
## Contract: with every switch OFF (set_all(false)) the game must behave and look exactly like commit d5c8df6.
## Launch flags (after `--`): `--perf-off` starts with every switch off (the baseline), `--perf-on` with every switch on.
##
## Default ON only for systems that cannot change a visible pixel by construction (they only stop drawing or lighting
## what no camera can see, or pause animation out of view). Everything that changes pixels on screen starts OFF until
## an idle-GPU measurement and a visual check say otherwise (docs/perf/final_report.md).

signal changed(setting: StringName)

# --- Master switches (A/B testing) ---
var zones_enabled := true             # Phase 2: room sleep/wake (camera layer mask, fixture lights)
var exterior_cull_enabled := true     # Phase 3: hide Mars when no window/open door can see it
var view_activation_enabled := true   # Phase 4: pause crew animation outside the view cone
var colony_lod_enabled := false       # Phase 5: HLOD proxies of the colony seen from far away (changes pixels)
var visibility_ranges_enabled := false  # Phase 5: per-object draw distance for Mars rocks and props (changes pixels)
var shader_warmup_enabled := false    # Phase 6: draw every zone once behind the loading overlay (Godot 4.7 precompiles)
# Phase 1 switches: these change the authored look, so they stay OFF until a measurement and a visual check say
# otherwise (decision recorded in docs/perf/phase_1.md).
var sun_shadow_tuning_enabled := false
var light_distance_fade_enabled := false

# --- Zone system ---
var warm_hops := 1                    # rooms within this many doors of the current room stay WARM
var glass_view_hops := 2              # rooms seen through this many glass doors/windows in a row stay drawn (VIEW_ONLY)
var prewarm_distance := 4.0           # m: near a door, also warm the rooms behind it
var cold_delay := 2.0                 # s: grace period before a room is allowed to go COLD
var step_budget_usec := 1500          # per-frame time slice for state changes (1.5 ms)
var snap_distance := 6.0              # m the player may move between two frames before it counts as a teleport

# --- Exterior (Mars) visibility ---
var exterior_hide_delay := 1.5        # s: Mars must be unneeded this long before it is hidden
var exterior_check_hops := 2          # how many open/glass doors in a row a sight line may pass
var exterior_door_prewarm := 4.0      # m: show Mars early when near a door that leads toward it
var sun_off_when_exterior_hidden := false  # optional extra saving; verify interior lighting first

# --- Player outside the colony ---
var outside_interior_distance := 25.0  # m: rooms with a view out stay drawn (VIEW_ONLY) this close
var outside_dome_distance := 400.0     # m: the glass dome plaza and the garden dome stay drawn this close
var entrance_prewarm_distance := 15.0  # m: warm the airlock rooms when approaching an exterior door

# --- Phase 5 tunables ---
var range_per_metre := 150.0          # visibility_range_end = this x largest dimension (about 5 px at 1080p, 72 deg)
var range_min := 30.0                 # m: never end closer than this
var colony_tier1_begin := 0.0         # m from the colony centre; 0 = colony radius + 40 (computed)
var colony_tier2_begin := 0.0         # m; 0 = colony radius + 200 (computed)

# --- Phase 1 tunables (used only while their switch is on) ---
var sun_shadow_max_distance := 150.0  # m, DirectionalLight3D.directional_shadow_max_distance
var sun_shadow_fade_start := 0.8      # DirectionalLight3D.directional_shadow_fade_start
var light_fade_begin := 30.0          # m, OmniLight3D/SpotLight3D distance_fade_begin
var light_fade_length := 10.0         # m
var light_fade_shadow := 25.0         # m

const SWITCHES: Array[StringName] = [&"zones_enabled", &"exterior_cull_enabled", &"view_activation_enabled",
	&"colony_lod_enabled", &"visibility_ranges_enabled", &"shader_warmup_enabled", &"sun_shadow_tuning_enabled",
	&"light_distance_fade_enabled"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--perf-off"):
		set_all(false)
	elif args.has("--perf-on"):
		set_all(true)
	for a: String in args:
		# --perf-set=name:value (repeatable), e.g. --perf-set=glass_view_hops:1
		if a.begins_with("--perf-set="):
			var kv := a.trim_prefix("--perf-set=").split(":", true, 1)
			if kv.size() == 2 and kv[0] in self:
				set_value(StringName(kv[0]), type_convert(kv[1], typeof(get(kv[0]))) if kv[1] != "true" and kv[1] != "false" else kv[1] == "true")


## Sets one switch or tunable by name and tells every listener.
func set_value(setting: StringName, value: Variant) -> void:
	set(setting, value)
	changed.emit(setting)


func toggle(setting: StringName) -> bool:
	set_value(setting, not bool(get(setting)))
	return bool(get(setting))


## Every master switch on or off at once (off = the d5c8df6 baseline).
func set_all(on: bool) -> void:
	for s in SWITCHES:
		set_value(s, on)


func snapshot() -> Dictionary:
	var d := {}
	for s in SWITCHES:
		d[s] = bool(get(s))
	return d


## Mesh LOD aggressiveness. The engine default is 1.0 pixel; this project ships 2.0
## (rendering/mesh_lod/lod_change/threshold_pixels), so "high" keeps 2.0 and nothing changes by default.
func apply_quality(preset: StringName) -> void:
	var root := get_tree().root
	match preset:
		&"low":
			root.mesh_lod_threshold = 4.0
		&"medium":
			root.mesh_lod_threshold = 3.0
		_:
			root.mesh_lod_threshold = float(ProjectSettings.get_setting("rendering/mesh_lod/lod_change/threshold_pixels", 2.0))
