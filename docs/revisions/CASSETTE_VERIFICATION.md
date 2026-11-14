# C01-C04 cassette verification

The newest complete per-suite results in `evidence/cassette_tests/`, `evidence/cassette_rechecks/` and `evidence/cassette_final_checks/` pass **17 affected suites, 1261/1261 checks**. Logs are grouped by suite name and selected by newest modification time. All selected logs contain a complete RESULT line and zero FAIL, SCRIPT ERROR or Parse Error lines.

These are current cassette/merged-main regression results. The earlier foundation batch's 2042 checks remain historical and are not added to this total. Full original F and later S/T/A/V/Q feature acceptance is not inferred from these affected-suite results.

| Suite | Latest result | Evidence |
| --- | --- | --- |
| `test_cassette_assets` | 57/57 | `evidence/cassette_rechecks/test_cassette_assets.txt` |
| `test_cassette_ui` | 76/76 | `evidence/cassette_final_checks/test_cassette_ui.txt` |
| `test_cassettes` | 88/88 | `evidence/cassette_rechecks/test_cassettes.txt` |
| `test_game_scene` | 33/33 | `evidence/cassette_final_checks/test_game_scene.txt` |
| `test_game_services` | 25/25 | `evidence/cassette_tests/test_game_services.txt` |
| `test_hud_panels` | 89/89 | `evidence/cassette_tests/test_hud_panels.txt` |
| `test_net` | 56/56 | `evidence/cassette_rechecks/test_net.txt` |
| `test_net_game` | 21/21 | `evidence/cassette_tests/test_net_game.txt` |
| `test_p07_panels` | 54/54 | `evidence/cassette_rechecks/test_p07_panels.txt` |
| `test_perf` | 48/48 | `evidence/cassette_rechecks/test_perf.txt` |
| `test_repair_anchors` | 113/113 | `evidence/cassette_tests/test_repair_anchors.txt` |
| `test_repair_foundations` | 119/119 | `evidence/cassette_tests/test_repair_foundations.txt` |
| `test_saves` | 56/56 | `evidence/cassette_rechecks/test_saves.txt` |
| `test_sources` | 76/76 | `evidence/cassette_rechecks/test_sources.txt` |
| `test_station_panels` | 196/196 | `evidence/cassette_tests/test_station_panels.txt` |
| `test_task_panel` | 29/29 | `evidence/cassette_final_checks/test_task_panel.txt` |
| `test_ui_framework` | 125/125 | `evidence/cassette_final_checks/test_ui_framework.txt` |

## Compilation, packaging and repeat verification

- Engine: `4.7.2.stable.official.ed1daf0bf`. Import completed without script/parse errors. `evidence/cassette_compile.log` records `COMPILE OK 258 scripts`.
- Actual exported PCK verification passed all six local cassette metadata/texture records: `evidence/cassette_pack_verify.log`, `PACK RESULT 6/6`. Gameplay photograph loading uses local resources; the source link is optional. The temporary approximately 370 MB pack is kept in ignored test output, rather than committed as a source asset.
- The corrected suit fixture was repeated using the same test helper with `--suit-only`: `evidence/cassette_suit_fixture_recheck.log`, 10/10, exit 0. This repeat overlaps the full game-scene suite and is not added to the unique 1261-check total.
- The final rendered world walkthrough passed 113/113 in `evidence/cassette_world_capture.log`. It exercises local approaches to all nineteen foundations, actual E collection/disappearance for all six tapes, a physical player opening a local photograph/page, and rejected reading away from the player. Tests teleport between rooms; an uninterrupted human traversal is not claimed.

## Corrected initial failures

The raw command summaries retain earlier FAILED TESTS lines for transparency. The table above uses newer passing results after the following corrections:

1. Save integrity initially 53/56: its fixture used the shared `_test_saves/` root and expected only save JSON files. The offline PCK/export logs were legitimate unrelated files in that directory. The test now uses isolated `_test_saves/save_integrity/`, preserving the exact rotation/deletion assertions and unrelated outputs. Rerun: 56/56.
2. P07 panel mapping initially 53/54: the old expectation classified the new cassette player as a generic StationPanel. The explicit new-kind case now requires the real CassettePlayerPanel and retains legacy type checks. Rerun: 54/54.
3. Game-scene suit checks initially 28/32: the test's search probe used a hard-coded 1.7 m capsule with its bottom at 0.10 m, while actual player placement uses a 1.8 m body with feet initially at 0.05 m. The fixture admitted an invalid approach; physics depenetrated the body/host to `(15.54384, 2.509142, 8.304588)`, actually 2.93 m from the rack. The host correctly rejected that request beyond its unchanged 2.6 m limit. The helper now uses actual PlayerTuning dimensions with a small conservative margin and matching placement center. Suit checks use the existing measured clear approach `(16.4, 0, 7.5)` and add a grounded/reported/in-reach assertion. All original timing, tank and cancellation assertions remain. Full rerun: 33/33; repeated focused fixture: 10/10. No production distance validator or gameplay rule was weakened.

The new ENet sequence also required its position-report fixture to repeat reports until the transport's existing 20 Hz throttle accepted them, as a normal controller does. Its original host-position/request assertions remain intact, and the complete updated suite passed 56/56.

## Visual and product verification

All six actual NASA image files were independently viewed and match their room-specific subject/caption. `data/cassette_photos.json` carries original URLs, official pages, identities, credits, access date, dimensions and hashes; six source-register/credit records match the packaged files. NASA ground-test/ISS photographs are accurately labeled, with no claim that they show an operating Mars colony.

The updated `evidence/cassettes/` images show all six reader combinations, 720p/1080p normal and enlarged/high-contrast layouts, keyboard-accessible scrolled controls, collected/missing popup, metadata-only inventory and critical interruption. Initial MenuButton contrast and zero-height pane problems were corrected; final tests verify actual contrast, useful pane sizes and keyboard scrolling. Image remains left, text right, aspect ratio preserved, Close reachable and world corners visible.

`evidence/cassette_world/` includes twenty-one PNGs plus a before/after contact sheet: six visible labeled native cassette props disappear after actual collection, and the sole physical Command Room player is shown before use and reading. No solid pickup obstruction is added.

C04 ships the user-approved truthful previews: six two-page briefings of 169-178 words, with current collection/player controls and clearly labeled future task designs. Final controls/success conditions for all twelve production puzzles remain deferred to T implementation. S01 and later sections were not implemented.

## Known limits

No human or two-computer LAN playtest was performed. ENet tests use separate SceneMultiplayer branches over real loopback transport. Its occupied-port negative test intentionally prints a host-creation error before the refusal assertion passes.

Godot Vulkan renderer softshadow/indexing diagnostics were observed during rendered setup/teardown. The final world capture records 314 indexing diagnostics, seven texture RIDs reported leaked, 116 ObjectDB instances and 24 resources reported at exit; it still exits successfully with 113/113 and no script/parse/fail lines. These diagnostics are not claimed to be pre-existing: no clean rendered baseline comparison establishes that. A warning-free renderer is not claimed. Existing global HUD overlap is outside this cassette batch.
