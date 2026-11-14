# Prompt 16 — Playtest two and regression review (AGENT/TECHNICAL PLAYTEST)

Date 2026-11-14. Build: `_work\p14` with fix F-01 (`P15_FIX_MATRIX.md`). Same script and same definitions as
playtest one (`tools\playtest\playtest_run.gd -- --tag=two`); changes in conditions: one extra seed (2027),
continued play 10 sols instead of 3, plus an idle-colony 12-sol run (seeds 4242, 2027). Raw:
`docs_draft\playtest_two_raw.txt`, `docs_draft\playtest_two.json`. **No human or child testers**; audience targets
are unverified.

## Comparison with playtest one

| Measure (same definition) | Playtest one | Playtest two |
|---|---|---|
| Weather data source at offline boot | `builtin` (constant sky) | `shipped` bundle |
| Solo runs reaching certification with real actions | 3/3 | 4/4 (incl. new seed 2027) |
| Weather events, solo seeds | 0 in 3 sols (all seeds) | warned minor first event in every seed |
| First warning → start (game h), severity | — | 4242: 57.47→62.68, 0.222 · 7: 53.17→58.38, 0.237 · 99: 53.25→58.46, 0.304 · 2027: 51.19→56.41, 0.236 |
| Warning lead | — | 5.2 game h in every seed |
| Steps, solo (per run) | 34 / 34 / 36 | 35 / 35 / 37 / 35 (+1 = acknowledging the storm warning) |
| Blocked requests in tutorial runs | 0 | 0 |
| Hub trips solo / 2 / 3 / 4 players | 4 / 4 / 2 / 2 | 4 / 4 / 2 / 2 |
| Hub rules (away refused, occupied refused, free accepted) | pass at 2/3/4 | pass at 2/3/4 |
| Tutorial done / certified (game h) | 1.586 / 26.287 | 1.586 / 26.287 (storm starts after certification) |
| Lowest reserve during certification | 60.38 | 60.38 |
| Invariant violations at end | none | none (end at 249 game h) |

Seeds now change decisions: stage 9 fault (3 variants over 4 seeds), storm timing (51–57 h) and severity
(0.22–0.30). Stages 1–8 stay identical across seeds (fixed tutorial by design).

## Regression results (after the fix)

`docs_draft\final_tests.txt`, `docs_draft\extra_tests.txt`: test_weather_data 15/15 (new regression check),
test_weather 66/66, test_saves 56/56, test_session 91/91, test_tutorial 59/59, test_rover 80/80,
test_net_game 20/20, test_game_services 25/25, plus the others listed in the final summary; compile check
`COMPILE OK 216 scripts`.

## New observations in playtest two

| ID | Class | Observation | Severity | Status |
|---|---|---|---|---|
| PT-05 | Design observation | The first dust event is long: start ~58 h, peak at 180–233 h, end at 240 h (seed 99); others still running at 249 h. So no second, stronger event happened within 10 sols. The "minor then stronger" sequence is therefore shown only by `test_weather` on its fixture, not on the shipped data. | Medium (pacing) | Open: owner/balance review of episode stretch vs. campaign length; not changed (no evidence from people) |
| PT-06 | Design observation | Idle colony on starting settings: battery reaches 0 kWh within 12 sols (food 60, O2 ≥ 49.6 kg, water ≥ 898 L) and the storm is held back ("colony is not ready") so no event fires. A shortage with recovery is designed; recovery itself was verified by `test_session`/`test_weather`, not by this script. | Low | Open (by design; recorded) |

## Release-readiness decision

**Not release-ready as a validated product; technically ready for a first human playtest on the fixed build.**
- The one blocker found (PT-01, no weather in any real game) is fixed and verified on this copy; it must be merged
  into `mars_colony_godot` (same defect there).
- The ten-stage tutorial, certification and continued play complete with real actions at 1–4 players and on four
  seeds; hub rules hold.
- Limits that stay visible: no human/child testing (pilot targets unmeasured); pacing in real time unknown (I-58);
  visual, lighting, camera, voice and frame-time evidence not collected (headless); a second stronger storm not seen
  on shipped data within 10 sols (PT-05); rover builds/driving, offline refresh failure, cache retrieval and
  disconnect/rejoin evidenced only by existing suites, not by this playtest script; I-59 still open.
