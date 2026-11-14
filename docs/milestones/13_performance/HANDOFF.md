# Prompt 13 handoff: performance and final visual integration (worker P13, 2026-11-14)

Status: **measurement done, no game optimization made, targets not met, results are contaminated by a busy GPU.**
Work copy: `G:\nasa app\_work\p13` (no git). All raw JSON and logs: `G:\nasa app\_work\p13\perf\`.

## 1. Test conditions

| Item | Value |
|---|---|
| Machine | Owner's desktop, **not the owner's laptop**: NVIDIA GeForce RTX 4060 Ti 8 GB, driver 32.0.16.1088 (nvidia-smi 610.88), Intel Core i7-12700KF (20 threads) |
| Engine / renderer | Godot 4.7.2-stable (official), Forward+, Vulkan 1.4.341 |
| Build | Editor/debug run from source (`OS.is_debug_build() = true`), `--script res://tools/perf/perf_bench.gd`, no exported build |
| Resolution | 1920x1080 window (render size checked per view in the JSON). One earlier run at 2560x1369 by mistake, kept separately (see 3.4) |
| Frame cap | uncapped = vsync off, `max_fps 0`; capped = vsync on + `max_fps 60` |
| Session | Solo, fresh colony in a temp save folder, no weather refresh. `--host` run not done (time) |
| **GPU contention** | **The Godot editor was open on `G:\nasa app\mars_colony_godot` (PID 39360) and had a game instance of that project running since 2026-11-13 20:25 (PID 14308, `Mars Colony (DEBUG)`, `res://scenes/game.tscn`, shown as Not Responding). Blender 5.3 was open too, and other P-workers ran headless Godot jobs on the CPU. nvidia-smi before each run: GPU utilisation 98-100 % and 6.2-6.5 GB of 8 GB VRAM used before our process started.** I did not stop other people's processes |

Consequence: the GPU times below are the game's cost **plus an unknown, changing share of another game instance on the
same GPU**. The same view measured twice in one process a minute apart went from 111 ms to 349 ms GPU (ablation,
`high` vs `high_again`). Absolute FPS here understates the game on an idle GPU by an unknown factor; the earlier E-33
rough figures (31-42 ms High at 1600x900, also with other Godot windows open) were already much better than today's.
**None of these numbers can confirm or deny 60 FPS on an idle machine; they must be re-run with the editor's game
instance closed.**

## 2. Harness fixes (tools only, no game code)

- `tools/perf/perf_bench.gd`: project.godot starts the window maximized (`window/size/mode=2`), so the first run
  rendered at 2560x1369. Added `_force_window()` (leave maximized, 1920x1080, centred), called at start and again after
  boot; each view record now carries `render_size` and `window_size`. The rover view's `await` inside `_enter_view`
  worked as is (boarding OK: `ROVER boarding: true`), no change needed.
- New `tools/perf/perf_switch_memory.gd` (extends perf_bench): perf_bench switches Medium/High N times inside one frame
  and reads memory straight away, before the renderer has freed the replaced buffers (frees wait for the frames in
  flight). This version renders `--settle` frames (30) after each switch before reading memory.
- New `tools/perf/perf_ablation.gd` (extends perf_bench): static camera in a view, High baseline, then one feature off
  at a time, then Medium, then High again (drift check). Diagnostic only; restores everything.
- New `perf/summarise.py`, `perf/run_all.sh`, `perf/run_diag.sh` (table printer and run scripts).

## 3. Results at 1920x1080

Frame time = wall time between `_process` calls. CPU ms = main viewport render CPU time + frame setup. GPU ms = main
viewport GPU time. Draw calls / primitives = whole frame. Video MB = `RENDER_VIDEO_MEM_USED`. Private / WS = Windows
private bytes / working set of the game process, read after the view. 60 FPS? = "yes" only if frame p95 <= 16.7 ms.
About 40-80 frames per view (5 s at low FPS), so p99 is close to the max.

### 3.1 High, uncapped (`perf/high_uncapped.json`)

