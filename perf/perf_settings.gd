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
var room_props_enabled := true        # Phase 2: props added at run time inside a room sleep with that room
var exterior_cull_enabled := true     # Phase 3: hide Mars when no window/open door can see it
var view_activation_enabled := true   # Phase 4: pause crew animation outside the view cone
# Light view (2026-11-18, docs/perf/ultra_60fps.md): a drawn room's fixture lights are off while the camera cannot see
# into that room through a door or window. Lights of rooms you cannot see cost about half of every frame at Ultra.
var light_view_enabled := true
# ... and a zone the camera is not in (nor standing next to a door into) draws its fixture lights without shadow maps:
# the shadow redraws of the rooms seen through glass took up to half the draw calls (Greenhouse at Ultra: 14k -> 7k
# draws, 18.3 -> 14.9 ms per frame), with no difference in the picture beyond run-to-run noise.
var light_view_shadows_enabled := true
var colony_lod_enabled := false       # Phase 5: HLOD proxies of the colony seen from far away (changes pixels)
var visibility_ranges_enabled := false  # Phase 5: per-object draw distance for Mars rocks and props (changes pixels)
var shader_warmup_enabled := false    # Phase 6: draw every zone once behind the loading overlay (Godot 4.7 precompiles)
# Phase 1 switches: these change the authored look, so they stay OFF until a measurement and a visual check say
# otherwise (decision recorded in docs/perf/phase_1.md).
var sun_shadow_tuning_enabled := false
var light_distance_fade_enabled := false
# Battery / thermals (a fanless MacBook throttles hard when it heats up): while the game window is in the background
# and you are not hosting or in an online game, cap the frame rate. Online games are never touched, so the host's
# state and voice ticks keep their pace.
var background_throttle_enabled := true
var background_max_fps := 10

# --- Zone system ---
var warm_hops := 1                    # rooms within this many doors of the current room stay WARM
var glass_view_hops := 2              # rooms seen through this many glass doors/windows in a row stay drawn (VIEW_ONLY)
var prewarm_distance := 4.0           # m: near a door, also warm the rooms behind it
var cold_delay := 2.0                 # s: grace period before a room is allowed to go COLD
var step_budget_usec := 1500          # per-frame time slice for state changes (1.5 ms)
var snap_distance := 6.0              # m the player may move between two frames before it counts as a teleport

# --- Light view ---
var light_view_margin_deg := 25.0     # degrees added around the camera's view (lights are already on when you turn)
var light_view_hold := 1.0            # s a room stays lit after its last door or window left the view
var light_view_near := 3.0            # m: standing this close to a door or window keeps the room behind it lit
var light_view_hops := 2              # glass links in a row a sight line may pass to light a zone (doors / windows)
var light_view_shadow_near := 2.0     # m: this close to a door, the room behind it gets its shadows back (before you cross)

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

# --- Adaptive render resolution (perf/dynamic_resolution.gd, docs/perf/laptop_rtx5050.md) ---
# Not in SWITCHES: the player's "Fit to this computer" setting decides, not the A/B switches. `--perf-off` sets mode 0.
var dynamic_resolution_mode := -1     # -1 = follow the setting and the graphics card, 0 = never, 1 = always
var dynamic_resolution_target_fps := 60.0  # the frame rate it holds (the screen's refresh rate when that is lower)

const SWITCHES: Array[StringName] = [&"zones_enabled", &"room_props_enabled", &"exterior_cull_enabled", &"view_activation_enabled",
	&"light_view_enabled", &"light_view_shadows_enabled",
	&"colony_lod_enabled", &"visibility_ranges_enabled", &"shader_warmup_enabled", &"sun_shadow_tuning_enabled",
	&"light_distance_fade_enabled", &"background_throttle_enabled"]

var _fps_before_background := -1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--perf-off"):
		set_all(false)
		dynamic_resolution_mode = 0   # the baseline never changes the render resolution
	elif args.has("--perf-on"):
		set_all(true)
	for a: String in args:
		# --perf-set=name:value (repeatable), e.g. --perf-set=glass_view_hops:1
		if a.begins_with("--perf-set="):
			var kv := a.trim_prefix("--perf-set=").split(":", true, 1)
			if kv.size() == 2 and kv[0] in self:
				set_value(StringName(kv[0]), type_convert(kv[1], typeof(get(kv[0]))) if kv[1] != "true" and kv[1] != "false" else kv[1] == "true")


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if background_throttle_enabled and not _is_online() and _fps_before_background < 0:
				_fps_before_background = Engine.max_fps
				Engine.max_fps = background_max_fps
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_restore_fps()


func _process(_delta: float) -> void:
	# a game hosted or joined while the window is in the background gets its full frame rate back at once
	if _fps_before_background >= 0 and (_is_online() or not background_throttle_enabled):
		_restore_fps()


func _restore_fps() -> void:
	if _fps_before_background >= 0:
		Engine.max_fps = _fps_before_background
		_fps_before_background = -1


func _is_online() -> bool:
	var peer := get_tree().root.multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)


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
