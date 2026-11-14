# Perf overhaul, Phase 5: distance LOD

Status: **implemented, OFF by default (changes pixels; no visual check possible headless).**

## 5.1 Proxies (no Blender needed)

`tools/perf/build_colony_lod.gd` (headless): merges every colony mesh on layer 20 (the exterior shell: roofs, outer
walls, outdoor objects; 782 meshes, 4,433,475 triangles; 11 glass surfaces left out) around the colony centre, writes
each surface's `albedo` as a vertex colour, and simplifies with Godot's meshoptimizer LOD generator:

| Tier | File | Triangles | Material | Shadows |
|---|---|---|---|---|
| T0 | the existing 2147 colony meshes | 4.43 M (shell) | authored | authored |
| T1 | `res://lod/colony_t1.res` (10.9 MB) | 1,108,182 (25.0 %) | one StandardMaterial3D, vertex colour, no maps | on |
| T2 | `res://lod/colony_t2.res` (2.4 MB) | 234,070 (5.3 %) | vertex colour, per-vertex shading | off |

Centre (8.6, -1.3, 22.0), radius 68.4 m (the box includes the garden dome and outdoor pads), from
`res://lod/colony_lod.json`. Re-run the tool after any map rebuild.

## 5.2 ColonyLod

`perf/colony_lod.gd`: the brief's HLOD wiring (T0 -> visibility parent T1 -> T2), tier1_begin = radius + 40 =
108 m, tier2_begin = radius + 200 = 268 m, 8 m margin, hard swap. Proxies sit on layer 20 only, so the zone system
never hides them. Switching off clears every visibility parent and hides the proxies (test_perf checks it).
The colony shell box is ~106 m across, under the brief's 150 m "one HLOD group per wing" threshold, so one group.

Not verified: silhouettes at distance, colour match of the vertex-colour proxies against the authored shader, and the
triangle drop at S4 distances. Turn on with Ctrl+Shift+1 and compare at 100 / 300 / 800 m before making it default.

## 5.3 Mars

- Terrain: 25 chunks of a 2.77 M-triangle surface with import LODs: already chunked; no terrain change proposed.
- Rocks: all 996 already have hand-authored ranges (`tools/godot/colony_post_import.gd`: 140 x size, at least 90 m,
  alpha fade SELF). Left alone, as the brief requires.
- `perf/visibility_ranges.gd`: the brief's 150 x size rule for the remaining 39 unranged scenery meshes of
  `Environment` (scorch marks, tracks, drifts...; landmarks over 40 m keep no end), switch
  `visibility_ranges_enabled` (OFF), Ctrl+Shift+2. `tools/perf/apply_visibility_ranges.gd` is the editor dry-run of
  the same plan (the scenery lives inside environment.glb, so nothing is written to a scene file).
- Mesh LOD presets low 4 / medium 3 / high = project 2.0 (`PerfSettings.apply_quality`). Not hooked to the graphics
  menu: the project already ships 2.0, and High must stay authored.
