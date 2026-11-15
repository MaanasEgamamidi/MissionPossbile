# Mars Colony — Godot 4.7.2 project

The `revisions` branch implements F01-F06 foundations, C01-C04 cassettes and S01-S04 survival (pages 1-25). Collect six shared room tapes with E, then read their local NASA photos and two-page briefings at the Command Room cassette player. Inventory shows collection status only. See [the survival handoff](docs/revisions/SURVIVAL_HANDOFF.md), [cassette handoff](docs/revisions/CASSETTE_HANDOFF.md) and [foundation handoff](docs/revisions/HANDOFF.md) for APIs, verification and limitations.

Unprotected exposure to unbreathable air causes recovery after four unpaused real seconds. A failed seal or open outer door depressurizes only the exit vestibule; retreat through the inner door or wear a sealed suit with oxygen. Use the safe interior T12 station as the field engineer for 20-second seal maintenance. All twelve repair stations provide role-checked operational maintenance as condition wears continuously. Maintenance preserves puzzle achievements; the twelve actual puzzles, restoration art and completion shots remain future T-section work. The performance update from `main` is merged. No human playtest has been run for these changes.

Open `project.godot` with Godot 4.7.2. The main scene is `scenes/game.tscn` (the map alone is `scenes/world/colony_world.tscn`).

## Play

Run the project. It continues the last save or starts a new colony. Click the window to take the mouse.

| Key | Does |
|---|---|
| W A S D, mouse | Move and look |
| Shift / Space | Sprint / jump (Mars gravity, 3.73 m/s²) |
| E | Use what you look at: the suit rack in the Airlock runs the one-second suit check; the power panel in the Power Room opens the room switches |
| G or left mouse | Pick up, drop (hold Shift to throw) one of the three crates near the start |
| Tab | First person / third person |
| Esc | Close a panel, otherwise pause |
| 1 to 4 | Interim: take that crew member (only at the hub) |

Doors open when you walk up to them. The top-left text shows the sol clock, the colony stores and your crew member.

## Automated checks

```powershell
& .\tools\run_tests.ps1 -Import
```

The runner includes the existing gameplay suites and repair, cassette and survival checks. Current results and visual evidence are recorded in [the survival verification](docs/revisions/SURVIVAL_VERIFICATION.md). Historical Prompt 03/04 records remain in `docs/milestones/03_simulation/HANDOFF.md` and `docs/milestones/04_player/HANDOFF.md`.

## Collision data

`scripts/world/world_collision.gd` builds collision at start-up from `data/colony_manifest.json` and `data/colliders.json`. The outdoor ground is a sampled height grid; rebuild it after a terrain change:

```powershell
godot --headless --path . --script res://tools/godot/build_heightmap.gd -- --scene res://assets/colony/terrain.glb --cell 1.0 --out res://data/terrain_height.res
godot --headless --path . --script res://tools/godot/heightmap_level_rooms.gd
```

## Code layout (gameplay)

| Folder | Holds |
|---|---|
| `config/` | `game_config.tres` (engineering settings), `game_balance.tres` (designer tuning) |
| `scripts/core/` | settings, events, requests and results, layers, `GameServices` |
| `scripts/state/` | `ColonyState`, `CharacterState` |
| `scripts/sim/` | `SolClock`, `ColonySim` |
| `scripts/session/` | `SessionService`, `ActionService`, built-in actions, legacy station facade |
| `scripts/survival/` | Host exposure, localized exit pressure and continuous operational wear |
| `scripts/save/` | `SaveService`, migrations |
| `scripts/world/` | zones, lighting, stations, collision, doors, terrain height |
| `scripts/player/` | controller, camera rig, input map, tuning, body, carried props |
| `scripts/game/` | `GameMain` (scene root), `GameHud` |
| `tests/` | headless test suites |


## Rebuild from the Blender source

```powershell
& "G:\nasa app\mars_colony_godot\tools\export_from_blender.ps1"
```

```powershell
& "G:\nasa app\mars_colony_godot\tools\build.ps1"
```

The first command opens the source `.blend` in a background Blender, never saves it, and writes `assets/colony/*.glb` and `data/*.json`. The second regenerates the materials, imports the GLBs and assembles the world scene. If only `data/lighting_preset.json` changed, run the second command with `-SkipImport`. If `tools/godot/colony_post_import.gd` or `scripts/world/colony_zones.gd` changed, delete `.godot/imported/*.glb-*` first so the GLBs are re-imported.

## Layout

| Path | What it is |
| --- | --- |
| `assets/colony/colony.glb` | 1,857 placed objects at the game detail level (553,542 triangles, 593 shared meshes), flat-shaded, grouped by area. Custom properties `gc_asset`, `area`, `cls`, `dust`, `door_id`, `door_slide`, `inter` travel as glTF extras and become node metadata. |
| `assets/colony/environment.glb` | Terrain (25 tiles with vertex colour, plus the outer plain), 996 rocks sharing 14 meshes, glass hall, airlock tunnel, decals, drifts. |
| `data/colony_manifest.json` | Source of truth for the Godot build: every object's Blender matrix, all 471 lights (with a flag for the 418 used by the Blender render), 184 cameras, 30 probes, room rectangles with ceiling height and mean albedo. |
| `data/palette.json` | Palette roles from the Blender scripts: colour, emission, roughness, metallic, opacity, material class, dust factor. |
| `data/colliders.json` | Collision boxes of the browser export, for Prompt 04. Not used yet. |
| `data/lighting_preset.json` | Every lighting constant, with the notes of the three calibration passes. |
| `materials/colony/*.tres` | Generated: one material per palette role. Do not edit by hand; edit the preset or the palette and run `tools/gen_materials.py`. |
| `materials/colony_surface.gdshader` | Opaque surface shader: palette colour plus the Mars dust layer, with per-instance `dust` and `power`. |
| `scripts/world/colony_zones.gd` | Lighting zones (15 rooms, dome plaza, garden dome, exterior) and the render-layer mask of each mesh. |
| `scripts/world/zone_lighting.gd` | Run-time switch: per-zone fixture power, day and night. Nothing is baked. |
| `tools/godot/build_world.gd` | Assembles the world scene from the data files. |
| `tools/godot/verify_import.gd` | Compares the imported world with the manifest. |
| `tools/godot/test_zone_lighting.gd` | Logic test of power and day/night switching. |
| `tools/godot/capture_views.gd`, `tools/capture.ps1` | Renders reference-camera views to PNG with no UI. |
| `tools/compare_pairs.py`, `tools/lighting_experiment.py` | Image metrics against the Cycles references; preset variants. |

## Checks

```powershell
& "C:\Users\josev\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "G:\nasa app\mars_colony_godot" --script res://tools/godot/verify_import.gd
```

```powershell
& "C:\Users\josev\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "G:\nasa app\mars_colony_godot" --script res://tools/godot/test_zone_lighting.gd
```

```powershell
& "G:\nasa app\mars_colony_godot\tools\capture.ps1" -Out "G:\nasa app\mars_colony_godot\docs\milestones\02_import\evidence\pairs\pass3" -Cams beauty
```

Records: `G:\nasa app\mars_colony_godot\docs\milestones\02_import\`.