| View | Frames | Mean FPS | Frame p50 / p95 / p99 ms | CPU ms mean / p95 | GPU ms mean / p95 | Draw calls | Primitives | Video MB | Private / WS MB | 60 FPS? |
|---|---|---|---|---|---|---|---|---|---|---|
| room_command_room | 56 | 11.2 | 84.4 / 122.5 / 140.8 | 5.8 / 14.0 | 82.1 / 102.2 | 5226 | 10.81 M | 1462 | 3336 / 2298 | no |
| room_power_room | 67 | 13.2 | 76.4 / 85.2 / 98.5 | 4.5 / 5.9 | 71.2 / 80.0 | 3345 | 6.20 M | 1462 | 3336 / 2300 | no |
| room_greenhouse | 50 | 9.9 | 100.2 / 115.8 / 121.3 | 15.0 / 19.5 | 98.0 / 113.1 | 12591 | 13.85 M | 1455 | 3330 / 2291 | no |
| room_med_bay | 66 | 13.1 | 76.3 / 88.1 / 90.4 | 12.8 / 21.6 | 73.2 / 84.3 | 10056 | 11.53 M | 1456 | 3327 / 2286 | no |
| room_life_support | 70 | 13.8 | 71.4 / 82.5 / 87.6 | 9.3 / 18.6 | 68.8 / 78.9 | 8185 | 10.08 M | 1458 | 3382 / 2341 | no |
| plaza_through_glass | 63 | 12.4 | 80.9 / 88.9 / 94.6 | 11.6 / 14.9 | 77.3 / 85.4 | 9796 | 12.07 M | 1458 | 3377 / 2337 | no |
| exterior_garage | 60 | 11.9 | 83.2 / 96.1 / 101.8 | 13.9 / 22.3 | 80.7 / 92.7 | 11009 | 11.92 M | 1458 | 3360 / 2319 | no |
| exterior_storm (tau 0.5-2.5-0.5) | 83 | 16.4 | 60.2 / 68.9 / 76.2 | 2.7 / 3.5 | 57.5 / 63.7 | 1303 | 4.49 M | 1458 | 3369 / 2282 | no |
| four_suited_crew | 58 | 11.6 | 86.0 / 107.9 / 116.1 | 15.7 / 29.1 | 83.5 / 102.0 | 12391 | 12.40 M | 1458 | 3364 / 2277 | no |
| rover_route (driven) | 68 | 13.6 | 72.4 / 92.4 / 99.5 | 4.2 / 5.0 | 68.7 / 74.5 | 1395 | 5.40 M | 1458 | 3376 / 2288 | no |

### 3.2 Medium, uncapped (`perf/medium_uncapped.json`)

| View | Frames | Mean FPS | Frame p50 / p95 / p99 ms | CPU ms mean / p95 | GPU ms mean / p95 | Draw calls | Primitives | Video MB | Private / WS MB | 60 FPS? |
|---|---|---|---|---|---|---|---|---|---|---|
| room_command_room | 40 | 7.2 | 130.9 / 226.1 / 250.7 | 6.5 / 19.7 | 132.1 / 219.9 | 5385 | 10.59 M | 1251 | 3705 / 2538 | no |
| room_power_room | 39 | 6.4 | 158.9 / 192.0 / 214.4 | 5.0 / 7.1 | 147.8 / 174.9 | 3431 | 6.37 M | 1256 | 3636 / 2474 | no |
| room_greenhouse | 38 | 4.6 | 217.4 / 304.9 / 307.7 | 15.3 / 23.0 | 214.2 / 300.4 | 11598 | 13.22 M | 1249 | 3645 / 2481 | no |
| room_med_bay | 38 | 5.1 | 198.3 / 262.0 / 268.6 | 12.6 / 19.7 | 192.5 / 255.1 | 8266 | 9.53 M | 1250 | 3629 / 2466 | no |
| room_life_support | 38 | 6.0 | 163.1 / 220.8 / 227.2 | 10.2 / 18.5 | 163.5 / 218.2 | 7392 | 9.95 M | 1252 | 3633 / 2470 | no |
| plaza_through_glass | 38 | 4.5 | 214.8 / 275.9 / 300.4 | 12.9 / 22.6 | 218.2 / 272.5 | 8807 | 11.49 M | 1252 | 3649 / 2486 | no |
| exterior_garage | 39 | 6.5 | 153.8 / 202.1 / 207.9 | 12.0 / 24.2 | 151.0 / 197.9 | 6792 | 9.61 M | 1252 | 3653 / 2490 | no |
| exterior_storm | 46 | 9.0 | 111.4 / 140.8 / 167.2 | 3.1 / 4.5 | 107.0 / 136.3 | 1133 | 4.26 M | 1252 | 3658 / 2497 | no |
| four_suited_crew | 39 | 6.2 | 156.0 / 237.4 / 258.6 | 14.8 / 26.5 | 157.3 / 230.0 | 7927 | 10.24 M | 1252 | 3697 / 2528 | no |
| rover_route | 41 | 7.8 | 131.3 / 156.7 / 171.8 | 5.2 / 6.6 | 123.2 / 144.3 | 1279 | 5.37 M | 1252 | 3682 / 2515 | no |

