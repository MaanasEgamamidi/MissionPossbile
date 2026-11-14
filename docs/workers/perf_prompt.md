# Godot 4: Mars Base Performance Overhaul (Implementation Prompt)

**How to use this file:** open your Godot project in your coding agent (Claude Code, Cursor, etc.) and paste everything from "START OF PROMPT" down. The code blocks are reference implementations: adapt them to your project's real node names, but keep the behavior and the numbers as the starting point.

---

# START OF PROMPT

You are a senior Godot 4 engine/gameplay programmer. You are optimizing an existing, large 3D game set on Mars. The game has a space base ("the colony") made of many rooms, plus a huge Mars environment outside it (terrain, rocks, props). Performance is currently poor. Your job is to implement the plan below, **measuring before and after every phase**, without changing how the game plays or looks in normal conditions.

Read the whole prompt before writing code. Work phase by phase. Do not skip Phase 0.

## 0. Ground rules

**Before touching anything**
1. Make sure the project is under version control, or make a full zip backup *outside* the project folder. Work on a branch called `perf-overhaul`. Commit at the end of every phase with a message like `perf: phase 2 zone sleep/wake`.
2. Detect and write down (in `docs/perf/phase_0.md`):
   - Godot version (look at `config/features` in `project.godot`, or run the editor/binary with `--version`).
   - Renderer: `rendering/renderer/rendering_method` in `project.godot` (`forward_plus`, `mobile` or `gl_compatibility`).
   - Scripting language(s) in use (GDScript or C#). All reference code below is GDScript. If the project is C#, port it 1:1 keeping the same class names, signals, constants and logic.
   - Whether the folder `res://perf/` and any of these `class_name`s already exist: `Zone`, `ZoneDoor`, `ZoneManager`, `ExteriorController`, `ViewActivator`, `ColonyLod`, `ShaderWarmup`. If a name collides, rename mine (not the project's).
3. Features that need a minimum version: pipeline precompilation / ubershaders need **4.4+** and Forward+/Mobile; baking CSG nodes into occluders needs **4.4+**. If the project is on 4.2 or 4.3 everything else here still works; note which parts you skipped.

**Hard rules**
- Every optimization must be switchable at runtime through `PerfSettings` (see Phase 0) so it can be A/B tested. Nothing is allowed to be "always on with no way to disable".
- Do **not** change gameplay values, art, level layout or unrelated code. Do not refactor things you were not asked to touch.
- Do **not** toggle `visible` on individual objects per frame based on the camera's field of view. Godot already frustum-culls in the renderer, and doing it in script is slower and causes pop-in (see 2.2).
- Do **not** free and re-instantiate rooms when the player crosses a door in the first implementation. Rooms stay resident in memory and just sleep/wake (see 2.3).
- Do **not** try to use Rooms & Portals. That system only exists in Godot 3.x; Godot 4 replaced it with occlusion culling.
- Never disable a `CollisionShape3D` and change `process_mode` on the same node in the same frame (known engine pitfall). The reference code only uses `process_mode` and `visible`.
- Do not mark a phase done until you have measured it. If a change does not help (or makes things worse), say so in the notes and leave it switched off by default rather than hiding that fact.

**Reporting.** After each phase write `docs/perf/phase_N.md` containing: what you changed (files), the exact settings/numbers used, before/after measurements for the standard scenarios from Phase 0, and anything surprising. If a decision is ambiguous, pick the most reasonable option, write the choice and your reasoning in the notes, and continue. Stop and ask only before something irreversible or destructive.

## 1. Units and assumptions
- 1 Godot unit = 1 metre. If the game uses another scale, multiply every distance below accordingly and note it.
- Player eye height about 1.6 m. Rooms are at least a few metres across; doorways about 1 m wide.
- The colony is a static structure (it does not move at runtime). Rooms are connected by doors. Some doors lead outside (airlocks). Some rooms have windows (or glass doors) that see the Mars environment; some are sealed with no view outside.
- If any of these are false for this project, adapt and record it.

## 2. The plan and the reasons behind it

This section is the design. The research behind it is from the official Godot 4 documentation (links in section 14).

### 2.1 Rooms: only the current room and its neighbours are "alive" (Zone sleep/wake)
Each room becomes a **Zone** with four states:

| State | Visible | Dynamic content processing | When |
|---|---|---|---|
| `COLD` | no | off | default for every room that is not close to the player |
| `VIEW_ONLY` | yes | off | an interior you can see through windows while you are *outside* and close |
| `WARM` | yes | on | rooms adjacent to the room you are in (within `warm_hops` doors) |
| `ACTIVE` | yes | on | the room you are standing in |

"Dynamic content" means anything with scripts, animation, physics bodies, lights, particles, audio. Static meshes and static colliders stay in the scene; hiding them with `visible = false` does not affect collisions (hidden nodes still collide), so collision never has to be rebuilt.

Two kinds of cost are being cut, and they are separate:
- **Rendering cost**: `visible = false` removes the room from the render list. Occlusion culling (Phase 1) additionally removes rooms hidden behind walls *inside* the visible set.
- **Simulation cost**: scripts, animation, physics, particles. `visible = false` does **not** stop these. You must set `process_mode = PROCESS_MODE_DISABLED` on the room's dynamic root. Disabling processing does **not** stop rendering. Zones do both on purpose.

### 2.2 "Only render what is in the field of view": what Godot already does, and what we add
Godot **already performs view-frustum culling automatically every frame**: anything outside the camera's view is not drawn. It is cheap and happens in the engine. A fast camera turn costs the same per-frame work as standing still and looking at that view; there is no "suddenly rendering everything" event to protect against. The only things that can spike on a turn are first-time shader compilation (Phase 6) and any loading you add yourself. Writing my own FOV-based `visible` toggling would be slower than the engine and would add pop-in. **Do not implement custom render culling by FOV.**

What *is* worth doing, and what games commonly do with the "view cone plus 10-20 degrees" idea, is **gameplay-side gating**: put expensive entities (animated NPCs, particle rigs, scripted props) to sleep when they are outside a view cone with a safety margin, and wake them *before* they enter view. That is the `ViewActivator` (Phase 4). It handles fast turning with five mechanisms:
1. a wide cone (half-diagonal FOV + 20 degrees);
2. **look-ahead**: the cone grows with the camera's angular speed (up to +60 degrees);
3. a **near radius** (12 m) where everything is always awake, so things behind you are never frozen;
4. **hysteresis**: sleeping needs a bigger cone and a 1.5 s delay, so nothing flickers at the edge;
5. **rate-limited, priority-ordered wake-ups** (closest to screen centre first, max 6 per 0.1 s tick) so a sudden 180 degree spin can never cause a spike of work.

### 2.3 Door-crossing lag, and "render distance" like Minecraft
The worry was: when the player crosses a door, the new room has to be loaded/rendered all at once and the game hitches. Decisions:
- **Rooms stay resident in memory.** Nothing is loaded or freed at a door. "Cold" rooms are just hidden and not processed. Waking a cold room is flipping a few flags, not loading assets. This removes the biggest cause of door hitches (instancing scenes, loading textures, creating physics bodies).
- **Predictive pre-warming.** When the player is within 4 m of a door, the rooms around the room *behind* that door are woken too. So by the time the player steps through, the next ring of rooms is already warm. Crossing a door changes almost nothing.
- **Time-sliced transitions.** Every state change is split into small steps (show static, show dynamic, enable processing, notify hooks in chunks of 16). A scheduler runs steps inside a 1.5 ms per-frame budget, waking before sleeping, nearest room first. A big room can never cost more than ~1.5 ms in any frame.
- **Hysteresis.** A room only goes `COLD` after being unneeded for 2 s, so standing in a doorway or walking back and forth never causes thrash.
- **Shader hitch protection.** The first time a material is ever drawn, the GPU driver may compile a pipeline, which can hitch. Phase 6 draws every zone once behind a loading screen.

**Should rooms use a metric "render distance" (like Minecraft chunks) instead of "adjacent rooms"?** Decision: **no, not for rooms.** Inside a building, walls and doors decide what is visible, not metres. A room 8 m away through a wall does not need to be alive, while a room 25 m away down a straight open corridor might. Graph distance (doors) is more accurate and cheaper. Metric distance *is* the right tool for **individual objects** (small props and decorations), and Godot has it built in: `visibility_range_begin/end` per object (Phase 5). So: **hops for rooms, metres for objects.** `warm_hops = 1` is the default; if a long straight corridor shows pop-in, raise it to 2 for that case only.

### 2.4 Mars is always loaded, unless the player is sealed in
The Mars environment is hidden only when the player *cannot see it*: the current room has no windows, and no chain of open/glass doors (up to 2 deep) leads to a room that has windows or an open exterior door. It is **never freed or reloaded**: it only has `visible = false`, so showing it again is instant. It is shown *before* it is needed: when the player is within 4 m of a door that leads toward windows or outside, and again the moment any door starts to open. Hiding waits 1.5 s. When unsure (for example the player is not inside any room), Mars is shown. The player must never see it pop in or out.

### 2.5 Outside the colony: distance LOD tiers
When the player is on Mars, the colony exterior is rendered with three levels of detail, using Godot's **HLOD** (visibility ranges plus Visibility Parent) with automatic mesh LOD layered on top:

| Tier | What | Typical distance from colony centre |
|---|---|---|
| T0 | the existing full-detail exterior meshes | up to `colony radius + ~40 m` |
| T1 | one merged, decimated shell, about 25% of the triangles, simplified material | up to `colony radius + ~200 m` |
| T2 | one very low-poly silhouette, about 3-5% of the triangles, cheapest material, no shadows | beyond that, including from outside the crater |

Interiors are `COLD` when the player is outside (except windows close up, `VIEW_ONLY`), so the interior costs nothing from outside. Mars props use the same idea per object: `visibility_range_end` scaled to the object's size, and MultiMesh chunks for repeated rocks.

### 2.6 Things considered and rejected
| Idea | Why not |
|---|---|
| Custom FOV culling of rendering | engine already frustum-culls; script version is slower and pops |
| Rooms & Portals | Godot 3.x only |
| Unload/reload rooms at doors | causes the exact hitch we want to avoid; keep resident |
| Metric render distance for rooms | graph distance is more accurate indoors (see 2.3) |
| Occlusion culling on open Mars terrain | docs say open scenes benefit more from mesh LOD and visibility ranges; measure before baking terrain |

## 3. Phase 0: Instrumentation and baseline (do this first)

1. Create `res://perf/`. Add the files `perf_settings.gd` and `perf_hud.gd` (code in section 12). Register them as autoloads named exactly `PerfSettings` and `PerfHud` (Project Settings > Globals > Autoload, or in `project.godot` under `[autoload]`: `PerfSettings="*res://perf/perf_settings.gd"`, `PerfHud="*res://perf/perf_hud.gd"`).
2. Run the game. Ctrl+1 toggles the HUD, Ctrl+7 starts/stops a CSV log in `user://`. Confirm the HUD shows FPS, average/p99/worst frame time, draw calls, objects, primitives, node count, video memory. Fix the Ctrl-key choices if they collide with the game's input map.
3. Write `res://perf/benchmark_route.gd` (a debug-only node). Requirements:
   - Ctrl+8 records a waypoint (position + yaw + pitch of the player camera) into an array; Ctrl+9 plays the recorded route back by moving the player at a constant 4 m/s, turning at a capped 90 degrees/s, with player input disabled during playback. Save/load the route as `res://perf/route.json`.
   - A waypoint may carry an optional `open_door` NodePath; when reached, call `set_open(true)` on that door (once doors are `ZoneDoor`s) or trigger the game's normal door opening.
   - A "spin test" function: rotate the camera yaw at 720 degrees/s for 5 s, then back, without moving.
4. Record these five scenarios, each for 30 s with the CSV log, with all optimizations *off* (baseline) and write the numbers into `docs/perf/baseline.md` (avg, p99, worst frame ms, draw calls, objects, primitives, video memory, node count):
   - **S1** idle at the spawn point.
   - **S2** a route through every room of the colony, through every door.
   - **S3** standing in the room that is farthest from any window (sealed, if one exists).
   - **S4** outside the colony, looking at it, at 20 m, 100 m, 300 m, 800 m and 1500 m from its centre.
   - **S5** the spin test, indoors and outdoors.
5. **Find out whether you are CPU-bound or GPU-bound** with the editor's Debugger > Visual Profiler (it shows CPU and GPU time per frame) and the Monitors tab. Roughly: if GPU time per frame is the larger bar, rendering work matters most (Phases 1 and 5); if CPU/script/physics time is larger, simulation work matters most (Phases 2 and 4). Write the conclusion in `baseline.md` and do the phases in the order that fits, but still do all of them.
6. Cheap detective work to find the big costs (record each result): switch off, one at a time in the `WorldEnvironment`, SSAO, SSIL, SSR, SDFGI/VoxelGI, volumetric fog, glow; reduce MSAA; lower viewport 3D resolution scale; count the shadow-casting lights (`OmniLight3D`/`SpotLight3D` with `shadow_enabled`). Whatever gives the largest gain tells you where the budget is going. **Do not change the visual settings permanently**; only report them to me in the notes as options.

## 4. Phase 1: Free wins from engine settings (no new systems)

1. **Occlusion culling** (indoors this is the big one; the docs say it works best in indoor scenes with many small rooms).
   - Project Settings (turn on the Advanced toggle) > Rendering > Occlusion Culling > **Use Occlusion Culling = on** (`rendering/occlusion_culling/use_occlusion_culling`). It costs some CPU, so keep the A/B toggle (Ctrl+5).
   - Put an `OccluderInstance3D` in the scene that contains the colony, select it and click **Bake Occluders**. Only `MeshInstance3D` nodes are baked; `MultiMeshInstance3D`, particles and CSG nodes are ignored (CSG can be baked from 4.4 if converted to `MeshInstance3D`). Check the debug view: Perspective menu > Display Advanced > **Occlusion Culling Buffer**.
   - Keep dynamic things (player, NPCs, doors, movable props) out of the bake: put them on visual layer 2 (VisualInstance3D > Layers) and untick layer 2 in the occluder's **Bake > Cull Mask**, then re-bake.
   - If the bake is slow or the buffer is heavy, raise **Bake > Simplification** and re-bake.
   - **Doors:** closed doors should block sight lines. Give each door a `BoxOccluder3D`/`QuadOccluder3D` in an `OccluderInstance3D` child, enabled only while closed (the `ZoneDoor.closed_occluder` export does this by toggling `visible`). **Never animate or move an OccluderInstance3D**: the docs warn that moving them triggers a multi-frame background recomputation; toggling visibility is cheaper but still not free, which is fine because doors change rarely.
   - Design note from the docs: occlusion culling benefits from level design. If a long straight corridor of rooms exists, report it; do not rebuild the level.
2. **Mesh LOD (automatic).** Godot generates lower-detail meshes at import (meshoptimizer) for glTF/.blend/FBX/Collada, and uses them automatically with a screen-space metric. OBJ files do not get it unless Import As is set to **Scene** (then Reimport and restart the editor). Verify with Perspective > Display Advanced > wireframe, and compare with the **Disable Mesh LOD** debug draw mode. If one mesh breaks (skinned meshes are the usual case) disable LOD generation for that file in the Import dock. The runtime knob is `get_tree().root.mesh_lod_threshold` (default 1.0 pixel; 2 and 4 are more aggressive); project setting `rendering/mesh_lod/lod_change/threshold_pixels`. `PerfSettings.apply_quality()` exposes it as low/medium/high. Do not change the default for the high preset.
3. **Shadows.**
   - The sun (`DirectionalLight3D`): set `directional_shadow_max_distance` to the smallest value that still looks right on Mars (start at 150 m and tune), keep the 4-split PSSM only if needed (else `SHADOW_PARALLEL_2_SPLITS`), and set `directional_shadow_fade_start` so the cutoff is not noticeable. The docs state a lower maximum distance gives both better-looking shadows and better performance.
   - Every `OmniLight3D`/`SpotLight3D`: enable `distance_fade_enabled` (begin about 30 m, length 10 m, `distance_fade_shadow` about 25 m). Turn `shadow_enabled` off on purely decorative lights. (Distance fade only applies to omni and spot lights.)
4. **Far plane and fog.** Set `Camera3D.far` to the farthest distance anything matters (use the largest value you measured in S4 and add a margin). Use depth fog in the `Environment` (`fog_enabled`, `fog_depth_begin/end`) tuned as Martian dust haze so distant LOD swaps are hidden. Report the values you chose.
5. **Repeated objects.** Identical `MeshInstance3D`s that share a mesh and material are batched automatically. For hundreds or thousands of the same thing (rocks, pipes, crates, rivets) use `MultiMeshInstance3D`. **Split big MultiMeshes into grid cells (for example 64 m x 64 m)**: culling and LOD decisions use each node's bounding box (mesh LOD uses the point of the box closest to the camera), so one giant MultiMesh is always treated as "close" and always drawn.
6. **Transparency.** Transparent objects are sorted and cannot be batched. List how many transparent materials are in a typical view (windows, glass, holograms, dust) and reduce where it is free to do so (for example one glass surface per window, not three).

## 5. Phase 2: Zones (room sleep/wake)

**Goal:** `ZoneManager` keeps `ACTIVE` = current room, `WARM` = adjacent rooms, everything else `COLD`, with pre-warming, hysteresis and time-slicing (section 2.3).

### 5.1 Target scene structure
```
Level
├─ ZoneManager            (ZoneManager.gd, export: player)
├─ ExteriorController     (Phase 3)
├─ ViewActivator          (Phase 4)
├─ Persistent             (things that travel between rooms: NPCs that roam, carried items; never disabled by zones)
├─ Colony
│   ├─ Zones
│   │   ├─ Zone_Airlock   (Zone.gd)
│   │   │   ├─ Bounds     (Node3D with 1+ CollisionShape3D using BoxShape3D)
│   │   │   ├─ Static     (Node3D: MeshInstance3D, StaticBody3D, CollisionShape3D, no scripts)
│   │   │   └─ Dynamic    (Node3D: anything scripted, animated, physical, lit, emitting)
│   │   └─ ...one per room
│   ├─ Doors              (ZoneDoor.gd instances placed in the doorways)
│   ├─ Occluders          (OccluderInstance3D baked in Phase 1)
│   └─ ExteriorShell      (full-detail exterior meshes, used in Phase 5)
├─ MarsRoot               (terrain, rocks, props: Phase 3)
├─ WorldEnvironment, Sun  (stay at the Level root; never toggled)
└─ Player (+ Camera3D)    (never inside a zone)
```
The player and camera are never children of a Zone. Global lighting (`LightmapGI`, `VoxelGI`, `SDFGI`, `ReflectionProbe`s that are not room-specific) also stay out of zones. Room-specific `ReflectionProbe`s with update mode Always belong in `Dynamic` so they stop updating when hidden.

### 5.2 Inventory first (no code changes yet)
1. Walk the existing scene tree and write `docs/perf/scene_inventory.md`: list every room (name, scene file or node path, rough node count, number of scripted nodes, number of lights, particles, `RigidBody3D`/`CharacterBody3D`, `AnimationPlayer`s), every door (path, how it opens, which two rooms it joins), and which rooms have windows or glass.
2. Decide the migration approach per room and write it down:
   - **Preferred:** reparent children into `Static` and `Dynamic` roots (use `Node.reparent(new_parent, true)` to keep global transforms). Classify: script-less `MeshInstance3D`, `StaticBody3D`, `CollisionShape3D`, `CSG*`, `Decal` -> `Static`. Everything else (scripts, `AnimationPlayer`, `RigidBody3D`, `CharacterBody3D`, `Area3D` with logic, `OmniLight3D`/`SpotLight3D`, particles, `AudioStreamPlayer3D`, `ReflectionProbe`) -> `Dynamic`.
   - **If reparenting would break hard-coded `NodePath`s, `$Path` lookups, `%UniqueNames`, signal connections or exported node references:** grep for them first (`get_node`, `$`, `%`, `NodePath`, `@export var .*: Node`). Fix what you can safely; for the rest, keep the node where it is and add it to the zone through two optional exported arrays instead (add `extra_static: Array[Node3D]` / `extra_dynamic: Array[Node3D]` to `Zone` and apply the same state changes to them). Never leave a room half-converted.
   - Scenes that are instanced rooms: do this in the room's own scene file so every instance gets it.
3. Build the zone graph: place a `ZoneDoor` in every doorway, assign `zone_a` and `zone_b`, `transparent = true` for glass doors, `leads_outside = true` (and only `zone_a`) for airlock exterior doors. Hook the game's existing door logic to call `set_open(true)` at the **start** of the opening animation and `set_open(false)` after closing finishes.
4. Bounds: add one or more `BoxShape3D` collision shapes under each `Bounds` node that cover the room's interior. **Overlap neighbouring rooms by about 0.3 m at doorways** so there is never a gap. Bounds are used only for point-in-box maths (no physics layers needed). Boxes must not be scaled (change the shape size instead). Odd-shaped rooms: use several boxes.
5. Flag windows: `has_exterior_view = true` on every zone that has a window, a glass door to the outside, or any opening where Mars is visible.

### 5.3 Code
Files go in `res://perf/`. Add `Zone`, `ZoneDoor`, `ZoneManager` as shown.

**File: `res://perf/zone.gd`**
```gdscript
class_name Zone
extends Node3D
## One room (or corridor segment) of the colony.
##
## Children layout (names are exported, so yours can differ):
##   Bounds   - Node3D holding one or more CollisionShape3D with BoxShape3D (used for math only)
##   Static   - meshes and static colliders, no scripts, nothing animated
##   Dynamic  - everything scripted, animated, physical, lit, or emitting
##
## States (ordered, so comparisons like state >= State.WARM work):
##   COLD      hidden, Dynamic processing off
##   VIEW_ONLY visible, Dynamic processing off (interior seen through windows from outside)
##   WARM      visible, processing on (rooms next to the player)
##   ACTIVE    visible, processing on (room the player is in)

enum State { COLD, VIEW_ONLY, WARM, ACTIVE }

const HOOK_CHUNK := 16

@export var zone_id: StringName
@export var has_exterior_view := false  ## windows, glass airlock door, open hatch to the outside
@export var static_root: Node3D
@export var dynamic_root: Node3D
@export var bounds_root: Node3D

var state: int = State.ACTIVE  ## one of State.*, stored as int so it compares cleanly
var neighbors: Array[Zone] = []

var _tid := 0
var _boxes: Array[Dictionary] = []
var _hooks: Array[Node] = []
var _dynamic_mode_on: Node.ProcessMode = Node.PROCESS_MODE_INHERIT


func _ready() -> void:
	add_to_group(&"zone")
	if zone_id == &"":
		zone_id = StringName(name)
	if dynamic_root != null:
		_dynamic_mode_on = dynamic_root.process_mode
		if _dynamic_mode_on == Node.PROCESS_MODE_DISABLED:
			_dynamic_mode_on = Node.PROCESS_MODE_INHERIT
	refresh_bounds()
	refresh_hooks()


## Call again if the zone is moved at runtime (normally the colony is static).
func refresh_bounds() -> void:
	_boxes.clear()
	if bounds_root == null:
		push_error("Zone '%s' has no bounds_root assigned." % name)
		return
	for c in bounds_root.find_children("*", "CollisionShape3D", true, false):
		var cs := c as CollisionShape3D
		var box := cs.shape as BoxShape3D
		if box == null:
			continue
		_boxes.append({
			"inv": cs.global_transform.affine_inverse(),
			"half": box.size * 0.5,
		})


## Nodes inside Dynamic that implement _zone_state_changed(new_state: int) get notified
## so they can throttle themselves (stop particles, lower animation rate, etc.).
func refresh_hooks() -> void:
	_hooks.clear()
	if dynamic_root == null:
		return
	for n in dynamic_root.find_children("*", "", true, false):
		if n.has_method(&"_zone_state_changed"):
			_hooks.append(n)


func contains_point(p: Vector3, margin := 0.0) -> bool:
	for b in _boxes:
		var inv: Transform3D = b["inv"]
		var half: Vector3 = b["half"]
		var l: Vector3 = inv * p
		if absf(l.x) <= half.x + margin and absf(l.y) <= half.y + margin and absf(l.z) <= half.z + margin:
			return true
	return false


## Distance from a point to the nearest bounds box (0 when inside). Assumes unscaled boxes.
func distance_to_bounds(p: Vector3) -> float:
	var best := INF
	for b in _boxes:
		var inv: Transform3D = b["inv"]
		var half: Vector3 = b["half"]
		var l: Vector3 = inv * p
		var q := Vector3(
			maxf(absf(l.x) - half.x, 0.0),
			maxf(absf(l.y) - half.y, 0.0),
			maxf(absf(l.z) - half.z, 0.0))
		best = minf(best, q.length())
	return best


## Runs every step immediately (use at load time, behind a loading screen).
func apply_immediately(target: int) -> void:
	for step in plan_transition(target):
		step.call()


## Returns small steps that the ZoneManager runs inside a per-frame time budget.
## Starting a new transition invalidates the unfinished steps of the previous one.
func plan_transition(target: int) -> Array[Callable]:
	_tid += 1
	var id := _tid
	var waking := target > state
	state = target
	var vis := target != State.COLD
	var proc := target >= State.WARM
	var steps: Array[Callable] = []
	if waking:
		# show first, then start processing
		steps.append(func(): _apply_visible(id, static_root, vis))
		steps.append(func(): _apply_visible(id, dynamic_root, vis))
		steps.append(func(): _apply_process(id, proc))
	else:
		# stop processing first, then hide
		steps.append(func(): _apply_process(id, proc))
		steps.append(func(): _apply_visible(id, dynamic_root, vis))
		steps.append(func(): _apply_visible(id, static_root, vis))
	var i := 0
	while i < _hooks.size():
		var start := i
		steps.append(func(): _apply_hooks(id, target, start))
		i += HOOK_CHUNK
	return steps


func _apply_visible(id: int, root: Node3D, v: bool) -> void:
	if id != _tid or root == null:
		return
	root.visible = v


func _apply_process(id: int, on: bool) -> void:
	if id != _tid or dynamic_root == null:
		return
	dynamic_root.process_mode = _dynamic_mode_on if on else Node.PROCESS_MODE_DISABLED


func _apply_hooks(id: int, target: int, start: int) -> void:
	if id != _tid:
		return
	var end := mini(start + HOOK_CHUNK, _hooks.size())
	for k in range(start, end):
		var h := _hooks[k]
		if is_instance_valid(h):
			h.call(&"_zone_state_changed", int(target))
```

**File: `res://perf/zone_door.gd`**
```gdscript
class_name ZoneDoor
extends Node3D
## A connection between two Zones (or between one Zone and the outside).
## Your existing door logic must call set_open(true) at the START of the opening
## animation and set_open(false) when the door has finished closing.

signal open_changed(opened: bool)
signal opening_started

@export var zone_a: Zone
@export var zone_b: Zone                 ## leave empty for an exterior door (airlock outer door)
@export var leads_outside := false       ## true for doors that open onto Mars
@export var transparent := false         ## glass door: sight line exists even when closed
@export var closed_occluder: OccluderInstance3D  ## optional: only enabled while the door is closed
@export var is_open := false: set = set_open


func _ready() -> void:
	add_to_group(&"zone_door")
	_sync_occluder()


func other(z: Zone) -> Zone:
	return zone_b if z == zone_a else zone_a


func lets_sight_through() -> bool:
	return is_open or transparent


func set_open(v: bool) -> void:
	if v == is_open:
		return
	is_open = v
	if is_open:
		opening_started.emit()
	_sync_occluder()
	open_changed.emit(is_open)


func _sync_occluder() -> void:
	if closed_occluder != null:
		closed_occluder.visible = not is_open
```

**File: `res://perf/zone_manager.gd`**
```gdscript
class_name ZoneManager
extends Node
## One instance per level. Decides which Zones are COLD / VIEW_ONLY / WARM / ACTIVE and applies
## the changes inside a small per-frame time budget so no frame ever does a big batch of work.
##
## Rules (inside the colony):
##   current room                         -> ACTIVE
##   rooms within PerfSettings.warm_hops  -> WARM   (visible + processing, so entering is instant)
##   near a door (prewarm_distance)       -> also WARM the rooms around the room behind that door
##   everything else                      -> COLD, but only after cold_delay seconds (hysteresis)
## Rules (player outside the colony):
##   interiors with windows within outside_interior_distance -> VIEW_ONLY
##   airlock (and its neighbours) when approaching an exterior door -> WARM
##   everything else -> COLD

signal graph_ready
signal current_zone_changed(zone: Zone)
signal player_outside_changed(outside: bool)

const POLL_INTERVAL := 0.1   # s between target recalculations (10 Hz is plenty)
const OUTSIDE_GRACE := 0.3   # s outside every zone's bounds before we call it "outside"

@export var player: Node3D

var zones: Array[Zone] = []
var doors: Array[ZoneDoor] = []
var current: Zone = null
var player_outside := false
var is_graph_ready := false

var _wake_q: Array[Callable] = []
var _sleep_q: Array[Callable] = []
var _cold_since: Dictionary = {}
var _acc := 0.0
var _none_time := 0.0
var _was_enabled := true


func _ready() -> void:
	add_to_group(&"zone_manager")
	# Wait one frame so every Zone / ZoneDoor has finished its own _ready().
	await get_tree().process_frame
	_build_graph()
	is_graph_ready = true
	graph_ready.emit()
	if player != null:
		_update_targets(true)


func _process(delta: float) -> void:
	if not is_graph_ready or player == null:
		return
	if not PerfSettings.zones_enabled:
		if _was_enabled:
			_was_enabled = false
			_wake_q.clear()
			_sleep_q.clear()
			for z in zones:
				z.apply_immediately(Zone.State.ACTIVE)
		return
	_was_enabled = true
	_acc += delta
	if _acc >= POLL_INTERVAL:
		_acc = 0.0
		_update_targets(false)
	_run_queue()


func queue_length() -> int:
	return _wake_q.size() + _sleep_q.size()


## Call after any teleport, respawn, fast travel or save-game load, ideally while the screen is
## faded to black. Applies the correct state to every zone immediately instead of time-slicing.
func snap() -> void:
	_wake_q.clear()
	_sleep_q.clear()
	_cold_since.clear()
	if is_graph_ready and player != null:
		_update_targets(true)


# ---------------------------------------------------------------- graph

func _build_graph() -> void:
	zones.clear()
	doors.clear()
	for n in get_tree().get_nodes_in_group(&"zone"):
		var z := n as Zone
		if z != null:
			z.neighbors.clear()
			zones.append(z)
	for n in get_tree().get_nodes_in_group(&"zone_door"):
		var d := n as ZoneDoor
		if d == null:
			continue
		doors.append(d)
		if d.zone_a != null and d.zone_b != null:
			if not d.zone_a.neighbors.has(d.zone_b):
				d.zone_a.neighbors.append(d.zone_b)
			if not d.zone_b.neighbors.has(d.zone_a):
				d.zone_b.neighbors.append(d.zone_a)


## Zones reachable within `hops` doors (closed or open). Includes `start`.
func zones_within_hops(start: Zone, hops: int) -> Array[Zone]:
	var out: Array[Zone] = []
	if start == null:
		return out
	var seen: Dictionary = {start: true}
	var frontier: Array[Zone] = [start]
	for _h in hops:
		var nxt: Array[Zone] = []
		for z in frontier:
			for n in z.neighbors:
				if not seen.has(n):
					seen[n] = true
					nxt.append(n)
		frontier = nxt
	for k in seen.keys():
		out.append(k as Zone)
	return out


## Zones you could see into by looking through doors that are open (or glass). Includes `start`.
func zones_visible_through_open_doors(start: Zone, hops: int) -> Array[Zone]:
	var out: Array[Zone] = []
	if start == null:
		return out
	var seen: Dictionary = {start: true}
	var frontier: Array[Zone] = [start]
	for _h in hops:
		var nxt: Array[Zone] = []
		for z in frontier:
			for d in doors:
				if d.zone_a == null or d.zone_b == null:
					continue
				if d.zone_a != z and d.zone_b != z:
					continue
				if not d.lets_sight_through():
					continue
				var o := d.other(z)
				if not seen.has(o):
					seen[o] = true
					nxt.append(o)
		frontier = nxt
	for k in seen.keys():
		out.append(k as Zone)
	return out


# ---------------------------------------------------------------- locating the player

## Sticky lookup: stay in the current zone while the player is still inside its bounds.
## Zone bounds should overlap by ~0.3 m at doorways so there is never a gap.
func _locate(p: Vector3) -> Zone:
	if current != null and current.contains_point(p):
		return current
	if current != null:
		for z in current.neighbors:
			if z.contains_point(p):
				return z
	for z in zones:
		if z.contains_point(p):
			return z
	return null


# ---------------------------------------------------------------- targets

func _update_targets(initial: bool) -> void:
	var p := player.global_position
	var found := _locate(p)
	if found != null:
		_none_time = 0.0
		if found != current:
			current = found
			current_zone_changed.emit(current)
	else:
		_none_time += POLL_INTERVAL
		if initial:
			_none_time = OUTSIDE_GRACE
	var outside := current == null or _none_time >= OUTSIDE_GRACE
	if outside != player_outside:
		player_outside = outside
		player_outside_changed.emit(outside)

	var targets: Dictionary = {}
	for z in zones:
		targets[z] = Zone.State.COLD
	if player_outside:
		_targets_outside(p, targets)
	else:
		_targets_inside(p, targets)
	_apply_targets(targets, p, initial)


func _raise(targets: Dictionary, z: Zone, s: int) -> void:
	var cur: int = targets[z]
	targets[z] = maxi(cur, s)


func _targets_outside(p: Vector3, targets: Dictionary) -> void:
	for z in zones:
		if z.has_exterior_view and z.distance_to_bounds(p) <= PerfSettings.outside_interior_distance:
			_raise(targets, z, Zone.State.VIEW_ONLY)
	for d in doors:
		if not d.leads_outside:
			continue
		var inner := d.zone_a if d.zone_a != null else d.zone_b
		if inner == null:
			continue
		if d.global_position.distance_to(p) <= PerfSettings.entrance_prewarm_distance:
			for z in zones_within_hops(inner, PerfSettings.warm_hops):
				_raise(targets, z, Zone.State.WARM)


func _targets_inside(p: Vector3, targets: Dictionary) -> void:
	_raise(targets, current, Zone.State.ACTIVE)
	for z in zones_within_hops(current, PerfSettings.warm_hops):
		_raise(targets, z, Zone.State.WARM)
	# Close to a door: also warm everything around the room behind it, so that walking
	# through never has to wake rooms at the moment of crossing.
	for d in doors:
		if d.zone_a == null or d.zone_b == null:
			continue
		if d.zone_a != current and d.zone_b != current:
			continue
		if d.global_position.distance_to(p) > PerfSettings.prewarm_distance:
			continue
		for z in zones_within_hops(d.other(current), PerfSettings.warm_hops):
			_raise(targets, z, Zone.State.WARM)


func _apply_targets(targets: Dictionary, p: Vector3, initial: bool) -> void:
	if initial:
		for z in zones:
			var t0: int = targets[z]
			z.apply_immediately(t0)
		return

	var now := Time.get_ticks_msec() * 0.001
	var wakes: Array[Zone] = []
	var sleeps: Array[Zone] = []
	for z in zones:
		var want: int = targets[z]
		var have: int = z.state
		if want == have:
			_cold_since.erase(z)
		elif want > have:
			_cold_since.erase(z)
			wakes.append(z)
		elif want >= Zone.State.WARM:
			# ACTIVE -> WARM costs nothing, no need to delay it
			sleeps.append(z)
		else:
			# Losing visibility / processing: wait cold_delay seconds first (hysteresis)
			if not _cold_since.has(z):
				_cold_since[z] = now
			if now - float(_cold_since[z]) >= PerfSettings.cold_delay:
				_cold_since.erase(z)
				sleeps.append(z)

	# Wake the rooms closest to the player first.
	wakes.sort_custom(func(a: Zone, b: Zone) -> bool:
		return a.distance_to_bounds(p) < b.distance_to_bounds(p))
	for z in wakes:
		var tw: int = targets[z]
		_wake_q.append_array(z.plan_transition(tw))
	for z in sleeps:
		var ts: int = targets[z]
		_sleep_q.append_array(z.plan_transition(ts))


## Runs queued steps until the per-frame time budget is used up (always at least one step).
## Wake steps always run before sleep steps.
func _run_queue() -> void:
	var start := Time.get_ticks_usec()
	while not (_wake_q.is_empty() and _sleep_q.is_empty()):
		var step: Callable
		if not _wake_q.is_empty():
			step = _wake_q.pop_front()
		else:
			step = _sleep_q.pop_front()
		step.call()
		if Time.get_ticks_usec() - start >= PerfSettings.step_budget_usec:
			break
```

### 5.4 Wiring and hooks
- Add the `ZoneManager` node to the level, assign `player`. Add `Zone` scripts to every room root and assign `static_root`, `dynamic_root`, `bounds_root`. Add `ZoneDoor` scripts and assign their exports.
- Anything in `Dynamic` that should throttle itself implements `func _zone_state_changed(new_state: int) -> void` (`Zone.State.COLD/VIEW_ONLY/WARM/ACTIVE`). Typical uses: `GPUParticles3D.emitting = (new_state == Zone.State.ACTIVE)`, lower the update rate of an `AnimationTree` in `WARM`, mute a looping ambient sound when `COLD`. Implement it for at least particles and looping audio found in the inventory.
- **Roaming characters** and anything that crosses room boundaries go under `Persistent` (not inside a Zone). If a roaming NPC must be frozen when far from the player, let `ViewActivator` (Phase 4) do that.
- **Teleport, respawn, fast travel and save-load:** call `zone_manager.snap()` right after moving the player (ideally while the screen is faded). It applies all zone states immediately instead of time-slicing.
- Physics detail: bodies and areas under a node with `process_mode = DISABLED` are removed from the physics space by default (`disable_mode = DISABLE_MODE_REMOVE` on `CollisionObject3D`; confirm in your version's class reference and leave that default). `RigidBody3D`s in cold rooms therefore freeze, which is intended.
- Audio detail: decide per sound whether it should stop with the room. Sounds that must continue go to `Persistent` or are handled in `_zone_state_changed`.
- Do not give `Static` roots a script or children that need processing. If a "static" node turns out to have logic, move it to `Dynamic`.

### 5.5 Defaults to start with
`warm_hops = 1`, `prewarm_distance = 4.0`, `cold_delay = 2.0`, `step_budget_usec = 1500`, poll rate 10 Hz (all in `PerfSettings` / `ZoneManager`). Tune using the HUD: the queue length should return to 0 within a few frames of crossing a door.

## 6. Phase 3: Exterior controller (Mars hidden only when sealed in)

**File: `res://perf/exterior_controller.gd`**
```gdscript
class_name ExteriorController
extends Node
## Hides the Mars environment only when the player cannot possibly see it:
## current room has no window, and no open/glass door chain leads to a room that does.
## It never frees or reloads anything: it only flips `visible`, so showing it again is instant.
##
## Safety rules:
##   - When unsure (player outside, no current zone) the exterior is SHOWN.
##   - Showing is immediate. Hiding waits exterior_hide_delay seconds of "not needed".
##   - A door that starts opening forces an immediate re-check, and a door within
##     exterior_door_prewarm metres that leads toward a window/outside keeps Mars shown,
##     so Mars is already on screen before the door has moved.

const CHECK_INTERVAL := 0.1

@export var zone_manager: ZoneManager
@export var mars_root: Node3D          ## terrain, rocks, props. NOT the WorldEnvironment, NOT the player.
@export var mars_dynamic_root: Node3D  ## optional: only scripted Mars things (dust devils, rovers).
                                       ## Never put terrain colliders here.
@export var sun: DirectionalLight3D    ## optional, see PerfSettings.sun_off_when_exterior_hidden

var shown := true

var _acc := 0.0
var _unneeded_for := 0.0


func _ready() -> void:
	add_to_group(&"exterior_controller")
	if zone_manager.is_graph_ready:
		_connect_doors()
	else:
		zone_manager.graph_ready.connect(_connect_doors, CONNECT_ONE_SHOT)


func _connect_doors() -> void:
	for d in zone_manager.doors:
		d.opening_started.connect(_on_door_opening)


func _on_door_opening() -> void:
	_evaluate(0.0)


func _process(delta: float) -> void:
	if not PerfSettings.exterior_cull_enabled:
		if not shown:
			_set_shown(true)
		return
	_acc += delta
	if _acc < CHECK_INTERVAL:
		return
	var dt := _acc
	_acc = 0.0
	_evaluate(dt)


func _evaluate(dt: float) -> void:
	if not zone_manager.is_graph_ready:
		return
	if _exterior_needed():
		_unneeded_for = 0.0
		if not shown:
			_set_shown(true)
	else:
		_unneeded_for += dt
		if shown and _unneeded_for >= PerfSettings.exterior_hide_delay:
			_set_shown(false)


func _exterior_needed() -> bool:
	var zm := zone_manager
	if zm.player_outside or zm.current == null or zm.player == null:
		return true  # fail-safe

	# 1. Can a sight line through open/glass doors reach a room with windows or an open exterior door?
	var seen := zm.zones_visible_through_open_doors(zm.current, PerfSettings.exterior_check_hops)
	for z in seen:
		if z.has_exterior_view:
			return true
	for d in zm.doors:
		if d.leads_outside and d.lets_sight_through():
			if seen.has(d.zone_a) or seen.has(d.zone_b):
				return true

	# 2. Is the player about to open a door that leads toward the outside?
	var p := zm.player.global_position
	for d in zm.doors:
		if d.zone_a != zm.current and d.zone_b != zm.current:
			continue
		if d.global_position.distance_to(p) > PerfSettings.exterior_door_prewarm:
			continue
		if d.leads_outside:
			return true
		var o := d.other(zm.current)
		if o != null and o.has_exterior_view:
			return true
	return false


func _set_shown(v: bool) -> void:
	shown = v
	if mars_root != null:
		mars_root.visible = v
	if mars_dynamic_root != null:
		mars_dynamic_root.process_mode = Node.PROCESS_MODE_INHERIT if v else Node.PROCESS_MODE_DISABLED
	if sun != null and PerfSettings.sun_off_when_exterior_hidden:
		sun.visible = v
```

Setup:
1. Put everything that is "outside" (terrain, rocks, props, dust effects, rovers) under one `MarsRoot` node. **Do not** put the player, `WorldEnvironment`, the sun, the sky or the colony under it. Terrain and rock colliders stay enabled at all times (only `visible` is toggled, so re-showing is instant and no physics bodies are ever re-added).
2. Optionally create `MarsDynamic` under `MarsRoot` for purely scripted/animated Mars things (they get paused when Mars is hidden) and assign it as `mars_dynamic_root`. Never put terrain colliders there.
3. Add an `ExteriorController` node, assign `zone_manager`, `mars_root`, optionally `mars_dynamic_root` and `sun`. `sun_off_when_exterior_hidden` is **off** by default; only try it after checking, in a sealed room, that interior lighting is unchanged.
4. Behaviour to verify:

| Situation | Mars |
|---|---|
| Player outside the colony | shown |
| Player in a room with a window | shown |
| Sealed room, all doors closed | hidden after 1.5 s |
| Sealed room, door open to a room with a window (or chain of up to 2 open doors) | shown |
| Sealed room, within 4 m of a door that leads toward a window or outside | shown |
| Any door starts opening | re-checked immediately; shown if it can lead to a view |
| Player teleported or not inside any zone | shown (fail-safe) |

If glass or windows exist in *doors* that are not otherwise flagged, set `ZoneDoor.transparent = true`.

## 7. Phase 4: ViewActivator (gameplay gating, fast-turn safe)

**File: `res://perf/view_activator.gd`**
```gdscript
class_name ViewActivator
extends Node
## Gameplay-side "only care about what the player can see" system.
##
## IMPORTANT: this does NOT hide or show anything. Godot already frustum-culls rendering every
## frame, so a fast camera turn can never cause a rendering spike. This node only puts
## EXPENSIVE ENTITIES (animated NPCs, particle rigs, scripted props) to sleep when they are
## outside the view cone, and wakes them before they come into view.
##
## An entity opts in by being in group "view_gated" (a Node3D). Optional hooks on the entity:
##   _view_state_changed(awake: bool)   e.g. stop/start particles, pause an AnimationTree
## Optional meta on the entity:
##   "view_radius" (float, default 1.0) rough size, so large things wake earlier.
##
## How it handles fast turning:
##   1. Wide cone: half-diagonal FOV + cone_margin_deg.
##   2. Look-ahead: the cone grows with the camera's angular speed (up to max_extra_deg).
##   3. Anything within near_radius is always awake (covers "behind you" threats).
##   4. Sleeping needs a bigger cone (sleep_extra_deg) AND sleep_delay seconds: no flicker.
##   5. Wake-ups are rate limited (wakes_per_tick) and sorted by angle, closest-to-centre first.

@export var camera: Camera3D
@export var near_radius := 12.0
@export var far_radius := 90.0
@export var cone_margin_deg := 20.0
@export var sleep_extra_deg := 10.0
@export var lookahead_s := 0.25
@export var max_extra_deg := 60.0
@export var sleep_delay := 1.5
@export var tick_hz := 10.0
@export var wakes_per_tick := 6

const META_AWAKE := &"va_awake"
const META_MODE := &"va_mode"
const META_OUT := &"va_out_since"
const META_RADIUS := &"view_radius"

var _acc := 0.0
var _last_fwd := Vector3.ZERO
var _ang_speed := 0.0
var _was_enabled := true


func _process(delta: float) -> void:
	if camera == null:
		return
	if not PerfSettings.view_activation_enabled:
		if _was_enabled:
			_was_enabled = false
			for n in get_tree().get_nodes_in_group(&"view_gated"):
				_set_awake(n as Node3D, true)
		return
	_was_enabled = true
	_acc += delta
	if _acc < 1.0 / tick_hz:
		return
	var dt := _acc
	_acc = 0.0
	_tick(dt)


func _tick(dt: float) -> void:
	var cam_pos := camera.global_position
	var fwd := -camera.global_transform.basis.z
	if _last_fwd != Vector3.ZERO:
		_ang_speed = lerpf(_ang_speed, fwd.angle_to(_last_fwd) / dt, 0.5)
	_last_fwd = fwd

	var half := _half_diag_angle()
	var extra := clampf(_ang_speed * lookahead_s, 0.0, deg_to_rad(max_extra_deg))
	var wake_angle := half + deg_to_rad(cone_margin_deg) + extra
	var sleep_angle := wake_angle + deg_to_rad(sleep_extra_deg)
	var now := Time.get_ticks_msec() * 0.001

	var to_wake: Array = []  # items: [angle, node, is_near]
	for n in get_tree().get_nodes_in_group(&"view_gated"):
		var e := n as Node3D
		if e == null or not e.is_inside_tree():
			continue
		var awake: bool = e.get_meta(META_AWAKE, true)
		var to := e.global_position - cam_pos
		var d := to.length()
		var near := d <= near_radius
		var inside := false
		var angle := 0.0
		if near:
			inside = true
		elif d <= far_radius * (1.1 if awake else 1.0):
			var r: float = e.get_meta(META_RADIUS, 1.0)
			angle = to.angle_to(fwd) - asin(clampf(r / d, 0.0, 1.0))
			inside = angle <= (sleep_angle if awake else wake_angle)

		if awake:
			if inside:
				e.set_meta(META_OUT, -1.0)
			else:
				var since: float = e.get_meta(META_OUT, -1.0)
				if since < 0.0:
					e.set_meta(META_OUT, now)
				elif now - since >= sleep_delay:
					_set_awake(e, false)
		elif inside:
			to_wake.append([angle, e, near])

	to_wake.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var budget := wakes_per_tick
	for item in to_wake:
		var is_near: bool = item[2]
		if budget <= 0 and not is_near:
			break
		_set_awake(item[1] as Node3D, true)
		budget -= 1


func _set_awake(e: Node3D, awake: bool) -> void:
	if e == null:
		return
	e.set_meta(META_AWAKE, awake)
	e.set_meta(META_OUT, -1.0)
	if not e.has_meta(META_MODE):
		e.set_meta(META_MODE, int(e.process_mode))
	var base: int = e.get_meta(META_MODE)
	if base == Node.PROCESS_MODE_DISABLED:
		base = Node.PROCESS_MODE_INHERIT
	# Only ever toggles between the node's own authored mode and DISABLED, so it
	# composes with ZoneManager (which disables whole Dynamic roots from above).
	e.set(&"process_mode", base if awake else int(Node.PROCESS_MODE_DISABLED))
	if e.has_method(&"_view_state_changed"):
		e.call(&"_view_state_changed", awake)


## Half of the screen diagonal's field of view, in radians (the widest angle that can be on screen).
func _half_diag_angle() -> float:
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var tan_half := tan(deg_to_rad(camera.fov) * 0.5)
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		tan_half /= aspect  # fov was horizontal; convert to vertical
	return atan(tan_half * sqrt(1.0 + aspect * aspect))
```

Setup:
1. Add a `ViewActivator` node to the level and assign the player's `Camera3D`.
2. Tag only **expensive** things (add the node to group `view_gated`): animated NPCs, particle rigs, scripted props with `_process`. Do not tag cheap things; do not tag the player or anything gameplay-critical that must act when unseen (turrets that shoot you from behind should either stay untagged or have a large `view_radius`/the near radius cover them). If the project has such enemies, list them in the notes and keep them untagged.
3. Large things: `set_meta("view_radius", r)` with a rough radius so big objects wake earlier.
4. Implement `_view_state_changed(awake: bool)` on tagged entities where freezing looks wrong (for example stop footstep sounds, keep an idle animation looping on a low update rate).
5. `ViewActivator` only toggles between a node's own authored `process_mode` and `DISABLED`, so it composes with `ZoneManager` (which disables whole `Dynamic` roots from above).
6. `VisibleOnScreenEnabler3D` is the built-in alternative for placing in a scene, but it is an approximate heuristic, has no angular margin or look-ahead (you can only enlarge its box), ignores walls unless occlusion culling is enabled, requires `visible = true`, and **only affects nodes that were in the scene at initialisation (not nodes spawned later)**. Use it only for static, hand-placed things if you prefer; for anything spawned at runtime, use `ViewActivator`.
7. Defaults: `near_radius 12`, `far_radius 90`, `cone_margin_deg 20`, `sleep_extra_deg 10`, `lookahead_s 0.25`, `max_extra_deg 60`, `sleep_delay 1.5`, `tick_hz 10`, `wakes_per_tick 6`. For more than about 2000 tagged entities, process a rotating slice of the list per tick instead of all of it.
8. Test with the spin test (S5): no frame spike, no entity visibly "waking late" (an NPC that was behind you must already be animating when it enters view).

## 8. Phase 5: Distance LOD (colony from outside, and Mars)

### 8.1 Build the proxy meshes (T1 and T2)
Create proxies of the colony **exterior shell only** (no interior geometry), with the **origin at the colony's centre**:
- **T1:** all exterior meshes joined into one object, decimated to about 25% of triangles, with a single simplified material (no normal map, no rim, no clearcoat, no anisotropy, no height, no subsurface, no backlight, no refraction, no proximity fade; the docs point out that cheaper materials matter because LOD meshes reduce vertex work but not per-pixel shading work).
- **T2:** the same joined, decimated to about 3-5%, one flat/low-cost material (unshaded or a single albedo colour with the colony's average tone), shadows off.
Check the silhouettes in the viewport at distance; raise the ratio if antennas, domes or landing pads disappear.

If you have Blender access (or the Blender tool), use this as a starting point. Select the exterior mesh objects, put the 3D cursor at the colony centre, then run it:
```python
import bpy

TIERS = {"T1": 0.25, "T2": 0.05}   # Decimate ratio = fraction of triangles kept
src = [o for o in bpy.context.selected_objects if o.type == 'MESH']
assert src, "Select the colony EXTERIOR mesh objects first (not interiors)."

for name, ratio in TIERS.items():
    bpy.ops.object.select_all(action='DESELECT')
    copies = []
    for o in src:
        c = o.copy()
        c.data = o.data.copy()
        bpy.context.collection.objects.link(c)
        c.select_set(True)
        copies.append(c)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join()
    proxy = bpy.context.view_layer.objects.active
    proxy.name = "Colony_" + name
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')   # origin = 3D cursor = colony centre
    mod = proxy.modifiers.new("Decimate", 'DECIMATE')
    mod.ratio = ratio
    bpy.ops.object.modifier_apply(modifier=mod.name)
```
Export each proxy as `.glb` into `res://lod/` (for example `colony_t1.glb`, `colony_t2.glb`). Without Blender, create the proxies from the existing meshes some other way you can verify (report it). For T2 disable import LOD generation (it is already minimal).

### 8.2 Wire the tiers together
Instance the two proxies under the colony at the colony centre (same transform as the exterior). Then add `ColonyLod`:

**File: `res://perf/colony_lod.gd`**
```gdscript
class_name ColonyLod
extends Node
## Hierarchical LOD for the colony EXTERIOR, seen from outside.
##
##   Tier 0  existing full-detail exterior meshes (many nodes)   close
##   Tier 1  one merged, decimated shell (~25% triangles)        middle distance
##   Tier 2  one very low-poly silhouette (~3-5% triangles)      far away
##
## Uses visibility ranges + Visibility Parent (Godot's HLOD): a node is hidden while its
## visibility-parent is visible according to the parent's own range, so the tiers swap
## without gaps or double-drawing. Distances are measured from each proxy's ORIGIN, so put
## the origin of tier 1 and tier 2 at the centre of the colony.
##
## Read the example on https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html
## and confirm the behaviour in the editor (Perspective > Display Advanced > wireframe) before
## trusting these numbers.

@export var tier0_root: Node3D
@export var tier1: GeometryInstance3D
@export var tier2: GeometryInstance3D
@export var tier1_begin := 120.0   ## m: Tier 0 -> Tier 1. Use (colony radius + ~40 m).  (80 m radius example)
@export var tier2_begin := 280.0   ## m: Tier 1 -> Tier 2. Use (colony radius + ~200 m).
@export var margin := 8.0          ## m of hysteresis so the swap never flickers
@export var use_alpha_fade := false  ## smoother, but forces transparent rendering during the fade
@export var tier1_casts_shadow := true
@export var tier2_casts_shadow := false


func _ready() -> void:
	var mode: GeometryInstance3D.VisibilityRangeFadeMode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	if use_alpha_fade:
		mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

	tier2.visibility_range_begin = tier2_begin
	tier2.visibility_range_begin_margin = margin
	tier2.visibility_range_end = 0.0
	tier2.visibility_range_fade_mode = mode
	tier2.cast_shadow = _shadow(tier2_casts_shadow)

	tier1.visibility_range_begin = tier1_begin
	tier1.visibility_range_begin_margin = margin
	tier1.visibility_range_end = 0.0
	tier1.visibility_range_fade_mode = mode
	tier1.cast_shadow = _shadow(tier1_casts_shadow)
	tier1.visibility_parent = tier1.get_path_to(tier2)

	for n in tier0_root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		g.visibility_parent = g.get_path_to(tier1)


func _shadow(on: bool) -> GeometryInstance3D.ShadowCastingSetting:
	return GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
```

- `tier0_root` = the node containing the full-detail exterior meshes (the `ExteriorShell` node).
- Visibility ranges are measured from each node's **origin**, which is why the proxies' origins sit at the colony centre. So set `tier1_begin = colony_radius + 40` and `tier2_begin = colony_radius + 200` (example for an 80 m radius: 120 and 280, which are the script defaults). Measure the colony radius from the exterior meshes' combined bounding box and write it in the notes.
- This is Godot's HLOD pattern: T0's `visibility_parent` is T1, T1's is T2, and each parent has its own visibility-range begin. A child is hidden while its parent is visible by range, so there are no gaps and no double drawing. **Open the visibility ranges page (section 14) and compare with the page's own example. Then verify in the editor and in game** with the wireframe view while moving the camera back and forth across each boundary.
- Hysteresis comes from `margin` (8 m) so the swap does not flicker. Default fade mode is **disabled** (hard swap, cheapest); alpha fade (`use_alpha_fade = true`) forces transparent rendering during the transition and can show sorting artefacts, so only enable it if the pop is clearly visible even with fog on.
- If the colony is large (about 150 m or more across), make one HLOD group **per module/wing** instead of one for the whole colony, so a module far away drops detail while one nearby keeps it.
- Interiors do not need tiers: they are `COLD` when the player is outside (Phase 2) and `VIEW_ONLY` only for windowed rooms closer than `outside_interior_distance` (25 m).
- Record the triangle count (HUD primitives) at S4 distances before and after.

### 8.3 Mars environment
Inspect how the terrain and props are built and do the matching items:
- **Terrain is one giant mesh:** split it into chunks (for example 128 x 128 m) with their own LOD, or switch to a clipmap terrain (if the project already uses Terrain3D, use its built-in LOD and its occluder baking, which the docs describe). Do not change terrain systems without telling me; if a switch is warranted, write the proposal in the notes and keep the current terrain working.
- **Props (rocks, equipment, flags, antennas):** every `GeometryInstance3D` gets `visibility_range_end` from its size: `end ≈ 150 x largest dimension in metres` (at 1080p with a 75 degree FOV that is roughly 5 pixels tall, where the object stops mattering). Examples: 0.3 m pebble -> 45 m; 1 m rock -> 150 m; 4 m boulder -> 600 m. Hero objects and landmarks that need to be visible far away have no end. Set `visibility_range_end_margin` to 10% of `end`. For MultiMesh chunks use the same rule with the chunk's biggest item size, or split the chunk into size classes.
- Write one `EditorScript` tool (`res://perf/tools/apply_visibility_ranges.gd`, `@tool`, run from File > Run) that walks `MarsRoot` and applies this rule to nodes that do not already have a visibility range, logging what it changed, with a dry-run mode. Do not overwrite hand-authored ranges.
- Dust, decals, `Label3D`, markers: set visibility range or distance fade so they disappear at a sensible distance.
- Mesh LOD threshold presets: low 4.0, medium 2.0, high 1.0 via `PerfSettings.apply_quality()`; hook them to the game's graphics settings menu if one exists.

## 9. Phase 6: Shader warm-up, diagnostics and (optional) streaming

### 9.1 Warm-up pass behind the loading screen
Drawing something for the first time can force the GPU driver to compile a pipeline, which shows up as a hitch. Godot 4.4 added ubershaders and pipeline precompilation (Forward+/Mobile only), which removes most of these, but not every case (the docs list the cases it cannot detect, and the Compatibility renderer has no such support, where the old approach of showing every material for at least one frame in the view frustum during loading is the recommended workaround).

**File: `res://perf/shader_warmup.gd`**
```gdscript
class_name ShaderWarmup
extends Node
## Run once behind a full-screen black overlay (your loading screen) so every material, light and
## shadow variant has been drawn at least once before the player sees anything. This prevents the
## "first time this room becomes visible" hitch. Godot 4.4+ precompiles many pipelines on load,
## but not all cases; check the pipeline compilation monitors, and on the Compatibility renderer
## this manual approach is the only option.
##
## Adapt: disable the player's controller and mouse-look while this runs, and keep the black
## overlay on top until `finished` is emitted.

signal finished

@export var zone_manager: ZoneManager
@export var camera: Camera3D
@export var mars_root: Node3D
@export var mars_viewpoints: Array[Marker3D] = []
@export var frames_per_stop := 3
@export var eye_height := 1.6


func run() -> void:
	var saved := camera.global_transform
	var mars_was_visible := mars_root.visible
	mars_root.visible = true
	for z in zone_manager.zones:
		z.apply_immediately(Zone.State.WARM)
	await get_tree().process_frame

	for z in zone_manager.zones:
		for yaw in [0.0, 90.0, 180.0, 270.0]:
			camera.global_position = z.global_position + Vector3.UP * eye_height
			camera.global_rotation_degrees = Vector3(0.0, yaw, 0.0)
			for _i in frames_per_stop:
				await get_tree().process_frame

	for m in mars_viewpoints:
		camera.global_transform = m.global_transform
		for _i in frames_per_stop:
			await get_tree().process_frame

	camera.global_transform = saved
	mars_root.visible = mars_was_visible
	# ZoneManager will cool the zones down again (after PerfSettings.cold_delay seconds).
	finished.emit()
```

1. Call `await warmup.run()` during the game's loading screen (a full-screen black overlay must cover the screen), then `zone_manager.snap()`. Place a few `Marker3D` viewpoints looking at the main Mars scenery and at the colony from outside, and assign them to `mars_viewpoints`.
2. While running, disable the player controller and mouse look so nothing fights the camera.
3. On 4.4+, open the editor's Debugger > Monitors and check the pipeline compilation monitors (compilations are counted per step, for example the Surface step) during S2 and S4. If compilations spike during gameplay after the warm-up, note what triggered them (the docs list typical triggers such as turning on MSAA or instancing a `VoxelGI` at runtime) and avoid doing that at runtime.

### 9.2 Optional: threaded streaming (only if memory or load time forces it)
**Decision gate:** do this only if peak RAM/VRAM or startup time is a real problem *after* Phases 1-5. Keeping all zones resident is simpler and hitch-free. If the gate is passed:
- Make each zone its own `.tscn`. Load with `ResourceLoader.load_threaded_request(path, "", true)`, poll `ResourceLoader.load_threaded_get_status(path, progress)`, and only call `load_threaded_get(path)` once the status is `THREAD_LOAD_LOADED` (calling it early blocks).
- Instantiating a large scene and `add_child` still run on the main thread, and forum reports show hitching from that even with threaded loading. So: keep zone scenes small, start loading rooms **two hops** ahead (never in the frame the player crosses a door), instantiate the scene while the zone is `COLD`, and add its children over several frames (for example 50 nodes per frame) before it is ever allowed to become `WARM`.
- Never unload a zone the player could return to within 30 s; unload only zones more than 3 hops away. Report RAM before and after.

## 10. Phase 7: Verification and acceptance

Re-run S1-S5 with **everything on**, then with each system off one at a time (Ctrl+2/3/4/5/6) so each system's individual contribution is documented. Fill a table in `docs/perf/final_report.md`: scenario, baseline vs now (avg, p99, worst frame ms, draw calls, primitives, objects, video memory, node count).

**Acceptance criteria** (if one cannot be met, say why and what would be needed):
1. No visual difference in normal play: same rooms, same lighting, same Mars. Compare screenshots at the same positions (indoors, at a window, outside at 20/100/300/800/1500 m) with all systems off vs on.
2. **Door crossing:** across every door in S2, the worst frame in the 1 s around the crossing is no more than 2x the median frame time and under 33 ms. Report the worst offender and its room.
3. **Windowless room:** Mars is hidden within about 1.5 s of becoming unneeded. Opening a door that leads toward a window or outside shows Mars **before the door has visibly moved**, with no pop. Spam the door open/close 20 times: no flicker, no stuck state.
4. **Fast turning:** spin test indoors and outdoors: no frame over 2x the median, no crash, and no tagged entity visibly "waking late" when it enters the view.
5. **Outside LOD:** walk away from the airlock to 1500 m and back; at each tier boundary there is no visible gap, no double-drawing, no flicker (use the wireframe and a screenshot pair). Triangle count at S4 distances drops by the expected factor.
6. **Teleport/respawn/load game** into a cold room: `snap()` leaves the destination room and its neighbours correct on the first visible frame.
7. **Physics:** objects in a cold room are frozen and fall/behave normally when woken; nothing falls through a floor; nothing "wakes" with a velocity spike. The player can walk through every door with no collider issues.
8. **Memory:** video memory and node count do not grow over a 10 minute route repeated (no leaks from transitions).
9. **No regressions:** existing game scripts run without new errors or warnings in the output panel. Fix or report any.
10. **Average frame time improves** in S2 and S3 (indoors) and S4 (outdoors) versus baseline. State the numbers. If one does not improve, explain with profiler evidence.

## 11. Tuning table

| Setting | Default | Raise it when | Lower it when |
|---|---|---|---|
| `warm_hops` | 1 | rooms pop in down long open corridors | simulation is still too heavy |
| `prewarm_distance` | 4 m | hitches when stepping through doors | wake-ups are happening too early/too often |
| `cold_delay` | 2 s | rooms flicker when walking back and forth | memory/CPU still high |
| `step_budget_usec` | 1500 | queue stays long after door crossing | any frame spikes during transitions |
| `exterior_hide_delay` | 1.5 s | Mars flickers near windowed rooms | Mars is hidden too late |
| `exterior_check_hops` | 2 | Mars visible through long open-door chains | never needed lower |
| `exterior_door_prewarm` | 4 m | Mars appears late when approaching an airlock | n/a |
| `outside_interior_distance` | 25 m | windows show empty rooms | outside cost is high |
| `near_radius` (view) | 12 m | enemies behind the player act late | too many entities awake |
| `cone_margin_deg` | 20 | turning wakes things late | too many entities awake |
| `lookahead_s` | 0.25 | very fast turns still catch entities late | n/a |
| `tier1_begin` / `tier2_begin` | R+40 / R+200 | pop is visible | GPU still heavy at medium distance |
| `mesh_lod_threshold` | 1.0 | quality is poor | GPU-bound on weak hardware (use 2-4) |
| sun shadow max distance | 150 m | shadows cut off visibly | GPU-bound |

## 12. Reference code for Phase 0

**File: `res://perf/perf_settings.gd`** (autoload `PerfSettings`)
```gdscript
extends Node
## Autoload name: PerfSettings
## Master switches and tunables for every optimization system.
## Each system reads its values from here so you can toggle it live (see perf_hud.gd)
## and compare frame times with it ON vs OFF.

# --- Master switches (A/B testing) ---
var zones_enabled := true            # room sleep/wake system
var exterior_cull_enabled := true    # hide Mars when no window/open door can see it
var view_activation_enabled := true  # sleep expensive entities outside the view cone

# --- Zone system ---
var warm_hops := 1                   # rooms within this many doors of the current room stay WARM
var prewarm_distance := 4.0          # m: near a door, also warm the rooms behind it
var cold_delay := 2.0                # s: grace period before a room is allowed to go COLD
var step_budget_usec := 1500         # per-frame time slice for state changes (1.5 ms)

# --- Exterior (Mars) visibility ---
var exterior_hide_delay := 1.5       # s: Mars must be unneeded this long before it is hidden
var exterior_check_hops := 2         # how many open doors in a row a sight line may pass
var exterior_door_prewarm := 4.0     # m: show Mars early when near a door that leads toward it
var sun_off_when_exterior_hidden := false  # optional extra saving; verify interior lighting first

# --- Player outside the colony ---
var outside_interior_distance := 25.0  # m: interiors with windows stay visible (VIEW_ONLY) this close
var entrance_prewarm_distance := 15.0  # m: warm the airlock room when approaching an exterior door


## Mesh LOD aggressiveness. The engine default is 1.0 pixel ("perceptually lossless");
## higher values switch to simpler meshes sooner.
func apply_quality(preset: StringName) -> void:
	var root := get_tree().root
	match preset:
		&"low":
			root.mesh_lod_threshold = 4.0
		&"medium":
			root.mesh_lod_threshold = 2.0
		_:
			root.mesh_lod_threshold = 1.0
```

**File: `res://perf/perf_hud.gd`** (autoload `PerfHud`)
```gdscript
extends CanvasLayer
## Autoload name: PerfHud. Debug builds only.
##   Ctrl+1  show/hide HUD            Ctrl+2  zones on/off
##   Ctrl+3  exterior cull on/off     Ctrl+4  view activation on/off
##   Ctrl+5  occlusion culling on/off Ctrl+6  mesh LOD threshold 1 -> 2 -> 4
##   Ctrl+7  start/stop CSV logging to user://perf_*.csv
## The HUD keeps collecting frame times even while hidden.

const HISTORY := 600

var _label := Label.new()
var _frames := PackedFloat32Array()
var _since_update := 0.0
var _log: FileAccess = null
var _log_t0 := 0.0


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label.position = Vector2(12, 12)
	_label.add_theme_color_override(&"font_color", Color.WHITE)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 6)
	add_child(_label)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed):
		return
	var root := get_tree().root
	match event.keycode:
		KEY_1:
			visible = not visible
		KEY_2:
			PerfSettings.zones_enabled = not PerfSettings.zones_enabled
		KEY_3:
			PerfSettings.exterior_cull_enabled = not PerfSettings.exterior_cull_enabled
		KEY_4:
			PerfSettings.view_activation_enabled = not PerfSettings.view_activation_enabled
		KEY_5:
			root.use_occlusion_culling = not root.use_occlusion_culling
		KEY_6:
			root.mesh_lod_threshold = 2.0 if root.mesh_lod_threshold < 1.5 else (4.0 if root.mesh_lod_threshold < 3.0 else 1.0)
		KEY_7:
			_toggle_log()


func _process(delta: float) -> void:
	var ms := delta * 1000.0
	_frames.append(ms)
	if _frames.size() > HISTORY:
		_frames.remove_at(0)
	if _log != null:
		_write_log_row(ms)
	_since_update += delta
	if _since_update < 0.5:
		return
	_since_update = 0.0
	if visible:
		_label.text = _build_text()


func _stats() -> Dictionary:
	var sorted := _frames.duplicate()
	sorted.sort()
	var n := sorted.size()
	var sum := 0.0
	for f in _frames:
		sum += f
	return {
		"avg": sum / maxf(float(n), 1.0),
		"p99": sorted[int(n * 0.99)] if n > 0 else 0.0,
		"worst": sorted[n - 1] if n > 0 else 0.0,
	}


func _build_text() -> String:
	var s := _stats()
	var root := get_tree().root
	var zm := get_tree().get_first_node_in_group(&"zone_manager") as ZoneManager
	var ec := get_tree().get_first_node_in_group(&"exterior_controller") as ExteriorController
	var t := "FPS %d | avg %.2f ms | p99 %.2f ms | worst %.2f ms\n" % [
		Engine.get_frames_per_second(), s["avg"], s["p99"], s["worst"]]
	t += "draw calls %d | objects %d | primitives %d\n" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))]
	t += "nodes %d | active 3D physics objects %d | video mem %.0f MB\n" % [
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0]
	t += "[2]zones %s  [3]exterior %s  [4]view %s  [5]occlusion %s  [6]mesh LOD thr %.1f\n" % [
		_onoff(PerfSettings.zones_enabled), _onoff(PerfSettings.exterior_cull_enabled),
		_onoff(PerfSettings.view_activation_enabled), _onoff(root.use_occlusion_culling),
		root.mesh_lod_threshold]
	if zm != null and zm.is_graph_ready:
		var cur := String(zm.current.zone_id) if zm.current != null else "-"
		var counts := [0, 0, 0, 0]
		for z in zm.zones:
			counts[z.state] += 1
		t += "zone %s | outside %s | queue %d | COLD %d VIEW %d WARM %d ACTIVE %d\n" % [
			cur, str(zm.player_outside), zm.queue_length(), counts[0], counts[1], counts[2], counts[3]]
	if ec != null:
		t += "Mars visible: %s\n" % str(ec.shown)
	if _log != null:
		t += "[7] LOGGING\n"
	return t


func _onoff(v: bool) -> String:
	return "ON" if v else "off"


func _toggle_log() -> void:
	if _log != null:
		_log.close()
		_log = null
		return
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	_log = FileAccess.open("user://perf_%s.csv" % stamp, FileAccess.WRITE)
	if _log != null:
		_log_t0 = Time.get_ticks_msec() * 0.001
		_log.store_line("t_s,frame_ms,draw_calls,objects,primitives,zone,outside,mars_visible")
		print("PerfHud logging to ", _log.get_path_absolute())


func _write_log_row(ms: float) -> void:
	var zm := get_tree().get_first_node_in_group(&"zone_manager") as ZoneManager
	var ec := get_tree().get_first_node_in_group(&"exterior_controller") as ExteriorController
	var zone_name := "-"
	var outside := false
	if zm != null and zm.is_graph_ready:
		outside = zm.player_outside
		if zm.current != null:
			zone_name = String(zm.current.zone_id)
	_log.store_line("%.3f,%.3f,%d,%d,%d,%s,%s,%s" % [
		Time.get_ticks_msec() * 0.001 - _log_t0, ms,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		zone_name, str(outside), str(ec.shown) if ec != null else "-"])
```

## 13. Pitfalls checklist (check each one before finishing)

- `visible = false` does **not** stop scripts, physics or animation. `process_mode = DISABLED` does **not** stop rendering. Zones do both.
- Hidden nodes still collide. That is relied on for static geometry; do not "fix" it.
- Toggling `visible` on a node tells every descendant node about the change, so the cost grows with node count. Keep rooms' `Static` roots lean (merge many small meshes where it is free to do so) and never toggle a huge subtree in one frame; the scheduler already splits work but a single root with thousands of children is still one step.
- Occluders are mostly static: never move or animate them; toggling their visibility is acceptable for doors.
- Visibility range distance is measured to the node's origin, not the nearest edge; `MultiMeshInstance3D` mesh LOD uses the closest point of the node's bounding box. Big single nodes behave as "always close".
- Alpha-fade LOD transitions force transparent rendering for the fading objects and can cause sorting artefacts.
- `VisibleOnScreenEnabler3D` does not affect nodes added after scene start and does not do exact visibility.
- If a `Zone` is moved at runtime, call `refresh_bounds()`.
- Render features such as SDFGI, volumetric fog, SSR/SSAO/SSIL, high MSAA and a high 3D resolution scale can dominate GPU time regardless of everything above. Phase 0 step 6 finds out; report, do not silently change them.

## 14. Final deliverables

1. All code under `res://perf/` plus the small edits to existing scenes/scripts, each phase committed on branch `perf-overhaul`.
2. `docs/perf/phase_0.md` ... `phase_6.md`, `scene_inventory.md`, `baseline.md`, `final_report.md` (the before/after tables and acceptance checklist with pass/fail for each of the ten criteria).
3. A short `docs/perf/how_to_tune.md`: which `PerfSettings` values do what, the Ctrl+1..7 debug keys, and how to add a new room (Zone + Bounds + Static/Dynamic + doors + `has_exterior_view`).
4. A list of anything you could not verify or chose not to do, with the reason.

## 15. Reference documentation (read the relevant page before each phase)

- Optimizing 3D performance (frustum culling is automatic; LOD options; MultiMesh; transparency): https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html
- Occlusion culling (setup, baking, doors, limits): https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html
- OccluderInstance3D class: https://docs.godotengine.org/en/stable/classes/class_occluderinstance3d.html
- Visibility ranges (HLOD), Visibility Parent, fade modes, hysteresis margins: https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html
- Mesh level of detail (automatic LOD, `mesh_lod_threshold`): https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html
- VisibleOnScreenEnabler3D: https://docs.godotengine.org/en/stable/classes/class_visibleonscreenenabler3d.html
- Background loading (`ResourceLoader.load_threaded_request`): https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html
- Reducing stutter from shader (pipeline) compilations: https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html
- Lights and shadows (shadow max distance, PSSM splits, distance fade): https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html
- Pausing games and process modes (`PROCESS_MODE_DISABLED`): https://docs.godotengine.org/en/stable/tutorials/scripting/pausing_games.html

# END OF PROMPT
