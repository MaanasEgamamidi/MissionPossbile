# Perf overhaul, Phase 6: shader warm-up, diagnostics, streaming

Status: **warm-up implemented, OFF by default; streaming not done (decision gate not passed).**

- `perf/shader_warmup.gd`: black CanvasLayer overlay, player input off, the camera alone (top_level) visits every
  zone at 4 yaws for 2 frames each, then optional Mars viewpoints; zones and the exterior controller are paused
  during the tour and `snap()`ped after. Started by PerfRig at the start of play when `shader_warmup_enabled`.
  OFF because Godot 4.7 Forward+ precompiles pipelines (ubershaders), and at the frame rates measured in Prompt 13
  (10-15 FPS) the 136-frame tour would take ~10 s. Turn it on only if Debugger > Monitors shows pipeline
  compilations during S2/S4 play.
- Pipeline compilation monitors: not checked (needs a windowed run).
- Streaming (9.2): not done. Gate not passed: all zones are resident already (the map is one imported scene),
  and memory did not grow across quality switches in Prompt 13.