Medium measured slower than High in this run. That is the GPU contention changing between runs, not Medium costing
more: in the single-process ablation (3.5) Medium was faster than the High baseline next to it in both views
(greenhouse 88 vs 111 ms GPU, storm 116 vs 198 ms). Medium does use ~200 MB less video memory (1251 vs 1458 MB).

### 3.3 High, capped 60 (`perf/high_capped.json`)

| View | Frames | Mean FPS | Frame p50 / p95 / p99 ms | CPU ms mean / p95 | GPU ms mean / p95 | Draw calls | Primitives | Video MB | Private / WS MB | 60 FPS? |
|---|---|---|---|---|---|---|---|---|---|---|
| room_command_room | 44 | 8.4 | 118.5 / 156.1 / 170.6 | 7.4 / 17.6 | 109.3 / 124.4 | 4865 | 10.94 M | 1458 | 3284 / 2246 | no |
| room_power_room | 45 | 8.8 | 116.3 / 160.1 / 172.0 | 5.4 / 6.5 | 104.8 / 125.2 | 3276 | 6.21 M | 1462 | 3289 / 2252 | no |
| room_greenhouse | 39 | 7.2 | 140.8 / 158.3 / 162.2 | 15.4 / 19.3 | 134.7 / 154.5 | 10330 | 12.86 M | 1455 | 3293 / 2257 | no |
| room_med_bay | 40 | 7.4 | 139.4 / 158.7 / 160.0 | 16.9 / 28.7 | 130.8 / 155.1 | 9622 | 11.44 M | 1456 | 3337 / 2303 | no |
| room_life_support | 43 | 8.2 | 129.4 / 148.6 / 161.8 | 11.6 / 24.1 | 118.5 / 143.2 | 7251 | 9.76 M | 1458 | 3361 / 2325 | no |
| plaza_through_glass | 41 | 7.8 | 134.3 / 152.9 / 153.8 | 13.3 / 16.1 | 124.1 / 147.4 | 8049 | 11.13 M | 1458 | 3348 / 2313 | no |
| exterior_garage | 41 | 7.5 | 142.0 / 160.5 / 166.0 | 15.1 / 27.1 | 128.3 / 157.9 | 8564 | 10.33 M | 1458 | 3357 / 2320 | no |
| exterior_storm | 51 | 10.0 | 98.7 / 139.9 / 142.4 | 3.4 / 4.6 | 95.4 / 134.6 | 1188 | 4.44 M | 1458 | 3358 / 2318 | no |
| four_suited_crew | 49 | 9.7 | 103.1 / 128.3 / 135.7 | 13.7 / 24.8 | 99.3 / 122.8 | 10196 | 11.13 M | 1458 | 3366 / 2326 | no |
| rover_route | 51 | 10.1 | 98.2 / 121.0 / 137.4 | 4.8 / 6.4 | 93.8 / 116.6 | 1282 | 5.35 M | 1458 | 3382 / 2344 | no |

The cap never engages (nothing reaches 60), so capped vs uncapped only shows the contention drift.

### 3.4 Medium capped and the 2560x1369 run

- Medium capped (`perf/medium_capped.json`; a headless test run shared the CPU during it):

