# Prompt 15 — Feedback-to-fix matrix (from AGENT/TECHNICAL playtest one)

All "feedback" here is agent observation from `P14_PLAYTEST_ONE.md`; there was no human feedback.

| Playtest issue | Fix | Change (smallest correct) | Regression check | Before | After | Status |
|---|---|---|---|---|---|---|
| PT-01 shipped weather bundle rejected → no dust events in any fresh game | F-01 | `scripts\weather\weather_archive.gd`: new `COLUMN_RANGES := {"samples": [0.0, 100000.0]}`, checked before the unit range, so the count column is not held to the dimensionless-ratio range. The ratio range for real unit-"1" values (tau etc.) is unchanged; no data file changed; weather not disabled or weakened. | `tests\test_weather_data.gd`: "the game's WeatherArchive loader accepts the shipped bundle … so an offline boot uses it" | Check FAILS on the old loader (`docs_draft\regression_before_fix.txt`, 14/15); playtest one: source `builtin`, 0 events | 15/15; playtest two: source `shipped`, warned minor first event in every seed (see P16) | **Fixed, verified** |
| PT-02 seeds identical before the first storm | — | No change: caused by PT-01; re-measured in P16 | playtest script | identical runs | see P16 | Re-checked in P16 |
| PT-03 pacing not measurable headless | — | None (method limit) | — | — | — | Open: needs a human session (I-58) |
| PT-04 visual/performance not observable | — | None (method limit) | — | — | — | Open: needs a windowed run |
| I-59 suit-rack body thrown ~2.3 m | — | Not investigated: no time in this window | — | — | — | Open; workaround: re-run `test_game_scene` |

Notes
- Values: the only new value is a validator bound for a count column, kept beside the existing unit ranges in the
  same constant block (validator limits are code constants in this project, not game balance in `config`).
- Save impact: none. Saves pin `data_snapshot_id`; an old save made on the built-in default keeps its pinned sky
  (WeatherArchive behaviour unchanged); new games and loads pick the shipped bundle. No migration needed.
- Matching the main project: `mars_colony_godot\scripts\weather\weather_archive.gd` has the same code (diff empty
  before this fix), so the main project has the same defect until F-01 is merged.

## Repeat/transfer scenarios for Prompt 16

1. Same three solo seeds (4242, 7, 99) to certification, plus a changed seed 2027; continued play extended to 10
   sols so a second, stronger weather event can occur.
2. Same 2/3/4-crew tutorial and hub-rule runs.
3. Idle-colony storm/shortage run, seeds 4242 and 2027, 12 sols.
4. Rover: both builds via `test_rover` (custom 2/1/3/1/2 and the refit/cargo builds) and the driven route via
   `test_rover_drive`.
