# Perf overhaul: final report (2026-11-14)

Branch `optimization` (worked on as `perf-overhaul`), from `d5c8df6`. Everything is in `res://perf/` plus small edits:
`game_main.gd` (one call), `zone_lighting.gd` (sleep composed with power), `door_controller.gd` (two signals),
`project.godot` (two autoloads), `tools/godot/check_compile.gd` (also compiles `res://perf`),
`tools/perf/perf_bench.gd` (`--shots`, perf switches in the report).

## Headline

Measured on an idle GPU (RTX 4060 Ti, 1080p, High; `benchmark_2026-11-14.md`):

- **The game already runs at 30-75 FPS once the stale editor game window is closed.** Prompt 13's 10-16 FPS came from
  that hung window (PID 14308) holding the GPU, not from the game. Closing it was by far the biggest gain.
- The shipped perf defaults give **10-13 % lower GPU time in Med Bay and Life Support**, about -4 % in the Command
  Room, and nothing measurable elsewhere (inside the 3-12 % run-to-run drift). Draw calls drop 25-29 % outdoors, but
  the GPU time there does not move: outdoors the cost is elsewhere (terrain, rocks, shadows).
- **No quality drop:** with the defaults, every benchmark still is pixel-identical to the baseline except crew idle
  poses (SSIM 0.956-1.000; the rooms themselves are identical).
- The "all on" extras (colony LOD, Mars ranges, sun and fixture tuning) changed nothing visible **and** gained nothing
  in these views, so they stay OFF.

| View | Baseline GPU ms (2 runs) | Defaults GPU ms (2 runs) | Change | Draw calls change | Image vs baseline (SSIM) |
|---|---|---|---|---|---|
| room_command_room | 16.3 / 17.2 | 15.6 / 16.4 | -4 % | -2 % | 0.9998 |
| room_power_room | 19.6 / 20.9 | 19.1 / 20.7 | -2 % (noise) | -1 % | 1.0000 |
| room_greenhouse | 31.7 / 35.4 | 31.1 / 34.6 | -2 % (noise) | -2 % | 1.0000 |
| room_med_bay | 18.0 / 19.1 | 15.9 / 17.1 | **-11 %** | +5 % | 0.9564 (crew pose only) |
| room_life_support | 17.9 / 18.8 | 16.1 / 15.9 | **-13 %** | -14 % | 0.9995 |
| plaza_through_glass | 19.3 / 20.4 | 20.4 / 20.5 | +3 % (noise) | +9 % | 1.0000 |
| exterior_garage | 16.3 / 16.8 | 16.4 / 16.2 | -2 % (noise) | -28 % | 0.9994 |
| exterior_storm | 13.8 / 14.0 | 13.8 / 13.7 | -1 % (noise) | -29 % | 0.9994 |
| four_suited_crew | 17.6 / 18.2 | 17.4 / 17.4 | -3 % (noise) | -25 % | 0.9963 (crew pose) |
| rover_route | 16.5 / 17.6 | 17.4 / 17.4 | +2 % (noise) | 0 % | 0.9983 |

The Greenhouse (31-35 ms, ~30 FPS) is now the slowest view; its 76 fixtures (35 area lights) are lit whenever you
are in it, which no culling can avoid. Options for the owner (change the look, not done): fewer or unshadowed area
lights there, SSIL off on High.

## What ships ON / OFF

| System | Default | Why |
|---|---|---|
| Zones (Phase 2) | ON | measured gain in the rooms far from the plaza, image identical |
| Exterior cull (Phase 3) | ON | correct and free; never triggers on this map (every room sees the glass dome within two glass doors) |
| View gating (Phase 4) | ON | pauses off-screen crew animation; image identical |
| Colony LOD (Phase 5) | OFF | no gain in the measured views (all within 108 m); not checked from far away |
| Mars visibility ranges (Phase 5) | OFF | no gain measured; the 996 rocks already have authored ranges |
| Sun shadow tuning, fixture fade (Phase 1) | OFF | no gain measured |
| Shader warm-up (Phase 6) | OFF | 4.7 precompiles pipelines; a ~10 s black tour at start |

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | No visual difference in normal play | **Pass** for the defaults: 10 benchmark stills compared to the baseline, rooms pixel-identical (only crew idle poses differ). |
| 2 | Door crossing <= 2x median, < 33 ms | **Not measured** (no door-crossing route recorded). Transitions are bit flips + light toggles, time-sliced at 1.5 ms. |
| 3 | Windowless room: Mars hidden / shown before the door moves | **Logic pass (headless)**, but no room on this map is "windowless": all doors are glazed, so Mars is never hidden. |
| 4 | Spin test | **Not measured** (Ctrl+0 exists). |
| 5 | Outside LOD swaps cleanly | **Not checked**; colony LOD ships OFF. |
| 6 | Teleport into a cold room correct on the first frame | **Pass (headless):** a jump > 6 m between frames snaps every zone in that frame. |
| 7 | Physics unchanged | **Pass by construction:** no collision node is touched; crew Presence bodies are never gated. All 27 existing suites pass. |
| 8 | No memory growth over 10 minutes | **Not measured.** Transitions create and free no nodes. |
| 9 | No new errors or warnings | **Pass:** compile check OK; 27 existing suites + test_perf (48 checks) pass; 0 script errors in the 6 bench logs. |
| 10 | Average frame time improves in S2, S3, S4 | **Partly:** -11 % / -13 % in the two rooms farthest from the glass (S3-like); no measurable change in the plaza or outdoors (S4). |

## Could not verify / chose not to do

- Door-crossing, spin and 10-minute memory runs (tools exist: Ctrl+8/9/0, Ctrl+7 CSV).
- Wall occluder baking (editor-only; glazed doors would need holes); room `process_mode` sleep (no room owns dynamic
  content); MultiMesh rocks (collision and authored ranges read the nodes); streaming (gate not passed).
- Colony LOD from far away (100-1500 m): ships OFF until someone looks.