| View | Frames | Mean FPS | Frame p50 / p95 / p99 ms | CPU ms mean / p95 | GPU ms mean / p95 | Draw calls | Primitives | Video MB | Private / WS MB | 60 FPS? |
|---|---|---|---|---|---|---|---|---|---|---|
| room_command_room | 50 | 9.9 | 97.5 / 132.7 / 133.7 | 4.8 / 8.4 | 94.3 / 103.7 | 3003 | 9.18 M | 1250 | 3562 / 2324 | no |
| room_power_room | 46 | 9.0 | 108.9 / 131.2 / 139.0 | 4.7 / 6.5 | 105.2 / 119.1 | 2966 | 6.13 M | 1250 | 3568 / 2330 | no |
| room_greenhouse | 39 | 7.7 | 128.9 / 141.8 / 145.2 | 12.3 / 17.3 | 126.3 / 138.8 | 8962 | 11.22 M | 1244 | 3572 / 2336 | no |
| room_med_bay | 43 | 8.5 | 117.6 / 131.2 / 134.0 | 11.8 / 16.5 | 114.3 / 127.7 | 7148 | 8.93 M | 1244 | 3600 / 2363 | no |
| room_life_support | 46 | 9.1 | 109.2 / 125.8 / 128.4 | 7.9 / 13.0 | 106.1 / 121.6 | 5836 | 8.99 M | 1246 | 3638 / 2402 | no |
| plaza_through_glass | 42 | 8.3 | 119.8 / 132.9 / 137.5 | 11.5 / 14.8 | 117.4 / 129.2 | 8298 | 11.73 M | 1246 | 3613 / 2377 | no |
| exterior_garage | 54 | 10.7 | 94.6 / 105.7 / 109.4 | 9.0 / 19.2 | 89.9 / 103.3 | 4872 | 7.64 M | 1246 | 3629 / 2393 | no |
| exterior_storm | 68 | 13.4 | 74.0 / 82.5 / 86.8 | 2.7 / 3.6 | 70.7 / 78.9 | 1078 | 4.24 M | 1246 | 3664 / 2428 | no |
| four_suited_crew | 50 | 9.9 | 100.9 / 115.6 / 121.2 | 10.9 / 20.8 | 98.0 / 110.6 | 6202 | 8.77 M | 1246 | 3640 / 2405 | no |
| rover_route | 55 | 10.9 | 91.9 / 108.2 / 122.6 | 4.3 / 5.0 | 87.4 / 98.2 | 1233 | 5.27 M | 1246 | 3637 / 2402 | no |

  Medium draws fewer calls than High in every view (e.g. exterior_garage 4.9k vs 8.6-11k, command room 3.0k vs
  4.9-5.2k) because the fixture shadows fade out past 24 m.
- `perf/high_uncapped_2560x1369_maximized.json` (window maximized by project.godot, before the fix): 1.6-2.5 FPS,
  GPU 391-633 ms, video memory 1658 MB. Same machine state; about 6x slower for 1.7x the pixels, which points to VRAM
  over-commit (8 GB card, ~6.4 GB already used by others) rather than shading cost. Not a valid 1080p result.

### 3.5 Feature cost, single process, static camera (`perf/ablation.json`, 40 frames per case)

GPU ms mean, each case starting from High. Read with care: `high_again` (the same High state at the end) shows how
much the GPU share moved during the run.

| Case | Greenhouse GPU ms | Draw calls | Storm exterior GPU ms | Draw calls |
|---|---|---|---|---|
| high (baseline) | 111.3 | 7576 | 198.0 | 1744 |
| no fixture shadows | 103.6 | 6230 | 188.3 | 897 |
| no area lights (39 AreaLight3D) | 82.3 | 15884 | 181.1 | 883 |
| no fixture lights at all (417) | 61.4 | 6158 | 143.0 | 850 |
| no sun shadow | 106.4 | 16083 | 168.8 | 1291 |
| no SSIL | 96.5 | 19223 | 167.1 | 1698 |
| no SSR | 107.2 | 19208 | 194.7 | 1705 |
| no SSAO | 118.8 | 19190 | 212.3 | 1502 |
| no glow | 111.6 | 19114 | 185.7 | 1502 |
| MSAA off | 135.7 | 19063 | 79.4 | 1502 |
| Medium preset | 88.1 | 7114 | 115.9 | 1404 |
| high_again (drift check) | **349.3** | 7181 | 172.5 | 1502 |

What can be said: CPU render time is 3-19 ms mean (p95 up to 29 ms with four suited crew), so on this desktop the
frame is GPU-bound in every view. The fixture lights are the largest single item that showed up consistently in both
views (all fixture lights off: -45 % greenhouse, -28 % storm, adjacent cases), and the area lights are a large part of
that indoors. Medium was faster than the adjacent High case in both views. SSR, SSAO and glow were within noise.
The draw-call count for the same still camera swings 6k-19k between cases, i.e. shadow-map re-renders are a large part
of the draw calls (they jump after each preset re-apply). Everything else is below the noise of a shared GPU.

## 4. Optimization changes

