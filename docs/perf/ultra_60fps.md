# Ultra at 60 FPS on the RTX 4060 Ti (2026-11-18)

Owner goal: "60fps stable on ultra on my 4060ti, use any technique, gameplay should not be affected at all". Second
goal: 30 FPS on Low on any post-2020 computer with a decent CPU and an integrated GPU or an RTX 3050-class card.

Machine: RTX 4060 Ti 8 GB, i7-12700KF, Godot 4.7.2 Forward+, window 2560x1369 (the owner's 1440p screen,
maximized). All numbers from `tools/perf/perf_bench.gd` / `ultra_ablation.gd` runs in `G:/nasa app/_perf/ultra/`.

## Where it started

| View (Ultra, 2560x1369, vsync off) | Frame ms | GPU ms |
|---|---|---|
| Command Room | 47.6 | 32.7 |
| Power Room | 50.4 | 36.8 |
| Greenhouse | 57.3 | 42.5 |
| Med Bay | 36.6 | 25.9 |
| Plaza through glass | 54.8 | 39.2 |
| Exterior (garage) | 58.0 | 45.1 |

17-27 FPS. Two separate problems: a CPU stall in every view (frame ms far above GPU ms), and a GPU frame 2-3x over.

## What was changed

| # | Change | Where | Gain (measured) | Picture |
|---|---|---|---|---|
| 1 | **HUD battery forecast stall.** `ReserveForecast._battery()` steps ~1500 times and called `PowerModel.solar_kw()` each step (upgrade, area-level, condition lookups). The vitals bar runs it 4x a second: one ~95 ms frame every 0.25 s on every machine and preset. `PowerModel.solar_inputs()` / `solar_kw_with()` read the time-independent inputs once. | `scripts/sim/power_model.gd`, `reserve_forecast.gd` | refresh 94 ms -> 1.5 ms; frame = GPU time again | none (bit-identical: 4000 phases compared) |
| 2 | **Ultra uses FSR 2** (temporal anti-aliasing + upscaling) instead of 4x MSAA, render scale 0.77 adaptive down to 0.5 by `DynamicResolution` (budget 80 % of a 60 FPS frame: the measured 3D time leaves out the full-size upscale, post and UI). A step down is undone only after two probes in a row find no gain (one probe right after loading held Ultra at 77 % for 30 s in the MCP play test). Changing the scale costs < 3 ms once (measured). | `scripts/ui/graphics_quality.gd`, `perf/dynamic_resolution.gd` | about -50 % GPU | stills within run-to-run noise of native 4x MSAA |
| 3 | **Light view.** The colony's meshes are merged across rooms and a 70-degree spot light is clustered by Godot as a cone of base radius tan(70) x range (38 m for a 14 m light), so every neighbouring room's lights were evaluated over the whole room you stand in (lights with an empty cull mask cost the same as lit ones, measured). A drawn zone's fixture lights now stay off while no door or window into it is near the camera's view (diagonal FOV + 25 degrees, held 1 s; 2 glass links deep). | `perf/zone_manager.gd` (`_update_light_view`, `zones_in_view`) | -3 to -4 ms in rooms | mean diff < 1/255 |
| 4 | **Neighbour shadows.** A zone the camera is not in (nor within 2 m of a door into) draws its lights without shadow maps, through a 0 m shadow fade distance (never `shadow_enabled`, see 6). Their per-frame shadow redraws were half the draw calls. | same + `ZoneLighting.set_zone_shadows`, `GraphicsQuality.set_fixture_shadow_blocked` | Greenhouse 14k -> 7k draws, 18.3 -> 14.9 ms | within noise |
| 5 | **Tunnel area lights fade** (Ultra): the four shadowed exit-tunnel panels (30 m range) light only the tunnel; full strength within 12 m of the camera, gone by 18 m. | `GraphicsQuality._apply_fixture` | -15 ms outdoors, -2.5 ms in the plaza | within noise |
| 6 | **Lights switched by distance fade, not `visible`** (`GraphicsQuality.set_fixture_view_off`). A light made visible again is re-paired by Godot with every mesh in its reach, ~1-1.5 ms of CPU each (a snap turn that lit 5 rooms: 28-33 ms frames), and hiding or switching the shadow of soft-shadow lights printed engine "softshadow_count==0 - BUG!" errors with backtraces. A light past its fade is skipped at draw time and stays paired. `visible` stays with power cuts. | `scripts/world/zone_lighting.gd`, `scripts/ui/graphics_quality.gd` | snap turns: no frame over 22 ms after the first sight of an area | none |
| 7 | **Background autosave.** The 60 s autosave took ~23 ms on the main thread (checksum, JSON, write, read-back, backups). The colony is snapshotted and deep-copied on the main thread (0.5 ms); the same `SaveService.write()` runs on a worker. Saves for a reason (important action, manual, quit) stay immediate and wait for a running one. Headless runs save in place. | `scripts/core/game_services.gd` | removes the once-a-minute long frame | n/a |
| 8 | **"Fit to this computer" picks Ultra on Strong cards** (was High). High draws every pixel natively with 2x MSAA and now runs slower than Ultra at 1440p (36-50 FPS, `bench_high_final.json`). Picking High by hand keeps it exactly as authored. | `scripts/ui/hardware_profile.gd` | owner's card starts at Ultra 60 | - |
| 9 | **Shadow proxies.** Godot draws every surface of a mesh separately in every shadow pass, and the merged colony meshes carry ~5.4 materials each (the sun alone: 7.7k of 12.9k draws at the tutorial start). Each colony mesh whose materials are all opaque and leave vertices in place casts through a one-surface child copy (SHADOWS_ONLY) and stops casting itself: same shadow geometry, 1692 proxies built in ~2 s at load. | `perf/shadow_proxies.gd` (`PerfSettings.shadow_proxies_enabled`) | draws 12.9k -> 3.5k (tutorial start), 8.6k -> 4.9k (Command Room); render CPU -1 to -3 ms | within noise |

