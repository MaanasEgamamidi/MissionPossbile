# Worker P12 — tutorial, campaign certification, optional story (Prompt 12)

Copy: `G:\nasa app\_work\p12`. Date 2026-11-14. Headless tests and compile checks only; **nobody has played any of it**.
Detail: `docs_draft\TUTORIAL_GRAPH.md` (objective/learning graph, campaign rule, pacing log, story outline, gaps).

## 1. Files

New (mine):
- `scripts\sim\tutorial_system.gd` — `TutorialSystem` (post-system): stages, objective checks, credit of real actions,
  reminders, stage 9 fault injection and tracking, certification sol, story records/discoveries, pure text helpers
  (objective text per player count, mastery skip, hint count, specialist cue).
- `scripts\session\tutorial_actions.gd` — `TutorialActions`: `read_record` (record stations, important) and
  `tutorial_replay` (`{"stage": 0..10}`, reminder of a finished stage, 0 stops). Also wraps the `apply` of every watched
  action (`TutorialSystem.watched_actions()`: clean_panel, set_zone_power, plant, inspect_bed, exercise, refill_suit,
  inspect_donor, take_sample) so the tutorial sees them host-side; the wrapped action returns the same changes.
- `scripts\game\tutorial_presenter.gd` — `TutorialPresenter` (Node, `setup(world, services, game)`): tracker refresh 4 Hz,
  hint timer (real seconds, paused while the game is paused), H = hint, J = colony journal; `view()` is pure.
- `scripts\game\tutorial_hud.gd` — `TutorialHud` (HUD widget, right edge under the crew box, never over the corners,
  messages or crosshair; scrolls inside its box).
- `scripts\ui\story_log_panel.gd` — `StoryLogPanel` "Colony journal": current step, explanation, hints, "Answer the
  question here" (opens a QuizPanel where the question can be answered), reminders, campaign goal, the story.
- `scripts\ui\stations\record_station_panel.gd` — panel for kind `record`.
- `data\tutorial.json`, `data\lore.json`, `data\stations_lore.json` (7 record stations on existing consoles/boxes),
  `data\model_sources_campaign.json`, `tests\test_tutorial.gd`, `docs_draft\TUTORIAL_GRAPH.md`.