**None made to the game.** The brief asked for a change only if it is clearly safe and measurable. With the GPU shared
with another running game instance (run-to-run drift 40 % to 3x), no before/after could be measured honestly, and
the candidates found (fixture/area-light shadow budget, light distance fades in High, visibility ranges) all change
High's authored look, so they need an idle-GPU measurement and a visual check first. The candidates, in the order I
would try them on an idle GPU:
1. Area lights (39, all shadowed, `area_range` up to 30 m): Medium keeps them shadowed with a 40 m fade; profile a
   per-zone cull (lights only in the player's zone and neighbours; the build already masks them by zone layer) or
   Medium shadows off for area lights only.
2. Shadow re-render churn: the positional atlas is re-rendered after each preset apply (draw calls jump 7k to 19k on
   a still camera); check `shadow_atlas` quadrant subdivision and whether static fixture shadows can update less often.
3. Visibility ranges: no `visibility_range_end` is set on any mesh in `colony_world.tscn` (one script clears it);
   room interiors are drawn from the exterior (11k draw calls at exterior_garage). Room-level ranges or zone culling.

## 5. Memory growth across quality switches

- perf_bench's in-frame check (6 switches inside one frame, `quality_switch_memory` in high_uncapped.json): private
  bytes 3600, 3866, 4140, 4412, 4381, 4657 MB, i.e. +200-270 MB per switch. This is a **measurement artefact**: the
  switches happen with no frame rendered, so the renderer has not freed the replaced buffers yet.
- Settled check (`perf/switch_memory.json`, 8 switches, 30 rendered frames after each, no views): private MB
  2795 (High baseline), 3061 (Medium), 3104, 3078, 3079, 3113, 3111, 3132, 3088, final High 3089. **+266 MB once on the
  first switch, then flat within +/-35 MB over 8 more switches: no growth.** Video memory alternates 934 MB (High) /
  728 MB (Medium), texture memory 380 / 174 MB: Medium does release the larger shadow atlases and buffers.
- The one-time +266 MB after the first switch is not explained (possibly pipeline/shader variants compiled for the
  second preset); it does not repeat.

## 6. Other observations

- Engine error spam `geom->softshadow_count==0 - BUG!` (`renderer_scene_cull.cpp:348`, `_instance_unpair`), 80 lines
  per run, with GDScript backtrace `player_visual.gd:239 set_suit` from `player_controller.gd:307` when suit parts
  toggle visibility near soft-shadow lights. Engine-side; costs console time in debug runs. `set_suit` and its
  `_apply_look_parts / _apply_face_glow / _update_name_tag` run every physics frame for the local player even when
  nothing changed (small CPU waste; not changed here, gameplay code).
- Views missing from the bench: Hangar, Rec Kitchen, Mess Hall were not created (their names in `zones.rooms` do not
  match the harness's target names); the multiplayer `--host` run was not done.

## 7. Targets and limits

| Target | Result |
|---|---|
| 60 FPS at 1080p, High, per view | **Not met in any view** under these conditions (best: exterior_storm 16.4 FPS mean) |
| 60 FPS at 1080p, Medium, per view | **Not met in any view** (best: exterior_storm 9.0 FPS, contended run) |
| Valid idle-GPU measurement | **Not obtained**: re-run `perf/run_all.sh` with the editor's running game (PID 14308) and other GPU users closed |
| Owner's laptop | **Not measured.** These are desktop RTX 4060 Ti numbers; do not generalise to the laptop |
| Memory growth over quality switches | No growth after the first switch (settled check) |
| Lighting re-score vs matched Blender Cycles cameras | **Not done (not feasible in the time).** All earlier sub-95 lighting flags stay open; no lighting parity is claimed |
| Screenshots, transitions, UI legibility, full traversal route after optimization | Not done |

## 8. Files changed (work copy only)

- `G:\nasa app\_work\p13\tools\perf\perf_bench.gd` (window fix, render size in records)
- `G:\nasa app\_work\p13\tools\perf\perf_switch_memory.gd` (new)
- `G:\nasa app\_work\p13\tools\perf\perf_ablation.gd` (new)
- `G:\nasa app\_work\p13\perf\summarise.py`, `run_all.sh`, `run_diag.sh` (new), JSON + logs + nvidia-smi snapshots
- `G:\nasa app\_work\p13\docs_draft\P13_HANDOFF.md` (this file)

Checks (headless): `check_compile.gd` -> `COMPILE OK 216 scripts`. `tools\run_tests.ps1 -Import -Tests
test_graphics_quality,test_game_scene,test_player`: graphics_quality 23/23, player 112/112, game_scene 27/32 on the
first run (walk-from-hub and suit-rack timing checks; it ran while the windowed Medium-capped benchmark and other
workers loaded the CPU), then **32/32 on an immediate re-run** of `test_game_scene` alone. No game code was changed,
so those five checks are timing-sensitive under load, not a regression from this work.
