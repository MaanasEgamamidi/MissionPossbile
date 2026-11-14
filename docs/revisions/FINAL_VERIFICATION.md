# Final foundation verification

Scope: implementation pack pages 1-17 (F01-F06); stop before C01. Engine: Godot `4.7.2.stable.official.ed1daf0bf`.

The newest complete result for each of the 30 suites passes: **2042/2042 checks**. Selection groups logs in `evidence/tests/` and `evidence/rechecks/` by suite name and selects the newest modification time. All selected logs contain a complete `RESULT` line and zero `FAIL`, `SCRIPT ERROR` or `Parse Error` lines. The fresh broad-run import reported `import: ok`.

## Results

| Suite | Latest result | Evidence |
| --- | --- | --- |
| `test_collision` | 40/40 | `evidence/rechecks/test_collision.txt` |
| `test_crew_collision` | 5/5 | `evidence/tests/test_crew_collision.txt` |
| `test_food` | 85/85 | `evidence/tests/test_food.txt` |
| `test_game_scene` | 32/32 | `evidence/tests/test_game_scene.txt` |
| `test_game_services` | 25/25 | `evidence/rechecks/test_game_services.txt` |
| `test_graphics_quality` | 23/23 | `evidence/tests/test_graphics_quality.txt` |
| `test_hud_panels` | 89/89 | `evidence/tests/test_hud_panels.txt` |
| `test_life_support` | 88/88 | `evidence/tests/test_life_support.txt` |
| `test_net` | 44/44 | `evidence/tests/test_net.txt` |
| `test_net_game` | 20/20 | `evidence/tests/test_net_game.txt` |
| `test_p07_panels` | 54/54 | `evidence/tests/test_p07_panels.txt` |
| `test_pdf_fixes` | 43/43 | `evidence/tests/test_pdf_fixes.txt` |
| `test_player` | 112/112 | `evidence/tests/test_player.txt` |
| `test_progression` | 84/84 | `evidence/tests/test_progression.txt` |
| `test_repair_anchors` | 102/102 | `evidence/tests/test_repair_anchors.txt` |
| `test_repair_foundations` | 119/119 | `evidence/tests/test_repair_foundations.txt` |
| `test_rover` | 80/80 | `evidence/tests/test_rover.txt` |
| `test_rover_drive` | 64/64 | `evidence/tests/test_rover_drive.txt` |
| `test_saves` | 56/56 | `evidence/tests/test_saves.txt` |
| `test_science` | 76/76 | `evidence/tests/test_science.txt` |
| `test_scout` | 60/60 | `evidence/tests/test_scout.txt` |
| `test_session` | 91/91 | `evidence/tests/test_session.txt` |
| `test_sources` | 76/76 | `evidence/tests/test_sources.txt` |
| `test_station_panels` | 196/196 | `evidence/rechecks/test_station_panels.txt` |
| `test_task_panel` | 29/29 | `evidence/tests/test_task_panel.txt` |
| `test_tutorial` | 59/59 | `evidence/tests/test_tutorial.txt` |
| `test_ui_framework` | 125/125 | `evidence/tests/test_ui_framework.txt` |
| `test_voice` | 84/84 | `evidence/tests/test_voice.txt` |
| `test_weather` | 66/66 | `evidence/tests/test_weather.txt` |
| `test_weather_data` | 15/15 | `evidence/tests/test_weather_data.txt` |

## Initial failures and corrected reruns

`evidence/test_summary.txt` preserves the original broad command's `FAILED TESTS: 2` result. This file is historical evidence of that run, not the final combined status. Its failures were resolved and their original logs remain intact:

- Collision initially 39/40: the old assertion required radius 1.2 for every station, while F06 intentionally uses radius 0.38 for compact reserved interactions. The assertion now checks legacy radius 1.2 and reserved radius 0.38 separately. Corrected rerun: 40/40.
- Station panels initially 195/196: changing the generic panel title to its header text unintentionally changed existing solar panel titles. Production code now uses custom titles only for the three new reserved station kinds, preserving legacy titles. Corrected rerun: 196/196. Game services rerun: 25/25.

Targeted correction summaries are `evidence/recheck_summary.txt` and `evidence/station_recheck_summary.txt`. The updated suites were rerun after their corresponding fixes. No failed assertion was suppressed.

## Integration and visual evidence

- New foundation rules: 119/119, including role access, host-only puzzle validation, stale/replayed requests, operator lifecycle, same-room co-op, durable state and exposure, safe switching and hazardous disconnect recovery.
- Real ENet loopback: 44/44, including late join midway through a puzzle, live lease replication, completed room/seen-shot state, disconnect/rejoin cleanup and host LAN shutdown ownership cleanup.
- F06 rendered local approach walkthrough: 102/102 in `evidence/anchor_walkthrough.log`; all 19 anchors were locally walked to, aimed at and opened, and all four Med Bay spawn/recovery spots checked against the real map. Tests teleport between rooms; no uninterrupted human route traversal is claimed.
- F05: 29/29. Normal and supported enlarged/high-contrast layouts at 1280x720 and 1920x1080 are captured in `evidence/task_*.png`. Enlarged content scrolls with a fixed Cancel footer. Keyboard/focus/mouse restoration, pending/stale results, live simulation and urgent interruption are covered.
- HUD/arrival and room interaction views: `evidence/anchors/`; seven room/airlock overviews: `evidence/rooms/`. The final marker pass uses smaller, sharper labels and short cassette labels.

## Known limits

The ENet occupied-port negative test intentionally logs a host-creation error before its refusal check passes. Godot Vulkan renderer softshadow/indexing diagnostics were observed during rendered scene setup/teardown, together with teardown resource warnings; the capture processes exited successfully and produced the reviewed images. These are not GDScript parse/runtime failures, and a warning-free renderer is not claimed. Existing HUD tutorial/minimap overlap remains visible; no global HUD redesign was part of this batch.

No human playtest or two-computer LAN session was performed. Actual puzzles, cassette collection/playback, new lethal timing/degradation, restoration art and cinematics are deferred by the explicit C-section boundary. These limitations do not represent missing F01-F06 production puzzle behavior: F05 specifically requests a dummy shell and F02 specifically excludes room puzzles.