Shared (small edit): `scripts\session\session_service.gd` — two lines, exactly:
```gdscript
	# Prompt 12: tutorial, campaign and story. Registered last: it watches actions the parts above registered.
	TutorialActions.register(actions)
	...
	sim.post_systems.append(TutorialSystem.new())
```
(`TutorialActions.register` after `WeatherActions.register`; **keep it after every other `*Actions.register`**, including
P10A's `RoverActions.register`; `TutorialSystem` after `ProgressionSystem`; RoverSystem may come after it.)
`game_services.gd` was **not** changed: `state.campaign` is initialised lazily by the first tick (`TutorialSystem.ensure`).

## 2. Design decisions

- **Objectives come only from the real simulation.** State checks (positions/zones via `report_position`, suit, equipment,
  allocations, knowledge, `CommsStage.stage`) or real actions credited from inside their `apply`. No tutorial-only action
  completes an objective. `read_record` and `tutorial_replay` are story/reminder controls, not objective shortcuts.
- **Why wrap `apply` instead of listening to `action_resolved`:** `ActionResult` carries no action id for every part
  and the listener can only connect at the first tick; the wrapper is synchronous, has the actor and params, and its
  writes land in the same state the "important" save writes. No other worker's file is edited. `test_tutorial` checks
  every watched action is wrapped and that a wrapped action behaves the same.
- **Order:** stages in the supplied order; objectives in order; a real action of the current stage done early is
  credited when its step opens; actions from other stages never count. Repeating work never double-counts (stage
  records, evidence and knowledge are once-only). Reminders (`tutorial_replay`) tick their own copy and count nothing.
- **Player counts:** every step is one actor. Specialist steps say who; with 4 players `text_team`/`hints_team` and the cue
  never ask to switch (switching is disabled); with 1–3 players a switch cue appears only when nobody plays the needed
  specialist. Solo uses real hub switches (test: biology for the greenhouse, electrical for comms, field engineer at 10).
- **Hints/mastery:** hint after 75 real s without progress, then every 60 s, plus on request; explanations skipped when
  the question is known or the stage was done before in this colony.
- **Stage 9:** three real, harmless faults (Greenhouse circuit off; sun trackers off; shared lighting line overload with a
  fiction breaker that re-opens while room lights > 3.5 kW), chosen by `variant_for_seed(state.rng_seed)`, injected once
  (flag saved), solved at the power panel / greenhouse console, then held for 1 game hour.
- **Certification rule ("operate"):** every sector `ProgressionSystem.tier >= 1` and `CommsStage.stage >= 1`; then one
  full sol with battery, water, oxygen and food > 1e-6 and no `character_recovered`. A store at zero (checked each tick,
  after each watched action, and food at the end of the previous tick from the ledger) or a recovery restarts the sol
  (status `paused_reserve` while a store is empty); progress is never wiped; `complete` never reverts.
- **Story:** 12 records ≤ 60 words, 4 discoveries + final, hopeful (everyone went home safely), no remains/aliens/NPC/
  cutscene. 5 records on the existing salvage donors (found with `inspect_donor`), 7 on existing consoles/boxes (kind
  `record`). Fiction label on every record; real science linked by VERIFIED source ids (S01, S02, S08, S11, W10) or
  marked as a game rule / general principle. Discoveries in `state.discoveries`. Never required (test: milestone
  completes with 1 of 12 records).

## 3. Numbers and categories

All in `data\model_sources_campaign.json`: hint 75 s / 60 s (design), near 3 m, walk 8 m (design), greenhouse water
0.5 L/h (balance), suit 95 % (design), radio stage ≥ 1 (requirement), stage 9 hold 1 game hour (design), lighting line
3.5 kW (fiction), certification 1 sol = 24.6598 game h (requirement, S02), empty threshold 1e-6 (design), record numbers
(fiction), 3.73 m/s² (S01), 24 h 39 min (S02). Starting supplies and stored food are unchanged (test_life_support passes).

## 4. Test results: see section 7 at the end of this file

## 5. Limits

1. Nothing was played by a person; pacing (≈ 30–50 min tutorial, ≈ 1.2–2 h milestone) is an estimate.
2. Stage 8 in this copy uses `state.upgrades["comms_radio_1"]` set directly in the tests ("until P11 merges"). The test
   already tries the real path when the card exists (answers the card's questions at the comms console and installs);
   it prints a NOTE if the card's evidence is not earned by stages 1–7.
3. Arrival is still at the hub (C-09 not resolved): see request 4.
4. Hub = rehearsal Med Bay point; "hub monitoring" uses the Command Room colony computer.
5. H and J are fixed keys until PlayerInput has the actions (request 2). The tracker cannot be clicked (mouse captured);
   everything interactive is in the journal.
6. Four-player food: 96 meals last 8 sols for four; the tracker warns below three sols of food. Balance not changed.
7. The record stations' interaction points are the objects' origins (like every station); not checked in 3D.
8. Headless window: the HUD layout test runs at 1280×720 with content scaling disabled (as `test_station_panels`).

## 6. Requests for the executor

1. **game_main.gd** — in `GameMain._begin_play()`, after the HUD is set up (after `hud.setup(services)`; anywhere before
   `_apply_player_settings()` is fine), add exactly:
   ```gdscript
	# Prompt 12: tutorial tracker, hints, specialist cues and the colony journal (J).
	var tutorial := TutorialPresenter.new()
	tutorial.name = "TutorialPresenter"
	add_child(tutorial)
	tutorial.setup(world, services, self)
   ```
   (`_begin_play` runs once per play session; the presenter needs `self.hud` and `self.ui`.)
2. **scripts\player\player_input.gd** — add to the defaults dictionary `&"tutorial_hint": [KEY_H], &"journal": [KEY_J],`
   and to the labels `&"tutorial_hint": "Tutorial hint", &"journal": "Colony journal",` (the presenter uses these
   actions when they exist, otherwise H and J).
3. **scripts\game\game_hud.gd** — optional polish: in `_update_cue`, fall back to `StationPanels.name_of(station_kind).to_lower()`
   instead of `"station"` so record stations read "[E] Use old record".
4. **Owner decision (C-09 / PW-05):** to start at the landed spacecraft, `GameServices.start_new_game` would place the
   host's crew member by `ex_lander` (Exterior, ≈ (−29.1, 0, 30.5)), suited, before `session.begin`; then stage 1's
   second objective should be "reach the airlock" (`near` the outer door / tunnel) and stage 2 "cycle in and take the suit
   off". Not done here: it changes another part's file and the start for every player.
5. **After P11 merges:** in `tests\test_tutorial.gd`, `_install_radio` already uses the real card when it exists. Make sure
   `comms_radio_1`'s questions are answerable at `cm_comms_console` and its practical evidence is earned by stages 1–7
   (otherwise stage 8 cannot be finished in play); then delete the "until P11 merges" branch.
6. **After P10A merges:** confirm no object in `data\stations_lore.json` (`pr_fsp_console`, `sf_junction_box`,
   `gr_w_hab_screen`, `pr_panelboard`, `ak_terminal`, `mb_ct_console`, `cr_console.001`) became a donor in another
   stations file (`test_tutorial` fails if it did), and that `RoverActions.register` is before `TutorialActions.register`.
7. Requirements matrix: CP-01, CP-02 → implemented (headless); PW-05 stays pending (C-09).

## 7. Final run (2026-11-14, headless, in this copy)

`tools\run_tests.ps1 -Import -Tests test_tutorial,test_saves,test_session,test_game_services,test_progression,test_science,test_life_support,test_net,test_net_game,test_station_panels,test_food,test_weather,test_hud_panels`
→ import ok, **ALL TESTS PASSED**:

| Suite | Result |
|---|---|
| test_tutorial (new) | 59/59 |
| test_saves | 56/56 |
| test_session | 91/91 |
| test_game_services | 25/25 |
| test_progression | 84/84 |
| test_science | 76/76 |
| test_life_support | 88/88 |
| test_net | 34/34 |
| test_net_game | 20/20 |
| test_station_panels | 122/122 (was 108: +7 layout and +7 focus checks for the 7 new record-station panels; no check changed) |
| test_food | 85/85 |
| test_weather | 66/66 |
| test_hud_panels | 89/89 |

Compile check `tools/godot/check_compile.gd`: **COMPILE OK, 170 scripts**. No existing test was edited.
test_tutorial prints `NOTE comms_radio_1 set as installed directly (until P11 merges)`.
