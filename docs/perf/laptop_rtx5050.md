# Laptop fit: RTX 5050 Laptop GPU, Ryzen 9 9955HX, 16 GB DDR5 (2026-11-15)

Owner request: "optimize the game for a laptop gpu 5050 16 gigs of ddr5 amd ryzen 9 9955hx 16 core processor laptop".

**Status: written, not run.** No compile check, test or benchmark was run (owner rule: the owner runs all checks), and
the laptop itself was not available: the work machine is a desktop RTX 4060 Ti. The test file
`tests/test_hardware_profile.gd` is in `tools/run_tests.ps1`; run the suites with `-Import` once, because two new
`class_name` scripts were added (`HardwareProfile`, `DynamicResolution`).

## What limits this game on that laptop

From the measurements already in this folder (`benchmark_2026-11-14.md`, `baseline.md`):

- **GPU, not CPU and not memory.** Every view is GPU-bound: 14-35 ms GPU at 1080p High on the RTX 4060 Ti, against
  3-19 ms of CPU render time. A 16-core Ryzen 9 9955HX has room to spare. The game uses about 3.5 GB of RAM and
  1.3-1.5 GB of video memory, so 16 GB of RAM and the 5050's 8 GB of video memory are not a limit.
- **The RTX 5050 Laptop GPU is about 0.7x an RTX 4060 Ti** (estimate from public benchmark averages, not measured in
  this game). At 1080p High that puts it at roughly 20-50 ms per frame: 20-50 FPS, the Greenhouse slowest.
- **Laptop panels have more pixels.** The game window opens maximized and draws 3D at the panel's own resolution. A
  2560x1600 panel is twice the pixels of 1080p, and most of the frame cost is per pixel (417 fixture lights,
  SSAO / SSIL, MSAA).

## What was added

| Part | File | What it does |
|---|---|---|
| Hardware fit | `scripts/ui/hardware_profile.gd` | Rates the graphics card by name against the RTX 4060 Ti (1.0). STRONG (0.90+): High, nothing changed. MID (0.50-0.90, the 5050 laptop scores 0.70): Medium. BASIC (under 0.50, or a chip built into the processor): Low. Unknown names and headless runs: nothing changed. |
| Adaptive render resolution | `perf/dynamic_resolution.gd` | On MID and BASIC cards only. Caps the 3D picture at 1920x1200 pixels (BASIC: 1600x900), then measures the real GPU time twice a second and moves the 3D render scale in 0.1 steps (FSR upscaling, floor 0.6 / 0.5) to hold 60 FPS. Menus and HUD stay at full resolution. A step that saves under 4 % is undone. |
| Setting | `GameSettings.graphics_auto`, Settings > Graphics > "Fit to this computer" | On by default. Picking a preset by hand turns it off and the preset then runs exactly as before. The line under the presets names the graphics card the game is running on. |
| Perf HUD | `perf/perf_hud.gd` (Ctrl+1, debug builds) | New line: graphics card, score, 3D render scale and window size, adaptive on/off, measured GPU ms. |
| Switch | `PerfSettings.dynamic_resolution_mode` | -1 follow the setting (default), 0 never, 1 always. `--perf-off` sets 0. `-- --perf-set=dynamic_resolution_mode:1` forces it on any card; `dynamic_resolution_target_fps` (60) is the rate it holds. |

Existing settings files: a file that has no `graphics_auto` yet keeps a preset other than High as a hand-made choice
(fit off); a file on High, the old default, gets fit on.

Nothing changes on the desktop RTX 4060 Ti: it rates STRONG (0.96), so it stays on High at the window's resolution.

## Expected result on the RTX 5050 laptop (estimate, to be confirmed on the laptop)

Medium was 12-21 % cheaper than High indoors and 41-64 % cheaper outdoors in the earlier runs (decision E-33 and the
Prompt 13 ablation, both on a shared GPU). With the
1920x1200 cap and the render scale free to drop to 0.6, most rooms should hold 60 FPS; the Greenhouse (76 fixtures, 35
area lights) is the likely exception at around 45 FPS. These are estimates from 4060 Ti numbers, not measurements.

## How to check on the laptop

1. Start the game, open Settings > Graphics. The line under the presets must name the **RTX 5050**. If it names
   "AMD Radeon(TM) 610M" the game started on the processor's built-in chip: in Windows Settings > System > Display >
   Graphics, set the game (or Godot) to "High performance", or pick the NVIDIA card in the NVIDIA Control Panel.
2. In a debug build press Ctrl+1: the new line shows the score (about 0.70), the render scale and the GPU ms.
   Walk through the Greenhouse and outdoors: the scale should settle, not flip back and forth.
3. Plug the laptop in and use its performance power mode: on battery the card runs at a fraction of its power.

## Not done

- No measurement on the laptop or on the desktop (see Status).
- The Greenhouse's area lights were not changed (it would change the authored look; listed as an owner option in
  `final_report.md`).
- No frame-rate cap: with vsync on, a 165 Hz panel lets cheap views run above 60 FPS.
