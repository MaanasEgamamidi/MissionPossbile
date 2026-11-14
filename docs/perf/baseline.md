# Perf overhaul baseline

**Measured baseline (idle GPU, owner's go-ahead, 2026-11-14 13:19): see `benchmark_2026-11-14.md`, runs 1 and 4.**
Every view runs at 14-35 ms GPU (Greenhouse slowest), i.e. 30-75 FPS at 1080p High. The Prompt 13 table below
(10-16 FPS) was spoiled by a hung game window holding the GPU; it is kept only for its feature-cost ablation.

## Older numbers (Prompt 13, RTX 4060 Ti, 1920x1080, High, uncapped; GPU shared with a hung game instance)

| View | Frame p50 ms | CPU ms mean | GPU ms mean | Draw calls | Primitives | Video MB |
|---|---|---|---|---|---|---|
| room_command_room | 84.4 | 5.8 | 82.1 | 5226 | 10.81 M | 1462 |
| room_power_room | 76.4 | 4.5 | 71.2 | 3345 | 6.20 M | 1462 |
| room_greenhouse | 100.2 | 15.0 | 98.0 | 12591 | 13.85 M | 1455 |
| room_med_bay | 76.3 | 12.8 | 73.2 | 10056 | 11.53 M | 1456 |
| room_life_support | 71.4 | 9.3 | 68.8 | 8185 | 10.08 M | 1458 |
| plaza_through_glass | 80.9 | 11.6 | 77.3 | 9796 | 12.07 M | 1458 |
| exterior_garage | 83.2 | 13.9 | 80.7 | 11009 | 11.92 M | 1458 |
| exterior_storm | 60.2 | 2.7 | 57.5 | 1303 | 4.49 M | 1458 |
| four_suited_crew | 86.0 | 15.7 | 83.5 | 12391 | 12.40 M | 1458 |
| rover_route | 72.4 | 4.2 | 68.7 | 1395 | 5.40 M | 1458 |

## CPU- or GPU-bound

GPU-bound in every view (CPU render time 3-19 ms against 57-98 ms GPU). So rendering work matters most:
Phases 1, 2 (its rendering half) and 5 first, then 4.

## Feature cost (brief step 6, from Prompt 13's single-process ablation; read with care, the GPU share drifted)

| Change from High | Greenhouse GPU ms | Storm exterior GPU ms |
|---|---|---|
| baseline | 111.3 | 198.0 |
| no fixture shadows | 103.6 | 188.3 |
| no area lights (39) | 82.3 | 181.1 |
| **no fixture lights at all (417)** | **61.4** | **143.0** |
| no sun shadow | 106.4 | 168.8 |
| no SSIL | 96.5 | 167.1 |
| no SSR / no SSAO / no glow | within noise | within noise |
| MSAA off | 135.7 (noise) | 79.4 |
| Medium preset | 88.1 | 115.9 |
| High again (drift check) | 349.3 | 172.5 |

Options to report, **not changed** (the brief forbids permanent visual changes here): fixture lights are the largest
consistent item; the greenhouse's 32 unshadowed AreaLight3D are a large share indoors; SSIL is next. MSAA 2x looked
large outdoors in one run only. The Medium preset already fades and trims these.

## Scene size facts found in this work (headless, `tools/perf/probe_*.gd`)

- 3366 GeometryInstance3D in the world; 7741 nodes in a running game.
- Colony exterior shell alone (layer 20 meshes): 782 meshes, **4.43 M triangles**.
- Terrain: 25 chunks, 2.77 M triangles. Rocks: 996 MeshInstance3D sharing **14 meshes**, 3.39 M triangles in total,
  already with hand-authored visibility ranges (140 x size, alpha fade SELF, from `tools/godot/colony_post_import.gd`).
- Fixture lights: 417 (60 shadowed), all limited to their zone's render layer.
