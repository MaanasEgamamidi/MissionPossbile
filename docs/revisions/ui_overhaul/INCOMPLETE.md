# UI overhaul: what is not finished (2026-11-15)

The owner's goal ("UI Overhaul Prompt", `E:\Prompt`) is met: particles bigger and at chest height, the whole UI
reviewed and simplified, all ten repair mini-games rebuilt with their action titles, the rest of the interface
following the same rules. Everything is on `main`. This file lists what is left, how big each item is, and exactly
how to do it. `UI_OVERHAUL.md` is the full record; `AFTER_TOKENS_RESET.md` the short status.

Checked and already done (no action): T03's wider timing window (`t03_rule.gd` `ASSIST_WINDOW_DEG` 32 vs 20, the
"wide window" accessibility help); T11's fewer patches on the first run (added in the third session, see §0).

## Status (third session, after the merge with upgrade paths phase 1)

Done: §2 mid-game screenshots, §3 T02 locked badge, §4 lab and weather text, §5 upgrade cards (merged with phase 1:
the station strip is display-only, builds are chosen at the section's core spot), §6 T09 standing start, §7 "Water
splitter" / "CO2 splitter", §8 live pictogram sizes, §9 old tests updated to the switched-off features.
Still open: **§1 a real playthrough** (solo and with a second player), and a full test run on the merged `main`
(skipped at the owner's request). Small polish seen in screenshots: the wrong-socket cross reads small, and the locked
T02 screen names the role twice ("Electrical engineer only" and "Electrical and comms").

## Size at a glance

| # | Item | Size | Needs |
|---|---|---|---|
| 1 | Play the game end to end, solo and with a second player | 1-2 h of a person playing | A human (two machines or two windows) |
| 2 | Look at the mid-game states nobody has seen | 30-60 min | Screenshot runs + small capture-script additions |
| 3 | T02 wrong specialist: badge where the first plug would be | 1-2 h of coding | Panel + registry change, tests |
| 4 | Lab and weather station panels: cut the long text | 1-2 h | Writing + test updates |
| 5 | Upgrades strip on a station: five sentences per card | 1 h | Writing + `test_upgrade_ui` updates |
| 6 | T09: open the first puzzle with every tube standing | 30-60 min | Rule + panel + test change, design call |
| 7 | Life-support jargon ("Electrolyser", "CO2-oxygen unit") | 30 min | A decision first |
| 8 | Pictogram sizes follow the text-size setting live | 1 h | Code |
| 9 | Old failing tests (not caused by this work) | 30 min | A decision per feature |

None of this needs money or new art: every sprite exists. Nothing here blocks playing the game.

## 0. Done in the third session (for reference)

- Aim: a station inside a broken part's whole-model target (the Command Room tape in the T02 rack) wins the crosshair
  (`scripts/player/player_controller.gd` `_station_inside_part`, `PART_INNER_DEPTH_M`). `test_repair_anchors` 116/116.
- `test_game_scene` suit-rack approach retries free spots until the player stands still on the floor. 34/34.
- T11 first run: the middle column (`back_middle`, `front_middle`) starts clean, so the first repair is four
  patches (`t11_rule.gd` `FIRST_RUN_CLEAN`, `is_first_run`); later breakdowns are all six. 59/59.

## 1. Play it end to end (most important)

Everything was checked by automated tests and screenshots, never by a person playing.

1. Start a new game from the main menu. Follow the tape guide lines (gold sparkles at chest height) to each tape.
2. Do every repair once as the right specialist: T01 Lock the Relay, T02 Patch the Relay, T03 Sync the Turbine,
   T04 Light the Power Bench, T06 Water the Kale, T08 Glaze the Dome, T09 Sort the Lab Samples, T10 Revive the Med
   Bay, T11 Clear the Landing Lines, T12 Seal the Airlock. For each, note: did you know what to do without pressing
   "?"; did the mouse work on the equipment; does the keyboard alone finish it (Tab/arrows + Enter); did the panel
   close itself with the tick and the sparkle burst show in the world.
3. Open one repair as the wrong specialist: the padlock screen must show and no move must be possible.
4. Open every station (E): bed, cargo, cassette player, colony computer, garage, gym, lab, weather, workbench,
   drone pad, scout bay, salvage, ore deposit, rover charger, food, upgrade console, power, solar, life support.
   Look for leftover long text or developer words.
5. Let a supply run low (sleep / skip time) and check the HUD shows a number plus a mark only on that supply.
6. Settings: text size large, high contrast on, less motion on. Repeat steps 2 and 4 quickly.
7. Second player: host + join (Play with friends). Both open the same repair; moves from one must show on the
   other; a wrong specialist on the second machine must be refused by the host.

Write what was confusing into a list; each item is usually a one-line cue or a size tweak.

## 2. Mid-game states nobody has looked at

Add a capture step to the solver of each game in `tools/godot/capture_puzzles.gd` (they already save
`TNN_start/solved/stamp.png`; add a `_shot("TNN_mid")` at the right point), then run
`timeout 300 "$G" --path . --script res://tools/godot/capture_puzzles.gd -- --out <dir> --only TNN` and look:

- T02 / T10: a plug held (picked, not yet seated), and a plug pushed into the wrong socket (the shake and amber
  cross).
- T04: the path joined to the lamp at the wrong voltage (meter shows booster / reducer icon, lamp stays off).
- The Power & life support drawer (P) with messages in its Messages list.
- The "B Build here" chip on the HUD.

## 3. T02 wrong specialist: badge on the first plug

Concept (prompt line 136): "Show the electrical specialist badge where the first plug would be if the player needs
to switch crew." Today every wrong-specialist repair opens the plain shell (`TaskPanel.new()` in
`scripts/tasks/puzzle_registry.gd` `make_panel`, lines ~74-82), which draws a padlock, the specialist's symbol and
name. It reads fine; this is polish.

How:
1. In `make_panel`, for a non-readable task whose panel script declares it can draw a locked view (e.g. a
   `static func supports_locked_view() -> bool` on `t02_panel.gd`), instantiate the real panel and call
   `panel.set_locked(true)` before `configure_task`, instead of `TaskPanel.new()`.
2. In `t02_panel.gd`, `set_locked(true)`: draw the patch bay dimmed, no plugs, and at the first plug's position draw
   the electrical badge (`Kit.lock` + the specialist symbol; the shell has the symbol helper it uses in its own
   locked view) with a target ring; set the cue to "Electrical engineer only". Disable every plug/socket button
   (`disabled = true`, `focus_mode = FOCUS_NONE`) and never call the base script's move sender while locked.
3. Tests: in `tests/test_puzzle_t02.gd` add a wrong-specialist UI check: the panel is the T02 panel, every button is
   disabled, sending is impossible, and the host still answers `wrong_specialty` (the existing checks at lines 164 and
   172 must keep passing). `tests/test_task_panel.gd` must stay green (the shell's own locked view is still used by
   the other nine games).
4. Screenshot `T02_wrong_specialist.png` (the capture script already supports it) and look.

## 4. Lab and weather station panels: long text

Files: `scripts/ui/stations/lab_station_panel.gd`, `scripts/ui/stations/weather_station_panel.gd`. They have the
new frame (`station_kit.gd`) but still show paragraphs. Apply the rules from `UI_OVERHAUL.md` §3: one obvious
action, states not numbers (bar + icon, number only when it matters), six words or fewer for standing lines,
explanations behind a "?" or in a tooltip. Use `scripts/ui/stations/bed_station_panel.gd` or
`food_station_panel.gd` as the finished pattern. Run `tests/test_station_panels.gd` and `tests/test_science.gd`
/ `tests/test_weather.gd`; update assertions that pin old sentences, never ones about state. Capture with
`tools/godot/capture_stations.gd` (read its header for arguments) and look at 1280x720 and with large text.

## 5. Upgrades strip on a station

The upgrade cards on a station surface still carry about five sentences each. `tests/test_upgrade_ui.gd` pins some
of that text (e.g. line 236 `"Now: V2: Two-layer rack with LED bars"`, line 203 the button text). Cut each card to:
name, a picture or icon, one line of what it adds, the cost as icons, the button. Move the rest to the card's
tooltip. Update the pinned strings in the test to the new short lines (keep the checks on cost, greyed-out
button and the reason it is greyed).

## 6. T09: first puzzle with every tube standing

Concept (prompt line 179): "Try opening with the tubes already standing for a shorter first puzzle." Today
`scripts/tasks/puzzles/t09_rule.gd` has `FALLEN_TUBES := 1` for every run (the second session's choice, already
shorter than the old 3). To finish it the same way as T11:
1. In the rule, give the start generator a `first_run` flag (true while `not task.first_completed`), and on the
   first run start with 0 fallen tubes; keep 1 for later breakdowns. Make the saved-state check accept both.
2. In `t09_panel.gd`, when nothing is fallen, skip the "Stand the tubes up" cue and go straight to the pour cue;
   hide the mat.
3. `tests/test_puzzle_t09.gd`: the 60-seed check at lines ~121-126 compares `fallen != Rule.FALLEN_TUBES`; split
   it into first-run (0) and later (1). The "rack a fallen tube" checks (lines ~131-139) need a task with
   `first_completed: true`.
This is a design call: standing up a tube teaches the rack. If the first puzzle already feels short in play
(item 1), skip this.

## 7. Life-support words

`scripts/sim/power_model.gd` `LABELS` / `SHED_TEXT` and `scripts/session/system_actions.gd` use "Electrolyser" and
"CO2-oxygen unit". They are real Mars life-support terms (it is a NASA learning game), and `tests/test_life_support.gd`
(line ~594) and `tests/test_p07_panels.gd` (line ~349) pin them. Decide: keep (with a one-line tooltip explaining
each) or rename (e.g. "Water-to-oxygen machine", "Air-to-oxygen machine") and update those tests.

## 8. Pictogram sizes and the text-size setting

On the information panels, text and bars follow the text-size setting live, but pictograms are sized once when the
panel opens. Fix: in the panels that draw pictograms with a fixed `custom_minimum_size`, recompute it in the handler
that already reacts to the text-size change (search `text_size` in `scripts/ui/game_settings.gd` for the signal)
and `queue_redraw()`. The Mission Control card and the bottom dock were reworked in the second session; check
whether they now follow the text-size setting (they used the old `AstraStyle`, which did not).

## 9. Old failing tests (not caused by the overhaul)

| Suite | Failing check | Why |
|---|---|---|
| `test_ui_framework` (2), `test_station_panels` (1) | M key opens / closes the blueprint; computer buttons include Blueprint | Blueprint switched off by the owner in `301d499` |
| `test_tutorial` (1) | tutorial widget presentation | widget switched off at `72070d4` |
| `test_scout` (1) | scout goals | scout goals switched off at `72070d4` |
| `test_broken_parts` (1) | "transition ends after about 1 s, glow removed" (T02 repair glow) | timing; was failing in the first health run before any overhaul change |

When each feature's future is decided, update or delete those assertions. For the glow check, find the transition
length in `scripts/tasks/broken_part_presenter.gd` and either make the test run long enough or end the glow on time.

## How to run things (this machine)

```
G="/c/Users/megam/Downloads/Godot Installs/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
timeout 900 "$G" --headless --path . --script res://tests/<suite>.gd 2>&1 | grep -E "^FAIL|^RESULT|SCRIPT ERROR"
timeout 300 "$G" --path . --script res://tools/godot/capture_puzzles.gd -- --out <dir> --only T02
```