Switches (all on by default, all off with `--perf-off`): `PerfSettings.light_view_enabled`,
`light_view_shadows_enabled`; tunables `light_view_margin_deg` 25, `light_view_hold` 1 s, `light_view_near` 3 m,
`light_view_hops` 2, `light_view_shadow_near` 2 m. Nothing here touches game state, collision or physics: fixture
lights are visual only (nothing in the game reads them) and the HUD fix returns the same numbers.

## Result (Ultra, 2560x1369, vsync on, 60 cap, camera turning 20 deg/s)

| View | FPS | Frame p95 | p99 | max | GPU ms |
|---|---|---|---|---|---|
| Command Room | 60.0 | 16.9 | 17.0 | 18.3 | 13.1 |
| Power Room | 60.0 | 16.8 | 17.0 | 18.1 | 12.6 |
| Greenhouse | 60.0 | 16.8 | 17.0 | 17.1 | 12.4 |
| Med Bay | 60.0 | 16.8 | 17.0 | 24.1 | 9.8 |
| Life Support | 60.0 | 16.8 | 17.1 | 17.6 | 11.9 |
| Plaza through glass | 60.0 | 16.8 | 16.9 | 16.9 | 11.2 |
| Tutorial start (new colony) | 60.0 | 16.9 | 17.2 | 20.4 | 10.7 |
| Exterior (garage) | 60.0 | 17.0 | 17.3 | 17.9 | 8.7 |
| Exterior (storm) | 60.0 | 17.0 | 17.2 | 17.5 | 9.9 |
| Four suited crew | 60.0 | 17.0 | 17.1 | 17.3 | 10.6 |
| Rover route | 60.0 | 17.2 | 18.1 | 19.1 | 13.1 |

(`bench_ultra_v8.json`, commit b33066d; debug build run from the editor binary: an exported release build has less
CPU overhead.)

