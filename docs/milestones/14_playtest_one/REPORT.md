# Prompt 14 — Playtest one (AGENT/TECHNICAL PLAYTEST)

Date 2026-11-14, worker P14-16. Build: copy `G:\nasa app\_work\p14` (pre-fix source), Godot 4.7.2 headless.
**No human, adult or child testers took part.** Everything below is agent/technical observation from scripted runs.
No participant feedback, ages, surveys or comprehension results exist; the brief's pilot targets (80 % / 80 % / 70 %)
remain unmeasured hypotheses.

## Method

- Script: `tools\playtest\playtest_run.gd -- --tag=one` (headless SceneTree). Real model, real `SessionService`
  requests from real peers; crew move by host position reports (the same path the player body uses). No `_skip_to`,
  no direct state writes, no shortened sol (default sol length). Raw output: `docs_draft\playtest_one_raw.txt`,
  per-run data: `docs_draft\playtest_one.json`. (Playtest one ran before the script gained the idle-colony
  `_storms` run and the `_cont_sols` switch; re-running `--tag=one` now also adds one 12-sol idle run.)
- Definitions (reused unchanged in P16): **steps** = player requests sent; **game h** = `sim_hours` from stage start
  to stage end; **blocked** = refused requests with the reason text the player sees; **hub trips** = moves of more
  than 3 m onto the hub point; **warnings** = weather warnings issued.
- Limits of the method: movement is a position report (teleport), so walking time, navigation friction, camera
  comfort, readability, voice and frame time are **not measured** (visual/performance cannot be seen headless).
  Game time per stage therefore reflects simulation waits only, not travel.

## Runs

| Run | Players | Seed | Stage 9 variant | Steps | Hub trips | Blocked | Tutorial done (game h) | Certified (game h) | Lowest reserve | Weather events in 3 sols |
|---|---|---|---|---|---|---|---|---|---|---|
| Solo + certification | 1 | 4242 | trackers_stopped | 34 | 4 | 0 | 1.586 | 26.287 | 60.38 | **0** |
| Solo + certification | 1 | 7 | greenhouse_breaker | 34 | 4 | 0 | 1.586 | 26.287 | 60.38 | **0** |
| Solo + certification | 1 | 99 | lighting_overload | 36 | 4 | 0 | 1.586 | 26.287 | 60.38 | **0** |
| Tutorial | 2 | 4242 | trackers_stopped | 26 | 4 | 0 | 1.586 | — | — | 0 |
| Tutorial | 3 | 4242 | trackers_stopped | 25 | 2 | 0 | 1.586 | — | — | 0 |
| Tutorial | 4 | 4242 | trackers_stopped | 25 | 2 | 0 | 1.586 | — | — | 0 |

Per-stage (all solo seeds identical): game h / steps = 1: 0.021/1, 2: 0.049/1, 3: 0.021/1, 4: 0.029/3, 5: 0.037/6,
6: 0.037/5, 7: 0.021/1, 8: 0.021/4, 9: 1.315/1 (3 for lighting_overload), 10: 0.029/2. Stage 9 holds for ~1.3 game h
by design (the fix must hold). All three stage 9 variants occurred across the three seeds.

Hub switching rules (2/3/4 crew, seed 4242), all as specified:

| Players | Claim away from hub | Claim an occupied crew member | Claim a free one at the hub |
|---|---|---|---|
| 2 | refused `not_at_hub` "Go to the hub to change crew member." | refused `character_taken` "Another player is already that crew member." | accepted |
| 3 | refused `not_at_hub` (same text) | refused `character_taken` | accepted |
| 4 | refused `character_taken` (nobody is free) | refused `character_taken` | n/a (no free crew) |

With four players no tutorial step asked anyone to switch (hub trips 2 = stage 3 and stage 10 visits only).

## Scenarios covered by existing scripted suites (not re-implemented in the playtest script)

Run unchanged on this build; they use real actions on the same model. Results: `docs_draft\baseline_tests.txt`.

| Scenario | Evidence | Result |
|---|---|---|
| Two materially different rover builds, assemble + refit (custom 2/1/3/1/2 for 5 parts; refit lowering battery refunds 3 parts once; cargo 100 kg limit) | `tests\test_rover.gd` `_test_challenge_and_assemble`, `_test_refit_economy`, `_test_cargo` | 80/80 |
| Driven trip on the map collision | `tests\test_rover_drive.gd` | 64/64 |
| Shortage, recovery, dropped-cargo cache retrieval; minor first storm then stronger; offline refresh failure | `tests\test_weather.gd` (fixture bundle), `tests\test_session.gd` | 91/91 session; test_weather 66/66 |
| In-process host + client, late join, peer loss | `tests\test_net_game.gd` | 20/20 |
| Save/load | `tests\test_saves.gd` 56/56, `tests\test_tutorial.gd` 59/59 (save at every stage boundary) | pass |

Important: `test_weather` drives storms from a **test fixture bundle**, not the shipped data, which is why PT-01
below was not caught by any suite.

## Issues found

| ID | Class | Trigger (players/seed) | Expected | Actual | Severity | Suspected cause |
|---|---|---|---|---|---|---|
| **PT-01** | **Blocker** (weather/data) | Any fresh game, offline, any player count; seeds 4242, 7, 99 | Offline boot uses the shipped NASA-derived bundle; a warned minor dust event arrives within the first sols | `WeatherArchive.active().source == "builtin"`: the shipped bundle is rejected ("product meda_ps_sol0289: 88 bad cells … column samples = 314 1 is outside the plausible range"), so the game runs a constant sky with **no dust events at all** (0 events in 3 sols × 3 seeds) | Blocker for weather preparation, storms, the "different seed changes decisions" goal | `scripts\weather\weather_archive.gd` checks every unit-"1" column against the ratio range [-0.001, 50]; the `samples` count column (1 Hz readings per bin, up to ~600) fails. `tests\test_weather_data.gd` has its own validator with a per-name range for `samples`, so it passed while the game's loader failed. |
| PT-02 | Usability / design observation | Solo, all seeds | Seeds should vary decisions | Before the first storm, seeds change only the stage 9 fault; stages 1–8, steps and lowest reserve are identical (60.38) | Low | Expected while PT-01 hides weather (the main seed-dependent system); re-check after fix |
| PT-03 | Usability (pacing) | Solo | 2–3 h target | Not measurable headless: teleport movement; tutorial took 1.59 game h of simulation waits. Real-time pacing still an estimate (I-58) | Info | Method limit |
| PT-04 | Visual/performance | all | — | Not observable headless (no frame times, lighting, camera, readability) | n/a | Method limit |
| I-59 (known) | Blocker-flaky in a test | `test_game_scene` suit-rack step | Body stays on the floor | Thrown ~2.3 m up near the suit rack in some runs | Medium | Not investigated in this window (time); open |

No refused request occurred in any tutorial run; no invariant violation (`invariants_ok()` empty) after 3 sols.
No science error was found in the texts exercised; question texts were not reviewed for wording by a person.
