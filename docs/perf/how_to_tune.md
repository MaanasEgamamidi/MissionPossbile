# Perf overhaul: how to tune

All values live in `perf/perf_settings.gd` (autoload `PerfSettings`); code reads them through `Perf.cfg()`. Change
one live with the HUD keys, at launch with `-- --perf-set=name:value`, or in the file.

## Debug keys (debug builds; PerfHud)

| Key | Action |
|---|---|
| Ctrl+1 | HUD: FPS, avg / p99 / worst ms, draw calls, objects, primitives, nodes, video MB, switch states, zone states, Mars |
| Ctrl+2 / 3 / 4 | zones / exterior cull / view gating on-off |
| Ctrl+5 | occlusion culling on-off |
| Ctrl+6 | mesh LOD threshold 2 -> 3 -> 4 -> 1 -> 2 |
| Ctrl+7 | CSV log to `user://perf_*.csv` |
| Ctrl+8 / 9 / 0 | benchmark route: record waypoint / play / spin test |
| Ctrl+Shift+1 / 2 / 3 / 4 | colony LOD / Mars ranges / sun shadow tuning / fixture fade |
| Ctrl+Shift+0 | every switch off (baseline) / on |

Launch: `-- --perf-off` (baseline), `-- --perf-on` (all on). A/B bench: `sh tools/perf/run_perf_ab.sh`.

## Settings

| Setting | Default | Raise it when | Lower it when |
|---|---|---|---|
| `warm_hops` | 1 | rooms pop in next to you | (never below 1) |
| `glass_view_hops` | 2 | a room vanishes seen through several glass panels | measured safe and you want more culling |
| `prewarm_distance` | 4 m | a room appears late after a door | wake-ups too early / often |
| `cold_delay` | 2 s | rooms flicker when walking back and forth | - |
| `step_budget_usec` | 1500 | the HUD queue stays long after a door | frames spike during transitions |
| `snap_distance` | 6 m | false snaps (never seen) | teleports are short and not snapped |
| `exterior_hide_delay` | 1.5 s | Mars flickers near windows | Mars is hidden too late |
| `exterior_check_hops` | 2 | Mars visible through long glass chains | (1 = more culling, pop risk) |
| `exterior_door_prewarm` | 4 m | Mars appears late near an airlock | - |
| `outside_interior_distance` | 25 m | windows show dark rooms from outside | outside cost is high |
| `outside_dome_distance` | 400 m | the plaza vanishes from far away | - |
| `entrance_prewarm_distance` | 15 m | the airlock looks dark when you arrive | - |
| `range_per_metre` / `range_min` | 150 / 30 m | scenery pops | GPU heavy outdoors |
| `colony_tier1_begin` / `colony_tier2_begin` | 0 = R+40 / R+200 (108 / 268 m) | pop is visible | GPU heavy at medium distance |
| ViewActivator `near_radius` / `cone_margin_deg` | 12 m / 20 | crew wake late | - |
| `sun_shadow_max_distance` | 150 m | shadows cut off visibly | GPU bound |

## Adding a room

Rooms come from the map: add the room rectangle to the manifest (`data/colony_manifest.json` `rooms`, built by the
map export), give it a zone in `ColonyZones` (it gets the next render layer; layers 1..18 are zones, 19 first-person
hidden, 20 sun) and put its fixtures under `world/Lights/<zone>` with `metadata/zone`. ZoneManager then builds the Zone
(bounds = the rectangle, floor to ceiling, +0.15 m), finds its doors from the DoorControllers (zones sampled 1.2 m either
side), marks glazed door leaves transparent, adds window links for glazed meshes touching two zones, and sets
`has_exterior_view` for zones with a glass link to the plaza or a door to Mars. Nothing is placed by hand.
Note: all 20 render layers are in use; a 19th zone needs a layer plan first.

## Runtime props and moving features (2026-11-15)

`PerfSettings.room_props_enabled` (default ON) ties static props added at run time on layer 1 to the room they stand
in. When you add a feature whose nodes move through the colony (a vehicle, a carried object, an NPC), add its GameMain
field to `ZoneManager.MOVERS` (`[field, sub-field or ""]`) so it is never tied to one room.