## Live play test through the Godot MCP (2026-11-18, owner's request)

The game was run from the editor (play mode), driven through the Funplay runtime bridge (keys, actions, mouse drags)
and measured with `PerfHud.summary` (last 600 frames). Ultra, 2560x1369, the owner's display (~59-60 Hz with vsync;
some stretches ran faster). The owner's save and settings were backed up first and restored after.

| Stretch (10 s each) | avg ms | p99 ms | frames > 20 ms | worst ms |
|---|---|---|---|---|
| Tutorial start, standing (before the fixes below) | 23.0 | 26.1 | 600 | 30.5 |
| Tutorial start, standing (final) | 16.9 | 16.9 | 0 | 16.9 (locked to the display) |
| Loaded save, airlock / Power Room, standing | 9.4 | 10.8 | 0 | 18.5 |
| Same, instant 60-110 degree camera snaps | 11.3 | 14.6 | 2 | 24.2 |
| Walking Power Room -> airlock with turns | 14.0 | 21.1 | 9 (1.5 %) | 27.3 |
| Command Room: walk to the colony computer, hold E, panel opens (colony summary, upgrades, rover tabs, live data) | 9.0 | 13.6 | 3 | 147 (the frame the panel is built) |

What the play test found that the bench had missed (all fixed above): the tutorial start view (shadow proxies),
DynamicResolution held at 77 % by one bad probe after loading, its budget leaving out the full-size passes, and the
light view's `visible` re-pairing cost on fast turns. Still left: the first time an area comes into view in a
session costs one 70-90 ms frame (pipeline warm-up, it does not repeat), and room crossings show ~1-2 % frames of
20-27 ms. Watch out when measuring: a game left running from the editor shares the GPU and inflates every number
(it did once here; those runs were thrown away).

## Low on integrated graphics and RTX 3050 (estimate, not measured on those machines)

### Measured with the RTX 4060 Ti underclocked (owner's go-ahead, 2026-11-18)

