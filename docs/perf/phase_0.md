# Perf overhaul, Phase 0: instrumentation and baseline (2026-11-14)

Branch `perf-overhaul`, from `d5c8df6` (Prompts 13-17). Source brief: `docs/workers/perf_prompt.md`.

## Project facts

| Item | Value |
|---|---|
| Godot | 4.7.2-stable (`config/features` = 4.7, Forward Plus) |
| Renderer | Forward+ (`rendering_method` not overridden: Forward+). Pipeline precompilation / ubershaders available (4.4+) |
| Scripting | GDScript only (no C#) |
| `res://perf/` | Created here (an earlier session of this branch had left only `perf_settings.gd`, kept and extended) |
| Class names asked for | `Zone`, `ZoneDoor`, `ZoneManager`, `ExteriorController`, `ViewActivator`, `ColonyLod`, `ShaderWarmup`: none existed. The project has `ColonyZones` and `ZoneLighting` (kept, not renamed) |
| Scale | 1 unit = 1 m (manifest in metres, Blender x = Godot x, Blender y = -Godot z) |
| Main scene | `res://scenes/game.tscn` -> `GameMain` builds everything in code; the map is `scenes/world/colony_world.tscn` (instances `colony.glb`, `environment.glb`, `terrain.glb`) |
| Occlusion culling | already ON in project.godot; 21 roof `BoxOccluder3D`s exist |
| Mesh LOD threshold | project setting 2.0 px (engine default 1.0) |

## What was added

- `perf/perf_settings.gd` (autoload `PerfSettings`) and `perf/perf_hud.gd` (autoload `PerfHud`), registered in
  `project.godot [autoload]`. `perf/perf.gd` (`Perf.cfg()`) reads the switches: scripts run with `--script` (all
  headless tests and benchmark tools) are compiled before autoloads are registered and cannot name `PerfSettings`.
- HUD keys (no collision with the game's input map: it binds no Ctrl+digit): Ctrl+1 HUD, Ctrl+2 zones, Ctrl+3 exterior,
  Ctrl+4 view gating, Ctrl+5 occlusion culling, Ctrl+6 mesh LOD threshold 2->3->4->1, Ctrl+7 CSV log
  (`user://perf_*.csv`, now also video MB, node count and the switch state), Ctrl+8/9/0 benchmark route
  record / play / spin test, Ctrl+Shift+1..4 the pixel-changing switches, Ctrl+Shift+0 all off / all on.
- `perf/benchmark_route.gd`: Ctrl+8 records player position + yaw + pitch to `res://perf/route.json` (editor runs) or
  `user://perf_route.json`; Ctrl+9 plays it at 4 m/s, at most 90 deg/s of turn, input off; waypoints may carry
  `open_door` (door id); Ctrl+0 spins 720 deg/s for 5 s and back.
- Launch flags after `--`: `--perf-off` (baseline: every switch off = d5c8df6 behaviour), `--perf-on` (all on),
  `--perf-set=name:value`.
- `tools/perf/run_perf_ab.sh`: the existing Prompt 13 `perf_bench.gd` views run off / default / all, twice.

## Baseline measurements

Headless only at first (owner rule), then the owner asked for a benchmark and approved closing the hung game window
(PID 14308) that had held the GPU since 2026-11-13 20:25 and spoiled Prompt 13. Baseline and A/B results:
`benchmark_2026-11-14.md` (S1-S5 of the brief map onto perf_bench's ten views; the benchmark route itself was not
recorded).
