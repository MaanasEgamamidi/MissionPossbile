# Milestone handoff — Prompt 02: Map import and lighting calibration

Date: 2026-11-11. Workspace: `G:\nasa app`. Executor: Claude (Claude Code session). Owner instruction: page 12 of the pack starts Prompt 02; finish Prompt 02 as well (decision D-04).

## 1. Outcome

Prompt 02 was executed in the form the prompt allows when its main input is missing: **independent preparation, with the missing dependency flagged.** The owner-supplied improved map and its source scene were not available, so the import and the three lighting passes were run on the **current** map as a rehearsal.

What now exists and works:

- A Godot 4.7.2 project inside the workspace, `G:\nasa app\mars_colony_godot\`.
- A reproducible Blender-to-GLB derivative export that never saves the source file.
- The current map imported with exact placement: 1,857 of 1,857 objects, zero position error, matching triangle counts, mesh sharing, door ids and station ids preserved.
- The Blender render rig rebuilt in Godot: 417 fixture lights, the sun, 15 room probes, 184 source cameras.
- A first lighting preset, three calibration passes on 15 matched camera pairs, a score sheet and a list of every remaining mismatch.
- Switchable lighting (per-room power, day and night) with nothing baked, and checks that a powered-off room is dark.

What is **not** achieved:

- **No final-map import and no final-map reference set**, because the improved map is missing. Nothing here is an acceptance of the final map.
- **No view reaches the 95-point target.** Rubric scores are 60 to 77, mean 69.1 (executor's visual review; owner review pending).
- Night, unpowered, suit and rover *reference* views do not exist in the source, so those Godot states were checked for behaviour only, not against a reference.

## 2. Prompt 02 acceptance, item by item

| Acceptance item | Result |
| --- | --- |
| Imported placement and scale agree with the source. | Met for the current map: `evidence\verify_import.json`, `ok = true`. Not applicable to the improved map yet. |
| No missing walkable floors, gross material errors or broken source references remain unreported. | Reported in `import_report.md` section 4. All 387 floor-class objects are present as geometry; nothing was walked (no collision yet). Material limits are listed. No broken references. |
| Every reference view has a pair and a score, or an explicit reason. | 15 of 15 existing reference views have a pair, metrics and a rubric score. The four rooms without a hero camera (Pipe gallery, Service corridor, Blast-door passage, Dome plaza), the garden-dome interior, and the night, unpowered, suit and rover views have no reference to pair with. |
| No physical 95-percent claim is inferred from a subjective score. | None made. Scores are labelled as rubric scores; metrics are reported separately. |

## 3. Changed files

Created — Godot project `G:\nasa app\mars_colony_godot\`:

| Path | Purpose |
| --- | --- |
| `project.godot`, `.gitignore`, `README.md` | Project (Forward+, MSAA 4×), ignore rules, rebuild instructions |
| `assets\colony\colony.glb`, `environment.glb` and their `.import` files | Derivative exports and import settings |
| `data\colony_manifest.json`, `palette.json`, `colliders.json`, `lighting_preset.json` | Source data for the build |
| `data\import_report_*.json`, `build_world_report.json` | Generated reports |
| `materials\colony_surface.gdshader`, `materials\colony\*.tres` (238) | External materials |
| `scenes\world\colony_world.tscn`, `scenes\world\lighting\env_reference_day.tres` | World scene and environment |
| `scripts\world\colony_zones.gd`, `zone_lighting.gd` | Lighting zones and run-time switching |
| `tools\export_from_blender.ps1`, `build.ps1`, `capture.ps1`, `gen_materials.py`, `compare_pairs.py`, `lighting_experiment.py`, `image_stats.py`, `stack_sheets.py` | Pipeline tools |
| `tools\blender\export_colony_glb.py`, `probe_export.py` | Blender side |
| `tools\godot\build_world.gd`, `colony_post_import.gd`, `verify_import.gd`, `capture_views.gd`, `test_zone_lighting.gd`, `inspect_nodes.gd` | Godot side |

Created — records `G:\nasa app\docs\milestones\02_import\`: `HANDOFF.md`, `import_report.md`, `lighting_report.md`, `score_sheet.csv`, `score_sheet.json`, `camera_pairs.json`, `tools\make_score_sheet.py`, `evidence\` (export and build logs, verification, 6 sets of pair captures, pair sheets, metrics, experiments, state checks).

Updated: `docs\requirements_matrix.md`, `decisions.md`, `issues.md`, `source_register.md`, `README.md`, `milestones\01_audit\contradictions.md`.

Not modified: every `.blend` (14 of 14 hashes unchanged), the build scripts, the browser game, both LAN prototypes, the `grand_colony` git state. No file under `grand_colony\` has a modification time from this session.

## 4. Interfaces later milestones use

| Interface | Where | Contract |
| --- | --- | --- |
| World scene | `res://scenes/world/colony_world.tscn` | Children: `Colony` (areas → objects), `Environment`, `WorldEnvironment`, `GC_MarsSun`, `Lights/<zone>/<fixture>`, `ReflectionProbes/Probe_<zone>`, `ReferenceCameras/<camera>`. Regenerated by `build_world.gd`; do not hand-edit. |
| Object identity | Node name and metadata on every colony mesh | `gc_asset`, `area`, `cls`, `dust`; doors add `door_id`, `door_slide`; stations add `inter`. |
| Zones | `ColonyZones` | `zone_at_world(pos)`, `zone_of(area, pos)`, `layer_of(zone)`, `mask_for_aabb(box)`. 15 rooms + `Dome plaza`, `Garden dome`, `Exterior`. |
| Lighting state | `ZoneLighting` | `setup(world)`, `set_zone_powered(zone, bool)`, `is_zone_powered(zone)`, `set_sun_phase(0..1)`, `set_night(bool)`, signal `zone_power_changed`. |
| Groups | Scene groups | `fixture_lights`, `zone_<slug>`, `sun`, `room_probes`. |
| Per-instance shader values | `colony_surface.gdshader` | `dust` (0..1), `power` (0 or 1). |
| Data | `res://data/` | `colony_manifest.json` (schema 1), `palette.json`, `colliders.json`, `lighting_preset.json`. |

