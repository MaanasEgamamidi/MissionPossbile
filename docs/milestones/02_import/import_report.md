# Prompt 02 — Import report

Date: 2026-11-11. Godot `4.7.2.stable.official.ed1daf0bf`. Blender `5.3.0`. GPU: NVIDIA GeForce RTX 4060 Ti.

**Scope warning.** The owner-supplied improved map and its source scene were not available. This report covers the **current** map (`grand_colony\grand_colony.blend`, SHA-256 `6AAD006F…5C916B`), imported as a rehearsal of the pipeline. The pipeline is reproducible and is meant to be re-run unchanged on the improved map. Nothing here is an acceptance of the final map.

## 1. Workflow

| Step | Tool | Input | Output | Time |
| --- | --- | --- | --- | --- |
| Derivative export | `mars_colony_godot\tools\export_from_blender.ps1` → `tools\blender\export_colony_glb.py`, background Blender with `--factory-startup --disable-autoexec` | Source `.blend`, build scripts in `grand_colony\scripts` | `assets\colony\colony.glb` (17.7 MB), `environment.glb` (90.1 MB), `data\colony_manifest.json`, `palette.json`, `colliders.json`, `evidence\export\export_report.json` | about 60 s |
| Materials | `tools\gen_materials.py` | `palette.json`, `lighting_preset.json` | 238 files in `materials\colony\` | under 1 s |
| Import | `godot --headless --import` with `tools\godot\colony_post_import.gd` set as the import script | The two GLBs | `.godot\imported\*.scn`, `data\import_report_*.json` | about 25 s |
| World assembly | `tools\godot\build_world.gd` | Manifest, preset, imported scenes | `scenes\world\colony_world.tscn`, `scenes\world\lighting\env_reference_day.tres` | about 1 s |
| Verification | `tools\godot\verify_import.gd` | World scene, manifest | `evidence\verify_import.json` | about 5 s |

The source `.blend` is opened read-only and is never saved. Its SHA-256 was the same before and after every export run, and all 14 `.blend` files in the workspace match their Prompt 01 hashes.

What the exporter does in memory:

1. Registers the colony's asset functions (`gc_build._reload()`) and regenerates each of the 593 assets at the `game` detail level. Result: 303,340 unique triangles, exactly the count in the browser export `colony.json`.
2. Points each of the 1,857 placed objects at its game mesh. Objects that share an asset keep sharing one mesh.
3. Sets the game meshes to flat shading, as the browser export draws them.
4. Replaces the procedural Blender materials with flat materials named after their palette role.
5. Turns the geometry-nodes rock scatter into 996 ordinary objects that share the 14 rock meshes.
6. Exports with Y up, no modifiers applied, custom properties as extras, collections as parent nodes, no cameras, no lights.

## 2. Import settings

Both GLBs use the same `.import` parameters: root scale 1.0, `meshes/generate_lods=true`, `meshes/create_shadow_meshes=true`, `meshes/ensure_tangents=true`, `meshes/light_baking=0` (no lightmap UVs, no baking), `animation/import=false`, `import_script/path="res://tools/godot/colony_post_import.gd"`. The post-import script swaps each embedded material for the external one of the same name, assigns render layers per lighting zone, copies glTF extras to node metadata and sets the per-instance dust value. It changes no transform, name or mesh.

Project settings: Forward+, MSAA 3D 4×, 4096 directional and positional shadow maps, clustered element limit 1024.

## 3. Source against import

From `evidence\verify_import.json` (last run after all changes; result `ok = true`):

| Check | Source | Godot | Result |
| --- | ---: | ---: | --- |
| Colony objects | 1,857 | 1,857 mesh nodes, all matched by name | Pass |
| Largest position error | — | 0.000000 m | Pass |
| Largest basis (rotation and scale) error | — | 0.000001 | Pass |
| Triangles, colony | 553,542 | 553,542 | Pass |
| Shared meshes | 593 assets | 593 mesh resources | Pass: sharing preserved |
| `gc_asset` metadata mismatches | — | 0 | Pass |
| Area (parent node) mismatches | — | 0 | Pass |
| Doors | 24 doors, 52 leaves | 24 ids, 52 leaves with `door_id` and `door_slide` | Pass |
| Stations | 9 | `board`, `comms`, `computer`, `food`, `heal`, `lifesupport`, `power`, `suits`, `survivor` | Pass |
| Floor-class objects | 387 | 387 | Pass |
| Environment objects | 1,060 | 1,060 matched, largest position error 0.000001 m | Pass |
| Triangles, environment | 6,952,830 | 6,952,830 | Pass |
| Terrain tiles with vertex colour | 25 | 25 | Pass |
| White or uncoloured terrain | — | none | Pass |
| Materials not external | — | 0 of 238 | Pass |
| Glass roles transparent | 8 | 8 (alpha 0.16 to 0.55) | Pass |
| Lights used by the Blender render | 418 | 417 fixtures + 1 sun | Pass |
| Source cameras | 184 | 184 Camera3D, largest position error 0 m | Pass |

Objects per area match the source collection counts: Hangar 131, Crew Corridor 63, Mess Hall 130, Rec Kitchen 72, Med Bay 92, Command Room 84, Blast-door Passage 7, West Bunk Room 52, East Quarters 80, Service Corridor 29, Greenhouse 184, Airlock 69, Power Room 120, Life Support 58, Pipe gallery 19, Dome plaza 42, Exterior 63, Garden Dome 52, Roofs 510.

Axis convention: Blender (x, y, z) → Godot (x, z, −y). Mesh objects: T = C·M·C⁻¹. Cameras and lights keep their own local axes: T = C·M. Metre scale is unchanged.

## 4. What was not carried, and why

Nothing below was dropped silently; each item is in `export_report.json`.

| Source feature | Count | What happened | Consequence |
| --- | ---: | --- | --- |
| Render detail level | 12.9 M triangles | Replaced by the game detail level the build scripts generate | Silhouettes are simpler than in the Cycles references (plants, rover wheels, suit, dome struts). |
| Procedural materials | 230 on colony meshes, 29 on environment meshes | Replaced by flat palette materials | Wear, grime, bump, variation and screen content are absent. Dust is approximated (section 5). |
| Per-object `dust` | 1,857 objects | Carried as metadata and as a per-instance shader value | Approximated, not baked. |
| Explicit render colours | 19 roles | Used instead of the palette colour | — |
| Terrain colour attributes `gc_ma`, `gc_mb`, `gc_trk` | 25 tiles × 3 | Not exported; only `gc_alb` goes out as COLOR_0 | Strata, ejecta, dune and tyre-track detail of the Blender terrain material is absent. |
| Terrain outer plain | 1 object | Has no colour attribute in the source; given the flat mean of the tiles' `gc_alb` | Stand-in colour. |
| Rock material `GC_terrain_basalt` | 14 meshes | Flat stand-in (0.115, 0.095, 0.08 linear), inside the albedo range stated in `gc_terrain.rock_material` | Stand-in colour. |
| Decal materials `SFX_decal_*` | 7 objects | Flat translucent dark stand-in | Soft procedural edges absent. |
| Volumes and motes | 10 objects | Skipped: glTF has no volumes | No dust devils, dust sheets, ground dust or atmosphere volume. |
| Render-only gravel scatter | modifier on 25 tiles | The `GC_gravel` modifier adds no triangles (checked per tile); nothing to export | Fine gravel visible in the Cycles exteriors is absent. |
| Area lights | 431 | glTF cannot carry them; rebuilt from the manifest (lighting report) | — |
| Browser-game fill lights (`Lights` collection) | 53 | Not built: that collection is excluded from the Blender view layer, so the Cycles references never used it | Recorded in the manifest with `in_blender_render: false`. |
| EEVEE light probes | 30 | Not transferable; 15 Godot reflection probes were placed from the room rectangles | — |
| Compositor | 1 node group | Not transferable; approximated with glow and a saturation adjustment | Dispersion and vignette absent. |
| Transmissive roles without a palette opacity (`glass`, `sf_hall_glass`, `en_water`, `gd_water`) | 4 | Given derivative opacities | Tunable in the preset. |

## 5. External materials

`materials\colony\<role>.tres`, generated, one per role: 228 `ShaderMaterial` using `materials\colony_surface.gdshader`, 10 alpha-blended `StandardMaterial3D` for see-through roles. 23 roles emit light.

The shader reproduces the dust mask of `gc_mat._surface`: upward-facing faces, two world-space noises, scaled by the object's `dust` value and the role's dust factor, mixing toward the source dust colour (0.36, 0.165, 0.075 linear) and roughness 0.93. `dust` and `power` are per-instance, so one material serves all rooms and a switched-off fixture stops glowing without a material copy.

Known limits of these materials: no cavity dust, wear, grime or bump (the game meshes carry no occlusion data); screens and boards are one flat colour; at low dust values the pattern is rustier and patchier than the reference.

## 6. Gameplay anchors preserved

Object names, `gc_asset`, area, collision class (`floor`, `static`, `dynamic`, `door`, `ladder`, `deco`), door ids and slide distances, and the nine station ids are all on the imported nodes. Room rectangles, dome, airlock, landing pads and roof rectangles are in the manifest. Collision boxes are in `data\colliders.json`; no physics bodies were created, because movement and collision belong to Prompt 04.

## 7. Open import issues

| Issue | Detail |
| --- | --- |
| Improved map missing | All of the above must be re-run on it. The exporter assumes the same build scripts; a map authored another way needs a different step 1. |
| Environment weight | 6.95 M triangles, of which 3.39 M are rocks at render detail. Not reduced. |
| No collision | By design at this milestone. "No missing walkable floors" was checked as geometry only (387 floor-class objects present); nothing was walked. |
| Hard-coded paths | The exporter reads `G:\nasa app\grand_colony\scripts` and `game\colony.json`. |
| Godot MCP | The MCP-connected editor still has a project outside the workspace open. This project was built and run through the Godot command line only. |