`nvidia-smi -lgc 1100,1100` (elevated) locked the card at 1110 MHz, ~40 % of its boost clock: about an RTX 3050's
compute (its memory bandwidth stays higher than a 3050's, 288 vs 224 GB/s). The second lock (270 MHz, Iris Xe-like)
and the reset prompt were not accepted, so the iGPU numbers are scaled from the 1110 MHz runs (x 1110 / 270 = 4.1).

**RTX 3050-like (1110 MHz), Low at 1920x1080, adaptive resolution on (aims for 60)** (`bench_low_3050emu.json`):
67-99 FPS in all 11 views (p99 13-26 ms). One single 1.6 s frame on first entering the Med Bay (render thread:
a first-use pipeline compile; it did not repeat).

**Low made lighter for chips in the processor** (Low only; High / Ultra unchanged): fixture lights fade from 15 m
(was 25 m), the light view goes one glass link deep, unshadowed area lights (greenhouse grow panels) reach half
their range. At the adaptive floor (render scale 0.5, 1600x900 window, 1110 MHz), GPU ms before -> after:
Greenhouse 9.5 -> 7.0, Plaza 8.6 -> 7.2, tutorial start 8.3 -> 7.6, Command Room 6.2 -> 4.9, exterior 6.8 -> 5.5,
Power Room 5.8, Med Bay 4.0 (`ablation_low_1110*.json`).

Scaled to Iris Xe-class compute (x4.1): 16-31 ms, i.e. 32+ FPS in every view at the floor; Radeon 680M/780M-class
(x2.6): 10-20 ms. Optimistic for real iGPUs, whose shared memory (~68 GB/s) is far slower than this card's; CPU side
(game logic ~3 ms, render thread 3-7 ms at Low here) leaves a post-2020 laptop CPU well under 33 ms.

Older estimate, kept for the record:

Measured here: Low at 1600x900 (the cap for Basic cards), adaptive resolution off: 3.5-6.1 ms GPU, 2-6 ms render CPU,
105-240 FPS; at render scale 0.5 the heaviest rooms (Greenhouse, Plaza) still take ~4 ms, half of it fixture lights
(Godot clusters each light's volume, a cost that does not shrink with resolution). Scaled by rough GPU throughput
(RTX 4060 Ti = 1):

| Graphics | Ratio | Expected on Low (adaptive) |
|---|---|---|
| RTX 3050 desktop / laptop | ~0.45 / ~0.35 | 60 FPS, little or no scaling |
| Radeon 680M / 780M (Ryzen 6000/7000) | ~0.2-0.25 | 30+ FPS everywhere, 60 in light rooms |
| Intel Iris Xe 96EU (11th-13th gen) | ~0.12 | about 30 FPS in the heaviest rooms at 50 % scale, more elsewhere |
| Radeon Vega 7/8 (Ryzen 4000/5000) | ~0.09 | 30 in most rooms, low 20s in the Greenhouse / Plaza |

A chip built into the processor now aims for 30 FPS (`HardwareProfile.INTEGRATED_TARGET_FPS`), so the render scale
stays as high as 30 FPS allows instead of dropping to 50 % to chase 60. CPU: game logic is ~3 ms a frame after the two
stall fixes; a post-2020 laptop CPU at ~60 % of an i7-12700KF needs ~10-18 ms a frame on Low, well under 33 ms.

## Station panels and an FSR 2 particle error (2026-11-18, later)

- **Opening a station panel** (Colony computer, bench colony, Command Room, `probe_panel_open.gd`): the first open
  takes 25 ms on the main thread (7 ms to build the panel, 18 ms in `ui.open`), and the slowest of the next 10 frames
  is 53 ms (first-time UI shaders and glyphs). Later opens take 13 ms (4 + 9), and the slowest following frame is about
  35 ms against a ~25 ms baseline at the 1110 MHz underclock. So after the first time, opening a panel costs about one
  frame. Not changed: caching built panels could change how panels keep their state.
- **`Parameter "uniform_set" is null` once per frame on Ultra**: found in the probe logs. One GPU particle system (the
  green-dome tape's idle sparkles) that already ran before the game switched from a non-temporal preset to FSR 2 kept
  printing it every frame, even with the camera turned away. It happens when you switch Low → Ultra in Settings (or the bench boots on the owner's Low
  settings and then applies Ultra). Starting a new colony on Ultra never does (checked live through the MCP: 0
  errors). Switching the upscaler off and on later does not bring it back. Fix: `GraphicsQuality.apply` hides the
  visible GPU particle systems for one drawn frame when a temporal preset replaces a non-temporal one, then shows them
  (`_refresh_particles`; nothing restarts). Low boot → Ultra after the fix: 0 errors in the whole run (was ~30 a
  second). `tools/perf/probe_fsr2_errors.gd` bisects this kind of error by node type (`--each`, `--only=`, `--seq`,
  `--modes`). Bench numbers measured before the fix included this error printing, so they slightly overstate the
  frame time.

## Tried and not kept

- Separate render thread (`thread_model=2`): small gain, engine prints "experimental", errors on exit.
- Shorter range / no shadow on the tunnel lights, shorter greenhouse grow-light range, narrower spot angles: smaller
  gains than the above and a visible change.
- Light view at 1 glass link: -1.2 ms more but the far side of the plaza goes dark.

## Tools

`tools/perf/ultra_ablation.gd` (cases, `a+b` combos, `--shots`, `--yaw`), `compare_images.gd` (mean / changed /
p99 and diff images), `probe_hitch.gd` (main-thread stall bisection), `probe_hud_cost.gd`, `probe_spikes.gd`
(what changed in a long frame), `probe_scale_switch.gd`, `probe_panel_open.gd` (station panel first / later opens), `probe_fsr2_errors.gd`,
`perf_bench.gd --window=WxH`.