No save format, schema, input map or gameplay behaviour was created.

## 5. Checks run, with results

| # | Check | Kind | Result |
| --- | --- | --- | --- |
| 1 | Source hashes before and after each export, and at the end | Automated | Unchanged every time |
| 2 | Game-detail regeneration against the browser export | Automated | 303,340 unique triangles in both; no asset missing or mismatched |
| 3 | Import verification | Automated, headless | `ok = true`: counts, transforms, triangles, sharing, ids, vertex colours, glass, lights, cameras |
| 4 | Lighting state logic, 18 zones and day/night | Automated, headless | Pass |
| 5 | 15 matched pairs × 4 capture sets, image metrics | Automated capture and statistics | Mean SSIM 0.670 → 0.764; mean absolute EV difference 0.689 → 0.111; mean ΔE76 16.74 → 9.12 |
| 6 | Rubric scoring of 15 final pairs | Visual review by the executor | 60 to 77, mean 69.1, none at 95 |
| 7 | Unpowered greenhouse, neighbour room, night | Automated capture and statistics | Greenhouse 0.4% of lit luminance; mess hall unchanged; night exterior 6% |
| 8 | Six preset experiments | Automated | Recorded in `evidence\pairs\experiments\` |

Nothing was walked, driven or played. No human looked at the results other than through this report. The render times in `lighting_report.md` section 8 are capture-time observations, not a performance test.

## 6. Sources used

Checked against the locally generated Godot 4.7.2 class reference (`--doctool`) for exact property names: AreaLight3D, SpotLight3D, Light3D, Environment, ReflectionProbe, SubViewport, EditorScenePostImport. Online references from Prompt 01: T03 (AreaLight3D), T04 (global illumination), T05 (tonemapping), T06 and T07 (import). Two behaviours were established here by measurement, not from documentation: AreaLight3D gave no SDFGI contribution, and SDFGI let sky light into closed rooms (`source_register.md` section 8, entries M01 and M02).

## 7. Evidence images

| Set | Camera and state | Resolution | Where |
| --- | --- | --- | --- |
| Cycles references | `Shot_01` to `Shot_15`; day, powered; historical, 2026-11-08 | 1920 × 1080 | `grand_colony_drive\beauty_shots_cycles_1080p.zip` |
| Godot baseline, pass 1, pass 2, pass 3 | The same 15 cameras; day, powered | 1920 × 1080, MSAA 4× | `evidence\pairs\pass0_baseline`, `pass1`, `pass2`, `pass3` |
| Pair sheets | Reference left, Godot right, with metrics in the label | 1606 × 476 | `evidence\pairs\sheets_<pass>\` |
| States | Greenhouse off (2 cameras); night (3 cameras) | 1920 × 1080 | `evidence\states\` |

## 8. Remaining defects and limits

- All 15 views are below 95; each is listed with cause and remaining work in `lighting_report.md` section 7.
- Materials are the largest gap: flat palette colours, approximate dust, flat screens, alpha-blended glass.
- Indoor bounce is a uniform per-room ambient, not global illumination. Open ceilings above the fixtures read too light.
- No atmosphere: no haze, dust volumes or particles.
- Five of 15 static views took more than 16.7 ms of GPU time at 1080p.
- The environment is 6.95 M triangles and was not reduced.
- Doors were only tested closed; no light-leak check with open doors.
- Issues opened or updated: I-08, I-09, I-10, I-11, I-16, I-18, I-19 and new I-29 to I-35 in `docs\issues.md`.

## 9. Contradictions and decisions

- C-13 (which page is page 12) is resolved by the owner: Prompt 02 was in scope.
- C-03 (Godot project outside the workspace) is worked around: the project is inside the workspace and was driven through the Godot command line; the MCP-connected editor still shows the other project.
- C-01 stands: there was no Godot port to extend, so this project is new (decision E-09).
- Executor decisions E-09 to E-15 are in `docs\decisions.md`.

## 10. Missing inputs — requests to the owner

1. **The improved map with its source Blender scene.** Still the blocker for the real Prompt 02 result.
2. The three governing documents.
3. A decision on materials: keep palette colours plus shader, or bake textures in a derivative (needs UVs).
4. Open `G:\nasa app\mars_colony_godot` in the MCP-connected Godot editor if later milestones should use the editor tools.

## 11. Dependencies for the next milestone (Prompt 03, simulation, configuration and save foundation)

| Dependency | State |
| --- | --- |
| Prompts 01 and 02 contracts | Written. Zone names, station ids and the `ZoneLighting` API are the hooks the simulation needs. |
| "The current port and its tests" | Do not exist (C-01). Prompt 03 starts from this project and from the browser game's behaviour as evidence. |
| Map-dependent tasks | Still blocked on the improved map; Prompt 03 says independent service work may proceed. |
| Sol clock → lighting | `ZoneLighting.set_sun_phase(phase)` is ready to be driven. |
| Power state → lighting | `ZoneLighting.set_zone_powered(zone, bool)` is ready to be driven. |

## 12. Optional suggestions (not requirements, not acted on)

- Commit `mars_colony_godot` and the v12 state of `grand_colony` to version control before further work.
- Merge repeated static meshes (ceiling tiles, floor tiles) into MultiMesh instances per room to cut draw calls.
- Evaluate VoxelGI per room as real local dynamic GI once the final geometry is fixed; it was not tried here.
- Reduce the rock meshes: 996 rocks account for 3.39 M of the environment's triangles.
