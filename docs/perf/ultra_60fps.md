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
| 2 | **Ultra uses FSR 2** (temporal anti-aliasing + upscaling) instead of 4x MSAA, render scale 0.77 adaptive down to 0.5 by `DynamicResolution` (budget 85 % of a 60 FPS frame). Changing the scale costs < 3 ms once (measured). | `scripts/ui/graphics_quality.gd`, `perf/dynamic_resolution.gd` | about -50 % GPU | stills within run-to-run noise of native 4x MSAA |
| 3 | **Light view.** The colony's meshes are merged across rooms and a 70-degree spot light is clustered by Godot as a cone of base radius tan(70) x range (38 m for a 14 m light), so every neighbouring room's lights were evaluated over the whole room you stand in (lights with an empty cull mask cost the same as lit ones, measured). A drawn zone's fixture lights now stay off while no door or window into it is near the camera's view (diagonal FOV + 25 degrees, held 1 s; 2 glass links deep). | `perf/zone_manager.gd` (`_update_light_view`, `zones_in_view`) | -3 to -4 ms in rooms | mean diff < 1/255 |
| 4 | **Neighbour shadows.** A zone the camera is not in (nor within 2 m of a door into) draws its lights without shadow maps. Their per-frame shadow redraws were half the draw calls. | same + `ZoneLighting.set_zone_shadows`, `GraphicsQuality.set_fixture_shadow_blocked` | Greenhouse 14k -> 7k draws, 18.3 -> 14.9 ms | within noise |
| 5 | **Tunnel area lights fade** (Ultra): the four shadowed exit-tunnel panels (30 m range) light only the tunnel; full strength within 12 m of the camera, gone by 18 m. | `GraphicsQuality._apply_fixture` | -15 ms outdoors, -2.5 ms in the plaza | within noise |
| 6 | **Light switches spread over frames**: up to 8 lights on and 4 off per frame (each zone toggle cost 6-8 ms in one frame). Power changes stay immediate; teleports flush at once. | `scripts/world/zone_lighting.gd` | removes 33-39 ms hitches | none |

Switches (all on by default, all off with `--perf-off`): `PerfSettings.light_view_enabled`,
`light_view_shadows_enabled`; tunables `light_view_margin_deg` 25, `light_view_hold` 1 s, `light_view_near` 3 m,
`light_view_hops` 2, `light_view_shadow_near` 2 m. Nothing here touches game state, collision or physics: fixture
lights are visual only (nothing in the game reads them) and the HUD fix returns the same numbers.

## Result (Ultra, 2560x1369, vsync on, 60 cap, camera turning 20 deg/s)

| View | FPS | Frame p95 | p99 | GPU ms |
|---|---|---|---|---|
| Command Room | 59.6 | 18.2 | 20.8 | 13.8 |
| Power Room | 60.0 | 16.8 | 17.7 | 14.5 |
| Greenhouse | 60.0 | 16.9 | 17.3 | 12.0 |
| Med Bay | 60.0 | 17.6 | 19.6 | 9.6 |
| Life Support | 59.8 | 18.1 | 20.0 | 11.6 |
| Plaza through glass | 60.0 | 16.9 | 17.9 | 10.8 |
| Exterior (garage) | 60.0 | 17.0 | 17.3 | 8.5 |
| Exterior (storm) | 60.0 | 16.9 | 17.1 | 11.2 |
| Four suited crew | 60.0 | 17.1 | 17.3 | 12.4 |
| Rover route | 60.0 | 17.0 | 18.7 | 13.1 |

(`bench_ultra_v5_vsync.json`; debug build run from the editor binary: an exported release build has less CPU
overhead.)

## Tried and not kept

- Separate render thread (`thread_model=2`): small gain, engine prints "experimental", errors on exit.
- Shorter range / no shadow on the tunnel lights, shorter greenhouse grow-light range, narrower spot angles: smaller
  gains than the above and a visible change.
- Light view at 1 glass link: -1.2 ms more but the far side of the plaza goes dark.

## Tools

`tools/perf/ultra_ablation.gd` (cases, `a+b` combos, `--shots`, `--yaw`), `compare_images.gd` (mean / changed /
p99 and diff images), `probe_hitch.gd` (main-thread stall bisection), `probe_hud_cost.gd`, `probe_spikes.gd`
(what changed in a long frame), `probe_scale_switch.gd`, `perf_bench.gd --window=WxH`.
